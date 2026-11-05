//! Messages as the Teams clients show them: formatted text, reactions,
//! edits and deletions, and call events in the timeline.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One reaction on a message.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Reaction {
    /// Teams' key, e.g. `like`, `heart`.
    pub key: String,
    /// The emoji to show.
    pub emoji: String,
    pub count: usize,
    /// Whether we reacted with this one.
    pub mine: bool,
}

/// An inline image in a message.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct InlineImage {
    /// AMS object id (safe for a file name).
    pub id: String,
    /// The AMS view URL (needs the Skype token).
    pub url: String,
    pub width: u32,
    pub height: u32,
    /// Filled in by the client once cached locally.
    pub local_path: String,
}

/// A timeline item.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MessageView {
    pub id: String,
    /// The sender's own id for the message (read receipts refer to it).
    pub client_message_id: String,
    /// "message" or "call".
    pub kind: String,
    pub sender: String,
    pub sender_mri: String,
    pub time: String,
    pub mine: bool,
    /// Sanitised HTML for display (a subset Qt renders), "" when deleted.
    pub html: String,
    /// Plain text (search, notifications, accessibility).
    pub text: String,
    pub edited: bool,
    pub deleted: bool,
    pub reactions: Vec<Reaction>,
    /// Inline images (Teams' AMS objects), in order.
    pub images: Vec<InlineImage>,
    /// For call events: "ended" (with duration) or "missed".
    pub call_state: String,
    pub call_seconds: u64,
    /// Your message, and the other person has read up to it (Teams' "Seen").
    pub seen: bool,
    /// The first message that arrived after you last read the chat (Teams
    /// draws its "Last read" line above it).
    #[serde(default)]
    pub first_unread: bool,
    /// Attached files (Teams' file cards).
    #[serde(default)]
    pub files: Vec<super::files::FileAttachment>,
    /// In a channel, the post this message belongs to: its own id for a
    /// post, the post's id for a reply. Empty in chats.
    #[serde(default)]
    pub root_id: String,
}

/// Teams' reaction keys and their emoji.
pub fn reaction_emoji(key: &str) -> &'static str {
    match key {
        "like" => "👍",
        "heart" => "❤️",
        "laugh" => "😆",
        "surprised" => "😮",
        "sad" => "😢",
        "angry" => "😠",
        _ => "🙂",
    }
}

/// Load a chat's timeline, oldest first.
pub async fn read_timeline(
    client: &TeamsClient,
    chat_id: &str,
    limit: usize,
) -> Result<Vec<MessageView>> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages?pageSize={}&view=msnp24Equivalent",
        client.chat_service_url(),
        chat_id,
        limit
    );
    let resp = match client.chat_get(&url).await {
        Ok(r) => r,
        // A 1:1 chat nobody has written in yet, or your own notes chat
        // before its first note, does not exist; the first message creates
        // it, so it opens empty.
        Err(e)
            if e.to_string().contains("HTTP 404")
                && (chat_id.ends_with("@unq.gbl.spaces") || chat_id == "48:notes") =>
        {
            return Ok(Vec::new())
        }
        Err(e) => return Err(e),
    };
    let v: serde_json::Value = resp.json().await.context("Messages reply")?;
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    let own_name = client.display_name().unwrap_or_default();
    let mut out: Vec<MessageView> = v
        .get("messages")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter_map(|m| view_of(m, &me, &own_name))
        .collect();
    // The service lists by last change (a reaction or edit moves a message
    // up), so order by arrival time; ids are arrival milliseconds.
    out.sort_by(|a, b| {
        let key = |m: &MessageView| m.id.parse::<u64>().unwrap_or(0);
        key(a).cmp(&key(b)).then_with(|| a.time.cmp(&b.time))
    });
    Ok(out)
}

