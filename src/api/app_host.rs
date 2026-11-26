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

use anyhow::{Context, Result};
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
    /// The app's personal tabs (staticTabs), in the definition's order.
    pub static_tabs: Vec<StaticTab>,
    /// The app hides Teams' app header (manifest `isFullScreen`: Shifts,
    /// Clipchamp, Copilot, the Office apps).
    pub full_screen: bool,
}

/// One of an app's personal tabs (manifest staticTabs), as Teams opens it
/// from the app bar (docs/spec/app-host.md "Personal apps").
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct StaticTab {
    pub entity_id: String,
    pub name: String,
    pub content_url: String,
    pub website_url: String,
    pub scopes: Vec<String>,
}

/// The apps' facts read so far this run, by app id.
static FACTS: Mutex<Option<HashMap<String, AppFacts>>> = Mutex::new(None);

/// An app's facts if they have been read this run (without asking).
pub fn cached_facts(app_id: &str) -> Option<AppFacts> {
    FACTS
        .lock()
        .ok()
        .and_then(|c| c.as_ref()?.get(app_id).cloned())
}

/// The app's facts from its middle-tier definition (cached per app).
pub async fn facts(client: &TeamsClient, app_id: &str) -> Result<AppFacts> {
    if let Some(f) = cached_facts(app_id) {
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
    if let Ok(mut c) = FACTS.lock() {
        c.get_or_insert_with(HashMap::new)
            .insert(app_id.to_string(), f.clone());
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
    for v in d
        .get("validDomains")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
    {
        add(v.as_str().unwrap_or_default());
    }
    let host = |u: &str| {
        url::Url::parse(&u.replace(['{', '}'], ""))
            .ok()
            .and_then(|u| u.host_str().map(str::to_string))
    };
    for (list, key) in [
        ("galleryTabs", "configurationUrl"),
        ("configurableTabs", "configurationUrl"),
        ("staticTabs", "contentUrl"),
    ] {
        for t in d.get(list).and_then(|v| v.as_array()).into_iter().flatten() {
            if let Some(h) = t.get(key).and_then(|v| v.as_str()).and_then(host) {
                add(&h);
            }
        }
    }
    let s = |p: &str| {
        d.pointer(p)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let b = |k: &str| d.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
    let str_of = |t: &serde_json::Value, k: &str| {
        t.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let static_tabs = d
        .get("staticTabs")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .map(|t| StaticTab {
            entity_id: str_of(t, "entityId"),
            name: str_of(t, "name"),
            content_url: str_of(t, "contentUrl"),
            website_url: str_of(t, "websiteUrl"),
            scopes: t
                .get("scopes")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect(),
        })
        .collect();
    AppFacts {
        static_tabs,
        full_screen: b("isFullScreen"),
        valid_domains: domains,
        web_app_id: s("/webApplicationInfo/id"),
        web_app_resource: s("/webApplicationInfo/resource"),
        microsoft_owned: b("isMicrosoftOwned"),
        full_trust: b("isFullTrust"),
        manifest_version: s("/manifestVersion"),
    }
}

/// The personal tab Teams opens for an app from the app bar: the asked
/// entity, else the first personal-scope tab with a page (conversation
/// and about tabs have no content address).
pub fn personal_tab<'a>(f: &'a AppFacts, entity: &str) -> Option<&'a StaticTab> {
    let usable = |t: &&StaticTab| {
        t.content_url.starts_with("https://")
            && (t.scopes.is_empty() || t.scopes.iter().any(|s| s.eq_ignore_ascii_case("personal")))
    };
    f.static_tabs
        .iter()
        .filter(usable)
        .find(|t| !entity.is_empty() && t.entity_id == entity)
        .or_else(|| f.static_tabs.iter().find(usable))
}

/// Teams' answer to `getUserJoinedTeams` (teams.fullTrust.joinedTeams,
/// measured for Shifts): `{userJoinedTeams: [{teamId, teamName, groupId,
/// isTeamLocked, isTeamArchived, teamDescription, thumbnailUri,
/// userTeamRole, teamType}]}`, userTeamRole 0 owner, 1 member, 2 guest.
pub fn joined_teams_from(teams: &[super::teams::ListTeam]) -> serde_json::Value {
    let list: Vec<serde_json::Value> = teams
        .iter()
        .map(|t| {
            serde_json::json!({
                "teamId": t.thread_id,
                "teamName": t.name,
                "groupId": t.id,
                "isTeamLocked": false,
                "isTeamArchived": t.archived,
                "teamDescription": t.description,
                "thumbnailUri": "",
                "userTeamRole": match t.role.as_str() { "admin" => 0, "guest" => 2, _ => 1 },
                "teamType": t.team_type,
            })
        })
        .collect();
    serde_json::json!({ "userJoinedTeams": list })
}

/// Share to Outlook (measured 2026-11-16, Teams on the web): Teams asks the
/// middle tier to make a draft of the conversation in your mailbox, `GET
/// {mt}/beta/shareToOutlook/GetEmailIdForConversation?threadId=…
/// &messageId=…&locale=en-us[&bodyType=…]`, and frames Outlook's compose
/// for that draft.
pub async fn share_to_outlook_email(
    client: &TeamsClient,
    thread: &str,
    message_id: &str,
    body_type: &str,
) -> Result<String> {
    // Teams sends the thread id as it is (19:…@thread.v2).
    anyhow::ensure!(
        thread.starts_with("19:")
            && thread
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || ":@._-".contains(c)),
        "Not a conversation id"
    );
    let (base, token) = super::tabs::middle_tier(client).await?;
    let e = super::tabs::encode_uri_component;
    let mut url = format!(
        "{base}/beta/shareToOutlook/GetEmailIdForConversation?threadId={thread}&messageId={}&locale=en-us",
        e(message_id)
    );
    if !body_type.is_empty() {
        url.push_str(&format!("&bodyType={}", e(body_type)));
    }
    let v: serde_json::Value = client
        .http()
        .get(url)
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let id = v
        .get("id")
        .or_else(|| v.get("emailId"))
        .and_then(|i| i.as_str())
        .or_else(|| v.as_str())
        .unwrap_or_default();
    anyhow::ensure!(!id.is_empty(), "No email draft for the conversation");
    Ok(id.to_string())
}

/// The compose page Teams frames for a Share to Outlook draft (Teams'
/// shareToOutlookOPXBaseUrl and shareToOutlookOPXConfig, culture added).
pub fn share_to_outlook_compose_url(email_id: &str, culture: &str) -> String {
    format!(
        "https://outlook.office.com/mail/opxdeeplink/compose/{}?isAnonymous=true&opxAuth=true&hostApp=teams&useOwaTheme=true&culture={}",
        super::tabs::encode_uri_component(email_id),
        super::tabs::encode_uri_component(culture)
    )
}

/// Closing Share to Outlook without sending: Teams discards the draft,
/// `DELETE {mt}/v1/shareToOutlook/email?emailId=…`.
pub async fn share_to_outlook_discard(client: &TeamsClient, email_id: &str) -> Result<()> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    client
        .http()
        .delete(format!(
            "{base}/v1/shareToOutlook/email?emailId={}",
            super::tabs::encode_uri_component(email_id)
        ))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// Whether a frame served from `origin` belongs to the app (Teams'
/// isValidOriginForApp).
pub fn origin_valid_for_app(origin: &str, valid_domains: &[String]) -> bool {
    let Ok(u) = url::Url::parse(origin) else {
        return false;
    };
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
            regex::escape(&d)
                .replace("\\.", "[.]")
                .replace("\\*", "[^/^.]+")
        );
        regex::Regex::new(&pattern).is_ok_and(|r| r.is_match(&href))
    })
}

