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

/// Whether Teams' chat list leaves a chat out (checked against Teams'
/// list on winpc, 2026-11-15). Teams lists chats nothing has been said in
/// yet (group chats and meeting chats alike), but not:
/// - an empty one-on-one chat;
/// - a meeting's lobby chat (`threadSubType` LobbyChat);
/// - a breakout room's chat (a meeting thread with no `meetingChatPolicy`);
/// - a chat you aren't a member of any more (see `left`).
///
/// Your membership's `interest` doesn't count: someone added to a new chat
/// has none (OST Test 3 in "OST 0.2.0 release", 2026-11-23, even after
/// reading it), and Teams lists the chat for them.
fn unlisted(
    thread: &std::collections::HashMap<String, serde_json::Value>,
    empty: bool,
    one_on_one: bool,
) -> bool {
    let s = |k: &str| thread.get(k).and_then(|v| v.as_str()).unwrap_or_default();
    let meeting = s("threadType") == "meeting";
    (empty && one_on_one)
        || s("threadSubType") == "LobbyChat"
        || (meeting && !thread.contains_key("meetingChatPolicy"))
        || left(thread)
}

/// Whether a one-on-one chat is a bot's (see `ChatInfo::bot`).
fn bot_one_on_one(id: &str, conv: &Conversation) -> bool {
    let Some(pair) = id
        .strip_prefix("19:")
        .and_then(|s| s.strip_suffix("@unq.gbl.spaces"))
    else {
        return false;
    };
    let ends: Vec<String> = pair
        .split('_')
        .map(|g| format!("28:{}", g.to_ascii_lowercase()))
        .collect();
    let from = conv
        .last_message
        .as_ref()
        .and_then(|m| m.from.as_deref())
        .and_then(|f| f.rsplit('/').next())
        .unwrap_or_default()
        .to_ascii_lowercase();
    let added = conv
        .properties
        .as_ref()
        .and_then(|p| p.get("addedBy"))
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    ends.iter().any(|e| *e == from || *e == added)
}

/// Whether you left the chat (or were only let in for a while, as into a
/// meeting's lobby): Teams' isCurrentUserMember for a chat whose roster it
/// doesn't hold (worker 3398 `sn`): you last left it after you last
/// joined it.
fn left(thread: &std::collections::HashMap<String, serde_json::Value>) -> bool {
    let ms = |k: &str| {
        thread
            .get(k)
            .and_then(|v| {
                v.as_str()
                    .and_then(|s| s.trim().parse::<i64>().ok())
                    .or_else(|| v.as_i64())
            })
            .filter(|t| *t > 0)
    };
    match (ms("lastleaveat"), ms("lastjoinat")) {
        (Some(leave), Some(join)) => join < leave,
        (Some(_), None) => true,
        _ => false,
    }
}

/// Whether a chat is a request you haven't answered (Teams' chat request:
/// someone outside your org, a Teams free user for one, started it and you
/// haven't accepted or blocked it). Teams (shared worker `isInQuarantine`)
/// reads your membership's `relationshipState.inQuarantine` (an object, or
/// the same as a JSON string), else the conversation's `conversationstatus`
/// "AcceptPendingRecipient".
pub fn is_chat_request(conversation: &serde_json::Value) -> bool {
    let state = &conversation["memberProperties"]["relationshipState"];
    let parsed;
    let state = match state.as_str() {
        Some(s) => {
            parsed = serde_json::from_str::<serde_json::Value>(s).unwrap_or_default();
            &parsed
        }
        None => state,
    };
    let quarantined = &state["inQuarantine"];
    if !quarantined.is_null() {
        return quarantined.as_bool().unwrap_or(false)
            || quarantined
                .as_str()
                .is_some_and(|q| q.eq_ignore_ascii_case("true"));
    }
    conversation["properties"]["conversationstatus"].as_str() == Some("AcceptPendingRecipient")
}

/// Whether a chat thread is a one-on-one chat although its id is a
/// thread's (`19:uni01_…@thread.v2`, as every chat with a Teams free user
/// is): its `productThreadType` "OneToOneChat" (a chat they started), or,
/// as Teams' worker decides it, `uniquerosterthread` or `isStickyThread`
/// "true" (a chat a work user started with them is a sticky thread).
pub fn is_one_on_one_thread(thread: &std::collections::HashMap<String, serde_json::Value>) -> bool {
    let s = |k: &str| thread.get(k).and_then(|v| v.as_str()).unwrap_or_default();
    s("productThreadType").eq_ignore_ascii_case("OneToOneChat")
        || s("uniquerosterthread").eq_ignore_ascii_case("true")
        || s("isStickyThread").eq_ignore_ascii_case("true")
}

/// Whether a conversation is one of Teams free's system streams rather
/// than a chat: its call logs (`19:stream01_…@thread.v2`, threadType
/// "streamofcalllogs", streamType "calllogs"; Teams for personal use
/// doesn't list it, seen 2026-11-28).
pub fn is_system_stream(
    id: &str,
    thread: Option<&std::collections::HashMap<String, serde_json::Value>>,
) -> bool {
    let kind = thread
        .and_then(|t| t.get("threadType"))
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    kind.to_ascii_lowercase().starts_with("streamof") || id.starts_with("19:stream01_")
}

/// The one-on-one chats whose ids are a thread's (see
/// `is_one_on_one_thread`), as the chat list last named them.
static ONE_ON_ONE_THREADS: std::sync::RwLock<Option<std::collections::HashSet<String>>> =
    std::sync::RwLock::new(None);

