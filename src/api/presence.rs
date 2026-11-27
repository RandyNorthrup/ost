//! Presence API for Microsoft Teams

use anyhow::{Context, Result, bail};
use serde::Deserialize;

use super::client::TeamsClient;

#[derive(Debug, Deserialize)]
struct PresenceResponse {
    availability: String,
    activity: String,
}

/// Get current presence status (prints to stdout).
pub async fn get_presence() -> Result<()> {
    let client = TeamsClient::new().await?;
    let info = get_presence_data(&client).await?;

    println!("\nPresence Status:");
    println!("  Availability: {}", info.availability);
    println!("  Activity: {}", info.activity);

    Ok(())
}

// ---------------------------------------------------------------------------
// Data-returning API functions for TUI integration
// ---------------------------------------------------------------------------

/// Presence info for TUI display.
#[allow(dead_code)]
pub struct PresenceInfo {
    pub availability: String,
    pub activity: String,
}

/// Fetch current presence and return structured data.
pub async fn get_presence_data(client: &TeamsClient) -> Result<PresenceInfo> {
    let resp = client.graph_get("/me/presence").await?;
    let presence: PresenceResponse = resp
        .json()
        .await
        .context("Failed to parse presence response")?;

    Ok(PresenceInfo {
        availability: presence.availability,
        activity: presence.activity,
    })
}

/// Set presence status
pub async fn set_presence(status: &str) -> Result<()> {
    let (availability, activity) = match status.to_lowercase().as_str() {
        "available" => ("Available", "Available"),
        "busy" => ("Busy", "InACall"),
        "dnd" | "donotdisturb" => ("DoNotDisturb", "Presenting"),
        "away" => ("Away", "Away"),
        "offline" => ("Offline", "OffWork"),
        other => bail!(
            "Unknown status: {}. Use: available, busy, dnd, away, offline",
            other
        ),
    };

    let client = TeamsClient::new().await?;
    let body = serde_json::json!({
        "sessionId": "teams-cli",
        "availability": availability,
        "activity": activity,
        "expirationDuration": "PT1H"
    });

    client
        .graph_post("/me/presence/setUserPreferredPresence", &body)
        .await?;

    println!("Presence set to: {}", status);
    Ok(())
}

/// Presence service audience and front door.
const PRESENCE_SCOPE: &str = "https://presence.teams.microsoft.com/.default";
const PRESENCE_URL: &str = "https://presence.teams.microsoft.com";

/// Set your status as Teams' profile menu does ("Available", "Busy",
/// "DoNotDisturb", "BeRightBack", "Away", "Offline"), or `None` to reset it
/// to what your activity says (PUT …/v1/me/forceavailability/).
pub async fn force_availability(http: &reqwest::Client, availability: Option<&str>) -> Result<()> {
    force_availability_until(http, availability, None).await
}

/// Teams' expiry choices (worker module 49107 `Rn`), from local time `now`:
/// HalfHour, OneHour, TwoHours, FourHours, Today (23:59:59.999), ThisWeek
/// (the Saturday of this week, 00:00), or Never (none).
pub fn expiry_for(choice: &str, now: &jiff::ZonedDateTime) -> Option<jiff::ZonedDateTime> {
    use jiff::SignedDuration;
    let at = |d: jiff::civil::Date, h, m, s, ms: i32| {
        crate::clock::earliest(now.time_zone(), d.at(h, m, s, ms * 1_000_000))
    };
    match choice {
        "HalfHour" => Some(now + SignedDuration::from_mins(30)),
        "OneHour" => Some(now + SignedDuration::from_hours(1)),
        "TwoHours" => Some(now + SignedDuration::from_hours(2)),
        "FourHours" => Some(now + SignedDuration::from_hours(4)),
        "Today" => at(now.date(), 23, 59, 59, 999),
        "ThisWeek" => {
            // Weeks start on Sunday; endOfWeek is Saturday, then its start of day.
            let days_to_sat = 6 - i64::from(now.weekday().to_sunday_zero_offset());
            at(crate::clock::add_days(now.date(), days_to_sat), 0, 0, 0, 0)
        }
        _ => None,
    }
}

/// Set your status until `until` (Teams' desiredExpirationTime), or
/// reset it with `None`.
pub async fn force_availability_until(
    http: &reqwest::Client,
    availability: Option<&str>,
    until: Option<jiff::ZonedDateTime>,
) -> Result<()> {
    if let Some(a) = availability
        && ![
            "Available",
            "Busy",
            "DoNotDisturb",
            "BeRightBack",
            "Away",
            "Offline",
        ]
        .contains(&a)
    {
        bail!("Unknown status: {a}");
    }
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let mut req = http
        .put(format!("{PRESENCE_URL}/v1/me/forceavailability/"))
        .bearer_auth(token);
    // Teams sends "activity":"OffWork" with Offline (its check rejects
    // Offline without it).
    let expiry = until.map(|t| crate::clock::iso_ms(t.timestamp()));
    req = match availability {
        Some(a) => {
            let mut body = serde_json::json!({ "availability": a });
            if a == "Offline" {
                body["activity"] = "OffWork".into();
            }
            if let Some(e) = &expiry {
                body["desiredExpirationTime"] = e.clone().into();
            }
            req.json(&body)
        }
        None => req.header("Content-Length", "0"),
    };
    let resp = req.send().await.context("Status request failed")?;
    if !resp.status().is_success() {
        bail!("Setting status failed: HTTP {}", resp.status().as_u16());
    }
    Ok(())
}

