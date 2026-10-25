import 'dart:io';
import 'dart:math';

import 'package:app_context_kit/app_context_kit.dart' show AppJsonFile;

import 'game.dart';
import 'scores.dart';

/// What loading a file found. When the file was damaged it has been set aside (not deleted) and [problem] says so.
class Loaded<T> {
  const Loaded(this.value, [this.problem]);
  final T value;
  final String? problem;
}

/// The game in progress and the high scores, as two files in the app's data directory.
class GameStorage {
  GameStorage(String dataDir)
      : _game = AppJsonFile(File('$dataDir${Platform.pathSeparator}game.json')),
        _scores = AppJsonFile(File('$dataDir${Platform.pathSeparator}scores.json'));

  final AppJsonFile _game, _scores;

  /// The saved game, or null when there is none (or it was damaged, in which case [Loaded.problem] is set).
  Loaded<Minesweeper?> loadGame({Random? rng}) {
    final r = _game.read();
    if (!r.exists) return const Loaded(null);
    if (r.ok) {
      try {
        return Loaded(Minesweeper.fromJson(r.value, rng: rng));
      } on FormatException catch (e) {
        return Loaded(null, _setAside(_game, 'saved game', e.message));
      }
    }
    return Loaded(null, _setAside(_game, 'saved game', r.problem!));
  }

  void saveGame(Minesweeper g) => _game.write(g.toJson());
  void clearGame() => _game.delete();

  Loaded<HighScores> loadScores() {
    final r = _scores.read();
    if (!r.exists) return Loaded(HighScores());
    if (r.ok) {
      try {
        return Loaded(HighScores.fromJson(r.value));
      } on FormatException catch (e) {
        return Loaded(HighScores(), _setAside(_scores, 'high scores', e.message));
      }
    }
    return Loaded(HighScores(), _setAside(_scores, 'high scores', r.problem!));
  }

  void saveScores(HighScores s) => _scores.write(s.toJson());

  String _setAside(AppJsonFile f, String what, String why) {
    final moved = f.quarantine();
    return 'The $what file was damaged ($why). It was kept as ${moved.path}.';
  }
}
