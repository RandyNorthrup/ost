//! A person's profile card, as Teams' Live Persona Card fills it (measured
//! on winpc 2026-11-10): who they are and how to reach them (Graph user),
//! their manager and the people reporting to them, and when they're free
//! with their working hours and time zone (Graph getSchedule).

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// The fields the card shows.
const SELECT: &str = "id,displayName,givenName,surname,jobTitle,department,mail,userPrincipalName,imAddresses,businessPhones,mobilePhone,officeLocation,companyName,city,state,country,streetAddress,postalCode,preferredLanguage";

/// One person in the card's organization section.
fn person(v: &serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "id": v["id"],
        "name": v["displayName"],
        "jobTitle": v["jobTitle"],
        "mri": v["id"].as_str().map(|o| format!("8:orgid:{o}")),
    })
}

/// Everything the card shows for the user `oid` (an AAD object id), as
/// JSON: the profile, `manager`, `reports`, and `schedule` (workingHours
/// and the free/busy view for the next day), each left out when Graph
/// won't say.
pub async fn profile_card(client: &TeamsClient, oid: &str) -> Result<serde_json::Value> {
    let my_mail = client
        .graph_get("/me?$select=mail,userPrincipalName")
        .await
        .ok()
        .map(|r| async move { r.json::<serde_json::Value>().await.ok() });
    let my_mail = match my_mail {
        Some(f) => f.await.and_then(|v| v["mail"].as_str().or(v["userPrincipalName"].as_str()).map(str::to_string)),
        None => None,
    };
    anyhow::ensure!(
        oid.len() == 36 && oid.chars().all(|c| c.is_ascii_hexdigit() || c == '-'),
        "Not a user id: {oid}"
    );
    let mut card: serde_json::Value = client
        .graph_get(&format!("/users/{oid}?$select={SELECT}"))
        .await?
        .json()
        .await
        .context("Profile reply")?;
    if let Ok(Some(r)) = client.graph_get_opt(&format!("/users/{oid}/manager?$select=id,displayName,jobTitle")).await
        && let Ok(m) = r.json::<serde_json::Value>().await
    {
        card["manager"] = person(&m);
    }
    if let Ok(r) = client
        .graph_get(&format!("/users/{oid}/directReports?$select=id,displayName,jobTitle"))
        .await
        && let Ok(v) = r.json::<serde_json::Value>().await
    {
        card["reports"] = serde_json::Value::Array(v["value"].as_array().into_iter().flatten().map(person).collect());
    }
    if let Some(mail) = card["mail"].as_str().or(card["userPrincipalName"].as_str()) {
        let now = chrono::Utc::now();
        let schedules: Vec<String> = [Some(mail.to_string()), my_mail.clone()].into_iter().flatten().collect();
        let body = serde_json::json!({
            "schedules": schedules,
            "startTime": { "dateTime": now.format("%Y-%m-%dT%H:%M:%S").to_string(), "timeZone": "UTC" },
            "endTime": { "dateTime": (now + chrono::Duration::days(2)).format("%Y-%m-%dT%H:%M:%S").to_string(), "timeZone": "UTC" },
            "availabilityViewInterval": 30,
        });
        if let Ok(r) = client.graph_post("/me/calendar/getSchedule", &body).await
            && let Ok(v) = r.json::<serde_json::Value>().await
            && let Some(s) = v["value"].get(0)
        {
            card["schedule"] = serde_json::json!({
                "start": now.to_rfc3339(),
                "view": s["availabilityView"],
                "workingHours": s["workingHours"],
                "items": s["scheduleItems"],
                // Yours, to say "Same time zone as you".
                "myTimeZone": v["value"].get(1).map(|m| m["workingHours"]["timeZone"]["name"].clone()),
            });
        }
    }
    Ok(card)
}

/// When someone is next free, from a getSchedule availability view (one
/// digit per 30 minutes from `start`: 0 free, 1 tentative, 2 busy, 3 out of
/// office, 4 working elsewhere): the start of the first free slot after a
/// busy one, or None when free now or never in the window.
pub fn next_free(view: &str, start: chrono::DateTime<chrono::Utc>) -> Option<chrono::DateTime<chrono::Utc>> {
    if view.starts_with('0') {
        return None;
    }
    view.find('0').map(|i| start + chrono::Duration::minutes(30 * i as i64))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn next_free_is_the_first_free_slot_after_busy() {
        let start = chrono::DateTime::parse_from_rfc3339("2026-11-10T11:00:00Z").unwrap().with_timezone(&chrono::Utc);
        assert_eq!(next_free("000", start), None);
        assert_eq!(next_free("2200", start).unwrap().to_rfc3339(), "2026-11-10T12:00:00+00:00");
        assert_eq!(next_free("3333", start), None);
    }
}
