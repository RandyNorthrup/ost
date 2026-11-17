//! Teams' Events app (docs/spec/events.md): Discover, Manage and Create
//! event, from the virtual events service as Teams draws them itself.
//!
//! Measured in Teams on the web as ost-test1 on 2026-11-16 (requests and
//! layout; Teams' modules services-virtual-events and meet-app read):
//! - Discover asks `GET {virtualevents}/eventOverviews` three times
//!   (`x-api-version: 2.0`): happening now (`startTo` now + 5 min,
//!   `endFrom` now, 9, by start), upcoming (`startFrom` now + 5 min, 21, by
//!   start) and past (`endTo` now, 9, by end, newest first), each
//!   `returnRequesterProperties=true&eventStatus=Published&
//!   includeRequesterStatus=AllInOrg`; `{virtualevents}` is
//!   `https://teams.microsoft.com/api/virtualevents/prod/beta`.
//! - Manage, Create and the rest go to the regional service (Teams'
//!   `virtualEventsService` endpoint, `…/api/teamsevents/us`): the counts
//!   (`eventOverviews?manageFilterType=Published|Draft&pageSize=1&
//!   includeTotalCount=true`) and the lists (`manageFilterType=Draft|
//!   Published|Past&pageSize=4&includeTotalCount=true&eventTypes=Townhall,
//!   Webinar`); `users/{oid}/eventFeatureDetails` (capacity options).
//! - Save and continue makes a draft: `POST {regional}/events` (201, the
//!   event); a draft's Cancel deletes it: `DELETE {regional}/events/{id}`
//!   (204). Neither notifies anyone (a draft has no attendees).
//! - All with Teams' own token for resource
//!   7fc21101-d09b-4343-8eb3-21187e0431a4, `x-ms-correlation-id`.
//!
//! Tokens are minted from OST's sign-in, kept in memory by the caller
//! only, and never logged.

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// Teams' virtual events service resource (ECS `virtualEventsServiceResource`).
pub const RESOURCE: &str = "7fc21101-d09b-4343-8eb3-21187e0431a4";
/// Teams' default service address (ECS `virtualEventsServiceEndpoint`).
pub const DEFAULT_ENDPOINT: &str = "https://teams.microsoft.com/api/virtualevents/prod/beta";
/// The regional service Teams' web client used for ost-test1's tenant.
pub const DEFAULT_REGIONAL: &str = "https://teams.microsoft.com/api/teamsevents/us";

/// The regional service (Teams' region discovery `virtualEventsService`),
/// else the US one Teams used for this tenant.
pub fn regional_endpoint(client: &TeamsClient) -> String {
    client
        .region_endpoint("virtualEventsService")
        .map(|u| u.trim_end_matches('/').trim_end_matches("/beta").to_string())
        .unwrap_or_else(|| DEFAULT_REGIONAL.to_string())
}

/// Which Discover list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiscoverList {
    /// "Happening now" (Teams' category UP_NEXT).
    Now,
    /// "Upcoming".
    Upcoming,
    /// "Past".
    Past,
}

/// Discover's filters (the Filters pane): My events and a date range.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DiscoverFilter {
    /// Events you're invited to or registered for (Teams'
    /// `includeRequesterStatus` REGISTERED, INVITED).
    pub my_events: bool,
    /// The range's start and end (RFC 3339, UTC), when one is chosen.
    pub from: String,
    pub to: String,
}

