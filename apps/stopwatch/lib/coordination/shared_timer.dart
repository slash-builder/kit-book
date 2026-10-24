/// The stopwatch app's meaning of "peers": ONE shared countdown, replicated between copies, plus a "finished" signal.
///
/// Pure Dart (no Flutter). The Kit finds, authenticates, connects and routes; everything below is the app's decision.
///
/// ## The model, and why
///  * The shared thing is the countdown only (the count-up stopwatch and its laps stay per copy: nobody asked to share them).
///  * **Last writer wins, ordered by a Lamport stamp `(rev, writer)`**, not by wall-clock time and not by an owner copy:
///    commands are rare human actions, so a conflict is two people pressing Start within one network round trip, and either
///    outcome is acceptable; a stamp needs no synchronised clocks (two machines can disagree by seconds); and there is no
///    owner to lose. An owner model would need an election the Kit does not provide, and would freeze the timer whenever the
///    owner copy quit.
///  * The wire form of a countdown is `{d, e, run, endedAgo}`: lengths and AGES, never absolute instants, so a skewed clock on
///    another machine does not move the end of the timer (error is the network delay).
///  * "Finished" is announced by ONE copy: the writer of the current stamp (it started the run). The others stay quiet, wait
///    for its `timer.finished`, and show "finished on DEVICE". If it never comes (owner quit or hung) the lowest live copy
///    takes over after [takeoverGrace]. Delivery is best effort, so under a partition two copies may both announce; that is
///    at-least-once, on purpose.
///  * A late joiner needs no replay: the state rides in `hello()`, and on `ready` the side that is behind adopts it and the
///    side that is ahead pushes (the hello is a snapshot taken at connect, a command can land between hello and ready).
library;

import 'dart:async';

import 'package:application_kit/application_kit.dart';

import '../logic/clock.dart';
import '../logic/models.dart';

class Stamp implements Comparable<Stamp> {
  const Stamp(this.rev, this.writer);
  final int rev;
  final String writer;

  @override
  int compareTo(Stamp other) => rev != other.rev ? rev.compareTo(other.rev) : writer.compareTo(other.writer);
  bool operator >(Stamp other) => compareTo(other) > 0;
  @override
  bool operator ==(Object other) => other is Stamp && other.rev == rev && other.writer == writer;
  @override
  int get hashCode => Object.hash(rev, writer);

  Map<String, Object?> toJson() => {'rev': rev, 'w': writer};

  static Stamp? parse(Object? j) {
    if (j is! Map) return null;
    final r = j['rev'], w = j['w'];
    return (r is int && r >= 0 && r < 1 << 40 && w is String && w.length <= 128) ? Stamp(r, w) : null;
  }
}

/// A countdown as it travels: its length and how far it has run, in durations only.
class WireCountdown {
  const WireCountdown(this.durationMs, this.elapsedMs, this.running, this.endedAgoMs);
  final int durationMs, elapsedMs;
  final bool running;
  final int? endedAgoMs;

  static const maxDurationMs = 99 * 3600 * 1000;

  static WireCountdown from(CountdownModel c, int nowMs) {
    final ended = c.endedAtMs;
    if (ended != null) return WireCountdown(c.durationMs, c.durationMs, false, nowMs - ended < 0 ? 0 : nowMs - ended);
    return WireCountdown(c.durationMs, c.clock.elapsedMs(nowMs).clamp(0, c.durationMs), c.clock.running, null);
  }

  CountdownModel toModel(int nowMs) {
    final ago = endedAgoMs;
    if (ago != null) {
      return CountdownModel(durationMs: durationMs, clock: Clock(accumulatedMs: durationMs), endedAtMs: nowMs - ago, notified: true);
    }
    return CountdownModel(durationMs: durationMs, clock: running ? Clock(startedAtMs: nowMs - elapsedMs) : Clock(accumulatedMs: elapsedMs));
  }

  Map<String, Object?> toJson() => {'d': durationMs, 'e': elapsedMs, 'run': running, 'endedAgo': endedAgoMs};

  /// Null for anything that is not a sane countdown (a hostile peer can send any JSON).
  static WireCountdown? parse(Object? j) {
    if (j is! Map) return null;
    final d = j['d'], e = j['e'], run = j['run'], ago = j['endedAgo'];
    if (d is! int || d < 1 || d > maxDurationMs || e is! int || e < 0 || e > d || run is! bool) return null;
    if (ago != null && (ago is! int || ago < 0 || ago > 366 * 86400000)) return null;
    return WireCountdown(d, e, run, ago as int?);
  }
}

class Finished {
  const Finished({required this.label, required this.by, required this.local});

  /// The countdown's length, as the person set it ("00:10").
  final String label;
  final PeerId by;

  /// True when this copy is the one announcing; false when another copy told us.
  final bool local;
}

class _State {
  const _State(this.stamp, this.timer, [this.label]);
  final Stamp stamp;
  final WireCountdown timer;
  final String? label;

