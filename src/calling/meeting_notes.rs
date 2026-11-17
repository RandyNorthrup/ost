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
}

fn states(event: &Value) -> Option<&Value> {
    ["/body/meetingStates", "/meetingStates", "/conversationResponse/meetingStates"]
        .iter()
        .find_map(|p| event.pointer(p))
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
        let Some(st) = states(event) else { return false };
        let mut changed = false;
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

    /// The meeting state that claims making the notes.
    pub fn claim(&self) -> Value {
        json!({ LEADER: { "value": { "type": "notes" }, "sequenceNumber": self.leader_sequence + 1 } })
    }

    /// The meeting state that shares the notes' link.
    pub fn share(&self, resource_uri: &str) -> Value {
        json!({ RESOURCE: { "value": { "type": "notes", "resourceUri": resource_uri }, "sequenceNumber": self.resource_sequence + 1 } })
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
    fn publishes_as_teams() {
        let n = Notes::default();
        assert_eq!(n.claim(), json!({"collabLeaders.notes": {"value": {"type": "notes"}, "sequenceNumber": 1}}));
        assert_eq!(n.share("https://x"), json!({"collabResources.notes": {"value": {"type": "notes", "resourceUri": "https://x"}, "sequenceNumber": 1}}));
        let mut m = Notes::default();
        m.apply(&json!({"meetingStates": {"collabLeaders.notes": {"value": {"type": "notes"}, "sequenceNumber": 1}}}));
        assert!(m.leader);
        assert_eq!(m.claim()["collabLeaders.notes"]["sequenceNumber"], 2);
    }
}
