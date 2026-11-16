//! What OST's TeamsJS host needs to know about an embedded app (its Teams
//! app definition), and Teams' rules for which frame origins belong to it
//! (docs/spec/app-host.md).
//!
//! Teams trusts a frame's origin for an app when it matches the app's
//! valid domains: the definition's `validDomains` plus the hosts of its
//! tabs' configuration and content addresses (Teams' module 9883 `C`).
//! A valid domain matches `^https://<domain>((/|\?).*)?$` against the
//! origin's address, case-insensitive, each `*` standing for one label
//! (`[^/^.]+`).

use std::collections::HashMap;
use std::sync::Mutex;

use anyhow::Result;
use serde::Serialize;

use super::client::TeamsClient;

/// The parts of an app's definition the host uses.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct AppFacts {
    /// Valid domains (with the tabs' hosts), as Teams collects them.
    pub valid_domains: Vec<String>,
    /// `webApplicationInfo`: the app's Azure AD app and resource (for
    /// authentication.getAuthToken).
    pub web_app_id: String,
    pub web_app_resource: String,
    /// Microsoft's own app (Teams lets only those add trusted origins and
    /// ask for any resource).
    pub microsoft_owned: bool,
    pub full_trust: bool,
    /// The manifest's version (getContext's manifestVersion).
    pub manifest_version: String,
}

