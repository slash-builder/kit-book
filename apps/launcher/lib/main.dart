import 'package:application_kit_flutter/application_kit_flutter.dart';

import 'bootstrap.dart';
import 'ui/launcher_app.dart';

Future<void> main() => AppKit.run(
      manifestAsset: 'app.json',
      app: (ctx) => LauncherApp(controller: buildController(ctx)),
    );
