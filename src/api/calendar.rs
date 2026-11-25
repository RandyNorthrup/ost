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
    /// An unsent meeting (Graph `isDraft`): the Filter menu's Draft.
    pub is_draft: bool,
    /// What Outlook knows of the event that Graph doesn't say (its
    /// GetCalendarView item), for Teams' Filter menu: a meeting (IsMeeting),
    /// a scheduling poll's hold (EventPollMetadata `Type`: OrganizerHold or
    /// AttendeeHold, and your `VoteType`), a desk booking
    /// (CalendarEventClassifications DeskBooking) and the hybrid RSVP's
    /// requested attendance (RequestedAttendanceMode, e.g. InPersonRequired).
    pub is_meeting: Option<bool>,
    pub poll_hold: String,
    pub poll_vote: String,
    pub is_desk_booking: bool,
    pub attendance_mode: String,
    /// The calendar it's in, for events read from another calendar than
    /// your own (Split view): its Graph id, or `group:<id>`.
    pub calendar_id: String,
    /// Its charm (Outlook's event icon) as Outlook names it ("Plane"; empty
    /// for none), from Outlook's view.
    pub charm: String,
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
    /// The new time they proposed (UTC, ISO 8601), if any: Graph's
    /// `proposedNewTime`, as the organizer's event shows it.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub proposed_start: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub proposed_end: String,
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
         iCalUId,type,seriesMasterId,responseStatus,responseRequested,attendees,isCancelled,categories,sensitivity,allowNewTimeProposals,isDraft"
    );
    // Immutable ids, as Teams' calendar (Outlook on the web) asks for them.
    let v: serde_json::Value = client
        .graph_get_with(&path, &[("Prefer", "IdType=\"ImmutableId\"")])
        .await?
        .json()
        .await
        .context("Calendar reply")?;
    let mut events = parse_events(&v);
    if crate::auth::oauth::browser_sign_in() {
        match outlook_items(start, end).await {
            Ok(items) => merge_outlook_items(&mut events, &items),
            Err(e) => tracing::debug!("Outlook calendar view: {e:#}"),
        }
    }
    Ok(events)
}

/// One of your calendars as Teams' calendar pane lists it: your own
/// (My calendars: Calendar, United States holidays, Birthdays, ones you
/// made) and your Microsoft 365 groups' (Groups).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct CalendarInfo {
    /// Graph's calendar id, or `group:<group id>`.
    pub id: String,
    pub name: String,
    /// "My calendars" or "Groups".
    pub section: String,
    pub is_default: bool,
    /// Its colour (Graph's hexColor; empty for the default).
    pub color: String,
    /// Whether you can share it (Teams' "…" Share lists these).
    pub can_share: bool,
}

pub async fn calendars(client: &TeamsClient) -> Result<Vec<CalendarInfo>> {
    let v: serde_json::Value = client
        .graph_get("/me/calendars?$select=id,name,hexColor,isDefaultCalendar,canShare&$top=100")
        .await?
        .json()
        .await?;
    let mut out: Vec<CalendarInfo> = v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| CalendarInfo {
            id: c["id"].as_str().unwrap_or_default().to_string(),
            name: c["name"].as_str().unwrap_or_default().to_string(),
            section: "My calendars".into(),
            is_default: c["isDefaultCalendar"].as_bool().unwrap_or(false),
            color: c["hexColor"].as_str().unwrap_or_default().to_string(),
            can_share: c["canShare"].as_bool().unwrap_or(false),
        })
        .collect();
    if let Ok(r) = client
        .graph_get("/me/memberOf/microsoft.graph.group?$select=id,displayName,groupTypes&$top=100")
        .await
        && let Ok(g) = r.json::<serde_json::Value>().await
    {
        for x in g["value"].as_array().into_iter().flatten() {
            let unified = x["groupTypes"]
                .as_array()
                .is_some_and(|t| t.iter().any(|t| t.as_str() == Some("Unified")));
            if unified {
                out.push(CalendarInfo {
                    id: format!("group:{}", x["id"].as_str().unwrap_or_default()),
                    name: x["displayName"].as_str().unwrap_or_default().to_string(),
                    section: "Groups".into(),
                    is_default: false,
                    color: String::new(),
                    can_share: false,
                });
            }
        }
    }
    Ok(out)
}

/// Events overlapping `[start, end)` in one of your calendars, or a group's.
pub async fn calendar_view_of(
    client: &TeamsClient,
    calendar: &str,
    start: &str,
    end: &str,
) -> Result<Vec<CalendarEvent>> {
    let base = match calendar.strip_prefix("group:") {
        Some(g) if !g.is_empty() && g.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') => {
            format!("/groups/{g}/calendarView")
        }
        Some(_) => bail!("Not a group id"),
        None => format!("/me/calendars/{}/calendarView", event_path_id(calendar)?),
    };
    let path = format!(
        "{base}?startDateTime={start}&endDateTime={end}&$top=250&$orderby=start/dateTime\
         &$select=id,subject,start,end,isAllDay,location,organizer,isOnlineMeeting,onlineMeeting,showAs,bodyPreview,isOrganizer,\
         iCalUId,type,seriesMasterId,responseStatus,responseRequested,attendees,isCancelled,categories,sensitivity,allowNewTimeProposals,isDraft"
    );
    let v: serde_json::Value = client
        .graph_get_with(&path, &[("Prefer", "IdType=\"ImmutableId\"")])
        .await?
        .json()
        .await?;
    let mut events = parse_events(&v);
    for e in &mut events {
        e.calendar_id = calendar.to_string();
    }
    Ok(events)
}

/// Make a calendar of your own (`POST /me/calendars`), and delete one.
pub async fn create_calendar(client: &TeamsClient, name: &str) -> Result<String> {
    let v: serde_json::Value = client
        .graph_post("/me/calendars", &serde_json::json!({ "name": name }))
        .await?
        .json()
        .await?;
    Ok(v["id"].as_str().unwrap_or_default().to_string())
}

pub async fn delete_calendar(client: &TeamsClient, id: &str) -> Result<()> {
    client
        .graph_delete(&format!("/me/calendars/{}", event_path_id(id)?))
        .await?;
    Ok(())
}

/// The same range from Outlook's own calendar view (GetCalendarView, as
/// Teams' calendar reads it), by item id.
async fn outlook_items(
    start: &str,
    end: &str,
) -> Result<std::collections::HashMap<String, serde_json::Value>> {
    let local = |t: &str| {
        format!(
            "{}.000",
            t.trim_end_matches('Z').split('.').next().unwrap_or(t)
        )
    };
    let body = serde_json::json!({
        "__type": "GetCalendarViewJsonRequest:#Exchange",
        "Header": {
            "__type": "JsonRequestHeaders:#Exchange",
            "RequestServerVersion": "V2018_01_08",
            "TimeZoneContext": { "__type": "TimeZoneContext:#Exchange", "TimeZoneDefinition": { "__type": "TimeZoneDefinitionType:#Exchange", "Id": "UTC" } }
        },
        "Body": {
            "__type": "GetCalendarViewRequest:#Exchange",
            "CalendarId": { "__type": "TargetFolderId:#Exchange", "BaseFolderId": { "__type": "DistinguishedFolderId:#Exchange", "Id": "calendar" } },
            "RangeStart": local(start), "RangeEnd": local(end),
            "ClientSupportsIrm": true, "OptimizeExtendedPropertyLoading": true, "IncludeSkypeTeamsProperties": true
        }
    });
    let v = owa_action("GetCalendarView", &body).await?;
    Ok(v.pointer("/Body/Items")
        .and_then(|i| i.as_array())
        .into_iter()
        .flatten()
        .filter_map(|i| Some((i.pointer("/ItemId/Id")?.as_str()?.to_string(), i.clone())))
        .collect())
}

/// Outlook's view of each event, matched by its immutable id (Graph's is
/// the same id, URL-safe).
fn merge_outlook_items(
    events: &mut [CalendarEvent],
    items: &std::collections::HashMap<String, serde_json::Value>,
) {
    for e in events.iter_mut() {
        let Some(i) = items.get(&ews_id(&e.id)) else {
            continue;
        };
        e.is_meeting = i.get("IsMeeting").and_then(|b| b.as_bool());
        let poll: std::collections::HashMap<&str, &str> = i
            .get("EventPollMetadata")
            .and_then(|m| m.as_str())
            .unwrap_or_default()
            .split('|')
            .filter_map(|kv| kv.split_once(':'))
            .collect();
        if i.get("EventPollFinalizedChoice")
            .is_none_or(|c| c.is_null())
        {
            e.poll_hold = poll.get("Type").copied().unwrap_or_default().to_string();
        }
        e.poll_vote = poll
            .get("VoteType")
            .copied()
            .unwrap_or_default()
            .to_string();
        e.is_desk_booking = i
            .get("CalendarEventClassifications")
            .and_then(|c| c.as_array())
            .is_some_and(|c| c.iter().any(|x| x.as_str() == Some("DeskBooking")));
        e.attendance_mode = i
            .get("RequestedAttendanceMode")
            .and_then(|m| m.as_str())
            .unwrap_or_default()
            .to_string();
        // The charm is `CharmId` in Outlook's view (a number: an event made
        // in Outlook's form, as Teams' New event form, gets the one its
        // title suggests, e.g. 57 Exam for "test", and its `Charm` stays
        // "None"); the tile menu's charm is `Charm`.
        let charm = |v: Option<&serde_json::Value>| match v {
            Some(serde_json::Value::String(c)) if c != "None" && !c.is_empty() && c != "0" => {
                Some(c.clone())
            }
            Some(serde_json::Value::Number(n)) if n.as_i64().is_some_and(|n| n > 0) => {
                Some(n.to_string())
            }
            _ => None,
        };
        e.charm = charm(i.get("CharmId"))
            .or_else(|| charm(i.get("Charm")))
            .unwrap_or_default();
    }
}

/// Set an event's charm, as Teams' calendar does (Outlook's UpdateItem,
/// the item's Charm field).
pub async fn set_charm(id: &str, charm: i64) -> Result<()> {
    let body = serde_json::json!({
        "__type": "UpdateItemJsonRequest:#Exchange",
        "Header": { "__type": "JsonRequestHeaders:#Exchange", "RequestServerVersion": "V2018_01_08" },
        "Body": {
            "__type": "UpdateItemRequest:#Exchange",
            "ItemChanges": [{
                "__type": "ItemChange:#Exchange",
                "ItemId": { "__type": "ItemId:#Exchange", "Id": ews_id(event_path_id(id)?) },
                "Updates": [{
                    "__type": "SetItemField:#Exchange",
                    "Path": { "__type": "PropertyUri:#Exchange", "FieldURI": "Charm" },
                    "Item": { "__type": "CalendarItem:#Exchange", "Charm": charm }
                }]
            }],
            "ConflictResolution": "AlwaysOverwrite",
            "MessageDisposition": "SaveOnly",
            "SendCalendarInvitationsOrCancellations": "SendToNone"
        }
    });
    let v = owa_action("UpdateItem", &body).await?;
    let code = v
        .pointer("/Body/ResponseMessages/Items/0/ResponseCode")
        .and_then(|c| c.as_str())
        .unwrap_or_default();
    if code != "NoError" {
        bail!("Outlook didn't set the charm: {code}");
    }
    Ok(())
}

/// Change what the tile's menu changes on an event of yours: Show as,
/// categories, Private (Graph's showAs, categories, sensitivity).
pub async fn patch_event(client: &TeamsClient, id: &str, patch: &serde_json::Value) -> Result<()> {
    let mut body = serde_json::Map::new();
    // (Outlook's event form also saves the reminder and its Response
    // options' switches as they change.)
    for k in [
        "showAs",
        "categories",
        "sensitivity",
        "isReminderOn",
        "reminderMinutesBeforeStart",
        "responseRequested",
        "hideAttendees",
    ] {
        if let Some(v) = patch.get(k) {
            body.insert(k.into(), v.clone());
        }
    }
    if body.is_empty() {
        bail!("Nothing to change");
    }
    client
        .graph_patch(
            &format!("/me/events/{}", event_path_id(id)?),
            &serde_json::Value::Object(body),
        )
        .await?;
    Ok(())
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
    pub subject: String,
    pub body_html: String,
    pub recurrence: Option<serde_json::Value>,
}

/// Your calendar's event for a meeting, by its iCalUId (Teams' calendar
/// service `userEventUsingICalUId`). For a series this is the series.
pub async fn event_by_ical_uid(
    client: &TeamsClient,
    ical_uid: &str,
) -> Result<Option<MeetingEvent>> {
    if ical_uid.is_empty() || !ical_uid.bytes().all(|b| b.is_ascii_alphanumeric()) {
        anyhow::bail!("Not an iCalUId");
    }
    let path = format!(
        "/me/events?$filter=iCalUId%20eq%20'{ical_uid}'&$select=subject,body,recurrence,type&$top=1"
    );
    let v: serde_json::Value = client
        .graph_get(&path)
        .await?
        .json()
        .await
        .context("Failed to read the meeting's calendar event")?;
    Ok(v.pointer("/value/0").map(|e| MeetingEvent {
        subject: e
            .get("subject")
            .and_then(|s| s.as_str())
            .unwrap_or_default()
            .to_string(),
        body_html: e
            .pointer("/body/content")
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .to_string(),
        recurrence: e.get("recurrence").filter(|r| !r.is_null()).cloned(),
    }))
}

