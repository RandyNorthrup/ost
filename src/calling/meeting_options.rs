//! The meeting-wide actions of Teams' People pane "More actions" menu, and
//! the state they change, as Teams' calling stack does them:
//!
//! - Lock the meeting / Unlock the meeting and Disable / Allow mic or camera
//!   for attendees post the conversation's `updateMeetingSettings` link with
//!   `{from, meetingSettings, sequenceNumber}`. Teams sends
//!   `{lockMeeting: bool}`, or `{attendeeRestrictions: <bitmap>}` with the
//!   bits Audio 1, Video 2 and Chat 4 (`toAttendeeRestrictionsBitmap`).
//! - The meeting reports both back in `meetingDetails.meetingCapability`
//!   (`lockMeeting`, `attendeeRestrictions`); Teams reads the restrictions
//!   as the bitmap or as one of the names `UnRestricted`, `DisableAudio`,
//!   `DisableVideo`, `DisableAv` and `DisableChat`.
//! - Lower all hands and Stop all spotlights post `removeState` with scope
//!   "all" and the state type (`raiseHands`, `spotlight`).
//! - Download attendance list writes the joins and leaves the client saw
//!   (Teams' `participantActions`) as `meetingAttendanceList.csv`: tab
//!   separated, UTF-16LE with a byte-order mark.
//! - Meeting AI (the bar's AI indicator): `meetingCapability.copilotMode`
//!   says whether AI is available in the meeting ("Enabled" or
//!   "EnabledWithTranscript"), `groupCopilotDetails.enabled` whether its
//!   Facilitator is; whether AI is on follows the meeting's transcript
//!   (`roster::Processing`). Teams shows the indicator in Meet now and
//!   private scheduled meetings, not in channel meetings, ad hoc or
//!   end-to-end encrypted calls ([`shows_ai_indicator`]).

use serde_json::Value;

/// Attendee restriction bits (Teams' modality enum).
pub const RESTRICT_AUDIO: u32 = 1;
pub const RESTRICT_VIDEO: u32 = 2;
pub const RESTRICT_CHAT: u32 = 4;

/// What `meetingDetails.meetingCapability` says about the meeting.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MeetingCapability {
    /// Locked: nobody else can join.
    pub locked: bool,
    /// The attendee restriction bitmap (audio 1, video 2, chat 4).
    pub attendee_restrictions: u32,
    /// AI is available in the meeting (`copilotMode` "Enabled" or
    /// "EnabledWithTranscript").
    pub copilot: bool,
    /// Its Facilitator is enabled (`groupCopilotDetails.enabled`).
    pub facilitator: bool,
    /// Everyone can present (`presenterOption` "Everyone" or
    /// "EveryoneInCompany"): Teams shows the meeting timer then.
    pub everyone_presents: bool,
}

/// The meeting capability in a conversation response or update, if it
/// carries one.
pub fn meeting_capability(json: &Value) -> Option<MeetingCapability> {
    let cap = [
        "/meetingDetails/meetingCapability",
        "/conversationResponse/meetingDetails/meetingCapability",
        "/conversationUpdate/meetingDetails/meetingCapability",
        "/conversation/meetingDetails/meetingCapability",
        // A call event (`callAgentPath`, `body`).
        "/body/meetingDetails/meetingCapability",
        "/body/conversationUpdate/meetingDetails/meetingCapability",
    ]
    .iter()
    .find_map(|p| json.pointer(p))?
    .as_object()?;
    Some(MeetingCapability {
        locked: cap
            .get("lockMeeting")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        attendee_restrictions: cap
            .get("attendeeRestrictions")
            .map(restriction_bits)
            .unwrap_or(0),
        copilot: matches!(
            cap.get("copilotMode").and_then(Value::as_str),
            Some("Enabled" | "EnabledWithTranscript")
        ),
        facilitator: cap
            .get("groupCopilotDetails")
            .and_then(|g| g.get("enabled"))
            .and_then(Value::as_bool)
            .unwrap_or(false),
        everyone_presents: matches!(
            cap.get("presenterOption").and_then(Value::as_str),
            Some("Everyone" | "EveryoneInCompany")
        ),
    })
}

