import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

void main() {
  testWidgets('shows the icon, title and body; no button without an action',
      (tester) async {
    await pumpCandidate(
        tester,
        const EmptyState(
            icon: Icons.note_add_outlined,
            title: 'No notes yet',
            body: 'Notes you write show up here.'));
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Notes you write show up here.'), findsOneWidget);
    expect(find.byIcon(Icons.note_add_outlined), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('title only is enough', (tester) async {
    await pumpCandidate(tester, const EmptyState(title: 'Nothing here'));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('one primary action fires its callback', (tester) async {
    var taps = 0;
    await pumpCandidate(
      tester,
      EmptyState(
          title: 'No notes yet',
          action:
              CandidateAction(label: 'Create a note', onPressed: () => taps++)),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create a note'));
    expect(taps, 1);
  });

  testWidgets('a custom leading widget replaces the icon', (tester) async {
    await pumpCandidate(
        tester,
        const EmptyState(
            title: 'T',
            leading: SizedBox(key: ValueKey('art'), width: 40, height: 40)));
    expect(find.byKey(const ValueKey('art')), findsOneWidget);
  });

  test('icon and leading together are rejected', () {
    expect(
        () =>
            EmptyState(title: 'T', icon: Icons.add, leading: const SizedBox()),
        throwsAssertionError);
  });

  group('theming', () {
    testWidgets('colours come from the ambient theme', (tester) async {
      final theme = altTheme();
      await pumpCandidate(
          tester, const EmptyState(icon: Icons.inbox, title: 'T', body: 'B'),
          theme: theme);
      expect(tester.widget<Icon>(find.byIcon(Icons.inbox)).color,
          theme.colorScheme.onSurfaceVariant);
      final body = tester.widget<Text>(find.text('B'));
      expect(body.style?.color, theme.colorScheme.onSurfaceVariant);
      final resolved =
          Theme.of(tester.element(find.text('B'))).textTheme.bodyMedium;
      expect(body.style?.fontSize, resolved?.fontSize);
      expect(body.style?.fontSize, isNotNull);
    });
  });

  group('accessibility', () {
    testWidgets(
        'title is a heading, icon is hidden, action is a labelled button',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
        tester,
        EmptyState(
            icon: Icons.inbox,
            title: 'No notes yet',
            action: CandidateAction(label: 'Create a note', onPressed: () {})),
      );
      expect(
        tester.getSemantics(find.text('No notes yet')),
        matchesSemantics(
            label: 'No notes yet',
            isHeader: true,
            textDirection: TextDirection.ltr),
      );
      expect(
          tester
              .getSemantics(find.widgetWithText(FilledButton, 'Create a note')),
          matchesSemantics(
              label: 'Create a note',
              isButton: true,
              hasTapAction: true,
              hasFocusAction: true,
              isEnabled: true,
              hasEnabledState: true,
              isFocusable: true));
      // The decorative icon contributes no semantics node of its own.
      expect(find.bySemanticsLabel(RegExp('inbox', caseSensitive: false)),
          findsNothing);
      handle.dispose();
    });

    testWidgets(
        'action meets the 48 dp tap target and labelled-target guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester,
          EmptyState(
              title: 'T',
              body: 'B',
              action: CandidateAction(label: 'Go', onPressed: () {})));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets(
        'text scale 2.0 on a small screen: no overflow, and it scrolls to the action',
        (tester) async {
      await pumpCandidate(
        tester,
        EmptyState(
          icon: Icons.inbox,
          title: 'Nothing has been announced on this machine yet',
          body:
              'Start an app and it will appear here within a few seconds. This text is long on purpose.',
          action:
              CandidateAction(label: 'Refresh the list now', onPressed: () {}),
        ),
        textScale: 2.0,
        size: const Size(320, 480),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Refresh the list now'), 100);
      expect(find.text('Refresh the list now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme still meets text contrast', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(tester, const EmptyState(title: 'T', body: 'B'),
          theme: altTheme(brightness: Brightness.dark));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