fn iso(t: chrono::DateTime<chrono::Utc>) -> String {
    t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

/// A Discover request's address (relative to the service), as Teams asks.
pub fn discover_query(list: DiscoverList, now: chrono::DateTime<chrono::Utc>, filter: &DiscoverFilter) -> String {
    let soon = now + chrono::Duration::minutes(5);
    let status = if filter.my_events { "&includeRequesterStatus=Registered&includeRequesterStatus=Invited" } else { "&includeRequesterStatus=AllInOrg" };
    let tail = format!("&returnRequesterProperties=true&eventStatus=Published{status}");
    if !filter.from.is_empty() && !filter.to.is_empty() {
        // A chosen range: one list of the events starting in it.
        return format!(
            "/eventOverviews?pageSize=21&sortBy=StartTime&sortOrder=Ascending&startFrom={}&startTo={}{tail}",
            filter.from, filter.to
        );
    }
    match list {
        DiscoverList::Now => format!(
            "/eventOverviews?pageSize=9&sortBy=StartTime&sortOrder=Ascending&startTo={}&endFrom={}{tail}",
            iso(soon),
            iso(now)
        ),
        DiscoverList::Upcoming => format!("/eventOverviews?pageSize=21&sortBy=StartTime&sortOrder=Ascending&startFrom={}{tail}", iso(soon)),
        DiscoverList::Past => format!("/eventOverviews?pageSize=9&sortBy=EndTime&sortOrder=Descending&endTo={}{tail}", iso(now)),
    }
}

/// Manage's requests: the counts and the three lists, as Teams asks.
pub fn manage_queries() -> Vec<(&'static str, String)> {
    vec![
        ("publishedCount", "/eventOverviews?manageFilterType=Published&pageSize=1&includeTotalCount=true".into()),
        ("draftCount", "/eventOverviews?manageFilterType=Draft&pageSize=1&includeTotalCount=true".into()),
        ("drafts", "/eventOverviews?manageFilterType=Draft&pageSize=4&includeTotalCount=true&eventTypes=Townhall,Webinar".into()),
        ("published", "/eventOverviews?manageFilterType=Published&pageSize=4&includeTotalCount=true&eventTypes=Townhall,Webinar".into()),
        ("past", "/eventOverviews?manageFilterType=Past&pageSize=4&includeTotalCount=true&eventTypes=Townhall,Webinar".into()),
    ]
}

/// An event as Events' cards show it.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct EventCard {
    pub id: String,
    pub title: String,
    /// RFC 3339.
    pub start: String,
    pub end: String,
    /// Webinar, Townhall, …
    pub event_type: String,
    /// Draft, Published, Canceled, …
    pub state: String,
    /// The promo picture (Teams' media store object) when there is one.
    pub promo_image: String,
    pub primary_color: String,
    /// Your role ("Organizer", "Presenter", …), first one.
    pub role: String,
    /// "Online" (Teams Online Meeting) or the room's name.
    pub location: String,
    /// The meeting's join link (first session).
    pub join_url: String,
    /// The event's page (`siteUrl`, events.teams.microsoft.com), what
    /// "Copy event page link" copies.
    pub site_url: String,
}

/// The cards in an eventOverviews reply (`results[].eventDetails`).
pub fn cards_from(reply: &Value, ams_v2: &str) -> Vec<EventCard> {
    reply
        .get("results")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|r| {
            let e = r.get("eventDetails")?;
            let s = |p: &str| e.pointer(p).and_then(Value::as_str).unwrap_or_default().to_string();
            let promo = s("/theme/promoImage");
            let role = r
                .get("roles")
                .and_then(Value::as_array)
                .and_then(|a| a.first())
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            let session = r.pointer("/eventSessions/0");
            Some(EventCard {
                id: s("/id"),
                title: s("/title"),
                start: s("/eventTime/startTime"),
                end: s("/eventTime/endTime"),
                event_type: s("/type"),
                state: s("/state"),
                promo_image: promo_url(ams_v2, &promo),
                primary_color: s("/theme/primaryColor"),
                role,
                location: "Online".into(),
                join_url: session
                    .and_then(|x| x.pointer("/meetingContext/joinLink"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                site_url: s("/siteUrl"),
            })
        })
        .collect()
}

/// A promo picture's address in Teams' media store (as Teams fetches it:
/// `{amsV2}/v1/objects/{id}/views/imgpsh_fullsize?v=1`).
pub fn promo_url(ams_v2: &str, id: &str) -> String {
    let ok = !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    if !ok || ams_v2.is_empty() {
        return String::new();
    }
    format!("{}/v1/objects/{id}/views/imgpsh_fullsize?v=1", ams_v2.trim_end_matches('/'))
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await
}

async fn send(method: reqwest::Method, url: &str, body: Option<&Value>, api_v2: bool) -> Result<reqwest::Response> {
    let t = token().await?;
    let mut req = reqwest::Client::new()
        .request(method, url)
        .bearer_auth(t)
        .header("content-type", "application/json")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string());
    if api_v2 {
        req = req.header("x-api-version", "2.0");
    }
    if let Some(b) = body {
        req = req.json(b);
    }
    let resp = req.send().await.context("The events service")?;
    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().await.unwrap_or_default();
        let msg = serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|v| v.get("ErrorMessage").or_else(|| v.get("message")).and_then(Value::as_str).map(str::to_string))
            .unwrap_or_default();
        anyhow::bail!("The events service answered {status}{}", if msg.is_empty() { String::new() } else { format!(": {msg}") });
    }
    Ok(resp)
}

