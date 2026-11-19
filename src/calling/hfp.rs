//! Bluetooth (HFP) headset call controls, as Teams has them.
//!
//! Teams doesn't talk to a Bluetooth headset itself. Windows' Bluetooth
//! audio gateway (BTAGService) speaks HFP with it, and Teams reports its
//! calls to Windows' VoIP call coordinator (Windows.ApplicationModel.Calls,
//! Teams' `HfpVoipCallCoordinatorImpl`): a ringing call (reportIncomingCall)
//! makes the gateway ring the headset, an answered or placed call
//! (reportCallAccepted, requestStartCall, reportOutgoingCallConnected)
//! raises its call indicator, and reportCallEnded drops it. The gateway
//! turns the headset's commands into the coordinator's events: ATA is
//! AnswerRequested, AT+CHUP is RejectRequested on a ringing call and
//! EndRequested on a call, and on Windows 11 the microphone gain carries
//! the mute: AT+VGM=0 mutes, a gain above 0 unmutes
//! (HfpAtVgmReceivedExpectMuteChange) and Teams' own mute sends the headset
//! +VGM: 0 (HfpAtVgmSentMuteChange). Teams acts on them only with Sync
//! device buttons on, with a Bluetooth hands-free microphone selected and
//! with one Bluetooth hands-free device present (its multi-device mode is
//! off); otherwise it fails the action and the gateway answers ERROR.
//!
//! On Linux the audio gateway is PipeWire's native HFP backend. It takes a
//! headset's call commands to the calls of a ModemManager modem (Voice
//! API); OST offers its calls that way on the session bus (desktop's
//! `hfp_calls`; PipeWire's `bluez5.hfphsp-backend-native-modem-bus =
//! "session"`). PipeWire turns AT+VGM into the headset microphone's volume
//! and its volume into +VGM, so this module watches and sets that volume
//! for the mute.

/// ModemManager's D-Bus names and values (ModemManager-enums.h).
pub mod mm {
    pub const SERVICE: &str = "org.freedesktop.ModemManager1";
    pub const ROOT: &str = "/org/freedesktop/ModemManager1";
    pub const MODEM: &str = "/org/freedesktop/ModemManager1/Modem/0";
    pub const CALL_PREFIX: &str = "/org/freedesktop/ModemManager1/Call/";

    pub const CALL_STATE_DIALING: i32 = 1;
    pub const CALL_STATE_RINGING_OUT: i32 = 2;
    pub const CALL_STATE_RINGING_IN: i32 = 3;
    pub const CALL_STATE_ACTIVE: i32 = 4;
    pub const CALL_STATE_HELD: i32 = 5;
    pub const CALL_STATE_TERMINATED: i32 = 7;

    pub const CALL_DIRECTION_INCOMING: i32 = 1;
    pub const CALL_DIRECTION_OUTGOING: i32 = 2;

    pub const REASON_OUTGOING_STARTED: u32 = 1;
    pub const REASON_INCOMING_NEW: u32 = 2;
    pub const REASON_ACCEPTED: u32 = 3;
    pub const REASON_TERMINATED: u32 = 4;

    /// MM_MODEM_STATE_REGISTERED: PipeWire's gateway has "service" from it
    /// on (it refuses ATA and AT+CHUP without).
    pub const MODEM_STATE_REGISTERED: i32 = 8;
    /// MM_MODEM_3GPP_REGISTRATION_STATE_HOME.
    pub const REGISTRATION_HOME: u32 = 1;
}

/// The call as the headset sees it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Phase {
    #[default]
    Idle,
    /// An incoming call rings (Teams' reportIncomingCall).
    RingingIn,
    /// A call this app places hasn't connected (requestStartCall).
    RingingOut,
    /// Connected (reportCallAccepted / reportOutgoingCallConnected).
    Active,
    /// On hold (reportHoldCall).
    Held,
}

