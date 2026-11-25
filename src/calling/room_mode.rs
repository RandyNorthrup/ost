//! OST as a Teams Rooms device ("room mode"): what Teams Rooms (Teams'
//! meeting-room host, "Rigel") does when a laptop nearby picks the room in
//! Room audio and invites it to its meeting.
//!
//! Read from Teams' bundles (89637: byomAutoAcceptService,
//! RigelCallHandler, DevicesBLEService, ProximityValidationService;
//! calling-pluginless: the conversation requests):
//! - The room advertises a Bluetooth beacon with its account and a
//!   proximity validation code (a "salt") that changes every minute; a
//!   laptop hearing it sends the code back as the invitation's
//!   `autoAcceptAuthorization.token` (`OutgoingCall::add_room`).
//! - Its calling stack says it is a room: `deviceType: "room"` in each
//!   conversation request, which the roster then shows on its endpoint.
//! - An incoming meeting (Conference) or 1:1 call goes to the auto-join
//!   check (`onCallStateNotified`). byomAutoAcceptService then accepts by
//!   itself when its settings allow the invitation's proximity source and
//!   the caller's participant type, and the token is a salt the room
//!   advertised lately (`isValidProof`), within 4 seconds; otherwise the
//!   call rings on the room's console for someone there to answer.
//! - Accepting joins with the microphone on and the camera on when video
//!   is allowed; when the call ends the room goes back to its home screen.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

/// How the inviter found the room (Teams' `ProximitySource`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProximitySource {
    Bluetooth,
    Ultrasound,
    QrCode,
    CopilotQr,
}

impl ProximitySource {
    /// The invitation's source: `proximitySource` (1 Bluetooth, 2
    /// ultrasound, 3 QR code, 4 Copilot QR), else its
    /// `autoAcceptAuthorization.source` ("CopilotQR", "QR", "BTP"), as
    /// Teams Rooms' getProximitySource reads it.
    pub fn of(invitation: &serde_json::Value) -> Option<Self> {
        match invitation.get("proximitySource").and_then(|v| v.as_i64()) {
            Some(1) => return Some(Self::Bluetooth),
            Some(2) => return Some(Self::Ultrasound),
            Some(3) => return Some(Self::QrCode),
            Some(4) => return Some(Self::CopilotQr),
            _ => {}
        }
        match invitation
            .pointer("/autoAcceptAuthorization/source")
            .and_then(|v| v.as_str())
        {
            Some("CopilotQR") => Some(Self::CopilotQr),
            Some("QR") => Some(Self::QrCode),
            Some("BTP") => Some(Self::Bluetooth),
            _ => None,
        }
    }
}

/// Teams Rooms' "Auto accept proximity-based meeting invitations" choice
/// (`byomAutoAcceptSetting`, lower case; unknown values count as InTenant).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum AutoAccept {
    Disabled,
    #[default]
    InTenant,
    All,
}

impl AutoAccept {
    pub fn parse(s: &str) -> Self {
        match s.to_ascii_lowercase().as_str() {
            "disabled" => Self::Disabled,
            "all" => Self::All,
            _ => Self::InTenant,
        }
    }
}

/// The room's settings that gate auto-accepting (Teams Rooms'
/// meetingRoomSettingsService).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    /// `byomAutoAcceptEnabled`.
    pub auto_accept_enabled: bool,
    /// `byomAutoAcceptSetting`.
    pub auto_accept: AutoAccept,
    /// `ultrasoundAdvertisementEnabled` and
    /// `ultrasoundAutoAcceptProximateMeetingInvitations`.
    pub ultrasound_auto_accept: bool,
    /// `roomQRcodeEnabled` and `qrCodeAutoAcceptProximateMeetingInvitations`.
    pub qr_auto_accept: bool,
    /// `copilotQRCodeEnabled`.
    pub copilot_qr: bool,
    /// The room's camera may send video (RigelCallHandler.isVideoAllowed:
    /// the meeting policy's allowIPVideo).
    pub video_allowed: bool,
}

