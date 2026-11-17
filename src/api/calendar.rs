//! Calendar events from Microsoft Graph (`/me/calendarView`).

use anyhow::{Context, Result, bail};

use super::client::TeamsClient;

/// One calendar event, times in UTC (ISO 8601).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct CalendarEvent {
    /// Graph's immutable id (the same id Outlook on the web uses, in URL
    /// form), so Teams' Outlook calls take it as is.
    pub id: String,
    pub subject: String,
    pub start_utc: String,
    pub end_utc: String,
    pub is_all_day: bool,
    pub location: String,
    pub organizer: String,
    pub organizer_address: String,
    pub is_online_meeting: bool,
    /// Teams meeting join link, when there is one.
    pub join_url: Option<String>,
    /// Free, tentative, busy, oof, workingElsewhere.
    pub show_as: String,
    /// The start of the description, as plain text.
    pub preview: String,
    /// You organise it (you can edit or cancel it).
    pub is_organizer: bool,
    pub ical_uid: String,
    /// singleInstance, occurrence, exception or seriesMaster.
    pub event_type: String,
    pub series_master_id: String,
    /// Your answer: none, organizer, tentativelyAccepted, accepted,
    /// declined, notResponded.
    pub response: String,
    pub response_requested: bool,
    pub attendees: Vec<Attendee>,
    pub is_cancelled: bool,
    pub categories: Vec<String>,
    pub sensitivity: String,
    /// A channel meeting's channel (`19:…@thread.tacv2`) and the post it
    /// lives in, from its join link.
    pub channel_id: String,
    pub channel_message_id: String,
    pub allow_new_time_proposals: bool,
}

/// One invitee and their answer.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct Attendee {
    pub name: String,
    pub address: String,
    /// required, optional or resource.
    pub kind: String,
    /// none, accepted, tentativelyAccepted, declined, notResponded.
    pub response: String,
}

/// Events overlapping `[start, end)` (UTC, `YYYY-MM-DDTHH:MM:SSZ`).
pub async fn calendar_view(
    client: &TeamsClient,
    start: &str,
    end: &str,
) -> Result<Vec<CalendarEvent>> {
    let path = format!(
        "/me/calendarView?startDateTime={start}&endDateTime={end}&$top=250&$orderby=start/dateTime\
         &$select=id,subject,start,end,isAllDay,location,organizer,isOnlineMeeting,onlineMeeting,showAs,bodyPreview,isOrganizer,\
         iCalUId,type,seriesMasterId,responseStatus,responseRequested,attendees,isCancelled,categories,sensitivity,allowNewTimeProposals"
    );
    // Immutable ids, as Teams' calendar (Outlook on the web) asks for them.
    let v: serde_json::Value = client
        .graph_get_with(&path, &[("Prefer", "IdType=\"ImmutableId\"")])
        .await?
        .json()
        .await
        .context("Calendar reply")?;
    Ok(parse_events(&v))
}

/// Create an event in your calendar (`start`/`end` in UTC,
/// `YYYY-MM-DDTHH:MM:SSZ`); with `teams_meeting` it gets a Teams meeting
/// link, as Teams' New meeting does. Attendees are e-mail addresses.
pub async fn create_event(
    client: &TeamsClient,
    subject: &str,
    start: &str,
    end: &str,
    attendees: &[String],
    teams_meeting: bool,
) -> Result<CalendarEvent> {
    let body = new_event_body(subject, start, end, attendees, teams_meeting)?;
    let v: serde_json::Value = client
        .graph_post("/me/events", &body)
        .await?
        .json()
        .await
        .context("Create event reply")?;
    parse_events(&serde_json::json!({ "value": [v] }))
        .into_iter()
        .next()
        .context("Create event reply had no event")
}

/// Change an event's title and time (UTC). For a meeting you organise,
/// Outlook sends the attendees the update.
pub async fn update_event(
    client: &TeamsClient,
    id: &str,
    subject: &str,
    start: &str,
    end: &str,
) -> Result<()> {
    let mut body = new_event_body(subject, start, end, &[], false)?;
    // Leave the invitees as they are.
    if let Some(o) = body.as_object_mut() {
        o.remove("attendees");
    }
    client
        .graph_patch(&format!("/me/events/{}", event_path_id(id)?), &body)
        .await?;
    Ok(())
}

/// Delete an event; for a meeting you organise this cancels it for
/// everyone, as Teams' Delete does.
pub async fn delete_event(client: &TeamsClient, id: &str) -> Result<()> {
    client
        .graph_delete(&format!("/me/events/{}", event_path_id(id)?))
        .await?;
    Ok(())
}

