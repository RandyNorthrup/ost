//! Native Teams chat API (chatsvcagg / chat service)
//!
//! Uses the Skype token with `Authentication: skypetoken={token}` header,
//! bypassing Graph API which requires tenant admin consent for Chat.Read.

use anyhow::{Context, Result};
use serde::Deserialize;

use super::client::TeamsClient;

// -- Response types for the native chat API --

#[derive(Debug, Deserialize)]
struct ConversationsResponse {
    conversations: Option<Vec<Conversation>>,
}

#[derive(Debug, Deserialize)]
struct Conversation {
    id: Option<String>,
    #[serde(rename = "threadProperties")]
    thread_properties: Option<ThreadProperties>,
    #[serde(rename = "lastMessage")]
    last_message: Option<NativeMessage>,
    /// Your own properties for the chat (`alerts`, `consumptionhorizon`…).
    properties: Option<std::collections::HashMap<String, serde_json::Value>>,
}

/// Whether you muted the chat: its `alerts` property is "false".
fn is_muted(conv: &Conversation) -> bool {
    conv.properties
        .as_ref()
        .and_then(|p| p.get("alerts"))
        .and_then(|a| a.as_str())
        == Some("false")
}

#[derive(Debug, Deserialize)]
struct ThreadProperties {
    topic: Option<String>,
    /// Everything else, for the call liveness entries.
    #[serde(flatten)]
    extra: std::collections::HashMap<String, serde_json::Value>,
}

/// A meeting chat's meeting, from its thread's `meeting` property (a JSON
/// string): what the header's Join and Meeting details need.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct ThreadMeeting {
    pub subject: String,
    pub join_url: String,
    pub ical_uid: String,
    pub cancelled: bool,
    pub start: String,
    pub end: String,
    pub organizer_id: String,
}

/// The meeting in a thread's properties, if it has one with a join link.
pub fn thread_meeting(properties: &serde_json::Value) -> Option<ThreadMeeting> {
    let raw = properties.get("meeting")?;
    let m: serde_json::Value = match raw {
        serde_json::Value::String(s) => serde_json::from_str(s).ok()?,
        other => other.clone(),
    };
    let s = |k: &str| {
        m.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let meeting = ThreadMeeting {
        subject: s("subject"),
        join_url: s("meetingJoinUrl"),
        ical_uid: s("iCalUid"),
        cancelled: m
            .get("isCancelled")
            .and_then(|c| c.as_bool())
            .unwrap_or(false),
        start: s("startTime"),
        end: s("endTime"),
        organizer_id: s("organizerId"),
    };
    (!meeting.join_url.is_empty()).then_some(meeting)
}

/// A meeting chat's meeting (`GET /v1/threads/{id}`).
pub async fn chat_meeting(client: &TeamsClient, thread: &str) -> Result<Option<ThreadMeeting>> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        thread
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Thread reply")?;
    Ok(v.get("properties").and_then(thread_meeting))
}

/// The call going on in a chat, from its thread's liveness entry
/// (`GET /v1/threads/{id}`): Teams joins it by its id.
pub async fn thread_live_call(client: &TeamsClient, thread: &str) -> Result<Option<LiveCall>> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        thread
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Thread reply")?;
    let properties: std::collections::HashMap<String, serde_json::Value> = v
        .get("properties")
        .and_then(|p| serde_json::from_value(p.clone()).ok())
        .unwrap_or_default();
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    Ok(live_call(&properties, now_secs))
}

/// A call going on in a chat, from the thread's liveness entry
/// (`awareness_conversationLiveState:<message id>`, a JSON string), as
/// Teams shows it in the chat list and the chat header.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct LiveCall {
    /// The call's id (`conversationId`).
    pub call_id: String,
    pub conversation_url: String,
    /// `huddleGroupCall` for Meet now.
    pub conversation_type: String,
    pub initiator: String,
    pub initiator_name: String,
}

/// The call going on in a thread, if any: an `Active` liveness entry that
/// hasn't expired (`expiration` is in seconds) at `now_secs`.
pub fn live_call(
    properties: &std::collections::HashMap<String, serde_json::Value>,
    now_secs: u64,
) -> Option<LiveCall> {
    properties
        .iter()
        .filter(|(k, _)| k.starts_with("awareness_conversationLiveState"))
        .filter_map(|(_, v)| serde_json::from_str::<serde_json::Value>(v.as_str()?).ok())
        .find(|v| {
            v.get("status").and_then(|s| s.as_str()) == Some("Active")
                && v.get("expiration")
                    .and_then(|e| e.as_u64())
                    .is_some_and(|e| e > now_secs)
        })
        .map(|v| {
            let s = |k: &str| {
                v.get(k)
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string()
            };
            LiveCall {
                call_id: s("conversationId"),
                conversation_url: s("conversationUrl"),
                conversation_type: s("conversationType"),
                initiator: s("groupCallInitiator"),
                initiator_name: s("groupCallInitiatorDisplayName"),
            }
        })
}

#[derive(Debug, Deserialize)]
struct NativeMessage {
    #[serde(rename = "composetime")]
    compose_time: Option<String>,
    #[serde(rename = "originalarrivaltime")]
    original_arrival_time: Option<String>,
    #[serde(rename = "imdisplayname")]
    im_display_name: Option<String>,
    content: Option<String>,
    messagetype: Option<String>,
    #[serde(default)]
    properties: Option<serde_json::Value>,
}

