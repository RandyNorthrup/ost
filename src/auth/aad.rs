//! Minimal Azure AD (Microsoft identity platform) client for a public client.
//!
//! Teams needs exactly two OAuth2 grants: the device authorization grant
//! (RFC 8628) for interactive sign-in, and the refresh-token grant to mint
//! tokens for further audiences. Both are a form-encoded POST, so this module
//! implements them directly on the shared `reqwest` client instead of pulling
//! in a general OAuth2 framework and its separate TLS stack.
//!
//! Tokens never appear in errors or logs: failures report only the
//! endpoint's `error` code and its description.

use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde::Deserialize;

/// The longest error description we copy into an error message.
const MAX_ERROR_DESCRIPTION: usize = 300;
/// Extra seconds to wait after a `slow_down` response, per RFC 8628 §3.5.
const SLOW_DOWN_STEP_SECS: u64 = 5;
/// Polling interval when the device code response omits one (RFC 8628 §3.2).
const DEFAULT_POLL_INTERVAL_SECS: u64 = 5;

/// Tokens returned by the token endpoint.
#[derive(Debug, Deserialize)]
pub struct TokenSet {
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    /// Lifetime in seconds. Azure AD sends a number; some proxies send a string.
    #[serde(default, deserialize_with = "seconds")]
    pub expires_in: Option<u64>,
}

/// The device authorization response (RFC 8628 §3.2).
#[derive(Debug, Deserialize)]
pub struct DeviceCode {
    device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    #[serde(deserialize_with = "seconds")]
    expires_in: Option<u64>,
    #[serde(default, deserialize_with = "seconds")]
    interval: Option<u64>,
}

/// An OAuth2 error body (RFC 6749 §5.2).
#[derive(Debug, Deserialize)]
struct ErrorBody {
    error: String,
    #[serde(default)]
    error_description: Option<String>,
}

impl ErrorBody {
    fn summary(&self) -> String {
        match &self.error_description {
            Some(d) => {
                let first_line = d.lines().next().unwrap_or_default();
                let short: String = first_line.chars().take(MAX_ERROR_DESCRIPTION).collect();
                format!("{}: {}", self.error, short)
            }
            None => self.error.clone(),
        }
    }
}

/// What one poll of the token endpoint told us.
#[derive(Debug, PartialEq)]
enum PollOutcome {
    Pending,
    SlowDown,
}

/// Client for one public client id against one tenant.
pub struct AadClient {
    http: reqwest::Client,
    client_id: String,
    token_url: String,
    device_url: String,
}

impl AadClient {
    pub fn new(http: reqwest::Client, client_id: &str, tenant: &str) -> Self {
        let base = format!("https://login.microsoftonline.com/{tenant}/oauth2/v2.0");
        Self {
            http,
            client_id: client_id.to_string(),
            token_url: format!("{base}/token"),
            device_url: format!("{base}/devicecode"),
        }
    }

    /// Start a device-code sign-in for the given space-separated scopes.
    pub async fn request_device_code(&self, scope: &str) -> Result<DeviceCode> {
        let response = self
            .http
            .post(&self.device_url)
            .form(&[("client_id", self.client_id.as_str()), ("scope", scope)])
            .send()
            .await
            .context("Device code request failed to send")?;
        parse_json(response, "device code request").await
    }

    /// Poll until the user completes sign-in, the code expires, or sign-in fails.
    pub async fn poll_device_token(&self, code: &DeviceCode) -> Result<TokenSet> {
        let mut interval = code.interval.unwrap_or(DEFAULT_POLL_INTERVAL_SECS).max(1);
        let lifetime = Duration::from_secs(code.expires_in.unwrap_or(900));
        let deadline = Instant::now() + lifetime;
        loop {
            tokio::time::sleep(Duration::from_secs(interval)).await;
            if Instant::now() >= deadline {
                bail!("Device code expired before sign-in was completed");
            }
            let response = self
                .http
                .post(&self.token_url)
                .form(&[
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                    ("client_id", self.client_id.as_str()),
                    ("device_code", code.device_code.as_str()),
                ])
                .send()
                .await
                .context("Token poll failed to send")?;
            match poll_result(response).await? {
                Ok(tokens) => return Ok(tokens),
                Err(PollOutcome::Pending) => {}
                Err(PollOutcome::SlowDown) => interval += SLOW_DOWN_STEP_SECS,
            }
        }
    }

    /// Exchange a refresh token for tokens with the given scopes.
    pub async fn refresh(&self, refresh_token: &str, scope: &str) -> Result<TokenSet> {
        let response = self
            .http
            .post(&self.token_url)
            .form(&[
                ("grant_type", "refresh_token"),
                ("client_id", self.client_id.as_str()),
                ("refresh_token", refresh_token),
                ("scope", scope),
            ])
            .send()
            .await
            .context("Token refresh failed to send")?;
        parse_json(response, "token refresh").await
    }
}