/// A meeting's calendar event as its Meeting info pane needs it: the body
/// (HTML) and, for a series, its recurrence (Graph's `pattern` and
/// `range`).
#[derive(Debug, Clone, Default)]
pub struct MeetingEvent {
    pub body_html: String,
    pub recurrence: Option<serde_json::Value>,
}

/// Your calendar's event for a meeting, by its iCalUId (Teams' calendar
/// service `userEventUsingICalUId`). For a series this is the series.
pub async fn event_by_ical_uid(client: &TeamsClient, ical_uid: &str) -> Result<Option<MeetingEvent>> {
    if ical_uid.is_empty() || !ical_uid.bytes().all(|b| b.is_ascii_alphanumeric()) {
        anyhow::bail!("Not an iCalUId");
    }
    let path = format!("/me/events?$filter=iCalUId%20eq%20'{ical_uid}'&$select=body,recurrence,type&$top=1");
    let v: serde_json::Value = client
        .graph_get(&path)
        .await?
        .json()
        .await
        .context("Failed to read the meeting's calendar event")?;
    Ok(v.pointer("/value/0").map(|e| MeetingEvent {
        body_html: e
            .pointer("/body/content")
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .to_string(),
        recurrence: e.get("recurrence").filter(|r| !r.is_null()).cloned(),
    }))
}

/// A calendar event's body (HTML), by its id: a Teams meeting's
/// invitation, with its dial-in block when the meeting has one.
pub async fn event_body(client: &TeamsClient, id: &str) -> Result<String> {
    let v: serde_json::Value = client
        .graph_get(&format!("/me/events/{}?$select=body", event_path_id(id)?))
        .await?
        .json()
        .await
        .context("Failed to read the calendar event")?;
    Ok(v.pointer("/body/content").and_then(|c| c.as_str()).unwrap_or_default().to_string())
}

/// Graph event ids are base64url-ish; refuse anything else in a path.
fn event_path_id(id: &str) -> Result<&str> {
    if id.is_empty()
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_=".contains(&b))
    {
        anyhow::bail!("Not an event id");
    }
    Ok(id)
}

fn new_event_body(
    subject: &str,
    start: &str,
    end: &str,
    attendees: &[String],
    teams_meeting: bool,
) -> Result<serde_json::Value> {
    let bare = |t: &str| -> Result<String> {
        let t = t.trim_end_matches('Z');
        if t.len() < 16 || !t.as_bytes()[..4].iter().all(u8::is_ascii_digit) {
            anyhow::bail!("Not a UTC time: {t}");
        }
        Ok(t.to_string())
    };
    let mut body = serde_json::json!({
        "subject": if subject.trim().is_empty() { "New meeting" } else { subject.trim() },
        "start": { "dateTime": bare(start)?, "timeZone": "UTC" },
        "end": { "dateTime": bare(end)?, "timeZone": "UTC" },
        "attendees": attendees.iter().filter(|a| a.contains('@')).map(|a| serde_json::json!({
            "emailAddress": { "address": a },
            "type": "required"
        })).collect::<Vec<_>>(),
    });
    if teams_meeting {
        body["isOnlineMeeting"] = serde_json::json!(true);
        body["onlineMeetingProvider"] = serde_json::json!("teamsForBusiness");
    }
    Ok(body)
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
        .map(|e| {
            let join_url = e
                .pointer("/onlineMeeting/joinUrl")
                .and_then(|x| x.as_str())
                .map(str::to_string);
            let (channel_id, channel_message_id) = join_url
                .as_deref()
                .and_then(crate::calling::outgoing::MeetingLink::parse)
                .filter(|l| l.thread_id.ends_with("@thread.tacv2"))
                .map(|l| (l.thread_id, l.message_id))
                .unwrap_or_default();
            let all_day = e.get("isAllDay").and_then(|b| b.as_bool()).unwrap_or(false);
            let floating = |t: String| t.split('.').next().unwrap_or_default().trim_end_matches('Z').to_string();
            CalendarEvent {
                id: s(e, "/id"),
                subject: s(e, "/subject"),
                // An all-day event's dates are its own days, not UTC instants:
                // local midnights (no Z), as Teams draws them.
                start_utc: if all_day { floating(s(e, "/start/dateTime")) } else { utc(s(e, "/start/dateTime")) },
                end_utc: if all_day { floating(s(e, "/end/dateTime")) } else { utc(s(e, "/end/dateTime")) },
                is_all_day: all_day,
                location: s(e, "/location/displayName"),
                organizer: s(e, "/organizer/emailAddress/name"),
                organizer_address: s(e, "/organizer/emailAddress/address"),
                is_online_meeting: e
                    .get("isOnlineMeeting")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false),
                join_url,
                show_as: s(e, "/showAs"),
                preview: s(e, "/bodyPreview"),
                is_organizer: e
                    .get("isOrganizer")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false),
                ical_uid: s(e, "/iCalUId"),
                event_type: s(e, "/type"),
                series_master_id: s(e, "/seriesMasterId"),
                response: s(e, "/responseStatus/response"),
                response_requested: e.get("responseRequested").and_then(|b| b.as_bool()).unwrap_or(true),
                attendees: attendees_of(e),
                is_cancelled: e.get("isCancelled").and_then(|b| b.as_bool()).unwrap_or(false),
                categories: e
                    .get("categories")
                    .and_then(|c| c.as_array())
                    .map(|a| a.iter().filter_map(|c| c.as_str().map(str::to_string)).collect())
                    .unwrap_or_default(),
                sensitivity: s(e, "/sensitivity"),
                channel_id,
                channel_message_id,
                allow_new_time_proposals: e.get("allowNewTimeProposals").and_then(|b| b.as_bool()).unwrap_or(false),
            }
        })
        .collect()
}