/// Whether the chat list knows `chat_id` as a one-on-one chat with a
/// thread's id (a chat with someone on Teams free).
pub fn known_one_on_one_thread(chat_id: &str) -> bool {
    ONE_ON_ONE_THREADS
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .is_some_and(|s| s.contains(chat_id))
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
    /// `coOrganizerIds` (object ids).
    pub co_organizer_ids: Vec<String>,
    /// `meetingType`: Scheduled, Recurring, Broadcast, …
    pub meeting_type: String,
    /// `tenantId`: the meeting's tenant (Q&A and Whiteboard tabs).
    pub tenant_id: String,
    /// `networkId`: the Viva Engage network of the meeting's Q&A.
    pub network_id: String,
    /// `scenario` ("breakoutRoom" for a room's own chat).
    pub scenario: String,
    /// The `meeting` property's keys (what Teams' meetingInformation can
    /// read), for diagnostics.
    pub keys: Vec<String>,
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
        co_organizer_ids: m
            .get("coOrganizerIds")
            .and_then(|c| c.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default(),
        meeting_type: s("meetingType"),
        tenant_id: s("tenantId"),
        network_id: s("networkId"),
        scenario: s("scenario"),
        keys: m
            .as_object()
            .map(|o| o.keys().cloned().collect())
            .unwrap_or_default(),
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
    /// The meeting's `meetingData {meetingCode, passcode}`, while a
    /// meeting's call goes on (Teams' active calls keep it and send it
    /// when they join the call where it is).
    pub meeting_data: Option<serde_json::Value>,
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
                meeting_data: v
                    .get("meetingData")
                    .filter(|m| {
                        m.get("meetingCode")
                            .and_then(|c| c.as_str())
                            .is_some_and(|c| !c.is_empty())
                    })
                    .cloned(),
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
    /// Who sent it (`…/contacts/8:orgid:…` or `…/contacts/28:…`).
    #[serde(default)]
    from: Option<String>,
    #[serde(default)]
    properties: Option<serde_json::Value>,
}

/// A chat's last message as the chat list previews it (Teams' messaging
/// 390776 `u`): system events and media get Teams' own words ("Bot
/// added", "Sent an image", …, flagged `true` so they show in italics);
/// anything else is its text.
pub fn list_preview(
    content: &str,
    messagetype: &str,
    properties: Option<&serde_json::Value>,
) -> (String, bool) {
    use crate::i18n::tr_id;
    let own = |s: String| (s, true);
    let forwarded = content.is_empty()
        && properties
            .and_then(|p| p.get("forwardTemplateId"))
            .is_some_and(|v| !v.is_null());
    match messagetype {
        "RichText/Media_Card" if content.is_empty() => {
            return own(tr_id("Sent a card", "messaging:k8dmn31tp"));
        }
        "RichText/Media_Card" => return (strip_html(content), false),
        "RichText/Media_CallRecording" | "RichText/Media_CallLocalRecording" => {
            let recording = content.contains("<RecordingContent")
                && content.contains("contentTypes=\"Recording");
            if messagetype == "RichText/Media_CallRecording" && !recording {
                return (String::new(), true);
            }
            return if content.contains("status=\"Initial\"") {
                own(tr_id("Recording has started", "messaging:k7i54d3hc"))
            } else if content.contains("status=\"ChunkFinished\"") {
                own(tr_id("Recording has stopped", "messaging:k2z6nhw6a"))
            } else if content.contains("status=\"Success\"") {
                own(if messagetype == "RichText/Media_CallRecording" {
                    tr_id("Recording is ready", "messaging:k2v2b538c")
                } else {
                    tr_id("Recording has stopped", "messaging:k2z6nhw6a")
                })
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
                return own(tr_id("User joined", "messaging:k1rwm6emd"));
            }
            return if targets.iter().any(|t| t.starts_with("28:")) {
                own(tr_id("Bot added", "messaging:kklbpo3c"))
            } else {
                own(tr_id("User added", "messaging:k2vd59ni8"))
            };
        }
        "RichText/Media_CallTranscript" => {
            return own(tr_id("Transcript is available", "messaging:k7gd0qafj"));
        }
        "RichText/Media_Collaborate" => return (String::new(), true),
        // A Loop component with no text.
        "RichText/Media_Embed" if content.is_empty() => {
            return own(tr_id("Loop component", "messaging:kdnv8u7ph"));
        }
        _ => {}
    }
    let trimmed = content.trim();
    if trimmed.starts_with("<img") && trimmed.ends_with('>') && trimmed.matches('<').count() == 1 {
        return own(tr_id("Sent an image", "messaging:k8l5b8qq8"));
    }
    if content.contains("<video") && content.contains("</video>") {
        return own(tr_id("🎥 Video", "messaging:kmpyz4yc"));
    }
    if forwarded {
        return own(tr_id("Forwarded a message", "messaging:k9d6qptd8"));
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
///
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
        mri.and_then(|m| super::messages::cached_name(&m))
            .filter(|n| !n.is_empty())
    };
    use crate::i18n::{fill, tr_id};
    let status = attr("RecordingStatus", "status").unwrap_or_default();
    if status == "Initial" {
        let auto = attr("RecordingInitiatorId", "isAutoRecording").as_deref() == Some("True");
        return Some(if auto {
            tr_id(
                "Recording started automatically per the organizer's setting.",
                "messaging:k31yglod4",
            )
        } else {
            match name_of(attr("RecordingInitiatorId", "value")) {
                Some(n) => fill(
                    &tr_id("%1 started recording.", "messaging:k200fm25m"),
                    &[&n],
                ),
                None => tr_id("Recording has started", "messaging:k8xknh78u"),
            }
        });
    }
    if status == "ChunkFinished" {
        return Some(match name_of(attr("RecordingTerminatorId", "value")) {
            Some(n) => fill(
                &tr_id(
                    "%1 stopped recording. Saving recording…",
                    "messaging:kc7tejk6o",
                ),
                &[&n],
            ),
            None => tr_id(
                "Recording stopped. Saving recording…",
                "messaging:kdx0yyor8",
            ),
        });
    }
    let title = between(content, "<Title>", "</Title>").map(|t| strip_html(t).trim().to_string());
    let duration = attr("RecordingContent", "duration")
        .map(|d| {
            // "hh:mm:ss[.fff]" as Teams' "#h #m #s" (zero parts left out).
            let parts: Vec<u64> = d
                .split(['.'])
                .next()
                .unwrap_or_default()
                .split(':')
                .filter_map(|p| p.parse().ok())
                .collect();
            let (h, m, s) = match parts.as_slice() {
                [h, m, s] => (*h, *m, *s),
                _ => (0, 0, 0),
            };
            [(h, "h"), (m, "m"), (s, "s")]
                .iter()
                .filter(|(v, _)| *v > 0)
                .map(|(v, u)| format!("{v}{u}"))
                .collect::<Vec<_>>()
                .join(" ")
        })
        .filter(|d| !d.is_empty());
    let organizer = organizer
        .map(str::to_string)
        .or_else(|| name_of(attr("MeetingOrganizerId", "value")))
        .filter(|n| !n.is_empty())
        .map(|n| format!("organizer {n}"));
    let parts: Vec<String> = std::iter::once("Recording".to_string())
        .chain(title)
        .chain(duration)
        .chain(organizer)
        .filter(|p| !p.is_empty())
        .collect();
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
        own_name
            .filter(|n| !n.is_empty())
            .unwrap_or("You")
            .to_string()
    } else {
        "Unknown".to_string()
    };
    Some(MessageInfo {
        sender,
        timestamp: view.time.clone(),
        content: text.to_string(),
        subject: view.subject.trim().to_string(),
        // Only messages carry formatting; events and calls are their text.
        html: if view.kind == "message" {
            view.html.clone()
        } else {
            String::new()
        },
        flow: if view.kind == "message" {
            view.flow.clone()
        } else {
            Vec::new()
        },
        files: view.files.iter().map(|f| f.name.clone()).collect(),
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

/// Someone in a chat, as a group chat's generated name needs them (their
/// short profile).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ChatPerson {
    pub mri: String,
    pub display: String,
    pub given: String,
    pub surname: String,
}

/// The longest name list a generated chat name shows before "+N" (Teams'
/// 99234 `p`).
const TITLE_MAX: usize = 26;

/// Text length as JavaScript counts it (UTF-16 units), as Teams measures
/// its chat names.
fn js_len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// The name Teams gives a group chat that has none of its own (its chat
/// list and header; worker 98382 `O`/`q` and 99234 `JR`): the people sorted
/// by name, the first three others (not you) by their short names (given
/// names, see `directory::short_name`), as many as fit in 24 characters
/// joined by ", ", or, when they all fit, as a list in the app language
/// (`locale`, Teams' `Intl.ListFormat(locale)`: "A and B", "A, B, and C";
/// "A und B" in de-de) if that is at most 26 long, then ", +N" for the rest
/// (N counting one more than are left out; Teams' ", +" is not
/// translated). "Just me" when you're its
/// only member, "Unknown" when nobody's name is known.
/// `members` are the chat's member MRIs; `people` their known profiles.
pub fn generated_title(
    members: &[String],
    people: &[ChatPerson],
    me: &str,
    locale: &str,
) -> String {
    use crate::i18n::tr_id;
    let unknown = || tr_id("Unknown", "messaging:k7k6gmhup");
    if members.len() == 1 && members[0].eq_ignore_ascii_case(me) {
        return tr_id("Just me", "messaging:kaie41xa2");
    }
    // The profiles in name order (Teams' collator); with three or more, the
    // first three others who have a name, else everyone but you.
    let mut sorted: Vec<&ChatPerson> = people.iter().collect();
    sorted.sort_by(|a, b| {
        a.display
            .to_lowercase()
            .cmp(&b.display.to_lowercase())
            .then_with(|| a.display.cmp(&b.display))
    });
    let shown: Vec<&ChatPerson> = if sorted.len() <= 2 {
        sorted
            .into_iter()
            .filter(|p| !p.mri.eq_ignore_ascii_case(me))
            .collect()
    } else {
        sorted
            .into_iter()
            .filter(|p| !p.mri.eq_ignore_ascii_case(me) && !p.display.is_empty())
            .take(3)
            .collect()
    };
    if shown.is_empty() {
        return unknown();
    }
    let others = members
        .iter()
        .filter(|m| !m.eq_ignore_ascii_case(me))
        .count();
    let names: Vec<String> = shown
        .iter()
        .map(|p| {
            let n = super::directory::short_name(locale, &p.surname, &p.given, &p.display);
            if n.is_empty() { unknown() } else { n }
        })
        .collect();
    // As many names as fit (99234 `S`).
    let mut text = names[0].clone();
    let mut fit = 1;
    while fit < names.len() && js_len(&text) + js_len(&names[fit]) <= TITLE_MAX - 2 {
        text = format!("{text}, {}", names[fit]);
        fit += 1;
    }
    let mut more = (fit < others).then(|| others - fit + 1);
    // All of them: as a list when that fits (99234 `JR`).
    if more.is_none() && fit > 1 {
        let list = crate::i18n::list_and(&names[..fit], locale);
        if js_len(&list) <= TITLE_MAX {
            text = list;
        } else {
            text = names[..fit - 1].join(", ");
            more = Some(2);
        }
    }
    match more {
        Some(n) => format!("{text}, +{n}"),
        None => text,
    }
}

/// Group chats' members by chat (with the roster version they were read
/// at), and people's short profiles by MRI (with when they were read), for
/// the generated chat names.
type MemberCache = std::collections::HashMap<String, (String, Vec<String>)>;
type ProfileCache = std::collections::HashMap<String, (std::time::Instant, ChatPerson)>;
static TITLE_MEMBERS: std::sync::Mutex<Option<MemberCache>> = std::sync::Mutex::new(None);
static TITLE_PROFILES: std::sync::Mutex<Option<ProfileCache>> = std::sync::Mutex::new(None);
/// How long a short profile is used for names before it's read again.
const TITLE_PROFILE_TTL: std::time::Duration = std::time::Duration::from_secs(3600);

/// The generated names of the group chats `chats` (id, roster version)
/// that have none of their own. Chats whose members can't be read are left
/// out.
async fn generated_titles(
    client: &TeamsClient,
    chats: &[(String, String)],
    me: &str,
) -> std::collections::HashMap<String, String> {
    let mut members: std::collections::HashMap<String, Vec<String>> = Default::default();
    let mut need: Vec<(String, String)> = Vec::new();
    {
        let cache = TITLE_MEMBERS.lock().unwrap_or_else(|e| e.into_inner());
        for (id, roster) in chats {
            match cache
                .as_ref()
                .and_then(|c| c.get(id))
                .filter(|(r, _)| r == roster)
            {
                Some((_, m)) => {
                    members.insert(id.clone(), m.clone());
                }
                None => need.push((id.clone(), roster.clone())),
            }
        }
    }
    // A few at a time; the chat service throttles the burst of requests
    // at start (429), so those are asked again after a pause.
    for attempt in 0..3 {
        if need.is_empty() {
            break;
        }
        if attempt > 0 {
            tokio::time::sleep(std::time::Duration::from_secs(3 * attempt)).await;
        }
        let mut again = Vec::new();
        for chunk in need.chunks(4) {
            let read = futures::future::join_all(
                chunk.iter().map(|(id, _)| thread_member_ids(client, id)),
            )
            .await;
            let mut cache = TITLE_MEMBERS.lock().unwrap_or_else(|e| e.into_inner());
            let cache = cache.get_or_insert_with(Default::default);
            for ((id, roster), m) in chunk.iter().zip(read) {
                match m {
                    Ok(m) if !m.is_empty() => {
                        cache.insert(id.clone(), (roster.clone(), m.clone()));
                        members.insert(id.clone(), m);
                    }
                    Ok(_) => {}
                    Err(e) if e.to_string().contains("HTTP 429") => {
                        again.push((id.clone(), roster.clone()))
                    }
                    Err(e) => tracing::debug!("chat members for its name: {e:#}"),
                }
            }
        }
        need = again;
    }
    // Their short profiles (one request per 50 people not known lately).
    let mut wanted: Vec<String> = members
        .values()
        .flatten()
        .filter(|m| m.starts_with("8:"))
        .cloned()
        .collect();
    wanted.sort();
    wanted.dedup();
    let missing: Vec<String> = {
        let cache = TITLE_PROFILES.lock().unwrap_or_else(|e| e.into_inner());
        wanted
            .iter()
            .filter(|m| {
                cache
                    .as_ref()
                    .and_then(|c| c.get(*m))
                    .is_none_or(|(at, _)| at.elapsed() > TITLE_PROFILE_TTL)
            })
            .cloned()
            .collect()
    };
    for chunk in missing.chunks(50) {
        // (Once more after a moment: right after start the middle tier's
        // token can still be on its way.)
        let read = match super::directory::short_profile_records(client, chunk).await {
            Ok(r) => Ok(r),
            Err(_) => {
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                super::directory::short_profile_records(client, chunk).await
            }
        };
        match read {
            Ok(records) => {
                let mut cache = TITLE_PROFILES.lock().unwrap_or_else(|e| e.into_inner());
                let cache = cache.get_or_insert_with(Default::default);
                for r in records {
                    let s = |k: &str| {
                        r.get(k)
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string()
                    };
                    let mri = s("mri").to_ascii_lowercase();
                    if mri.is_empty() {
                        continue;
                    }
                    let person = ChatPerson {
                        mri: mri.clone(),
                        display: s("displayName"),
                        given: s("givenName"),
                        surname: s("surname"),
                    };
                    cache.insert(mri, (std::time::Instant::now(), person));
                }
            }
            Err(e) => tracing::debug!("short profiles for chat names: {e:#}"),
        }
    }
    let locale = crate::i18n::locale();
    let cache = TITLE_PROFILES.lock().unwrap_or_else(|e| e.into_inner());
    members
        .into_iter()
        .map(|(id, m)| {
            let people: Vec<ChatPerson> = m
                .iter()
                .filter_map(|mri| {
                    cache
                        .as_ref()
                        .and_then(|c| c.get(&mri.to_ascii_lowercase()))
                        .map(|(_, p)| p.clone())
                })
                .collect();
            let title = generated_title(&m, &people, me, &locale);
            (id, title)
        })
        .collect()
}

/// A consumption horizon's arrival time ("<arrival>;<client time>;<id>",
/// Teams' `OV`: 0 unless all three parts are there).
pub fn horizon_arrival(h: &str) -> i64 {
    let parts: Vec<&str> = h.split(';').collect();
    if parts.len() != 3 || parts.iter().any(|p| p.is_empty()) {
        return 0;
    }
    match (parts[0].parse::<i64>(), parts[1].parse::<f64>()) {
        (Ok(a), Ok(_)) => a,
        _ => 0,
    }
}

/// The full names of a chat's other members, as last read for its names.
fn title_member_names(members: &[String], me: &str) -> Vec<String> {
    let cache = TITLE_PROFILES.lock().unwrap_or_else(|e| e.into_inner());
    members
        .iter()
        .filter(|m| !m.eq_ignore_ascii_case(me))
        .filter_map(|m| {
            cache
                .as_ref()
                .and_then(|c| c.get(&m.to_ascii_lowercase()))
                .map(|(_, p)| p.display.clone())
        })
        .filter(|n| !n.is_empty())
        .collect()
}

/// A chat's members as they were last read for its generated name.
/// The last message's sender name (`imdisplayname`) when someone other
/// than `me` sent it (its `from` is a contact link ending in their MRI).
fn sender_name_unless(conv: &serde_json::Value, me: &str) -> Option<String> {
    let from = conv["lastMessage"]["from"].as_str()?.to_ascii_lowercase();
    (!me.is_empty() && !from.ends_with(&me.to_ascii_lowercase()))
        .then(|| conv["lastMessage"]["imdisplayname"].as_str())
        .flatten()
        .filter(|n| !n.trim().is_empty())
        .map(str::to_string)
}

/// The last message's sender name when `mri` sent it.
fn sender_name_if(conv: &serde_json::Value, mri: &str) -> Option<String> {
    let from = conv["lastMessage"]["from"].as_str()?.to_ascii_lowercase();
    from.ends_with(&mri.to_ascii_lowercase())
        .then(|| conv["lastMessage"]["imdisplayname"].as_str())
        .flatten()
        .filter(|n| !n.trim().is_empty())
        .map(str::to_string)
}

/// A person's name from the chat names' profiles, if read lately.
fn known_person_name(mri: &str) -> Option<String> {
    TITLE_PROFILES
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|c| c.get(&mri.to_ascii_lowercase()))
        .map(|(_, p)| p.display.clone())
        .filter(|n| !n.is_empty())
}

fn known_title_members(id: &str) -> Vec<String> {
    TITLE_MEMBERS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|c| c.get(id))
        .map(|(_, m)| m.clone())
        .unwrap_or_default()
}

/// The other participant of a 1:1 chat, from its id
/// `19:<oid>_<oid>@unq.gbl.spaces`. None if the id is not that shape or
/// does not include `me`.
pub(crate) fn other_member_oid(chat_id: &str, me: &str) -> Option<String> {
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
    let oid = crate::identity::work_object_id(user).unwrap_or(user);
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
    let ids: Vec<String> = v
        .get("members")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter_map(|m| {
            m.get("id")
                .and_then(|i| i.as_str())
                .map(|i| i.to_ascii_lowercase())
        })
        .collect();
    tracing::debug!(thread, members = ids.len(), "chat members read");
    remember_members(thread, ids.clone());
    // The thread's `cfet` (the chat list's conversations leave it out).
    let cfet = v.pointer("/properties/cfet").is_some_and(|c| {
        c.as_bool()
            .unwrap_or_else(|| c.as_str().is_some_and(|s| s.eq_ignore_ascii_case("true")))
    });
    let mut set = CFET_THREADS.lock().unwrap_or_else(|e| e.into_inner());
    let (set, read) = set.get_or_insert_with(Default::default);
    read.insert(thread.to_string());
    if cfet {
        set.insert(thread.to_string());
    } else {
        set.remove(thread);
    }
    Ok(ids)
}

/// Which of these group chats are external access threads (`cfet`), each
/// thread read once a session (four at a time); for the Store's quick
/// start, which offers no app there.
pub async fn cfet_threads(client: &TeamsClient, chats: &[String]) -> Vec<String> {
    let unread: Vec<&String> = {
        let state = CFET_THREADS.lock().unwrap_or_else(|e| e.into_inner());
        chats
            .iter()
            .filter(|c| c.starts_with("19:") && c.ends_with("@thread.v2"))
            .filter(|c| {
                !state
                    .as_ref()
                    .is_some_and(|(_, read)| read.contains(c.as_str()))
            })
            .collect()
    };
    for chunk in unread.chunks(4) {
        let read =
            futures::future::join_all(chunk.iter().map(|id| thread_member_ids(client, id))).await;
        for (id, r) in chunk.iter().zip(read) {
            if let Err(e) = r {
                tracing::debug!(chat = %id, "chat thread for cfet: {e:#}");
            }
        }
    }
    chats.iter().filter(|c| cfet_thread(c)).cloned().collect()
}

/// Threads whose `cfet` is "true", and every thread read, as
/// `thread_member_ids` read them.
type ThreadSets = (
    std::collections::HashSet<String>,
    std::collections::HashSet<String>,
);
static CFET_THREADS: std::sync::Mutex<Option<ThreadSets>> = std::sync::Mutex::new(None);

fn cfet_thread(thread: &str) -> bool {
    CFET_THREADS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .is_some_and(|(s, _)| s.contains(thread))
}

pub(crate) fn remember_members(thread: &str, ids: Vec<String>) {
    KNOWN_MEMBERS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(Default::default)
        .insert(thread.to_string(), ids);
}

/// Chats' member MRIs (lowercase) as last read, by chat: OST's copy of
/// each chat's roster, as Teams keeps the chat's `memberIds` in its store.
static KNOWN_MEMBERS: std::sync::Mutex<Option<std::collections::HashMap<String, Vec<String>>>> =
    std::sync::Mutex::new(None);

/// Chats' roster versions as the chat list last gave them.
static ROSTER_VERSIONS: std::sync::Mutex<Option<std::collections::HashMap<String, String>>> =
    std::sync::Mutex::new(None);

/// The chat list's roster versions (chat id, version): the members kept for
/// a chat whose roster changed since are dropped (Teams' store takes the
/// chat's new `memberIds` the same way), so its call reads them again.
pub(crate) fn note_roster_versions<'a>(chats: impl IntoIterator<Item = (&'a str, String)>) {
    let mut changed = Vec::new();
    {
        let mut versions = ROSTER_VERSIONS.lock().unwrap_or_else(|e| e.into_inner());
        let versions = versions.get_or_insert_with(Default::default);
        for (id, version) in chats {
            if versions
                .insert(id.to_string(), version.clone())
                .is_some_and(|old| old != version)
            {
                changed.push(id);
            }
        }
    }
    if changed.is_empty() {
        return;
    }
    if let Some(known) = KNOWN_MEMBERS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_mut()
    {
        for id in changed {
            known.remove(id);
        }
    }
}

/// A chat's members as last read (opening the chat, naming it, its call),
/// without asking the chat service.
pub fn known_member_ids(thread: &str) -> Option<Vec<String>> {
    KNOWN_MEMBERS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()?
        .get(thread)
        .cloned()
}

