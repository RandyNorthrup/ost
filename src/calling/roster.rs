//! Meeting rosters: the `conversation/rosterUpdate` callbacks the
//! conversation service sends while you're in a group call or meeting.
//! Each update is a delta of participants by MRI; a participant whose
//! `state` is no longer `active` has left.

use serde::Serialize;

/// One person in the meeting.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Participant {
    /// `8:orgid:<oid>` for people in a tenant.
    pub id: String,
    pub name: String,
    /// Teams' meeting role: "organizer", "presenter", "attendee"… (may be empty).
    pub role: String,
    /// Still in the meeting.
    pub active: bool,
    /// Muted by the meeting (server mute) on every endpoint.
    pub server_muted: bool,
    /// Their audio is inactive: they put the call on hold (Teams' Hold
    /// moves the held side to a music bot and makes the holder inactive).
    pub on_hold: bool,
    /// Their raised hand's state id (Teams' "raiseHands" published state).
    pub hand: Option<String>,
    /// An anonymous guest (Teams shows its Unverified trust icon).
    pub guest: bool,
    /// A guest Teams' join shield flagged as a bot (Teams keeps the app
    /// avatar for them).
    pub suspected: bool,
    /// Their camera's stream (`main-video` sourceId) while it sends: what
    /// a meeting's source requests name.
    pub video_source: Option<i64>,
    /// Their audio stream's sourceId (dominant speaker updates name it).
    pub audio_source: Option<i64>,
    /// The update listed their endpoints' streams; one that didn't (Teams'
    /// first update after joining names people only) leaves the
    /// stream-derived fields as they were.
    #[serde(skip)]
    pub streams_known: bool,
}

/// The sourceId of an endpoint stream labelled `label`, when it sends.
fn sending_source(streams: &[&serde_json::Value], label: &str) -> Option<i64> {
    streams
        .iter()
        .filter(|m| m.get("label").and_then(|l| l.as_str()) == Some(label))
        .find(|m| {
            matches!(
                m.get("direction").and_then(|d| d.as_str()),
                Some("sendrecv" | "sendonly")
            )
        })
        .and_then(|m| m.get("sourceId")?.as_i64())
}

/// The participants a roster update changes, or `None` for other events.
/// `json` is a call event as published on the event hub
/// (`{"callAgentPath": "conversation/rosterUpdate/", "body": {…}}`).
pub fn roster_delta(json: &str) -> Option<Vec<Participant>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let path = v.get("callAgentPath")?.as_str()?;
    if !path.starts_with("conversation/rosterUpdate") {
        return None;
    }
    let participants = v.pointer("/body/participants")?.as_object()?;
    tracing::debug!(target: "teams_cli::calling::roster", "rosterUpdate {}", json);
    Some(
        participants
            .iter()
            // Service bots (28:…, such as Hold's music) aren't people.
            .filter(|(mri, p)| {
                !(mri.starts_with("28:")
                    && p.pointer("/details/displayName")
                        .and_then(|n| n.as_str())
                        .is_none_or(str::is_empty))
            })
            .map(|(mri, p)| {
                let s = |ptr: &str| p.pointer(ptr).and_then(|x| x.as_str()).unwrap_or_default();
                let all_streams: Vec<&serde_json::Value> = p
                    .get("endpoints")
                    .and_then(|e| e.as_object())
                    .into_iter()
                    .flat_map(|e| e.values())
                    .filter_map(|ep| ep.pointer("/call/mediaStreams")?.as_array())
                    .flatten()
                    .collect();
                let streams: Vec<&serde_json::Value> = p
                    .get("endpoints")
                    .and_then(|e| e.as_object())
                    .into_iter()
                    .flat_map(|e| e.values())
                    .filter_map(|ep| ep.pointer("/call/mediaStreams")?.as_array())
                    .flatten()
                    .filter(|m| m.get("type").and_then(|t| t.as_str()) == Some("audio"))
                    .collect();
                Participant {
                    id: mri.to_ascii_lowercase(),
                    name: s("/details/displayName").to_string(),
                    role: [s("/meetingRole"), s("/advancedMeetingRole")]
                        .into_iter()
                        .find(|r| !r.is_empty())
                        .unwrap_or_default()
                        .to_string(),
                    active: s("/state") == "active",
                    server_muted: !streams.is_empty()
                        && streams
                            .iter()
                            .all(|m| m.get("serverMuted").and_then(|b| b.as_bool()) == Some(true)),
                    hand: p
                        .get("publishedStates")
                        .and_then(|s| s.as_array())
                        .into_iter()
                        .flatten()
                        .find(|s| s.get("stateType").and_then(|t| t.as_str()) == Some("raiseHands"))
                        .map(|s| {
                            s.get("stateId")
                                .and_then(|i| i.as_str())
                                .unwrap_or("raised")
                                .to_string()
                        }),
                    on_hold: !streams.is_empty()
                        && streams.iter().all(|m| {
                            m.get("direction").and_then(|d| d.as_str()) == Some("inactive")
                        }),
                    guest: mri.starts_with("8:teamsvisitor:"),
                    suspected: mri.starts_with("8:teamsvisitor:")
                        && p.pointer("/details/propertyBag/participantScreening/value/isBot")
                            .and_then(|b| b.as_bool())
                            == Some(true),
                    streams_known: p
                        .get("endpoints")
                        .is_some_and(|e| e.as_object().is_some_and(|o| !o.is_empty())),
                    video_source: sending_source(&all_streams, "main-video"),
                    audio_source: all_streams
                        .iter()
                        .find(|m| m.get("label").and_then(|l| l.as_str()) == Some("main-audio"))
                        .and_then(|m| m.get("sourceId")?.as_i64()),
                }
            })
            .collect(),
    )
}