fn view_of(m: &serde_json::Value, me: &str, own_name: &str) -> Option<MessageView> {
    let s = |p: &str| {
        m.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let kind = s("/messagetype");
    let sender_mri = s("/from")
        .rsplit("/contacts/")
        .next()
        .unwrap_or_default()
        .to_string();
    let mine = !me.is_empty() && sender_mri == me;
    let mut sender = s("/imdisplayname");
    if sender.is_empty() && mine {
        sender = own_name.to_string();
    }
    let time = {
        let t = s("/originalarrivaltime");
        if t.is_empty() {
            s("/composetime")
        } else {
            t
        }
    };
    let base = MessageView {
        id: s("/id"),
        client_message_id: s("/clientmessageid"),
        kind: "message".into(),
        sender,
        sender_mri,
        time,
        mine,
        html: String::new(),
        text: String::new(),
        edited: false,
        deleted: false,
        reactions: Vec::new(),
        images: Vec::new(),
        call_state: String::new(),
        call_seconds: 0,
        seen: false,
        first_unread: false,
        files: Vec::new(),
        root_id: s("/rootMessageId"),
    };
    if kind == "Event/Call" {
        let content = s("/content");
        // Only the end of a call goes in the timeline, as in Teams.
        if !content.contains("<ended/>") {
            return None;
        }
        let seconds = content
            .split("<duration>")
            .nth(1)
            .and_then(|r| r.split('<').next())
            .and_then(|d| d.trim().parse().ok())
            .unwrap_or(0);
        let state = if seconds == 0 { "missed" } else { "ended" };
        return Some(MessageView {
            kind: "call".into(),
            call_state: state.into(),
            call_seconds: seconds,
            ..base
        });
    }
    if !(kind == "Text" || kind.starts_with("RichText")) {
        return None;
    }
    let props = m.get("properties");
    let deleted = props.and_then(|p| p.get("deletetime")).is_some();
    let edited = props
        .and_then(|p| p.get("edittime"))
        .is_some_and(|e| !e.is_null() && e != "");
    let content = s("/content");
    let reactions = props
        .and_then(|p| p.get("emotions"))
        .map(|e| reactions_of(e, me))
        .unwrap_or_default();
    let text = super::strip_html(&content).trim().to_string();
    // Teams shows "This message has been deleted" to its sender only (and
    // only right after deleting; the app decides that); for everyone else
    // the message just disappears.
    let images = if deleted {
        Vec::new()
    } else {
        inline_images(&content)
    };
    let files = if deleted {
        Vec::new()
    } else {
        props
            .and_then(|p| p.get("files"))
            .map(super::files::parse_files)
            .unwrap_or_default()
    };
    if (deleted && !mine) || (!deleted && text.is_empty() && images.is_empty() && files.is_empty())
    {
        return None;
    }
    let text = if text.is_empty() && !images.is_empty() {
        "Image".to_string()
    } else {
        text
    };
    Some(MessageView {
        images,
        files,
        html: if deleted {
            String::new()
        } else {
            sanitize_html(&content)
        },
        text: if deleted { String::new() } else { text },
        edited,
        deleted,
        reactions,
        ..base
    })
}

fn reactions_of(e: &serde_json::Value, me: &str) -> Vec<Reaction> {
    // Sent either as a JSON array or as a string holding one.
    let parsed;
    let list = match e {
        serde_json::Value::String(s) => {
            parsed = serde_json::from_str::<serde_json::Value>(s).unwrap_or_default();
            &parsed
        }
        other => other,
    };
    list.as_array()
        .into_iter()
        .flatten()
        .filter_map(|r| {
            let key = r.get("key")?.as_str()?.to_string();
            let users = r
                .get("users")
                .and_then(|u| u.as_array())
                .cloned()
                .unwrap_or_default();
            if users.is_empty() {
                return None;
            }
            let mine = users
                .iter()
                .any(|u| u.get("mri").and_then(|m| m.as_str()) == Some(me));
            Some(Reaction {
                emoji: reaction_emoji(&key).to_string(),
                key,
                count: users.len(),
                mine,
            })
        })
        .collect()
}

/// Reduce Teams message HTML to the subset Qt's rich text renders safely:
/// paragraphs, line breaks, emphasis, lists, code, quotes and links. Emoji
/// images become their alt text, other tags and all attributes except a
/// link's href are dropped, and bare URLs become links.
pub fn sanitize_html(html: &str) -> String {
    const KEEP: [&str; 15] = [
        "p",
        "br",
        "b",
        "strong",
        "i",
        "em",
        "u",
        "s",
        "a",
        "ul",
        "ol",
        "li",
        "code",
        "pre",
        "blockquote",
    ];
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    let mut in_link = 0usize;
    while let Some(start) = rest.find('<') {
        out.push_str(&linkify(&rest[..start], in_link > 0));
        let Some(end) = rest[start..].find('>') else {
            out.push_str(&escape(&rest[start..]));
            return out;
        };
        let tag = &rest[start + 1..start + end];
        rest = &rest[start + end + 1..];
        let closing = tag.starts_with('/');
        let name: String = tag
            .trim_start_matches('/')
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect::<String>()
            .to_ascii_lowercase();
        // Script and style elements are dropped with their content.
        if !closing && (name == "script" || name == "style") {
            let close = format!("</{name}");
            match rest.to_ascii_lowercase().find(&close) {
                Some(i) => {
                    rest = &rest[i..];
                    if let Some(e) = rest.find('>') {
                        rest = &rest[e + 1..];
                    }
                }
                None => rest = "",
            }
            continue;
        }
        if name == "img" {
            // Inline pictures are shown by the client from `images`.
            if tag.contains("AMSImage") {
                continue;
            }
            if let Some(alt) = attr(tag, "alt") {
                out.push_str(&escape(&alt));
            }
            continue;
        }
        if !KEEP.contains(&name.as_str()) {
            continue;
        }
        if name == "a" {
            if closing {
                if in_link > 0 {
                    in_link -= 1;
                    out.push_str("</a>");
                }
            } else if let Some(href) = attr(tag, "href").filter(|h| safe_url(h)) {
                in_link += 1;
                out.push_str(&format!("<a href=\"{}\">", escape(&href)));
            }
            continue;
        }
        out.push('<');
        if closing {
            out.push('/');
        }
        out.push_str(&name);
        if name == "br" {
            out.push_str(" /");
        }
        out.push('>');
    }
    out.push_str(&linkify(rest, in_link > 0));
    while in_link > 0 {
        out.push_str("</a>");
        in_link -= 1;
    }
    out
}

/// Teams inline images: `<img itemtype="…/AMSImage" src="https://*.asm.skype.com/…">`.
/// Only AMS hosts are accepted, since fetching them sends our token.
fn inline_images(html: &str) -> Vec<InlineImage> {
    let mut out = Vec::new();
    let mut rest = html;
    while let Some(i) = rest.find("<img") {
        let end = rest[i..].find('>').map(|e| i + e).unwrap_or(rest.len());
        let tag = &rest[i..end];
        rest = &rest[end..];
        if !tag.contains("AMSImage") {
            continue;
        }
        let Some(url) = attr(tag, "src") else {
            continue;
        };
        if !is_ams_url(&url) {
            continue;
        }
        let id = attr(tag, "itemid").unwrap_or_default();
        if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
            continue;
        }
        let num = |k: &str| attr(tag, k).and_then(|v| v.parse().ok()).unwrap_or(0);
        out.push(InlineImage {
            id,
            url,
            width: num("width"),
            height: num("height"),
            local_path: String::new(),
        });
    }
    out
}