/// Teams Rooms' defaults (meetingRoomSettingsService): auto-accept on for
/// people in the tenant, over Bluetooth, ultrasound and the room's QR code;
/// the Copilot QR code off.
impl Default for Settings {
    fn default() -> Self {
        Self {
            auto_accept_enabled: true,
            auto_accept: AutoAccept::InTenant,
            ultrasound_auto_accept: true,
            qr_auto_accept: true,
            copilot_qr: false,
            video_allowed: true,
        }
    }
}

/// What the room does with an invitation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    /// Join at once (with video when allowed).
    Accept { video: bool },
    /// Ring on the room's console (Teams Rooms' manual accept), with the
    /// reason Teams logs.
    Ring(&'static str),
}

/// Teams Rooms' byomAutoAcceptService.acceptCall for an invitation
/// (`invitation`: its invitationData, possibly absent) from a caller in
/// the room's tenant or not, with the salts the room advertised.
pub fn decide(
    invitation: Option<&serde_json::Value>,
    caller_in_tenant: bool,
    settings: &Settings,
    salts: &Salts,
) -> Decision {
    let empty = serde_json::Value::Null;
    let inv = invitation.unwrap_or(&empty);
    let source = ProximitySource::of(inv);
    let mode = if settings.auto_accept_enabled {
        settings.auto_accept
    } else {
        AutoAccept::Disabled
    };
    match mode {
        AutoAccept::Disabled => return Decision::Ring("Auto_accept_not_allowed"),
        AutoAccept::InTenant if !caller_in_tenant => {
            return Decision::Ring("Auto_accept_not_allowed");
        }
        _ => {}
    }
    let allowed = match source {
        Some(ProximitySource::Ultrasound) => settings.ultrasound_auto_accept,
        Some(ProximitySource::Bluetooth) => settings.auto_accept_enabled,
        Some(ProximitySource::CopilotQr) => settings.copilot_qr,
        Some(ProximitySource::QrCode) => settings.qr_auto_accept,
        None => true,
    };
    if !allowed {
        return Decision::Ring("Auto_accept_not_allowed");
    }
    let Some(token) = token_of(inv) else {
        return Decision::Ring("Salt_not_found");
    };
    if !salts.is_valid(token) {
        return Decision::Ring("Salt_is_invalid");
    }
    // A Copilot QR join brings the room in without its camera.
    let video = settings.video_allowed && source != Some(ProximitySource::CopilotQr);
    Decision::Accept { video }
}

/// The invitation's `autoAcceptAuthorization.token` (a number, or a
/// number in a string); Teams treats 0 as no token.
fn token_of(inv: &serde_json::Value) -> Option<u32> {
    let t = inv.pointer("/autoAcceptAuthorization/token")?;
    t.as_u64()
        .or_else(|| t.as_str().and_then(|s| s.trim().parse().ok()))
        .and_then(|n| u32::try_from(n).ok())
        .filter(|n| *n != 0)
}

/// Teams' proximityAdvertiser defaults (config-prod).
pub const SALT_UPDATE: Duration = Duration::from_secs(60);
pub const SALT_HISTORY: usize = 1;
pub const SALT_LIFETIME: Duration = Duration::from_secs(60);

/// The proximity validation codes the room advertises (Teams Rooms'
/// ProximityValidationService): a random 16-bit salt, replaced every
/// `update` (`proximitySaltUpdateTime`), the replaced ones kept in a
/// history of `history` (`proximitySaltHistoryLength`); a token is valid
/// when it is the salt, or the salt `n` places into the history with
/// `(len - n) × update <= lifetime` (`proximitySaltLifetime`).
pub struct Salts {
    update: Duration,
    lifetime: Duration,
    history: usize,
    salt: u16,
    old: VecDeque<u16>,
    since: Instant,
}