/// A value as JavaScript source that is safe inside an inline `<script>`
/// of a page OST builds: JSON with `<`, `>` and `&` written as `\u003c`,
/// `\u003e`, `\u0026` (so `</script>` or `<!--` in it can't end or
/// change the script element) and U+2028/U+2029 escaped (line
/// terminators to older JavaScript). Quotes, backslashes and newlines are
/// escaped by JSON itself.
pub fn script_json(v: &serde_json::Value) -> String {
    let json = serde_json::to_string(v).unwrap_or_else(|_| "null".into());
    let mut out = String::with_capacity(json.len());
    for c in json.chars() {
        match c {
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c => out.push(c),
        }
    }
    out
}

/// Whether a page served from `origin` may have the camera, microphone,
/// location or notifications an app's App permissions allow: one of the
/// app's valid domains (Teams' isValidOriginForApp), or, for Microsoft's
/// own apps, Microsoft's own service hosts over https. Any other page in
/// the app's view (a link it navigated to, a frame from another site, a
/// redirect elsewhere) gets nothing.
pub fn device_origin_allowed(origin: &str, facts: &AppFacts) -> bool {
    // Chromium hands the requesting frame's origin ("https://host[:port]").
    let origin = origin.trim();
    if !url::Url::parse(origin).is_ok_and(|u| u.scheme() == "https" && u.host_str().is_some()) {
        return false;
    }
    origin_valid_for_app(origin, &facts.valid_domains)
        || (facts.microsoft_owned && crate::auth::token_hosts::redirect_allowed(origin))
}

