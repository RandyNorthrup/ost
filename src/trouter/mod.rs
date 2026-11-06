//! Trouter v4 WebSocket push notification client
//!
//! Connects to Microsoft Teams' Trouter service to receive real-time
//! push notifications (messages, presence, calls, etc.).

pub mod registrar;
pub mod session;
pub mod websocket;

use anyhow::{Context, Result};
use std::time::{Duration, Instant};
use tokio::time;

use crate::auth::tokens::TokenStore;
use crate::calling;
use crate::config::Config;

/// How a Trouter session behaves for its host.
#[derive(Debug, Clone, Copy)]
pub struct ListenOptions {
    /// Print frames and status to stdout (the CLI's `trouter` command).
    pub console: bool,
    /// Answer incoming calls automatically (the CLI's echo-test mode).
    /// Embedders that show an incoming-call UI leave this off.
    pub auto_answer: bool,
}

impl ListenOptions {
    /// The CLI: print everything, auto-answer calls.
    pub const CLI: Self = Self {
        console: true,
        auto_answer: true,
    };
    /// A library host: quiet, events only via [`crate::event_hub`].
    pub const EMBEDDED: Self = Self {
        console: false,
        auto_answer: false,
    };
}

/// The live Trouter endpoint: (`surl`, `epid`). Call signalling needs it to
/// build callback URLs that reach this socket.
static CURRENT_ENDPOINT: std::sync::Mutex<Option<(String, String)>> = std::sync::Mutex::new(None);

/// The connected Trouter endpoint, if any: (`surl`, `epid`).
pub fn current_endpoint() -> Option<(String, String)> {
    CURRENT_ENDPOINT
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
}

/// Reason the inner connection loop exited.
enum DisconnectReason {
    /// Clean shutdown (Ctrl+C). Do not reconnect.
    Shutdown,
    /// Error or server-initiated close. Should reconnect.
    Error(anyhow::Error),
}

