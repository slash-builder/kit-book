import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A theme that is NOT Flutter's default seed, so a test can prove a widget
/// takes its colours from the ambient theme rather than from constants.
ThemeData altTheme({Brightness brightness = Brightness.light}) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8E24AA), brightness: brightness),
    );

/// Pumps [child] inside a MaterialApp + Scaffold on a [size] logical-pixel
/// surface, at [textScale] (the accessibility contract is tested at 2.0).
///
/// Anything that overflows throws a FlutterError that fails the test, so a
/// plain `pumpCandidate(..., textScale: 2.0)` IS the overflow test.
Future<void> pumpCandidate(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
  Size size = const Size(400, 800),
  ThemeData? theme,
  bool inScaffold = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: inScaffold ? Scaffold(body: child) : child,
    ),
  );
}
