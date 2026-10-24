import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

void main() {
  group('StatusBanner', () {
    for (final (severity, word, icon) in [
      (Severity.info, 'Info', Icons.info_outline),
      (Severity.success, 'Success', Icons.check_circle_outline),
      (Severity.warning, 'Warning', Icons.warning_amber_rounded),
      (Severity.error, 'Error', Icons.error_outline),
    ]) {
      testWidgets('$severity: visible word "$word", its own icon, the message',
          (tester) async {
        await pumpCandidate(tester,
            StatusBanner(severity: severity, message: 'Something happened'));
        expect(find.text('$word: Something happened', findRichText: true),
            findsOneWidget);
        expect(find.byIcon(icon), findsOneWidget);
      });
    }

    testWidgets(
        'the four severities are distinguishable without colour (distinct icon and word)',
        (tester) async {
      final icons = <IconData>{};
      final words = <String>{};
      await pumpCandidate(tester, const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      for (final s in Severity.values) {
        final style = SeverityStyle.of(context, s);
        icons.add(style.icon);
        words.add(style.label);
      }
      expect(icons.length, Severity.values.length);
      expect(words.length, Severity.values.length);
    });

    testWidgets(
        'colours come from the ambient ColorScheme, and follow a theme change',
        (tester) async {
      final theme = altTheme();
      await pumpCandidate(
          tester, const StatusBanner(severity: Severity.error, message: 'm'),
          theme: theme);
      final box = tester.widget<Container>(find.byType(Container).first);
      expect(box.color, theme.colorScheme.errorContainer);
      expect(tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
          theme.colorScheme.onErrorContainer);

      final dark = altTheme(brightness: Brightness.dark);
      await pumpCandidate(
          tester, const StatusBanner(severity: Severity.error, message: 'm'),
          theme: dark);
      await tester.pump(const Duration(milliseconds: 500)); // AnimatedTheme
      expect(tester.widget<Container>(find.byType(Container).first).color,
          dark.colorScheme.errorContainer);
    });

    testWidgets('action and dismiss call back; absent by default',
        (tester) async {
      await pumpCandidate(
          tester, const StatusBanner(severity: Severity.info, message: 'm'));
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);

      var acted = 0, dismissed = 0;
      await pumpCandidate(
        tester,
        StatusBanner(
          severity: Severity.warning,
          message: 'Holds from an earlier run',
          action: CandidateAction(label: 'Release', onPressed: () => acted++),
          onDismiss: () => dismissed++,
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Release'));
      await tester.tap(find.byTooltip('Dismiss Warning'));
      expect((acted, dismissed), (1, 1));
    });

    testWidgets(
        'label overrides the severity word (the companion says "Note" for info)',
        (tester) async {
      await pumpCandidate(
          tester,
          const StatusBanner(
              severity: Severity.info, message: 'Venue is off', label: 'Note'));
      expect(
          find.text('Note: Venue is off', findRichText: true), findsOneWidget);
    });

    group('accessibility', () {
      testWidgets(
          'semantic label is "Word: message"; warning and error are live regions, info is not',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCandidate(
          tester,
          const Column(children: [
            StatusBanner(severity: Severity.error, message: 'Closing failed'),
            StatusBanner(
                severity: Severity.warning, message: 'Settings damaged'),
            StatusBanner(severity: Severity.success, message: 'Saved'),
            StatusBanner(severity: Severity.info, message: 'Venue is off'),
          ]),
        );
        bool live(String label) => tester
            .getSemantics(find.bySemanticsLabel(label))
            .flagsCollection
            .isLiveRegion;
        expect(live('Error: Closing failed'), isTrue);
        expect(live('Warning: Settings damaged'), isTrue);
        expect(live('Success: Saved'), isTrue);
        expect(live('Info: Venue is off'), isFalse);
        handle.dispose();
      });

      testWidgets('the message is read once, not twice', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCandidate(
            tester,
            const StatusBanner(
                severity: Severity.error, message: 'Closing failed'));
        expect(find.bySemanticsLabel(RegExp('Closing failed')), findsOneWidget);
        handle.dispose();
      });

      testWidgets(
          'action and dismiss are buttons of at least 48 dp, with accessible names',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCandidate(
          tester,
          StatusBanner(
              severity: Severity.warning,
              message: 'm',
              action: CandidateAction(label: 'Fix it', onPressed: () {}),
              onDismiss: () {}),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.getSemantics(find.byTooltip('Dismiss Warning')).tooltip,
            'Dismiss Warning');
        expect(find.bySemanticsLabel('Fix it'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('text contrast holds for every severity, light and dark',
          (tester) async {
        final handle = tester.ensureSemantics();
        for (final theme in [
          altTheme(),
          altTheme(brightness: Brightness.dark),
          null
        ]) {
          await pumpCandidate(
            tester,
            Column(children: [
              for (final s in Severity.values)
                StatusBanner(
                    severity: s, message: 'A message for $s', onDismiss: () {})
            ]),
            theme: theme,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        handle.dispose();
      });

      testWidgets('text scale 2.0 with action and dismiss: no overflow',
          (tester) async {
        await pumpCandidate(
          tester,
          StatusBanner(
            severity: Severity.warning,
            message: 'Holds from a crashed run remain.',
            action: CandidateAction(label: 'Release', onPressed: () {}),
            onDismiss: () {},
          ),
          textScale: 2.0,
          size: const Size(320, 640),
        );
        // (flutter_test's Ahem font is 1 em wide per glyph, about twice as wide as real text, so this is a worst case.)
        expect(tester.takeException(), isNull);
      });
    });
  });
}