/// A random 16-bit salt (Teams: `crypto.getRandomValues(new Uint16Array(1))`).
fn random_salt() -> u16 {
    let mut b = [0u8; 2];
    getrandom::fill(&mut b).expect("OS CSPRNG failed");
    u16::from_le_bytes(b)
}

impl Default for Salts {
    fn default() -> Self {
        Self::new(SALT_UPDATE, SALT_HISTORY, SALT_LIFETIME)
    }
}

impl Salts {
    pub fn new(update: Duration, history: usize, lifetime: Duration) -> Self {
        Self {
            update,
            lifetime,
            history,
            salt: random_salt(),
            old: VecDeque::new(),
            since: Instant::now(),
        }
    }

    /// The salt to advertise now.
    pub fn current(&self) -> u16 {
        self.salt
    }

    /// The salt's update period.
    pub fn update_period(&self) -> Duration {
        self.update
    }

    /// Replace the salt when it is due; true when it changed.
    pub fn tick(&mut self, now: Instant) -> bool {
        if now.duration_since(self.since) < self.update {
            return false;
        }
        self.old.push_back(self.salt);
        while self.old.len() > self.history {
            self.old.pop_front();
        }
        self.salt = random_salt();
        self.since = now;
        true
    }

    /// Teams Rooms' isValidProof(token, saltLifetime).
    pub fn is_valid(&self, token: u32) -> bool {
        if token == u32::from(self.salt) {
            return true;
        }
        let len = self.old.len();
        self.old
            .iter()
            .position(|s| u32::from(*s) == token)
            .is_some_and(|n| self.update * (len - n) as u32 <= self.lifetime)
    }
}

/// Whether this OST runs as a Teams Rooms device.
static ACTIVE: AtomicBool = AtomicBool::new(false);

/// Run (or stop running) as a Teams Rooms device.
pub fn set_active(on: bool) {
    ACTIVE.store(on, Ordering::Relaxed);
}

pub fn is_active() -> bool {
    ACTIVE.load(Ordering::Relaxed)
}

/// Teams Rooms' `deviceType`.
pub const ROOM_DEVICE_TYPE: &str = "room";

/// Teams Rooms' account configuration has `deviceType: "room"` (a rigel or
/// Surface Hub client), which its calling stack puts in each conversation
/// request it creates, joins or attaches with
/// (`conversationRequest.deviceType`); the meeting's roster then lists the
/// room's endpoint with `deviceType: "room"`, and Teams shows a room.
pub fn mark_device(payload: &mut serde_json::Value) {
    if is_active()
        && let Some(req) = payload
            .get_mut("conversationRequest")
            .and_then(|r| r.as_object_mut())
    {
        req.insert("deviceType".into(), ROOM_DEVICE_TYPE.into());
    }
}

/// What Teams Rooms' auto exit needs to know about the meeting, from its
/// `meetingDetails` (RigelAutoExitMeetingManager in Teams Rooms 26198:
/// `meetingType = meetingDetails.meetingType`, ad hoc is exactly "Adhoc",
/// so a Meet now ("MeetNow", as Cast's "Just cast" makes) is not; a
/// channel's Meet now is "Adhoc" like any other, as there is no channel
/// rule; and the schedule's end).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MeetingKind {
    pub adhoc: bool,
    /// The scheduled end (ISO 8601), when the details carry one.
    pub end: Option<String>,
}

pub fn meeting_kind(details: &serde_json::Value) -> MeetingKind {
    let s = |k: &str| details.get(k).and_then(|v| v.as_str()).map(str::to_string);
    MeetingKind {
        adhoc: s("meetingType").as_deref() == Some("Adhoc"),
        // Teams Rooms' isValidEndTime: an ad-hoc meeting says 0001-01-01.
        end: ["endTime", "scheduledEndTime", "meetingEndTime"]
            .iter()
            .find_map(|k| s(k))
            .filter(|e| !e.is_empty() && !e.starts_with("0001-")),
    }
}

