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
                // Follow is Outlook's Tentative with attendance Follow: free, and
                // the subject marked "Following: ".
                response: match s(e, "/responseStatus/response") {
                    r if r == "tentativelyAccepted" && s(e, "/subject").starts_with("Following: ") => "following".to_string(),
                    r => r,
                },
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
pub async fn respond(client: &TeamsClient, ev: &RsvpTarget, response: &str, send_response: bool, note: &str) -> Result<()> {
    let (owa_response, attendance) = match response {
        "Accept" | "Tentative" | "Decline" => (response, 0),
        "Follow" => ("Tentative", 3),
        other => bail!("Not a response: {other}"),
    };
    if crate::auth::oauth::browser_sign_in() {
        let id = event_path_id(&ev.id)?;
        let tz = mailbox_time_zone().await;
        owa_action("RespondToCalendarEvent", &respond_body(&ews_id(id), owa_response, attendance, send_response, note, &tz)).await?;
        return Ok(());
    }
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
async fn respond_mt(client: &TeamsClient, ev: &RsvpTarget, response: &str, send_response: bool, note: &str) -> Result<()> {
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
        .map(|d| d.with_timezone(&chrono::Utc).format("%Y-%m-%dT%H:%M:%S.000Z").to_string())
        .unwrap_or_default();
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let q: String = url::form_urlencoded::Serializer::new(String::new())
        .append_pair("eventType", event_type)
        .append_pair("eventStartDateTime", &start)
        .finish();
    let r = client
        .http()
        .put(format!("{base}/v2.0/me/calendars/events/{uid}/respond?{q}"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "responseType": kind, "sendResponse": send_response, "comment": note.trim(), "attendance": attendance }))
        .send()
        .await?;
    let status = r.status();
    if !status.is_success() {
        bail!("{status}: {}", r.text().await.unwrap_or_default().chars().take(300).collect::<String>());
    }
    Ok(())
}

fn respond_body(ews_id: &str, response: &str, attendance: u8, send_response: bool, note: &str, tz: &str) -> serde_json::Value {
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
        let esc = note.trim().replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('\n', "<br>");
        b["Body"]["Notes"] = serde_json::json!({ "__type": "BodyContentType:#Exchange", "BodyType": "HTML", "Value": format!("<div>{esc}</div>") });
    }
    b
}

/// Graph's URL-safe immutable id as Exchange writes it (standard base64,
/// padded).
fn ews_id(rest_id: &str) -> String {
    let mut s = rest_id.replace('-', "/").replace('_', "+");
    while s.len() % 4 != 0 {
        s.push('=');
    }
    s
}

/// The hosted Outlook calendar's app in Teams (its broker token request:
/// `brk-multihub://outlook.office.com`, scope `https://outlook.office.com/.default`).
const HOSTED_CALENDAR_APP: &str = "ceb96695-e468-48ba-ba21-35e2a242d396";

/// A browser's User-Agent, as the hosted calendar's web view sends (Outlook
/// on the web fails every action without one).
const OWA_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0";

/// One Outlook on the web service action as Teams' hosted calendar sends
/// it: the request JSON URL-encoded in `x-owa-urlpostdata`, an empty body,
/// and its headers (`action`, `x-owa-actionsource`, `x-req-source:
/// Calendar`, `x-owa-hosted-ux: true`, a session and correlation id, the
/// tenant, `prefer: IdType="ImmutableId"…`).
pub async fn owa_action(action: &str, body: &serde_json::Value) -> Result<serde_json::Value> {
    if !action.bytes().all(|b| b.is_ascii_alphanumeric()) {
        bail!("Not an action: {action}");
    }
    let (token, _) = crate::auth::oauth::brokered_token(HOSTED_CALENDAR_APP, "https://outlook.office.com", "https://outlook.office.com/.default", None).await?;
    let tenant = crate::config::Config::load().ok().and_then(|c| c.tenant_id).unwrap_or_default();
    static SESSION: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let session = SESSION.get_or_init(|| uuid::Uuid::new_v4().to_string());
    let anchor = crate::config::Config::load().ok().and_then(|c| c.object_id()).map(|o| format!("OID:{o}@{tenant}")).unwrap_or_default();
    // encodeURIComponent, as the page encodes it: a space is %20 (a "+"
    // would reach the service as a plus: "Pacific+Standard+Time").
    let data = url::form_urlencoded::byte_serialize(body.to_string().as_bytes()).collect::<String>().replace('+', "%20");
    let resp = reqwest::Client::new()
        .post(format!("https://outlook.office.com/owa/service.svc?action={action}&app=Calendar"))
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
        .header("prefer", "IdType=\"ImmutableId\", exchange.behavior=\"IncludeThirdPartyOnlineMeetingProviders\"")
        .header("content-type", "application/json; charset=utf-8")
        .header("x-owa-urlpostdata", data)
        .body("")
        .send()
        .await
        .with_context(|| format!("{action} failed"))?;
    let status = resp.status();
    let err = resp.headers().get("x-owa-error").and_then(|v| v.to_str().ok()).unwrap_or_default().to_string();
    let text = resp.text().await.unwrap_or_default();
    let v: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    let class = v.pointer("/Body/ResponseClass").and_then(|c| c.as_str()).unwrap_or_default();
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
            out.mri = v["id"].as_str().map(|id| format!("8:orgid:{id}")).unwrap_or_default();
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
    let id = v.pointer("/value/0/targetId").and_then(|t| t.as_str()).context("No id for the event")?;
    Ok(id.replace('/', "-").replace('+', "_"))
}

