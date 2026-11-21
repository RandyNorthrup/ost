//! The meeting's notes as a call shares them (docs/spec/call-and-meeting-
//! window.md "Notes"; measured in Teams on the web on a Meet now,
//! 2026-11-16): the conversation's meeting states
//! - `collabLeaders.notes` `{value: {type: "notes"}, sequenceNumber}`: the
//!   participant making the notes claims it first (so only one makes them);
//! - `collabResources.notes` `{value: {type: "notes", resourceUri},
//!   sequenceNumber}`: the notes' Loop page link, which every participant's
//!   Notes panel then opens.
//!
//! Both go to the conversation's `updateMeetingStates` link as
//! `{from, meetingStates: {<name>: …}, updateMeetingStatesStatus,
//! operationId}`; Teams sent sequence number 1 for each the first time.
//!
//! A scheduled meeting's notes live in Teams' collab object service instead
//! (reserve, make, commit); whoever committed them then asks the call to
//! refresh its collab details (`updateMeetingSettings` with
//! `{refreshSettings: 1}`, Teams' `RefreshSettings.CollabDetails`), and
//! every participant's `meetingDetails.collabDetails` then carries
//! `{id, changeKey, resources: [{id, type: "notes", location, addedBy,
//! metadata: {linkScope, isShared}}]}`: the notes' link is the resource's
//! `location` (Teams' cacheMeetingNotesDetailsFromCall).

use serde_json::{Value, json};

pub const RESOURCE: &str = "collabResources.notes";
pub const LEADER: &str = "collabLeaders.notes";

/// What the call knows of its notes.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Notes {
    /// The notes' Loop page link, once someone made them.
    pub resource_uri: String,
    pub resource_sequence: u64,
    /// Someone claimed making the notes.
    pub leader: bool,
    pub leader_sequence: u64,
    /// The call's election of who makes a Meet now's notes
    /// (`collabDetails.collabLeaders`, type notes), when it says.
    pub leaders: Option<Vec<Leader>>,
}

/// One entry of the call's `collabLeaders`: the participant's id
/// (`8:orgid:…`) and Teams' status: 0 elected (to acknowledge), 1 elected
/// (acknowledged: makes the notes), 2 locked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Leader {
    pub id: String,
    pub status: u64,
}

/// What Teams' Notes panel does in a Meet now (its createFlow), given the
/// call's leaders and who you are.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MeetNowStep {
    /// Nobody elected, or you are elected and haven't acknowledged yet:
    /// acknowledge (`collabLeaders.notes`).
    Acknowledge,
    /// You are the leader: make the notes.
    Make,
    /// Someone else is: wait for their link.
    Wait,
}

fn leaders_of(details: &Value) -> Option<Vec<Leader>> {
    let l = details.get("collabLeaders")?.as_array()?;
    Some(
        l.iter()
            .filter(|x| x.get("type").and_then(Value::as_str).is_some_and(|t| t.eq_ignore_ascii_case("notes")))
            .map(|x| Leader {
                id: x.pointer("/participant/id").and_then(Value::as_str).unwrap_or_default().to_string(),
                status: x.get("status").and_then(Value::as_u64).unwrap_or(0),
            })
            .collect(),
    )
}

fn states(event: &Value) -> Option<&Value> {
    ["/body/meetingStates", "/meetingStates", "/conversationResponse/meetingStates"]
        .iter()
        .find_map(|p| event.pointer(p))
}

fn collab_details(event: &Value) -> Option<Value> {
    let d = [
        "/meetingDetails/collabDetails",
        "/conversationResponse/meetingDetails/collabDetails",
        "/conversationUpdate/meetingDetails/collabDetails",
        "/conversation/meetingDetails/collabDetails",
        "/body/meetingDetails/collabDetails",
        "/body/conversationUpdate/meetingDetails/collabDetails",
    ]
    .iter()
    .find_map(|p| event.pointer(p))?;
    match d {
        Value::String(s) => serde_json::from_str(s).ok(),
        Value::Null => None,
        v => Some(v.clone()),
    }
}

