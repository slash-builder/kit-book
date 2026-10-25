/// An in-memory [NotesCore] with the same behaviour as the Rust core where the app can tell, so widget tests and sync tests
/// run without the native library (the way Bozzetto's mock pipeline does). Blocks are hashed with SHA-256 here; the real core
/// uses the Storage Kit's BLAKE3. Bodies are cut into fixed [chunkBytes] chunks under one list block, which is enough to see
/// "a small edit moves a small part".
///
/// What it does NOT do: touch the disk, adopt a context, or share anything with another process. The tests that need those
/// are the Rust tests (`cargo test`) and the integration tests (`integration_test/`, real library).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'notes_core.dart';

String _sha(List<int> bytes) => crypto.sha256.convert(bytes).toString();

class _M {
  _M({
    required this.id,
    required this.title,
    required this.deleted,
    required this.at,
    required this.by,
    required this.root,
    required this.depth,
    required this.len,
    required this.parents,
  });
  final String id, title, by, root;
  final bool deleted;
  final int at, depth, len;
  final List<String> parents;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'deleted': deleted,
        'at': at,
        'by': by,
        'root': root,
        'depth': depth,
        'len': len,
        'parents': parents,
      };
  static _M fromJson(Map<String, dynamic> j) => _M(
        id: j['id'] as String,
        title: j['title'] as String,
        deleted: j['deleted'] as bool,
        at: j['at'] as int,
        by: j['by'] as String,
        root: j['root'] as String,
        depth: j['depth'] as int,
        len: j['len'] as int,
        parents: (j['parents'] as List).cast<String>(),
      );
  bool sameContent(_M o) => deleted == o.deleted && title == o.title && root == o.root && len == o.len;
}

