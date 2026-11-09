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
    /// How many of their devices are in the call (endpoints with a call):
    /// with more than one of yours, Teams offers "Leave on all my devices".
    pub devices: usize,
    /// Muted, as Teams shows it: no endpoint has an audio stream that is
    /// neither server-muted nor muted by its owner (`endpointState.state.
    /// isMuted`).
    pub muted: bool,
    /// Their audio is inactive: they put the call on hold (Teams' Hold
    /// moves the held side to a music bot and makes the holder inactive).
    pub on_hold: bool,
    /// Their raised hand's state id (Teams' "raiseHands" published state).
    pub hand: Option<String>,
    /// Their spotlight's state id (Teams' "spotlight" published state):
    /// spotlighted for everyone.
    pub spotlight: Option<String>,
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
    /// Their shared screen's stream (`applicationsharing-video` sourceId)
    /// while they present.
    pub share_source: Option<i64>,
    /// The update listed their endpoints' streams; one that didn't (Teams'
    /// first update after joining names people only) leaves the
    /// stream-derived fields as they were.
    #[serde(skip)]
    pub streams_known: bool,
}

/// The meeting's call recorder (transcription and recording).
pub const CALL_RECORDER_MRI: &str = "28:bdd75849-e0a6-4cce-8fc1-d7c0d4da43e5";

/// The roster marks this participant hidden (Teams leaves them out of the
/// People pane and the stage).
fn is_hidden(mri: &str, p: &serde_json::Value) -> bool {
    // The call recorder is always hidden; not every update repeats its
    // endpoint's flag, which Teams keeps from an earlier one.
    mri.eq_ignore_ascii_case(CALL_RECORDER_MRI)
        || p.pointer("/details/hidden").and_then(|h| h.as_bool()) == Some(true)
        || p.get("endpoints").and_then(|e| e.as_object()).is_some_and(|eps| {
            eps.values().any(|ep| {
                ep.pointer("/endpointMetadata/__platform/ui/hidden").and_then(|h| h.as_bool()) == Some(true)
            })
        })
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
    delta_on(json, "conversation/rosterUpdate")
}

/// The same, for a call we only watch (OST's `subscription/rosterUpdate/`
/// callback, kept apart from the call we're in).
pub fn subscription_roster_delta(json: &str) -> Option<Vec<Participant>> {
    delta_on(json, "subscription/rosterUpdate")
}

