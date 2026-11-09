//! Teams' live settings (ECS, config.teams.microsoft.com): the flags and
//! values Teams desktop reads for each feature, for this user and tenant.
//!
//! OST asks exactly as Teams desktop's main settings provider does (its
//! request on winpc, 2026-11-09): `GET /config/v1/MicrosoftTeams/49_1.0.0.0`
//! with the client, user and licence filters and the agents TeamsNorthstar,
//! TeamsBuilds, Segmentation and TeamsNorthstarUserOverrides. Teams reads a
//! setting from TeamsNorthstarUserOverrides first, then TeamsNorthstar
//! (namespace, then key). The reply is kept with its ETag and asked again
//! with If-None-Match.

use std::path::Path;
use std::sync::RwLock;

use anyhow::{Context, Result};

use super::client::TeamsClient;

const ENDPOINT: &str = "https://config.teams.microsoft.com/config/v1/MicrosoftTeams/49_1.0.0.0";
/// The Teams desktop build OST follows (winpc, MSTeams 26276.513), as Teams
/// sends it: its web build and the desktop host version.
const EXPERIENCE_BUILD: &str = "26101515220";
const DESKTOP_VERSION: &str = "26276.513.5241.9675";
const AGENTS: &str = "TeamsNorthstar,TeamsBuilds,Segmentation,TeamsNorthstarUserOverrides";

static SETTINGS: RwLock<Option<serde_json::Value>> = RwLock::new(None);

/// The query Teams desktop sends, for this user.
pub fn query(
    user_id: &str,
    tenant_id: &str,
    region: &str,
    license: Option<&serde_json::Value>,
    session_id: &str,
    client_id: &str,
) -> Vec<(&'static str, String)> {
    let categories = license
        .and_then(|l| l.get("experimentationTeamsLicenseCategories"))
        .and_then(|c| c.as_array())
        .map(|c| c.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(","))
        .unwrap_or_default();
    let room = license
        .and_then(|l| l.get("meetingRoomLicenseCategories"))
        .and_then(|c| c.as_array())
        .map(|c| c.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(","))
        .filter(|c| !c.is_empty())
        .unwrap_or_else(|| "None".into());
    // Teams' user-override filters name an SMB licence "TeamsSmb".
    let override_category = if categories == "SmbLicense" { "TeamsSmb".to_string() } else { categories.clone() };
    let mut q = vec![
        ("environment", "prod".to_string()),
        ("experience", "react-web-client".to_string()),
        ("buildType", "production".to_string()),
        ("virtualization", String::new()),
        ("browser", "edge".to_string()),
        ("browserVersion", "157.0.4341.42".to_string()),
        ("osPlatform", "windows".to_string()),
        ("wipChannel", String::new()),
        ("wipRing", String::new()),
        ("osVersion", "10.0.19045.6456".to_string()),
        ("isOcdi", "false".to_string()),
        ("isPwa", "false".to_string()),
        ("id", user_id.to_string()),
        ("aaduserid", user_id.to_string()),
        ("tenantId", tenant_id.to_string()),
        ("experienceBuild", EXPERIENCE_BUILD.to_string()),
        ("desktopVersion", DESKTOP_VERSION.to_string()),
        ("teamsLocale", "en-us".to_string()),
    ];
    if !categories.is_empty() {
        q.push(("teamsLicenseCategory", categories));
    }
    q.push(("mtmaCount", "1".to_string()));
    q.push(("TeamsMeetingRoomLicenseCategory", room));
    if !region.is_empty() {
        q.push(("Region", region.to_string()));
    }
    if !override_category.is_empty() {
        q.push(("TeamsLicenseCategory", override_category));
    }
    q.push(("sessionId", session_id.to_string()));
    q.push(("clientId", client_id.to_string()));
    q.push(("agents", AGENTS.to_string()));
    q.push(("ECSCanary", "1".to_string()));
    q
}

/// A setting as Teams reads it: the user overrides first, then
/// TeamsNorthstar.
pub fn setting_in(v: &serde_json::Value, namespace: &str, key: &str) -> Option<serde_json::Value> {
    ["TeamsNorthstarUserOverrides", "TeamsNorthstar"]
        .iter()
        .find_map(|agent| v.get(agent)?.get(namespace)?.get(key).cloned())
}

/// A setting from the settings loaded so far (None before they load, or
/// when ECS doesn't set it: the feature's default applies).
pub fn setting(namespace: &str, key: &str) -> Option<serde_json::Value> {
    SETTINGS
        .read()
        .ok()?
        .as_ref()
        .and_then(|v| setting_in(v, namespace, key))
}

