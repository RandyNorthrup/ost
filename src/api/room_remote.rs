//! Teams' room remote ("Control Room System" on a Teams Room's menu in a
//! meeting): a meeting attendee near the room controls it from their own
//! Teams. Read from Teams' bundles (its RemoteControllerSessionManager,
//! RemoteControllerConnectionHandler, the room's
//! RemoteControllerIncomingCommandFactory and RemoteControllerCallState)
//! and SlimCore's Better Together sessions (CBTSession, CBTTransportUser):
//!
//! - **Session.** The controller asks the call controller for a session
//!   with the room's account (`POST cc/v1/sessions`, a `sessionInvitation`
//!   of type `roomControls`); the service pushes it to the room's calling
//!   endpoints as event 122 (`sessionNotification` with `accept` and
//!   `reject` links, the controller's endpoint id and the meeting's
//!   thread). A room in that meeting accepts (`sessionAcceptance` with its
//!   own `receive` and `end` links).
//! - **Pairing.** The controller scans for the room's Bluetooth beacon and
//!   sends `pair` with the beacon's salt; the room checks the salt and
//!   answers with its name, its supported controls and its state.
//! - **Commands.** `mute`/`unmute`, `cameraOn`/`cameraOff`,
//!   `captionsOn`/`captionsOff`, `volumeUp`/`volumeDown`, the stage
//!   layouts and `leaveMeeting`; the room tells the controller of state and
//!   capability changes (`stateUpdate`, `capabilityUpdate`).

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// The calling push event of an incoming Better Together session (Teams'
/// `LU.IncomingSession`).
pub const EVENT_INCOMING_SESSION: u64 = 122;
/// The session type of a room remote (SlimCore's sessionType 1).
pub const SESSION_TYPE: &str = "roomControls";
/// The first command of a session (`command` of the push).
pub const SESSION_START: &str = "sessionStart";
/// Where sessions are made (SlimCore's callControllerServiceUrl +
/// `cc/v1/sessions`).
pub const SESSIONS_URL: &str =
    "https://api.flightproxy.teams.microsoft.com/api/v2/ep/api.cc.skype.com/cc/v1/sessions";

/// A session pushed to the room (event 122).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct IncomingSession {
    /// The controller's user (MRI).
    pub from: String,
    /// Who it's for (the room's MRI).
    pub to: String,
    pub accept: String,
    pub reject: String,
    /// The controller's endpoint id.
    pub controller_endpoint: String,
    pub command: String,
    /// The meeting's chat the controller is in.
    pub thread_id: String,
    pub chain_id: String,
    pub cause_id: String,
}

/// Read a calling push as an incoming session (the push already unwrapped
/// from its `{evt, cp}` envelope).
pub fn incoming_session(json: &str) -> Option<IncomingSession> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let n = v.get("sessionNotification")?;
    let s = |p: &str| {
        v.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let details = match v.get("commandDetails") {
        Some(serde_json::Value::String(t)) => serde_json::from_str(t).unwrap_or_default(),
        Some(d) => d.clone(),
        None => serde_json::Value::Null,
    };
    Some(IncomingSession {
        from: n
            .pointer("/from/id")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        to: n
            .pointer("/to/id")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        accept: n
            .pointer("/links/accept")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        reject: n
            .pointer("/links/reject")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        controller_endpoint: s("/registrationId"),
        command: s("/command"),
        thread_id: details
            .pointer("/meetingInfo/threadId")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        chain_id: s("/debugContent/chainId"),
        cause_id: s("/debugContent/causeId"),
    })
}

