//! Messages as the Teams clients show them: formatted text, reactions,
//! edits and deletions, and call events in the timeline.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One reaction pill on a message: the reactions sharing an emoji whatever
/// their skin tone (Teams' `diverseEmotions` item).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Reaction {
    /// Teams' common key, e.g. `like`, `heart` (`-tone{n}` dropped).
    pub key: String,
    /// The emoji to show.
    pub emoji: String,
    pub count: usize,
    /// Whether we reacted with this one.
    pub mine: bool,
    /// The exact keys the pill shows, at most three (Teams' `Ne`).
    pub variants: Vec<String>,
    /// How many exact keys there are (for Teams' width estimate).
    pub kinds: usize,
    /// The exact key we reacted with, if any (removing deletes that one).
    pub my_key: String,
    /// Who reacted, newest first.
    pub users: Vec<Reactor>,
}

/// Someone who reacted with an emoji.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Reactor {
    pub mri: String,
    /// Their display name, once known.
    pub name: String,
    /// The exact key, with its skin tone.
    pub key: String,
    /// When, in epoch milliseconds.
    pub time: i64,
    /// Whether this is us.
    pub me: bool,
}

/// The variants a pill shows (Teams' `Ne`): the first three in arrival
/// order; when there are more and ours has a skin tone, the first one
/// without a tone gives way.
fn shown_variants(all: &[String], mine: &str) -> Vec<String> {
    let toned = |k: &str| common_key(k) != k;
    let mut out = all.to_vec();
    if all.len() > 3
        && !mine.is_empty()
        && toned(mine)
        && let Some(i) = all.iter().position(|k| !toned(k))
        && i < 3
    {
        out.remove(i);
    }
    out.truncate(3);
    out
}

/// Teams' common key of an emoticon id: without a final `-tone{digit}`,
/// with 1 to 40 characters before it (`/^(.{1,40})-tone\d$/`).
pub fn common_key(key: &str) -> &str {
    match key
        .strip_suffix(|c: char| c.is_ascii_digit())
        .and_then(|k| k.strip_suffix("-tone"))
    {
        Some(base) if !base.is_empty() && base.chars().count() <= 40 => base,
        _ => key,
    }
}

/// One card in a message: its content type (Teams' supported set, e.g.
/// `application/vnd.microsoft.card.adaptive`) and its JSON content.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Card {
    pub content_type: String,
    pub content: serde_json::Value,
    #[serde(default)]
    pub app_id: String,
}

/// The SWIFT payload of a `RichText/Media_Card` message: `<Swift b64="…"/>`
/// (base64 UTF-8 JSON), else the first text child of `<URIObject>` when it
/// is JSON (Teams 49385). Element and attribute names match case-
/// insensitively.
pub fn swift_payload(content: &str) -> Option<serde_json::Value> {
    use base64::Engine;
    let lower = content.to_ascii_lowercase();
    if let Some(i) = lower.find("<swift") {
        let tag_end = lower[i..].find('>').map(|e| i + e)?;
        let tag = &content[i..tag_end];
        let tag_lower = &lower[i..tag_end];
        if let Some(a) = tag_lower.find("b64=") {
            let rest = &tag[a + 4..];
            let quote = rest.chars().next()?;
            if quote == '"' || quote == '\'' {
                let value = &rest[1..];
                let end = value.find(quote)?;
                let b64: String = value[..end]
                    .chars()
                    .filter(|c| !c.is_whitespace())
                    .collect();
                let bytes = base64::engine::general_purpose::STANDARD
                    .decode(b64.as_bytes())
                    .or_else(|_| {
                        base64::engine::general_purpose::STANDARD_NO_PAD
                            .decode(b64.trim_end_matches('=').as_bytes())
                    })
                    .ok()?;
                return serde_json::from_slice(&bytes).ok();
            }
        }
    }
    // The fallback: <URIObject …>{json}</URIObject> (escaped or URI-encoded).
    let start = lower.find("<uriobject")?;
    let open_end = lower[start..].find('>').map(|e| start + e + 1)?;
    let close = lower[open_end..]
        .find('<')
        .map(|e| open_end + e)
        .unwrap_or(content.len());
    let text = super::strip_html(content[open_end..close].trim());
    if text.trim_start().starts_with('{') {
        return serde_json::from_str(&text).ok();
    }
    let decoded = percent_decode(&text);
    decoded
        .trim_start()
        .starts_with('{')
        .then(|| serde_json::from_str(&decoded).ok())
        .flatten()
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(b) = u8::from_str_radix(&s[i + 1..i + 3], 16)
        {
            out.push(b);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// The cards of a SWIFT payload, its text, and whether it is a carousel.
pub fn swift_cards(swift: &serde_json::Value) -> (Vec<Card>, String, bool) {
    let cards = swift
        .get("attachments")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .filter_map(|a| {
            let content_type = a.get("contentType")?.as_str()?.to_string();
            let content = match a.get("content")? {
                serde_json::Value::String(s) => serde_json::from_str(s).unwrap_or_default(),
                v => v.clone(),
            };
            Some(Card {
                content_type,
                content,
                app_id: a
                    .get("appId")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
            })
        })
        .collect();
    let text = swift
        .get("text")
        .and_then(|t| t.as_str())
        .unwrap_or_default()
        .to_string();
    let carousel = swift.get("type").and_then(|t| t.as_str()) == Some("message/card.carousel");
    (cards, text, carousel)
}

/// The announcement banner card's content type.
pub const ANNOUNCEMENT_BANNER: &str = "application/vnd.microsoft.teams.messaging-announcementBanner";

/// A channel announcement's banner (Teams' announcementBanner card with the
/// post's `title`): the headline over a colour scheme ("0".."11") or a
/// picture.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Announcement {
    pub title: String,
    pub color_theme: String,
    /// The cropped picture (AMS) and its size, when it has one.
    pub image_url: String,
    pub image_width: u32,
    pub image_height: u32,
    pub image_alt: String,
    /// The picture's cached file (file://), filled in by the client.
    #[serde(default)]
    pub image_local: String,
}

/// The announcement of a post, as Teams reads it (async-entry `Jt`/`fn`):
/// the banner card's `content.imageData.colorTheme` or `content.colorTheme`,
/// `content.imageData.croppedImage` for a picture, and `properties.title`.
pub fn announcement_from(props: Option<&serde_json::Value>) -> Option<Announcement> {
    let props = props?;
    let raw = props.get("cards")?;
    let list: serde_json::Value = match raw {
        serde_json::Value::String(s) => serde_json::from_str(s).ok()?,
        other => other.clone(),
    };
    let card = list
        .as_array()?
        .iter()
        .find(|c| c.get("contentType").and_then(|t| t.as_str()) == Some(ANNOUNCEMENT_BANNER))?;
    let content = match card.get("content") {
        Some(serde_json::Value::String(s)) => serde_json::from_str(s).unwrap_or_default(),
        Some(v) => v.clone(),
        None => serde_json::Value::Null,
    };
    let str_at = |p: &str| content.pointer(p).and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let num_at = |p: &str| {
        content
            .pointer(p)
            .and_then(|v| v.as_u64().or_else(|| v.as_str().and_then(|s| s.parse().ok())))
            .unwrap_or(0) as u32
    };
    let theme = {
        let t = str_at("/imageData/colorTheme");
        if t.is_empty() { str_at("/colorTheme") } else { t }
    };
    Some(Announcement {
        title: props.get("title").and_then(|t| t.as_str()).unwrap_or_default().to_string(),
        color_theme: if theme.is_empty() { "0".into() } else { theme },
        image_url: str_at("/imageData/croppedImage/src"),
        image_width: num_at("/imageData/croppedImage/imageWidth"),
        image_height: num_at("/imageData/croppedImage/imageHeight"),
        image_alt: str_at("/imageData/croppedImage/imageAltText"),
        image_local: String::new(),
    })
}

/// Cards inside a `RichText/Html` message (`properties.cards`, a JSON string
/// of `[{cardClientId, contentType, content, appId?}]`). The announcement
/// banner isn't one: it is the post's header (`announcement_from`).
pub fn property_cards(props: Option<&serde_json::Value>) -> Vec<Card> {
    let Some(raw) = props.and_then(|p| p.get("cards")) else {
        return Vec::new();
    };
    let parsed;
    let list = match raw {
        serde_json::Value::String(s) => {
            parsed = serde_json::from_str::<serde_json::Value>(s).unwrap_or_default();
            &parsed
        }
        other => other,
    };
    list.as_array()
        .into_iter()
        .flatten()
        .filter(|c| c.get("contentType").and_then(|t| t.as_str()) != Some(ANNOUNCEMENT_BANNER))
        .filter_map(|c| {
            Some(Card {
                content_type: c.get("contentType")?.as_str()?.to_string(),
                content: match c.get("content")? {
                    serde_json::Value::String(s) => serde_json::from_str(s).unwrap_or_default(),
                    v => v.clone(),
                },
                app_id: c
                    .get("appId")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
            })
        })
        .collect()
}

/// A quoted message at the top of a reply (Teams' Reply with quote): the
/// `<blockquote itemtype="http://schema.skype.com/Reply">` card.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Quote {
    /// The quoted message's id (also its arrival time in ms).
    pub message_id: String,
    pub sender_mri: String,
    pub sender_name: String,
    /// Plain text of the quoted message.
    pub preview: String,
}

/// A forwarded message inside a message (Teams' forward card): the
/// `<blockquote itemtype="http://schema.skype.com/Forward">` and its
/// `properties.originalMessageContext`.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Forwarded {
    pub sender_mri: String,
    /// Filled in from the person's name when known.
    pub sender_name: String,
    pub arrival_ms: i64,
    pub message_id: String,
    pub thread_id: String,
    pub parent_id: String,
    /// The original's sanitised HTML and plain text.
    pub html: String,
    pub text: String,
    pub deleted: bool,
}

/// Split Teams' forward blockquote off a message's HTML, using the
/// message's `originalMessageContext` (the card needs the original's id,
/// sender and time; without them the blockquote stays ordinary HTML).
pub fn split_forward(
    content: &str,
    props: Option<&serde_json::Value>,
) -> (Option<Forwarded>, String) {
    const START: &str = "<blockquote itemtype=\"http://schema.skype.com/Forward\">";
    let Some(start) = content.find(START) else {
        return (None, content.to_string());
    };
    let inner_start = start + START.len();
    let Some(end) = content[inner_start..]
        .rfind("</blockquote>")
        .map(|i| inner_start + i)
    else {
        return (None, content.to_string());
    };
    let ctx: serde_json::Value = match props.and_then(|p| p.get("originalMessageContext")) {
        Some(serde_json::Value::String(s)) => serde_json::from_str(s).unwrap_or_default(),
        Some(v) => v.clone(),
        None => serde_json::Value::Null,
    };
    let get = |k: &str| {
        ctx.get(k)
            .map(|v| {
                v.as_str()
                    .map(str::to_string)
                    .unwrap_or_else(|| v.to_string())
            })
            .unwrap_or_default()
    };
    let (sender, message_id) = (get("originalSender"), get("messageId"));
    let arrival_ms = ctx
        .get("originalSentTime")
        // Epoch ms, or (as the service writes it) an ISO time.
        .and_then(|t| {
            t.as_i64().or_else(|| {
                let s = t.as_str()?;
                s.parse().ok().or_else(|| {
                    chrono::DateTime::parse_from_rfc3339(s)
                        .ok()
                        .map(|d| d.timestamp_millis())
                })
            })
        })
        .unwrap_or(0);
    if sender.is_empty() || message_id.is_empty() || arrival_ms == 0 {
        return (None, content.to_string());
    }
    let inner = &content[inner_start..end];
    let fwd = Forwarded {
        sender_mri: sender.clone(),
        sender_name: cached_name(&sender).unwrap_or_default(),
        arrival_ms,
        message_id,
        thread_id: get("originalThreadId"),
        parent_id: get("parentMessageId"),
        html: sanitize_html(inner),
        text: super::strip_html(inner).trim().to_string(),
        deleted: ctx
            .get("isDeleted")
            .and_then(|d| d.as_bool())
            .unwrap_or(false),
    };
    let rest = format!(
        "{}{}",
        &content[..start],
        &content[end + "</blockquote>".len()..]
    );
    (Some(fwd), rest)
}

/// Split a Teams quote card off the start of a message's HTML.
pub fn split_quote(content: &str) -> (Option<Quote>, String) {
    let Some(start) = content.find("<blockquote") else {
        return (None, content.to_string());
    };
    let Some(open_end) = content[start..].find('>').map(|i| start + i + 1) else {
        return (None, content.to_string());
    };
    let open = &content[start..open_end];
    if !open.contains("schema.skype.com/Reply") {
        return (None, content.to_string());
    }
    let Some(close) = content[open_end..]
        .find("</blockquote>")
        .map(|i| open_end + i)
    else {
        return (None, content.to_string());
    };
    let inner = &content[open_end..close];
    let message_id = attr(open, "itemid").unwrap_or_default();
    let (sender_mri, sender_name) = match inner.find("<strong") {
        Some(i) => {
            let tag_end = inner[i..]
                .find('>')
                .map(|j| i + j + 1)
                .unwrap_or(inner.len());
            let name_end = inner[tag_end..]
                .find("</strong>")
                .map(|j| tag_end + j)
                .unwrap_or(tag_end);
            (
                attr(&inner[i..tag_end], "itemid").unwrap_or_default(),
                super::strip_html(&inner[tag_end..name_end])
                    .trim()
                    .to_string(),
            )
        }
        None => (String::new(), String::new()),
    };
    let preview = match inner.find("itemprop=\"preview\"") {
        Some(i) => {
            let body = inner[i..]
                .find('>')
                .map(|j| i + j + 1)
                .unwrap_or(inner.len());
            let end = inner[body..]
                .find("</p>")
                .map(|j| body + j)
                .unwrap_or(inner.len());
            super::strip_html(&inner[body..end]).trim().to_string()
        }
        None => String::new(),
    };
    let rest = format!(
        "{}{}",
        &content[..start],
        content[close + "</blockquote>".len()..].trim_start_matches('\n')
    );
    (
        Some(Quote {
            message_id,
            sender_mri,
            sender_name,
            preview,
        }),
        rest,
    )
}

/// Teams' quote card HTML for a reply, as the client sends it: the reply's
/// paragraphs follow directly (the service puts a newline between them).
pub fn quote_html(q: &Quote) -> String {
    format!(
        "<blockquote itemscope itemtype=\"http://schema.skype.com/Reply\" itemid=\"{id}\"><strong itemprop=\"mri\" itemid=\"{mri}\">{name}</strong><span itemprop=\"time\" itemid=\"{id}\"></span><p itemprop=\"preview\">{preview}</p></blockquote>",
        id = escape(&q.message_id.replace('&', "&amp;")),
        mri = escape(&q.sender_mri.replace('&', "&amp;")),
        name = escape(&q.sender_name.replace('&', "&amp;")),
        preview = escape(&q.preview.replace('&', "&amp;"))
    )
}

/// Teams' `properties.qtdMsgs` for a reply: the quoted references as a
/// JSON string.
pub fn quoted_messages_property(q: &Quote) -> String {
    let time: serde_json::Value = q
        .message_id
        .parse::<i64>()
        .map(serde_json::Value::from)
        .unwrap_or(serde_json::Value::Null);
    serde_json::json!([{ "messageId": q.message_id, "sender": q.sender_mri, "time": time, "replyChainId": null }]).to_string()
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

/// A GIF or sticker in a message (Teams' fun picker sends both as a plain
/// `<img>`: GIFs straight from GIPHY's media hosts, stickers from Teams'
/// public CDN with `itemtype=".../Sticker"`). They load without our token.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct MessageMedia {
    /// "gif" or "sticker".
    pub kind: String,
    pub url: String,
    pub width: u32,
    pub height: u32,
    pub alt: String,
}

/// One part of a message's flow: a picture (`pic`, its index in `images`
/// followed by `media`) or text (`html`).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct FlowPart {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pic: Option<usize>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub html: String,
    /// A quote (`<blockquote>`): its HTML, drawn in Teams' quote box.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quote: Option<String>,
    /// A code block (`<pre class="language-…">`): its text, drawn as
    /// Teams' code card.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<CodeBlock>,
}

/// A code block in a message.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct CodeBlock {
    /// The language id (`plaintext`, `javascript`, …).
    pub lang: String,
    /// Its name as Teams shows it ("Plain Text", "JavaScript", …).
    #[serde(default)]
    pub name: String,
    pub text: String,
}

/// Teams' code block languages: (`language-` id, the name shown), as its
/// code block editor lists them (125961).
pub const CODE_LANGUAGES: [(&str, &str); 44] = [
    ("plaintext", "Plain Text"),
    ("bash", "Bash"),
    ("c", "C"),
    ("cpp", "C++"),
    ("csharp", "C#"),
    ("css", "CSS"),
    ("dart", "Dart"),
    ("dockerfile", "DockerFile"),
    ("dos", "DOS"),
    ("go", "Go"),
    ("graphql", "GraphQL"),
    ("html", "HTML"),
    ("http", "HTTP"),
    ("java", "Java"),
    ("javascript", "JavaScript"),
    ("json", "JSON"),
    ("jsp", "JSP"),
    ("jsx", "JSX"),
    ("kotlin", "Kotlin"),
    ("kql", "KQL"),
    ("latex", "LaTeX"),
    ("lisp", "Lisp"),
    ("markdown", "Markdown"),
    ("objectivec", "Objective-C"),
    ("octave", "Octave"),
    ("perl", "Perl"),
    ("php", "PHP"),
    ("powershell", "PowerShell"),
    ("python", "Python"),
    ("r", "R"),
    ("ruby", "Ruby"),
    ("rust", "Rust"),
    ("scala", "Scala"),
    ("scss", "SCSS"),
    ("shell", "Shell"),
    ("sql", "SQL"),
    ("swift", "Swift"),
    ("typescript", "TypeScript"),
    ("vbnet", "VB.NET"),
    ("vbscript", "VBScript"),
    ("verilog", "Verilog"),
    ("vhdl", "VHDL"),
    ("xml", "XML"),
    ("yaml", "YAML"),
];

/// The name Teams shows for a code block's language ("Plain Text" when
/// unknown).
pub fn code_language_name(lang: &str) -> &'static str {
    CODE_LANGUAGES
        .iter()
        .find(|(id, _)| id.eq_ignore_ascii_case(lang))
        .map(|(_, n)| *n)
        .unwrap_or("Plain Text")
}

/// A timeline item.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
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
    /// Teams' delivery option: "" (standard), "high" (Important) or
    /// "urgent".
    #[serde(default)]
    pub importance: String,
    pub deleted: bool,
    pub reactions: Vec<Reaction>,
    /// Inline images (Teams' AMS objects), in order.
    pub images: Vec<InlineImage>,
    /// GIFs and stickers, shown animated.
    #[serde(default)]
    pub media: Vec<MessageMedia>,
    /// What follows the message's first picture, in order: pictures and
    /// the text between them (Teams keeps each picture where it was
    /// written); `html` then holds the text before it. Empty when the
    /// pictures simply follow the text.
    #[serde(default)]
    pub flow: Vec<FlowPart>,
    /// Your own message as the edit box takes it: its HTML with each
    /// emoticon, custom emoji and picture as an `<img>`, and what each is.
    #[serde(default)]
    pub edit_html: String,
    #[serde(default)]
    pub edit_media: Vec<ComposeMedia>,
    /// Teams' mention highlight: "me", "everyone", "channel", "team" or "".
    #[serde(default)]
    pub mention_kind: String,
    /// The text a quoted reply to this message carries, as Teams builds it.
    #[serde(default)]
    pub quote_text: String,
    /// For call events: "ended" (with duration), "missed" or "started".
    pub call_state: String,
    pub call_seconds: u64,
    /// The call's id (`<callId>`), linking its started and ended events.
    #[serde(default)]
    pub call_id: String,
    /// A Meet now call (`conversationType` "huddleGroupCall"); its end shows
    /// as "Meeting ended".
    #[serde(default)]
    pub call_huddle: bool,
    /// Who started the call (a started event's participant).
    #[serde(default)]
    pub call_initiator: String,
    /// A started call with no end in the loaded timeline (Teams' Join).
    #[serde(default)]
    pub call_active: bool,
    /// A channel meeting's post (its callStarted root): the join link,
    /// title (empty for Meet now: Teams shows `Meeting in "<channel>"`),
    /// when this conversation started (RFC 3339) and its conversation (to
    /// watch who's in it).
    #[serde(default)]
    pub meeting_join_url: String,
    #[serde(default)]
    pub meeting_title: String,
    #[serde(default)]
    pub call_started_at: String,
    #[serde(default)]
    pub call_conversation_url: String,
    /// A rejoin's start posted as a new root that Teams folds into the
    /// meeting's post (`properties.linkedRootMessageId`).
    #[serde(default)]
    pub linked_root: String,
    /// Your message, and the other person has read up to it (Teams' "Seen").
    pub seen: bool,
    /// The first message that arrived after you last read the chat (Teams
    /// draws its "Last read" line above it).
    #[serde(default)]
    pub first_unread: bool,
    /// Attached files (Teams' file cards).
    #[serde(default)]
    pub files: Vec<super::files::FileAttachment>,
    /// Cards (bot, connector, workflow and message-extension cards).
    #[serde(default)]
    pub cards: Vec<Card>,
    /// Several cards shown as Teams' carousel (`message/card.carousel`).
    #[serde(default)]
    pub carousel: bool,
    /// Whether the message @mentions you (Teams marks it with an "@").
    #[serde(default)]
    pub mentions_me: bool,
    /// In a channel, the post this message belongs to: its own id for a
    /// post, the post's id for a reply. Empty in chats.
    #[serde(default)]
    pub root_id: String,
    /// A Threads-layout reply also sent to the channel (Teams'
    /// `isSharedInMain`): the conversation shows it with "Replied in
    /// thread", the thread with "Also sent to channel".
    #[serde(default)]
    pub shared_in_main: bool,
    /// A Threads-layout thread's first message: its read state (rcmetadata
    /// `ch`, and `chb` while Mark as unread's bookmark is set; 0 if none).
    #[serde(default)]
    pub thread_read_to: i64,
    #[serde(default)]
    pub thread_bookmark: i64,
    /// For system events (kind "event"): what happened, as Teams' control
    /// message renderer reads it; `text` then holds Teams' sentence.
    #[serde(default)]
    pub event: Option<ChatEvent>,
    /// An own message still being sent: "sending", "retrying" or "failed"
    /// (Teams' Sending / Retrying / Error); "" once delivered.
    #[serde(default)]
    pub send_state: String,
    /// The pending icon's tooltip, or the failed message's text.
    #[serde(default)]
    pub send_note: String,
    /// A failed message offers Retry.
    #[serde(default)]
    pub can_retry: bool,
    /// The message it quotes (Reply with quote).
    #[serde(default)]
    pub quote: Option<Quote>,
    /// Saved by you (Teams' Save this message).
    #[serde(default)]
    pub saved: bool,
    /// Pinned for everyone in the chat.
    #[serde(default)]
    pub pinned: bool,
    /// A channel post we follow (Teams' Follow thread).
    #[serde(default)]
    pub following: bool,
    /// Our explicit follow choice from the post's emotions, if any.
    #[serde(default)]
    pub follow_explicit: Option<bool>,
    /// The message it forwards (Teams' forward card).
    #[serde(default)]
    pub forward: Option<Forwarded>,
    /// Shown translated (Teams' on-demand translation); `translated_from`
    /// is the source language when known.
    #[serde(default)]
    pub translated: bool,
    #[serde(default)]
    pub translated_from: String,
    /// Translation was asked for and failed (Teams: "Failed to translate").
    #[serde(default)]
    pub translation_failed: bool,
    /// A channel post's subject (Teams' subject line; an announcement's
    /// subheading).
    #[serde(default)]
    pub subject: String,
    /// A channel announcement's banner.
    #[serde(default)]
    pub announcement: Option<Announcement>,
}