class FakeNotesCore implements NotesCore {
  FakeNotesCore({
    this.device = 'fake',
    this.account = 'local',
    this.appId = 'com.slashbuilder.demo.notes-rust',
    this.instance = 'f4k3f4k3',
    int Function()? clock,
    this.chunkBytes = 4096,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String device, account, appId, instance;
  final int chunkBytes;
  int Function() _clock;
  set clock(int Function() c) => _clock = c;

  final _blocks = <String, Uint8List>{};
  final _heads = <String, String>{};
  final _conflicts = <String, String>{};
  var _closed = false;
  var _nextId = 0;

  /// Test hooks.
  Object? failNextWith;
  int saveCalls = 0;

  int get blockCount => _blocks.length;

  void _check() {
    if (_closed) throw const NotesCoreException('closed', 'the core is closed');
    final f = failNextWith;
    if (f != null) {
      failNextWith = null;
      throw f;
    }
  }

  // ---- blocks and manifests ----
  String _put(List<int> bytes) {
    final h = _sha(bytes);
    _blocks.putIfAbsent(h, () => Uint8List.fromList(bytes));
    return h;
  }

  _M _manifest(String h) {
    final b = _blocks[h];
    if (b == null) throw NotesCoreException('storage', 'not found: $h');
    return _M.fromJson(jsonDecode(utf8.decode(b)) as Map<String, dynamic>);
  }

  ({String root, int depth, int len}) _tree(List<int> body) {
    if (body.length <= chunkBytes) return (root: _put(body), depth: 0, len: body.length);
    final hashes = <String>[];
    for (var i = 0; i < body.length; i += chunkBytes) {
      hashes.add(_put(body.sublist(i, i + chunkBytes > body.length ? body.length : i + chunkBytes)));
    }
    return (root: _put(utf8.encode(hashes.join('\n'))), depth: 1, len: body.length);
  }

  String _writeManifest(String id, String title, bool deleted, ({String root, int depth, int len}) t, List<String> parents, int at, String by) =>
      _put(utf8.encode(jsonEncode(_M(id: id, title: title, deleted: deleted, at: at, by: by, root: t.root, depth: t.depth, len: t.len, parents: parents).toJson())));

  List<String> _children(String listHash) => utf8.decode(_blocks[listHash]!).split('\n');

  bool _treeComplete(_M m) {
    if (!_blocks.containsKey(m.root)) return false;
    if (m.depth == 0) return true;
    return _children(m.root).every(_blocks.containsKey);
  }

  String _body(_M m) {
    if (!_treeComplete(m)) throw NotesCoreException('version_unavailable', 'version is not on this copy');
    if (m.depth == 0) return utf8.decode(_blocks[m.root]!, allowMalformed: true);
    final out = BytesBuilder(copy: false);
    for (final c in _children(m.root)) {
      out.add(_blocks[c]!);
    }
    return utf8.decode(out.takeBytes(), allowMalformed: true);
  }

  Set<String> _ancestors(String start, [Set<String> stop = const {}]) {
    final seen = <String>{};
    final todo = [start];
    while (todo.isNotEmpty) {
      final h = todo.removeLast();
      if (!seen.add(h)) continue;
      if (stop.contains(h) || !_blocks.containsKey(h)) continue;
      todo.addAll(_manifest(h).parents);
    }
    return seen;
  }

  NoteView _view(String id, String addr) {
    final m = _manifest(addr);
    return NoteView(id: id, title: m.title, body: _body(m), atMs: m.at, by: m.by, head: addr);
  }

  // ---- notes ----
  @override
  Future<List<NoteSummary>> listNotes() async {
    _check();
    final out = <NoteSummary>[];
    for (final e in _heads.entries) {
      final m = _manifest(e.value);
      if (m.deleted) continue;
      final prefix = _treeComplete(m) ? _body(m) : '';
      final line = prefix.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
      out.add(NoteSummary(id: e.key, title: m.title, preview: line.length > 120 ? line.substring(0, 120) : line, len: m.len, atMs: m.at, by: m.by, head: e.value));
    }
    out.sort((a, b) => b.atMs != a.atMs ? b.atMs.compareTo(a.atMs) : a.id.compareTo(b.id));
    return out;
  }

  @override
  Future<NoteView> getNote(String id) async {
    _check();
    final h = _heads[id];
    if (h == null || _manifest(h).deleted) throw NotesCoreException('no_such_note', 'no such note: $id');
    return _view(id, h);
  }

  @override
  Future<NoteView> createNote(String title, String body) async {
    _check();
    String id;
    do {
      id = 'n${device.hashCode.abs().toRadixString(36)}${(_nextId++).toRadixString(36).padLeft(4, '0')}${_clock().toRadixString(36)}'.toLowerCase();
    } while (_heads.containsKey(id));
    return _save(id, title, body);
  }

  NoteView _save(String id, String title, String body) {
    saveCalls++;
    final bytes = utf8.encode(body);
    final t = _tree(bytes);
    final head = _heads[id];
    if (head != null) {
      final cur = _manifest(head);
      if (!cur.deleted && cur.title == title && cur.root == t.root && cur.len == t.len) return _view(id, head);
    }
    final a = _writeManifest(id, title, false, t, head == null ? [] : [head], _clock(), device);
    _heads[id] = a;
    return _view(id, a);
  }

  @override
  Future<NoteView> saveNote(String id, String title, String body) async {
    _check();
    if (!_heads.containsKey(id)) throw NotesCoreException('no_such_note', 'no such note: $id');
    return _save(id, title, body);
  }

  @override
  Future<void> deleteNote(String id) async {
    _check();
    final head = _heads[id];
    if (head == null) throw NotesCoreException('no_such_note', 'no such note: $id');
    final cur = _manifest(head);
    if (cur.deleted) return;
    _heads[id] = _writeManifest(id, cur.title, true, _tree(const []), [head], _clock(), device);
  }

  @override
  Future<List<VersionInfo>> listVersions(String id, {int limit = 50}) async {
    _check();
    final head = _heads[id];
    if (head == null) throw NotesCoreException('no_such_note', 'no such note: $id');
    final all = _ancestors(head).where(_blocks.containsKey).map((h) => (h, _manifest(h))).toList()
      ..sort((a, b) => b.$2.at != a.$2.at ? b.$2.at.compareTo(a.$2.at) : b.$1.compareTo(a.$1));
    return [
      for (final (h, m) in all.take(limit < 1 ? 1 : limit))
        VersionInfo(manifest: h, parents: m.parents, title: m.title, len: m.len, atMs: m.at, by: m.by, deleted: m.deleted, available: _treeComplete(m), isHead: h == head),
    ];
  }

  @override
  Future<NoteView> readVersion(String id, String manifest) async {
    _check();
    if (!_blocks.containsKey(manifest) || _manifest(manifest).id != id) throw NotesCoreException('no_such_version', 'no such version: $manifest');
    return _view(id, manifest);
  }

  @override
  Future<NoteView> restoreVersion(String id, String manifest) async {
    _check();
    final head = _heads[id];
    if (head == null) throw NotesCoreException('no_such_note', 'no such note: $id');
    if (!_blocks.containsKey(manifest) || _manifest(manifest).id != id) throw NotesCoreException('no_such_version', 'no such version: $manifest');
    final old = _manifest(manifest);
    if (!_treeComplete(old)) throw NotesCoreException('version_unavailable', 'version is not on this copy');
    final cur = _manifest(head);
    if (!cur.deleted && cur.title == old.title && cur.root == old.root && cur.len == old.len) return _view(id, head);
    final a = _writeManifest(id, old.title, old.deleted, (root: old.root, depth: old.depth, len: old.len), [head], _clock(), device);
    _heads[id] = a;
    return _view(id, a);
  }

  // ---- sync ----
  @override
  Future<List<HeadEntry>> heads() async {
    _check();
    return [for (final e in _heads.entries) HeadEntry(e.key, e.value)];
  }

  @override
  Future<String> headsDigest() async {
    _check();
    final ids = _heads.keys.toList()..sort();
    return _sha(utf8.encode('fake-heads\n${ids.map((i) => '$i\t${_heads[i]}\n').join()}'));
  }

  @override
  Future<List<String>> missingBlocks(List<HeadEntry> theirs, {int limit = 512}) async {
    _check();
    final out = <String>[];
    void add(String h) {
      if (out.length < limit && !out.contains(h)) out.add(h);
    }

    for (final e in theirs) {
      final r = e.head;
      final l = _heads[e.id];
      if (l == r) continue;
      final stop = l == null ? <String>{} : _ancestors(l);
      // history back to something we have
      final seen = <String>{};
      final todo = [r];
      while (todo.isNotEmpty) {
        final h = todo.removeLast();
        if (!seen.add(h) || stop.contains(h)) continue;
        if (!_blocks.containsKey(h)) {
          add(h);
          continue;
        }
        todo.addAll(_manifest(h).parents);
      }
      if (_blocks.containsKey(r)) {
        final m = _manifest(r);
        if (m.id != e.id) throw NotesCoreException('invalid', 'head $r is not a version of note ${e.id}');
        if (!_blocks.containsKey(m.root)) {
          add(m.root);
        } else if (m.depth > 0) {
          _children(m.root).where((c) => !_blocks.containsKey(c)).forEach(add);
        }
      }
    }
    return out;
  }

  static final _magic = utf8.encode('NBK1');

  @override
  Future<Uint8List> exportBlocks(List<String> hashes) async {
    _check();
    final out = BytesBuilder()..add(_magic);
    for (final h in hashes.take(1024)) {
      final b = _blocks[h];
      if (b == null) continue;
      if (out.length > 4 && out.length + 36 + b.length > 8 * 1024 * 1024) break;
      // the real format has 32 raw hash bytes; the fake's SHA-256 hex is 64 characters, so it carries them as 32 bytes too
      out.add(_unhex(h));
      out.add((ByteData(4)..setUint32(0, b.length, Endian.little)).buffer.asUint8List());
      out.add(b);
    }
    return out.takeBytes();
  }

  static Uint8List _unhex(String h) => Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<ImportReport> importBlocks(Uint8List export) async {
    _check();
    NotesCoreException bad(String m) => NotesCoreException('bad_export', 'bad block export: $m');
    if (export.length < 4 || !_listEq(export.sublist(0, 4), _magic)) throw bad('not a block export');
    final records = <(String, Uint8List)>[];
    var pos = 4;
    while (pos < export.length) {
      if (export.length - pos < 36) throw bad('a record header runs past the end');
      final claimed = _hex(export.sublist(pos, pos + 32));
      final len = ByteData.sublistView(export, pos + 32, pos + 36).getUint32(0, Endian.little);
      pos += 36;
      if (export.length - pos < len) throw bad('a block runs past the end');
      records.add((claimed, export.sublist(pos, pos + len)));
      pos += len;
    }
    for (final (claimed, bytes) in records) {
      final actual = _sha(bytes);
      if (actual != claimed) throw NotesCoreException('bad_block', 'block sent as $claimed hashes to $actual; refused');
    }
    var stored = 0, total = 0;
    for (final (claimed, bytes) in records) {
      total += bytes.length;
      if (_blocks.containsKey(claimed)) continue;
      _blocks[claimed] = bytes;
      stored++;
    }
    return ImportReport(received: records.length, stored: stored, bytes: total);
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _closure(String r, String? l) {
    final stop = l == null ? <String>{} : _ancestors(l);
    final seen = <String>{};
    final todo = [r];
    while (todo.isNotEmpty) {
      final h = todo.removeLast();
      if (!seen.add(h) || stop.contains(h)) continue;
      if (!_blocks.containsKey(h)) return false;
      todo.addAll(_manifest(h).parents);
    }
    return _treeComplete(_manifest(r));
  }

  NoteVersion _nv(String h) {
    final m = _manifest(h);
    return NoteVersion(manifest: h, title: m.title, body: _body(m), atMs: m.at, by: m.by, deleted: m.deleted);
  }

  Conflict _conflict(String id, String l, String r) {
    final ours = _ancestors(l);
    String? base;
    final q = [r];
    final seen = <String>{};
    while (q.isNotEmpty && base == null) {
      final h = q.removeAt(0);
      if (!seen.add(h) || !_blocks.containsKey(h)) continue;
      if (ours.contains(h)) {
        base = h;
        break;
      }
      q.addAll(_manifest(h).parents);
    }
    return Conflict(noteId: id, local: _nv(l), remote: _nv(r), base: base != null && _treeComplete(_manifest(base)) ? _nv(base) : null);
  }

  @override
  Future<ApplyReport> applyHeads(List<HeadEntry> theirs) async {
    _check();
    final upToDate = <String>[], ff = <String>[], ahead = <String>[], incomplete = <String>[], rejected = <String>[];
    final conflicts = <Conflict>[];
    for (final e in theirs) {
      final r = e.head;
      final l = _heads[e.id];
      if (l == r) {
        upToDate.add(e.id);
        continue;
      }
      if (!_blocks.containsKey(r)) {
        incomplete.add(e.id);
        continue;
      }
      final rm = _manifest(r);
      if (rm.id != e.id) {
        rejected.add(e.id);
        continue;
      }
      if (l != null && _ancestors(l).contains(r)) {
        ahead.add(e.id);
        continue;
      }
      if (!_closure(r, l)) {
        incomplete.add(e.id);
        continue;
      }
      if (l == null || _ancestors(r).contains(l)) {
        _heads[e.id] = r;
        _conflicts.remove(e.id);
        ff.add(e.id);
        continue;
      }
      final lm = _manifest(l);
      if (lm.sameContent(rm)) {
        if (r.compareTo(l) < 0) {
          _heads[e.id] = r;
          ff.add(e.id);
        } else {
          upToDate.add(e.id);
        }
        _conflicts.remove(e.id);
        continue;
      }
      _conflicts[e.id] = r;
      conflicts.add(_conflict(e.id, l, r));
    }
    return ApplyReport(upToDate: upToDate, fastForwarded: ff, localAhead: ahead, incomplete: incomplete, rejected: rejected, conflicts: conflicts);
  }

  @override
  Future<List<Conflict>> pendingConflicts() async {
    _check();
    final out = <Conflict>[];
    for (final e in _conflicts.entries.toList()) {
      final l = _heads[e.key];
      final r = e.value;
      if (l == null || l == r || !_blocks.containsKey(l) || !_blocks.containsKey(r) || _ancestors(l).contains(r) || _ancestors(r).contains(l)) {
        _conflicts.remove(e.key);
        continue;
      }
      out.add(_conflict(e.key, l, r));
    }
    return out;
  }

  @override
  Future<void> resolveConflict(String noteId, String remote, Resolution how) async {
    _check();
    final l = _heads[noteId];
    if (l == null) throw NotesCoreException('no_such_note', 'no such note: $noteId');
    if (_conflicts[noteId] != remote || !_blocks.containsKey(remote)) throw NotesCoreException('no_conflict', 'note $noteId has no pending conflict with that version');
    final lm = _manifest(l), rm = _manifest(remote);
    ({String root, int depth, int len}) body(_M m) => (root: m.root, depth: m.depth, len: m.len);
    final at = _clock();
    switch (how) {
      case KeepLocal():
        _heads[noteId] = _writeManifest(noteId, lm.title, lm.deleted, body(lm), [l, remote], at, device);
      case TakeRemote():
        _heads[noteId] = _writeManifest(noteId, rm.title, rm.deleted, body(rm), [l, remote], at, device);
      case Merged(:final title, :final body):
        _heads[noteId] = _writeManifest(noteId, title, false, _tree(utf8.encode(body)), [l, remote], at, device);
      case KeepBoth(:final winner):
        final (win, lose, loseM) = winner == Side.local ? (l, remote, rm) : (remote, l, lm);
        if (win != l) _heads[noteId] = win;
        if (!loseM.deleted) {
          final cid = 'cf${_sha(utf8.encode('fake-conflict-copy\n$noteId\n$lose')).substring(0, 16)}';
          _heads.putIfAbsent(cid, () => _writeManifest(cid, '${loseM.title} (conflict from ${loseM.by})', false, body(loseM), const [], loseM.at, loseM.by));
        }
    }
    _conflicts.remove(noteId);
  }

  @override
  Future<CoreStats> stats() async {
    _check();
    return CoreStats(
      appId: appId,
      instance: instance,
      mode: 'mock',
      account: account,
      device: device,
      partition: _sha(utf8.encode('fake\n$account\n$appId')).substring(0, 32),
      dataDir: '(memory)',
      blockCount: _blocks.length,
      noteCount: _heads.values.where((h) => !_manifest(h).deleted).length,
      unreadableNotes: 0,
      pendingConflicts: _conflicts.length,
      maxNoteBytes: 32 * 1024 * 1024,
    );
  }

  @override
  Future<void> close() async => _closed = true;
}
