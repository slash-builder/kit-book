/// The notepad's meaning of "peers": every copy keeps the same set of notes. Pure Dart (no Flutter).
///
/// ## What the Kit gives, and what this file is
/// The Kit carries small opaque messages between copies that are connected right now. It has no store, no merge, no large
/// transfer, no acknowledgement and no replay. All of that is here:
///
///  * **Source of truth = the note files.** This engine never keeps notes; it asks the [NoteHost] (the controller, which owns
///    the files). Its own state is a sidecar `sync.json` of per-note metadata (version vector, tombstone, content hash) that can
///    be thrown away: the worst case is spurious "conflict" copies, never a lost note.
///  * **Version vectors, not timestamps**, to tell "behind" from "both edited".
///  * **A concurrent edit is a CONFLICT and the app resolves it visibly.** Both versions survive: the one that sorts later
///    (`updatedAt`, then device) keeps the note's title and place, the other becomes a NEW note titled
///    `<title> (conflict from <device>)`. Both copies compute the same winner and the same id for the new note, so they converge
///    without talking, and the banner says what happened. Last-writer-wins would be a one-line rule but it would delete one
///    person's text with no trace, on a clock that may be wrong. Edit beats delete (a delete never destroys a concurrent edit).
///  * **Pull, not push, for content.** Small `sync.have` messages say "note X is at version V". A copy that is behind PULLS with
///    a request/reply (`sync.get`), one part at a time. A pull is the only way to get an acknowledgement and a retry out of a
///    transport that has neither, and it makes large notes (over the 64 KiB Hearth payload limit) the same code path as small
///    ones: [partBytes] per reply, reassembled, bounded by [maxNoteBytes], restarted if the sender's version changes mid-way.
///  * **Late joiner:** the hello carries only a digest (a constant 100 bytes however many notes there are; a full index in the
///    hello would hit the payload limit at about 600 notes). If digests differ, each side sends its index as pages of `have`s and
///    the side that is behind pulls. A periodic `sync.digest` (also the liveness beat a real transport needs) repairs a lost
///    message, because the Kit never replays one.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:application_kit/application_kit.dart';

import '../kit_gaps/blob_pull.dart';
import '../logic/note.dart';
import 'version_vector.dart';

/// What the engine needs from the app. The controller implements it; tests implement it with a map.
abstract interface class NoteHost {
  /// The notes that loaded fine, newest first.
  List<Note> get notes;
  Note? note(String id);

  /// A file with this id exists but could not be read. The engine never writes over it.
  bool isDamaged(String id);

  /// Commit any unsaved edit of [id] now, so its version is recorded before it is compared with a remote one.
  void flushNote(String id);

  /// Write [note] (new or replacing) and show it. Must NOT call back into the engine. May throw FileSystemException.
  void applyRemote(Note note);
  void removeRemote(String id);
}

/// Per-note sync metadata, kept in `sync.json` beside the notes directory.
class Meta {
  Meta(this.vv, {this.deleted = false, required this.by, this.hash = '', this.big = false});
  Vv vv;
  bool deleted;

  /// The device that wrote this version (needed to name a conflict copy and to break ties the same way on both sides).
  String by;

  /// Hash of title+body when [vv] was last updated: a different hash at start-up means the file was edited outside the app.
  String hash;

  /// Too large to sync: kept on this copy only and left out of digests and indexes.
  bool big;

  Map<String, Object?> toJson() => {'vv': vv.toJson(), 'del': deleted, 'by': by, 'h': hash, 'big': big};

  static Meta? parse(Object? j) {
    if (j is! Map) return null;
    final vv = Vv.parse(j['vv']), by = j['by'], h = j['h'];
    if (vv == null || by is! String || by.isEmpty || by.length > 64) return null;
    return Meta(vv, deleted: j['del'] == true, by: by, hash: h is String && h.length <= 64 ? h : '', big: j['big'] == true);
  }
}

