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
    /// A meeting's notes in the call window's Notes panel.
    MeetingNotes,
    /// A Loop component in the compose box (Teams' "Loop components").
    Compose,
    /// A Loop component in a message (Teams' FluidEmbedCard).
    Message,
}

impl Kind {
    pub fn parse(s: &str) -> Self {
        match s {
            "channelPages" => Kind::ChannelPage,
            "meetingNotes" => Kind::MeetingNotes,
            "compose" => Kind::Compose,
            "message" => Kind::Message,
            _ => Kind::ChatNotes,
        }
    }
    fn name(self) -> &'static str {
        match self {
            Kind::ChatNotes => "fluidThread",
            Kind::ChannelPage => "channelPages",
            Kind::MeetingNotes => "meetingNotes",
            Kind::Compose => "compose",
            Kind::Message => "message",
        }
    }
    /// Teams' settings category for the page (its fluid settings; the
    /// meeting notes panel's isn't traced, so it takes the chat notes').
    fn category(self) -> &'static str {
        match self {
            Kind::ChatNotes | Kind::MeetingNotes => "fluidThread",
            Kind::ChannelPage => "channelPages",
            // Loop components in compose and messages take messaging's
            // own fluid settings (view properties growHeight, maxHeight
            // 20rem, viewType Large).
            Kind::Compose | Kind::Message => "messaging",
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
            let host = rest
                .split('/')
                .next()
                .unwrap_or_default()
                .to_ascii_lowercase();
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
            if host == "augloop.office.com"
                && rest
                    .to_ascii_lowercase()
                    .starts_with("augloop.office.com/v2/")
            {
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
            (e.until.checked_duration_since(Instant::now())? > RENEW_BEFORE)
                .then(|| e.token.clone())
        })
    {
        return Ok((t, true));
    }
    let (t, expires) = crate::auth::oauth::access_token_expiring(&scope).await?;
    if let Ok(mut c) = TOKENS.lock() {
        c.get_or_insert_with(HashMap::new).insert(
            scope,
            Cached {
                token: t.clone(),
                until: Instant::now() + Duration::from_secs(expires.unwrap_or(3600)),
            },
        );
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
    let vp = |view_type: &str| {
        json!({ "compactMargins": false, "viewType": view_type, "layoutMode": "fixedByHost", "visualSpacingTop": 12,
                                       "narrowVisualSpacingLeft": 28, "narrowVisualSpacingRight": 28 })
    };
    let mut d = json!({
        "ipEnabled": true, "oneWayRedeemEnabled": true, "sizeLimitEnabled": true, "phasedLoadEnabled": true,
        "paragraphWithoutInsertionMenuExperimentEnabled": true, "enableDiscoveryFooterInAttachedState": true,
        "startInPostCriticalEnabled": true, "useResolvedUrlForLocator": true,
    });
    match kind {
        Kind::ChatNotes | Kind::MeetingNotes => {
            d["sizeLimitValueBytes"] = json!(6291456);
            d["viewProperties"] = vp("Small");
        }
        Kind::ChannelPage => {
            d["sizeLimitValueBytes"] = json!(0xa00000);
            d["viewProperties"] = vp("Large");
        }
        // Messaging's settings are ECS's `messaging.fluid` as they are.
        Kind::Compose | Kind::Message => return json!({}),
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
pub fn fluid_settings_from(
    messaging: Option<&Value>,
    category: Option<&Value>,
    kind: Kind,
) -> Value {
    let mut s = messaging
        .cloned()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));
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
    let audience = setting("messaging", "fluidAudience")
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_else(|| "Production".into());
    let fluid = fluid_settings_from(
        setting("messaging", "fluid").as_ref(),
        setting(kind.category(), "fluid").as_ref(),
        kind,
    );
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
    let folder = props
        .get("channelDocsFolderRelativeUrl")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    anyhow::ensure!(
        folder.starts_with('/'),
        "The channel has no files folder yet"
    );
    let site_path = site_path_of(&folder).context("The channel's files folder")?;
    let host = super::app_host::sharepoint_host(client).await;
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "The tenant's SharePoint");
    let site_url = format!("https://{host}{site_path}");
    let drive: Value = client
        .graph_get(&format!(
            "/sites/{host}:{site_path}:/drive?$select=id,webUrl"
        ))
        .await?
        .json()
        .await
        .context("The site's library")?;
    let drive_id = drive
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let lib_url = url::Url::parse(
        drive
            .get("webUrl")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
    )
    .context("The site's library")?;
    let lib_path = percent_decode(lib_url.path());
    anyhow::ensure!(!drive_id.is_empty(), "The site's library");
    let file_path = folder_in_library(&folder, &lib_path)
        .context("The channel's folder isn't in its site's library")?;
    Ok(PageTarget {
        site_url,
        drive_id,
        file_path,
    })
}

