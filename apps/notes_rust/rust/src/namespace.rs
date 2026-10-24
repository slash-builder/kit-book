//! The idea this app takes from the Application Kit's storage prototype: ONE `(account, app id)` pair names the app's slice
//! of the Storage Kit.
//!
//! ```text
//! partition = BLAKE3("slash-builder/application-kit/storage-partition/v1\n<account>\n<app id>")[0..16]
//! ```
//!
//! * The domain string is fixed and versioned, so the same pair can never collide with a partition another subsystem derives,
//!   and a future change bumps the version instead of silently re-homing everyone's data.
//! * Newlines separate the parts. A validated app id and an account name (checked below) contain none.
//! * The account is in the key: two household members running this app get different partitions; two copies of the app for the
//!   same account share one, which is what lets them sync by content address.
//! * It is not access control: anyone who knows the two strings can compute the partition.
//!
//! The Application Kit does not hand out an account to the Rust side (the snapshot has none), so the Dart owner passes
//! `ctx.peerAccount`, the same account the peer layer scopes by. That is a gap noted in the README.

use storage_kit::PartitionId;

use crate::error::{Error, Result};

pub const PARTITION_DOMAIN: &str = "slash-builder/application-kit/storage-partition/v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Namespace {
    account: String,
    app_id: String,
}

/// A name that is safe to put between newlines: 1 to 64 characters, no control characters.
pub(crate) fn check_label(what: &str, s: &str) -> Result<()> {
    if s.is_empty() || s.chars().count() > 64 || s.chars().any(char::is_control) {
        return Err(Error::Invalid(format!(
            "{what} must be 1 to 64 characters with no control characters"
        )));
    }
    Ok(())
}

impl Namespace {
    /// `app_id` comes from an accepted snapshot (the Kit's parser already checked its shape); `account` is checked here.
    pub fn new(account: &str, app_id: &str) -> Result<Namespace> {
        check_label("account", account)?;
        Ok(Namespace {
            account: account.to_string(),
            app_id: app_id.to_string(),
        })
    }

    pub fn account(&self) -> &str {
        &self.account
    }

    pub fn app_id(&self) -> &str {
        &self.app_id
    }

    pub fn partition(&self) -> PartitionId {
        PartitionId::derive(&format!(
            "{PARTITION_DOMAIN}\n{}\n{}",
            self.account, self.app_id
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_and_separated() {
        let a = Namespace::new("home", "dev.demo.notes-rust").unwrap();
        assert_eq!(
            a.partition(),
            Namespace::new("home", "dev.demo.notes-rust").unwrap().partition()
        );
        assert_ne!(a.partition(), Namespace::new("work", "dev.demo.notes-rust").unwrap().partition());
        assert_ne!(a.partition(), Namespace::new("home", "dev.demo.notepad").unwrap().partition());
        // a prefix of an id is another app, not a sub-namespace
        assert_ne!(
            Namespace::new("home", "dev.demo.notes").unwrap().partition(),
            a.partition()
        );
    }

    /// The same derivation, string for string, as the Application Kit's storage prototype, whose test pins this value
    /// (account "00000000-0000-0000-0000-000000000001", app "dev.demo.notepad"). Changing the domain string or the layout
    /// would re-home every user's data.
    #[test]
    fn matches_the_prototype_pin_and_a_hand_computed_blake3() {
        let a = Namespace::new("00000000-0000-0000-0000-000000000001", "dev.demo.notepad").unwrap();
        assert_eq!(a.partition().to_hex(), "8094edc87c3dec028f1b9841ac7064c5");
        let s = "slash-builder/application-kit/storage-partition/v1\n00000000-0000-0000-0000-000000000001\ndev.demo.notepad";
        let full = storage_kit::Hash::of(s.as_bytes());
        assert_eq!(a.partition().as_bytes(), &full.as_bytes()[..16]);
    }

    #[test]
    fn accounts_that_would_break_the_separator_are_refused() {
        for bad in ["", "a\nb", "tab\there", &"x".repeat(65)] {
            assert!(Namespace::new(bad, "dev.demo.x").is_err(), "{bad:?}");
        }
    }
}
