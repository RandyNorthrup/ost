//! Teams' Meeting Recaps app (opened from Events' View audio recaps;
//! measured in Teams desktop 26304 on winpc 2026-11-18): Home lists your
//! meetings that have something to recap, day by day; Audio recaps lists
//! your AI audio recaps. Both come from Teams' regional meeting artifacts
//! service (`https://teams.microsoft.com/api/mcps/{region}`, token for
//! resource 6bc3b958-689b-49f5-9006-36d165f30e00):
//! - `GET podcasts?top=10` → `{items: [...], skipToken}`;
//! - `GET user/meetings/contents?top=20&startDateTime=<day's start>&
//!   endDateTime=<day's end>&includeTypes=Recording,TranscriptV2,
//!   MeetingChat,MeetingStage,Notes` per day (local days, UTC with
//!   milliseconds) → `{value: [{threadInfo: {threadId, iCalUid, organizer
//!   {emailAddress {name, address}}, start, end, subject, …}, resources}],
//!   paginationInfo}`.

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

fn base(region: &str) -> String {
    let region = if region.is_empty() || !region.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') { "us" } else { region };
    format!("https://teams.microsoft.com/api/mcps/{region}")
}

async fn get(url: &str) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for(&format!("{}/.default", super::meeting_notes::RESOURCE)).await?;
    let r = reqwest::Client::new()
        .get(url)
        .bearer_auth(token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .send()
        .await
        .context("The meeting artifacts service")?;
    let status = r.status();
    anyhow::ensure!(status.is_success(), "The meeting artifacts service answered {status}");
    r.json().await.context("The meeting artifacts service's reply")
}

/// A day's meeting artifacts as the service gives them (debugging aid:
/// examples/recap_days).
pub async fn day_contents(region: &str, start: chrono::DateTime<chrono::Utc>, end: chrono::DateTime<chrono::Utc>) -> Result<Value> {
    get(&format!("{}/{}", base(region), day_query(start, end))).await
}

/// Audio recaps (Teams' podcasts), newest first.
pub async fn podcasts(region: &str) -> Result<Value> {
    let v = get(&format!("{}/podcasts?top=10", base(region))).await?;
    Ok(json!({ "items": v.get("items").cloned().unwrap_or(json!([])), "skipToken": v.get("skipToken").cloned().unwrap_or(Value::Null) }))
}

/// The audio recap already made from a meeting's transcripts (Teams'
/// `podcasts/consume` check before generating); None on 404.
pub async fn podcast_consume(region: &str, query: &str) -> Result<Option<Value>> {
    let token = crate::auth::oauth::access_token_for(&format!("{}/.default", super::meeting_notes::RESOURCE)).await?;
    let r = reqwest::Client::new()
        .get(format!("{}/{query}", base(region)))
        .bearer_auth(token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .send()
        .await
        .context("The meeting artifacts service")?;
    let status = r.status();
    if status == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    anyhow::ensure!(status.is_success(), "The meeting artifacts service answered {status}");
    Ok(Some(r.json().await.context("The meeting artifacts service's reply")?))
}

/// A day's request, as Teams asks (the local day's first and last moment).
pub fn day_query(start: chrono::DateTime<chrono::Utc>, end: chrono::DateTime<chrono::Utc>) -> String {
    let f = |t: chrono::DateTime<chrono::Utc>| t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    format!(
        "user/meetings/contents?top=20&startDateTime={}&endDateTime={}&includeTypes=Recording,TranscriptV2,MeetingChat,MeetingStage,Notes",
        f(start),
        f(end)
    )
}

/// A meeting row of Home and Generate audio recap from one of a day's
/// threads (Teams' meetingRecapList node, its resolver's `Ee`).
pub fn row_from(m: &Value) -> Option<Value> {
    let t = m.get("threadInfo")?;
    let s = |p: &str| t.pointer(p).and_then(Value::as_str).unwrap_or_default().to_string();
    let utc = |p: &str| {
        let d = s(p);
        if d.is_empty() { d } else { format!("{}Z", d.trim_end_matches('Z').split('.').next().unwrap_or_default()) }
    };
    let resources = || m.get("resources").and_then(Value::as_array).into_iter().flatten();
    let rec = t.get("recommendationData").filter(|r| r.is_object());
    let count = |k: &str| rec.and_then(|r| r.get(k)).and_then(Value::as_u64).unwrap_or(0);
    let list = |k: &str| rec.and_then(|r| r.get(k)).and_then(Value::as_array).cloned().unwrap_or_default();
    let of = |ty: &str| resources().filter(|r| r.get("type").and_then(Value::as_str) == Some(ty)).collect::<Vec<_>>();
    let meta = |r: &Value, k: &str| r.pointer(&format!("/metadata/{k}")).or_else(|| r.get(k)).and_then(Value::as_str).unwrap_or_default().to_string();
    let (recordings, transcripts) = (of("Recording"), of("TranscriptV2"));
    // Whether you can open what the meeting has (Teams' ot.t): none of
    // its recordings and transcripts for you, a recording, or only a
    // transcript.
    let refused = |v: &[&Value]| v.iter().all(|r| r.get("hasPermission").and_then(Value::as_bool) == Some(false));
    let access = if (!recordings.is_empty() || !transcripts.is_empty()) && (transcripts.is_empty() || refused(&transcripts)) && (recordings.is_empty() || refused(&recordings)) {
        "NoPermission"
    } else if recordings.is_empty() && !transcripts.is_empty() {
        "TranscriptOnly"
    } else {
        "Good"
    };
    let recording_list: Vec<Value> = recordings
        .iter()
        .map(|r| json!({ "driveId": meta(r, "driveId"), "itemId": meta(r, "driveItemId"), "url": r.get("location").and_then(Value::as_str).unwrap_or_default(),
                         "hasPermission": r.get("hasPermission").cloned().unwrap_or(Value::Null) }))
        .collect();
    // Home's thumbnail (Teams' xn): the recording the catch-up names, else
    // the first.
    let (rd, ri) = (rec.and_then(|r| r["driveId"].as_str()).unwrap_or_default(), rec.and_then(|r| r["driveItemId"].as_str()).unwrap_or_default());
    let thumb = recording_list
        .iter()
        .find(|r| !ri.is_empty() && r["itemId"] == ri && (rd.is_empty() || r["driveId"] == rd))
        .or_else(|| recording_list.first())
        .cloned()
        .unwrap_or(Value::Null);
    Some(json!({
        "threadId": s("/threadId"),
        // The meeting's calendar event (Teams' node id).
        "eventId": s("/eventId"),
        "subject": s("/subject"),
        "start": utc("/start/dateTime"),
        "end": utc("/end/dateTime"),
        "organizer": s("/organizer/emailAddress/name"),
        "channel": s("/channelDisplayName"),
        // Generate audio recap lists the meetings you have a transcript of.
        "transcript": resources().any(|r| r.get("type").and_then(Value::as_str) == Some("TranscriptV2")),
        // What its Generate sends for the meeting.
        "iCalUid": s("/iCalUid"),
        "organizerId": t.pointer("/organizer/id").or_else(|| t.pointer("/organizer/objectId")).or_else(|| t.pointer("/organizerId")).or_else(|| t.pointer("/organizer/user/id"))
            .and_then(Value::as_str).unwrap_or_default().split('@').next().unwrap_or_default(),
        "transcripts": resources().filter_map(super::podcast::transcript_from).collect::<Vec<_>>(),
        // Generate audio recap's row thumbnail: the first recording's
        // file (Teams' meeting.recordings[0]).
        "recording": resources()
            .find(|r| r.get("type").and_then(Value::as_str) == Some("Recording"))
            .map(|r| {
                let g = |k: &str| r.pointer(&format!("/metadata/{k}")).or_else(|| r.get(k)).and_then(Value::as_str).unwrap_or_default().to_string();
                json!({ "driveId": g("driveId"), "itemId": g("driveItemId") })
            })
            .unwrap_or(Value::Null),
        // The meeting's catch-up counts (Teams' recommendationData
        // actionItemCount / mentionEventCount; 0 without one).
        "catchUp": rec.is_some(),
        "actionItemCount": count("actionItemCount"),
        "mentionEventCount": count("mentionEventCount"),
        // Home's row (Teams' Recap Home V2): what the catch-up found (its
        // tasks, your mentions, who spoke, why it's recommended), the
        // recordings, the thumbnail's recording, whether you can open the
        // recap, the meeting's files (its notes, stage and chat files).
        "actionItems": list("actionItems"),
        "mentions": list("atMentionEvents"),
        "speakers": list("speakers"),
        "reasons": list("recommendationReasons"),
        "recapFile": rec.map(|r| json!({ "driveId": r["driveId"].as_str().unwrap_or_default(), "itemId": r["driveItemId"].as_str().unwrap_or_default(), "url": r["url"].as_str().unwrap_or_default() })).unwrap_or(Value::Null),
        "recordings": recording_list,
        "thumb": thumb,
        "access": access,
        "attendanceStatus": s("/attendanceStatus"),
        "files": if access == "NoPermission" { Vec::new() } else { meeting_files(m) },
    }))
}

/// A meeting's files for Home's files chip (Teams' worker `le`): its
/// MeetingChat, MeetingStage and Notes resources that have an id, a type
/// and an address, once each.
pub fn meeting_files(m: &Value) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for r in m.get("resources").and_then(Value::as_array).into_iter().flatten() {
        let ty = r.get("type").and_then(Value::as_str).unwrap_or_default();
        if !matches!(ty.to_ascii_lowercase().as_str(), "meetingchat" | "meetingstage" | "notes") {
            continue;
        }
        let g = |k: &str| r.get(k).or_else(|| r.pointer(&format!("/metadata/{k}"))).and_then(Value::as_str).unwrap_or_default().to_string();
        let location = [g("location"), g("objectUrl"), g("shareUrl")].into_iter().find(|s| !s.is_empty()).unwrap_or_default();
        // (The service leaves a note's id empty; Teams then has its
        // mcoResourceId, as seen on winpc.)
        let id = [g("id"), g("mcoResourceId")].into_iter().find(|s| !s.is_empty()).unwrap_or_default();
        if id.is_empty() || location.is_empty() {
            continue;
        }
        let key = [g("fileId"), g("listItemUniqueId"), g("objectUrl"), location.clone(), id.clone()].into_iter().find(|s| !s.is_empty()).unwrap_or_default().to_lowercase();
        if !seen.insert(key) {
            continue;
        }
        let ty = if ty.eq_ignore_ascii_case("notes") { "Notes" } else if ty.eq_ignore_ascii_case("meetingstage") { "MeetingStage" } else if ty.eq_ignore_ascii_case("meetingchat") { "MeetingChat" } else { ty };
        out.push(json!({ "id": id, "type": ty, "location": location, "fileType": g("fileType"), "fileTitle": g("fileTitle"), "fileId": g("fileId"), "webUrl": g("webUrl") }));
    }
    out
}

/// Home's rows of a contents reply as it came (no catch-up merged).
pub fn meetings_from(v: &Value) -> Vec<Value> {
    v.get("value").and_then(Value::as_array).into_iter().flatten().filter_map(row_from).collect()
}

/// A day's threads as Teams keeps them (fetchAllThreadsForDay).
pub fn threads_from(v: &Value) -> Vec<Value> {
    v.get("value").and_then(Value::as_array).cloned().unwrap_or_default()
}

/// Whether Teams lists a day's thread (its meetingRecapList resolver: a
/// calendar event, and a catch-up recommendation or a recording or
/// transcript).
pub fn listed(m: &Value) -> bool {
    let t = &m["threadInfo"];
    !t["eventId"].as_str().unwrap_or_default().is_empty()
        && (t.get("recommendationData").is_some_and(|r| r.is_object())
            || m["resources"].as_array().into_iter().flatten().any(|r| matches!(r["type"].as_str(), Some("Recording" | "TranscriptV2"))))
}

/// Teams' meeting catch-up recommendations for a time range (its
/// getMeetingCatchUpRecommendationsByTimeRange: `POST substrate.office.com/
/// search/api/v1/recommendations?setflight=AiTasksV2,AiNotesV2,
/// AllowResultsWithoutMeeting,PeopleMentionsV2` with an entity request of
/// type MeetingCatchUp, scenario MeetingCatchUp), asked a local day at a
/// time along with the day's artifacts.
pub async fn catch_up_range(start: &str, end: &str) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let body = catch_up_body_range(start, end);
    let id = uuid::Uuid::new_v4().to_string();
    let r = reqwest::Client::new()
        .post("https://substrate.office.com/search/api/v1/recommendations?setflight=AiTasksV2,AiNotesV2,AllowResultsWithoutMeeting,PeopleMentionsV2")
        .bearer_auth(token)
        .header("client-request-id", &id)
        .header("x-ms-correlation-id", &id)
        .json(&body)
        .send()
        .await
        .context("Meeting catch-up")?;
    let status = r.status();
    anyhow::ensure!(status.is_success(), "Meeting catch-up answered {status}");
    Ok(r.json().await.unwrap_or_default())
}

