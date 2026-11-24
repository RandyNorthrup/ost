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

/// Teams' Live Persona Card org chart query (Loki OrgExplorer,
/// `useOrgExplorerQueryRef_OrganizationQuery`, captured on winpc 2026-11-20),
/// cut to the fields the Organization tab draws.
const ORG_QUERY: &str = "query useOrgExplorerQueryRef_OrganizationQuery($personIds: OneGQL_PersonIdsInput!, $directsToLoad: Int!, $worksWithToLoad: Int!, $isMto: Boolean = false) {
  orgexplorer {
    personInFocusV2(personIds: $personIds, isMto: $isMto) {
      aadObjectId fullName isMe email jobTitle department location directReportsCount transitiveReportsCount id
      presence { availability calendarData { isOutOfOffice } id }
      managerChainTopToBottom(first: 100) { nodes { aadObjectId fullName email jobTitle location directReportsCount transitiveReportsCount presence { availability calendarData { isOutOfOffice } id } id } }
      directs(first: $directsToLoad) { edges { node { aadObjectId fullName email jobTitle location directReportsCount transitiveReportsCount presence { availability calendarData { isOutOfOffice } id } id } } pageInfo { endCursor hasNextPage } }
      workingWith(first: $worksWithToLoad) { nodes { aadObjectId fullName email jobTitle location presence { availability calendarData { isOutOfOffice } id } id } }
    }
  }
}";

/// One person of Loki's org chart as the card draws them.
fn org_person(v: &serde_json::Value) -> serde_json::Value {
    let oid = v["aadObjectId"].as_str().unwrap_or_default();
    serde_json::json!({
        "id": oid,
        "mri": format!("8:orgid:{oid}"),
        "name": v["fullName"],
        "jobTitle": v["jobTitle"].as_str().unwrap_or_default(),
        "location": v["location"].as_str().unwrap_or_default(),
        "email": v["email"],
        "reports": v["transitiveReportsCount"].as_i64().unwrap_or(0),
        "directs": v["directReportsCount"].as_i64().unwrap_or(0),
        "availability": v["presence"]["availability"].as_str().unwrap_or_default(),
        "outOfOffice": v["presence"]["calendarData"]["isOutOfOffice"].as_bool().unwrap_or(false),
        "isMe": v["isMe"].as_bool().unwrap_or(false),
    })
}

/// The org chart Teams draws from a Loki answer: the person in focus, their
/// manager chain (top first), the people reporting to them and the people
/// they work with. Multipart (deferred) answers are merged first.
pub fn org_from(body: &str) -> Option<serde_json::Value> {
    let mut root: Option<serde_json::Value> = None;
    // A plain JSON answer, or `multipart/mixed` parts each with a JSON body.
    let parts: Vec<&str> = if body.trim_start().starts_with('{') { vec![body] } else { body.split("\r\n---").chain(std::iter::empty()).collect() };
    for part in parts {
        let Some(at) = part.find('{') else { continue };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(part[at..].trim_end().trim_end_matches("-----").trim_end_matches("---").trim()) else { continue };
        if let Some(d) = v.get("data") {
            root = Some(d.clone());
        }
        for inc in v["incremental"].as_array().into_iter().flatten() {
            let (Some(r), Some(path)) = (root.as_mut(), inc["path"].as_array()) else { continue };
            let mut at = r;
            for p in path {
                at = match p {
                    serde_json::Value::String(k) => &mut at[k.as_str()],
                    serde_json::Value::Number(n) => &mut at[n.as_u64().unwrap_or(0) as usize],
                    _ => at,
                };
            }
            if let (Some(dst), Some(src)) = (at.as_object_mut(), inc["data"].as_object()) {
                for (k, val) in src {
                    dst.insert(k.clone(), val.clone());
                }
            }
        }
    }
    let p = root?.pointer("/orgexplorer/personInFocusV2")?.clone();
    Some(serde_json::json!({
        "focus": org_person(&p),
        "managers": p["managerChainTopToBottom"]["nodes"].as_array().into_iter().flatten().map(org_person).collect::<Vec<_>>(),
        "directs": p["directs"]["edges"].as_array().into_iter().flatten().map(|e| org_person(&e["node"])).collect::<Vec<_>>(),
        "worksWith": p["workingWith"]["nodes"].as_array().into_iter().flatten().map(org_person).collect::<Vec<_>>(),
    }))
}

