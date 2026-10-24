import 'dart:async';

import 'job.dart';
import 'render_queue.dart';

/// A pretend render: sleeps in small steps, reporting progress, and stops early when cancelled.
/// (Sleep, not a CPU loop: there is no GPU here and a busy loop would only freeze the demo.)
Future<void> fakeRender(Job job, CancelToken cancel, {Duration step = const Duration(milliseconds: 100)}) async {
  final total = job.durationMs;
  var spent = 0;
  while (spent < total) {
    if (cancel.isCancelled) throw JobCancelled();
    await Future.any([Future<void>.delayed(step), cancel.whenCancelled]);
    spent += step.inMilliseconds;
    job.progress = (spent / total).clamp(0.0, 1.0);
  }
  if (cancel.isCancelled) throw JobCancelled();
}
