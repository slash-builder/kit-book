//! The notes store on a real Storage Kit partition: CRUD, versions, content addressing, damaged files.

mod common;

use common::*;
use notes_core::Error;
use std::fs;

#[test]
fn create_read_edit_delete() {
    let c = open_copy("laptop", "0a1b2c3d");
    let n = c.engine.create_note("Shopping", "milk\neggs\n").unwrap();
    assert!(n.id.starts_with('n') && n.id.len() == 16);
    assert_eq!(c.engine.get_note(&n.id).unwrap().body, "milk\neggs\n");

    let list = c.engine.list_notes().unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(
        (list[0].title.as_str(), list[0].preview.as_str()),
        ("Shopping", "milk")
    );

    let n2 = c
        .engine
        .save_note(&n.id, "Shopping", "milk\neggs\nbread\n")
        .unwrap();
    assert_ne!(n2.head, n.head);
    // an unchanged save writes no version
    assert_eq!(
        c.engine
            .save_note(&n.id, "Shopping", "milk\neggs\nbread\n")
            .unwrap()
            .head,
        n2.head
    );
    assert_eq!(c.engine.list_versions(&n.id, 50).unwrap().len(), 2);

    c.engine.delete_note(&n.id).unwrap();
    assert!(c.engine.list_notes().unwrap().is_empty());
    assert!(matches!(
        c.engine.get_note(&n.id),
        Err(Error::NoSuchNote(_))
    ));
    // history survives the delete
    assert_eq!(c.engine.list_versions(&n.id, 50).unwrap().len(), 3);
    assert!(matches!(
        c.engine.save_note("nosuchnote1", "x", "y"),
        Err(Error::NoSuchNote(_))
    ));
}

#[test]
fn notes_survive_a_restart() {
    let c = open_copy("laptop", "0a1b2c3d");
    let n = c.engine.create_note("Keep", "still here").unwrap();
    let c = c.reopen("laptop");
    assert_eq!(c.engine.get_note(&n.id).unwrap().body, "still here");
    assert_eq!(c.engine.list_versions(&n.id, 10).unwrap().len(), 1);
}

#[test]
fn restoring_a_version_writes_one_manifest_and_no_body_block() {
    let c = open_copy("laptop", "0a1b2c3d");
    let big = text(300_000, 1);
    let n = c.engine.create_note("Big", &big).unwrap();
    let edited = format!("{}{}", &big[..1000], "X");
    c.engine.save_note(&n.id, "Big", &edited).unwrap();
    let versions = c.engine.list_versions(&n.id, 50).unwrap();
    assert_eq!(versions.len(), 2);
    assert!(versions[0].is_head && !versions[1].is_head && versions.iter().all(|v| v.available));
    let first = &versions[1].manifest;

    // the old version can be read without being made current
    assert_eq!(c.engine.read_version(&n.id, first).unwrap().body, big);
    assert_eq!(c.engine.get_note(&n.id).unwrap().body, edited);

    let before = c.engine.stats().block_count;
    let restored = c.engine.restore_version(&n.id, first).unwrap();
    assert_eq!(restored.body, big);
    assert_eq!(
        c.engine.stats().block_count,
        before + 1,
        "only the new manifest is a new block"
    );
    // history is a line: restore, edit, original
    assert_eq!(c.engine.list_versions(&n.id, 50).unwrap().len(), 3);
    // restoring what is already current changes nothing
    let again = c
        .engine
        .restore_version(&n.id, &c.engine.get_note(&n.id).unwrap().head)
        .unwrap();
    assert_eq!(again.head, restored.head);
}

#[test]
fn identical_bodies_share_their_blocks() {
    let c = open_copy("laptop", "0a1b2c3d");
    let body = text(200_000, 2);
    c.engine.create_note("one", &body).unwrap();
    let after_first = c.engine.stats().block_count;
    c.engine.create_note("two", &body).unwrap();
    assert_eq!(
        c.engine.stats().block_count,
        after_first + 1,
        "the second copy of the text adds one manifest"
    );
}