impl Phase {
    /// From OST's call state; `incoming`: the call rang here first.
    pub fn of(call_state: &str, held: bool, incoming: bool) -> Phase {
        match call_state {
            "ringing" => Phase::RingingIn,
            // Teams reports an answered call accepted when it starts
            // connecting, and a placed one once it connects.
            "connecting" if incoming => Phase::Active,
            "calling" | "connecting" | "lobby" => Phase::RingingOut,
            "connected" if held => Phase::Held,
            "connected" => Phase::Active,
            _ => Phase::Idle,
        }
    }

    /// The ModemManager call state (`None`: no call).
    pub fn mm_state(self) -> Option<i32> {
        match self {
            Phase::Idle => None,
            Phase::RingingIn => Some(mm::CALL_STATE_RINGING_IN),
            Phase::RingingOut => Some(mm::CALL_STATE_RINGING_OUT),
            Phase::Active => Some(mm::CALL_STATE_ACTIVE),
            Phase::Held => Some(mm::CALL_STATE_HELD),
        }
    }
}

/// What Teams checks before it acts on a headset's call command.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Context {
    /// "Sync device buttons" (Teams' isHFPDeviceSyncEnabled).
    pub sync: bool,
    /// The selected microphone (the system default when none was chosen).
    pub mic: Option<String>,
    /// The Bluetooth hands-free microphones present.
    pub bt_mics: Vec<String>,
}

impl Context {
    /// The selected microphone is a Bluetooth hands-free one (Teams'
    /// isSelectedMicHfpBT: its connection type is Bluetooth).
    pub fn mic_is_bt(&self) -> bool {
        self.mic.as_ref().is_some_and(|m| self.bt_mics.contains(m))
    }

    /// Teams' checks, with its reasons for failing the action.
    pub fn gate(&self) -> Result<(), &'static str> {
        if !self.sync {
            return Err("HFP call controls are unavailable (Sync device buttons is off)");
        }
        if !self.mic_is_bt() {
            return Err("the selected microphone isn't a Bluetooth hands-free device");
        }
        if self.bt_mics.len() > 1 {
            return Err("more than 1 Bluetooth hands-free device; HFP call controls are not available");
        }
        Ok(())
    }
}

/// A microphone gain crossing zero is a mute change (Windows 11's
/// HfpAtVgmReceivedExpectMuteChange); the first gain only sets the
/// baseline (HfpAtVgmReceivedInitialStateUnknown).
pub fn gain_mute_change(was_zero: Option<bool>, zero: bool) -> Option<bool> {
    match was_zero {
        Some(w) if w != zero => Some(zero),
        _ => None,
    }
}

// ---- Preferences and the app's mute ----

use std::sync::Mutex;

struct Prefs {
    mic: Option<String>,
    sync: bool,
}

static PREFS: Mutex<Prefs> = Mutex::new(Prefs { mic: None, sync: true });
/// The microphone whose gain OST zeroed for its mute, if any.
static ZEROED: Mutex<Option<String>> = Mutex::new(None);

/// The selected microphone (`None`: the system default) and Teams' "Sync
/// device buttons".
pub fn set_preferences(mic: Option<String>, sync: bool) {
    let mut p = PREFS.lock().unwrap_or_else(|e| e.into_inner());
    p.mic = mic;
    p.sync = sync;
}

/// Teams' checks as things stand.
pub fn context() -> Context {
    let (mic, sync) = {
        let p = PREFS.lock().unwrap_or_else(|e| e.into_inner());
        (p.mic.clone(), p.sync)
    };
    let bt_mics = bt_mics();
    #[cfg(all(feature = "audio", target_os = "linux"))]
    let mic = mic.or_else(|| {
        // The system default, only worth asking about with a Bluetooth
        // microphone around.
        if bt_mics.is_empty() { None } else { crate::calling::pw_defaults::default_endpoints().0 }
    });
    Context { sync, mic, bt_mics }
}