/// Your calendar event's id for a meeting, by its iCalUId (Teams'
/// meetingEventRedemption); "" when it isn't in your calendar.
pub async fn event_id_by_ical_uid(client: &TeamsClient, ical_uid: &str) -> Result<String> {
    if ical_uid.is_empty() || !ical_uid.bytes().all(|b| b.is_ascii_alphanumeric()) {
        anyhow::bail!("Not an iCalUId");
    }
    let v: serde_json::Value = client
        .graph_get(&format!(
            "/me/events?$filter=iCalUId%20eq%20'{ical_uid}'&$select=id&$top=1"
        ))
        .await?
        .json()
        .await
        .context("Failed to read the meeting's calendar event")?;
    Ok(v.pointer("/value/0/id")
        .and_then(|i| i.as_str())
        .unwrap_or_default()
        .to_string())
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
    Ok(v.pointer("/body/content")
        .and_then(|c| c.as_str())
        .unwrap_or_default()
        .to_string())
}

/// Graph event ids are base64url-ish; refuse anything else in a path.
pub(crate) fn event_path_id(id: &str) -> Result<&str> {
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
            let floating = |t: String| {
                t.split('.')
                    .next()
                    .unwrap_or_default()
                    .trim_end_matches('Z')
                    .to_string()
            };
            CalendarEvent {
                id: s(e, "/id"),
                subject: s(e, "/subject"),
                // An all-day event's dates are its own days, not UTC instants:
                // local midnights (no Z), as Teams draws them.
                start_utc: if all_day {
                    floating(s(e, "/start/dateTime"))
                } else {
                    utc(s(e, "/start/dateTime"))
                },
                end_utc: if all_day {
                    floating(s(e, "/end/dateTime"))
                } else {
                    utc(s(e, "/end/dateTime"))
                },
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
                // Follow is Outlook's Tentative with attendance Follow: free, and
                // the subject marked "Following: ".
                response: match s(e, "/responseStatus/response") {
                    r if r == "tentativelyAccepted"
                        && s(e, "/subject").starts_with("Following: ") =>
                    {
                        "following".to_string()
                    }
                    r => r,
                },
                response_requested: e
                    .get("responseRequested")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(true),
                attendees: attendees_of(e),
                is_cancelled: e
                    .get("isCancelled")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false),
                categories: e
                    .get("categories")
                    .and_then(|c| c.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|c| c.as_str().map(str::to_string))
                            .collect()
                    })
                    .unwrap_or_default(),
                sensitivity: s(e, "/sensitivity"),
                channel_id,
                channel_message_id,
                allow_new_time_proposals: e
                    .get("allowNewTimeProposals")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false),
                is_draft: e.get("isDraft").and_then(|b| b.as_bool()).unwrap_or(false),
                ..Default::default()
            }
        })
        .collect()
}

/// A Graph dateTime (UTC unless its zone says otherwise) as UTC ISO 8601.
fn graph_utc(t: &str, zone: &str) -> String {
    if t.is_empty() || !(zone.is_empty() || zone.eq_ignore_ascii_case("UTC")) {
        return String::new();
    }
    format!(
        "{}Z",
        t.split('.').next().unwrap_or(t).trim_end_matches('Z')
    )
}

fn attendees_of(e: &serde_json::Value) -> Vec<Attendee> {
    let s = |a: &serde_json::Value, p: &str| {
        a.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    e.get("attendees")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .map(|a| Attendee {
            name: s(a, "/emailAddress/name"),
            address: s(a, "/emailAddress/address"),
            kind: s(a, "/type"),
            response: s(a, "/status/response"),
            proposed_start: graph_utc(
                &s(a, "/proposedNewTime/start/dateTime"),
                &s(a, "/proposedNewTime/start/timeZone"),
            ),
            proposed_end: graph_utc(
                &s(a, "/proposedNewTime/end/dateTime"),
                &s(a, "/proposedNewTime/end/timeZone"),
            ),
        })
        .collect()
}

/// An event as its page needs it: the body (HTML), the invitees with
/// their answers and, for a series, its recurrence.
pub async fn event_detail(client: &TeamsClient, id: &str) -> Result<serde_json::Value> {
    let v: serde_json::Value = client
        .graph_get_with(
            &format!(
                "/me/events/{}?$select=body,attendees,recurrence,onlineMeeting,type,seriesMasterId,createdDateTime,isReminderOn,reminderMinutesBeforeStart,responseRequested,hideAttendees",
                event_path_id(id)?
            ),
            &[("Prefer", "IdType=\"ImmutableId\"")],
        )
        .await?
        .json()
        .await
        .context("Failed to read the event")?;
    // An occurrence has no recurrence of its own: its series' (what
    // Outlook's form shows on Edit series).
    let mut recurrence = v
        .get("recurrence")
        .cloned()
        .unwrap_or(serde_json::Value::Null);
    if recurrence.is_null()
        && let Some(master) = v
            .get("seriesMasterId")
            .and_then(|m| m.as_str())
            .filter(|m| !m.is_empty())
        && let Ok(r) = client
            .graph_get_with(
                &format!("/me/events/{}?$select=recurrence", event_path_id(master)?),
                &[("Prefer", "IdType=\"ImmutableId\"")],
            )
            .await
    {
        let m: serde_json::Value = r.json().await.unwrap_or_default();
        recurrence = m
            .get("recurrence")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
    }
    Ok(serde_json::json!({
        "id": id,
        "body_html": v.pointer("/body/content").and_then(|c| c.as_str()).unwrap_or_default(),
        "attendees": attendees_of(&v),
        "recurrence": recurrence,
        "conference_id": v.pointer("/onlineMeeting/conferenceId").and_then(|c| c.as_str()).unwrap_or_default(),
        // Outlook's event form: "Sent on …" (when the event was made),
        // the reminder (minutes, -1 off), Response options' switches.
        "created": v.get("createdDateTime").and_then(|c| c.as_str()).unwrap_or_default(),
        "reminder": if v.get("isReminderOn").and_then(|r| r.as_bool()).unwrap_or(true) { v.get("reminderMinutesBeforeStart").and_then(|m| m.as_i64()).unwrap_or(15) } else { -1 },
        "response_requested": v.get("responseRequested").and_then(|r| r.as_bool()).unwrap_or(true),
        "hide_attendees": v.get("hideAttendees").and_then(|r| r.as_bool()).unwrap_or(false),
    }))
}

/// Answer an invitation (the card's Accept / Tentative / Decline, Follow,
/// the event page's RSVP with note) as Teams' calendar does: Outlook on the
/// web's `RespondToCalendarEvent` (measured 2026-11-17) with the event's
/// immutable id (the occurrence, or the series for "All events in the
/// series"), `Response`, `SendResponse` ("Email organizer"), the note as
/// `<div>…</div>`, and `Attendance` (Teams desktop's calendar bundle:
/// AttendanceType None 0, InPerson 1, Online 2, Follow 3; Follow is
/// `Tentative` with attendance Follow). The token is the hosted calendar's
/// (client ceb96695…, through Teams' broker), so it needs the browser
/// sign-in; on a device-code sign-in OST answers through Graph
/// (`/me/events/{id}/accept|tentativelyAccept|decline`), which has no Follow.
pub async fn respond(
    client: &TeamsClient,
    ev: &RsvpTarget,
    response: &str,
    send_response: bool,
    note: &str,
) -> Result<()> {
    respond_with_time(client, ev, response, send_response, note, None).await
}

/// Propose a new time, as Teams' calendar does from an invitation
/// ("Tentative and propose new time", "Decline and propose new time"):
/// Outlook's `RespondToCalendarEvent` with `ProposedStartTime` and
/// `ProposedEndTime` (local times in the mailbox's zone) beside the answer.
/// The organizer's event then carries the proposal (Graph's attendee
/// `proposedNewTime`) and they get a "New time proposed" response.
pub async fn propose_new_time(
    client: &TeamsClient,
    ev: &RsvpTarget,
    response: &str,
    start: &str,
    end: &str,
    send_response: bool,
    note: &str,
) -> Result<()> {
    if !matches!(response, "Tentative" | "Decline") {
        bail!("A proposal goes with Tentative or Decline");
    }
    if !crate::auth::oauth::browser_sign_in() {
        bail!("Proposing a new time needs the browser sign-in (Outlook's calendar service)");
    }
    let s = chrono::DateTime::parse_from_rfc3339(start).context("Proposed start")?;
    let e = chrono::DateTime::parse_from_rfc3339(end).context("Proposed end")?;
    if e <= s {
        bail!("The proposed end is before its start");
    }
    match respond_with_time(client, ev, response, send_response, note, Some((s, e))).await {
        Ok(()) => Ok(()),
        // Outlook didn't take it: Graph's tentativelyAccept / decline with
        // `proposedNewTime` sends the same proposal.
        Err(err) => {
            tracing::warn!("proposal through Outlook failed ({err:#}); sending it through Graph");
            let verb = if response == "Decline" {
                "decline"
            } else {
                "tentativelyAccept"
            };
            let utc = |d: chrono::DateTime<chrono::FixedOffset>| {
                d.with_timezone(&chrono::Utc)
                    .format("%Y-%m-%dT%H:%M:%S")
                    .to_string()
            };
            let body = serde_json::json!({
                "comment": note.trim(),
                "sendResponse": send_response,
                "proposedNewTime": {
                    "start": { "dateTime": utc(s), "timeZone": "UTC" },
                    "end": { "dateTime": utc(e), "timeZone": "UTC" }
                }
            });
            client
                .graph_post(
                    &format!("/me/events/{}/{verb}", event_path_id(&ev.id)?),
                    &body,
                )
                .await?;
            Ok(())
        }
    }
}

async fn respond_with_time(
    client: &TeamsClient,
    ev: &RsvpTarget,
    response: &str,
    send_response: bool,
    note: &str,
    proposed: Option<(
        chrono::DateTime<chrono::FixedOffset>,
        chrono::DateTime<chrono::FixedOffset>,
    )>,
) -> Result<()> {
    let (owa_response, attendance) = match response {
        "Accept" | "Tentative" | "Decline" => (response, 0),
        "Follow" => ("Tentative", 3),
        other => bail!("Not a response: {other}"),
    };
    if crate::auth::oauth::browser_sign_in() {
        let id = event_path_id(&ev.id)?;
        let tz = mailbox_time_zone().await;
        let mut body = respond_body(
            &ews_id(id),
            owa_response,
            attendance,
            send_response,
            note,
            &tz,
        );
        if let Some((s, e)) = proposed {
            // As Outlook on the web writes them: local wall-clock times
            // (the request's TimeZoneContext names the zone), milliseconds.
            let local = |d: chrono::DateTime<chrono::FixedOffset>| {
                d.format("%Y-%m-%dT%H:%M:%S%.3f").to_string()
            };
            body["Body"]["ProposedStartTime"] = serde_json::json!(local(s));
            body["Body"]["ProposedEndTime"] = serde_json::json!(local(e));
        }
        owa_action("RespondToCalendarEvent", &body).await?;
        tracing::info!(
            response,
            attendance,
            proposed = proposed.is_some(),
            "answered through Outlook (RespondToCalendarEvent)"
        );
        return Ok(());
    }
    if proposed.is_some() {
        bail!("Proposing a new time needs the browser sign-in");
    }
    tracing::info!(
        response,
        "answer through Teams' calendar service (device-code sign-in)"
    );
    respond_mt(client, ev, response, send_response, note).await
}

/// What an answer is about: the event (its Graph id), and for Teams' own
/// calendar service its iCalUId, type and start (UTC).
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct RsvpTarget {
    pub id: String,
    pub ical_uid: String,
    /// singleInstance, occurrence, exception or seriesMaster.
    pub event_type: String,
    pub start_utc: String,
}

/// Teams' own calendar's answer (its event page, calv2: `PUT
/// {mt}/v2.0/me/calendars/events/{iCalUId}/respond?eventType=…&eventStartDateTime=…`,
/// `{responseType: Accept|TentativelyAccept|Decline, sendResponse, comment,
/// attendance: None|Follow}`, from Teams' calendar service bundle).
async fn respond_mt(
    client: &TeamsClient,
    ev: &RsvpTarget,
    response: &str,
    send_response: bool,
    note: &str,
) -> Result<()> {
    let (kind, attendance) = match response {
        "Accept" => ("Accept", "None"),
        "Tentative" => ("TentativelyAccept", "None"),
        "Decline" => ("Decline", "None"),
        "Follow" => ("TentativelyAccept", "Follow"),
        other => bail!("Not a response: {other}"),
    };
    let uid = &ev.ical_uid;
    if uid.is_empty() || !uid.bytes().all(|b| b.is_ascii_hexdigit()) {
        bail!("Not an iCalUId");
    }
    let event_type = match ev.event_type.as_str() {
        "occurrence" => "Occurrence",
        "exception" => "Exception",
        "seriesMaster" => "RecurringMaster",
        _ => "Single",
    };
    let start = chrono::DateTime::parse_from_rfc3339(&ev.start_utc)
        .map(|d| {
            d.with_timezone(&chrono::Utc)
                .format("%Y-%m-%dT%H:%M:%S.000Z")
                .to_string()
        })
        .unwrap_or_default();
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let url = crate::auth::token_hosts::service_url(
        &base,
        crate::auth::token_hosts::Audience::Teams,
        &["v2.0", "me", "calendars", "events", uid, "respond"],
        &[("eventType", event_type), ("eventStartDateTime", &start)],
    )?;
    let r = client
        .http()
        .put(url)
        .bearer_auth(&token)
        .json(&serde_json::json!({ "responseType": kind, "sendResponse": send_response, "comment": note.trim(), "attendance": attendance }))
        .send()
        .await?;
    let status = r.status();
    if !status.is_success() {
        bail!(
            "{status}: {}",
            r.text()
                .await
                .unwrap_or_default()
                .chars()
                .take(300)
                .collect::<String>()
        );
    }
    Ok(())
}

fn respond_body(
    ews_id: &str,
    response: &str,
    attendance: u8,
    send_response: bool,
    note: &str,
    tz: &str,
) -> serde_json::Value {
    let mut b = serde_json::json!({
        "__type": "RespondToCalendarEventJsonRequest:#Exchange",
        "Header": {
            "__type": "JsonRequestHeaders:#Exchange",
            "RequestServerVersion": "V2018_01_08",
            "TimeZoneContext": {
                "__type": "TimeZoneContext:#Exchange",
                "TimeZoneDefinition": { "__type": "TimeZoneDefinitionType:#Exchange", "Id": tz }
            }
        },
        "Body": {
            "__type": "RespondToCalendarEventRequest:#Exchange",
            "EventId": { "__type": "ItemId:#Exchange", "Id": ews_id },
            "Response": response,
            "SendResponse": send_response,
            "ProposedStartTime": "",
            "ProposedEndTime": "",
            "Attendance": attendance,
            "Mode": 0
        }
    });
    if !note.trim().is_empty() {
        let esc = note
            .trim()
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('\n', "<br>");
        b["Body"]["Notes"] = serde_json::json!({ "__type": "BodyContentType:#Exchange", "BodyType": "HTML", "Value": format!("<div>{esc}</div>") });
    }
    b
}

/// Graph's URL-safe immutable id as Exchange writes it (standard base64,
/// padded).
pub(crate) fn ews_id(rest_id: &str) -> String {
    let mut s = rest_id.replace('-', "/").replace('_', "+");
    while !s.len().is_multiple_of(4) {
        s.push('=');
    }
    s
}

/// The hosted Outlook calendar's app in Teams (its broker token request:
/// `brk-multihub://outlook.office.com`, scope `https://outlook.office.com/.default`).
pub const HOSTED_CALENDAR_APP: &str = "ceb96695-e468-48ba-ba21-35e2a242d396";

/// A browser's User-Agent, as the hosted calendar's web view sends (Outlook
/// on the web fails every action without one).
pub(crate) const OWA_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0";

/// One Outlook on the web service action as Teams' hosted calendar sends
/// it: the request JSON URL-encoded in `x-owa-urlpostdata`, an empty body,
/// and its headers (`action`, `x-owa-actionsource`, `x-req-source:
/// Calendar`, `x-owa-hosted-ux: true`, a session and correlation id, the
/// tenant, `prefer: IdType="ImmutableId"…`).
pub async fn owa_action(action: &str, body: &serde_json::Value) -> Result<serde_json::Value> {
    if !action.bytes().all(|b| b.is_ascii_alphanumeric()) {
        bail!("Not an action: {action}");
    }
    let (token, _) = crate::auth::oauth::brokered_token(
        HOSTED_CALENDAR_APP,
        "https://outlook.office.com",
        "https://outlook.office.com/.default",
        None,
    )
    .await?;
    let tenant = crate::config::Config::load()
        .ok()
        .and_then(|c| c.tenant_id())
        .unwrap_or_default();
    static SESSION: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let session = SESSION.get_or_init(|| uuid::Uuid::new_v4().to_string());
    let anchor = crate::config::Config::load()
        .ok()
        .and_then(|c| c.object_id())
        .map(|o| format!("OID:{o}@{tenant}"))
        .unwrap_or_default();
    // encodeURIComponent, as the page encodes it: a space is %20 (a "+"
    // would reach the service as a plus: "Pacific+Standard+Time").
    let data = url::form_urlencoded::byte_serialize(body.to_string().as_bytes())
        .collect::<String>()
        .replace('+', "%20");
    // A small request goes in the X-OWA-UrlPostData header, a large one
    // (GetCalendarEvent, an UpdateCalendarEvent with pictures in its body)
    // as the request's body, as the page sends them (captured 2026-11-24).
    let (data, payload) = if data.len() > 4096 {
        (String::new(), body.to_string())
    } else {
        (data, String::new())
    };
    let req = reqwest::Client::new()
        .post(format!(
            "https://outlook.office.com/owa/service.svc?action={action}&app=Calendar"
        ))
        .bearer_auth(token)
        .header("x-anchormailbox", anchor)
        .header("user-agent", OWA_USER_AGENT)
        .header("action", action)
        .header("x-owa-actionsource", action)
        .header("x-req-source", "Calendar")
        .header("x-owa-hosted-ux", "true")
        .header("x-owa-host-app", "teams_desktop")
        .header("origin", "https://outlook.office.com")
        .header("x-owa-sessionid", session.as_str())
        .header("x-owa-correlationid", uuid::Uuid::new_v4().to_string())
        .header("x-tenantid", tenant)
        .header(
            "prefer",
            "IdType=\"ImmutableId\", exchange.behavior=\"IncludeThirdPartyOnlineMeetingProviders\"",
        )
        .header("content-type", "application/json; charset=utf-8");
    let req = if data.is_empty() {
        req
    } else {
        req.header("x-owa-urlpostdata", data)
    };
    let resp = req
        .body(payload)
        .send()
        .await
        .with_context(|| format!("{action} failed"))?;
    let status = resp.status();
    let err = resp
        .headers()
        .get("x-owa-error")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_string();
    let text = resp.text().await.unwrap_or_default();
    let v: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    let class = v
        .pointer("/Body/ResponseClass")
        .and_then(|c| c.as_str())
        .unwrap_or_default();
    tracing::debug!(action, %status, class, code = v.pointer("/Body/ResponseCode").and_then(|c| c.as_str()).unwrap_or_default(), "Outlook action answered");
    // An empty 204 is no answer: Outlook didn't take the action (seen for
    // OST Test 3's RespondToCalendarEvent), not a success.
    if status == reqwest::StatusCode::NO_CONTENT && text.trim().is_empty() {
        bail!("{action}: Outlook gave no answer (204)");
    }
    if !status.is_success() || class == "Error" {
        let msg = v
            .pointer("/Body/MessageText")
            .or_else(|| v.pointer("/Body/FaultMessage"))
            .or_else(|| v.pointer("/Body/ExceptionName"))
            .and_then(|c| c.as_str())
            .map(str::to_string)
            .unwrap_or_else(|| format!("{err} {}", text.chars().take(300).collect::<String>()));
        bail!("{action}: {status} {msg}");
    }
    Ok(v)
}

/// One Outlook web service request (`https://outlook.office.com/<path>`) as
/// Teams' hosted calendar sends it: its token (the hosted calendar's app,
/// through Teams' broker), `x-anchormailbox`, the session id,
/// `x-outlook-client: owa` and a browser User-Agent. Its settings live
/// there: `ows/v1.0/OutlookOptions` (Time scale, the day count),
/// `ows/v1/OutlookCloudSettings/settings` (the Filter menu's
/// `calendar_filters`) and `ows/v1/SaveCalendarView` (Saved views).
pub async fn ows(
    method: reqwest::Method,
    path: &str,
    body: Option<&serde_json::Value>,
) -> Result<serde_json::Value> {
    if !ows_path_ok(path) {
        bail!("Not an Outlook service path: {path}");
    }
    let (token, _) = crate::auth::oauth::brokered_token(
        HOSTED_CALENDAR_APP,
        "https://outlook.office.com",
        "https://outlook.office.com/.default",
        None,
    )
    .await?;
    let tenant = crate::config::Config::load()
        .ok()
        .and_then(|c| c.tenant_id())
        .unwrap_or_default();
    let anchor = crate::config::Config::load()
        .ok()
        .and_then(|c| c.object_id())
        .map(|o| format!("OID:{o}@{tenant}"))
        .unwrap_or_default();
    static SESSION: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let session = SESSION.get_or_init(|| uuid::Uuid::new_v4().to_string());
    let mut req = reqwest::Client::new()
        .request(method.clone(), format!("https://outlook.office.com/{path}"))
        .bearer_auth(token)
        .header("x-anchormailbox", anchor)
        .header("user-agent", OWA_USER_AGENT)
        .header("x-outlook-client", "owa")
        .header("x-owa-sessionid", session.as_str())
        .header("x-owa-hosted-ux", "true")
        .header("x-owa-host-app", "teams_desktop")
        .header("x-req-source", "Calendar")
        .header(
            "prefer",
            "IdType=\"ImmutableId\", exchange.behavior=\"IncludeThirdPartyOnlineMeetingProviders\"",
        )
        .header("origin", "https://outlook.office.com");
    if let Some(b) = body {
        req = req.json(b);
    }
    let resp = req
        .send()
        .await
        .with_context(|| format!("{method} {path} failed"))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!(
            "{method} {path}: {status} {}",
            text.chars().take(300).collect::<String>()
        );
    }
    Ok(serde_json::from_str(&text).unwrap_or(serde_json::Value::Null))
}