/// Decode a success body, or turn an OAuth2 error body into an error.
async fn parse_json<T: for<'de> Deserialize<'de>>(
    response: reqwest::Response,
    what: &str,
) -> Result<T> {
    let status = response.status();
    let body = response
        .bytes()
        .await
        .with_context(|| format!("Failed to read {what} response"))?;
    decode(status, &body, what)
}

fn decode<T: for<'de> Deserialize<'de>>(
    status: reqwest::StatusCode,
    body: &[u8],
    what: &str,
) -> Result<T> {
    if status.is_success() {
        return serde_json::from_slice(body)
            .with_context(|| format!("Unexpected {what} response shape"));
    }
    match serde_json::from_slice::<ErrorBody>(body) {
        Ok(err) => bail!("{what} rejected ({status}): {}", err.summary()),
        Err(_) => bail!("{what} failed with HTTP {status}"),
    }
}

/// Classify one device-code poll: tokens, keep waiting, or a hard failure.
async fn poll_result(
    response: reqwest::Response,
) -> Result<std::result::Result<TokenSet, PollOutcome>> {
    let status = response.status();
    let body = response
        .bytes()
        .await
        .context("Failed to read token poll response")?;
    classify_poll(status, &body)
}

fn classify_poll(
    status: reqwest::StatusCode,
    body: &[u8],
) -> Result<std::result::Result<TokenSet, PollOutcome>> {
    if status.is_success() {
        return Ok(Ok(decode(status, body, "token poll")?));
    }
    if let Ok(err) = serde_json::from_slice::<ErrorBody>(body) {
        match err.error.as_str() {
            "authorization_pending" => return Ok(Err(PollOutcome::Pending)),
            "slow_down" => return Ok(Err(PollOutcome::SlowDown)),
            _ => bail!("Sign-in failed ({status}): {}", err.summary()),
        }
    }
    bail!("Token poll failed with HTTP {status}")
}

/// Accept a lifetime sent as either a JSON number or a numeric string.
fn seconds<'de, D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Option<u64>, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Raw {
        Num(u64),
        Str(String),
    }
    Ok(match Option::<Raw>::deserialize(d)? {
        Some(Raw::Num(n)) => Some(n),
        Some(Raw::Str(s)) => s.trim().parse().ok(),
        None => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::StatusCode;

    #[test]
    fn token_set_accepts_numeric_and_string_lifetimes() {
        let a: TokenSet = decode(
            StatusCode::OK,
            br#"{"access_token":"a","expires_in":3599}"#,
            "t",
        )
        .unwrap();
        assert_eq!(a.expires_in, Some(3599));
        assert_eq!(a.refresh_token, None);
        let b: TokenSet = decode(
            StatusCode::OK,
            br#"{"access_token":"a","refresh_token":"r","expires_in":"3599"}"#,
            "t",
        )
        .unwrap();
        assert_eq!(b.expires_in, Some(3599));
        assert_eq!(b.refresh_token.as_deref(), Some("r"));
    }

    #[test]
    fn device_code_parses_azure_ad_shape() {
        let body = br#"{"user_code":"ABQK4PKP6","device_code":"dc","verification_uri":"https://login.microsoft.com/device","expires_in":900,"interval":5,"message":"m"}"#;
        let code: DeviceCode = decode(StatusCode::OK, body, "d").unwrap();
        assert_eq!(code.user_code, "ABQK4PKP6");
        assert_eq!(code.interval, Some(5));
        assert_eq!(code.expires_in, Some(900));
    }

    #[test]
    fn poll_distinguishes_pending_slow_down_and_failure() {
        let pending = classify_poll(
            StatusCode::BAD_REQUEST,
            br#"{"error":"authorization_pending"}"#,
        )
        .unwrap();
        assert_eq!(pending.unwrap_err(), PollOutcome::Pending);
        let slow = classify_poll(StatusCode::BAD_REQUEST, br#"{"error":"slow_down"}"#).unwrap();
        assert_eq!(slow.unwrap_err(), PollOutcome::SlowDown);
        let declined = classify_poll(
            StatusCode::BAD_REQUEST,
            br#"{"error":"authorization_declined","error_description":"AADSTS70000: The user declined.\r\nTrace ID: x"}"#,
        )
        .unwrap_err()
        .to_string();
        assert!(declined.contains("authorization_declined"));
        assert!(declined.contains("AADSTS70000"));
        assert!(
            !declined.contains("Trace ID"),
            "only the first line is kept"
        );
        let ok = classify_poll(StatusCode::OK, br#"{"access_token":"a"}"#).unwrap();
        assert_eq!(ok.unwrap().access_token, "a");
    }

    #[test]
    fn errors_never_echo_unparsed_bodies() {
        let err = decode::<TokenSet>(StatusCode::INTERNAL_SERVER_ERROR, b"secret-ish body", "t")
            .unwrap_err()
            .to_string();
        assert!(!err.contains("secret-ish"));
        assert!(err.contains("500"));
    }
}
