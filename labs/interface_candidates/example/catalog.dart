// A catalog of every candidate component in every state, for visual review.
//
//   flutter run -t example/main.dart     (see README for the one-time runner step)
//
// The catalog is built from the candidates themselves: a PageScaffold in
// master/detail mode, a StatusBanner, a SaveStatusChip in the footer. The two
// app bar buttons switch light/dark and 1x/2x text scale, so the accessibility
// contract can be reviewed by eye as well as by test.

import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

/// The catalog app. [initialDark] and [initialTextScale] exist for tests.
class CatalogApp extends StatefulWidget {
  const CatalogApp(
      {super.key, this.initialDark = false, this.initialTextScale = 1.0});

  final bool initialDark;
  final double initialTextScale;

  @override
  State<CatalogApp> createState() => _CatalogAppState();
}

class _CatalogAppState extends State<CatalogApp> {
  late bool _dark = widget.initialDark;
  late double _scale = widget.initialTextScale;

  // Any seed will do; the point is that nothing in the components names a colour.
  ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Interface candidates',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(_scale)),
        child: child!,
      ),
      home: CatalogPage(
        dark: _dark,
        bigText: _scale > 1,
        onToggleDark: () => setState(() => _dark = !_dark),
        onToggleText: () => setState(() => _scale = _scale > 1 ? 1.0 : 2.0),
      ),
    );
  }
}

class _Entry {
  const _Entry(this.title, this.evidence, this.build);
  final String title;
  final String evidence;
  final Widget Function(BuildContext context) build;
}

final _entries = <_Entry>[
  _Entry('EmptyState', 'notepad, launcher, render-queue; the larger app x5',
      (_) => const _EmptyStateDemo()),
  _Entry('LoadingView / AsyncStateView', 'launcher; the larger app x15 hand-rolled',
      (_) => const _AsyncDemo()),
  _Entry('PageScaffold', 'all 6 apps; the larger app x2 conventions',
      (_) => const _ScaffoldDemo()),
  _Entry('StatusBanner', '4 apps hand-built, 5 wanted one',
      (_) => const _BannerDemo()),
  _Entry('showToast', '0 apps built one; 4 wanted one; the larger app x3',
      (_) => const _ToastDemo()),
  _Entry('StatusDotRow', 'launcher only (thin)', (_) => const _DotRowDemo()),
  _Entry('confirmDialog / promptDialog', 'notepad only',
      (_) => const _DialogDemo()),
  _Entry('SaveStatusChip', 'notepad only', (_) => const _SaveChipDemo()),
  _Entry('relativeTime', 'launcher wanted one (thin)',
      (_) => const _RelativeTimeDemo()),
];

/// The catalog page: a master/detail [PageScaffold] over [_entries].
class CatalogPage extends StatefulWidget {
  const CatalogPage(
      {super.key,
      required this.dark,
      required this.bigText,
      required this.onToggleDark,
      required this.onToggleText});

  final bool dark;
  final bool bigText;
  final VoidCallback onToggleDark;
  final VoidCallback onToggleText;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  var _selected = 0;
  var _showDetail = false;
  var _bannerVisible = true;

  @override
  Widget build(BuildContext context) {
    final entry = _entries[_selected];
    return PageScaffold.masterDetail(
      title: 'Interface candidates',
      subtitle: '${_entries.length} candidates; not the Interface Kit',
      masterLabel: 'Components',
      detailLabel: entry.title,
      showDetail: _showDetail,
      onDetailBack: () => setState(() => _showDetail = false),
      actions: [
        IconButton(
          tooltip: widget.dark
              ? 'Switch to the light theme'
              : 'Switch to the dark theme',
          icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: widget.onToggleDark,
        ),
        IconButton(
          tooltip: widget.bigText ? 'Use normal text size' : 'Use 2x text size',
          icon:
              Icon(widget.bigText ? Icons.text_decrease : Icons.text_increase),
          onPressed: widget.onToggleText,
        ),
      ],
      banner: _bannerVisible
          ? StatusBanner(
              severity: Severity.info,
              message:
                  'Plain Material; every colour and text style comes from the theme.',
              onDismiss: () => setState(() => _bannerVisible = false),
            )
          : null,
      footer: const Padding(
        padding: EdgeInsets.symmetric(horizontal: kGapL, vertical: kGapS),
        child: Align(
            alignment: Alignment.centerLeft,
            child: SaveStatusChip(status: SaveStatus.saved)),
      ),
      master: ListView(
        children: [
          for (var i = 0; i < _entries.length; i++)
            ListTile(
              selected: i == _selected,
              title: Text(_entries[i].title),
              subtitle: Text(_entries[i].evidence),
              onTap: () => setState(() {
                _selected = i;
                _showDetail = true;
              }),
            ),
        ],
      ),
      detail: ListView(
        key: ValueKey(entry.title),
        padding: const EdgeInsets.all(kGapL),
        children: [
          Semantics(
              header: true,
              child: Text(entry.title,
                  style: Theme.of(context).textTheme.headlineSmall)),
          const SizedBox(height: kGapXs),
          Text('Evidence: ${entry.evidence}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: kGapL),
          entry.build(context),
        ],
      ),
    );
  }
}

/// A labelled block inside a demo.
class _Block extends StatelessWidget {
  const _Block(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: kGapXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
                header: true,
                child:
                    Text(label, style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: kGapS),
            child,
          ],
        ),
      );
}

