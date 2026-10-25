//! The core as one object: an adopted App Context Kit context plus the Storage Kit slice for `(account, app id)`.
//!
//! **Who owns what.** The Dart UI opened the App Context Kit context (`AppContextKit.run`); it owns `config.json` and the roster
//! entry. This side adopted a snapshot of it ([`app_context_kit::AppContext::adopt`]): it announces nothing, never writes
//! settings (it only reads `maxNoteBytes` through the Kit's read-only reader), and owns the files it creates under `data`:
//! `blocks/` (the Storage Kit store), `heads-<partition>.json` and `conflicts-<partition>.json`.
//!
//! One lock guards the store, so calls from Dart's worker threads are serialised.

use std::sync::{Mutex, MutexGuard};

use app_context_kit::{AdoptedContext, AppContext, ContextSnapshot};
use storage_kit::Hash;

use crate::error::{Error, Result};
use crate::namespace::{check_label, Namespace};
use crate::store::{is_note_id, parse_hash, NotesStore, DEFAULT_MAX_NOTE_BYTES};
use crate::types::{
    ApplyReport, Conflict, CoreStats, HeadEntry, ImportReport, NoteSummary, NoteView, Resolution,
    VersionInfo,
};

pub struct Engine {
    inner: Mutex<Inner>,
}

impl std::fmt::Debug for Engine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Engine { .. }")
    }
}

struct Inner {
    ctx: AdoptedContext,
    store: NotesStore,
}

impl Inner {
    fn max_note_bytes(&self) -> u64 {
        // Read the owner's settings fresh each time: a change in the Dart UI shows up without a restart.
        self.ctx
            .settings()
            .get_or("maxNoteBytes", DEFAULT_MAX_NOTE_BYTES)
    }
}

/// First non-blank line of `text`, at most 120 characters.
fn preview_of(text: &str) -> String {
    text.lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map(|l| l.chars().take(120).collect())
        .unwrap_or_default()
}

impl Engine {
    /// Adopt the context described by `snapshot_json` (what Dart's `AppContext.snapshot()` encodes) and open the notes
    /// store for `account` and `device`.
    pub fn open(snapshot_json: &str, account: &str, device: &str) -> Result<Engine> {
        let snapshot = ContextSnapshot::parse(snapshot_json)?;
        Engine::open_snapshot(&snapshot, account, device)
    }

