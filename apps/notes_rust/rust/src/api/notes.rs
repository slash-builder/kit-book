//! The core as Dart sees it: one opaque `NotesEngine` and plain data. Every method runs on flutter_rust_bridge's worker pool
//! and is a `Future` in Dart; a failure is thrown as a [`CoreError`].
//!
//! This file only adapts. The logic is `crate::engine::Engine`, which `cargo test` covers without the bridge.

pub use crate::types::{
    ApplyReport, Conflict, CoreStats, HeadEntry, ImportReport, NoteSummary, NoteView, VersionInfo,
};
use crate::types::{Resolution, Side};

use crate::engine::Engine;

/// Every failure, as a stable `code` to switch on and a sentence to show. Codes: `bad_snapshot`, `adopt`, `storage`, `io`,
/// `json`, `corrupt`, `bad_block`, `bad_export`, `no_such_note`, `no_such_version`, `version_unavailable`, `no_conflict`,
/// `too_large`, `invalid`.
#[derive(Debug, Clone)]
pub struct CoreError {
    pub code: String,
    pub message: String,
}

impl From<crate::Error> for CoreError {
    fn from(e: crate::Error) -> Self {
        CoreError {
            code: e.code().to_string(),
            message: e.to_string(),
        }
    }
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for CoreError {}

/// How the app answers a conflict (see `Resolution` in `types.rs`). flutter_rust_bridge turns a Rust enum that carries data
/// into a `freezed` class, which needs `freezed` and a build_runner step in the Dart project; this flat form avoids that.
/// `title` and `body` are read only for `Merged`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResolutionKind {
    KeepLocal,
    TakeRemote,
    Merged,
    KeepBothLocalWins,
    KeepBothRemoteWins,
}

#[derive(Debug, Clone)]
pub struct ResolutionChoice {
    pub kind: ResolutionKind,
    pub title: String,
    pub body: String,
}

impl From<ResolutionChoice> for Resolution {
    fn from(c: ResolutionChoice) -> Resolution {
        match c.kind {
            ResolutionKind::KeepLocal => Resolution::KeepLocal,
            ResolutionKind::TakeRemote => Resolution::TakeRemote,
            ResolutionKind::Merged => Resolution::Merged {
                title: c.title,
                body: c.body,
            },
            ResolutionKind::KeepBothLocalWins => Resolution::KeepBoth {
                winner: Side::Local,
            },
            ResolutionKind::KeepBothRemoteWins => Resolution::KeepBoth {
                winner: Side::Remote,
            },
        }
    }
}

/// The notes core. Open it with the snapshot of the App Context Kit context the Dart side already holds.
pub struct NotesEngine {
    inner: Engine,
}

impl NotesEngine {
    /// `snapshot_json` is `jsonEncode(ctx.snapshot())`. `account` is `ctx.peerAccount`; `device` is `ctx.peerDevice`.
    pub fn open(
        snapshot_json: String,
        account: String,
        device: String,
    ) -> Result<NotesEngine, CoreError> {
        Ok(NotesEngine {
            inner: Engine::open(&snapshot_json, &account, &device)?,
        })
    }

    pub fn list_notes(&self) -> Result<Vec<NoteSummary>, CoreError> {
        Ok(self.inner.list_notes()?)
    }
    pub fn get_note(&self, id: String) -> Result<NoteView, CoreError> {
        Ok(self.inner.get_note(&id)?)
    }
    pub fn create_note(&self, title: String, body: String) -> Result<NoteView, CoreError> {
        Ok(self.inner.create_note(&title, &body)?)
    }
    pub fn save_note(
        &self,
        id: String,
        title: String,
        body: String,
    ) -> Result<NoteView, CoreError> {
        Ok(self.inner.save_note(&id, &title, &body)?)
    }
    pub fn delete_note(&self, id: String) -> Result<(), CoreError> {
        Ok(self.inner.delete_note(&id)?)
    }
    pub fn list_versions(&self, id: String, limit: u32) -> Result<Vec<VersionInfo>, CoreError> {
        Ok(self.inner.list_versions(&id, limit as usize)?)
    }
    pub fn read_version(&self, id: String, manifest: String) -> Result<NoteView, CoreError> {
        Ok(self.inner.read_version(&id, &manifest)?)
    }
    pub fn restore_version(&self, id: String, manifest: String) -> Result<NoteView, CoreError> {
        Ok(self.inner.restore_version(&id, &manifest)?)
    }

    // ---- the sync primitive ----
    pub fn heads(&self) -> Vec<HeadEntry> {
        self.inner.heads()
    }
    pub fn heads_digest(&self) -> String {
        self.inner.heads_digest()
    }
    pub fn missing_blocks(
        &self,
        theirs: Vec<HeadEntry>,
        limit: u32,
    ) -> Result<Vec<String>, CoreError> {
        Ok(self.inner.missing_blocks(&theirs, limit as usize)?)
    }
    pub fn export_blocks(&self, hashes: Vec<String>) -> Result<Vec<u8>, CoreError> {
        Ok(self.inner.export_blocks(&hashes)?)
    }
    pub fn import_blocks(&self, bytes: Vec<u8>) -> Result<ImportReport, CoreError> {
        Ok(self.inner.import_blocks(&bytes)?)
    }
    pub fn apply_heads(&self, theirs: Vec<HeadEntry>) -> Result<ApplyReport, CoreError> {
        Ok(self.inner.apply_heads(&theirs)?)
    }
    pub fn pending_conflicts(&self) -> Result<Vec<Conflict>, CoreError> {
        Ok(self.inner.pending_conflicts()?)
    }
    pub fn resolve_conflict(
        &self,
        note_id: String,
        remote: String,
        how: ResolutionChoice,
    ) -> Result<(), CoreError> {
        Ok(self
            .inner
            .resolve_conflict(&note_id, &remote, &how.into())?)
    }

    pub fn stats(&self) -> CoreStats {
        self.inner.stats()
    }
}