/// A bordered, fixed-height frame for components that fill their parent.
class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.height = 280});
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: SizedBox(height: height, child: child),
      );
}

class _EmptyStateDemo extends StatelessWidget {
  const _EmptyStateDemo();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Block(
            'Icon, title, body and one primary action',
            _Frame(
              child: EmptyState(
                icon: Icons.note_add_outlined,
                title: 'No notes yet',
                body: 'Notes you write show up here.',
                action: CandidateAction(
                    label: 'Create a note',
                    onPressed: () => showToast(context, 'Created a note',
                        severity: Severity.success)),
              ),
            ),
          ),
          const _Block(
              'Title only',
              _Frame(
                  height: 140,
                  child: EmptyState(title: 'Nothing announced yet'))),
          const _Block(
            'Custom leading widget',
            _Frame(
                child: EmptyState(
                    leading: CircleAvatar(
                        radius: kMinTapTarget / 2,
                        child: Icon(Icons.hub_outlined)),
                    title: 'No peers found',
                    body: 'Start the app on another device.')),
          ),
        ],
      );
}

class _AsyncDemo extends StatefulWidget {
  const _AsyncDemo();

  @override
  State<_AsyncDemo> createState() => _AsyncDemoState();
}

class _AsyncDemoState extends State<_AsyncDemo> {
  var _which = 0;

  static const _labels = [
    'Loading',
    'Empty',
    'Error',
    'Error + detail',
    'Content'
  ];

  ViewState<List<String>> get _state => switch (_which) {
        0 => const ViewState.loading(),
        1 => const ViewState.empty(),
        2 => const ViewState.failure('Could not load the roster.'),
        3 => const ViewState.failure('Could not load the roster.',
            detail:
                'PathAccessException: Directory listing failed, path = "/roster" (OS Error: Operation not permitted, errno = 1)'),
        _ => const ViewState.ready(['Stopwatch', 'Notepad', 'Launcher']),
      };

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: kGapS, runSpacing: kGapS, children: [
            for (var i = 0; i < _labels.length; i++)
              ChoiceChip(
                  label: Text(_labels[i]),
                  selected: i == _which,
                  onSelected: (_) => setState(() => _which = i)),
          ]),
          const SizedBox(height: kGapL),
          _Frame(
            child: AsyncStateView<List<String>>(
              state: _state,
              empty: const EmptyState(
                  icon: Icons.inbox_outlined, title: 'Nothing running'),
              onRetry: () => setState(() => _which = 0),
              builder: (context, items) => ListView(
                  children: [for (final i in items) ListTile(title: Text(i))]),
            ),
          ),
        ],
      );
}

