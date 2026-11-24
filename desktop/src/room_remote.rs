//! Teams' room remote ("Control Room System") on the desktop
//! (`teams_cli::api::room_remote`): the room's side, as Teams Rooms does
//! it (RemoteControllerSessionManager, RemoteControllerConnectionHandler,
//! the RemoteControllerIncomingCommandFactory's commands and
//! RemoteControllerCallState).
//!
//! - A session for the meeting the room is in is accepted (only while
//!   it's in that meeting).
//! - `pair` is taken when it carries one of the room's recent beacon salts;
//!   the answer names the room, what a remote may do and the room's state.
//! - A paired remote's commands work the room's own controls: mic, camera,
//!   captions, speaker volume (steps of 10; the lowest step mutes the
//!   speaker), the stage layout and leaving the meeting.
//! - The room tells its remotes when its state or its controls change.
//!
//! And the controller's side (Teams' CallRoomRemoteWrapper and
//! RemoteControllerSessionManager.createSession): Control Room System scans
//! for the room's beacon, starts a session with the room's account, waits
//! for the room to accept, pairs with the beacon's salt and shows the
//! room's remote; its buttons send the room commands, the room's updates
//! redraw it, and closing it ends the session (DELETE on the session).
//! Messages go through the call controller: each side posts to the active
//! session's `broadcast` link, which relays them to the other side's
//! `receive` link.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use cxx_qt_lib::QString;
use teams_cli::api::better_together::{self as bt, Message};
use teams_cli::api::client::TeamsClient;
use teams_cli::api::room_remote::{self as rr, Capabilities, RoomState, command, layout};
use teams_cli::event_hub::EventKind;

use crate::backend::{qobject, runtime};

type Qt = cxx_qt::CxxQtThread<qobject::Backend>;

static QT: std::sync::OnceLock<Qt> = std::sync::OnceLock::new();

/// One remote session the room accepted.
#[derive(Debug, Clone, Default)]
struct RoomSession {
    /// The controller's endpoint id.
    controller: String,
    /// Where our messages go: the session's broadcast link at the
    /// service, which relays them to the controller.
    url: String,
    /// The controller's chain id for the session.
    chain: String,

    paired: bool,
}

#[derive(Default)]
struct RoomSide {
    /// By session id.
    sessions: HashMap<String, RoomSession>,
    seq: u64,
    /// What the paired remotes were last told.
    told_state: Option<RoomState>,
    told_caps: Option<Capabilities>,
}

static ROOM: std::sync::LazyLock<Mutex<RoomSide>> = std::sync::LazyLock::new(Default::default);

fn room() -> std::sync::MutexGuard<'static, RoomSide> {
    ROOM.lock().unwrap_or_else(|e| e.into_inner())
}

/// Run `f` on the Qt thread and wait for its result.
async fn on_qt<T: Send + 'static>(f: impl FnOnce(std::pin::Pin<&mut qobject::Backend>) -> T + Send + 'static) -> Option<T> {
    let qt = QT.get()?;
    let (tx, rx) = tokio::sync::oneshot::channel();
    qt.queue(move |this| {
        let _ = tx.send(f(this));
    })
    .ok()?;
    rx.await.ok()
}

async fn client() -> Option<(reqwest::Client, String)> {
    let c = TeamsClient::new().await.ok()?;
    let token = c.skype_token_value().ok()?;
    Some((c.http().clone(), token))
}

/// Start listening for room remote sessions and their messages.
pub fn start(qt: Qt) {
    if QT.set(qt).is_err() {
        return;
    }
    let mut events = teams_cli::event_hub::subscribe();
    runtime().spawn(async move {
        use tokio::sync::broadcast::error::RecvError;
        loop {
            match events.recv().await {
                Ok(ev) if ev.kind == EventKind::Call && ev.json.contains("\"sessionNotification\"") => {
                    if let Some(s) = rr::incoming_session(&ev.json) {
                        tokio::spawn(on_incoming_session(s));
                    }
                }
                Ok(ev) if ev.kind == EventKind::RoomRemote => {
                    tokio::spawn(on_message(ev.json));
                }
                Ok(_) | Err(RecvError::Lagged(_)) => {}
                Err(RecvError::Closed) => return,
            }
        }
    });
    // The room tells its remotes of changes (Teams Rooms sends them as its
    // controls change).
    runtime().spawn(async {
        loop {
            tokio::time::sleep(Duration::from_millis(500)).await;
            if room().sessions.values().any(|s| s.paired) {
                tell_changes().await;
            }
        }
    });
}

