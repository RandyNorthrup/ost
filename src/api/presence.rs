//! Presence API for Microsoft Teams

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use super::client::TeamsClient;

#[derive(Debug, Deserialize)]
struct PresenceResponse {
    availability: String,
    activity: String,
}

/// Get current presence status (prints to stdout).
pub async fn get_presence() -> Result<()> {
    let client = TeamsClient::new().await?;
    let info = get_presence_data(&client).await?;

    println!("\nPresence Status:");
    println!("  Availability: {}", info.availability);
    println!("  Activity: {}", info.activity);

    Ok(())
}

// ---------------------------------------------------------------------------
// Data-returning API functions for TUI integration
// ---------------------------------------------------------------------------

/// Presence info for TUI display.
#[allow(dead_code)]
pub struct PresenceInfo {
    pub availability: String,
    pub activity: String,
}

/// Fetch current presence and return structured data.
pub async fn get_presence_data(client: &TeamsClient) -> Result<PresenceInfo> {
    let resp = client.graph_get("/me/presence").await?;
    let presence: PresenceResponse = resp
        .json()
        .await
        .context("Failed to parse presence response")?;

    Ok(PresenceInfo {
        availability: presence.availability,
        activity: presence.activity,
    })
}

/// Set presence status
pub async fn set_presence(status: &str) -> Result<()> {
    let (availability, activity) = match status.to_lowercase().as_str() {
        "available" => ("Available", "Available"),
        "busy" => ("Busy", "InACall"),
        "dnd" | "donotdisturb" => ("DoNotDisturb", "Presenting"),
        "away" => ("Away", "Away"),
        "offline" => ("Offline", "OffWork"),
        other => bail!(
            "Unknown status: {}. Use: available, busy, dnd, away, offline",
            other
        ),
    };

    let client = TeamsClient::new().await?;
    let body = serde_json::json!({
        "sessionId": "teams-cli",
        "availability": availability,
        "activity": activity,
        "expirationDuration": "PT1H"
    });

    client
        .graph_post("/me/presence/setUserPreferredPresence", &body)
        .await?;

    println!("Presence set to: {}", status);
    Ok(())
}

/// Presence service audience and front door.
const PRESENCE_SCOPE: &str = "https://presence.teams.microsoft.com/.default";
const PRESENCE_URL: &str = "https://presence.teams.microsoft.com";

/// Tell the presence service this endpoint (the Trouter `epid`) is online
/// and active. Without an active endpoint the user shows as Offline and
/// incoming calls are not offered to it; they go straight to voicemail.
pub async fn publish_endpoint(http: &reqwest::Client, epid: &str) -> Result<()> {
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let endpoint = serde_json::json!({
        "id": epid,
        "activity": "Available",
        "availability": "Available",
        "deviceType": "Desktop",
    });
    let url = format!("{PRESENCE_URL}/v1/me/endpoints/");
    let resp = http
        .put(&url)
        .bearer_auth(&token)
        .json(&endpoint)
        .send()
        .await
        .context("Presence endpoint PUT failed to send")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Presence endpoint PUT failed: HTTP {status}");
    }
    tracing::debug!("Presence endpoint published ({status})");
    Ok(())
}

/// Someone's presence as the presence service reports it.
#[derive(Debug, Clone, serde::Serialize)]
pub struct UserPresence {
    pub mri: String,
    /// Available, Busy, DoNotDisturb, BeRightBack, Away, Offline, …
    pub availability: String,
    pub activity: String,
}

/// Look up several users' presence by MRI (`8:orgid:<oid>`).
pub async fn get_presences(http: &reqwest::Client, mris: &[String]) -> Result<Vec<UserPresence>> {
    if mris.is_empty() {
        return Ok(Vec::new());
    }
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let body: Vec<serde_json::Value> = mris
        .iter()
        .map(|m| serde_json::json!({ "mri": m }))
        .collect();
    let resp = http
        .post(format!("{PRESENCE_URL}/v1/presence/getpresence/"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await
        .context("Presence lookup failed to send")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Presence lookup failed: HTTP {status}");
    }
    let v: serde_json::Value = resp.json().await.context("Presence lookup reply")?;
    Ok(parse_presences(&v))
}

fn parse_presences(v: &serde_json::Value) -> Vec<UserPresence> {
    v.as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let mri = e.get("mri")?.as_str()?.to_string();
            let p = e.get("presence").unwrap_or(e);
            let field = |k: &str| {
                p.get(k)
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string()
            };
            Some(UserPresence {
                mri,
                availability: field("availability"),
                activity: field("activity"),
            })
        })
        .collect()
}

#[cfg(test)]
mod presence_tests {
    use super::*;

    #[test]
    fn parses_presence_service_reply() {
        let v = serde_json::json!([
            {"mri": "8:orgid:a", "presence": {"availability": "Available", "activity": "Available"}},
            {"mri": "8:orgid:b", "presence": {"availability": "Busy", "activity": "InACall"}},
            {"nomri": true}
        ]);
        let p = parse_presences(&v);
        assert_eq!(p.len(), 2);
        assert_eq!(p[1].availability, "Busy");
        assert_eq!(p[1].activity, "InACall");
    }
}