class _ScaffoldDemo extends StatelessWidget {
  const _ScaffoldDemo();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Block(
            'Title, subtitle, actions, banner slot, footer slot',
            _Frame(
              height: 360,
              child: PageScaffold(
                title: 'Render queue',
                subtitle: '3 running, peak 3',
                actions: [
                  IconButton(
                      tooltip: 'Refresh now',
                      icon: const Icon(Icons.refresh),
                      onPressed: () {})
                ],
                banner: const StatusBanner(
                    severity: Severity.warning,
                    message: 'Venue is not answering; running locally.'),
                footer: const Padding(
                    padding: EdgeInsets.all(kGapS),
                    child: Text('Footer / status slot')),
                body: const Center(child: Text('Body')),
              ),
            ),
          ),
          _Block(
            'Master / detail (both panes here; below the breakpoint only one shows, with a Back button)',
            _Frame(
              height: 300,
              child: PageScaffold.masterDetail(
                title: 'Notepad',
                wideBreakpoint: 360,
                masterWidth: 140,
                master: ListView(children: const [
                  ListTile(title: Text('Groceries'), selected: true),
                  ListTile(title: Text('Errands'))
                ]),
                detail: const Padding(
                    padding: EdgeInsets.all(kGapL),
                    child: Text('The editor pane')),
              ),
            ),
          ),
        ],
      );
}

class _BannerDemo extends StatefulWidget {
  const _BannerDemo();

  @override
  State<_BannerDemo> createState() => _BannerDemoState();
}

class _BannerDemoState extends State<_BannerDemo> {
  var _dismissed = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Block(
              'Four severities',
              Column(children: [
                StatusBanner(
                    severity: Severity.info,
                    message: 'Venue is off for this app.'),
                SizedBox(height: kGapS),
                StatusBanner(
                    severity: Severity.success, message: 'Imported 12 notes.'),
                SizedBox(height: kGapS),
                StatusBanner(
                    severity: Severity.warning,
                    message: 'Settings file is damaged; defaults are in use.'),
                SizedBox(height: kGapS),
                StatusBanner(
                    severity: Severity.error,
                    message: 'Closing failed: disk full.'),
              ])),
          _Block(
            'With an action',
            StatusBanner(
              severity: Severity.warning,
              message:
                  '3 holds from an earlier run still count against your quota.',
              action: CandidateAction(
                  label: 'Release',
                  onPressed: () => showToast(context, 'Released 3 holds',
                      severity: Severity.success)),
            ),
          ),
          _Block(
            'Dismissible (controlled: the caller stops building it)',
            _dismissed
                ? TextButton(
                    onPressed: () => setState(() => _dismissed = false),
                    child: const Text('Show the banner again'))
                : StatusBanner(
                    severity: Severity.error,
                    message: 'Could not save "Groceries".',
                    onDismiss: () => setState(() => _dismissed = true)),
          ),
          const _Block(
              'Custom severity word',
              StatusBanner(
                  severity: Severity.info,
                  label: 'Note',
                  message: 'The companion says "Note" for info.')),
        ],
      );
}

class _ToastDemo extends StatelessWidget {
  const _ToastDemo();

  @override
  Widget build(BuildContext context) => _Block(
        'One toast at a time: a new one replaces the old one',
        Wrap(spacing: kGapS, runSpacing: kGapS, children: [
          for (final s in Severity.values)
            OutlinedButton(
                onPressed: () =>
                    showToast(context, 'A ${s.name} toast', severity: s),
                child: Text(s.name)),
          OutlinedButton(
            onPressed: () => showToast(context, 'Note deleted',
                action: CandidateAction(
                    label: 'Undo',
                    onPressed: () => showToast(context, 'Restored',
                        severity: Severity.success))),
            child: const Text('with an action'),
          ),
          OutlinedButton(
            onPressed: () {
              for (var i = 1; i <= 5; i++) {
                showToast(context, 'Burst $i of 5 (only the last shows)');
              }
            },
            child: const Text('burst of five'),
          ),
        ]),
      );
}

class _DotRowDemo extends StatefulWidget {
  const _DotRowDemo();

  @override
  State<_DotRowDemo> createState() => _DotRowDemoState();
}

