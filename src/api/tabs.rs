//! A channel's tabs as Teams desktop has them (docs/spec/channel-tabs.md):
//! the middle tier's pinned tabs (as Teams reads them, which includes the
//! channel Page), each tab's kind, its menu (order, visibility and
//! disabled states as Teams computes them), Teams' order algorithm for
//! moves, and rename / remove / copy link through the same services.

use std::collections::HashMap;
use std::sync::Mutex;

use anyhow::{Context, Result, bail};
use serde::Serialize;

use super::client::TeamsClient;

/// Files (Shared): a predefined StaticExtensionTab.
pub const FILES_APP: &str = "3ed5b337-c2c9-4d5d-b7b4-84ff09a8fc1c";
/// Channel Pages (Loop).
pub const PAGES_APP: &str = "5ae80e49-7ada-461a-a6bd-c5df2e0cdb06";
/// Website tabs.
pub const WEB_APP: &str = "com.microsoft.teamspace.tab.web";

/// The kinds of tab whose menus differ (Teams' `__typename`s).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Kind {
    /// Posts: no menu.
    Posts,
    /// Files (Shared): predefined static app tab.
    StaticExtension,
    /// A real channel Page.
    ChannelPage,
    Website,
    /// An app tab (the current Notes app is one).
    Extension,
    /// A legacy OneNote tab (settings with a section URL).
    OneNote,
}

/// One entry of a tab's menu.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct MenuItem {
    /// Teams' key: popOut, expandTab, reloadTab, goToWebsite, copyLink,
    /// renameTab, updateTab, devicePermissions, aboutTab, moveLeft,
    /// moveRight, removeTab, or divider.
    pub key: &'static str,
    pub label: &'static str,
    pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Tab {
    /// The pinned tab id (`tab::<guid>`), or the app id for Files.
    pub id: String,
    pub name: String,
    pub app_id: String,
    pub kind: Kind,
    pub entity_id: String,
    /// Where the tab's content lives, placeholders filled (for native
    /// views to identify it; never loaded as a page).
    pub content_url: String,
    /// What Open in browser opens (https only; empty when none).
    pub website_url: String,
    pub order: f64,
    pub draggable: bool,
    /// Teams opens website tabs in the browser (enableDeprecateWebsiteTab,
    /// on in Teams): clicking one opens `website_url` and never selects it.
    pub opens_in_browser: bool,
    /// The chevron menu of the selected tab.
    pub menu: Vec<MenuItem>,
    /// The right-click menu.
    pub context_menu: Vec<MenuItem>,
}

/// What a tab's URLs may be told about where they are, as Teams fills
/// their `{placeholders}`.
#[derive(Debug, Clone, Default)]
pub struct TabContext {
    pub tenant: String,
    pub upn: String,
    pub team: String,
    pub channel: String,
    pub channel_name: String,
}

/// Fill a URL's `{name}` placeholders as Teams does (URL-encoded); unknown
/// ones become empty.
fn fill(url: &str, ctx: &TabContext, entity_id: &str) -> String {
    let enc = |v: &str| url::form_urlencoded::byte_serialize(v.as_bytes()).collect::<String>();
    let mut out = String::new();
    let mut rest = url;
    while let Some(i) = rest.find('{') {
        let Some(j) = rest[i..].find('}') else { break };
        out.push_str(&rest[..i]);
        let value = match &rest[i + 1..i + j] {
            "locale" => "en-us",
            "tid" | "tenantId" => &ctx.tenant,
            "upn" | "userPrincipalName" | "loginHint" => &ctx.upn,
            "groupId" | "teamId" => &ctx.team,
            "channelId" => &ctx.channel,
            "channelName" => &ctx.channel_name,
            "entityId" => entity_id,
            "theme" => "default",
            _ => "",
        };
        out.push_str(&enc(value));
        rest = &rest[i + j + 1..];
    }
    out.push_str(rest);
    out
}

fn https_only(url: &str) -> String {
    if !url.contains('{') && reqwest::Url::parse(url).is_ok_and(|u| u.scheme() == "https") {
        url.to_string()
    } else {
        String::new()
    }
}

