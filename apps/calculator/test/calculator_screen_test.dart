import 'dart:io';

import 'package:app_context_kit_flutter/testing.dart';
import 'package:calculator/ui/calculator_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late KitTestContext kit;

  // announce: true so the roster test below sees the real presence file; everything else is the helper's defaults
  // (temp scratch dir, mock mode, opened under runAsync, removed when the test ends).
  Future<void> boot(WidgetTester t, {bool announce = false}) async {
    kit = await pumpKitApp(t,
        manifest: File('app.json').readAsStringSync(), app: (_) => const CalculatorApp(), announce: announce);
  }

  Future<void> tap(WidgetTester t, String id) async {
    await t.tap(find.byKey(ValueKey('key-$id')));
    await t.pump();
  }

  String display(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('display'))).data!;

  testWidgets('computes 0.1 + 0.2 as 0.3 with the on-screen keys', (t) async {
    await boot(t);
    for (final k in ['0', 'decimal', '1', 'add', '0', 'decimal', '2', 'equals']) {
      await tap(t, k);
    }
    expect(display(t), '0.3');
    await kit.close();
  });

  testWidgets('keyboard input works', (t) async {
    await boot(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit7, character: '7');
    await t.sendKeyEvent(LogicalKeyboardKey.numpadMultiply, character: '*');
    await t.sendKeyEvent(LogicalKeyboardKey.digit6, character: '6');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(display(t), '42');
    await kit.close();
  });

  testWidgets('division by zero shows Error and AC recovers', (t) async {
    await boot(t);
    for (final k in ['5', 'divide', '0', 'equals']) {
      await tap(t, k);
    }
    expect(display(t), 'Error');
    await tap(t, 'clear');
    expect(display(t), '0');
    await kit.close();
  });

  testWidgets('identity and mode come from the context', (t) async {
    await boot(t);
    expect(find.text('Calculator'), findsWidgets); // manifest.name in the app bar
    expect(find.byKey(const ValueKey('mode-chip')), findsOneWidget);
    expect(find.text('mock + scratch'), findsOneWidget);
    await kit.close();
  });

  testWidgets('it announces itself in the roster while open and withdraws on close', (t) async {
    await boot(t, announce: true);
    expect(kit.ctx.roster.running().map((e) => e.id), ['com.slashbuilder.demo.calc']);
    await kit.close();
    expect(kit.ctx.roster.running(), isEmpty);
  });

  testWidgets('all of the app writes stays inside the scratch directory', (t) async {
    await boot(t);
    await kit.close();
    for (final d in kit.ctx.dirs.all) {
      expect(d.startsWith(kit.scratch.path), isTrue, reason: d);
    }
    expect(kit.ctx.roster.dir.startsWith(kit.scratch.path), isTrue);
  });
}
