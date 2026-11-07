//! Teams' chat send pipeline (docs/spec/send-pipeline.md):
//! - the optimistic message (Teams' "client lie");
//! - the POST, with its transport retries;
//! - error classification and Teams' failure texts;
//! - the per-conversation offline queue that replays failed sends.

use super::client::TeamsClient;
use super::messages::MessageView;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// An own message's send state (worker 18823 `rI`, as the UI sees it).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SendState {
    Sending,
    Retrying,
    Error,
    Delivered,
}

/// A message being sent: the lie shown in the timeline and its queue entry.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Outgoing {
    /// The conversation, with `;messageid=<post>` for a channel reply.
    pub conversation_id: String,
    pub client_message_id: String,
    /// Teams HTML.
    pub content: String,
    pub display_name: String,
    pub sender_mri: String,
    pub compose_time: String,
    /// The lie's arrival time (epoch ms): `max(now, last message + 1)`.
    pub arrival_ms: i64,
    /// When it was first queued (the 48 h expiry counts from here).
    pub created_ms: i64,
    pub state: SendState,
    /// Teams' sendPipelineStatus (worker 16163 `Df`); drives the texts.
    pub pipeline_status: Option<String>,
    /// numberOfCrossSessionFailures.
    pub failures: u32,
    /// In the offline queue. A manual Retry is sent outside it.
    pub queued: bool,
    pub server_id: Option<String>,
    /// The message this one quotes (its card is already in `content`).
    #[serde(default)]
    pub quote: Option<super::messages::Quote>,
}

/// offlineActionsManagerDefaultCrossSessionRetries.
pub const MAX_CROSS_SESSION_RETRIES: u32 = 10;
/// offlineActionsManagerDefaultActionExpirationInMs (48 h).
pub const ACTION_EXPIRATION_MS: i64 = 172_800_000;
/// offlineActionsSyncStrategyRefreshIntervalInMs.
pub const REPLAY_INTERVAL: Duration = Duration::from_secs(600);
/// maxMessageContentSize: the composer refuses larger HTML (UTF-8 bytes).
pub const MAX_MESSAGE_CONTENT_SIZE: usize = 90_112;
/// The composer's text when content is over the limit.
pub const TOO_LARGE_TO_SEND: &str = "Message is too large to send.";
/// Where "Teams standards" in the spam failure text links (module 92099 `ne`).
pub const TEAMS_STANDARDS_URL: &str = "https://go.microsoft.com/fwlink/?linkid=2186905";

// chatService transport retry settings (prod defaults).
const MAX_RETRY_COUNT: u32 = 4;
const MIN_RETRY_INTERVAL_MS: u64 = 1000;
const EXPONENTIAL_DELAY_FACTOR: u64 = 2;
const MAX_RETRY_TIME_MS: u64 = 300_000;
const MAX_ENDPOINT_FALLBACK_COUNT: u32 = 3;
const MAX_NOT_AUTHORIZED_COUNT: u32 = 1;
/// Delivered lies are kept until the server copy shows, at most this long.
const DELIVERED_KEEP_MS: i64 = 600_000;

/// Teams' clientmessageid (770328 `sN`): two random 32-bit numbers in
/// decimal, joined and cut to 19 characters.
pub fn new_client_message_id() -> String {
    let mut b = [0u8; 8];
    if getrandom::fill(&mut b).is_err() {
        let n = chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0) as u64;
        b = n.to_le_bytes();
    }
    let a = u32::from_le_bytes([b[0], b[1], b[2], b[3]]);
    let c = u32::from_le_bytes([b[4], b[5], b[6], b[7]]);
    format!("{a}{c}").chars().take(19).collect()
}

/// A lie's arrival time: never before the conversation's last message, so
/// it always sorts last.
pub fn lie_arrival(now_ms: i64, last_ms: Option<i64>) -> i64 {
    last_ms.map_or(now_ms, |l| now_ms.max(l + 1))
}

