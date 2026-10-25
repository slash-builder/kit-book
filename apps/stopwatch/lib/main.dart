import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';

import 'bootstrap.dart';
import 'kit_gaps/notifier.dart';
import 'ui/stopwatch_app.dart';

Future<void> main() => AppContextKit.run(
      manifestAsset: 'app.json',
      app: (ctx) => StopwatchApp(controller: buildController(ctx, SystemNotifier())),
    );
