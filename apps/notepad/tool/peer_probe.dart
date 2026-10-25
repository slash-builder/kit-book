// ignore_for_file: avoid_print
// HEADLESS PROBE, not the app: the notepad's own sync engine (NotesPeers -> NoteSyncHook -> NoteSync) over the REAL loopback
// provider, as a second copy next to the built macOS app. The display is off, so nothing can type into the real window; this
// process plays the person on the other copy. The notes controller is a Flutter ChangeNotifier and cannot run under `dart run`,
// so the NoteHost here is a small file-backed stand-in (the same shape as the test double).
//
//   dart run tool/peer_probe.dart --scratch DIR --peers DIR --device NAME [--for SECS] [--create SECS:TITLE:BYTES] [--edit SECS]
//
// Every line starts with the wall-clock time in epoch milliseconds so lines from several processes can be compared.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:notepad/coordination/note_sync.dart';
import 'package:notepad/coordination/notes_peers.dart';
import 'package:notepad/logic/note.dart';
import 'package:notepad/logic/note_store.dart';

void log(String m) => print('${DateTime.now().millisecondsSinceEpoch} $m');

class FileHost implements NoteHost {
  FileHost(this.store);
  final NoteStore store;
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

Future<void> main(List<String> args) async {
  String opt(String k, [String d = '']) {
    final i = args.indexOf('--$k');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : d;
  }

  final manifest = AppManifest.parse(File('app.json').readAsStringSync());
  final scratch = opt('scratch');
  final ctx = await AppContext.open(manifest,
      env: {'APP_CONTEXT_SCRATCH': scratch, 'APP_CONTEXT_MODE': 'real', 'APP_CONTEXT_PEERS_DIR': opt('peers'), 'APP_CONTEXT_DEVICE': opt('device', 'probe'), 'HOME': scratch},
      announce: false);
  final store = NoteStore('${ctx.dirs.data}/notes');
  final host = FileHost(store);
  final peers = NotesPeers.start(ctx, host, report: (m) => log('REPORT $m'), heartbeat: const Duration(seconds: 5));
  await peers.handle.started;
  final hub = peers.handle.hub!;
  log('START ${hub.id} notes=${host.notes.length} digest=${peers.sync.digest()}');
  hub.changes.listen((e) => log('PEER ${e.change.name} ${e.peer.id} hello=${jsonEncode(e.peer.hello)}'));

  // log every note that appears or changes in this copy's directory (how convergence is observed from outside)
  final seen = <String, String>{};
  Timer.periodic(const Duration(milliseconds: 10), (_) {
    for (final n in host.notes) {
      final sig = '${n.title}|${n.body.length}|${n.body.hashCode}';
      if (seen[n.id] != sig) {
        seen[n.id] = sig;
        log('NOTE ${n.id} "${n.title}" body=${n.body.length} chars');
      }
    }
  });

  final create = opt('create'); // SECS:TITLE:BYTES, after the first peer is ready
  if (create.isNotEmpty) {
    final p = create.split(':');
    unawaited(hub.changes.firstWhere((e) => e.change == PeerChange.ready).then((_) async {
      await Future<void>.delayed(Duration(seconds: int.parse(p[0])));
      final n = store.create(title: p[1], body: List.generate(int.parse(p[2]) ~/ 10 + 1, (i) => 'line ${i.toString().padLeft(4, '0')}\n').join().substring(0, int.parse(p[2])));
      log('COMMAND created ${n.id} "${n.title}" body=${n.body.length}');
      peers.sync.localSaved(n);
    }));
  }
  final edit = opt('edit'); // SECS: edit the newest note after the first peer is ready
  if (edit.isNotEmpty) {
    unawaited(hub.changes.firstWhere((e) => e.change == PeerChange.ready).then((_) async {
      await Future<void>.delayed(Duration(seconds: int.parse(edit)));
      final n = host.notes.first;
      final e = n.copyWith(body: '${n.body}\nedited on the probe', updatedAt: DateTime.now().toUtc());
      store.save(e);
      log('COMMAND edited ${e.id}');
      peers.sync.localSaved(e);
    }));
  }

  final timer = Timer.periodic(const Duration(seconds: 1), (_) => log('TICK peers=${hub.peers.map((p) => '${p.id}:${p.state.name}').toList()} dialFailures=${hub.stats.dialFailures} notes=${host.notes.length} digest=${peers.sync.digest()} pending=${peers.sync.pending}'));
  await Future<void>.delayed(Duration(seconds: int.parse(opt('for', '20'))));
  timer.cancel();
  log('END conflicts=${peers.sync.conflicts} pulled=${peers.sync.pulled} parts=${peers.sync.partsPulled} ignored=${peers.sync.ignored}');
  await ctx.close();
  exit(0);
}