/// The MeetingCatchUp request for a range.
pub fn catch_up_body_range(start: &str, end: &str) -> Value {
    json!({ "EntityRequests": [{ "QueryParameters": [{ "EntityType": "MeetingCatchUp", "StartDateTime": start, "EndDateTime": end }] }], "Scenario": { "Name": "MeetingCatchUp" } })
}

/// The first transcript id (a GUID) in a recommendation's description.
fn first_guid(d: &str) -> Option<String> {
    let b = d.as_bytes();
    (0..b.len().saturating_sub(35)).find_map(|i| {
        let w = &b[i..i + 36];
        let ok = w.iter().enumerate().all(|(j, c)| if matches!(j, 8 | 13 | 18 | 23) { *c == b'-' } else { c.is_ascii_digit() || (b'a'..=b'f').contains(c) });
        ok.then(|| String::from_utf8_lossy(w).into_owned())
    })
}

/// A MeetingCatchUp reply's recommendations as day threads (Teams' reply
/// transform, then its `qb`): the meeting's ids, subject and times, a
/// TranscriptV2 resource when the description names the transcript, and
/// recommendationData with the counts of `PointsOfInterest.ActionItems` and
/// `MentionEvents`.
pub fn recommendation_threads(v: &Value) -> Vec<Value> {
    v.pointer("/EntitySets/0/ResultSets/0/Results").and_then(Value::as_array).into_iter().flatten().map(|r| {
        let s = &r["Source"];
        let g = |p: &str| s.pointer(p).cloned().unwrap_or(Value::Null);
        let st = |p: &str| s.pointer(p).and_then(Value::as_str).unwrap_or_default().to_string();
        let n = |k: &str| s.pointer(&format!("/PointsOfInterest/{k}")).and_then(Value::as_array).map(Vec::len).unwrap_or(0);
        let resources = first_guid(&st("/Description")).map(|t| json!([{
            "type": "TranscriptV2",
            "location": format!("{}/_api/v2.1/drives/{}/items/{}/versions/current/media/transcripts/{t}/streamContent", st("/SitePath"), st("/DriveId"), st("/DriveItemId")),
            "hasPermission": true,
            "metadata": { "startTime": g("/RecordingStartTime"), "endTime": g("/RecordingEndTime"), "driveId": g("/DriveId"), "driveItemId": g("/DriveItemId"),
                          "callId": g("/MeetingRecording/CallId"), "iCalUid": g("/MeetingRecording/ICalUid"), "transcriptId": t },
        }])).unwrap_or(Value::Null);
        json!({
            "threadInfo": {
                "threadId": g("/MeetingRecording/TeamsThreadId"), "iCalUid": g("/MeetingRecording/ICalUid"), "callId": g("/MeetingRecording/CallId"),
                "eventId": g("/MeetingId"), "subject": g("/MeetingSubject"),
                "start": { "dateTime": g("/MeetingStartTime"), "timeZone": "UTC" }, "end": { "dateTime": g("/MeetingEndTime"), "timeZone": "UTC" },
                "organizer": { "emailAddress": { "name": g("/Organizer/DisplayName"), "address": "" }, "objectId": g("/MeetingRecording/OrganizerId") },
                "recommendationData": { "actionItemCount": n("ActionItems"), "mentionEventCount": n("MentionEvents"), "driveId": g("/DriveId"), "driveItemId": g("/DriveItemId"),
                    "url": g("/Url"),
                    "recommendationReasons": s.get("RecommendationsReasonList").and_then(Value::as_array).into_iter().flatten().filter_map(|r| r["Type"].as_str()).map(reason_key).collect::<Vec<_>>(),
                    "actionItems": action_items(s.pointer("/PointsOfInterest/ActionItems")),
                    "atMentionEvents": mention_events(s.pointer("/PointsOfInterest/MentionEvents")),
                    "speakers": s.get("Speakers").and_then(Value::as_array).into_iter().flatten().map(|p| json!({
                        "displayName": p["DisplayName"].as_str().unwrap_or_default(), "objectId": p["ObjectId"].as_str().unwrap_or_default(), "tenantId": p["TenantId"].as_str().unwrap_or_default(),
                    })).collect::<Vec<_>>() },
            },
            "resources": resources,
        })
    }).collect()
}

/// A recommendation reason as Teams' list compares it ("Attended" →
/// ATTENDED, "MissedMeeting" → MISSED_MEETING; seen on winpc 2026-11-23).
fn reason_key(t: &str) -> String {
    let mut out = String::new();
    for (i, c) in t.chars().enumerate() {
        if c.is_ascii_uppercase() && i > 0 && !out.ends_with('_') {
            out.push('_');
        }
        out.push(if c == ' ' || c == '-' { '_' } else { c.to_ascii_uppercase() });
    }
    out
}

/// A recommendation's tasks as Teams keeps them (its `i`: Headline as the
/// title, DisplayCleanContent, OwnerDisplayName as the owner).
fn action_items(v: Option<&Value>) -> Vec<Value> {
    v.and_then(Value::as_array).into_iter().flatten().map(|d| {
        let s = |k: &str| d[k].as_str().unwrap_or_default();
        json!({ "actionItemTitle": s("Headline"), "displayCleanContent": s("DisplayCleanContent"), "ownerName": s("OwnerDisplayName"), "language": s("Language") })
    }).collect()
}

/// A recommendation's mentions of you as Teams keeps them (its `p`): who
/// spoke, when, and the words with your name in them (the Snippet when it
/// has one, the name found in it again).
fn mention_events(v: Option<&Value>) -> Vec<Value> {
    v.and_then(Value::as_array).into_iter().flatten().map(|e| {
        let s = |k: &str| e[k].as_str().unwrap_or_default().to_string();
        let num = |k: &str| e[k].as_i64().or_else(|| e[k].as_str().and_then(|x| x.parse().ok()));
        let mut text = s("UtteranceFromTranscript");
        let mut at = num("MentionOffsetInUtterance").unwrap_or(-1);
        let len = num("NameLength").unwrap_or(-1);
        let chars: Vec<char> = text.chars().collect();
        let ok = len > 0 && !text.is_empty() && at >= 0 && (at as usize) < chars.len();
        if !ok {
            at = -1;
        }
        let snippet = s("Snippet");
        if !snippet.is_empty() {
            if ok {
                let name: String = chars.iter().skip(at as usize).take(len as usize).collect();
                let cap = name.chars().next().map(|c| c.to_uppercase().collect::<String>() + &name[c.len_utf8()..]).unwrap_or_default();
                let found = snippet.find(&name).or_else(|| if name.is_empty() { None } else { snippet.find(&cap) });
                if let Some(b) = found {
                    at = snippet[..b].chars().count() as i64;
                }
            }
            text = snippet;
        }
        let when = if s("EventDateTime").is_empty() { s("EventDateTimeUtc") } else { s("EventDateTime") };
        json!({ "dateTimeUtc": when, "mentionedByUserId": s("SpeakerObjectId"), "mentionedByUserDisplayName": s("SpeakerName"),
                "utteranceContainingTheMention": text, "mentionOffsetInUtterance": at, "nameLength": len, "language": s("Language") })
    }).collect()
}

fn ical_key(m: &Value) -> Option<String> {
    m.pointer("/threadInfo/iCalUid").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_lowercase)
}

fn drive_key(d: Option<&str>, i: Option<&str>) -> Option<String> {
    match (d.filter(|s| !s.is_empty()), i.filter(|s| !s.is_empty())) {
        (Some(d), Some(i)) => Some(format!("{d}:{i}")),
        _ => None,
    }
}

/// One recommendation per meeting (Teams' `Lm`): of several for the same
/// iCalUid, the one whose file is the meeting's recording (the artifacts'
/// thread's, else the first recommendation's), else one with a file.
fn one_per_meeting(recs: Vec<Value>, artifacts: &std::collections::HashMap<String, Value>) -> Vec<Value> {
    let rec_key = |m: &Value| {
        let r = m.pointer("/threadInfo/recommendationData");
        drive_key(r.and_then(|r| r["driveId"].as_str()), r.and_then(|r| r["driveItemId"].as_str()))
    };
    let recordings = |m: &Value| -> std::collections::HashSet<String> {
        m["resources"].as_array().into_iter().flatten()
            .filter(|r| r["type"].as_str().is_some_and(|t| t.eq_ignore_ascii_case("recording")))
            .filter_map(|r| drive_key(r.pointer("/metadata/driveId").and_then(Value::as_str), r.pointer("/metadata/driveItemId").and_then(Value::as_str)))
            .collect()
    };
    let mut order: Vec<String> = Vec::new();
    let mut kept: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
    for n in recs {
        let Some(k) = ical_key(&n) else { continue };
        let Some(r) = kept.get(&k) else {
            order.push(k.clone());
            kept.insert(k, n);
            continue;
        };
        let i = recordings(artifacts.get(&k).unwrap_or(r));
        let (c, l) = (rec_key(r), rec_key(&n));
        let g = c.as_ref().is_some_and(|c| i.contains(c));
        let m = l.as_ref().is_some_and(|l| i.contains(l));
        if !g && (m || (c.is_none() && l.is_some())) {
            kept.insert(k, n);
        }
    }
    order.into_iter().filter_map(|k| kept.remove(&k)).collect()
}

/// A day's artifacts merged with its catch-up recommendations (Teams'
/// `Um`): by iCalUid, a recommendation adds its counts to the meeting's
/// thread, or comes in as a thread of its own; threads without an iCalUid
/// drop out.
pub fn merge_day(recs: Vec<Value>, artifacts: Vec<Value>) -> Vec<Value> {
    let mut order: Vec<String> = Vec::new();
    let mut t: std::collections::HashMap<String, Value> = std::collections::HashMap::new();
    for a in artifacts {
        if let Some(k) = ical_key(&a) {
            if !t.contains_key(&k) {
                order.push(k.clone());
            }
            t.insert(k, a);
        }
    }
    for n in one_per_meeting(recs, &t) {
        let Some(k) = ical_key(&n) else { continue };
        match t.get_mut(&k) {
            Some(a) => a["threadInfo"]["recommendationData"] = n["threadInfo"]["recommendationData"].clone(),
            None => {
                order.push(k.clone());
                t.insert(k, n);
            }
        }
    }
    order.into_iter().filter_map(|k| t.remove(&k)).collect()
}

/// A day's listed rows (Teams' getMeetingRecapByDay, merged, then its
/// resolver's filter).
pub fn day_rows(contents: Option<&Value>, catch_up: Option<&Value>) -> Vec<Value> {
    let artifacts = contents.map(threads_from).unwrap_or_default();
    let recs = catch_up.map(recommendation_threads).unwrap_or_default();
    merge_day(recs, artifacts).iter().filter(|m| listed(m)).filter_map(row_from).collect()
}

/// Home's and Generate audio recap's meetings for `days` local days back
/// from `from_days_ago` (newest first), the days asked in parallel. Each
/// day as Teams' getMeetingRecapByDay: the day's meeting artifacts and its
/// catch-up recommendations, merged. A meeting across midnight comes on
/// both of its days; the list keeps one (by eventId, MeetingRecapsView's
/// `meetingList`).
pub async fn meetings(region: &str, from_days_ago: i64, days: i64) -> Result<Value> {
    use chrono::{Local, TimeZone};
    let today = Local::now().date_naive();
    let mut asks = Vec::new();
    for i in from_days_ago..from_days_ago + days {
        let day = today - chrono::Duration::days(i);
        let start = Local.from_local_datetime(&day.and_hms_opt(0, 0, 0).unwrap_or_default()).single().map(|d| d.with_timezone(&chrono::Utc));
        let end = Local.from_local_datetime(&day.and_hms_milli_opt(23, 59, 59, 999).unwrap_or_default()).single().map(|d| d.with_timezone(&chrono::Utc));
        if let (Some(a), Some(b)) = (start, end) {
            asks.push((day, a, b));
        }
    }
    let f = |t: chrono::DateTime<chrono::Utc>| t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    // At most 8 days at a time (Teams' fetchAndCacheArtifactsByUserRange).
    use futures::StreamExt;
    let owned: Vec<(String, String, String)> = asks.iter().map(|(_, a, b)| (format!("{}/{}", base(region), day_query(*a, *b)), f(*a), f(*b))).collect();
    let replies: Vec<(Result<Value>, Result<Value>)> = futures::stream::iter(owned)
        .map(|(url, a, b)| async move { futures::join!(get(&url), catch_up_range(&a, &b)) })
        .buffered(8)
        .collect()
        .await;
    let mut out = Vec::new();
    for ((day, _, _), (contents, catch_up)) in asks.iter().zip(replies) {
        let list = day_rows(contents.as_ref().ok(), catch_up.as_ref().ok());
        if !list.is_empty() {
            out.push(json!({ "day": day.format("%Y-%m-%d").to_string(), "meetings": list }));
        }
    }
    Ok(json!({ "days": out, "next": from_days_ago + days }))
}