/// Whether a URL is on Teams' media store (where our token may go).
pub fn is_ams_url(url: &str) -> bool {
    url::Url::parse(url).is_ok_and(|u| {
        u.scheme() == "https" && u.host_str().is_some_and(|h| h.ends_with(".asm.skype.com"))
    })
}

/// Download an inline image (AMS object view).
pub async fn fetch_image(client: &TeamsClient, url: &str) -> Result<Vec<u8>> {
    anyhow::ensure!(is_ams_url(url), "Not a Teams media URL");
    client.ams_get(url).await
}

fn safe_url(u: &str) -> bool {
    let l = u.trim().to_ascii_lowercase();
    l.starts_with("https://") || l.starts_with("http://") || l.starts_with("mailto:")
}

fn attr(tag: &str, name: &str) -> Option<String> {
    let lower = tag.to_ascii_lowercase();
    let i = lower.find(&format!("{name}="))?;
    let rest = &tag[i + name.len() + 1..];
    let (quote, rest) = match rest.chars().next()? {
        q @ ('"' | '\'') => (Some(q), &rest[1..]),
        _ => (None, rest),
    };
    let value = match quote {
        Some(q) => rest.split(q).next()?,
        None => rest.split(|c: char| c.is_whitespace() || c == '>').next()?,
    };
    Some(super::strip_html(value))
}

/// Escape text that is going into HTML. Input text is already entity
/// encoded by Teams, so only stray `<` / `>` / `"` need it.
fn escape(t: &str) -> String {
    t.replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Turn bare http(s) URLs in a text run into links.
fn linkify(text: &str, inside_link: bool) -> String {
    if inside_link {
        return text.to_string();
    }
    let mut out = String::new();
    let mut rest = text;
    while let Some(i) = rest
        .find("http://")
        .into_iter()
        .chain(rest.find("https://"))
        .min()
    {
        out.push_str(&rest[..i]);
        let url_len = rest[i..]
            .find(|c: char| c.is_whitespace() || c == '<' || c == '"')
            .unwrap_or(rest.len() - i);
        let mut url = &rest[i..i + url_len];
        // Trailing punctuation belongs to the sentence.
        while url.ends_with(['.', ',', ')', '!', '?', ';', ':']) {
            url = &url[..url.len() - 1];
        }
        out.push_str(&format!("<a href=\"{0}\">{0}</a>", url));
        rest = &rest[i + url.len()..];
    }
    out.push_str(rest);
    out
}

/// Add (`on`) or remove our reaction `key` on a message.
pub async fn set_reaction(
    client: &TeamsClient,
    chat_id: &str,
    message_id: &str,
    key: &str,
    on: bool,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}/properties?name=emotions",
        client.chat_service_url(),
        chat_id,
        message_id
    );
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let (method, body) = if on {
        (
            reqwest::Method::PUT,
            serde_json::json!({ "emotions": { "key": key, "value": now } }),
        )
    } else {
        (
            reqwest::Method::DELETE,
            serde_json::json!({ "emotions": { "key": key } }),
        )
    };
    client.chat_request(method, &url, &body).await?;
    Ok(())
}