/// The calendar's own settings as Teams' calendar keeps them: Time scale
/// (minutes) and the Day view's day count (CalendarSurfaceOptions'
/// `timeScaleSetting` and `numDaysInDayRange`; 0 means the default, 30 and
/// 1), the Filter menu's unchecked values (`calendar_filters`, an array of
/// `[filterType, [values]]`; null when you never set it), your saved views,
/// and your categories (name and preset colour).
pub async fn calendar_prefs(client: &TeamsClient) -> Result<serde_json::Value> {
    let options = ows(reqwest::Method::GET, "ows/v1.0/OutlookOptions", None).await;
    let surface = options
        .as_ref()
        .ok()
        .and_then(|v| v.get("options").and_then(|o| o.as_array()).cloned())
        .unwrap_or_default()
        .into_iter()
        .find(is_surface_options)
        .unwrap_or(serde_json::Value::Null);
    if let Err(e) = &options {
        tracing::warn!("calendar options: {e:#}");
    }
    let filters = ows(
        reqwest::Method::GET,
        "ows/v1/OutlookCloudSettings/settings/?settingname=calendar_filters",
        None,
    )
    .await
    .map_err(|e| tracing::warn!("calendar filters: {e:#}"))
    .ok()
    .and_then(|v| cloud_setting_value(&v, "calendar_filters"));
    let views = ows(reqwest::Method::GET, "ows/v1/SaveCalendarView", None)
        .await
        .map_err(|e| tracing::warn!("saved views: {e:#}"))
        .ok()
        .and_then(|v| v.get("savedViews").cloned())
        .unwrap_or(serde_json::json!([]));
    let categories: Vec<serde_json::Value> =
        match client.graph_get("/me/outlook/masterCategories").await {
            Ok(r) => r
                .json::<serde_json::Value>()
                .await
                .ok()
                .and_then(|v| v.get("value").and_then(|c| c.as_array()).cloned())
                .unwrap_or_default()
                .into_iter()
                .map(|c| serde_json::json!({ "name": c["displayName"], "color": c["color"] }))
                .collect(),
            Err(e) => {
                tracing::warn!("categories: {e:#}");
                Vec::new()
            }
        };
    // Your calendar's folder id as Outlook names it (saved views keep it).
    let calendar_id = match client.graph_get("/me/calendar?$select=id").await {
        Ok(r) => r
            .json::<serde_json::Value>()
            .await
            .ok()
            .and_then(|v| v["id"].as_str().map(ews_id))
            .unwrap_or_default(),
        Err(_) => String::new(),
    };
    let n = |k: &str, default: u64| {
        surface
            .get(k)
            .and_then(|x| x.as_u64())
            .filter(|x| *x > 0)
            .unwrap_or(default)
    };
    Ok(serde_json::json!({
        "timeScale": n("timeScaleSetting", 30),
        "numDays": n("numDaysInDayRange", 1),
        "filters": filters,
        "savedViews": views,
        "categories": categories,
        "calendarId": calendar_id,
        "objectId": crate::config::Config::load().ok().and_then(|c| c.object_id()).unwrap_or_default(),
        "tenantId": crate::config::Config::load().ok().and_then(|c| c.tenant_id()).unwrap_or_default(),
        // A Copilot licence (authz licenseDetails isCopilot): the calendar's
        // Copilot entry points.
        "copilot": client.license_details().and_then(|l| l.get("isCopilot").and_then(|b| b.as_bool())).unwrap_or(false),
    }))
}

fn is_surface_options(o: &serde_json::Value) -> bool {
    o.get("feature")
        .is_some_and(|f| f.as_u64() == Some(15) || f.as_str() == Some("CalendarSurfaceOptions"))
        || o.get("timeScaleSetting").is_some()
}

/// One OutlookCloudSettings value by name (a JSON setting parsed).
fn cloud_setting_value(v: &serde_json::Value, name: &str) -> Option<serde_json::Value> {
    let list = v
        .as_array()
        .or_else(|| v.get("value").and_then(|x| x.as_array()))?;
    let s = list.iter().find(|s| {
        s["name"]
            .as_str()
            .is_some_and(|n| n.eq_ignore_ascii_case(name))
    })?;
    match &s["value"] {
        serde_json::Value::String(t) => serde_json::from_str(t).ok(),
        other if !other.is_null() => Some(other.clone()),
        _ => None,
    }
}

