import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter/material.dart';

import '../coordination/timer_peers.dart';
import '../logic/controller.dart';
import 'countdown_page.dart';
import 'stopwatch_page.dart';

class StopwatchApp extends StatelessWidget {
  const StopwatchApp({super.key, required this.controller});
  final StopwatchController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppContextScope.of(context).manifest.name,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: HomeScreen(controller: controller),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final StopwatchController controller;

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        // Interface Kit: page scaffold (title bar, tabs, footer status line).
        appBar: AppBar(
          title: Text(ctx.manifest.name),
          bottom: const TabBar(tabs: [Tab(text: 'Stopwatch'), Tab(text: 'Timer')]),
        ),
        body: TabBarView(children: [
          StopwatchPage(controller: controller),
          CountdownPage(controller: controller),
        ]),
        bottomNavigationBar: Column(
          key: const Key('footer'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NotesBanner.forContext(ctx),
            if (controller.peers != null) _PeersFooter(peers: controller.peers!),
            Align(alignment: Alignment.centerLeft, child: ModeBadge.forContext(ctx)),
          ],
        ),
      ),
    );
  }
}

/// Who is connected (the Kit's indicator follows the handle itself), plus the last "finished on" notice, which is the app's.
class _PeersFooter extends StatelessWidget {
  const _PeersFooter({required this.peers});
  final TimerPeers peers;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream: peers.changes,
        builder: (context, _) => PeersIndicator.forHandle(peers.handle, extra: peers.notice),
      );
}
