import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

/// A STATELESS host: promptDialog must not need the caller to own anything.
class _Host extends StatelessWidget {
  const _Host(this.onOpen);
  final Future<void> Function(BuildContext) onOpen;

  @override
  Widget build(BuildContext context) => Center(
      child: ElevatedButton(
          onPressed: () => onOpen(context), child: const Text('open')));
}

void main() {
  group('confirmDialog', () {
    Future<bool?> run(WidgetTester tester,
        {bool destructive = false,
        String confirm = 'Delete',
        ThemeData? theme,
        double textScale = 1.0,
        Size? size}) async {
      bool? result;
      await pumpCandidate(
        tester,
        _Host((c) async => result = await confirmDialog(c,
            title: 'Delete "Groceries"?',
            message: 'This cannot be undone.',
            confirmLabel: confirm,
            destructive: destructive)),
        theme: theme,
        textScale: textScale,
        size: size ?? const Size(400, 800),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('shows title, message and both buttons', (tester) async {
      await run(tester);
      expect(find.text('Delete "Groceries"?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
    });

    testWidgets('confirm is true', (tester) async {
      bool? result;
      await pumpCandidate(
          tester,
          _Host((c) async => result = await confirmDialog(c,
              title: 'T', message: 'M', confirmLabel: 'Yes')));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancel and tapping outside are false', (tester) async {
      bool? result;
      await pumpCandidate(
          tester,
          _Host((c) async =>
              result = await confirmDialog(c, title: 'T', message: 'M')));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      result = null;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets(
        'Enter confirms a normal dialog but CANCELS a destructive one (Cancel has the initial focus)',
        (tester) async {
      bool? result;
      await pumpCandidate(
          tester,
          _Host((c) async => result = await confirmDialog(c,
              title: 'T', message: 'M', confirmLabel: 'Go')));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isTrue);

      result = null;
      await pumpCandidate(
          tester,
          _Host((c) async => result = await confirmDialog(c,
              title: 'T',
              message: 'M',
              confirmLabel: 'Delete',
              destructive: true)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets(
        'destructive uses the ambient theme error colours; the label still says what it does',
        (tester) async {
      final theme = altTheme();
      await run(tester, destructive: true, theme: theme);
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));
      final style = button.style!;
      expect(style.backgroundColor!.resolve({}), theme.colorScheme.error);
      expect(style.foregroundColor!.resolve({}), theme.colorScheme.onError);
    });

    testWidgets(
        'accessibility: buttons named and at least 48 dp; contrast; text scale 2.0 without overflow',
        (tester) async {
      final handle = tester.ensureSemantics();
      await run(tester, destructive: true);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      handle.dispose();

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await run(tester,
          destructive: true, textScale: 2.0, size: const Size(320, 480));
      expect(tester.takeException(), isNull);
    });
  });

  group('promptDialog', () {
    Future<void> open(WidgetTester tester, void Function(String?) onResult,
        {String initial = 'Groceries',
        String? Function(String)? validator,
        double textScale = 1.0,
        Size size = const Size(400, 800)}) async {
      await pumpCandidate(
        tester,
        _Host((c) async => onResult(await promptDialog(c,
            title: 'Rename note',
            confirmLabel: 'Rename',
            initial: initial,
            fieldLabel: 'Name',
            validator: validator))),
        textScale: textScale,
        size: size,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the field with its initial text SELECTED, focused',
        (tester) async {
      await open(tester, (_) {});
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Groceries');
      expect(field.controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9));
      expect(field.autofocus, isTrue);
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('confirm returns the typed text', (tester) async {
      String? result = 'unset';
      await open(tester, (r) => result = r);
      await tester.enterText(find.byType(TextField), 'Errands');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(result, 'Errands');
    });

    testWidgets('Enter in the field confirms', (tester) async {
      String? result = 'unset';
      await open(tester, (r) => result = r);
      await tester.enterText(find.byType(TextField), 'Via enter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, 'Via enter');
    });

    testWidgets('cancel and tapping outside return null', (tester) async {
      String? result = 'unset';
      await open(tester, (r) => result = r);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);

      result = 'unset';
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets(
        'the dialog owns its controller: closing it (with its exit animation) throws nothing, from a stateless caller',
        (tester) async {
      String? result = 'unset';
      await open(tester, (r) => result = r);
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester
          .pump(); // first frame of the closing animation: the field is still on screen
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result, 'x');
    });

    testWidgets(
        'validator blocks confirm, shows the message, re-validates on edit, then lets it through',
        (tester) async {
      String? result = 'unset';
      String? rule(String t) => t.trim().isEmpty ? 'A name is required' : null;
      await open(tester, (r) => result = r, validator: rule);

      await tester.enterText(find.byType(TextField), '   ');
      expect(find.text('A name is required'),
          findsNothing); // not before the first attempt
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('A name is required'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(result, 'unset');

      await tester.enterText(find.byType(TextField), 'ok');
      await tester.pump();
      expect(find.text('A name is required'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(result, 'ok');
    });

    testWidgets(
        'accessibility: field is labelled, error is exposed, buttons are 48 dp, contrast',
        (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, (_) {},
          validator: (t) => t == 'Groceries' ? 'Pick a new name' : null);
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      final field = tester.getSemantics(find.bySemanticsLabel(RegExp('Name')));
      expect(field.label, contains('Name'));
      // The error is exposed as a node under the field (Flutter's TextField decides how it is announced).
      expect(find.bySemanticsLabel('Pick a new name'), findsOneWidget);
      expect(field.flagsCollection.isTextField, isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets(
        'text scale 2.0 on a small screen, with the keyboard-sized viewport: no overflow',
        (tester) async {
      await open(tester, (_) {},
          textScale: 2.0,
          size: const Size(320, 480),
          validator: (_) =>
              'An error message that wraps onto a couple of lines');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
