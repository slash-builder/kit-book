//! Notes on a Storage Kit partition.
//!
//! * A note **version** is the body fragmented into content-addressed blocks (Storage Kit `build_fragment_tree`) plus a
//!   **manifest** block (JSON) that names the tree root and the versions it follows (`parents`). The manifest is itself a
//!   block, so a version's address is the hash of its manifest bytes, and history is a DAG.
//! * The **head index** (`note id -> manifest address`) is the one mutable thing. The Storage Kit has no mutable store
//!   implementation, so this app keeps it as `heads-<partition>.json` in its data directory, written by rename. It is the
//!   only file that moves a note: blocks are written first, the head last, so a crash leaves orphan blocks, never a head
//!   that points at nothing.
//! * Restoring an old version writes ONE new manifest that points at the old body's existing blocks. No body block is
//!   written. That is content addressing at work, and `tests/store.rs` counts it.

use std::collections::{BTreeMap, HashSet};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use application_kit::AdoptedContext;
use serde::{Deserialize, Serialize};
use storage_kit::fragment::CHILD_REF_LEN;
use storage_kit::{
    build_fragment_tree, read_fragment_tree, ChunkingProfile, Hash, ImmutableStore, PartitionId,
    PartitionStore, RootType,
};

use crate::error::{Error, Result};
use crate::namespace::{check_label, Namespace};

/// Folder under the app's `data` directory that is the Storage Kit store root.
pub const BLOCKS_DIR: &str = "blocks";
/// Manifest schema number.
pub const SCHEMA: u32 = 1;
/// Most list-node levels a manifest may claim. With the Kit's fixed 1024-child fanout, 4 levels is 2^40 leaves.
pub const MAX_DEPTH: u32 = 6;
pub const MAX_TITLE_BYTES: usize = 1024;
/// The default `maxNoteBytes` (the owner can change it in `config.json`; this side only reads it).
pub const DEFAULT_MAX_NOTE_BYTES: u64 = 32 * 1024 * 1024;

/// One file per partition: the Application Kit's directories are per OS user, not per account.
pub fn heads_file_name(partition: &PartitionId) -> String {
    format!("heads-{}.json", partition.to_hex())
}

pub fn conflicts_file_name(partition: &PartitionId) -> String {
    format!("conflicts-{}.json", partition.to_hex())
}

/// `^[a-z0-9]{4,40}$` (the notepad demo's note id pattern).
pub fn is_note_id(s: &str) -> bool {
    (4..=40).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
}

pub fn parse_hash(hex: &str) -> Result<Hash> {
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
        return Err(Error::Invalid(format!("not a block hash: {hex:?}")));
    }
    Ok(Hash::from_hex(hex)?)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    pub schema: u32,
    pub id: String,
    pub title: String,
    /// A tombstone: the note was deleted in this version. The body is empty.
    pub deleted: bool,
    /// Milliseconds since the Unix epoch (UTC) when this copy wrote the version.
    pub at: i64,
    /// The device that wrote it.
    pub by: String,
    /// Fragment tree root hash (hex).
    pub root: String,
    pub root_type: RootType,
    pub depth: u32,
    pub len: u64,
    pub profile: ChunkingProfile,
    /// Manifest addresses (hex) this version follows: none for the first, one for an edit, two for a merge.
    pub parents: Vec<String>,
}

impl Manifest {
    /// What a manifest from a peer must satisfy before this copy will build anything on it.
    pub fn check(&self) -> Result<()> {
        let bad = |m: &str| Err(Error::Corrupt(format!("manifest: {m}")));
        if self.schema != SCHEMA {
            return bad("unknown schema");
        }
        if !is_note_id(&self.id) {
            return bad("bad note id");
        }
        if self.title.len() > MAX_TITLE_BYTES {
            return bad("title too long");
        }
        if check_label("device", &self.by).is_err() {
            return bad("bad device name");
        }
        if parse_hash(&self.root).is_err() || self.parents.len() > 2 || self.parents.iter().any(|p| parse_hash(p).is_err()) {
            return bad("bad hash");
        }
        if self.depth > MAX_DEPTH || (self.depth == 0) != (self.root_type == RootType::Leaf) {
            return bad("depth does not match root type");
        }
        Ok(())
    }

    pub fn root_hash(&self) -> Hash {
        Hash::from_hex(&self.root).expect("checked")
    }

    pub fn parent_hashes(&self) -> Vec<Hash> {
        self.parents.iter().map(|p| Hash::from_hex(p).expect("checked")).collect()
    }
}

/// The body part of a manifest: where the fragment tree is and how big it is.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Body {
    pub root: Hash,
    pub root_type: RootType,
    pub depth: u32,
    pub len: u64,
}

