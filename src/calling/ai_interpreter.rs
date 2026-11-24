//! Teams' Interpreter (AI interpretation in meetings), as Teams desktop
//! drives it (bundles 527114 / calling-shell / unified-bar 26304; research
//! in the session scratchpad c225/research.md):
//!
//! - **On** is a meeting setting: the conversation's `updateMeetingSettings`
//!   (PUT) with `{aiInterpretationEnabled: true}`. The service then adds
//!   the interpreter bots itself and the conversation's
//!   `meetingDetails.meetingCapability.aiInterpretationEnabled` turns true.
//! - **Listening** in a language is joining that language's meeting group:
//!   POST the conversation's `joinMeetingGroup` with `meetingGroupLabel`
//!   (the language code), `groupPreferences.muteDefaultAudio` false, our
//!   `joinMeetingGroupStatus` callback and an operation id. The roster
//!   then puts our endpoint in the group
//!   (`meetingGroupDetails.groups.languageGroup[0].id`, one of
//!   `meetingDetails.meetingGroups.groups.languageGroup[{id, label}]`) and
//!   the media processor adds the group's interpretation to our audio.
//! - **Off for me** is `leaveMeetingGroup` `{meetingGroup: <id>}`; **off for
//!   all** (organizer) the setting with `aiInterpretationEnabled` and
//!   `aiInterpretationEnabledForAllParticipants` false.
//! - Teams desktop balances the interpreter's audio against everyone else's
//!   over per-speaker audio (x-much2), from -1 (original) to 1
//!   (interpretation), 0.8 at first ([`gains`]).

use serde_json::{Value, json};

/// The interpreter's output bot (one endpoint per language, meeting role
/// "interpreter"); prod `aiInterpretationBotIds.output`, with the input
/// bot and the first-party one.
pub const OUTPUT_BOT: &str = "28:5f2511f1-6da9-41d9-80d9-af7da23a2c27";
pub const INPUT_BOT: &str = "28:7cbe7d58-04af-48aa-b9f8-b64f99ee1f9e";
pub const FIRST_PARTY_BOT: &str = "28:c739e0df-765e-4f78-9f68-6dcfaa84bbff";

/// The languages Interpreter translates into (live ECS
/// `aiInterpretationLanguages`).
pub const LANGUAGES: [&str; 10] = ["de", "en", "es", "fr", "it", "ja", "ko", "pt", "zh-cn", "zh-tw"];

/// Teams' default balance (`RD`), and where the slider ends.
pub const DEFAULT_BALANCE: f32 = 0.8;

/// The meeting's Interpreter state from a conversation response or update
/// (`meetingDetails`).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct MeetingState {
    /// `meetingCapability.aiInterpretationEnabled` (simultaneous: not
    /// turn-by-turn).
    pub enabled: bool,
    /// `meetingCapability.aiInterpretationEnabledForAllParticipants`.
    pub for_all: bool,
    /// `meetingGroups.groups.languageGroup`: (id, label).
    pub groups: Vec<(String, String)>,
    /// Consecutive interpretation is on for everyone
    /// (`aiInterpretationSettings.interpretationMode` "TurnByTurn"), with
    /// its two languages (`turnByTurnModeTargetLanguages`).
    pub turn_by_turn: bool,
    pub turn_by_turn_languages: Vec<String>,
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

/// The Interpreter state a conversation response or update carries, if it
/// carries meeting details.
pub fn meeting_state(json: &Value) -> Option<MeetingState> {
    let d = details(json)?;
    let cap = d.get("meetingCapability");
    let flag = |k: &str| cap.and_then(|c| c.get(k)).and_then(Value::as_bool).unwrap_or(false);
    let turn_by_turn = cap
        .and_then(|c| c.pointer("/aiInterpretationSettings/interpretationMode"))
        .and_then(Value::as_str)
        == Some("TurnByTurn");
    let groups = d
        .pointer("/meetingGroups/groups/languageGroup")
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .filter_map(|g| Some((g.get("id")?.as_str()?.to_string(), g.get("label")?.as_str()?.to_string())))
                .collect()
        })
        .unwrap_or_default();
    let turn_by_turn_languages = cap
        .and_then(|c| c.pointer("/aiInterpretationSettings/turnByTurnModeTargetLanguages"))
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|l| l.as_str().filter(|l| !l.is_empty()).map(str::to_string)).collect())
        .unwrap_or_default();
    Some(MeetingState {
        enabled: flag("aiInterpretationEnabled") && !turn_by_turn,
        for_all: flag("aiInterpretationEnabledForAllParticipants"),
        groups,
        turn_by_turn: flag("aiInterpretationEnabled") && turn_by_turn,
        turn_by_turn_languages,
    })
}

