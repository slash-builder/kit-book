// Two AppContexts in one test, one FakePeerNetwork between them. Real async (plain `test`), real timers, mock mode: the same
// shape a Product would use to test its hook with no network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:application_kit/application_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stopwatch/bootstrap.dart';
import 'package:stopwatch/coordination/shared_timer.dart';
import 'package:stopwatch/kit_gaps/notifier.dart';
import 'package:stopwatch/logic/controller.dart';
import 'package:stopwatch/logic/models.dart';

class RecordingNotifier implements Notifier {
  final sent = <String>[];
  @override
  Future<bool> notify(String title, String body) async {
    sent.add('$title: $body');
    return true;
  }
}

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for ${what ?? 'a condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class Copy {
  Copy(this.ctx, this.controller, this.notifier);
  final AppContext ctx;
  final StopwatchController controller;
  final RecordingNotifier notifier;
  PeerHub get hub => controller.peers!.handle.hub!;
  SharedTimerHook get hook => controller.peers!.hook;
  CountdownModel get cd => controller.state.countdown;
  Future<void> quit() => ctx.close();
}

void main() {
  final manifest = AppManifest.parse(File('app.json').readAsStringSync());
  late Directory tmp;
  late FakePeerNetwork net;
  var now = 5000000;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stopwatch-peers-');
    net = FakePeerNetwork();
    now = 5000000;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Copy> open(String device, {AppManifest? m, String scratchName = '', Map<String, String> env = const {}, Duration grace = const Duration(seconds: 2)}) async {
    final dir = Directory('${tmp.path}/${scratchName.isEmpty ? device : scratchName}')..createSync(recursive: true);
    final ctx = await AppContext.open(m ?? manifest,
        env: {'APPKIT_SCRATCH': dir.path, 'APPKIT_MODE': 'mock', 'APPKIT_DEVICE': device, 'HOME': dir.path, ...env}, announce: false);
    final notifier = RecordingNotifier();
    final c = buildController(ctx, notifier, now: () => now, network: net, takeoverGrace: grace);
    await c.peers!.handle.started;
    return Copy(ctx, c, notifier);
  }

  Future<(Copy, Copy)> pair({Duration grace = const Duration(seconds: 2)}) async {
    final a = await open('laptop', grace: grace), b = await open('desktop', grace: grace);
    await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty, what: 'the copies to find each other');
    return (a, b);
  }

  test('copies of the app find each other, and each sees the other as a peer', () async {
    final (a, b) = await pair();
    expect(a.hub.readyPeers.single.id.device, 'desktop');
    expect(b.hub.readyPeers.single.id.device, 'laptop');
    await a.quit();
    await b.quit();
  });

  test('start on one copy runs on the other; either copy can pause and reset it for both', () async {
    final (a, b) = await pair();
    a.controller.resetCountdown(durationMs: 10000);
    a.controller.toggleCountdown();
    await until(() => b.cd.clock.running, what: 'B to run');
    expect(b.cd.durationMs, 10000);

    now += 3000;
    b.controller.toggleCountdown(); // pause from the OTHER copy
    await until(() => !a.cd.clock.running, what: 'A to pause');
    expect(a.cd.remainingMs(now), 7000);
    expect(b.cd.remainingMs(now), 7000);

    a.controller.resetCountdown();
    await until(() => b.cd.phase() == CountdownPhase.idle, what: 'B to reset');
    expect(b.cd.remainingMs(now), 10000);
    await a.quit();
    await b.quit();
  });

  test('finish: the copy that started it announces, the other says where it finished (once each)', () async {
    final (a, b) = await pair();
    a.controller.resetCountdown(durationMs: 5000);
    a.controller.toggleCountdown();
    await until(() => b.cd.clock.running);
    now += 6000;
    b.controller.tick(); // the other copy's end timer fires FIRST: it must not announce on its own
    a.controller.tick();
    await until(() => b.notifier.sent.isNotEmpty, what: 'B to be told');
    expect(a.notifier.sent, ['Timer finished: 00:05 countdown is done']);
    expect(b.notifier.sent.single, startsWith('Timer finished: 00:05 countdown finished on laptop #'));
    expect(b.controller.peers!.notice, startsWith('Timer finished on laptop #'));
    expect(b.cd.phase(), CountdownPhase.done);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(a.notifier.sent.length, 1);
    expect(b.notifier.sent.length, 1);
    await a.quit();
    await b.quit();
  });

  test('a copy that joins later learns the running countdown from hello', () async {
    final a = await open('laptop');
    a.controller.resetCountdown(durationMs: 60000);
    a.controller.toggleCountdown();
    now += 10000;
    final b = await open('desktop');
    await until(() => b.cd.clock.running, what: 'B to learn the state');
    expect(b.cd.durationMs, 60000);
    expect(b.cd.remainingMs(now), 50000);
    expect(b.hook.stamp, a.hook.stamp);
    await a.quit();
    await b.quit();
  });

  test('the stamp survives a restart, so a returning copy does not lose to an older state', () async {
    final a = await open('laptop');
    a.controller.resetCountdown(durationMs: 20000);
    a.controller.toggleCountdown();
    final rev = a.hook.stamp.rev;
    expect(rev, 2);
    await a.quit();
    final again = await open('laptop');
    expect(again.hook.stamp.rev, rev);
    await again.quit();
  });

  test('a peer lost and back: changes made while apart are picked up on return (and the newer side wins)', () async {
    final (a, b) = await pair();
    final bId = b.hub.id, aId = a.hub.id;
    net.partition(aId, bId);
    await until(() => a.hub.readyPeers.isEmpty && b.hub.readyPeers.isEmpty, what: 'both to notice the cut');
    a.controller.resetCountdown(durationMs: 30000);
    a.controller.toggleCountdown(); // rev 2 on A while B is away
    b.controller.resetCountdown(durationMs: 99000); // rev 1 on B
    net.heal(aId, bId);
    await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty, what: 'them to reconnect');
    await until(() => b.cd.durationMs == 30000, what: 'B to adopt the newer state');
    expect(a.cd.durationMs, 30000);
    expect(b.cd.clock.running, isTrue);
    await a.quit();
    await b.quit();
  });

  test('the announcer quits before the end: the surviving copy announces after the grace period', () async {
    final (a, b) = await pair(grace: const Duration(milliseconds: 100));
    a.controller.resetCountdown(durationMs: 5000);
    a.controller.toggleCountdown();
    await until(() => b.cd.clock.running);
    await a.quit();
    await until(() => b.hub.readyPeers.isEmpty, what: 'B to see A leave');
    now += 6000;
    b.controller.tick();
    expect(b.notifier.sent, ['Timer finished: 00:05 countdown is done']);
    await b.quit();
  });

  test('the announcer is alive but silent: the other copy waits, then announces', () async {
    final (a, b) = await pair(grace: const Duration(milliseconds: 100));
    a.controller.resetCountdown(durationMs: 5000);
    a.controller.toggleCountdown();
    await until(() => b.cd.clock.running);
    now += 6000;
    b.controller.tick(); // A never ticks (hung)
    expect(b.notifier.sent, isEmpty);
    await until(() => b.notifier.sent.isNotEmpty, what: 'the takeover');
    expect(b.notifier.sent, ['Timer finished: 00:05 countdown is done']);
    await a.quit();
    await b.quit();
  });

  group('a hostile or broken peer', () {
    late PeerHub evil;
    late Copy a;

    Future<void> connect() async {
      a = await open('laptop');
      evil = PeerHub(
          account: 'local', app: manifest.id, device: 'evil', instance: 'e1', provider: net.provider(), hook: _Silent('timer'));
      await evil.start();
      await until(() => evil.readyPeers.isNotEmpty && a.hub.readyPeers.isNotEmpty);
    }

    Future<void> send(String kind, Object? json, {int schema = 1}) =>
        evil.send(evil.readyPeers.single, json is Uint8List ? json : Uint8List.fromList(utf8.encode(jsonEncode(json))), kind: kind, schema: schema);

    final good = {
      'stamp': {'rev': 50, 'w': 'evil@e1'},
      'timer': {'d': 1000, 'e': 0, 'run': false, 'endedAgo': null},
    };

    test('malformed or out-of-range messages change nothing and are counted', () async {
      await connect();
      final before = a.cd;
      await send('timer.state', Uint8List.fromList([0xff, 0xfe, 0x00])); // not UTF-8
      await send('timer.state', 'a string');
      await send('timer.state', {'stamp': {'rev': -1, 'w': 'x'}, 'timer': good['timer']});
      await send('timer.state', {'stamp': good['stamp'], 'timer': {'d': 1, 'e': 5, 'run': true, 'endedAgo': null}}); // e > d
      await send('timer.state', {'stamp': good['stamp'], 'timer': {'d': 9999999999, 'e': 0, 'run': false}}); // 99 h cap
      await send('timer.state', {'stamp': good['stamp'], 'timer': {'d': 1000, 'e': 0, 'run': 'yes'}});
      await send('timer.finished', good); // a finish without a label
      await send('timer.state', good, schema: 2); // a newer app version: not readable by this one
      await send('nonsense', good);
      await until(() => a.hook.ignored >= 9, what: 'the hook to see all 9');
      expect(a.cd, same(before));
      expect(a.hook.stamp.rev, 0);
      expect(a.notifier.sent, isEmpty);
      expect(a.hub.stats.hookErrors, 0);
      await a.quit();
      await evil.close();
    });

    test('a well-formed message from a peer in scope IS obeyed: scope is trust, the Kit cannot tell good from hostile', () async {
      await connect();
      await send('timer.state', good);
      await until(() => a.hook.stamp.rev == 50, what: 'the (valid) state to be adopted');
      expect(a.cd.durationMs, 1000);
      await a.quit();
      await evil.close();
    });

    test('the Kit refuses to let an app send a reserved kind', () async {
      await connect();
      expect(() => evil.send(evil.readyPeers.single, Uint8List(0), kind: 'kit.reply'), throwsArgumentError);
      await a.quit();
      await evil.close();
    });
  });

  group('scope isolation', () {
    test('another app on the same network never receives the timer, and never appears as a peer', () async {
      final other = AppManifest.parse(File('app.json').readAsStringSync().replaceAll('dev.demo.stopwatch', 'dev.demo.notepad'));
      final a = await open('laptop');
      final o = await open('laptop-notes', m: other);
      final b = await open('desktop');
      await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty);
      a.controller.resetCountdown(durationMs: 7000);
      a.controller.toggleCountdown();
      await until(() => b.cd.clock.running);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(o.hub.peers, isEmpty);
      expect(o.cd.durationMs, 60000, reason: 'the other app kept its own default countdown');
      expect(net.deliveries.where((d) => d.to.app == other.id), isEmpty);
      expect(a.hub.peers.map((p) => p.app).toSet(), {manifest.id});
      for (final c in [a, b, o]) {
        await c.quit();
      }
    });

    test('the same app under another account is a stranger too', () async {
      final a = await open('laptop');
      final x = await open('stranger', env: {'APPKIT_ACCOUNT': 'someone-else'});
      final b = await open('desktop');
      await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty);
      a.controller.resetCountdown(durationMs: 7000);
      await until(() => b.cd.durationMs == 7000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(x.hub.peers, isEmpty);
      expect(x.cd.durationMs, 60000);
      for (final c in [a, b, x]) {
        await c.quit();
      }
    });
  });

  test('peers not declared in app.json: the Kit refuses, and the error names the app and the Kit', () async {
    final undeclared = AppManifest.parse(File('app.json').readAsStringSync().replaceAll('"venue", "peers"', '"venue"'));
    final dir = Directory('${tmp.path}/undeclared')..createSync();
    final ctx = await AppContext.open(undeclared, env: {'APPKIT_SCRATCH': dir.path, 'APPKIT_MODE': 'mock', 'HOME': dir.path}, announce: false);
    expect(() => buildController(ctx, RecordingNotifier(), network: net),
        throwsA(isA<KitNotDeclared>().having((e) => e.toString(), 'message', allOf(contains('peers'), contains('dev.demo.stopwatch')))));
    // and the app still works without peers when it asks for none
    final solo = buildController(ctx, RecordingNotifier(), peers: false, network: net);
    expect(solo.peers, isNull);
    await ctx.close();
  });

  test('peers that cannot start (a peers directory that is a file) leave the app working alone, with a reason', () async {
    final dir = Directory('${tmp.path}/real')..createSync();
    final blocker = File('${tmp.path}/not-a-dir')..writeAsStringSync('x');
    final ctx = await AppContext.open(manifest,
        env: {'APPKIT_SCRATCH': dir.path, 'APPKIT_MODE': 'real', 'HOME': dir.path, 'APPKIT_PEERS_DIR': blocker.path}, announce: false);
    final c = buildController(ctx, RecordingNotifier(), now: () => now);
    await c.peers!.handle.started;
    expect(c.peers!.handle.hub, isNull);
    expect(c.peers!.handle.error, contains('peers unavailable'));
    c.resetCountdown(durationMs: 4000);
    c.toggleCountdown();
    expect(c.state.countdown.clock.running, isTrue);
    await ctx.close();
  });
}

class _Silent extends AppCoordination {
  _Silent(this.channel);
  @override
  final String channel;
  @override
  Object? hello() => null;
  @override
  FutureOr<Admit> admit(Peer peer, Object? theirHello) => const Admit.accept();
  @override
  void onPeer(Peer peer, PeerChange change) {}
  @override
  void onMessage(Peer from, AppMessage message) {}
}