/// The app's mute for the headset (Teams' reportMuteStateChange; Windows
/// sends the headset +VGM: 0): in a call with the Bluetooth microphone
/// selected, OST's mute zeroes its gain and unmuting puts it back; out of a
/// call the gain goes back. Returns at once; a worker applies the latest.
pub fn sync_app_mute(in_call: bool, muted: bool) {
    use std::sync::{OnceLock, mpsc};
    static WORKER: OnceLock<Mutex<mpsc::Sender<(bool, bool)>>> = OnceLock::new();
    let tx = WORKER.get_or_init(|| {
        let (tx, rx) = mpsc::channel::<(bool, bool)>();
        std::thread::Builder::new()
            .name("ost-hfp-mute".into())
            .spawn(move || {
                while let Ok(mut latest) = rx.recv() {
                    while let Ok(next) = rx.try_recv() {
                        latest = next;
                    }
                    apply_app_mute(latest.0, latest.1);
                }
            })
            .ok();
        Mutex::new(tx)
    });
    let _ = tx.lock().unwrap_or_else(|e| e.into_inner()).send((in_call, muted));
}

fn apply_app_mute(in_call: bool, muted: bool) {
    let ctx = context();
    let mut zeroed = ZEROED.lock().unwrap_or_else(|e| e.into_inner());
    let want = (in_call && muted && ctx.gate().is_ok()).then(|| ctx.mic.clone()).flatten();
    if *zeroed == want {
        return;
    }
    if let Some(old) = zeroed.take() {
        set_gain_muted(&old, false);
    }
    if let Some(mic) = &want {
        set_gain_muted(mic, true);
    }
    *zeroed = want;
}

// ---- The Bluetooth hands-free microphones (PipeWire) ----

/// A headset's gain crossed zero: (microphone, muted).
pub type GainHandler = Box<dyn Fn(String, bool) + Send>;

#[cfg(all(feature = "audio", target_os = "linux"))]
pub use watch::{bt_mics, set_gain_muted, start};

#[cfg(not(all(feature = "audio", target_os = "linux")))]
pub fn bt_mics() -> Vec<String> {
    Vec::new()
}

#[cfg(not(all(feature = "audio", target_os = "linux")))]
pub fn set_gain_muted(_mic: &str, _muted: bool) {}

#[cfg(not(all(feature = "audio", target_os = "linux")))]
pub fn start(_on_gain: GainHandler) {}

#[cfg(all(feature = "audio", target_os = "linux"))]
mod watch {
    use std::cell::RefCell;
    use std::collections::HashMap;
    use std::rc::Rc;
    use std::sync::{Mutex, OnceLock};

    use pipewire as pw;
    use pw::spa;
    use pw::types::ObjectType;

    use super::GainHandler;

    /// A Bluetooth hands-free microphone (a bluez5 source node).
    #[derive(Debug, Clone, Default)]
    struct Mic {
        /// Its name in OST's device lists (node.description).
        name: String,
        /// Its device and the device's route for it: the headset's gain
        /// is set on the route (PipeWire then sends +VGM), as mixers do.
        device: u32,
        profile_device: i32,
        /// Its channel volumes (PipeWire carries the headset's gain there).
        volumes: Vec<f32>,
        /// The volumes before OST zeroed them.
        saved: Option<Vec<f32>>,
    }

    impl Mic {
        fn zero(&self) -> Option<bool> {
            (!self.volumes.is_empty()).then(|| self.volumes.iter().all(|v| *v <= 0.0))
        }
    }

    enum Cmd {
        SetMuted(String, bool),
    }

    static MICS: Mutex<Vec<(u32, Mic)>> = Mutex::new(Vec::new());
    static CMD: OnceLock<Mutex<pw::channel::Sender<Cmd>>> = OnceLock::new();

    pub fn bt_mics() -> Vec<String> {
        MICS.lock().unwrap_or_else(|e| e.into_inner()).iter().map(|(_, m)| m.name.clone()).collect()
    }

    pub fn set_gain_muted(mic: &str, muted: bool) {
        if let Some(tx) = CMD.get() {
            let _ = tx.lock().unwrap_or_else(|e| e.into_inner()).send(Cmd::SetMuted(mic.to_string(), muted));
        }
    }

