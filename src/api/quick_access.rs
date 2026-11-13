//! Quick access, as Teams' OneDrive app and its Move/Copy picker show it
//! (docs/spec/file-actions.md): the document libraries you pinned
//! (`SP.PinnedItems.GetItemsBy`), then the ones you used lately
//! (`sp.QuickAccessItemCollection.GetQuickAccessItems`, whose own pinned
//! list stays empty), both on your OneDrive site; pinning and unpinning with
//! `SP.PinnedItems.AddItem` / `RemoveItem`.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// One library in Quick access.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct QuickLibrary {
    /// What the list shows: the site's name, plus " - {library}" for a
    /// library other than the site's default one ("OST Test Team - Site
    /// Assets").
    pub label: String,
    /// The library's own title ("Documents"), used in the notices.
    pub title: String,
    pub site_title: String,
    pub list_url: String,
    pub site_url: String,
    pub site_id: String,
    pub web_id: String,
    pub list_id: String,
    pub acronym: String,
    /// The tile's colour ("#7a7574").
    pub color: String,
    pub logo_url: String,
    pub is_default: bool,
    pub pinned: bool,
    /// Graph's drive id, for opening it (empty when it couldn't be found).
    #[serde(default)]
    pub drive_id: String,
}

/// Your OneDrive's site address ("https://x-my.sharepoint.com/personal/you").
pub async fn personal_site(client: &TeamsClient) -> Result<String> {
    let d: Value = client.graph_get("/me/drive?$select=webUrl").await?.json().await?;
    let web = d["webUrl"].as_str().unwrap_or_default();
    match web.rsplit_once('/') {
        Some((site, _)) if site.starts_with("https://") && site.contains("/personal/") => Ok(site.to_string()),
        _ => bail!("Your OneDrive's address is unknown"),
    }
}

fn s(v: &Value, k: &str) -> String {
    v[k].as_str().unwrap_or_default().to_string()
}

/// One entry, from either reply (OneDrive's `_processQuickAccessItems`: a
/// library in "Shared Documents" counts as the default one; a missing
/// acronym is the first letters of the site's first two words). Pinned
/// items name their fields differently (`listUrl`, `siteUrl`, `siteTitle`).
fn library(v: &Value, pinned: bool) -> Option<QuickLibrary> {
    let pick = |a: &str, b: &str| match s(v, a) {
        x if x.is_empty() => s(v, b),
        x => x,
    };
    let list_url = pick("accessUrl", "listUrl");
    let list_id = s(v, "listId");
    if list_url.is_empty() || list_id.is_empty() {
        return None;
    }
    let site_title = pick("containerTitle", "siteTitle");
    let title = s(v, "title");
    let decoded = percent_decode(&list_url);
    let is_default = v["isDefaultDocumentLibrary"].as_bool().unwrap_or(false) || decoded.contains("Shared Documents");
    let mut site_url = pick("webUrl", "siteUrl");
    if site_url.is_empty() {
        site_url = decoded.rsplit_once('/').map(|(a, _)| a.to_string()).unwrap_or_default();
    }
    let acronym = match s(v, "siteAcronym") {
        a if !a.is_empty() => a,
        _ => site_title.split_whitespace().take(2).filter_map(|w| w.chars().next()).flat_map(char::to_uppercase).collect(),
    };
    Some(QuickLibrary {
        label: if is_default || title.is_empty() { site_title.clone() } else { format!("{site_title} - {title}") },
        title,
        site_title,
        list_url,
        site_url,
        site_id: s(v, "siteId"),
        web_id: s(v, "webId"),
        list_id,
        acronym,
        color: s(v, "siteColor"),
        logo_url: pick("siteLogoUrl", "siteIconUrl"),
        is_default,
        pinned,
        drive_id: String::new(),
    })
}

fn percent_decode(u: &str) -> String {
    url::form_urlencoded::parse(format!("x={}", u.replace('+', "%2B")).as_bytes())
        .next()
        .map(|(_, v)| v.into_owned())
        .unwrap_or_default()
}