/// A chat member as Teams lists people (the mention picker, the roster).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct Member {
    pub mri: String,
    pub name: String,
    pub mail: String,
    /// Whether this is us.
    pub me: bool,
    /// Their address is one they don't let people find (a Teams free
    /// user's `emailsInfo` visibility "Private": Teams' request says "This
    /// person is not sharing their email in Teams.").
    #[serde(default)]
    pub mail_private: bool,
}

/// A chat's members with their names and e-mail addresses, us included and
/// marked. Names come as Teams gets them: one `fetchShortProfile` request
/// for the whole roster (guests too); anyone it leaves out is looked up in
/// Graph (`8:orgid:` users). Members with no name are left out.
pub async fn chat_members(client: &TeamsClient, thread: &str) -> Result<Vec<Member>> {
    let me = client
        .self_mri()
        .map(|m| m.to_ascii_lowercase())
        .unwrap_or_default();
    let ids = thread_member_ids(client, thread).await?;
    let records = super::directory::short_profile_records(client, &ids)
        .await
        .unwrap_or_else(|e| {
            tracing::warn!("short profiles unavailable: {e:#}");
            Vec::new()
        });
    // Teams free people's addresses: Teams' work client asks for the one
    // who started a chat with the chat (`invitersToThreads`), which is how
    // a request shows "{name} ({email}) wants to chat with you".
    let mut private: std::collections::HashSet<String> = Default::default();
    let mut inviter_mail: std::collections::HashMap<String, String> = Default::default();
    for r in &records {
        let mri = r["mri"].as_str().unwrap_or_default().to_ascii_lowercase();
        if !crate::identity::is_consumer_mri(&mri) {
            continue;
        }
        // (fetchTflProfiles is the work client's; a personal account's
        // short profiles carry the address already.)
        if client.is_personal() {
            if r["emailPrivate"].as_bool() == Some(true) {
                private.insert(mri.clone());
            }
            continue;
        }
        if r["email"].as_str().is_none_or(str::is_empty)
            && let Some(p) = super::directory::tfl_inviter(client, &mri, thread).await
        {
            if let Some(m) = p["email"].as_str().filter(|m| !m.is_empty()) {
                inviter_mail.insert(mri.clone(), m.to_string());
            }
            if p["emailPrivate"].as_bool() == Some(true) {
                private.insert(mri.clone());
            }
        } else if r["emailPrivate"].as_bool() == Some(true) {
            private.insert(mri.clone());
        }
    }
    let profiles: std::collections::HashMap<String, (String, String)> = records
        .iter()
        .filter_map(|p| {
            let mri = p["mri"].as_str()?.to_ascii_lowercase();
            let name = p["displayName"]
                .as_str()
                .filter(|n| !n.is_empty())?
                .to_string();
            let mail = p["email"]
                .as_str()
                .filter(|m| !m.is_empty())
                .or_else(|| p["userPrincipalName"].as_str())
                .unwrap_or_default()
                .to_string();
            Some((mri, (name, mail)))
        })
        .collect();
    let mut out = Vec::new();
    for mri in ids {
        let mut m = Member {
            me: mri == me,
            ..Default::default()
        };
        if let Some((name, mail)) = profiles.get(&mri) {
            m.name = name.clone();
            m.mail = inviter_mail
                .get(&mri)
                .cloned()
                .unwrap_or_else(|| mail.clone());
            m.mail_private = private.contains(&mri);
        } else if let Some(oid) = crate::identity::work_object_id(&mri)
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
    if client.is_personal() {
        let me = client.self_mri().unwrap_or_default();
        let others: Vec<String> = members
            .iter()
            .filter(|m| !m.trim().eq_ignore_ascii_case(&me))
            .cloned()
            .collect();
        return start_personal_chat(client, &others, topic, true).await;
    }
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
    // Teams free's 1:1 chats are sticky threads; asking for one again
    // hands back the one you have.
    if client.is_personal() {
        return start_personal_chat(client, &[other.to_string()], "", false).await;
    }
    // Work users by object ID; anyone else (a personal account, a bot)
    // by MRI, as the chat service names them.
    let id_of = |m: &str| crate::identity::work_object_id(m).unwrap_or(m).to_string();
    let id = super::directory::one_on_one_chat_id(&id_of(me), &id_of(other));
    ensure_unique_chat(client, &id, me, other, Some("2")).await
}

/// Make sure the 1:1 chat `id` between `me` and `other` (a person or a
/// bot, `28:…`) exists, creating it as Teams does when it doesn't.
/// Teams' test call creates its chat with the Echo bot this way (no
/// files index; measured on winpc 2026-11-16).
pub async fn ensure_unique_chat(
    client: &TeamsClient,
    id: &str,
    me: &str,
    other: &str,
    files_index: Option<&str>,
) -> Result<String> {
    let id = id.to_string();
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
    let mut body = serde_json::json!({
        "members": [
            { "id": me.to_ascii_lowercase(), "role": "Admin" },
            { "id": other.to_ascii_lowercase(), "role": "Admin" },
        ],
        "properties": {
            "threadType": "chat",
            "fixedRoster": "true",
            "uniquerosterthread": "true",
        },
    });
    if let Some(index) = files_index {
        body["properties"]["chatFilesIndexId"] = index.into();
    }
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

/// The body of a new 1:1 chat with someone on Teams free, as Teams' worker
/// makes it (`createThread` with one other member who is a consumer):
/// you and them, `fixedRoster` and `isStickyThread` (the chat service
/// refuses `uniquerosterthread` for them: "Consumer users disallowed on
/// uniquerosterthread"), and the chat's files index.
pub fn external_chat_body(me: &str, other: &str) -> serde_json::Value {
    serde_json::json!({
        "members": [
            { "id": me.to_ascii_lowercase(), "role": "Admin" },
            { "id": other, "role": "Admin" },
        ],
        "properties": {
            "threadType": "chat",
            "chatFilesIndexId": "2",
            "fixedRoster": "true",
            "isStickyThread": "true",
        },
    })
}

/// Start (or find again) the 1:1 chat with `other`, someone on Teams free
/// (`8:live:…`): the chat service makes it a thread (`19:uni01_…@thread.v2`)
/// rather than a `…@unq.gbl.spaces` id, and for a sticky thread hands back
/// the one you already have (live check 2026-11-27). Returns its id.
pub async fn start_external_chat(client: &TeamsClient, me: &str, other: &str) -> Result<String> {
    // A personal account starts every chat through Teams free's groups
    // service, with Teams free people and work users alike.
    if client.is_personal() {
        anyhow::ensure!(crate::identity::is_person_mri(other), "Not a person");
        return start_personal_chat(client, &[other.to_string()], "", false).await;
    }
    anyhow::ensure!(
        crate::identity::is_consumer_mri(other),
        "Not a Teams free user"
    );
    let resp = client
        .chat_post(
            &format!("{}/v1/threads", client.chat_service_url()),
            &external_chat_body(me, other),
        )
        .await?;
    let location = resp
        .headers()
        .get(reqwest::header::LOCATION)
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    let text = resp.text().await.unwrap_or_default();
    thread_id_from_reply(location.as_deref(), &text)
        .context("The chat service didn't say which chat it made")
}

/// Teams free's groups service token audience.
const PERSONAL_GROUPS_SCOPE: &str = "https://groupssvc.fl.teams.microsoft.com/teams.readwrite";

/// A new chat's body for Teams free's groups service, as its web client
/// sends it (captured 2026-11-28): you and the others; a 1:1 chat as
/// `"User"` members of a sticky thread, a group chat as `"Admin"` members
/// with its name, if any, as the topic (`group`: a group chat even with
/// one other person, as the group chat form makes it).
pub fn personal_chat_body(
    me: &str,
    others: &[String],
    topic: &str,
    group: bool,
) -> Result<serde_json::Value> {
    let mut seen = std::collections::HashSet::new();
    let members: Vec<String> = std::iter::once(me.to_string())
        .chain(others.iter().cloned())
        .map(|m| m.trim().to_string())
        .filter(|m| crate::identity::is_person_mri(m) && seen.insert(m.to_ascii_lowercase()))
        .collect();
    anyhow::ensure!(members.len() >= 2, "A chat needs someone else in it");
    let one_on_one = !group && members.len() == 2 && topic.trim().is_empty();
    let role = if one_on_one { "User" } else { "Admin" };
    let mut properties = serde_json::json!({ "threadType": "chat" });
    if one_on_one {
        properties["isStickyThread"] = "true".into();
    } else if !topic.trim().is_empty() {
        properties["topic"] = topic.trim().into();
    }
    Ok(serde_json::json!({
        "members": members.iter().map(|m| serde_json::json!({ "id": m, "role": role })).collect::<Vec<_>>(),
        "properties": properties,
    }))
}

/// Start a chat as Teams free's client does: `POST {groupsServiceV2}/v1/
/// threads` (teams.live.com/api/groups) with the groups service token and
/// the Skype token; its answer is `{"value": {"threadId": …, "membersStatus":
/// […]}}`. A 1:1 chat with someone you already have one with gives that
/// chat back. The person is then added to your contacts, as Teams does
/// (`{mt}/beta/contacts/buddylist/TflContacts/managebuddies`).
pub async fn start_personal_chat(
    client: &TeamsClient,
    others: &[String],
    topic: &str,
    group: bool,
) -> Result<String> {
    let me = client.self_mri().context("No signed-in user")?;
    let body = personal_chat_body(&me, others, topic, group)?;
    let base = client
        .region_endpoint("groupsServiceV2")
        .unwrap_or_else(|| "https://teams.live.com/api/groups".to_string());
    let url = format!("{base}/v1/threads");
    crate::auth::token_hosts::ensure(&url, crate::auth::token_hosts::Audience::Teams)?;
    let token = crate::auth::oauth::access_token_for(PERSONAL_GROUPS_SCOPE).await?;
    let req = client
        .http()
        .post(&url)
        .header("x-ms-client-type", "cdlworker");
    let v: serde_json::Value = client
        .middle_tier_auth(req, &token)
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("New chat")?
        .json()
        .await?;
    let id = v
        .pointer("/value/threadId")
        .and_then(|i| i.as_str())
        .filter(|i| i.starts_with("19:") && i.ends_with("@thread.v2"))
        .context("The groups service didn't say which chat it made")?
        .to_string();
    if let [other] = others
        && body["properties"]["isStickyThread"] == "true"
        && let Err(e) = add_contact(client, other).await
    {
        tracing::debug!("contact not added: {e:#}");
    }
    Ok(id)
}

/// Add someone to a personal account's contacts (Teams free's
/// managebuddies, as it does when you start a chat with them).
pub(crate) async fn add_contact(client: &TeamsClient, mri: &str) -> Result<()> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let name = super::directory::short_profile_records(client, &[mri.to_string()])
        .await
        .ok()
        .and_then(|r| {
            r.first()
                .and_then(|p| p["displayName"].as_str().map(str::to_string))
        })
        .unwrap_or_default();
    let req = client.http().post(format!(
        "{base}/beta/contacts/buddylist/TflContacts/managebuddies?migrationRequested=true&federatedContactsSupported=true&ggEnabled=true&skipBuddylistFetch=true"
    ));
    client
        .middle_tier_auth(req, &token)
        .json(&serde_json::json!({ "add": [{ "mri": mri, "displayName": name }] }))
        .send()
        .await?
        .error_for_status()
        .context("Contacts")?;
    Ok(())
}

fn group_chat_body(members: &[String], topic: &str) -> Result<serde_json::Value> {
    let mut seen = std::collections::HashSet::new();
    let members: Vec<_> = members
        .iter()
        .map(|m| m.trim().to_ascii_lowercase())
        .filter(|m| crate::identity::is_person_mri(m) && seen.insert(m.clone()))
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
    fn teams_free_call_logs_are_not_chats() {
        let calllogs: std::collections::HashMap<String, serde_json::Value> =
            serde_json::from_value(serde_json::json!({"threadType": "streamofcalllogs"})).unwrap();
        assert!(is_system_stream("19:x@thread.v2", Some(&calllogs)));
        assert!(is_system_stream("19:stream01_detyhk@thread.v2", None));
        let chat: std::collections::HashMap<String, serde_json::Value> =
            serde_json::from_value(serde_json::json!({"threadType": "chat"})).unwrap();
        assert!(!is_system_stream("19:uni01_abc@thread.v2", Some(&chat)));
    }

    #[test]
    fn group_chats_need_two_distinct_members() {
        let me = "8:orgid:aaaa".to_string();
        assert!(group_chat_body(&[me.clone(), me.clone()], "").is_err());
        let b = group_chat_body(
            &[
                me.clone(),
                "8:orgid:BBBB".into(),
                "bogus".into(),
                "8:live:.cid.c".into(),
                "28:bot".into(),
            ],
            " Team ",
        )
        .unwrap();
        // People of any kind of account; not bots or junk.
        assert_eq!(b["members"].as_array().unwrap().len(), 3);
        assert_eq!(b["members"][2]["id"], "8:live:.cid.c");
        assert_eq!(b["members"][1]["id"], "8:orgid:bbbb");
        assert_eq!(b["properties"]["topic"], "Team");
        assert_eq!(b["properties"]["threadType"], "chat");
    }

    #[test]
    fn chat_requests_and_teams_free_one_on_ones_are_recognised() {
        // ost-test1's request from OST Personal 2 and OST Test 2's
        // accepted chat with them (the chat service's list, 2026-11-27).
        let request = serde_json::json!({
            "id": "19:uni01_dsnpahgaglgokpbmo7a77ouadegypeikx3eqrrbiiz7pek6idxha@thread.v2",
            "memberProperties": {"isReader": false, "relationshipState": {"hasImpersonation": "null", "inQuarantine": true}, "role": "User"},
            "properties": {"addedBy": "8:live:.cid.ca2738c364862c6"},
            "threadProperties": {"productThreadType": "OneToOneChat", "threadType": "chat"}
        });
        assert!(is_chat_request(&request));
        let mut accepted = request.clone();
        accepted["memberProperties"]["relationshipState"]["inQuarantine"] = false.into();
        assert!(!is_chat_request(&accepted));
        // The same as a JSON string, and Teams' conversation status.
        let s = serde_json::json!({"memberProperties": {"relationshipState": "{\"inQuarantine\":true}"}});
        assert!(is_chat_request(&s));
        let pending =
            serde_json::json!({"properties": {"conversationstatus": "AcceptPendingRecipient"}});
        assert!(is_chat_request(&pending));
        assert!(!is_chat_request(
            &serde_json::json!({"id": "19:x@thread.v2"})
        ));
        let thread: std::collections::HashMap<String, serde_json::Value> =
            serde_json::from_value(request["threadProperties"].clone()).unwrap();
        assert!(is_one_on_one_thread(&thread));
        let group: std::collections::HashMap<String, serde_json::Value> =
            serde_json::from_value(serde_json::json!({"threadType": "chat"})).unwrap();
        assert!(!is_one_on_one_thread(&group));
        let sticky: std::collections::HashMap<String, serde_json::Value> = serde_json::from_value(
            serde_json::json!({"threadType": "chat", "isStickyThread": "true"}),
        )
        .unwrap();
        assert!(is_one_on_one_thread(&sticky));
    }

    #[test]
    fn a_request_is_named_after_its_sender() {
        // OST Personal 2's request from OST Personal 1 (2026-11-28).
        let c = serde_json::json!({"lastMessage": {"from": "https://msgapi.teams.live.com/v1/users/ME/contacts/8:live:.cid.77ac230600c33285", "imdisplayname": "OST Personal 1"}});
        assert_eq!(
            sender_name_unless(&c, "8:live:.cid.ca2738c364862c6").as_deref(),
            Some("OST Personal 1")
        );
        assert_eq!(sender_name_unless(&c, "8:live:.cid.77ac230600c33285"), None);
        assert_eq!(
            sender_name_if(&c, "8:live:.cid.77ac230600c33285").as_deref(),
            Some("OST Personal 1")
        );
        assert_eq!(sender_name_if(&c, "8:live:.cid.ca2738c364862c6"), None);
    }

    #[test]
    fn personal_chats_are_made_as_teams_free_makes_them() {
        let me = "8:live:.cid.77ac230600c33285";
        let p2 = "8:live:.cid.ca2738c364862c6".to_string();
        let t3 = "8:orgid:01c4860d-5776-4b16-8736-6a739fcc8b34".to_string();
        let one = personal_chat_body(me, std::slice::from_ref(&p2), "", false).unwrap();
        assert_eq!(
            one,
            serde_json::json!({"members":[{"id":me,"role":"User"},{"id":p2,"role":"User"}],"properties":{"threadType":"chat","isStickyThread":"true"}})
        );
        let group =
            personal_chat_body(me, &[p2.clone(), t3.clone(), p2.clone()], "", true).unwrap();
        assert_eq!(
            group,
            serde_json::json!({"members":[{"id":me,"role":"Admin"},{"id":p2,"role":"Admin"},{"id":t3,"role":"Admin"}],"properties":{"threadType":"chat"}})
        );
        let named = personal_chat_body(me, std::slice::from_ref(&p2), " Plans ", false).unwrap();
        assert_eq!(named["properties"]["topic"], "Plans");
        assert_eq!(named["members"][1]["role"], "Admin");
        assert!(personal_chat_body(me, &[me.to_string()], "", false).is_err());
    }

    #[test]
    fn teams_free_chats_are_made_as_sticky_threads() {
        let b = external_chat_body("8:orgid:ABC", "8:live:.cid.ca2738c364862c6");
        assert_eq!(b["members"][0]["id"], "8:orgid:abc");
        assert_eq!(b["members"][1]["id"], "8:live:.cid.ca2738c364862c6");
        assert_eq!(b["properties"]["isStickyThread"], "true");
        assert_eq!(b["properties"]["fixedRoster"], "true");
        assert!(b["properties"].get("uniquerosterthread").is_none());
    }

    #[test]
    fn hidden_chats_stay_hidden_until_something_newer() {
        assert!(hidden_until_newer(Some(1794226106734), Some(1794177028993)));
        assert!(!hidden_until_newer(
            Some(1794226106734),
            Some(1794226200000)
        ));
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

/// Teams' Block / Unblock bot conversation: the bot's 1:1 chat gets the
/// thread property `messagingdisabled` "true" / "false" (`PUT
/// /v1/threads/{id}/properties?name=messagingdisabled`).
pub async fn set_messaging_disabled(
    client: &TeamsClient,
    chat_id: &str,
    disabled: bool,
) -> Result<()> {
    anyhow::ensure!(
        chat_id.starts_with("19:") && chat_id.len() < 300,
        "Not a chat"
    );
    let url = format!(
        "{}/v1/threads/{}/properties?name=messagingdisabled",
        client.chat_service_url(),
        super::tabs::encode_uri_component(chat_id)
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "messagingdisabled": disabled.to_string() }),
        )
        .await
        .context("Block bot conversation")?;
    Ok(())
}

/// A bot's 1:1 chat with you and whether you blocked it: Teams keeps the
/// block on the thread (`messagingdisabled`), which the conversations list
/// leaves out, so the thread itself is read (`GET /v1/threads/{id}`).
pub async fn bot_chat(client: &TeamsClient, bot_id: &str) -> Option<(String, bool)> {
    let me = client.object_id()?.to_ascii_lowercase();
    let bot = bot_id.trim_start_matches("28:").to_ascii_lowercase();
    if bot.is_empty() || bot.len() > 64 {
        return None;
    }
    for id in [
        format!("19:{me}_{bot}@unq.gbl.spaces"),
        format!("19:{bot}_{me}@unq.gbl.spaces"),
    ] {
        let url = format!(
            "{}/v1/threads/{}?view=msnp24Equivalent",
            client.chat_service_url(),
            super::tabs::encode_uri_component(&id)
        );
        let Ok(r) = client.chat_get(&url).await else {
            continue;
        };
        let Ok(v) = r.json::<serde_json::Value>().await else {
            continue;
        };
        if v.get("id").is_none() {
            continue;
        }
        let blocked = v
            .pointer("/properties/messagingdisabled")
            .or_else(|| v.pointer("/threadProperties/messagingdisabled"))
            .and_then(|b| b.as_str())
            == Some("true");
        return Some((id, blocked));
    }
    None
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
    /// Nothing has been said in it yet (`isemptyconversation`).
    pub empty: bool,
    /// Teams' chat list leaves it out (an empty one-on-one, a lobby or
    /// breakout room chat, one you left; see `unlisted`).
    pub unlisted: bool,
    /// When it last saw activity, for Teams' Most recent order: its last
    /// message, or when you joined it (an empty chat), whichever is later
    /// (Unix milliseconds).
    pub activity_ms: i64,
    /// You hid it and nothing newer has been said (Teams' Hide sets
    /// `historyHiddenTime`; a newer message shows the chat again).
    pub hidden: bool,
    /// You created it (meeting chats: the creator can't leave).
    pub is_creator: bool,
    /// A meeting's group chat for its organizers and helpers (Teams'
    /// `meetingChatType` "Backroom"): "event" for a town hall's or a
    /// webinar's (Teams' "Event group"), "meeting" for a meeting's
    /// ("Planning group"), else "".
    pub backroom: String,
    /// A backroom chat's own title (its name without Teams' prefix).
    pub topic: String,
    /// A group chat with a name of its own (its thread's topic), not one
    /// named after its members.
    pub named: bool,
    /// Where you last read it (its consumption horizon's arrival time, ms;
    /// 0 never): Teams' go-to ranking weighs how recently you read a chat.
    pub horizon_ms: i64,
    /// When it was made (threadProperties.createdat, ms).
    pub created_ms: i64,
    /// A group chat's members as Teams names a chat after them (its
    /// chatTitle.shortTitle; go-to shows it under a named chat's topic),
    /// and their full names (go-to matches a chat's members too).
    pub member_title: String,
    pub member_names: Vec<String>,
    /// A group chat with nobody in it but you.
    pub alone: bool,
    /// You left it (Teams' go-to leaves those out but lists the meeting
    /// chats its chat list doesn't).
    pub left: bool,
    /// A bot's 1:1 chat you blocked (Teams' Block bot conversation sets
    /// the thread's `messagingdisabled` to "true").
    pub messaging_disabled: bool,
    /// A one-on-one chat with a bot (`19:{you}_{bot}@unq.gbl.spaces`, the
    /// bot showing as `28:{its id}` as the last message's sender or as who
    /// added you): Teams' chat list keeps it, its quick-start dialog doesn't
    /// (worker 3398 `LN`).
    pub bot: bool,
    /// The thread's `cfet` is "true" (a chat of external access, as one
    /// that once held someone on Teams free): Teams' quick-start dialog
    /// offers no app there (shared worker 40799 `we`, with
    /// enableExternalChatAppAccess).
    pub cfet: bool,
    /// Unread as Teams counts it: someone else's message newer than your
    /// read horizon, or marked unread (see `messages::is_unread`).
    pub unread: bool,
    /// A chat request you haven't answered (see `is_chat_request`): Teams
    /// shows "… wants to chat with you" with Block and Accept.
    pub request: bool,
    /// Who asked, for a request: the person who added you (`addedBy`),
    /// and their name as the chat names read it. Teams free's Requests
    /// list shows a request under that person's name, a group's too.
    pub inviter: Option<String>,
    pub inviter_name: Option<String>,
    /// A one-on-one chat's other person, when its id doesn't name them
    /// (a `19:uni01_…@thread.v2` chat with a Teams free user).
    pub peer: Option<String>,
    /// Someone in it uses Teams free (an `8:live:` member): Teams shows
    /// them as External and turns off calls and files in the chat.
    pub external: bool,
}

/// Teams' backroom chat kind from the thread's properties (its
/// `meetingChatType` and the meeting's template, the chat's `isTownhall`
/// / `isWebinar`).
pub fn backroom_kind(
    thread: &std::collections::HashMap<String, serde_json::Value>,
) -> &'static str {
    let backroom = thread
        .get("meetingChatType")
        .and_then(|v| v.as_str())
        .is_some_and(|t| t.eq_ignore_ascii_case("backroom"));
    if !backroom {
        return "";
    }
    let meeting: serde_json::Value = match thread.get("meeting") {
        Some(serde_json::Value::String(s)) => serde_json::from_str(s).unwrap_or_default(),
        Some(v) => v.clone(),
        None => serde_json::Value::Null,
    };
    let template = ["/templateDetails/id", "/templateDetails/templateId"]
        .iter()
        .find_map(|p| meeting.pointer(p).and_then(|v| v.as_str()))
        .unwrap_or_default()
        .to_lowercase();
    if template == crate::calling::live_event::TOWNHALL_TEMPLATE
        || template == crate::calling::live_event::WEBINAR_TEMPLATE
    {
        "event"
    } else {
        "meeting"
    }
}

