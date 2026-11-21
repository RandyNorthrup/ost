//! Teams' Bluetooth room discovery for the pre-join screen's Room audio
//! ("Nearby"), as its BluetoothLEService does it: while Room audio looks
//! for rooms, scan for Bluetooth LE advertisements with Microsoft's
//! manufacturer data and keep the Teams Rooms devices heard (their room
//! account, signal and validation code; `api::rooms::parse_beacon`) for 30
//! seconds after the last advertisement (Teams' houseKeep).
//!
//! Teams scans through Windows' Bluetooth LE watcher; OST asks BlueZ
//! (org.bluez on the system bus): the adapter's Powered state is Teams'
//! radio state, discovery with an LE transport filter is its scan, and
//! each device's ManufacturerData and RSSI are its advertisements.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use teams_cli::api::better_together::{Companion, parse_companion};
use teams_cli::api::rooms::{Beacon, parse_beacon};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

/// Teams' state for the Room audio hints.
#[derive(Debug, Clone, Copy, Default, serde::Serialize)]
pub struct BleState {
    /// There is a Bluetooth adapter (Teams' isBleSupported).
    pub supported: bool,
    /// It's powered (Teams' isRadioOn).
    pub radio_on: bool,
}

struct Shared {
    state: BleState,
    seen: std::collections::BTreeMap<String, (Beacon, Instant)>,
    /// Teams phones heard (Better Together's companion discovery), by
    /// user and endpoint bytes.
    companions: std::collections::BTreeMap<(String, Option<[u8; 2]>), (Companion, Instant)>,
    scanning: bool,
    /// Better Together proximity checks running (Teams subscribes to its
    /// companion discovery for each).
    companion_scans: u32,
    task: bool,
}

static SHARED: Mutex<Shared> = Mutex::new(Shared {
    state: BleState { supported: false, radio_on: false },
    seen: std::collections::BTreeMap::new(),
    companions: std::collections::BTreeMap::new(),
    scanning: false,
    companion_scans: 0,
    task: false,
});

fn scanning_wanted() -> bool {
    let s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    s.scanning || s.companion_scans > 0
}

fn note_companion(c: Companion, now: Instant) {
    let mut s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    s.companions.insert((c.oid.clone(), c.tail), (c, now));
}

/// The Teams phones heard in the last 30 s, with when each was last heard.
pub fn companions() -> Vec<(Companion, Instant)> {
    let mut s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    s.companions.retain(|_, (_, at)| at.elapsed() < KEEP);
    s.companions.values().cloned().collect()
}

/// Scan for Teams phones while a Better Together proximity check runs.
pub fn set_companion_scanning(on: bool) {
    let start = {
        let mut s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
        if on {
            s.companion_scans += 1;
        } else {
            s.companion_scans = s.companion_scans.saturating_sub(1);
        }
        let start = on && !s.task;
        if start {
            s.task = true;
        }
        start
    };
    if start {
        spawn_scan();
    }
}

fn spawn_scan() {
    crate::backend::runtime().spawn(async {
        if let Err(e) = scan().await {
            tracing::info!("Bluetooth discovery: {e}");
        }
        SHARED.lock().unwrap_or_else(|e| e.into_inner()).task = false;
    });
}

fn set_state(state: BleState) {
    SHARED.lock().unwrap_or_else(|e| e.into_inner()).state = state;
}

fn note_beacon(b: Beacon, now: Instant) {
    let mut s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    if !s.seen.contains_key(&b.mri) {
        tracing::info!(room = %b.mri, rssi = b.rssi, adjacent = b.adjacent, "Teams Rooms device nearby");
    }
    s.seen.insert(b.mri.clone(), (b, now));
}

/// Teams keeps a room for 30 s after its last advertisement.
const KEEP: Duration = Duration::from_secs(30);

/// The adapter's state and the Teams Rooms heard lately, strongest first.
pub fn snapshot() -> (BleState, Vec<Beacon>) {
    let mut s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    s.seen.retain(|_, (_, at)| at.elapsed() < KEEP);
    let mut rooms: Vec<Beacon> = s.seen.values().map(|(b, _)| b.clone()).collect();
    rooms.sort_by_key(|b| -b.rssi);
    (s.state, rooms)
}

/// Scan while Room audio is looking for rooms (Teams subscribes to its
/// MTR discovery then); stop when it isn't.
pub fn set_scanning(on: bool) {
    let start = {
        let mut s = SHARED.lock().unwrap_or_else(|e| e.into_inner());
        s.scanning = on;
        let start = on && !s.task;
        if start {
            s.task = true;
        }
        start
    };
    if start {
        spawn_scan();
    }
}

type Objects = HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>;