/// Quick access from the two replies: the pinned items in their `order`,
/// then the recent libraries (a JSON string inside the reply) that aren't
/// pinned.
pub fn parse(pinned: &Value, quick: &Value) -> Vec<QuickLibrary> {
    let mut pins: Vec<&Value> = pinned.pointer("/d/GetItemsBy/results").and_then(Value::as_array).into_iter().flatten().collect();
    let order = |v: &Value| v["order"].as_str().and_then(|o| o.parse::<f64>().ok()).or_else(|| v["order"].as_f64()).unwrap_or(f64::MAX);
    pins.sort_by(|a, b| order(a).total_cmp(&order(b)));
    let mut out: Vec<QuickLibrary> = pins.into_iter().filter_map(|x| library(x, true)).collect();
    let inner = quick.pointer("/d/GetQuickAccessItems").and_then(Value::as_str).unwrap_or("{}");
    let v: Value = serde_json::from_str(inner).unwrap_or_default();
    let list = |k: &str| -> Vec<Value> { v[k].as_str().and_then(|t| serde_json::from_str(t).ok()).unwrap_or_default() };
    for r in list("RecentDocumentLibraries").iter().filter_map(|x| library(x, false)) {
        if !out.iter().any(|p| p.list_id == r.list_id && p.site_id == r.site_id) {
            out.push(r);
        }
    }
    out
}

/// Quick access, with each library's Graph drive id.
pub async fn items(client: &TeamsClient) -> Result<Vec<QuickLibrary>> {
    let site = personal_site(client).await?;
    let (pins_url, quick_url, empty) = (
        format!("{site}/_api/SP.PinnedItems.GetItemsBy"),
        format!("{site}/_api/sp.QuickAccessItemCollection.GetQuickAccessItems"),
        json!({}),
    );
    let (pinned, quick) = tokio::join!(super::sharing::post(&pins_url, &empty), super::sharing::get_with(&quick_url, &[]));
    // Quick access still lists recent libraries when the pins can't be read.
    let pinned = pinned.unwrap_or_else(|e| {
        tracing::warn!("Quick access pins: {e:#}");
        Value::Null
    });
    let mut libs = parse(&pinned, &quick?);
    let ids = futures::future::join_all(libs.iter().map(|l| drive_id(client, l))).await;
    for (l, id) in libs.iter_mut().zip(ids) {
        l.drive_id = id.unwrap_or_default();
    }
    Ok(libs)
}

fn guid(id: &str) -> Result<&str> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Not an id: {id}");
    }
    Ok(id)
}

/// The library's drive in Graph (`/sites/{host},{site},{web}/lists/{list}/drive`).
async fn drive_id(client: &TeamsClient, l: &QuickLibrary) -> Result<String> {
    let host = l.site_url.split('/').nth(2).context("No site host")?;
    let path = format!("/sites/{host},{},{}/lists/{}/drive?$select=id", guid(&l.site_id)?, guid(&l.web_id)?, guid(&l.list_id)?);
    let v: Value = client.graph_get(&path).await?.json().await?;
    Ok(s(&v, "id"))
}

/// `SP.PinnedItems.AddItem`'s body, as OneDrive builds it.
pub fn pin_body(l: &QuickLibrary, personal: &str) -> Value {
    // OneDrive always points the icon at your site's icon manager.
    let enc: String = url::form_urlencoded::byte_serialize(l.site_url.as_bytes()).collect();
    let icon = format!("{personal}/_api/siteiconmanager/getsitelogo?siteUrl='{}'", enc.replace('.', "%2E"));
    json!({ "pinnedItem": {
        "webId": l.web_id, "listId": l.list_id, "title": l.title,
        "listUrl": percent_decode(&l.list_url), "siteUrl": l.site_url, "siteTitle": l.site_title,
        "siteIconUrl": icon, "siteId": l.site_id, "isDefaultDocumentLibrary": l.is_default,
        "siteColor": l.color, "siteAcronym": l.acronym,
    }})
}

