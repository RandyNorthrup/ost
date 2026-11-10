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

/// The `callAccessibilitySettings` user property: live captions' "Always
/// turn on captions" (`startCaptionsAutomatically`) and "Filter profane
/// words" (`profanityFilterEnabled`), with Teams' other calling
/// accessibility settings.
const CALL_ACCESSIBILITY: &str = "callAccessibilitySettings";

/// Teams' defaults for the calling accessibility settings (its
/// `callAccessibilitySettings` reader when none are saved).
pub fn call_accessibility_defaults() -> serde_json::Value {
    serde_json::json!({
        "accessibilityModeEnabled": false,
        "accessibilityModeEnabledV2": false,
        "selectedInterpreters": [],
        "selectedDHHInterpreters": [],
        "startCaptionsAutomatically": false,
        "profanityFilterEnabled": false,
        "signLanguageModeSelection": "SIGNER",
        "showSignerIdentificationToOthers": true,
        "hideCallMonitorOnMinimize": false,
    })
}

/// Your calling accessibility settings (Teams' defaults where unsaved).
pub async fn call_accessibility_settings(client: &TeamsClient) -> Result<serde_json::Value> {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("User properties reply")?;
    Ok(call_accessibility_from_properties(&v))
}

/// The settings in a user properties object, over Teams' defaults.
pub fn call_accessibility_from_properties(v: &serde_json::Value) -> serde_json::Value {
    let saved = v
        .get(CALL_ACCESSIBILITY)
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str::<serde_json::Value>(s).ok())
        .unwrap_or_else(|| serde_json::json!({}));
    merged(call_accessibility_defaults(), &saved)
}

/// Change some calling accessibility settings: Teams PUTs the whole object
/// (as its GraphQL cache holds it, `__typename` included).
pub async fn update_call_accessibility_settings(
    client: &TeamsClient,
    patch: &serde_json::Value,
) -> Result<serde_json::Value> {
    let mut all = merged(call_accessibility_settings(client).await?, patch);
    if let Some(o) = all.as_object_mut() {
        o.insert("__typename".into(), "CallAccessibilitySettings".into());
    }
    let url = format!(
        "{}/v1/users/ME/properties?name={CALL_ACCESSIBILITY}",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ CALL_ACCESSIBILITY: all.to_string() }),
        )
        .await?;
    Ok(all)
}

/// Settings kept as user properties whose value is a JSON object in a
/// string (Teams merges the changed keys into the whole object).
pub const JSON_PROPERTIES: [&str; 4] = [
    PROPERTY,
    CALL_ACCESSIBILITY,
    "simpleCollabUserSettings",
    "suggestedRepliesSettings",
];

/// Settings kept as plain string user properties ("true", "COMFY", …),
/// written as Teams' Settings writes them.
pub const PLAIN_PROPERTIES: [&str; 7] = [
    "messageDensity",
    "readReceiptsEnabled",
    "enableChannelsV2",
    "userEnableSurveysNotification",
    "showInMeetingReport",
    "enablePushToTalk",
    "preferredSkinToneIndex",
];

/// All your user properties, the JSON-string ones parsed (Settings reads
/// these; unsaved settings are absent and take Teams' defaults).
pub async fn all_properties(client: &TeamsClient) -> Result<serde_json::Value> {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("User properties reply")?;
    Ok(parsed_properties(&v))
}

/// The properties with JSON-string objects parsed into objects.
pub fn parsed_properties(v: &serde_json::Value) -> serde_json::Value {
    let mut out = serde_json::Map::new();
    for (k, x) in v.as_object().into_iter().flatten() {
        let parsed = x
            .as_str()
            .filter(|_| JSON_PROPERTIES.contains(&k.as_str()))
            .and_then(|s| serde_json::from_str::<serde_json::Value>(s).ok())
            .unwrap_or_else(|| x.clone());
        out.insert(k.clone(), parsed);
    }
    serde_json::Value::Object(out)
}

