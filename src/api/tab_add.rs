//! Adding a tab, as Teams desktop does it (docs/spec/add-a-tab.md):
//! the "+" picker (Teams' in-context Store with the Tab capability), the
//! Website tab's configuration, and the chat service thread properties
//! (`tab::{guid}`) that hold a chat's or a channel's tabs. Captured on winpc
//! 2026-11-16 adding and removing a website tab in OST group test and in
//! OST Test Team › General:
//!
//! - add: `PUT {chatsvc}/v1/threads/{thread}/properties?name=tab::{id}`
//!   with `{"tab::{id}": "<the tab as JSON>"}`; with "Post to the chat
//!   (channel) about this tab" a post that links the tab, then the same
//!   PUT with the post as the tab's `replyChainId`;
//! - remove: the same PUT with `{"tab::{id}": null}`.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

use anyhow::{Context, Result, bail};

use super::client::TeamsClient;
use super::store_content::{self, IcKind, InContext, StoreApp};
use super::tabs::{self, GAP, Kind, Tab, WALL, WEB_APP};

/// Pages, which Teams' tab picker leaves out (`filteredOutAppIds`).
const PAGES_APP: &str = tabs::PAGES_APP;

/// The text of the post that announces a new tab.
pub fn announcement(channel: bool) -> &'static str {
    if channel {
        "I added a tab at the top of this channel. Check it out!"
    } else {
        "I added a tab at the top of this chat. Check it out!"
    }
}

/// The order Teams gives a tab added after `orders` (worker module 61009:
/// `last.order > orderLeftWall ? last.order + defaultOrderGap :
/// orderLeftWall + defaultOrderGap`).
pub fn add_order(orders: &[f64]) -> f64 {
    match orders.iter().copied().reduce(f64::max) {
        Some(last) if last > WALL => last + GAP,
        _ => WALL + GAP,
    }
}

/// Why a Website tab's URL can't be saved ("That isn't a valid URL."), as
/// Teams' Website configuration judges it (tried on winpc 2026-11-16:
/// only `https://` in lower case, a host of letters, digits, dots and
/// hyphens, no spaces; `https://x` and `https://localhost` pass). An
/// empty field shows no error (Save just stays off).
pub fn website_url_error(url: &str) -> Option<&'static str> {
    const ERR: &str = "That isn't a valid URL.";
    if url.is_empty() {
        return None;
    }
    let Some(rest) = url.strip_prefix("https://") else {
        return Some(ERR);
    };
    if url.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return Some(ERR);
    }
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let (host, port) = match rest[..end].rsplit_once(':') {
        Some((h, p)) => (h, Some(p)),
        None => (&rest[..end], None),
    };
    let host_ok = !host.is_empty()
        && host.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
        && !host.starts_with('.')
        && !host.starts_with('-');
    let port_ok = port.is_none_or(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()));
    let path_ok = !rest[end..].contains(['<', '>', '"', '`', '{', '}', '|', '\\', '^']);
    if host_ok && port_ok && path_ok && reqwest::Url::parse(url).is_ok() {
        None
    } else {
        Some(ERR)
    }
}

/// Why a new tab's name can't be used (Teams' "Tab name": required, at
/// most 128 characters).
pub fn tab_name_error(name: &str) -> Option<&'static str> {
    if name.trim().is_empty() {
        Some("Name is required")
    } else if name.chars().count() > 128 {
        Some("Tab name cannot exceed 128 characters.")
    } else {
        None
    }
}

/// A number as JavaScript's JSON writes it (110000, not 110000.0).
fn js_number(n: f64) -> String {
    if n.fract() == 0.0 && n.abs() < 9e15 {
        format!("{}", n as i64)
    } else {
        serde_json::json!(n).to_string()
    }
}

/// A website tab's thread property, byte for byte as Teams writes it.
pub fn website_property(id: &str, order: f64, url: &str, date_added: &str, name: &str) -> String {
    let q = |v: &str| serde_json::Value::String(v.to_string()).to_string();
    format!(
        r#"{{"id":{id},"order":{order},"definitionId":{def},"directive":"webpage-tab","type":"tab:","settings":{{"url":{url},"websiteUrl":{url},"dateAdded":{date}}},"name":{name}}}"#,
        id = q(id),
        order = js_number(order),
        def = q(WEB_APP),
        url = q(url),
        date = q(date_added),
        name = q(name),
    )
}

