//! The QML-facing backend: one QObject that drives the OST engine.
//!
//! Engine calls are async and run on a shared Tokio runtime; results are
//! posted back to the Qt thread with `qt_thread().queue`, so properties are
//! only ever written on the Qt thread. Lists cross to QML as JSON strings,
//! which QML parses into its own models; this keeps the bridge small.

use std::collections::HashSet;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::json;
use teams_cli::api::{self, client::TeamsClient};
use teams_cli::calling::incoming::{ActiveCall, CallAuth, IncomingCall};
use teams_cli::calling::outgoing::{self, OutgoingCall};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, busy)]
        #[qproperty(bool, signed_in)]
        #[qproperty(QString, user_name)]
        #[qproperty(QString, status_text)]
        #[qproperty(QString, chats_json)]
        #[qproperty(QString, messages_json)]
        #[qproperty(QString, current_chat_id)]
        #[qproperty(QString, current_chat_name)]
        #[qproperty(bool, has_credentials)]
        #[qproperty(QString, sign_in_code)]
        #[qproperty(QString, sign_in_url)]
        /// "", "ringing", "connecting", "connected" or "ended".
        #[qproperty(QString, call_state)]
        #[qproperty(QString, call_peer)]
        #[qproperty(bool, call_video_offered)]
        #[qproperty(bool, call_muted)]
        #[qproperty(bool, call_has_audio)]
        type Backend = super::BackendRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        /// Load the signed-in user and the chat list.
        #[qinvokable]
        fn refresh(self: Pin<&mut Backend>);

        /// Decide what to show at startup: the app, or the sign-in screen.
        #[qinvokable]
        fn start(self: Pin<&mut Backend>);

        /// Begin a device-code sign-in; the code and page appear in
        /// `signInCode` / `signInUrl`, and the app loads once approved.
        #[qinvokable]
        fn begin_sign_in(self: Pin<&mut Backend>);

        /// Forget the stored credentials and return to the sign-in screen.
        #[qinvokable]
        fn sign_out(self: Pin<&mut Backend>);

        /// Open a chat and load its messages.
        #[qinvokable]
        fn select_chat(self: Pin<&mut Backend>, chat_id: &QString, chat_name: &QString);

        /// Send a message to the open chat, then reload it.
        #[qinvokable]
        fn send_message(self: Pin<&mut Backend>, text: &QString);

        /// Answer the ringing call, with or without video.
        #[qinvokable]
        fn accept_call(self: Pin<&mut Backend>, with_video: bool);

        /// Decline the ringing call.
        #[qinvokable]
        fn decline_call(self: Pin<&mut Backend>);

        /// Call the other person in the open 1:1 chat.
        #[qinvokable]
        fn start_call(self: Pin<&mut Backend>);

        /// End the current call.
        #[qinvokable]
        fn hang_up(self: Pin<&mut Backend>);

        /// Mute or unmute the microphone in the current call.
        #[qinvokable]
        fn toggle_mute(self: Pin<&mut Backend>);
    }

    impl cxx_qt::Threading for Backend {}
}

#[derive(Default)]
pub struct BackendRust {
    busy: bool,
    signed_in: bool,
    user_name: QString,
    status_text: QString,
    chats_json: QString,
    messages_json: QString,
    current_chat_id: QString,
    current_chat_name: QString,
    has_credentials: bool,
    sign_in_code: QString,
    sign_in_url: QString,
    call_state: QString,
    call_peer: QString,
    call_video_offered: bool,
    call_muted: bool,
    call_has_audio: bool,
    /// Chats with messages pushed since the user last opened them.
    unread: HashSet<String>,
    /// The chat list as loaded, before unread flags are applied.
    chats: Vec<serde_json::Value>,
    /// Availability by MRI for the other members of 1:1 chats.
    presence: std::collections::HashMap<String, String>,
}

/// The call this app is ringing for or in. Lives on the engine side so the
/// media keeps running independently of the Qt thread.
#[derive(Default)]
struct CallSlot {
    ringing: Option<IncomingCall>,
    active: Option<ActiveCall>,
    outgoing: Option<OutgoingCall>,
    /// The call being placed (still ringing the callee).
    placing: Option<tokio::task::JoinHandle<()>>,
}

fn call_slot() -> &'static tokio::sync::Mutex<CallSlot> {
    static SLOT: OnceLock<tokio::sync::Mutex<CallSlot>> = OnceLock::new();
    SLOT.get_or_init(Default::default)
}