/// A tab's kind, from its app (Teams' app id → tab kind table).
fn kind_of(app_id: &str, id: &str) -> Kind {
    match app_id {
        FILES_APP if id == FILES_APP => Kind::StaticExtension,
        PAGES_APP => Kind::ChannelPage,
        WEB_APP => Kind::Website,
        "com.microsoft.teamspace.tab.notes" => Kind::OneNote,
        _ => Kind::Extension,
    }
}

/// A tab's menus, as Teams builds them (`We` plus its `c` / `m` filters,
/// channel entry point, desktop host). `can_update` is the channel's
/// isAllowedToUpdateTabs; `device_permissions` whether the tab's app
/// declares any; `can_left` / `can_right` whether it can move.
pub fn menus(
    kind: Kind,
    can_update: bool,
    device_permissions: bool,
    can_left: bool,
    can_right: bool,
) -> (Vec<MenuItem>, Vec<MenuItem>) {
    use Kind::*;
    if kind == Posts {
        return (Vec::new(), Vec::new());
    }
    let item = |key, label| MenuItem {
        key,
        label,
        enabled: true,
    };
    let divider = || MenuItem {
        key: "divider",
        label: "",
        enabled: true,
    };
    // Per item: the tab kinds that keep it (module 542104).
    let reload_expand = matches!(kind, StaticExtension | Extension | Website | OneNote);
    let popout = matches!(kind, Extension | ChannelPage);
    let copy_link = matches!(kind, Extension | Website | OneNote | ChannelPage);
    let rename = can_update && matches!(kind, Website | Extension | ChannelPage);
    let remove = can_update && matches!(kind, Website | Extension | OneNote | ChannelPage);
    let about = matches!(kind, Extension | Website | OneNote);
    let website = matches!(kind, Extension | Website | OneNote);
    let perms = device_permissions && matches!(kind, Extension | StaticExtension);
    let mut all: Vec<(MenuItem, bool)> = Vec::new();
    let mut push = |m: MenuItem, submenu_only: bool, keep: bool| {
        if keep {
            all.push((m, submenu_only));
        }
    };
    push(item("popOut", "Open tab in new window"), false, popout);
    push(item("expandTab", "Expand tab"), true, reload_expand);
    push(item("reloadTab", "Reload tab"), true, reload_expand);
    push(item("goToWebsite", "Open in browser"), false, website);
    push(item("copyLink", "Copy link to tab"), false, copy_link);
    // The divider before Rename shows with Rename (ConfigDivider).
    push(divider(), false, rename);
    push(item("renameTab", "Rename"), false, rename);
    push(item("devicePermissions", "App permissions"), false, perms);
    push(item("aboutTab", "About this tab"), false, about);
    push(
        MenuItem {
            key: "moveLeft",
            label: "Move left",
            enabled: can_left,
        },
        false,
        true,
    );
    push(
        MenuItem {
            key: "moveRight",
            label: "Move right",
            enabled: can_right,
        },
        false,
        true,
    );
    push(divider(), false, remove);
    push(item("removeTab", "Remove"), false, remove);
    let menu = all.iter().map(|(m, _)| m.clone()).collect();
    let context = all
        .iter()
        .filter(|(_, s)| !s)
        .map(|(m, _)| m.clone())
        .collect();
    (menu, context)
}

/// Teams' tab order constants (worker module 61009).
const WALL: f64 = 100_000.0;
const GAP: f64 = 10_000.0;
const MIN_GAP: f64 = 50.0;

fn mid(mut a: f64, b: f64) -> f64 {
    if a < WALL && b > WALL {
        a = WALL;
    }
    let c = (a + b) / 2.0;
    let f = c.floor();
    if f > a { f } else { c }
}

/// The order Teams gives tab `i` of `orders` (the list after the move,
/// the moved tab at `i`; worker module 80574).
pub fn new_order(i: usize, orders: &[f64]) -> f64 {
    let n = orders.len();
    if i == 0 && n == 1 {
        WALL + GAP
    } else if i == 0 {
        let r = orders[1];
        if r > WALL {
            mid(WALL, r)
        } else {
            mid(0.0, r).max(r - MIN_GAP)
        }
    } else if i == n - 1 {
        orders[i - 1].max(WALL) + GAP
    } else {
        mid(orders[i - 1], orders[i + 1])
    }
}

