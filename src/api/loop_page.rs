//! What OST's Loop page host needs from OST (docs/spec/loop-host.md): the
//! host's settings for Loop (Teams' fluid settings from ECS, the user, the
//! audience), the tokens Loop's page container asks the host for, and
//! where a channel's New page is made.
//!
//! Teams hosts a chat's Notes and a channel's Pages the same way: Loop's
//! page container, service-delivered from res.cdn.office.net, in a
//! same-origin frame of Teams' page, loaded with Fluid's container loader
//! and Teams' host services. The tokens are Teams' own web-client tokens
//! (client 5e3ce6c0) for each resource Loop names: the tenant's SharePoint
//! (`https://<tenant>.sharepoint.com/files.readwrite.all`), the push channel
//! (`https://pushchannel.1drv.ms/pushchannel.readwrite.all`), AugLoop
//! (`https://augloop.office.com/v2/.default`), Graph (`user.read`,
//! `Organization.Read.All`) and Substrate (the page's recent-files mark,
//! `Files.ReadWrite.Shared`); Teams asks Azure AD for `<resource>/.default`
//! (measured 2026-11-16). OST mints them from its browser sign-in, keeps
//! them in memory only until five minutes before they expire, and never
//! logs them.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// Teams desktop's host name for Loop (Teams' `hostName`: "Microsoft Teams
/// Maglev" for its desktop clients, "Microsoft Teams Web" on the web).
pub const HOST_NAME: &str = "Microsoft Teams Maglev";

/// Which Loop page: a chat's Notes (Teams' fluid type `fluidThread`) or a
/// channel's Page (`channelPages`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    ChatNotes,
    ChannelPage,
}

impl Kind {
    pub fn parse(s: &str) -> Self {
        if s == "channelPages" { Kind::ChannelPage } else { Kind::ChatNotes }
    }
    fn name(self) -> &'static str {
        match self {
            Kind::ChatNotes => "fluidThread",
            Kind::ChannelPage => "channelPages",
        }
    }
    /// Teams' settings category for the page (its fluid settings).
    fn category(self) -> &'static str {
        match self {
            Kind::ChatNotes => "fluidThread",
            Kind::ChannelPage => "channelPages",
        }
    }
}

/// The resource Teams asks Azure AD for (`<resource>/.default`) when Loop
/// asks the host for `scopes`; `None` for a resource the Loop host has no
/// business with (only SharePoint, the push channel, AugLoop, Graph and
/// Substrate are answered). All scopes must name the same resource.
pub fn token_resource(scopes: &[String]) -> Option<String> {
    let mut found: Option<String> = None;
    for s in scopes.iter().map(|s| s.trim()).filter(|s| !s.is_empty()) {
        let r = if let Some(rest) = s.strip_prefix("https://") {
            let host = rest.split('/').next().unwrap_or_default().to_ascii_lowercase();
            let ok = (host.ends_with(".sharepoint.com") && host.len() > ".sharepoint.com".len())
                || host == "pushchannel.1drv.ms"
                || host == "augloop.office.com"
                || host == "graph.microsoft.com"
                // The page's recent-files mark (WorkingSetFiles), as Teams.
                || host == "substrate.office.com";
            if !ok || host.contains(':') {
                return None;
            }
            // AugLoop's resource keeps its version path, as Teams asks.
            if host == "augloop.office.com" && rest.to_ascii_lowercase().starts_with("augloop.office.com/v2/") {
                "https://augloop.office.com/v2".to_string()
            } else {
                format!("https://{host}")
            }
        } else if s.contains("://") {
            return None;
        } else {
            // A bare permission ("user.read") is Graph's.
            "https://graph.microsoft.com".to_string()
        };
        match &found {
            Some(f) if *f != r => return None,
            _ => found = Some(r),
        }
    }
    found.map(|r| format!("{r}/.default"))
}

struct Cached {
    token: String,
    until: Instant,
}

static TOKENS: Mutex<Option<HashMap<String, Cached>>> = Mutex::new(None);
const RENEW_BEFORE: Duration = Duration::from_secs(300);