    /// Watch PipeWire's Bluetooth hands-free microphones; `on_gain` runs
    /// on the watcher's thread when one's gain crosses zero.
    pub fn start(on_gain: GainHandler) {
        if CMD.get().is_some() {
            return;
        }
        let (tx, rx) = pw::channel::channel::<Cmd>();
        let _ = CMD.set(Mutex::new(tx));
        std::thread::Builder::new()
            .name("ost-hfp-pw".into())
            .spawn(move || {
                if let Err(e) = run(rx, on_gain) {
                    tracing::info!("hfp: PipeWire watcher stopped: {e}");
                }
            })
            .ok();
    }

    fn volumes_of(pod: &spa::pod::Pod) -> Option<Vec<f32>> {
        use spa::pod::{Value, ValueArray, deserialize::PodDeserializer};
        let (_, value) = PodDeserializer::deserialize_any_from(pod.as_bytes()).ok()?;
        let Value::Object(obj) = value else { return None };
        obj.properties.into_iter().find(|p| p.key == spa::sys::SPA_PROP_channelVolumes).and_then(|p| match p.value {
            Value::ValueArray(ValueArray::Float(v)) => Some(v),
            _ => None,
        })
    }

    /// An input route of a device: (route index, its profile device).
    fn input_route_of(pod: &spa::pod::Pod) -> Option<(i32, i32)> {
        use spa::pod::{Value, deserialize::PodDeserializer};
        let (_, value) = PodDeserializer::deserialize_any_from(pod.as_bytes()).ok()?;
        let Value::Object(obj) = value else { return None };
        let (mut index, mut device, mut input) = (None, None, false);
        for p in obj.properties {
            match (p.key, p.value) {
                (spa::sys::SPA_PARAM_ROUTE_index, Value::Int(i)) => index = Some(i),
                (spa::sys::SPA_PARAM_ROUTE_device, Value::Int(d)) => device = Some(d),
                (spa::sys::SPA_PARAM_ROUTE_direction, Value::Id(d)) => input = d.0 == spa::sys::SPA_DIRECTION_INPUT,
                _ => {}
            }
        }
        input.then_some((index?, device?))
    }

