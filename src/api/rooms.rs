//! The tenant's meeting rooms for the pre-join screen's Room audio, as
//! Teams finds them (its RoomService, read from Teams' bundles and
//! captured from Teams desktop on winpc 2026-11-17):
//!
//! - **Other Suggestions**: `POST https://outlook.office.com/SchedulingB2/
//!   api/v1.0/me/findmeetinglocations` with `{"MaxCandidates":10,
//!   "ConferenceRoomsOnly":true}` and an Outlook token (Teams' EWS
//!   resource), a `client-request-id`.
//! - **Search for a room**: the same with `"QueryConstraint":{"Query":
//!   "<typed>"}` and `"LocationProvider":"80"` (Teams' 10 at most).
//! - Each room's `MeetingLocation.LocationEmailAddress` is then resolved
//!   to a Teams user the way Teams resolves people by mail (`POST {mt}/
//!   beta/users/fetchShortProfile?isMailAddress=true&…` with the
//!   addresses): Teams keeps the ones with a known address
//!   (`enableNearbyRoomsFromExternalTenants`) and uses their MRI as the
//!   room's id. A room without a Teams account can't be resolved and isn't
//!   listed.

use anyhow::{Context, Result, bail};

use super::client::TeamsClient;

/// Teams' address for a profile it couldn't resolve.
const UNKNOWN_EMAIL: &str = "unknown_email_address@invalid.teams.ms";

/// A room Teams can put in a meeting.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Room {
    /// The room account's MRI (`8:orgid:<object id>`): Teams' `userId`.
    pub mri: String,
    pub name: String,
    pub email: String,
}

/// The request body Teams sends to findmeetinglocations.
pub fn locations_body(max: u32, query: Option<&str>) -> serde_json::Value {
    let mut b = serde_json::json!({ "MaxCandidates": max, "ConferenceRoomsOnly": true });
    if let Some(q) = query.map(str::trim).filter(|q| !q.is_empty()) {
        b["QueryConstraint"] = serde_json::json!({ "Query": q });
        b["LocationProvider"] = "80".into();
    }
    b
}

/// The room addresses (and names) in a findmeetinglocations reply.
pub fn locations_from(v: &serde_json::Value) -> Vec<(String, String)> {
    v["MeetingLocations"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|l| {
            let m = &l["MeetingLocation"];
            let email = m["LocationEmailAddress"].as_str().filter(|e| !e.is_empty())?;
            Some((email.to_string(), m["DisplayName"].as_str().unwrap_or_default().to_string()))
        })
        .collect()
}

/// Teams' findmeetinglocations: suggested rooms, or the rooms matching
/// `query`.
pub async fn meeting_locations(client: &TeamsClient, max: u32, query: Option<&str>) -> Result<Vec<(String, String)>> {
    let token = crate::auth::oauth::access_token_for("https://outlook.office.com/.default").await?;
    let resp = client
        .http()
        .post("https://outlook.office.com/SchedulingB2/api/v1.0/me/findmeetinglocations")
        .bearer_auth(token)
        .header("client-request-id", uuid::Uuid::new_v4().to_string())
        .json(&locations_body(max, query))
        .send()
        .await
        .context("Find meeting locations")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Find meeting locations: HTTP {status}");
    }
    let v: serde_json::Value = resp.json().await.context("Find meeting locations reply")?;
    Ok(locations_from(&v))
}

/// The Events form's room search body (captured 2026-11-18): 25 rooms,
/// the typed text, and the event's time slot in its Windows zone so each
/// room comes with its availability.
pub fn locations_at_body(query: &str, start: &str, end: &str, zone: &str) -> serde_json::Value {
    serde_json::json!({
        "MaxCandidates": 25,
        "ConferenceRoomsOnly": true,
        "QueryConstraint": { "Query": query },
        "LocationProvider": "80",
        "TimeConstraint": { "Timeslots": [{ "Start": { "DateTime": start, "TimeZone": zone }, "End": { "DateTime": end, "TimeZone": zone } }], "Recurrence": null },
        "ResolveLocationsAvailability": true
    })
}

/// Rooms for a time slot: (address, name, availability, object id).
pub fn locations_at_from(v: &serde_json::Value) -> Vec<(String, String, String, String)> {
    v["MeetingLocations"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|l| {
            let m = &l["MeetingLocation"];
            let email = m["LocationEmailAddress"].as_str().filter(|e| !e.is_empty())?;
            let s = |k: &str| m[k].as_str().unwrap_or_default().to_string();
            Some((email.to_string(), s("DisplayName"), s("Availability"), s("UniqueId")))
        })
        .collect()
}

