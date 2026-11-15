//! Link previews (URL previews), as Teams makes them.
//!
//! - **Compose.** The first link in the message gets a preview from Teams'
//!   URL preview service (region GTM `urlpV2`): `GET {urlpV2}/v1/url/richInfo?url=…`,
//!   falling back to `v1/url/info`. A preview counts when it has two of
//!   picture, title and description.
//! - **Send.** The preview travels in `properties.links`, a JSON string:
//!   `[{"@type":"http://schema.skype.com/HyperLink","itemid":"0","url",
//!   "previewenabled","preview":{"previewurl","previewmeta","title",
//!   "description"}}]`. A removed preview is sent with `previewenabled:false`.
//! - **Receive.** Teams fetches nothing for received links: it shows the
//!   sender's preview when it is enabled, valid, and for the message's first
//!   link.
//! - **Privacy.** "Optional connected experiences" off (the user preference
//!   `controllerConnectedServicesEnabled`) or a messaging policy without URL
//!   previews: no cards.
//!
//! Teams' pictures are already behind its URL proxy (`…/urlp/v1/url/image/
//! Thumbnail?url=…`), so the origin image is never fetched.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;

/// One link's preview.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct UrlPreview {
    pub url: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    /// The picture (a URL proxy address), or "".
    #[serde(default)]
    pub thumbnail: String,
    /// The picture's size when the service gave it.
    #[serde(default)]
    pub thumbnail_meta: Option<(u64, u64)>,
    /// Shown (false once the sender removed it).
    #[serde(default = "yes")]
    pub enabled: bool,
}

fn yes() -> bool {
    true
}

impl UrlPreview {
    /// Teams' rule: two of picture, title and description.
    pub fn is_valid(&self) -> bool {
        let (t, ti, d) = (!self.thumbnail.is_empty(), !self.title.is_empty(), !self.description.is_empty());
        (t && ti) || (t && d) || (ti && d)
    }

    /// The card's last line: the link's host name.
    pub fn host(&self) -> String {
        url::Url::parse(&self.url)
            .ok()
            .and_then(|u| u.host_str().map(str::to_string))
            .unwrap_or_default()
    }
}

/// Links Teams makes no preview for: Teams' own message, channel, chat and
/// meeting-recap links, mail links, Loop pages and non-web links.
pub fn excluded(url: &str) -> bool {
    let Ok(u) = url::Url::parse(url) else { return true };
    if u.scheme() != "http" && u.scheme() != "https" {
        return true;
    }
    let host = u.host_str().unwrap_or("");
    if (host == "teams.microsoft.com" || host == "teams.cloud.microsoft")
        && ["/l/message", "/l/channel", "/l/chat", "/l/meetingrecap"]
            .iter()
            .any(|p| u.path().contains(p))
    {
        return true;
    }
    // SharePoint and OneDrive file links become file cards instead.
    host.ends_with(".sharepoint.com") || host == "1drv.ms" || host.ends_with("onedrive.live.com")
}

/// The first link's address in message HTML (Teams previews only that one),
/// outside cards.
pub fn first_link(html: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let mut from = 0;
    while let Some(i) = lower[from..].find("<a ") {
        let start = from + i;
        let end = lower[start..].find('>').map(|e| start + e)?;
        let tag = &html[start..end];
        from = end;
        if let Some(h) = attr(tag, "href") {
            return Some(unescape(&h));
        }
    }
    None
}

fn attr(tag: &str, name: &str) -> Option<String> {
    let lower = tag.to_ascii_lowercase();
    let i = lower.find(&format!("{name}="))? + name.len() + 1;
    let rest = &tag[i..];
    let q = rest.chars().next()?;
    if q == '"' || q == '\'' {
        rest[1..].find(q).map(|e| rest[1..1 + e].to_string())
    } else {
        Some(rest.split(|c: char| c.is_whitespace() || c == '>').next()?.to_string())
    }
}

/// Teams' normalisation before comparing a link with its preview's.
pub fn unescape(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&#38;", "&")
        .replace("&#x26;", "&")
}

/// What Teams asks the service for: decoded, without trailing quote marks.
fn query_url(url: &str) -> String {
    let decoded = percent_decode(url).unwrap_or_else(|| url.to_string());
    decoded.trim_end_matches(['<', '>', '\'', '"', '`']).to_string()
}

fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = s.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// Asks Teams' URL preview service for a link's preview (`richInfo`, then
/// `info`); None when it has no valid one.
pub async fn fetch(client: &TeamsClient, url: &str) -> Result<Option<UrlPreview>> {
    if excluded(url) {
        return Ok(None);
    }
    let base = client
        .region_endpoint("urlpV2")
        .context("No URL preview service for this account")?;
    let base = base.trim_end_matches('/');
    let q = encode(&query_url(url));
    for path in ["richInfo", "info"] {
        let endpoint = format!("{base}/v1/url/{path}?url={q}");
        let Ok(bytes) = client.ams_get(&endpoint).await else { continue };
        let Ok(v) = serde_json::from_slice::<serde_json::Value>(&bytes) else { continue };
        let p = if path == "richInfo" { preview_from_rich(url, &v) } else { preview_from_info(url, &v) };
        return Ok(p.filter(UrlPreview::is_valid));
    }
    Ok(None)
}

/// encodeURIComponent.
fn encode(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>().replace('+', "%20")
}

fn s(v: &serde_json::Value, k: &str) -> String {
    v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string()
}

fn preview_from_info(url: &str, v: &serde_json::Value) -> Option<UrlPreview> {
    let meta = v.get("thumbnail_meta").and_then(|m| Some((m.get("width")?.as_u64()?, m.get("height")?.as_u64()?)));
    Some(UrlPreview {
        url: url.to_string(),
        title: s(v, "title"),
        description: s(v, "description"),
        thumbnail: s(v, "thumbnail"),
        thumbnail_meta: meta,
        enabled: true,
    })
}

fn preview_from_rich(url: &str, v: &serde_json::Value) -> Option<UrlPreview> {
    let info = v.get("urlInfo")?;
    Some(UrlPreview {
        url: url.to_string(),
        title: s(info, "title"),
        description: s(info, "description"),
        thumbnail: s(info, "thumbnail"),
        thumbnail_meta: None,
        enabled: true,
    })
}

/// `properties.links` for a sent message with this preview (or "[]").
pub fn links_property(preview: Option<&UrlPreview>) -> String {
    let Some(p) = preview else { return "[]".into() };
    let mut inner = serde_json::Map::new();
    if !p.thumbnail.is_empty() {
        inner.insert("previewurl".into(), p.thumbnail.clone().into());
    }
    if let Some((w, h)) = p.thumbnail_meta {
        inner.insert("previewmeta".into(), serde_json::json!({ "width": w, "height": h }));
    }
    if !p.title.is_empty() {
        inner.insert("title".into(), p.title.clone().into());
    }
    if !p.description.is_empty() {
        inner.insert("description".into(), p.description.clone().into());
    }
    serde_json::json!([{
        "@type": "http://schema.skype.com/HyperLink",
        "itemid": "0",
        "url": p.url,
        "previewenabled": p.enabled,
        "preview": inner,
    }])
    .to_string()
}

/// A received message's preview (the first `properties.links` entry), as
/// Teams reads it; None when there is none to show for the message's first
/// link.
pub fn from_message(props: Option<&serde_json::Value>, html: &str) -> Option<UrlPreview> {
    let links = props?.get("links")?;
    let list: serde_json::Value = match links {
        serde_json::Value::String(s) => serde_json::from_str(s).ok()?,
        other => other.clone(),
    };
    let e = list.as_array()?.first()?;
    let pv = e.get("preview")?;
    let url = s(e, "url");
    let meta = pv.get("previewmeta").and_then(|m| Some((m.get("width")?.as_u64()?, m.get("height")?.as_u64()?)));
    let p = UrlPreview {
        title: s(pv, "title").trim().to_string(),
        description: s(pv, "description"),
        thumbnail: safe_url(&s(pv, "previewurl")),
        thumbnail_meta: meta,
        enabled: e.get("previewenabled").and_then(|b| b.as_bool()).unwrap_or(false),
        url: safe_url(&url),
    };
    let first = first_link(html)?;
    (p.enabled && p.is_valid() && unescape(&first) == unescape(&p.url)).then_some(p)
}

