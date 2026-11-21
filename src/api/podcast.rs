//! Audio recap (Teams' podcasts) of one meeting, as the recap window's
//! "Audio recap" button makes it (Teams 26304: 991291's AudioRecapButton,
//! services-podcast's generatePodcast, services-augloop's
//! submitPodcastGenerationOperation; seen on winpc 2026-11-21 for "OST
//! TEST 240 recap meeting"):
//! 1. `GET {mcps}/podcasts/consume?threadId&transcriptIds&language&style
//!    &iCalUid` (404 when there is none yet; otherwise the podcast to play);
//! 2. an AugLoop session: the TeamsRecapPodcastGenerationAnnotation
//!    activated, then a TeamsRecapPodcastGenerationSignal added at
//!    `session/doc/teams_recap_podcast_generation_podcast-session/{request}`
//!    with the meeting, its transcripts, style Dual/formal, language
//!    en-US, podcastType SharedSingleMeetingAudioRecap;
//! 3. the annotation answers with the podcast (status InProgress,
//!    Completed or Failed) and a workflow status; Teams' mini player shows
//!    "Generating...", then plays it or shows why it failed (for a meeting
//!    with too little in its transcript: NoValidMeetingInsightError).

use anyhow::{Context, Result};
use futures::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio_tungstenite::tungstenite::Message;

/// A meeting transcript an audio recap is made from (a TranscriptV2
/// resource of the meeting artifacts service).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Transcript {
    pub id: String,
    /// Its `…/media/transcripts/{id}/streamContent` address.
    pub location: String,
    pub start: String,
    pub end: String,
    pub drive_id: String,
    pub item_id: String,
    pub call_id: String,
}

/// .NET ticks (100 ns since 0001-01-01) as Teams' ISO time with
/// milliseconds; "" when there are none.
pub fn ticks_iso(ticks: &str) -> String {
    let Ok(t) = ticks.parse::<i64>() else { return String::new() };
    if t <= 621_355_968_000_000_000 {
        return String::new();
    }
    let ms = (t - 621_355_968_000_000_000) / 10_000;
    chrono::DateTime::from_timestamp_millis(ms).map(|d| d.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)).unwrap_or_default()
}

/// A TranscriptV2 resource as an audio recap's transcript (Teams reads
/// its stream address, not the content one).
pub fn transcript_from(res: &Value) -> Option<Transcript> {
    if res.get("type").and_then(Value::as_str) != Some("TranscriptV2") {
        return None;
    }
    let m = |k: &str| res.pointer(&format!("/metadata/{k}")).and_then(Value::as_str).unwrap_or_default().to_string();
    let location = res.get("location").and_then(Value::as_str).unwrap_or_default();
    let id = location.split("/transcripts/").nth(1).and_then(|s| s.split('/').next()).unwrap_or_default().to_string();
    if id.is_empty() {
        return None;
    }
    let location = match location.strip_suffix("/content") {
        Some(base) => format!("{base}/streamContent"),
        None => location.to_string(),
    };
    Some(Transcript { id, location, start: ticks_iso(&m("startTime")), end: ticks_iso(&m("endTime")), drive_id: m("driveId"), item_id: m("driveItemId"), call_id: m("callId") })
}

/// What the generation is asked for (Teams' generateAndPopoutPodcast from
/// the recap window: one meeting).
#[derive(Debug, Clone, Default)]
pub struct Meeting {
    /// The calendar event's id ("" when it isn't in your calendar).
    pub event_id: String,
    pub subject: String,
    pub organizer_name: String,
    pub organizer_id: String,
    pub thread_id: String,
    pub ical_uid: String,
    /// The meeting's start and end, UTC milliseconds.
    pub start_ms: i64,
    pub end_ms: i64,
    pub transcripts: Vec<Transcript>,
}

fn iso_ms(ms: i64) -> String {
    chrono::DateTime::from_timestamp_millis(ms).map(|d| d.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)).unwrap_or_default()
}