/// Retry counters across one POST's attempts.
#[derive(Debug, Default)]
pub struct Counts {
    endpoint_fallback: u32,
    not_authorized: u32,
}

/// Whether the transport tries again after attempt `attempt` (0-based) got
/// `status` (None: no reply), and after how long (worker 66704 `P`).
pub fn transport_retry(
    attempt: u32,
    status: Option<u16>,
    counts: &mut Counts,
    retry_after_ms: Option<u64>,
) -> Option<Duration> {
    if attempt >= MAX_RETRY_COUNT || retry_after_ms.is_some_and(|r| r > MAX_RETRY_TIME_MS) {
        return None;
    }
    let retry = match status {
        None | Some(429) => true,
        Some(502 | 503) => {
            counts.endpoint_fallback += 1;
            counts.endpoint_fallback <= MAX_ENDPOINT_FALLBACK_COUNT
        }
        Some(401) => {
            counts.not_authorized += 1;
            counts.not_authorized <= MAX_NOT_AUTHORIZED_COUNT
        }
        // Sends carry no If-Match, so 412 is retried.
        Some(412) => true,
        Some(404) => false,
        Some(s) => (500..=599).contains(&s),
    };
    if !retry {
        return None;
    }
    let delay =
        (MIN_RETRY_INTERVAL_MS * EXPONENTIAL_DELAY_FACTOR.pow(attempt)).min(MAX_RETRY_TIME_MS);
    Some(Duration::from_millis(
        delay.max(retry_after_ms.unwrap_or(0)),
    ))
}

/// Whether a failure ends the send or leaves it for a replay.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    Retryable,
    Terminal,
}

/// The inner error code of a chat-service error body
/// (`{"message":"<json>"}` with errorCode / errorSubCode / subCode).
fn sub_code(body: &str) -> Option<String> {
    let outer: serde_json::Value = serde_json::from_str(body).ok()?;
    let inner = match outer.get("message").and_then(|m| m.as_str()) {
        Some(s) => serde_json::from_str(s).unwrap_or(serde_json::Value::Null),
        None => outer.clone(),
    };
    ["subCode", "errorSubCode", "errorCode"]
        .iter()
        .find_map(|k| inner.get(*k).or_else(|| outer.get(*k)))
        .and_then(|v| v.as_str().map(str::to_string))
}

/// How a failed send ends, and its sendPipelineStatus (worker 16163 `E2`,
/// `Df`). `status` is None when no reply came.
pub fn classify(
    status: Option<u16>,
    body: &str,
    content_has_url: bool,
) -> (Failure, Option<String>) {
    let retryable_status = |s: u16| {
        matches!(
            s,
            429 | 401 | 412 | 500 | 502 | 503 | 504 | 507 | 509 | 511 | 599
        )
    };
    let Some(s) = status else {
        return (Failure::Retryable, Some("REJECT_HTTP_ERROR".into()));
    };
    let mut failure = if retryable_status(s) {
        Failure::Retryable
    } else {
        Failure::Terminal
    };
    let pipeline = match s {
        400 => match sub_code(body).as_deref() {
            Some("MessageSizeExceeded") => Some("MessageTooLong"),
            Some("InvalidQuotedMessage") => Some("QUOTED_MESSAGE_VALIDATION_FAILED"),
            Some("TenantExceedMessageLimit") => Some("TENANT_MESSAGE_SEND_LIMIT_EXCEEDED"),
            Some("MoeraOnlyTenantExceedMessageLimit") => {
                Some("MOERA_TENANT_MESSAGE_SEND_LIMIT_EXCEEDED")
            }
            Some("ThreadedChatNotEligibleForConversion") => {
                failure = Failure::Terminal;
                Some("THREADED_CHAT_NOT_ELIGIBLE_FOR_CONVERSION")
            }
            _ => None,
        },
        429 => Some("SERVICE_THROTTLED"),
        455 => Some("THREAD_READ_ONLY"),
        403 if content_has_url || body.contains("QuarantineURLsBlocked") => {
            Some("QUARANTINE_URLS_BLOCKED")
        }
        403 => Some("SPAM_MESSAGE_DETECTED"),
        404 => Some("CONVERSATION_DELETED"),
        s if s >= 500 && retryable_status(s) => Some("SERVICE_ISSUE_GENERIC"),
        _ => None,
    };
    (failure, pipeline.map(str::to_string))
}