/// The app's facts from its middle-tier definition (cached per app).
pub async fn facts(client: &TeamsClient, app_id: &str) -> Result<AppFacts> {
    static CACHE: Mutex<Option<HashMap<String, AppFacts>>> = Mutex::new(None);
    if let Some(f) = CACHE.lock().ok().and_then(|c| c.as_ref()?.get(app_id).cloned()) {
        return Ok(f);
    }
    let (base, token) = super::tabs::middle_tier(client).await?;
    let enc: String = url::form_urlencoded::byte_serialize(app_id.as_bytes()).collect();
    let d: serde_json::Value = client
        .http()
        .get(format!("{base}/beta/users/apps/definitions/{enc}"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let f = facts_from(&d);
    if let Ok(mut c) = CACHE.lock() {
        c.get_or_insert_with(HashMap::new).insert(app_id.to_string(), f.clone());
    }
    Ok(f)
}

/// [`facts`] from a definition.
pub fn facts_from(d: &serde_json::Value) -> AppFacts {
    let mut domains: Vec<String> = Vec::new();
    let mut add = |s: &str| {
        if !s.is_empty() && !domains.iter().any(|d| d.eq_ignore_ascii_case(s)) {
            domains.push(s.to_string());
        }
    };
    for v in d.get("validDomains").and_then(|v| v.as_array()).into_iter().flatten() {
        add(v.as_str().unwrap_or_default());
    }
    let host = |u: &str| url::Url::parse(&u.replace(['{', '}'], "")).ok().and_then(|u| u.host_str().map(str::to_string));
    for (list, key) in [("galleryTabs", "configurationUrl"), ("configurableTabs", "configurationUrl"), ("staticTabs", "contentUrl")] {
        for t in d.get(list).and_then(|v| v.as_array()).into_iter().flatten() {
            if let Some(h) = t.get(key).and_then(|v| v.as_str()).and_then(host) {
                add(&h);
            }
        }
    }
    let s = |p: &str| d.pointer(p).and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let b = |k: &str| d.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
    AppFacts {
        valid_domains: domains,
        web_app_id: s("/webApplicationInfo/id"),
        web_app_resource: s("/webApplicationInfo/resource"),
        microsoft_owned: b("isMicrosoftOwned"),
        full_trust: b("isFullTrust"),
        manifest_version: s("/manifestVersion"),
    }
}

/// Whether a frame served from `origin` belongs to the app (Teams'
/// isValidOriginForApp).
pub fn origin_valid_for_app(origin: &str, valid_domains: &[String]) -> bool {
    let Ok(u) = url::Url::parse(origin) else { return false };
    if u.scheme() != "https" {
        return false;
    }
    let href = u.as_str().to_ascii_lowercase();
    valid_domains.iter().any(|d| {
        let d = d.to_ascii_lowercase();
        // The same shape Teams accepts: hostname labels, `*` labels, a port.
        if d.is_empty() || d.contains('/') || d.ends_with('*') {
            return false;
        }
        let pattern = format!(
            "^https://{}((/|\\?).*)?$",
            regex::escape(&d).replace("\\.", "[.]").replace("\\*", "[^/^.]+")
        );
        regex::Regex::new(&pattern).is_ok_and(|r| r.is_match(&href))
    })
}

/// The resource authentication.getAuthToken asks a token for, as Teams
/// picks it (module 9883 `w`): a full-trust Microsoft app's first asked
/// resource, else the app's webApplicationInfo resource (its
/// `{teamSiteDomain}` filled), which an asked resource must match.
pub fn sso_resource(f: &AppFacts, team_site_domain: &str, asked: Option<&serde_json::Value>) -> Result<String> {
    let asked: Vec<String> = asked
        .and_then(|a| a.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect())
        .unwrap_or_default();
    if f.full_trust && f.microsoft_owned && let Some(r) = asked.first() {
        anyhow::ensure!(r.starts_with("https://") || r.starts_with("api://"), "Invalid resource");
        return Ok(r.clone());
    }
    anyhow::ensure!(!f.web_app_resource.is_empty(), "App webApplicationInfo or resource not defined in manifest");
    let mine = f.web_app_resource.replace("{teamSiteDomain}", team_site_domain);
    if let Some(r) = asked.first() {
        anyhow::ensure!(r.eq_ignore_ascii_case(&mine), "App resource defined in manifest and iframe origin do not match");
    }
    Ok(mine)
}

/// One id for this run of OST: Teams' `sessionId` in app contexts.
pub fn session_id() -> String {
    static ID: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    ID.get_or_init(|| uuid::Uuid::new_v4().to_string()).clone()
}

/// The signed-in user, as the context names them.
#[derive(Debug, Clone, Default)]
pub struct HostUser {
    pub tid: String,
    pub oid: String,
    pub upn: String,
    pub mri: String,
}

/// An app's context as Teams answers `getContext` (measured for the
/// channel Notes tab, docs/spec/app-host.md): the user, the host and, for
/// a channel tab, its channel and team from their thread properties
/// (`channel_props`, `team_props`; empty outside channels). The caller
/// adds appSessionId, appLaunchId, theme, frameContext and the tab's
/// entityId.
#[allow(clippy::too_many_arguments)]
pub fn context_from(
    app_id: &str,
    manifest_version: &str,
    user: &HostUser,
    chat_id: &str,
    tenant_site_domain: &str,
    channel_id: &str,
    channel_props: &serde_json::Value,
    team_id: &str,
    team_props: &serde_json::Value,
    team_members: &[serde_json::Value],
) -> serde_json::Value {
    let p = |v: &serde_json::Value, k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    let site = p(team_props, "sharepointSiteUrl");
    let (site_domain, site_path) = url::Url::parse(&site)
        .ok()
        .map(|u| (u.host_str().unwrap_or_default().to_string(), u.path().trim_end_matches('/').to_string()))
        .unwrap_or_default();
    // Teams' userTeamRole: 0 owner (Admin), 1 member, 2 guest.
    let role = team_members
        .iter()
        .find(|m| m.get("id").and_then(|i| i.as_str()) == Some(user.mri.as_str()))
        .and_then(|m| m.get("role").and_then(|r| r.as_str()))
        .map(|r| match r { "Admin" => 0, "Guest" => 2, _ => 1 })
        .unwrap_or(1);
    let mut c = serde_json::json!({
        "locale": "en-us",
        "appId": app_id,
        "osLocaleInfo": { "platform": "windows", "regionalFormat": "en-us", "shortDate": "M/d/yyyy", "longDate": "dddd, MMMM d, yyyy",
                          "shortTime": "h:mm tt", "longTime": "h:mm:ss tt", "timezone": iana_zone() },
        "parentMessageId": "",
        "userClickTime": chrono::Utc::now().timestamp_millis(),
        "userClickTimeV2": 0,
        "userFileOpenPreference": "inline",
        "manifestVersion": if manifest_version.is_empty() { "devPreview" } else { manifest_version },
        "hostName": "TeamsModern",
        "hostFeatures": { "nestedWildcardsInValidDomains": false, "serverSideRendering": false },
        "hostClientType": "desktop",
        "sessionId": session_id(),
        "ringId": "general",
        "hostAncestors": ["TeamsModern"],
        "subEntityId": "",
        "isFullScreen": false,
        "isMultiWindow": false,
        "isBackgroundLoad": false,
        "sourceOrigin": "",
        "userObjectId": user.oid,
        "userLicenseType": "Unknown",
        "loginHint": user.upn,
        "userPrincipalName": user.upn,
        "upn": user.upn,
        "userDisplayName": "",
        "tid": user.tid,
        "tenantSKU": "enterprise",
        "defaultOneNoteSectionId": "",
        "chatId": "",
        "meetingId": "",
    });
    if !chat_id.is_empty() {
        // A chat's tab (Storyline): the chat, Teams' meeting id for it
        // (base64 of "0#<chat>#0") and the tenant's SharePoint host.
        use base64::Engine as _;
        let extra = serde_json::json!({
            "channelId": "",
            "chatId": chat_id,
            "meetingId": base64::engine::general_purpose::STANDARD.encode(format!("0#{chat_id}#0")),
            "teamSiteId": "",
            "teamSiteUrl": "",
            "teamSiteDomain": tenant_site_domain,
            "teamSitePath": "",
        });
        if let (Some(o), serde_json::Value::Object(e)) = (c.as_object_mut(), extra) {
            o.extend(e);
        }
    }
    if !channel_id.is_empty() {
        let extra = serde_json::json!({
            "channelId": channel_id,
            "channelName": Some(p(channel_props, "topic")).filter(|t| !t.is_empty()).unwrap_or_else(|| "General".into()),
            "channelRelativeUrl": p(channel_props, "channelDocsFolderRelativeUrl"),
            "channelType": match p(channel_props, "threadType").as_str() { "topic" | "space" | "" => "Regular", _ => "Private" },
            "teamId": team_id,
            "teamName": p(team_props, "spaceThreadTopic"),
            "teamType": 0,
            "groupId": p(team_props, "groupId"),
            "isTeamArchived": false,
            "userTeamRole": role,
            "teamSiteId": "",
            "teamSiteUrl": site,
            "teamSiteDomain": site_domain,
            "teamSitePath": site_path,
        });
        if let (Some(o), serde_json::Value::Object(e)) = (c.as_object_mut(), extra) {
            o.extend(e);
        }
    }
    c
}

/// The local time zone's IANA name (Teams sends it in osLocaleInfo).
fn iana_zone() -> String {
    std::env::var("TZ")
        .ok()
        .filter(|z| z.contains('/'))
        .or_else(|| std::fs::read_link("/etc/localtime").ok().and_then(|p| {
            let s = p.to_string_lossy().to_string();
            s.split("zoneinfo/").nth(1).map(str::to_string)
        }))
        .unwrap_or_else(|| "UTC".into())
}

/// The tenant's SharePoint host (`<tenant>.sharepoint.com`), from Graph's
/// root site (cached).
async fn tenant_site_domain(client: &TeamsClient) -> String {
    static HOST: Mutex<Option<String>> = Mutex::new(None);
    if let Some(h) = HOST.lock().ok().and_then(|h| h.clone()) {
        return h;
    }
    let h = async {
        let v: serde_json::Value = client.graph_get("/sites/root?$select=siteCollection").await.ok()?.json().await.ok()?;
        v.pointer("/siteCollection/hostname").and_then(|h| h.as_str()).map(str::to_string)
    }
    .await
    .unwrap_or_default();
    if !h.is_empty()
        && let Ok(mut c) = HOST.lock()
    {
        *c = Some(h.clone());
    }
    h
}

/// [`context_from`] with the user from OST's sign-in and, for a channel,
/// the channel's and team's thread properties read from the chat service
/// (`thread` a channel or a chat; `team_thread` the channel's team).
pub async fn context(client: &TeamsClient, app_id: &str, thread: &str, team_thread: &str) -> Result<serde_json::Value> {
    let user = HostUser {
        tid: client.tenant_id().unwrap_or_default(),
        oid: client.object_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
        mri: format!("8:orgid:{}", client.object_id().unwrap_or_default()),
    };
    let manifest = facts(client, app_id).await.map(|f| f.manifest_version).unwrap_or_default();
    let is_channel = thread.ends_with("@thread.tacv2") || thread.ends_with("@thread.skype");
    let (mut channel, mut team, mut members) = (serde_json::Value::Null, serde_json::Value::Null, Vec::new());
    let team_id = if team_thread.is_empty() { thread } else { team_thread };
    if is_channel {
        channel = super::tab_add::thread_properties(client, thread).await.unwrap_or_default();
        let url = format!("{}/v1/threads/{}?view=msnp24Equivalent", client.chat_service_url(), super::tabs::encode_uri_component(team_id));
        if let Ok(r) = client.chat_get(&url).await
            && let Ok(v) = r.json::<serde_json::Value>().await
        {
            team = v.get("properties").cloned().unwrap_or_default();
            members = v.get("members").and_then(|m| m.as_array()).cloned().unwrap_or_default();
        }
    }
    let chat = if !is_channel && !thread.is_empty() { thread } else { "" };
    let site = if chat.is_empty() { String::new() } else { tenant_site_domain(client).await };
    Ok(context_from(
        app_id,
        &manifest,
        &user,
        chat,
        &site,
        if is_channel { thread } else { "" },
        &channel,
        if is_channel { team_id } else { "" },
        &team,
        &members,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_context_is_teams() {
        let user = HostUser { tid: "t".into(), oid: "o".into(), upn: "u@x".into(), mri: "8:orgid:o".into() };
        let channel = serde_json::json!({"topic": "OST test channel 2", "channelDocsFolderRelativeUrl": "/sites/OSTTestTeam/Shared Documents/OST test channel 2", "threadType": "topic"});
        let team = serde_json::json!({"spaceThreadTopic": "OST Test Team", "groupId": "g", "sharepointSiteUrl": "https://scnetsolutions.sharepoint.com/sites/OSTTestTeam"});
        let members = vec![serde_json::json!({"id": "8:orgid:o", "role": "Admin"})];
        let c = context_from("0d820ecd-def2-4297-adad-78056cde7c78", "devPreview", &user, "", "", "19:c@thread.tacv2", &channel, "19:t@thread.tacv2", &team, &members);
        assert_eq!(c["channelName"], "OST test channel 2");
        assert_eq!(c["channelRelativeUrl"], "/sites/OSTTestTeam/Shared Documents/OST test channel 2");
        assert_eq!(c["channelType"], "Regular");
        assert_eq!(c["teamId"], "19:t@thread.tacv2");
        assert_eq!(c["teamSiteDomain"], "scnetsolutions.sharepoint.com");
        assert_eq!(c["teamSitePath"], "/sites/OSTTestTeam");
        assert_eq!(c["userTeamRole"], 0);
        assert_eq!(c["hostName"], "TeamsModern");
        assert_eq!(c["upn"], "u@x");
        let chat = context_from("683f3525-d193-4a67-8d91-22093beab1ca", "1.25", &user, "19:a_b@unq.gbl.spaces", "x.sharepoint.com", "", &serde_json::Value::Null, "", &serde_json::Value::Null, &[]);
        assert_eq!(chat["channelId"], "");
        assert_eq!(chat["chatId"], "19:a_b@unq.gbl.spaces");
        // Teams' meetingId for a chat: base64 of "0#<chat>#0".
        assert_eq!(chat["meetingId"], "MCMxOTphX2JAdW5xLmdibC5zcGFjZXMjMA==");
        assert_eq!(chat["teamSiteDomain"], "x.sharepoint.com");
        assert_eq!(chat["manifestVersion"], "1.25");
        assert_eq!(chat["tid"], "t");
    }

    #[test]
    fn valid_domains_match_as_teams() {
        let d = vec!["*.officeapps.live.com".to_string(), "www.microsoft365.com".to_string(), "*.resources.office.net".to_string()];
        assert!(origin_valid_for_app("https://www.microsoft365.com", &d));
        assert!(origin_valid_for_app("https://oauth.officeapps.live.com", &d));
        assert!(origin_valid_for_app("https://fa000000128.resources.office.net", &d));
        // One label per `*`, https only, no look-alikes.
        assert!(!origin_valid_for_app("https://a.b.officeapps.live.com", &d));
        assert!(!origin_valid_for_app("http://www.microsoft365.com", &d));
        assert!(!origin_valid_for_app("https://www.microsoft365.com.evil.example", &d));
        assert!(!origin_valid_for_app("https://wwwxmicrosoft365.com", &d));
        assert!(!origin_valid_for_app("not a url", &d));
    }

    #[test]
    fn facts_collect_domains_and_web_app() {
        let d = serde_json::json!({
            "validDomains": ["*.onenote.com", "www.microsoft365.com"],
            "galleryTabs": [{"configurationUrl": "https://www.onenote.com/teams/TabConfigure?x={locale}"}],
            "staticTabs": [{"contentUrl": "https://WWW.MICROSOFT365.COM/launch"}],
            "webApplicationInfo": {"id": "app", "resource": "https://onenote.com"}
        });
        let f = facts_from(&d);
        assert_eq!(f.valid_domains, vec!["*.onenote.com", "www.microsoft365.com", "www.onenote.com"]);
        assert_eq!(f.web_app_id, "app");
        assert_eq!(f.web_app_resource, "https://onenote.com");
        assert!(!f.microsoft_owned);
    }
}