/// A token for what Loop asked (`scopes`), Teams' own (the stored sign-in's
/// client); the second value says whether it came from memory.
pub async fn token(scopes: &[String], force_refresh: bool) -> Result<(String, bool)> {
    let scope = token_resource(scopes).context("The Loop host doesn't give tokens for that")?;
    if !force_refresh
        && let Some(t) = TOKENS.lock().ok().and_then(|c| {
            let e = c.as_ref()?.get(&scope)?;
            (e.until.checked_duration_since(Instant::now())? > RENEW_BEFORE).then(|| e.token.clone())
        })
    {
        return Ok((t, true));
    }
    let (t, expires) = crate::auth::oauth::access_token_expiring(&scope).await?;
    if let Ok(mut c) = TOKENS.lock() {
        c.get_or_insert_with(HashMap::new).insert(scope, Cached { token: t.clone(), until: Instant::now() + Duration::from_secs(expires.unwrap_or(3600)) });
    }
    Ok((t, false))
}

/// Forget the Loop host's tokens (sign-out).
pub fn clear() {
    if let Ok(mut c) = TOKENS.lock() {
        *c = None;
    }
}

/// Teams' built-in `fluid` settings for a page's settings category (its
/// config bundle, 2026-11-16), which ECS overlays key by key: the view
/// properties Teams renders the page with, among others.
fn category_defaults(kind: Kind) -> Value {
    let vp = |view_type: &str| json!({ "compactMargins": false, "viewType": view_type, "layoutMode": "fixedByHost", "visualSpacingTop": 12,
                                       "narrowVisualSpacingLeft": 28, "narrowVisualSpacingRight": 28 });
    let mut d = json!({
        "ipEnabled": true, "oneWayRedeemEnabled": true, "sizeLimitEnabled": true, "phasedLoadEnabled": true,
        "paragraphWithoutInsertionMenuExperimentEnabled": true, "enableDiscoveryFooterInAttachedState": true,
        "startInPostCriticalEnabled": true, "useResolvedUrlForLocator": true,
    });
    match kind {
        Kind::ChatNotes => {
            d["sizeLimitValueBytes"] = json!(6291456);
            d["viewProperties"] = vp("Small");
        }
        Kind::ChannelPage => {
            d["sizeLimitValueBytes"] = json!(0xa00000);
            d["viewProperties"] = vp("Large");
        }
    }
    d
}

/// Teams' fluid settings for a page: its category's (`fluidThread` for a
/// chat's Notes, `channelPages` for a channel's Page: Teams' defaults, then
/// ECS) laid over ECS's `messaging.fluid`, key by key, so the category's
/// view properties replace messaging's (measured: a channel's Page renders
/// with `{compactMargins: false, onlyInlineComponents: false,
/// narrowVisualSpacingLeft/Right: 28, visualSpacingTop: 12, layoutMode:
/// fixedByHost}`).
pub fn fluid_settings_from(messaging: Option<&Value>, category: Option<&Value>, kind: Kind) -> Value {
    let mut s = messaging.cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut cat = category_defaults(kind);
    if let (Some(o), Some(Value::Object(c))) = (cat.as_object_mut(), category) {
        for (k, v) in c {
            o.insert(k.clone(), v.clone());
        }
    }
    if let (Some(o), Value::Object(c)) = (s.as_object_mut(), cat) {
        o.extend(c);
    }
    s
}

/// The Loop host's settings for a page (no secrets): who is signed in, the
/// Loop audience (Teams' `messaging.fluidAudience`), Teams' fluid settings
/// and policy switches, the host's names.
pub fn host_config(client: &TeamsClient, kind: Kind) -> Value {
    use super::ecs::setting;
    let audience = setting("messaging", "fluidAudience").and_then(|v| v.as_str().map(str::to_string)).unwrap_or_else(|| "Production".into());
    let fluid = fluid_settings_from(setting("messaging", "fluid").as_ref(), setting(kind.category(), "fluid").as_ref(), kind);
    let flag = |ns: &str, k: &str| setting(ns, k).and_then(|v| v.as_bool()).unwrap_or(false);
    json!({
        "kind": kind.name(),
        "user": { "oid": client.object_id().unwrap_or_default(), "tid": client.tenant_id().unwrap_or_default() },
        "locale": "en-us",
        "audience": audience,
        "hostName": HOST_NAME,
        "hostAppPlatform": "Desktop",
        "hostAppVersion": "49/26101515220",
        "sessionId": super::app_host::session_id(),
        "fluidSettings": fluid,
        "policy": {
            "connectedExperiences": true,
            "enableDefaultPolicyValue": flag("messaging", "enableDefaultPolicyValue"),
            "allowFluidCollaborate": flag("messaging", "allowFluidCollaborate"),
            "enableFluidThread": flag("fluidThread", "enableFluidThread"),
        },
    })
}

