import 'dart:async';

import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../logic/job.dart';
import '../logic/render_queue.dart';

class RenderQueueApp extends StatelessWidget {
  const RenderQueueApp({super.key, required this.queue});
  final RenderQueue queue;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppContextScope.of(context).manifest.name,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
        home: QueueScreen(queue: queue),
      );
}

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.queue});
  final RenderQueue queue;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  StreamSubscription<void>? _sub;
  Timer? _timer;
  var _added = 0;

  RenderQueue get q => widget.queue;

  @override
  void initState() {
    super.initState();
    _sub = q.changes.listen((_) => setState(() {}));
    q.scanOrphans(); // holds a crashed earlier run left behind (needs Venue; a no-op for the local and fake sessions)
    // Progress changes inside jobs without a notification; a light poll keeps the bars moving.
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (q.runningNow > 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _addJobs(int n) {
    for (var i = 0; i < n; i++) {
      _added++;
      q.add(name: 'render-$_added', durationMs: 3000 + (_added * 700) % 3000);
    }
  }

  void _setPolicy(RefusalPolicy p) {
    q.policy = p;
    AppContextScope.of(context).config.set('policy', p == RefusalPolicy.failFast ? 'failFast' : 'wait');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    final jobs = q.jobs;
    final venue = q.venue;
    return PageScaffold(
      title: ctx.manifest.name,
      actions: [ModeBadge.forContext(ctx), const SizedBox(width: 12)],
      // The Venue session's one-sentence description. Green-ish (success) only for a real daemon; fake and local sessions
      // give no cross-app protection, which is what the warning says.
      banner: StatusBanner(
        key: const Key('venue-banner'),
        severity: venue.kind == 'venue' ? Severity.success : Severity.warning,
        message: venue.description,
      ),
      // ctx.notes also carries the Venue description, already shown in the banner above, so it is filtered out.
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text('${q.runningNow} running now, peak ${q.peakConcurrent}', key: const Key('venue-counts')),
        ),
        NotesBanner(notes: [for (final n in ctx.notes) if (n.text != venue.description) n]),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton(key: const Key('add-one'), onPressed: () => _addJobs(1), child: const Text('Add job')),
            OutlinedButton(key: const Key('add-five'), onPressed: () => _addJobs(5), child: const Text('Add 5 jobs')),
            FilledButton(key: const Key('run-all'), onPressed: jobs.any((j) => j.state == JobState.queued) ? q.runAll : null, child: const Text('Run all')),
            TextButton(key: const Key('cancel-all'), onPressed: jobs.any((j) => !j.state.finished) ? q.cancelAll : null, child: const Text('Cancel all')),
            TextButton(key: const Key('clear'), onPressed: jobs.any((j) => j.state.finished) ? q.clearFinished : null, child: const Text('Clear finished')),
            const SizedBox(width: 16),
            const Text('When Venue refuses:'),
            SegmentedButton<RefusalPolicy>(
              key: const Key('policy'),
              segments: const [
                ButtonSegment(value: RefusalPolicy.wait, label: Text('wait')),
                ButtonSegment(value: RefusalPolicy.failFast, label: Text('fail fast')),
              ],
              selected: {q.policy},
              onSelectionChanged: (s) => _setPolicy(s.first),
            ),
          ]),
        ),
        if (q.orphans.isNotEmpty) _OrphanBanner(queue: q),
        const Divider(height: 1),
        Expanded(
          child: jobs.isEmpty
              ? const EmptyState(title: 'No jobs', body: 'Add some, then Run all.')
              : ListView(children: [for (final j in jobs) _JobTile(job: j, queue: q)]),
        ),
      ]),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.queue});
  final Job job;
  final RenderQueue queue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (job.state) {
      JobState.done => Colors.green,
      JobState.running => scheme.primary,
      JobState.waiting => Colors.orange,
      JobState.refused || JobState.failed => scheme.error,
      _ => Colors.grey,
    };
    final detail = [
      if (job.holdName != null) 'hold ${job.holdName} (${job.holdKind})',
      if (job.reason != null) job.reason!,
      if (job.attempts > 1) 'asked ${job.attempts} times',
    ].join('\n');
    return ListTile(
      key: Key('job-${job.id}'),
      title: Text(job.name),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (job.state == JobState.running) LinearProgressIndicator(value: job.progress),
        if (detail.isNotEmpty) Text(detail, key: Key('job-${job.id}-detail')),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Chip(
          key: Key('job-${job.id}-state'),
          label: Text(job.state.label),
          side: BorderSide(color: color),
        ),
        if (job.state == JobState.refused || job.state == JobState.failed || job.state == JobState.cancelled)
          IconButton(key: Key('job-${job.id}-retry'), tooltip: 'Retry', icon: const Icon(Icons.refresh), onPressed: () => queue.retry(job)),
        if (!job.state.finished)
          IconButton(key: Key('job-${job.id}-cancel'), tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: () => queue.cancel(job)),
      ]),
    );
  }
}

/// Holds this consumer still has at Venue that this run did not take: what a crash left behind. They count against the
/// quota until their lease lapses, so a relaunched app is refused. Shows when each lapses and offers to release them.
class _OrphanBanner extends StatelessWidget {
  const _OrphanBanner({required this.queue});
  final RenderQueue queue;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lines = [
      for (final h in queue.orphans)
        h.expiresAt == null ? h.name : '${h.name} (lapses in ${h.expiresAt!.difference(now).inSeconds.clamp(0, 86400)} s)',
    ];
    final n = queue.orphans.length;
    return StatusBanner(
      key: const Key('orphans'),
      severity: Severity.warning,
      message: [
        '$n hold${n == 1 ? '' : 's'} from an earlier run still count against your quota',
        ...lines,
        if (queue.orphansMayBeAnotherCopys) 'Another copy of this app is running; these may be its jobs, not a crash.',
      ].join('\n'),
      action: CandidateAction(label: 'Release', onPressed: queue.releaseOrphans),
    );
  }
}