/// Change a setting kept in a user property: for a JSON one, `value` is a
/// patch merged into what is saved; for a plain one, the string itself.
/// Returns the property's new value.
pub async fn set_property(client: &TeamsClient, name: &str, value: &serde_json::Value) -> Result<serde_json::Value> {
    let saved = if JSON_PROPERTIES.contains(&name) {
        if name == CALL_ACCESSIBILITY {
            return update_call_accessibility_settings(client, value).await;
        }
        let all = all_properties(client).await?;
        let base = all.get(name).cloned().filter(|b| b.is_object()).unwrap_or_else(|| serde_json::json!({}));
        let next = merged(base, value);
        (next.to_string(), next)
    } else if PLAIN_PROPERTIES.contains(&name) {
        let s = value.as_str().map(str::to_string).unwrap_or_else(|| value.to_string());
        (s.clone(), serde_json::Value::String(s))
    } else {
        anyhow::bail!("Not a setting: {name}");
    };
    let url = format!("{}/v1/users/ME/properties?name={name}", client.chat_service_url());
    client
        .chat_request(reqwest::Method::PUT, &url, &serde_json::json!({ name: saved.0 }))
        .await?;
    Ok(saved.1)
}

/// Settings Teams keeps in the middle tier (captured on winpc 2026-11-10):
/// "Set my status to do not disturb when I'm sharing my screen"
/// (`PUT beta/usersettings/allowAutoDndSettings {isEnabled}`, write only;
/// on unless saved off), "Block calls with no caller ID" (`POST
/// beta/usersettings/blockedCallers {blockAnonymousCaller}`, read with GET)
/// and "Automatically identify me in live captions and live transcripts"
/// (`beta/users/{get,update}UserTranscriptMeetingSettings/tenant/{t}/user/{o}`
/// with `attributionSettings.enableSpeakerAttribution`).
pub async fn middle_tier_settings(client: &TeamsClient) -> Result<serde_json::Value> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let get = |path: String| {
        let req = client.http().get(format!("{mt}/{path}")).bearer_auth(token.clone());
        async move {
            let r = req.send().await.ok()?;
            if !r.status().is_success() {
                return None;
            }
            r.json::<serde_json::Value>().await.ok()
        }
    };
    let blocked = get("beta/usersettings/blockedCallers".into()).await;
    let transcript = match (client.tenant_id(), client.object_id()) {
        (Some(t), Some(o)) => get(format!("beta/users/getUserTranscriptMeetingSettings/tenant/{t}/user/{o}")).await,
        _ => None,
    };
    Ok(serde_json::json!({
        "blockAnonymousCaller": blocked.as_ref().and_then(|b| b["blockAnonymousCaller"].as_bool()).unwrap_or(false),
        "enableSpeakerAttribution": transcript.as_ref().and_then(|t| t.pointer("/attributionSettings/enableSpeakerAttribution")?.as_bool()).unwrap_or(true),
    }))
}

/// Your calling settings, as Settings ▸ Calls reads them (`GET {mt}/beta/
/// usersettings/{mri}/voicesettings`): {callRedirectionSettings, …}.
pub async fn voice_settings(client: &TeamsClient) -> Result<serde_json::Value> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let oid = client.object_id().context("No user id")?;
    let resp = client
        .http()
        .get(format!("{mt}/beta/usersettings/8:orgid:{oid}/voicesettings"))
        .bearer_auth(token)
        .send()
        .await
        .context("Voice settings request")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} reading voice settings", resp.status().as_u16());
    }
    resp.json().await.context("Voice settings reply")
}

/// Teams' call redirection body (captured 2026-11-10) from the page's
/// choices: forward everything to voicemail, or ring and then redirect
/// unanswered calls to voicemail (or not) after `delay` seconds.
pub fn call_redirection_body(forward_all: bool, unanswered_to_voicemail: bool, delay: u32) -> serde_json::Value {
    let forwarding = if forward_all {
        serde_json::json!({ "isEnabled": true, "forwardingType": "Immediate", "targetType": "Voicemail", "target": null, "delaySeconds": 0 })
    } else {
        serde_json::json!({ "isEnabled": false, "forwardingType": "Simultaneous", "target": null, "delaySeconds": 0 })
    };
    serde_json::json!({
        "callForwardingSettings": forwarding,
        "callGroupDetails": { "callOrder": "simultaneous", "delaySeconds": 0, "targets": [] },
        "unansweredCallSettings": { "isEnabled": !forward_all && unanswered_to_voicemail, "targetType": "Voicemail", "target": null, "delaySeconds": delay, "safeForward": false },
        "favoriteTargets": { "targets": [] },
    })
}