/// The backroom chats seen in the chat list: chat id → (kind, title).
static BACKROOMS: std::sync::RwLock<Option<std::collections::HashMap<String, (String, String)>>> =
    std::sync::RwLock::new(None);

/// A chat's backroom kind and own title, if the chat list said it is one.
pub fn backroom_of(chat_id: &str) -> Option<(String, String)> {
    BACKROOMS.read().ok()?.as_ref()?.get(chat_id).cloned()
}

/// A backroom chat's title as Teams shows it: "Event group: {title}"
/// (event_backroom_chat_title_prefix) or "Planning group: {title}"
/// (meeting_backroom_chat_title_prefix), in the app language.
pub fn backroom_title(kind: &str, title: &str) -> String {
    match kind {
        "event" => crate::i18n::fill(
            &crate::i18n::tr_id("Event group: %1", "messaging:k6wwmex4q"),
            &[title],
        ),
        "meeting" => crate::i18n::fill(
            &crate::i18n::tr_id("Planning group: %1", "messaging:k21d43hht"),
            &[title],
        ),
        _ => title.to_string(),
    }
}

/// Your notes-to-self chat's name, as Teams lists it: "{you} (You)"
/// (chat_self_chat_header_title, in the app language).
pub fn notes_name(my_name: &str) -> String {
    crate::i18n::fill(
        &crate::i18n::tr_id("%1 (You)", "messaging:kdq26mx1z"),
        &[my_name],
    )
}

/// The chats as Teams lists them: your notes-to-self chat (48:notes) first
/// as "{you} (You)", then the rest. System streams (48:drafts, 48:threads,
/// call logs, notifications, mentions…) aren't chats, channels belong under
/// their team, and chats Teams leaves out (`unlisted`) or you hid aren't
/// listed. Chats nothing has been said in are listed, as Teams does.
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
            && !c.unlisted
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
    /// Its formatting: the sanitized HTML and flow parts (quotes, code
    /// blocks, pictures), and its files' names; empty for text-only rows
    /// (events, recordings).
    pub html: String,
    pub flow: Vec<super::messages::FlowPart>,
    pub files: Vec<String>,
}

