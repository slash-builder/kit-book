import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:app_context_kit_flutter/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/coordination/note_sync.dart';
import 'package:notepad/coordination/notes_peers.dart';
import 'package:notepad/logic/note.dart';
import 'package:notepad/logic/note_store.dart';
import 'package:notepad/ui/notepad_app.dart';
import 'package:notepad/ui/notepad_screen.dart';
import 'package:notepad/ui/notes_controller.dart';

/// The OTHER copy: a plain context with its own note files, running in real async next to the widget tree.
class _Other implements NoteHost {
  _Other(this.ctx, this.store);
  final AppContext ctx;
  final NoteStore store;
  late NotesPeers peers;
  final reports = <String>[];

  @override
  List<Note> get notes => store.load().notes;
  @override
  Note? note(String id) => notes.where((n) => n.id == id).firstOrNull;
  @override
  bool isDamaged(String id) => false;
  @override
  void flushNote(String id) {}
  @override
  void applyRemote(Note n) => store.save(n);
  @override
  void removeRemote(String id) => store.delete(id);

  Note create(String title, String body) {
    final n = store.create(title: title, body: body);
    peers.sync.localSaved(n);
    return n;
  }

  void edit(Note n, String body) {
    final e = n.copyWith(body: body, updatedAt: DateTime.now().toUtc().add(const Duration(seconds: 5)));
    store.save(e);
    peers.sync.localSaved(e);
  }
}

void main() {
  final manifestText = File('app.json').readAsStringSync();

  Future<void> settleUntil(WidgetTester t, bool Function() cond, {String? what}) async {
    for (var i = 0; i < 400 && !cond(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(cond(), isTrue, reason: 'the UI did not reach: ${what ?? 'the expected state'}');
  }

  Future<_Other> other(WidgetTester t, KitTestContext kit, FakePeerNetwork net) async {
    final ctx = await t.runAsync(() => AppContext.open(AppManifest.parse(manifestText),
        env: {'APP_CONTEXT_SCRATCH': '${kit.scratch.path}/other', 'APP_CONTEXT_MODE': 'mock', 'APP_CONTEXT_DEVICE': 'desktop', 'HOME': kit.scratch.path},
        announce: false));
    final o = _Other(ctx!, NoteStore('${ctx.dirs.data}/notes'));
    o.peers = NotesPeers.start(ctx, o, report: o.reports.add, network: net, heartbeat: const Duration(milliseconds: 200));
    return o;
  }

  Future<NotesController> boot(WidgetTester t, FakePeerNetwork net, {Directory? scratch}) async {
    final kit = await pumpKitApp(t,
        manifest: manifestText,
        env: {'APP_CONTEXT_DEVICE': 'laptop'},
        scratch: scratch,
        app: (_) => NotepadApp(autosaveDelay: const Duration(milliseconds: 100), network: net, syncHeartbeat: const Duration(milliseconds: 200)));
    _kit = kit;
    return t.widget<NotepadScreen>(find.byType(NotepadScreen)).controller;
  }

  testWidgets('the footer shows this copy and who is connected; a note made on the other copy appears and opens', (t) async {
    final net = FakePeerNetwork();
    final c = await boot(t, net);
    expect(find.text('Peers: 0'), findsOneWidget);
    expect(find.textContaining('This copy: laptop #'), findsOneWidget);

    final o = await other(t, _kit, net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty, what: 'Peers: 1');
    expect(find.textContaining('desktop #'), findsOneWidget);

    final n = o.create('From the desktop', 'hello over there');
    await settleUntil(t, () => c.note(n.id) != null, what: 'the note to arrive');
    await t.pump();
    expect(find.text('From the desktop'), findsWidgets);

    // an edit on the other copy replaces the text in the OPEN editor (the editor is rebuilt on a remote write)
    await t.tap(find.text('From the desktop').first);
    await t.pumpAndSettle();
    expect(find.text('hello over there'), findsWidgets);
    o.edit(n, 'hello over there, edited');
    await settleUntil(t, () => find.text('hello over there, edited').evaluate().isNotEmpty, what: 'the editor to show the remote edit');

    await t.runAsync(o.ctx.close);
    await settleUntil(t, () => find.text('Peers: 0').evaluate().isNotEmpty, what: 'Peers: 0 after the other copy left');
    await _kit.quit();
  });

  testWidgets('typing here while the other copy edits the same note: both versions are kept and the banner says so', (t) async {
    final net = FakePeerNetwork();
    final c = await boot(t, net);
    final o = await other(t, _kit, net);
    await settleUntil(t, () => find.text('Peers: 1').evaluate().isNotEmpty);

    await t.tap(find.text('Create a note'));
    await t.pump();
    final id = c.selectedId!;
    await settleUntil(t, () => o.note(id) != null, what: 'the new note on the other copy');

    // type here (NOT yet saved: the autosave pause has not passed) ...
    await t.enterText(find.byKey(const ValueKey('editor')), 'typed on the laptop');
    // ... and the other copy saves its own edit of the same note
    o.edit(o.note(id)!, 'typed on the desktop');
    await settleUntil(t, () => c.notes.length == 2, what: 'a conflict copy to appear');
    await t.pump();
    expect(find.textContaining('Both versions are kept'), findsOneWidget);
    final bodies = c.notes.map((n) => n.body).toSet();
    expect(bodies, {'typed on the laptop', 'typed on the desktop'}, reason: 'nothing was lost on either side');
    expect(c.notes.any((n) => n.title.contains('(conflict from ')), isTrue);

    await t.runAsync(o.ctx.close);
    await _kit.quit();
  });

  testWidgets('when peers cannot start the footer says why and the notes still work', (t) async {
    final dir = Directory.systemTemp.createTempSync('np-peers-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final blocker = File('${dir.path}/file')..writeAsStringSync('x');
    final kit = await pumpKitApp(t,
        manifest: manifestText,
        env: {'APP_CONTEXT_MODE': 'real', 'APP_CONTEXT_PEERS_DIR': blocker.path},
        app: (_) => const NotepadApp(autosaveDelay: Duration(milliseconds: 100)));
    await settleUntil(t, () => find.byKey(const ValueKey('peers-offline')).evaluate().isNotEmpty);
    expect(find.textContaining('Peers: off (peers unavailable'), findsOneWidget);
    await t.tap(find.text('Create a note'));
    await t.pump();
    expect(find.byKey(const ValueKey('editor')), findsOneWidget);
    await kit.quit();
  });
}

late KitTestContext _kit;