impl Body {
    pub(crate) fn of(m: &Manifest) -> Body {
        Body { root: m.root_hash(), root_type: m.root_type, depth: m.depth, len: m.len }
    }
}

#[derive(Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
struct IndexFile {
    schema: u32,
    /// note id -> hex hash
    heads: BTreeMap<String, String>,
}

/// Child hashes of a list node body (`hash(32) | len(8)` per child). The Storage Kit has no public helper for this, and
/// `walk_hashes` needs every block present, which a half-synced tree is not.
pub(crate) fn list_children(body: &[u8]) -> Result<Vec<Hash>> {
    if body.len() % CHILD_REF_LEN != 0 {
        return Err(Error::Corrupt("list node length".into()));
    }
    Ok(body
        .chunks(CHILD_REF_LEN)
        .map(|rec| Hash::from_bytes(rec[..32].try_into().expect("32 bytes")))
        .collect())
}

pub struct NotesStore {
    pub(crate) store: PartitionStore,
    ns: Namespace,
    heads_path: PathBuf,
    pub(crate) conflicts_path: PathBuf,
    heads: BTreeMap<String, Hash>,
    pub(crate) conflicts: BTreeMap<String, Hash>,
    profile: ChunkingProfile,
    device: String,
    clock: Box<dyn Fn() -> i64 + Send>,
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

/// Writes `bytes` to `path` so a crash never leaves half a file: temp file, flush to disk, rename.
pub(crate) fn write_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let tmp = path.with_extension("json.tmp");
    {
        let mut f = File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path)?;
    Ok(())
}

fn load_index(path: &Path) -> Result<BTreeMap<String, Hash>> {
    let text = match fs::read(path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(BTreeMap::new()),
        Err(e) => return Err(e.into()),
    };
    // A damaged index is an error, never silently replaced (the same rule as the Kit's config.json).
    let file: IndexFile = serde_json::from_slice(&text)
        .map_err(|e| Error::Corrupt(format!("{}: {e}", path.display())))?;
    let mut out = BTreeMap::new();
    for (k, v) in file.heads {
        if !is_note_id(&k) {
            return Err(Error::Corrupt(format!("{}: bad note id {k:?}", path.display())));
        }
        out.insert(k, parse_hash(&v)?);
    }
    Ok(out)
}

impl NotesStore {
    /// Open the app's slice of the Storage Kit inside an adopted context: store root `<data>/blocks`, head index
    /// `<data>/heads-<partition>.json`. Creates directories under `data` only.
    pub fn open(ctx: &AdoptedContext, ns: Namespace, device: &str) -> Result<NotesStore> {
        check_label("device", device)?;
        let root = ctx.create_data_dir(BLOCKS_DIR)?;
        let partition = ns.partition();
        let store = PartitionStore::open(&root, partition)?;
        let heads_path = ctx.data_file(&heads_file_name(&partition))?;
        let conflicts_path = ctx.data_file(&conflicts_file_name(&partition))?;
        let heads = load_index(&heads_path)?;
        let conflicts = load_index(&conflicts_path)?;
        Ok(NotesStore {
            store,
            ns,
            heads_path,
            conflicts_path,
            heads,
            conflicts,
            profile: ChunkingProfile::default(),
            device: device.to_string(),
            clock: Box::new(now_ms),
        })
    }

    /// Replace the clock (tests, so "the later edit" is not a race).
    pub fn set_clock(&mut self, clock: Box<dyn Fn() -> i64 + Send>) {
        self.clock = clock;
    }

    pub fn namespace(&self) -> &Namespace {
        &self.ns
    }

    pub fn device(&self) -> &str {
        &self.device
    }

    pub fn partition(&self) -> PartitionId {
        self.store.partition_id()
    }

    pub fn now(&self) -> i64 {
        (self.clock)()
    }

    pub fn heads(&self) -> &BTreeMap<String, Hash> {
        &self.heads
    }

    pub fn head(&self, id: &str) -> Option<Hash> {
        self.heads.get(id).copied()
    }

    /// How many distinct blocks (chunks, list nodes and manifests) the partition holds.
    pub fn block_count(&self) -> usize {
        self.store.all_hashes().len()
    }

    pub fn has_block(&self, hash: &Hash) -> bool {
        self.store.has(hash)
    }

    pub fn get_block(&self, hash: &Hash) -> Result<Vec<u8>> {
        Ok(self.store.get(hash)?)
    }

    // ---- manifests and bodies ------------------------------------------------------------------------------

    pub fn manifest(&self, addr: &Hash) -> Result<Manifest> {
        let bytes = self.store.get(addr)?;
        let m: Manifest = serde_json::from_slice(&bytes)
            .map_err(|e| Error::Corrupt(format!("manifest {addr}: {e}")))?;
        m.check()?;
        Ok(m)
    }

