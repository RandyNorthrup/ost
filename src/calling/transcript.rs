//! Teams' live meeting transcript (the Transcript side pane).
//!
//! - **Live.** The media processor sends the meeting's speech recognition
//!   on the MCP data channel ([`super::mcp::transcript_payload`]):
//!   `recognitionResults`, each a partial (`isFinal: false`,
//!   `temporaryStorageOnly: true`, what live captions show) or a final
//!   (`isFinal: true`). The pane lists the finals, as Teams' pane does
//!   (verified on winpc: its entries are the finals' ids). `events` carry
//!   transcript starts and stops.
//! - **History.** On opening, Teams reads the meeting's stored transcript
//!   and call events from the real-time activity feed
//!   (`meetingDetails.realTimeActivityFeedDetails.links.getArtifacts`,
//!   POST `{"artifactTypes": ["Transcript", "CallEvents"], "maxResults":
//!   -1}` with the IC3 token).
//!
//! Times: `timestampAudioSent` counts 100 ns since 1900 (NTP's epoch).

use serde_json::Value;

/// What a row of the pane is.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    Speech,
    /// "<name> started transcription".
    Started,
    /// "<name> stopped transcription".
    Stopped,
}

/// One row.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub kind: Kind,
    /// The speaker's (or starter's) MRI.
    pub user_id: String,
    pub name: String,
    pub text: String,
    /// The words before the service masked profanity, when it says
    /// (`rawText`): shown unless "Filter profane words" is on.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub raw_text: Option<String>,
    /// A final result (a caption still being recognized is not).
    pub is_final: bool,
    /// Unix milliseconds.
    pub at_ms: i64,
    /// When a partial result last changed (Unix ms, ours): one not
    /// refined for 5 s is dropped.
    #[serde(skip)]
    pub updated_ms: i64,
}

/// Every recognition result in a live message, partials included: each
/// partial (and the final after it) comes with a new id, so a speaker's
/// partial is replaced by the next one from them ([`merge_live`]).
pub fn results_from_live(payload: &Value) -> Vec<Entry> {
    payload
        .get("recognitionResults")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|r| Entry {
            id: s(r, "id"),
            kind: Kind::Speech,
            user_id: s(r, "userId"),
            name: s(r, "displayName"),
            text: s(r, "text"),
            raw_text: r.get("rawText").and_then(Value::as_str).map(str::to_string),
            is_final: r.get("isFinal").and_then(Value::as_bool) == Some(true),
            at_ms: r
                .get("timestampAudioSent")
                .and_then(Value::as_i64)
                .map(ntp_ticks_to_ms)
                .unwrap_or_default(),
            updated_ms: 0,
        })
        .filter(|e| !e.text.is_empty())
        .collect()
}

/// A partial not refined for this long is dropped (Teams' 5 s).
pub const PARTIAL_TIMEOUT_MS: i64 = 5_000;

/// Add live results as Teams' transcript store does: a speaker has at most
/// one partial (a newer one replaces it, their final removes it); finals
/// go in time order; the partials follow the finals. Partials not refined
/// for [`PARTIAL_TIMEOUT_MS`] are dropped. `now_ms` is the time of arrival.
pub fn merge_live(into: &mut Vec<Entry>, rows: Vec<Entry>, now_ms: i64) {
    let partial = |e: &Entry| e.kind == Kind::Speech && !e.is_final;
    for mut r in rows {
        if r.kind == Kind::Speech {
            if let Some(i) = into
                .iter()
                .position(|e| partial(e) && e.user_id == r.user_id)
            {
                into.remove(i);
            }
        }
        if !r.id.is_empty() && into.iter().any(|e| e.id == r.id) {
            continue;
        }
        if partial(&r) {
            r.updated_ms = now_ms;
            into.push(r);
        } else {
            let finals = into.iter().take_while(|e| !partial(e)).count();
            let at = into[..finals].partition_point(|e| e.at_ms <= r.at_ms);
            into.insert(at, r);
        }
    }
    into.retain(|e| !partial(e) || now_ms - e.updated_ms <= PARTIAL_TIMEOUT_MS);
}

