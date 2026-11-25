//! What the devices and the network did, for Teams' test call report
//! (the quality events its calling stack raises: Microsoft documents the
//! same events for Azure Communication Services as "User Facing
//! Diagnostics", read 2026-11-18):
//! - a microphone or camera that couldn't be opened for lack of permission
//!   (AudioCapturePermissionDenied, VideoCapturePermissionDenied);
//! - a device that failed to start (DeviceCaptureNotFunctioning,
//!   DeviceRenderNotFunctioning, VideoCapturerDeviceStartFailed…);
//! - a camera that stops producing frames for more than 5 seconds
//!   (VideoCaptureDeviceFreeze);
//! - the network disconnected (NetworkReconnect "Bad", NoNetwork).
//!
//! The audio and camera code note each open's outcome and every camera
//! frame here; the test call's watch reads it each second.

use std::sync::atomic::{AtomicI64, AtomicU8, AtomicU64, Ordering};

/// How a device's last open went.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Open {
    #[default]
    Unknown,
    Ok,
    /// The system refused access (EACCES / "Permission denied").
    Permission,
    /// Busy, gone or otherwise failed to start.
    Failed,
}

impl Open {
    fn code(self) -> u8 {
        match self {
            Open::Unknown => 0,
            Open::Ok => 1,
            Open::Permission => 2,
            Open::Failed => 3,
        }
    }

    fn from_code(c: u8) -> Self {
        match c {
            1 => Open::Ok,
            2 => Open::Permission,
            3 => Open::Failed,
            _ => Open::Unknown,
        }
    }

    /// The outcome an error message stands for (cpal and V4L2 pass the
    /// system's error text on).
    pub fn from_error(message: &str) -> Self {
        let m = message.to_ascii_lowercase();
        if m.contains("permission denied") || m.contains("eacces") || m.contains("operation not permitted") {
            Open::Permission
        } else {
            Open::Failed
        }
    }
}

static MIC: AtomicU8 = AtomicU8::new(0);
static SPEAKER: AtomicU8 = AtomicU8::new(0);
static CAMERA: AtomicU8 = AtomicU8::new(0);
/// The running camera capture (0: none) and when it last gave a frame
/// (or started), in ms on [`now_ms`]'s clock.
static CAMERA_RUN: AtomicU64 = AtomicU64::new(0);
static CAMERA_RUNS: AtomicU64 = AtomicU64::new(0);
static CAMERA_FRAME_MS: AtomicI64 = AtomicI64::new(0);

fn now_ms() -> i64 {
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START.get_or_init(std::time::Instant::now).elapsed().as_millis() as i64
}

pub fn note_mic(o: Open) {
    MIC.store(o.code(), Ordering::Relaxed);
}

pub fn note_speaker(o: Open) {
    SPEAKER.store(o.code(), Ordering::Relaxed);
}

pub fn note_camera(o: Open) {
    CAMERA.store(o.code(), Ordering::Relaxed);
}

/// Whether the system refuses this app its audio: the PipeWire socket
/// (`$PIPEWIRE_REMOTE`, else `$XDG_RUNTIME_DIR/pipewire-0`) won't take our
/// connection for lack of permission (a sandbox or the socket's mode).
/// The audio library reports such a refusal only as a device without a
/// usable configuration, so a failed open asks here.
pub fn audio_access_denied() -> bool {
    let path = match std::env::var_os("PIPEWIRE_REMOTE") {
        Some(p) if std::path::Path::new(&p).is_absolute() => std::path::PathBuf::from(p),
        Some(p) => match std::env::var_os("XDG_RUNTIME_DIR") {
            Some(d) => std::path::PathBuf::from(d).join(p),
            None => return false,
        },
        None => match std::env::var_os("XDG_RUNTIME_DIR") {
            Some(d) => std::path::PathBuf::from(d).join("pipewire-0"),
            None => return false,
        },
    };
    #[cfg(unix)]
    {
        matches!(std::os::unix::net::UnixStream::connect(&path), Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied)
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        false
    }
}

/// A microphone that failed to open: refused (no permission) or not working.
pub fn mic_failed(message: &str) {
    let o = Open::from_error(message);
    note_mic(if o == Open::Permission || audio_access_denied() { Open::Permission } else { o });
}

/// A test call starts: forget how the devices opened before it.
pub fn reset() {
    note_mic(Open::Unknown);
    note_speaker(Open::Unknown);
    if CAMERA_RUN.load(Ordering::Relaxed) == 0 {
        note_camera(Open::Unknown);
    }
}

/// A camera capture started: its id, for [`camera_stopped`].
pub fn camera_started() -> u64 {
    let id = CAMERA_RUNS.fetch_add(1, Ordering::Relaxed) + 1;
    CAMERA_FRAME_MS.store(now_ms(), Ordering::Relaxed);
    CAMERA_RUN.store(id, Ordering::Relaxed);
    note_camera(Open::Ok);
    id
}

/// The camera gave a frame.
pub fn camera_frame() {
    CAMERA_FRAME_MS.store(now_ms(), Ordering::Relaxed);
}

/// That capture was stopped (turned off, or another took its place).
pub fn camera_stopped(id: u64) {
    let _ = CAMERA_RUN.compare_exchange(id, 0, Ordering::Relaxed, Ordering::Relaxed);
}