/// The notes' link in the call's collab details (the `notes` resource's
/// location), if they carry one.
pub fn collab_notes_location(event: &Value) -> Option<String> {
    let d = collab_details(event)?;
    let r = d.get("resources")?.as_array()?.iter().find(|r| {
        r.get("type").and_then(Value::as_str).is_some_and(|t| t.eq_ignore_ascii_case("notes"))
    })?;
    let loc = r.get("location").and_then(Value::as_str)?;
    loc.starts_with("https://").then(|| loc.to_string())
}

/// Teams' `updateMeetingSettings` asking the call to refresh its collab
/// details (`RefreshSettings.CollabDetails`).
pub fn refresh_collab_details() -> Value {
    json!({ "refreshSettings": 1 })
}

fn value_of(state: &Value) -> Option<Value> {
    match state.get("value")? {
        Value::String(s) => serde_json::from_str(s).ok(),
        v => Some(v.clone()),
    }
}

impl Notes {
    /// Take the notes' states from a join response or conversation update;
    /// true when something changed.
    pub fn apply(&mut self, event: &Value) -> bool {
        let mut changed = false;
        // Who the call elected to make a Meet now's notes.
        if let Some(l) = collab_details(event).as_ref().and_then(leaders_of)
            && self.leaders.as_ref() != Some(&l)
        {
            self.leaders = Some(l);
            changed = true;
        }
        // A scheduled meeting's notes, from the call's collab details.
        if let Some(loc) = collab_notes_location(event)
            && loc != self.resource_uri
        {
            self.resource_uri = loc;
            changed = true;
        }
        let Some(st) = states(event) else { return changed };
        if let Some(r) = st.get(RESOURCE) {
            let seq = r.get("sequenceNumber").and_then(Value::as_u64).unwrap_or(0);
            let uri = value_of(r)
                .and_then(|v| v.get("resourceUri").and_then(Value::as_str).map(str::to_string))
                .unwrap_or_default();
            if (uri.starts_with("https://") || uri.is_empty()) && (uri != self.resource_uri || seq != self.resource_sequence) {
                self.resource_uri = uri;
                self.resource_sequence = seq;
                changed = true;
            }
        }
        if let Some(l) = st.get(LEADER) {
            let seq = l.get("sequenceNumber").and_then(Value::as_u64).unwrap_or(0);
            if !self.leader || seq != self.leader_sequence {
                self.leader = true;
                self.leader_sequence = seq;
                changed = true;
            }
        }
        changed
    }

    /// Teams' createFlow for a Meet now: no leader → acknowledge (try to
    /// become it); you elected (0) → acknowledge; you elected and
    /// acknowledged (1) or locked (2) → make them; someone else → wait.
    /// Without the call's leaders at all, a claim seen in the meeting
    /// states means someone else is at it.
    pub fn meet_now_step(&self, me: &str) -> MeetNowStep {
        let Some(l) = &self.leaders else {
            return if self.leader { MeetNowStep::Wait } else { MeetNowStep::Acknowledge };
        };
        if l.is_empty() {
            return MeetNowStep::Acknowledge;
        }
        if let Some(mine) = l.iter().find(|x| x.id.eq_ignore_ascii_case(me)) {
            return if mine.status == 0 { MeetNowStep::Acknowledge } else { MeetNowStep::Make };
        }
        MeetNowStep::Wait
    }

    /// The meeting state that acknowledges being the notes' leader (Teams
    /// sends sequence number 1).
    pub fn claim(&self) -> Value {
        json!({ LEADER: { "value": { "type": "notes" }, "sequenceNumber": 1 } })
    }