// ---- The room's side ----

/// The room's controls as a remote sees them.
async fn room_now() -> Option<(RoomState, Capabilities, String)> {
    let captions = crate::backend::call_has_captions().await;
    on_qt(move |this| {
        let sharing = *this.room_remote_content();
        let current = this.room_remote_layout().to_string();
        let video_allowed = crate::room_host::settings().video_allowed;
        let mut layouts = vec![layout::GALLERY.to_string()];
        if sharing {
            layouts.push(layout::CONTENT.to_string());
            layouts.push(layout::CONTENT_AND_GALLERY.to_string());
        }
        let shown = match (current.as_str(), sharing) {
            ("focus", true) => layout::CONTENT,
            (_, true) => layout::CONTENT_AND_GALLERY,
            _ => layout::GALLERY,
        };
        let state = RoomState {
            muted: *this.call_muted() || !*this.call_has_audio(),
            camera: *this.call_camera_on(),
            captions: *this.call_captions_on(),
            layout: shown.to_string(),
        };
        let caps = Capabilities { mute: true, camera: video_allowed, captions, layouts };
        (state, caps, this.call_state().to_string())
    })
    .await
}

/// The room's side (Teams Rooms' onProxiedPushNotificaton and
/// RemoteControllerSessionManager.addSession): a session for the meeting
/// the room is in is accepted.
async fn on_incoming_session(s: rr::IncomingSession) {
    tracing::info!(command = %s.command, "room remote: incoming session");
    if !teams_cli::calling::room_mode::is_active() {
        tracing::info!("room remote: not a room, session ignored");
        return;
    }
    let Some((state, thread)) = on_qt(|this| (this.call_state().to_string(), this.call_thread_id().to_string())).await else {
        return;
    };
    if state != "connected" || thread != s.thread_id {
        tracing::info!(%state, same_meeting = (thread == s.thread_id), "room remote: not in that meeting, session ignored");
        return;
    }
    let Some((surl, _)) = teams_cli::trouter::current_endpoint() else { return };
    let Some(session) = rr::session_id_of(&s.accept) else {
        tracing::info!("room remote: no session id in the accept link");
        return;
    };
    let Some((http, token)) = client().await else { return };
    let debug = rr::Debug { chain_id: s.chain_id.clone(), cause_id: rr::teams_id() };
    let me = teams_cli::trouter::registrar::calling_registration_id();
    let body = rr::acceptance_body(&rr::session_link(&surl, &session, "receive"), &rr::session_link(&surl, &session, "end"), me, &debug);
    room().sessions.insert(session.clone(), RoomSession { controller: s.controller_endpoint.clone(), chain: s.chain_id.clone(), ..Default::default() });
    match rr::post(&http, &token, &s.accept, &body, &s.chain_id).await {
        Ok((status, reply)) if (200..300).contains(&status) => {
            tracing::info!(status, "room remote: session accepted");
            tracing::debug!(%reply, "room remote: acceptance reply");
            let links = serde_json::from_str(&reply).ok().and_then(|v| rr::active_links(&v));
            if let (Some(sess), Some((broadcast, _))) = (room().sessions.get_mut(&session), links) {
                sess.url = broadcast;
            }
        }
        Ok((status, reply)) => {
            tracing::info!(status, "room remote: acceptance turned down");
            tracing::debug!(%reply, "room remote: acceptance reply");
            room().sessions.remove(&session);
        }
        Err(e) => {
            tracing::info!("room remote: accepting failed: {e:#}");
            room().sessions.remove(&session);
        }
    }
}

