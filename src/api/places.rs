//! Microsoft Places as Teams reads it: the tenant's buildings (the middle
//! tier's `GET v2.0/places/findPlaces?filterQuery=Type = "Building"`,
//! captured at Teams' start on winpc 2026-11-15; the reply is
//! `{"data":{"places":[…]}}`). With the ECS flight
//! `places.enableNewGetBuildingsAPIInMeControl` Teams 26304 asks
//! `GET v2.0/places/getBuildings` (reply `{"places":[…]}`) for the whole
//! list instead; one building by id is always findPlaces with
//! `Type = "Building" AND Id = "…"` (its places worker resolvers
//! placesBuildings / buildingById).

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// A building from Places.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Building {
    pub id: String,
    pub name: String,
    pub city: String,
    pub state: String,
    pub country: String,
}

async fn middle_tier_get(
    client: &TeamsClient,
    path: &str,
    query: Option<(&str, &str)>,
) -> Result<serde_json::Value> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let mut url = reqwest::Url::parse(&format!("{mt}/{path}")).context("Places address")?;
    if let Some((k, v)) = query {
        url.query_pairs_mut().append_pair(k, v);
    }
    client
        .http()
        .get(url)
        .bearer_auth(token)
        .send()
        .await
        .with_context(|| path.to_string())?
        .error_for_status()
        .with_context(|| path.to_string())?
        .json()
        .await
        .with_context(|| format!("{path} reply"))
}

/// The places matching a Places filter (`Type = "Building"`, `Id = "…"`).
pub async fn find_places(client: &TeamsClient, filter: &str) -> Result<Vec<serde_json::Value>> {
    let v = middle_tier_get(
        client,
        "v2.0/places/findPlaces",
        Some(("filterQuery", filter)),
    )
    .await?;
    Ok(v["data"]["places"].as_array().cloned().unwrap_or_default())
}

/// Teams' newer building list (`GET v2.0/places/getBuildings`).
pub async fn get_buildings(client: &TeamsClient) -> Result<Vec<serde_json::Value>> {
    let v = middle_tier_get(client, "v2.0/places/getBuildings", None).await?;
    Ok(v["places"].as_array().cloned().unwrap_or_default())
}

/// The tenant's buildings in Teams' order (by name, numbers by value,
/// case and accents aside). `new_api`: the getBuildings flight.
pub async fn buildings(client: &TeamsClient, new_api: bool) -> Result<Vec<Building>> {
    let places = if new_api {
        get_buildings(client).await?
    } else {
        find_places(client, BUILDINGS_FILTER).await?
    };
    Ok(sorted(places.iter().filter_map(building_from).collect()))
}

/// Teams' filter for all buildings.
pub const BUILDINGS_FILTER: &str = "Type = \"Building\"";

/// Teams' filter for one building (buildingById).
pub fn building_filter(id: &str) -> String {
    format!("Type = \"Building\" AND Id = \"{id}\"")
}

/// One building by id, as Teams' buildingById: only when Places answers
/// exactly one.
pub async fn building_by_id(client: &TeamsClient, id: &str) -> Result<Option<Building>> {
    let found = find_places(client, &building_filter(id)).await?;
    Ok(if found.len() == 1 {
        building_from(&found[0])
    } else {
        None
    })
}

/// A building from a Places record (`id` or `placeId`, `name` or
/// `displayName`, and its address).
pub fn building_from(p: &serde_json::Value) -> Option<Building> {
    let s = |k: &str| p[k].as_str().unwrap_or_default().to_string();
    let id = [s("id"), s("placeId")]
        .into_iter()
        .find(|x| !x.is_empty())?;
    let name = [s("name"), s("displayName")]
        .into_iter()
        .find(|x| !x.is_empty())?;
    let a = &p["address"];
    let part = |k: &str| a[k].as_str().unwrap_or_default().to_string();
    let country = [part("country"), part("countryOrRegion")]
        .into_iter()
        .find(|x| !x.is_empty())
        .unwrap_or_default();
    Some(Building {
        id,
        name,
        city: part("city"),
        state: part("state"),
        country,
    })
}

