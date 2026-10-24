import 'dart:async';

import 'package:flutter/widgets.dart';

import '../logic/controller.dart';

/// Rebuilds [builder] when the controller changes and every 50 ms while something is running,
/// so the readout moves. The time itself always comes from the wall clock, not from the ticks.
class Ticking extends StatefulWidget {
  const Ticking({super.key, required this.controller, required this.builder});
  final StopwatchController controller;
  final Widget Function(BuildContext context, int nowMs) builder;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  Timer? _timer;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.changes.listen((_) => setState(() {}));
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final s = widget.controller.state;
      if (s.stopwatch.clock.running || s.countdown.clock.running) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.controller.nowMs);
}
