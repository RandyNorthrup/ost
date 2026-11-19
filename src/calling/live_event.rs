//! Town halls and webinars in the call window (docs/spec/town-halls-and-webinars.md).
//!
//! A meeting made by the Events app carries its event facts in
//! `meetingDetails.meetingCapability` (captured joining "OST TEST 184 town
//! hall" as its organizer, 2026-11-17): `forceAttendeeStreaming` (a town
//! hall: attendees watch a stream), `stagingRoomEnabled` (the green room),
//! `meetingLiveState {phase, seqNum}` ("staging", "live", "ended"),
//! `attendeeViewModes` ("Default", "HostMode": Manage what attendees see
//! is On, "AdvancedHostMode": On with preview) and `yammerQNAEnabled`
//! (Q&A). Teams tells webinars and town halls apart by the meeting's
//! template (Teams' webinarTemplateId / townhallTemplateId).
//!
//! Starting and ending the event for attendees is Teams' meetingGoLive /
//! meetingShowEndCurtain: a user-level "ufd" state with the curtain
//! (`{"publishStateUFDType": "stage-curtain" | "stage-end-curtain",
//! "meetingPhase": "live" | "ended", "teamsCallId": …}`), three seconds
//! (`callingStageCurtainPublishStateUFDTimeoutSec`), then the
//! conversation's `updateMeetingLiveState` link with the new phase and the
//! live state's sequence number, then the curtain state removed.

use serde_json::{Value, json};

/// Teams' webinar template (`webinarTemplateId`).
pub const WEBINAR_TEMPLATE: &str = "firstparty_d892ef44-003e-480c-9929-07349265a2e2";
/// Teams' town hall template (`townhallTemplateId`).
pub const TOWNHALL_TEMPLATE: &str = "firstparty_21f91ef7-6265-4064-b78b-41ab66889d90";
/// How long Teams shows the curtain before changing the phase
/// (`callingStageCurtainPublishStateUFDTimeoutSec`, 3).
pub const CURTAIN_SECONDS: u64 = 3;

/// What the meeting says about itself as an event.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveEvent {
    /// A town hall (`forceAttendeeStreaming`, the town hall template or a
    /// `scheduledTownhall` conversation).
    pub town_hall: bool,
    /// A webinar (its template).
    pub webinar: bool,
    /// Its attendees watch a stream (`forceAttendeeStreaming`): Teams' town
    /// hall wording ("Start event", the delay message).
    pub streaming: bool,
    /// The green room is on (`stagingRoomEnabled`).
    pub staging: bool,
    /// "staging", "live", "ended" or "" (no live state).
    pub phase: String,
    /// The live state's sequence number (sent back when changing it).
    pub seq: u64,
    /// `attendeeViewModes`: "Default", "HostMode" or "AdvancedHostMode".
    pub attendee_view: String,
    /// Q&A is on (`yammerQNAEnabled`).
    pub qna: bool,
    /// Attendees may react (`allowTeamsMeetingReactions`).
    pub reactions: bool,
}

impl LiveEvent {
    /// Teams' isEvent: a town hall or webinar (they say "End event").
    pub fn is_event(&self) -> bool {
        self.town_hall || self.webinar
    }

    /// Presenters manage what attendees see (Bring on screen).
    pub fn managed(&self) -> bool {
        matches!(self.attendee_view.as_str(), "HostMode" | "AdvancedHostMode")
    }

    /// Teams' stagingRoomEventPhase: "prelive", "active", "ended", or ""
    /// without a green room.
    pub fn event_phase(&self) -> &'static str {
        match (self.staging, self.phase.as_str()) {
            (false, _) => "",
            (true, "live") => "active",
            (true, "ended") => "ended",
            (true, _) => "prelive",
        }
    }
}

fn details(json: &Value) -> Option<&Value> {
    [
        "/meetingDetails",
        "/conversationResponse/meetingDetails",
        "/conversationUpdate/meetingDetails",
        "/conversation/meetingDetails",
        "/body/meetingDetails",
        "/body/conversationUpdate/meetingDetails",
    ]
    .iter()
    .find_map(|p| json.pointer(p))
}

