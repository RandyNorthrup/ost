//! Skype token exchange
//!
//! After obtaining an AAD access token, exchange it for a Skype token
//! via the Teams authsvc endpoint. The Skype token is what Teams APIs
//! actually require for most operations.
//!
//! A personal account's token comes from Teams free's consumer authz
//! (v2, with the `auth.fl` token), whose answer has another shape:
//! `skypeToken.skypetoken` with the account's `skypeid`, and
//! `consumerLicenseDetails` in place of `licenseDetails`.

use anyhow::{Context, Result, bail};
use serde::Deserialize;

/// Response from Teams authsvc token exchange
#[derive(Debug, Deserialize)]
pub struct AuthzResponse {
    pub tokens: Option<AuthzTokens>,
    #[serde(rename = "regionGtms")]
    pub region_gtms: Option<serde_json::Value>,
    /// The user's licences (Teams' ECS filters and feature gates read it).
    #[serde(rename = "licenseDetails")]
    pub license_details: Option<serde_json::Value>,
    /// The consumer authz's token (`skypeToken`).
    #[serde(rename = "skypeToken")]
    pub consumer: Option<ConsumerSkypeToken>,
    /// The consumer authz's licences (Teams free's limits).
    #[serde(rename = "consumerLicenseDetails")]
    pub consumer_license_details: Option<serde_json::Value>,
}

/// The consumer authz's `skypeToken` object.
#[derive(Debug, Deserialize)]
pub struct ConsumerSkypeToken {
    pub skypetoken: Option<String>,
    #[serde(rename = "expiresIn")]
    pub expires_in: Option<u64>,
    /// The account's Skype ID (`live:.cid.…`): its MRI without the `8:`.
    pub skypeid: Option<String>,
    /// Its display name.
    pub signinname: Option<String>,
}

/// What a token exchange gives back.
pub struct Exchanged {
    pub skype_token: String,
    pub expires_in: Option<u64>,
    pub region_gtms: Option<serde_json::Value>,
    pub license_details: Option<serde_json::Value>,
    /// A personal account's Skype ID (`live:.cid.…`), from the consumer authz.
    pub skype_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AuthzTokens {
    #[serde(rename = "skypeToken")]
    pub skype_token: Option<String>,
    #[serde(rename = "expiresIn")]
    pub expires_in: Option<u64>,
}

const AUTHZ_URL_WORK: &str = "https://teams.microsoft.com/api/authsvc/v1.0/authz";
/// Teams free's consumer authz, v2 (what its web client calls; v1 refuses
/// the web client's tokens, captured 2026-11-27).
const AUTHZ_URL_PERSONAL: &str = "https://teams.live.com/api/auth/v2.0/authz/consumer";
/// The token audience the consumer authz takes.
pub const PERSONAL_AUTHZ_SCOPE: &str = "https://auth.fl.teams.microsoft.com/teams.auth.readwrite";
/// Teams on the web for personal use's client type and version, as its
/// authz requests name them.
const PERSONAL_CLIENT_VERSION: &str = "1415/26101516645";

/// Exchange an AAD access token for a Skype token: a work account's at
/// authsvc, or (`personal`) a personal account's `auth.fl` token at the
/// consumer authz.
pub async fn exchange_skype_token(aad_token: &str, personal: bool) -> Result<Exchanged> {
    let url = if personal {
        AUTHZ_URL_PERSONAL
    } else {
        AUTHZ_URL_WORK
    };

    tracing::debug!("Exchanging AAD token for Skype token at {}", url);

    let client = reqwest::Client::new();
    let mut req = client
        .post(url)
        .bearer_auth(aad_token)
        .header("Content-Length", "0");
    if personal {
        req = req
            .header("ms-teams-authz-type", "ExplicitLogin")
            .header("x-ms-client-type", "web")
            .header("x-ms-client-version", PERSONAL_CLIENT_VERSION)
            .header("claimschallengecapable", "true");
    }
    let resp = req
        .send()
        .await
        .context("Failed to call authsvc for Skype token exchange")?;

    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        bail!(
            "Skype token exchange failed (HTTP {}): {}",
            status.as_u16(),
            body
        );
    }

    let authz: AuthzResponse = resp
        .json()
        .await
        .context("Failed to parse authsvc response")?;
    exchanged(authz)
}

/// The token and what came with it, from either answer's shape.
fn exchanged(authz: AuthzResponse) -> Result<Exchanged> {
    if let Some(c) = authz.consumer {
        return Ok(Exchanged {
            skype_token: c
                .skypetoken
                .context("consumer authz response missing 'skypetoken'")?,
            expires_in: c.expires_in,
            region_gtms: authz.region_gtms,
            license_details: authz.consumer_license_details.or(authz.license_details),
            skype_id: c.skypeid.filter(|s| !s.is_empty()),
        });
    }
    let tokens = authz
        .tokens
        .context("authsvc response missing 'tokens' field")?;
    let skype_token = tokens
        .skype_token
        .context("authsvc response missing 'skypeToken'")?;

    Ok(Exchanged {
        skype_token,
        expires_in: tokens.expires_in,
        region_gtms: authz.region_gtms,
        license_details: authz.license_details,
        skype_id: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_authz_answers_give_the_token() {
        let work: AuthzResponse = serde_json::from_str(
            r#"{"tokens":{"skypeToken":"w","expiresIn":86399},"regionGtms":{"chatService":"https://amer.ng.msg.teams.microsoft.com"},"licenseDetails":{"isFreemium":false}}"#,
        )
        .unwrap();
        let w = exchanged(work).unwrap();
        assert_eq!((w.skype_token.as_str(), w.expires_in), ("w", Some(86399)));
        assert_eq!(w.skype_id, None);
        // Teams free's (shape captured 2026-11-27).
        let personal: AuthzResponse = serde_json::from_str(
            r#"{"skypeToken":{"skypetoken":"p","expiresIn":28799,"skypeid":"live:.cid.ca2738c364862c6","signinname":"OST Personal 2","isBusinessTenant":false},"regionGtms":{"chatServiceAfd":"https://teams.live.com/api/chatsvc/consumer"},"regionSettings":{},"consumerLicenseDetails":{"maxMeetingDurationMinutes":60}}"#,
        )
        .unwrap();
        let p = exchanged(personal).unwrap();
        assert_eq!((p.skype_token.as_str(), p.expires_in), ("p", Some(28799)));
        assert_eq!(p.skype_id.as_deref(), Some("live:.cid.ca2738c364862c6"));
        assert_eq!(p.license_details.unwrap()["maxMeetingDurationMinutes"], 60);
        assert!(p.region_gtms.is_some());
        let empty: AuthzResponse = serde_json::from_str("{}").unwrap();
        assert!(exchanged(empty).is_err());
    }
}
