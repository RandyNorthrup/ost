//! Teams' engagement surfaces (its first-run tips and banners): the
//! middle tier keeps which "actions" you've done, `GET {mt}/beta/me/
//! engagementSurfaces` (`userState.completedActions[].action`), and the
//! client reports new ones with `PUT {mt}/beta/me/engagementSurfaces/
//! actions` `{"items":[{"action":…}]}` (captured from Teams desktop). The
//! threads-layout channel banner, for one, shows until
//! `ThreadedChannelInteraction` is done: a message sent in a threads
//! channel's main view.

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// Teams' action for sending in a threads-layout channel's main view.
pub const THREADED_CHANNEL_INTERACTION: &str = "ThreadedChannelInteraction";

/// The actions you've done, from the service's user state.
pub fn completed_actions(v: &Value) -> Vec<String> {
    v.pointer("/userState/completedActions")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .filter_map(|a| a["action"].as_str().map(str::to_string))
        .collect()
}

pub async fn load_completed_actions(client: &TeamsClient) -> Result<Vec<String>> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .get(format!("{base}/beta/me/engagementSurfaces"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Engagement surfaces")?
        .json()
        .await?;
    Ok(completed_actions(&v))
}

pub async fn record_action(client: &TeamsClient, action: &str) -> Result<()> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    client
        .http()
        .put(format!("{base}/beta/me/engagementSurfaces/actions"))
        .bearer_auth(&token)
        .json(&json!({ "items": [{ "action": action }] }))
        .send()
        .await?
        .error_for_status()
        .context("Engagement action")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_completed_actions() {
        // OST Test 1's state (2026-11-11), shortened.
        let v = json!({"displayed": [], "userState": {"completedActions": [{"action": "ThreadedChannelInteraction"}, {"action": "ShareFile"}]}});
        assert_eq!(completed_actions(&v), vec!["ThreadedChannelInteraction", "ShareFile"]);
        assert!(completed_actions(&json!({})).is_empty());
    }
}