/// Replace the text of one of our messages.
pub async fn edit_message(
    client: &TeamsClient,
    chat_id: &str,
    message_id: &str,
    text: &str,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}",
        client.chat_service_url(),
        chat_id,
        message_id
    );
    let body = serde_json::json!({
        "content": format!("<p>{}</p>", html_escape(text)),
        "messagetype": "RichText/Html",
        "contenttype": "text",
    });
    client
        .chat_request(reqwest::Method::PUT, &url, &body)
        .await?;
    Ok(())
}

/// Delete one of our messages.
pub async fn delete_message(client: &TeamsClient, chat_id: &str, message_id: &str) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}",
        client.chat_service_url(),
        chat_id,
        message_id
    );
    client
        .chat_request(reqwest::Method::DELETE, &url, &serde_json::json!({}))
        .await?;
    Ok(())
}

/// Escape plain text for a message body (line breaks become <br>).
fn html_escape(t: &str) -> String {
    t.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\n', "<br>")
}

/// Mark a chat read up to `last_message_id` (our consumption horizon; the
/// other side sees it as a read receipt, other clients clear the unread).
pub async fn mark_read(
    client: &TeamsClient,
    chat_id: &str,
    last_message_id: &str,
    last_client_message_id: &str,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/properties?name=consumptionhorizon",
        client.chat_service_url(),
        chat_id
    );
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let body = serde_json::json!({
        "consumptionhorizon": format!("{last_message_id};{now};{last_client_message_id}")
    });
    client
        .chat_request(reqwest::Method::PUT, &url, &body)
        .await?;
    Ok(())
}

/// How far the other members of a chat have read: the highest message id
/// in anyone else's consumption horizon. Teams only publishes horizons for
/// members who have read receipts on, so `None` also means "not shared".
pub async fn peer_read_horizon(client: &TeamsClient, chat_id: &str) -> Result<Option<u64>> {
    let url = format!(
        "{}/v1/threads/{}/consumptionhorizons",
        client.chat_service_url(),
        chat_id
    );
    let text = client
        .chat_get(&url)
        .await?
        .text()
        .await
        .context("Consumption horizons reply")?;
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    Ok(peer_horizon(&text, &me))
}

/// The highest read message id among members other than `me` in a
/// `/threads/{id}/consumptionhorizons` reply ("msgId;time;clientMsgId").
pub fn peer_horizon(json: &str, me: &str) -> Option<u64> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    v.get("consumptionhorizons")?
        .as_array()?
        .iter()
        .filter(|h| {
            h.get("id")
                .and_then(|i| i.as_str())
                .is_some_and(|i| !i.eq_ignore_ascii_case(me))
        })
        .filter_map(|h| {
            h.get("consumptionhorizon")?
                .as_str()?
                .split(';')
                .next()?
                .parse()
                .ok()
        })
        .max()
}

/// How far you had read a chat: the message id in your consumption horizon.
pub async fn my_read_horizon(client: &TeamsClient, chat_id: &str) -> Result<Option<u64>> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        chat_id
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Conversation reply")?;
    Ok(v.pointer("/properties/consumptionhorizon")
        .and_then(|h| h.as_str())
        .and_then(|h| h.split(';').next())
        .and_then(|h| h.parse().ok()))
}

/// Flag the first message from someone else after `horizon` (your read
/// position when the chat was opened).
pub fn mark_first_unread(timeline: &mut [MessageView], horizon: Option<u64>) {
    for m in timeline.iter_mut() {
        m.first_unread = false;
    }
    let Some(h) = horizon else { return };
    if let Some(m) = timeline
        .iter_mut()
        .find(|m| !m.mine && m.id.parse::<u64>().is_ok_and(|id| id > h))
    {
        m.first_unread = true;
    }
}

/// Mark your messages up to `horizon` as seen.
pub fn apply_seen(timeline: &mut [MessageView], horizon: Option<u64>) {
    let Some(h) = horizon else { return };
    for m in timeline.iter_mut().filter(|m| m.mine) {
        m.seen = m.id.parse::<u64>().is_ok_and(|id| id <= h);
    }
}