/// Set where you work today, as Teams' Set work location does (presence
/// service `PUT v1/me/workLocation/`, captured on winpc 2026-11-10):
/// Office `{"location":1,"expirationTime":<end of today>}`, Remote 2, and
/// clearing `{"location":0}`.
pub async fn set_work_location(http: &reqwest::Client, location: Option<&str>) -> Result<()> {
    let body = work_location_body(location, &crate::clock::local_now())?;
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let resp = http
        .put(format!("{PRESENCE_URL}/v1/me/workLocation/"))
        .bearer_auth(token)
        .json(&body)
        .send()
        .await
        .context("Work location request failed")?;
    if !resp.status().is_success() {
        bail!(
            "Setting work location failed: HTTP {}",
            resp.status().as_u16()
        );
    }
    Ok(())
}

/// Teams' work location body: the location's number (Office 1, Remote 2;
/// none 0) and, when set, the end of today (23:59:59.999 local) in UTC.
pub fn work_location_body(
    location: Option<&str>,
    now: &jiff::ZonedDateTime,
) -> Result<serde_json::Value> {
    let n = match location {
        None => return Ok(serde_json::json!({ "location": 0 })),
        Some("Office") => 1,
        Some("Remote") => 2,
        Some(other) => bail!("Unknown work location: {other}"),
    };
    let end = expiry_for("Today", now).context("No end of today")?;
    Ok(serde_json::json!({
        "location": n,
        "expirationTime": crate::clock::iso_ms(end.timestamp()),
    }))
}

/// What this endpoint is doing, as Teams' calling client state reports it
/// (apps-calling module 361789): not in a call, in a call, or presenting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum CallState {
    NotInCall = 0,
    InCall = 1,
    Presenting = 2,
}

/// Teams' presence state for this endpoint (docs/spec/presence.md): the
/// Trouter epid, whether the machine is locked, the call state, and when
/// a publish last succeeded. Changes reach the Trouter loop through
/// `changes()`.
#[derive(Debug, Clone, PartialEq)]
pub struct EndpointState {
    pub epid: Option<String>,
    pub locked: bool,
    pub call: CallState,
}

fn state() -> &'static tokio::sync::watch::Sender<EndpointState> {
    static S: std::sync::OnceLock<tokio::sync::watch::Sender<EndpointState>> =
        std::sync::OnceLock::new();
    S.get_or_init(|| {
        tokio::sync::watch::channel(EndpointState {
            epid: None,
            locked: false,
            call: CallState::NotInCall,
        })
        .0
    })
}

/// Watch this endpoint's presence state (the Trouter loop sends
/// `user.activity` when `locked` changes).
pub fn changes() -> tokio::sync::watch::Receiver<EndpointState> {
    state().subscribe()
}

fn last_success() -> &'static std::sync::Mutex<Option<std::time::Instant>> {
    static T: std::sync::OnceLock<std::sync::Mutex<Option<std::time::Instant>>> =
        std::sync::OnceLock::new();
    T.get_or_init(Default::default)
}

/// The machine was locked or unlocked (logind), as Teams' host reports it.
pub fn set_machine_locked(locked: bool) {
    state().send_if_modified(|s| std::mem::replace(&mut s.locked, locked) != locked);
}

/// The pair Teams publishes for a state (worker module 67431 `rU`): the
/// call state first, then the machine; none when locked (BeRightBack is
/// never sent).
pub fn endpoint_pair(s: &EndpointState) -> Option<(&'static str, &'static str)> {
    match s.call {
        CallState::InCall => Some(("Busy", "InACall")),
        CallState::Presenting => Some(("DoNotDisturb", "Presenting")),
        CallState::NotInCall if s.locked => None,
        CallState::NotInCall => Some(("Available", "Available")),
    }
}

