import 'package:application_kit/application_kit.dart';

import 'kit_gaps/pid_alive.dart';
import 'logic/launcher_controller.dart';

/// Builds the controller from the context. The apps directory comes from LAUNCHER_APPS_DIR (read from `ctx.env`, the
/// same environment the Kit resolved from) or, failing that, the `appsDir` setting in config.json.
LauncherController buildController(AppContext ctx, {bool Function(int pid)? isAlive}) {
  final fromEnv = ctx.env['LAUNCHER_APPS_DIR'];
  final appsDir = (fromEnv != null && fromEnv.isNotEmpty) ? fromEnv : ctx.config.get<String?>('appsDir', null);
  return LauncherController(
    roster: ctx.roster,
    appsDir: appsDir,
    nodes: ctx.venue.nodes,
    selfInstance: ctx.instance,
    isAlive: isAlive ?? pidAliveViaKill,
  );
}