/// Keep the Filter menu's unchecked values, as Teams' calendar saves them:
/// the `calendar_filters` roaming setting, registered with the global
/// scope (type JSON, its value the `[filterType, [values]]` entries as a
/// string; the account scope answers "Requested scope doesn't match
/// registered scope: Global").
pub async fn set_calendar_filters(filters: &serde_json::Value) -> Result<()> {
    let body = serde_json::json!([{
        "itemClass": "RoamingSetting",
        "name": "calendar_filters",
        "scope": "global",
        "type": "JSON",
        "value": filters.to_string(),
    }]);
    ows(
        reqwest::Method::PATCH,
        "ows/v1/OutlookCloudSettings/settings/global",
        Some(&body),
    )
    .await?;
    Ok(())
}

/// Change CalendarSurfaceOptions fields (`timeScaleSetting`,
/// `numDaysInDayRange`) as Teams' calendar does: the whole feature's
/// options with the change, PATCHed (POSTed the first time) to
/// `ows/v1.0/OutlookOptions/CalendarSurfaceOptions` with a correlation id.
pub async fn set_surface_options(change: &serde_json::Value) -> Result<()> {
    let all = ows(reqwest::Method::GET, "ows/v1.0/OutlookOptions", None)
        .await
        .unwrap_or_default();
    let current = all
        .get("options")
        .and_then(|o| o.as_array())
        .and_then(|l| l.iter().find(|o| is_surface_options(o)).cloned());
    let existed = current
        .as_ref()
        .is_some_and(|c| c.get("lastModifiedDateTime").is_some());
    let mut options = current.unwrap_or_else(|| serde_json::json!({ "feature": 15 }));
    if let (Some(o), Some(c)) = (options.as_object_mut(), change.as_object()) {
        for k in [
            "feature@is.Queryable",
            "feature@odata.type",
            "createdDateTime",
            "lastModifiedDateTime",
        ] {
            o.remove(k);
        }
        for (k, v) in c {
            o.insert(k.clone(), v.clone());
        }
    }
    let body = serde_json::json!({ "correlationId": uuid::Uuid::new_v4().to_string(), "options": options });
    let method = if existed {
        reqwest::Method::PATCH
    } else {
        reqwest::Method::POST
    };
    ows(
        method,
        "ows/v1.0/OutlookOptions/CalendarSurfaceOptions",
        Some(&body),
    )
    .await?;
    Ok(())
}

/// Save a calendar view (Saved views ▸ Save current view, or Edit) as
/// Teams' calendar does: `PUT ows/v1/SaveCalendarView` with the view
/// (`id`, `viewName`, `viewIcon`, `selectedCalendarIds`, `dateRangeType`,
/// `splitView`, `numDaysInDayRange`, `chosenHotkey`, and `filterState` as
/// the filters' entries in a string). A new view gets its id here.
pub async fn save_calendar_view(view: &serde_json::Value) -> Result<serde_json::Value> {
    let mut v = view.clone();
    if v.get("id")
        .and_then(|i| i.as_str())
        .is_none_or(str::is_empty)
    {
        v["id"] = serde_json::json!(uuid::Uuid::new_v4().to_string());
    }
    if let Some(f) = v
        .get("filterState")
        .filter(|f| !f.is_string() && !f.is_null())
        .cloned()
    {
        v["filterState"] = serde_json::json!(f.to_string());
    }
    ows(reqwest::Method::PUT, "ows/v1/SaveCalendarView", Some(&v)).await?;
    Ok(v)
}

/// Delete a saved view (`DELETE ows/v1/SaveCalendarView/{id}`).
pub async fn delete_calendar_view(id: &str) -> Result<()> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Not a saved view id");
    }
    ows(
        reqwest::Method::DELETE,
        &format!("ows/v1/SaveCalendarView/{id}"),
        None,
    )
    .await?;
    Ok(())
}