/// The failed message's text (533020 `v`, send variant).
pub fn failure_text(pipeline: Option<&str>) -> &'static str {
    match pipeline {
        Some("MessageTooLong") => "Failed to send. Message too large.",
        Some("CONVERSATION_DELETED") => {
            "Message didn't send. Check your connection or try again later."
        }
        Some("TENANT_MESSAGE_SEND_LIMIT_EXCEEDED" | "MOERA_TENANT_MESSAGE_SEND_LIMIT_EXCEEDED") => {
            "Message limit reached"
        }
        Some("SPAM_MESSAGE_DETECTED") => {
            "This message might not meet Teams standards. Edit it, and try again."
        }
        Some("QUARANTINE_URLS_BLOCKED") => {
            "You can't send links in this message until the invite is accepted."
        }
        Some("THREADED_CHAT_NOT_ELIGIBLE_FOR_CONVERSION") => {
            "This chat doesn't support threading yet."
        }
        _ => "Failed to send.",
    }
}

/// The pending icon's tooltip (533020 `u`).
pub fn pending_tooltip(state: SendState, pipeline: Option<&str>) -> &'static str {
    if state == SendState::Sending {
        return "Sending...";
    }
    match pipeline {
        Some("REJECT_HTTP_ERROR") => {
            "Retrying... Message delayed due to connection issues. Please check your network."
        }
        Some("DEPENDENT_OAM_ACTION") => {
            "Waiting for another message action to complete. We'll send this soon."
        }
        Some("SERVICE_THROTTLED") => {
            "Retrying... You've reached the current limit. Please wait a moment."
        }
        Some("SERVICE_ISSUE_GENERIC") => {
            "The service is temporarily unavailable. We'll retry when it's back."
        }
        _ => "Retrying...",
    }
}

/// Whether a failed message offers Retry (318259 `canRetry`).
pub fn can_retry(pipeline: Option<&str>) -> bool {
    !matches!(
        pipeline,
        Some(
            "TENANT_MESSAGE_SEND_LIMIT_EXCEEDED"
                | "MOERA_TENANT_MESSAGE_SEND_LIMIT_EXCEEDED"
                | "THREAD_READ_ONLY"
                | "FILE_UPLOAD_FAILED"
                | "THREADED_CHAT_NOT_ELIGIBLE_FOR_CONVERSION"
        )
    )
}

