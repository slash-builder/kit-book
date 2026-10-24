import 'package:flutter/material.dart';

import '../logic/clock.dart';
import '../logic/controller.dart';
import '../logic/models.dart';
import 'ticking.dart';

class CountdownPage extends StatefulWidget {
  const CountdownPage({super.key, required this.controller});
  final StopwatchController controller;

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> {
  final _field = TextEditingController();
  String? _error;

  StopwatchController get c => widget.controller;

  void _apply(String text) {
    final ms = parseDurationMs(text);
    if (ms == null || ms == 0) {
      setState(() => _error = 'Use seconds (90), mm:ss (1:30) or h:mm:ss');
      return;
    }
    setState(() => _error = null);
    c.resetCountdown(durationMs: ms);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Ticking(
      controller: c,
      builder: (context, now) {
        final cd = c.state.countdown;
        final phase = cd.phase();
        final idle = phase == CountdownPhase.idle;
        return Column(children: [
          const SizedBox(height: 24),
          Text(formatMs(cd.remainingMs(now)),
              key: const Key('cd-readout'),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 8),
          Text(
            switch (phase) {
              CountdownPhase.idle => 'Ready: ${formatMs(cd.durationMs, tenths: false)}',
              CountdownPhase.running => 'Running',
              CountdownPhase.paused => 'Paused',
              CountdownPhase.done => 'Done${cd.endedAtMs == null ? '' : ' at ${_clock(cd.endedAtMs!)}'}',
            },
            key: const Key('cd-status'),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton(
                key: const Key('cd-toggle'),
                onPressed: phase == CountdownPhase.done ? null : c.toggleCountdown,
                child: Text(phase == CountdownPhase.running ? 'Pause' : 'Start')),
            const SizedBox(width: 8),
            TextButton(key: const Key('cd-reset'), onPressed: idle ? null : () => c.resetCountdown(), child: const Text('Reset')),
          ]),
          const SizedBox(height: 24),
          if (idle) ...[
            Wrap(spacing: 8, children: [
              for (final s in const [10, 60, 300, 600])
                ActionChip(label: Text(formatMs(s * 1000, tenths: false)), onPressed: () => c.resetCountdown(durationMs: s * 1000)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              child: TextField(
                key: const Key('cd-custom'),
                controller: _field,
                decoration: InputDecoration(labelText: 'Custom length', hintText: '1:30', errorText: _error),
                onSubmitted: _apply,
              ),
            ),
          ],
        ]);
      },
    );
  }

  static String _clock(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
