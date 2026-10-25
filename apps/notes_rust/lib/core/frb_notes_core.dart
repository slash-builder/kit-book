/// [NotesCore] over the generated flutter_rust_bridge binding. This file is the only place outside `src/rust/` that touches
/// generated types: errors become [NotesCoreException] and data becomes the plain classes in `notes_core.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:app_context_kit/app_context_kit.dart';

import '../src/rust/api/notes.dart' as b;
import '../src/rust/types.dart' as t;
import 'notes_core.dart';

class FrbNotesCore implements NotesCore {
  FrbNotesCore._(this._engine);

  final b.NotesEngine _engine;

  /// Hands the Rust core the context [ctx] already opened. The core adopts it: no second roster entry, no second instance id,
  /// and no write to `config.json`. `RustLib.init()` must have run (see `main.dart`).
  static Future<FrbNotesCore> open(AppContext ctx) => openWith(snapshot: ctx.snapshot(), account: ctx.peerAccount, device: ctx.peerDevice);

  /// The same from the three values [open] reads.
  static Future<FrbNotesCore> openWith({required Map<String, Object?> snapshot, required String account, required String device}) async {
    return _guard(() async => FrbNotesCore._(await b.NotesEngine.open(snapshotJson: jsonEncode(snapshot), account: account, device: device)));
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on b.CoreError catch (e) {
      throw NotesCoreException(e.code, e.message);
    }
  }

  static NoteSummary _summary(t.NoteSummary n) =>
      NoteSummary(id: n.id, title: n.title, preview: n.preview, len: n.len.toInt(), atMs: n.atMs.toInt(), by: n.by, head: n.head);
  static NoteView _view(t.NoteView n) => NoteView(id: n.id, title: n.title, body: n.body, atMs: n.atMs.toInt(), by: n.by, head: n.head);
  static VersionInfo _version(t.VersionInfo v) => VersionInfo(
        manifest: v.manifest,
        parents: v.parents,
        title: v.title,
        len: v.len.toInt(),
        atMs: v.atMs.toInt(),
        by: v.by,
        deleted: v.deleted,
        available: v.available,
        isHead: v.isHead,
      );
  static NoteVersion _nv(t.NoteVersion v) =>
      NoteVersion(manifest: v.manifest, title: v.title, body: v.body, atMs: v.atMs.toInt(), by: v.by, deleted: v.deleted);
  static Conflict _conflict(t.Conflict c) =>
      Conflict(noteId: c.noteId, local: _nv(c.local), remote: _nv(c.remote), base: c.base == null ? null : _nv(c.base!));
  static List<t.HeadEntry> _entries(List<HeadEntry> l) => [for (final e in l) t.HeadEntry(id: e.id, head: e.head)];

  @override
  Future<List<NoteSummary>> listNotes() => _guard(() async => (await _engine.listNotes()).map(_summary).toList());
  @override
  Future<NoteView> getNote(String id) => _guard(() async => _view(await _engine.getNote(id: id)));
  @override
  Future<NoteView> createNote(String title, String body) => _guard(() async => _view(await _engine.createNote(title: title, body: body)));
  @override
  Future<NoteView> saveNote(String id, String title, String body) => _guard(() async => _view(await _engine.saveNote(id: id, title: title, body: body)));
  @override
  Future<void> deleteNote(String id) => _guard(() => _engine.deleteNote(id: id));
  @override
  Future<List<VersionInfo>> listVersions(String id, {int limit = 50}) =>
      _guard(() async => (await _engine.listVersions(id: id, limit: limit)).map(_version).toList());
  @override
  Future<NoteView> readVersion(String id, String manifest) => _guard(() async => _view(await _engine.readVersion(id: id, manifest: manifest)));
  @override
  Future<NoteView> restoreVersion(String id, String manifest) => _guard(() async => _view(await _engine.restoreVersion(id: id, manifest: manifest)));

  @override
  Future<List<HeadEntry>> heads() async => [for (final e in await _engine.heads()) HeadEntry(e.id, e.head)];
  @override
  Future<String> headsDigest() => _engine.headsDigest();
  @override
  Future<List<String>> missingBlocks(List<HeadEntry> theirs, {int limit = 512}) =>
      _guard(() => _engine.missingBlocks(theirs: _entries(theirs), limit: limit));
  @override
  Future<Uint8List> exportBlocks(List<String> hashes) => _guard(() => _engine.exportBlocks(hashes: hashes));
  @override
  Future<ImportReport> importBlocks(Uint8List export) => _guard(() async {
        final r = await _engine.importBlocks(bytes: export);
        return ImportReport(received: r.received, stored: r.stored, bytes: r.bytes.toInt());
      });
  @override
  Future<ApplyReport> applyHeads(List<HeadEntry> theirs) => _guard(() async {
        final r = await _engine.applyHeads(theirs: _entries(theirs));
        return ApplyReport(
          upToDate: r.upToDate,
          fastForwarded: r.fastForwarded,
          localAhead: r.localAhead,
          incomplete: r.incomplete,
          rejected: r.rejected,
          conflicts: r.conflicts.map(_conflict).toList(),
        );
      });
  @override
  Future<List<Conflict>> pendingConflicts() => _guard(() async => (await _engine.pendingConflicts()).map(_conflict).toList());
  @override
  Future<void> resolveConflict(String noteId, String remote, Resolution how) {
    final choice = switch (how) {
      KeepLocal() => b.ResolutionChoice(kind: b.ResolutionKind.keepLocal, title: '', body: ''),
      TakeRemote() => b.ResolutionChoice(kind: b.ResolutionKind.takeRemote, title: '', body: ''),
      Merged(:final title, :final body) => b.ResolutionChoice(kind: b.ResolutionKind.merged, title: title, body: body),
      KeepBoth(:final winner) => b.ResolutionChoice(
          kind: winner == Side.local ? b.ResolutionKind.keepBothLocalWins : b.ResolutionKind.keepBothRemoteWins, title: '', body: ''),
    };
    return _guard(() => _engine.resolveConflict(noteId: noteId, remote: remote, how: choice));
  }

  @override
  Future<CoreStats> stats() async {
    final s = await _engine.stats();
    return CoreStats(
      appId: s.appId,
      instance: s.instance,
      mode: s.mode,
      account: s.account,
      device: s.device,
      partition: s.partition,
      dataDir: s.dataDir,
      blockCount: s.blockCount,
      noteCount: s.noteCount,
      unreadableNotes: s.unreadableNotes,
      pendingConflicts: s.pendingConflicts,
      maxNoteBytes: s.maxNoteBytes.toInt(),
    );
  }

  @override
  Future<void> close() async => _engine.dispose();
}
