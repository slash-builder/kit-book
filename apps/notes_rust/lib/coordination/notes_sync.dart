/// The transport half of sync. The Rust core holds the blocks and does every check that needs them (`missingBlocks`,
/// `exportBlocks`, `importBlocks` with hash verification, `applyHeads`, conflicts); this file only carries bytes over the
/// App Context Kit's peer layer and applies the app's policy. Pure Dart (no Flutter).
///
/// ## The protocol
///  * **hello** carries the core's heads digest (one hash of every note's head). Equal digests: nothing to do.
///  * **On ready**, a side whose digest differs sends its heads (`notes.heads`, in pages). Whoever receives heads it lacks asks
///    for the blocks, the other side exports them, the receiver imports (the core verifies every hash) and then applies the
///    heads. Both sides do this, so "whoever lacks asks" needs no one to decide who is ahead.
///  * **Asking** is a pull: `notes.get` is a request/reply for a list of block hashes, answered in numbered parts
///    (`kit_gaps/blob_pull.dart`), because request/reply is the only reliable primitive the Kit has. The receiver asks again
///    after each import, because a list node's children are only known once the list node is here (manifest, then list
///    node, then chunks: three rounds for a note that changed).
///  * **Part size is 24 KiB**, as in the notepad. The Hearth-compatible payload is 64 KiB minus the Kit header. A part's bytes
///    go into JSON as base64 (x4/3, so 24 KiB becomes 32 KiB of text) and the Kit's own envelope base64-encodes the payload
///    again (x4/3, 43.7 KB on the wire), which leaves about 20 KB under the limit for the header and the reply fields. 32 KiB
///    parts would land at 58 KB, too close to the cap for no gain a person could see. A single block can be up to 64 KiB, so a
///    block is routinely sent in more than one part; the receiver reassembles the whole export before it verifies anything.
///  * **Conflicts** (both copies edited a note) come back from the core with both versions. The policy here is the notepad's:
///    the later edit keeps the note, the other becomes "title (conflict from device)", both copies choose the same winner
///    from the same data, so they converge without talking. An edit beats a delete.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:app_context_kit/app_context_kit.dart';

import '../core/notes_core.dart';
import '../kit_gaps/blob_pull.dart';

/// What the sync engine needs from the app (the controller implements it; tests implement it with nothing).
abstract interface class NotesHost {
  /// Save anything unsaved now, so the typed text is a recorded version before it is compared with a remote one.
  Future<void> flushAll();

  /// Notes changed in the core behind the screen's back (a synced note arrived or was resolved). Reload them.
  void remoteChanged(List<String> ids);
}

class NoHost implements NotesHost {
  const NoHost();
  @override
  Future<void> flushAll() async {}
  @override
  void remoteChanged(List<String> ids) {}
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');
final _noteId = RegExp(r'^[a-z0-9]{4,40}$');

/// Which side keeps the note: the same answer on both copies (they swap local and remote, nothing else). An edit beats a
/// delete; otherwise the later edit; then the device name; then the address.
Side conflictWinner(Conflict c) {
  if (c.local.deleted != c.remote.deleted) return c.local.deleted ? Side.remote : Side.local;
  final t = c.local.atMs.compareTo(c.remote.atMs);
  if (t != 0) return t > 0 ? Side.local : Side.remote;
  final d = c.local.by.compareTo(c.remote.by);
  if (d != 0) return d > 0 ? Side.local : Side.remote;
  return c.local.manifest.compareTo(c.remote.manifest) > 0 ? Side.local : Side.remote;
}

class NotesSync {
  NotesSync({
    required this.core,
    required this.device,
    this.host = const NoHost(),
    required this.report,
    this.partBytes = 24 * 1024,
    this.fetchBatch = 32,
    this.heartbeat = const Duration(seconds: 30),
    this.pullTimeout = const Duration(seconds: 10),
    this.serveTransform,
  });

  final NotesCore core;
  final String device;
  final NotesHost host;

  /// Tells the person something (the app wires it to the notice banner).
  final void Function(String message) report;

  /// Raw bytes of an export per reply. See the library comment for the arithmetic.
  final int partBytes;

  /// Hashes asked for in one pull. Small enough that an export stays near 0.6 MiB (a block is at most 64 KiB).
  final int fetchBatch;
  final Duration heartbeat;
  final Duration pullTimeout;

  /// Test seam: changes an export just before it is cut into parts and served (a tampering peer).
  Uint8List Function(Uint8List export)? serveTransform;

  PeerHub? hub;
  String _digest = '';
  Timer? _beat;
  Future<void> _tail = Future<void>.value();
  var _pending = 0;
  final _digestSentAt = <PeerId, DateTime>{};
  final _exports = <String, Uint8List>{};
  final _changes = StreamController<void>.broadcast();