fn attendees_of(e: &serde_json::Value) -> Vec<Attendee> {
    let s = |a: &serde_json::Value, p: &str| a.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    e.get("attendees")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .map(|a| Attendee {
            name: s(a, "/emailAddress/name"),
            address: s(a, "/emailAddress/address"),
            kind: s(a, "/type"),
            response: s(a, "/status/response"),
        })
        .collect()
}

/// An event as its page needs it: the body (HTML), the invitees with
/// their answers and, for a series, its recurrence.
pub async fn event_detail(client: &TeamsClient, id: &str) -> Result<serde_json::Value> {
    let v: serde_json::Value = client
        .graph_get_with(
            &format!(
                "/me/events/{}?$select=body,attendees,recurrence,onlineMeeting,type,seriesMasterId",
                event_path_id(id)?
            ),
            &[("Prefer", "IdType=\"ImmutableId\"")],
        )
        .await?
        .json()
        .await
        .context("Failed to read the event")?;
    Ok(serde_json::json!({
        "id": id,
        "body_html": v.pointer("/body/content").and_then(|c| c.as_str()).unwrap_or_default(),
        "attendees": attendees_of(&v),
        "recurrence": v.get("recurrence").cloned().unwrap_or(serde_json::Value::Null),
        "conference_id": v.pointer("/onlineMeeting/conferenceId").and_then(|c| c.as_str()).unwrap_or_default(),
    }))
}

/// Answer an invitation (the card's Accept / Tentative / Decline, the
/// event page's RSVP with note): the answer, whether the organizer gets an
/// e-mail ("Email organizer") and the note. Teams' calendar sends this
/// to Outlook on the web (`owa/service.svc?action=RespondToCalendarEvent`:
/// the occurrence or series id, `Response`, `SendResponse`, `Notes` as
/// `<div>…</div>`); that service refuses Teams' own token (500,
/// ExAssertException for app 1fec8e78), so OST asks Exchange the same
/// through Graph (`/me/events/{id}/accept|tentativelyAccept|decline`,
/// `{comment, sendResponse}`). For "All events in the series" the id is the
/// series'. Follow has no Graph or Outlook call OST can make.
pub async fn respond(client: &TeamsClient, event_id: &str, response: &str, send_response: bool, note: &str) -> Result<()> {
    let action = match response {
        "Accept" => "accept",
        "Tentative" => "tentativelyAccept",
        "Decline" => "decline",
        "Follow" => bail!("Follow isn't available here"),
        other => bail!("Not a response: {other}"),
    };
    let body = serde_json::json!({ "comment": note.trim(), "sendResponse": send_response });
    client
        .graph_post(&format!("/me/events/{}/{action}", event_path_id(event_id)?), &body)
        .await?;
    Ok(())
}

/// Your mailbox's time zone (its Windows name, e.g. "Pacific Standard Time").
pub async fn mailbox_time_zone() -> String {
    static TZ: tokio::sync::OnceCell<String> = tokio::sync::OnceCell::const_new();
    TZ.get_or_init(|| async {
        let r = async {
            let client = TeamsClient::new().await?;
            let v: serde_json::Value = client.graph_get("/me/mailboxSettings/timeZone").await?.json().await?;
            Ok::<_, anyhow::Error>(v.get("value").and_then(|t| t.as_str()).unwrap_or_default().to_string())
        }
        .await;
        r.ok().filter(|t| !t.is_empty()).unwrap_or_else(|| "UTC".into())
    })
    .await
    .clone()
}

