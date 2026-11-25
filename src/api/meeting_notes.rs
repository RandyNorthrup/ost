//! A meeting's notes (the call window's Notes), as Teams gets or makes
//! them (docs/spec/call-and-meeting-window.md "Notes"; Teams' modules
//! 648378 call-meeting-notes, 600612 its helper, services-io-collab-object,
//! read 2026-11-16, and a Meet now measured in Teams on the web):
//!
//! 1. A link someone already shared (the call's `collabResources.notes`
//!    meeting state) opens as it is.
//! 2. Otherwise Teams' meeting-notes service, `POST
//!    https://teams.microsoft.com/api/mcps/prod/notes/getOrCreateMeetingNotes`
//!    (ECS `cmdMeetingNotesServiceEndpoint`, token for resource
//!    6bc3b958-689b-49f5-9006-36d165f30e00) with `{threadId, organizer
//!    ("oid@tid"), meetingTitle, messageId "0", meetingUrl,
//!    externalEntityKey (the meeting's iCalUid), seriesExternalEntityKey,
//!    locale}`, answers `{resources: [{type: "notes", location,
//!    resourceState}], expiry}`; `pending` is asked again (up to 3 more
//!    times, after the expiry, at most 30 s; Teams' 5 s otherwise).
//! 3. When it can't (a Meet now in Teams on the web made its notes this
//!    way): claim `collabLeaders.notes`, make the page from Loop's
//!    `meeting` blueprint (Agenda, Meeting notes, Follow-up tasks) as
//!    `<title>.loop` in your OneDrive's Meetings folder (Graph
//!    `me/drive/special/meetings`; Fluid's create request without a share
//!    link scope), make its organization edit link (`createLink {"type":
//!    "edit", "scope": "organization"}`) and share it as
//!    `collabResources.notes`.

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// Teams' meeting-notes service (ECS cmdMeetingNotesServiceEndpoint).
pub const SERVICE: &str = "https://teams.microsoft.com/api/mcps/prod/notes";
/// Its resource (ECS cmdMeetingArtifactsServiceResource).
pub const RESOURCE: &str = "6bc3b958-689b-49f5-9006-36d165f30e00";
/// Teams' tries after a pending answer.
const RETRIES: u32 = 3;

/// What the service is told about the meeting.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Meeting {
    pub thread_id: String,
    pub organizer: String,
    pub meeting_title: String,
    pub meeting_url: String,
    pub i_cal_uid: String,
}

/// The request body Teams sends (call-meeting-notes `getOrCreateMeetingNotes`
/// with the helper's locale).
pub fn request_body(m: &Meeting) -> Value {
    json!({
        "threadId": m.thread_id,
        "organizer": m.organizer,
        "meetingTitle": m.meeting_title,
        "messageId": "0",
        "meetingUrl": m.meeting_url,
        "externalEntityKey": m.i_cal_uid,
        "seriesExternalEntityKey": m.i_cal_uid,
        "locale": "en-us",
    })
}

/// The service's answer: the notes' link and state.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Reply {
    pub location: String,
    /// "committed", "pending" or "" (Teams treats "" with a link as done).
    pub state: String,
    pub expiry: String,
}