/// Pin the library to Quick access, or unpin it.
pub async fn set_pinned(client: &TeamsClient, l: &QuickLibrary, pin: bool) -> Result<()> {
    let site = personal_site(client).await?;
    if pin {
        super::sharing::post(&format!("{site}/_api/SP.PinnedItems.AddItem"), &pin_body(l, &site)).await?;
    } else {
        super::sharing::post(
            &format!("{site}/_api/SP.PinnedItems.RemoveItem"),
            &json!({ "listId": l.list_id, "siteId": l.site_id, "webId": l.web_id }),
        )
        .await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reply(recent: &[Value]) -> Value {
        json!({ "d": { "GetQuickAccessItems": json!({
            "RecentDocumentLibraries": serde_json::to_string(recent).unwrap(),
            "PinnedDocumentLibraries": "",
        }).to_string() } })
    }

    fn pins(items: &[Value]) -> Value {
        json!({ "d": { "GetItemsBy": { "results": items } } })
    }

    /// A pinned item as `GetItemsBy` gives it.
    fn pin(site: &str, list: &str, order: &str) -> Value {
        json!({ "siteId": "9d", "webId": "cc", "listId": list, "title": "Documents", "siteTitle": site,
            "listUrl": "https://x.sharepoint.com/sites/S/Shared Documents", "siteUrl": "https://x.sharepoint.com/sites/S",
            "siteAcronym": "SC", "siteColor": "#4f6bed", "isDefaultDocumentLibrary": true, "order": order })
    }

    fn lib(title: &str, site: &str, list: &str, url: &str, default: Option<bool>) -> Value {
        let mut v = json!({ "siteId": "9d", "webId": "cc", "listId": list, "title": title, "accessUrl": url,
            "containerTitle": site, "webUrl": "https://x.sharepoint.com/sites/T", "siteColor": "#7a7574" });
        if let Some(d) = default {
            v["isDefaultDocumentLibrary"] = json!(d);
        }
        v
    }

    #[test]
    fn labels_are_the_site_plus_a_non_default_library() {
        let r = reply(&[
            lib("Documents", "OST Test Team", "17", "https://x.sharepoint.com/sites/T/Shared%20Documents", Some(true)),
            lib("Site Assets", "OST Test Team", "dd", "https://x.sharepoint.com/sites/T/SiteAssets", None),
        ]);
        let libs = parse(&Value::Null, &r);
        assert_eq!(libs.iter().map(|l| l.label.as_str()).collect::<Vec<_>>(), ["OST Test Team", "OST Test Team - Site Assets"]);
        assert_eq!(libs[1].acronym, "OT");
        assert!(!libs[0].pinned);
    }

    #[test]
    fn pinned_come_first_and_are_not_repeated() {
        let docs = lib("Documents", "OST Test Team", "17", "https://x.sharepoint.com/sites/T/Shared%20Documents", None);
        let other = lib("Documents", "Secure Coast Network Solutions", "aa", "https://x.sharepoint.com/sites/S/Shared%20Documents", Some(true));
        let libs = parse(&pins(&[pin("Second", "bb", "8589934592"), pin("Secure Coast Network Solutions", "aa", "4294967296")]), &reply(&[docs, other]));
        assert_eq!(libs.iter().map(|l| (l.label.as_str(), l.pinned)).collect::<Vec<_>>(),
            [("Secure Coast Network Solutions", true), ("Second", true), ("OST Test Team", false)]);
        // "Shared Documents" counts as the default library.
        assert!(libs[2].is_default);
        assert_eq!((libs[0].acronym.as_str(), libs[0].color.as_str()), ("SC", "#4f6bed"));
    }

    #[test]
    fn pin_body_is_onedrives() {
        let l = parse(&Value::Null, &reply(&[lib("Documents", "OST Test Team", "17", "https://x.sharepoint.com/sites/T/Shared%20Documents", Some(true))])).remove(0);
        let b = pin_body(&l, "https://x-my.sharepoint.com/personal/me");
        assert_eq!(b["pinnedItem"]["listUrl"], "https://x.sharepoint.com/sites/T/Shared Documents");
        assert_eq!(b["pinnedItem"]["siteIconUrl"], "https://x-my.sharepoint.com/personal/me/_api/siteiconmanager/getsitelogo?siteUrl='https%3A%2F%2Fx%2Esharepoint%2Ecom%2Fsites%2FT'");
        assert_eq!(b["pinnedItem"]["siteAcronym"], "OT");
        assert_eq!(b["pinnedItem"]["isDefaultDocumentLibrary"], true);
    }
}
