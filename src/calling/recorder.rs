//! Teams' in-meeting Record and transcribe (More ▸ Record and transcribe),
//! as Teams desktop drives it (captured on winpc, 2026-11-09).
//!
//! The meeting's call recorder is a hidden `28:` participant. Its
//! endpoint's `endpointMetadata.commandUrl` takes the commands as a POST
//! with a recorder-service token (audience
//! `4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76`, scope `access_recorder_service`)
//! and the call's chain id:
//!
//! - Start transcription: `mode: "transcription"`, processing modes
//!   `["realTimeTranscript"]`.
//! - Start recording: `["recording", "realTimeTranscript"]` (recording
//!   and transcription), with `recordingMode` "Normal" or "AudioOnly";
//!   with the transcript already running Teams offers "Start recording
//!   only" (`["recording"]`).
//! - Stop sends the same modes with `action: "stop"` and nothing else.
//!
//! A start carries `actionParameters`: the recording features, where to
//! store the file ("<title>-YYYYMMDD_HHMMSS-Meeting Transcript|Recording"
//! in the starter's OneDrive Recordings), the meeting's iCalUid, title and
//! organizer, a correlation id and the spoken language. The recorder
//! answers `{CorrelationId}`; its processing modes then turn up in the
//! roster ([`super::roster::processing_updates`]).

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

/// The recorder service's audience, for its token.
pub const RECORDER_SCOPE: &str = "4580fd1d-e5a3-4f56-9ad1-aab0e3bf8f76/.default";

/// What to ask the recorder for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    StartTranscription,
    StopTranscription,
    /// Recording and transcription (`audio_only`: Teams' "Audio only").
    StartRecording { audio_only: bool },
    /// Recording only, the transcript already running.
    StartRecordingOnly { audio_only: bool },
    /// Recording and transcription.
    StopRecording,
    /// Live captions (Teams' closed-captions service: processing mode
    /// `closedCaptions`; turning them off only changes our endpoint's
    /// `transcriptionPrefs`).
    StartCaptions,
    /// The meeting's spoken language, for its captions and transcript
    /// (`meeting.spoken_language`).
    SetCaptionsLanguage,
}

impl Command {
    fn action(self) -> &'static str {
        match self {
            Command::StartTranscription | Command::StartRecording { .. } | Command::StartRecordingOnly { .. } => {
                "start"
            }
            Command::StopTranscription | Command::StopRecording => "stop",
            Command::StartCaptions => "start",
            Command::SetCaptionsLanguage => "setLanguage",
        }
    }

    fn modes(self) -> &'static [&'static str] {
        match self {
            Command::StartTranscription | Command::StopTranscription => &["realTimeTranscript"],
            Command::StartRecording { .. } | Command::StopRecording => &["recording", "realTimeTranscript"],
            Command::StartRecordingOnly { .. } => &["recording"],
            Command::StartCaptions | Command::SetCaptionsLanguage => &["closedCaptions"],
        }
    }

    fn transcription(self) -> bool {
        matches!(
            self,
            Command::StartTranscription
                | Command::StopTranscription
                | Command::StartCaptions
                | Command::SetCaptionsLanguage
        )
    }

    /// Teams asks for the recorder-service token alone for recording and
    /// the transcript; other commands (captions) carry our Skype token too.
    pub fn needs_skype_token(self) -> bool {
        matches!(self, Command::StartCaptions | Command::SetCaptionsLanguage)
    }
}

/// The meeting a start describes.
#[derive(Debug, Clone, Default)]
pub struct Meeting {
    pub title: String,
    pub ical_uid: String,
    pub organizer: String,
    /// "en-us"…
    pub spoken_language: String,
}

/// Teams' recorder features (the same for transcription and recording).
fn features() -> Value {
    json!({
        "enablePPTSharing": true,
        "intermediateLiveCaptions": false,
        "actionItemsEnabled": false,
        "enableEmailAndMeetingLanguageModel": true,
        "ceoSummit": false,
        "useUnmixedAudio": true,
        "enableTranscriptMeetingChaptering": false
    })
}