/// Mark a chat read up to its newest message (for "Mark all as read").
pub async fn mark_chat_read_to_latest(client: &TeamsClient, chat_id: &str) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        chat_id
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Conversation reply")?;
    let last = v.get("lastMessage").context("Chat has no messages")?;
    let id = last
        .get("id")
        .and_then(|i| i.as_str())
        .context("No message id")?;
    let client_id = last
        .get("clientmessageid")
        .and_then(|i| i.as_str())
        .unwrap_or(id);
    mark_read(client, chat_id, id, client_id).await
}

/// Whether read receipts are on (the `readReceiptsEnabled` user property;
/// Teams treats a missing value as on).
pub async fn read_receipts_enabled(client: &TeamsClient) -> Result<bool> {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("User properties reply")?;
    Ok(v.get("readReceiptsEnabled")
        .and_then(|r| r.as_str())
        .is_none_or(|r| !r.eq_ignore_ascii_case("false")))
}

/// Turn read receipts on or off, as Teams' Settings toggle does.
pub async fn set_read_receipts_enabled(client: &TeamsClient, on: bool) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/properties?name=readReceiptsEnabled",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "readReceiptsEnabled": if on { "true" } else { "false" } }),
        )
        .await?;
    Ok(())
}

/// Turn the rich text Qt's editor produces (`getFormattedText`: a full HTML
/// document with styled spans) into the small, safe HTML Teams sends:
/// paragraphs, line breaks, b/i/u/s, lists and http(s) links. Everything
/// else (head, styles, fonts, colours, scripts) is dropped; text keeps the
/// escaping Qt gave it.
pub fn teams_html_from_editor(qt: &str) -> String {
    let body = match (qt.find("<body"), qt.rfind("</body>")) {
        (Some(b), Some(e)) if b < e => {
            let start = qt[b..].find('>').map(|i| b + i + 1).unwrap_or(b);
            &qt[start..e]
        }
        _ => qt,
    };
    let mut out = String::new();
    // For each open <span>, the tags it opened (closed in reverse).
    let mut spans: Vec<Vec<&'static str>> = Vec::new();
    let mut rest = body;
    while let Some(lt) = rest.find('<') {
        let text = &rest[..lt];
        out.push_str(&text.replace(['\n', '\r'], ""));
        let Some(gt) = rest[lt..].find('>') else {
            break;
        };
        let tag = &rest[lt + 1..lt + gt];
        rest = &rest[lt + gt + 1..];
        let closing = tag.starts_with('/');
        let name: String = tag
            .trim_start_matches('/')
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect::<String>()
            .to_ascii_lowercase();
        let style = editor_attr(tag, "style")
            .unwrap_or_default()
            .to_ascii_lowercase()
            .replace(' ', "");
        match (name.as_str(), closing) {
            ("p", false) => out.push_str("<p>"),
            ("p", true) => out.push_str("</p>"),
            ("br", _) => out.push_str("<br>"),
            ("ul" | "ol" | "li", false) => {
                out.push('<');
                out.push_str(&name);
                out.push('>');
            }
            ("ul" | "ol" | "li", true) => {
                out.push_str("</");
                out.push_str(&name);
                out.push('>');
            }
            ("b" | "strong", _) => out.push_str(if closing { "</b>" } else { "<b>" }),
            ("i" | "em", _) => out.push_str(if closing { "</i>" } else { "<i>" }),
            ("u", _) => out.push_str(if closing { "</u>" } else { "<u>" }),
            ("s" | "strike" | "del", _) => out.push_str(if closing { "</s>" } else { "<s>" }),
            ("span", false) => {
                let mut opened = Vec::new();
                let weight = style
                    .split(';')
                    .find_map(|d| d.strip_prefix("font-weight:"))
                    .and_then(|w| w.parse::<u32>().ok())
                    .unwrap_or(400);
                if weight >= 600 || style.contains("font-weight:bold") {
                    opened.push("b");
                }
                if style.contains("font-style:italic") {
                    opened.push("i");
                }
                if style.contains("underline") {
                    opened.push("u");
                }
                if style.contains("line-through") {
                    opened.push("s");
                }
                for t in &opened {
                    out.push('<');
                    out.push_str(t);
                    out.push('>');
                }
                spans.push(opened);
            }
            ("span", true) => {
                for t in spans.pop().unwrap_or_default().iter().rev() {
                    out.push_str("</");
                    out.push_str(t);
                    out.push('>');
                }
            }
            ("a", false) => match editor_attr(tag, "href")
                .filter(|h| h.starts_with("https://") || h.starts_with("http://"))
            {
                Some(href) => {
                    out.push_str("<a href=\"");
                    out.push_str(&href.replace('"', "&quot;"));
                    out.push_str("\">");
                }
                None => out.push_str("<a>"),
            },
            ("a", true) => out.push_str("</a>"),
            _ => {}
        }
    }
    out.push_str(&rest.replace(['\n', '\r'], ""));
    out.replace("<p></p>", "")
        .replace("<p><br></p>", "")
        .trim()
        .to_string()
}

