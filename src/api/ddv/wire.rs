//! The Diagnostic Data Viewer's wire format, as Teams' host speaks it
//! (captured from Teams 26304 on winpc against a listener, 2026-11-19):
//! - Connect: `GET http://<ip>:<port>/`, then an empty `POST /` with the
//!   headers below; a 2xx answer to both is "Connection established".
//! - Events: `POST /`, `Content-Type: Application/bond-compact-binary`, the
//!   body raw-deflated Common Schema 3.0 records (1DS `CsProtocol::Record`)
//!   in Bond CompactBinary v1, one after another.
//! - Headers: App-Name, App-Platform, Machine-Identifier, Cache-Control
//!   no-cache, Accept */*.
//!
//! Each record is laid out as Teams' are: 1 ver "3.0", 2 name, 3 time (.NET
//! ticks), 5 iKey, 6 flags 257, 23 device {2 localId, 5 deviceClass}, 24
//! os {4 name, 5 ver}, 25 app {5 id, 6 ver, 8 name}, 32 sdk {1 libVer,
//! 2 epoch, 3 seq, 4 installId}, 33 loc {3 tz}, 60 the event's type, 70 data
//! [{1 properties: map<string, {3 string}>}].

use std::io::Write;
use std::sync::atomic::{AtomicI64, Ordering};

use anyhow::{bail, Context, Result};

// Bond CompactBinary field types.
const BT_STOP: u8 = 0;
const BT_STRING: u8 = 9;
const BT_STRUCT: u8 = 10;
const BT_LIST: u8 = 11;
const BT_MAP: u8 = 13;
const BT_INT64: u8 = 17;

/// What OST says it is (Teams: "ms-teams", "Windows.Desktop").
const APP_NAME: &str = "ost";
const APP_PLATFORM: &str = "Linux.Desktop";
/// The tenant key a record names (Teams' is its own 1DS token).
const IKEY: &str = "o:ost";

fn varint(out: &mut Vec<u8>, mut v: u64) {
    loop {
        let b = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(b);
            return;
        }
        out.push(b | 0x80);
    }
}

fn field(out: &mut Vec<u8>, id: u16, ty: u8) {
    if id <= 5 {
        out.push(((id as u8) << 5) | ty);
    } else if id <= 0xff {
        out.push((6 << 5) | ty);
        out.push(id as u8);
    } else {
        out.push((7 << 5) | ty);
        out.extend_from_slice(&id.to_le_bytes());
    }
}

fn string(out: &mut Vec<u8>, s: &str) {
    varint(out, s.len() as u64);
    out.extend_from_slice(s.as_bytes());
}

fn str_field(out: &mut Vec<u8>, id: u16, s: &str) {
    field(out, id, BT_STRING);
    string(out, s);
}

fn i64_field(out: &mut Vec<u8>, id: u16, v: i64) {
    field(out, id, BT_INT64);
    varint(out, ((v << 1) ^ (v >> 63)) as u64);
}

/// A field holding a one-element list of a struct (Common Schema's
/// extensions), built by `body`.
fn ext(out: &mut Vec<u8>, id: u16, body: impl FnOnce(&mut Vec<u8>)) {
    field(out, id, BT_LIST);
    out.push(BT_STRUCT);
    varint(out, 1);
    body(out);
    out.push(BT_STOP);
}

/// .NET ticks (100 ns since 0001-01-01) for Unix milliseconds.
pub fn ticks(unix_ms: u64) -> i64 {
    unix_ms as i64 * 10_000 + 621_355_968_000_000_000
}

static SEQ: AtomicI64 = AtomicI64::new(0);

fn ids() -> (&'static str, &'static str) {
    static IDS: std::sync::OnceLock<(String, String)> = std::sync::OnceLock::new();
    let (a, b) = IDS.get_or_init(|| (uuid::Uuid::new_v4().to_string().to_uppercase(), uuid::Uuid::new_v4().to_string().to_uppercase()));
    (a, b)
}

fn os_version() -> String {
    std::fs::read_to_string("/etc/os-release")
        .ok()
        .and_then(|s| s.lines().find_map(|l| l.strip_prefix("VERSION_ID=").map(|v| v.trim_matches('"').to_string())))
        .unwrap_or_default()
}

fn utc_offset() -> String {
    let secs = chrono::Local::now().offset().local_minus_utc();
    let (sign, m) = if secs < 0 { ('-', -secs / 60) } else { ('+', secs / 60) };
    format!("{sign}{:02}:{:02}", m / 60, m % 60)
}

