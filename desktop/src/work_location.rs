//! Workplace check-in over Wi-Fi (TASK-0149), as Teams desktop does it
//! (Teams 26304: the ADL job's action strategy with adlWiredCheckout, and
//! the worker's WifiAutoLocationHelper). With the tenant's work-location
//! detection policy on and your Settings ▸ Privacy ▸ "Manage my work
//! location" switch on, each network change (connecting, switching access
//! point, waking) is handled once:
//! - On Wi-Fi whose SSID is one of the tenant's office networks (the SSID
//!   allow list, kept a day): the access point is reported and the location
//!   service checks you in (at its building, or "In the office").
//! - On another Wi-Fi network, or on a wired connection: you are checked
//!   out, but only from a work location a check-in set (presence
//!   locationSource VerifiedLocation), with Teams' adlCheckout flight, and
//!   on a wired connection not when this device's stationary location
//!   (Privacy ▸ Stationary device location) is that building.
//! - With no network, or an empty allow list, nothing happens.
//! Reports and check-outs wait for an unlocked machine, as Teams'
//! useUserStateForWiFiUpdate. Teams reads Windows' WLAN API and needs the
//! OS location permission; OST reads the network from NetworkManager over
//! D-Bus.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use teams_cli::api::{self, client::TeamsClient, places};