/// A message on one of our session links, or a session command on the
/// Better Together path.
async fn on_message(json: String) {
    let v: serde_json::Value = serde_json::from_str(&json).unwrap_or_default();
    let url = v.get("url").and_then(|u| u.as_str()).unwrap_or_default().to_string();
    let body = v.get("body").cloned().unwrap_or_default();
    let path = url.split("/bettertogether").nth(1).unwrap_or_default().to_string();
    tracing::info!(%path, command = ?body.get("command"), "room remote: message");
    tracing::debug!(%body, "room remote: message body");
    let session = path.strip_prefix("/session/").and_then(|p| p.split('/').next()).map(str::to_string);
    // Ours as the controller: our session's links, or the paired room.
    let ours = {
        let r = remote();
        let from = body.get("registrationId").and_then(|f| f.as_str()).unwrap_or_default();
        (!r.session.is_empty() && session.as_deref() == Some(r.session.as_str()))
            || (session.is_none() && !r.room_endpoint.is_empty() && from == r.room_endpoint)
    };
    if ours {
        controller_message(&path, body).await;
        return;
    }
    if path.ends_with("/end") {
        if let Some(id) = &session {
            tracing::info!("room remote: session ended");
            room().sessions.remove(id);
        }
        return;
    }
    let Ok(m) = serde_json::from_value::<Message>(body.clone()) else { return };
    if teams_cli::calling::room_mode::is_active() {
        room_command(session, m).await;
    }
}

/// The session a command belongs to: the link it came to, else the one
/// with its sender.
fn session_of(link: Option<String>, m: &Message) -> Option<String> {
    let r = room();
    link.filter(|id| r.sessions.contains_key(id))
        .or_else(|| r.sessions.iter().find(|(_, s)| s.controller == m.registration_id).map(|(id, _)| id.clone()))
}

async fn room_command(link: Option<String>, m: Message) {
    let Some(id) = session_of(link, &m) else {
        tracing::info!(command = %m.command, "room remote: command outside a session");
        return;
    };
    if let Some(s) = room().sessions.get_mut(&id) {
        if !m.debug_content.chain_id.is_empty() {
            s.chain = m.debug_content.chain_id.clone();
        }
    }
    let name = m.name();
    if name == command::RESPONSE {
        return;
    }
    if name == command::PAIR {
        pair(&id, &m).await;
        return;
    }
    if name == command::UNPAIR {
        if let Some(s) = room().sessions.get_mut(&id) {
            s.paired = false;
        }
        respond(&id, &m, Ok(serde_json::json!({}))).await;
        return;
    }
    if !room().sessions.get(&id).is_some_and(|s| s.paired) {
        respond(&id, &m, Err((bt::ERROR_NOT_PAIRED, "Device is not paired".to_string()))).await;
        return;
    }
    let result = run_command(&name).await;
    respond(&id, &m, result).await;
}

/// Teams Rooms' RemoteControllerPairCommand.
async fn pair(id: &str, m: &Message) {
    let details = m.details();
    let salt = details.get("salt").and_then(|s| s.as_array()).and_then(|a| a.first()).and_then(|v| v.as_u64()).unwrap_or(0);
    let valid = crate::room_host::salt_valid((salt & 0xffff) as u32);
    tracing::info!(valid, "room remote: pairing");
    if !valid {
        respond(id, m, Err(("INVALID_SALT", "Invalid salt received".to_string()))).await;
        return;
    }
    let Some((state, caps, _)) = room_now().await else { return };
    let config = teams_cli::config::Config::load().ok();
    let name = config.as_ref().and_then(|c| c.display_name()).unwrap_or_default();
    let info = rr::RoomInfo {
        client_type: "desktop".into(),
        client_version: format!("{}/{}", env!("CARGO_PKG_VERSION"), env!("CARGO_PKG_VERSION")),
        device_name: hostname(),
        endpoint_id: teams_cli::trouter::registrar::calling_registration_id().to_string(),
        user_display_name: name,
        user_object_id: config.and_then(|c| c.object_id()).unwrap_or_default(),
    };
    if let Some(s) = room().sessions.get_mut(id) {
        s.paired = true;
    }
    {
        let mut r = room();
        r.told_state = Some(state.clone());
        r.told_caps = Some(caps.clone());
    }
    respond(id, m, Ok(rr::pair_result(&info, &caps, &state))).await;
}

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname").map(|h| h.trim().to_string()).unwrap_or_default()
}