/// Log media health every 5 s while a call lasts.
fn spawn_call_stats_logger() {
    runtime().spawn(async {
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            let slot = call_slot().lock().await;
            if let Some(call) = slot.active.as_ref() {
                if let Some(s) = call.audio_stats().await {
                    tracing::info!(
                        sent = s.packets_sent,
                        received = s.packets_received,
                        muted = call.is_muted(),
                        "call audio"
                    );
                }
            } else if let Some(call) = slot.outgoing.as_ref() {
                if let Some(s) = call.stats().await {
                    tracing::info!(
                        sent = s.packets_sent,
                        received = s.packets_received,
                        muted = call.is_muted(),
                        "call audio"
                    );
                }
            } else {
                return;
            }
        }
    });
}

/// How long an unanswered call rings before it counts as missed.
const RING_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

/// How many chats and messages to load per request.
const CHAT_LIMIT: usize = 50;
const MESSAGE_LIMIT: usize = 50;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("failed to start the engine runtime")
    })
}

/// A short, single-line error for the status bar. Never includes tokens:
/// engine errors are built from endpoint error codes, not response bodies.
fn short_error(e: &anyhow::Error) -> String {
    let text = format!("{e:#}");
    let line = text.lines().next().unwrap_or_default();
    line.chars().take(200).collect()
}

async fn load_overview() -> anyhow::Result<(String, Vec<serde_json::Value>)> {
    let client = TeamsClient::new().await?;
    let my_oid = client.object_id().unwrap_or_default();
    let me = api::whoami_data(&client).await?;
    let chats = api::list_chats_data(&client, CHAT_LIMIT).await?;
    let list: Vec<_> = chats
        .iter()
        // 48:… threads are system streams (call logs, notifications,
        // mentions), not chats; Teams does not list them.
        .filter(|c| !c.id.starts_with("48:"))
        .map(|c| {
            json!({
                "id": c.id,
                "name": c.name,
                "isGroup": c.is_group,
                "time": c.last_message_time,
                "sender": c.last_message_sender,
                "preview": c.last_message_preview,
                "peerMri": outgoing::callee_mri_for_chat(&c.id, &my_oid),
            })
        })
        .collect();
    Ok((me.display_name, list))
}

async fn load_messages(chat_id: String) -> anyhow::Result<String> {
    let client = TeamsClient::new().await?;
    let own = client.display_name().unwrap_or_default();
    let messages = api::read_messages_data(&client, &chat_id, MESSAGE_LIMIT).await?;
    let list: Vec<_> = messages
        .iter()
        .map(|m| {
            json!({
                "sender": m.sender,
                "time": m.timestamp,
                "text": m.content,
                "mine": !own.is_empty() && m.sender == own,
            })
        })
        .collect();
    Ok(serde_json::to_string(&list)?)
}

/// A call event arrived: ring for a new invitation; anything else about
/// the current call is logged by shape (never by content) so call-end
/// signalling can be recognised.
async fn on_call_event(qt: &cxx_qt::CxxQtThread<qobject::Backend>, json: &str) {
    if let Some(call) = IncomingCall::parse(json) {
        let mut slot = call_slot().lock().await;
        if slot.ringing.is_some() || slot.active.is_some() {
            tracing::info!("second incoming call while busy; ignoring");
            return;
        }
        let peer = call.caller_name();
        let video = call.has_video();
        let call_id = call.call_id();
        slot.ringing = Some(call);
        drop(slot);
        tracing::info!(video, "incoming call");
        let _ = qt.queue(move |mut this| {
            this.as_mut().set_call_peer(QString::from(peer.as_str()));
            this.as_mut().set_call_video_offered(video);
            this.as_mut().set_call_state(QString::from("ringing"));
        });
        // Stop ringing if nobody answers.
        let qt = qt.clone();
        runtime().spawn(async move {
            tokio::time::sleep(RING_TIMEOUT).await;
            let mut slot = call_slot().lock().await;
            if slot.ringing.as_ref().map(|c| c.call_id()) == Some(call_id) {
                slot.ringing = None;
                drop(slot);
                tracing::info!("call missed");
                let _ = qt.queue(|mut this| this.as_mut().end_call_ui());
            }
        });
        return;
    }
    if teams_cli::calling::incoming::is_call_end_event(json) {
        let mut slot = call_slot().lock().await;
        let was_ringing = slot.ringing.take().is_some();
        // The other side ended it: drop media without signalling an end.
        let was_active = slot.active.take().is_some() || slot.outgoing.take().is_some();
        drop(slot);
        if was_ringing || was_active {
            tracing::info!(was_ringing, was_active, "call ended by the other side");
            let _ = qt.queue(|mut this| this.as_mut().end_call_ui());
        }
        return;
    }
    fn keys(v: &serde_json::Value, prefix: &str, depth: usize, out: &mut Vec<String>) {
        if let Some(o) = v.as_object() {
            for (k, child) in o {
                let path = if prefix.is_empty() {
                    k.clone()
                } else {
                    format!("{prefix}.{k}")
                };
                out.push(path.clone());
                if depth > 0 {
                    keys(child, &path, depth - 1, out);
                }
            }
        }
    }
    let mut shape = Vec::new();
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(json) {
        keys(&v, "", 4, &mut shape);
    }
    tracing::info!(?shape, "call event");
}