/// Teams' ids for its debug content (`t` + a GUID).
pub fn teams_id() -> String {
    format!("t{}", uuid::Uuid::new_v4())
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Debug {
    pub chain_id: String,
    pub cause_id: String,
}

/// POST a session request to a service link with the user's Skype token;
/// the reply's status and body.
pub async fn post(
    http: &reqwest::Client,
    skype_token: &str,
    url: &str,
    body: &serde_json::Value,
    chain: &str,
) -> Result<(u16, String)> {
    send(http, reqwest::Method::POST, skype_token, url, body, chain).await
}

/// A session request with the given method.
pub async fn send(
    http: &reqwest::Client,
    method: reqwest::Method,
    skype_token: &str,
    url: &str,
    body: &serde_json::Value,
    chain: &str,
) -> Result<(u16, String)> {
    if !crate::calling::incoming::is_service_link(url) {
        bail!("room remote: not a Teams service link");
    }
    let r = http
        .request(method, url)
        .header("X-Skypetoken", skype_token)
        .header("X-Microsoft-Skype-Chain-ID", chain)
        .header("MS-CV", format!("{}.1", uuid::Uuid::new_v4().simple()))
        .header("Content-Type", "application/json")
        .json(body)
        .send()
        .await
        .context("room remote request")?;
    let status = r.status().as_u16();
    let text = r.text().await.unwrap_or_default();
    Ok((status, text))
}

/// One message on a session, as the call controller relays it (Teams'
/// pair arrived so): the sender's endpoint, the command, its details as
/// an object, and Teams' debug content (a fresh cause id, the session's
/// chain).
pub fn session_message(
    endpoint: &str,
    command: &str,
    details: &serde_json::Value,
    seq: u64,
    chain: &str,
) -> serde_json::Value {
    serde_json::json!({
        "registrationId": endpoint,
        "command": command,
        "commandSequenceNumber": seq,
        "commandDetails": details,
        "debugContent": { "causeId": uuid::Uuid::new_v4().to_string(), "chainId": chain },
    })
}

/// Ending a session (SlimCore's sendEndRequest, as the room got Teams'
/// end relayed: the user ended it, no error).
pub fn end_body(endpoint: &str, seq: u64, debug: &Debug) -> serde_json::Value {
    serde_json::json!({
        "registrationId": endpoint,
        "commandSequenceNumber": seq,
        "debugContent": debug,
        "sessionEnd": { "code": 0, "subCode": 0, "phrase": "Local User Terminated", "reason": "noError" },
    })
}

/// The room's acceptance of a session (SlimCore's sendAcceptRequest):
/// where the controller reaches it (`receive`) and where the session's end
/// is told (`end`).
pub fn acceptance_body(
    receive: &str,
    end: &str,
    endpoint: &str,
    debug: &Debug,
) -> serde_json::Value {
    serde_json::json!({
        "debugContent": debug,
        "registrationId": endpoint,
        "sessionAcceptance": { "links": { "receive": receive, "end": end } }
    })
}

/// The controller's session request (SlimCore's sendStartRequest): who
/// asks (`from`, with its endpoint), the room (`to`), the session type and
/// the controller's links, plus the first command (`sessionStart`) with the
/// meeting's chat, which the service hands the room.
#[allow(clippy::too_many_arguments)]
pub fn invitation_body(
    me_mri: &str,
    me_name: &str,
    me_endpoint: &str,
    room_mri: &str,
    links: &SessionLinks,
    thread_id: &str,
    debug: &Debug,
) -> serde_json::Value {
    serde_json::json!({
        "sessionInvitation": {
            "from": { "id": me_mri, "displayName": me_name, "endpointId": me_endpoint },
            "to": { "id": room_mri },
            "sessionType": SESSION_TYPE,
            "links": {
                "acceptance": links.acceptance,
                "rejection": links.rejection,
                "receive": links.receive,
                "end": links.end,
            }
        },
        "debugContent": debug,
        "registrationId": me_endpoint,
        "commandSequenceNumber": 1,
        "command": SESSION_START,
        "commandDetails": { "meetingInfo": { "threadId": thread_id } },
    })
}

/// A controller's links for one session.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SessionLinks {
    pub acceptance: String,
    pub rejection: String,
    pub receive: String,
    pub end: String,
}

impl SessionLinks {
    pub fn on(surl: &str, session: &str) -> Self {
        Self {
            acceptance: session_link(surl, session, "acceptance"),
            rejection: session_link(surl, session, "rejection"),
            receive: session_link(surl, session, "receive"),
            end: session_link(surl, session, "end"),
        }
    }
}

/// Our Trouter links for one session:
/// `<surl>bettertogether/session/<id>/<what>`. The call controller posts to
/// them (it relays the session's messages), so they stay on the socket's
/// service front, as call callbacks do.
pub fn session_link(surl: &str, session: &str, what: &str) -> String {
    format!(
        "{}/{}/session/{session}/{what}",
        surl.trim_end_matches('/'),
        super::better_together::TROUTER_PATH
    )
}

