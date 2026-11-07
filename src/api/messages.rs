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
    /// Whether the message @mentions you (Teams marks it with an "@").
    #[serde(default)]
    pub mentions_me: bool,
    /// In a channel, the post this message belongs to: its own id for a
    /// post, the post's id for a reply. Empty in chats.
    #[serde(default)]
    pub root_id: String,
    /// For system events (kind "event"): what happened, as Teams' control
    /// message renderer reads it; `text` then holds Teams' sentence.
    #[serde(default)]
    pub event: Option<ChatEvent>,
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
    let ev = |kind: &str, targets: Vec<String>, value: String, history_days| ChatEvent {
        kind: kind.into(),
        actor: actor.clone(),
        targets,
        value,
        history_days,
        names: names.clone(),
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
        "PictureUpdate" => Some(ev("PictureUpdate", Vec::new(), String::new(), None)),
        "MemberJoined" | "MemberLeft" => {
            if targets.is_empty() && !actor.is_empty() {
                targets.push(actor.clone());
            }
            (!targets.is_empty()).then(|| ev(kind, targets, String::new(), None))
        }
        "MemberRenamed" => Some(ev("MemberRenamed", Vec::new(), first("value"), None)),
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
        "PictureUpdate" => format!("{actor} changed the group profile picture."),
        "MemberJoined" => {
            let verb = match (e.targets.len(), meeting) {
                (1, true) => "was invited to the meeting",
                (_, true) => "were invited to the meeting",
                _ => "joined the conversation",
            };
            format!("{} {verb}.", list(&e.targets))
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
        _ => String::new(),
    }
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

/// One page of a chat's history, oldest first, and the token for the
/// page before it (none at the start of the chat).
#[derive(Debug, Default)]
pub struct TimelinePage {
    pub messages: Vec<MessageView>,
    pub older: Option<String>,
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
    for id in wanted {
        person_name(client, &id).await;
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
        if let Some(e) = &m.event {
            m.text = event_text(e, &name, meeting);
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
        mentions_me: false,
        event: None,
    };
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
    // Which mention ids (`itemid`) are you, from properties.mentions.
    let my_mentions = my_mention_ids(props, me);
    Some(MessageView {
        images,
        files,
        mentions_me: !my_mentions.is_empty() && !deleted,
        html: if deleted {
            String::new()
        } else {
            sanitize_html_marking(&content, &my_mentions)
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
            !me.is_empty()
                && m.get("mri")
                    .and_then(|x| x.as_str())
                    .is_some_and(|x| x.eq_ignore_ascii_case(me))
        })
        .filter_map(|m| match m.get("itemid")? {
            serde_json::Value::Number(n) => Some(n.to_string()),
            serde_json::Value::String(s) => Some(s.clone()),
            _ => None,
        })
        .collect()
}

/// As `sanitize_html`, keeping Teams' mention spans as
/// `<span class="mention">`, or `class="mention-me"` for the `itemid`s in
/// `mine`, so the client can colour them as Teams does.
pub fn sanitize_html_marking(html: &str, mine: &[String]) -> String {
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
    // Open spans, and whether each is a mention (others are dropped).
    let mut spans: Vec<bool> = Vec::new();
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
                }
                spans.push(mention);
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
    for open in spans {
        if open {
            out.push_str("</span>");
        }
    }
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
pub fn apply_seen(timeline: &mut [MessageView], rule: Option<SeenRule>) {
    let Some(r) = rule else { return };
    for m in timeline.iter_mut().filter(|m| m.mine) {
        m.seen =
            m.id.parse::<u64>()
                .is_ok_and(|id| id <= r.read_to && id >= r.visible_from);
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
            mentions_me: false,
            event: None,
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
}