/// Your mailbox's time zone (its Windows name, e.g. "Pacific Standard Time").
pub async fn mailbox_time_zone() -> String {
    static TZ: tokio::sync::OnceCell<String> = tokio::sync::OnceCell::const_new();
    TZ.get_or_init(|| async {
        let r = async {
            let client = TeamsClient::new().await?;
            let v: serde_json::Value = client
                .graph_get("/me/mailboxSettings/timeZone")
                .await?
                .json()
                .await?;
            Ok::<_, anyhow::Error>(
                v.get("value")
                    .and_then(|t| t.as_str())
                    .unwrap_or_default()
                    .to_string(),
            )
        }
        .await;
        r.ok()
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| "UTC".into())
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

/// You as the organizer, your mail and name from Graph when the sign-in
/// didn't give them.
pub async fn organizer(client: &TeamsClient, me: &Me) -> Me {
    if !me.mail.is_empty() && !me.name.is_empty() {
        return me.clone();
    }
    let mut out = me.clone();
    if let Ok(r) = client.graph_get("/me?$select=mail,displayName,id").await {
        let v: serde_json::Value = r.json().await.unwrap_or_default();
        if out.mail.is_empty() {
            out.mail = v["mail"].as_str().unwrap_or_default().to_string();
        }
        if out.name.is_empty() {
            out.name = v["displayName"].as_str().unwrap_or_default().to_string();
        }
        if out.mri.is_empty() {
            out.mri = v["id"]
                .as_str()
                .map(crate::identity::work_user_mri)
                .unwrap_or_default();
        }
    }
    out
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
    let me = &organizer(client, me).await;
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let mut attendees = vec![
        serde_json::json!({"type": "Organizer", "address": me.mail, "name": me.name, "mri": me.mri, "role": "Admin"}),
    ];
    for (mail, name) in people {
        attendees.push(
            serde_json::json!({"type": "Required", "address": mail, "name": name, "role": "Admin"}),
        );
    }
    let s = chrono::DateTime::parse_from_rfc3339(start)?;
    let e = chrono::DateTime::parse_from_rfc3339(end)?;
    // As Teams asks: UTC with milliseconds, the day's start, whole days.
    let utc = |d: chrono::DateTime<chrono::FixedOffset>| {
        d.with_timezone(&chrono::Utc)
            .format("%Y-%m-%dT%H:%M:%S.000Z")
            .to_string()
    };
    let day0 = s
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .and_then(|d| d.and_local_timezone(*s.offset()).single())
        .unwrap_or(s);
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
        let who = u
            .get("userPrincipalName")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_lowercase();
        if who == me.mail.to_lowercase() {
            tz = u
                .get("timeZone")
                .and_then(|x| x.as_str())
                .unwrap_or_default()
                .to_string();
        }
        out.insert(who, serde_json::json!(busiest(u, s, e)));
    }
    Ok((serde_json::Value::Object(out), tz))
}

/// The strongest status overlapping `[s, e)`, as Teams' attendee chips
/// show it.
fn busiest(
    u: &serde_json::Value,
    s: chrono::DateTime<chrono::FixedOffset>,
    e: chrono::DateTime<chrono::FixedOffset>,
) -> &'static str {
    let named = |st: &str| match st {
        "Oof" => ("Oof", 4),
        "Busy" => ("Busy", 3),
        "Tentative" => ("Tentative", 2),
        "WorkingElsewhere" => ("WorkingElsewhere", 1),
        _ => ("Free", 0),
    };
    let mut best = ("Free", 0);
    for ev in u
        .get("freeBusyEvents")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
    {
        let t = |k: &str| {
            ev.get(k)
                .and_then(|x| x.as_str())
                .and_then(|x| chrono::DateTime::parse_from_rfc3339(x).ok())
        };
        let (Some(a), Some(b)) = (t("startTime"), t("endTime")) else {
            continue;
        };
        if a < e && b > s {
            let n = named(
                ev.get("freeBusyStatus")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default(),
            );
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
    /// The meeting template ("" for Teams' "default"; New ▸ Virtual
    /// appointment uses [`VIRTUAL_APPOINTMENT_TEMPLATE`]).
    pub template_id: String,
    /// A virtual appointment's external guests (its clients), who get
    /// Teams' tailored invitation instead of being attendees.
    pub guests: Vec<FormGuest>,
    /// Whether the details changed since the form opened (an update sends
    /// only what changed, as Teams' event page does).
    pub body_changed: bool,
    /// Whether the repeat changed since the form opened: an update then
    /// sends the series its new recurrence (Outlook's "Edit series").
    pub recurrence_changed: bool,
    /// Who gets the update when only the attendees changed (Outlook's
    /// "Send update" prompt): 0 not asked, 1 all attendees, 2 only those
    /// added or removed.
    pub target_audience: u8,
    /// Which events of a series the update is for, as Outlook's form edits
    /// them: "occurrence" (this event), "following" (this and all
    /// following events) or "series" (all events in the series); "" for
    /// an event that isn't a series'.
    pub scope: String,
    /// What else Outlook's form sends with it (only what changed):
    /// Response options, Rebook declined rooms, the Copilot reschedule
    /// switch, Loop components' links ([`super::event_form::form_updates`]).
    #[serde(default)]
    pub outlook: serde_json::Value,
}

/// Teams' Virtual appointment template (Calendar ▸ New ▸ Virtual
/// appointment, measured 2026-11-19).
pub const VIRTUAL_APPOINTMENT_TEMPLATE: &str = "firstparty_e514e598-fba6-4e1f-b8b3-138dd3bca748";

/// A virtual appointment's external guest (name and email, both
/// required in Teams' form).
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FormGuest {
    pub display_name: String,
    pub email_address: String,
}

/// What Teams' form sends for a virtual appointment's guests
/// (`virtualAppointmentInfo`, captured 2026-11-19).
pub fn virtual_appointment_info(guests: &[FormGuest]) -> serde_json::Value {
    serde_json::json!({
        "appointmentClients": guests.iter().map(|g| serde_json::json!({ "displayName": g.display_name.trim(), "emailAddress": g.email_address.trim() })).collect::<Vec<_>>(),
        "eTag": "",
        "isSmsEligible": false,
        "settings": { "allowClientToJoinUsingBrowser": true, "notifications": [], "organizerLocale": "en-us" },
    })
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
    let start = chrono::DateTime::parse_from_rfc3339(&form.start)
        .with_context(|| format!("Not a time: {}", form.start))?;
    chrono::DateTime::parse_from_rfc3339(&form.end)
        .with_context(|| format!("Not a time: {}", form.end))?;
    let utc_offset = i64::from(start.offset().local_minus_utc()) / 60;
    let people: Vec<&FormAttendee> = form
        .attendees
        .iter()
        .filter(|a| a.address.contains('@'))
        .collect();
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
    let id = (0..5)
        .map(|_| rand_u32().to_string())
        .collect::<Vec<_>>()
        .join("-");
    // Without the middle tier's name for your zone (a mailbox with no time
    // zone answers none) the event goes in UTC, and so must its times: the
    // middle tier reads them as wall-clock times in eventTimeZone.
    let in_zone = |t: &str| {
        if !form.time_zone.is_empty() {
            return t.to_string();
        }
        chrono::DateTime::parse_from_rfc3339(t)
            .map(|d| {
                d.with_timezone(&chrono::Utc)
                    .format("%Y-%m-%dT%H:%M:%S+00:00")
                    .to_string()
            })
            .unwrap_or_else(|_| t.to_string())
    };
    let mut ev = serde_json::json!({
        "attendees": attendees,
        "bodyContent": form.body_html,
        "clientOptimisticEventId": id,
        "doNotForward": false,
        "emptyBodyPlaceholder": "Scheduled a meeting",
        "endTime": in_zone(&form.end),
        "eventTimeZone": if form.time_zone.is_empty() { "UTC" } else { &form.time_zone },
        "eventType": if form.recurrence.is_some() { "RecurringMaster" } else { "Single" },
        "isAllDayEvent": form.all_day,
        "isOrganizer": true,
        "isPrivate": false,
        "isReminderSet": true,
        "isResponseRequested": true,
        "joinMeetingLabel": "Join Microsoft Teams Online Meeting",
        "location": form.location,
        "meetingTemplateId": if form.template_id.is_empty() { "default" } else { form.template_id.as_str() },
        "organizerAddress": me.mail,
        "organizerName": me.name,
        "primarySpokenLanguage": "en-us",
        "reminderMinutesBeforeStart": 15,
        "sensitivityLabelId": "",
        "showAs": if form.show_as.is_empty() { "Busy" } else { &form.show_as },
        "startTime": in_zone(&form.start),
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
        ev["skypeTeamsData"] = serde_json::json!(
            serde_json::json!({"cid": c.channel_id, "uid": me.mri, "type": 0}).to_string()
        );
    } else {
        // A virtual appointment is a meeting with its guests, never an
        // appointment (Teams sends isAppointment false with no attendees).
        ev["isAppointment"] = serde_json::json!(people.is_empty() && form.guests.is_empty());
        ev["skypeTeamsData"] = serde_json::json!(
            serde_json::json!({"uid": me.mri, "type": 0, "private": true}).to_string()
        );
        ev["TransactionId"] = serde_json::json!(id);
    }
    if !form.guests.is_empty() {
        ev["virtualAppointmentInfo"] = virtual_appointment_info(&form.guests);
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
pub async fn schedule(
    client: &TeamsClient,
    form: &MeetingForm,
    me: &Me,
) -> Result<serde_json::Value> {
    let me = &organizer(client, me).await;
    // The form's eventTimeZone is the middle tier's name for your zone, as
    // its free/busy answer gives it (the form asks when it opens).
    let mut owned;
    let form = if form.time_zone.is_empty() {
        owned = form.clone();
        if let Ok((_, tz)) = availability(client, me, &[], &form.start, &form.end).await {
            owned.time_zone = tz;
        }
        &owned
    } else {
        form
    };
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let post = |url: String, body: serde_json::Value| {
        let token = token.clone();
        async move {
            let r = client
                .http()
                .post(&url)
                .bearer_auth(&token)
                .json(&body)
                .send()
                .await?;
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
        let url = format!(
            "{base}/v2.0/groups/smtp:{mail}/calendars/default/events?isOnlineMeeting=true&shouldDecryptData=false"
        );
        return Ok(post(url, ev)
            .await?
            .get("value")
            .cloned()
            .unwrap_or_default());
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
    let url = format!(
        "{base}/v2.0/me/calendars/default/events?isOnlineMeeting={}&shouldDecryptData=true",
        form.online
    );
    Ok(post(url, body)
        .await?
        .get("value")
        .cloned()
        .unwrap_or_default())
}

/// Cast's meetings step (cast-app's CastWizard, read 2026-11-19): your
/// Teams meetings from 60 minutes ago to 60 minutes ahead (Teams reads its
/// calendar cache for that window), all-day ones first, then by start and
/// subject; cancelled ones and ones without a Teams link left out.
pub fn cast_meetings(
    events: &[CalendarEvent],
    now: chrono::DateTime<chrono::Utc>,
) -> Vec<&CalendarEvent> {
    let at = |s: &str| {
        chrono::DateTime::parse_from_rfc3339(s)
            .ok()
            .map(|d| d.with_timezone(&chrono::Utc))
    };
    let (from, to) = (
        now - chrono::Duration::minutes(60),
        now + chrono::Duration::minutes(60),
    );
    let mut out: Vec<&CalendarEvent> = events
        .iter()
        .filter(|e| !e.is_cancelled && e.join_url.as_deref().is_some_and(|u| !u.is_empty()))
        .filter(|e| match (at(&e.start_utc), at(&e.end_utc)) {
            (Some(s), Some(en)) => s < to && en > from,
            _ => false,
        })
        .collect();
    out.sort_by(|a, b| {
        b.is_all_day
            .cmp(&a.is_all_day)
            .then(a.start_utc.cmp(&b.start_utc))
            .then(a.subject.cmp(&b.subject))
    });
    out
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

/// The meeting chat's `meeting` property after Teams'
/// instantMeetingService.updateInstantMeetingInfo: the subject, meetingType
/// "MeetNow" and, for a Meet now that is being started (not only a link to
/// share), its start and end both set to `started_at` (Teams'
/// `startTime = endTime = new Date`). Teams Rooms reads that end: a room
/// left alone in it leaves once its auto exit applies.
pub fn instant_meeting_property(
    meeting: &serde_json::Value,
    title: &str,
    started_at: Option<&str>,
) -> serde_json::Value {
    let mut m = meeting.clone();
    if !m.is_object() {
        m = serde_json::json!({});
    }
    m["subject"] = title.into();
    m["meetingType"] = "MeetNow".into();
    if let Some(t) = started_at {
        m["startTime"] = t.into();
        m["endTime"] = t.into();
    }
    m
}

/// Teams' update of a Meet now's chat right after making it
/// (updateInstantMeetingInfo): the chat's topic, then its `meeting`
/// property (`PUT {chatsvc}/v1/threads/{id}/properties?name=meeting`, the
/// property as JSON text). `started` is a Meet now being joined now (Start
/// meeting, Cast's Just cast), not "Get a link to share".
pub async fn update_instant_meeting(
    client: &TeamsClient,
    join_url: &str,
    title: &str,
    started: bool,
) -> Result<()> {
    let thread =
        crate::calling::breakout::thread_of_join_url(join_url).context("Not a meeting link")?;
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        thread
    );
    let v: serde_json::Value = client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Thread reply")?;
    let meeting: serde_json::Value = match v.pointer("/properties/meeting") {
        Some(serde_json::Value::String(s)) => {
            serde_json::from_str(s).context("The chat's meeting property")?
        }
        Some(o @ serde_json::Value::Object(_)) => o.clone(),
        _ => bail!("The chat has no meeting property"),
    };
    let now = chrono::Utc::now()
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    let updated = instant_meeting_property(&meeting, title, started.then_some(now.as_str()));
    super::msgactions::set_chat_topic(client, &thread, title.trim()).await?;
    let prop_url = format!(
        "{}/v1/threads/{}/properties?name=meeting",
        client.chat_service_url(),
        thread
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &prop_url,
            &serde_json::json!({ "meeting": updated.to_string() }),
        )
        .await?;
    Ok(())
}

/// A team's group mailbox (its calendar's `smtp:` address).
async fn group_mail(client: &TeamsClient, team_id: &str) -> Result<String> {
    if team_id.is_empty() || !team_id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Not a team id");
    }
    let v: serde_json::Value = client
        .graph_get(&format!("/groups/{team_id}?$select=mail"))
        .await?
        .json()
        .await?;
    v.get("mail")
        .and_then(|m| m.as_str())
        .filter(|m| m.contains('@'))
        .map(str::to_string)
        .context("The team has no mailbox")
}

/// Graph's immutable id as the middle tier names the event (its REST id,
/// as the scheduling form's objectId).
async fn rest_id(client: &TeamsClient, immutable: &str) -> Result<String> {
    let v: serde_json::Value = client
        .graph_post(
            "/me/translateExchangeIds",
            &serde_json::json!({ "inputIds": [event_path_id(immutable)?], "sourceIdType": "restImmutableEntryId", "targetIdType": "restId" }),
        )
        .await?
        .json()
        .await?;
    let id = v
        .pointer("/value/0/targetId")
        .and_then(|t| t.as_str())
        .context("No id for the event")?;
    Ok(id.replace('/', "-").replace('+', "_"))
}

/// Send an update for a meeting you organise, as Teams' form does (its
/// Send update: `PUT {mt}/v2.0/me/calendars/events/{objectId}?isOnlineMeeting=…`
/// with `{updatedCalendarEvent}`, from Teams' calendar service bundle);
/// the service sends the attendees the update.
pub async fn update_meeting(
    client: &TeamsClient,
    id: &str,
    form: &MeetingForm,
    me: &Me,
    join_url: &str,
    event_type: &str,
) -> Result<()> {
    let object_id = rest_id(client, id).await?;
    let me = &organizer(client, me).await;
    let mut ev = mt_event(form, me, None)?;
    ev["objectId"] = serde_json::json!(object_id);
    // The meeting's chat (Teams sends it in skypeTeamsData; without it the
    // service answers "Conversation id cannot be null").
    if let Some(link) = crate::calling::outgoing::MeetingLink::parse(join_url) {
        ev["skypeTeamsData"] = serde_json::json!(serde_json::json!({"cid": link.thread_id, "rid": 0, "mid": 0, "uid": me.mri, "private": !link.thread_id.ends_with("@thread.tacv2"), "type": 0}).to_string());
    }
    if let Some(t) = match event_type {
        "occurrence" => Some("Occurrence"),
        "exception" => Some("Exception"),
        "seriesMaster" => Some("RecurringMaster"),
        _ => None,
    } {
        ev["eventType"] = serde_json::json!(t);
    }
    if let Some(o) = ev.as_object_mut() {
        o.remove("TransactionId");
    }
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let r = client
        .http()
        .put(format!(
            "{base}/v2.0/me/calendars/events/{object_id}?isOnlineMeeting={}",
            form.online
        ))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "updatedCalendarEvent": ev }))
        .send()
        .await?;
    let status = r.status();
    if !status.is_success() {
        bail!(
            "{status}: {}",
            r.text()
                .await
                .unwrap_or_default()
                .chars()
                .take(300)
                .collect::<String>()
        );
    }
    Ok(())
}

/// Send an update for an event you organise, as Teams' event page does
/// (Outlook's form in the hosted calendar, for plain events and Teams
/// meetings alike; captured 2026-11-23): Outlook's `UpdateCalendarEvent`
/// with what changed (`SetItemField`s on the item) and the attendees added
/// and removed; Exchange sends the attendees the update. A changed repeat
/// goes to the series (Outlook's "Edit series"): the series master's id,
/// its `Recurrence`, and the times on the series' own start date. "This
/// and all following events" goes to the occurrence with `EventScope` 2:
/// Exchange ends the series before it and starts a new series from it.
pub async fn send_event_update(client: &TeamsClient, id: &str, form: &MeetingForm) -> Result<()> {
    let select = "$select=subject,start,end,isAllDay,location,showAs,attendees,type,seriesMasterId,recurrence";
    let get = |path_id: String| async move {
        client
            .graph_get_with(
                &format!("/me/events/{path_id}?{select}"),
                &[("Prefer", "IdType=\"ImmutableId\", outlook.timezone=\"UTC\"")],
            )
            .await?
            .json::<serde_json::Value>()
            .await
            .context("Failed to read the event")
    };
    let mut path_id = event_path_id(id)?.to_string();
    let mut cur = get(path_id.clone()).await?;
    // All events in the series (or a new repeat for it) go to the series
    // master; this and all following events to the occurrence itself.
    if (form.scope == "series"
        || (form.scope != "following" && form.recurrence_changed && form.recurrence.is_some()))
        && let Some(master) = cur
            .get("seriesMasterId")
            .and_then(|m| m.as_str())
            .filter(|m| !m.is_empty())
    {
        path_id = event_path_id(master)?.to_string();
        cur = get(path_id.clone()).await?;
    }
    let tz = mailbox_time_zone().await;
    let body = update_event_request(&ews_id(&path_id), &cur, form, &tz)?;
    let v = owa_action("UpdateCalendarEvent", &body).await?;
    let code = v
        .pointer("/Body/ResponseMessages/Items/0/ResponseCode")
        .and_then(|c| c.as_str())
        .unwrap_or("NoError");
    if code != "NoError" {
        bail!("Outlook didn't update the event: {code}");
    }
    Ok(())
}

/// The `UpdateCalendarEvent` request for [`send_event_update`]: the event as
/// Graph has it (`cur`, times in UTC) against the form.
fn update_event_request(
    ews: &str,
    cur: &serde_json::Value,
    form: &MeetingForm,
    tz: &str,
) -> Result<serde_json::Value> {
    let item_id = serde_json::json!({ "__type": "ItemId:#Exchange", "Id": ews });
    let set = |field: &str, item: serde_json::Value| {
        let mut it = serde_json::json!({ "__type": "CalendarItem:#Exchange" });
        if let (Some(o), Some(i)) = (it.as_object_mut(), item.as_object()) {
            o.extend(i.clone());
        }
        serde_json::json!({ "__type": "SetItemField:#Exchange", "Path": { "__type": "PropertyUri:#Exchange", "FieldURI": field }, "Item": it })
    };
    let mut updates = Vec::new();
    let cs = |p: &str| cur.pointer(p).and_then(|x| x.as_str()).unwrap_or_default();
    // Times: the form's, with their offset, in the mailbox's zone context.
    let start = chrono::DateTime::parse_from_rfc3339(&form.start)
        .with_context(|| format!("Not a time: {}", form.start))?;
    let end = chrono::DateTime::parse_from_rfc3339(&form.end)
        .with_context(|| format!("Not a time: {}", form.end))?;
    let utc = |t: &str| {
        chrono::NaiveDateTime::parse_from_str(t.split('.').next().unwrap_or(t), "%Y-%m-%dT%H:%M:%S")
            .ok()
            .map(|n| n.and_utc())
    };
    let same_time = utc(cs("/start/dateTime")) == Some(start.with_timezone(&chrono::Utc))
        && utc(cs("/end/dateTime")) == Some(end.with_timezone(&chrono::Utc));
    let all_day = cur
        .get("isAllDay")
        .and_then(|b| b.as_bool())
        .unwrap_or(false);
    let ews_time = |t: &chrono::DateTime<chrono::FixedOffset>| {
        t.format("%Y-%m-%dT%H:%M:%S%.3f%:z").to_string()
    };
    if form.subject.trim() != cs("/subject") {
        updates.push(set(
            "Subject",
            serde_json::json!({ "Subject": form.subject.trim() }),
        ));
    }
    // A series (its repeat changed): the times of day on the series' own
    // start date, as Outlook's series form shows them.
    let series = cs("/type") == "seriesMaster";
    let (start, end, same_time) = match utc(cs("/start/dateTime")).zip(utc(cs("/end/dateTime"))) {
        Some((s0, e0)) if series => {
            let off = *start.offset();
            let (s0, e0) = (s0.with_timezone(&off), e0.with_timezone(&off));
            let same = s0.time() == start.time() && e0 - s0 == end - start;
            let s = s0
                .date_naive()
                .and_time(start.time())
                .and_local_timezone(off)
                .single()
                .unwrap_or(s0);
            (s, s + (end - start), same)
        }
        _ => (start, end, same_time),
    };
    if !same_time || form.all_day != all_day {
        updates.push(set(
            "Start",
            serde_json::json!({ "Start": ews_time(&start) }),
        ));
        updates.push(set("End", serde_json::json!({ "End": ews_time(&end) })));
        updates.push(set(
            "IsAllDayEvent",
            serde_json::json!({ "IsAllDayEvent": form.all_day }),
        ));
    }
    // This and all following events (EventScope 2, captured 2026-11-23): a
    // new repeat starts on the occurrence's date.
    let following = form.scope == "following";
    if form.recurrence_changed
        && let Some(mut r) = form.recurrence.as_ref().and_then(ews_recurrence)
    {
        if following {
            r["RecurrenceRange"]["StartDate"] =
                start.date_naive().format("%Y-%m-%d").to_string().into();
        }
        updates.push(set("Recurrence", serde_json::json!({ "Recurrence": r })));
    }
    // (A Teams meeting's "Microsoft Teams Meeting" isn't in the form.)
    let cur_location = Some(cs("/location/displayName"))
        .filter(|l| *l != "Microsoft Teams Meeting")
        .unwrap_or_default();
    if form.location.trim() != cur_location {
        updates.push(set("Location", serde_json::json!({ "Location": { "__type": "EnhancedLocation:#Exchange", "DisplayName": form.location.trim() } })));
    }
    if form.body_changed {
        updates.push(set("Body", serde_json::json!({ "Body": { "__type": "BodyContentType:#Exchange", "BodyType": "HTML", "Value": form.body_html } })));
    }
    let show_as = match form.show_as.to_ascii_lowercase().as_str() {
        "free" => "Free",
        "tentative" => "Tentative",
        "oof" => "OOF",
        "workingelsewhere" => "WorkingElsewhere",
        _ => "Busy",
    };
    if !form.show_as.is_empty() && !cs("/showAs").eq_ignore_ascii_case(show_as) {
        updates.push(set(
            "LegacyFreeBusyStatus",
            serde_json::json!({ "FreeBusyType": show_as }),
        ));
    }
    // Attendees: the whole lists when they changed, and what was added and
    // removed (Teams sends both).
    let mailbox = |name: &str, address: &str| serde_json::json!({ "Mailbox": { "Name": if name.is_empty() { address } else { name }, "EmailAddress": address, "RoutingType": "SMTP" } });
    let had: Vec<(String, String, String)> = cur
        .get("attendees")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .filter(|a| a["type"].as_str() != Some("resource"))
        .map(|a| {
            (
                a.pointer("/emailAddress/address")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_ascii_lowercase(),
                a.pointer("/emailAddress/name")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string(),
                if a["type"].as_str() == Some("optional") {
                    "Optional"
                } else {
                    "Required"
                }
                .to_string(),
            )
        })
        .filter(|(m, _, _)| !m.is_empty())
        .collect();
    let want: Vec<(String, String, String)> = form
        .attendees
        .iter()
        .filter(|a| a.address.contains('@'))
        .map(|a| {
            (
                a.address.to_ascii_lowercase(),
                a.name.clone(),
                if a.kind == "Optional" {
                    "Optional"
                } else {
                    "Required"
                }
                .to_string(),
            )
        })
        .collect();
    let key = |l: &[(String, String, String)], kind: &str| {
        let mut v: Vec<String> = l
            .iter()
            .filter(|x| x.2 == kind)
            .map(|x| x.0.clone())
            .collect();
        v.sort();
        v
    };
    let mut body = serde_json::json!({
        "__type": "UpdateCalendarEventRequest:#Exchange",
        "EventId": item_id,
        "EventScope": if following { 2 } else { 0 },
        "ShouldSendUpdateToAttendees": false,
        "TargetAudience": form.target_audience.min(2),
        "ClientSupportsIrm": true,
    });
    // (This and all following events can't change the attendees: "You can
    // only change attendees by editing the series.")
    if !following
        && (key(&had, "Required") != key(&want, "Required")
            || key(&had, "Optional") != key(&want, "Optional"))
    {
        let list = |kind: &str| {
            want.iter()
                .filter(|x| x.2 == kind)
                .map(|x| mailbox(&x.1, &x.0))
                .collect::<Vec<_>>()
        };
        let diff = |a: &[(String, String, String)], b: &[(String, String, String)], kind: &str| {
            a.iter()
                .filter(|x| x.2 == kind && !b.iter().any(|y| y.2 == kind && y.0 == x.0))
                .map(|x| mailbox(&x.1, &x.0))
                .collect::<Vec<_>>()
        };
        updates.push(set(
            "OptionalAttendees",
            serde_json::json!({ "OptionalAttendees": list("Optional") }),
        ));
        updates.push(set(
            "RequiredAttendees",
            serde_json::json!({ "RequiredAttendees": list("Required") }),
        ));
        let b = body.as_object_mut().context("request")?;
        b.insert(
            "AddedRequiredAttendees".into(),
            diff(&want, &had, "Required").into(),
        );
        b.insert(
            "AddedOptionalAttendees".into(),
            diff(&want, &had, "Optional").into(),
        );
        b.insert("AddedResources".into(), serde_json::json!([]));
        b.insert(
            "RemovedRequiredAttendees".into(),
            diff(&had, &want, "Required").into(),
        );
        b.insert(
            "RemovedOptionalAttendees".into(),
            diff(&had, &want, "Optional").into(),
        );
        b.insert("RemovedResources".into(), serde_json::json!([]));
    }
    updates.extend(super::event_form::form_updates(&form.outlook));
    if updates.is_empty() {
        // Nothing the form shows changed: send the title again, so the
        // attendees still get the update.
        updates.push(set(
            "Subject",
            serde_json::json!({ "Subject": form.subject.trim() }),
        ));
    }
    body["ItemChange"] = serde_json::json!({ "__type": "ItemChange:#Exchange", "Updates": updates, "ItemId": item_id });
    Ok(serde_json::json!({
        "__type": "UpdateCalendarEventJsonRequest:#Exchange",
        "Header": {
            "__type": "JsonRequestHeaders:#Exchange",
            "RequestServerVersion": "V2018_01_08",
            "TimeZoneContext": { "__type": "TimeZoneContext:#Exchange", "TimeZoneDefinition": { "__type": "TimeZoneDefinitionType:#Exchange", "Id": tz } }
        },
        "Body": body,
    }))
}

/// The form's repeat (Teams' `{pattern: {patternType, daily|weekly|monthly|yearly}, range: {startDate, endDate}}`)
/// as Outlook's `RecurrenceType`, as its series form sends it (captured
/// 2026-11-23: `WeeklyRecurrence` with `DaysOfWeek` "Tuesday Thursday",
/// `FirstDayOfWeek` Sunday and `Interval`, then `EndDateRecurrence` with
/// `EndDate` and `StartDate`, or `NoEndRecurrence`).
fn ews_recurrence(r: &serde_json::Value) -> Option<serde_json::Value> {
    const DAYS: [&str; 7] = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
    ];
    const MONTHS: [&str; 12] = [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ];
    let p = r.get("pattern")?;
    let num = |v: &serde_json::Value, k: &str| v.get(k).and_then(|x| x.as_u64());
    let kind = |t: &str| (format!("{t}:#Exchange"), t.to_string());
    let pattern = match num(p, "patternType")? {
        1 => {
            let (ty, name) = kind("DailyRecurrence");
            serde_json::json!({ "__type": ty, "__typename": name, "Interval": num(&p["daily"], "interval").unwrap_or(1) })
        }
        2 => {
            let w = &p["weekly"];
            let mut days: Vec<usize> = w
                .get("daysOfTheWeek")?
                .as_array()?
                .iter()
                .filter_map(|d| d.as_u64())
                .map(|d| d as usize)
                .filter(|d| *d < 7)
                .collect();
            days.sort_unstable();
            days.dedup();
            if days.is_empty() {
                return None;
            }
            let (ty, name) = kind("WeeklyRecurrence");
            serde_json::json!({
                "__type": ty, "__typename": name,
                "DaysOfWeek": days.iter().map(|d| DAYS[*d]).collect::<Vec<_>>().join(" "),
                "FirstDayOfWeek": "Sunday",
                "Interval": num(w, "interval").unwrap_or(1),
            })
        }
        3 => {
            let m = &p["monthly"];
            let (ty, name) = kind("AbsoluteMonthlyRecurrence");
            serde_json::json!({ "__type": ty, "__typename": name, "DayOfMonth": num(m, "dayOfMonth")?, "Interval": num(m, "interval").unwrap_or(1) })
        }
        5 => {
            let y = &p["yearly"];
            let month = num(y, "month").filter(|m| (1..=12).contains(m))? as usize;
            let (ty, name) = kind("AbsoluteYearlyRecurrence");
            serde_json::json!({ "__type": ty, "__typename": name, "DayOfMonth": num(y, "dayOfMonth")?, "Month": MONTHS[month - 1] })
        }
        _ => return None,
    };
    let date = |k: &str| {
        r.pointer(&format!("/range/{k}"))
            .and_then(|d| d.as_str())
            .filter(|d| d.len() >= 10)
            .map(|d| d[..10].to_string())
    };
    let start = date("startDate")?;
    let range = match date("endDate") {
        Some(end) => {
            let (ty, name) = kind("EndDateRecurrence");
            serde_json::json!({ "__type": ty, "__typename": name, "EndDate": end, "StartDate": start })
        }
        None => {
            let (ty, name) = kind("NoEndRecurrence");
            serde_json::json!({ "__type": ty, "__typename": name, "StartDate": start })
        }
    };
    Some(
        serde_json::json!({ "__type": "RecurrenceType:#Exchange", "RecurrencePattern": pattern, "RecurrenceRange": range }),
    )
}

/// Cancel a meeting you organise, with an optional note, for one event, this
/// and the following events or the series (`scope`). A channel meeting is
/// cancelled in its team's calendar and post (`PUT {mt}/v2.0/groups/smtp:<group>/calendars/events/<iCalUId>/cancel`,
/// measured 2026-11-17).
pub async fn cancel_meeting(
    client: &TeamsClient,
    ev: &serde_json::Value,
    team_id: &str,
    note: &str,
    scope: &str,
) -> Result<()> {
    let s = |k: &str| {
        ev.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
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
        let group = format!("smtp:{mail}");
        let url = crate::auth::token_hosts::service_url(
            &base,
            crate::auth::token_hosts::Audience::Teams,
            &[
                "v2.0",
                "groups",
                &group,
                "calendars",
                "events",
                &uid,
                "cancel",
            ],
            &[],
        )?;
        client
            .http()
            .put(url)
            .bearer_auth(&token)
            .json(&body)
            .send()
            .await?
            .error_for_status()
            .context("Cancel the channel meeting")?;
        return Ok(());
    }
    // Every other event you organise is cancelled through Outlook, as
    // Teams' card and event page do.
    cancel_event(ev, scope, note).await
}

/// Which events a cancel takes, as Outlook's `CancelCalendarEvent` names
/// them (`EventScope`, captured on winpc 2026-11-23): 1 this event (of a
/// series, or one that doesn't repeat), 2 this and all following events, 3
/// all events in the series (sent with the series master's id).
fn cancel_scope(scope: &str) -> u8 {
    match scope {
        "following" => 2,
        "series" => 3,
        _ => 1,
    }
}

/// Cancel an event you organise as Teams' card ("Cancel ▾ This event /
/// This and all following events / All events in the series", then "Send")
/// and its event page's "Cancel meeting" do (Outlook's hosted calendar,
/// captured on winpc 2026-11-23): `CancelCalendarEvent` on the event (the
/// series master for all events) with its `EventScope` and the optional
/// message as HTML `Notes`. Exchange removes the events and sends the
/// attendees "Canceled: <subject>" with the message.
pub async fn cancel_event(ev: &serde_json::Value, scope: &str, note: &str) -> Result<()> {
    let s = |k: &str| {
        ev.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let id = if scope == "series" && !s("series_master_id").is_empty() {
        s("series_master_id")
    } else {
        s("id")
    };
    let tz = mailbox_time_zone().await;
    let body = cancel_event_request(&ews_id(event_path_id(&id)?), scope, note, &tz);
    let v = owa_action("CancelCalendarEvent", &body).await?;
    let code = v
        .pointer("/Body/ResponseMessages/Items/0/ResponseCode")
        .or_else(|| v.pointer("/Body/ResponseCode"))
        .and_then(|c| c.as_str())
        .unwrap_or("NoError");
    if code != "NoError" {
        bail!("Outlook didn't cancel the event: {code}");
    }
    Ok(())
}

/// The `CancelCalendarEvent` request for [`cancel_event`]. The message goes
/// as Outlook's editor writes it: a `<div>` a line.
fn cancel_event_request(ews: &str, scope: &str, note: &str, tz: &str) -> serde_json::Value {
    let mut body = serde_json::json!({
        "__type": "CancelCalendarEventRequest:#Exchange",
        "EventId": { "__type": "ItemId:#Exchange", "Id": ews },
        "EventScope": cancel_scope(scope),
        "ClientSupportsIrm": true,
    });
    let note = note.trim();
    if !note.is_empty() {
        let html: String = note
            .lines()
            .map(|l| {
                if l.trim().is_empty() {
                    "<div><br></div>".to_string()
                } else {
                    format!("<div>{}</div>", super::chat::html_escape(l))
                }
            })
            .collect();
        body["Notes"] = serde_json::json!({ "__type": "BodyContentType:#Exchange", "BodyType": "HTML", "Value": html });
    }
    serde_json::json!({
        "__type": "CancelCalendarEventJsonRequest:#Exchange",
        "Header": {
            "__type": "JsonRequestHeaders:#Exchange",
            "RequestServerVersion": "V2018_01_08",
            "TimeZoneContext": { "__type": "TimeZoneContext:#Exchange", "TimeZoneDefinition": { "__type": "TimeZoneDefinitionType:#Exchange", "Id": tz } }
        },
        "Body": body,
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn cancel_event_request_as_outlook_sends_it() {
        // This event, with a message (captured on winpc 2026-11-23).
        let r = super::cancel_event_request(
            "AAkBOQ=",
            "occurrence",
            "Sorry & bye\n\nnext week",
            "Pacific Standard Time",
        );
        assert_eq!(r["__type"], "CancelCalendarEventJsonRequest:#Exchange");
        assert_eq!(
            r["Header"]["TimeZoneContext"]["TimeZoneDefinition"]["Id"],
            "Pacific Standard Time"
        );
        assert_eq!(r["Body"]["EventId"]["Id"], "AAkBOQ=");
        assert_eq!(r["Body"]["EventScope"], 1);
        assert_eq!(r["Body"]["ClientSupportsIrm"], true);
        assert_eq!(r["Body"]["Notes"]["BodyType"], "HTML");
        assert_eq!(
            r["Body"]["Notes"]["Value"],
            "<div>Sorry &amp; bye</div><div><br></div><div>next week</div>"
        );
        // This and all following events; all events without a message.
        assert_eq!(
            super::cancel_event_request("x", "following", "", "UTC")["Body"]["EventScope"],
            2
        );
        let all = super::cancel_event_request("x", "series", "  ", "UTC");
        assert_eq!(all["Body"]["EventScope"], 3);
        assert!(all["Body"].get("Notes").is_none());
        // An event that doesn't repeat: this event.
        assert_eq!(
            super::cancel_event_request("x", "", "", "UTC")["Body"]["EventScope"],
            1
        );
    }

    #[test]
    fn update_event_sends_what_changed() {
        let cur = serde_json::json!({
            "subject": "Plan", "isAllDay": false, "showAs": "busy",
            "start": { "dateTime": "2026-11-26T22:00:00.0000000", "timeZone": "UTC" },
            "end": { "dateTime": "2026-11-26T22:30:00.0000000", "timeZone": "UTC" },
            "location": { "displayName": "" },
            "attendees": [{ "type": "required", "emailAddress": { "address": "b@x.com", "name": "B" } }]
        });
        let mut form = super::MeetingForm {
            subject: "Plan 2".into(),
            start: "2026-11-26T14:00:00-08:00".into(),
            end: "2026-11-26T14:30:00-08:00".into(),
            show_as: "Busy".into(),
            attendees: vec![super::FormAttendee {
                address: "b@x.com".into(),
                name: "B".into(),
                kind: "Required".into(),
            }],
            ..Default::default()
        };
        let r = super::update_event_request("ID/1=", &cur, &form, "Pacific Standard Time").unwrap();
        assert_eq!(
            r["Header"]["TimeZoneContext"]["TimeZoneDefinition"]["Id"],
            "Pacific Standard Time"
        );
        let ups = r["Body"]["ItemChange"]["Updates"].as_array().unwrap();
        assert_eq!(ups.len(), 1, "{ups:?}");
        assert_eq!(ups[0]["Path"]["FieldURI"], "Subject");
        assert_eq!(ups[0]["Item"]["Subject"], "Plan 2");
        assert_eq!(r["Body"]["EventId"]["Id"], "ID/1=");
        assert!(r["Body"].get("AddedRequiredAttendees").is_none());
        // A new attendee and a later time.
        form.attendees.push(super::FormAttendee {
            address: "c@x.com".into(),
            name: "C".into(),
            kind: "Required".into(),
        });
        form.start = "2026-11-26T15:00:00-08:00".into();
        form.end = "2026-11-26T15:30:00-08:00".into();
        let r = super::update_event_request("ID/1=", &cur, &form, "Pacific Standard Time").unwrap();
        let fields: Vec<&str> = r["Body"]["ItemChange"]["Updates"]
            .as_array()
            .unwrap()
            .iter()
            .map(|u| u["Path"]["FieldURI"].as_str().unwrap())
            .collect();
        assert_eq!(
            fields,
            [
                "Subject",
                "Start",
                "End",
                "IsAllDayEvent",
                "OptionalAttendees",
                "RequiredAttendees"
            ]
        );
        let start = &r["Body"]["ItemChange"]["Updates"][1]["Item"]["Start"];
        assert_eq!(start, "2026-11-26T15:00:00.000-08:00");
        assert_eq!(
            r["Body"]["AddedRequiredAttendees"][0]["Mailbox"]["EmailAddress"],
            "c@x.com"
        );
        assert_eq!(
            r["Body"]["RemovedRequiredAttendees"]
                .as_array()
                .unwrap()
                .len(),
            0
        );
        assert_eq!(
            r["Body"]["ItemChange"]["Updates"][5]["Item"]["RequiredAttendees"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
    }

    #[test]
    fn a_new_repeat_goes_to_the_series_as_outlook_sends_it() {
        // Teams' event page, Edit series, Tuesday + Thursday (captured
        // 2026-11-23): only the Recurrence, on the series master.
        let master = serde_json::json!({
            "subject": "Series", "isAllDay": false, "showAs": "busy", "type": "seriesMaster",
            "start": { "dateTime": "2026-11-24T23:00:00.0000000", "timeZone": "UTC" },
            "end": { "dateTime": "2026-11-24T23:30:00.0000000", "timeZone": "UTC" },
            "location": { "displayName": "" },
            "attendees": [{ "type": "required", "emailAddress": { "address": "b@x.com", "name": "B" } }]
        });
        // The form was opened on the 12/1 occurrence.
        let mut form = super::MeetingForm {
            subject: "Series".into(),
            start: "2026-12-01T15:00:00-08:00".into(),
            end: "2026-12-01T15:30:00-08:00".into(),
            show_as: "Busy".into(),
            attendees: vec![super::FormAttendee {
                address: "b@x.com".into(),
                name: "B".into(),
                kind: "Required".into(),
            }],
            recurrence: Some(serde_json::json!({
                "pattern": { "patternType": 2, "weekly": { "interval": 1, "daysOfTheWeek": [4, 2] } },
                "range": { "startDate": "2026-11-24T00:00:00-08:00", "endDate": "2026-12-15T00:00:00-08:00" }
            })),
            recurrence_changed: true,
            ..Default::default()
        };
        let r =
            super::update_event_request("M/1=", &master, &form, "Pacific Standard Time").unwrap();
        let ups = r["Body"]["ItemChange"]["Updates"].as_array().unwrap();
        assert_eq!(ups.len(), 1, "{ups:?}");
        assert_eq!(ups[0]["Path"]["FieldURI"], "Recurrence");
        let rec = &ups[0]["Item"]["Recurrence"];
        assert_eq!(rec["__type"], "RecurrenceType:#Exchange");
        assert_eq!(
            rec["RecurrencePattern"]["__type"],
            "WeeklyRecurrence:#Exchange"
        );
        assert_eq!(rec["RecurrencePattern"]["DaysOfWeek"], "Tuesday Thursday");
        assert_eq!(rec["RecurrencePattern"]["FirstDayOfWeek"], "Sunday");
        assert_eq!(rec["RecurrencePattern"]["Interval"], 1);
        assert_eq!(
            rec["RecurrenceRange"]["__type"],
            "EndDateRecurrence:#Exchange"
        );
        assert_eq!(rec["RecurrenceRange"]["StartDate"], "2026-11-24");
        assert_eq!(rec["RecurrenceRange"]["EndDate"], "2026-12-15");
        assert_eq!(r["Body"]["EventId"]["Id"], "M/1=");
        assert_eq!(r["Body"]["TargetAudience"], 0);
        // A later time of day moves the series, on its own start date.
        form.start = "2026-12-01T16:00:00-08:00".into();
        form.end = "2026-12-01T17:00:00-08:00".into();
        let r =
            super::update_event_request("M/1=", &master, &form, "Pacific Standard Time").unwrap();
        let ups = r["Body"]["ItemChange"]["Updates"].as_array().unwrap();
        assert_eq!(ups[0]["Item"]["Start"], "2026-11-24T16:00:00.000-08:00");
        assert_eq!(ups[1]["Item"]["End"], "2026-11-24T17:00:00.000-08:00");
        // Unchanged repeat: no Recurrence.
        form.recurrence_changed = false;
        let r =
            super::update_event_request("M/1=", &master, &form, "Pacific Standard Time").unwrap();
        assert!(
            r["Body"]["ItemChange"]["Updates"]
                .as_array()
                .unwrap()
                .iter()
                .all(|u| u["Path"]["FieldURI"] != "Recurrence")
        );
        // Other repeats.
        let rec = |p: serde_json::Value, end: Option<&str>| {
            let mut range = serde_json::json!({ "startDate": "2026-11-24T00:00:00-08:00" });
            if let Some(e) = end {
                range["endDate"] = e.into();
            }
            super::ews_recurrence(&serde_json::json!({ "pattern": p, "range": range })).unwrap()
        };
        let d = rec(
            serde_json::json!({ "patternType": 1, "daily": { "interval": 2 } }),
            None,
        );
        assert_eq!(
            d["RecurrencePattern"]["__type"],
            "DailyRecurrence:#Exchange"
        );
        assert_eq!(d["RecurrencePattern"]["Interval"], 2);
        assert_eq!(d["RecurrenceRange"]["__type"], "NoEndRecurrence:#Exchange");
        let m = rec(
            serde_json::json!({ "patternType": 3, "monthly": { "interval": 1, "dayOfMonth": 24 } }),
            Some("2027-03-01T00:00:00-08:00"),
        );
        assert_eq!(
            m["RecurrencePattern"]["__type"],
            "AbsoluteMonthlyRecurrence:#Exchange"
        );
        assert_eq!(m["RecurrencePattern"]["DayOfMonth"], 24);
        let y = rec(
            serde_json::json!({ "patternType": 5, "yearly": { "interval": 1, "month": 11, "dayOfMonth": 24 } }),
            None,
        );
        assert_eq!(y["RecurrencePattern"]["Month"], "November");
    }

    #[test]
    fn this_and_all_following_goes_to_the_occurrence_as_outlook_sends_it() {
        // Teams' event page, Edit ▸ This and all following events on the
        // 12/7 occurrence, 9:30 PM, Monday + Wednesday (captured
        // 2026-11-23): EventScope 2 on the occurrence, the new repeat from
        // its date.
        let occ = serde_json::json!({
            "subject": "Follow", "isAllDay": false, "showAs": "busy", "type": "occurrence", "seriesMasterId": "M",
            "start": { "dateTime": "2026-12-08T05:00:00.0000000", "timeZone": "UTC" },
            "end": { "dateTime": "2026-12-08T05:30:00.0000000", "timeZone": "UTC" },
            "location": { "displayName": "" },
            "attendees": [{ "type": "required", "emailAddress": { "address": "b@x.com", "name": "B" } }]
        });
        let mut form = super::MeetingForm {
            subject: "Follow B".into(),
            start: "2026-12-07T21:00:00-08:00".into(),
            end: "2026-12-07T21:30:00-08:00".into(),
            show_as: "Busy".into(),
            attendees: vec![super::FormAttendee {
                address: "b@x.com".into(),
                name: "B".into(),
                kind: "Required".into(),
            }],
            scope: "following".into(),
            ..Default::default()
        };
        let r = super::update_event_request("O/1=", &occ, &form, "Pacific Standard Time").unwrap();
        assert_eq!(r["Body"]["EventScope"], 2);
        assert_eq!(r["Body"]["EventId"]["Id"], "O/1=");
        let ups = r["Body"]["ItemChange"]["Updates"].as_array().unwrap();
        assert_eq!(ups.len(), 1, "{ups:?}");
        assert_eq!(ups[0]["Item"]["Subject"], "Follow B");
        // A new time and repeat: the occurrence's times, the repeat from its
        // date (the form still holds the series' start).
        form.start = "2026-12-07T21:30:00-08:00".into();
        form.end = "2026-12-07T22:00:00-08:00".into();
        form.recurrence = Some(serde_json::json!({
            "pattern": { "patternType": 2, "weekly": { "interval": 1, "daysOfTheWeek": [1, 3] } },
            "range": { "startDate": "2026-11-23T00:00:00-08:00", "endDate": "2027-05-17T00:00:00-08:00" }
        }));
        form.recurrence_changed = true;
        // Attendees can't change from here.
        form.attendees.push(super::FormAttendee {
            address: "c@x.com".into(),
            name: "C".into(),
            kind: "Required".into(),
        });
        let r = super::update_event_request("O/1=", &occ, &form, "Pacific Standard Time").unwrap();
        let ups = r["Body"]["ItemChange"]["Updates"].as_array().unwrap();
        let field = |f: &str| {
            ups.iter()
                .find(|u| u["Path"]["FieldURI"] == f)
                .cloned()
                .unwrap_or_default()
        };
        assert_eq!(
            field("Start")["Item"]["Start"],
            "2026-12-07T21:30:00.000-08:00"
        );
        assert_eq!(field("End")["Item"]["End"], "2026-12-07T22:00:00.000-08:00");
        let rec = &field("Recurrence")["Item"]["Recurrence"];
        assert_eq!(rec["RecurrencePattern"]["DaysOfWeek"], "Monday Wednesday");
        assert_eq!(rec["RecurrenceRange"]["StartDate"], "2026-12-07");
        assert_eq!(rec["RecurrenceRange"]["EndDate"], "2027-05-17");
        assert!(r["Body"].get("AddedRequiredAttendees").is_none());
        assert!(
            ups.iter()
                .all(|u| u["Path"]["FieldURI"] != "RequiredAttendees")
        );
        // The series (Edit series): EventScope 0.
        form.scope = "series".into();
        let r = super::update_event_request("M/1=", &occ, &form, "Pacific Standard Time").unwrap();
        assert_eq!(r["Body"]["EventScope"], 0);
    }

    #[test]
    fn only_added_attendees_get_the_update_when_asked() {
        let cur = serde_json::json!({
            "subject": "Plan", "isAllDay": false, "showAs": "busy",
            "start": { "dateTime": "2026-11-26T23:00:00.0000000", "timeZone": "UTC" },
            "end": { "dateTime": "2026-11-26T23:30:00.0000000", "timeZone": "UTC" },
            "location": { "displayName": "" },
            "attendees": [{ "type": "required", "emailAddress": { "address": "c@x.com", "name": "C" } }]
        });
        let form = super::MeetingForm {
            subject: "Plan".into(),
            start: "2026-11-26T15:00:00-08:00".into(),
            end: "2026-11-26T15:30:00-08:00".into(),
            show_as: "Busy".into(),
            attendees: vec![
                super::FormAttendee {
                    address: "c@x.com".into(),
                    name: "C".into(),
                    kind: "Required".into(),
                },
                super::FormAttendee {
                    address: "b@x.com".into(),
                    name: "B".into(),
                    kind: "Required".into(),
                },
            ],
            target_audience: 2,
            ..Default::default()
        };
        let r = super::update_event_request("ID/1=", &cur, &form, "Pacific Standard Time").unwrap();
        assert_eq!(r["Body"]["TargetAudience"], 2);
        assert_eq!(
            r["Body"]["AddedRequiredAttendees"][0]["Mailbox"]["EmailAddress"],
            "b@x.com"
        );
    }

    #[test]
    fn cast_lists_meetings_as_teams() {
        let ev = |subject: &str, start: &str, end: &str, all_day: bool, link: bool| {
            super::CalendarEvent {
                subject: subject.into(),
                start_utc: start.into(),
                end_utc: end.into(),
                is_all_day: all_day,
                join_url: link.then(|| "https://teams.microsoft.com/l/meetup-join/x".to_string()),
                ..Default::default()
            }
        };
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-20T10:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let list = vec![
            ev(
                "B later",
                "2026-11-20T10:30:00Z",
                "2026-11-20T11:00:00Z",
                false,
                true,
            ),
            ev(
                "A earlier",
                "2026-11-20T09:30:00Z",
                "2026-11-20T10:30:00Z",
                false,
                true,
            ),
            ev(
                "No link",
                "2026-11-20T10:00:00Z",
                "2026-11-20T10:30:00Z",
                false,
                false,
            ),
            ev(
                "Too late",
                "2026-11-20T11:00:00Z",
                "2026-11-20T11:30:00Z",
                false,
                true,
            ),
            ev(
                "Over",
                "2026-11-20T08:00:00Z",
                "2026-11-20T09:00:00Z",
                false,
                true,
            ),
            ev(
                "All day",
                "2026-11-20T00:00:00Z",
                "2026-11-21T00:00:00Z",
                true,
                true,
            ),
        ];
        let got: Vec<&str> = super::cast_meetings(&list, now)
            .iter()
            .map(|e| e.subject.as_str())
            .collect();
        assert_eq!(got, vec!["All day", "A earlier", "B later"]);
    }

    #[test]
    fn scheduling_bodies_match_teams_form() {
        let me = super::Me {
            name: "OST Test 1".into(),
            mail: "t1@x.com".into(),
            mri: "8:orgid:1".into(),
        };
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
        ch.channel = Some(super::FormChannel {
            channel_id: "19:c@thread.tacv2".into(),
            ..Default::default()
        });
        ch.recurrence = Some(
            serde_json::json!({"pattern": {"patternType": 2, "weekly": {"interval": 1, "daysOfTheWeek": [2]}}, "range": {"startDate": "2026-11-17T00:00:00-08:00"}}),
        );
        let c = super::mt_event(&ch, &me, Some("Team@x.com")).unwrap();
        assert_eq!(c["eventType"], "RecurringMaster");
        assert_eq!(c["mailboxAddress"], "Team@x.com");
        assert_eq!(
            c["attendees"].as_array().unwrap().last().unwrap()["address"],
            "Team@x.com"
        );
        assert!(
            c["skypeTeamsData"]
                .as_str()
                .unwrap()
                .contains("19:c@thread.tacv2")
        );
        assert_eq!(c["eventRecurrencePattern"]["patternType"], 2);
    }

    #[test]
    fn a_virtual_appointment_is_sent_as_teams_sends_it() {
        // Calendar ▸ New ▸ Virtual appointment, Send (captured 2026-11-19).
        let me = super::Me {
            name: "OST Test 1".into(),
            mail: "t1@x.com".into(),
            mri: "8:orgid:1".into(),
        };
        let form: super::MeetingForm = serde_json::from_value(serde_json::json!({
            "subject": "OST TEST 217 virtual appointment", "start": "2026-11-18T23:30:00-08:00", "end": "2026-11-19T00:00:00-08:00",
            "online": true, "timeZone": "PacificSt", "templateId": super::VIRTUAL_APPOINTMENT_TEMPLATE,
            "guests": [{"displayName": "OST Test 2", "emailAddress": "t2@x.com"}]
        }))
        .unwrap();
        let e = super::mt_event(&form, &me, None).unwrap();
        assert_eq!(
            e["meetingTemplateId"],
            "firstparty_e514e598-fba6-4e1f-b8b3-138dd3bca748"
        );
        assert_eq!(e["isAppointment"], false);
        assert_eq!(e["attendees"].as_array().unwrap().len(), 1);
        assert_eq!(
            e["virtualAppointmentInfo"],
            serde_json::json!({
            "appointmentClients": [{"displayName": "OST Test 2", "emailAddress": "t2@x.com"}], "eTag": "", "isSmsEligible": false,
            "settings": {"allowClientToJoinUsingBrowser": true, "notifications": [], "organizerLocale": "en-us"}})
        );
        let plain: super::MeetingForm = serde_json::from_value(serde_json::json!({"start": "2026-11-18T23:30:00-08:00", "end": "2026-11-19T00:00:00-08:00"})).unwrap();
        let p = super::mt_event(&plain, &me, None).unwrap();
        assert_eq!(p["meetingTemplateId"], "default");
        assert!(p.get("virtualAppointmentInfo").is_none());
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
        assert_eq!(
            e.channel_id,
            "19:782662e702f14fa7b33f95096b357dd8@thread.tacv2"
        );
        assert_eq!(e.channel_message_id, "1794905737503");
    }

    #[test]
    fn answers_are_built_as_teams_calendar_sends_them() {
        let b = super::respond_body(
            "AAk/x+y=",
            "Tentative",
            3,
            true,
            "a < b",
            "Pacific Standard Time",
        );
        assert_eq!(b["Body"]["EventId"]["Id"], "AAk/x+y=");
        assert_eq!(b["Body"]["Response"], "Tentative");
        assert_eq!(b["Body"]["Attendance"], 3);
        assert_eq!(b["Body"]["SendResponse"], true);
        assert_eq!(b["Body"]["Notes"]["Value"], "<div>a &lt; b</div>");
        assert!(
            super::respond_body("x", "Accept", 0, false, " ", "UTC")["Body"]
                .get("Notes")
                .is_none()
        );
        assert_eq!(super::ews_id("AAkAL-Q_xyz"), "AAkAL/Q+xyz=");
    }

    #[test]
    fn instant_meeting_property_is_teams_update() {
        // A Meet now chat as the scheduling service makes it, and as Teams'
        // Cast left it (startTime = endTime = when it was started).
        let made = serde_json::json!({"subject": "Meeting", "startTime": "0001-01-01T00:00:00", "endTime": "0001-01-01T00:00:00", "meetingType": "MeetNow", "isCancelled": false, "eventType": "Single"});
        let started = super::instant_meeting_property(
            &made,
            "OST Test Room",
            Some("2026-11-24T04:11:50.707Z"),
        );
        assert_eq!(started["subject"], "OST Test Room");
        assert_eq!(started["meetingType"], "MeetNow");
        assert_eq!(started["startTime"], "2026-11-24T04:11:50.707Z");
        assert_eq!(started["endTime"], "2026-11-24T04:11:50.707Z");
        assert_eq!(started["eventType"], "Single");
        // Get a link to share: subject and type only.
        let link = super::instant_meeting_property(&made, "Sync", None);
        assert_eq!(link["subject"], "Sync");
        assert_eq!(link["endTime"], "0001-01-01T00:00:00");
    }

    #[test]
    fn availability_takes_the_strongest_overlapping_status() {
        let u = serde_json::json!({"freeBusyEvents": [
            {"freeBusyStatus": "Tentative", "startTime": "2026-11-17T22:00:00+00:00", "endTime": "2026-11-17T22:30:00+00:00"},
            {"freeBusyStatus": "Busy", "startTime": "2026-11-17T23:00:00+00:00", "endTime": "2026-11-17T23:30:00+00:00"}
        ]});
        let t = |s: &str| chrono::DateTime::parse_from_rfc3339(s).unwrap();
        assert_eq!(
            super::busiest(&u, t("2026-11-17T22:00:00Z"), t("2026-11-17T22:30:00Z")),
            "Tentative"
        );
        assert_eq!(
            super::busiest(&u, t("2026-11-17T22:00:00Z"), t("2026-11-17T23:15:00Z")),
            "Busy"
        );
        assert_eq!(
            super::busiest(&u, t("2026-11-18T00:00:00Z"), t("2026-11-18T01:00:00Z")),
            "Free"
        );
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

    #[test]
    fn calendar_settings_are_read_as_outlook_keeps_them() {
        // OutlookCloudSettings: a JSON setting's value is a string.
        let v = serde_json::json!([{"name": "calendar_filters", "type": "Json", "value": "[[\"Reservations\",[\"Desk\"]]]"}]);
        assert_eq!(
            cloud_setting_value(&v, "calendar_filters").unwrap(),
            serde_json::json!([["Reservations", ["Desk"]]])
        );
        assert!(cloud_setting_value(&v, "calendar_apptreminders").is_none());
        // Outlook options: CalendarSurfaceOptions is feature 15.
        assert!(is_surface_options(
            &serde_json::json!({"feature": 15, "timeScaleSetting": 30})
        ));
        assert!(!is_surface_options(&serde_json::json!({"feature": 2})));
    }

    #[test]
    fn proposals_come_from_the_attendees_proposed_time() {
        let v = serde_json::json!({"value": [{"id": "x", "attendees": [{"emailAddress": {"name": "OST Test 3", "address": "t3@x"}, "type": "required",
            "status": {"response": "tentativelyAccepted"},
            "proposedNewTime": {"start": {"dateTime": "2026-11-20T18:00:00.0000000", "timeZone": "UTC"}, "end": {"dateTime": "2026-11-20T18:30:00.0000000", "timeZone": "UTC"}}},
            {"emailAddress": {"name": "B", "address": "b@x"}, "type": "required", "status": {"response": "accepted"}}], "isDraft": true}]});
        let e = &parse_events(&v)[0];
        assert!(e.is_draft);
        assert_eq!(e.attendees[0].proposed_start, "2026-11-20T18:00:00Z");
        assert_eq!(e.attendees[0].proposed_end, "2026-11-20T18:30:00Z");
        assert!(e.attendees[1].proposed_start.is_empty());
    }

    #[test]
    fn outlook_items_fill_what_graph_lacks() {
        let mut events =
            parse_events(&serde_json::json!({"value": [{"id": "AAkALg_x-y", "subject": "Hold"}]}));
        let mut items = std::collections::HashMap::new();
        items.insert(ews_id("AAkALg_x-y"), serde_json::json!({"IsMeeting": true, "EventPollMetadata": "Type:AttendeeHold|VoteType:Yes|HoldId:1",
            "CalendarEventClassifications": ["DeskBooking"], "RequestedAttendanceMode": "InPersonRequired", "Charm": "Plane"}));
        merge_outlook_items(&mut events, &items);
        let e = &events[0];
        assert_eq!(e.is_meeting, Some(true));
        assert_eq!(
            (e.poll_hold.as_str(), e.poll_vote.as_str()),
            ("AttendeeHold", "Yes")
        );
        assert!(e.is_desk_booking);
        assert_eq!(e.attendance_mode, "InPersonRequired");
        assert_eq!(e.charm, "Plane");
        // An event made in Outlook's form (Teams' New event): its view's
        // CharmId, Charm "None" (GetCalendarView, 2026-11-24).
        items.insert(
            ews_id("AAkALg_x-y"),
            serde_json::json!({"Charm": "None", "CharmId": 57}),
        );
        merge_outlook_items(&mut events, &items);
        assert_eq!(events[0].charm, "57");
        items.insert(
            ews_id("AAkALg_x-y"),
            serde_json::json!({"Charm": "None", "CharmId": 0}),
        );
        merge_outlook_items(&mut events, &items);
        assert_eq!(events[0].charm, "");
    }

    #[test]
    fn a_proposal_goes_in_the_answer_as_local_times() {
        let b = respond_body("AAMk=", "Tentative", 0, true, "", "Pacific Standard Time");
        assert_eq!(b["Body"]["ProposedStartTime"], "");
        assert!(
            ows_path_ok("ows/v1/SaveCalendarView")
                && !ows_path_ok("/ows/x")
                && !ows_path_ok("ows/../owa")
        );
    }
}

/// An Outlook web service path OST may ask for (`ows/…`, relative).
fn ows_path_ok(path: &str) -> bool {
    !(path.starts_with('/') || path.contains("..") || !path.starts_with("ows/"))
}
