// ignore_for_file: avoid_print
// HEADLESS PROBE, not the app: the stopwatch's own coordination code (buildController -> TimerPeers -> SharedTimerHook) over the
// REAL loopback provider (TCP on 127.0.0.1 and a directory of announcement files), as a second copy next to the built macOS app.
// The display is off, so nothing can click the real window; this process plays the person on the other copy.
//
//   dart run tool/peer_probe.dart --scratch DIR --peers DIR --device NAME [--for SECS] [--start-after-ready SECS] [--grace MS]
//
// Every line starts with the wall-clock time in epoch milliseconds so lines from several processes can be compared.
import 'dart:async';
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:stopwatch/bootstrap.dart';
import 'package:stopwatch/kit_gaps/notifier.dart';

void log(String m) => print('${DateTime.now().millisecondsSinceEpoch} $m');

class PrintNotifier implements Notifier {
  @override
  Future<bool> notify(String title, String body) async {
    log('NOTIFY $title: $body');
    return true;
  }
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
  final c = buildController(ctx, PrintNotifier(), takeoverGrace: Duration(milliseconds: int.parse(opt('grace', '2000'))));
  final hub = c.peers!.handle.hub!;
  await c.peers!.handle.started;
  log('START ${hub.id} stamp=${c.peers!.hook.stamp.rev}');
  hub.changes.listen((e) => log('PEER ${e.change.name} ${e.peer.id} hello=${e.peer.hello}'));
  c.changes.listen((_) {
    final cd = c.state.countdown;
    log('STATE duration=${cd.durationMs} running=${cd.clock.running} remaining=${cd.remainingMs(c.nowMs)} phase=${cd.phase().name} stamp=${c.peers!.hook.stamp.rev}/${c.peers!.hook.stamp.writer}');
  });
  final startAfter = opt('start-after-ready');
  if (startAfter.isNotEmpty) {
    unawaited(hub.changes.firstWhere((e) => e.change == PeerChange.ready).then((_) async {
      await Future<void>.delayed(Duration(seconds: int.parse(startAfter)));
      log('COMMAND reset 6s + start (this is the person on the probe copy)');
      c.resetCountdown(durationMs: 6000);
      c.toggleCountdown();
    }));
  }
  final secs = int.parse(opt('for', '20'));
  var n = 0;
  final timer = Timer.periodic(const Duration(seconds: 1), (_) => log('TICK peers=${hub.peers.map((p) => '${p.id}:${p.state.name}').toList()} dialFailures=${hub.stats.dialFailures} ${PeerJson.label(hub.id)}'));
  await Future<void>.delayed(Duration(seconds: secs));
  timer.cancel();
  n++;
  log('END $n');
  await ctx.close();
  exit(0);
}