async fn get_json(url: &str, api_v2: bool) -> Result<Value> {
    let r = send(reqwest::Method::GET, url, None, api_v2).await?;
    if r.status() == reqwest::StatusCode::NO_CONTENT {
        return Ok(json!({}));
    }
    r.json().await.context("The events service's reply")
}

/// Discover's three lists (or the filtered one), as Teams asks for them.
pub async fn discover(client: &TeamsClient, filter: &DiscoverFilter) -> Result<Value> {
    let ams = client.ams_v2_url().unwrap_or_default();
    let now = chrono::Utc::now();
    let url = |l| format!("{DEFAULT_ENDPOINT}{}", discover_query(l, now, filter));
    if !filter.from.is_empty() && !filter.to.is_empty() {
        let r = get_json(&url(DiscoverList::Upcoming), true).await?;
        return Ok(json!({ "filtered": cards_from(&r, &ams) }));
    }
    let (un, uu, up) = (url(DiscoverList::Now), url(DiscoverList::Upcoming), url(DiscoverList::Past));
    let (a, b, c) = tokio::join!(get_json(&un, true), get_json(&uu, true), get_json(&up, true));
    let (a, b, c) = (a?, b?, c?);
    let out = json!({
        "now": cards_from(&a, &ams),
        "upcoming": cards_from(&b, &ams),
        "past": cards_from(&c, &ams),
    });
    if filter.my_events {
        let mut o = out;
        let all: Vec<Value> = ["now", "upcoming", "past"].iter().flat_map(|k| o[*k].as_array().cloned().unwrap_or_default()).collect();
        o["filtered"] = Value::Array(all);
        return Ok(o);
    }
    Ok(out)
}

/// Manage's sections: Drafts, Published and Past (Teams' four cards each,
/// with the totals).
pub async fn manage(client: &TeamsClient) -> Result<Value> {
    let ams = client.ams_v2_url().unwrap_or_default();
    let base = regional_endpoint(client);
    let qs = manage_queries();
    let futs = qs.iter().map(|(_, q)| get_json_owned(format!("{base}{q}")));
    let replies = futures::future::join_all(futs).await;
    let mut out = json!({});
    for ((name, _), r) in qs.iter().zip(replies) {
        let r = r?;
        out[*name] = json!({
            "total": r.get("totalCount").and_then(Value::as_u64).unwrap_or(0),
            "items": cards_from(&r, &ams),
        });
    }
    Ok(out)
}

async fn get_json_owned(url: String) -> Result<Value> {
    get_json(&url, false).await
}

/// Your event capacity options (Teams' eventFeatureDetails).
pub async fn feature_details(client: &TeamsClient) -> Result<Value> {
    let oid = client.object_id().context("Not signed in")?;
    get_json(&format!("{}/users/{oid}/eventFeatureDetails", regional_endpoint(client)), false).await
}

/// What the New event form gives.
#[derive(Debug, Clone, Default, PartialEq, serde::Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct NewEvent {
    /// "Webinar" (Create from scratch and the webinar templates) or
    /// "Townhall".
    pub event_type: String,
    pub title: String,
    /// The description's HTML.
    pub description: String,
    /// RFC 3339 (UTC).
    pub start: String,
    pub end: String,
    /// "Public", "Organization" or "Private" (specific people and groups).
    pub access: String,
    pub registration: bool,
    pub green_room: bool,
    pub allow_mic: bool,
    pub allow_camera: bool,
    pub reactions: bool,
    pub chat: bool,
    pub qna: bool,
    /// A chosen capacity (0: Teams' default, sent as null).
    pub capacity: u64,
    /// Optimize for large audience (Teams' base event experience).
    pub base_experience: bool,
    /// A town hall's "Optimize for large audience" (on by default): the
    /// event streams to view-only attendees (3,000 by default).
    pub large_audience: bool,
}