/// Where a channel's New page is made: the channel's folder in its team's
/// (or private channel's) document library.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct PageTarget {
    /// The site (`https://<tenant>.sharepoint.com/sites/<team>`).
    pub site_url: String,
    pub drive_id: String,
    /// The channel's folder from the library's root ("OST test channel").
    pub file_path: String,
}

/// The library's site path and the folder within it, from the channel's
/// `channelDocsFolderRelativeUrl` ("/sites/X/Shared Documents/Channel") and
/// the library's own path ("/sites/X/Shared Documents").
pub fn folder_in_library(channel_folder: &str, library_path: &str) -> Option<String> {
    let lib = library_path.trim_end_matches('/');
    let rest = channel_folder.strip_prefix(lib)?;
    let rest = rest.strip_prefix('/').unwrap_or(rest);
    (!rest.is_empty()).then(|| rest.trim_end_matches('/').to_string())
}

/// The site a server-relative library or folder address belongs to:
/// "/sites/X" or "/teams/X".
pub fn site_path_of(relative: &str) -> Option<String> {
    let mut parts = relative.trim_start_matches('/').split('/');
    let (a, b) = (parts.next()?, parts.next()?);
    (matches!(a, "sites" | "teams") && !b.is_empty()).then(|| format!("/{a}/{b}"))
}

/// Find where a channel's New page goes, from the channel's thread
/// (`channelDocsFolderRelativeUrl`) and Graph (the site's library).
pub async fn channel_page_target(client: &TeamsClient, channel_id: &str) -> Result<PageTarget> {
    let props = super::tab_add::thread_properties(client, channel_id).await?;
    let folder = props.get("channelDocsFolderRelativeUrl").and_then(|v| v.as_str()).unwrap_or_default().to_string();
    anyhow::ensure!(folder.starts_with('/'), "The channel has no files folder yet");
    let site_path = site_path_of(&folder).context("The channel's files folder")?;
    let host = super::app_host::sharepoint_host(client).await;
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "The tenant's SharePoint");
    let site_url = format!("https://{host}{site_path}");
    let drive: Value = client
        .graph_get(&format!("/sites/{host}:{site_path}:/drive?$select=id,webUrl"))
        .await?
        .json()
        .await
        .context("The site's library")?;
    let drive_id = drive.get("id").and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let lib_url = url::Url::parse(drive.get("webUrl").and_then(|v| v.as_str()).unwrap_or_default()).context("The site's library")?;
    let lib_path = percent_decode(lib_url.path());
    anyhow::ensure!(!drive_id.is_empty(), "The site's library");
    let file_path = folder_in_library(&folder, &lib_path).context("The channel's folder isn't in its site's library")?;
    Ok(PageTarget { site_url, drive_id, file_path })
}

fn percent_decode(s: &str) -> String {
    url::form_urlencoded::parse(format!("x={}", s.replace('+', "%2B")).as_bytes())
        .next()
        .map(|(_, v)| v.into_owned())
        .unwrap_or_else(|| s.to_string())
}