/// Meeting reactions in a call event (Teams' proxied "Reaction" messages on
/// `conversation/receiveMessage/`): (sender MRI, reaction name such as
/// "like", "heart", "applause", "laugh", "surprised").
pub fn meeting_reactions(json: &str) -> Option<Vec<(String, String)>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    if !v
        .get("callAgentPath")?
        .as_str()?
        .starts_with("conversation/receiveMessage")
    {
        return None;
    }
    let body = v.get("body")?;
    let messages: Vec<&serde_json::Value> =
        match body.get("messageContent").and_then(|m| m.as_array()) {
            Some(list) => list.iter().collect(),
            None => vec![body],
        };
    let out: Vec<(String, String)> = messages
        .into_iter()
        .filter(|m| m.get("type").and_then(|t| t.as_str()) == Some("Reaction"))
        .flat_map(|m| {
            let from = m
                .pointer("/from/id")
                .and_then(|i| i.as_str())
                .unwrap_or_default()
                .to_ascii_lowercase();
            m.pointer("/payload/values")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
                .filter_map(|r| r.get("name")?.as_str().map(str::to_string))
                .map(move |name| (from.clone(), name))
                .collect::<Vec<_>>()
        })
        .collect();
    Some(out)
}

/// How many wait in the lobby, when a roster update says
/// (`body.participantCounts.lobbyParticipants`).
pub fn lobby_count(json: &str) -> Option<u64> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    if !v
        .get("callAgentPath")?
        .as_str()?
        .starts_with("conversation/rosterUpdate")
    {
        return None;
    }
    v.pointer("/body/participantCounts/lobbyParticipants")?
        .as_u64()
}

/// Apply a delta to a roster kept in join order.
pub fn apply(roster: &mut Vec<Participant>, delta: Vec<Participant>) {
    for mut p in delta {
        match roster.iter_mut().find(|x| x.id == p.id) {
            Some(x) => {
                if !p.streams_known {
                    p.video_source = x.video_source;
                    p.audio_source = x.audio_source;
                    p.server_muted = x.server_muted;
                    p.on_hold = x.on_hold;
                    p.streams_known = x.streams_known;
                }
                *x = p
            }
            None => roster.push(p),
        }
    }
    roster.retain(|p| p.active);
}