/// Whether Teams' bar shows the AI indicator in this meeting, from the
/// join response's `meetingDetails` (Teams' `CopilotIndicator` with its
/// meeting checks): Meet now meetings, and private scheduled meetings
/// with a calendar event; never channel meetings (not enabled for the
/// AI control), ad hoc calls or end-to-end encrypted meetings.
pub fn shows_ai_indicator(json: &Value) -> bool {
    let Some(d) = [
        "/meetingDetails",
        "/conversationResponse/meetingDetails",
        "/conversation/meetingDetails",
    ]
    .iter()
    .find_map(|p| json.pointer(p))
    else {
        return false;
    };
    let flag = |k: &str| d.get(k).and_then(Value::as_bool).unwrap_or(false);
    let kind = d.get("meetingType").and_then(Value::as_str).unwrap_or("");
    if flag("isChannelMeeting") || kind.is_empty() || kind == "Adhoc" {
        return false;
    }
    if kind == "MeetNow" {
        return true;
    }
    let has_event = d
        .get("iCalUid")
        .and_then(Value::as_str)
        .is_some_and(|u| !u.is_empty());
    let e2ee = d
        .pointer("/meetingCapability/meetingEndToEndEncryptionEnabled")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    // A "private" meeting is one not held in a channel; the conversation
    // service doesn't send Teams' client-side isPrivateMeeting.
    let private = d
        .get("isPrivateMeeting")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    private && has_event && !e2ee
}

/// Teams' `normalizeAttendeeRestrictions`: the bitmap, or a name.
fn restriction_bits(v: &Value) -> u32 {
    if let Some(n) = v.as_u64() {
        return u32::try_from(n).unwrap_or(0) & (RESTRICT_AUDIO | RESTRICT_VIDEO | RESTRICT_CHAT);
    }
    match v.as_str().unwrap_or("") {
        "DisableAudio" => RESTRICT_AUDIO,
        "DisableVideo" => RESTRICT_VIDEO,
        "DisableAv" => RESTRICT_AUDIO | RESTRICT_VIDEO,
        "DisableChat" => RESTRICT_CHAT,
        _ => 0,
    }
}

/// Teams' `from` for meeting state requests: who we are in the call.
pub fn state_from(me: &Value) -> Value {
    serde_json::json!({
        "id": me["id"],
        "displayName": me["displayName"],
        "endpointId": me["endpointId"],
        "participantId": me["participantId"],
        "languageId": me["languageId"],
    })
}

/// The `updateMeetingSettings` body.
pub fn settings_body(me: &Value, settings: Value, sequence: u64) -> Value {
    serde_json::json!({
        "from": state_from(me),
        "meetingSettings": settings,
        "sequenceNumber": sequence,
    })
}

/// The `removeState` body clearing a state type for everyone.
pub fn remove_state_for_everyone_body(me: &Value, state_type: &str, sequence: u64) -> Value {
    serde_json::json!({
        "from": state_from(me),
        "sequenceNumber": sequence,
        "scope": "all",
        "stateType": state_type,
    })
}

/// One line of the attendance list: who did what, when.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attendance {
    pub id: String,
    pub name: String,
    pub action: AttendanceAction,
    pub at: chrono::DateTime<chrono::Local>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AttendanceAction {
    /// In the meeting when you joined.
    JoinedBefore,
    Joined,
    Left,
}

impl AttendanceAction {
    fn label(self) -> &'static str {
        match self {
            AttendanceAction::JoinedBefore => "Joined before",
            AttendanceAction::Joined => "Joined",
            AttendanceAction::Left => "Left",
        }
    }
}

/// The joins and leaves seen during a meeting, per person in first-seen
/// order, as Teams' roster keeps them (`participantActions`): an action is
/// noted only when it differs from that person's latest one.
#[derive(Debug, Default, Clone)]
pub struct AttendanceLog {
    people: Vec<(String, Vec<Attendance>)>,
    present: std::collections::HashSet<String>,
    started: bool,
}

impl AttendanceLog {
    fn note(&mut self, a: Attendance) {
        match self.people.iter_mut().find(|(id, _)| *id == a.id) {
            Some((_, list)) => {
                if list.last().map(|l| l.action) != Some(a.action) {
                    list.push(a);
                }
            }
            None => self.people.push((a.id.clone(), vec![a])),
        }
    }

