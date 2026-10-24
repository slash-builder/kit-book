import 'package:flutter_test/flutter_test.dart';
import 'package:minesweeper/logic/game.dart';
import 'package:minesweeper/logic/scores.dart';

void main() {
  final t = DateTime.utc(2026, 10, 21);

  test('ranks fastest first and keeps difficulties apart', () {
    final s = HighScores();
    expect(s.add(Difficulty.beginner, 50, t), 1);
    expect(s.add(Difficulty.beginner, 30, t), 1);
    expect(s.add(Difficulty.beginner, 40, t), 2);
    expect(s.add(Difficulty.expert, 200, t), 1);
    expect(s.of(Difficulty.beginner).map((e) => e.seconds), [30, 40, 50]);
    expect(s.best(Difficulty.intermediate), isNull);
  });

  test('a tie ranks below the older score', () {
    final s = HighScores()..add(Difficulty.beginner, 30, t);
    expect(s.add(Difficulty.beginner, 30, t), 2);
  });

  test('only ten are kept', () {
    final s = HighScores();
    for (var i = 1; i <= 10; i++) {
      s.add(Difficulty.beginner, i * 10, t);
    }
    expect(s.add(Difficulty.beginner, 500, t), isNull);
    expect(s.of(Difficulty.beginner), hasLength(10));
    expect(s.add(Difficulty.beginner, 5, t), 1);
    expect(s.of(Difficulty.beginner).last.seconds, 90);
  });

  test('round-trips through json', () {
    final s = HighScores()
      ..add(Difficulty.beginner, 12, t)
      ..add(Difficulty.expert, 300, t);
    final back = HighScores.fromJson(s.toJson());
    expect(back.of(Difficulty.beginner).single.seconds, 12);
    expect(back.of(Difficulty.beginner).single.when, t);
    expect(back.of(Difficulty.expert).single.seconds, 300);
  });

  test('refuses damaged data', () {
    expect(() => HighScores.fromJson([]), throwsFormatException);
    expect(() => HighScores.fromJson({'beginner': 'x'}), throwsFormatException);
    expect(() => HighScores.fromJson({'beginner': [{'s': 'fast'}]}), throwsFormatException);
    expect(() => HighScores.fromJson({'beginner': [{'s': 3, 'at': 'yesterday'}]}), throwsFormatException);
  });
}