fn percent_decode(s: &str) -> String {
    url::form_urlencoded::parse(format!("x={}", s.replace('+', "%2B")).as_bytes())
        .next()
        .map(|(_, v)| v.into_owned())
        .unwrap_or_else(|| s.to_string())
}

/// Where Teams makes a Loop component from the compose box: in a chat,
/// your OneDrive's "Microsoft Teams Chat Files" folder (as Teams' chat
/// file uploads); in a channel, the channel's folder (measured 2026-11-20:
/// `POST {OneDrive}/_api/v2.1/drives/{d}/items/root:%2FMicrosoft%20Teams%20Chat%20Files/Loop%20paragraph.loop:/opStream/snapshots/snapshot`,
/// no share link yet).
pub async fn compose_target(client: &TeamsClient, conversation: &str) -> Result<PageTarget> {
    if conversation.ends_with("@thread.tacv2") {
        return channel_page_target(client, conversation).await;
    }
    let drive: Value = client
        .graph_get("/me/drive?$select=id,webUrl")
        .await?
        .json()
        .await?;
    let drive_id = drive
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let site = super::meeting_notes::site_of(
        drive
            .get("webUrl")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )
    .context("Your OneDrive")?;
    anyhow::ensure!(!drive_id.is_empty(), "Your OneDrive");
    Ok(PageTarget {
        site_url: site,
        drive_id,
        file_path: CHAT_FILES_FOLDER.to_string(),
    })
}

/// The folder Teams keeps a chat's files in, in the sender's OneDrive.
pub const CHAT_FILES_FOLDER: &str = "Microsoft Teams Chat Files";

/// A drive or item id as Graph hands them out (nothing that could change
/// the request's path).
fn plain_id(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c))
}