/// A chat's system event (ThreadActivity/*), as Teams parses it (module
/// 75579): who did it, to whom, and the value (a new name).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ChatEvent {
    /// Teams' control type: AddMember, DeleteMember, TopicUpdate,
    /// PictureUpdate, MemberJoined, MemberLeft, MemberRenamed. Its icon is
    /// Teams' (module 349533 `ir`).
    pub kind: String,
    pub actor: String,
    pub targets: Vec<String>,
    pub value: String,
    /// Shared history, in days (Teams' shareHistoryDaysCount); none when
    /// no history was shared.
    pub history_days: Option<i64>,
    /// Names given in the event itself (`friendlyName`), by MRI.
    #[serde(skip)]
    pub names: std::collections::HashMap<String, String>,
    /// A link the row offers (a saved recording's "Remove expiration").
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub link: String,
    /// The names in the row that belong to unverified visitors
    /// (`8:teamsvisitor:`), which Teams follows with its Unverified badge.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub unverified: Vec<String>,
}

/// A meeting recording message (`RichText/Media_CallRecording`) as Teams'
/// control rows show it (seen in OST calendar test on winpc, 2026-11-10;
/// docs/spec/message-types.md §17):
/// - RecordingStarted: "{initiator} started recording." (Record icon);
/// - RecordingStopped: "{terminator} stopped recording." (RecordStop);
/// - RecordingSaved: "Recording has been saved to {owner}'s OneDrive and
///   will expire in {N} days." with "Remove expiration" (CloudArrowUp).
/// Transcript-only messages, and a recording's paired transcript start and
/// stop, show nothing (Teams keeps them in the meeting's recap).
pub fn recording_event(content: &str, now: chrono::DateTime<chrono::Utc>) -> Option<ChatEvent> {
    let attr = |tag: &str, name: &str| -> Option<String> {
        let start = content.find(&format!("<{tag} "))?;
        let head = &content[start..start + content[start..].find('>')?];
        let key = format!("{name}=\"");
        let i = head.find(&key)? + key.len();
        Some(head[i..i + head[i..].find('"')?].to_string())
    };
    let types = attr("RecordingContent", "contentTypes")?;
    if !types.contains("Recording") {
        return None;
    }
    let status = attr("RecordingStatus", "status").unwrap_or_default();
    let mri = |v: Option<String>| v.map(|v| if v.starts_with("8:") { v } else { format!("8:orgid:{v}") }).unwrap_or_default();
    let event = |kind: &str, actor: String| ChatEvent { kind: kind.into(), actor, ..ChatEvent::default() };
    match status.as_str() {
        "Initial" => {
            let auto = attr("RecordingInitiatorId", "isAutoRecording").as_deref() == Some("True");
            let mut e = event("RecordingStarted", if auto { String::new() } else { mri(attr("RecordingInitiatorId", "value")) });
            if auto {
                e.value = "auto".into();
            }
            Some(e)
        }
        "ChunkFinished" => Some(event("RecordingStopped", mri(attr("RecordingTerminatorId", "value")))),
        "Success" => {
            let mut e = event("RecordingSaved", mri(attr("RecordingStorage", "userId")));
            // Recordings expire 120 days after they start (Teams' default
            // policy); Teams counts the days left up.
            if attr("RecordingContent", "canVideoExpire").as_deref() == Some("True")
                && let Some(start) = attr("RecordingContent", "timestamp")
                    .and_then(|t| chrono::DateTime::parse_from_rfc3339(&t).ok())
            {
                let left = (start.with_timezone(&chrono::Utc) + chrono::Duration::days(120) - now).num_seconds();
                e.value = ((left + 86_399) / 86_400).max(0).to_string();
            }
            e.link = content
                .split("type=\"onedriveForBusinessVideo\" uri=\"")
                .nth(1)
                .and_then(|r| r.split('"').next())
                .or_else(|| content.split("<a href=\"").nth(1).and_then(|r| r.split('"').next()))
                .unwrap_or_default()
                .replace("&amp;", "&");
            Some(e)
        }
        _ => None,
    }
}

/// Every `<tag>…</tag>` value of `tag` in a control message, in order.
fn tag_values(xml: &str, tag: &str) -> Vec<String> {
    let (open, close) = (format!("<{tag}>"), format!("</{tag}>"));
    let mut out = Vec::new();
    let mut rest = xml;
    while let Some(i) = rest.find(&open) {
        let after = &rest[i + open.len()..];
        let Some(j) = after.find(&close) else { break };
        out.push(super::strip_html(&after[..j]).trim().to_string());
        rest = &after[j + close.len()..];
    }
    out
}

/// A ThreadActivity message as Teams reads it: the parts its sentence
/// needs, or none for types Teams doesn't show.
pub fn chat_event(message_type: &str, content: &str) -> Option<ChatEvent> {
    let kind = message_type.strip_prefix("ThreadActivity/")?;
    // Meeting chats send members joining and leaving as JSON
    // ({"initiator", "members": [{"id", "friendlyname"}]}), seen in OST
    // calendar test for its guests.
    if content.trim_start().starts_with('{')
        && let Ok(v) = serde_json::from_str::<serde_json::Value>(content)
        && let Some(members) = v["members"].as_array()
    {
        let mut names = std::collections::HashMap::new();
        let targets: Vec<String> = members
            .iter()
            .filter_map(|m| {
                let id = m["id"].as_str()?.to_string();
                if let Some(n) = m["friendlyname"].as_str().filter(|n| !n.is_empty()) {
                    names.insert(id.clone(), n.to_string());
                }
                Some(id)
            })
            .collect();
        let actor = v["initiator"].as_str().unwrap_or_default().to_string();
        // A lobby chat's people waiting join as temporary members
        // (meetingMemberType "temp"): Teams says they're in the lobby.
        let lobby = kind == "MemberJoined"
            && !members.is_empty()
            && members.iter().all(|m| m["meetingMemberType"].as_str() == Some("temp"));
        return (matches!(kind, "MemberJoined" | "MemberLeft" | "AddMember" | "DeleteMember") && !targets.is_empty()).then(|| ChatEvent {
            kind: if lobby { "LobbyJoined".into() } else { kind.into() },
            actor,
            targets,
            names,
            ..ChatEvent::default()
        });
    }
    let first = |t: &str| {
        tag_values(content, t)
            .into_iter()
            .next()
            .unwrap_or_default()
    };
    let actor = first("initiator");
    let mut names = std::collections::HashMap::new();
    // Each <detailedtargetinfo>: <id>, then an optional <friendlyName>.
    for block in content.split("<detailedtargetinfo>").skip(1) {
        let b = block
            .split("</detailedtargetinfo>")
            .next()
            .unwrap_or_default();
        if let (Some(id), Some(name)) = (
            tag_values(b, "id").pop(),
            tag_values(b, "friendlyName").pop(),
        ) && !name.is_empty()
        {
            names.insert(id, name);
        }
    }
    let mut targets: Vec<String> = tag_values(content, "target");
    // A bot joining or leaving with its app: Teams shows the app's own
    // event (AddCustomApp / DeleteCustomApp) instead.
    if kind == "AddMember" || kind == "DeleteMember" {
        targets.retain(|t| !t.starts_with("28:"));
        if targets.is_empty() && tag_values(content, "target").iter().any(|t| t.starts_with("28:")) {
            return None;
        }
    }
    let ev = |kind: &str, targets: Vec<String>, value: String, history_days| ChatEvent {
        kind: kind.into(),
        actor: actor.clone(),
        targets,
        value,
        history_days,
        names: names.clone(),
        link: String::new(),
        unverified: Vec::new(),
    };
    match kind {
        "AddMember" => {
            if actor.is_empty() {
                return None;
            }
            let joined = targets.iter().all(|t| *t == actor);
            targets.retain(|t| *t != actor);
            if joined {
                return Some(ev("MemberJoined", vec![actor.clone()], String::new(), None));
            }
            let event_time: i64 = first("eventtime").parse().unwrap_or(-1);
            let share: i64 = first("sharehistorytime").parse().unwrap_or(-1);
            let days = (share >= 0 && event_time >= 0)
                .then(|| ((event_time - share) as f64 / 86_400_000.0).round() as i64);
            Some(ev("AddMember", targets, String::new(), days))
        }
        "DeleteMember" => {
            (!targets.is_empty()).then(|| ev("DeleteMember", targets, String::new(), None))
        }
        "TopicUpdate" => Some(ev("TopicUpdate", Vec::new(), first("value"), None)),
        // A channel's layout changed (<value>Conversational or PostReply):
        // Teams' "The layout was changed to threads." / "… to posts."
        "ModalityUpdate" => Some(ev("ModalityUpdate", Vec::new(), first("value"), None)),
        "PictureUpdate" => Some(ev("PictureUpdate", Vec::new(), String::new(), None)),
        "MemberJoined" | "MemberLeft" => {
            if targets.is_empty() && !actor.is_empty() {
                targets.push(actor.clone());
            }
            (!targets.is_empty()).then(|| ev(kind, targets, String::new(), None))
        }
        "MemberRenamed" => Some(ev("MemberRenamed", Vec::new(), first("value"), None)),
        // An app added to or removed from the chat (its name in
        // <targetName>).
        "AddCustomApp" | "DeleteCustomApp" => {
            let app = first("targetName");
            (!actor.is_empty() && !app.is_empty()).then(|| ev(kind, targets, app, None))
        }
        _ => None,
    }
}

/// Teams' sentence for an event (module 75579's strings), with names.
pub fn event_text(e: &ChatEvent, name: &dyn Fn(&str) -> String, meeting: bool) -> String {
    let others = |n: usize| {
        if n == 1 {
            "1 other".to_string()
        } else {
            format!("{n} others")
        }
    };
    // <1>, <1> and <2>, or <1> and N others.
    let list = |ts: &[String]| -> String {
        match ts.len() {
            0 => String::new(),
            1 => name(&ts[0]),
            2 => format!("{} and {}", name(&ts[0]), name(&ts[1])),
            n => format!("{} and {}", name(&ts[0]), others(n - 1)),
        }
    };
    let actor = name(&e.actor);
    match e.kind.as_str() {
        "AddMember" => {
            let base = format!("{actor} added {} to the chat", list(&e.targets));
            match e.history_days {
                None => format!("{base}."),
                Some(0) => format!("{base} and shared all chat history."),
                Some(1) => format!("{base} and shared chat history from the past day."),
                Some(d) => format!("{base} and shared chat history from the past {d} days."),
            }
        }
        "DeleteMember" => {
            if e.targets.len() == 1 && e.targets[0] == e.actor {
                format!("{actor} left the chat.")
            } else if !e.actor.starts_with("8:") {
                let verb = if e.targets.len() == 1 { "was" } else { "were" };
                format!("{} {verb} removed from the chat.", list(&e.targets))
            } else {
                format!("{actor} removed {} from the chat.", list(&e.targets))
            }
        }
        "TopicUpdate" if e.value.is_empty() => {
            format!("{actor} removed the group name for this conversation.")
        }
        "TopicUpdate" if meeting => format!("{actor} named the meeting {}.", e.value),
        "TopicUpdate" => format!("{actor} changed the group name to {}.", e.value),
        "ModalityUpdate" if e.value == "Conversational" => "The layout was changed to threads.".into(),
        "ModalityUpdate" => "The layout was changed to posts.".into(),
        "PictureUpdate" => format!("{actor} changed the group profile picture."),
        "MemberJoined" => {
            let verb = match (e.targets.len(), meeting) {
                (1, true) => "was invited to the meeting",
                (_, true) => "were invited to the meeting",
                _ => "joined the conversation",
            };
            format!("{} {verb}.", list(&e.targets))
        }
        // Teams: "{{targetOne}} is in the lobby." / "… and … are in the lobby."
        "LobbyJoined" => {
            let verb = if e.targets.len() == 1 { "is" } else { "are" };
            format!("{} {verb} in the lobby.", list(&e.targets))
        }
        "MemberLeft" => {
            let verb = match (e.targets.len(), meeting) {
                (_, true) => "left the chat",
                (1, false) => "no longer has access to the chat",
                _ => "no longer have access to the chat",
            };
            format!("{} {verb}.", list(&e.targets))
        }
        "MemberRenamed" => format!("{actor} changed their display name to {}.", e.value),
        "AddCustomApp" => format!("{actor} added {} here.", e.value),
        "DeleteCustomApp" => format!("{actor} removed {} from the chat.", e.value),
        "Transcript" => "Transcript".into(),
        "RecordingStarted" if e.value == "auto" => "Recording started automatically per the organizer's setting.".into(),
        "RecordingStarted" if e.actor.is_empty() => "Recording has started".into(),
        "RecordingStarted" => format!("{actor} started recording."),
        "RecordingStopped" if e.actor.is_empty() => "Recording stopped.".into(),
        "RecordingStopped" => format!("{actor} stopped recording."),
        "RecordingSaved" => {
            let to = if e.actor.is_empty() { "OneDrive".to_string() } else { format!("{actor}'s OneDrive") };
            match e.value.as_str() {
                "" => format!("Recording has been saved to {to}."),
                "1" => format!("Recording has been saved to {to} and will expire in 1 day."),
                d => format!("Recording has been saved to {to} and will expire in {d} days."),
            }
        }
        _ => String::new(),
    }
}

/// Teams' reaction keys and their emoji.
pub fn reaction_emoji(key: &str) -> &'static str {
    match key {
        // The service's like is the client's yes.
        "like" | "yes" => "👍",
        "heart" => "❤️",
        "laugh" => "😆",
        "surprised" => "😮",
        "sad" => "😢",
        "angry" => "😠",
        _ => "🙂",
    }
}

/// One page of a chat's history, oldest first, and the token for the
/// page before it (none at the start of the chat).
#[derive(Debug, Default)]
pub struct TimelinePage {
    pub messages: Vec<MessageView>,
    pub older: Option<String>,
}

/// One message by id (for a pinned message that isn't loaded).
pub async fn read_message(
    client: &TeamsClient,
    chat_id: &str,
    message_id: &str,
) -> Result<MessageView> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}",
        client.chat_service_url(),
        chat_id,
        message_id
    );
    let m: serde_json::Value = client.chat_get(&url).await?.json().await?;
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    let name = client.display_name().unwrap_or_default();
    view_of(&m, &me, &name).ok_or_else(|| anyhow::anyhow!("not a message Teams shows"))
}

/// Teams' page size for a conversation's messages (its chat service cap).
pub const PAGE_SIZE: usize = 200;

/// The `syncState` of a chat service `_metadata.backwardLink` (the token
/// Teams sends for the page before).
pub fn backward_token(metadata: &serde_json::Value) -> Option<String> {
    let link = metadata.get("backwardLink")?.as_str()?;
    let url = reqwest::Url::parse(link).ok()?;
    url.query_pairs()
        .find(|(k, _)| k == "syncState")
        .map(|(_, v)| v.into_owned())
        .filter(|v| !v.is_empty())
}

/// The URL Teams asks for a conversation's messages with (worker module
/// `ne`: view msnp24Equivalent, plus supportsMessageProperties for chats;
/// pageSize; syncState for an older page; startTime=1, the start of time).
pub fn messages_url(
    base: &str,
    chat_id: &str,
    page_size: usize,
    sync_state: Option<&str>,
) -> String {
    let enc = |v: &str| url::form_urlencoded::byte_serialize(v.as_bytes()).collect::<String>();
    let channel = chat_id.ends_with("@thread.tacv2") || chat_id.ends_with("@thread.skype");
    let mut url = format!(
        "{base}/v1/users/ME/conversations/{}/messages?view=msnp24Equivalent{}&pageSize={page_size}",
        enc(chat_id),
        if channel {
            ""
        } else {
            "|supportsMessageProperties"
        }
    );
    if let Some(t) = sync_state {
        url.push_str(&format!("&syncState={}", enc(t)));
    }
    url.push_str("&startTime=1");
    url
}

/// Load a chat's timeline, oldest first (its newest page).
pub async fn read_timeline(
    client: &TeamsClient,
    chat_id: &str,
    limit: usize,
) -> Result<Vec<MessageView>> {
    Ok(read_timeline_page(client, chat_id, limit, None)
        .await?
        .messages)
}

