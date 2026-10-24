import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

/// A page with one button per call so tests can drive showToast from a real
/// BuildContext under a real ScaffoldMessenger.
Widget _host(void Function(BuildContext) onTap) => Builder(
      builder: (context) => Center(
          child: ElevatedButton(
              onPressed: () => onTap(context), child: const Text('go'))),
    );

void main() {
  testWidgets('shows the message with its severity word and icon',
      (tester) async {
    await pumpCandidate(tester,
        _host((c) => showToast(c, 'Could not save', severity: Severity.error)));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.text('Error: Could not save', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets(
      'a new toast replaces the old one at once: never two on screen, none queued',
      (tester) async {
    await pumpCandidate(
      tester,
      _host((c) {
        showToast(c, 'first');
        showToast(c, 'second');
        showToast(c, 'third', severity: Severity.success);
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Success: third', findRichText: true), findsOneWidget);
    expect(find.textContaining('first', findRichText: true), findsNothing);
    expect(find.textContaining('second', findRichText: true), findsNothing);

    // Let it time out: nothing from the replaced toasts comes back afterwards.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('replaces a toast shown earlier, across separate taps',
      (tester) async {
    var n = 0;
    await pumpCandidate(tester, _host((c) => showToast(c, 'message ${++n}')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Info: message 2', findRichText: true), findsOneWidget);
  });

  testWidgets('action fires its callback and dismisses the toast',
      (tester) async {
    var undone = 0;
    await pumpCandidate(
        tester,
        _host((c) => showToast(c, 'Note deleted',
            action:
                CandidateAction(label: 'Undo', onPressed: () => undone++))));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, 1);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'times out by itself (4 s plain, longer with an action) and has a close button',
      (tester) async {
    await pumpCandidate(tester, _host((c) => showToast(c, 'plain')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.pump(const Duration(
        seconds: 1)); // entrance animation completes, the 4 s timer starts
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'a toast with an action outlives a plain one, and its close button still works',
      (tester) async {
    await pumpCandidate(
        tester,
        _host((c) => showToast(c, 'm',
            action: CandidateAction(label: 'Undo', onPressed: () {}))));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(SnackBar),
        findsOneWidget); // a plain toast would be gone by now
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('colours come from the ambient ColorScheme', (tester) async {
    final theme = altTheme();
    await pumpCandidate(
        tester, _host((c) => showToast(c, 'm', severity: Severity.warning)),
        theme: theme);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        theme.colorScheme.tertiaryContainer);
    expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded)).color,
        theme.colorScheme.onTertiaryContainer);
  });

  group('accessibility', () {
    testWidgets(
        'announced: the toast is a live region labelled "Severity: message"',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester,
          _host(
              (c) => showToast(c, 'Could not save', severity: Severity.error)));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(
          milliseconds:
              750)); // semantics appear once the entrance animation is done
      final node =
          tester.getSemantics(find.bySemanticsLabel('Error: Could not save'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(find.bySemanticsLabel('Error: Could not save'), findsOneWidget);
      expect(
          tester.getSemantics(find.byTooltip('Close')).flagsCollection.isButton,
          isTrue);
      handle.dispose();
    });

    testWidgets('action and close meet 48 dp and have names', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester,
          _host((c) => showToast(c, 'm',
              action: CandidateAction(label: 'Undo', onPressed: () {}))));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('text contrast for every severity', (tester) async {
      final handle = tester.ensureSemantics();
      for (final s in Severity.values) {
        await pumpCandidate(tester,
            _host((c) => showToast(c, 'A message for $s', severity: s)));
        await tester.tap(find.text('go'));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });

    testWidgets('text scale 2.0 with a long message and an action: no overflow',
        (tester) async {
      await pumpCandidate(
        tester,
        _host((c) => showToast(c,
            'The note could not be written because the disk is full or read-only.',
            severity: Severity.error,
            action: CandidateAction(label: 'Retry', onPressed: () {}))),
        textScale: 2.0,
        size: const Size(320, 640),
      );
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}
