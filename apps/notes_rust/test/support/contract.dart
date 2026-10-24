/// What any [NotesCore] must do, written once. `test/core_contract_fake_test.dart` runs it on the in-memory fake;
/// `integration_test/notes_rust_test.dart` runs the same group on the real Rust core. If the fake and the real core disagree,
/// one of these fails.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_rust/core/notes_core.dart';

/// [make] opens a fresh, empty core with the given device name.
void coreContract(String label, Future<NotesCore> Function(String device) make) {
  group('NotesCore contract ($label)', () {
    test('create, edit, version, restore and delete', () async {
      final c = await make('laptop');
      final n = await c.createNote('Shopping', 'milk\neggs\n');
      expect((await c.getNote(n.id)).body, 'milk\neggs\n');
      expect((await c.listNotes()).single.preview, 'milk');

      final v2 = await c.saveNote(n.id, 'Shopping', 'milk\neggs\nbread\n');
      expect((await c.saveNote(n.id, 'Shopping', 'milk\neggs\nbread\n')).head, v2.head, reason: 'an unchanged save writes no version');
      final versions = await c.listVersions(n.id);
      expect(versions.map((v) => v.isHead), [true, false]);
      expect(versions.every((v) => v.available), isTrue);
      expect((await c.readVersion(n.id, versions.last.manifest)).body, 'milk\neggs\n');

      final blocks = (await c.stats()).blockCount;
      final restored = await c.restoreVersion(n.id, versions.last.manifest);
      expect(restored.body, 'milk\neggs\n');
      expect((await c.stats()).blockCount, blocks + 1, reason: 'a restore writes one manifest and no body block');
      expect(await c.listVersions(n.id), hasLength(3));

      await c.deleteNote(n.id);
      expect(await c.listNotes(), isEmpty);
      await expectLater(c.getNote(n.id), throwsA(isA<NotesCoreException>().having((e) => e.code, 'code', 'no_such_note')));
      expect(await c.listVersions(n.id), hasLength(4));
      await c.close();
    });

    test('a refused import changes nothing; the same blocks, whole, are accepted', () async {
      final a = await make('laptop'), b = await make('desktop');
      await a.createNote('x', 'y' * 20000);
      final theirs = await a.heads();
      final missing = await b.missingBlocks(theirs);
      expect(missing, isNotEmpty);
      final export = await a.exportBlocks(missing);
      final bad = Uint8List.fromList(export)..[export.length - 1] ^= 0x01;
      await expectLater(b.importBlocks(bad), throwsA(isA<NotesCoreException>().having((e) => e.isBadBlock, 'isBadBlock', true)));
      expect((await b.stats()).blockCount, 0);
      await expectLater(b.importBlocks(Uint8List.fromList([1, 2, 3])), throwsA(isA<NotesCoreException>().having((e) => e.code, 'code', 'bad_export')));
      final r = await b.importBlocks(export);
      expect(r.stored, missing.length);
      await a.close();
      await b.close();
    });

    test('heads move only after the blocks are here; then both copies agree', () async {
      final a = await make('laptop'), b = await make('desktop');
      final n = await a.createNote('Plan', 'z' * 9000);
      final theirs = await a.heads();
      expect((await b.applyHeads(theirs)).incomplete, [n.id]);
      expect(await b.listNotes(), isEmpty);
      for (var i = 0; i < 8; i++) {
        final missing = await b.missingBlocks(theirs);
        if (missing.isEmpty) break;
        await b.importBlocks(await a.exportBlocks(missing));
      }
      expect((await b.applyHeads(theirs)).fastForwarded, [n.id]);
      expect(await a.headsDigest(), await b.headsDigest());
      expect((await b.getNote(n.id)).body, 'z' * 9000);
      await a.close();
      await b.close();
    });

    test('two edits of one note come back as a conflict with both versions; the core does not merge', () async {
      final a = await make('laptop'), b = await make('desktop');
      final n = await a.createNote('Plan', 'base\n');
      Future<void> pull(NotesCore to, NotesCore from) async {
        final theirs = await from.heads();
        for (var i = 0; i < 8; i++) {
          final missing = await to.missingBlocks(theirs);
          if (missing.isEmpty) break;
          await to.importBlocks(await from.exportBlocks(missing));
        }
      }

      await pull(b, a);
      await b.applyHeads(await a.heads());
      await a.saveNote(n.id, 'Plan', 'base\nfrom laptop\n');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.saveNote(n.id, 'Plan', 'base\nfrom desktop\n');
      await pull(a, b);
      final report = await a.applyHeads(await b.heads());
      final c = report.conflicts.single;
      expect((c.local.body, c.local.by), ('base\nfrom laptop\n', 'laptop'));
      expect((c.remote.body, c.remote.by), ('base\nfrom desktop\n', 'desktop'));
      expect(c.base?.body, 'base\n');
      expect((await a.getNote(n.id)).body, 'base\nfrom laptop\n', reason: 'nothing moved');
      expect(await a.pendingConflicts(), hasLength(1));

      await a.resolveConflict(n.id, c.remote.manifest, const Resolution.keepBoth(Side.remote));
      expect((await a.getNote(n.id)).body, 'base\nfrom desktop\n');
      final notes = await a.listNotes();
      expect(notes.map((x) => x.title).toSet(), {'Plan', 'Plan (conflict from laptop)'});
      expect(await a.pendingConflicts(), isEmpty);
      await expectLater(a.resolveConflict(n.id, c.remote.manifest, const Resolution.keepLocal()), throwsA(isA<NotesCoreException>().having((e) => e.code, 'code', 'no_conflict')));
      await a.close();
      await b.close();
    });
  });
}