/// The call state changed: publish it at once, as Teams'
/// publishPresenceWithCallState does (a repeat is skipped; ending a call
/// publishes Available even when locked).
pub async fn set_call_state(http: &reqwest::Client, call: CallState) {
    let changed = state().send_if_modified(|s| std::mem::replace(&mut s.call, call) != call);
    let epid = state().borrow().epid.clone();
    let (Some(epid), true) = (epid, changed) else {
        return;
    };
    let (availability, activity) = match call {
        CallState::InCall => ("Busy", "InACall"),
        CallState::Presenting => ("DoNotDisturb", "Presenting"),
        CallState::NotInCall => ("Available", "Available"),
    };
    // Teams' call-state publish key order: availability, activity, id, …
    let body = format!(
        r#"{{"availability":"{availability}","activity":"{activity}","id":{},"activityReporting":"Transport","deviceType":"Desktop"}}"#,
        serde_json::Value::from(epid.as_str())
    );
    if let Err(e) = put_endpoint(http, &epid, body, "calling-state-changed").await {
        tracing::warn!("call-state presence publish failed: {e:#}");
    }
}

/// Teams' presence request headers (services_i module 93846 `D`).
fn headers(
    req: reqwest::RequestBuilder,
    epid: Option<&str>,
    caller: &str,
) -> reqwest::RequestBuilder {
    let mut req = req
        .header("x-ms-client-user-agent", "Teams-V2-Desktop")
        .header("x-ms-client-caller", caller)
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .header("Content-Type", "application/json");
    if let Some(e) = epid {
        req = req.header("x-ms-endpoint-id", e);
    }
    req
}

async fn put_endpoint(
    http: &reqwest::Client,
    epid: &str,
    body: String,
    caller: &str,
) -> Result<()> {
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let resp = headers(
        http.put(format!("{PRESENCE_URL}/v1/me/endpoints/")),
        Some(epid),
        caller,
    )
    .bearer_auth(&token)
    .body(body)
    .send()
    .await
    .context("Presence endpoint PUT failed to send")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Presence endpoint PUT failed: HTTP {status}");
    }
    *last_success().lock().unwrap() = Some(std::time::Instant::now());
    Ok(())
}

/// Trouter connected with endpoint `epid`: create the presence endpoint
/// as Teams does (onTrouterConnected): only for a new epid, or when the
/// last success was 240 s or more ago; never while locked (the pair would
/// be BeRightBack, which Teams doesn't send).
pub async fn publish_endpoint(http: &reqwest::Client, epid: &str) -> Result<()> {
    let new_epid = state().borrow().epid.as_deref() != Some(epid);
    state().send_modify(|s| s.epid = Some(epid.to_string()));
    let recent = last_success()
        .lock()
        .unwrap()
        .is_some_and(|t| t.elapsed() < std::time::Duration::from_secs(240));
    if !new_epid && recent {
        return Ok(());
    }
    let s = state().borrow().clone();
    let Some((availability, activity)) = endpoint_pair(&s) else {
        return Ok(());
    };
    // Teams' create key order: id, availability, activity, activityReporting, deviceType.
    let body = format!(
        r#"{{"id":{},"availability":"{availability}","activity":"{activity}","activityReporting":"Transport","deviceType":"Desktop"}}"#,
        serde_json::Value::from(epid)
    );
    put_endpoint(
        http,
        epid,
        body,
        "presence-sync-strategy:TrouterStateChanged",
    )
    .await?;
    tracing::debug!("Presence endpoint published");
    Ok(())
}

/// A state change (unlock): publish the current pair at once, as Teams'
/// debounced state-change publish does; nothing while locked.
pub async fn publish_state(http: &reqwest::Client) -> Result<()> {
    let s = state().borrow().clone();
    let (Some(epid), Some((availability, activity))) = (s.epid.clone(), endpoint_pair(&s)) else {
        return Ok(());
    };
    // Teams' state-change key order: id, activity, availability, …
    let body = format!(
        r#"{{"id":{},"activity":"{activity}","availability":"{availability}","activityReporting":"Transport","deviceType":"Desktop"}}"#,
        serde_json::Value::from(epid.as_str())
    );
    put_endpoint(http, &epid, body, "presence-sync-strategy:AppStateChanged").await
}

/// Teams' hourly heartbeat: POST v1/me/reportmyactivity/ {endpointId,
/// isActive}, isActive = the machine is unlocked (skipped while locked).
pub async fn heartbeat(http: &reqwest::Client) -> Result<()> {
    let s = state().borrow().clone();
    let Some(epid) = s.epid.filter(|_| !s.locked) else {
        return Ok(());
    };
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let resp = headers(
        http.post(format!("{PRESENCE_URL}/v1/me/reportmyactivity/")),
        Some(&epid),
        "presence-heartbeat",
    )
    .bearer_auth(&token)
    .body(serde_json::json!({ "endpointId": epid, "isActive": true }).to_string())
    .send()
    .await
    .context("Presence heartbeat failed to send")?;
    if resp.status() == reqwest::StatusCode::NOT_FOUND {
        // Teams re-creates the endpoint after a 404.
        *last_success().lock().unwrap() = None;
        return publish_endpoint(http, &epid).await;
    }
    if !resp.status().is_success() {
        bail!("Presence heartbeat failed: HTTP {}", resp.status());
    }
    Ok(())
}