    /// The meeting state that shares the notes' link. Teams' compose
    /// container (FluidMeetNowComposeContainer, which makes the page) sends
    /// `{type, resourceUri}`; its leader-ack helper adds the call's id as
    /// `secret` (given here).
    pub fn share(&self, resource_uri: &str, secret: Option<&str>) -> Value {
        let mut value = json!({ "type": "notes", "resourceUri": resource_uri });
        if let Some(s) = secret {
            value["secret"] = s.into();
        }
        json!({ RESOURCE: { "value": value, "sequenceNumber": 1 } })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_notes_link_from_an_update() {
        let mut n = Notes::default();
        let ev = json!({"body": {"meetingStates": {"collabResources.notes": {"value": "{\"type\":\"notes\",\"resourceUri\":\"https://t-my.sharepoint.com/:fl:/p/u/x?nav=abc\"}", "sequenceNumber": 1}}}});
        assert!(n.apply(&ev));
        assert_eq!(n.resource_uri, "https://t-my.sharepoint.com/:fl:/p/u/x?nav=abc");
        assert!(!n.apply(&ev));
        // Other links are not taken.
        let bad = json!({"meetingStates": {"collabResources.notes": {"value": {"type": "notes", "resourceUri": "javascript:x"}, "sequenceNumber": 2}}});
        assert!(!n.apply(&bad));
    }

    #[test]
    fn reads_the_notes_from_collab_details() {
        let mut n = Notes::default();
        let ev = json!({"body": {"meetingDetails": {"collabDetails": {"id": "c", "changeKey": "1", "resources": [
            {"id": "r0", "type": "MeetingRecap", "location": "https://x/recap"},
            {"id": "r1", "type": "notes", "location": "https://t-my.sharepoint.com/:fl:/g/p", "addedBy": "8:orgid:a", "metadata": {"linkScope": "People", "isShared": "false"}}
        ]}}}, "callAgentPath": "conversation/conversationUpdate/"});
        assert!(n.apply(&ev));
        assert_eq!(n.resource_uri, "https://t-my.sharepoint.com/:fl:/g/p");
        assert!(!n.apply(&ev));
        // As a JSON string in a join response, and without notes.
        let s = json!({"conversationResponse": {"meetingDetails": {"collabDetails": "{\"resources\":[{\"type\":\"Notes\",\"location\":\"https://y/n\"}]}"}}});
        assert_eq!(collab_notes_location(&s).as_deref(), Some("https://y/n"));
        assert!(collab_notes_location(&json!({"meetingDetails": {"collabDetails": {"resources": []}}})).is_none());
        assert_eq!(refresh_collab_details(), json!({"refreshSettings": 1}));
    }

    #[test]
    fn publishes_as_teams() {
        let n = Notes::default();
        assert_eq!(n.claim(), json!({"collabLeaders.notes": {"value": {"type": "notes"}, "sequenceNumber": 1}}));
        assert_eq!(n.share("https://x", Some("c1")), json!({"collabResources.notes": {"value": {"type": "notes", "resourceUri": "https://x", "secret": "c1"}, "sequenceNumber": 1}}));
        assert_eq!(n.share("https://x", None), json!({"collabResources.notes": {"value": {"type": "notes", "resourceUri": "https://x"}, "sequenceNumber": 1}}));
        let mut m = Notes::default();
        m.apply(&json!({"meetingStates": {"collabLeaders.notes": {"value": {"type": "notes"}, "sequenceNumber": 1}}}));
        assert!(m.leader);
        assert_eq!(m.claim()["collabLeaders.notes"]["sequenceNumber"], 1);
        assert_eq!(m.meet_now_step("8:orgid:a"), MeetNowStep::Wait);
    }

    #[test]
    fn follows_the_calls_election_as_teams() {
        let me = "8:orgid:a";
        let mut n = Notes::default();
        assert_eq!(n.meet_now_step(me), MeetNowStep::Acknowledge);
        let with = |l: Value| json!({"body": {"meetingDetails": {"collabDetails": {"id": "c", "resources": [], "collabLeaders": l}}}});
        assert!(n.apply(&with(json!([]))));
        assert_eq!(n.meet_now_step(me), MeetNowStep::Acknowledge);
        n.apply(&with(json!([{"type": "notes", "participant": {"id": "8:orgid:A"}, "status": 0}])));
        assert_eq!(n.meet_now_step(me), MeetNowStep::Acknowledge);
        n.apply(&with(json!([{"type": "notes", "participant": {"id": "8:orgid:a"}, "status": 1}])));
        assert_eq!(n.meet_now_step(me), MeetNowStep::Make);
        n.apply(&with(json!([{"type": "notes", "participant": {"id": "8:orgid:b"}, "status": 1}])));
        assert_eq!(n.meet_now_step(me), MeetNowStep::Wait);
        // Other kinds of leaders don't count.
        n.apply(&with(json!([{"type": "whiteboard", "participant": {"id": "8:orgid:b"}, "status": 1}])));
        assert_eq!(n.meet_now_step(me), MeetNowStep::Acknowledge);
    }
}
