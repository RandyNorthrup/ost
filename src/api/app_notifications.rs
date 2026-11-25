//! Settings ▸ Notifications and activity ▸ Apps (Teams 26304's
//! activity-settings worker, `ml` / `sa` / `wl` / `Pi`): the apps whose
//! notifications you've had (Graph activities in your feed, their
//! `activityContext.teamsAppId`) or whose settings you've saved
//! (`userGraphSettings`), less the ones ECS hides
//! (activity.activityCustomizations' hideAppSettings) and Calendar (its
//! own section). Each lists its manifest's activity types
//! (`activities.activityItems`), or ECS's settingsAggregation groups.
//!
//! Choices per row: BannerAndFeed ("Show in Activity and banner"),
//! OnlyFeed ("Show in Activity"), Off — kept in the user property
//! userGraphSettings as `{appId: {activityGenerationSettings: {type:
//! bool}, toastSettings: {type: bool}, appNotificationEnabled: bool}}`; a
//! group reads as on when any of its types is and saves to all of them.

use serde_json::{Value, json};

/// Teams' Calendar app (Notifications' Calendar section).
pub const CALENDAR_APP: &str = "ef56c0de-36fc-4ef8-b417-3d82ba9d073c";

/// Teams 26304's default activity.activityCustomizations (config-prod),
/// for when ECS doesn't send its own.
pub fn default_customizations() -> Value {
    json!([
        { "appId": "9f1a4ae0-6ae2-475d-973d-c89687d03753", "hideAppSettings": true },
        { "appId": "2a84919f-59d8-4441-a975-2a8c2643b741", "hideAppSettings": true },
        { "appId": "d948be58-6ace-4f5a-a31c-0df7cf105a21", "hideAppSettings": true },
        { "appId": "eb62d082-2c0a-4672-9252-e8e456f192b1", "hideAppSettings": true },
        { "appId": CALENDAR_APP, "defaultAppSettings": "OnlyFeed" },
        { "appId": "1d192ad2-6590-4179-a088-daff383a52b5", "defaultAppSettings": "OnlyFeed" },
        { "appId": "981bbfd0-5eb8-4393-8158-bfff69d2d6b5", "defaultAppSettings": "OnlyFeed", "settingsAggregation": [
            { "key": "recapIsReadyForFollowedMeetings", "subTypes": ["recapIsReadyForFollowedMeetingsV2", "recapIsReadyForFollowedMeetings"] },
            { "key": "recapIsReady", "subTypes": ["recapIsReadyV2", "recapIsReady"] } ] }
    ])
}

/// The app ids in the order Teams meets them: the feed's (newest first),
/// then the saved settings'.
pub fn app_ids(
    feed_messages: &Value,
    graph_settings: &Value,
    customizations: &Value,
) -> Vec<String> {
    let hidden: Vec<String> = customizations
        .as_array()
        .into_iter()
        .flatten()
        .filter(|c| c["hideAppSettings"].as_bool() == Some(true))
        .filter_map(|c| c["appId"].as_str().map(str::to_lowercase))
        .collect();
    let mut out: Vec<String> = Vec::new();
    let mut add = |id: &str| {
        let id = id.to_lowercase();
        if !id.is_empty() && id != CALENDAR_APP && !hidden.contains(&id) && !out.contains(&id) {
            out.push(id);
        }
    };
    let mut msgs: Vec<&Value> = feed_messages.as_array().into_iter().flatten().collect();
    msgs.sort_by(|a, b| {
        b["composetime"]
            .as_str()
            .unwrap_or_default()
            .cmp(a["composetime"].as_str().unwrap_or_default())
    });
    for m in msgs {
        let a = &m["properties"]["activity"];
        let a: Value = a
            .as_str()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or_else(|| a.clone());
        if a["activityType"].as_str() == Some("msGraph")
            && let Some(id) = a
                .pointer("/activityContext/teamsAppId")
                .and_then(Value::as_str)
        {
            add(id);
        }
    }
    for k in graph_settings
        .as_object()
        .into_iter()
        .flat_map(|o| o.keys())
    {
        add(k);
    }
    out
}

/// One app's rows: [{key, label, subTypes}] and whether its banners are
/// on by default (not for defaultAppSettings OnlyFeed).
pub fn app_rows(definition: &Value, customizations: &Value) -> (Vec<Value>, bool) {
    let id = definition["id"].as_str().unwrap_or_default().to_lowercase();
    let custom = customizations
        .as_array()
        .into_iter()
        .flatten()
        .find(|c| c["appId"].as_str().map(str::to_lowercase).as_deref() == Some(id.as_str()));
    let toast_default = custom.and_then(|c| c["defaultAppSettings"].as_str()) != Some("OnlyFeed");
    let items: Vec<&Value> = definition
        .pointer("/activities/activityItems")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .collect();
    let label = |t: &str| {
        items
            .iter()
            .find(|i| i["type"].as_str() == Some(t))
            .and_then(|i| i["description"].as_str())
            .unwrap_or(t)
            .to_string()
    };
    let groups = custom
        .and_then(|c| c["settingsAggregation"].as_array())
        .filter(|g| !g.is_empty());
    let rows = match groups {
        Some(g) => g
            .iter()
            .filter_map(|x| {
                let key = x["key"].as_str()?;
                Some(json!({ "key": key, "label": label(key), "subTypes": x["subTypes"].clone() }))
            })
            .collect(),
        None => items
            .iter()
            .filter_map(|i| {
                let t = i["type"].as_str()?;
                Some(json!({ "key": t, "label": label(t), "subTypes": [t] }))
            })
            .collect(),
    };
    (rows, toast_default)
}