// ---------------------------------------------------------------------
// A meeting's recap opened from its recap card (Teams' intelligent recap
// window, measured on winpc 2026-11-20 in "Event group: OST TEST 217 town
// hall 2"), and its sharing.

/// What a recap is opened and shared with (Teams' recapOptions).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct RecapRef {
    /// The meeting's own thread (`19:meeting_…`), not a backroom chat's.
    #[serde(default)]
    pub thread_id: String,
    #[serde(default)]
    pub ical_uid: String,
    /// The organizer's object id.
    #[serde(default)]
    pub organizer_id: String,
    #[serde(default)]
    pub tenant_id: String,
    #[serde(default)]
    pub call_id: String,
    #[serde(default)]
    pub drive_id: String,
    #[serde(default)]
    pub item_id: String,
    /// The recording's sharing address (`…/:v:/p/{owner}/{token}`).
    #[serde(default)]
    pub file_url: String,
    #[serde(default)]
    pub subject: String,
    /// The meeting's start and end, UTC milliseconds.
    #[serde(default)]
    pub start_ms: i64,
    #[serde(default)]
    pub end_ms: i64,
    /// "RecordingAndTranscript", "Recording" or "Transcript".
    #[serde(default)]
    pub recap_type: String,
    /// Teams' recap id (selectedRecap.recapId): `canonical_recap_id` of the
    /// recording's file, or of the transcript's when the meeting has no
    /// recording. The catch-up service's EntityId and Copilot's vroomId.
    #[serde(default)]
    pub recap_id: String,
}

impl RecapRef {
    /// The recap id, made from the recording's file when not known yet.
    pub fn recap_id(&self) -> String {
        if !self.recap_id.is_empty() {
            self.recap_id.clone()
        } else {
            canonical_recap_id(&self.drive_id, &self.item_id)
        }
    }
}

/// Teams' canonical recap id (597421 `Tv`, used when its recap card opens
/// a recap): `SPO_{base64url("{site},{web},{library}")}_{itemId}`, the three
/// GUIDs read from the `b!` drive id (16 bytes each, in .NET's byte order),
/// base64url without padding; "" without a drive item.
pub fn canonical_recap_id(drive_id: &str, item_id: &str) -> String {
    use base64::Engine as _;
    if drive_id.is_empty() || item_id.is_empty() {
        return String::new();
    }
    if drive_id == "null" || item_id == "null" {
        return "null".into();
    }
    let url = base64::engine::general_purpose::URL_SAFE_NO_PAD;
    let bytes = url.decode(drive_id.strip_prefix("b!").unwrap_or(drive_id).trim_end_matches('=')).unwrap_or_default();
    let guid = |b: &[u8]| -> String {
        if b.len() < 16 {
            return String::new();
        }
        let h = |i: usize| format!("{:02x}", b[i]);
        format!(
            "{}{}{}{}-{}{}-{}{}-{}{}-{}",
            h(3), h(2), h(1), h(0), h(5), h(4), h(7), h(6), h(8), h(9),
            (10..16).map(h).collect::<String>()
        )
    };
    let part = |i: usize| guid(bytes.get(i * 16..i * 16 + 16).unwrap_or_default());
    let ids = format!("{},{},{}", part(0), part(1), part(2));
    format!("SPO_{}_{item_id}", url.encode(ids))
}

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// Teams' recap link (Copy link, and the share message's): its
/// `l/meetingrecap` deep link with the recording and the meeting, subType
/// RecapSharingLink_RecapChiclet.
pub fn recap_link(r: &RecapRef) -> String {
    format!(
        "https://teams.microsoft.com/l/meetingrecap?driveId={}&driveItemId={}&sitePath={}&fileUrl={}&iCalUid={}&threadId={}&organizerId={}&tenantId={}&callId={}&threadType=Meeting&meetingType=Scheduled&subType=RecapSharingLink_RecapChiclet&recapType={}",
        enc(&r.drive_id),
        enc(&r.item_id),
        enc(&r.file_url),
        enc(&r.file_url),
        enc(&r.ical_uid),
        enc(&r.thread_id),
        enc(&r.organizer_id),
        enc(&r.tenant_id),
        enc(&r.call_id),
        enc(if r.recap_type.is_empty() { "RecordingAndTranscript" } else { &r.recap_type }),
    )
}

/// What the meeting artifacts service tells about a recap's meeting.
#[derive(Debug, Default, PartialEq)]
pub struct MeetingContents {
    pub thread: String,
    pub organizer: String,
    pub file_url: String,
    /// The latest TranscriptV2's file (drive id, item id), as Teams keeps
    /// the last one.
    pub transcript: Option<(String, String)>,
    /// Every TranscriptV2 (what an audio recap is made from).
    pub transcripts: Vec<super::podcast::Transcript>,
    /// The organizer's name.
    pub organizer_name: String,
}

/// The meeting's own thread, organizer, recording address and transcript
/// file for a recap card, from the meeting artifacts service's contents
/// for the meeting's day (Teams reads them from its recap data): the entry
/// with the same iCalUid, or whose resources name the recording.
pub fn match_contents(v: &Value, ical_uid: &str, item_id: &str) -> Option<MeetingContents> {
    v.get("value").and_then(Value::as_array).into_iter().flatten().find_map(|m| {
        let t = m.get("threadInfo")?;
        let ical = t.get("iCalUid").and_then(Value::as_str).unwrap_or_default();
        let text = m.to_string();
        let hit = (!ical_uid.is_empty() && ical.eq_ignore_ascii_case(ical_uid)) || (!item_id.is_empty() && text.contains(item_id));
        if !hit {
            return None;
        }
        let thread = t.get("threadId").and_then(Value::as_str).unwrap_or_default().to_string();
        let org = t
            .pointer("/organizer/id")
            .or_else(|| t.pointer("/organizerId"))
            .or_else(|| t.pointer("/organizer/user/id"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .split('@')
            .next()
            .unwrap_or_default()
            .to_string();
        let file = m
            .get("resources")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|res| !item_id.is_empty() && res.to_string().contains(item_id))
            .find_map(|res| ["fileUrl", "webUrl", "location", "url"].iter().find_map(|k| res.pointer(&format!("/{k}")).and_then(Value::as_str)).map(str::to_string))
            .unwrap_or_default();
        let transcript = m
            .get("resources")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|res| res.get("type").and_then(Value::as_str) == Some("TranscriptV2"))
            .filter_map(|res| {
                let s = |k: &str| res.get(k).or_else(|| res.pointer(&format!("/metadata/{k}"))).and_then(Value::as_str).unwrap_or_default().to_string();
                let (d, i) = (s("driveId"), s("driveItemId"));
                (!d.is_empty() && !i.is_empty()).then_some((d, i))
            })
            .next_back();
        let transcripts = m.get("resources").and_then(Value::as_array).into_iter().flatten().filter_map(super::podcast::transcript_from).collect();
        let organizer_name = t
            .pointer("/organizer/emailAddress/name")
            .or_else(|| t.pointer("/organizer/user/displayName"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        Some(MeetingContents { thread, organizer: org, file_url: file, transcript, transcripts, organizer_name })
    })
}

/// Fill a recap's meeting thread, organizer and recording address from
/// the meeting artifacts service. A meeting with a transcript and no
/// recording gets the transcript's file as its recap's file (Teams'
/// ODSPTranscript recap: the "Meeting Transcript.mp4" the transcript
/// lives in), which Open in Clipchamp and the transcript read.
pub async fn resolve(region: &str, r: &mut RecapRef) -> Result<Value> {
    resolve_contents(region, r).await.map(|(v, _)| v)
}

/// `resolve`, with what the service said about the meeting.
pub async fn resolve_contents(region: &str, r: &mut RecapRef) -> Result<(Value, Option<MeetingContents>)> {
    let day = |ms: i64| chrono::DateTime::from_timestamp_millis(ms).unwrap_or_default();
    let (a, b) = (day(r.start_ms - 86_400_000), day(r.end_ms.max(r.start_ms) + 86_400_000));
    let v = get(&format!("{}/{}", base(region), day_query(a, b))).await?;
    let found = match_contents(&v, &r.ical_uid, &r.item_id);
    if let Some(c) = &found {
        let c = MeetingContents { transcript: c.transcript.clone(), thread: c.thread.clone(), organizer: c.organizer.clone(), file_url: c.file_url.clone(), ..Default::default() };
        if r.thread_id.is_empty() || !c.thread.is_empty() {
            r.thread_id = c.thread;
        }
        if !c.organizer.is_empty() {
            r.organizer_id = c.organizer;
        }
        if !c.file_url.is_empty() && r.file_url.is_empty() {
            r.file_url = c.file_url;
        }
        // A meeting with a transcript and no recording: Teams' recap is the
        // transcript's file.
        if r.item_id.is_empty()
            && let Some((d, i)) = c.transcript
        {
            if r.recap_id.is_empty() {
                r.recap_id = canonical_recap_id(&d, &i);
            }
            r.drive_id = d;
            r.item_id = i;
            r.recap_type = "ODSPTranscript".into();
        }
    }
    if r.recap_id.is_empty() {
        r.recap_id = canonical_recap_id(&r.drive_id, &r.item_id);
    }
    Ok((v, found))
}

/// Whether the recap has a recording to play (Teams shows its player and
/// the Speakers / Topics / Chapters card only then).
pub fn has_recording(r: &RecapRef) -> bool {
    !matches!(r.recap_type.as_str(), "Transcript" | "ODSPTranscript") && !r.item_id.is_empty()
}

/// Share recap access (Teams' MeetingRecapSharingDialog, Give access):
/// `POST {mcps}/recapSharing {threadId, iCalUid, messageId: "",
/// organizerId: "{oid}@{tid}", driveId, driveItemId, recapSharingToList:
/// ["{oid}@{tid}", …]}`; the people it gave access to.
pub async fn share_access(region: &str, r: &RecapRef, people_oids: &[String]) -> Result<Vec<String>> {
    let tid = &r.tenant_id;
    let body = json!({
        "threadId": r.thread_id,
        "iCalUid": r.ical_uid,
        "messageId": "",
        "organizerId": format!("{}@{tid}", r.organizer_id),
        "driveId": r.drive_id,
        "driveItemId": r.item_id,
        "recapSharingToList": people_oids.iter().map(|o| format!("{o}@{tid}")).collect::<Vec<_>>(),
    });
    let token = crate::auth::oauth::access_token_for(&format!("{}/.default", super::meeting_notes::RESOURCE)).await?;
    let resp = reqwest::Client::new()
        .post(format!("{}/recapSharing", base(region)))
        .bearer_auth(token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .json(&body)
        .send()
        .await
        .context("The meeting artifacts service")?;
    let status = resp.status();
    anyhow::ensure!(status.is_success(), "The meeting artifacts service answered {status}");
    let v: Value = resp.json().await.unwrap_or_default();
    Ok(v.get("recapSharingValidList")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|x| x.as_str().map(|s| s.split('@').next().unwrap_or_default().to_string()))
        .collect())
}

/// "Notify them in chat": the message Teams sends each person (a 1:1
/// chat), the recap link as a MeetingRecap hyperlink titled "Recap:
/// {title} {Weekday, Month d} | Meeting | Microsoft Teams", and its two
/// `links` entries. `day` is the meeting's date as Teams writes it
/// ("Wednesday, November 18") and `when` its time ("Wednesday, November
/// 18 · 8:40 PM - 9:40 PM").
pub fn share_message(r: &RecapRef, day: &str, when: &str) -> (String, String) {
    let link = recap_link(r);
    let e = super::messages::escape;
    // In Teams' key order (version, kind, title, start, end).
    let props = format!(
        "{{\"version\":1,\"kind\":\"meetingRecap\",\"meetingTitle\":{},\"meetingStartTimeMs\":\"{}\",\"meetingEndTimeMs\":\"{}\"}}",
        Value::String(r.subject.clone()),
        r.start_ms,
        r.end_ms
    );
    let content = format!(
        "\n    <div itemprop=\"teams-copy-link\"><a href=\"{l}\" title=\"{l}\" data-origin-known=\"true\" itemtype=\"http://schema.skype.com/HyperLink/MeetingRecap\" data-itemprops=\"{p}\">Recap: {t} {d} | Meeting | Microsoft Teams</a></div>",
        l = e(&link),
        p = e(&props),
        t = e(&r.subject),
        d = e(day),
    );
    let links = json!([
        { "@type": "http://schema.skype.com/HyperLink", "itemid": "0", "url": link, "previewenabled": true,
          "preview": { "previewurl": null, "previewmeta": null, "title": r.subject, "description": when } },
        { "@type": "http://schema.skype.com/HyperLink",
          "recapSharingLinkMeta": { "meetingEndTimeMs": r.end_ms.to_string(), "meetingStartTimeMs": r.start_ms.to_string(), "meetingTitle": r.subject, "version": 1 },
          "url": link },
    ]);
    (content, links.to_string())
}

/// The recording's player: OneDrive's own video player for the file (the
/// Stream player Teams embeds), its embeddable address.
pub async fn player_url(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<String> {
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c));
    anyhow::ensure!(ok(drive_id) && ok(item_id), "Not a recording");
    let v: Value = client.graph_post(&format!("/drives/{drive_id}/items/{item_id}/preview"), &json!({})).await?.json().await?;
    let url = v.get("getUrl").and_then(Value::as_str).context("No player for the recording")?;
    anyhow::ensure!(url.starts_with("https://"), "No player for the recording");
    Ok(url.to_string())
}

/// The recording's transcript as the Stream transcript plug-in reads it
/// (`{site}/_api/v2.1/drives/{d}/items/{i}/media/transcripts`, then the
/// first one's `streamContent?format=json`): its entries ({speaker, text,
/// start}); empty when it has none (Teams: "No transcript available").
pub async fn transcript(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<Vec<Value>> {
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c));
    anyhow::ensure!(ok(drive_id) && ok(item_id), "Not a recording");
    let item: Value = client.graph_get(&format!("/drives/{drive_id}/items/{item_id}?$select=id,webUrl")).await?.json().await?;
    let web = item.get("webUrl").and_then(Value::as_str).unwrap_or_default();
    let host = url::Url::parse(web).ok().and_then(|u| u.host_str().map(str::to_string)).context("The recording's site")?;
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "The recording's site");
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let http = reqwest::Client::new();
    let list: Value = http
        .get(format!("https://{host}/_api/v2.1/drives/{drive_id}/items/{item_id}/media/transcripts"))
        .bearer_auth(&token)
        .send()
        .await?
        .json()
        .await
        .unwrap_or_default();
    let Some(id) = list.pointer("/value/0/id").and_then(Value::as_str) else { return Ok(Vec::new()) };
    let content: Value = http
        .get(format!("https://{host}/_api/v2.1/drives/{drive_id}/items/{item_id}/media/transcripts/{}/streamContent?format=json", enc(id)))
        .bearer_auth(&token)
        .send()
        .await?
        .json()
        .await
        .unwrap_or_default();
    Ok(content
        .get("entries")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|e| {
            let s = |k: &str| e.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
            json!({ "speaker": s("speakerDisplayName"), "text": s("text"), "start": s("startOffset") })
        })
        .collect())
}

