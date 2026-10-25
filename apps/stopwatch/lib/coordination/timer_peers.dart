/// Glue between the app (controller, notifier, state directory) and the pure hook in `shared_timer.dart`. No Flutter.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';

import '../logic/controller.dart';
import 'shared_timer.dart';

class TimerPeers {
  TimerPeers._(this.hook, this.handle);

  final SharedTimerHook hook;
  /// What `ctx.startPeers` returned: the hub (null while peers are unavailable), why, and a change stream.
  final PeersHandle handle;

  /// "Timer finished on laptop #3fa2" after another copy announced; cleared when this copy starts or resets the timer.
  String? notice;

  final _changes = StreamController<void>.broadcast();

  /// Fires when [notice] changes. (The hub opening, failing or a peer coming and going is [PeersHandle.changes], which the
  /// Kit's `PeersIndicator.forHandle` follows by itself.)
  Stream<void> get changes => _changes.stream;

  /// Wires [controller] to a new hub. [announce] is called with (title, body) for a finish, here or elsewhere; the app decides
  /// whether that becomes a system notification.
  static TimerPeers start(
    AppContext ctx,
    StopwatchController controller, {
    required void Function(String title, String body) announce,
    FakePeerNetwork? network,
    Duration takeoverGrace = const Duration(seconds: 2),
  }) {
    final stampFile = File('${ctx.dirs.state}${Platform.pathSeparator}shared-timer.json');
    late final TimerPeers self;
    final hook = SharedTimerHook(
      nowMs: () => controller.nowMs,
      current: () => controller.state.countdown,
      adopt: controller.adoptCountdown,
      initial: _loadStamp(stampFile),
      onStamp: (s) => _saveStamp(stampFile, s),
      takeoverGrace: takeoverGrace,
      onFinished: (f) {
        if (f.local) {
          announce('Timer finished', '${f.label} countdown is done');
        } else {
          self.notice = 'Timer finished on ${PeerJson.label(f.by)}';
          announce('Timer finished', '${f.label} countdown finished on ${PeerJson.label(f.by)}');
          self._poke();
        }
      },
    );
    final handle = ctx.startPeers(hook, network: network);
    self = TimerPeers._(hook, handle);
    if (handle.hub != null) {
      controller.onCountdownCommand = () {
        self.notice = null;
        hook.changed();
        self._poke();
      };
    }
    ctx.onClose(() {
      hook.dispose();
      return self._changes.close();
    });
    controller.peers = self;
    return self;
  }

  void _poke() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // The stamp must survive a restart: a copy that comes back with stamp 0 would lose to every peer's older state.
  static Stamp _loadStamp(File f) {
    try {
      return Stamp.parse(jsonDecode(f.readAsStringSync())) ?? const Stamp(0, '');
    } on FormatException {
      return const Stamp(0, ''); // derived data: safe to start over; the next save replaces it
    } on FileSystemException {
      return const Stamp(0, '');
    }
  }

  static void _saveStamp(File f, Stamp s) {
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(s.toJson()));
    } on FileSystemException {
      // best effort: without it a restarted copy just has to learn the stamp from its peers
    }
  }
}
