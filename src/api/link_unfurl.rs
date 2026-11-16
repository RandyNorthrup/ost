//! App link unfurling: links to sites that have a Teams app get that app's
//! card instead of the plain preview (read from Teams' AppBasedLinkService
//! and app-based-link helpers, and captured on winpc 2026-11-16 with
//! Wikipedia Search, "OST TEST 168a").
//!
//! - **Which app.** An app's message extension declares the links it
//!   unfurls (`messageExtensions[0].messageHandlers[0]` of type `link`, its
//!   `value.domains`). Teams looks among your installed apps first, then
//!   among all message-extension apps; an app you haven't installed is used
//!   only when it supports anonymous access (`supportsAnonymousAccess`, or
//!   ECS `anonymousAppBasedLinkApps`).
//! - **Domains.** A domain without "/" matches `https://{domain}` with `*`
//!   for one label, then the end or a path or query; one with "/" is a
//!   pattern (`*` for anything) found anywhere in the URL. Domains whose
//!   last two labels hold a `*` are ignored.
//! - **Asking the app.** `POST {chat service}/v1/agents/28:{bot}/invoke`
//!   with `{name, appId, value: {url}, imdisplayname, userAadToken,
//!   conversation: {id}}`; the name is `composeExtension/queryLink` for an
//!   installed app and `composeExtension/anonymousQueryLink` otherwise. The
//!   reply is `{composeExtension: {type?, attachments: [{contentType,
//!   content, preview}]}}`: the first attachment is the card, its `preview`
//!   the collapsed preview.
//! - **Sending.** The card goes in `properties.cards` as `{appIcon, appId,
//!   appName, cardClientId: "app-preview-card-ps{32 hex}", contentType,
//!   content}`; the body ends with an `inline-compose-card` span naming it;
//!   `properties.links` carries the preview turned off.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::client::TeamsClient;
use super::url_preview::UrlPreview;

/// An app that unfurls a link.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct LinkApp {
    pub app_id: String,
    pub name: String,
    pub icon: String,
    /// The message extension's bot (no `28:`).
    pub bot_id: String,
    /// Installed for you (else used anonymously).
    pub installed: bool,
    pub privacy_url: String,
    pub terms_url: String,
}

/// An app's card for a link.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct AppCard {
    pub url: String,
    pub app_id: String,
    pub app_name: String,
    pub app_icon: String,
    pub content_type: String,
    pub content: Value,
    /// Unfurled without installing (Teams then shows the app's terms).
    #[serde(default)]
    pub anonymous: bool,
    #[serde(default)]
    pub privacy_url: String,
    #[serde(default)]
    pub terms_url: String,
    /// The collapsed form (the app's `preview` card as a link preview).
    #[serde(default)]
    pub preview: Option<UrlPreview>,
    /// Sent collapsed: the plain preview instead of the card.
    #[serde(default)]
    pub collapsed: bool,
}

/// Teams' `F`: a domain it can use (at least two labels, no `*` in the
/// last two).
pub fn domain_usable(d: &str) -> bool {
    let host = d.split('/').next().unwrap_or("");
    let labels: Vec<&str> = host.split('.').collect();
    if labels.len() <= 1 {
        return false;
    }
    !labels[labels.len() - 1].contains('*') && !labels[labels.len() - 2].contains('*')
}

/// Teams' match of a URL against an app's domains (`F6` for host domains,
/// `A` for path patterns).
pub fn domains_match(url: &str, domains: &[String]) -> bool {
    let Ok(parsed) = url::Url::parse(url) else { return false };
    let href = parsed.as_str();
    let usable: Vec<&String> = domains.iter().filter(|d| domain_usable(d)).collect();
    let (paths, hosts): (Vec<&String>, Vec<&String>) = usable.into_iter().partition(|d| d.contains('/'));
    let mut seen = std::collections::HashSet::new();
    for d in hosts {
        if !seen.insert(d.to_lowercase()) {
            continue;
        }
        let pat: Vec<String> = d.split('.').map(|l| regex::escape(l).replace("\\*", "[^/^.]+")).collect();
        if let Ok(re) = regex::Regex::new(&format!("(?i)^https://{}((/|\\?).*)?$", pat.join("[.]")))
            && re.is_match(href)
        {
            return true;
        }
    }
    // Teams turns `*` into `(.*)` and leaves the rest as a pattern.
    paths.iter().any(|d| regex::Regex::new(&d.replace('*', "(.*)")).is_ok_and(|re| re.is_match(url)))
}

