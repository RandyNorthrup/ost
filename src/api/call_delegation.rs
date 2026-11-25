//! Settings ▸ Calls for Teams Phone users, beyond forwarding (Teams 26304,
//! captured on winpc 2026-11-21):
//!
//! - Manage delegates: `POST {mt}/beta/usersettings/{mri}/delegate`
//!   `{userMri, isActive, allowedActions, createdDate}`, `PATCH
//!   …/delegate/{delegateMri}` `{isActive, allowedActions}`, `DELETE
//!   …/delegate/{delegateMri}` and `PATCH …/delegationWarningTone`
//!   `{playWarningTone}`. Read from the voice admin settings'
//!   `delegationSettings` (`userDelegates.delegates`,
//!   `userDelegators.delegators`).
//! - Intelligent call delegation: `PUT {mt}/beta/usersettings/
//!   personalAttendantSettings` with the whole settings (read from the
//!   voice admin settings' `personalAttendantSettings`); turning it on
//!   the first time also makes your personal Bookings service for
//!   follow-ups (`POST {mt}/beta/personalbookings/bookingsService`), as
//!   Teams' useEnsureBookingCalendar does.

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// Teams' new delegate permissions (delegation_delegate_added_*): all but
/// joining active calls.
pub fn default_allowed_actions() -> Value {
    json!({ "makeCalls": true, "manageSettings": true, "receiveCalls": true, "pickUpHeldCalls": true, "joinActiveCalls": false })
}

/// The permission keys in Teams' order, for the delegate's checkboxes.
pub const ACTIONS: [&str; 5] = [
    "makeCalls",
    "receiveCalls",
    "manageSettings",
    "pickUpHeldCalls",
    "joinActiveCalls",
];

/// The body Teams posts when you add a delegate.
pub fn add_body(delegate_mri: &str, now_iso: &str) -> Value {
    json!({ "userMri": delegate_mri, "isActive": true, "allowedActions": default_allowed_actions(), "createdDate": now_iso })
}

/// A delegate's permissions with one changed (Teams' PATCH body).
pub fn edit_body(current_actions: &Value, action: &str, on: bool) -> Value {
    let mut a = if current_actions.is_object() {
        current_actions.clone()
    } else {
        default_allowed_actions()
    };
    for k in ACTIONS {
        if !a[k].is_boolean() {
            a[k] = default_allowed_actions()[k].clone();
        }
    }
    a[action] = json!(on);
    if let Some(o) = a.as_object_mut() {
        o.retain(|k, _| ACTIONS.contains(&k.as_str()));
    }
    json!({ "isActive": true, "allowedActions": a })
}

/// Your delegates as the voice admin settings list them.
pub fn delegates_of(voice_admin: &Value) -> Vec<Value> {
    voice_admin
        .pointer("/delegationSettings/userDelegates/delegates")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

async fn mt_send(
    client: &TeamsClient,
    method: reqwest::Method,
    path: &str,
    body: Option<&Value>,
) -> Result<Value> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let mut req = client
        .http()
        .request(method, format!("{mt}{path}"))
        .bearer_auth(token);
    if let Some(b) = body {
        req = req.json(b);
    }
    let resp = req.send().await.context("Calls setting request")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!("HTTP {} from {path}", status.as_u16());
    }
    Ok(serde_json::from_str(&text).unwrap_or(Value::Null))
}

fn me(client: &TeamsClient) -> Result<String> {
    Ok(format!(
        "8:orgid:{}",
        client.object_id().context("No user id")?
    ))
}

pub async fn add_delegate(client: &TeamsClient, delegate_mri: &str) -> Result<()> {
    let now = chrono::Utc::now()
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    mt_send(
        client,
        reqwest::Method::POST,
        &format!("/beta/usersettings/{}/delegate", me(client)?),
        Some(&add_body(delegate_mri, &now)),
    )
    .await?;
    Ok(())
}

pub async fn edit_delegate(client: &TeamsClient, delegate_mri: &str, body: &Value) -> Result<()> {
    mt_send(
        client,
        reqwest::Method::PATCH,
        &format!("/beta/usersettings/{}/delegate/{delegate_mri}", me(client)?),
        Some(body),
    )
    .await?;
    Ok(())
}

pub async fn remove_delegate(client: &TeamsClient, delegate_mri: &str) -> Result<()> {
    mt_send(
        client,
        reqwest::Method::DELETE,
        &format!("/beta/usersettings/{}/delegate/{delegate_mri}", me(client)?),
        None,
    )
    .await?;
    Ok(())
}

/// "Announce when delegates join the call".
pub async fn set_warning_tone(client: &TeamsClient, on: bool) -> Result<()> {
    mt_send(
        client,
        reqwest::Method::PATCH,
        &format!("/beta/usersettings/{}/delegationWarningTone", me(client)?),
        Some(&json!({ "playWarningTone": on })),
    )
    .await?;
    Ok(())
}

