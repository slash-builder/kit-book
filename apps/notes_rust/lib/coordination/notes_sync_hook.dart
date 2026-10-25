/// The hook: the five things the Kit asks of an app, each a line or two because the engine ([NotesSync]) holds the meaning.
library;

import 'dart:async';

import 'package:app_context_kit/app_context_kit.dart';

import 'notes_sync.dart';

class NotesSyncHook extends AppCoordination {
  NotesSyncHook(this.sync);
  final NotesSync sync;

  @override
  String get channel => 'notes';
  @override
  void attach(PeerHub hub) => sync.attach(hub);
  @override
  Object? hello() => sync.hello();
  @override
  FutureOr<Admit> admit(Peer peer, Object? theirHello) => sync.admit(peer, theirHello);
  @override
  void onPeer(Peer peer, PeerChange change) {
    if (change == PeerChange.ready) sync.ready(peer);
  }

  @override
  void onMessage(Peer from, AppMessage message) => sync.onMessage(from, message);
}
