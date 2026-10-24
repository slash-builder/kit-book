import 'dart:io';
import 'dart:math';

import 'package:application_kit/application_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minesweeper/logic/game.dart';
import 'package:minesweeper/logic/scores.dart';
import 'package:minesweeper/logic/settings.dart';
import 'package:minesweeper/logic/storage.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mines-storage-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  GameStorage storage() => GameStorage(tmp.path);
  File gameFile() => File('${tmp.path}/game.json');
  List<String> damaged(String prefix) => [for (final f in tmp.listSync()) if (f.path.split('/').last.startsWith(prefix)) f.path];

  test('no saved game is not a problem', () {
    final l = storage().loadGame();
    expect(l.value, isNull);
    expect(l.problem, isNull);
  });

  test('a saved game comes back', () {
    final g = Minesweeper(Difficulty.beginner, rng: Random(2))..reveal(4, 4);
    storage().saveGame(g);
    final l = storage().loadGame();
    expect(l.problem, isNull);
    expect(l.value!.toJson(), g.toJson());
    expect(File('${tmp.path}/game.json.tmp').existsSync(), isFalse); // atomic write leaves no temp file
  });

  test('clearGame removes it', () {
    storage().saveGame(Minesweeper(Difficulty.beginner));
    storage().clearGame();
    expect(gameFile().existsSync(), isFalse);
    storage().clearGame(); // and is fine when there is nothing to remove
  });

  for (final (name, bytes) in [
    ('not json', '{oops'.codeUnits),
    ('json of the wrong shape', '[1,2,3]'.codeUnits),
    ('a game that does not add up', '{"difficulty":"beginner","status":"playing","seconds":1,"cells":[]}'.codeUnits),
    ('binary garbage', [0xff, 0xfe, 0x80, 0x00]),
  ]) {
    test('a damaged game ($name) is set aside, not deleted or overwritten', () {
      gameFile().writeAsBytesSync(bytes);
      final l = storage().loadGame();
      expect(l.value, isNull);
      expect(l.problem, contains('saved game'));
      expect(gameFile().existsSync(), isFalse);
      final kept = damaged('game.json.damaged-');
      expect(kept, hasLength(1));
      expect(File(kept.single).readAsBytesSync(), bytes);
      expect(l.problem, contains(kept.single));
    });
  }

  test('scores round-trip and damaged scores are set aside', () {
    final s = HighScores()..add(Difficulty.beginner, 33, DateTime.utc(2026, 1, 1));
    storage().saveScores(s);
    expect(storage().loadScores().value.best(Difficulty.beginner)!.seconds, 33);
    File('${tmp.path}/scores.json').writeAsStringSync('}{');
    final l = storage().loadScores();
    expect(l.value.best(Difficulty.beginner), isNull);
    expect(l.problem, contains('high scores'));
    expect(damaged('scores.json.damaged-'), hasLength(1));
  });

  group('settings through the Kit', () {
    final manifest = AppManifest.fromJson({'id': 'dev.demo.minesweeper', 'name': 'Minesweeper', 'version': '0.1.0', 'envPrefix': 'MINES'});
    Map<String, String> env() => {'APPKIT_SCRATCH': tmp.path, 'MINES_MODE': 'mock'};

    test('difficulty and question marks persist across opens', () async {
      var ctx = await AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);
      var s = Settings(SessionSettings(ctx.config));
      expect(s.difficulty, Difficulty.beginner);
      expect(s.questionMarks, isFalse);
      s.difficulty = Difficulty.expert;
      s.questionMarks = true;
      await ctx.close();
      ctx = await AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);
      s = Settings(SessionSettings(ctx.config));
      expect(s.difficulty, Difficulty.expert);
      expect(s.questionMarks, isTrue);
      await ctx.close();
    });

    test('an unknown difficulty in the file falls back to beginner', () async {
      final dir = Directory('${tmp.path}/dev.demo.minesweeper/config')..createSync(recursive: true);
      File('${dir.path}/config.json').writeAsStringSync('{"difficulty":"nightmare","questionMarks":"yes"}');
      final ctx = await AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);
      final s = Settings(SessionSettings(ctx.config));
      expect(s.difficulty, Difficulty.beginner);
      expect(s.questionMarks, isFalse);
      await ctx.close();
    });

    test('a damaged config.json is reported and left exactly as it was', () async {
      final dir = Directory('${tmp.path}/dev.demo.minesweeper/config')..createSync(recursive: true);
      final f = File('${dir.path}/config.json')..writeAsStringSync('{broken');
      final ctx = await AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);
      expect(ctx.noteTexts.any((n) => n.startsWith('Settings:')), isTrue);
      expect(ctx.notes.any((n) => n.severity == NoteSeverity.warning), isTrue);
      final s = Settings(SessionSettings(ctx.config));
      expect(s.readOnly, isTrue);
      s.difficulty = Difficulty.expert;
      expect(s.difficulty, Difficulty.expert); // holds for the session
      expect(f.readAsStringSync(), '{broken');
      await ctx.close();
    });

    test('a config.json that is not text does not stop the app starting, and is left exactly as it was', () async {
      final dir = Directory('${tmp.path}/dev.demo.minesweeper/config')..createSync(recursive: true);
      final f = File('${dir.path}/config.json')..writeAsBytesSync([0xff, 0xfe, 0x80]);
      // Round 1 needed a pre-flight (kit_gaps/survivable_open.dart) for this: the Kit threw FileSystemException. Now it opens.
      final ctx = await AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);
      expect(ctx.noteTexts.any((n) => n.startsWith('Settings:') && n.contains('UTF-8')), isTrue);
      final s = Settings(SessionSettings(ctx.config));
      expect(s.readOnly, isTrue);
      s.questionMarks = true;
      expect(s.questionMarks, isTrue); // holds for the session
      expect(f.readAsBytesSync(), [0xff, 0xfe, 0x80]);
      expect(dir.listSync().map((e) => e.path.split('/').last), ['config.json']); // nothing renamed, nothing added
      await ctx.close();
    });

    test('the Kit itself refuses to write over a damaged config.json (DamagedConfigError)', () async {
      final dir = Directory('${tmp.path}/dev.demo.minesweeper/config')..createSync(recursive: true);
      final f = File('${dir.path}/config.json')..writeAsStringSync('{broken');
      final ctx = await AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);
      expect(() => ctx.config.set('difficulty', 'expert'), throwsA(isA<DamagedConfigError>()));
      expect(f.readAsStringSync(), '{broken');
      await ctx.close();
    });
  });
}
