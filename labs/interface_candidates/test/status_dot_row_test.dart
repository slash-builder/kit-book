import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

Widget _row({
  StatusTone tone = StatusTone.ok,
  String status = 'Running',
  String title = 'Stopwatch',
  String? subtitle = 'pid 4242',
  Widget? trailing,
  List<CandidateAction> menu = const [],
  VoidCallback? onTap,
  bool selected = false,
  bool enabled = true,
}) =>
    StatusDotRow(
      tone: tone,
      statusLabel: status,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      menu: menu,
      onTap: onTap,
      selected: selected,
      enabled: enabled,
    );

void main() {
  testWidgets('shows title, the status word and the subtitle', (tester) async {
    await pumpCandidate(tester, _row());
    expect(find.text('Stopwatch'), findsOneWidget);
    expect(find.text('Running · pid 4242'), findsOneWidget);
  });

  testWidgets('no subtitle: just the status word', (tester) async {
    await pumpCandidate(tester, _row(subtitle: null));
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('each tone has its own dot SHAPE, not only its own colour',
      (tester) async {
    final shapes = <IconData>{};
    for (final tone in StatusTone.values) {
      await pumpCandidate(tester, _row(tone: tone));
      final icon = tester.widget<Icon>(
          find.byWidgetPredicate((w) => w is Icon && w.size == kDotSize));
      shapes.add(icon.icon!);
    }
    expect(shapes.length, StatusTone.values.length);
  });

  testWidgets('dot colours come from the ambient ColorScheme', (tester) async {
    final theme = altTheme();
    final expected = {
      StatusTone.ok: theme.colorScheme.primary,
      StatusTone.attention: theme.colorScheme.tertiary,
      StatusTone.problem: theme.colorScheme.error,
      StatusTone.idle: theme.colorScheme.outline,
    };
    for (final e in expected.entries) {
      await pumpCandidate(tester, _row(tone: e.key), theme: theme);
      final icon = tester.widget<Icon>(
          find.byWidgetPredicate((w) => w is Icon && w.size == kDotSize));
      expect(icon.color, e.value, reason: '${e.key}');
    }
  });

  testWidgets('a disabled row dims its dot with the theme disabled colour',
      (tester) async {
    final theme = altTheme();
    await pumpCandidate(tester, _row(enabled: false), theme: theme);
    final icon = tester.widget<Icon>(
        find.byWidgetPredicate((w) => w is Icon && w.size == kDotSize));
    expect(icon.color,
        Theme.of(tester.element(find.byType(ListTile))).disabledColor);
  });

  testWidgets('tap calls back; a disabled row does not', (tester) async {
    var taps = 0;
    await pumpCandidate(tester, _row(onTap: () => taps++));
    await tester.tap(find.text('Stopwatch'));
    expect(taps, 1);
    await pumpCandidate(tester, _row(onTap: () => taps++, enabled: false));
    await tester.tap(find.text('Stopwatch'));
    expect(taps, 1);
  });

  testWidgets('trailing widget is shown; without trailing or menu nothing is',
      (tester) async {
    await pumpCandidate(tester, _row(trailing: const Text('1h 02m')));
    expect(find.text('1h 02m'), findsOneWidget);
    await pumpCandidate(tester, _row());
    expect(find.byType(PopupMenuButton<int>), findsNothing);
  });

  testWidgets('overflow menu lists its entries and calls the chosen one',
      (tester) async {
    final chosen = <String>[];
    await pumpCandidate(
      tester,
      _row(menu: [
        CandidateAction(label: 'Rename', onPressed: () => chosen.add('rename')),
        CandidateAction(label: 'Delete', onPressed: () => chosen.add('delete')),
      ]),
    );
    await tester.tap(find.byTooltip('More actions for Stopwatch'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(chosen, ['delete']);
  });

  group('accessibility', () {
    testWidgets(
        'the row reads as title + status word + subtitle; the dot adds nothing',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(tester, _row(onTap: () {}, selected: true));
      final node = tester.getSemantics(find.byType(ListTile));
      expect(node.label, contains('Stopwatch'));
      expect(node.label, contains('Running'));
      expect(node.label, contains('pid 4242'));
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets(
        'the overflow button is named for its row and is at least 48 dp',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester,
          _row(
              onTap: () {},
              menu: [CandidateAction(label: 'Rename', onPressed: () {})]));
      expect(
          tester
              .getSemantics(find.byTooltip('More actions for Stopwatch'))
              .tooltip,
          'More actions for Stopwatch');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets(
        'text scale 2.0 with a long title, trailing and a menu: no overflow',
        (tester) async {
      await pumpCandidate(
        tester,
        _row(
            title: 'Quarterly render of the long hallway scene',
            subtitle: 'asked 3 times, hold render-3 (container.run.v1)',
            trailing: const Text('1h 02m'),
            menu: [CandidateAction(label: 'Cancel', onPressed: () {})]),
        textScale: 2.0,
        size: const Size(360, 700),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a very long trailing widget is capped instead of breaking the row (ListTile would assert)',
        (tester) async {
      await pumpCandidate(
        tester,
        _row(
            trailing: const Text(
                'a trailing text that is far too long to fit beside the title and the menu'),
            menu: [CandidateAction(label: 'Quit', onPressed: () {})]),
        textScale: 2.0,
        size: const Size(360, 700),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Stopwatch'), findsOneWidget);
    });

    testWidgets('a list of rows at 2.0 scrolls without overflow',
        (tester) async {
      await pumpCandidate(
        tester,
        ListView(children: [
          for (final t in StatusTone.values)
            _row(
                tone: t,
                status: t.name,
                title: 'Row ${t.name}',
                menu: [CandidateAction(label: 'Rename', onPressed: () {})]),
        ]),
        textScale: 2.0,
        size: const Size(360, 700),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