class _DotRowDemoState extends State<_DotRowDemo> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final menu = [
      CandidateAction(
          label: 'Quit',
          onPressed: () => showToast(context, 'Asked it to quit')),
      CandidateAction(
          label: 'Copy id', onPressed: () => showToast(context, 'Copied')),
    ];
    return _Block(
      'Four tones, each with its own dot shape and a visible status word; trailing slot; overflow menu; selected; disabled',
      Column(children: [
        StatusDotRow(
            tone: StatusTone.ok,
            statusLabel: 'Running',
            title: 'Stopwatch',
            subtitle: 'pid 4242',
            trailing: const Text('1h 02m'),
            menu: menu,
            selected: _selected == 0,
            onTap: () => setState(() => _selected = 0)),
        StatusDotRow(
            tone: StatusTone.attention,
            statusLabel: 'Stale',
            title: 'Notepad',
            subtitle: 'no heartbeat for 20 s',
            menu: menu,
            selected: _selected == 1,
            onTap: () => setState(() => _selected = 1)),
        StatusDotRow(
            tone: StatusTone.problem,
            statusLabel: 'Failed',
            title: 'render-3',
            subtitle: 'refused by Venue',
            menu: menu,
            selected: _selected == 2,
            onTap: () => setState(() => _selected = 2)),
        const StatusDotRow(
            tone: StatusTone.idle,
            statusLabel: 'Not running',
            title: 'Minesweeper'),
        const StatusDotRow(
            tone: StatusTone.ok,
            statusLabel: 'Running',
            title: 'Disabled row',
            enabled: false),
      ]),
    );
  }
}

class _DialogDemo extends StatefulWidget {
  const _DialogDemo();

  @override
  State<_DialogDemo> createState() => _DialogDemoState();
}

class _DialogDemoState extends State<_DialogDemo> {
  var _result = 'No dialog shown yet.';

  void _say(String text) => setState(() => _result = text);

  @override
  Widget build(BuildContext context) => _Block(
        'Helpers: no StatefulWidget needed to own the prompt controller',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: kGapS, runSpacing: kGapS, children: [
            OutlinedButton(
              onPressed: () async => _say(
                  'confirmDialog -> ${await confirmDialog(context, title: 'Save changes?', message: 'The note has unsaved changes.', confirmLabel: 'Save')}'),
              child: const Text('confirm'),
            ),
            OutlinedButton(
              onPressed: () async => _say(
                  'confirmDialog (destructive) -> ${await confirmDialog(context, title: 'Delete "Groceries"?', message: 'This cannot be undone.', confirmLabel: 'Delete', destructive: true)}'),
              child: const Text('confirm, destructive'),
            ),
            OutlinedButton(
              onPressed: () async => _say(
                  'promptDialog -> ${await promptDialog(context, title: 'Rename note', confirmLabel: 'Rename', initial: 'Groceries', fieldLabel: 'Name')}'),
              child: const Text('prompt'),
            ),
            OutlinedButton(
              onPressed: () async => _say(
                'promptDialog (validated) -> ${await promptDialog(context, title: 'Rename note', confirmLabel: 'Rename', initial: 'Groceries', fieldLabel: 'Name', validator: (t) => t.trim().isEmpty ? 'A name is required' : null)}',
              ),
              child: const Text('prompt, validated'),
            ),
          ]),
          const SizedBox(height: kGapM),
          Semantics(liveRegion: true, child: Text(_result)),
        ]),
      );
}

class _SaveChipDemo extends StatelessWidget {
  const _SaveChipDemo();

  @override
  Widget build(BuildContext context) => _Block(
        'Every state (idle renders nothing)',
        Wrap(
            spacing: kGapM,
            runSpacing: kGapM,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in SaveStatus.values)
                Column(children: [
                  SaveStatusChip(status: s),
                  Text(s.name, style: Theme.of(context).textTheme.bodySmall)
                ]),
            ]),
      );
}

class _RelativeTimeDemo extends StatelessWidget {
  const _RelativeTimeDemo();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.utc(2026, 10, 21, 12);
    const offsets = <Duration>[
      Duration(seconds: -30),
      Duration.zero,
      Duration(seconds: 59),
      Duration(minutes: 1),
      Duration(minutes: 59),
      Duration(hours: 1),
      Duration(hours: 23),
      Duration(days: 1),
      Duration(days: 8),
      Duration(days: 45),
      Duration(days: 400),
      Duration(minutes: -5),
      Duration(days: -3),
    ];
    return _Block(
      'Fixed "now"; negative offsets are in the future',
      Column(children: [
        for (final d in offsets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: kGapXs),
            child: Row(children: [
              Expanded(
                  child: Text(d.isNegative
                      ? 'now + ${-d.inSeconds} s'
                      : 'now - ${d.inSeconds} s')),
              Expanded(
                  child: Text(relativeTime(now.subtract(d), now: now),
                      textAlign: TextAlign.end)),
            ]),
          ),
      ]),
    );
  }
}
