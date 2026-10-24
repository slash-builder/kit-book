import 'dart:convert';
import 'dart:io';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';
import 'package:notes_rust/core/fake_notes_core.dart';
import 'package:notes_rust/core/notes_core.dart';
import 'package:notes_rust/ui/notes_app.dart';
import 'package:notes_rust/ui/notes_screen.dart';
import 'package:notes_rust/ui/notes_controller.dart';

import 'support/copy.dart';

/// The UI over the in-memory fake core: no native library. (The real core is covered by `cargo test` and integration_test/.)
void main() {
  final manifestText = File('app.json').readAsStringSync();
  late KitTestContext kit;
  late FakeNotesCore core;
  var clock = 1000000;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<NotesController> boot(WidgetTester t, {FakeNotesCore? with_, Directory? scratch, bool peers = false, FakePeerNetwork? net}) async {
    core = with_ ?? FakeNotesCore(device: 'laptop', clock: () => clock += 1000);
    kit = await pumpKitApp(t,
        manifest: manifestText,
        env: {'APPKIT_DEVICE': 'laptop'},
        scratch: scratch,
        app: (_) => NotesApp(
              openCore: (_) async => core,
              autosaveDelay: const Duration(milliseconds: 100),
              peers: peers,
              network: net,
              syncHeartbeat: Duration.zero,
            ));
    await settle(t);
    return t.widget<NotesScreen>(find.byType(NotesScreen)).controller;
  }

  Future<void> type(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const ValueKey('editor')), text);
    await t.pump(const Duration(milliseconds: 150)); // past the autosave pause
    await settle(t);
  }

  Finder noticeText() => find.descendant(of: find.byKey(const ValueKey('notice')), matching: find.byType(Text));
  String saveText(WidgetTester t) => t.widget<Text>(find.descendant(of: find.byType(SaveStatusChip), matching: find.byType(Text))).data!;

  testWidgets('first run shows the empty state, the mode chip and the core line with the context instance', (t) async {
    await boot(t);
    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.text('mock + scratch'), findsOneWidget);
    expect(noticeText(), findsNothing);
    expect(find.byKey(const ValueKey('core-line')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('core-line'))).data, contains('0 notes'));
    await kit.quit();
  });

  testWidgets('NOTES_RUST_SEED writes sample notes into an empty store only', (t) async {
    core = FakeNotesCore(device: 'laptop', clock: () => clock += 1000);
    kit = await pumpKitApp(t,
        manifest: manifestText,
        env: {'NOTES_RUST_SEED': '3'},
        app: (_) => NotesApp(openCore: (_) async => core, peers: false));
    await settle(t);
    expect((await t.runAsync(core.listNotes))!.map((n) => n.title).toSet(), {'Sample note 1', 'Sample note 2', 'Sample note 3'});
    await kit.quit();

    // a store that already has a note is left alone
    core = FakeNotesCore(device: 'laptop', clock: () => clock += 1000);
    await core.createNote('Mine', 'already here');
    kit = await pumpKitApp(t,
        manifest: manifestText,
        env: {'NOTES_RUST_SEED': '3'},
        app: (_) => NotesApp(openCore: (_) async => core, peers: false));
    await settle(t);
    expect((await t.runAsync(core.listNotes))!.map((n) => n.title), ['Mine']);
    await kit.quit();
  });

  testWidgets('create a note, type, and it is saved by the core after the pause', (t) async {
    final c = await boot(t);
    await t.tap(find.byKey(const ValueKey('new-note')));
    await settle(t);
    expect(find.byKey(const ValueKey('editor')), findsOneWidget);
    expect(find.text('Untitled'), findsWidgets);
    await type(t, 'milk\neggs');
    expect(saveText(t), 'Saved');
    final notes = await t.runAsync(core.listNotes);
    expect(notes!.single.title, 'Untitled');
    expect((await t.runAsync(() => core.getNote(c.selectedId!)))!.body, 'milk\neggs');
    expect(find.text('milk'), findsOneWidget); // the list preview
    await kit.quit();
  });

  testWidgets('quitting saves the last keystrokes (the close hook flushes the controller before the core closes)', (t) async {
    final c = await boot(t);
    await t.tap(find.byKey(const ValueKey('new-note')));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('editor')), 'typed just before quitting');
    await t.pump(const Duration(milliseconds: 10)); // NOT past the pause: still unsaved
    expect(c.hasUnsavedChanges, isTrue);
    final id = c.selectedId!;
    // close() runs the hooks; the core is closed last, so read through a second handle to the same fake state
    await kit.close();
    expect(c.hasUnsavedChanges, isFalse);
    final other = core;
    expect(() => other.getNote(id), throwsA(isA<NotesCoreException>().having((e) => e.code, 'code', 'closed')), reason: 'the core was closed last');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('history lists every save, previews one and restores it as a new version', (t) async {
    final c = await boot(t);
    await t.tap(find.byKey(const ValueKey('new-note')));
    await settle(t);
    await type(t, 'one');
    await type(t, 'one two');
    await type(t, 'one two three');
    final id = c.selectedId!;
    expect((await t.runAsync(() => core.listVersions(id)))!.length, 4); // created empty, then three saves

    await t.tap(find.byKey(const ValueKey('history')));
    await settle(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('history-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('current-chip')), findsOneWidget);
    final versions = (await t.runAsync(() => core.listVersions(id)))!;
    final second = versions[2]; // 'one'
    await t.tap(find.byKey(ValueKey('version-${second.manifest.substring(0, 8)}')));
    await settle(t);
    expect(t.widget<SelectableText>(find.byKey(const ValueKey('preview-body'))).data, 'one');
    await t.tap(find.byKey(const ValueKey('preview-close')));
    await settle(t);

    final blocksBefore = core.blockCount;
    await t.tap(find.byKey(ValueKey('restore-${second.manifest.substring(0, 8)}')));
    await settle(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('history-title')), findsNothing, reason: 'the sheet closes after a restore');
    expect(t.widget<TextField>(find.byKey(const ValueKey('editor'))).controller!.text, 'one');
    expect((await t.runAsync(() => core.getNote(id)))!.body, 'one');
    expect((await t.runAsync(() => core.listVersions(id)))!.length, 5, reason: 'a restore adds a version; nothing is removed');
    expect(core.blockCount, blocksBefore + 1, reason: 'one manifest and no body block');
    await kit.quit();
  });

  testWidgets('a version that was never synced here is listed but cannot be previewed or restored', (t) async {
    // This copy received only the CURRENT version of a note from another copy (sync pulls the head's body, not old bodies).
    final far = FakeNotesCore(device: 'desktop', clock: () => clock += 1000);
    final mine = FakeNotesCore(device: 'laptop', clock: () => clock += 1000);
    final id = (await t.runAsync(() async {
      final n = await far.createNote('Report', 'first draft ' * 800);
      await far.saveNote(n.id, 'Report', 'second draft ' * 800);
      final theirs = await far.heads();
      for (var i = 0; i < 8; i++) {
        final missing = await mine.missingBlocks(theirs);
        if (missing.isEmpty) break;
        await mine.importBlocks(await far.exportBlocks(missing));
      }
      await mine.applyHeads(theirs);
      return n.id;
    }))!;
    await boot(t, with_: mine);
    await t.tap(find.byKey(ValueKey('note-$id')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('history')));
    await settle(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('not on this copy'), findsOneWidget);
    final old = (await t.runAsync(() => mine.listVersions(id)))!.last;
    expect(old.available, isFalse);
    final restore = t.widget<TextButton>(find.byKey(ValueKey('restore-${old.manifest.substring(0, 8)}')));
    expect(restore.onPressed, isNull, reason: 'the button is disabled');
    expect(find.byKey(const ValueKey('current-chip')), findsOneWidget);
    await t.tap(find.byType(ModalBarrier).last);
    await settle(t);
    await kit.quit();
  });

  testWidgets('rename and delete go through the core', (t) async {
    final c = await boot(t);
    await t.tap(find.byKey(const ValueKey('new-note')));
    await settle(t);
    final id = c.selectedId!;
    await t.tap(find.byKey(ValueKey('note-menu-$id')));
    await t.pumpAndSettle();
    await t.tap(find.text('Rename').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('rename-field')), 'Groceries');
    await t.tap(find.byKey(const ValueKey('rename-ok')));
    await settle(t);
    expect((await t.runAsync(() => core.getNote(id)))!.title, 'Groceries');
    expect(find.text('Groceries'), findsWidgets);

    await t.tap(find.byKey(ValueKey('note-menu-$id')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('delete-ok')));
    await settle(t);
    expect((await t.runAsync(core.listNotes))!, isEmpty);
    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect((await t.runAsync(() => core.listVersions(id)))!.length, 3, reason: 'created, renamed, deleted: a delete is a version and the history stays');
    await kit.quit();
  });

  testWidgets('a failing save is reported, the text stays on screen and quitting retries it', (t) async {
    final c = await boot(t);
    await t.tap(find.byKey(const ValueKey('new-note')));
    await settle(t);
    core.failNextWith = const NotesCoreException('io', 'io: disk full');
    await type(t, 'precious words');
    expect(saveText(t), 'Not saved');
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('editor'))).controller!.text, 'precious words');
    expect(c.saveFailed, isTrue);
    await kit.quit(); // the close hook flushes: the retry succeeds
    final again = core;
    expect(again.saveCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('a core that cannot start shows its error instead of crashing', (t) async {
    kit = await pumpKitApp(t,
        manifest: manifestText,
        app: (_) => NotesApp(openCore: (_) async => throw const NotesCoreException('bad_snapshot', 'snapshot field `dirs.data` is not an absolute path'), peers: false));
    await settle(t);
    expect(find.byKey(const ValueKey('core-error')), findsOneWidget);
    expect(find.textContaining('bad_snapshot'), findsOneWidget);
    await kit.quit();
  });

  testWidgets('the owner writes settings: the font size lands in config.json, which the core never touches', (t) async {
    await boot(t);
    await t.tap(find.byKey(const ValueKey('font-larger')));
    await t.pump();
    final cfg = File('${kit.ctx.dirs.config}/config.json');
    expect(jsonDecode(cfg.readAsStringSync()), containsPair('fontSize', 18.0));
    expect(core.saveCalls, 0);
    await kit.quit();
  });

  testWidgets('a note made on the other copy appears on screen and opens', (t) async {
    final net = FakePeerNetwork();
    final c = await boot(t, peers: true, net: net);
    final other = (await t.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('notes-rust-other-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final o = await Copy.open(manifestText, dir, 'desktop', (ctx) async => FakeNotesCore(device: 'desktop', clock: () => clock += 1000));
      await o.startPeers(net, heartbeat: Duration.zero);
      await o.write('From the desktop', 'hello from the other copy');
      return o;
    }))!;
    for (var i = 0; i < 100 && c.notes.isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(c.notes.single.title, 'From the desktop');
    expect(find.text('From the desktop'), findsWidgets);
    expect(find.textContaining('Peers: 1'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('editor'))).controller!.text, 'hello from the other copy');
    await t.runAsync(other.close);
    await kit.quit();
  });
}