/// Teams' order: Intl.Collator(numeric, sensitivity base) on the names.
pub fn sorted(mut list: Vec<Building>) -> Vec<Building> {
    list.sort_by(|a, b| collate(&a.name, &b.name));
    list
}

/// A comparison like Intl.Collator(undefined, {numeric: true,
/// sensitivity: "base"}): case and accents don't count, runs of digits
/// compare by value.
pub fn collate(a: &str, b: &str) -> std::cmp::Ordering {
    fn chunks(s: &str) -> Vec<(bool, String)> {
        let mut out: Vec<(bool, String)> = Vec::new();
        for c in deburr(&s.to_lowercase()).chars() {
            let digit = c.is_ascii_digit();
            match out.last_mut() {
                Some((d, run)) if *d == digit => run.push(c),
                _ => out.push((digit, c.to_string())),
            }
        }
        out
    }
    let (x, y) = (chunks(a), chunks(b));
    for (p, q) in x.iter().zip(y.iter()) {
        let o = match (p.0, q.0) {
            (true, true) => {
                let (m, n) = (p.1.trim_start_matches('0'), q.1.trim_start_matches('0'));
                m.len().cmp(&n.len()).then_with(|| m.cmp(n))
            }
            _ => p.1.cmp(&q.1),
        };
        if o != std::cmp::Ordering::Equal {
            return o;
        }
    }
    x.len().cmp(&y.len())
}

/// lodash's deburr: Latin-1 Supplement and Latin Extended-A letters to
/// basic Latin, combining marks dropped.
pub fn deburr(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        let code = c as u32;
        if (0x300..=0x36f).contains(&code)
            || (0xfe20..=0xfe2f).contains(&code)
            || (0x20d0..=0x20ff).contains(&code)
        {
            continue;
        }
        match deburred(c) {
            Some(r) => out.push_str(r),
            None => out.push(c),
        }
    }
    out
}

fn deburred(c: char) -> Option<&'static str> {
    Some(match c {
        'À'..='Å' | 'Ā' | 'Ă' | 'Ą' => "A",
        'à'..='å' | 'ā' | 'ă' | 'ą' => "a",
        'Ç' | 'Ć' | 'Ĉ' | 'Ċ' | 'Č' => "C",
        'ç' | 'ć' | 'ĉ' | 'ċ' | 'č' => "c",
        'Ð' | 'Ď' | 'Đ' => "D",
        'ð' | 'ď' | 'đ' => "d",
        'È'..='Ë' | 'Ē' | 'Ĕ' | 'Ė' | 'Ę' | 'Ě' => "E",
        'è'..='ë' | 'ē' | 'ĕ' | 'ė' | 'ę' | 'ě' => "e",
        'Ĝ' | 'Ğ' | 'Ġ' | 'Ģ' => "G",
        'ĝ' | 'ğ' | 'ġ' | 'ģ' => "g",
        'Ĥ' | 'Ħ' => "H",
        'ĥ' | 'ħ' => "h",
        'Ì'..='Ï' | 'Ĩ' | 'Ī' | 'Ĭ' | 'Į' | 'İ' => "I",
        'ì'..='ï' | 'ĩ' | 'ī' | 'ĭ' | 'į' | 'ı' => "i",
        'Ĵ' => "J",
        'ĵ' => "j",
        'Ķ' => "K",
        'ķ' | 'ĸ' => "k",
        'Ĺ' | 'Ļ' | 'Ľ' | 'Ŀ' | 'Ł' => "L",
        'ĺ' | 'ļ' | 'ľ' | 'ŀ' | 'ł' => "l",
        'Ñ' | 'Ń' | 'Ņ' | 'Ň' | 'Ŋ' => "N",
        'ñ' | 'ń' | 'ņ' | 'ň' | 'ŋ' => "n",
        'Ò'..='Ö' | 'Ø' | 'Ō' | 'Ŏ' | 'Ő' => "O",
        'ò'..='ö' | 'ø' | 'ō' | 'ŏ' | 'ő' => "o",
        'Ŕ' | 'Ŗ' | 'Ř' => "R",
        'ŕ' | 'ŗ' | 'ř' => "r",
        'Ś' | 'Ŝ' | 'Ş' | 'Š' => "S",
        'ś' | 'ŝ' | 'ş' | 'š' | 'ſ' => "s",
        'Ţ' | 'Ť' | 'Ŧ' => "T",
        'ţ' | 'ť' | 'ŧ' => "t",
        'Ù'..='Ü' | 'Ũ' | 'Ū' | 'Ŭ' | 'Ů' | 'Ű' | 'Ų' => "U",
        'ù'..='ü' | 'ũ' | 'ū' | 'ŭ' | 'ů' | 'ű' | 'ų' => "u",
        'Ŵ' => "W",
        'ŵ' => "w",
        'Ý' | 'Ŷ' | 'Ÿ' => "Y",
        'ý' | 'ÿ' | 'ŷ' => "y",
        'Ź' | 'Ż' | 'Ž' => "Z",
        'ź' | 'ż' | 'ž' => "z",
        'Æ' => "Ae",
        'æ' => "ae",
        'Þ' => "Th",
        'þ' => "th",
        'ß' => "ss",
        'Ĳ' => "IJ",
        'ĳ' => "ij",
        'Œ' => "Oe",
        'œ' => "oe",
        'ŉ' => "'n",
        _ => return None,
    })
}