/// An app definition's link handler: (bot, domains, anonymous access).
/// The middle tier's catalog calls message extensions `inputExtensions`
/// (Teams' GraphQL layer renames them `messageExtensions`).
pub fn link_handler(def: &Value) -> Option<(String, Vec<String>, bool)> {
    let me = def
        .get("inputExtensions")
        .or_else(|| def.get("messageExtensions"))?
        .as_array()?
        .first()?;
    let h = me.get("messageHandlers")?.as_array()?.first()?;
    if h.get("type").and_then(|t| t.as_str()).is_some_and(|t| !t.eq_ignore_ascii_case("link")) {
        return None;
    }
    let v = h.get("value")?;
    let domains = v
        .get("domains")
        .and_then(|d| d.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect())
        .unwrap_or_default();
    let anon = v.get("supportsAnonymousAccess").and_then(|b| b.as_bool()).unwrap_or(false);
    let bot = me.get("botId").and_then(|b| b.as_str()).unwrap_or_default().to_string();
    Some((bot, domains, anon))
}

fn str_at<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(|x| x.as_str()).unwrap_or_default()
}

/// Entitlement states Teams counts as installed (`bt`).
pub fn installed_state(state: &str) -> bool {
    matches!(state, "Installed" | "InstalledAndFavorited" | "InstalledAndPermanent" | "AdminPreInstalled" | "installed" | "installedAndFavorited" | "installedAndPermanent" | "adminPreInstalled")
}

/// The app Teams uses for a link: an installed app whose domains match,
/// else an app that may unfurl anonymously (`anonymous_ids` is ECS
/// `anonymousAppBasedLinkApps`). Apps blocked for you (Teams' catalog
/// leaves them out) never match.
pub fn find_app(
    url: &str,
    catalog: &[Value],
    entitlements: &std::collections::HashMap<String, String>,
    anonymous_ids: &[String],
) -> Option<LinkApp> {
    let candidate = |def: &Value| -> Option<(LinkApp, bool)> {
        let (bot, domains, anon) = link_handler(def)?;
        if bot.is_empty() || !domains_match(url, &domains) {
            return None;
        }
        let id = str_at(def, "id").to_string();
        let installed = entitlements.get(&id.to_lowercase()).is_some_and(|s| installed_state(s));
        let anonymous = anon || anonymous_ids.iter().any(|a| a.eq_ignore_ascii_case(&id));
        Some((
            LinkApp {
                app_id: id,
                name: str_at(def, "name").to_string(),
                icon: super::tabs::https_only(str_at(def, "largeImageUrl")),
                bot_id: bot.strip_prefix("28:").unwrap_or(&bot).to_string(),
                installed,
                privacy_url: str_at(def, "privacyUrl").to_string(),
                terms_url: str_at(def, "termsOfUseUrl").to_string(),
            },
            anonymous,
        ))
    };
    let all: Vec<(LinkApp, bool)> = catalog.iter().filter_map(candidate).collect();
    if let Some((a, _)) = all.iter().find(|(a, _)| a.installed) {
        return Some(a.clone());
    }
    // Teams' uninstalled match is the first; it unfurls only when anonymous.
    all.into_iter().next().filter(|(_, anon)| *anon).map(|(a, _)| a)
}

/// The invoke's name: installed apps get `queryLink`, others the anonymous
/// one.
pub fn invoke_name(app: &LinkApp) -> &'static str {
    if app.installed { "composeExtension/queryLink" } else { "composeExtension/anonymousQueryLink" }
}

