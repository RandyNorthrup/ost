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

/// Audio recaps (Teams' podcasts), newest first.
pub async fn podcasts(region: &str) -> Result<Value> {
    let v = get(&format!("{}/podcasts?top=10", base(region))).await?;
    Ok(json!({ "items": v.get("items").cloned().unwrap_or(json!([])), "skipToken": v.get("skipToken").cloned().unwrap_or(Value::Null) }))
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

/// A meeting row of Home from a contents reply.
pub fn meetings_from(v: &Value) -> Vec<Value> {
    v.get("value").and_then(Value::as_array).into_iter().flatten().filter_map(|m| {
        let t = m.get("threadInfo")?;
        let s = |p: &str| t.pointer(p).and_then(Value::as_str).unwrap_or_default().to_string();
        let utc = |p: &str| {
            let d = s(p);
            if d.is_empty() { d } else { format!("{}Z", d.trim_end_matches('Z').split('.').next().unwrap_or_default()) }
        };
        Some(json!({
            "threadId": s("/threadId"),
            "subject": s("/subject"),
            "start": utc("/start/dateTime"),
            "end": utc("/end/dateTime"),
            "organizer": s("/organizer/emailAddress/name"),
            "channel": s("/channelDisplayName"),
            // Generate audio recap lists the meetings you have a transcript of.
            "transcript": m.to_string().contains("TranscriptV2"),
        }))
    }).collect()
}

/// Home's meetings for `days` local days back from `from_days_ago`
/// (newest first), the days asked in parallel.
pub async fn meetings(region: &str, from_days_ago: i64, days: i64) -> Result<Value> {
    use chrono::{Local, TimeZone};
    let today = Local::now().date_naive();
    let mut asks = Vec::new();
    for i in from_days_ago..from_days_ago + days {
        let day = today - chrono::Duration::days(i);
        let start = Local.from_local_datetime(&day.and_hms_opt(0, 0, 0).unwrap_or_default()).single().map(|d| d.with_timezone(&chrono::Utc));
        let end = Local.from_local_datetime(&day.and_hms_milli_opt(23, 59, 59, 999).unwrap_or_default()).single().map(|d| d.with_timezone(&chrono::Utc));
        if let (Some(a), Some(b)) = (start, end) {
            asks.push((day, format!("{}/{}", base(region), day_query(a, b))));
        }
    }
    let replies = futures::future::join_all(asks.iter().map(|(_, u)| get(u))).await;
    let mut out = Vec::new();
    for ((day, _), r) in asks.iter().zip(replies) {
        let list = r.map(|v| meetings_from(&v)).unwrap_or_default();
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

/// The meeting's own thread, organizer and recording address for a recap
/// card, from the meeting artifacts service's contents for the meeting's
/// day (Teams reads them from its recap data): the entry with the same
/// iCalUid, or whose resources name the recording.
pub fn match_contents(v: &Value, ical_uid: &str, item_id: &str) -> Option<(String, String, String)> {
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
            .filter(|res| res.to_string().contains(item_id))
            .find_map(|res| ["fileUrl", "webUrl", "location", "url"].iter().find_map(|k| res.pointer(&format!("/{k}")).and_then(Value::as_str)).map(str::to_string))
            .unwrap_or_default();
        Some((thread, org, file))
    })
}

/// Fill a recap's meeting thread, organizer and recording address from
/// the meeting artifacts service.
pub async fn resolve(region: &str, r: &mut RecapRef) -> Result<Value> {
    let day = |ms: i64| chrono::DateTime::from_timestamp_millis(ms).unwrap_or_default();
    let (a, b) = (day(r.start_ms - 86_400_000), day(r.end_ms.max(r.start_ms) + 86_400_000));
    let v = get(&format!("{}/{}", base(region), day_query(a, b))).await?;
    if let Some((thread, org, file)) = match_contents(&v, &r.ical_uid, &r.item_id) {
        if r.thread_id.is_empty() || !thread.is_empty() {
            r.thread_id = thread;
        }
        if !org.is_empty() {
            r.organizer_id = org;
        }
        if !file.is_empty() && r.file_url.is_empty() {
            r.file_url = file;
        }
    }
    Ok(v)
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
    let props = json!({ "version": 1, "kind": "meetingRecap", "meetingTitle": r.subject, "meetingStartTimeMs": r.start_ms.to_string(), "meetingEndTimeMs": r.end_ms.to_string() });
    let content = format!(
        "\n    <div itemprop=\"teams-copy-link\"><a href=\"{l}\" title=\"{l}\" data-origin-known=\"true\" itemtype=\"http://schema.skype.com/HyperLink/MeetingRecap\" data-itemprops=\"{p}\">Recap: {t} {d} | Meeting | Microsoft Teams</a></div>",
        l = e(&link),
        p = e(&props.to_string()),
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

#[cfg(test)]
mod tests {
    use super::*;

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
            start_ms: 1795063200000, end_ms: 1795066800000, recap_type: String::new(),
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
        let (t, o, f) = match_contents(&v, "0400ab", "").unwrap();
        assert_eq!((t.as_str(), o.as_str(), f.as_str()), ("19:meeting_b@thread.v2", "4287", ""));
        let (_, _, f) = match_contents(&v, "", "01BV").unwrap();
        assert_eq!(f, "https://x/:v:/p/o/I");
        assert!(match_contents(&v, "nope", "nope").is_none());
    }
}
