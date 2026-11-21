//! Teams' Better Together on the desktop (its TransportConnectionHandler
//! and incoming command classes): the Teams phones paired with this PC,
//! listed on Settings ▸ Devices ▸ Manage devices.
//!
//! - A phone's `broadcast` is answered with this PC's name once the phone
//!   is heard nearby over Bluetooth (or is wired).
//! - Its `pair` is taken when it carries the salt last heard from it, or
//!   once it's heard nearby; then Teams asks the user (Connect / Cancel, 50 s)
//!   and on Connect keeps it as Connected and answers `{accepted, salt}`.
//! - A connected phone gets a `keepalive` every 30 s while it's near; two
//!   misses (or not heard) disconnect it (`lock`), and hearing it again
//!   reconnects it (`keepalive`, `unlock`).
//! - Disconnect (Teams' unpairDevice) sends `unpair` and forgets it; a
//!   phone's own `unpair` forgets it too.
//!
//! The list is kept as Teams keeps it (`BTPairedDevices`, without the
//! connection status: every phone starts disconnected).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use teams_cli::api::better_together::{self as bt, Endpoint, Message, PairedDevice, command};
use teams_cli::api::client::TeamsClient;

use crate::backend::{qobject, runtime};

type Qt = cxx_qt::CxxQtThread<qobject::Backend>;

/// Teams' local storage key for the list.
const STORE_KEY: &str = "BTPairedDevices";

struct State {
    devices: Vec<PairedDevice>,
    /// The salt last heard from a phone (Teams' currentSalt; 0 at first).
    salt: u16,
    /// Each phone's Better Together URL, from its commands or the registrar.
    urls: HashMap<String, String>,
    seq: u64,
    /// The pairing waiting for the user.
    prompt: Option<tokio::sync::oneshot::Sender<bool>>,
    /// Responses awaited, by the command's cause id.
    waiting: HashMap<String, tokio::sync::oneshot::Sender<serde_json::Value>>,
    /// Keep-alive misses in a row per phone.
    misses: HashMap<String, u8>,
}

static STATE: std::sync::LazyLock<Mutex<State>> = std::sync::LazyLock::new(|| Mutex::new(State {
    devices: Vec::new(),
    salt: 0,
    urls: HashMap::new(),
    seq: 0,
    prompt: None,
    waiting: HashMap::new(),
    misses: HashMap::new(),
}));
static QT: std::sync::OnceLock<Qt> = std::sync::OnceLock::new();

fn state() -> std::sync::MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(|e| e.into_inner())
}

/// The paired phones for Manage devices: [{endPointId, deviceName,
/// clientType, clientVersion, connectionType, connectionStatus}].
pub fn devices_json() -> String {
    let s = state();
    let v: Vec<serde_json::Value> = s
        .devices
        .iter()
        .map(|d| {
            let mut j = serde_json::to_value(d).unwrap_or_default();
            j["connectionStatus"] = d.connection_status.into();
            j
        })
        .collect();
    serde_json::Value::Array(v).to_string()
}

fn changed() {
    let s = state();
    bt::set_paired_ids(s.devices.iter().map(|d| d.end_point_id.clone()).collect());
    let stored = bt::store_devices(&s.devices);
    drop(s);
    let mut map = crate::backend::load_settings();
    map.insert(STORE_KEY.into(), serde_json::Value::String(stored));
    if let Err(e) = crate::backend::save_settings(&map) {
        tracing::warn!("Better Together: saving the paired devices: {e:#}");
    }
    if let Some(qt) = QT.get() {
        let _ = qt.queue(|mut this| this.as_mut().better_together_changed());
    }
}

fn set_status(id: &str, status: u8) -> bool {
    let mut s = state();
    let Some(d) = s.devices.iter_mut().find(|d| d.end_point_id == id) else { return false };
    let was = d.connection_status;
    d.connection_status = status;
    drop(s);
    if was != status {
        tracing::info!(status, "Better Together: phone status changed");
        changed();
    }
    true
}

/// Start: the stored list (all disconnected), the commands from Trouter
/// and the reconnection of phones heard nearby.
pub fn start(qt: Qt) {
    if QT.set(qt).is_err() {
        return;
    }
    let stored = crate::backend::load_settings()
        .get(STORE_KEY)
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_default();
    state().devices = bt::load_devices(&stored);
    bt::set_paired_ids(state().devices.iter().map(|d| d.end_point_id.clone()).collect());
    let mut events = teams_cli::event_hub::subscribe();
    runtime().spawn(async move {
        use tokio::sync::broadcast::error::RecvError;
        loop {
            match events.recv().await {
                Ok(ev) if ev.kind == teams_cli::event_hub::EventKind::BetterTogether => {
                    match serde_json::from_str::<Message>(&ev.json) {
                        Ok(m) => {
                            tokio::spawn(on_command(m));
                        }
                        Err(e) => tracing::info!("Better Together: unreadable command: {e}"),
                    }
                }
                Ok(_) | Err(RecvError::Lagged(_)) => {}
                Err(RecvError::Closed) => return,
            }
        }
    });
    // Teams' keep-alive and its continuous scan for paired phones.
    runtime().spawn(async {
        loop {
            tokio::time::sleep(Duration::from_secs(bt::KEEP_ALIVE_SECS)).await;
            keep_alive_round().await;
        }
    });
}