/// The devices now.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Devices {
    pub mic: Open,
    pub speaker: Open,
    pub camera: Open,
    /// While a camera capture runs: how long since its last frame (ms).
    pub camera_silent_ms: Option<i64>,
    /// The machine has a network to reach the call over.
    pub online: bool,
}

pub fn devices() -> Devices {
    let running = CAMERA_RUN.load(Ordering::Relaxed) != 0;
    Devices {
        mic: Open::from_code(MIC.load(Ordering::Relaxed)),
        speaker: Open::from_code(SPEAKER.load(Ordering::Relaxed)),
        camera: Open::from_code(CAMERA.load(Ordering::Relaxed)),
        camera_silent_ms: running.then(|| now_ms() - CAMERA_FRAME_MS.load(Ordering::Relaxed)),
        online: network_online(),
    }
}

/// Whether a route leads off this machine: a default route (IPv4 or
/// IPv6) on an interface other than loopback. Teams' stack watches the
/// system's connectivity the same way (NoNetwork / NetworkReconnect "Bad"
/// when the network is disconnected).
pub fn network_online() -> bool {
    let v4 = std::fs::read_to_string("/proc/net/route").unwrap_or_default();
    let v6 = std::fs::read_to_string("/proc/net/ipv6_route").unwrap_or_default();
    // Without /proc (not Linux) assume online.
    if v4.is_empty() && v6.is_empty() {
        return true;
    }
    default_route_v4(&v4) || default_route_v6(&v6)
}

/// /proc/net/route: "Iface Destination Gateway Flags …" (hex); a default
/// route has destination and mask 0 and is up (flag 1).
fn default_route_v4(table: &str) -> bool {
    table.lines().skip(1).any(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        f.len() >= 8
            && f[0] != "lo"
            && f[1] == "00000000"
            && f[7] == "00000000"
            && u32::from_str_radix(f[3], 16).map(|fl| fl & 1 == 1).unwrap_or(false)
    })
}

/// /proc/net/ipv6_route: "dest destlen src srclen nexthop metric ref use
/// flags iface"; a default route is ::/0 (not the unreachable one, flag
/// 0x200 RTF_REJECT) on a real interface.
fn default_route_v6(table: &str) -> bool {
    table.lines().any(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        f.len() >= 10
            && f[0].chars().all(|c| c == '0')
            && f[1] == "00"
            && f[9] != "lo"
            && u32::from_str_radix(f[8], 16).map(|fl| fl & 0x200 == 0 && fl & 1 == 1).unwrap_or(false)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errors_name_a_permission_problem() {
        assert_eq!(
            Open::from_error("ALSA function 'snd_pcm_open' failed with error 'EACCES: Permission denied'"),
            Open::Permission
        );
        assert_eq!(Open::from_error("Failed to open camera at /dev/video0: Permission denied (os error 13)"), Open::Permission);
        assert_eq!(Open::from_error("Device or resource busy (os error 16)"), Open::Failed);
    }

    #[test]
    fn default_routes() {
        let v4 = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n\
                  wlp5s0\t00000000\t010A0A0A\t0003\t0\t0\t600\t00000000\t0\t0\t0\n\
                  wlp5s0\t000A0A0A\t00000000\t0001\t0\t0\t600\t00FFFFFF\t0\t0\t0\n";
        assert!(default_route_v4(v4));
        let only_lan = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n\
                        docker0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0\n";
        assert!(!default_route_v4(only_lan));
        let v6 = "00000000000000000000000000000000 00 00000000000000000000000000000000 00 fe800000000000000000000000000001 00000400 00000001 00000000 00000003 wlp5s0\n\
                  00000000000000000000000000000000 00 00000000000000000000000000000000 00 00000000000000000000000000000000 ffffffff 00000001 00000000 00200200       lo\n";
        assert!(default_route_v6(v6));
        assert!(!default_route_v6(v6.lines().nth(1).unwrap()));
    }

    #[test]
    fn a_refused_audio_socket_is_a_permission_problem() {
        let dir = std::env::temp_dir().join(format!("ost-dh-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let sock = dir.join("pw");
        let _ = std::fs::remove_file(&sock);
        let _l = std::os::unix::net::UnixListener::bind(&sock).unwrap();
        // SAFETY: tests in this module don't read these variables concurrently.
        unsafe { std::env::set_var("PIPEWIRE_REMOTE", &sock) };
        assert!(!audio_access_denied());
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&sock, std::fs::Permissions::from_mode(0o000)).unwrap();
        // Root may connect anyway; then there is nothing to check.
        let root = std::fs::metadata("/root").map(|m| std::os::unix::fs::MetadataExt::uid(&m) == 0).unwrap_or(false)
            && std::fs::read_dir("/root").is_ok();
        if !root {
            assert!(audio_access_denied());
        }
        unsafe { std::env::remove_var("PIPEWIRE_REMOTE") };
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_camera_run_is_tracked_until_it_stops() {
        let id = camera_started();
        assert!(devices().camera_silent_ms.is_some());
        camera_frame();
        camera_stopped(id + 1000);
        assert!(devices().camera_silent_ms.is_some());
        camera_stopped(id);
        assert!(devices().camera_silent_ms.is_none());
        assert_eq!(devices().camera, Open::Ok);
    }
}
