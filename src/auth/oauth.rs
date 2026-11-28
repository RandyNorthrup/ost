//! Sign-in (device code, or Teams on the web's browser sign-in) and the
//! Skype token exchange.

use anyhow::{Context, Result};

use super::aad::{AadClient, DeviceCode, TokenSet};
use super::skype::{AuthzKind, exchange_skype_token};
use super::{AuthConfig, TokenStore};
use crate::config::Config;

/// Audience scopes, each paired with `offline_access` so a refresh token is kept.
const SKYPE_SCOPE: &str = "https://api.spaces.skype.com/.default offline_access";
const GRAPH_SCOPE: &str = "https://graph.microsoft.com/.default offline_access";
const IC3_SCOPE: &str = "https://ic3.teams.office.com/.default offline_access";
const RECORDER_SCOPE: &str = "4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76/.default offline_access";

/// Build the Azure AD client from an AuthConfig
fn build_client(auth_config: &AuthConfig) -> AadClient {
    AadClient::new(
        reqwest::Client::new(),
        auth_config.client_id,
        auth_config.tenant,
    )
    .with_origin(auth_config.origin)
}

/// The client the stored refresh token belongs to.
fn stored_client(config: &Config) -> AadClient {
    build_client(&AuthConfig::for_flow(config.auth_flow.as_deref()))
}

/// Mint a token for another audience from the refresh token.
async fn acquire_token(
    client: &AadClient,
    refresh_token_str: &str,
    scope: &str,
    what: &str,
) -> Result<(String, Option<u64>)> {
    let tokens = client
        .refresh(refresh_token_str, scope)
        .await
        .with_context(|| format!("Failed to acquire {what} token"))?;
    Ok((tokens.access_token, tokens.expires_in))
}

/// Acquire an IC3 token by exchanging the refresh token with IC3 scope.
async fn acquire_ic3_token(client: &AadClient, rt: &str) -> Result<(String, Option<u64>)> {
    acquire_token(client, rt, IC3_SCOPE, "IC3").await
}

/// Acquire a recorder service AAD token (audience: 4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76).
async fn acquire_recorder_token(client: &AadClient, rt: &str) -> Result<(String, Option<u64>)> {
    acquire_token(client, rt, RECORDER_SCOPE, "recorder").await
}

/// Acquire a Graph API token by exchanging the refresh token with Graph scope.
async fn acquire_graph_token(client: &AadClient, rt: &str) -> Result<(String, Option<u64>)> {
    acquire_token(client, rt, GRAPH_SCOPE, "Graph").await
}

/// Mint a short-lived access token for another audience from the stored
/// refresh token, without storing it (for services used now and then).
pub async fn access_token_for(scope: &str) -> Result<String> {
    Ok(access_token_expiring(scope).await?.0)
}

/// [`access_token_for`] with the token's lifetime in seconds (when Azure AD
/// gave one), for callers that keep it until it nears expiry.
pub async fn access_token_expiring(scope: &str) -> Result<(String, Option<u64>)> {
    let config = Config::load()?;
    let rt = config
        .get_refresh_token()
        .context("Not signed in (no refresh token)")?;
    let client = stored_client(&config);
    let full_scope = format!("{scope} offline_access");
    acquire_token(&client, &rt, &full_scope, scope).await
}

/// Store the primary (Skype-audience) AAD tokens.
fn store_primary(config: &mut Config, tokens: &TokenSet) {
    config.set_access_token(tokens.access_token.clone(), tokens.expires_in);
    if let Some(rt) = &tokens.refresh_token {
        config.set_refresh_token(rt.clone());
    }
}

/// One token refresh at a time in this process: a personal account's
/// refresh token rotates with each use, and two refreshes racing would
/// each keep a different one.
static REFRESHING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// Which of a personal account's tokens to renew.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Renew {
    /// All of them (sign-in, or an explicit refresh).
    All,
    /// Only those missing or about to expire, each on its own lifetime, as
    /// Teams on the web for personal use renews them: the Skype token
    /// lasts 8 hours (28,799 s), the middle tier's token as long, Graph's
    /// 1 hour.
    Expired,
}

