//! Events ▸ Manage ▸ Manage immersive collections (Teams' immersive
//! worlds service and Microsoft 365 groups), as Teams desktop 26304 does it
//! (services-immersive-worlds, r_data-resolvers-immersive-worlds, the
//! collection pages in meet-app):
//! - the list is Graph `me/memberOf` filtered to groups with the
//!   `teams.immersive` behaviour (`ConsistencyLevel: eventual`);
//! - a collection is made, read, renamed and deleted on the worlds service
//!   (`immersiveWorldsServiceEndpoint`, token resource 3016d0ce-…):
//!   `/v3.0/collections` POST `{DisplayName, Description?}`, GET
//!   `{collection, privileges, status}`, PATCH, DELETE;
//! - owners and members are the group's (Graph `groups/{id}/owners` and
//!   `/members`), changed on the worlds service (`/owners {userId}`,
//!   `/owners/remove`, `/members {userIds}`, `/members/remove {userId}`).

use anyhow::{Context, Result};
use serde_json::{json, Value};

use super::client::TeamsClient;

/// Teams' `immersiveWorldsServiceEndpoint` (config-prod).
const DEFAULT_ENDPOINT: &str = "https://eur.worlds.mesh.cloud.microsoft";
/// Teams' `immersiveWorldsServiceResource`.
pub const RESOURCE: &str = "3016d0ce-47cc-4005-b11d-5fcabb1b643d";

fn endpoint() -> String {
    super::ecs::setting("virtualEvents", "immersiveWorldsServiceEndpoint")
        .and_then(|v| v.as_str().map(str::to_string))
        .filter(|u| u.starts_with("https://"))
        .unwrap_or_else(|| DEFAULT_ENDPOINT.to_string())
        .trim_end_matches('/')
        .to_string()
}

fn check_id(id: &str) -> Result<()> {
    anyhow::ensure!(uuid::Uuid::parse_str(id).is_ok(), "Not a collection id");
    Ok(())
}

/// Whether Manage shows "Manage immersive collections": ECS
/// `enableImmersiveContentManagementInMeetApp` and your events policy's
/// immersive events (`allowImmersiveEventsPolicy`).
pub fn management_enabled(ecs_flag: Option<&Value>, policy: Option<&Value>) -> bool {
    let flag = ecs_flag.and_then(Value::as_bool).unwrap_or(false);
    let allowed = policy
        .and_then(|p| p.as_str().map(str::to_string).or_else(|| p.as_bool().map(|b| if b { "Enabled".into() } else { "Disabled".into() })))
        .is_some_and(|s| s.eq_ignore_ascii_case("enabled"));
    flag && allowed
}

/// Your immersive collections: `[{id, displayName, description,
/// sensitivityLabelId}]` sorted by name (Graph's `$orderBy`).
pub async fn list(client: &TeamsClient) -> Result<Value> {
    let path = "/me/memberOf?$filter=resourceBehaviorOptions/any(i:i%20eq%20'teams.immersive')&$count=true&$select=id,displayName,description,classification,assignedLabels&$orderBy=displayName";
    let v: Value = client.graph_get_with(path, &[("ConsistencyLevel", "eventual")]).await?.json().await.context("Collections")?;
    Ok(Value::Array(collections_from(&v)))
}

pub fn collections_from(v: &Value) -> Vec<Value> {
    v.get("value").and_then(Value::as_array).into_iter().flatten()
        .map(|g| json!({
            "id": g.get("id").cloned().unwrap_or_default(),
            "displayName": g.get("displayName").cloned().unwrap_or_default(),
            "description": g.get("description").cloned().unwrap_or(Value::Null),
            "sensitivityLabelId": g.pointer("/assignedLabels/0/labelId").or_else(|| g.pointer("/assignedLabels/0/id")).cloned().unwrap_or(Value::Null),
        }))
        .collect()
}

async fn worlds(method: reqwest::Method, path: &str, body: Option<&Value>) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await?;
    let trace = uuid::Uuid::new_v4().simple().to_string();
    let span: String = uuid::Uuid::new_v4().simple().to_string().chars().take(16).collect();
    let mut req = reqwest::Client::new()
        .request(method, format!("{}{path}", endpoint()))
        .bearer_auth(token)
        .header("Content-Type", "application/json")
        .header("Traceparent", format!("00-{trace}-{span}-01"));
    if let Some(b) = body {
        req = req.json(b);
    }
    let resp = req.send().await.context("The immersive worlds service")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!("The immersive worlds service answered {status}");
    }
    Ok(serde_json::from_str(&text).unwrap_or_else(|_| json!({})))
}