/// A chat's last message as the chat list previews it (Teams' messaging
/// 390776 `u`): system events and media get Teams' own words ("Bot
/// added", "Sent an image", …, flagged `true` so they show in italics);
/// anything else is its text.
pub fn list_preview(content: &str, messagetype: &str, properties: Option<&serde_json::Value>) -> (String, bool) {
    let own = |s: &str| (s.to_string(), true);
    let forwarded = content.is_empty()
        && properties.and_then(|p| p.get("forwardTemplateId")).is_some_and(|v| !v.is_null());
    match messagetype {
        "RichText/Media_Card" if content.is_empty() => return own("Sent a card"),
        "RichText/Media_Card" => return (strip_html(content), false),
        "RichText/Media_CallRecording" | "RichText/Media_CallLocalRecording" => {
            let recording = content.contains("<RecordingContent") && content.contains("contentTypes=\"Recording");
            if messagetype == "RichText/Media_CallRecording" && !recording {
                return (String::new(), true);
            }
            return if content.contains("status=\"Initial\"") {
                own("Recording has started")
            } else if content.contains("status=\"ChunkFinished\"") {
                own("Recording has stopped")
            } else if content.contains("status=\"Success\"") {
                own(if messagetype == "RichText/Media_CallRecording" { "Recording is ready" } else { "Recording has stopped" })
            } else {
                (String::new(), true)
            };
        }
        "ThreadActivity/AddMember" => {
            let initiator = between(content, "<initiator>", "</initiator>").unwrap_or_default();
            let targets: Vec<&str> = content
                .split("<target>")
                .skip(1)
                .filter_map(|t| t.split("</target>").next())
                .map(str::trim)
                .filter(|t| *t != initiator.trim())
                .collect();
            if !initiator.is_empty() && targets.is_empty() {
                return own("User joined");
            }
            return if targets.iter().any(|t| t.starts_with("28:")) { own("Bot added") } else { own("User added") };
        }
        "RichText/Media_CallTranscript" => return own("Transcript is available"),
        "RichText/Media_Collaborate" => return (String::new(), true),
        // A Loop component with no text.
        "RichText/Media_Embed" if content.is_empty() => return own("Loop component"),
        _ => {}
    }
    let trimmed = content.trim();
    if trimmed.starts_with("<img") && trimmed.ends_with('>') && trimmed.matches('<').count() == 1 {
        return own("Sent an image");
    }
    if content.contains("<video") && content.contains("</video>") {
        return own("🎥 Video");
    }
    if forwarded {
        return own("Forwarded a message");
    }
    (strip_html(content), false)
}

fn between<'a>(s: &'a str, a: &str, b: &str) -> Option<&'a str> {
    let i = s.find(a)? + a.len();
    let j = s[i..].find(b)? + i;
    Some(&s[i..j])
}

/// A meeting recording message (`RichText/Media_CallRecording`) in Teams'
/// words (docs/spec/message-types.md §17):
/// - the start and stop rows ("{name} started recording." / "Recording has
///   started", "Recording stopped. Saving recording…");
/// - the result card as "Recording · {title} · {duration} · organizer
///   {name}".
/// None for messages Teams doesn't show (no content type).
pub fn recording_summary(content: &str, organizer: Option<&str>) -> Option<String> {
    let attr = |tag: &str, name: &str| -> Option<String> {
        let start = content.find(&format!("<{tag}"))?;
        let rest = &content[start..];
        let end = rest.find('>')?;
        let head = &rest[..end];
        let key = format!("{name}=\"");
        let i = head.find(&key)? + key.len();
        let j = head[i..].find('"')? + i;
        Some(head[i..j].to_string())
    };
    let name_of = |mri: Option<String>| {
        mri.and_then(|m| super::messages::cached_name(&m)).filter(|n| !n.is_empty())
    };
    let status = attr("RecordingStatus", "status").unwrap_or_default();
    if status == "Initial" {
        let auto = attr("RecordingInitiatorId", "isAutoRecording").as_deref() == Some("True");
        return Some(if auto {
            "Recording started automatically per the organizer's setting.".to_string()
        } else {
            match name_of(attr("RecordingInitiatorId", "value")) {
                Some(n) => format!("{n} started recording."),
                None => "Recording has started".to_string(),
            }
        });
    }
    if status == "ChunkFinished" {
        return Some(match name_of(attr("RecordingTerminatorId", "value")) {
            Some(n) => format!("{n} stopped recording. Saving recording…"),
            None => "Recording stopped. Saving recording…".to_string(),
        });
    }
    let title = between(content, "<Title>", "</Title>").map(|t| strip_html(t).trim().to_string());
    let duration = attr("RecordingContent", "duration").map(|d| {
        // "hh:mm:ss[.fff]" as Teams' "#h #m #s" (zero parts left out).
        let parts: Vec<u64> = d.split(['.']).next().unwrap_or_default().split(':').filter_map(|p| p.parse().ok()).collect();
        let (h, m, s) = match parts.as_slice() { [h, m, s] => (*h, *m, *s), _ => (0, 0, 0) };
        [(h, "h"), (m, "m"), (s, "s")].iter().filter(|(v, _)| *v > 0).map(|(v, u)| format!("{v}{u}")).collect::<Vec<_>>().join(" ")
    }).filter(|d| !d.is_empty());
    let organizer = organizer
        .map(str::to_string)
        .or_else(|| name_of(attr("MeetingOrganizerId", "value")))
        .filter(|n| !n.is_empty())
        .map(|n| format!("organizer {n}"));
    let parts: Vec<String> = std::iter::once("Recording".to_string()).chain(title).chain(duration).chain(organizer).filter(|p| !p.is_empty()).collect();
    Some(parts.join(" · "))
}

/// A message as the TUI lists it: the desktop's reading of it, its sender
/// being the name it carries, else your own name (or "You") on yours, else
/// "Unknown"; None when there's nothing to show (deleted, or no text).
fn tui_message(view: super::messages::MessageView, own_name: Option<&str>) -> Option<MessageInfo> {
    let text = view.text.trim();
    if view.deleted || text.is_empty() {
        return None;
    }
    let sender = if !view.sender.trim().is_empty() {
        view.sender.clone()
    } else if view.mine {
        own_name.filter(|n| !n.is_empty()).unwrap_or("You").to_string()
    } else {
        "Unknown".to_string()
    };
    Some(MessageInfo {
        sender,
        timestamp: view.time.clone(),
        content: text.to_string(),
        subject: view.subject.trim().to_string(),
    })
}

/// Strip HTML tags from message content and decode the common entities.
/// `&amp;` is decoded last so `&amp;lt;` stays the text `&lt;`.
pub fn strip_html(html: &str) -> String {
    let mut result = String::with_capacity(html.len());
    let mut in_tag = false;
    for ch in html.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => result.push(ch),
            _ => {}
        }
    }
    result
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
}

