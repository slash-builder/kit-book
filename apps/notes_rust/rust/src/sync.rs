//! The sync primitive. The transport is not here (the Dart side carries bytes over the Application Kit's peer layer); what
//! is here is everything that needs the blocks:
//!
//! * [`NotesStore::heads_digest`]: one hash for "everything I have", sent in the peer hello.
//! * [`NotesStore::missing_blocks`]: given the peer's heads, which blocks do I lack? A list node's children are only
//!   known once it is here, so this is asked again after each import (manifest, then list node, then chunks).
//! * [`NotesStore::export_blocks`] / [`NotesStore::import_blocks`]: blocks as one byte string. **Import verifies every
//!   block's hash before storing any of them**: the Storage Kit's `put` would file tampered bytes under their own hash
//!   without an error, so the check is ours to make. A refused import changes nothing.
//! * [`NotesStore::apply_heads`]: with the blocks here, move heads forward, report who is ahead, and detect conflicts.
//!   **The core never merges.** It returns both versions; the app answers with a [`Resolution`].
//!
//! Heads only ever move in `apply_heads` and the resolution calls, after the whole version is present, so a failed or
//! tampered transfer leaves every note exactly as it was (orphan blocks may remain: the Storage Kit has no delete).

use std::collections::HashSet;

use storage_kit::{Hash, ImmutableStore};

use crate::error::{Error, Result};
use crate::store::{list_children, parse_hash, Body, Manifest, NotesStore};
use crate::types::{ApplyReport, Conflict, HeadEntry, ImportReport, NoteVersion, Resolution, Side};

/// First four bytes of an export.
pub const EXPORT_MAGIC: &[u8; 4] = b"NBK1";
const RECORD_HEADER: usize = 32 + 4;
/// Most hashes one `export_blocks` call looks at.
pub const MAX_EXPORT_HASHES: usize = 1024;
/// An export stops adding blocks once it holds this many bytes; the caller asks again for the rest.
pub const MAX_EXPORT_BYTES: usize = 8 * 1024 * 1024;
/// Largest single block an import accepts (the Kit's chunks are at most 64 KiB; this leaves room for other profiles).
pub const MAX_BLOCK_BYTES: usize = 4 * 1024 * 1024;
pub const MAX_IMPORT_BYTES: usize = 64 * 1024 * 1024;
pub const MAX_IMPORT_RECORDS: usize = 8192;

impl NotesStore {
    /// One hash of every note's head. Equal digests mean two copies hold the same notes.
    pub fn heads_digest(&self) -> String {
        let mut text = String::from("notes-rust/heads/v1\n");
        for (id, head) in self.heads() {
            text.push_str(id);
            text.push('\t');
            text.push_str(&head.to_hex());
            text.push('\n');
        }
        Hash::of(text.as_bytes()).to_hex()
    }

    pub fn head_entries(&self) -> Vec<HeadEntry> {
        self.heads()
            .iter()
            .map(|(id, h)| HeadEntry {
                id: id.clone(),
                head: h.to_hex(),
            })
            .collect()
    }

    fn entry(&self, e: &HeadEntry) -> Result<Hash> {
        if !crate::store::is_note_id(&e.id) {
            return Err(Error::Invalid(format!("not a note id: {:?}", e.id)));
        }
        parse_hash(&e.head)
    }

    // ---- what do I lack? ---------------------------------------------------------------------------------------

    /// Blocks needed to reach the peer's heads that this copy lacks and can name now, at most `limit`.
    ///
    /// For each note whose head differs: the head manifest, then any ancestors back to a version this copy has, then the
    /// body of the head version only (old versions' bodies are not pulled; history from a peer is listed as unavailable until
    /// its blocks arrive some other way). Empty means there is nothing more to ask for right now.
    pub fn missing_blocks(&self, theirs: &[HeadEntry], limit: usize) -> Result<Vec<Hash>> {
        let mut out: Vec<Hash> = Vec::new();
        let mut seen = HashSet::new();
        let mut push = |h: Hash, out: &mut Vec<Hash>| {
            if out.len() < limit && seen.insert(h) {
                out.push(h);
            }
        };
        for e in theirs {
            if out.len() >= limit {
                break;
            }
            let r = self.entry(e)?;
            let local = self.head(&e.id);
            if local == Some(r) {
                continue;
            }
            let stop = match local {
                Some(l) => self.ancestors(l)?,
                None => HashSet::new(),
            };
            let (_, missing) = self.walk_history(r, &stop)?;
            for m in missing {
                push(m, &mut out);
            }
            if self.has_block(&r) {
                let m = self.manifest(&r)?;
                if m.id != e.id {
                    return Err(Error::Invalid(format!(
                        "head {} is not a version of note {}",
                        e.head, e.id
                    )));
                }
                let mut tree = Vec::new();
                self.missing_in_tree(m.root_hash(), m.depth, &mut tree, limit)?;
                for h in tree {
                    push(h, &mut out);
                }
            }
        }
        Ok(out)
    }

