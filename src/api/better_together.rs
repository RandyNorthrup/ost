//! Teams' Better Together: a Teams phone paired with the desktop
//! (Settings ▸ Devices ▸ Manage devices), as Teams does it. Read from
//! Teams' bundles (its TransportConnectionHandler, TransportCommandRouter
//! and BttDeviceSettings) and its SlimCore Better Together transport
//! ("BTT", SlimCoreWebview2.dll):
//!
//! - **Endpoints.** Each Teams client signed in as the user registers a
//!   Better Together endpoint with the registrar: its calling endpoint id,
//!   reachable on its Trouter socket under the path `bettertogether`.
//!   A phone finds the user's desktops there (the transport's discover).
//! - **Commands.** Both sides POST one JSON message to the other's Trouter
//!   URL: `{registrationId, command, commandSequenceNumber,
//!   commandDetails, transportDetails: {context, endpointType, url},
//!   debugContent: {chainId, causeId}}`. The receiver acknowledges it at
//!   once (HTTP 200 `{}`, or 300 with `{errorCode}` for a command it
//!   won't take), does it, and sends a `response` command back with
//!   `{requestCauseId, statusCode, salt, …}`.
//! - **Proximity.** The phone advertises a Bluetooth LE beacon:
//!   Microsoft's manufacturer data `34 F0 40`, the user's object id, a
//!   salt and its endpoint signature. The desktop scans for it before it
//!   takes a pairing (unless the command carries the salt it last heard,
//!   or the phone is wired), and learns the salt from it.
//! - **Pairing.** The phone sends `pair` with `{deviceName, clientType,
//!   clientVersion, endpointSignature, capabilities, salt}`; the desktop
//!   asks ("Connection request", Connect / Cancel, 50 s), and on Connect keeps the phone as
//!   Connected and answers `{accepted: true, salt}`.
//! - **Manage devices** lists the paired phones (name, "Connected" when
//!   connected) with Disconnect: Teams' unpairDevice sends the phone
//!   `unpair` and forgets it.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// The Trouter path Better Together endpoints listen on (SlimCore's
/// CBTTransportUser registers its listener for it); commands go to
/// `<surl>bettertogether/send`.
pub const TROUTER_PATH: &str = "bettertogether";
/// The registrar transport's context for it (Teams desktop's calling
/// registration carries it as a second Trouter transport).
pub const TRANSPORT_CONTEXT: &str = "BetterTogether";
/// `transportDetails.endpointType` of a Better Together endpoint (a room
/// remote's is `RemoteControl`).
pub const ENDPOINT_TYPE: &str = "BetterTogether";
/// SlimCore's registrar when the Trouter session names none.
pub const REGISTRAR_URL: &str = "https://prod.registrar.skype.com/v2/registrations";

/// The commands of Teams' TransportCommandRouter (its incoming `He` and
/// outgoing `tt` names, lower case on the wire).
pub mod command {
    pub const RESPONSE: &str = "response";
    pub const BROADCAST: &str = "broadcast";
    pub const PAIR: &str = "pair";
    pub const UNPAIR: &str = "unpair";
    pub const AUTOPAIR: &str = "autopair";
    pub const LOCKED: &str = "locked";
    pub const UNLOCKED: &str = "unlocked";
    pub const UPDATE_ENDPOINT: &str = "updateendpoint";
    pub const KEEP_ALIVE: &str = "keepalive";
    pub const LOCK: &str = "lock";
    pub const UNLOCK: &str = "unlock";
}

/// Teams' acknowledgement status codes (TransportCommandRouter's NT/sg).
pub const STATUS_OK: u16 = 200;
pub const STATUS_FAILED: u16 = 300;
pub const STATUS_ERROR: u16 = 400;