  static _State? parse(Object? j) {
    if (j is! Map) return null;
    final s = Stamp.parse(j['stamp']), t = WireCountdown.parse(j['timer']), l = j['label'];
    if (s == null || t == null || (l != null && (l is! String || l.length > 64))) return null;
    return _State(s, t, l as String?);
  }
}

class SharedTimerHook extends AppCoordination {
  SharedTimerHook({
    required this.nowMs,
    required this.current,
    required this.adopt,
    required this.onFinished,
    Stamp initial = const Stamp(0, ''),
    this.onStamp,
    this.takeoverGrace = const Duration(seconds: 2),
  }) : stamp = initial;

  final int Function() nowMs;
  final CountdownModel Function() current;

  /// Replace the local countdown with this one WITHOUT calling [changed] again.
  final void Function(CountdownModel) adopt;
  final void Function(Finished) onFinished;
  final void Function(Stamp)? onStamp;
  final Duration takeoverGrace;

  Stamp stamp;
  PeerHub? hub;
  Stamp? _told; // the stamp whose end has been announced (here or by a peer)
  Timer? _grace;

  /// Messages dropped because they were malformed, of an unknown schema, or stale. For tests and diagnostics.
  int ignored = 0;

  String get _me => hub!.id.toString();

  @override
  String get channel => 'timer';
  @override
  void attach(PeerHub hub) => this.hub = hub;

  @override
  Object? hello() => stamp.rev == 0 ? null : _stateJson(current());

  @override
  FutureOr<Admit> admit(Peer peer, Object? theirHello) => const Admit.accept();

  @override
  void onPeer(Peer peer, PeerChange change) {
    if (change != PeerChange.ready) return;
    final theirs = _State.parse(peer.hello);
    if (theirs != null && theirs.stamp > stamp) {
      _take(theirs);
    } else if (stamp.rev > 0 && (theirs == null || stamp > theirs.stamp)) {
      PeerJson.quiet(hub!.send(peer, PeerJson.encode(_stateJson(current())), kind: 'timer.state', schema: 1));
    }
  }

  /// The person started, paused or reset the countdown on THIS copy: it becomes the newest write everywhere.
  void changed() {
    _grace?.cancel();
    stamp = Stamp(stamp.rev + 1, _me);
    onStamp?.call(stamp);
    PeerJson.quiet(hub!.broadcast(PeerJson.encode(_stateJson(current())), kind: 'timer.state', schema: 1));
  }

  /// This copy's countdown ran out. Announce if we are the announcer, else wait for the announcer.
  void countdownEnded(CountdownModel done) {
    if (_told == stamp) return;
    if (_isAnnouncer()) return _announce(done);
    final at = stamp;
    _grace = Timer(takeoverGrace, () {
      if (_told != at && stamp == at) _announce(done);
    });
  }

  bool _isAnnouncer() {
    final h = hub;
    if (h == null || stamp.rev == 0 || stamp.writer == _me) return true;
    final ready = h.readyPeers;
    if (ready.any((p) => p.id.toString() == stamp.writer)) return false; // the owner is alive: it announces
    return ready.every((p) => h.id.compareTo(p.id) < 0); // owner gone: the lowest live copy does
  }

  void _announce(CountdownModel done) {
    _told = stamp;
    final label = formatMs(done.durationMs, tenths: false);
    onFinished(Finished(label: label, by: hub?.id ?? const PeerId('local', 'local'), local: true));
    final h = hub;
    if (h != null) {
      final ended = _stateJson(done)..['label'] = label;
      PeerJson.quiet(h.broadcast(PeerJson.encode(ended), kind: 'timer.finished', schema: 1));
    }
  }

  @override
  void onMessage(Peer from, AppMessage m) {
    if (m.schema != 1 || (m.kind != 'timer.state' && m.kind != 'timer.finished')) {
      ignored++;
      return;
    }
    final s = _State.parse(m.jsonBody);
    if (s == null || (m.kind == 'timer.finished' && s.label == null)) {
      ignored++;
      return;
    }
    if (s.stamp > stamp) {
      _take(s);
    } else if (m.kind == 'timer.finished' && s.stamp == stamp && current().endedAtMs == null) {
      adopt(s.timer.toModel(nowMs()));
    }
    if (m.kind == 'timer.finished' && s.stamp.compareTo(stamp) >= 0 && _told != stamp) {
      _told = stamp;
      _grace?.cancel();
      onFinished(Finished(label: s.label!, by: from.id, local: false));
    } else if (m.kind == 'timer.finished') {
      ignored++; // stale: a finish for a run that has since been reset or replaced
    }
  }

  void _take(_State s) {
    _grace?.cancel();
    stamp = s.stamp;
    onStamp?.call(stamp);
    adopt(s.timer.toModel(nowMs()));
  }

  Map<String, Object?> _stateJson(CountdownModel c) => {'stamp': stamp.toJson(), 'timer': WireCountdown.from(c, nowMs()).toJson()};

  void dispose() => _grace?.cancel();
}
