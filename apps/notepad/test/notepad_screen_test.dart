import 'dart:convert';
import 'dart:io';

import 'package:app_context_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';
import 'package:notepad/ui/notepad_app.dart';
import 'package:notepad/ui/notepad_screen.dart';
import 'package:notepad/ui/notes_controller.dart';

void main() {
  late KitTestContext kit;

  Directory notesDir() => Directory('${kit.scratch.path}/com.slashbuilder.demo.notepad/data/notes');
  Directory configDir() => Directory('${kit.scratch.path}/com.slashbuilder.demo.notepad/config');
  File configFile() => File('${configDir().path}/config.json');

  NotesController controller(WidgetTester t) => t.widget<NotepadScreen>(find.byType(NotepadScreen)).controller;

  // pumpKitApp: temp scratch dir, mock mode, context opened under runAsync, the app mounted under an AppContextScope.
  // Pass [scratch] to plant files before the app starts.
  Future<NotesController> boot(WidgetTester t, {Directory? scratch}) async {
    kit = await pumpKitApp(t,
        manifest: File('app.json').readAsStringSync(), app: (_) => const NotepadApp(autosaveDelay: Duration(milliseconds: 300)), scratch: scratch);
    return controller(t);
  }

  Directory plantedScratch() {
    final d = Directory.systemTemp.createTempSync('notepad-widget-');
    addTearDown(() => d.deleteSync(recursive: true));
    return d;
  }

  // The NotesBanner is always mounted (it renders nothing when there is nothing to say), so "no notice" means no text in it.
  Finder noticeText() => find.descendant(of: find.byKey(const ValueKey('notice')), matching: find.byType(Text));

  String text(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey(key))).data!;
  // The save-status chip (Interface Kit candidate) has no key; it is the only SaveStatusChip on screen.
  String saveText(WidgetTester t) => t.widget<Text>(find.descendant(of: find.byType(SaveStatusChip), matching: find.byType(Text))).data!;
  List<File> noteFiles() => notesDir().existsSync() ? notesDir().listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList() : [];
  Map<String, dynamic> readNote(File f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

  Future<void> menu(WidgetTester t, NotesController c, String id, String item) async {
    await t.tap(find.byKey(ValueKey('note-menu-$id')));
    await t.pumpAndSettle();
    await t.tap(find.text(item).last);
    await t.pumpAndSettle();
  }

  testWidgets('first run shows the empty state and creates its directories under the scratch root', (t) async {
    await boot(t);
    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    expect(find.text('mock + scratch'), findsOneWidget);
    expect(noticeText(), findsNothing);
    expect(kit.ctx.dirs.data.startsWith(kit.scratch.path), isTrue);
    await kit.quit();
  });

  testWidgets('create a note, type, and it autosaves after the pause', (t) async {
    final c = await boot(t);
    await t.tap(find.text('Create a note'));
    await t.pump();
    expect(noteFiles(), hasLength(1));
    await t.enterText(find.byKey(const ValueKey('editor')), 'remember the milk');
    await t.pump();
    expect(saveText(t), 'Saving...');
    expect(readNote(noteFiles().single)['body'], ''); // not yet written
    await t.pump(const Duration(milliseconds: 400));
    expect(readNote(noteFiles().single)['body'], 'remember the milk');
    expect(saveText(t), 'Saved');
    expect(c.notes.single.body, 'remember the milk');
    await kit.quit();
  });

  testWidgets('quitting right after typing still saves (flush on close)', (t) async {
    await boot(t);
    await t.tap(find.text('Create a note'));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor')), 'typed a moment ago');
    await t.pump(const Duration(milliseconds: 50)); // well inside the autosave delay
    expect(readNote(noteFiles().single)['body'], '');
    await kit.quit();
    expect(readNote(noteFiles().single)['body'], 'typed a moment ago');
  });

  testWidgets('switching notes saves the one you leave', (t) async {
    final c = await boot(t);
    c.create();
    await t.pump();
    c.create();
    await t.pump();
    final first = c.notes.last.id;
    await t.enterText(find.byKey(const ValueKey('editor')), 'second note text');
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byKey(ValueKey('note-$first')));
    await t.pump();
    final saved = noteFiles().map(readNote).where((n) => n['body'] == 'second note text');
    expect(saved, hasLength(1));
    await kit.quit();
  });

  testWidgets('rename keeps the text and persists', (t) async {
    final c = await boot(t);
    c.create();
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor')), 'body text');
    await t.pump(const Duration(milliseconds: 400));
    final id = c.notes.single.id;
    await menu(t, c, id, 'Rename');
    await t.enterText(find.byKey(const ValueKey('rename-field')), 'Groceries');
    await t.tap(find.byKey(const ValueKey('rename-ok')));
    await t.pumpAndSettle();
    expect(text(t, 'editor-title'), 'Groceries');
    final saved = readNote(noteFiles().single);
    expect((saved['title'], saved['body']), ('Groceries', 'body text'));
    await kit.quit();
  });

  testWidgets('a narrow window shows the list, then the editor with a Back button (PageScaffold.masterDetail)', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = await boot(t);
    expect(find.byKey(const ValueKey('new-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor')), findsNothing); // the list alone
    await t.tap(find.byKey(const ValueKey('new-note')));
    await t.pump();
    expect(find.byKey(const ValueKey('editor')), findsOneWidget); // the editor alone
    expect(find.byKey(const ValueKey('new-note')), findsNothing);
    await t.tap(find.byTooltip('Back'));
    await t.pump();
    expect(find.byKey(const ValueKey('new-note')), findsOneWidget);
    expect(c.notes, hasLength(1));
    await kit.quit();
  });

  testWidgets('the delete dialog (confirmDialog, destructive) puts the focus on Cancel, not on Delete', (t) async {
    final c = await boot(t);
    c.create();
    await t.pump();
    await menu(t, c, c.notes.single.id, 'Delete');
    final cancel = t.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'));
    expect(cancel.autofocus, isTrue);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(noteFiles(), hasLength(1));
    await kit.quit();
  });

  testWidgets('delete asks first, and removes the file only when confirmed', (t) async {
    final c = await boot(t);
    c.create();
    await t.pump();
    final id = c.notes.single.id;
    await menu(t, c, id, 'Delete');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(noteFiles(), hasLength(1));
    await menu(t, c, id, 'Delete');
    await t.tap(find.byKey(const ValueKey('delete-ok')));
    await t.pumpAndSettle();
    expect(noteFiles(), isEmpty);
    expect(find.byKey(const ValueKey('empty-state')), findsOneWidget);
    await kit.quit();
  });

  testWidgets('font size changes persist through the Kit config store', (t) async {
    await boot(t);
    expect(text(t, 'font-size'), '16');
    await t.tap(find.byKey(const ValueKey('font-larger')));
    await t.tap(find.byKey(const ValueKey('font-larger')));
    await t.pump();
    expect(text(t, 'font-size'), '20');
    await kit.quit();

    await kit.relaunch();
    expect(text(t, 'font-size'), '20');
    await kit.quit();
  });

  testWidgets('the editor uses the configured font size', (t) async {
    final c = await boot(t);
    c.create();
    await t.pump();
    double size() => t.widget<TextField>(find.byKey(const ValueKey('editor'))).style!.fontSize!;
    expect(size(), 16);
    await t.tap(find.byKey(const ValueKey('font-larger')));
    await t.pump();
    expect(size(), 18);
    await kit.quit();
  });

  testWidgets('notes are there after quitting and reopening, newest first', (t) async {
    var c = await boot(t);
    c.create();
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor')), 'older');
    await t.pump(const Duration(milliseconds: 400));
    c.create();
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor')), 'newer');
    await t.pump(const Duration(milliseconds: 400));
    await kit.quit();

    await kit.relaunch();
    c = controller(t);
    expect(c.notes.map((n) => n.body), ['newer', 'older']);
    expect(find.text('newer'), findsWidgets);
    await kit.quit();
  });

  group('survival', () {
    testWidgets('a corrupt note file is reported, shown as damaged, left untouched, and the other notes load', (t) async {
      var c = await boot(t);
      c.create();
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('editor')), 'precious');
      await t.pump(const Duration(milliseconds: 400));
      await kit.quit();

      final bad = File('${notesDir().path}/broken1.json')..writeAsStringSync('{"id": "broken1", "title": "half');
      final bin = File('${notesDir().path}/binary1.json')..writeAsBytesSync([0xff, 0xfe, 0x80]);
      final badBefore = bad.readAsBytesSync();

      await kit.reopen(); // the damaged files are planted while the app is down
      await kit.mount((_) => const NotepadApp(autosaveDelay: Duration(milliseconds: 300)));
      c = controller(t);
      expect(c.notes.single.body, 'precious');
      expect(noticeText(), findsNWidgets(2)); // one row per damaged file (round 1 joined them in one box)
      expect(find.textContaining('broken1.json'), findsWidgets);
      expect(find.byKey(const ValueKey('damaged-broken1.json')), findsOneWidget);
      expect(find.byKey(const ValueKey('damaged-binary1.json')), findsOneWidget);
      expect(kit.ctx.noteTexts.where((n) => n.contains('broken1.json')), hasLength(1)); // reported through ctx.notes

      // work normally; nothing may touch the damaged files
      c.create();
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('editor')), 'new work');
      await t.pump(const Duration(milliseconds: 400));
      c.delete(c.notes.first.id);
      await t.pump();
      await kit.quit();
      expect(bad.readAsBytesSync(), badBefore);
      expect(bin.readAsBytesSync(), [0xff, 0xfe, 0x80]);
    });

    testWidgets('a corrupt config.json is reported and never overwritten, and the app still works', (t) async {
      final scratch = plantedScratch();
      final cfg = File('${scratch.path}/com.slashbuilder.demo.notepad/config/config.json')..createSync(recursive: true);
      cfg.writeAsStringSync('{"fontSize": 22, "other": "keep me", ');
      final before = cfg.readAsStringSync();
      final c = await boot(t, scratch: scratch);
      expect(find.textContaining('Settings: config.json is not valid UTF-8 JSON'), findsOneWidget);
      expect(text(t, 'font-size'), '16');
      await t.tap(find.byKey(const ValueKey('font-larger')));
      await t.pump();
      expect(text(t, 'font-size'), '18'); // works for this session
      c.create();
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('editor')), 'notes still work');
      await t.pump(const Duration(milliseconds: 400));
      expect(readNote(noteFiles().single)['body'], 'notes still work');
      await kit.quit();
      expect(configFile().readAsStringSync(), before);
    });

    testWidgets('a config.json that is not even text does not stop the app starting and is left exactly as it was', (t) async {
      final scratch = plantedScratch();
      final cfg = File('${scratch.path}/com.slashbuilder.demo.notepad/config/config.json')..createSync(recursive: true);
      cfg.writeAsBytesSync([0xff, 0xfe, 0x80, 0x00]);
      // Round 1: the Kit threw FileSystemException here and the app renamed the file aside before opening. Now the Kit opens,
      // reports it, and the file stays where it is.
      final c = await boot(t, scratch: scratch);
      expect(find.textContaining('Settings: config.json is not valid UTF-8 JSON'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('font-larger')));
      await t.pump();
      expect(text(t, 'font-size'), '18'); // works for this session
      expect(c.notes, isEmpty);
      await kit.quit();
      expect(cfg.readAsBytesSync(), [0xff, 0xfe, 0x80, 0x00]);
      expect(cfg.parent.listSync().map((e) => e.path.split('/').last), ['config.json']); // nothing renamed, nothing added
    });

    testWidgets('a note that cannot be written is reported and the text stays on screen', (t) async {
      final c = await boot(t);
      c.create();
      await t.pump();
      // make the note's file unwritable by turning its path into a directory
      final f = noteFiles().single;
      final tmpPath = '${f.path}.tmp';
      Directory(tmpPath).createSync(); // the atomic write's temp file name is now taken by a directory
      await t.enterText(find.byKey(const ValueKey('editor')), 'cannot hit disk');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(saveText(t), 'Not saved');
      expect(c.notes.single.body, 'cannot hit disk');
      Directory(tmpPath).deleteSync();
      expect(c.hasUnsavedChanges, isTrue);
      await kit.quit(); // the problem is gone; quitting retries the save
      expect(readNote(noteFiles().single)['body'], 'cannot hit disk');
    });
  });
}
