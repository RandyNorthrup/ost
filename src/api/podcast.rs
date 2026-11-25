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
    let Ok(t) = ticks.parse::<i64>() else {
        return String::new();
    };
    if t <= 621_355_968_000_000_000 {
        return String::new();
    }
    let ms = (t - 621_355_968_000_000_000) / 10_000;
    chrono::DateTime::from_timestamp_millis(ms)
        .map(|d| d.to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
        .unwrap_or_default()
}

/// A TranscriptV2 resource as an audio recap's transcript (Teams reads
/// its stream address, not the content one).
pub fn transcript_from(res: &Value) -> Option<Transcript> {
    if res.get("type").and_then(Value::as_str) != Some("TranscriptV2") {
        return None;
    }
    let m = |k: &str| {
        res.pointer(&format!("/metadata/{k}"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let location = res
        .get("location")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let id = location
        .split("/transcripts/")
        .nth(1)
        .and_then(|s| s.split('/').next())
        .unwrap_or_default()
        .to_string();
    if id.is_empty() {
        return None;
    }
    let location = match location.strip_suffix("/content") {
        Some(base) => format!("{base}/streamContent"),
        None => location.to_string(),
    };
    Some(Transcript {
        id,
        location,
        start: ticks_iso(&m("startTime")),
        end: ticks_iso(&m("endTime")),
        drive_id: m("driveId"),
        item_id: m("driveItemId"),
        call_id: m("callId"),
    })
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
    chrono::DateTime::from_timestamp_millis(ms)
        .map(|d| d.to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
        .unwrap_or_default()
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

/// A meeting as an entry of the signal's eventsWithTranscripts.
fn event_with_transcripts(m: &Meeting) -> Value {
    let (start, end) = (iso_ms(m.start_ms), iso_ms(m.end_ms));
    json!({
        "event": { "id": m.event_id, "subject": m.subject, "organizerName": m.organizer_name, "startDateTime": start, "endDateTime": end,
                   "threadId": m.thread_id, "iCalUid": m.ical_uid.to_uppercase(), "organizerObjectId": m.organizer_id },
        "transcripts": m.transcripts.iter().map(|t| json!({
            "id": t.id, "location": t.location, "startDateTime": t.start, "endDateTime": t.end,
            "driveId": t.drive_id, "driveItemId": t.item_id, "transcriptId": t.id, "callId": t.call_id,
        })).collect::<Vec<_>>(),
    })
}

/// Generate audio recap's Style as Teams sends it (`{format: host, tone:
/// format}`; Teams' podcast formats Formal / Newscast / Casual, the host
/// Single for Newscast, else Dual; the tone lower-cased as
/// generateAndPopoutPodcast does). The dialog's "Executive" is Formal.
pub fn style(choice: &str) -> (&'static str, &'static str) {
    match choice {
        "Newscast" => ("Single", "newscast"),
        "Casual" => ("Dual", "casual"),
        _ => ("Dual", "formal"),
    }
}

/// The generation signal's body (Teams' TeamsRecapPodcastGenerationSignal)
/// for one meeting's audio recap (the recap window's Audio recap).
pub fn generation_signal(m: &Meeting, generation_id: &str) -> Value {
    signal_for(
        std::slice::from_ref(m),
        ("Dual", "formal"),
        "en-US",
        generation_id,
        Some("SharedSingleMeetingAudioRecap"),
    )
}

/// The signal for Generate audio recap (Meeting Recaps, origin RecapHome):
/// up to eight meetings, the range from the first start to the last end,
/// the chosen style and language, and no podcastType (Teams sets it only
/// for the single-meeting origins).
pub fn generation_signal_multi(
    meetings: &[Meeting],
    style: (&str, &str),
    language: &str,
    generation_id: &str,
) -> Value {
    signal_for(meetings, style, language, generation_id, None)
}

fn signal_for(
    meetings: &[Meeting],
    style: (&str, &str),
    language: &str,
    generation_id: &str,
    podcast_type: Option<&str>,
) -> Value {
    let start = meetings
        .iter()
        .map(|m| m.start_ms)
        .min()
        .unwrap_or_default();
    let end = meetings.iter().map(|m| m.end_ms).max().unwrap_or_default();
    let mut v = json!({
        "range": { "startDateTime": iso_ms(start), "endDateTime": iso_ms(end) },
        "eventsWithTranscripts": meetings.iter().map(event_with_transcripts).collect::<Vec<_>>(),
        "style": { "format": style.0, "tone": style.1 },
        "language": language,
        "experiments": "EnableGenerationFromMeetingCrux:true;EnablePodcastGenerationEmail:true",
        "promptVersion": "\"\"",
        "generationId": generation_id,
        "triggerType": "Manual",
        "H_": { "T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationSignal", "B_": ["AugLoop_Signals_Signal"] },
    });
    if let Some(t) = podcast_type {
        v["podcastType"] = json!(t);
    }
    v
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
    if body.pointer("/H_/T_").and_then(Value::as_str)
        != Some("AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation")
    {
        return None;
    }
    let podcast = body.get("podcast").cloned().unwrap_or(Value::Null);
    let workflow = body
        .get("workflowStatus")
        .and_then(Value::as_i64)
        .unwrap_or(0);
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
    Some(Generation {
        status: status.into(),
        message,
        podcast,
    })
}

/// Listen on mobile's address for an audio recap (Teams'
/// `https://{host}/l/meetingpodcast?id={podcastId}&origin=desktopQRCode`,
/// the host being Teams' own, teams.microsoft.com).
pub fn mobile_link(podcast_id: &str) -> String {
    format!("https://teams.microsoft.com/l/meetingpodcast?id={podcast_id}&origin=desktopQRCode")
}

/// Teams' mini player wording for a failed generation: too little in the
/// meetings, or anything else.
pub fn no_insight(message: &str) -> bool {
    matches!(
        message,
        "NoValidMeetingInsightError" | "NoValidMeetingFoundError"
    )
}

fn h(t: &str, b: &[&str]) -> Value {
    json!({ "T_": t, "B_": b })
}

/// One AugLoop operation as Teams' AugLoop service runs it: a session
/// (SessionInit, the "doc" seed, the token), the annotation activated, the
/// signal added at `path`, then every annotation result handed to `seen`
/// until it says it's done (true), the socket closes or `wait` runs out.
/// Server messages with an "s…" id are acked and "~" keepalives answered.
async fn run_op(
    annotation: &str,
    path: Value,
    signal: Value,
    ui_language: &str,
    wait: std::time::Duration,
    seen: impl FnMut(&Value) -> bool,
) -> Result<()> {
    run_op_with(&[annotation], path, signal, ui_language, wait, seen).await
}

/// [`run_op`] with several annotations activated first (Teams' streaming
/// operations: a progress annotation and the result's).
pub(crate) async fn run_op_with(
    annotations: &[&str],
    path: Value,
    signal: Value,
    ui_language: &str,
    wait: std::time::Duration,
    mut seen: impl FnMut(&Value) -> bool,
) -> Result<()> {
    let token =
        crate::auth::oauth::access_token_for("https://augloop.office.com/v2/.default").await?;
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request(
        "wss://augloop.office.com/",
    )?;
    req.headers_mut()
        .insert("Origin", "https://teams.microsoft.com".parse()?);
    let (mut ws, _) = tokio_tungstenite::connect_async(req)
        .await
        .context("AugLoop")?;
    let group = uuid::Uuid::new_v4().simple().to_string();
    let mut n = 0u64;
    let next = |n: &mut u64| {
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
        let Some(msg) = tokio::time::timeout(std::time::Duration::from_secs(20), ws.next())
            .await
            .context("AugLoop didn't answer")?
        else {
            anyhow::bail!("AugLoop closed")
        };
        if let Message::Text(t) = msg?
            && t.as_str() != "~"
        {
            let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
            if v.get("sessionKey").is_some() {
                break;
            }
            anyhow::ensure!(
                !v.pointer("/H_/T_")
                    .and_then(Value::as_str)
                    .is_some_and(|t| t.contains("Error")),
                "AugLoop refused the session"
            );
        }
    }
    for annotation in annotations {
        let (mid, cv) = next(&mut n);
        ws.send(send(json!({"annotationType": annotation, "token": uuid::Uuid::new_v4().to_string(), "ignoreExistingAnnotations": false, "sendStateUpdates": false,
            "returnAnnotationDoesNotExist": true, "sendApologies": false, "H_": h("AugLoop_Session_Protocol_AnnotationActivationMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid})))
        .await?;
    }
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"cv": cv, "seq": 0, "ops": [{"parentPath": ["session"], "items": [{"id": "doc", "body": {"isReadonly": false, "H_": h("AugLoop_Core_Document", &["AugLoop_Core_TileGroup"])}}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}], "groupId": "Seed", "groupSize": 1, "groupComplete": true,
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid})))
    .await?;
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"authToken": token, "version": 1, "H_": h("AugLoop_Session_Protocol_TokenProvisionMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid}))).await?;
    let (mid, cv) = next(&mut n);
    ws.send(send(json!({"cv": cv, "seq": 1, "ops": [{"parentPath": path,
        "items": [{"id": uuid::Uuid::new_v4().to_string(), "body": signal, "contextId": "C1"}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}],
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid})))
    .await?;
    let deadline = tokio::time::Instant::now() + wait;
    let mut any = false;
    loop {
        let Ok(next_msg) = tokio::time::timeout_at(deadline, ws.next()).await else {
            break;
        };
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
        if let Some(id) = v
            .get("messageId")
            .and_then(Value::as_str)
            .filter(|id| id.starts_with('s'))
        {
            ws.send(send(
                json!({"H_": h("AugLoop_Session_Protocol_Response", &[]), "messageId": id}),
            ))
            .await?;
        }
        if v.pointer("/H_/T_")
            .and_then(Value::as_str)
            .is_some_and(|t| t.contains("Error"))
            && !any
        {
            anyhow::bail!(
                "AugLoop: {}",
                v.pointer("/H_/T_")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
            );
        }
        let bodies: Vec<Value> = v
            .get("ops")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .flat_map(|op| {
                op.get("items")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default()
            })
            .filter_map(|i| i.get("body").cloned())
            .collect();
        let mut done = false;
        for b in &bodies {
            any = true;
            done |= seen(b);
        }
        if done {
            break;
        }
    }
    let _ = ws.close(None).await;
    Ok(())
}

/// Make the audio recap over AugLoop and wait for the podcast to finish
/// (or fail): the first annotation with a podcast id or a workflow error
/// answers Teams' operation; an in-progress podcast is followed until its
/// status changes (at most 10 minutes).
pub async fn generate(m: &Meeting, ui_language: &str) -> Result<Generation> {
    generate_signal(&|id: &str| generation_signal(m, id), ui_language, &|_| {}).await
}

/// Generate audio recap's Generate: several meetings, a style and a
/// language, made over AugLoop like the single-meeting one. `progress` gets
/// every update of the recap while it's being made (its chapters come one
/// by one, each with its own audio as it's made).
pub async fn generate_multi(
    meetings: &[Meeting],
    style_choice: &str,
    language: &str,
    ui_language: &str,
    progress: &(dyn Fn(&Generation) + Sync),
) -> Result<Generation> {
    anyhow::ensure!(
        !meetings.is_empty() && meetings.len() <= 8,
        "Select up to 8 meetings"
    );
    generate_signal(
        &|id: &str| generation_signal_multi(meetings, style(style_choice), language, id),
        ui_language,
        progress,
    )
    .await
}

/// A recap's chapters as (status, has audio), for the logs.
pub fn chapter_states(podcast: &Value) -> Vec<(String, bool)> {
    podcast
        .get("chapters")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|c| {
            let st = c
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            let audio = c
                .pointer("/audioFile/fileUrl")
                .and_then(Value::as_str)
                .is_some_and(|u| !u.is_empty());
            (st, audio)
        })
        .collect()
}

/// Whether a recap has chapters to play (Teams' `hasChapters`: a chapter
/// in progress or made), the moment Teams starts a just-made recap.
pub fn has_chapters(podcast: &Value) -> bool {
    chapter_states(podcast)
        .iter()
        .any(|(st, _)| st == "InProgress" || st == "Completed")
}

async fn generate_signal(
    make: &(dyn Fn(&str) -> Value + Sync),
    ui_language: &str,
    progress: &(dyn Fn(&Generation) + Sync),
) -> Result<Generation> {
    let generation_id = uuid::Uuid::new_v4().to_string();
    // Teams' publishing path: identifier "teams_recap_podcast_generation",
    // subscription "podcast-session", a new request id.
    let path = json!([
        "session",
        "doc",
        "teams_recap_podcast_generation_podcast-session",
        uuid::Uuid::new_v4().to_string()
    ]);
    let mut last: Option<Generation> = None;
    run_op("AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation", path, make(&generation_id), ui_language, std::time::Duration::from_secs(600), |b| {
        let Some(g) = generation_from(b) else { return false };
        // An update without the podcast keeps the podcast seen.
        let g = match (&last, g.podcast.is_null()) {
            (Some(prev), true) => Generation { podcast: prev.podcast.clone(), ..g },
            _ => g,
        };
        let finished = g.status != "IN_PROGRESS";
        tracing::info!(status = %g.status, chapters = ?chapter_states(&g.podcast), "audio recap: update");
        if !finished {
            progress(&g);
        }
        last = Some(g);
        finished
    })
    .await?;
    last.context("No audio recap came back")
}

/// Delete audio recaps (Teams' deletePodcasts: a TeamsRecapPodcastDeleteSignal
/// with the podcast ids); the ids deleted.
pub async fn delete(ids: &[String], ui_language: &str) -> Result<Vec<String>> {
    let signal = json!({ "podcastIds": ids, "H_": h("AugLoop_TeamsRecapPodcast_TeamsRecapPodcastDeleteSignal", &["AugLoop_Signals_Signal"]) });
    let mut deleted = Vec::new();
    let mut answered = false;
    run_op(
        "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastDeleteAnnotation",
        json!(["session", "doc"]),
        signal,
        ui_language,
        std::time::Duration::from_secs(60),
        |b| {
            let Some(results) = b.get("operationResults").and_then(Value::as_array) else {
                return false;
            };
            answered = true;
            deleted = results
                .iter()
                .filter(|r| r.get("success").and_then(Value::as_bool) == Some(true))
                .filter_map(|r| {
                    r.get("podcastId")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
                .collect();
            true
        },
    )
    .await?;
    anyhow::ensure!(answered, "AugLoop didn't answer the delete");
    Ok(deleted)
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
    fn listen_on_mobile_link() {
        assert_eq!(
            mobile_link("abc-1"),
            "https://teams.microsoft.com/l/meetingpodcast?id=abc-1&origin=desktopQRCode"
        );
    }

    #[test]
    fn signal_and_consume_query() {
        let m = Meeting {
            subject: "S".into(),
            thread_id: "19:meeting_x@thread.v2".into(),
            ical_uid: "04abc".into(),
            start_ms: 1_795_235_380_000,
            end_ms: 1_795_237_720_000,
            transcripts: vec![Transcript {
                id: "t1".into(),
                ..Default::default()
            }],
            ..Default::default()
        };
        let s = generation_signal(&m, "g1");
        assert_eq!(s["range"]["startDateTime"], "2026-11-21T04:29:40.000Z");
        assert_eq!(s["eventsWithTranscripts"][0]["event"]["iCalUid"], "04ABC");
        assert_eq!(
            s["eventsWithTranscripts"][0]["transcripts"][0]["transcriptId"],
            "t1"
        );
        assert_eq!(s["podcastType"], "SharedSingleMeetingAudioRecap");
        let two = [
            m.clone(),
            Meeting {
                thread_id: "19:meeting_y@thread.v2".into(),
                start_ms: 1_795_000_000_000,
                end_ms: 1_795_000_600_000,
                ..m.clone()
            },
        ];
        let s = generation_signal_multi(&two, style("Newscast"), "en-US", "g2");
        assert_eq!(s["eventsWithTranscripts"].as_array().map(Vec::len), Some(2));
        assert_eq!(s["range"]["startDateTime"], "2026-11-18T11:06:40.000Z");
        assert_eq!(s["range"]["endDateTime"], "2026-11-21T05:08:40.000Z");
        assert_eq!(s["style"], json!({"format": "Single", "tone": "newscast"}));
        assert!(s.get("podcastType").is_none());
        assert_eq!(style("Executive"), ("Dual", "formal"));
        assert_eq!(style("Casual"), ("Dual", "casual"));
        assert_eq!(
            consume_query(&m, "en-US", "formal"),
            "podcasts/consume?threadId=19:meeting_x@thread.v2&transcriptIds=t1&language=en-US&style=formal&iCalUid=04ABC"
        );
    }

    #[test]
    fn generation_states() {
        let failed = json!({"podcast": {"status": "Failed", "statusMessage": "NoValidMeetingInsightError", "id": "p"}, "workflowStatus": 46, "workflowStatusMessage": "NoValidMeetingInsightError",
            "H_": {"T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation"}});
        let g = generation_from(&failed).unwrap();
        assert_eq!(
            (g.status.as_str(), g.message.as_str()),
            ("FAILED", "NoValidMeetingInsightError")
        );
        assert!(no_insight(&g.message));
        let going = json!({"podcast": {"status": "InProgress", "id": "p"}, "workflowStatus": 0, "H_": {"T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation"}});
        assert_eq!(generation_from(&going).unwrap().status, "IN_PROGRESS");
        let workflow = json!({"workflowStatus": 3, "workflowStatusMessage": "X", "H_": {"T_": "AugLoop_TeamsRecapPodcast_TeamsRecapPodcastGenerationAnnotation"}});
        assert_eq!(generation_from(&workflow).unwrap().status, "FAILED");
        assert!(generation_from(&json!({"H_": {"T_": "Other"}})).is_none());
    }

    #[test]
    fn chapters_to_play() {
        let p = json!({"status": "InProgress", "chapters": [{"status": "NotStarted"}, {"status": "NotStarted"}]});
        assert!(!has_chapters(&p));
        let p = json!({"status": "InProgress", "chapters": [{"status": "InProgress", "audioFile": {"fileType": "m3u8", "fileUrl": "https://x/a.m3u8"}}, {"status": "NotStarted"}]});
        assert!(has_chapters(&p));
        assert_eq!(
            chapter_states(&p),
            vec![
                ("InProgress".to_string(), true),
                ("NotStarted".to_string(), false)
            ]
        );
        assert!(!has_chapters(&json!({"chapters": [{"status": "Failed"}]})));
    }
}
