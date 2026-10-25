// Headless stand-in for the app, for the kill -9 experiment (the display was off, so the window could not be clicked).
// It uses the app's own bootstrap (config.json, leaseSeconds, the queue, withHoldWaiting, scanOrphans); only the UI is missing.
//   dart run tool/orphan_probe.dart start            3 jobs of 60 s, then waits to be killed
//   dart run tool/orphan_probe.dart relaunch <ms>    what the app does at startup, then one more job; <ms> = kill time (epoch ms)
import 'dart:async';
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:render_queue/bootstrap.dart';
import 'package:render_queue/logic/job.dart';
import 'package:render_queue/logic/render_queue.dart' show JobCancelled;

int now() => DateTime.now().millisecondsSinceEpoch;

Future<void> main(List<String> args) async {
  final ctx = await AppContext.open(AppManifest.parse(File('app.json').readAsStringSync()), announce: false);
  stdout.writeln('venue: ${ctx.venue.description}');
  final q = buildQueue(ctx, work: (j, c) async {
    final end = now() + j.durationMs;
    while (now() < end) {
      if (c.isCancelled) throw JobCancelled();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  if (args.first == 'start') {
    for (var i = 0; i < 3; i++) {
      q.add(durationMs: 60000);
    }
    q.runAll();
    await Future<void>.delayed(const Duration(seconds: 2));
    stdout.writeln('RUNNING ${q.jobs.map((j) => '${j.holdName}:${j.state.label}').join(' ')} at ${now()}');
    await Completer<void>().future; // until kill -9
  }
  final killedAt = int.parse(args[1]);
  final t0 = now();
  await q.scanOrphans();
  stdout.writeln('relaunch +${t0 - killedAt} ms after kill: scan done at +${now() - killedAt} ms; orphans=${q.orphans.length}: '
      '${q.orphans.map((h) => '${h.name} expiresIn=${h.expiresAt?.difference(DateTime.now()).inMilliseconds} ms').join(', ')}');
  final j = q.add(durationMs: 200);
  q.runAll();
  Timer.periodic(const Duration(milliseconds: 500), (t) {
    if (j.state == JobState.waiting) stdout.writeln('  +${now() - killedAt} ms: new job waiting, asked ${j.attempts} times: ${j.reason}');
  });
  j.reason = null;
  final grantedWatch = Timer.periodic(const Duration(milliseconds: 20), (t) {
    if (j.state == JobState.running) {
      stdout.writeln('  new job GRANTED at +${now() - killedAt} ms after kill');
      t.cancel();
    }
  });
  await q.idle();
  grantedWatch.cancel();
  stdout.writeln('new job ${j.state.label} at +${now() - killedAt} ms after kill (asked ${j.attempts} times) ${j.reason ?? ''}');
  await q.scanOrphans();
  stdout.writeln('orphans now: ${q.orphans.length}, holds at Venue: ${(await ctx.venue.holds()).length}');
  await ctx.close();
  exit(0);
}