/// Sign-out: remove this endpoint (DELETE v1/me/endpoints/{epid}).
pub async fn delete_endpoint(http: &reqwest::Client) -> Result<()> {
    let Some(epid) = state().borrow().epid.clone() else {
        return Ok(());
    };
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let enc: String = url::form_urlencoded::byte_serialize(epid.as_bytes()).collect();
    headers(
        http.delete(format!("{PRESENCE_URL}/v1/me/endpoints/{enc}")),
        Some(&epid),
        "sign-out",
    )
    .bearer_auth(&token)
    .send()
    .await
    .context("Presence endpoint DELETE failed to send")?;
    Ok(())
}

#[cfg(test)]
mod endpoint_tests {
    use super::*;

    #[test]
    fn pairs_are_the_three_teams_publishes() {
        let s = |call, locked| EndpointState {
            epid: None,
            locked,
            call,
        };
        assert_eq!(
            endpoint_pair(&s(CallState::NotInCall, false)),
            Some(("Available", "Available"))
        );
        assert_eq!(endpoint_pair(&s(CallState::NotInCall, true)), None);
        assert_eq!(
            endpoint_pair(&s(CallState::InCall, true)),
            Some(("Busy", "InACall"))
        );
        assert_eq!(
            endpoint_pair(&s(CallState::Presenting, false)),
            Some(("DoNotDisturb", "Presenting"))
        );
    }
}

/// Set your status message (Teams' setStatusNote: PUT v1/me/publishnote
/// {expiry, message}). `pinned` is "Show when people message me", kept in
/// the message as a trailing `<pinnednote></pinnednote>`; an empty message
/// clears it.
pub async fn publish_note(
    http: &reqwest::Client,
    message: &str,
    pinned: bool,
    until: Option<jiff::ZonedDateTime>,
) -> Result<()> {
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let body = note_body(message, pinned, until);
    let resp = headers(
        http.put(format!("{PRESENCE_URL}/v1/me/publishnote")),
        None,
        "set-status-note",
    )
    .bearer_auth(&token)
    .body(body.to_string())
    .send()
    .await
    .context("Status note request failed")?;
    if !resp.status().is_success() {
        bail!(
            "Setting the status message failed: HTTP {}",
            resp.status().as_u16()
        );
    }
    Ok(())
}

/// The publishnote body: `{"message": ""}` to clear; else the text in a
/// paragraph (escaped), the pinned marker, and the expiry (Never is
/// 9999-12-31 local, which Teams sends for notes).
/// The status editor's text as Teams' note HTML: one paragraph, each
/// mention (picked as one token per word) a single span with the person's
/// whole name and its `data-itemprops`, as Teams sends it (captured on
/// winpc, 2026-11-09: `<span itemtype=".../Mention" itemscope itemid="0"
/// data-itemprops="{&quot;mri&quot;:…,&quot;mentionType&quot;:&quot;person&quot;}">OST Test 1</span>`).
pub fn note_html(editor_html: &str) -> String {
    let (html, mentions) = super::messages::teams_html_and_mentions(editor_html);
    // Spans of the same person next to each other (words joined by
    // &nbsp; or a space) become one.
    let open = |i: usize| {
        format!("<span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"\" itemid=\"{i}\">")
    };
    let mut out = String::new();
    let mut rest = html.as_str();
    let mut next = 0;
    let mut i = 0;
    while i < mentions.len() {
        let tag = open(i);
        let Some(at) = rest.find(&tag) else { break };
        out.push_str(&rest[..at]);
        let mut name = String::new();
        let mut j = i;
        let mut after = &rest[at..];
        loop {
            let t = open(j);
            let body = &after[t.len()..];
            // Its closing tag (Qt's editor nests a styled span inside).
            let mut depth = 0;
            let mut end = body.len();
            let mut k = 0;
            while let Some(lt) = body[k..].find('<') {
                let at = k + lt;
                if body[at..].starts_with("</span>") {
                    if depth == 0 {
                        end = at;
                        break;
                    }
                    depth -= 1;
                } else if body[at..].starts_with("<span") {
                    depth += 1;
                }
                k = at + 1;
            }
            if !name.is_empty() {
                name.push(' ');
            }
            name.push_str(super::strip_html(&body[..end]).trim());
            after = &body[(end + "</span>".len()).min(body.len())..];
            let sep = ["&nbsp;", "\u{a0}", " "]
                .iter()
                .find(|s| after.starts_with(*s));
            match (sep, mentions.get(j + 1)) {
                (Some(sep), Some(m))
                    if m.mri == mentions[i].mri && after[sep.len()..].starts_with(&open(j + 1)) =>
                {
                    after = &after[sep.len()..];
                    j += 1;
                }
                _ => break,
            }
        }
        let props = format!(
            "{{&quot;mri&quot;:&quot;{}&quot;,&quot;mentionType&quot;:&quot;person&quot;}}",
            mentions[i].mri
        );
        out.push_str(&format!(
            "<span itemtype=\"http://schema.skype.com/Mention\" itemscope itemid=\"{next}\" data-itemprops=\"{props}\">{name}</span>"
        ));
        next += 1;
        rest = after;
        i = j + 1;
    }
    out.push_str(rest);
    // One paragraph, as Teams' note editor keeps it.
    let inner = out
        .replace("</p><p>", " ")
        .replace("<p>", "")
        .replace("</p>", "");
    format!("<p>{}</p>", inner.trim())
}

