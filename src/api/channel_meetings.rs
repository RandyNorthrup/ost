//! A channel's meetings, as Teams' View meetings lists them (the channel
//! header's meeting menu and its ··· menu; Teams 26304's contextual search
//! with the ContextualMeetings tab, worker getGroupCalendarEvents): the
//! team's group calendar (`GET graph/v1.0/groups/{group}/calendarView`)
//! narrowed to the channel by the meeting's SkypeTeamsProperties (`"cid"`),
//! three months back (newest first) and three months ahead (soonest first),
//! 50 of each, shown oldest first with "now" between them.

use anyhow::{Context, Result};
use serde::Serialize;

use super::client::TeamsClient;

/// The extended property Teams' meetings carry their channel in.
pub const TEAMS_PROPERTY: &str =
    "String {00020329-0000-0000-C000-000000000046} Name SkypeTeamsProperties";
/// What Teams asks for of each event.
/// (lastModifiedDateTime is left out: group calendarView doesn't take it
/// in $select.)
const SELECT: [&str; 18] = [
    "id",
    "subject",
    "iCalUId",
    "seriesMasterId",
    "type",
    "isCancelled",
    "isOrganizer",
    "responseRequested",
    "hasAttachments",
    "webLink",
    "bodyPreview",
    "start",
    "end",
    "location",
    "organizer",
    "responseStatus",
    "onlineMeeting",
    "singleValueExtendedProperties",
];
/// Teams' contextualSearchChannelMeetingsConfig: 50 a page, three months
/// either way.
pub const PAGE: usize = 50;
pub const RADIUS_MONTHS: i64 = 3;

/// One meeting of the channel.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct ChannelMeeting {
    pub id: String,
    pub subject: String,
    /// UTC, ISO with a Z.
    pub start: String,
    pub end: String,
    pub location: String,
    pub organizer_name: String,
    pub organizer_address: String,
    /// Who set it up (SkypeTeamsProperties' `uid`, as an MRI): a group
    /// calendar names the team itself as the organizer, so Teams' card
    /// reads the person from here.
    pub organizer_mri: String,
    pub is_organizer: bool,
    pub cancelled: bool,
    pub join_url: String,
    pub web_link: String,
    pub ical_uid: String,
    /// Graph's `type` (singleInstance, occurrence, exception,
    /// seriesMaster) and an occurrence's series, for its page.
    pub event_type: String,
    pub series_master_id: String,
}

/// The meetings, oldest first, and where "now" falls among them.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct ChannelMeetings {
    pub meetings: Vec<ChannelMeeting>,
    /// How many of `meetings` are before now.
    pub past: usize,
}

/// What the pane's filters narrow to.
#[derive(Debug, Clone, Default)]
pub struct Filters {
    /// Date filter (UTC ms), either end open.
    pub from_ms: Option<i64>,
    pub to_ms: Option<i64>,
    /// Organizer filter: their MRI (`8:orgid:…`).
    pub organizer: String,
}

/// OData string quoting (Teams' zG).
fn quote(s: &str) -> String {
    s.replace('\'', "''")
}

/// Teams' $filter (hOr): the channel, and the organizer when chosen.
pub fn filter(channel_id: &str, organizer: &str) -> String {
    let prop = quote(TEAMS_PROPERTY);
    let mut parts = vec![format!(
        "singleValueExtendedProperties/any(ep: ep/id eq '{prop}' and contains(ep/value, '{}'))",
        quote(&format!("\"cid\":\"{channel_id}\""))
    )];
    if !organizer.is_empty() {
        parts.push(format!(
            "singleValueExtendedProperties/any(ep: ep/id eq '{prop}' and contains(ep/value, '{}'))",
            quote(&format!("\"uid\":\"{organizer}\""))
        ));
    }
    parts.join(" and ")
}

/// A calendarView request's path and query, in Teams' order (fOr).
pub fn path(
    group_id: &str,
    channel_id: &str,
    organizer: &str,
    start: &str,
    end: &str,
    newest_first: bool,
) -> String {
    let enc = super::tabs::encode_uri_component;
    let q = [
        format!("startDateTime={}", enc(start)),
        format!("endDateTime={}", enc(end)),
        format!(
            "$expand={}",
            enc(&format!(
                "singleValueExtendedProperties($filter=id eq '{}')",
                quote(TEAMS_PROPERTY)
            ))
        ),
        format!("$filter={}", enc(&filter(channel_id, organizer))),
        "$count=true".to_string(),
        format!("$select={}", enc(&SELECT.join(","))),
        format!("$top={PAGE}"),
        "$skip=0".to_string(),
        format!(
            "$orderby={}",
            enc(if newest_first {
                "start/dateTime desc"
            } else {
                "start/dateTime"
            })
        ),
    ];
    format!("/groups/{}/calendarView?{}", enc(group_id), q.join("&"))
}

