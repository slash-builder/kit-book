//! The plain data that crosses the bridge. Hashes are lower-case hex strings so Dart never handles raw bytes except for
//! block exports. Times are milliseconds since the Unix epoch (UTC).

/// A note as the list shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteSummary {
    pub id: String,
    pub title: String,
    /// The first non-blank line of the body, up to 120 characters.
    pub preview: String,
    pub len: u64,
    pub at_ms: i64,
    pub by: String,
    /// The current version's address (hex).
    pub head: String,
}

/// A whole note: what the editor opens.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteView {
    pub id: String,
    pub title: String,
    pub body: String,
    pub at_ms: i64,
    pub by: String,
    pub head: String,
}

/// One entry of a note's history.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VersionInfo {
    /// The version's address (hex): the hash of its manifest.
    pub manifest: String,
    pub parents: Vec<String>,
    pub title: String,
    pub len: u64,
    pub at_ms: i64,
    pub by: String,
    pub deleted: bool,
    /// Every block of this version's body is on this copy, so it can be read and restored.
    pub available: bool,
    pub is_head: bool,
}

/// One note's current version on a copy: what copies compare.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeadEntry {
    pub id: String,
    pub head: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportReport {
    /// Records in the export.
    pub received: u32,
    /// Blocks this copy did not have and now does.
    pub stored: u32,
    pub bytes: u64,
}

/// One side of a conflict.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteVersion {
    pub manifest: String,
    pub title: String,
    pub body: String,
    pub at_ms: i64,
    pub by: String,
    pub deleted: bool,
}

/// Two versions of one note that neither follows the other. The Kit never merges: the app decides.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conflict {
    pub note_id: String,
    pub local: NoteVersion,
    pub remote: NoteVersion,
    /// A common ancestor, when the histories share one and its body is here.
    pub base: Option<NoteVersion>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ApplyReport {
    /// Notes whose head already equalled the peer's (or whose content did).
    pub up_to_date: Vec<String>,
    /// Notes this copy moved forward to the peer's version.
    pub fast_forwarded: Vec<String>,
    /// Notes where this copy already contains the peer's version: the peer should pull from us.
    pub local_ahead: Vec<String>,
    /// Notes whose blocks are not all here yet: ask again after importing more.
    pub incomplete: Vec<String>,
    /// Entries this copy refused (a manifest that is not for that note, one that fails the schema).
    pub rejected: Vec<String>,
    /// Newly found conflicts (also kept until resolved; see `pending_conflicts`).
    pub conflicts: Vec<Conflict>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Local,
    Remote,
}

/// The app's answer to a conflict. The core applies it mechanically.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Resolution {
    /// Keep this copy's content; record a merge version so the peer sees us as ahead.
    KeepLocal,
    /// Take the peer's content; record a merge version with both as parents.
    TakeRemote,
    /// A body the app merged; recorded as a version with both parents.
    Merged { title: String, body: String },
    /// Deterministic and silent: `winner` stays or becomes the note, the other becomes a new note
    /// "<title> (conflict from <device>)" with an id derived from its address. Two copies that choose the same winner make
    /// the same blocks, so they converge without talking.
    KeepBoth { winner: Side },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreStats {
    pub app_id: String,
    pub instance: String,
    pub mode: String,
    pub account: String,
    pub device: String,
    pub partition: String,
    pub data_dir: String,
    pub block_count: u32,
    pub note_count: u32,
    /// Notes whose current version cannot be read here (a head that names a block this disk lost).
    pub unreadable_notes: u32,
    pub pending_conflicts: u32,
    /// `maxNoteBytes` as read from the owner's settings (or the default).
    pub max_note_bytes: u64,
}
