import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart';

import '../coordination/notes_peers.dart';
import '../coordination/note_sync.dart' show NoteHost;
import '../logic/autosaver.dart';
import '../logic/note.dart';
import '../logic/note_store.dart';
import '../logic/settings.dart';

/// The notes on screen, the selection, and autosave. All disk work goes through [NoteStore].
class NotesController extends ChangeNotifier implements NoteHost {
  NotesController({
    required this.store,
    required this.settings,
    required this.report,
    Duration autosaveDelay = const Duration(milliseconds: 600),
  }) {
    _autosaver = Autosaver(autosaveDelay, _saveDirty);
    final loaded = store.load();
    notes = [...loaded.notes];
    damaged = loaded.damaged;
    for (final d in damaged) {
      report('Note file ${d.fileName} could not be read (${d.reason}). It was left untouched.');
    }
    selectedId = notes.isEmpty ? null : notes.first.id;
  }

  final NoteStore store;
  final Settings settings;

  /// Tells the person about a problem: the app wires this to `ctx.notes.add`.
  final void Function(String message) report;

  late final Autosaver _autosaver;
  @override
  late List<Note> notes;
  late final List<DamagedNote> damaged;
  String? selectedId;
  final _dirty = <String>{};
  bool saveFailed = false;

  /// Peer sync for this copy's notes (null when the app did not start it).
  NotesPeers? peers;

  /// Called after a note was written by the PERSON (create, autosave, rename) or deleted; not after a synced write.
  void Function(Note note)? onNoteSaved;
  void Function(String id)? onNoteDeleted;

  /// How many times a remote change replaced note [id] on screen; the editor is rebuilt when it changes.
  final _remoteRev = <String, int>{};
  int remoteRevision(String id) => _remoteRev[id] ?? 0;

  Note? get selected => notes.where((n) => n.id == selectedId).firstOrNull;
  bool get hasUnsavedChanges => _dirty.isNotEmpty;

  void select(String id) {
    if (id == selectedId) return;
    flush();
    selectedId = id;
    notifyListeners();
  }

  void create() {
    flush();
    final n = store.create();
    onNoteSaved?.call(n);
    notes.insert(0, n);
    selectedId = n.id;
    notifyListeners();
  }

  /// Called for every change to the text of the selected note.
  void edit(String id, String body) {
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0 || notes[i].body == body) return;
    notes[i] = store.edited(notes[i], body: body);
    _dirty.add(id);
    _autosaver.schedule();
    notifyListeners();
  }

  void rename(String id, String title) {
    final i = notes.indexWhere((n) => n.id == id);
    final t = title.trim();
    if (i < 0 || t.isEmpty || notes[i].title == t) return;
    notes[i] = store.edited(notes[i], title: t);
    _dirty.add(id);
    _autosaver.cancel(); // a rename is saved now, together with anything else still waiting
    _saveDirty();
  }

  void delete(String id) {
    _dirty.remove(id);
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    try {
      store.delete(id);
    } on FileSystemException catch (e) {
      report('Could not delete the note: ${e.message}');
      notifyListeners();
      return;
    }
    onNoteDeleted?.call(id);
    notes.removeAt(i);
    if (selectedId == id) selectedId = notes.isEmpty ? null : notes[i.clamp(0, notes.length - 1)].id;
    notifyListeners();
  }

  /// Saves anything unsaved now, including a note whose last save failed (so quitting retries it).
  void flush() {
    _autosaver.cancel();
    if (_dirty.isNotEmpty) _saveDirty();
  }

  // ---- NoteHost: what the sync engine may ask of the notes (the files stay the source of truth) ----

  @override
  Note? note(String id) => notes.where((n) => n.id == id).firstOrNull;

  @override
  bool isDamaged(String id) => damaged.any((d) => d.fileName == '$id.json');

  @override
  void flushNote(String id) {
    if (_dirty.contains(id)) flush();
  }

  @override
  void applyRemote(Note n) {
    store.save(n); // throws FileSystemException: the engine reports it and tries again later
    _dirty.remove(n.id);
    notes.removeWhere((x) => x.id == n.id);
    notes.add(n);
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    selectedId ??= n.id;
    _remoteRev[n.id] = remoteRevision(n.id) + 1;
    notifyListeners();
  }

  @override
  void removeRemote(String id) {
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    store.delete(id);
    _dirty.remove(id);
    notes.removeAt(i);
    if (selectedId == id) selectedId = notes.isEmpty ? null : notes[i.clamp(0, notes.length - 1)].id;
    notifyListeners();
  }

  /// Something outside the controller changed what the screen shows (a notice, the peer list): redraw.
  void changedExternally() => notifyListeners();

  void changeFont(double delta) {
    settings.fontSize = settings.fontSize + delta;
    notifyListeners();
  }

  void _saveDirty() {
    for (final id in _dirty.toList()) {
      final n = notes.where((n) => n.id == id).firstOrNull;
      if (n == null) {
        _dirty.remove(id);
        continue;
      }
      try {
        store.save(n);
        _dirty.remove(id);
        saveFailed = false;
        onNoteSaved?.call(n);
      } on FileSystemException catch (e) {
        if (!saveFailed) report('Could not save "${n.title}": ${e.message}. Your text is still on screen.');
        saveFailed = true;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _autosaver.cancel();
    super.dispose();
  }
}
