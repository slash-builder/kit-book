import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';

import 'ui/calculator_app.dart';

Future<void> main() => AppContextKit.run(manifestAsset: 'app.json', app: (_) => const CalculatorApp());
