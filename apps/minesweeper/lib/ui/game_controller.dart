import 'dart:math';

import 'package:flutter/foundation.dart';

import '../coordination/game_hook.dart';
import '../coordination/game_peers.dart';
import '../logic/game.dart';
import '../logic/scores.dart';
import '../logic/settings.dart';
import '../logic/storage.dart';

/// Holds the current game, the scores and the settings, and saves after every move so quitting never loses a game.
class GameController extends ChangeNotifier implements GameHost {
  GameController({required this.storage, required this.settings, Random? rng, DateTime Function()? now})
      : _rng = rng,
        _now = now ?? DateTime.now {
    final scoresLoad = storage.loadScores();
    scores = scoresLoad.value;
    final gameLoad = storage.loadGame(rng: rng);
    problems = [?scoresLoad.problem, ?gameLoad.problem];
    game = gameLoad.value ?? Minesweeper(settings.difficulty, rng: rng);
  }

  final GameStorage storage;
  final Settings settings;
  final Random? _rng;
  final DateTime Function() _now;

  @override
  late Minesweeper game;
  late HighScores scores;

  /// Peer coordination (null when the app did not start it).
  GamePeers? peers;

  /// Called after the PERSON moved: (op, row, col, resulting mark for a flag, whether the board had no mines before this move).
  void Function(String op, int r, int c, String? mark, bool wasReady)? onMove;

  /// Called after the person started a new game.
  void Function()? onNewBoard;

  /// Damaged files found at start-up (already set aside by the storage layer).
  late final List<String> problems;

  /// Rank of the most recent win in the high scores, if it made the list.
  int? lastRank;

  void reveal(int r, int c) {
    final cell = game.at(r, c);
    final wasReady = game.status == GameStatus.ready, chord = cell.revealed;
    if (cell.revealed) {
      game.chord(r, c);
    } else {
      game.reveal(r, c);
    }
    _afterMove();
    onMove?.call(chord ? 'chord' : 'reveal', r, c, null, wasReady);
  }

  void flag(int r, int c) {
    game.toggleMark(r, c, questionMarks: settings.questionMarks);
    _afterMove();
    onMove?.call('flag', r, c, game.at(r, c).mark.name, false);
  }

  void tick() {
    final before = game.seconds;
    game.tick();
    if (game.seconds != before) notifyListeners();
  }

  void newGame([Difficulty? d]) {
    if (d != null && d != settings.difficulty) settings.difficulty = d;
    storage.clearGame();
    lastRank = null;
    game = Minesweeper(d ?? settings.difficulty, rng: _rng);
    notifyListeners();
    onNewBoard?.call();
  }

  // ---- GameHost: what the peers hook may ask of the game ----

  @override
  void adoptBoard(Map<String, Object?> board) {
    final g = Minesweeper.fromJson(board, rng: _rng); // throws FormatException: nothing changes
    game = g;
    if (settings.difficulty != g.difficulty) settings.difficulty = g.difficulty;
    g.status == GameStatus.playing ? storage.saveGame(g) : storage.clearGame();
    lastRank = null;
    notifyListeners();
  }

  @override
  void releaseTo(String label) {
    storage.clearGame();
    lastRank = null;
    game = Minesweeper(settings.difficulty, rng: _rng);
    notifyListeners();
  }

  @override
  void applyRemoteMove(String op, int r, int c, String? mark) {
    final cell = game.at(r, c);
    switch (op) {
      case 'reveal':
        if (!cell.revealed) game.reveal(r, c);
      case 'chord':
        game.chord(r, c);
      case 'flag':
        if (!game.isOver && !cell.revealed) cell.mark = Mark.values.byName(mark!);
    }
    _afterMove();
  }

  @override
  void refresh() => notifyListeners();

  void setQuestionMarks(bool v) {
    settings.questionMarks = v;
    notifyListeners();
  }

  /// Called when the app closes: the timer ticks are not saved one by one.
  void saveNow() {
    if (game.status == GameStatus.playing) storage.saveGame(game);
  }

  void _afterMove() {
    switch (game.status) {
      case GameStatus.won:
        lastRank = scores.add(game.difficulty, game.seconds, _now());
        storage.saveScores(scores);
        storage.clearGame();
      case GameStatus.lost:
        storage.clearGame();
      case GameStatus.playing:
        storage.saveGame(game);
      case GameStatus.ready:
        break;
    }
    notifyListeners();
  }
}