/// The time zone details Teams sends with an event (its time zone keys are
/// the Windows names shortened: "Pacific Standard Time" → "PacificSt").
pub fn time_zone_details(iana: &str, utc_offset_minutes: i64) -> Value {
    let windows = super::search::windows_zone(iana);
    let key = windows.replace(" Standard Time", "St").replace(' ', "");
    json!({
        "timeZone": key,
        "utcOffset": utc_offset_minutes,
        "ianaTimeZone": iana,
        "windowsTimeZone": key,
        "localizedTimeZoneString": key,
    })
}

/// The new event as Teams sends it (`POST events`): a draft with you as the
/// owner, nobody invited, Teams' default meeting options and theme.
pub fn create_body(e: &NewEvent, owner: &Value, tz: Value, promo: &str) -> Value {
    let (access_type, invite_only) = match e.access.as_str() {
        "Public" => ("Public", false),
        "Private" => ("Private", true),
        _ => ("Private", false),
    };
    let town_hall = e.event_type == "Townhall";
    let meeting_options = new_meeting_options(e, town_hall);
    let to_ms = |s: &str| {
        chrono::DateTime::parse_from_rfc3339(s)
            .map(|d| iso(d.with_timezone(&chrono::Utc)))
            .unwrap_or_else(|_| s.to_string())
    };
    json!({
        "type": if e.event_type.is_empty() { "Webinar" } else { e.event_type.as_str() },
        "sessionType": "Single",
        "description": e.description,
        "language": "en-us",
        "title": e.title,
        "eventTime": { "startTime": to_ms(&e.start), "endTime": to_ms(&e.end), "timeZoneDetails": tz },
        "owner": owner,
        "team": [],
        "access": { "accessType": access_type, "inviteOnly": invite_only, "isRegistrationEnabled": e.registration },
        "presenters": [],
        "attendees": [],
        "communicationProperties": {
            "isReminderEmailEnabled": true, "isGroupMailboxEnabled": true, "disableAttendeeEmails": false,
            "isSocialShareEnabled": null, "isSeparateAttendeeInvitesEnabled": false, "enableOneEventsArtifacts": true,
            "enablePreviewOneEventsArtifacts": false, "enableNotifyForNonRegAttendeesEmail": false,
            "enableOneEventsEmailTemplates": false, "enableEventAccessLobbyValidation": true
        },
        "speakerJoinLinkProperties": { "isSpeakerJoinLinkEnabled": true },
        "productionModeProperties": { "enableManagedModeContentSharePreview": true, "enableProductionStudioMeetingOption": true },
        // A town hall's comment stream: its own backroom chat, apps on the
        // streaming thread (captured 2026-11-17).
        "commentStreamProperties": {
            "isCommentStreamEnabled": town_hall, "isPolicyAndLicenseCheckEnabled": town_hall, "isSeparateBackroomChatThreadEnabled": town_hall,
            "useBackroomChatAsMainThread": false, "useStreamingThreadForApps": town_hall
        },
        "eventCapacityProperties": if e.capacity > 0 {
            json!({ "maxEventCapacity": e.capacity, "isBaseEventExperience": e.base_experience })
        } else {
            Value::Null
        },
        "substrateGroupSessionKey": uuid::Uuid::new_v4().to_string(),
        "meetingOptions": meeting_options,
        "clientTags": { "version": "2.0" },
        "theme": { "primaryColor": "#5B5FC7", "promoImage": promo }
    })
}