/// List recent chats and return structured data.
pub async fn list_chats_data(client: &TeamsClient, limit: usize) -> Result<Vec<ChatInfo>> {
    // Strategy 1: CSA AFD endpoint with Bearer auth
    let csa_url = format!(
        "https://teams.microsoft.com/api/csa/api/v1/teams/users/ME/conversations?view=mychats&pageSize={}",
        limit
    );
    tracing::debug!("Trying CSA endpoint: {}", csa_url);
    // A personal account's chats are on Teams free's chat service (its
    // front door); the work CSA and aggregator don't know the account.
    let first = if client.is_personal() {
        let url = format!(
            "{}/v1/users/ME/conversations?view=mychats&pageSize={}",
            client.chat_service_url(),
            limit
        );
        Ok(client.chat_get(&url).await?)
    } else {
        client.csa_get(&csa_url).await
    };
    let resp = match first {
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

    let mut raw: serde_json::Value = resp
        .json()
        .await
        .context("Failed to parse conversations response")?;
    // The chat service hands the list out in time slices: the first page
    // holds the chats active lately, its backwardLink the older ones (in
    // ost-test1's case "OST empty chat test" and "OST large chat test",
    // which Teams' chat list shows from its full sync). Read them all.
    // (Older slices change only when a chat in them changes, and then it is
    // on the first page too: they're kept for ten minutes, each kept chat
    // brought up to date from the first page as it's read.)
    static OLDER: std::sync::Mutex<Option<(std::time::Instant, Vec<serde_json::Value>, usize)>> =
        std::sync::Mutex::new(None);
    let cached = OLDER
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|(at, _, _)| at.elapsed() < std::time::Duration::from_secs(600))
        .map(|(_, v, n)| (v.clone(), *n));
    let (mut older, pages) = match cached {
        Some(c) => c,
        None => {
            let mut back = raw
                .pointer("/_metadata/backwardLink")
                .and_then(|l| l.as_str())
                .unwrap_or_default()
                .to_string();
            let (mut older, mut pages) = (Vec::new(), 0usize);
            while !back.is_empty() && pages < 20 {
                let url = if back.contains("pageSize=") {
                    back.clone()
                } else {
                    format!("{back}&pageSize=200")
                };
                let Ok(r) = client.chat_get(&url).await else {
                    break;
                };
                let Ok(more) = r.json::<serde_json::Value>().await else {
                    break;
                };
                pages += 1;
                let page = more
                    .get("conversations")
                    .and_then(|c| c.as_array())
                    .cloned()
                    .unwrap_or_default();
                if page.is_empty() {
                    break;
                }
                older.extend(page);
                back = more
                    .pointer("/_metadata/backwardLink")
                    .and_then(|l| l.as_str())
                    .unwrap_or_default()
                    .to_string();
            }
            *OLDER.lock().unwrap_or_else(|e| e.into_inner()) =
                Some((std::time::Instant::now(), older.clone(), pages));
            (older, pages)
        }
    };
    if let Some(first) = raw.get("conversations").and_then(|c| c.as_array())
        && refresh_older(&mut older, first)
        && let Some((_, kept, _)) = OLDER.lock().unwrap_or_else(|e| e.into_inner()).as_mut()
    {
        kept.clone_from(&older);
    }
    if let Some(list) = raw.get_mut("conversations").and_then(|c| c.as_array_mut()) {
        let mut seen: std::collections::HashSet<String> = list
            .iter()
            .filter_map(|c| c.get("id").and_then(|i| i.as_str()).map(str::to_string))
            .collect();
        list.extend(older.into_iter().filter(|c| {
            c.get("id")
                .and_then(|i| i.as_str())
                .is_some_and(|i| seen.insert(i.to_string()))
        }));
    }
    let body: ConversationsResponse =
        serde_json::from_value(raw.clone()).context("Failed to parse conversations response")?;

    let conversations = body.conversations.unwrap_or_default();
    // The same conversations as JSON, for the unread rule.
    let raw_convs: Vec<serde_json::Value> = raw
        .get("conversations")
        .and_then(|c| c.as_array())
        .cloned()
        .unwrap_or_default();

    let own_oid = client.object_id();
    let me = client.self_mri().unwrap_or_default();
    let personal = client.is_personal();
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();
    let mut names: std::collections::HashMap<String, Option<String>> = Default::default();
    // Meeting chats' backroom kinds, as Teams learns them: from its chat
    // sync (CSA), not from each meeting's thread (see `chat_sync`). Only
    // the titled ones whose properties don't say already.
    let meeting_ids: Vec<String> = conversations
        .iter()
        .filter(|c| {
            has_topic(c)
                && c.thread_properties
                    .as_ref()
                    .is_none_or(|p| backroom_kind(&p.extra).is_empty())
        })
        .filter_map(|c| c.id.clone())
        .filter(|id| id.starts_with("19:meeting_"))
        .collect();
    tracing::info!(
        conversations = conversations.len(),
        pages = pages + 1,
        titled_meetings = meeting_ids.len(),
        "chat list read"
    );
    let backrooms = super::chat_sync::meeting_kinds(client, &meeting_ids).await;
    // Each chat's roster version: a chat whose members changed since OST
    // last read them is read again when it's called.
    note_roster_versions(conversations.iter().filter_map(|c| {
        let id = c.id.as_deref()?;
        let p = c.thread_properties.as_ref()?;
        let v = p
            .extra
            .get("rosterVersion")
            .or_else(|| p.extra.get("version"))?;
        Some((id, v.to_string()))
    }));
    // Group chats without a name of their own are named after their
    // members, as Teams names them (never their thread id).
    let untitled: Vec<(String, String)> = conversations
        .iter()
        .filter(|c| !has_topic(c))
        .filter_map(|c| {
            let id = c.id.as_deref()?;
            let p = c.thread_properties.as_ref()?;
            let chat = p.extra.get("threadType").and_then(|t| t.as_str()) == Some("chat");
            (chat
                && id.starts_with("19:")
                && id.ends_with("@thread.v2")
                && !id.starts_with("19:meeting_"))
            .then(|| {
                let roster = p
                    .extra
                    .get("rosterVersion")
                    .or_else(|| p.extra.get("version"))
                    .map(|v| v.to_string())
                    .unwrap_or_default();
                (id.to_string(), roster)
            })
        })
        .collect();
    // Named group chats' member names too (Teams' go-to shows a named
    // chat's members under its topic and matches them).
    let named_groups: Vec<(String, String)> = conversations
        .iter()
        .filter(|c| has_topic(c))
        .filter_map(|c| {
            let id = c.id.as_deref()?;
            let p = c.thread_properties.as_ref()?;
            let chat = p.extra.get("threadType").and_then(|t| t.as_str()) == Some("chat");
            (chat
                && id.starts_with("19:")
                && id.ends_with("@thread.v2")
                && !id.starts_with("19:meeting_"))
            .then(|| {
                let roster = p
                    .extra
                    .get("rosterVersion")
                    .or_else(|| p.extra.get("version"))
                    .map(|v| v.to_string())
                    .unwrap_or_default();
                (id.to_string(), roster)
            })
        })
        .collect();
    let untitled_ids: std::collections::HashSet<&str> =
        untitled.iter().map(|(u, _)| u.as_str()).collect();
    let titles = generated_titles(
        client,
        &[untitled.as_slice(), named_groups.as_slice()].concat(),
        &me,
    )
    .await;
    let mut chats = Vec::new();
    for (i, conv) in conversations.iter().enumerate() {
        let id = conv.id.as_deref().unwrap_or("").to_string();
        if id.is_empty() {
            continue;
        }
        // Teams free's call log stream is a system stream, not a chat.
        if is_system_stream(&id, conv.thread_properties.as_ref().map(|p| &p.extra)) {
            continue;
        }
        let unread = raw_convs
            .get(i)
            .is_some_and(|c| super::messages::is_unread(c, &me));

        let one_on_one_thread = conv
            .thread_properties
            .as_ref()
            .is_some_and(|p| is_one_on_one_thread(&p.extra));
        let is_group = (id.contains("thread") || id.contains("meeting")) && !one_on_one_thread;
        if one_on_one_thread {
            ONE_ON_ONE_THREADS
                .write()
                .unwrap_or_else(|e| e.into_inner())
                .get_or_insert_with(Default::default)
                .insert(id.clone());
        }
        // Its members (when they were read for its name): its other person
        // and whether anyone in it is on Teams free.
        let members = known_title_members(&id);
        // (For a personal account, the people outside Teams free are
        // the work users.)
        let external = if personal {
            members
                .iter()
                .any(|m| crate::identity::work_object_id(m).is_some())
        } else {
            members.iter().any(|m| crate::identity::is_consumer_mri(m))
        };
        let peer = one_on_one_thread
            .then(|| {
                members
                    .iter()
                    .find(|m| !m.eq_ignore_ascii_case(&me) && crate::identity::is_person_mri(m))
                    .cloned()
            })
            .flatten();
        let untitled_chat = untitled_ids.contains(id.as_str());
        let member_title = titles.get(&id).cloned().unwrap_or_default();
        let mut name = if untitled_chat {
            // (Its members unreadable: never the thread id.)
            // (A 1:1 with someone whose profile isn't yours to read yet,
            // such as a Teams free request: the name they sent with.)
            if member_title.is_empty() {
                one_on_one_thread
                    .then(|| raw_convs.get(i).and_then(|c| sender_name_unless(c, &me)))
                    .flatten()
                    .unwrap_or_else(|| crate::i18n::tr_id("Unknown", "messaging:k7k6gmhup"))
            } else {
                member_title.clone()
            }
        } else {
            conversation_name(conv)
        };
        // A 1:1 thread is named after the other person in full (the
        // generated names use given names, as a group's do).
        if one_on_one_thread
            && !has_topic(conv)
            && let Some(full) = peer.as_deref().and_then(known_person_name)
        {
            name = full;
        }
        let mut backroom = conv
            .thread_properties
            .as_ref()
            .map(|p| backroom_kind(&p.extra))
            .unwrap_or_default()
            .to_string();
        if backroom.is_empty() && id.starts_with("19:meeting_") && has_topic(conv) {
            backroom = backrooms.get(&id).cloned().unwrap_or_default();
        }
        let mut topic = String::new();
        if !backroom.is_empty() && has_topic(conv) {
            topic = name.clone();
            name = backroom_title(&backroom, &name);
            BACKROOMS
                .write()
                .unwrap_or_else(|e| e.into_inner())
                .get_or_insert_with(Default::default)
                .insert(id.clone(), (backroom.clone(), topic.clone()));
        }
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

        let named = has_topic(conv);
        let bot = bot_one_on_one(&id, conv);
        let cfet = cfet_thread(&id)
            || conv
                .thread_properties
                .as_ref()
                .and_then(|p| p.extra.get("cfet"))
                .is_some_and(|v| {
                    v.as_bool().unwrap_or_else(|| {
                        v.as_str().is_some_and(|s| s.eq_ignore_ascii_case("true"))
                    })
                });
        let thread_ms = |k: &str| {
            conv.thread_properties
                .as_ref()
                .and_then(|p| p.extra.get(k))
                .and_then(|j| {
                    j.as_str()
                        .and_then(|s| s.parse().ok())
                        .or_else(|| j.as_i64())
                })
                .unwrap_or(0)
        };
        let group_chat = is_group && !id.starts_with("19:meeting_") && id.ends_with("@thread.v2");
        let member_names = if group_chat {
            title_member_names(&members, &me)
        } else {
            Vec::new()
        };
        let alone = group_chat && members.len() == 1 && members[0].eq_ignore_ascii_case(&me);
        chats.push(ChatInfo {
            horizon_ms: conv
                .properties
                .as_ref()
                .and_then(|p| p.get("consumptionhorizon"))
                .and_then(|h| h.as_str())
                .map(horizon_arrival)
                .unwrap_or(0),
            created_ms: thread_ms("createdat"),
            member_title: if named && group_chat {
                member_title
            } else {
                String::new()
            },
            member_names,
            alone,
            left: conv
                .thread_properties
                .as_ref()
                .is_some_and(|p| left(&p.extra)),
            id,
            name,
            is_group,
            named,
            last_message_time: last_time,
            last_message_sender: last_sender,
            last_message_preview: last_preview,
            last_message_system: preview_system,
            live_call: conv
                .thread_properties
                .as_ref()
                .and_then(|p| live_call(&p.extra, now_secs)),
            muted: is_muted(conv),
            messaging_disabled: conv
                .thread_properties
                .as_ref()
                .and_then(|p| p.extra.get("messagingdisabled"))
                .and_then(|v| v.as_str())
                .is_some_and(|v| v.eq_ignore_ascii_case("true")),
            bot,
            cfet,
            empty: conv
                .properties
                .as_ref()
                .and_then(|p| p.get("isemptyconversation"))
                .and_then(|e| e.as_str())
                .is_some_and(|e| e.eq_ignore_ascii_case("true")),
            // Hidden (Hide) or its history removed (Remove chat history):
            // listed again once something newer is said.
            hidden: hidden_until_newer(
                ["historyHiddenTime", "clearHistoryTime"]
                    .iter()
                    .filter_map(|k| {
                        conv.properties
                            .as_ref()
                            .and_then(|p| p.get(*k))
                            .and_then(|h| {
                                h.as_str()
                                    .and_then(|s| s.parse().ok())
                                    .or_else(|| h.as_i64())
                            })
                    })
                    .max(),
                conv.last_message
                    .as_ref()
                    .and_then(|m| m.original_arrival_time.as_deref())
                    .and_then(crate::clock::parse_instant)
                    .map(crate::clock::millis),
            ),
            backroom,
            topic,
            is_creator: conv
                .thread_properties
                .as_ref()
                .and_then(|p| p.extra.get("isCreator"))
                .and_then(|c| c.as_bool())
                .unwrap_or(false),
            unread,
            request: raw_convs.get(i).is_some_and(is_chat_request),
            inviter: raw_convs
                .get(i)
                .filter(|c| is_chat_request(c))
                .and_then(|c| c["properties"]["addedBy"].as_str())
                .filter(|m| crate::identity::is_person_mri(m))
                .map(str::to_string),
            inviter_name: raw_convs
                .get(i)
                .filter(|c| is_chat_request(c))
                .and_then(|c| {
                    let by = c["properties"]["addedBy"].as_str()?;
                    known_person_name(by).or_else(|| sender_name_if(c, by))
                }),
            peer,
            external,
            activity_ms: {
                let message = conv
                    .last_message
                    .as_ref()
                    .and_then(|m| m.original_arrival_time.as_deref())
                    .and_then(crate::clock::parse_instant)
                    .map(crate::clock::millis)
                    .unwrap_or(0);
                let joined = conv
                    .thread_properties
                    .as_ref()
                    .and_then(|p| p.extra.get("lastjoinat"))
                    .and_then(|j| {
                        j.as_str()
                            .and_then(|s| s.parse().ok())
                            .or_else(|| j.as_i64())
                    })
                    .unwrap_or(0);
                message.max(joined)
            },
            unlisted: conv.thread_properties.as_ref().is_some_and(|p| {
                let empty = conv
                    .properties
                    .as_ref()
                    .and_then(|p| p.get("isemptyconversation"))
                    .and_then(|e| e.as_str())
                    .is_some_and(|e| e.eq_ignore_ascii_case("true"));
                unlisted(&p.extra, empty, !is_group)
            }),
        });
    }

    // Teams' Most recent order (checked on winpc 2026-11-15: an empty Meet
    // now chat joined after a one-on-one's last message lists above it).
    chats.sort_by(|a, b| b.activity_ms.cmp(&a.activity_ms));
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
                m["messagetype"]
                    .as_str()
                    .is_some_and(|t| t.starts_with("Text") || t.starts_with("RichText"))
                    && !m["content"].as_str().unwrap_or_default().is_empty()
            })
            .count();
        sync = page
            .get("_metadata")
            .and_then(super::messages::backward_token);
        if shown >= limit || sync.is_none() {
            break;
        }
    }
    let body = serde_json::json!({ "messages": raw });

    let me = client.self_mri().unwrap_or_default();
    let own_name = client.display_name();
    let mut names: std::collections::HashMap<String, Option<String>> = Default::default();
    let mut result = Vec::new();
    // Messages come newest-first; show them oldest first.
    for m in body["messages"].as_array().into_iter().flatten().rev() {
        let Some(mut view) =
            super::messages::message_view(m, &me, own_name.as_deref().unwrap_or_default())
        else {
            continue;
        };
        // A meeting recording: Teams' words for it, not its XML's text
        // (which ends in the card's "Play" link), with its organizer.
        let kind = m["messagetype"].as_str().unwrap_or_default();
        if kind.starts_with("RichText/Media_CallRecording")
            || kind == "RichText/Media_CallLocalRecording"
        {
            let content = m["content"].as_str().unwrap_or_default();
            let organizer = match between(content, "<MeetingOrganizerId value=\"", "\"")
                .and_then(crate::identity::work_object_id)
            {
                Some(oid) => resolve_user_name(client, oid, &mut names).await,
                None => None,
            };
            let Some(text) = recording_summary(content, organizer.as_deref()) else {
                continue;
            };
            view.text = text;
            // Teams' words, not the recording card's markup.
            view.html.clear();
            view.flow.clear();
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

/// Bring the kept older slices of the chat list up to date with its first
/// page: a chat that changes (hidden or shown by any client, a new message)
/// is on the first page then, and once newer changes push it back into the
/// older slices its kept copy must be the changed one, not the one read when
/// the slices were kept (a burst of hides showed chats again), and a chat
/// that was on the first page then must be kept too (it went missing from
/// the list). Whether the kept slices changed.
fn refresh_older(older: &mut Vec<serde_json::Value>, first: &[serde_json::Value]) -> bool {
    let id = |c: &serde_json::Value| c.get("id").and_then(|i| i.as_str()).map(str::to_string);
    let mut at: std::collections::HashMap<String, usize> = older
        .iter()
        .enumerate()
        .filter_map(|(n, c)| Some((id(c)?, n)))
        .collect();
    let mut changed = false;
    for new in first {
        let Some(i) = id(new) else { continue };
        match at.get(&i) {
            Some(&n) if older[n] == *new => {}
            Some(&n) => {
                older[n] = new.clone();
                changed = true;
            }
            None => {
                at.insert(i, older.len());
                older.push(new.clone());
                changed = true;
            }
        }
    }
    changed
}

#[cfg(test)]
mod bot_chat_tests {
    use super::{Conversation, bot_one_on_one};
    use serde_json::json;

    fn conv(v: serde_json::Value) -> Conversation {
        serde_json::from_value(v).unwrap()
    }

    #[test]
    fn a_bots_one_on_one_is_known_by_its_sender_or_who_added_you() {
        let id = "19:4287e791-1b98-4963-8b94-281c50472683_358f0194-6b0e-4dd3-af35-c24fe8a9ec87@unq.gbl.spaces";
        // Workflows (ost-test1, 2026-11-27): the bot wrote last.
        let sent = conv(
            json!({ "id": id, "lastMessage": { "from": "https://amer.ng.msg.teams.microsoft.com/v1/users/ME/contacts/28:358f0194-6b0e-4dd3-af35-c24fe8a9ec87" } }),
        );
        assert!(bot_one_on_one(id, &sent));
        let added = conv(
            json!({ "id": id, "properties": { "addedBy": "28:358F0194-6B0E-4DD3-AF35-C24FE8A9EC87" } }),
        );
        assert!(bot_one_on_one(id, &added));
        // A person's 1:1 and a group chat aren't.
        let person = conv(
            json!({ "id": id, "lastMessage": { "from": "https://x/v1/users/ME/contacts/8:orgid:358f0194-6b0e-4dd3-af35-c24fe8a9ec87" } }),
        );
        assert!(!bot_one_on_one(id, &person));
        assert!(!bot_one_on_one("19:abc@thread.v2", &added));
    }
}

#[cfg(test)]
mod older_slice_tests {
    use super::refresh_older;
    use serde_json::json;

    #[test]
    fn kept_slices_take_the_first_pages_copy() {
        let mut older = vec![
            json!({ "id": "19:a", "properties": {} }),
            json!({ "id": "19:b", "properties": {} }),
        ];
        let first = vec![
            json!({ "id": "19:new", "properties": {} }),
            json!({ "id": "19:b", "properties": { "historyHiddenTime": "1" } }),
        ];
        assert!(refresh_older(&mut older, &first));
        assert_eq!(older[0], json!({ "id": "19:a", "properties": {} }));
        assert_eq!(older[1]["properties"]["historyHiddenTime"], "1");
        // A chat only on the first page is kept too, for when it leaves it.
        assert_eq!(older[2]["id"], "19:new");
        // Nothing more to take: no change.
        assert!(!refresh_older(&mut older, &first));
        assert_eq!(older.len(), 3);
    }
}

#[cfg(test)]
mod tui_message_tests {
    use super::*;

    const ME: &str = "8:orgid:4287e791-1b98-4963-8b94-281c50472683";
    const OWN: &str = "https://amer.ng.msg.teams.microsoft.com/v1/users/ME/contacts/8:orgid:4287e791-1b98-4963-8b94-281c50472683";

    fn show(m: serde_json::Value) -> Option<MessageInfo> {
        tui_message(
            super::super::messages::message_view(&m, ME, "")?,
            Some("OST Test 1"),
        )
    }

    #[test]
    fn senders_as_the_tui_shows_them() {
        let text = |name: &str, from: &str| serde_json::json!({"id": "1", "messagetype": "RichText/Html", "content": "<p>hi</p>", "imdisplayname": name, "from": from});
        assert_eq!(
            show(text("Randy Northrup", "https://x/contacts/8:orgid:aaaa"))
                .unwrap()
                .sender,
            "Randy Northrup"
        );
        // A blank name on your own message shows your name…
        assert_eq!(show(text("", OWN)).unwrap().sender, "OST Test 1");
        // …and someone else's shows as Unknown.
        assert_eq!(
            show(text(" ", &OWN.replace("4287e791", "00000000")))
                .unwrap()
                .sender,
            "Unknown"
        );
    }

    #[test]
    fn recordings_read_as_teams_words_them() {
        // As the service sent OST calendar test's recording (trimmed).
        let done = r#"<URIObject type="Video.2/CallRecording.1"><RecordingStatus status="Success" code="200"></RecordingStatus><Title>OST calendar test created from OST</Title><a href="https://x">Play</a><RecordingContent duration="00:01:05.120" contentTypes="Recording"/><MeetingOrganizerId value="8:orgid:nobody" /></URIObject>"#;
        let s = recording_summary(done, None).unwrap();
        assert_eq!(s, "Recording · OST calendar test created from OST · 1m 5s");
        assert_eq!(
            recording_summary(done, Some("OST Test 1")).unwrap(),
            "Recording · OST calendar test created from OST · 1m 5s · organizer OST Test 1"
        );
        assert!(!s.contains("Play"));
        assert_eq!(
            recording_summary(
                r#"<URIObject><RecordingStatus status="Initial" code="0"/></URIObject>"#,
                None
            )
            .unwrap(),
            "Recording has started"
        );
        assert_eq!(
            recording_summary(
                r#"<URIObject><RecordingStatus status="ChunkFinished" code="202"/></URIObject>"#,
                None
            )
            .unwrap(),
            "Recording stopped. Saving recording…"
        );
    }

    #[test]
    fn mentions_keep_their_names() {
        // "OST test 54" as the service holds it: one person mentioned in
        // two parts. (Its neighbour "OST test 54: mention for check" really
        // has no mention in its content: nothing was lost on the way.)
        let m = serde_json::json!({"id": "1", "messagetype": "RichText/Html", "from": OWN, "imdisplayname": "OST Test 1",
            "content": "<p>OST test 54: mention for <span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"\" itemid=\"0\">Randy</span>&nbsp;<span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"\" itemid=\"1\">Northrup</span>&nbsp;check</p>",
            "properties": {"mentions": "[{\"@type\":\"http://schema.skype.com/Mention\",\"itemid\":0,\"mri\":\"8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3\",\"mentionType\":\"person\",\"displayName\":\"Randy\"},{\"@type\":\"http://schema.skype.com/Mention\",\"itemid\":1,\"mri\":\"8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3\",\"mentionType\":\"person\",\"displayName\":\"Northrup\"}]"}});
        assert_eq!(
            show(m).unwrap().content,
            "OST test 54: mention for Randy Northrup check"
        );
    }

    #[test]
    fn no_raw_json_or_card_buttons() {
        // A system event shows as Teams' sentence, not its JSON.
        let event = serde_json::json!({"id": "2", "messagetype": "ThreadActivity/AddMember",
            "content": "<addmember><eventtime>1</eventtime><initiator>8:orgid:a</initiator><target>8:orgid:b</target></addmember>",
            "from": "https://x/contacts/8:orgid:a"});
        if let Some(m) = show(event) {
            assert!(
                !m.content.starts_with('{') && !m.content.contains("<addmember>"),
                "{}",
                m.content
            );
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

/// The conversation that holds your Calls history.
pub const CALL_LOGS: &str = "48:calllogs";

/// Someone else in a call, as its log names them.
#[derive(Debug, Clone, Default, serde::Serialize, PartialEq, Eq)]
pub struct CallParticipant {
    pub mri: String,
    /// The log's display name (often empty: the app looks people up).
    pub name: String,
    /// Their given name, which Teams puts in a group call's name (filled
    /// in by the app).
    pub given: String,
}

/// One row of the Calls history (from the `48:calllogs` stream), with what
/// Teams' call log model (CallLogDbRow / CallLogItem) works out of it.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct CallRecord {
    /// The log message's id (what Remove from view and Report call name).
    pub message_id: String,
    pub call_id: String,
    /// "incoming" or "outgoing".
    pub direction: String,
    /// "accepted", "missed", "declined", … as the service reports it.
    pub state: String,
    /// "twoParty" or "multiParty".
    pub call_type: String,
    pub start_time: String,
    pub connect_time: Option<String>,
    pub end_time: Option<String>,
    /// How long it was connected, in whole milliseconds (Teams'
    /// durationInMs: end minus connect, none for a voicemail).
    pub duration_ms: i64,
    /// The chat the call was in (a group chat's or meeting's), if any.
    pub thread_id: String,
    /// Teams' isGroupCall: a multi-party call in a chat, or with more than
    /// one other person.
    pub is_group: bool,
    /// The person Teams resolves the call to (its `person` and
    /// resolvedDisplayName): whoever you called, or who called you. Your
    /// own id when the log names you as the target of a call you placed.
    pub peer_mri: String,
    pub peer_name: String,
    /// Who placed the call.
    pub originator_mri: String,
    pub originator_name: String,
    /// The others in the call, without you and bots.
    pub participants: Vec<CallParticipant>,
    /// Who transferred the call to you, when Teams says so ("Transferred
    /// by …": a transferor, no transfer target, neither you nor the call's
    /// person; none on a parked call).
    pub transferor_mri: String,
    pub transferor_name: String,
    /// The call's chat topic (Teams' groupCall.title; filled in by the
    /// app), which names a group call.
    pub title: String,
    /// Whether you can still read the call's chat (Teams' isUserMember).
    pub member: bool,
    /// An unread missed call (its activity not yet opened; filled in by the
    /// app), and that activity's id.
    pub unread: bool,
    pub activity_id: String,
}

/// Recent calls, newest first, as Teams lists them: `limit` log messages
/// at most, read 100 at a time as far back as the service keeps them
/// (Teams lists the whole history).
pub async fn call_history(client: &TeamsClient, limit: usize) -> Result<Vec<CallRecord>> {
    let base = client.chat_service_url();
    let mut url = format!(
        "{base}/v1/users/ME/conversations/{CALL_LOGS}/messages?pageSize=100&view=msnp24Equivalent"
    );
    let mut messages: Vec<serde_json::Value> = Vec::new();
    loop {
        let v: serde_json::Value = client
            .chat_get(&url)
            .await?
            .json()
            .await
            .context("Call history reply")?;
        let page = v
            .get("messages")
            .and_then(|m| m.as_array())
            .cloned()
            .unwrap_or_default();
        let empty = page.is_empty();
        messages.extend(page);
        // The next (older) page, on the chat service only.
        let next = v
            .pointer("/_metadata/backwardLink")
            .and_then(|l| l.as_str())
            .filter(|l| l.starts_with(&base) && !l.contains(['#', ' ']));
        match next {
            Some(n) if !empty && messages.len() < limit => url = n.to_string(),
            _ => break,
        }
    }
    let me = client.self_mri().unwrap_or_default();
    Ok(call_records(
        &serde_json::json!({ "messages": messages }),
        &me,
    ))
}

/// Remove a call from your history (Teams' Remove from view): its log
/// message gets `isDeleted`, which every client then leaves out.
pub async fn remove_call(client: &TeamsClient, message_id: &str) -> Result<()> {
    if message_id.is_empty() || !message_id.chars().all(|c| c.is_ascii_digit()) {
        anyhow::bail!("Not a call log message id");
    }
    let base = format!(
        "{}/v1/users/ME/conversations/{CALL_LOGS}/messages/{message_id}",
        client.chat_service_url()
    );
    let m: serde_json::Value = client
        .chat_get(&base)
        .await?
        .json()
        .await
        .context("Call log message")?;
    let log = m
        .pointer("/properties/call-log")
        .context("No call log in that message")?;
    let mut log: serde_json::Value = match log {
        serde_json::Value::String(s) => serde_json::from_str(s).context("Call log")?,
        v => v.clone(),
    };
    let obj = log.as_object_mut().context("Call log isn't an object")?;
    obj.insert("isDeleted".into(), serde_json::Value::Bool(true));
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!("{base}/properties?name=call-log"),
            &serde_json::json!({ "call-log": log.to_string() }),
        )
        .await?;
    Ok(())
}

/// Report a call to Microsoft (Teams' Report a concern: middle tier
/// `beta/reports`). `reported` is the other person, none for a group call.
pub async fn report_call(
    client: &TeamsClient,
    message_id: &str,
    reported: Option<&str>,
    comment: &str,
) -> Result<()> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let body = serde_json::json!({
        "reportType": "Call",
        "reportTimestamp": jiff::Timestamp::now().to_string(),
        "reportedUsers": reported.into_iter().collect::<Vec<_>>(),
        "messageId": message_id,
        "category": "Security",
        "comment": comment,
    });
    let r = client
        .http()
        .post(format!("{base}/beta/reports"))
        .bearer_auth(&token)
        .header("x-ms-client-caller", "Mutation:reportCall")
        .json(&body)
        .send()
        .await
        .context("Report call")?;
    if !r.status().is_success() {
        anyhow::bail!("Report call: HTTP {}", r.status().as_u16());
    }
    Ok(())
}

/// A call log's time in milliseconds since 1970 (as a browser's Date reads
/// it: the fraction past milliseconds dropped).
pub fn call_time_ms(iso: &str) -> Option<i64> {
    iso.parse::<jiff::Timestamp>()
        .ok()
        .map(|t| t.as_millisecond())
}

/// The rows of a `48:calllogs` reply, as Teams' reduceCallHistoryMessages
/// keeps them: only call logs (a personal attendant's log belongs to its
/// call), none removed from view, no screen sharing sessions, no call park
/// pickups, and no outgoing call that reached nobody (a Meet now you were
/// alone in); one row per call and leg.
pub fn call_records(reply: &serde_json::Value, me: &str) -> Vec<CallRecord> {
    let logs: Vec<(String, serde_json::Value)> = reply
        .get("messages")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter(|m| {
            // Text (and HTML) messages are the calls; the rest are a
            // call's transcript, recording or attendant log.
            matches!(
                m.get("messagetype").and_then(|t| t.as_str()),
                Some("Text" | "RichText/Html" | "RichText")
            )
        })
        .filter_map(|m| {
            let log = m.pointer("/properties/call-log")?;
            let log = match log {
                serde_json::Value::String(s) => serde_json::from_str(s).ok()?,
                v => v.clone(),
            };
            let id = m.get("id").and_then(|i| i.as_str()).unwrap_or_default();
            Some((id.to_string(), log))
        })
        .collect();
    let deleted: std::collections::HashSet<String> = logs
        .iter()
        .filter(|(_, l)| l.get("isDeleted").and_then(|d| d.as_bool()) == Some(true))
        .filter_map(|(_, l)| l.get("callId").and_then(|c| c.as_str()).map(String::from))
        .collect();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    logs.iter()
        .filter_map(|(id, l)| parse_call_log(id, l, me))
        .filter(|r| !deleted.contains(&r.record.call_id))
        .filter(|r| seen.insert(format!("{}-{}", r.record.call_id, r.leg)))
        .map(|r| r.record)
        .collect()
}

/// A parsed log and its leg (Teams keys a row by call and leg).
struct ParsedLog {
    record: CallRecord,
    leg: String,
}

fn parse_call_log(message_id: &str, v: &serde_json::Value, me: &str) -> Option<ParsedLog> {
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).map(str::to_string);
    let direction = s("callDirection")?;
    let start_time = s("startTime")?;
    let participant = |k: &str, id_key: &str| -> Option<(String, String, String)> {
        let p = v.get(k).filter(|p| p.is_object());
        let id = p
            .and_then(|p| p.get("id"))
            .and_then(|i| i.as_str())
            .map(str::to_string)
            .or_else(|| s(id_key))?;
        let name = p
            .and_then(|p| p.get("displayName"))
            .and_then(|n| n.as_str())
            .unwrap_or_default()
            .to_string();
        let kind = p
            .and_then(|p| p.get("type"))
            .and_then(|n| n.as_str())
            .unwrap_or_default()
            .to_string();
        Some((id, name, kind))
    };
    let originator = participant("originatorParticipant", "originator");
    let target = participant("targetParticipant", "target");
    let outgoing = direction.eq_ignore_ascii_case("outgoing");
    let state = s("callState").unwrap_or_default();
    let missed = !outgoing && state.eq_ignore_ascii_case("missed");
    let session = s("sessionType").unwrap_or_default();
    if session.eq_ignore_ascii_case("screenSharing") {
        return None;
    }
    if target
        .as_ref()
        .is_some_and(|t| t.2.eq_ignore_ascii_case("callParkService"))
    {
        return None;
    }
    // The others: participantList without you and bots, a personal
    // attendant first (Teams' participantList getter).
    let list = v.get("participantList").and_then(|p| p.as_array());
    let is_attendant = |p: &serde_json::Value| {
        p.get("type")
            .and_then(|t| t.as_str())
            .is_some_and(|t| t.eq_ignore_ascii_case("personalattendant"))
    };
    let mut people: Vec<(bool, CallParticipant)> = list
        .into_iter()
        .flatten()
        .filter_map(|p| {
            let mri = p.get("id")?.as_str()?.to_string();
            let name = p
                .get("displayName")
                .and_then(|n| n.as_str())
                .unwrap_or_default()
                .to_string();
            Some((
                is_attendant(p),
                CallParticipant {
                    mri,
                    name,
                    given: String::new(),
                },
            ))
        })
        .filter(|(_, p)| p.mri != me && !p.mri.starts_with("28:"))
        .collect();
    // (a stable sort: the attendant first, the rest in the log's order)
    people.sort_by_key(|(attendant, _)| !attendant);
    let participants: Vec<CallParticipant> = people.into_iter().map(|(_, p)| p).collect();
    // isOutgoingCallWithNoTarget: a call you placed that reached nobody.
    if outgoing && target.is_none() && participants.is_empty() {
        return None;
    }
    let thread_id = s("threadId").unwrap_or_default();
    let call_type = s("callType").unwrap_or_default();
    let multi = call_type.eq_ignore_ascii_case("multiParty");
    let is_group = multi && (participants.len() > 1 || !thread_id.is_empty());
    // The person (Teams' yT): with both ends, the target when you placed
    // it, else whoever placed it; a call to one other person in a chat,
    // them; a missed call, its caller.
    let person = match (&originator, &target) {
        (Some(o), Some(t)) => Some(if o.0.contains(me) && !me.is_empty() {
            t.clone()
        } else {
            o.clone()
        }),
        (_, None) if outgoing && participants.len() == 1 => Some((
            participants[0].mri.clone(),
            participants[0].name.clone(),
            String::new(),
        )),
        (Some(o), _) if missed => Some(o.clone()),
        _ => None,
    };
    let (peer_mri, peer_name) = person.map(|p| (p.0, p.1)).unwrap_or_default();
    let connect_time = s("connectTime");
    let end_time = s("endTime");
    let voicemail = target
        .as_ref()
        .is_some_and(|t| t.2.eq_ignore_ascii_case("voicemail"));
    let duration_ms = match v.get("durationInSeconds").and_then(|d| {
        d.as_f64()
            .or_else(|| d.as_str().and_then(|s| s.parse::<f64>().ok()))
    }) {
        Some(secs) => (secs * 1000.0) as i64,
        None => match (&connect_time, &end_time) {
            (Some(c), Some(e)) if !voicemail => match (call_time_ms(c), call_time_ms(e)) {
                (Some(c), Some(e)) => e - c,
                _ => 0,
            },
            _ => 0,
        },
    };
    // Teams' isParkedCall, transferorParticipant, transferTargetParticipant
    // and showTransferorAsCallHistoryDescription.
    let kind_of = |p: Option<&serde_json::Value>| {
        p.and_then(|p| p.get("type"))
            .and_then(|t| t.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let park = v
        .pointer("/transferInfo/parkType")
        .and_then(|t| t.as_str())
        .unwrap_or_default();
    let parked = (!park.is_empty() && park != "none" && park != "Unknown")
        || [
            target.as_ref().map(|t| t.2.clone()).unwrap_or_default(),
            originator.as_ref().map(|o| o.2.clone()).unwrap_or_default(),
            kind_of(v.pointer("/callAttributes/transferor")),
        ]
        .iter()
        .any(|k| k == "callParkService");
    let transferor = v
        .pointer("/callAttributes/transferor")
        .filter(|t| t.is_object())
        .or_else(|| {
            v.pointer("/transferInfo/transferor")
                .filter(|t| t.is_object())
        })
        .filter(|_| !parked);
    let transfer_target = !parked
        && v.pointer("/transferInfo/transferTarget")
            .is_some_and(|t| t.is_object());
    let (transferor_mri, transferor_name) = match transferor {
        Some(t) if !transfer_target => {
            let id = t.get("id").and_then(|i| i.as_str()).unwrap_or_default();
            if id.is_empty() || id == me || id == peer_mri || id.starts_with("28:") {
                (String::new(), String::new())
            } else {
                let name = t.get("displayName").and_then(|n| n.as_str());
                (id.to_string(), name.unwrap_or_default().to_string())
            }
        }
        _ => (String::new(), String::new()),
    };
    let (originator_mri, originator_name) = originator.map(|o| (o.0, o.1)).unwrap_or_default();
    let call_id = s("callId").unwrap_or_default();
    Some(ParsedLog {
        leg: s("userParticipantId").unwrap_or_default(),
        record: CallRecord {
            message_id: message_id.to_string(),
            call_id,
            direction: direction.to_ascii_lowercase(),
            state,
            call_type,
            start_time,
            connect_time,
            end_time,
            duration_ms,
            thread_id,
            is_group,
            peer_mri,
            peer_name,
            originator_mri,
            originator_name,
            participants,
            transferor_mri,
            transferor_name,
            ..CallRecord::default()
        },
    })
}

#[cfg(test)]
mod call_log_tests {
    use super::{call_records, call_time_ms};

    const ME: &str = "8:orgid:4287e791-1b98-4963-8b94-281c50472683";
    const T3: &str = "8:orgid:01c4860d-5776-4b16-8736-6a739fcc8b34";
    const T2: &str = "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5";

    fn reply(logs: &[(&str, &str, serde_json::Value)]) -> serde_json::Value {
        serde_json::json!({ "messages": logs.iter().map(|(id, kind, log)| serde_json::json!({
            "id": id, "messagetype": kind, "properties": { "call-log": log.to_string() }
        })).collect::<Vec<_>>() })
    }

    fn p(id: &str, name: Option<&str>) -> serde_json::Value {
        serde_json::json!({"id": id, "type": "default", "displayName": name})
    }

    #[test]
    fn rows_as_teams_lists_them() {
        // ost-test1's history of 2026-11-27, as the service holds it
        // (trimmed): a Meet now alone (no target, nobody else), a call in
        // "OST TEST 348 ost" (target: you), a missed one there, a group
        // call in a chat without a topic, a 1:1 call and a personal
        // attendant's log.
        let alone = serde_json::json!({"startTime": "2026-11-27T14:30:24.2567883Z", "connectTime": "2026-11-27T14:30:24.7715567Z", "endTime": "2026-11-27T14:31:23.092523Z",
            "callDirection": "outgoing", "callType": "multiParty", "callState": "accepted", "userParticipantId": "d6e3", "originator": ME, "target": null,
            "originatorParticipant": p(ME, Some("OST Test 1")), "targetParticipant": null, "callId": "ebe3",
            "participants": [ME], "participantList": [p(ME, None)], "threadId": "19:6b5a@thread.v2", "sessionType": "default"});
        let meeting = serde_json::json!({"startTime": "2026-11-27T12:46:29.6005548Z", "connectTime": "2026-11-27T12:46:34.3217729Z", "endTime": "2026-11-27T12:49:42.5531783Z",
            "callDirection": "outgoing", "callType": "multiParty", "callState": "accepted", "userParticipantId": "663a", "originator": ME, "target": ME,
            "originatorParticipant": p(ME, Some("OST Test 1")), "targetParticipant": p(ME, None), "callId": "f935",
            "participantList": [p(T3, None), p(ME, None), p(T2, None)], "threadId": "19:68dc@thread.v2", "sessionType": "default"});
        let missed = serde_json::json!({"startTime": "2026-11-27T12:31:39.3252979Z", "connectTime": null, "endTime": "2026-11-27T12:32:35.3393575Z",
            "callDirection": "incoming", "callType": "multiParty", "callState": "missed", "userParticipantId": "b41f", "originator": T3, "target": ME,
            "originatorParticipant": p(T3, Some("OST Test 3")), "targetParticipant": p(ME, None), "callId": "0287",
            "participantList": [p(T3, None)], "threadId": "19:7e81@thread.v2", "sessionType": "default"});
        let group = serde_json::json!({"startTime": "2026-11-27T08:10:06.474375Z", "connectTime": "2026-11-27T08:10:09.294559Z", "endTime": "2026-11-27T08:11:18.8290945Z",
            "callDirection": "outgoing", "callType": "multiParty", "callState": "accepted", "userParticipantId": "e4a5", "originator": ME, "target": T3,
            "originatorParticipant": p(ME, Some("OST Test 1")), "targetParticipant": p(T3, None), "callId": "5490",
            "participantList": [p(ME, None), p(T3, None), p(T2, None), p("28:bot", None)], "threadId": "19:b160@thread.v2", "sessionType": "default"});
        let one = serde_json::json!({"startTime": "2026-11-27T07:09:11Z", "connectTime": "2026-11-27T07:09:15.100Z", "endTime": "2026-11-27T07:11:48.900Z",
            "callDirection": "incoming", "callType": "twoParty", "callState": "accepted", "originator": T3, "target": ME,
            "originatorParticipant": p(T3, Some("OST Test 3")), "targetParticipant": p(ME, None), "callId": "c1"});
        let attendant = serde_json::json!({"attendantName": "PersonalAttendant", "startTime": "2026-11-22T16:06:10Z"});
        let r = reply(&[
            ("10", "Text", alone),
            ("9", "Text", meeting),
            ("8", "Text", missed),
            ("7", "Text", group),
            ("6", "Text", one),
            ("5", "RichText/CallLogPersonalAttendant", attendant),
        ]);
        let rows = call_records(&r, ME);
        // The Meet now alone and the attendant's log aren't rows.
        assert_eq!(
            rows.iter()
                .map(|r| r.message_id.as_str())
                .collect::<Vec<_>>(),
            ["9", "8", "7", "6"]
        );
        // A call in a chat is a group call, named by its chat; Teams
        // resolves its person to the log's target: you.
        assert!(rows[0].is_group);
        assert_eq!(rows[0].thread_id, "19:68dc@thread.v2");
        assert_eq!(rows[0].peer_mri, ME);
        assert_eq!(
            rows[0]
                .participants
                .iter()
                .map(|p| p.mri.as_str())
                .collect::<Vec<_>>(),
            [T3, T2]
        );
        // 3m 8.232s connected.
        assert_eq!(rows[0].duration_ms, 188_232);
        // A missed call in a chat (one other person, but a chat): a group
        // call; its person is the caller.
        assert!(rows[1].is_group);
        assert_eq!(
            (rows[1].peer_mri.as_str(), rows[1].peer_name.as_str()),
            (T3, "OST Test 3")
        );
        assert_eq!(rows[1].duration_ms, 0);
        // Bots aren't among the others; the person is whoever you called.
        assert_eq!(rows[2].participants.len(), 2);
        assert_eq!(rows[2].peer_mri, T3);
        // 1m 9.535s: Teams shows 1m 9s.
        assert_eq!(rows[2].duration_ms, 69_535);
        // A 1:1 call: its caller.
        assert!(!rows[3].is_group);
        assert_eq!(rows[3].peer_mri, T3);
        assert_eq!(rows[3].direction, "incoming");
    }

    #[test]
    fn removed_and_repeated_calls_are_dropped() {
        let log = |id: &str, deleted: bool| {
            serde_json::json!({"startTime": "2026-11-05T05:59:53Z", "callDirection": "incoming", "callType": "twoParty", "callState": "missed",
                "originator": T2, "target": ME, "originatorParticipant": p(T2, Some("OST Test 2")), "callId": id, "isDeleted": deleted})
        };
        let r = reply(&[
            ("3", "Text", log("a", true)),
            ("2", "Text", log("a", false)),
            ("1", "Text", log("b", false)),
            ("0", "Text", log("b", false)),
        ]);
        let rows = call_records(&r, ME);
        assert_eq!(
            rows.iter()
                .map(|r| r.message_id.as_str())
                .collect::<Vec<_>>(),
            ["1"]
        );
        // Screen sharing and call park pickups aren't calls in the list.
        let share = serde_json::json!({"startTime": "2026-11-05T05:59:53Z", "callDirection": "outgoing", "callType": "twoParty", "callState": "accepted",
            "originator": ME, "target": T2, "callId": "s", "sessionType": "ScreenSharing"});
        let park = serde_json::json!({"startTime": "2026-11-05T05:59:53Z", "callDirection": "outgoing", "callType": "twoParty", "callState": "accepted",
            "originator": ME, "target": "28:park", "targetParticipant": {"id": "28:park", "type": "callParkService"}, "callId": "p"});
        assert!(call_records(&reply(&[("1", "Text", share), ("2", "Text", park)]), ME).is_empty());
    }

    #[test]
    fn transferred_calls_name_who_transferred_them() {
        // OST Test 2 transferred OST Test 3's call to you (2026-11-17):
        // "Transferred by OST Test 2".
        let to_you = serde_json::json!({"startTime": "2026-11-17T21:05:00Z", "callDirection": "incoming", "callType": "twoParty", "callState": "accepted",
            "originator": T3, "target": ME, "originatorParticipant": p(T3, Some("OST Test 3")), "callId": "t1",
            "callAttributes": {"transferor": p(T2, None)}});
        // You transferred a call on (a transfer target): no transferor line.
        let by_you = serde_json::json!({"startTime": "2026-11-17T22:00:23Z", "callDirection": "outgoing", "callType": "multiParty", "callState": "accepted",
            "originator": ME, "target": T2, "callId": "t2",
            "transferInfo": {"transferor": p(ME, None), "transferTarget": p(T3, None), "parkType": "none"}});
        // A parked call: no transferor.
        let parked = serde_json::json!({"startTime": "2026-11-17T22:08:16Z", "callDirection": "outgoing", "callType": "twoParty", "callState": "accepted",
            "originator": ME, "target": T2, "callId": "t3", "transferInfo": {"transferor": p(T3, None), "parkType": "teamPark"}});
        let rows = call_records(
            &reply(&[
                ("3", "Text", to_you),
                ("2", "Text", by_you),
                ("1", "Text", parked),
            ]),
            ME,
        );
        assert_eq!(rows[0].transferor_mri, T2);
        assert!(rows[1].transferor_mri.is_empty());
        assert!(rows[2].transferor_mri.is_empty());
    }

    #[test]
    fn times_read_as_a_browser_does() {
        assert_eq!(
            call_time_ms("2026-11-27T12:31:39.3252979Z"),
            call_time_ms("2026-11-27T12:31:39.325Z")
        );
        assert!(call_time_ms("soon").is_none());
    }
}

#[cfg(test)]
mod live_call_tests {
    use super::{live_call, thread_meeting};

    #[test]
    fn a_meeting_chats_meeting_is_read() {
        // As the OST calendar test meeting's thread has it.
        let meeting = r#"{"subject":"OST calendar test: created from OST","startTime":"2026-11-06T23:00:00Z","endTime":"2026-11-06T23:30:00Z","iCalUid":"0400","isCancelled":false,"organizerId":"4287","meetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/19%3ameeting_Y%40thread.v2/0?context=x","meetingType":"Scheduled","coOrganizerIds":["9edc"]}"#;
        let m = thread_meeting(&serde_json::json!({ "meeting": meeting })).unwrap();
        assert_eq!(
            (m.co_organizer_ids.clone(), m.meeting_type.as_str()),
            (vec!["9edc".to_string()], "Scheduled")
        );
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
        // A meeting's call names its code and passcode (meeting3 as
        // OST Test 1 saw it, 2026-11-17); a chat's call has none.
        assert!(call.meeting_data.is_none());
        let meeting = r#"{"conversationUrl":"https://api.flightproxy.teams.microsoft.com/api/v2/ep/conv-usea-02-prod-aks.conv.skype.com/conv/7ImO","conversationId":"59cb","groupCallInitiator":"8:orgid:9edc","expiration":1794992223,"status":"Active","conversationType":"scheduledMeeting","meetingData":{"meetingCode":"2994875690452594","passcode":"jp3nm7Cb"}}"#;
        let props: std::collections::HashMap<String, serde_json::Value> = [(
            "awareness_conversationLiveState:0".to_string(),
            serde_json::json!(meeting),
        )]
        .into();
        let call = live_call(&props, 1_794_990_000).unwrap();
        assert_eq!(
            call.meeting_data.unwrap()["meetingCode"],
            "2994875690452594"
        );
        assert!(call.conversation_url.contains("/conv/7ImO"));
    }
}

#[cfg(test)]
mod list_preview_tests {
    use super::{ChatInfo, list_preview, listed_chats};

    #[test]
    fn system_events_and_media_preview_as_teams() {
        // OST group test's last message: Polls added (a bot).
        let add_bot = "<addmember><eventtime>1</eventtime><initiator>8:orgid:a</initiator><target>28:d2d6f9b4</target></addmember>";
        assert_eq!(
            list_preview(add_bot, "ThreadActivity/AddMember", None),
            ("Bot added".into(), true)
        );
        let add_user =
            "<addmember><initiator>8:orgid:a</initiator><target>8:orgid:b</target></addmember>";
        assert_eq!(
            list_preview(add_user, "ThreadActivity/AddMember", None).0,
            "User added"
        );
        let joined =
            "<addmember><initiator>8:orgid:a</initiator><target>8:orgid:a</target></addmember>";
        assert_eq!(
            list_preview(joined, "ThreadActivity/AddMember", None).0,
            "User joined"
        );
        assert_eq!(
            list_preview("<img src=\"x\">", "RichText/Html", None).0,
            "Sent an image"
        );
        assert_eq!(
            list_preview("<p>Hi <b>there</b></p>", "RichText/Html", None),
            ("Hi there".into(), false)
        );
        let fwd = serde_json::json!({ "forwardTemplateId": "1" });
        assert_eq!(
            list_preview("", "RichText/Html", Some(&fwd)).0,
            "Forwarded a message"
        );
    }

    #[test]
    fn horizon_arrival_as_teams_reads_it() {
        assert_eq!(
            super::horizon_arrival("1795646436569;1795646436695;4248595710370111517"),
            1795646436569
        );
        assert_eq!(super::horizon_arrival("0;0;0"), 0);
        assert_eq!(super::horizon_arrival(" "), 0);
        assert_eq!(super::horizon_arrival("12;;3"), 0);
    }

    #[test]
    fn chats_are_listed_as_teams_lists_them() {
        let chat = |id: &str, name: &str| ChatInfo {
            id: id.into(),
            name: name.into(),
            ..Default::default()
        };
        let mut empty = chat("19:e@thread.v2", "OST empty chat test");
        empty.empty = true;
        let mut lobby = chat("19:meeting_l@thread.v2", "Lobby");
        lobby.unlisted = true;
        let mut hidden = chat("19:h@thread.v2", "Hidden");
        hidden.hidden = true;
        let listed = listed_chats(
            vec![
                chat("48:drafts", "OST Test 1"),
                chat("19:g@thread.v2", "OST group test"),
                chat("48:threads", "48:threads"),
                chat("19:c@thread.tacv2", "OST test channel"),
                empty,
                lobby,
                hidden,
                chat("48:notes", "OST Test 1"),
                chat("48:calllogs", "48:calllogs"),
            ],
            "OST Test 1",
        );
        let names: Vec<&str> = listed.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(
            names,
            ["OST Test 1 (You)", "OST group test", "OST empty chat test"]
        );
        assert_eq!(listed[0].id, "48:notes");
    }

    #[test]
    fn unnamed_group_chats_are_named_after_their_members_as_teams_does() {
        use super::{ChatPerson, generated_title};
        let p = |mri: &str, display: &str, given: &str, surname: &str| ChatPerson {
            mri: mri.into(),
            display: display.into(),
            given: given.into(),
            surname: surname.into(),
        };
        let me = "8:orgid:3";
        let ids = |n: usize| (1..=n).map(|i| format!("8:orgid:{i}")).collect::<Vec<_>>();
        // OST Test 3's chats with OST Test 1 and 2: their given names, as a list.
        let test = vec![
            p("8:orgid:1", "OST Test 1", "OST", "Test 1"),
            p("8:orgid:2", "OST Test 2", "OST", "Test 2"),
            p("8:orgid:3", "OST Test 3", "OST", "Test 3"),
        ];
        assert_eq!(generated_title(&ids(3), &test, me, ""), "OST and OST");
        assert_eq!(
            generated_title(&[me.to_string()], &test[2..], me, ""),
            "Just me"
        );
        assert_eq!(generated_title(&ids(3), &[], me, ""), "Unknown");
        // As many as fit in 24, then "+N" (one more than are left out).
        let long = vec![
            p("8:orgid:1", "Alexandra Smith", "Alexandra", "Smith"),
            p("8:orgid:2", "Bartholomew Jones", "Bartholomew", "Jones"),
            p("8:orgid:3", "Me", "", ""),
            p("8:orgid:4", "Christopher Lee", "Christopher", "Lee"),
        ];
        assert_eq!(
            generated_title(&ids(6), &long, me, ""),
            "Alexandra, Bartholomew, +4"
        );
        // All fit, but not as a list: the last one drops out.
        let pair = vec![
            p("8:orgid:1", "Maximiliana Ortiz", "Maximiliana", "Ortiz"),
            p("8:orgid:2", "Bartholomew Jones", "Bartholomew", "Jones"),
            p("8:orgid:3", "Me", "", ""),
        ];
        assert_eq!(generated_title(&ids(3), &pair, me, ""), "Bartholomew, +2");
        // Three short names fit as a list.
        let short = vec![
            p("8:orgid:1", "Ann Lee", "Ann", "Lee"),
            p("8:orgid:2", "Bo Kim", "Bo", "Kim"),
            p("8:orgid:3", "Me", "", ""),
            p("8:orgid:4", "Cy Young", "Cy", "Young"),
        ];
        assert_eq!(generated_title(&ids(4), &short, me, ""), "Ann, Bo, and Cy");
        // In the app language (Intl.ListFormat); "+N" stays as it is.
        assert_eq!(
            generated_title(&ids(4), &short, me, "de-de"),
            "Ann, Bo und Cy"
        );
        assert_eq!(generated_title(&ids(3), &test, me, "fr-fr"), "OST et OST");
        assert_eq!(
            generated_title(&ids(6), &long, me, "de-de"),
            "Alexandra, Bartholomew, +4"
        );
    }

    #[test]
    fn lists_in_the_app_language() {
        use crate::i18n::list_and;
        let l = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(list_and(&l(&["A", "B"]), ""), "A and B");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "en-us"), "A, B, and C");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "en-gb"), "A, B and C");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "de-de"), "A, B und C");
        assert_eq!(list_and(&l(&["A", "B"]), "es-es"), "A y B");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "ja-jp"), "A、B、C");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "zh-tw"), "A、B和C");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "ar-sa"), "A وB وC");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "he-il"), "A, B ו-C");
        assert_eq!(list_and(&l(&["A", "B", "C"]), "sr-latn-rs"), "A, B i C");
    }

    #[test]
    fn teams_leaves_out_lobby_breakout_and_left_chats() {
        use super::unlisted;
        let props = |v: serde_json::Value| {
            v.as_object()
                .unwrap()
                .clone()
                .into_iter()
                .collect::<std::collections::HashMap<_, _>>()
        };
        let group = props(
            serde_json::json!({"threadType": "chat", "productThreadType": "Chat", "lastjoinat": "1795446459494"}),
        );
        let meet_now = props(
            serde_json::json!({"threadType": "meeting", "meetingChatPolicy": "ChatEnabled", "lastjoinat": "1795446831604"}),
        );
        let breakout = props(
            serde_json::json!({"threadType": "meeting", "ongoingCallChatEnforcement": "true"}),
        );
        let lobby = props(
            serde_json::json!({"threadType": "meeting", "threadSubType": "LobbyChat", "meetingChatPolicy": "ChatEnabledAnonymousDisabled", "lastjoinat": "1795144247449", "lastleaveat": "1795144349966"}),
        );
        // OST Test 3's room camera meeting: joined, then left.
        let left = props(
            serde_json::json!({"threadType": "meeting", "meetingChatPolicy": "ChatEnabled", "lastjoinat": "1795224007677", "lastleaveat": "1795230311398"}),
        );
        let back = props(
            serde_json::json!({"threadType": "chat", "lastjoinat": "1795230311399", "lastleaveat": "1795230311398"}),
        );
        // An empty group chat and an empty Meet now chat are listed, and so
        // is a chat you were added to (no `interest`) or came back to.
        assert!(!unlisted(&group, true, false));
        assert!(!unlisted(&meet_now, true, false));
        assert!(!unlisted(&group, false, false));
        assert!(!unlisted(&back, false, false));
        // An empty one-on-one, a breakout room, a lobby and a left chat aren't.
        assert!(unlisted(&group, true, true));
        assert!(unlisted(&breakout, false, false));
        assert!(unlisted(&lobby, false, false));
        assert!(unlisted(&left, false, false));
    }
}
