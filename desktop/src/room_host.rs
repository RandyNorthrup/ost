//! OST as a Teams Rooms device (room mode): the room's proximity salts and
//! Bluetooth beacon, and its answer to an invitation
//! (`teams_cli::calling::room_mode`).
//!
//! Room mode is on when the signed-in account has a Teams Rooms licence
//! (authz `licenseDetails.meetingRoomLicenseCategories`), or with `--room`
//! / `OST_ROOM=1`.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use teams_cli::calling::incoming::IncomingCall;
use teams_cli::calling::room_mode::{self, AutoAccept, Decision, Salts, Settings};

static SALTS: Mutex<Option<Salts>> = Mutex::new(None);

/// Whether this OST should run as a Teams Rooms device.
pub fn wanted(license: Option<&serde_json::Value>) -> bool {
    if std::env::args().any(|a| a == "--room") || std::env::var("OST_ROOM").is_ok_and(|v| v == "1") {
        return true;
    }
    license
        .and_then(|l| l.get("meetingRoomLicenseCategories"))
        .and_then(|c| c.as_array())
        .is_some_and(|c| c.iter().any(|x| x.as_str().is_some_and(|s| !s.is_empty() && s != "None")))
}

/// The room's settings: Teams Rooms' defaults, with
/// `OST_ROOM_AUTO_ACCEPT` (disabled / intenant / all, Teams Rooms'
/// `byomAutoAcceptSetting`) and `OST_ROOM_VIDEO=0` (no camera).
pub fn settings() -> Settings {
    let mut s = Settings::default();
    if let Ok(v) = std::env::var("OST_ROOM_AUTO_ACCEPT") {
        s.auto_accept = AutoAccept::parse(&v);
        s.auto_accept_enabled = s.auto_accept != AutoAccept::Disabled;
    }
    if std::env::var("OST_ROOM_VIDEO").is_ok_and(|v| v == "0") {
        s.video_allowed = false;
    }
    s
}

/// Teams Rooms' home-screen QR code (MeetingRoomQrCodeRenderer): Teams'
/// `qr_code` link for the room (action 5, OutOfMeetingDefault; the room's
/// MRI, tenant, current salt and name, URI-encoded), padded with spaces to
/// 221 characters, error correction H. A phone's Teams that scans it
/// invites the room with the salt as its token.
pub fn qr_link(mri: &str, tenant: &str, salt: u16, name: &str) -> String {
    let enc = |s: &str| {
        // encodeURI: keeps letters, digits and ;,/?:@&=+$-_.!~*'()#
        let mut out = String::new();
        for b in s.bytes() {
            if b.is_ascii_alphanumeric() || b";,/?:@&=+$-_.!~*'()#".contains(&b) {
                out.push(b as char);
            } else {
                out.push_str(&format!("%{b:02X}"));
            }
        }
        out
    };
    let link = format!(
        "https://teams.microsoft.com/l/qr_code/?actions=5&identity={}&tenant_id={}&salt={salt}&name={}",
        enc(mri),
        enc(tenant),
        enc(name)
    );
    format!("{link:<221}")
}

/// The QR code of `text` as rows of "0"/"1" modules (dark = 1), with
/// Teams' quiet zone of 4 modules; empty if it can't be encoded.
pub fn qr_rows(text: &str) -> String {
    qr_rows_at(text, qrcode::EcLevel::H)
}

/// The same at another error correction level (Teams' audio recap code
/// uses L).
pub fn qr_rows_at(text: &str, level: qrcode::EcLevel) -> String {
    let Ok(code) = qrcode::QrCode::with_error_correction_level(text.as_bytes(), level) else {
        return String::new();
    };
    let w = code.width();
    let colors = code.to_colors();
    let pad = 4;
    let size = w + 2 * pad;
    let mut rows = Vec::with_capacity(size);
    for y in 0..size {
        let mut row = String::with_capacity(size);
        for x in 0..size {
            let dark = x >= pad
                && y >= pad
                && x < w + pad
                && y < w + pad
                && colors[(y - pad) * w + (x - pad)] == qrcode::Color::Dark;
            row.push(if dark { '1' } else { '0' });
        }
        rows.push(row);
    }
    rows.join("\n")
}

