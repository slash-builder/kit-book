import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/logic/controller.dart';
import 'package:stopwatch/logic/models.dart';
import 'package:stopwatch/logic/state_store.dart';

void main() {
  late Directory tmp;
  late File file;
  var now = 1000000;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stopwatch-test-');
    file = File('${tmp.path}/state/state.json');
    now = 1000000;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  StopwatchController open({void Function(CountdownModel)? done}) =>
      StopwatchController.load(StateStore(file), now: () => now, onCountdownDone: done);

  test('a running stopwatch survives quitting and relaunching, and counts the time in between', () {
    final a = open();
    a.toggleStopwatch();
    now += 2000;
    a.lap();
    a.dispose(); // quit
    now += 60000; // a minute passes with the app closed
    final b = open(); // relaunch
    expect(b.state.stopwatch.clock.running, isTrue);
    expect(b.state.stopwatch.clock.elapsedMs(now), 62000);
    expect(b.state.stopwatch.laps.single.totalMs, 2000);
    b.dispose();
  });

  test('state is saved on every change, so a crash loses nothing', () {
    final a = open();
    a.toggleStopwatch();
    now += 500;
    a.lap();
    // no dispose: simulate kill -9
    final b = open();
    expect(b.state.stopwatch.laps.length, 1);
    expect(b.state.stopwatch.clock.running, isTrue);
    a.dispose();
    b.dispose();
  });

  test('a paused stopwatch stays paused across a relaunch', () {
    final a = open();
    a.toggleStopwatch();
    now += 3000;
    a.toggleStopwatch();
    a.dispose();
    now += 10000;
    final b = open();
    expect(b.state.stopwatch.clock.elapsedMs(now), 3000);
    b.dispose();
  });

  test('tick fires the done callback once when the countdown ends', () {
    final fired = <CountdownModel>[];
    final c = open(done: fired.add);
    c.resetCountdown(durationMs: 5000);
    c.toggleCountdown();
    now += 4000;
    c.tick();
    expect(fired, isEmpty);
    now += 2000;
    c.tick();
    c.tick();
    expect(fired.length, 1);
    expect(c.state.countdown.phase(), CountdownPhase.done);
    expect(c.state.countdown.notified, isTrue);
    c.dispose();
  });

  test('a countdown that ended while the app was closed notifies once on relaunch', () {
    final a = open();
    a.resetCountdown(durationMs: 5000);
    a.toggleCountdown();
    a.dispose();
    now += 600000;
    final fired = <CountdownModel>[];
    final b = open(done: fired.add);
    expect(fired.length, 1);
    expect(fired.single.endedAtMs, 1005000);
    b.dispose();
    final again = <CountdownModel>[];
    open(done: again.add).dispose();
    expect(again, isEmpty, reason: 'already told the person');
  });

  test('the end timer fires by itself (real time, short countdown)', () async {
    final real = StopwatchController.load(StateStore(file), onCountdownDone: (_) {});
    final done = Completer<void>();
    final c = StopwatchController(StateStore(File('${tmp.path}/other.json')), const AppState(),
        onCountdownDone: (_) => done.complete());
    c.resetCountdown(durationMs: 50);
    c.toggleCountdown();
    await done.future.timeout(const Duration(seconds: 3));
    expect(c.state.countdown.phase(), CountdownPhase.done);
    c.dispose();
    real.dispose();
  });

  test('a damaged state file is reported and the app starts fresh', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{not json');
    final store = StateStore(file);
    final s = store.load();
    expect(store.problem, contains('not valid JSON'));
    expect(s.stopwatch.clock.running, isFalse);
  });

  test('changes stream announces mutations', () async {
    final c = open();
    final seen = <void>[];
    final sub = c.changes.listen(seen.add);
    c.toggleStopwatch();
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, 1);
    await sub.cancel();
    c.dispose();
  });
}