/// An attribute's value from a tag's text (`name="value"`).
fn editor_attr(tag: &str, name: &str) -> Option<String> {
    let lower = tag.to_ascii_lowercase();
    let key = format!("{name}=\"");
    let i = lower.find(&key)? + key.len();
    let end = tag[i..].find('"')? + i;
    Some(tag[i..end].to_string())
}

/// Whether editor HTML carries any formatting worth sending as rich text.
pub fn editor_has_formatting(qt: &str) -> bool {
    let h = teams_html_from_editor(qt);
    ["<b>", "<i>", "<u>", "<s>", "<ul>", "<ol>", "<a href"]
        .iter()
        .any(|t| h.contains(t))
}

/// Your favourite chats, in Teams' order: the `favorites` user property
/// (`{"48:notes":1, "19:…":2}`), sorted by its values.
pub async fn favorites(client: &TeamsClient) -> Result<Vec<String>> {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let text = client
        .chat_get(&url)
        .await?
        .text()
        .await
        .context("User properties reply")?;
    Ok(favorites_from_properties(&text))
}

/// The favourites list from a `/users/ME/properties` reply; its
/// `favorites` value is itself JSON text.
pub fn favorites_from_properties(json: &str) -> Vec<String> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let Some(map) = v
        .get("favorites")
        .and_then(|f| f.as_str())
        .and_then(|f| serde_json::from_str::<serde_json::Map<String, serde_json::Value>>(f).ok())
    else {
        return Vec::new();
    };
    let mut list: Vec<(f64, String)> = map
        .into_iter()
        .map(|(id, order)| (order.as_f64().unwrap_or(f64::MAX), id))
        .collect();
    list.sort_by(|a, b| a.0.total_cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
    list.into_iter().map(|(_, id)| id).collect()
}

