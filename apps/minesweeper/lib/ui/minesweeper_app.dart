import 'dart:math';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';

import '../coordination/game_peers.dart';
import '../logic/settings.dart';
import '../logic/storage.dart';
import 'game_controller.dart';
import 'game_screen.dart';

class MinesweeperApp extends StatefulWidget {
  const MinesweeperApp({super.key, this.rng, this.peers = true, this.network});

  /// Injected by tests for a repeatable board.
  final Random? rng;

  /// Start peer coordination (the manifest must list "peers").
  final bool peers;

  /// Tests: the shared in-memory network (mock mode); otherwise the Kit picks the provider.
  final FakePeerNetwork? network;

  @override
  State<MinesweeperApp> createState() => _MinesweeperAppState();
}

class _MinesweeperAppState extends State<MinesweeperApp> {
  GameController? _controller;

  // The context is read from the scope, which an InheritedWidget cannot give in initState, so the controller is made on the
  // first didChangeDependencies instead.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final ctx = AppContextScope.of(context);
    final controller = GameController(
      storage: GameStorage(ctx.dirs.data),
      settings: Settings(SessionSettings(ctx.config)),
      rng: widget.rng,
    );
    // The banner shows ctx.notes, so the app's own start-up problems join the Kit's (added once, so a dismissal sticks).
    ctx.notes.addAll([
      for (final p in controller.problems) AppNote(NoteSeverity.warning, p),
      if (controller.settings.readOnly) const AppNote(NoteSeverity.warning, 'Settings are read-only this session; changes will not be saved.'),
    ]);
    if (widget.peers) {
      final p = GamePeers.start(ctx, controller, network: widget.network);
      controller.peers = p;
      controller.onMove = (op, r, c, mark, wasReady) => p.hook.localMove(op, r, c, mark: mark, wasReady: wasReady);
      controller.onNewBoard = p.hook.localBoard;
    }
    ctx.onClose(controller.saveNow);
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppContextScope.of(context).manifest.name,
        theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
        home: GameScreen(controller: _controller!),
      );
}
