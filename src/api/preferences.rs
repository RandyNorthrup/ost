//! Teams' personal settings (the `userPersonalSettings` user property, a
//! JSON string): what the client remembers for you across devices, such as
//! the 1:1 chat header's last call choice.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// The user property holding the settings.
const PROPERTY: &str = "userPersonalSettings";

/// Your settings, `{}` when none are saved.
pub async fn personal_settings(client: &TeamsClient) -> Result<serde_json::Value> {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("User properties reply")?;
    Ok(v.get(PROPERTY)
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_else(|| serde_json::json!({})))
}

/// `patch` merged into `base`, objects key by key (Teams' updateUserPreferences
/// changes only the settings it is given).
pub fn merged(mut base: serde_json::Value, patch: &serde_json::Value) -> serde_json::Value {
    match (base.as_object_mut(), patch.as_object()) {
        (Some(b), Some(p)) => {
            for (k, v) in p {
                let old = b.remove(k).unwrap_or(serde_json::Value::Null);
                b.insert(k.clone(), merged(old, v));
            }
            base
        }
        _ => patch.clone(),
    }
}

/// Change some settings, keeping the rest: `PUT /v1/users/ME/properties?
/// name=userPersonalSettings` with the whole JSON string.
pub async fn update_personal_settings(
    client: &TeamsClient,
    patch: &serde_json::Value,
) -> Result<()> {
    let all = merged(personal_settings(client).await?, patch);
    let url = format!(
        "{}/v1/users/ME/properties?name={PROPERTY}",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ PROPERTY: all.to_string() }),
        )
        .await?;
    Ok(())
}

/// The 1:1 header's call button: video when the last call you placed from
/// it was a video call (`chatSettings.mruChatHeaderCallOption`, default
/// `VOICE_CALL`).
pub fn header_call_is_video(settings: &serde_json::Value) -> bool {
    settings
        .pointer("/chatSettings/mruChatHeaderCallOption")
        .and_then(|v| v.as_str())
        == Some("VIDEO_CALL")
}

/// The patch that remembers the header's call choice, as Teams writes it.
pub fn header_call_patch(video: bool) -> serde_json::Value {
    serde_json::json!({ "chatSettings": { "mruChatHeaderCallOption": if video { "VIDEO_CALL" } else { "VOICE_CALL" } } })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_call_choice_merges_into_the_other_settings() {
        // As ost-test1's settings were before any call.
        let before = serde_json::json!({"messagingSettings": {"hasUserSeenFollowUnfollowPostReplyChannel": true}});
        assert!(!header_call_is_video(&before));
        let after = merged(before, &header_call_patch(true));
        assert!(header_call_is_video(&after));
        assert_eq!(
            after["messagingSettings"]["hasUserSeenFollowUnfollowPostReplyChannel"],
            true
        );
        let back = merged(after, &header_call_patch(false));
        assert_eq!(
            back["chatSettings"]["mruChatHeaderCallOption"],
            "VOICE_CALL"
        );
        assert_eq!(back.as_object().unwrap().len(), 2);
    }
}