/// Whether a stored token should be renewed now (missing, or less than
/// five minutes left).
fn lapsed(token: Option<super::StoredToken>) -> bool {
    token.is_none_or(|t| t.is_expired())
}

/// Which stored tokens [`refresh_expired`] would renew: (Skype, primary
/// access token, Graph).
fn lapsed_tokens(config: &Config) -> (bool, bool, bool) {
    (
        lapsed(config.get_skype_token()),
        lapsed(config.get_access_token()),
        lapsed(config.get_graph_token()),
    )
}

/// Whether the stored sign-in needs [`refresh_expired`]: a token it renews
/// is missing or about to expire. A work account's Skype token only
/// counts once it has one (a device-code sign-in can lack it).
pub fn needs_refresh(config: &Config) -> bool {
    let (skype, access, graph) = lapsed_tokens(config);
    let personal = super::is_personal_flow(config.auth_flow.as_deref());
    access
        || graph
        || if personal {
            skype
        } else {
            config.get_skype_token().is_some_and(|t| t.is_expired())
        }
}

/// Renew the stored tokens that are missing or about to expire. A
/// personal account renews each of its tokens on its own expiry (the
/// 8-hour Skype token from the consumer authz, the middle tier's token,
/// Graph's); a work account refreshes them all ([`refresh`]). Waits for a
/// refresh already running in this process and then only renews what is
/// still lapsed. `Ok(false)` when there is no refresh token.
pub async fn refresh_expired() -> Result<bool> {
    let one = REFRESHING.lock().await;
    let mut config = Config::load()?;
    if config.get_refresh_token().is_none() {
        return Ok(false);
    }
    if !needs_refresh(&config) {
        return Ok(true);
    }
    if !super::is_personal_flow(config.auth_flow.as_deref()) {
        drop(one);
        return refresh().await;
    }
    let client = stored_client(&config);
    // (a middle tier or Graph token that couldn't be had is logged; the
    // services that need it say so)
    personal_tokens(&client, &mut config, Renew::Expired).await?;
    config.save()?;
    Ok(true)
}

/// Refresh the AAD access token using a stored refresh_token, then
/// re-exchange for a Skype token. Returns Ok(true) if refresh succeeded.
pub async fn refresh() -> Result<bool> {
    let _one = REFRESHING.lock().await;
    let mut config = Config::load()?;
    let refresh_token_str = match config.get_refresh_token() {
        Some(rt) => rt,
        None => return Ok(false),
    };

    let client = stored_client(&config);

    if super::is_personal_flow(config.auth_flow.as_deref()) {
        tracing::info!("Refreshing the personal account's tokens...");
        personal_tokens(&client, &mut config, Renew::All).await?;
        config.save()?;
        tracing::info!("Token refresh complete");
        return Ok(true);
    }

    tracing::info!("Refreshing AAD token...");

    let tokens = client
        .refresh(&refresh_token_str, SKYPE_SCOPE)
        .await
        .context("Failed to refresh AAD token")?;
    store_primary(&mut config, &tokens);

    // Exchange for Skype token
    match exchange_skype_token(&tokens.access_token, false).await {
        Ok(x) => {
            config.set_skype_token(x.skype_token, x.expires_in);
            if let Some(gtms) = x.region_gtms {
                config.set_region_gtms(gtms);
            }
            if let Some(l) = x.license_details {
                config.set_license_details(l);
            }
            tracing::info!("Skype token refreshed");
        }
        Err(e) => {
            tracing::warn!("Skype token exchange failed during refresh: {:#}", e);
        }
    }

    // Acquire Graph API token (separate audience)
    let rt_for_graph = config.get_refresh_token().unwrap_or_default();
    if !rt_for_graph.is_empty() {
        match acquire_graph_token(&client, &rt_for_graph).await {
            Ok((graph_tok, expires_in)) => {
                config.set_graph_token(graph_tok, expires_in);
                tracing::info!("Graph token acquired");
            }
            Err(e) => {
                tracing::warn!("Graph token acquisition failed: {:#}", e);
            }
        }
    }

    // Acquire IC3 token (for Trouter WebSocket auth)
    let rt_for_ic3 = config.get_refresh_token().unwrap_or_default();
    if !rt_for_ic3.is_empty() {
        match acquire_ic3_token(&client, &rt_for_ic3).await {
            Ok((ic3_tok, expires_in)) => {
                config.set_ic3_token(ic3_tok, expires_in);
                tracing::info!("IC3 token acquired");
            }
            Err(e) => {
                tracing::warn!("IC3 token acquisition failed: {:#}", e);
            }
        }
    }

    // Acquire recorder service token (for call recording)
    let rt_for_recorder = config.get_refresh_token().unwrap_or_default();
    if !rt_for_recorder.is_empty() {
        match acquire_recorder_token(&client, &rt_for_recorder).await {
            Ok((rec_tok, expires_in)) => {
                config.set_recorder_token(rec_tok, expires_in);
                tracing::info!("Recorder token acquired");
            }
            Err(e) => {
                tracing::warn!("Recorder token acquisition failed: {:#}", e);
            }
        }
    }

    config.save()?;
    tracing::info!("Token refresh complete");
    Ok(true)
}