/// The buildings a search matches, as Teams' stationary location box:
/// the query (lower case, trimmed, deburred) is part of the building's
/// name, city, state or country (each lower case, deburred); an empty
/// query matches all.
pub fn matching<'a>(query: &str, list: &'a [Building]) -> Vec<&'a Building> {
    let q = deburr(query.to_lowercase().trim());
    if q.is_empty() {
        return list.iter().collect();
    }
    let has = |s: &str| deburr(&s.to_lowercase()).contains(&q);
    list.iter()
        .filter(|b| has(&b.name) || has(&b.city) || has(&b.state) || has(&b.country))
        .collect()
}

/// Teams' "Suggested" group: the building the check-out banner named
/// (Places' answer for it), then your current office building when it is
/// another one; only those among the buildings shown (`shown`).
pub fn suggested<'a>(
    banner: Option<&'a Building>,
    office: Option<&'a Building>,
    shown: &[&Building],
) -> Vec<&'a Building> {
    let banner = banner.filter(|b| !b.id.is_empty() && !b.name.is_empty());
    let mut out: Vec<&Building> = banner.into_iter().collect();
    if let Some(o) = office.filter(|o| !o.id.is_empty() && !o.name.is_empty())
        && banner.map(|b| b.id != o.id).unwrap_or(true)
    {
        out.push(o);
    }
    out.into_iter()
        .filter(|s| shown.iter().any(|b| b.id == s.id))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b(id: &str, name: &str, city: &str) -> Building {
        Building {
            id: id.into(),
            name: name.into(),
            city: city.into(),
            ..Default::default()
        }
    }

    #[test]
    fn buildings_from_places_records() {
        let p = serde_json::json!({"id": "b1", "name": "HQ", "address": {"city": "Jacksonville", "state": "FL", "country": "US"}});
        assert_eq!(
            building_from(&p),
            Some(Building {
                id: "b1".into(),
                name: "HQ".into(),
                city: "Jacksonville".into(),
                state: "FL".into(),
                country: "US".into()
            })
        );
        let q = serde_json::json!({"placeId": "b2", "displayName": "Annex", "address": {"countryOrRegion": "CA"}});
        assert_eq!(
            building_from(&q).map(|b| (b.id, b.name, b.country)),
            Some(("b2".into(), "Annex".into(), "CA".into()))
        );
        assert_eq!(building_from(&serde_json::json!({"id": "x"})), None);
    }

    #[test]
    fn teams_filters() {
        assert_eq!(BUILDINGS_FILTER, r#"Type = "Building""#);
        assert_eq!(
            building_filter("a93350e7"),
            r#"Type = "Building" AND Id = "a93350e7""#
        );
    }

    #[test]
    fn deburr_is_lodash() {
        assert_eq!(deburr("déjà vu"), "deja vu");
        assert_eq!(
            deburr("Straße Œuvre Æsir Þing"),
            "Strasse Oeuvre Aesir Thing"
        );
        assert_eq!(deburr("Łódź"), "Lodz");
        assert_eq!(deburr("e\u{301}"), "e");
        assert_eq!(deburr("×÷"), "×÷");
    }

    #[test]
    fn collator_order() {
        let names = |l: Vec<Building>| l.into_iter().map(|b| b.name).collect::<Vec<_>>();
        let l = sorted(vec![
            b("1", "Building 10", ""),
            b("2", "building 9", ""),
            b("3", "Éast", ""),
            b("4", "Annex", ""),
        ]);
        assert_eq!(names(l), ["Annex", "building 9", "Building 10", "Éast"]);
    }

    #[test]
    fn search_matches_name_city_state_country() {
        let list = vec![
            b("1", "OST Test Building", "Jacksonville"),
            Building {
                id: "2".into(),
                name: "Annex".into(),
                state: "Québec".into(),
                ..Default::default()
            },
            Building {
                id: "3".into(),
                name: "Tower".into(),
                country: "Deutschland".into(),
                ..Default::default()
            },
        ];
        let ids = |q: &str| {
            matching(q, &list)
                .iter()
                .map(|b| b.id.clone())
                .collect::<Vec<_>>()
        };
        assert_eq!(ids(""), ["1", "2", "3"]);
        assert_eq!(ids("  "), ["1", "2", "3"]);
        assert_eq!(ids("test"), ["1"]);
        assert_eq!(ids("JACKSON"), ["1"]);
        assert_eq!(ids("quebec"), ["2"]);
        assert_eq!(ids("Québ"), ["2"]);
        assert_eq!(ids("deutsch "), ["3"]);
        assert_eq!(ids("zzz"), Vec::<String>::new());
    }

    #[test]
    fn suggested_group() {
        let hq = b("hq", "HQ", "");
        let annex = b("an", "Annex", "");
        let gone = b("gone", "Gone", "");
        let all = [&hq, &annex];
        let ids = |v: Vec<&Building>| v.iter().map(|b| b.id.clone()).collect::<Vec<_>>();
        // The banner's building first, then the office one.
        assert_eq!(ids(suggested(Some(&hq), Some(&annex), &all)), ["hq", "an"]);
        // The same building once.
        assert_eq!(ids(suggested(Some(&hq), Some(&hq), &all)), ["hq"]);
        // Only buildings the list shows (the search, the tenant's list).
        assert_eq!(ids(suggested(Some(&gone), Some(&annex), &all)), ["an"]);
        assert_eq!(
            ids(suggested(Some(&hq), None, &[&annex])),
            Vec::<String>::new()
        );
        assert_eq!(ids(suggested(None, None, &all)), Vec::<String>::new());
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
    let resp = location_request(
        client,
        reqwest::Method::GET,
        "v1/me/ssid-allowlist",
        endpoint_id,
    )
    .await?
    .send()
    .await
    .context("SSID allow list")?;
    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!(
            "SSID allow list: HTTP {} {}",
            status.as_u16(),
            body.chars().take(300).collect::<String>()
        );
    }
    let v: serde_json::Value = resp.json().await.context("SSID allow list reply")?;
    Ok(ssid_list_from(&v))
}

