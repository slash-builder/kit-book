import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

import 'support.dart';

Widget _page({
  String? subtitle,
  List<Widget> actions = const [],
  Widget? banner,
  Widget? footer,
}) =>
    PageScaffold(
      title: 'Notepad',
      subtitle: subtitle,
      actions: actions,
      banner: banner,
      footer: footer,
      body: const Center(child: Text('the body')),
    );

Widget _masterDetail(
        {bool showDetail = false, VoidCallback? onBack, Key? key}) =>
    PageScaffold.masterDetail(
      key: key,
      title: 'Notepad',
      showDetail: showDetail,
      onDetailBack: onBack,
      masterLabel: 'Notes',
      detailLabel: 'Editor',
      master: const Text('the list'),
      detail: const Text('the editor'),
    );

void main() {
  group('single pane', () {
    testWidgets('title, subtitle, actions, body', (tester) async {
      await pumpCandidate(
        tester,
        _page(subtitle: 'Three notes', actions: [
          IconButton(
              onPressed: () {},
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh))
        ]),
        inScaffold: false,
      );
      expect(find.text('Notepad'), findsOneWidget);
      expect(find.text('Three notes'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(find.text('the body'), findsOneWidget);
    });

    testWidgets(
        'one app bar convention: a real AppBar, title left-aligned, no colour overrides',
        (tester) async {
      await pumpCandidate(tester, _page(), inScaffold: false);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.centerTitle, isFalse);
      expect(bar.backgroundColor, isNull);
      expect(bar.foregroundColor, isNull);
    });

    testWidgets('banner is above the body and the footer below it',
        (tester) async {
      await pumpCandidate(
        tester,
        _page(
            banner: const StatusBanner(
                severity: Severity.warning, message: 'A banner'),
            footer: const Text('a footer')),
        inScaffold: false,
      );
      final banner = tester.getTopLeft(find.byType(StatusBanner)).dy;
      final body = tester.getTopLeft(find.text('the body')).dy;
      final footer = tester.getTopLeft(find.text('a footer')).dy;
      expect(banner, lessThan(body));
      expect(body, lessThan(footer));
      expect(tester.getBottomLeft(find.text('a footer')).dy,
          lessThanOrEqualTo(800));
    });

    testWidgets('slots take no space when absent', (tester) async {
      await pumpCandidate(tester, _page(), inScaffold: false);
      expect(find.byType(StatusBanner), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('footer colours come from the ambient theme', (tester) async {
      final theme = altTheme();
      await pumpCandidate(tester, _page(footer: const Text('f')),
          inScaffold: false, theme: theme);
      final box = tester.widget<DecoratedBox>(find
          .ancestor(of: find.text('f'), matching: find.byType(DecoratedBox))
          .first);
      expect((box.decoration as BoxDecoration).color,
          theme.colorScheme.surfaceContainer);
    });
  });

  group('master / detail', () {
    testWidgets('wide: both panes side by side, master on the left',
        (tester) async {
      await pumpCandidate(tester, _masterDetail(),
          inScaffold: false, size: const Size(1000, 700));
      expect(find.text('the list'), findsOneWidget);
      expect(find.text('the editor'), findsOneWidget);
      expect(tester.getTopLeft(find.text('the list')).dx,
          lessThan(tester.getTopLeft(find.text('the editor')).dx));
      expect(tester.getTopLeft(find.text('the editor')).dx,
          greaterThanOrEqualTo(kMasterPaneWidth));
    });

    testWidgets('the breakpoint is inclusive: 719 is narrow, 720 is wide',
        (tester) async {
      await pumpCandidate(tester, _masterDetail(),
          inScaffold: false, size: const Size(719, 700));
      expect(find.text('the editor'), findsNothing);
      await pumpCandidate(tester, _masterDetail(),
          inScaffold: false, size: const Size(720, 700));
      expect(find.text('the editor'), findsOneWidget);
    });

    testWidgets('narrow: master only, or detail only with a Back button',
        (tester) async {
      await pumpCandidate(tester, _masterDetail(),
          inScaffold: false, size: const Size(400, 700));
      expect(find.text('the list'), findsOneWidget);
      expect(find.text('the editor'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);

      var backs = 0;
      await pumpCandidate(
          tester, _masterDetail(showDetail: true, onBack: () => backs++),
          inScaffold: false, size: const Size(400, 700));
      expect(find.text('the list'), findsNothing);
      expect(find.text('the editor'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      expect(backs, 1);
    });

    testWidgets('wide ignores showDetail and shows no Back button',
        (tester) async {
      await pumpCandidate(
          tester, _masterDetail(showDetail: true, onBack: () {}),
          inScaffold: false, size: const Size(1000, 700));
      expect(find.text('the list'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('panes are labelled for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(tester, _masterDetail(),
          inScaffold: false, size: const Size(1000, 700));
      expect(find.bySemanticsLabel('Notes'), findsOneWidget);
      expect(find.bySemanticsLabel('Editor'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
        'keyboard focus order: app bar action, then the whole master pane, then the detail pane',
        (tester) async {
      final action = FocusNode(),
          list1 = FocusNode(),
          list2 = FocusNode(),
          edit = FocusNode();
      addTearDown(() {
        for (final n in [action, list1, list2, edit]) {
          n.dispose();
        }
      });
      await pumpCandidate(
        tester,
        PageScaffold.masterDetail(
          title: 'T',
          actions: [
            TextButton(
                focusNode: action, onPressed: () {}, child: const Text('act'))
          ],
          master: Column(children: [
            TextButton(
                focusNode: list1, onPressed: () {}, child: const Text('one')),
            TextButton(
                focusNode: list2, onPressed: () {}, child: const Text('two')),
          ]),
          detail: TextButton(
              focusNode: edit, onPressed: () {}, child: const Text('edit')),
        ),
        inScaffold: false,
        size: const Size(1000, 700),
      );
      action.requestFocus();
      await tester.pump();
      final order = <FocusNode>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add([list1, list2, edit].firstWhere((n) => n.hasPrimaryFocus));
      }
      expect(order, [list1, list2, edit]);
    });
  });

  group('accessibility', () {
    testWidgets('title is a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(tester, _page(), inScaffold: false);
      expect(tester.getSemantics(find.text('Notepad')).flagsCollection.isHeader,
          isTrue);
      handle.dispose();
    });

    testWidgets('Back and the tooltip-named actions meet the 48 dp guideline',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCandidate(
        tester,
        PageScaffold.masterDetail(
          title: 'T',
          showDetail: true,
          onDetailBack: () {},
          actions: [
            IconButton(
                onPressed: () {},
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh))
          ],
          master: const Text('m'),
          detail: const Text('d'),
        ),
        inScaffold: false,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets(
        'text scale 2.0 with subtitle, actions, banner and footer: no overflow, body still on screen',
        (tester) async {
      await pumpCandidate(
        tester,
        _page(
          subtitle: 'Three notes, one damaged',
          actions: [
            IconButton(
                onPressed: () {},
                tooltip: 'Smaller text',
                icon: const Icon(Icons.text_decrease)),
            IconButton(
                onPressed: () {},
                tooltip: 'Larger text',
                icon: const Icon(Icons.text_increase)),
          ],
          banner: const StatusBanner(
              severity: Severity.warning,
              message: 'A file could not be read and was left alone.'),
          footer: const Text('Saved'),
        ),
        inScaffold: false,
        textScale: 2.0,
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('the body'), findsOneWidget);
      final bodyRect = tester.getRect(find.text('the body'));
      expect(bodyRect.top, greaterThan(0));
      expect(bodyRect.bottom, lessThan(640));
    });

    testWidgets(
        'a huge banner and footer are capped and scroll; the body keeps its room',
        (tester) async {
      final long = List.filled(40, 'A very long notice line.').join(' ');
      await pumpCandidate(
        tester,
        _page(
            banner: StatusBanner(severity: Severity.error, message: long),
            footer: Text(long)),
        inScaffold: false,
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StatusBanner)).height,
          greaterThan(640 * 0.4)); // taller than its slot ...
      expect(tester.getSize(find.byType(SingleChildScrollView).first).height,
          lessThanOrEqualTo(640 * 0.4)); // ... which is capped
      expect(tester.getSize(find.text('the body')).height, greaterThan(0));
    });

    testWidgets(
        'with a subtitle the app bar grows with the text scale; without one it stays the standard height',
        (tester) async {
      await pumpCandidate(tester, _page(subtitle: 's'), inScaffold: false);
      final normal = tester.getSize(find.byType(AppBar)).height;
      await pumpCandidate(tester, _page(subtitle: 's'),
          inScaffold: false, textScale: 2.0);
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, greaterThan(normal));
      expect(tester.takeException(), isNull);
      await pumpCandidate(tester, _page(), inScaffold: false, textScale: 2.0);
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    });

    testWidgets('a long title ends in an ellipsis, not an overflow',
        (tester) async {
      await pumpCandidate(
        tester,
        const PageScaffold(
            title:
                'A very long page title that cannot possibly fit in one line of a narrow app bar',
            subtitle: 'and a subtitle',
            body: SizedBox()),
        inScaffold: false,
        textScale: 2.0,
        size: const Size(320, 480),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