/// The Events form's Add a room: the rooms matching `query` for the
/// event's slot (`start`/`end` "yyyy-MM-dd HH:mm:ss" in the Windows zone
/// `zone`, as Teams sends them).
pub async fn meeting_locations_at(client: &TeamsClient, query: &str, start: &str, end: &str, zone: &str) -> Result<Vec<(String, String, String, String)>> {
    let token = crate::auth::oauth::access_token_for("https://outlook.office.com/.default").await?;
    let resp = client
        .http()
        .post("https://outlook.office.com/SchedulingB2/api/v1.0/me/findmeetinglocations")
        .bearer_auth(token)
        .header("client-request-id", uuid::Uuid::new_v4().to_string())
        .json(&locations_at_body(query, start, end, zone))
        .send()
        .await
        .context("Find meeting locations")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Find meeting locations: HTTP {status}");
    }
    let v: serde_json::Value = resp.json().await.context("Find meeting locations reply")?;
    Ok(locations_at_from(&v))
}

/// Rooms from short profiles: the ones Teams resolved (a known address
/// and an MRI).
pub fn rooms_from_profiles(profiles: &[serde_json::Value]) -> Vec<Room> {
    profiles
        .iter()
        .filter_map(|p| {
            let email = p["email"].as_str().filter(|e| !e.is_empty() && *e != UNKNOWN_EMAIL)?;
            let mri = p["mri"].as_str().filter(|m| !m.is_empty())?;
            Some(Room {
                mri: mri.to_string(),
                name: p["displayName"].as_str().unwrap_or_default().to_string(),
                email: email.to_string(),
            })
        })
        .collect()
}

/// Resolve room addresses to Teams users, as Teams' people service does by
/// mail.
pub async fn resolve(client: &TeamsClient, emails: &[String]) -> Result<Vec<Room>> {
    if emails.is_empty() {
        return Ok(Vec::new());
    }
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!(
            "{base}/beta/users/fetchShortProfile?isMailAddress=true&enableGuest=true&skypeTeamsInfo=true&canBeSmtpAddress=false&includeIBBarredUsers=true&includeDisabledAccounts=true"
        ))
        .bearer_auth(&token)
        .json(emails)
        .send()
        .await?
        .error_for_status()
        .context("Room profiles")?
        .json()
        .await?;
    let mut rooms = rooms_from_profiles(v["value"].as_array().map(Vec::as_slice).unwrap_or_default());
    // In the order the scheduling service gave them.
    rooms.sort_by_key(|r| emails.iter().position(|e| e.eq_ignore_ascii_case(&r.email)).unwrap_or(usize::MAX));
    Ok(rooms)
}

/// Teams' suggested rooms (Other Suggestions), or a search's (10 at most).
pub async fn rooms(client: &TeamsClient, query: Option<&str>) -> Result<Vec<Room>> {
    let emails: Vec<String> = meeting_locations(client, 10, query).await?.into_iter().map(|(e, _)| e).collect();
    resolve(client, &emails).await
}

/// The room's MRI from a Teams Rooms Bluetooth beacon's object id.
pub fn mri_for(object_id: &str) -> String {
    format!("8:orgid:{object_id}")
}

/// Microsoft's Bluetooth company id (Teams' `aB`).
pub const BEACON_COMPANY: u16 = 0x0006;
/// Teams' proximity list cutoff (`bleProximityListRssiCutoffClient`,
/// default -75 dBm) and its adjacent cutoff for Teams Rooms
/// (`adjacentRssiCutoffMTR`, -50 dBm).
pub const PROXIMAL_RSSI: i16 = -75;
pub const ADJACENT_RSSI: i16 = -50;

/// A Teams Rooms device heard over Bluetooth.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Beacon {
    pub mri: String,
    pub rssi: i16,
    /// Teams' proximityValidationCode: what the room accepts as
    /// autoAcceptAuthorization.
    pub code: Option<u16>,
    /// Close enough for Teams to suggest it (`isAdjacent`).
    pub adjacent: bool,
}

/// Teams' `_bookKeepMtr` on a Bluetooth advertisement's Microsoft
/// manufacturer data: `34 F0`, a protocol byte (type << 5 | version: a
/// Teams Rooms device is type 0, version 0), the room account's object id
/// as a packed GUID (Windows byte order), the validation code (big-endian)
/// and the device type. Rooms quieter than the proximity cutoff are left
/// out.
pub fn parse_beacon(company: u16, data: &[u8], rssi: i16) -> Option<Beacon> {
    if company != BEACON_COMPANY || data.len() < 3 + 16 || data[0] != 0x34 || data[1] != 0xF0 {
        return None;
    }
    let (kind, version) = (data[2] >> 5, data[2] & 31);
    if kind != 0 || version > 0 || rssi < PROXIMAL_RSSI {
        return None;
    }
    let g = &data[3..];
    let guid = format!(
        "{:08x}-{:04x}-{:04x}-{:04x}-{:04x}{:04x}{:04x}",
        u32::from_le_bytes([g[0], g[1], g[2], g[3]]),
        u16::from_le_bytes([g[4], g[5]]),
        u16::from_le_bytes([g[6], g[7]]),
        u16::from_be_bytes([g[8], g[9]]),
        u16::from_be_bytes([g[10], g[11]]),
        u16::from_be_bytes([g[12], g[13]]),
        u16::from_be_bytes([g[14], g[15]]),
    );
    let code = (g.len() >= 18).then(|| u16::from_be_bytes([g[16], g[17]]));
    Some(Beacon { mri: mri_for(&guid), rssi, code, adjacent: rssi >= ADJACENT_RSSI })
}