/// The SSIDs in the allow list's reply (`SSIDList`).
pub fn ssid_list_from(v: &serde_json::Value) -> Vec<String> {
    v["SSIDList"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|s| s.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

/// The network body Teams reports (its reportDetectedNetworkForUpdate;
/// the SSID only with ECS places.useSSIDForIC3LSNetworkApiRequest).
pub fn network_body(
    bssid: &str,
    ssid: Option<&str>,
    at: chrono::DateTime<chrono::Utc>,
) -> serde_json::Value {
    let mut b = serde_json::json!({ "bssid": bssid });
    if let Some(s) = ssid {
        b["ssid"] = serde_json::Value::String(s.to_string());
    }
    b["eventTime"] =
        serde_json::Value::String(at.to_rfc3339_opts(chrono::SecondsFormat::Millis, true));
    b["shouldUpdate"] = serde_json::Value::Bool(true);
    b["canShareLocationDetails"] = serde_json::Value::Bool(true);
    b
}

/// Report the access point you're on (the service checks you in).
pub async fn report_network(
    client: &TeamsClient,
    endpoint_id: &str,
    body: &serde_json::Value,
) -> Result<Detected> {
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
            anyhow::bail!(
                "Report network: HTTP {s} {}",
                body.chars().take(300).collect::<String>()
            )
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
pub async fn resolve_network(
    client: &TeamsClient,
    endpoint_id: &str,
    bssid: &str,
    ssid: Option<&str>,
) -> Result<Detected> {
    let path = format!(
        "v1/me/endpoints/{endpoint_id}/location/wifiNetwork?{}",
        wifi_network_query(bssid, ssid)
    );
    let resp = location_request(client, reqwest::Method::GET, &path, endpoint_id)
        .await?
        .send()
        .await
        .context("Resolve network")?;
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
    let resp = location_request(client, reqwest::Method::DELETE, &path, endpoint_id)
        .await?
        .send()
        .await
        .context("Check out")?;
    if !resp.status().is_success() {
        anyhow::bail!("Check out: HTTP {}", resp.status().as_u16());
    }
    Ok(())
}

/// A new correlation vector (the service checks MS-CV's form: 22 base64
/// characters of a random 128-bit base, then ".0").
pub fn correlation_vector() -> String {
    use base64::Engine as _;
    let b =
        base64::engine::general_purpose::STANDARD_NO_PAD.encode(uuid::Uuid::new_v4().as_bytes());
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
            .map(|m| {
                format!(
                    "{}-{}-{}-{}-{}",
                    &m[0..8],
                    &m[8..12],
                    &m[12..16],
                    &m[16..20],
                    &m[20..32]
                )
            })
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string())
    })
    .clone()
}