/// A tab property with its post as `replyChainId` (Teams sends the same
/// JSON with the field added at the end).
pub fn append_reply_chain(property: &str, root: &str) -> Result<String> {
    let body = property.trim_end();
    let Some(open) = body.strip_suffix('}') else {
        bail!("Tab property")
    };
    serde_json::from_str::<serde_json::Value>(property).context("Tab property")?;
    Ok(format!(
        "{open},\"replyChainId\":{}}}",
        serde_json::Value::String(root.to_string())
    ))
}

/// A conversation thread id, checked before it reaches a URL path.
fn check_thread(id: &str) -> Result<()> {
    let ok = id.starts_with("19:")
        && id.len() < 200
        && id[3..]
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.@=".contains(&b));
    if ok { Ok(()) } else { bail!("Not a conversation") }
}

/// The `tab::` properties of a thread's property map, parsed, in Teams'
/// order (by `order`).
pub fn property_tabs(props: &serde_json::Value) -> Vec<serde_json::Value> {
    let mut tabs: Vec<serde_json::Value> = props
        .as_object()
        .into_iter()
        .flatten()
        .filter(|(k, _)| k.starts_with("tab::"))
        .filter_map(|(_, v)| match v {
            serde_json::Value::String(s) => serde_json::from_str(s).ok(),
            serde_json::Value::Object(_) => Some(v.clone()),
            _ => None,
        })
        .filter(|t: &serde_json::Value| t.get("id").and_then(|i| i.as_str()).is_some_and(|i| i.starts_with("tab::")))
        .collect();
    tabs.sort_by(|a, b| order_of(a).total_cmp(&order_of(b)));
    tabs
}

fn order_of(t: &serde_json::Value) -> f64 {
    t.get("order").and_then(|o| o.as_f64()).unwrap_or(f64::MAX)
}

fn str_at(t: &serde_json::Value, p: &str) -> String {
    t.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string()
}

/// A thread's properties (`GET {chatsvc}/v1/threads/{id}?view=msnp24Equivalent`).
pub async fn thread_properties(client: &TeamsClient, thread_id: &str) -> Result<serde_json::Value> {
    check_thread(thread_id)?;
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        tabs::encode_uri_component(thread_id)
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Thread")?;
    Ok(v.get("properties").cloned().unwrap_or_default())
}

/// Set (or, with `None`, clear) a thread's `tab::` property.
async fn put_property(client: &TeamsClient, thread_id: &str, tab_id: &str, value: Option<&str>) -> Result<()> {
    check_thread(thread_id)?;
    tabs::check_tab(tab_id)?;
    let url = format!(
        "{}/v1/threads/{}/properties?name={}",
        client.chat_service_url(),
        tabs::encode_uri_component(thread_id),
        tabs::encode_uri_component(tab_id)
    );
    let body = serde_json::json!({ tab_id: value });
    client.chat_request(reqwest::Method::PUT, &url, &body).await?;
    Ok(())
}

/// Remove a tab: its thread property set to null (Teams' Remove, in chats
/// and channels alike).
pub async fn remove_property(client: &TeamsClient, thread_id: &str, tab_id: &str) -> Result<()> {
    put_property(client, thread_id, tab_id, None).await
}

/// Rename a chat's tab: its thread property with the new name.
pub async fn rename_property(client: &TeamsClient, thread_id: &str, tab_id: &str, name: &str) -> Result<()> {
    let props = thread_properties(client, thread_id).await?;
    let tabs = property_tabs(&props);
    let others: Vec<String> = tabs
        .iter()
        .filter(|t| str_at(t, "/id") != tab_id)
        .map(|t| str_at(t, "/name"))
        .collect();
    if let Some(e) = tabs::rename_error(name, &others) {
        bail!(e);
    }
    let mut t = tabs
        .into_iter()
        .find(|t| str_at(t, "/id") == tab_id)
        .context("No such tab")?;
    t["name"] = serde_json::json!(name.trim());
    put_property(client, thread_id, tab_id, Some(&t.to_string())).await
}

