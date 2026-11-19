//! OST's calls for a Bluetooth headset's call commands (TASK-0223), as
//! Teams reports its calls to Windows' VoIP call coordinator.
//!
//! PipeWire's HFP audio gateway takes a headset's ATA and AT+CHUP to the
//! calls of a ModemManager modem, rings the headset for an incoming one and
//! raises its call indicator for an active one. OST offers its calls there:
//! ModemManager's Modem, Modem3gpp and Voice interfaces and one Call object
//! per call, on the session bus (PipeWire's
//! `bluez5.hfphsp-backend-native-modem-bus = "session"`). Only the OST that
//! answers the headset's buttons (Teams' "Transfer controls to this app")
//! owns the name. Accept and Hangup pass Teams' checks (Sync device
//! buttons, a Bluetooth hands-free microphone selected, one such device)
//! or fail, and PipeWire answers the headset ERROR.

use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

use teams_cli::calling::hfp::{self, Phase, mm};
use teams_cli::calling::hid_telephony::{self, Action};
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue};

/// The call as the headset should see it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CallView {
    pub phase: Phase,
    pub incoming: bool,
    /// The other side's name (the headset's caller id).
    pub peer: String,
}

type OnAction = Arc<dyn Fn(Action) + Send + Sync>;

static TX: OnceLock<tokio::sync::watch::Sender<CallView>> = OnceLock::new();

/// OST's call changed.
pub fn set_call(view: CallView) {
    if let Some(tx) = TX.get() {
        tx.send_if_modified(|v| {
            let changed = *v != view;
            *v = view;
            changed
        });
    }
}

/// Offer OST's calls to the headset; `on_action` runs (on a runtime
/// thread) for each command Teams' checks let through.
pub fn start(on_action: impl Fn(Action) + Send + Sync + 'static) {
    if TX.get().is_some() {
        return;
    }
    let (tx, rx) = tokio::sync::watch::channel(CallView::default());
    let _ = TX.set(tx);
    let on_action: OnAction = Arc::new(on_action);
    crate::backend::runtime().spawn(async move {
        if let Err(e) = run(rx, on_action).await {
            tracing::info!("hfp: no call service for Bluetooth headsets: {e}");
        }
    });
}

struct Modem;

#[zbus::interface(name = "org.freedesktop.ModemManager1.Modem")]
impl Modem {
    #[zbus(property)]
    fn state(&self) -> i32 {
        mm::MODEM_STATE_REGISTERED
    }
    #[zbus(property)]
    fn manufacturer(&self) -> String {
        "OST".into()
    }
    #[zbus(property)]
    fn model(&self) -> String {
        "OST calls".into()
    }
    #[zbus(property)]
    fn revision(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }
    #[zbus(property)]
    fn equipment_identifier(&self) -> String {
        "ost".into()
    }
    #[zbus(property)]
    fn device(&self) -> String {
        "ost".into()
    }
    #[zbus(property)]
    fn own_numbers(&self) -> Vec<String> {
        Vec::new()
    }
    #[zbus(property)]
    fn signal_quality(&self) -> (u32, bool) {
        (100, true)
    }
}

struct Modem3gpp;

#[zbus::interface(name = "org.freedesktop.ModemManager1.Modem.Modem3gpp")]
impl Modem3gpp {
    #[zbus(property)]
    fn registration_state(&self) -> u32 {
        mm::REGISTRATION_HOME
    }
    #[zbus(property)]
    fn operator_name(&self) -> String {
        "OST".into()
    }
}

struct Voice {
    calls: Vec<OwnedObjectPath>,
}

