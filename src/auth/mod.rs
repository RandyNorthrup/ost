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
    PendingSignIn, begin_personal_sign_in, begin_sign_in, brokered_token, brokered_tokens,
    browser_session, browser_sign_in, finish_browser_sign_in, finish_sign_in, has_credentials,
    login, logout, personal_session, sign_out, status,
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

    /// Teams on the web for personal use's sign-in, for a personal
    /// Microsoft account (see [`spa`]).
    pub fn teams_live() -> Self {
        Self {
            client_id: spa::PERSONAL_CLIENT_ID,
            redirect_uri: spa::PERSONAL_REDIRECT_URI,
            origin: Some(spa::PERSONAL_ORIGIN),
            tenant: "consumers",
            scope: spa::PERSONAL_SIGN_IN_SCOPE,
        }
    }

    /// A personal account's device-code sign-in (`teams-cli login
    /// --personal`): Teams' own native client for personal accounts
    /// ("Microsoft Teams-T4L"), as Teams on phones and Teams desktop's
    /// account broker sign in. Teams on the web for personal use's client is
    /// a single-page app, which Microsoft refuses a device code
    /// (AADSTS70002). Its refresh token isn't held to the single-page app's
    /// 24 hours, and its tokens reach the same consumer services (authz
    /// v2, middle tier, Graph; checked live 2026-11-28).
    pub fn teams_live_device() -> Self {
        Self {
            client_id: PERSONAL_NATIVE_CLIENT_ID,
            redirect_uri: "msauth.com.microsoft.teams://auth",
            origin: None,
            tenant: "consumers",
            scope: "https://auth.fl.teams.microsoft.com/teams.auth.readwrite openid profile offline_access",
        }
    }

    /// The client the stored sign-in belongs to: refresh tokens only work
    /// with the client (and origin) that got them.
    pub fn for_flow(flow: Option<&str>) -> Self {
        match flow {
            Some(TEAMS_WEB_FLOW) => Self::teams_web(),
            Some(TEAMS_LIVE_FLOW) => Self::teams_live(),
            Some(TEAMS_LIVE_DEVICE_FLOW) => Self::teams_live_device(),
            _ => Self::work(),
        }
    }
}

/// Teams' native client for personal accounts (Teams-T4L).
pub const PERSONAL_NATIVE_CLIENT_ID: &str = "8ec6bc83-69c8-4392-8f08-b3c986009232";

/// [`crate::config::Config::auth_flow`] for a browser (Teams on the web) sign-in.
pub const TEAMS_WEB_FLOW: &str = "teams-web";
/// [`crate::config::Config::auth_flow`] for a personal account's browser
/// sign-in (Teams on the web for personal use).
pub const TEAMS_LIVE_FLOW: &str = "teams-live";
/// [`crate::config::Config::auth_flow`] for a personal account's
/// device-code sign-in (`teams-cli login --personal`).
pub const TEAMS_LIVE_DEVICE_FLOW: &str = "teams-live-device";

/// Whether a stored sign-in's flow is a personal account's (either way).
pub fn is_personal_flow(flow: Option<&str>) -> bool {
    matches!(flow, Some(TEAMS_LIVE_FLOW | TEAMS_LIVE_DEVICE_FLOW))
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self::work()
    }
}
