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
//!
//! A personal account (Teams for personal use) asks as Teams desktop does
//! for it (the same app id, captured 2026-11-28): `environment=life`, the
//! personal-account tenant, its own object id, no licence filters and the
//! agents TflNorthstar, TeamsBuilds and Segmentation. Its settings are read
//! from TflNorthstar.

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
/// The agents Teams asks for a personal account (Teams free's
/// `ecsNamespaces`, critical namespace TflNorthstar).
const AGENTS_PERSONAL: &str = "TflNorthstar,TeamsBuilds,Segmentation";
/// The tenant ECS is told for a personal Microsoft account.
const MSA_TENANT: &str = "9188040d-6c67-4c5b-b112-36a304b66dad";
/// Teams desktop 26304's host version (testpc2, as it signs in a personal
/// account next to a work one).
const DESKTOP_VERSION_PERSONAL: &str = "26304.1207.5384.858";

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
        .map(|c| {
            c.iter()
                .filter_map(|x| x.as_str())
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default();
    let room = license
        .and_then(|l| l.get("meetingRoomLicenseCategories"))
        .and_then(|c| c.as_array())
        .map(|c| {
            c.iter()
                .filter_map(|x| x.as_str())
                .collect::<Vec<_>>()
                .join(",")
        })
        .filter(|c| !c.is_empty())
        .unwrap_or_else(|| "None".into());
    // Teams' user-override filters name an SMB licence "TeamsSmb".
    let override_category = if categories == "SmbLicense" {
        "TeamsSmb".to_string()
    } else {
        categories.clone()
    };
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

/// The query Teams desktop sends for a personal account: the life
/// environment, the personal-account tenant and the user's own id, with no
/// licence or region filters (captured 2026-11-28; Teams free's web client
/// sends the same with its web app id).
pub fn query_personal(
    user_id: &str,
    session_id: &str,
    client_id: &str,
    account_count: usize,
) -> Vec<(&'static str, String)> {
    vec![
        ("environment", "life".to_string()),
        ("experience", "react-web-client".to_string()),
        ("buildType", "production".to_string()),
        ("virtualization", String::new()),
        ("browser", "edge".to_string()),
        ("browserVersion", "157.0.4341.42".to_string()),
        ("osPlatform", "windows".to_string()),
        ("isOcdi", "false".to_string()),
        ("isPwa", "false".to_string()),
        ("id", user_id.to_string()),
        ("aaduserid", user_id.to_string()),
        ("tenantId", MSA_TENANT.to_string()),
        ("experienceBuild", EXPERIENCE_BUILD.to_string()),
        ("desktopVersion", DESKTOP_VERSION_PERSONAL.to_string()),
        ("teamsLocale", "en-us".to_string()),
        ("mtmaCount", account_count.max(1).to_string()),
        ("sessionId", session_id.to_string()),
        ("clientId", client_id.to_string()),
        ("agents", AGENTS_PERSONAL.to_string()),
        ("ECSCanary", "1".to_string()),
    ]
}

/// A setting as Teams reads it: the user overrides first, then
/// TeamsNorthstar; a personal account's reply has TflNorthstar instead.
pub fn setting_in(v: &serde_json::Value, namespace: &str, key: &str) -> Option<serde_json::Value> {
    [
        "TeamsNorthstarUserOverrides",
        "TeamsNorthstar",
        "TflNorthstar",
    ]
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

/// Whether any settings have loaded yet (the cached reply or ECS').
pub fn loaded() -> bool {
    SETTINGS.read().is_ok_and(|s| s.is_some())
}

/// Wait up to `limit` for the settings to load; whether they did.
pub async fn wait_loaded(limit: std::time::Duration) -> bool {
    let start = std::time::Instant::now();
    while !loaded() {
        if start.elapsed() >= limit {
            return false;
        }
        tokio::time::sleep(std::time::Duration::from_millis(250)).await;
    }
    true
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
    if client.is_personal() {
        // (A personal account's come with each Skype token, kept in the
        // config; none means none yet.)
        return None;
    }
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default")
        .await
        .ok()?;
    let x = crate::auth::skype::exchange_skype_token(&token, false)
        .await
        .ok()?;
    let l = x.license_details?;
    if let Ok(mut c) = crate::config::Config::load() {
        c.set_license_details(l.clone());
        let _ = c.save();
    }
    *FETCHED.lock().ok()? = Some(l.clone());
    Some(l)
}

/// Fetch the licence details again (a fresh authz exchange, kept in the
/// config), as Teams does after a licence changes (Teams Premium's trial).
/// A personal account's (Teams free's `consumerLicenseDetails`, Plans and
/// upgrades' Verify subscription) come with a new Skype token.
pub async fn refresh_license() -> Option<serde_json::Value> {
    if crate::config::Config::load()
        .ok()?
        .identity()
        .is_some_and(|i| i.is_personal())
    {
        crate::auth::oauth::refresh().await.ok()?;
        return crate::config::Config::load().ok()?.get_license_details();
    }
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default")
        .await
        .ok()?;
    let x = crate::auth::skype::exchange_skype_token(&token, false)
        .await
        .ok()?;
    let l = x.license_details?;
    if let Ok(mut c) = crate::config::Config::load() {
        c.set_license_details(l.clone());
        let _ = c.save();
    }
    Some(l)
}

/// Load the settings: the cached reply at once, then ECS (If-None-Match).
/// `cache_dir` keeps the reply between runs ([`cache_name`]).
pub async fn load(client: &TeamsClient, cache_dir: &Path) -> Result<()> {
    let file = cache_dir.join(cache_name(
        crate::config::profile().as_deref(),
        client.is_personal(),
    ));
    let cached: Option<serde_json::Value> = std::fs::read(&file)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok());
    if let Some(c) = &cached {
        install(c.clone());
    }
    let user = client.object_id().context("not signed in")?;
    let session = uuid::Uuid::new_v4().to_string();
    let device = uuid::Uuid::new_v4().to_string();
    let q = if client.is_personal() {
        let accounts = teams_cli_accounts();
        query_personal(&user, &session, &device, accounts)
    } else {
        work_query(client, &user, &session, &device).await
    };
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

/// The cached reply's file: each profile keeps its own, and a personal
/// account's (TflNorthstar) is kept apart from a work account's.
pub fn cache_name(profile: Option<&str>, personal: bool) -> String {
    let kind = if personal { "-life" } else { "" };
    match profile {
        Some(p) => format!("ecs-{p}{kind}.json"),
        None => format!("ecs{kind}.json"),
    }
}

/// How many accounts are signed in on this device (Teams' mtmaCount).
fn teams_cli_accounts() -> usize {
    crate::config::accounts().len()
}

async fn work_query(
    client: &TeamsClient,
    user: &str,
    session: &str,
    device: &str,
) -> Vec<(&'static str, String)> {
    let tenant = client.tenant_id().unwrap_or_default();
    let region = client
        .chat_service_url()
        .split("//")
        .nth(1)
        .and_then(|h| h.split('.').next())
        .unwrap_or_default()
        .to_string();
    let license = license(client).await;
    query(user, &tenant, &region, license.as_ref(), session, device)
}

/// About's ring line (settings-app `by` / `wy` / `Ty`): shown when the
/// user's ring is Early Access (Teams' host takes the ring from ECS
/// Segmentation.TeamsRing, "ring3_6" for Targeted release users), with
/// the link Teams' core.aboutRingInfoLinks gives (its defaults below).
/// Returns (link text, url) or None.
pub fn about_ring_in(v: &serde_json::Value) -> Option<(String, String)> {
    let ring = v.get("Segmentation")?.get("TeamsRing")?.as_str()?;
    let off = setting_in(v, "core", "disableAboutRingInfo")
        .and_then(|x| x.as_bool())
        .unwrap_or(false);
    if off || ring != "ring3_6" {
        return None;
    }
    let links = setting_in(v, "core", "aboutRingInfoLinks").unwrap_or_default();
    let link = |k: &str, d: &str| {
        links
            .get(k)
            .and_then(|x| x.as_str())
            .unwrap_or(d)
            .to_string()
    };
    if setting_in(v, "core", "enableReleaseDashboardButton")
        .and_then(|x| x.as_bool())
        .unwrap_or(false)
    {
        return Some((
            "Ring 3.6".into(),
            link("internalPreviewLink", "https://aka.ms/Ring3.6"),
        ));
    }
    // The ring the host was given is the user's own (isAssignedRing), so
    // an Early Access user is in Targeted release.
    Some((
        "Targeted release".into(),
        link(
            "targetedReleaseLink",
            "https://go.microsoft.com/fwlink/?linkid=2254754",
        ),
    ))
}

pub fn about_ring() -> Option<(String, String)> {
    SETTINGS.read().ok()?.as_ref().and_then(about_ring_in)
}

/// Teams' client ring (its settings' Metadata.ring.id), in `v` (the ECS
/// reply): the host takes it from Segmentation.TeamsRing ("ring3_6" for a
/// Targeted release user; measured on winpc 2026-11-23, TASK-0263: the
/// Copilot frame's hostRing and TeamsJS ringId), else a metadata.ring
/// setting, else "general".
pub fn ring_in(v: &serde_json::Value) -> String {
    v.get("Segmentation")
        .and_then(|s| s.get("TeamsRing"))
        .and_then(|r| r.as_str())
        .filter(|r| !r.is_empty())
        .map(str::to_string)
        .or_else(|| {
            setting_in(v, "metadata", "ring")
                .and_then(|r| r.get("id")?.as_str().map(str::to_string))
        })
        .unwrap_or_else(|| "general".into())
}

/// The user's ring from the settings loaded so far ("general" before they
/// load): what Teams names as hostRing, ringId, uihRing and
/// x-ringoverride.
pub fn ring() -> String {
    SETTINGS
        .read()
        .ok()
        .and_then(|s| s.as_ref().map(ring_in))
        .unwrap_or_else(|| "general".into())
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
            Some(serde_json::json!(
                "Enterprise/NewStoreCustomization/storev3"
            ))
        );
        assert_eq!(
            setting_in(&v, "extensibility", "enableChannelApps"),
            Some(serde_json::json!(true))
        );
        assert_eq!(setting_in(&v, "extensibility", "b"), None);
    }

    #[test]
    fn personal_accounts_ask_for_tfl_northstar() {
        let q = query_personal("00000000-0000-0000-0ca2-738c364862c6", "s", "c", 2);
        let get = |k: &str| q.iter().find(|(a, _)| *a == k).map(|(_, v)| v.as_str());
        assert_eq!(get("environment"), Some("life"));
        assert_eq!(get("agents"), Some("TflNorthstar,TeamsBuilds,Segmentation"));
        assert_eq!(get("tenantId"), Some(MSA_TENANT));
        assert_eq!(get("id"), get("aaduserid"));
        assert_eq!(get("mtmaCount"), Some("2"));
        // No licence or region filters, as Teams sends for Teams free.
        assert_eq!(get("teamsLicenseCategory"), None);
        assert_eq!(get("Region"), None);
        assert_eq!(q.last().unwrap(), &("ECSCanary", "1".to_string()));
        // Shaped as the reply for OST Personal 2 on 2026-11-28.
        let v = serde_json::json!({ "TflNorthstar": { "core": { "isPremiumButtonInAppBarEnabled": true },
            "monetization": { "enableRefreshPlansAndUpgrades": true } } });
        assert_eq!(
            setting_in(&v, "core", "isPremiumButtonInAppBarEnabled"),
            Some(serde_json::json!(true))
        );
        assert_eq!(setting_in(&v, "core", "missing"), None);
        assert_eq!(cache_name(None, false), "ecs.json");
        assert_eq!(cache_name(Some("p2"), true), "ecs-p2-life.json");
    }

    #[test]
    fn ring_line_for_targeted_release_only() {
        let v = serde_json::json!({ "Segmentation": { "TeamsRing": "ring3_6" } });
        assert_eq!(about_ring_in(&v).unwrap().0, "Targeted release");
        assert!(
            about_ring_in(&serde_json::json!({ "Segmentation": { "TeamsRing": "general" } }))
                .is_none()
        );
    }

    #[test]
    fn ring_from_segmentation_as_teams_host() {
        assert_eq!(
            ring_in(&serde_json::json!({ "Segmentation": { "TeamsRing": "ring3_6" } })),
            "ring3_6"
        );
        let meta =
            serde_json::json!({ "TeamsNorthstar": { "metadata": { "ring": { "id": "ring1" } } } });
        assert_eq!(ring_in(&meta), "ring1");
        assert_eq!(ring_in(&serde_json::json!({})), "general");
    }
}