/// Keep at most this many captions (Teams' caption window scrolls back a
/// little; older ones are gone).
pub const MAX_CAPTIONS: usize = 100;

/// Add caption results ([`merge_live`]), keeping the newest
/// [`MAX_CAPTIONS`].
pub fn merge_captions(into: &mut Vec<Entry>, rows: Vec<Entry>, now_ms: i64) {
    merge_live(into, rows, now_ms);
    let extra = into.len().saturating_sub(MAX_CAPTIONS);
    into.drain(..extra);
}

/// Seconds from 1900 to 1970.
const NTP_TO_UNIX: i64 = 2_208_988_800;

/// 100 ns ticks since 1900 as Unix milliseconds.
pub fn ntp_ticks_to_ms(ticks: i64) -> i64 {
    ticks / 10_000 - NTP_TO_UNIX * 1000
}

fn s(v: &Value, k: &str) -> String {
    v.get(k)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

/// A stored speaker or user id as Teams resolves it (its transcript
/// store's `nt`): "<oid>@<tenant>" is the org user "8:orgid:<oid>" (an old
/// MRI joins the tenant and oid without dashes), "<n>@local" (a room's
/// anonymous speaker) stays, and a bare id gains the "8:" prefix.
fn speaker_mri(id: &str, old_mri: bool) -> String {
    if id.is_empty() || id.ends_with("@local") {
        return id.to_string();
    }
    let id = match id.split_once('@') {
        Some((oid, tenant)) if old_mri => {
            format!("orgid:{}_{}", tenant.replace('-', ""), oid.replace('-', ""))
        }
        Some((oid, _)) => format!("orgid:{oid}"),
        None => id.to_string(),
    };
    let prefixed = id
        .split_once(':')
        .is_some_and(|(p, _)| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()));
    if prefixed { id } else { format!("8:{id}") }
}

/// A room's anonymous speaker ("@2" at "…@local") as Teams names them.
fn speaker_name(id: &str, name: &str) -> String {
    match name.strip_prefix('@') {
        Some(n) if id.ends_with("@local") => format!("Speaker {n}"),
        _ => name.to_string(),
    }
}

/// A stored time: ISO 8601, or 100 ns ticks since 1900.
fn stored_ms(v: Option<&Value>) -> Option<i64> {
    match v? {
        Value::String(t) => chrono::DateTime::parse_from_rfc3339(t)
            .ok()
            .map(|d| d.timestamp_millis()),
        Value::Number(n) => n.as_i64().map(ntp_ticks_to_ms),
        _ => None,
    }
}

fn event_kind(t: &str) -> Option<Kind> {
    match t {
        "TranscriptStarted" => Some(Kind::Started),
        "TranscriptStopped" => Some(Kind::Stopped),
        _ => None,
    }
}

/// The rows a live speech recognition message adds: its results (partials
/// too, see [`merge_live`]) and its transcript events.
pub fn from_live(payload: &Value) -> Vec<Entry> {
    let mut out = results_from_live(payload);
    for e in payload
        .get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if let Some(kind) = event_kind(&s(e, "type")) {
            out.push(Entry {
                id: s(e, "id"),
                kind,
                user_id: speaker_mri(&s(e, "userId"), false),
                name: s(e, "displayName"),
                text: String::new(),
                raw_text: None,
                is_final: true,
                at_ms: stored_ms(e.get("timestamp")).unwrap_or_default(),
                updated_ms: 0,
            });
        }
    }
    out
}

fn iso_ms(t: &str) -> i64 {
    chrono::DateTime::parse_from_rfc3339(t)
        .map(|d| d.timestamp_millis())
        .unwrap_or_default()
}

