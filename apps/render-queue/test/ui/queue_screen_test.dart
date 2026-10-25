import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:app_context_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:render_queue/bootstrap.dart';
import 'package:render_queue/logic/fake_render.dart';
import 'package:render_queue/logic/render_queue.dart';
import 'package:render_queue/ui/render_queue_app.dart';

/// Renewals always fail, like a daemon that went away mid-job.
class FailingRenewVenue extends FakeVenue {
  FailingRenewVenue() : super(capacity: 3);
  @override
  Future<void> renew(VenueHold h) async => throw VenueUnavailable('renew: connection reset');
}

void main() {
  final manifest = File('app.json').readAsStringSync();

  // fakeCapacity: 2 is what main() passes to AppContextKit.run. Scratch + mock, so no real directory and no Venue is touched.
  Future<KitTestContext> launch(WidgetTester t,
      {Map<String, String> env = const {}, void Function(AppContext ctx)? before, void Function(RenderQueue q)? onQueue}) async {
    // A tall window: the job list is a lazy ListView and offscreen tiles are not built, so they could not be found.
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final kit = await testAppContext(t, manifest: manifest, env: env, fakeCapacity: 2);
    before?.call(kit.ctx);
    await kit.mount((ctx) {
      final q = buildQueue(ctx);
      onQueue?.call(q);
      return RenderQueueApp(queue: q);
    });
    return kit;
  }

  String stateOf(WidgetTester t, int id) => (t.widget(find.byKey(Key('job-$id-state'))) as Chip).label.toString();

  testWidgets('mock mode: the banner says fake, 5 jobs on a node of 2 wait for Venue and then all finish', (t) async {
    late RenderQueue q;
    final kit = await launch(t, onQueue: (x) => q = x);

    expect(find.byKey(const Key('venue-banner')), findsOneWidget);
    expect(find.textContaining('Venue: fake (mock mode)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Warning: Venue: fake')), findsOneWidget); // not a real Venue, so a warning, said in words
    expect(find.text('mock + scratch'), findsOneWidget); // ModeBadge
    expect(find.text('No jobs'), findsOneWidget);

    await t.tap(find.byKey(const Key('add-five')));
    await t.pump();
    expect(find.text('queued'), findsNWidgets(5));
    await t.tap(find.byKey(const Key('run-all')));
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('running'), findsNWidgets(2));
    expect(find.text('waiting for Venue'), findsNWidgets(3));
    expect(find.textContaining('Venue said: the fake node is full'), findsNWidgets(3));
    expect(find.textContaining('hold rq-'), findsNWidgets(2));

    for (var i = 0; i < 80; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('done'), findsNWidgets(5));
    expect(q.peakConcurrent, 2);
    await kit.quit();
  });

  testWidgets('fail fast (from config): the third job is refused, shows the reason, and Retry works', (t) async {
    final kit = await launch(t, before: (ctx) => ctx.config.set('policy', 'failFast'));
    await t.tap(find.byKey(const Key('add-five')));
    await t.pump();
    await t.tap(find.byKey(const Key('run-all')));
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('running'), findsNWidgets(2));
    expect(find.text('refused'), findsNWidgets(3));
    expect(find.text('the fake node is full'), findsNWidgets(3));

    // let the two finish, then retry one refused job
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('done'), findsNWidgets(2));
    await t.tap(find.byKey(const Key('job-3-retry')));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(stateOf(t, 3), contains('done'));
    await kit.quit();
  });

  testWidgets('local mode (real mode, no token): the banner says local and nothing limits the jobs', (t) async {
    final kit = await launch(t, env: {'APP_CONTEXT_MODE': 'real'});
    expect(kit.ctx.venue.kind, 'local');
    expect(find.textContaining('Venue: local (Venue not configured)'), findsOneWidget);
    expect(find.text('scratch'), findsOneWidget); // ModeBadge: scratch but not mock
    await t.tap(find.byKey(const Key('add-five')));
    await t.pump();
    await t.tap(find.byKey(const Key('run-all')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('running'), findsNWidgets(5));
    expect(find.textContaining('(local)'), findsNWidgets(5));
    await t.tap(find.byKey(const Key('cancel-all')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('cancelled'), findsNWidgets(5));
    await kit.quit();
  });

  testWidgets('switching the policy in the UI is saved to the app config', (t) async {
    final kit = await launch(t);
    await t.tap(find.text('fail fast'));
    await t.pump();
    expect(kit.ctx.config.get<String>('policy', ''), 'failFast');
    await kit.quit();
  });

  testWidgets('orphan holds from an earlier run are shown at startup, and Release frees them', (t) async {
    final kit = await testAppContext(t, manifest: manifest, fakeCapacity: 3);
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    // what a crashed run left: two live holds of this consumer, named by an earlier run id
    await t.runAsync(() async {
      await kit.ctx.venue.hold(const VenueNeed(name: 'rq-old-1', contractClass: 'container.run.v1'), leaseSeconds: 300);
      await kit.ctx.venue.hold(const VenueNeed(name: 'rq-old-2', contractClass: 'container.run.v1'), leaseSeconds: 300);
    });
    await kit.mount((ctx) => RenderQueueApp(queue: buildQueue(ctx)));
    await t.pump();

    expect(find.byKey(const Key('orphans')), findsOneWidget);
    expect(find.textContaining('2 holds from an earlier run still count against your quota'), findsOneWidget);
    expect(find.textContaining('rq-old-1 (lapses in'), findsOneWidget);

    await t.tap(find.text('Release'));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('orphans')), findsNothing);
    expect(await t.runAsync(kit.ctx.venue.holds), isEmpty);
    await kit.quit();
  });

  testWidgets('no orphans, no banner', (t) async {
    final kit = await launch(t);
    await t.pump();
    expect(find.byKey(const Key('orphans')), findsNothing);
    await kit.quit();
  });

  testWidgets('lease lost mid-job: the job shows failed with the reason, and Retry is offered', (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final kit = await pumpKitApp(t, manifest: manifest, app: (ctx) {
      final q = RenderQueue(
        venue: FailingRenewVenue(),
        work: (j, c) => fakeRender(j, c),
        renewEvery: const Duration(milliseconds: 300),
        runId: 'ui',
      );
      return RenderQueueApp(queue: q);
    });
    await t.tap(find.byKey(const Key('add-one')));
    await t.pump();
    await t.tap(find.byKey(const Key('run-all')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('running'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('failed'), findsOneWidget);
    expect(find.textContaining('Venue lease lost'), findsOneWidget);
    expect(find.byKey(const Key('job-1-retry')), findsOneWidget);
    await kit.quit();
  });
}
