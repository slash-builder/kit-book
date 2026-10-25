import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher/kit_gaps/manifest_scan.dart';
import 'package:launcher/kit_gaps/pid_alive.dart';
import 'package:launcher/logic/launcher_controller.dart';
import 'package:launcher/logic/launcher_model.dart';

import '../support.dart';

void main() {
  late Directory tmp;
  late String roster;
  late String apps;
  final t0 = DateTime.utc(2026, 10, 21, 12, 0, 0);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('launcher-test-');
    roster = '${tmp.path}/roster';
    apps = '${tmp.path}/apps';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // Every pid is "alive" unless a test says otherwise, so only the heartbeat decides.
  List<RosterRecord> scan(DateTime now) => Roster(roster).scan(now: now);
  LauncherController controller({bool Function(int)? alive, DateTime Function()? now, String? self}) => LauncherController(
      roster: Roster(roster), appsDir: apps, nodes: () async => const [], isAlive: alive ?? (_) => true, now: now, selfInstance: self);

  group('the controller over Roster.scan()', () {
    test('keeps the stale entries that Roster.running() hides, and flags a dead pid', () async {
      writeRoster(roster, 'com.slashbuilder.demo.fresh', started: t0, heartbeat: t0);
      writeRoster(roster, 'com.slashbuilder.demo.old', started: t0, heartbeat: t0.subtract(const Duration(seconds: 40)));
      writeRoster(roster, 'com.slashbuilder.demo.dead', pid: 99, started: t0, heartbeat: t0);
      final snap = await controller(alive: (p) => p != 99, now: () => t0).refresh();
      expect(snap.rows.map((r) => (r.id, r.status)),
          [('com.slashbuilder.demo.fresh', AppStatus.running), ('com.slashbuilder.demo.dead', AppStatus.stale), ('com.slashbuilder.demo.old', AppStatus.stale)]);
      expect(snap.rows.firstWhere((r) => r.id == 'com.slashbuilder.demo.dead').why, 'process 99 does not exist');
      // the Kit's own view of the same directory
      expect(Roster(roster).running(now: t0).map((e) => e.id), ['com.slashbuilder.demo.dead', 'com.slashbuilder.demo.fresh'],
          reason: 'running() drops the stale one and, with no pid check, still lists the crashed one with a fresh heartbeat');
    });

    test('a damaged file is reported by name, not swallowed', () async {
      Directory(roster).createSync(recursive: true);
      File('$roster/junk.json').writeAsStringSync('{nope');
      File('$roster/shape.json').writeAsStringSync('{"id": 5}');
      final snap = await controller(now: () => t0).refresh();
      expect(snap.rows, isEmpty);
      expect(snap.unreadableRosterFiles, unorderedEquals(['junk.json', 'shape.json']));
    });

    test('a missing directory is an empty roster', () async {
      final c = LauncherController(roster: Roster('${tmp.path}/nope'), appsDir: null, nodes: () async => const []);
      expect((await c.refresh()).rows, isEmpty);
    });

    test('the real pid check: this process is alive, a huge pid is not', () {
      expect(pidAliveViaKill(pid), isTrue);
      expect(pidAliveViaKill(2147483000), isFalse);
    });
  });

  group('scanManifests', () {
    test('lists <dir>/*/app.json and says why one was skipped', () {
      writeManifest(apps, 'stopwatch', manifestJson('com.slashbuilder.demo.stopwatch', 'Stopwatch'));
      writeManifest(apps, 'broken', {'id': 'NOPE', 'name': 'x', 'version': '1.0.0'});
      Directory('$apps/empty').createSync(recursive: true);
      File('$apps/readme.txt').createSync();
      final scan = scanManifests(apps);
      expect(scan.manifests.map((m) => m.id), ['com.slashbuilder.demo.stopwatch']);
      expect(scan.problems, {'broken/app.json': 'bad-id'});
    });

    test('unset or missing directory', () {
      expect(scanManifests(null).manifests, isEmpty);
      expect(scanManifests('${tmp.path}/nope').problems.values.single, 'directory does not exist');
    });
  });

  group('LauncherModel', () {
    AppRow row(List<AppRow> rows, String id) => rows.firstWhere((r) => r.id == id);
    List<AppRow> update(LauncherModel m, DateTime now, {List<AppManifest> known = const [], bool Function(int)? alive}) =>
        m.update(records: scan(now), isAlive: alive ?? (_) => true, known: known, now: now);

    test('running, stale (crash), not running, and a running app with no manifest', () {
      writeRoster(roster, 'com.slashbuilder.demo.a', name: 'A', started: t0.subtract(const Duration(minutes: 5)), heartbeat: t0);
      writeRoster(roster, 'com.slashbuilder.demo.b', name: 'B', pid: 7, started: t0, heartbeat: t0.subtract(const Duration(seconds: 30)));
      writeRoster(roster, 'com.slashbuilder.demo.stranger', name: 'Stranger', started: t0, heartbeat: t0);
      final known = [AppManifest.fromJson(manifestJson('com.slashbuilder.demo.a', 'A')), AppManifest.fromJson(manifestJson('com.slashbuilder.demo.b', 'B')), AppManifest.fromJson(manifestJson('com.slashbuilder.demo.c', 'C'))];
      final rows = update(LauncherModel(), t0, known: known);
      expect(row(rows, 'com.slashbuilder.demo.a').status, AppStatus.running);
      expect(row(rows, 'com.slashbuilder.demo.a').uptime(t0), const Duration(minutes: 5));
      expect(row(rows, 'com.slashbuilder.demo.b').status, AppStatus.stale);
      expect(row(rows, 'com.slashbuilder.demo.b').why, 'heartbeat 30 s old');
      expect(row(rows, 'com.slashbuilder.demo.c').status, AppStatus.notRunning);
      expect(row(rows, 'com.slashbuilder.demo.stranger').known, isFalse);
      // order: running, stale, gone, not running
      expect(rows.map((r) => r.status.index).toList(), [0, 0, 1, 3]);
    });

    test('a dead pid is stale at once, before the heartbeat window passes', () {
      writeRoster(roster, 'com.slashbuilder.demo.a', pid: 99, started: t0, heartbeat: t0);
      final rows = update(LauncherModel(), t0, alive: (_) => false);
      expect(rows.single.status, AppStatus.stale);
      expect(rows.single.why, 'process 99 does not exist');
    });

    test('an entry that disappears becomes gone, then is forgotten', () {
      final m = LauncherModel(forgetGoneAfter: const Duration(seconds: 30));
      writeRoster(roster, 'com.slashbuilder.demo.a', name: 'A', started: t0, heartbeat: t0);
      expect(update(m, t0).single.status, AppStatus.running);
      File('$roster/com.slashbuilder.demo.a@$defaultInstance.json').deleteSync();
      final t1 = t0.add(const Duration(seconds: 5));
      var rows = update(m, t1);
      expect(rows.single.status, AppStatus.gone);
      expect(rows.single.name, 'A');
      final t2 = t0.add(const Duration(seconds: 40));
      rows = update(m, t2);
      expect(rows, isEmpty);
    });

    test('a gone app that is known falls back to not running; one that comes back is running again', () {
      final m = LauncherModel(forgetGoneAfter: const Duration(seconds: 10));
      final known = [AppManifest.fromJson(manifestJson('com.slashbuilder.demo.a', 'A'))];
      writeRoster(roster, 'com.slashbuilder.demo.a', started: t0, heartbeat: t0);
      update(m, t0, known: known);
      File('$roster/com.slashbuilder.demo.a@$defaultInstance.json').deleteSync();
      expect(update(m, t0, known: known).single.status, AppStatus.gone);
      final later = t0.add(const Duration(seconds: 20));
      expect(update(m, later, known: known).single.status, AppStatus.notRunning);
      writeRoster(roster, 'com.slashbuilder.demo.a', started: later, heartbeat: later);
      expect(update(m, later, known: known).single.status, AppStatus.running);
    });

    test('a crash leaves a stale row, and the model cannot tell it from a hang', () {
      // The heartbeat timer runs on the app's own isolate: a frozen UI whose isolate still runs keeps beating, and a
      // hung process with a dead event loop stops beating. Either way the file says "stale", never "hung" or "crashed".
      writeRoster(roster, 'com.slashbuilder.demo.a', started: t0, heartbeat: t0);
      final later = t0.add(const Duration(minutes: 10));
      expect(update(LauncherModel(), later).single.status, AppStatus.stale);
    });

    test('two copies of one app are two rows, told apart by instance; only the launcher\'s own instance is "this app"', () {
      writeRoster(roster, 'com.slashbuilder.demo.twin', name: 'Twin', pid: 1, instance: 'aaaaaaaa', started: t0, heartbeat: t0);
      writeRoster(roster, 'com.slashbuilder.demo.twin', name: 'Twin', pid: 2, instance: 'bbbbbbbb', started: t0, heartbeat: t0);
      final rows = update(LauncherModel(selfInstance: 'bbbbbbbb'), t0);
      expect(rows.map((r) => (r.key, r.pid, r.isSelf)), [('com.slashbuilder.demo.twin@aaaaaaaa', 1, false), ('com.slashbuilder.demo.twin@bbbbbbbb', 2, true)]);
    });

    test('one of two copies quits: its row goes gone, the other stays running', () {
      final m = LauncherModel();
      writeRoster(roster, 'com.slashbuilder.demo.twin', pid: 1, instance: 'aaaaaaaa', started: t0, heartbeat: t0);
      writeRoster(roster, 'com.slashbuilder.demo.twin', pid: 2, instance: 'bbbbbbbb', started: t0, heartbeat: t0);
      update(m, t0);
      File('$roster/com.slashbuilder.demo.twin@aaaaaaaa.json').deleteSync();
      final rows = update(m, t0.add(const Duration(seconds: 5)));
      expect(rows.map((r) => (r.instance, r.status)), [('bbbbbbbb', AppStatus.running), ('aaaaaaaa', AppStatus.gone)]);
    });

    test('a known app is "not running" only when none of its copies has a row', () {
      writeRoster(roster, 'com.slashbuilder.demo.twin', name: 'Twin', instance: 'aaaaaaaa', started: t0, heartbeat: t0);
      final known = [AppManifest.fromJson(manifestJson('com.slashbuilder.demo.twin', 'Twin'))];
      expect(update(LauncherModel(), t0, known: known).map((r) => r.status), [AppStatus.running]);
    });
  });

  group('with the real AppContext', () {
    test('an app announced by the Kit shows as running, then gone after it closes', () async {
      final env = {'APP_CONTEXT_SCRATCH': tmp.path, 'APP_CONTEXT_MODE': 'mock', 'HOME': tmp.path};
      final self = AppManifest.fromJson(manifestJson('com.slashbuilder.demo.other', 'Other'));
      final other = await AppContext.open(self, env: env, heartbeat: const Duration(milliseconds: 50));
      final c = LauncherController(roster: other.roster, appsDir: null, nodes: other.venue.nodes);
      var snap = await c.refresh();
      expect(snap.rows.single.status, AppStatus.running);
      expect(snap.rows.single.pid, pid);
      expect(snap.rows.single.instance, other.instance);
      expect(snap.venueNodes.single.name, 'fake-node');
      await other.close();
      snap = await c.refresh();
      expect(snap.rows.single.status, AppStatus.gone);
    });

    test('two instances of one app are two rows, and the first to quit no longer removes the other', () async {
      final env = {'APP_CONTEXT_SCRATCH': tmp.path, 'APP_CONTEXT_MODE': 'mock', 'HOME': tmp.path};
      final m = AppManifest.fromJson(manifestJson('com.slashbuilder.demo.twin', 'Twin'));
      final a = await AppContext.open(m, env: env, heartbeat: const Duration(seconds: 30));
      final b = await AppContext.open(m, env: env, heartbeat: const Duration(seconds: 30));
      expect(a.instance, isNot(b.instance));
      final c = LauncherController(roster: a.roster, appsDir: null, nodes: a.venue.nodes, selfInstance: a.instance);
      var snap = await c.refresh();
      expect(snap.rows.map((r) => (r.instance, r.status, r.isSelf)),
          unorderedEquals([(a.instance, AppStatus.running, true), (b.instance, AppStatus.running, false)]));
      await a.close();
      snap = await c.refresh();
      expect(snap.rows.map((r) => (r.instance, r.status)),
          unorderedEquals([(b.instance, AppStatus.running), (a.instance, AppStatus.gone)]));
      expect(Directory(b.roster.dir).listSync().whereType<File>().length, 1, reason: 'b\'s file is still there');
      await b.close();
    });

    test('the controller reports a Venue that cannot list nodes', () async {
      final c = LauncherController(roster: Roster(roster), appsDir: null, nodes: () async => throw VenueUnavailable('nodes: HTTP 401'));
      final snap = await c.refresh();
      expect(snap.venueError, contains('HTTP 401'));
    });
  });

  test('formatUptime', () {
    expect(formatUptime(const Duration(seconds: 12)), '12s');
    expect(formatUptime(const Duration(seconds: 185)), '3m 05s');
    expect(formatUptime(const Duration(seconds: 3725)), '1h 02m');
  });
}
