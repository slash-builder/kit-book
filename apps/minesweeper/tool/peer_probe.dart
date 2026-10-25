// ignore_for_file: avoid_print
// HEADLESS PROBE, not the app: the minesweeper's own coordination code (GamePeers -> GameHook) over the REAL loopback provider, as
// another copy next to the built macOS app, or as two probes talking to each other. The display is off, so nothing can click the
// real window (Accept / Send); this process plays the person. GameController is a Flutter ChangeNotifier and cannot run under
// `dart run`, so the GameHost here is a small stand-in with the same behaviour for adopt / release / remote moves.
//
//   dart run tool/peer_probe.dart --scratch DIR --peers DIR --device NAME [--for SECS] [--game] [--offer SECS:handoff|share]
//        [--accept] [--move SECS]
//
// Every line starts with the wall-clock time in epoch milliseconds so lines from several processes can be compared.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:minesweeper/coordination/game_hook.dart';
import 'package:minesweeper/coordination/game_peers.dart';
import 'package:minesweeper/logic/game.dart';

void log(String m) => print('${DateTime.now().millisecondsSinceEpoch} $m');

class ProbeHost implements GameHost {
  @override
  Minesweeper game = Minesweeper(Difficulty.beginner, rng: Random(1));

  @override
  void adoptBoard(Map<String, Object?> board) {
    game = Minesweeper.fromJson(board);
    log('ADOPT status=${game.status.name} sum=${sum()}');
  }

  @override
  void releaseTo(String label) {
    game = Minesweeper(Difficulty.beginner);
    log('RELEASE to $label');
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
    log('MOVE-APPLIED $op $r,$c sum=${sum()}');
  }

  @override
  void refresh() {}

  String sum() => hash64(jsonEncode(game.toJson()['cells']));
}

Future<void> main(List<String> args) async {
  String opt(String k, [String d = '']) {
    final i = args.indexOf('--$k');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : d;
  }

  final manifest = AppManifest.parse(File('app.json').readAsStringSync());
  final scratch = opt('scratch');
  final ctx = await AppContext.open(manifest,
      env: {'APP_CONTEXT_SCRATCH': scratch, 'APP_CONTEXT_MODE': 'real', 'APP_CONTEXT_PEERS_DIR': opt('peers'), 'APP_CONTEXT_DEVICE': opt('device', 'probe'), 'HOME': scratch},
      announce: false);
  final host = ProbeHost();
  if (args.contains('--game')) {
    host.game = Minesweeper.withMines(Difficulty.beginner, {(0, 0), (0, 8), (8, 0), (8, 8), (4, 4), (2, 6), (6, 2), (1, 1), (7, 7), (3, 5)});
    host.game.reveal(4, 0);
    log('GAME in progress sum=${host.sum()}');
  }
  final peers = GamePeers.start(ctx, host);
  await peers.handle.started;
  final hub = peers.handle.hub!;
  final hook = peers.hook;
  log('START ${hub.id}');
  hub.changes.listen((e) => log('PEER ${e.change.name} ${e.peer.id} hello=${jsonEncode(e.peer.hello)}'));
  hook.changes.listen((_) {
    log('HOOK message="${hook.message}" incoming=${hook.incoming.length} sharing=${hook.sharing}');
    if (args.contains('--accept')) {
      for (final o in hook.incoming.values.toList()) {
        log('OFFER from ${o.from} ${o.mode}: ${o.summary}');
        unawaited(hook.accept(o).then((m) => log('ACCEPTED -> $m')));
      }
    }
  });
  final offer = opt('offer'); // SECS:MODE, after the first peer is ready
  if (offer.isNotEmpty) {
    final p = offer.split(':');
    unawaited(hub.changes.firstWhere((e) => e.change == PeerChange.ready).then((e) async {
      await Future<void>.delayed(Duration(seconds: int.parse(p[0])));
      log('COMMAND offer ${p[1]}');
      await hook.offer(e.peer, p[1]);
    }));
  }
  final move = opt('move'); // SECS after sharing starts: reveal the first closed safe square
  if (move.isNotEmpty) {
    unawaited(hook.changes.firstWhere((_) => hook.sharing != null).then((_) async {
      await Future<void>.delayed(Duration(seconds: int.parse(move)));
      final g = host.game;
      for (var r = 0; r < g.rows; r++) {
        for (var c = 0; c < g.cols; c++) {
          final cell = g.at(r, c);
          if (!cell.revealed && !cell.mine && cell.mark == Mark.none) {
            g.reveal(r, c);
            log('COMMAND move reveal $r,$c sum=${host.sum()}');
            hook.localMove('reveal', r, c);
            return;
          }
        }
      }
    }));
  }
  final timer = Timer.periodic(const Duration(seconds: 1), (_) => log('TICK peers=${hub.peers.map((p) => '${p.id}:${p.state.name}').toList()} dialFailures=${hub.stats.dialFailures} status=${host.game.status.name}'));
  await Future<void>.delayed(Duration(seconds: int.parse(opt('for', '20'))));
  timer.cancel();
  log('END ignored=${hook.ignored}');
  await ctx.close();
  exit(0);
}