fn delta_on(json: &str, prefix: &str) -> Option<Vec<Participant>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let path = v.get("callAgentPath")?.as_str()?;
    if !path.starts_with(prefix) {
        return None;
    }
    let participants = v.pointer("/body/participants")?.as_object()?;
    tracing::debug!(target: "teams_cli::calling::roster", "rosterUpdate {}", json);
    Some(
        participants
            .iter()
            // Service bots (28:…, such as Hold's music) aren't people, nor
            // is anyone the service marks hidden (the call recorder:
            // `details.hidden`, or its endpoint's `__platform.ui.hidden`).
            .filter(|(mri, p)| {
                !(mri.starts_with("28:")
                    && p.pointer("/details/displayName")
                        .and_then(|n| n.as_str())
                        .is_none_or(str::is_empty))
                    && !is_hidden(mri, p)
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
                // Teams' rule (calling-pluginless): someone is unmuted when an
                // endpoint's first audio stream isn't server-muted and the
                // endpoint itself isn't muted.
                let muted = !p
                    .get("endpoints")
                    .and_then(|e| e.as_object())
                    .into_iter()
                    .flat_map(|e| e.values())
                    .filter(|ep| ep.get("call").is_some())
                    .any(|ep| {
                        let audio = ep
                            .pointer("/call/mediaStreams")
                            .and_then(|m| m.as_array())
                            .into_iter()
                            .flatten()
                            .find(|m| m.get("type").and_then(|t| t.as_str()) == Some("audio"));
                        let server = audio
                            .and_then(|a| a.get("serverMuted"))
                            .and_then(|b| b.as_bool())
                            .unwrap_or(false);
                        let own = ep
                            .pointer("/endpointState/state/isMuted")
                            .and_then(|b| b.as_bool())
                            .unwrap_or(false);
                        !server && !own
                    });
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
                    muted,
                    devices: p
                        .get("endpoints")
                        .and_then(|e| e.as_object())
                        .map_or(0, |e| {
                            e.values().filter(|ep| ep.get("call").is_some()).count()
                        }),
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
                    spotlight: p
                        .get("publishedStates")
                        .and_then(|s| s.as_array())
                        .into_iter()
                        .flatten()
                        .find(|s| s.get("stateType").and_then(|t| t.as_str()) == Some("spotlight"))
                        .map(|s| {
                            s.get("stateId")
                                .and_then(|i| i.as_str())
                                .unwrap_or("spotlight")
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
                    share_source: sending_source(&all_streams, "applicationsharing-video"),
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

/// Whether a roster update says the meeting muted our endpoint (its audio
/// stream is serverMuted): None when the update doesn't list it.
pub fn own_server_muted(json: &str, endpoint_id: &str) -> Option<bool> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    if !v
        .get("callAgentPath")?
        .as_str()?
        .starts_with("conversation/rosterUpdate")
    {
        return None;
    }
    v.pointer("/body/participants")?
        .as_object()?
        .values()
        .filter_map(|p| p.pointer(&format!("/endpoints/{endpoint_id}/call/mediaStreams")))
        .filter_map(|m| m.as_array())
        .flatten()
        .find(|m| m.get("type").and_then(|t| t.as_str()) == Some("audio"))
        .map(|m| {
            m.get("serverMuted")
                .and_then(|b| b.as_bool())
                .unwrap_or(false)
        })
}

/// What the meeting's call recorder is doing, from its endpoint's
/// `endpointMetadata.processingModes` (the hidden `28:` participant the
/// recorder joins as): the transcript (`realTimeTranscript`), recording
/// and Copilot's own transcript, each "Active" or "Inactive" with the
/// `userId` of whoever started it. Teams' AI indicator is on while the
/// transcript or Copilot runs; its recording indicator shows the
/// recording and transcript with who started them.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Processing {
    /// Who started the running transcript (may be empty).
    pub transcript: Option<String>,
    /// Who started the running recording (may be empty).
    pub recording: Option<String>,
    pub copilot: bool,
    /// Live captions run (`closedCaptions`, started for anyone who turned
    /// them on).
    pub captions: bool,
}

impl Processing {
    pub fn any(self, other: &Processing) -> Processing {
        Processing {
            transcript: self.transcript.or_else(|| other.transcript.clone()),
            recording: self.recording.or_else(|| other.recording.clone()),
            copilot: self.copilot || other.copilot,
            captions: self.captions || other.captions,
        }
    }

    /// Teams' recording indicator state: "Transcribing", "Recording",
    /// "RecordingAndTranscribing", or "" when neither runs.
    pub fn indicator_state(&self) -> &'static str {
        match (self.recording.is_some(), self.transcript.is_some()) {
            (true, true) => "RecordingAndTranscribing",
            (true, false) => "Recording",
            (false, true) => "Transcribing",
            (false, false) => "",
        }
    }

    /// The recording indicator's tooltip (Teams' strings), naming who
    /// started each with `name` (an MRI to a display name, "" if unknown).
    pub fn indicator_tooltip(&self, name: impl Fn(&str) -> String) -> String {
        let who = |id: &Option<String>| id.as_deref().map(&name).unwrap_or_default();
        let (rec, tr) = (who(&self.recording), who(&self.transcript));
        let same = self.recording.as_deref().map(str::to_ascii_lowercase)
            == self.transcript.as_deref().map(str::to_ascii_lowercase);
        match (!rec.is_empty(), !tr.is_empty()) {
            (true, true) if same => format!("Recording and transcription started by {tr}."),
            (true, true) => format!("Recording started by {rec}. Transcription started by {tr}."),
            (true, false) => format!("Recording started by {rec}."),
            (false, true) => format!("Transcription started by {tr}."),
            (false, false) => match self.indicator_state() {
                "Transcribing" => "Transcription started".into(),
                "" => String::new(),
                _ => "Recording started".into(),
            },
        }
    }
}

/// The processing a roster update (or a join response, `{"roster":
/// {"participants": …}}`) reports, by participant: `Some` with the modes
/// for one whose endpoint carries them, `None` for one that left.
/// Participants the update names without endpoints are left out.
pub fn processing_updates(json: &serde_json::Value) -> Vec<(String, Option<Processing>)> {
    versioned_processing_updates(json).into_iter().map(|(id, m, _)| (id, m)).collect()
}

/// The same with each participant's roster `version`: updates can arrive
/// out of order, and the newer version wins (as Teams merges the roster).
pub fn versioned_processing_updates(json: &serde_json::Value) -> Vec<(String, Option<Processing>, u64)> {
    let participants = match json.get("callAgentPath").and_then(|p| p.as_str()) {
        Some(path) if path.starts_with("conversation/rosterUpdate") => json.pointer("/body/participants"),
        Some(_) => None,
        None => json.pointer("/roster/participants"),
    };
    let Some(participants) = participants.and_then(|p| p.as_object()) else {
        return Vec::new();
    };
    participants
        .iter()
        .filter_map(|(mri, p)| {
            let id = mri.to_ascii_lowercase();
            let version = p.get("version").and_then(|v| v.as_u64()).unwrap_or(0);
            if p.get("state").and_then(|s| s.as_str()).is_some_and(|s| s != "active") {
                return Some((id, None, version));
            }
            let modes = p
                .get("endpoints")?
                .as_object()?
                .values()
                .find_map(|ep| ep.pointer("/endpointMetadata/processingModes"))?;
            let started_by = |k: &str| {
                let m = modes.get(k)?;
                (m.get("state").and_then(|s| s.as_str()) == Some("Active"))
                    .then(|| m.get("userId").and_then(|u| u.as_str()).unwrap_or_default().to_string())
            };
            Some((
                id,
                Some(Processing {
                    transcript: started_by("realTimeTranscript"),
                    recording: started_by("recording"),
                    copilot: started_by("copilot").is_some(),
                    captions: started_by("closedCaptions").is_some(),
                }),
                version,
            ))
        })
        .collect()
}

/// Apply a delta to a roster kept in join order.
pub fn apply(roster: &mut Vec<Participant>, delta: Vec<Participant>) {
    for mut p in delta {
        match roster.iter_mut().find(|x| x.id == p.id) {
            Some(x) => {
                if !p.streams_known {
                    p.video_source = x.video_source;
                    p.share_source = x.share_source;
                    p.audio_source = x.audio_source;
                    p.server_muted = x.server_muted;
                    p.muted = x.muted;
                    p.devices = x.devices;
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

    #[test]
    fn hidden_participants_are_left_out() {
        let ev = serde_json::json!({"callAgentPath": "conversation/rosterUpdate/", "body": {"participants": {
            "28:bdd": {"state": "active", "details": {"displayName": "CallRecorder Bot"},
                "endpoints": {"e": {"endpointMetadata": {"__platform": {"ui": {"hidden": true}}}}}},
            "28:bdd75849-e0a6-4cce-8fc1-d7c0d4da43e5": {"state": "active", "details": {"displayName": "CallRecorder Bot"},
                "endpoints": {"e": {"call": {}}}},
            "8:orgid:a": {"state": "active", "details": {"displayName": "A"}}
        }}});
        let d = roster_delta(&ev.to_string()).unwrap();
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].name, "A");
    }

    #[test]
    fn call_recorder_processing() {
        let bot = |state: &str, transcript: &str| serde_json::json!({
            "callAgentPath": "conversation/rosterUpdate/",
            "body": {"participants": {
                "28:BDD75849-e0a6": {"state": state, "details": {"displayName": null},
                    "endpoints": {"fca2": {"endpointMetadata": {"processingModes": {
                        "copilot": {"state": "Inactive"},
                        "realTimeTranscript": {"state": transcript, "userId": "8:orgid:a"},
                        "recording": {"state": "Inactive", "userId": ""}}}}}},
                "8:orgid:a": {"state": "active", "details": {"displayName": "A"}}
            }}
        });
        let u = processing_updates(&bot("active", "Active"));
        assert_eq!(u, vec![("28:bdd75849-e0a6".to_string(), Some(Processing { transcript: Some("8:orgid:a".into()), ..Default::default() }))]);
        let u = processing_updates(&bot("active", "Inactive"));
        assert_eq!(u[0].1, Some(Processing::default()));
        let u = processing_updates(&bot("inactive", "Inactive"));
        assert_eq!(u[0].1, None);
        // A join response's roster.
        let joined = serde_json::json!({"roster": {"participants": bot("active", "Active")["body"]["participants"].clone()}});
        assert!(processing_updates(&joined)[0].1.clone().unwrap().transcript.is_some());
        assert!(processing_updates(&serde_json::json!({"callAgentPath": "call/x"})).is_empty());
        let mut v = bot("active", "Active");
        v["body"]["participants"]["28:BDD75849-e0a6"]["version"] = 578.into();
        assert_eq!(versioned_processing_updates(&v)[0].2, 578);
    }

    #[test]
    fn recording_indicator_as_teams_words_it() {
        let name = |id: &str| match id {
            "8:orgid:a" => "OST Test 1".to_string(),
            "8:orgid:b" => "Randy".to_string(),
            _ => String::new(),
        };
        let p = |r: Option<&str>, t: Option<&str>| Processing { recording: r.map(Into::into), transcript: t.map(Into::into), copilot: false, captions: false };
        assert_eq!(p(None, Some("8:orgid:a")).indicator_state(), "Transcribing");
        assert_eq!(p(None, Some("8:orgid:a")).indicator_tooltip(name), "Transcription started by OST Test 1.");
        assert_eq!(p(Some("8:orgid:a"), Some("8:orgid:a")).indicator_tooltip(name), "Recording and transcription started by OST Test 1.");
        assert_eq!(p(Some("8:orgid:b"), Some("8:orgid:a")).indicator_tooltip(name), "Recording started by Randy. Transcription started by OST Test 1.");
        assert_eq!(p(Some("8:orgid:b"), None).indicator_tooltip(name), "Recording started by Randy.");
        assert_eq!(p(Some("8:orgid:b"), None).indicator_state(), "Recording");
        assert_eq!(p(None, Some("")).indicator_tooltip(name), "Transcription started");
        assert_eq!(p(Some(""), Some("")).indicator_tooltip(name), "Recording started");
        assert_eq!(p(None, None).indicator_state(), "");
    }

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
    fn muted_is_teams_rule_over_endpoints() {
        // As Guest 1 muted itself (endpointState), Guest 2 was muted by the
        // meeting (serverMuted), and Guest 3 was neither (trimmed).
        let ep = |server: bool, own: Option<bool>| {
            let state = own.map_or(String::new(), |m| {
                format!(r#","endpointState":{{"endpointStateSequenceNumber":11,"state":{{"isMuted":{m}}}}}"#)
            });
            format!(
                r#"{{"call":{{"mediaStreams":[{{"direction":"sendrecv","label":"main-audio","serverMuted":{server},"sourceId":1,"type":"audio"}}]}}{state}}}"#
            )
        };
        let json = format!(
            r#"{{"callAgentPath":"conversation/rosterUpdate/","body":{{"participants":{{
                "8:teamsvisitor:1":{{"state":"active","details":{{"displayName":"OST Guest 1"}},"endpoints":{{"a":{}}}}},
                "8:teamsvisitor:2":{{"state":"active","details":{{"displayName":"OST Guest 2"}},"endpoints":{{"b":{}}}}},
                "8:teamsvisitor:3":{{"state":"active","details":{{"displayName":"OST Guest 3"}},"endpoints":{{"c":{}}}}},
                "8:orgid:4":{{"state":"active","details":{{"displayName":"Two devices"}},"endpoints":{{"d":{},"e":{}}}}}}}}}}}"#,
            ep(false, Some(true)),
            ep(true, Some(false)),
            ep(false, Some(false)),
            ep(false, Some(true)),
            ep(false, None),
        );
        let people = roster_delta(&json).unwrap();
        let muted = |id: &str| people.iter().find(|p| p.id == id).unwrap().muted;
        assert!(muted("8:teamsvisitor:1"), "muted themselves");
        assert!(muted("8:teamsvisitor:2"), "muted by the meeting");
        assert!(!muted("8:teamsvisitor:3"));
        assert!(!muted("8:orgid:4"), "one endpoint still talks");
    }

    #[test]
    fn watched_calls_have_their_own_roster_updates() {
        let body = r#"{"participants":{"8:orgid:a":{"state":"active","details":{"displayName":"OST Test 1"}}}}"#;
        let watched = format!(r#"{{"callAgentPath":"subscription/rosterUpdate/","body":{body}}}"#);
        let ours = format!(r#"{{"callAgentPath":"conversation/rosterUpdate/","body":{body}}}"#);
        assert_eq!(
            subscription_roster_delta(&watched).unwrap()[0].name,
            "OST Test 1"
        );
        assert!(roster_delta(&watched).is_none(), "not the call we're in");
        assert!(subscription_roster_delta(&ours).is_none());
    }

    #[test]
    fn our_own_server_mute_comes_from_our_endpoint() {
        let json = r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"participants":{
            "8:orgid:4287":{"state":"active","endpoints":{
                "ours":{"call":{"mediaStreams":[{"label":"main-audio","serverMuted":true,"sourceId":1,"type":"audio"}]}},
                "other-device":{"call":{"mediaStreams":[]}}}}}}}"#;
        assert_eq!(own_server_muted(json, "ours"), Some(true));
        assert_eq!(
            own_server_muted(&json.replace("true", "false"), "ours"),
            Some(false)
        );
        assert_eq!(own_server_muted(json, "elsewhere"), None);
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
