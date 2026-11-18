//! Teams' test call report (the "Post EchoBot Calling Screen" after Settings
//! ▸ Devices ▸ Make a test call), as Teams' CallingEchoBotCallService builds
//! it (module 527114, read 2026-11-16): four lists of problems — Microphone,
//! Speaker, Camera, Network — filled from the call's bad quality events
//! while it runs, and finished when it ends (no camera: "None found"; still
//! muted: "Muted"). An empty list shows "Connected".

use serde::Serialize;

/// Teams' report strings (calling_echoCallReport_*).
pub const NOT_FOUND: &str = "None found";
pub const MUTED: &str = "Muted";
pub const DIDNT_WORK: &str = "Didn’t work";
/// (Teams names itself here; OST says its own name.)
pub const NEED_PERMISSION: &str = "OST needs permission to use this device";
pub const CALL_DROP: &str = "Call drop detected";
pub const POOR_CONNECTION: &str = "Poor connection";

/// The quality events Teams turns into report lines (only when "Bad").
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    /// DeviceRenderNotFunctioning.
    SpeakerNotWorking,
    /// DeviceRenderMute.
    SpeakerMuted,
    /// ZeroRenderDevicesEnumerated.
    NoSpeakers,
    /// DeviceCaptureNotFunctioning / DeviceCaptureNotMuteButSilent.
    MicNotWorking,
    /// DeviceCaptureMute.
    MicMuted,
    /// ZeroCaptureDevicesEnumerated.
    NoMics,
    /// AudioCapturePermissionDenied.
    MicPermission,
    /// NetworkReconnect / NoNetwork.
    CallDrop,
    /// NetworkSendQuality / NetworkRecvQuality.
    PoorNetwork,
    /// VideoCapturerDeviceStartFailed and the like, VideoCaptureDeviceFreeze.
    CameraNotWorking,
    /// VideoCapturePermissionDenied.
    CameraPermission,
}

/// The four lists, in Teams' order on the screen.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Report {
    pub microphone: Vec<String>,
    pub speaker: Vec<String>,
    pub camera: Vec<String>,
    pub network: Vec<String>,
}

impl Report {
    /// Note a quality event (each line once, as Teams' pushReportTo).
    pub fn note(&mut self, event: Event) {
        let (list, line) = match event {
            Event::SpeakerNotWorking => (&mut self.speaker, DIDNT_WORK),
            Event::SpeakerMuted => (&mut self.speaker, MUTED),
            Event::NoSpeakers => (&mut self.speaker, NOT_FOUND),
            Event::MicNotWorking => (&mut self.microphone, DIDNT_WORK),
            Event::MicMuted => (&mut self.microphone, MUTED),
            Event::NoMics => (&mut self.microphone, NOT_FOUND),
            Event::MicPermission => (&mut self.microphone, NEED_PERMISSION),
            Event::CallDrop => (&mut self.network, CALL_DROP),
            Event::PoorNetwork => (&mut self.network, POOR_CONNECTION),
            Event::CameraNotWorking => (&mut self.camera, DIDNT_WORK),
            Event::CameraPermission => (&mut self.camera, NEED_PERMISSION),
        };
        if !list.iter().any(|l| l == line) {
            list.push(line.to_string());
        }
    }

    /// The call ended (Teams' finalizeEchoBotReport): no camera chosen is
    /// "None found"; a mic or speaker still muted is "Muted".
    pub fn finish(&mut self, has_camera: bool, mic_muted: bool, speaker_muted: bool) {
        if !has_camera && !self.camera.iter().any(|l| l == NOT_FOUND) {
            self.camera.push(NOT_FOUND.to_string());
        }
        if mic_muted {
            self.note(Event::MicMuted);
        }
        if speaker_muted {
            self.note(Event::SpeakerMuted);
        }
    }
}

/// How long the mic must be on, giving nothing but silence, before it
/// "didn't work" (Teams' DeviceCaptureNotMuteButSilent).
pub const SILENT_SECONDS: u32 = 5;

/// Watches the test call each second, as Teams' calling stack raises its
/// quality events.
#[derive(Debug, Default)]
pub struct Watch {
    pub report: Report,
    unmuted_seconds: u32,
    heard: bool,
    /// The Echo bot has joined (its leaving then ends the call).
    pub bot_seen: bool,
    poor_seconds: u32,
    /// The microphone was refused (no permission): it never ran, so its
    /// silence isn't a second problem.
    mic_refused: bool,
}