fn iso(ms: i64) -> String {
    chrono::DateTime::from_timestamp_millis(ms)
        .unwrap_or_default()
        .to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

/// JavaScript's encodeURIComponent, as Teams encodes the conversation in
/// the URL.
fn encode_uri_component(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The POST body: the whole lie, as Teams sends it (§7).
pub fn post_body(o: &Outgoing) -> serde_json::Value {
    let mut body = serde_json::json!({
        "id": "-1",
        "type": "Message",
        "conversationid": o.conversation_id,
        "conversationLink": format!("blah/{}", o.conversation_id),
        "from": o.sender_mri,
        "fromUserId": o.sender_mri,
        "composetime": o.compose_time,
        "originalarrivaltime": iso(o.arrival_ms),
        "content": o.content,
        "messagetype": "RichText/Html",
        "contenttype": "Text",
        "imdisplayname": o.display_name,
        "clientmessageid": o.client_message_id,
        "callId": "",
        "state": 0,
        "version": "0",
        "amsreferences": [],
        "properties": {
            "importance": "",
            "cards": "[]",
            "links": "[]",
            "mentions": "[]",
            "onbehalfof": null,
            "files": "[]",
            "formatVariant": "TEAMS",
        },
    });
    // qtdMsgs goes only with a quote (Teams adds it when quotedMessages is
    // not empty).
    if let Some(q) = &o.quote {
        body["properties"]["qtdMsgs"] = super::messages::quoted_messages_property(q).into();
    }
    body
}

/// One run of the POST, with the transport's retries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PostResult {
    Delivered { id: String, arrival_ms: i64 },
    Failed { status: Option<u16>, body: String },
}

/// The server id from the reply's `Location` (`…/messages/{id}`).
fn location_id(resp: &reqwest::Response) -> Option<String> {
    let loc = resp.headers().get("location")?.to_str().ok()?;
    let id = loc.trim_end_matches('/').rsplit('/').next()?;
    (!id.is_empty()).then(|| id.split('?').next().unwrap_or(id).to_string())
}

/// POST the message, retrying as Teams' transport does.
pub async fn post(o: &Outgoing) -> PostResult {
    let mut client = match TeamsClient::new().await {
        Ok(c) => c,
        Err(_) => {
            return PostResult::Failed {
                status: None,
                body: String::new(),
            };
        }
    };
    let body = post_body(o);
    let mut counts = Counts::default();
    let mut attempt = 0;
    loop {
        let url = format!(
            "{}/v1/users/ME/conversations/{}/messages",
            client.chat_service_url(),
            encode_uri_component(&o.conversation_id)
        );
        let reply = client
            .chat_post_unchecked(&url, &body, &[("x-ms-request-priority", "0")])
            .await;
        let (status, retry_after, text) = match reply {
            Ok(resp) if resp.status().is_success() => {
                let id = location_id(&resp);
                let v: serde_json::Value = resp.json().await.unwrap_or_default();
                let arrival_ms = v
                    .get("OriginalArrivalTime")
                    .and_then(|t| t.as_i64())
                    .unwrap_or(o.arrival_ms);
                return match id {
                    Some(id) => PostResult::Delivered { id, arrival_ms },
                    // No id: Teams' InvalidResponse.
                    None => PostResult::Failed {
                        status: Some(500),
                        body: "InvalidResponse".into(),
                    },
                };
            }
            Ok(resp) => {
                let status = resp.status().as_u16();
                let retry_after = resp
                    .headers()
                    .get("retry-after")
                    .and_then(|h| h.to_str().ok())
                    .and_then(|s| s.trim().parse::<u64>().ok())
                    .map(|s| s * 1000);
                (
                    Some(status),
                    retry_after,
                    resp.text().await.unwrap_or_default(),
                )
            }
            Err(_) => (None, None, String::new()),
        };
        let Some(wait) = transport_retry(attempt, status, &mut counts, retry_after) else {
            return PostResult::Failed { status, body: text };
        };
        tokio::time::sleep(wait).await;
        if status == Some(401) {
            // The token is refreshed before the one retry 401 gets.
            if let Ok(c) = TeamsClient::new().await {
                client = c;
            }
        }
        attempt += 1;
    }
}

/// On a replay, whether the message already arrived (worker 68245 `Ko`):
/// its server id and arrival time.
async fn delivered_copy(o: &Outgoing) -> Option<(String, i64)> {
    let client = TeamsClient::new().await.ok()?;
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages?view=msnp24Equivalent&pageSize=50&startTime=1",
        client.chat_service_url(),
        encode_uri_component(&o.conversation_id)
    );
    let v: serde_json::Value = client.chat_get(&url).await.ok()?.json().await.ok()?;
    v.get("messages")?.as_array()?.iter().find_map(|m| {
        let cmid = m.get("clientmessageid")?.as_str()?;
        let from = m.get("from")?.as_str()?;
        (cmid == o.client_message_id && from.ends_with(&o.sender_mri)).then(|| {
            let id = m.get("id")?.as_str()?.to_string();
            let at = id.parse().unwrap_or(o.arrival_ms);
            Some((id, at))
        })?
    })
}