/// Run the Trouter connection with automatic reconnection.
///
/// On transient errors or server-initiated disconnects, reconnects with
/// exponential backoff (1s, 2s, 4s, ... capped at 64s). On clean shutdown
/// (Ctrl+C), exits immediately.
pub async fn connect_and_run() -> Result<()> {
    listen(ListenOptions::CLI, || async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await
}

/// Run Trouter until `shutdown()` resolves, reconnecting with backoff.
/// Every chat and call event is published to [`crate::event_hub`].
/// `shutdown` is called once per wait, so it must build a fresh future.
pub async fn listen<S, F>(opts: ListenOptions, shutdown: S) -> Result<()>
where
    S: Fn() -> F,
    F: std::future::Future<Output = ()>,
{
    let mut backoff = 1u64;

    loop {
        match connect_and_run_inner(opts, &shutdown).await {
            Ok(DisconnectReason::Shutdown) => {
                return Ok(());
            }
            Ok(DisconnectReason::Error(e)) => {
                // Connection was stable (>60s), reset backoff before reconnecting.
                backoff = 1;
                tracing::warn!(
                    "Trouter disconnected after stable session: {:#}. Reconnecting in 1s...",
                    e,
                );

                tokio::select! {
                    _ = time::sleep(Duration::from_secs(1)) => {}
                    _ = shutdown() => {
                        if opts.console { println!("Shutting down..."); }
                        return Ok(());
                    }
                }
            }
            Err(e) => {
                tracing::warn!(
                    "Trouter disconnected: {:#}. Reconnecting in {}s...",
                    e,
                    backoff
                );

                tokio::select! {
                    _ = time::sleep(Duration::from_secs(backoff)) => {}
                    _ = shutdown() => {
                        if opts.console { println!("Shutting down..."); }
                        return Ok(());
                    }
                }

                backoff = (backoff * 2).min(64);
            }
        }
    }
}

/// Run one full Trouter session: negotiate, connect, event loop.
///
/// Returns `DisconnectReason::Shutdown` on clean Ctrl+C, or
/// `DisconnectReason::Error` when the connection should be retried.
async fn connect_and_run_inner<S, F>(opts: ListenOptions, shutdown: &S) -> Result<DisconnectReason>
where
    S: Fn() -> F,
    F: std::future::Future<Output = ()>,
{
    // Reload config each attempt so we pick up refreshed tokens; renew them
    // first if the Skype token has lapsed (long-running hosts outlive it).
    let mut config = Config::load().context("Failed to load config")?;
    if config.get_skype_token().is_some_and(|t| t.is_expired())
        && config.get_refresh_token().is_some()
    {
        tracing::info!("Skype token expired; refreshing before reconnecting");
        crate::auth::oauth::refresh()
            .await
            .context("Token refresh failed")?;
        config = Config::load().context("Failed to load config")?;
    }

    let skype_token = config
        .get_skype_token()
        .context("No skype token found. Run `teams-cli login` first.")?;
    anyhow::ensure!(
        !skype_token.is_expired(),
        "Skype token expired. Run `teams-cli login` to refresh."
    );

    let skype_token_str = &skype_token.token;
    let http = reqwest::Client::new();

    // 1. Negotiate session (returns session info + epid)
    let (session, epid) = session::negotiate(&http, skype_token_str).await?;
    *CURRENT_ENDPOINT.lock().unwrap_or_else(|e| e.into_inner()) =
        Some((session.surl.clone(), epid.clone()));

    // 2. Get socket.io session ID (authenticated via X-Skypetoken header)
    let session_id = session::get_session_id(&session, skype_token_str, &epid).await?;

    // 3. Connect WebSocket (auth is via session ID in URL, no headers needed)
    let mut ws = websocket::TrouterSocket::connect(&session, &session_id, &epid).await?;

    // 4. Wait for handshake frame (1::)
    let frame = ws
        .recv_frame()
        .await?
        .context("Connection closed before handshake")?;

    if !frame.starts_with("1::") {
        tracing::warn!("Expected 1:: handshake, got: {}", frame);
    } else {
        tracing::info!("Received handshake frame");
    }

    // 5. Register with registrar
    let registrar_ttl_secs: u64 = 86400;
    if let Some(ref reg_url) = session.registrar_url
        && let Err(e) = registrar::register_with_endpoint(
            &http,
            skype_token_str,
            reg_url,
            &session.surl,
            Some(&epid),
        )
        .await
    {
        tracing::warn!("Initial registrar registration failed: {:#}", e);
    }
    // Publish the endpoint to the presence service: users with no active
    // endpoint show as Offline and are never rung.
    if let Err(e) = crate::api::presence::publish_endpoint(&http, &epid).await {
        tracing::warn!("Presence endpoint publish failed: {:#}", e);
    }
    // Mark the endpoint active, as Teams clients do right after the
    // handshake; chat pushes only flow to active endpoints. (eisbaw/ost#88)
    let activity = serde_json::json!({
        "name": "user.activity",
        "args": [{"state": "active", "cv": format!("{}.0.1", uuid::Uuid::new_v4().simple())}],
    });
    if let Err(e) = ws.send_text(&format!("5:1+::{}", activity)).await {
        tracing::warn!("user.activity send failed: {:#}", e);
    }

    // 6. Event loop: recv frames, send heartbeat, re-register before TTL,
    //    force reconnect after session max age.
    let connected_at = Instant::now();
    let mut heartbeat = time::interval(Duration::from_secs(30));
    // The presence service drops endpoints that stop reporting within a
    // few minutes; republish well inside that window.
    let mut presence_tick = time::interval(Duration::from_secs(120));
    presence_tick.tick().await; // first publish happened above
    heartbeat.tick().await; // skip first immediate tick

    // Re-register 30s before TTL expires.
    let re_register_interval = Duration::from_secs(registrar_ttl_secs.saturating_sub(30));
    let mut re_register_deadline = Box::pin(time::sleep(re_register_interval));

    // Force full reconnect after 1 hour to refresh the session.
    // The session TTL is typically ~589000s but rotating more frequently
    // keeps tokens and registrations fresh.
    let session_max_age = Duration::from_secs(3600);
    let mut session_deadline = Box::pin(time::sleep(session_max_age));

    // Stability threshold: reset backoff after 60s of successful connection.
    // We communicate this via the return value — the caller checks timing.
    let stability_threshold = Duration::from_secs(60);

    if opts.console {
        println!("Trouter connected. Listening for events... (Ctrl-C to stop)");
    } else {
        tracing::info!("Trouter connected");
    }

    let mut cdl_reregistered = false;
    let disconnect_reason = loop {
        tokio::select! {
            frame = ws.recv_frame() => {
                match frame {
                    Ok(Some(text)) => {
                        // On the first message_loss after connect, re-register
                        // the chat (CDL) entry with the 1.9 template, as the
                        // Teams clients do. (eisbaw/ost#88)
                        if !cdl_reregistered && text.contains("trouter.message_loss") {
                            cdl_reregistered = true;
                            if let Some(ref reg_url) = session.registrar_url {
                                let (h, tok, reg, surl, ep) = (
                                    http.clone(),
                                    skype_token_str.to_string(),
                                    reg_url.clone(),
                                    session.surl.clone(),
                                    epid.clone(),
                                );
                                tokio::spawn(async move {
                                    if let Err(e) = registrar::register_cdl(
                                        &h, &tok, &reg, &surl, &ep, "TeamsCDLWebWorker_1.9",
                                    )
                                    .await
                                    {
                                        tracing::warn!("CDL re-registration failed: {:#}", e);
                                    }
                                });
                            }
                        }
                        handle_frame(&text, &http, skype_token_str, opts).await
                    }
                    Ok(None) => {
                        break DisconnectReason::Error(anyhow::anyhow!("WebSocket closed by server"));
                    }
                    Err(e) => {
                        break DisconnectReason::Error(e.context("WebSocket recv error"));
                    }
                }
            }
            _ = presence_tick.tick() => {
                let (h, ep) = (http.clone(), epid.clone());
                tokio::spawn(async move {
                    if let Err(e) = crate::api::presence::publish_endpoint(&h, &ep).await {
                        tracing::warn!("Presence refresh failed: {:#}", e);
                    }
                });
            }
            _ = heartbeat.tick() => {
                if let Err(e) = ws.send_text("2::").await {
                    break DisconnectReason::Error(e.context("Heartbeat send failed"));
                }
            }
            _ = &mut re_register_deadline => {
                tracing::info!("Re-registering with registrar (TTL refresh)");
                if let Some(ref reg_url) = session.registrar_url {
                    let http2 = http.clone();
                    let tok = skype_token_str.to_string();
                    let surl = session.surl.clone();
                    let reg = reg_url.clone();
                    let ep = epid.clone();
                    tokio::spawn(async move {
                        if let Err(e) = registrar::register_with_endpoint(&http2, &tok, &reg, &surl, Some(&ep)).await {
                            tracing::warn!("Re-registration failed: {:#}", e);
                        }
                    });
                }
                // Reset the timer for another cycle.
                re_register_deadline = Box::pin(time::sleep(re_register_interval));
            }
            _ = &mut session_deadline => {
                tracing::info!("Session max age reached (1h), forcing reconnect for fresh session");
                break DisconnectReason::Error(anyhow::anyhow!("Session max age reached"));
            }
            _ = shutdown() => {
                if opts.console { println!("Shutting down..."); }
                break DisconnectReason::Shutdown;
            }
        }
    };

    // If we were connected long enough, signal stability so caller resets backoff.
    // We do this by returning Ok (the caller pattern-matches on it).
    if connected_at.elapsed() >= stability_threshold {
        // Reset backoff indirectly: caller sees Ok and resets.
        // But we still need to convey the reason.
        // Use Ok for both shutdown and stable-error cases.
        return Ok(disconnect_reason);
    }

    match disconnect_reason {
        DisconnectReason::Shutdown => Ok(DisconnectReason::Shutdown),
        DisconnectReason::Error(e) => Err(e),
    }
}

/// Developer aid: with `OST_TROUTER_DUMP_DIR` set, every frame is written
/// there (one file each, owner-only). Frames carry message text and call
/// links, so this is for local protocol work only and is off by default.
fn dump_frame(frame: &str) {
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    let Some(dir) = std::env::var_os("OST_TROUTER_DUMP_DIR") else {
        return;
    };
    let n = N.fetch_add(1, Ordering::Relaxed);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let path = std::path::Path::new(&dir).join(format!("{ts}-{n:05}.txt"));
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    if let Ok(mut f) = opts.open(path) {
        use std::io::Write;
        let _ = f.write_all(frame.as_bytes());
    }
}

/// Handle an incoming socket.io frame.
async fn handle_frame(frame: &str, http: &reqwest::Client, skype_token: &str, opts: ListenOptions) {
    use crate::event_hub::{EventKind, publish};
    // Stdout output belongs to the CLI only.
    macro_rules! say {
        ($($t:tt)*) => { if opts.console { println!($($t)*); } };
    }
    dump_frame(frame);
    // socket.io framing:
    // 1:: — handshake (handled above)
    // 2:: — heartbeat ping (server)
    // 3::: — ephemeral message
    // 5:X::{json} — event
    // 6:X+::{json} — ack event

    if frame.starts_with("2::") {
        tracing::debug!("Heartbeat ping from server");
        return;
    }

    if frame.starts_with("5:::") || frame.starts_with("5:") {
        // Socket.IO v1 event frame: 5:ACK_ID:ENDPOINT:JSON
        // Ack (6:ID::) is sent automatically by recv_frame() in websocket.rs.
        // Here we just extract the JSON payload after the `::` separator.
        let after_5 = &frame[2..]; // skip "5:"
        let json_str = after_5
            .find("::")
            .map(|pos| &after_5[pos + 2..])
            .filter(|s| s.starts_with('{'));

        if let Some(json_str) = json_str {
            let is_call = frame.contains("NGCallManagerWin");
            let prefix = if is_call {
                "[CALL]"
            } else if frame.contains("SkypeSpacesWeb") {
                "[CALL-INFO]"
            } else {
                "[MSG]"
            };
            say!("{} Event: {}", prefix, json_str);

            if is_call {
                let body = unwrap_call_payload(json_str);
                publish(EventKind::Call, body.clone());
                if opts.auto_answer {
                    handle_call_event(&body, http, skype_token).await;
                }
            } else if let Some(ev) = chat_event_json(json_str) {
                publish(EventKind::Chat, ev);
            }
        } else {
            say!("Frame: {}", frame);
        }
        return;
    }

    if frame.starts_with("6:") {
        if let Some(json_start) = frame.find(":::{") {
            let json_str = &frame[json_start + 3..];
            say!("Ack: {}", json_str);
        } else {
            say!("Ack frame: {}", frame);
        }
        return;
    }

    // Chat-service pushes arrive as HTTP-over-WebSocket data frames.
    if let Some(payload) = frame.strip_prefix("3:::") {
        if let Some(body) = data_frame_call(payload).map(|b| unwrap_call_payload(&b)) {
            say!("[CALL] Event: {}", body);
            publish(EventKind::Call, body.clone());
            if opts.auto_answer {
                handle_call_event(&body, http, skype_token).await;
            }
            return;
        }
        if let Some(ev) = data_frame_event(payload) {
            say!("[CHAT] Event: {}", ev);
            publish(EventKind::Chat, ev);
            return;
        }
    }

    if let Some(payload) = frame.strip_prefix("3:::") {
        // Unrecognised push: log only where it was sent, never its body.
        if let Some((url, _)) = data_frame_body(payload) {
            tracing::info!(%url, "unhandled data frame");
        }
    }
    say!("Frame: {}", frame);
}

/// Decode one Trouter `3:::` data frame payload
/// (`{id, method, url, headers, body}`) into the pushed chat-service
/// event JSON. Only chat-service events (`resourceType` / `resource` /
/// `eventMessages`) are returned; anything else is None.
pub fn data_frame_event(payload: &str) -> Option<String> {
    let (_, body) = data_frame_body(payload)?;
    chat_event_json(&body)
}

/// Decode a `3:::` data frame carrying call signalling (an invitation or
/// another call-controller callback) into its JSON body.
pub fn data_frame_call(payload: &str) -> Option<String> {
    let (url, body) = data_frame_body(payload)?;
    // Callbacks we registered for a call (`…/callAgent/<ep>/<id>/call/end/`
    // and friends) carry call-state changes; tag them with their path.
    if let Some(i) = url.find("/callAgent/") {
        let path = url[i + "/callAgent/".len()..]
            .splitn(3, '/')
            .nth(2)
            .unwrap_or_default()
            .to_string();
        let body: serde_json::Value =
            serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
        return Some(serde_json::json!({ "callAgentPath": path, "body": body }).to_string());
    }
    let is_call = url.contains("NGCallManagerWin") || body.contains("\"callInvitation\"");
    is_call.then_some(body)
}

/// Call-controller events wrap the notification as `{callId, callerId,
/// evt, cp}` with `cp` = base64 + gzip JSON (or `gp` = base64 JSON).
/// Return the inner notification, or the input unchanged.
pub fn unwrap_call_payload(json: &str) -> String {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return json.to_string();
    };
    if let Some(cp) = v.get("cp").and_then(|c| c.as_str())
        && let Some(inner) = gunzip_base64(cp)
    {
        return inner;
    }
    if let Some(gp) = v.get("gp").and_then(|c| c.as_str()) {
        use base64::Engine;
        if let Some(inner) = base64::engine::general_purpose::STANDARD
            .decode(gp.trim())
            .ok()
            .and_then(|raw| String::from_utf8(raw).ok())
        {
            return inner;
        }
    }
    json.to_string()
}