/// A tab's thread property once its app has set its settings (TeamsJS
/// `settings.setSettings` / pages.config.setConfig from the tab's content
/// page, e.g. the channel Notes page once it has made the channel's
/// section). Teams rewrote OST test channel 2's Notes tab this way on
/// 2026-11-16: `{"id","name","definitionId","directive","tabType":"tab:",
/// "order","replyChainId","settings":{"url","websiteUrl","entityId",
/// "subtype","removeUrl"}}`, in that order, `isUnconfigured` gone.
pub fn configured_property(old: &serde_json::Value, settings: &serde_json::Value) -> String {
    #[derive(serde::Serialize)]
    struct Settings<'a> {
        url: &'a str,
        #[serde(rename = "websiteUrl")]
        website_url: &'a str,
        #[serde(rename = "entityId")]
        entity_id: &'a str,
        subtype: &'a str,
        #[serde(rename = "removeUrl")]
        remove_url: &'a str,
    }
    #[derive(serde::Serialize)]
    struct Prop<'a> {
        id: &'a str,
        name: &'a str,
        #[serde(rename = "definitionId")]
        definition_id: &'a str,
        directive: &'a str,
        #[serde(rename = "tabType")]
        tab_type: &'a str,
        order: serde_json::Value,
        #[serde(rename = "replyChainId")]
        reply_chain_id: serde_json::Value,
        settings: Settings<'a>,
    }
    let o = |p: &str| old.pointer(p).and_then(|v| v.as_str()).unwrap_or_default();
    let n = |k: &str| settings.get(k).and_then(|v| v.as_str()).unwrap_or_default();
    let order = old.get("order").and_then(|v| v.as_f64()).unwrap_or(10000.0);
    let order = if order.fract() == 0.0 { serde_json::json!(order as i64) } else { serde_json::json!(order) };
    let reply = old.get("replyChainId").cloned().filter(|v| !v.is_null()).unwrap_or(serde_json::json!(0));
    serde_json::to_string(&Prop {
        id: o("/id"),
        name: o("/name"),
        definition_id: o("/definitionId"),
        directive: o("/directive"),
        tab_type: "tab:",
        order,
        reply_chain_id: reply,
        settings: Settings {
            url: n("contentUrl"),
            website_url: n("websiteUrl"),
            entity_id: n("entityId"),
            subtype: Some(o("/settings/subtype")).filter(|s| !s.is_empty()).unwrap_or("extension"),
            remove_url: n("removeUrl"),
        },
    })
    .unwrap_or_default()
}

/// Save a tab's new settings from its app, as Teams does: the thread
/// property rewritten (see [`configured_property`]). Only https content
/// addresses are taken.
pub async fn set_settings(client: &TeamsClient, thread_id: &str, tab_id: &str, settings: &serde_json::Value) -> Result<()> {
    let url = settings.get("contentUrl").and_then(|v| v.as_str()).unwrap_or_default();
    anyhow::ensure!(url.starts_with("https://"), "The tab's address must be https");
    let props = thread_properties(client, thread_id).await?;
    let old = property_tabs(&props)
        .into_iter()
        .find(|t| str_at(t, "/id") == tab_id)
        .context("No such tab")?;
    put_property(client, thread_id, tab_id, Some(&configured_property(&old, settings))).await
}

/// A chat's own tabs (its `tab::` thread properties), with their menus:
/// the channel menus without Move left / Move right (Teams' chat tabs
/// can't be moved; a chat's website tab showed Copy link to tab, Rename,
/// About this tab and Remove on winpc).
pub async fn chat_tabs(client: &TeamsClient, chat_id: &str) -> Result<Vec<Tab>> {
    let props = thread_properties(client, chat_id).await?;
    let ctx = tabs::TabContext {
        tenant: client.tenant_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
        ..Default::default()
    };
    let mut out = Vec::new();
    for t in property_tabs(&props) {
        let mut tab = tab_from_property(&t, &ctx);
        let (perms, icon) = tabs::app_facts(client, &tab.app_id).await;
        let (menu, context) = tabs::menus(tab.kind, true, perms, false, false);
        let unmovable = |m: &Vec<tabs::MenuItem>| -> Vec<tabs::MenuItem> {
            m.iter().filter(|i| i.key != "moveLeft" && i.key != "moveRight").cloned().collect()
        };
        tab.menu = unmovable(&menu);
        tab.context_menu = unmovable(&context);
        tab.icon = icon;
        out.push(tab);
    }
    Ok(out)
}

/// A tab from its thread property (menus and icon left for the caller).
pub fn tab_from_property(t: &serde_json::Value, ctx: &tabs::TabContext) -> Tab {
    let id = str_at(t, "/id");
    let app_id = str_at(t, "/definitionId");
    let kind = tabs::kind_of(&app_id, &id);
    let entity_id = str_at(t, "/settings/entityId");
    let content = [str_at(t, "/settings/url"), str_at(t, "/settings/contentUrl")]
        .into_iter()
        .find(|u| !u.is_empty())
        .unwrap_or_default();
    Tab {
        name: str_at(t, "/name"),
        content_url: tabs::fill(&content, ctx, &entity_id),
        content_template: tabs::https_template(&content),
        website_url: tabs::https_only(&tabs::fill(&str_at(t, "/settings/websiteUrl"), ctx, &entity_id)),
        order: order_of(t),
        draggable: false,
        opens_in_browser: kind == Kind::Website,
        menu: Vec::new(),
        context_menu: Vec::new(),
        can_converse: false,
        conversation: Some(str_at(t, "/replyChainId"))
            .filter(|m| m.bytes().all(|b| b.is_ascii_digit()) && !m.is_empty())
            .unwrap_or_default(),
        icon: String::new(),
        id,
        app_id,
        kind,
        entity_id,
    }
}