/// Plain text as Teams sends it: one paragraph, line breaks as `<br>`.
pub fn plain_html(text: &str) -> String {
    format!(
        "<p>{}</p>",
        super::chat::html_escape(text).replace('\n', "<br>")
    )
}

/// Whether HTML contains a link (Teams' URL check for 403s).
fn has_url(html: &str) -> bool {
    html.contains("http://") || html.contains("https://") || html.contains("www.")
}

/// The lie as a timeline item.
pub fn lie_view(o: &Outgoing) -> MessageView {
    let (quote, rest) = super::messages::split_quote(&o.content);
    let html = super::messages::sanitize_html(&rest);
    let (send_state, send_note) = match o.state {
        SendState::Sending | SendState::Retrying => (
            if o.state == SendState::Sending {
                "sending"
            } else {
                "retrying"
            },
            pending_tooltip(o.state, o.pipeline_status.as_deref()),
        ),
        SendState::Error => ("failed", failure_text(o.pipeline_status.as_deref())),
        SendState::Delivered => ("", ""),
    };
    MessageView {
        id: o
            .server_id
            .clone()
            .unwrap_or_else(|| o.client_message_id.clone()),
        client_message_id: o.client_message_id.clone(),
        kind: "message".into(),
        sender: o.display_name.clone(),
        sender_mri: o.sender_mri.clone(),
        time: iso(o.arrival_ms),
        mine: true,
        text: super::strip_html(&rest).trim().to_string(),
        quote,
        html,
        send_state: send_state.into(),
        send_note: send_note.into(),
        can_retry: o.state == SendState::Error && can_retry(o.pipeline_status.as_deref()),
        // A channel reply goes under its post.
        root_id: o
            .conversation_id
            .split_once(";messageid=")
            .map(|(_, post)| post.to_string())
            .unwrap_or_default(),
        ..Default::default()
    }
}

/// Put a conversation's lies into its timeline, in arrival order. Lies the
/// server already has (same clientmessageid) are left out; their ids are
/// returned so the outbox can drop them.
pub fn merge_lies(timeline: &mut Vec<MessageView>, lies: &[Outgoing]) -> Vec<String> {
    let on_server: HashSet<String> = timeline
        .iter()
        .filter(|m| m.mine && !m.client_message_id.is_empty())
        .map(|m| m.client_message_id.clone())
        .collect();
    let mut arrived = Vec::new();
    for o in lies {
        if on_server.contains(&o.client_message_id) {
            arrived.push(o.client_message_id.clone());
            continue;
        }
        let at = o
            .server_id
            .as_deref()
            .and_then(|i| i.parse::<i64>().ok())
            .unwrap_or(o.arrival_ms);
        let pos = timeline
            .iter()
            .position(|m| m.id.parse::<i64>().is_ok_and(|id| id > at))
            .unwrap_or(timeline.len());
        timeline.insert(pos, lie_view(o));
    }
    arrived
}

/// Teams' offline action queue for sends, persisted to a file: a FIFO per
/// conversation, replayed at startup, on reconnect and every 10 minutes.
pub struct Outbox {
    entries: Mutex<Vec<Outgoing>>,
    path: Option<PathBuf>,
    running: Mutex<HashSet<String>>,
    changed: tokio::sync::watch::Sender<u64>,
}

fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

impl Outbox {
    /// Open the outbox stored at `path` (None: memory only). Messages that
    /// were in flight when OST stopped are replayed like Retrying ones.
    pub fn open(path: Option<PathBuf>) -> Arc<Self> {
        let mut entries: Vec<Outgoing> = path
            .as_ref()
            .and_then(|p| std::fs::read(p).ok())
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        let now = now_ms();
        entries.retain(|o| {
            !(o.state == SendState::Delivered && now - o.arrival_ms > DELIVERED_KEEP_MS)
        });
        Arc::new(Self {
            entries: Mutex::new(entries),
            path,
            running: Mutex::new(HashSet::new()),
            changed: tokio::sync::watch::channel(0).0,
        })
    }

