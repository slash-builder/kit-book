import 'dart:io';
import 'dart:math';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minesweeper/coordination/game_peers.dart';
import 'package:minesweeper/logic/game.dart';
import 'package:minesweeper/logic/settings.dart';
import 'package:minesweeper/logic/storage.dart';
import 'package:minesweeper/ui/game_controller.dart';
import 'package:minesweeper/ui/game_screen.dart';
import 'package:minesweeper/ui/minesweeper_app.dart';

void main() {
  final manifestText = File('app.json').readAsStringSync();
  late KitTestContext kit;

  Future<void> settleUntil(WidgetTester t, bool Function() cond, {String? what}) async {
    for (var i = 0; i < 400 && !cond(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(cond(), isTrue, reason: 'the UI did not reach: ${what ?? 'the expected state'}');
  }

  Future<GameController> boot(WidgetTester t, FakePeerNetwork net) async {
    kit = await pumpKitApp(t, manifest: manifestText, env: {'APPKIT_DEVICE': 'laptop'}, app: (_) => MinesweeperApp(rng: Random(3), network: net));
    return t.widget<GameScreen>(find.byType(GameScreen)).controller;
  }

  Future<(AppContext, GameController, GamePeers)> other(WidgetTester t, FakePeerNetwork net) async {
    final ctx = (await t.runAsync(() => AppContext.open(AppManifest.parse(manifestText),
        env: {'APPKIT_SCRATCH': '${kit.scratch.path}/other', 'APPKIT_MODE': 'mock', 'APPKIT_DEVICE': 'desktop', 'HOME': kit.scratch.path},
        announce: false)))!;
    final c = GameController(storage: GameStorage(ctx.dirs.data), settings: Settings(SessionSettings(ctx.config)), rng: Random(5));
    final p = GamePeers.start(ctx, c, network: net);
    c.peers = p;
    c.onMove = (op, r, col, mark, wasReady) => p.hook.localMove(op, r, col, mark: mark, wasReady: wasReady);
    c.onNewBoard = p.hook.localBoard;
    return (ctx, c, p);
  }

  testWidgets('the bar shows this copy and the connected copy; an offer from it can be taken over from the screen', (t) async {
    final net = FakePeerNetwork();
    final c = await boot(t, net);
    expect(find.text('Peers: 0'), findsOneWidget);
    expect(find.textContaining('This copy: laptop #'), findsOneWidget);
    final (octx, oc, op) = await other(t, net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty);
    expect(find.textContaining('Send to desktop #'), findsOneWidget);

    // the other copy has a game in progress and sends it here
    oc.game = Minesweeper.withMines(Difficulty.beginner, {(0, 0), (0, 8), (8, 0), (8, 8), (4, 4), (2, 6), (6, 2), (1, 1), (7, 7), (3, 5)});
    oc.reveal(4, 0);
    final sent = oc.game.toJson();
    await t.runAsync(() => op.hook.offer(op.handle.hub!.readyPeers.single, 'handoff'));
    await settleUntil(t, () => find.byKey(const ValueKey('offer-accept')).evaluate().isNotEmpty);
    expect(find.textContaining('offers a game: Beginner, playing'), findsOneWidget);
    expect(c.game.status, GameStatus.ready, reason: 'an offer changes nothing until the person says yes');

    await t.tap(find.byKey(const ValueKey('offer-accept')));
    await settleUntil(t, () => c.game.status == GameStatus.playing, what: 'the board to arrive');
    expect(c.game.toJson(), sent);
    expect(find.textContaining('Took over the game from desktop #'), findsOneWidget);
    await settleUntil(t, () => oc.game.status == GameStatus.ready, what: 'the sender to stand down');

    await t.runAsync(octx.close);
    await kit.quit();
  });

  testWidgets('"Send this game to" from the menu offers it, and the other copy sees it', (t) async {
    final net = FakePeerNetwork();
    final c = await boot(t, net);
    final (octx, _, op) = await other(t, net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty);
    await t.tap(find.byKey(const ValueKey('cell-4-4'))); // first click: starts the game
    await t.pump();
    expect(c.game.status, GameStatus.playing);

    await t.tap(find.textContaining('Send to desktop #'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('send-handoff')));
    await t.pump();
    await settleUntil(t, () => op.hook.incoming.isNotEmpty, what: 'the offer on the other copy');
    expect(op.hook.incoming.values.single.mode, 'handoff');
    expect(find.textContaining('Offered the game to desktop #'), findsOneWidget);

    await t.runAsync(octx.close);
    await kit.quit();
  });

  testWidgets('playing together: a move on the screen reaches the other copy and a move there appears on the screen', (t) async {
    final net = FakePeerNetwork();
    final c = await boot(t, net);
    final (octx, oc, op) = await other(t, net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty);
    await t.runAsync(() => op.hook.offer(op.handle.hub!.readyPeers.single, 'share'));
    await settleUntil(t, () => find.byKey(const ValueKey('offer-accept')).evaluate().isNotEmpty);
    await t.tap(find.byKey(const ValueKey('offer-accept')));
    await settleUntil(t, () => find.byKey(const ValueKey('sharing-label')).evaluate().isNotEmpty && op.hook.sharing != null);

    await t.tap(find.byKey(const ValueKey('cell-4-4'))); // the first move: the whole board goes across
    await t.pump();
    await settleUntil(t, () => oc.game.status == GameStatus.playing);
    expect(oc.game.toJson(), c.game.toJson());
    final hidden = [for (var r = 0; r < 9; r++) for (var col = 0; col < 9; col++) if (!oc.game.at(r, col).revealed && !oc.game.at(r, col).mine) (r, col)];
    oc.flag(hidden.first.$1, hidden.first.$2);
    await settleUntil(t, () => c.game.at(hidden.first.$1, hidden.first.$2).mark == Mark.flag);

    await t.tap(find.byKey(const ValueKey('stop-sharing')));
    await t.pump();
    expect(find.byKey(const ValueKey('sharing-label')), findsNothing);
    await t.runAsync(octx.close);
    await kit.quit();
  });

  testWidgets('when peers cannot start the bar says why and the game still works', (t) async {
    final dir = Directory.systemTemp.createTempSync('mines-peers-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final blocker = File('${dir.path}/file')..writeAsStringSync('x');
    kit = await pumpKitApp(t,
        manifest: manifestText, env: {'APPKIT_MODE': 'real', 'APPKIT_PEERS_DIR': blocker.path}, app: (_) => MinesweeperApp(rng: Random(3)));
    await settleUntil(t, () => find.byKey(const ValueKey('peers-offline')).evaluate().isNotEmpty);
    expect(find.textContaining('Peers: off (peers unavailable'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cell-4-4')));
    await t.pump();
    expect(t.widget<GameScreen>(find.byType(GameScreen)).controller.game.status, GameStatus.playing);
    await kit.quit();
  });
}