async fn objects(bus: &zbus::Connection) -> zbus::Result<Objects> {
    let reply = bus
        .call_method(Some("org.bluez"), "/", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &())
        .await?;
    reply.body().deserialize::<Objects>()
}

/// A device's Microsoft manufacturer data, if it has any.
fn manufacturer_data(props: &HashMap<String, OwnedValue>) -> Vec<(u16, Vec<u8>)> {
    fn bytes_of(v: &Value) -> Option<Vec<u8>> {
        match v {
            Value::Value(inner) => bytes_of(inner),
            Value::Array(a) => a.iter().map(|x| u8::try_from(x).ok()).collect(),
            _ => None,
        }
    }
    let Some(Ok(v)) = props.get("ManufacturerData").map(|v| v.try_clone()) else { return Vec::new() };
    let Ok(map) = HashMap::<u16, OwnedValue>::try_from(v) else { return Vec::new() };
    map.into_iter().filter_map(|(company, data)| bytes_of(&data).map(|b| (company, b))).collect()
}

async fn scan() -> zbus::Result<()> {
    let bus = zbus::Connection::system().await?;
    let mut adapter: Option<OwnedObjectPath> = None;
    loop {
        let wanted = scanning_wanted();
        let objs = match objects(&bus).await {
            Ok(o) => o,
            Err(e) => {
                // No BlueZ: no Bluetooth (Teams' isBleSupported false).
                set_state(BleState::default());
                if !wanted {
                    return Ok(());
                }
                tracing::info!("Bluetooth: {e}");
                tokio::time::sleep(Duration::from_secs(5)).await;
                continue;
            }
        };
        let found = pick_adapter(&objs);
        let powered = found
            .and_then(|(_, i)| i["org.bluez.Adapter1"].get("Powered"))
            .and_then(|v| bool::try_from(v).ok())
            .unwrap_or(false);
        let path = found.map(|(p, _)| p.clone());
        set_state(BleState { supported: path.is_some(), radio_on: powered });
        let call = |method: &'static str, p: OwnedObjectPath| {
            let bus = bus.clone();
            async move { bus.call_method(Some("org.bluez"), p.as_str(), Some("org.bluez.Adapter1"), method, &()).await.map(|_| ()) }
        };
        if !wanted {
            if let Some(p) = adapter.take() {
                let _ = call("StopDiscovery", p).await;
                tracing::info!("Bluetooth room discovery stopped");
            }
            return Ok(());
        }
        if adapter.is_none()
            && powered
            && let Some(p) = path.clone()
        {
            let mut filter: HashMap<&str, Value> = HashMap::new();
            filter.insert("Transport", Value::from("le"));
            filter.insert("DuplicateData", Value::from(true));
            let _ = bus
                .call_method(Some("org.bluez"), p.as_str(), Some("org.bluez.Adapter1"), "SetDiscoveryFilter", &(filter,))
                .await;
            match call("StartDiscovery", p.clone()).await {
                Ok(()) => {
                    tracing::info!("Bluetooth room discovery started");
                    adapter = Some(p);
                }
                Err(e) => tracing::info!("Bluetooth discovery: {e}"),
            }
        }
        if !powered {
            adapter = None;
        }
        // The advertisements heard.
        let now = Instant::now();
        for props in objs.values().filter_map(|i| i.get("org.bluez.Device1")) {
            // An emulated radio (btvirt) reports no signal strength:
            // OST_BT_ASSUMED_RSSI stands in for it on such test rigs.
            let Some(rssi) = props
                .get("RSSI")
                .and_then(|v| i16::try_from(v).ok())
                // 127 is HCI's "not available" (what btvirt reports).
                .filter(|r| *r != 127)
                .or_else(|| std::env::var("OST_BT_ASSUMED_RSSI").ok().and_then(|v| v.parse().ok()))
            else {
                continue;
            };
            for (company, data) in manufacturer_data(props) {
                if let Some(b) = parse_beacon(company, &data, rssi) {
                    note_beacon(b, now);
                }
                if let Some(c) = parse_companion(company, &data, rssi) {
                    note_companion(c, now);
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}

/// The adapter OST's Bluetooth uses: `OST_BT_ADAPTER` (such as `hci1`) when
/// set, otherwise the first one BlueZ has (by name, so always the same).
#[allow(clippy::type_complexity)]
fn pick_adapter(objs: &Objects) -> Option<(&OwnedObjectPath, &HashMap<String, HashMap<String, OwnedValue>>)> {
    let wanted = std::env::var("OST_BT_ADAPTER").ok().map(|a| a.trim().to_string()).filter(|a| !a.is_empty());
    let mut adapters: Vec<_> = objs.iter().filter(|(_, i)| i.contains_key("org.bluez.Adapter1")).collect();
    adapters.sort_by(|a, b| a.0.as_str().cmp(b.0.as_str()));
    match wanted {
        Some(name) => adapters.into_iter().find(|(p, _)| p.as_str().rsplit('/').next() == Some(name.as_str())),
        None => adapters.into_iter().next(),
    }
}

/// A Teams Rooms device's Bluetooth beacon (Teams Rooms' DevicesBLEService):
/// Microsoft's manufacturer data naming the room account and its current
/// proximity validation code, advertised non-connectable, so laptops nearby
/// list the room under Room audio's Nearby and send the code back as their
/// invitation's autoAcceptAuthorization.
struct Advertisement {
    data: Vec<u8>,
}

#[zbus::interface(name = "org.bluez.LEAdvertisement1")]
impl Advertisement {
    #[zbus(property, name = "Type")]
    fn kind(&self) -> String {
        "broadcast".into()
    }
    #[zbus(property)]
    fn manufacturer_data(&self) -> HashMap<u16, OwnedValue> {
        let mut m = HashMap::new();
        if let Ok(v) = OwnedValue::try_from(Value::from(self.data.clone())) {
            m.insert(teams_cli::api::rooms::BEACON_COMPANY, v);
        }
        m
    }
    /// BlueZ dropped the advertisement (its adapter went away).
    fn release(&self) {
        tracing::info!("Teams Rooms beacon released by BlueZ");
    }
}

const ADVERT_PATH: &str = "/com/ost/room/beacon";

/// Advertise the room `object_id`'s beacon with each validation code
/// `codes` sends, until it closes (BlueZ reads an advertisement's data
/// once, so each new code registers it again).
pub fn advertise(object_id: String, mut codes: tokio::sync::watch::Receiver<u16>) {
    crate::backend::runtime().spawn(async move {
        let mut registered: Option<OwnedObjectPath> = None;
        loop {
            let code = *codes.borrow_and_update();
            match register(&object_id, code, registered.take()).await {
                Ok(adapter) => {
                    tracing::debug!(adapter = adapter.as_str(), "Teams Rooms beacon advertised");
                    registered = Some(adapter);
                }
                Err(e) => tracing::info!("Teams Rooms beacon: {e}"),
            }
            tokio::select! {
                r = codes.changed() => if r.is_err() { break },
                // A failed advertisement is tried again (no adapter yet,
                // the radio off).
                _ = tokio::time::sleep(Duration::from_secs(30)), if registered.is_none() => {}
            }
        }
        if let Some(adapter) = registered {
            let _ = unregister(&adapter).await;
        }
    });
}

async fn system_bus() -> zbus::Result<zbus::Connection> {
    static BUS: tokio::sync::OnceCell<zbus::Connection> = tokio::sync::OnceCell::const_new();
    BUS.get_or_try_init(zbus::Connection::system).await.cloned()
}

async fn unregister(adapter: &OwnedObjectPath) -> zbus::Result<()> {
    let bus = system_bus().await?;
    let path = zbus::zvariant::ObjectPath::try_from(ADVERT_PATH)?;
    let r = bus
        .call_method(Some("org.bluez"), adapter.as_str(), Some("org.bluez.LEAdvertisingManager1"), "UnregisterAdvertisement", &(path,))
        .await;
    let _ = bus.object_server().remove::<Advertisement, _>(ADVERT_PATH).await;
    r.map(|_| ())
}

async fn register(object_id: &str, code: u16, previous: Option<OwnedObjectPath>) -> zbus::Result<OwnedObjectPath> {
    if let Some(p) = previous {
        let _ = unregister(&p).await;
    }
    let data = teams_cli::api::rooms::beacon_data(object_id, code).ok_or_else(|| zbus::Error::Failure("not a room id".into()))?;
    let bus = system_bus().await?;
    let objs = objects(&bus).await?;
    let (adapter, ifaces) = pick_adapter(&objs).ok_or_else(|| zbus::Error::Failure("no Bluetooth adapter".into()))?;
    if !ifaces.contains_key("org.bluez.LEAdvertisingManager1") {
        return Err(zbus::Error::Failure("the adapter can't advertise".into()));
    }
    let adapter = adapter.clone();
    bus.object_server().at(ADVERT_PATH, Advertisement { data }).await?;
    let path = zbus::zvariant::ObjectPath::try_from(ADVERT_PATH)?;
    let options: HashMap<&str, Value> = HashMap::new();
    bus.call_method(Some("org.bluez"), adapter.as_str(), Some("org.bluez.LEAdvertisingManager1"), "RegisterAdvertisement", &(path, options))
        .await?;
    Ok(adapter)
}