/// Teams' consume check (does an audio recap of these transcripts exist?).
pub fn consume_query(m: &Meeting, language: &str, style: &str) -> String {
    let ids: Vec<&str> = m.transcripts.iter().map(|t| t.id.as_str()).collect();
    format!(
        "podcasts/consume?threadId={}&transcriptIds={}&language={}&style={}&iCalUid={}",
        m.thread_id,
        ids.join(","),
        language,
        style,
        m.ical_uid.to_uppercase()
    )
}

/// The generation signal's body (Teams' TeamsRecapPodcastGenerationSignal).
pub fn generation_signal(m: &Meeting, generation_id: &str) -> Value {
    let (start, end) = (iso_ms(m.start_ms), iso_ms(m.end_ms));
    json!({
        "range": { "startDateTime": start, "endDateTime": end },
        "eventsWithTranscripts": [{
            "event": { "id": m.event_id, "subject": m.subject, "organizerName": m.organizer_name, "startDateTime": start, "endDateTime": end,
                       "threadId": m.thread_id, "iCalUid": m.ical_uid.to_uppercase(), "organizerObjectId": m.organizer_id },
            "transcripts": m.transcripts.iter().map(|t| json!({
                "id": t.id, "location": t.location, "startDateTime": t.start, "endDateTime": t.end,
                "driveId": t.drive_id, "driveItemId": t.item_id, "transcriptId": t.id, "callId": t.call_id,
            })).collect::<Vec<_>>(),
        }],
        "style": { "format": "Dual", "tone": "formal" },
        "language": "en-US",
        "experiments": "EnableGenerationFromMeetingCrux:true;EnablePodcastGenerationEmail:true",
        "promptVersion": "\"\"",
        "generationId": generation_id,
        "triggerType": "Manual",
        "podcastType": "SharedSingleMeetingAudioRecap",
        "H_": { "T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationSignal", "B_": ["AugLoop_Signals_Signal"] },
    })
}

/// Where an audio recap stands, from a generation annotation (Teams'
/// activateTeamsRecapGenerationSubscription): Completed / Failed by the
/// podcast's status, else failed when the workflow status isn't 0, else
/// in progress.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Generation {
    /// "COMPLETED", "FAILED" or "IN_PROGRESS".
    pub status: String,
    /// The podcast's statusMessage, or the workflow's.
    pub message: String,
    pub podcast: Value,
}

pub fn generation_from(body: &Value) -> Option<Generation> {
    if body.pointer("/H_/T_").and_then(Value::as_str) != Some("AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation") {
        return None;
    }
    let podcast = body.get("podcast").cloned().unwrap_or(Value::Null);
    let workflow = body.get("workflowStatus").and_then(Value::as_i64).unwrap_or(0);
    let status = match podcast.get("status").and_then(Value::as_str) {
        Some("Completed") => "COMPLETED",
        Some("Failed") => "FAILED",
        _ if workflow != 0 => "FAILED",
        _ => "IN_PROGRESS",
    };
    let message = podcast
        .get("statusMessage")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .or_else(|| body.get("workflowStatusMessage").and_then(Value::as_str))
        .unwrap_or_default()
        .to_string();
    Some(Generation { status: status.into(), message, podcast })
}

/// Teams' mini player wording for a failed generation: too little in the
/// meetings, or anything else.
pub fn no_insight(message: &str) -> bool {
    matches!(message, "NoValidMeetingInsightError" | "NoValidMeetingFoundError")
}

fn h(t: &str, b: &[&str]) -> Value {
    json!({ "T_": t, "B_": b })
}

