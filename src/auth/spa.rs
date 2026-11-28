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
//!
//! A personal Microsoft account signs in the way Teams on the web for
//! personal use (teams.live.com) does: its own client (4b3e8f46…), the
//! `consumers` authority (which hands off to login.live.com), the return
//! address `https://teams.live.com/v2/authv2`, redeemed from the
//! `https://teams.live.com` origin. As Teams desktop's Add another account,
//! one sign-in page takes either kind of address. Microsoft's work page
//! sends a personal address on to login.live.com through Azure AD's own
//! Microsoft-account federation ([`personal_hand_off`]; going on there
//! would sign the account in as a guest of some work tenant, or fail), or
//! refuses it ("You can't sign in here with a personal account"; then OST
//! asks Microsoft's realm discovery, [`is_personal_address`]). Either way
//! OST continues with the personal sign-in for that address.

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

/// Teams on the web for personal use's client id (Teams free).
pub const PERSONAL_CLIENT_ID: &str = "4b3e8f46-56d3-427f-b1e2-d239b2ea6bca";
/// Its return address (what its MSAL sends, captured 2026-11-27).
pub const PERSONAL_REDIRECT_URI: &str = "https://teams.live.com/v2/authv2";
/// The origin it redeems codes and refresh tokens from (required: without
/// it Microsoft refuses the redemption with AADSTS90023).
pub const PERSONAL_ORIGIN: &str = "https://teams.live.com";
/// Personal Microsoft accounts.
const PERSONAL_AUTHORITY: &str =
    "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize";
/// What its first sign-in asks for; the services' tokens are minted from
/// the refresh token afterwards.
pub const PERSONAL_SIGN_IN_SCOPE: &str = "openid profile offline_access";
/// What the sign-in asks for: the Teams middle tier (the primary token),
/// with the user's profile and a refresh token.
pub const SIGN_IN_SCOPE: &str =
    "https://api.spaces.skype.com/.default openid profile offline_access";

/// A browser sign-in waiting for its return address to be reached.
#[derive(Clone)]
pub struct BrowserSignIn {
    verifier: String,
    state: String,
    personal: bool,
    /// The page to open in the web view.
    pub url: String,
}

impl BrowserSignIn {
    /// Start a work sign-in. `silent` asks Azure AD not to show anything
    /// (`prompt=none`): it answers at once from the browser's session, or
    /// with `login_required`.
    pub fn new(login_hint: Option<&str>, silent: bool) -> Self {
        Self::build(false, AUTHORITY, login_hint, silent)
    }

    /// Start a personal account's sign-in (Teams on the web for personal
    /// use's), for the address the sign-in page was given.
    pub fn personal(login_hint: Option<&str>, silent: bool) -> Self {
        Self::build(true, PERSONAL_AUTHORITY, login_hint, silent)
    }

    fn build(personal: bool, authority: &str, login_hint: Option<&str>, silent: bool) -> Self {
        let verifier = random_token(48);
        let state = random_token(24);
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let mut url = url::Url::parse(authority).expect("valid authority");
        let (client, scope, redirect) = if personal {
            (
                PERSONAL_CLIENT_ID,
                PERSONAL_SIGN_IN_SCOPE,
                PERSONAL_REDIRECT_URI,
            )
        } else {
            (CLIENT_ID, SIGN_IN_SCOPE, REDIRECT_URI)
        };
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("client_id", client)
                .append_pair("scope", scope)
                .append_pair("redirect_uri", redirect)
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
        Self {
            verifier,
            state,
            personal,
            url: url.to_string(),
        }
    }

    /// Whether this is a personal account's sign-in.
    pub fn is_personal(&self) -> bool {
        self.personal
    }

    /// Whether `url` is a return address, work or personal (the web view
    /// should stop there).
    pub fn is_redirect(url: &str) -> bool {
        url.starts_with(REDIRECT_URI) || url.starts_with(PERSONAL_REDIRECT_URI)
    }