/// Why `teams-cli login` won't start this device-code sign-in for this
/// profile. A work profile that uses OST desktop's browser sign-in (the
/// only one whose tokens broker embedded apps' tokens) is only switched to
/// a device code with `--device-code` (`device_code`). A personal
/// account's profile signs in again as a personal account (`--personal`),
/// and a work account's profile doesn't become a personal one: each
/// account has its own profile (`OST_PROFILE`).
fn device_code_refusal(
    auth_flow: Option<&str>,
    work_identity: bool,
    device_code: bool,
    personal: bool,
) -> Option<&'static str> {
    if personal {
        return (work_identity || auth_flow == Some(super::TEAMS_WEB_FLOW)).then_some(
            "This profile holds a work or school account. Sign the personal account in under its own profile:              OST_PROFILE=<name> teams-cli login --personal",
        );
    }
    if super::is_personal_flow(auth_flow) {
        return Some(
            "This profile holds a personal Microsoft account. Run `teams-cli login --personal` to sign it in again.",
        );
    }
    (auth_flow == Some(super::TEAMS_WEB_FLOW) && !device_code).then_some(
        "This profile signs in through OST desktop's browser sign-in, which the desktop's embedded apps need. \
         Run ost-desktop to sign in again, or run `teams-cli login --device-code` to switch this profile to a device-code sign-in.",
    )
}

/// Perform OAuth2 login flow. A profile that uses the browser sign-in is
/// only switched to the device code with `device_code`; `personal` signs
/// in a personal Microsoft account.
pub async fn login(force: bool, device_code: bool, personal: bool) -> Result<()> {
    {
        let config = Config::load()?;

        // Check for existing valid token
        if !force && let Some(token) = config.get_access_token() {
            let stored_personal = super::is_personal_flow(config.auth_flow.as_deref());
            if !token.is_expired() && !needs_refresh(&config) {
                // Check if any derived tokens are missing; if so, refresh to acquire them
                let missing_tokens = !stored_personal
                    && (config.get_recorder_token().is_none() || config.get_ic3_token().is_none());
                if missing_tokens && config.get_refresh_token().is_some() {
                    tracing::info!(
                        "AAD token valid but some derived tokens missing, refreshing..."
                    );
                    if let Ok(true) = refresh().await {
                        println!("Tokens refreshed (acquired missing derived tokens).");
                        return Ok(());
                    }
                }
                println!("Already logged in (AAD token valid). Use --force to re-authenticate.");
                return Ok(());
            }
            // Try refresh before falling through to device code
            if config.get_refresh_token().is_some() {
                tracing::info!("Tokens expired, attempting refresh...");
                match refresh_expired().await {
                    Ok(true) => {
                        println!("Token refreshed successfully.");
                        return Ok(());
                    }
                    Ok(false) => {}
                    Err(e) => {
                        tracing::warn!("Refresh failed, falling back to device code: {:#}", e);
                    }
                }
            }
        }
        let work_identity = config.identity().is_some_and(|i| !i.is_personal());
        if let Some(why) = device_code_refusal(
            config.auth_flow.as_deref(),
            work_identity,
            device_code,
            personal,
        ) {
            anyhow::bail!(why);
        }
    }

    let pending = if personal {
        begin_personal_sign_in().await?
    } else {
        begin_sign_in().await?
    };

    println!();
    println!("To sign in, visit: {}", pending.verification_uri());
    println!("Enter code:        {}", pending.user_code());
    println!();

    tracing::info!("Waiting for authentication...");
    let missing = finish_sign_in(pending).await?;
    if missing.is_empty() {
        println!("Login successful.");
    } else {
        for what in &missing {
            eprintln!("Warning: {what} token acquisition failed; some features may not work.");
        }
        println!(
            "Login partially successful (missing: {}).",
            missing.join(", ")
        );
    }
    Ok(())
}