String hash64(String s) {
  var a = 0x811c9dc5, b = 0x9dc5bd1e;
  for (final c in utf8.encode(s)) {
    a = ((a ^ c) * 0x01000193) & 0xffffffff;
    b = ((b ^ c) * 0x85ebca6b) & 0xffffffff;
  }
  return a.toRadixString(16).padLeft(8, '0') + b.toRadixString(16).padLeft(8, '0');
}

String hashNote(Note n) => hash64('${n.title}\u0000${n.body}');

class _Want {
  _Want(this.peer, this.id, this.vv);
  final PeerId peer;
  final String id;
  final Vv vv;
}

class NoteSync {
  NoteSync({
    required this.device,
    required this.host,
    required this.sidecar,
    required this.report,
    this.partBytes = 24 * 1024,
    this.maxNoteBytes = 2 * 1024 * 1024,
    this.heartbeat = const Duration(seconds: 30),
    this.pullTimeout = const Duration(seconds: 5),
  });

  final String device;
  final NoteHost host;
  final AppJsonFile sidecar;

  /// Tells the person something (the app wires it to the notice banner).
  final void Function(String message) report;

  /// Raw bytes of note JSON per reply. Base64 (x1.34) inside the Kit envelope's own base64 (x1.34) must stay under the 64 KiB
  /// Hearth payload limit: 24 KiB raw becomes about 58 KB on the wire.
  final int partBytes;
  final int maxNoteBytes;
  final Duration heartbeat;
  final Duration pullTimeout;

  PeerHub? hub;
  final Map<String, Meta> meta = {};
  final _wants = Queue<_Want>();
  var _pumping = false;
  Timer? _beat;
  final _indexSentAt = <PeerId, DateTime>{};
  final _reported = <String>{};
  final _changes = StreamController<void>.broadcast();

  /// Counters for tests and diagnostics.
  int ignored = 0, conflicts = 0, pulled = 0, partsPulled = 0;

  /// Fires after the engine applied or recorded something.
  Stream<void> get changes => _changes.stream;
  int get pending => _wants.length + (_pumping ? 1 : 0);

  // ------------------------------------------------------------------ start-up

  /// Reads the sidecar and reconciles it with the files. Safe to call with no hub.
  void load() {
    final r = sidecar.read();
    if (r.exists && !r.ok) {
      final moved = sidecar.quarantine();
      report('Sync information was damaged and set aside as ${moved.path}. Notes are untouched; the next sync may show conflict copies.');
    } else if (r.ok && r.value is Map && (r.value as Map)['notes'] is Map) {
      for (final e in ((r.value as Map)['notes'] as Map).entries) {
        final m = Meta.parse(e.value);
        if (e.key is String && Note.idPattern.hasMatch(e.key as String) && m != null) meta[e.key as String] = m;
      }
    }
    for (final n in host.notes) {
      final m = meta[n.id];
      if (m == null) {
        meta[n.id] = Meta(Vv.empty.bump(device), by: device, hash: hashNote(n));
      } else if (m.deleted || m.hash != hashNote(n)) {
        // the file is there but the record says deleted, or it changed while the app was closed: either way it is a local edit
        meta[n.id] = Meta(m.vv.bump(device), by: device, hash: hashNote(n));
      }
    }
    for (final e in meta.entries.toList()) {
      if (!e.value.deleted && host.note(e.key) == null && !host.isDamaged(e.key)) {
        meta[e.key] = Meta(e.value.vv.bump(device), deleted: true, by: device); // the file was removed outside the app
      }
    }
    _save();
  }

  void _save() {
    try {
      sidecar.write({'v': 1, 'notes': {for (final e in meta.entries) e.key: e.value.toJson()}});
    } on FileSystemException catch (e) {
      report('Could not save sync information: ${e.message}');
    }
  }

  void attach(PeerHub h) {
    hub = h;
    if (heartbeat > Duration.zero) {
      _beat = Timer.periodic(heartbeat, (_) {
        final h = hub;
        if (h != null && h.readyPeers.isNotEmpty) PeerJson.quiet(h.broadcast(PeerJson.encode({'digest': digest(), 'count': _syncable().length}), kind: 'sync.digest', schema: 1));
      });
    }
  }

  void dispose() {
    _beat?.cancel();
    _changes.close();
  }