// ---------------------------------------------------------------------
// The recap window's extras (Teams 26304, module 991291 and the shared
// worker's recap resolvers).

/// Teams' client type for recap links on desktop (MeetingRecap.
/// clientTypeForRecap: "TEAMS-ELECTRON" on the desktop platforms).
pub const CLIENT_TYPE: &str = "TEAMS-ELECTRON";

/// "Open in Clipchamp" (Teams' label for "Watch in browser"): the
/// recording's web page with `web=1` and Teams' referrer
/// (RecapOpenInStreamButton.view), opened in the browser.
pub fn clipchamp_url(web_url: &str) -> String {
    let sep = if web_url.contains('?') { '&' } else { '?' };
    format!("{web_url}{sep}web=1&referrer=Teams.{CLIENT_TYPE}&referrerScenario=RecapOpenInStreamButton.view")
}

/// The recording's file facts the window needs: its web page, its site
/// and server-relative path (for Manage's expiration), whether you may
/// download and edit it, and its expiration (UTC, "" when none).
pub async fn file_info(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<Value> {
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c));
    anyhow::ensure!(ok(drive_id) && ok(item_id), "Not a recording");
    let item: Value = client
        .graph_get(&format!("/drives/{drive_id}/items/{item_id}?$select=id,name,webUrl,parentReference,sharepointIds,file"))
        .await?
        .json()
        .await?;
    let web = item.get("webUrl").and_then(Value::as_str).unwrap_or_default().to_string();
    let site = item.pointer("/sharepointIds/siteUrl").and_then(Value::as_str).unwrap_or_default().to_string();
    let host = url::Url::parse(&web).ok().and_then(|u| u.host_str().map(str::to_string)).unwrap_or_default();
    let path = url::Url::parse(&web).ok().map(|u| percent_decode(u.path())).unwrap_or_default();
    // The file's expiration and your rights, as ODSP's v2.1 item gives them.
    let mut expiration = String::new();
    let mut can_edit = false;
    if host.ends_with(".sharepoint.com") {
        let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
        let v: Value = reqwest::Client::new()
            .get(format!("https://{host}/_api/v2.1/drives/{drive_id}/items/{item_id}?$select=id,expiration,permissions&$expand=permissions"))
            .bearer_auth(token)
            .send()
            .await?
            .json()
            .await
            .unwrap_or_default();
        expiration = v.pointer("/expiration/expirationDateTime").and_then(Value::as_str).unwrap_or_default().to_string();
        can_edit = v.get("permissions").and_then(Value::as_array).into_iter().flatten().any(|p| {
            p.get("roles").and_then(Value::as_array).into_iter().flatten().any(|r| matches!(r.as_str(), Some("owner") | Some("write")))
        });
    }
    // A recording in your own OneDrive is yours to change (Teams'
    // accessViewpoint.canEdit).
    if !can_edit
        && let Ok(r) = client.graph_get("/me/drive?$select=webUrl").await
        && let Ok(d) = r.json::<Value>().await
        && let Some(mine) = d.get("webUrl").and_then(Value::as_str)
    {
        can_edit = !mine.is_empty() && web.starts_with(mine);
    }
    Ok(json!({ "webUrl": web, "site": site, "path": path, "name": item.get("name").cloned().unwrap_or(Value::Null),
               "expiration": expiration, "canEdit": can_edit }))
}

fn percent_decode(s: &str) -> String {
    url::form_urlencoded::parse(format!("x={}", s.replace('+', "%2B")).as_bytes())
        .next()
        .map(|(_, v)| v.into_owned())
        .unwrap_or_default()
}

/// Days left before the recording expires (rounded up), -1 for none.
pub fn remaining_days(expiration: &str, now: chrono::DateTime<chrono::Utc>) -> i64 {
    match chrono::DateTime::parse_from_rfc3339(expiration) {
        Ok(t) => ((t.with_timezone(&chrono::Utc) - now).num_seconds() as f64 / 86_400.0).ceil().max(0.0) as i64,
        Err(_) => -1,
    }
}

/// Manage ▸ Expires in ▸ Extend by 60 days / Remove expiration: Teams'
/// `POST {site}/_api/web/GetFileByServerRelativePath(DecodedUrl=@url)/
/// SetExpirationDate?@url='{path}'` with `{"expirationDate": ISO|null}`.
pub async fn set_expiration(site: &str, path: &str, date: Option<&str>) -> Result<()> {
    let host = url::Url::parse(site).ok().and_then(|u| u.host_str().map(str::to_string)).context("The recording's site")?;
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "The recording's site");
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let quoted = path.replace('\'', "''");
    let url = format!("{}/_api/web/GetFileByServerRelativePath(DecodedUrl=@url)/SetExpirationDate?@url='{}'", site.trim_end_matches('/'), enc(&quoted));
    let r = reqwest::Client::new()
        .post(url)
        .bearer_auth(token)
        .header("accept", "application/json;odata=nometadata")
        .json(&json!({ "expirationDate": date }))
        .send()
        .await?;
    let status = r.status();
    anyhow::ensure!(status.is_success(), "SharePoint answered {status}");
    Ok(())
}

/// The catch-up request Teams' AI notes and Mentions read (substrate
/// recommendations, scenario MeetingCatchUp.MeetingRecap).
pub fn catch_up_body(entity_id: &str) -> Value {
    json!({
        "EntityRequests": [{ "Context": { "EntityId": entity_id }, "QueryParameters": [{ "EntityType": "MeetingCatchUp" }] }],
        "Scenario": { "Name": "MeetingCatchUp.MeetingRecap" },
    })
}

/// A catch-up answer's Mentions: {count, items [{speaker, speakerId, text,
/// offset (ms from the recording's start), at, nameStart, nameLength}]}.
pub fn mentions_from(v: &Value) -> Value {
    let src = v.pointer("/EntitySets/0/ResultSets/0/Results/0/Source").cloned().unwrap_or_default();
    let events = src.pointer("/PointsOfInterest/MentionEvents").and_then(Value::as_array).cloned().unwrap_or_default();
    let items: Vec<Value> = events
        .iter()
        .map(|e| {
            let s = |k: &str| e.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
            let text = if s("UtteranceFromTranscript").is_empty() { s("Snippet") } else { s("UtteranceFromTranscript") };
            json!({
                "speaker": s("SpeakerName"), "speakerId": s("SpeakerObjectId"), "text": text, "at": s("EventDateTime"),
                "nameStart": e.get("MentionOffsetInUtterance").and_then(Value::as_i64).unwrap_or(-1),
                "nameLength": e.get("NameLength").and_then(Value::as_i64).unwrap_or(0),
            })
        })
        .collect();
    let count = src.pointer("/PointsOfInterest/UserMentionCount").and_then(Value::as_i64).unwrap_or(items.len() as i64);
    json!({ "count": count, "items": items, "found": !src.is_null() })
}

/// Mentions (Teams' recap Mentions pill): the catch-up call's mentions.
pub async fn mentions(oid: &str, tid: &str, entity_id: &str) -> Result<Value> {
    Ok(mentions_from(&catch_up(oid, tid, entity_id).await?))
}

/// The catch-up call (substrate recommendations, MeetingCatchUp.MeetingRecap)
/// with your anchor mailbox, for the recap id.
pub async fn catch_up(oid: &str, tid: &str, entity_id: &str) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let r = reqwest::Client::new()
        // (Teams 26304 on winpc sends the V3 notes and tasks flights.)
        .post("https://substrate.office.com/search/api/v1/recommendations/?&setflight=AiTasksV3,AiNotesV3,PeopleMentionsV2")
        .bearer_auth(token)
        .header("X-AnchorMailbox", format!("Oid:{oid}@{tid}"))
        .header("client-request-id", uuid::Uuid::new_v4().to_string())
        .json(&catch_up_body(entity_id))
        .send()
        .await?;
    let status = r.status();
    anyhow::ensure!(status.is_success(), "The catch-up service answered {status}");
    Ok(r.json().await.unwrap_or_default())
}

/// Custom summary's built-in templates (Teams' 209818), in its order:
/// (key, title, description); Project update third unless Teams hides it.
pub const SUMMARY_TEMPLATES: [(&str, &str, &str); 3] = [
    ("SpeakersBasedRecap", "Speaker summary", "Main points by speaker"),
    ("ExecutiveSummary", "Executive report", "Overview and key area updates"),
    ("ProjectSummary", "Project update", "Accomplishments, risks, and action items"),
];

/// The prompt Teams sends for a template you wrote (633679's `rP`, the
/// recap instructions): a saved template's text, or Create template's
/// Preview with the description typed (trimmed), in place of
/// {$USERINPUT$} (a literal replace, as Teams' `String.replace`).
pub fn saved_template_prompt(template: &str) -> String {
    include_str!("recap_saved_template_prompt.txt").replacen("{$USERINPUT$}", template, 1)
}