impl qobject::Backend {
    pub fn start(mut self: Pin<&mut Self>) {
        let stored = teams_cli::auth::has_credentials();
        self.as_mut().set_has_credentials(stored);
        if stored {
            self.refresh();
        }
    }

    pub fn begin_sign_in(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_status_text(QString::default());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let pending = match teams_cli::auth::begin_sign_in().await {
                Ok(p) => p,
                Err(e) => {
                    let msg = short_error(&e);
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_busy(false);
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                    });
                    return;
                }
            };
            let code = pending.user_code().to_string();
            let url = pending.verification_uri().to_string();
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_sign_in_code(QString::from(code.as_str()));
                this.as_mut().set_sign_in_url(QString::from(url.as_str()));
            });
            let result = teams_cli::auth::finish_sign_in(pending).await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                this.as_mut().set_sign_in_code(QString::default());
                this.as_mut().set_sign_in_url(QString::default());
                match result {
                    Ok(missing) => {
                        if !missing.is_empty() {
                            tracing::warn!("signed in without: {}", missing.join(", "));
                        }
                        this.as_mut().set_has_credentials(true);
                        this.as_mut().refresh();
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn sign_out(mut self: Pin<&mut Self>) {
        if let Err(e) = teams_cli::auth::sign_out() {
            self.as_mut()
                .set_status_text(QString::from(short_error(&e).as_str()));
            return;
        }
        self.as_mut().set_has_credentials(false);
        self.as_mut().set_signed_in(false);
        self.as_mut().set_user_name(QString::default());
        self.as_mut().set_chats_json(QString::from("[]"));
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().set_current_chat_id(QString::default());
        self.as_mut().set_current_chat_name(QString::default());
        self.as_mut().rust_mut().unread.clear();
        self.as_mut().rust_mut().chats.clear();
    }

    /// Hand the chat list, with unread flags, to QML.
    fn publish_chats(mut self: Pin<&mut Self>) {
        let unread = &self.rust().unread;
        let list: Vec<_> = self
            .rust()
            .chats
            .iter()
            .map(|c| {
                let mut c = c.clone();
                let id = c["id"].as_str().unwrap_or_default().to_string();
                c["unread"] = json!(unread.contains(&id));
                if let Some(mri) = c["peerMri"].as_str() {
                    if let Some(p) = self.rust().presence.get(mri) {
                        c["presence"] = json!(p);
                    }
                }
                c
            })
            .collect();
        let text = serde_json::to_string(&list).unwrap_or_else(|_| "[]".into());
        self.as_mut().set_chats_json(QString::from(text.as_str()));
    }

    /// Connect to Trouter once per process and react to pushed chat events:
    /// reload the open chat, mark others unread, and refresh the list order.
    fn start_push(self: Pin<&mut Self>) {
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let mut events = teams_cli::event_hub::subscribe();
        runtime().spawn(async {
            let opts = teams_cli::trouter::ListenOptions::EMBEDDED;
            if let Err(e) = teams_cli::trouter::listen(opts, std::future::pending).await {
                tracing::warn!("push channel stopped: {}", short_error(&e));
            }
        });
        let qt = self.qt_thread();
        runtime().spawn(async move {
            use teams_cli::event_hub::EventKind;
            use tokio::sync::broadcast::error::RecvError;
            loop {
                let ev = match events.recv().await {
                    Ok(ev) => ev,
                    Err(RecvError::Lagged(n)) => {
                        tracing::warn!("missed {n} push events; reloading");
                        let _ = qt.queue(|mut this| {
                            this.as_mut().reload_messages();
                            this.as_mut().reload_chats();
                        });
                        continue;
                    }
                    Err(RecvError::Closed) => return,
                };
                if ev.kind == EventKind::Call {
                    on_call_event(&qt, &ev.json).await;
                    continue;
                }
                let ids = teams_cli::event_hub::conversation_ids(&ev.json);
                if ids.is_empty() {
                    continue;
                }
                tracing::info!(chats = ids.len(), "chat push");
                let _ = qt.queue(move |mut this| this.as_mut().on_chat_push(ids));
            }
        });
    }

    pub fn accept_call(mut self: Pin<&mut Self>, with_video: bool) {
        if self.rust().call_state.to_string() != "ringing" {
            return;
        }
        self.as_mut().set_call_state(QString::from("connecting"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let Some(call) = call_slot().lock().await.ringing.take() else {
                return;
            };
            let result = async {
                let auth = CallAuth::load().await?;
                auth.answer(call, with_video, true).await
            }
            .await;
            match result {
                Ok(active) => {
                    let has_audio = active.has_audio();
                    tracing::info!(has_audio, "call answered");
                    call_slot().lock().await.active = Some(active);
                    spawn_call_stats_logger();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_muted(false);
                        this.as_mut().set_call_state(QString::from("connected"));
                    });
                }
                Err(e) => {
                    let msg = short_error(&e);
                    tracing::warn!("answer failed: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
    }

    pub fn decline_call(mut self: Pin<&mut Self>) {
        self.as_mut().end_call_ui();
        runtime().spawn(async {
            let Some(call) = call_slot().lock().await.ringing.take() else {
                return;
            };
            let result = async { CallAuth::load().await?.decline(&call).await }.await;
            if let Err(e) = result {
                tracing::warn!("decline failed: {}", short_error(&e));
            }
        });
    }

    pub fn start_call(mut self: Pin<&mut Self>) {
        if !self.rust().call_state.is_empty() {
            return;
        }
        // Placing calls currently joins a server-hosted conversation that does
        // not ring the callee like a Teams 1:1 call (TASK-0020); keep it
        // behind a flag until it does.
        if std::env::var_os("OST_EXPERIMENTAL_OUTGOING_CALLS").is_none() {
            self.as_mut().set_status_text(QString::from(
                "Starting calls from OST isn't available yet. You can receive calls.",
            ));
            return;
        }
        let chat_id = self.rust().current_chat_id.to_string();
        let peer = self.rust().current_chat_name.clone();
        let my_oid = teams_cli::config::Config::load()
            .ok()
            .and_then(|c| c.object_id())
            .unwrap_or_default();
        tracing::info!(chat = %chat_id, has_oid = !my_oid.is_empty(), "start call");
        let Some(callee) = outgoing::callee_mri_for_chat(&chat_id, &my_oid) else {
            self.as_mut()
                .set_status_text(QString::from("Calls are available in 1:1 chats"));
            return;
        };
        self.as_mut().set_call_peer(peer);
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_muted(false);
        self.as_mut().set_call_state(QString::from("calling"));
        let qt = self.qt_thread();
        let task = runtime().spawn(async move {
            let result = outgoing::place_call(&chat_id, &callee).await;
            let mut slot = call_slot().lock().await;
            slot.placing = None;
            match result {
                Ok(call) => {
                    let has_audio = call.has_audio();
                    tracing::info!(has_audio, "outgoing call connected");
                    slot.outgoing = Some(call);
                    drop(slot);
                    spawn_call_stats_logger();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_state(QString::from("connected"));
                    });
                }
                Err(e) => {
                    drop(slot);
                    let msg = short_error(&e);
                    tracing::info!("outgoing call ended: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
        runtime().block_on(async { call_slot().lock().await.placing = Some(task) });
    }

    pub fn hang_up(mut self: Pin<&mut Self>) {
        self.as_mut().end_call_ui();
        runtime().spawn(async {
            let mut slot = call_slot().lock().await;
            if let Some(task) = slot.placing.take() {
                task.abort();
                tracing::info!("outgoing call cancelled");
            }
            if let Some(call) = slot.outgoing.take() {
                drop(slot);
                if let Err(e) = call.hang_up().await {
                    tracing::warn!("hang up failed: {}", short_error(&e));
                }
                return;
            }
            let Some(call) = slot.active.take() else {
                return;
            };
            drop(slot);
            let result = async { CallAuth::load().await?.hang_up(call).await }.await;
            if let Err(e) = result {
                tracing::warn!("hang up failed: {}", short_error(&e));
            }
        });
    }

    pub fn toggle_mute(mut self: Pin<&mut Self>) {
        let muted = !self.rust().call_muted;
        self.as_mut().set_call_muted(muted);
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            if let Some(call) = slot.active.as_ref() {
                call.set_muted(muted);
            }
            if let Some(call) = slot.outgoing.as_ref() {
                call.set_muted(muted);
            }
        });
    }

    /// Show the call as over; the UI fades it out from "ended".
    fn end_call_ui(mut self: Pin<&mut Self>) {
        if !self.rust().call_state.is_empty() {
            self.as_mut().set_call_state(QString::from("ended"));
        }
    }

    /// Poll the presence of 1:1 chat partners every minute (Teams shows a
    /// badge on each avatar).
    fn start_presence(self: Pin<&mut Self>) {
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            loop {
                let (tx, rx) = tokio::sync::oneshot::channel::<Vec<String>>();
                let _ = qt.queue(move |this| {
                    let mris: Vec<String> = this
                        .rust()
                        .chats
                        .iter()
                        .filter_map(|c| c["peerMri"].as_str().map(str::to_string))
                        .collect();
                    let _ = tx.send(mris);
                });
                let mris = rx.await.unwrap_or_default();
                match teams_cli::api::presence::get_presences(&http, &mris).await {
                    Ok(list) => {
                        let _ = qt.queue(move |mut this| {
                            for p in list {
                                this.as_mut()
                                    .rust_mut()
                                    .presence
                                    .insert(p.mri, p.availability);
                            }
                            this.as_mut().publish_chats();
                        });
                    }
                    Err(e) => tracing::warn!("presence lookup failed: {}", short_error(&e)),
                }
                tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            }
        });
    }

    fn on_chat_push(mut self: Pin<&mut Self>, ids: Vec<String>) {
        let current = self.rust().current_chat_id.to_string();
        let mut list_changed = false;
        for id in ids {
            if id == current {
                self.as_mut().reload_messages();
            } else {
                list_changed |= self.as_mut().rust_mut().unread.insert(id);
            }
        }
        if list_changed {
            self.as_mut().publish_chats();
        }
        self.as_mut().reload_chats();
    }

    /// Reload the chat list quietly (new chats, new order), keeping unread
    /// flags. Pushes arriving while a reload runs are folded into it.
    fn reload_chats(self: Pin<&mut Self>) {
        static RUNNING: AtomicBool = AtomicBool::new(false);
        static AGAIN: AtomicBool = AtomicBool::new(false);
        if RUNNING.swap(true, Ordering::SeqCst) {
            AGAIN.store(true, Ordering::SeqCst);
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = load_overview().await;
            let _ = qt.queue(move |mut this| {
                RUNNING.store(false, Ordering::SeqCst);
                match result {
                    Ok((_, chats)) => {
                        this.as_mut().rust_mut().chats = chats;
                        this.as_mut().publish_chats();
                    }
                    Err(e) => tracing::warn!("chat list reload failed: {}", short_error(&e)),
                }
                if AGAIN.swap(false, Ordering::SeqCst) {
                    this.as_mut().reload_chats();
                }
            });
        });
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_status_text(QString::from("Loading…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = load_overview().await;
            tracing::info!(ok = result.is_ok(), "overview loaded");
            if let Err(e) = &result {
                tracing::warn!("overview failed: {}", short_error(e));
            }
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok((name, chats)) => {
                        this.as_mut().set_signed_in(true);
                        this.as_mut().set_user_name(QString::from(name.as_str()));
                        this.as_mut().rust_mut().chats = chats;
                        this.as_mut().publish_chats();
                        this.as_mut().set_status_text(QString::default());
                        this.as_mut().start_push();
                        this.as_mut().start_presence();
                    }
                    Err(e) => {
                        this.as_mut().set_signed_in(false);
                        this.as_mut()
                            .set_status_text(QString::from(short_error(&e).as_str()));
                    }
                }
            });
        });
    }

    pub fn select_chat(mut self: Pin<&mut Self>, chat_id: &QString, chat_name: &QString) {
        if self.as_mut().rust_mut().unread.remove(&chat_id.to_string()) {
            self.as_mut().publish_chats();
        }
        self.as_mut().set_current_chat_id(chat_id.clone());
        self.as_mut().set_current_chat_name(chat_name.clone());
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().reload_messages();
    }

    pub fn send_message(mut self: Pin<&mut Self>, text: &QString) {
        let body = text.to_string();
        let chat_id = self.rust().current_chat_id.to_string();
        if body.trim().is_empty() || chat_id.is_empty() {
            return;
        }
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::send_message_with_client(&client, &chat_id, &body).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => this.as_mut().reload_messages(),
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    fn reload_messages(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let wanted = chat_id.clone();
            let result = load_messages(chat_id).await;
            tracing::info!(ok = result.is_ok(), "messages loaded");
            let _ = qt.queue(move |mut this| {
                // Ignore a late answer for a chat the user has already left.
                if this.rust().current_chat_id.to_string() != wanted {
                    return;
                }
                match result {
                    Ok(json) => this
                        .as_mut()
                        .set_messages_json(QString::from(json.as_str())),
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }
}