/// The organizer, as Teams' scheduling form names them.
#[derive(Debug, Clone, Default, serde::Deserialize)]
pub struct Me {
    pub name: String,
    pub mail: String,
    pub mri: String,
}

/// Free/busy for people as Teams' form asks for it (`PUT
/// {mt}/v2.0/me/calendars/schedules`, "AttendeeAvailabilityOnly"): each
/// address's strongest status over `[start, end)` (RFC 3339), and your time
/// zone as the middle tier names it ("PacificSt", the form's
/// eventTimeZone).
pub async fn availability(
    client: &TeamsClient,
    me: &Me,
    people: &[(String, String)],
    start: &str,
    end: &str,
) -> Result<(serde_json::Value, String)> {
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let mut attendees = vec![serde_json::json!({"type": "Organizer", "address": me.mail, "name": me.name, "mri": me.mri, "role": "Admin"})];
    for (mail, name) in people {
        attendees.push(serde_json::json!({"type": "Required", "address": mail, "name": name, "role": "Admin"}));
    }
    let s = chrono::DateTime::parse_from_rfc3339(start)?;
    let e = chrono::DateTime::parse_from_rfc3339(end)?;
    // As Teams asks: UTC with milliseconds, the day's start, whole days.
    let utc = |d: chrono::DateTime<chrono::FixedOffset>| d.with_timezone(&chrono::Utc).format("%Y-%m-%dT%H:%M:%S.000Z").to_string();
    let day0 = s.date_naive().and_hms_opt(0, 0, 0).and_then(|d| d.and_local_timezone(*s.offset()).single()).unwrap_or(s);
    let days = ((e - day0).num_hours() + 23) / 24;
    let body = serde_json::json!({
        "attendees": attendees,
        "minimumSuggestionQuality": "Good",
        "numberOfDays": days.max(1),
        "requestType": "AttendeeAvailabilityOnly",
        "startDate": utc(day0), "startTime": utc(day0), "startDateTimeZone": "Utc",
        "meetingDurationInMinutes": (e - s).num_minutes().max(0),
        "endTime": utc(day0 + chrono::Duration::days(days.max(1)))
    });
    let v: serde_json::Value = client
        .http()
        .put(format!("{base}/v2.0/me/calendars/schedules"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("Availability")?
        .json()
        .await?;
    let mut out = serde_json::Map::new();
    let mut tz = String::new();
    for u in v.as_array().into_iter().flatten() {
        let who = u.get("userPrincipalName").and_then(|x| x.as_str()).unwrap_or_default().to_lowercase();
        if who == me.mail.to_lowercase() {
            tz = u.get("timeZone").and_then(|x| x.as_str()).unwrap_or_default().to_string();
        }
        out.insert(who, serde_json::json!(busiest(u, s, e)));
    }
    Ok((serde_json::Value::Object(out), tz))
}

/// The strongest status overlapping `[s, e)`, as Teams' attendee chips
/// show it.
fn busiest(u: &serde_json::Value, s: chrono::DateTime<chrono::FixedOffset>, e: chrono::DateTime<chrono::FixedOffset>) -> &'static str {
    let named = |st: &str| match st {
        "Oof" => ("Oof", 4),
        "Busy" => ("Busy", 3),
        "Tentative" => ("Tentative", 2),
        "WorkingElsewhere" => ("WorkingElsewhere", 1),
        _ => ("Free", 0),
    };
    let mut best = ("Free", 0);
    for ev in u.get("freeBusyEvents").and_then(|x| x.as_array()).into_iter().flatten() {
        let t = |k: &str| ev.get(k).and_then(|x| x.as_str()).and_then(|x| chrono::DateTime::parse_from_rfc3339(x).ok());
        let (Some(a), Some(b)) = (t("startTime"), t("endTime")) else { continue };
        if a < e && b > s {
            let n = named(ev.get("freeBusyStatus").and_then(|x| x.as_str()).unwrap_or_default());
            if n.1 > best.1 {
                best = n;
            }
        }
    }
    best.0
}

/// The scheduling form's fields (as MeetingForm.qml sends them).
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct MeetingForm {
    pub subject: String,
    /// Local times with their offset (`2026-11-17T15:00:00-08:00`).
    pub start: String,
    pub end: String,
    pub all_day: bool,
    pub attendees: Vec<FormAttendee>,
    pub location: String,
    pub body_html: String,
    pub online: bool,
    pub channel: Option<FormChannel>,
    /// Teams' {pattern, range} (patternType 1 daily … 5 yearly).
    pub recurrence: Option<serde_json::Value>,
    pub show_as: String,
    pub editing_id: String,
    pub send_personal_invites: bool,
    /// The middle tier's name for your time zone ("PacificSt").
    pub time_zone: String,
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct FormAttendee {
    pub address: String,
    pub name: String,
    /// "Required" or "Optional".
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FormChannel {
    pub team_id: String,
    pub team_name: String,
    pub channel_id: String,
    pub channel_name: String,
}

/// The calendar event Teams' form sends to the middle tier (measured
/// 2026-11-17: Send with attendees, Save without, a channel meeting).
fn mt_event(form: &MeetingForm, me: &Me, group_mail: Option<&str>) -> Result<serde_json::Value> {
    let start = chrono::DateTime::parse_from_rfc3339(&form.start).with_context(|| format!("Not a time: {}", form.start))?;
    chrono::DateTime::parse_from_rfc3339(&form.end).with_context(|| format!("Not a time: {}", form.end))?;
    let utc_offset = i64::from(start.offset().local_minus_utc()) / 60;
    let people: Vec<&FormAttendee> = form.attendees.iter().filter(|a| a.address.contains('@')).collect();
    let mut attendees = vec![serde_json::json!({
        "address": me.mail, "mri": me.mri, "name": me.name, "role": "Admin", "type": "Organizer"
    })];
    for a in &people {
        attendees.push(serde_json::json!({
            "address": a.address,
            "name": if a.name.is_empty() { &a.address } else { &a.name },
            "role": "Admin",
            "type": if a.kind == "Optional" { "Optional" } else { "Required" }
        }));
    }
    if let Some(g) = group_mail {
        attendees.push(serde_json::json!({"address": g, "role": "User", "type": "Required"}));
    }
    let id = (0..5).map(|_| rand_u32().to_string()).collect::<Vec<_>>().join("-");
    let mut ev = serde_json::json!({
        "attendees": attendees,
        "bodyContent": form.body_html,
        "clientOptimisticEventId": id,
        "doNotForward": false,
        "emptyBodyPlaceholder": "Scheduled a meeting",
        "endTime": form.end,
        "eventTimeZone": if form.time_zone.is_empty() { "UTC" } else { &form.time_zone },
        "eventType": if form.recurrence.is_some() { "RecurringMaster" } else { "Single" },
        "isAllDayEvent": form.all_day,
        "isOrganizer": true,
        "isPrivate": false,
        "isReminderSet": true,
        "isResponseRequested": true,
        "joinMeetingLabel": "Join Microsoft Teams Online Meeting",
        "location": form.location,
        "meetingTemplateId": "default",
        "organizerAddress": me.mail,
        "organizerName": me.name,
        "primarySpokenLanguage": "en-us",
        "reminderMinutesBeforeStart": 15,
        "sensitivityLabelId": "",
        "showAs": if form.show_as.is_empty() { "Busy" } else { &form.show_as },
        "startTime": form.start,
        "subject": form.subject.trim(),
        "utcOffset": utc_offset,
    });
    if let Some(r) = &form.recurrence {
        ev["eventRecurrencePattern"] = r.get("pattern").cloned().unwrap_or_default();
        ev["eventRecurrenceRange"] = r.get("range").cloned().unwrap_or_default();
    }
    if let Some(c) = &form.channel {
        ev["categories"] = serde_json::json!([]);
        ev["mailboxAddress"] = serde_json::json!(group_mail.unwrap_or_default());
        ev["skypeTeamsData"] = serde_json::json!(serde_json::json!({"cid": c.channel_id, "uid": me.mri, "type": 0}).to_string());
    } else {
        ev["isAppointment"] = serde_json::json!(people.is_empty());
        ev["skypeTeamsData"] = serde_json::json!(serde_json::json!({"uid": me.mri, "type": 0, "private": true}).to_string());
        ev["TransactionId"] = serde_json::json!(id);
    }
    Ok(ev)
}

fn rand_u32() -> u32 {
    let u = uuid::Uuid::new_v4();
    let b = u.as_bytes();
    u32::from_le_bytes([b[0], b[1], b[2], b[3]])
}

/// Schedule a meeting as Teams' form does (its Send or Save):
/// - a channel meeting goes to the team's group calendar
///   (`POST {mt}/v2.0/groups/smtp:<group>/calendars/default/events?isOnlineMeeting=true`),
///   and the service posts it in the channel;
/// - an online meeting first gets its Teams meeting (`POST
///   {mt}/beta/me/calendarEvents/privateMeeting/schedulingService/create`),
///   then `POST {mt}/v2.0/me/calendars/default/events?isOnlineMeeting=true`
///   with both;
/// - anything else is a plain event in your calendar.
///
/// Answers the middle tier's event (objectId, join links).
pub async fn schedule(client: &TeamsClient, form: &MeetingForm, me: &Me) -> Result<serde_json::Value> {
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let post = |url: String, body: serde_json::Value| {
        let token = token.clone();
        async move {
            let r = client.http().post(&url).bearer_auth(&token).json(&body).send().await?;
            let status = r.status();
            let text = r.text().await.unwrap_or_default();
            if !status.is_success() {
                bail!("{status}: {}", text.chars().take(300).collect::<String>());
            }
            Ok::<serde_json::Value, anyhow::Error>(serde_json::from_str(&text).unwrap_or_default())
        }
    };
    if let Some(c) = &form.channel {
        let mail = group_mail(client, &c.team_id).await?;
        let ev = mt_event(form, me, Some(&mail))?;
        let url = format!("{base}/v2.0/groups/smtp:{mail}/calendars/default/events?isOnlineMeeting=true&shouldDecryptData=false");
        return Ok(post(url, ev).await?.get("value").cloned().unwrap_or_default());
    }
    let ev = mt_event(form, me, None)?;
    let body = if form.online {
        let sse = post(
            format!("{base}/beta/me/calendarEvents/privateMeeting/schedulingService/create"),
            serde_json::json!({"isStreamEnabled": false, "meetingType": "Scheduled"}),
        )
        .await?;
        serde_json::json!({"calendarEvent": ev, "schedulingServiceEvent": sse.get("value").cloned().unwrap_or_default()})
    } else {
        serde_json::json!({"calendarEvent": ev})
    };
    let url = format!("{base}/v2.0/me/calendars/default/events?isOnlineMeeting={}&shouldDecryptData=true", form.online);
    Ok(post(url, body).await?.get("value").cloned().unwrap_or_default())
}

/// The calendar's Meet now ("Start a meeting now" ▸ Start meeting, or Get
/// a link to share): a meeting made now (`POST
/// {mt}/beta/me/calendarEvents/privateMeeting/schedulingService/create`,
/// meetingType "MeetNow"). Answers its join link.
pub async fn meet_now(client: &TeamsClient, subject: &str) -> Result<String> {
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/me/calendarEvents/privateMeeting/schedulingService/create"))
        .bearer_auth(&token)
        .json(&serde_json::json!({"meetingType": "MeetNow", "isStreamEnabled": false, "subject": subject, "unhideChatThread": true}))
        .send()
        .await?
        .error_for_status()
        .context("Meet now")?
        .json()
        .await?;
    v.pointer("/value/links/join")
        .and_then(|j| j.as_str())
        .map(str::to_string)
        .context("Meet now gave no join link")
}

/// Join with an ID: the meeting in your calendar (90 days either side)
/// whose invitation carries this meeting ID and passcode. Teams itself
/// hands the ID and passcode to the calling service (its conversation's
/// `meetingData`); OST's call stack joins by link, so it finds the link.
pub async fn meeting_by_id(client: &TeamsClient, meeting_id: &str, passcode: &str) -> Result<Option<(String, String, String, String)>> {
    let digits: String = meeting_id.chars().filter(char::is_ascii_digit).collect();
    if digits.len() < 9 {
        bail!("Not a meeting ID");
    }
    let now = chrono::Utc::now();
    let fmt = |d: chrono::DateTime<chrono::Utc>| d.format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let path = format!(
        "/me/calendarView?startDateTime={}&endDateTime={}&$top=500&$select=subject,start,end,bodyPreview,onlineMeeting",
        fmt(now - chrono::Duration::days(90)),
        fmt(now + chrono::Duration::days(90))
    );
    let v: serde_json::Value = client.graph_get(&path).await?.json().await?;
    for e in v.get("value").and_then(|x| x.as_array()).into_iter().flatten() {
        let preview = e.get("bodyPreview").and_then(|x| x.as_str()).unwrap_or_default();
        let flat: String = preview.chars().filter(|c| !c.is_whitespace()).collect();
        let Some(join) = e.pointer("/onlineMeeting/joinUrl").and_then(|x| x.as_str()) else { continue };
        if flat.contains(&format!("MeetingID:{digits}")) && (passcode.is_empty() || flat.contains(&format!("Passcode:{passcode}"))) {
            let s = |p: &str| e.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
            let utc = |t: String| if t.is_empty() || t.ends_with('Z') { t } else { format!("{}Z", t.split('.').next().unwrap_or(&t)) };
            return Ok(Some((join.to_string(), s("/subject"), utc(s("/start/dateTime")), utc(s("/end/dateTime")))));
        }
    }
    Ok(None)
}

/// A team's group mailbox (its calendar's `smtp:` address).
async fn group_mail(client: &TeamsClient, team_id: &str) -> Result<String> {
    if team_id.is_empty() || !team_id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Not a team id");
    }
    let v: serde_json::Value = client.graph_get(&format!("/groups/{team_id}?$select=mail")).await?.json().await?;
    v.get("mail")
        .and_then(|m| m.as_str())
        .filter(|m| m.contains('@'))
        .map(str::to_string)
        .context("The team has no mailbox")
}

/// Send an update for a meeting you organise (Teams' Send update) with
/// the fields the form edits; Outlook sends the attendees the update.
pub async fn update_meeting(client: &TeamsClient, id: &str, form: &MeetingForm) -> Result<()> {
    let tz = mailbox_time_zone().await;
    let local = |t: &str| -> Result<String> {
        let d = chrono::DateTime::parse_from_rfc3339(t).with_context(|| format!("Not a time: {t}"))?;
        Ok(d.naive_local().format("%Y-%m-%dT%H:%M:%S").to_string())
    };
    let mut body = serde_json::json!({
        "subject": form.subject.trim(),
        "start": { "dateTime": local(&form.start)?, "timeZone": tz },
        "end": { "dateTime": local(&form.end)?, "timeZone": tz },
        "isAllDay": form.all_day,
        "location": { "displayName": form.location },
        "body": { "contentType": "html", "content": form.body_html },
        "attendees": form.attendees.iter().filter(|a| a.address.contains('@')).map(|a| serde_json::json!({
            "emailAddress": { "address": a.address, "name": a.name },
            "type": if a.kind == "Optional" { "optional" } else { "required" }
        })).collect::<Vec<_>>(),
    });
    if !form.show_as.is_empty() {
        body["showAs"] = serde_json::json!(graph_show_as(&form.show_as));
    }
    client.graph_patch(&format!("/me/events/{}", event_path_id(id)?), &body).await?;
    Ok(())
}

fn graph_show_as(s: &str) -> &'static str {
    match s {
        "Free" => "free",
        "Tentative" => "tentative",
        "Oof" | "Away" => "oof",
        "WorkingElsewhere" => "workingElsewhere",
        _ => "busy",
    }
}

/// Cancel a meeting you organise, with an optional note (Teams' "Cancel
/// meeting?"). A channel meeting is cancelled in its team's calendar and
/// post (`PUT {mt}/v2.0/groups/smtp:<group>/calendars/events/<iCalUId>/cancel`,
/// measured 2026-11-17).
pub async fn cancel_meeting(client: &TeamsClient, ev: &serde_json::Value, team_id: &str, note: &str) -> Result<()> {
    let s = |k: &str| ev.get(k).and_then(|v| v.as_str()).unwrap_or_default().to_string();
    if !s("channel_id").is_empty() {
        let (base, token) = crate::api::tabs::middle_tier(client).await?;
        let mail = group_mail(client, team_id).await?;
        let uid = s("ical_uid").to_lowercase();
        if uid.is_empty() || !uid.bytes().all(|b| b.is_ascii_hexdigit()) {
            bail!("Not an iCalUId");
        }
        let kind = match s("event_type").as_str() {
            "occurrence" => "Occurrence",
            "exception" => "Exception",
            "seriesMaster" => "RecurringMaster",
            _ => "Single",
        };
        let body = serde_json::json!({
            "conversationId": s("channel_id"),
            "messageId": s("channel_message_id"),
            "rootMessageId": s("channel_message_id"),
            "cancellationMessageFormat": "The meeting \"{0}\" is cancelled",
            "fetchEventContract": {
                "eventType": kind,
                "eventTimeZone": "UTC",
                "startTime": s("start_utc").replace('Z', ".000Z"),
            }
        });
        client
            .http()
            .put(format!("{base}/v2.0/groups/smtp:{mail}/calendars/events/{uid}/cancel"))
            .bearer_auth(&token)
            .json(&body)
            .send()
            .await?
            .error_for_status()
            .context("Cancel the channel meeting")?;
        return Ok(());
    }
    client
        .graph_post(&format!("/me/events/{}/cancel", event_path_id(&s("id"))?), &serde_json::json!({ "comment": note }))
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn scheduling_bodies_match_teams_form() {
        let me = super::Me { name: "OST Test 1".into(), mail: "t1@x.com".into(), mri: "8:orgid:1".into() };
        let form: super::MeetingForm = serde_json::from_value(serde_json::json!({
            "subject": " Sync ", "start": "2026-11-17T15:00:00-08:00", "end": "2026-11-17T15:30:00-08:00",
            "attendees": [{"address": "t2@x.com", "name": "OST Test 2", "type": "Required"}, {"address": "nope"}],
            "location": "Room 9", "bodyHtml": "<p>b</p>", "online": true, "timeZone": "PacificSt"
        }))
        .unwrap();
        let e = super::mt_event(&form, &me, None).unwrap();
        assert_eq!(e["subject"], "Sync");
        assert_eq!(e["utcOffset"], -480);
        assert_eq!(e["eventType"], "Single");
        assert_eq!(e["isAppointment"], false);
        assert_eq!(e["attendees"].as_array().unwrap().len(), 2);
        assert_eq!(e["attendees"][0]["type"], "Organizer");
        assert_eq!(e["eventTimeZone"], "PacificSt");
        let mut ch = form.clone();
        ch.channel = Some(super::FormChannel { channel_id: "19:c@thread.tacv2".into(), ..Default::default() });
        ch.recurrence = Some(serde_json::json!({"pattern": {"patternType": 2, "weekly": {"interval": 1, "daysOfTheWeek": [2]}}, "range": {"startDate": "2026-11-17T00:00:00-08:00"}}));
        let c = super::mt_event(&ch, &me, Some("Team@x.com")).unwrap();
        assert_eq!(c["eventType"], "RecurringMaster");
        assert_eq!(c["mailboxAddress"], "Team@x.com");
        assert_eq!(c["attendees"].as_array().unwrap().last().unwrap()["address"], "Team@x.com");
        assert!(c["skypeTeamsData"].as_str().unwrap().contains("19:c@thread.tacv2"));
        assert_eq!(c["eventRecurrencePattern"]["patternType"], 2);
    }

    #[test]
    fn all_day_events_keep_their_own_days_and_channel_meetings_their_channel() {
        let v = serde_json::json!({"value": [{
            "id": "e1", "subject": "Off", "isAllDay": true,
            "start": {"dateTime": "2026-11-18T00:00:00.0000000", "timeZone": "UTC"},
            "end": {"dateTime": "2026-11-21T00:00:00.0000000", "timeZone": "UTC"},
            "onlineMeeting": {"joinUrl": "https://teams.microsoft.com/l/meetup-join/19%3a782662e702f14fa7b33f95096b357dd8%40thread.tacv2/1794905737503?context=%7b%7d"}
        }]});
        let e = &super::parse_events(&v)[0];
        assert_eq!(e.start_utc, "2026-11-18T00:00:00");
        assert_eq!(e.end_utc, "2026-11-21T00:00:00");
        assert_eq!(e.channel_id, "19:782662e702f14fa7b33f95096b357dd8@thread.tacv2");
        assert_eq!(e.channel_message_id, "1794905737503");
    }

    #[test]
    fn availability_takes_the_strongest_overlapping_status() {
        let u = serde_json::json!({"freeBusyEvents": [
            {"freeBusyStatus": "Tentative", "startTime": "2026-11-17T22:00:00+00:00", "endTime": "2026-11-17T22:30:00+00:00"},
            {"freeBusyStatus": "Busy", "startTime": "2026-11-17T23:00:00+00:00", "endTime": "2026-11-17T23:30:00+00:00"}
        ]});
        let t = |s: &str| chrono::DateTime::parse_from_rfc3339(s).unwrap();
        assert_eq!(super::busiest(&u, t("2026-11-17T22:00:00Z"), t("2026-11-17T22:30:00Z")), "Tentative");
        assert_eq!(super::busiest(&u, t("2026-11-17T22:00:00Z"), t("2026-11-17T23:15:00Z")), "Busy");
        assert_eq!(super::busiest(&u, t("2026-11-18T00:00:00Z"), t("2026-11-18T01:00:00Z")), "Free");
    }
}

#[cfg(test)]
mod older_tests {
    #[test]
    fn event_ids_are_checked_before_use_in_paths() {
        assert!(super::event_path_id("AAMkADg0ODhl_-=").is_ok());
        assert!(super::event_path_id("../me/drive").is_err());
        assert!(super::event_path_id("").is_err());
    }

    #[test]
    fn new_event_bodies_are_teams_meetings_in_utc() {
        let b = super::new_event_body(
            "Sync",
            "2026-11-06T15:00:00Z",
            "2026-11-06T15:30:00Z",
            &["a@example.com".into(), "nonsense".into()],
            true,
        )
        .unwrap();
        assert_eq!(b["start"]["dateTime"], "2026-11-06T15:00:00");
        assert_eq!(b["start"]["timeZone"], "UTC");
        assert_eq!(b["isOnlineMeeting"], true);
        assert_eq!(b["attendees"].as_array().unwrap().len(), 1);
        assert!(super::new_event_body("x", "garbage", "2026-11-06T15:30:00Z", &[], false).is_err());
    }

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