/// Teams' policy values for intelligent call delegation (module 477210:
/// `tc`, `Ru`): the user may choose, or it's on for them.
pub const POLICY_USER_OVERRIDE: &str = "EnabledUserOverride";
pub const POLICY_ENABLED: &str = "Enabled";

/// The settings Teams PUTs: the read's fields without Apollo's.
pub fn attendant_body(settings: &Value) -> Value {
    let mut o = if settings.is_object() {
        settings.clone()
    } else {
        json!({})
    };
    if let Some(m) = o.as_object_mut() {
        m.remove("__typename");
    }
    o["id"] = json!("personalAttendantSettingsId");
    o
}

pub async fn set_attendant(client: &TeamsClient, settings: &Value) -> Result<Value> {
    mt_send(
        client,
        reqwest::Method::PUT,
        "/beta/usersettings/personalAttendantSettings",
        Some(&attendant_body(settings)),
    )
    .await
}

/// The follow-up booking page Teams makes (its createBookingCalendar with
/// firstTimeSetup, captured): 30 minutes, 1 h lead, 60 days ahead,
/// 15-minute slots, private, online.
pub fn bookings_service_body() -> Value {
    json!({
        "title": "Personal Attendant Followup",
        "defaultDuration": "PT30M",
        "bookingsSchedulingPolicy": { "maximumAdvance": "P60D", "minimumLeadTime": "PT1H", "timeSlotInterval": "PT15M", "sendConfirmationsToOwner": true },
        "isPrivate": true, "isLocationOnline": true, "smsNotificationsEnabled": false,
        "description": "{\"description\":\" Book time to connect with me.\",\"privacyType\":1,\"version\":1}",
    })
}

/// Makes your personal Bookings service: (serviceId, bookingCode).
pub async fn create_bookings_service(
    client: &TeamsClient,
    email: &str,
) -> Result<(String, String)> {
    let path = format!(
        "/beta/personalbookings/bookingsService?email={}&settingsSync=false&provisionMailbox=true",
        url::form_urlencoded::byte_serialize(email.as_bytes()).collect::<String>()
    );
    let v = mt_send(
        client,
        reqwest::Method::POST,
        &path,
        Some(&bookings_service_body()),
    )
    .await?;
    let d = &v["bookingUrlDetails"];
    match (d["serviceId"].as_str(), d["bookingCode"].as_str()) {
        (Some(s), Some(c)) => Ok((s.to_string(), c.to_string())),
        _ => anyhow::bail!("Bookings service reply without its ids"),
    }
}

fn bookings_path(email: &str, service_id: &str, code: &str) -> String {
    format!(
        "/beta/personalbookings/bookingsService?email={}&bookingServiceId={}&bookingCode={}",
        url::form_urlencoded::byte_serialize(email.as_bytes()).collect::<String>(),
        url::form_urlencoded::byte_serialize(service_id.as_bytes()).collect::<String>(),
        url::form_urlencoded::byte_serialize(code.as_bytes()).collect::<String>()
    )
}

/// Follow-ups (Teams' bookingCalendarDetails, worker Y0r/X0r): your
/// follow-up booking page as the service keeps it, read the way Teams
/// reads it (settingsSync=false, provisionMailbox=false), in Teams' shape:
/// title, webUrl (with its booking code), isPrivate, defaultDuration,
/// minimumLeadTime, maximumAdvanceTime, hasCustomServiceWindows and
/// bookingServiceWindows.
pub async fn bookings_service(
    client: &TeamsClient,
    email: &str,
    service_id: &str,
    code: &str,
) -> Result<Value> {
    let path = format!(
        "{}&settingsSync=false&provisionMailbox=false",
        bookings_path(email, service_id, code)
    );
    let v = mt_send(client, reqwest::Method::GET, &path, None).await?;
    Ok(bookings_details(&v))
}

/// Teams' X0r: the service's reply as the Follow-ups page shows it.
pub fn bookings_details(v: &Value) -> Value {
    let p = &v["bookingsSchedulingPolicy"];
    let code = v["bookingUrlCodes"]
        .as_object()
        .and_then(|m| m.keys().next().cloned())
        .unwrap_or_default();
    let web = v["webUrl"].as_str().unwrap_or_default();
    json!({
        "title": v["title"], "isPrivate": v["isPrivate"], "defaultDuration": v["defaultDuration"],
        "webUrl": if web.is_empty() { String::new() } else { format!("{web}?bookingCode={code}") },
        "minimumLeadTime": p["minimumLeadTime"], "maximumAdvanceTime": p["maximumAdvance"], "timeSlotInterval": p["timeSlotInterval"],
        "hasCustomServiceWindows": p["hasCustomServiceWindows"].as_bool().unwrap_or(false),
        "bookingServiceWindows": if p["bookingServiceWindows"].is_array() { p["bookingServiceWindows"].clone() } else { json!([]) },
        "serviceId": v["serviceId"], "bookingCode": code,
    })
}