/// Work one of the room's controls (Teams Rooms' command classes).
async fn run_command(name: &str) -> Result<serde_json::Value, (&'static str, String)> {
    let Some((state, caps, call)) = room_now().await else { return Err(("OPERATION_FAILED", "No room".into())) };
    if call != "connected" {
        return Err(("NO_ACTIVE_CALL", "No active call going on.".into()));
    }
    fn lower(s: &str) -> String {
        s.to_ascii_lowercase()
    }
    let already = |what: &str| Err(("STATE_ALREADY_SET", format!("State already set {what}")));
    let not_allowed = || Err(("ACTION_NOT_ALLOWED", format!("Action is disabled for current command={name}.")));
    let ok = Ok(serde_json::json!({}));
    if name == lower(command::MUTE) || name == lower(command::UNMUTE) {
        if !caps.mute {
            return not_allowed();
        }
        let mute = name == lower(command::MUTE);
        if state.muted == mute {
            return already("mute");
        }
        on_qt(move |this| this.room_remote_set_muted(mute)).await;
        return ok;
    }
    if name == lower(command::CAMERA_ON) || name == lower(command::CAMERA_OFF) {
        if !caps.camera {
            return not_allowed();
        }
        let on = name == lower(command::CAMERA_ON);
        if state.camera == on {
            return already("camera");
        }
        on_qt(|this| this.toggle_camera()).await;
        return ok;
    }
    if name == lower(command::CAPTIONS_ON) || name == lower(command::CAPTIONS_OFF) {
        if !caps.captions {
            return not_allowed();
        }
        let on = name == lower(command::CAPTIONS_ON);
        if state.captions == on {
            return already("captions");
        }
        on_qt(move |this| this.set_captions(on)).await;
        return ok;
    }
    if name == lower(command::VOLUME_UP) || name == lower(command::VOLUME_DOWN) {
        let up = name == lower(command::VOLUME_UP);
        on_qt(move |this| this.room_remote_volume(up)).await;
        return ok;
    }
    if name == lower(command::LEAVE_MEETING) {
        // Teams Rooms unpairs its remotes, then leaves.
        let ids: Vec<String> = room().sessions.iter().filter(|(_, s)| s.paired).map(|(id, _)| id.clone()).collect();
        for id in ids {
            send(&id, command::UNPAIR, serde_json::json!({})).await;
            if let Some(s) = room().sessions.get_mut(&id) {
                s.paired = false;
            }
        }
        on_qt(|this| this.hang_up()).await;
        return ok;
    }
    if let Some(l) = layout::ALL.iter().find(|l| lower(l) == name) {
        if *l != layout::GALLERY && !caps.layouts.iter().any(|x| x == l) {
            return not_allowed();
        }
        let view = match *l {
            layout::CONTENT => "focus",
            _ => "gallery",
        };
        on_qt(move |this| this.room_remote_layout_requested(QString::from(view))).await;
        return ok;
    }
    Err(("INVALID_COMMAND_REQUEST", format!("Received unexpected command subtype on this command: {name}")))
}

/// Answer a command with Teams' `response` (its result, `requestCauseId`
/// and `statusCode`; a failure carries `errorCode` and `errorDetails`).
async fn respond(id: &str, m: &Message, result: Result<serde_json::Value, (&str, String)>) {
    let details = match result {
        Ok(r) => bt::response_details(m, true, r),
        Err((code, why)) => {
            tracing::info!(command = %m.command, code, "room remote: command failed");
            bt::response_details(m, false, serde_json::json!({ "errorCode": code, "errorDetails": why }))
        }
    };
    send(id, command::RESPONSE, details).await;
}

/// Send a session's controller one message.
async fn send(id: &str, name: &str, details: serde_json::Value) -> bool {
    let (url, seq, chain) = {
        let mut r = room();
        r.seq += 1;
        let seq = r.seq;
        match r.sessions.get(id) {
            Some(s) if !s.url.is_empty() => (s.url.clone(), seq, s.chain.clone()),
            _ => {
                tracing::info!(name, "room remote: no link to the controller");
                return false;
            }
        }
    };
    let Some((http, token)) = client().await else { return false };
    let me = teams_cli::trouter::registrar::calling_registration_id();
    let msg = rr::session_message(me, name, &details, seq, &chain);
    tracing::debug!(%msg, "room remote: sending");
    match rr::post(&http, &token, &url, &msg, &chain).await {
        Ok((status, body)) => {
            tracing::info!(name, status, "room remote: sent");
            tracing::debug!(%body, "room remote: send reply");
            (200..300).contains(&status)
        }
        Err(e) => {
            tracing::info!(name, "room remote: sending failed: {e:#}");
            false
        }
    }
}