    /// The roster changed: `here` is everyone else in the meeting now
    /// (id, name). The first call notes them as "Joined before" and you
    /// (`me`) as joined; later calls note who joined and who left.
    pub fn update(
        &mut self,
        me: (&str, &str),
        here: &[(String, String)],
        at: chrono::DateTime<chrono::Local>,
    ) {
        let ids: std::collections::HashSet<String> = here.iter().map(|(i, _)| i.clone()).collect();
        if !self.started {
            self.started = true;
            for (id, name) in here {
                self.note(Attendance { id: id.clone(), name: name.clone(), action: AttendanceAction::JoinedBefore, at });
            }
            self.note(Attendance { id: me.0.into(), name: me.1.into(), action: AttendanceAction::Joined, at });
            self.present = ids;
            return;
        }
        for (id, name) in here {
            if !self.present.contains(id) {
                self.note(Attendance { id: id.clone(), name: name.clone(), action: AttendanceAction::Joined, at });
            }
        }
        let gone: Vec<String> = self.present.difference(&ids).cloned().collect();
        for id in gone {
            let name = self
                .people
                .iter()
                .find(|(i, _)| *i == id)
                .and_then(|(_, l)| l.last())
                .map(|a| a.name.clone())
                .unwrap_or_default();
            self.note(Attendance { id, name, action: AttendanceAction::Left, at });
        }
        self.present = ids;
    }

    /// You left the meeting.
    pub fn leave(&mut self, me: (&str, &str), at: chrono::DateTime<chrono::Local>) {
        if self.started {
            self.note(Attendance { id: me.0.into(), name: me.1.into(), action: AttendanceAction::Left, at });
        }
    }

    /// The list as Teams writes it: "Full Name\tUser Action\tTimestamp",
    /// then a line per action. Timestamps read as Teams formats them for
    /// en-US (`11/8/26, 10:21:33 AM`).
    pub fn tsv(&self) -> String {
        let mut out = String::from("Full Name\tUser Action\tTimestamp\n");
        for (_, list) in &self.people {
            for a in list {
                out.push_str(&format!(
                    "{}\t{}\t{}\n",
                    safe_cell(&a.name),
                    a.action.label(),
                    a.at.format("%-m/%-d/%y, %-I:%M:%S %p")
                ));
            }
        }
        out
    }
}

/// Teams' guard against spreadsheet formulas: every tab-, CR- or
/// LF-separated piece starting with one of `=+-@|%"` gets a leading space.
fn safe_cell(s: &str) -> String {
    let mut s = s.to_string();
    for sep in ['\t', '\r', '\n'] {
        s = s
            .split(sep)
            .map(|p| {
                if p.starts_with(['=', '+', '-', '@', '|', '%', '"']) {
                    format!(" {p}")
                } else {
                    p.to_string()
                }
            })
            .collect::<Vec<_>>()
            .join(&sep.to_string());
    }
    s
}

