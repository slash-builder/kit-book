/// The minesweeper's meaning of "peers": hand a game to another copy, and (optionally) play one board together. Pure Dart.
///
/// ## Decisions
///  * **A handoff is a PULL with a confirmation**, because the Kit has no ack and `send` completing only means "the transport
///    took it". The sender OFFERS (`game.offer`, a few fields, no board); the receiving person decides; the receiver then
///    REQUESTS the board (`game.take`, request/reply: the reply is the data) and, once it has applied it, REQUESTS `game.taken`;
///    only when that request arrives does the sender release its own game. If the confirmation is lost, both copies keep the
///    game (a duplicate), never zero. The window between serving the board and hearing `game.taken` is not locked: moves
///    made on the sender in that window are lost to the receiver (a lock would need a UI state the hook cannot own).
///  * **Playing together** ("share") uses the same offer, then each move is sent as a small absolute message
///    (`reveal`/`chord`/`flag` with the resulting mark, so replays are idempotent) plus a checksum of the sender's board after
///    the move. A receiver whose own checksum differs (a move was lost or raced) pulls the whole board. The first move of a
///    game and "new game" send the whole board instead, because mine placement is random and cannot be replayed.
///  * **Only the people decide.** An offer never changes a board by itself; `game.take` is served only for an offer THIS copy
///    made, to the peer it made it to; `game.taken` releases the game only from that peer for that offer.
library;

import 'dart:async';

import 'package:application_kit/application_kit.dart';

import '../logic/game.dart';

/// What the hook needs from the app. The controller implements it.
abstract interface class GameHost {
  Minesweeper get game;

  /// Replace the current game with a board from another copy. Throws [FormatException] if it is not a consistent game.
  void adoptBoard(Map<String, Object?> board);

  /// The game was taken by another copy: this copy starts a fresh one.
  void releaseTo(String label);

  /// Apply a move that happened on another copy; does not report it as a local move.
  void applyRemoteMove(String op, int r, int c, String? mark);

  /// Peers state changed (offers, sharing, message): redraw.
  void refresh();
}

String hash64(String s) {
  var a = 0x811c9dc5, b = 0x9dc5bd1e;
  for (final c in s.codeUnits) {
    a = ((a ^ c) * 0x01000193) & 0xffffffff;
    b = ((b ^ c) * 0x85ebca6b) & 0xffffffff;
  }
  return a.toRadixString(16).padLeft(8, '0') + b.toRadixString(16).padLeft(8, '0');
}

class Offer {
  const Offer(this.id, this.from, this.mode, this.difficulty, this.status, this.seconds, this.opened);
  final String id;
  final PeerId from;

  /// `handoff` (the sender gives the game up) or `share` (both keep playing it).
  final String mode;
  final String difficulty, status;
  final int seconds, opened;

  String get summary => '${difficulty[0].toUpperCase()}${difficulty.substring(1)}, $status, $seconds s, $opened squares open';
}

class _Out {
  _Out(this.id, this.peer, this.mode);
  final String id;
  final PeerId peer;
  final String mode;
}

class GameHook extends AppCoordination {
  GameHook(this.host);
  final GameHost host;

  static const proto = 1;
  static const maxPending = 8;

  PeerHub? hub;

  /// Offers made TO this copy, waiting for the person.
  final Map<PeerId, Offer> incoming = {};
  _Out? _outgoing;
  int _nextOffer = 0;

  /// The peer this copy is playing one board with, if any.
  PeerId? sharing;

  /// Which generation of the shared board this copy holds. A new game or a first move starts a new one (epoch + 1); when two
  /// copies do that at once, the higher epoch wins and a tie goes to the lower PeerId, so both end on the same board.
  int epoch = 0;

  /// One line for the person about the last thing that happened ("desktop took the game").
  String? message;

  /// Messages refused: malformed, out of range, not from the partner, no such offer.
  int ignored = 0;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  void _tell(String? m) {
    message = m ?? message;
    if (!_changes.isClosed) _changes.add(null);
    host.refresh();
  }

  @override
  String get channel => 'game';
  @override
  void attach(PeerHub hub) => this.hub = hub;

  @override
  Object? hello() => {'proto': proto};

  @override
  FutureOr<Admit> admit(Peer peer, Object? theirHello) =>
      theirHello is Map && theirHello['proto'] == proto ? const Admit.accept() : const Admit.reject('minesweeper protocol 1 only');