/// Load one page of a chat's history: the newest (`sync_state` none), or
/// the page before the one whose token is given, as Teams pages back.
pub async fn read_timeline_page(
    client: &TeamsClient,
    chat_id: &str,
    page_size: usize,
    sync_state: Option<&str>,
) -> Result<TimelinePage> {
    let url = messages_url(&client.chat_service_url(), chat_id, page_size, sync_state);
    let resp = match client.chat_get(&url).await {
        Ok(r) => r,
        // A 1:1 chat nobody has written in yet, or your own notes chat
        // before its first note, does not exist; the first message creates
        // it, so it opens empty.
        Err(e)
            if e.to_string().contains("HTTP 404")
                && (chat_id.ends_with("@unq.gbl.spaces") || chat_id == "48:notes") =>
        {
            return Ok(TimelinePage::default());
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
    sort_by_arrival(&mut out);
    name_events(client, chat_id, &mut out).await;
    let older = v.get("_metadata").and_then(backward_token);
    Ok(TimelinePage {
        messages: out,
        older,
    })
}

/// People's display names by MRI, learnt from messages, events and Graph
/// and kept for the session (Teams resolves names from its person store).
fn names() -> &'static std::sync::Mutex<std::collections::HashMap<String, String>> {
    use std::sync::{Mutex, OnceLock};
    static NAMES: OnceLock<Mutex<std::collections::HashMap<String, String>>> = OnceLock::new();
    NAMES.get_or_init(Default::default)
}

/// A person's display name if already known.
pub fn cached_name(mri: &str) -> Option<String> {
    names().lock().unwrap().get(mri).cloned()
}

/// A person's display name: known, else from Graph (`8:orgid:` users).
pub async fn person_name(client: &TeamsClient, mri: &str) -> Option<String> {
    if let Some(n) = cached_name(mri) {
        return Some(n);
    }
    let oid = mri.strip_prefix("8:orgid:")?;
    uuid::Uuid::parse_str(oid).ok()?;
    let v: serde_json::Value = client
        .graph_get(&format!("/users/{oid}?$select=displayName"))
        .await
        .ok()?
        .json()
        .await
        .ok()?;
    let n = v.get("displayName")?.as_str()?.to_string();
    names().lock().unwrap().insert(mri.to_string(), n.clone());
    Some(n)
}

/// Fill in system events' sentences, resolving people's names (from the
/// event, else Graph; remembered for the session).
async fn name_events(client: &TeamsClient, chat_id: &str, out: &mut [MessageView]) {
    let cache = names();
    let mut wanted: Vec<String> = Vec::new();
    {
        let mut c = cache.lock().unwrap();
        for m in out.iter() {
            if !m.sender_mri.is_empty() && !m.sender.is_empty() {
                c.entry(m.sender_mri.clone())
                    .or_insert_with(|| m.sender.clone());
            }
        }
    }
    for e in out.iter().filter_map(|m| m.event.as_ref()) {
        let mut c = cache.lock().unwrap();
        for (id, n) in &e.names {
            c.entry(id.clone()).or_insert_with(|| n.clone());
        }
        for id in std::iter::once(&e.actor).chain(e.targets.iter()) {
            if id.starts_with("8:orgid:") && !c.contains_key(id) && !wanted.contains(id) {
                wanted.push(id.clone());
            }
        }
    }
    // Forwarded messages' original senders too.
    for f in out.iter().filter_map(|m| m.forward.as_ref()) {
        if f.sender_name.is_empty()
            && !wanted.contains(&f.sender_mri)
            && cached_name(&f.sender_mri).is_none()
        {
            wanted.push(f.sender_mri.clone());
        }
    }
    // And who reacted (Teams' who-reacted list names them).
    for u in out
        .iter()
        .flat_map(|m| m.reactions.iter())
        .flat_map(|r| r.users.iter())
    {
        if !wanted.contains(&u.mri) && cached_name(&u.mri).is_none() {
            wanted.push(u.mri.clone());
        }
    }
    for id in wanted {
        person_name(client, &id).await;
    }
    for u in out
        .iter_mut()
        .flat_map(|m| m.reactions.iter_mut())
        .flat_map(|r| r.users.iter_mut())
    {
        u.name = cached_name(&u.mri).unwrap_or_else(|| "Unknown user".into());
    }
    for f in out.iter_mut().filter_map(|m| m.forward.as_mut()) {
        if f.sender_name.is_empty() {
            f.sender_name = cached_name(&f.sender_mri).unwrap_or_else(|| "Unknown user".into());
        }
    }
    let meeting = chat_id.starts_with("19:meeting_");
    let names = cache.lock().unwrap().clone();
    let name = |id: &str| {
        names
            .get(id)
            .cloned()
            .unwrap_or_else(|| "Unknown user".into())
    };
    for m in out.iter_mut() {
        if let Some(e) = &mut m.event {
            m.text = event_text(e, &name, meeting);
            e.unverified = e
                .targets
                .iter()
                .filter(|t| t.starts_with("8:teamsvisitor:"))
                .map(|t| name(t))
                .collect();
        }
    }
}

/// The service lists by last change (a reaction or edit moves a message
/// up), so order by arrival time; ids are arrival milliseconds.
pub fn sort_by_arrival(out: &mut [MessageView]) {
    out.sort_by(|a, b| {
        let key = |m: &MessageView| m.id.parse::<u64>().unwrap_or(0);
        key(a).cmp(&key(b)).then_with(|| a.time.cmp(&b.time))
    });
    link_calls(out);
}

/// What a call start says about a channel meeting.
#[derive(Default, Debug, PartialEq)]
struct ChannelMeeting {
    join_url: String,
    title: String,
    started_at: String,
    conversation_url: String,
    linked_root: String,
}

/// A call start's meeting details: `properties.meeting` (a JSON string:
/// `meetingJoinUrl`, `meetingtitle`), `properties.linkedRootMessageId`, and
/// the content's `<conversationStartTime>` (UTC, "MM/DD/YYYY HH:MM:SS") and
/// `<conversationUrl>`.
fn channel_meeting(m: &serde_json::Value, content: &str) -> ChannelMeeting {
    let props = m.get("properties");
    let meeting: serde_json::Value = props
        .and_then(|p| p.get("meeting"))
        .and_then(|v| v.as_str())
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();
    let tag = |t: &str| {
        content
            .split(&format!("<{t}>"))
            .nth(1)
            .and_then(|r| r.split('<').next())
            .unwrap_or_default()
            .trim()
            .replace("&amp;", "&")
    };
    let started_at = chrono::NaiveDateTime::parse_from_str(&tag("conversationStartTime"), "%m/%d/%Y %H:%M:%S")
        .map(|t| t.and_utc().to_rfc3339())
        .unwrap_or_default();
    let s = |v: &serde_json::Value, k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    ChannelMeeting {
        join_url: s(&meeting, "meetingJoinUrl"),
        title: s(&meeting, "meetingtitle"),
        started_at,
        conversation_url: tag("conversationUrl"),
        linked_root: props.map(|p| s(p, "linkedRootMessageId")).unwrap_or_default(),
    }
}

/// Pair calls' started and ended events by call id: an end of a Meet now
/// call is a meeting end, and a start with no end is still going on.
pub fn link_calls(out: &mut [MessageView]) {
    let huddles: std::collections::HashSet<String> = out
        .iter()
        .filter(|m| m.call_state == "started" && m.call_huddle && !m.call_id.is_empty())
        .map(|m| m.call_id.clone())
        .collect();
    let ended: std::collections::HashSet<String> = out
        .iter()
        .filter(|m| m.kind == "call" && m.call_state != "started" && !m.call_id.is_empty())
        .map(|m| m.call_id.clone())
        .collect();
    for m in out.iter_mut().filter(|m| m.kind == "call") {
        if m.call_state == "started" {
            m.call_active = !m.call_id.is_empty() && !ended.contains(&m.call_id);
        } else if huddles.contains(&m.call_id) {
            m.call_huddle = true;
        }
    }
}

/// Older pages loaded so far followed by the newest page, each message
/// once (the newest page's copy wins: it has the latest edits and
/// reactions), oldest first.
pub fn merge_pages(older: &[MessageView], newest: Vec<MessageView>) -> Vec<MessageView> {
    let ids: std::collections::HashSet<&str> = newest.iter().map(|m| m.id.as_str()).collect();
    let mut all: Vec<MessageView> = older
        .iter()
        .filter(|m| !ids.contains(m.id.as_str()))
        .cloned()
        .collect();
    all.extend(newest);
    sort_by_arrival(&mut all);
    all
}

/// A message from the chat service as OST shows it (for streams outside a
/// chat's timeline, such as scheduled drafts).
pub fn message_view(m: &serde_json::Value, me: &str, own_name: &str) -> Option<MessageView> {
    view_of(m, me, own_name)
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
        if t.is_empty() { s("/composetime") } else { t }
    };
    let base = MessageView {
        importance: s("/properties/importance"),
        subject: s("/properties/subject"),
        announcement: announcement_from(m.pointer("/properties")),
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
        shared_in_main: matches!(m.pointer("/properties/isSharedInMain"), Some(serde_json::Value::Bool(true)))
            || m.pointer("/properties/isSharedInMain").and_then(|v| v.as_str()) == Some("true"),
        mentions_me: false,
        event: None,
        ..Default::default()
    };
    // Teams shows a legacy transcript message only in a 1:1 chat (as its
    // "Transcript" card); in group and meeting chats it goes with the
    // call's ended row. Meeting objects have no row at all
    // (docs/spec/message-types.md §19, §20).
    if kind == "RichText/Media_MeetingObjects" {
        return None;
    }
    if kind == "RichText/Media_CallTranscript" {
        let conv = s("/conversationid");
        if !conv.ends_with("@unq.gbl.spaces") {
            return None;
        }
        return Some(MessageView {
            kind: "event".into(),
            event: Some(ChatEvent { kind: "Transcript".into(), ..ChatEvent::default() }),
            ..base
        });
    }
    if kind == "RichText/Media_CallRecording" {
        let event = recording_event(&s("/content"), chrono::Utc::now())?;
        return Some(MessageView {
            kind: "event".into(),
            event: Some(event),
            ..base
        });
    }
    if kind.starts_with("ThreadActivity/") {
        let event = chat_event(&kind, &s("/content"))?;
        return Some(MessageView {
            kind: "event".into(),
            event: Some(event),
            ..base
        });
    }
    if kind == "Event/Call" {
        let content = s("/content");
        let call_id = content
            .split("<callId>")
            .nth(1)
            .and_then(|r| r.split('<').next())
            .unwrap_or_default()
            .to_string();
        // A start: Teams shows Meet now's ("… started a meeting."); other
        // starts only tell that a call is going on.
        if content.contains("callStarted") && !content.contains("<ended/>") {
            // Starts name the initiator only by MRI (`<name>8:orgid:…`);
            // a display name, when one is there, is the person's name.
            let initiator = content
                .split("<displayName>")
                .nth(1)
                .and_then(|r| r.split('<').next())
                .unwrap_or_default()
                .trim()
                .to_string();
            let meeting = channel_meeting(m, &content);
            return Some(MessageView {
                kind: "call".into(),
                call_state: "started".into(),
                call_huddle: content.contains("\"huddleGroupCall\""),
                call_initiator: initiator,
                call_id,
                meeting_join_url: meeting.join_url,
                meeting_title: meeting.title,
                call_started_at: meeting.started_at,
                call_conversation_url: meeting.conversation_url,
                linked_root: meeting.linked_root,
                ..base
            });
        }
        // Otherwise only the end of a call goes in the timeline, as in Teams.
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
            call_id,
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
    // Card messages: the SWIFT payload's cards, with its text as the body.
    let (cards, carousel, content) = if kind == "RichText/Media_Card" {
        match swift_payload(&s("/content")) {
            Some(swift) => {
                let (cards, text, carousel) = swift_cards(&swift);
                (cards, carousel, text)
            }
            None => (Vec::new(), false, s("/content")),
        }
    } else {
        (property_cards(props), false, s("/content"))
    };
    let (quote, content) = split_quote(&content);
    let (forward, content) = split_forward(&content, m.get("properties"));
    let reactions = props
        .and_then(|p| p.get("emotions"))
        .map(|e| reactions_of(e, me))
        .unwrap_or_default();
    let follow_explicit = props
        .and_then(|p| p.get("emotions"))
        .and_then(|e| follow_of(e, me));
    // From the sanitised HTML, so Teams emoticons count as their character
    // and custom emoji as Teams' text form `:name:`.
    let text = super::strip_html(&custom_emoji_as_text(&sanitize_html(&content)))
        .trim()
        .to_string();
    // Teams shows "This message has been deleted" to its sender only (and
    // only right after deleting; the app decides that); for everyone else
    // the message just disappears.
    let images = if deleted {
        Vec::new()
    } else {
        inline_images(&content)
    };
    let media = if deleted {
        Vec::new()
    } else {
        message_media(&content)
    };
    let files = if deleted {
        Vec::new()
    } else {
        props
            .and_then(|p| p.get("files"))
            .map(super::files::parse_files)
            .unwrap_or_default()
    };
    // A forward with no note of its own still shows (its card).
    if forward.is_some() && text.is_empty() && images.is_empty() && files.is_empty() && !deleted {
        return Some(MessageView {
            quote,
            forward,
            ..base
        });
    }
    if (deleted && !mine)
        || (!deleted
            && text.is_empty()
            && images.is_empty()
            && media.is_empty()
            && files.is_empty()
            && cards.is_empty())
    {
        return None;
    }
    let text = if text.is_empty() && (!images.is_empty() || !media.is_empty()) {
        "Image".to_string()
    } else if text.is_empty() && !cards.is_empty() {
        // Teams' preview of a message that is only cards.
        "Sent a card".to_string()
    } else {
        text
    };
    // Which mention ids (`itemid`) are you, from properties.mentions.
    let my_mentions = my_mention_ids(props, me);
    let cards = if deleted { Vec::new() } else { cards };
    // Files, cards, pictures, GIFs and stickers keep emoticons small (as in
    // Teams, where any other image counts).
    let may_be_big = files.is_empty() && cards.is_empty() && images.is_empty() && media.is_empty();
    let (marked, pic_tags) = if deleted {
        (String::new(), Vec::new())
    } else {
        let (m, p) = sanitize_core(&content, &my_mentions, true);
        (sized_lines(&m), p)
    };
    // Pictures stay where they were written (Teams keeps the order).
    let (head, flow) = split_flow(&marked, &pic_tags, |tag| {
        let src = attr(tag, "src")?;
        images.iter().position(|i| i.url == src).or_else(|| {
            media
                .iter()
                .position(|m| m.url == src)
                .map(|k| images.len() + k)
        })
    });
    let head = if flow.is_empty() {
        without_empty_paragraphs(&head)
    } else {
        flow_text(&head)
    };
    let (edit_html, edit_media) = if mine && !deleted {
        edit_form(&marked, &pic_tags, &mention_list(props))
    } else {
        (String::new(), Vec::new())
    };
    Some(MessageView {
        quote,
        forward,
        images,
        media,
        files,
        cards,
        carousel,
        mentions_me: !my_mentions.is_empty() && !deleted,
        mention_kind: if deleted {
            String::new()
        } else {
            mention_kind(!my_mentions.is_empty(), &mention_types(props), mine).to_string()
        },
        html: if deleted {
            String::new()
        } else if may_be_big && big_emoticons(&head) {
            head.replace("width=\"20\" height=\"20\"", "width=\"50\" height=\"50\"")
        } else {
            head
        },
        flow,
        edit_html,
        edit_media,
        quote_text: if deleted {
            String::new()
        } else {
            quote_preview(&content)
        },
        text: if deleted { String::new() } else { text },
        edited,
        deleted,
        reactions,
        follow_explicit,
        ..base
    })
}

/// Teams' follow state of each channel post: an explicit choice wins (the
/// thread's rcmetadata `f`: 1 follows, 3 unfollowed; else the post's
/// `follow` emotion); otherwise posts we wrote or replied to are followed
/// (autoFollowAuthoredThreads / autoFollowParticipatedThreads).
pub fn apply_following(
    timeline: &mut [MessageView],
    rc_follow: &std::collections::HashMap<String, i64>,
) {
    let mut participated: std::collections::HashSet<String> = std::collections::HashSet::new();
    for m in timeline.iter() {
        if m.mine && !m.root_id.is_empty() {
            participated.insert(m.root_id.clone());
        }
    }
    for m in timeline.iter_mut() {
        let is_post = m.root_id.is_empty() || m.root_id == m.id;
        if !is_post {
            continue;
        }
        m.following = match rc_follow.get(&m.id) {
            Some(1) => true,
            Some(3) => false,
            _ => m
                .follow_explicit
                .unwrap_or(m.mine || participated.contains(&m.id)),
        };
    }
}

/// Put each thread's read state on its first message.
pub fn apply_thread_horizons(
    timeline: &mut [MessageView],
    horizons: &std::collections::HashMap<String, super::msgactions::ThreadHorizon>,
) {
    for m in timeline.iter_mut() {
        if let Some(h) = horizons.get(&m.id) {
            m.thread_read_to = h.read_to;
            m.thread_bookmark = h.bookmark;
        }
    }
}

/// Emotion keys that are not reactions: acknowledgements, a thread's follow
/// state and the service's star (Teams' `OS` set).
const HIDDEN_EMOTIONS: [&str; 3] = ["acks", "follow", "star"];

/// Our explicit follow state of a channel thread from its emotions: the
/// `follow` key's value for us ("1" follows, "0" unfollowed).
fn follow_of(e: &serde_json::Value, me: &str) -> Option<bool> {
    let parsed;
    let list = match e {
        serde_json::Value::String(s) => {
            parsed = serde_json::from_str::<serde_json::Value>(s).unwrap_or_default();
            &parsed
        }
        other => other,
    };
    let entry = list
        .as_array()?
        .iter()
        .find(|r| r.get("key").and_then(|k| k.as_str()) == Some("follow"))?;
    let user = entry
        .get("users")?
        .as_array()?
        .iter()
        .find(|u| u.get("mri").and_then(|m| m.as_str()) == Some(me))?;
    let v = user.get("value")?;
    Some(
        v.as_str()
            .map(|s| s == "1")
            .or_else(|| v.as_i64().map(|n| n == 1))
            .unwrap_or(false),
    )
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
    let mut pills: Vec<Reaction> = Vec::new();
    for r in list.as_array().into_iter().flatten() {
        let Some(raw) = r.get("key").and_then(|k| k.as_str()) else {
            continue;
        };
        // Not reactions: Teams keeps these in emotions too (719107).
        if HIDDEN_EMOTIONS.contains(&raw) {
            continue;
        }
        // Teams works in client ids (its summary maps the service's keys).
        let key = super::emoticons::client_key(raw);
        let users: Vec<Reactor> = r
            .get("users")
            .and_then(|u| u.as_array())
            .into_iter()
            .flatten()
            .filter_map(|u| {
                Some(Reactor {
                    mri: u.get("mri")?.as_str()?.to_string(),
                    me: u.get("mri")?.as_str()? == me,
                    name: String::new(),
                    key: key.to_string(),
                    time: u
                        .get("time")
                        .and_then(|t| t.as_i64().or_else(|| t.as_str()?.parse().ok()))
                        .unwrap_or_default(),
                })
            })
            .collect();
        if users.is_empty() {
            continue;
        }
        let common = common_key(key);
        let i = match pills.iter().position(|p| p.key == common) {
            Some(i) => i,
            None => {
                pills.push(Reaction {
                    key: common.to_string(),
                    emoji: reaction_emoji(common).to_string(),
                    ..Default::default()
                });
                pills.len() - 1
            }
        };
        let pill = &mut pills[i];
        if users.iter().any(|u| u.me) {
            pill.mine = true;
            pill.my_key = key.to_string();
        }
        if !pill.variants.iter().any(|k| k == key) {
            pill.variants.push(key.to_string());
        }
        pill.users.extend(users);
    }
    for p in &mut pills {
        p.count = p.users.len();
        p.users.sort_by_key(|u| std::cmp::Reverse(u.time));
        p.kinds = p.variants.len();
        p.variants = shown_variants(&p.variants, &p.my_key);
    }
    // Teams' order: pills with our reaction first, by count; then the rest
    // as listed.
    let (mut mine, rest): (Vec<_>, Vec<_>) = pills.into_iter().partition(|p| p.mine);
    // Equal counts: the one we reacted to first (Teams' `at`).
    let my_time = |p: &Reaction| {
        p.users
            .iter()
            .find(|u| u.me)
            .map(|u| u.time)
            .unwrap_or_default()
    };
    mine.sort_by(|a, b| b.count.cmp(&a.count).then(my_time(a).cmp(&my_time(b))));
    mine.extend(rest);
    mine
}

/// Reduce Teams message HTML to the subset Qt's rich text renders safely:
/// paragraphs, line breaks, emphasis, lists, code, quotes and links. Emoji
/// images become their alt text, other tags and all attributes except a
/// link's href are dropped, and bare URLs become links.
pub fn sanitize_html(html: &str) -> String {
    sanitize_html_marking(html, &[])
}

/// The `itemid`s of a message's mentions that name `me`, from
/// `properties.mentions` (a JSON array, usually sent as a string).
fn my_mention_ids(props: Option<&serde_json::Value>, me: &str) -> Vec<String> {
    let Some(raw) = props.and_then(|p| p.get("mentions")) else {
        return Vec::new();
    };
    let list = match raw {
        serde_json::Value::String(s) => serde_json::from_str(s).unwrap_or_default(),
        v => v.clone(),
    };
    list.as_array()
        .into_iter()
        .flatten()
        .filter(|m| {
            // Sharing your contact doesn't mention you (Teams).
            m.get("mentionType").and_then(|t| t.as_str()) != Some("share-contact")
        })
        .filter(|m| {
            let mri = m.get("mri").and_then(|x| x.as_str());
            (!me.is_empty() && mri.is_some_and(|x| x.eq_ignore_ascii_case(me)))
                // A tag you are in mentions you (Teams' currentUserTagIds).
                || (m.get("mentionType").and_then(|t| t.as_str()) == Some("tag")
                    && mri.is_some_and(super::teams::is_my_tag))
        })
        .filter_map(|m| match m.get("itemid")? {
            serde_json::Value::Number(n) => Some(n.to_string()),
            serde_json::Value::String(s) => Some(s.clone()),
            _ => None,
        })
        .collect()
}

/// The kinds of mention in a message (`mentionType`s), each once.
fn mention_types(props: Option<&serde_json::Value>) -> Vec<String> {
    let Some(raw) = props.and_then(|p| p.get("mentions")) else {
        return Vec::new();
    };
    let list: serde_json::Value = match raw {
        serde_json::Value::String(s) => serde_json::from_str(s).unwrap_or_default(),
        v => v.clone(),
    };
    let mut out: Vec<String> = Vec::new();
    for m in list.as_array().into_iter().flatten() {
        if let Some(t) = m.get("mentionType").and_then(|t| t.as_str())
            && !out.iter().any(|o| o == t)
        {
            out.push(t.to_string());
        }
    }
    out
}

/// Which of Teams' mention highlights a message gets (Teams' post
/// indicator, 763654 `L`, before importance and your own posts): "me"
/// when it @mentions you, "everyone" for @Everyone from someone else,
/// "channel" or "team" for a channel or team mention; "" otherwise.
fn mention_kind(me_mentioned: bool, types: &[String], mine: bool) -> &'static str {
    let has = |t: &str| types.iter().any(|x| x == t);
    if me_mentioned {
        "me"
    } else if has("everyone") && !mine {
        "everyone"
    } else if has("channel") {
        "channel"
    } else if has("team") {
        "team"
    } else {
        ""
    }
}

/// As `sanitize_html`, keeping Teams' mention spans as
/// `<span class="mention">`, or `class="mention-me"` for the `itemid`s in
/// `mine`, so the client can colour them as Teams does.
pub fn sanitize_html_marking(html: &str, mine: &[String]) -> String {
    sanitize_core(html, mine, false).0
}

/// Where the sanitised HTML had a picture (an AMS image, GIF or sticker):
/// `<img src="ost-pic:N">`, N counting from 0 in document order.
const PIC_SRC: &str = "ost-pic:";

fn pic_marker(n: usize) -> String {
    format!("<img src=\"{PIC_SRC}{n}\">")
}

