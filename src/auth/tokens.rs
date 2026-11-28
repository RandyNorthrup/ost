//! Token storage and management

use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

/// Stored access token
#[derive(Clone, Serialize, Deserialize)]
pub struct StoredToken {
    pub token: String,
    pub expires_at: Option<u64>,
}

/// A secret's stand-in in `Debug` output: its length only, so a debug
/// print or log line never holds a token.
pub struct Redacted<'a>(pub &'a str);

impl std::fmt::Debug for Redacted<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "<redacted, {} chars>", self.0.len())
    }
}

/// An optional secret's stand-in in `Debug` output.
pub fn redacted(secret: &Option<String>) -> Option<Redacted<'_>> {
    secret.as_deref().map(Redacted)
}

impl std::fmt::Debug for StoredToken {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("StoredToken")
            .field("token", &Redacted(&self.token))
            .field("expires_at", &self.expires_at)
            .finish()
    }
}

impl StoredToken {
    pub fn new(token: String, expires_in_secs: Option<u64>) -> Self {
        let expires_at = expires_in_secs.map(|secs| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
                + secs
        });

        Self { token, expires_at }
    }

    pub fn is_expired(&self) -> bool {
        match self.expires_at {
            Some(exp) => {
                let now = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs();
                // Consider expired if less than 5 minutes remaining
                now + 300 >= exp
            }
            None => false,
        }
    }
}

/// Token store trait for different storage backends
pub trait TokenStore {
    fn get_access_token(&self) -> Option<StoredToken>;
    fn set_access_token(&mut self, token: String, expires_in: Option<u64>);
    fn get_refresh_token(&self) -> Option<String>;
    fn set_refresh_token(&mut self, token: String);
    fn clear_tokens(&mut self);
}
