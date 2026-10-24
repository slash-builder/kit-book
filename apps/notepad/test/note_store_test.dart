import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/logic/autosaver.dart';
import 'package:notepad/logic/note.dart';
import 'package:notepad/logic/note_store.dart';

void main() {
  late Directory tmp;
  late String dir;
  var clock = DateTime.utc(2026, 10, 21, 12);
  DateTime now() => clock = clock.add(const Duration(minutes: 1));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('notes-');
    dir = '${tmp.path}/notes'; // does not exist yet: the store must cope
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  NoteStore store() => NoteStore(dir, now: now, rng: Random(1));
  File file(String name) => File('$dir/$name');

  group('Note', () {
    test('round-trips', () {
      final n = Note(id: 'abc123', title: 'T', body: 'line 1\nline 2 é中', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026, 2));
      final back = Note.fromJson(jsonDecode(jsonEncode(n.toJson())));
      expect(back.body, n.body);
      expect(back.updatedAt, n.updatedAt);
    });

    for (final (name, json) in <(String, Object?)>[
      ('not an object', []),
      ('no id', {'title': 't', 'body': 'b', 'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z'}),
      ('path-like id', {'id': '../x', 'title': 't', 'body': 'b', 'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z'}),
      ('title not text', {'id': 'abcd', 'title': 5, 'body': 'b', 'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z'}),
      ('body missing', {'id': 'abcd', 'title': 't', 'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z'}),
      ('bad date', {'id': 'abcd', 'title': 't', 'body': 'b', 'createdAt': 'soon', 'updatedAt': '2026-01-01T00:00:00Z'}),
    ]) {
      test('refuses: $name', () => expect(() => Note.fromJson(json), throwsFormatException));
    }
  });

  group('NoteStore', () {
    test('loading a directory that does not exist is empty, not an error', () {
      final l = store().load();
      expect(l.notes, isEmpty);
      expect(l.damaged, isEmpty);
    });

    test('create, edit, save and load back', () {
      final s = store();
      final n = s.create(title: 'Shopping');
      final edited = s.edited(n, body: 'milk\neggs');
      s.save(edited);
      final l = store().load();
      expect(l.notes.single.title, 'Shopping');
      expect(l.notes.single.body, 'milk\neggs');
      expect(l.notes.single.updatedAt.isAfter(l.notes.single.createdAt), isTrue);
      expect(Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('notes come back newest edit first', () {
      final s = store();
      final a = s.create(title: 'a');
      final b = s.create(title: 'b');
      s.save(s.edited(a, body: 'touched last'));
      expect(store().load().notes.map((n) => n.title), ['a', 'b']);
      expect(b.title, 'b');
    });

    test('rename keeps the body and the id', () {
      final s = store();
      final n = s.edited(s.create(title: 'old'), body: 'text');
      s.save(n);
      final r = s.edited(n, title: 'new');
      s.save(r);
      final l = store().load().notes.single;
      expect((l.id, l.title, l.body), (n.id, 'new', 'text'));
    });

    test('delete removes the file and is fine twice', () {
      final s = store();
      final n = s.create();
      s.delete(n.id);
      expect(store().load().notes, isEmpty);
      s.delete(n.id);
    });

    test('ignores files that are not notes and leftover temp files', () {
      final s = store();
      s.create(title: 'real');
      file('readme.txt').writeAsStringSync('hello');
      file('x.json.tmp').writeAsStringSync('{half a write');
      final l = s.load();
      expect(l.notes, hasLength(1));
      expect(l.damaged, isEmpty);
    });
  });

  group('damaged notes', () {
    test('are listed, left byte-for-byte untouched, and do not hide the good notes', () {
      final s = store();
      final good = s.create(title: 'good');
      final bad = {
        'notjson.json': utf8.encode('{"id": "notjson", "title": '),
        'binary.json': [0xff, 0xfe, 0x00, 0x80],
        'shape.json': utf8.encode('[1, 2, 3]'),
        'mismatch.json': utf8.encode(jsonEncode(Note(id: 'other1', title: 't', body: 'b', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)).toJson())),
        'empty.json': <int>[],
      };
      bad.forEach((name, bytes) => file(name).writeAsBytesSync(bytes));

      final l = store().load();
      expect(l.notes.single.id, good.id);
      expect(l.damaged.map((d) => d.fileName).toSet(), bad.keys.toSet());
      for (final d in l.damaged) {
        expect(d.reason, isNotEmpty);
      }
      bad.forEach((name, bytes) => expect(file(name).readAsBytesSync(), bytes, reason: name));
    });

    test('a new note never takes the name of a damaged file', () {
      final fixed = DateTime.utc(2026);
      final first = NoteStore(dir, now: () => fixed, rng: Random(1)).create();
      file('${first.id}.json').writeAsBytesSync([0xff, 0xfe]); // the id a same-seeded store would pick first
      final second = NoteStore(dir, now: () => fixed, rng: Random(1)).create();
      expect(second.id, isNot(first.id));
      expect(file('${first.id}.json').readAsBytesSync(), [0xff, 0xfe]);
    });
  });

  group('Autosaver', () {
    test('saves once, a short time after the last change', () async {
      var saves = 0;
      final a = Autosaver(const Duration(milliseconds: 40), () => saves++);
      a.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      a.schedule(); // restarts the wait
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(saves, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(saves, 1);
      expect(a.pending, isFalse);
    });

    test('flush saves immediately and only when something is pending', () {
      var saves = 0;
      final a = Autosaver(const Duration(seconds: 10), () => saves++);
      a.flush();
      expect(saves, 0);
      a.schedule();
      a.flush();
      expect(saves, 1);
      a.flush();
      expect(saves, 1);
    });

    test('cancel drops the pending save', () async {
      var saves = 0;
      final a = Autosaver(const Duration(milliseconds: 10), () => saves++)..schedule();
      a.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(saves, 0);
    });
  });
}