/// Teams' error code for a command from a phone that isn't paired (vh).
pub const ERROR_NOT_PAIRED: &str = "DEVICE_NOT_PAIRED";
/// Teams' other error codes (kN, Axe, _N).
pub const ERROR_WRONG_ENDPOINT: &str = "INCORRECT_ENDPOINT_ID";
pub const ERROR_NOT_IN_PROXIMITY: &str = "NOT_IN_PROXIMITY";
pub const ERROR_INVALID_REQUEST: &str = "INVALID_COMMAND_REQUEST";
/// The user turned the pairing down (Teams' RejectedByUser / RejectedByTimeout).
pub const REJECTED_BY_USER: &str = "RejectedByUser";
pub const REJECTED_BY_TIMEOUT: &str = "RejectedByTimeout";

/// How long Teams waits for the user to answer a pairing ($9e).
pub const PAIR_PROMPT_SECS: u64 = 50;
/// Teams' keep-alive period (Y6e) and Bluetooth scan for a phone (X6e).
pub const KEEP_ALIVE_SECS: u64 = 30;
pub const PROXIMITY_SCAN_SECS: u64 = 15;

/// Where a command came from and how to answer it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransportDetails {
    #[serde(default)]
    pub context: String,
    #[serde(default)]
    pub endpoint_type: String,
    #[serde(default)]
    pub url: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DebugContent {
    #[serde(default)]
    pub chain_id: String,
    #[serde(default)]
    pub cause_id: String,
}

/// One Better Together message (SlimCore's command request).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Message {
    /// The sender's endpoint id.
    #[serde(default)]
    pub registration_id: String,
    #[serde(default)]
    pub command: String,
    #[serde(default)]
    pub command_sequence_number: u64,
    /// The command's details, a JSON text (Teams' JS hands SlimCore the
    /// stringified details and parses them back on receipt).
    #[serde(default, deserialize_with = "text_or_json")]
    pub command_details: String,
    #[serde(default)]
    pub transport_details: TransportDetails,
    #[serde(default)]
    pub debug_content: DebugContent,
}

fn text_or_json<'de, D: serde::Deserializer<'de>>(d: D) -> std::result::Result<String, D::Error> {
    let v = serde_json::Value::deserialize(d)?;
    Ok(match v {
        serde_json::Value::String(s) => s,
        serde_json::Value::Null => String::new(),
        other => other.to_string(),
    })
}

impl Message {
    /// The details as JSON (an empty object when there are none).
    pub fn details(&self) -> serde_json::Value {
        serde_json::from_str(&self.command_details).unwrap_or_else(|_| serde_json::json!({}))
    }

    /// The command, lower case (Teams lower-cases what it receives).
    pub fn name(&self) -> String {
        self.command.to_ascii_lowercase()
    }

    pub fn cause_id(&self) -> &str {
        &self.debug_content.cause_id
    }
}

/// This endpoint, as it signs the messages it sends.
#[derive(Debug, Clone, Default)]
pub struct Endpoint {
    /// The calling endpoint id (Teams' getRegistrationId).
    pub id: String,
    /// Its Better Together Trouter URL (`<surl>bettertogether`).
    pub url: String,
}

impl Endpoint {
    pub fn from_surl(id: &str, surl: &str) -> Self {
        Self {
            id: id.to_string(),
            url: trouter_url(surl),
        }
    }

    /// A message from this endpoint.
    pub fn message(&self, command: &str, details: &serde_json::Value, seq: u64) -> Message {
        Message {
            registration_id: self.id.clone(),
            command: command.to_string(),
            command_sequence_number: seq,
            command_details: details.to_string(),
            transport_details: TransportDetails {
                context: String::new(),
                endpoint_type: ENDPOINT_TYPE.to_string(),
                url: self.url.clone(),
            },
            debug_content: DebugContent {
                chain_id: uuid::Uuid::new_v4().to_string(),
                cause_id: uuid::Uuid::new_v4().to_string(),
            },
        }
    }
}

