/// Glue between the app (the core, the notes host, the notice banner) and the sync engine. No Flutter.
library;

import 'dart:typed_data';

import 'package:application_kit/application_kit.dart';

import '../core/notes_core.dart';
import 'notes_sync.dart';
import 'notes_sync_hook.dart';

class NotesPeers {
  NotesPeers._(this.sync, this.handle);

  final NotesSync sync;

  /// What `ctx.startPeers` returned: the hub (null while peers are unavailable), why, and a change stream.
  final PeersHandle handle;

  /// Reads the core's digest, then starts a hub for the context. The transport is the Kit's (`ctx.startPeers`, a fake network
  /// in mock mode); the blocks, their verification and the conflict detection are the Rust core's. [KitNotDeclared] is not
  /// swallowed.
  static Future<NotesPeers> start(
    AppContext ctx,
    NotesCore core, {
    NotesHost host = const NoHost(),
    required void Function(String message) report,
    FakePeerNetwork? network,
    Duration heartbeat = const Duration(seconds: 30),
    int partBytes = 24 * 1024,
    Duration pullTimeout = const Duration(seconds: 10),
    Uint8List Function(Uint8List export)? serveTransform,
  }) async {
    final sync = NotesSync(
      core: core,
      device: ctx.peerDevice,
      host: host,
      report: report,
      heartbeat: heartbeat,
      partBytes: partBytes,
      pullTimeout: pullTimeout,
      serveTransform: serveTransform,
    );
    await sync.init();
    final handle = ctx.startPeers(NotesSyncHook(sync), network: network);
    ctx.onClose(sync.dispose);
    return NotesPeers._(sync, handle);
  }
}