/// The sanitiser; with `mark_pics`, pictures leave a marker (`PIC_SRC`)
/// and their tags are returned in order.
fn sanitize_core(html: &str, mine: &[String], mark_pics: bool) -> (String, Vec<String>) {
    let mut pics: Vec<String> = Vec::new();
    const KEEP: [&str; 24] = [
        "h1",
        "h2",
        "h3",
        "hr",
        "table",
        "tbody",
        "tr",
        "td",
        "th",
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
    // Open spans, and whether each is a mention (others are dropped).
    let mut spans: Vec<bool> = Vec::new();
    while let Some(start) = rest.find('<') {
        out.push_str(&linkify(&rest[..start], in_link > 0));
        let Some(end) = rest[start..].find('>') else {
            out.push_str(&escape(&rest[start..]));
            return (out, pics);
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
            // Inline pictures, GIFs and stickers are shown by the client
            // from `images` and `media`.
            if tag.contains("AMSImage") || media_kind(tag).is_some() {
                if mark_pics {
                    out.push_str(&pic_marker(pics.len()));
                    pics.push(tag.to_string());
                }
                continue;
            }
            // A custom emoji, rebuilt from its itemid alone (as Teams does):
            // a 20 px picture whose src the client fills in
            // (CUSTOM_EMOJI_SRC + document id).
            if attr(tag, "itemtype").is_some_and(|t| t.ends_with("schema.skype.com/CustomEmoji"))
                && let Some(e) = attr(tag, "itemid")
                    .and_then(|id| super::custom_emoji::CustomEmoji::from_id(&id))
                && e.document_id
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-')
            {
                out.push_str(&format!(
                    "<img src=\"{CUSTOM_EMOJI_SRC}{}\" width=\"20\" height=\"20\" alt=\"{}\">",
                    e.document_id,
                    escape(&e.shortcut)
                ));
                continue;
            }
            // A shared contact's card icon (Teams draws its contact-card
            // icon in brand colour, not the emoticon).
            if attr(tag, "itemid").as_deref() == Some("idcard") {
                let at = html.len() - rest.len() - end - 1;
                let span = html[..at.min(html.len())]
                    .rfind("<span")
                    .map(|i| &html[i..at.min(html.len())])
                    .unwrap_or("");
                if span.contains("Share_Contact_Card") {
                    out.push_str(&format!(
                        "<img src=\"{CONTACT_CARD_SRC}\" width=\"20\" height=\"20\" alt=\"{}\">",
                        escape(&attr(tag, "alt").unwrap_or_default())
                    ));
                    continue;
                }
            }
            // A Teams emoticon: its Fluent picture, 20 px in the line, whose
            // src the client fills in (EMOTICON_SRC + emoticon id).
            if attr(tag, "itemtype").is_some_and(|t| t.ends_with("schema.skype.com/Emoji"))
                && let Some(id) = attr(tag, "itemid").filter(|id| {
                    !id.is_empty()
                        && id.len() <= 80
                        && id
                            .chars()
                            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                })
            {
                out.push_str(&format!(
                    "<img src=\"{EMOTICON_SRC}{id}\" width=\"20\" height=\"20\" alt=\"{}\" title=\"{}\">",
                    escape(&attr(tag, "alt").unwrap_or_default()),
                    escape(&attr(tag, "title").unwrap_or_default())
                ));
                continue;
            }
            if let Some(alt) = attr(tag, "alt") {
                out.push_str(&escape(&alt));
            }
            continue;
        }
        if name == "span" {
            if closing {
                if spans.pop() == Some(true) {
                    out.push_str("</span>");
                }
            } else if !tag.ends_with('/') {
                let mention =
                    attr(tag, "itemtype").is_some_and(|t| t.ends_with("schema.skype.com/Mention"));
                if mention {
                    let me = attr(tag, "itemid").is_some_and(|id| mine.contains(&id));
                    out.push_str(if me {
                        "<span class=\"mention-me\">"
                    } else {
                        "<span class=\"mention\">"
                    });
                    spans.push(true);
                } else if let Some(style) = attr(tag, "style").and_then(|s| text_style(&s)) {
                    // Teams' highlight, font colour and size.
                    out.push_str(&format!("<span style=\"{style}\">"));
                    spans.push(true);
                } else {
                    spans.push(false);
                }
            }
            continue;
        }
        // Teams' code block editor leaves an empty paragraph before the
        // block; Teams doesn't show it.
        if name == "p"
            && !closing
            && attr(tag, "itemtype")
                .is_some_and(|t| t.ends_with("schema.skype.com/CodeBlockEditor"))
        {
            match rest.find("</p>") {
                Some(e) => rest = &rest[e + 4..],
                None => rest = "",
            }
            continue;
        }
        // A code block keeps its language.
        if name == "pre" && !closing {
            match attr(tag, "class")
                .and_then(|c| c.strip_prefix("language-").map(str::to_string))
                .filter(|l| {
                    !l.is_empty()
                        && l.len() <= 40
                        && l.chars()
                            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '+' || c == '#')
                }) {
                Some(lang) => out.push_str(&format!("<pre class=\"language-{lang}\">")),
                None => out.push_str("<pre>"),
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
        // Tables as Teams draws them in messages (measured on winpc
        // 2026-11-12): collapsed 0.67 px #D1D1D1 borders, auto width, cells
        // padded 0 5 and centred vertically.
        if !closing && name == "table" {
            out.push_str("<table border=\"0.67\" cellspacing=\"0\" cellpadding=\"0\" style=\"border-collapse:collapse;border-color:#D1D1D1;border-style:solid\">");
            continue;
        }
        if !closing && (name == "td" || name == "th") {
            out.push_str(&format!("<{name} style=\"padding-left:5px;padding-right:5px;vertical-align:middle\">"));
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
    for open in spans {
        if open {
            out.push_str("</span>");
        }
    }
    while in_link > 0 {
        out.push_str("</a>");
        in_link -= 1;
    }
    (out, pics)
}

/// The part of a span's style Teams' formatting bar sets, made safe:
/// `background-color` and `color` (hex or rgb), and `font-size` (Teams'
/// sizes are CSS keywords; they become pixels as a browser draws them).
/// None when nothing is left.
fn text_style(style: &str) -> Option<String> {
    let color_ok = |v: &str| {
        (v.starts_with('#')
            && (4..=9).contains(&v.len())
            && v[1..].chars().all(|c| c.is_ascii_hexdigit()))
            || (v.starts_with("rgb(")
                && v.ends_with(')')
                && v[4..v.len() - 1]
                    .chars()
                    .all(|c| c.is_ascii_digit() || c == ',' || c == ' '))
    };
    let mut out: Vec<String> = Vec::new();
    for decl in style.split(';') {
        let Some((k, v)) = decl.split_once(':') else {
            continue;
        };
        let (k, v) = (k.trim().to_ascii_lowercase(), v.trim().to_ascii_lowercase());
        match k.as_str() {
            "background-color" | "color" if color_ok(&v) => out.push(format!("{k}:{v}")),
            "font-size" => {
                let px = match v.as_str() {
                    "xx-small" => Some(9),
                    "x-small" => Some(10),
                    "small" => Some(13),
                    "medium" => Some(16),
                    "large" => Some(18),
                    "x-large" => Some(24),
                    "xx-large" => Some(32),
                    _ => v
                        .strip_suffix("px")
                        .and_then(|n| n.trim().parse::<f32>().ok())
                        .map(|n| n.clamp(8.0, 48.0).round() as i32),
                };
                if let Some(px) = px {
                    out.push(format!("font-size:{px}px"));
                }
            }
            _ => {}
        }
    }
    (!out.is_empty()).then(|| out.join("; "))
}

/// Paragraphs holding Teams' bigger text get their taller line (Teams'
/// lines are 1.4286 × the size: 20 for 14, 34.3 for 24).
fn sized_lines(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    while let Some(i) = rest.find("<p>") {
        out.push_str(&rest[..i]);
        let body = &rest[i + 3..];
        let end = body.find("</p>").unwrap_or(body.len());
        let biggest = body[..end]
            .split("font-size:")
            .skip(1)
            .filter_map(|s| s.split("px").next()?.trim().parse::<f32>().ok())
            .fold(0.0f32, f32::max);
        if biggest > 14.0 {
            out.push_str(&format!(
                "<p style=\"line-height:{}px\">",
                (biggest * 20.0 / 14.0).round()
            ));
        } else {
            out.push_str("<p>");
        }
        rest = body;
    }
    out.push_str(rest);
    out
}

/// Whether sanitised HTML has text to show (emoticons count).
fn has_visible_text(html: &str) -> bool {
    !super::strip_html(&custom_emoji_as_text(html))
        .trim()
        .is_empty()
}

/// Text between pictures as Teams shows it: blank paragraphs stay (Teams
/// draws `<p>&nbsp;</p>` as an empty line), but text that is only blank
/// is dropped.
fn flow_text(html: &str) -> String {
    // A paragraph with nothing in it has no height in Teams.
    let t = html.replace("<p></p>", "");
    let t = t.trim();
    if has_visible_text(t) {
        t.to_string()
    } else {
        String::new()
    }
}

/// Marked HTML (`sanitize_core` with `mark_pics`) as the text before the
/// first picture and the flow after it. `index` maps a picture's tag to
/// its place in `images` + `media`. When nothing but blank text follows
/// the first picture (pictures after the text, the usual case), the flow
/// is empty and the text is returned as before.
fn split_flow(
    marked: &str,
    pics: &[String],
    index: impl Fn(&str) -> Option<usize>,
) -> (String, Vec<FlowPart>) {
    let lead = format!("<img src=\"{PIC_SRC}");
    // The next picture marker, quote or code block.
    let next = |s: &str| -> Option<usize> {
        [s.find(&lead), s.find("<blockquote>"), s.find("<pre")]
            .into_iter()
            .flatten()
            .min()
    };
    let Some(first) = next(marked) else {
        return (marked.to_string(), Vec::new());
    };
    let text_part = |html: String| FlowPart {
        html,
        ..Default::default()
    };
    let mut flow = Vec::new();
    let mut rest = &marked[first..];
    while let Some(j) = next(rest) {
        let text = flow_text(&rest[..j]);
        if !text.is_empty() {
            flow.push(text_part(text));
        }
        let at = &rest[j..];
        if at.starts_with("<blockquote>") {
            let end = block_end(at, "blockquote");
            let inner = &at["<blockquote>".len()
                ..end
                    .saturating_sub("</blockquote>".len())
                    .max("<blockquote>".len())];
            let inner = without_pic_markers(inner);
            flow.push(FlowPart {
                quote: Some(without_empty_paragraphs(&inner)),
                ..Default::default()
            });
            rest = &at[end..];
        } else if at.starts_with("<pre") {
            let open_end = at.find('>').map(|e| e + 1).unwrap_or(at.len());
            let lang = attr(&at[..open_end], "class")
                .and_then(|c| c.strip_prefix("language-").map(str::to_string))
                .unwrap_or_default();
            let close = at.find("</pre>").unwrap_or(at.len());
            let text = super::strip_html(
                &at[open_end..close]
                    .replace("<br />", "\n")
                    .replace("<br>", "\n"),
            );
            flow.push(FlowPart {
                code: Some(CodeBlock {
                    name: code_language_name(&lang).to_string(),
                    lang,
                    text: text.trim_end_matches('\n').to_string(),
                }),
                ..Default::default()
            });
            rest = &at[(close + "</pre>".len()).min(at.len())..];
        } else {
            let end = at.find('>').map(|e| e + 1).unwrap_or(at.len());
            let n = at[lead.len()..end]
                .split('"')
                .next()
                .and_then(|n| n.parse::<usize>().ok());
            if let Some(k) = n.and_then(|n| pics.get(n)).and_then(|t| index(t)) {
                flow.push(FlowPart {
                    pic: Some(k),
                    ..Default::default()
                });
            }
            rest = &at[end..];
        }
    }
    let text = flow_text(rest);
    if !text.is_empty() {
        flow.push(text_part(text));
    }
    if flow.iter().all(|p| p.pic.is_some()) {
        flow.clear();
    }
    (marked[..first].to_string(), flow)
}

/// Where an element opened at the start of `html` ends (after its closing
/// tag), counting nested ones.
fn block_end(html: &str, name: &str) -> usize {
    let (open, close) = (format!("<{name}"), format!("</{name}>"));
    let mut depth = 0usize;
    let mut i = 0usize;
    while i < html.len() {
        let rest = &html[i..];
        if rest.starts_with(&close) {
            depth = depth.saturating_sub(1);
            i += close.len();
            if depth == 0 {
                return i;
            }
        } else if rest.starts_with(&open) {
            depth += 1;
            i += open.len();
        } else {
            i += rest.chars().next().map(char::len_utf8).unwrap_or(1);
        }
    }
    html.len()
}

/// HTML without picture markers (pictures inside a quote aren't shown).
fn without_pic_markers(html: &str) -> String {
    let lead = format!("<img src=\"{PIC_SRC}");
    let mut out = String::new();
    let mut rest = html;
    while let Some(i) = rest.find(&lead) {
        out.push_str(&rest[..i]);
        let end = rest[i..].find('>').map(|e| i + e + 1).unwrap_or(rest.len());
        rest = &rest[end..];
    }
    out.push_str(rest);
    out
}

/// A received message as the edit box takes it (Teams keeps every
/// emoticon, custom emoji, GIF, sticker and picture when you edit): the
/// marked HTML with each one as an `<img>` the box shows, and what each is,
/// keyed by that `src`. Emoticons, custom emoji and AMS pictures keep
/// placeholder srcs (`ost-emoticon:`, `ost-custom-emoji:`, `ost-image:`)
/// that the client swaps for its cached files.
pub fn edit_form(
    marked: &str,
    pics: &[String],
    mentions: &[(String, String)],
) -> (String, Vec<ComposeMedia>) {
    let tokens = mentions_as_tokens(marked, mentions);
    let marked = tokens.as_str();
    let mut media: Vec<ComposeMedia> = Vec::new();
    let mut add = |m: ComposeMedia| {
        if !media.iter().any(|x| x.src == m.src) {
            media.push(m);
        }
    };
    let mut out = String::new();
    let mut rest = marked;
    while let Some(i) = rest.find("<img src=\"ost-") {
        out.push_str(&rest[..i]);
        let end = rest[i..].find('>').map(|e| i + e + 1).unwrap_or(rest.len());
        let tag = &rest[i..end];
        rest = &rest[end..];
        let src = attr(tag, "src").unwrap_or_default();
        let alt = attr(tag, "alt").unwrap_or_default();
        if let Some(n) = src
            .strip_prefix(PIC_SRC)
            .and_then(|n| n.parse::<usize>().ok())
        {
            let Some(pic) = pics.get(n) else { continue };
            let num = |k: &str| attr(pic, k).and_then(|v| v.parse().ok()).unwrap_or(0u32);
            let url = attr(pic, "src").unwrap_or_default();
            let title = attr(pic, "alt").unwrap_or_default();
            let (kind, (w, h)) = match media_kind(pic) {
                Some("gif") => ("gif", fit(num("width"), num("height"), 444, 250)),
                Some(_) => ("sticker", (180, 180)),
                None => ("image", fit(num("width"), num("height"), 240, 180)),
            };
            let id = if kind == "image" {
                attr(pic, "itemid").unwrap_or_default()
            } else {
                String::new()
            };
            // AMS objects need our token: the client shows its cached copy.
            let shown = if kind == "image" {
                if id.is_empty()
                    || !id
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
                {
                    continue;
                }
                format!("{IMAGE_SRC}{id}")
            } else {
                url.clone()
            };
            out.push_str(&format!(
                "<img src=\"{}\" width=\"{w}\" height=\"{h}\">",
                escape(&shown)
            ));
            add(ComposeMedia {
                src: shown,
                kind: kind.to_string(),
                id,
                title: match kind {
                    "gif" => title.trim_end_matches(" (GIF Image)").to_string(),
                    _ => title,
                },
                url,
                width: num("width"),
                height: num("height"),
                ..Default::default()
            });
        } else if let Some(doc) = src.strip_prefix(CUSTOM_EMOJI_SRC) {
            out.push_str(tag);
            add(ComposeMedia {
                src: src.clone(),
                kind: "custom".into(),
                id: format!("{alt};{doc}"),
                title: alt,
                ..Default::default()
            });
        } else if src == CONTACT_CARD_SRC {
            // A shared contact's icon: shown in the box; the contact's
            // token sends the card again.
            out.push_str(tag);
        } else if let Some(id) = src.strip_prefix(EMOTICON_SRC) {
            out.push_str(tag);
            add(ComposeMedia {
                src: src.clone(),
                kind: "emoji".into(),
                id: id.to_string(),
                title: attr(tag, "title").unwrap_or_default(),
                unicode: alt,
                ..Default::default()
            });
        }
    }
    out.push_str(rest);
    (between_tags_trimmed(&without_empty_paragraphs(&out)), media)
}

/// The message's mentions in order (`itemid`), as (mri, mentionType).
fn mention_list(props: Option<&serde_json::Value>) -> Vec<(String, String)> {
    let Some(raw) = props.and_then(|p| p.get("mentions")) else {
        return Vec::new();
    };
    let list: serde_json::Value = match raw {
        serde_json::Value::String(s) => serde_json::from_str(s).unwrap_or_default(),
        v => v.clone(),
    };
    let mut out: Vec<(i64, String, String)> = list
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| {
            let id = match m.get("itemid")? {
                serde_json::Value::Number(n) => n.as_i64()?,
                serde_json::Value::String(s) => s.parse().ok()?,
                _ => return None,
            };
            Some((
                id,
                m.get("mri")?.as_str()?.to_string(),
                m.get("mentionType")
                    .and_then(|t| t.as_str())
                    .unwrap_or("person")
                    .to_string(),
            ))
        })
        .collect();
    out.sort_by_key(|m| m.0);
    out.into_iter().map(|(_, mri, t)| (mri, t)).collect()
}

/// Sanitised HTML with each mention span (in order, matching `mentions`)
/// as the edit box's mention token: a link to `mention:{mri}` (or
/// `mention-everyone:`, `-channel:`, `-team:`, `-contact:`), so an edit
/// sends them again.
fn mentions_as_tokens(html: &str, mentions: &[(String, String)]) -> String {
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    let mut k = 0;
    while let Some(i) = rest.find("<span class=\"mention") {
        out.push_str(&rest[..i]);
        let open_end = rest[i..].find('>').map(|e| i + e + 1).unwrap_or(rest.len());
        let close = rest[open_end..]
            .find("</span>")
            .map(|e| open_end + e)
            .unwrap_or(rest.len());
        let text = &rest[open_end..close];
        match mentions.get(k) {
            Some((mri, kind)) => {
                let scheme = match kind.as_str() {
                    "everyone" => "mention-everyone",
                    "channel" => "mention-channel",
                    "team" => "mention-team",
                    "tag" => "mention-tag",
                    "share-contact" => "mention-contact",
                    _ => "mention",
                };
                out.push_str(&format!("<a href=\"{scheme}:{}\">{text}</a>", escape(mri)));
            }
            None => out.push_str(text),
        }
        k += 1;
        rest = &rest[(close + "</span>".len()).min(rest.len())..];
    }
    out.push_str(rest);
    out
}

/// HTML without the line breaks and spaces between its tags (Qt's editor
/// would keep them as a space, sent back as `<p> </p>`).
fn between_tags_trimmed(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    while let Some(i) = rest.find('>') {
        out.push_str(&rest[..=i]);
        rest = &rest[i + 1..];
        let ws = rest.len() - rest.trim_start().len();
        if rest[ws..].starts_with('<') {
            rest = &rest[ws..];
        }
    }
    out.push_str(rest);
    out
}

/// What a quoted reply to a message shows of it, as Teams' quoted-reply
/// preview (QuotedReplyContent) builds it: the text, with emoticons as
/// their character, custom emoji as `:name:`, any picture (GIF, sticker,
/// AMS image) as " 📷 ", an AMS video as " 🎥 " and list items numbered or
/// bulleted; whitespace collapsed. Teams stops taking parts once it has
/// more than 200 characters.
pub fn quote_preview(content: &str) -> String {
    const ENOUGH: usize = 200;
    let mut out = String::new();
    let mut rest = content;
    // Open lists: Some(count) for <ol>, None for <ul>.
    let mut lists: Vec<Option<usize>> = Vec::new();
    let mut skip_until: Option<String> = None;
    let push = |out: &mut String, piece: &str| {
        if out.chars().count() <= ENOUGH {
            out.push_str(piece);
        }
    };
    while let Some(lt) = rest.find('<') {
        if skip_until.is_none() {
            push(&mut out, &super::strip_html(&rest[..lt]));
        }
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
        if let Some(until) = &skip_until {
            if closing && &name == until {
                skip_until = None;
            }
            continue;
        }
        let itemtype = attr(tag, "itemtype").unwrap_or_default();
        if !closing && (itemtype.ends_with("schema.skype.com/AMSVideo") || name == "video") {
            push(&mut out, " \u{1F3A5} ");
            if !tag.ends_with('/') {
                skip_until = Some(name);
            }
            continue;
        }
        match (name.as_str(), closing) {
            ("img", _) => {
                let alt = attr(tag, "alt").unwrap_or_default();
                if itemtype.ends_with("schema.skype.com/Emoji") {
                    push(&mut out, &alt);
                } else if itemtype.ends_with("schema.skype.com/CustomEmoji") {
                    push(&mut out, &format!(":{alt}:"));
                } else {
                    push(&mut out, " \u{1F4F7} ");
                }
            }
            ("ol", false) => lists.push(Some(0)),
            ("ul", false) => lists.push(None),
            ("ol" | "ul", true) => {
                lists.pop();
            }
            ("li", false) => match lists.last_mut() {
                Some(Some(n)) => {
                    *n += 1;
                    let n = *n;
                    push(&mut out, &format!(" {n}. "));
                }
                Some(None) => push(&mut out, " \u{2022} "),
                None => {}
            },
            ("p" | "div" | "br" | "li", _) => push(&mut out, " "),
            _ => {}
        }
    }
    if skip_until.is_none() {
        push(&mut out, &super::strip_html(rest));
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Where a shared contact's card icon goes in message HTML; the client
/// draws its contact-card icon there.
pub const CONTACT_CARD_SRC: &str = "ost-contact-card";

/// Teams' picture for the ID card emoticon it sends before a shared
/// contact (a 64 px PNG, sent inline exactly as Teams sends it).
const SHARE_CONTACT_IDCARD_PNG: &str = include_str!("share_contact_idcard.b64");

/// Where an AMS picture goes in the edit box until the client puts its
/// cached file there.
pub const IMAGE_SRC: &str = "ost-image:";

/// Where a custom emoji's picture goes in message HTML until the client
/// puts its cached file there.
pub const CUSTOM_EMOJI_SRC: &str = "ost-custom-emoji:";

/// The custom emoji pictures (document ids) a message's HTML needs.
pub fn custom_emoji_docs(html: &str) -> Vec<String> {
    html.split(CUSTOM_EMOJI_SRC)
        .skip(1)
        .filter_map(|r| r.split('"').next())
        .map(str::to_string)
        .collect()
}

/// Sanitised HTML with each custom emoji as `:name:` (Teams' plain-text
/// form, as in previews and notifications) and each emoticon as its
/// character.
fn custom_emoji_as_text(html: &str) -> String {
    let mut out = String::new();
    let mut rest = html;
    while let Some(i) = rest.find("<img src=\"ost-") {
        out.push_str(&rest[..i]);
        let end = rest[i..].find('>').map(|e| i + e + 1).unwrap_or(rest.len());
        let tag = &rest[i..end];
        let alt = attr(tag, "alt").unwrap_or_default();
        if tag.contains(CUSTOM_EMOJI_SRC) {
            out.push_str(&format!(":{alt}:"));
        } else {
            out.push_str(&alt);
        }
        rest = &rest[end..];
    }
    out.push_str(rest);
    out
}

/// Where a Teams emoticon's picture goes in message HTML until the client
/// puts its cached file there.
pub const EMOTICON_SRC: &str = "ost-emoticon:";

/// The emoticon ids a message's HTML shows.
pub fn emoticon_ids(html: &str) -> Vec<String> {
    html.split(EMOTICON_SRC)
        .skip(1)
        .filter_map(|r| r.split('"').next())
        .map(str::to_string)
        .collect()
}

/// Teams' big emoticons (async-entry BigEmoticonPreprocessor): a message of
/// only one to three emoticons or custom emoji, without other text,
/// pictures or line breaks, shows them at 50 px instead of 20.
pub fn big_emoticons(html: &str) -> bool {
    let markers = html.matches("<img src=\"ost-").count();
    if markers == 0 || markers > 3 || html.contains("<br") {
        return false;
    }
    let mut rest = html;
    let mut others = String::new();
    while let Some(i) = rest.find("<img") {
        others.push_str(&rest[..i]);
        let end = rest[i..].find('>').map(|e| i + e + 1).unwrap_or(rest.len());
        if !rest[i..end].starts_with("<img src=\"ost-") {
            return false;
        }
        rest = &rest[end..];
    }
    others.push_str(rest);
    super::strip_html(&others)
        .replace(
            ['\u{a0}', '\u{200b}', '\u{200c}', '\u{200d}', '\u{feff}'],
            "",
        )
        .trim()
        .is_empty()
}

/// The message HTML without the empty paragraphs Teams puts around GIFs,
/// stickers and pictures (`<p>&nbsp;</p>`), which show as nothing there.
fn without_empty_paragraphs(html: &str) -> String {
    let mut out = html.to_string();
    for empty in ["<p>&nbsp;</p>", "<p>\u{a0}</p>", "<p> </p>", "<p></p>"] {
        out = out.replace(empty, "");
    }
    out.trim().to_string()
}

/// Whether an `<img>` tag is a GIF or sticker from the fun picker, and which.
fn media_kind(tag: &str) -> Option<&'static str> {
    let src = attr(tag, "src")?;
    let u = url::Url::parse(&src).ok()?;
    if u.scheme() != "https" {
        return None;
    }
    let host = u.host_str()?;
    let sticker = attr(tag, "itemtype").is_some_and(|t| t.ends_with("schema.skype.com/Sticker"));
    if sticker && host == "teams.public.onecdn.static.microsoft" {
        Some("sticker")
    } else if host.starts_with("media") && host.ends_with(".giphy.com") {
        Some("gif")
    } else {
        None
    }
}

/// GIFs and stickers in a message's HTML.
fn message_media(html: &str) -> Vec<MessageMedia> {
    let mut out = Vec::new();
    let mut rest = html;
    while let Some(i) = rest.find("<img") {
        let end = rest[i..].find('>').map(|e| i + e).unwrap_or(rest.len());
        let tag = &rest[i..end];
        rest = &rest[end..];
        let Some(kind) = media_kind(tag) else {
            continue;
        };
        let num = |k: &str| attr(tag, k).and_then(|v| v.parse().ok()).unwrap_or(0);
        out.push(MessageMedia {
            kind: kind.to_string(),
            url: attr(tag, "src").unwrap_or_default(),
            width: num("width"),
            height: num("height"),
            alt: attr(tag, "alt")
                .map(|a| super::strip_html(&a))
                .unwrap_or_default(),
        });
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

/// The body of Teams' edit (`PUT …/messages/{id}`), built from the
/// original as Teams does: the new content, the original's client message
/// id and properties (importance, files, cards, links, mentions), the
/// quote's `qtdMsgs` when the quote stays, and `edittime`.
pub fn edit_body(
    original: &serde_json::Value,
    content: &str,
    quote: Option<&Quote>,
    edit_ms: i64,
) -> serde_json::Value {
    let props = original.get("properties").cloned().unwrap_or_default();
    let keep = |k: &str, default: &str| -> serde_json::Value {
        match props.get(k) {
            Some(serde_json::Value::String(s)) => s.clone().into(),
            Some(v) if !v.is_null() => v.to_string().into(),
            _ => default.into(),
        }
    };
    let content = match quote {
        Some(q) => format!("{}{}", quote_html(q), content),
        None => content.to_string(),
    };
    let mut body = serde_json::json!({
        "id": original.get("id").cloned().unwrap_or_default(),
        "type": "Message",
        "conversationid": original.get("conversationid").cloned().unwrap_or_default(),
        "content": content,
        "messagetype": "RichText/Html",
        "contenttype": "Text",
        "imdisplayname": original.get("imdisplayname").cloned().unwrap_or_default(),
        "clientmessageid": original.get("clientmessageid").cloned().unwrap_or_default(),
        "properties": {
            "importance": keep("importance", ""),
            "cards": keep("cards", "[]"),
            "links": keep("links", "[]"),
            "mentions": keep("mentions", "[]"),
            "files": keep("files", "[]"),
            "formatVariant": "TEAMS",
            "edittime": edit_ms,
        },
    });
    if let Some(q) = quote {
        body["properties"]["qtdMsgs"] = quoted_messages_property(q).into();
    }
    body
}

/// Edit one of our messages as Teams does: `content` is Teams HTML (the
/// editor's, formatting kept) and `quote` the quote it keeps, if any.
pub async fn edit_message_html(
    client: &TeamsClient,
    chat_id: &str,
    message_id: &str,
    content: &str,
    quote: Option<&Quote>,
    mentions: Option<&[OutMention]>,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}",
        client.chat_service_url(),
        chat_id,
        message_id
    );
    let original: serde_json::Value = client.chat_get(&url).await?.json().await?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or_default();
    let mut body = edit_body(&original, content, quote, now);
    // The edited text's own mentions (an edit can add or remove them).
    if let Some(m) = mentions {
        body["properties"]["mentions"] = serde_json::to_string(m)
            .unwrap_or_else(|_| "[]".into())
            .into();
    }
    client
        .chat_request(reqwest::Method::PUT, &url, &body)
        .await?;
    Ok(())
}

/// Edit one of our messages to plain text, keeping its quote.
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
    let original: serde_json::Value = client.chat_get(&url).await?.json().await?;
    let (quote, _) = split_quote(original["content"].as_str().unwrap_or_default());
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or_default();
    let content = format!("<p>{}</p>", html_escape(text));
    let body = edit_body(&original, &content, quote.as_ref(), now);
    client
        .chat_request(reqwest::Method::PUT, &url, &body)
        .await?;
    Ok(())
}

/// Delete one of our messages.
pub async fn delete_message(client: &TeamsClient, chat_id: &str, message_id: &str) -> Result<()> {
    // Teams' deleteMessage: a soft delete, so it can be undone.
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}?behavior=softDelete",
        client.chat_service_url(),
        chat_id,
        message_id
    );
    client
        .chat_request(reqwest::Method::DELETE, &url, &serde_json::json!({}))
        .await?;
    Ok(())
}

/// Undo a delete, as Teams' undeleteMessage does: remove the message's
/// `deletetime` property.
pub async fn undelete_message(client: &TeamsClient, chat_id: &str, message_id: &str) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/{}/properties?name=deletetime",
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
pub async fn peer_read_horizon(client: &TeamsClient, chat_id: &str) -> Result<Option<SeenRule>> {
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
    if let Some(n) = serde_json::from_str::<serde_json::Value>(&text)
        .ok()
        .and_then(|v| v.get("consumptionhorizons")?.as_array().map(Vec::len))
    {
        rosters().lock().unwrap().insert(chat_id.to_string(), n);
    }
    Ok(peer_horizon(&text, &me))
}

fn rosters() -> &'static std::sync::Mutex<std::collections::HashMap<String, usize>> {
    use std::sync::{Mutex, OnceLock};
    static ROSTERS: OnceLock<Mutex<std::collections::HashMap<String, usize>>> = OnceLock::new();
    ROSTERS.get_or_init(Default::default)
}

