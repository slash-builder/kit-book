// Runs against a real venued, and is skipped unless VENUE_TOKEN_FILE is set. Start one with tools/venued-dev.sh from the App Context Kit (.kits/app-context-kit/tools/venued-dev.sh), then
//   VENUE_DAEMON=http://127.0.0.1:7878 VENUE_TOKEN_FILE=/tmp/venue-spike/tokens/render-queue flutter test test/venue_real_test.dart
// The consumer `render-queue` has maxLiveHolds 3 in tools/venued-dev.sh, which is what the assertions rely on.
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:render_queue/bootstrap.dart';
import 'package:render_queue/logic/fake_render.dart';
import 'package:render_queue/logic/job.dart';
import 'package:render_queue/logic/render_queue.dart';

/// The assertions below need all 3 of this consumer's hold slots free. `venue.holds()` lists this consumer's live holds
/// (round 1 had to ask the daemon over raw HTTP here), so wait for a leftover hold (a killed run, a previous test) to lapse.
Future<void> waitForNoHolds(VenueSession venue) async {
  for (var i = 0; i < 80; i++) {
    if ((await venue.holds()).isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('this consumer still has live holds after 40 s; another process is using the same token');
}

void main() {
  final skip = Platform.environment['VENUE_TOKEN_FILE'] == null ? 'set VENUE_TOKEN_FILE (see tools/venued-dev.sh)' : null;

  late Directory tmp;
  late AppContext ctx;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('rq-real-');
    final manifest = AppManifest.parse(File('app.json').readAsStringSync());
    ctx = await AppContext.open(manifest, env: {...Platform.environment, 'APP_CONTEXT_SCRATCH': tmp.path, 'APP_CONTEXT_MODE': 'real'}, announce: false);
    if (skip == null) await waitForNoHolds(ctx.venue);
  });
  tearDown(() async {
    await ctx.close();
    tmp.deleteSync(recursive: true);
  });

  RenderQueue fast() => RenderQueue(
        venue: ctx.venue,
        work: (j, c) => fakeRender(j, c, step: const Duration(milliseconds: 50)),
        retryEvery: const Duration(milliseconds: 200),
        maxWait: const Duration(seconds: 20),
        leaseSeconds: 30,
      );

  test('the session is a real Venue connection', () {
    expect(ctx.venue.kind, 'venue', reason: ctx.venue.description);
  }, skip: skip);

  test('fail fast: of 5 concurrent jobs, 3 get holds and 2 are refused with Venue\'s reason', () async {
    final q = fast()..policy = RefusalPolicy.failFast;
    for (var i = 0; i < 5; i++) {
      q.add(durationMs: 1500);
    }
    q.runAll();
    await q.idle();
    final refused = q.jobs.where((j) => j.state == JobState.refused).toList();
    expect(q.jobs.where((j) => j.state == JobState.done).length, 3, reason: q.jobs.map((j) => '${j.state.label} ${j.reason}').join('\n'));
    expect(refused.length, 2);
    expect(refused.first.reason, isNotEmpty);
    expect(q.peakConcurrent, 3);
    // ignore: avoid_print
    print('Venue refusal reason: ${refused.first.reason}');
  }, skip: skip);

  test('wait: all 5 finish, never more than 3 holding at once', () async {
    final q = fast();
    for (var i = 0; i < 5; i++) {
      q.add(durationMs: 1000);
    }
    q.runAll();
    await q.idle();
    expect(q.jobs.every((j) => j.state == JobState.done), isTrue, reason: q.jobs.map((j) => '${j.state.label} ${j.reason}').join('\n'));
    expect(q.peakConcurrent, 3);
    // after everything, Venue has none of our holds
    expect(q.runningNow, 0);
  }, skip: skip);

  test('orphan holds: a hold nobody released is found by a fresh session, listed, and releasable', () async {
    // "the crashed run": a second session of the same consumer takes a hold and never releases it.
    final manifest = AppManifest.parse(File('app.json').readAsStringSync());
    final crashed = await AppContext.open(manifest,
        env: {...Platform.environment, 'APP_CONTEXT_SCRATCH': '${tmp.path}/crashed', 'APP_CONTEXT_MODE': 'real'}, announce: false);
    await crashed.venue.hold(const VenueNeed(name: 'rq-crashed-1', contractClass: 'container.run.v1'), leaseSeconds: 60);
    await crashed.close(); // closing the context does not release holds it did not take through withHold
    final q = fast();
    await q.scanOrphans();
    expect(q.orphans.map((h) => h.name), ['rq-crashed-1']);
    expect(q.orphans.single.expiresAt, isNotNull);
    expect(await q.releaseOrphans(), 1);
    expect(q.orphans, isEmpty);
    expect(await ctx.venue.holds(), isEmpty);
  }, skip: skip);

  test('buildQueue wires the real session through the context', () {
    final q = buildQueue(ctx);
    expect(q.venue.kind, 'venue');
  }, skip: skip);
}
