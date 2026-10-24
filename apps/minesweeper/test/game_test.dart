import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:minesweeper/logic/game.dart';

/// A beginner board with one mine at each of the given cells.
Minesweeper board(Set<(int, int)> mines) => Minesweeper.withMines(Difficulty.beginner, mines);

int mineCount(Minesweeper g) => [for (var r = 0; r < g.rows; r++) for (var c = 0; c < g.cols; c++) if (g.at(r, c).mine) 1].length;

void main() {
  group('sizes', () {
    test('the three difficulties', () {
      expect((Difficulty.beginner.rows, Difficulty.beginner.cols, Difficulty.beginner.mines), (9, 9, 10));
      expect((Difficulty.intermediate.rows, Difficulty.intermediate.cols, Difficulty.intermediate.mines), (16, 16, 40));
      expect((Difficulty.expert.rows, Difficulty.expert.cols, Difficulty.expert.mines), (16, 30, 99));
    });
  });

  group('first click', () {
    test('places no mines before the first reveal', () {
      final g = Minesweeper(Difficulty.beginner, rng: Random(1));
      expect(g.status, GameStatus.ready);
      expect(mineCount(g), 0);
    });

    for (final d in Difficulty.values) {
      test('is always safe and the right number of mines are placed (${d.name})', () {
        for (var seed = 0; seed < 25; seed++) {
          final g = Minesweeper(d, rng: Random(seed));
          final r = seed % d.rows, c = (seed * 7) % d.cols;
          g.reveal(r, c);
          expect(g.at(r, c).mine, isFalse, reason: 'seed $seed');
          expect(g.at(r, c).revealed, isTrue);
          expect(mineCount(g), d.mines);
          expect(g.status == GameStatus.playing || g.status == GameStatus.won, isTrue);
          // neighbours are safe too, so the first click opens an area
          for (final (nr, nc) in g.neighbours(r, c)) {
            expect(g.at(nr, nc).mine, isFalse, reason: 'seed $seed neighbour');
          }
        }
      });
    }

    test('the same seed gives the same board', () {
      List<int> layout(int seed) {
        final g = Minesweeper(Difficulty.beginner, rng: Random(seed))..reveal(4, 4);
        return [for (var i = 0; i < 81; i++) if (g.at(i ~/ 9, i % 9).mine) i];
      }

      expect(layout(7), layout(7));
      expect(layout(7), isNot(layout(8)));
    });
  });

  group('adjacency and flood reveal', () {
    test('counts neighbouring mines', () {
      final g = board({(0, 0), (0, 1), (8, 8)});
      expect(g.at(1, 0).adjacent, 2);
      expect(g.at(1, 1).adjacent, 2);
      expect(g.at(0, 2).adjacent, 1);
      expect(g.at(4, 4).adjacent, 0);
      expect(g.at(7, 7).adjacent, 1);
    });

    test('revealing a zero opens the connected area and its numbered border only', () {
      final g = board({(0, 0)});
      g.reveal(8, 8);
      expect(g.at(8, 8).revealed, isTrue);
      expect(g.at(1, 1).revealed, isTrue); // a 1, on the border
      expect(g.at(0, 0).revealed, isFalse);
      expect(g.revealedCount, 80); // everything but the mine
      expect(g.status, GameStatus.won);
    });

    test('flood stops at numbers', () {
      final g = board({(0, 4), (4, 0), (8, 4), (4, 8)});
      g.reveal(4, 4);
      expect(g.at(4, 4).revealed, isTrue);
      expect(g.at(0, 4).revealed, isFalse);
      expect(g.at(1, 4).adjacent, 1);
    });

    test('flood does not open flagged cells', () {
      final g = board({(0, 0)});
      g.toggleMark(5, 5);
      g.reveal(8, 8);
      expect(g.at(5, 5).revealed, isFalse);
      expect(g.at(5, 5).mark, Mark.flag);
      expect(g.status, GameStatus.playing); // the wrong flag blocks the win
      g.toggleMark(5, 5); // unflag
      g.reveal(5, 5);
      expect(g.status, GameStatus.won);
    });

    test('a numbered cell opens by itself', () {
      final g = board({(0, 0)});
      g.reveal(0, 1);
      expect(g.at(0, 1).revealed, isTrue);
      expect(g.revealedCount, 1);
    });
  });

  group('flags', () {
    test('toggle none, flag, none', () {
      final g = board({(0, 0)});
      g.toggleMark(3, 3);
      expect(g.at(3, 3).mark, Mark.flag);
      expect(g.minesLeft, 0);
      g.toggleMark(3, 3);
      expect(g.at(3, 3).mark, Mark.none);
      expect(g.minesLeft, 1);
    });

    test('with question marks the cycle has a third state', () {
      final g = board({(0, 0)});
      g.toggleMark(3, 3, questionMarks: true);
      g.toggleMark(3, 3, questionMarks: true);
      expect(g.at(3, 3).mark, Mark.question);
      expect(g.minesLeft, 1);
      g.toggleMark(3, 3, questionMarks: true);
      expect(g.at(3, 3).mark, Mark.none);
    });

    test('a question mark left from before the setting was turned off clears cleanly', () {
      final g = board({(0, 0)});
      g.toggleMark(3, 3, questionMarks: true);
      g.toggleMark(3, 3, questionMarks: true);
      g.toggleMark(3, 3); // setting now off
      expect(g.at(3, 3).mark, Mark.none);
    });

    test('a flagged cell cannot be revealed; a question-marked one can', () {
      final g = board({(0, 0)});
      g.toggleMark(0, 1);
      g.reveal(0, 1);
      expect(g.at(0, 1).revealed, isFalse);
      g.toggleMark(0, 1, questionMarks: true);
      g.reveal(0, 1);
      expect(g.at(0, 1).revealed, isTrue);
      expect(g.at(0, 1).mark, Mark.none);
    });

    test('a revealed cell cannot be flagged', () {
      final g = board({(0, 0)});
      g.reveal(0, 1);
      g.toggleMark(0, 1);
      expect(g.at(0, 1).mark, Mark.none);
    });
  });

  group('chord', () {
    test('opens the rest of the neighbours when the flags match the number', () {
      final g = board({(0, 0), (4, 4)});
      g.reveal(0, 1); // a 1
      g.toggleMark(0, 0);
      g.chord(0, 1);
      expect(g.at(1, 1).revealed, isTrue);
      expect(g.at(1, 0).revealed, isTrue);
      expect(g.status, isNot(GameStatus.lost));
    });

    test('does nothing when the flag count differs', () {
      final g = board({(0, 0), (4, 4)});
      g.reveal(0, 1);
      g.chord(0, 1);
      expect(g.at(1, 1).revealed, isFalse);
    });

    test('with a wrong flag it hits the mine', () {
      final g = board({(0, 0), (4, 4)});
      g.reveal(0, 1);
      g.toggleMark(1, 1); // wrong
      g.chord(0, 1);
      expect(g.status, GameStatus.lost);
    });
  });

  group('lose and win', () {
    test('clicking a mine loses, marks it exploded and shows the other mines', () {
      final g = board({(0, 0), (4, 4), (8, 8)});
      g.toggleMark(8, 8);
      g.reveal(0, 0);
      expect(g.status, GameStatus.lost);
      expect(g.at(0, 0).exploded, isTrue);
      expect(g.at(4, 4).revealed, isTrue);
      expect(g.at(8, 8).revealed, isFalse); // correctly flagged stays flagged
      expect(g.isOver, isTrue);
    });

    test('nothing changes after the game is over', () {
      final g = board({(0, 0)});
      g.reveal(0, 0);
      g.reveal(5, 5);
      g.toggleMark(5, 5);
      expect(g.at(5, 5).revealed, isFalse);
      expect(g.at(5, 5).mark, Mark.none);
      g.tick();
      expect(g.seconds, 0);
    });

    test('revealing every safe cell wins and flags the mines', () {
      final g = board({(0, 0), (0, 8)});
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          if (!g.at(r, c).mine) g.reveal(r, c);
        }
      }
      expect(g.status, GameStatus.won);
      expect(g.at(0, 0).mark, Mark.flag);
      expect(g.minesLeft, 0);
    });
  });

  group('timer', () {
    test('only counts while playing', () {
      final g = Minesweeper(Difficulty.beginner, rng: Random(3));
      g.tick();
      expect(g.seconds, 0);
      g.reveal(4, 4);
      g.tick();
      g.tick();
      expect(g.seconds, 2);
    });

    test('caps at 999', () {
      final g = board({(0, 0)});
      for (var i = 0; i < 1100; i++) {
        g.tick();
      }
      expect(g.seconds, 999);
    });
  });

  group('json', () {
    test('a game in progress round-trips', () {
      final g = Minesweeper(Difficulty.intermediate, rng: Random(5))..reveal(8, 8);
      g.toggleMark(0, 0, questionMarks: true);
      g.toggleMark(0, 0, questionMarks: true);
      g.tick();
      final back = Minesweeper.fromJson(g.toJson());
      expect(back.toJson(), g.toJson());
      expect(back.status, GameStatus.playing);
      expect(back.seconds, 1);
      expect(back.at(0, 0).mark, Mark.question);
      expect(back.at(8, 8).adjacent, g.at(8, 8).adjacent);
    });

    test('a game not yet started round-trips', () {
      final back = Minesweeper.fromJson(Minesweeper(Difficulty.expert).toJson());
      expect(back.status, GameStatus.ready);
      expect(mineCount(back), 0);
    });

    final good = Minesweeper(Difficulty.beginner, rng: Random(1))..reveal(4, 4);
    final cases = <String, Object? Function(Map<String, Object?>)>{
      'not an object': (_) => 'nope',
      'unknown difficulty': (j) => {...j, 'difficulty': 'huge'},
      'unknown status': (j) => {...j, 'status': 'asleep'},
      'seconds not int': (j) => {...j, 'seconds': '3'},
      'seconds negative': (j) => {...j, 'seconds': -1},
      'cells missing': (j) => {...j, 'cells': null},
      'cells too short': (j) => {...j, 'cells': (j['cells'] as List).take(80).toList()},
      'cell out of range': (j) => {...j, 'cells': [99, ...(j['cells'] as List).skip(1)]},
      'cell not int': (j) => {...j, 'cells': ['x', ...(j['cells'] as List).skip(1)]},
      'wrong mine count': (j) => {...j, 'cells': [for (final _ in (j['cells'] as List)) 0], 'status': 'playing'},
      'mines before first move': (j) => {...j, 'status': 'ready'},
    };
    cases.forEach((name, damage) {
      test('refuses a damaged save: $name', () {
        expect(() => Minesweeper.fromJson(damage(good.toJson())), throwsFormatException);
      });
    });
  });
}
