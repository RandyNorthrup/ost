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
    let notes = v
        .get("resources")
        .and_then(Value::as_array)
        .and_then(|a| a.iter().find(|r| r.get("type").and_then(Value::as_str).is_some_and(|t| t.eq_ignore_ascii_case("notes"))));
    let s = |x: Option<&Value>, k: &str| x.and_then(|r| r.get(k)).and_then(Value::as_str).unwrap_or_default().to_string();
    Reply {
        location: s(notes, "location"),
        state: s(notes, "resourceState").to_ascii_lowercase(),
        expiry: v.get("expiry").and_then(Value::as_str).unwrap_or_default().to_string(),
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
    if m.thread_id.is_empty() || (!m.i_cal_uid.is_empty() && !m.organizer.is_empty() && !m.meeting_title.is_empty()) {
        return;
    }
    match super::chat_meeting(client, &m.thread_id).await {
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
        Err(e) => tracing::info!("meeting notes: the meeting chat's meeting: {e:#}"),
    }
}

/// Get or make the meeting's notes through Teams' meeting-notes service;
/// the notes' link.
pub async fn get_or_create(m: &Meeting) -> Result<String> {
    anyhow::ensure!(!m.thread_id.is_empty() && !m.organizer.is_empty(), "This call isn't a meeting with notes");
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
            tracing::info!("meeting-notes service: HTTP {status}: {}", text.chars().take(600).collect::<String>());
            anyhow::bail!("The meeting-notes service answered {status}");
        }
        let r = parse_reply(&resp.json().await.context("The meeting-notes service's reply")?);
        if !r.location.is_empty() && (r.state == "committed" || r.state.is_empty()) {
            return Ok(r.location);
        }
        if r.state == "pending" && attempt < RETRIES {
            tokio::time::sleep(retry_delay(&r.expiry, chrono::Utc::now())).await;
            continue;
        }
        anyhow::bail!("The meeting-notes service has no notes ({})", if r.state.is_empty() { "no link" } else { r.state.as_str() });
    }
    anyhow::bail!("The meeting-notes service's notes stayed pending")
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
    Some(format!("{}://{}/{}", u.scheme(), u.host_str()?, segs.join("/")))
}

pub async fn meetings_target(client: &TeamsClient) -> Result<Target> {
    let folder: Value = client.graph_get("/me/drive/special/meetings?$select=id,name,parentReference").await?.json().await?;
    let drive: Value = client.graph_get("/me/drive?$select=id,webUrl").await?.json().await?;
    let drive_id = folder.pointer("/parentReference/driveId").and_then(Value::as_str).or_else(|| drive.get("id").and_then(Value::as_str)).unwrap_or_default();
    let name = folder.get("name").and_then(Value::as_str).unwrap_or("Meetings");
    let site = site_of(drive.get("webUrl").and_then(Value::as_str).unwrap_or_default()).context("Your OneDrive")?;
    anyhow::ensure!(!drive_id.is_empty(), "Your OneDrive");
    Ok(Target { site_url: site, drive_id: drive_id.to_string(), file_path: name.to_string() })
}

/// A page's file name as Teams names it: the meeting's title (Teams'
/// "Meeting Notes" without one) with characters a file can't have left
/// out, then `.loop`.
pub fn file_name(title: &str) -> String {
    let clean: String = title.chars().filter(|c| !"\"*:<>?/\\|#%".contains(*c) && !c.is_control()).collect();
    let clean = clean.trim().trim_end_matches('.').to_string();
    format!("{}.loop", if clean.is_empty() { "Meeting Notes".to_string() } else { clean })
}

/// The notes' link Teams shares: the item's organization edit link with
/// the page's `nav` (from the page's own link).
pub fn shared_link(edit_link: &str, page_link: &str) -> String {
    let nav = url::Url::parse(page_link)
        .ok()
        .and_then(|u| u.query_pairs().find(|(k, _)| k == "nav").map(|(_, v)| v.into_owned()));
    match nav {
        Some(n) => {
            let enc: String = url::form_urlencoded::byte_serialize(n.as_bytes()).collect();
            format!("{edit_link}{}nav={enc}", if edit_link.contains('?') { '&' } else { '?' })
        }
        None => edit_link.to_string(),
    }
}

/// The organization edit link of a made page (Teams' createLink).
pub async fn edit_link(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<String> {
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_".contains(c));
    anyhow::ensure!(ok(drive_id) && ok(item_id), "Not a page");
    let v: Value = client
        .graph_post(&format!("/drives/{drive_id}/items/{item_id}/createLink"), &json!({ "type": "edit", "scope": "organization" }))
        .await?
        .json()
        .await?;
    v.pointer("/link/webUrl").and_then(Value::as_str).map(str::to_string).context("The page's link")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asks_as_teams() {
        let m = Meeting { thread_id: "19:meeting_x@thread.v2".into(), organizer: "o@t".into(), meeting_title: "OST TEST".into(),
                          meeting_url: "https://teams.microsoft.com/l/meetup-join/x".into(), i_cal_uid: "040000".into() };
        let b = request_body(&m);
        assert_eq!(b["messageId"], "0");
        assert_eq!(b["externalEntityKey"], "040000");
        assert_eq!(b["organizer"], "o@t");
    }

    #[test]
    fn reads_the_answer() {
        let r = parse_reply(&json!({"resources": [{"type": "Notes", "location": "https://x/:fl:/p", "resourceState": "Committed"}], "expiry": "2026-11-16T23:00:05Z"}));
        assert_eq!(r.location, "https://x/:fl:/p");
        assert_eq!(r.state, "committed");
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-16T23:00:00Z").unwrap().with_timezone(&chrono::Utc);
        assert_eq!(retry_delay("2026-11-16T23:00:05Z", now).as_millis(), 5000);
        assert_eq!(retry_delay("2026-11-16T23:05:00Z", now).as_millis(), 30_000);
        assert_eq!(retry_delay("", now).as_millis(), 5000);
    }

    #[test]
    fn makes_names_and_links() {
        assert_eq!(file_name("OST TEST 209 notes"), "OST TEST 209 notes.loop");
        assert_eq!(file_name("a/b: c?"), "ab c.loop");
        assert_eq!(file_name(""), "Meeting Notes.loop");
        assert_eq!(site_of("https://t-my.sharepoint.com/personal/ost-test1_t_com/Documents").as_deref(), Some("https://t-my.sharepoint.com/personal/ost-test1_t_com"));
        assert_eq!(shared_link("https://t-my.sharepoint.com/:fl:/g/personal/u/abc", "https://t-my.sharepoint.com/x.loop?d=w1&nav=cz0lMkY%3D"),
                   "https://t-my.sharepoint.com/:fl:/g/personal/u/abc?nav=cz0lMkY%3D");
    }
}
