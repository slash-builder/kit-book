// Two AppContexts in one test, one FakePeerNetwork between them: the real GameController on each side, real files, mock mode.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minesweeper/coordination/game_hook.dart';
import 'package:minesweeper/coordination/game_peers.dart';
import 'package:minesweeper/logic/game.dart';
import 'package:minesweeper/logic/settings.dart';
import 'package:minesweeper/logic/storage.dart';
import 'package:minesweeper/ui/game_controller.dart';

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for ${what ?? 'a condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// A board with its mines in fixed places, so two copies can be compared cell by cell.
Minesweeper board({Set<(int, int)>? mines}) =>
    Minesweeper.withMines(Difficulty.beginner, mines ?? {(0, 0), (0, 8), (8, 0), (8, 8), (4, 4), (2, 6), (6, 2), (1, 1), (7, 7), (3, 5)});

class Copy {
  Copy(this.ctx, this.controller, this.peers);
  final AppContext ctx;
  final GameController controller;
  final GamePeers peers;
  PeerHub get hub => peers.handle.hub!;
  GameHook get hook => peers.hook;
  Minesweeper get game => controller.game;
  String get cells => jsonEncode(game.toJson());
  Peer peer(String device) => hub.readyPeers.singleWhere((p) => p.id.device == device);
  File get savedGame => File('${ctx.dirs.data}/game.json');
  Future<void> quit() => ctx.close();
}

void main() {
  final manifest = AppManifest.parse(File('app.json').readAsStringSync());
  late Directory tmp;
  late FakePeerNetwork net;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mines-peers-');
    net = FakePeerNetwork();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Copy> open(String device, {AppManifest? m, Map<String, String> env = const {}}) async {
    final dir = Directory('${tmp.path}/$device')..createSync(recursive: true);
    final ctx = await AppContext.open(m ?? manifest,
        env: {'APP_CONTEXT_SCRATCH': dir.path, 'APP_CONTEXT_MODE': 'mock', 'APP_CONTEXT_DEVICE': device, 'HOME': dir.path, ...env}, announce: false);
    final c = GameController(storage: GameStorage(ctx.dirs.data), settings: Settings(SessionSettings(ctx.config)), rng: Random(7));
    final p = GamePeers.start(ctx, c, network: net);
    c.peers = p;
    c.onMove = (op, r, col, mark, wasReady) => p.hook.localMove(op, r, col, mark: mark, wasReady: wasReady);
    c.onNewBoard = p.hook.localBoard;
    await p.handle.started;
    return Copy(ctx, c, p);
  }

  Future<(Copy, Copy)> pair() async {
    final a = await open('laptop'), b = await open('desktop');
    await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty, what: 'the copies to connect');
    return (a, b);
  }

  /// A has a game in progress with a few squares open and a flag.
  void playSome(Copy a) {
    a.controller.game = board();
    a.controller.reveal(4, 0);
    a.controller.reveal(8, 4);
    a.controller.flag(0, 0);
  }

  /// Squares that are still closed, safe and unflagged on [c]'s board (a move there changes the board).
  List<(int, int)> closedSafe(Copy c) => [
        for (var r = 0; r < c.game.rows; r++)
          for (var col = 0; col < c.game.cols; col++)
            if (!c.game.at(r, col).revealed && !c.game.at(r, col).mine && c.game.at(r, col).mark == Mark.none) (r, col),
      ];

  group('handoff', () {
    test('send this game to my other copy: it asks, gets the board, takes over, and the sender stands down', () async {
      final (a, b) = await pair();
      playSome(a);
      final before = a.cells;
      expect(a.game.status, GameStatus.playing);
      expect(a.savedGame.existsSync(), isTrue);

      await a.hook.offer(a.peer('desktop'), 'handoff');
      await until(() => b.hook.incoming.isNotEmpty, what: 'the offer to appear on B');
      final offer = b.hook.incoming.values.single;
      expect(offer.mode, 'handoff');
      expect(offer.summary, contains('Beginner'));
      expect(b.cells, isNot(before), reason: 'an offer alone changes nothing');

      final said = await b.hook.accept(offer);
      expect(said, startsWith('Took over the game from laptop #'));
      expect(b.cells, before, reason: 'the board arrived cell for cell, including the flag');
      expect(b.savedGame.existsSync(), isTrue, reason: 'and it is saved on the new copy');
      await until(() => a.game.status == GameStatus.ready, what: 'A to stand down');
      expect(a.savedGame.existsSync(), isFalse);
      expect(a.hook.message, contains('took the game'));
      expect(b.hook.incoming, isEmpty);
      await a.quit();
      await b.quit();
    });

    test('declining changes nothing and tells the sender; ignoring it changes nothing either', () async {
      final (a, b) = await pair();
      playSome(a);
      final before = a.cells;
      await a.hook.offer(a.peer('desktop'), 'handoff');
      await until(() => b.hook.incoming.isNotEmpty);
      b.hook.decline(b.hook.incoming.values.single);
      await until(() => a.hook.message!.contains('declined'));
      expect(a.cells, before);
      expect(b.game.status, GameStatus.ready);
      await a.quit();
      await b.quit();
    });

    test('a copy that joins later is found and can be handed a game (an old offer is NOT replayed to it)', () async {
      final a = await open('laptop');
      playSome(a);
      final b = await open('desktop');
      await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty);
      expect(b.hook.incoming, isEmpty, reason: 'the Kit has no replay; nothing was offered while B was away');
      await a.hook.offer(a.peer('desktop'), 'handoff');
      await until(() => b.hook.incoming.isNotEmpty);
      await b.hook.accept(b.hook.incoming.values.single);
      expect(b.cells, isNot(a.cells));
      expect(b.game.status, GameStatus.playing);
      await a.quit();
      await b.quit();
    });

    test('the sender leaves before the receiver says yes: the offer disappears; saying yes late fails with words, not an exception', () async {
      final (a, b) = await pair();
      playSome(a);
      await a.hook.offer(a.peer('desktop'), 'handoff');
      await until(() => b.hook.incoming.isNotEmpty);
      final offer = b.hook.incoming.values.single;
      await a.quit();
      await until(() => b.hook.incoming.isEmpty, what: 'the offer to be withdrawn when its sender left');
      expect(await b.hook.accept(offer), contains('no longer connected'));
      expect(b.game.status, GameStatus.ready);
      await b.quit();
    });

    test('the receiver says yes but the confirmation is lost: it keeps the game, says so, and the sender still has it too (a duplicate, never zero)', () async {
      final (a, b) = await pair();
      playSome(a);
      final before = a.cells;
      await a.hook.offer(a.peer('desktop'), 'handoff');
      await until(() => b.hook.incoming.isNotEmpty);
      // swallow every frame from B to A after the board has been requested: the 'game.taken' request never arrives
      net.dropIf = (from, to, bytes) {
        final k = Envelope.decode(bytes).header.kind;
        return from.device == 'desktop' && k == 'game.taken';
      };
      final said = await b.hook.accept(b.hook.incoming.values.single);
      expect(said, contains('did not confirm'));
      expect(b.cells, before);
      expect(a.cells, before);
      await a.quit();
      await b.quit();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('playing together', () {
    Future<(Copy, Copy)> sharing() async {
      final (a, b) = await pair();
      playSome(a);
      await a.hook.offer(a.peer('desktop'), 'share');
      await until(() => b.hook.incoming.isNotEmpty);
      await b.hook.accept(b.hook.incoming.values.single);
      await until(() => a.hook.sharing != null && b.hook.sharing != null, what: 'both to be sharing');
      expect(b.cells, a.cells);
      expect(a.game.status, GameStatus.playing, reason: 'sharing does not take the game away');
      return (a, b);
    }

    test('moves from either copy apply to both', () async {
      final (a, b) = await sharing();
      final (r1, c1) = closedSafe(a).first;
      a.controller.reveal(r1, c1);
      await until(() => b.game.at(r1, c1).revealed, what: 'a reveal to cross');
      b.controller.flag(1, 1);
      await until(() => a.game.at(1, 1).mark == Mark.flag, what: 'a flag to cross');
      b.controller.flag(1, 1);
      b.controller.flag(1, 1); // flag, question? (off) -> none, flag again: absolute marks cannot cancel each other
      await until(() => a.game.at(1, 1).mark == b.game.at(1, 1).mark);
      expect(a.cells, b.cells);
      await a.quit();
      await b.quit();
    });

    test('a lost move is noticed at the next move (checksum) and repaired by pulling the whole board', () async {
      final (a, b) = await sharing();
      net.dropIf = (from, to, bytes) => Envelope.decode(bytes).header.kind == 'game.move';
      final (r1, c1) = closedSafe(a).first;
      a.controller.reveal(r1, c1); // never arrives
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.game.at(r1, c1).revealed, isFalse);
      net.dropIf = null;
      final (r2, c2) = closedSafe(a).last;
      a.controller.reveal(r2, c2);
      await until(() => b.cells == a.cells, what: 'the resync');
      expect(b.game.at(r1, c1).revealed, isTrue);
      await a.quit();
      await b.quit();
    });

    test('both players make the first move of a fresh board at the same instant: both end on ONE board', () async {
      final (a, b) = await pair();
      for (final c in [a, b]) {
        c.controller.newGame();
      }
      await a.hook.offer(a.peer('desktop'), 'share');
      await until(() => b.hook.incoming.isNotEmpty);
      await b.hook.accept(b.hook.incoming.values.single);
      await until(() => a.hook.sharing != null);
      a.controller.reveal(4, 4);
      b.controller.reveal(0, 8); // before A's board message can reach B
      await until(() => a.cells == b.cells, what: 'one board');
      expect(a.game.status, GameStatus.playing);
      await a.quit();
      await b.quit();
    });

    test('new game on one copy starts it on both', () async {
      final (a, b) = await sharing();
      b.controller.newGame(Difficulty.intermediate);
      await until(() => a.game.difficulty == Difficulty.intermediate, what: 'the new board');
      expect(a.game.status, GameStatus.ready);
      await a.quit();
      await b.quit();
    });

    test('a peer lost and back: sharing ends visibly on both, each keeps its own board, and playing together needs a new offer', () async {
      final (a, b) = await sharing();
      net.partition(a.hub.id, b.hub.id);
      await until(() => a.hook.sharing == null && b.hook.sharing == null);
      expect(a.hook.message, contains('Stopped playing together'));
      final (r1, c1) = closedSafe(a).first;
      a.controller.reveal(r1, c1);
      net.heal(a.hub.id, b.hub.id);
      await until(() => a.hub.readyPeers.isNotEmpty && b.hub.readyPeers.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(b.game.at(r1, c1).revealed, isFalse, reason: 'not sharing any more: nothing is applied behind the person\'s back');
      await a.hook.offer(a.peer('desktop'), 'share');
      await until(() => b.hook.incoming.isNotEmpty);
      await b.hook.accept(b.hook.incoming.values.single);
      await until(() => a.cells == b.cells);
      await a.quit();
      await b.quit();
    });

    test('stop sharing: moves stop crossing', () async {
      final (a, b) = await sharing();
      a.hook.stopSharing();
      await until(() => b.hook.sharing == null);
      final (r1, c1) = closedSafe(a).first;
      a.controller.reveal(r1, c1);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(b.game.at(r1, c1).revealed, isFalse);
      await a.quit();
      await b.quit();
    });
  });

  group('a hostile or broken peer', () {
    late Copy a;
    late PeerHub evil;
    late _EvilHook hook;

    Future<void> connect() async {
      a = await open('laptop');
      hook = _EvilHook();
      evil = PeerHub(account: 'local', app: manifest.id, device: 'evil', instance: 'e1', provider: net.provider(), hook: hook);
      await evil.start();
      await until(() => evil.readyPeers.isNotEmpty && a.hub.readyPeers.isNotEmpty);
    }

    Future<void> send(String kind, Object? json) =>
        evil.send(evil.readyPeers.single, json is Uint8List ? json : Uint8List.fromList(utf8.encode(jsonEncode(json))), kind: kind, schema: 1);

    test('malformed offers, moves from a stranger, confirmations nobody asked for, and requests for a board nobody offered are refused', () async {
      await connect();
      playSome(a);
      final before = a.cells;
      Map<String, Object?> offer(Object id, Object mode, Object d, Object st, Object secs, Object opened) =>
          {'id': id, 'mode': mode, 'difficulty': d, 'status': st, 'seconds': secs, 'opened': opened};
      await send('game.offer', Uint8List.fromList([0xff, 0xfe]));
      await send('game.offer', offer('x' * 100, 'handoff', 'beginner', 'playing', 1, 1));
      await send('game.offer', offer('ok', 'steal', 'beginner', 'playing', 1, 1));
      await send('game.offer', offer('ok', 'handoff', 'nightmare', 'playing', 1, 1));
      await send('game.offer', offer('ok', 'handoff', 'beginner', 'playing', -1, 1));
      await send('game.offer', offer('ok', 'handoff', 'beginner', 'playing', 1, 9999));
      await send('game.move', {'op': 'reveal', 'r': 7, 'c': 3, 'mark': null, 'sum': 'x'}); // not sharing with us
      await send('game.board', {'epoch': 99, 'board': board().toJson()}); // same
      await send('game.taken', {'offer': 'whatever'}); // we offered nothing
      await send('game.declined', {'offer': 'whatever'});
      await send('game.leave', {});
      await send('game.nonsense', {});
      await until(() => a.hook.ignored >= 12, what: 'all twelve to be refused');
      expect(a.cells, before);
      expect(a.hook.incoming, isEmpty);
      // asking for the board without an offer is answered "no", and the answer does not contain the board
      final r = await evil.request(evil.readyPeers.single, Uint8List.fromList(utf8.encode('{"offer":"guess"}')), kind: 'game.take', schema: 1);
      expect(utf8.decode(r.payload), isNot(contains('cells')));
      expect(jsonDecode(utf8.decode(r.payload))['ok'], false);
      await a.quit();
      await evil.close();
    });

    test('a confirmation from the wrong peer does not release the game', () async {
      await connect();
      final b = await open('desktop');
      await until(() => a.hub.readyPeers.length == 2);
      playSome(a);
      final before = a.cells;
      await a.hook.offer(a.peer('desktop'), 'handoff'); // offered to desktop, not to evil
      await until(() => b.hook.incoming.isNotEmpty);
      final r = await evil.request(evil.readyPeers.firstWhere((p) => p.id.device == 'laptop'), Uint8List.fromList(utf8.encode('{"offer":"${b.hook.incoming.values.single.id}"}')), kind: 'game.taken', schema: 1);
      expect(jsonDecode(utf8.decode(r.payload))['ok'], false);
      expect(a.cells, before, reason: 'still ours');
      expect(a.game.status, GameStatus.playing);
      await a.quit();
      await b.quit();
      await evil.close();
    });

    test('an inconsistent board in a reply (wrong cell count, mines before the first move, impossible values) is refused and nothing changes', () async {
      await connect();
      a.controller.game = board();
      final mine = a.cells;
      final lies = <Map<String, Object?>>[
        {...board().toJson(), 'cells': List.filled(5, 0)},
        {...Minesweeper(Difficulty.beginner).toJson(), 'cells': List.filled(81, 1)}, // status ready but mines present
        {...board().toJson(), 'cells': List.filled(81, 0x1f)},
        {...board().toJson(), 'difficulty': 'nope'},
        {...board().toJson(), 'seconds': 100000},
      ];
      for (var i = 0; i < lies.length; i++) {
        hook.reply = {'ok': true, 'board': lies[i]};
        await send('game.offer', {'id': 'o$i', 'mode': 'handoff', 'difficulty': 'beginner', 'status': 'playing', 'seconds': 1, 'opened': 1});
        await until(() => a.hook.incoming.isNotEmpty);
        final said = await a.hook.accept(a.hook.incoming.values.single);
        expect(said, contains('was not accepted'), reason: 'lie $i');
        expect(a.cells, mine, reason: 'lie $i changed the board');
      }
      await a.quit();
      await evil.close();
    });

    test('a peer on another minesweeper protocol is refused at the door', () async {
      a = await open('laptop');
      final old = PeerHub(account: 'local', app: manifest.id, device: 'old', instance: 'o1', provider: net.provider(), hook: _EvilHook(helloValue: {'proto': 2}));
      await old.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(a.hub.readyPeers, isEmpty);
      expect(old.readyPeers, isEmpty);
      await a.quit();
      await old.close();
    });
  });

  group('scope', () {
    test('another app on the same network, or another account, never sees the game or the offers', () async {
      final other = AppManifest.parse(File('app.json').readAsStringSync().replaceAll('com.slashbuilder.demo.minesweeper', 'com.slashbuilder.demo.notepad'));
      final (a, b) = await pair();
      final notes = await open('laptop-notes', m: other);
      final stranger = await open('stranger', env: {'APP_CONTEXT_ACCOUNT': 'someone-else'});
      playSome(a);
      await a.hook.offer(a.peer('desktop'), 'handoff');
      await until(() => b.hook.incoming.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (final x in [notes, stranger]) {
        expect(x.hub.peers, isEmpty);
        expect(x.hook.incoming, isEmpty);
      }
      expect(net.deliveries.where((d) => d.to.app == other.id || d.to.account == 'someone-else'), isEmpty);
      for (final c in [a, b, notes, stranger]) {
        await c.quit();
      }
    });

    test('peers not declared in app.json: starting fails loudly with the Kit\'s error', () async {
      final undeclared = AppManifest.parse(File('app.json').readAsStringSync().replaceAll('"kits": ["peers"]', '"kits": []'));
      final dir = Directory('${tmp.path}/undeclared')..createSync();
      final ctx = await AppContext.open(undeclared, env: {'APP_CONTEXT_SCRATCH': dir.path, 'APP_CONTEXT_MODE': 'mock', 'HOME': dir.path}, announce: false);
      final c = GameController(storage: GameStorage(ctx.dirs.data), settings: Settings(SessionSettings(ctx.config)));
      expect(() => GamePeers.start(ctx, c, network: net), throwsA(isA<KitNotDeclared>()));
      await ctx.close();
    });

    test('peers that cannot start leave the game working alone, with a reason', () async {
      final dir = Directory('${tmp.path}/real')..createSync();
      final blocker = File('${tmp.path}/file')..writeAsStringSync('x');
      final ctx = await AppContext.open(manifest,
          env: {'APP_CONTEXT_SCRATCH': dir.path, 'APP_CONTEXT_MODE': 'real', 'HOME': dir.path, 'APP_CONTEXT_PEERS_DIR': blocker.path}, announce: false);
      final c = GameController(storage: GameStorage(ctx.dirs.data), settings: Settings(SessionSettings(ctx.config)));
      final p = GamePeers.start(ctx, c);
      await p.handle.started;
      expect(p.handle.hub, isNull);
      expect(p.handle.error, contains('peers unavailable'));
      c.game = board();
      c.reveal(4, 0);
      expect(c.game.status, GameStatus.playing);
      await ctx.close();
    });
  });
}

class _EvilHook extends AppCoordination {
  _EvilHook({this.helloValue});
  final Object? helloValue;
  Object? reply;
  PeerHub? hub;
  @override
  String get channel => 'game';
  @override
  void attach(PeerHub h) => hub = h;
  @override
  Object? hello() => helloValue ?? {'proto': 1};
  @override
  FutureOr<Admit> admit(Peer peer, Object? theirHello) => const Admit.accept();
  @override
  void onPeer(Peer peer, PeerChange change) {}
  @override
  void onMessage(Peer from, AppMessage m) {
    if (m.kind == 'game.take' && m.requestId != null && reply != null) {
      unawaited(hub!.reply(m, Uint8List.fromList(utf8.encode(jsonEncode(reply))), schema: 1).then((_) {}, onError: (_) {}));
    } else if (m.kind == 'game.taken' && m.requestId != null) {
      unawaited(hub!.reply(m, Uint8List.fromList(utf8.encode('{"ok":true}')), schema: 1).then((_) {}, onError: (_) {}));
    }
  }
}