  /// Counters for tests and diagnostics.
  int ignored = 0, refused = 0, conflicts = 0, blocksStored = 0, bytesPulled = 0, partsPulled = 0, stalled = 0;

  Stream<void> get changes => _changes.stream;
  int get pending => _pending;

  /// Reads the core's digest. Must complete before the hub starts: the hook's `hello()` is synchronous and the core is not,
  /// so the digest is cached here and refreshed after every change.
  Future<void> init() async => _digest = await core.headsDigest();

  Future<void> _refreshDigest() async => _digest = await core.headsDigest();

  void attach(PeerHub h) {
    hub = h;
    if (heartbeat > Duration.zero) {
      _beat = Timer.periodic(heartbeat, (_) {
        final h = hub;
        if (h != null && h.readyPeers.isNotEmpty) PeerJson.quiet(h.broadcast(PeerJson.encode({'digest': _digest}), kind: 'notes.digest', schema: 1));
      });
    }
  }

  void dispose() {
    _beat?.cancel();
    _changes.close();
  }

  // ------------------------------------------------------------------ what the hook asks for

  Object hello() => {'proto': 1, 'digest': _digest};

  /// Rejects a peer that speaks another protocol or is on THIS device: two copies with one device id share one data directory
  /// and one block store, so they are one replica, not two.
  Admit admit(Peer peer, Object? theirs) {
    if (theirs is! Map || theirs['proto'] != 1 || theirs['digest'] is! String) return const Admit.reject('notes protocol 1 only');
    if (peer.id.device == device) return const Admit.reject('same device: this copy shares its notes folder');
    return const Admit.accept();
  }

  void ready(Peer peer) {
    final t = peer.hello;
    if (t is Map && t['digest'] == _digest) return; // already identical
    _sendHeads(peer);
  }

  // ------------------------------------------------------------------ local changes

  /// A note was changed by the person. Tell the other copies where it is now.
  Future<void> localChanged(List<String> ids) async {
    await _refreshDigest();
    final h = hub;
    if (h == null) return;
    final all = await core.heads();
    final entries = [for (final e in all) if (ids.contains(e.id)) e];
    _announce(entries);
  }

  void _announce(List<HeadEntry> entries) {
    final h = hub;
    if (h == null || entries.isEmpty) return;
    for (final page in _pages(entries)) {
      PeerJson.quiet(h.broadcast(PeerJson.encode({'heads': page}), kind: 'notes.heads', schema: 1));
    }
  }

  List<List<Map<String, Object?>>> _pages(List<HeadEntry> entries) {
    const perPage = 150; // about 110 bytes each: 16 KB, far inside one message
    return [
      for (var i = 0; i < entries.length; i += perPage) [for (final e in entries.skip(i).take(perPage)) e.toJson()],
    ];
  }

  Future<void> _sendHeads(Peer peer, {Set<String>? only}) async {
    final h = hub;
    if (h == null) return;
    _digestSentAt[peer.id] = DateTime.now();
    var all = await core.heads();
    if (only != null) all = [for (final e in all) if (only.contains(e.id)) e];
    for (final page in _pages(all)) {
      PeerJson.quiet(h.send(peer, PeerJson.encode({'heads': page}), kind: 'notes.heads', schema: 1));
    }
  }

  // ------------------------------------------------------------------ messages

  void onMessage(Peer from, AppMessage m) {
    if (m.schema != 1) return _bad();
    final j = m.jsonBody;
    switch (m.kind) {
      case 'notes.heads':
        final list = j is Map ? j['heads'] : null;
        if (list is! List || list.length > 500) return _bad();
        final entries = <HeadEntry>[];
        for (final e in list) {
          if (e is! Map || e['id'] is! String || e['head'] is! String || !_noteId.hasMatch(e['id'] as String) || !_hex64.hasMatch(e['head'] as String)) {
            return _bad();
          }
          entries.add(HeadEntry(e['id'] as String, e['head'] as String));
        }
        _enqueue(() => _receive(from, entries));
      case 'notes.digest':
        if (j is! Map || j['digest'] is! String) return _bad();
        final last = _digestSentAt[from.id];
        if (j['digest'] != _digest && (last == null || DateTime.now().difference(last) > const Duration(seconds: 5))) _sendHeads(from);
      case 'notes.get':
        if (m.requestId == null || j is! Map) return _bad();
        unawaited(_serve(m, j));
      default:
        ignored++;
    }
  }

  void _bad() => ignored++;

