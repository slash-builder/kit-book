import 'dart:io';

import 'package:app_context_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher/bootstrap.dart';
import 'package:launcher/ui/launcher_app.dart';

import '../support.dart';

void main() {
  final manifest = File('app.json').readAsStringSync();

  // Scratch + mock. The roster lands in <scratch>/roster, so no real roster is read.
  Future<KitTestContext> open(WidgetTester t, {Map<String, String> env = const {}}) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    return testAppContext(t, manifest: manifest, env: env);
  }

  Future<void> show(KitTestContext kit, {Duration? refreshEvery}) =>
      kit.mount((ctx) => LauncherApp(controller: buildController(ctx, isAlive: (_) => true), refreshEvery: refreshEvery));

  String status(WidgetTester t, String id, [String instance = defaultInstance]) =>
      (t.widget(find.byKey(Key('status-$id@$instance'))) as Text).data!;

  testWidgets('lists running, stale and not-running apps, and updates when an entry disappears', (t) async {
    // The apps directory has to exist before the context opens, so it is made next to where the scratch dir will be.
    final apps = Directory.systemTemp.createTempSync('launcher-apps-').path;
    addTearDown(() => Directory(apps).deleteSync(recursive: true));
    writeManifest(apps, 'stopwatch', manifestJson('com.slashbuilder.demo.stopwatch', 'Stopwatch'));
    writeManifest(apps, 'notepad', manifestJson('com.slashbuilder.demo.notepad', 'Notepad'));
    writeManifest(apps, 'broken', {'id': 'BAD', 'name': 'x', 'version': '1.0.0'});
    final kit = await open(t, env: {'LAUNCHER_APPS_DIR': apps});
    final now = DateTime.now().toUtc();
    final roster = kit.ctx.roster.dir;
    writeRoster(roster, 'com.slashbuilder.demo.stopwatch', name: 'Stopwatch', version: '0.1.0', pid: 111, started: now.subtract(const Duration(minutes: 3, seconds: 5)), heartbeat: now);
    writeRoster(roster, 'com.slashbuilder.demo.crashed', name: 'Crashed', pid: 222, started: now, heartbeat: now.subtract(const Duration(minutes: 2)));

    await show(kit, refreshEvery: const Duration(seconds: 3));
    await t.pump();

    expect(status(t, 'com.slashbuilder.demo.stopwatch'), 'running');
    expect(status(t, 'com.slashbuilder.demo.crashed'), 'stale');
    expect((t.widget(find.byKey(const Key('status-com.slashbuilder.demo.notepad'))) as Text).data, 'not running');
    expect(find.text('111'), findsOneWidget);
    expect(find.text('3m 05s'), findsOneWidget);
    expect(find.textContaining('heartbeat 120 s old'), findsOneWidget);
    expect(find.textContaining('no manifest found'), findsOneWidget, reason: 'the crashed app has no manifest in the apps directory');
    expect(find.textContaining('Skipped broken/app.json: bad-id'), findsOneWidget);
    expect(find.textContaining('fake-node ready=true'), findsOneWidget);
    expect(find.textContaining('Roster: $roster'), findsOneWidget);
    expect(find.text('mock + scratch'), findsOneWidget); // ModeBadge

    // the stopwatch quits: its file is withdrawn; the next refresh shows "gone"
    File('$roster/com.slashbuilder.demo.stopwatch@$defaultInstance.json').deleteSync();
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(status(t, 'com.slashbuilder.demo.stopwatch'), 'gone');

    await kit.quit();
  });

  testWidgets('two copies of one app are two rows with their own instance ids; one quitting leaves the other', (t) async {
    final kit = await open(t);
    final now = DateTime.now().toUtc();
    final roster = kit.ctx.roster.dir;
    writeRoster(roster, 'com.slashbuilder.demo.stopwatch', name: 'Stopwatch', pid: 111, instance: 'aaaaaaaa', started: now, heartbeat: now);
    writeRoster(roster, 'com.slashbuilder.demo.stopwatch', name: 'Stopwatch', pid: 222, instance: 'bbbbbbbb', started: now, heartbeat: now);
    await show(kit, refreshEvery: const Duration(seconds: 3));
    await t.pump();

    expect(find.text('Stopwatch'), findsNWidgets(2));
    expect(status(t, 'com.slashbuilder.demo.stopwatch', 'aaaaaaaa'), 'running');
    expect(status(t, 'com.slashbuilder.demo.stopwatch', 'bbbbbbbb'), 'running');
    expect(find.text('aaaaaaaa'), findsOneWidget);
    expect(find.text('bbbbbbbb'), findsOneWidget);

    File('$roster/com.slashbuilder.demo.stopwatch@aaaaaaaa.json').deleteSync();
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(status(t, 'com.slashbuilder.demo.stopwatch', 'aaaaaaaa'), 'gone');
    expect(status(t, 'com.slashbuilder.demo.stopwatch', 'bbbbbbbb'), 'running');
    await kit.quit();
  });

  testWidgets('no apps directory set: only announced apps, and the banner says how to set it', (t) async {
    final kit = await open(t);
    final now = DateTime.now().toUtc();
    writeRoster(kit.ctx.roster.dir, 'com.slashbuilder.demo.a', name: 'A', started: now, heartbeat: now);
    await show(kit);
    await t.pump();
    expect(status(t, 'com.slashbuilder.demo.a'), 'running');
    expect(find.textContaining('Apps directory: not set'), findsOneWidget);
    await kit.quit();
  });

  testWidgets('the apps directory can come from the settings file instead of the environment', (t) async {
    final apps = Directory.systemTemp.createTempSync('launcher-apps-').path;
    addTearDown(() => Directory(apps).deleteSync(recursive: true));
    writeManifest(apps, 'notepad', manifestJson('com.slashbuilder.demo.notepad', 'Notepad'));
    final kit = await open(t);
    kit.ctx.config.set('appsDir', apps);
    await show(kit);
    await t.pump();
    expect(find.byKey(const Key('status-com.slashbuilder.demo.notepad')), findsOneWidget);
    expect((t.widget(find.byKey(const Key('status-com.slashbuilder.demo.notepad'))) as Text).data, 'not running');
    await kit.quit();
  });

  testWidgets('empty: nothing announced and no apps directory', (t) async {
    final kit = await open(t);
    await show(kit);
    await t.pump();
    expect(find.text('Nothing announced and no apps directory set.'), findsOneWidget);
    await kit.quit();
  });

  testWidgets('a damaged settings file is shown by the notes banner', (t) async {
    final kit = await open(t);
    File('${kit.ctx.dirs.config}/config.json').writeAsStringSync('{nope');
    await kit.reopen(); // the same scratch directory, now with a damaged config.json
    await show(kit);
    await t.pump();
    expect(find.textContaining('Settings: config.json is not valid UTF-8 JSON'), findsOneWidget);
    await kit.quit();
  });
}
