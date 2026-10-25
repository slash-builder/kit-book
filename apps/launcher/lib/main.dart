import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';

import 'bootstrap.dart';
import 'ui/launcher_app.dart';

Future<void> main() => AppContextKit.run(
      manifestAsset: 'app.json',
      app: (ctx) => LauncherApp(controller: buildController(ctx)),
    );