/// Our own language group id in a roster update: our endpoint's
/// `meetingGroupDetails.groups.languageGroup[0].id`. `Some(None)` when the
/// update names our endpoint outside any group, `None` when it doesn't
/// name it.
pub fn self_group(roster: &Value, me: &str, endpoint_id: &str) -> Option<Option<String>> {
    let participants = roster
        .pointer("/participants")
        .or_else(|| roster.pointer("/body/participants"))?
        .as_object()?;
    let p = participants.iter().find(|(k, _)| k.eq_ignore_ascii_case(me)).map(|(_, v)| v)?;
    let ep = p.get("endpoints")?.get(endpoint_id)?;
    Some(
        ep.pointer("/call/meetingGroupDetails/groups/languageGroup/0/id")
            .or_else(|| ep.pointer("/meetingGroupDetails/groups/languageGroup/0/id"))
            .and_then(Value::as_str)
            .map(str::to_string),
    )
}

/// The interpreter's audio sources in a roster update for a language
/// group: the output bot's endpoints in that group (their audio
/// `sourceId`s).
pub fn interpreter_sources(roster: &Value, group: &str) -> Vec<u32> {
    let Some(participants) = roster.pointer("/participants").or_else(|| roster.pointer("/body/participants")).and_then(Value::as_object) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for (id, p) in participants {
        if ![OUTPUT_BOT, INPUT_BOT, FIRST_PARTY_BOT].iter().any(|b| b.eq_ignore_ascii_case(id)) {
            continue;
        }
        for ep in p.get("endpoints").and_then(Value::as_object).into_iter().flat_map(|e| e.values()) {
            let in_group = ep
                .pointer("/call/meetingGroupDetails/groups/languageGroup/0/id")
                .or_else(|| ep.pointer("/meetingGroupDetails/groups/languageGroup/0/id"))
                .and_then(Value::as_str)
                == Some(group);
            if !in_group {
                continue;
            }
            for s in ep.pointer("/call/mediaStreams").and_then(Value::as_array).into_iter().flatten() {
                if s.get("type").and_then(Value::as_str) == Some("audio")
                    && let Some(src) = s.get("sourceId").and_then(Value::as_u64)
                {
                    out.push(src as u32);
                }
            }
        }
    }
    out.sort_unstable();
    out.dedup();
    out
}

/// Who a roster update names, and whether each is in a language group
/// (people only: the interpreter bots are left out), as Teams counts the
/// people using Interpreter.
pub fn group_members(roster: &Value) -> Vec<(String, bool)> {
    let Some(participants) = roster.pointer("/participants").or_else(|| roster.pointer("/body/participants")).and_then(Value::as_object) else {
        return Vec::new();
    };
    participants
        .iter()
        .filter(|(id, _)| id.starts_with("8:"))
        .filter_map(|(id, p)| {
            let eps = p.get("endpoints")?.as_object()?;
            let in_group = eps.values().any(|ep| {
                ep.pointer("/call/meetingGroupDetails/groups/languageGroup/0/id")
                    .or_else(|| ep.pointer("/meetingGroupDetails/groups/languageGroup/0/id"))
                    .is_some()
            });
            Some((id.to_ascii_lowercase(), in_group))
        })
        .collect()
}

/// Teams' joinMeetingGroup body (shell `XX`).
pub fn join_group_body(from: &Value, label: &str, status_link: &str, operation: &str) -> Value {
    json!({
        "from": from,
        "meetingGroupLabel": label,
        "groupPreferences": { "muteDefaultAudio": false },
        "links": { "joinMeetingGroupStatus": status_link },
        "operationId": operation,
    })
}

