import 'dart:io';
import 'dart:math';

import 'package:application_kit_flutter/testing.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minesweeper/logic/game.dart';
import 'package:minesweeper/ui/game_controller.dart';
import 'package:minesweeper/ui/game_screen.dart';
import 'package:minesweeper/ui/minesweeper_app.dart';

void main() {
  late KitTestContext kit;

  // pumpKitApp: temp scratch dir, mock mode, context opened under runAsync, the app mounted under an AppContextScope.
  // Pass [scratch] to plant files before the app starts, or to start again on the same files.
  Future<GameController> boot(WidgetTester t, {int seed = 42, Directory? scratch}) async {
    kit = await pumpKitApp(t, manifest: File('app.json').readAsStringSync(), app: (_) => MinesweeperApp(rng: Random(seed)), scratch: scratch);
    return t.widget<GameScreen>(find.byType(GameScreen)).controller;
  }

  Directory plantedScratch() {
    final d = Directory.systemTemp.createTempSync('mines-widget-');
    addTearDown(() => d.deleteSync(recursive: true));
    return d;
  }

  // The NotesBanner is always mounted (it renders nothing when there is nothing to say), so "no notice" means no text in it.
  Finder noticeText() => find.descendant(of: find.byKey(const ValueKey('notice')), matching: find.byType(Text));

  Finder cell(int r, int c) => find.byKey(ValueKey('cell-$r-$c'));
  String text(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey(key))).data!;
  Future<void> pickDifficulty(WidgetTester t, Difficulty d) async {
    await t.tap(find.byKey(const ValueKey('difficulty-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('difficulty-${d.name}')));
    await t.pumpAndSettle();
  }

  testWidgets('starts a beginner game from an empty data directory', (t) async {
    await boot(t);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('cell-')), findsNWidgets(81));
    expect(text(t, 'mines-left'), '010');
    expect(text(t, 'timer'), '000');
    expect(text(t, 'status-text'), 'Click any square to start.');
    expect(find.text('mock + scratch'), findsOneWidget);
    expect(noticeText(), findsNothing); // the Venue "off" note is not a problem
    await kit.quit();
  });

  testWidgets('the first click is safe, starts the timer, and a flag changes the mine counter', (t) async {
    final c = await boot(t);
    await t.tap(cell(4, 4));
    await t.pump();
    expect(c.game.status, GameStatus.playing);
    expect(c.game.at(4, 4).mine, isFalse);
    await t.pump(const Duration(seconds: 3));
    expect(text(t, 'timer'), '003');

    final closed = [for (var r = 0; r < 9; r++) for (var col = 0; col < 9; col++) if (!c.game.at(r, col).revealed) (r, col)].first;
    await t.tap(cell(closed.$1, closed.$2), buttons: kSecondaryButton);
    await t.pump();
    expect(text(t, 'mines-left'), '009');
    await kit.quit();
  });

  testWidgets('clicking a mine loses and the face resets the game', (t) async {
    final c = await boot(t);
    await t.tap(cell(4, 4));
    await t.pump();
    final mine = [for (var r = 0; r < 9; r++) for (var col = 0; col < 9; col++) if (c.game.at(r, col).mine) (r, col)].first;
    await t.tap(cell(mine.$1, mine.$2));
    await t.pump();
    expect(c.game.status, GameStatus.lost);
    expect(text(t, 'status-text'), startsWith('Boom'));
    await t.tap(find.byKey(const ValueKey('new-game')));
    await t.pump();
    expect(c.game.status, GameStatus.ready);
    expect(text(t, 'timer'), '000');
    await kit.quit();
  });

  testWidgets('winning records a high score, shown in the scores dialog and kept on disk', (t) async {
    final c = await boot(t);
    await t.tap(cell(4, 4));
    await t.pump(const Duration(seconds: 5));
    for (var r = 0; r < 9; r++) {
      for (var col = 0; col < 9; col++) {
        if (!c.game.at(r, col).mine && !c.game.at(r, col).revealed) c.reveal(r, col);
      }
    }
    await t.pump();
    expect(c.game.status, GameStatus.won);
    expect(text(t, 'status-text'), 'You won in 5 s (rank 1).');
    expect(File('${kit.ctx.dirs.data}/game.json').existsSync(), isFalse); // a finished game is not kept for resuming
    await t.tap(find.byKey(const ValueKey('scores-button')));
    await t.pumpAndSettle();
    expect(text(t, 'score-beginner-0'), '1.  5 s');
    expect(find.byKey(const ValueKey('scores-empty-expert')), findsOneWidget);
    expect(File('${kit.ctx.dirs.data}/scores.json').existsSync(), isTrue);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await kit.quit();
  });

  testWidgets('quitting and reopening resumes the game in progress', (t) async {
    var c = await boot(t);
    await t.tap(cell(4, 4));
    await t.pump(const Duration(seconds: 7));
    c.flag(0, 0);
    await t.pump();
    final before = c.game.toJson();
    await kit.quit();

    await kit.reopen(); // a new context on the same scratch files
    await kit.mount((_) => MinesweeperApp(rng: Random(999))); // a different seed: the board must come from the file, not the generator
    c = t.widget<GameScreen>(find.byType(GameScreen)).controller;
    expect(c.game.toJson(), before);
    expect(text(t, 'timer'), '007');
    expect(c.game.at(0, 0).mark, Mark.flag);
    await kit.quit();
  });

  testWidgets('difficulty and question marks are remembered', (t) async {
    await boot(t);
    await pickDifficulty(t, Difficulty.expert);
    expect(text(t, 'difficulty-label'), 'Expert');
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('cell-')), findsNWidgets(480));
    await t.tap(find.byKey(const ValueKey('settings-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('question-marks')));
    await t.pumpAndSettle();
    await kit.quit();

    await kit.reopen();
    await kit.mount((_) => MinesweeperApp(rng: Random(42)));
    final c = t.widget<GameScreen>(find.byType(GameScreen)).controller;
    expect(text(t, 'difficulty-label'), 'Expert');
    expect(c.game.difficulty, Difficulty.expert);
    expect(c.settings.questionMarks, isTrue);
    // two right-clicks now give a question mark
    await t.tap(cell(0, 0), buttons: kSecondaryButton);
    await t.tap(cell(0, 0), buttons: kSecondaryButton);
    await t.pump();
    expect(c.game.at(0, 0).mark, Mark.question);
    expect(find.text('?'), findsOneWidget);
    await kit.quit();
  });

  testWidgets('a damaged saved game is set aside, reported, and a fresh game starts', (t) async {
    final scratch = plantedScratch();
    final dataDir = Directory('${scratch.path}/dev.demo.minesweeper/data')..createSync(recursive: true);
    File('${dataDir.path}/game.json').writeAsStringSync('{"difficulty": "beginner", "status": "pla');
    final c = await boot(t, scratch: scratch);
    expect(c.game.status, GameStatus.ready);
    expect(noticeText(), findsOneWidget);
    expect(find.textContaining('saved game file was damaged'), findsOneWidget);
    expect(dataDir.listSync().where((f) => f.path.contains('game.json.damaged-')), hasLength(1));
    await t.tap(find.byTooltip('Dismiss Warning'));
    await t.pump();
    expect(noticeText(), findsNothing);
    await kit.quit();
  });

  testWidgets('a damaged config.json is reported and never overwritten, even after changing a setting', (t) async {
    final scratch = plantedScratch();
    final cfgDir = Directory('${scratch.path}/dev.demo.minesweeper/config')..createSync(recursive: true);
    final cfg = File('${cfgDir.path}/config.json')..writeAsStringSync('{"difficulty": ');
    await boot(t, scratch: scratch);
    expect(find.textContaining('Settings: config.json is not valid UTF-8 JSON'), findsOneWidget);
    expect(find.textContaining('read-only this session'), findsOneWidget);
    await pickDifficulty(t, Difficulty.intermediate);
    expect(text(t, 'difficulty-label'), 'Intermediate');
    expect(cfg.readAsStringSync(), '{"difficulty": ');
    await kit.quit();
    expect(cfg.readAsStringSync(), '{"difficulty": ');
  });

  testWidgets('everything the app wrote is under the scratch directory', (t) async {
    final c = await boot(t);
    await t.tap(cell(4, 4));
    await t.pump();
    await kit.quit();
    expect(c.storage, isNotNull);
    final outside = [for (final d in kit.ctx.dirs.all) if (!d.startsWith(kit.scratch.path)) d];
    expect(outside, isEmpty);
    expect(File('${kit.ctx.dirs.data}/game.json').existsSync(), isTrue);
  });
}
