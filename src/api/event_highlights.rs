//! An event's AI highlights, as Teams' Events app makes them on the
//! event page's Highlights tab (Teams 26304: event-highlights-tab,
//! event-highlights-organizer, services-io-collab-object,
//! services-augloop):
//! 1. the meeting's artifacts (the meeting artifacts service's contents of
//!    the event's meeting thread): its recordings (the "Recording used for
//!    highlights" choices) and its Highlights artifact (a Loop file);
//! 2. no Highlights artifact yet: `createHighlights` = `POST {mcps}/spe/
//!    highlights` `{threadId, organizer: "oid@tid", meetingTitle,
//!    externalEntityKey: ""}` (201 made, 409 already there);
//! 3. with a recording picked: an AugLoop operation (identifier
//!    "teams_event_highlights") with the TeamsEventHighlightsSignal
//!    `{eventContext {eventId, threadId, eventLanguage}, recording {driveId,
//!    itemId}, loopFile {driveId, itemId, siteUrl}}`; the progress
//!    annotation names the steps (FetchGroundingData, GenerateHighlights,
//!    WriteToLoop) and the result annotation says whether it succeeded
//!    (`succeeded`, `errorCode`). The highlights are written into the Loop
//!    file, which the tab then shows.

use anyhow::{Context, Result};
use serde_json::{Value, json};

fn base(region: &str) -> String {
    let region = if region.is_empty() || !region.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') { "us" } else { region };
    format!("https://teams.microsoft.com/api/mcps/{region}")
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for(&format!("{}/.default", super::meeting_notes::RESOURCE)).await
}

/// A recording of the meeting (a "Recording" artifact), as the recording
/// picker lists it.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Recording {
    pub id: String,
    pub drive_id: String,
    pub item_id: String,
    /// .NET ticks.
    pub start: String,
    pub end: String,
    pub location: String,
}

/// The meeting's highlights Loop file (its "Highlights" artifact).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct LoopFile {
    pub drive_id: String,
    pub item_id: String,
    pub location: String,
}

/// The recordings and the highlights file from a contents reply (every
/// meeting entry whose thread is `thread`).
pub fn artifacts_from(v: &Value, thread: &str) -> (Vec<Recording>, Option<LoopFile>) {
    let (recs, lf, _) = artifacts_with_transcripts(v, thread);
    (recs, lf)
}

/// [`artifacts_from`] with the transcripts' addresses too.
pub fn artifacts_with_transcripts(v: &Value, thread: &str) -> (Vec<Recording>, Option<LoopFile>, Vec<String>) {
    let mut transcripts = Vec::new();
    let mut recs = Vec::new();
    let mut loop_file = None;
    for m in v.get("value").and_then(Value::as_array).into_iter().flatten() {
        let t = m.pointer("/threadInfo/threadId").and_then(Value::as_str).unwrap_or_default();
        if !thread.is_empty() && !t.is_empty() && t != thread {
            continue;
        }
        for r in m.get("resources").and_then(Value::as_array).into_iter().flatten() {
            let s = |k: &str| r.get(k).or_else(|| r.pointer(&format!("/metadata/{k}"))).and_then(Value::as_str).unwrap_or_default().to_string();
            match r.get("type").and_then(Value::as_str) {
                Some("Recording") => recs.push(Recording {
                    id: Some(s("id")).filter(|i| !i.is_empty()).unwrap_or_else(|| s("driveItemId")),
                    drive_id: s("driveId"),
                    item_id: s("driveItemId"),
                    start: s("startTime"),
                    end: s("endTime"),
                    location: s("location"),
                }),
                Some("TranscriptV2") => transcripts.push(s("location")),
                Some("Highlights" | "highlights") => loop_file = Some(LoopFile { drive_id: s("driveId"), item_id: s("driveItemId"), location: s("location") }),
                _ => {}
            }
        }
    }
    (recs, loop_file, transcripts)
}

/// Download a meeting file (the recording's video, or a transcript as a
/// Word document: its `…/media/transcripts/{id}/content?format=docx`, as
/// Teams' downloadODSPTranscript) into `dir`; the saved path.
pub async fn download(location: &str, docx: bool, name: &str, dir: &std::path::Path) -> Result<std::path::PathBuf> {
    let u = url::Url::parse(location).context("Not a file address")?;
    let host = u.host_str().unwrap_or_default().to_string();
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "Not a file address");
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let base = location.split('?').next().unwrap_or_default();
    let url = if docx {
        format!("{base}?format=docx")
    } else if base.ends_with("/content") {
        base.to_string()
    } else {
        format!("{base}/content")
    };
    let r = reqwest::Client::new().get(&url).bearer_auth(token).send().await.context("The file")?;
    anyhow::ensure!(r.status().is_success(), "The file answered {}", r.status());
    let bytes = r.bytes().await?;
    let clean: String = name.chars().filter(|c| !"/\\:*?\"<>|".contains(*c)).collect();
    let path = dir.join(clean);
    std::fs::write(&path, &bytes)?;
    Ok(path)
}