/// djb2 as Teams computes it (module 428148: JS int32 shifts, uint32 result).
fn djb2(s: &str) -> u32 {
    let mut u: f64 = 5381.0;
    for c in s.encode_utf16() {
        let shifted = ((u as i64 as i32) << 5) as f64;
        u = shifted + u + c as f64;
    }
    (u as i64) as u32
}

/// Copy link to tab, as Teams builds it (module 137308): the link, and the
/// HTML that carries the tab's name.
pub fn copy_link(tab: &Tab, channel_id: &str, group_id: &str, tenant_id: &str) -> (String, String) {
    let enc = encode_uri_component;
    let path = if tab.entity_id.is_empty() {
        format!("channel/{}/{}", enc(channel_id), enc(&tab.id))
    } else {
        let key = format!("{}:{}", tab.app_id, tab.entity_id.replace('+', " "));
        format!("entity/{}/_djb2_msteams_prefix_{}", tab.app_id, djb2(&key))
    };
    // JSON.stringify({subEntityId: undefined, channelId}) drops the
    // undefined key.
    let context = format!("{{\"channelId\":{}}}", serde_json::Value::from(channel_id));
    let mut query = vec![format!("context={}", enc(&context))];
    if !group_id.is_empty() {
        query.push(format!("groupId={group_id}"));
    }
    if !tenant_id.is_empty() {
        query.push(format!("tenantId={tenant_id}"));
    }
    let link = format!("https://teams.microsoft.com/l/{path}?{}", query.join("&"));
    let esc = |s: &str| {
        s.replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
            .replace('\'', "&#39;")
    };
    let html = format!(
        "<div><a href=\"{}\" title=\"{}\" data-origin-known=\"true\">{}</a></div>",
        esc(&link),
        esc(&link),
        esc(&tab.name)
    );
    (link, html)
}

/// JavaScript's encodeURIComponent (leaves `A-Z a-z 0-9 - _ . ! ~ * ' ( )`).
fn encode_uri_component(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A channel thread id, checked before it reaches a URL path.
fn check_channel(channel_id: &str) -> Result<()> {
    let ok = channel_id.starts_with("19:")
        && channel_id.len() < 200
        && channel_id[3..]
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.@=".contains(&b));
    if ok { Ok(()) } else { bail!("Not a channel") }
}

/// A pinned tab id (`tab::<guid>`), checked.
fn check_tab(id: &str) -> Result<()> {
    let guid = id.strip_prefix("tab::").unwrap_or("");
    if uuid::Uuid::parse_str(guid).is_ok() {
        Ok(())
    } else {
        bail!("Not a tab")
    }
}

async fn middle_tier(client: &TeamsClient) -> Result<(String, String)> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    Ok((base, token))
}

