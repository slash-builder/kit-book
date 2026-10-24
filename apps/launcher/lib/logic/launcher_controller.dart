import 'package:application_kit/application_kit.dart';

import '../kit_gaps/manifest_scan.dart';
import '../kit_gaps/pid_alive.dart';
import 'launcher_model.dart';

class LauncherSnapshot {
  const LauncherSnapshot({
    required this.rows,
    required this.takenAt,
    required this.unreadableRosterFiles,
    required this.manifestProblems,
    required this.venueNodes,
    required this.venueError,
  });
  final List<AppRow> rows;
  final DateTime takenAt;
  final List<String> unreadableRosterFiles;
  final Map<String, String> manifestProblems;

  /// `name` and `ready` for each Venue node, for comparing with the roster's idea of "alive".
  final List<({String name, String ready})> venueNodes;
  final String? venueError;
}

/// One refresh = scan the roster directory, scan the manifests directory, ask Venue for its nodes. No Flutter.
class LauncherController {
  LauncherController({
    required this.roster,
    required this.appsDir,
    required this.nodes,
    this.selfInstance,
    DateTime Function()? now,
    this.isAlive = pidAliveViaKill,
    this.staleAfter = const Duration(seconds: 15),
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        model = LauncherModel(selfInstance: selfInstance);

  final Roster roster;
  final String? appsDir;
  final Future<List<Map<String, Object?>>> Function() nodes;
  final String? selfInstance;
  final bool Function(int pid) isAlive;
  final Duration staleAfter;
  final DateTime Function() _now;
  final LauncherModel model;

  Future<LauncherSnapshot> refresh() async {
    final now = _now();
    final records = roster.scan(now: now, staleAfter: staleAfter);
    final manifests = scanManifests(appsDir);
    final rows = model.update(records: records, isAlive: isAlive, known: manifests.manifests, now: now);
    var venueNodes = <({String name, String ready})>[];
    String? venueError;
    try {
      venueNodes = [
        for (final n in await nodes()) (name: '${n['name']}', ready: '${n['ready']}'),
      ];
    } catch (e) {
      venueError = '$e';
    }
    return LauncherSnapshot(
      rows: rows,
      takenAt: now,
      unreadableRosterFiles: [for (final r in records) if (r.status == RosterStatus.unreadable) r.file],
      manifestProblems: manifests.problems,
      venueNodes: venueNodes,
      venueError: venueError,
    );
  }
}

/// `1h 02m`, `3m 05s`, `12s`.
String formatUptime(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s >= 3600) return '${s ~/ 3600}h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')}m';
  if (s >= 60) return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${s}s';
}
