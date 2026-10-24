import 'dart:io';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/bootstrap.dart';
import 'package:stopwatch/kit_gaps/notifier.dart';
import 'package:stopwatch/logic/controller.dart';
import 'package:stopwatch/ui/stopwatch_app.dart';

class _Notifier implements Notifier {
  final sent = <String>[];
  @override
  Future<bool> notify(String title, String body) async {
    sent.add('$title: $body');
    return true;
  }
}

void main() {
  final manifestText = File('app.json').readAsStringSync();
  var now = 9000000;
  setUp(() => now = 9000000);

  // The widget tree runs under fake async; the OTHER copy (a plain context) runs in real async via tester.runAsync, and we
  // alternate between the two until the UI shows what we expect.
  Future<void> settleUntil(WidgetTester t, bool Function() cond) async {
    for (var i = 0; i < 300 && !cond(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(cond(), isTrue, reason: 'the UI did not reach the expected state');
  }

  testWidgets('the footer shows this copy, how many peers are connected, and who they are', (t) async {
    final net = FakePeerNetwork();
    late StopwatchController c;
    final kit = await pumpKitApp(t, manifest: manifestText, env: {'APPKIT_DEVICE': 'laptop'}, app: (ctx) {
      return StopwatchApp(controller: c = buildController(ctx, _Notifier(), now: () => now, network: net));
    });
    expect(find.byKey(const ValueKey('peers-count')), findsOneWidget);
    expect(find.text('Peers: 0'), findsOneWidget);
    expect(find.textContaining('This copy: laptop #'), findsOneWidget);

    final other = await t.runAsync(() => AppContext.open(AppManifest.parse(manifestText),
        env: {'APPKIT_SCRATCH': '${kit.scratch.path}/other', 'APPKIT_MODE': 'mock', 'APPKIT_DEVICE': 'desktop', 'HOME': kit.scratch.path},
        announce: false));
    final oc = buildController(other!, _Notifier(), now: () => now, network: net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty);
    expect(find.textContaining('desktop #'), findsOneWidget); // the chip

    // the other copy leaves: the indicator goes back to zero
    await t.runAsync(other.close);
    await settleUntil(t, () => find.text('Peers: 0').evaluate().isNotEmpty);
    expect(oc.peers, isNotNull);
    expect(c.peers!.handle.hub!.readyPeers, isEmpty);
    await kit.quit();
  });

  testWidgets('a finish on the other copy shows "Timer finished on <device>" here and notifies', (t) async {
    final net = FakePeerNetwork();
    final mine = _Notifier(), theirs = _Notifier();
    late StopwatchController c;
    final kit = await pumpKitApp(t, manifest: manifestText, env: {'APPKIT_DEVICE': 'laptop'}, app: (ctx) {
      return StopwatchApp(controller: c = buildController(ctx, mine, now: () => now, network: net));
    });
    final other = await t.runAsync(() => AppContext.open(AppManifest.parse(manifestText),
        env: {'APPKIT_SCRATCH': '${kit.scratch.path}/other', 'APPKIT_MODE': 'mock', 'APPKIT_DEVICE': 'desktop', 'HOME': kit.scratch.path},
        announce: false));
    final oc = buildController(other!, theirs, now: () => now, network: net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty);

    oc.resetCountdown(durationMs: 5000);
    oc.toggleCountdown();
    await settleUntil(t, () => c.state.countdown.clock.running); // started over there, running here
    now += 6000;
    oc.tick();
    await settleUntil(t, () => find.textContaining('Timer finished on desktop #').evaluate().isNotEmpty);
    expect(mine.sent.single, startsWith('Timer finished: 00:05 countdown finished on desktop #'));
    expect(theirs.sent, ['Timer finished: 00:05 countdown is done']);
    await t.runAsync(other.close);
    await kit.quit();
  });

  testWidgets('when peers cannot start the footer says so and the timer still works', (t) async {
    final dir = Directory.systemTemp.createTempSync('sw-peers-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final blocker = File('${dir.path}/file')..writeAsStringSync('x');
    // real mode so the loopback provider is used; the scratch keeps every other directory inside the temp dir
    late StopwatchController c;
    final kit = await pumpKitApp(t, manifest: manifestText, env: {'APPKIT_MODE': 'real', 'APPKIT_PEERS_DIR': blocker.path}, app: (ctx) {
      return StopwatchApp(controller: c = buildController(ctx, _Notifier(), now: () => now));
    });
    await settleUntil(t, () => find.byKey(const ValueKey('peers-offline')).evaluate().isNotEmpty);
    expect(find.textContaining('Peers: off (peers unavailable'), findsOneWidget);
    c.toggleCountdown();
    expect(c.state.countdown.clock.running, isTrue);
    await kit.quit();
  });
}
