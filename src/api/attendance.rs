//! Meeting attendance reports, as Teams' Attendance view reads them
//! (captured from Teams desktop on 2026-11-11):
//! - `GET https://teams.microsoft.com/api/attendancereport/prod/attendancereport/history
//!   ?threadId={thread}&organizerObjectId={oid}[&messageId={post}]&pageSize=50&uiSource=…`
//!   lists the meeting's reports, one per call: `{reports: [{threadId,
//!   callId, startTimeUtc, endTimeUtc, createdTimeUtc, attendeeCount}]}`;
//! - `GET …/attendancereport?threadId=…&callId=…&organizerObjectId=…&pageIndex=0[&messageId=…]&uiSource=…`
//!   is one report: `{summary: {startTime, endTime, duration,
//!   attendeeCount, averageAttendeeDuration, …}, participants:
//!   [{displayName, emailAddress, upn, mri, role, joinTime, leaveTime,
//!   durationInSeconds, attendanceIntervals, …}], pageIndex, totalPages}`.
//!
//! `messageId` is a channel meeting's post id (a scheduled meeting has
//! none). Teams' `uiSource` is "channelChiclet" from a channel thread and
//! "meetingchat" from a meeting chat.

use anyhow::{Context, Result, bail};
use serde_json::Value;

use super::client::TeamsClient;

const BASE: &str = "https://teams.microsoft.com/api/attendancereport/prod/attendancereport";

fn check(thread: &str, organizer: &str, message: Option<&str>) -> Result<()> {
    let thread_ok = thread.starts_with("19:")
        && (thread.ends_with("@thread.v2") || thread.ends_with("@thread.tacv2") || thread.ends_with("@thread.skype"))
        && thread[3..].chars().all(|c| c.is_ascii_alphanumeric() || "_-=@.".contains(c));
    let message_ok = message.is_none_or(|m| !m.is_empty() && m.bytes().all(|b| b.is_ascii_digit()));
    if !thread_ok || uuid::Uuid::parse_str(organizer).is_err() || !message_ok {
        bail!("Not a meeting");
    }
    Ok(())
}

fn ui_source(message: Option<&str>) -> &'static str {
    if message.is_some() { "channelChiclet" } else { "meetingchat" }
}

/// The history URL (query in Teams' order).
pub fn history_url(thread: &str, organizer: &str, message: Option<&str>) -> String {
    let msg = message.map(|m| format!("&messageId={m}")).unwrap_or_default();
    format!(
        "{BASE}/history?threadId={thread}&organizerObjectId={organizer}{msg}&pageSize=50&uiSource={}",
        ui_source(message)
    )
}

/// One report's URL.
pub fn report_url(thread: &str, call: &str, organizer: &str, message: Option<&str>, page: u32) -> String {
    let msg = message.map(|m| format!("&messageId={m}")).unwrap_or_default();
    format!(
        "{BASE}?threadId={thread}&callId={call}&organizerObjectId={organizer}&pageIndex={page}{msg}&uiSource={}",
        ui_source(message)
    )
}

/// The attendance report service's app (Teams asks for its
/// `AttendanceReport.Read` scope).
const RESOURCE: &str = "c82e1b1b-5ab6-48fb-b4f8-890a5b27b181/.default";

async fn get_json(client: &TeamsClient, url: &str) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for(RESOURCE).await?;
    Ok(client
        .http()
        .get(url)
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Attendance report")?
        .json()
        .await?)
}

/// The meeting's reports, newest first as the service lists them.
pub async fn history(client: &TeamsClient, thread: &str, organizer: &str, message: Option<&str>) -> Result<Vec<Value>> {
    check(thread, organizer, message)?;
    let v = get_json(client, &history_url(thread, organizer, message)).await?;
    Ok(v["reports"].as_array().cloned().unwrap_or_default())
}

/// One call's report (every page of participants).
pub async fn report(client: &TeamsClient, thread: &str, call: &str, organizer: &str, message: Option<&str>) -> Result<Value> {
    check(thread, organizer, message)?;
    if uuid::Uuid::parse_str(call).is_err() {
        bail!("Not a call");
    }
    let mut first = get_json(client, &report_url(thread, call, organizer, message, 0)).await?;
    let pages = first["totalPages"].as_u64().unwrap_or(1).min(50) as u32;
    for page in 1..pages {
        let more = get_json(client, &report_url(thread, call, organizer, message, page)).await?;
        if let (Some(all), Some(extra)) = (first["participants"].as_array_mut(), more["participants"].as_array()) {
            all.extend(extra.iter().cloned());
        }
    }
    Ok(first)
}