/// One Common Schema record for an event OST sends.
pub fn record(at_ms: u64, name: &str, data: &serde_json::Value) -> Vec<u8> {
    let mut o = Vec::new();
    str_field(&mut o, 1, "3.0");
    str_field(&mut o, 2, name);
    i64_field(&mut o, 3, ticks(at_ms));
    str_field(&mut o, 5, IKEY);
    i64_field(&mut o, 6, 257);
    let (epoch, install) = ids();
    ext(&mut o, 23, |o| {
        str_field(o, 2, &format!("c:{}", install.to_lowercase()));
        str_field(o, 5, APP_PLATFORM);
    });
    ext(&mut o, 24, |o| {
        str_field(o, 4, "Linux");
        str_field(o, 5, &os_version());
    });
    ext(&mut o, 25, |o| {
        str_field(o, 5, APP_NAME);
        str_field(o, 6, env!("CARGO_PKG_VERSION"));
        str_field(o, 8, APP_NAME);
    });
    ext(&mut o, 32, |o| {
        str_field(o, 1, concat!("OST-", env!("CARGO_PKG_VERSION")));
        str_field(o, 2, epoch);
        i64_field(o, 3, SEQ.fetch_add(1, Ordering::Relaxed) + 1);
        str_field(o, 4, install);
    });
    ext(&mut o, 33, |o| str_field(o, 3, &utc_offset()));
    str_field(&mut o, 60, name);
    // Data: the event's fields as strings (as Teams sends all of its own).
    let mut props: Vec<(String, String)> = vec![("AppInfo.ClientType".into(), APP_NAME.into()), ("AppInfo.Version".into(), env!("CARGO_PKG_VERSION").into())];
    if let Some(map) = data.as_object() {
        for (k, v) in map {
            let s = match v {
                serde_json::Value::String(s) => s.clone(),
                other => other.to_string(),
            };
            props.push((k.clone(), s));
        }
    }
    ext(&mut o, 70, |o| {
        field(o, 1, BT_MAP);
        o.push(BT_STRING);
        o.push(BT_STRUCT);
        varint(o, props.len() as u64);
        for (k, v) in &props {
            string(o, k);
            str_field(o, 3, v);
            o.push(BT_STOP);
        }
    });
    o.push(BT_STOP);
    o
}

fn url(target: (std::net::Ipv4Addr, Option<u16>)) -> String {
    match target.1 {
        Some(p) => format!("http://{}:{p}/", target.0),
        None => format!("http://{}/", target.0),
    }
}

fn post(http: &reqwest::Client, url: &str, body: Vec<u8>) -> reqwest::RequestBuilder {
    let host = std::fs::read_to_string("/etc/hostname").map(|h| h.trim().to_string()).unwrap_or_default();
    // The viewer wants the length even of the empty Connect POST (Teams
    // sends "Content-Length: 0"); without it Microsoft's Diagnostic Data
    // Viewer answers 411 and then stops answering anyone (seen on winpc,
    // DDV 4.2209, 2026-11-19).
    let len = body.len();
    http.post(url)
        .header("Accept", "*/*")
        .header("App-Name", APP_NAME)
        .header("App-Platform", APP_PLATFORM)
        .header("Content-Type", "Application/bond-compact-binary")
        .header("Machine-Identifier", host)
        .header("Content-Length", len)
        .header("Cache-Control", "no-cache")
        .body(body)
}

/// Each request on a connection of its own, its headers title-cased as
/// Teams' host sends them.
fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .http1_title_case_headers()
        .pool_max_idle_per_host(0)
        .build()?)
}

/// Teams' Connect: the viewer answers a GET and an empty POST.
pub async fn handshake(target: (std::net::Ipv4Addr, Option<u16>)) -> Result<()> {
    let http = client()?;
    let u = url(target);
    let r = http.get(&u).header("Accept", "*/*").send().await.context("Diagnostic Data Viewer")?;
    if !r.status().is_success() {
        bail!("Diagnostic Data Viewer: HTTP {}", r.status().as_u16());
    }
    let r = post(&http, &u, Vec::new()).send().await.context("Diagnostic Data Viewer")?;
    if !r.status().is_success() {
        bail!("Diagnostic Data Viewer: HTTP {}", r.status().as_u16());
    }
    Ok(())
}

/// One event to the viewer at `connection` (raw-deflated, as Teams sends).
pub async fn send(connection: &str, at_ms: u64, name: &str, data: &serde_json::Value) -> Result<()> {
    let target = super::parse_connection_string(connection)?;
    let mut z = flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::default());
    z.write_all(&record(at_ms, name, data))?;
    let body = z.finish()?;
    let r = post(&client()?, &url(target), body).send().await.context("Diagnostic Data Viewer")?;
    if !r.status().is_success() {
        bail!("Diagnostic Data Viewer: HTTP {}", r.status().as_u16());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_are_bond_compact_like_teams() {
        let r = record(1_763_550_000_000, "Ost.UpdateCheck", &serde_json::json!({ "status": 200, "url": "u" }));
        // 1 ver "3.0", then 2 name.
        assert_eq!(&r[..5], &[0x29, 3, b'3', b'.', b'0']);
        assert_eq!(r[5], 0x49);
        assert_eq!(r[6] as usize, "Ost.UpdateCheck".len());
        assert_eq!(*r.last().unwrap(), BT_STOP);
        // Field 60 goes as an id byte after the type.
        let pos = r.windows(2).position(|w| w == [(6 << 5) | BT_STRING, 60]).unwrap();
        assert!(pos > 7);
    }

    #[test]
    fn ticks_are_dotnet_ticks() {
        // Teams' record: 639306929860371940 ticks ≈ 2026-11-19.
        let ms = (639_306_929_860_371_940_i64 - 621_355_968_000_000_000) / 10_000;
        assert_eq!(ticks(ms as u64) / 10_000, 639_306_929_860_371_940 / 10_000);
    }
}
