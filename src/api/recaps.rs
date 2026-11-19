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
}