/// Display name for a conversation.
fn conversation_name(conv: &Conversation) -> String {
    if let Some(ref props) = conv.thread_properties
        && let Some(ref topic) = props.topic
        && !topic.is_empty()
    {
        return topic.clone();
    }
    // Fall back to last message sender or the thread ID
    if let Some(ref msg) = conv.last_message
        && let Some(ref name) = msg.im_display_name
        && !name.is_empty()
    {
        return name.clone();
    }
    conv.id.as_deref().unwrap_or("[unknown]").to_string()
}

fn has_topic(conv: &Conversation) -> bool {
    conv.thread_properties
        .as_ref()
        .and_then(|p| p.topic.as_deref())
        .is_some_and(|t| !t.is_empty())
}

/// The other participant of a 1:1 chat, from its id
/// `19:<oid>_<oid>@unq.gbl.spaces`. None if the id is not that shape or
/// does not include `me`.
fn other_member_oid(chat_id: &str, me: &str) -> Option<String> {
    let inner = chat_id
        .strip_prefix("19:")?
        .strip_suffix("@unq.gbl.spaces")?;
    let (a, b) = inner.split_once('_')?;
    let valid = |s: &str| s.len() == 36 && s.chars().all(|c| c == '-' || c.is_ascii_hexdigit());
    if !valid(a) || !valid(b) {
        return None;
    }
    if a.eq_ignore_ascii_case(me) {
        Some(b.to_string())
    } else if b.eq_ignore_ascii_case(me) {
        Some(a.to_string())
    } else {
        None
    }
}

/// A user's display name from Graph (by object id or `8:orgid:` MRI).
pub async fn user_display_name(client: &TeamsClient, user: &str) -> Option<String> {
    let oid = user.trim_start_matches("8:orgid:");
    resolve_user_name(client, oid, &mut Default::default()).await
}

/// Look up a user's display name in Graph, once per oid per listing.
async fn resolve_user_name(
    client: &TeamsClient,
    oid: &str,
    cache: &mut std::collections::HashMap<String, Option<String>>,
) -> Option<String> {
    if let Some(hit) = cache.get(oid) {
        return hit.clone();
    }
    #[derive(Deserialize)]
    struct User {
        #[serde(rename = "displayName")]
        display_name: Option<String>,
    }
    let name = match client
        .graph_get(&format!("/users/{oid}?$select=displayName"))
        .await
    {
        Ok(resp) => resp.json::<User>().await.ok().and_then(|u| u.display_name),
        Err(e) => {
            tracing::debug!("Could not resolve user {oid}: {e:#}");
            None
        }
    };
    cache.insert(oid.to_string(), name.clone());
    name
}

/// List recent chats using the native Teams API (prints to stdout).
pub async fn list_chats(limit: usize) -> Result<()> {
    let client = TeamsClient::new().await?;
    let chats = list_chats_data(&client, limit).await?;

    println!("\nRecent Chats:");
    println!("{:-<60}", "");

    if chats.is_empty() {
        println!("  (no chats found)");
        return Ok(());
    }

    for chat in &chats {
        println!("{}", chat.name);
        println!("  ID: {}", chat.id);

        if let Some(ref time) = chat.last_message_time {
            println!("  Last: {}", time);
        }
        if let Some(ref preview) = chat.last_message_preview
            && !preview.trim().is_empty()
        {
            let sender = chat.last_message_sender.as_deref().unwrap_or("?");
            println!("  [{}]: {}", sender, preview.trim());
        }

        println!();
    }

    Ok(())
}

/// Read messages from a specific chat thread (prints to stdout).
pub async fn read_messages(chat_id: &str, limit: usize) -> Result<()> {
    let client = TeamsClient::new().await?;
    let msgs = read_messages_data(&client, chat_id, limit).await?;

    if msgs.is_empty() {
        println!("(no messages)");
        return Ok(());
    }

    for msg in &msgs {
        println!("[{}] {}: {}", msg.timestamp, msg.sender, msg.content);
    }

    Ok(())
}

/// Send a message to a chat thread using the native API.
pub async fn send_message(chat_id: &str, message: &str) -> Result<()> {
    let client = TeamsClient::new().await?;
    send_message_with_client(&client, chat_id, message).await?;
    println!("Message sent.");
    Ok(())
}

/// HTML-escape text for embedding in Teams RichText/Html messages.
pub(crate) fn html_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

/// A thread's members' MRIs (lowercase), from the chat service.
pub async fn thread_member_ids(client: &TeamsClient, thread: &str) -> Result<Vec<String>> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        thread
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await?;
    Ok(v.get("members")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter_map(|m| {
            m.get("id")
                .and_then(|i| i.as_str())
                .map(|i| i.to_ascii_lowercase())
        })
        .collect())
}

/// A chat member as Teams lists people (the mention picker, the roster).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct Member {
    pub mri: String,
    pub name: String,
    pub mail: String,
    /// Whether this is us.
    pub me: bool,
}

/// A chat's members with their names and e-mail addresses (Graph, for
/// `8:orgid:` users), us included and marked.
pub async fn chat_members(client: &TeamsClient, thread: &str) -> Result<Vec<Member>> {
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}").to_ascii_lowercase())
        .unwrap_or_default();
    let ids = thread_member_ids(client, thread).await?;
    let mut out = Vec::new();
    for mri in ids {
        let mut m = Member {
            me: mri == me,
            ..Default::default()
        };
        if let Some(oid) = mri.strip_prefix("8:orgid:")
            && uuid::Uuid::parse_str(oid).is_ok()
            && let Ok(resp) = client
                .graph_get(&format!(
                    "/users/{oid}?$select=displayName,mail,userPrincipalName"
                ))
                .await
            && let Ok(v) = resp.json::<serde_json::Value>().await
        {
            m.name = v["displayName"].as_str().unwrap_or_default().to_string();
            m.mail = v["mail"]
                .as_str()
                .or_else(|| v["userPrincipalName"].as_str())
                .unwrap_or_default()
                .to_string();
        }
        m.mri = mri;
        if !m.name.is_empty() || m.me {
            out.push(m);
        }
    }
    Ok(out)
}

