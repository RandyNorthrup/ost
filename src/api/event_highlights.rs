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
                Some("Highlights") => loop_file = Some(LoopFile { drive_id: s("driveId"), item_id: s("driveItemId"), location: s("location") }),
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

/// The meeting's artifacts (Teams' listContents for one meeting).
pub async fn artifacts(region: &str, thread: &str, ical_uid: &str, organizer_oid: &str) -> Result<Value> {
    let token = token().await?;
    let q = format!(
        "?threadId={thread}&iCalUid={ical_uid}&organizerId={organizer_oid}&includeTypes=Recording,TranscriptV2,Highlights"
    );
    let url = format!("{}/collab/meetings/contents/{q}", base(region));
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
}