/// The message for a built-in template (Teams 855033 with ECS
/// enableMeetingRecapCustomizedNotesCatalystEndpoint): Speaker summary and
/// Executive report send their recap prompts (633679 `OM` / `TJ`) with
/// {$LANGUAGE_INSTRUCTION$} replaced by the meeting summary's language (""
/// when it has none); other keys go as they are.
pub fn catalyst_message(key: &str, language: &str) -> String {
    let prompt = match key {
        "SpeakersBasedRecap" => include_str!("recap_speaker_summary_prompt.txt"),
        "ExecutiveSummary" => include_str!("recap_executive_summary_prompt.txt"),
        _ => return key.to_string(),
    };
    prompt.replace("{$LANGUAGE_INSTRUCTION$}", language)
}

/// The variants Teams' Catalyst hub address carries (its
/// constructCatalystHubUrl, Teams 26304).
const CATALYST_VARIANTS: &str = "EnableMcpServerWidgets,feature.EnableMcpServerWidgets,feature.EnableLuForChatCIQ,feature.enableChatCIQPlugin,EnableRequestPlugins,feature.EnableSensitivityLabels,EnableUnsupportedUrlDetector,MetricsSummaryEnabled,feature.EnableMessageExtensionAnnotations,3S.ProcessMECardTitleForEntityAnotation,feature.IsCustomEngineCopilotEnabled,feature.bizchatfluxv3,feature.IsOpenApiAnnotationsEnabled,feature.EnableConnectorAnnotations,feature.turnOnWorkTabRecommendation,WorkTabNudgeAddData,WorkTabNudgeAddSources,feature.turnOnDARecommendation,feature.IsStreamingModeInChatRequestEnabled,IncludeSourceAttributionsConcise,SkipPublishEmptyMessage,feature.EnableDeduplicatingSourceAttributions,feature.IsCitationsReferencesOutputEnabled,feature.enableDeltaStreamingForReferences,feature.enableIncludeReferencesInDeltaResponse,feature.enablereferencesforagents,Enable3PActionProgressMessages,feature.enableClientWebRtc,feature.EnableMeetingRecapOfSeriesMeetingWithCiq,feature.EnableReferencesListCompleteSignal,feature.StorageMessageSplitDisabled,feature.EnableCuaTakeControlApi,feature.isExternalEmailEnabled,feature.isExcludedEmailEnabled,feature.disabledisallowedmsgs,feature.enableCitationsForSynthesisData,feature.enableGenerateGraphicArtOptionsSet,cdximagen,feature.EnableClientFileURLSupport,feature.ConversationalScheduledPromptsAlwaysOnEnabled,feature.EnableCuaTakeControlApi,feature.EnableUpdatedUXForConfirmationDialog,cdxgrounding_api_v2_rich_web_answers_reference_bottom_force,cdxgapi_rwa_segments_magazine,feature.EnableDesignEditorImageGrounding,feature.EnablePersonalization,feature.EnableQueryOverrideConversationStorageTypes";

/// Custom summary's hub (Teams' recap custom summary service, streamed
/// over SignalR): `wss://substrate.office.com/m365Copilot/Chathub/{oid}@{tid}`
/// with the token and Teams' query; WebSockets without negotiation.
pub fn catalyst_hub_url(client_request_id: &str, token: &str, oid: &str, tid: &str) -> String {
    let user = if oid.is_empty() || tid.is_empty() { String::new() } else { format!("/{oid}@{tid}") };
    let q: String = url::form_urlencoded::Serializer::new(String::new())
        .append_pair("ClientRequestId", client_request_id)
        .append_pair("access_token", token)
        .append_pair("variants", CATALYST_VARIANTS)
        .append_pair("source", "teamshub")
        .append_pair("scenario", "TeamsMeetingRecapCopilot")
        .append_pair("product", "Teams")
        .append_pair("agentHost", "BizChat.FullScreen")
        .append_pair("licenseType", "Premium")
        .append_pair("agent", "work")
        .append_pair("isproactivechat", "1")
        .finish();
    format!("wss://substrate.office.com/m365Copilot/Chathub{user}?{q}")
}

/// Where the request is made from (Teams' locationInfo).
pub struct Place {
    /// Minutes behind UTC (JavaScript's getTimezoneOffset).
    pub offset_minutes: i64,
    pub zone: String,
}

impl Place {
    pub fn here() -> Place {
        Place { offset_minutes: -(chrono::Local::now().offset().local_minus_utc() as i64) / 60, zone: super::compose_copilot::iana_timezone() }
    }
}

/// Custom summary's chat request (Teams' constructCatalystCustomSummaryRequest):
/// the message annotated with the meeting (callId, threadId, organizerId,
/// vroomId = the recap id, iCalUID; canvasType RecapCall without an
/// iCalUID). `ical_uid` is "" with ECS enableCustomSummaryCurrentCallGrounding
/// (Teams' current-call grounding), else the meeting's in capitals.
pub fn catalyst_request(r: &RecapRef, recap_id: &str, ical_uid: &str, message: &str, language: &str, correlation: &str, session: &str, place: &Place) -> Value {
    let os = std::env::consts::OS;
    json!({
        "source": "teamshub",
        "clientCorrelationId": correlation,
        "sessionId": session,
        "optionsSets": [],
        "spokenTextMode": "None",
        "options": {},
        "allowedMessageTypes": ["Chat", "ConfirmationCard", "InternalLoaderMessage", "InternalSearchQuery", "Progress", "SemanticSerp", "Suggestion"],
        "sliceIds": [],
        "threadLevelGptId": {},
        "traceId": correlation,
        "isStartOfSession": false,
        "streamingMode": "ConciseWithPadding",
        "clientInfo": { "clientPlatform": os, "clientAppName": "Teams", "clientEntrypoint": "Recap", "clientSessionId": session,
                        "ProductCategory": "Meeting", "clientAppType": "Web", "deviceOS": os, "deviceType": "Desktop" },
        "message": {
            "author": "user", "inputMethod": "Keyboard", "text": message,
            "entityAnnotationTypes": ["People", "File", "Event", "External", "ExternalMessageExtension", "Email", "TeamsMessage"],
            "requestId": correlation,
            "locationInfo": { "timeZoneOffset": place.offset_minutes, "timeZone": place.zone },
            "locale": language,
            "conversationAction": "Create",
            "messageType": "Chat",
            "messageAnnotations": [{
                "id": r.call_id, "text": message, "messageAnnotationSource": "ClientAnnotated",
                "messageAnnotationMetadata": { "@type": "TeamsMeeting", "callId": r.call_id, "canvasType": if ical_uid.is_empty() { "RecapCall" } else { "Recap" },
                    "threadId": r.thread_id, "organizerId": r.organizer_id, "channelMessageId": "", "groupId": "", "vroomId": recap_id, "iCalUID": ical_uid },
                "messageAnnotationType": "TeamsMeeting",
            }],
            "experienceType": "Prompts",
            "adaptiveCards": [],
            "clientPreferences": {},
        },
        "plugins": [{ "Id": "BingWebSearch", "Source": "BuiltIn" }],
        "tone": "Chat",
        "renderReferencesBehindEOS": true,
        "copilotReferenceId": uuid::Uuid::new_v4().simple().to_string(),
        "disconnectBehavior": "continue",
    })
}

/// SignalR's JSON frames (each ends with U+001E).
pub fn hub_frames(text: &str) -> Vec<Value> {
    text.split('\u{1e}').filter(|f| !f.trim().is_empty()).filter_map(|f| serde_json::from_str(f).ok()).collect()
}

/// A custom summary as its hub's "update" calls build it (Teams'
/// requestCatalystCustomSummary): "Full" updates replace the text with the
/// last bot message's, "Delta" ones add `writeAtCursor`; an `item.result.
/// error` marks it failed.
#[derive(Debug, Default)]
pub struct HubSummary {
    pub text: String,
    pub error: Option<String>,
    pub done: bool,
}

impl HubSummary {
    pub fn frame(&mut self, f: &Value) {
        match f.get("type").and_then(Value::as_i64) {
            Some(1) if f.get("target").and_then(Value::as_str) == Some("update") => {
                for u in f.get("arguments").and_then(Value::as_array).into_iter().flatten() {
                    self.update(u);
                }
            }
            Some(2) => {
                if let Some(e) = f.pointer("/item/result/error") {
                    self.error = Some(f.pointer("/item/result/value").and_then(Value::as_str).unwrap_or(e.as_str().unwrap_or("error")).to_string());
                }
            }
            Some(3) => {
                if let Some(e) = f.get("error").and_then(Value::as_str) {
                    self.error = Some(e.to_string());
                }
                self.done = true;
            }
            Some(7) => {
                self.error.get_or_insert_with(|| f.get("error").and_then(Value::as_str).unwrap_or("closed").to_string());
                self.done = true;
            }
            _ => {}
        }
    }
    fn update(&mut self, u: &Value) {
        if let Some(e) = u.pointer("/item/result/error") {
            self.error = Some(u.pointer("/item/result/value").and_then(Value::as_str).unwrap_or(e.as_str().unwrap_or("error")).to_string());
        }
        match u.get("streamingMode").and_then(Value::as_str) {
            Some("Full") => {
                if let Some(last) = u.get("messages").and_then(Value::as_array).and_then(|m| m.last())
                    && last.get("author").and_then(Value::as_str) == Some("bot")
                    && let Some(t) = last.get("text").and_then(Value::as_str)
                    && !t.is_empty()
                {
                    self.text = t.to_string();
                }
            }
            Some("Delta") => {
                if let Some(t) = u.get("writeAtCursor").and_then(Value::as_str) {
                    self.text.push_str(t);
                }
            }
            _ => {}
        }
    }
    /// The finished text: `[n](…)` reference links dropped, then Teams'
    /// clean-up.
    pub fn summary(&self) -> String {
        use std::sync::LazyLock;
        static REFS: LazyLock<Option<regex::Regex>> = LazyLock::new(|| regex::Regex::new(r"\[(\d+)\]\([^)]+\)").ok());
        let t = match &*REFS {
            Some(r) => r.replace_all(&self.text, "").into_owned(),
            None => self.text.clone(),
        };
        clean_summary(&t).trim().to_string()
    }
}

/// Teams' clean-up of a custom summary (855033): the `<RESPONSE>` lead,
/// `{utt_id=…}` marks, the private-use (U+E200–U+E2FF) citation spans and
/// the links made of them, `<cite>`, `【n†…】`, `[^n^]`, the `turnNsearchN`
/// and `cite…turnN` tokens, a doubled heading mark ("## ## A" → "## A");
/// then `<b>`/`<strong>` become `**` and `<span>`/`<font>` tags go.
pub fn clean_summary(text: &str) -> String {
    use regex::Regex;
    use std::sync::LazyLock;
    static RULES: LazyLock<Vec<Regex>> = LazyLock::new(|| {
        [
            r"\A<RESPONSE>\s*",
            r"\s*\{utt_id=[^}]*\}",
            r"\[[^\]]*\]\(\s*\x{E200}[\s\S]*?\x{E201}\s*\)",
            r"\]\(\s*\x{E200}[\s\S]*?\x{E201}\s*\)",
            r"\x{E200}[\s\S]*?\x{E201}",
            r"[\x{E200}-\x{E2FF}]+",
            r"<cite>[\s\S]*?</cite>",
            r"\x{3010}[0-9]+\x{2020}[\s\S]*?\x{3011}",
            r"\[\^[0-9]+\^\]",
            r#"(?i)\s*\bcite(?:search[0-9]+)?turn[0-9]+(?:search[0-9]+)?\b[\x{201C}\x{201D}"]?"#,
            r#"(?i)\s*\bturn[0-9]+(?:search[0-9]+)?cite\b[\x{201C}\x{201D}"]?"#,
            r"(?i)\s*\bturn[0-9]+search[0-9]+\b",
        ]
        .iter()
        .filter_map(|r| Regex::new(r).ok())
        .collect()
    });
    static TAGS: LazyLock<Vec<(Regex, &'static str)>> = LazyLock::new(|| {
        [(r"(?i)<(?:b|strong)(?:[\s/][^>]*)?>", "**"), (r"(?i)</(?:b|strong)\s*>", "**"), (r"(?i)</?(?:span|font)(?:[\s/][^>]*)?>", "")]
            .iter()
            .filter_map(|(r, w)| Regex::new(r).ok().map(|r| (r, *w)))
            .collect()
    });
    let mut t = text.to_string();
    for r in RULES.iter() {
        t = r.replace_all(&t, "").into_owned();
    }
    t = collapse_heading_marks(&t);
    for (r, with) in TAGS.iter() {
        t = r.replace_all(&t, *with).into_owned();
    }
    t
}