/// A device-code sign-in waiting for the user to approve it in a browser.
pub struct PendingSignIn {
    client: AadClient,
    code: DeviceCode,
    /// A personal account's sign-in ([`begin_personal_sign_in`]).
    personal: bool,
}

impl PendingSignIn {
    /// The code the user types at the verification page.
    pub fn user_code(&self) -> &str {
        &self.code.user_code
    }

    /// The page where the user enters the code.
    pub fn verification_uri(&self) -> &str {
        &self.code.verification_uri
    }
}

/// Start a device-code sign-in. Show the user its code and page, then call
/// [`finish_sign_in`].
pub async fn begin_sign_in() -> Result<PendingSignIn> {
    let client = build_client(&AuthConfig::default());
    tracing::info!("Initiating device code flow...");
    let code = client
        .request_device_code(SKYPE_SCOPE)
        .await
        .context("Failed to request device code")?;
    Ok(PendingSignIn {
        client,
        code,
        personal: false,
    })
}

/// Start a personal account's device-code sign-in (`teams-cli login
/// --personal`), with Teams' native client for personal accounts (see
/// [`AuthConfig::teams_live_device`]). Microsoft's page for the code is
/// microsoft.com/link.
pub async fn begin_personal_sign_in() -> Result<PendingSignIn> {
    let config = AuthConfig::teams_live_device();
    let client = build_client(&config);
    tracing::info!("Initiating a personal account's device code flow...");
    let code = client
        .request_device_code(config.scope)
        .await
        .context("Failed to request device code")?;
    Ok(PendingSignIn {
        client,
        code,
        personal: true,
    })
}

/// Teams' broker for embedded apps (nested app authentication): a token
/// for `app_client_id` with `scope` (space-separated), asked by a page
/// served from `app_origin`, minted from the stored browser sign-in, as
/// Teams on the web answers an app's GetToken. The hub's refresh token is
/// left as it is.
pub async fn brokered_token(
    app_client_id: &str,
    app_origin: &str,
    scope: &str,
    claims: Option<&str>,
) -> Result<(String, Option<u64>)> {
    let tokens = brokered_tokens(app_client_id, app_origin, scope, claims).await?;
    Ok((tokens.access_token, tokens.expires_in))
}

/// [`brokered_token`] with the whole answer (the app's OpenID token too, for
/// the account Teams returns with it).
pub async fn brokered_tokens(
    app_client_id: &str,
    app_origin: &str,
    scope: &str,
    claims: Option<&str>,
) -> Result<TokenSet> {
    let config = Config::load()?;
    anyhow::ensure!(
        config.auth_flow.as_deref() == Some(super::TEAMS_WEB_FLOW),
        "Embedded apps' tokens need the browser sign-in"
    );
    let rt = config
        .get_refresh_token()
        .context("Not signed in (no refresh token)")?;
    let tenant = config
        .tenant_id
        .clone()
        .unwrap_or_else(|| "organizations".into());
    let client = AadClient::new(reqwest::Client::new(), app_client_id, &tenant)
        .with_origin(Some(super::spa::ORIGIN));
    let full_scope = if scope.contains("openid") {
        scope.to_string()
    } else {
        format!("{scope} openid profile offline_access")
    };
    let tokens = client
        .broker_refresh(
            app_client_id,
            &rt,
            &full_scope,
            super::spa::CLIENT_ID,
            super::spa::REDIRECT_URI,
            &super::spa::app_redirect_uri(app_origin),
            claims,
        )
        .await?;
    Ok(tokens)
}