/// Tell the paired remotes what changed (Teams Rooms' capabilityUpdate,
/// then stateUpdate).
async fn tell_changes() {
    let Some((state, caps, _)) = room_now().await else { return };
    let (caps_update, state_changed) = {
        let r = room();
        let cu = r.told_caps.as_ref().and_then(|c| caps.update_from(c));
        (cu, r.told_state.as_ref() != Some(&state))
    };
    if caps_update.is_none() && !state_changed {
        return;
    }
    {
        let mut r = room();
        r.told_caps = Some(caps.clone());
        r.told_state = Some(state.clone());
    }
    let ids: Vec<String> = room().sessions.iter().filter(|(_, s)| s.paired).map(|(id, _)| id.clone()).collect();
    for id in ids {
        if let Some(u) = &caps_update {
            send(&id, command::CAPABILITY_UPDATE, u.clone()).await;
        }
        send(&id, command::STATE_UPDATE, state.to_json()).await;
    }
}

// ---- The controller's side ----

/// The remote this OST controls (Teams' CallRoomRemoteWrapper state).
#[derive(Default)]
struct Remote {
    /// Bumped per Control Room System and on close, so a late answer of an
    /// older one is dropped.
    generation: u64,
    /// Our session id (its links' segment).
    session: String,
    /// The session's chain id (Teams' session id: `t` + a GUID).
    chain: String,
    /// The meeting's chat.
    thread: String,
    /// The service's link for the session (cancel before it's accepted,
    /// then the active session: its end).
    outgoing: String,
    /// The active session's broadcast link: our messages to the room.
    broadcast: String,
    /// The room's endpoint id.
    room_endpoint: String,
    caps: Capabilities,
    state: RoomState,
    room_name: String,
    seq: u64,
    /// The session's acceptance, once pushed.
    accepted: Option<tokio::sync::oneshot::Sender<serde_json::Value>>,
    /// Responses awaited, by the command's cause id.
    waiting: HashMap<String, tokio::sync::oneshot::Sender<serde_json::Value>>,
}

static REMOTE: std::sync::LazyLock<Mutex<Remote>> = std::sync::LazyLock::new(Default::default);

fn remote() -> std::sync::MutexGuard<'static, Remote> {
    REMOTE.lock().unwrap_or_else(|e| e.into_inner())
}

/// Teams' roomRemoteTimeout when ECS sets none (120 s), and its
/// roomRemoteScanTimeout (15 s).
const REMOTE_TIMEOUT: Duration = Duration::from_secs(120);
const SCAN_TIMEOUT: Duration = Duration::from_secs(15);

/// What the Room Remote pane shows (JSON): {view: "loading" | "remote" |
/// "error" | "left", error, roomName, caps: {mediaControls,
/// stageLayoutControls, meetingControls}, state: {toggleMute, toggleCamera,
/// toggleCaptions, stageLayout}}.
fn publish(view: &str, error: Option<u8>) {
    let json = {
        let r = remote();
        serde_json::json!({
            "view": view,
            "error": error.map(i64::from).unwrap_or(-1),
            "roomName": r.room_name,
            "caps": r.caps.to_json(),
            "state": r.state.to_json(),
        })
        .to_string()
    };
    if let Some(qt) = QT.get() {
        let _ = qt.queue(move |mut this| this.as_mut().set_room_remote_json(QString::from(json.as_str())));
    }
}

