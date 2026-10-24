import 'package:application_kit/application_kit.dart';

import 'logic/fake_render.dart';
import 'logic/render_queue.dart';

/// Builds the queue from the context: the Venue session, the settings in the app's config, and the close hook that
/// cancels running jobs and waits for their holds to be released before Venue closes.
/// Settings (config.json): policy "wait" | "failFast", maxWaitSeconds, retrySeconds, leaseSeconds.
RenderQueue buildQueue(AppContext ctx, {RenderWork? work}) {
  final cfg = ctx.config;
  final q = RenderQueue(
    venue: ctx.venue,
    work: work ?? fakeRender,
    policy: cfg.get<String>('policy', 'wait') == 'failFast' ? RefusalPolicy.failFast : RefusalPolicy.wait,
    maxWait: Duration(seconds: cfg.get<int>('maxWaitSeconds', 30)),
    retryEvery: Duration(seconds: cfg.get<int>('retrySeconds', 1)),
    leaseSeconds: cfg.get<int>('leaseSeconds', 30),
    // Holds found at startup may belong to another running copy of this app (same Venue consumer): ask the roster.
    anotherCopyRunning: () =>
        ctx.roster.scan().any((r) => r.id == ctx.manifest.id && r.instance != ctx.instance && r.status == RosterStatus.live),
  );
  ctx.onClose(q.shutdown);
  return q;
}
