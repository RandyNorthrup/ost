//! OST's calls for a Bluetooth headset's call commands (TASK-0223), as
//! Teams reports its calls to Windows' VoIP call coordinator.
//!
//! PipeWire's HFP audio gateway takes a headset's ATA and AT+CHUP to the
//! calls of a ModemManager modem, rings the headset for an incoming one and
//! raises its call indicator for an active one. OST offers its calls there:
//! ModemManager's Modem, Modem3gpp and Voice interfaces and one Call object
//! per call, under ModemManager's name. Only the OST that answers the
//! headset's buttons (Teams' "Transfer controls to this app") owns the
//! name. Accept and Hangup pass Teams' checks (Sync device buttons, a
//! Bluetooth hands-free microphone selected, one such device) or fail, and
//! PipeWire answers the headset ERROR.
//!
//! Stock PipeWire looks for the modem on the system bus, with WirePlumber's
//! `bluez5.hfphsp-backend-native-modem` set (it's "none" by default). There
//! OST needs a D-Bus policy that lets its user own the name, and the
//! system's ModemManager must not hold it (it owns the name for good once
//! started): desktop/packaging/install-hfp-calls.sh sets both up. OST then
//! shows its modem only to that user's PipeWire gateway (WirePlumber), and
//! other system clients (NetworkManager, GeoClue, Plasma) see a
//! ModemManager without modems; only that gateway may answer or end a call.
//! PipeWire with contrib/pipewire's patch looks on the session bus instead,
//! so OST offers its calls on both buses.
//!
//! Without either, the headset's answer and hang-up aren't offered, as
//! Teams offers none where the platform lacks call control (it logs
//! "Platform not supported" and shows nothing), and the headset's mute
//! still works through its microphone gain.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use teams_cli::calling::hfp::{self, Phase, mm};
use teams_cli::calling::hid_telephony::{self, Action};
use tokio::time::Instant;
use zbus::message::Header;
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

/// The processes PipeWire's bluez5 plugin (the HFP gateway) runs in:
/// WirePlumber's Bluetooth monitor, PipeWire itself in custom setups, or
/// the old media session.
const GATEWAY_PROCESSES: &[&str] = &["wireplumber", "pipewire", "pipewire-media-session"];

/// Whether a D-Bus peer is this user's PipeWire gateway, by its bus
/// connection (unique name), checked once per connection.
static CALLERS: Mutex<Option<HashMap<String, bool>>> = Mutex::new(None);

fn own_uid() -> Option<u32> {
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata("/proc/self").ok().map(|m| m.uid())
}

/// Whether `uid` and the process name `comm` are this user's PipeWire
/// gateway.
fn is_gateway(uid: u32, comm: &str, own: Option<u32>) -> bool {
    own == Some(uid) && GATEWAY_PROCESSES.contains(&comm.trim())
}

/// Whether the message came from this user's PipeWire gateway. On the
/// system bus every local user can reach ModemManager's name (and, with
/// ModemManager's own policy installed, call Accept and Hangup), and other
/// system services read it; only the gateway sees OST's modem and acts on
/// its calls.
async fn from_gateway(conn: &zbus::Connection, hdr: Option<&Header<'_>>) -> bool {
    let Some(sender) = hdr.and_then(|h| h.sender()) else { return false };
    let key = format!("{} {}", conn.unique_name().map(|n| n.as_str()).unwrap_or_default(), sender.as_str());
    if let Some(ok) = CALLERS.lock().ok().and_then(|c| c.as_ref().and_then(|c| c.get(&key).copied())) {
        return ok;
    }
    let ok = async {
        let dbus = zbus::fdo::DBusProxy::new(conn).await.ok()?;
        let name = zbus::names::BusName::from(sender.to_owned());
        let uid = dbus.get_connection_unix_user(name.clone()).await.ok()?;
        let pid = dbus.get_connection_unix_process_id(name).await.ok()?;
        let comm = std::fs::read_to_string(format!("/proc/{pid}/comm")).ok()?;
        let ok = is_gateway(uid, &comm, own_uid());
        tracing::debug!(sender = sender.as_str(), uid, pid, comm = comm.trim(), ok, "hfp: modem client");
        Some(ok)
    }
    .await
    .unwrap_or(false);
    if let Ok(mut c) = CALLERS.lock() {
        c.get_or_insert_with(HashMap::new).insert(key, ok);
    }
    ok
}