/// How many members a chat had when its read horizons were last read
/// (each member has one).
pub fn roster_size(chat_id: &str) -> Option<usize> {
    rosters().lock().unwrap().get(chat_id).copied()
}

/// Teams' group-chat roster limit for typing indicators and read receipts
/// (`maxRosterSizeInGroupChatChatServiceLimit`, live 20).
pub const MAX_ROSTER: usize = 20;

/// When a message counts as Seen, by Teams' rule (module 434910): read
/// by every other member, `arrival ≤ min(their horizons)`, and not before
/// any member could see it, `arrival ≥ max(their messageVisibilityTime)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SeenRule {
    pub read_to: u64,
    pub visible_from: u64,
}

/// Teams' Seen rule from a `/threads/{id}/consumptionhorizons` reply
/// ("arrivalMs;timestampMs;clientMsgId" each). None when receipts don't
/// apply: fewer than 2 or more than 20 members, or another member has no
/// horizon yet.
pub fn peer_horizon(json: &str, me: &str) -> Option<SeenRule> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let all = v.get("consumptionhorizons")?.as_array()?;
    if !(2..=MAX_ROSTER).contains(&all.len()) {
        return None;
    }
    let mut read_to = u64::MAX;
    let mut visible_from = 0u64;
    for h in all.iter().filter(|h| {
        h.get("id")
            .and_then(|i| i.as_str())
            .is_some_and(|i| !i.eq_ignore_ascii_case(me))
    }) {
        let at: u64 = h
            .get("consumptionhorizon")
            .and_then(|c| c.as_str())
            .and_then(|c| c.split(';').next())
            .and_then(|c| c.parse().ok())?;
        read_to = read_to.min(at);
        let vis = h
            .get("messageVisibilityTime")
            .and_then(|t| {
                t.as_u64()
                    .or_else(|| t.as_str().and_then(|s| s.parse().ok()))
            })
            .unwrap_or(0);
        visible_from = visible_from.max(vis);
    }
    (read_to != u64::MAX).then_some(SeenRule {
        read_to,
        visible_from,
    })
}

/// How far you had read a chat: the message id in your consumption horizon.
/// What the chat service says of a conversation that the lists don't
/// always carry.
#[derive(Debug, Default, PartialEq)]
pub struct ConversationFacts {
    /// When you removed its history (Teams' `clearHistoryTime`, ms):
    /// messages up to then aren't shown.
    pub cleared_ms: Option<u64>,
    /// A channel's layout (`threadProperties.chatModalityType`:
    /// "Conversational" or "PostReply"); the teams list leaves it out for
    /// some members.
    pub modality: Option<String>,
}

impl ConversationFacts {
    pub fn from_reply(v: &serde_json::Value) -> Self {
        Self {
            cleared_ms: v
                .pointer("/properties/clearHistoryTime")
                .and_then(|h| h.as_str().and_then(|s| s.parse().ok()).or_else(|| h.as_u64()))
                .filter(|t| *t > 0),
            modality: v
                .pointer("/threadProperties/chatModalityType")
                .and_then(|m| m.as_str())
                .filter(|m| !m.is_empty())
                .map(str::to_string),
        }
    }
}

/// A channel's layout from its thread (`/v1/threads/{id}`,
/// `properties.chatModalityType`), which members can read before they've
/// opened the channel (their own conversation of it doesn't exist yet).
pub async fn thread_modality(client: &TeamsClient, thread_id: &str) -> Result<Option<String>> {
    let url = format!("{}/v1/threads/{}?view=msnp24Equivalent", client.chat_service_url(), thread_id);
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Thread reply")?;
    Ok(v.pointer("/properties/chatModalityType")
        .and_then(|m| m.as_str())
        .filter(|m| !m.is_empty())
        .map(str::to_string))
}

pub async fn conversation_facts(client: &TeamsClient, chat_id: &str) -> Result<ConversationFacts> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        chat_id
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Conversation reply")?;
    Ok(ConversationFacts::from_reply(&v))
}

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
    Ok(read_position(
        v.pointer("/properties/consumptionhorizon").and_then(|h| h.as_str()),
        v.pointer("/properties/consumptionHorizonBookmark").and_then(|h| h.as_str()),
    ))
}

/// Your read position: the consumption horizon, unless Mark as unread
/// set the bookmark after it (both "{id};{time};{clientMessageId}"), as
/// Teams reads them: then the bookmark's.
pub fn read_position(horizon: Option<&str>, bookmark: Option<&str>) -> Option<u64> {
    let parse = |s: &str| {
        let mut it = s.split(';');
        let id = it.next()?.parse::<u64>().ok()?;
        let time = it.next().and_then(|t| t.parse::<u64>().ok()).unwrap_or(0);
        Some((id, time))
    };
    let h = horizon.and_then(parse);
    match (h, bookmark.and_then(parse)) {
        (Some((_, ht)), Some((bid, bt))) if bt >= ht => Some(bid),
        (None, Some((bid, _))) => Some(bid),
        (Some((hid, _)), _) => Some(hid),
        (None, None) => None,
    }
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
pub fn apply_seen(timeline: &mut [MessageView], rule: Option<SeenRule>) {
    let Some(r) = rule else { return };
    for m in timeline.iter_mut().filter(|m| m.mine) {
        m.seen =
            m.id.parse::<u64>()
                .is_ok_and(|id| id <= r.read_to && id >= r.visible_from);
    }
}

/// A chat's newest message: its id and client message id.
async fn latest_message(client: &TeamsClient, chat_id: &str) -> Result<(String, String)> {
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
    Ok((id.to_string(), client_id.to_string()))
}

/// Mark a chat read up to its newest message (for "Mark all as read").
pub async fn mark_chat_read_to_latest(client: &TeamsClient, chat_id: &str) -> Result<()> {
    let (id, client_id) = latest_message(client, chat_id).await?;
    mark_read(client, chat_id, &id, &client_id).await
}

/// Mark a chat unread from its newest message, as the chat list's Mark as
/// unread does (Teams' consumption-horizon bookmark).
pub async fn mark_chat_unread_from_latest(client: &TeamsClient, chat_id: &str) -> Result<()> {
    let (id, client_id) = latest_message(client, chat_id).await?;
    let arrival = id.parse::<i64>().context("Message id is not a time")?;
    super::msgactions::mark_unread(client, chat_id, arrival, &client_id).await
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
    teams_html_and_mentions(qt).0
}

/// A mention in a message we send (Teams' `properties.mentions` entry).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct OutMention {
    #[serde(rename = "@type")]
    pub kind: &'static str,
    pub itemid: usize,
    pub mri: String,
    #[serde(rename = "mentionType")]
    pub mention_type: &'static str,
    #[serde(rename = "displayName")]
    pub display_name: String,
}

/// Editor HTML to Teams HTML, with the editor's mention tokens (links to
/// `mention:{mri}`) turned into Teams' mention spans
/// (`<span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="N">`)
/// and listed for `properties.mentions`.
/// Something the fun picker put in the compose box as an `<img>` (keyed by
/// that image's `src`), sent as Teams sends it.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ComposeMedia {
    /// The `src` the compose box shows it with.
    pub src: String,
    /// "emoji", "gif" or "sticker".
    pub kind: String,
    /// Emoji: the emoticon id; its description and unicode character.
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub unicode: String,
    /// GIF or sticker: what's sent, and its size.
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub width: u32,
    #[serde(default)]
    pub height: u32,
    /// "image": the local PNG to upload first.
    #[serde(default)]
    pub path: String,
}

/// Teams' HTML for a picked emoticon, GIF or sticker (captured from Teams'
/// own messages). Emoticons sit in the line; GIFs and stickers get their own
/// block between empty paragraphs.
pub fn compose_media_html(m: &ComposeMedia) -> String {
    match m.kind.as_str() {
        "emoji" => format!(
            "<span title=\"{t}\" type=\"({id})\" class=\"animated-emoticon-20-{id}\" itemscope=\"\"><img itemscope=\"\" itemtype=\"http://schema.skype.com/Emoji\" itemid=\"{id}\" src=\"https://statics.teams.cdn.office.net/evergreen-assets/personal-expressions/v2/assets/emoticons/{id}/default/20_f.png\" title=\"{t}\" alt=\"{u}\" style=\"width:20px; height:20px\"></span>",
            t = escape(&m.title),
            id = escape(&m.id),
            u = escape(&m.unicode),
        ),
        "gif" => {
            // Teams fits a GIF into 444 x 250 (480 x 270 went out as 444 x 250).
            let (w, h) = fit(m.width, m.height, 444, 250);
            format!(
                "</p><p>&nbsp;</p>\n<img src=\"{}\" width=\"{w}\" height=\"{h}\" alt=\"{} (GIF Image)\" style=\"height:auto; margin-top:4px; max-width:100%\">\n<p>&nbsp;</p><p>",
                escape(&m.url),
                escape(&m.title)
            )
        }
        // A picture uploaded to AMS (a captioned sticker): `url` is the
        // object's imgo view and `id` its object id, as Teams sends it (the
        // service prefixes the element id with "x_" itself).
        "image" => {
            let (w, h) = fit(m.width, m.height, 240, 180);
            format!(
                "</p><p>&nbsp;</p>\n<img src=\"{u}\" width=\"{w}\" height=\"{h}\" itemscope=\"image/png\" itemtype=\"http://schema.skype.com/AMSImage\" alt=\"{t}\" id=\"{id}\" itemid=\"{id}\">\n<p>&nbsp;</p><p>",
                u = escape(&m.url),
                t = escape(&m.title),
                id = escape(&m.id),
            )
        }
        // A custom emoji (CustomEmojiSerializer): `id` "{name};{documentId}",
        // `url` its imgt2_anim view, `title` its name.
        "custom" => format!(
            "<span contenteditable=\"false\"><img alt=\"{n}\" itemid=\"{id}\" itemtype=\"http://schema.skype.com/CustomEmoji\" src=\"{u}\" style=\"width:20px;height:20px;\"></span>",
            n = escape(&m.title),
            id = escape(&m.id),
            u = escape(&m.url),
        ),
        "sticker" => format!(
            "</p><p>&nbsp;</p>\n<img src=\"{}\" height=\"180\" alt=\"{}\" width=\"180\" itemtype=\"http://schema.skype.com/Sticker\">\n<p>&nbsp;</p><p>",
            escape(&m.url),
            escape(&m.title)
        ),
        _ => String::new(),
    }
}

/// The highlight, font colour and size of a compose span (`style`, lower
/// case without spaces) as Teams writes them: `background-color:#FDD472;
/// color:#B6424C; font-size:x-large` (Large 24 px, Small 13 px).
fn teams_text_style(style: &str) -> Option<String> {
    let get = |k: &str| {
        style
            .split(';')
            .find_map(|d| d.strip_prefix(k))
            .map(|v| v.trim().to_string())
    };
    let hex = |v: String| {
        (v.starts_with('#') && v.len() == 7 && v[1..].chars().all(|c| c.is_ascii_hexdigit()))
            .then(|| v.to_ascii_uppercase())
    };
    let mut out: Vec<String> = Vec::new();
    if let Some(c) = get("background-color:").and_then(hex) {
        out.push(format!("background-color:{c}"));
    }
    if let Some(c) = get("color:").and_then(hex) {
        out.push(format!("color:{c}"));
    }
    if let Some(px) = get("font-size:").and_then(|v| v.trim_end_matches("px").parse::<u32>().ok()) {
        out.push(format!(
            "font-size:{}",
            match px {
                24 => "x-large".to_string(),
                13 => "small".to_string(),
                n => format!("{n}px"),
            }
        ));
    }
    (!out.is_empty()).then(|| out.join("; "))
}

/// `w` x `h` scaled down to fit `max_w` x `max_h`, rounded.
fn fit(w: u32, h: u32, max_w: u32, max_h: u32) -> (u32, u32) {
    if w == 0 || h == 0 {
        return (max_w.min(w.max(1)), max_h.min(h.max(1)));
    }
    let scale = (max_w as f64 / w as f64)
        .min(max_h as f64 / h as f64)
        .min(1.0);
    (
        (w as f64 * scale).floor() as u32,
        (h as f64 * scale).round() as u32,
    )
}

pub fn teams_html_and_mentions(qt: &str) -> (String, Vec<OutMention>) {
    teams_html_with_media(qt, &[])
}

