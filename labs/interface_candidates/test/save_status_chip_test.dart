import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

void main() {
  testWidgets('idle renders nothing and takes no space', (tester) async {
    await pumpCandidate(
        tester, const Row(children: [SaveStatusChip(status: SaveStatus.idle)]));
    expect(find.byType(Chip), findsNothing);
    expect(tester.getSize(find.byType(SaveStatusChip)), Size.zero);
  });

  for (final (status, word, icon) in [
    (SaveStatus.saving, 'Saving...', Icons.sync),
    (SaveStatus.saved, 'Saved', Icons.check),
    (SaveStatus.notSaved, 'Not saved', Icons.error_outline),
  ]) {
    testWidgets('$status: the word "$word" and its own icon', (tester) async {
      await pumpCandidate(tester, SaveStatusChip(status: status));
      expect(find.text(word), findsOneWidget);
      expect(find.byIcon(icon), findsOneWidget);
      expect(SaveStatusChip.labelFor(status), word);
    });
  }

  testWidgets('the three states differ by word and icon, not only colour',
      (tester) async {
    final words = {
      for (final s in SaveStatus.values) SaveStatusChip.labelFor(s)
    };
    expect(words.length,
        SaveStatus.values.length); // idle's empty string counts as the fourth
  });

  testWidgets('changing the status updates the chip in place', (tester) async {
    final status = ValueNotifier(SaveStatus.saving);
    await pumpCandidate(
        tester,
        ValueListenableBuilder(
            valueListenable: status,
            builder: (_, s, __) => SaveStatusChip(status: s)));
    expect(find.text('Saving...'), findsOneWidget);
    status.value = SaveStatus.saved;
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saving...'), findsNothing);
  });

  testWidgets('colours come from the ambient ColorScheme', (tester) async {
    final theme = altTheme();
    await pumpCandidate(
        tester, const SaveStatusChip(status: SaveStatus.notSaved),
        theme: theme);
    expect(tester.widget<Chip>(find.byType(Chip)).backgroundColor,
        theme.colorScheme.errorContainer);
    expect(tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
        theme.colorScheme.onErrorContainer);
    await pumpCandidate(tester, const SaveStatusChip(status: SaveStatus.saved),
        theme: theme);
    expect(tester.widget<Chip>(find.byType(Chip)).backgroundColor,
        theme.colorScheme.surfaceContainerHighest);
  });

  group('accessibility', () {
    testWidgets(
        'label is "Save status: <word>"; only a failure is a live region',
        (tester) async {
      final handle = tester.ensureSemantics();
      bool live(String label) => tester
          .getSemantics(find.bySemanticsLabel(label))
          .flagsCollection
          .isLiveRegion;

      await pumpCandidate(
          tester, const SaveStatusChip(status: SaveStatus.saving));
      expect(live('Save status: Saving...'), isFalse);
      await pumpCandidate(
          tester, const SaveStatusChip(status: SaveStatus.saved));
      expect(live('Save status: Saved'), isFalse);
      await pumpCandidate(
          tester, const SaveStatusChip(status: SaveStatus.notSaved));
      expect(live('Save status: Not saved'), isTrue);
      handle.dispose();
    });

    testWidgets(
        'the label is read once (chip text and icon are not separate nodes)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester, const SaveStatusChip(status: SaveStatus.saved));
      expect(find.bySemanticsLabel(RegExp('Saved')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('text contrast, every state, light and dark', (tester) async {
      final handle = tester.ensureSemantics();
      for (final theme in [altTheme(), altTheme(brightness: Brightness.dark)]) {
        await pumpCandidate(
            tester,
            Column(children: [
              for (final s in SaveStatus.values) SaveStatusChip(status: s)
            ]),
            theme: theme);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });

    testWidgets('text scale 2.0 in a narrow footer: no overflow',
        (tester) async {
      await pumpCandidate(
          tester,
          const Wrap(children: [
            SaveStatusChip(status: SaveStatus.notSaved),
            SaveStatusChip(status: SaveStatus.saving)
          ]),
          textScale: 2.0,
          size: const Size(240, 400));
      expect(tester.takeException(), isNull);
    });
  });
}
