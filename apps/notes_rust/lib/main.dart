import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter/material.dart';

import 'core/frb_notes_core.dart';
import 'src/rust/frb_generated.dart';
import 'ui/notes_app.dart';

/// `AppKit.run` opens the Application Kit context ONCE (the roster entry, the instance id, `config.json` are this side's).
/// The Rust core is then opened by handing it that context's snapshot: it adopts the context and opens none of its own.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RustLib.init();
  } on Object catch (e) {
    runApp(_NativeMissing(error: e));
    return;
  }
  await AppKit.run(manifestAsset: 'app.json', app: (_) => NotesApp(openCore: FrbNotesCore.open));
}

/// Shown when the native library cannot be loaded.
class _NativeMissing extends StatelessWidget {
  const _NativeMissing({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('The Rust core could not be loaded.\n\n$error\n\nBuild it with `make app APP=notes_rust`.'),
          ),
        ),
      );
}