/// The compose box's HTML as Teams HTML, with mentions, and the picker's
/// emoticons, GIFs and stickers in Teams' own form.
pub fn teams_html_with_media(qt: &str, media: &[ComposeMedia]) -> (String, Vec<OutMention>) {
    let mut mentions: Vec<OutMention> = Vec::new();
    // For each open <a>: whether it is a mention (closed as </span>).
    let mut anchors: Vec<bool> = Vec::new();
    let mut mention_text: Option<String> = None;
    // Where the open mention's span content starts (it is sent as plain text).
    let mut mention_start = 0usize;
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
    // Inside a code block, line breaks are the code's.
    let mut in_pre = false;
    let mut rest = body;
    while let Some(lt) = rest.find('<') {
        let text = &rest[..lt];
        if in_pre {
            out.push_str(text);
        } else {
            out.push_str(&text.replace(['\n', '\r'], ""));
        }
        if let Some(t) = mention_text.as_mut() {
            t.push_str(text);
        }
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
            // Teams' code block editor's paragraph before the block.
            ("p", false)
                if editor_attr(tag, "itemtype").as_deref()
                    == Some("http://schema.skype.com/CodeBlockEditor") =>
            {
                out.push_str(&format!(
                    "<p itemtype=\"http://schema.skype.com/CodeBlockEditor\" id=\"{}\">",
                    escape(&editor_attr(tag, "id").unwrap_or_default())
                ));
            }
            // An indented paragraph (the formatting bar's Increase indent).
            ("p", false) if style.starts_with("margin-left:") => {
                let px: u32 = style["margin-left:".len()..]
                    .trim_end_matches(';')
                    .trim_end_matches("px")
                    .parse()
                    .unwrap_or(0);
                if px > 0 {
                    out.push_str(&format!("<p style=\"margin-left:{px}px\">"));
                } else {
                    out.push_str("<p>");
                }
            }
            ("p", false) => out.push_str("<p>"),
            ("p", true) => out.push_str("</p>"),
            ("h1" | "h2" | "h3" | "blockquote" | "code", _) => {
                out.push('<');
                if closing {
                    out.push('/');
                }
                out.push_str(&name);
                out.push('>');
            }
            ("hr", false) => out.push_str("<hr>"),
            // A table, as Teams' editor sends it (no attributes).
            ("table" | "tbody" | "tr" | "td", _) => {
                out.push('<');
                if closing {
                    out.push('/');
                }
                out.push_str(&name);
                out.push('>');
            }
            // A code block (its language and the editor's id).
            ("pre", false) => {
                let lang = editor_attr(tag, "class")
                    .and_then(|c| c.strip_prefix("language-").map(str::to_string))
                    .filter(|l| l.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'))
                    .unwrap_or_else(|| "plaintext".into());
                out.push_str(&format!("<pre class=\"language-{lang}\""));
                if let Some(id) = editor_attr(tag, "itemid") {
                    out.push_str(&format!(" itemid=\"{}\"", escape(&id)));
                }
                out.push('>');
                in_pre = true;
            }
            ("pre", true) => {
                out.push_str("</pre>");
                in_pre = false;
            }
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
                // Highlight, font colour and size, as Teams writes them (a
                // link's own colour isn't one).
                if anchors.is_empty()
                    && let Some(css) = teams_text_style(&style)
                {
                    out.push_str(&format!("<span style=\"{css}\">"));
                    opened.push("span");
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
            ("a", false) => {
                let href = editor_attr(tag, "href").unwrap_or_default();
                let target = href
                    .strip_prefix("mention-everyone:")
                    .map(|c| (c, "everyone"))
                    // A channel or a team (its General channel's thread id),
                    // as Teams' channel picker sends them.
                    .or_else(|| {
                        href.strip_prefix("mention-channel:")
                            .map(|c| (c, "channel"))
                    })
                    .or_else(|| href.strip_prefix("mention-team:").map(|t| (t, "team")))
                    // A team tag (its tagId).
                    .or_else(|| href.strip_prefix("mention-tag:").map(|t| (t, "tag")))
                    // A shared contact (Share someone's contact info).
                    .or_else(|| {
                        href.strip_prefix("mention-contact:")
                            .map(|m| (m, "share-contact"))
                    })
                    .or_else(|| href.strip_prefix("mention:").map(|m| (m, "person")));
                if let Some((mri, mention_type)) = target {
                    let itemid = mentions.len();
                    let scope = if mention_type == "share-contact" {
                        // Teams' ID card emoticon goes first.
                        out.push_str(&format!(
                            "<span title=\"ID card\" type=\"(idcard)\" class=\"animated-emoticon-20-idcard\" itemscope=\"Share_Contact_Card\"><img itemscope=\"\" itemtype=\"http://schema.skype.com/Emoji\" itemid=\"idcard\" src=\"data:image/png;base64,{}\" title=\"ID card\" alt=\"\u{1FAAA}\" style=\"width:20px; height:20px\"></span>",
                            SHARE_CONTACT_IDCARD_PNG.trim()
                        ));
                        "Share_Contact_Card"
                    } else {
                        ""
                    };
                    if mention_type == "tag" {
                        // As Teams posted a tag mention (OST Test Team, on
                        // winpc): its editor's read-only wrapper stays.
                        out.push_str(&format!(
                            "<readonly class=\"skipProofing\" itemtype=\"http://schema.skype.com/Mention\" spellcheck=\"false\"><span itemtype=\"http://schema.skype.com/Mention\" itemscope itemid=\"{itemid}\">"
                        ));
                    } else {
                        out.push_str(&format!(
                            "<span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"{scope}\" itemid=\"{itemid}\">"
                        ));
                    }
                    mentions.push(OutMention {
                        kind: "http://schema.skype.com/Mention",
                        itemid,
                        mri: mri.to_string(),
                        mention_type,
                        display_name: String::new(),
                    });
                    anchors.push(true);
                    mention_text = Some(String::new());
                    mention_start = out.len();
                } else if href.starts_with("https://") || href.starts_with("http://") {
                    // As Teams' compose writes a link.
                    let h = href.replace('"', "&quot;");
                    out.push_str(&format!(
                        "<a href=\"{h}\" rel=\"noreferrer noopener\" target=\"_blank\" title=\"{h}\">"
                    ));
                    anchors.push(false);
                } else {
                    out.push_str("<a>");
                    anchors.push(false);
                }
            }
            ("img", false) => {
                if let Some(src) = editor_attr(tag, "src")
                    && let Some(m) = media.iter().find(|m| m.src == src)
                {
                    out.push_str(&compose_media_html(m));
                }
            }
            ("a", true) => {
                if anchors.pop().unwrap_or(false) {
                    let name = super::strip_html(&mention_text.take().unwrap_or_default())
                        .trim()
                        .to_string();
                    out.truncate(mention_start);
                    out.push_str(&escape(&name));
                    out.push_str("</span>");
                    if mentions.last().is_some_and(|m| m.mention_type == "tag") {
                        out.push_str("</readonly>");
                    }
                    if let Some(m) = mentions.last_mut() {
                        m.display_name = name;
                    }
                } else {
                    out.push_str("</a>");
                }
            }
            _ => {}
        }
    }
    out.push_str(&rest.replace(['\n', '\r'], ""));
    let html = out
        .replace("<p></p>", "")
        .replace("<p><br></p>", "")
        .trim()
        .to_string();
    (html, mentions)
}

#[cfg(test)]
mod compose_media_tests {
    use super::*;

    #[test]
    fn formatting_bar_output_is_sent_as_teams_sends_it() {
        // What the compose box's RichText exports for "OST TEST 66"…
        let ours = r#"<blockquote><p><span style="background-color:#FDD472">OST TEST 66 highlighted</span></p></blockquote><p><span style="background-color:#FDD472; color:#B6424C">red text</span></p><p><span style="font-size:24px">large text</span></p>"#;
        let (html, _) = teams_html_and_mentions(ours);
        // …goes out as Teams sent it (its line breaks aside; Teams' reset
        // of the colours to inherit isn't needed).
        assert_eq!(
            html,
            r#"<blockquote><p><span style="background-color:#FDD472">OST TEST 66 highlighted</span></p></blockquote><p><span style="background-color:#FDD472; color:#B6424C">red text</span></p><p><span style="font-size:x-large">large text</span></p>"#
        );
        // A code block keeps its lines, language and the editor's id.
        let code = "<p>see</p><p itemtype=\"http://schema.skype.com/CodeBlockEditor\" id=\"codeBlockEditor-1\">&nbsp;</p><pre class=\"language-rust\" itemid=\"codeBlockEditor-1\"><code>let x = 1;\nlet y = x &lt; 2;</code></pre>";
        assert_eq!(teams_html_and_mentions(code).0, code);
        // Headings, rules, inline code and indents pass through.
        let rest = r#"<h2>Plan</h2><hr><p>run <code>cargo</code></p><p style="margin-left:40px">later</p>"#;
        assert_eq!(teams_html_and_mentions(rest).0, rest);
    }

    #[test]
    fn picked_items_are_sent_as_teams_sends_them() {
        let emoji = ComposeMedia {
            src: "file:///c/surprised.png".into(),
            kind: "emoji".into(),
            id: "surprised".into(),
            title: "Surprised".into(),
            unicode: "😮".into(),
            ..Default::default()
        };
        let gif = ComposeMedia {
            src: "https://media3.giphy.com/x/200w.gif".into(),
            kind: "gif".into(),
            url: "https://media3.giphy.com/x/giphy.gif".into(),
            title: "Pedro Pascal Laughing GIF by Crafture".into(),
            width: 480,
            height: 270,
            ..Default::default()
        };
        let editor = r#"<html><body><p>hi <img src="file:///c/surprised.png" width="20" height="20" /><img src="https://media3.giphy.com/x/200w.gif" width="200" height="113" /></p></body></html>"#;
        let (html, _) = teams_html_with_media(editor, &[emoji, gif]);
        // As Teams' own surprised emoticon and GIF messages read.
        assert!(html.starts_with(r#"<p>hi <span title="Surprised" type="(surprised)" class="animated-emoticon-20-surprised" itemscope=""><img itemscope="" itemtype="http://schema.skype.com/Emoji" itemid="surprised" src="https://statics.teams.cdn.office.net/evergreen-assets/personal-expressions/v2/assets/emoticons/surprised/default/20_f.png" title="Surprised" alt="😮" style="width:20px; height:20px"></span></p>"#), "{html}");
        assert!(html.contains(r#"<p>&nbsp;</p>
<img src="https://media3.giphy.com/x/giphy.gif" width="444" height="250" alt="Pedro Pascal Laughing GIF by Crafture (GIF Image)" style="height:auto; margin-top:4px; max-width:100%">
<p>&nbsp;</p>"#), "{html}");
        // A captioned sticker, once uploaded, reads as Teams' own did.
        let img = ComposeMedia {
            src: "file:///t/s.png".into(),
            kind: "image".into(),
            id: "0-wus-d8-6d53".into(),
            url: "https://us-api.asm.skype.com/v1/objects/0-wus-d8-6d53/views/imgo".into(),
            title: "Sticker image, OST TEST 56".into(),
            width: 320,
            height: 240,
            ..Default::default()
        };
        let (h2, _) = teams_html_with_media(r#"<p><img src="file:///t/s.png" /></p>"#, &[img]);
        assert_eq!(
            h2,
            "<p>&nbsp;</p>\n<img src=\"https://us-api.asm.skype.com/v1/objects/0-wus-d8-6d53/views/imgo\" width=\"240\" height=\"180\" itemscope=\"image/png\" itemtype=\"http://schema.skype.com/AMSImage\" alt=\"Sticker image, OST TEST 56\" id=\"0-wus-d8-6d53\" itemid=\"0-wus-d8-6d53\">\n<p>&nbsp;</p>"
        );
        // Images the picker didn't put there are left out, as before.
        assert_eq!(
            teams_html_and_mentions(r#"<p>a<img src="x.png" /></p>"#).0,
            "<p>a</p>"
        );
    }
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
    let field = |name: &str, i: usize| -> u64 {
        conv.pointer(&format!("/properties/{name}"))
            .and_then(|h| h.as_str())
            .and_then(|h| h.split(';').nth(i))
            .and_then(|h| h.parse().ok())
            .unwrap_or(0)
    };
    let horizon = field("consumptionhorizon", 0);
    // Mark as unread writes a bookmark behind the horizon
    // ("{arrival-1};{when};{clientmessageid}"); it holds until the chat is
    // read again (a later horizon).
    let bookmark = field("consumptionHorizonBookmark", 0);
    let marked_unread = bookmark > 0
        && bookmark < last_id
        && field("consumptionHorizonBookmark", 1) > field("consumptionhorizon", 1);
    last_id > horizon || marked_unread
}

#[cfg(test)]
mod quote_tests {
    use super::*;

    #[test]
    fn editor_mentions_become_teams_mentions() {
        let qt = r#"<html><body><p>Hi <a href="mention:8:orgid:abc"><span style=" font-weight:600;">Randy Northrup</span></a>, see <a href="https://x.y">this</a></p></body></html>"#;
        let (html, m) = teams_html_and_mentions(qt);
        assert_eq!(
            html,
            r#"<p>Hi <span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="0">Randy Northrup</span>, see <a href="https://x.y" rel="noreferrer noopener" target="_blank" title="https://x.y">this</a></p>"#
        );
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].mri, "8:orgid:abc");
        assert_eq!(m[0].display_name, "Randy Northrup");
        let j = serde_json::to_value(&m).unwrap();
        let (_, e) = teams_html_and_mentions(
            r#"<p><a href="mention-everyone:19:x@thread.v2">Everyone</a></p>"#,
        );
        assert_eq!(
            (
                e[0].mri.as_str(),
                e[0].mention_type,
                e[0].display_name.as_str()
            ),
            ("19:x@thread.v2", "everyone", "Everyone")
        );
        assert_eq!(j[0]["@type"], "http://schema.skype.com/Mention");
        assert_eq!(j[0]["mentionType"], "person");
        // A channel and a team, as Teams sent them from OST Test Team's
        // General channel ("OST TEST 60").
        let team = "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2";
        let (html, m) = teams_html_and_mentions(&format!(
            r#"<p><a href="mention-channel:{team}">General</a>&nbsp;and <a href="mention-team:{team}">OST Test Team</a>&nbsp;OST TEST 60</p>"#
        ));
        assert_eq!(
            html,
            r#"<p><span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="0">General</span>&nbsp;and <span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="1">OST Test Team</span>&nbsp;OST TEST 60</p>"#
        );
        let j = serde_json::to_value(&m).unwrap();
        assert_eq!(
            j,
            serde_json::json!([
                {"@type": "http://schema.skype.com/Mention", "itemid": 0, "mri": team, "mentionType": "channel", "displayName": "General"},
                {"@type": "http://schema.skype.com/Mention", "itemid": 1, "mri": team, "mentionType": "team", "displayName": "OST Test Team"}
            ])
        );
    }

    #[test]
    fn tag_mentions_send_and_highlight_as_teams() {
        // As Teams posted "OST TEST 69 tag mention: @OST test tag check" in
        // OST Test Team's General channel.
        let (html, m) = teams_html_and_mentions(
            r#"<p>OST TEST 69 tag mention: <a href="mention-tag:tmu3aacUko">OST test tag</a>&nbsp;check</p>"#,
        );
        assert_eq!(
            html,
            r#"<p>OST TEST 69 tag mention: <readonly class="skipProofing" itemtype="http://schema.skype.com/Mention" spellcheck="false"><span itemtype="http://schema.skype.com/Mention" itemscope itemid="0">OST test tag</span></readonly>&nbsp;check</p>"#
        );
        assert_eq!(
            serde_json::to_value(&m).unwrap(),
            serde_json::json!([{"@type": "http://schema.skype.com/Mention", "itemid": 0, "mri": "tmu3aacUko", "mentionType": "tag", "displayName": "OST test tag"}])
        );
        // Received: a tag you are in mentions you; your own post stays
        // editable with the tag kept.
        let mentions = r#"[{"@type":"http://schema.skype.com/Mention","itemid":"0","mri":"tmu3aacUko","mentionType":"tag","displayName":"OST test tag"}]"#;
        let msg = |from: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": html, "from": format!("https://x/contacts/{from}"), "imdisplayname": "X", "properties": {"mentions": mentions}});
        let v = view_of(&msg("8:orgid:x"), "8:orgid:me", "Me").unwrap();
        assert!(v.html.contains("OST test tag") && !v.html.contains("readonly"));
        let tag = |mine| crate::api::teams::TeamTag { id: "tmu3aacUko".into(), name: "OST test tag".into(), count: 1, mine };
        crate::api::teams::note_tags_for_test(&[tag(true)]);
        let v = view_of(&msg("8:orgid:x"), "8:orgid:me", "Me").unwrap();
        assert!(v.mentions_me && v.mention_kind == "me" && v.html.contains("mention-me"));
        let own = view_of(&msg("8:orgid:me"), "8:orgid:me", "Me").unwrap();
        assert!(own.edit_html.contains(r#"href="mention-tag:tmu3aacUko""#), "{}", own.edit_html);
        crate::api::teams::note_tags_for_test(&[tag(false)]);
    }

    #[test]
    fn channel_and_team_mentions_highlight_posts() {
        let team = "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2";
        // As Teams posted "OST TEST 60" (a channel and a team mention).
        let mentions = serde_json::json!([
            {"@type": "http://schema.skype.com/Mention", "itemid": 0, "mri": team, "mentionType": "channel", "displayName": "General"},
            {"@type": "http://schema.skype.com/Mention", "itemid": 1, "mri": team, "mentionType": "team", "displayName": "OST Test Team"}
        ]).to_string();
        let m = |mentions: &str, from: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": "<p>x</p>", "from": format!("https://x/contacts/{from}"), "imdisplayname": "X", "properties": {"mentions": mentions}});
        let v = view_of(&m(&mentions, "8:orgid:me"), "8:orgid:me", "Me").unwrap();
        assert_eq!(v.mention_kind, "channel");
        let only_team =
            serde_json::json!([{"itemid": 0, "mri": team, "mentionType": "team"}]).to_string();
        assert_eq!(
            view_of(&m(&only_team, "8:orgid:x"), "8:orgid:me", "Me")
                .unwrap()
                .mention_kind,
            "team"
        );
        // You, before anything else; Everyone only from someone else.
        let me_and_channel = serde_json::json!([{"itemid": 0, "mri": team, "mentionType": "channel"}, {"itemid": 1, "mri": "8:orgid:me", "mentionType": "person"}]).to_string();
        assert_eq!(
            view_of(&m(&me_and_channel, "8:orgid:x"), "8:orgid:me", "Me")
                .unwrap()
                .mention_kind,
            "me"
        );
        let everyone =
            serde_json::json!([{"itemid": 0, "mri": "19:g@thread.v2", "mentionType": "everyone"}])
                .to_string();
        assert_eq!(
            view_of(&m(&everyone, "8:orgid:x"), "8:orgid:me", "Me")
                .unwrap()
                .mention_kind,
            "everyone"
        );
        assert_eq!(
            view_of(&m(&everyone, "8:orgid:me"), "8:orgid:me", "Me")
                .unwrap()
                .mention_kind,
            ""
        );
    }

    #[test]
    fn shared_contacts_read_and_send_as_teams_does() {
        let png = SHARE_CONTACT_IDCARD_PNG.trim();
        // As Teams sent "OST TEST 64" (Share someone's contact info).
        let wire = format!(
            "<p><span title=\"ID card\" type=\"(idcard)\" class=\"animated-emoticon-20-idcard\" itemscope=\"Share_Contact_Card\"><img itemscope=\"\" itemtype=\"http://schema.skype.com/Emoji\" itemid=\"idcard\" src=\"data:image/png;base64,{png}\" title=\"ID card\" alt=\"\u{1FAAA}\" style=\"width:20px; height:20px\"></span><span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"Share_Contact_Card\" itemid=\"0\">Randy Northrup</span>&nbsp; OST TEST 64 shared contact</p>"
        );
        let randy = "8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3";
        let mentions = serde_json::json!([{"@type": "http://schema.skype.com/Mention", "itemid": 0, "mri": randy, "mentionType": "share-contact", "displayName": "Randy Northrup"}]).to_string();
        let m = serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": wire, "from": "https://x/contacts/8:orgid:me", "imdisplayname": "Me", "properties": {"mentions": mentions}});
        // Read by Randy: the card icon and the name, not a mention of him.
        let v = view_of(&m, randy, "Randy Northrup").unwrap();
        assert!(
            v.html.starts_with(&format!(
                "<p><img src=\"{CONTACT_CARD_SRC}\" width=\"20\" height=\"20\""
            )),
            "{}",
            v.html
        );
        assert!(
            v.html
                .contains("<span class=\"mention\">Randy Northrup</span>"),
            "{}",
            v.html
        );
        assert!(!v.mentions_me && v.mention_kind.is_empty());
        assert!(emoticon_ids(&v.html).is_empty());
        // Sent from the compose box: byte for byte Teams' own.
        let (html, out) = teams_html_and_mentions(&format!(
            "<p><a href=\"mention-contact:{randy}\">Randy Northrup</a>&nbsp; OST TEST 64 shared contact</p>"
        ));
        assert_eq!(html, wire);
        assert_eq!(
            serde_json::to_string(&out).unwrap(),
            format!(
                "[{{\"@type\":\"http://schema.skype.com/Mention\",\"itemid\":0,\"mri\":\"{randy}\",\"mentionType\":\"share-contact\",\"displayName\":\"Randy Northrup\"}}]"
            )
        );
    }

    #[test]
    fn teams_formatting_reads_as_teams_shows_it() {
        let m = |c: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": c, "from": "https://x/contacts/8:orgid:them", "imdisplayname": "Them"});
        // As Teams sent "OST TEST 66": a quote, highlight, colour, size.
        let fmt = "<blockquote>\r\n<p><span style=\"background-color:#FDD472\">OST TEST 66 highlighted</span></p>\r\n</blockquote>\r\n<p><span style=\"background-color:#FDD472; color:#B6424C\">red text</span></p>\r\n<p><span style=\"background-color:inherit; color:inherit; font-size:x-large\">large text</span></p>\r\n<p>&nbsp;</p>";
        let v = view_of(&m(fmt), "8:orgid:me", "Me").unwrap();
        assert_eq!(v.html, "");
        assert_eq!(
            v.flow[0].quote.as_deref(),
            Some("<p><span style=\"background-color:#fdd472\">OST TEST 66 highlighted</span></p>")
        );
        assert_eq!(
            v.flow[1].html,
            "<p><span style=\"background-color:#fdd472; color:#b6424c\">red text</span></p>\r\n<p style=\"line-height:34px\"><span style=\"font-size:24px\">large text</span></p>\r\n<p>&nbsp;</p>"
        );
        // As Teams sent "OST TEST 68": text, then a code block.
        let code = "<p>OST TEST 68 code block:</p>\r\n<p></p>\r\n<p itemtype=\"http://schema.skype.com/CodeBlockEditor\" id=\"x_codeBlockEditor-1b8c\">\r\n&nbsp;</p>\r\n<pre class=\"language-plaintext\" itemid=\"codeBlockEditor-1b8c\"><code>let x = 1;\nlet y = x &lt; 2;</code></pre>";
        let v = view_of(&m(code), "8:orgid:me", "Me").unwrap();
        assert_eq!(v.html, "<p>OST TEST 68 code block:</p>");
        assert_eq!(
            v.flow,
            [FlowPart {
                code: Some(CodeBlock {
                    lang: "plaintext".into(),
                    name: "Plain Text".into(),
                    text: "let x = 1;\nlet y = x < 2;".into()
                }),
                ..Default::default()
            }]
        );
        // Unsafe styles go.
        assert_eq!(
            text_style("color:red; background-color:url(x); font-size:x-large"),
            Some("font-size:24px".into())
        );
        assert_eq!(text_style("background-color:inherit; color:inherit"), None);
    }

    #[test]
    fn card_messages_parse_as_teams_reads_them() {
        use base64::Engine;
        let swift = serde_json::json!({"type": "message/card", "attachments": [
            {"contentType": "application/vnd.microsoft.card.adaptive", "content": {"type": "AdaptiveCard", "version": "1.5", "body": [{"type": "TextBlock", "text": "Hi"}]}}
        ]});
        let b64 = base64::engine::general_purpose::STANDARD.encode(swift.to_string());
        let m = serde_json::json!({
            "id": "1", "messagetype": "RichText/Media_Card", "from": "https://x/contacts/28:bot",
            "content": format!("<URIObject type=\"SWIFT.1\"><Swift b64=\"{b64}\"/></URIObject>"),
        });
        let v = view_of(&m, "8:orgid:me", "Me").unwrap();
        assert_eq!(v.cards.len(), 1);
        assert_eq!(v.cards[0].content["body"][0]["text"], "Hi");
        assert_eq!(v.text, "Sent a card");
        let fallback = format!(
            "<URIObject type=\"SWIFT.1\">{}</URIObject>",
            escape(&swift.to_string())
        );
        assert!(swift_payload(&fallback).is_some());
        let enc = format!(
            "<uriobject type=\"SWIFT.1\">{}</uriobject>",
            swift
                .to_string()
                .replace('{', "%7B")
                .replace('}', "%7D")
                .replace('"', "%22")
        );
        assert!(swift_payload(&enc).is_some());
        let props = serde_json::json!({"cards": "[{\"cardClientId\":\"c1\",\"contentType\":\"application/vnd.microsoft.card.hero\",\"content\":{\"title\":\"T\"}}]"});
        let c = property_cards(Some(&props));
        assert_eq!(c[0].content["title"], "T");
    }

    #[test]
    fn follow_state_as_teams_derives_it() {
        let post = |id: &str, mine: bool, explicit: Option<bool>| MessageView {
            id: id.into(),
            root_id: id.into(),
            mine,
            follow_explicit: explicit,
            ..Default::default()
        };
        let mut t = vec![
            post("1", true, None),
            post("2", false, None),
            post("3", false, Some(true)),
            post("4", true, Some(false)),
            post("5", false, None),
            MessageView {
                id: "6".into(),
                root_id: "5".into(),
                mine: true,
                ..Default::default()
            },
        ];
        let mut rc = std::collections::HashMap::new();
        rc.insert("2".to_string(), 1);
        rc.insert("1".to_string(), 3);
        apply_following(&mut t, &rc);
        let f: Vec<bool> = t.iter().take(5).map(|m| m.following).collect();
        assert_eq!(f, vec![false, true, true, false, true]);
        let e = serde_json::json!([{"key": "follow", "users": [{"mri": "me", "value": "1"}]}, {"key": "like", "users": [{"mri": "a"}]}]);
        assert_eq!(follow_of(&e, "me"), Some(true));
        let r = reactions_of(&e, "me");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].key, "yes");
    }

    #[test]
    fn meet_now_events_pair_as_teams_shows_them() {
        let started = serde_json::json!({"id": "1", "messagetype": "Event/Call", "from": "https://x/contacts/8:orgid:me",
            "content": "<partlist type=\"started\" alt=\"\"><part identity=\"8:orgid:me\"><name>8:orgid:me</name></part></partlist><conversationType>\"huddleGroupCall\"</conversationType><callEventType>callStarted</callEventType><callId>c1</callId>"});
        let ended = serde_json::json!({"id": "2", "messagetype": "Event/Call", "from": "https://x/contacts/8:orgid:me",
            "content": "<ended/><partlist alt=\"\" count=\"1\"><part identity=\"8:orgid:me\"><duration>134</duration></part></partlist><callEventType>callEnded</callEventType><callId>c1</callId>"});
        let other = serde_json::json!({"id": "3", "messagetype": "Event/Call", "from": "https://x/contacts/8:orgid:me",
            "content": "<partlist alt=\"\"></partlist><callEventType>callStarted</callEventType><callId>c2</callId>"});
        let mut v: Vec<MessageView> = [started, ended, other]
            .iter()
            .filter_map(|m| view_of(m, "8:orgid:me", "Me"))
            .collect();
        sort_by_arrival(&mut v);
        assert_eq!(
            (
                v[0].call_state.as_str(),
                v[0].call_huddle,
                v[0].call_active,
                v[0].call_initiator.as_str()
            ),
            ("started", true, false, "")
        );
        assert_eq!(
            (
                v[1].call_state.as_str(),
                v[1].call_huddle,
                v[1].call_seconds
            ),
            ("ended", true, 134)
        );
        assert_eq!(
            (v[2].call_state.as_str(), v[2].call_huddle, v[2].call_active),
            ("started", false, true)
        );
    }

    #[test]
    fn edit_body_keeps_teams_properties() {
        let original = serde_json::json!({
            "id": "1794037612096", "conversationid": "19:x@thread.v2", "imdisplayname": "OST Test 1",
            "clientmessageid": "757156935902784764",
            "content": "<p>old</p>",
            "properties": {"importance": "high", "files": "[]", "mentions": "[]", "cards": "[]", "links": "[]",
                           "qtdMsgs": [{"messageId": 1}], "edittime": 1}
        });
        let q = Quote {
            message_id: "1794032815852".into(),
            sender_mri: "8:orgid:r".into(),
            sender_name: "R".into(),
            preview: "hi".into(),
        };
        let b = edit_body(&original, "<p>new <b>bold</b></p>", Some(&q), 42);
        assert_eq!(b["clientmessageid"], "757156935902784764");
        assert_eq!(b["properties"]["importance"], "high");
        assert_eq!(b["properties"]["edittime"], 42);
        assert!(
            b["content"]
                .as_str()
                .unwrap()
                .starts_with("<blockquote itemscope")
        );
        assert!(
            b["content"]
                .as_str()
                .unwrap()
                .ends_with("<p>new <b>bold</b></p>")
        );
        assert!(
            b["properties"]["qtdMsgs"]
                .as_str()
                .unwrap()
                .contains("1794032815852")
        );
        let b = edit_body(&original, "<p>new</p>", None, 42);
        assert!(b["properties"].get("qtdMsgs").is_none());
        assert_eq!(b["content"], "<p>new</p>");
    }

    #[test]
    fn reactions_group_skin_tones_and_order() {
        let e = serde_json::json!([
            {"key": "heart", "users": [{"mri": "a", "time": 1}]},
            {"key": "yes-tone2", "users": [{"mri": "me", "time": 5}]},
            {"key": "like", "users": [{"mri": "b", "time": 9}, {"mri": "c", "time": 3}]},
            {"key": "fire", "users": []}
        ]);
        let r = reactions_of(&e, "me");
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].key, "yes");
        assert_eq!(r[0].emoji, "👍");
        assert!(r[0].mine);
        assert_eq!(r[0].my_key, "yes-tone2");
        assert_eq!(r[0].count, 3);
        assert_eq!(r[0].variants, vec!["yes-tone2", "yes"]);
        assert_eq!(r[0].kinds, 2);
        let v = |l: &[&str]| l.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(
            shown_variants(
                &v(&["yes", "yes-tone1", "yes-tone3", "yes-tone4"]),
                "yes-tone4"
            ),
            v(&["yes-tone1", "yes-tone3", "yes-tone4"])
        );
        assert_eq!(
            shown_variants(&v(&["yes", "yes-tone1", "yes-tone3", "yes-tone4"]), "yes"),
            v(&["yes", "yes-tone1", "yes-tone3"])
        );
        let order: Vec<_> = r[0].users.iter().map(|u| u.mri.as_str()).collect();
        assert_eq!(order, vec!["b", "me", "c"]);
        assert_eq!(r[1].key, "heart");
        let e = serde_json::json!([
            {"key": "heart", "users": [{"mri": "me", "time": 9}]},
            {"key": "fire", "users": [{"mri": "me", "time": 2}]},
            {"key": "cry", "users": [{"mri": "a", "time": 1}, {"mri": "b", "time": 1}]}
        ]);
        let keys: Vec<_> = reactions_of(&e, "me").into_iter().map(|r| r.key).collect();
        assert_eq!(keys, vec!["fire", "heart", "cry"]);
        assert_eq!(common_key("like-tone5"), "like");
        assert_eq!(common_key("handsinair-tone"), "handsinair-tone");
    }

    #[test]
    fn quotes_round_trip_as_teams_writes_them() {
        let wire = "<blockquote itemscope itemtype=\"http://schema.skype.com/Reply\" itemid=\"1794032815852\"><strong itemprop=\"mri\" itemid=\"8:orgid:5050\">Randy Northrup</strong><span itemprop=\"time\" itemid=\"1794032815852\"></span><p itemprop=\"preview\">OST test 43: typing clears on send</p></blockquote>\n<p>OST test 47: quoted reply</p>";
        let (q, rest) = split_quote(wire);
        let q = q.unwrap();
        assert_eq!(q.message_id, "1794032815852");
        assert_eq!(q.sender_mri, "8:orgid:5050");
        assert_eq!(q.sender_name, "Randy Northrup");
        assert_eq!(q.preview, "OST test 43: typing clears on send");
        assert_eq!(rest, "<p>OST test 47: quoted reply</p>");
        // The client sends no newline after the card; the service adds one.
        assert_eq!(format!("{}\n{}", quote_html(&q), rest), wire);
        let qtd: serde_json::Value = serde_json::from_str(&quoted_messages_property(&q)).unwrap();
        assert_eq!(qtd[0]["time"], 1794032815852i64);
        assert_eq!(split_quote("<p>hi</p>").0, None);
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn conversation_facts_read_clear_time_and_layout() {
        let v = serde_json::json!({"properties": {"clearHistoryTime": "1794433826361"}, "threadProperties": {"chatModalityType": "Conversational"}});
        let f = super::ConversationFacts::from_reply(&v);
        assert_eq!(f.cleared_ms, Some(1794433826361));
        assert_eq!(f.modality.as_deref(), Some("Conversational"));
        assert_eq!(super::ConversationFacts::from_reply(&serde_json::json!({})), super::ConversationFacts::default());
    }

    #[test]
    fn editor_html_becomes_teams_html() {
        let qt = r#"<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN"><html><head><meta name="qrichtext" content="1" /><style type="text/css">p, li { white-space: pre-wrap; }</style></head><body style=" font-family:'Selawik'; font-size:14px;">
<p style=" margin-top:0px;">Hello <span style=" font-weight:700;">bold</span> and <span style=" font-style:italic; text-decoration: underline;">both</span> &lt;tag&gt;</p>
<ul style="margin-top: 0px;"><li style=" margin-top:0px;">one</li></ul>
<p><a href="https://example.com/x"><span style=" text-decoration: underline; color:#5b5fc7;">link</span></a> <a href="javascript:alert(1)">bad</a><script>evil()</script></p></body></html>"#;
        let h = super::teams_html_from_editor(qt);
        assert_eq!(
            h,
            "<p>Hello <b>bold</b> and <i><u>both</u></i> &lt;tag&gt;</p><ul><li>one</li></ul><p><a href=\"https://example.com/x\" rel=\"noreferrer noopener\" target=\"_blank\" title=\"https://example.com/x\"><u>link</u></a> <a>bad</a>evil()</p>"
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
    fn mark_as_unread_moves_the_read_position_back() {
        use super::read_position;
        assert_eq!(read_position(Some("200;1000;x"), None), Some(200));
        // Marked unread after the last read: the bookmark wins.
        assert_eq!(read_position(Some("200;1000;x"), Some("149;2000;y")), Some(149));
        // Read again since: the horizon wins.
        assert_eq!(read_position(Some("300;3000;x"), Some("149;2000;y")), Some(300));
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
            mentions_me: false,
            event: None,
            ..Default::default()
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
    fn seen_follows_teams_rule() {
        use super::{SeenRule, peer_horizon};
        // 1:1: the other member's horizon.
        let one = r#"{"consumptionhorizons":[
            {"id":"8:orgid:me","consumptionhorizon":"900;1;a"},
            {"id":"8:orgid:peer","consumptionhorizon":"500;1;b"}]}"#;
        assert_eq!(
            peer_horizon(one, "8:orgid:me"),
            Some(SeenRule {
                read_to: 500,
                visible_from: 0
            })
        );
        // Group: the lowest horizon among the others, the latest visibility.
        let group = r#"{"consumptionhorizons":[
            {"id":"8:orgid:me","consumptionhorizon":"900;1;a"},
            {"id":"8:orgid:b","consumptionhorizon":"800;1;b","messageVisibilityTime":100},
            {"id":"8:orgid:c","consumptionhorizon":"300;1;c","messageVisibilityTime":200}]}"#;
        assert_eq!(
            peer_horizon(group, "8:orgid:me"),
            Some(SeenRule {
                read_to: 300,
                visible_from: 200
            })
        );
        // Someone without a horizon yet: no receipts.
        let missing = r#"{"consumptionhorizons":[
            {"id":"8:orgid:me","consumptionhorizon":"900;1;a"},
            {"id":"8:orgid:b","consumptionhorizon":"800;1;b"},
            {"id":"8:orgid:c"}]}"#;
        assert_eq!(peer_horizon(missing, "8:orgid:me"), None);
        // Only me, or more than 20 members: no receipts.
        assert_eq!(
            peer_horizon(
                r#"{"consumptionhorizons":[{"id":"8:orgid:me","consumptionhorizon":"900;1;a"}]}"#,
                "8:orgid:me"
            ),
            None
        );
        let big: Vec<String> = (0..21)
            .map(|k| format!(r#"{{"id":"8:orgid:{k}","consumptionhorizon":"1;1;x"}}"#))
            .collect();
        assert_eq!(
            peer_horizon(
                &format!(r#"{{"consumptionhorizons":[{}]}}"#, big.join(",")),
                "8:orgid:0"
            ),
            None
        );
        assert_eq!(peer_horizon("nonsense", "8:orgid:me"), None);
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
    fn text_after_a_picture_stays_after_it_and_edits_keep_pictures() {
        // As OST's compose sends text, an emoticon, a GIF and more text.
        let c = r#"<p>Look <span title="Surprised" type="(surprised)" class="animated-emoticon-20-surprised" itemscope=""><img itemscope="" itemtype="http://schema.skype.com/Emoji" itemid="surprised" src="https://statics.teams.cdn.office.net/x/20_f.png" title="Surprised" alt="😮" style="width:20px; height:20px"></span></p><p>&nbsp;</p>
<img src="https://media1.giphy.com/media/abc/giphy.gif" width="444" height="250" alt="Cat Dance (GIF Image)" style="height:auto; margin-top:4px; max-width:100%">
<p>&nbsp;</p><p>after it</p>"#;
        let m = |c: &str, from: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": c, "from": format!("https://x/contacts/{from}"), "imdisplayname": "X"});
        let v = view_of(&m(c, "8:orgid:me"), "8:orgid:me", "Me").expect("shows");
        // Teams draws the blank paragraphs around the GIF as empty lines.
        assert!(
            v.html.contains("Look") && v.html.ends_with("<p>&nbsp;</p>"),
            "{}",
            v.html
        );
        assert_eq!(
            v.flow,
            [
                FlowPart {
                    pic: Some(0),
                    ..Default::default()
                },
                FlowPart {
                    html: "<p>&nbsp;</p><p>after it</p>".into(),
                    ..Default::default()
                }
            ]
        );
        assert_eq!(v.media.len(), 1);
        // Your own message: the edit box gets everything back, in place.
        assert_eq!(
            v.edit_html,
            "<p>Look <img src=\"ost-emoticon:surprised\" width=\"20\" height=\"20\" alt=\"😮\" title=\"Surprised\"></p><img src=\"https://media1.giphy.com/media/abc/giphy.gif\" width=\"444\" height=\"250\"><p>after it</p>"
        );
        let kinds: Vec<_> = v
            .edit_media
            .iter()
            .map(|m| (m.kind.as_str(), m.title.as_str()))
            .collect();
        assert_eq!(kinds, [("emoji", "Surprised"), ("gif", "Cat Dance")]);
        // Sent again, the GIF goes out as Teams' own (444 x 250, its title).
        let (html, _) = teams_html_with_media(&v.edit_html, &v.edit_media);
        assert!(html.contains("alt=\"Cat Dance (GIF Image)\""), "{html}");
        assert!(html.contains("itemid=\"surprised\""), "{html}");
        assert!(html.find("Look").unwrap() < html.find("giphy").unwrap());
        assert!(html.find("giphy").unwrap() < html.find("after it").unwrap());
        // A reply quotes it as Teams does, the GIF as a camera.
        assert_eq!(v.quote_text, "Look 😮 📷 after it");
        assert_eq!(v.mention_kind, "");
        // Mentions come back as the edit box's tokens, sent again as
        // Teams' mentions.
        let with_mention = r#"<p>Hi <span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="0">Randy</span>&nbsp;<span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="1">Northrup</span>&nbsp;and <span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="2">General</span></p>"#;
        let mentions = serde_json::json!([
            {"@type": "http://schema.skype.com/Mention", "itemid": 0, "mri": "8:orgid:r", "mentionType": "person", "displayName": "Randy"},
            {"@type": "http://schema.skype.com/Mention", "itemid": 1, "mri": "8:orgid:r", "mentionType": "person", "displayName": "Northrup"},
            {"@type": "http://schema.skype.com/Mention", "itemid": 2, "mri": "19:c@thread.tacv2", "mentionType": "channel", "displayName": "General"}
        ]).to_string();
        let mm = serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": with_mention, "from": "https://x/contacts/8:orgid:me", "imdisplayname": "Me", "properties": {"mentions": mentions}});
        let v2 = view_of(&mm, "8:orgid:me", "Me").unwrap();
        assert_eq!(
            v2.edit_html,
            r#"<p>Hi <a href="mention:8:orgid:r">Randy</a>&nbsp;<a href="mention:8:orgid:r">Northrup</a>&nbsp;and <a href="mention-channel:19:c@thread.tacv2">General</a></p>"#
        );
        let (again, out) = teams_html_and_mentions(&v2.edit_html);
        assert_eq!(again, with_mention);
        let got: Vec<_> = out
            .iter()
            .map(|m| {
                (
                    m.itemid,
                    m.mri.as_str(),
                    m.mention_type,
                    m.display_name.as_str(),
                )
            })
            .collect();
        assert_eq!(
            got,
            [
                (0, "8:orgid:r", "person", "Randy"),
                (1, "8:orgid:r", "person", "Northrup"),
                (2, "19:c@thread.tacv2", "channel", "General")
            ]
        );
        // Someone else's message has no edit form.
        let theirs = view_of(&m(c, "8:orgid:them"), "8:orgid:me", "Me").unwrap();
        assert!(theirs.edit_html.is_empty() && theirs.edit_media.is_empty());
        // A picture first and text after: nothing above it.
        let pic_first = r#"<p>&nbsp;</p><img src="https://media1.giphy.com/media/abc/giphy.gif" width="480" height="270" alt="Cat (GIF Image)"><p>&nbsp;</p><p>caption</p>"#;
        let v = view_of(&m(pic_first, "8:orgid:me"), "8:orgid:me", "Me").unwrap();
        assert_eq!(v.html, "");
        assert_eq!(v.flow[1].html, "<p>&nbsp;</p><p>caption</p>");
        // Text, then only a picture: nothing after.
        let text_first = r#"<p>hi</p><p>&nbsp;</p><img src="https://media1.giphy.com/media/abc/giphy.gif" width="480" height="270" alt="Cat (GIF Image)"><p>&nbsp;</p>"#;
        let v = view_of(&m(text_first, "8:orgid:me"), "8:orgid:me", "Me").unwrap();
        assert_eq!((v.html.as_str(), v.flow.len()), ("<p>hi</p>", 0));
        // A sticker, an emoticon line, then a GIF (as OST's fun picker test
        // sent them): each in its place.
        let mixed = r#"<p>&nbsp;</p><img src="https://us-api.asm.skype.com/v1/objects/0-wus-d1-abc/views/imgo" width="240" height="180" itemtype="http://schema.skype.com/AMSImage" alt="Sticker image, hi" itemid="0-wus-d1-abc"><p>&nbsp;</p><p>wow</p><p>&nbsp;</p><img src="https://media1.giphy.com/media/abc/giphy.gif" width="444" height="250" alt="Cat (GIF Image)"><p>&nbsp;</p>"#;
        let v = view_of(&m(mixed, "8:orgid:them"), "8:orgid:me", "Me").unwrap();
        let parts: Vec<_> = v.flow.iter().map(|p| (p.pic, p.html.as_str())).collect();
        assert_eq!(
            parts,
            [
                (Some(0), ""),
                (None, "<p>&nbsp;</p><p>wow</p><p>&nbsp;</p>"),
                (Some(1), "")
            ]
        );
        // An AMS picture keeps its object id for the edit box.
        let ams = r#"<p>&nbsp;</p><img src="https://us-api.asm.skype.com/v1/objects/0-wus-d1-abc/views/imgo" width="240" height="180" itemscope="image/png" itemtype="http://schema.skype.com/AMSImage" alt="Sticker image, hi" id="x_0-wus-d1-abc" itemid="0-wus-d1-abc"><p>&nbsp;</p>"#;
        let v = view_of(&m(ams, "8:orgid:me"), "8:orgid:me", "Me").unwrap();
        assert_eq!(
            v.edit_html,
            "<img src=\"ost-image:0-wus-d1-abc\" width=\"240\" height=\"180\">"
        );
        assert_eq!(
            (v.edit_media[0].kind.as_str(), v.edit_media[0].id.as_str()),
            ("image", "0-wus-d1-abc")
        );
    }

    #[test]
    fn gifs_and_stickers_are_media() {
        // As Teams sent them from its fun picker.
        let gif = r#"<p>&nbsp;</p>
<img src="https://media3.giphy.com/media/v1.Y2lk/YRPBhd3vscg5Fxx1DQ/giphy.gif" width="444" height="250" alt="Pedro Pascal Laughing GIF by Crafture (GIF Image)" style="height:auto; margin-top:4px; max-width:100%">
<p>&nbsp;</p>"#;
        let sticker = r#"<p>&nbsp;</p>
<img src="https://teams.public.onecdn.static.microsoft/evergreen-assets/stickerassets/clippy-250x250/en-us/Clippy_HelloThere.gif?v=5" height="180" alt="Clippy says &quot;Hello there&quot;" width="180" itemtype="http://schema.skype.com/Sticker">
<p>&nbsp;</p>"#;
        let m = |c: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": c, "from": "https://x/contacts/8:orgid:them", "imdisplayname": "Them"});
        let g = view_of(&m(gif), "8:orgid:me", "Me").expect("a GIF message shows");
        assert_eq!(
            (g.media.len(), g.media[0].kind.as_str(), g.media[0].width),
            (1, "gif", 444)
        );
        assert!(!g.html.contains("GIF Image"));
        let st = view_of(&m(sticker), "8:orgid:me", "Me").expect("a sticker message shows");
        assert_eq!(st.media[0].kind, "sticker");
        assert_eq!(st.media[0].alt, "Clippy says \"Hello there\"");
        // Other hosts aren't media (an untagged sticker host, a random site).
        assert!(
            message_media(r#"<img src="https://teams.public.onecdn.static.microsoft/x.gif">"#)
                .is_empty()
        );
        assert!(message_media(r#"<img src="https://evil.example/giphy.gif">"#).is_empty());
        // An emoticon on its own is a message (its character).
        let emoji = r#"<p><span title="Surprised" type="(surprised)" class="animated-emoticon-20-surprised" itemscope=""><img itemscope="" itemtype="http://schema.skype.com/Emoji" itemid="surprised" src="https://statics.teams.cdn.office.net/x/20_f.png" title="Surprised" alt="😮" style="width:20px; height:20px"></span></p>"#;
        assert_eq!(
            view_of(&m(emoji), "8:orgid:me", "Me")
                .expect("an emoticon shows")
                .text,
            "😮"
        );
        // Emoticons keep their place as pictures; one to three on their own
        // are big (50 px), as in Teams.
        let one = view_of(&m(emoji), "8:orgid:me", "Me").unwrap();
        assert_eq!(emoticon_ids(&one.html), ["surprised"]);
        assert!(
            one.html
                .contains(r#"<img src="ost-emoticon:surprised" width="50" height="50" alt="😮" title="Surprised">"#),
            "{}",
            one.html
        );
        let with_text = view_of(
            &m(&emoji.replace("<p><span", "<p>wow <span")),
            "8:orgid:me",
            "Me",
        )
        .unwrap();
        assert!(
            with_text.html.contains(r#"width="20" height="20""#) && with_text.text == "wow 😮",
            "{} / {}",
            with_text.html,
            with_text.text
        );
        let four = emoji.replace("</span></p>", "</span>").repeat(4) + "</p>";
        assert!(!big_emoticons(
            &view_of(&m(&four), "8:orgid:me", "Me").unwrap().html
        ));
        // A custom emoji keeps its place, its picture filled in later.
        let ce = r#"<p>hi <span contenteditable="false"><img alt="ost-test" itemid="ost-test;0-wus-d1-ab" itemtype="http://schema.skype.com/CustomEmoji" src="https://gw/v1/objects/0-wus-d1-ab/views/imgt2_anim" style="width:20px;height:20px;"></span></p>"#;
        let v = view_of(&m(ce), "8:orgid:me", "Me").unwrap();
        assert_eq!(custom_emoji_docs(&v.html), ["0-wus-d1-ab"]);
        assert_eq!(v.text, "hi :ost-test:");
        assert!(
            v.html.contains(
                r#"<img src="ost-custom-emoji:0-wus-d1-ab" width="20" height="20" alt="ost-test">"#
            ),
            "{}",
            v.html
        );
        // The empty paragraphs around a GIF show as nothing.
        assert!(
            !g.html.contains("<p>") || !g.html.contains("&nbsp;"),
            "{}",
            g.html
        );
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
    fn tables_go_out_as_teams_sends_them_and_show_as_teams_draws_them() {
        // OST's export of a 3x2 table ("OST TEST 111", as Teams sent it on
        // 2026-11-12 less its CRLFs).
        let qt = "<p>&nbsp;</p><table><tbody><tr><td><p>OST TEST 111</p></td><td><p>b</p></td></tr></tbody></table><p>&nbsp;</p>";
        let (html, _) = teams_html_and_mentions(qt);
        assert_eq!(html, qt);
        let shown = sanitize_html("<table>\r\n<tbody>\r\n<tr>\r\n<td>\r\n<p>1</p>\r\n</td>\r\n</tr>\r\n</tbody>\r\n</table>");
        assert!(shown.starts_with("<table border=\"0.67\" cellspacing=\"0\" cellpadding=\"0\" style=\"border-collapse:collapse;border-color:#D1D1D1;border-style:solid\">"), "{shown}");
        assert!(shown.contains("<td style=\"padding-left:5px;padding-right:5px;vertical-align:middle\">"), "{shown}");
        assert!(shown.contains("</td>") && shown.ends_with("</table>"), "{shown}");
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
    fn mentions_are_marked_and_yours_stand_out() {
        let m = serde_json::json!({
            "id": "9", "messagetype": "RichText/Html",
            "content": "<p>hi <span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"\" itemid=\"0\">Me</span> and <span itemtype=\"http://schema.skype.com/Mention\" itemid=\"1\">Bo</span> <span style=\"x\">plain</span></p>",
            "from": "https://x/v1/users/ME/contacts/8:orgid:them",
            "originalarrivaltime": "2026-11-05T18:58:00Z",
            "properties": { "mentions": "[{\"itemid\":0,\"mri\":\"8:orgid:ME\"},{\"itemid\":1,\"mri\":\"8:orgid:bo\"}]" }
        });
        let v = view_of(&m, "8:orgid:me", "Me").unwrap();
        assert!(v.mentions_me);
        assert_eq!(
            v.html,
            "<p>hi <span class=\"mention-me\">Me</span> and <span class=\"mention\">Bo</span> plain</p>"
        );
        // Unclosed mention spans are closed; stray closings are ignored.
        assert_eq!(
            sanitize_html("<span itemtype=\"http://schema.skype.com/Mention\">x</span></span>"),
            "<span class=\"mention\">x</span>"
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
                key: "yes".into(),
                emoji: "👍".into(),
                count: 2,
                mine: true,
                variants: vec!["yes".into()],
                kinds: 1,
                my_key: "yes".into(),
                users: vec![
                    Reactor {
                        mri: "8:orgid:them".into(),
                        key: "yes".into(),
                        ..Default::default()
                    },
                    Reactor {
                        mri: "8:orgid:me".into(),
                        key: "yes".into(),
                        me: true,
                        ..Default::default()
                    },
                ],
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

#[cfg(test)]
mod paging_and_event_tests {
    use super::*;

    #[test]
    fn system_events_read_as_teams_says_them() {
        let add = "<addmember><eventtime>1793904854879</eventtime><initiator>8:orgid:a</initiator><target>8:orgid:a</target><detailedtargetinfo><id>8:orgid:a</id></detailedtargetinfo><target>8:orgid:b</target><detailedtargetinfo><id>8:orgid:b</id><friendlyName>Bo</friendlyName></detailedtargetinfo></addmember>";
        let e = chat_event("ThreadActivity/AddMember", add).unwrap();
        assert_eq!(
            (e.kind.as_str(), e.targets.clone()),
            ("AddMember", vec!["8:orgid:b".to_string()])
        );
        assert_eq!(e.names.get("8:orgid:b").map(String::as_str), Some("Bo"));
        let names = |id: &str| match id {
            "8:orgid:a" => "Ann".to_string(),
            "8:orgid:b" => "Bo".to_string(),
            "8:orgid:c" => "Cy".to_string(),
            _ => "Di".to_string(),
        };
        assert_eq!(event_text(&e, &names, false), "Ann added Bo to the chat.");
        let many = ChatEvent {
            kind: "AddMember".into(),
            actor: "8:orgid:a".into(),
            targets: vec!["8:orgid:b".into(), "8:orgid:c".into(), "8:orgid:d".into()],
            history_days: Some(3),
            ..Default::default()
        };
        assert_eq!(
            event_text(&many, &names, false),
            "Ann added Bo and 2 others to the chat and shared chat history from the past 3 days."
        );
        let topic = chat_event(
            "ThreadActivity/TopicUpdate",
            "<topicupdate><eventtime>1</eventtime><initiator>8:orgid:a</initiator><value>OST group test</value></topicupdate>",
        )
        .unwrap();
        assert_eq!(
            event_text(&topic, &names, false),
            "Ann changed the group name to OST group test."
        );
        let left = ChatEvent {
            kind: "DeleteMember".into(),
            actor: "8:orgid:a".into(),
            targets: vec!["8:orgid:a".into()],
            ..Default::default()
        };
        assert_eq!(event_text(&left, &names, false), "Ann left the chat.");
        let joined = chat_event(
            "ThreadActivity/AddMember",
            "<addmember><initiator>8:orgid:a</initiator><target>8:orgid:a</target></addmember>",
        )
        .unwrap();
        assert_eq!(
            event_text(&joined, &names, false),
            "Ann joined the conversation."
        );
        assert!(chat_event("ThreadActivity/PinnedItemsUpdate", "<x/>").is_none());
        // OST layout test's conversion to threads (Teams, 2026-11-11).
        let layout = "<modalityupdate><eventtime>1</eventtime><initiator>8:orgid:a</initiator><value>Conversational</value></modalityupdate>";
        let e = chat_event("ThreadActivity/ModalityUpdate", layout).unwrap();
        assert_eq!(event_text(&e, &names, false), "The layout was changed to threads.");
        let back = layout.replace("Conversational", "PostReply");
        let e = chat_event("ThreadActivity/ModalityUpdate", &back).unwrap();
        assert_eq!(event_text(&e, &names, false), "The layout was changed to posts.");
        // Adding Polls to OST group test (OST, 2026-11-09): the bot's
        // AddMember is hidden; the app events read as Teams words them.
        let bot = "<addmember><eventtime>1794234644843</eventtime><initiator>8:orgid:a</initiator><target>28:fd931076-bbfb-4a38-a85c-1f0fb5b61bee</target><detailedtargetinfo><id>28:fd931076-bbfb-4a38-a85c-1f0fb5b61bee</id></detailedtargetinfo></addmember>";
        assert!(chat_event("ThreadActivity/AddMember", bot).is_none());
        let add = "<AddCustomApp><eventtime>1794234645103</eventtime><initiator>8:orgid:a</initiator><target>0e3bedea-4720-48b5-9e13-5a1ce1387d45</target><DeprecatedTargetName></DeprecatedTargetName><targetName>Polls</targetName><initiatorType>User</initiatorType></AddCustomApp>";
        let e = chat_event("ThreadActivity/AddCustomApp", add).unwrap();
        assert_eq!(event_text(&e, &names, false), "Ann added Polls here.");
        let del = add.replace("AddCustomApp", "DeleteCustomApp");
        let e = chat_event("ThreadActivity/DeleteCustomApp", &del).unwrap();
        assert_eq!(event_text(&e, &names, false), "Ann removed Polls from the chat.");
    }

    #[test]
    fn pages_back_as_teams_does() {
        let meta = serde_json::json!({"backwardLink": "https://emea.ng.msg.teams.microsoft.com/v1/users/ME/conversations/19%3Ax%40thread.v2/messages?startTime=1&syncState=abc%2B%3D&pageSize=200&view=msnp24Equivalent"});
        assert_eq!(backward_token(&meta).as_deref(), Some("abc+="));
        assert_eq!(backward_token(&serde_json::json!({})), None);
        assert_eq!(
            messages_url("https://cs", "19:x@thread.v2", 200, Some("abc+=")),
            "https://cs/v1/users/ME/conversations/19%3Ax%40thread.v2/messages?view=msnp24Equivalent|supportsMessageProperties&pageSize=200&syncState=abc%2B%3D&startTime=1"
        );
        assert!(
            !messages_url("https://cs", "19:c@thread.tacv2", 200, None)
                .contains("supportsMessageProperties")
        );
    }

    #[test]
    fn threads_layout_replies_also_sent_to_the_channel() {
        // As Teams sent "OST TEST 82" (Send to: thread and channel).
        let m = serde_json::json!({"id": "1794313462721", "messagetype": "RichText/Html", "content": "<p>OST TEST 82 thread and channel</p>", "from": "https://x/contacts/8:orgid:me", "imdisplayname": "Me", "rootMessageId": "1794312901896", "properties": {"isSharedInMain": true}});
        let v = view_of(&m, "8:orgid:me", "Me").unwrap();
        assert!(v.shared_in_main);
        assert_eq!(v.root_id, "1794312901896");
        let mut thread_only = m.clone();
        thread_only["properties"] = serde_json::json!({});
        assert!(!view_of(&thread_only, "8:orgid:me", "Me").unwrap().shared_in_main);
    }

    #[test]
    fn thread_read_state_from_rcmetadata() {
        // As the service returned it for "OST threads test" after Teams'
        // Mark as unread and OST reading the thread.
        let v = serde_json::json!({"rcMetadataList": [{"rcMetadata": {"ch": 1794315486744_i64, "chb": 1794313462719_i64, "chbv": 1794313949207_i64, "f": 2, "sl2": []}, "rootMessageId": 1794312901896_i64}]});
        let h = super::super::msgactions::horizons_from(&v);
        let t = h["1794312901896"];
        assert_eq!(t.unread_after(), 1794313462719, "the bookmark wins while set");
        let mut tl = vec![MessageView { id: "1794312901896".into(), ..Default::default() }];
        apply_thread_horizons(&mut tl, &h);
        assert_eq!((tl[0].thread_read_to, tl[0].thread_bookmark), (1794315486744, 1794313462719));
        let cleared = serde_json::json!({"rcMetadataList": [{"rcMetadata": {"ch": 7, "chb": 0}, "rootMessageId": 5}]});
        assert_eq!(super::super::msgactions::horizons_from(&cleared)["5"].unread_after(), 7);
        use super::super::msgactions::HorizonChange;
        assert_eq!(HorizonChange::UnreadFrom(1794313462720).body(), serde_json::json!({"chb": 1794313462719_i64}));
        assert_eq!(HorizonChange::ClearBookmark.body(), serde_json::json!({"chb": 0}));
        assert_eq!(HorizonChange::ReadTo(9).body(), serde_json::json!({"ch": 9}));
    }

    #[test]
    fn recordings_are_teams_control_rows() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-10T16:40:00Z").unwrap().with_timezone(&chrono::Utc);
        let rec = |status: &str, types: &str, extra: &str| format!(
            "<URIObject type=\"Video.2/CallRecording.1\"><RecordingStatus status=\"{status}\" code=\"0\"></RecordingStatus><RecordingContent contentTypes=\"{types}\" timestamp=\"2026-11-08T23:57:07.8493222Z\" duration=\"0:07:23.8\" canVideoExpire=\"True\"><item type=\"onedriveForBusinessVideo\" uri=\"https://x-my.sharepoint.com/rec.mp4\" /></RecordingContent><RecordingInitiatorId value=\"8:orgid:me\" isAutoRecording=\"False\" /><RecordingTerminatorId value=\"8:orgid:me\" /><RecordingStorage type=\"MeetingOrganizerOneDrive\" userId=\"me\" />{extra}</URIObject>");
        let names = |_: &str| "OST Test 1".to_string();
        let started = recording_event(&rec("Initial", "Recording", ""), now).unwrap();
        assert_eq!(event_text(&started, &names, true), "OST Test 1 started recording.");
        let stopped = recording_event(&rec("ChunkFinished", "Recording", ""), now).unwrap();
        assert_eq!(event_text(&stopped, &names, true), "OST Test 1 stopped recording.");
        // As Teams showed Sunday 4:07 PM's on Tuesday morning.
        let saved = recording_event(&rec("Success", "Recording+Transcript", ""), now).unwrap();
        assert_eq!(saved.actor, "8:orgid:me");
        assert_eq!(event_text(&saved, &names, true), "Recording has been saved to OST Test 1's OneDrive and will expire in 119 days.");
        assert_eq!(saved.link, "https://x-my.sharepoint.com/rec.mp4");
        // Legacy transcript messages: nothing in a meeting chat.
        let legacy = serde_json::json!({"id": "1", "messagetype": "RichText/Media_CallTranscript", "conversationid": "19:meeting_x@thread.v2",
            "content": "{\\\"scopeId\\\":\\\"f74ff03b\\\"}", "from": "https://x/contacts/8:orgid:me"});
        assert!(view_of(&legacy, "8:orgid:me", "Me").is_none());
        // Transcript-only messages show nothing.
        assert!(recording_event(&rec("Success", "Transcript", ""), now).is_none());
        assert!(recording_event(&rec("Initial", "Transcript", ""), now).is_none());
    }

    #[test]
    fn meeting_chat_members_from_json_events() {
        // As OST calendar test holds its guests leaving and joining.
        let left = chat_event("ThreadActivity/MemberLeft", r#"{"eventtime":1794200002535,"initiator":"8:orgid:me","members":[{"id":"8:teamsvisitor:dfeeb0b8","friendlyname":"OST Guest 1"}]}"#).unwrap();
        let names = |id: &str| if id == "8:teamsvisitor:dfeeb0b8" { "OST Guest 1".to_string() } else { "Unknown user".to_string() };
        assert_eq!(event_text(&left, &names, true), "OST Guest 1 left the chat.");
        assert_eq!(left.names.get("8:teamsvisitor:dfeeb0b8").map(String::as_str), Some("OST Guest 1"));
        let joined = chat_event("ThreadActivity/MemberJoined", r#"{"initiator":"8:orgid:me","members":[{"id":"8:teamsvisitor:dfeeb0b8","friendlyname":"OST Guest 1"}]}"#).unwrap();
        // A lobby chat's waiting person (as the lobby thread has it, 2026-11-11).
        let lobby = chat_event("ThreadActivity/MemberJoined", r#"{"eventtime":1794413917998,"initiator":"8:orgid:4287","members":[{"id":"8:teamsvisitor:e928","friendlyname":"Attendee","meetingMemberType":"temp"}]}"#).unwrap();
        assert_eq!(lobby.kind, "LobbyJoined");
        assert_eq!(event_text(&lobby, &|id| lobby.names.get(id).cloned().unwrap_or_default(), true), "Attendee is in the lobby.");
        assert_eq!(event_text(&joined, &names, true), "OST Guest 1 was invited to the meeting.");
    }
}

#[cfg(test)]
mod channel_meeting_tests {
    use super::channel_meeting;

    #[test]
    fn reads_a_channel_meetings_start() {
        let m = serde_json::json!({"properties": {"meeting": "{\"meetingtitle\":null,\"organizerId\":\"o\",\"meetingJoinUrl\":\"https://teams.microsoft.com/l/meetup-join/19%3ax%40thread.tacv2/179?context=x\"}"}});
        let content = "<partlist alt =\"\"></partlist><callEventType>callStarted</callEventType>\n<conversationStartTime>11/11/2026 06:38:08</conversationStartTime>\n<conversationUrl>https://api.example/conv/d?i=1&amp;e=2</conversationUrl>\n<callId>bc</callId>";
        let c = channel_meeting(&m, content);
        assert_eq!(c.join_url, "https://teams.microsoft.com/l/meetup-join/19%3ax%40thread.tacv2/179?context=x");
        assert_eq!(c.title, "");
        assert_eq!(c.started_at, "2026-11-11T06:38:08+00:00");
        assert_eq!(c.conversation_url, "https://api.example/conv/d?i=1&e=2");
        assert_eq!(c.linked_root, "");
        let linked = serde_json::json!({"properties": {"linkedRootMessageId": "1794373384701"}});
        assert_eq!(channel_meeting(&linked, "").linked_root, "1794373384701");
    }
}
