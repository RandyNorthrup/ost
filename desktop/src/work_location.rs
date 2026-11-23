//! Workplace check-in over Wi-Fi (TASK-0149), as Teams desktop does it:
//! with the tenant's work-location detection policy on and your Settings ▸
//! Privacy ▸ "Manage my work location" switch on, every Wi-Fi network
//! change (connecting, switching access point, waking) is checked against
//! the tenant's office networks (the SSID allow list, kept a day). On one
//! of them the access point is reported and the location service checks
//! you in (at its building, or "In the office"); on another network you
//! are checked out where Teams does that (its adlCheckout flight, and only
//! from a check-in's work location). Teams reads Windows' WLAN API; OST
//! reads the network
//! from NetworkManager over D-Bus. Wired connections are not used (Teams'
//! workplace check-in is Wi-Fi only).

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

/// The Wi-Fi network the computer reaches the network through: (SSID,
/// BSSID), or None on a wired or no connection.
pub async fn current_wifi() -> Option<(String, String)> {
    let conn = zbus::Connection::system().await.ok()?;
    let nm = NetworkManagerProxy::new(&conn).await.ok()?;
    let primary = nm.primary_connection().await.ok()?;
    if primary.as_str() == "/" {
        return None;
    }
    let active = ActiveConnectionProxy::builder(&conn).path(primary).ok()?.build().await.ok()?;
    if active.kind().await.ok()? != "802-11-wireless" {
        return None;
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
    Some((ssid, bssid))
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
/// at the start).
async fn watch() {
    let mut last: Option<Option<(String, String)>> = None;
    let mut allow: Option<(Instant, Vec<String>)> = None;
    loop {
        if ENABLED.load(Ordering::SeqCst) {
            let now = current_wifi().await;
            if last.as_ref() != Some(&now) {
                last = Some(now.clone());
                if let Some((ssid, bssid)) = now {
                    match process(&ssid, &bssid, &mut allow).await {
                        Ok(r) => tracing::info!("WORKLOC network change: {r}"),
                        Err(e) => tracing::warn!("WORKLOC network change failed: {e:#}"),
                    }
                } else {
                    tracing::info!("WORKLOC not on Wi-Fi");
                }
            }
        } else {
            last = None;
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

async fn process(ssid: &str, bssid: &str, allow: &mut Option<(Instant, Vec<String>)>) -> anyhow::Result<String> {
    let client = TeamsClient::new().await?;
    let epid = api::presence::changes().borrow().epid.clone().unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    // Teams keeps the tenant's list a day (DEFAULT_SSID_ALLOW_LIST_TTL).
    if allow.as_ref().map(|(t, _)| t.elapsed() > Duration::from_secs(86_400)).unwrap_or(true) {
        *allow = Some((Instant::now(), places::ssid_allow_list(&client, &epid).await?));
    }
    let list = &allow.as_ref().map(|(_, l)| l.clone()).unwrap_or_default();
    if !list.iter().any(|s| s == ssid) {
        // Not an office network. Teams checks out (its processCheckout)
        // only with the adlCheckout flight and only a work location a
        // check-in set (presence locationSource VerifiedLocation).
        let checkout = api::ecs::setting("places", "adlCheckout").and_then(|v| v.as_bool()).unwrap_or(false);
        if checkout && !ssid.is_empty() && checked_in_now(&client).await {
            places::report_remote(&client, &epid).await?;
            return Ok("checked out (not an office network)".into());
        }
        return Ok(format!("not an office network ({} listed)", list.len()));
    }
    let with_ssid = api::ecs::setting("places", "useSSIDForIC3LSNetworkApiRequest").and_then(|v| v.as_bool()).unwrap_or(false);
    let body = places::network_body(bssid, with_ssid.then_some(ssid), chrono::Utc::now());
    let r = places::report_network(&client, &epid, &body).await?;
    Ok(format!("{r:?}"))
}

/// Whether your work location now is a check-in's (Teams'
/// hasVerifiedLocationPresence).
async fn checked_in_now(client: &TeamsClient) -> bool {
    let Some(oid) = client.object_id() else { return false };
    api::presence::get_presences(client.http(), &[format!("8:orgid:{oid}")])
        .await
        .ok()
        .and_then(|l| l.into_iter().next())
        .is_some_and(|p| p.work_location_source == "VerifiedLocation")
}