pub fn parse_reply(v: &Value) -> Reply {
    let notes = v.get("resources").and_then(Value::as_array).and_then(|a| {
        a.iter().find(|r| {
            r.get("type")
                .and_then(Value::as_str)
                .is_some_and(|t| t.eq_ignore_ascii_case("notes"))
        })
    });
    let s = |x: Option<&Value>, k: &str| {
        x.and_then(|r| r.get(k))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    Reply {
        location: s(notes, "location"),
        state: s(notes, "resourceState").to_ascii_lowercase(),
        expiry: v
            .get("expiry")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
    }
}

/// How long to wait after a pending answer (Teams: the expiry, else 5 s,
/// at most 30 s).
pub fn retry_delay(expiry: &str, now: chrono::DateTime<chrono::Utc>) -> std::time::Duration {
    let ms = chrono::DateTime::parse_from_rfc3339(expiry)
        .ok()
        .map(|e| (e.with_timezone(&chrono::Utc) - now).num_milliseconds())
        .filter(|ms| *ms > 0)
        .unwrap_or(5000);
    std::time::Duration::from_millis(ms.clamp(1000, 30_000) as u64)
}

/// Fill what the call didn't say from the meeting chat's meeting (its
/// thread's properties: iCalUid, organizer, subject, join link), as Teams'
/// call object carries them.
pub async fn fill_from_chat(client: &TeamsClient, m: &mut Meeting) {
    if m.thread_id.is_empty()
        || (!m.i_cal_uid.is_empty() && !m.organizer.is_empty() && !m.meeting_title.is_empty())
    {
        return;
    }
    // (The chat service answers 429 to bursts, such as right after a join.)
    let mut tries = 0;
    let found = loop {
        match super::chat_meeting(client, &m.thread_id).await {
            Err(e) if tries < 3 && format!("{e:#}").contains("429") => {
                tries += 1;
                tokio::time::sleep(std::time::Duration::from_secs(3 * tries)).await;
            }
            r => break r,
        }
    };
    match found {
        Ok(Some(t)) => {
            if m.i_cal_uid.is_empty() {
                m.i_cal_uid = t.ical_uid;
            }
            if m.organizer.is_empty() && !t.organizer_id.is_empty() && !t.tenant_id.is_empty() {
                m.organizer = format!("{}@{}", t.organizer_id, t.tenant_id);
            }
            if m.meeting_title.is_empty() {
                m.meeting_title = t.subject;
            }
            if m.meeting_url.is_empty() {
                m.meeting_url = t.join_url;
            }
        }
        Ok(None) => {}
        Err(e) => tracing::info!(
            "meeting notes: the meeting chat's meeting: {}",
            format!("{e:#}").chars().take(160).collect::<String>()
        ),
    }
    // Still untitled: the calendar event's subject (what Teams' call
    // details name the meeting's instance by).
    if m.meeting_title.is_empty()
        && !m.i_cal_uid.is_empty()
        && let Ok(Some(ev)) = crate::api::calendar::event_by_ical_uid(client, &m.i_cal_uid).await
    {
        m.meeting_title = ev.subject;
    }
}

/// Get or make the meeting's notes through Teams' meeting-notes service;
/// the notes' link.
pub async fn get_or_create(m: &Meeting) -> Result<String> {
    anyhow::ensure!(
        !m.thread_id.is_empty() && !m.organizer.is_empty(),
        "This call isn't a meeting with notes"
    );
    let token = crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await?;
    let http = reqwest::Client::new();
    let body = request_body(m);
    for attempt in 0..=RETRIES {
        let resp = http
            .post(format!("{SERVICE}/getOrCreateMeetingNotes"))
            .bearer_auth(&token)
            .header("content-type", "application/json;charset=UTF-8")
            .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
            .json(&body)
            .send()
            .await
            .context("The meeting-notes service")?;
        let status = resp.status();
        if !status.is_success() {
            // The service's error (codes and messages, no secrets).
            let text = resp.text().await.unwrap_or_default();
            tracing::info!(
                "meeting-notes service: HTTP {status}: {}",
                text.chars().take(600).collect::<String>()
            );
            anyhow::bail!("The meeting-notes service answered {status}");
        }
        let r = parse_reply(
            &resp
                .json()
                .await
                .context("The meeting-notes service's reply")?,
        );
        if !r.location.is_empty() && (r.state == "committed" || r.state.is_empty()) {
            return Ok(r.location);
        }
        if r.state == "pending" && attempt < RETRIES {
            tokio::time::sleep(retry_delay(&r.expiry, chrono::Utc::now())).await;
            continue;
        }
        anyhow::bail!(
            "The meeting-notes service has no notes ({})",
            if r.state.is_empty() {
                "no link"
            } else {
                r.state.as_str()
            }
        );
    }
    anyhow::bail!("The meeting-notes service's notes stayed pending")
}

/// Teams' collab object service for a scheduled meeting's notes
/// (services-io-collab-object; captured 2026-11-18 from Teams desktop when
/// it made a scheduled meeting's notes): `POST {mcps}/collab/reserveresource`
/// claims making them (or returns the ones made), `PATCH …/commitresource`
/// gives the made page's link. `{mcps}` is the regional meeting artifacts
/// service (`https://teams.microsoft.com/api/mcps/{region}`; ECS
/// cmdMeetingArtifactsServiceEndpoint with the region put in).
pub fn collab_base(region: &str) -> String {
    let region = if region.is_empty()
        || !region
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-')
    {
        "us"
    } else {
        region
    };
    format!("https://teams.microsoft.com/api/mcps/{region}/collab")
}

/// Who asks and for which meeting (the reserve and commit requests).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CollabCaller {
    /// "oid@tid".
    pub user: String,
    pub organizer_upn: String,
}

