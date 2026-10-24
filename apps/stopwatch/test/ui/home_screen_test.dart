import 'dart:convert';
import 'dart:io';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/bootstrap.dart';
import 'package:stopwatch/kit_gaps/notifier.dart';
import 'package:stopwatch/logic/controller.dart';
import 'package:stopwatch/ui/stopwatch_app.dart';

class RecordingNotifier implements Notifier {
  final sent = <String>[];
  @override
  Future<bool> notify(String title, String body) async {
    sent.add('$title: $body');
    return true;
  }
}

void main() {
  var now = 5000000;
  setUp(() => now = 5000000);

  final manifest = File('app.json').readAsStringSync();

  // pumpKitApp: scratch dir + mock mode + AppContextScope, the same tree AppKit.run mounts.
  Future<KitTestContext> launch(WidgetTester t, RecordingNotifier notifier) =>
      pumpKitApp(t, manifest: manifest, app: (ctx) => StopwatchApp(controller: buildController(ctx, notifier, now: () => now)));

  testWidgets('start, lap, relaunch: the running stopwatch keeps counting', (t) async {
    final kit = await launch(t, RecordingNotifier());

    expect(find.text('00:00.0'), findsOneWidget);
    expect(find.text('mock + scratch'), findsOneWidget); // ModeBadge
    expect(find.text('No laps yet'), findsOneWidget);

    await t.tap(find.byKey(const Key('sw-toggle')));
    await t.pump(); // the Lap button enables once the change reaches the UI
    now += 12300;
    await t.tap(find.byKey(const Key('sw-lap')));
    await t.pump();
    expect(find.text('00:12.3'), findsWidgets);
    expect(find.text('Lap 1'), findsOneWidget);

    // a minute later: quit (close hooks run, saving the state) and relaunch on the same files
    now += 60000;
    await kit.relaunch();
    expect(find.text('01:12.3'), findsWidgets);
    expect(find.text('Lap 1'), findsOneWidget);

    await kit.quit();
    expect(File('${kit.ctx.dirs.state}/state.json').existsSync(), isTrue);
  });

  testWidgets('the footer shows the badge and only warnings and errors, not the "Venue is fake" info note', (t) async {
    final kit = await launch(t, RecordingNotifier());
    expect(find.textContaining('Venue: fake'), findsNothing);
    expect(find.textContaining('Warning'), findsNothing);
    kit.ctx.notes.add(const AppNote(NoteSeverity.warning, 'Settings: damaged'));
    await kit.mount((ctx) => StopwatchApp(controller: buildController(ctx, RecordingNotifier(), now: () => now)));
    expect(find.textContaining('Settings: damaged'), findsOneWidget);
    await kit.quit();
  });

  testWidgets('the timer tab: pick a length, run it, it ends and a notification is sent', (t) async {
    late StopwatchController c;
    final notifier = RecordingNotifier();
    final kit = await pumpKitApp(t, manifest: manifest, app: (ctx) {
      return StopwatchApp(controller: c = buildController(ctx, notifier, now: () => now));
    });
    await t.tap(find.text('Timer'));
    await t.pumpAndSettle();
    expect(find.text('Ready: 01:00'), findsOneWidget);

    await t.enterText(find.byKey(const Key('cd-custom')), '0:05');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.text('Ready: 00:05'), findsOneWidget);

    await t.tap(find.byKey(const Key('cd-toggle')));
    await t.pump();
    expect(find.text('Running'), findsOneWidget);

    now += 6000;
    c.tick(); // the real app's end timer calls this
    await t.pump();
    expect(find.textContaining('Done at'), findsOneWidget);
    expect(notifier.sent, ['Timer finished: 00:05 countdown is done']);

    await kit.quit();
  });

  testWidgets('a bad custom length shows an error and does not change the timer', (t) async {
    final kit = await launch(t, RecordingNotifier());
    await t.tap(find.text('Timer'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('cd-custom')), 'soon');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('Use seconds'), findsOneWidget);
    expect(find.text('Ready: 01:00'), findsOneWidget);
    await kit.quit();
  });

  testWidgets('the notify setting is read from the app config', (t) async {
    final kit = await testAppContext(t, manifest: manifest);
    kit.ctx.config.set('notify', false);
    final notifier = RecordingNotifier();
    final c = buildController(kit.ctx, notifier, now: () => now);
    c.resetCountdown(durationMs: 1000);
    c.toggleCountdown();
    now += 2000;
    c.tick();
    expect(notifier.sent, isEmpty);
    // Round 2: the peers hub writes a generated `device` id into the same file the first time it is built, so the file is
    // no longer exactly {'notify': false}; the setting itself must still be there.
    expect(jsonDecode(File('${kit.ctx.dirs.config}/config.json').readAsStringSync()), containsPair('notify', false));
    await kit.close(); // runs the onClose hook, which disposes the controller
  });
}