/// What a Teams Rooms device advertises (the inverse of
/// [`parse_beacon`]; Teams Rooms' DevicesBLEService._startAdvertising):
/// Microsoft's manufacturer data `34 F0`, protocol `00`, the room account
/// `object_id` as a packed GUID and the current salt (big-endian), with
/// nothing after it (only a Surface Hub appends `20 00`). `None` for an
/// id that isn't a GUID.
pub fn beacon_data(object_id: &str, code: u16) -> Option<Vec<u8>> {
    let hex: String = object_id.chars().filter(|c| *c != '-').collect();
    if hex.len() != 32 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let raw: Vec<u8> = (0..16).map(|i| u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap_or(0)).collect();
    // A packed GUID: the first three fields little-endian (Windows' order).
    let mut out = vec![0x34, 0xF0, 0x00];
    out.extend([raw[3], raw[2], raw[1], raw[0], raw[5], raw[4], raw[7], raw[6]]);
    out.extend(&raw[8..16]);
    out.extend(code.to_be_bytes());
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_room_advertises_what_teams_reads() {
        let d = beacon_data("42401e65-4053-40ec-a6bf-61be49524ff6", 0x1234).unwrap();
        assert_eq!(
            d,
            [
                0x34, 0xF0, 0x00, 0x65, 0x1e, 0x40, 0x42, 0x53, 0x40, 0xec, 0x40, 0xa6, 0xbf, 0x61, 0xbe, 0x49, 0x52,
                0x4f, 0xf6, 0x12, 0x34
            ]
        );
        let b = parse_beacon(BEACON_COMPANY, &d, -40).unwrap();
        assert_eq!((b.mri.as_str(), b.code), ("8:orgid:42401e65-4053-40ec-a6bf-61be49524ff6", Some(0x1234)));
        assert!(beacon_data("not-a-guid", 1).is_none());
    }

    #[test]
    fn bodies_as_teams_sends_them() {
        assert_eq!(locations_body(10, None).to_string(), r#"{"ConferenceRoomsOnly":true,"MaxCandidates":10}"#);
        let b = locations_body(10, Some("OST"));
        assert_eq!(b["QueryConstraint"]["Query"], "OST");
        assert_eq!(b["LocationProvider"], "80");
    }

    #[test]
    fn parses_a_teams_rooms_beacon() {
        // OST Test Room (42401e65-4053-40ec-a6bf-61be49524ff6), code 0x1234.
        let d = [
            0x34, 0xF0, 0x00, 0x65, 0x1e, 0x40, 0x42, 0x53, 0x40, 0xec, 0x40, 0xa6, 0xbf, 0x61, 0xbe, 0x49, 0x52, 0x4f,
            0xf6, 0x12, 0x34, 0x10,
        ];
        let b = parse_beacon(6, &d, -60).unwrap();
        assert_eq!(b.mri, "8:orgid:42401e65-4053-40ec-a6bf-61be49524ff6");
        assert_eq!((b.code, b.adjacent), (Some(0x1234), false));
        assert!(parse_beacon(6, &d, -45).unwrap().adjacent);
        assert!(parse_beacon(6, &d, -80).is_none());
        assert!(parse_beacon(0x4c, &d, -60).is_none());
        let mut personal = d;
        personal[2] = 1 << 5;
        assert!(parse_beacon(6, &personal, -60).is_none());
    }

    #[test]
    fn parses_locations_and_profiles() {
        let v = serde_json::json!({"MeetingLocations": [
            {"MeetingLocation": {"DisplayName": "OST Test Room", "LocationEmailAddress": "ost-test-room@scnetsolutions.com"}},
            {"MeetingLocation": {"DisplayName": "No mail"}}
        ]});
        assert_eq!(locations_from(&v), vec![("ost-test-room@scnetsolutions.com".into(), "OST Test Room".into())]);
        let p = vec![
            serde_json::json!({"email": "ost-test-room@scnetsolutions.com", "displayName": "OST Test Room", "mri": "8:orgid:42401e65-4053-40ec-a6bf-61be49524ff6"}),
            serde_json::json!({"email": UNKNOWN_EMAIL, "displayName": "?", "mri": "8:orgid:x"}),
        ];
        let r = rooms_from_profiles(&p);
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "OST Test Room");
    }
}