/// Everyone in a conversation the join response's `roster` lists, with
/// their streams (later roster updates may name people without them).
pub fn joined(create_response: &str) -> Vec<Participant> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(create_response) else {
        return Vec::new();
    };
    let Some(participants) = v.pointer("/roster/participants") else {
        return Vec::new();
    };
    let event = serde_json::json!({
        "callAgentPath": "conversation/rosterUpdate/",
        "body": {"participants": participants},
    });
    roster_delta(&event.to_string()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn update(mri: &str, name: &str, state: &str, role: &str) -> String {
        serde_json::json!({
            "callAgentPath": "conversation/rosterUpdate/",
            "body": { "type": "Delta", "participants": { mri: {
                "state": state, "meetingRole": role,
                "details": { "displayName": name },
                "endpoints": { "e1": { "call": { "mediaStreams": [
                    { "type": "audio", "serverMuted": false },
                    { "type": "video", "serverMuted": true }
                ] } } }
            } } }
        })
        .to_string()
    }

    #[test]
    fn guests_and_their_screening_come_from_the_roster() {
        // As a meeting's rosterUpdate carried two admitted guests (trimmed).
        let json = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{
            "8:teamsvisitor:311b":{"state":"active","details":{"displayName":"OST Guest 1",
                "propertyBag":{"participantScreening":{"sequenceNumber":1,"value":{"isBot":true,"source":"JoinShield"}}}}},
            "8:teamsvisitor:43cf":{"state":"active","details":{"displayName":"OST Guest 2",
                "propertyBag":{"participantScreening":{"sequenceNumber":2,"value":{"isBot":false,"markedBy":"admitter","source":"JoinShield"}}}}},
            "8:orgid:4287":{"state":"active","details":{"displayName":"OST Test 1"}}}}}"#;
        let people = roster_delta(json).unwrap();
        let by = |id: &str| people.iter().find(|p| p.id == id).unwrap().clone();
        assert!(by("8:teamsvisitor:311b").guest && by("8:teamsvisitor:311b").suspected);
        assert!(by("8:teamsvisitor:43cf").guest && !by("8:teamsvisitor:43cf").suspected);
        assert!(!by("8:orgid:4287").guest);
    }

    #[test]
    fn sending_cameras_and_audio_sources_come_from_the_streams() {
        // As the join roster listed a guest with the camera on, and Teams
        // desktop receiving only (trimmed).
        let json = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{
            "8:teamsvisitor:43cf":{"state":"active","details":{"displayName":"OST Guest 2"},
                "endpoints":{"c129":{"call":{"mediaStreams":[
                    {"direction":"sendrecv","label":"main-audio","sourceId":2030,"type":"audio"},
                    {"direction":"sendrecv","label":"main-video","sourceId":2031,"type":"video"},
                    {"direction":"recvonly","label":"applicationsharing-video","sourceId":2041,"type":"applicationsharing-video"}]}}}},
            "8:orgid:4287":{"state":"active","details":{"displayName":"OST Test 1"},
                "endpoints":{"f648":{"call":{"mediaStreams":[
                    {"direction":"sendrecv","label":"main-audio","sourceId":201,"type":"audio"},
                    {"direction":"recvonly","label":"main-video","sourceId":202,"type":"video"}]}}}}}}}"#;
        let people = roster_delta(json).unwrap();
        let by = |id: &str| people.iter().find(|p| p.id == id).unwrap().clone();
        assert_eq!(by("8:teamsvisitor:43cf").video_source, Some(2031));
        assert_eq!(by("8:teamsvisitor:43cf").audio_source, Some(2030));
        assert_eq!(
            by("8:orgid:4287").video_source,
            None,
            "a camera that's off isn't a source"
        );
        assert_eq!(by("8:orgid:4287").audio_source, Some(201));
    }

    #[test]
    fn updates_without_streams_keep_what_the_join_roster_said() {
        let joined = joined(
            r#"{"roster":{"participants":{
            "8:teamsvisitor:43cf":{"state":"active","details":{"displayName":"OST Guest 2"},
                "endpoints":{"c129":{"call":{"mediaStreams":[
                    {"direction":"sendrecv","label":"main-audio","sourceId":2030},
                    {"direction":"sendrecv","label":"main-video","sourceId":2031}]}}}}}}}"#,
        );
        assert_eq!(joined[0].video_source, Some(2031));
        let mut r = Vec::new();
        apply(&mut r, joined);
        // Teams' first update after joining: names only.
        let names = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{
            "8:teamsvisitor:43cf":{"state":"active","details":{"displayName":"OST Guest 2"}}}}}"#;
        apply(&mut r, roster_delta(names).unwrap());
        assert_eq!(r[0].video_source, Some(2031));
        assert_eq!(r[0].audio_source, Some(2030));
        // Their camera goes off: the update lists the stream as receiving.
        let off = names.replace(
            r#""details":{"displayName":"OST Guest 2"}"#,
            r#""details":{"displayName":"OST Guest 2"},"endpoints":{"c129":{"call":{"mediaStreams":[{"direction":"recvonly","label":"main-video","sourceId":2031}]}}}"#,
        );
        apply(&mut r, roster_delta(&off).unwrap());
        assert_eq!(r[0].video_source, None);
    }

    #[test]
    fn reactions_come_from_proxied_messages() {
        let json = r#"{"callAgentPath":"conversation/receiveMessage/","body":{"messageContent":[
            {"operationId":"o1","type":"Reaction","payload":{"values":[{"id":"r1","name":"like","count":1,"attributes":{}}]},
             "from":{"id":"8:orgid:ABC","participantId":"p","endpointId":"e"}},
            {"operationId":"o2","type":"LiveInking","payload":{}}]}}"#;
        assert_eq!(
            meeting_reactions(json).unwrap(),
            vec![("8:orgid:abc".to_string(), "like".to_string())]
        );
        assert!(
            meeting_reactions(r#"{"callAgentPath":"conversation/rosterUpdate/","body":{}}"#)
                .is_none()
        );
    }

    #[test]
    fn lobby_counts_come_from_roster_updates() {
        // As the conversation service sent it with OST Guest 1 waiting.
        let json = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participantCounts":{"lobbyParticipants":1,"totalParticipants":2,"unverifiedUsersInLobby":1},"participants":{},"sequenceNumber":4,"type":"Delta"}}"#;
        assert_eq!(lobby_count(json), Some(1));
        assert_eq!(
            lobby_count(
                r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{}}}"#
            ),
            None
        );
    }

    #[test]
    fn rosters_follow_joins_and_leaves() {
        let mut r = Vec::new();
        apply(
            &mut r,
            roster_delta(&update("8:orgid:ME", "Me", "active", "organizer")).unwrap(),
        );
        apply(
            &mut r,
            roster_delta(&update("8:orgid:them", "Them", "active", "")).unwrap(),
        );
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].id, "8:orgid:me");
        assert_eq!(r[0].role, "organizer");
        assert!(!r[1].server_muted);
        apply(
            &mut r,
            roster_delta(&update("8:orgid:them", "Them", "inactive", "")).unwrap(),
        );
        assert_eq!(r.len(), 1);
        assert!(roster_delta(r#"{"callAgentPath":"call/end/","body":{}}"#).is_none());
        assert!(roster_delta("not json").is_none());
    }

    #[test]
    fn hold_shows_as_inactive_audio_and_bots_are_left_out() {
        let json = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{
            "28:56aa0a8f-4cd3-446b-8146-0023476a5ff2":{"state":"active","details":{"displayName":null},
                "endpoints":{"e":{"call":{"mediaStreams":[{"type":"audio","direction":"sendrecv"}]}}}},
            "8:orgid:aaaa":{"state":"active","details":{"displayName":"Randy"},
                "endpoints":{"e":{"call":{"mediaStreams":[{"type":"audio","direction":"inactive"},{"type":"video","direction":"inactive"}]}}}}}}}"#;
        let d = roster_delta(json).unwrap();
        assert_eq!(d.len(), 1, "the music bot isn't a person");
        assert!(d[0].on_hold);
        let resumed = json.replacen(r#""direction":"inactive""#, r#""direction":"sendrecv""#, 1);
        assert!(!roster_delta(&resumed).unwrap()[0].on_hold);
    }
}
