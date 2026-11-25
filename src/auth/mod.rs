//! Authentication module for Microsoft Teams
//!
//! Implements OAuth2 device code flow for Azure AD authentication,
//! then exchanges the AAD token for a Skype token.

pub mod aad;
pub mod broker;
pub mod oauth;
pub mod skype;
pub mod spa;
pub mod token_hosts;
pub mod tokens;

pub use oauth::{
    PendingSignIn, begin_sign_in, brokered_token, brokered_tokens, browser_sign_in,
    finish_browser_sign_in, finish_sign_in, has_credentials, login, logout, sign_out, status,
};
pub use tokens::{StoredToken, TokenStore};

/// Azure AD client configuration for Teams
pub struct AuthConfig {
    /// OAuth2 client ID (public client)
    pub client_id: &'static str,
    /// OAuth2 redirect URI
    pub redirect_uri: &'static str,
    /// Token requests' `Origin` (a single-page app's sign-in), if any.
    pub origin: Option<&'static str>,
    /// Azure AD tenant (common for multi-tenant)
    pub tenant: &'static str,
    /// Primary resource scope
    pub scope: &'static str,
}

impl AuthConfig {
    /// Config for work/school accounts (Teams desktop client_id)
    pub fn work() -> Self {
        Self {
            client_id: "1fec8e78-bce4-4aaf-ab1b-5451cc387264",
            redirect_uri: "https://login.microsoftonline.com/common/oauth2/nativeclient",
            origin: None,
            tenant: "common",
            scope: "https://api.spaces.skype.com/.default offline_access",
        }
    }

    /// Config for personal (consumer) accounts
    pub fn personal() -> Self {
        Self {
            client_id: "8ec6bc83-69c8-4392-8f08-b3c986009232",
            redirect_uri: "https://login.microsoftonline.com/common/oauth2/nativeclient",
            origin: None,
            tenant: "consumers",
            scope: "https://api.spaces.skype.com/.default offline_access",
        }
    }
}

impl AuthConfig {
    /// Teams on the web's browser sign-in (see [`spa`]).
    pub fn teams_web() -> Self {
        Self {
            client_id: spa::CLIENT_ID,
            redirect_uri: spa::REDIRECT_URI,
            origin: Some(spa::ORIGIN),
            tenant: "organizations",
            scope: spa::SIGN_IN_SCOPE,
        }
    }

    /// The client the stored sign-in belongs to: refresh tokens only work
    /// with the client (and origin) that got them.
    pub fn for_flow(flow: Option<&str>) -> Self {
        match flow {
            Some(TEAMS_WEB_FLOW) => Self::teams_web(),
            _ => Self::work(),
        }
    }
}

/// [`crate::config::Config::auth_flow`] for a browser (Teams on the web) sign-in.
pub const TEAMS_WEB_FLOW: &str = "teams-web";

impl Default for AuthConfig {
    fn default() -> Self {
        Self::work()
    }
}
