import 'package:application_kit_flutter/application_kit_flutter.dart';

import 'bootstrap.dart';
import 'kit_gaps/notifier.dart';
import 'ui/stopwatch_app.dart';

Future<void> main() => AppKit.run(
      manifestAsset: 'app.json',
      app: (ctx) => StopwatchApp(controller: buildController(ctx, SystemNotifier())),
    );
