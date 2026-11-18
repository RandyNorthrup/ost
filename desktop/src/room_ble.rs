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
    scanning: bool,
    task: bool,
}

static SHARED: Mutex<Shared> = Mutex::new(Shared {
    state: BleState { supported: false, radio_on: false },
    seen: std::collections::BTreeMap::new(),
    scanning: false,
    task: false,
});

fn scanning_wanted() -> bool {
    SHARED.lock().unwrap_or_else(|e| e.into_inner()).scanning
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
        crate::backend::runtime().spawn(async {
            if let Err(e) = scan().await {
                tracing::info!("Bluetooth room discovery: {e}");
            }
            SHARED.lock().unwrap_or_else(|e| e.into_inner()).task = false;
        });
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
        let found = objs.iter().find(|(_, i)| i.contains_key("org.bluez.Adapter1"));
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
            let Some(rssi) = props.get("RSSI").and_then(|v| i16::try_from(v).ok()) else { continue };
            for (company, data) in manufacturer_data(props) {
                if let Some(b) = parse_beacon(company, &data, rssi) {
                    note_beacon(b, now);
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}
