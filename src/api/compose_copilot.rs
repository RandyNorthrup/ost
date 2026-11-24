//! Teams' "Write with Copilot" in the compose box: Copilot's rewrites of
//! a draft, over Office's AugLoop service as Teams desktop asks for them
//! (captured on winpc 2026-11-16, docs/spec/messages-and-composer.md §17
//! "Write with Copilot").
//!
//! One websocket session (`wss://augloop.office.com/`, the same AAD token
//! as Teams' Editor) of its own, opened on the first request:
//! - SessionInit (appName "Teams", appPlatform "Web", Teams' AugLoop
//!   flights), the "doc" document, the activation of
//!   `AugLoop_TeamsCopilot_TeamsCopilotComposeRewriteStreamingAnnotation`
//!   and the token;
//! - each request is a `TeamsCopilotComposeRewriteSignal` added under a
//!   fresh `teams_compose_copilot_streaming_<id>` node: the draft's HTML
//!   (`userText`), a `tone` ("default", "proofread_scenario", "casual",
//!   "professional", "confident", "enthusiastic", or the words typed in
//!   Custom), a `length` ("short", "medium", "long") and where it is
//!   written (the thread, "Chat" or "Channel", the tenant);
//! - the answer streams back as annotations under the signal: `answerPart`
//!   pieces of HTML, then `isCompleted` with the whole `answer` and a
//!   `status` (0 is fine).

use std::collections::HashMap;

use futures::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

/// The annotation Teams activates for compose rewrites.
pub const ANNOTATION: &str = "AugLoop_TeamsCopilot_TeamsCopilotComposeRewriteStreamingAnnotation";

/// One rewrite as Teams asks for it.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(default)]
pub struct Rewrite {
    /// The draft (or the selected part) as the compose box's HTML.
    pub user_text: String,
    pub tone: String,
    pub length: String,
    pub thread_id: String,
    /// "Chat" or "Channel".
    pub context_type: String,
    pub tenant_id: String,
}

/// What a request reports.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// The answer so far (HTML, maybe cut inside a tag).
    Partial { request: String, html: String },
    Done { request: String, html: String },
    Failed { request: String, error: String },
}

enum Cmd {
    Rewrite { request: String, rewrite: Rewrite },
}

pub struct Copilot {
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Copilot {
    /// Start on `rt` (the session opens with the first request); `flights`
    /// is Teams' AugLoop flights line, `events` is called from its task.
    pub fn start(rt: &tokio::runtime::Handle, ui_language: &str, flights: String, events: impl Fn(Event) + Send + Sync + 'static) -> Copilot {
        let (tx, rx) = mpsc::unbounded_channel();
        rt.spawn(run(rx, ui_language.to_lowercase(), flights, Box::new(events)));
        Copilot { tx }
    }
    /// Ask for a rewrite; its events carry `request`.
    pub fn rewrite(&self, request: &str, rewrite: Rewrite) {
        let _ = self.tx.send(Cmd::Rewrite { request: request.into(), rewrite });
    }
}

fn h(t: &str, b: &[&str]) -> Value {
    json!({"T_": t, "B_": b})
}

/// Teams' flights line from its AugLoop settings (`runtimeFlights` and
/// `experimentationRuntimeFlights`, `{name, value}` each), with the audience
/// and the two message kinds it accepts.
pub fn flights(settings: &Value) -> String {
    let mut parts: Vec<String> = ["runtimeFlights", "experimentationRuntimeFlights"]
        .iter()
        .flat_map(|k| settings[*k].as_array().cloned().unwrap_or_default())
        .filter_map(|f| Some(format!("{}:{}", f["name"].as_str()?, f["value"].as_str().map(str::to_string).unwrap_or_else(|| f["value"].to_string()))))
        .collect();
    parts.push("automate-audience:Production".into());
    parts.push("_acceptsClaimsChallengeMessages".into());
    parts.push("_acceptsSeedingStatusChangeMessages".into());
    parts.join(";")
}

/// The signal for one rewrite, as Teams adds it.
pub fn signal_body(r: &Rewrite) -> Value {
    json!({
        "userText": r.user_text,
        "tone": if r.tone.is_empty() { "default" } else { r.tone.as_str() },
        "length": if r.length.is_empty() { "medium" } else { r.length.as_str() },
        "requestContext": { "threadId": r.thread_id, "contextType": if r.context_type.is_empty() { "Chat" } else { r.context_type.as_str() }, "tenantId": r.tenant_id },
        "streamResponse": true,
        "H_": h("AugLoop_TeamsCopilot_TeamsCopilotComposeRewriteSignal", &["AugLoop_TeamsCopilot_TeamsCopilotBaseSignal", "AugLoop_Signals_Signal"])
    })
}

/// The sync operation adding a signal (`node` the streaming node's id,
/// `item` the signal's), as Teams sends it.
pub fn signal_op(node: &str, child: &str, item: &str, context: &str, r: &Rewrite) -> Value {
    json!({
        "parentPath": ["session", "doc", format!("teams_compose_copilot_streaming_{node}"), child],
        "items": [{ "id": item, "body": signal_body(r), "contextId": context }],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])
    })
}