/// The report as Teams' Download saves it: `GET …/attendancereport/file
/// ?threadId=…&callId=…&organizerObjectId=…&timeZoneId={Windows zone}
/// &locale=en` answers the tab-separated report (Summary, Participants,
/// In-Meeting Activities). Returns the file name the service gives (its
/// Content-Disposition) and the bytes.
pub async fn file(client: &TeamsClient, thread: &str, call: &str, organizer: &str) -> Result<(Option<String>, Vec<u8>)> {
    check(thread, organizer, None)?;
    if uuid::Uuid::parse_str(call).is_err() {
        bail!("Not a call");
    }
    let zone = super::search::windows_zone(&super::find::local_timezone());
    let url = format!(
        "{BASE}/file?threadId={thread}&callId={call}&organizerObjectId={organizer}&timeZoneId={}&locale=en",
        url::form_urlencoded::byte_serialize(zone.as_bytes()).collect::<String>().replace('+', "%20")
    );
    let token = crate::auth::oauth::access_token_for(RESOURCE).await?;
    let resp = client.http().get(&url).bearer_auth(&token).send().await?.error_for_status().context("Attendance report")?;
    let name = resp
        .headers()
        .get(reqwest::header::CONTENT_DISPOSITION)
        .and_then(|v| v.to_str().ok())
        .and_then(file_name);
    tracing::debug!(headers = ?resp.headers(), "attendance report file");
    Ok((name, resp.bytes().await?.to_vec()))
}

fn percent_decode(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            out.push(u8::from_str_radix(s.get(i + 1..i + 3)?, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// The file name in a Content-Disposition header (`filename*=UTF-8''…`
/// preferred over `filename="…"`), without any path.
fn file_name(cd: &str) -> Option<String> {
    let star = cd.split(';').map(str::trim).find_map(|p| p.strip_prefix("filename*=")).and_then(|v| {
        let v = v.trim_matches('"');
        let enc = v.splitn(3, '\'').nth(2).unwrap_or(v);
        percent_decode(enc)
    });
    // The service percent-encodes the plain name too.
    let plain = || {
        cd.split(';').map(str::trim).find_map(|p| p.strip_prefix("filename=")).map(|v| {
            let v = v.trim_matches('"');
            percent_decode(v).unwrap_or_else(|| v.to_string())
        })
    };
    let name = star.or_else(plain)?;
    let name = name.rsplit(['/', '\\']).next().unwrap_or_default().trim().to_string();
    (!name.is_empty() && name != "." && name != "..").then_some(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls_as_teams() {
        let t = "19:ekCP@thread.tacv2";
        let o = "4287e791-1b98-4963-8b94-281c50472683";
        assert_eq!(
            history_url(t, o, Some("1794372973956")),
            "https://teams.microsoft.com/api/attendancereport/prod/attendancereport/history?threadId=19:ekCP@thread.tacv2&organizerObjectId=4287e791-1b98-4963-8b94-281c50472683&messageId=1794372973956&pageSize=50&uiSource=channelChiclet"
        );
        assert_eq!(
            report_url(t, "5ad9ff0e-405b-4ad7-975f-22fbef6cc491", o, Some("1794372973956"), 0),
            "https://teams.microsoft.com/api/attendancereport/prod/attendancereport?threadId=19:ekCP@thread.tacv2&callId=5ad9ff0e-405b-4ad7-975f-22fbef6cc491&organizerObjectId=4287e791-1b98-4963-8b94-281c50472683&pageIndex=0&messageId=1794372973956&uiSource=channelChiclet"
        );
        assert!(history_url("19:meeting_a@thread.v2", o, None).ends_with("&pageSize=50&uiSource=meetingchat"));
    }

    #[test]
    fn content_disposition_names() {
        assert_eq!(file_name("attachment; filename=\"a b.csv\""), Some("a b.csv".into()));
        assert_eq!(file_name("attachment; filename=x.csv; filename*=UTF-8''r%C3%A9union.csv"), Some("réunion.csv".into()));
        assert_eq!(file_name("attachment; filename=\"../../etc/passwd\""), Some("passwd".into()));
        assert_eq!(file_name("inline"), None);
        // As the service sends it.
        assert_eq!(
            file_name("attachment; filename=OST%20calendar%20test_%20created%20from%20OST%20-%20Attendance%20report%2011-11-26.csv"),
            Some("OST calendar test_ created from OST - Attendance report 11-11-26.csv".into())
        );
    }

    #[test]
    fn rejects_bad_ids() {
        let o = "4287e791-1b98-4963-8b94-281c50472683";
        assert!(check("19:a@thread.tacv2", o, Some("17")).is_ok());
        assert!(check("19:a@thread.tacv2&x=1", o, None).is_err());
        assert!(check("19:a@thread.tacv2", "x", None).is_err());
        assert!(check("19:a@thread.tacv2", o, Some("1&x")).is_err());
    }
}