/// A compose Loop component's link, as Teams makes it once the component
/// exists: the item's organization edit link (`createLink {"type":"edit",
/// "scope":"organization"}`) with the component's `nav`, and the link's
/// description for the card ("People in your organization with the link
/// can edit").
pub async fn compose_link(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
    page_link: &str,
) -> Result<(String, String, String)> {
    anyhow::ensure!(
        plain_id(drive_id) && plain_id(item_id),
        "Not a Loop component"
    );
    // As Teams: SharePoint's own v2.1 createLink (its answer names the link
    // in the user's language, `localizedDescription`); Graph's otherwise.
    let host = url::Url::parse(page_link)
        .ok()
        .and_then(|u| u.host_str().map(str::to_string))
        .unwrap_or_default();
    let body = json!({ "type": "edit", "scope": "organization" });
    let sp: Option<Value> = async {
        anyhow::ensure!(host.ends_with(".sharepoint.com"), "not SharePoint");
        let token =
            crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
        let r = reqwest::Client::new()
            .post(format!(
                "https://{host}/_api/v2.1/drives/{drive_id}/items/{item_id}/createLink"
            ))
            .bearer_auth(token)
            .json(&body)
            .send()
            .await?
            .error_for_status()?;
        anyhow::Ok(r.json::<Value>().await?)
    }
    .await
    .ok();
    let v: Value = match sp {
        Some(v) => v,
        None => {
            client
                .graph_post(
                    &format!("/drives/{drive_id}/items/{item_id}/createLink"),
                    &body,
                )
                .await?
                .json()
                .await?
        }
    };
    let web = v
        .pointer("/link/webUrl")
        .and_then(Value::as_str)
        .context("The component's link")?;
    let desc = v
        .pointer("/link/localizedDescription")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    // The link's share id (its permission's id), which Teams deletes when
    // Link settings replace the link.
    let share = v
        .get("shareId")
        .or_else(|| v.get("id"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    Ok((
        super::meeting_notes::shared_link(web, page_link),
        desc,
        share,
    ))
}

/// A compose Loop component's file as SharePoint names it (site, list and
/// item unique id), for the link settings Teams' header opens, and its
/// current organization link's share id.
pub async fn compose_file_ref(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
) -> Result<(super::sharing::ItemRef, String)> {
    anyhow::ensure!(
        plain_id(drive_id) && plain_id(item_id),
        "Not a Loop component"
    );
    let v: Value = client
        .graph_get(&format!(
            "/drives/{drive_id}/items/{item_id}?$select=id,name,sharepointIds"
        ))
        .await?
        .json()
        .await?;
    let ids = v.get("sharepointIds").context("The component's file")?;
    let g = |k: &str| {
        ids.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let r = super::sharing::ItemRef {
        site: g("siteUrl"),
        list: g("listId"),
        item: g("listItemUniqueId"),
    };
    anyhow::ensure!(
        !r.site.is_empty() && !r.list.is_empty() && !r.item.is_empty(),
        "The component's file"
    );
    Ok((
        r,
        v.get("name")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
    ))
}

/// The component's link changed in its header's Link settings, as Teams'
/// fluid compose permission button does (525430 `onFilePermissionChange`):
/// the chosen link is made (SharePoint's ShareLink, with the chat's people
/// for "People currently in this chat"), the component's link becomes it
/// with the component's `nav` kept, and the old link, when it was a
/// different one, is deleted (Teams' deleteShareLink: `DELETE
/// drives/{d}/items/{i}/permissions/{shareId}`). Returns the component's
/// new link and the new share id.
pub async fn compose_relink(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
    component_url: &str,
    old_share_id: &str,
    body: Option<&Value>,
) -> Result<(String, String)> {
    let (url, share_id) = match body {
        Some(body) => {
            let (r, _) = compose_file_ref(client, drive_id, item_id).await?;
            super::sharing::create_link_for(&r, body).await?
        }
        // "People with existing access": no link, the file's own address.
        None => {
            anyhow::ensure!(
                plain_id(drive_id) && plain_id(item_id),
                "Not a Loop component"
            );
            let v: Value = client
                .graph_get(&format!(
                    "/drives/{drive_id}/items/{item_id}?$select=id,webUrl"
                ))
                .await?
                .json()
                .await?;
            (
                v.get("webUrl")
                    .and_then(Value::as_str)
                    .context("The component's file")?
                    .to_string(),
                String::new(),
            )
        }
    };
    if !old_share_id.is_empty()
        && !old_share_id.eq_ignore_ascii_case(&share_id)
        && plain_id(&old_share_id.replace('-', ""))
        && let Err(e) = client
            .graph_delete(&format!(
                "/drives/{drive_id}/items/{item_id}/permissions/{old_share_id}"
            ))
            .await
    {
        tracing::warn!("deleting the Loop component's old link failed: {e:#}");
    }
    Ok((
        super::meeting_notes::shared_link(&url, component_url),
        share_id,
    ))
}

/// Discard (Teams' "The Loop component will be deleted."): the file goes.
pub async fn compose_discard(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<()> {
    anyhow::ensure!(
        plain_id(drive_id) && plain_id(item_id),
        "Not a Loop component"
    );
    client
        .graph_delete(&format!("/drives/{drive_id}/items/{item_id}"))
        .await?;
    Ok(())
}

/// The first `n` UTF-16 units of `s` (JavaScript's slice(0, n)).
fn js_slice(s: &str, n: usize) -> &str {
    let mut units = 0;
    for (i, c) in s.char_indices() {
        units += c.len_utf16();
        if units > n {
            return &s[..i];
        }
    }
    s
}

/// The file's name once the component is sent, as Teams' fluid compose
/// (997266 `lt`, at send) picks it: the component's title (its first 60
/// characters); a component without one is named after the chat ("{chat
/// title} Loop paragraph"); then ".loop", and ODSP's file-name rules (the
/// shared worker's `rj`: no ~ " # % & * : < > ? / \ { | } or line breaks,
/// "_vti_" as "vti", trimmed, no reserved names). None: Teams keeps the
/// name it made ("Loop paragraph.loop").
pub fn compose_file_name(title: &str, chat_title: &str, kind_name: &str) -> Option<String> {
    const MAX: usize = 60;
    let mut p = js_slice(title.trim(), MAX).trim().to_string();
    if p.is_empty() && !chat_title.trim().is_empty() {
        p = format!(
            "{} {}",
            js_slice(chat_title.trim(), MAX),
            js_slice(kind_name, MAX)
        );
    }
    if p.is_empty() {
        return None;
    }
    let clean: String = p
        .chars()
        .filter(|c| !"~\"#%&*:<>?/\\{|}\r\n".contains(*c))
        .collect();
    let clean = vti(&clean);
    let clean = clean.trim();
    const RESERVED: [&str; 24] = [
        "con", "prn", "aux", "nul", "com0", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
        "com8", "com9", "lpt0", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
        "lpt9",
    ];
    (!clean.is_empty() && !RESERVED.contains(&clean.to_lowercase().as_str()))
        .then(|| format!("{clean}.loop"))
}

/// ODSP's "_vti_" (any case) as "vti".
fn vti(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while !rest.is_empty() {
        if rest.len() >= 5 && rest.is_char_boundary(5) && rest[..5].eq_ignore_ascii_case("_vti_") {
            out.push_str("vti");
            rest = &rest[5..];
        } else {
            let c = rest.chars().next().unwrap();
            out.push(c);
            rest = &rest[c.len_utf8()..];
        }
    }
    out
}

pub async fn compose_rename(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
    title: &str,
    chat_title: &str,
    kind_name: &str,
) -> Result<()> {
    anyhow::ensure!(
        plain_id(drive_id) && plain_id(item_id),
        "Not a Loop component"
    );
    let Some(name) = compose_file_name(title, chat_title, kind_name) else {
        return Ok(());
    };
    client
        .graph_patch(
            &format!("/drives/{drive_id}/items/{item_id}?@microsoft.graph.conflictBehavior=rename"),
            &json!({ "name": name }),
        )
        .await?;
    Ok(())
}

/// The name Teams' page header shows: the page's file name without
/// `.loop` (Graph's shares lookup of its link).
pub async fn page_name(client: &TeamsClient, component_url: &str) -> Result<String> {
    Ok(super::tab_add::resolve_page_link(client, component_url)
        .await?
        .name)
}

/// "See who has access" (Loop's header PermissionsPanel with Teams'
/// ShareService, 154570): the component's file's permissions (ODSP v2.1
/// `drives/{d}/items/{i}/permissions`) as {personas [{name, email}] (the
/// people with an email, once each), groups [names], scope (the widest
/// link: anyone > anonymous > organization > users, else "")}.
pub fn access_from(v: &Value) -> Value {
    let mut personas: Vec<Value> = Vec::new();
    let mut groups: Vec<String> = Vec::new();
    let mut scopes: Vec<String> = Vec::new();
    for p in v
        .get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let mut users: Vec<&Value> = Vec::new();
        if let Some(u) = p.pointer("/grantedTo/user") {
            users.push(u);
        }
        for g in p
            .get("grantedToIdentities")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if let Some(u) = g.get("user") {
                users.push(u);
            }
        }
        for u in users {
            let name = u
                .get("displayName")
                .and_then(Value::as_str)
                .unwrap_or_default();
            match u
                .get("email")
                .and_then(Value::as_str)
                .filter(|e| !e.is_empty())
            {
                Some(email) => {
                    if !personas.iter().any(|x| {
                        x["email"]
                            .as_str()
                            .is_some_and(|e| e.eq_ignore_ascii_case(email))
                    }) {
                        personas.push(json!({ "name": name, "email": email }));
                    }
                }
                None if !name.is_empty() && !groups.iter().any(|g| g == name) => {
                    groups.push(name.to_string())
                }
                None => {}
            }
        }
        if let Some(sc) = p.pointer("/link/scope").and_then(Value::as_str) {
            scopes.push(sc.to_string());
        }
    }
    let scope = ["anyone", "anonymous", "organization", "users"]
        .iter()
        .find(|s| scopes.iter().any(|x| x == *s))
        .map(|s| s.to_string())
        .unwrap_or_default();
    json!({ "personas": personas, "groups": groups, "scope": scope })
}

pub async fn access(client: &TeamsClient, component_url: &str) -> Result<Value> {
    let link = component_url.split('?').next().unwrap_or(component_url);
    let item: Value = client
        .graph_get(&format!(
            "/shares/{}/driveItem?$select=id,webUrl,parentReference",
            super::drive::share_id(link)
        ))
        .await?
        .json()
        .await?;
    let s = |p: &str| {
        item.pointer(p)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let (drive, id, web) = (s("/parentReference/driveId"), s("/id"), s("/webUrl"));
    let host = url::Url::parse(&web)
        .ok()
        .and_then(|u| u.host_str().map(str::to_string))
        .context("The component's site")?;
    anyhow::ensure!(
        host.ends_with(".sharepoint.com") && !drive.is_empty() && !id.is_empty(),
        "The component's file"
    );
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let v: Value = reqwest::Client::new()
        .get(format!(
            "https://{host}/_api/v2.1/drives/{drive}/items/{id}/permissions"
        ))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(access_from(&v))
}

/// A sent component's link as its edit box's header names it (Teams'
/// compose header: the link's description, "People in your organization
/// with the link can edit"): the widest sharing link on its file
/// (`localizedDescription` when SharePoint gives one).
pub async fn link_description(client: &TeamsClient, component_url: &str) -> Result<Value> {
    let link = component_url.split('?').next().unwrap_or(component_url);
    let item: Value = client
        .graph_get(&format!(
            "/shares/{}/driveItem?$select=id,webUrl,parentReference",
            super::drive::share_id(link)
        ))
        .await?
        .json()
        .await?;
    let s = |p: &str| {
        item.pointer(p)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let (drive, id) = (s("/parentReference/driveId"), s("/id"));
    anyhow::ensure!(plain_id(&drive) && plain_id(&id), "The component's file");
    let v: Value = client
        .graph_get(&format!("/drives/{drive}/items/{id}/permissions"))
        .await?
        .json()
        .await?;
    Ok(link_description_from(&v))
}

/// [`link_description`] from a permissions list: {description (SharePoint's
/// own words, if any), scope, edit}; the client words the rest.
pub fn link_description_from(v: &Value) -> Value {
    let rank = |scope: &str| match scope {
        "anonymous" | "anyone" => 3,
        "organization" => 2,
        "users" | "existingAccess" => 1,
        _ => 0,
    };
    let best = v
        .get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|p| p.get("link"))
        .max_by_key(|l| rank(l.get("scope").and_then(Value::as_str).unwrap_or_default()));
    let Some(l) = best else { return json!({}) };
    json!({
        "description": l.get("localizedDescription").and_then(Value::as_str).unwrap_or_default(),
        "scope": l.get("scope").and_then(Value::as_str).unwrap_or_default(),
        "edit": l.get("type").and_then(Value::as_str) == Some("edit"),
    })
}

/// Shared locations (the Loop control Teams bundles, 698099, with its
/// MTSFoundInPlaces provider): where a Loop component was shared, from
/// `GET https://substrate.office.com/recommended/api/beta/loop/sharedlocations
/// ?fileId=SPO_{site,web,list}_{item}`. Each `sharing_history` entry
/// becomes {host, location, title, url, participants}: Teams chats and
/// channels (title "team / channel" or the subject; participants' names
/// for Teams' fallback title), Outlook mail and calendar, and files (Word,
/// Whiteboard, a Loop page). Workspaces carry no address here and backlinks
/// need another lookup; both are left out.
pub fn shared_locations_from(v: &Value, me_email: &str) -> Value {
    let s = |v: &Value, p: &str| {
        v.pointer(p)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let places: Vec<Value> = v["sharing_history"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|n| {
            let medium = n.get("sharing_medium").and_then(Value::as_i64);
            let (host, location) = match medium {
                None | Some(0) => ("Outlook", "Email"),
                Some(1) => ("Teams", "Chat"),
                Some(2) => ("Outlook", "Calendar"),
                Some(3) => ("Teams", "Channel"),
                Some(6) => match s(n, "/file/type").as_str() {
                    "Word" => ("Word", "other"),
                    "Whiteboard" => ("Whiteboard", "other"),
                    "Fluid" => ("Loop", "Page"),
                    _ => ("other", "other"),
                },
                _ => return None,
            };
            if medium == Some(6) {
                return n.get("file").map(|_| json!({ "host": host, "location": location, "title": s(n, "/file/title"), "url": s(n, "/sharing_reference_url"), "participants": [] }));
            }
            n.get("sharing_reference_url")?;
            let (team, channel) = (s(n, "/teams_name"), s(n, "/teams_channel_name"));
            let title = if !team.is_empty() && !channel.is_empty() { format!("{team} / {channel}") } else { s(n, "/subject") };
            let mut self_name = String::new();
            let participants: Vec<String> = n["participants"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|p| {
                    let name = s(p, "/display_name");
                    if !me_email.is_empty() && s(p, "/smtp").eq_ignore_ascii_case(me_email) {
                        self_name = name;
                        return None;
                    }
                    (!name.is_empty()).then_some(name)
                })
                .collect();
            Some(json!({ "host": host, "location": location, "title": title, "url": s(n, "/sharing_reference_url"), "participants": participants, "self": self_name }))
        })
        .collect();
    json!({ "places": places })
}

/// Shared locations for a Loop component (its link), as Teams asks.
pub async fn shared_locations(client: &TeamsClient, component_url: &str) -> Result<Value> {
    let link = component_url.split('?').next().unwrap_or(component_url);
    let item: Value = client
        .graph_get(&format!(
            "/shares/{}/driveItem?$select=id,parentReference",
            super::drive::share_id(link)
        ))
        .await?
        .json()
        .await?;
    let s = |p: &str| {
        item.pointer(p)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let file_id = super::recaps::canonical_recap_id(&s("/parentReference/driveId"), &s("/id"));
    anyhow::ensure!(file_id.starts_with("SPO_"), "The component's file");
    let token =
        crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let (oid, tid) = (
        client.object_id().unwrap_or_default(),
        client.tenant_id().unwrap_or_default(),
    );
    let v: Value = reqwest::Client::new()
        .get(format!(
            "https://substrate.office.com/recommended/api/beta/loop/sharedlocations?fileId={}",
            urlencoding(&file_id)
        ))
        .bearer_auth(token)
        .header("Client-Request-Id", uuid::Uuid::new_v4().to_string())
        .header("X-Office-Application", "300")
        .header("X-Office-Platform", "Web")
        .header("X-AnchorMailbox", format!("OID:{oid}@{tid}"))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let me = client.user_principal_name().unwrap_or_default();
    Ok(shared_locations_from(&v, &me))
}

fn urlencoding(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// Add to Loop workspace (Teams' bundled Loop control): Loop's own page,
/// `https://loop.cloud.microsoft/p/{base64 of {"p":{"u":<component>,
/// "r":false},"a":"AddToWorkspace"}}`, opened in the browser.
pub fn add_to_workspace_url(component_url: &str) -> String {
    use base64::Engine as _;
    let body = json!({ "p": { "u": component_url, "r": false }, "a": "AddToWorkspace" });
    format!(
        "https://loop.cloud.microsoft/p/{}",
        urlencoding(&base64::engine::general_purpose::STANDARD.encode(body.to_string()))
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn link_description_names_the_widest_link() {
        let v = json!({"value": [
            {"roles": ["owner"], "grantedTo": {"user": {"displayName": "OST Test 1"}}},
            {"roles": ["write"], "link": {"type": "edit", "scope": "organization"}},
            {"roles": ["read"], "link": {"type": "view", "scope": "users"}}]});
        assert_eq!(
            link_description_from(&v),
            json!({"description": "", "scope": "organization", "edit": true})
        );
        let sp = json!({"value": [{"link": {"type": "edit", "scope": "organization", "localizedDescription": "People in Contoso with the link can edit"}}]});
        assert_eq!(
            link_description_from(&sp)["description"],
            "People in Contoso with the link can edit"
        );
        assert_eq!(link_description_from(&json!({"value": []})), json!({}));
    }

    #[test]
    fn shared_locations_and_workspace_link_as_teams() {
        let v = shared_locations_from(
            &json!({"sharing_history": [
            {"sharing_medium": 1, "sharing_reference_url": "https://teams.microsoft.com/l/message/19:x", "subject": "", "participants": [
                {"display_name": "OST Test 1", "smtp": "ost-test1@x.com"}, {"display_name": "OST Test 2", "smtp": "ost-test2@x.com"}]},
            {"sharing_medium": 3, "sharing_reference_url": "https://teams.microsoft.com/l/channel/19:y", "teams_name": "OST Test Team", "teams_channel_name": "General"},
            {"sharing_medium": 6, "file": {"type": "Fluid", "title": "Plan"}, "sharing_reference_url": "https://x/plan.loop"},
            {"sharing_medium": 7, "backlink": {"page_id": "p"}}]}),
            "OST-TEST1@x.com",
        );
        let p = v["places"].as_array().unwrap();
        assert_eq!(p.len(), 3);
        assert_eq!(
            (
                p[0]["host"].as_str(),
                p[0]["location"].as_str(),
                p[0]["self"].as_str()
            ),
            (Some("Teams"), Some("Chat"), Some("OST Test 1"))
        );
        assert_eq!(p[0]["participants"], json!(["OST Test 2"]));
        assert_eq!(p[1]["title"], "OST Test Team / General");
        assert_eq!(
            (p[2]["host"].as_str(), p[2]["location"].as_str()),
            (Some("Loop"), Some("Page"))
        );
        // Teams' Add to Loop workspace for OST TEST 240's notes (winpc,
        // 2026-11-21): the base64 decodes to {"p":{"u":…,"r":false},"a":"AddToWorkspace"}.
        use base64::Engine as _;
        let u = add_to_workspace_url("https://x.sharepoint.com/:fl:/r/a.loop?d=w1");
        let b64 = u
            .strip_prefix("https://loop.cloud.microsoft/p/")
            .unwrap()
            .replace("%3D", "=")
            .replace("%2B", "+")
            .replace("%2F", "/");
        let back: Value = serde_json::from_slice(
            &base64::engine::general_purpose::STANDARD
                .decode(b64)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            back,
            json!({"p": {"u": "https://x.sharepoint.com/:fl:/r/a.loop?d=w1", "r": false}, "a": "AddToWorkspace"})
        );
    }

    #[test]
    fn access_reads_permissions_as_teams() {
        let v = access_from(&json!({"value": [
            {"roles": ["owner"], "grantedTo": {"user": {"displayName": "OST Test 1", "email": "ost-test1@x.com"}}},
            {"roles": ["write"], "grantedToIdentities": [{"user": {"displayName": "OST Test 2", "email": "ost-test2@x.com"}}, {"user": {"displayName": "OST Test 1", "email": "OST-TEST1@x.com"}}],
             "link": {"scope": "users"}},
            {"roles": ["read"], "grantedTo": {"user": {"displayName": "Everyone except external users"}}},
            {"roles": ["write"], "link": {"scope": "organization"}}]}));
        assert_eq!(v["personas"].as_array().unwrap().len(), 2);
        assert_eq!(v["groups"][0], "Everyone except external users");
        assert_eq!(v["scope"], "organization");
    }

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn compose_names_as_teams() {
        let n = |t: &str, c: &str| compose_file_name(t, c, "Loop paragraph");
        assert_eq!(
            n("OST TEST 85 loop", "OST group test").as_deref(),
            Some("OST TEST 85 loop.loop")
        );
        assert_eq!(
            n("  a/b: c? {x} ~1 & 2  ", "").as_deref(),
            Some("ab c x 1  2.loop")
        );
        assert_eq!(n("my _VTI_ page", "").as_deref(), Some("my vti page.loop"));
        // no title: the chat's, then the component's kind
        assert_eq!(
            n("   ", "OST group test").as_deref(),
            Some("OST group test Loop paragraph.loop")
        );
        assert_eq!(n("", ""), None);
        assert_eq!(n("con", ""), None);
        // the title's first 60 characters
        assert_eq!(
            n(&"x".repeat(70), "").unwrap(),
            format!("{}.loop", "x".repeat(60))
        );
        assert_eq!(Kind::parse("compose").category(), "messaging");
        assert_eq!(category_defaults(Kind::Message), json!({}));
    }

    #[test]
    fn tokens_go_to_the_resources_teams_asks_for() {
        // The scopes Loop's page container asked Teams for (2026-11-16).
        assert_eq!(
            token_resource(&s(&[
                "https://scnetsolutions.sharepoint.com/files.readwrite.all"
            ]))
            .as_deref(),
            Some("https://scnetsolutions.sharepoint.com/.default")
        );
        assert_eq!(
            token_resource(&s(&[
                "https://pushchannel.1drv.ms/pushchannel.readwrite.all"
            ]))
            .as_deref(),
            Some("https://pushchannel.1drv.ms/.default")
        );
        assert_eq!(
            token_resource(&s(&["https://augloop.office.com/v2/.default"])).as_deref(),
            Some("https://augloop.office.com/v2/.default")
        );
        assert_eq!(
            token_resource(&s(&["user.read"])).as_deref(),
            Some("https://graph.microsoft.com/.default")
        );
        assert_eq!(
            token_resource(&s(&["Organization.Read.All"])).as_deref(),
            Some("https://graph.microsoft.com/.default")
        );
        assert_eq!(
            token_resource(&s(&["https://substrate.office.com/Files.ReadWrite.Shared"])).as_deref(),
            Some("https://substrate.office.com/.default")
        );
        // Nothing else, and never two resources at once.
        assert_eq!(
            token_resource(&s(&["https://outlook.office.com/.default"])),
            None
        );
        assert_eq!(token_resource(&s(&["https://evil.example/x"])), None);
        assert_eq!(token_resource(&s(&["https://.sharepoint.com/x"])), None);
        assert_eq!(token_resource(&s(&["http://x.sharepoint.com/x"])), None);
        assert_eq!(
            token_resource(&s(&["user.read", "https://x.sharepoint.com/a"])),
            None
        );
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
        let page = fluid_settings_from(
            Some(&messaging),
            Some(&json!({ "sizeLimitEnabled": true })),
            Kind::ChannelPage,
        );
        assert_eq!(
            page["viewProperties"],
            json!({ "compactMargins": false, "viewType": "Large", "layoutMode": "fixedByHost", "visualSpacingTop": 12,
                                                    "narrowVisualSpacingLeft": 28, "narrowVisualSpacingRight": 28 })
        );
        assert_eq!(page["sizeLimitEnabled"], true);
        assert_eq!(page["sizeLimitValueBytes"], 10485760);
        assert_eq!(page["ipEnabled"], true);
        assert_eq!(
            fluid_settings_from(None, None, Kind::ChannelPage)["viewProperties"]["layoutMode"],
            "fixedByHost"
        );
    }

    #[test]
    fn channel_folders_are_found_in_their_library() {
        // OST test channel (2026-11-16): the page went to
        // items/root:/%2FOST%20test%20channel/Loop%20paragraph.loop.
        assert_eq!(
            folder_in_library(
                "/sites/OSTTestTeam/Shared Documents/OST test channel",
                "/sites/OSTTestTeam/Shared Documents"
            )
            .as_deref(),
            Some("OST test channel")
        );
        assert_eq!(
            folder_in_library(
                "/sites/OSTTestTeam/Shared Documents/General/",
                "/sites/OSTTestTeam/Shared Documents/"
            )
            .as_deref(),
            Some("General")
        );
        assert_eq!(
            folder_in_library(
                "/sites/Other/Shared Documents/X",
                "/sites/OSTTestTeam/Shared Documents"
            ),
            None
        );
        assert_eq!(
            folder_in_library(
                "/sites/OSTTestTeam/Shared Documents",
                "/sites/OSTTestTeam/Shared Documents"
            ),
            None
        );
        assert_eq!(
            site_path_of("/sites/OSTTestTeam/Shared Documents/OST test channel").as_deref(),
            Some("/sites/OSTTestTeam")
        );
        assert_eq!(
            site_path_of("/teams/T-Private/Shared Documents/P").as_deref(),
            Some("/teams/T-Private")
        );
        assert_eq!(site_path_of("/Shared Documents"), None);
        assert_eq!(
            percent_decode("/sites/OSTTestTeam/Shared%20Documents"),
            "/sites/OSTTestTeam/Shared Documents"
        );
    }
}