/// The rows of the stored transcript and call events (a `getArtifacts`
/// reply), as Teams merges them: by time, an event before speech at the
/// same moment; events other than transcript starts and stops are left out.
/// Speech carries `speakerId`, `displayName` and `startTime`; events
/// `eventId`, `eventType`, `userId`, `displayName` and `timestamp`.
pub fn from_artifacts(reply: &Value) -> Vec<Entry> {
    let mut speech = Vec::new();
    let mut events = Vec::new();
    for a in reply
        .get("artifacts")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let artifact = s(a, "artifactType");
        for e in a
            .get("artifactEntries")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let c: Value = e
                .get("jsonContent")
                .and_then(Value::as_str)
                .and_then(|c| serde_json::from_str(c).ok())
                .unwrap_or_default();
            let old = c.get("isOldMri").and_then(Value::as_bool).unwrap_or(false);
            let created = iso_ms(&s(e, "createdTimeUtc"));
            match artifact.as_str() {
                "CallEvents" => {
                    let Some(kind) = event_kind(&s(&c, "eventType")) else {
                        continue;
                    };
                    let id = s(&c, "eventId");
                    events.push(Entry {
                        id: if id.is_empty() { s(e, "entryId") } else { id },
                        kind,
                        user_id: speaker_mri(&s(&c, "userId"), old),
                        name: s(&c, "displayName"),
                        text: String::new(),
                        raw_text: None,
                        is_final: true,
                        at_ms: stored_ms(c.get("timestamp")).unwrap_or(created),
                        updated_ms: 0,
                    });
                }
                "Transcript" => {
                    let speaker = speaker_mri(&s(&c, "speakerId"), old);
                    let id = s(&c, "entryId");
                    speech.push(Entry {
                        id: if id.is_empty() { s(e, "entryId") } else { id },
                        kind: Kind::Speech,
                        name: speaker_name(&speaker, &s(&c, "displayName")),
                        user_id: speaker,
                        text: s(&c, "text"),
                        raw_text: c.get("rawText").and_then(Value::as_str).map(str::to_string),
                        is_final: true,
                        at_ms: stored_ms(c.get("startTime")).unwrap_or(created),
                        updated_ms: 0,
                    });
                }
                _ => {}
            }
        }
    }
    speech.sort_by_key(|e| e.at_ms);
    events.sort_by_key(|e| e.at_ms);
    let mut out = Vec::with_capacity(speech.len() + events.len());
    let (mut i, mut j) = (0, 0);
    while i < speech.len() || j < events.len() {
        if i < speech.len() && (j == events.len() || speech[i].at_ms < events[j].at_ms) {
            out.push(speech[i].clone());
            i += 1;
        } else {
            out.push(events[j].clone());
            j += 1;
        }
    }
    out
}

/// The meeting's `getArtifacts` link, from a join response's
/// `meetingDetails.realTimeActivityFeedDetails`.
pub fn artifacts_link(join: &Value) -> Option<String> {
    [
        "/meetingDetails",
        "/conversationResponse/meetingDetails",
        "/conversation/meetingDetails",
    ]
    .iter()
    .find_map(|p| {
        join.pointer(&format!(
            "{p}/realTimeActivityFeedDetails/links/getArtifacts"
        ))
    })
    .and_then(Value::as_str)
    .filter(|u| u.starts_with("https://"))
    .map(str::to_string)
}

