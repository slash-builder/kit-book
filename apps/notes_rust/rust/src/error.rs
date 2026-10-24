//! One error type for the core. It crosses the bridge as `{ code, message }` (see `api/`), so Dart gets a stable code to
//! switch on and a sentence to show.

use std::fmt;

use storage_kit::StorageError;

#[derive(Debug)]
pub enum Error {
    /// The snapshot the Dart side passed was refused by the Application Kit's strict parser.
    Snapshot(application_kit::SnapshotError),
    /// Something the Application Kit's adopt API refused (a bad name, a directory that cannot be created).
    Adopt(application_kit::AdoptError),
    Storage(StorageError),
    Io(std::io::Error),
    Json(serde_json::Error),
    /// A file or block this app wrote itself no longer parses, or a manifest is not shaped as the schema says.
    Corrupt(String),
    /// Bytes that do not hash to the address they were sent under. Nothing was stored.
    BadBlock { claimed: String, actual: String },
    /// A malformed export (bad magic, a record that runs past the end, a block over the size limit).
    BadExport(String),
    NoSuchNote(String),
    NoSuchVersion(String),
    /// A version whose blocks are not all on this copy (it was never synced here).
    VersionUnavailable(String),
    NoConflict(String),
    /// A note body over the limit (`maxNoteBytes` in the settings the owner writes, default 32 MiB).
    TooLarge { len: u64, limit: u64 },
    /// An argument that cannot be right (an id that is not a note id, a hash that is not hex, a blank device name).
    Invalid(String),
}

impl Error {
    /// The stable code Dart switches on.
    pub fn code(&self) -> &'static str {
        match self {
            Error::Snapshot(_) => "bad_snapshot",
            Error::Adopt(_) => "adopt",
            Error::Storage(_) => "storage",
            Error::Io(_) => "io",
            Error::Json(_) => "json",
            Error::Corrupt(_) => "corrupt",
            Error::BadBlock { .. } => "bad_block",
            Error::BadExport(_) => "bad_export",
            Error::NoSuchNote(_) => "no_such_note",
            Error::NoSuchVersion(_) => "no_such_version",
            Error::VersionUnavailable(_) => "version_unavailable",
            Error::NoConflict(_) => "no_conflict",
            Error::TooLarge { .. } => "too_large",
            Error::Invalid(_) => "invalid",
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Snapshot(e) => write!(f, "{e}"),
            Error::Adopt(e) => write!(f, "{e}"),
            Error::Storage(e) => write!(f, "storage: {e}"),
            Error::Io(e) => write!(f, "io: {e}"),
            Error::Json(e) => write!(f, "json: {e}"),
            Error::Corrupt(m) => write!(f, "corrupt: {m}"),
            Error::BadBlock { claimed, actual } => {
                write!(f, "block sent as {claimed} hashes to {actual}; refused")
            }
            Error::BadExport(m) => write!(f, "bad block export: {m}"),
            Error::NoSuchNote(n) => write!(f, "no such note: {n}"),
            Error::NoSuchVersion(v) => write!(f, "no such version: {v}"),
            Error::VersionUnavailable(v) => {
                write!(f, "version {v} is not on this copy (its blocks were never synced here)")
            }
            Error::NoConflict(n) => write!(f, "note {n} has no pending conflict with that version"),
            Error::TooLarge { len, limit } => write!(f, "note is {len} bytes; the limit is {limit}"),
            Error::Invalid(m) => write!(f, "invalid argument: {m}"),
        }
    }
}

impl std::error::Error for Error {}

macro_rules! from {
    ($t:ty, $v:ident) => {
        impl From<$t> for Error {
            fn from(e: $t) -> Self {
                Error::$v(e)
            }
        }
    };
}
from!(StorageError, Storage);
from!(std::io::Error, Io);
from!(serde_json::Error, Json);
from!(application_kit::SnapshotError, Snapshot);
from!(application_kit::AdoptError, Adopt);

pub type Result<T> = std::result::Result<T, Error>;