/// Start a group chat with `members` (MRIs such as `8:orgid:<oid>`, you
/// included) and an optional name; returns the new chat's id. This is the
/// chat service call Teams makes when you send the first message of a new
/// group chat.
pub async fn create_group_chat(
    client: &TeamsClient,
    members: &[String],
    topic: &str,
) -> Result<String> {
    let body = group_chat_body(members, topic)?;
    let url = format!("{}/v1/threads", client.chat_service_url());
    let resp = client.chat_post(&url, &body).await?;
    let location = resp
        .headers()
        .get(reqwest::header::LOCATION)
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    let text = resp.text().await.unwrap_or_default();
    thread_id_from_reply(location.as_deref(), &text)
        .context("The chat service didn't say which chat it created")
}

/// Make sure the 1:1 chat with `other` (an `8:orgid:` MRI) exists, creating
/// it as Teams does (`createThread` with a fixed, unique roster) when it
/// doesn't; returns its id.
pub async fn ensure_one_on_one_chat(client: &TeamsClient, me: &str, other: &str) -> Result<String> {
    let oid = |m: &str| m.trim_start_matches("8:orgid:").to_string();
    let id = super::directory::one_on_one_chat_id(&oid(me), &oid(other));
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        id
    );
    match client.chat_get(&url).await {
        Ok(_) => return Ok(id),
        Err(e) if e.to_string().contains("HTTP 404") => {}
        Err(e) => return Err(e),
    }
    let body = serde_json::json!({
        "members": [
            { "id": me.to_ascii_lowercase(), "role": "Admin" },
            { "id": other.to_ascii_lowercase(), "role": "Admin" },
        ],
        "properties": {
            "threadType": "chat",
            "chatFilesIndexId": "2",
            "fixedRoster": "true",
            "uniquerosterthread": "true",
        },
    });
    let resp = client
        .chat_post(&format!("{}/v1/threads", client.chat_service_url()), &body)
        .await?;
    let location = resp
        .headers()
        .get(reqwest::header::LOCATION)
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    let text = resp.text().await.unwrap_or_default();
    Ok(thread_id_from_reply(location.as_deref(), &text).unwrap_or(id))
}

fn group_chat_body(members: &[String], topic: &str) -> Result<serde_json::Value> {
    let mut seen = std::collections::HashSet::new();
    let members: Vec<_> = members
        .iter()
        .map(|m| m.trim().to_ascii_lowercase())
        .filter(|m| m.starts_with("8:orgid:") && m.len() > 8 && seen.insert(m.clone()))
        .map(|m| serde_json::json!({ "id": m, "role": "Admin" }))
        .collect();
    if members.len() < 2 {
        anyhow::bail!("A group chat needs at least one other person");
    }
    let mut properties = serde_json::json!({
        "threadType": "chat",
        "fixedRoster": "false",
        "uniquerosterthread": "false",
    });
    if !topic.trim().is_empty() {
        properties["topic"] = serde_json::Value::String(topic.trim().to_string());
    }
    Ok(serde_json::json!({ "members": members, "properties": properties }))
}

/// The new thread's id, from the reply's Location header
/// (`…/v1/threads/19:…@thread.v2`) or its JSON body (`{"id": …}`).
fn thread_id_from_reply(location: Option<&str>, body: &str) -> Option<String> {
    let valid = |id: &str| id.starts_with("19:") && id.contains("@thread");
    if let Some(id) = location.and_then(|l| l.rsplit("/threads/").next()) {
        let id = id.split(['?', '/']).next().unwrap_or_default();
        if valid(id) {
            return Some(id.to_string());
        }
    }
    let v: serde_json::Value = serde_json::from_str(body).ok()?;
    let id = v.get("id")?.as_str()?;
    valid(id).then(|| id.to_string())
}

#[cfg(test)]
mod group_chat_tests {
    use super::*;

    #[test]
    fn group_chats_need_two_distinct_members() {
        let me = "8:orgid:aaaa".to_string();
        assert!(group_chat_body(&[me.clone(), me.clone()], "").is_err());
        let b = group_chat_body(
            &[me.clone(), "8:orgid:BBBB".into(), "bogus".into()],
            " Team ",
        )
        .unwrap();
        assert_eq!(b["members"].as_array().unwrap().len(), 2);
        assert_eq!(b["members"][1]["id"], "8:orgid:bbbb");
        assert_eq!(b["properties"]["topic"], "Team");
        assert_eq!(b["properties"]["threadType"], "chat");
    }

    #[test]
    fn hidden_chats_stay_hidden_until_something_newer() {
        assert!(hidden_until_newer(Some(1794226106734), Some(1794177028993)));
        assert!(!hidden_until_newer(Some(1794226106734), Some(1794226200000)));
        assert!(hidden_until_newer(Some(5), None));
        assert!(!hidden_until_newer(None, Some(1)));
        assert!(!hidden_until_newer(Some(0), Some(1)));
    }