/// Teams' updateBookingService (worker Z0r): the page's whole scheduling
/// settings in one PUT.
pub fn bookings_update_body(d: &Value) -> Value {
    json!({
        "minimumLeadTime": d["minimumLeadTime"], "maximumAdvance": d["maximumAdvanceTime"], "defaultDuration": d["defaultDuration"],
        "hasCustomServiceWindows": d["hasCustomServiceWindows"].as_bool().unwrap_or(false),
        "bookingServiceWindows": if d["bookingServiceWindows"].is_array() { d["bookingServiceWindows"].clone() } else { json!([]) },
    })
}

pub async fn update_bookings_service(
    client: &TeamsClient,
    email: &str,
    service_id: &str,
    code: &str,
    details: &Value,
) -> Result<()> {
    mt_send(
        client,
        reqwest::Method::PUT,
        &bookings_path(email, service_id, code),
        Some(&bookings_update_body(details)),
    )
    .await?;
    Ok(())
}

/// Teams' turn-on (settings `De`'s Z): with Bookings allowed by the policy
/// and no service yet, the calendar is asked for too.
pub fn wants_bookings(policy: &Value, settings: &Value, on: bool) -> bool {
    let bookings = policy["calendarBookings"].as_str().unwrap_or_default();
    on && (bookings == POLICY_USER_OVERRIDE || bookings == POLICY_ENABLED)
        && settings["isEnabled"].as_bool() != Some(true)
        && settings["bookingServiceId"]
            .as_str()
            .is_none_or(str::is_empty)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bookings_reply_reads_as_teams_shows_it() {
        let reply = json!({
            "title": "Personal Attendant Followup", "webUrl": "https://outlook.office.com/book/x/s/abc", "isPrivate": true, "defaultDuration": "PT30M",
            "serviceId": "ddf16a17", "bookingUrlCodes": { "5e82": "x" },
            "bookingsSchedulingPolicy": { "maximumAdvance": "P60D", "minimumLeadTime": "PT1H", "timeSlotInterval": "PT15M" }
        });
        let d = bookings_details(&reply);
        assert_eq!(
            d["webUrl"],
            "https://outlook.office.com/book/x/s/abc?bookingCode=5e82"
        );
        assert_eq!(d["maximumAdvanceTime"], "P60D");
        assert_eq!(d["hasCustomServiceWindows"], false);
        assert_eq!(d["bookingServiceWindows"], json!([]));
        let mut changed = d.clone();
        changed["defaultDuration"] = json!("PT45M");
        changed["hasCustomServiceWindows"] = json!(true);
        changed["bookingServiceWindows"] = json!([{ "bookableHours": [{ "day": "Monday", "timeSlots": [{ "start": 540, "end": 1020 }] }] }]);
        assert_eq!(
            bookings_update_body(&changed),
            json!({ "minimumLeadTime": "PT1H", "maximumAdvance": "P60D", "defaultDuration": "PT45M", "hasCustomServiceWindows": true,
                    "bookingServiceWindows": [{ "bookableHours": [{ "day": "Monday", "timeSlots": [{ "start": 540, "end": 1020 }] }] }] })
        );
        assert!(bookings_path("a b@x.com", "s", "c").starts_with("/beta/personalbookings/bookingsService?email=a+b%40x.com&bookingServiceId=s&bookingCode=c"));
    }

    #[test]
    fn delegate_bodies_match_the_capture() {
        let b = add_body("8:orgid:9e", "2026-11-21T17:16:58.750Z");
        assert_eq!(
            b,
            json!({ "userMri": "8:orgid:9e", "isActive": true, "allowedActions": { "makeCalls": true, "manageSettings": true, "receiveCalls": true, "pickUpHeldCalls": true, "joinActiveCalls": false }, "createdDate": "2026-11-21T17:16:58.750Z" })
        );
        let e = edit_body(&b["allowedActions"], "joinActiveCalls", true);
        assert_eq!(
            e,
            json!({ "isActive": true, "allowedActions": { "makeCalls": true, "manageSettings": true, "receiveCalls": true, "pickUpHeldCalls": true, "joinActiveCalls": true } })
        );
    }

    #[test]
    fn bookings_only_on_first_turn_on_where_allowed() {
        let pol = json!({ "calendarBookings": "EnabledUserOverride" });
        assert!(wants_bookings(&pol, &json!({ "isEnabled": false }), true));
        assert!(!wants_bookings(
            &pol,
            &json!({ "isEnabled": false, "bookingServiceId": "x" }),
            true
        ));
        assert!(!wants_bookings(
            &json!({ "calendarBookings": "Disabled" }),
            &json!({}),
            true
        ));
        assert_eq!(
            attendant_body(&json!({ "isEnabled": true, "__typename": "X" })),
            json!({ "isEnabled": true, "id": "personalAttendantSettingsId" })
        );
    }
}
