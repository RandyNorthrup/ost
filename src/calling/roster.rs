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
                }
            })
            .collect(),
    )
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
    for p in delta {
        match roster.iter_mut().find(|x| x.id == p.id) {
            Some(x) => *x = p,
            None => roster.push(p),
        }
    }
    roster.retain(|p| p.active);
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