/// The body the Teams client returns in its Trouter reply to a pushed
/// call acceptance (its "synchronous Trouter response"). The Call
/// Controller waits for this acknowledgement in the reply itself and ends
/// the call with 408/10056 after 30 s without it, even when the same
/// acknowledgement is also POSTed to the acceptance's link.
pub(crate) fn sync_reply_body(frame: &str) -> Option<String> {
    let payload = frame.strip_prefix("3:::")?;
    let (url, body) = data_frame_body(payload)?;
    if !url.trim_end_matches('/').ends_with("call/acceptance") {
        return None;
    }
    let v: serde_json::Value = serde_json::from_str(&body).ok()?;
    v.get("callAcceptance")?;
    let endpoint_id = url.split("/callAgent/").nth(1)?.split('/').next()?;
    let (surl, _) = current_endpoint()?;
    Some(acceptance_ack_body(&surl, endpoint_id).to_string())
}

/// `callAcceptanceAcknowledgement` with the links Teams sends back.
pub(crate) fn acceptance_ack_body(surl: &str, endpoint_id: &str) -> serde_json::Value {
    let tc = |path: &str| crate::calling::signaling::trouter_callback(surl, endpoint_id, path);
    serde_json::json!({
        "callAcceptanceAcknowledgement": {
            "links": {
                "mediaRenegotiation": tc("call/mediaRenegotiation/"),
                "transfer": tc("call/transfer/"),
                "replacement": tc("call/replacement/"),
                "balanceUpdate": tc("call/balanceUpdate/"),
                "retargetCompletion": tc("call/retargetCompletion/"),
                "controlVideoStreaming": tc("call/controlVideoStreaming/"),
                "updateMediaDescriptions": tc("call/updateMediaDescriptions")
            }
        }
    })
}