fn os_version() -> String {
    std::fs::read_to_string("/proc/sys/kernel/osrelease")
        .map(|v| v.trim().to_string())
        .unwrap_or_default()
}

async fn location_request(
    client: &TeamsClient,
    method: reqwest::Method,
    path: &str,
    endpoint_id: &str,
) -> Result<reqwest::RequestBuilder> {
    let base = client
        .region_endpoint("iC3LocationService")
        .context("No IC3 location service address")?;
    let token =
        crate::auth::oauth::access_token_for(&format!("{IC3_LOCATION_RESOURCE}/.default")).await?;
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
        let at = chrono::DateTime::parse_from_rfc3339("2026-11-20T17:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let b = network_body("f4:92:bf:00:00:01", None, at);
        assert_eq!(
            b,
            serde_json::json!({"bssid": "f4:92:bf:00:00:01", "eventTime": "2026-11-20T17:00:00.000Z", "shouldUpdate": true, "canShareLocationDetails": true})
        );
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
        assert_eq!(
            ssid_list_from(&serde_json::json!({"SSIDList": ["A", "B"]})),
            vec!["A", "B"]
        );
        assert_eq!(
            detected_from(
                200,
                &serde_json::json!({"placeId": "p1", "name": "OST Test Building"})
            ),
            Detected::Building {
                id: "p1".into(),
                name: "OST Test Building".into()
            }
        );
        assert_eq!(detected_from(207, &serde_json::json!({})), Detected::Office);
        assert_eq!(
            detected_from(404, &serde_json::json!({})),
            Detected::NotFound
        );
    }

    #[test]
    fn first_run_query_is_teams() {
        assert_eq!(
            wifi_network_query("f4:92:bf:78:c4:67", Some("Condor Cave")),
            "bssid=f4%3A92%3Abf%3A78%3Ac4%3A67&ssid=Condor+Cave"
        );
        assert_eq!(
            wifi_network_query("f4:92:bf:78:c4:67", None),
            "bssid=f4%3A92%3Abf%3A78%3Ac4%3A67"
        );
        assert_eq!(
            wifi_network_query("f4:92:bf:78:c4:67", Some("")),
            "bssid=f4%3A92%3Abf%3A78%3Ac4%3A67"
        );
    }
}
