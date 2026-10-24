import 'dart:io';
import 'dart:math';

import 'package:application_kit/application_kit.dart' show AppJsonFile;

import 'note.dart';

/// A file in the notes directory that could not be used as a note. It is never written to or deleted by the app.
class DamagedNote {
  const DamagedNote(this.fileName, this.reason);
  final String fileName, reason;
}

class LoadedNotes {
  const LoadedNotes(this.notes, this.damaged);
  final List<Note> notes; // newest edit first
  final List<DamagedNote> damaged;
}

/// Notes as one JSON file each in [dir] (the app uses `ctx.dirs.data/notes`).
/// Every write is atomic, so a crash mid-save leaves the previous version of the note intact.
class NoteStore {
  NoteStore(this.dir, {DateTime Function()? now, Random? rng})
      : _now = now ?? DateTime.now,
        _rng = rng ?? Random();

  final String dir;
  final DateTime Function() _now;
  final Random _rng;

  AppJsonFile _file(String id) => AppJsonFile(File('$dir${Platform.pathSeparator}$id.json'));

  LoadedNotes load() {
    final d = Directory(dir);
    if (!d.existsSync()) return const LoadedNotes([], []);
    final notes = <Note>[];
    final damaged = <DamagedNote>[];
    final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final r = AppJsonFile(f).read();
      if (!r.ok) {
        damaged.add(DamagedNote(name, r.problem!));
        continue;
      }
      try {
        final n = Note.fromJson(r.value);
        if ('${n.id}.json' != name) throw const FormatException('the id inside does not match the file name');
        notes.add(n);
      } on FormatException catch (e) {
        damaged.add(DamagedNote(name, e.message));
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return LoadedNotes(notes, damaged);
  }

  Note create({String title = 'Untitled', String body = ''}) {
    final now = _now().toUtc();
    final note = Note(id: _newId(), title: title, body: body, createdAt: now, updatedAt: now);
    save(note);
    return note;
  }

  /// Writes the note. Callers must not pass a note whose file was reported damaged (its id is never reused).
  void save(Note n) => _file(n.id).write(n.toJson());

  Note edited(Note n, {String? title, String? body}) => n.copyWith(title: title, body: body, updatedAt: _now().toUtc());

  void delete(String id) => _file(id).delete();

  String _newId() {
    // Existing files, damaged ones included, are never reused.
    while (true) {
      final id = '${_now().microsecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 20).toRadixString(36)}';
      if (!_file(id).file.existsSync()) return id;
    }
  }
}
