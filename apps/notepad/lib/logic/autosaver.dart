import 'dart:async';

/// Runs [save] a short while after the last [schedule], so typing is not a disk write per key.
class Autosaver {
  Autosaver(this.delay, this.save);

  final Duration delay;
  final void Function() save;
  Timer? _timer;

  bool get pending => _timer != null;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      save();
    });
  }

  /// Saves now if something is waiting (on switching notes and on quit).
  void flush() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    save();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