/// The meeting's own artifacts as Teams' meetingArtifactsV3 reads them (the
/// meeting content service, `GET {mcps}/contents?threadId&iCalUid
/// &organizerId`: a collection whose resources include the Highlights
/// file, `{id, type, location, driveId, driveItemId}`), wrapped as a
/// contents reply for [`artifacts_from`]. The reply's shape is logged.
pub async fn artifacts_v3(region: &str, thread: &str, ical_uid: &str, organizer_oid: &str, tenant: &str) -> Result<Value> {
    // The organizer as "oid@tid" (the service answers a bare oid with
    // CrossTenantRequest), then as a bare oid.
    let mut last = Err(anyhow::anyhow!("No organizer"));
    for org in [format!("{organizer_oid}@{tenant}"), organizer_oid.to_string()] {
        last = artifacts_v3_as(region, thread, ical_uid, &org).await;
        if last.is_ok() {
            break;
        }
    }
    last
}

async fn artifacts_v3_as(region: &str, thread: &str, ical_uid: &str, organizer: &str) -> Result<Value> {
    let token = token().await?;
    let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>();
    let mut url = format!("{}/contents?threadId={}", base(region), enc(thread));
    if !ical_uid.is_empty() {
        url.push_str(&format!("&iCalUid={}", enc(ical_uid)));
    }
    if !organizer.is_empty() {
        url.push_str(&format!("&organizerId={}", enc(organizer)));
    }
    let r = reqwest::Client::new()
        .get(&url)
        .bearer_auth(&token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .send()
        .await
        .context("The meeting content service")?;
    let status = r.status();
    let v: Value = r.json().await.unwrap_or_default();
    let types: Vec<String> = v.get("resources").and_then(Value::as_array).into_iter().flatten().filter_map(|x| x.get("type").and_then(Value::as_str).map(str::to_string)).collect();
    let why = v.get("ErrorMessage").and_then(Value::as_str).unwrap_or_default().to_string();
    let sub = v.get("SubError").map(Value::to_string).unwrap_or_default();
    tracing::info!(%status, keys = ?v.as_object().map(|o| o.keys().cloned().collect::<Vec<_>>()), ?types, %why, %sub, "event highlights: meeting contents");
    anyhow::ensure!(status.is_success(), "The meeting content service answered {status}");
    let resources = v.get("resources").cloned().unwrap_or(json!([]));
    Ok(json!({ "value": [{ "threadInfo": { "threadId": thread }, "resources": resources }] }))
}

/// The meeting artifacts around the meeting's time (the artifacts
/// service's contents for the 12 hours either side of `start_ms`, as
/// Meeting Recaps reads a day), with Highlights; the caller picks the
/// meeting by its thread.
pub async fn artifacts(region: &str, start_ms: i64) -> Result<Value> {
    let token = token().await?;
    let f = |ms: i64| chrono::DateTime::from_timestamp_millis(ms).map(|d| d.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)).unwrap_or_default();
    let url = format!(
        "{}/user/meetings/contents?top=20&startDateTime={}&endDateTime={}&includeTypes=Recording,TranscriptV2,Highlights,Notes",
        base(region),
        f(start_ms - 12 * 3_600_000),
        f(start_ms + 12 * 3_600_000)
    );
    let r = reqwest::Client::new()
        .get(&url)
        .bearer_auth(&token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .send()
        .await
        .context("The meeting artifacts service")?;
    let status = r.status();
    let text = r.text().await.unwrap_or_default();
    anyhow::ensure!(status.is_success(), "The meeting artifacts service answered {status}");
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

/// Teams' createHighlights: the meeting's Highlights artifact made (or
/// already there).
pub async fn create(region: &str, thread: &str, organizer: &str, title: &str) -> Result<u16> {
    let token = token().await?;
    let r = reqwest::Client::new()
        .post(format!("{}/spe/highlights", base(region)))
        .bearer_auth(token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .json(&json!({ "threadId": thread, "organizer": organizer, "meetingTitle": title, "externalEntityKey": "" }))
        .send()
        .await
        .context("The meeting artifacts service")?;
    let status = r.status();
    anyhow::ensure!(status.as_u16() == 201 || status.as_u16() == 409 || status.is_success(), "createHighlights answered {status}");
    Ok(status.as_u16())
}

/// The highlights signal (Teams' TeamsEventHighlightsSignal).
pub fn signal(event_id: &str, thread: &str, language: &str, rec: (&str, &str), loop_file: (&str, &str, &str)) -> Value {
    let mut ctx = json!({ "eventId": event_id, "threadId": thread });
    if !language.is_empty() {
        ctx["eventLanguage"] = json!(language);
    }
    let mut lf = json!({ "driveId": loop_file.0, "itemId": loop_file.1 });
    if !loop_file.2.is_empty() {
        lf["siteUrl"] = json!(loop_file.2);
    }
    json!({
        "eventContext": ctx,
        "recording": { "driveId": rec.0, "itemId": rec.1 },
        "loopFile": lf,
        "H_": { "T_": "AugLoop_TeamsEventHighlights_TeamsEventHighlightsSignal", "B_": ["AugLoop_Signals_Signal"] },
    })
}

/// The Loop file's site (Teams' siteUrl from the artifact's location: the
/// address up to its `/_api/` part, or its personal site).
pub fn site_url(location: &str) -> String {
    if let Some(i) = location.find("/_api/") {
        return location[..i].to_string();
    }
    if let Some(i) = location.find("/personal/") {
        let rest = &location[i + 10..];
        let end = rest.find('/').map(|j| i + 10 + j).unwrap_or(location.len());
        return location[..end].to_string();
    }
    String::new()
}

/// How long a published recording stays on the event page (Teams'
/// virtualEventsRecording expirationDurationDays).
pub const EXPIRATION_DAYS: i64 = 30;
/// Extend's days (Teams' "Extend for 60 days").
pub const EXTENSION_DAYS: i64 = 60;

/// A recording as Teams publishes it to the event's session (its
/// addVirtualEventSessionRecording input after the resolver's At(): `{name,
/// webUrl, duration, expirationDurationDays, driveId, itemId}`, plus the
/// Loop page's serialized `highlightsContent` when the highlights go with
/// it, and `isDraft` for a draft). For a meeting artifact Teams names the
/// file by the artifact's id and sends its location as the address.
pub fn recording_body(name: &str, web_url: &str, duration_ms: Option<f64>, drive_id: &str, item_id: &str, highlights_content: Option<&str>, draft: bool) -> Value {
    let mut b = json!({ "name": name, "webUrl": web_url, "expirationDurationDays": EXPIRATION_DAYS, "driveId": drive_id, "itemId": item_id });
    if let Some(d) = duration_ms {
        b["duration"] = json!(d);
    }
    if let Some(c) = highlights_content {
        b["highlightsContent"] = json!(c);
    }
    if draft {
        b["isDraft"] = json!(true);
    }
    b
}

/// The video's length in milliseconds, as Teams reads it before
/// publishing (its fetchOdspVideoItem: the file's `video.duration`).
pub async fn video_duration(location: &str, drive_id: &str, item_id: &str) -> Result<Option<f64>> {
    let u = url::Url::parse(location).context("Not a file address")?;
    let host = u.host_str().unwrap_or_default().to_string();
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "Not a file address");
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let base = location.split('?').next().unwrap_or_default().trim_end_matches("/content");
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c));
    let url = if base.contains("/_api/") {
        format!("{base}?select=video")
    } else if ok(drive_id) && ok(item_id) {
        format!("https://{host}/_api/v2.0/drives/{drive_id}/items/{item_id}?select=video")
    } else {
        anyhow::bail!("Not a file address")
    };
    let r = reqwest::Client::new().get(&url).bearer_auth(token).send().await.context("The file")?;
    anyhow::ensure!(r.status().is_success(), "The file answered {}", r.status());
    let v: Value = r.json().await.unwrap_or_default();
    Ok(v.pointer("/video/duration").and_then(Value::as_f64))
}