/// Read the meeting's stored transcript and call events, as Teams does on
/// opening the pane.
pub async fn history(
    http: &reqwest::Client,
    link: &str,
    chain_id: &str,
) -> anyhow::Result<Vec<Entry>> {
    use anyhow::Context;
    let mut config = crate::config::Config::load()?;
    if config.get_ic3_token().is_none_or(|t| t.is_expired()) {
        crate::auth::oauth::refresh()
            .await
            .context("Token refresh failed")?;
        config = crate::config::Config::load()?;
    }
    let token = config
        .get_ic3_token()
        .context("No calling (IC3) token")?
        .token;
    let session = uuid::Uuid::new_v4().to_string();
    let resp = http
        .post(link)
        .bearer_auth(token)
        .header("x-ms-session-id", &session)
        .header("x-ms-correlation-id", &session)
        .header("x-microsoft-skype-chain-id", chain_id)
        .header("accept", "application/json")
        .json(&serde_json::json!({"artifactTypes": ["Transcript", "CallEvents"], "maxResults": -1}))
        .send()
        .await
        .context("Transcript history")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!(
            "Transcript history failed ({status}): {}",
            &text[..text.len().min(300)]
        );
    }
    let reply: Value = serde_json::from_str(&text).context("Transcript history reply")?;
    // The stored transcript's entry shape (logged so it can be checked
    // against what Teams reads).
    for a in reply
        .get("artifacts")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if let Some(e) = a.pointer("/artifactEntries/0") {
            tracing::debug!(artifact = %s(a, "artifactType"), entry = %e, "stored entry");
        }
        for e in a
            .get("artifactEntries")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let named = e
                .get("jsonContent")
                .and_then(Value::as_str)
                .and_then(|c| serde_json::from_str::<Value>(c).ok())
                .is_some_and(|c| !s(&c, "displayName").is_empty());
            if !named {
                tracing::debug!(entry = %e, "stored entry without a name");
            }
        }
    }
    Ok(from_artifacts(&reply))
}