/// Add a website tab to a chat or a channel, as Teams' Website
/// configuration saves it; `post` posts "I added a tab…" with the tab's
/// link and makes that post the tab's reply chain. Returns the tab's id.
pub async fn add_website(
    client: &TeamsClient,
    thread_id: &str,
    channel: bool,
    name: &str,
    url: &str,
    post: bool,
) -> Result<String> {
    if let Some(e) = tab_name_error(name) {
        bail!(e);
    }
    if url.is_empty() {
        bail!("That isn't a valid URL.");
    }
    if let Some(e) = website_url_error(url) {
        bail!(e);
    }
    let props = thread_properties(client, thread_id).await?;
    let orders: Vec<f64> = property_tabs(&props).iter().map(order_of).filter(|o| o.is_finite() && *o < f64::MAX).collect();
    let id = format!("tab::{}", uuid::Uuid::new_v4());
    let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    let name = name.trim();
    let property = website_property(&id, add_order(&orders), url, &now, name);
    put_property(client, thread_id, &id, Some(&property)).await?;
    record_used(WEB_APP);
    if post {
        let root = post_link(client, thread_id, &id, name, announcement(channel)).await?;
        put_property(client, thread_id, &id, Some(&append_reply_chain(&property, &root)?)).await?;
    }
    Ok(id)
}

/// Post `text` with the tab's link; the post's id.
async fn post_link(client: &TeamsClient, thread_id: &str, tab_id: &str, tab_name: &str, text: &str) -> Result<String> {
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .context("Not signed in")?;
    let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    let body = tabs::tab_link_post(
        thread_id,
        tab_id,
        tab_name,
        text,
        &me,
        &client.display_name().unwrap_or_default(),
        &super::outbox::new_client_message_id(),
        &now,
    );
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages",
        client.chat_service_url(),
        tabs::encode_uri_component(thread_id)
    );
    let reply: serde_json::Value = client.chat_post(&url, &body).await?.json().await.context("Post")?;
    Ok(reply
        .get("OriginalArrivalTime")
        .and_then(|v| v.as_i64())
        .context("The post has no id")?
        .to_string())
}

/// Apps used this session, newest first (Teams' `recordAppMru`, which
/// puts an app first in the picker once you've used it).
static USED: Mutex<Vec<String>> = Mutex::new(Vec::new());

fn record_used(app_id: &str) {
    if let Ok(mut u) = USED.lock() {
        u.retain(|a| !a.eq_ignore_ascii_case(app_id));
        u.insert(0, app_id.to_string());
    }
}

/// Your apps' most recently used order (`GET {mt}/beta/users/apps/usage`:
/// `appsMru[].appId`, else `appIds`), with this session's use first.
pub fn mru_from(v: &serde_json::Value) -> Vec<String> {
    let v = v.get("value").filter(|x| x.is_object()).unwrap_or(v);
    let mru: Vec<String> = v
        .get("appsMru")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .filter_map(|a| a.get("appId").and_then(|i| i.as_str()).map(str::to_string))
        .collect();
    if !mru.is_empty() {
        return mru;
    }
    ["appIds", "apps"]
        .iter()
        .find_map(|k| v.get(*k).and_then(|a| a.as_array()))
        .into_iter()
        .flatten()
        .filter_map(|a| a.as_str().map(str::to_string))
        .collect()
}