/// Teams' checkRoomProximity: scan (up to 15 s) for the room's beacon and
/// take its proximity code as the salt.
async fn room_salt(room_mri: &str) -> Option<u16> {
    crate::room_ble::set_remote_scanning(true);
    let started = std::time::Instant::now();
    let found = loop {
        let (_, rooms) = crate::room_ble::snapshot();
        if let Some(code) = rooms.iter().find(|b| b.mri.eq_ignore_ascii_case(room_mri)).and_then(|b| b.code) {
            break Some(code);
        }
        if started.elapsed() >= SCAN_TIMEOUT {
            break None;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    };
    crate::room_ble::set_remote_scanning(false);
    found
}

/// Control Room System (Teams' createRoomRemoteSession): reach the room
/// over a session, pair with it, show its remote.
pub fn open(room_mri: String, room_name: String, thread_id: String) {
    let generation = {
        let mut r = remote();
        r.generation += 1;
        r.room_name = room_name;
        r.thread = thread_id.clone();
        r.caps = Capabilities::default();
        r.state = RoomState::default();
        r.room_endpoint.clear();
        r.outgoing.clear();
        r.broadcast.clear();
        r.generation
    };
    publish("loading", None);
    runtime().spawn(async move {
        let result = tokio::time::timeout(REMOTE_TIMEOUT, connect(room_mri, thread_id, generation)).await;
        if remote().generation != generation {
            return;
        }
        match result {
            Ok(Ok(())) => publish("remote", None),
            Ok(Err(code)) => {
                end_session(generation).await;
                publish("error", Some(code));
            }
            Err(_) => {
                tracing::info!("room remote: timed out");
                end_session(generation).await;
                publish("error", Some(rr::error::CONNECTION_FAILED));
            }
        }
    });
}

async fn connect(room_mri: String, thread_id: String, generation: u64) -> Result<(), u8> {
    let Some(salt) = room_salt(&room_mri).await else {
        tracing::info!("room remote: the room isn't nearby");
        return Err(rr::error::OUT_OF_PROXIMITY);
    };
    let Some((surl, _)) = teams_cli::trouter::current_endpoint() else { return Err(rr::error::CONNECTION_FAILED) };
    let Some((http, token)) = client().await else { return Err(rr::error::CONNECTION_FAILED) };
    let config = teams_cli::config::Config::load().ok();
    let me = config.as_ref().and_then(|c| c.object_id()).map(|o| format!("8:orgid:{o}")).unwrap_or_default();
    let my_name = config.as_ref().and_then(|c| c.display_name()).unwrap_or_default();
    let my_endpoint = teams_cli::trouter::registrar::calling_registration_id().to_string();
    let session = uuid::Uuid::new_v4().to_string();
    let chain = rr::teams_id();
    let links = rr::SessionLinks::on(&surl, &session);
    let (tx, rx) = tokio::sync::oneshot::channel();
    {
        let mut r = remote();
        r.session = session.clone();
        r.chain = chain.clone();
        r.accepted = Some(tx);
    }
    let debug = rr::Debug { chain_id: chain.clone(), cause_id: rr::teams_id() };
    let body = rr::invitation_body(&me, &my_name, &my_endpoint, &room_mri, &links, &thread_id, &debug);
    match rr::post(&http, &token, rr::SESSIONS_URL, &body, &debug.chain_id).await {
        Ok((status, reply)) if (200..300).contains(&status) => {
            tracing::info!(status, "room remote: session started");
            tracing::debug!(%reply, "room remote: session reply");
            if let Some(link) = rr::outgoing_link_in(&reply) {
                remote().outgoing = link;
            }
        }
        Ok((status, reply)) => {
            tracing::info!(status, "room remote: session refused");
            tracing::debug!(%reply, "room remote: session reply");
            return Err(rr::error::CONNECTION_FAILED);
        }
        Err(e) => {
            tracing::info!("room remote: starting the session failed: {e:#}");
            return Err(rr::error::CONNECTION_FAILED);
        }
    }
    // The room's acceptance: its endpoint and link.
    let accepted = rx.await.map_err(|_| rr::error::CONNECTION_FAILED)?;
    tracing::debug!(%accepted, "room remote: acceptance");
    let endpoint = rr::acceptance_of(&accepted).ok_or(rr::error::CONNECTION_FAILED)?;
    tracing::info!("room remote: the room accepted");
    {
        let mut r = remote();
        if r.generation != generation {
            return Err(rr::error::CONNECTION_FAILED);
        }
        r.room_endpoint = endpoint.clone();
        // From here the active session's links at the service carry our
        // messages (broadcast) and its end (session).
        if let Some((broadcast, session)) = rr::active_links(&accepted) {
            r.broadcast = broadcast;
            r.outgoing = session;
        }
    }
    // Teams checks the room is still near, then pairs with its salt.
    let Some(salt) = room_salt(&room_mri).await.or(Some(salt)) else { return Err(rr::error::OUT_OF_PROXIMITY) };
    let details = serde_json::json!({
        "causeId": rr::teams_id(),
        "commandName": command::PAIR,
        "sessionId": chain,
        "targetEndpointId": endpoint,
        "companionResponseRequired": true,
        "sequenceNumber": 1,
        "controllerEndpointInfo": {
            "endpointId": my_endpoint,
            "deviceName": hostname(),
            "clientType": "default",
            "clientVersion": env!("CARGO_PKG_VERSION"),
        },
        "meetingInfo": { "threadId": thread_id },
        "salt": [salt],
    });
    let reply = command_to_room(command::PAIR, details).await.ok_or(rr::error::PAIRING_FAILED)?;
    if reply.get("statusCode").and_then(|s| s.as_u64()) != Some(200) || reply.get("accepted").and_then(|a| a.as_bool()) == Some(false) {
        tracing::info!(code = ?reply.get("errorCode"), "room remote: pairing refused");
        return Err(rr::error::PAIRING_FAILED);
    }
    let mut r = remote();
    r.caps = Capabilities::from_json(reply.get("supportedCapabilities").unwrap_or(&serde_json::Value::Null));
    r.state = RoomState::from_json(reply.get("initialState").unwrap_or(&serde_json::Value::Null));
    if let Some(n) = reply.pointer("/roomEndpointInfo/userDisplayName").and_then(|n| n.as_str()).filter(|n| !n.is_empty()) {
        r.room_name = n.to_string();
    }
    tracing::info!("room remote: paired");
    Ok(())
}

/// Send the room a command and wait (20 s) for its response.
async fn command_to_room(name: &str, details: serde_json::Value) -> Option<serde_json::Value> {
    let (url, seq, chain) = {
        let mut r = remote();
        r.seq += 1;
        // The session's broadcast link at the service relays to the room.
        (r.broadcast.clone(), r.seq, r.chain.clone())
    };
    if url.is_empty() {
        return None;
    }
    let (http, token) = client().await?;
    let me = teams_cli::trouter::registrar::calling_registration_id();
    let msg = rr::session_message(me, name, &details, seq, &chain);
    let cause = msg.pointer("/debugContent/causeId").and_then(|c| c.as_str()).unwrap_or_default().to_string();
    let (tx, rx) = tokio::sync::oneshot::channel();
    remote().waiting.insert(cause.clone(), tx);
    let sent = match rr::post(&http, &token, &url, &msg, &chain).await {
        Ok((status, body)) => {
            tracing::info!(name, status, "room remote: command sent");
            tracing::debug!(%body, "room remote: command ack");
            (200..300).contains(&status)
        }
        Err(e) => {
            tracing::info!(name, "room remote: sending failed: {e:#}");
            false
        }
    };
    let reply = if sent { tokio::time::timeout(Duration::from_secs(20), rx).await.ok().and_then(|r| r.ok()) } else { None };
    if reply.is_none() {
        remote().waiting.remove(&cause);
    }
    reply
}

/// A button on the remote (Teams' sendCommandToPairedMeetingRoom).
pub fn command(name: String) {
    let generation = remote().generation;
    runtime().spawn(async move {
        // As Teams sends them (its RemoteControllerOutgoingCommand).
        let details = {
            let r = remote();
            serde_json::json!({
                "callId": "",
                "companionResponseRequired": true,
                "conversationId": r.thread,
                "endpointId": "",
                "targetEndpointId": r.room_endpoint,
            })
        };
        let reply = command_to_room(&name, details).await;
        if remote().generation != generation {
            return;
        }
        match reply {
            Some(r) if r.get("statusCode").and_then(|s| s.as_u64()) == Some(200) => {
                if name == command::LEAVE_MEETING {
                    // The room left: Teams closes the panel.
                    end_session(generation).await;
                    publish("left", None);
                } else {
                    publish("remote", None);
                }
            }
            other => {
                tracing::info!(name = %name, code = ?other.as_ref().and_then(|r| r.get("errorCode").cloned()), "room remote: command failed");
                publish("error", Some(rr::error::COMMAND_FAILED));
            }
        }
    });
}

/// End the session (Teams' endRoomRemoteSession).
async fn end_session(generation: u64) {
    let outgoing = {
        let mut r = remote();
        if r.generation != generation {
            return;
        }
        r.broadcast.clear();
        std::mem::take(&mut r.outgoing)
    };
    if outgoing.is_empty() {
        return;
    }
    let Some((http, token)) = client().await else { return };
    let (seq, chain) = {
        let mut r = remote();
        r.seq += 1;
        (r.seq, r.chain.clone())
    };
    let debug = rr::Debug { chain_id: chain, cause_id: rr::teams_id() };
    let me = teams_cli::trouter::registrar::calling_registration_id();
    let body = rr::end_body(me, seq, &debug);
    // DELETE on the session (live: the room's `end` link got it relayed;
    // a POST to the session was taken and went nowhere).
    match rr::send(&http, reqwest::Method::DELETE, &token, &outgoing, &body, &debug.chain_id).await {
        Ok((status, reply)) => {
            tracing::info!(status, "room remote: session ended");
            tracing::debug!(%reply, "room remote: end reply");
        }
        Err(e) => tracing::info!("room remote: ending the session failed: {e:#}"),
    }
}

/// The pane closed: end the session, and drop what's still on its way.
pub fn close() {
    let generation = remote().generation;
    runtime().spawn(async move {
        end_session(generation).await;
        let mut r = remote();
        if r.generation == generation {
            r.generation += 1;
            r.waiting.clear();
            r.accepted = None;
        }
    });
}

/// A message to one of our controller links (acceptance, rejection,
/// receive, end).
async fn controller_message(path: &str, body: serde_json::Value) {
    if path.ends_with("/acceptance") {
        if let Some(tx) = remote().accepted.take() {
            let _ = tx.send(body);
        }
        return;
    }
    if path.ends_with("/rejection") || path.ends_with("/end") {
        tracing::info!(%path, "room remote: the session ended on the room's side");
        remote().accepted.take();
        return;
    }
    let Ok(m) = serde_json::from_value::<Message>(body) else { return };
    let name = m.name();
    let d = m.details();
    if name == command::RESPONSE {
        let cause = d.get("requestCauseId").and_then(|c| c.as_str()).unwrap_or_default().to_string();
        if let Some(tx) = remote().waiting.remove(&cause) {
            let _ = tx.send(d);
        }
        return;
    }
    if name == command::STATE_UPDATE.to_ascii_lowercase() {
        {
            let mut r = remote();
            let mut merged = r.state.to_json();
            if let (Some(o), Some(n)) = (merged.as_object_mut(), d.as_object()) {
                for (k, v) in n {
                    o.insert(k.clone(), v.clone());
                }
            }
            r.state = RoomState::from_json(&merged);
        }
        publish("remote", None);
    } else if name == command::CAPABILITY_UPDATE.to_ascii_lowercase() {
        remote().caps.apply(&d);
        publish("remote", None);
    } else if name == command::UNPAIR {
        // The room ended the pairing (it leaves, or its remote control was
        // turned off): the panel closes.
        tracing::info!("room remote: the room unpaired");
        publish("left", None);
    }
    // Teams answers an update with its response.
    let ok = bt::response_details(&m, true, serde_json::json!({}));
    let (url, seq, chain) = {
        let mut r = remote();
        r.seq += 1;
        (r.broadcast.clone(), r.seq, r.chain.clone())
    };
    if url.is_empty() {
        return;
    }
    if let Some((http, token)) = client().await {
        let me = teams_cli::trouter::registrar::calling_registration_id();
        let _ = rr::post(&http, &token, &url, &rr::session_message(me, command::RESPONSE, &ok, seq, &chain), &chain).await;
    }
}