/// A person's org chart as Teams' card asks Loki for it (`POST https://
/// {region}.loki.delve.office.com/api/v2/graphql?operationName=
/// useOrgExplorerQueryRef_OrganizationQuery`, a Loki token: Teams'
/// lokiTokenResourceUrl https://loki.delve.office.com/).
pub async fn org_chart(client: &TeamsClient, oid: &str, smtp: &str) -> Result<serde_json::Value> {
    anyhow::ensure!(uuid::Uuid::parse_str(oid).is_ok(), "Not a user id: {oid}");
    let token = crate::auth::oauth::access_token_for("https://loki.delve.office.com//.default").await?;
    let body = serde_json::json!({
        "operationName": "useOrgExplorerQueryRef_OrganizationQuery",
        "variables": { "personIds": { "aadObjectId": oid, "smtp": smtp }, "directsToLoad": 20, "worksWithToLoad": 25, "isMto": false },
        "query": ORG_QUERY,
    });
    let mut last = None;
    for host in [loki_host(), "https://loki.delve.office.com".to_string()] {
        let r = client
            .http()
            .post(format!("{host}/api/v2/graphql?operationName=useOrgExplorerQueryRef_OrganizationQuery"))
            .bearer_auth(&token)
            .header("accept", "application/json")
            .header("x-clientfeature", "LivePersonaCard")
            .header("x-clienttype", "Teams")
            .header("x-clientscenario", "GetOrgExplorerV2")
            .header("scenariotag", "Teams_useOrgExplorerQueryRef_OrganizationQuery")
            .json(&body)
            .send()
            .await;
        match r {
            Ok(r) if r.status().is_success() => {
                let text = r.text().await?;
                return org_from(&text).context("Org chart reply");
            }
            Ok(r) => last = Some(anyhow::anyhow!("Org chart: {}", r.status())),
            Err(e) => last = Some(e.into()),
        }
    }
    Err(last.unwrap_or_else(|| anyhow::anyhow!("Org chart")))
}

/// Loki's regional host (`https://nam.loki.delve.office.com` for a North
/// American tenant, as Teams' card calls it).
fn loki_host() -> String {
    let region = std::env::var("OST_LOKI_REGION").unwrap_or_else(|_| "nam".to_string());
    format!("https://{region}.loki.delve.office.com")
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
    fn org_chart_merges_lokis_deferred_parts() {
        // Shaped as Loki answered for OST Test 1 (2026-11-20).
        let body = "\r\n---\r\nContent-Type: application/json; charset=utf-8\r\n\r\n{\"data\":{\"orgexplorer\":{\"personInFocusV2\":{\"aadObjectId\":\"a1\",\"fullName\":\"OST Test 1\",\"transitiveReportsCount\":0,\"directReportsCount\":0,\"managerChainTopToBottom\":{\"nodes\":[{\"aadObjectId\":\"b2\",\"fullName\":\"OST Test 2\",\"transitiveReportsCount\":1,\"directReportsCount\":1}]},\"directs\":{\"edges\":[]}}}},\"hasNext\":true}\r\n---\r\nContent-Type: application/json; charset=utf-8\r\n\r\n{\"incremental\":[{\"data\":{\"presence\":{\"availability\":\"Offline\"}},\"path\":[\"orgexplorer\",\"personInFocusV2\",\"managerChainTopToBottom\",\"nodes\",0]},{\"data\":{\"workingWith\":{\"nodes\":[{\"aadObjectId\":\"c3\",\"fullName\":\"OST Test 3\"}]}},\"path\":[\"orgexplorer\",\"personInFocusV2\"]}],\"hasNext\":false}\r\n-----\r\n";
        let o = org_from(body).unwrap();
        assert_eq!(o["focus"]["name"], "OST Test 1");
        assert_eq!(o["managers"][0]["name"], "OST Test 2");
        assert_eq!(o["managers"][0]["availability"], "Offline");
        assert_eq!(o["managers"][0]["reports"], 1);
        assert_eq!(o["worksWith"][0]["mri"], "8:orgid:c3");
        assert_eq!(o["directs"].as_array().unwrap().len(), 0);
        let plain = org_from("{\"data\":{\"orgexplorer\":{\"personInFocusV2\":{\"aadObjectId\":\"a1\",\"fullName\":\"X\"}}}}").unwrap();
        assert_eq!(plain["focus"]["name"], "X");
    }

    #[test]
    fn next_free_is_the_first_free_slot_after_busy() {
        let start = chrono::DateTime::parse_from_rfc3339("2026-11-10T11:00:00Z").unwrap().with_timezone(&chrono::Utc);
        assert_eq!(next_free("000", start), None);
        assert_eq!(next_free("2200", start).unwrap().to_rfc3339(), "2026-11-10T12:00:00+00:00");
        assert_eq!(next_free("3333", start), None);
    }
}