/// A new event's meeting options as the form sends them. A town hall
/// streaming to a large audience (Teams' default) has view-only attendees:
/// mic and camera off (`"DisableAudio,DisableVideo"`), no reactions or
/// lobby setting, the chat left to the service (null); a town hall's
/// green room is on unless turned off. "Manage what attendees see" isn't
/// sent: Teams' form sent `attendeeViewModes` null with it On (captured
/// 2026-11-17).
fn new_meeting_options(e: &NewEvent, town_hall: bool) -> Value {
    let streaming = town_hall && e.large_audience;
    let restrictions = match (e.allow_mic, e.allow_camera) {
        _ if streaming => "DisableAudio,DisableVideo",
        (true, true) => "UnRestricted",
        (false, true) => "DisableAudio",
        (true, false) => "DisableVideo",
        (false, false) => "DisableAv",
    };
    let mut o = json!({
        "allowTeamsMeetingReactions": e.reactions,
        "allowMeetingChat": if e.chat { "Enabled" } else { "Disabled" },
        "yammerQNAEnabled": e.qna,
        "allowPstnUsersToBypassLobby": false,
        "autoAdmittedUsers": "EveryoneInCompany",
        "usersCanAdmitFromLobby": "OrganizersAndPresentersOnly",
        "attendanceReportEnabled": true,
        "entryExitAnnouncementsEnabled": false,
        "attendeeRestrictions": restrictions,
        "autoRecordAndTranscribeMode": "AutoRecordingAndTranscription",
        "meetingSpokenLanguage": "en-us",
        "whoCanManageQna": "OrganizersAndCoorganizers",
        "producerOption": "OrganizersAndPresentersOnly",
        "stagingRoomEnabled": e.green_room,
        "recorderOption": "OrganizersAndPresentersOnly",
        "copilotMode": "EnabledWithTranscript",
        "attendeeViewModes": null,
        "allowedUsersForMeetingDetails": "UsersAllowedToByPassTheLobby",
        "whoCanAccessTranscriptAndRecording": "Default",
        "enableMultiLingualMeeting": false,
        "isGroupCopilotEnabled": false
    });
    if streaming {
        let m = o.as_object_mut().expect("an object");
        m.remove("allowTeamsMeetingReactions");
        m.remove("autoAdmittedUsers");
        m.insert("allowMeetingChat".into(), Value::Null);
    }
    o
}

/// Teams' default promo pictures (ECS `virtualEvents.
/// oneEventsDefaultPromoImages`, 2026-11-16); a new event gets one.
pub const DEFAULT_PROMO_IMAGES: [&str; 12] = [
    "0-ea-d8-cb957d5c7670b8102f391ac3b8d2dcab", "0-ea-d9-7aa2763990eb6501cee5a1f10d1a64de", "0-ea-d1-844c96573cb54bea119d491e901da436",
    "0-ea-d4-9d0a5e76a96eeaf05a069df75c809e19", "0-ea-d12-f5f8bfa8939e0e526fb957efa7eba7ce", "0-ea-d10-c479e6b1249707acb0dc80b12f1828a4",
    "0-ea-d10-7ce1ec7262e6ddd449b707d3a7bd47fb", "0-ea-d12-f8379ddb570a56396c8b483fc469b987", "0-ea-d10-95ab29d1e8818087793edbc92fa7a7da",
    "0-ea-d12-d5cefd297ac4bfc461bcb599f90e4afb", "0-ea-d11-339f679162f8a786f523cabee1c66fc5", "0-ea-d8-03b7cf6be16d773074d3cf105e7aea72",
];

/// A default promo picture for a new event (ECS's list, else Teams').
pub fn default_promo() -> String {
    let list: Vec<String> = super::ecs::setting("virtualEvents", "oneEventsDefaultPromoImages")
        .and_then(|v| v.as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()))
        .filter(|l: &Vec<String>| !l.is_empty())
        .unwrap_or_else(|| DEFAULT_PROMO_IMAGES.iter().map(|s| s.to_string()).collect());
    let i = (uuid::Uuid::new_v4().as_u128() % list.len() as u128) as usize;
    list[i].clone()
}

