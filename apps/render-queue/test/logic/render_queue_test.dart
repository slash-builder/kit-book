import 'dart:async';

import 'package:application_kit/application_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:render_queue/logic/fake_render.dart';
import 'package:render_queue/logic/job.dart';
import 'package:render_queue/logic/render_queue.dart';

/// A session whose every call fails like a daemon that went away.
class DeadVenue extends FakeVenue {
  @override
  Future<VenueHold> hold(VenueNeed need, {int leaseSeconds = 300}) async => throw VenueUnavailable('connection refused');
}

/// What the real RemoteVenue now throws when the consumer is at its live-hold limit (HTTP 403, seen against a real
/// venued): a typed `forbidden` refusal. [ownHolds] is what `holds()` reports, which the app uses to guess whether the
/// 403 is its own limit (it holds something) or a missing grant (it holds nothing).
class ForbiddenVenue extends FakeVenue {
  ForbiddenVenue(this.message, {this.ownHolds = 0});
  final String message;
  final int ownHolds;
  @override
  Future<VenueHold> hold(VenueNeed need, {int leaseSeconds = 300}) async =>
      throw VenueRefused(message, kind: VenueRefusalKind.forbidden);
  @override
  Future<List<VenueHold>> holds() async => [for (var i = 0; i < ownHolds; i++) VenueHold('other-$i', 'fake', null)];
}

/// A session whose lease renewals fail after [okRenewals] good ones (a daemon that went away, or a lapsed lease).
class FailingRenewVenue extends FakeVenue {
  FailingRenewVenue({this.okRenewals = 0}) : super(capacity: 3);
  final int okRenewals;
  int renewCalls = 0;
  @override
  Future<void> renew(VenueHold h) async {
    log.add('renew ${h.name}');
    if (++renewCalls > okRenewals) throw VenueUnavailable('renew: connection reset');
  }
}

/// A session whose `holds()` or `release` fails.
class BrokenOrphanVenue extends FakeVenue {
  BrokenOrphanVenue({this.failHolds = false, this.failRelease = false}) : super(capacity: 3);
  final bool failHolds, failRelease;
  @override
  Future<List<VenueHold>> holds() async => failHolds ? throw VenueUnavailable('holds: connection refused') : super.holds();
  @override
  Future<void> release(VenueHold h) async => failRelease ? throw VenueUnavailable('release: connection refused') : super.release(h);
}

RenderQueue queueWith(VenueSession v,
        {RefusalPolicy policy = RefusalPolicy.wait, RenderWork? work, int maxWaitMs = 5000, Duration? renewEvery, bool Function()? other}) =>
    RenderQueue(
      venue: v,
      work: work ?? (j, c) => fakeRender(j, c, step: const Duration(milliseconds: 5)),
      policy: policy,
      maxWait: Duration(milliseconds: maxWaitMs),
      retryEvery: const Duration(milliseconds: 10),
      leaseSeconds: 30,
      renewEvery: renewEvery,
      anotherCopyRunning: other,
      runId: 't',
    );

