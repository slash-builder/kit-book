import 'package:app_context_kit/app_context_kit.dart';
import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';

import '../coordination/notes_peers.dart';
import '../core/notes_core.dart';
import '../logic/settings.dart';
import 'notes_controller.dart';
import 'notes_screen.dart';

/// Opens the core for the context the app opened. In the real app this is `FrbNotesCore.open`; tests pass the fake.
typedef CoreFactory = Future<NotesCore> Function(AppContext ctx);

class NotesApp extends StatefulWidget {
  const NotesApp({
    super.key,
    required this.openCore,
    this.autosaveDelay = const Duration(milliseconds: 600),
    this.peers = true,
    this.network,
    this.syncHeartbeat = const Duration(seconds: 30),
    this.partBytes = 24 * 1024,
  });

  final CoreFactory openCore;
  final Duration autosaveDelay;

  /// Start peer sync (the manifest must list "peers"). Tests that do not care turn it off.
  final bool peers;

  /// Tests: the shared in-memory network (mock mode); otherwise the Kit picks the provider.
  final FakePeerNetwork? network;
  final Duration syncHeartbeat;
  final int partBytes;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  NotesController? _controller;
  Object? _error;

  // The context comes from the scope, which an InheritedWidget cannot give in initState, so everything is made on the first
  // didChangeDependencies instead.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || _error != null) return;
    _start(AppContextScope.of(context));
  }

  Future<void> _start(AppContext ctx) async {
    try {
      final core = await widget.openCore(ctx);
      // Hooks run last-registered first. The core is registered FIRST so it closes LAST: on quit the controller saves the last
      // keystrokes (and announces them), then the sync engine stops, then the native object is released.
      ctx.onClose(core.close);
      final controller = NotesController(
        core: core,
        settings: Settings(SessionSettings(ctx.config)),
        autosaveDelay: widget.autosaveDelay,
        // ctx.notes is the Kit's place for things the person should hear about. It does not notify, so the controller
        // redraws after every report, and the banner reads the list again.
        report: (message) => ctx.notes.add(AppNote(NoteSeverity.warning, message)),
      );
      if (widget.peers) {
        final p = await NotesPeers.start(
          ctx,
          core,
          host: controller,
          network: widget.network,
          heartbeat: widget.syncHeartbeat,
          partBytes: widget.partBytes,
          report: (message) {
            ctx.notes.add(AppNote(NoteSeverity.warning, message));
            controller.changedExternally();
          },
        );
        controller.peers = p;
        controller.onLocalChange = (ids) => p.sync.localChanged(ids);
        p.sync.changes.listen((_) => controller.changedExternally());
      }
      ctx.onClose(controller.flush); // registered last, so it runs first: the hub is still open while the last keystrokes go out
      await controller.load();
      await _seed(ctx, core, controller);
      if (!mounted) return;
      setState(() => _controller = controller);
    } on NotesCoreException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// `NOTES_RUST_SEED=3` (an environment variable the context was opened with) writes that many sample notes into an EMPTY store.
  /// It exists so a smoke test can start the built app headless and see blocks land under the data directory.
  Future<void> _seed(AppContext ctx, NotesCore core, NotesController controller) async {
    final n = int.tryParse(ctx.env['NOTES_RUST_SEED'] ?? '') ?? 0;
    if (n <= 0 || controller.notes.isNotEmpty) return;
    for (var i = 1; i <= n.clamp(1, 20); i++) {
      await core.createNote('Sample note $i', 'Sample note $i, written by NOTES_RUST_SEED.\n' * 40);
    }
    await controller.load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MaterialApp(
      title: AppContextScope.of(context).manifest.name,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: _error != null
          ? Scaffold(body: Center(child: SelectableText('The notes core could not start.\n\n$_error', key: const ValueKey('core-error'))))
          : controller == null
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : NotesScreen(controller: controller),
    );
  }
}