  // ------------------------------------------------------------------ what the hook asks for

  Iterable<MapEntry<String, Meta>> _syncable() => meta.entries.where((e) => !e.value.big);

  /// A short fingerprint of every syncable note's id, version and tombstone.
  String digest() => hash64((_syncable().map((e) => '${e.key}|${e.value.vv.canon}|${e.value.deleted}').toList()..sort()).join('\n'));

  Object hello() => {'proto': 1, 'digest': digest(), 'count': _syncable().length};

  /// Rejects a peer that speaks another notes protocol, whose hello is not shaped like ours, or that is on THIS device: two
  /// copies with one device id (the default on one machine) share one notes directory and one `sync.json`, so they are one
  /// replica, not two. Syncing them would have both bump the same counter and trust a metadata file both are rewriting.
  Admit admit(Peer peer, Object? theirs) {
    if (theirs is! Map || theirs['proto'] != 1 || theirs['digest'] is! String) return const Admit.reject('notes protocol 1 only');
    if (peer.id.device == device) return const Admit.reject('same device: this copy shares its notes folder');
    return const Admit.accept();
  }

  void ready(Peer peer) {
    final t = peer.hello;
    if (t is Map && t['digest'] == digest()) return; // already identical: nothing to say
    sendIndex(peer);
  }

  // ------------------------------------------------------------------ local changes

  void localSaved(Note n) {
    final m = meta[n.id], h = hashNote(n);
    if (m != null && !m.deleted && m.hash == h) return;
    final size = utf8.encode(jsonEncode(n.toJson())).length;
    final big = size > maxNoteBytes;
    meta[n.id] = Meta((m?.vv ?? Vv.empty).bump(device), by: device, hash: h, big: big);
    _save();
    if (big) {
      report('"${n.title}" is ${(size / 1048576).toStringAsFixed(1)} MB; notes over ${(maxNoteBytes / 1048576).toStringAsFixed(0)} MB are not synced. It stays on this copy only.');
    } else {
      _announce([n.id]);
    }
  }

  void localDeleted(String id) {
    final m = meta[id];
    if (m == null) return;
    meta[id] = Meta(m.vv.bump(device), deleted: true, by: device, big: m.big);
    _save();
    if (!m.big) _announce([id]);
  }

  // ------------------------------------------------------------------ messages

  Map<String, Object?> _entry(String id, Meta m) => {'id': id, 'vv': m.vv.toJson(), 'del': m.deleted, 'by': m.by};

  void _announce(List<String> ids) {
    final h = hub;
    if (h == null) return;
    final entries = [for (final id in ids) if (meta[id] != null && !meta[id]!.big) _entry(id, meta[id]!)];
    if (entries.isNotEmpty) PeerJson.quiet(h.broadcast(PeerJson.encode({'entries': entries}), kind: 'sync.have', schema: 1));
    if (!_changes.isClosed) _changes.add(null);
  }

  /// The whole index as `have` pages that each fit well inside one message.
  void sendIndex(Peer peer) {
    final h = hub;
    if (h == null) return;
    _indexSentAt[peer.id] = DateTime.now();
    var page = <Map<String, Object?>>[];
    var size = 0;
    void flush() {
      if (page.isEmpty) return;
      PeerJson.quiet(h.send(peer, PeerJson.encode({'entries': page}), kind: 'sync.have', schema: 1));
      page = [];
      size = 0;
    }

    for (final e in _syncable()) {
      final entry = _entry(e.key, e.value);
      final len = jsonEncode(entry).length;
      if (size + len > 16 * 1024) flush();
      page.add(entry);
      size += len;
    }
    flush();
  }

  void onMessage(Peer from, AppMessage m) {
    if (m.schema != 1) return _bad();
    final j = m.jsonBody;
    switch (m.kind) {
      case 'sync.have':
        final list = j is Map ? j['entries'] : null;
        if (list is! List || list.length > 500) return _bad();
        for (final e in list) {
          _consider(from, e);
        }
      case 'sync.digest':
        if (j is! Map || j['digest'] is! String) return _bad();
        final last = _indexSentAt[from.id];
        if (j['digest'] != digest() && (last == null || DateTime.now().difference(last) > const Duration(seconds: 5))) sendIndex(from);
      case 'sync.get':
        if (m.requestId == null || j is! Map) return _bad();
        _serve(m, j);
      default:
        ignored++;
    }
  }