/// A rewrite's piece of answer in an AnnotationResultsMessage: (the
/// signal's id, answerPart, the whole answer once complete, its status).
pub fn parse_result(v: &Value) -> Vec<(String, String, Option<String>, i64)> {
    if v["annotationType"].as_str() != Some(ANNOTATION) {
        return Vec::new();
    }
    let mut out = Vec::new();
    for op in v["ops"].as_array().into_iter().flatten() {
        let signal = op["parentPath"].as_array().and_then(|p| p.last()).and_then(|x| x.as_str()).unwrap_or_default().to_string();
        for it in op["items"].as_array().into_iter().flatten() {
            let b = &it["body"];
            let part = b["answerPart"].as_str().unwrap_or_default().to_string();
            let done = b["isCompleted"].as_bool().unwrap_or(false);
            let answer = if done { Some(b["answer"].as_str().unwrap_or_default().to_string()) } else { None };
            out.push((signal.clone(), part, answer, b["status"].as_i64().unwrap_or(0)));
        }
    }
    out
}

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

struct Session {
    ws: Ws,
    n: u64,
    seq: u64,
    context: u64,
    id: String,
}

impl Session {
    async fn send(&mut self, v: Value) -> anyhow::Result<()> {
        self.ws.send(Message::Text(v.to_string().into())).await?;
        Ok(())
    }
    fn mid(&mut self) -> String {
        self.n += 1;
        format!("c{}", self.n)
    }
    fn cv(&self) -> String {
        format!("ost{}.{}", &self.id[..8], self.n)
    }
    async fn provide_token(&mut self, token: &str) -> anyhow::Result<()> {
        let mid = self.mid();
        let m = json!({"authToken": token, "version": 1, "H_": h("AugLoop_Session_Protocol_TokenProvisionMessage", &["AugLoop_Session_Protocol_Message"]), "cv": self.cv(), "messageId": mid});
        self.send(m).await
    }
    /// Add a request's signal; its id.
    async fn request(&mut self, r: &Rewrite) -> anyhow::Result<String> {
        let item = uuid::Uuid::new_v4().to_string();
        // Teams' first request is C1; its later ones step by three (C31,
        // C34, …).
        self.context = if self.context == 0 { 1 } else { self.context + 3 };
        let op = signal_op(&uuid::Uuid::new_v4().to_string(), &uuid::Uuid::new_v4().to_string(), &item, &format!("C{}", self.context), r);
        let mid = self.mid();
        let m = json!({"cv": self.cv(), "seq": self.seq, "ops": [op], "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid});
        self.seq += 1;
        self.send(m).await?;
        Ok(item)
    }
}

async fn token() -> anyhow::Result<String> {
    crate::auth::oauth::access_token_for("https://augloop.office.com/v2/.default").await
}

pub fn iana_timezone() -> String {
    std::fs::read_link("/etc/localtime")
        .ok()
        .and_then(|p| p.to_str().and_then(|s| s.split("zoneinfo/").nth(1)).map(str::to_string))
        .unwrap_or_else(|| "UTC".into())
}

/// Teams' SessionInit for its Copilot session.
pub fn session_init(ui_language: &str, flights: &str, cv: &str, mid: &str) -> Value {
    json!({"protocolVersion": 2,
        "clientMetadata": {"appName": "Teams", "appPlatform": "Web", "uiLanguage": ui_language, "flights": flights, "releaseAudienceGroup": "Production",
            "releaseChannel": "general", "sessionId": uuid::Uuid::new_v4().to_string(), "runtimeVersion": "2.37.2676",
            "docSessionId": uuid::Uuid::new_v4().to_string(), "userSystemTimezone": iana_timezone()},
        "extensionConfigs": [], "returnWorkflowInputTypes": true, "enableRemoteExecutionNotification": false, "createBlobStorageContainer": false,
        "H_": h("AugLoop_Session_Protocol_SessionInitMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})
}

async fn connect(ui_language: &str, flights: &str) -> anyhow::Result<(Session, tokio::time::Instant)> {
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request("wss://augloop.office.com/")?;
    req.headers_mut().insert("Origin", "https://teams.microsoft.com".parse()?);
    let (ws, _) = tokio_tungstenite::connect_async(req).await?;
    let mut s = Session { ws, n: 0, seq: 0, context: 0, id: uuid::Uuid::new_v4().to_string() };
    let mid = s.mid();
    let init = session_init(ui_language, flights, &s.cv(), &mid);
    s.send(init).await?;
    loop {
        let Some(m) = tokio::time::timeout(std::time::Duration::from_secs(20), s.ws.next()).await? else { anyhow::bail!("AugLoop closed") };
        if let Message::Text(t) = m?
            && t.as_str() != "~"
        {
            let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
            if v.get("sessionKey").is_some() {
                break;
            }
            if v.pointer("/H_/T_").and_then(|x| x.as_str()).is_some_and(|t| t.contains("Error")) {
                anyhow::bail!("AugLoop refused the session");
            }
        }
    }
    let mid = s.mid();
    let seed = json!({"cv": s.cv(), "seq": s.seq, "ops": [{"parentPath": ["session"], "items": [{"id": "doc", "body": {"isReadonly": false, "H_": h("AugLoop_Core_Document", &["AugLoop_Core_TileGroup"])}}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}], "groupId": "Seed", "groupSize": 1, "groupComplete": true,
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid});
    s.seq += 1;
    s.send(seed).await?;
    let mid = s.mid();
    let activate = json!({"annotationType": ANNOTATION, "token": uuid::Uuid::new_v4().to_string(), "ignoreExistingAnnotations": false, "returnAnnotationDoesNotExist": true, "sendApologies": false,
        "H_": h("AugLoop_Session_Protocol_AnnotationActivationMessage", &["AugLoop_Session_Protocol_Message"]), "cv": s.cv(), "messageId": mid});
    s.send(activate).await?;
    s.provide_token(&token().await?).await?;
    Ok((s, tokio::time::Instant::now() + std::time::Duration::from_secs(25 * 60)))
}

/// How long a request may go without an answer.
const ANSWER_WITHIN: std::time::Duration = std::time::Duration::from_secs(60);

async fn run(mut rx: mpsc::UnboundedReceiver<Cmd>, ui_language: String, flights: String, events: Box<dyn Fn(Event) + Send + Sync>) {
    let mut queued: Vec<(String, Rewrite)> = Vec::new();
    loop {
        if queued.is_empty() {
            match rx.recv().await {
                None => return,
                Some(Cmd::Rewrite { request, rewrite }) => queued.push((request, rewrite)),
            }
        }
        let (mut s, mut renew_at) = match connect(&ui_language, &flights).await {
            Ok(x) => x,
            Err(e) => {
                tracing::warn!("Compose Copilot: {e:#}");
                for (request, _) in queued.drain(..) {
                    events(Event::Failed { request, error: format!("{e:#}") });
                }
                continue;
            }
        };
        // Signal id -> (request, answer so far, when it was asked).
        let mut pending: HashMap<String, (String, String, tokio::time::Instant)> = HashMap::new();
        let mut ok = true;
        for (request, r) in queued.drain(..) {
            match s.request(&r).await {
                Ok(item) => {
                    pending.insert(item, (request, String::new(), tokio::time::Instant::now()));
                }
                Err(e) => {
                    events(Event::Failed { request, error: format!("{e:#}") });
                    ok = false;
                }
            }
        }
        let mut ping = tokio::time::interval(std::time::Duration::from_secs(30));
        ping.tick().await;
        let mut sweep = tokio::time::interval(std::time::Duration::from_secs(5));
        while ok {
            tokio::select! {
                m = s.ws.next() => {
                    let Some(Ok(m)) = m else { break };
                    let Message::Text(t) = m else { continue };
                    if t.as_str() == "~" { continue }
                    let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
                    if let Some(mid) = v["messageId"].as_str().filter(|m| m.starts_with('s')) {
                        let ack = json!({"H_": h("AugLoop_Session_Protocol_Response", &[]), "messageId": mid});
                        if s.send(ack).await.is_err() { break }
                    }
                    for (signal, part, answer, status) in parse_result(&v) {
                        let Some(p) = pending.get_mut(&signal) else { continue };
                        p.1.push_str(&part);
                        match answer {
                            Some(a) => {
                                let Some((request, so_far, _)) = pending.remove(&signal) else { continue };
                                let html = if a.is_empty() { so_far } else { a };
                                if status != 0 || html.trim().is_empty() {
                                    events(Event::Failed { request, error: format!("Copilot status {status}") });
                                } else {
                                    events(Event::Done { request, html });
                                }
                            }
                            None if !part.is_empty() => events(Event::Partial { request: p.0.clone(), html: p.1.clone() }),
                            None => {}
                        }
                    }
                }
                c = rx.recv() => {
                    let Some(Cmd::Rewrite { request, rewrite }) = c else { return };
                    match s.request(&rewrite).await {
                        Ok(item) => { pending.insert(item, (request, String::new(), tokio::time::Instant::now())); }
                        Err(e) => { events(Event::Failed { request, error: format!("{e:#}") }); ok = false; }
                    }
                }
                _ = sweep.tick() => {
                    let late: Vec<String> = pending.iter().filter(|(_, p)| p.2.elapsed() > ANSWER_WITHIN).map(|(k, _)| k.clone()).collect();
                    for k in late {
                        if let Some((request, _, _)) = pending.remove(&k) {
                            events(Event::Failed { request, error: "Copilot didn't answer".into() });
                        }
                    }
                }
                _ = ping.tick() => {
                    ok = s.ws.send(Message::Text("~".into())).await.is_ok();
                }
                _ = tokio::time::sleep_until(renew_at) => {
                    match token().await {
                        Ok(t) => ok = s.provide_token(&t).await.is_ok(),
                        Err(e) => tracing::warn!("Compose Copilot token: {e:#}"),
                    }
                    renew_at = tokio::time::Instant::now() + std::time::Duration::from_secs(25 * 60);
                }
            }
        }
        let _ = s.ws.close(None).await;
        for (_, (request, _, _)) in pending.drain() {
            events(Event::Failed { request, error: "The Copilot session closed".into() });
        }
    }
}

/// Plain text of the answer HTML so far, for the popover while it streams
/// (a tag cut at the end is dropped).
pub fn streaming_text(html: &str) -> String {
    let cut = match (html.rfind('<'), html.rfind('>')) {
        (Some(a), Some(b)) if a > b => &html[..a],
        (Some(a), None) => &html[..a],
        _ => html,
    };
    let mut out = String::new();
    let mut in_tag = false;
    for c in cut.chars() {
        match c {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    out.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rewrite() -> Rewrite {
        Rewrite {
            user_text: "<p>hey team can we meet tmrw at 10 to go over the test plan thx</p>".into(),
            tone: "default".into(),
            length: "medium".into(),
            thread_id: "19:ef213c7c46cf4036b11608300e96fee4@thread.v2".into(),
            context_type: "Chat".into(),
            tenant_id: "2716d134-5614-4856-a48d-2002edd9a570".into(),
        }
    }

    #[test]
    fn signals_are_teams_own() {
        // Rewrite in OST group test (2026-11-16), Teams' item verbatim.
        let teams = json!({"userText": "<p>hey team can we meet tmrw at 10 to go over the test plan thx</p>", "tone": "default", "length": "medium",
            "requestContext": {"threadId": "19:ef213c7c46cf4036b11608300e96fee4@thread.v2", "contextType": "Chat", "tenantId": "2716d134-5614-4856-a48d-2002edd9a570"},
            "streamResponse": true, "H_": {"T_": "AugLoop_TeamsCopilot_TeamsCopilotComposeRewriteSignal", "B_": ["AugLoop_TeamsCopilot_TeamsCopilotBaseSignal", "AugLoop_Signals_Signal"]}});
        assert_eq!(signal_body(&rewrite()), teams);
        let op = signal_op("0fe8", "9117", "3ecc", "C1", &rewrite());
        assert_eq!(op["parentPath"], json!(["session", "doc", "teams_compose_copilot_streaming_0fe8", "9117"]));
        assert_eq!(op["items"][0]["id"], "3ecc");
        // Proofread and Adjust only change the tone and length.
        let p = Rewrite { tone: "proofread_scenario".into(), ..rewrite() };
        assert_eq!(signal_body(&p)["tone"], "proofread_scenario");
    }

    #[test]
    fn answers_stream_then_complete() {
        let part = json!({"annotationType": ANNOTATION, "ops": [{"parentPath": ["session", "doc", "teams_compose_copilot_streaming_x", "y", "3ecc"],
            "items": [{"id": "#A12", "body": {"answerPart": "Hey", "isCompleted": false}}]}]});
        assert_eq!(parse_result(&part), vec![("3ecc".to_string(), "Hey".to_string(), None, 0)]);
        let done = json!({"annotationType": ANNOTATION, "ops": [{"parentPath": ["session", "doc", "teams_compose_copilot_streaming_x", "y", "3ecc"],
            "items": [{"id": "#A18", "body": {"status": 0, "answerPart": "", "answer": "<p>Hey team.</p>", "isCompleted": true}}]}]});
        assert_eq!(parse_result(&done), vec![("3ecc".to_string(), String::new(), Some("<p>Hey team.</p>".to_string()), 0)]);
        assert!(parse_result(&json!({"annotationType": "AugLoop_Text_Critique"})).is_empty());
    }

    #[test]
    fn streaming_text_drops_cut_tags() {
        assert_eq!(streaming_text("<p"), "");
        assert_eq!(streaming_text("<p>Hey team, could we"), "Hey team, could we");
        assert_eq!(streaming_text("<p>Hey</p><p"), "Hey");
    }

    #[test]
    fn flights_follow_teams_settings() {
        let s = json!({"runtimeFlights": [{"name": "Microsoft.Teams.Augloop.AllowPartialResults", "value": "true"}],
            "experimentationRuntimeFlights": [{"name": "Microsoft.Teams.Augloop.RequireToolChainAnalysis", "value": "true"}]});
        assert_eq!(flights(&s), "Microsoft.Teams.Augloop.AllowPartialResults:true;Microsoft.Teams.Augloop.RequireToolChainAnalysis:true;automate-audience:Production;_acceptsClaimsChallengeMessages;_acceptsSeedingStatusChangeMessages");
    }
}
