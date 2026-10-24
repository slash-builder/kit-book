/// Glue between the app (controller, notice banner) and the pure hook in `game_hook.dart`. No Flutter.
library;

import 'package:application_kit/application_kit.dart';

import 'game_hook.dart';

class GamePeers {
  GamePeers._(this.hook, this.handle);
  final GameHook hook;
  /// What `ctx.startPeers` returned: the hub (null while peers are unavailable), why, and a change stream.
  final PeersHandle handle;

  /// Builds the hook over [host] and starts a hub. The caller connects the host's move callbacks to [GameHook.localMove] and
  /// [GameHook.localBoard]. [KitNotDeclared] is not swallowed.
  static GamePeers start(AppContext ctx, GameHost host, {FakePeerNetwork? network}) {
    final hook = GameHook(host);
    final handle = ctx.startPeers(hook, network: network);
    ctx.onClose(hook.dispose);
    return GamePeers._(hook, handle);
  }
}