/// Teams' sanitising of a preview's addresses: web links only.
fn safe_url(u: &str) -> String {
    if u.starts_with("https://") || u.starts_with("http://") {
        u.replace('\'', "%27").replace('"', "%22").replace('{', "%7B").replace('}', "%7D")
    } else {
        String::new()
    }
}

/// Pictures Teams shows: its URL proxy and media hosts only (others get the
/// link placeholder).
pub fn thumbnail_allowed(u: &str) -> bool {
    let Ok(p) = url::Url::parse(u) else { return false };
    let host = p.host_str().unwrap_or("");
    p.scheme() == "https"
        && (host == "urlp.asm.skype.com"
            || host == "urlp.sfbassets.com"
            || host.ends_with(".asm.skype.com")
            || host.ends_with(".asyncgw.teams.microsoft.com"))
}

/// Removing your sent message's preview (Teams' X): `PUT …/messages/{id}/
/// properties?name=links` with the preview turned off.
pub async fn remove_from_message(
    client: &TeamsClient,
    conversation: &str,
    message_id: &str,
    preview: &UrlPreview,
) -> Result<()> {
    let off = UrlPreview { enabled: false, ..preview.clone() };
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}/properties?name=links",
        client.chat_service_url(),
        encode(conversation),
        message_id
    );
    client
        .chat_request(reqwest::Method::PUT, &url, &serde_json::json!({ "links": links_property(Some(&off)) }))
        .await
        .map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rust() -> UrlPreview {
        UrlPreview {
            url: "https://www.rust-lang.org/".into(),
            title: "\n            Rust Programming Language\n        ".into(),
            description: "A language empowering everyone to build reliable and efficient software.".into(),
            thumbnail: "https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/image/Thumbnail?url=https%3a%2f%2fwww.rust-lang.org%2fstatic%2fimages%2frust-social.jpg".into(),
            thumbnail_meta: None,
            enabled: true,
        }
    }

    #[test]
    fn sends_teams_links_property() {
        // As Teams sent OST TEST 158 (2026-11-15).
        let want = r#"[{"@type":"http://schema.skype.com/HyperLink","itemid":"0","url":"https://www.rust-lang.org/","previewenabled":true,"preview":{"previewurl":"https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/image/Thumbnail?url=https%3a%2f%2fwww.rust-lang.org%2fstatic%2fimages%2frust-social.jpg","title":"\n            Rust Programming Language\n        ","description":"A language empowering everyone to build reliable and efficient software."}}]"#;
        let got: serde_json::Value = serde_json::from_str(&links_property(Some(&rust()))).unwrap();
        assert_eq!(got, serde_json::from_str::<serde_json::Value>(want).unwrap());
        assert_eq!(links_property(None), "[]");
    }

    #[test]
    fn reads_received_previews_as_teams() {
        let html = r#"<p>OST TEST 158 link preview <a href="https://www.rust-lang.org/" title="x">https://www.rust-lang.org/</a> </p>"#;
        let props = serde_json::json!({ "links": links_property(Some(&rust())) });
        let p = from_message(Some(&props), html).unwrap();
        assert_eq!(p.title, "Rust Programming Language");
        assert_eq!(p.host(), "www.rust-lang.org");
        // Removed by the sender, or for another link: nothing.
        let off = serde_json::json!({ "links": links_property(Some(&UrlPreview { enabled: false, ..rust() })) });
        assert!(from_message(Some(&off), html).is_none());
        assert!(from_message(Some(&props), r#"<a href="https://example.com/">x</a>"#).is_none());
        // Two of picture, title and description.
        let thin = UrlPreview { thumbnail: String::new(), description: String::new(), ..rust() };
        assert!(!thin.is_valid());
    }

    #[test]
    fn first_link_and_exclusions() {
        assert_eq!(first_link(r#"<p>a <a href="https://a.example/?x=1&amp;y=2">a</a> <a href="https://b.example/">b</a></p>"#).as_deref(), Some("https://a.example/?x=1&y=2"));
        assert!(excluded("https://teams.microsoft.com/l/message/19:x/123"));
        assert!(excluded("mailto:someone@example.com"));
        assert!(excluded("https://contoso.sharepoint.com/sites/x/doc.docx"));
        assert!(!excluded("https://www.rust-lang.org/"));
        assert_eq!(query_url("https://example.com/a%20b\""), "https://example.com/a b");
    }
}