void main() {
  test('fail fast: jobs beyond the node capacity are refused with the reason, the rest run', () async {
    final gate = Completer<void>();
    final q = queueWith(FakeVenue(capacity: 2), policy: RefusalPolicy.failFast, work: (j, c) => gate.future);
    for (var i = 0; i < 4; i++) {
      q.add(durationMs: 1);
    }
    q.runAll();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(q.jobs.map((j) => j.state), [JobState.running, JobState.running, JobState.refused, JobState.refused]);
    expect(q.jobs[2].reason, 'the fake node is full');
    expect(q.peakConcurrent, 2);
    gate.complete();
    await q.idle();
    expect(q.jobs.take(2).map((j) => j.state), [JobState.done, JobState.done]);
    // a refused job can be retried once room is free
    q.retry(q.jobs[2]);
    await q.idle();
    expect(q.jobs[2].state, JobState.done);
  });

  test('wait: the same four jobs all finish, never more than two at once', () async {
    final v = FakeVenue(capacity: 2);
    final q = queueWith(v);
    for (var i = 0; i < 4; i++) {
      q.add(durationMs: 40);
    }
    q.runAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(q.jobs.where((j) => j.state == JobState.waiting).length, 2);
    expect(q.jobs.firstWhere((j) => j.state == JobState.waiting).reason, 'Venue said: the fake node is full');
    await q.idle();
    expect(q.jobs.every((j) => j.state == JobState.done), isTrue);
    expect(q.peakConcurrent, 2);
    expect(q.jobs.where((j) => j.attempts > 1), isNotEmpty);
    // every granted hold was released (refused attempts were never granted, so they have nothing to release)
    expect(v.log.where((l) => l.startsWith('release')).length, 4);
  });

  test('wait gives up after maxWait and says so', () async {
    final gate = Completer<void>();
    final q = queueWith(FakeVenue(capacity: 1), work: (j, c) => gate.future, maxWaitMs: 40);
    q.add();
    q.add();
    q.runAll();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(q.jobs[1].state, JobState.refused);
    expect(q.jobs[1].reason, contains('still refused after'));
    expect(q.jobs[1].reason, contains('the fake node is full'));
    gate.complete();
    await q.idle();
  });

  test('hold names are unique and carry the run id', () async {
    final v = FakeVenue(capacity: 10);
    final q = queueWith(v);
    for (var i = 0; i < 3; i++) {
      q.add(durationMs: 1);
    }
    q.runAll();
    await q.idle();
    expect(q.jobs.map((j) => j.holdName), ['rq-t-1', 'rq-t-2', 'rq-t-3']);
    expect(q.jobs.every((j) => j.holdKind == 'fake'), isTrue);
  });

  test('cancel a waiting job, and a running one (its hold is released)', () async {
    final v = FakeVenue(capacity: 1);
    final q = queueWith(v, work: (j, c) => fakeRender(j, c, step: const Duration(milliseconds: 5)));
    q.add(durationMs: 10000);
    q.add(durationMs: 10000);
    q.runAll();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(q.jobs[1].state, JobState.waiting);
    q.cancel(q.jobs[1]);
    q.cancel(q.jobs[0]);
    await q.idle();
    expect(q.jobs.map((j) => j.state), [JobState.cancelled, JobState.cancelled]);
    expect(v.log, contains('release rq-t-1'));
    expect(q.runningNow, 0);
  });

  test('cancelling a queued job never asks Venue', () async {
    final v = FakeVenue();
    final q = queueWith(v);
    final j = q.add();
    q.cancel(j);
    q.runAll();
    await q.idle();
    expect(j.state, JobState.cancelled);
    expect(v.log, isEmpty);
  });

  test('shutdown (the close hook) cancels running jobs and releases every hold', () async {
    final v = FakeVenue(capacity: 3);
    final q = queueWith(v);
    for (var i = 0; i < 3; i++) {
      q.add(durationMs: 60000);
    }
    q.runAll();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(q.runningNow, 3);
    await q.shutdown();
    expect(v.log.where((l) => l.startsWith('release')).length, 3);
  });

  test('a Venue that cannot be reached fails the job with the reason instead of hanging', () async {
    final q = queueWith(DeadVenue());
    final j = q.add();
    q.runAll();
    await q.idle();
    expect(j.state, JobState.failed);
    expect(j.reason, contains('connection refused'));
  });

  test('local session: no cross-app limit, so every job runs at once (and the banner must say local)', () async {
    final q = queueWith(LocalVenue('Venue not configured'));
    for (var i = 0; i < 5; i++) {
      q.add(durationMs: 30);
    }
    q.runAll();
    await q.idle();
    expect(q.peakConcurrent, 5);
    expect(q.jobs.every((j) => j.holdKind == 'local'), isTrue);
  });

  test('a work error fails the job and still releases the hold', () async {
    final v = FakeVenue();
    final q = queueWith(v, work: (j, c) async => throw StateError('encoder crashed'));
    final j = q.add();
    q.runAll();
    await q.idle();
    expect(j.state, JobState.failed);
    expect(j.reason, contains('encoder crashed'));
    expect(v.log, contains('release rq-t-1'));
  });

  test('clearFinished keeps what is still in flight', () async {
    final gate = Completer<void>();
    final q = queueWith(FakeVenue(capacity: 1), policy: RefusalPolicy.failFast, work: (j, c) => gate.future);
    q.add();
    q.add();
    q.runAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    q.clearFinished();
    expect(q.jobs.length, 1);
    gate.complete();
    await q.idle();
  });

  group('the real daemon refuses with HTTP 403, which the Kit now types as forbidden', () {
    test('over the live-hold limit (it holds something itself): treated as a refusal, with the daemon\'s words', () async {
      final q = queueWith(ForbiddenVenue('render-queue already holds 3 live placements (limit 3)', ownHolds: 3), policy: RefusalPolicy.failFast);
      final j = q.add();
      q.runAll();
      await q.idle();
      expect(j.state, JobState.refused);
      expect(j.reason, 'render-queue already holds 3 live placements (limit 3)');
    });

    test('over the limit under the wait policy: retried, then refused after maxWait', () async {
      final q = queueWith(ForbiddenVenue('render-queue already holds 3 live placements (limit 3)', ownHolds: 3), maxWaitMs: 40);
      final j = q.add();
      q.runAll();
      await q.idle();
      expect(j.state, JobState.refused);
      expect(j.attempts, greaterThan(1));
      expect(j.reason, contains('still refused after'));
    });

    test('a 403 while it holds nothing (no grant) is a permanent refusal: no waiting', () async {
      final q = queueWith(ForbiddenVenue('principal render-queue has no grant for container.run.v1'));
      final j = q.add();
      q.runAll();
      await q.idle();
      expect(j.state, JobState.refused);
      expect(j.attempts, 0, reason: 'never retried');
      expect(j.reason, 'principal render-queue has no grant for container.run.v1');
    });

    test('the daemon\'s JSON body is unwrapped to its message for the person', () async {
      final q = queueWith(
          ForbiddenVenue('{"error":{"code":"forbidden","message":"render-queue already holds 3 live placements (limit 3)"}}', ownHolds: 3),
          policy: RefusalPolicy.failFast);
      final j = q.add();
      q.runAll();
      await q.idle();
      expect(j.reason, 'render-queue already holds 3 live placements (limit 3)');
    });

    test('a 5xx or a dead socket is still a failure, not a refusal', () async {
      final q = queueWith(DeadVenue());
      final j = q.add();
      q.runAll();
      await q.idle();
      expect(j.state, JobState.failed);
    });
  });

  group('lease lost (onLeaseLost): the job fails visibly and stops', () {
    test('a failed renewal fails the job, stops the work, says why, and still releases the hold', () async {
      final v = FailingRenewVenue();
      final q = queueWith(v, renewEvery: const Duration(milliseconds: 10), work: (j, c) => fakeRender(j, c, step: const Duration(milliseconds: 5)));
      final j = q.add(durationMs: 60000);
      q.runAll();
      await q.idle();
      expect(j.state, JobState.failed);
      expect(j.reason, contains('Venue lease lost'));
      expect(j.reason, contains('connection reset'));
      expect(j.progress, lessThan(0.1), reason: 'the work was stopped, not run to the end');
      expect(q.runningNow, 0);
      expect(v.log, contains('release rq-t-1'));
    });

    test('only that job fails: a healthy job in the same queue is done', () async {
      // Renewals 1..2 fail for whoever asks; the short job finishes before its first renewal at 200 ms.
      final v = FailingRenewVenue();
      final q = queueWith(v, renewEvery: const Duration(milliseconds: 200), work: (j, c) => fakeRender(j, c, step: const Duration(milliseconds: 5)));
      final quick = q.add(durationMs: 20);
      final slow = q.add(durationMs: 60000);
      q.runAll();
      await q.idle();
      expect(quick.state, JobState.done);
      expect(slow.state, JobState.failed);
    });

    test('the person can Retry a lease-lost job; it gets a new hold', () async {
      final v = FailingRenewVenue(okRenewals: 1);
      final q = queueWith(v, renewEvery: const Duration(milliseconds: 10), work: (j, c) => fakeRender(j, c, step: const Duration(milliseconds: 5)));
      final j = q.add(durationMs: 60000);
      q.runAll();
      await q.idle();
      expect(j.state, JobState.failed);
      q.retry(j);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(j.state, anyOf(JobState.waiting, JobState.running));
      expect(j.reason, isNull, reason: 'the old failure is cleared on Retry');
      q.cancel(j);
      await q.idle();
    });

    test('a cancel by the person is still "cancelled", not "lease lost"', () async {
      final v = FakeVenue();
      final q = queueWith(v, renewEvery: const Duration(milliseconds: 10));
      final j = q.add(durationMs: 60000);
      q.runAll();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      q.cancel(j);
      await q.idle();
      expect(j.state, JobState.cancelled);
    });
  });

  group('orphan holds (venue.holds() at startup)', () {
    const need = VenueNeed(name: 'x', contractClass: 'container.run.v1');

    test('holds a previous run left behind are found; this run\'s own jobs are not orphans', () async {
      final v = FakeVenue(capacity: 5);
      await v.hold(need.copyNamed('rq-old-1'));
      await v.hold(need.copyNamed('rq-old-2'));
      final gate = Completer<void>();
      final q = queueWith(v, work: (j, c) => gate.future);
      q.add();
      q.runAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await q.scanOrphans();
      expect(q.orphans.map((h) => h.name), ['rq-old-1', 'rq-old-2']);
      expect(q.orphanScanError, isNull);
      gate.complete();
      await q.idle();
    });

    test('releaseOrphans frees them at Venue and reports how many', () async {
      final v = FakeVenue(capacity: 5);
      await v.hold(need.copyNamed('rq-old-1'));
      await v.hold(need.copyNamed('rq-old-2'));
      final q = queueWith(v);
      await q.scanOrphans();
      expect(await q.releaseOrphans(), 2);
      expect(q.orphans, isEmpty);
      expect(await v.holds(), isEmpty);
      expect(v.log, containsAll(['release rq-old-1', 'release rq-old-2']));
    });

    test('nothing left behind: no orphans, no error', () async {
      final q = queueWith(FakeVenue());
      await q.scanOrphans();
      expect(q.orphans, isEmpty);
      expect(q.orphanScanError, isNull);
    });

    test('a scan that cannot reach Venue records the error and shows no orphans', () async {
      final q = queueWith(BrokenOrphanVenue(failHolds: true));
      await q.scanOrphans();
      expect(q.orphans, isEmpty);
      expect(q.orphanScanError, isA<VenueUnavailable>());
    });

    test('a release that fails leaves the hold listed (its lease will lapse) and counts 0', () async {
      final v = BrokenOrphanVenue(failRelease: true);
      await v.hold(need.copyNamed('rq-old-1'));
      final q = queueWith(v);
      await q.scanOrphans();
      expect(await q.releaseOrphans(), 0);
      expect(q.orphans.map((h) => h.name), ['rq-old-1']);
    });

    test('with another live copy of the app running, the orphans are flagged as possibly its', () async {
      final v = FakeVenue();
      await v.hold(need.copyNamed('rq-other-1'));
      final q = queueWith(v, other: () => true);
      await q.scanOrphans();
      expect(q.orphansMayBeAnotherCopys, isTrue);
      expect(queueWith(v).orphansMayBeAnotherCopys, isFalse);
    });
  });

  group('VenueSession.withHoldWaiting (the Kit method, driven the way the queue drives it)', () {
    const need = VenueNeed(name: 'n', contractClass: 'container.run.v1');

    test('with no maxWait it is plain withHold', () async {
      final v = FakeVenue(capacity: 0);
      await expectLater(v.withHoldWaiting(need, (h) async => 1, maxWait: Duration.zero), throwsA(isA<VenueRefused>()));
      expect(v.log, ['hold n']);
    });

    test('retries until a hold is free', () async {
      final v = FakeVenue(capacity: 1);
      final first = await v.hold(const VenueNeed(name: 'other', contractClass: 'container.run.v1'));
      Timer(const Duration(milliseconds: 35), () => v.release(first));
      final seen = <int>[];
      final out = await v.withHoldWaiting(need, (h) async => h.name,
          maxWait: const Duration(seconds: 2), retryEvery: const Duration(milliseconds: 10), onWaiting: (r, a) => seen.add(a));
      expect(out, 'n');
      expect(seen, isNotEmpty);
    });

    test('a hold refused as forbidden with nothing held is not retried', () async {
      final v = ForbiddenVenue('no grant');
      var asked = 0;
      await expectLater(
          v.withHoldWaiting(need, (h) async => 1,
              maxWait: const Duration(seconds: 5), retryEvery: const Duration(milliseconds: 10), onWaiting: (r, a) => asked++),
          throwsA(isA<VenueRefused>().having((e) => e.kind, 'kind', VenueRefusalKind.forbidden)));
      expect(asked, 0);
    });

    test('a VenueRefused thrown by the body (after the hold was granted) is not treated as Venue refusing the hold', () async {
      final v = FakeVenue(capacity: 5);
      var bodyRuns = 0;
      await expectLater(
          v.withHoldWaiting(need, (h) async {
            bodyRuns++;
            throw VenueRefused('inner', kind: VenueRefusalKind.doesNotFit);
          }, maxWait: const Duration(seconds: 5), retryEvery: const Duration(milliseconds: 10)),
          throwsA(isA<VenueRefused>()));
      expect(bodyRuns, 1);
    });

    test('a cancel while waiting throws HoldWaitCancelled', () async {
      final v = FakeVenue(capacity: 0);
      final c = Completer<void>();
      Timer(const Duration(milliseconds: 25), c.complete);
      await expectLater(
          v.withHoldWaiting(need, (h) async => 1,
              maxWait: const Duration(seconds: 5), retryEvery: const Duration(milliseconds: 10), cancel: c.future),
          throwsA(isA<HoldWaitCancelled>()));
    });
  });
}

extension on VenueNeed {
  VenueNeed copyNamed(String name) => VenueNeed(name: name, contractClass: contractClass);
}