/// Teams' queryLink body (as sent on winpc, OST TEST 168a).
pub fn query_body(app: &LinkApp, url: &str, thread: &str, display_name: &str, aad_token: &str) -> Value {
    json!({
        "name": invoke_name(app),
        "appId": app.app_id,
        "value": { "url": url },
        "imdisplayname": display_name,
        "userAadToken": aad_token,
        "conversation": { "id": thread },
    })
}

fn strip_tags(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_tag = false;
    for c in s.chars() {
        match c {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    super::url_preview::unescape(&out)
}

/// The app's reply as a card (the first attachment), with its preview;
/// None when it gave no usable card (Teams: Hero or Thumbnail previews, or
/// the card's own preview).
pub fn card_from_reply(reply: &Value, app: &LinkApp, url: &str) -> Option<AppCard> {
    let ce = reply.get("composeExtension").unwrap_or(reply);
    let kind = ce.get("type").and_then(|t| t.as_str()).unwrap_or("result");
    if kind != "result" {
        return None;
    }
    let a = ce.get("attachments")?.as_array()?.first()?;
    let content_type = a.get("contentType")?.as_str()?.to_string();
    let content = match a.get("content")? {
        Value::String(s) => serde_json::from_str(s).ok()?,
        v => v.clone(),
    };
    let preview_card = a
        .get("preview")
        .filter(|p| p.is_object())
        .cloned()
        .or_else(|| {
            let t = content_type.to_lowercase();
            (t == "application/vnd.microsoft.card.hero" || t == "application/vnd.microsoft.card.thumbnail")
                .then(|| json!({ "contentType": content_type, "content": content }))
        })?;
    let pc = match preview_card.get("content") {
        Some(Value::String(s)) => serde_json::from_str(s).unwrap_or_default(),
        Some(v) => v.clone(),
        None => Value::Null,
    };
    let preview = UrlPreview {
        url: url.to_string(),
        title: strip_tags(str_at(&pc, "title")).trim().to_string(),
        description: strip_tags(str_at(&pc, "text")).trim().to_string(),
        thumbnail: pc.pointer("/images/0/url").and_then(|u| u.as_str()).unwrap_or_default().to_string(),
        thumbnail_meta: None,
        enabled: false,
    };
    Some(AppCard {
        url: url.to_string(),
        app_id: app.app_id.clone(),
        app_name: app.name.clone(),
        app_icon: app.icon.clone(),
        content_type,
        content,
        anonymous: !app.installed,
        privacy_url: app.privacy_url.clone(),
        terms_url: app.terms_url.clone(),
        preview: Some(preview),
        collapsed: false,
    })
}

/// A new card id as Teams sends it.
pub fn new_card_client_id() -> String {
    format!("app-preview-card-ps{}", uuid::Uuid::new_v4().simple())
}

/// The span Teams adds to the message body for the card.
pub fn inline_span(card_client_id: &str) -> String {
    format!(
        "<span class=\"inline-compose-card\" itemid=\"{card_client_id}\" itemscope itemtype=\"http://schema.skype.com/InputExtension\"><span content=\"{card_client_id}\" itemprop=\"cardId\"></span></span>"
    )
}

/// `properties.cards` for the card.
pub fn cards_property(card: &AppCard, card_client_id: &str) -> String {
    json!([{
        "appIcon": card.app_icon,
        "appId": card.app_id,
        "appName": card.app_name,
        "cardClientId": card_client_id,
        "contentType": card.content_type,
        "content": card.content,
    }])
    .to_string()
}

/// Whether a received card is an app link card (Teams' `app-preview-card`
/// ids).
pub fn is_link_card(card_client_id: &str) -> bool {
    card_client_id.starts_with("app-preview-card")
}

/// Whether this account may unfurl anonymously with an app that isn't
/// installed (ECS `enableAnonymousAppBasedLink`, on unless turned off).
fn anonymous_allowed() -> bool {
    super::ecs::setting("extensibility", "enableAnonymousAppBasedLink").and_then(|v| v.as_bool()).unwrap_or(true)
}

/// Teams' commercial default for ECS `anonymousAppBasedLinkApps`
/// (config-prod): Wikipedia Search and YouTube.
pub const DEFAULT_ANONYMOUS_APPS: [&str; 2] = ["25492237-70ef-4c56-a36e-dd3405edd40e", "com.microsoft.teamspace.tab.youtube"];

fn anonymous_ids() -> Vec<String> {
    super::ecs::setting("extensibility", "anonymousAppBasedLinkApps")
        .and_then(|v| v.as_array().cloned())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect())
        .unwrap_or_else(|| DEFAULT_ANONYMOUS_APPS.iter().map(|s| s.to_string()).collect())
}

/// The app for a link, from the catalog and your apps (None when no app
/// unfurls it).
pub async fn app_for(client: &TeamsClient, url: &str) -> Result<Option<LinkApp>> {
    if super::url_preview::excluded(url) {
        return Ok(None);
    }
    let apps = match index() {
        Some(a) => a,
        None => {
            build_index(client, INDEX_FILE.get().map(|p| p.as_path())).await?;
            index().unwrap_or_default()
        }
    };
    let ents = entitlements(client).await;
    let anon = anonymous_ids();
    let app = find_app(url, &apps, &ents, &anon);
    Ok(app.filter(|a| a.installed || anonymous_allowed()))
}

/// The catalog's apps that unfurl links, trimmed to what matching needs
/// (Teams keeps its app definitions cached; the whole catalog takes OST
/// minutes to page through, so the index is kept on disk).
static INDEX: std::sync::RwLock<Option<std::sync::Arc<Vec<Value>>>> = std::sync::RwLock::new(None);
static INDEX_FILE: std::sync::OnceLock<std::path::PathBuf> = std::sync::OnceLock::new();
static ENTITLEMENTS: std::sync::Mutex<Option<std::collections::HashMap<String, String>>> = std::sync::Mutex::new(None);

fn index() -> Option<std::sync::Arc<Vec<Value>>> {
    INDEX.read().ok()?.clone()
}

/// Your apps, read once a session.
async fn entitlements(client: &TeamsClient) -> std::collections::HashMap<String, String> {
    if let Some(e) = ENTITLEMENTS.lock().unwrap_or_else(|e| e.into_inner()).clone() {
        return e;
    }
    let e = super::app_details::entitlements(client).await.unwrap_or_default();
    *ENTITLEMENTS.lock().unwrap_or_else(|e| e.into_inner()) = Some(e.clone());
    e
}

/// The link apps of a catalog, each trimmed to its id, name, icon, links
/// and handler.
pub fn index_from(catalog: &[Value]) -> Vec<Value> {
    catalog
        .iter()
        .filter(|d| link_handler(d).is_some())
        .map(|d| {
            let ext = d.get("inputExtensions").or_else(|| d.get("messageExtensions")).and_then(|a| a.as_array()).and_then(|a| a.first()).cloned().unwrap_or_default();
            json!({
                "id": d.get("id"), "name": d.get("name"), "largeImageUrl": d.get("largeImageUrl"),
                "privacyUrl": d.get("privacyUrl"), "termsOfUseUrl": d.get("termsOfUseUrl"),
                "inputExtensions": [{ "botId": ext.get("botId"), "messageHandlers": ext.get("messageHandlers") }],
            })
        })
        .collect()
}

async fn build_index(client: &TeamsClient, file: Option<&std::path::Path>) -> Result<()> {
    let catalog = super::app_details::catalog(client).await?;
    let apps = index_from(&catalog);
    if let Some(f) = file {
        if let Some(dir) = f.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(f, serde_json::to_vec(&apps)?);
    }
    tracing::info!("app link index: {} apps", apps.len());
    *INDEX.write().unwrap_or_else(|e| e.into_inner()) = Some(std::sync::Arc::new(apps));
    Ok(())
}

/// Load the link-app index at sign-in: the saved one at once, then a new
/// one from the catalog when it is a day old (or missing).
pub async fn load_index(client: &TeamsClient, cache_dir: &std::path::Path) -> Result<()> {
    let file = cache_dir.join("link-apps.json");
    let _ = INDEX_FILE.set(file.clone());
    let saved: Option<Vec<Value>> = std::fs::read(&file).ok().and_then(|b| serde_json::from_slice(&b).ok());
    let fresh = std::fs::metadata(&file)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|age| age < std::time::Duration::from_secs(24 * 3600));
    if let Some(apps) = saved {
        tracing::info!("app link index: {} apps saved (fresh {fresh})", apps.len());
        *INDEX.write().unwrap_or_else(|e| e.into_inner()) = Some(std::sync::Arc::new(apps));
    }
    let _ = entitlements(client).await;
    if !fresh || index().is_none() {
        build_index(client, Some(&file)).await?;
    }
    Ok(())
}