/// Teams' `/^(#{1,6})\s+\1\s*/gm` → "$1 ": a heading mark said twice.
fn collapse_heading_marks(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let (mut i, mut copied) = (0, 0);
    while i < b.len() {
        let line_start = i == 0 || b[i - 1] == b'\n';
        let n = if line_start { b[i..].iter().take(7).take_while(|&&c| c == b'#').count() } else { 0 };
        if (1..=6).contains(&n) {
            let rest = &s[i + n..];
            let ws = rest.len() - rest.trim_start().len();
            if ws > 0 && rest.as_bytes()[ws..].iter().take(n).filter(|&&c| c == b'#').count() == n {
                let after = &rest[ws + n..];
                let tail = after.len() - after.trim_start().len();
                out.push_str(&s[copied..i]);
                out.push_str(&"#".repeat(n));
                out.push(' ');
                i += n + ws + n + tail;
                copied = i;
                continue;
            }
        }
        i += 1;
    }
    out.push_str(&s[copied..]);
    out
}

/// Custom summary: Copilot's summary of the meeting in a template's format,
/// streamed from its hub as Teams asks for it (ECS
/// enableCustomSummaryStreaming and the Catalyst endpoint).
pub async fn custom_summary(r: &RecapRef, recap_id: &str, ical_uid: &str, message: &str, language: &str, oid: &str, tid: &str) -> Result<String> {
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;
    let token = crate::auth::oauth::access_token_for("https://substrate.office.com/sydney/.default").await?;
    let correlation = uuid::Uuid::new_v4().to_string();
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request(catalyst_hub_url(&correlation, &token, oid, tid))?;
    req.headers_mut().insert("Origin", "https://teams.microsoft.com".parse()?);
    let (mut ws, _) = tokio_tungstenite::connect_async(req).await.context("Copilot's hub")?;
    ws.send(Message::text("{\"protocol\":\"json\",\"version\":1}\u{1e}")).await?;
    let body = catalyst_request(r, recap_id, ical_uid, message, language, &correlation, &uuid::Uuid::new_v4().to_string(), &Place::here());
    let call = json!({ "type": 4, "invocationId": "0", "target": "chat", "arguments": [body] });
    let mut sent = false;
    let mut summary = HubSummary::default();
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(180);
    while !summary.done {
        let Ok(next) = tokio::time::timeout_at(deadline, ws.next()).await else { anyhow::bail!("Copilot didn't finish the summary") };
        let Some(m) = next else { break };
        let text = match m? {
            Message::Text(t) => t.to_string(),
            Message::Close(_) => break,
            _ => continue,
        };
        for f in hub_frames(&text) {
            // The handshake's answer ({}), then the chat call.
            if !sent && f.get("type").is_none() {
                anyhow::ensure!(f.get("error").is_none(), "Copilot's hub refused the connection");
                ws.send(Message::text(format!("{call}\u{1e}"))).await?;
                sent = true;
                continue;
            }
            if f.get("type").and_then(Value::as_i64) == Some(6) {
                ws.send(Message::text("{\"type\":6}\u{1e}")).await?;
            }
            summary.frame(&f);
        }
    }
    let _ = ws.close(None).await;
    if let Some(e) = &summary.error {
        anyhow::bail!("Copilot: {e}");
    }
    let text = summary.summary();
    anyhow::ensure!(!text.is_empty(), "No summary");
    Ok(text)
}

/// The meeting summary's language from a catch-up answer (its
/// MeetingSummary's Language; "" when none).
pub fn summary_language(v: &Value) -> String {
    let src = v.pointer("/EntitySets/0/ResultSets/0/Results/0/Source/MeetingSummary").cloned().unwrap_or_default();
    let ms = match src {
        Value::String(s) => serde_json::from_str(&s).unwrap_or_default(),
        other => other,
    };
    ms.get("Language").and_then(Value::as_str).unwrap_or_default().to_string()
}

/// The recap's AI summary page (Teams 26304: the shared worker's catch-up
/// transform `hG`, 991291's AI notes and tasks panels): from the catch-up
/// answer, the meeting notes (MeetingSummary's KeyTopics: headline,
/// summary and their detailed points) and the follow-up tasks
/// (PointsOfInterest.ActionItems v2: Headline, DisplayCleanContent,
/// OwnerDisplayName), with each one's processing state.
/// `{notes: [{title, summary, details: [{topic, text}]}], tasks: [{title,
/// text, owner}], notesState, tasksState}`.
pub fn ai_notes_from(v: &Value) -> Value {
    let src = v.pointer("/EntitySets/0/ResultSets/0/Results/0/Source").cloned().unwrap_or_default();
    let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let summary = match src.get("MeetingSummary") {
        Some(Value::String(t)) => serde_json::from_str(t).unwrap_or_default(),
        Some(other) => other.clone(),
        None => Value::Null,
    };
    let notes: Vec<Value> = summary
        .get("KeyTopics")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|t| !s(t, "Summary").is_empty())
        .map(|t| {
            let details: Vec<Value> = t
                .get("DetailedSummaries")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .map(|d| json!({ "topic": s(d, "topic"), "text": s(d, "text") }))
                .collect();
            json!({ "title": s(t, "Headline"), "summary": s(t, "Summary"), "details": details })
        })
        .collect();
    let tasks: Vec<Value> = src
        .pointer("/PointsOfInterest/ActionItems")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|a| !s(a, "DisplayCleanContent").is_empty())
        .map(|a| json!({ "title": s(a, "Headline"), "text": s(a, "DisplayCleanContent"), "owner": s(a, "OwnerDisplayName") }))
        .collect();
    let state = |k: &str| src.pointer(&format!("/InsightProcessingStates/{k}")).and_then(Value::as_str).unwrap_or_default().to_string();
    json!({
        "notes": notes, "tasks": tasks, "found": !src.is_null(),
        "notesState": state("MeetingSummary"), "tasksState": state("ActionItemsPointsOfInterest"),
    })
}

/// What a recap's card may lack, from its catch-up answer (Teams' `hG`
/// reads organizerId, callId and the meeting's times from it): the
/// organizer, call, subject and start/end, where they're empty.
pub fn fill_from_catch_up(r: &mut RecapRef, v: &Value) {
    let src = v.pointer("/EntitySets/0/ResultSets/0/Results/0/Source").cloned().unwrap_or_default();
    let s = |p: &str| src.pointer(p).and_then(Value::as_str).unwrap_or_default().to_string();
    let ms = |p: &str| chrono::DateTime::parse_from_rfc3339(&s(p)).map(|t| t.timestamp_millis()).unwrap_or(0);
    if r.organizer_id.is_empty() {
        r.organizer_id = s("/MeetingRecording/OrganizerId");
    }
    if r.call_id.is_empty() {
        r.call_id = s("/MeetingRecording/CallId");
    }
    if r.thread_id.is_empty() {
        r.thread_id = s("/MeetingRecording/TeamsThreadId");
    }
    if r.ical_uid.is_empty() {
        r.ical_uid = s("/MeetingRecording/ICalUid");
    }
    if r.subject.is_empty() {
        r.subject = s("/MeetingSubject");
    }
    if r.start_ms == 0 {
        r.start_ms = ms("/MeetingStartTime");
        r.end_ms = ms("/MeetingEndTime");
    }
}

/// AI summary (Teams' recap AI notes): the catch-up call's notes and tasks.
pub async fn ai_notes(oid: &str, tid: &str, entity_id: &str) -> Result<Value> {
    Ok(ai_notes_from(&catch_up(oid, tid, entity_id).await?))
}

// ---------------------------------------------------------------------
// Custom summary's templates of your own (Teams 26304's customize-notes
// panel and the shared worker's template resolvers): files in your
// OneDrive's Recordings/CustomSummaryTemplates, named as the template, each
// `{"template": "<text>"}`.

/// Your templates' folder listing (Teams' getTemplatesFromODB), newest
/// first.
pub const TEMPLATES_LIST: &str = "/me/drive/root:/Recordings/CustomSummaryTemplates:/children?$orderby=lastModifiedDateTime%20desc";

fn is_item_id(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c))
}

/// A path segment for Graph's path addressing (the name as given,
/// percent-encoded).
fn segment(s: &str) -> String {
    s.bytes()
        .map(|c| if c.is_ascii_alphanumeric() || b"-_.~".contains(&c) { (c as char).to_string() } else { format!("%{c:02X}") })
        .collect()
}

/// Save and Apply of a new template (Teams' uploadTemplateFileToODB):
/// `PUT /me/drive/root:/Recordings/CustomSummaryTemplates/{name}:/content`
/// (Graph makes the folders).
pub fn template_upload_path(name: &str) -> String {
    format!("/me/drive/root:/Recordings/CustomSummaryTemplates/{}:/content", segment(name))
}

/// A template file's body (Teams' upload and content update).
pub fn template_body(template: &str) -> Vec<u8> {
    json!({ "template": template }).to_string().into_bytes()
}

/// The templates of a folder listing: [{id, name}] (Teams' Ut transform).
pub fn templates_from(v: &Value) -> Vec<Value> {
    v.get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|f| {
            let s = |k: &str| f.get(k).and_then(Value::as_str).unwrap_or_default();
            json!({ "id": s("id"), "name": s("name") })
        })
        .collect()
}

/// A template file's text (Teams' Ft transform: `template`, "" when none).
pub fn template_content_from(v: &Value) -> String {
    v.get("template").and_then(Value::as_str).unwrap_or_default().to_string()
}

/// Your templates (none while the folder doesn't exist).
pub async fn summary_templates(client: &TeamsClient) -> Result<Vec<Value>> {
    let Some(r) = client.graph_get_opt(TEMPLATES_LIST).await? else { return Ok(Vec::new()) };
    Ok(templates_from(&r.json().await.unwrap_or_default()))
}

/// A template's text (Edit's text, Share's copy, and a saved template's
/// summary): `GET /me/drive/items/{id}/content`.
pub async fn template_content(client: &TeamsClient, id: &str) -> Result<String> {
    anyhow::ensure!(is_item_id(id), "Not a template");
    let v: Value = client.graph_get(&format!("/me/drive/items/{id}/content")).await?.json().await.unwrap_or_default();
    Ok(template_content_from(&v))
}

/// Save a new template; its item id. Teams takes only 201 Created as
/// saved (a name already there would be replaced: 200).
pub async fn create_template(client: &TeamsClient, name: &str, template: &str) -> Result<String> {
    anyhow::ensure!(!name.trim().is_empty() && !template.trim().is_empty(), "This field cannot be blank");
    let r = client.graph_put_bytes(&template_upload_path(name), template_body(template), "application/json").await?;
    let status = r.status();
    anyhow::ensure!(status == reqwest::StatusCode::CREATED, "OneDrive answered {status}");
    let v: Value = r.json().await.unwrap_or_default();
    Ok(v.get("id").and_then(Value::as_str).unwrap_or_default().to_string())
}

/// Rename (`PATCH /me/drive/items/{id}` {name}) and/or replace the text
/// (`PUT /me/drive/items/{id}/content` {template}); each must answer 200.
pub async fn update_template(client: &TeamsClient, id: &str, name: Option<&str>, template: Option<&str>) -> Result<()> {
    anyhow::ensure!(is_item_id(id), "Not a template");
    if let Some(name) = name {
        let r = client.graph_patch(&format!("/me/drive/items/{id}"), &json!({ "name": name })).await?;
        anyhow::ensure!(r.status() == reqwest::StatusCode::OK, "OneDrive answered {}", r.status());
    }
    if let Some(template) = template {
        let r = client.graph_put_bytes(&format!("/me/drive/items/{id}/content"), template_body(template), "application/json").await?;
        anyhow::ensure!(r.status() == reqwest::StatusCode::OK, "OneDrive answered {}", r.status());
    }
    Ok(())
}