/// Teams Rooms' auto exit (RigelAutoExitMeetingManager, on by default)
/// leaves at once when nobody else is left in an ad-hoc meeting. This is
/// the guess from the conversation's chat (`thread`) when the meeting's
/// details are missing: a group chat's call is ad hoc; a meeting's own chat
/// (`19:meeting_…`) is scheduled or a Meet now, and a channel
/// (`@thread.tacv2`) holds both kinds, so those wait for the meeting's end.
pub fn auto_exits_when_alone(thread: Option<&str>) -> bool {
    thread.is_some_and(|t| {
        t.starts_with("19:") && t.ends_with("@thread.v2") && !t.starts_with("19:meeting_")
    })
}

/// What a call's conversation is, for its title (Teams' calling
/// conversation: `isChannel`, `isGroup`, `isPrivateMeeting`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConversationKind {
    /// A channel (`@thread.tacv2` / `@thread.skype`, threadType space or topic).
    Channel,
    /// A group chat (threadType chat).
    Group,
    /// A meeting's own chat (threadType meeting, `19:meeting_…`).
    PrivateMeeting,
    /// A breakout room's chat.
    BreakoutRoom,
    /// No chat (a 1:1 call) or one Teams couldn't read.
    Other,
}

/// The conversation a call is in, as Teams Rooms' call title reads it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CallConversation {
    pub kind: Option<ConversationKind>,
    /// The chat's title (`topic`): a meeting's subject, a group chat's
    /// name, a channel's name.
    pub topic: Option<String>,
    /// A channel's display name when the thread has no topic.
    pub channel_name: Option<String>,
    /// Everyone else in it (display names).
    pub others: Vec<String>,
    /// A huddle (`conversationType` huddleGroupCall).
    pub huddle: bool,
}

/// Teams' `numberOfNamesInTitle`.
const NAMES_IN_TITLE: usize = 3;

/// The title Teams Rooms shows for a call it's in (the console's
/// meeting-room-in-call-info and the call header): useMeetingTitle in
/// Teams' bundles gives the calling intent's title, else the call's title
/// (`callTitleChangedEvent`), else "OST meeting" (Teams' "Microsoft Teams meeting")
/// (`teams_meeting_text_variant`; Rooms fetches a title for every call,
/// `enableTitleFetchForAllCalls`). The call's title comes from
/// callTitleService.getDefaultCallTitle (Rooms' message service has no
/// meetup titles): with a topic, a channel's is `Meeting in "{topic}"`, a
/// group chat's "Call with {topic}" ("Meeting in {topic}" for a huddle), a
/// meeting's the topic itself; without one, a breakout room or a meeting
/// is "OST meeting", a channel `Meeting in "{channel}"`, and
/// anything else the other people's names (sorted, ", "; past three
/// "{first name} and {n} others").
pub fn call_title(conv: &CallConversation) -> String {
    use crate::i18n::{fill, tr_id};
    // Teams' strings, in the app language ("Teams" in them reads "OST").
    let default = || tr_id("OST meeting", "calling:k7f4r2l46");
    let in_channel = |c: &str| {
        fill(&tr_id("Meeting in \"%1\"", "calling:k81e9cufd"), &[c])
            .trim_end()
            .to_string()
    };
    let topic = conv
        .topic
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty());
    match (conv.kind, topic) {
        (Some(ConversationKind::Channel), Some(t)) => return in_channel(t),
        (Some(ConversationKind::Group), Some(t)) => {
            return if conv.huddle {
                fill(&tr_id("Meeting in %1", "calling:k4836zld9"), &[t])
            } else {
                fill(&tr_id("Call with %1", "calling:k5s9mvdcx"), &[t])
            };
        }
        (Some(ConversationKind::PrivateMeeting), Some(t)) => return t.to_string(),
        (Some(ConversationKind::BreakoutRoom), t) => {
            return t.map(str::to_string).unwrap_or_else(default);
        }
        (Some(ConversationKind::Channel), None) => {
            return match conv
                .channel_name
                .as_deref()
                .map(str::trim)
                .filter(|c| !c.is_empty())
            {
                Some(c) => in_channel(c),
                None => default(),
            };
        }
        (Some(ConversationKind::PrivateMeeting), None) => return default(),
        _ => {}
    }
    let mut names: Vec<&str> = conv
        .others
        .iter()
        .map(|n| n.trim())
        .filter(|n| !n.is_empty())
        .collect();
    if names.is_empty() {
        return default();
    }
    names.sort_unstable();
    if names.len() > NAMES_IN_TITLE {
        let first = names[0].split(' ').next().unwrap_or(names[0]);
        let n = names.len() - 1;
        let text = if n == 1 {
            tr_id("%1 and %2 other", "calling:k2foouxfo")
        } else {
            tr_id("%1 and %2 others", "calling:kch21kbpc")
        };
        return fill(&text, &[first, &n.to_string()]);
    }
    names.join(", ")
}