/// A Segmentation value (TeamsRing, AudienceGroup, …).
pub fn segment(key: &str) -> Option<String> {
    SETTINGS
        .read()
        .ok()?
        .as_ref()?
        .get("Segmentation")?
        .get(key)?
        .as_str()
        .map(str::to_string)
}

fn install(v: serde_json::Value) {
    if let Ok(mut s) = SETTINGS.write() {
        *s = Some(v);
    }
}

/// The user's licence details (Teams' authz `licenseDetails`): from the
/// config, else from a fresh authz exchange (kept in the config). Teams
/// has them from its start; ECS filters and the Store's doc depend on them.
pub async fn license(client: &TeamsClient) -> Option<serde_json::Value> {
    if let Some(l) = client.license_details() {
        return Some(l);
    }
    static FETCHED: std::sync::Mutex<Option<serde_json::Value>> = std::sync::Mutex::new(None);
    if let Some(l) = FETCHED.lock().ok()?.clone() {
        return Some(l);
    }
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await.ok()?;
    let x = crate::auth::skype::exchange_skype_token(&token, false).await.ok()?;
    let l = x.license_details?;
    if let Ok(mut c) = crate::config::Config::load() {
        c.set_license_details(l.clone());
        let _ = c.save();
    }
    *FETCHED.lock().ok()? = Some(l.clone());
    Some(l)
}

/// Load the settings: the cached reply at once, then ECS (If-None-Match).
/// `cache_dir` keeps `ecs.json` (the reply) between runs.
pub async fn load(client: &TeamsClient, cache_dir: &Path) -> Result<()> {
    let file = cache_dir.join("ecs.json");
    let cached: Option<serde_json::Value> = std::fs::read(&file)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok());
    if let Some(c) = &cached {
        install(c.clone());
    }
    let user = client.object_id().context("not signed in")?;
    let tenant = client.tenant_id().unwrap_or_default();
    let region = client
        .chat_service_url()
        .split("//")
        .nth(1)
        .and_then(|h| h.split('.').next())
        .unwrap_or_default()
        .to_string();
    let license = license(client).await;
    let session = uuid::Uuid::new_v4().to_string();
    let device = uuid::Uuid::new_v4().to_string();
    let q = query(&user, &tenant, &region, license.as_ref(), &session, &device);
    let mut req = client.http().get(ENDPOINT).query(&q);
    if let Some(tag) = cached
        .as_ref()
        .and_then(|c| c.pointer("/Headers/ETag"))
        .and_then(|t| t.as_str())
    {
        req = req.header("If-None-Match", tag);
    }
    let resp = req.send().await.context("ECS")?;
    if resp.status() == reqwest::StatusCode::NOT_MODIFIED {
        return Ok(());
    }
    let v: serde_json::Value = resp.error_for_status().context("ECS")?.json().await?;
    std::fs::create_dir_all(cache_dir)?;
    std::fs::write(&file, serde_json::to_vec(&v)?)?;
    install(v);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asks_as_teams_desktop_and_reads_overrides_first() {
        let license = serde_json::json!({"experimentationTeamsLicenseCategories": ["TeamsSmb"], "meetingRoomLicenseCategories": []});
        let q = query("u", "t", "amer", Some(&license), "s", "c");
        let get = |k: &str| q.iter().find(|(a, _)| *a == k).map(|(_, v)| v.as_str());
        assert_eq!(get("teamsLicenseCategory"), Some("TeamsSmb"));
        assert_eq!(get("TeamsLicenseCategory"), Some("TeamsSmb"));
        assert_eq!(get("TeamsMeetingRoomLicenseCategory"), Some("None"));
        assert_eq!(get("Region"), Some("amer"));
        assert_eq!(get("agents"), Some(AGENTS));
        assert_eq!(q.last().unwrap(), &("ECSCanary", "1".to_string()));
        // Shaped as Teams' reply for ost-test1 on 2026-11-09 (the store doc
        // from TeamsNorthstar, enableChannelApps from the user overrides);
        // an override wins over the same key in TeamsNorthstar.
        let v = serde_json::json!({
            "TeamsNorthstar": {"extensibility": {"storeAppsCollectionsDoc": "Enterprise/NewStoreCustomization/storev3", "enableChannelApps": false}},
            "TeamsNorthstarUserOverrides": {"extensibility": {"enableChannelApps": true}}
        });
        assert_eq!(
            setting_in(&v, "extensibility", "storeAppsCollectionsDoc"),
            Some(serde_json::json!("Enterprise/NewStoreCustomization/storev3"))
        );
        assert_eq!(setting_in(&v, "extensibility", "enableChannelApps"), Some(serde_json::json!(true)));
        assert_eq!(setting_in(&v, "extensibility", "b"), None);
    }
}