/// Make the audio recap over AugLoop and wait for the podcast to finish
/// (or fail): the first annotation with a podcast id or a workflow error
/// answers Teams' operation; an in-progress podcast is followed until its
/// status changes (at most 10 minutes).
pub async fn generate(m: &Meeting, ui_language: &str) -> Result<Generation> {
    let token = crate::auth::oauth::access_token_for("https://augloop.office.com/v2/.default").await?;
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request("wss://augloop.office.com/")?;
    req.headers_mut().insert("Origin", "https://teams.microsoft.com".parse()?);
    let (mut ws, _) = tokio_tungstenite::connect_async(req).await.context("AugLoop")?;
    let group = uuid::Uuid::new_v4().simple().to_string();
    let mut n = 0u64;
    let mut next = |n: &mut u64| {
        *n += 1;
        (format!("c{n}"), format!("ost{}.{n}", &group[..8]))
    };
    let send = |v: Value| Message::Text(v.to_string().into());
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"protocolVersion": 2,
        "clientMetadata": {"appName": "Teams", "appPlatform": "Win32", "releaseAudienceGroup": "Production", "releaseChannel": "general", "sessionId": uuid::Uuid::new_v4().to_string(),
            "uiLanguage": ui_language, "flights": "", "runtimeVersion": "2.37.2676", "docSessionId": uuid::Uuid::new_v4().to_string(), "userSystemTimezone": super::compose_copilot::iana_timezone()},
        "extensionConfigs": [], "returnWorkflowInputTypes": false, "enableRemoteExecutionNotification": false, "createBlobStorageContainer": false,
        "H_": h("AugLoop_Session_Protocol_SessionInitMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})))
    .await?;
    loop {
        let Some(msg) = tokio::time::timeout(std::time::Duration::from_secs(20), ws.next()).await.context("AugLoop didn't answer")? else { anyhow::bail!("AugLoop closed") };
        if let Message::Text(t) = msg?
            && t.as_str() != "~"
        {
            let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
            if v.get("sessionKey").is_some() {
                break;
            }
            anyhow::ensure!(!v.pointer("/H_/T_").and_then(Value::as_str).is_some_and(|t| t.contains("Error")), "AugLoop refused the session");
        }
    }
    let annotation = "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation";
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"annotationType": annotation, "token": uuid::Uuid::new_v4().to_string(), "ignoreExistingAnnotations": false, "sendStateUpdates": false,
        "returnAnnotationDoesNotExist": true, "sendApologies": false, "H_": h("AugLoop_Session_Protocol_AnnotationActivationMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})))
    .await?;
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"cv": cv, "seq": 0, "ops": [{"parentPath": ["session"], "items": [{"id": "doc", "body": {"isReadonly": false, "H_": h("AugLoop_Core_Document", &["AugLoop_Core_TileGroup"])}}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}], "groupId": "Seed", "groupSize": 1, "groupComplete": true,
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid})))
    .await?;
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"authToken": token, "version": 1, "H_": h("AugLoop_Session_Protocol_TokenProvisionMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid}))).await?;
    let generation_id = uuid::Uuid::new_v4().to_string();
    let request = uuid::Uuid::new_v4().to_string();
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"cv": cv, "seq": 1, "ops": [{"parentPath": ["session", "doc", "teams_recap_podcast_generation_podcast-session", request],
        "items": [{"id": uuid::Uuid::new_v4().to_string(), "body": generation_signal(m, &generation_id), "contextId": "C1"}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}],
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid})))
    .await?;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(600);
    let mut last: Option<Generation> = None;
    loop {
        let Ok(next_msg) = tokio::time::timeout_at(deadline, ws.next()).await else { break };
        let Some(msg) = next_msg else { break };
        let t = match msg? {
            Message::Text(t) => t.to_string(),
            Message::Close(_) => break,
            _ => continue,
        };
        if t == "~" {
            ws.send(Message::Text("~".into())).await?;
            continue;
        }
        let v: Value = serde_json::from_str(&t).unwrap_or_default();
        if let Some(id) = v.get("messageId").and_then(Value::as_str).filter(|id| id.starts_with('s')) {
            ws.send(send(json!({"H_": h("AugLoop_Session_Protocol_Response", &[]), "messageId": id}))).await?;
        }
        if v.pointer("/H_/T_").and_then(Value::as_str).is_some_and(|t| t.contains("Error")) && last.is_none() {
            anyhow::bail!("AugLoop: {}", v.pointer("/H_/T_").and_then(Value::as_str).unwrap_or_default());
        }
        let bodies = v.get("ops").and_then(Value::as_array).into_iter().flatten().flat_map(|op| op.get("items").and_then(Value::as_array).cloned().unwrap_or_default());
        for item in bodies {
            if let Some(g) = item.get("body").and_then(generation_from) {
                // An update without the podcast keeps the podcast seen.
                let g = match (&last, g.podcast.is_null()) {
                    (Some(prev), true) => Generation { podcast: prev.podcast.clone(), ..g },
                    _ => g,
                };
                last = Some(g);
            }
        }
        if let Some(g) = &last
            && g.status != "IN_PROGRESS"
        {
            break;
        }
    }
    let _ = ws.close(None).await;
    last.context("No audio recap came back")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transcripts_as_teams_sends_them() {
        let res = json!({"type": "TranscriptV2", "location": "https://x-my.sharepoint.com/personal/a/_api/v2.1/drives/b!d/items/I1/versions/current/media/transcripts/440f/content",
            "metadata": {"driveId": "b!d", "driveItemId": "I1", "callId": "c1", "startTime": "639308319617584877", "endTime": "639308323264957532"}});
        let t = transcript_from(&res).unwrap();
        assert_eq!(t.id, "440f");
        assert!(t.location.ends_with("/transcripts/440f/streamContent"));
        assert_eq!(t.start, "2026-11-21T04:26:01.758Z");
        assert_eq!(t.end, "2026-11-21T04:32:06.495Z");
        assert!(transcript_from(&json!({"type": "Recording"})).is_none());
    }

    #[test]
    fn signal_and_consume_query() {
        let m = Meeting { subject: "S".into(), thread_id: "19:meeting_x@thread.v2".into(), ical_uid: "04abc".into(), start_ms: 1_795_235_380_000, end_ms: 1_795_237_720_000,
            transcripts: vec![Transcript { id: "t1".into(), ..Default::default() }], ..Default::default() };
        let s = generation_signal(&m, "g1");
        assert_eq!(s["range"]["startDateTime"], "2026-11-21T04:29:40.000Z");
        assert_eq!(s["eventsWithTranscripts"][0]["event"]["iCalUid"], "04ABC");
        assert_eq!(s["eventsWithTranscripts"][0]["transcripts"][0]["transcriptId"], "t1");
        assert_eq!(s["podcastType"], "SharedSingleMeetingAudioRecap");
        assert_eq!(consume_query(&m, "en-US", "formal"), "podcasts/consume?threadId=19:meeting_x@thread.v2&transcriptIds=t1&language=en-US&style=formal&iCalUid=04ABC");
    }

    #[test]
    fn generation_states() {
        let failed = json!({"podcast": {"status": "Failed", "statusMessage": "NoValidMeetingInsightError", "id": "p"}, "workflowStatus": 46, "workflowStatusMessage": "NoValidMeetingInsightError",
            "H_": {"T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation"}});
        let g = generation_from(&failed).unwrap();
        assert_eq!((g.status.as_str(), g.message.as_str()), ("FAILED", "NoValidMeetingInsightError"));
        assert!(no_insight(&g.message));
        let going = json!({"podcast": {"status": "InProgress", "id": "p"}, "workflowStatus": 0, "H_": {"T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation"}});
        assert_eq!(generation_from(&going).unwrap().status, "IN_PROGRESS");
        let workflow = json!({"workflowStatus": 3, "workflowStatusMessage": "X", "H_": {"T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation"}});
        assert_eq!(generation_from(&workflow).unwrap().status, "FAILED");
        assert!(generation_from(&json!({"H_": {"T_": "Other"}})).is_none());
    }
}