/// The conversation kind of a thread from its id and `threadType`
/// property.
pub fn conversation_kind(thread: &str, thread_type: Option<&str>) -> ConversationKind {
    match thread_type.map(str::to_ascii_lowercase).as_deref() {
        Some("meeting") => ConversationKind::PrivateMeeting,
        Some("space") | Some("topic") => ConversationKind::Channel,
        Some("breakoutroom") | Some("breakout") => ConversationKind::BreakoutRoom,
        Some("chat") => ConversationKind::Group,
        _ if thread.starts_with("19:meeting_") => ConversationKind::PrivateMeeting,
        _ if thread.ends_with("@thread.tacv2") || thread.ends_with("@thread.skype") => {
            ConversationKind::Channel
        }
        _ if thread.ends_with("@thread.v2") => ConversationKind::Group,
        _ => ConversationKind::Other,
    }
}

/// Teams Rooms' ad-hoc auto exit (RigelAutoExitMeetingManager): an ad-hoc
/// meeting is "escalated" once anyone besides the room and one other is
/// in it (`getInCallParticipants().length > 1`), and then it's no longer
/// left the moment the others are gone.
pub fn adhoc_escalated(others_in_call: usize) -> bool {
    others_in_call > 1
}

/// Whether a roster participant's endpoint is a Teams Rooms device
/// (`endpoints.endpointDetails[0].deviceType == "room"`, Teams'
/// getInCallMtrMris).
pub fn is_room_participant(participant: &serde_json::Value) -> bool {
    let first = participant
        .pointer("/endpoints/endpointDetails/0")
        .or_else(|| participant.pointer("/endpointDetails/0"));
    first
        .and_then(|e| e.get("deviceType"))
        .and_then(|d| d.as_str())
        == Some(ROOM_DEVICE_TYPE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn call_titles_follow_teams_rooms() {
        let conv = |kind, topic: Option<&str>, others: &[&str]| CallConversation {
            kind,
            topic: topic.map(str::to_string),
            channel_name: None,
            others: others.iter().map(|s| s.to_string()).collect(),
            huddle: false,
        };
        use ConversationKind::*;
        assert_eq!(
            call_title(&conv(
                Some(PrivateMeeting),
                Some("OST TEST 226 sync"),
                &["OST Test 1"]
            )),
            "OST TEST 226 sync"
        );
        assert_eq!(
            call_title(&conv(Some(PrivateMeeting), None, &["OST Test 1"])),
            "OST meeting"
        );
        assert_eq!(
            call_title(&conv(Some(Channel), Some("OST layout test"), &[])),
            "Meeting in \"OST layout test\""
        );
        let mut ch = conv(Some(Channel), None, &[]);
        ch.channel_name = Some("General".into());
        assert_eq!(call_title(&ch), "Meeting in \"General\"");
        assert_eq!(
            call_title(&conv(Some(Group), Some("OST group"), &[])),
            "Call with OST group"
        );
        assert_eq!(
            call_title(&conv(Some(Group), None, &["OST Test 2", "OST Test 1"])),
            "OST Test 1, OST Test 2"
        );
        assert_eq!(
            call_title(&conv(Some(Other), None, &["OST Test 1"])),
            "OST Test 1"
        );
        assert_eq!(
            call_title(&conv(None, None, &["D d", "C c", "B b", "A a"])),
            "A and 3 others"
        );
        assert_eq!(call_title(&conv(None, None, &[])), "OST meeting");
        assert_eq!(
            call_title(&conv(Some(BreakoutRoom), None, &["x"])),
            "OST meeting"
        );
    }

    #[test]
    fn conversation_kinds() {
        use ConversationKind::*;
        assert_eq!(
            conversation_kind("19:meeting_abc@thread.v2", None),
            PrivateMeeting
        );
        assert_eq!(conversation_kind("19:de4@thread.tacv2", None), Channel);
        assert_eq!(conversation_kind("19:abc@thread.v2", Some("chat")), Group);
        assert_eq!(
            conversation_kind("19:abc@thread.v2", Some("meeting")),
            PrivateMeeting
        );
        assert_eq!(conversation_kind("", None), Other);
        assert!(adhoc_escalated(2) && !adhoc_escalated(1));
    }

    #[test]
    fn a_proximity_invite_with_a_current_code_is_accepted() {
        let s = Salts::default();
        let inv = json!({"proximitySource": 1, "deviceType": "computer", "autoAcceptAuthorization": {"token": s.current()}});
        let expect = if s.current() == 0 {
            Decision::Ring("Salt_not_found")
        } else {
            Decision::Accept { video: true }
        };
        assert_eq!(decide(Some(&inv), true, &Settings::default(), &s), expect);
    }

    #[test]
    fn without_a_valid_code_the_room_rings() {
        let s = Salts::default();
        let none = json!({"proximitySource": 1, "deviceType": "computer", "autoAcceptAuthorization": null});
        assert_eq!(
            decide(Some(&none), true, &Settings::default(), &s),
            Decision::Ring("Salt_not_found")
        );
        assert_eq!(
            decide(None, true, &Settings::default(), &s),
            Decision::Ring("Salt_not_found")
        );
        let wrong = s.current().wrapping_add(1).max(1);
        let bad = json!({"proximitySource": 1, "autoAcceptAuthorization": {"token": wrong}});
        assert_eq!(
            decide(Some(&bad), true, &Settings::default(), &s),
            Decision::Ring("Salt_is_invalid")
        );
    }

    #[test]
    fn settings_gate_auto_accept() {
        let mut s = Salts::default();
        while s.current() == 0 {
            s = Salts::default();
        }
        let inv = json!({"proximitySource": 1, "autoAcceptAuthorization": {"token": s.current()}});
        assert_eq!(
            decide(Some(&inv), false, &Settings::default(), &s),
            Decision::Ring("Auto_accept_not_allowed")
        );
        let all = Settings {
            auto_accept: AutoAccept::All,
            ..Settings::default()
        };
        assert_eq!(
            decide(Some(&inv), false, &all, &s),
            Decision::Accept { video: true }
        );
        let off = Settings {
            auto_accept_enabled: false,
            ..Settings::default()
        };
        assert_eq!(
            decide(Some(&inv), true, &off, &s),
            Decision::Ring("Auto_accept_not_allowed")
        );
        let us = json!({"proximitySource": 2, "autoAcceptAuthorization": {"token": s.current()}});
        let no_us = Settings {
            ultrasound_auto_accept: false,
            ..Settings::default()
        };
        assert_eq!(
            decide(Some(&us), true, &no_us, &s),
            Decision::Ring("Auto_accept_not_allowed")
        );
        let no_video = Settings {
            video_allowed: false,
            ..Settings::default()
        };
        assert_eq!(
            decide(Some(&inv), true, &no_video, &s),
            Decision::Accept { video: false }
        );
        let copilot =
            json!({"proximitySource": 4, "autoAcceptAuthorization": {"token": s.current()}});
        assert_eq!(
            decide(Some(&copilot), true, &Settings::default(), &s),
            Decision::Ring("Auto_accept_not_allowed")
        );
    }

    #[test]
    fn the_salt_and_the_one_before_are_valid() {
        let mut s = Salts::new(Duration::from_secs(60), 1, Duration::from_secs(60));
        s.salt = 0x1111;
        let t0 = s.since;
        assert!(!s.tick(t0 + Duration::from_secs(10)));
        assert!(s.tick(t0 + Duration::from_secs(60)));
        s.salt = 0x2222;
        assert!(s.is_valid(0x2222) && s.is_valid(0x1111));
        assert!(s.tick(t0 + Duration::from_secs(120)));
        s.salt = 0x3333;
        assert!(s.is_valid(0x3333) && s.is_valid(0x2222));
        assert!(!s.is_valid(0x1111));
        // A shorter lifetime than the period lets only the salt in.
        let mut short = Salts::new(Duration::from_secs(60), 1, Duration::from_secs(30));
        short.salt = 0x4444;
        let t = short.since;
        short.tick(t + Duration::from_secs(60));
        short.salt = 0x5555;
        assert!(short.is_valid(0x5555) && !short.is_valid(0x4444));
    }

    #[test]
    fn room_endpoints_and_requests() {
        assert!(is_room_participant(
            &json!({"endpoints": {"endpointDetails": [{"deviceType": "room"}]}})
        ));
        assert!(!is_room_participant(
            &json!({"endpoints": {"endpointDetails": [{"participantId": "x"}]}})
        ));
        let mut p = json!({"conversationRequest": {"subject": null}});
        mark_device(&mut p);
        assert!(p["conversationRequest"].get("deviceType").is_none());
        set_active(true);
        mark_device(&mut p);
        set_active(false);
        assert_eq!(p["conversationRequest"]["deviceType"], "room");
    }

    #[test]
    fn meeting_kinds_from_details() {
        let k = meeting_kind(&json!({"meetingType": "Adhoc", "isChannelMeeting": true}));
        assert!(k.adhoc && k.end.is_none());
        let k =
            meeting_kind(&json!({"meetingType": "Scheduled", "endTime": "2026-11-19T07:00:00Z"}));
        assert_eq!(
            (k.adhoc, k.end.as_deref()),
            (false, Some("2026-11-19T07:00:00Z"))
        );
        // Cast's "Just cast" Meet now isn't ad hoc to Teams Rooms.
        assert!(
            !meeting_kind(&json!({"meetingType": "MeetNow", "endTime": "0001-01-01T00:00:00"}))
                .adhoc
        );
    }

    #[test]
    fn auto_exit_only_in_ad_hoc_chat_meetings() {
        assert!(auto_exits_when_alone(Some("19:ef21abc@thread.v2")));
        assert!(!auto_exits_when_alone(Some("19:meeting_NjU1@thread.v2")));
        assert!(!auto_exits_when_alone(Some("19:de43@thread.tacv2")));
        assert!(!auto_exits_when_alone(None));
    }

    #[test]
    fn sources_as_teams_rooms_reads_them() {
        assert_eq!(
            ProximitySource::of(&json!({"proximitySource": 2})),
            Some(ProximitySource::Ultrasound)
        );
        assert_eq!(
            ProximitySource::of(&json!({"autoAcceptAuthorization": {"source": "QR"}})),
            Some(ProximitySource::QrCode)
        );
        assert_eq!(ProximitySource::of(&json!({})), None);
        assert_eq!(AutoAccept::parse("ALL"), AutoAccept::All);
        assert_eq!(AutoAccept::parse("weird"), AutoAccept::InTenant);
    }
}
