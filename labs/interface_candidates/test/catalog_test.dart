// The catalog shows every component in every state. These tests walk all of it
// (light and dark, 1x and 2x text, wide and narrow) and fail on any exception,
// which includes every RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../example/catalog.dart';

const _titles = [
  'EmptyState',
  'LoadingView / AsyncStateView',
  'PageScaffold',
  'StatusBanner',
  'showToast',
  'StatusDotRow',
  'confirmDialog / promptDialog',
  'SaveStatusChip',
  'relativeTime',
];

Future<void> _pump(WidgetTester tester, Size size,
    {bool dark = false, double scale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester
      .pumpWidget(CatalogApp(initialDark: dark, initialTextScale: scale));
  await tester.pump();
}

/// Opens [title] from the master list (wide: both panes are up; narrow: the tap switches to the detail).
Future<void> _open(WidgetTester tester, String title) async {
  final tile = find.widgetWithText(ListTile, title);
  // The first ListView is the master list (the banner slot is a SingleChildScrollView, also Scrollable).
  final master = find
      .descendant(
          of: find.byType(ListView).first, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(tile, 100, scrollable: master);
  await tester
      .ensureVisible(tile); // built is not the same as on screen, at 2x text
  await tester.pump();
  await tester.tap(tile);
  await tester.pump();
}

void main() {
  testWidgets('wide: master and detail side by side, every entry opens',
      (tester) async {
    await _pump(tester, const Size(1100, 900));
    expect(find.text('Interface candidates'), findsOneWidget);
    for (final title in _titles) {
      await _open(tester, title);
      expect(find.text(title), findsWidgets);
      expect(find.textContaining('Evidence:'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: title);
    }
  });

  for (final (name, dark, scale) in [
    ('light 1x', false, 1.0),
    ('dark 1x', true, 1.0),
    ('light 2x', false, 2.0),
    ('dark 2x', true, 2.0)
  ]) {
    testWidgets(
        'narrow, $name: every entry opens and goes Back without an exception',
        (tester) async {
      await _pump(tester, const Size(360, 720), dark: dark, scale: scale);
      for (final title in _titles) {
        await _open(tester, title);
        expect(find.byTooltip('Back'), findsOneWidget, reason: title);
        expect(tester.takeException(), isNull, reason: title);
        await tester.tap(find.byTooltip('Back'));
        await tester.pump();
        expect(find.byTooltip('Back'), findsNothing);
      }
    });
  }

  testWidgets('the theme and text-size buttons work', (tester) async {
    await _pump(tester, const Size(1100, 900));
    expect(
        Theme.of(tester.element(find.byType(Scaffold).first))
            .colorScheme
            .brightness,
        Brightness.light);
    await tester.tap(find.byTooltip('Switch to the dark theme'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // AnimatedTheme
    expect(
        Theme.of(tester.element(find.byType(Scaffold).first))
            .colorScheme
            .brightness,
        Brightness.dark);

    expect(
        MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first))
            .scale(10),
        10);
    await tester.tap(find.byTooltip('Use 2x text size'));
    await tester.pump();
    expect(
        MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first))
            .scale(10),
        20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the intro banner can be dismissed', (tester) async {
    await _pump(tester, const Size(1100, 900));
    expect(find.byType(StatusBanner), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss Info'));
    await tester.pump();
    expect(find.byType(StatusBanner), findsNothing);
  });

  testWidgets(
      'async demo steps through loading, empty, error, error + detail and content',
      (tester) async {
    await _pump(tester, const Size(1100, 900));
    await _open(tester, 'LoadingView / AsyncStateView');
    expect(find.byType(LoadingView), findsOneWidget);
    await tester.tap(find.text('Empty'));
    await tester.pump();
    expect(find.text('Nothing running'), findsOneWidget);
    await tester.tap(find.text('Error'));
    await tester.pump();
    expect(find.text('Could not load the roster.'), findsOneWidget);
    expect(find.textContaining('technical details'), findsNothing);
    await tester.tap(find.text('Error + detail'));
    await tester.pump();
    expect(find.text('Show technical details'), findsOneWidget);
    await tester.tap(find.text('Content'));
    await tester.pump();
    expect(find.text('Launcher'), findsOneWidget);
    // Retry from an error returns to loading.
    await tester.tap(find.text('Error'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets(
      'toasts replace each other; the burst of five shows only the last',
      (tester) async {
    await _pump(tester, const Size(1100, 900));
    await _open(tester, 'showToast');
    await tester.tap(find.text('burst of five'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Burst 5 of 5', findRichText: true),
        findsOneWidget);
    expect(
        find.textContaining('Burst 1 of 5', findRichText: true), findsNothing);
  });

  testWidgets('dialogs report their result into the page', (tester) async {
    await _pump(tester, const Size(1100, 900));
    await _open(tester, 'confirmDialog / promptDialog');
    await tester.tap(find.text('confirm, destructive'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(destructive) -> true'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Errands');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.text('promptDialog -> Errands'), findsOneWidget);
  });

  testWidgets('dot rows: selecting one moves the selection; the menu works',
      (tester) async {
    await _pump(tester, const Size(1100, 900));
    await _open(tester, 'StatusDotRow');
    await tester.tap(find.text('Notepad'));
    await tester.pump();
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Notepad'))
            .selected,
        isTrue);
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Stopwatch'))
            .selected,
        isFalse);
    await tester.tap(find.byTooltip('More actions for Stopwatch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Asked it to quit', findRichText: true),
        findsOneWidget);
  });

  testWidgets('relativeTime table renders the future and the past',
      (tester) async {
    await _pump(tester, const Size(1100, 900));
    await _open(tester, 'relativeTime');
    expect(find.text('just now'), findsWidgets);
    expect(find.text('in 5 minutes'), findsOneWidget);
    expect(find.text('in 3 days'), findsOneWidget);
    expect(find.text('1 year ago'), findsOneWidget);
  });
}
