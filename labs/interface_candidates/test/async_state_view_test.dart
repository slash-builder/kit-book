import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

Widget _view(ViewState<List<String>> state,
        {VoidCallback? onRetry, Widget? empty}) =>
    AsyncStateView<List<String>>(
      state: state,
      empty: empty,
      onRetry: onRetry,
      builder: (context, items) =>
          Column(children: [for (final i in items) Text(i)]),
    );

void main() {
  group('LoadingView', () {
    testWidgets('shows a spinner and its label', (tester) async {
      await pumpCandidate(tester, const LoadingView(label: 'Loading roster'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading roster'), findsOneWidget);
    });

    testWidgets('is announced as one live region with the label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(tester, const LoadingView());
      final node = tester.getSemantics(find.bySemanticsLabel('Loading'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('text scale 2.0: no overflow', (tester) async {
      await pumpCandidate(
          tester,
          const LoadingView(
              label: 'Loading the installed apps and their manifests'),
          textScale: 2.0,
          size: const Size(320, 480));
      expect(tester.takeException(), isNull);
    });
  });

  group('AsyncStateView', () {
    testWidgets('loading', (tester) async {
      await pumpCandidate(tester, _view(const ViewState.loading()));
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('empty: default and custom', (tester) async {
      await pumpCandidate(tester, _view(const ViewState.empty()));
      expect(find.text('Nothing here yet'), findsOneWidget);
      await pumpCandidate(
          tester,
          _view(const ViewState.empty(),
              empty: const EmptyState(title: 'No jobs')));
      expect(find.text('No jobs'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsNothing);
    });

    testWidgets('ready builds the content', (tester) async {
      await pumpCandidate(tester, _view(const ViewState.ready(['a', 'b'])));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets(
        'failure shows the message, not the detail, and Retry calls back',
        (tester) async {
      var retries = 0;
      await pumpCandidate(
          tester,
          _view(
              const ViewState.failure('Could not load jobs',
                  detail: 'SocketException: refused'),
              onRetry: () => retries++));
      expect(find.text('Could not load jobs'), findsOneWidget);
      expect(find.text('SocketException: refused'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      expect(retries, 1);
    });

    testWidgets('failure without onRetry has no Retry button', (tester) async {
      await pumpCandidate(tester, _view(const ViewState.failure('Gone')));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('changing state swaps the view', (tester) async {
      final state =
          ValueNotifier<ViewState<List<String>>>(const ViewState.loading());
      await pumpCandidate(
          tester,
          ValueListenableBuilder(
              valueListenable: state, builder: (_, s, __) => _view(s)));
      expect(find.byType(LoadingView), findsOneWidget);
      state.value = const ViewState.ready(['x']);
      await tester.pump();
      expect(find.byType(LoadingView), findsNothing);
      expect(find.text('x'), findsOneWidget);
    });

    test('fromList maps empty and non-empty lists', () {
      expect(ViewState.fromList(<int>[]), isA<ViewEmpty<List<int>>>());
      final ready = ViewState.fromList([1, 2]);
      expect(ready, isA<ViewReady<List<int>>>());
      expect((ready as ViewReady<List<int>>).value, [1, 2]);
    });
  });

  group('ErrorView', () {
    testWidgets('technical detail is collapsed by default and toggles',
        (tester) async {
      await pumpCandidate(
          tester,
          const ErrorView(
              message: 'Could not save', detail: 'EACCES: permission denied'));
      expect(find.text('EACCES: permission denied'), findsNothing);
      expect(find.text('Show technical details'), findsOneWidget);

      await tester.tap(find.text('Show technical details'));
      await tester.pump();
      expect(find.text('EACCES: permission denied'), findsOneWidget);
      expect(find.text('Hide technical details'), findsOneWidget);

      await tester.tap(find.text('Hide technical details'));
      await tester.pump();
      expect(find.text('EACCES: permission denied'), findsNothing);
    });

    testWidgets('no detail means no toggle', (tester) async {
      await pumpCandidate(tester, const ErrorView(message: 'Could not save'));
      expect(find.textContaining('technical details'), findsNothing);
    });

    testWidgets(
        'error is not conveyed by colour alone: icon, the word Error, and the message',
        (tester) async {
      await pumpCandidate(tester, const ErrorView(message: 'Could not save'));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('uses the ambient theme error colour', (tester) async {
      final theme = altTheme();
      await pumpCandidate(tester, const ErrorView(message: 'm'), theme: theme);
      expect(tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
          theme.colorScheme.error);
    });

    testWidgets(
        'semantics: announced as "Error: message"; the toggle is a labelled button whose label tracks its state',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester, const ErrorView(message: 'Could not save', detail: 'd'));
      final node =
          tester.getSemantics(find.bySemanticsLabel('Error: Could not save'));
      expect(node.flagsCollection.isLiveRegion, isTrue);

      final toggle = tester.getSemantics(find.text('Show technical details'));
      expect(toggle.label, 'Show technical details');
      expect(toggle.flagsCollection.isButton, isTrue);
      await tester.tap(find.text('Show technical details'));
      await tester.pump();
      expect(tester.getSemantics(find.text('Hide technical details')).label,
          'Hide technical details');
      handle.dispose();
    });

    testWidgets('Retry and the toggle meet the 48 dp guideline',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
          tester, ErrorView(message: 'm', detail: 'd', onRetry: () {}));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('text scale 2.0 with the long detail open: no overflow',
        (tester) async {
      await pumpCandidate(
        tester,
        ErrorView(
            message: 'The roster directory could not be read.',
            detail:
                'PathAccessException: Directory listing failed, path = "/path/to/Library/Application Support/roster" (OS Error: Operation not permitted, errno = 1)',
            onRetry: () {}),
        textScale: 2.0,
        size: const Size(320, 480),
      );
      await tester.tap(find.text('Show technical details'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
