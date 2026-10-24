/// The slice of the Rust core the app uses, as plain Dart.
///
/// Three things implement [NotesCore]: `FrbNotesCore` (the real core, over the generated flutter_rust_bridge binding), the
/// in-memory `FakeNotesCore` (widget tests and sync tests that must run without the native library), and nothing else. The UI
/// and the sync engine only ever see this file, so a change to the generated binding is absorbed in one place.
library;

import 'dart:typed_data';

/// Every failure from the core, as a stable [code] (`bad_block`, `no_such_note`, `too_large`, ...; the full list is in
/// `rust/src/api/notes.rs`) and a sentence to show.
class NotesCoreException implements Exception {
  const NotesCoreException(this.code, this.message);
  final String code;
  final String message;

  /// A block whose bytes did not hash to its address: a peer sent something tampered or damaged. Nothing was stored.
  bool get isBadBlock => code == 'bad_block';
  @override
  String toString() => 'NotesCoreException($code): $message';
}

class NoteSummary {
  const NoteSummary({required this.id, required this.title, required this.preview, required this.len, required this.atMs, required this.by, required this.head});
  final String id, title, preview, by, head;
  final int len, atMs;
}

class NoteView {
  const NoteView({required this.id, required this.title, required this.body, required this.atMs, required this.by, required this.head});
  final String id, title, body, by, head;
  final int atMs;
}

class VersionInfo {
  const VersionInfo({
    required this.manifest,
    required this.parents,
    required this.title,
    required this.len,
    required this.atMs,
    required this.by,
    required this.deleted,
    required this.available,
    required this.isHead,
  });
  final String manifest, title, by;
  final List<String> parents;
  final int len, atMs;
  final bool deleted, available, isHead;
}

/// A note's current version on one copy.
class HeadEntry {
  const HeadEntry(this.id, this.head);
  final String id, head;
  Map<String, Object?> toJson() => {'id': id, 'head': head};
  @override
  bool operator ==(Object other) => other is HeadEntry && other.id == id && other.head == head;
  @override
  int get hashCode => Object.hash(id, head);
}

class ImportReport {
  const ImportReport({required this.received, required this.stored, required this.bytes});
  final int received, stored, bytes;
}

class NoteVersion {
  const NoteVersion({required this.manifest, required this.title, required this.body, required this.atMs, required this.by, required this.deleted});
  final String manifest, title, body, by;
  final int atMs;
  final bool deleted;
}

/// Two versions of one note, neither following the other. The core never merges; the app decides ([Resolution]).
class Conflict {
  const Conflict({required this.noteId, required this.local, required this.remote, this.base});
  final String noteId;
  final NoteVersion local, remote;
  final NoteVersion? base;
}

class ApplyReport {
  const ApplyReport({
    this.upToDate = const [],
    this.fastForwarded = const [],
    this.localAhead = const [],
    this.incomplete = const [],
    this.rejected = const [],
    this.conflicts = const [],
  });
  final List<String> upToDate, fastForwarded, localAhead, incomplete, rejected;
  final List<Conflict> conflicts;
}

enum Side { local, remote }

/// The app's answer to a [Conflict].
sealed class Resolution {
  const Resolution();

  /// Keep this copy's content; record a merge version so the other copy sees us as ahead.
  const factory Resolution.keepLocal() = KeepLocal;

  /// Take the other copy's content; record a merge version with both as parents.
  const factory Resolution.takeRemote() = TakeRemote;

  /// A body the app merged.
  const factory Resolution.merged(String title, String body) = Merged;

  /// Silent and deterministic: [winner] stays the note, the other becomes a new note "title (conflict from device)".
  const factory Resolution.keepBoth(Side winner) = KeepBoth;
}

class KeepLocal extends Resolution {
  const KeepLocal();
}

class TakeRemote extends Resolution {
  const TakeRemote();
}

class Merged extends Resolution {
  const Merged(this.title, this.body);
  final String title, body;
}

class KeepBoth extends Resolution {
  const KeepBoth(this.winner);
  final Side winner;
}

class CoreStats {
  const CoreStats({
    required this.appId,
    required this.instance,
    required this.mode,
    required this.account,
    required this.device,
    required this.partition,
    required this.dataDir,
    required this.blockCount,
    required this.noteCount,
    required this.unreadableNotes,
    required this.pendingConflicts,
    required this.maxNoteBytes,
  });
  final String appId, instance, mode, account, device, partition, dataDir;
  final int blockCount, noteCount, unreadableNotes, pendingConflicts, maxNoteBytes;
}

abstract interface class NotesCore {
  Future<List<NoteSummary>> listNotes();
  Future<NoteView> getNote(String id);
  Future<NoteView> createNote(String title, String body);

  /// A new version; an unchanged title and body writes nothing.
  Future<NoteView> saveNote(String id, String title, String body);
  Future<void> deleteNote(String id);

  /// Newest first.
  Future<List<VersionInfo>> listVersions(String id, {int limit = 50});
  Future<NoteView> readVersion(String id, String manifest);

  /// Makes an earlier version current again. Writes one manifest and no body block.
  Future<NoteView> restoreVersion(String id, String manifest);

  // ---- the sync primitive (the transport is the app's: see lib/coordination) ----
  Future<List<HeadEntry>> heads();

  /// One hash of every head: equal digests mean equal notes.
  Future<String> headsDigest();

  /// Blocks needed to reach [theirs] that this copy lacks and can name now. Empty: nothing to ask for.
  Future<List<String>> missingBlocks(List<HeadEntry> theirs, {int limit = 512});
  Future<Uint8List> exportBlocks(List<String> hashes);

  /// Verifies every block's hash before storing any. Throws [NotesCoreException] `bad_block` and stores nothing otherwise.
  Future<ImportReport> importBlocks(Uint8List export);
  Future<ApplyReport> applyHeads(List<HeadEntry> theirs);
  Future<List<Conflict>> pendingConflicts();
  Future<void> resolveConflict(String noteId, String remote, Resolution how);

  Future<CoreStats> stats();

  /// Releases the native object. Calls after this are errors.
  Future<void> close();
}