  void _consider(Peer from, Object? raw) {
    if (raw is! Map) return _bad();
    final id = raw['id'], vv = Vv.parse(raw['vv']), by = raw['by'], del = raw['del'];
    if (id is! String || !Note.idPattern.hasMatch(id) || vv == null || by is! String || by.isEmpty || by.length > 64 || del is! bool) return _bad();
    if (host.isDamaged(id)) {
      if (_reported.add('damaged:$id')) report('A synced note ($id.json) was not applied because a damaged file with that name is on this copy. The file was left alone.');
      return;
    }
    var local = meta[id];
    if (local != null && local.vv.compare(vv) != VvOrder.equal) {
      host.flushNote(id); // an unsaved keystroke is an edit: record it first, so it counts as concurrent, not as overwritten
      local = meta[id];
    }
    final order = local == null ? VvOrder.before : local.vv.compare(vv);
    switch (order) {
      case VvOrder.equal:
        return;
      case VvOrder.after:
        // I am ahead: say so, and the other side will pull (this is "whoever is ahead pushes", one message at a time)
        PeerJson.quiet(hub!.send(from, PeerJson.encode({'entries': [_entry(id, local!)]}), kind: 'sync.have', schema: 1));
      case VvOrder.before:
        if (del) {
          _applyDelete(id, vv, by);
        } else {
          _want(from, id, vv);
        }
      case VvOrder.concurrent:
        if (del && !local!.deleted) {
          // edit beats delete: keep my note, record that I have seen the delete, and tell everyone
          meta[id] = Meta(local.vv.join(vv), by: local.by, hash: local.hash);
          _save();
          _announce([id]);
        } else if (del) {
          meta[id] = Meta(local!.vv.join(vv), deleted: true, by: local.by);
          _save();
        } else {
          _want(from, id, vv);
        }
    }
  }

  void _bad() => ignored++;

  void _applyDelete(String id, Vv vv, String by) {
    try {
      if (host.note(id) != null) host.removeRemote(id);
    } on FileSystemException catch (e) {
      return report('Could not remove a note deleted on another copy: ${e.message}');
    }
    meta[id] = Meta(vv, deleted: true, by: by);
    _save();
    _announce([id]);
  }

  // ------------------------------------------------------------------ pulling