/// The Better Together URL on a Trouter socket, as Teams registers it: the
/// socket's address on Trouter's user-token front (`-t` host, port 443;
/// the `-f` service front at 3443 turns a Skype token away with 401) and
/// the path `bettertogether/send`.
pub fn trouter_url(surl: &str) -> String {
    let base = surl
        .trim_end_matches('/')
        .replacen("-f.trouter.", "-t.trouter.", 1)
        .replacen(":3443/", ":443/", 1);
    format!("{base}/{TROUTER_PATH}/send")
}

/// Whether a pushed request's URL is a Better Together command.
pub fn is_trouter_url(url: &str) -> bool {
    let path = url.split(['?', '#']).next().unwrap_or_default();
    path.trim_end_matches('/')
        .split('/')
        .any(|seg| seg == TROUTER_PATH)
}

// ---- Paired devices ----

/// Teams' connection type (`Ol`): over Bluetooth, or a USB-C cable
/// (`WIRED_CONNECTION` in the phone's capabilities).
pub const CONNECTION_BLUETOOTH: u8 = 0;
pub const CONNECTION_WIRED: u8 = 1;
/// Teams' connection status (`kl`).
pub const STATUS_CONNECTED: u8 = 0;
pub const STATUS_PAIRED_NOT_CONNECTED: u8 = 1;
pub const STATUS_LOCKED: u8 = 2;

/// A paired phone, with Teams' field names (its BetterTogetherPairedDevice).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PairedDevice {
    #[serde(rename = "endPointId")]
    pub end_point_id: String,
    #[serde(default)]
    pub device_name: String,
    #[serde(default)]
    pub client_type: String,
    #[serde(default)]
    pub client_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub endpoint_signature: Option<i64>,
    #[serde(default)]
    pub connection_type: u8,
    /// Not stored: Teams strips it and starts every device disconnected.
    #[serde(default = "not_connected", skip_serializing)]
    pub connection_status: u8,
}

fn not_connected() -> u8 {
    STATUS_PAIRED_NOT_CONNECTED
}

impl PairedDevice {
    /// The device a `pair` command describes, Connected (Teams'
    /// onUserResponse on Pair).
    pub fn from_pair(endpoint_id: &str, details: &serde_json::Value) -> Self {
        let s = |k: &str| {
            details
                .get(k)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        Self {
            end_point_id: endpoint_id.to_string(),
            device_name: s("deviceName"),
            client_type: s("clientType"),
            client_version: s("clientVersion"),
            endpoint_signature: details.get("endpointSignature").and_then(|v| v.as_i64()),
            connection_type: connection_type(details),
            connection_status: STATUS_CONNECTED,
        }
    }

    pub fn connected(&self) -> bool {
        self.connection_status == STATUS_CONNECTED
    }
}

/// Teams' `bo`: wired when the phone's capabilities say so.
pub fn connection_type(details: &serde_json::Value) -> u8 {
    let wired = details
        .get("capabilities")
        .and_then(|c| c.as_array())
        .is_some_and(|c| c.iter().any(|x| x.as_str() == Some("WIRED_CONNECTION")));
    if wired {
        CONNECTION_WIRED
    } else {
        CONNECTION_BLUETOOTH
    }
}

/// The stored list (Teams' `BTPairedDevices`), every device disconnected.
pub fn load_devices(json: &str) -> Vec<PairedDevice> {
    let mut v: Vec<PairedDevice> = serde_json::from_str(json).unwrap_or_default();
    for d in &mut v {
        d.connection_status = STATUS_PAIRED_NOT_CONNECTED;
    }
    v
}

/// The list as Teams stores it (without the connection status).
pub fn store_devices(devices: &[PairedDevice]) -> String {
    serde_json::to_string(devices).unwrap_or_else(|_| "[]".into())
}

/// Teams' verifySalt: a command proves the phone is near when it carries
/// the salt the desktop last heard from it.
pub fn salt_matches(details: &serde_json::Value, current: u16) -> bool {
    details
        .get("salt")
        .and_then(|s| s.as_array())
        .is_some_and(|s| {
            s.iter()
                .take(2)
                .any(|x| x.as_u64() == Some(u64::from(current)))
        })
}

// ---- The phone's beacon ----

/// Microsoft's Bluetooth company id and Teams' beacon kinds (`hjV`).
pub const BEACON_COMPANY: u16 = 0x0006;
pub const KIND_ROOM: u8 = 0;
pub const KIND_COMPANION: u8 = 2;
/// Teams' companion cut-off (eU).
pub const COMPANION_RSSI: i16 = -75;

/// A Teams phone heard over Bluetooth.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Companion {
    /// The signed-in user's object id.
    pub oid: String,
    /// The phone's current salt (Teams' retrieveSaltFromData).
    pub salt: Option<u16>,
    /// Bytes 19-20: the endpoint signature (little-endian), or the
    /// endpoint id's last two bytes.
    pub tail: Option<[u8; 2]>,
    pub rssi: i16,
}