/// The command's body. `now` names the file (local time, as Teams), and
/// `timestamp` is the same moment in UTC.
pub fn body(
    command: Command,
    me_mri: &str,
    leg_id: &str,
    meeting: &Meeting,
    now: chrono::DateTime<chrono::Local>,
    correlation_id: &str,
) -> Value {
    let mut b = json!({
        "timestamp": now.with_timezone(&chrono::Utc).to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
        "participantMri": me_mri,
        "participantLegId": leg_id,
        "action": command.action(),
    });
    if command.transcription() {
        b["mode"] = json!("transcription");
    }
    b["processingModes"] = json!(command.modes());
    if command == Command::SetCaptionsLanguage {
        b["actionParameters"] = json!({
            "spokenLanguage": if meeting.spoken_language.is_empty() { "en-us" } else { meeting.spoken_language.as_str() },
            "type": "setLanguage",
        });
    } else if command.action() == "start" && command != Command::StartCaptions {
        let kind = if command.transcription() { "Meeting Transcript" } else { "Meeting Recording" };
        let mut p = json!({
            "recordingFeatures": features(),
            "recordingStorageSettings": [{
                "StorageType": "OnedriveForBusiness",
                "StorageLocation": "Recordings",
                "FileName": format!("{}-{}-{kind}", meeting.title, now.format("%Y%m%d_%H%M%S")),
            }],
            "iCalUid": if meeting.ical_uid.is_empty() { Value::Null } else { json!(meeting.ical_uid) },
            "correlationId": correlation_id,
            "meetingTitle": meeting.title,
            "exchangeId": Value::Null,
            "meetingOrganizer": meeting.organizer,
        });
        if let Command::StartRecording { audio_only } | Command::StartRecordingOnly { audio_only } = command {
            p["recordingMode"] = json!(if audio_only { "AudioOnly" } else { "Normal" });
        }
        p["spokenLanguage"] = json!(if meeting.spoken_language.is_empty() { "en-us" } else { meeting.spoken_language.as_str() });
        p["type"] = json!("start");
        b["actionParameters"] = p;
    }
    b["participantSkypeToken"] = json!("");
    b
}

/// Send a command to the recorder's command URL.
pub async fn send(
    http: &reqwest::Client,
    command_url: &str,
    token: &str,
    skype_token: Option<&str>,
    chain_id: &str,
    body: &Value,
) -> Result<()> {
    if !command_url.starts_with("https://") {
        bail!("No recorder command URL");
    }
    let mut req = http.post(command_url);
    if let Some(t) = skype_token {
        req = req.header("X-Skypetoken", t);
    }
    let resp = req
        .bearer_auth(token)
        .header("x-microsoft-skype-chain-id", chain_id)
        .header("requestid", uuid::Uuid::new_v4().to_string())
        .json(body)
        .send()
        .await
        .context("Recorder command")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("Recorder command failed ({status}): {}", &text[..text.len().min(300)]);
    }
    tracing::info!(%status, reply = %text.chars().take(120).collect::<String>(), "recorder command sent");
    Ok(())
}

