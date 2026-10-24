//! The sync primitive between two copies: convergence, how little a small edit moves, tamper refusal, conflicts.

mod common;

use common::*;
use notes_core::types::{Resolution, Side};
use notes_core::Error;

fn two() -> (Copy, Copy) {
    (open_copy("laptop", "aaaaaaa1"), open_copy("desktop", "bbbbbbb2"))
}

#[test]
fn a_new_copy_catches_up_and_both_end_with_the_same_digest() {
    let (a, b) = two();
    let n1 = a.engine.create_note("One", "first").unwrap();
    let n2 = a.engine.create_note("Two", &text(150_000, 3)).unwrap();
    assert_ne!(a.engine.heads_digest(), b.engine.heads_digest());

    let (wire, report) = pull(&b.engine, &a.engine, None).unwrap();
    assert_eq!(report.fast_forwarded.len(), 2);
    assert!(report.conflicts.is_empty() && report.incomplete.is_empty());
    assert!(wire.rounds >= 2, "manifest, then list node, then chunks: {wire:?}");
    assert_eq!(b.engine.get_note(&n1.id).unwrap().body, "first");
    assert_eq!(b.engine.get_note(&n2.id).unwrap().body.len(), 150_000);
    assert_eq!(a.engine.heads_digest(), b.engine.heads_digest());

    // a second pull has nothing to ask for
    let (wire, report) = pull(&b.engine, &a.engine, None).unwrap();
    assert_eq!((wire.rounds, wire.bytes), (0, 0));
    assert_eq!(report.up_to_date.len(), 2);
}

#[test]
fn a_one_byte_edit_of_a_10_mib_note_moves_a_small_fraction_of_the_body() {
    let (a, b) = two();
    let body = text(10 * 1024 * 1024, 7);
    let n = a.engine.create_note("Big", &body).unwrap();

    let (cold, _) = pull(&b.engine, &a.engine, None).unwrap();
    assert!(cold.bytes > body.len() * 9 / 10, "a cold sync carries the body: {cold:?}");
    assert_eq!(b.engine.get_note(&n.id).unwrap().body.len(), body.len());

    // change ONE byte in the middle
    let mut bytes = body.clone().into_bytes();
    bytes[5 * 1024 * 1024] = if bytes[5 * 1024 * 1024] == b'q' { b'z' } else { b'q' };
    let edited = String::from_utf8(bytes).unwrap();
    a.engine.save_note(&n.id, "Big", &edited).unwrap();

    let (warm, report) = pull(&b.engine, &a.engine, None).unwrap();
    assert_eq!(report.fast_forwarded, vec![n.id.clone()]);
    assert_eq!(b.engine.get_note(&n.id).unwrap().body, edited);
    // manifest + the root list node (544 children x 40 bytes) + the one or two chunks the byte fell in
    assert!(warm.blocks <= 5, "{warm:?}");
    assert!(warm.bytes < 200 * 1024, "one byte moved {} bytes of a {} byte body", warm.bytes, body.len());
    println!("cold sync: {} bytes in {} blocks; one-byte edit: {} bytes in {} blocks ({} rounds)", cold.bytes, cold.blocks, warm.bytes, warm.blocks, warm.rounds);
}

#[test]
fn a_tampered_block_is_refused_and_nothing_changes() {
    let (a, b) = two();
    let n = a.engine.create_note("Mine", &text(120_000, 5)).unwrap();
    let digest_before = b.engine.heads_digest();
    let blocks_before = b.engine.stats().block_count;

    // Flip one byte inside the first block's payload, whichever block (manifest, list node, chunk) comes first.
    let flip = |export: &mut Vec<u8>| {
        let n = export.len();
        export[n - 1] ^= 0x01;
    };
    let err = pull(&b.engine, &a.engine, Some(&flip)).unwrap_err();
    assert!(matches!(err, Error::BadBlock { .. }), "{err}");
    assert_eq!(err.code(), "bad_block");
    assert_eq!(b.engine.heads_digest(), digest_before, "the head did not move");
    assert_eq!(b.engine.stats().block_count, blocks_before, "nothing was stored");
    assert!(b.engine.list_notes().unwrap().is_empty());

    // an honest retry works
    pull(&b.engine, &a.engine, None).unwrap();
    assert_eq!(b.engine.get_note(&n.id).unwrap().body.len(), 120_000);
}