/// Send an update for a meeting you organise, as Teams' form does (its
/// Send update: `PUT {mt}/v2.0/me/calendars/events/{objectId}?isOnlineMeeting=…`
/// with `{updatedCalendarEvent}`, from Teams' calendar service bundle);
/// the service sends the attendees the update.
pub async fn update_meeting(client: &TeamsClient, id: &str, form: &MeetingForm, me: &Me, join_url: &str, event_type: &str) -> Result<()> {
    let object_id = rest_id(client, id).await?;
    let me = &organizer(client, me).await;
    let mut ev = mt_event(form, me, None)?;
    ev["objectId"] = serde_json::json!(object_id);
    // The meeting's chat (Teams sends it in skypeTeamsData; without it the
    // service answers "Conversation id cannot be null").
    if let Some(link) = crate::calling::outgoing::MeetingLink::parse(join_url) {
        ev["skypeTeamsData"] = serde_json::json!(serde_json::json!({"cid": link.thread_id, "rid": 0, "mid": 0, "uid": me.mri, "private": !link.thread_id.ends_with("@thread.tacv2"), "type": 0}).to_string());
    }
    if let Some(t) = match event_type { "occurrence" => Some("Occurrence"), "exception" => Some("Exception"), "seriesMaster" => Some("RecurringMaster"), _ => None } {
        ev["eventType"] = serde_json::json!(t);
    }
    if let Some(o) = ev.as_object_mut() {
        o.remove("TransactionId");
    }
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let r = client
        .http()
        .put(format!("{base}/v2.0/me/calendars/events/{object_id}?isOnlineMeeting={}", form.online))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "updatedCalendarEvent": ev }))
        .send()
        .await?;
    let status = r.status();
    if !status.is_success() {
        bail!("{status}: {}", r.text().await.unwrap_or_default().chars().take(300).collect::<String>());
    }
    Ok(())
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
    // Teams' own cancel (`PUT {mt}/v2.0/me/calendars/events/{objectId}/cancel`,
    // `{cancellationMessage}`).
    let object_id = rest_id(client, &s("id")).await?;
    let (base, token) = crate::api::tabs::middle_tier(client).await?;
    let body = if note.trim().is_empty() { serde_json::json!({}) } else { serde_json::json!({ "cancellationMessage": note.trim() }) };
    let r = client
        .http()
        .put(format!("{base}/v2.0/me/calendars/events/{object_id}/cancel"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?;
    let status = r.status();
    if !status.is_success() {
        bail!("{status}: {}", r.text().await.unwrap_or_default().chars().take(300).collect::<String>());
    }
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
    fn answers_are_built_as_teams_calendar_sends_them() {
        let b = super::respond_body("AAk/x+y=", "Tentative", 3, true, "a < b", "Pacific Standard Time");
        assert_eq!(b["Body"]["EventId"]["Id"], "AAk/x+y=");
        assert_eq!(b["Body"]["Response"], "Tentative");
        assert_eq!(b["Body"]["Attendance"], 3);
        assert_eq!(b["Body"]["SendResponse"], true);
        assert_eq!(b["Body"]["Notes"]["Value"], "<div>a &lt; b</div>");
        assert!(super::respond_body("x", "Accept", 0, false, " ", "UTC")["Body"].get("Notes").is_none());
        assert_eq!(super::ews_id("AAkAL-Q_xyz"), "AAkAL/Q+xyz=");
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
