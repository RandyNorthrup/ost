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
    /// What is live on screen with "On with preview" (the conversation's
    /// `layoutDetails`).
    pub layout: ProductionLayout,
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

    /// "On with preview": presenters put people on a preview and send it
    /// live (Teams' isPreviewEnabled: AdvancedHostMode with
    /// enablePreviewQueueInAdvancedManagedMode).
    pub fn preview(&self) -> bool {
        self.attendee_view == "AdvancedHostMode"
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
    let template = [
        "/templateDetails/templateId",
        "/templateDetails/id",
        "/templateId",
    ]
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
        town_hall: flag("forceAttendeeStreaming")
            || template == TOWNHALL_TEMPLATE
            || conv_type == "scheduledTownhall",
        webinar: template == WEBINAR_TEMPLATE,
        streaming: flag("forceAttendeeStreaming"),
        staging: flag("stagingRoomEnabled"),
        phase: state
            .and_then(|s| s.get("phase"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        seq: state
            .and_then(|s| s.get("seqNum").or_else(|| s.get("sequenceNumber")))
            .and_then(Value::as_u64)
            .unwrap_or(0),
        attendee_view: cap
            .get("attendeeViewModes")
            .and_then(Value::as_str)
            .unwrap_or("Default")
            .to_string(),
        qna: flag("yammerQNAEnabled"),
        reactions: flag("allowTeamsMeetingReactions"),
        layout: production_layout(json).unwrap_or_default(),
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
pub fn live_state_body(
    from: &Value,
    live: bool,
    seq: u64,
    status_link: &str,
    operation_id: &str,
) -> Value {
    json!({
        "from": from,
        "meetingLiveState": { "phase": if live { "live" } else { "ended" }, "sequenceNumber": seq },
        "links": { "updateMeetingLiveStateStatus": status_link },
        "operationId": operation_id,
    })
}

/// One source on an event's production layout ("On with preview"): a
/// person's video (`VIDEO`) or screen share (`VBSS`) on the live screen.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LayoutSource {
    /// Their MRI.
    pub id: String,
    pub participant_id: String,
    pub endpoint_id: String,
    /// "VIDEO" or "VBSS".
    pub modality: String,
}

/// What attendees see in an event with "On with preview" (Manage what
/// attendees see: AdvancedHostMode): the conversation's `layoutDetails`
/// (Teams' meetingLayoutDetails, kept from every conversation update)
/// `{layout {kind, participants […], …}, sequenceNumber}`.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProductionLayout {
    /// Teams' layout kinds: CLASSIC, PANELIST, SPEAKER, GALLERY,
    /// SIDEBYSIDE, STACKED, CONTENTONLY, CONTENTSPEAKERFOCUSED.
    pub kind: String,
    pub participants: Vec<LayoutSource>,
    pub sequence: u64,
    /// Who sent it live last (`layout.lastUpdatedById`): Teams' "Last updated
    /// by" over the Live stage.
    pub updated_by: String,
}

/// The production layout in a conversation response or update.
pub fn production_layout(json: &Value) -> Option<ProductionLayout> {
    let d = [
        "/layoutDetails",
        "/conversationResponse/layoutDetails",
        "/conversationUpdate/layoutDetails",
        "/conversation/layoutDetails",
        "/body/layoutDetails",
        "/body/conversationUpdate/layoutDetails",
    ]
    .iter()
    .find_map(|p| json.pointer(p))
    .filter(|v| v.is_object())?;
    let layout = d.get("layout").unwrap_or(&Value::Null);
    let s = |v: &Value, k: &str| {
        v.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let participants = layout
        .get("participants")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        // Teams (hI): only who is on stage.
        .filter(|p| p.get("isOnStage").and_then(Value::as_bool) != Some(false))
        .map(|p| LayoutSource {
            id: s(p, "id"),
            participant_id: s(p, "participantId"),
            endpoint_id: s(p, "endpointId"),
            modality: s(p, "modality"),
        })
        .collect();
    Some(ProductionLayout {
        kind: match s(layout, "kind").as_str() {
            "" | "NONE" => "CLASSIC".into(),
            k => k.to_string(),
        },
        participants,
        sequence: d.get("sequenceNumber").and_then(Value::as_u64).unwrap_or(0),
        updated_by: s(layout, "lastUpdatedById").to_ascii_lowercase(),
    })
}

/// Teams' layout kind for these sources (getUpdatedLayoutKind): side by
/// side with a screen share among them, else classic.
pub fn layout_kind(sources: &[LayoutSource]) -> &'static str {
    if sources.iter().any(|s| s.modality == "VBSS") {
        "SIDEBYSIDE"
    } else {
        "CLASSIC"
    }
}

/// Send live (Teams' production studio setProductionLayout ▸
/// convertLayoutToPayload, then the calling stack's setMeetingLayout,
/// pluginless payload builder): `from`, `layoutDetails {layout {…,
/// action "put", kind, participants}, sequenceNumber}`, the operation id,
/// the conversation's layout sequence number and the status callback.
/// The layout is what Teams desktop sent pressing Send live (logged on
/// winpc 2026-11-19): `{id "<call>_Preview", participants [{id,
/// participantId, endpointId, modality, isRTMPInVideo false, state
/// null}], nameTag {isEnabled true}, kind, kindDetails null, background
/// null, action "put"}` with the conversation's sequence number.
pub fn set_layout_body(
    from: &Value,
    layout_id: &str,
    sources: &[LayoutSource],
    seq: u64,
    status_link: &str,
    operation_id: &str,
) -> Value {
    let participants: Vec<Value> = sources
        .iter()
        .map(|p| {
            json!({ "id": p.id, "participantId": p.participant_id, "endpointId": p.endpoint_id, "modality": p.modality,
                    "isRTMPInVideo": false, "state": null })
        })
        .collect();
    json!({
        "from": from,
        "layoutDetails": {
            "layout": {
                "id": layout_id,
                "participants": participants,
                "nameTag": { "isEnabled": true },
                "kind": layout_kind(sources),
                "kindDetails": null,
                "background": null,
                "action": "put",
            },
            "sequenceNumber": seq,
        },
        "operationId": operation_id,
        "sequenceNumber": 0,
        "links": { "setMeetingLayoutStatus": status_link },
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
    fn reads_the_live_layout_as_the_service_sends_it() {
        // The conversation update after Teams desktop's Send live (trimmed;
        // captured 2026-11-19, "OST TEST 217 r3 town hall").
        let j = json!({"callAgentPath": "conversation/conversationUpdate/", "body": {"layoutDetails": {"lastNonScreenshareLayoutKind": null,
            "lastSideBySideLayoutKind": null, "lastUpdatedBy": null, "layout": {"action": "put", "kind": "CLASSIC", "lastNonScreenshareLayoutKind": "CLASSIC",
            "lastUpdatedById": "8:orgid:4287", "nameTag": {"isEnabled": true}, "operationId": "98c0", "participants": [{"endpointId": "f2a6", "id": "8:orgid:9edc", "isOnStage": true,
            "isRTMPInVideo": false, "modality": "VIDEO", "participantId": "9c84"}], "resolution": {"height": 720, "width": 1280}, "sequenceNumber": 0},
            "sequenceNumber": 1}}});
        let l = production_layout(&j).unwrap();
        assert_eq!(
            (l.kind.as_str(), l.sequence, l.updated_by.as_str()),
            ("CLASSIC", 1, "8:orgid:4287")
        );
        assert_eq!(
            l.participants,
            vec![LayoutSource {
                id: "8:orgid:9edc".into(),
                participant_id: "9c84".into(),
                endpoint_id: "f2a6".into(),
                modality: "VIDEO".into()
            }]
        );
        // As the meeting starts: no layout yet ("NONE", null participants);
        // and a conversation without one.
        let none = json!({"body": {"layoutDetails": {"layout": {"kind": "NONE", "participants": null, "sequenceNumber": 0}, "sequenceNumber": 0}}});
        let n = production_layout(&none).unwrap();
        assert!(n.participants.is_empty() && n.kind == "CLASSIC");
        assert_eq!(
            production_layout(&json!({"body": {"layoutDetails": null}})),
            None
        );
        // Off stage (isOnStage false) isn't shown.
        let off = json!({"layoutDetails": {"layout": {"participants": [{"id": "a", "isOnStage": false}]}}});
        assert!(production_layout(&off).unwrap().participants.is_empty());
    }

    #[test]
    fn sends_live_as_teams_does() {
        let src = vec![LayoutSource {
            id: "8:orgid:9edc".into(),
            participant_id: "9c84".into(),
            endpoint_id: "f2a6".into(),
            modality: "VIDEO".into(),
        }];
        let b = set_layout_body(
            &json!({"id": "8:orgid:me"}),
            "112_Preview",
            &src,
            1,
            "https://cb/conversation/setMeetingLayoutStatus/",
            "op",
        );
        // Teams desktop's layoutDetails for Send live (logged 2026-11-19).
        assert_eq!(
            b["layoutDetails"],
            json!({"layout": {"id": "112_Preview", "participants": [{"id": "8:orgid:9edc", "participantId": "9c84",
            "endpointId": "f2a6", "modality": "VIDEO", "isRTMPInVideo": false, "state": null}], "nameTag": {"isEnabled": true}, "kind": "CLASSIC",
            "kindDetails": null, "background": null, "action": "put"}, "sequenceNumber": 1})
        );
        assert_eq!(b["operationId"], "op");
        assert_eq!(
            b["links"]["setMeetingLayoutStatus"],
            "https://cb/conversation/setMeetingLayoutStatus/"
        );
        let share = vec![LayoutSource {
            modality: "VBSS".into(),
            ..src[0].clone()
        }];
        assert_eq!(layout_kind(&share), "SIDEBYSIDE");
        assert_eq!(
            set_layout_body(&json!({}), "1_Preview", &[], 2, "", "")["layoutDetails"]["layout"]["participants"],
            json!([])
        );
    }

    #[test]
    fn starts_the_event_as_teams_does() {
        let c = curtain_state(true, "abc", 7);
        assert_eq!(c["stateType"], "ufd");
        assert_eq!(
            c["content"],
            json!({"publishStateUFDType": "stage-curtain", "meetingPhase": "live", "teamsCallId": "abc"})
        );
        let b = live_state_body(
            &json!({"id": "8:orgid:x"}),
            false,
            2,
            "https://cb/conversation/updateMeetingLiveStateStatus/",
            "op",
        );
        assert_eq!(
            b["meetingLiveState"],
            json!({"phase": "ended", "sequenceNumber": 2})
        );
        assert_eq!(
            b["links"]["updateMeetingLiveStateStatus"],
            "https://cb/conversation/updateMeetingLiveStateStatus/"
        );
    }
}
