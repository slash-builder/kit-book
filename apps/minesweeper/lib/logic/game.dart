import 'dart:math';

enum Difficulty {
  beginner(9, 9, 10),
  intermediate(16, 16, 40),
  expert(16, 30, 99);

  const Difficulty(this.rows, this.cols, this.mines);
  final int rows, cols, mines;
}

enum Mark { none, flag, question }

enum GameStatus { ready, playing, won, lost }

class Cell {
  bool mine = false;
  bool revealed = false;
  bool exploded = false; // the mine that was clicked
  Mark mark = Mark.none;
  int adjacent = 0;
}

/// One game of minesweeper. Pure Dart; the random generator and the clock are the caller's.
/// Mines are placed on the first reveal, never on the clicked cell (nor its neighbours when the board has room),
/// so the first click is always safe and usually opens an area.
class Minesweeper {
  Minesweeper(this.difficulty, {Random? rng})
      : rows = difficulty.rows,
        cols = difficulty.cols,
        mines = difficulty.mines,
        _rng = rng ?? Random(),
        _cells = List.generate(difficulty.rows * difficulty.cols, (_) => Cell());

  /// A game with the mines already placed (for tests and for loading); the first reveal is then not special.
  Minesweeper.withMines(this.difficulty, Set<(int, int)> mineAt, {Random? rng})
      : rows = difficulty.rows,
        cols = difficulty.cols,
        mines = mineAt.length,
        _rng = rng ?? Random(),
        _cells = List.generate(difficulty.rows * difficulty.cols, (_) => Cell()) {
    for (final (r, c) in mineAt) {
      _cells[r * cols + c].mine = true;
    }
    _placed = true;
    _countAdjacent();
    status = GameStatus.playing;
  }

  final Difficulty difficulty;
  final int rows, cols, mines;
  final Random _rng;
  final List<Cell> _cells;
  bool _placed = false;
  GameStatus status = GameStatus.ready;

  /// Whole seconds since the first reveal; advanced by [tick], capped at 999 like the original.
  int seconds = 0;

  Cell at(int r, int c) => _cells[r * cols + c];
  bool get isOver => status == GameStatus.won || status == GameStatus.lost;
  int get flagsPlaced => _cells.where((c) => c.mark == Mark.flag).length;
  int get minesLeft => mines - flagsPlaced;
  int get revealedCount => _cells.where((c) => c.revealed && !c.mine).length;

