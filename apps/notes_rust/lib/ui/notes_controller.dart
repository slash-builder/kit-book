import 'dart:async';

import 'package:flutter/foundation.dart';

import '../coordination/notes_peers.dart';
import '../coordination/notes_sync.dart' show NotesHost;
import '../core/notes_core.dart';
import '../logic/autosaver.dart';
import '../logic/settings.dart';

/// The notes on screen, the selection and autosave, over a [NotesCore]. Every core call is async, so the controller keeps a
/// local draft of the open note (what the editor shows) and saves it a moment after the last keystroke, one save at a time.
class NotesController extends ChangeNotifier implements NotesHost {
  NotesController({
    required this.core,
    required this.settings,
    required this.report,
    Duration autosaveDelay = const Duration(milliseconds: 600),
  }) {
    _autosaver = Autosaver(autosaveDelay, () => unawaited(_saveDirty()));
  }

  final NotesCore core;
  final Settings settings;

  /// Tells the person about a problem: the app wires this to `ctx.notes.add`.
  final void Function(String message) report;

  late final Autosaver _autosaver;
  List<NoteSummary> notes = const [];
  CoreStats? stats;
  String? selectedId;

  /// The open note's text as typed (not yet necessarily saved).
  String draftTitle = '', draftBody = '';
  bool saveFailed = false;
  bool loaded = false;
  String? _dirtyId;
  // The save in flight (and everything queued behind it), or null when idle. Kept null when idle so `flush` never awaits an old
  // completed future: a future made in another zone (a widget test's fake-async one) would never resume in this one.
  Future<void>? _inFlight;
  bool _disposed = false;

  /// Peer sync for this copy (null when the app did not start it).
  NotesPeers? peers;

  /// Called after the PERSON changed notes: the sync engine tells the other copies.
  void Function(List<String> ids)? onLocalChange;

  final _remoteRev = <String, int>{};

  /// How many times a remote change or a restore replaced note [id] on screen; the editor is rebuilt when it changes.
  int remoteRevision(String id) => _remoteRev[id] ?? 0;

  bool get hasUnsavedChanges => _dirtyId != null;
  NoteSummary? get selected => notes.where((n) => n.id == selectedId).firstOrNull;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    await _reloadList();
    if (selectedId == null && notes.isNotEmpty) await select(notes.first.id);
    loaded = true;
    _notify();
  }

  Future<void> _reloadList() async {
    try {
      notes = await core.listNotes();
      stats = await core.stats();
    } on NotesCoreException catch (e) {
      report('Could not read the notes: ${e.message}');
    }
    _notify();
  }

  Future<void> select(String id) async {
    if (id == selectedId) return;
    await flush();
    try {
      final v = await core.getNote(id);
      selectedId = id;
      draftTitle = v.title;
      draftBody = v.body;
    } on NotesCoreException catch (e) {
      report('Could not open the note: ${e.message}');
    }
    _notify();
  }

  Future<void> create() async {
    await flush();
    try {
      final n = await core.createNote('Untitled', '');
      selectedId = n.id;
      draftTitle = n.title;
      draftBody = n.body;
      onLocalChange?.call([n.id]);
    } on NotesCoreException catch (e) {
      report('Could not create a note: ${e.message}');
    }
    await _reloadList();
  }

  /// Called for every change to the text of the open note.
  void edit(String id, String body) {
    if (id != selectedId || body == draftBody) return;
    draftBody = body;
    _dirtyId = id;
    _autosaver.schedule();
    _notify();
  }

  Future<void> rename(String id, String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await flush();
    try {
      final current = id == selectedId ? draftBody : (await core.getNote(id)).body;
      await core.saveNote(id, t, current);
      if (id == selectedId) draftTitle = t;
      onLocalChange?.call([id]);
    } on NotesCoreException catch (e) {
      report('Could not rename the note: ${e.message}');
    }
    await _reloadList();
  }

  Future<void> delete(String id) async {
    if (_dirtyId == id) {
      _autosaver.cancel();
      _dirtyId = null;
    }
    await flush();
    try {
      await core.deleteNote(id);
      onLocalChange?.call([id]);
    } on NotesCoreException catch (e) {
      report('Could not delete the note: ${e.message}');
      _notify();
      return;
    }
    await _reloadList();
    if (selectedId == id) {
      selectedId = null;
      if (notes.isNotEmpty) {
        await select(notes.first.id);
      } else {
        draftTitle = draftBody = '';
      }
    }
    _notify();
  }

  /// Saves anything unsaved now, including a note whose last save failed (so quitting retries it).
  Future<void> flush() async {
    _autosaver.cancel();
    if (_dirtyId != null) await _saveDirty();
    final f = _inFlight;
    if (f != null) await f;
  }

  Future<void> _saveDirty() {
    final prev = _inFlight ?? Future<void>.value();
    late final Future<void> mine;
    mine = prev.then((_) => _saveOnce()).whenComplete(() {
      if (identical(_inFlight, mine)) _inFlight = null;
    });
    return _inFlight = mine;
  }

  Future<void> _saveOnce() async {
    {
      final id = _dirtyId;
      if (id == null) return;
      final title = draftTitle, body = draftBody;
      try {
        await core.saveNote(id, title, body);
        if (_dirtyId == id && draftBody == body) _dirtyId = null;
        saveFailed = false;
        onLocalChange?.call([id]);
        await _reloadList();
      } on NotesCoreException catch (e) {
        if (!saveFailed) report('Could not save "$title": ${e.message}. Your text is still on screen.');
        saveFailed = true;
        _notify();
      }
    }
  }

  // ---- history ----

  Future<List<VersionInfo>> history(String id) => core.listVersions(id);
  Future<NoteView> preview(String id, String manifest) => core.readVersion(id, manifest);

  /// Makes an earlier version current. Returns false (and reports) when it could not.
  Future<bool> restore(String id, String manifest) async {
    await flush();
    try {
      final v = await core.restoreVersion(id, manifest);
      if (id == selectedId) {
        draftTitle = v.title;
        draftBody = v.body;
        _remoteRev[id] = remoteRevision(id) + 1;
      }
      onLocalChange?.call([id]);
      await _reloadList();
      return true;
    } on NotesCoreException catch (e) {
      report('Could not restore that version: ${e.message}');
      _notify();
      return false;
    }
  }

  // ---- NotesHost: what the sync engine may ask of the screen ----

  @override
  Future<void> flushAll() => flush();

  @override
  void remoteChanged(List<String> ids) => unawaited(_afterRemote(ids));

  Future<void> _afterRemote(List<String> ids) async {
    await _reloadList();
    final id = selectedId;
    if (id == null) {
      if (notes.isNotEmpty) await select(notes.first.id);
      return;
    }
    if (!ids.contains(id) || _dirtyId == id) return;
    try {
      final v = await core.getNote(id);
      draftTitle = v.title;
      draftBody = v.body;
      _remoteRev[id] = remoteRevision(id) + 1;
    } on NotesCoreException {
      // deleted on the other copy: leave the selection
      selectedId = null;
      draftTitle = draftBody = '';
      if (notes.isNotEmpty) await select(notes.first.id);
    }
    _notify();
  }

  /// Something outside the controller changed what the screen shows (a notice, the peer list): redraw.
  void changedExternally() => _notify();

  void changeFont(double delta) {
    settings.fontSize = settings.fontSize + delta;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _autosaver.cancel();
    super.dispose();
  }
}