    /// Bumped on every change (watch it to redraw the timeline).
    pub fn changes(&self) -> tokio::sync::watch::Receiver<u64> {
        self.changed.subscribe()
    }

    fn save_and_notify(&self) {
        if let Some(p) = &self.path {
            let entries = self.entries.lock().unwrap().clone();
            let write = || -> Result<()> {
                if let Some(dir) = p.parent() {
                    std::fs::create_dir_all(dir)?;
                }
                let tmp = p.with_extension("tmp");
                std::fs::write(&tmp, serde_json::to_vec(&entries)?)?;
                std::fs::rename(&tmp, p).context("outbox rename")
            };
            if let Err(e) = write() {
                tracing::warn!("outbox not saved: {e:#}");
            }
        }
        self.changed.send_modify(|n| *n += 1);
    }

    /// A conversation's lies, oldest first.
    pub fn for_conversation(&self, conversation_id: &str) -> Vec<Outgoing> {
        let mut v: Vec<Outgoing> = self
            .entries
            .lock()
            .unwrap()
            .iter()
            .filter(|o| {
                o.conversation_id == conversation_id
                    || o.conversation_id
                        .starts_with(&format!("{conversation_id};"))
            })
            .cloned()
            .collect();
        v.sort_by_key(|o| o.arrival_ms);
        v
    }

    fn update(&self, cmid: &str, f: impl FnOnce(&mut Outgoing)) {
        if let Some(o) = self
            .entries
            .lock()
            .unwrap()
            .iter_mut()
            .find(|o| o.client_message_id == cmid)
        {
            f(o);
        }
    }

    /// Send a new message: it shows at once (Sending) and is queued.
    pub fn submit(self: &Arc<Self>, o: Outgoing) {
        let conv = o.conversation_id.clone();
        self.entries.lock().unwrap().push(o);
        self.save_and_notify();
        self.run(conv);
    }

    /// Replay every conversation's queue (startup, reconnect, interval).
    pub fn replay(self: &Arc<Self>) {
        let convs: HashSet<String> = self
            .entries
            .lock()
            .unwrap()
            .iter()
            .filter(|o| o.queued && matches!(o.state, SendState::Sending | SendState::Retrying))
            .map(|o| o.conversation_id.clone())
            .collect();
        for c in convs {
            self.run(c);
        }
    }

    /// Retry a failed message (318259 `Ug`): same clientmessageid, arrival
    /// raised to last + 1, sent outside the offline queue.
    pub fn retry(self: &Arc<Self>, cmid: &str, last_ms: Option<i64>) {
        let mut found = None;
        self.update(cmid, |o| {
            if o.state == SendState::Error {
                o.state = SendState::Sending;
                o.pipeline_status = None;
                o.queued = false;
                o.arrival_ms = lie_arrival(now_ms(), last_ms);
                found = Some(o.clone());
            }
        });
        let Some(o) = found else { return };
        self.save_and_notify();
        let me = Arc::clone(self);
        tokio::spawn(async move {
            let result = post(&o).await;
            me.settle(&o, result, false, false);
        });
    }

    /// Delete a failed message: local only (Teams makes no network call).
    pub fn delete(&self, cmid: &str) {
        self.entries
            .lock()
            .unwrap()
            .retain(|o| !(o.client_message_id == cmid && o.state != SendState::Delivered));
        self.save_and_notify();
    }

    /// The server copies of these messages are in the timeline: drop them.
    pub fn arrived(&self, cmids: &[String]) {
        if cmids.is_empty() {
            return;
        }
        let before = self.entries.lock().unwrap().len();
        self.entries
            .lock()
            .unwrap()
            .retain(|o| !cmids.contains(&o.client_message_id));
        if self.entries.lock().unwrap().len() != before {
            self.save_and_notify();
        }
    }

