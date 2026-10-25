import 'dart:async';

import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../logic/game.dart';
import 'game_controller.dart';
import 'peers_bar.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Timer? _timer;
  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => c.tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final g = c.game;
        return PageScaffold(
          title: ctx.manifest.name,
          actions: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: ModeBadge.forContext(ctx, key: const ValueKey('mode-chip'))),
            PopupMenuButton<Difficulty>(
              key: const ValueKey('difficulty-menu'),
              tooltip: 'Difficulty',
              initialValue: g.difficulty,
              onSelected: c.newGame,
              itemBuilder: (_) => [
                for (final d in Difficulty.values)
                  PopupMenuItem(key: ValueKey('difficulty-${d.name}'), value: d, child: Text('${_title(d)}  ${d.cols}x${d.rows}, ${d.mines} mines')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text(_title(g.difficulty), key: const ValueKey('difficulty-label'))),
              ),
            ),
            IconButton(key: const ValueKey('scores-button'), tooltip: 'High scores', icon: const Icon(Icons.emoji_events_outlined), onPressed: _showScores),
            PopupMenuButton<String>(
              key: const ValueKey('settings-menu'),
              icon: const Icon(Icons.settings),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  key: const ValueKey('question-marks'),
                  value: 'question',
                  checked: c.settings.questionMarks,
                  child: const Text('Question marks'),
                ),
              ],
              onSelected: (_) => c.setQuestionMarks(!c.settings.questionMarks),
            ),
          ],
          banner: NotesBanner.forContext(ctx, key: const ValueKey('notice'), dismissible: true),
          body: Column(
            children: [
              _header(g),
              Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(12), child: FittedBox(child: _board(g))))),
              SizedBox(height: 28, child: Text(_statusText(g), key: const ValueKey('status-text'))),
              // In the body, not PageScaffold.footer: the footer slot is capped at 25% of the page and scrolls inside the cap,
              // and this bar carries buttons (Take over, Join, Send to ...) that must stay on screen.
              if (c.peers != null) PeersBar(peers: c.peers!),
            ],
          ),
        );
      },
    );
  }

  Widget _header(Minesweeper g) {
    final icon = switch (g.status) {
      GameStatus.won => Icons.sentiment_very_satisfied,
      GameStatus.lost => Icons.sentiment_very_dissatisfied,
      _ => Icons.sentiment_satisfied,
    };
    TextStyle style() => const TextStyle(fontSize: 22, fontFeatures: [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(g.minesLeft.toString().padLeft(3, '0'), key: const ValueKey('mines-left'), style: style()),
        IconButton.filledTonal(key: const ValueKey('new-game'), tooltip: 'New game', iconSize: 32, icon: Icon(icon), onPressed: () => c.newGame()),
        Text(g.seconds.toString().padLeft(3, '0'), key: const ValueKey('timer'), style: style()),
      ]),
    );
  }

  String _statusText(Minesweeper g) => switch (g.status) {
        GameStatus.won => 'You won in ${g.seconds} s${c.lastRank == null ? '' : ' (rank ${c.lastRank})'}.',
        GameStatus.lost => 'Boom. Press the face to try again.',
        GameStatus.ready => 'Click any square to start.',
        GameStatus.playing => '',
      };

  static const cellSize = 30.0;

  Widget _board(Minesweeper g) => SizedBox(
        width: g.cols * cellSize,
        height: g.rows * cellSize,
        child: Column(children: [
          for (var r = 0; r < g.rows; r++)
            Row(children: [
              for (var col = 0; col < g.cols; col++) _cell(g, r, col),
            ]),
        ]),
      );

  static const _numberColors = [
    Colors.transparent, Colors.blue, Color(0xFF2E7D32), Colors.red, Color(0xFF1A237E), Color(0xFF8D1B1B), Colors.teal, Colors.black, Colors.grey,
  ];

  Widget _cell(Minesweeper g, int r, int col) {
    final cell = g.at(r, col);
    final lost = g.status == GameStatus.lost;
    final scheme = Theme.of(context).colorScheme;
    Widget? child;
    Color bg;
    if (cell.revealed) {
      bg = cell.exploded ? Colors.red : scheme.surfaceContainerHighest;
      if (cell.mine) {
        child = const Icon(Icons.circle, size: 16);
      } else if (cell.adjacent > 0) {
        child = Text('${cell.adjacent}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _numberColors[cell.adjacent]));
      }
    } else {
      bg = scheme.primaryContainer;
      if (cell.mark == Mark.flag) {
        child = Icon(lost && !cell.mine ? Icons.close : Icons.flag, size: 18, color: lost && !cell.mine ? Colors.red : null);
      } else if (cell.mark == Mark.question) {
        child = const Text('?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
      }
    }
    return GestureDetector(
      key: ValueKey('cell-$r-$col'),
      onTap: () => c.reveal(r, col),
      onSecondaryTap: () => c.flag(r, col),
      onLongPress: () => c.flag(r, col),
      child: Container(
        width: cellSize - 1,
        height: cellSize - 1,
        margin: const EdgeInsets.all(0.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
        child: child,
      ),
    );
  }

  void _showScores() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('High scores'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final d in Difficulty.values) ...[
              Text(_title(d), style: Theme.of(context).textTheme.titleSmall),
              if (c.scores.of(d).isEmpty)
                Text('No wins yet', key: ValueKey('scores-empty-${d.name}'))
              else
                for (final (i, s) in c.scores.of(d).take(5).indexed) Text('${i + 1}.  ${s.seconds} s', key: ValueKey('score-${d.name}-$i')),
              const SizedBox(height: 8),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  static String _title(Difficulty d) => '${d.name[0].toUpperCase()}${d.name.substring(1)}';
}