/// The resource authentication.getAuthToken asks a token for, as Teams
/// picks it (module 9883 `w`): a full-trust Microsoft app's first asked
/// resource, else the app's webApplicationInfo resource (its
/// `{teamSiteDomain}` filled), which an asked resource must match.
pub fn sso_resource(
    f: &AppFacts,
    team_site_domain: &str,
    asked: Option<&serde_json::Value>,
) -> Result<String> {
    let asked: Vec<String> = asked
        .and_then(|a| a.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    if f.full_trust
        && f.microsoft_owned
        && let Some(r) = asked.first()
    {
        anyhow::ensure!(
            r.starts_with("https://") || r.starts_with("api://"),
            "Invalid resource"
        );
        return Ok(r.clone());
    }
    anyhow::ensure!(
        !f.web_app_resource.is_empty(),
        "App webApplicationInfo or resource not defined in manifest"
    );
    let mine = f
        .web_app_resource
        .replace("{teamSiteDomain}", team_site_domain);
    if let Some(r) = asked.first() {
        anyhow::ensure!(
            r.eq_ignore_ascii_case(&mine),
            "App resource defined in manifest and iframe origin do not match"
        );
    }
    Ok(mine)
}

/// Whether Teams offers deeply nested NAA (and managing trusted origins)
/// to an app: its id in ECS `extensibility.deeplyNestedAppAuthAllowList`
/// (Teams' NAA service, module 985817: `isDeeplyNestedAuthSupported()` is
/// `allowList.includes(appId)`, `canParentManageNAATrustedOrigins()` the
/// same). Measured: OneNote and Storyline yes; Lists, Whiteboard, Q&A
/// and Workflows no. Without the ECS list, the apps measured with it.
pub fn deep_naa(app_id: &str) -> bool {
    const MEASURED: [&str; 2] = [
        "0d820ecd-def2-4297-adad-78056cde7c78",
        "683f3525-d193-4a67-8d91-22093beab1ca",
    ];
    super::ecs::setting("extensibility", "deeplyNestedAppAuthAllowList")
        .and_then(|l| deep_naa_in(&l, app_id))
        .unwrap_or_else(|| MEASURED.iter().any(|a| a.eq_ignore_ascii_case(app_id)))
}

fn deep_naa_in(list: &serde_json::Value, app_id: &str) -> Option<bool> {
    Some(
        list.as_array()?
            .iter()
            .filter_map(|v| v.as_str())
            .any(|a| a.eq_ignore_ascii_case(app_id)),
    )
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
    let p = |v: &serde_json::Value, k: &str| {
        v.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let site = p(team_props, "sharepointSiteUrl");
    let (site_domain, site_path) = url::Url::parse(&site)
        .ok()
        .map(|u| {
            (
                u.host_str().unwrap_or_default().to_string(),
                u.path().trim_end_matches('/').to_string(),
            )
        })
        .unwrap_or_default();
    // Teams' userTeamRole: 0 owner (Admin), 1 member, 2 guest.
    let role = team_members
        .iter()
        .find(|m| m.get("id").and_then(|i| i.as_str()) == Some(user.mri.as_str()))
        .and_then(|m| m.get("role").and_then(|r| r.as_str()))
        .map(|r| match r {
            "Admin" => 0,
            "Guest" => 2,
            _ => 1,
        })
        .unwrap_or(1);
    let mut c = serde_json::json!({
        "locale": "en-us",
        "appId": app_id,
        "osLocaleInfo": { "platform": "windows", "regionalFormat": "en-us", "shortDate": "M/d/yyyy", "longDate": "dddd, MMMM d, yyyy",
                          "shortTime": "h:mm tt", "longTime": "h:mm:ss tt", "timezone": iana_zone() },
        "parentMessageId": "",
        "userClickTime": crate::clock::now_ms(),
        "userClickTimeV2": 0,
        "userFileOpenPreference": "inline",
        "manifestVersion": if manifest_version.is_empty() { "devPreview" } else { manifest_version },
        "hostName": "TeamsModern",
        "hostFeatures": { "nestedWildcardsInValidDomains": false, "serverSideRendering": false },
        "hostClientType": "desktop",
        "sessionId": session_id(),
        "ringId": super::ecs::ring(),
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
    } else if channel_id.is_empty() && !tenant_site_domain.is_empty() {
        // A personal app (Whiteboard, Shifts, Copilot…): no conversation,
        // the tenant's SharePoint host (measured).
        let extra = serde_json::json!({
            "channelId": "",
            "teamSiteId": "",
            "teamSiteUrl": "",
            "teamSiteDomain": tenant_site_domain,
            "teamSitePath": "",
        });
        if let (Some(o), serde_json::Value::Object(e)) = (c.as_object_mut(), extra) {
            o.extend(e);
            // (Teams gives a conversation-free app no OneNote section:
            // Copilot's context, captured on winpc 2026-11-23.)
            o.remove("defaultOneNoteSectionId");
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
        .or_else(|| {
            std::fs::read_link("/etc/localtime").ok().and_then(|p| {
                let s = p.to_string_lossy().to_string();
                s.split("zoneinfo/").nth(1).map(str::to_string)
            })
        })
        .unwrap_or_else(|| "UTC".into())
}

/// The service a OneDrive Copilot pane's fetchAuthToken asks for: its
/// `resource` when that is a Microsoft service's address (SharePoint
/// sends the site), else the service its `type` names. Anything else is
/// refused.
pub fn odsp_token_resource(kind: &str, resource: &str) -> Result<String> {
    const ALLOWED: &[&str] = &[
        ".sharepoint.com",
        ".microsoft.com",
        ".office.com",
        ".office.net",
        ".cloud.microsoft",
        ".microsoftonline.com",
    ];
    if let Ok(u) = reqwest::Url::parse(resource.trim()) {
        let host = u.host_str().unwrap_or_default().to_ascii_lowercase();
        anyhow::ensure!(
            u.scheme() == "https"
                && ALLOWED
                    .iter()
                    .any(|d| host.ends_with(d) || format!(".{host}") == *d),
            "Not a Microsoft service"
        );
        return Ok(format!("https://{host}"));
    }
    let by_type = match kind.to_ascii_lowercase().as_str() {
        "graph" | "msgraph" => "https://graph.microsoft.com",
        "substrate" | "mssubstrate" | "mssubstratetenantfeedback" => "https://substrate.office.com",
        "augloop" => "https://augloop.office.com",
        "ocps" => "https://clients.config.office.net",
        _ => anyhow::bail!("Unknown token kind"),
    };
    Ok(by_type.into())
}

/// The tenant's SharePoint host (`<tenant>.sharepoint.com`), from Graph's
/// root site (cached).
pub async fn sharepoint_host(client: &TeamsClient) -> String {
    tenant_site_domain(client).await
}

/// Your OneDrive site as Teams' context names it for Copilot
/// (`mySiteDomain` `<tenant>-my.sharepoint.com`, `mySitePath`
/// `/personal/<you>`), from Graph's drive address.
pub async fn my_site(client: &TeamsClient) -> Option<(String, String)> {
    let v: serde_json::Value = client
        .graph_get("/me/drive?$select=webUrl")
        .await
        .ok()?
        .json()
        .await
        .ok()?;
    my_site_from(v.get("webUrl")?.as_str()?)
}

fn my_site_from(web_url: &str) -> Option<(String, String)> {
    let u = url::Url::parse(web_url).ok()?;
    let mut parts = u.path().split('/').filter(|p| !p.is_empty());
    let (a, b) = (parts.next()?, parts.next()?);
    Some((u.host_str()?.to_string(), format!("/{a}/{b}")))
}

async fn tenant_site_domain(client: &TeamsClient) -> String {
    static HOST: Mutex<Option<String>> = Mutex::new(None);
    if let Some(h) = HOST.lock().ok().and_then(|h| h.clone()) {
        return h;
    }
    let h = async {
        let v: serde_json::Value = client
            .graph_get("/sites/root?$select=siteCollection")
            .await
            .ok()?
            .json()
            .await
            .ok()?;
        v.pointer("/siteCollection/hostname")
            .and_then(|h| h.as_str())
            .map(str::to_string)
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
pub async fn context(
    client: &TeamsClient,
    app_id: &str,
    thread: &str,
    team_thread: &str,
) -> Result<serde_json::Value> {
    let user = HostUser {
        tid: client.tenant_id().unwrap_or_default(),
        oid: client.object_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
        mri: client.self_mri().unwrap_or_default(),
    };
    let manifest = facts(client, app_id)
        .await
        .map(|f| f.manifest_version)
        .unwrap_or_default();
    let is_channel = thread.ends_with("@thread.tacv2") || thread.ends_with("@thread.skype");
    let (mut channel, mut team, mut members) =
        (serde_json::Value::Null, serde_json::Value::Null, Vec::new());
    let team_id = if team_thread.is_empty() {
        thread
    } else {
        team_thread
    };
    if is_channel {
        channel = super::tab_add::thread_properties(client, thread)
            .await
            .unwrap_or_default();
        let url = format!(
            "{}/v1/threads/{}?view=msnp24Equivalent",
            client.chat_service_url(),
            super::tabs::encode_uri_component(team_id)
        );
        if let Ok(r) = client.chat_get(&url).await
            && let Ok(v) = r.json::<serde_json::Value>().await
        {
            team = v.get("properties").cloned().unwrap_or_default();
            members = v
                .get("members")
                .and_then(|m| m.as_array())
                .cloned()
                .unwrap_or_default();
        }
    }
    let chat = if !is_channel && !thread.is_empty() {
        thread
    } else {
        ""
    };
    // Chats and personal apps carry the tenant's SharePoint host.
    let site = if is_channel {
        String::new()
    } else {
        tenant_site_domain(client).await
    };
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

/// The meeting's own whiteboard, which Teams keeps for the meeting so
/// everyone opens the same board (captured 2026-11-16 in a "Meeting with
/// OST Test 1" chat): `GET {mt}/beta/meetings/fluidboard?threadId=…
/// &messageId=0&organizerId=8:orgid:{organizer}&tenantId=…&meetingTitle=…`
/// answers `{url, shareUrl}`, the board's Whiteboard address (with its
/// `encodedShareLink` once there is a board).
pub async fn meeting_board(
    client: &TeamsClient,
    thread: &str,
    organizer_oid: &str,
    title: &str,
) -> Result<String> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let q = board_query(client, thread, organizer_oid);
    let v: serde_json::Value = client
        .http()
        .get(format!(
            "{base}/beta/meetings/fluidboard?{q}&meetingTitle={}",
            super::tabs::encode_uri_component(title)
        ))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let url = v.get("url").and_then(|u| u.as_str()).unwrap_or_default();
    anyhow::ensure!(
        url.starts_with("https://"),
        "No whiteboard url for this meeting"
    );
    Ok(url.to_string())
}

/// The meeting's annotation board (Teams' Annotate; 326418
/// `getAnnotationUrl`): `GET {mt}/beta/meetings/annotation?threadId=…
/// &organizerId=…&tenantId=…&meetingTitle=…` (no messageId) answers
/// `{url, shareUrl}`.
pub async fn meeting_annotation_board(
    client: &TeamsClient,
    thread: &str,
    organizer_oid: &str,
    title: &str,
) -> Result<String> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let e = super::tabs::encode_uri_component;
    let q = format!(
        "threadId={}&organizerId={}&tenantId={}&meetingTitle={}",
        e(thread),
        e(&crate::identity::user_mri(organizer_oid)),
        e(&client.tenant_id().unwrap_or_default()),
        e(title)
    );
    let v: serde_json::Value = client
        .http()
        .get(format!("{base}/beta/meetings/annotation?{q}"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let url = v.get("url").and_then(|u| u.as_str()).unwrap_or_default();
    anyhow::ensure!(
        url.starts_with("https://"),
        "No annotation board for this meeting"
    );
    Ok(url.to_string())
}

/// Keep the meeting's annotation board as Teams does once Whiteboard
/// reports it (326418 `postAnnotationWhiteboard`): `POST {mt}/beta/
/// meetings/annotation?threadId=…&messageId=…&organizerId=…&tenantId=…`,
/// the address (without its proof token) as a JSON string.
pub async fn save_meeting_annotation_board(
    client: &TeamsClient,
    thread: &str,
    organizer_oid: &str,
    url: &str,
) -> Result<()> {
    let url = board_url_to_save(url).context("Not a whiteboard address")?;
    let (base, token) = super::tabs::middle_tier(client).await?;
    client
        .http()
        .post(format!(
            "{base}/beta/meetings/annotation?{}",
            board_query(client, thread, organizer_oid)
        ))
        .bearer_auth(&token)
        .json(&url)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// A shared board's address in the meeting stage, as Teams' whiteboard
/// renderer loads it (measured 2026-11-18, Teams presenting Whiteboard in
/// a Meet now): the session's address (`meeting?embed=1&meetingTitle=…
/// &initiatorId=…&initiatorTimestamp=…`, `meetingType`, `meetingTenantId`
/// from 89637 `Tm`), then correlationId, culture, enableReactApp,
/// isInitiator, isEduUser, meetingId, teamsEnvV2, client, userRole,
/// teamsCallId, meetingTenantId, isMeetingRecurring, isEU, userId,
/// userTenantId, isNAAEnabled. `extra` adds Annotate's parameters
/// (screenSharer, sharedScreenWidth…).
#[allow(clippy::too_many_arguments)]
pub fn shared_board_frame_url(
    session_url: &str,
    correlation: &str,
    initiator: bool,
    meeting_id: &str,
    call_id: &str,
    user: &str,
    tenant: &str,
    extra: &[(&str, String)],
) -> Option<String> {
    let mut u = url::Url::parse(session_url)
        .ok()
        .filter(|u| u.scheme() == "https")?;
    {
        let mut q = u.query_pairs_mut();
        for (k, v) in extra {
            q.append_pair(k, v);
        }
        q.append_pair("correlationId", correlation)
            .append_pair("culture", "en-us")
            .append_pair("enableReactApp", "1")
            .append_pair("isInitiator", if initiator { "1" } else { "0" })
            .append_pair("isEduUser", "0")
            .append_pair("meetingId", meeting_id)
            .append_pair("teamsEnvV2", "prod")
            .append_pair("client", "TeamsModern")
            .append_pair("userRole", "Member")
            .append_pair("teamsCallId", call_id)
            .append_pair("meetingTenantId", tenant)
            .append_pair("isMeetingRecurring", "false")
            .append_pair("isEU", "false")
            .append_pair("userId", user)
            .append_pair("userTenantId", tenant)
            .append_pair("isNAAEnabled", "true");
    }
    Some(u.to_string())
}

fn board_query(client: &TeamsClient, thread: &str, organizer_oid: &str) -> String {
    let e = super::tabs::encode_uri_component;
    format!(
        "threadId={}&messageId=0&organizerId={}&tenantId={}",
        e(thread),
        e(&crate::identity::user_mri(organizer_oid)),
        e(&client.tenant_id().unwrap_or_default())
    )
}

/// A board address as Teams keeps it for the meeting: what Whiteboard
/// sent in `changeWhiteboardUrl`, without its `proofToken` (a credential;
/// Teams' saved address has none).
pub fn board_url_to_save(url: &str) -> Option<String> {
    let mut u = url::Url::parse(url)
        .ok()
        .filter(|u| u.scheme() == "https")?;
    let host = u.host_str()?.to_ascii_lowercase();
    if !(host == "app.whiteboard.microsoft.com"
        || host == "whiteboard.cloud.microsoft"
        || host.ends_with(".whiteboard.microsoft.com"))
    {
        return None;
    }
    // The other parameters exactly as sent.
    let kept: Vec<&str> = u
        .query()
        .unwrap_or_default()
        .split('&')
        .filter(|p| !p.is_empty() && !p.starts_with("proofToken=") && *p != "proofToken")
        .collect();
    let query = kept.join("&");
    u.set_query(if query.is_empty() { None } else { Some(&query) });
    Some(u.to_string())
}

/// Keep the meeting's board, as Teams does when Whiteboard reports it
/// (`changeWhiteboardUrl`): `POST {mt}/beta/meetings/v2/whiteboard?
/// threadId=…&messageId=0&organizerId=…&tenantId=…` with the address as a
/// JSON string; answered `{"success": true}`.
pub async fn save_meeting_board(
    client: &TeamsClient,
    thread: &str,
    organizer_oid: &str,
    url: &str,
) -> Result<()> {
    let url = board_url_to_save(url).context("Not a whiteboard address")?;
    let (base, token) = super::tabs::middle_tier(client).await?;
    client
        .http()
        .post(format!(
            "{base}/beta/meetings/v2/whiteboard?{}",
            board_query(client, thread, organizer_oid)
        ))
        .bearer_auth(&token)
        .json(&url)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// Teams' parameters on a meeting board's address in the meeting chat's
/// Whiteboard tab (measured): the stored address, then tabStartTime,
/// correlationId, culture, enableReactApp, isInitiator, isEduUser,
/// meetingId, teamsEnvV2, client, userRole, isEU, userId, userTenantId,
/// isNAAEnabled.
#[allow(clippy::too_many_arguments)]
pub fn board_frame_url(
    stored: &str,
    tab_start: i64,
    correlation: &str,
    initiator: bool,
    meeting_id: &str,
    user: &str,
    tenant: &str,
) -> Option<String> {
    let mut u = url::Url::parse(stored)
        .ok()
        .filter(|u| u.scheme() == "https")?;
    u.query_pairs_mut()
        .append_pair("tabStartTime", &tab_start.to_string())
        .append_pair("correlationId", correlation)
        .append_pair("culture", "en-us")
        .append_pair("enableReactApp", "1")
        .append_pair("isInitiator", if initiator { "1" } else { "0" })
        .append_pair("isEduUser", "0")
        .append_pair("meetingId", meeting_id)
        .append_pair("teamsEnvV2", "prod")
        .append_pair("client", "TeamsModern")
        .append_pair("userRole", "Member")
        .append_pair("isEU", "false")
        .append_pair("userId", user)
        .append_pair("userTenantId", tenant)
        .append_pair("isNAAEnabled", "true");
    Some(u.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn odsp_tokens_only_for_microsoft() {
        assert_eq!(
            odsp_token_resource("SharePoint", "https://x-my.sharepoint.com/personal/a").unwrap(),
            "https://x-my.sharepoint.com"
        );
        assert_eq!(
            odsp_token_resource("MSGraph", "").unwrap(),
            "https://graph.microsoft.com"
        );
        assert!(odsp_token_resource("SharePoint", "https://evil.example/x").is_err());
        assert!(odsp_token_resource("SharePoint", "http://x.sharepoint.com").is_err());
        assert!(odsp_token_resource("Other", "").is_err());
    }

    #[test]
    fn deep_naa_follows_teams_allow_list() {
        let list = serde_json::json!([
            "0d820ecd-def2-4297-adad-78056cde7c78",
            "683F3525-D193-4A67-8D91-22093BEAB1CA"
        ]);
        assert_eq!(
            deep_naa_in(&list, "0d820ecd-def2-4297-adad-78056cde7c78"),
            Some(true)
        );
        assert_eq!(
            deep_naa_in(&list, "683f3525-d193-4a67-8d91-22093beab1ca"),
            Some(true)
        );
        assert_eq!(
            deep_naa_in(&list, "26bc2873-6023-480c-a11b-76b66605ce8c"),
            Some(false)
        );
        assert_eq!(deep_naa_in(&serde_json::json!("x"), "a"), None);
    }

    #[test]
    fn meeting_boards_are_kept_as_teams() {
        // Whiteboard's changeWhiteboardUrl carries a proof token; Teams'
        // saved address has none.
        let sent = "https://app.whiteboard.microsoft.com/meeting?embed=1&encodedShareLink=aHR0cA%3D%3D&shareLinkId=ae8a&canEditBoardUsingProofToken=1&proofToken=v1.secret&fluidFileId=c3Bv";
        assert_eq!(
            board_url_to_save(sent).unwrap(),
            "https://app.whiteboard.microsoft.com/meeting?embed=1&encodedShareLink=aHR0cA%3D%3D&shareLinkId=ae8a&canEditBoardUsingProofToken=1&fluidFileId=c3Bv"
        );
        assert!(board_url_to_save("https://evil.example/meeting?x=1").is_none());
        assert!(board_url_to_save("http://app.whiteboard.microsoft.com/meeting").is_none());
        let f = board_frame_url("https://app.whiteboard.microsoft.com/meeting?embed=1&encodedShareLink=aHR0cA%3d%3d&shareLinkId=ae8a&meetingTitle=Meeting%20with%20OST%20Test%201",
            1794843119003, "c", true, "MCMx", "u", "t").unwrap();
        let keys: Vec<String> = url::Url::parse(&f)
            .unwrap()
            .query_pairs()
            .map(|(k, _)| k.into_owned())
            .collect();
        assert_eq!(
            keys,
            [
                "embed",
                "encodedShareLink",
                "shareLinkId",
                "meetingTitle",
                "tabStartTime",
                "correlationId",
                "culture",
                "enableReactApp",
                "isInitiator",
                "isEduUser",
                "meetingId",
                "teamsEnvV2",
                "client",
                "userRole",
                "isEU",
                "userId",
                "userTenantId",
                "isNAAEnabled"
            ]
        );
    }

    #[test]
    fn channel_context_is_teams() {
        let user = HostUser {
            tid: "t".into(),
            oid: "o".into(),
            upn: "u@x".into(),
            mri: "8:orgid:o".into(),
        };
        let channel = serde_json::json!({"topic": "OST test channel 2", "channelDocsFolderRelativeUrl": "/sites/OSTTestTeam/Shared Documents/OST test channel 2", "threadType": "topic"});
        let team = serde_json::json!({"spaceThreadTopic": "OST Test Team", "groupId": "g", "sharepointSiteUrl": "https://scnetsolutions.sharepoint.com/sites/OSTTestTeam"});
        let members = vec![serde_json::json!({"id": "8:orgid:o", "role": "Admin"})];
        let c = context_from(
            "0d820ecd-def2-4297-adad-78056cde7c78",
            "devPreview",
            &user,
            "",
            "",
            "19:c@thread.tacv2",
            &channel,
            "19:t@thread.tacv2",
            &team,
            &members,
        );
        assert_eq!(c["channelName"], "OST test channel 2");
        assert_eq!(
            c["channelRelativeUrl"],
            "/sites/OSTTestTeam/Shared Documents/OST test channel 2"
        );
        assert_eq!(c["channelType"], "Regular");
        assert_eq!(c["teamId"], "19:t@thread.tacv2");
        assert_eq!(c["teamSiteDomain"], "scnetsolutions.sharepoint.com");
        assert_eq!(c["teamSitePath"], "/sites/OSTTestTeam");
        assert_eq!(c["userTeamRole"], 0);
        assert_eq!(c["hostName"], "TeamsModern");
        assert_eq!(c["upn"], "u@x");
        let chat = context_from(
            "683f3525-d193-4a67-8d91-22093beab1ca",
            "1.25",
            &user,
            "19:a_b@unq.gbl.spaces",
            "x.sharepoint.com",
            "",
            &serde_json::Value::Null,
            "",
            &serde_json::Value::Null,
            &[],
        );
        assert_eq!(chat["channelId"], "");
        assert_eq!(chat["chatId"], "19:a_b@unq.gbl.spaces");
        // Teams' meetingId for a chat: base64 of "0#<chat>#0".
        assert_eq!(chat["meetingId"], "MCMxOTphX2JAdW5xLmdibC5zcGFjZXMjMA==");
        assert_eq!(chat["teamSiteDomain"], "x.sharepoint.com");
        assert_eq!(chat["manifestVersion"], "1.25");
        assert_eq!(chat["tid"], "t");
    }

    #[test]
    fn personal_apps_open_as_teams() {
        let d = serde_json::json!({
            "isFullScreen": true,
            "staticTabs": [
                {"entityId": "conversations", "scopes": ["personal"]},
                {"entityId": "shifts", "name": "Shifts", "contentUrl": "https://flw.teams.microsoft.com/shifts-web-app?ui-culture={locale}&tid={tid}", "scopes": ["personal"]},
                {"entityId": "about", "contentUrl": "https://example.com/about", "scopes": ["team"]}
            ]
        });
        let f = facts_from(&d);
        assert!(f.full_screen);
        assert_eq!(personal_tab(&f, "").unwrap().entity_id, "shifts");
        assert_eq!(personal_tab(&f, "about").unwrap().entity_id, "shifts");
        assert!(personal_tab(&facts_from(&serde_json::json!({})), "").is_none());
        let user = HostUser {
            tid: "t".into(),
            oid: "o".into(),
            upn: "u@x".into(),
            mri: "8:orgid:o".into(),
        };
        let c = context_from(
            "95de633a-083e-42f5-b444-a4295d8e9314",
            "1.25",
            &user,
            "",
            "x.sharepoint.com",
            "",
            &serde_json::Value::Null,
            "",
            &serde_json::Value::Null,
            &[],
        );
        assert_eq!(c["teamSiteDomain"], "x.sharepoint.com");
        assert_eq!(c["chatId"], "");
        assert_eq!(c["channelId"], "");
        assert!(
            c.get("defaultOneNoteSectionId").is_none(),
            "Teams gives Copilot no OneNote section"
        );
        assert_eq!(
            my_site_from("https://x-my.sharepoint.com/personal/u_x_com/Documents"),
            Some(("x-my.sharepoint.com".into(), "/personal/u_x_com".into()))
        );
    }

    #[test]
    fn joined_teams_and_share_to_outlook_as_teams() {
        let t = super::super::teams::ListTeam {
            id: "g".into(),
            thread_id: "19:t@thread.tacv2".into(),
            name: "OST Test Team".into(),
            role: "admin".into(),
            ..Default::default()
        };
        let v = joined_teams_from(&[t]);
        assert_eq!(v["userJoinedTeams"][0]["teamId"], "19:t@thread.tacv2");
        assert_eq!(v["userJoinedTeams"][0]["groupId"], "g");
        assert_eq!(v["userJoinedTeams"][0]["userTeamRole"], 0);
        assert_eq!(
            share_to_outlook_compose_url("AAMk=", "en-us"),
            "https://outlook.office.com/mail/opxdeeplink/compose/AAMk%3D?isAnonymous=true&opxAuth=true&hostApp=teams&useOwaTheme=true&culture=en-us"
        );
    }

    #[test]
    fn script_values_cannot_break_out_of_the_script() {
        let evil =
            "https://x.example/?a=</script><script>alert(1)</script><!--\"'\n\r\u{2028}\u{2029}&\\";
        let v = serde_json::json!({ "url": evil, "domains": [evil] });
        let js = script_json(&v);
        for bad in ["<", ">", "\n", "\r", "\u{2028}", "\u{2029}", "&"] {
            assert!(!js.contains(bad), "{bad:?} left unescaped");
        }
        // Every quote is escaped: the string literal can't end early.
        let lit = script_json(&serde_json::json!(evil));
        assert!(lit.starts_with('"') && lit.ends_with('"'));
        assert!(
            !lit[1..lit.len() - 1]
                .replace("\\\\", "")
                .replace("\\\"", "")
                .contains('"'),
            "a quote ends the literal early"
        );
        // It is still the same value to a JavaScript (and JSON) parser.
        let back: serde_json::Value = serde_json::from_str(&js).unwrap();
        assert_eq!(back, v);
        // Inside the page it stays one script element.
        let page = format!("<script>const v = {js};</script>");
        assert_eq!(page.matches("</script>").count(), 1);
        assert_eq!(page.matches("<script>").count(), 1);
    }

    #[test]
    fn valid_domains_match_as_teams() {
        let d = vec![
            "*.officeapps.live.com".to_string(),
            "www.microsoft365.com".to_string(),
            "*.resources.office.net".to_string(),
        ];
        assert!(origin_valid_for_app("https://www.microsoft365.com", &d));
        assert!(origin_valid_for_app(
            "https://oauth.officeapps.live.com",
            &d
        ));
        assert!(origin_valid_for_app(
            "https://fa000000128.resources.office.net",
            &d
        ));
        // One label per `*`, https only, no look-alikes.
        assert!(!origin_valid_for_app("https://a.b.officeapps.live.com", &d));
        assert!(!origin_valid_for_app("http://www.microsoft365.com", &d));
        // Device permissions follow the same rule.
        let f = AppFacts {
            valid_domains: d.clone(),
            ..Default::default()
        };
        assert!(device_origin_allowed("https://www.microsoft365.com", &f));
        assert!(!device_origin_allowed("http://www.microsoft365.com", &f));
        assert!(!device_origin_allowed("https://evil.example", &f));
        assert!(!device_origin_allowed(
            "https://www.microsoft365.com.evil.example",
            &f
        ));
        assert!(!device_origin_allowed("", &f));
        assert!(!device_origin_allowed("null", &f));
        // A third-party app's page can't borrow Microsoft's hosts.
        assert!(!device_origin_allowed("https://teams.microsoft.com", &f));
        let ms = AppFacts {
            microsoft_owned: true,
            ..f.clone()
        };
        assert!(device_origin_allowed("https://tasks.office.com", &ms));
        assert!(!device_origin_allowed("https://evil.example", &ms));
        assert!(!origin_valid_for_app(
            "https://www.microsoft365.com.evil.example",
            &d
        ));
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
        assert_eq!(
            f.valid_domains,
            vec!["*.onenote.com", "www.microsoft365.com", "www.onenote.com"]
        );
        assert_eq!(f.web_app_id, "app");
        assert_eq!(f.web_app_resource, "https://onenote.com");
        assert!(!f.microsoft_owned);
    }
}