/// This PC's endpoint, once its Trouter socket is up.
fn me() -> Option<Endpoint> {
    teams_cli::trouter::better_together_endpoint().map(|(ep, _)| ep)
}

fn response_salt() -> serde_json::Value {
    serde_json::json!({ "salt": [state().salt] })
}

async fn client() -> Option<(reqwest::Client, String)> {
    let c = TeamsClient::new().await.ok()?;
    let token = c.skype_token_value().ok()?;
    Some((c.http().clone(), token))
}

/// A phone's URL: the one its commands came from, else the registrar's.
async fn url_of(id: &str) -> Option<String> {
    if let Some(u) = state().urls.get(id).cloned() {
        return Some(u);
    }
    let (http, token) = client().await?;
    let registrar = teams_cli::trouter::better_together_endpoint().map(|(_, r)| r)?;
    let peers = bt::discover(&http, &token, &registrar).await.ok()?;
    let mut s = state();
    for p in &peers {
        s.urls.insert(p.id.clone(), p.url.clone());
    }
    s.urls.get(id).cloned()
}

/// Send a command to a phone; with `wait`, the phone's response.
async fn send(id: &str, name: &str, details: serde_json::Value, wait: Option<Duration>) -> Result<serde_json::Value, String> {
    let me = me().ok_or("not connected")?;
    let url = url_of(id).await.ok_or("the phone isn't reachable")?;
    let (http, token) = client().await.ok_or("not signed in")?;
    let mut details = details;
    details["targetEndpointId"] = id.into();
    // Teams' outgoing command classes mark the ones the phone answers.
    details["companionResponseRequired"] = matches!(name, command::KEEP_ALIVE | command::UNLOCK).into();
    let seq = {
        let mut s = state();
        s.seq += 1;
        s.seq
    };
    let msg = me.message(name, &details, seq);
    let rx = wait.map(|_| {
        let (tx, rx) = tokio::sync::oneshot::channel();
        state().waiting.insert(msg.cause_id().to_string(), tx);
        rx
    });
    let (status, body) = bt::send(&http, &token, &url, &msg).await.map_err(|e| format!("{e:#}"))?;
    tracing::info!(command = name, status, "Better Together: command sent");
    if !(200..300).contains(&status) {
        state().waiting.remove(msg.cause_id());
        return Err(format!("{status} {body}"));
    }
    match (rx, wait) {
        (Some(rx), Some(w)) => {
            let r = tokio::time::timeout(w, rx).await;
            state().waiting.remove(msg.cause_id());
            match r {
                Ok(Ok(v)) if v.get("statusCode").and_then(|c| c.as_u64()) == Some(u64::from(bt::STATUS_OK)) => Ok(v),
                Ok(Ok(v)) => Err(v.to_string()),
                _ => Err("no response".into()),
            }
        }
        _ => Ok(serde_json::json!({})),
    }
}

async fn respond(to: &Message, ok: bool, result: serde_json::Value) {
    let Some(me) = me() else { return };
    let url = if to.transport_details.url.is_empty() {
        url_of(&to.registration_id).await.unwrap_or_default()
    } else {
        to.transport_details.url.clone()
    };
    let Some((http, token)) = client().await else { return };
    let seq = {
        let mut s = state();
        s.seq += 1;
        s.seq
    };
    let msg = me.message(command::RESPONSE, &bt::response_details(to, ok, result), seq);
    match bt::send(&http, &token, &url, &msg).await {
        Ok((status, _)) => tracing::info!(to = %to.command, ok, status, "Better Together: response sent"),
        Err(e) => tracing::info!("Better Together: response to {}: {e:#}", to.command),
    }
}