impl Companion {
    pub fn signature(&self) -> Option<i16> {
        self.tail.map(i16::from_le_bytes)
    }

    /// Teams' hasEndpointsMatched for one endpoint.
    pub fn matches(&self, endpoint_id: &str, signature: Option<i64>) -> bool {
        let Some(tail) = self.tail else { return false };
        if let Some(sig) = signature
            && i64::from(i16::from_le_bytes(tail)) == sig
        {
            return true;
        }
        let raw = guid_bytes(endpoint_id);
        raw.len() == 16 && tail[0] == raw[15] && tail[1] == raw[14]
    }
}

fn guid_bytes(id: &str) -> Vec<u8> {
    let hex: String = id.chars().filter(|c| *c != '-').collect();
    if hex.len() != 32 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Vec::new();
    }
    (0..16)
        .map(|i| u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap_or(0))
        .collect()
}

/// A GUID packed as Windows does (first three fields little-endian).
fn packed_guid(id: &str) -> Option<[u8; 16]> {
    let r = guid_bytes(id);
    if r.len() != 16 {
        return None;
    }
    let mut out = [0u8; 16];
    out[..8].copy_from_slice(&[r[3], r[2], r[1], r[0], r[5], r[4], r[7], r[6]]);
    out[8..].copy_from_slice(&r[8..]);
    Some(out)
}

fn unpacked_guid(g: &[u8]) -> String {
    format!(
        "{:08x}-{:04x}-{:04x}-{:04x}-{:04x}{:04x}{:04x}",
        u32::from_le_bytes([g[0], g[1], g[2], g[3]]),
        u16::from_le_bytes([g[4], g[5]]),
        u16::from_le_bytes([g[6], g[7]]),
        u16::from_be_bytes([g[8], g[9]]),
        u16::from_be_bytes([g[10], g[11]]),
        u16::from_be_bytes([g[12], g[13]]),
        u16::from_be_bytes([g[14], g[15]]),
    )
}

/// Teams' BluetoothLEService for a phone: the manufacturer data `34 F0`,
/// a kind/version byte, then the payload: the user's packed object id,
/// one byte, the salt (bytes 17-18, little-endian) and the signature
/// (19-20). Teams books a companion from a companion beacon or a room's
/// (kind 0 or 2, version 0), heard at -75 dBm or better.
pub fn parse_companion(company: u16, data: &[u8], rssi: i16) -> Option<Companion> {
    if company != BEACON_COMPANY || data.len() < 3 + 16 || data[0] != 0x34 || data[1] != 0xF0 {
        return None;
    }
    let (kind, version) = (data[2] >> 5, data[2] & 31);
    if !(kind == KIND_COMPANION || kind == KIND_ROOM) || version > 0 || rssi < COMPANION_RSSI {
        return None;
    }
    let o = &data[3..];
    Some(Companion {
        oid: unpacked_guid(&o[..16]),
        salt: (o.len() > 18).then(|| u16::from(o[18]) << 8 | u16::from(o[17])),
        tail: (o.len() > 20).then(|| [o[19], o[20]]),
        rssi,
    })
}

