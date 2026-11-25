//! Teams' View Diagnostic Data (Settings ▸ Privacy ▸ Manage; settings-app
//! FF/RF and its trusted-UI viewer page): with "Enable data viewing" on and a
//! Windows device's Diagnostic Data Viewer connection string entered, the app
//! streams its diagnostic data to that viewer over HTTP for 24 hours.
//!
//! Unlike Teams (which sends plain HTTP to any private address), OST sends
//! plain HTTP only to this device (a loopback address); a viewer elsewhere
//! takes an `https://` address, or a port forwarded to it over SSH
//! (`ssh -L 7070:<windows device>:<port> …`, then `127.0.0.1:7070`).
//!
//! OST has no telemetry of its own; what it sends that is diagnostic data
//! (the update check, Report a problem and its call quality details,
//! suggested-reply feedback) is recorded here, and while viewing is on each
//! of those events goes to the viewer too, so it lists exactly what OST
//! sends.

use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// Teams' viewer disconnects after a day.
pub const CONNECTION_LIFETIME_SECS: u64 = 24 * 60 * 60;

/// The viewer's state, as the Manage page shows it.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct DdvState {
    pub enabled: bool,
    #[serde(rename = "connectionString")]
    pub connection_string: String,
    /// "idle", "connecting", "connected" or "failed" (Teams' Wn).
    pub state: String,
    /// When the connection was made (Unix seconds).
    #[serde(rename = "connectedAt")]
    pub connected_at: u64,
}

static STATE: Mutex<Option<DdvState>> = Mutex::new(None);
/// What OST has sent this run, newest last: (Unix ms, name, data).
static EVENTS: Mutex<Vec<(u64, String, serde_json::Value)>> = Mutex::new(Vec::new());

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// $XDG_CONFIG_HOME/ost/ddv.json (per device, beside desktop.json).
fn state_path() -> Option<std::path::PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")))
        .map(|b| b.join("ost").join("ddv.json"))
}

/// The viewer's state (kept on this device, as Teams' host keeps it).
pub fn state() -> DdvState {
    let mut g = STATE.lock().unwrap_or_else(|e| e.into_inner());
    if g.is_none() {
        let loaded = state_path()
            .and_then(|p| std::fs::read(p).ok())
            .and_then(|b| serde_json::from_slice::<DdvState>(&b).ok())
            .unwrap_or_default();
        *g = Some(loaded);
    }
    let mut s = g.clone().unwrap_or_default();
    // A day on, the connection is over; so is one to an address OST no
    // longer sends to (a private address saved by an older OST).
    if s.state == "connected"
        && (now_secs().saturating_sub(s.connected_at) > CONNECTION_LIFETIME_SECS
            || parse_connection_string(&s.connection_string).is_err())
    {
        s.state = "idle".into();
        *g = Some(s.clone());
    }
    if s.state.is_empty() {
        s.state = "idle".into();
    }
    s
}

fn save(s: &DdvState) {
    *STATE.lock().unwrap_or_else(|e| e.into_inner()) = Some(s.clone());
    if let Some(p) = state_path() {
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(p, serde_json::to_vec(s).unwrap_or_default());
    }
}

/// "Enable data viewing": on keeps the connection string; off ends it.
pub fn set_enabled(on: bool) {
    let mut s = state();
    s.enabled = on;
    s.state = "idle".into();
    s.connected_at = 0;
    save(&s);
}

/// The viewer's address from a connection string: `host[:port]` or
/// `http://host[:port]` for a viewer on this device (a loopback address:
/// 127.0.0.0/8, ::1, localhost), or `https://host[:port]` for any other.
/// Plain HTTP to another device is refused: the events would cross the
/// network unencrypted.
pub fn parse_connection_string(s: &str) -> Result<String> {
    let s = s.trim();
    if s.is_empty() {
        bail!("No connection string");
    }
    let with_scheme = if s.contains("://") {
        s.to_string()
    } else {
        format!("http://{s}")
    };
    let u = url::Url::parse(&with_scheme).context("Not a connection string")?;
    if !u.username().is_empty()
        || u.password().is_some()
        || u.query().is_some()
        || u.fragment().is_some()
        || !matches!(u.path(), "" | "/")
    {
        bail!("Not a connection string");
    }
    let host = u.host().context("Not a connection string")?;
    let loopback = match &host {
        url::Host::Ipv4(ip) => ip.is_loopback(),
        url::Host::Ipv6(ip) => ip.is_loopback(),
        url::Host::Domain(d) => d.eq_ignore_ascii_case("localhost"),
    };
    match u.scheme() {
        "https" => {}
        "http" if loopback => {}
        "http" => bail!(
            "Plain HTTP goes only to this device (a loopback address such as 127.0.0.1); use https:// or an SSH tunnel for a viewer on another device"
        ),
        _ => bail!("Not a connection string"),
    }
    let port = u.port().map(|p| format!(":{p}")).unwrap_or_default();
    Ok(format!("{}://{}{port}/", u.scheme(), host))
}