/// Start running as the room `object_id`: the calling stack says it's a
/// room, the salt changes every minute and the beacon advertises it;
/// `on_salt` gets each salt (the QR code shows it).
pub fn start(object_id: String, on_salt: impl Fn(u16) + Send + 'static) {
    if room_mode::is_active() {
        return;
    }
    room_mode::set_active(true);
    let salts = Salts::default();
    let period = salts.update_period();
    let (tx, rx) = tokio::sync::watch::channel(salts.current());
    *SALTS.lock().unwrap_or_else(|e| e.into_inner()) = Some(salts);
    tracing::info!(room = %object_id, "room mode: running as a Teams Rooms device");
    on_salt(*rx.borrow());
    crate::room_ble::advertise(object_id, rx);
    crate::backend::runtime().spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(1).min(period));
        loop {
            tick.tick().await;
            let changed = {
                let mut g = SALTS.lock().unwrap_or_else(|e| e.into_inner());
                let Some(s) = g.as_mut() else { return };
                s.tick(Instant::now()).then(|| s.current())
            };
            if let Some(code) = changed {
                on_salt(code);
                if tx.send(code).is_err() {
                    return;
                }
            }
        }
    });
}

/// Whether `token` is the room's current salt or a recent one (Teams
/// Rooms' devicesBLEService.isSaltValid, as a room remote's pairing checks
/// it).
pub fn salt_valid(token: u32) -> bool {
    SALTS.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|s| s.is_valid(token))
}

/// Teams Rooms' answer to `call`: accept it by itself, or ring. `tenant`
/// is the room's tenant (Teams' participant type InTenant when the
/// caller's is the same).
pub fn decide(call: &IncomingCall, tenant: Option<&str>) -> Decision {
    let caller_tenant = call.caller_tenant();
    let in_tenant = match (&caller_tenant, tenant) {
        (Some(c), Some(t)) => c.eq_ignore_ascii_case(t),
        // No tenant on the caller: an organization's user (8:orgid:)
        // inviting the room into a meeting of the room's tenant.
        (None, Some(t)) => {
            call.caller_id().is_some_and(|id| id.starts_with("8:orgid:"))
                && call
                    .invitation_data()
                    .and_then(|d| d.pointer("/meetingInfo/tenantId"))
                    .and_then(|v| v.as_str())
                    .is_some_and(|m| m.eq_ignore_ascii_case(t))
        }
        _ => false,
    };
    tracing::info!(caller_tenant = caller_tenant.is_some(), in_tenant, "room mode: caller");
    let g = SALTS.lock().unwrap_or_else(|e| e.into_inner());
    let Some(salts) = g.as_ref() else {
        return Decision::Ring("Not_a_room");
    };
    let d = room_mode::decide(call.invitation_data(), in_tenant, &settings(), salts);
    tracing::info!(
        decision = ?d,
        in_tenant,
        source = ?call.invitation_data().and_then(room_mode::ProximitySource::of),
        "room mode: incoming invitation"
    );
    d
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audio_recap_code_at_level_l() {
        // A Listen on mobile link of 101 bytes is version 5 at L: 37
        // modules and 4 of quiet zone each side.
        let rows = qr_rows_at("https://teams.microsoft.com/l/meetingpodcast?id=0123456789abcdef0123456789abcdef&origin=desktopQRCode", qrcode::EcLevel::L);
        let lines: Vec<&str> = rows.lines().collect();
        assert_eq!(lines.len(), 45);
        assert!(lines.iter().all(|l| l.len() == 45));
        assert!(lines[0].chars().all(|c| c == '0'));
        assert_eq!(&lines[4][4..11], "1111111");
    }
}
