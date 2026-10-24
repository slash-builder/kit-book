import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/logic/models.dart';

void main() {
  group('stopwatch laps', () {
    test('a lap records the total and the split from the previous lap', () {
      var s = const StopwatchModel().toggle(1000);
      s = s.lap(1400);
      s = s.lap(2000);
      expect(s.laps.map((l) => (l.number, l.totalMs, l.splitMs)), [(1, 400, 400), (2, 1000, 600)]);
    });

    test('no lap while stopped', () {
      expect(const StopwatchModel().lap(5).laps, isEmpty);
    });

    test('laps survive a pause and a json round trip', () {
      var s = const StopwatchModel().toggle(0).lap(100).toggle(150);
      final back = StopwatchModel.fromJson(s.toJson());
      expect(back.laps.single.totalMs, 100);
      expect(back.clock.accumulatedMs, 150);
      expect(back.clock.running, isFalse);
    });

    test('damaged laps are dropped, not fatal', () {
      final s = StopwatchModel.fromJson({
        'laps': [
          {'n': 1, 'totalMs': 1, 'splitMs': 1},
          'junk',
          {'n': 'x'}
        ]
      });
      expect(s.laps.length, 1);
    });
  });

  group('countdown', () {
    const base = CountdownModel(durationMs: 10000);

    test('idle, running, paused, done', () {
      expect(base.phase(), CountdownPhase.idle);
      final r = base.toggle(1000);
      expect(r.phase(), CountdownPhase.running);
      expect(r.remainingMs(4000), 7000);
      final p = r.toggle(4000);
      expect(p.phase(), CountdownPhase.paused);
      expect(p.remainingMs(99999), 7000);
      expect(r.resolve(20000).phase(), CountdownPhase.done);
    });

    test('it records the true end instant even if resolved long afterwards', () {
      final r = base.toggle(1000);
      expect(r.endsAtMs(), 11000);
      final d = r.resolve(500000);
      expect(d.endedAtMs, 11000);
      expect(d.remainingMs(500000), 0);
      expect(d.notified, isFalse);
      expect(d.markNotified().notified, isTrue);
    });

    test('resolve is a no-op before the end and idempotent after', () {
      final r = base.toggle(1000);
      expect(identical(r.resolve(5000), r), isTrue);
      final d = r.resolve(50000);
      expect(identical(d.resolve(90000), d), isTrue);
    });

    test('pausing then resuming moves the end', () {
      final r = base.toggle(0).toggle(4000).toggle(10000);
      expect(r.endsAtMs(), 16000);
    });

    test('toggling after the time ran out resolves rather than restarts', () {
      final r = base.toggle(0).toggle(11000);
      expect(r.phase(), CountdownPhase.done);
    });

    test('reset can change the length', () {
      expect(base.toggle(0).reset(durationMs: 5000).durationMs, 5000);
      expect(base.toggle(0).reset().phase(), CountdownPhase.idle);
    });

    test('json round trip keeps a running countdown running', () {
      final r = CountdownModel.fromJson(base.toggle(1000).toJson());
      expect(r.phase(), CountdownPhase.running);
      expect(r.endsAtMs(), 11000);
    });
  });

  test('AppState from junk is the default state', () {
    expect(AppState.fromJson(42).stopwatch.laps, isEmpty);
    expect(AppState.fromJson({'countdown': 'x'}).countdown.durationMs, 60000);
  });
}
