import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter/material.dart';

import 'calculator_screen.dart';

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppContextScope.of(context).manifest.name,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const CalculatorScreen(),
      );
}