#[test]
fn a_damaged_head_index_is_reported_and_never_replaced() {
    let c = open_copy("laptop", "0a1b2c3d");
    c.engine.create_note("x", "y").unwrap();
    let index = fs::read_dir(c.data())
        .unwrap()
        .map(|e| e.unwrap().path())
        .find(|p| {
            p.file_name()
                .unwrap()
                .to_str()
                .unwrap()
                .starts_with("heads-")
        })
        .unwrap();
    let Copy { dir, engine, .. } = c;
    drop(engine);
    fs::write(&index, "{not json").unwrap();
    let err = Engine_open(&dir).unwrap_err();
    assert!(matches!(err, Error::Corrupt(_)), "{err}");
    assert_eq!(fs::read_to_string(&index).unwrap(), "{not json");
}

#[allow(non_snake_case)]
fn Engine_open(dir: &tempfile::TempDir) -> Result<notes_core::Engine, Error> {
    notes_core::Engine::open(&snapshot_json(dir.path(), "0a1b2c3d"), "home", "laptop")
}

#[test]
fn the_owner_writes_settings_and_the_core_only_reads_them() {
    let c = open_copy("laptop", "0a1b2c3d");
    fs::create_dir_all(c.config()).unwrap();
    let cfg = c.config().join("config.json");
    fs::write(&cfg, r#"{"maxNoteBytes": 10, "fontSize": 18}"#).unwrap();
    let before = fs::read(&cfg).unwrap();

    assert_eq!(c.engine.stats().max_note_bytes, 10);
    assert!(matches!(
        c.engine.create_note("t", "01234567890"),
        Err(Error::TooLarge { len: 11, limit: 10 })
    ));
    c.engine.create_note("t", "0123456789").unwrap();

    // The core never touched the owner's file, and made no roster entry.
    assert_eq!(fs::read(&cfg).unwrap(), before);
    assert_eq!(fs::read_dir(c.config()).unwrap().count(), 1);
    assert!(!c.dir.path().join("roster").exists());
    // What the core created is under data only.
    assert!(!c.dir.path().join(APP).join("cache").exists());
    assert!(!c.dir.path().join(APP).join("runtime").exists());
}

#[test]
fn the_partition_is_the_one_the_account_and_app_name() {
    let c = open_copy("laptop", "0a1b2c3d");
    let stats = c.engine.stats();
    let expect = notes_core::namespace::Namespace::new("home", APP)
        .unwrap()
        .partition()
        .to_hex();
    assert_eq!(stats.partition, expect);
    assert!(c.data().join("blocks").join(&expect).is_dir());
    assert_eq!(
        (
            stats.app_id.as_str(),
            stats.instance.as_str(),
            stats.mode.as_str()
        ),
        (APP, "0a1b2c3d", "real")
    );
}

#[test]
fn bad_snapshots_and_arguments_are_typed_errors() {
    let dir = tempfile::tempdir().unwrap();
    let mut bad =
        serde_json::from_str::<serde_json::Value>(&snapshot_json(dir.path(), "0a1b2c3d")).unwrap();
    bad["dirs"]["data"] = serde_json::json!("relative/data");
    let err = notes_core::Engine::open(&bad.to_string(), "home", "laptop").unwrap_err();
    assert_eq!(err.code(), "bad_snapshot");
    assert!(notes_core::Engine::open(
        &snapshot_json(dir.path(), "0a1b2c3d"),
        "bad\naccount",
        "laptop"
    )
    .is_err());
    assert!(notes_core::Engine::open(&snapshot_json(dir.path(), "0a1b2c3d"), "home", "").is_err());
}

#[test]
fn a_torn_pack_tail_hides_one_note_not_the_list() {
    let c = open_copy("laptop", "0a1b2c3d");
    c.engine.create_note("first", "safe").unwrap();
    let last = c
        .engine
        .create_note("last", "written when the power went")
        .unwrap();
    let pack = c
        .data()
        .join("blocks")
        .join(c.engine.stats().partition)
        .join("active")
        .join("active.pack");
    let Copy { dir, engine, .. } = c;
    drop(engine);
    // Cut the file in the middle of the last note's final block, as a power cut that lost unsynced pages would.
    let len = fs::metadata(&pack).unwrap().len();
    fs::OpenOptions::new()
        .write(true)
        .open(&pack)
        .unwrap()
        .set_len(len - 20)
        .unwrap();
    let engine = Engine_open(&dir).unwrap();
    let stats = engine.stats();
    assert_eq!(stats.unreadable_notes, 1);
    let list = engine.list_notes().unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].title, "first");
    assert!(engine.get_note(&last.id).is_err());
}
