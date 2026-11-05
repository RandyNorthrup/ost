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
    Some(
        participants
            .iter()
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
                }
            })
            .collect(),
    )
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
}