/// Whether the stored sign-in is Teams on the web's browser sign-in (its
/// refresh token then lasts 24 hours and is renewed through the web view).
pub fn browser_sign_in() -> bool {
    Config::load().ok().and_then(|c| c.auth_flow).as_deref() == Some(super::TEAMS_WEB_FLOW)
}

/// Whether the stored sign-in is a browser sign-in whose 24-hour refresh
/// token is renewed through the web view: Teams on the web's, or a personal
/// account's (Teams on the web for personal use's). `Some(true)` for the
/// personal one.
pub fn browser_session() -> Option<bool> {
    // (a personal account's device-code sign-in renews from its own,
    // longer-lived refresh token: None)
    match Config::load().ok().and_then(|c| c.auth_flow).as_deref() {
        Some(super::TEAMS_WEB_FLOW) => Some(false),
        Some(super::TEAMS_LIVE_FLOW) => Some(true),
        _ => None,
    }
}

/// Whether the stored sign-in is a personal account's (in OST's web view
/// or with `teams-cli login --personal`).
pub fn personal_session() -> bool {
    Config::load()
        .ok()
        .is_some_and(|c| super::is_personal_flow(c.auth_flow.as_deref()))
}

/// Wait for the user to approve the sign-in, then store every token OST
/// needs. Returns the names of the secondary tokens that could not be
/// acquired (empty on full success); fails if sign-in itself failed.
pub async fn finish_sign_in(pending: PendingSignIn) -> Result<Vec<&'static str>> {
    let PendingSignIn {
        client,
        code,
        personal,
    } = pending;
    let tokens = client
        .poll_device_token(&code)
        .await
        .context("Failed to exchange device code for token")?;
    if personal {
        return store_personal_sign_in(&client, tokens, super::TEAMS_LIVE_DEVICE_FLOW).await;
    }
    store_sign_in(&client, &tokens, None).await
}

/// Redeem a browser sign-in's code (Teams on the web's sign-in, see
/// [`super::spa`]) and store every token OST needs, as [`finish_sign_in`].
pub async fn finish_browser_sign_in(
    pending: &super::spa::BrowserSignIn,
    code: &str,
) -> Result<Vec<&'static str>> {
    if pending.is_personal() {
        return finish_personal_sign_in(pending, code).await;
    }
    let client = build_client(&AuthConfig::teams_web());
    let tokens = client
        .redeem_code(
            code,
            pending.verifier(),
            super::spa::REDIRECT_URI,
            super::spa::SIGN_IN_SCOPE,
        )
        .await
        .context("Failed to redeem the sign-in")?;
    store_sign_in(&client, &tokens, Some(super::TEAMS_WEB_FLOW)).await
}

/// The Graph scope Teams free's client asks for: its token can reach the
/// user's OneDrive only (`Files.ReadWrite`).
const PERSONAL_GRAPH_SCOPE: &str = "https://graph.microsoft.com/.default offline_access";
/// Teams free's middle tier, the personal account's primary token.
const PERSONAL_MT_SCOPE: &str =
    "https://mtsvc.fl.teams.microsoft.com/teams.mt.readwrite offline_access";

