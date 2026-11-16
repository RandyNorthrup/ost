//! Microsoft Places as Teams reads it: the tenant's buildings (the middle
//! tier's `GET v2.0/places/findPlaces?filterQuery=Type = "Building"`,
//! captured at Teams' start on winpc 2026-11-15; the reply is
//! `{"data":{"places":[…]}}`).

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// A building from Places.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Building {
    pub id: String,
    pub name: String,
    /// "City, State, Country" as far as Places has it.
    pub address: String,
}

/// The places matching a Places filter (`Type = "Building"`, `Id = "…"`).
pub async fn find_places(client: &TeamsClient, filter: &str) -> Result<Vec<serde_json::Value>> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let mut url = reqwest::Url::parse(&format!("{mt}/v2.0/places/findPlaces")).context("Places address")?;
    url.query_pairs_mut().append_pair("filterQuery", filter);
    let v: serde_json::Value = client
        .http()
        .get(url)
        .bearer_auth(token)
        .send()
        .await
        .context("Find places")?
        .error_for_status()
        .context("Find places")?
        .json()
        .await
        .context("Find places reply")?;
    Ok(v["data"]["places"].as_array().cloned().unwrap_or_default())
}

/// The tenant's buildings, by name.
pub async fn buildings(client: &TeamsClient) -> Result<Vec<Building>> {
    let mut out: Vec<Building> = find_places(client, "Type = \"Building\"")
        .await?
        .iter()
        .filter_map(building_from)
        .collect();
    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    Ok(out)
}

/// A building from a Places record (`id` or `placeId`, `displayName` or
/// `name`, and its address).
pub fn building_from(p: &serde_json::Value) -> Option<Building> {
    let s = |k: &str| p[k].as_str().unwrap_or_default().to_string();
    let id = [s("placeId"), s("id")].into_iter().find(|x| !x.is_empty())?;
    let name = [s("displayName"), s("name")].into_iter().find(|x| !x.is_empty())?;
    let a = &p["address"];
    let part = |k: &str| a[k].as_str().unwrap_or_default().to_string();
    let address = [part("city"), part("state"), part("countryOrRegion"), part("country")]
        .into_iter()
        .filter(|x| !x.is_empty())
        .collect::<Vec<_>>()
        .join(", ");
    Some(Building { id, name, address })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buildings_from_places_records() {
        let p = serde_json::json!({"placeId": "b1", "displayName": "HQ", "address": {"city": "Jacksonville", "state": "FL", "countryOrRegion": "US"}});
        assert_eq!(
            building_from(&p),
            Some(Building { id: "b1".into(), name: "HQ".into(), address: "Jacksonville, FL, US".into() })
        );
        assert_eq!(building_from(&serde_json::json!({"id": "x"})), None);
    }
}