  @override
  void onPeer(Peer peer, PeerChange change) {
    if (change != PeerChange.lost) return;
    final id = peer.id;
    final hadOffer = incoming.remove(id) != null;
    if (_outgoing?.peer == id) _outgoing = null;
    if (sharing == id) {
      sharing = null;
      _tell('Stopped playing together: ${PeerJson.label(id)} left. Both copies keep their own board.');
    } else if (hadOffer) {
      _tell(null);
    }
  }

  // ------------------------------------------------------------------ the person's actions

  Map<String, Object?> _summary() {
    final g = host.game;
    return {'difficulty': g.difficulty.name, 'status': g.status.name, 'seconds': g.seconds, 'opened': g.revealedCount};
  }

  /// Offer this copy's game to [peer]. mode: `handoff` or `share`.
  Future<void> offer(Peer peer, String mode) async {
    final id = '${hub!.id.instance}-${_nextOffer++}';
    _outgoing = _Out(id, peer.id, mode);
    try {
      await hub!.send(peer, PeerJson.encode({'id': id, 'mode': mode, ..._summary()}), kind: 'game.offer', schema: 1);
      _tell('Offered the game to ${PeerJson.label(peer.id)}. Waiting for them to answer.');
    } on PeerError catch (e) {
      _outgoing = null;
      _tell('Could not offer the game: ${e.message}');
    }
  }

  /// The person said yes to [o]: pull the board, apply it, confirm. Returns what happened, in words.
  Future<String> accept(Offer o) async {
    final h = hub!;
    final peer = h.readyPeers.where((p) => p.id == o.from).firstOrNull;
    incoming.remove(o.from);
    if (peer == null) return _done('${PeerJson.label(o.from)} is no longer connected.');
    try {
      final reply = await h.request(peer, PeerJson.encode({'offer': o.id}), kind: 'game.take', schema: 1);
      final j = reply.jsonBody;
      if (j is! Map || j['ok'] != true || j['board'] is! Map) return _done('${PeerJson.label(o.from)} no longer has that game to give.');
      try {
        host.adoptBoard((j['board'] as Map).cast<String, Object?>());
      } on FormatException catch (e) {
        return _done('The game from ${PeerJson.label(o.from)} was not accepted: ${e.message}');
      }
      if (o.mode == 'share') sharing = o.from;
      try {
        final ack = (await h.request(peer, PeerJson.encode({'offer': o.id}), kind: 'game.taken', schema: 1)).jsonBody;
        if (ack is Map && ack['ok'] == true) return _done(o.mode == 'share' ? 'Playing together with ${PeerJson.label(o.from)}.' : 'Took over the game from ${PeerJson.label(o.from)}.');
      } on PeerError {
        // fall through
      }
      return _done('Took the game, but ${PeerJson.label(o.from)} did not confirm: it may still show the game too.');
    } on PeerError catch (e) {
      return _done('Could not get the game from ${PeerJson.label(o.from)}: ${e.message}');
    }
  }

  String _done(String m) {
    _tell(m);
    return m;
  }

  void decline(Offer o) {
    incoming.remove(o.from);
    final peer = hub!.readyPeers.where((p) => p.id == o.from).firstOrNull;
    if (peer != null) PeerJson.quiet(hub!.send(peer, PeerJson.encode({'offer': o.id}), kind: 'game.declined', schema: 1));
    _tell(null);
  }

  void stopSharing() {
    final p = sharing;
    if (p == null) return;
    sharing = null;
    final peer = hub!.readyPeers.where((x) => x.id == p).firstOrNull;
    if (peer != null) PeerJson.quiet(hub!.send(peer, PeerJson.encode({}), kind: 'game.leave', schema: 1));
    _tell('Stopped playing together.');
  }

  /// The person moved on THIS copy. [wasReady]: the board had no mines yet, so the move cannot be replayed elsewhere.
  void localMove(String op, int r, int c, {String? mark, bool wasReady = false}) {
    final p = sharing;
    final peer = p == null ? null : hub?.readyPeers.where((x) => x.id == p).firstOrNull;
    if (peer == null) return;
    if (wasReady) return localBoard();
    PeerJson.quiet(hub!.send(peer, PeerJson.encode({'op': op, 'r': r, 'c': c, 'mark': mark, 'sum': _sum()}), kind: 'game.move', schema: 1));
  }

  /// A whole new or restarted board (new game, first move): send it all.
  void localBoard() {
    final p = sharing;
    final peer = p == null ? null : hub?.readyPeers.where((x) => x.id == p).firstOrNull;
    epoch++;
    if (peer != null) PeerJson.quiet(hub!.send(peer, PeerJson.encode({'epoch': epoch, 'board': host.game.toJson()}), kind: 'game.board', schema: 1));
  }