    fn missing_in_tree(
        &self,
        hash: Hash,
        depth: u32,
        out: &mut Vec<Hash>,
        limit: usize,
    ) -> Result<()> {
        if out.len() >= limit {
            return Ok(());
        }
        if !self.has_block(&hash) {
            out.push(hash);
            return Ok(());
        }
        if depth == 0 {
            return Ok(());
        }
        for child in list_children(&self.get_block(&hash)?)? {
            self.missing_in_tree(child, depth - 1, out, limit)?;
        }
        Ok(())
    }

    // ---- moving blocks -----------------------------------------------------------------------------------------

    /// The listed blocks this copy has, as one byte string: `NBK1`, then per block `hash(32) | len(u32 LE) | bytes`.
    /// Blocks it lacks are skipped. Each block is read through the Storage Kit's verified `get`.
    pub fn export_blocks(&self, hashes: &[Hash]) -> Result<Vec<u8>> {
        let mut out = EXPORT_MAGIC.to_vec();
        for h in hashes.iter().take(MAX_EXPORT_HASHES) {
            if !self.has_block(h) {
                continue;
            }
            let bytes = self.get_block(h)?;
            if out.len() > EXPORT_MAGIC.len()
                && out.len() + RECORD_HEADER + bytes.len() > MAX_EXPORT_BYTES
            {
                break;
            }
            out.extend_from_slice(h.as_bytes());
            out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            out.extend_from_slice(&bytes);
        }
        Ok(out)
    }

    /// Verify every block of `export`, then store those this copy lacks. Moves no head.
    ///
    /// A malformed export, or one block whose bytes do not hash to the address it was sent under, is an error and **nothing
    /// is stored**.
    pub fn import_blocks(&mut self, export: &[u8]) -> Result<ImportReport> {
        if export.len() > MAX_IMPORT_BYTES + 4 + MAX_IMPORT_RECORDS * RECORD_HEADER {
            return Err(Error::BadExport("export is too large".into()));
        }
        if export.len() < 4 || &export[..4] != EXPORT_MAGIC {
            return Err(Error::BadExport("not a block export".into()));
        }
        let mut records: Vec<(Hash, &[u8])> = Vec::new();
        let mut pos = 4;
        let mut total = 0usize;
        while pos < export.len() {
            if records.len() >= MAX_IMPORT_RECORDS {
                return Err(Error::BadExport("too many blocks".into()));
            }
            if export.len() - pos < RECORD_HEADER {
                return Err(Error::BadExport("a record header runs past the end".into()));
            }
            let claimed = Hash::from_bytes(export[pos..pos + 32].try_into().expect("32 bytes"));
            let len = u32::from_le_bytes(export[pos + 32..pos + 36].try_into().expect("4 bytes"))
                as usize;
            pos += RECORD_HEADER;
            if len > MAX_BLOCK_BYTES {
                return Err(Error::BadExport(format!(
                    "a block of {len} bytes is over the limit"
                )));
            }
            if export.len() - pos < len {
                return Err(Error::BadExport("a block runs past the end".into()));
            }
            total += len;
            if total > MAX_IMPORT_BYTES {
                return Err(Error::BadExport("export holds too many bytes".into()));
            }
            records.push((claimed, &export[pos..pos + len]));
            pos += len;
        }
        // Check ALL of them before storing ANY.
        for (claimed, bytes) in &records {
            let actual = Hash::of(bytes);
            if actual != *claimed {
                return Err(Error::BadBlock {
                    claimed: claimed.to_hex(),
                    actual: actual.to_hex(),
                });
            }
        }
        let mut stored = 0;
        for (claimed, bytes) in &records {
            if self.has_block(claimed) {
                continue;
            }
            let got = self.store.put(bytes)?;
            debug_assert_eq!(got, *claimed);
            if got != *claimed {
                return Err(Error::Corrupt(
                    "the store filed a block under another address".into(),
                ));
            }
            stored += 1;
        }
        Ok(ImportReport {
            received: records.len() as u32,
            stored,
            bytes: total as u64,
        })
    }