/// The event facts in a conversation response or update (None when it
/// carries no meeting capability).
pub fn live_event(json: &Value) -> Option<LiveEvent> {
    let d = details(json)?;
    let cap = d.get("meetingCapability")?.as_object()?;
    let template = ["/templateDetails/templateId", "/templateDetails/id", "/templateId"]
        .iter()
        .find_map(|p| d.pointer(p).and_then(Value::as_str))
        .unwrap_or_default();
    let conv_type = ["/conversationType", "/body/conversationType"]
        .iter()
        .find_map(|p| json.pointer(p).and_then(Value::as_str))
        .unwrap_or_default();
    let flag = |k: &str| cap.get(k).and_then(Value::as_bool).unwrap_or(false);
    let state = cap.get("meetingLiveState");
    Some(LiveEvent {
        town_hall: flag("forceAttendeeStreaming") || template == TOWNHALL_TEMPLATE || conv_type == "scheduledTownhall",
        webinar: template == WEBINAR_TEMPLATE,
        streaming: flag("forceAttendeeStreaming"),
        staging: flag("stagingRoomEnabled"),
        phase: state.and_then(|s| s.get("phase")).and_then(Value::as_str).unwrap_or_default().to_string(),
        seq: state
            .and_then(|s| s.get("seqNum").or_else(|| s.get("sequenceNumber")))
            .and_then(Value::as_u64)
            .unwrap_or(0),
        attendee_view: cap.get("attendeeViewModes").and_then(Value::as_str).unwrap_or("Default").to_string(),
        qna: flag("yammerQNAEnabled"),
        reactions: flag("allowTeamsMeetingReactions"),
    })
}

/// The curtain Teams publishes while the event starts or ends (a "ufd"
/// state at user level). The content goes as an object: Teams' calling
/// stack parses a state's JSON before it posts it (pluginless
/// publishStateAsync and its payload builder).
pub fn curtain_state(live: bool, teams_call_id: &str, sequence: u64) -> Value {
    let content = json!({
        "publishStateUFDType": if live { "stage-curtain" } else { "stage-end-curtain" },
        "meetingPhase": if live { "live" } else { "ended" },
        "teamsCallId": teams_call_id,
    });
    json!({
        "content": content,
        "level": "user",
        "stateType": "ufd",
        "sequenceNumber": sequence,
    })
}

/// The `updateMeetingLiveState` body (Teams' calling stack: `from`, the
/// phase with the live state's sequence number, the status callback and an
/// operation id).
pub fn live_state_body(from: &Value, live: bool, seq: u64, status_link: &str, operation_id: &str) -> Value {
    json!({
        "from": from,
        "meetingLiveState": { "phase": if live { "live" } else { "ended" }, "sequenceNumber": seq },
        "links": { "updateMeetingLiveStateStatus": status_link },
        "operationId": operation_id,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_town_hall_as_teams_sends_it() {
        // The town hall's meetingCapability as its organizer joined it
        // (trimmed; captured 2026-11-17).
        let j = json!({"meetingDetails": {"meetingCapability": {"forceAttendeeStreaming": true, "stagingRoomEnabled": true,
            "meetingLiveState": {"phase": "staging", "seqNum": 0, "sequenceNumber": 0}, "attendeeViewModes": "HostMode",
            "yammerQNAEnabled": true, "allowTeamsMeetingReactions": false}}});
        let e = live_event(&j).unwrap();
        assert!(e.town_hall && !e.webinar && e.staging && e.qna && !e.reactions);
        assert_eq!(e.phase, "staging");
        assert_eq!(e.event_phase(), "prelive");
        assert!(e.managed() && e.is_event());
        let live = json!({"body": {"meetingDetails": {"templateDetails": {"templateId": WEBINAR_TEMPLATE},
            "meetingCapability": {"stagingRoomEnabled": true, "meetingLiveState": {"phase": "live", "seqNum": 3}}}}});
        let w = live_event(&live).unwrap();
        assert!(w.webinar && !w.town_hall);
        assert_eq!((w.event_phase(), w.seq), ("active", 3));
        assert_eq!(live_event(&json!({"meetingDetails": {}})), None);
        let plain = live_event(&json!({"meetingDetails": {"meetingCapability": {}}})).unwrap();
        assert_eq!(plain.event_phase(), "");
        assert!(!plain.is_event() && !plain.managed());
    }

    #[test]
    fn starts_the_event_as_teams_does() {
        let c = curtain_state(true, "abc", 7);
        assert_eq!(c["stateType"], "ufd");
        assert_eq!(c["content"], json!({"publishStateUFDType": "stage-curtain", "meetingPhase": "live", "teamsCallId": "abc"}));
        let b = live_state_body(&json!({"id": "8:orgid:x"}), false, 2, "https://cb/conversation/updateMeetingLiveStateStatus/", "op");
        assert_eq!(b["meetingLiveState"], json!({"phase": "ended", "sequenceNumber": 2}));
        assert_eq!(b["links"]["updateMeetingLiveStateStatus"], "https://cb/conversation/updateMeetingLiveStateStatus/");
    }
}
