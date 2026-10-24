import 'dart:io';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter/material.dart';

import '../coordination/notes_peers.dart';
import '../logic/note_store.dart';
import '../logic/settings.dart';
import 'notepad_screen.dart';
import 'notes_controller.dart';

class NotepadApp extends StatefulWidget {
  const NotepadApp({
    super.key,
    this.autosaveDelay = const Duration(milliseconds: 600),
    this.peers = true,
    this.network,
    this.syncHeartbeat = const Duration(seconds: 30),
    this.partBytes = 24 * 1024,
  });
  final Duration autosaveDelay;

  /// Start peer sync (the manifest must list "peers"). Tests that do not care turn it off.
  final bool peers;

  /// Tests: the shared in-memory network (mock mode); otherwise the Kit picks the provider.
  final FakePeerNetwork? network;
  final Duration syncHeartbeat;
  final int partBytes;

  @override
  State<NotepadApp> createState() => _NotepadAppState();
}

class _NotepadAppState extends State<NotepadApp> {
  NotesController? _controller;

  // The context comes from the scope, which an InheritedWidget cannot give in initState, so the controller is made on the
  // first didChangeDependencies instead.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final ctx = AppContextScope.of(context);
    _controller = NotesController(
      store: NoteStore('${ctx.dirs.data}${Platform.pathSeparator}notes'),
      settings: Settings(SessionSettings(ctx.config)),
      autosaveDelay: widget.autosaveDelay,
      // ctx.notes is the Kit's place for things the person should hear about. It does not notify, so the
      // controller calls notifyListeners itself after every report, and the banner reads the list again.
      report: (message) => ctx.notes.add(AppNote(NoteSeverity.warning, message)),
    );
    final controller = _controller!;
    if (widget.peers) {
      // Registered BEFORE the flush hook below: hooks run last-added-first, so on quit the last keystrokes are saved (and
      // announced) while the hub is still open.
      final p = NotesPeers.start(
        ctx,
        controller,
        network: widget.network,
        heartbeat: widget.syncHeartbeat,
        partBytes: widget.partBytes,
        report: (message) {
          ctx.notes.add(AppNote(NoteSeverity.warning, message));
          controller.changedExternally();
        },
      );
      controller.peers = p;
      controller.onNoteSaved = p.sync.localSaved;
      controller.onNoteDeleted = p.sync.localDeleted;
      p.sync.changes.listen((_) => controller.changedExternally());
    }
    ctx.onClose(controller.flush); // never lose the last few keystrokes on quit
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppContextScope.of(context).manifest.name,
        theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true),
        home: NotepadScreen(controller: _controller!),
      );
}