    // ---- moving heads --------------------------------------------------------------------------------------------

    fn version(&self, addr: &Hash) -> Result<NoteVersion> {
        let m = self.manifest(addr)?;
        Ok(NoteVersion {
            manifest: addr.to_hex(),
            title: m.title.clone(),
            body: String::from_utf8_lossy(&self.read_body(&m)?).into_owned(),
            at_ms: m.at,
            by: m.by.clone(),
            deleted: m.deleted,
        })
    }

    fn conflict(&self, id: &str, local: Hash, remote: Hash) -> Result<Conflict> {
        let base = match self.common_ancestor(local, remote)? {
            Some(b) if self.tree_complete(&self.manifest(&b)?)? => Some(self.version(&b)?),
            _ => None,
        };
        Ok(Conflict {
            note_id: id.to_string(),
            local: self.version(&local)?,
            remote: self.version(&remote)?,
            base,
        })
    }

    /// Everything the new head needs is here: its manifest, the ancestors back to something this copy had, and its body.
    fn closure_present(&self, remote: Hash, local: Option<Hash>) -> Result<bool> {
        let stop = match local {
            Some(l) => self.ancestors(l)?,
            None => HashSet::new(),
        };
        let (_, missing) = self.walk_history(remote, &stop)?;
        if !missing.is_empty() {
            return Ok(false);
        }
        self.tree_complete(&self.manifest(&remote)?)
    }

    /// With the peer's blocks imported, decide each note: same, we are ahead, fast-forward, incomplete, or diverged.
    /// A fast-forward moves the head. A divergence is recorded (`pending_conflicts`) and returned, and moves nothing.
    pub fn apply_heads(&mut self, theirs: &[HeadEntry]) -> Result<ApplyReport> {
        let mut report = ApplyReport::default();
        for e in theirs {
            let r = self.entry(e)?;
            let id = e.id.as_str();
            let local = self.head(id);
            if local == Some(r) {
                report.up_to_date.push(id.to_string());
                continue;
            }
            if !self.has_block(&r) {
                report.incomplete.push(id.to_string());
                continue;
            }
            let rm = match self.manifest(&r) {
                Ok(m) if m.id == id => m,
                _ => {
                    report.rejected.push(id.to_string());
                    continue;
                }
            };
            if let Some(l) = local {
                if self.ancestors(l)?.contains(&r) {
                    report.local_ahead.push(id.to_string());
                    continue;
                }
            }
            if !self.closure_present(r, local)? {
                report.incomplete.push(id.to_string());
                continue;
            }
            let fast_forward = match local {
                None => true,
                Some(l) => self.ancestors(r)?.contains(&l),
            };
            if fast_forward {
                self.set_head(id, r)?;
                self.clear_conflict(id)?;
                report.fast_forwarded.push(id.to_string());
                continue;
            }
            let l = local.expect("diverged implies a local head");
            let lm = self.manifest(&l)?;
            if same_content(&lm, &rm) {
                // Two independent identical edits: nothing to decide. Both copies pick the smaller address, so they converge.
                if r.to_hex() < l.to_hex() {
                    self.set_head(id, r)?;
                    report.fast_forwarded.push(id.to_string());
                } else {
                    report.up_to_date.push(id.to_string());
                }
                self.clear_conflict(id)?;
                continue;
            }
            self.conflicts.insert(id.to_string(), r);
            self.save_conflicts()?;
            report.conflicts.push(self.conflict(id, l, r)?);
        }
        Ok(report)
    }

