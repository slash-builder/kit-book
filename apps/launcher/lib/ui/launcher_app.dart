import 'dart:async';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../logic/launcher_controller.dart';
import '../logic/launcher_model.dart';

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key, required this.controller, this.refreshEvery});
  final LauncherController controller;

  /// Defaults to the `refreshSeconds` setting (3 s).
  final Duration? refreshEvery;

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    return MaterialApp(
      title: ctx.manifest.name,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
      home: RosterScreen(controller: controller, refreshEvery: refreshEvery ?? Duration(seconds: ctx.config.get<int>('refreshSeconds', 3))),
    );
  }
}

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key, required this.controller, required this.refreshEvery});
  final LauncherController controller;
  final Duration refreshEvery;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  LauncherSnapshot? _snap;
  Timer? _timer;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    final s = await widget.controller.refresh();
    _busy = false;
    if (mounted) setState(() => _snap = s);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final c = widget.controller;
    final ctx = AppContextScope.of(context);
    return PageScaffold(
      title: ctx.manifest.name,
      actions: [
        ModeBadge.forContext(ctx),
        IconButton(key: const Key('refresh'), tooltip: 'Refresh now', icon: const Icon(Icons.refresh), onPressed: _refresh),
      ],
      // Nothing is on screen until the first scan has come back; after that the banner stays and only the list can be empty.
      body: AsyncStateView<LauncherSnapshot>(
        state: snap == null ? const ViewState.loading() : ViewState.ready(snap),
        loadingLabel: 'Scanning the roster',
        builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ctx.notes also carries the Venue description, already a line in the banner below, so it is filtered out.
          NotesBanner(notes: [for (final n in ctx.notes) if (n.text != ctx.venue.description) n]),
          _Banner(ctx: ctx, controller: c, snap: snap),
          const Divider(height: 1),
          Expanded(
            child: AsyncStateView<List<AppRow>>(
              state: ViewState.fromList(snap.rows),
              empty: const EmptyState(title: 'Nothing announced and no apps directory set.'),
              builder: (context, rows) => ListView(children: [
                const _Header(),
                for (final r in rows) _Row(row: r, now: snap.takenAt),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Where the roster lives, where the manifests come from, what Venue says. A warning when something was skipped or unreachable.
class _Banner extends StatelessWidget {
  const _Banner({required this.ctx, required this.controller, required this.snap});
  final AppContext ctx;
  final LauncherController controller;
  final LauncherSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      'Roster: ${controller.roster.dir}',
      controller.appsDir == null ? 'Apps directory: not set (LAUNCHER_APPS_DIR or appsDir in settings)' : 'Apps directory: ${controller.appsDir}',
      if (snap.venueError != null) 'Venue nodes: unavailable (${snap.venueError})' else 'Venue nodes: ${snap.venueNodes.isEmpty ? 'none' : snap.venueNodes.map((n) => '${n.name} ready=${n.ready}').join(', ')}',
      ctx.venue.description,
      for (final f in snap.unreadableRosterFiles) 'Unreadable roster file: $f',
      for (final e in snap.manifestProblems.entries) 'Skipped ${e.key}: ${e.value}',
    ];
    final trouble = snap.venueError != null || snap.unreadableRosterFiles.isNotEmpty || snap.manifestProblems.isNotEmpty;
    return StatusBanner(
      key: const Key('banner'),
      severity: trouble ? Severity.warning : Severity.info,
      message: lines.join('\n'),
    );
  }
}

const _cols = [3, 3, 2, 5, 2, 2, 2, 5];

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    const names = ['Status', 'Name', 'Version', 'Id', 'Copy', 'Pid', 'Uptime', 'Note'];
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        for (var i = 0; i < names.length; i++) Expanded(flex: _cols[i], child: Text(names[i], style: style)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.now});
  final AppRow row;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (row.status) {
      AppStatus.running => ('running', Colors.green),
      AppStatus.stale => ('stale', Colors.red),
      AppStatus.gone => ('gone', Colors.grey),
      AppStatus.notRunning => ('not running', Colors.blueGrey),
    };
    final up = row.uptime(now);
    final dim = row.status == AppStatus.gone || row.status == AppStatus.notRunning;
    final style = dim ? TextStyle(color: Theme.of(context).disabledColor) : null;
    final note = [
      if (row.isSelf) 'this app',
      if (!row.known && row.status != AppStatus.notRunning) 'no manifest found',
      if (row.why != null) row.why!,
    ].join('; ');
    return Padding(
      key: Key('row-${row.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Expanded(
          flex: _cols[0],
          child: Row(children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(label, key: Key('status-${row.key}'), style: style)),
          ]),
        ),
        Expanded(flex: _cols[1], child: Text(row.name, style: style)),
        Expanded(flex: _cols[2], child: Text(row.version, style: style)),
        Expanded(flex: _cols[3], child: Text(row.id, style: style)),
        Expanded(flex: _cols[4], child: Text(row.instance ?? '', key: Key('instance-${row.key}'), style: style)),
        Expanded(flex: _cols[5], child: Text(row.pid?.toString() ?? '', style: style)),
        Expanded(flex: _cols[6], child: Text(up == null ? '' : formatUptime(up), style: style)),
        Expanded(flex: _cols[7], child: Text(note, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