/// Graph's UTC times come without a zone (Teams' ip adds the Z).
fn utc(s: &str) -> String {
    if s.is_empty()
        || s.ends_with('Z')
        || s.rsplit_once(['+', '-'])
            .is_some_and(|(_, z)| z.contains(':') && z.len() == 5)
    {
        s.to_string()
    } else {
        format!("{s}Z")
    }
}

/// The meetings of a calendarView reply (Teams' We).
pub fn meetings_from(v: &serde_json::Value) -> Vec<ChannelMeeting> {
    let s = |e: &serde_json::Value, p: &str| {
        e.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let b = |e: &serde_json::Value, k: &str| e.get(k).and_then(|x| x.as_bool()).unwrap_or(false);
    v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .map(|e| ChannelMeeting {
            id: s(e, "/id"),
            subject: s(e, "/subject"),
            start: utc(&s(e, "/start/dateTime")),
            end: utc(&s(e, "/end/dateTime")),
            location: s(e, "/location/displayName"),
            organizer_name: s(e, "/organizer/emailAddress/name"),
            organizer_address: s(e, "/organizer/emailAddress/address"),
            organizer_mri: teams_uid(e),
            is_organizer: b(e, "isOrganizer"),
            cancelled: b(e, "isCancelled"),
            join_url: Some(s(e, "/onlineMeeting/joinUrl"))
                .filter(|u| u.starts_with("https://"))
                .unwrap_or_default(),
            web_link: Some(s(e, "/webLink"))
                .filter(|u| u.starts_with("https://"))
                .unwrap_or_default(),
            ical_uid: s(e, "/iCalUId"),
            event_type: s(e, "/type"),
            series_master_id: s(e, "/seriesMasterId"),
        })
        .collect()
}

/// The organizer's MRI from an event's SkypeTeamsProperties (`uid`).
pub(crate) fn teams_uid(e: &serde_json::Value) -> String {
    let props: serde_json::Value = e
        .pointer("/singleValueExtendedProperties/0/value")
        .and_then(|v| v.as_str())
        .and_then(|v| serde_json::from_str(v).ok())
        .unwrap_or_default();
    match props.get("uid").and_then(|u| u.as_str()) {
        Some(u) if u.starts_with("8:") => u.to_string(),
        Some(u) if uuid::Uuid::parse_str(u).is_ok() => format!("8:orgid:{u}"),
        _ => String::new(),
    }
}

/// Add to calendar (a channel meeting read from its team's calendar, not
/// in yours), as Teams' calendar service does (AddToMyCalendar,
/// worker `executeAddToMyCalendar`): `POST {mt}/beta/teams/{team
/// address}/addtomycalendar/{eventId}?useICalUId=false` (204), the team's
/// group mail as the address and the event id the group calendar gave.
pub async fn add_to_my_calendar(
    client: &TeamsClient,
    group_id: &str,
    event_id: &str,
) -> Result<()> {
    anyhow::ensure!(uuid::Uuid::parse_str(group_id).is_ok(), "Not a team");
    anyhow::ensure!(
        !event_id.is_empty() && !event_id.contains(['/', '?', '#']),
        "Not an event"
    );
    let g: serde_json::Value = client
        .graph_get(&format!("/groups/{group_id}?$select=mail"))
        .await?
        .json()
        .await
        .context("Team")?;
    let mail = g["mail"].as_str().unwrap_or_default();
    anyhow::ensure!(mail.contains('@'), "The team has no address");
    let (base, token) = super::tabs::middle_tier(client).await?;
    let enc = super::tabs::encode_uri_component;
    client
        .http()
        .post(format!(
            "{base}/beta/teams/{}/addtomycalendar/{}?useICalUId=false",
            enc(mail),
            enc(event_id)
        ))
        .bearer_auth(&token)
        .header("Content-Length", "0")
        .send()
        .await?
        .error_for_status()
        .context("Add to calendar")?;
    Ok(())
}

fn iso(t: jiff::Timestamp) -> String {
    crate::clock::iso_ms(t)
}

/// `t` moved by whole months in UTC, as JavaScript's setUTCMonth does
/// (a day past the month's end runs into the next).
fn months_from(t: jiff::Timestamp, months: i64) -> jiff::Timestamp {
    let iso = crate::clock::iso_ms(t);
    let n = |a: usize, b: usize| iso.get(a..b).and_then(|x| x.parse::<i64>().ok());
    let (Some(y), Some(m), Some(d), Some(h), Some(mi), Some(sec), Some(ms)) = (
        n(0, 4),
        n(5, 7),
        n(8, 10),
        n(11, 13),
        n(14, 16),
        n(17, 19),
        n(20, 23),
    ) else {
        return t;
    };
    let total = y * 12 + (m - 1) + months;
    let (year, month) = (total.div_euclid(12), total.rem_euclid(12) + 1);
    let Ok(first) = jiff::civil::Date::new(year as i16, month as i8, 1) else {
        return t;
    };
    let date = crate::clock::add_days(first, d - 1);
    crate::clock::as_utc(date.at(h as i8, mi as i8, sec as i8, 0))
        .and_then(|x| x.checked_add(jiff::SignedDuration::from_millis(ms)).ok())
        .unwrap_or(t)
}

async fn fetch(client: &TeamsClient, path: &str) -> Result<Vec<ChannelMeeting>> {
    let v: serde_json::Value = client
        .graph_get(path)
        .await?
        .json()
        .await
        .context("Channel meetings")?;
    Ok(meetings_from(&v))
}

fn by_start(m: &mut [ChannelMeeting]) {
    m.sort_by(|a, b| a.start.cmp(&b.start));
}

/// A channel's meetings as View meetings shows them first: with no date
/// filter (or one around now), the past and the coming three months in
/// two requests; a date range away from now in one.
pub async fn channel_meetings(
    client: &TeamsClient,
    group_id: &str,
    channel_id: &str,
    f: &Filters,
) -> Result<ChannelMeetings> {
    anyhow::ensure!(uuid::Uuid::parse_str(group_id).is_ok(), "Not a team");
    anyhow::ensure!(
        channel_id.starts_with("19:") && !channel_id.contains(['/', '?', '#', '\'']),
        "Not a channel"
    );
    anyhow::ensure!(
        f.organizer.is_empty()
            || f.organizer.starts_with("8:") && !f.organizer.contains(['\'', '"']),
        "Not a person"
    );
    let now = jiff::Timestamp::now();
    let from = f.from_ms.and_then(crate::clock::from_ms);
    let to = f.to_ms.and_then(crate::clock::from_ms);
    let around_now = from.is_none_or(|t| t <= now) && to.is_none_or(|t| t >= now);
    if !around_now {
        let start = from.unwrap_or_else(|| months_from(now, -RADIUS_MONTHS));
        let end = to.unwrap_or_else(|| months_from(now, RADIUS_MONTHS));
        let mut meetings = fetch(
            client,
            &path(
                group_id,
                channel_id,
                &f.organizer,
                &iso(start),
                &iso(end),
                false,
            ),
        )
        .await?;
        by_start(&mut meetings);
        let past = meetings.iter().filter(|m| m.start < iso(now)).count();
        return Ok(ChannelMeetings { meetings, past });
    }
    let past_start = from.unwrap_or_else(|| months_from(now, -RADIUS_MONTHS));
    let future_end = to.unwrap_or_else(|| months_from(now, RADIUS_MONTHS));
    let soon = now
        .checked_add(jiff::SignedDuration::from_millis(1))
        .unwrap_or(now);
    let past_path = path(
        group_id,
        channel_id,
        &f.organizer,
        &iso(past_start),
        &iso(now),
        true,
    );
    let future_path = path(
        group_id,
        channel_id,
        &f.organizer,
        &iso(soon),
        &iso(future_end),
        false,
    );
    let (past, future) = tokio::join!(fetch(client, &past_path), fetch(client, &future_path));
    let mut past = past?;
    by_start(&mut past);
    let mut meetings = past;
    let n = meetings.len();
    // A meeting that is on now overlaps both ranges (calendarView returns
    // what overlaps): it is shown once, before "now".
    let mut future: Vec<ChannelMeeting> = future?
        .into_iter()
        .filter(|f| f.id.is_empty() || !meetings.iter().any(|p| p.id == f.id))
        .collect();
    by_start(&mut future);
    meetings.extend(future);
    Ok(ChannelMeetings { meetings, past: n })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_request_is_teams() {
        let p = path(
            "0d0b1c43-9a3f-4d1b-8b5e-2d6c2a1b0f11",
            "19:ab@thread.tacv2",
            "",
            "2026-08-27T18:00:00.000Z",
            "2026-11-27T18:00:00.000Z",
            true,
        );
        assert!(p.starts_with("/groups/0d0b1c43-9a3f-4d1b-8b5e-2d6c2a1b0f11/calendarView?startDateTime=2026-08-27T18%3A00%3A00.000Z&endDateTime=2026-11-27T18%3A00%3A00.000Z&$expand=singleValueExtendedProperties(%24filter%3Did%20eq%20'String%20%7B00020329-0000-0000-C000-000000000046%7D%20Name%20SkypeTeamsProperties')&$filter="));
        assert!(p.ends_with("&$count=true&$select=id%2Csubject%2CiCalUId%2CseriesMasterId%2Ctype%2CisCancelled%2CisOrganizer%2CresponseRequested%2ChasAttachments%2CwebLink%2CbodyPreview%2Cstart%2Cend%2Clocation%2Corganizer%2CresponseStatus%2ConlineMeeting%2CsingleValueExtendedProperties&$top=50&$skip=0&$orderby=start%2FdateTime%20desc"));
        assert_eq!(
            filter("19:ab@thread.tacv2", "8:orgid:o"),
            "singleValueExtendedProperties/any(ep: ep/id eq 'String {00020329-0000-0000-C000-000000000046} Name SkypeTeamsProperties' and contains(ep/value, '\"cid\":\"19:ab@thread.tacv2\"')) and singleValueExtendedProperties/any(ep: ep/id eq 'String {00020329-0000-0000-C000-000000000046} Name SkypeTeamsProperties' and contains(ep/value, '\"uid\":\"8:orgid:o\"'))"
        );
    }

    #[test]
    fn months_move_as_javascript_moves_them() {
        let t = |s: &str| crate::clock::parse_instant(s).unwrap();
        let iso = |x| crate::clock::iso_ms(x);
        assert_eq!(
            iso(months_from(t("2026-11-27T18:05:01.250Z"), 3)),
            "2027-02-27T18:05:01.250Z"
        );
        assert_eq!(
            iso(months_from(t("2026-11-27T18:05:01.250Z"), -3)),
            "2026-08-27T18:05:01.250Z"
        );
        assert_eq!(
            iso(months_from(t("2026-11-30T00:00:00.000Z"), 3)),
            "2027-03-02T00:00:00.000Z"
        );
    }

    #[test]
    fn events_read_as_teams_reads_them() {
        let v = serde_json::json!({"value": [{
            "id": "AAMk", "subject": "Design review", "iCalUId": "040000",
            "isOrganizer": false, "isCancelled": false, "type": "occurrence", "seriesMasterId": "AAMkM",
            "start": {"dateTime": "2026-12-01T22:00:00.0000000", "timeZone": "UTC"},
            "end": {"dateTime": "2026-12-01T22:30:00.0000000", "timeZone": "UTC"},
            "location": {"displayName": "Microsoft Teams Meeting"},
            "organizer": {"emailAddress": {"name": "OST Test 1", "address": "ost-test1@example.com"}},
            "onlineMeeting": {"joinUrl": "https://teams.microsoft.com/l/meetup-join/x"},
            "webLink": "javascript:alert(1)",
            "singleValueExtendedProperties": [{"id": TEAMS_PROPERTY, "value": "{\"cid\":\"19:ab@thread.tacv2\",\"uid\":\"8:orgid:o1\"}"}]
        }]});
        let m = &meetings_from(&v)[0];
        assert_eq!(m.start, "2026-12-01T22:00:00.0000000Z");
        assert_eq!(
            (
                m.subject.as_str(),
                m.organizer_name.as_str(),
                m.location.as_str()
            ),
            ("Design review", "OST Test 1", "Microsoft Teams Meeting")
        );
        assert!(m.join_url.starts_with("https://") && m.web_link.is_empty());
        assert_eq!(m.organizer_mri, "8:orgid:o1");
        assert_eq!(
            (m.event_type.as_str(), m.series_master_id.as_str()),
            ("occurrence", "AAMkM")
        );
    }
}
