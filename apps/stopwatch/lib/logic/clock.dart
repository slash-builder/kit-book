/// A clock that survives a restart because it stores the wall-clock instant it started (UTC epoch
/// milliseconds), never a tick count. Immutable: every change returns a new [Clock].
class Clock {
  const Clock({this.accumulatedMs = 0, this.startedAtMs});

  /// Time banked from earlier runs (before the last pause).
  final int accumulatedMs;

  /// When the current run started, or null while stopped.
  final int? startedAtMs;

  bool get running => startedAtMs != null;

  /// Total elapsed time at [nowMs]. A clock set backwards never shows negative time.
  int elapsedMs(int nowMs) {
    final s = startedAtMs;
    if (s == null) return accumulatedMs;
    final run = nowMs - s;
    return accumulatedMs + (run < 0 ? 0 : run);
  }

  Clock start(int nowMs) => running ? this : Clock(accumulatedMs: accumulatedMs, startedAtMs: nowMs);

  Clock pause(int nowMs) => running ? Clock(accumulatedMs: elapsedMs(nowMs)) : this;

  Map<String, Object?> toJson() => {'accumulatedMs': accumulatedMs, 'startedAtMs': startedAtMs};

  static Clock fromJson(Object? j) {
    if (j is! Map) return const Clock();
    final a = j['accumulatedMs'];
    final s = j['startedAtMs'];
    return Clock(accumulatedMs: a is int && a >= 0 ? a : 0, startedAtMs: s is int ? s : null);
  }
}

/// `1:02.3` or `1:02:03.4` (tenths optional).
String formatMs(int ms, {bool tenths = true}) {
  final m = ms < 0 ? 0 : ms;
  final totalSeconds = m ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final min = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final t = (m % 1000) ~/ 100;
  final body = h > 0
      ? '$h:${min.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${min.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return tenths ? '$body.$t' : body;
}

/// Parses `90`, `1:30` or `1:02:03` (seconds, mm:ss, h:mm:ss) into milliseconds; null when not a duration.
int? parseDurationMs(String text) {
  final parts = text.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  var total = 0;
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null || n < 0) return null;
    total = total * 60 + n;
  }
  return total * 1000;
}