/// Save a Settings ▸ Calls change: "redirection" (a call_redirection_body)
/// or "voicemail" (Teams' voicemail settings with only the changed keys
/// set, the rest null).
pub async fn set_voice_setting(client: &TeamsClient, which: &str, body: &serde_json::Value) -> Result<()> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let oid = client.object_id().context("No user id")?;
    let (path, body) = match which {
        "redirection" => ("callredirectionsettings", body.clone()),
        "voicemail" => {
            let mut all = serde_json::json!({
                "vmEnabled": null, "vmUseOof": null, "vmUseAutoRepliesForOof": null, "vmUseCalForOof": null,
                "vmCallAnswerRule": null, "vmAudioLang": null, "vmTransferTarget": null,
                "vmDefaultGreetingPromptOverwrite": null, "vmDefaultOofGreetingPromptOverwrite": null,
            });
            for (k, v) in body.as_object().into_iter().flatten() {
                all[k] = v.clone();
            }
            ("voicemailsettings", all)
        }
        _ => anyhow::bail!("Not a calls setting: {which}"),
    };
    let resp = client
        .http()
        .post(format!("{mt}/beta/usersettings/8:orgid:{oid}/{path}"))
        .bearer_auth(token)
        .json(&body)
        .send()
        .await
        .context("Calls setting save")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} saving {which}", resp.status().as_u16());
    }
    Ok(())
}

/// Change one of the middle tier's settings: "allowAutoDnd",
/// "blockAnonymousCaller" or "enableSpeakerAttribution".
pub async fn set_middle_tier_setting(client: &TeamsClient, key: &str, on: bool) -> Result<()> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let http = client.http();
    let req = match key {
        "allowAutoDnd" => http
            .put(format!("{mt}/beta/usersettings/allowAutoDndSettings"))
            .json(&serde_json::json!({ "isEnabled": on })),
        "blockAnonymousCaller" => http
            .post(format!("{mt}/beta/usersettings/blockedCallers"))
            .json(&serde_json::json!({ "blockAnonymousCaller": on })),
        "enableSpeakerAttribution" => {
            let (t, o) = client.tenant_id().zip(client.object_id()).context("No tenant or user id")?;
            http.put(format!("{mt}/beta/users/updateUserTranscriptMeetingSettings/tenant/{t}/user/{o}"))
                .json(&serde_json::json!({ "attributionSettings": { "enableSpeakerAttribution": on } }))
        }
        _ => anyhow::bail!("Not a setting: {key}"),
    };
    let resp = req.bearer_auth(token).send().await.context("Settings request")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} saving {key}", resp.status().as_u16());
    }
    Ok(())
}

/// Your out of office automatic replies, as Teams' Settings ▸ General ▸
/// Out of office reads them (`GET {mt}/beta/users/automaticRepliesSetting`):
/// {status: disabled | alwaysEnabled | scheduled, internalReplyMessage,
/// externalReplyMessage, externalAudience: none | contactsOnly | all,
/// scheduledStartDateTime, scheduledEndDateTime}.
pub async fn automatic_replies(client: &TeamsClient) -> Result<serde_json::Value> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let resp = client
        .http()
        .get(format!("{mt}/beta/users/automaticRepliesSetting"))
        .bearer_auth(token)
        .send()
        .await
        .context("Out of office request")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} reading out of office", resp.status().as_u16());
    }
    resp.json().await.context("Out of office reply")
}

/// Save them as Teams' Save does (captured on winpc 2026-11-10): `POST
/// {mt}/beta/users/updateAutomaticRepliesSetting` with all six fields.
pub async fn set_automatic_replies(client: &TeamsClient, setting: &serde_json::Value) -> Result<()> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let body = automatic_replies_body(setting);
    let resp = client
        .http()
        .post(format!("{mt}/beta/users/updateAutomaticRepliesSetting"))
        .bearer_auth(token)
        .json(&body)
        .send()
        .await
        .context("Out of office save")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} saving out of office", resp.status().as_u16());
    }
    Ok(())
}