#[zbus::interface(name = "org.freedesktop.ModemManager1.Modem.Voice")]
impl Voice {
    #[zbus(property)]
    fn calls(&self) -> Vec<OwnedObjectPath> {
        self.calls.clone()
    }
    async fn list_calls(&self) -> Vec<OwnedObjectPath> {
        self.calls.clone()
    }
    /// The headset dialling (ATD, AT+BLDN): Teams places no call from it.
    async fn create_call(&self, _properties: HashMap<String, OwnedValue>) -> zbus::fdo::Result<OwnedObjectPath> {
        tracing::info!("hfp: the headset asked to place a call; not supported");
        Err(zbus::fdo::Error::NotSupported("OST places calls from its own window".into()))
    }
    async fn delete_call(&self, _path: OwnedObjectPath) -> zbus::fdo::Result<()> {
        Ok(())
    }
    #[zbus(signal)]
    async fn call_added(emitter: &SignalEmitter<'_>, path: ObjectPath<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn call_deleted(emitter: &SignalEmitter<'_>, path: ObjectPath<'_>) -> zbus::Result<()>;
}

struct Call {
    state: i32,
    reason: u32,
    direction: i32,
    number: String,
    on_action: OnAction,
}

impl Call {
    /// Teams' checks for a command from the headset.
    fn allowed(&self, what: &str) -> zbus::fdo::Result<()> {
        let ctx = hfp::context();
        ctx.gate().map_err(|why| {
            tracing::info!(what, mic = ?ctx.mic, bt_mics = ?ctx.bt_mics, "hfp: headset command ignored: {why}");
            zbus::fdo::Error::AccessDenied(why.into())
        })
    }
}

#[zbus::interface(name = "org.freedesktop.ModemManager1.Call")]
impl Call {
    /// ATA (Teams' onAnswerCallActionEvent).
    async fn accept(&self) -> zbus::fdo::Result<()> {
        if self.state != mm::CALL_STATE_RINGING_IN {
            return Err(zbus::fdo::Error::Failed("the call isn't ringing".into()));
        }
        self.allowed("answer")?;
        tracing::info!("hfp: headset answered");
        (self.on_action)(Action::Answer);
        Ok(())
    }
    /// AT+CHUP: rejects a ringing call (onRejectCallActionEvent), else ends
    /// the call (onEndCallActionEvent).
    async fn hangup(&self) -> zbus::fdo::Result<()> {
        let ringing = self.state == mm::CALL_STATE_RINGING_IN;
        self.allowed(if ringing { "reject" } else { "end" })?;
        tracing::info!(ringing, "hfp: headset hung up");
        (self.on_action)(if ringing { Action::Reject } else { Action::HangUp });
        Ok(())
    }
    async fn start(&self) -> zbus::fdo::Result<()> {
        Err(zbus::fdo::Error::NotSupported("not a placed call".into()))
    }
    async fn send_dtmf(&self, _dtmf: String) -> zbus::fdo::Result<()> {
        Err(zbus::fdo::Error::NotSupported("no tones".into()))
    }
    #[zbus(property)]
    fn state(&self) -> i32 {
        self.state
    }
    #[zbus(property)]
    fn state_reason(&self) -> i32 {
        self.reason as i32
    }
    #[zbus(property)]
    fn direction(&self) -> i32 {
        self.direction
    }
    #[zbus(property)]
    fn number(&self) -> String {
        self.number.clone()
    }
    #[zbus(property)]
    fn multiparty(&self) -> bool {
        false
    }
    #[zbus(signal, name = "StateChanged")]
    async fn state_changed_signal(emitter: &SignalEmitter<'_>, old: i32, new: i32, reason: u32) -> zbus::Result<()>;
}

/// The headset's caller id: PipeWire passes it on in +CLIP, quoted.
fn caller_id(peer: &str) -> String {
    peer.chars().filter(|c| *c != '"' && !c.is_control()).take(32).collect()
}

async fn run(mut rx: tokio::sync::watch::Receiver<CallView>, on_action: OnAction) -> zbus::Result<()> {
    let conn = zbus::Connection::session().await?;
    let server = conn.object_server();
    server.at(mm::ROOT, zbus::fdo::ObjectManager).await?;
    server.at(mm::MODEM, Modem).await?;
    server.at(mm::MODEM, Modem3gpp).await?;
    server.at(mm::MODEM, Voice { calls: Vec::new() }).await?;
    let mut owned = false;
    // The call object: its path and ModemManager state.
    let mut current: Option<(OwnedObjectPath, i32)> = None;
    let mut next = 1u32;
    // A call already up when this OST takes the name is announced again
    // once PipeWire has read the modem (it learns calls only from
    // CallAdded).
    let mut announce_at: Option<tokio::time::Instant> = None;
    let mut tick = tokio::time::interval(std::time::Duration::from_secs(1));
    loop {
        tokio::select! {
            _ = tick.tick() => {}
            r = rx.changed() => if r.is_err() { return Ok(()) },
        }
        // The name follows the headset buttons' control between OSTs.
        let want = hid_telephony::status().has_control;
        if want && !owned {
            let flags = zbus::fdo::RequestNameFlags::ReplaceExisting | zbus::fdo::RequestNameFlags::AllowReplacement;
            match conn.request_name_with_flags(mm::SERVICE, flags).await {
                Ok(reply) => {
                    owned = matches!(reply, zbus::fdo::RequestNameReply::PrimaryOwner | zbus::fdo::RequestNameReply::AlreadyOwner);
                    if owned {
                        announce_at = Some(tokio::time::Instant::now() + std::time::Duration::from_millis(1500));
                    }
                    tracing::info!(?reply, "hfp: call service for Bluetooth headsets (ModemManager's Voice API on the session bus)");
                }
                Err(e) => tracing::info!("hfp: can't offer calls to Bluetooth headsets: {e}"),
            }
        } else if !want && owned {
            let _ = conn.release_name(mm::SERVICE).await;
            owned = false;
            tracing::info!("hfp: another OST has the headset's buttons; call service released");
        }
        let view = rx.borrow_and_update().clone();
        let target = view.phase.mm_state();
        let voice = server.interface::<_, Voice>(mm::MODEM).await?;
        if announce_at.is_some_and(|t| tokio::time::Instant::now() >= t) {
            announce_at = None;
            if let Some((path, state)) = &current {
                Voice::call_added(voice.signal_emitter(), path.as_ref()).await?;
                tracing::info!(call = %path.as_str(), state, "hfp: call announced to the headset (this OST took the buttons)");
            }
        }
        match (&current, target) {
            (None, None) => {}
            (None, Some(state)) => {
                let path = OwnedObjectPath::try_from(format!("{}{next}", mm::CALL_PREFIX))?;
                next += 1;
                let (direction, reason) = if view.incoming {
                    (mm::CALL_DIRECTION_INCOMING, mm::REASON_INCOMING_NEW)
                } else {
                    (mm::CALL_DIRECTION_OUTGOING, mm::REASON_OUTGOING_STARTED)
                };
                let call = Call { state, reason, direction, number: caller_id(&view.peer), on_action: on_action.clone() };
                server.at(path.as_ref(), call).await?;
                voice.get_mut().await.calls.push(path.clone());
                voice.get().await.calls_changed(voice.signal_emitter()).await?;
                Voice::call_added(voice.signal_emitter(), path.as_ref()).await?;
                tracing::info!(call = %path.as_str(), state, incoming = view.incoming, "hfp: call reported to the headset");
                current = Some((path, state));
            }
            (Some((path, old)), Some(state)) if *old != state => {
                let (path, old) = (path.clone(), *old);
                let call = server.interface::<_, Call>(path.as_ref()).await?;
                let reason = if old == mm::CALL_STATE_RINGING_IN { mm::REASON_ACCEPTED } else { 0 };
                {
                    let mut c = call.get_mut().await;
                    c.state = state;
                    c.reason = reason;
                }
                call.get().await.state_changed(call.signal_emitter()).await?;
                Call::state_changed_signal(call.signal_emitter(), old, state, reason).await?;
                tracing::info!(call = %path.as_str(), old, state, "hfp: call state to the headset");
                current = Some((path, state));
            }
            (Some(_), Some(_)) => {}
            (Some((path, old)), None) => {
                let (path, old) = (path.clone(), *old);
                if let Ok(call) = server.interface::<_, Call>(path.as_ref()).await {
                    call.get_mut().await.state = mm::CALL_STATE_TERMINATED;
                    let _ = Call::state_changed_signal(call.signal_emitter(), old, mm::CALL_STATE_TERMINATED, mm::REASON_TERMINATED).await;
                }
                voice.get_mut().await.calls.retain(|p| *p != path);
                voice.get().await.calls_changed(voice.signal_emitter()).await?;
                Voice::call_deleted(voice.signal_emitter(), path.as_ref()).await?;
                let _ = server.remove::<Call, _>(path.as_ref()).await;
                tracing::info!(call = %path.as_str(), "hfp: call ended for the headset");
                current = None;
            }
        }
    }
}