/// The reserve request as Teams sends it (call-meeting-notes
/// reserveCollabResource: type "Notes").
pub fn reserve_body(m: &Meeting, c: &CollabCaller) -> Value {
    let organizer_id = m.organizer.split('@').next().unwrap_or_default();
    json!({
        "type": "Notes",
        "externalEntityKey": m.i_cal_uid,
        "seriesExternalEntityKey": m.i_cal_uid,
        "meetingUrl": m.meeting_url,
        "threadId": m.thread_id,
        "messageId": "0",
        "organizerUpn": c.organizer_upn,
        "organizer": m.organizer,
        "user": c.user,
        "organizedByUserId": organizer_id,
        "organizedByUserUpn": c.organizer_upn,
    })
}

/// The reserve answer: whether you make the notes (`isLeader`, with the
/// secret to commit them), or the notes already made.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Reserve {
    pub is_leader: bool,
    pub secret: String,
    pub state: String,
    /// The notes already made (`collab.resources[type notes].location`).
    pub location: String,
}

pub fn parse_reserve(v: &Value) -> Reserve {
    let notes = v
        .pointer("/collab/resources")
        .and_then(Value::as_array)
        .and_then(|a| {
            a.iter().find(|r| {
                r.get("type")
                    .and_then(Value::as_str)
                    .is_some_and(|t| t.eq_ignore_ascii_case("notes"))
            })
        });
    Reserve {
        is_leader: v.get("isLeader").and_then(Value::as_bool).unwrap_or(false),
        secret: v
            .get("secret")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        state: v
            .get("resourceState")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_ascii_lowercase(),
        location: notes
            .and_then(|r| r.get("location"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
    }
}

/// The commit request: the made page's shared link (with its `nav`), as
/// Teams' commitCollabResource sends it. Without `state: "Enabled"` the
/// resource stays pending for everyone else in the meeting.
pub fn commit_body(m: &Meeting, c: &CollabCaller, secret: &str, resource_uri: &str) -> Value {
    json!({
        "type": "Notes",
        "externalEntityKey": m.i_cal_uid,
        "seriesExternalEntityKey": m.i_cal_uid,
        "organizer": m.organizer,
        "user": c.user,
        "secret": secret,
        "resourceUri": resource_uri,
        "metadata": { "state": "Enabled", "linkScope": "organization", "hostClient": "TeamsInMeeting", "creationSource": "LWSApi" },
    })
}

async fn collab_send(
    method: reqwest::Method,
    url: &str,
    body: &Value,
) -> Result<reqwest::Response> {
    let token = crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await?;
    let resp = reqwest::Client::new()
        .request(method, url)
        .bearer_auth(&token)
        .header("content-type", "application/json;charset=UTF-8")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .json(body)
        .send()
        .await
        .context("The collab object service")?;
    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().await.unwrap_or_default();
        tracing::info!(
            "collab object service: HTTP {status}: {}",
            text.chars().take(400).collect::<String>()
        );
        anyhow::bail!("The collab object service answered {status}");
    }
    Ok(resp)
}

/// The notes a meeting already has (Teams' recap Notes reads the collab
/// object, `GET {mcps}/collab/readcollabobject/V2/{organizer}@{tenant}/
/// {iCalUid}/{thread}`): the Notes resource's location, or "".
pub fn notes_location(v: &Value) -> String {
    v.get("resources")
        .and_then(Value::as_array)
        .and_then(|a| {
            a.iter().find(|r| {
                r.get("type")
                    .and_then(Value::as_str)
                    .is_some_and(|t| t.eq_ignore_ascii_case("notes"))
            })
        })
        .and_then(|r| r.get("location"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

pub async fn read_notes(
    region: &str,
    organizer_oid: &str,
    tenant: &str,
    ical_uid: &str,
    thread: &str,
) -> Result<String> {
    let ok = |s: &str| {
        !s.is_empty()
            && s.chars()
                .all(|c| c.is_ascii_alphanumeric() || "-:@._".contains(c))
    };
    anyhow::ensure!(
        ok(organizer_oid) && ok(tenant) && ok(ical_uid) && ok(thread),
        "Not a meeting"
    );
    let token = crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await?;
    let who = format!("{organizer_oid}@{tenant}");
    let url = crate::auth::token_hosts::service_url(
        &collab_base(region),
        crate::auth::token_hosts::Audience::Teams,
        &["readcollabobject", "V2", &who, ical_uid, thread],
        &[],
    )?;
    let r = reqwest::Client::new()
        .get(url)
        .bearer_auth(&token)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .send()
        .await
        .context("The collab object service")?;
    if r.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(String::new());
    }
    anyhow::ensure!(
        r.status().is_success(),
        "The collab object service answered {}",
        r.status()
    );
    Ok(notes_location(&r.json().await.unwrap_or_default()))
}

/// Reserve the notes of a scheduled meeting: made already, yours to make,
/// or someone else is making them (pending: asked again, as Teams does).
pub async fn reserve(region: &str, m: &Meeting, c: &CollabCaller) -> Result<Reserve> {
    anyhow::ensure!(
        !m.i_cal_uid.is_empty() && !m.organizer.is_empty(),
        "Not a scheduled meeting"
    );
    let url = format!("{}/reserveresource", collab_base(region));
    // The keys the collab object files the notes under (not secrets: the
    // meeting's calendar id and chat thread).
    tracing::info!(external_entity_key = %m.i_cal_uid, thread = %m.thread_id, organizer = %m.organizer, "meeting notes: reserve");
    for attempt in 0..=RETRIES {
        let r = parse_reserve(
            &collab_send(reqwest::Method::POST, &url, &reserve_body(m, c))
                .await?
                .json()
                .await
                .context("The reserve answer")?,
        );
        if !r.location.is_empty() || r.is_leader || attempt == RETRIES {
            return Ok(r);
        }
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    }
    anyhow::bail!("The meeting's notes stayed pending")
}

/// Commit the made notes (their shared link) for everyone.
pub async fn commit(
    region: &str,
    m: &Meeting,
    c: &CollabCaller,
    secret: &str,
    resource_uri: &str,
) -> Result<()> {
    let v: Value = collab_send(
        reqwest::Method::PATCH,
        &format!("{}/commitresource", collab_base(region)),
        &commit_body(m, c, secret, resource_uri),
    )
    .await?
    .json()
    .await
    .unwrap_or_default();
    // Teams treats an answer without wasSuccessful as a failed commit.
    if v.get("wasSuccessful").and_then(Value::as_bool) == Some(false) {
        anyhow::bail!(
            "The meeting's notes weren't committed ({})",
            v.get("statusCode").cloned().unwrap_or_default()
        );
    }
    tracing::info!(answer = %v.to_string().chars().take(300).collect::<String>(), "meeting notes: commit");
    Ok(())
}

/// More actions ▸ Add to Loop workspace: Loop's own page for it (the Fluid
/// host controls' link: `https://loop.microsoft.com/p/<base64 of
/// {"p":{"u":<link>,"r":false},"a":"AddToWorkspace"}>`).
pub fn add_to_workspace_url(link: &str) -> String {
    use base64::Engine as _;
    // In Teams' key order (its JSON.stringify of {p: {u, r}, a}).
    let payload = format!(
        r#"{{"p":{{"u":{},"r":false}},"a":"AddToWorkspace"}}"#,
        Value::String(link.to_string())
    );
    let b64 = base64::engine::general_purpose::STANDARD.encode(payload);
    let enc: String = url::form_urlencoded::byte_serialize(b64.as_bytes()).collect();
    // encodeURIComponent keeps none of "+/=": byte_serialize matches it.
    format!("https://loop.microsoft.com/p/{enc}")
}

/// The notes' file (for See who has access): its SharePoint site, list and
/// item, and name, from its link (Graph `shares/u!…/driveItem`).
pub async fn notes_item(client: &TeamsClient, link: &str) -> Result<Value> {
    let id = super::drive::share_id(link.split('?').next().unwrap_or(link));
    let v: Value = client
        .graph_get(&format!(
            "/shares/{id}/driveItem?$select=name,sharepointIds,webUrl"
        ))
        .await?
        .json()
        .await?;
    let s = |p: &str| {
        v.pointer(p)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    anyhow::ensure!(
        !s("/sharepointIds/listItemUniqueId").is_empty()
            || !s("/sharepointIds/listItemId").is_empty(),
        "The notes' file"
    );
    Ok(
        json!({ "site": s("/sharepointIds/siteUrl"), "list": s("/sharepointIds/listId"), "item": s("/sharepointIds/listItemId"), "name": s("/name") }),
    )
}

/// Test cleanup (the harness): delete the notes pages in your Meetings
/// folder whose names start with `prefix` ("OST TEST 212"); their names.
pub async fn delete_test_notes(client: &TeamsClient, prefix: &str) -> Result<Vec<String>> {
    anyhow::ensure!(prefix.starts_with("OST TEST "), "Only test notes");
    let v: Value = client
        .graph_get("/me/drive/special/meetings/children?$select=id,name,parentReference&$top=200")
        .await?
        .json()
        .await?;
    let mut gone = Vec::new();
    for it in v
        .get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let name = it.get("name").and_then(Value::as_str).unwrap_or_default();
        if !name.starts_with(prefix) || !name.ends_with(".loop") {
            continue;
        }
        let drive = it
            .pointer("/parentReference/driveId")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let id = it.get("id").and_then(Value::as_str).unwrap_or_default();
        if super::drive::delete(client, drive, id).await.is_ok() {
            gone.push(name.to_string());
        }
    }
    Ok(gone)
}

/// The meeting organizer's sign-in name (the reserve request's
/// `organizerUpn`).
pub async fn organizer_upn(client: &TeamsClient, organizer: &str) -> String {
    let oid = organizer.split('@').next().unwrap_or_default();
    if oid.is_empty() || client.object_id().as_deref() == Some(oid) {
        return client.user_principal_name().unwrap_or_default();
    }
    if uuid::Uuid::parse_str(oid).is_err() {
        return String::new();
    }
    match client
        .graph_get(&format!("/users/{oid}?$select=userPrincipalName"))
        .await
    {
        Ok(r) => r
            .json::<Value>()
            .await
            .ok()
            .and_then(|v| {
                v.get("userPrincipalName")
                    .and_then(Value::as_str)
                    .map(str::to_string)
            })
            .unwrap_or_default(),
        Err(_) => String::new(),
    }
}

/// Where Teams makes a meeting's notes itself: your OneDrive's Meetings
/// folder.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Target {
    pub site_url: String,
    pub drive_id: String,
    pub file_path: String,
}

/// Your OneDrive's site from its library address
/// (`https://t-my.sharepoint.com/personal/u/Documents` → `…/personal/u`).
pub fn site_of(library_url: &str) -> Option<String> {
    let u = url::Url::parse(library_url).ok()?;
    let mut segs: Vec<&str> = u.path_segments()?.filter(|s| !s.is_empty()).collect();
    (segs.len() >= 3 && segs[0] == "personal").then_some(())?;
    segs.truncate(2);
    Some(format!(
        "{}://{}/{}",
        u.scheme(),
        u.host_str()?,
        segs.join("/")
    ))
}

pub async fn meetings_target(client: &TeamsClient) -> Result<Target> {
    let folder: Value = client
        .graph_get("/me/drive/special/meetings?$select=id,name,parentReference")
        .await?
        .json()
        .await?;
    let drive: Value = client
        .graph_get("/me/drive?$select=id,webUrl")
        .await?
        .json()
        .await?;
    let drive_id = folder
        .pointer("/parentReference/driveId")
        .and_then(Value::as_str)
        .or_else(|| drive.get("id").and_then(Value::as_str))
        .unwrap_or_default();
    let name = folder
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("Meetings");
    let site = site_of(
        drive
            .get("webUrl")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )
    .context("Your OneDrive")?;
    anyhow::ensure!(!drive_id.is_empty(), "Your OneDrive");
    Ok(Target {
        site_url: site,
        drive_id: drive_id.to_string(),
        file_path: name.to_string(),
    })
}

/// A page's file name as Teams names it: the meeting's title (Teams'
/// "Meeting Notes" without one) with characters a file can't have left
/// out, then `.loop`.
pub fn file_name(title: &str) -> String {
    let clean: String = title
        .chars()
        .filter(|c| !"\"*:<>?/\\|#%".contains(*c) && !c.is_control())
        .collect();
    let clean = clean.trim().trim_end_matches('.').to_string();
    format!(
        "{}.loop",
        if clean.is_empty() {
            "Meeting Notes".to_string()
        } else {
            clean
        }
    )
}

/// The notes' link Teams shares: the item's organization edit link with
/// the page's `nav` (from the page's own link).
pub fn shared_link(edit_link: &str, page_link: &str) -> String {
    let nav = url::Url::parse(page_link).ok().and_then(|u| {
        u.query_pairs()
            .find(|(k, _)| k == "nav")
            .map(|(_, v)| v.into_owned())
    });
    match nav {
        Some(n) => {
            let enc: String = url::form_urlencoded::byte_serialize(n.as_bytes()).collect();
            format!(
                "{edit_link}{}nav={enc}",
                if edit_link.contains('?') { '&' } else { '?' }
            )
        }
        None => edit_link.to_string(),
    }
}

/// The organization edit link of a made page, as Teams makes it: OneDrive's
/// own `POST {your OneDrive site}/_api/v2.1/drives/{drive}/items/{item}/
/// createLink {"type": "edit", "scope": "organization"}` (captured from
/// Teams desktop making a Meet now's notes, TASK-0212). Its link is the
/// short `/:fl:/p/<user>/<token>` form; Graph's createLink answers with
/// the older `/:fl:/g/personal/…` one, which the call refuses to store as
/// a Meet now's notes (CollabCommitError CrossTenantRequest, 6176).
pub async fn edit_link(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<String> {
    let ok = |s: &str| {
        !s.is_empty()
            && s.chars()
                .all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c))
    };
    anyhow::ensure!(ok(drive_id) && ok(item_id), "Not a page");
    let site = meetings_target(client).await?.site_url;
    let host = url::Url::parse(&site)
        .ok()
        .and_then(|u| u.host_str().map(str::to_string))
        .context("Your OneDrive")?;
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "Your OneDrive");
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let v: Value = client
        .http()
        .post(create_link_url(&site, drive_id, item_id))
        .bearer_auth(token)
        .json(&json!({ "type": "edit", "scope": "organization" }))
        .send()
        .await?
        .error_for_status()
        .context("The page's link")?
        .json()
        .await?;
    v.pointer("/link/webUrl")
        .and_then(Value::as_str)
        .map(str::to_string)
        .context("The page's link")
}

