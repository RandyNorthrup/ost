//! Teams' Editor: spelling in the compose box, from Microsoft Editor over
//! Office's AugLoop service, as Teams desktop does it (its Editor SDK).
//!
//! One websocket session (`wss://augloop.office.com/`, an AAD token for
//! `https://augloop.office.com/v2`) carries every compose box: each is a
//! text tile in the session's document. Typing sends text deltas; AugLoop
//! answers with `AugLoop_Text_Critique` annotations (the misspelt range,
//! its suggestions) and deletes them as the text changes. The proofing
//! settings (your spellcheck languages, Teams' "authoringLanguages", and
//! your dictionary) are read and written through the same session.
//! Positions are UTF-16 offsets, as in Teams' editor and QML strings.

use std::collections::HashMap;

use futures::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

/// A misspelling AugLoop found.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Critique {
    pub id: String,
    /// UTF-16 offset and length in the compose text.
    pub start: usize,
    pub length: usize,
    /// "Spelling".
    pub category: String,
    /// The word as checked.
    pub word: String,
    pub suggestions: Vec<String>,
    /// The first suggestion may be applied as you type (Teams' "Correct
    /// words while typing").
    pub autocorrect: bool,
    pub language: String,
}

/// Your proofing settings: spellcheck languages (preferred first) and
/// dictionary.
#[derive(Debug, Clone, PartialEq, Eq, Default, serde::Serialize)]
pub struct ProofingSettings {
    pub languages: Vec<String>,
    pub dictionary: Vec<String>,
}

/// What the session reports.
#[derive(Debug, Clone)]
pub enum Event {
    /// A compose box's critiques, in text order (complete each time).
    Critiques { doc: String, critiques: Vec<Critique> },
    Settings(ProofingSettings),
}

/// Teams' limit on spellcheck languages.
pub const MAX_LANGUAGES: usize = 3;

/// The languages Teams' Manage spellcheck languages offers: (code, native
/// name, English name).
pub fn supported_languages() -> &'static [(String, String, String)] {
    static L: std::sync::OnceLock<Vec<(String, String, String)>> = std::sync::OnceLock::new();
    L.get_or_init(|| {
        let v: Vec<Value> = serde_json::from_str(include_str!("editor_languages.json")).expect("editor_languages.json");
        v.iter()
            .filter_map(|l| Some((l["code"].as_str()?.to_string(), l["native"].as_str()?.to_string(), l["english"].as_str()?.to_string())))
            .collect()
    })
}

/// One of Editor's critique categories for a language (Teams' options
/// under Editor spellcheck): the category's own switch and its critique
/// types.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Category {
    pub id: String,
    pub name: String,
    pub priority: i64,
    pub critiques: Vec<CritiqueType>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct CritiqueType {
    pub id: String,
    pub name: String,
    pub binary: bool,
    pub default: i64,
    pub priority: i64,
}

/// Microsoft Editor's options for `language` (Teams asks Editor's service:
/// `POST https://editor.svc.cloud.microsoft/NLEditor/Config/V2` as
/// Teams_Win32); Teams shows those of priority 0.
pub async fn categories(http: &reqwest::Client, language: &str) -> anyhow::Result<Vec<Category>> {
    let body = json!({"AppId": "Teams_Win32", "Descriptors": [{"Name": "LicenseType", "Value": "Subscription"}, {"Name": "FlightIds", "Value": "mc-officeEditorTonalEnabled;mc-officeEditorDNNGrammarEnabled"}], "LanguageId": language});
    let v: Value = http.post("https://editor.svc.cloud.microsoft/NLEditor/Config/V2").json(&body).send().await?.error_for_status()?.json().await?;
    Ok(parse_categories(&v))
}

fn parse_categories(v: &Value) -> Vec<Category> {
    v["CritiqueCategoryInfoList"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| Category {
            id: c["Id"].as_str().unwrap_or_default().to_lowercase(),
            name: c["Name"].as_str().unwrap_or_default().into(),
            priority: c["Priority"].as_i64().unwrap_or(0),
            critiques: c["CritiqueTypeInfoList"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|t| CritiqueType {
                    id: t["Id"].as_str().unwrap_or_default().to_lowercase(),
                    name: t["Name"].as_str().unwrap_or_default().into(),
                    binary: t["IsBinaryCritiqueType"].as_bool().unwrap_or(true),
                    default: t["DefaultCritiqueValue"].as_i64().unwrap_or(1),
                    priority: t["CritiquePriority"].as_i64().unwrap_or(0),
                })
                .collect(),
        })
        .collect()
}