impl Watch {
    pub fn new() -> Self {
        Self::default()
    }

    /// One second of the call: whether you're muted, whether the mic gave
    /// any sound since the last second, and the network's strength.
    pub fn second(&mut self, muted: bool, mic_signal: bool, strength: super::network_quality::Strength) {
        if !muted {
            self.unmuted_seconds += 1;
            self.heard |= mic_signal;
            if !self.heard && !self.mic_refused && self.unmuted_seconds >= SILENT_SECONDS {
                self.report.note(Event::MicNotWorking);
            }
        }
        // Teams' network quality events are "Bad" only after its
        // averaging; OST's strength is already averaged over seconds.
        if strength == super::network_quality::Strength::Bad {
            self.poor_seconds += 1;
            if self.poor_seconds >= 3 {
                self.report.note(Event::PoorNetwork);
            }
        } else {
            self.poor_seconds = 0;
        }
    }
}

/// How long a running camera may give no frame before it froze (Teams'
/// VideoCaptureDeviceFreeze: "Camera stops producing frames for more than
/// 5 seconds").
pub const CAMERA_FREEZE_MS: i64 = 5_000;

impl Watch {
    /// One second of the devices and the network, as Teams' stack raises
    /// their quality events: permission refused, a device that failed to
    /// start, a frozen camera, the network gone.
    pub fn devices(&mut self, d: &super::device_health::Devices) {
        use super::device_health::Open;
        match d.mic {
            Open::Permission => {
                self.mic_refused = true;
                self.report.note(Event::MicPermission)
            }
            Open::Failed => self.report.note(Event::MicNotWorking),
            _ => {}
        }
        if matches!(d.speaker, Open::Permission | Open::Failed) {
            self.report.note(Event::SpeakerNotWorking);
        }
        match d.camera {
            Open::Permission => self.report.note(Event::CameraPermission),
            Open::Failed => self.report.note(Event::CameraNotWorking),
            _ => {}
        }
        if d.camera_silent_ms.is_some_and(|ms| ms >= CAMERA_FREEZE_MS) {
            self.report.note(Event::CameraNotWorking);
        }
        if !d.online {
            self.report.note(Event::CallDrop);
        }
    }
}

/// The Echo bot in a roster update of the test call: Some(true) while it
/// is in the call, Some(false) once it has left (its state no longer
/// "active"); None when the update doesn't name it. The bot leaves once
/// it has played your recording back, and Teams' test call ends then
/// (measured 2026-11-16: about 25 s after the bot joins).
pub fn echo_bot_active(json: &str) -> Option<bool> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    if !v.get("callAgentPath")?.as_str()?.starts_with("conversation/rosterUpdate") {
        return None;
    }
    let bot = v
        .pointer("/body/participants")?
        .as_object()?
        .iter()
        .find(|(mri, _)| mri.eq_ignore_ascii_case(super::signaling::ECHO_BOT_MRI))?
        .1;
    Some(bot.get("state").and_then(|s| s.as_str()) == Some("active"))
}

/// The screen's rows: (name, the device's label, its problems), as
/// Teams' `X` builds them: "Microphone - <device>", "Speaker - <device>",
/// "Camera - <device>", "Network".
pub fn rows(report: &Report, mic: Option<&str>, speaker: Option<&str>, camera: Option<&str>) -> serde_json::Value {
    let label = |name: &str, device: Option<&str>| match device.filter(|d| !d.is_empty()) {
        Some(d) => format!("{name} - {d}"),
        None => name.to_string(),
    };
    serde_json::json!([
        { "kind": "microphone", "title": label("Microphone", mic), "problems": report.microphone },
        { "kind": "speaker", "title": label("Speaker", speaker), "problems": report.speaker },
        { "kind": "camera", "title": label("Camera", camera), "problems": report.camera },
        { "kind": "network", "title": "Network", "problems": report.network },
    ])
}

#[cfg(test)]
mod tests {
    use super::super::network_quality::Strength;
    use super::*;

    #[test]
    fn a_clean_call_reports_nothing() {
        let mut w = Watch::new();
        for _ in 0..20 {
            w.second(false, true, Strength::Good);
        }
        w.report.finish(true, false, false);
        assert_eq!(w.report, Report::default());
    }