    /// The code in a return-address URL, or Azure AD's error (for example
    /// `login_required` after a silent attempt).
    pub fn code_from(&self, url: &str) -> Result<String> {
        let parsed = url::Url::parse(url).context("Unexpected sign-in return address")?;
        // MSAL asks for the answer in the fragment; accept the query too.
        let params: Vec<(String, String)> = parsed
            .fragment()
            .map(|f| {
                url::form_urlencoded::parse(f.as_bytes())
                    .into_owned()
                    .collect()
            })
            .filter(|p: &Vec<(String, String)>| !p.is_empty())
            .unwrap_or_else(|| parsed.query_pairs().into_owned().collect());
        let get = |k: &str| params.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
        if let Some(err) = get("error") {
            let desc = get("error_description").unwrap_or_default();
            let first = desc
                .lines()
                .next()
                .unwrap_or_default()
                .chars()
                .take(200)
                .collect::<String>();
            bail!(
                "Sign-in failed: {err}{}",
                if first.is_empty() {
                    String::new()
                } else {
                    format!(": {first}")
                }
            );
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

/// Azure AD's own client for signing Microsoft accounts in through
/// login.live.com (its `urlGoToAADError` hand-off, probed 2026-11-27).
const AAD_MSA_FEDERATION_CLIENT: &str = "51483342-085c-4d86-bf88-cf50c7252078";

/// The address a personal account's sign-in is for, when Microsoft's work
/// sign-in page hands a personal address on to login.live.com (Azure AD's
/// Microsoft-account federation, or the work client itself): `Some("")`
/// when it names none. OST then starts [`BrowserSignIn::personal`]
/// instead, as Teams desktop's sign-in goes on with a personal account.
pub fn personal_hand_off(url: &str) -> Option<String> {
    let u = url::Url::parse(url).ok()?;
    if u.scheme() != "https"
        || !u
            .host_str()
            .is_some_and(|h| h.eq_ignore_ascii_case("login.live.com"))
    {
        return None;
    }
    let q: Vec<(String, String)> = u.query_pairs().into_owned().collect();
    let get = |k: &str| q.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
    // Only the work sign-in's hand-off: the personal sign-in itself goes
    // through login.live.com too, with its own client.
    let client = get("client_id")?;
    if client != AAD_MSA_FEDERATION_CLIENT && client != CLIENT_ID {
        return None;
    }
    Some(
        get("login_hint")
            .or_else(|| get("username"))
            .unwrap_or_default(),
    )
}

/// Microsoft's realm discovery, which its sign-in pages ask about an
/// address before they sign it in.
const USER_REALM: &str = "https://login.microsoftonline.com/common/userrealm/";

/// Whether `address` is a personal Microsoft account's (outlook.com,
/// hotmail.com, or any address Microsoft knows as a Microsoft account), as
/// Microsoft's realm discovery answers: `ConsumerDomain`, or the live.com
/// realm. Teams desktop's sign-in then goes on with the personal sign-in.
pub async fn is_personal_address(http: &reqwest::Client, address: &str) -> Result<bool> {
    let resp = http
        .get(USER_REALM)
        .query(&[("user", address), ("api-version", "2.1")])
        .send()
        .await
        .context("Couldn't reach Microsoft's sign-in")?;
    anyhow::ensure!(
        resp.status().is_success(),
        "Microsoft's realm discovery answered {}",
        resp.status()
    );
    let realm: serde_json::Value = resp.json().await.context("Unexpected realm answer")?;
    Ok(realm_is_personal(&realm))
}

fn realm_is_personal(realm: &serde_json::Value) -> bool {
    realm["ConsumerDomain"].as_bool() == Some(true)
        || realm["DomainName"]
            .as_str()
            .is_some_and(|d| d.eq_ignore_ascii_case("live.com"))
}

/// An embedded app's return address under Teams' broker, as Teams on the
/// web sends it (captured 2026-11-16, e.g. `brk-multihub://engage.cloud.microsoft`
/// for Viva Engage, `brk-multihub://outlook.office.com` for Outlook):
/// `brk-multihub://<the host the app page is served from>`.
pub fn app_redirect_uri(app_origin: &str) -> String {
    let host = app_origin
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_end_matches('/');
    format!("brk-multihub://{host}")
}

/// Whether an error says the 24-hour browser sign-in must be renewed
/// (AADSTS700084: the single-page app's refresh token has expired; or an
/// interaction Azure AD or login.live.com now requires).
pub fn needs_renewal(err: &anyhow::Error) -> bool {
    let s = format!("{err:#}");
    s.contains("AADSTS700084")
        || s.contains("AADSTS50173")
        || s.contains("interaction_required")
        || s.contains("AADSTS70043")
        // login.live.com's answers for a personal account's ended session
        // (Teams free's interactionRequiredErrorCodes)
        || s.contains("invalid_grant")
        || s.contains("login_required")
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
        assert_eq!(
            q["code_challenge"],
            URL_SAFE_NO_PAD.encode(Sha256::digest(s.verifier().as_bytes()))
        );
        assert!(s.verifier().len() >= 43);
        assert_eq!(
            url::Url::parse(&BrowserSignIn::new(None, true).url)
                .unwrap()
                .query_pairs()
                .find(|(k, _)| k == "prompt")
                .unwrap()
                .1,
            "none"
        );
    }

    #[test]
    fn personal_sign_in_is_teams_free_webs() {
        let q = |s: &BrowserSignIn| {
            let u = url::Url::parse(&s.url).unwrap();
            let q: std::collections::HashMap<_, _> = u.query_pairs().into_owned().collect();
            (u.path().to_string(), q)
        };
        let w = BrowserSignIn::new(None, false);
        assert!(!w.is_personal());
        assert_eq!(q(&w).0, "/organizations/oauth2/v2.0/authorize");
        let p = BrowserSignIn::personal(Some("ost-personal1-5135@outlook.com"), false);
        assert!(p.is_personal());
        let (path, pq) = q(&p);
        assert_eq!(path, "/consumers/oauth2/v2.0/authorize");
        assert_eq!(pq["client_id"], PERSONAL_CLIENT_ID);
        assert_eq!(pq["redirect_uri"], PERSONAL_REDIRECT_URI);
        assert_eq!(pq["scope"], PERSONAL_SIGN_IN_SCOPE);
        assert_eq!(pq["login_hint"], "ost-personal1-5135@outlook.com");
        assert_eq!(pq["prompt"], "select_account");
        assert!(BrowserSignIn::is_redirect(&format!(
            "{PERSONAL_REDIRECT_URI}#code=x"
        )));
    }

    #[test]
    fn the_work_pages_hand_off_to_login_live_starts_the_personal_sign_in() {
        // login.microsoftonline.com/organizations with an outlook.com
        // address (Azure AD's federation to login.live.com, 2026-11-27).
        let fed = "https://login.live.com/oauth20_authorize.srf?scope=openid+profile+email+offline_access&response_type=code&client_id=51483342-085c-4d86-bf88-cf50c7252078&response_mode=form_post&redirect_uri=https%3a%2f%2flogin.microsoftonline.com%2fcommon%2ffederation%2foauth2msa&state=x&login_hint=ost-personal1-5135%40outlook.com&estsfed=1";
        assert_eq!(
            personal_hand_off(fed).as_deref(),
            Some("ost-personal1-5135@outlook.com")
        );
        let post = "https://login.live.com/ppsecure/post.srf?username=ost-personal1-5135%40outlook.com&client_id=51483342-085c-4d86-bf88-cf50c7252078&contextid=C1";
        assert_eq!(
            personal_hand_off(post).as_deref(),
            Some("ost-personal1-5135@outlook.com")
        );
        // The personal sign-in's own trip through login.live.com isn't one.
        let own = format!(
            "https://login.live.com/oauth20_authorize.srf?client_id={PERSONAL_CLIENT_ID}&login_hint=x%40outlook.com"
        );
        assert_eq!(personal_hand_off(&own), None);
        assert_eq!(
            personal_hand_off(
                "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize"
            ),
            None
        );
    }

    #[test]
    fn realm_discovery_tells_personal_addresses() {
        // Microsoft's answers (probed 2026-11-27).
        let personal = serde_json::json!({"NameSpaceType":"Federated","DomainName":"live.com","FederationBrandName":"Windows Live","ConsumerDomain":true});
        let work = serde_json::json!({"NameSpaceType":"Managed","DomainName":"scnetsolutions.com","FederationBrandName":"Secure Coast Network Solutions"});
        assert!(realm_is_personal(&personal));
        assert!(!realm_is_personal(&work));
        assert!(realm_is_personal(
            &serde_json::json!({"DomainName":"LIVE.COM"})
        ));
    }

    #[test]
    fn return_address_gives_the_code_or_the_error() {
        let s = BrowserSignIn::new(None, true);
        let ok = format!(
            "{REDIRECT_URI}#code=abc&client_info=x&state={}&session_state=y",
            s.state
        );
        assert!(BrowserSignIn::is_redirect(&ok));
        assert_eq!(s.code_from(&ok).unwrap(), "abc");
        let wrong_state = format!("{REDIRECT_URI}#code=abc&state=other");
        assert!(s.code_from(&wrong_state).is_err());
        let err = format!(
            "{REDIRECT_URI}#error=login_required&error_description=AADSTS50058%3A+no+session&state={}",
            s.state
        );
        let e = s.code_from(&err).unwrap_err().to_string();
        assert!(e.contains("login_required") && e.contains("AADSTS50058"));
        assert!(!BrowserSignIn::is_redirect(
            "https://login.microsoftonline.com/common/login"
        ));
    }

    #[test]
    fn brokered_apps_return_to_brk_multihub_on_their_host() {
        assert_eq!(
            app_redirect_uri("https://engage.cloud.microsoft"),
            "brk-multihub://engage.cloud.microsoft"
        );
        assert_eq!(
            app_redirect_uri("https://outlook.office.com/"),
            "brk-multihub://outlook.office.com"
        );
    }

    #[test]
    fn renewal_errors_are_recognised() {
        assert!(needs_renewal(&anyhow::anyhow!(
            "token refresh rejected (400): invalid_grant: AADSTS700084: The refresh token was issued to a single page app"
        )));
        assert!(!needs_renewal(&anyhow::anyhow!("network down")));
    }
}
