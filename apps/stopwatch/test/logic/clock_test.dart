import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/logic/clock.dart';

void main() {
  test('elapsed is banked time plus the running segment', () {
    final c = const Clock().start(1000);
    expect(c.running, isTrue);
    expect(c.elapsedMs(1500), 500);
    final p = c.pause(2000);
    expect(p.running, isFalse);
    expect(p.elapsedMs(9999), 1000);
    expect(p.start(5000).elapsedMs(5250), 1250);
  });

  test('starting a running clock or pausing a stopped one changes nothing', () {
    final c = const Clock().start(1000);
    expect(identical(c.start(2000), c), isTrue);
    const s = Clock(accumulatedMs: 7);
    expect(identical(s.pause(2000), s), isTrue);
  });

  test('a clock set backwards never shows negative time', () {
    expect(const Clock(accumulatedMs: 100, startedAtMs: 5000).elapsedMs(1000), 100);
  });

  test('json round trip; junk falls back to a stopped clock', () {
    final c = const Clock(accumulatedMs: 12, startedAtMs: 34);
    final back = Clock.fromJson(c.toJson());
    expect(back.accumulatedMs, 12);
    expect(back.startedAtMs, 34);
    expect(Clock.fromJson('nope').running, isFalse);
    expect(Clock.fromJson({'accumulatedMs': -5, 'startedAtMs': 'x'}).accumulatedMs, 0);
  });

  test('formatMs', () {
    expect(formatMs(0), '00:00.0');
    expect(formatMs(61234), '01:01.2');
    expect(formatMs(3723400), '1:02:03.4');
    expect(formatMs(90000, tenths: false), '01:30');
    expect(formatMs(-5), '00:00.0');
  });

  test('parseDurationMs', () {
    expect(parseDurationMs('90'), 90000);
    expect(parseDurationMs('1:30'), 90000);
    expect(parseDurationMs('1:02:03'), 3723000);
    expect(parseDurationMs(' 5 '), 5000);
    expect(parseDurationMs(''), isNull);
    expect(parseDurationMs('a:b'), isNull);
    expect(parseDurationMs('-1'), isNull);
    expect(parseDurationMs('1:2:3:4'), isNull);
  });
}