    /// The device route that sets the headset's gain.
    fn route_pod(index: i32, device: i32, volumes: Vec<f32>) -> Option<Vec<u8>> {
        use spa::pod::{Object, Property, PropertyFlags, Value, ValueArray, serialize::PodSerializer};
        let prop = |key, value| Property { key, flags: PropertyFlags::empty(), value };
        let props = Value::Object(Object {
            type_: spa::utils::SpaTypes::ObjectParamProps.as_raw(),
            id: spa::param::ParamType::Route.as_raw(),
            properties: vec![prop(spa::sys::SPA_PROP_channelVolumes, Value::ValueArray(ValueArray::Float(volumes)))],
        });
        let value = Value::Object(Object {
            type_: spa::utils::SpaTypes::ObjectParamRoute.as_raw(),
            id: spa::param::ParamType::Route.as_raw(),
            properties: vec![
                prop(spa::sys::SPA_PARAM_ROUTE_index, Value::Int(index)),
                prop(spa::sys::SPA_PARAM_ROUTE_device, Value::Int(device)),
                prop(spa::sys::SPA_PARAM_ROUTE_props, props),
                // Not kept as the device's volume: the gain comes back on
                // unmute.
                prop(spa::sys::SPA_PARAM_ROUTE_save, Value::Bool(false)),
            ],
        });
        Some(PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &value).ok()?.0.into_inner())
    }

    fn run(rx: pw::channel::Receiver<Cmd>, on_gain: GainHandler) -> anyhow::Result<()> {
        pw::init();
        let mainloop = pw::main_loop::MainLoopRc::new(None)?;
        let context = pw::context::ContextRc::new(&mainloop, None)?;
        let core = context.connect_rc(None)?;
        let registry = core.get_registry_rc()?;
        let on_gain = Rc::new(on_gain);
        // Bound nodes and their listeners, by global id.
        let nodes: Rc<RefCell<HashMap<u32, (pw::node::Node, pw::node::NodeListener)>>> = Rc::default();
        // Bound Bluetooth devices, their listeners and input routes.
        type Routes = Rc<RefCell<Vec<(i32, i32)>>>;
        let devices: Rc<RefCell<HashMap<u32, (pw::device::Device, pw::device::DeviceListener, Routes)>>> = Rc::default();

        let _registry_listener = registry
            .add_listener_local()
            .global({
                let nodes = nodes.clone();
                let devices = devices.clone();
                let registry = registry.clone();
                let on_gain = on_gain.clone();
                move |global| {
                    if global.type_ == ObjectType::Device {
                        let bluez = global.props.is_some_and(|p| {
                            p.get("device.api") == Some("bluez5") || p.get("device.name").is_some_and(|n| n.starts_with("bluez_card."))
                        });
                        if !bluez {
                            return;
                        }
                        let Ok(device) = registry.bind::<pw::device::Device, _>(global) else { return };
                        let routes: Routes = Rc::default();
                        let listener = device
                            .add_listener_local()
                            .param({
                                let routes = routes.clone();
                                move |_seq, _id, index, _next, pod| {
                                    if index == 0 {
                                        routes.borrow_mut().clear();
                                    }
                                    if let Some(r) = pod.and_then(input_route_of) {
                                        routes.borrow_mut().push(r);
                                    }
                                }
                            })
                            .register();
                        device.subscribe_params(&[spa::param::ParamType::Route]);
                        devices.borrow_mut().insert(global.id, (device, listener, routes));
                        return;
                    }
                    if global.type_ != ObjectType::Node {
                        return;
                    }
                    let Some(props) = global.props else { return };
                    if props.get("media.class") != Some("Audio/Source") {
                        return;
                    }
                    let Ok(node) = registry.bind::<pw::node::Node, _>(global) else { return };
                    let id = global.id;
                    let on_gain = on_gain.clone();
                    let listener = node
                        .add_listener_local()
                        .info(move |info| {
                            let Some(p) = info.props() else { return };
                            let bluez = p.get("device.api") == Some("bluez5") || p.get("api.bluez5.address").is_some();
                            let name = p.get("node.description").unwrap_or_default().to_string();
                            if !bluez || name.is_empty() {
                                return;
                            }
                            let mut mics = MICS.lock().unwrap_or_else(|e| e.into_inner());
                            if !mics.iter().any(|(i, _)| *i == id) {
                                tracing::info!(%name, id, address = p.get("api.bluez5.address").unwrap_or(""), profile = p.get("api.bluez5.profile").unwrap_or(""), "hfp: Bluetooth hands-free microphone");
                                mics.push((id, Mic { name, ..Mic::default() }));
                            }
                            if let Some((_, mic)) = mics.iter_mut().find(|(i, _)| *i == id) {
                                mic.device = p.get("device.id").and_then(|d| d.parse().ok()).unwrap_or(0);
                                mic.profile_device = p.get("card.profile.device").and_then(|d| d.parse().ok()).unwrap_or(0);
                            }
                        })
                        .param(move |_seq, _id, _index, _next, pod| {
                            let Some(volumes) = pod.and_then(volumes_of) else { return };
                            let mut mics = MICS.lock().unwrap_or_else(|e| e.into_inner());
                            let Some((_, mic)) = mics.iter_mut().find(|(i, _)| *i == id) else { return };
                            if mic.volumes == volumes {
                                return;
                            }
                            let was = mic.zero();
                            mic.volumes = volumes;
                            let now = mic.zero().unwrap_or(false);
                            tracing::info!(mic = %mic.name, volumes = ?mic.volumes, "hfp: headset gain");
                            if let Some(muted) = super::gain_mute_change(was, now) {
                                let name = mic.name.clone();
                                drop(mics);
                                on_gain(name, muted);
                            }
                        })
                        .register();
                    node.subscribe_params(&[spa::param::ParamType::Props]);
                    nodes.borrow_mut().insert(id, (node, listener));
                }
            })
            .global_remove({
                let nodes = nodes.clone();
                let devices = devices.clone();
                move |id| {
                    nodes.borrow_mut().remove(&id);
                    devices.borrow_mut().remove(&id);
                    let mut mics = MICS.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(i) = mics.iter().position(|(n, _)| *n == id) {
                        tracing::info!(mic = %mics[i].1.name, "hfp: Bluetooth hands-free microphone gone");
                        mics.remove(i);
                    }
                }
            })
            .register();

        let _rx = rx.attach(mainloop.loop_(), {
            let devices = devices.clone();
            move |cmd| match cmd {
                Cmd::SetMuted(name, muted) => {
                    let (device, profile_device) = {
                        let mics = MICS.lock().unwrap_or_else(|e| e.into_inner());
                        let Some((_, mic)) = mics.iter().find(|(_, m)| m.name == name) else { return };
                        (mic.device, mic.profile_device)
                    };
                    let devices = devices.borrow();
                    let Some((proxy, _, routes)) = devices.get(&device) else {
                        tracing::info!(mic = %name, device, "hfp: no device for the headset's gain");
                        return;
                    };
                    let Some(&(route, _)) = routes.borrow().iter().find(|(_, d)| *d == profile_device) else {
                        tracing::info!(mic = %name, device, "hfp: no input route for the headset's gain");
                        return;
                    };
                    let target = {
                        let mut mics = MICS.lock().unwrap_or_else(|e| e.into_inner());
                        let Some((id, mic)) = mics.iter_mut().find(|(_, m)| m.name == name) else { return };
                        let volumes = if muted {
                            if mic.zero() != Some(false) {
                                return;
                            }
                            mic.saved = Some(mic.volumes.clone());
                            vec![0.0; mic.volumes.len()]
                        } else {
                            match mic.saved.take() {
                                Some(v) if mic.zero() == Some(true) => v,
                                _ => return,
                            }
                        };
                        (*id, volumes)
                    };
                    tracing::info!(mic = %name, muted, volumes = ?target.1, route, "hfp: setting the headset's gain");
                    let Some(bytes) = route_pod(route, profile_device, target.1) else { return };
                    let Some(pod) = spa::pod::Pod::from_bytes(&bytes) else { return };
                    proxy.set_param(spa::param::ParamType::Route, 0, pod);
                }
            }
        });
        mainloop.run();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phases_follow_teams_reports() {
        assert_eq!(Phase::of("ringing", false, true), Phase::RingingIn);
        // An answered call is accepted as it connects; a placed one only
        // once connected.
        assert_eq!(Phase::of("connecting", false, true), Phase::Active);
        assert_eq!(Phase::of("connecting", false, false), Phase::RingingOut);
        assert_eq!(Phase::of("calling", false, false), Phase::RingingOut);
        assert_eq!(Phase::of("connected", false, false), Phase::Active);
        assert_eq!(Phase::of("connected", true, false), Phase::Held);
        assert_eq!(Phase::of("ended", false, true), Phase::Idle);
        assert_eq!(Phase::of("", false, false), Phase::Idle);
        assert_eq!(Phase::RingingIn.mm_state(), Some(mm::CALL_STATE_RINGING_IN));
        assert_eq!(Phase::Idle.mm_state(), None);
    }

    #[test]
    fn gate_is_teams_checks() {
        let bt = "Headset (HFP)".to_string();
        let mut c = Context { sync: true, mic: Some(bt.clone()), bt_mics: vec![bt.clone()] };
        assert!(c.gate().is_ok());
        c.sync = false;
        assert!(c.gate().is_err());
        c.sync = true;
        c.mic = Some("Built-in Audio".into());
        assert!(c.gate().is_err());
        c.mic = Some(bt.clone());
        c.bt_mics.push("Other headset".into());
        assert!(c.gate().is_err());
    }

    #[test]
    fn gain_through_zero_is_mute() {
        assert_eq!(gain_mute_change(None, true), None);
        assert_eq!(gain_mute_change(Some(false), true), Some(true));
        assert_eq!(gain_mute_change(Some(true), false), Some(false));
        assert_eq!(gain_mute_change(Some(false), false), None);
    }
}