/// The recorder's command URL in a roster update or join response, if a
/// participant's endpoint carries one.
pub fn command_url(json: &Value) -> Option<String> {
    let participants = json
        .pointer("/body/participants")
        .or_else(|| json.pointer("/roster/participants"))?
        .as_object()?;
    participants.values().find_map(|p| {
        p.get("endpoints")?.as_object()?.values().find_map(|ep| {
            ep.pointer("/endpointMetadata/commandUrl")
                .and_then(Value::as_str)
                .filter(|u| u.starts_with("https://"))
                .map(str::to_string)
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn meeting() -> Meeting {
        Meeting {
            title: "OST calendar test: created from OST".into(),
            ical_uid: "040000008200E0".into(),
            organizer: "OST Test 1".into(),
            spoken_language: "en-us".into(),
        }
    }

    #[test]
    fn bodies_as_teams_sends_them() {
        let now = chrono::Local.with_ymd_and_hms(2026, 11, 8, 17, 15, 15).unwrap();
        let b = body(Command::StartTranscription, "8:orgid:a", "leg", &meeting(), now, "cid");
        assert_eq!(b["action"], "start");
        assert_eq!(b["mode"], "transcription");
        assert_eq!(b["processingModes"], json!(["realTimeTranscript"]));
        assert_eq!(
            b["actionParameters"]["recordingStorageSettings"][0]["FileName"],
            "OST calendar test: created from OST-20261108_171515-Meeting Transcript"
        );
        assert_eq!(b["actionParameters"]["type"], "start");
        assert!(b["actionParameters"].get("recordingMode").is_none());
        assert_eq!(b["participantSkypeToken"], "");

        let r = body(Command::StartRecording { audio_only: false }, "8:orgid:a", "leg", &meeting(), now, "cid");
        assert!(r.get("mode").is_none());
        assert_eq!(r["processingModes"], json!(["recording", "realTimeTranscript"]));
        assert_eq!(r["actionParameters"]["recordingMode"], "Normal");
        assert!(r["actionParameters"]["recordingStorageSettings"][0]["FileName"].as_str().unwrap().ends_with("-Meeting Recording"));
        let a = body(Command::StartRecordingOnly { audio_only: true }, "8:orgid:a", "leg", &meeting(), now, "cid");
        assert_eq!(a["processingModes"], json!(["recording"]));
        assert_eq!(a["actionParameters"]["recordingMode"], "AudioOnly");

        let s = body(Command::StopRecording, "8:orgid:a", "leg", &meeting(), now, "cid");
        assert_eq!(s["action"], "stop");
        assert!(s.get("actionParameters").is_none());
        let t = body(Command::StopTranscription, "8:orgid:a", "leg", &meeting(), now, "cid");
        assert_eq!(t["mode"], "transcription");
        let mut keys: Vec<_> = t.as_object().unwrap().keys().cloned().collect();
        keys.sort();
        assert_eq!(keys, ["action", "mode", "participantLegId", "participantMri", "participantSkypeToken", "processingModes", "timestamp"]);
    }

    #[test]
    fn captions_bodies_as_teams_sends_them() {
        let now = chrono::Local.with_ymd_and_hms(2026, 11, 8, 17, 15, 15).unwrap();
        let c = body(Command::StartCaptions, "8:orgid:a", "leg", &meeting(), now, "cid");
        let mut keys: Vec<_> = c.as_object().unwrap().keys().cloned().collect();
        keys.sort();
        assert_eq!(keys, ["action", "mode", "participantLegId", "participantMri", "participantSkypeToken", "processingModes", "timestamp"]);
        assert_eq!(c["action"], "start");
        assert_eq!(c["mode"], "transcription");
        assert_eq!(c["processingModes"], json!(["closedCaptions"]));
        let mut m = meeting();
        m.spoken_language = "de-de".into();
        let l = body(Command::SetCaptionsLanguage, "8:orgid:a", "leg", &m, now, "cid");
        assert_eq!(l["action"], "setLanguage");
        assert_eq!(l["actionParameters"], json!({"spokenLanguage": "de-de", "type": "setLanguage"}));
        assert!(Command::StartCaptions.needs_skype_token());
        assert!(!Command::StartTranscription.needs_skype_token());
    }

    #[test]
    fn finds_the_command_url() {
        let ev = json!({"callAgentPath": "conversation/rosterUpdate/", "body": {"participants": {
            "28:bdd": {"endpoints": {"e": {"endpointMetadata": {"commandUrl": "https://api.flightproxy.teams.microsoft.com/api/v2/ep/x/v2/oncommand/1"}}}},
            "8:orgid:a": {"endpoints": {"f": {"call": {}}}}
        }}});
        assert_eq!(command_url(&ev).as_deref(), Some("https://api.flightproxy.teams.microsoft.com/api/v2/ep/x/v2/oncommand/1"));
        assert_eq!(command_url(&json!({"body": {"participants": {}}})), None);
    }
}