/// Teams' Connect: Connecting, then Connected or Couldn't connect.
pub async fn connect(connection_string: &str) -> Result<DdvState> {
    let mut s = state();
    s.connection_string = connection_string.trim().to_string();
    s.state = "connecting".into();
    save(&s);
    let ok = match parse_connection_string(&s.connection_string) {
        Ok(base) => wire::handshake(&base).await.is_ok(),
        Err(e) => {
            tracing::info!("diagnostic data viewer: {e:#}");
            false
        }
    };
    let mut s = state();
    s.state = if ok { "connected" } else { "failed" }.into();
    s.connected_at = if ok { now_secs() } else { 0 };
    save(&s);
    if ok {
        // What was sent before the connection goes first.
        let earlier: Vec<_> = EVENTS.lock().unwrap_or_else(|e| e.into_inner()).clone();
        for (at, name, data) in earlier {
            let _ = wire::send(&s.connection_string, at, &name, &data).await;
        }
    }
    Ok(s)
}

/// Note one piece of diagnostic data OST sends (an event name such as
/// "Ost.UpdateCheck" and its fields); while viewing, it goes to the viewer.
pub fn record(name: &str, data: serde_json::Value) {
    let at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    {
        let mut ev = EVENTS.lock().unwrap_or_else(|e| e.into_inner());
        ev.push((at, name.to_string(), data.clone()));
        let n = ev.len();
        if n > 500 {
            ev.drain(..n - 500);
        }
    }
    let s = state();
    tracing::info!(
        event = name,
        viewing = s.enabled && s.state == "connected",
        "diagnostic data"
    );
    if s.enabled && s.state == "connected" {
        let name = name.to_string();
        if let Ok(rt) = tokio::runtime::Handle::try_current() {
            rt.spawn(async move {
                if let Err(e) = wire::send(&s.connection_string, at, &name, &data).await {
                    tracing::warn!("diagnostic data viewer: {e:#}");
                }
            });
        }
    }
}

/// What OST has sent this run: [{time, name, data}].
pub fn events() -> Vec<serde_json::Value> {
    EVENTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .iter()
        .map(|(at, name, data)| serde_json::json!({ "time": at, "name": name, "data": data }))
        .collect()
}

mod wire;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_http_goes_only_to_this_device() {
        assert_eq!(
            parse_connection_string("127.0.0.1:7070").unwrap(),
            "http://127.0.0.1:7070/"
        );
        assert_eq!(
            parse_connection_string("localhost").unwrap(),
            "http://localhost/"
        );
        assert_eq!(
            parse_connection_string("[::1]:7070").unwrap(),
            "http://[::1]:7070/"
        );
        assert_eq!(
            parse_connection_string("http://127.0.0.2:80").unwrap(),
            "http://127.0.0.2/"
        );
        // Another device: https only.
        for refused in [
            "10.10.11.64",
            "192.168.1.5:7070",
            "http://10.0.0.1:7070",
            "8.8.8.8",
            "example.com",
            "http://localhost.evil.example",
            "10.0.0.1:x",
            "",
            "https://user@10.0.0.1",
            "https://10.0.0.1/path",
            "ftp://127.0.0.1",
        ] {
            assert!(parse_connection_string(refused).is_err(), "{refused}");
        }
        assert_eq!(
            parse_connection_string("https://10.10.11.64:7070").unwrap(),
            "https://10.10.11.64:7070/"
        );
        assert_eq!(
            parse_connection_string("https://ddv.example").unwrap(),
            "https://ddv.example/"
        );
    }
}