/// The session's recording Teams treats as the active one (the first),
/// and its publish status ("Draft", "Scheduled", "InProgress",
/// "Published", "Failed", "Expired").
pub fn active_recording(sessions: &Value) -> (String, Option<Value>) {
    let s = sessions.as_array().and_then(|a| a.first()).cloned().unwrap_or_default();
    let sid = s.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
    let rec = s.get("recordings").and_then(Value::as_array).and_then(|a| a.first()).cloned();
    (sid, rec)
}

/// What came of a generation: the steps seen, and the result.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Generation {
    pub steps: Vec<String>,
    pub succeeded: bool,
    pub error_code: String,
}

/// Generate the highlights over AugLoop and wait for the result (at most
/// 10 minutes).
pub async fn generate(sig: Value, ui_language: &str) -> Result<Generation> {
    let path = json!(["session", "doc", format!("teams_event_highlights_{}", uuid::Uuid::new_v4()), uuid::Uuid::new_v4().to_string()]);
    let mut g = Generation::default();
    let mut answered = false;
    super::podcast::run_op_with(
        &["AugLoop_TeamsEventHighlights_TeamsEventHighlightsProgressAnnotation", "AugLoop_TeamsEventHighlights_TeamsEventHighlightsAnnotation"],
        path,
        sig,
        ui_language,
        std::time::Duration::from_secs(600),
        |b| {
            match b.pointer("/H_/T_").and_then(Value::as_str) {
                Some("AugLoop_TeamsEventHighlights_TeamsEventHighlightsProgressAnnotation") => {
                    if let Some(step) = b.get("step").and_then(Value::as_str) {
                        tracing::info!(step, "event highlights: step");
                        g.steps.push(step.to_string());
                    }
                    false
                }
                Some("AugLoop_TeamsEventHighlights_TeamsEventHighlightsAnnotation") => {
                    answered = true;
                    g.succeeded = b.get("succeeded").and_then(Value::as_bool).unwrap_or(false);
                    g.error_code = b.get("errorCode").and_then(Value::as_str).unwrap_or_default().to_string();
                    true
                }
                other => {
                    tracing::info!(kind = other.unwrap_or_default(), "event highlights: other answer");
                    false
                }
            }
        },
    )
    .await?;
    anyhow::ensure!(answered, "AugLoop didn't answer the highlights");
    Ok(g)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artifacts_and_signal() {
        let v = json!({"value": [{"threadInfo": {"threadId": "19:meeting_a@thread.v2"}, "resources": [
            {"type": "Recording", "location": "https://x-my.sharepoint.com/personal/u/_api/v2.1/drives/b!d/items/R1", "metadata": {"driveId": "b!d", "driveItemId": "R1", "startTime": "1", "endTime": "2"}},
            {"type": "Highlights", "location": "https://x-my.sharepoint.com/personal/u/_api/v2.1/drives/b!d/items/L1", "metadata": {"driveId": "b!d", "driveItemId": "L1"}}]},
            {"threadInfo": {"threadId": "19:meeting_b@thread.v2"}, "resources": [{"type": "Recording", "metadata": {"driveId": "x", "driveItemId": "y"}}]}]});
        let (recs, lf) = artifacts_from(&v, "19:meeting_a@thread.v2");
        assert_eq!(recs.len(), 1);
        assert_eq!(recs[0].item_id, "R1");
        let lf = lf.unwrap();
        assert_eq!(lf.item_id, "L1");
        assert_eq!(site_url(&lf.location), "https://x-my.sharepoint.com/personal/u");
        let s = signal("e1", "19:meeting_a@thread.v2", "en-US", ("b!d", "R1"), ("b!d", "L1", "https://x-my.sharepoint.com/personal/u"));
        assert_eq!(s["eventContext"]["eventLanguage"], "en-US");
        assert_eq!(s["loopFile"]["siteUrl"], "https://x-my.sharepoint.com/personal/u");
        assert_eq!(s["H_"]["T_"], "AugLoop_TeamsEventHighlights_TeamsEventHighlightsSignal");
    }

    #[test]
    fn publish_bodies() {
        let d = recording_body("rec.mp4", "https://x/_api/v2.1/drives/b!d/items/R1", Some(171_000.0), "b!d", "R1", None, true);
        assert_eq!(d["isDraft"], true);
        assert_eq!(d["expirationDurationDays"], 30);
        assert!(d.get("highlightsContent").is_none());
        let p = recording_body("rec.mp4", "https://x", None, "b!d", "R1", Some("<p>hi</p>"), false);
        assert_eq!(p["highlightsContent"], "<p>hi</p>");
        assert!(p.get("isDraft").is_none() && p.get("duration").is_none());
        let s = json!([{"id": "s1", "recordings": [{"id": "r1", "publishProgress": {"status": "Draft"}}]}]);
        let (sid, rec) = active_recording(&s);
        assert_eq!(sid, "s1");
        assert_eq!(rec.unwrap()["publishProgress"]["status"], "Draft");
        assert!(active_recording(&json!([])).1.is_none());
    }
}