/// The request URL and decoded body text of a `3:::` data frame. `body`
/// sits top-level or under `data` depending on the Trouter version; it is
/// an object, plain JSON text, or base64 + gzip
/// (`X-Microsoft-Skype-Content-Encoding: gzip`, also tried when the plain
/// body isn't JSON).
fn data_frame_body(payload: &str) -> Option<(String, String)> {
    let v: serde_json::Value = serde_json::from_str(payload).ok()?;
    let obj = v.as_object()?;
    let field = |m: &serde_json::Map<String, serde_json::Value>, name: &str| {
        m.iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.clone())
    };
    let data = field(obj, "data").and_then(|d| d.as_object().cloned());
    let body_val = field(obj, "body").or_else(|| data.as_ref().and_then(|d| field(d, "body")))?;
    let url = field(obj, "url")
        .or_else(|| data.as_ref().and_then(|d| field(d, "url")))
        .and_then(|u| u.as_str().map(str::to_string))
        .unwrap_or_default();
    if body_val.is_object() {
        return Some((url, body_val.to_string()));
    }
    let body = body_val.as_str()?;
    let gzip_header = field(obj, "headers")
        .and_then(|h| h.as_object().cloned())
        .is_some_and(|h| {
            h.iter().any(|(k, v)| {
                k.eq_ignore_ascii_case("X-Microsoft-Skype-Content-Encoding")
                    && v.as_str()
                        .is_some_and(|s| s.to_ascii_lowercase().contains("gzip"))
            })
        });
    let plain = (!gzip_header && serde_json::from_str::<serde_json::Value>(body).is_ok())
        .then(|| body.to_string());
    let text = plain.or_else(|| gunzip_base64(body))?;
    Some((url, text))
}

