/// Glue between the app (note host, data directory, notice banner) and the sync engine. No Flutter.
library;

import 'package:app_context_kit/app_context_kit.dart';

import 'note_sync.dart';
import 'note_sync_hook.dart';

class NotesPeers {
  NotesPeers._(this.sync, this.handle);

  final NoteSync sync;
  /// What `ctx.startPeers` returned: the hub (null while peers are unavailable), why, and a change stream.
  final PeersHandle handle;

  /// Builds the engine over [host]'s notes, reads its sidecar (`<data>/sync.json`, outside the notes directory so the note
  /// loader never sees it) and starts a hub. The caller connects the host's save/delete callbacks to [NoteSync.localSaved] and
  /// [NoteSync.localDeleted]. [KitNotDeclared] is not swallowed.
  static NotesPeers start(
    AppContext ctx,
    NoteHost host, {
    required void Function(String message) report,
    FakePeerNetwork? network,
    Duration heartbeat = const Duration(seconds: 30),
    int partBytes = 24 * 1024,
    int maxNoteBytes = 2 * 1024 * 1024,
  }) {
    final sync = NoteSync(
      device: ctx.peerDevice,
      host: host,
      sidecar: ctx.dataJson('sync.json'),
      report: report,
      heartbeat: heartbeat,
      partBytes: partBytes,
      maxNoteBytes: maxNoteBytes,
    );
    sync.load();
    final handle = ctx.startPeers(NoteSyncHook(sync), network: network);
    ctx.onClose(sync.dispose);
    return NotesPeers._(sync, handle);
  }
}