/// Create collection's body: `{"DisplayName", "Description"?}` (empty
/// fields left out, as Teams sends it).
pub fn create_body(name: &str, description: &str) -> Value {
    let mut b = json!({ "DisplayName": name.trim() });
    if !description.trim().is_empty() {
        b["Description"] = json!(description.trim());
    }
    b
}

pub async fn create(name: &str, description: &str) -> Result<Value> {
    anyhow::ensure!(!name.trim().is_empty(), "Collection name is required");
    worlds(reqwest::Method::POST, "/v3.0/collections", Some(&create_body(name, description))).await
}

pub async fn get(id: &str) -> Result<Value> {
    check_id(id)?;
    worlds(reqwest::Method::GET, &format!("/v3.0/collections/{id}"), None).await
}

pub async fn update(id: &str, name: &str, description: &str) -> Result<Value> {
    check_id(id)?;
    worlds(reqwest::Method::PATCH, &format!("/v3.0/collections/{id}"), Some(&create_body(name, description))).await
}

pub async fn delete(id: &str) -> Result<()> {
    check_id(id)?;
    worlds(reqwest::Method::DELETE, &format!("/v3.0/collections/{id}"), None).await?;
    Ok(())
}

/// The collection's owners and members (the group's; members without the
/// owners): `{owners: [...], members: [...]}` with `id, displayName,
/// jobTitle, userPrincipalName`.
pub async fn people(client: &TeamsClient, id: &str) -> Result<Value> {
    check_id(id)?;
    let read = |v: Value| -> Vec<Value> {
        v.get("value").and_then(Value::as_array).cloned().unwrap_or_default().into_iter()
            .map(|p| json!({ "id": p.get("id").cloned().unwrap_or_default(), "displayName": p.get("displayName").cloned().unwrap_or_default(),
                             "jobTitle": p.get("jobTitle").cloned().unwrap_or(Value::Null), "userPrincipalName": p.get("userPrincipalName").cloned().unwrap_or_default() }))
            .collect()
    };
    let owners = read(client.graph_get(&format!("/groups/{id}/owners")).await?.json().await?);
    let all = read(client.graph_get(&format!("/groups/{id}/members")).await?.json().await?);
    let members: Vec<Value> = all.into_iter().filter(|m| !owners.iter().any(|o| o["id"] == m["id"])).collect();
    Ok(json!({ "owners": owners, "members": members }))
}

/// Add people's requests: each owner `POST /owners {userId}`, then
/// everyone `POST /members {userIds}` (owners and members, once each).
pub async fn add_people(id: &str, owners: &[String], members: &[String]) -> Result<()> {
    check_id(id)?;
    for o in owners {
        check_id(o)?;
        worlds(reqwest::Method::POST, &format!("/v3.0/collections/{id}/owners"), Some(&json!({ "userId": o }))).await?;
    }
    let mut all: Vec<String> = owners.iter().chain(members).cloned().collect();
    all.sort();
    all.dedup();
    if !all.is_empty() {
        worlds(reqwest::Method::POST, &format!("/v3.0/collections/{id}/members"), Some(&json!({ "userIds": all }))).await?;
    }
    Ok(())
}

/// A role change or removal: `owner` (POST /owners), `member` (POST
/// /owners/remove), `remove` (POST /members/remove).
pub async fn change_person(id: &str, user: &str, what: &str) -> Result<()> {
    check_id(id)?;
    check_id(user)?;
    let path = match what {
        "owner" => "owners",
        "member" => "owners/remove",
        "remove" => "members/remove",
        _ => anyhow::bail!("Not a change"),
    };
    worlds(reqwest::Method::POST, &format!("/v3.0/collections/{id}/{path}"), Some(&json!({ "userId": user }))).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bodies_and_lists_as_teams() {
        assert_eq!(create_body(" OST TEST 212 c ", ""), json!({ "DisplayName": "OST TEST 212 c" }));
        assert_eq!(create_body("A", "d"), json!({ "DisplayName": "A", "Description": "d" }));
        let v = json!({ "value": [{ "id": "g1", "displayName": "A", "description": null, "assignedLabels": [] }] });
        assert_eq!(collections_from(&v), vec![json!({ "id": "g1", "displayName": "A", "description": null, "sensitivityLabelId": null })]);
        assert!(management_enabled(Some(&json!(true)), Some(&json!("Enabled"))));
        assert!(!management_enabled(Some(&json!(false)), Some(&json!("Enabled"))));
        assert!(!management_enabled(None, Some(&json!("Enabled"))));
        assert!(!management_enabled(Some(&json!(true)), Some(&json!("Disabled"))));
    }
}