fn chat_event_json(text: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(text).ok()?;
    // Wrapped payloads (as the Teams clients unwrap them): `cp` = base64 +
    // gzip JSON, `gp` = base64 JSON.
    if let Some(cp) = v.get("cp").and_then(|c| c.as_str()) {
        return gunzip_base64(cp).and_then(|t| chat_event_json(&t));
    }
    if let Some(gp) = v.get("gp").and_then(|c| c.as_str()) {
        use base64::Engine;
        let raw = base64::engine::general_purpose::STANDARD
            .decode(gp.trim())
            .ok()?;
        return chat_event_json(&String::from_utf8(raw).ok()?);
    }
    let is_chat = v.as_object()?.keys().any(|k| {
        k.eq_ignore_ascii_case("resourceType")
            || k.eq_ignore_ascii_case("resource")
            || k.eq_ignore_ascii_case("eventMessages")
    });
    is_chat.then(|| text.to_string())
}

fn gunzip_base64(body: &str) -> Option<String> {
    use base64::Engine;
    use std::io::Read;
    let raw = base64::engine::general_purpose::STANDARD
        .decode(body.trim())
        .ok()?;
    let mut out = String::new();
    flate2::read::GzDecoder::new(&raw[..])
        .read_to_string(&mut out)
        .ok()?;
    Some(out)
}