/// The commands of a room remote (Teams' `He` names; compared lower case).
pub mod command {
    pub const PAIR: &str = "pair";
    pub const UNPAIR: &str = "unpair";
    pub const RESPONSE: &str = "response";
    pub const MUTE: &str = "mute";
    pub const UNMUTE: &str = "unmute";
    pub const CAMERA_ON: &str = "cameraOn";
    pub const CAMERA_OFF: &str = "cameraOff";
    pub const VOLUME_UP: &str = "volumeUp";
    pub const VOLUME_DOWN: &str = "volumeDown";
    pub const CAPTIONS_ON: &str = "captionsOn";
    pub const CAPTIONS_OFF: &str = "captionsOff";
    pub const LEAVE_MEETING: &str = "leaveMeeting";
    pub const STATE_UPDATE: &str = "stateUpdate";
    pub const CAPABILITY_UPDATE: &str = "capabilityUpdate";
}

/// The stage layouts (Teams' `Kt`), in the order Teams lists them.
pub mod layout {
    pub const GALLERY: &str = "showVideoGallery";
    pub const MIXED_GRID: &str = "showMixedGrid";
    pub const PRIORITIZE_VIDEO: &str = "showPrioritizeVideoView";
    pub const CONTENT: &str = "showContent";
    pub const CONTENT_AND_GALLERY: &str = "showVideoGalleryAndContent";
    pub const LARGE_GALLERY: &str = "showLargeGallery";
    pub const TOGETHER: &str = "showTogether";
    pub const FRONT_ROW: &str = "showFrontRow";
    pub const ALL: [&str; 8] = [
        GALLERY,
        MIXED_GRID,
        PRIORITIZE_VIDEO,
        CONTENT,
        CONTENT_AND_GALLERY,
        LARGE_GALLERY,
        TOGETHER,
        FRONT_ROW,
    ];
}

/// The media controls (Teams' `Is`).
pub mod control {
    pub const MUTE: &str = "toggleMute";
    pub const CAMERA: &str = "toggleCamera";
    pub const CAPTIONS: &str = "toggleCaptions";
    pub const VOLUME: &str = "volume";
    pub const LEAVE: &str = "leaveMeeting";
}

/// Teams' error codes for the remote's error dialogs (`To`).
pub mod error {
    pub const OUT_OF_PROXIMITY: u8 = 0;
    pub const CONNECTION_FAILED: u8 = 1;
    pub const DISCONNECTED: u8 = 2;
    pub const COMMAND_FAILED: u8 = 3;
    pub const PAIRING_FAILED: u8 = 4;
}

/// What the room's controls show (Teams Rooms' RemoteControllerCallState
/// `state`): its mic muted, camera and captions on, and the stage layout.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RoomState {
    pub muted: bool,
    pub camera: bool,
    pub captions: bool,
    pub layout: String,
}

impl RoomState {
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "toggleMute": self.muted,
            "toggleCamera": self.camera,
            "toggleCaptions": self.captions,
            "stageLayout": self.layout,
        })
    }

    pub fn from_json(v: &serde_json::Value) -> Self {
        let b = |k: &str| {
            v.get(k)
                .and_then(|x| x.as_bool().or_else(|| x.as_str().map(|s| s == "true")))
                .unwrap_or(false)
        };
        Self {
            muted: b("toggleMute"),
            camera: b("toggleCamera"),
            captions: b("toggleCaptions"),
            layout: v
                .get("stageLayout")
                .and_then(|x| x.as_str())
                .unwrap_or_default()
                .to_string(),
        }
    }
}

/// What the room lets a remote do (`supportedCapabilities`): the media
/// controls (volume always), the stage layouts and the meeting controls
/// (leave always).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Capabilities {
    pub mute: bool,
    pub camera: bool,
    pub captions: bool,
    pub layouts: Vec<String>,
}