/// The note HTML for editor HTML or plain text.
pub fn note_html_any(message: &str) -> String {
    if message.trim_start().starts_with('<') {
        note_html(message)
    } else {
        format!(
            "<p>{}</p>",
            message
                .replace('&', "&amp;")
                .replace('<', "&lt;")
                .replace('>', "&gt;")
        )
    }
}

/// The note's plain text (what the profile shows while editing).
pub fn note_plain(editor_html: &str) -> String {
    if editor_html.trim_start().starts_with('<') {
        super::strip_html(&note_html(editor_html))
            .trim()
            .to_string()
    } else {
        editor_html.to_string()
    }
}

pub fn note_body(
    message: &str,
    pinned: bool,
    until: Option<jiff::ZonedDateTime>,
) -> serde_json::Value {
    if message.trim().is_empty() {
        return serde_json::json!({ "message": "" });
    }
    // The status editor's rich text (with mention tokens), or plain text.
    let para = if message.trim_start().starts_with('<') {
        note_html(message)
    } else {
        let esc = message
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;");
        format!("<p>{esc}</p>")
    };
    let html = format!(
        "{para}{}",
        if pinned {
            "<pinnednote></pinnednote>"
        } else {
            ""
        }
    );
    let expiry = match until {
        Some(t) => Some(crate::clock::iso_ms(t.timestamp())),
        None => never_expiry(&crate::clock::local_zone()),
    };
    serde_json::json!({ "expiry": expiry, "message": html })
}

/// A note that doesn't expire: 9999-12-31 00:00 local, in UTC (past the
/// last moment jiff holds, so worked out on the wall clock).
fn never_expiry(tz: &jiff::tz::TimeZone) -> Option<String> {
    use jiff::tz::AmbiguousOffset;
    let wall = jiff::civil::datetime(9999, 12, 31, 0, 0, 0, 0);
    let offset = match tz.to_ambiguous_timestamp(wall).offset() {
        AmbiguousOffset::Unambiguous { offset } | AmbiguousOffset::Fold { before: offset, .. } => {
            offset
        }
        AmbiguousOffset::Gap { .. } => return None,
    };
    let utc = wall
        .checked_sub(jiff::SignedDuration::from_secs(i64::from(offset.seconds())))
        .ok()?;
    Some(crate::clock::format(utc, "%Y-%m-%dT%H:%M:%S%.3fZ"))
}

#[cfg(test)]
mod expiry_tests {
    use super::*;

    #[test]
    fn work_location_bodies_are_teams() {
        let now = &local(2026, 11, 10, 9, 0);
        assert_eq!(
            work_location_body(None, now).unwrap(),
            serde_json::json!({ "location": 0 })
        );
        let office = work_location_body(Some("Office"), now).unwrap();
        assert_eq!(office["location"], 1);
        let end = crate::clock::local(
            crate::clock::parse_instant(office["expirationTime"].as_str().unwrap()).unwrap(),
        );
        assert_eq!(
            (end.date(), crate::clock::format(&end, "%H:%M:%S%.3f")),
            (now.date(), "23:59:59.999".to_string())
        );
        assert_eq!(
            work_location_body(Some("Remote"), now).unwrap()["location"],
            2
        );
        assert!(work_location_body(Some("Moon"), now).is_err());
    }
    fn local(y: i16, m: i8, d: i8, h: i8, mi: i8) -> jiff::ZonedDateTime {
        crate::clock::local_single(jiff::civil::datetime(y, m, d, h, mi, 0, 0)).unwrap()
    }

    #[test]
    fn expiries_are_teams_choices() {
        // A Wednesday afternoon.
        let now = &local(2026, 11, 4, 15, 20);
        let today = expiry_for("Today", now).unwrap();
        assert_eq!(
            (today.day(), today.hour(), today.minute(), today.second()),
            (4, 23, 59, 59)
        );
        let week = expiry_for("ThisWeek", now).unwrap();
        assert_eq!(
            (week.weekday(), week.day(), week.hour()),
            (jiff::civil::Weekday::Saturday, 7, 0)
        );
        assert_eq!(expiry_for("HalfHour", now).unwrap().minute(), 50);
        assert!(expiry_for("Never", now).is_none());
        // Saturday's "This week" is that same day, 00:00.
        let sat = &local(2026, 11, 7, 10, 0);
        assert_eq!(expiry_for("ThisWeek", sat).unwrap().day(), 7);
    }

