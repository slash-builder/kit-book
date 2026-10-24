//! What `kill -9` of the Rust half does to the store. The parent starts this same test binary as a child that writes notes
//! as fast as it can, kills it with SIGKILL at a random moment, reopens the directories and checks that every note the head
//! index names can be read in full. (A head is written last and by rename, so a kill leaves orphan blocks at worst.)

mod common;

use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

use common::*;

const CHILD_ENV: &str = "NOTES_CORE_KILL_CHILD";

/// The child: runs only when the parent set the variable; otherwise a no-op.
#[test]
fn child_writer() {
    let Ok(root) = std::env::var(CHILD_ENV) else {
        return;
    };
    let root = PathBuf::from(root);
    let engine =
        notes_core::Engine::open(&snapshot_json(&root, "dddddddd"), "home", "victim").unwrap();
    let mut i = 0u64;
    loop {
        let n = engine
            .create_note(&format!("note {i}"), &text(150_000, i))
            .unwrap();
        for k in 0..3 {
            engine
                .save_note(&n.id, &format!("note {i}"), &text(150_000, i * 10 + k + 1))
                .unwrap();
        }
        i += 1;
        std::fs::write(root.join("progress"), i.to_string()).unwrap();
    }
}

#[test]
fn a_killed_writer_leaves_a_store_that_opens_and_reads() {
    if std::env::var(CHILD_ENV).is_ok() {
        return; // we ARE the child process's copy of this test; the work is in child_writer
    }
    for (round, delay_ms) in [120u64, 330, 700].into_iter().enumerate() {
        let root = tempfile::tempdir().unwrap();
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["child_writer", "--exact", "--nocapture", "--test-threads=1"])
            .env(CHILD_ENV, root.path())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        std::thread::sleep(Duration::from_millis(delay_ms));
        child.kill().unwrap(); // SIGKILL on Unix: no destructors, no flush
        child.wait().unwrap();

        let engine = notes_core::Engine::open(
            &snapshot_json(root.path(), "dddddddd"),
            "home",
            "after-the-kill",
        )
        .unwrap_or_else(|e| panic!("round {round}: reopening after kill -9 failed: {e}"));
        let notes = engine.list_notes().unwrap();
        for n in &notes {
            let full = engine
                .get_note(&n.id)
                .unwrap_or_else(|e| panic!("round {round}: note {} unreadable: {e}", n.id));
            assert_eq!(full.body.len(), 150_000);
            for v in engine.list_versions(&n.id, 50).unwrap() {
                assert!(
                    v.available,
                    "round {round}: a version whose blocks are missing"
                );
            }
        }
        // and the store takes new writes
        engine.create_note("after", "the kill").unwrap();
        println!(
            "round {round}: killed after {delay_ms} ms, {} notes intact, {} blocks",
            notes.len(),
            engine.stats().block_count
        );
    }
}