/// The file's bytes: UTF-16LE with a byte-order mark, as Teams saves it.
pub fn utf16le_with_bom(text: &str) -> Vec<u8> {
    let mut out = vec![0xff, 0xfe];
    for u in text.encode_utf16() {
        out.extend_from_slice(&u.to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn reads_the_meeting_capability_in_either_form() {
        let v: Value = serde_json::from_str(
            r#"{"conversationResponse":{"meetingDetails":{"meetingCapability":{"lockMeeting":true,"attendeeRestrictions":3}}}}"#,
        )
        .unwrap();
        assert_eq!(
            meeting_capability(&v),
            Some(MeetingCapability { locked: true, attendee_restrictions: 3, ..Default::default() })
        );
        let v: Value = serde_json::from_str(
            r#"{"meetingDetails":{"meetingCapability":{"attendeeRestrictions":"DisableVideo"}}}"#,
        )
        .unwrap();
        assert_eq!(
            meeting_capability(&v),
            Some(MeetingCapability { locked: false, attendee_restrictions: RESTRICT_VIDEO, ..Default::default() })
        );
        assert_eq!(meeting_capability(&serde_json::json!({"meetingDetails":{}})), None);
        let v = serde_json::json!({"meetingDetails":{"meetingCapability":{"copilotMode":"EnabledWithTranscript","groupCopilotDetails":{"enabled":true}}}});
        let c = meeting_capability(&v).unwrap();
        assert!(c.copilot && c.facilitator);
        let v = serde_json::json!({"meetingDetails":{"meetingCapability":{"copilotMode":"Disabled"}}});
        assert!(!meeting_capability(&v).unwrap().copilot);
    }

    #[test]
    fn ai_indicator_meetings() {
        let m = |d: Value| shows_ai_indicator(&serde_json::json!({ "meetingDetails": d }));
        assert!(m(serde_json::json!({"meetingType":"Scheduled","isPrivateMeeting":true,"iCalUid":"040000008200E0"})));
        // As the conversation service sends it (no isPrivateMeeting).
        assert!(m(serde_json::json!({"meetingType":"Scheduled","isChannelMeeting":false,"iCalUid":"040000008200E0"})));
        assert!(!m(serde_json::json!({"meetingType":"Scheduled","isPrivateMeeting":false,"iCalUid":"x"})));
        assert!(m(serde_json::json!({"meetingType":"MeetNow"})));
        assert!(!m(serde_json::json!({"meetingType":"MeetNow","isChannelMeeting":true})));
        assert!(!m(serde_json::json!({"meetingType":"Scheduled","isChannelMeeting":true,"isPrivateMeeting":false,"iCalUid":"x"})));
        assert!(!m(serde_json::json!({"meetingType":"Adhoc"})));
        assert!(!m(serde_json::json!({"meetingType":"Scheduled","isPrivateMeeting":true,"iCalUid":""})));
        assert!(!m(serde_json::json!({"meetingType":"Scheduled","isPrivateMeeting":true,"iCalUid":"x","meetingCapability":{"meetingEndToEndEncryptionEnabled":true}})));
        assert!(!shows_ai_indicator(&serde_json::json!({})));
    }

    #[test]
    fn builds_teams_bodies() {
        let me = serde_json::json!({"id":"8:orgid:a","displayName":"A","endpointId":"e","participantId":"p","languageId":"en-US","extra":1});
        let b = settings_body(&me, serde_json::json!({"lockMeeting": true}), 4);
        assert_eq!(b["meetingSettings"]["lockMeeting"], true);
        assert_eq!(b["sequenceNumber"], 4);
        assert_eq!(b["from"]["participantId"], "p");
        assert!(b["from"].get("extra").is_none());
        let r = remove_state_for_everyone_body(&me, "raiseHands", 5);
        assert_eq!(r["scope"], "all");
        assert_eq!(r["stateType"], "raiseHands");
        assert!(r.get("stateIds").is_none());
    }

    #[test]
    fn attendance_list_as_teams_writes_it() {
        let t = |s| chrono::Local.with_ymd_and_hms(2026, 11, 8, 10, 21, s).unwrap();
        let mut log = AttendanceLog::default();
        let g1 = ("8:guest:1".to_string(), "OST Guest 1".to_string());
        let g2 = ("8:guest:2".to_string(), "=Guest 2".to_string());
        log.update(("8:orgid:me", "OST Test 1"), std::slice::from_ref(&g1), t(1));
        log.update(("8:orgid:me", "OST Test 1"), std::slice::from_ref(&g1), t(2));
        log.update(("8:orgid:me", "OST Test 1"), &[g1.clone(), g2.clone()], t(3));
        log.update(("8:orgid:me", "OST Test 1"), std::slice::from_ref(&g2), t(4));
        log.leave(("8:orgid:me", "OST Test 1"), t(5));
        assert_eq!(
            log.tsv(),
            "Full Name\tUser Action\tTimestamp\n\
             OST Guest 1\tJoined before\t11/8/26, 10:21:01 AM\n\
             OST Guest 1\tLeft\t11/8/26, 10:21:04 AM\n\
             OST Test 1\tJoined\t11/8/26, 10:21:01 AM\n\
             OST Test 1\tLeft\t11/8/26, 10:21:05 AM\n \
             =Guest 2\tJoined\t11/8/26, 10:21:03 AM\n"
        );
        assert_eq!(&utf16le_with_bom("Fu")[..], &[0xff, 0xfe, b'F', 0, b'u', 0]);
    }
}