#[test]
fn one_bad_block_in_an_export_stores_none_of_the_others() {
    let (a, b) = two();
    a.engine.create_note("Mine", &text(150_000, 6)).unwrap();
    // a third copy gets the manifest and the root list node honestly, then receives a multi-block chunk export with its last block damaged
    let _ = &b;
    let c = open_copy("tablet", "ccccccc3");
    let theirs = a.engine.heads();
    // first round: manifest
    let first = c.engine.missing_blocks(&theirs, 512).unwrap();
    c.engine.import_blocks(&a.engine.export_blocks(&first).unwrap()).unwrap();
    let second = c.engine.missing_blocks(&theirs, 512).unwrap();
    c.engine.import_blocks(&a.engine.export_blocks(&second).unwrap()).unwrap();
    let chunks = c.engine.missing_blocks(&theirs, 512).unwrap();
    assert!(chunks.len() > 3);
    let mut export = a.engine.export_blocks(&chunks).unwrap();
    let before = c.engine.stats().block_count;
    let last = export.len() - 1;
    export[last] ^= 0xff; // damage only the LAST block
    assert!(c.engine.import_blocks(&export).is_err());
    assert_eq!(c.engine.stats().block_count, before, "the earlier, honest blocks of the same export were not stored either");
}

#[test]
fn malformed_exports_are_refused_before_anything_is_stored() {
    let (a, b) = two();
    a.engine.create_note("x", "y").unwrap();
    let missing = b.engine.missing_blocks(&a.engine.heads(), 10).unwrap();
    let good = a.engine.export_blocks(&missing).unwrap();
    let before = b.engine.stats().block_count;
    let mut bad_magic = good.clone();
    bad_magic[0] = b'X';
    let truncated = good[..good.len() - 3].to_vec();
    let mut huge = good.clone();
    huge[4 + 32..4 + 36].copy_from_slice(&u32::MAX.to_le_bytes());
    for (name, bytes) in [("magic", bad_magic), ("truncated", truncated), ("huge length", huge), ("empty", vec![]), ("header only", good[..8].to_vec())] {
        let err = b.engine.import_blocks(&bytes).unwrap_err();
        assert_eq!(err.code(), "bad_export", "{name}: {err}");
    }
    assert_eq!(b.engine.stats().block_count, before);
    // an export with no records is fine and stores nothing
    assert_eq!(b.engine.import_blocks(b"NBK1").unwrap().stored, 0);
}

#[test]
fn heads_do_not_move_until_the_blocks_are_here() {
    let (a, b) = two();
    let n = a.engine.create_note("x", &text(50_000, 9)).unwrap();
    let report = b.engine.apply_heads(&a.engine.heads()).unwrap();
    assert_eq!(report.incomplete, vec![n.id.clone()]);
    assert!(b.engine.list_notes().unwrap().is_empty());
}

#[test]
fn a_peer_head_that_is_not_a_version_of_that_note_is_rejected() {
    let (a, b) = two();
    let n1 = a.engine.create_note("one", "1").unwrap();
    let n2 = a.engine.create_note("two", "2").unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    // claim note 1's head for note 2's id
    let lie = vec![notes_core::types::HeadEntry { id: n2.id.clone(), head: n1.head.clone() }];
    assert!(b.engine.missing_blocks(&lie, 10).is_err());
    let report = b.engine.apply_heads(&lie).unwrap();
    assert_eq!(report.rejected, vec![n2.id.clone()]);
    assert_eq!(b.engine.get_note(&n2.id).unwrap().body, "2");
}