    pub fn read_body(&self, m: &Manifest) -> Result<Vec<u8>> {
        Ok(read_fragment_tree(m.root_hash(), m.depth, &self.store)?)
    }

    /// The first `max` bytes of the body, reading only the leftmost leaf (a list's preview does not read a 10 MiB note).
    pub fn read_prefix(&self, m: &Manifest, max: usize) -> Result<Vec<u8>> {
        let mut hash = m.root_hash();
        for _ in 0..m.depth {
            let children = list_children(&self.store.get(&hash)?)?;
            hash = *children.first().ok_or_else(|| Error::Corrupt("empty list node".into()))?;
        }
        let mut bytes = self.store.get(&hash)?;
        bytes.truncate(max);
        Ok(bytes)
    }

    /// True when every block of the version's body is present on this copy.
    pub fn tree_complete(&self, m: &Manifest) -> Result<bool> {
        self.subtree_complete(m.root_hash(), m.depth)
    }

    fn subtree_complete(&self, hash: Hash, depth: u32) -> Result<bool> {
        if !self.store.has(&hash) {
            return Ok(false);
        }
        if depth == 0 {
            return Ok(true);
        }
        for child in list_children(&self.store.get(&hash)?)? {
            if !self.subtree_complete(child, depth - 1)? {
                return Ok(false);
            }
        }
        Ok(true)
    }

    /// `start` and every manifest reachable through `parents` that is present here, stopping at (and not descending
    /// from) any hash in `stop`. A missing manifest is returned in the second list.
    pub fn walk_history(
        &self,
        start: Hash,
        stop: &HashSet<Hash>,
    ) -> Result<(Vec<Hash>, Vec<Hash>)> {
        const LIMIT: usize = 200_000;
        let mut seen = HashSet::new();
        let mut order = Vec::new();
        let mut missing = Vec::new();
        let mut todo = vec![start];
        while let Some(h) = todo.pop() {
            if !seen.insert(h) {
                continue;
            }
            if seen.len() > LIMIT {
                return Err(Error::Corrupt("history is implausibly long".into()));
            }
            if stop.contains(&h) {
                order.push(h);
                continue;
            }
            if !self.store.has(&h) {
                missing.push(h);
                continue;
            }
            order.push(h);
            todo.extend(self.manifest(&h)?.parent_hashes());
        }
        Ok((order, missing))
    }

    /// Every manifest reachable from `start` through present manifests (including `start`).
    pub fn ancestors(&self, start: Hash) -> Result<HashSet<Hash>> {
        Ok(self.walk_history(start, &HashSet::new())?.0.into_iter().collect())
    }

    /// The first version reachable from `remote` (breadth first) that is also an ancestor of `local`.
    pub fn common_ancestor(&self, local: Hash, remote: Hash) -> Result<Option<Hash>> {
        let ours = self.ancestors(local)?;
        let mut queue = std::collections::VecDeque::from([remote]);
        let mut seen = HashSet::new();
        while let Some(h) = queue.pop_front() {
            if !seen.insert(h) || !self.store.has(&h) {
                continue;
            }
            if ours.contains(&h) {
                return Ok(Some(h));
            }
            queue.extend(self.manifest(&h)?.parent_hashes());
        }
        Ok(None)
    }

    // ---- writing -------------------------------------------------------------------------------------------

    /// Fragment `body` into the store and write a manifest block following `parents`. Does NOT move any head.
    pub(crate) fn write_manifest(
        &mut self,
        id: &str,
        title: &str,
        deleted: bool,
        body: &[u8],
        parents: Vec<Hash>,
        at: i64,
        by: &str,
    ) -> Result<Hash> {
        if !is_note_id(id) {
            return Err(Error::Invalid(format!("not a note id: {id:?}")));
        }
        let tree = build_fragment_tree(body, &self.profile, &mut self.store)?;
        self.write_manifest_for_tree(id, title, deleted, &tree, parents, at, by)
    }

    pub(crate) fn write_manifest_for_tree(
        &mut self,
        id: &str,
        title: &str,
        deleted: bool,
        tree: &storage_kit::FragmentTree,
        parents: Vec<Hash>,
        at: i64,
        by: &str,
    ) -> Result<Hash> {
        // `tree.root` is an `Address`, which the Storage Kit holds outside its freeze; `.hash` is the part it promises.
        let body = Body { root: tree.root.hash, root_type: tree.root_type, depth: tree.depth, len: tree.uncompressed_len };
        self.write_manifest_for_body(id, title, deleted, body, parents, at, by)
    }

