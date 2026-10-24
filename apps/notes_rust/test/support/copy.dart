/// A running "copy" of the app without a window: an Application Kit context in mock mode, a core opened on it (the fake or the
/// real Rust one, the caller's factory decides) and the sync engine on the Kit's fake peer network.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:application_kit/application_kit.dart';
import 'package:notes_rust/coordination/notes_peers.dart';
import 'package:notes_rust/core/notes_core.dart';

typedef CoreFactory = Future<NotesCore> Function(AppContext ctx);

/// The manifest text, read by the caller: `File('app.json')` in `flutter test`, the asset bundle in the app-hosted tests.
class Copy {
  Copy._(this.name, this.ctx, this.core, this.reports);

  final String name;
  final AppContext ctx;
  final NotesCore core;
  final List<String> reports;
  NotesPeers? peers;

  /// Opens a context named [name] under [root] (its own data, config, state and roster) in mock mode, then a core on it.
  /// Peers are NOT started; call [startPeers]. Two copies must have different [name]s: the sync refuses a peer with the same
  /// device id, because two copies with one device id share one data directory and are one replica.
  static Future<Copy> open(String manifestText, Directory root, String name, CoreFactory factory) async {
    final ctx = await AppContext.open(
      AppManifest.parse(manifestText),
      env: {'APPKIT_SCRATCH': '${root.path}/$name', 'APPKIT_MODE': 'mock', 'APPKIT_DEVICE': name, 'HOME': root.path},
    );
    final core = await factory(ctx);
    return Copy._(name, ctx, core, <String>[]);
  }

  Future<NotesPeers> startPeers(
    FakePeerNetwork net, {
    Uint8List Function(Uint8List export)? serveTransform,
    int partBytes = 24 * 1024,
    Duration heartbeat = Duration.zero,
  }) async {
    return peers = await NotesPeers.start(ctx, core,
        network: net, report: reports.add, serveTransform: serveTransform, partBytes: partBytes, heartbeat: heartbeat, pullTimeout: const Duration(seconds: 20));
  }

  /// A note typed on this copy, announced to the others like the controller does.
  Future<NoteView> write(String title, String body, {String? id}) async {
    final v = id == null ? await core.createNote(title, body) : await core.saveNote(id, title, body);
    await peers?.sync.localChanged([v.id]);
    return v;
  }

  Future<void> close() => ctx.close();
}

/// Polls until [cond] holds (real time: these tests run in plain `test`, not under fake async).
Future<void> until(Future<bool> Function() cond, {String? what, Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('timed out waiting for: ${what ?? 'the expected state'}');
}

Future<bool> sameNotes(Copy a, Copy b) async => await a.core.headsDigest() == await b.core.headsDigest();