#[test]
fn whoever_is_ahead_is_told_so_and_nothing_moves_backwards() {
    let (a, b) = two();
    let n = a.engine.create_note("n", "v1").unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    a.engine.save_note(&n.id, "n", "v2").unwrap();
    // a pulls from b, which is behind
    let (_, report) = pull(&a.engine, &b.engine, None).unwrap();
    assert_eq!(report.local_ahead, vec![n.id.clone()]);
    assert_eq!(a.engine.get_note(&n.id).unwrap().body, "v2");
}

#[test]
fn two_edits_of_one_note_are_a_conflict_with_both_versions_and_the_core_does_not_merge() {
    let (a, b) = two();
    a.engine.set_clock(Box::new(|| 1_000));
    b.engine.set_clock(Box::new(|| 2_000));
    let n = a.engine.create_note("Plan", "base\n").unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    a.engine.save_note(&n.id, "Plan", "base\nfrom laptop\n").unwrap();
    b.engine.save_note(&n.id, "Plan", "base\nfrom desktop\n").unwrap();

    let (_, report) = pull(&a.engine, &b.engine, None).unwrap();
    assert_eq!(report.conflicts.len(), 1);
    let c = &report.conflicts[0];
    assert_eq!(c.note_id, n.id);
    assert_eq!((c.local.body.as_str(), c.local.by.as_str()), ("base\nfrom laptop\n", "laptop"));
    assert_eq!((c.remote.body.as_str(), c.remote.by.as_str()), ("base\nfrom desktop\n", "desktop"));
    assert_eq!(c.base.as_ref().unwrap().body, "base\n");
    // nothing moved
    assert_eq!(a.engine.get_note(&n.id).unwrap().body, "base\nfrom laptop\n");
    assert_eq!(a.engine.pending_conflicts().unwrap().len(), 1);
    assert_eq!(a.engine.stats().pending_conflicts, 1);
}

fn diverge() -> (Copy, Copy, String) {
    let (a, b) = two();
    a.engine.set_clock(Box::new(|| 1_000));
    b.engine.set_clock(Box::new(|| 2_000));
    let n = a.engine.create_note("Plan", "base\n").unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    a.engine.save_note(&n.id, "Plan", "A\n").unwrap();
    b.engine.save_note(&n.id, "Plan", "B\n").unwrap();
    pull(&a.engine, &b.engine, None).unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    (a, b, n.id)
}

fn remote_of(e: &notes_core::Engine) -> String {
    e.pending_conflicts().unwrap()[0].remote.manifest.clone()
}

#[test]
fn the_apps_choice_is_applied_and_the_other_copy_fast_forwards() {
    for (name, how, want) in [
        ("keep local", Resolution::KeepLocal, "A\n"),
        ("take remote", Resolution::TakeRemote, "B\n"),
        ("merged", Resolution::Merged { title: "Plan".into(), body: "A and B\n".into() }, "A and B\n"),
    ] {
        let (a, b, id) = diverge();
        let r = remote_of(&a.engine);
        a.engine.resolve_conflict(&id, &r, &how).unwrap();
        assert_eq!(a.engine.get_note(&id).unwrap().body, want, "{name}");
        assert!(a.engine.pending_conflicts().unwrap().is_empty(), "{name}");
        // b still has its own conflict until it sees a's merge version, which has both parents
        let (_, report) = pull(&b.engine, &a.engine, None).unwrap();
        assert_eq!(report.fast_forwarded, vec![id.clone()], "{name}");
        assert_eq!(b.engine.get_note(&id).unwrap().body, want, "{name}");
        assert!(b.engine.pending_conflicts().unwrap().is_empty(), "{name}");
        assert_eq!(a.engine.heads_digest(), b.engine.heads_digest(), "{name}");
    }
}