pub async fn apps_usage(client: &TeamsClient) -> Vec<String> {
    let mut out: Vec<String> = USED.lock().map(|u| u.clone()).unwrap_or_default();
    let fetched = async {
        let (base, token) = tabs::middle_tier(client).await?;
        let v: serde_json::Value = client
            .http()
            .get(format!("{base}/beta/users/apps/usage"))
            .bearer_auth(token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        anyhow::Ok(mru_from(&v))
    }
    .await
    .unwrap_or_default();
    for a in fetched {
        if !out.iter().any(|x| x.eq_ignore_ascii_case(&a)) {
            out.push(a);
        }
    }
    out
}

/// Teams' sort of the picker's apps (module 143369 `v8`): by place in
/// the most-recently-used list, the rest after in their own order.
pub fn sort_by_mru(ids: &mut [String], mru: &[String]) {
    let pos: HashMap<String, usize> = mru.iter().enumerate().map(|(i, a)| (a.to_lowercase(), i)).collect();
    ids.sort_by_key(|i| pos.get(&i.to_lowercase()).copied().unwrap_or(usize::MAX));
}

/// The states Teams' picker leaves out (module 143369 `h3`).
pub fn offered_state(state: &str) -> bool {
    !matches!(state, "NotInstalled" | "InstalledAndHidden" | "InstalledAndDeprecated" | "Featured")
}

/// Your apps and their states in Teams' order (aggregated user
/// entitlements, as `app_details::entitlements` reads them).
pub async fn your_apps(client: &TeamsClient) -> Result<Vec<(String, String)>> {
    let (base, token) = tabs::middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned"))
        .bearer_auth(token)
        .json(&serde_json::json!([]))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(v.pointer("/value/userEntitlements")
        .and_then(|u| u.as_object())
        .into_iter()
        .flat_map(|o| o.values())
        .filter_map(|l| l.as_array())
        .flatten()
        .filter_map(|e| {
            Some((
                e.get("id")?.as_str()?.to_string(),
                e.get("state").and_then(|s| s.as_str()).unwrap_or_default().to_string(),
            ))
        })
        .collect())
}

/// A conversation's app catalogue with each app's `state` there
/// (`GET {mt}/beta/chats/{thread}/apps/definitionsv2`, paged with
/// `x-ms-continuation`), kept for the session.
pub async fn conversation_apps(client: &TeamsClient, thread_id: &str) -> Result<std::sync::Arc<Vec<serde_json::Value>>> {
    static CACHE: Mutex<Option<HashMap<String, std::sync::Arc<Vec<serde_json::Value>>>>> = Mutex::new(None);
    check_thread(thread_id)?;
    if let Some(c) = CACHE.lock().ok().and_then(|c| c.as_ref()?.get(thread_id).cloned()) {
        return Ok(c);
    }
    let (base, token) = tabs::middle_tier(client).await?;
    let mut all = Vec::new();
    let mut cont: Option<String> = None;
    for _ in 0..50 {
        let mut rq = client.http().get(format!("{base}/beta/chats/{thread_id}/apps/definitionsv2")).bearer_auth(&token);
        if let Some(c) = &cont {
            rq = rq.header("x-ms-continuation", c);
        }
        let v: serde_json::Value = rq.send().await?.error_for_status().context("Conversation apps")?.json().await?;
        all.extend(v.pointer("/value/appDefinitions").and_then(|a| a.as_array()).cloned().unwrap_or_default());
        cont = v
            .pointer("/value/continuationToken")
            .and_then(|c| c.as_str())
            .filter(|c| !c.is_empty())
            .map(str::to_string);
        if cont.is_none() {
            break;
        }
    }
    let all = std::sync::Arc::new(all);
    if let Ok(mut c) = CACHE.lock() {
        c.get_or_insert_with(HashMap::new).insert(thread_id.to_string(), all.clone());
    }
    Ok(all)
}

/// App definitions (`POST {mt}/beta/users/apps/batchedDefinitions`), by
/// lowercase id.
pub async fn definitions(client: &TeamsClient, ids: &[String]) -> Result<HashMap<String, serde_json::Value>> {
    let (base, token) = tabs::middle_tier(client).await?;
    let mut out = HashMap::new();
    for chunk in ids.chunks(50) {
        let v: serde_json::Value = client
            .http()
            .post(format!("{base}/beta/users/apps/batchedDefinitions"))
            .bearer_auth(&token)
            .json(&chunk)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let list = v.get("value").cloned().unwrap_or(v);
        for d in list.as_array().into_iter().flatten() {
            if let Some(id) = d.get("id").and_then(|i| i.as_str()) {
                out.insert(id.to_lowercase(), d.clone());
            }
        }
    }
    Ok(out)
}

/// Teams' "Add a tab" picker for a chat, a meeting's chat or a channel
/// (`team_thread` for a channel's team): the grid holds your apps that have
/// a tab here, most recently used first (Pages left out); the collections
/// are the in-context Store's Tab collections without them.
pub async fn tab_store(
    client: &TeamsClient,
    kind: IcKind,
    conversation: &str,
    team_thread: Option<&str>,
) -> Result<InContext> {
    // The conversation's apps with their states here (Teams' worker asks
    // `{mt}/beta/chats/{thread}/apps/definitionsv2`, for a channel too):
    // Website and PDF are InstalledAndPermanent there though not among
    // your entitlements; apps you have only for yourself have no state.
    let conv = conversation_apps(client, conversation).await?;
    let mut apps: Vec<(String, String)> = conv
        .iter()
        .filter_map(|d| {
            let state = d.get("state").and_then(|s| s.as_str()).filter(|s| !s.is_empty() && *s != "None")?;
            Some((d.get("id")?.as_str()?.to_string(), state.to_string()))
        })
        .collect();
    if let Some(t) = team_thread
        && let Ok(team) = store_content::channel_apps(client, t).await
    {
        // The team's apps (Planner, Forms, …), those it has: not "None", and
        // not Files, which every channel has as Shared.
        for (id, state) in team {
            if state.is_empty() || state == "None" || id.eq_ignore_ascii_case(tabs::FILES_APP) {
                continue;
            }
            match apps.iter_mut().find(|(i, _)| i.eq_ignore_ascii_case(&id)) {
                Some(e) => {
                    if !offered_state(&e.1) {
                        e.1 = state
                    }
                }
                None => apps.push((id, state)),
            }
        }
    }
    let mut seen = HashSet::new();
    let mut ids: Vec<String> = apps
        .iter()
        .filter(|(id, state)| offered_state(state) && !id.eq_ignore_ascii_case(PAGES_APP) && seen.insert(id.to_lowercase()))
        .map(|(id, _)| id.clone())
        .collect();
    let mut defs: HashMap<String, serde_json::Value> = conv
        .iter()
        .filter_map(|d| Some((d.get("id")?.as_str()?.to_lowercase(), d.clone())))
        .collect();
    let missing: Vec<String> = ids.iter().filter(|i| !defs.contains_key(&i.to_lowercase())).cloned().collect();
    if !missing.is_empty() {
        defs.extend(definitions(client, &missing).await.unwrap_or_default());
    }
    ids.retain(|id| defs.get(&id.to_lowercase()).is_some_and(|d| kind.supports(d)));
    sort_by_mru(&mut ids, &apps_usage(client).await);
    let ctx = tabs::TabContext {
        tenant: client.tenant_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
        ..Default::default()
    };
    let installed: Vec<StoreApp> = ids
        .iter()
        .filter_map(|id| defs.get(&id.to_lowercase()))
        .map(|d| {
            let mut a = store_content::store_app(d, None);
            a.config_url = tabs::https_only(&tabs::fill(&a.config_url, &ctx, ""));
            a
        })
        .collect();
    let excluded: HashSet<String> = ids.iter().map(|i| i.to_lowercase()).collect();
    let (collections, _, _) = store_content::ic_collections(client, kind, &excluded).await?;
    Ok(InContext { installed, collections })
}

/// The picker's search: the Store's matches that have a tab here.
pub async fn tab_store_search(client: &TeamsClient, kind: IcKind, query: &str) -> Result<Vec<StoreApp>> {
    store_content::search_in_context(client, query, kind, &HashSet::new()).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn configured_notes_tab_is_teams_property() {
        // OST layout test's Notes before its first opening, as stored.
        let old = serde_json::json!({"name":"Notes","id":"tab::bd0832e4-b2df-4f65-9da5-93178e668f4d","definitionId":"0d820ecd-def2-4297-adad-78056cde7c78",
            "type":"tab:","settings":{"url":"https://www.onenote.com/teams/ChannelNotes?ui={locale}","websiteUrl":"https://www.onenote.com","entityId":"NOTES","subtype":"extension"},
            "directive":"extension-tab","order":10000.0,"isUnconfigured":"True"});
        let set = serde_json::json!({"entityId":"NOTES_d9d63f71","contentUrl":"https://www.microsoft365.com/launch/onenote/officeunihost/teams?locale={locale}",
            "suggestedDisplayName":"Notes","websiteUrl":"https://onenote.com/","removeUrl":""});
        assert_eq!(
            configured_property(&old, &set),
            r#"{"id":"tab::bd0832e4-b2df-4f65-9da5-93178e668f4d","name":"Notes","definitionId":"0d820ecd-def2-4297-adad-78056cde7c78","directive":"extension-tab","tabType":"tab:","order":10000,"replyChainId":0,"settings":{"url":"https://www.microsoft365.com/launch/onenote/officeunihost/teams?locale={locale}","websiteUrl":"https://onenote.com/","entityId":"NOTES_d9d63f71","subtype":"extension","removeUrl":""}}"#
        );
    }

    #[test]
    fn new_tabs_go_after_the_wall() {
        // OST group test had no tabs; General had Page (10) and Notes
        // (10000): both new website tabs got 110000.
        assert_eq!(add_order(&[]), 110_000.0);
        assert_eq!(add_order(&[10.0, 10_000.0]), 110_000.0);
        assert_eq!(add_order(&[10.0, 110_000.0]), 120_000.0);
    }

    #[test]
    fn website_urls_as_teams_judges_them() {
        for ok in ["https://example.com", "https://example", "https://x", "https://localhost", "https://example.com/x?y=1", "https://a-b.example.com:8443/p"] {
            assert_eq!(website_url_error(ok), None, "{ok}");
        }
        for bad in ["http://example", "example.com", "www.example.com", "HTTPS://example.com", "https://", "https://a b.com", "https://ex<ample.com", "https://example.com ", "https://exa%mple.com"] {
            assert_eq!(website_url_error(bad), Some("That isn't a valid URL."), "{bad}");
        }
        assert_eq!(website_url_error(""), None);
        assert_eq!(tab_name_error(" "), Some("Name is required"));
        assert_eq!(tab_name_error(&"x".repeat(129)), Some("Tab name cannot exceed 128 characters."));
        assert_eq!(tab_name_error("Website"), None);
    }

    #[test]
    fn website_property_is_teams_byte_for_byte() {
        // Captured from Teams (OST group test, 2026-11-16).
        let p = website_property(
            "tab::506f2aac-c7a2-4eb2-b232-7a948ea7c597",
            110_000.0,
            "https://example.com",
            "2026-11-16T07:55:18.702Z",
            "Website",
        );
        assert_eq!(
            p,
            r#"{"id":"tab::506f2aac-c7a2-4eb2-b232-7a948ea7c597","order":110000,"definitionId":"com.microsoft.teamspace.tab.web","directive":"webpage-tab","type":"tab:","settings":{"url":"https://example.com","websiteUrl":"https://example.com","dateAdded":"2026-11-16T07:55:18.702Z"},"name":"Website"}"#
        );
        assert_eq!(
            append_reply_chain(&p, "1794815719181").unwrap(),
            r#"{"id":"tab::506f2aac-c7a2-4eb2-b232-7a948ea7c597","order":110000,"definitionId":"com.microsoft.teamspace.tab.web","directive":"webpage-tab","type":"tab:","settings":{"url":"https://example.com","websiteUrl":"https://example.com","dateAdded":"2026-11-16T07:55:18.702Z"},"name":"Website","replyChainId":"1794815719181"}"#
        );
        assert_eq!(js_number(120_000.5), "120000.5");
    }

    #[test]
    fn the_announcement_is_teams() {
        let v = tabs::tab_link_post("19:x@thread.v2", "tab::1", "Website", announcement(false), "8:orgid:me", "OST Test 1", "1", "2026-11-16T07:55:18.994Z");
        assert_eq!(v["content"], "I added a tab at the top of this chat. Check it out!");
        assert_eq!(v["messagetype"], "Text");
        assert!(v["properties"]["files"].as_str().unwrap().contains(r#""itemid":"tab::1","fileName":"Website","fileType":"deeplink""#));
        assert_eq!(announcement(true), "I added a tab at the top of this channel. Check it out!");
    }

    #[test]
    fn chat_tabs_come_from_thread_properties() {
        let props = serde_json::json!({
            "topic": "OST group test",
            "tab::b": "{\"id\":\"tab::0bb8bcb0-d5a3-47d2-977c-692a7ca35ebc\",\"order\":120000,\"definitionId\":\"0d820ecd-def2-4297-adad-78056cde7c78\",\"type\":\"tab:\",\"settings\":{\"entityId\":\"n1\",\"contentUrl\":\"https://x/{entityId}\"},\"name\":\"Notes\"}",
            "tab::a": "{\"id\":\"tab::506f2aac-c7a2-4eb2-b232-7a948ea7c597\",\"order\":110000,\"definitionId\":\"com.microsoft.teamspace.tab.web\",\"directive\":\"webpage-tab\",\"type\":\"tab:\",\"settings\":{\"url\":\"https://example.com\",\"websiteUrl\":\"https://example.com\"},\"name\":\"Website\",\"replyChainId\":\"1794815719181\"}",
            "tab::gone": null,
        });
        let list = property_tabs(&props);
        assert_eq!(list.len(), 2);
        let ctx = tabs::TabContext::default();
        let web = tab_from_property(&list[0], &ctx);
        assert_eq!((web.name.as_str(), web.kind, web.opens_in_browser), ("Website", Kind::Website, true));
        assert_eq!(web.website_url, "https://example.com");
        assert_eq!(web.conversation, "1794815719181");
        // A chat tab's link is a chat's (module 407834).
        let (link, _) = tabs::copy_link_in(&web, "19:ef213c7c46cf4036b11608300e96fee4@thread.v2", true, "t1");
        assert_eq!(
            link,
            "https://teams.microsoft.com/l/chat/19%3Aef213c7c46cf4036b11608300e96fee4%40thread.v2/tab%3A%3A506f2aac-c7a2-4eb2-b232-7a948ea7c597?context=%7B%22chatId%22%3A%2219%3Aef213c7c46cf4036b11608300e96fee4%40thread.v2%22%2C%22contextType%22%3A%22chat%22%7D&tenantId=t1"
        );
        let notes = tab_from_property(&list[1], &ctx);
        assert_eq!((notes.kind, notes.content_url.as_str()), (Kind::Extension, "https://x/n1"));
        // A chat website tab's menu (right-click, or ">" under "+N"):
        // Copy link, Rename, About, Remove. It never becomes the open tab,
        // so it has no chevron menu.
        let (_, context) = tabs::menus(Kind::Website, true, false, false, false);
        let keys: Vec<&str> = context.iter().map(|m| m.key).filter(|k| *k != "moveLeft" && *k != "moveRight").collect();
        assert_eq!(keys, ["copyLink", "divider", "renameTab", "aboutTab", "divider", "removeTab"]);
    }

    #[test]
    fn the_picker_keeps_teams_order() {
        let mut ids: Vec<String> = ["0d820ecd", "95de633a", "com.microsoft.teamspace.tab.planner", "com.microsoft.teamspace.tab.web"].iter().map(|s| s.to_string()).collect();
        sort_by_mru(&mut ids, &["com.microsoft.teamspace.tab.web".to_string(), "95DE633A".to_string()]);
        assert_eq!(ids, ["com.microsoft.teamspace.tab.web", "95de633a", "0d820ecd", "com.microsoft.teamspace.tab.planner"]);
        assert!(!offered_state("NotInstalled") && !offered_state("InstalledAndHidden") && offered_state("PreConsented") && offered_state("InstalledAndPermanent"));
        let usage = serde_json::json!({"appIds": ["a"], "appsMru": [{"appId": "b", "lastUsedTimeStamp": "x"}, {"appId": "c"}]});
        assert_eq!(mru_from(&usage), ["b", "c"]);
        assert_eq!(mru_from(&serde_json::json!({"appIds": ["a"]})), ["a"]);
    }

    #[test]
    fn tab_capability_follows_scope_and_context() {
        let onenote = serde_json::json!({"galleryTabs": [{"scopes": ["Team", "GroupChat"], "context": ["ChannelTab", "PrivateChatTab", "MeetingChatTab"]}]});
        let planner = serde_json::json!({"galleryTabs": [{"scopes": ["Team"]}], "staticTabs": [{"scopes": ["Personal"]}]});
        let forms = serde_json::json!({"galleryTabs": [{"scopes": ["GroupChat", "Team"], "context": ["ChannelTab", "MeetingChatTab"]}]});
        let loop_ = serde_json::json!({"galleryTabs": [{"scopes": ["Team"], "context": ["ChannelTab"]}], "staticTabs": [{"scopes": ["GroupChat"], "context": ["MeetingStage"]}]});
        let web = serde_json::json!({"configurableTabs": [{"scopes": ["team", "groupchat"]}]});
        for (def, chat, meeting, channel) in [(&onenote, true, true, true), (&planner, false, false, true), (&forms, false, true, true), (&loop_, false, false, true), (&web, true, true, true)] {
            assert_eq!(IcKind::TabChat.supports(def), chat);
            assert_eq!(IcKind::TabMeeting.supports(def), meeting);
            assert_eq!(IcKind::TabChannel.supports(def), channel);
        }
        let bot = serde_json::json!({"bots": [{"scopes": ["GroupChat"]}]});
        assert!(IcKind::BotGroupChat.supports(&bot) && !IcKind::BotTeam.supports(&bot) && !IcKind::TabChat.supports(&bot));
    }
}
