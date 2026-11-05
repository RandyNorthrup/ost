//! Messages as the Teams clients show them: formatted text, reactions,
//! edits and deletions, and call events in the timeline.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One reaction on a message.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Reaction {
    /// Teams' key, e.g. `like`, `heart`.
    pub key: String,
    /// The emoji to show.
    pub emoji: String,
    pub count: usize,
    /// Whether we reacted with this one.
    pub mine: bool,
}

/// A timeline item.
#[derive(Debug, Clone, serde::Serialize)]
pub struct MessageView {
    pub id: String,
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
    /// For call events: "ended" (with duration) or "missed".
    pub call_state: String,
    pub call_seconds: u64,
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
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Messages reply")?;
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
        call_state: String::new(),
        call_seconds: 0,
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
    if !deleted && text.is_empty() {
        return None;
    }
    Some(MessageView {
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

#[cfg(test)]
mod tests {
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