impl Capabilities {
    pub fn media(&self) -> Vec<&'static str> {
        let mut m = Vec::new();
        if self.mute {
            m.push(control::MUTE);
        }
        if self.camera {
            m.push(control::CAMERA);
        }
        if self.captions {
            m.push(control::CAPTIONS);
        }
        m.push(control::VOLUME);
        m
    }

    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "mediaControls": self.media(),
            "stageLayoutControls": self.layouts,
            "meetingControls": [control::LEAVE],
        })
    }

    pub fn from_json(v: &serde_json::Value) -> Self {
        let list = |k: &str| -> Vec<String> {
            v.get(k)
                .and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|s| s.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default()
        };
        let media = list("mediaControls");
        Self {
            mute: media.iter().any(|m| m == control::MUTE),
            camera: media.iter().any(|m| m == control::CAMERA),
            captions: media.iter().any(|m| m == control::CAPTIONS),
            layouts: list("stageLayoutControls"),
        }
    }

    /// Teams Rooms' capabilityUpdate between two sets: "enable" /
    /// "disable" per media control that changed, and the whole layout list
    /// when it changed. None when nothing did.
    pub fn update_from(&self, before: &Capabilities) -> Option<serde_json::Value> {
        let mut u = serde_json::Map::new();
        let flag = |on: bool| if on { "enable" } else { "disable" };
        if self.camera != before.camera {
            u.insert(control::CAMERA.into(), flag(self.camera).into());
        }
        if self.mute != before.mute {
            u.insert(control::MUTE.into(), flag(self.mute).into());
        }
        if self.captions != before.captions {
            u.insert(control::CAPTIONS.into(), flag(self.captions).into());
        }
        if self.layouts != before.layouts {
            u.insert(
                "stageLayoutControls".into(),
                serde_json::json!(self.layouts),
            );
        }
        (!u.is_empty()).then_some(serde_json::Value::Object(u))
    }

    /// A remote's copy after a capabilityUpdate (Teams'
    /// RemoteControllerCapabilitiesUpdateCommand).
    pub fn apply(&mut self, update: &serde_json::Value) {
        let on = |k: &str| {
            update
                .get(k)
                .and_then(|v| v.as_str())
                .map(|s| s != "disable")
        };
        if let Some(v) = on(control::CAMERA) {
            self.camera = v;
        }
        if let Some(v) = on(control::MUTE) {
            self.mute = v;
        }
        if let Some(v) = on(control::CAPTIONS) {
            self.captions = v;
        }
        if let Some(l) = update.get("stageLayoutControls").and_then(|x| x.as_array()) {
            self.layouts = l
                .iter()
                .filter_map(|s| s.as_str().map(str::to_string))
                .collect();
        }
    }
}

/// Teams Rooms' VolumeCommand step (0-100): up to the next ten, down to
/// the ten before (a full ten down from a multiple of ten), never below 1.
pub fn volume_step(now: i32, up: bool) -> i32 {
    const STEP: i32 = 10;
    let next = if up {
        now + (STEP - now.rem_euclid(STEP))
    } else {
        let d = if now % STEP != 0 { now % STEP } else { STEP };
        (now - d).max(1)
    };
    next.clamp(1, 100)
}

/// Who answers a pairing (Teams Rooms' buildPairResponse
/// `roomEndpointInfo`).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RoomInfo {
    pub client_type: String,
    pub client_version: String,
    pub device_name: String,
    pub endpoint_id: String,
    pub user_display_name: String,
    pub user_object_id: String,
}

/// The room's answer to `pair` (merged into its `response`).
pub fn pair_result(info: &RoomInfo, caps: &Capabilities, state: &RoomState) -> serde_json::Value {
    serde_json::json!({
        "accepted": true,
        "roomEndpointInfo": {
            "clientType": info.client_type,
            "clientVersion": info.client_version,
            "deviceName": info.device_name,
            "endpointId": info.endpoint_id,
            "userDisplayName": info.user_display_name,
            "userObjectId": info.user_object_id,
        },
        "supportedCapabilities": caps.to_json(),
        "initialState": state.to_json(),
    })
}

/// Whether a pushed request came to one of our session links.
pub fn is_session_path(url: &str) -> bool {
    let path = url.split(['?', '#']).next().unwrap_or_default();
    path.contains("/bettertogether/session/")
}

/// Whether a Better Together command belongs to a room remote session
/// (it names its session, or comes from a remote control endpoint).
pub fn is_session_message(body: &str) -> bool {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(body) else {
        return false;
    };
    if v.pointer("/transportDetails/endpointType")
        .and_then(|t| t.as_str())
        == Some("RemoteControl")
    {
        return true;
    }
    let details = match v.get("commandDetails") {
        Some(serde_json::Value::String(t)) => serde_json::from_str(t).unwrap_or_default(),
        Some(d) => d.clone(),
        None => serde_json::Value::Null,
    };
    details.get("sessionId").is_some() || details.get("controllerEndpointInfo").is_some()
}

/// What the room's socket answers a session message at once: taken.
pub fn acknowledgement(_url: &str, _body: &str) -> (u16, String) {
    (200, "{}".into())
}