/// Teams' leaveMeetingGroup body (shell `QX`).
pub fn leave_group_body(from: &Value, group: &str, status_link: &str, operation: &str) -> Value {
    json!({
        "from": from,
        "meetingGroup": group,
        "links": { "leaveMeetingGroupStatus": status_link },
        "operationId": operation,
    })
}

/// The meeting settings Teams sends to turn Interpreter on, or off for
/// everyone (core `turnOnOffAiInterpreter`, without the master turn-on
/// that live ECS leaves off).
pub fn settings(on: bool) -> Value {
    if on {
        json!({ "aiInterpretationEnabled": true })
    } else {
        json!({ "aiInterpretationEnabled": false, "aiInterpretationEnabledForAllParticipants": false })
    }
}

/// The meeting settings Teams sends to turn consecutive interpretation on
/// for everyone, in two languages (core `updateAiInterpretationTurnByTurnMode`).
pub fn turn_by_turn_settings(first: &str, second: &str) -> Value {
    let inner = json!({ "interpretationMode": "TurnByTurn", "turnByTurnModeTargetLanguages": [first, second] });
    json!({ "aiInterpretationEnabled": true, "aiInterpretationSettingsJson": inner.to_string() })
}

/// Teams' aiVoiceConsent participant property: "0" simulate my voice, "1"
/// automated voice, or an automated voice's number (1 Ava, 2 Andrew, 3
/// Fable Turbo).
pub fn voice_consent_property(value: &str, seq: u64) -> Value {
    json!({ "aiVoiceConsent": { "sequenceNumber": seq, "value": { "aiVoiceConsentValue": value } } })
}

/// The join's result (`joinMeetingGroupResponse` / `leaveMeetingGroupResponse`):
/// (operation id, code); code 0 is success.
pub fn group_response(json: &Value) -> Option<(String, i64)> {
    let r = ["/body/joinMeetingGroupResponse", "/joinMeetingGroupResponse", "/body/leaveMeetingGroupResponse", "/leaveMeetingGroupResponse"]
        .iter()
        .find_map(|p| json.pointer(p))?;
    let op = r.get("operationId").and_then(Value::as_str).unwrap_or_default().to_string();
    let code = r
        .get("code")
        .or_else(|| r.pointer("/result/code"))
        .or_else(|| r.pointer("/results/0/result/code"))
        .and_then(Value::as_i64)
        .unwrap_or(0);
    Some((op, code))
}

/// A join failure Teams retries (6 times, 1.5 s apart): 404/6011 and
/// 500/5406.
pub fn retriable(status: u16, sub_code: i64) -> bool {
    matches!((status, sub_code), (404, 6011) | (500, 5406))
}

/// How loud the interpreter and everyone else are for a balance from -1
/// (more original audio) to 1 (more interpretation audio): Teams desktop
/// hands the balance to its native mixer (setLiveInterpretationAttributes;
/// its curve isn't in the bundles). OST keeps the favoured side at full
/// level and lowers the other one linearly: at Teams' default 0.8 the
/// original plays at 20 %. (interpreter gain, others' gain).
pub fn gains(balance: f32) -> (f32, f32) {
    let b = balance.clamp(-1.0, 1.0);
    ((1.0 + b).min(1.0), (1.0 - b).min(1.0))
}

/// While we listen in a language group: the interpreter's audio sources
/// and the balance, for the per-speaker mix (Teams desktop's
/// setLiveInterpretationAttributes with enableLiveInterpretation).
struct Listening {
    sources: Vec<u32>,
    balance: f32,
}

static LISTENING: std::sync::Mutex<Option<Listening>> = std::sync::Mutex::new(None);

/// Start (or update) balancing: the interpreter's sources and the balance;
/// `None` stops it.
pub fn set_listening(state: Option<(Vec<u32>, f32)>) {
    *LISTENING.lock().unwrap_or_else(|e| e.into_inner()) = state.map(|(sources, balance)| Listening { sources, balance });
}

/// Whether we listen to an interpretation (the meeting's audio then comes
/// per speaker, x-much2, as Teams desktop asks while it balances).
pub fn listening() -> bool {
    LISTENING.lock().unwrap_or_else(|e| e.into_inner()).is_some()
}

