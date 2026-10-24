// Runs INSIDE the built app (`flutter test integration_test -d macos`), so the Rust core is the real native library and the
// Storage Kit writes real packfiles. The same contract and sync scenarios as test/, plus what only the real pair can show: one
// Application Kit context shared by the Dart UI and the Rust core.
import 'dart:convert';
import 'dart:io';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/testing.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notes_rust/core/frb_notes_core.dart';
import 'package:notes_rust/core/notes_core.dart';
import 'package:notes_rust/src/rust/frb_generated.dart';
import 'package:notes_rust/ui/notes_app.dart';
import 'package:notes_rust/ui/notes_screen.dart';

import '../test/support/contract.dart';
import '../test/support/scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String manifestText;

  setUpAll(() async {
    await RustLib.init();
    manifestText = await rootBundle.loadString('app.json');
  });

  // ---- the contract, on the real core ----
  coreContract('real Rust core', (device) async {
    final root = Directory.systemTemp.createTempSync('notes-rust-contract-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final ctx = await AppContext.open(AppManifest.parse(manifestText),
        env: {'APPKIT_SCRATCH': root.path, 'APPKIT_MODE': 'mock', 'APPKIT_DEVICE': device, 'HOME': root.path}, announce: false);
    return FrbNotesCore.open(ctx);
  });

  // ---- sync scenarios, on the real core ----
  group('sync over the Kit peer layer, real core', () {
    Scenarios scenarios() => Scenarios(manifestText, FrbNotesCore.open);

    test('two copies converge on notes made, edited and deleted on either side', () => scenarios().convergence());

    test('a one-byte edit of a 10 MiB note moves a small part of it, in parts of at most 24 KiB', () async {
      final (cold, edit, body) = await scenarios().smallEdit(10 * 1024 * 1024);
      // ignore: avoid_print
      print('REAL CORE: cold sync ${cold}B, one-byte edit ${edit}B, body ${body}B (${(edit * 100 / body).toStringAsFixed(2)}%)');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('a tampered block is refused, nothing is stored, and an honest retry works', () => scenarios().tamperedBlockIsRefused());

    test('a conflict keeps both versions and both copies end up the same', () => scenarios().conflictKeepsBothAndConverges());
  });

  // ---- one context, two halves ----
  group('one Application Kit context shared by the Dart UI and the Rust core', () {
    testWidgets('the app running with both halves up has exactly one roster entry, one instance id, and Dart wrote config.json', (t) async {
      final kit = await pumpKitApp(t,
          manifest: manifestText,
          announce: true,
          env: {'APPKIT_DEVICE': 'laptop', 'APPKIT_MODE': 'real'},
          app: (_) => NotesApp(openCore: FrbNotesCore.open, autosaveDelay: const Duration(milliseconds: 100), peers: false));
      for (var i = 0; i < 100; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 20));
        if (find.byType(NotesScreen).evaluate().isNotEmpty) break;
      }
      final controller = t.widget<NotesScreen>(find.byType(NotesScreen)).controller;
      await t.runAsync(() async {
        await controller.create();
        controller.edit(controller.selectedId!, 'written through the real core');
        await controller.flush();
      });
      await t.pump(const Duration(milliseconds: 50));

      final ctx = kit.ctx;
      final roster = Directory(ctx.resolved.roster).listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList();
      expect(roster, ['dev.demo.notes-rust@${ctx.instance}.json'], reason: 'one roster file, written by the Dart side');
      final entries = ctx.roster.scan();
      expect(entries, hasLength(1));
      expect(entries.single.entry!.instance, ctx.instance);

      final stats = controller.stats!;
      expect(stats.instance, ctx.instance, reason: 'the Rust core reports the Dart side\'s instance id: it opened none of its own');
      expect(stats.dataDir, ctx.dirs.data);
      expect(stats.mode, 'real');

      // The core created its files under data, and only there.
      expect(Directory('${ctx.dirs.data}/blocks').existsSync(), isTrue);
      expect(Directory(ctx.dirs.data).listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last), containsAll(['blocks']));
      expect(Directory(ctx.dirs.data).listSync().whereType<File>().any((f) => f.path.contains('heads-')), isTrue);
      expect(Directory(ctx.dirs.config).listSync().map((e) => e.uri.pathSegments.last), isNot(contains('heads-')));

      // Settings: Dart writes, Rust reads.
      final config = File('${ctx.dirs.config}/config.json');
      ctx.config.set('maxNoteBytes', 16);
      final written = config.readAsStringSync();
      expect(jsonDecode(written), {'maxNoteBytes': 16});
      expect((await t.runAsync(() => controller.core.stats()))!.maxNoteBytes, 16, reason: 'the core reads the owner\'s setting');
      await t.runAsync(() => expectLater(controller.core.createNote('x', 'a body of more than sixteen bytes'),
          throwsA(isA<NotesCoreException>().having((x) => x.code, 'code', 'too_large'))));
      expect(config.readAsStringSync(), written, reason: 'the core never writes config.json');

      await kit.quit();
      expect(Directory(ctx.resolved.roster).listSync().whereType<File>(), isEmpty, reason: 'the owner withdrew its roster entry on quit');
    });

    test('opening the core with a snapshot that is not absolute is a typed error, not a crash', () async {
      final bad = <String, Object?>{
        'schema': 1,
        'appId': 'dev.demo.notes-rust',
        'instance': '0a1b2c3d',
        'mode': 'real',
        'scratch': false,
        'dirs': {'data': 'relative', 'config': '/c', 'state': '/s', 'cache': '/k', 'runtime': '/r'},
        'roster': '/r',
      };
      await expectLater(FrbNotesCore.openWith(snapshot: bad, account: 'local', device: 'laptop'),
          throwsA(isA<NotesCoreException>().having((e) => e.code, 'code', 'bad_snapshot')));
    });
  });
}
