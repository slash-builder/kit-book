//! notes_core: notes stored as content-addressed blocks on the Storage Kit, inside an Application Kit context that the
//! Flutter UI opened and this crate only adopts.
//!
//! * [`engine::Engine`] is the whole core (plain Rust, tested alone with `cargo test`).
//! * [`store`] has the notes, versions and head index; [`sync`] the primitives a transport drives
//!   (heads, missing blocks, export, verified import, conflicts); [`namespace`] the `(account, app)` partition.
//! * `api/` is the thin flutter_rust_bridge layer over `Engine`; `frb_generated.rs` is generated and committed.

pub mod engine;
pub mod error;
pub mod namespace;
pub mod store;
pub mod sync;
pub mod types;

mod api;
mod frb_generated;

pub use engine::Engine;
pub use error::{Error, Result};
