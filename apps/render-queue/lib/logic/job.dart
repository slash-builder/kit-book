import 'dart:async';

enum JobState { queued, waiting, running, done, refused, failed, cancelled }

extension JobStateLabel on JobState {
  String get label => switch (this) {
        JobState.queued => 'queued',
        JobState.waiting => 'waiting for Venue',
        JobState.running => 'running',
        JobState.done => 'done',
        JobState.refused => 'refused',
        JobState.failed => 'failed',
        JobState.cancelled => 'cancelled',
      };

  bool get finished => this == JobState.done || this == JobState.refused || this == JobState.failed || this == JobState.cancelled;
}

class Job {
  Job(this.id, this.name, this.durationMs);
  final int id;
  final String name;
  final int durationMs;

  JobState state = JobState.queued;

  /// 0..1 while running.
  double progress = 0;

  /// Why the job is waiting (last refusal), or was refused or failed.
  String? reason;

  /// How many times Venue was asked.
  int attempts = 0;

  /// The hold's name and where it came from (`venue`, `local`, `fake`) once granted.
  String? holdName;
  String? holdKind;
}

/// Cooperative cancel: `isCancelled` for loops, `whenCancelled` for waiting.
class CancelToken {
  final _completer = Completer<void>();
  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
