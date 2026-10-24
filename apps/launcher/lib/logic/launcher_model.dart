import 'package:application_kit/application_kit.dart';

/// running: announced and alive. stale: a roster file is there but the heartbeat lapsed or the process is gone
/// (a crash left it behind). gone: was running and its file was withdrawn (a clean exit). notRunning: known from a
/// manifest and not announced.
enum AppStatus { running, stale, gone, notRunning }

class AppRow {
  AppRow({
    required this.id,
    required this.name,
    required this.version,
    required this.status,
    this.instance,
    this.pid,
    this.startedAt,
    this.heartbeatAt,
    this.lastSeen,
    this.known = false,
    this.isSelf = false,
    this.why,
  });
  final String id, name, version;

  /// Which copy of the app this row is (the part after `@` in the roster file name); null for a not-running app.
  final String? instance;
  final AppStatus status;
  final int? pid;
  final DateTime? startedAt, heartbeatAt;

  /// For gone rows: when it was last seen running.
  final DateTime? lastSeen;

  /// A manifest for it was found in the apps directory.
  final bool known;
  final bool isSelf;

  /// A plain-words reason for stale: "heartbeat 40 s old", "process 1234 does not exist".
  final String? why;

  /// Unique per row: the app id and, for a running or remembered copy, its instance.
  String get key => instance == null ? id : '$id@$instance';

  Duration? uptime(DateTime now) => (status == AppStatus.running && startedAt != null) ? now.difference(startedAt!) : null;
}

/// Merges what the roster directory says with what the manifests say, and remembers what it saw last time so it can
/// tell "exited" from "never ran". Pure: all inputs are arguments.
class LauncherModel {
  LauncherModel({this.forgetGoneAfter = const Duration(seconds: 30), this.selfInstance});
  final Duration forgetGoneAfter;

  /// This launcher's own instance id, so only its own row says "this app" (another copy of the launcher is just another row).
  final String? selfInstance;

  final _lastEntry = <String, RosterEntry>{};
  final _goneAt = <String, DateTime>{};

  /// One row per presence file (so per running copy). [isAlive] is the OS pid check, which `Roster.scan()` does not do.
  List<AppRow> update({
    required List<RosterRecord> records,
    required bool Function(int pid) isAlive,
    required List<AppManifest> known,
    required DateTime now,
  }) {
    final manifests = {for (final m in known) m.id: m};
    final rows = <String, AppRow>{};

    for (final r in records) {
      final e = r.entry;
      if (e == null) continue; // unreadable: the controller reports these by file name
      final alive = r.status == RosterStatus.live && isAlive(e.pid);
      final k = r.file;
      _goneAt.remove(k);
      _lastEntry[k] = e;
      String? why;
      if (r.status == RosterStatus.live && !alive) {
        why = 'process ${e.pid} does not exist';
      } else if (r.status == RosterStatus.stale) {
        why = 'heartbeat ${now.difference(e.heartbeatAt).inSeconds} s old';
      }
      rows[k] = AppRow(
        id: e.id,
        instance: e.instance,
        name: e.name,
        version: e.version,
        status: alive ? AppStatus.running : AppStatus.stale,
        pid: e.pid,
        startedAt: e.startedAt,
        heartbeatAt: e.heartbeatAt,
        known: manifests.containsKey(e.id),
        isSelf: e.instance != null && e.instance == selfInstance,
        why: why,
      );
    }

    // Seen before, file gone now: it exited (a crash leaves the file, so this is a clean exit or a clean-up).
    for (final k in _lastEntry.keys.toList()) {
      if (rows.containsKey(k)) continue;
      final at = _goneAt.putIfAbsent(k, () => now);
      if (now.difference(at) > forgetGoneAfter) {
        _lastEntry.remove(k);
        _goneAt.remove(k);
        continue;
      }
      final e = _lastEntry[k]!;
      rows[k] = AppRow(
        id: e.id,
        instance: e.instance,
        name: e.name,
        version: e.version,
        status: AppStatus.gone,
        lastSeen: e.heartbeatAt,
        known: manifests.containsKey(e.id),
        isSelf: e.instance != null && e.instance == selfInstance,
        why: 'its roster entry was withdrawn ${now.difference(at).inSeconds} s ago',
      );
    }

    // A known app with no row at all (no running, stale or just-exited copy) is simply not running.
    for (final m in known) {
      if (rows.values.any((r) => r.id == m.id)) continue;
      rows[m.id] = AppRow(id: m.id, name: m.name, version: m.version, status: AppStatus.notRunning, known: true);
    }

    final list = rows.values.toList()
      ..sort((a, b) {
        final c = a.status.index.compareTo(b.status.index);
        if (c != 0) return c;
        final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return n != 0 ? n : a.key.compareTo(b.key);
      });
    return list;
  }
}