    pub(crate) fn write_manifest_for_body(
        &mut self,
        id: &str,
        title: &str,
        deleted: bool,
        body: Body,
        parents: Vec<Hash>,
        at: i64,
        by: &str,
    ) -> Result<Hash> {
        let m = Manifest {
            schema: SCHEMA,
            id: id.to_string(),
            title: title.to_string(),
            deleted,
            at,
            by: by.to_string(),
            root: body.root.to_hex(),
            root_type: body.root_type,
            depth: body.depth,
            len: body.len,
            profile: self.profile.clone(),
            parents: parents.iter().map(Hash::to_hex).collect(),
        };
        m.check()?;
        Ok(self.store.put(&serde_json::to_vec(&m)?)?)
    }

    /// Flush the active pack to disk. The Storage Kit's `put` only hands bytes to the operating system (its "flush" is a
    /// no-op on a `File`), so without this a power cut could keep a head that names blocks the disk never received.
    /// A process kill does not need it. Best effort on the file the Kit documents: `<partition>/active/active.pack`.
    fn sync_blocks(&self) {
        if let Ok(f) = File::open(self.store.partition_root().join("active").join("active.pack")) {
            let _ = f.sync_all();
        }
    }

    pub(crate) fn set_head(&mut self, id: &str, addr: Hash) -> Result<()> {
        self.sync_blocks(); // blocks first, then the head that names them
        let before = self.heads.insert(id.to_string(), addr);
        if let Err(e) = self.save_heads() {
            match before {
                Some(b) => self.heads.insert(id.to_string(), b),
                None => self.heads.remove(id),
            };
            return Err(e);
        }
        Ok(())
    }

    fn save_heads(&self) -> Result<()> {
        save_index(&self.heads_path, &self.heads)
    }

    pub(crate) fn save_conflicts(&self) -> Result<()> {
        save_index(&self.conflicts_path, &self.conflicts)
    }

    /// Store a new version of note `id` (created when `parent` is none) and make it the head. An unchanged title and body
    /// returns the current head and writes nothing.
    pub fn save(&mut self, id: &str, title: &str, body: &[u8], limit: u64) -> Result<Hash> {
        if body.len() as u64 > limit {
            return Err(Error::TooLarge { len: body.len() as u64, limit });
        }
        let head = self.head(id);
        let tree = build_fragment_tree(body, &self.profile, &mut self.store)?;
        if let Some(h) = head {
            let cur = self.manifest(&h)?;
            if !cur.deleted
                && cur.title == title
                && cur.root == tree.root.hash.to_hex()
                && cur.len == tree.uncompressed_len
            {
                return Ok(h);
            }
        }
        let at = self.now();
        let by = self.device.clone();
        let addr = self.write_manifest_for_tree(id, title, false, &tree, head.into_iter().collect(), at, &by)?;
        self.set_head(id, addr)?;
        Ok(addr)
    }

    /// Delete = a tombstone version (history stays; the note disappears from the list).
    pub fn delete(&mut self, id: &str) -> Result<Hash> {
        let head = self.head(id).ok_or_else(|| Error::NoSuchNote(id.to_string()))?;
        let cur = self.manifest(&head)?;
        if cur.deleted {
            return Ok(head);
        }
        let at = self.now();
        let by = self.device.clone();
        let addr = self.write_manifest(id, &cur.title, true, &[], vec![head], at, &by)?;
        self.set_head(id, addr)?;
        Ok(addr)
    }

    /// Make version `version` of `id` the current one by writing a new manifest that reuses its body blocks.
    /// Writes no body block. Fails with `VersionUnavailable` when the body is not fully on this copy.
    pub fn restore(&mut self, id: &str, version: &Hash) -> Result<Hash> {
        let head = self.head(id).ok_or_else(|| Error::NoSuchNote(id.to_string()))?;
        if !self.store.has(version) {
            return Err(Error::NoSuchVersion(version.to_hex()));
        }
        let old = self.manifest(version)?;
        if old.id != id {
            return Err(Error::NoSuchVersion(version.to_hex()));
        }
        if !self.tree_complete(&old)? {
            return Err(Error::VersionUnavailable(version.to_hex()));
        }
        let cur = self.manifest(&head)?;
        if !cur.deleted && cur.title == old.title && cur.root == old.root && cur.len == old.len {
            return Ok(head); // already the current content
        }
        let at = self.now();
        let by = self.device.clone();
        let addr = self.write_manifest_for_body(id, &old.title, old.deleted, Body::of(&old), vec![head], at, &by)?;
        self.set_head(id, addr)?;
        Ok(addr)
    }
}

fn save_index(path: &Path, map: &BTreeMap<String, Hash>) -> Result<()> {
    let file = IndexFile {
        schema: 1,
        heads: map.iter().map(|(k, v)| (k.clone(), v.to_hex())).collect(),
    };
    write_atomic(path, &serde_json::to_vec_pretty(&file)?)
}