/// The middle tier's pinned tabs of a channel (Teams' GetPinnedTabs).
async fn pinned(client: &TeamsClient, channel_id: &str) -> Result<Vec<serde_json::Value>> {
    check_channel(channel_id)?;
    let (base, token) = middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .get(format!("{base}/v1.0/channels/{channel_id}/tabs"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let mut tabs = v
        .get("value")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    tabs.sort_by(|a, b| order_of(a).total_cmp(&order_of(b)));
    Ok(tabs)
}

fn order_of(t: &serde_json::Value) -> f64 {
    t.get("order").and_then(|o| o.as_f64()).unwrap_or(f64::MAX)
}

fn str_at(t: &serde_json::Value, p: &str) -> String {
    t.pointer(p)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

/// Whether an app declares device permissions (middle tier app
/// definitions, cached for the session).
async fn declares_device_permissions(client: &TeamsClient, app_id: &str) -> bool {
    static CACHE: Mutex<Option<HashMap<String, bool>>> = Mutex::new(None);
    if let Some(v) = CACHE
        .lock()
        .ok()
        .and_then(|c| c.as_ref()?.get(app_id).copied())
    {
        return v;
    }
    let Ok((base, token)) = middle_tier(client).await else {
        return false;
    };
    let enc: String = url::form_urlencoded::byte_serialize(app_id.as_bytes()).collect();
    let v = async {
        let d: serde_json::Value = client
            .http()
            .get(format!("{base}/beta/users/apps/definitions/{enc}"))
            .bearer_auth(&token)
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json()
            .await
            .ok()?;
        Some(
            d.get("devicePermissions")
                .and_then(|p| p.as_array())
                .is_some_and(|p| !p.is_empty()),
        )
    }
    .await
    .unwrap_or(false);
    if let Ok(mut c) = CACHE.lock() {
        c.get_or_insert_with(HashMap::new)
            .insert(app_id.to_string(), v);
    }
    v
}

/// What About this tab shows (Teams' About dialog: the app's name, icon,
/// description, developer, and privacy / terms links), from the middle
/// tier's app definition.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct AppAbout {
    pub name: String,
    pub icon: String,
    pub description: String,
    pub developer: String,
    pub developer_url: String,
    pub privacy_url: String,
    pub terms_url: String,
    /// Not full trust: Teams lists the identity information it gets.
    pub needs_identity: bool,
}

/// An app's description as Teams shows it (module 160381: markdown-it's
/// "zero" profile with link, emphasis, list, newline and escape, each line
/// its own block), as Qt rich text: runs of text lines joined by line
/// breaks, "- " / "* " / "+ " lines as a list, `[text](https://…)` links and
/// `*` / `**` emphasis; everything else escaped.
pub fn description_html(md: &str) -> String {
    fn esc(s: &str) -> String {
        s.replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
    }
    fn inline(s: &str) -> String {
        let mut out = String::new();
        let mut rest = s;
        while !rest.is_empty() {
            if let Some(stripped) = rest.strip_prefix('\\')
                && let Some(c) = stripped.chars().next().filter(|c| c.is_ascii_punctuation())
            {
                out.push_str(&esc(&c.to_string()));
                rest = &stripped[c.len_utf8()..];
                continue;
            }
            if rest.starts_with('[')
                && let Some(close) = rest.find("](")
                && let Some(end) = rest[close + 2..].find(')')
                && rest[close + 2..].starts_with("https://")
            {
                let text = &rest[1..close];
                let url = &rest[close + 2..close + 2 + end];
                out.push_str(&format!("<a href=\"{}\">{}</a>", esc(url), esc(text)));
                rest = &rest[close + 3 + end..];
                continue;
            }
            let emphasis = [("**", "b"), ("*", "i")]
                .into_iter()
                .find_map(|(mark, tag)| {
                    let body = rest.strip_prefix(mark)?;
                    let end = body.find(mark).filter(|&e| e > 0)?;
                    Some((
                        format!("<{tag}>{}</{tag}>", esc(&body[..end])),
                        &body[end + mark.len()..],
                    ))
                });
            if let Some((html, after)) = emphasis {
                out.push_str(&html);
                rest = after;
                continue;
            }
            let c = rest.chars().next().unwrap_or_default();
            out.push_str(&esc(&c.to_string()));
            rest = &rest[c.len_utf8()..];
        }
        out
    }
    let mut html = String::new();
    let mut text: Vec<String> = Vec::new();
    let mut items: Vec<String> = Vec::new();
    let flush_text = |html: &mut String, text: &mut Vec<String>| {
        if !text.is_empty() {
            html.push_str(&format!("<p>{}</p>", text.join("<br/>")));
            text.clear();
        }
    };
    let flush_items = |html: &mut String, items: &mut Vec<String>| {
        if !items.is_empty() {
            html.push_str("<ul>");
            for i in items.drain(..) {
                html.push_str(&format!("<li>{i}</li>"));
            }
            html.push_str("</ul>");
        }
    };
    for line in md.lines() {
        let l = line.trim();
        if l.is_empty() {
            flush_text(&mut html, &mut text);
            flush_items(&mut html, &mut items);
        } else if let Some(item) = ["- ", "* ", "+ "].iter().find_map(|m| l.strip_prefix(m)) {
            flush_text(&mut html, &mut text);
            items.push(inline(item));
        } else {
            flush_items(&mut html, &mut items);
            text.push(inline(l));
        }
    }
    flush_text(&mut html, &mut text);
    flush_items(&mut html, &mut items);
    html
}

pub fn about_from(d: &serde_json::Value) -> AppAbout {
    let s = |k: &str| https_only(d.get(k).and_then(|v| v.as_str()).unwrap_or_default());
    let t = |k: &str| {
        d.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    AppAbout {
        name: t("name"),
        icon: s("largeImageUrl"),
        description: description_html(&t("longDescription")),
        developer: t("developerName"),
        developer_url: s("developerUrl"),
        privacy_url: s("privacyUrl"),
        terms_url: s("termsOfUseUrl"),
        needs_identity: !d
            .get("isFullTrust")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
    }
}

/// An app's definition from the middle tier (Teams' GetAppDefinition).
pub async fn app_about(client: &TeamsClient, app_id: &str) -> Result<AppAbout> {
    let (base, token) = middle_tier(client).await?;
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
    Ok(about_from(&d))
}

/// Whether the signed-in user may change the channel's tabs (Teams'
/// isAllowedToUpdateTabs for a standard channel: owners yes, guests no,
/// members per the team's "create, update and remove tabs" setting; never
/// in an archived team).
async fn can_update_tabs(client: &TeamsClient, team_id: &str) -> bool {
    let team: Option<serde_json::Value> = async {
        client
            .graph_get(&format!(
                "/teams/{team_id}?$select=isArchived,memberSettings"
            ))
            .await
            .ok()?
            .json()
            .await
            .ok()
    }
    .await;
    let Some(team) = team else { return false };
    if team
        .get("isArchived")
        .and_then(|a| a.as_bool())
        .unwrap_or(false)
    {
        return false;
    }
    let me = client.object_id().unwrap_or_default();
    let owner = async {
        let v: serde_json::Value = client
            .graph_get(&format!("/groups/{team_id}/owners?$select=id&$top=999"))
            .await
            .ok()?
            .json()
            .await
            .ok()?;
        Some(
            v.get("value")?
                .as_array()?
                .iter()
                .any(|o| o.get("id").and_then(|i| i.as_str()) == Some(me.as_str())),
        )
    }
    .await
    .unwrap_or(false);
    owner
        || team
            .pointer("/memberSettings/allowCreateUpdateRemoveTabs")
            .and_then(|a| a.as_bool())
            .unwrap_or(false)
}

/// The tabs of a channel in Teams' order: Posts, then the pinned tabs
/// (Files as Shared first), with their menus.
pub async fn channel_tabs(
    client: &TeamsClient,
    team_id: &str,
    channel_id: &str,
    channel_name: &str,
) -> Result<Vec<Tab>> {
    if uuid::Uuid::parse_str(team_id).is_err() {
        bail!("Not a team");
    }
    let pinned = pinned(client, channel_id).await?;
    let can_update = can_update_tabs(client, team_id).await;
    let ctx = TabContext {
        tenant: client.tenant_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
        team: team_id.to_string(),
        channel: channel_id.to_string(),
        channel_name: channel_name.to_string(),
    };
    let mut perms = HashMap::new();
    for t in &pinned {
        let app = str_at(t, "/appId");
        if let std::collections::hash_map::Entry::Vacant(e) = perms.entry(app) {
            let p = declares_device_permissions(client, e.key()).await;
            e.insert(p);
        }
    }
    Ok(tabs_from(&pinned, &ctx, can_update, &perms))
}

fn tabs_from(
    pinned: &[serde_json::Value],
    ctx: &TabContext,
    can_update: bool,
    perms: &HashMap<String, bool>,
) -> Vec<Tab> {
    let mut tabs = vec![Tab {
        id: "com.microsoft.channeltabs.posts".into(),
        name: "Posts".into(),
        app_id: "com.microsoft.channeltabs.posts".into(),
        kind: Kind::Posts,
        entity_id: String::new(),
        content_url: String::new(),
        website_url: String::new(),
        order: 1.0,
        draggable: false,
        opens_in_browser: false,
        menu: Vec::new(),
        context_menu: Vec::new(),
    }];
    for t in pinned {
        let id = str_at(t, "/id");
        let app_id = str_at(t, "/appId");
        let kind = kind_of(&app_id, &id);
        let entity_id = str_at(t, "/configuration/entityId");
        let files = kind == Kind::StaticExtension;
        tabs.push(Tab {
            name: if files {
                "Shared".into()
            } else {
                str_at(t, "/name")
            },
            content_url: fill(&str_at(t, "/configuration/contentUrl"), ctx, &entity_id),
            website_url: https_only(&fill(
                &str_at(t, "/configuration/websiteUrl"),
                ctx,
                &entity_id,
            )),
            order: if files { 2.0 } else { order_of(t) },
            draggable: !files,
            opens_in_browser: kind == Kind::Website,
            menu: Vec::new(),
            context_menu: Vec::new(),
            id,
            app_id,
            kind,
            entity_id: if files { String::new() } else { entity_id },
        });
    }
    tabs.sort_by(|a, b| a.order.total_cmp(&b.order));
    // Moves: not for fixed tabs; the first movable tab can't go left, the
    // last can't go right.
    let movable: Vec<usize> = (0..tabs.len()).filter(|&i| tabs[i].draggable).collect();
    for (i, tab) in tabs.iter_mut().enumerate() {
        let pos = movable.iter().position(|&m| m == i);
        let can_left = pos.is_some_and(|p| p > 0);
        let can_right = pos.is_some_and(|p| p + 1 < movable.len());
        let device = perms.get(&tab.app_id).copied().unwrap_or(false);
        let (menu, context) = menus(tab.kind, can_update, device, can_left, can_right);
        tab.menu = menu;
        tab.context_menu = context;
    }
    tabs
}

/// Move a tab one place left or right among the movable tabs, as Teams
/// does: only the moved tab gets a new order (Teams' algorithm), saved
/// with one UpdatePinnedTabs PATCH.
pub async fn move_tab(
    client: &TeamsClient,
    channel_id: &str,
    tab: &str,
    right: bool,
) -> Result<()> {
    check_tab(tab)?;
    let mut tabs: Vec<serde_json::Value> = pinned(client, channel_id)
        .await?
        .into_iter()
        .filter(|t| str_at(t, "/appId") != FILES_APP)
        .collect();
    let i = tabs
        .iter()
        .position(|t| str_at(t, "/id") == tab)
        .context("No such tab")?;
    let j = if right { Some(i + 1) } else { i.checked_sub(1) }
        .filter(|j| *j < tabs.len())
        .context("The tab is already at that end")?;
    let moved = tabs.remove(i);
    tabs.insert(j, moved);
    let orders: Vec<f64> = tabs.iter().map(order_of).collect();
    let mut changed = tabs[j].clone();
    changed["order"] = serde_json::json!(new_order(j, &orders));
    patch_pinned(client, channel_id, &[changed]).await
}

async fn patch_pinned(
    client: &TeamsClient,
    channel_id: &str,
    tabs: &[serde_json::Value],
) -> Result<()> {
    check_channel(channel_id)?;
    let (base, token) = middle_tier(client).await?;
    client
        .http()
        .patch(format!("{base}/beta/channels/{channel_id}/tabs"))
        .bearer_auth(&token)
        .json(&tabs)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// Why a new tab name can't be used, as Teams' Rename dialog says it
/// (none when it can).
pub fn rename_error(name: &str, others: &[String]) -> Option<&'static str> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        Some("Name is required")
    } else if name.chars().count() > 128 {
        Some("Tab name cannot exceed 128 characters.")
    } else if others
        .iter()
        .any(|o| o.trim().to_lowercase() == trimmed.to_lowercase())
    {
        Some("You already have a tab with that name. Try a different one.")
    } else {
        None
    }
}

/// Rename a tab, as Teams saves it (UpdatePinnedTabs with the new name).
pub async fn rename(client: &TeamsClient, channel_id: &str, tab: &str, name: &str) -> Result<()> {
    check_tab(tab)?;
    let tabs = pinned(client, channel_id).await?;
    let others: Vec<String> = tabs
        .iter()
        .filter(|t| str_at(t, "/id") != tab)
        .map(|t| str_at(t, "/name"))
        .collect();
    if let Some(e) = rename_error(name, &others) {
        bail!(e);
    }
    let mut t = tabs
        .into_iter()
        .find(|t| str_at(t, "/id") == tab)
        .context("No such tab")?;
    t["name"] = serde_json::json!(name.trim());
    patch_pinned(client, channel_id, &[t]).await
}

/// Remove a tab, as Teams does (DeletePinnedTab).
pub async fn remove(client: &TeamsClient, channel_id: &str, tab: &str) -> Result<()> {
    check_channel(channel_id)?;
    check_tab(tab)?;
    let (base, token) = middle_tier(client).await?;
    let id: String = url::form_urlencoded::byte_serialize(tab.as_bytes()).collect();
    client
        .http()
        .delete(format!("{base}/beta/channels/{channel_id}/tabs/{id}"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(m: &[MenuItem]) -> Vec<String> {
        m.iter()
            .map(|i| {
                if i.enabled {
                    i.key.to_string()
                } else {
                    format!("{}(off)", i.key)
                }
            })
            .collect()
    }

    /// The menus Windows Teams showed for OST Test Team › General
    /// (read from the live client, 2026-11-06).
    #[test]
    fn menus_match_the_live_client() {
        let pinned = vec![
            serde_json::json!({"id": FILES_APP, "appId": FILES_APP, "name": "Files", "order": 2.0,
                "configuration": {"entityId": "FileBrowserTabApp"}}),
            serde_json::json!({"id": "tab::d7c1b5c5-6d6a-4f5e-8a3e-1f2b3c4d5e6f", "appId": "0d820ecd-def2-4297-adad-78056cde7c78",
                "name": "Notes", "order": 10000.0, "configuration": {"entityId": "NOTES",
                "contentUrl": "https://www.onenote.com/teams/ChannelNotes?groupId={groupId}"}}),
            serde_json::json!({"id": "tab::a62a7cb0-4528-4db8-958e-c6a5ce6b364e", "appId": PAGES_APP,
                "name": "Page", "order": 10.0, "configuration": {}}),
        ];
        let perms = HashMap::from([("0d820ecd-def2-4297-adad-78056cde7c78".to_string(), true)]);
        let t = tabs_from(&pinned, &TabContext::default(), true, &perms);
        let names: Vec<_> = t.iter().map(|t| t.name.as_str()).collect();
        assert_eq!(names, ["Posts", "Shared", "Page", "Notes"]);
        assert!(t[0].menu.is_empty() && t[0].context_menu.is_empty());
        assert_eq!(
            keys(&t[1].menu),
            ["expandTab", "reloadTab", "moveLeft(off)", "moveRight(off)"]
        );
        assert_eq!(
            keys(&t[1].context_menu),
            ["moveLeft(off)", "moveRight(off)"]
        );
        assert_eq!(
            keys(&t[2].menu),
            [
                "popOut",
                "copyLink",
                "divider",
                "renameTab",
                "moveLeft(off)",
                "moveRight",
                "divider",
                "removeTab"
            ]
        );
        assert_eq!(t[2].menu, t[2].context_menu);
        assert_eq!(
            keys(&t[3].menu),
            [
                "popOut",
                "expandTab",
                "reloadTab",
                "goToWebsite",
                "copyLink",
                "divider",
                "renameTab",
                "devicePermissions",
                "aboutTab",
                "moveLeft",
                "moveRight(off)",
                "divider",
                "removeTab"
            ]
        );
        assert_eq!(
            keys(&t[3].context_menu),
            [
                "popOut",
                "goToWebsite",
                "copyLink",
                "divider",
                "renameTab",
                "devicePermissions",
                "aboutTab",
                "moveLeft",
                "moveRight(off)",
                "divider",
                "removeTab"
            ]
        );
        // Without update rights: no Rename / Remove (nor their dividers).
        let t = tabs_from(&pinned, &TabContext::default(), false, &perms);
        assert_eq!(
            keys(&t[2].menu),
            ["popOut", "copyLink", "moveLeft(off)", "moveRight"]
        );
    }

    #[test]
    fn moves_use_teams_order_algorithm() {
        // Between neighbours: the floored midpoint.
        assert_eq!(new_order(1, &[10.0, 0.0, 10000.0]), 5005.0);
        // Crossing the wall: the left side counts as the wall.
        assert_eq!(new_order(1, &[10.0, 0.0, 120000.0]), 110000.0);
        // To the end: past the wall by a gap.
        assert_eq!(new_order(1, &[10000.0, 0.0]), 110000.0);
        assert_eq!(new_order(1, &[130000.0, 0.0]), 140000.0);
        // To the front: half the right neighbour, at most a minimum gap below it.
        assert_eq!(new_order(0, &[0.0, 10.0]), 5.0);
        assert_eq!(new_order(0, &[0.0, 10000.0]), 9950.0);
        assert_eq!(new_order(0, &[0.0, 120000.0]), 110000.0);
        assert_eq!(new_order(0, &[0.0]), 110000.0);
    }

    #[test]
    fn rename_errors_are_teams_own() {
        let others = vec!["Notes".to_string(), "Page".to_string()];
        assert_eq!(rename_error("  ", &others), Some("Name is required"));
        assert_eq!(
            rename_error(&"x".repeat(129), &others),
            Some("Tab name cannot exceed 128 characters.")
        );
        assert_eq!(
            rename_error(" notes ", &others),
            Some("You already have a tab with that name. Try a different one.")
        );
        assert_eq!(rename_error("Plans", &others), None);
    }

    #[test]
    fn copy_link_is_teams_deep_link() {
        // djb2 as JS computes it (int32 shift, uint32 result).
        assert_eq!(djb2(""), 5381);
        assert_eq!(djb2("a"), 177670);
        let mut tab = Tab {
            id: "tab::a62a7cb0-4528-4db8-958e-c6a5ce6b364e".into(),
            name: "Page <1>".into(),
            app_id: PAGES_APP.into(),
            kind: Kind::ChannelPage,
            entity_id: String::new(),
            content_url: String::new(),
            website_url: String::new(),
            order: 10.0,
            draggable: true,
            opens_in_browser: false,
            menu: Vec::new(),
            context_menu: Vec::new(),
        };
        let (link, html) = copy_link(&tab, "19:ab@thread.tacv2", "g-1", "t-1");
        assert_eq!(
            link,
            "https://teams.microsoft.com/l/channel/19%3Aab%40thread.tacv2/tab%3A%3Aa62a7cb0-4528-4db8-958e-c6a5ce6b364e?context=%7B%22channelId%22%3A%2219%3Aab%40thread.tacv2%22%7D&groupId=g-1&tenantId=t-1"
        );
        assert!(html.ends_with(">Page &lt;1&gt;</a></div>"));
        tab.entity_id = "NOTES".into();
        tab.app_id = "0d820ecd-def2-4297-adad-78056cde7c78".into();
        let (link, _) = copy_link(&tab, "19:ab@thread.tacv2", "", "");
        assert!(link.starts_with(&format!(
            "https://teams.microsoft.com/l/entity/0d820ecd-def2-4297-adad-78056cde7c78/_djb2_msteams_prefix_{}?",
            djb2("0d820ecd-def2-4297-adad-78056cde7c78:NOTES")
        )));
    }

    #[test]
    fn descriptions_render_as_teams_does() {
        let d = "Intro line.\nSecond line:\n- One *a*[l](https://l.example)\n- Two **b**\nAfter [here](https://x.example/p) and [bad](http://x) \\* <b>.";
        assert_eq!(
            description_html(d),
            "<p>Intro line.<br/>Second line:</p><ul><li>One <i>a</i><a href=\"https://l.example\">l</a></li><li>Two <b>b</b></li></ul>\
             <p>After <a href=\"https://x.example/p\">here</a> and [bad](http://x) * &lt;b&gt;.</p>"
        );
    }

    #[test]
    fn about_comes_from_the_app_definition() {
        let d = serde_json::json!({"name": "OneNote", "largeImageUrl": "https://res.cdn.office.net/x.png",
            "longDescription": "**Notes**", "developerName": "Microsoft Corporation",
            "developerUrl": "https://www.onenote.com/", "privacyUrl": "http://not-https/",
            "termsOfUseUrl": "https://www.microsoft.com/servicesagreement", "isFullTrust": true});
        let a = about_from(&d);
        assert_eq!(
            (a.name.as_str(), a.developer.as_str()),
            ("OneNote", "Microsoft Corporation")
        );
        assert!(a.privacy_url.is_empty(), "https only");
        assert!(!a.needs_identity);
        assert!(about_from(&serde_json::json!({})).needs_identity);
    }

    #[test]
    fn ids_are_checked_before_they_reach_a_path() {
        assert!(check_tab("tab::a62a7cb0-4528-4db8-958e-c6a5ce6b364e").is_ok());
        assert!(check_tab("a62a7cb0-4528-4db8-958e-c6a5ce6b364e").is_err());
        assert!(check_tab("tab::../x").is_err());
        assert!(check_channel("19:ab@thread.tacv2").is_ok());
        assert!(check_channel("19:a/b@thread").is_err());
    }
}