/// Teams' save body, in its order, from what the page holds.
pub fn automatic_replies_body(v: &serde_json::Value) -> serde_json::Value {
    let s = |k: &str, d: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or(d).to_string();
    serde_json::json!({
        "status": s("status", "disabled"),
        "internalReplyMessage": s("internalReplyMessage", ""),
        "externalReplyMessage": s("externalReplyMessage", ""),
        "externalAudience": s("externalAudience", "all"),
        "scheduledStartDateTime": s("scheduledStartDateTime", ""),
        "scheduledEndDateTime": s("scheduledEndDateTime", ""),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn call_redirection_bodies_are_teams() {
        // As Teams sent them on winpc (2026-11-10).
        assert_eq!(
            call_redirection_body(true, true, 20).to_string(),
            r#"{"callForwardingSettings":{"delaySeconds":0,"forwardingType":"Immediate","isEnabled":true,"target":null,"targetType":"Voicemail"},"callGroupDetails":{"callOrder":"simultaneous","delaySeconds":0,"targets":[]},"favoriteTargets":{"targets":[]},"unansweredCallSettings":{"delaySeconds":20,"isEnabled":false,"safeForward":false,"target":null,"targetType":"Voicemail"}}"#
        );
        let off = call_redirection_body(false, true, 5);
        assert_eq!(off["callForwardingSettings"]["forwardingType"], "Simultaneous");
        assert_eq!(off["unansweredCallSettings"]["isEnabled"], true);
        assert_eq!(off["unansweredCallSettings"]["delaySeconds"], 5);
    }

    #[test]
    fn out_of_office_bodies_are_teams() {
        // As Teams saved "OST test 82" (2026-11-10).
        let b = automatic_replies_body(&serde_json::json!({
            "status": "scheduled", "internalReplyMessage": "OST test 82 out of office",
            "scheduledStartDateTime": "2026-11-10T08:00:00.000Z", "scheduledEndDateTime": "2026-11-11T08:00:00.000Z",
        }));
        assert_eq!(
            b.to_string(),
            r#"{"externalAudience":"all","externalReplyMessage":"","internalReplyMessage":"OST test 82 out of office","scheduledEndDateTime":"2026-11-11T08:00:00.000Z","scheduledStartDateTime":"2026-11-10T08:00:00.000Z","status":"scheduled"}"#
        );
    }

    #[test]
    fn json_properties_are_parsed_and_plain_ones_kept() {
        // As ost-test1's properties read on 2026-11-10.
        let raw = serde_json::json!({
            "messageDensity": "COMFY",
            "readReceiptsEnabled": "true",
            "simpleCollabUserSettings": "{\"hasUserEnabledShowTimeStamps\":false}",
            "userPersonalSettings": "{\"chatSettings\":{\"mruChatHeaderCallOption\":\"VOICE_CALL\"}}",
            "favorites": "{\"48:notes\":1}",
        });
        let p = parsed_properties(&raw);
        assert_eq!(p["messageDensity"], "COMFY");
        assert_eq!(p["simpleCollabUserSettings"]["hasUserEnabledShowTimeStamps"], false);
        assert_eq!(p["userPersonalSettings"]["chatSettings"]["mruChatHeaderCallOption"], "VOICE_CALL");
        // Not a settings object: left as the string.
        assert!(p["favorites"].is_string());
    }

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

    #[test]
    fn accessibility_settings_over_teams_defaults() {
        // As ost-test1's property was after toggling Filter profane words.
        let props = serde_json::json!({"callAccessibilitySettings": "{\"accessibilityModeEnabled\":false,\"startCaptionsAutomatically\":false,\"profanityFilterEnabled\":true,\"signLanguageModeSelection\":\"SIGNER\",\"__typename\":\"CallAccessibilitySettings\"}"});
        let s = call_accessibility_from_properties(&props);
        assert_eq!(s["profanityFilterEnabled"], true);
        assert_eq!(s["showSignerIdentificationToOthers"], true);
        assert_eq!(s["selectedInterpreters"], serde_json::json!([]));
        let none = call_accessibility_from_properties(&serde_json::json!({}));
        assert_eq!(none, call_accessibility_defaults());
    }
}