/// The active session's links at the service, from the room's
/// acceptance reply (`sessionAcceptanceResponse`) or the acceptance pushed
/// to the controller (`sessionInvitationAcceptance`): `broadcast` relays a
/// message to the other side's `receive` link (live: a message to the
/// `session` link is taken, 202, and goes nowhere), `session` is the
/// session itself (its end).
pub fn active_links(v: &serde_json::Value) -> Option<(String, String)> {
    let links = [
        "/sessionAcceptanceResponse/links",
        "/sessionInvitationAcceptance/links",
    ]
    .iter()
    .find_map(|p| v.pointer(p))?;
    let get = |k: &str| {
        links
            .get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let (broadcast, session) = (get("broadcast"), get("session"));
    (!broadcast.is_empty()).then_some((broadcast, session))
}

/// The service's link for a started session (SlimCore's handleStartResponse:
/// `links.outgoingSession`, or `links.session`).
pub fn outgoing_link_in(reply: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(reply).ok()?;
    fn walk(v: &serde_json::Value) -> Option<String> {
        match v {
            serde_json::Value::Object(o) => {
                if let Some(l) = o.get("links") {
                    for k in ["outgoingSession", "session"] {
                        if let Some(s) = l.get(k).and_then(|s| s.as_str()) {
                            return Some(s.to_string());
                        }
                    }
                }
                o.values().find_map(walk)
            }
            _ => None,
        }
    }
    walk(&v)
}

/// The room's endpoint id in the session's acceptance as pushed to the
/// controller (`{registrationId, sessionInvitationAcceptance}`; it may
/// also sit in the acceptance's `acceptedBy`).
pub fn acceptance_of(v: &serde_json::Value) -> Option<String> {
    v.get("registrationId")
        .and_then(|r| r.as_str())
        .filter(|r| !r.is_empty())
        .or_else(|| {
            v.pointer("/sessionInvitationAcceptance/acceptedBy/endpointId")
                .and_then(|r| r.as_str())
        })
        .filter(|r| !r.is_empty())
        .map(str::to_string)
}

/// The session id in a service link (`…/incomingSession/<id>/…` or
/// `…/sessions/<id>/…`).
pub fn session_id_of(link: &str) -> Option<String> {
    let mut it = link.split('/');
    while let Some(seg) = it.next() {
        if seg == "incomingSession" || seg == "sessions" || seg == "outgoingSession" {
            return it.next().filter(|s| !s.is_empty()).map(str::to_string);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_pushed_session() {
        // As Teams' Control Room System reached OST Test Room (2026-11-24).
        let push = r#"{"sessionNotification":{"from":{"id":"8:orgid:a","displayName":null},"to":{"id":"8:orgid:room"},
            "links":{"accept":"https://r0-api.flightproxy.skype.com/api/v2/cp/cc-usce-01-prod-aks.cc.skype.com/cc/v1/incomingSession/fdb6/3/t/21/accept?i=1",
            "reject":"https://r0-api.flightproxy.skype.com/api/v2/cp/cc-usce-01-prod-aks.cc.skype.com/cc/v1/incomingSession/fdb6/3/t/21/reject?i=1"},
            "routingStrategy":"ConsumerFlightingProxy"},
            "debugContent":{"chainId":"tc","causeId":"tk"},"registrationId":"f648","commandSequenceNumber":1,
            "command":"sessionStart","commandDetails":{"meetingInfo":{"threadId":"19:meeting_x@thread.v2"}}}"#;
        let s = incoming_session(push).unwrap();
        assert_eq!(s.from, "8:orgid:a");
        assert_eq!(s.to, "8:orgid:room");
        assert!(s.accept.ends_with("/accept?i=1"));
        assert_eq!(s.controller_endpoint, "f648");
        assert_eq!(s.command, SESSION_START);
        assert_eq!(s.thread_id, "19:meeting_x@thread.v2");
        assert_eq!(session_id_of(&s.accept).as_deref(), Some("fdb6"));
        assert!(incoming_session(r#"{"callNotification":{}}"#).is_none());
    }

    #[test]
    fn finds_the_links_of_the_other_side() {
        let acc = serde_json::json!({"registrationId": "room-ep",
            "sessionInvitationAcceptance": {"acceptedBy": {"id": "8:orgid:r", "endpointId": "room-ep"},
                "links": {"receive": "https://t/x/bettertogether/session/s/receive", "end": "https://t/x/end"}}});
        assert_eq!(acceptance_of(&acc).as_deref(), Some("room-ep"));
        assert!(acceptance_of(&serde_json::json!({"sessionInvitationAcceptance": {}})).is_none());
        assert_eq!(
            outgoing_link_in(r#"{"links":{"outgoingSession":"https://cc/s/1"}}"#).as_deref(),
            Some("https://cc/s/1")
        );
        assert!(outgoing_link_in("{}").is_none());
        let reply = serde_json::json!({"sessionAcceptanceResponse": {"links": {"broadcast": "https://cc/a/b", "session": "https://cc/a"}}});
        assert_eq!(
            active_links(&reply),
            Some(("https://cc/a/b".into(), "https://cc/a".into()))
        );
        let pushed = serde_json::json!({"registrationId": "r", "sessionInvitationAcceptance": {"links": {"broadcast": "https://cc/x/broadcast", "session": "https://cc/x"}}});
        assert_eq!(
            active_links(&pushed).map(|l| l.0),
            Some("https://cc/x/broadcast".into())
        );
        assert!(is_session_path(
            "https://t/v4/f/a/bettertogether/session/s1/receive"
        ));
        assert!(!is_session_path("https://t/v4/f/a/bettertogether/send"));
        let remote_cmd =
            r#"{"registrationId":"c","command":"pair","commandDetails":"{\"sessionId\":\"s\"}"}"#;
        assert!(is_session_message(remote_cmd));
        assert!(!is_session_message(
            r#"{"registrationId":"p","command":"pair","commandDetails":"{\"deviceName\":\"Phone\"}"}"#
        ));
    }

    #[test]
    fn volume_steps_as_teams_rooms() {
        assert_eq!(volume_step(43, true), 50);
        assert_eq!(volume_step(50, true), 60);
        assert_eq!(volume_step(43, false), 40);
        assert_eq!(volume_step(40, false), 30);
        assert_eq!(volume_step(10, false), 1);
        assert_eq!(volume_step(1, false), 1);
        assert_eq!(volume_step(100, true), 100);
    }

    #[test]
    fn capabilities_and_state_as_teams_sends_them() {
        let caps = Capabilities {
            mute: true,
            camera: false,
            captions: true,
            layouts: vec![layout::GALLERY.into()],
        };
        let j = caps.to_json();
        assert_eq!(
            j["mediaControls"],
            serde_json::json!(["toggleMute", "toggleCaptions", "volume"])
        );
        assert_eq!(j["meetingControls"], serde_json::json!(["leaveMeeting"]));
        assert_eq!(Capabilities::from_json(&j), caps);
        let mut more = caps.clone();
        more.camera = true;
        more.layouts.push(layout::CONTENT.into());
        let u = more.update_from(&caps).unwrap();
        assert_eq!(u["toggleCamera"], "enable");
        assert_eq!(
            u["stageLayoutControls"],
            serde_json::json!(["showVideoGallery", "showContent"])
        );
        assert!(caps.update_from(&caps).is_none());
        let mut copy = caps.clone();
        copy.apply(&u);
        assert_eq!(copy, more);
        let st = RoomState {
            muted: true,
            camera: false,
            captions: false,
            layout: layout::GALLERY.into(),
        };
        assert_eq!(RoomState::from_json(&st.to_json()), st);
        let p = pair_result(
            &RoomInfo {
                device_name: "room".into(),
                ..Default::default()
            },
            &caps,
            &st,
        );
        assert_eq!(p["accepted"], true);
        assert_eq!(p["initialState"]["toggleMute"], true);
        assert_eq!(p["roomEndpointInfo"]["deviceName"], "room");
    }

    #[test]
    fn session_links_are_better_together_paths() {
        let l = session_link(
            "https://pub-ent-ussc-05-f.trouter.teams.microsoft.com:3443/v4/f/abc/",
            "s1",
            "receive",
        );
        assert_eq!(
            l,
            "https://pub-ent-ussc-05-f.trouter.teams.microsoft.com:3443/v4/f/abc/bettertogether/session/s1/receive"
        );
        assert!(super::super::better_together::is_trouter_url(&l));
        let b = acceptance_body(
            "r",
            "e",
            "ep",
            &Debug {
                chain_id: "c".into(),
                cause_id: "k".into(),
            },
        );
        assert_eq!(b["sessionAcceptance"]["links"]["receive"], "r");
        assert_eq!(b["debugContent"]["chainId"], "c");
    }
}
