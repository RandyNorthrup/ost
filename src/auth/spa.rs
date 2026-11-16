//! Teams on the web's sign-in, for OST's desktop app.
//!
//! Teams desktop on Windows signs in through the system's account broker
//! (WAM), which Linux doesn't have. Teams on the web signs in with
//! Microsoft's sign-in page instead: MSAL.js runs the authorization-code
//! flow with PKCE as a single-page app (client 5e3ce6c0…, return address
//! `https://teams.cloud.microsoft/v2/authv2`), and redeems the code from the
//! Teams origin. OST does the same in its own web view, so it gets the same
//! tokens as Teams. Those can broker tokens for embedded apps (NAA,
//! `brk_client_id`), which Microsoft refuses for a device-code sign-in.
//!
//! A single-page app's refresh token lasts 24 hours from sign-in. After
//! that MSAL.js signs in again silently (`prompt=none`) with the browser's
//! Microsoft session, and so does OST's desktop app, with the web profile
//! that holds that session.

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use sha2::{Digest, Sha256};

/// Teams on the web's client id.
pub const CLIENT_ID: &str = "5e3ce6c0-2b1f-4285-8d4b-75ee78787346";
/// Its single-page-app return address (also its broker address, as embedded
/// apps' token requests send it as `brk_redirect_uri`).
pub const REDIRECT_URI: &str = "https://teams.cloud.microsoft/v2/authv2";
/// The origin Teams on the web redeems codes and refresh tokens from;
/// Azure AD only redeems a single-page app's codes cross-origin.
pub const ORIGIN: &str = "https://teams.cloud.microsoft";
/// Multi-tenant work or school accounts, as Teams on the web asks.
const AUTHORITY: &str = "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize";
/// What the sign-in asks for: the Teams middle tier (the primary token),
/// with the user's profile and a refresh token.
pub const SIGN_IN_SCOPE: &str = "https://api.spaces.skype.com/.default openid profile offline_access";

/// A browser sign-in waiting for its return address to be reached.
#[derive(Clone)]
pub struct BrowserSignIn {
    verifier: String,
    state: String,
    /// The page to open in the web view.
    pub url: String,
}

impl BrowserSignIn {
    /// Start a sign-in. `silent` asks Azure AD not to show anything
    /// (`prompt=none`): it answers at once from the browser's session, or
    /// with `login_required`.
    pub fn new(login_hint: Option<&str>, silent: bool) -> Self {
        let verifier = random_token(48);
        let state = random_token(24);
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let mut url = url::Url::parse(AUTHORITY).expect("valid authority");
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("client_id", CLIENT_ID)
                .append_pair("scope", SIGN_IN_SCOPE)
                .append_pair("redirect_uri", REDIRECT_URI)
                .append_pair("response_type", "code")
                .append_pair("response_mode", "fragment")
                .append_pair("code_challenge", &challenge)
                .append_pair("code_challenge_method", "S256")
                .append_pair("state", &state)
                .append_pair("client_info", "1");
            if let Some(hint) = login_hint.filter(|h| !h.is_empty()) {
                q.append_pair("login_hint", hint);
            }
            if silent {
                q.append_pair("prompt", "none");
            } else {
                q.append_pair("prompt", "select_account");
            }
        }
        Self { verifier, state, url: url.to_string() }
    }

    /// Whether `url` is the return address (the web view should stop there).
    pub fn is_redirect(url: &str) -> bool {
        url.starts_with(REDIRECT_URI)
    }

    /// The code in a return-address URL, or Azure AD's error (for example
    /// `login_required` after a silent attempt).
    pub fn code_from(&self, url: &str) -> Result<String> {
        let parsed = url::Url::parse(url).context("Unexpected sign-in return address")?;
        // MSAL asks for the answer in the fragment; accept the query too.
        let params: Vec<(String, String)> = parsed
            .fragment()
            .map(|f| url::form_urlencoded::parse(f.as_bytes()).into_owned().collect())
            .filter(|p: &Vec<(String, String)>| !p.is_empty())
            .unwrap_or_else(|| parsed.query_pairs().into_owned().collect());
        let get = |k: &str| params.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
        if let Some(err) = get("error") {
            let desc = get("error_description").unwrap_or_default();
            let first = desc.lines().next().unwrap_or_default().chars().take(200).collect::<String>();
            bail!("Sign-in failed: {err}{}", if first.is_empty() { String::new() } else { format!(": {first}") });
        }
        if get("state").as_deref() != Some(self.state.as_str()) {
            bail!("Sign-in answer doesn't match this sign-in");
        }
        get("code").context("Sign-in returned no code")
    }

    /// The PKCE verifier, for redeeming the code.
    pub(crate) fn verifier(&self) -> &str {
        &self.verifier
    }
}

/// Whether an error says the 24-hour browser sign-in must be renewed
/// (AADSTS700084: the single-page app's refresh token has expired; or an
/// interaction Azure AD now requires).
pub fn needs_renewal(err: &anyhow::Error) -> bool {
    let s = format!("{err:#}");
    s.contains("AADSTS700084") || s.contains("AADSTS50173") || s.contains("interaction_required") || s.contains("AADSTS70043")
}

fn random_token(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    getrandom::fill(&mut buf).expect("OS CSPRNG failed");
    URL_SAFE_NO_PAD.encode(buf)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_in_url_is_teams_webs() {
        let s = BrowserSignIn::new(Some("ost-test1@scnetsolutions.com"), false);
        let u = url::Url::parse(&s.url).unwrap();
        let q: std::collections::HashMap<_, _> = u.query_pairs().into_owned().collect();
        assert_eq!(q["client_id"], CLIENT_ID);
        assert_eq!(q["redirect_uri"], REDIRECT_URI);
        assert_eq!(q["response_type"], "code");
        assert_eq!(q["code_challenge_method"], "S256");
        assert_eq!(q["login_hint"], "ost-test1@scnetsolutions.com");
        assert_eq!(q["prompt"], "select_account");
        // The challenge is the verifier's SHA-256, base64url without padding.
        assert_eq!(q["code_challenge"], URL_SAFE_NO_PAD.encode(Sha256::digest(s.verifier().as_bytes())));
        assert!(s.verifier().len() >= 43);
        assert_eq!(url::Url::parse(&BrowserSignIn::new(None, true).url).unwrap().query_pairs().find(|(k, _)| k == "prompt").unwrap().1, "none");
    }

    #[test]
    fn return_address_gives_the_code_or_the_error() {
        let s = BrowserSignIn::new(None, true);
        let ok = format!("{REDIRECT_URI}#code=abc&client_info=x&state={}&session_state=y", s.state);
        assert!(BrowserSignIn::is_redirect(&ok));
        assert_eq!(s.code_from(&ok).unwrap(), "abc");
        let wrong_state = format!("{REDIRECT_URI}#code=abc&state=other");
        assert!(s.code_from(&wrong_state).is_err());
        let err = format!("{REDIRECT_URI}#error=login_required&error_description=AADSTS50058%3A+no+session&state={}", s.state);
        let e = s.code_from(&err).unwrap_err().to_string();
        assert!(e.contains("login_required") && e.contains("AADSTS50058"));
        assert!(!BrowserSignIn::is_redirect("https://login.microsoftonline.com/common/login"));
    }

    #[test]
    fn renewal_errors_are_recognised() {
        assert!(needs_renewal(&anyhow::anyhow!("token refresh rejected (400): invalid_grant: AADSTS700084: The refresh token was issued to a single page app")));
        assert!(!needs_renewal(&anyhow::anyhow!("network down")));
    }
}
