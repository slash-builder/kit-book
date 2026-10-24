//! Shared helpers for the integration tests: a scratch "app", snapshots like the Dart owner would pass, and a sync driver
//! that does what the Dart transport does (ask, export, import, apply) with a function call as the wire.
#![allow(dead_code)]

use std::path::{Path, PathBuf};

use notes_core::types::{ApplyReport, HeadEntry};
use notes_core::Engine;
use serde_json::json;
use tempfile::TempDir;

pub const APP: &str = "dev.demo.notes-rust";

/// A scratch directory standing in for one running copy: its own data/config/state/cache/runtime and roster.
pub struct Copy {
    pub dir: TempDir,
    pub engine: Engine,
    pub instance: String,
}

pub fn snapshot_json(root: &Path, instance: &str) -> String {
    let d = |k: &str| root.join(APP).join(k).to_str().unwrap().to_string();
    json!({
        "schema": 1, "appId": APP, "instance": instance, "mode": "real", "scratch": true,
        "dirs": {"data": d("data"), "config": d("config"), "state": d("state"), "cache": d("cache"), "runtime": d("runtime")},
        "roster": root.join("roster").to_str().unwrap(),
    })
    .to_string()
}

pub fn open_copy(device: &str, instance: &str) -> Copy {
    let dir = TempDir::new().unwrap();
    let engine = Engine::open(&snapshot_json(dir.path(), instance), "home", device).unwrap();
    Copy { dir, engine, instance: instance.to_string() }
}

impl Copy {
    pub fn data(&self) -> PathBuf {
        self.dir.path().join(APP).join("data")
    }
    pub fn config(&self) -> PathBuf {
        self.dir.path().join(APP).join("config")
    }
    /// Reopen the same directories (a restart).
    pub fn reopen(self, device: &str) -> Copy {
        let Copy { dir, engine, instance } = self;
        drop(engine);
        let engine = Engine::open(&snapshot_json(dir.path(), &instance), "home", device).unwrap();
        Copy { dir, engine, instance }
    }
}

/// Pseudo-random printable text of exactly `len` bytes (a fixed seed, so runs repeat).
pub fn text(len: usize, seed: u64) -> String {
    let mut x = seed.wrapping_mul(0x9E3779B97F4A7C15) | 1;
    let alphabet = b"abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n";
    let mut out = Vec::with_capacity(len);
    for _ in 0..len {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        out.push(alphabet[(x % alphabet.len() as u64) as usize]);
    }
    String::from_utf8(out).unwrap()
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Wire {
    /// Export bytes carried (what a transport would split into parts).
    pub bytes: usize,
    pub rounds: usize,
    pub blocks: usize,
}

/// `to` catches up with `from`'s heads: the loop the Dart sync hook runs. `tamper` may change an export in flight.
pub fn pull(
    to: &Engine,
    from: &Engine,
    tamper: Option<&dyn Fn(&mut Vec<u8>)>,
) -> Result<(Wire, ApplyReport), notes_core::Error> {
    let theirs: Vec<HeadEntry> = from.heads();
    let mut wire = Wire::default();
    for _ in 0..64 {
        let missing = to.missing_blocks(&theirs, 512)?;
        if missing.is_empty() {
            break;
        }
        wire.rounds += 1;
        let mut progressed = false;
        for batch in missing.chunks(32) {
            let mut export = from.export_blocks(batch)?;
            if let Some(t) = tamper {
                t(&mut export);
            }
            wire.bytes += export.len();
            let r = to.import_blocks(&export)?;
            wire.blocks += r.stored as usize;
            progressed |= r.stored > 0;
        }
        if !progressed {
            break;
        }
    }
    let report = to.apply_heads(&theirs)?;
    Ok((wire, report))
}

/// Both directions until quiet (one round is enough unless a resolution wrote a new version).
pub fn sync_both(a: &Engine, b: &Engine) {
    for _ in 0..3 {
        pull(a, b, None).unwrap();
        pull(b, a, None).unwrap();
        if a.heads_digest() == b.heads_digest() {
            return;
        }
    }
}