/// The name Teams' page header shows: the page's file name without
/// `.loop` (Graph's shares lookup of its link).
pub async fn page_name(client: &TeamsClient, component_url: &str) -> Result<String> {
    Ok(super::tab_add::resolve_page_link(client, component_url).await?.name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn tokens_go_to_the_resources_teams_asks_for() {
        // The scopes Loop's page container asked Teams for (2026-11-16).
        assert_eq!(token_resource(&s(&["https://scnetsolutions.sharepoint.com/files.readwrite.all"])).as_deref(), Some("https://scnetsolutions.sharepoint.com/.default"));
        assert_eq!(token_resource(&s(&["https://pushchannel.1drv.ms/pushchannel.readwrite.all"])).as_deref(), Some("https://pushchannel.1drv.ms/.default"));
        assert_eq!(token_resource(&s(&["https://augloop.office.com/v2/.default"])).as_deref(), Some("https://augloop.office.com/v2/.default"));
        assert_eq!(token_resource(&s(&["user.read"])).as_deref(), Some("https://graph.microsoft.com/.default"));
        assert_eq!(token_resource(&s(&["Organization.Read.All"])).as_deref(), Some("https://graph.microsoft.com/.default"));
        assert_eq!(token_resource(&s(&["https://substrate.office.com/Files.ReadWrite.Shared"])).as_deref(), Some("https://substrate.office.com/.default"));
        // Nothing else, and never two resources at once.
        assert_eq!(token_resource(&s(&["https://outlook.office.com/.default"])), None);
        assert_eq!(token_resource(&s(&["https://evil.example/x"])), None);
        assert_eq!(token_resource(&s(&["https://.sharepoint.com/x"])), None);
        assert_eq!(token_resource(&s(&["http://x.sharepoint.com/x"])), None);
        assert_eq!(token_resource(&s(&["user.read", "https://x.sharepoint.com/a"])), None);
        assert_eq!(token_resource(&[]), None);
    }

    #[test]
    fn fluid_settings_are_teams_merge() {
        let messaging = json!({ "audience": "Preview", "ipEnabled": true, "viewProperties": { "layoutMode": "growHeight", "viewType": "Large" } });
        let thread = json!({ "viewProperties": { "layoutMode": "fixedByHost", "viewType": "Small", "visualSpacingTop": 12 }, "oneWayRedeemEnabled": true });
        let notes = fluid_settings_from(Some(&messaging), Some(&thread), Kind::ChatNotes);
        assert_eq!(notes["viewProperties"]["viewType"], "Small");
        assert_eq!(notes["ipEnabled"], true);
        assert_eq!(notes["oneWayRedeemEnabled"], true);
        // A channel's Page: Teams' channelPages defaults over messaging's
        // (ECS gave only sizeLimitEnabled), so its view properties win.
        let page = fluid_settings_from(Some(&messaging), Some(&json!({ "sizeLimitEnabled": true })), Kind::ChannelPage);
        assert_eq!(page["viewProperties"], json!({ "compactMargins": false, "viewType": "Large", "layoutMode": "fixedByHost", "visualSpacingTop": 12,
                                                    "narrowVisualSpacingLeft": 28, "narrowVisualSpacingRight": 28 }));
        assert_eq!(page["sizeLimitEnabled"], true);
        assert_eq!(page["sizeLimitValueBytes"], 10485760);
        assert_eq!(page["ipEnabled"], true);
        assert_eq!(fluid_settings_from(None, None, Kind::ChannelPage)["viewProperties"]["layoutMode"], "fixedByHost");
    }

    #[test]
    fn channel_folders_are_found_in_their_library() {
        // OST test channel (2026-11-16): the page went to
        // items/root:/%2FOST%20test%20channel/Loop%20paragraph.loop.
        assert_eq!(folder_in_library("/sites/OSTTestTeam/Shared Documents/OST test channel", "/sites/OSTTestTeam/Shared Documents").as_deref(), Some("OST test channel"));
        assert_eq!(folder_in_library("/sites/OSTTestTeam/Shared Documents/General/", "/sites/OSTTestTeam/Shared Documents/").as_deref(), Some("General"));
        assert_eq!(folder_in_library("/sites/Other/Shared Documents/X", "/sites/OSTTestTeam/Shared Documents"), None);
        assert_eq!(folder_in_library("/sites/OSTTestTeam/Shared Documents", "/sites/OSTTestTeam/Shared Documents"), None);
        assert_eq!(site_path_of("/sites/OSTTestTeam/Shared Documents/OST test channel").as_deref(), Some("/sites/OSTTestTeam"));
        assert_eq!(site_path_of("/teams/T-Private/Shared Documents/P").as_deref(), Some("/teams/T-Private"));
        assert_eq!(site_path_of("/Shared Documents"), None);
        assert_eq!(percent_decode("/sites/OSTTestTeam/Shared%20Documents"), "/sites/OSTTestTeam/Shared Documents");
    }
}