    #[test]
    fn expiries_in_a_dst_zone() {
        let tz = jiff::tz::TimeZone::posix("EST5EDT,M3.2.0,M11.1.0").unwrap();
        let at = |mo, d, h, mi| {
            crate::clock::single(&tz, jiff::civil::datetime(2026, mo, d, h, mi, 0, 0)).unwrap()
        };
        let iso = |t: Option<jiff::ZonedDateTime>| crate::clock::iso_ms(t.unwrap().timestamp());
        // Sunday November 1, 00:30 daylight time: the day ends in standard
        // time, four hours are four real hours.
        let now = &at(11, 1, 0, 30);
        assert_eq!(iso(expiry_for("Today", now)), "2026-11-02T04:59:59.999Z");
        assert_eq!(
            iso(expiry_for("FourHours", now)),
            "2026-11-01T08:30:00.000Z"
        );
        assert_eq!(iso(expiry_for("ThisWeek", now)), "2026-11-07T05:00:00.000Z");
        assert_eq!(
            work_location_body(Some("Office"), now).unwrap()["expirationTime"],
            "2026-11-02T04:59:59.999Z"
        );
        // Saturday March 7: the week ends that day, before the change.
        let now = &at(3, 7, 22, 0);
        assert_eq!(iso(expiry_for("ThisWeek", now)), "2026-03-07T05:00:00.000Z");
        assert_eq!(iso(expiry_for("TwoHours", now)), "2026-03-08T05:00:00.000Z");
        // A repeated hour reads at daylight time, the first time round, as
        // Teams reads it.
        let early = &at(11, 1, 0, 30);
        assert_eq!(
            iso(crate::clock::earliest(&tz, early.date().at(1, 30, 0, 0))),
            "2026-11-01T05:30:00.000Z"
        );
        // Where clocks go back at midnight (Chile: Sunday April 5, 00:00
        // back to Saturday 23:00), Saturday's end comes twice; Teams'
        // "Today" ends at the first, in daylight time.
        let chile = jiff::tz::TimeZone::posix("<-04>4<-03>,M9.1.0/0,M4.1.0/0").unwrap();
        let sat =
            &crate::clock::single(&chile, jiff::civil::datetime(2026, 4, 4, 12, 0, 0, 0)).unwrap();
        assert_eq!(iso(expiry_for("Today", sat)), "2026-04-05T02:59:59.999Z");
        // A note without an end: 9999-12-31 00:00 on the zone's clock.
        assert_eq!(
            never_expiry(&tz).as_deref(),
            Some("9999-12-31T05:00:00.000Z")
        );
        let sydney = jiff::tz::TimeZone::posix("AEST-10AEDT,M10.1.0,M4.1.0/3").unwrap();
        assert_eq!(
            never_expiry(&sydney).as_deref(),
            Some("9999-12-30T13:00:00.000Z")
        );
        assert_eq!(
            never_expiry(&jiff::tz::TimeZone::UTC).as_deref(),
            Some("9999-12-31T00:00:00.000Z")
        );
    }

    #[test]
    fn expiries_keep_wall_times_across_dst_changes() {
        // The US and EU change days: "Today" still ends at 23:59:59.999
        // local, "This week" on Saturday 00:00 local, and the hours are
        // real hours.
        for (m, d) in [(3, 8), (3, 29), (10, 25), (11, 1), (3, 7), (10, 31)] {
            let now = crate::clock::local_earliest(jiff::civil::datetime(2026, m, d, 1, 30, 0, 0));
            let now = &now.unwrap_or_else(|| local(2026, m, d, 12, 0));
            let today = expiry_for("Today", now).unwrap();
            assert_eq!(today.datetime(), now.date().at(23, 59, 59, 999_000_000));
            assert_eq!(
                expiry_for("HalfHour", now)
                    .unwrap()
                    .duration_since(now)
                    .as_secs(),
                1800
            );
            assert_eq!(
                expiry_for("FourHours", now)
                    .unwrap()
                    .duration_since(now)
                    .as_secs(),
                14_400
            );
            let week = expiry_for("ThisWeek", now).unwrap();
            assert_eq!(
                (week.weekday(), week.hour(), week.minute()),
                (jiff::civil::Weekday::Saturday, 0, 0)
            );
            assert!(week.date() >= now.date());
        }
        let until =
            crate::clock::local(crate::clock::parse_instant("2026-11-20T17:00:00+01:00").unwrap());
        assert_eq!(
            note_body("Hi", false, Some(until))["expiry"],
            "2026-11-20T16:00:00.000Z"
        );
    }

