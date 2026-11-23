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

// ── Workplace check-in over Wi-Fi (TASK-0149) ───────────────────────────
// Teams' worker (shared worker 26304: PlacesManager / wifiAutoLocationHelper
// and the IC3 location service client): with the work-location policy on
// and your "Manage my work location" switch on, a Wi-Fi network change
// gets the tenant's SSID allow list (cached a day) and, on one of those
// networks, reports the access point (PUT …/location/network with
// shouldUpdate): the service checks you in, answering 200 with the
// building its BSSID maps to, 207 for an office network with no building
// (In the office), or 404. On any other network Teams checks you out
// (DELETE …/location/wifiNetwork).

/// The IC3 location service's resource (ECS presence.ic3LocationResourceUrl).
pub const IC3_LOCATION_RESOURCE: &str = "https://ic3.teams.office.com";

/// What the service made of a reported network.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub enum Detected {
    /// Checked in at this building (BSSID match).
    Building { id: String, name: String },
    /// Checked in "In the office" (SSID match, no building).
    Office,
    /// The service knows no place for it.
    NotFound,
}

/// The office networks (SSIDs) your tenant lists.
pub async fn ssid_allow_list(client: &TeamsClient, endpoint_id: &str) -> Result<Vec<String>> {
    let resp = location_request(client, reqwest::Method::GET, "v1/me/ssid-allowlist", endpoint_id)
        .await?
        .send()
        .await
        .context("SSID allow list")?;
    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!("SSID allow list: HTTP {} {}", status.as_u16(), body.chars().take(300).collect::<String>());
    }
    let v: serde_json::Value = resp.json().await.context("SSID allow list reply")?;
    Ok(ssid_list_from(&v))
}

/// The SSIDs in the allow list's reply (`SSIDList`).
pub fn ssid_list_from(v: &serde_json::Value) -> Vec<String> {
    v["SSIDList"].as_array().map(|a| a.iter().filter_map(|s| s.as_str().map(str::to_string)).collect()).unwrap_or_default()
}

/// The network body Teams reports (its reportDetectedNetworkForUpdate;
/// the SSID only with ECS places.useSSIDForIC3LSNetworkApiRequest).
pub fn network_body(bssid: &str, ssid: Option<&str>, at: chrono::DateTime<chrono::Utc>) -> serde_json::Value {
    let mut b = serde_json::json!({ "bssid": bssid });
    if let Some(s) = ssid {
        b["ssid"] = serde_json::Value::String(s.to_string());
    }
    b["eventTime"] = serde_json::Value::String(at.to_rfc3339_opts(chrono::SecondsFormat::Millis, true));
    b["shouldUpdate"] = serde_json::Value::Bool(true);
    b["canShareLocationDetails"] = serde_json::Value::Bool(true);
    b
}

/// Report the access point you're on (the service checks you in).
pub async fn report_network(client: &TeamsClient, endpoint_id: &str, body: &serde_json::Value) -> Result<Detected> {
    let path = format!("v1/me/endpoints/{endpoint_id}/location/network");
    let resp = location_request(client, reqwest::Method::PUT, &path, endpoint_id)
        .await?
        .body(body.to_string())
        .send()
        .await
        .context("Report network")?;
    let status = resp.status().as_u16();
    match status {
        200 | 207 | 404 => {
            let v: serde_json::Value = resp.json().await.unwrap_or_default();
            Ok(detected_from(status, &v))
        }
        s => {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("Report network: HTTP {s} {}", body.chars().take(300).collect::<String>())
        }
    }
}

/// The place a reply names (200: `placeId`, `name`).
pub fn detected_from(status: u16, v: &serde_json::Value) -> Detected {
    match status {
        200 => Detected::Building {
            id: v["placeId"].as_str().unwrap_or_default().to_string(),
            name: v["name"].as_str().unwrap_or_default().to_string(),
        },
        207 => Detected::Office,
        _ => Detected::NotFound,
    }
}

/// What the service makes of an access point without checking you in:
/// Teams' first-run look-up (its reportDetectedNetworkForFRE, `GET
/// …/location/wifiNetwork?bssid=…[&ssid=…]`) while your automatic work
/// location was never set. 200 names the building, 207 is "In the office",
/// 404 none.
pub async fn resolve_network(client: &TeamsClient, endpoint_id: &str, bssid: &str, ssid: Option<&str>) -> Result<Detected> {
    let path = format!("v1/me/endpoints/{endpoint_id}/location/wifiNetwork?{}", wifi_network_query(bssid, ssid));
    let resp = location_request(client, reqwest::Method::GET, &path, endpoint_id).await?.send().await.context("Resolve network")?;
    let status = resp.status().as_u16();
    match status {
        200 | 207 | 404 => {
            let v: serde_json::Value = resp.json().await.unwrap_or_default();
            Ok(detected_from(status, &v))
        }
        s => anyhow::bail!("Resolve network: HTTP {s}"),
    }
}

