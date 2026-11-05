//! Calendar events from Microsoft Graph (`/me/calendarView`).

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One calendar event, times in UTC (ISO 8601).
#[derive(Debug, Clone, serde::Serialize)]
pub struct CalendarEvent {
    pub id: String,
    pub subject: String,
    pub start_utc: String,
    pub end_utc: String,
    pub is_all_day: bool,
    pub location: String,
    pub organizer: String,
    pub is_online_meeting: bool,
    /// Teams meeting join link, when there is one.
    pub join_url: Option<String>,
    /// Free, tentative, busy, oof, workingElsewhere.
    pub show_as: String,
}

/// Events overlapping `[start, end)` (UTC, `YYYY-MM-DDTHH:MM:SSZ`).
pub async fn calendar_view(
    client: &TeamsClient,
    start: &str,
    end: &str,
) -> Result<Vec<CalendarEvent>> {
    let path = format!(
        "/me/calendarView?startDateTime={start}&endDateTime={end}&$top=250&$orderby=start/dateTime\
         &$select=id,subject,start,end,isAllDay,location,organizer,isOnlineMeeting,onlineMeeting,showAs"
    );
    let v: serde_json::Value = client
        .graph_get(&path)
        .await?
        .json()
        .await
        .context("Calendar reply")?;
    Ok(parse_events(&v))
}

fn parse_events(v: &serde_json::Value) -> Vec<CalendarEvent> {
    let s = |e: &serde_json::Value, p: &str| {
        e.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    // Graph sends "2026-11-05T15:00:00.0000000" in UTC when no time zone
    // is requested; mark it as UTC so clients parse it right.
    let utc = |t: String| {
        if t.is_empty() || t.ends_with('Z') {
            t
        } else {
            format!("{}Z", t.split('.').next().unwrap_or(&t))
        }
    };
    v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .map(|e| CalendarEvent {
            id: s(e, "/id"),
            subject: s(e, "/subject"),
            start_utc: utc(s(e, "/start/dateTime")),
            end_utc: utc(s(e, "/end/dateTime")),
            is_all_day: e.get("isAllDay").and_then(|b| b.as_bool()).unwrap_or(false),
            location: s(e, "/location/displayName"),
            organizer: s(e, "/organizer/emailAddress/name"),
            is_online_meeting: e
                .get("isOnlineMeeting")
                .and_then(|b| b.as_bool())
                .unwrap_or(false),
            join_url: e
                .pointer("/onlineMeeting/joinUrl")
                .and_then(|x| x.as_str())
                .map(str::to_string),
            show_as: s(e, "/showAs"),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_graph_events_as_utc() {
        let v = serde_json::json!({"value": [{
            "id": "e1", "subject": "Standup",
            "start": {"dateTime": "2026-11-05T15:00:00.0000000", "timeZone": "UTC"},
            "end": {"dateTime": "2026-11-05T15:30:00.0000000", "timeZone": "UTC"},
            "isAllDay": false, "location": {"displayName": "Room 1"},
            "organizer": {"emailAddress": {"name": "Ada"}},
            "isOnlineMeeting": true, "onlineMeeting": {"joinUrl": "https://teams.microsoft.com/l/meetup-join/x"},
            "showAs": "busy"
        }]});
        let e = &parse_events(&v)[0];
        assert_eq!(e.start_utc, "2026-11-05T15:00:00Z");
        assert_eq!(e.end_utc, "2026-11-05T15:30:00Z");
        assert_eq!(e.organizer, "Ada");
        assert!(e.join_url.as_deref().unwrap().contains("meetup-join"));
    }
}