/// Redeem a personal account's sign-in (Teams on the web for personal
/// use's, see [`super::spa`]): the account's identity from the OpenID
/// token, then its service tokens ([`personal_tokens`]).
async fn finish_personal_sign_in(
    pending: &super::spa::BrowserSignIn,
    code: &str,
) -> Result<Vec<&'static str>> {
    let client = build_client(&AuthConfig::teams_live());
    let tokens = client
        .redeem_code(
            code,
            pending.verifier(),
            super::spa::PERSONAL_REDIRECT_URI,
            super::spa::PERSONAL_SIGN_IN_SCOPE,
        )
        .await
        .context("Failed to redeem the sign-in")?;
    store_personal_sign_in(&client, tokens, super::TEAMS_LIVE_FLOW).await
}

/// Store a personal account's sign-in (`flow`: in OST's web view, or a
/// device code): the account's identity from the OpenID token, its
/// refresh token, then its service tokens ([`personal_tokens`]).
async fn store_personal_sign_in(
    client: &AadClient,
    tokens: TokenSet,
    flow: &str,
) -> Result<Vec<&'static str>> {
    let identity = tokens
        .id_token
        .as_deref()
        .and_then(crate::identity::AccountIdentity::from_personal_id_token)
        .context("The sign-in didn't name a personal Microsoft account")?;
    let mut config = Config::load()?;
    config.auth_flow = Some(flow.to_string());
    config.set_refresh_token(
        tokens
            .refresh_token
            .context("The sign-in gave no refresh token")?,
    );
    config.set_identity(identity);
    // A new sign-in: none of an earlier sign-in's tokens are kept.
    config.skype_token = None;
    config.access_token = None;
    config.graph_token = None;
    config.ic3_token = None;
    config.recorder_token = None;
    let missing = personal_tokens(client, &mut config, Renew::All).await?;
    config.save()?;
    Ok(missing)
}

/// A token for `scope` from a personal account's refresh token, keeping
/// the rotated refresh token that comes with it.
async fn mint_personal(client: &AadClient, config: &mut Config, scope: &str) -> Result<TokenSet> {
    let rt = config
        .get_refresh_token()
        .context("Not signed in (no refresh token)")?;
    let t = client.refresh(&rt, scope).await?;
    if let Some(new_rt) = &t.refresh_token {
        config.set_refresh_token(new_rt.clone());
    }
    Ok(t)
}

/// A personal account's tokens from its refresh token (rotated with each
/// use, so each new one is kept): the consumer authz token for the Skype
/// token and regional URLs (which also give the account's `skypeid`), the
/// middle tier's as the primary token, and Graph. With [`Renew::Expired`]
/// only the ones missing or about to expire. Fails when the Skype token
/// can't be had (nothing works without it).
async fn personal_tokens(
    client: &AadClient,
    config: &mut Config,
    renew: Renew,
) -> Result<Vec<&'static str>> {
    let (skype, access, graph) = match renew {
        Renew::All => (true, true, true),
        Renew::Expired => lapsed_tokens(config),
    };
    let mut missing = Vec::new();
    if skype {
        let authz = mint_personal(
            client,
            config,
            &format!("{} offline_access", super::skype::PERSONAL_AUTHZ_SCOPE),
        )
        .await
        .context("Failed to get the personal account's authz token")?;
        // Teams on the web for personal use names a renewal TokenRefresh,
        // a sign-in ExplicitLogin.
        let kind = if config.get_skype_token().is_some() {
            AuthzKind::TokenRefresh
        } else {
            AuthzKind::ExplicitLogin
        };
        let x = super::skype::exchange_personal_skype_token(&authz.access_token, kind).await?;
        config.set_skype_token(x.skype_token, x.expires_in);
        if let Some(gtms) = x.region_gtms {
            config.set_region_gtms(gtms);
        }
        if let Some(l) = x.license_details {
            config.set_license_details(l);
        }
        if let (Some(me), Some(id)) = (config.identity().cloned(), x.skype_id.as_deref()) {
            config.set_identity(me.with_skype_id(id));
        }
        tracing::info!("Personal account's Skype token renewed");
    }
    if access {
        match mint_personal(client, config, PERSONAL_MT_SCOPE).await {
            Ok(t) => config.set_access_token(t.access_token, t.expires_in),
            Err(e) => {
                tracing::warn!("Middle tier token acquisition failed: {:#}", e);
                missing.push("Middle tier");
            }
        }
    }
    if graph {
        match mint_personal(client, config, PERSONAL_GRAPH_SCOPE).await {
            Ok(t) => config.set_graph_token(t.access_token, t.expires_in),
            Err(e) => {
                tracing::warn!("Graph token acquisition failed: {:#}", e);
                missing.push("Graph");
            }
        }
    }
    Ok(missing)
}