/// Add rows, keeping order by time and dropping repeats (by id).
pub fn merge(into: &mut Vec<Entry>, rows: Vec<Entry>) {
    for r in rows {
        if !r.id.is_empty() && into.iter().any(|e| e.id == r.id) {
            continue;
        }
        let at = into.partition_point(|e| e.at_ms <= r.at_ms);
        into.insert(at, r);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ntp_ticks() {
        // 2026-11-09T02:22:… from a captured final.
        let ms = ntp_ticks_to_ms(40031800316768100);
        let d = chrono::DateTime::from_timestamp_millis(ms).unwrap();
        assert_eq!(d.format("%Y-%m-%d").to_string(), "2026-11-09");
    }

    #[test]
    fn a_final_replaces_the_speakers_partial() {
        let live = serde_json::json!({"version": "1.1", "recognitionResults": [
            {"id": "a/52", "userId": "8:teamsvisitor:x", "displayName": "OST Guest 1", "text": "Front.", "isFinal": false, "timestampAudioSent": 40031800327868100i64},
            {"id": "a/53", "userId": "8:teamsvisitor:x", "displayName": "OST Guest 1", "text": "Front, right", "isFinal": false, "timestampAudioSent": 40031800327868100i64}
        ]});
        let mut rows = Vec::new();
        merge_live(&mut rows, from_live(&live), 1_000);
        assert_eq!(rows.len(), 1, "one partial per speaker");
        assert_eq!(rows[0].text, "Front, right");
        let fin = serde_json::json!({"recognitionResults": [
            {"id": "a/55", "userId": "8:teamsvisitor:x", "displayName": "OST Guest 1", "text": "Front, right.", "isFinal": true, "timestampAudioSent": 40031800316768100i64}
        ]});
        merge_live(&mut rows, from_live(&fin), 2_000);
        assert_eq!(rows.len(), 1);
        assert!(rows[0].is_final);
        // Someone else's partial follows the finals and lapses after 5 s.
        let other = serde_json::json!({"recognitionResults": [
            {"id": "b/1", "userId": "8:orgid:y", "displayName": "Y", "text": "Hello", "isFinal": false, "timestampAudioSent": 40031800300000000i64}
        ]});
        merge_live(&mut rows, from_live(&other), 3_000);
        assert_eq!(
            rows.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(),
            ["a/55", "b/1"]
        );
        merge_live(&mut rows, Vec::new(), 8_001);
        assert_eq!(rows.len(), 1);
        let ev = serde_json::json!({"events": [{"type": "LanguageMismatch", "id": "a/59"}]});
        assert!(from_live(&ev).is_empty());
    }

    #[test]
    fn reads_stored_call_events() {
        let reply = serde_json::json!({"artifacts": [
            {"artifactType": "Transcript", "artifactEntries": [
                {"entryId": "b/12", "createdTimeUtc": "2026-11-08T23:40:00Z", "jsonContent": "{\"entryId\":\"b/12\",\"text\":\"Front, left.\",\"speakerId\":\"4287e791@2716d134\",\"displayName\":\"OST Test 1\",\"startTime\":\"2026-11-08T23:39:59.5Z\"}"}
            ]},
            {"artifactType": "CallEvents", "artifactEntries": [
                {"entryId": "b/5", "createdTimeUtc": "2026-11-08T23:37:18.6884536Z", "jsonContent": "{\"eventType\":\"CallStarted\",\"displayName\":\"OST Test 1\"}"},
                {"entryId": "b/6", "createdTimeUtc": "2026-11-08T23:37:18.6886005Z", "jsonContent": "{\"eventType\":\"TranscriptStarted\",\"userId\":\"4287e791@2716d134\",\"displayName\":\"OST Test 1\"}"},
                {"entryId": "b/30", "createdTimeUtc": "2026-11-08T23:41:29.7792197Z", "jsonContent": "{\"eventType\":\"TranscriptStopped\",\"userId\":\"4287e791@2716d134\",\"displayName\":\"OST Test 1\"}"}
            ]}
        ]});
        let rows = from_artifacts(&reply);
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].kind, Kind::Started);
        assert_eq!(rows[0].user_id, "8:orgid:4287e791");
        assert_eq!(rows[1].kind, Kind::Speech);
        assert_eq!(rows[1].user_id, "8:orgid:4287e791");
        assert_eq!(rows[1].text, "Front, left.");
        assert_eq!(rows[2].kind, Kind::Stopped);
        let mut all = rows.clone();
        merge(&mut all, rows);
        assert_eq!(all.len(), 3, "no repeats");
    }

    #[test]
    fn captions_keep_the_newest() {
        let a = serde_json::json!({"recognitionResults": [
            {"id": "a/1", "userId": "8:x", "displayName": "G", "text": "Front", "isFinal": false},
            {"id": "a/2", "userId": "8:x", "displayName": "G", "text": "Front left", "isFinal": false},
            {"id": "a/3", "userId": "8:x", "displayName": "G", "text": "Front, left.", "isFinal": true, "rawText": "Front, left."}
        ]});
        let mut c = Vec::new();
        merge_captions(&mut c, results_from_live(&a), 0);
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].raw_text.as_deref(), Some("Front, left."));
        for i in 0..150 {
            let n = Entry {
                id: format!("n/{i}"),
                at_ms: i,
                ..c[0].clone()
            };
            merge_captions(&mut c, vec![n], 0);
        }
        assert_eq!(c.len(), MAX_CAPTIONS);
        assert_eq!(c.last().unwrap().id, "n/149");
    }

    #[test]
    fn speaker_ids_as_teams_resolves_them() {
        assert_eq!(
            speaker_mri("4287e791-aa@2716d134-bb", false),
            "8:orgid:4287e791-aa"
        );
        assert_eq!(
            speaker_mri("4287e791-aa@2716d134-bb", true),
            "8:orgid:2716d134bb_4287e791aa"
        );
        assert_eq!(speaker_mri("2@local", false), "2@local");
        assert_eq!(speaker_mri("teamsvisitor:abc", false), "8:teamsvisitor:abc");
        assert_eq!(
            speaker_mri("8:teamsvisitor:abc", false),
            "8:teamsvisitor:abc"
        );
        assert_eq!(speaker_name("2@local", "@2"), "Speaker 2");
        assert_eq!(speaker_name("8:orgid:a", "@2"), "@2");
    }
}