    #[test]
    fn notes_with_mentions_are_teams_bodies() {
        // OST's editor: one token per word, as the compose box makes them.
        let editor = r#"<p>OST status mention <a href="mention:8:orgid:4287e791-1b98-4963-8b94-281c50472683">OST</a>&nbsp;<a href="mention:8:orgid:4287e791-1b98-4963-8b94-281c50472683">Test</a>&nbsp;<a href="mention:8:orgid:4287e791-1b98-4963-8b94-281c50472683">1</a></p>"#;
        // Teams' own request (winpc, 2026-11-09).
        assert_eq!(
            note_html(editor),
            r#"<p>OST status mention <span itemtype="http://schema.skype.com/Mention" itemscope itemid="0" data-itemprops="{&quot;mri&quot;:&quot;8:orgid:4287e791-1b98-4963-8b94-281c50472683&quot;,&quot;mentionType&quot;:&quot;person&quot;}">OST Test 1</span></p>"#
        );
        assert_eq!(note_plain(editor), "OST status mention OST Test 1");
        assert_eq!(note_html("<p>a &amp; b</p>"), "<p>a &amp; b</p>");
        // Qt's TextEdit document (logged from the editor): each word's
        // link wraps a styled span, words joined by a raw U+00A0.
        let doc = r#"<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd">
<html><head><meta name="qrichtext" content="1" /><meta charset="utf-8" /><style type="text/css">
p, li { white-space: pre-wrap; }
</style></head><body style=" font-family:'Selawik'; font-size:14px; font-weight:400; font-style:normal;">
<p style=" margin-top:0px; margin-bottom:0px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;">OST status mention <a href="mention:8:orgid:4287e791-1b98-4963-8b94-281c50472683"><span style=" color:#4f52b2;">OST</span></a> <a href="mention:8:orgid:4287e791-1b98-4963-8b94-281c50472683"><span style=" color:#4f52b2;">Test</span></a> <a href="mention:8:orgid:4287e791-1b98-4963-8b94-281c50472683"><span style=" color:#4f52b2;">1</span></a> </p></body></html>"#;
        assert_eq!(note_html(doc), note_html(editor));
        // What the profile flyout shows: one mention.
        assert_eq!(
            crate::api::messages::sanitize_html_marking(&note_html(editor), &[]),
            r#"<p>OST status mention <span class="mention">OST Test 1</span></p>"#
        );
    }

    #[test]
    fn notes_are_teams_bodies() {
        assert_eq!(
            note_body("  ", true, None),
            serde_json::json!({ "message": "" })
        );
        let b = note_body("Out <today>", true, None);
        assert_eq!(
            b["message"],
            "<p>Out &lt;today&gt;</p><pinnednote></pinnednote>"
        );
        assert!(b["expiry"].as_str().unwrap().starts_with("9999-12-3"));
    }
}

/// Someone's presence as the presence service reports it.
#[derive(Debug, Clone, serde::Serialize)]
pub struct UserPresence {
    pub mri: String,
    /// Available, Busy, DoNotDisturb, BeRightBack, Away, Offline, …
    pub availability: String,
    pub activity: String,
    /// The status message for display: Teams' note HTML made safe, its
    /// mentions as `<span class="mention">` (empty when none).
    pub note_html: String,
    /// The same as plain text.
    pub note_text: String,
    /// "Show when people message me" (`<pinnednote>`).
    pub note_pinned: bool,
    /// When the status message is cleared (`note.expiry`, ISO; Never is
    /// year 9999), or "".
    pub note_expiry: String,
    /// When a status you set yourself ends (`forcedAvailability.expiry`,
    /// ISO UTC; only your own), or "" when it doesn't.
    pub forced_until: String,
    /// Where they work today (`workLocation.location`: "Office", "Remote"
    /// or "TimeOff"), or "".
    pub work_location: String,
    /// How it was set (`workLocation.locationSource`): "VerifiedLocation"
    /// (workplace check-in), "ForcedLocation" (set by hand),
    /// "ScheduledLocation" (the work plan), or "".
    pub work_location_source: String,
    /// The building it names (`workLocation.approximateDetails.name`), or "".
    pub work_location_building: String,
    /// That building's Places id (`approximateDetails.id`), or "".
    pub work_location_building_id: String,
    /// When they were last active (`lastActiveTime`, ISO), or "".
    pub last_active: String,
    /// Out of office (`calendarData.isOutOfOffice`).
    pub out_of_office: bool,
}