#[test]
fn keep_both_converges_with_no_conversation() {
    let (a, b, id) = diverge();
    // Each copy applies the SAME deterministic policy on its own: the later edit (desktop, t=2000) wins.
    let (ra, rb) = (remote_of(&a.engine), remote_of(&b.engine));
    a.engine.resolve_conflict(&id, &ra, &Resolution::KeepBoth { winner: Side::Remote }).unwrap();
    b.engine.resolve_conflict(&id, &rb, &Resolution::KeepBoth { winner: Side::Local }).unwrap();

    assert_eq!(a.engine.heads_digest(), b.engine.heads_digest(), "same heads on both copies, nothing sent");
    assert_eq!(a.engine.get_note(&id).unwrap().body, "B\n");
    let notes = a.engine.list_notes().unwrap();
    assert_eq!(notes.len(), 2);
    let copy = notes.iter().find(|n| n.id != id).unwrap();
    assert!(copy.id.starts_with("cf"));
    assert_eq!(copy.title, "Plan (conflict from laptop)");
    assert_eq!(a.engine.get_note(&copy.id).unwrap().body, "A\n");
    // and a further sync finds nothing to do
    let (wire, report) = pull(&a.engine, &b.engine, None).unwrap();
    assert_eq!(wire.bytes, 0);
    assert!(report.conflicts.is_empty());
    // resolving twice is refused: the conflict is gone
    assert!(matches!(a.engine.resolve_conflict(&id, &ra, &Resolution::KeepLocal), Err(Error::NoConflict(_))));
}

#[test]
fn an_edit_and_a_delete_are_a_conflict_too() {
    let (a, b) = two();
    a.engine.set_clock(Box::new(|| 1_000));
    b.engine.set_clock(Box::new(|| 2_000));
    let n = a.engine.create_note("Doomed", "text").unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    a.engine.save_note(&n.id, "Doomed", "text, edited").unwrap();
    b.engine.delete_note(&n.id).unwrap();
    let (_, report) = pull(&a.engine, &b.engine, None).unwrap();
    assert_eq!(report.conflicts.len(), 1);
    assert!(report.conflicts[0].remote.deleted && !report.conflicts[0].local.deleted);
    // the edit wins ("edit beats delete" is the app's rule, applied through the same call)
    let r = remote_of(&a.engine);
    a.engine.resolve_conflict(&n.id, &r, &Resolution::KeepLocal).unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    assert_eq!(b.engine.get_note(&n.id).unwrap().body, "text, edited");
}

#[test]
fn identical_independent_edits_are_not_a_conflict() {
    let (a, b) = two();
    let n = a.engine.create_note("Same", "base").unwrap();
    pull(&b.engine, &a.engine, None).unwrap();
    a.engine.set_clock(Box::new(|| 1_000));
    b.engine.set_clock(Box::new(|| 2_000));
    a.engine.save_note(&n.id, "Same", "same text").unwrap();
    b.engine.save_note(&n.id, "Same", "same text").unwrap(); // different time and device: a different manifest, the same content
    let (_, ra) = pull(&a.engine, &b.engine, None).unwrap();
    let (_, rb) = pull(&b.engine, &a.engine, None).unwrap();
    assert!(ra.conflicts.is_empty() && rb.conflicts.is_empty());
    assert_eq!(a.engine.heads_digest(), b.engine.heads_digest());
}

#[test]
fn old_history_arrives_as_unavailable_until_its_blocks_do() {
    let (a, b) = two();
    let n = a.engine.create_note("h", &text(60_000, 11)).unwrap();
    a.engine.save_note(&n.id, "h", &text(60_000, 12)).unwrap(); // a different body: the old chunks are not in the new tree
    pull(&b.engine, &a.engine, None).unwrap();
    let versions = b.engine.list_versions(&n.id, 10).unwrap();
    assert_eq!(versions.len(), 2);
    assert!(versions[0].available);
    assert!(!versions[1].available, "the old body was not pulled");
    let err = b.engine.restore_version(&n.id, &versions[1].manifest).unwrap_err();
    assert_eq!(err.code(), "version_unavailable");
    // and it can be fetched on purpose: the old version's blocks are ordinary blocks
    let a_old = a.engine.list_versions(&n.id, 10).unwrap()[1].manifest.clone();
    assert_eq!(a_old, versions[1].manifest);
}

#[test]
fn a_conflict_survives_a_restart() {
    let (a, _b, id) = diverge();
    assert_eq!(a.engine.pending_conflicts().unwrap().len(), 1);
    let a = a.reopen("laptop");
    let pending = a.engine.pending_conflicts().unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].note_id, id);
}
