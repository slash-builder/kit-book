/// Sync scenarios that do not care which core is under them. `test/sync_fake_test.dart` runs them on the in-memory fake (fast,
/// no native library); `integration_test/notes_rust_test.dart` runs the same functions on the real Rust core inside the app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:application_kit/application_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_rust/core/notes_core.dart';

import 'copy.dart';

/// Pseudo-random printable text, the same on every run.
String text(int len, int seed) {
  var x = (seed * 0x9E3779B1 + 1) & 0xffffffff;
  const alphabet = 'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n';
  final out = StringBuffer();
  final buf = <int>[];
  for (var i = 0; i < len; i++) {
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    buf.add(alphabet.codeUnitAt(x % alphabet.length));
    if (buf.length == 8192) {
      out.write(String.fromCharCodes(buf));
      buf.clear();
    }
  }
  out.write(String.fromCharCodes(buf));
  return out.toString();
}

class Scenarios {
  Scenarios(this.manifestText, this.factory);
  final String manifestText;
  final CoreFactory factory;

  Future<(Directory, FakePeerNetwork)> _world() async {
    final root = Directory.systemTemp.createTempSync('notes-rust-sync-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    return (root, FakePeerNetwork());
  }

  Future<Copy> _copy(Directory root, String name) => Copy.open(manifestText, root, name, factory);

  /// Two copies find each other; notes made, edited and deleted on either side reach the other, and both end with the same
  /// digest.
  Future<void> convergence() async {
    final (root, net) = await _world();
    final a = await _copy(root, 'laptop');
    final b = await _copy(root, 'desktop');
    final first = await a.write('Shopping', 'milk\neggs\n');
    await a.write('Ideas', 'a Rust core\n');
    await a.startPeers(net);
    await b.startPeers(net);

    await until(() async => (await b.core.listNotes()).length == 2, what: 'both notes reach the second copy');
    expect((await b.core.getNote(first.id)).body, 'milk\neggs\n');
    expect(await sameNotes(a, b), isTrue);

    await b.write('Shopping', 'milk\neggs\nbread\n', id: first.id);
    await until(() async => (await a.core.getNote(first.id)).body == 'milk\neggs\nbread\n', what: 'an edit on the second copy reaches the first');

    final made = await b.write('From desktop', 'hello');
    await until(() async => (await a.core.listNotes()).any((n) => n.id == made.id), what: 'a note made on the second copy');

    await a.core.deleteNote(first.id);
    await a.peers!.sync.localChanged([first.id]);
    await until(() async => !(await b.core.listNotes()).any((n) => n.id == first.id), what: 'a delete');
    await until(() => sameNotes(a, b), what: 'equal digests');
    expect(a.reports, isEmpty);
    expect(b.reports, isEmpty);
    await a.close();
    await b.close();
  }

  /// A one-byte edit of a large note moves a small part of it. Returns (cold bytes, edit bytes, body length).
  Future<(int, int, int)> smallEdit(int bodyBytes) async {
    final (root, net) = await _world();
    final a = await _copy(root, 'laptop');
    final b = await _copy(root, 'desktop');
    final body = text(bodyBytes, 3);
    final n = await a.write('Big', body);
    await a.startPeers(net);
    await b.startPeers(net);
    await until(() async => (await b.core.listNotes()).length == 1, what: 'the cold sync');
    expect((await b.core.getNote(n.id)).body.length, bodyBytes);
    final cold = b.peers!.sync.bytesPulled;
    final coldParts = b.peers!.sync.partsPulled;
    expect(cold, greaterThan(bodyBytes * 0.9), reason: 'a cold sync carries the body');
    expect(coldParts, greaterThan(bodyBytes ~/ (24 * 1024)), reason: 'sent in parts of at most 24 KiB');

    final units = body.codeUnits.toList();
    final at = bodyBytes ~/ 2;
    units[at] = units[at] == 0x71 ? 0x7a : 0x71; // 'q' <-> 'z': exactly one byte
    final edited = String.fromCharCodes(units);
    await a.write('Big', edited, id: n.id);
    await until(() async => (await b.core.getNote(n.id)).body == edited, what: 'the one-byte edit');
    final edit = b.peers!.sync.bytesPulled - cold;
    expect(edit, lessThan(bodyBytes ~/ 10), reason: 'one byte moved $edit of $bodyBytes bytes');
    expect(b.peers!.sync.partsPulled - coldParts, lessThan(20));
    await until(() => sameNotes(a, b), what: 'equal digests');
    await a.close();
    await b.close();
    return (cold, edit, bodyBytes);
  }

  /// A peer that serves a damaged block is refused: nothing is stored and no head moves. An honest retry then works.
  Future<void> tamperedBlockIsRefused() async {
    final (root, net) = await _world();
    final a = await _copy(root, 'laptop');
    final b = await _copy(root, 'desktop');
    final n = await a.write('Mine', text(90 * 1024, 5));
    final digestBefore = await b.core.headsDigest();
    final blocksBefore = (await b.core.stats()).blockCount;

    Uint8List flip(Uint8List export) => Uint8List.fromList(export)..[export.length - 1] ^= 0x01;
    await a.startPeers(net, serveTransform: flip);
    await b.startPeers(net);
    await until(() async => b.peers!.sync.refused > 0, what: 'the damaged block to be refused');
    await b.peers!.sync.idle();

    expect(await b.core.headsDigest(), digestBefore, reason: 'the head did not move');
    expect((await b.core.stats()).blockCount, blocksBefore, reason: 'nothing was stored');
    expect(await b.core.listNotes(), isEmpty);
    expect(b.reports.single, contains('did not match its hash and was refused'));

    // The same bytes, un-damaged, are accepted: the refusal was about the bytes, not about the peer.
    a.peers!.sync.serveTransform = null;
    await a.peers!.sync.localChanged([n.id]);
    await until(() async => (await b.core.listNotes()).length == 1, what: 'the honest retry');
    expect((await b.core.getNote(n.id)).body.length, 90 * 1024);
    await a.close();
    await b.close();
  }

  /// Both copies edit one note while apart. The core returns both versions; the app's policy keeps both; the copies agree.
  Future<void> conflictKeepsBothAndConverges() async {
    final (root, net) = await _world();
    final a = await _copy(root, 'laptop');
    final b = await _copy(root, 'desktop');
    final n = await a.core.createNote('Plan', 'base\n');
    await a.startPeers(net);
    await b.startPeers(net);
    await until(() async => (await b.core.listNotes()).length == 1, what: 'the base note');
    await a.peers!.sync.idle();
    await b.peers!.sync.idle();

    // apart: stop hearing each other by editing on both cores before either announces
    await a.core.saveNote(n.id, 'Plan', 'base\nfrom laptop\n');
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await b.core.saveNote(n.id, 'Plan', 'base\nfrom desktop\n');
    await a.peers!.sync.localChanged([n.id]);
    await b.peers!.sync.localChanged([n.id]);

    await until(() async => (await a.core.listNotes()).length == 2 && (await b.core.listNotes()).length == 2, what: 'both versions kept on both copies');
    await until(() => sameNotes(a, b), what: 'equal digests');
    for (final c in [a, b]) {
      final notes = await c.core.listNotes();
      final main = notes.firstWhere((x) => x.id == n.id);
      final copy = notes.firstWhere((x) => x.id != n.id);
      expect((await c.core.getNote(main.id)).body, 'base\nfrom desktop\n', reason: 'the later edit keeps the note on ${c.name}');
      expect(copy.title, 'Plan (conflict from laptop)');
      expect((await c.core.getNote(copy.id)).body, 'base\nfrom laptop\n');
      expect(c.reports.where((r) => r.contains('Both versions are kept')), hasLength(1), reason: '${c.name} told the person once');
    }
    await a.close();
    await b.close();
  }
}