    fn clear_conflict(&mut self, id: &str) -> Result<()> {
        if self.conflicts.remove(id).is_some() {
            self.save_conflicts()?;
        }
        Ok(())
    }

    /// Conflicts still open. One that was settled some other way (a later sync fast-forwarded past it) is dropped here.
    pub fn pending_conflicts(&mut self) -> Result<Vec<Conflict>> {
        let mut out = Vec::new();
        let mut settled = Vec::new();
        for (id, r) in self.conflicts.clone() {
            let Some(l) = self.head(&id) else {
                settled.push(id);
                continue;
            };
            if l == r || !self.has_block(&r) || !self.has_block(&l) {
                settled.push(id);
                continue;
            }
            if self.ancestors(l)?.contains(&r) || self.ancestors(r)?.contains(&l) {
                settled.push(id);
                continue;
            }
            match self.conflict(&id, l, r) {
                Ok(c) => out.push(c),
                Err(_) => settled.push(id), // the other version is incomplete here: it will be reported again after a sync
            }
        }
        for id in settled {
            self.clear_conflict(&id)?;
        }
        Ok(out)
    }

    /// Apply the app's answer to the pending conflict on `id` against the peer version `remote`.
    pub fn resolve_conflict(&mut self, id: &str, remote: &Hash, how: &Resolution) -> Result<()> {
        let l = self
            .head(id)
            .ok_or_else(|| Error::NoSuchNote(id.to_string()))?;
        if self.conflicts.get(id) != Some(remote) || !self.has_block(remote) {
            return Err(Error::NoConflict(id.to_string()));
        }
        let lm = self.manifest(&l)?;
        let rm = self.manifest(remote)?;
        if !self.tree_complete(&rm)? {
            return Err(Error::VersionUnavailable(remote.to_hex()));
        }
        let at = self.now();
        let by = self.device().to_string();
        match how {
            Resolution::KeepLocal => {
                let a = self.write_manifest_for_body(
                    id,
                    &lm.title,
                    lm.deleted,
                    Body::of(&lm),
                    vec![l, *remote],
                    at,
                    &by,
                )?;
                self.set_head(id, a)?;
            }
            Resolution::TakeRemote => {
                let a = self.write_manifest_for_body(
                    id,
                    &rm.title,
                    rm.deleted,
                    Body::of(&rm),
                    vec![l, *remote],
                    at,
                    &by,
                )?;
                self.set_head(id, a)?;
            }
            Resolution::Merged { title, body } => {
                let a = self.write_manifest(
                    id,
                    title,
                    false,
                    body.as_bytes(),
                    vec![l, *remote],
                    at,
                    &by,
                )?;
                self.set_head(id, a)?;
            }
            Resolution::KeepBoth { winner } => {
                let (win, lose, lose_m) = match winner {
                    Side::Local => (l, *remote, &rm),
                    Side::Remote => (*remote, l, &lm),
                };
                if win != l {
                    self.set_head(id, win)?;
                }
                if !lose_m.deleted {
                    self.keep_as_copy(id, &lose, lose_m)?;
                }
            }
        }
        self.clear_conflict(id)
    }

    /// The losing version of a `KeepBoth` becomes a new note whose every byte is a function of the loser alone, so the
    /// other copy, deciding the same way, writes the identical manifest and the two never diverge over the copy.
    fn keep_as_copy(&mut self, id: &str, loser: &Hash, m: &Manifest) -> Result<()> {
        let digest = Hash::of(
            format!(
                "slash-builder/notes-rust/conflict-copy/v1\n{id}\n{}",
                loser.to_hex()
            )
            .as_bytes(),
        )
        .to_hex();
        let cid = format!("cf{}", &digest[..16]);
        if self.head(&cid).is_some() {
            return Ok(());
        }
        let title = format!("{} (conflict from {})", m.title, m.by);
        let a =
            self.write_manifest_for_body(&cid, &title, false, Body::of(m), vec![], m.at, &m.by)?;
        self.set_head(&cid, a)
    }
}

/// Same title, same body, same deletion state: the two versions say the same thing.
fn same_content(a: &Manifest, b: &Manifest) -> bool {
    a.deleted == b.deleted && a.title == b.title && a.root == b.root && a.len == b.len
}