/// Store a sign-in's tokens and mint the other audiences from it.
async fn store_sign_in(
    client: &AadClient,
    tokens: &TokenSet,
    flow: Option<&str>,
) -> Result<Vec<&'static str>> {
    // Single load-mutate-save, so a partial failure never leaves half a login.
    let mut config = Config::load()?;
    config.auth_flow = flow.map(str::to_string);
    store_primary(&mut config, tokens);
    let mut missing = Vec::new();

    match exchange_skype_token(&tokens.access_token, false).await {
        Ok(x) => {
            config.set_skype_token(x.skype_token, x.expires_in);
            if let Some(gtms) = x.region_gtms {
                config.set_region_gtms(gtms);
            }
            if let Some(l) = x.license_details {
                config.set_license_details(l);
            }
        }
        Err(e) => {
            tracing::warn!("Skype token exchange failed: {:#}", e);
            missing.push("Skype");
        }
    }

    if let Some(rt) = config.get_refresh_token() {
        match acquire_graph_token(client, &rt).await {
            Ok((tok, exp)) => config.set_graph_token(tok, exp),
            Err(e) => {
                tracing::warn!("Graph token acquisition failed: {:#}", e);
                missing.push("Graph");
            }
        }
        match acquire_ic3_token(client, &rt).await {
            Ok((tok, exp)) => config.set_ic3_token(tok, exp),
            Err(e) => {
                tracing::warn!("IC3 token acquisition failed: {:#}", e);
                missing.push("IC3");
            }
        }
        match acquire_recorder_token(client, &rt).await {
            Ok((tok, exp)) => config.set_recorder_token(tok, exp),
            Err(e) => {
                tracing::warn!("Recorder token acquisition failed: {:#}", e);
                missing.push("Recorder");
            }
        }
    } else {
        missing.extend(["Graph", "IC3", "Recorder"]);
    }

    config.save()?;
    Ok(missing)
}

/// Whether credentials are stored (they may still need a refresh).
pub fn has_credentials() -> bool {
    Config::load()
        .map(|c| c.get_refresh_token().is_some())
        .unwrap_or(false)
}

/// Forget all stored credentials.
pub fn sign_out() -> Result<()> {
    super::broker::clear();
    crate::api::loop_page::clear();
    let mut config = Config::load()?;
    config.clear_tokens();
    config.save()
}

/// Clear stored credentials
pub async fn logout() -> Result<()> {
    super::broker::clear();
    crate::api::loop_page::clear();
    let mut config = Config::load()?;
    config.clear_tokens();
    config.save()?;
    println!("Logged out.");
    Ok(())
}