/// Chats with messages from someone else newer than our read horizon.
pub async fn unread_chat_ids(client: &TeamsClient) -> Result<Vec<String>> {
    let url = format!(
        "{}/v1/users/ME/conversations?view=msnp24Equivalent&pageSize=100",
        client.chat_service_url()
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Conversations reply")?;
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    Ok(v.get("conversations")
        .and_then(|c| c.as_array())
        .into_iter()
        .flatten()
        .filter(|c| is_unread(c, &me))
        .filter_map(|c| c.get("id").and_then(|i| i.as_str()).map(str::to_string))
        .collect())
}

fn is_unread(conv: &serde_json::Value, me: &str) -> bool {
    let id = conv.get("id").and_then(|i| i.as_str()).unwrap_or_default();
    if !id.starts_with("19:") {
        return false;
    }
    let Some(last) = conv.get("lastMessage") else {
        return false;
    };
    let kind = last
        .get("messagetype")
        .and_then(|k| k.as_str())
        .unwrap_or_default();
    if !(kind == "Text" || kind.starts_with("RichText")) {
        return false;
    }
    let from = last
        .get("from")
        .and_then(|f| f.as_str())
        .unwrap_or_default();
    if !me.is_empty() && from.ends_with(me) {
        return false;
    }
    let last_id: u64 = last
        .get("id")
        .and_then(|i| i.as_str())
        .and_then(|i| i.parse().ok())
        .unwrap_or(0);
    let horizon: u64 = conv
        .pointer("/properties/consumptionhorizon")
        .and_then(|h| h.as_str())
        .and_then(|h| h.split(';').next())
        .and_then(|h| h.parse().ok())
        .unwrap_or(0);
    last_id > horizon
}

#[cfg(test)]
mod tests {
    #[test]
    fn editor_html_becomes_teams_html() {
        let qt = r#"<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN"><html><head><meta name="qrichtext" content="1" /><style type="text/css">p, li { white-space: pre-wrap; }</style></head><body style=" font-family:'Selawik'; font-size:14px;">
<p style=" margin-top:0px;">Hello <span style=" font-weight:700;">bold</span> and <span style=" font-style:italic; text-decoration: underline;">both</span> &lt;tag&gt;</p>
<ul style="margin-top: 0px;"><li style=" margin-top:0px;">one</li></ul>
<p><a href="https://example.com/x"><span style=" text-decoration: underline; color:#5b5fc7;">link</span></a> <a href="javascript:alert(1)">bad</a><script>evil()</script></p></body></html>"#;
        let h = super::teams_html_from_editor(qt);
        assert_eq!(
            h,
            "<p>Hello <b>bold</b> and <i><u>both</u></i> &lt;tag&gt;</p><ul><li>one</li></ul><p><a href=\"https://example.com/x\"><u>link</u></a> <a>bad</a>evil()</p>"
        );
        assert!(super::editor_has_formatting(qt));
        let plain = r#"<html><body><p>just text</p></body></html>"#;
        assert!(!super::editor_has_formatting(plain));
    }

    #[test]
    fn favorites_come_in_teams_order() {
        let json = r#"{"favorites":"{\"19:b@unq.gbl.spaces\":2,\"48:notes\":1}","locale":"en-us"}"#;
        assert_eq!(
            super::favorites_from_properties(json),
            ["48:notes", "19:b@unq.gbl.spaces"]
        );
        assert!(super::favorites_from_properties(r#"{"locale":"en-us"}"#).is_empty());
        assert!(super::favorites_from_properties("nope").is_empty());
    }

    #[test]
    fn first_unread_is_the_first_message_from_others_after_the_horizon() {
        let mk = |id: &str, mine: bool| super::MessageView {
            id: id.into(),
            client_message_id: String::new(),
            kind: "message".into(),
            sender: String::new(),
            sender_mri: String::new(),
            time: String::new(),
            mine,
            html: String::new(),
            text: String::new(),
            edited: false,
            deleted: false,
            reactions: vec![],
            images: vec![],
            call_state: String::new(),
            call_seconds: 0,
            seen: false,
            first_unread: false,
            files: vec![],
            root_id: String::new(),
        };
        let mut t = vec![
            mk("100", false),
            mk("200", true),
            mk("300", false),
            mk("400", false),
        ];
        super::mark_first_unread(&mut t, Some(150));
        assert_eq!(
            t.iter().map(|m| m.first_unread).collect::<Vec<_>>(),
            [false, false, true, false]
        );
        super::mark_first_unread(&mut t, Some(400));
        assert!(t.iter().all(|m| !m.first_unread));
        super::mark_first_unread(&mut t, None);
        assert!(t.iter().all(|m| !m.first_unread));
    }

    #[test]
    fn peer_horizon_ignores_my_own_entry() {
        let json = r#"{"consumptionhorizons":[
            {"id":"8:orgid:me","consumptionhorizon":"900;1;a"},
            {"id":"8:orgid:peer","consumptionhorizon":"500;1;b"}]}"#;
        assert_eq!(super::peer_horizon(json, "8:orgid:me"), Some(500));
        assert_eq!(
            super::peer_horizon(
                r#"{"consumptionhorizons":[{"id":"8:orgid:me","consumptionhorizon":"900;1;a"}]}"#,
                "8:orgid:me"
            ),
            None
        );
        assert_eq!(super::peer_horizon("nonsense", "8:orgid:me"), None);
    }

    use super::*;

    #[test]
    fn sanitizer_keeps_formatting_and_drops_the_rest() {
        assert_eq!(
            sanitize_html(
                r#"<p>Hi <b>there</b> <span style="x">you</span><script>bad()</script></p>"#
            ),
            "<p>Hi <b>there</b> you</p>"
        );
        assert_eq!(
            sanitize_html(
                r#"<a href="javascript:alert(1)">x</a><a href="https://ok.example">ok</a>"#
            ),
            r#"x<a href="https://ok.example">ok</a>"#
        );
        assert_eq!(
            sanitize_html(
                r#"<p><img itemtype="http://schema.skype.com/Emoji" alt="🎉" src="x"></p>"#
            ),
            "<p>🎉</p>"
        );
        assert_eq!(sanitize_html("line<br>two"), "line<br />two");
    }

    #[test]
    fn unread_compares_the_last_message_with_the_horizon() {
        let conv = |from: &str, last: &str, horizon: Option<&str>| {
            let mut c = serde_json::json!({"id": "19:a_b@unq.gbl.spaces",
                "lastMessage": {"id": last, "messagetype": "RichText/Html", "from": format!("https://x/contacts/{from}")},
                "properties": {}});
            if let Some(h) = horizon {
                c["properties"]["consumptionhorizon"] = serde_json::json!(format!("{h};1;{h}"));
            }
            c
        };
        assert!(is_unread(
            &conv("8:orgid:them", "200", Some("100")),
            "8:orgid:me"
        ));
        assert!(!is_unread(
            &conv("8:orgid:them", "200", Some("200")),
            "8:orgid:me"
        ));
        assert!(!is_unread(
            &conv("8:orgid:me", "200", Some("100")),
            "8:orgid:me"
        ));
        assert!(is_unread(&conv("8:orgid:them", "200", None), "8:orgid:me"));
    }

    #[test]
    fn inline_images_only_from_teams_media() {
        let html = r#"<p><img src="https://us-api.asm.skype.com/v1/objects/0-wus-d5-02b/views/imgo" itemtype="http://schema.skype.com/AMSImage" width="320" height="180" alt="image" itemid="0-wus-d5-02b"></p>"#;
        let imgs = inline_images(html);
        assert_eq!(imgs.len(), 1);
        assert_eq!((imgs[0].width, imgs[0].height), (320, 180));
        assert_eq!(imgs[0].id, "0-wus-d5-02b");
        // Dropped from the HTML (rendered separately).
        assert_eq!(sanitize_html(html), "<p></p>");
        let evil = html.replace("us-api.asm.skype.com", "evil.example");
        assert!(inline_images(&evil).is_empty());
        let traversal = html.replace(r#"itemid="0-wus-d5-02b""#, r#"itemid="../../x""#);
        assert!(inline_images(&traversal).is_empty());
        assert!(!is_ams_url("https://asm.skype.com.evil.example/x"));
    }

    #[test]
    fn edit_text_is_escaped() {
        assert_eq!(
            html_escape("a < b & \"c\"\nd"),
            "a &lt; b &amp; &quot;c&quot;<br>d"
        );
    }

    #[test]
    fn bare_urls_become_links() {
        assert_eq!(
            sanitize_html("<p>see https://example.com.</p>"),
            r#"<p>see <a href="https://example.com">https://example.com</a>.</p>"#
        );
        // Not inside an existing link.
        assert_eq!(
            sanitize_html(r#"<a href="https://a.example">https://a.example</a>"#),
            r#"<a href="https://a.example">https://a.example</a>"#
        );
    }

    #[test]
    fn channel_replies_name_their_post() {
        let reply = serde_json::json!({
            "id": "1793905132592", "rootMessageId": "1793889784763",
            "messagetype": "RichText/Html", "content": "<p>a reply</p>",
            "from": "https://x/v1/users/ME/contacts/8:orgid:them", "imdisplayname": "Them",
            "originalarrivaltime": "2026-11-05T18:58:00Z"
        });
        let v = view_of(&reply, "8:orgid:me", "me").unwrap();
        assert_eq!(v.root_id, "1793889784763");
        assert_ne!(v.root_id, v.id);
        let chat = serde_json::json!({
            "id": "5", "messagetype": "Text", "content": "hi",
            "from": "https://x/v1/users/ME/contacts/8:orgid:them",
            "originalarrivaltime": "2026-11-05T18:58:00Z"
        });
        assert_eq!(view_of(&chat, "8:orgid:me", "me").unwrap().root_id, "");
    }

    #[test]
    fn reactions_and_call_events() {
        let m = serde_json::json!({
            "id": "1", "messagetype": "RichText/Html", "content": "<p>hello</p>",
            "from": "https://x/v1/users/ME/contacts/8:orgid:me", "imdisplayname": "",
            "originalarrivaltime": "2026-11-05T03:55:00Z",
            "properties": {"emotions": [{"key": "like", "users": [{"mri": "8:orgid:them"}, {"mri": "8:orgid:me"}]}],
                           "edittime": "1793858969344"}
        });
        let v = view_of(&m, "8:orgid:me", "OST Test 1").unwrap();
        assert!(v.mine && v.edited);
        assert_eq!(v.sender, "OST Test 1");
        assert_eq!(
            v.reactions,
            vec![Reaction {
                key: "like".into(),
                emoji: "👍".into(),
                count: 2,
                mine: true
            }]
        );

        let call = serde_json::json!({
            "id": "2", "messagetype": "Event/Call", "from": "https://x/contacts/8:orgid:me",
            "content": "<ended/><partlist><part><duration>189</duration></part></partlist>",
            "originalarrivaltime": "2026-11-05T04:00:00Z"
        });
        let c = view_of(&call, "8:orgid:me", "me").unwrap();
        assert_eq!(
            (c.kind.as_str(), c.call_state.as_str(), c.call_seconds),
            ("call", "ended", 189)
        );
        let started = serde_json::json!({"messagetype": "Event/Call", "content": "<partlist/>"});
        assert!(view_of(&started, "x", "y").is_none());
    }
}