/// You, as Teams names the owner of a new event.
pub fn owner_of(client: &TeamsClient) -> Value {
    let oid = client.object_id().unwrap_or_default();
    json!({
        "email": client.user_principal_name().unwrap_or_default(),
        "displayName": client.display_name().unwrap_or_default(),
        "identity": { "mri": format!("8:orgid:{oid}"), "objectId": oid, "tenantId": client.tenant_id().unwrap_or_default(), "upn": null },
        "userBio": { "description": "", "company": "", "jobTitle": "", "socialMediaLinks": { "linkedIn": "", "twitter": "" } },
        "userPurpose": "unknown"
    })
}

/// Save a new event as a draft (Save and continue); its id.
pub async fn create_draft(client: &TeamsClient, e: &NewEvent) -> Result<Value> {
    anyhow::ensure!(!e.title.trim().is_empty(), "The event needs a name");
    let iana = super::find::local_timezone();
    let offset = chrono::Local::now().offset().local_minus_utc() as i64 / 60;
    let body = create_body(e, &owner_of(client), time_zone_details(&iana, offset), &default_promo());
    let r = send(reqwest::Method::POST, &format!("{}/events", regional_endpoint(client)), Some(&body), false).await?;
    let v: Value = r.json().await.context("The new event")?;
    let ams = client.ams_v2_url().unwrap_or_default();
    Ok(json!({
        "id": v.get("id").and_then(Value::as_str).unwrap_or_default(),
        "state": v.get("state").and_then(Value::as_str).unwrap_or_default(),
        "card": cards_from(&json!({ "results": [{ "eventDetails": v, "roles": ["Organizer"] }] }), &ams).pop(),
    }))
}

fn event_path(id: &str) -> Result<String> {
    anyhow::ensure!(
        !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '@'),
        "Not an event id"
    );
    Ok(id.to_string())
}

/// An event's overview (Teams' `events/{id}/overview`): the event, its
/// sessions, registration and your roles.
pub async fn overview(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let v = get_json(&format!("{}/events/{}/overview", regional_endpoint(client), urlencoding(&id)), false).await?;
    let ams = client.ams_v2_url().unwrap_or_default();
    let card = cards_from(&json!({ "results": [{ "eventDetails": v.get("event").cloned().unwrap_or_default(),
                                                 "eventSessions": v.get("sessions").cloned().unwrap_or_default(),
                                                 "roles": v.get("roles").cloned().unwrap_or_default() }] }), &ams)
        .pop();
    Ok(json!({ "card": card, "description": v.pointer("/event/description").cloned().unwrap_or_default(),
               "access": v.pointer("/event/access/accessType").cloned().unwrap_or_default(),
               "inviteOnly": v.pointer("/event/access/inviteOnly").cloned().unwrap_or_default(),
               "registration": v.pointer("/event/access/isRegistrationEnabled").cloned().unwrap_or_default() }))
}

