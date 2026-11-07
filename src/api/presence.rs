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
pub fn expiry_for(
    choice: &str,
    now: chrono::DateTime<chrono::Local>,
) -> Option<chrono::DateTime<chrono::Local>> {
    use chrono::{Datelike, Duration, TimeZone};
    let at = |d: chrono::NaiveDate, h, m, s, ms| {
        chrono::Local
            .from_local_datetime(&d.and_hms_milli_opt(h, m, s, ms)?)
            .earliest()
    };
    match choice {
        "HalfHour" => Some(now + Duration::minutes(30)),
        "OneHour" => Some(now + Duration::hours(1)),
        "TwoHours" => Some(now + Duration::hours(2)),
        "FourHours" => Some(now + Duration::hours(4)),
        "Today" => at(now.date_naive(), 23, 59, 59, 999),
        "ThisWeek" => {
            // Weeks start on Sunday; endOfWeek is Saturday, then its start of day.
            let days_to_sat = 6 - now.weekday().num_days_from_sunday() as i64;
            at(now.date_naive() + Duration::days(days_to_sat), 0, 0, 0, 0)
        }
        _ => None,
    }
}

/// Set your status until `until` (Teams' desiredExpirationTime), or
/// reset it with `None`.
pub async fn force_availability_until(
    http: &reqwest::Client,
    availability: Option<&str>,
    until: Option<chrono::DateTime<chrono::Local>>,
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
    let expiry = until.map(|t| {
        t.with_timezone(&chrono::Utc)
            .to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
    });
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
    until: Option<chrono::DateTime<chrono::Local>>,
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
pub fn note_body(
    message: &str,
    pinned: bool,
    until: Option<chrono::DateTime<chrono::Local>>,
) -> serde_json::Value {
    use chrono::TimeZone;
    if message.trim().is_empty() {
        return serde_json::json!({ "message": "" });
    }
    let esc = message
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;");
    let html = format!(
        "<p>{esc}</p>{}",
        if pinned {
            "<pinnednote></pinnednote>"
        } else {
            ""
        }
    );
    let never = chrono::Local
        .with_ymd_and_hms(9999, 12, 31, 0, 0, 0)
        .earliest();
    let expiry = until.or(never).map(|t| {
        t.with_timezone(&chrono::Utc)
            .to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
    });
    serde_json::json!({ "expiry": expiry, "message": html })
}

#[cfg(test)]
mod expiry_tests {
    use super::*;
    use chrono::{Datelike, TimeZone, Timelike};

    #[test]
    fn expiries_are_teams_choices() {
        // A Wednesday afternoon.
        let now = chrono::Local
            .with_ymd_and_hms(2026, 11, 4, 15, 20, 0)
            .unwrap();
        let today = expiry_for("Today", now).unwrap();
        assert_eq!(
            (today.day(), today.hour(), today.minute(), today.second()),
            (4, 23, 59, 59)
        );
        let week = expiry_for("ThisWeek", now).unwrap();
        assert_eq!(
            (week.weekday(), week.day(), week.hour()),
            (chrono::Weekday::Sat, 7, 0)
        );
        assert_eq!(expiry_for("HalfHour", now).unwrap().minute(), 50);
        assert!(expiry_for("Never", now).is_none());
        // Saturday's "This week" is that same day, 00:00.
        let sat = chrono::Local
            .with_ymd_and_hms(2026, 11, 7, 10, 0, 0)
            .unwrap();
        assert_eq!(expiry_for("ThisWeek", sat).unwrap().day(), 7);
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
            Some(UserPresence {
                mri,
                availability: field("availability"),
                activity: field("activity"),
            })
        })
        .collect()
}

#[cfg(test)]
mod presence_tests {
    use super::*;

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
