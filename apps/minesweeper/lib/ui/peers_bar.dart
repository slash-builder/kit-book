import 'dart:async';

import 'package:application_kit/application_kit.dart';
import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter/material.dart';

import '../coordination/game_hook.dart';
import '../coordination/game_peers.dart';

/// Who is connected, what they have offered, and the buttons to send this game to (or play it together with) a connected copy.
class PeersBar extends StatefulWidget {
  const PeersBar({super.key, required this.peers});
  final GamePeers peers;

  @override
  State<PeersBar> createState() => _PeersBarState();
}

class _PeersBarState extends State<PeersBar> {
  StreamSubscription<void>? _sub;
  StreamSubscription<void>? _sub2;

  GameHook get hook => widget.peers.hook;
  PeerHub? get hub => widget.peers.handle.hub;

  @override
  void initState() {
    super.initState();
    _sub = widget.peers.handle.changes.listen((_) => _redraw()); // hub opened or failed, a peer came or went
    _sub2 = hook.changes.listen((_) => _redraw());
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub2?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = hub;
    return Column(key: const ValueKey('peers-bar'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      PeersIndicator.forHandle(widget.peers.handle, extra: hook.message),
      for (final o in hook.incoming.values.toList())
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, key: ValueKey('offer-${o.from}'), children: [
            Text('${PeerJson.label(o.from)} offers ${o.mode == 'share' ? 'to play together' : 'a game'}: ${o.summary}.'),
            FilledButton(
                key: const ValueKey('offer-accept'),
                onPressed: () => hook.accept(o),
                child: Text(o.mode == 'share' ? 'Join (replaces my game)' : 'Take over (replaces my game)')),
            TextButton(key: const ValueKey('offer-decline'), onPressed: () => hook.decline(o), child: const Text('Decline')),
          ]),
        ),
      if (hook.sharing != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Playing together with ${PeerJson.label(hook.sharing!)}', key: const ValueKey('sharing-label')),
            TextButton(key: const ValueKey('stop-sharing'), onPressed: hook.stopSharing, child: const Text('Stop')),
          ]),
        ),
      if (h != null && h.readyPeers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 8, children: [
            for (final p in h.readyPeers)
              PopupMenuButton<String>(
                key: ValueKey('send-${p.id}'),
                tooltip: 'Send this game to ${PeerJson.label(p.id)}',
                onSelected: (mode) => hook.offer(p, mode),
                itemBuilder: (_) => [
                  PopupMenuItem(key: const ValueKey('send-handoff'), value: 'handoff', child: Text('Send this game to ${PeerJson.label(p.id)}')),
                  PopupMenuItem(key: const ValueKey('send-share'), value: 'share', child: Text('Play this game together with ${PeerJson.label(p.id)}')),
                ],
                child: Chip(label: Text('Send to ${PeerJson.label(p.id)}'), avatar: const Icon(Icons.send, size: 16), visualDensity: VisualDensity.compact),
              ),
          ]),
        ),
    ]);
  }
}