/// OneDrive's createLink address for an item of your OneDrive site.
pub fn create_link_url(site: &str, drive_id: &str, item_id: &str) -> String {
    format!(
        "{}/_api/v2.1/drives/{drive_id}/items/{item_id}/createLink",
        site.trim_end_matches('/')
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notes_from_the_collab_object() {
        let v = json!({"resources": [{"type": "TranscriptV2", "location": "t"}, {"type": "Notes", "location": "https://x.sharepoint.com/:fl:/g/n"}]});
        assert_eq!(notes_location(&v), "https://x.sharepoint.com/:fl:/g/n");
        assert_eq!(
            notes_location(&json!({"resources": [{"type": "TranscriptV2", "location": "t"}]})),
            ""
        );
    }

    #[test]
    fn asks_as_teams() {
        let m = Meeting {
            thread_id: "19:meeting_x@thread.v2".into(),
            organizer: "o@t".into(),
            meeting_title: "OST TEST".into(),
            meeting_url: "https://teams.microsoft.com/l/meetup-join/x".into(),
            i_cal_uid: "040000".into(),
        };
        let b = request_body(&m);
        assert_eq!(b["messageId"], "0");
        assert_eq!(b["externalEntityKey"], "040000");
        assert_eq!(b["organizer"], "o@t");
    }

    #[test]
    fn reads_the_answer() {
        let r = parse_reply(
            &json!({"resources": [{"type": "Notes", "location": "https://x/:fl:/p", "resourceState": "Committed"}], "expiry": "2026-11-16T23:00:05Z"}),
        );
        assert_eq!(r.location, "https://x/:fl:/p");
        assert_eq!(r.state, "committed");
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-16T23:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(retry_delay("2026-11-16T23:00:05Z", now).as_millis(), 5000);
        assert_eq!(retry_delay("2026-11-16T23:05:00Z", now).as_millis(), 30_000);
        assert_eq!(retry_delay("", now).as_millis(), 5000);
    }

    #[test]
    fn collab_object_as_teams() {
        // Captured 2026-11-18 (Teams desktop making a scheduled meeting's notes).
        let m = Meeting {
            thread_id: "19:meeting_Z@thread.v2".into(),
            organizer: "4287@2716".into(),
            meeting_title: "OST TEST 212".into(),
            meeting_url: "https://teams.microsoft.com/l/meetup-join/x".into(),
            i_cal_uid: "0400".into(),
        };
        let c = CollabCaller {
            user: "4287@2716".into(),
            organizer_upn: "ost-test1@x.com".into(),
        };
        let r = reserve_body(&m, &c);
        assert_eq!(r["type"], "Notes");
        assert_eq!(r["externalEntityKey"], "0400");
        assert_eq!(r["organizedByUserId"], "4287");
        assert_eq!(r["organizerUpn"], "ost-test1@x.com");
        let a = parse_reserve(
            &json!({"isLeader": true, "secret": "s", "resourceState": "pending", "collab": {"resources": []}}),
        );
        assert!(a.is_leader && a.location.is_empty() && a.state == "pending");
        let b = parse_reserve(
            &json!({"isLeader": false, "collab": {"resources": [{"type": "notes", "location": "https://x/:fl:/p"}]}}),
        );
        assert_eq!(b.location, "https://x/:fl:/p");
        let k = commit_body(&m, &c, "s", "https://x/:fl:/p?nav=1");
        assert_eq!(
            k["metadata"],
            json!({ "state": "Enabled", "linkScope": "organization", "hostClient": "TeamsInMeeting", "creationSource": "LWSApi" })
        );
        assert_eq!(k["type"], "Notes");
        assert_eq!(
            collab_base("us"),
            "https://teams.microsoft.com/api/mcps/us/collab"
        );
        assert_eq!(
            collab_base("../x"),
            "https://teams.microsoft.com/api/mcps/us/collab"
        );
        let w = add_to_workspace_url("https://x/:fl:/p");
        assert!(w.starts_with("https://loop.microsoft.com/p/"));
        let enc = w.trim_start_matches("https://loop.microsoft.com/p/");
        let b64: String = url::form_urlencoded::parse(format!("x={enc}").as_bytes())
            .find(|(k, _)| k == "x")
            .unwrap()
            .1
            .into_owned();
        use base64::Engine as _;
        let raw = String::from_utf8(
            base64::engine::general_purpose::STANDARD
                .decode(b64)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            raw,
            r#"{"p":{"u":"https://x/:fl:/p","r":false},"a":"AddToWorkspace"}"#
        );
    }

    #[test]
    fn makes_names_and_links() {
        assert_eq!(file_name("OST TEST 209 notes"), "OST TEST 209 notes.loop");
        assert_eq!(file_name("a/b: c?"), "ab c.loop");
        assert_eq!(file_name(""), "Meeting Notes.loop");
        assert_eq!(
            site_of("https://t-my.sharepoint.com/personal/ost-test1_t_com/Documents").as_deref(),
            Some("https://t-my.sharepoint.com/personal/ost-test1_t_com")
        );
        assert_eq!(
            shared_link(
                "https://t-my.sharepoint.com/:fl:/g/personal/u/abc",
                "https://t-my.sharepoint.com/x.loop?d=w1&nav=cz0lMkY%3D"
            ),
            "https://t-my.sharepoint.com/:fl:/g/personal/u/abc?nav=cz0lMkY%3D"
        );
        assert_eq!(
            create_link_url(
                "https://t-my.sharepoint.com/personal/u_t_com/",
                "b!d",
                "01AB"
            ),
            "https://t-my.sharepoint.com/personal/u_t_com/_api/v2.1/drives/b!d/items/01AB/createLink"
        );
    }
}