    pub fn open_snapshot(
        snapshot: &ContextSnapshot,
        account: &str,
        device: &str,
    ) -> Result<Engine> {
        check_label("device", device)?;
        let ctx = AppContext::adopt(snapshot);
        let ns = Namespace::new(account, ctx.app_id())?;
        let store = NotesStore::open(&ctx, ns, device)?;
        Ok(Engine {
            inner: Mutex::new(Inner { ctx, store }),
        })
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        // A panic while the lock was held leaves the files consistent (every write is by rename), so carry on.
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Tests: a fixed clock, so "the later edit" is not a race.
    pub fn set_clock(&self, clock: Box<dyn Fn() -> i64 + Send>) {
        self.lock().store.set_clock(clock);
    }

    // ---- notes -------------------------------------------------------------------------------------------------

    pub fn list_notes(&self) -> Result<Vec<NoteSummary>> {
        let g = self.lock();
        let mut out = Vec::new();
        for (id, head) in g.store.heads() {
            // A head whose manifest cannot be read (blocks lost to a torn write) hides one note, not the whole list;
            // `stats().unreadable_notes` counts them.
            let Ok(m) = g.store.manifest(head) else {
                continue;
            };
            if m.deleted {
                continue;
            }
            let prefix = g.store.read_prefix(&m, 4096).unwrap_or_default();
            out.push(NoteSummary {
                id: id.clone(),
                title: m.title.clone(),
                preview: preview_of(&String::from_utf8_lossy(&prefix)),
                len: m.len,
                at_ms: m.at,
                by: m.by.clone(),
                head: head.to_hex(),
            });
        }
        out.sort_by(|a, b| b.at_ms.cmp(&a.at_ms).then_with(|| a.id.cmp(&b.id)));
        Ok(out)
    }

    fn view(g: &Inner, id: &str, addr: &Hash) -> Result<NoteView> {
        let m = g.store.manifest(addr)?;
        if !g.store.tree_complete(&m)? {
            return Err(Error::VersionUnavailable(addr.to_hex()));
        }
        Ok(NoteView {
            id: id.to_string(),
            title: m.title.clone(),
            body: String::from_utf8_lossy(&g.store.read_body(&m)?).into_owned(),
            at_ms: m.at,
            by: m.by.clone(),
            head: addr.to_hex(),
        })
    }

    pub fn get_note(&self, id: &str) -> Result<NoteView> {
        let g = self.lock();
        let head = g
            .store
            .head(id)
            .ok_or_else(|| Error::NoSuchNote(id.to_string()))?;
        if g.store.manifest(&head)?.deleted {
            return Err(Error::NoSuchNote(id.to_string()));
        }
        Engine::view(&g, id, &head)
    }

    /// A new note with a fresh id.
    pub fn create_note(&self, title: &str, body: &str) -> Result<NoteView> {
        let mut g = self.lock();
        let limit = g.max_note_bytes();
        let id = loop {
            let id = new_note_id(g.store.heads().len());
            if g.store.head(&id).is_none() {
                break id;
            }
        };
        let addr = g.store.save(&id, title, body.as_bytes(), limit)?;
        Engine::view(&g, &id, &addr)
    }

    /// A new version of `id`; an unchanged title and body writes nothing.
    pub fn save_note(&self, id: &str, title: &str, body: &str) -> Result<NoteView> {
        let mut g = self.lock();
        if g.store.head(id).is_none() {
            return Err(Error::NoSuchNote(id.to_string()));
        }
        let limit = g.max_note_bytes();
        let addr = g.store.save(id, title, body.as_bytes(), limit)?;
        Engine::view(&g, id, &addr)
    }

    pub fn delete_note(&self, id: &str) -> Result<()> {
        self.lock().store.delete(id).map(|_| ())
    }

    pub fn list_versions(&self, id: &str, limit: usize) -> Result<Vec<VersionInfo>> {
        let g = self.lock();
        let head = g
            .store
            .head(id)
            .ok_or_else(|| Error::NoSuchNote(id.to_string()))?;
        let (all, _) = g.store.walk_history(head, &Default::default())?;
        let mut rows = Vec::new();
        for addr in all {
            let m = g.store.manifest(&addr)?;
            rows.push((addr, m));
        }
        rows.sort_by(|a, b| {
            b.1.at
                .cmp(&a.1.at)
                .then_with(|| b.0.to_hex().cmp(&a.0.to_hex()))
        });
        rows.truncate(limit.max(1));
        rows.into_iter()
            .map(|(addr, m)| {
                Ok(VersionInfo {
                    manifest: addr.to_hex(),
                    parents: m.parents.clone(),
                    title: m.title.clone(),
                    len: m.len,
                    at_ms: m.at,
                    by: m.by.clone(),
                    deleted: m.deleted,
                    available: g.store.tree_complete(&m)?,
                    is_head: addr == head,
                })
            })
            .collect()
    }

    /// The content of one version of `id`, without making it current.
    pub fn read_version(&self, id: &str, manifest: &str) -> Result<NoteView> {
        let g = self.lock();
        let addr = parse_hash(manifest)?;
        if !g.store.has_block(&addr) {
            return Err(Error::NoSuchVersion(manifest.to_string()));
        }
        if g.store.manifest(&addr)?.id != id {
            return Err(Error::NoSuchVersion(manifest.to_string()));
        }
        Engine::view(&g, id, &addr)
    }

    /// Make an earlier version current again. Writes one manifest and no body block.
    pub fn restore_version(&self, id: &str, manifest: &str) -> Result<NoteView> {
        let mut g = self.lock();
        let addr = g.store.restore(id, &parse_hash(manifest)?)?;
        Engine::view(&g, id, &addr)
    }

    // ---- sync --------------------------------------------------------------------------------------------------

    pub fn heads(&self) -> Vec<HeadEntry> {
        self.lock().store.head_entries()
    }

    pub fn heads_digest(&self) -> String {
        self.lock().store.heads_digest()
    }

    pub fn missing_blocks(&self, theirs: &[HeadEntry], limit: usize) -> Result<Vec<String>> {
        let g = self.lock();
        Ok(g.store
            .missing_blocks(theirs, limit.clamp(1, 4096))?
            .iter()
            .map(Hash::to_hex)
            .collect())
    }

    pub fn export_blocks(&self, hashes: &[String]) -> Result<Vec<u8>> {
        let g = self.lock();
        let parsed: Result<Vec<Hash>> = hashes.iter().map(|h| parse_hash(h)).collect();
        g.store.export_blocks(&parsed?)
    }

    pub fn import_blocks(&self, export: &[u8]) -> Result<ImportReport> {
        self.lock().store.import_blocks(export)
    }

    pub fn apply_heads(&self, theirs: &[HeadEntry]) -> Result<ApplyReport> {
        self.lock().store.apply_heads(theirs)
    }

    pub fn pending_conflicts(&self) -> Result<Vec<Conflict>> {
        self.lock().store.pending_conflicts()
    }

    pub fn resolve_conflict(&self, note_id: &str, remote: &str, how: &Resolution) -> Result<()> {
        if !is_note_id(note_id) {
            return Err(Error::Invalid(format!("not a note id: {note_id:?}")));
        }
        self.lock()
            .store
            .resolve_conflict(note_id, &parse_hash(remote)?, how)
    }

    pub fn stats(&self) -> CoreStats {
        let g = self.lock();
        let manifests: Vec<_> = g
            .store
            .heads()
            .values()
            .map(|h| g.store.manifest(h))
            .collect();
        let live = manifests
            .iter()
            .filter(|m| matches!(m, Ok(m) if !m.deleted))
            .count();
        let unreadable = manifests.iter().filter(|m| m.is_err()).count();
        CoreStats {
            app_id: g.ctx.app_id().to_string(),
            instance: g.ctx.instance().to_string(),
            mode: g.ctx.mode().as_str().to_string(),
            account: g.store.namespace().account().to_string(),
            device: g.store.device().to_string(),
            partition: g.store.partition().to_hex(),
            data_dir: g.ctx.dirs().data.clone(),
            block_count: g.store.block_count() as u32,
            note_count: live as u32,
            unreadable_notes: unreadable as u32,
            pending_conflicts: g.store.conflicts.len() as u32,
            max_note_bytes: g.max_note_bytes(),
        }
    }
}

/// `n` plus 15 hex digits drawn from the clock, the process, a counter and the std hasher's per-process random keys. Not
/// cryptographic: it only has to make two copies' new notes unlikely to share an id.
fn new_note_id(salt: usize) -> String {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let mut h = RandomState::new().build_hasher();
    h.write_u64(COUNTER.fetch_add(1, Ordering::Relaxed));
    h.write_usize(salt);
    h.write_u32(std::process::id());
    h.write_u128(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos()),
    );
    let digest = Hash::of(&h.finish().to_le_bytes()).to_hex();
    format!("n{}", &digest[..15])
}
