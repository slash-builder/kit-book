import 'package:application_kit_flutter/application_kit_flutter.dart';

import 'ui/notepad_app.dart';

Future<void> main() => AppKit.run(manifestAsset: 'app.json', app: (_) => const NotepadApp());
