//! OAuth2 device code flow for Azure AD, plus Skype token exchange

use anyhow::{Context, Result};

use super::aad::{AadClient, DeviceCode, TokenSet};
use super::skype::exchange_skype_token;
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
    let config = Config::load()?;
    let rt = config
        .get_refresh_token()
        .context("Not signed in (no refresh token)")?;
    let client = build_client(&AuthConfig::default());
    let full_scope = format!("{scope} offline_access");
    Ok(acquire_token(&client, &rt, &full_scope, scope).await?.0)
}

/// Store the primary (Skype-audience) AAD tokens.
fn store_primary(config: &mut Config, tokens: &TokenSet) {
    config.set_access_token(tokens.access_token.clone(), tokens.expires_in);
    if let Some(rt) = &tokens.refresh_token {
        config.set_refresh_token(rt.clone());
    }
}

/// Refresh the AAD access token using a stored refresh_token, then
/// re-exchange for a Skype token. Returns Ok(true) if refresh succeeded.
pub async fn refresh() -> Result<bool> {
    let mut config = Config::load()?;
    let refresh_token_str = match config.get_refresh_token() {
        Some(rt) => rt,
        None => return Ok(false),
    };

    let auth_config = AuthConfig::default();
    let client = build_client(&auth_config);

    tracing::info!("Refreshing AAD token...");

    let tokens = client
        .refresh(&refresh_token_str, SKYPE_SCOPE)
        .await
        .context("Failed to refresh AAD token")?;
    store_primary(&mut config, &tokens);

    // Exchange for Skype token
    match exchange_skype_token(&tokens.access_token, false).await {
        Ok((skype_tok, expires_in, region_gtms)) => {
            config.set_skype_token(skype_tok, expires_in);
            if let Some(gtms) = region_gtms {
                config.set_region_gtms(gtms);
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

/// Perform OAuth2 login flow
pub async fn login(force: bool) -> Result<()> {
    {
        let config = Config::load()?;

        // Check for existing valid token
        if !force {
            if let Some(token) = config.get_access_token() {
                if !token.is_expired() {
                    // Check if any derived tokens are missing; if so, refresh to acquire them
                    let missing_tokens =
                        config.get_recorder_token().is_none() || config.get_ic3_token().is_none();
                    if missing_tokens && config.get_refresh_token().is_some() {
                        tracing::info!(
                            "AAD token valid but some derived tokens missing, refreshing..."
                        );
                        if let Ok(true) = refresh().await {
                            println!("Tokens refreshed (acquired missing derived tokens).");
                            return Ok(());
                        }
                    }
                    println!(
                        "Already logged in (AAD token valid). Use --force to re-authenticate."
                    );
                    return Ok(());
                }
                // Try refresh before falling through to device code
                if config.get_refresh_token().is_some() {
                    tracing::info!("AAD token expired, attempting refresh...");
                    match refresh().await {
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
        }
    }

    let pending = begin_sign_in().await?;

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
    Ok(PendingSignIn { client, code })
}

/// Wait for the user to approve the sign-in, then store every token OST
/// needs. Returns the names of the secondary tokens that could not be
/// acquired (empty on full success); fails if sign-in itself failed.
pub async fn finish_sign_in(pending: PendingSignIn) -> Result<Vec<&'static str>> {
    let PendingSignIn { client, code } = pending;
    let tokens = client
        .poll_device_token(&code)
        .await
        .context("Failed to exchange device code for token")?;

    // Single load-mutate-save, so a partial failure never leaves half a login.
    let mut config = Config::load()?;
    store_primary(&mut config, &tokens);
    let mut missing = Vec::new();

    match exchange_skype_token(&tokens.access_token, false).await {
        Ok((skype_tok, expires_in, region_gtms)) => {
            config.set_skype_token(skype_tok, expires_in);
            if let Some(gtms) = region_gtms {
                config.set_region_gtms(gtms);
            }
        }
        Err(e) => {
            tracing::warn!("Skype token exchange failed: {:#}", e);
            missing.push("Skype");
        }
    }

    if let Some(rt) = config.get_refresh_token() {
        match acquire_graph_token(&client, &rt).await {
            Ok((tok, exp)) => config.set_graph_token(tok, exp),
            Err(e) => {
                tracing::warn!("Graph token acquisition failed: {:#}", e);
                missing.push("Graph");
            }
        }
        match acquire_ic3_token(&client, &rt).await {
            Ok((tok, exp)) => config.set_ic3_token(tok, exp),
            Err(e) => {
                tracing::warn!("IC3 token acquisition failed: {:#}", e);
                missing.push("IC3");
            }
        }
        match acquire_recorder_token(&client, &rt).await {
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
    let mut config = Config::load()?;
    config.clear_tokens();
    config.save()
}

/// Clear stored credentials
pub async fn logout() -> Result<()> {
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