  void _want(Peer from, String id, Vv vv) {
    if (_wants.any((w) => w.peer == from.id && w.id == id)) return;
    _wants.add(_Want(from.id, id, vv));
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_wants.isNotEmpty) {
        final w = _wants.removeFirst();
        try {
          await _pull(w);
        } on PeerError {
          // lost, timed out or refused: the next index or digest asks again; there is nothing more useful to do here
        } catch (_) {
          ignored++; // a hostile reply that got past the checks must not stop the queue
        }
      }
    } finally {
      _pumping = false;
      if (!_changes.isClosed) _changes.add(null);
    }
  }

  Future<void> _pull(_Want w) async {
    final h = hub;
    final peer = h?.readyPeers.where((p) => p.id == w.peer).firstOrNull;
    if (h == null || peer == null) return;
    final PulledBlob? blob;
    try {
      blob = await pullBlob(h, peer, kind: 'sync.get', key: {'id': w.id}, maxBytes: maxNoteBytes, partBytes: partBytes, timeout: pullTimeout, onPart: () => partsPulled++);
    } on FormatException {
      return _bad();
    }
    if (blob == null) return; // gone, too large, or edited under us three times: the next index or digest asks again
    final tag = blob.tag;
    final vv = tag is Map ? Vv.parse(tag['vv']) : null, by = tag is Map ? tag['by'] : null;
    final Note note;
    try {
      note = Note.fromJson(jsonDecode(utf8.decode(blob.bytes)));
    } on FormatException {
      return _bad();
    }
    if (vv == null || by is! String || by.isEmpty || by.length > 64 || note.id != w.id) return _bad();
    pulled++;
    _applyRemote(note, vv, by);
  }

  void _serve(AppMessage m, Map j) {
    final id = j['id'], part = j['part'];
    final h = hub;
    if (h == null || id is! String || part is! int || part < 0) return _bad();
    Map<String, Object?> answer() {
      final mt = meta[id], n = host.note(id);
      if (mt == null || mt.deleted || n == null) return {'ok': false, 'reason': 'gone'};
      if (mt.big) return {'ok': false, 'reason': 'too-large'};
      return blobPartReply(
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(n.toJson()))),
          part: part,
          partBytes: partBytes,
          tag: {'vv': mt.vv.toJson(), 'by': mt.by},
          wantTag: j['tag']);
    }

    host.flushNote(id); // serve what the person sees, not the file from before the last keystrokes
    PeerJson.quiet(h.reply(m, PeerJson.encode(answer()), schema: 1));
  }

  // ------------------------------------------------------------------ applying a remote note

  void _applyRemote(Note remote, Vv rvv, String rby) {
    final id = remote.id;
    if (host.isDamaged(id)) return;
    host.flushNote(id);
    final local = meta[id];
    final order = local == null ? VvOrder.before : local.vv.compare(rvv);
    try {
      switch (order) {
        case VvOrder.equal || VvOrder.after:
          return;
        case VvOrder.before:
          _put(remote, rvv, rby);
        case VvOrder.concurrent:
          final mine = host.note(id);
          if (local!.deleted || mine == null) {
            _put(remote, local.vv.join(rvv), rby); // edit beats delete
          } else if (hashNote(mine) == hashNote(remote)) {
            meta[id] = Meta(local.vv.join(rvv), by: local.by, hash: local.hash); // same text on both: only the histories merge
            _save();
            _announce([id]);
          } else {
            _conflict(mine, local, remote, rvv, rby);
          }
      }
    } on FileSystemException catch (e) {
      report('Could not store a synced note: ${e.message}. It will be tried again at the next sync.');
    }
  }

  void _put(Note n, Vv vv, String by) {
    host.applyRemote(n);
    meta[n.id] = Meta(vv, by: by, hash: hashNote(n));
    _save();
    _announce([n.id]);
  }

  /// Does A sort after B? Symmetric and total, so both copies pick the same winner with no conversation.
  bool _beats(Note a, String aBy, Note b, String bBy) {
    final t = a.updatedAt.compareTo(b.updatedAt);
    if (t != 0) return t > 0;
    final d = aBy.compareTo(bBy);
    return d != 0 ? d > 0 : hashNote(a).compareTo(hashNote(b)) > 0;
  }

  void _conflict(Note mine, Meta lm, Note theirs, Vv rvv, String rby) {
    conflicts++;
    final iWin = _beats(mine, lm.by, theirs, rby);
    final winner = iWin ? mine : theirs, loser = iWin ? theirs : mine;
    final winBy = iWin ? lm.by : rby, loseBy = iWin ? rby : lm.by;
    if (!iWin) host.applyRemote(theirs);
    meta[winner.id] = Meta(lm.vv.join(rvv), by: winBy, hash: hashNote(winner));
    // The loser survives as a new note. Its id is a function of the note id and the loser's content, so the other copy, which
    // reaches this same decision on its own, makes the same note instead of a second one.
    final cid = 'cf${hash64('${winner.id}|$loseBy|${loser.updatedAt.toUtc().toIso8601String()}|${hashNote(loser)}')}';
    final copy = Note(
        id: cid,
        title: '${loser.title} (conflict from $loseBy)',
        body: loser.body,
        createdAt: loser.createdAt,
        updatedAt: loser.updatedAt);
    if (meta[cid] == null && !host.isDamaged(cid)) {
      host.applyRemote(copy);
      meta[cid] = Meta(Vv({loseBy: 1}), by: loseBy, hash: hashNote(copy));
    }
    _save();
    _announce([winner.id, cid]);
    report('"${winner.title}" was edited on $winBy and on $loseBy at the same time. Both versions are kept: the other one is "${copy.title}".');
  }
}