/// What a Teams phone advertises (the inverse of [`parse_companion`]).
pub fn companion_beacon(oid: &str, salt: u16, signature: i16) -> Option<Vec<u8>> {
    let g = packed_guid(oid)?;
    let mut out = vec![0x34, 0xF0, KIND_COMPANION << 5];
    out.extend(g);
    out.push(0);
    out.extend(salt.to_le_bytes());
    out.extend(signature.to_le_bytes());
    Some(out)
}

// ---- The transport ----

/// The OS name Teams shows phones for this PC (platformDetectService.getOS).
pub fn os_name() -> &'static str {
    match std::env::consts::OS {
        "windows" => "Windows",
        "macos" => "Mac",
        _ => "Linux",
    }
}

/// Another Better Together endpoint of the user, as the registrar lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Peer {
    pub id: String,
    pub url: String,
    pub app_id: String,
    pub platform: String,
}

/// The user's Better Together endpoints in a registrar listing
/// (`{bindings: [...]}`): each registration with a Trouter transport whose
/// context is `BetterTogether` (or whose path is a `bettertogether` one).
pub fn peers_in(listing: &serde_json::Value) -> Vec<Peer> {
    let regs = ["bindings", "registrations"]
        .iter()
        .find_map(|k| listing.get(*k).and_then(|r| r.as_array()).cloned())
        .or_else(|| listing.as_array().cloned())
        .unwrap_or_default();
    let mut out = Vec::new();
    for r in regs {
        let id = r
            .get("registrationId")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let cd = r.get("clientDescription").cloned().unwrap_or_default();
        let transports = r
            .get("transports")
            .and_then(|t| t.as_object())
            .and_then(|t| {
                t.iter()
                    .find(|(k, _)| k.eq_ignore_ascii_case("trouter"))
                    .map(|(_, v)| v.clone())
            })
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default();
        for t in transports {
            let path = t.get("path").and_then(|v| v.as_str()).unwrap_or_default();
            let context = t
                .get("context")
                .and_then(|v| v.as_str())
                .unwrap_or_default();
            if (context == TRANSPORT_CONTEXT || is_trouter_url(path))
                && !id.is_empty()
                && !path.is_empty()
            {
                out.push(Peer {
                    id: id.to_string(),
                    url: path.to_string(),
                    app_id: cd
                        .get("appId")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    platform: cd
                        .get("platform")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                });
            }
        }
    }
    out
}

/// The user's Better Together endpoints (the transport's discover).
pub async fn discover(
    http: &reqwest::Client,
    skype_token: &str,
    registrar_url: &str,
) -> Result<Vec<Peer>> {
    let r = http
        .get(registrar_url.trim_end_matches('/'))
        .header("X-Skypetoken", skype_token)
        .send()
        .await
        .context("Better Together discover")?;
    let status = r.status();
    let text = r.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("Better Together discover returned {status}");
    }
    let v: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    Ok(peers_in(&v))
}

/// Send one command to a peer's URL; the answer is the peer's
/// acknowledgement (its status and body).
pub async fn send(
    http: &reqwest::Client,
    skype_token: &str,
    url: &str,
    msg: &Message,
) -> Result<(u16, String)> {
    let r = http
        .post(url)
        .header("X-Skypetoken", skype_token)
        .header("MS-CV", format!("{}.1", uuid::Uuid::new_v4().simple()))
        .header("X-Microsoft-Skype-Chain-ID", &msg.debug_content.chain_id)
        .header(
            "X-Microsoft-Skype-Message-ID",
            uuid::Uuid::new_v4().to_string(),
        )
        .header("Content-Type", "application/json")
        .body(serde_json::to_string(msg)?)
        .send()
        .await
        .with_context(|| format!("Better Together {}", msg.command))?;
    let status = r.status().as_u16();
    let body = r.text().await.unwrap_or_default();
    Ok((status, body))
}