enum Cmd {
    Text { doc: String, text: String },
    Close { doc: String },
    AddWord(String),
    IgnoreAll(String),
    SetDictionary(Vec<String>),
    SetLanguages(Vec<String>),
    ReadSettings,
    SetOverrides(Vec<Value>),
}

/// The Editor session, shared by every compose box.
#[derive(Clone)]
pub struct Editor {
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Editor {
    /// Start the session on `rt`; `events` is called from its task.
    /// `ui_language` ("en-us") checks text until you choose languages.
    pub fn start(rt: &tokio::runtime::Handle, ui_language: &str, events: impl Fn(Event) + Send + Sync + 'static) -> Editor {
        let (tx, rx) = mpsc::unbounded_channel();
        rt.spawn(run(rx, tx.clone(), ui_language.to_lowercase(), Box::new(events)));
        Editor { tx }
    }
    /// The compose box `doc` now reads `text` (sent once typing pauses).
    pub fn set_text(&self, doc: &str, text: &str) {
        let _ = self.tx.send(Cmd::Text { doc: doc.into(), text: text.into() });
    }
    pub fn close(&self, doc: &str) {
        let _ = self.tx.send(Cmd::Close { doc: doc.into() });
    }
    /// Teams' Add to Dictionary.
    pub fn add_to_dictionary(&self, word: &str) {
        let _ = self.tx.send(Cmd::AddWord(word.into()));
    }
    /// Teams' Ignore all: the word stops being flagged in this run.
    pub fn ignore_all(&self, word: &str) {
        let _ = self.tx.send(Cmd::IgnoreAll(word.into()));
    }
    /// Replace your dictionary (removing words).
    pub fn set_dictionary(&self, words: Vec<String>) {
        let _ = self.tx.send(Cmd::SetDictionary(words));
    }
    /// Read your proofing settings (an Event::Settings follows).
    pub fn read_settings(&self) {
        let _ = self.tx.send(Cmd::ReadSettings);
    }
    /// Your critique options that differ from Editor's defaults (Teams'
    /// OverriddenCritiqueTypeOptions: {id, value, languageId, name}).
    pub fn set_overrides(&self, overrides: Vec<Value>) {
        let _ = self.tx.send(Cmd::SetOverrides(overrides));
    }
    /// Teams' Manage spellcheck languages (up to three, preferred first).
    pub fn set_languages(&self, languages: Vec<String>) {
        let _ = self.tx.send(Cmd::SetLanguages(languages));
    }
}

fn h(t: &str, b: &[&str]) -> Value {
    json!({"T_": t, "B_": b})
}

/// A compose box's tile.
struct Doc {
    tile: String,
    /// What AugLoop has (with Teams' trailing newline).
    sent: String,
    /// What the box reads now.
    want: String,
    rev: u64,
    critiques: HashMap<String, Critique>,
    /// When to send `want`, and when to ask for the last word (Teams' flush
    /// after a pause).
    send_at: Option<tokio::time::Instant>,
    flush_at: Option<tokio::time::Instant>,
}

/// UTF-16 length.
fn u16len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// The delta from `old` to `new`: (position, removed length, inserted
/// text), in UTF-16 units, never splitting a surrogate pair.
pub fn diff(old: &str, new: &str) -> (usize, usize, String) {
    let a: Vec<u16> = old.encode_utf16().collect();
    let b: Vec<u16> = new.encode_utf16().collect();
    let mut p = a.iter().zip(&b).take_while(|(x, y)| x == y).count();
    while p > 0 && (0xD800..0xDC00).contains(&a[p - 1]) {
        p -= 1;
    }
    let mut s = a[p..].iter().rev().zip(b[p..].iter().rev()).take_while(|(x, y)| x == y).count();
    while s > 0 && (0xDC00..0xE000).contains(&a[a.len() - s]) {
        s -= 1;
    }
    (p, a.len() - p - s, String::from_utf16_lossy(&b[p..b.len() - s]))
}

fn word_count(s: &str) -> usize {
    s.split_whitespace().count()
}

/// Apply an AnnotationResultsMessage's operations to the docs (by tile);
/// the tiles whose critiques changed.
fn apply_results(v: &Value, docs: &mut HashMap<String, Doc>) -> Vec<String> {
    let mut changed = Vec::new();
    for op in v["ops"].as_array().into_iter().flatten() {
        let tile = op["parentPath"].as_array().and_then(|p| p.get(3)).and_then(|x| x.as_str()).unwrap_or_default();
        let Some((name, doc)) = docs.iter_mut().find(|(_, d)| d.tile == tile) else { continue };
        let kind = op.pointer("/H_/T_").and_then(|x| x.as_str()).unwrap_or_default();
        for it in op["items"].as_array().into_iter().flatten() {
            let id = it["id"].as_str().unwrap_or_default().to_string();
            if kind == "AugLoop_Core_DeleteOperation" {
                doc.critiques.remove(&id);
            } else if kind == "AugLoop_Core_AddOperation" {
                let b = &it["body"];
                let Some(word) = b["context"].as_str() else { continue };
                let start = b["range"]["start"].as_u64().unwrap_or(0) as usize;
                let length = b["range"]["length"].as_u64().unwrap_or(0) as usize;
                let suggestions = b["suggestions"].as_array().into_iter().flatten().filter_map(|s| s["text"].as_str().map(str::to_string)).collect();
                // Teams' suggestion actions: 1 change once, 2 change all, 4 autocorrect.
                let autocorrect = b["suggestions"].get(0).and_then(|s| s["suggestionActions"].as_u64()).is_some_and(|a| a & 4 != 0);
                let language = b["language"].as_str().unwrap_or_default().to_string();
                doc.critiques.insert(id.clone(), Critique { id, start, length, category: b["categoryName"].as_str().unwrap_or("Spelling").into(), word: word.into(), suggestions, autocorrect, language });
            }
        }
        if !changed.contains(name) {
            changed.push(name.clone());
        }
    }
    changed
}

/// A doc's critiques for the UI: in order, only those still matching the
/// text (a stale range is dropped until AugLoop catches up), not ignored.
fn visible(doc: &Doc, ignored: &[String]) -> Vec<Critique> {
    let text: Vec<u16> = doc.want.encode_utf16().collect();
    let mut v: Vec<Critique> = doc
        .critiques
        .values()
        .filter(|c| c.start + c.length <= text.len() && String::from_utf16_lossy(&text[c.start..c.start + c.length]) == c.word)
        .filter(|c| !ignored.contains(&c.word))
        .cloned()
        .collect();
    v.sort_by_key(|c| c.start);
    v
}

fn settings_from(v: &Value) -> Option<ProofingSettings> {
    let body = v["ops"].as_array()?.iter().flat_map(|op| op["items"].as_array().into_iter().flatten()).map(|it| &it["body"]).find(|b| b.get("userDictionary").is_some() || b.get("languageSettings").is_some())?;
    let languages = body["languageSettings"]["authoringLanguages"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|l| l["locale"].as_str().or(l.as_str()).map(|s| s.to_lowercase()))
        .collect();
    let dictionary = body["userDictionary"].as_array().into_iter().flatten().filter_map(|w| w.as_str().map(str::to_string)).collect();
    Some(ProofingSettings { languages, dictionary })
}

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

struct Session {
    ws: Ws,
    n: u64,
    seq: u64,
    group: String,
    /// The critique annotation's activation token (its config updates
    /// name it).
    critique_token: String,
}

fn critique_config(languages: &[String], overrides: &[Value]) -> Value {
    json!({"LicenseType": "Subscription", "OverriddenCritiqueTypeOptions": overrides, "ProofingLanguages": languages, "H_": h("AugLoop_Text_ProofingAnnotationActivationConfig", &[])})
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
        format!("ost{}.{}", &self.group[..8], self.n)
    }
    async fn sync(&mut self, ops: Vec<Value>, seq: bool) -> anyhow::Result<()> {
        let mid = self.mid();
        let mut m = json!({"cv": self.cv(), "ops": ops, "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid});
        if seq {
            m["seq"] = json!(self.seq);
            self.seq += 1;
        }
        self.send(m).await
    }
    fn path(&self) -> Value {
        json!(["session", "documentRoot", self.group])
    }
    async fn signal(&mut self, body: Value) -> anyhow::Result<()> {
        let op = json!({"parentPath": self.path(), "items": [{"id": "0", "body": body, "contextId": "C1"}], "H_": h("AugLoop_Signals_SignalOperation", &["AugLoop_Core_Operation"])});
        self.sync(vec![op], false).await
    }
    async fn add_tile(&mut self, doc: &mut Doc, language: &str) -> anyhow::Result<()> {
        doc.sent = format!("{}\n", doc.want);
        doc.rev = 0;
        let op = json!({"parentPath": self.path(), "prevId": "", "nextId": "", "items": [{"id": doc.tile, "body": {"content": doc.sent, "formattedRanges": [{"start": 0, "length": u16len(&doc.sent), "languageId": language}],
            "H_": h("AugLoop_Text_FormattedTextTile", &["AugLoop_Text_TextTile"])}, "revId": "0", "sourceTimestamp": now_ms(), "contextId": "C4"}],
            "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])});
        self.sync(vec![op], true).await
    }
    async fn delta(&mut self, doc: &mut Doc, flush: bool) -> anyhow::Result<()> {
        let new = format!("{}\n", doc.want);
        let (position, length, content, user_type, unit) = if flush {
            (u16len(&doc.want), 0, String::new(), 1, 3)
        } else {
            let (p, l, c) = diff(&doc.sent, &new);
            if l == 0 && c.is_empty() {
                return Ok(());
            }
            (p, l, c, 0, 0)
        };
        doc.rev += 1;
        let delta_type = if length == 0 && !flush { 0 } else { 2 };
        let op = json!({"parentPath": ["session", "documentRoot", self.group, doc.tile], "items": [{"id": doc.tile, "revId": doc.rev.to_string(), "body": {"deltaType": delta_type, "unit": unit, "position": position, "length": length, "content": content,
            "wordCount": word_count(&doc.want), "userInfo": {"userType": user_type}, "H_": h("AugLoop_Text_FormattedTextTileDelta", &["AugLoop_Text_TextTileDelta", "AugLoop_Core_ItemDelta"])},
            "sourceTimestamp": now_ms(), "contextId": format!("C{}", doc.rev)}], "H_": h("AugLoop_Core_DeltaUpdateOperation", &["AugLoop_Core_Operation"])});
        doc.sent = new;
        self.sync(vec![op], true).await
    }
    async fn remove_tile(&mut self, tile: &str) -> anyhow::Result<()> {
        let op = json!({"parentPath": self.path(), "items": [{"id": tile}], "H_": h("AugLoop_Core_DeleteOperation", &["AugLoop_Core_Operation"])});
        self.sync(vec![op], true).await
    }
    async fn activate(&mut self, annotation: &str, config: Option<Value>) -> anyhow::Result<()> {
        let mid = self.mid();
        let token = uuid::Uuid::new_v4().to_string();
        if config.is_some() {
            self.critique_token = token.clone();
        }
        let mut m = json!({"annotationType": annotation, "token": token, "ignoreExistingAnnotations": false, "sendStateUpdates": false, "returnAnnotationDoesNotExist": true, "sendApologies": false,
            "H_": h("AugLoop_Session_Protocol_AnnotationActivationMessage", &["AugLoop_Session_Protocol_Message"]), "cv": self.cv(), "messageId": mid});
        if let Some(c) = config {
            m["config"] = c;
        }
        self.send(m).await
    }
    async fn update_config(&mut self, config: Value) -> anyhow::Result<()> {
        let mid = self.mid();
        let m = json!({"token": self.critique_token, "config": config, "H_": h("AugLoop_Session_Protocol_AnnotationConfigUpdateMessage", &["AugLoop_Session_Protocol_Message"]), "cv": self.cv(), "messageId": mid});
        self.send(m).await
    }
    async fn provide_token(&mut self, token: &str) -> anyhow::Result<()> {
        let mid = self.mid();
        let m = json!({"authToken": token, "version": 1, "H_": h("AugLoop_Session_Protocol_TokenProvisionMessage", &["AugLoop_Session_Protocol_Message"]), "cv": self.cv(), "messageId": mid});
        self.send(m).await
    }
}

fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

async fn token() -> anyhow::Result<String> {
    crate::auth::oauth::access_token_for("https://augloop.office.com/v2/.default").await
}

/// Open a session: Teams' SessionInit, the document, the token, the
/// settings annotation (read), spelling critiques in `languages`.
async fn connect(ui_language: &str, languages: &[String], overrides: &[Value]) -> anyhow::Result<(Session, tokio::time::Instant)> {
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request("wss://augloop.office.com/")?;
    req.headers_mut().insert("Origin", "https://teams.microsoft.com".parse()?);
    let (ws, _) = tokio_tungstenite::connect_async(req).await?;
    let mut s = Session { ws, n: 0, seq: 0, group: uuid::Uuid::new_v4().to_string(), critique_token: String::new() };
    let mid = s.mid();
    let init = json!({"protocolVersion": 2,
        "clientMetadata": {"appName": "Teams", "appPlatform": "Win32", "releaseAudienceGroup": "Production", "releaseChannel": "general", "sessionId": uuid::Uuid::new_v4().to_string(),
            "uiLanguage": ui_language, "flights": "", "runtimeVersion": "2.37.2676", "docSessionId": uuid::Uuid::new_v4().to_string(), "userSystemTimezone": iana_timezone()},
        "extensionConfigs": [], "returnWorkflowInputTypes": false, "enableRemoteExecutionNotification": false, "createBlobStorageContainer": false,
        "H_": h("AugLoop_Session_Protocol_SessionInitMessage", &["AugLoop_Session_Protocol_Message"]), "cv": s.cv(), "messageId": mid});
    s.send(init).await?;
    // The session's answer (its sessionKey).
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
    s.activate("AugLoop_ProofingSettings_ProofingSettingsAnnotation", None).await?;
    let mid = s.mid();
    let seed = json!({"cv": s.cv(), "seq": s.seq, "ops": [{"parentPath": ["session"], "items": [{"id": "documentRoot", "body": {"isReadonly": false, "H_": h("AugLoop_Core_Document", &["AugLoop_Core_TileGroup"])}}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}], "groupId": "Seed", "groupSize": 1, "groupComplete": true,
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid});
    s.seq += 1;
    s.send(seed).await?;
    s.provide_token(&token().await?).await?;
    s.signal(json!({"settingNames": ["userDictionary", "overriddenOptions", "languageSettings"], "H_": h("AugLoop_ProofingSettings_ReadSettingSignal", &["AugLoop_ProofingSettings_ProofingSettingSignal", "AugLoop_Signals_Signal"])})).await?;
    let langs: Vec<String> = if languages.is_empty() { vec![ui_language.to_string()] } else { languages.to_vec() };
    s.activate("AugLoop_Text_Critique", Some(critique_config(&langs, overrides))).await?;
    // Tokens last over an hour; renew well before.
    Ok((s, tokio::time::Instant::now() + std::time::Duration::from_secs(25 * 60)))
}

fn iana_timezone() -> String {
    std::fs::read_link("/etc/localtime")
        .ok()
        .and_then(|p| p.to_str().and_then(|s| s.split("zoneinfo/").nth(1)).map(str::to_string))
        .unwrap_or_else(|| "UTC".into())
}

/// How long typing pauses before the text goes, and before Teams asks
/// for the last word too.
const SEND_AFTER: std::time::Duration = std::time::Duration::from_millis(250);
const FLUSH_AFTER: std::time::Duration = std::time::Duration::from_millis(1500);

async fn run(mut rx: mpsc::UnboundedReceiver<Cmd>, requeue: mpsc::UnboundedSender<Cmd>, ui_language: String, events: Box<dyn Fn(Event) + Send + Sync>) {
    let mut docs: HashMap<String, Doc> = HashMap::new();
    let mut languages: Vec<String> = Vec::new();
    let mut ignored: Vec<String> = Vec::new();
    let mut overrides: Vec<Value> = Vec::new();
    let mut backoff = 1u64;
    loop {
        // Only connect when there is something to check (or settings to
        // write).
        if docs.is_empty() {
            match rx.recv().await {
                None => return,
                Some(Cmd::Text { doc, text }) if !text.trim().is_empty() => {
                    docs.insert(doc, Doc { tile: uuid::Uuid::new_v4().to_string(), sent: String::new(), want: text, rev: 0, critiques: HashMap::new(), send_at: None, flush_at: None });
                }
                Some(Cmd::Text { .. }) | Some(Cmd::Close { .. }) => continue,
                Some(Cmd::IgnoreAll(w)) => {
                    ignored.push(w);
                    continue;
                }
                Some(Cmd::SetOverrides(o)) => {
                    overrides = o;
                    continue;
                }
                // Settings need the session: handled once it is open.
                Some(c) => {
                    let _ = requeue.send(c);
                }
            }
        }
        let (mut s, mut renew_at) = match connect(&ui_language, &languages, &overrides).await {
            Ok(x) => x,
            Err(e) => {
                tracing::warn!("Editor: {e:#}");
                tokio::time::sleep(std::time::Duration::from_secs(backoff)).await;
                backoff = (backoff * 2).min(120);
                continue;
            }
        };
        backoff = 1;
        let language = languages.first().cloned().unwrap_or_else(|| ui_language.clone());
        let mut ok = true;
        for d in docs.values_mut() {
            d.critiques.clear();
            ok &= s.add_tile(d, &language).await.is_ok();
            d.flush_at = Some(tokio::time::Instant::now() + FLUSH_AFTER);
        }
        let mut ping = tokio::time::interval(std::time::Duration::from_secs(30));
        ping.tick().await;
        let mut reconnect_for_languages = false;
        let mut reconnect_at: Option<tokio::time::Instant> = None;
        while ok {
            let next = docs.values().flat_map(|d| [d.send_at, d.flush_at]).flatten().chain(reconnect_at).min().unwrap_or_else(|| tokio::time::Instant::now() + std::time::Duration::from_secs(3600));
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
                    match v["annotationType"].as_str() {
                        Some("AugLoop_Text_Critique") => {
                            for name in apply_results(&v, &mut docs) {
                                let critiques = visible(&docs[&name], &ignored);
                                events(Event::Critiques { doc: name, critiques });
                            }
                        }
                        Some("AugLoop_ProofingSettings_ProofingSettingsAnnotation") => {
                            if let Some(p) = settings_from(&v) {
                                if !p.languages.is_empty() && p.languages != languages && languages.is_empty() {
                                    languages = p.languages.clone();
                                    reconnect_for_languages = true;
                                }
                                events(Event::Settings(p));
                            }
                        }
                        _ => {}
                    }
                    if reconnect_for_languages { break }
                }
                c = rx.recv() => {
                    let Some(c) = c else { return };
                    match c {
                        Cmd::Text { doc, text } => {
                            let d = docs.entry(doc.clone()).or_insert_with(|| Doc { tile: uuid::Uuid::new_v4().to_string(), sent: String::new(), want: String::new(), rev: 0, critiques: HashMap::new(), send_at: None, flush_at: None });
                            let fresh = d.sent.is_empty();
                            d.want = text;
                            if fresh {
                                ok = s.add_tile(d, &language).await.is_ok();
                                d.flush_at = Some(tokio::time::Instant::now() + FLUSH_AFTER);
                            } else {
                                d.send_at = Some(tokio::time::Instant::now() + SEND_AFTER);
                                d.flush_at = None;
                            }
                            // Ranges the edit moved are re-checked; show what still fits.
                            let critiques = visible(&docs[&doc], &ignored);
                            events(Event::Critiques { doc, critiques });
                        }
                        Cmd::Close { doc } => {
                            if let Some(d) = docs.remove(&doc) {
                                ok = s.remove_tile(&d.tile).await.is_ok();
                            }
                        }
                        Cmd::AddWord(w) => {
                            ok = s.signal(json!({"wordsToAdd": [w.clone()], "H_": h("AugLoop_ProofingSettings_AddToDictionarySignal", &["AugLoop_ProofingSettings_ProofingSettingSignal", "AugLoop_Signals_Signal"])})).await.is_ok();
                            // Shown as accepted at once, as Teams.
                            ignored.push(w);
                            for (name, d) in &docs {
                                events(Event::Critiques { doc: name.clone(), critiques: visible(d, &ignored) });
                            }
                        }
                        Cmd::IgnoreAll(w) => {
                            ignored.push(w);
                            for (name, d) in &docs {
                                events(Event::Critiques { doc: name.clone(), critiques: visible(d, &ignored) });
                            }
                        }
                        Cmd::SetOverrides(o) => {
                            overrides = o;
                            let langs: Vec<String> = if languages.is_empty() { vec![ui_language.clone()] } else { languages.clone() };
                            ok = s.update_config(critique_config(&langs, &overrides)).await.is_ok();
                        }
                        Cmd::ReadSettings => {
                            ok = s.signal(json!({"settingNames": ["userDictionary", "overriddenOptions", "languageSettings"], "H_": h("AugLoop_ProofingSettings_ReadSettingSignal", &["AugLoop_ProofingSettings_ProofingSettingSignal", "AugLoop_Signals_Signal"])})).await.is_ok();
                        }
                        Cmd::SetDictionary(words) => {
                            ok = s.signal(json!({"settingValues": {"userDictionary": words}, "H_": h("AugLoop_ProofingSettings_WriteSettingSignal", &["AugLoop_ProofingSettings_ProofingSettingSignal", "AugLoop_Signals_Signal"])})).await.is_ok();
                        }
                        Cmd::SetLanguages(l) => {
                            let names: Vec<Value> = l.iter().map(|c| json!({"locale": c, "displayName": supported_languages().iter().find(|x| &x.0 == c).map(|x| x.2.clone()).unwrap_or_default()})).collect();
                            ok = s.signal(json!({"settingValues": {"languageSettings": {"authoringLanguages": names}}, "H_": h("AugLoop_ProofingSettings_WriteSettingSignal", &["AugLoop_ProofingSettings_ProofingSettingSignal", "AugLoop_Signals_Signal"])})).await.is_ok();
                            languages = l;
                            // Critiques switch language on a new session, once
                            // AugLoop has the setting.
                            reconnect_at = Some(tokio::time::Instant::now() + std::time::Duration::from_millis(1500));
                        }
                    }
                }
                _ = tokio::time::sleep_until(next) => {
                    let now = tokio::time::Instant::now();
                    if reconnect_at.is_some_and(|t| t <= now) {
                        reconnect_for_languages = true;
                        break;
                    }
                    for d in docs.values_mut() {
                        if d.send_at.is_some_and(|t| t <= now) {
                            d.send_at = None;
                            ok &= s.delta(d, false).await.is_ok();
                            d.flush_at = Some(now + FLUSH_AFTER);
                        } else if d.flush_at.is_some_and(|t| t <= now) {
                            d.flush_at = None;
                            ok &= s.delta(d, true).await.is_ok();
                        }
                    }
                }
                _ = ping.tick() => {
                    ok = s.ws.send(Message::Text("~".into())).await.is_ok();
                }
                _ = tokio::time::sleep_until(renew_at) => {
                    match token().await {
                        Ok(t) => ok = s.provide_token(&t).await.is_ok(),
                        Err(e) => tracing::warn!("Editor token: {e:#}"),
                    }
                    renew_at = tokio::time::Instant::now() + std::time::Duration::from_secs(25 * 60);
                }
            }
        }
        let _ = s.ws.close(None).await;
        if !reconnect_for_languages {
            tokio::time::sleep(std::time::Duration::from_secs(backoff)).await;
            backoff = (backoff * 2).min(120);
        }
        // Drop empty boxes; the rest are re-added on the new session.
        docs.retain(|_, d| !d.want.trim().is_empty());
        for d in docs.values_mut() {
            d.sent.clear();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deltas_in_utf16_units() {
        assert_eq!(diff("Thsi\n", "This\n"), (2, 2, "is".into()));
        assert_eq!(diff("a\n", "ab\n"), (1, 0, "b".into()));
        assert_eq!(diff("abc\n", "ac\n"), (1, 1, String::new()));
        assert_eq!(diff("", "x\n"), (0, 0, "x\n".into()));
        // An emoji is two units and is never split.
        assert_eq!(diff("a😀\n", "a😃\n"), (1, 2, "😃".into()));
        assert_eq!(u16len("😀é"), 3);
    }

    fn doc(text: &str) -> Doc {
        Doc { tile: "t1".into(), sent: format!("{text}\n"), want: text.into(), rev: 0, critiques: HashMap::new(), send_at: None, flush_at: None }
    }

    #[test]
    fn critiques_follow_augloop_operations() {
        let mut docs = HashMap::from([("chat".to_string(), doc("Thsi is a tset"))]);
        let add: Value = serde_json::from_str(r##"{"annotationType":"AugLoop_Text_Critique","ops":[{"parentPath":["session","documentRoot","g","t1"],"items":[
            {"id":"#A2","body":{"categoryName":"Spelling","context":"Thsi","range":{"start":0,"length":4},"suggestions":[{"text":"This"},{"text":"Tshi"}]}},
            {"id":"#A3","body":{"categoryName":"Spelling","context":"tset","range":{"start":10,"length":4},"suggestions":[{"text":"test"}]}}],
            "H_":{"T_":"AugLoop_Core_AddOperation"}}]}"##).unwrap();
        assert_eq!(apply_results(&add, &mut docs), vec!["chat".to_string()]);
        let v = visible(&docs["chat"], &[]);
        assert_eq!(v.iter().map(|c| (c.word.as_str(), c.start)).collect::<Vec<_>>(), [("Thsi", 0), ("tset", 10)]);
        assert_eq!(v[0].suggestions, ["This", "Tshi"]);
        // Ignore all hides the word; an edit that moves a range hides it until
        // AugLoop answers again.
        assert_eq!(visible(&docs["chat"], &["tset".into()]).len(), 1);
        docs.get_mut("chat").unwrap().want = "XThsi is a tset".into();
        assert!(visible(&docs["chat"], &[]).is_empty());
        let del: Value = serde_json::from_str(r##"{"ops":[{"parentPath":["session","documentRoot","g","t1"],"items":[{"id":"#A2"},{"id":"#A3"}],"H_":{"T_":"AugLoop_Core_DeleteOperation"}}]}"##).unwrap();
        apply_results(&del, &mut docs);
        assert!(docs["chat"].critiques.is_empty());
    }

    #[test]
    fn categories_as_editor_lists_them() {
        let v: Value = serde_json::from_str(r#"{"CritiqueCategoryInfoList":[{"Id":"19A112EC-21fd","Name":"Spelling","Priority":0,"CritiqueTypeInfoList":[
            {"Id":"d1cf9ade","Name":"Ignore words in UPPERCASE","IsBinaryCritiqueType":true,"DefaultCritiqueValue":1,"CritiquePriority":0}]}]}"#).unwrap();
        let c = parse_categories(&v);
        assert_eq!(c[0].id, "19a112ec-21fd");
        assert_eq!(c[0].critiques[0], CritiqueType { id: "d1cf9ade".into(), name: "Ignore words in UPPERCASE".into(), binary: true, default: 1, priority: 0 });
        let cfg = critique_config(&["en-us".into()], &[json!({"id": "d1cf9ade", "value": "0", "languageId": "en-us", "name": "Ignore words in UPPERCASE"})]);
        assert_eq!(cfg["OverriddenCritiqueTypeOptions"][0]["value"], "0");
        assert_eq!(cfg["ProofingLanguages"], json!(["en-us"]));
    }

    #[test]
    fn settings_as_augloop_sends_them() {
        let v: Value = serde_json::from_str(r#"{"ops":[{"items":[{"body":{"userDictionary":["OST"],"languageSettings":{"authoringLanguages":[{"locale":"en-US","displayName":"English"},{"locale":"de-de"}]}}}]}]}"#).unwrap();
        assert_eq!(settings_from(&v), Some(ProofingSettings { languages: vec!["en-us".into(), "de-de".into()], dictionary: vec!["OST".into()] }));
        assert_eq!(supported_languages().len(), 173);
        assert!(supported_languages().iter().any(|l| l.0 == "en-us"));
    }
}
