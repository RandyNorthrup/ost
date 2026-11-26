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
/// The regional service Teams' web client used for ost-test1's tenant.
pub const DEFAULT_REGIONAL: &str = "https://teams.microsoft.com/api/teamsevents/us";

/// The regional service (Teams' region discovery `virtualEventsService`),
/// else the US one Teams used for this tenant.
pub fn regional_endpoint(client: &TeamsClient) -> String {
    client
        .region_endpoint("virtualEventsService")
        .map(|u| {
            u.trim_end_matches('/')
                .trim_end_matches("/beta")
                .to_string()
        })
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

fn iso(t: jiff::Timestamp) -> String {
    crate::clock::iso_ms(t)
}

/// A Discover request's address (relative to the service), as Teams asks.
pub fn discover_query(list: DiscoverList, now: jiff::Timestamp, filter: &DiscoverFilter) -> String {
    let soon = now + jiff::SignedDuration::from_mins(5);
    let status = if filter.my_events {
        "&includeRequesterStatus=Registered&includeRequesterStatus=Invited"
    } else {
        "&includeRequesterStatus=AllInOrg"
    };
    let tail = format!("&returnRequesterProperties=true&eventStatus=Published{status}");
    if !filter.from.is_empty() && !filter.to.is_empty() {
        // A chosen range (Teams: the regional service, 100, by start).
        return format!(
            "/eventOverviews?pageSize=100&sortBy=StartTime&startFrom={}&startTo={}{tail}",
            filter.from, filter.to
        );
    }
    match list {
        DiscoverList::Now => format!(
            "/eventOverviews?pageSize=9&sortBy=StartTime&sortOrder=Ascending&startTo={}&endFrom={}{tail}",
            iso(soon),
            iso(now)
        ),
        DiscoverList::Upcoming => format!(
            "/eventOverviews?pageSize=21&sortBy=StartTime&sortOrder=Ascending&startFrom={}{tail}",
            iso(soon)
        ),
        DiscoverList::Past => format!(
            "/eventOverviews?pageSize=9&sortBy=EndTime&sortOrder=Descending&endTo={}{tail}",
            iso(now)
        ),
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
    /// The rooms (session speakers of type Room), "OST Test Room".
    pub rooms: Vec<String>,
    /// The attendee card's "By {name}": the first presenter.
    pub by: String,
    /// Who the attendee card names after "By" (meet-app's dr, read
    /// 2026-11-19): the session's presenters in Teams' order (those without
    /// lobby bypass, then the rest) leaving out hidden ones, rooms and
    /// nameless ones, an external presenter whose name is an email shown as
    /// "Guest Speaker"; with none, the event's owner. The card shows two
    /// and "+N".
    pub by_names: Vec<String>,
    /// The event's chat and its event group's chat (Teams' backroom).
    pub thread_id: String,
    pub backroom_thread_id: String,
    /// The meeting's scheduler link (its join details).
    pub update_link: String,
    pub session_id: String,
    /// Shown in the Events app (Teams' `isDiscoverable`).
    pub discoverable: bool,
    pub access: String,
    pub invite_only: bool,
    pub registration: bool,
    /// Your registration for its first session
    /// (`requesterPropertiesBySession.{session}.registrationStatus`):
    /// "Registered", "Canceled", … or "" (Teams' card shows Register or
    /// Registered by it).
    pub registration_status: String,
    /// The registration form's terms of use link (`registrationInfo.
    /// termsOfUseUrl`) and its questions in their order (Teams'
    /// RegistrationQuestion: id, category Standard / Predefined /
    /// UserCreated, type Text / Note / SingleChoice / MultiChoice / Boolean
    /// / PromoEmailConsent, displayText, isRequired, order, choices,
    /// internalName, isCheckedByDefault).
    pub terms_url: String,
    pub questions: Vec<Value>,
}

/// The attendee card's presenters (see `EventCard::by_names`).
pub fn card_presenters(speakers: &[Value], owner: Option<&Value>) -> Vec<String> {
    let bypass = |p: &Value| {
        p.get("sessionsProps")
            .and_then(Value::as_array)
            .is_some_and(|a| {
                a.iter()
                    .any(|x| x.get("allowBypassLobby").and_then(Value::as_bool) == Some(true))
            })
    };
    let s = |p: &Value, k: &str| {
        p.pointer(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let external = |p: &Value| {
        s(p, "/identity/tenantId").is_empty()
            || (p.get("isGroup").and_then(Value::as_bool) != Some(true)
                && s(p, "/identity/mri").is_empty())
    };
    let email = |n: &str| {
        let (a, b) = n.split_once('@').unwrap_or(("", ""));
        !a.is_empty()
            && !n.contains(char::is_whitespace)
            && b.split_once('.')
                .is_some_and(|(x, y)| !x.is_empty() && !y.is_empty() && !b.contains('@'))
    };
    let shown = |p: &&Value| {
        !s(p, "/displayName").is_empty()
            && p.get("isHidden").and_then(Value::as_bool) != Some(true)
            && !s(p, "/userPurpose").eq_ignore_ascii_case("room")
    };
    let names: Vec<String> = speakers
        .iter()
        .filter(|p| !bypass(p))
        .chain(speakers.iter().filter(|p| bypass(p)))
        .filter(shown)
        .map(|p| {
            let n = s(p, "/displayName");
            if external(p) && email(&n) {
                crate::i18n::tr("Guest Speaker")
            } else {
                n
            }
        })
        .collect();
    if !names.is_empty() {
        return names;
    }
    owner
        .and_then(|o| o.get("displayName"))
        .and_then(Value::as_str)
        .filter(|n| !n.is_empty())
        .map(|n| vec![n.to_string()])
        .unwrap_or_default()
}

/// A registration form's questions in Teams' order (by `order`).
pub fn registration_questions(info: Option<&Value>) -> Vec<Value> {
    let mut q: Vec<Value> = info
        .and_then(|i| i.get("questions"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|x| x.is_object())
        .collect();
    q.sort_by_key(|x| x.get("order").and_then(Value::as_i64).unwrap_or(0));
    q
}

/// The answers Teams sends for a registration form (meet-app's ei): for
/// each question that has a value, Boolean as a bool, MultiChoice as a
/// list, the others as text. `values` holds the form's values by question
/// id.
pub fn registration_answers(questions: &[Value], values: &Value) -> Vec<(String, Value)> {
    questions
        .iter()
        .filter_map(|q| {
            let id = q.get("id").and_then(Value::as_str)?;
            let v = values.get(id).filter(|v| !v.is_null())?;
            let answer = match q.get("type").and_then(Value::as_str).unwrap_or_default() {
                "Boolean" => Value::Bool(v.as_bool().unwrap_or(false)),
                "MultiChoice" => match v {
                    Value::Array(a) => Value::Array(a.clone()),
                    other => json!([other
                        .as_str()
                        .map(str::to_string)
                        .unwrap_or_else(|| other.to_string())]),
                },
                "Text" | "Note" | "SingleChoice" | "PromoEmailConsent" => Value::String(
                    v.as_str()
                        .map(str::to_string)
                        .unwrap_or_else(|| v.to_string()),
                ),
                _ => return None,
            };
            Some((id.to_string(), answer))
        })
        .collect()
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
            let s = |p: &str| {
                e.pointer(p)
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
            let promo = s("/theme/promoImage");
            let role = r
                .get("roles")
                .and_then(Value::as_array)
                .and_then(|a| a.first())
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            let session = r.pointer("/eventSessions/0");
            let speakers = session
                .and_then(|x| x.get("speakers"))
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            // A room: Teams keeps it as a speaker of purpose "room".
            let is_room = |p: &Value| {
                p.get("userType").and_then(Value::as_str) == Some("Room")
                    || p.get("userPurpose").and_then(Value::as_str) == Some("room")
            };
            let rooms: Vec<String> = speakers
                .iter()
                .filter(|p| is_room(p))
                .filter_map(|p| {
                    p.get("displayName")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
                .collect();
            let by = speakers
                .iter()
                .find(|p| !is_room(p))
                .and_then(|p| p.get("displayName"))
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            let by_names = card_presenters(&speakers, e.get("owner"));
            let ctx = |k: &str| {
                session
                    .and_then(|x| x.pointer(&format!("/meetingContext/{k}")))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
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
                location: if rooms.is_empty() {
                    crate::i18n::tr_id("Online", "virtualEvents:kc7y4avmb")
                } else {
                    crate::i18n::tr_id("In-person and online", "virtualEvents:k5k2j4pka")
                },
                join_url: session
                    .and_then(|x| x.pointer("/meetingContext/joinLink"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                site_url: s("/siteUrl"),
                rooms,
                by,
                by_names,
                thread_id: ctx("threadId"),
                backroom_thread_id: ctx("backroomThreadId"),
                update_link: ctx("meetingUpdateLink"),
                session_id: session
                    .and_then(|x| x.get("id"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                discoverable: e
                    .pointer("/access/isDiscoverable")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                access: s("/access/accessType"),
                invite_only: e
                    .pointer("/access/inviteOnly")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                registration: e
                    .pointer("/access/isRegistrationEnabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                registration_status: session
                    .and_then(|x| x.get("id"))
                    .and_then(Value::as_str)
                    .and_then(|sid| {
                        r.pointer(&format!(
                            "/requesterPropertiesBySession/{sid}/registrationStatus"
                        ))
                    })
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                terms_url: r
                    .pointer("/registrationInfo/termsOfUseUrl")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                questions: registration_questions(r.get("registrationInfo")),
            })
        })
        .collect()
}

/// A promo picture's address in Teams' media store (as Teams fetches it:
/// `{amsV2}/v1/objects/{id}/views/imgpsh_fullsize?v=1`).
pub fn promo_url(ams_v2: &str, id: &str) -> String {
    let ok = !id.is_empty()
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    if !ok || ams_v2.is_empty() {
        return String::new();
    }
    format!(
        "{}/v1/objects/{id}/views/imgpsh_fullsize?v=1",
        ams_v2.trim_end_matches('/')
    )
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await
}

async fn send(
    method: reqwest::Method,
    url: &str,
    body: Option<&Value>,
    api_v2: bool,
) -> Result<reqwest::Response> {
    crate::auth::token_hosts::ensure(url, crate::auth::token_hosts::Audience::Teams)?;
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
            .and_then(|v| {
                v.get("ErrorMessage")
                    .or_else(|| v.get("message"))
                    .and_then(Value::as_str)
                    .map(str::to_string)
            })
            .unwrap_or_default();
        anyhow::bail!(
            "The events service answered {status}{}",
            if msg.is_empty() {
                String::new()
            } else {
                format!(": {msg}")
            }
        );
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
    let now = jiff::Timestamp::now();
    // Teams asks its virtual events service at the regional address (ECS
    // virtualEvents.useRegionalVirtualEventsServiceEndpointResolver, on):
    // the same address as Manage and the filtered lists.
    let base = regional_endpoint(client);
    let url = |l| format!("{base}{}", discover_query(l, now, filter));
    if !filter.from.is_empty() && !filter.to.is_empty() {
        let r = get_json(
            &format!(
                "{}{}",
                regional_endpoint(client),
                discover_query(DiscoverList::Upcoming, now, filter)
            ),
            false,
        )
        .await?;
        return Ok(json!({ "filtered": cards_from(&r, &ams) }));
    }
    let (un, uu, up) = (
        url(DiscoverList::Now),
        url(DiscoverList::Upcoming),
        url(DiscoverList::Past),
    );
    let (a, b, c) = tokio::join!(
        get_json(&un, true),
        get_json(&uu, true),
        get_json(&up, true)
    );
    let (a, b, c) = (a?, b?, c?);
    let short = |v: &Value| v.to_string().chars().take(400).collect::<String>();
    tracing::debug!(base = %base, now = %short(&a), upcoming = %short(&b), past = %short(&c), "events: discover replies");
    let out = json!({
        "now": cards_from(&a, &ams),
        "upcoming": cards_from(&b, &ams),
        "past": cards_from(&c, &ams),
    });
    if filter.my_events {
        let mut o = out;
        let all: Vec<Value> = ["now", "upcoming", "past"]
            .iter()
            .flat_map(|k| o[*k].as_array().cloned().unwrap_or_default())
            .collect();
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
    get_json(
        &format!(
            "{}/users/{oid}/eventFeatureDetails",
            regional_endpoint(client)
        ),
        false,
    )
    .await
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
    /// Teams' time zone key ("PacificSt"); empty: this device's zone.
    pub time_zone: String,
    /// Co-organizers (Teams' `team`), presenters, invited attendees and
    /// rooms (sent as presenters of type Room), from the pickers.
    pub team: Vec<Person>,
    pub presenters: Vec<Person>,
    pub attendees: Vec<Person>,
    pub rooms: Vec<Person>,
    /// All options' changes on top of the form's (Teams' meetingOptions
    /// names, camelCase).
    pub meeting_options: Option<Value>,
    /// Keep this promo picture (Duplicate, a template); else Teams' default.
    pub promo_image: String,
    /// Edit details: the event's session (presenters' `sessionsProps`).
    pub session_id: String,
    /// Edit details: whether the event shows in the Events app (sent back
    /// as it is).
    pub discoverable: bool,
    /// The registration form's questions (Teams' RegistrationQuestionInput:
    /// category, type, displayText, isRequired, order, choices,
    /// internalName, isCheckedByDefault; new ones without an id, as Teams'
    /// registration converter drops its form ids "predefined-…" /
    /// "custom-…"), sent as the event's `registrationInfo`.
    pub questions: Vec<Value>,
}

/// Someone (or a room or group) from the form's pickers.
#[derive(Debug, Clone, Default, PartialEq, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Person {
    pub name: String,
    pub email: String,
    pub mri: String,
    pub object_id: String,
    pub tenant_id: String,
    pub upn: String,
    /// "ADUser", "Guest", "Room", "Group", ...
    pub user_type: String,
    pub group: bool,
    /// The picker's second line (an alias in capitals, a group's mail).
    pub detail: String,
    /// A room's Room options "Set up room for": "Presenting" (Teams'
    /// meeting role Everyone: a presenter) or "AttendeeViewing" (Attendees:
    /// the room is invited as an attendee).
    pub room_role: String,
}

/// The rooms that present (Teams sends them with the presenters).
fn presenting(rooms: &[Person]) -> impl Iterator<Item = &Person> {
    rooms.iter().filter(|r| r.room_role != "AttendeeViewing")
}

/// The rooms set up for attendee viewing (sent with the attendees).
fn viewing(rooms: &[Person]) -> impl Iterator<Item = &Person> {
    rooms.iter().filter(|r| r.room_role == "AttendeeViewing")
}

/// Someone in your organization as an event names them (Teams' owner
/// mapping; the pickers' people go through [`person_body`]).
pub fn person(email: &str, display_name: &str, object_id: &str, tenant_id: &str) -> Value {
    json!({
        "email": email,
        "displayName": display_name,
        "identity": { "mri": crate::identity::work_user_mri(object_id), "objectId": object_id, "tenantId": tenant_id, "upn": null },
        "userBio": { "description": "", "company": "", "jobTitle": "", "socialMediaLinks": { "linkedIn": "", "twitter": "" } },
        "userPurpose": "unknown"
    })
}

/// A person as Teams sends them in an event (`team`, `presenters`,
/// `attendees`; captured 2026-11-18): presenters and rooms carry the
/// session's lobby setting, rooms are `userType` Room / `userPurpose` room.
pub fn person_body(p: &Person, session: Option<&str>) -> Value {
    let room = p.user_type == "Room";
    let user_type = if p.user_type.is_empty() {
        if p.group { "Group" } else { "ADUser" }
    } else {
        p.user_type.as_str()
    };
    let upn = if p.upn.is_empty() {
        p.email.as_str()
    } else {
        p.upn.as_str()
    };
    let mut o = json!({
        "email": p.email,
        "displayName": p.name,
        "identity": { "mri": p.mri, "objectId": p.object_id, "tenantId": p.tenant_id, "upn": upn },
        "userBio": { "description": "", "company": "", "jobTitle": "", "socialMediaLinks": { "linkedIn": "", "twitter": "" } },
    });
    let m = o.as_object_mut().expect("an object");
    if let Some(sid) = session {
        let props = if sid.is_empty() {
            json!([{ "allowBypassLobby": false }])
        } else {
            json!([{ "sessionId": sid, "allowBypassLobby": false }])
        };
        m.insert("sessionsProps".into(), props);
    }
    if p.group {
        m.insert("isGroup".into(), json!(true));
    }
    m.insert("userType".into(), json!(user_type));
    m.insert(
        "userPurpose".into(),
        json!(if room { "room" } else { "unknown" }),
    );
    o
}

/// A person from an event reply (`team`, `presenters`, `attendees`,
/// session `speakers`).
pub fn person_from(v: &Value) -> Person {
    let s = |p: &str| {
        v.pointer(p)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let email = s("/email");
    // The service keeps a room as an ADUser of purpose "room".
    let user_type = if s("/userPurpose") == "room" {
        "Room".to_string()
    } else {
        s("/userType")
    };
    let group = v.get("isGroup").and_then(Value::as_bool).unwrap_or(false) || user_type == "Group";
    let object_id = s("/identity/objectId");
    Person {
        name: s("/displayName"),
        detail: if group {
            email.clone()
        } else {
            email.split('@').next().unwrap_or_default().to_uppercase()
        },
        email,
        mri: s("/identity/mri"),
        object_id: if object_id.is_empty() {
            s("/id")
        } else {
            object_id
        },
        tenant_id: s("/identity/tenantId"),
        upn: s("/identity/upn"),
        group,
        user_type,
        room_role: String::new(),
    }
}

/// The people of a list in an event reply.
pub fn people_from(v: Option<&Value>) -> Vec<Person> {
    v.and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(person_from)
        .collect()
}

/// The time zone details Teams sends with an event (its time zone keys are
/// the Windows names shortened: "Pacific Standard Time" → "PacificSt").
pub fn time_zone_details(iana: &str, utc_offset_minutes: i64) -> Value {
    let windows = super::search::windows_zone(iana);
    let key = windows.replace(" Standard Time", "St").replace(' ', "");
    let iana = super::events_tz::ZONES
        .iter()
        .find(|z| z.0 == key)
        .map(|z| z.1)
        .unwrap_or(iana);
    json!({
        "timeZone": key,
        "utcOffset": utc_offset_minutes,
        "ianaTimeZone": iana,
        "windowsTimeZone": key,
        "localizedTimeZoneString": key,
    })
}

/// A zone of Teams' picker by its key: the details Teams sends (the
/// label's base offset, "(UTC-08:00)" -> -480).
pub fn zone_details(key: &str) -> Option<Value> {
    let (k, iana, label) = super::events_tz::ZONES.iter().find(|z| z.0 == key)?;
    let off = label.get(4..10).and_then(|o| {
        let sign = if o.starts_with('-') { -1 } else { 1 };
        let h: i64 = o.get(1..3)?.parse().ok()?;
        let m: i64 = o.get(4..6)?.parse().ok()?;
        Some(sign * (h * 60 + m))
    });
    Some(
        json!({ "timeZone": k, "utcOffset": off.unwrap_or(0), "ianaTimeZone": iana, "windowsTimeZone": k, "localizedTimeZoneString": k }),
    )
}

/// This device's zone as Teams' key.
pub fn local_zone_key() -> String {
    let iana = super::find::local_timezone();
    super::search::windows_zone(&iana)
        .replace(" Standard Time", "St")
        .replace(' ', "")
}

/// Teams' zone list for the picker: [key, label] in Teams' order.
pub fn zones() -> Value {
    Value::Array(
        super::events_tz::ZONES
            .iter()
            .map(|z| json!([z.0, z.2]))
            .collect(),
    )
}

/// The new event as Teams sends it (`POST events`): a draft with you as the
/// owner, the people and rooms from the pickers, Teams' default meeting
/// options (with All options' changes) and theme.
pub fn create_body(e: &NewEvent, owner: &Value, tz: Value, promo: &str) -> Value {
    let (access_type, invite_only) = match e.access.as_str() {
        "Public" => ("Public", false),
        "Private" => ("Private", true),
        _ => ("Private", false),
    };
    let town_hall = e.event_type == "Townhall";
    let mut meeting_options = new_meeting_options(e, town_hall);
    merge_options(&mut meeting_options, e.meeting_options.as_ref());
    let to_ms = |s: &str| {
        crate::clock::parse_instant(s)
            .map(iso)
            .unwrap_or_else(|| s.to_string())
    };
    json!({
        "type": if e.event_type.is_empty() { "Webinar" } else { e.event_type.as_str() },
        "sessionType": "Single",
        "description": e.description,
        "language": "en-us",
        "title": e.title,
        "eventTime": { "startTime": to_ms(&e.start), "endTime": to_ms(&e.end), "timeZoneDetails": tz },
        "owner": owner,
        "team": e.team.iter().map(|p| person_body(p, None)).collect::<Vec<_>>(),
        "access": { "accessType": access_type, "inviteOnly": invite_only, "isRegistrationEnabled": e.registration },
        "presenters": e.presenters.iter().chain(presenting(&e.rooms)).map(|p| person_body(p, Some(""))).collect::<Vec<_>>(),
        "attendees": e.attendees.iter().chain(viewing(&e.rooms)).map(|p| person_body(p, None)).collect::<Vec<_>>(),
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
        "registrationInfo": registration_info(&e.questions),
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

/// A form's registration (Teams' UpdateRegistrationInput converter):
/// its properties and questions; null without questions.
pub fn registration_info(questions: &[Value]) -> Value {
    if questions.is_empty() {
        return Value::Null;
    }
    json!({
        "registrationProperties": {
            "isManualApprovalEnabled": false, "isWaitlistEnabled": false,
            "registrationOpenTime": {}, "isRegistrationOpenTimeEnabled": false
        },
        "questions": questions,
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
        // A private event admits its invited people (the service refuses
        // anything else: "expected InvitedUsers", 2026-11-18).
        "autoAdmittedUsers": if e.access == "Private" { "InvitedUsers" } else { "EveryoneInCompany" },
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

/// All options' changes over the form's meeting options.
fn merge_options(o: &mut Value, changes: Option<&Value>) {
    if let (Some(m), Some(c)) = (o.as_object_mut(), changes.and_then(Value::as_object)) {
        for (k, v) in c {
            m.insert(k.clone(), v.clone());
        }
    }
}

/// Teams' default promo pictures (ECS `virtualEvents.
/// oneEventsDefaultPromoImages`, 2026-11-16); a new event gets one.
pub const DEFAULT_PROMO_IMAGES: [&str; 12] = [
    "0-ea-d8-cb957d5c7670b8102f391ac3b8d2dcab",
    "0-ea-d9-7aa2763990eb6501cee5a1f10d1a64de",
    "0-ea-d1-844c96573cb54bea119d491e901da436",
    "0-ea-d4-9d0a5e76a96eeaf05a069df75c809e19",
    "0-ea-d12-f5f8bfa8939e0e526fb957efa7eba7ce",
    "0-ea-d10-c479e6b1249707acb0dc80b12f1828a4",
    "0-ea-d10-7ce1ec7262e6ddd449b707d3a7bd47fb",
    "0-ea-d12-f8379ddb570a56396c8b483fc469b987",
    "0-ea-d10-95ab29d1e8818087793edbc92fa7a7da",
    "0-ea-d12-d5cefd297ac4bfc461bcb599f90e4afb",
    "0-ea-d11-339f679162f8a786f523cabee1c66fc5",
    "0-ea-d8-03b7cf6be16d773074d3cf105e7aea72",
];

/// A default promo picture for a new event (ECS's list, else Teams').
pub fn default_promo() -> String {
    let list: Vec<String> = super::ecs::setting("virtualEvents", "oneEventsDefaultPromoImages")
        .and_then(|v| {
            v.as_array().map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(str::to_string))
                    .collect()
            })
        })
        .filter(|l: &Vec<String>| !l.is_empty())
        .unwrap_or_else(|| DEFAULT_PROMO_IMAGES.iter().map(|s| s.to_string()).collect());
    let i = (uuid::Uuid::new_v4().as_u128() % list.len() as u128) as usize;
    list[i].clone()
}

/// You, as Teams names the owner of a new event.
pub fn owner_of(client: &TeamsClient) -> Value {
    person(
        &client.user_principal_name().unwrap_or_default(),
        &client.display_name().unwrap_or_default(),
        &client.object_id().unwrap_or_default(),
        &client.tenant_id().unwrap_or_default(),
    )
}

/// Save a new event as a draft (Save and continue); its id.
pub async fn create_draft(client: &TeamsClient, e: &NewEvent) -> Result<Value> {
    anyhow::ensure!(!e.title.trim().is_empty(), "The event needs a name");
    let promo = if e.promo_image.is_empty() {
        default_promo()
    } else {
        e.promo_image.clone()
    };
    let body = create_body(e, &owner_of(client), tz_for(e), &promo);
    let r = send(
        reqwest::Method::POST,
        &format!("{}/events", regional_endpoint(client)),
        Some(&body),
        false,
    )
    .await?;
    let v: Value = r.json().await.context("The new event")?;
    let ams = client.ams_v2_url().unwrap_or_default();
    Ok(json!({
        "id": v.get("id").and_then(Value::as_str).unwrap_or_default(),
        "state": v.get("state").and_then(Value::as_str).unwrap_or_default(),
        "card": cards_from(&json!({ "results": [{ "eventDetails": v, "roles": ["Organizer"] }] }), &ams).pop(),
    }))
}

/// The form's zone (else this device's), as Teams sends it.
fn tz_for(e: &NewEvent) -> Value {
    if let Some(z) = zone_details(&e.time_zone) {
        return z;
    }
    let iana = super::find::local_timezone();
    let offset = crate::clock::local_offset_seconds() as i64 / 60;
    time_zone_details(&iana, offset)
}

fn event_path(id: &str) -> Result<String> {
    anyhow::ensure!(
        !id.is_empty()
            && id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '@'),
        "Not an event id"
    );
    Ok(id.to_string())
}

/// An event's overview (Teams' `events/{id}/overview`): the event, its
/// sessions, registration and your roles.
pub async fn overview(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let v = get_json(
        &format!(
            "{}/events/{}/overview",
            regional_endpoint(client),
            urlencoding(&id)
        ),
        false,
    )
    .await?;
    let ams = client.ams_v2_url().unwrap_or_default();
    let card = cards_from(&json!({ "results": [{ "eventDetails": v.get("event").cloned().unwrap_or_default(),
                                                 "eventSessions": v.get("sessions").cloned().unwrap_or_default(),
                                                 "registrationInfo": v.get("registrationInfo").or_else(|| v.get("registration")).cloned().unwrap_or_default(),
                                                 "roles": v.get("roles").cloned().unwrap_or_default() }] }), &ams)
        .pop();
    Ok(
        json!({ "card": card, "description": v.pointer("/event/description").cloned().unwrap_or_default(),
               "access": v.pointer("/event/access/accessType").cloned().unwrap_or_default(),
               "inviteOnly": v.pointer("/event/access/inviteOnly").cloned().unwrap_or_default(),
               "registration": v.pointer("/event/access/isRegistrationEnabled").cloned().unwrap_or_default() }),
    )
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
    // The event itself (`GET events/{id}`: owner, team, presenters with the
    // rooms, attendees), as People & emails reads it.
    let attendees_url = format!("{base}/attendees?status={statuses}&pageSize=20&skip=0&count=true");
    let (event, attendees) = tokio::join!(get_json(&base, false), get_json(&attendees_url, false));
    let event = event?;
    let names = |k: &str| -> Vec<Value> {
        event
            .get(k)
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(|p| {
                json!(
                    p.get("displayName")
                        .or_else(|| p.get("email"))
                        .cloned()
                        .unwrap_or_default()
                )
            })
            .collect()
    };
    let presenters = people_from(event.get("presenters"));
    let (rooms, speakers): (Vec<Person>, Vec<Person>) =
        presenters.into_iter().partition(|p| p.user_type == "Room");
    let mut organizers = vec![person_from(event.get("owner").unwrap_or(&Value::Null))];
    organizers.extend(people_from(event.get("team")));
    Ok(json!({
        "organizerList": organizers,
        "presenterList": speakers,
        "roomList": rooms,
        "attendeeList": people_from(event.get("attendees")),
        "disableAttendeeEmails": event.pointer("/communicationProperties/disableAttendeeEmails").cloned().unwrap_or(json!(false)),
        "organizers": [event.pointer("/owner/displayName").cloned().unwrap_or_default()],
        "coOrganizers": names("team"),
        "presenters": names("presenters"),
        "invited": names("attendees"),
        "registered": attendees.ok().and_then(|a| a.get("totalCount").or_else(|| a.get("count")).cloned()).unwrap_or(json!(0)),
    }))
}

/// The event's registrations as its organizers read them (People &
/// emails' `…/attendees?status=…`): each registrant with their answers.
pub async fn registrations(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let statuses = "Waitlisted,PendingApproval,Registered,Canceled";
    get_json(
        &format!(
            "{}/events/{}/attendees?status={statuses}&pageSize=20&skip=0&count=true",
            regional_endpoint(client),
            urlencoding(&id)
        ),
        false,
    )
    .await
}

/// Publish an event (the draft card's Publish event ▸ "Ready to publish
/// your event?" ▸ Publish event): `PATCH events/{id}` with
/// `{"state": "Published", "meetingOptions": null}` (captured 2026-11-17).
/// Invites go to its invited attendees, presenters and co-organizers.
pub async fn publish(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let body = json!({ "state": "Published", "meetingOptions": null });
    let r = send(
        reqwest::Method::PATCH,
        &format!("{}/events/{}", regional_endpoint(client), urlencoding(&id)),
        Some(&body),
        false,
    )
    .await?;
    let v: Value = r.json().await.context("The published event")?;
    Ok(
        json!({ "id": v.get("id").cloned().unwrap_or_default(), "state": v.get("state").cloned().unwrap_or_default(),
               "isDiscoverable": v.get("isDiscoverable").cloned().unwrap_or(Value::Bool(false)),
               "embedCode": if v.get("type").and_then(Value::as_str) == Some("Townhall") { json!(embed_code(&id)) } else { Value::Null } }),
    )
}

/// Your registration for an event (Teams' get-virtual-event-attendee-
/// registration-by-user, `GET events/{id}/users/{oid}/registration`):
/// the service's registration, or null when you haven't registered.
pub async fn my_registration(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let oid = client.object_id().context("Not signed in")?;
    let url = format!(
        "{}/events/{}/users/{oid}/registration",
        regional_endpoint(client),
        urlencoding(&id)
    );
    match get_json(&url, false).await {
        Ok(v) => Ok(v),
        Err(e) if e.to_string().contains("404") => Ok(Value::Null),
        Err(e) => Err(e),
    }
}

/// Teams' registration form's payload (meet-app Es, then the resolver's
/// RegisterVirtualEventAttendeeInput converter; captured on winpc
/// 2026-11-19, Discover's Register): the host locale ("en-us"), the browser's time zone
/// (its IANA name everywhere, "GMT-08:00 America/Los_Angeles" and the
/// offset in minutes), your names and email, the answers
/// (`{Id, Answer}`), the terms of use (null without any). Add to calendar
/// sends the same with `registrationType` "AddToCalendar".
pub fn register_body(
    iana: &str,
    utc_offset_minutes: i64,
    first: &str,
    last: &str,
    email: &str,
    answers: &[(String, Value)],
    terms: Option<bool>,
) -> Value {
    let sign = if utc_offset_minutes < 0 { '-' } else { '+' };
    let off = utc_offset_minutes.abs();
    let localized = if off == 0 {
        format!("GMT {iana}")
    } else {
        format!("GMT{sign}{:02}:{:02} {iana}", off / 60, off % 60)
    };
    json!({
        "language": "en-us",
        "timeZoneDetails": {
            "ianaTimeZone": iana, "windowsTimeZone": iana, "localizedTimeZoneString": localized,
            "utcOffset": utc_offset_minutes, "timeZone": iana
        },
        "firstName": first,
        "lastName": last,
        "email": email,
        "answers": answers.iter().map(|(id, a)| json!({ "Id": id, "Answer": a })).collect::<Vec<_>>(),
        "hasAcceptedTermsOfUse": terms,
    })
}

/// Register for an event (Teams' register-virtual-event-attendee, `POST
/// events/{id}/attendee/register`): `{registrationId, status,
/// meetingJoinUrl, registrationType}`.
pub async fn register(client: &TeamsClient, id: &str, body: &Value) -> Result<Value> {
    let id = event_path(id)?;
    let r = send(
        reqwest::Method::POST,
        &format!(
            "{}/events/{}/attendee/register",
            regional_endpoint(client),
            urlencoding(&id)
        ),
        Some(body),
        false,
    )
    .await?;
    r.json().await.context("The registration")
}

/// Unregister (the Registered button's Unregister ▸ Cancel registration,
/// captured 2026-11-19): `POST events/{id}/attendees/{registrationId}/
/// cancel`, no body, 204.
pub async fn unregister(client: &TeamsClient, id: &str, registration_id: &str) -> Result<()> {
    let id = event_path(id)?;
    anyhow::ensure!(
        !registration_id.is_empty()
            && registration_id
                .chars()
                .all(|c| c.is_ascii_hexdigit() || c == '-'),
        "Not a registration"
    );
    send(
        reqwest::Method::POST,
        &format!(
            "{}/events/{id}/attendees/{registration_id}/cancel",
            regional_endpoint(client)
        ),
        None,
        false,
    )
    .await?;
    Ok(())
}

/// The published dialog's "Show event in Events app" (Teams'
/// toggleDiscoverability ▸ updateVirtualEvent, whose input converter puts
/// the flag in `access`): `PATCH events/{id}` `{"access": {"isDiscoverable":
/// on}, "meetingOptions": null}`
/// with the event's eTag as If-Match (Teams' updateVirtualEvent, read
/// 2026-11-18). On, people in your organization with access see the event
/// on Events' Discover page.
pub async fn set_discoverable(client: &TeamsClient, id: &str, on: bool) -> Result<bool> {
    let id = event_path(id)?;
    let base = format!("{}/events/{}", regional_endpoint(client), urlencoding(&id));
    let ov = get_json(&format!("{base}/overview"), false).await?;
    let etag = ov
        .pointer("/event/eTag")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let t = token().await?;
    let mut req = reqwest::Client::new()
        .patch(&base)
        .bearer_auth(t)
        .header("content-type", "application/json")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .json(&json!({ "access": { "isDiscoverable": on }, "meetingOptions": null }));
    if !etag.is_empty() {
        req = req.header("If-Match", etag);
    }
    let r = req.send().await.context("The events service")?;
    anyhow::ensure!(
        r.status().is_success(),
        "The events service answered {}",
        r.status()
    );
    let v: Value = r.json().await.unwrap_or_default();
    Ok(v.pointer("/access/isDiscoverable")
        .or_else(|| v.get("isDiscoverable"))
        .and_then(Value::as_bool)
        .unwrap_or(on))
}

/// Teams' "Copy embed code" for a published town hall (the share dialog's
/// copy-embed-code-button, town halls only): an iframe of Teams' town hall
/// player page for the event.
pub fn embed_code(event_id: &str) -> String {
    format!(
        "<iframe src=\"https://teams.microsoft.com/convene/townhall?eventId={event_id}\" width=\"1280\" height=\"720\" frameborder=\"0\" scrolling=\"no\" allowfullscreen style=\"border:none;\" allow=\"autoplay; camera; microphone\"></iframe>"
    )
}

/// Cancel an event (the event page's ··· ▸ Cancel): Teams'
/// cancelVirtualEvent, `DELETE events/{id}`. A draft is gone; a published
/// event's attendees are emailed (Teams' dialog says so).
pub async fn cancel(client: &TeamsClient, id: &str) -> Result<()> {
    let id = event_path(id)?;
    send(
        reqwest::Method::DELETE,
        &format!("{}/events/{id}", regional_endpoint(client)),
        None,
        false,
    )
    .await?;
    Ok(())
}

/// See more: a whole section (Manage's Drafts / Published / Past, 25 a
/// page; Discover's lists), with Teams' paging token.
pub async fn see_more(client: &TeamsClient, section: &str, skip: &str) -> Result<Value> {
    let ams = client.ams_v2_url().unwrap_or_default();
    let tok = if skip.is_empty() {
        String::new()
    } else {
        format!("&skipToken={}", urlencoding(skip))
    };
    let now = jiff::Timestamp::now();
    let f = DiscoverFilter::default();
    let url = match section {
        "Draft" | "Published" | "Past" => format!(
            "{}/eventOverviews?manageFilterType={section}&pageSize=25&includeTotalCount=true&eventTypes=Townhall,Webinar{tok}",
            regional_endpoint(client)
        ),
        "upcoming" => format!(
            "{}{}{tok}",
            regional_endpoint(client),
            discover_query(DiscoverList::Upcoming, now, &f).replace("pageSize=21", "pageSize=25")
        ),
        "past" => format!(
            "{}{}{tok}",
            regional_endpoint(client),
            discover_query(DiscoverList::Past, now, &f).replace("pageSize=9", "pageSize=25")
        ),
        "now" => format!(
            "{}{}{tok}",
            regional_endpoint(client),
            discover_query(DiscoverList::Now, now, &f).replace("pageSize=9", "pageSize=25")
        ),
        _ => anyhow::bail!("Not a section"),
    };
    let r = get_json(&url, !matches!(section, "Draft" | "Published" | "Past")).await?;
    Ok(json!({
        "items": cards_from(&r, &ams),
        "total": r.get("totalCount").cloned().unwrap_or(Value::Null),
        "next": r.get("nextPageSkipToken").cloned().unwrap_or(Value::Null),
    }))
}

/// An event for Edit details, Duplicate and Save as template: the event
/// (`GET events/{id}`) and its session (`…/sessions`), as the form's fields.
pub async fn event_form(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let base = format!("{}/events/{id}", regional_endpoint(client));
    let sessions_url = format!("{base}/sessions");
    let (e, sessions) = tokio::join!(get_json(&base, false), get_json(&sessions_url, false));
    let e = e?;
    let sessions = sessions.unwrap_or_default();
    let session = sessions.get(0).cloned().unwrap_or_default();
    let presenters = people_from(e.get("presenters"));
    let (mut rooms, people): (Vec<Person>, Vec<Person>) =
        presenters.into_iter().partition(|p| p.user_type == "Room");
    let (viewing_rooms, attendees): (Vec<Person>, Vec<Person>) = people_from(e.get("attendees"))
        .into_iter()
        .partition(|p| p.user_type == "Room");
    rooms.extend(viewing_rooms.into_iter().map(|r| Person {
        room_role: "AttendeeViewing".into(),
        ..r
    }));
    Ok(json!({
        "id": e.get("id").cloned().unwrap_or_default(),
        "title": e.get("title").cloned().unwrap_or_default(),
        "description": e.get("description").cloned().unwrap_or_default(),
        "type": e.get("type").cloned().unwrap_or_default(),
        "state": e.get("state").cloned().unwrap_or_default(),
        "start": e.pointer("/eventTime/startTime").cloned().unwrap_or_default(),
        "end": e.pointer("/eventTime/endTime").cloned().unwrap_or_default(),
        "timeZone": e.pointer("/eventTime/timeZoneDetails/timeZone").cloned().unwrap_or_default(),
        "access": e.pointer("/access/accessType").cloned().unwrap_or_default(),
        "inviteOnly": e.pointer("/access/inviteOnly").cloned().unwrap_or_default(),
        "registration": e.pointer("/access/isRegistrationEnabled").cloned().unwrap_or_default(),
        "discoverable": e.pointer("/access/isDiscoverable").cloned().unwrap_or_default(),
        "promoImage": e.pointer("/theme/promoImage").cloned().unwrap_or_default(),
        "owner": person_from(e.get("owner").unwrap_or(&Value::Null)),
        "team": people_from(e.get("team")),
        "presenters": people,
        "rooms": rooms,
        "attendees": attendees,
        "sessionId": session.get("id").cloned().unwrap_or_default(),
        "meetingOptions": session.get("meetingOptions").cloned().unwrap_or(Value::Null),
        "communication": e.get("communicationProperties").cloned().unwrap_or_default(),
        "capacity": e.pointer("/eventCapacityProperties/maxEventCapacity").cloned().unwrap_or(Value::Null),
    }))
}

/// Edit details' Save changes: `PATCH events/{id}` with what the form
/// holds (Teams sends the type, description, access's registration and
/// discoverability, the people with the session's lobby setting and the
/// meeting options; captured 2026-11-18).
pub fn update_body(e: &NewEvent) -> Value {
    let to_ms = |s: &str| {
        crate::clock::parse_instant(s)
            .map(iso)
            .unwrap_or_else(|| s.to_string())
    };
    let mut options = new_meeting_options(e, e.event_type == "Townhall");
    merge_options(&mut options, e.meeting_options.as_ref());
    json!({
        "type": if e.event_type.is_empty() { "Webinar" } else { e.event_type.as_str() },
        "title": e.title,
        "description": e.description,
        "eventTime": { "startTime": to_ms(&e.start), "endTime": to_ms(&e.end), "timeZoneDetails": tz_for(e) },
        "access": { "isRegistrationEnabled": e.registration, "isDiscoverable": e.discoverable },
        "team": e.team.iter().map(|p| person_body(p, None)).collect::<Vec<_>>(),
        "presenters": e.presenters.iter().chain(presenting(&e.rooms)).map(|p| person_body(p, Some(&e.session_id))).collect::<Vec<_>>(),
        "attendees": e.attendees.iter().chain(viewing(&e.rooms)).map(|p| person_body(p, None)).collect::<Vec<_>>(),
        "meetingOptions": options,
    })
}

pub async fn update(client: &TeamsClient, id: &str, e: &NewEvent) -> Result<()> {
    let id = event_path(id)?;
    send(
        reqwest::Method::PATCH,
        &format!("{}/events/{id}", regional_endpoint(client)),
        Some(&update_body(e)),
        false,
    )
    .await?;
    Ok(())
}

/// A partial change Teams makes from the event's page: Show event in
/// Events app (`access.isDiscoverable`), Send attendee emails
/// (`communicationProperties.disableAttendeeEmails`).
pub async fn patch(client: &TeamsClient, id: &str, body: &Value) -> Result<()> {
    let id = event_path(id)?;
    send(
        reqwest::Method::PATCH,
        &format!("{}/events/{id}", regional_endpoint(client)),
        Some(body),
        false,
    )
    .await?;
    Ok(())
}

/// Duplicate's Save and continue: `POST events/{id}/duplicate` with the
/// new event (the same body as a new draft).
pub async fn duplicate(client: &TeamsClient, id: &str, e: &NewEvent) -> Result<Value> {
    let id = event_path(id)?;
    anyhow::ensure!(!e.title.trim().is_empty(), "The event needs a name");
    let promo = if e.promo_image.is_empty() {
        default_promo()
    } else {
        e.promo_image.clone()
    };
    let body = create_body(e, &owner_of(client), tz_for(e), &promo);
    let r = send(
        reqwest::Method::POST,
        &format!("{}/events/{id}/duplicate", regional_endpoint(client)),
        Some(&body),
        false,
    )
    .await?;
    let v: Value = r.json().await.context("The new event")?;
    let ams = client.ams_v2_url().unwrap_or_default();
    Ok(json!({
        "id": v.get("id").and_then(Value::as_str).unwrap_or_default(),
        "state": v.get("state").and_then(Value::as_str).unwrap_or_default(),
        "card": cards_from(&json!({ "results": [{ "eventDetails": v, "roles": ["Organizer"] }] }), &ams).pop(),
    }))
}

/// Save as template: `POST events/{id}/saveAsTemplate` with the event and
/// the template's name (`eventTemplateName`) and description.
pub fn template_body(e: &NewEvent, name: &str, description: &str) -> Value {
    let mut b = update_body(e);
    let m = b.as_object_mut().expect("an object");
    m.insert("language".into(), json!("en-us"));
    m.insert("state".into(), json!("Draft"));
    let (access_type, invite_only) = match e.access.as_str() {
        "Public" => ("Public", false),
        "Private" => ("Private", true),
        _ => ("Private", false),
    };
    m.insert("access".into(), json!({ "accessType": access_type, "inviteOnly": invite_only, "isRegistrationEnabled": e.registration }));
    m.insert("eventTemplateName".into(), json!(name));
    if !description.is_empty() {
        m.insert("eventTemplateDescription".into(), json!(description));
    }
    m.insert(
        "theme".into(),
        json!({ "primaryColor": "#5B5FC7", "promoImage": e.promo_image }),
    );
    b
}

pub async fn save_as_template(
    client: &TeamsClient,
    id: &str,
    e: &NewEvent,
    name: &str,
    description: &str,
) -> Result<Value> {
    let id = event_path(id)?;
    anyhow::ensure!(
        !name.trim().is_empty(),
        crate::i18n::tr_id("Template name is required", "virtualEvents:k8tdaiazv")
    );
    let r = send(
        reqwest::Method::POST,
        &format!("{}/events/{id}/saveAsTemplate", regional_endpoint(client)),
        Some(&template_body(e, name, description)),
        false,
    )
    .await?;
    let v: Value = r.json().await.context("The template")?;
    Ok(
        json!({ "id": v.get("id").cloned().unwrap_or_default(), "name": v.get("name").cloned().unwrap_or_default() }),
    )
}

/// Your saved templates (`GET eventTemplates`), as Create's cards.
pub async fn templates(client: &TeamsClient) -> Result<Value> {
    let ams = client.ams_v2_url().unwrap_or_default();
    let v = get_json(
        &format!("{}/eventTemplates", regional_endpoint(client)),
        false,
    )
    .await?;
    let list = v
        .as_array()
        .cloned()
        .or_else(|| v.get("value").and_then(Value::as_array).cloned())
        .unwrap_or_default();
    Ok(Value::Array(list.iter().map(|t| {
        let d = t.get("eventTemplateData").cloned().unwrap_or_default();
        let presenters = people_from(d.get("presenters"));
        let (rooms, people): (Vec<Person>, Vec<Person>) = presenters.into_iter().partition(|p| p.user_type == "Room");
        json!({
            "id": t.get("id").cloned().unwrap_or_default(),
            "name": t.get("name").cloned().unwrap_or_default(),
            "description": t.get("description").cloned().unwrap_or_default(),
            "promo": promo_url(&ams, d.pointer("/theme/promoImage").and_then(Value::as_str).unwrap_or_default()),
            "data": {
                "title": d.get("title").cloned().unwrap_or_default(),
                "description": d.get("description").cloned().unwrap_or_default(),
                "type": d.get("eventType").cloned().unwrap_or_default(),
                "access": d.pointer("/access/accessType").cloned().unwrap_or_default(),
                "inviteOnly": d.pointer("/access/inviteOnly").cloned().unwrap_or_default(),
                "registration": d.pointer("/access/isRegistrationEnabled").cloned().unwrap_or_default(),
                "promoImage": d.pointer("/theme/promoImage").cloned().unwrap_or_default(),
                "team": people_from(d.get("team")),
                "presenters": people,
                "rooms": rooms,
                "attendees": people_from(d.get("attendees")),
                "meetingOptions": d.get("meetingOptions").cloned().unwrap_or(Value::Null),
            }
        })
    }).collect()))
}

/// A template's Delete (`DELETE eventTemplates/{id}`; Teams asks nothing).
pub async fn delete_template(client: &TeamsClient, id: &str) -> Result<()> {
    anyhow::ensure!(uuid::Uuid::parse_str(id).is_ok(), "Not a template");
    send(
        reqwest::Method::DELETE,
        &format!("{}/eventTemplates/{id}", regional_endpoint(client)),
        None,
        false,
    )
    .await?;
    Ok(())
}

/// Edit template's Save (`PATCH eventTemplates/{id}`).
pub async fn update_template(
    client: &TeamsClient,
    id: &str,
    e: &NewEvent,
    name: &str,
    description: &str,
) -> Result<()> {
    anyhow::ensure!(uuid::Uuid::parse_str(id).is_ok(), "Not a template");
    send(
        reqwest::Method::PATCH,
        &format!("{}/eventTemplates/{id}", regional_endpoint(client)),
        Some(&template_body(e, name, description)),
        false,
    )
    .await?;
    Ok(())
}

/// Teams' meeting templates for events (All options' options and their
/// strings): webinar and town hall.
pub const WEBINAR_TEMPLATE: &str = "firstparty_d892ef44-003e-480c-9929-07349265a2e2";
pub const TOWN_HALL_TEMPLATE: &str = "firstparty_21f91ef7-6265-4064-b78b-41ab66889d90";

/// All options: the event template's meeting options as Teams reads them
/// (`GET {mt}/beta/meetingTemplates/details/{template}?isChannelMeeting=
/// false&language=en-us&useCategoriesV2=true`), in the meeting options
/// dialog's shape.
pub async fn template_options(client: &TeamsClient, town_hall: bool) -> Result<Value> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let id = if town_hall {
        TOWN_HALL_TEMPLATE
    } else {
        WEBINAR_TEMPLATE
    };
    let v: Value = client
        .http()
        .get(format!("{base}//beta/meetingTemplates/details/{id}?isChannelMeeting=false&language=en-us&useCategoriesV2=true"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("The event's meeting options")?
        .json()
        .await?;
    Ok(v)
}

/// The form's pickers search as Teams does (`POST {mt}/beta/users/searchV2
/// ?…&source=oneEvents`, the query as the body): co-organizers are people
/// in your org; presenters may be guests and external people; invitees
/// also groups and distribution lists.
pub fn search_flags(kind: &str) -> &'static str {
    match kind {
        "team" => "includeDLs=false&enableGuest=false&includeBots=true&skypeTeamsInfo=true",
        "presenters" => {
            "includeDLs=false&enableGuest=true&includeBots=true&includeMTOUsers=true&skypeTeamsInfo=true"
        }
        _ => {
            "includeDLs=true&enableGuest=true&includeBots=true&includeMTOUsers=true&skypeTeamsInfo=true"
        }
    }
}

pub async fn search_people(client: &TeamsClient, kind: &str, query: &str) -> Result<Vec<Person>> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .post(format!(
            "{base}/beta/users/searchV2?{}&source=oneEvents",
            search_flags(kind)
        ))
        .bearer_auth(&token)
        .header("content-type", "text/plain")
        .body(query.to_string())
        .send()
        .await?
        .error_for_status()?
        .json()
        .await
        .context("Search")?;
    let tid = client.tenant_id().unwrap_or_default();
    Ok(v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|r| {
            let c = super::channels::add_candidate_from(r)?;
            let user_type = if c.group {
                "Group".to_string()
            } else if c.is_guest {
                "Guest".to_string()
            } else {
                "ADUser".to_string()
            };
            let tenant = r
                .get("tenantId")
                .and_then(Value::as_str)
                .map(str::to_string)
                .or_else(|| {
                    r.get("id")
                        .and_then(Value::as_str)
                        .and_then(|i| i.split('@').nth(1))
                        .map(str::to_string)
                })
                .unwrap_or_else(|| tid.clone());
            Some(Person {
                name: c.name,
                email: c.mail.clone(),
                mri: c.mri,
                object_id: c.object_id,
                tenant_id: tenant,
                upn: r
                    .get("userPrincipalName")
                    .and_then(Value::as_str)
                    .unwrap_or(&c.mail)
                    .to_string(),
                user_type,
                group: c.group,
                detail: c.detail,
                room_role: String::new(),
            })
        })
        .collect())
}

/// Add a room: Teams' room search for the event's time
/// (`findmeetinglocations` with the time slot and availability), each room
/// resolved to its Teams account. [person, availability ("Free", "Busy")].
pub async fn search_rooms(
    client: &TeamsClient,
    query: &str,
    start: &str,
    end: &str,
    zone: &str,
) -> Result<Value> {
    let found = super::rooms::meeting_locations_at(client, query, start, end, zone).await?;
    let emails: Vec<String> = found.iter().map(|r| r.0.clone()).collect();
    let rooms = super::rooms::resolve(client, &emails)
        .await
        .unwrap_or_default();
    let tid = client.tenant_id().unwrap_or_default();
    Ok(Value::Array(
        found
            .iter()
            .filter_map(|(email, name, avail, oid)| {
                let r = rooms.iter().find(|r| r.email.eq_ignore_ascii_case(email));
                let mri = r
                    .map(|r| r.mri.clone())
                    .unwrap_or_else(|| crate::identity::work_user_mri(oid));
                (!oid.is_empty() || r.is_some()).then(|| json!({
            "name": name, "email": email, "mri": mri,
            "objectId": crate::identity::work_object_id(&mri).unwrap_or(&mri), "tenantId": tid, "upn": email,
            "userType": "Room", "group": false, "detail": email, "availability": avail,
        }))
            })
            .collect(),
    ))
}

/// Copy join details: the meeting's invitation as Teams copies it (the
/// scheduler's `views.html` for the session's meeting, a data URL).
pub async fn join_details(link: &str) -> Result<String> {
    anyhow::ensure!(
        link.starts_with("https://api.scheduler.teams.microsoft.com/"),
        "Not a meeting"
    );
    // Teams' meeting scheduling service (ECS meetingSchedulingServiceAuthResource);
    // Teams asks with the thread's own form ("19:meeting_…", not "19_meeting_…").
    let token =
        crate::auth::oauth::access_token_for("7557eb47-c689-4224-abcf-aef9bd7573df/.default")
            .await?;
    let link = link.replace("/19_meeting_", "/19:meeting_");
    let v: Value = reqwest::Client::new()
        .get(&link)
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let html = v
        .pointer("/views/html")
        .and_then(Value::as_str)
        .context("The meeting's invitation")?;
    let data = html.strip_prefix("data:text/html,").unwrap_or(html);
    // Form-encoded ("+" for a space).
    Ok(url::form_urlencoded::parse(format!("x={data}").as_bytes())
        .find(|(k, _)| k == "x")
        .map(|(_, v)| v.into_owned())
        .unwrap_or_default())
}

/// Connect apps: Teams' third-party integrations (ECS `virtualEvents.
/// integrationsThirdParty`, else the list Teams ships).
pub fn integrations() -> Value {
    super::ecs::setting("virtualEvents", "integrationsThirdParty").filter(Value::is_array).unwrap_or_else(|| json!([
        { "id": "third-party-hubspot", "name": "Connect Hubspot to Teams", "appName": "Hubspot",
          "description": "Integrate Teams with Hubspot to receive Hubspot notifications and send conference call details to Hubspot contacts for events.",
          "link": "https://ecosystem.hubspot.com/marketplace/apps/sales/sales-enablement/microsoft-teams-221635",
          "icons": ["https://statics.teams.cdn.office.net/evergreen-assets/virtual-events/integrations/hubspot-logo.png"] },
        { "id": "third-party-zapier-pardot", "name": "Integrate Teams webinars to Pardot", "appName": "Pardot",
          "description": "Share Teams webinar registration, attendance, and engagement data to automate workflows with Pardot using Zapier.",
          "link": "https://api.zapier.com/v1/embed/microsoft-teams-events/create/1736124?utm_content=msteams_webinar",
          "icons": ["https://statics.teams.cdn.office.net/evergreen-assets/virtual-events/integrations/zapier-logo-circle.png", "https://statics.teams.cdn.office.net/evergreen-assets/virtual-events/integrations/pardot-logo.png"] },
        { "id": "third-party-zapier-marketo", "name": "Automate workflows with Marketo", "appName": "Marketo",
          "description": "Share Teams webinar registration, attendance, and engagement data to automate workflows with Marketo using Zapier.",
          "link": "https://api.zapier.com/v1/embed/microsoft-teams-events/create/1747046?utm_content=msteams_webinar",
          "icons": ["https://statics.teams.cdn.office.net/evergreen-assets/virtual-events/integrations/zapier-logo-circle.png", "https://statics.teams.cdn.office.net/evergreen-assets/virtual-events/integrations/marketo-logo.png"] }
    ]))
}

/// Teams' Events app id (its app bar entry).
pub const APP_ID: &str = "a63f7012-8cc9-42d5-99c3-e35f526fab17";

/// The app bar's pinned apps from your entitlements (`isAppBarPinned`,
/// `appBarOrder`), as Teams keeps them.
pub fn pinned_from(v: &Value) -> Vec<(String, f64)> {
    let mut out: Vec<(String, f64)> = v
        .pointer("/value/userEntitlements")
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|o| o.values())
        .filter_map(Value::as_array)
        .flatten()
        .filter(|e| {
            e.get("isAppBarPinned")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        })
        .filter_map(|e| {
            Some((
                e.get("id")?.as_str()?.to_string(),
                e.get("appBarOrder").and_then(Value::as_f64).unwrap_or(0.0),
            ))
        })
        .collect();
    out.dedup_by(|a, b| a.0.eq_ignore_ascii_case(&b.0));
    out
}

async fn pinned_now(client: &TeamsClient) -> Result<Vec<(String, f64)>> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .post(format!(
            "{base}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned"
        ))
        .bearer_auth(&token)
        .json(&json!([]))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(pinned_from(&v))
}

/// Whether Events is pinned to your app bar (Teams' entitlements).
pub async fn is_pinned(client: &TeamsClient) -> Result<bool> {
    Ok(pinned_now(client)
        .await?
        .iter()
        .any(|(id, _)| id.eq_ignore_ascii_case(APP_ID)))
}

/// The body Teams posts to pin or unpin Events: every pinned app with its
/// order, Events last when pinning (captured 2026-11-18: `{"appBarPinnedApps":
/// [{"appId": "a63f7012-…", "appBarOrder": 10}, …]}`).
pub fn pinned_body(now: &[(String, f64)], pin: bool) -> Value {
    let mut list: Vec<Value> = Vec::new();
    let others: Vec<&(String, f64)> = now
        .iter()
        .filter(|(id, _)| !id.eq_ignore_ascii_case(APP_ID))
        .collect();
    if pin {
        let next = others.iter().map(|(_, o)| *o).fold(0.0_f64, f64::max) + 1.0;
        list.push(json!({ "appId": APP_ID, "appBarOrder": next as i64 }));
    }
    list.extend(
        others
            .iter()
            .map(|(id, o)| json!({ "appId": id, "appBarOrder": *o as i64 })),
    );
    json!({ "appBarPinnedApps": list })
}

pub async fn set_pinned(client: &TeamsClient, pin: bool) -> Result<()> {
    let now = pinned_now(client).await?;
    let (base, token) = super::tabs::middle_tier(client).await?;
    client
        .http()
        .post(format!("{base}/beta/users/apps/pinned"))
        .bearer_auth(&token)
        .json(&pinned_body(&now, pin))
        .send()
        .await?
        .error_for_status()
        .context("Pin app")?;
    Ok(())
}

/// People & emails: the event's email templates (`GET events/{id}/
/// emailtemplates`).
pub async fn email_templates(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    get_json(
        &format!("{}/events/{id}/emailtemplates", regional_endpoint(client)),
        false,
    )
    .await
}

fn template_path(id: &str) -> Result<String> {
    anyhow::ensure!(
        !id.is_empty()
            && id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'),
        "Not a template id"
    );
    Ok(id.to_string())
}

/// One email template (`GET events/{id}/emailtemplates/{templateId}`):
/// `{templateId, templateType, subject, body, senderName, senderEmail,
/// footer, sendTimeInterval, adO4867893_IsBodyEditableStatusCode}`.
pub async fn email_template(client: &TeamsClient, id: &str, template: &str) -> Result<Value> {
    let (id, template) = (event_path(id)?, template_path(template)?);
    get_json(
        &format!(
            "{}/events/{id}/emailtemplates/{template}",
            regional_endpoint(client)
        ),
        false,
    )
    .await
}

/// Only the fields Teams' email editor saves: `subject`, `body`,
/// `senderName`, and the reminder's `sendTimeInterval {days, hours}`;
/// empty values and objects left out, as Teams does.
pub fn email_template_patch(v: &Value) -> Value {
    let mut out = serde_json::Map::new();
    for k in ["subject", "body", "senderName"] {
        if let Some(s) = v.get(k).and_then(Value::as_str) {
            out.insert(k.into(), json!(s));
        }
    }
    if let Some(t) = v
        .get("sendTimeInterval")
        .filter(|t| t.as_object().is_some_and(|o| !o.is_empty()))
    {
        let n = |k: &str| t.get(k).and_then(Value::as_i64).unwrap_or(0);
        out.insert(
            "sendTimeInterval".into(),
            json!({ "hours": n("hours"), "days": n("days") }),
        );
    }
    Value::Object(out)
}

/// Save an email template (`PATCH events/{id}/emailtemplates/{templateId}`).
pub async fn update_email_template(
    client: &TeamsClient,
    id: &str,
    template: &str,
    v: &Value,
) -> Result<Value> {
    let (id, template) = (event_path(id)?, template_path(template)?);
    let r = send(
        reqwest::Method::PATCH,
        &format!(
            "{}/events/{id}/emailtemplates/{template}",
            regional_endpoint(client)
        ),
        Some(&email_template_patch(v)),
        false,
    )
    .await?;
    Ok(r.json().await.unwrap_or_else(|_| json!({})))
}

/// The event's eTag and theme (`GET events/{id}`), for the Branding
/// dialog's `If-Match`.
pub async fn theme(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let v = get_json(&format!("{}/events/{id}", regional_endpoint(client)), false).await?;
    let ams = client.ams_v2_url().unwrap_or_default();
    let img = |k: &str| {
        v.pointer(&format!("/theme/{k}"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    Ok(
        json!({ "eTag": v.get("eTag").or_else(|| v.get("etag")).cloned().unwrap_or(json!("*")),
               "primaryColor": v.pointer("/theme/primaryColor").cloned().unwrap_or_default(),
               "promoImage": img("promoImage"), "logoImage": img("logoImage"),
               "promoUrl": promo_url(&ams, &img("promoImage")), "logoUrl": promo_url(&ams, &img("logoImage")),
               "communicationProperties": v.get("communicationProperties").cloned().unwrap_or_default() }),
    )
}

async fn send_if_match(
    client: &TeamsClient,
    method: reqwest::Method,
    url: &str,
    body: Option<&Value>,
    etag: &str,
    skype: bool,
) -> Result<Value> {
    crate::auth::token_hosts::ensure(url, crate::auth::token_hosts::Audience::Teams)?;
    let t = token().await?;
    let mut req = reqwest::Client::new()
        .request(method, url)
        .bearer_auth(t)
        .header("content-type", "application/json")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .header("If-Match", if etag.is_empty() { "*" } else { etag });
    if skype {
        req = req.header("x-skypetoken", client.skype_token_value()?);
    }
    if let Some(b) = body {
        req = req.json(b);
    }
    let resp = req.send().await.context("The events service")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    anyhow::ensure!(status.is_success(), "The events service answered {status}");
    Ok(serde_json::from_str(&text).unwrap_or_else(|_| json!({})))
}

/// The Branding dialog's theme colour (`PATCH events/{id}/theme
/// {primaryColor}` with `If-Match`).
pub async fn set_theme_color(
    client: &TeamsClient,
    id: &str,
    etag: &str,
    color: &str,
) -> Result<Value> {
    let id = event_path(id)?;
    anyhow::ensure!(
        color.len() == 7
            && color.starts_with('#')
            && color[1..].chars().all(|c| c.is_ascii_hexdigit()),
        "Not a colour"
    );
    send_if_match(
        client,
        reqwest::Method::PATCH,
        &format!("{}/events/{id}/theme", regional_endpoint(client)),
        Some(&json!({ "primaryColor": color })),
        etag,
        false,
    )
    .await
}

/// Teams' image checks: PNG or JPG, at most 5 MB.
pub const MAX_THEME_IMAGE: usize = 5 * 1024 * 1024;

/// The cover image or logo (`PATCH events/{id}/theme/promo|logo {imageId,
/// image: data URL}` with `If-Match` and `x-skypetoken`; the service
/// hosts it): `bytes` a PNG or JPEG, `current` the image it replaces.
pub async fn set_theme_image(
    client: &TeamsClient,
    id: &str,
    etag: &str,
    which: &str,
    current: &str,
    bytes: &[u8],
) -> Result<Value> {
    let id = event_path(id)?;
    anyhow::ensure!(which == "promo" || which == "logo", "Not a theme image");
    anyhow::ensure!(
        bytes.len() <= MAX_THEME_IMAGE,
        "Choose a file smaller than 5 MB."
    );
    let mime = if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        "image/png"
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "image/jpeg"
    } else {
        anyhow::bail!("Choose a PNG or JPG file.")
    };
    use base64::Engine as _;
    let data = format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    );
    let mut body = json!({ "image": data });
    if !current.is_empty() {
        body["imageId"] = json!(current);
    } else if which == "logo" {
        body["imageId"] = json!("null");
    }
    send_if_match(
        client,
        reqwest::Method::PATCH,
        &format!("{}/events/{id}/theme/{which}", regional_endpoint(client)),
        Some(&body),
        etag,
        true,
    )
    .await
}

/// A town hall's Manage apps card (measured in Teams desktop 26304 on winpc,
/// TASK-0212, an "OST TEST 212 town hall apps" draft): the apps of ECS
/// `extensibility.baseTownhallAppEntityAllowlist` (Teams' worker filter for a
/// town hall's own thread allows only these; live today AI Producer
/// e7fb100c… and Custom Streaming a59fe11a…), named from their definitions
/// (batchedDefinitions); "Added" once the event meeting's chat has the app
/// (`GET {mt}/beta/chats/{thread}/apps/chatentitlements`). Teams listed
/// Custom Streaming above AI Producer, the reverse of the allowlist.
pub async fn townhall_apps(client: &TeamsClient, thread: &str) -> Result<Value> {
    anyhow::ensure!(
        thread.starts_with("19:") && thread.ends_with("@thread.v2"),
        "Not a meeting chat"
    );
    let mut ids: Vec<String> =
        super::ecs::setting("extensibility", "baseTownhallAppEntityAllowlist")
            .and_then(|v| serde_json::from_value(v).ok())
            .unwrap_or_default();
    ids.retain(|i| uuid::Uuid::parse_str(i).is_ok());
    ids.reverse();
    if ids.is_empty() {
        return Ok(json!({ "apps": [] }));
    }
    let defs = super::app_details::definitions(client, &ids).await?;
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let installed: String = client
        .http()
        .get(format!("{base}/beta/chats/{thread}/apps/chatentitlements"))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("The event's apps")?
        .text()
        .await?
        .to_lowercase();
    Ok(json!({ "apps": townhall_rows(&ids, &defs, &installed) }))
}

/// The card's rows in `ids` order: name, icon, configuration page, added
/// (the app's id quoted in the chat's entitlements).
pub fn townhall_rows(ids: &[String], defs: &[Value], installed: &str) -> Vec<Value> {
    ids.iter()
        .filter_map(|id| {
            let def = defs.iter().find(|d| {
                d.get("id")
                    .and_then(Value::as_str)
                    .is_some_and(|x| x.eq_ignore_ascii_case(id))
            })?;
            let app = super::store_content::store_app(def, None);
            Some(json!({
                "id": app.id, "name": app.name, "icon": app.icon, "config_url": app.config_url,
                "added": installed.contains(&format!("\"{}\"", id.to_lowercase())),
            }))
        })
        .collect()
}

/// The card's Add, first step (captured on winpc): the app goes into the
/// event meeting's chat (`POST {mt}/beta/chats/{thread}/apps/entitlements`
/// with its definition), before its tab configuration opens.
pub async fn townhall_app_install(client: &TeamsClient, thread: &str, app: &str) -> Result<Value> {
    anyhow::ensure!(
        thread.starts_with("19:")
            && thread.ends_with("@thread.v2")
            && uuid::Uuid::parse_str(app).is_ok(),
        "Not an app"
    );
    let def = super::app_details::definition(client, app).await?;
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    client
        .http()
        .post(format!("{base}/beta/chats/{thread}/apps/entitlements"))
        .bearer_auth(token)
        .header("x-client-ui-language", "en-us")
        .json(&def)
        .send()
        .await?
        .error_for_status()
        .context("Add the app to the event")?;
    Ok(json!({ "added": app }))
}

/// The card's Uninstall (Teams: "Uninstall {app} from this event?" ▸
/// Uninstall): the app's tabs leave the event meeting's chat (their thread
/// properties set to null), then the app (`DELETE {mt}/beta/chats/{thread}/
/// apps/entitlements/{app}`).
pub async fn townhall_app_remove(client: &TeamsClient, thread: &str, app: &str) -> Result<Value> {
    anyhow::ensure!(
        thread.starts_with("19:") && uuid::Uuid::parse_str(app).is_ok(),
        "Not an app"
    );
    for t in super::tab_add::chat_tabs(client, thread)
        .await
        .unwrap_or_default()
    {
        if t.app_id.eq_ignore_ascii_case(app) {
            super::tab_add::remove_property(client, thread, &t.id).await?;
        }
    }
    super::store_content::remove_from_chat(client, thread, app).await?;
    Ok(json!({ "removed": app }))
}

/// The event's sessions with their published recordings (Teams'
/// virtualEventSessions: `GET events/{id}/sessions`; each session's
/// `recordings` `[{id, name, publishProgress {status, subStatus,
/// progressPct, timeStamp}, expirationDate, isExpirationExtended, duration,
/// hasHighlights, sourceUrl, sourceDriveId, sourceItemId}]`).
pub async fn sessions(client: &TeamsClient, id: &str) -> Result<Value> {
    let id = event_path(id)?;
    let v = get_json(
        &format!("{}/events/{id}/sessions", regional_endpoint(client)),
        false,
    )
    .await?;
    Ok(v.get("value")
        .cloned()
        .filter(Value::is_array)
        .unwrap_or(if v.is_array() { v } else { json!([]) }))
}

fn session_path(s: &str) -> Result<&str> {
    anyhow::ensure!(
        !s.is_empty()
            && s.chars()
                .all(|c| c.is_ascii_alphanumeric() || "-_@".contains(c)),
        "Not a session id"
    );
    Ok(s)
}

/// Teams' addSessionRecording (Highlights' draft and Publish): `POST
/// events/{id}/sessions/{sid}/recordings` with the recording (see
/// [`super::event_highlights::recording_body`]) and the Skype token, as
/// its virtual events transport sends it.
pub async fn add_session_recording(
    client: &TeamsClient,
    id: &str,
    session: &str,
    body: &Value,
) -> Result<Value> {
    let id = event_path(id)?;
    let session = session_path(session)?;
    let t = token().await?;
    let resp = reqwest::Client::new()
        .post(format!(
            "{}/events/{id}/sessions/{session}/recordings",
            regional_endpoint(client)
        ))
        .bearer_auth(t)
        .header("content-type", "application/json")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .header("x-skypetoken", client.skype_token_value()?)
        .json(body)
        .send()
        .await
        .context("The events service")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        // Teams tells "RecordingAlreadyExists" apart from other failures.
        let v = serde_json::from_str::<Value>(&text).unwrap_or_default();
        let code = v
            .get("ErrorCode")
            .or_else(|| v.get("code"))
            .or_else(|| v.get("errorCode"))
            .map(|c| {
                c.as_str()
                    .map(str::to_string)
                    .unwrap_or_else(|| c.to_string())
            })
            .unwrap_or_default();
        let msg = v
            .get("ErrorMessage")
            .or_else(|| v.get("message"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        tracing::warn!(%status, %code, message = %msg.chars().take(300).collect::<String>(), "events: session recording refused");
        anyhow::bail!(
            "The events service answered {status}{}",
            if code.is_empty() {
                String::new()
            } else {
                format!(": {code}")
            }
        );
    }
    Ok(serde_json::from_str(&text).unwrap_or_else(|_| json!({})))
}

/// Teams' deleteSessionRecording: `DELETE events/{id}/sessions/{sid}/
/// recordings/{rid}`.
pub async fn delete_session_recording(
    client: &TeamsClient,
    id: &str,
    session: &str,
    recording: &str,
) -> Result<()> {
    let id = event_path(id)?;
    let session = session_path(session)?;
    let recording = session_path(recording)?;
    send(
        reqwest::Method::DELETE,
        &format!(
            "{}/events/{id}/sessions/{session}/recordings/{recording}",
            regional_endpoint(client)
        ),
        None,
        false,
    )
    .await?;
    Ok(())
}

/// Extend for 60 days (Teams' updateSessionRecording: `PATCH events/{id}/
/// sessions/{sid}/recordings/{rid}` `{expirationDurationExtensionDays}`).
pub async fn extend_session_recording(
    client: &TeamsClient,
    id: &str,
    session: &str,
    recording: &str,
    days: i64,
) -> Result<Value> {
    let id = event_path(id)?;
    let session = session_path(session)?;
    let recording = session_path(recording)?;
    let t = token().await?;
    let resp = reqwest::Client::new()
        .patch(format!(
            "{}/events/{id}/sessions/{session}/recordings/{recording}",
            regional_endpoint(client)
        ))
        .bearer_auth(t)
        .header("content-type", "application/json")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .header("x-skypetoken", client.skype_token_value()?)
        .json(&json!({ "expirationDurationExtensionDays": days }))
        .send()
        .await
        .context("The events service")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    anyhow::ensure!(status.is_success(), "The events service answered {status}");
    Ok(serde_json::from_str(&text).unwrap_or_else(|_| json!({})))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn townhall_card_rows() {
        let ids = vec![
            "a59fe11a-7ae8-4569-94d1-081c83ab59b6".to_string(),
            "e7fb100c-8c81-4e3f-9c78-bb1407080cdc".to_string(),
        ];
        let defs = vec![
            json!({"id": "e7fb100c-8c81-4e3f-9c78-bb1407080cdc", "name": "AI Producer", "largeImageUrl": "https://x/ai.png"}),
            json!({"id": "a59fe11a-7ae8-4569-94d1-081c83ab59b6", "name": "Custom Streaming", "largeImageUrl": "https://x/cs.png",
                   "configurableTabs": [{"configurationUrl": "https://teams.microsoft.com/extensibility-apps/meetingstream/rtmp/config?host=teams"}]}),
        ];
        let rows = townhall_rows(
            &ids,
            &defs,
            r#"{"value":[{"appId":"a59fe11a-7ae8-4569-94d1-081c83ab59b6"}]}"#,
        );
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0]["name"], "Custom Streaming");
        assert_eq!(rows[0]["added"], true);
        assert!(
            rows[0]["config_url"]
                .as_str()
                .unwrap()
                .contains("meetingstream/rtmp/config")
        );
        assert_eq!(rows[1]["name"], "AI Producer");
        assert_eq!(rows[1]["added"], false);
    }

    #[test]
    fn email_template_patch_keeps_the_editor_fields() {
        let v = json!({ "subject": "S", "body": "<p>{{eventName}}</p>", "senderName": "OST", "footer": "x", "templateId": "t",
                        "sendTimeInterval": { "hours": 2 } });
        assert_eq!(
            email_template_patch(&v),
            json!({ "subject": "S", "body": "<p>{{eventName}}</p>", "senderName": "OST",
                                                     "sendTimeInterval": { "hours": 2, "days": 0 } })
        );
        assert_eq!(
            email_template_patch(&json!({ "sendTimeInterval": {}, "subject": "A" })),
            json!({ "subject": "A" })
        );
    }

    fn at(s: &str) -> jiff::Timestamp {
        crate::clock::parse_instant(s).unwrap()
    }

    #[test]
    fn registers_as_teams_does() {
        // Teams desktop's Register (Discover, captured 2026-11-19).
        let b = register_body(
            "America/Los_Angeles",
            -480,
            "OST",
            "Test 1",
            "ost-test1@scnetsolutions.com",
            &[],
            None,
        );
        assert_eq!(
            b,
            json!({"language": "en-us", "timeZoneDetails": {"ianaTimeZone": "America/Los_Angeles", "windowsTimeZone": "America/Los_Angeles",
                "localizedTimeZoneString": "GMT-08:00 America/Los_Angeles", "utcOffset": -480, "timeZone": "America/Los_Angeles"},
                "firstName": "OST", "lastName": "Test 1", "email": "ost-test1@scnetsolutions.com", "answers": [], "hasAcceptedTermsOfUse": null})
        );
        let a = register_body(
            "Asia/Kolkata",
            330,
            "a",
            "b",
            "c",
            &[("q1".into(), json!("yes"))],
            Some(true),
        );
        assert_eq!(
            a["timeZoneDetails"]["localizedTimeZoneString"],
            "GMT+05:30 Asia/Kolkata"
        );
        assert_eq!(a["answers"], json!([{"Id": "q1", "Answer": "yes"}]));
        assert_eq!(a["hasAcceptedTermsOfUse"], true);
    }

    #[test]
    fn reads_your_registration_on_a_card() {
        let r = json!({"results": [{"eventDetails": {"id": "e1", "access": {"isRegistrationEnabled": true, "isDiscoverable": true}},
            "eventSessions": [{"id": "s1"}], "registrationInfo": {"questions": [], "termsOfUseUrl": null},
            "requesterPropertiesBySession": {"s1": {"registrationStatus": "Registered", "roles": []}}}]});
        let c = &cards_from(&r, "")[0];
        assert!(c.registration && c.discoverable);
        assert_eq!(
            (
                c.registration_status.as_str(),
                c.questions.len(),
                c.terms_url.as_str()
            ),
            ("Registered", 0, "")
        );
    }

    #[test]
    fn card_names_presenters_as_teams() {
        let p = |n: &str, extra: Value| {
            let mut v = json!({"displayName": n, "identity": {"tenantId": "t", "mri": format!("8:orgid:{n}")}});
            for (k, x) in extra.as_object().unwrap() {
                v[k] = x.clone();
            }
            v
        };
        let owner = json!({"displayName": "OST Test 2"});
        // No presenters: the owner.
        assert_eq!(card_presenters(&[], Some(&owner)), vec!["OST Test 2"]);
        // Rooms, hidden ones and nameless ones are left out; bypassing
        // ones come last; an external email name is a guest speaker.
        let list = vec![
            p("B", json!({"sessionsProps": [{"allowBypassLobby": true}]})),
            p("OST Test Room", json!({"userPurpose": "Room"})),
            p("Hidden", json!({"isHidden": true})),
            p("", json!({})),
            json!({"displayName": "guest@example.com", "identity": {}}),
            p("A", json!({})),
        ];
        assert_eq!(
            card_presenters(&list, Some(&owner)),
            vec!["Guest Speaker", "A", "B"]
        );
        // The card reads the event's owner from the reply.
        let r = json!({"results": [{"eventDetails": {"id": "e1", "owner": owner}, "eventSessions": [{"id": "s1", "speakers": []}]}]});
        assert_eq!(cards_from(&r, "")[0].by_names, vec!["OST Test 2"]);
    }

    #[test]
    fn registration_answers_as_teams() {
        let info = json!({"questions": [
            {"id": "q2", "type": "SingleChoice", "order": 2, "choices": ["Red", "Blue"]},
            {"id": "q1", "type": "Text", "order": 1},
            {"id": "q3", "type": "MultiChoice", "order": 3},
            {"id": "q4", "type": "Boolean", "order": 4},
            {"id": "q5", "type": "Note", "order": 5}
        ]});
        let q = registration_questions(Some(&info));
        assert_eq!(
            q.iter()
                .map(|x| x["id"].as_str().unwrap())
                .collect::<Vec<_>>(),
            vec!["q1", "q2", "q3", "q4", "q5"]
        );
        // Unset questions (a multiple choice nobody ticked) are left out.
        let a = registration_answers(
            &q,
            &json!({"q1": "OST", "q2": "Blue", "q4": false, "q5": null}),
        );
        assert_eq!(
            a,
            vec![
                ("q1".into(), json!("OST")),
                ("q2".into(), json!("Blue")),
                ("q4".into(), json!(false))
            ]
        );
        let a = registration_answers(&q, &json!({"q3": ["x", "y"], "q4": true}));
        assert_eq!(
            a,
            vec![("q3".into(), json!(["x", "y"])), ("q4".into(), json!(true))]
        );
    }

    #[test]
    fn discover_asks_as_teams() {
        let now = at("2026-11-16T22:53:50.241Z");
        let f = DiscoverFilter::default();
        assert_eq!(
            discover_query(DiscoverList::Now, now, &f),
            "/eventOverviews?pageSize=9&sortBy=StartTime&sortOrder=Ascending&startTo=2026-11-16T22:58:50.241Z&endFrom=2026-11-16T22:53:50.241Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg"
        );
        assert_eq!(
            discover_query(DiscoverList::Upcoming, now, &f),
            "/eventOverviews?pageSize=21&sortBy=StartTime&sortOrder=Ascending&startFrom=2026-11-16T22:58:50.241Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg"
        );
        assert_eq!(
            discover_query(DiscoverList::Past, now, &f),
            "/eventOverviews?pageSize=9&sortBy=EndTime&sortOrder=Descending&endTo=2026-11-16T22:53:50.241Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg"
        );
        let mine = DiscoverFilter {
            my_events: true,
            ..Default::default()
        };
        assert!(
            discover_query(DiscoverList::Past, now, &mine)
                .ends_with("&includeRequesterStatus=Registered&includeRequesterStatus=Invited")
        );
    }

    #[test]
    fn manage_asks_as_teams() {
        let q = manage_queries();
        assert_eq!(
            q[2].1,
            "/eventOverviews?manageFilterType=Draft&pageSize=4&includeTotalCount=true&eventTypes=Townhall,Webinar"
        );
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
        assert_eq!(
            c[0].promo_image,
            "https://us-prod.asyncgw.teams.microsoft.com/v1/objects/0-ea-d1-844c96573cb54bea119d491e901da436/views/imgpsh_fullsize?v=1"
        );
        assert_eq!(c[0].join_url, "https://teams.microsoft.com/l/meetup-join/x");
        assert_eq!(promo_url("https://x", "../evil"), "");
    }

    #[test]
    fn a_new_draft_is_sent_as_teams_sends_it() {
        let e = NewEvent {
            title: "OST TEST".into(),
            start: "2026-11-16T23:30:00Z".into(),
            end: "2026-11-17T00:00:00Z".into(),
            access: "Organization".into(),
            allow_mic: true,
            allow_camera: true,
            reactions: true,
            chat: true,
            qna: true,
            ..Default::default()
        };
        let b = create_body(
            &e,
            &json!({"displayName": "OST Test 1"}),
            time_zone_details("America/Los_Angeles", -480),
            DEFAULT_PROMO_IMAGES[2],
        );
        assert_eq!(
            b["theme"],
            json!({"primaryColor": "#5B5FC7", "promoImage": "0-ea-d1-844c96573cb54bea119d491e901da436"})
        );
        assert_eq!(b["type"], "Webinar");
        assert_eq!(b["eventTime"]["startTime"], "2026-11-16T23:30:00.000Z");
        assert_eq!(b["eventTime"]["timeZoneDetails"]["timeZone"], "PacificSt");
        assert_eq!(
            b["access"],
            json!({"accessType": "Private", "inviteOnly": false, "isRegistrationEnabled": false})
        );
        assert_eq!(b["attendees"], json!([]));
        assert_eq!(b["presenters"], json!([]));
        assert_eq!(b["meetingOptions"]["attendeeRestrictions"], "UnRestricted");
        assert_eq!(b["meetingOptions"]["allowMeetingChat"], "Enabled");
        let p = create_body(
            &NewEvent {
                access: "Public".into(),
                ..Default::default()
            },
            &json!({}),
            json!({}),
            "",
        );
        assert_eq!(p["access"]["accessType"], "Public");
        assert_eq!(p["meetingOptions"]["attendeeRestrictions"], "DisableAv");
        assert_eq!(p["eventCapacityProperties"], Value::Null);
        let big = create_body(
            &NewEvent {
                capacity: 10000,
                base_experience: true,
                ..Default::default()
            },
            &json!({}),
            json!({}),
            "",
        );
        assert_eq!(
            big["eventCapacityProperties"],
            json!({"maxEventCapacity": 10000, "isBaseEventExperience": true})
        );
    }

    #[test]
    fn a_town_hall_is_sent_as_teams_sends_it() {
        // Teams' town hall template, defaults kept (captured 2026-11-17).
        let e = NewEvent {
            event_type: "Townhall".into(),
            title: "OST TEST 184 town hall".into(),
            access: "Public".into(),
            green_room: true,
            qna: true,
            capacity: 3000,
            large_audience: true,
            ..Default::default()
        };
        let b = create_body(&e, &json!({}), json!({}), "");
        assert_eq!(b["type"], "Townhall");
        assert_eq!(
            b["access"],
            json!({"accessType": "Public", "inviteOnly": false, "isRegistrationEnabled": false})
        );
        assert_eq!(
            b["eventCapacityProperties"],
            json!({"maxEventCapacity": 3000, "isBaseEventExperience": false})
        );
        assert_eq!(
            b["commentStreamProperties"],
            json!({"isCommentStreamEnabled": true, "isPolicyAndLicenseCheckEnabled": true,
            "isSeparateBackroomChatThreadEnabled": true, "useBackroomChatAsMainThread": false, "useStreamingThreadForApps": true})
        );
        let o = &b["meetingOptions"];
        assert_eq!(o["attendeeRestrictions"], "DisableAudio,DisableVideo");
        assert_eq!(o["allowMeetingChat"], Value::Null);
        assert!(
            o.get("allowTeamsMeetingReactions").is_none() && o.get("autoAdmittedUsers").is_none()
        );
        assert_eq!(o["stagingRoomEnabled"], true);
        assert_eq!(o["yammerQNAEnabled"], true);
        assert_eq!(o["attendeeViewModes"], Value::Null);
        // A webinar keeps its comment stream off.
        let w = create_body(
            &NewEvent {
                event_type: "Webinar".into(),
                ..Default::default()
            },
            &json!({}),
            json!({}),
            "",
        );
        assert_eq!(
            w["commentStreamProperties"]["isCommentStreamEnabled"],
            false
        );
        assert!(
            w["meetingOptions"]
                .get("allowTeamsMeetingReactions")
                .is_some()
        );
    }

    #[test]
    fn the_embed_code_is_teams_town_hall_player() {
        assert_eq!(
            embed_code("e1@t1"),
            "<iframe src=\"https://teams.microsoft.com/convene/townhall?eventId=e1@t1\" width=\"1280\" height=\"720\" frameborder=\"0\" scrolling=\"no\" allowfullscreen style=\"border:none;\" allow=\"autoplay; camera; microphone\"></iframe>"
        );
    }

    #[test]
    fn people_rooms_and_zones_are_sent_as_teams_sends_them() {
        // Captured 2026-11-18 (Teams desktop's POST events).
        let p = Person {
            name: "OST Test 3".into(),
            email: "ost-test3@x.com".into(),
            mri: "8:orgid:01c4".into(),
            object_id: "01c4".into(),
            tenant_id: "2716".into(),
            upn: "ost-test3@x.com".into(),
            user_type: "ADUser".into(),
            ..Default::default()
        };
        let b = person_body(&p, Some(""));
        assert_eq!(b["sessionsProps"], json!([{ "allowBypassLobby": false }]));
        assert_eq!(
            b["identity"],
            json!({ "mri": "8:orgid:01c4", "objectId": "01c4", "tenantId": "2716", "upn": "ost-test3@x.com" })
        );
        assert_eq!(b["userPurpose"], "unknown");
        let room = Person {
            user_type: "Room".into(),
            ..p.clone()
        };
        assert_eq!(person_body(&room, Some("79cd"))["userPurpose"], "room");
        assert_eq!(
            person_body(&room, Some("79cd"))["sessionsProps"][0]["sessionId"],
            "79cd"
        );
        assert!(person_body(&p, None).get("sessionsProps").is_none());
        let e = NewEvent {
            team: vec![p.clone()],
            presenters: vec![p.clone()],
            rooms: vec![room],
            ..Default::default()
        };
        let c = create_body(&e, &json!({}), json!({}), "");
        assert_eq!(c["presenters"].as_array().unwrap().len(), 2);
        assert_eq!(c["presenters"][1]["userType"], "Room");
        assert_eq!(c["team"][0]["userType"], "ADUser");
        let z = zone_details("PacificSt").unwrap();
        assert_eq!(
            z,
            json!({ "timeZone": "PacificSt", "utcOffset": -480, "ianaTimeZone": "US/Pacific", "windowsTimeZone": "PacificSt", "localizedTimeZoneString": "PacificSt" })
        );
        assert_eq!(zone_details("IndianSt").unwrap()["utcOffset"], 330);
        assert_eq!(super::super::events_tz::ZONES.len(), 140);
    }

    #[test]
    fn filtered_discover_pickers_and_pins_ask_as_teams() {
        let now = at("2026-11-19T03:08:30.973Z");
        let f = DiscoverFilter {
            my_events: true,
            from: "2026-11-18T08:00:00.000Z".into(),
            to: "2026-12-01T07:59:59.999Z".into(),
        };
        assert_eq!(
            discover_query(DiscoverList::Upcoming, now, &f),
            "/eventOverviews?pageSize=100&sortBy=StartTime&startFrom=2026-11-18T08:00:00.000Z&startTo=2026-12-01T07:59:59.999Z&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=Registered&includeRequesterStatus=Invited"
        );
        assert_eq!(
            search_flags("team"),
            "includeDLs=false&enableGuest=false&includeBots=true&skypeTeamsInfo=true"
        );
        assert!(search_flags("attendees").starts_with("includeDLs=true"));
        let now = vec![("3b64df9d".to_string(), 3.0), ("14d6962d".to_string(), 1.0)];
        let b = pinned_body(&now, true);
        assert_eq!(
            b["appBarPinnedApps"][0],
            json!({ "appId": APP_ID, "appBarOrder": 4 })
        );
        assert_eq!(b["appBarPinnedApps"].as_array().unwrap().len(), 3);
        let mut with = now.clone();
        with.push((APP_ID.to_string(), 10.0));
        assert_eq!(
            pinned_body(&with, false)["appBarPinnedApps"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        let v = json!({"value": {"userEntitlements": {"u": [{"id": APP_ID, "isAppBarPinned": true, "appBarOrder": 10}, {"id": "x", "state": "Installed"}]}}});
        assert_eq!(pinned_from(&v), vec![(APP_ID.to_string(), 10.0)]);
    }

    #[test]
    fn edits_and_templates_are_sent_as_teams_sends_them() {
        let e = NewEvent {
            event_type: "Webinar".into(),
            title: "OST TEST 212".into(),
            description: "<p>x</p>".into(),
            session_id: "79cd".into(),
            presenters: vec![Person {
                name: "P".into(),
                ..Default::default()
            }],
            allow_mic: true,
            allow_camera: true,
            ..Default::default()
        };
        let u = update_body(&e);
        assert_eq!(
            u["access"],
            json!({ "isRegistrationEnabled": false, "isDiscoverable": false })
        );
        assert_eq!(u["presenters"][0]["sessionsProps"][0]["sessionId"], "79cd");
        assert_eq!(u["meetingOptions"]["attendeeRestrictions"], "UnRestricted");
        let t = template_body(&e, "OST TEST 212 template", "");
        assert_eq!(t["eventTemplateName"], "OST TEST 212 template");
        assert_eq!(t["state"], "Draft");
        assert_eq!(t["access"]["accessType"], "Private");
    }

    #[test]
    fn event_ids_are_checked() {
        assert!(event_path("963c6306-128c@2716d134").is_ok());
        assert!(event_path("../x").is_err());
        assert!(event_path("").is_err());
    }
}
