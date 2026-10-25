import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';

import 'coordination/timer_peers.dart';
import 'kit_gaps/notifier.dart';
import 'logic/clock.dart';
import 'logic/controller.dart';
import 'logic/state_store.dart';

/// Builds the controller from the context: state file in the app's state directory, the "notify" setting from
/// the app's config, the save-on-close hook, and (unless [peers] is false) the shared countdown over the Kit's peers.
/// Shared by `main` and the widget test so both wire it the same way.
StopwatchController buildController(
  AppContext ctx,
  Notifier notifier, {
  NowMs? now,
  bool peers = true,
  FakePeerNetwork? network,
  Duration takeoverGrace = const Duration(seconds: 2),
}) {
  void notify(String title, String body) {
    if (ctx.config.get<bool>('notify', true)) notifier.notify(title, body);
  }

  final store = StateStore(File('${ctx.dirs.state}${Platform.pathSeparator}state.json'));
  TimerPeers? shared;
  final controller = StopwatchController.load(store, now: now, onCountdownDone: (done) {
    final p = shared;
    // With peers the hook decides whether this copy announces or waits for the copy that started the run.
    p != null ? p.hook.countdownEnded(done) : notify('Timer finished', '${formatMs(done.durationMs, tenths: false)} countdown is done');
  });
  ctx.onClose(controller.dispose);
  if (peers) shared = TimerPeers.start(ctx, controller, announce: notify, network: network, takeoverGrace: takeoverGrace);
  return controller;
}