    /// Record a run's outcome. Returns whether the queue may go on.
    fn settle(&self, o: &Outgoing, result: PostResult, final_retry: bool, expired: bool) -> bool {
        match result {
            PostResult::Delivered { id, arrival_ms } => {
                self.update(&o.client_message_id, |e| {
                    e.state = SendState::Delivered;
                    e.server_id = Some(id);
                    e.arrival_ms = arrival_ms;
                    e.queued = false;
                    e.pipeline_status = None;
                });
                self.save_and_notify();
                true
            }
            PostResult::Failed { status, body } => {
                let (failure, pipeline) = classify(status, &body, has_url(&o.content));
                tracing::info!(
                    ?status,
                    ?pipeline,
                    terminal = failure == Failure::Terminal,
                    "message send failed"
                );
                self.update(&o.client_message_id, |e| {
                    e.failures += 1;
                    e.pipeline_status = pipeline;
                    if failure == Failure::Terminal || final_retry {
                        e.state = SendState::Error;
                        e.queued = false;
                    } else {
                        e.state = SendState::Retrying;
                        // An expired action is not replayed again.
                        if expired {
                            e.queued = false;
                        }
                    }
                });
                self.save_and_notify();
                failure == Failure::Terminal || final_retry
            }
        }
    }

    /// Run a conversation's queue head-first until it empties or a
    /// message must wait for a replay.
    fn run(self: &Arc<Self>, conv: String) {
        if !self.running.lock().unwrap().insert(conv.clone()) {
            return;
        }
        let me = Arc::clone(self);
        tokio::spawn(async move {
            loop {
                let head = me
                    .entries
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|o| {
                        o.conversation_id == conv
                            && o.queued
                            && matches!(o.state, SendState::Sending | SendState::Retrying)
                    })
                    .min_by_key(|o| o.arrival_ms)
                    .cloned();
                let Some(head) = head else { break };
                if head.failures > MAX_CROSS_SESSION_RETRIES {
                    me.update(&head.client_message_id, |e| e.queued = false);
                    me.save_and_notify();
                    continue;
                }
                let final_retry = head.failures == MAX_CROSS_SESSION_RETRIES;
                let expired = now_ms() - head.created_ms > ACTION_EXPIRATION_MS;
                me.update(&head.client_message_id, |e| e.state = SendState::Sending);
                me.save_and_notify();
                // A replay first checks whether the message already arrived.
                let copy = if head.failures > 0 {
                    delivered_copy(&head).await
                } else {
                    None
                };
                let result = match copy {
                    Some((id, arrival_ms)) => PostResult::Delivered { id, arrival_ms },
                    None => post(&head).await,
                };
                let delivered = matches!(result, PostResult::Delivered { .. });
                let go_on = me.settle(&head, result, final_retry, expired);
                if !delivered && !go_on {
                    break;
                }
            }
            me.running.lock().unwrap().remove(&conv);
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_message_ids_are_teams_shape() {
        for _ in 0..50 {
            let id = new_client_message_id();
            assert!(id.len() <= 19 && id.len() >= 2, "{id}");
            assert!(id.bytes().all(|b| b.is_ascii_digit()), "{id}");
        }
    }

    #[test]
    fn lies_sort_last() {
        assert_eq!(lie_arrival(1000, None), 1000);
        assert_eq!(lie_arrival(1000, Some(5000)), 5001);
        assert_eq!(lie_arrival(9000, Some(5000)), 9000);
    }

    #[test]
    fn transport_retries_as_teams() {
        let mut c = Counts::default();
        let d: Vec<u64> = (0..5)
            .map(|a| {
                transport_retry(a, None, &mut c, None)
                    .map(|d| d.as_millis() as u64)
                    .unwrap_or(0)
            })
            .collect();
        assert_eq!(d, vec![1000, 2000, 4000, 8000, 0]);
        let mut c = Counts::default();
        assert!(transport_retry(0, Some(404), &mut c, None).is_none());
        assert!(transport_retry(0, Some(413), &mut c, None).is_none());
        assert!(transport_retry(0, Some(500), &mut c, None).is_some());
        assert_eq!(
            transport_retry(0, Some(429), &mut c, Some(5000)),
            Some(Duration::from_millis(5000))
        );
        assert!(transport_retry(0, Some(429), &mut c, Some(400_000)).is_none());
        let mut c = Counts::default();
        assert!(transport_retry(0, Some(401), &mut c, None).is_some());
        assert!(transport_retry(1, Some(401), &mut c, None).is_none());
        let mut c = Counts::default();
        assert!((0..3).all(|a| transport_retry(a, Some(503), &mut c, None).is_some()));
        assert!(transport_retry(3, Some(502), &mut c, None).is_none());
    }

    #[test]
    fn failures_read_as_teams_words_them() {
        let big = r#"{"message":"{\"subCode\":\"MessageSizeExceeded\"}"}"#;
        let (f, p) = classify(Some(400), big, false);
        assert_eq!(
            (f, failure_text(p.as_deref())),
            (Failure::Terminal, "Failed to send. Message too large.")
        );
        let (f, p) = classify(Some(413), "", false);
        assert_eq!(
            (f, failure_text(p.as_deref())),
            (Failure::Terminal, "Failed to send.")
        );
        let (f, p) = classify(Some(404), "", false);
        assert_eq!(
            (f, failure_text(p.as_deref())),
            (
                Failure::Terminal,
                "Message didn't send. Check your connection or try again later."
            )
        );
        let (f, p) = classify(None, "", false);
        assert_eq!(f, Failure::Retryable);
        assert_eq!(
            pending_tooltip(SendState::Retrying, p.as_deref()),
            "Retrying... Message delayed due to connection issues. Please check your network."
        );
        let (f, p) = classify(Some(503), "", false);
        assert_eq!(
            (f, p.as_deref()),
            (Failure::Retryable, Some("SERVICE_ISSUE_GENERIC"))
        );
        let (_, p) = classify(Some(403), "", true);
        assert_eq!(p.as_deref(), Some("QUARANTINE_URLS_BLOCKED"));
        let (_, p) = classify(Some(455), "", false);
        assert!(!can_retry(p.as_deref()));
    }

    #[test]
    fn the_post_body_is_teams_lie() {
        let o = Outgoing {
            conversation_id: "19:a_b@unq.gbl.spaces".into(),
            client_message_id: "123".into(),
            content: "<p>hi</p>".into(),
            display_name: "Me".into(),
            sender_mri: "8:orgid:x".into(),
            compose_time: "2026-01-01T00:00:00.000Z".into(),
            arrival_ms: 1_767_225_600_000,
            created_ms: 0,
            state: SendState::Sending,
            pipeline_status: None,
            failures: 0,
            queued: true,
            server_id: None,
            quote: None,
        };
        let b = post_body(&o);
        assert_eq!(b["id"], "-1");
        assert_eq!(b["state"], 0);
        assert_eq!(b["contenttype"], "Text");
        assert_eq!(b["conversationLink"], "blah/19:a_b@unq.gbl.spaces");
        assert_eq!(b["originalarrivaltime"], "2026-01-01T00:00:00.000Z");
        assert_eq!(b["properties"]["formatVariant"], "TEAMS");
        assert!(b["properties"].get("qtdMsgs").is_none());
        assert_eq!(
            encode_uri_component("19:a@thread.v2;messageid=1"),
            "19%3Aa%40thread.v2%3Bmessageid%3D1"
        );

        let mut timeline = vec![MessageView {
            id: "100".into(),
            mine: false,
            ..Default::default()
        }];
        let arrived = merge_lies(&mut timeline, std::slice::from_ref(&o));
        assert!(arrived.is_empty());
        assert_eq!(timeline.last().unwrap().send_state, "sending");
        let mut with_copy = vec![MessageView {
            id: "200".into(),
            mine: true,
            client_message_id: "123".into(),
            ..Default::default()
        }];
        assert_eq!(merge_lies(&mut with_copy, &[o]), vec!["123".to_string()]);
        assert_eq!(with_copy.len(), 1);
    }
}