/// A row's choice: 0 BannerAndFeed, 1 OnlyFeed, 2 Off (Teams' `is` + `Lo`).
pub fn level(app_settings: &Value, sub_types: &[&str], toast_default: bool) -> u8 {
    let get = |cat: &str, t: &str, d: bool| app_settings[cat][t].as_bool().unwrap_or(d);
    let generation = sub_types
        .iter()
        .any(|t| get("activityGenerationSettings", t, true));
    let toast = sub_types
        .iter()
        .any(|t| get("toastSettings", t, toast_default));
    if !generation {
        2
    } else if toast {
        0
    } else {
        1
    }
}

/// The userGraphSettings patch for a row's choice.
pub fn level_patch(app_id: &str, sub_types: &[&str], level: u8) -> Value {
    let (generation, toast) = match level {
        0 => (true, true),
        1 => (true, false),
        _ => (false, false),
    };
    let mut gen_map = serde_json::Map::new();
    let mut toast_map = serde_json::Map::new();
    for t in sub_types {
        gen_map.insert(t.to_string(), json!(generation));
        toast_map.insert(t.to_string(), json!(toast));
    }
    json!({ app_id: { "activityGenerationSettings": gen_map, "toastSettings": toast_map } })
}

/// The app's switch (Teams' `Uw`): on sets every row to Show in Activity,
/// off to Off, with appNotificationEnabled.
pub fn switch_patch(app_id: &str, rows: &[Vec<&str>], on: bool) -> Value {
    let all: Vec<&str> = rows.iter().flatten().copied().collect();
    let mut p = level_patch(app_id, &all, if on { 1 } else { 2 });
    p[app_id]["appNotificationEnabled"] = json!(on);
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apps_come_from_the_feed_and_saved_settings() {
        let feed = json!([
            { "composetime": "2026-11-21T04:48:55Z", "properties": { "activity": "{\"activityType\":\"msGraph\",\"activityContext\":{\"teamsAppId\":\"981bbfd0-5eb8-4393-8158-bfff69d2d6b5\"}}" } },
            { "composetime": "2026-11-20T04:48:55Z", "properties": { "activity": { "activityType": "msGraph", "activityContext": { "teamsAppId": "2a84919f-59d8-4441-a975-2a8c2643b741" } } } },
            { "composetime": "2026-11-19T04:48:55Z", "properties": { "activity": { "activityType": "msGraph", "activityContext": { "teamsAppId": "5db56dd0-534d-467b-aeda-d622bee2574a" } } } },
        ]);
        let custom =
            json!([{ "appId": "2a84919f-59d8-4441-a975-2a8c2643b741", "hideAppSettings": true }]);
        let ids = app_ids(&feed, &json!({ CALENDAR_APP: {} }), &custom);
        assert_eq!(
            ids,
            vec![
                "981bbfd0-5eb8-4393-8158-bfff69d2d6b5",
                "5db56dd0-534d-467b-aeda-d622bee2574a"
            ]
        );
    }

    #[test]
    fn aggregated_rows_and_levels() {
        let def = json!({ "id": "981bbfd0-5eb8-4393-8158-bfff69d2d6b5", "activities": { "activityItems": [
            { "type": "recapIsReadyForFollowedMeetings", "description": "When meeting recap is ready for meetings I follow" },
            { "type": "recapIsReady", "description": "When meeting recap is ready for my other meetings" },
            { "type": "systemDefault", "description": "Other activities" } ] } });
        let custom = json!([{ "appId": "981bbfd0-5eb8-4393-8158-bfff69d2d6b5", "defaultAppSettings": "OnlyFeed",
            "settingsAggregation": [{ "key": "recapIsReadyForFollowedMeetings", "subTypes": ["recapIsReadyForFollowedMeetingsV2", "recapIsReadyForFollowedMeetings"] }, { "key": "recapIsReady", "subTypes": ["recapIsReadyV2", "recapIsReady"] }] }]);
        let (rows, toast) = app_rows(&def, &custom);
        assert_eq!(rows.len(), 2);
        assert_eq!(
            rows[0]["label"],
            "When meeting recap is ready for meetings I follow"
        );
        assert!(!toast);
        assert_eq!(
            level(&json!({}), &["recapIsReadyV2", "recapIsReady"], toast),
            1
        );
        let p = level_patch("a", &["x", "y"], 0);
        assert_eq!(p["a"]["toastSettings"]["y"], true);
        assert_eq!(level(&p["a"], &["x"], false), 0);
        assert_eq!(
            switch_patch("a", &[vec!["x"]], false)["a"]["appNotificationEnabled"],
            false
        );
    }
}