/// Teams' checkProximity: hear the phone (the user's beacon matching its
/// endpoint) within 15 s, and learn its salt. Wired phones are near.
async fn check_proximity(id: &str, signature: Option<i64>, wired: bool) -> bool {
    if wired {
        return true;
    }
    let oid = match TeamsClient::new().await.ok().and_then(|c| c.object_id()) {
        Some(o) => o.to_ascii_lowercase(),
        None => return false,
    };
    let since = Instant::now();
    crate::room_ble::set_companion_scanning(true);
    let deadline = since + Duration::from_secs(bt::PROXIMITY_SCAN_SECS);
    let found = loop {
        if let Some(c) = crate::room_ble::companions()
            .into_iter()
            .find(|(c, at)| *at >= since && c.oid == oid && c.matches(id, signature))
            .map(|(c, _)| c)
        {
            break Some(c);
        }
        if Instant::now() >= deadline {
            break None;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    };
    crate::room_ble::set_companion_scanning(false);
    match found {
        Some(c) => {
            if let Some(salt) = c.salt {
                let mut s = state();
                if s.salt != salt {
                    tracing::info!("Better Together: salt updated");
                    s.salt = salt;
                }
            }
            tracing::info!(rssi = c.rssi, "Better Together: phone nearby");
            true
        }
        None => {
            tracing::info!("Better Together: phone not heard nearby");
            false
        }
    }
}

async fn on_command(m: Message) {
    let details = m.details();
    let id = m.registration_id.clone();
    if !m.transport_details.url.is_empty() {
        state().urls.insert(id.clone(), m.transport_details.url.clone());
    }
    let wired = bt::connection_type(&details) == bt::CONNECTION_WIRED;
    let signature = details.get("endpointSignature").and_then(|v| v.as_i64());
    tracing::info!(command = %m.command, "Better Together: command");
    match m.name().as_str() {
        command::RESPONSE => {
            let cause = details.get("requestCauseId").and_then(|v| v.as_str()).unwrap_or_default().to_string();
            if let Some(tx) = state().waiting.remove(&cause) {
                let _ = tx.send(details);
            }
        }
        command::BROADCAST => {
            if check_proximity(&id, signature, wired).await {
                let mut r = response_salt();
                r["deviceName"] = bt::os_name().into();
                respond(&m, true, r).await;
            } else {
                let mut r = response_salt();
                r["errorCode"] = bt::ERROR_NOT_IN_PROXIMITY.into();
                respond(&m, false, r).await;
            }
        }
        command::PAIR => on_pair(m, details, wired, signature).await,
        command::UNPAIR => {
            let known = forget(&id);
            let mut r = response_salt();
            if !known {
                r["errorCode"] = bt::ERROR_NOT_PAIRED.into();
            }
            respond(&m, known, r).await;
        }
        command::AUTOPAIR => {
            if check_proximity(&id, signature, wired).await && set_status(&id, bt::STATUS_CONNECTED) {
                state().misses.remove(&id);
                respond(&m, true, response_salt()).await;
            } else {
                let mut r = response_salt();
                r["errorCode"] = bt::ERROR_NOT_IN_PROXIMITY.into();
                respond(&m, false, r).await;
            }
        }
        command::LOCKED | command::UNLOCKED => {
            let status = if m.name() == command::LOCKED { bt::STATUS_LOCKED } else { bt::STATUS_CONNECTED };
            let ok = set_status(&id, status);
            let mut r = response_salt();
            if !ok {
                r["errorCode"] = bt::ERROR_NOT_PAIRED.into();
            }
            respond(&m, ok, r).await;
        }
        command::UPDATE_ENDPOINT => {
            let prev = details.get("previousEndpointId").and_then(|v| v.as_str()).unwrap_or(&id).to_string();
            let new_id = details.get("newEndpointId").and_then(|v| v.as_str()).unwrap_or(&id).to_string();
            let ok = {
                let mut s = state();
                match s.devices.iter_mut().find(|d| d.end_point_id == prev) {
                    Some(d) => {
                        d.end_point_id = new_id;
                        if let Some(n) = details.get("newEndpointDetails") {
                            let fresh = PairedDevice::from_pair(&d.end_point_id, n);
                            d.device_name = fresh.device_name;
                            d.client_type = fresh.client_type;
                            d.client_version = fresh.client_version;
                            d.endpoint_signature = fresh.endpoint_signature;
                        }
                        true
                    }
                    None => false,
                }
            };
            if ok {
                changed();
            }
            respond(&m, ok, response_salt()).await;
        }
        _ => {
            let mut r = response_salt();
            r["errorCode"] = "INVALID_COMMAND".into();
            respond(&m, false, r).await;
        }
    }
}

/// Teams' pair command (V9e): proximity, then the user's answer.
async fn on_pair(m: Message, details: serde_json::Value, wired: bool, signature: Option<i64>) {
    let id = m.registration_id.clone();
    let current = state().salt;
    let near = wired || bt::salt_matches(&details, current) || check_proximity(&id, signature, wired).await;
    if !near {
        let mut r = response_salt();
        r["errorCode"] = bt::ERROR_NOT_IN_PROXIMITY.into();
        respond(&m, false, r).await;
        return;
    }
    let name = details.get("deviceName").and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let (tx, rx) = tokio::sync::oneshot::channel();
    let busy = {
        let mut s = state();
        let busy = s.prompt.is_some();
        if !busy {
            s.prompt = Some(tx);
        }
        busy
    };
    if busy {
        let mut r = response_salt();
        r["errorCode"] = "Pairing request already pending".into();
        respond(&m, false, r).await;
        return;
    }
    if let Some(qt) = QT.get() {
        let n = name.clone();
        let _ = qt.queue(move |mut this| this.as_mut().better_together_pair_request(cxx_qt_lib::QString::from(n.as_str())));
    }
    let answer = tokio::time::timeout(Duration::from_secs(bt::PAIR_PROMPT_SECS), rx).await;
    state().prompt = None;
    let outcome = match answer {
        Ok(Ok(true)) => None,
        Ok(_) => Some(bt::REJECTED_BY_USER),
        Err(_) => Some(bt::REJECTED_BY_TIMEOUT),
    };
    if let Some(qt) = QT.get() {
        let _ = qt.queue(|mut this| this.as_mut().better_together_pair_request(cxx_qt_lib::QString::default()));
    }
    let mut r = response_salt();
    match outcome {
        None => {
            let device = PairedDevice::from_pair(&id, &details);
            {
                let mut s = state();
                s.devices.retain(|d| d.end_point_id != id);
                s.devices.push(device);
                s.misses.remove(&id);
            }
            tracing::info!("Better Together: phone paired");
            changed();
            r["accepted"] = true.into();
            respond(&m, true, r).await;
        }
        Some(why) => {
            tracing::info!(why, "Better Together: pairing turned down");
            r["accepted"] = false.into();
            r["errorCode"] = why.into();
            respond(&m, false, r).await;
        }
    }
}

/// The user's answer to the pairing prompt (Connect / Cancel).
pub fn answer(accept: bool) {
    if let Some(tx) = state().prompt.take() {
        let _ = tx.send(accept);
    }
}

/// Teams' onDeviceUnpaired.
fn forget(id: &str) -> bool {
    let known = {
        let mut s = state();
        let before = s.devices.len();
        s.devices.retain(|d| d.end_point_id != id);
        s.misses.remove(id);
        s.devices.len() != before
    };
    if known {
        tracing::info!("Better Together: phone unpaired");
        changed();
    }
    known
}

/// Manage devices' Disconnect (Teams' unpairDevice): tell the phone and
/// forget it at once.
pub fn unpair(id: String) {
    if !state().devices.iter().any(|d| d.end_point_id == id) {
        return;
    }
    let salt = response_salt();
    forget(&id);
    runtime().spawn(async move {
        if let Err(e) = send(&id, command::UNPAIR, salt, None).await {
            tracing::info!("Better Together: unpair: {e}");
        }
    });
}

/// Every 30 s: a keep-alive to each connected phone that's near (two
/// misses disconnect it, Teams' onProximityLost); a paired phone that's
/// disconnected and heard again is reconnected (keepalive, unlock).
async fn keep_alive_round() {
    let devices = state().devices.clone();
    for d in devices {
        let wired = d.connection_type == bt::CONNECTION_WIRED;
        let near = check_proximity(&d.end_point_id, d.endpoint_signature, wired).await;
        let reply = if near {
            send(&d.end_point_id, command::KEEP_ALIVE, response_salt(), Some(Duration::from_secs(60))).await
        } else {
            Err("not near".into())
        };
        // The phone no longer knows this PC (Teams' remove-out-of-sync
        // pairing): forget it here too.
        if let Err(e) = &reply
            && e.contains("\"NotPaired\"")
        {
            forget(&d.end_point_id);
            continue;
        }
        let alive = reply.is_ok();
        if d.connected() {
            if alive {
                state().misses.remove(&d.end_point_id);
                continue;
            }
            let misses = {
                let mut s = state();
                let n = s.misses.entry(d.end_point_id.clone()).or_insert(0);
                *n += 1;
                *n
            };
            if misses >= 2 {
                tracing::info!("Better Together: proximity lost");
                state().misses.remove(&d.end_point_id);
                // Teams' disconnect: a lock command, Locked once the phone
                // has it.
                let locked = send(&d.end_point_id, command::LOCK, response_salt(), None).await.is_ok();
                set_status(&d.end_point_id, if locked { bt::STATUS_LOCKED } else { bt::STATUS_PAIRED_NOT_CONNECTED });
            }
        } else if alive && send(&d.end_point_id, command::UNLOCK, response_salt(), Some(Duration::from_secs(60))).await.is_ok() {
            tracing::info!("Better Together: reconnected");
            set_status(&d.end_point_id, bt::STATUS_CONNECTED);
        }
    }
}