/// Ask the link's app for its card (None when there is no app or it gave
/// no card).
pub async fn unfurl(client: &TeamsClient, url: &str, thread: &str) -> Result<Option<AppCard>> {
    let Some(app) = app_for(client, url).await? else { return Ok(None) };
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await.unwrap_or_default();
    let display = client.display_name().unwrap_or_default();
    let endpoint = format!("{}/v1/agents/28:{}/invoke", client.chat_service_url(), app.bot_id);
    let body = query_body(&app, url, thread, &display, &token);
    let resp = client
        .chat_request_with(reqwest::Method::POST, &endpoint, &body, &[("content-type", "application/json")])
        .await
        .context("The app didn't answer")?;
    let text = resp.text().await.unwrap_or_default();
    let reply: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
    let card = card_from_reply(&reply, &app, url);
    tracing::info!("app link {}: {} card={}", app.name, invoke_name(&app), card.is_some());
    Ok(card)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wiki() -> Value {
        json!({
            "id": "25492237-70ef-4c56-a36e-dd3405edd40e", "name": "Wikipedia Search",
            "largeImageUrl": "https://res.cdn.office.net/teamsappdata/x/25492237_largeimage.png",
            "privacyUrl": "https://example.com/privacy", "termsOfUseUrl": "https://example.com/terms",
            "messageExtensions": [{ "botId": "25492237-70ef-4c56-a36e-dd3405edd40e",
                "messageHandlers": [{ "type": "link", "value": { "domains": ["*.wikipedia.org"], "supportsAnonymousAccess": true } }] }]
        })
    }

    #[test]
    fn matches_domains_as_teams() {
        let d = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert!(domains_match("https://en.wikipedia.org/wiki/Rust_(programming_language", &d(&["*.wikipedia.org"])));
        assert!(!domains_match("https://wikipedia.org/wiki/x", &d(&["*.wikipedia.org"])));
        assert!(!domains_match("http://en.wikipedia.org/wiki/x", &d(&["*.wikipedia.org"])));
        assert!(domains_match("https://github.com/rust-lang/cargo", &d(&["github.com"])));
        assert!(!domains_match("https://www.github.com/rust-lang/rust", &d(&["github.com"])));
        assert!(domains_match("https://contoso.com/items/42?x=1", &d(&["contoso.com/items/*"])));
        // Wildcards in the last two labels don't count.
        assert!(!domains_match("https://a.b.com/", &d(&["*.com", "a.*"])));
    }

    #[test]
    fn the_index_keeps_what_matching_needs() {
        let mut catalog_wiki = wiki();
        catalog_wiki["inputExtensions"] = catalog_wiki["messageExtensions"].take();
        catalog_wiki.as_object_mut().unwrap().remove("messageExtensions");
        catalog_wiki["longDescription"] = "lots".into();
        let other = json!({ "id": "x", "name": "No links", "inputExtensions": [{ "botId": "b", "commands": [] }] });
        let idx = index_from(&[catalog_wiki, other]);
        assert_eq!(idx.len(), 1);
        assert!(idx[0].get("longDescription").is_none());
        let a = find_app("https://en.wikipedia.org/wiki/Lighthouse", &idx, &Default::default(), &[]).unwrap();
        assert_eq!((a.name.as_str(), a.bot_id.as_str()), ("Wikipedia Search", "25492237-70ef-4c56-a36e-dd3405edd40e"));
    }

    #[test]
    fn picks_installed_then_anonymous_apps() {
        let cat = vec![wiki()];
        let none = std::collections::HashMap::new();
        let a = find_app("https://en.wikipedia.org/wiki/Ferris_wheel", &cat, &none, &[]).unwrap();
        assert_eq!((a.name.as_str(), a.installed), ("Wikipedia Search", false));
        assert_eq!(invoke_name(&a), "composeExtension/anonymousQueryLink");
        // Not anonymous and not installed: no card.
        let mut closed = wiki();
        closed["messageExtensions"][0]["messageHandlers"][0]["value"]["supportsAnonymousAccess"] = false.into();
        assert!(find_app("https://en.wikipedia.org/wiki/x", &[closed.clone()], &none, &[]).is_none());
        // ...unless ECS lists it, or it is installed.
        assert!(find_app("https://en.wikipedia.org/wiki/x", &[closed.clone()], &none, &["25492237-70EF-4c56-a36e-dd3405edd40e".into()]).is_some());
        let ents = std::collections::HashMap::from([("25492237-70ef-4c56-a36e-dd3405edd40e".to_string(), "Installed".to_string())]);
        let i = find_app("https://en.wikipedia.org/wiki/x", &[closed], &ents, &[]).unwrap();
        assert_eq!(invoke_name(&i), "composeExtension/queryLink");
        assert!(find_app("https://www.rust-lang.org/", &cat, &none, &[]).is_none());
    }

    #[test]
    fn reads_the_reply_and_sends_as_teams() {
        // Wikipedia Search's reply and Teams' message for it (OST TEST 168a).
        let reply = json!({"composeExtension":{"attachments":[{"content":{"title":"<a href=\"https://en.wikipedia.org/wiki/Rust%20%28programming%20language%29\" target=\"_blank\">Rust (programming language)</a>","text":"<span>Rust</span> is a general-purpose <span>programming</span> language","images":[{"alt":"Rust (programming language)","url":"https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/content?url=x"}]},"contentType":"application/vnd.microsoft.card.thumbnail","preview":{"content":{"title":"Rust (programming language)","text":"<span>Rust</span> is a general-purpose <span>programming</span> language","images":[{"alt":"Rust (programming language)","url":"https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/content?url=x"}]},"contentType":"application/vnd.microsoft.card.thumbnail"}}]}});
        let app = find_app("https://en.wikipedia.org/wiki/Rust_(programming_language", &[wiki()], &Default::default(), &[]).unwrap();
        let url = "https://en.wikipedia.org/wiki/Rust_(programming_language";
        let c = card_from_reply(&reply, &app, url).unwrap();
        assert_eq!(c.content_type, "application/vnd.microsoft.card.thumbnail");
        assert!(c.anonymous);
        let p = c.preview.clone().unwrap();
        assert_eq!((p.title.as_str(), p.description.as_str()), ("Rust (programming language)", "Rust is a general-purpose programming language"));
        assert_eq!(p.thumbnail, "https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/content?url=x");
        let id = new_card_client_id();
        assert!(id.starts_with("app-preview-card-ps") && id.len() == "app-preview-card-ps".len() + 32);
        assert!(is_link_card(&id));
        let cards: Value = serde_json::from_str(&cards_property(&c, &id)).unwrap();
        assert_eq!(cards[0]["appName"], "Wikipedia Search");
        assert_eq!(cards[0]["cardClientId"], id.as_str());
        assert_eq!(cards[0]["content"]["images"][0]["alt"], "Rust (programming language)");
        assert!(inline_span(&id).starts_with("<span class=\"inline-compose-card\" itemid=\"app-preview-card-ps"));
        let b = query_body(&app, url, "19:t@thread.v2", "OST Test 1", "tok");
        assert_eq!(b, json!({"name":"composeExtension/anonymousQueryLink","appId":"25492237-70ef-4c56-a36e-dd3405edd40e","value":{"url":url},"imdisplayname":"OST Test 1","userAadToken":"tok","conversation":{"id":"19:t@thread.v2"}}));
        // Auth or config replies give no card.
        assert!(card_from_reply(&json!({"composeExtension":{"type":"auth","suggestedActions":{"actions":[]}}}), &app, url).is_none());
    }
}