  bool inBounds(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;

  Iterable<(int, int)> neighbours(int r, int c) sync* {
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if ((dr != 0 || dc != 0) && inBounds(r + dr, c + dc)) yield (r + dr, c + dc);
      }
    }
  }

  void tick() {
    if (status == GameStatus.playing && seconds < 999) seconds++;
  }

  void reveal(int r, int c) {
    if (isOver) return;
    final cell = at(r, c);
    if (cell.revealed || cell.mark == Mark.flag) return;
    if (!_placed) {
      _placeMines(r, c);
      status = GameStatus.playing;
    }
    _open(r, c);
  }

  /// Revealing a number whose flags already account for it opens the rest of its neighbours.
  void chord(int r, int c) {
    if (isOver) return;
    final cell = at(r, c);
    if (!cell.revealed || cell.adjacent == 0) return;
    final around = neighbours(r, c).toList();
    final flags = around.where((n) => at(n.$1, n.$2).mark == Mark.flag).length;
    if (flags != cell.adjacent) return;
    for (final (nr, nc) in around) {
      if (isOver) break;
      final n = at(nr, nc);
      if (!n.revealed && n.mark != Mark.flag) _open(nr, nc);
    }
  }

  /// none, then flag, then question (when [questionMarks]), then none.
  void toggleMark(int r, int c, {bool questionMarks = false}) {
    if (isOver) return;
    final cell = at(r, c);
    if (cell.revealed) return;
    cell.mark = switch (cell.mark) {
      Mark.none => Mark.flag,
      Mark.flag => questionMarks ? Mark.question : Mark.none,
      Mark.question => Mark.none,
    };
  }

  void _open(int r, int c) {
    final first = at(r, c);
    if (first.mine) {
      _lose(r, c);
      return;
    }
    final stack = <(int, int)>[(r, c)];
    while (stack.isNotEmpty) {
      final (cr, cc) = stack.removeLast();
      final cell = at(cr, cc);
      if (cell.revealed || cell.mark == Mark.flag) continue;
      cell.revealed = true;
      cell.mark = Mark.none;
      if (cell.adjacent == 0) stack.addAll(neighbours(cr, cc));
    }
    if (revealedCount == rows * cols - mines) _win();
  }

  void _lose(int r, int c) {
    status = GameStatus.lost;
    at(r, c).exploded = true;
    for (final cell in _cells) {
      if (cell.mine && cell.mark != Mark.flag) cell.revealed = true;
    }
  }

  void _win() {
    status = GameStatus.won;
    for (final cell in _cells) {
      if (cell.mine) cell.mark = Mark.flag;
    }
  }

  void _placeMines(int safeR, int safeC) {
    final roomy = rows * cols - 9 >= mines;
    final safe = <int>{safeR * cols + safeC};
    if (roomy) {
      for (final (r, c) in neighbours(safeR, safeC)) {
        safe.add(r * cols + c);
      }
    }
    final candidates = [for (var i = 0; i < rows * cols; i++) if (!safe.contains(i)) i]..shuffle(_rng);
    for (final i in candidates.take(mines)) {
      _cells[i].mine = true;
    }
    _placed = true;
    _countAdjacent();
  }

  void _countAdjacent() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        at(r, c).adjacent = neighbours(r, c).where((n) => at(n.$1, n.$2).mine).length;
      }
    }
  }

  // ---- persistence -------------------------------------------------------------------------------------------

  static const _mine = 1, _revealed = 2, _exploded = 4;

  Map<String, Object?> toJson() => {
        'v': 1,
        'difficulty': difficulty.name,
        'status': status.name,
        'seconds': seconds,
        'cells': [
          for (final c in _cells) (c.mine ? _mine : 0) | (c.revealed ? _revealed : 0) | (c.exploded ? _exploded : 0) | (c.mark.index << 3),
        ],
      };

  /// Rebuilds a saved game. Throws [FormatException] on anything inconsistent, so the caller can set the file aside.
  static Minesweeper fromJson(Object? json, {Random? rng}) {
    if (json is! Map) throw const FormatException('game is not an object');
    final d = Difficulty.values.where((d) => d.name == json['difficulty']).firstOrNull;
    if (d == null) throw FormatException('unknown difficulty ${json['difficulty']}');
    final status = GameStatus.values.where((s) => s.name == json['status']).firstOrNull;
    if (status == null) throw FormatException('unknown status ${json['status']}');
    final seconds = json['seconds'];
    if (seconds is! int || seconds < 0 || seconds > 999) throw const FormatException('bad seconds');
    final cells = json['cells'];
    if (cells is! List || cells.length != d.rows * d.cols) throw const FormatException('wrong number of cells');
    final g = Minesweeper(d, rng: rng);
    var mineCount = 0;
    for (var i = 0; i < cells.length; i++) {
      final v = cells[i];
      if (v is! int || v < 0 || v > 0x1f || (v >> 3) > 2) throw FormatException('bad cell $i');
      final c = g._cells[i];
      c.mine = v & _mine != 0;
      c.revealed = v & _revealed != 0;
      c.exploded = v & _exploded != 0;
      c.mark = Mark.values[v >> 3];
      if (c.mine) mineCount++;
    }
    if (status == GameStatus.ready) {
      if (mineCount != 0) throw const FormatException('mines before the first move');
    } else {
      if (mineCount != d.mines) throw FormatException('expected ${d.mines} mines, found $mineCount');
      g._placed = true;
      g._countAdjacent();
    }
    g.status = status;
    g.seconds = seconds;
    return g;
  }
}
