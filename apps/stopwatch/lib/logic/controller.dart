import 'dart:async';

import '../coordination/timer_peers.dart';
import 'models.dart';
import 'state_store.dart';

typedef NowMs = int Function();

int wallClockMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

/// Owns the [AppState], saves it on every change, and watches for the countdown running out.
/// No Flutter: the UI listens to [changes] and the notifier is a callback.
class StopwatchController {
  StopwatchController(this._store, this._state, {NowMs? now, this.onCountdownDone}) : _now = now ?? wallClockMs;

  final StateStore _store;
  final NowMs _now;
  AppState _state;
  Timer? _endTimer;
  bool _disposed = false;
  final _changes = StreamController<void>.broadcast();

  /// Called once per countdown, when it ends (also on relaunch if it ended while the app was closed).
  final void Function(CountdownModel done)? onCountdownDone;

  /// Peer coordination for the shared countdown, when the app started it (null in tests that do not want it).
  TimerPeers? peers;

  /// Called after the PERSON started, paused or reset the countdown (not after [adoptCountdown] or the end timer): the
  /// coordination layer publishes it to the other copies.
  void Function()? onCountdownCommand;

  AppState get state => _state;
  int get nowMs => _now();
  Stream<void> get changes => _changes.stream;

  static StopwatchController load(StateStore store, {NowMs? now, void Function(CountdownModel)? onCountdownDone}) {
    final c = StopwatchController(store, store.load(), now: now, onCountdownDone: onCountdownDone);
    c.tick();
    return c;
  }

  void _set(AppState s) {
    _state = s;
    _store.save(s);
    if (!_changes.isClosed) _changes.add(null);
    _arm();
  }

  void toggleStopwatch() => _set(_state.copyWith(stopwatch: _state.stopwatch.toggle(_now())));
  void lap() => _set(_state.copyWith(stopwatch: _state.stopwatch.lap(_now())));
  void resetStopwatch() => _set(_state.copyWith(stopwatch: _state.stopwatch.reset()));

  void toggleCountdown() => _command(_state.copyWith(countdown: _state.countdown.toggle(_now())));
  void resetCountdown({int? durationMs}) => _command(_state.copyWith(countdown: _state.countdown.reset(durationMs: durationMs)));

  /// Replaces the countdown with one that came from another copy. Does not call [onCountdownCommand] (no echo).
  void adoptCountdown(CountdownModel c) => _set(_state.copyWith(countdown: c));

  void _command(AppState s) {
    final before = _state.countdown;
    _set(s);
    if (!identical(before, _state.countdown)) onCountdownCommand?.call();
  }

  /// Resolve the countdown against the clock; fire [onCountdownDone] once. Called by the end timer and on load.
  void tick() {
    if (_disposed) return;
    final resolved = _state.countdown.resolve(_now());
    if (resolved.endedAtMs != null && !resolved.notified) {
      onCountdownDone?.call(resolved);
      _set(_state.copyWith(countdown: resolved.markNotified()));
    } else if (!identical(resolved, _state.countdown)) {
      _set(_state.copyWith(countdown: resolved));
    } else {
      _arm();
    }
  }

  void _arm() {
    _endTimer?.cancel();
    _endTimer = null;
    final ends = _state.countdown.endsAtMs();
    if (ends == null || _disposed) return;
    final wait = ends - _now();
    // A small margin so the timer never wakes a hair before the end and re-arms in a loop.
    _endTimer = Timer(Duration(milliseconds: wait < 0 ? 0 : wait + 5), tick);
  }

  /// Persist now (the close hook).
  void save() => _store.save(_state);

  void dispose() {
    if (_disposed) return;
    save();
    _disposed = true;
    _endTimer?.cancel();
    _changes.close();
  }
}