/// Delete a template (`DELETE /me/drive/items/{id}`, 204).
pub async fn delete_template(client: &TeamsClient, id: &str) -> Result<()> {
    anyhow::ensure!(is_item_id(id), "Not a template");
    let r = client.graph_delete(&format!("/me/drive/items/{id}")).await?;
    anyhow::ensure!(r.status() == reqwest::StatusCode::NO_CONTENT, "OneDrive answered {}", r.status());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn day_merges_catch_up_as_teams() {
        let b = catch_up_body_range("2026-11-01T00:00:00.000Z", "2026-11-22T00:00:00.000Z");
        assert_eq!(b["EntityRequests"][0]["QueryParameters"][0]["EntityType"], "MeetingCatchUp");
        assert_eq!(b["Scenario"]["Name"], "MeetingCatchUp");
        let rec = |ical: &str, event: &str, item: &str, tasks: usize| json!({"Source": {
            "MeetingId": event, "MeetingSubject": "S", "MeetingStartTime": "2026-11-21T07:33:00Z", "MeetingEndTime": "2026-11-21T08:03:00Z",
            "MeetingRecording": {"TeamsThreadId": "19:meeting_a@thread.v2", "ICalUid": ical, "CallId": "c", "OrganizerId": "o"},
            "Organizer": {"DisplayName": "OST Test 1"}, "DriveId": "b!d", "DriveItemId": item, "SitePath": "https://x-my.sharepoint.com/personal/u",
            "Description": "Transcript 0123abcd-0000-4000-8000-00000000beef of the meeting",
            "PointsOfInterest": {"ActionItems": vec![json!({}); tasks], "MentionEvents": [{}]}}});
        // Two recommendations for the meeting (the second for its
        // recording), one without a calendar event.
        let v = json!({"EntitySets": [{"ResultSets": [{"Results": [rec("ABC", "ev1", "other", 2), rec("ABC", "ev1", "rec1", 13), rec("NOEVENT", "", "x", 1)]}]}]});
        let recs = recommendation_threads(&v);
        assert_eq!(recs[0]["resources"][0]["metadata"]["transcriptId"], "0123abcd-0000-4000-8000-00000000beef");
        let artifact = json!({"threadInfo": {"threadId": "19:meeting_a@thread.v2", "iCalUid": "abc", "eventId": "ev1", "subject": "OST TEST 248 agenda",
            "start": {"dateTime": "2026-11-21T07:33:00.0000000"}, "end": {"dateTime": "2026-11-21T08:03:00.0000000"}},
            "resources": [{"type": "Recording", "metadata": {"driveId": "b!d", "driveItemId": "rec1"}}, {"type": "TranscriptV2", "location": "https://x/transcripts/t1/content"}]});
        // An artifact without an iCalUid drops out, as in Teams' merge.
        let loose = json!({"threadInfo": {"eventId": "ev2", "subject": "x"}, "resources": [{"type": "Recording"}]});
        let rows = day_rows(Some(&json!({"value": [artifact, loose]})), Some(&v));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["subject"], "OST TEST 248 agenda");
        assert_eq!(rows[0]["eventId"], "ev1");
        assert_eq!(rows[0]["actionItemCount"], 13);
        assert_eq!(rows[0]["mentionEventCount"], 1);
        assert_eq!(rows[0]["transcript"], true);
        // No artifacts that day: the recommendation is the meeting's row
        // (no recording to tell them apart: the first one).
        let rows = day_rows(None, Some(&v));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["subject"], "S");
        assert_eq!(rows[0]["actionItemCount"], 2);
        assert_eq!(rows[0]["transcript"], true);
        // No catch-up: the artifacts as they are, without counts.
        let rows = day_rows(Some(&json!({"value": [json!({"threadInfo": {"iCalUid": "abc", "eventId": "ev1"}, "resources": [{"type": "TranscriptV2"}]})]})), None);
        assert_eq!(rows[0]["actionItemCount"], 0);
    }

    #[test]
    fn home_rows_as_teams() {
        // A day's recommendation with its tasks, a mention and a speaker
        // (the fields Teams' catch-up reply has), and the meeting's
        // artifacts: two recordings, a transcript and its notes twice.
        let v = json!({"EntitySets": [{"ResultSets": [{"Results": [{"Source": {
            "MeetingId": "ev1", "MeetingSubject": "OST TEST 240 recap meeting", "MeetingStartTime": "2026-11-21T04:23:00Z", "MeetingEndTime": "2026-11-21T05:02:00Z",
            "MeetingRecording": {"TeamsThreadId": "19:meeting_a@thread.v2", "ICalUid": "ABC"}, "DriveId": "b!d", "DriveItemId": "rec2", "Url": "https://x/r",
            "RecommendationsReasonList": [{"Type": "Attended"}, {"Type": "MissedMeeting"}],
            "Speakers": [{"DisplayName": "OST Test 3", "ObjectId": "01c4", "TenantId": "t"}, {"DisplayName": "", "ObjectId": "x"}],
            "PointsOfInterest": {
                "ActionItems": [{"Headline": "Q2 Budget Review", "DisplayCleanContent": "Check the second-quarter budget numbers.", "OwnerDisplayName": "OST Test 1"}],
                "MentionEvents": [{"SpeakerName": "OST Test 3", "SpeakerObjectId": "01c4", "EventDateTime": "2026-11-21T04:30:00Z",
                                   "UtteranceFromTranscript": "thanks ost for the plan", "MentionOffsetInUtterance": 7, "NameLength": 3, "Snippet": "Thanks OST for the plan."}]}}}]}]}]});
        let note = json!({"type": "notes", "id": "", "mcoResourceId": "n1", "location": "https://x/:fl:/p/u/abc", "metadata": {"state": "Enabled"}});
        let artifact = json!({"threadInfo": {"threadId": "19:meeting_a@thread.v2", "iCalUid": "abc", "eventId": "ev1", "subject": "OST TEST 240 recap meeting",
            "start": {"dateTime": "2026-11-21T04:23:00.0000000"}, "end": {"dateTime": "2026-11-21T05:02:00.0000000"}},
            "resources": [{"type": "Recording", "location": "https://x/v1", "hasPermission": true, "metadata": {"driveId": "b!d", "driveItemId": "rec1"}},
                          {"type": "Recording", "location": "https://x/v2", "hasPermission": true, "metadata": {"driveId": "b!d", "driveItemId": "rec2"}},
                          {"type": "TranscriptV2", "location": "https://x/transcripts/t1/content"}, note.clone(), note,
                          {"type": "MeetingChat", "id": "", "location": "https://x/nofile"}]});
        let rows = day_rows(Some(&json!({"value": [artifact.clone()]})), Some(&v));
        let r = &rows[0];
        assert_eq!(r["actionItems"][0]["actionItemTitle"], "Q2 Budget Review");
        assert_eq!(r["actionItems"][0]["ownerName"], "OST Test 1");
        // The mention's words are the snippet's, the name found in it again.
        assert_eq!(r["mentions"][0]["utteranceContainingTheMention"], "Thanks OST for the plan.");
        assert_eq!(r["mentions"][0]["mentionOffsetInUtterance"], 7);
        assert_eq!(r["mentions"][0]["mentionedByUserDisplayName"], "OST Test 3");
        assert_eq!(r["speakers"][0]["displayName"], "OST Test 3");
        assert_eq!(r["reasons"][0], "ATTENDED");
        assert_eq!(r["reasons"][1], "MISSED_MEETING");
        // The thumbnail is the catch-up's recording; the notes once; a
        // file without an id isn't listed.
        assert_eq!(r["thumb"]["itemId"], "rec2");
        assert_eq!(r["files"].as_array().map(Vec::len), Some(1));
        assert_eq!(r["files"][0]["type"], "Notes");
        assert_eq!(r["access"], "Good");
        // Only a transcript; nothing you may open (and then no files).
        let mut t = artifact.clone();
        t["resources"] = json!([{"type": "TranscriptV2", "location": "https://x/transcripts/t1/content"}]);
        assert_eq!(row_from(&t).unwrap()["access"], "TranscriptOnly");
        t["resources"] = json!([{"type": "TranscriptV2", "hasPermission": false, "location": "https://x/transcripts/t1/content"}, {"type": "Notes", "id": "n", "location": "https://x/n"}]);
        let r = row_from(&t).unwrap();
        assert_eq!(r["access"], "NoPermission");
        assert_eq!(r["files"].as_array().map(Vec::len), Some(0));
    }

    #[test]
    fn ai_notes_read_as_teams() {
        // OST TEST 240 recap meeting's catch-up (captured from Teams on
        // winpc, 2026-11-21), shortened.
        let summary = json!({"KeyTopics": [{"Headline": "Project Plan And Budget Updates", "Summary": "OST Test 1 is responsible for sending the updated project plan.",
            "DetailedSummaries": [{"topic": "Updated Project Plan", "text": "OST Test 1 was assigned to send the updated project plan to the team by Friday."},
                                  {"topic": "Second-Quarter Budget", "text": "OST Test 1 was asked to check the budget numbers."}],
            "Citations": [{"UtteranceStartOffsetTimespan": "00:01:12", "Source": "Transcript"}]}],
            "ProcessingResult": "ProcessedSuccessfully", "Version": "2.0.0", "Language": "en-us"});
        let v = json!({"EntitySets": [{"MeetingInsights": "Premium", "ResultSets": [{"Results": [{"Source": {
            "MeetingSummary": summary.to_string(),
            "PointsOfInterest": {"ActionItemsVersion": "2.0.0", "ActionItems": [
                {"Id": null, "DisplayCleanContent": "Send the updated project plan to the team.", "OwnerDisplayName": "OST Test 1", "Headline": "Updated Project Plan"},
                {"Id": null, "DisplayCleanContent": "Book the Review Room for the launch review scheduled next Tuesday at 10.", "OwnerDisplayName": "OST Test 3", "Headline": "Launch Review Logistics"}]},
            "InsightProcessingStates": {"ActionItemsPointsOfInterest": "ProcessedSuccessfully", "MeetingSummary": "ProcessedSuccessfully"}}}]}]}]});
        let n = ai_notes_from(&v);
        assert_eq!(n["notes"][0]["title"], "Project Plan And Budget Updates");
        assert_eq!(n["notes"][0]["details"][1]["topic"], "Second-Quarter Budget");
        assert_eq!(n["tasks"].as_array().unwrap().len(), 2);
        assert_eq!((n["tasks"][1]["title"].as_str(), n["tasks"][1]["owner"].as_str()), (Some("Launch Review Logistics"), Some("OST Test 3")));
        assert_eq!(n["notesState"], "ProcessedSuccessfully");
        let mut r = RecapRef::default();
        let src = json!({"EntitySets": [{"ResultSets": [{"Results": [{"Source": {"MeetingSubject": "OST TEST 240 recap meeting",
            "MeetingStartTime": "2026-11-21T04:26:01Z", "MeetingEndTime": "2026-11-21T04:32:06Z",
            "MeetingRecording": {"OrganizerId": "4287e791", "CallId": "26943b81", "TeamsThreadId": "19:meeting_x@thread.v2", "ICalUid": "0400"}}}]}]}]});
        fill_from_catch_up(&mut r, &src);
        assert_eq!((r.organizer_id.as_str(), r.subject.as_str(), r.start_ms), ("4287e791", "OST TEST 240 recap meeting", 1795235161000));
        let empty = ai_notes_from(&json!({}));
        assert_eq!((empty["notes"].as_array().unwrap().len(), empty["found"].as_bool()), (0, Some(false)));
    }

    #[test]
    fn recap_extras_as_teams() {
        assert_eq!(
            clipchamp_url("https://x-my.sharepoint.com/personal/o/Documents/Recordings/a.mp4"),
            "https://x-my.sharepoint.com/personal/o/Documents/Recordings/a.mp4?web=1&referrer=Teams.TEAMS-ELECTRON&referrerScenario=RecapOpenInStreamButton.view"
        );
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-20T00:00:00Z").unwrap().with_timezone(&chrono::Utc);
        assert_eq!(remaining_days("2027-03-19T12:00:00Z", now), 120);
        assert_eq!(remaining_days("", now), -1);
        let m = mentions_from(&json!({"EntitySets": [{"ResultSets": [{"Results": [{"Source": {"PointsOfInterest": {"UserMentionCount": 1,
            "MentionEvents": [{"SpeakerName": "OST Test 2", "UtteranceFromTranscript": "Thanks OST Test 1", "MentionOffsetInUtterance": 7, "NameLength": 10}]}}}]}]}]}));
        assert_eq!((m["count"].as_i64(), m["items"][0]["speaker"].as_str(), m["items"][0]["nameStart"].as_i64()), (Some(1), Some("OST Test 2"), Some(7)));
        let r = RecapRef { call_id: "c".into(), organizer_id: "o".into(), thread_id: "19:meeting_t@thread.v2".into(), ..Default::default() };
        let b = catalyst_request(&r, "SPO_x_01T", "", "Go", "en-US", "corr", "sess", &Place { offset_minutes: 480, zone: "America/Los_Angeles".into() });
        let meta = &b["message"]["messageAnnotations"][0]["messageAnnotationMetadata"];
        assert_eq!((meta["vroomId"].as_str(), meta["canvasType"].as_str(), meta["organizerId"].as_str(), meta["callId"].as_str()), (Some("SPO_x_01T"), Some("RecapCall"), Some("o"), Some("c")));
        assert_eq!((b["message"]["locale"].as_str(), b["message"]["locationInfo"]["timeZoneOffset"].as_i64(), b["streamingMode"].as_str()), (Some("en-US"), Some(480), Some("ConciseWithPadding")));
        assert_eq!(catalyst_request(&r, "v", "0400AB", "Go", "", "c", "s", &Place::here())["message"]["messageAnnotations"][0]["messageAnnotationMetadata"]["canvasType"], "Recap");
    }

    #[test]
    fn asks_and_reads_as_teams() {
        let a = chrono::DateTime::parse_from_rfc3339("2026-11-18T08:00:00Z").unwrap().with_timezone(&chrono::Utc);
        let b = chrono::DateTime::parse_from_rfc3339("2026-11-19T07:59:59.999Z").unwrap().with_timezone(&chrono::Utc);
        assert_eq!(day_query(a, b), "user/meetings/contents?top=20&startDateTime=2026-11-18T08:00:00.000Z&endDateTime=2026-11-19T07:59:59.999Z&includeTypes=Recording,TranscriptV2,MeetingChat,MeetingStage,Notes");
        let v = json!({"value": [{"threadInfo": {"threadId": "19:meeting_x@thread.v2", "organizer": {"emailAddress": {"name": "OST Test 1"}},
            "start": {"dateTime": "2026-11-16T23:00:00.0000000", "timeZone": "UTC"}, "end": {"dateTime": "2026-11-16T23:30:00.0000000"},
            "subject": "OST calendar test: created from OST"}}]});
        let m = meetings_from(&v);
        assert_eq!(m[0]["start"], "2026-11-16T23:00:00Z");
        assert_eq!(m[0]["organizer"], "OST Test 1");
    }

    #[test]
    fn recap_link_and_share_message_as_teams() {
        // OST TEST 217 town hall 2's, as Teams' Give access sent it.
        let r = RecapRef {
            thread_id: "19:meeting_YTE4@thread.v2".into(), ical_uid: "0400".into(), organizer_id: "4287".into(), tenant_id: "2716".into(),
            call_id: "084f".into(), drive_id: "b!Mww".into(), item_id: "01BV".into(),
            file_url: "https://scnetsolutions-my.sharepoint.com/:v:/p/ost-test1/IQBv".into(), subject: "OST TEST 217 town hall 2".into(),
            start_ms: 1795063200000, end_ms: 1795066800000, recap_type: String::new(), recap_id: String::new(),
        };
        let l = recap_link(&r);
        assert_eq!(l, "https://teams.microsoft.com/l/meetingrecap?driveId=b%21Mww&driveItemId=01BV&sitePath=https%3A%2F%2Fscnetsolutions-my.sharepoint.com%2F%3Av%3A%2Fp%2Fost-test1%2FIQBv&fileUrl=https%3A%2F%2Fscnetsolutions-my.sharepoint.com%2F%3Av%3A%2Fp%2Fost-test1%2FIQBv&iCalUid=0400&threadId=19%3Ameeting_YTE4%40thread.v2&organizerId=4287&tenantId=2716&callId=084f&threadType=Meeting&meetingType=Scheduled&subType=RecapSharingLink_RecapChiclet&recapType=RecordingAndTranscript");
        let (content, links) = share_message(&r, "Wednesday, November 18", "Wednesday, November 18 \u{b7} 8:40 PM - 9:40 PM");
        assert!(content.contains(">Recap: OST TEST 217 town hall 2 Wednesday, November 18 | Meeting | Microsoft Teams</a></div>"));
        assert!(content.contains("data-itemprops=\"{&quot;version&quot;:1,"));
        let links: Value = serde_json::from_str(&links).unwrap();
        assert_eq!(links[1]["recapSharingLinkMeta"]["meetingStartTimeMs"], "1795063200000");
        assert_eq!(links[0]["preview"]["title"], "OST TEST 217 town hall 2");
    }

    #[test]
    fn finds_the_meeting_of_a_recap() {
        let v = json!({"value": [
            {"threadInfo": {"threadId": "19:meeting_a@thread.v2", "iCalUid": "X1"}, "resources": []},
            {"threadInfo": {"threadId": "19:meeting_b@thread.v2", "iCalUid": "0400AB", "organizer": {"id": "4287@2716"}},
             "resources": [{"type": "Recording", "driveItemId": "01BV", "fileUrl": "https://x/:v:/p/o/I"}]}]});
        let c = match_contents(&v, "0400ab", "").unwrap();
        assert_eq!((c.thread.as_str(), c.organizer.as_str(), c.file_url.as_str()), ("19:meeting_b@thread.v2", "4287", ""));
        assert_eq!(c.transcript, None);
        let c = match_contents(&v, "", "01BV").unwrap();
        assert_eq!(c.file_url, "https://x/:v:/p/o/I");
        // A transcript and no recording: the last TranscriptV2's file.
        let v = json!({"value": [{"threadInfo": {"threadId": "19:meeting_t@thread.v2", "iCalUid": "T1"}, "resources": [
            {"type": "TranscriptV2", "driveId": "b!old", "driveItemId": "01OLD"},
            {"type": "Notes", "driveId": "b!n", "driveItemId": "01N"},
            {"type": "TranscriptV2", "metadata": {"driveId": "b!new", "driveItemId": "01NEW"}}]}]});
        assert_eq!(match_contents(&v, "t1", "").unwrap().transcript, Some(("b!new".into(), "01NEW".into())));
        assert!(match_contents(&v, "nope", "nope").is_none());
    }

    #[test]
    fn cleans_a_summary_as_teams() {
        assert_eq!(clean_summary("<RESPONSE>  ## ## Overview\nA point {utt_id=12}."), "## Overview\nA point.");
        assert_eq!(clean_summary("x [1](\u{e200}cite\u{e202}turn0\u{e201}) y\u{e203}"), "x  y");
        assert_eq!(clean_summary("a<cite>1</cite> b\u{3010}3\u{2020}source\u{3011}[^2^]"), "a b");
        assert_eq!(clean_summary("Done citeturn0search1 and turn1search2."), "Done and.");
        assert_eq!(clean_summary("<b>Bold</b> <strong class=\"x\">S</strong> <span style=\"c\">t</span><font>f</font>"), "**Bold** **S** tf");
        // Only the start's <RESPONSE>; a <br> isn't <b>; a heading said once stays.
        assert_eq!(clean_summary("x <RESPONSE> <br> ### Title\n#### #### Sub"), "x <RESPONSE> <br> ### Title\n#### Sub");
        assert_eq!(collapse_heading_marks("## ### x"), "## # x");
        assert_eq!(collapse_heading_marks("##\n## A"), "## A");
    }

    #[test]
    fn template_requests_as_teams() {
        let p = saved_template_prompt("Create an executive report that includes:\n\n- Overview");
        assert!(p.contains("-->\nCreate an executive report that includes:\n\n- Overview\n</RECAP_INSTRUCTIONS_AND_EXAMPLE>"));
        assert!(!p.contains("{$USERINPUT$}"));
        // A template that itself says {$USERINPUT$} is put in once, as written.
        assert_eq!(saved_template_prompt("{$USERINPUT$}").matches("{$USERINPUT$}").count(), 1);
        assert_eq!(template_upload_path("OST TEST 240 template"), "/me/drive/root:/Recordings/CustomSummaryTemplates/OST%20TEST%20240%20template:/content");
        assert_eq!(template_upload_path("a#b%c\u{e9}"), "/me/drive/root:/Recordings/CustomSummaryTemplates/a%23b%25c%C3%A9:/content");
        assert_eq!(String::from_utf8(template_body("Line \"1\"\n- a")).unwrap(), r#"{"template":"Line \"1\"\n- a"}"#);
        assert_eq!(TEMPLATES_LIST, "/me/drive/root:/Recordings/CustomSummaryTemplates:/children?$orderby=lastModifiedDateTime%20desc");
        let list = templates_from(&json!({"value": [{"id": "01AB!x", "name": "Mine", "size": 30}, {"name": "No id"}]}));
        assert_eq!(list, vec![json!({"id": "01AB!x", "name": "Mine"}), json!({"id": "", "name": "No id"})]);
        assert_eq!(template_content_from(&json!({"template": "- Speaker"})), "- Speaker");
        assert_eq!(template_content_from(&json!({"other": 1})), "");
        assert!(is_item_id("01BVABC!123") && !is_item_id("../x") && !is_item_id(""));
    }

    #[test]
    fn recap_id_as_teams() {
        use base64::Engine as _;
        // A drive id of three GUIDs' bytes (site 00..0f, web 10..1f, library 20..2f).
        let bytes: Vec<u8> = (0u8..48).collect();
        let drive = format!("b!{}", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&bytes));
        let ids = "03020100-0504-0706-0809-0a0b0c0d0e0f,13121110-1514-1716-1819-1a1b1c1d1e1f,23222120-2524-2726-2829-2a2b2c2d2e2f";
        let want = format!("SPO_{}_01ITEM", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(ids));
        assert_eq!(canonical_recap_id(&drive, "01ITEM"), want);
        assert_eq!(canonical_recap_id("", "01ITEM"), "");
        assert_eq!(canonical_recap_id("null", "x"), "null");
        let r = RecapRef { drive_id: drive.clone(), item_id: "01ITEM".into(), ..Default::default() };
        assert_eq!(r.recap_id(), want);
        let r = RecapRef { recap_id: "SPO_t_01T".into(), ..Default::default() };
        assert_eq!(r.recap_id(), "SPO_t_01T");
    }

    #[test]
    fn custom_summary_streams_as_teams() {
        let speaker = catalyst_message("SpeakersBasedRecap", "French");
        assert!(speaker.contains("Translate content into French") && !speaker.contains("{$LANGUAGE_INSTRUCTION$}"));
        assert!(catalyst_message("ExecutiveSummary", "").contains("Translate ALL content into ,"));
        assert_eq!(catalyst_message("ProjectSummary", "x"), "ProjectSummary");
        let u = catalyst_hub_url("cid", "tok", "oid", "tid");
        assert!(u.starts_with("wss://substrate.office.com/m365Copilot/Chathub/oid@tid?ClientRequestId=cid&access_token=tok&variants=EnableMcpServerWidgets%2C"));
        assert!(u.ends_with("&source=teamshub&scenario=TeamsMeetingRecapCopilot&product=Teams&agentHost=BizChat.FullScreen&licenseType=Premium&agent=work&isproactivechat=1"));
        let mut h = HubSummary::default();
        for f in hub_frames("{}\u{1e}{\"type\":1,\"target\":\"update\",\"arguments\":[{\"streamingMode\":\"Full\",\"messages\":[{\"author\":\"user\",\"text\":\"q\"},{\"author\":\"bot\",\"text\":\"#### **OST**\"}]}]}\u{1e}") {
            h.frame(&f);
        }
        for f in hub_frames("{\"type\":1,\"target\":\"update\",\"arguments\":[{\"streamingMode\":\"Delta\",\"writeAtCursor\":\"\\n- **Plan**: send it [1](https://x/y)\"}]}\u{1e}{\"type\":6}\u{1e}{\"type\":3,\"invocationId\":\"0\"}\u{1e}") {
            h.frame(&f);
        }
        assert!(h.done && h.error.is_none());
        assert_eq!(h.summary(), "#### **OST**\n- **Plan**: send it");
        let mut h = HubSummary::default();
        h.frame(&json!({"type": 1, "target": "update", "arguments": [{"item": {"result": {"error": "Throttled", "value": "Too many"}}}]}));
        assert_eq!(h.error.as_deref(), Some("Too many"));
        assert_eq!(summary_language(&json!({"EntitySets": [{"ResultSets": [{"Results": [{"Source": {"MeetingSummary": "{\"Language\":\"en-US\"}"}}]}]}]})), "en-US");
        assert_eq!(summary_language(&json!({})), "");
    }
}