/// Display current auth status
pub async fn status() -> Result<()> {
    let config = Config::load()?;

    // AAD token status
    match config.get_access_token() {
        Some(token) if !token.is_expired() => {
            println!("AAD token:   valid");
            if let Some(exp) = token.expires_at {
                println!("  expires_at: {}", exp);
            }
        }
        Some(_) => {
            println!("AAD token:   expired");
        }
        None => {
            println!("AAD token:   none");
        }
    }

    // Refresh token
    match config.get_refresh_token() {
        Some(_) => println!("Refresh tok: present"),
        None => println!("Refresh tok: none"),
    }

    // Graph token status
    match config.get_graph_token() {
        Some(token) if !token.is_expired() => {
            println!("Graph token: valid");
            if let Some(exp) = token.expires_at {
                println!("  expires_at: {}", exp);
            }
        }
        Some(_) => {
            println!("Graph token: expired");
        }
        None => {
            println!("Graph token: none");
        }
    }

    // IC3 token status
    match config.get_ic3_token() {
        Some(token) if !token.is_expired() => {
            println!("IC3 token:   valid");
            if let Some(exp) = token.expires_at {
                println!("  expires_at: {}", exp);
            }
        }
        Some(_) => {
            println!("IC3 token:   expired");
        }
        None => {
            println!("IC3 token:   none");
        }
    }

    // Recorder token status
    match config.get_recorder_token() {
        Some(token) if !token.is_expired() => {
            println!("Recorder tk: valid");
            if let Some(exp) = token.expires_at {
                println!("  expires_at: {}", exp);
            }
        }
        Some(_) => {
            println!("Recorder tk: expired");
        }
        None => {
            println!("Recorder tk: none");
        }
    }

    // Skype token status
    match config.get_skype_token() {
        Some(token) if !token.is_expired() => {
            println!("Skype token: valid");
            if let Some(exp) = token.expires_at {
                println!("  expires_at: {}", exp);
            }
        }
        Some(_) => {
            println!("Skype token: expired");
        }
        None => {
            println!("Skype token: none");
        }
    }

    // Region GTMs
    if config.region_gtms.is_some() {
        println!("Region GTMs: present");
    } else {
        println!("Region GTMs: none");
    }

    if config.get_access_token().is_none() {
        println!("\nRun 'teams-cli login' to authenticate.");
    }

    Ok(())
}

#[cfg(test)]
mod login_tests {
    use super::*;

    #[test]
    fn device_code_login_needs_the_flag_on_a_browser_profile() {
        let web = Some(crate::auth::TEAMS_WEB_FLOW);
        let why = device_code_refusal(web, true, false, false).expect("refused");
        assert!(why.contains("ost-desktop") && why.contains("--device-code"));
        assert_eq!(device_code_refusal(web, true, true, false), None);
        assert_eq!(device_code_refusal(None, false, false, false), None);
    }

    #[test]
    fn a_personal_account_signs_in_under_its_own_profile() {
        let live = Some(crate::auth::TEAMS_LIVE_FLOW);
        let device = Some(crate::auth::TEAMS_LIVE_DEVICE_FLOW);
        // A fresh profile, or a personal account's (either sign-in).
        assert_eq!(device_code_refusal(None, false, false, true), None);
        assert_eq!(device_code_refusal(live, false, false, true), None);
        assert_eq!(device_code_refusal(device, false, false, true), None);
        // A personal profile isn't turned into a work one...
        let why = device_code_refusal(live, false, true, false).expect("refused");
        assert!(why.contains("--personal"));
        assert!(device_code_refusal(device, false, false, false).is_some());
        // ...nor a work profile into a personal one.
        let why = device_code_refusal(None, true, false, true).expect("refused");
        assert!(why.contains("OST_PROFILE"));
        assert!(
            device_code_refusal(Some(crate::auth::TEAMS_WEB_FLOW), false, false, true).is_some()
        );
    }

    #[test]
    fn personal_tokens_renew_on_their_own_expiry() {
        let fresh = |s: u64| Some(crate::auth::StoredToken::new("t".into(), Some(s)));
        let mut c = Config {
            auth_flow: Some(crate::auth::TEAMS_LIVE_FLOW.into()),
            refresh_token: Some("r".into()),
            access_token: fresh(28_799),
            graph_token: fresh(3_599),
            skype_token: fresh(28_799),
            ..Default::default()
        };
        assert!(!needs_refresh(&c));
        // The 8-hour Skype token lapses by itself: only it is renewed.
        c.skype_token = fresh(60);
        assert!(needs_refresh(&c));
        assert_eq!(lapsed_tokens(&c), (true, false, false));
        // A personal account can't work without it.
        c.skype_token = None;
        assert!(needs_refresh(&c));
        // A work account's device-code sign-in may lack one.
        c.auth_flow = None;
        assert!(!needs_refresh(&c));
        c.skype_token = fresh(60);
        assert!(needs_refresh(&c));
        c.skype_token = fresh(28_799);
        c.graph_token = fresh(10);
        assert_eq!(lapsed_tokens(&c), (false, false, true));
    }
}