  void _enqueue(Future<void> Function() job) {
    _pending++;
    _tail = _tail.then((_) => job()).catchError((Object e) {
      // A peer must never be able to stop the queue.
      if (e is NotesCoreException && e.isBadBlock) return;
      ignored++;
    }).whenComplete(() {
      _pending--;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  // ------------------------------------------------------------------ catching up

  Future<void> _receive(Peer from, List<HeadEntry> theirs) async {
    final h = hub;
    if (h == null) return;
    await host.flushAll(); // an unsaved keystroke is an edit: record it first, so it counts as concurrent, not as overwritten
    final before = {for (final e in await core.heads()) e.id: e.head};

    var report = const ApplyReport();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!await _pull(h, from, theirs)) break;
      report = await core.applyHeads(theirs);
      if (report.incomplete.isEmpty) break;
    }

    for (final c in report.conflicts) {
      conflicts++;
      final win = conflictWinner(c);
      await core.resolveConflict(c.noteId, c.remote.manifest, Resolution.keepBoth(win));
      final (keep, other) = win == Side.local ? (c.local, c.remote) : (c.remote, c.local);
      this.report(keep.deleted || other.deleted
          ? '"${keep.deleted ? other.title : keep.title}" was deleted on ${keep.deleted ? keep.by : other.by} and edited on ${keep.deleted ? other.by : keep.by}. The edit was kept.'
          : '"${keep.title}" was edited on ${keep.by} and on ${other.by} at the same time. Both versions are kept: the other one is "${other.title} (conflict from ${other.by})".');
    }

    await _refreshDigest();
    final after = await core.heads();
    final changed = [for (final e in after) if (before[e.id] != e.head) e];
    if (changed.isNotEmpty) {
      host.remoteChanged([for (final e in changed) e.id]);
      _announce(changed);
    }
    if (report.localAhead.isNotEmpty) await _sendHeads(from, only: report.localAhead.toSet());
  }

  /// Fetch what [theirs] needs. Returns false when it could not (the peer is gone, tampered, or stopped answering).
  Future<bool> _pull(PeerHub h, Peer from, List<HeadEntry> theirs) async {
    for (var round = 0; round < 64; round++) {
      final missing = await core.missingBlocks(theirs, limit: 512);
      if (missing.isEmpty) return true;
      var progressed = false;
      for (var i = 0; i < missing.length; i += fetchBatch) {
        final batch = missing.sublist(i, i + fetchBatch > missing.length ? missing.length : i + fetchBatch);
        final PulledBlob? blob;
        try {
          blob = await pullBlob(h, from, kind: 'notes.get', key: {'hashes': batch}, maxBytes: 9 * 1024 * 1024, partBytes: partBytes, timeout: pullTimeout, onPart: () => partsPulled++);
        } on FormatException {
          _bad();
          return false;
        } on PeerError {
          return false; // lost or silent: the next hello, heads or digest asks again
        }
        if (blob == null) return false;
        bytesPulled += blob.bytes.length;
        try {
          final r = await core.importBlocks(blob.bytes);
          blocksStored += r.stored;
          progressed |= r.stored > 0;
        } on NotesCoreException catch (e) {
          if (e.isBadBlock) {
            refused++;
            report('A block from ${PeerJson.label(from.id)} did not match its hash and was refused. Nothing from that transfer was kept.');
          } else {
            _bad();
          }
          return false;
        }
      }
      if (!progressed) {
        stalled++;
        return false;
      }
    }
    return false;
  }

  // ------------------------------------------------------------------ serving

  Future<void> _serve(AppMessage m, Map j) async {
    final h = hub;
    final hashes = j['hashes'], part = j['part'];
    if (h == null) return;
    if (hashes is! List || hashes.length > 64 || hashes.any((x) => x is! String || !_hex64.hasMatch(x)) || part is! int || part < 0) return _bad();
    Map<String, Object?> answer;
    try {
      final key = hashes.join(',');
      // One export is asked for part by part, so the bytes are kept (a few exports at most) instead of being read and
      // re-hashed from the store for every 24 KiB part.
      var bytes = _exports[key];
      if (bytes == null) {
        bytes = await core.exportBlocks(hashes.cast<String>());
        if (_exports.length >= 4) _exports.remove(_exports.keys.first);
        _exports[key] = bytes;
      }
      final t = serveTransform;
      answer = blobPartReply(bytes: t == null ? bytes : t(bytes), part: part, partBytes: partBytes, tag: 'x', wantTag: j['tag']);
    } on NotesCoreException {
      answer = {'ok': false, 'reason': 'error'};
    }
    PeerJson.quiet(h.reply(m, PeerJson.encode(answer), schema: 1));
  }

  /// For tests: wait until nothing is queued.
  Future<void> idle() async {
    while (_pending > 0) {
      await _tail;
    }
  }
}