#[zbus::proxy(interface = "org.freedesktop.NetworkManager", default_service = "org.freedesktop.NetworkManager", default_path = "/org/freedesktop/NetworkManager")]
trait NetworkManager {
    #[zbus(property)]
    fn primary_connection(&self) -> zbus::Result<zbus::zvariant::OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Connection.Active", default_service = "org.freedesktop.NetworkManager")]
trait ActiveConnection {
    #[zbus(property, name = "Type")]
    fn kind(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn devices(&self) -> zbus::Result<Vec<zbus::zvariant::OwnedObjectPath>>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Device.Wireless", default_service = "org.freedesktop.NetworkManager")]
trait Wireless {
    #[zbus(property)]
    fn active_access_point(&self) -> zbus::Result<zbus::zvariant::OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.AccessPoint", default_service = "org.freedesktop.NetworkManager")]
trait AccessPoint {
    #[zbus(property)]
    fn ssid(&self) -> zbus::Result<Vec<u8>>;
    #[zbus(property)]
    fn hw_address(&self) -> zbus::Result<String>;
}

/// How the computer reaches the network.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Network {
    /// Wi-Fi: (SSID, BSSID).
    Wifi(String, String),
    /// Online through something else (Ethernet, a dock, a VPN on it).
    Wired,
    /// No network.
    Offline,
}

/// NetworkManager's primary connection.
pub async fn current_network() -> Network {
    let Ok(conn) = zbus::Connection::system().await else { return Network::Offline };
    let Ok(nm) = NetworkManagerProxy::new(&conn).await else { return Network::Offline };
    let Ok(primary) = nm.primary_connection().await else { return Network::Offline };
    if primary.as_str() == "/" {
        return Network::Offline;
    }
    let wifi = async {
        let active = ActiveConnectionProxy::builder(&conn).path(primary).ok()?.build().await.ok()?;
        if active.kind().await.ok()? != "802-11-wireless" {
            return Some(None);
        }
        let device = active.devices().await.ok()?.into_iter().next()?;
        let wireless = WirelessProxy::builder(&conn).path(device).ok()?.build().await.ok()?;
        let ap_path = wireless.active_access_point().await.ok()?;
        if ap_path.as_str() == "/" {
            return None;
        }
        let ap = AccessPointProxy::builder(&conn).path(ap_path).ok()?.build().await.ok()?;
        let ssid = String::from_utf8_lossy(&ap.ssid().await.ok()?).to_string();
        let bssid = ap.hw_address().await.ok()?.to_lowercase();
        Some(Some((ssid, bssid)))
    }
    .await;
    match wifi {
        Some(Some((ssid, bssid))) => Network::Wifi(ssid, bssid),
        Some(None) => Network::Wired,
        // Wireless without an access point yet: not settled, as offline.
        None => Network::Offline,
    }
}

static ENABLED: AtomicBool = AtomicBool::new(false);
static RUNNING: AtomicBool = AtomicBool::new(false);

/// Turn the check-in on or off (the policy and your switch, from Settings'
/// state); the watcher starts the first time it is on.
pub fn set_enabled(on: bool, runtime: &tokio::runtime::Runtime) {
    let was = ENABLED.swap(on, Ordering::SeqCst);
    tracing::info!("WORKLOC detection {}", if on { "on" } else { "off" });
    if on && !was && !RUNNING.swap(true, Ordering::SeqCst) {
        runtime.spawn(watch());
    }
}

/// Teams reacts to network change events; OST looks at NetworkManager's
/// primary connection every few seconds and acts when it changes (and once
/// at the start). A change seen while the machine is locked is handled once
/// it is unlocked.
async fn watch() {
    let mut last: Option<Network> = None;
    let mut allow: Option<(Instant, Vec<String>)> = None;
    loop {
        if ENABLED.load(Ordering::SeqCst) && !api::presence::changes().borrow().locked {
            let now = current_network().await;
            if last.as_ref() != Some(&now) {
                last = Some(now.clone());
                match process(&now, &mut allow).await {
                    Ok(r) => tracing::info!("WORKLOC network change: {r}"),
                    Err(e) => tracing::warn!("WORKLOC network change failed: {e:#}"),
                }
            }
        } else if !ENABLED.load(Ordering::SeqCst) {
            last = None;
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

/// What Teams does for a network (its getActionStrategyV2).
#[derive(Debug, PartialEq, Eq)]
pub enum Action {
    Report,
    CheckOut(&'static str),
    Skip,
}

/// Teams' decision: an empty allow list stops everything; a listed Wi-Fi
/// network is reported; another Wi-Fi network (SSID_MISMATCH) or a wired
/// connection (WIRED_CONNECTION) checks out; no network does nothing.
pub fn action_for(network: &Network, allow_list: &[String]) -> Action {
    if allow_list.is_empty() {
        return Action::Skip;
    }
    match network {
        Network::Wifi(ssid, _) if allow_list.iter().any(|s| s == ssid) => Action::Report,
        Network::Wifi(ssid, _) if !ssid.is_empty() => Action::CheckOut("SSID_MISMATCH"),
        // No SSID (hidden network): never on the list (SSID_NOT_ALLOWED).
        Network::Wifi(..) => Action::Skip,
        Network::Wired => Action::CheckOut("WIRED_CONNECTION"),
        Network::Offline => Action::Skip,
    }
}

/// A Places flight, at Teams' bundled default (config-prod) unless ECS
/// says otherwise.
fn places_flag(key: &str, default: bool) -> bool {
    api::ecs::setting("places", key).and_then(|v| v.as_bool()).unwrap_or(default)
}

async fn process(network: &Network, allow: &mut Option<(Instant, Vec<String>)>) -> anyhow::Result<String> {
    if *network == Network::Offline {
        return Ok("offline".into());
    }
    let client = TeamsClient::new().await?;
    let epid = api::presence::changes().borrow().epid.clone().unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    // Teams keeps the tenant's list a day (DEFAULT_SSID_ALLOW_LIST_TTL).
    if allow.as_ref().map(|(t, _)| t.elapsed() > Duration::from_secs(86_400)).unwrap_or(true) {
        *allow = Some((Instant::now(), places::ssid_allow_list(&client, &epid).await?));
    }
    let list = allow.as_ref().map(|(_, l)| l.clone()).unwrap_or_default();
    match action_for(network, &list) {
        Action::Skip => Ok(format!("nothing to do ({network:?}, {} office networks)", list.len())),
        Action::Report => {
            let Network::Wifi(ssid, bssid) = network else { return Ok("not on Wi-Fi".into()) };
            let with_ssid = places_flag("useSSIDForIC3LSNetworkApiRequest", true);
            let body = places::network_body(bssid, with_ssid.then_some(ssid.as_str()), chrono::Utc::now());
            let r = places::report_network(&client, &epid, &body).await?;
            Ok(format!("{r:?}"))
        }
        Action::CheckOut(reason) => {
            if !places_flag("adlCheckout", true) {
                return Ok(format!("{reason}: check-out flight off"));
            }
            let Some((source, building_id)) = my_work_location(&client).await else {
                return Ok(format!("{reason}: no work location"));
            };
            if source != "VerifiedLocation" {
                return Ok(format!("{reason}: work location not from a check-in"));
            }
            // A stationary device stays checked in at its building.
            let home = crate::backend::load_settings().get("deviceHomeBuildingId").and_then(|v| v.as_str()).unwrap_or_default().to_string();
            if reason == "WIRED_CONNECTION" && !home.is_empty() && home == building_id {
                return Ok(format!("{reason}: at this device's stationary building"));
            }
            places::report_remote(&client, &epid).await?;
            Ok(format!("{reason}: checked out"))
        }
    }
}

/// Your work location's source and building id (Teams'
/// getCurrentVerifiedLocation), or None when none is set.
async fn my_work_location(client: &TeamsClient) -> Option<(String, String)> {
    let oid = client.object_id()?;
    let p = api::presence::get_presences(client.http(), &[format!("8:orgid:{oid}")]).await.ok()?.into_iter().next()?;
    (!p.work_location.is_empty()).then_some((p.work_location_source, p.work_location_building_id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn teams_action_strategy() {
        let list = vec!["Condor Cave".to_string()];
        let wifi = |s: &str| Network::Wifi(s.into(), "f4:92:bf:78:c4:67".into());
        assert_eq!(action_for(&wifi("Condor Cave"), &list), Action::Report);
        assert_eq!(action_for(&wifi("Cafe"), &list), Action::CheckOut("SSID_MISMATCH"));
        assert_eq!(action_for(&Network::Wired, &list), Action::CheckOut("WIRED_CONNECTION"));
        assert_eq!(action_for(&Network::Offline, &list), Action::Skip);
        // An empty allow list: Teams unsubscribes (EMPTY_SSID_ALLOWLIST).
        assert_eq!(action_for(&wifi("Condor Cave"), &[]), Action::Skip);
        assert_eq!(action_for(&Network::Wired, &[]), Action::Skip);
    }
}
