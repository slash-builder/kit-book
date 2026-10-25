// ignore_for_file: avoid_print
// Prints the rows the launcher would show for a roster directory (the display was off, so the window could not be read).
//   dart run tool/rows_probe.dart <roster dir>
import 'package:app_context_kit/app_context_kit.dart';
import 'package:launcher/kit_gaps/pid_alive.dart';
import 'package:launcher/logic/launcher_controller.dart';

Future<void> main(List<String> args) async {
  final c = LauncherController(roster: Roster(args.first), appsDir: null, nodes: () async => const [], isAlive: pidAliveViaKill);
  final snap = await c.refresh();
  for (final r in snap.rows) {
    print('${r.status.name.padRight(8)} ${r.name.padRight(10)} ${r.id} copy=${r.instance} pid=${r.pid} ${r.why ?? ''}');
  }
  if (snap.rows.isEmpty) print('(no rows)');
  for (final f in snap.unreadableRosterFiles) {
    print('unreadable: $f');
  }
}