    #[test]
    fn new_thread_ids_come_from_location_or_body() {
        assert_eq!(
            thread_id_from_reply(Some("https://x/v1/threads/19:abc@thread.v2"), "").as_deref(),
            Some("19:abc@thread.v2")
        );
        assert_eq!(
            thread_id_from_reply(None, r#"{"id":"19:def@thread.v2"}"#).as_deref(),
            Some("19:def@thread.v2")
        );
        assert_eq!(
            thread_id_from_reply(Some("https://x/v1/threads/evil"), "{}"),
            None
        );
    }
}

/// Send a message using an existing client (shared helper).
pub async fn send_message_with_client(
    client: &TeamsClient,
    chat_id: &str,
    message: &str,
) -> Result<()> {
    let base = client.chat_service_url();
    let url = format!("{}/v1/users/ME/conversations/{}/messages", base, chat_id);

    let escaped = html_escape(message);
    let mut body = serde_json::json!({
        "content": format!("<p>{}</p>", escaped),
        "messagetype": "RichText/Html",
        "contenttype": "text"
    });
    // Teams clients send the sender's display name with every message; the
    // service stores it as-is, and clients that do not look the sender up
    // themselves show a blank name without it.
    if let Some(name) = client.display_name() {
        body["imdisplayname"] = serde_json::Value::String(name);
    }

    tracing::debug!("Sending message to {}", url);
    client.chat_post(&url, &body).await?;
    Ok(())
}

/// Send a formatted message: `html` is what the compose editor produced
/// (converted to Teams' safe HTML here).
pub async fn send_html_with_client(
    client: &TeamsClient,
    chat_id: &str,
    editor_html: &str,
) -> Result<()> {
    let html = super::messages::teams_html_from_editor(editor_html);
    if html.trim().is_empty() {
        return Ok(());
    }
    let base = client.chat_service_url();
    let url = format!("{}/v1/users/ME/conversations/{}/messages", base, chat_id);
    let mut body = serde_json::json!({
        "content": html,
        "messagetype": "RichText/Html",
        "contenttype": "text"
    });
    if let Some(name) = client.display_name() {
        body["imdisplayname"] = serde_json::Value::String(name);
    }
    client.chat_post(&url, &body).await?;
    Ok(())
}

/// Tell the chat's other members you are typing (Teams clients send this
/// every few seconds while the compose box changes).
pub async fn send_typing(client: &TeamsClient, chat_id: &str) -> Result<()> {
    let base = client.chat_service_url();
    let url = format!("{}/v1/users/ME/conversations/{}/messages", base, chat_id);
    let mut body = serde_json::json!({
        "content": "",
        "messagetype": "Control/Typing",
        "contenttype": "text",
    });
    if let Some(name) = client.display_name() {
        body["imdisplayname"] = serde_json::Value::String(name);
    }
    client.chat_post(&url, &body).await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Data-returning API functions for TUI integration
// ---------------------------------------------------------------------------

/// Chat metadata for TUI display.
#[allow(dead_code)]
#[derive(Default)]
pub struct ChatInfo {
    pub id: String,
    pub name: String,
    pub is_group: bool,
    pub last_message_time: Option<String>,
    pub last_message_sender: Option<String>,
    pub last_message_preview: Option<String>,
    /// The preview is Teams' own words for a system event or media
    /// ("Bot added", "Sent an image"), shown in italics.
    pub last_message_system: bool,
    /// The call going on in this chat.
    pub live_call: Option<LiveCall>,
    /// You muted it.
    pub muted: bool,
    /// Nothing has been said in it yet (`isemptyconversation`); Teams
    /// doesn't list such chats.
    pub empty: bool,
    /// You hid it and nothing newer has been said (Teams' Hide sets
    /// `historyHiddenTime`; a newer message shows the chat again).
    pub hidden: bool,
    /// You created it (meeting chats: the creator can't leave).
    pub is_creator: bool,
}

/// Your notes-to-self chat's name, as Teams lists it: "{you} (You)".
pub fn notes_name(my_name: &str) -> String {
    format!("{my_name} (You)")
}

/// The chats as Teams lists them: your notes-to-self chat (48:notes) first
/// as "{you} (You)", then the rest. System streams (48:drafts, 48:threads,
/// call logs, notifications, mentions…) aren't chats, channels belong under
/// their team, and empty or hidden chats aren't listed.
pub fn listed_chats(chats: Vec<ChatInfo>, my_name: &str) -> Vec<ChatInfo> {
    let mut notes = None;
    let mut rest = Vec::new();
    for mut c in chats {
        if c.id == "48:notes" {
            c.name = notes_name(my_name);
            notes = Some(c);
        } else if !c.id.starts_with("48:")
            && !c.id.ends_with("@thread.tacv2")
            && !c.id.ends_with("@thread.skype")
            && !c.empty
            && !c.hidden
        {
            rest.push(c);
        }
    }
    notes.into_iter().chain(rest).collect()
}

/// Whether a chat you hid stays hidden: hidden at `hidden_ms` and its last
/// message (`last_ms`) isn't newer.
pub fn hidden_until_newer(hidden_ms: Option<i64>, last_ms: Option<i64>) -> bool {
    match hidden_ms {
        Some(h) if h > 0 => last_ms.is_none_or(|l| l <= h),
        _ => false,
    }
}

/// A single message for TUI display.
#[derive(Default)]
pub struct MessageInfo {
    pub sender: String,
    pub timestamp: String,
    pub content: String,
    /// A channel post's subject (Teams' "Add a subject"), or "".
    pub subject: String,
}

/// List recent chats and return structured data.
pub async fn list_chats_data(client: &TeamsClient, limit: usize) -> Result<Vec<ChatInfo>> {
    // Strategy 1: CSA AFD endpoint with Bearer auth
    let csa_url = format!(
        "https://teams.microsoft.com/api/csa/api/v1/teams/users/ME/conversations?view=mychats&pageSize={}",
        limit
    );
    tracing::debug!("Trying CSA endpoint: {}", csa_url);
    let resp = match client.csa_get(&csa_url).await {
        Ok(r) => r,
        Err(e) => {
            tracing::debug!("CSA endpoint failed: {:#}, trying chatsvcagg", e);
            // Strategy 2: chatsvcagg with skypetoken auth
            let base = client.chatsvcagg_url();
            let url = format!(
                "{}/api/v2/users/ME/conversations?view=mychats&pageSize={}",
                base, limit
            );
            tracing::debug!("Trying chatsvcagg: {}", url);
            match client.chat_get(&url).await {
                Ok(r) => r,
                Err(e2) => {
                    tracing::debug!("chatsvcagg failed: {:#}, trying chat service", e2);
                    // Strategy 3: chat service (amer.ng.msg) with skypetoken auth
                    let base = client.chat_service_url();
                    let url = format!(
                        "{}/v1/users/ME/conversations?view=mychats&pageSize={}",
                        base, limit
                    );
                    client.chat_get(&url).await?
                }
            }
        }
    };

    let body: ConversationsResponse = resp
        .json()
        .await
        .context("Failed to parse conversations response")?;

    let conversations = body.conversations.unwrap_or_default();

    let own_oid = client.object_id();
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();
    let mut names: std::collections::HashMap<String, Option<String>> = Default::default();
    let mut chats = Vec::new();
    for conv in &conversations {
        let id = conv.id.as_deref().unwrap_or("").to_string();
        if id.is_empty() {
            continue;
        }

        let is_group = id.contains("thread") || id.contains("meeting");
        let mut name = conversation_name(conv);
        // A 1:1 chat has no topic, and its last sender may be the signed-in
        // user; name it after the other person instead.
        if !is_group
            && !has_topic(conv)
            && let Some(other) = own_oid.as_deref().and_then(|me| other_member_oid(&id, me))
            && let Some(display) = resolve_user_name(client, &other, &mut names).await
        {
            name = display;
        }

        let mut preview_system = false;
        let (last_time, last_sender, last_preview) = if let Some(ref msg) = conv.last_message {
            let time = msg
                .original_arrival_time
                .as_deref()
                .or(msg.compose_time.as_deref())
                .map(String::from);
            let sender = msg.im_display_name.clone();
            let (text, system) = list_preview(
                msg.content.as_deref().unwrap_or_default(),
                msg.messagetype.as_deref().unwrap_or_default(),
                msg.properties.as_ref(),
            );
            preview_system = system;
            let preview = Some(text).filter(|t| !t.is_empty() || system).map(|text| {
                if text.len() > 80 {
                    let end = text
                        .char_indices()
                        .map(|(i, _)| i)
                        .take_while(|&i| i <= 77)
                        .last()
                        .unwrap_or(0);
                    format!("{}...", &text[..end])
                } else {
                    text
                }
            });
            (time, sender, preview)
        } else {
            (None, None, None)
        };

        chats.push(ChatInfo {
            id,
            name,
            is_group,
            last_message_time: last_time,
            last_message_sender: last_sender,
            last_message_preview: last_preview,
            last_message_system: preview_system,
            live_call: conv
                .thread_properties
                .as_ref()
                .and_then(|p| live_call(&p.extra, now_secs)),
            muted: is_muted(conv),
            empty: conv
                .properties
                .as_ref()
                .and_then(|p| p.get("isemptyconversation"))
                .and_then(|e| e.as_str())
                .is_some_and(|e| e.eq_ignore_ascii_case("true")),
            hidden: hidden_until_newer(
                conv.properties
                    .as_ref()
                    .and_then(|p| p.get("historyHiddenTime"))
                    .and_then(|h| h.as_str().and_then(|s| s.parse().ok()).or_else(|| h.as_i64())),
                conv.last_message
                    .as_ref()
                    .and_then(|m| m.original_arrival_time.as_deref())
                    .and_then(|t| chrono::DateTime::parse_from_rfc3339(t).ok())
                    .map(|t| t.timestamp_millis()),
            ),
            is_creator: conv
                .thread_properties
                .as_ref()
                .and_then(|p| p.extra.get("isCreator"))
                .and_then(|c| c.as_bool())
                .unwrap_or(false),
        });
    }

    Ok(chats)
}

/// Read messages from a specific chat thread and return structured data.
pub async fn read_messages_data(
    client: &TeamsClient,
    chat_id: &str,
    limit: usize,
) -> Result<Vec<MessageInfo>> {
    // Teams' message pages (the desktop's messages_url), following each
    // page's backward link until there are `limit` messages to show (the
    // TUI asks for more as you scroll up) or the history ends; a newest
    // page can hold only events (archival, favourite updates).
    let base = client.chat_service_url();
    let mut raw: Vec<serde_json::Value> = Vec::new();
    let mut sync: Option<String> = None;
    for _ in 0..(5 + limit / 50) {
        let url = super::messages::messages_url(&base, chat_id, limit.min(200), sync.as_deref());
        tracing::debug!("Reading messages from {}", url);
        let page: serde_json::Value = client
            .chat_get(&url)
            .await?
            .json()
            .await
            .context("Failed to parse messages response")?;
        raw.extend(page["messages"].as_array().cloned().unwrap_or_default());
        let shown = raw
            .iter()
            .filter(|m| {
                m["messagetype"].as_str().is_some_and(|t| t.starts_with("Text") || t.starts_with("RichText"))
                    && !m["content"].as_str().unwrap_or_default().is_empty()
            })
            .count();
        sync = page.get("_metadata").and_then(super::messages::backward_token);
        if shown >= limit || sync.is_none() {
            break;
        }
    }
    let body = serde_json::json!({ "messages": raw });

    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    let own_name = client.display_name();
    let mut names: std::collections::HashMap<String, Option<String>> = Default::default();
    let mut result = Vec::new();
    // Messages come newest-first; show them oldest first.
    for m in body["messages"].as_array().into_iter().flatten().rev() {
        let Some(mut view) = super::messages::message_view(m, &me, own_name.as_deref().unwrap_or_default()) else {
            continue;
        };
        // A meeting recording: Teams' words for it, not its XML's text
        // (which ends in the card's "Play" link), with its organizer.
        let kind = m["messagetype"].as_str().unwrap_or_default();
        if kind.starts_with("RichText/Media_CallRecording") || kind == "RichText/Media_CallLocalRecording" {
            let content = m["content"].as_str().unwrap_or_default();
            let organizer = match between(content, "<MeetingOrganizerId value=\"8:orgid:", "\"") {
                Some(oid) => resolve_user_name(client, oid, &mut names).await,
                None => None,
            };
            let Some(text) = recording_summary(content, organizer.as_deref()) else { continue };
            view.text = text;
        }
        if let Some(info) = tui_message(view, own_name.as_deref()) {
            result.push(info);
        }
    }

    Ok(result)
}

#[cfg(test)]
mod chat_name_tests {
    use super::other_member_oid;

    const ME: &str = "4287e791-1b98-4963-8b94-281c50472683";
    const THEM: &str = "5050c9d6-b8a7-41f2-830a-0c51777b7dc3";

    #[test]
    fn finds_the_other_member_in_either_position() {
        let id = format!("19:{ME}_{THEM}@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME).as_deref(), Some(THEM));
        let id = format!("19:{THEM}_{ME}@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME).as_deref(), Some(THEM));
    }

    #[test]
    fn rejects_other_shapes() {
        assert_eq!(other_member_oid("19:abc@thread.v2", ME), None);
        let id = format!("19:{THEM}_{THEM}@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME), None);
        let id = format!("19:{ME}_../users@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME), None);
    }
}

#[cfg(test)]
mod tui_message_tests {
    use super::*;

    const ME: &str = "8:orgid:4287e791-1b98-4963-8b94-281c50472683";
    const OWN: &str = "https://amer.ng.msg.teams.microsoft.com/v1/users/ME/contacts/8:orgid:4287e791-1b98-4963-8b94-281c50472683";

    fn show(m: serde_json::Value) -> Option<MessageInfo> {
        tui_message(super::super::messages::message_view(&m, ME, "")?, Some("OST Test 1"))
    }

    #[test]
    fn senders_as_the_tui_shows_them() {
        let text = |name: &str, from: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": "<p>hi</p>", "imdisplayname": name, "from": from});
        assert_eq!(show(text("Randy Northrup", "https://x/contacts/8:orgid:aaaa")).unwrap().sender, "Randy Northrup");
        // A blank name on your own message shows your name…
        assert_eq!(show(text("", OWN)).unwrap().sender, "OST Test 1");
        // …and someone else's shows as Unknown.
        assert_eq!(show(text(" ", &OWN.replace("4287e791", "00000000"))).unwrap().sender, "Unknown");
    }

    #[test]
    fn recordings_read_as_teams_words_them() {
        // As the service sent OST calendar test's recording (trimmed).
        let done = r#"<URIObject type="Video.2/CallRecording.1"><RecordingStatus status="Success" code="200"></RecordingStatus><Title>OST calendar test created from OST</Title><a href="https://x">Play</a><RecordingContent duration="00:01:05.120" contentTypes="Recording"/><MeetingOrganizerId value="8:orgid:nobody" /></URIObject>"#;
        let s = recording_summary(done, None).unwrap();
        assert_eq!(s, "Recording · OST calendar test created from OST · 1m 5s");
        assert_eq!(recording_summary(done, Some("OST Test 1")).unwrap(), "Recording · OST calendar test created from OST · 1m 5s · organizer OST Test 1");
        assert!(!s.contains("Play"));
        assert_eq!(recording_summary(r#"<URIObject><RecordingStatus status="Initial" code="0"/></URIObject>"#, None).unwrap(), "Recording has started");
        assert_eq!(recording_summary(r#"<URIObject><RecordingStatus status="ChunkFinished" code="202"/></URIObject>"#, None).unwrap(), "Recording stopped. Saving recording…");
    }

    #[test]
    fn no_raw_json_or_card_buttons() {
        // A system event shows as Teams' sentence, not its JSON.
        let event = serde_json::json!({"id": "2", "messagetype": "ThreadActivity/AddMember",
            "content": "<addmember><eventtime>1</eventtime><initiator>8:orgid:a</initiator><target>8:orgid:b</target></addmember>",
            "from": "https://x/contacts/8:orgid:a"});
        if let Some(m) = show(event) {
            assert!(!m.content.starts_with('{') && !m.content.contains("<addmember>"), "{}", m.content);
        }
        // Deleted messages and empty ones aren't listed.
        assert!(show(serde_json::json!({"id": "3", "messagetype": "RichText/Html", "content": "", "from": OWN})).is_none());
    }
}

#[cfg(test)]
mod strip_html_tests {
    use super::strip_html;

    #[test]
    fn strips_tags_and_decodes_entities_once() {
        assert_eq!(strip_html("<p>Tom &amp; Jerry</p>"), "Tom & Jerry");
        assert_eq!(
            strip_html("<p>write &amp;lt;b&amp;gt;</p>"),
            "write &lt;b&gt;"
        );
        assert_eq!(strip_html("a&nbsp;&lt;b&gt;"), "a <b>");
    }
}

/// One entry of the Calls history (from the `48:calllogs` stream).
#[derive(Debug, Clone, serde::Serialize)]
pub struct CallRecord {
    pub call_id: String,
    /// "incoming" or "outgoing".
    pub direction: String,
    /// "accepted", "missed", "declined", … as the service reports it.
    pub state: String,
    pub start_time: String,
    pub connect_time: Option<String>,
    pub end_time: Option<String>,
    /// The other person.
    pub peer_name: String,
    pub peer_mri: String,
}

/// Recent calls, newest first.
pub async fn call_history(client: &TeamsClient, limit: usize) -> Result<Vec<CallRecord>> {
    let url = format!(
        "{}/v1/users/ME/conversations/48:calllogs/messages?pageSize={}&view=msnp24Equivalent",
        client.chat_service_url(),
        limit.min(200)
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Call history reply")?;
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    Ok(v.get("messages")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter_map(|m| parse_call_log(m.pointer("/properties/call-log")?.as_str()?, &me))
        .collect())
}

fn parse_call_log(json: &str, me: &str) -> Option<CallRecord> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).map(str::to_string);
    let direction = s("callDirection").unwrap_or_default();
    // The other side is the originator of incoming calls and the target of
    // outgoing ones; fall back to whichever is not us.
    let (peer_key, peer_part) = if direction == "incoming" {
        ("originator", "originatorParticipant")
    } else {
        ("target", "targetParticipant")
    };
    let mut peer_mri = s(peer_key).unwrap_or_default();
    let mut peer_name = v
        .pointer(&format!("/{peer_part}/displayName"))
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string();
    if peer_mri == me {
        let (k, p) = if peer_key == "originator" {
            ("target", "targetParticipant")
        } else {
            ("originator", "originatorParticipant")
        };
        peer_mri = s(k).unwrap_or_default();
        peer_name = v
            .pointer(&format!("/{p}/displayName"))
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string();
    }
    Some(CallRecord {
        call_id: s("callId").unwrap_or_default(),
        direction,
        state: s("callState").unwrap_or_default(),
        start_time: s("startTime")?,
        connect_time: s("connectTime"),
        end_time: s("endTime"),
        peer_name,
        peer_mri,
    })
}

#[cfg(test)]
mod call_log_tests {
    use super::parse_call_log;

    #[test]
    fn parses_incoming_and_outgoing_logs() {
        let inc = r#"{"startTime":"2026-11-05T05:59:53Z","connectTime":"2026-11-05T05:59:59Z","endTime":"2026-11-05T06:00:08Z",
            "callDirection":"incoming","callState":"accepted","originator":"8:orgid:them","target":"8:orgid:me",
            "originatorParticipant":{"displayName":"Randy Northrup"},"targetParticipant":{"displayName":null},"callId":"c1"}"#;
        let r = parse_call_log(inc, "8:orgid:me").unwrap();
        assert_eq!(r.peer_name, "Randy Northrup");
        assert_eq!(r.peer_mri, "8:orgid:them");
        assert_eq!(r.state, "accepted");
        assert_eq!(r.connect_time.as_deref(), Some("2026-11-05T05:59:59Z"));
        let out = inc
            .replace("\"incoming\"", "\"outgoing\"")
            .replace("\"missed\"", "x");
        let r = parse_call_log(&out, "8:orgid:me").unwrap();
        // Target is us here, so the peer falls back to the originator.
        assert_eq!(r.peer_mri, "8:orgid:them");
        assert!(parse_call_log("{}", "x").is_none());
    }
}

#[cfg(test)]
mod live_call_tests {
    use super::{live_call, thread_meeting};

    #[test]
    fn a_meeting_chats_meeting_is_read() {
        // As the OST calendar test meeting's thread has it.
        let meeting = r#"{"subject":"OST calendar test: created from OST","startTime":"2026-11-06T23:00:00Z","endTime":"2026-11-06T23:30:00Z","iCalUid":"0400","isCancelled":false,"organizerId":"4287","meetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/19%3ameeting_Y%40thread.v2/0?context=x"}"#;
        let m = thread_meeting(&serde_json::json!({ "meeting": meeting })).unwrap();
        assert_eq!(
            (m.subject.as_str(), m.ical_uid.as_str(), m.cancelled),
            ("OST calendar test: created from OST", "0400", false)
        );
        assert!(
            m.join_url
                .starts_with("https://teams.microsoft.com/l/meetup-join/")
        );
        // A group chat's Meet now "meeting" has a join link too; none at all: no meeting.
        assert!(thread_meeting(&serde_json::json!({ "topic": "x" })).is_none());
    }

    #[test]
    fn an_active_liveness_entry_is_a_call_going_on() {
        // As the group chat's thread had it during a Meet now call.
        let entry = r#"{"conversationUrl":"https://conv/x","conversationId":"f649","groupCallInitiator":"8:orgid:r","groupCallInitiatorDisplayName":"Randy Northrup","expiration":1794075286,"status":"Active","conversationType":"huddleGroupCall"}"#;
        let props: std::collections::HashMap<String, serde_json::Value> = [
            (
                "awareness_conversationLiveState:0".to_string(),
                serde_json::json!(entry),
            ),
            ("topic".to_string(), serde_json::json!("OST group test")),
        ]
        .into();
        let call = live_call(&props, 1_794_070_000).unwrap();
        assert_eq!(
            (
                call.call_id.as_str(),
                call.initiator_name.as_str(),
                call.conversation_type.as_str()
            ),
            ("f649", "Randy Northrup", "huddleGroupCall")
        );
        // Expired, or no longer active: no call.
        assert!(live_call(&props, 1_794_075_287).is_none());
        let ended: std::collections::HashMap<String, serde_json::Value> = [(
            "awareness_conversationLiveState:0".to_string(),
            serde_json::json!(entry.replace("Active", "Ended")),
        )]
        .into();
        assert!(live_call(&ended, 1_794_070_000).is_none());
    }
}

#[cfg(test)]
mod list_preview_tests {
    use super::{ChatInfo, list_preview, listed_chats};

    #[test]
    fn system_events_and_media_preview_as_teams() {
        // OST group test's last message: Polls added (a bot).
        let add_bot = "<addmember><eventtime>1</eventtime><initiator>8:orgid:a</initiator><target>28:d2d6f9b4</target></addmember>";
        assert_eq!(list_preview(add_bot, "ThreadActivity/AddMember", None), ("Bot added".into(), true));
        let add_user = "<addmember><initiator>8:orgid:a</initiator><target>8:orgid:b</target></addmember>";
        assert_eq!(list_preview(add_user, "ThreadActivity/AddMember", None).0, "User added");
        let joined = "<addmember><initiator>8:orgid:a</initiator><target>8:orgid:a</target></addmember>";
        assert_eq!(list_preview(joined, "ThreadActivity/AddMember", None).0, "User joined");
        assert_eq!(list_preview("<img src=\"x\">", "RichText/Html", None).0, "Sent an image");
        assert_eq!(list_preview("<p>Hi <b>there</b></p>", "RichText/Html", None), ("Hi there".into(), false));
        let fwd = serde_json::json!({ "forwardTemplateId": "1" });
        assert_eq!(list_preview("", "RichText/Html", Some(&fwd)).0, "Forwarded a message");
    }

    #[test]
    fn chats_are_listed_as_teams_lists_them() {
        let chat = |id: &str, name: &str| ChatInfo { id: id.into(), name: name.into(), ..Default::default() };
        let mut empty = chat("19:e@thread.v2", "19:e@thread.v2");
        empty.empty = true;
        let mut hidden = chat("19:h@thread.v2", "Hidden");
        hidden.hidden = true;
        let listed = listed_chats(
            vec![
                chat("48:drafts", "OST Test 1"),
                chat("19:g@thread.v2", "OST group test"),
                chat("48:threads", "48:threads"),
                chat("19:c@thread.tacv2", "OST test channel"),
                empty,
                hidden,
                chat("48:notes", "OST Test 1"),
                chat("48:calllogs", "48:calllogs"),
            ],
            "OST Test 1",
        );
        let names: Vec<&str> = listed.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, ["OST Test 1 (You)", "OST group test"]);
        assert_eq!(listed[0].id, "48:notes");
    }
}
