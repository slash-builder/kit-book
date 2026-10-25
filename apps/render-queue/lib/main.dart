import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';

import 'bootstrap.dart';
import 'ui/render_queue_app.dart';

// fakeCapacity must be known before the context opens, so it is a constant here and no longer a config.json setting.
Future<void> main() => AppContextKit.run(
      manifestAsset: 'app.json',
      fakeCapacity: 2,
      app: (ctx) => RenderQueueApp(queue: buildQueue(ctx)),
    );