    #[test]
    fn muted_at_the_end_and_no_camera() {
        let mut w = Watch::new();
        for _ in 0..20 {
            w.second(true, false, Strength::Good);
        }
        w.report.finish(false, true, false);
        assert_eq!(w.report.microphone, vec![MUTED]);
        assert_eq!(w.report.camera, vec![NOT_FOUND]);
        assert!(w.report.speaker.is_empty() && w.report.network.is_empty());
    }

    #[test]
    fn a_silent_mic_didnt_work_and_lines_are_not_repeated() {
        let mut w = Watch::new();
        for _ in 0..(SILENT_SECONDS - 1) {
            w.second(false, false, Strength::Good);
        }
        assert!(w.report.microphone.is_empty());
        for _ in 0..10 {
            w.second(false, false, Strength::Good);
        }
        w.report.finish(true, true, false);
        assert_eq!(w.report.microphone, vec![DIDNT_WORK, MUTED]);
    }

    #[test]
    fn sound_once_is_enough() {
        let mut w = Watch::new();
        w.second(false, true, Strength::Good);
        for _ in 0..20 {
            w.second(false, false, Strength::Good);
        }
        assert!(w.report.microphone.is_empty());
    }

    #[test]
    fn a_bad_network_for_a_while_is_a_poor_connection() {
        let mut w = Watch::new();
        w.second(false, true, Strength::Bad);
        w.second(false, true, Strength::Good);
        w.second(false, true, Strength::Bad);
        assert!(w.report.network.is_empty());
        for _ in 0..3 {
            w.second(false, true, Strength::Bad);
        }
        assert_eq!(w.report.network, vec![POOR_CONNECTION]);
    }

    #[test]
    fn device_and_network_problems() {
        use crate::calling::device_health::{Devices, Open};
        let mut w = Watch::new();
        let ok = Devices { mic: Open::Ok, speaker: Open::Ok, camera: Open::Ok, camera_silent_ms: Some(40), online: true };
        w.devices(&ok);
        assert_eq!(w.report, Report::default());
        // A camera that stops giving frames for 5 s froze.
        w.devices(&Devices { camera_silent_ms: Some(CAMERA_FREEZE_MS - 1), ..ok });
        assert!(w.report.camera.is_empty());
        w.devices(&Devices { camera_silent_ms: Some(CAMERA_FREEZE_MS), ..ok });
        assert_eq!(w.report.camera, vec![DIDNT_WORK]);
        // Permission refused, and the network gone.
        w.devices(&Devices { mic: Open::Permission, camera: Open::Permission, online: false, ..ok });
        w.devices(&Devices { online: false, ..ok });
        assert_eq!(w.report.microphone, vec![NEED_PERMISSION]);
        // A refused mic's silence isn't reported as well.
        for _ in 0..10 {
            w.second(false, false, Strength::Good);
        }
        assert_eq!(w.report.microphone, vec![NEED_PERMISSION]);
        assert_eq!(w.report.camera, vec![DIDNT_WORK, NEED_PERMISSION]);
        assert_eq!(w.report.network, vec![CALL_DROP]);
        // A speaker that failed to start didn't work.
        w.devices(&Devices { speaker: Open::Failed, ..ok });
        assert_eq!(w.report.speaker, vec![DIDNT_WORK]);
    }

    #[test]
    fn the_bot_joining_and_leaving() {
        let joined = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{"28:cf28171e-fcfd-47e4-a1d6-79460b0b3ca0":{"state":"active","details":{"displayName":"Echo"}}}}}"#;
        let left = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{"28:cf28171e-fcfd-47e4-a1d6-79460b0b3ca0":{"state":"inactive"}}}}"#;
        let other = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{"8:orgid:x":{"state":"active"}}}}"#;
        assert_eq!(echo_bot_active(joined), Some(true));
        assert_eq!(echo_bot_active(left), Some(false));
        assert_eq!(echo_bot_active(other), None);
        assert_eq!(echo_bot_active(r#"{"callAgentPath":"call/end/"}"#), None);
    }

    #[test]
    fn rows_name_the_devices() {
        let mut r = Report::default();
        r.note(Event::MicMuted);
        let v = rows(&r, Some("Microphone (C920)"), Some("Speakers"), None);
        assert_eq!(v[0]["title"], "Microphone - Microphone (C920)");
        assert_eq!(v[0]["problems"][0], "Muted");
        assert_eq!(v[2]["title"], "Camera");
        assert_eq!(v[3]["title"], "Network");
        assert_eq!(v[3]["problems"].as_array().map(Vec::len), Some(0));
    }
}