/// Look up several users' presence by MRI (`8:orgid:<oid>`).
pub async fn get_presences(http: &reqwest::Client, mris: &[String]) -> Result<Vec<UserPresence>> {
    if mris.is_empty() {
        return Ok(Vec::new());
    }
    let token = crate::auth::oauth::access_token_for(PRESENCE_SCOPE).await?;
    let body: Vec<serde_json::Value> = mris
        .iter()
        .map(|m| serde_json::json!({ "mri": m }))
        .collect();
    let resp = http
        .post(format!("{PRESENCE_URL}/v1/presence/getpresence/"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await
        .context("Presence lookup failed to send")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Presence lookup failed: HTTP {status}");
    }
    let v: serde_json::Value = resp.json().await.context("Presence lookup reply")?;
    Ok(parse_presences(&v))
}

fn parse_presences(v: &serde_json::Value) -> Vec<UserPresence> {
    v.as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let mri = e.get("mri")?.as_str()?.to_string();
            let p = e.get("presence").unwrap_or(e);
            let field = |k: &str| {
                p.get(k)
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string()
            };
            let message = p
                .pointer("/note/message")
                .and_then(|m| m.as_str())
                .unwrap_or_default();
            let pinned = message.contains("<pinnednote>");
            let body = message.replace("<pinnednote></pinnednote>", "");
            Some(UserPresence {
                mri,
                availability: field("availability"),
                activity: field("activity"),
                note_html: if body.trim().is_empty() {
                    String::new()
                } else {
                    super::messages::sanitize_html_marking(&body, &[])
                },
                note_text: super::strip_html(&body).trim().to_string(),
                note_pinned: pinned,
                note_expiry: p
                    .pointer("/note/expiry")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string(),
                forced_until: p
                    .pointer("/forcedAvailability/expiry")
                    .and_then(|x| x.as_str())
                    .filter(|_| p.pointer("/forcedAvailability/availability").is_some())
                    .unwrap_or_default()
                    .to_string(),
                last_active: p
                    .get("lastActiveTime")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string(),
                out_of_office: p
                    .pointer("/calendarData/isOutOfOffice")
                    .and_then(|x| x.as_bool())
                    .unwrap_or(false),
                work_location: p
                    .pointer("/workLocation/location")
                    .and_then(|x| x.as_str())
                    .filter(|l| *l != "Unknown")
                    .unwrap_or_default()
                    .to_string(),
                work_location_source: p
                    .pointer("/workLocation/locationSource")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string(),
                work_location_building: p
                    .pointer("/workLocation/approximateDetails/name")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string(),
                work_location_building_id: p
                    .pointer("/workLocation/approximateDetails/id")
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string(),
            })
        })
        .collect()
}

#[cfg(test)]
mod presence_tests {
    use super::*;

    #[test]
    fn reads_status_notes_with_mentions() {
        // The service's reply after OST set a note (2026-11-09).
        let v = serde_json::json!([{"mri": "8:orgid:a", "presence": {"availability": "Available", "activity": "Available",
            "note": {"expiry": "9999-12-31T08:00:00Z", "message": "<p>OST probe <span itemtype=\"http://schema.skype.com/Mention\" itemscope=\"\" itemid=\"0\" data-itemprops=\"{&quot;mri&quot;:&quot;8:orgid:a&quot;,&quot;mentionType&quot;:&quot;person&quot;}\">OST Test 1</span></p><pinnednote></pinnednote>"}}}]);
        let p = &parse_presences(&v)[0];
        assert!(p.note_pinned);
        assert_eq!(p.note_text, "OST probe OST Test 1");
        assert!(
            p.note_html.contains("class=\"mention\"") && p.note_html.contains("OST Test 1"),
            "{}",
            p.note_html
        );
    }

    #[test]
    fn reads_checked_in_work_locations() {
        // Workplace check-in's shape (Teams' getWorkLocationFrom): Office,
        // VerifiedLocation, the building in approximateDetails.
        let v = serde_json::json!([{"mri": "8:orgid:a", "presence": {"availability": "Available", "workLocation": {
            "location": "Office", "locationSource": "VerifiedLocation",
            "approximateDetails": {"id": "a93350e7", "idType": "Directory", "name": "OST Test Building"}}}}]);
        let p = &parse_presences(&v)[0];
        assert_eq!(p.work_location, "Office");
        assert_eq!(p.work_location_source, "VerifiedLocation");
        assert_eq!(p.work_location_building, "OST Test Building");
        assert_eq!(p.work_location_building_id, "a93350e7");
        let v = serde_json::json!([{"mri": "8:orgid:a", "presence": {"workLocation": {"location": "Remote"}}}]);
        let p = &parse_presences(&v)[0];
        assert_eq!(
            (
                p.work_location_source.as_str(),
                p.work_location_building.as_str()
            ),
            ("", "")
        );
    }

    #[test]
    fn parses_presence_service_reply() {
        let v = serde_json::json!([
            {"mri": "8:orgid:a", "presence": {"availability": "Available", "activity": "Available"}},
            {"mri": "8:orgid:b", "presence": {"availability": "Busy", "activity": "InACall"}},
            {"nomri": true}
        ]);
        let p = parse_presences(&v);
        assert_eq!(p.len(), 2);
        assert_eq!(p[1].availability, "Busy");
        assert_eq!(p[1].activity, "InACall");
    }
}