  String _sum() {
    final j = host.game.toJson();
    return hash64('${j['status']}|${(j['cells'] as List).join(',')}');
  }

  // ------------------------------------------------------------------ messages

  void _bad() => ignored++;

  @override
  void onMessage(Peer from, AppMessage m) {
    if (m.schema != 1) return _bad();
    final j = m.jsonBody;
    if (j is! Map) return _bad();
    switch (m.kind) {
      case 'game.offer':
        final id = j['id'], mode = j['mode'], d = j['difficulty'], st = j['status'], secs = j['seconds'], opened = j['opened'];
        final diff = Difficulty.values.where((x) => x.name == d).firstOrNull;
        final stat = GameStatus.values.where((x) => x.name == st).firstOrNull;
        if (id is! String || id.length > 64 || (mode != 'handoff' && mode != 'share') || diff == null || stat == null) return _bad();
        if (secs is! int || secs < 0 || secs > 999 || opened is! int || opened < 0 || opened > diff.rows * diff.cols) return _bad();
        if (incoming.length >= maxPending && !incoming.containsKey(from.id)) return _bad();
        incoming[from.id] = Offer(id, from.id, mode as String, diff.name, stat.name, secs, opened);
        _tell('${PeerJson.label(from.id)} wants to ${mode == 'share' ? 'play this game together' : 'send you a game'}.');
      case 'game.take':
        final o = _outgoing;
        final resync = j['resync'] == true && sharing == from.id;
        final ok = resync || (o != null && o.peer == from.id && o.id == j['offer']);
        if (m.requestId == null) return _bad();
        PeerJson.quiet(hub!.reply(m, PeerJson.encode(ok ? {'ok': true, 'board': host.game.toJson()} : {'ok': false, 'reason': 'no such offer'}), schema: 1));
        if (!ok) ignored++;
      case 'game.taken':
        final o = _outgoing;
        final ok = o != null && o.peer == from.id && o.id == j['offer'];
        if (m.requestId != null) PeerJson.quiet(hub!.reply(m, PeerJson.encode({'ok': ok}), schema: 1));
        if (!ok) return _bad();
        _outgoing = null;
        if (o.mode == 'share') {
          sharing = from.id;
          _tell('Playing together with ${PeerJson.label(from.id)}.');
        } else {
          host.releaseTo(PeerJson.label(from.id));
          _tell('${PeerJson.label(from.id)} took the game.');
        }
      case 'game.declined':
        final o = _outgoing;
        if (o == null || o.peer != from.id || o.id != j['offer']) return _bad();
        _outgoing = null;
        _tell('${PeerJson.label(from.id)} declined the game.');
      case 'game.move':
        if (sharing != from.id) return _bad();
        final op = j['op'], r = j['r'], c = j['c'], mark = j['mark'], sum = j['sum'];
        final g = host.game;
        if (op is! String || r is! int || c is! int || !g.inBounds(r, c) || sum is! String) return _bad();
        if (op == 'flag' ? Mark.values.every((x) => x.name != mark) : (op != 'reveal' && op != 'chord')) return _bad();
        host.applyRemoteMove(op, r, c, mark as String?);
        if (_sum() != sum) PeerJson.quiet(_resync(from));
      case 'game.board':
        final e = j['epoch'];
        if (sharing != from.id || j['board'] is! Map || e is! int || e < 0 || e > 1 << 40) return _bad();
        if (e < epoch || (e == epoch && hub!.id.compareTo(from.id) < 0)) return; // we win this race: they will adopt ours
        try {
          host.adoptBoard((j['board'] as Map).cast<String, Object?>());
          epoch = e;
        } on FormatException {
          _bad();
        }
      case 'game.leave':
        if (sharing != from.id) return _bad();
        sharing = null;
        _tell('${PeerJson.label(from.id)} stopped playing together.');
      default:
        _bad();
    }
  }

  Future<void> _resync(Peer from) async {
    final reply = await hub!.request(from, PeerJson.encode({'resync': true}), kind: 'game.take', schema: 1);
    final j = reply.jsonBody;
    if (j is Map && j['ok'] == true && j['board'] is Map && sharing == from.id) {
      try {
        host.adoptBoard((j['board'] as Map).cast<String, Object?>());
      } on FormatException {
        _bad();
      }
    }
  }

  void dispose() => _changes.close();
}