fn urlencoding(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// The People & emails tab's lists: who is invited and how many have
/// registered, to show before publishing (the event's `overview` and
/// Teams' `…/attendees?status=…&count=true`).
pub async fn people(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let base = format!("{}/events/{}", regional_endpoint(client), urlencoding(&id));
    let statuses = "Waitlisted,ProcessingWaitlisting,PendingApproval,ProcessingApproval,ProcessingRejection,Rejected,ProcessingRegistration,Registered,ProcessingCancellation,Canceled,ProcessingPendingApproval";
    let overview_url = format!("{base}/overview");
    let attendees_url = format!("{base}/attendees?status={statuses}&pageSize=20&skip=0&count=true");
    let (event, attendees) = tokio::join!(
        get_json(&overview_url, false),
        get_json(&attendees_url, false)
    );
    let event = event?.get("event").cloned().unwrap_or_default();
    let names = |k: &str| -> Vec<Value> {
        event.get(k).and_then(Value::as_array).into_iter().flatten()
            .map(|p| json!(p.get("displayName").or_else(|| p.get("email")).cloned().unwrap_or_default()))
            .collect()
    };
    Ok(json!({
        "organizers": [event.pointer("/owner/displayName").cloned().unwrap_or_default()],
        "coOrganizers": names("team"),
        "presenters": names("presenters"),
        "invited": names("attendees"),
        "registered": attendees.ok().and_then(|a| a.get("totalCount").or_else(|| a.get("count")).cloned()).unwrap_or(json!(0)),
    }))
}

/// Publish an event (the draft card's Publish event ▸ "Ready to publish
/// your event?" ▸ Publish event): `PATCH events/{id}` with
/// `{"state": "Published", "meetingOptions": null}` (captured 2026-11-17).
/// Invites go to its invited attendees, presenters and co-organizers.
pub async fn publish(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let body = json!({ "state": "Published", "meetingOptions": null });
    let r = send(reqwest::Method::PATCH, &format!("{}/events/{}", regional_endpoint(client), urlencoding(&id)), Some(&body), false).await?;
    let v: Value = r.json().await.context("The published event")?;
    Ok(json!({ "id": v.get("id").cloned().unwrap_or_default(), "state": v.get("state").cloned().unwrap_or_default() }))
}

/// Cancel an event (the event page's ··· ▸ Cancel): Teams'
/// cancelVirtualEvent, `DELETE events/{id}`. A draft is gone; a published
/// event's attendees are emailed (Teams' dialog says so).
pub async fn cancel(client: &TeamsClient, id: &str) -> Result<()> {
    let id = event_path(id)?;
    send(reqwest::Method::DELETE, &format!("{}/events/{id}", regional_endpoint(client)), None, false).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(s: &str) -> chrono::DateTime<chrono::Utc> {
        chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc)
    }

    #[test]
    fn discover_asks_as_teams() {
        let now = at("2026-11-16T22:53:50.241Z");
        let f = DiscoverFilter::default();
        assert_eq!(discover_query(DiscoverList::Now, now, &f),
            "/eventOverviews?pageSize=9&sortBy=StartTime&sortOrder=Ascending&startTo=2026-11-16T22:58:50.241Z&endFrom=2026-11-16T22:53:50.241Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg");
        assert_eq!(discover_query(DiscoverList::Upcoming, now, &f),
            "/eventOverviews?pageSize=21&sortBy=StartTime&sortOrder=Ascending&startFrom=2026-11-16T22:58:50.241Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg");
        assert_eq!(discover_query(DiscoverList::Past, now, &f),
            "/eventOverviews?pageSize=9&sortBy=EndTime&sortOrder=Descending&endTo=2026-11-16T22:53:50.241Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg");
        let mine = DiscoverFilter { my_events: true, ..Default::default() };
        assert!(discover_query(DiscoverList::Past, now, &mine).ends_with("&includeRequesterStatus=Registered&includeRequesterStatus=Invited"));
    }

    #[test]
    fn manage_asks_as_teams() {
        let q = manage_queries();
        assert_eq!(q[2].1, "/eventOverviews?manageFilterType=Draft&pageSize=4&includeTotalCount=true&eventTypes=Townhall,Webinar");
        assert_eq!(q.len(), 5);
    }

    #[test]
    fn cards_from_a_manage_reply() {
        // The draft's overview as the service returned it (trimmed).
        let r = json!({"totalCount": 1, "results": [{"eventDetails": {"id": "963c@27", "title": "OST TEST 209 draft event",
            "eventTime": {"startTime": "2026-11-16T23:30:00+00:00", "endTime": "2026-11-17T00:00:00+00:00"}, "type": "Webinar",
            "state": "Draft", "theme": {"promoImage": "0-ea-d1-844c96573cb54bea119d491e901da436", "primaryColor": "#5B5FC7"}},
            "eventSessions": [{"meetingContext": {"joinLink": "https://teams.microsoft.com/l/meetup-join/x"}}], "roles": ["Organizer"]}]});
        let c = cards_from(&r, "https://us-prod.asyncgw.teams.microsoft.com");
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].title, "OST TEST 209 draft event");
        assert_eq!(c[0].state, "Draft");
        assert_eq!(c[0].role, "Organizer");
        assert_eq!(c[0].promo_image, "https://us-prod.asyncgw.teams.microsoft.com/v1/objects/0-ea-d1-844c96573cb54bea119d491e901da436/views/imgpsh_fullsize?v=1");
        assert_eq!(c[0].join_url, "https://teams.microsoft.com/l/meetup-join/x");
        assert_eq!(promo_url("https://x", "../evil"), "");
    }

    #[test]
    fn a_new_draft_is_sent_as_teams_sends_it() {
        let e = NewEvent { title: "OST TEST".into(), start: "2026-11-16T23:30:00Z".into(), end: "2026-11-17T00:00:00Z".into(),
                           access: "Organization".into(), allow_mic: true, allow_camera: true, reactions: true, chat: true, qna: true,
                           ..Default::default() };
        let b = create_body(&e, &json!({"displayName": "OST Test 1"}), time_zone_details("America/Los_Angeles", -480), DEFAULT_PROMO_IMAGES[2]);
        assert_eq!(b["theme"], json!({"primaryColor": "#5B5FC7", "promoImage": "0-ea-d1-844c96573cb54bea119d491e901da436"}));
        assert_eq!(b["type"], "Webinar");
        assert_eq!(b["eventTime"]["startTime"], "2026-11-16T23:30:00.000Z");
        assert_eq!(b["eventTime"]["timeZoneDetails"]["timeZone"], "PacificSt");
        assert_eq!(b["access"], json!({"accessType": "Private", "inviteOnly": false, "isRegistrationEnabled": false}));
        assert_eq!(b["attendees"], json!([]));
        assert_eq!(b["presenters"], json!([]));
        assert_eq!(b["meetingOptions"]["attendeeRestrictions"], "UnRestricted");
        assert_eq!(b["meetingOptions"]["allowMeetingChat"], "Enabled");
        let p = create_body(&NewEvent { access: "Public".into(), ..Default::default() }, &json!({}), json!({}), "");
        assert_eq!(p["access"]["accessType"], "Public");
        assert_eq!(p["meetingOptions"]["attendeeRestrictions"], "DisableAv");
        assert_eq!(p["eventCapacityProperties"], Value::Null);
        let big = create_body(&NewEvent { capacity: 10000, base_experience: true, ..Default::default() }, &json!({}), json!({}), "");
        assert_eq!(big["eventCapacityProperties"], json!({"maxEventCapacity": 10000, "isBaseEventExperience": true}));
    }

    #[test]
    fn a_town_hall_is_sent_as_teams_sends_it() {
        // Teams' town hall template, defaults kept (captured 2026-11-17).
        let e = NewEvent { event_type: "Townhall".into(), title: "OST TEST 184 town hall".into(), access: "Public".into(),
                           green_room: true, qna: true, capacity: 3000, large_audience: true, ..Default::default() };
        let b = create_body(&e, &json!({}), json!({}), "");
        assert_eq!(b["type"], "Townhall");
        assert_eq!(b["access"], json!({"accessType": "Public", "inviteOnly": false, "isRegistrationEnabled": false}));
        assert_eq!(b["eventCapacityProperties"], json!({"maxEventCapacity": 3000, "isBaseEventExperience": false}));
        assert_eq!(b["commentStreamProperties"], json!({"isCommentStreamEnabled": true, "isPolicyAndLicenseCheckEnabled": true,
            "isSeparateBackroomChatThreadEnabled": true, "useBackroomChatAsMainThread": false, "useStreamingThreadForApps": true}));
        let o = &b["meetingOptions"];
        assert_eq!(o["attendeeRestrictions"], "DisableAudio,DisableVideo");
        assert_eq!(o["allowMeetingChat"], Value::Null);
        assert!(o.get("allowTeamsMeetingReactions").is_none() && o.get("autoAdmittedUsers").is_none());
        assert_eq!(o["stagingRoomEnabled"], true);
        assert_eq!(o["yammerQNAEnabled"], true);
        assert_eq!(o["attendeeViewModes"], Value::Null);
        // A webinar keeps its comment stream off.
        let w = create_body(&NewEvent { event_type: "Webinar".into(), ..Default::default() }, &json!({}), json!({}), "");
        assert_eq!(w["commentStreamProperties"]["isCommentStreamEnabled"], false);
        assert!(w["meetingOptions"].get("allowTeamsMeetingReactions").is_some());
    }

    #[test]
    fn event_ids_are_checked() {
        assert!(event_path("963c6306-128c@2716d134").is_ok());
        assert!(event_path("../x").is_err());
        assert!(event_path("").is_err());
    }
}