/// How loud one speaker's audio plays: the interpreter's sources and
/// everyone else's by the balance; 1 when not listening (or no
/// interpreter is in our group yet, as Teams' balance "0").
pub fn gain_for(source: u32) -> f32 {
    let g = LISTENING.lock().unwrap_or_else(|e| e.into_inner());
    match g.as_ref() {
        Some(l) if !l.sources.is_empty() => {
            let (interp, others) = gains(l.balance);
            if l.sources.contains(&source) { interp } else { others }
        }
        _ => 1.0,
    }
}

/// Teams' language names for the codes (calling_ai_interpreter_language_*).
pub fn language_name(code: &str) -> &'static str {
    match code {
        "de" => "German",
        "en" => "English",
        "es" => "Spanish",
        "fr" => "French",
        "it" => "Italian",
        "ja" => "Japanese",
        "ko" => "Korean",
        "pt" => "Portuguese",
        "zh-cn" => "Chinese (Mandarin, Simplified)",
        "zh-tw" => "Chinese (Mandarin, Traditional)",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn meeting_state_reads_the_capability_and_groups() {
        let v = json!({"meetingDetails": {"meetingCapability": {"aiInterpretationEnabled": true},
            "meetingGroups": {"groups": {"languageGroup": [{"id": "g1", "label": "es"}, {"id": "g2", "label": "fr"}]}}}});
        let s = meeting_state(&v).unwrap();
        assert!(s.enabled && !s.for_all);
        assert_eq!(s.groups, vec![("g1".into(), "es".into()), ("g2".into(), "fr".into())]);
        let tbt = json!({"meetingDetails": {"meetingCapability": {"aiInterpretationEnabled": true,
            "aiInterpretationSettings": {"interpretationMode": "TurnByTurn"}}}});
        assert!(!meeting_state(&tbt).unwrap().enabled);
        assert!(meeting_state(&tbt).unwrap().turn_by_turn);
        let t = turn_by_turn_settings("en", "es");
        assert_eq!(t["aiInterpretationSettingsJson"], r#"{"interpretationMode":"TurnByTurn","turnByTurnModeTargetLanguages":["en","es"]}"#);
    }

    #[test]
    fn self_group_and_interpreter_sources_come_from_the_roster() {
        let r = json!({"participants": {
            "8:orgid:me": {"endpoints": {"ep1": {"call": {"meetingGroupDetails": {"groups": {"languageGroup": [{"id": "g1"}]}}}}}},
            OUTPUT_BOT: {"endpoints": {
                "es": {"call": {"meetingGroupDetails": {"groups": {"languageGroup": [{"id": "g1"}]}},
                    "mediaStreams": [{"type": "audio", "sourceId": 4242}]}},
                "fr": {"call": {"meetingGroupDetails": {"groups": {"languageGroup": [{"id": "g2"}]}},
                    "mediaStreams": [{"type": "audio", "sourceId": 4343}]}}}}}});
        assert_eq!(self_group(&r, "8:orgid:ME", "ep1"), Some(Some("g1".into())));
        assert_eq!(self_group(&r, "8:orgid:me", "other"), None);
        assert_eq!(interpreter_sources(&r, "g1"), vec![4242]);
    }

    #[test]
    fn bodies_are_teams() {
        let from = json!({"id": "8:orgid:me"});
        let j = join_group_body(&from, "es", "cb/conversation/joinMeetingGroupStatus/", "op");
        assert_eq!(j["meetingGroupLabel"], "es");
        assert_eq!(j["groupPreferences"]["muteDefaultAudio"], false);
        assert_eq!(leave_group_body(&from, "g1", "cb", "op")["meetingGroup"], "g1");
        assert_eq!(settings(false)["aiInterpretationEnabledForAllParticipants"], false);
        assert_eq!(voice_consent_property("1", 2)["aiVoiceConsent"]["value"]["aiVoiceConsentValue"], "1");
        let (i, o) = gains(0.8);
        assert!((i - 1.0).abs() < 1e-6 && (o - 0.2).abs() < 1e-6);
        assert_eq!(gains(-1.0), (0.0, 1.0));
        assert!(retriable(404, 6011) && !retriable(400, 1));
    }
}
