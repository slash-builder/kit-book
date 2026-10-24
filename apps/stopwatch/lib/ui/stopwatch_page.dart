import 'package:flutter/material.dart';

import '../logic/clock.dart';
import '../logic/controller.dart';
import 'ticking.dart';

class StopwatchPage extends StatelessWidget {
  const StopwatchPage({super.key, required this.controller});
  final StopwatchController controller;

  @override
  Widget build(BuildContext context) {
    return Ticking(
      controller: controller,
      builder: (context, now) {
        final sw = controller.state.stopwatch;
        final running = sw.clock.running;
        final fresh = !running && sw.clock.accumulatedMs == 0 && sw.laps.isEmpty;
        return Column(children: [
          const SizedBox(height: 24),
          Text(formatMs(sw.clock.elapsedMs(now)),
              key: const Key('sw-readout'),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton(
                key: const Key('sw-toggle'), onPressed: controller.toggleStopwatch, child: Text(running ? 'Pause' : 'Start')),
            const SizedBox(width: 8),
            OutlinedButton(key: const Key('sw-lap'), onPressed: running ? controller.lap : null, child: const Text('Lap')),
            const SizedBox(width: 8),
            TextButton(key: const Key('sw-reset'), onPressed: fresh || running ? null : controller.resetStopwatch, child: const Text('Reset')),
          ]),
          const Divider(height: 32),
          Expanded(
            child: sw.laps.isEmpty
                // Interface Kit: empty state.
                ? const Center(child: Text('No laps yet'))
                : ListView(children: [
                    for (final lap in sw.laps.reversed)
                      ListTile(
                        dense: true,
                        leading: Text('Lap ${lap.number}'),
                        title: Text('+${formatMs(lap.splitMs)}'),
                        trailing: Text(formatMs(lap.totalMs)),
                      ),
                  ]),
          ),
        ]);
      },
    );
  }
}
