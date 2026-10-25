import 'dart:async';

import 'package:app_context_kit/app_context_kit.dart';

import 'job.dart';

/// What to do when Venue refuses a hold.
///  - [wait]: the refusal is treated as "full right now": show the job as waiting, ask again every `retryEvery`, and
///    give up (refused, with the reason) after `maxWait`. This is the default because a render job that can wait
///    should not make the person press Run again.
///  - [failFast]: the job is refused at once and stays refused until the person presses Retry. Right when the person
///    would rather know now than wait.
enum RefusalPolicy { wait, failFast }

/// The fake render: takes a job and a cancel token, returns when the "render" is done. Injected so tests are fast.
typedef RenderWork = Future<void> Function(Job job, CancelToken cancel);

/// A queue of jobs where each takes a Venue hold before it runs. Concurrency is not limited here at all: every
/// started job asks Venue, and Venue's answer is the only limit. No Flutter.
class RenderQueue {
  RenderQueue({
    required this.venue,
    required this.work,
    this.policy = RefusalPolicy.wait,
    this.maxWait = const Duration(seconds: 30),
    this.retryEvery = const Duration(seconds: 1),
    this.leaseSeconds = 30,
    this.renewEvery,
    this.anotherCopyRunning,
    String? runId,
  }) : runId = runId ?? DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);

  final VenueSession venue;
  final RenderWork work;
  RefusalPolicy policy;
  Duration maxWait;
  Duration retryEvery;
  int leaseSeconds;

  /// How often a running job renews its lease (the Kit's default is a third of the lease). Tests shorten it.
  Duration? renewEvery;

  /// Whether another live copy of this app is running (so holds that are not ours may be its, not orphans).
  final bool Function()? anotherCopyRunning;

  /// Makes hold names unique across launches and across other apps sharing a daemon.
  final String runId;

  final _jobs = <Job>[];
  final _tokens = <int, CancelToken>{};
  final _inflight = <int, Future<void>>{};
  final _changes = StreamController<void>.broadcast();
  var _nextId = 1;
  var _peak = 0;
  var _running = 0;

  List<Job> get jobs => List.unmodifiable(_jobs);
  Stream<void> get changes => _changes.stream;

  /// The most jobs that were running (holding) at the same moment so far.
  int get peakConcurrent => _peak;
  int get runningNow => _running;

  Job add({String? name, int durationMs = 4000}) {
    final id = _nextId++;
    final j = Job(id, name ?? 'render-$id', durationMs);
    _jobs.add(j);
    _notify();
    return j;
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  String holdNameFor(Job j) => 'rq-$runId-${j.id}';

  /// Start every queued job. Safe to call again.
  void runAll() {
    for (final j in _jobs.where((j) => j.state == JobState.queued)) {
      _start(j);
    }
  }

  /// Put a refused, failed or cancelled job back to queued and start it.
  void retry(Job j) {
    if (j.state != JobState.refused && j.state != JobState.failed && j.state != JobState.cancelled) return;
    j.state = JobState.queued;
    j.reason = null;
    j.progress = 0;
    j.attempts = 0;
    _start(j);
  }

  void cancel(Job j) {
    _tokens[j.id]?.cancel();
    if (j.state == JobState.queued) {
      j.state = JobState.cancelled;
      _notify();
    }
  }

  void cancelAll() {
    for (final j in _jobs) {
      cancel(j);
    }
  }

  void clearFinished() {
    _jobs.removeWhere((j) => j.state.finished);
    _notify();
  }

  /// Completes when no job is in flight (all holds released).
  Future<void> idle() async {
    while (_inflight.isNotEmpty) {
      await Future.wait(_inflight.values.toList());
    }
  }

  // ---- orphan holds: what a previous crash of this consumer left behind ----

  var _orphans = <VenueHold>[];
  Object? _orphanScanError;

  /// Live holds of this consumer that this run did not take: left behind by a crash (kill -9, power loss), or taken by
  /// another running copy. Venue frees them only when their lease lapses, and until then they count against the quota.
  List<VenueHold> get orphans => List.unmodifiable(_orphans);

  /// Set when the scan itself failed (Venue unreachable); null otherwise.
  Object? get orphanScanError => _orphanScanError;

  /// True when [orphans] might belong to another running copy of this app rather than to a crash.
  bool get orphansMayBeAnotherCopys => _orphans.isNotEmpty && (anotherCopyRunning?.call() ?? false);

  /// Asks Venue for this consumer's holds and keeps those whose name is not from this run. Call at startup.
  Future<void> scanOrphans() async {
    try {
      final mine = 'rq-$runId-';
      _orphans = [for (final h in await venue.holds()) if (!h.name.startsWith(mine)) h];
      _orphanScanError = null;
    } catch (e) {
      _orphanScanError = e;
    }
    _notify();
  }

  /// Releases every orphan, then scans again. Returns how many Venue accepted the release of. A failure leaves the hold
  /// in [orphans] (it will lapse by itself).
  Future<int> releaseOrphans() async {
    var released = 0;
    for (final h in List.of(_orphans)) {
      try {
        await venue.release(h);
        released++;
      } catch (_) {
        // still listed after the rescan below; the lease will lapse by itself
      }
    }
    await scanOrphans();
    return released;
  }

  /// The close hook: cancel everything and wait until every hold has been released.
  Future<void> shutdown() async {
    cancelAll();
    await idle();
    await _changes.close();
  }

  void _start(Job j) {
    final token = _tokens[j.id] = CancelToken();
    j.state = JobState.waiting;
    _notify();
    _inflight[j.id] = _run(j, token).whenComplete(() {
      _inflight.remove(j.id);
      _notify();
    });
  }

  Future<void> _run(Job j, CancelToken token) async {
    final need = VenueNeed(name: holdNameFor(j), contractClass: 'container.run.v1');
    // Lease lost mid-job (a renewal failed). DECISION: the job FAILS, visibly, and is not silently re-queued. After a
    // failed renewal the Kit can no longer vouch that Venue still holds the slot, so continuing could run beyond the
    // quota, and re-queueing would hide a Venue outage as "waiting". The person sees "failed: Venue lease lost" and
    // decides with Retry. The work is cancelled so it stops using what it may no longer own.
    String? leaseLost;
    try {
      await venue.withHoldWaiting<void>(
        need,
        (hold) async {
          j.holdName = hold.name;
          j.holdKind = hold.where;
          j.state = JobState.running;
          j.reason = null;
          _running++;
          if (_running > _peak) _peak = _running;
          _notify();
          try {
            await work(j, token);
          } finally {
            _running--;
          }
        },
        leaseSeconds: leaseSeconds,
        renewEvery: renewEvery,
        maxWait: policy == RefusalPolicy.wait ? maxWait : Duration.zero,
        retryEvery: retryEvery,
        cancel: token.whenCancelled,
        onWaiting: (refusal, attempt) {
          j.attempts = attempt;
          j.state = JobState.waiting;
          j.reason = 'Venue said: ${refusal.plainReason}';
          _notify();
        },
        onLeaseLost: (hold, error) {
          leaseLost = 'Venue lease lost: renewing ${hold.name} failed ($error); the job was stopped';
          token.cancel();
          j.reason = leaseLost;
          _notify();
        },
      );
      j.state = leaseLost != null ? JobState.failed : (token.isCancelled ? JobState.cancelled : JobState.done);
      if (j.state == JobState.done) j.progress = 1;
    } on VenueRefused catch (e) {
      j.state = JobState.refused;
      // "still refused after Ns" only when we really did wait; a permanent refusal says just what Venue said.
      j.reason = j.attempts > 0 ? 'still refused after ${maxWait.inSeconds}s: ${e.plainReason}' : e.plainReason;
    } on HoldWaitCancelled {
      j.state = JobState.cancelled;
    } on JobCancelled {
      j.state = leaseLost != null ? JobState.failed : JobState.cancelled;
    } on VenueUnavailable catch (e) {
      j.state = JobState.failed;
      j.reason = 'Venue unavailable: ${e.reason}';
    } catch (e) {
      j.state = JobState.failed;
      j.reason = '$e';
    }
    if (j.state == JobState.failed && leaseLost != null) j.reason = leaseLost;
    _notify();
  }
}

class JobCancelled implements Exception {
  @override
  String toString() => 'JobCancelled';
}