/// The look-up's query: Teams appends each non-empty value in turn.
pub fn wifi_network_query(bssid: &str, ssid: Option<&str>) -> String {
    let mut q = reqwest::Url::parse("https://x/").expect("static URL");
    {
        let mut pairs = q.query_pairs_mut();
        if !bssid.is_empty() {
            pairs.append_pair("bssid", bssid);
        }
        if let Some(s) = ssid.filter(|s| !s.is_empty()) {
            pairs.append_pair("ssid", s);
        }
    }
    q.query().unwrap_or_default().to_string()
}

/// Check out (you left the office network).
pub async fn report_remote(client: &TeamsClient, endpoint_id: &str) -> Result<()> {
    let path = format!("v1/me/endpoints/{endpoint_id}/location/wifiNetwork");
    let resp = location_request(client, reqwest::Method::DELETE, &path, endpoint_id).await?.send().await.context("Check out")?;
    if !resp.status().is_success() {
        anyhow::bail!("Check out: HTTP {}", resp.status().as_u16());
    }
    Ok(())
}

/// A new correlation vector (the service checks MS-CV's form: 22 base64
/// characters of a random 128-bit base, then ".0").
pub fn correlation_vector() -> String {
    use base64::Engine as _;
    let b = base64::engine::general_purpose::STANDARD_NO_PAD.encode(uuid::Uuid::new_v4().as_bytes());
    format!("{b}.0")
}

/// This device's id for the location service (kept with OST's settings).
fn device_id() -> String {
    static ID: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    ID.get_or_init(|| {
        std::fs::read_to_string("/etc/machine-id")
            .ok()
            .map(|m| m.trim().to_string())
            .filter(|m| m.len() >= 32)
            .map(|m| format!("{}-{}-{}-{}-{}", &m[0..8], &m[8..12], &m[12..16], &m[16..20], &m[20..32]))
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string())
    })
    .clone()
}

fn os_version() -> String {
    std::fs::read_to_string("/proc/sys/kernel/osrelease").map(|v| v.trim().to_string()).unwrap_or_default()
}

async fn location_request(client: &TeamsClient, method: reqwest::Method, path: &str, endpoint_id: &str) -> Result<reqwest::RequestBuilder> {
    let base = client.region_endpoint("iC3LocationService").context("No IC3 location service address")?;
    let token = crate::auth::oauth::access_token_for(&format!("{IC3_LOCATION_RESOURCE}/.default")).await?;
    Ok(client
        .http()
        .request(method, format!("{}/{path}", base.trim_end_matches('/')))
        .bearer_auth(token)
        .header("x-ms-client-user-agent", "Teams-V2-desktop")
        .header("X-ms-client-version", "1416/1.0.0.2024050301")
        .header("X-ms-client-type", "desktop")
        .header("x-ms-client-device-id", device_id())
        .header("x-ms-client-os", "linux")
        .header("x-ms-client-os-ver", os_version())
        .header("ms-cv", correlation_vector())
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .header("x-ms-endpoint-id", endpoint_id)
        .header("Content-Type", "application/json"))
}

#[cfg(test)]
mod location_tests {
    use super::*;

    #[test]
    fn network_body_is_teams() {
        let at = chrono::DateTime::parse_from_rfc3339("2026-11-20T17:00:00Z").unwrap().with_timezone(&chrono::Utc);
        let b = network_body("f4:92:bf:00:00:01", None, at);
        assert_eq!(b, serde_json::json!({"bssid": "f4:92:bf:00:00:01", "eventTime": "2026-11-20T17:00:00.000Z", "shouldUpdate": true, "canShareLocationDetails": true}));
        assert_eq!(network_body("x", Some("Office"), at)["ssid"], "Office");
    }

    #[test]
    fn correlation_vectors_have_teams_form() {
        let cv = correlation_vector();
        assert_eq!(cv.len(), 24);
        assert!(cv.ends_with(".0"));
    }

    #[test]
    fn replies() {
        assert_eq!(ssid_list_from(&serde_json::json!({"SSIDList": ["A", "B"]})), vec!["A", "B"]);
        assert_eq!(detected_from(200, &serde_json::json!({"placeId": "p1", "name": "OST Test Building"})), Detected::Building { id: "p1".into(), name: "OST Test Building".into() });
        assert_eq!(detected_from(207, &serde_json::json!({})), Detected::Office);
        assert_eq!(detected_from(404, &serde_json::json!({})), Detected::NotFound);
    }

    #[test]
    fn first_run_query_is_teams() {
        assert_eq!(wifi_network_query("f4:92:bf:78:c4:67", Some("Condor Cave")), "bssid=f4%3A92%3Abf%3A78%3Ac4%3A67&ssid=Condor+Cave");
        assert_eq!(wifi_network_query("f4:92:bf:78:c4:67", None), "bssid=f4%3A92%3Abf%3A78%3Ac4%3A67");
        assert_eq!(wifi_network_query("f4:92:bf:78:c4:67", Some("")), "bssid=f4%3A92%3Abf%3A78%3Ac4%3A67");
    }
}
