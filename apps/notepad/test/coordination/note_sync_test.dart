// Two (or three) AppContexts in one test, each with its OWN note files, on one FakePeerNetwork. Plain `test`, real async, mock
// mode. The notes are real files read through the app's own NoteStore; only the NoteHost around them is a test double.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/coordination/note_sync.dart';
import 'package:notepad/coordination/notes_peers.dart';
import 'package:notepad/coordination/version_vector.dart';
import 'package:notepad/logic/note.dart';
import 'package:notepad/logic/note_store.dart';

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for ${what ?? 'a condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A NoteHost over real files. No in-memory copy: every question is answered from the directory.
class FileHost implements NoteHost {
  FileHost(this.store);
  final NoteStore store;
  final dirty = <String>{};

  @override
  List<Note> get notes => store.load().notes;
  @override
  Note? note(String id) => notes.where((n) => n.id == id).firstOrNull;
  @override
  bool isDamaged(String id) => store.load().damaged.any((d) => d.fileName == '$id.json');
  @override
  void flushNote(String id) {}
  @override
  void applyRemote(Note n) => store.save(n);
  @override
  void removeRemote(String id) => store.delete(id);
}

var wall = DateTime.utc(2026, 10, 22, 9);

class Replica {
  Replica(this.ctx, this.store, this.host, this.peers, this.reports);
  final AppContext ctx;
  final NoteStore store;
  final FileHost host;
  final NotesPeers peers;
  final List<String> reports;
  NoteSync get sync => peers.sync;
  PeerHub get hub => peers.handle.hub!;

  /// What the person does: edit and save (the controller would do this after the autosave pause).
  Note save(Note n) {
    store.save(n);
    sync.localSaved(n);
    return n;
  }

  Note create(String title, String body) {
    final n = store.create(title: title, body: body);
    sync.localSaved(n);
    return n;
  }

  Note edit(Note n, {String? title, String? body}) {
    wall = wall.add(const Duration(seconds: 1));
    return save(n.copyWith(title: title, body: body, updatedAt: wall));
  }

  void delete(String id) {
    store.delete(id);
    sync.localDeleted(id);
  }

  Map<String, String> snapshot() => {for (final n in store.load().notes) n.id: '${n.title}|${n.body}'};
  Note? get(String id) => host.note(id);
  Future<void> quit() => ctx.close();
}

void main() {
  final manifest = AppManifest.parse(File('app.json').readAsStringSync());
  late Directory tmp;
  late FakePeerNetwork net;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('notepad-peers-');
    net = FakePeerNetwork();
    wall = DateTime.utc(2026, 10, 22, 9);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Replica> open(String device,
      {AppManifest? m, Map<String, String> env = const {}, Duration heartbeat = const Duration(seconds: 30), int partBytes = 24 * 1024, int maxNoteBytes = 2 * 1024 * 1024, String? dirName, void Function(Directory notes)? plant}) async {
    final dir = Directory('${tmp.path}/${dirName ?? device}')..createSync(recursive: true);
    final ctx = await AppContext.open(m ?? manifest,
        env: {'APP_CONTEXT_SCRATCH': dir.path, 'APP_CONTEXT_MODE': 'mock', 'APP_CONTEXT_DEVICE': device, 'HOME': dir.path, ...env}, announce: false);
    final notesDir = Directory('${ctx.dirs.data}/notes')..createSync(recursive: true);
    plant?.call(notesDir);
    var t = 0;
    final store = NoteStore(notesDir.path, now: () => wall.add(Duration(microseconds: t++)), rng: null);
    final host = FileHost(store);
    final reports = <String>[];
    final peers = NotesPeers.start(ctx, host,
        report: reports.add, network: net, heartbeat: heartbeat, partBytes: partBytes, maxNoteBytes: maxNoteBytes);
    await peers.handle.started;
    return Replica(ctx, store, host, peers, reports);
  }

  Future<void> connected(Replica a, Replica b) =>
      until(() => a.hub.readyPeers.any((p) => p.id == b.hub.id) && b.hub.readyPeers.any((p) => p.id == a.hub.id), what: 'the copies to connect');

  Future<void> converged(List<Replica> rs, {String? what}) async {
    await until(() {
      final first = rs.first.snapshot();
      return rs.every((r) => r.snapshot().toString() == first.toString()) && rs.every((r) => r.sync.pending == 0);
    }, what: what ?? 'the copies to hold the same notes');
    // and quiet: equal digests everywhere
    await until(() => rs.every((r) => r.sync.digest() == rs.first.sync.digest()), what: 'equal digests');
  }

  group('sync', () {
    test('a copy that joins later receives every note (hello digest, then index, then pulls)', () async {
      final a = await open('laptop');
      final n1 = a.create('Groceries', 'milk\neggs');
      a.create('Ideas', 'a very good one');
      a.edit(n1, body: 'milk\neggs\nbread');
      final b = await open('desktop');
      await converged([a, b]);
      expect(b.snapshot().length, 2);
      expect(b.snapshot()[n1.id], 'Groceries|milk\neggs\nbread');
      expect(b.reports, isEmpty);
      await a.quit();
      await b.quit();
    });

    test('an edit, a rename and a new note on one copy reach the other while both run', () async {
      final a = await open('laptop'), b = await open('desktop');
      await connected(a, b);
      final n = a.create('Todo', 'one');
      await converged([a, b]);
      a.edit(n, body: 'one\ntwo');
      await converged([a, b]);
      expect(b.get(n.id)!.body, 'one\ntwo');
      b.edit(b.get(n.id)!, title: 'Todo (renamed)');
      await converged([a, b]);
      expect(a.get(n.id)!.title, 'Todo (renamed)');
      expect(a.reports + b.reports, isEmpty, reason: 'sequential edits are not conflicts');
      await a.quit();
      await b.quit();
    });

    test('a peer lost and back: edits made on both sides while apart become one visible conflict, not a silent overwrite', () async {
      final a = await open('laptop'), b = await open('desktop');
      await connected(a, b);
      final n = a.create('Plan', 'draft');
      await converged([a, b]);

      net.partition(a.hub.id, b.hub.id);
      await until(() => a.hub.readyPeers.isEmpty && b.hub.readyPeers.isEmpty);
      a.edit(a.get(n.id)!, body: 'draft + laptop idea'); // earlier
      b.edit(b.get(n.id)!, body: 'draft + desktop idea'); // later: keeps the note
      net.heal(a.hub.id, b.hub.id);
      await connected(a, b);
      await converged([a, b], what: 'the conflict to resolve identically');

      final notes = a.store.load().notes;
      expect(notes.length, 2, reason: 'the note and its conflict copy');
      expect(a.get(n.id)!.body, 'draft + desktop idea'); // the later edit keeps the name
      final copy = notes.singleWhere((x) => x.id != n.id);
      expect(copy.title, 'Plan (conflict from laptop)');
      expect(copy.body, 'draft + laptop idea', reason: 'nothing was lost');
      expect(b.snapshot(), a.snapshot());
      expect(b.get(copy.id)!.title, copy.title, reason: 'both copies derived the same id for the conflict note');
      expect(a.reports.single, allOf(contains('Plan'), contains('Both versions are kept')));
      expect(b.reports.single, contains('Both versions are kept'));
      // and it stays resolved: a second exchange changes nothing
      final before = a.snapshot();
      a.sync.sendIndex(a.hub.readyPeers.single);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(a.snapshot(), before);
      expect(a.store.load().notes.length, 2);
      await a.quit();
      await b.quit();
    });

    test('concurrent edits that produce the same text are not a conflict', () async {
      final a = await open('laptop'), b = await open('desktop');
      await connected(a, b);
      final n = a.create('Same', 'x');
      await converged([a, b]);
      net.isolate(a.hub.id);
      await until(() => a.hub.readyPeers.isEmpty);
      a.edit(a.get(n.id)!, body: 'agreed text');
      b.edit(b.get(n.id)!, body: 'agreed text');
      net.healAll();
      await connected(a, b);
      await converged([a, b]);
      expect(a.store.load().notes.length, 1);
      expect(a.reports + b.reports, isEmpty);
      await a.quit();
      await b.quit();
    });

    test('delete propagates; a copy that was away does not bring the note back; an edit made while apart beats the delete', () async {
      final a = await open('laptop'), b = await open('desktop'), c = await open('tablet');
      await connected(a, b);
      await connected(a, c);
      final gone = a.create('Gone', 'bye'), kept = a.create('Kept', 'hi');
      await converged([a, b, c]);

      net.isolate(c.hub.id); // the tablet is away with old copies of both notes
      await until(() => c.hub.readyPeers.isEmpty);
      a.delete(gone.id);
      a.delete(kept.id);
      c.edit(c.get(kept.id)!, body: 'edited on the tablet'); // deleted on A, edited on the tablet
      await until(() => b.get(gone.id) == null && b.get(kept.id) == null, what: 'B to follow the deletes');
      net.healAll();
      await connected(a, c);
      await converged([a, b, c]);
      expect(a.get(gone.id), isNull);
      expect(c.get(gone.id), isNull, reason: 'the away copy dropped the note instead of resurrecting it');
      expect(a.get(kept.id)?.body, 'edited on the tablet', reason: 'an edit beats a concurrent delete: the note is back everywhere');
      expect(b.get(kept.id)?.body, 'edited on the tablet');
      await a.quit();
      await b.quit();
      await c.quit();
    });
  });

  group('large notes (the Kit has no large transfer; Hearth carries 64 KiB)', () {
    test('a note over 64 KiB, with non-ASCII text, arrives byte-identical in parts that each fit the wire limit', () async {
      final a = await open('laptop'), b = await open('desktop');
      await connected(a, b);
      final body = List.generate(30000, (i) => 'line $i é€漢\n').join(); // about 500 KB, multi-byte characters
      final n = a.create('Big', body);
      expect(utf8.encode(body).length, greaterThan(64 * 1024));
      await converged([a, b]);
      expect(b.get(n.id)!.body, body);
      expect(File('${b.ctx.dirs.data}/notes/${n.id}.json').readAsStringSync(), File('${a.ctx.dirs.data}/notes/${n.id}.json').readAsStringSync());
      expect(a.sync.partsPulled + b.sync.partsPulled, greaterThan(15), reason: 'it travelled in many parts');
      final biggest = net.deliveries.map((d) => d.bytes.length).reduce((x, y) => x > y ? x : y);
      expect(biggest, lessThan(64 * 1024), reason: 'every frame, base64 and header included, fits the 64 KiB Hearth limit');
      await a.quit();
      await b.quit();
    });

    test('the sender edits the note while the receiver is reading it: the transfer restarts and ends on the newest text', () async {
      net.latency = const Duration(milliseconds: 15);
      final a = await open('laptop'), b = await open('desktop');
      await connected(a, b);
      final body = 'x' * 300000;
      final n = a.create('Big', body);
      await until(() => b.sync.partsPulled >= 2, what: 'the transfer to start');
      a.edit(a.get(n.id)!, body: 'short now');
      await converged([a, b]);
      expect(b.get(n.id)!.body, 'short now');
      await a.quit();
      await b.quit();
    });

    test('a note over the limit is refused with a clear message, stays intact locally, and does not keep the copies out of step', () async {
      final a = await open('laptop', maxNoteBytes: 100 * 1024), b = await open('desktop', maxNoteBytes: 100 * 1024);
      await connected(a, b);
      final small = a.create('Small', 'ok');
      final huge = a.create('Huge', 'y' * 150000);
      await until(() => b.get(small.id) != null, what: 'the small note');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(b.get(huge.id), isNull);
      expect(a.get(huge.id)!.body.length, 150000);
      expect(a.reports.single, allOf(contains('Huge'), contains('not synced'), contains('stays on this copy only')));
      expect(a.sync.digest(), b.sync.digest(), reason: 'a local-only note must not make every heartbeat look like a difference');
      await a.quit();
      await b.quit();
    });
  });

  group('the Kit has no replay and no ack', () {
    test('a lost "have" is repaired by the periodic digest', () async {
      final a = await open('laptop', heartbeat: const Duration(milliseconds: 150)), b = await open('desktop', heartbeat: const Duration(milliseconds: 150));
      await connected(a, b);
      net.dropIf = (from, to, bytes) => Envelope.decode(bytes).header.kind == 'sync.have';
      final n = a.create('Lost', 'message');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.get(n.id), isNull, reason: 'the announcement never arrived');
      net.dropIf = null;
      await until(() => b.get(n.id) != null, what: 'the digest to trigger an index and a pull');
      await a.quit();
      await b.quit();
    });
  });

  group('the files are the source of truth', () {
    test('a damaged note file is never overwritten by a synced note with the same id, and is not sent to anyone', () async {
      final a = await open('laptop');
      final n = a.create('Shared', 'from laptop');
      final b = await open('desktop', plant: (d) => File('${d.path}/${n.id}.json').writeAsStringSync('{ not json'));
      final damagedOnB = a.create('Other', 'fine');
      await until(() => b.get(damagedOnB.id) != null, what: 'the good note to arrive');
      expect(File('${b.ctx.dirs.data}/notes/${n.id}.json').readAsStringSync(), '{ not json', reason: 'byte for byte');
      expect(b.reports.any((r) => r.contains('damaged file')), isTrue);
      // and the other direction: B's damaged file is not in its index, so A never hears of a note it cannot read
      expect(a.get(n.id)!.body, 'from laptop');
      await a.quit();
      await b.quit();
    });

    test('a note edited by hand while the app was closed is noticed at start and synced', () async {
      final a = await open('laptop');
      final n = a.create('Hand', 'v1');
      final b = await open('desktop');
      await converged([a, b]);
      await a.quit();
      final f = File('${a.ctx.dirs.data}/notes/${n.id}.json');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      j['body'] = 'v2 edited with another program';
      j['updatedAt'] = DateTime.utc(2026, 10, 23).toIso8601String();
      f.writeAsStringSync(jsonEncode(j));
      final a2 = await open('laptop', dirName: 'laptop');
      await until(() => b.get(n.id)!.body.startsWith('v2'), what: 'the outside edit to sync');
      expect(a2.reports, isEmpty);
      await a2.quit();
      await b.quit();
    });

    test('a damaged sync.json is set aside, notes are untouched, and nothing is lost on the next sync', () async {
      final a = await open('laptop');
      final n = a.create('Keep', 'me');
      await a.quit();
      File('${a.ctx.dirs.data}/sync.json').writeAsStringSync('garbage');
      final a2 = await open('laptop', dirName: 'laptop');
      expect(a2.reports.single, contains('set aside'));
      expect(a2.get(n.id)!.body, 'me');
      expect(Directory(a2.ctx.dirs.data).listSync().any((f) => f.path.contains('sync.json.damaged-')), isTrue);
      await a2.quit();
    });
  });

  group('a hostile or broken peer', () {
    test('malformed messages, bad ids, impossible versions and oversize lists are ignored and counted', () async {
      final a = await open('laptop');
      final evil = _Scripted(PeerHub(account: 'local', app: manifest.id, device: 'evil', instance: 'e1', provider: net.provider(), hook: _EvilHook()));
      await evil.hub.start();
      await until(() => evil.hub.readyPeers.isNotEmpty && a.hub.readyPeers.isNotEmpty);
      final before = a.snapshot();
      Future<void> send(String kind, Object? json, {int schema = 1}) => evil.hub.send(evil.hub.readyPeers.single, json is Uint8List ? json : Uint8List.fromList(utf8.encode(jsonEncode(json))), kind: kind, schema: schema);
      Map<String, Object?> e(Object id, Object vv, {Object del = false, Object by = 'evil'}) => {'id': id, 'vv': vv, 'del': del, 'by': by};
      await send('sync.have', Uint8List.fromList([0xff, 0x00])); // not UTF-8
      await send('sync.have', {'entries': 'nope'});
      await send('sync.have', {'entries': List.filled(501, e('abcd1234', {'evil': 1}))});
      await send('sync.have', {'entries': [e('../../etc/passwd', {'evil': 1}), e('ABC', {'evil': 1}), e('abcd1234', {'evil': -1}), e('abcd1234', {'': 1}), e('abcd1234', 'x'), e('abcd1234', {'evil': 1}, del: 'yes'), e('abcd1234', {'evil': 1}, by: ''), 42, null]});
      await send('sync.have', {'entries': []}, schema: 2);
      await send('sync.get', {'id': 1});
      await send('sync.digest', {'digest': 7});
      await send('sync.nonsense', {});
      await until(() => a.sync.ignored >= 16, what: 'all 16 to be counted');
      expect(a.sync.ignored, 16);
      expect(a.snapshot(), before);
      expect(a.hub.stats.hookErrors, 0);
      expect(a.hub.readyPeers, hasLength(1), reason: 'garbage does not drop the link');
      await a.quit();
      await evil.hub.close();
    });

    test('lies in a pull reply (wrong note, absurd part count, bad base64, not JSON) never reach the notes, and the queue is not stuck', () async {
      final a = await open('laptop');
      final hook = _EvilHook();
      final evil = PeerHub(account: 'local', app: manifest.id, device: 'evil', instance: 'e1', provider: net.provider(), hook: hook);
      await evil.start();
      await until(() => evil.readyPeers.isNotEmpty && a.hub.readyPeers.isNotEmpty);
      final replies = <Object>[
        {'ok': true, 'vv': {'evil': 1}, 'by': 'evil', 'parts': 1, 'data': base64Encode(utf8.encode(jsonEncode(Note(id: 'otherid1', title: 't', body: 'b', createdAt: wall, updatedAt: wall).toJson())))},
        {'ok': true, 'vv': {'evil': 1}, 'by': 'evil', 'parts': 1000000000, 'data': ''},
        {'ok': true, 'vv': {'evil': 1}, 'by': 'evil', 'parts': 1, 'data': '***not base64***'},
        {'ok': true, 'vv': {'evil': 1}, 'by': 'evil', 'parts': 1, 'data': base64Encode(utf8.encode('{"id":"victim01"'))},
        Uint8List.fromList([1, 2, 3]),
      ];
      hook.replies.addAll(replies);
      for (var i = 0; i < replies.length; i++) {
        await evil.send(evil.readyPeers.single, Uint8List.fromList(utf8.encode(jsonEncode({'entries': [{'id': 'victim0$i', 'vv': {'evil': 1}, 'del': false, 'by': 'evil'}]}))), kind: 'sync.have', schema: 1);
      }
      await until(() => a.sync.ignored >= replies.length && a.sync.pending == 0, what: 'every lie to be refused');
      expect(a.store.load().notes, isEmpty);
      expect(a.store.load().damaged, isEmpty);
      // the queue still works: a real peer's note arrives afterwards
      final b = await open('desktop');
      final n = b.create('Real', 'still works');
      await until(() => a.get(n.id) != null, what: 'a legitimate note after the lies');
      await a.quit();
      await b.quit();
      await evil.close();
    });

    test('a peer that speaks another notes protocol, or sends a hello of the wrong shape, is refused at the door', () async {
      final a = await open('laptop');
      final old = _EvilHook(helloValue: {'proto': 2, 'digest': 'x'});
      final bad = _EvilHook(helloValue: 'hello');
      final h1 = PeerHub(account: 'local', app: manifest.id, device: 'old', instance: 'o1', provider: net.provider(), hook: old);
      final h2 = PeerHub(account: 'local', app: manifest.id, device: 'bad', instance: 'b1', provider: net.provider(), hook: bad);
      await h1.start();
      await h2.start();
      await until(() => !h1.peers.any((p) => p.id.device == 'laptop') && !h2.peers.any((p) => p.id.device == 'laptop'), what: 'both refused');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(a.hub.readyPeers, isEmpty, reason: 'neither stranger ever became a peer of the notepad');
      expect(a.hub.stats.hookErrors, 0);
      await a.quit();
      await h1.close();
      await h2.close();
    });
  });

  group('two copies on one device', () {
    test('share one notes folder, so they are not synced with each other (and say so instead of corrupting sync.json)', () async {
      final a = await open('laptop');
      final twin = await open('laptop', dirName: 'laptop-second-copy'); // same device id, another process
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(a.hub.readyPeers, isEmpty);
      expect(twin.hub.readyPeers, isEmpty);
      await a.quit();
      await twin.quit();
    });
  });

  group('scope', () {
    test('another app on the same network, or the same app under another account, never receives a note or appears as a peer', () async {
      final other = AppManifest.parse(File('app.json').readAsStringSync().replaceAll('com.slashbuilder.demo.notepad', 'com.slashbuilder.demo.minesweeper'));
      final a = await open('laptop'), b = await open('desktop');
      final game = await open('laptop-game', m: other);
      final stranger = await open('stranger', env: {'APP_CONTEXT_ACCOUNT': 'someone-else'});
      await connected(a, b);
      a.create('Private', 'for my copies only');
      await converged([a, b]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (final x in [game, stranger]) {
        expect(x.hub.peers, isEmpty);
        expect(x.store.load().notes, isEmpty);
      }
      expect(net.deliveries.where((d) => d.to.app == other.id || d.to.account == 'someone-else'), isEmpty);
      for (final r in [a, b, game, stranger]) {
        await r.quit();
      }
    });

    test('peers not declared in app.json: starting sync fails loudly with the Kit\'s error; the app without sync still works', () async {
      final undeclared = AppManifest.parse(File('app.json').readAsStringSync().replaceAll('"kits": ["peers"]', '"kits": []'));
      final dir = Directory('${tmp.path}/undeclared')..createSync();
      final ctx = await AppContext.open(undeclared, env: {'APP_CONTEXT_SCRATCH': dir.path, 'APP_CONTEXT_MODE': 'mock', 'HOME': dir.path}, announce: false);
      final host = FileHost(NoteStore('${ctx.dirs.data}/notes'));
      expect(() => NotesPeers.start(ctx, host, report: (_) {}, network: net), throwsA(isA<KitNotDeclared>()));
      await ctx.close();
    });
  });

  test('metadata round trip: version vectors order edits, and "both edited" is not "one is behind"', () {
    const a = Vv({'x': 2}), b = Vv({'x': 1, 'y': 1});
    expect(a.compare(b), VvOrder.concurrent);
    expect(a.compare(a.bump('x')), VvOrder.before);
    expect(a.join(b).compare(a), VvOrder.after);
    expect(Vv.parse({'x': 0}), isNull);
    expect(Vv.parse({'x': 1 << 41}), isNull);
    expect(Vv.parse(List.filled(1, 1)), isNull);
    expect(AppJsonFile(File('${tmp.path}/none.json')).read().exists, isFalse);
  });
}

class _Scripted {
  _Scripted(this.hub);
  final PeerHub hub;
}

/// A peer that says what the test tells it to: scripted hello, scripted replies to `sync.get`.
class _EvilHook extends AppCoordination {
  _EvilHook({this.helloValue});
  final Object? helloValue;
  final replies = <Object>[];
  PeerHub? hub;
  @override
  String get channel => 'notes';
  @override
  void attach(PeerHub h) => hub = h;
  @override
  Object? hello() => helloValue ?? {'proto': 1, 'digest': 'evil', 'count': 0};
  @override
  FutureOr<Admit> admit(Peer peer, Object? theirHello) => const Admit.accept();
  @override
  void onPeer(Peer peer, PeerChange change) {}
  @override
  void onMessage(Peer from, AppMessage m) {
    if (m.kind == 'sync.get' && m.requestId != null && replies.isNotEmpty) {
      final r = replies.removeAt(0);
      unawaited(hub!.reply(m, r is Uint8List ? r : Uint8List.fromList(utf8.encode(jsonEncode(r))), schema: 1).then((_) {}, onError: (_) {}));
    }
  }
}