/// The `response` a command's receiver sends back: its result fields plus
/// Teams' `requestCauseId` and `statusCode`.
pub fn response_details(
    request: &Message,
    ok: bool,
    mut result: serde_json::Value,
) -> serde_json::Value {
    if !result.is_object() {
        result = serde_json::json!({});
    }
    result["requestCauseId"] = request.cause_id().into();
    result["statusCode"] = if ok { STATUS_OK } else { STATUS_ERROR }.into();
    result
}

// ---- What the desktop's Trouter socket answers at once ----

static PAIRED: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

/// The paired phones' endpoint ids, for the socket's acknowledgements.
pub fn set_paired_ids(ids: Vec<String>) {
    *PAIRED.lock().unwrap_or_else(|e| e.into_inner()) = ids;
}

/// Teams' acknowledgement of a command (TransportCommandRouter's
/// validateIncomingCommand and shouldCreateCommand): 200 `{}` when it
/// takes it, 300 `{errorCode}` when it's from a phone that isn't paired
/// (only broadcast, pair, autopair and log uploads come from strangers).
pub fn acknowledgement(body: &str, own_endpoint: Option<&str>) -> (u16, String) {
    let Ok(msg) = serde_json::from_str::<Message>(body) else {
        return (
            STATUS_FAILED,
            serde_json::json!({"errorCode": ERROR_INVALID_REQUEST}).to_string(),
        );
    };
    let details = msg.details();
    if let (Some(target), Some(own)) = (
        details.get("targetEndpointId").and_then(|v| v.as_str()),
        own_endpoint,
    ) && !target.is_empty()
        && target != own
    {
        return (
            STATUS_FAILED,
            serde_json::json!({"errorCode": ERROR_WRONG_ENDPOINT}).to_string(),
        );
    }
    let open = [
        command::RESPONSE,
        command::BROADCAST,
        command::PAIR,
        command::AUTOPAIR,
        "uploadbettertogetherlogs",
    ];
    let name = msg.name();
    let paired = PAIRED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .contains(&msg.registration_id);
    if !open.contains(&name.as_str()) && !paired {
        return (
            STATUS_FAILED,
            serde_json::json!({"errorCode": ERROR_NOT_PAIRED}).to_string(),
        );
    }
    (STATUS_OK, "{}".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_phone_beacon_reads_back() {
        let oid = "42401e65-4053-40ec-a6bf-61be49524ff6";
        let d = companion_beacon(oid, 0x1234, -2).unwrap();
        assert_eq!(&d[..3], &[0x34, 0xF0, 0x40]);
        assert_eq!(d.len(), 3 + 21);
        let c = parse_companion(BEACON_COMPANY, &d, -60).unwrap();
        assert_eq!(c.oid, oid);
        assert_eq!(c.salt, Some(0x1234));
        assert_eq!(c.signature(), Some(-2));
        assert!(c.matches("anything", Some(-2)));
        assert!(!c.matches("anything", Some(5)));
        // Too far away for Teams.
        assert!(parse_companion(BEACON_COMPANY, &d, -80).is_none());
    }

    #[test]
    fn an_endpoint_id_matches_by_its_last_bytes() {
        let id = "0b9c1a2e-1111-2222-3333-4455667788aa";
        let mut d = companion_beacon("42401e65-4053-40ec-a6bf-61be49524ff6", 1, 0).unwrap();
        let n = d.len();
        d[n - 2] = 0xaa;
        d[n - 1] = 0x88;
        let c = parse_companion(BEACON_COMPANY, &d, -40).unwrap();
        assert!(c.matches(id, None));
        assert!(!c.matches("0b9c1a2e-1111-2222-3333-445566778800", None));
    }

    #[test]
    fn messages_carry_details_as_text() {
        let ep = Endpoint::from_surl("ep-1", "https://t.example/v4/f/abc/");
        assert_eq!(ep.url, "https://t.example/v4/f/abc/bettertogether/send");
        let m = ep.message(
            command::PAIR,
            &serde_json::json!({"deviceName": "Phone"}),
            3,
        );
        let v = serde_json::to_value(&m).unwrap();
        assert_eq!(v["commandDetails"], "{\"deviceName\":\"Phone\"}");
        assert_eq!(v["transportDetails"]["endpointType"], "BetterTogether");
        assert_eq!(v["commandSequenceNumber"], 3);
        // An object is taken too.
        let back: Message = serde_json::from_str(
            r#"{"registrationId":"p","command":"Pair","commandDetails":{"deviceName":"X"},"debugContent":{"causeId":"c"}}"#,
        )
        .unwrap();
        assert_eq!(back.name(), "pair");
        assert_eq!(back.details()["deviceName"], "X");
        assert_eq!(back.cause_id(), "c");
        assert!(is_trouter_url(
            "https://t.example/v4/f/abc/bettertogether/send"
        ));
        assert!(!is_trouter_url(
            "https://t.example/v4/f/abc/NGCallManagerWin"
        ));
    }

    #[test]
    fn pairing_and_storing_as_teams() {
        let d = serde_json::json!({"deviceName": "Yealink MP56", "clientType": "ipphone", "clientVersion": "1.0",
            "endpointSignature": 1234, "capabilities": ["WIRED_CONNECTION"], "salt": [7]});
        let dev = PairedDevice::from_pair("ep-phone", &d);
        assert!(dev.connected());
        assert_eq!(dev.connection_type, CONNECTION_WIRED);
        assert!(salt_matches(&d, 7));
        assert!(!salt_matches(&d, 8));
        let stored = store_devices(std::slice::from_ref(&dev));
        assert!(!stored.contains("connectionStatus"));
        assert!(stored.contains("\"endPointId\":\"ep-phone\""));
        let back = load_devices(&stored);
        assert_eq!(back[0].connection_status, STATUS_PAIRED_NOT_CONNECTED);
        assert_eq!(back[0].device_name, "Yealink MP56");
    }

    #[test]
    fn strangers_may_only_pair() {
        set_paired_ids(vec!["known".into()]);
        let m = |from: &str, cmd: &str| {
            serde_json::to_string(&Message {
                registration_id: from.into(),
                command: cmd.into(),
                ..Default::default()
            })
            .unwrap()
        };
        assert_eq!(acknowledgement(&m("stranger", "pair"), None).0, STATUS_OK);
        assert_eq!(
            acknowledgement(&m("stranger", "keepalive"), None).0,
            STATUS_FAILED
        );
        assert_eq!(acknowledgement(&m("known", "unpair"), None).0, STATUS_OK);
        set_paired_ids(Vec::new());
    }

    #[test]
    fn registrar_listing_names_the_phones() {
        // As the registrar lists Teams desktop (2026-11-21): its calling
        // registration with a second, BetterTogether, transport.
        let v = serde_json::json!({"bindings": [
            {"registrationId": "pc", "clientDescription": {"appId": "NextGenCalling", "platform": "49/26304"},
             "transports": {"trouter": [
                {"context": "", "path": "https://t:3443/v3/f/a/NGCallManagerWin"},
                {"context": "BetterTogether", "path": "https://t:443/v3/f/a/bettertogether/send"}]}},
            {"registrationId": "chat", "transports": {"trouter": [{"context": "", "path": "https://t/v4/f/a/"}]}}
        ]});
        let p = peers_in(&v);
        assert_eq!(p.len(), 1);
        assert_eq!(
            (p[0].id.as_str(), p[0].app_id.as_str()),
            ("pc", "NextGenCalling")
        );
        assert!(p[0].url.ends_with("/bettertogether/send"));
    }
}