/// ModemManager's manager object: other system clients (NetworkManager)
/// may read it.
struct Manager;

#[zbus::interface(name = "org.freedesktop.ModemManager1")]
impl Manager {
    async fn scan_devices(&self) {}
    async fn set_logging(&self, _level: String) {}
    #[zbus(property)]
    fn version(&self) -> String {
        format!("OST {}", env!("CARGO_PKG_VERSION"))
    }
}

/// ModemManager's object list (its ObjectManager): the modem, for PipeWire's
/// gateway only.
struct Modems {
    /// PipeWire's gateway has read the modem on this bus since OST took the
    /// name: it takes call commands from here.
    asked: Arc<AtomicBool>,
}

#[zbus::interface(name = "org.freedesktop.DBus.ObjectManager")]
impl Modems {
    async fn get_managed_objects(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        #[zbus(header)] hdr: Header<'_>,
    ) -> HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>> {
        let mut out = HashMap::new();
        if !from_gateway(conn, Some(&hdr)).await {
            // A ModemManager without modems, as on a machine without one.
            return out;
        }
        self.asked.store(true, Ordering::SeqCst);
        fn v<'a>(x: impl Into<zbus::zvariant::Value<'a>>) -> Option<OwnedValue> {
            OwnedValue::try_from(x.into()).ok()
        }
        let props = |list: Vec<(&str, Option<OwnedValue>)>| -> HashMap<String, OwnedValue> {
            list.into_iter().filter_map(|(k, x)| Some((k.to_string(), x?))).collect()
        };
        let mut ifaces = HashMap::new();
        ifaces.insert(
            "org.freedesktop.ModemManager1.Modem".to_string(),
            props(vec![
                ("State", v(mm::MODEM_STATE_REGISTERED)),
                ("Manufacturer", v("OST")),
                ("Model", v("OST calls")),
                ("Revision", v(env!("CARGO_PKG_VERSION"))),
                ("EquipmentIdentifier", v("ost")),
                ("Device", v("ost")),
                ("OwnNumbers", v(Vec::<String>::new())),
            ]),
        );
        ifaces.insert(
            "org.freedesktop.ModemManager1.Modem.Modem3gpp".to_string(),
            props(vec![("RegistrationState", v(mm::REGISTRATION_HOME)), ("OperatorName", v("OST"))]),
        );
        ifaces.insert("org.freedesktop.ModemManager1.Modem.Voice".to_string(), HashMap::new());
        if let Ok(path) = OwnedObjectPath::try_from(mm::MODEM) {
            out.insert(path, ifaces);
        }
        out
    }
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
    /// The command comes from this user's gateway, and Teams' checks pass.
    async fn allowed(&self, what: &str, conn: &zbus::Connection, hdr: &Header<'_>) -> zbus::fdo::Result<()> {
        if !from_gateway(conn, Some(hdr)).await {
            tracing::info!(what, sender = ?hdr.sender(), "hfp: call command from another program refused");
            return Err(zbus::fdo::Error::AccessDenied("only the user's Bluetooth audio gateway controls OST's calls".into()));
        }
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
    async fn accept(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        #[zbus(header)] hdr: Header<'_>,
    ) -> zbus::fdo::Result<()> {
        if self.state != mm::CALL_STATE_RINGING_IN {
            return Err(zbus::fdo::Error::Failed("the call isn't ringing".into()));
        }
        self.allowed("answer", conn, &hdr).await?;
        tracing::info!("hfp: headset answered");
        (self.on_action)(Action::Answer);
        Ok(())
    }
    /// AT+CHUP: rejects a ringing call (onRejectCallActionEvent), else ends
    /// the call (onEndCallActionEvent).
    async fn hangup(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        #[zbus(header)] hdr: Header<'_>,
    ) -> zbus::fdo::Result<()> {
        let ringing = self.state == mm::CALL_STATE_RINGING_IN;
        self.allowed(if ringing { "reject" } else { "end" }, conn, &hdr).await?;
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
    /// The caller's name, for the gateway only (other local users can read
    /// properties under ModemManager's name on the system bus).
    #[zbus(property)]
    async fn number(&self, #[zbus(connection)] conn: &zbus::Connection, #[zbus(header)] hdr: Option<Header<'_>>) -> String {
        if hdr.is_some() && !from_gateway(conn, hdr.as_ref()).await {
            return String::new();
        }
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

/// Which bus a gateway looks for the modem on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BusKind {
    /// Stock PipeWire (WirePlumber's `bluez5.hfphsp-backend-native-modem`).
    System,
    /// PipeWire with contrib/pipewire's patch
    /// (`bluez5.hfphsp-backend-native-modem-bus = "session"`).
    Session,
}

/// Why OST can't have ModemManager's name on a bus.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Blocked {
    /// No D-Bus policy lets this user own it (the system bus without
    /// desktop/packaging/install-hfp-calls.sh).
    NotAllowed,
    /// Another program holds it: on the system bus, the system's
    /// ModemManager (it never gives the name up).
    HeldBy(String),
    Failed(String),
}

impl Blocked {
    fn describe(&self, kind: BusKind) -> String {
        match (self, kind) {
            (Blocked::NotAllowed, BusKind::System) => {
                "OST's D-Bus policy isn't installed (desktop/packaging/install-hfp-calls.sh)".into()
            }
            (Blocked::NotAllowed, BusKind::Session) => "the session bus refused the name".into(),
            (Blocked::HeldBy(who), BusKind::System) => {
                format!("{who} holds org.freedesktop.ModemManager1 on the system bus (ModemManager runs; see desktop/packaging/install-hfp-calls.sh)")
            }
            (Blocked::HeldBy(who), BusKind::Session) => format!("{who} holds org.freedesktop.ModemManager1 on the session bus"),
            (Blocked::Failed(e), _) => e.clone(),
        }
    }
}

/// The bus's policy refused the request.
fn access_denied(e: &zbus::Error) -> bool {
    match e {
        zbus::Error::MethodError(name, _, _) => name.as_str() == "org.freedesktop.DBus.Error.AccessDenied",
        zbus::Error::FDO(f) => matches!(**f, zbus::fdo::Error::AccessDenied(_)),
        _ => false,
    }
}

/// ModemManager's name and OST's call objects on one bus.
struct Bus {
    kind: BusKind,
    conn: zbus::Connection,
    asked: Arc<AtomicBool>,
    owned: bool,
    blocked: Option<Blocked>,
    retry_at: Option<Instant>,
}

/// How often OST tries again for a name it couldn't have (the policy may be
/// installed or ModemManager stopped meanwhile).
const RETRY: Duration = Duration::from_secs(30);

impl Bus {
    async fn open(kind: BusKind) -> zbus::Result<Self> {
        let conn = match kind {
            BusKind::System => zbus::Connection::system().await?,
            BusKind::Session => zbus::Connection::session().await?,
        };
        let asked = Arc::new(AtomicBool::new(false));
        let server = conn.object_server();
        server.at(mm::ROOT, Manager).await?;
        server.at(mm::ROOT, Modems { asked: asked.clone() }).await?;
        server.at(mm::MODEM, Modem).await?;
        server.at(mm::MODEM, Modem3gpp).await?;
        server.at(mm::MODEM, Voice { calls: Vec::new() }).await?;
        Ok(Bus { kind, conn, asked, owned: false, blocked: None, retry_at: None })
    }

    /// Who holds the name, for the log: its process name.
    async fn holder(&self) -> String {
        async {
            let dbus = zbus::fdo::DBusProxy::new(&self.conn).await.ok()?;
            let name = zbus::names::BusName::try_from(mm::SERVICE).ok()?;
            let pid = dbus.get_connection_unix_process_id(name).await.ok()?;
            let comm = std::fs::read_to_string(format!("/proc/{pid}/comm")).unwrap_or_default();
            Some(format!("{} (pid {pid})", comm.trim()))
        }
        .await
        .unwrap_or_else(|| "another program".into())
    }

    /// Take ModemManager's name (from another OST of this user too, which
    /// lets it go when it loses the headset's buttons).
    async fn acquire(&mut self) {
        if self.retry_at.is_some_and(|t| Instant::now() < t) {
            return;
        }
        use zbus::fdo::{RequestNameFlags as F, RequestNameReply as R};
        self.asked.store(false, Ordering::SeqCst);
        let flags = F::ReplaceExisting | F::AllowReplacement | F::DoNotQueue;
        let blocked = match self.conn.request_name_with_flags(mm::SERVICE, flags).await {
            Ok(R::PrimaryOwner | R::AlreadyOwner) => None,
            Ok(R::Exists | R::InQueue) => Some(Blocked::HeldBy(self.holder().await)),
            Err(e) if access_denied(&e) => Some(Blocked::NotAllowed),
            Err(e) => Some(Blocked::Failed(e.to_string())),
        };
        self.owned = blocked.is_none();
        if self.owned {
            self.retry_at = None;
            tracing::info!(bus = ?self.kind, "hfp: call service for Bluetooth headsets (ModemManager's Voice API)");
        } else {
            self.retry_at = Some(Instant::now() + RETRY);
            if blocked != self.blocked {
                if let Some(b) = &blocked {
                    tracing::info!(bus = ?self.kind, "hfp: can't offer calls to Bluetooth headsets here: {}", b.describe(self.kind));
                }
            }
        }
        self.blocked = blocked;
    }

    async fn release(&mut self) {
        if self.owned {
            let _ = self.conn.release_name(mm::SERVICE).await;
            self.owned = false;
        }
        self.retry_at = None;
        self.blocked = None;
    }

    async fn voice(&self) -> zbus::Result<zbus::object_server::InterfaceRef<Voice>> {
        self.conn.object_server().interface::<_, Voice>(mm::MODEM).await
    }

    async fn announce(&self, path: &OwnedObjectPath) -> zbus::Result<()> {
        let voice = self.voice().await?;
        Voice::call_added(voice.signal_emitter(), path.as_ref()).await
    }

    async fn add_call(&self, path: &OwnedObjectPath, call: Call) -> zbus::Result<()> {
        self.conn.object_server().at(path.as_ref(), call).await?;
        let voice = self.voice().await?;
        voice.get_mut().await.calls.push(path.clone());
        voice.get().await.calls_changed(voice.signal_emitter()).await?;
        Voice::call_added(voice.signal_emitter(), path.as_ref()).await
    }

    async fn set_state(&self, path: &OwnedObjectPath, old: i32, state: i32, reason: u32) -> zbus::Result<()> {
        let call = self.conn.object_server().interface::<_, Call>(path.as_ref()).await?;
        {
            let mut c = call.get_mut().await;
            c.state = state;
            c.reason = reason;
        }
        call.get().await.state_changed(call.signal_emitter()).await?;
        Call::state_changed_signal(call.signal_emitter(), old, state, reason).await
    }

    async fn end_call(&self, path: &OwnedObjectPath, old: i32) -> zbus::Result<()> {
        let server = self.conn.object_server();
        if let Ok(call) = server.interface::<_, Call>(path.as_ref()).await {
            call.get_mut().await.state = mm::CALL_STATE_TERMINATED;
            let _ = Call::state_changed_signal(call.signal_emitter(), old, mm::CALL_STATE_TERMINATED, mm::REASON_TERMINATED).await;
        }
        let voice = self.voice().await?;
        voice.get_mut().await.calls.retain(|p| p != path);
        voice.get().await.calls_changed(voice.signal_emitter()).await?;
        Voice::call_deleted(voice.signal_emitter(), path.as_ref()).await?;
        let _ = server.remove::<Call, _>(path.as_ref()).await;
        Ok(())
    }
}

async fn run(mut rx: tokio::sync::watch::Receiver<CallView>, on_action: OnAction) -> zbus::Result<()> {
    let mut buses = Vec::new();
    for kind in [BusKind::System, BusKind::Session] {
        match Bus::open(kind).await {
            Ok(bus) => buses.push(bus),
            Err(e) => tracing::info!(bus = ?kind, "hfp: no D-Bus connection for headset calls: {e}"),
        }
    }
    if buses.is_empty() {
        return Err(zbus::Error::Failure("no D-Bus connection".into()));
    }
    // The call object: its path and ModemManager state, the same on each bus.
    let mut current: Option<(OwnedObjectPath, i32)> = None;
    let mut next = 1u32;
    // PipeWire's gateway reads the modem when this OST takes the name (if it
    // takes calls from that bus at all): then the headset's call buttons are
    // offered, and a call already up is announced (PipeWire learns calls
    // only from CallAdded).
    let mut offered = false;
    let mut check_at: Option<Instant> = None;
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    loop {
        tokio::select! {
            _ = tick.tick() => {}
            r = rx.changed() => if r.is_err() { return Ok(()) },
        }
        // The name follows the headset buttons' control between OSTs.
        let want = hid_telephony::status().has_control;
        for bus in buses.iter_mut() {
            if want && !bus.owned {
                bus.acquire().await;
                if bus.owned {
                    offered = false;
                    check_at = Some(Instant::now() + Duration::from_secs(5));
                    if let Ok(mut c) = CALLERS.lock() {
                        *c = None;
                    }
                }
            } else if !want && (bus.owned || bus.blocked.is_some()) {
                let was = bus.owned;
                bus.release().await;
                if was {
                    tracing::info!(bus = ?bus.kind, "hfp: another OST has the headset's buttons; call service released");
                }
            }
        }
        let view = rx.borrow_and_update().clone();
        let target = view.phase.mm_state();
        if !offered {
            if let Some(bus) = buses.iter().find(|b| b.owned && b.asked.load(Ordering::SeqCst)) {
                offered = true;
                check_at = None;
                tracing::info!(bus = ?bus.kind, "hfp: PipeWire's HFP gateway takes call commands from OST: a Bluetooth headset's answer and hang-up are offered");
                if let Some((path, state)) = &current {
                    bus.announce(path).await?;
                    tracing::info!(call = %path.as_str(), state, "hfp: call announced to the headset");
                }
            }
        }
        if check_at.is_some_and(|t| Instant::now() >= t) {
            check_at = None;
            let why: Vec<String> = buses
                .iter()
                .map(|b| match (&b.blocked, b.kind) {
                    (Some(blocked), kind) => format!("{kind:?} bus: {}", blocked.describe(kind)),
                    (None, BusKind::System) => "System bus: the gateway doesn't read the modem (WirePlumber's bluez5.hfphsp-backend-native-modem is \"none\", the default)".into(),
                    (None, BusKind::Session) => "Session bus: the gateway doesn't read the modem (stock PipeWire; contrib/pipewire's patch)".into(),
                })
                .collect();
            tracing::info!("hfp: PipeWire's HFP gateway doesn't take call commands from OST: a Bluetooth headset's answer and hang-up aren't offered, its mute works. {}", why.join("; "));
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
                for bus in &buses {
                    let call = Call { state, reason, direction, number: caller_id(&view.peer), on_action: on_action.clone() };
                    bus.add_call(&path, call).await?;
                }
                tracing::info!(call = %path.as_str(), state, incoming = view.incoming, "hfp: call reported to the headset");
                current = Some((path, state));
            }
            (Some((path, old)), Some(state)) if *old != state => {
                let (path, old) = (path.clone(), *old);
                let reason = if old == mm::CALL_STATE_RINGING_IN { mm::REASON_ACCEPTED } else { 0 };
                for bus in &buses {
                    bus.set_state(&path, old, state, reason).await?;
                }
                tracing::info!(call = %path.as_str(), old, state, "hfp: call state to the headset");
                current = Some((path, state));
            }
            (Some(_), Some(_)) => {}
            (Some((path, old)), None) => {
                let (path, old) = (path.clone(), *old);
                for bus in &buses {
                    bus.end_call(&path, old).await?;
                }
                tracing::info!(call = %path.as_str(), "hfp: call ended for the headset");
                current = None;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_this_users_gateway_controls_calls() {
        assert!(is_gateway(1000, "wireplumber\n", Some(1000)));
        assert!(is_gateway(1000, "pipewire", Some(1000)));
        // Another user's gateway, and other programs of this user (Plasma's
        // modem watcher, a script), don't.
        assert!(!is_gateway(1001, "wireplumber", Some(1000)));
        assert!(!is_gateway(1000, "kded6", Some(1000)));
        assert!(!is_gateway(0, "NetworkManager", Some(1000)));
        assert!(!is_gateway(1000, "wireplumber", None));
    }

    #[test]
    fn caller_id_is_safe_for_clip() {
        assert_eq!(caller_id("OST \"Test\" 1\n"), "OST Test 1");
        assert_eq!(caller_id(&"x".repeat(40)).len(), 32);
    }

    #[test]
    fn blocked_reasons_point_to_the_setup() {
        assert!(Blocked::NotAllowed.describe(BusKind::System).contains("install-hfp-calls.sh"));
        assert!(Blocked::HeldBy("ModemManager (pid 9)".into()).describe(BusKind::System).contains("ModemManager (pid 9)"));
    }
}