/// Handle a call event from Trouter: print the invitation and auto-answer
/// (the CLI's test mode). The call stays up, logging media statistics,
/// until the process exits.
async fn handle_call_event(json_str: &str, http: &reqwest::Client, skype_token: &str) {
    let Some(call) = calling::incoming::IncomingCall::parse(json_str) else {
        tracing::debug!("Call event is not an invitation");
        return;
    };
    println!(
        "  Incoming call from: {} ({})",
        call.caller_name(),
        call.caller_id().as_deref().unwrap_or("?")
    );
    if let Some(id) = call.call_id() {
        println!("  Call ID: {}", id);
    }
    let video = call.has_video();
    println!("  Auto-answering call (video: {video})...");
    match calling::incoming::answer(http, skype_token, call, video, true).await {
        Ok(active) => {
            tokio::spawn(async move {
                loop {
                    tokio::time::sleep(Duration::from_secs(5)).await;
                    if let Some(s) = active.audio_stats().await {
                        tracing::info!(
                            "Audio stats: sent={}, recv={} ({} bytes)",
                            s.packets_sent,
                            s.packets_received,
                            s.bytes_received
                        );
                    }
                    if let Some(v) = active.video_stats().await {
                        tracing::info!(
                            "Video stats: sent={} pkts/{} frames, recv={} pkts/{} frames",
                            v.packets_sent,
                            v.frames_sent,
                            v.packets_received,
                            v.frames_received
                        );
                    }
                }
            });
        }
        Err(e) => tracing::warn!("Failed to answer call: {:#}", e),
    }
}

#[cfg(test)]
mod data_frame_tests {
    use super::{acceptance_ack_body, data_frame_event, sync_reply_body};

    fn frame(body: &str, headers: serde_json::Value) -> String {
        serde_json::json!({"id": 7, "method": "POST", "url": "/v4/f/x/messaging",
            "headers": headers, "body": body})
        .to_string()
    }

    #[test]
    fn data_frame_plain_chat_event_is_published() {
        let ev = r#"{"resourceType":"NewMessage","resource":{"id":"1","clientmessageid":"9"}}"#;
        let got = data_frame_event(&frame(ev, serde_json::json!({}))).unwrap();
        assert_eq!(got, ev);
    }

    #[test]
    fn data_frame_gzip_body_is_decoded() {
        use base64::Engine;
        use std::io::Write;
        let ev = r#"{"eventMessages":[{"resourceType":"NewMessage","resource":{"id":"2"}}]}"#;
        let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        enc.write_all(ev.as_bytes()).unwrap();
        let b64 = base64::engine::general_purpose::STANDARD.encode(enc.finish().unwrap());
        let hdr = serde_json::json!({"X-Microsoft-Skype-Content-Encoding": "gzip"});
        assert_eq!(data_frame_event(&frame(&b64, hdr)).as_deref(), Some(ev));
        // Header missing: the base64+gzip fallback still decodes.
        assert_eq!(
            data_frame_event(&frame(&b64, serde_json::json!({}))).as_deref(),
            Some(ev)
        );
    }

