import 'clock.dart';

class Lap {
  const Lap(this.number, this.totalMs, this.splitMs);
  final int number;

  /// Stopwatch reading when the lap was taken.
  final int totalMs;

  /// Time since the previous lap.
  final int splitMs;

  Map<String, Object?> toJson() => {'n': number, 'totalMs': totalMs, 'splitMs': splitMs};

  static Lap? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['n'], t = j['totalMs'], s = j['splitMs'];
    return (n is int && t is int && s is int) ? Lap(n, t, s) : null;
  }
}

class StopwatchModel {
  const StopwatchModel({this.clock = const Clock(), this.laps = const []});
  final Clock clock;
  final List<Lap> laps;

  StopwatchModel toggle(int nowMs) =>
      StopwatchModel(clock: clock.running ? clock.pause(nowMs) : clock.start(nowMs), laps: laps);

  /// A lap only means something while running.
  StopwatchModel lap(int nowMs) {
    if (!clock.running) return this;
    final total = clock.elapsedMs(nowMs);
    final prev = laps.isEmpty ? 0 : laps.last.totalMs;
    return StopwatchModel(clock: clock, laps: [...laps, Lap(laps.length + 1, total, total - prev)]);
  }

  StopwatchModel reset() => const StopwatchModel();

  Map<String, Object?> toJson() => {'clock': clock.toJson(), 'laps': [for (final l in laps) l.toJson()]};

  static StopwatchModel fromJson(Object? j) {
    if (j is! Map) return const StopwatchModel();
    final laps = <Lap>[];
    final raw = j['laps'];
    if (raw is List) {
      for (final l in raw) {
        final lap = Lap.fromJson(l);
        if (lap != null) laps.add(lap);
      }
    }
    return StopwatchModel(clock: Clock.fromJson(j['clock']), laps: laps);
  }
}

enum CountdownPhase { idle, running, paused, done }

class CountdownModel {
  const CountdownModel({
    this.durationMs = 60000,
    this.clock = const Clock(),
    this.endedAtMs,
    this.notified = false,
  });

  final int durationMs;
  final Clock clock;

  /// When the countdown reached zero (the true instant, even if the app was closed then).
  final int? endedAtMs;

  /// Whether the person has been told it ended.
  final bool notified;

  CountdownPhase phase() {
    if (endedAtMs != null) return CountdownPhase.done;
    if (clock.running) return CountdownPhase.running;
    return clock.accumulatedMs > 0 ? CountdownPhase.paused : CountdownPhase.idle;
  }

  int remainingMs(int nowMs) {
    if (endedAtMs != null) return 0;
    final r = durationMs - clock.elapsedMs(nowMs);
    return r < 0 ? 0 : r;
  }

  /// When a running countdown will end; null if it is not running.
  int? endsAtMs() {
    final s = clock.startedAtMs;
    return (endedAtMs == null && s != null) ? s + (durationMs - clock.accumulatedMs) : null;
  }

  /// If the time has run out, record the instant it did. Idempotent.
  CountdownModel resolve(int nowMs) {
    if (endedAtMs != null || !clock.running) return this;
    final end = endsAtMs()!;
    if (nowMs < end) return this;
    return CountdownModel(
        durationMs: durationMs, clock: Clock(accumulatedMs: durationMs), endedAtMs: end, notified: notified);
  }

  CountdownModel toggle(int nowMs) {
    final r = resolve(nowMs);
    if (r.endedAtMs != null) return r;
    return CountdownModel(
        durationMs: durationMs, clock: clock.running ? clock.pause(nowMs) : clock.start(nowMs));
  }

  CountdownModel markNotified() =>
      CountdownModel(durationMs: durationMs, clock: clock, endedAtMs: endedAtMs, notified: true);

  /// Back to idle; [durationMs] changes the length (only sensible when not running).
  CountdownModel reset({int? durationMs}) => CountdownModel(durationMs: durationMs ?? this.durationMs);

  Map<String, Object?> toJson() => {
        'durationMs': durationMs,
        'clock': clock.toJson(),
        'endedAtMs': endedAtMs,
        'notified': notified,
      };

  static CountdownModel fromJson(Object? j) {
    if (j is! Map) return const CountdownModel();
    final d = j['durationMs'];
    final e = j['endedAtMs'];
    return CountdownModel(
      durationMs: d is int && d > 0 ? d : 60000,
      clock: Clock.fromJson(j['clock']),
      endedAtMs: e is int ? e : null,
      notified: j['notified'] == true,
    );
  }
}

class AppState {
  const AppState({this.stopwatch = const StopwatchModel(), this.countdown = const CountdownModel()});
  final StopwatchModel stopwatch;
  final CountdownModel countdown;

  AppState copyWith({StopwatchModel? stopwatch, CountdownModel? countdown}) =>
      AppState(stopwatch: stopwatch ?? this.stopwatch, countdown: countdown ?? this.countdown);

  Map<String, Object?> toJson() => {'v': 1, 'stopwatch': stopwatch.toJson(), 'countdown': countdown.toJson()};

  static AppState fromJson(Object? j) {
    if (j is! Map) return const AppState();
    return AppState(stopwatch: StopwatchModel.fromJson(j['stopwatch']), countdown: CountdownModel.fromJson(j['countdown']));
  }
}