    #[test]
    fn data_frame_body_under_data_or_as_object() {
        let ev = r#"{"resourceType":"NewMessage","resource":{"id":"3"}}"#;
        let nested = serde_json::json!({"id": 9, "data": {"body": ev}}).to_string();
        assert_eq!(data_frame_event(&nested).as_deref(), Some(ev));
        let obj = serde_json::json!({"id": 9, "body": {"resourceType": "NewMessage"}}).to_string();
        assert!(data_frame_event(&obj).unwrap().contains("NewMessage"));
    }

    #[test]
    fn data_frame_cp_and_gp_wrappers_are_unwrapped() {
        use base64::Engine;
        use std::io::Write;
        let ev = r#"{"type":"EventMessage","resourceType":"NewMessage","resource":{"id":"4"}}"#;
        let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        enc.write_all(ev.as_bytes()).unwrap();
        let cp = base64::engine::general_purpose::STANDARD.encode(enc.finish().unwrap());
        let body = serde_json::json!({"cp": cp}).to_string();
        assert_eq!(
            data_frame_event(&frame(&body, serde_json::json!({}))).as_deref(),
            Some(ev)
        );
        let gp = base64::engine::general_purpose::STANDARD.encode(ev);
        let body = serde_json::json!({"gp": gp}).to_string();
        assert_eq!(
            data_frame_event(&frame(&body, serde_json::json!({}))).as_deref(),
            Some(ev)
        );
    }

    #[test]
    fn data_frame_non_chat_payloads_are_skipped() {
        assert!(
            data_frame_event(&frame(r#"{"callNotification":{}}"#, serde_json::json!({}))).is_none()
        );
        assert!(data_frame_event("not json").is_none());
        assert!(data_frame_event(r#"{"id":1,"status":200}"#).is_none());
    }

    #[test]
    fn acceptance_ack_links_point_back_at_us() {
        let b = acceptance_ack_body("https://t.example/v4/f/abc/", "ep-1");
        let link = b
            .pointer("/callAcceptanceAcknowledgement/links/mediaRenegotiation")
            .and_then(|l| l.as_str())
            .unwrap();
        assert!(link.starts_with("https://t.example/v4/f/abc/callAgent/ep-1/"));
        assert!(link.ends_with("/call/mediaRenegotiation/"));
        // Only call acceptances get a reply body.
        let other = r#"3:::{"id":3,"url":"/v4/f/abc/callAgent/ep-1/h/call/progress/","body":"{}"}"#;
        assert!(sync_reply_body(other).is_none());
    }

    #[test]
    fn data_frame_call_invitations_are_recognised() {
        use super::data_frame_call;
        let inv = r#"{"callInvitation":{"links":{"acceptance":"https://cc/a"}}}"#;
        let by_url = serde_json::json!({"id": 3, "method": "POST",
            "url": "/v4/f/x/NGCallManagerWin", "headers": {}, "body": inv})
        .to_string();
        assert_eq!(data_frame_call(&by_url).as_deref(), Some(inv));
        // A chat event is not a call.
        let chat = frame(r#"{"resourceType":"NewMessage"}"#, serde_json::json!({}));
        assert!(data_frame_call(&chat).is_none());
    }

    #[test]
    fn call_payload_cp_wrapper_is_unwrapped() {
        use super::unwrap_call_payload;
        use base64::Engine;
        use std::io::Write;
        let inv = r#"{"callInvitation":{"links":{"acceptance":"https://cc/a"}}}"#;
        let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        enc.write_all(inv.as_bytes()).unwrap();
        let cp = base64::engine::general_purpose::STANDARD.encode(enc.finish().unwrap());
        let wrapped =
            serde_json::json!({"callId": "c", "callerId": "8:x", "evt": 107, "cp": cp}).to_string();
        assert_eq!(unwrap_call_payload(&wrapped), inv);
        assert_eq!(unwrap_call_payload(inv), inv);
    }

    #[test]
    fn call_agent_callbacks_are_tagged_with_their_path() {
        use super::data_frame_call;
        let f = serde_json::json!({"id": 4, "method": "POST",
            "url": "/v4/f/abc/callAgent/ep-1/0a1b2c3d/call/end/", "headers": {},
            "body": r#"{"callEnd":{"code":0}}"#})
        .to_string();
        let v: serde_json::Value = serde_json::from_str(&data_frame_call(&f).unwrap()).unwrap();
        assert_eq!(v["callAgentPath"], "call/end/");
        assert_eq!(v["body"]["callEnd"]["code"], 0);
    }
}
