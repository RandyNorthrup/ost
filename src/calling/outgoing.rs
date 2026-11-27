//! Outgoing 1:1 calls to Teams users, with WebRTC (DTLS-SRTP) audio.
//!
//! The call is created on the conversation service with our offer, the
//! callee is invited, and the callee's answer comes back over Trouter as a
//! callback on one of the links in our call invitation
//! (`…/callAgent/…/call/acceptance/`). Callbacks arrive through
//! [`crate::event_hub`], so the shared push connection must be running.

use anyhow::{Context, Result, bail};
use std::time::Duration;

use super::webrtc_audio::{LocalAudio, WebRtcAudioSession, WebRtcOffer, WebRtcStats};
use super::{call_test, signaling};
use crate::config::Config;
use crate::event_hub::{self, EventKind};

/// Most members a group call rings (Teams rings small groups only).
const MAX_RING: usize = 20;

/// How long the callee may ring before we give up.
const RING_TIMEOUT: Duration = Duration::from_secs(60);

/// A placed call that the callee answered.
pub struct OutgoingCall {
    http: reqwest::Client,
    /// A meeting's updateMediaDescriptions link, and the last request id.
    media_descriptions: Option<(String, std::sync::atomic::AtomicU64)>,
    /// The call's id (our chain id): Teams tags each share and each time
    /// the camera goes on with it ([`MediaTags`]).
    call_id: String,
    /// The tag in this call's callback URLs (events carry it as callTag).
    call_tag: String,
    tags: MediaTags,
    /// The join response's roster (people and their streams).
    joined_roster: Vec<super::roster::Participant>,
    skype_token: String,
    end_url: Option<String>,
    call_leg: Option<String>,
    media: Option<WebRtcAudioSession>,
    /// Our participant JSON and media-acknowledgement callback, for
    /// answering re-offers.
    me: (serde_json::Value, String),
    /// Our Trouter callback base: (surl, endpoint id).
    callbacks: (String, String),
    hold_link: Option<String>,
    resume_link: Option<String>,
    transfer_link: Option<String>,
    /// The callee's `links.replace` (what a consult then transfer names).
    replace_link: Option<String>,
    /// Who answered (`callAcceptance.acceptedBy.displayName`): the person
    /// a retrieved parked call brings back.
    answered_by: Option<String>,
    /// Where our own re-offers go (`links.mediaRenegotiation`).
    renegotiation_link: Option<String>,
    /// Each remote person's merge leg, from roster events (their
    /// `callLinks.replacement`), keyed by lowercase MRI: a silent merge
    /// names it so the service moves them instead of ringing.
    remote_legs: std::collections::HashMap<String, serde_json::Value>,
    /// Meetings: the conversation's publishState / removeState links
    /// (Raise hand), and the id of our raised hand.
    state_links: (Option<String>, Option<String>),
    hand: Option<String>,
    /// Our published Sign language mode state (sign_language_state).
    sign_state_id: Option<String>,
    state_seq: u64,
    /// The conversation's getAllParticipants link (who's already here).
    all_participants: Option<String>,
    /// Meetings: the conversation's admit and admitAll links (the lobby).
    admit_links: (Option<String>, Option<String>),
    /// The conversation's removeParticipant link (Deny, Remove).
    remove_link: Option<String>,
    /// The conversation's updateParticipantProperties link (marking a
    /// screened guest "not a bot" when admitting them).
    properties_link: Option<String>,
    /// The conversation's updateParticipantRole link (Make an attendee /
    /// Make a presenter).
    role_link: Option<String>,
    /// The conversation's updateMeetingSettings link (Lock the meeting,
    /// attendee mic and camera).
    settings_link: Option<String>,
    /// The conversation's joinMeetingGroup and leaveMeetingGroup links
    /// (Interpreter's language groups).
    group_links: (Option<String>, Option<String>),
    /// What the meeting says of Interpreter (on, for all, its language
    /// groups).
    interpretation: super::ai_interpreter::MeetingState,
    /// What the meeting last said about itself (locked, attendee
    /// restrictions).
    capability: super::meeting_options::MeetingCapability,
    /// The meeting's call recorder: its command URL (Record and
    /// transcribe) and what it does (transcript, recording, captions,
    /// Copilot).
    recorder: super::recorder::Tracker,
    /// Teams' bar shows the AI indicator in this meeting.
    ai_indicator: bool,
    /// The meeting is a Meet now (`meetingDetails.meetingType` "MeetNow").
    meet_now: bool,
    /// What the join response says about the meeting (Meeting info).
    meeting_info: Option<super::meeting_info::MeetingInfo>,
    /// The meeting's real-time activity feed `getArtifacts` link (the
    /// stored transcript).
    artifacts_link: Option<String>,
    /// The conversation controller (`conversationController`): deleting it
    /// ends the meeting for everyone.
    controller: Option<String>,
    /// The meeting's join link as Teams shares it (`meetingDetails`
    /// shortJoinUrl, else joinUrl): the People pane's Share invite.
    invite_url: Option<String>,
    /// The conversation's mute link (Mute all).
    mute_link: Option<String>,
    /// The conversation's updateEndpointMetadata link (whether we want
    /// live captions).
    metadata_link: Option<String>,
    /// The conversation's addParticipant link (inviting the meeting's
    /// recorder when it isn't in the call).
    add_participant_link: Option<String>,
    /// The conversation's updateMeetingStates link (the meeting timer).
    meeting_states_link: Option<String>,
    /// A town hall's or webinar's live state and green room
    /// (live_event.rs), as last reported.
    event: super::live_event::LiveEvent,
    /// The conversation's updateMeetingLiveState link (Start meeting, End
    /// event).
    live_state_link: Option<String>,
    /// The conversation's setMeetingLayout link (Send live, "On with
    /// preview").
    layout_link: Option<String>,
    /// The production layout's next sequence number (Teams' production
    /// studio counts its own and takes a higher one from the service).
    layout_seq: u64,
    /// The conversation's addParticipantAndModality link ("Call me").
    add_modality_link: Option<String>,
    /// The conversation's addModality link (content-sharing sessions:
    /// Whiteboard, PowerPoint Live, Excel Live, Annotate).
    content_link: Option<String>,
    /// The content-sharing session we present, once started.
    my_content: Option<super::content_sharing::Session>,
    /// Sessions others present that we joined (by correlation id).
    joined_content: std::collections::HashMap<String, super::content_sharing::Session>,
    /// The meeting's dial-in details (`meetingDetails.pstnDetails`).
    dial_in: Option<super::phone_audio::DialIn>,
    /// Whether the meeting offers phone audio (Teams' PSTN state).
    phone_audio: super::phone_audio::PhoneAudio,
    /// The phone "Call me" is calling (its participant id), until the
    /// meeting says it joined or failed.
    call_me: Option<String>,
    /// The room being added (Teams' join with a room), until the meeting answers.
    room_pending: Option<String>,
    /// People invited from the People pane (Teams' Invite someone), by
    /// MRI, until the call says they joined or couldn't be added.
    invited: Vec<String>,
    /// The meeting's message id in its chat ("0" for a scheduled
    /// meeting, the post for a channel meeting): Teams' teamsMessageId.
    group_message_id: Option<String>,
    /// The meeting timer as last received.
    timers: super::meeting_timer::Timers,
    /// The meeting's notes as the call shares them (collabResources.notes,
    /// collabLeaders.notes).
    notes: super::meeting_notes::Notes,
    /// The meeting's organizer as `oid@tid` (the join response's
    /// meetingInfo), for the meeting-notes service.
    notes_organizer: String,
    /// The thread the call belongs to.
    thread_id: String,
    /// A meeting's lobby chat (`activeModalities.groupChat.lobbyThreadId`):
    /// where the organizer and people waiting in the lobby talk.
    lobby_thread: Option<String>,
    /// The conversation's unmute link: unmuting yourself after the meeting
    /// muted you.
    unmute_link: Option<String>,
    /// The meeting has muted our endpoint (its audio stream is
    /// serverMuted), as the roster last said.
    server_muted: std::sync::atomic::AtomicBool,
    /// The conversation's sendMessage link (meeting reactions).
    message_link: Option<String>,
    /// The conversation's updateEndpointState link (our mute, as others
    /// see it), and the last sequence number posted.
    endpoint_state: Option<(String, std::sync::atomic::AtomicU64)>,
    /// Held in the meeting's lobby until someone admits us.
    in_lobby: bool,
    /// The meeting has started (`state.isMeetingActivated`): Teams' lobby
    /// text says someone will let you in shortly, else when it starts.
    meeting_started: bool,
    /// The conversation's leave link (leaving a meeting before joining it,
    /// as Teams' pre-join Cancel does).
    leave_link: Option<String>,
    /// A town hall's attendee: the meeting streams to us instead of
    /// answering our call (live_stream.rs).
    streaming: bool,
    /// The stream Teams' player would play (the composition bot's), as the
    /// roster last offered it.
    stream: Option<super::live_stream::StreamChoice>,
    /// Joined hidden while the pre-join window is open (Teams' preheat):
    /// nothing is sent or played, and nobody sees us, until
    /// [`OutgoingCall::join_preheated`].
    preheated: bool,
    /// The join response's `meetingDetails` (with its PSTN state), for the
    /// pre-join's Phone audio.
    joined_details: Option<serde_json::Value>,
}

/// Someone waiting in a meeting's lobby.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LobbyPerson {
    pub id: String,
    pub name: String,
    /// Teams' join shield flagged this anonymous guest as a bot: Teams
    /// lists them under "Suspected threats" with an Unverified badge.
    pub suspected: bool,
}

impl OutgoingCall {
    pub fn has_audio(&self) -> bool {
        self.media.is_some()
    }

    pub fn set_muted(&self, muted: bool) {
        if let Some(m) = &self.media {
            m.set_muted(muted);
        }
    }

    /// A meeting's lobby chat thread, if it has one.
    pub fn lobby_thread(&self) -> Option<&str> {
        self.lobby_thread.as_deref()
    }

    /// Our endpoint id (the roster lists our endpoint under it).
    pub fn endpoint_id(&self) -> Option<&str> {
        self.me.0.get("endpointId").and_then(|e| e.as_str())
    }

    /// The roster says whether the meeting has muted our endpoint.
    pub fn set_server_muted(&self, muted: bool) {
        self.server_muted
            .store(muted, std::sync::atomic::Ordering::Relaxed);
    }

    pub fn is_server_muted(&self) -> bool {
        self.server_muted.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Tell the conversation we muted or unmuted, as Teams does: muting,
    /// and unmuting ourselves, go in our endpoint state
    /// (updateEndpointState); unmuting after the meeting muted us asks the
    /// meeting (its unmute link, `mediaTypes: ["audio"]`).
    pub async fn publish_mute(&self, muted: bool) -> Result<()> {
        if !muted
            && self.is_server_muted()
            && let Some(link) = &self.unmute_link
        {
            let body = serde_json::json!({ "from": self.me.0, "mediaTypes": ["audio"] });
            cc_post(&self.http, &self.skype_token, link, &body, "Unmute").await?;
            return Ok(());
        }
        let Some((link, seq)) = &self.endpoint_state else {
            return Ok(());
        };
        let n = seq.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        cc_post(
            &self.http,
            &self.skype_token,
            link,
            &endpoint_state_body(&self.me.0, muted, n),
            "Endpoint state",
        )
        .await?;
        Ok(())
    }

    pub fn is_muted(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_muted())
    }

    /// Joined hidden by the pre-join window (Teams' preheat), not yet for
    /// real.
    pub fn is_preheated(&self) -> bool {
        self.preheated
    }

    /// The join response's meeting details (`{"meetingDetails": …}`), for
    /// the pre-join's PSTN state.
    pub fn joined_details(&self) -> Option<&serde_json::Value> {
        self.joined_details.as_ref()
    }

    /// Join now on a preheated call, as Teams' joinPreheatedCall: our
    /// endpoint state with `preheatProperties: 0` (and `isMuted` when
    /// joining with the mic off) makes us visible (held in the lobby, the
    /// lobby sees us), then our endpoint metadata; then the computer's
    /// audio is unmuted, unless we join without it (`with_audio` false:
    /// Don't use audio, Phone audio). Nothing is renegotiated: the media is
    /// up already.
    pub async fn join_preheated(&mut self, muted: bool, with_audio: bool) -> Result<()> {
        if !self.preheated {
            return Ok(());
        }
        let (link, seq) = self
            .endpoint_state
            .as_ref()
            .context("The preheated call has no endpoint state link")?;
        let n = seq.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        cc_post(
            &self.http,
            &self.skype_token,
            link,
            &preheat_join_body(&self.me.0, muted, n),
            "Join (preheated)",
        )
        .await?;
        self.preheated = false;
        if let Some(link) = self.metadata_link.clone() {
            let body = serde_json::json!({
                "participants": { "from": self.me.0 },
                "endpointMetadata": { "holographicCapabilities": 3 },
            });
            if let Err(e) = cc_send(
                &self.http,
                reqwest::Method::PUT,
                &self.skype_token,
                &link,
                &body,
                "Endpoint metadata",
            )
            .await
            {
                tracing::warn!("endpoint metadata after the preheated join: {e:#}");
            }
        }
        if let Some(m) = &self.media {
            m.set_muted(muted);
            m.set_held(!with_audio);
        }
        tracing::info!(muted, with_audio, "joined the preheated call");
        Ok(())
    }

    /// Leave the meeting's conversation (and with it the call), as Teams'
    /// pre-join Cancel does for its preheated call: `POST links.leave`.
    pub async fn leave(mut self) -> Result<()> {
        self.media = None;
        let link = self.leave_link.clone().context("No leave link")?;
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &leave_body(&self.me.0),
            "Leave",
        )
        .await?;
        tracing::info!("left the meeting's conversation");
        Ok(())
    }

    /// Hold or resume the call with the call controller, then our media.
    pub async fn hold(&mut self, held: bool) -> Result<()> {
        let (surl, epid) = self.callbacks.clone();
        let cb = |p: &str| signaling::trouter_callback(&surl, &epid, p);
        if held {
            let link = self
                .hold_link
                .clone()
                .context("This call can't be put on hold")?;
            let resume = super::incoming::request_hold(
                &self.http,
                &self.skype_token,
                &link,
                &cb("call/holdCompletion/"),
            )
            .await?;
            self.resume_link = Some(resume);
        } else {
            let link = self.resume_link.take().context("The call isn't on hold")?;
            super::incoming::request_resume(
                &self.http,
                &self.skype_token,
                &link,
                &cb("call/resumeCompletion/"),
            )
            .await?;
        }
        self.set_held(held);
        Ok(())
    }

    /// Raise or lower your hand in a meeting (Teams' "raiseHands" state).
    pub async fn raise_hand(&mut self, up: bool) -> Result<()> {
        self.state_seq += 1;
        let from = self.me.0.clone();
        if up {
            let link = self
                .state_links
                .0
                .clone()
                .context("This meeting doesn't take raised hands")?;
            let body = serde_json::json!({
                "from": from,
                "publishedState": {
                    "content": { "skinTone": 0 },
                    // Teams' publish levels are "user" and "endpoint"; a
                    // state about yourself has no scope.
                    "level": "user",
                    "stateType": "raiseHands",
                    "sequenceNumber": self.state_seq,
                },
            });
            let reply = cc_post(&self.http, &self.skype_token, &link, &body, "Raise hand").await?;
            self.hand = reply
                .pointer("/publishStateResponse/stateId")
                .or_else(|| reply.pointer("/publishStateResponse/publishedState/stateId"))
                .or_else(|| reply.pointer("/stateId"))
                .and_then(|v| v.as_str())
                .map(str::to_string);
            tracing::info!(has_id = self.hand.is_some(), "hand raised");
        } else {
            let link = self
                .state_links
                .1
                .clone()
                .context("This meeting doesn't take raised hands")?;
            let body = match self.hand.take() {
                Some(id) => {
                    serde_json::json!({ "from": from, "sequenceNumber": self.state_seq, "scope": "specified", "stateIds": [id] })
                }
                None => bail!("Your raised hand isn't known yet"),
            };
            cc_post(&self.http, &self.skype_token, &link, &body, "Lower hand").await?;
        }
        Ok(())
    }

    /// Everyone already in the conversation (roster updates only carry
    /// changes, so people who joined before us need this, as Teams does).
    /// Who was in the conversation when we joined, with their streams
    /// (the join response's roster).
    pub fn joined_roster(&self) -> Vec<super::roster::Participant> {
        self.joined_roster.clone()
    }

    pub async fn participants(&self) -> Result<Vec<super::roster::Participant>> {
        let link = self
            .all_participants
            .clone()
            .context("No participant list for this call")?;
        let body = serde_json::json!({ "from": self.me.0, "scope": "call", "scenario": 0 });
        let reply = cc_post(&self.http, &self.skype_token, &link, &body, "Participants").await?;
        let list = reply
            .pointer("/response/participants")
            .or_else(|| reply.get("participants"))
            .cloned()
            .unwrap_or_default();
        // An array of {id, displayName, participantScreening}: put it in
        // roster-update form (keyed by MRI, with details and state).
        let by_mri: serde_json::Map<String, serde_json::Value> = list
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|p| {
                let id = p.get("id")?.as_str()?.to_string();
                let name = p
                    .get("displayName")
                    .and_then(|n| n.as_str())
                    .unwrap_or_default();
                let mut details = serde_json::json!({ "displayName": name });
                if let Some(screening) = p.get("participantScreening") {
                    details["propertyBag"] =
                        serde_json::json!({ "participantScreening": { "value": screening } });
                }
                Some((
                    id,
                    serde_json::json!({ "state": "active", "details": details }),
                ))
            })
            .collect();
        let event = serde_json::json!({ "callAgentPath": "conversation/rosterUpdate/", "body": { "participants": by_mri } });
        Ok(super::roster::roster_delta(&event.to_string()).unwrap_or_default())
    }

    /// Who is waiting in the meeting's lobby: (MRI, name), as Teams asks
    /// for them (getAllParticipants with scope "lobby").
    pub async fn lobby(&self) -> Result<Vec<LobbyPerson>> {
        let link = self
            .all_participants
            .clone()
            .context("No participant list for this call")?;
        let body = serde_json::json!({ "from": self.me.0, "scope": "lobby", "scenario": 0 });
        let reply = cc_post(&self.http, &self.skype_token, &link, &body, "Lobby").await?;
        tracing::debug!("lobby reply {reply}");
        Ok(lobby_people(&reply))
    }

    /// Admit someone from the lobby (Teams' admit link). `not_bot`: the
    /// organizer ticked "This isn't a bot" for a suspected guest, so their
    /// screening is cleared afterwards, as Teams does.
    pub async fn admit(&self, id: &str, name: &str, not_bot: bool) -> Result<()> {
        let link = self
            .admit_links
            .0
            .clone()
            .context("This meeting has no lobby to admit from")?;
        let cb = |p: &str| signaling::trouter_callback(&self.callbacks.0, &self.callbacks.1, p);
        let body = serde_json::json!({
            "participants": { "from": self.me.0, "to": [{ "id": id, "displayName": name }] },
            "links": {
                "admitFailure": cb("conversation/admitParticipantFailure/"),
                "admitSuccess": cb("conversation/admitParticipantSuccess/"),
            },
            "debugContent": { "causeId": uuid::Uuid::new_v4().to_string() },
        });
        cc_post(&self.http, &self.skype_token, &link, &body, "Admit").await?;
        if not_bot {
            self.mark_not_bot(id).await?;
        }
        Ok(())
    }

    /// What we share, for everyone (Teams' updateScreensharerPropertyBag
    /// when screen sharing starts): our `screenSharerAttributes` — the
    /// source ("Monitor" or "Window") and the annotation window's size (the
    /// shared screen's), which viewers need to show Annotate over it.
    pub async fn screen_sharer_attributes(
        &mut self,
        source: u8,
        size: Option<(u32, u32, u32)>,
    ) -> Result<()> {
        let link = self
            .properties_link
            .clone()
            .context("This meeting can't update participants")?;
        self.state_seq += 1;
        let op = uuid::Uuid::new_v4().to_string();
        let from = serde_json::json!({
            "id": self.me.0["id"],
            "endpointId": self.me.0["endpointId"],
            "participantId": self.me.0["participantId"],
        });
        let body = screen_sharer_body(
            from,
            source,
            size,
            self.state_seq,
            &op,
            &signaling::trouter_callback(
                &self.callbacks.0,
                &self.callbacks.1,
                "conversation/updateParticipantPropertiesStatus/",
            ),
        );
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "Screen sharer attributes",
        )
        .await?;
        tracing::info!(?size, "screen sharer attributes sent");
        Ok(())
    }

    /// Clear a guest's bot screening (Teams' markParticipantAsNotBot: an
    /// updateParticipantsProperties for that participant).
    async fn mark_not_bot(&self, id: &str) -> Result<()> {
        let link = self
            .properties_link
            .clone()
            .context("This meeting can't update participants")?;
        let op = uuid::Uuid::new_v4().to_string();
        let from = serde_json::json!({
            "id": self.me.0["id"],
            "endpointId": self.me.0["endpointId"],
            "participantId": self.me.0["participantId"],
        });
        let body = not_bot_body(
            from,
            id,
            &op,
            &crate::clock::now_iso_ms(),
            &signaling::trouter_callback(
                &self.callbacks.0,
                &self.callbacks.1,
                "conversation/updateParticipantPropertiesStatus/",
            ),
        );
        cc_post(&self.http, &self.skype_token, &link, &body, "Not a bot").await?;
        Ok(())
    }

    /// Deny someone in the lobby, or remove them from the meeting (Teams'
    /// removeParticipant with `to`).
    pub async fn remove(&self, id: &str, name: &str) -> Result<()> {
        let link = self
            .remove_link
            .clone()
            .context("This call can't remove people")?;
        let cb = |p: &str| signaling::trouter_callback(&self.callbacks.0, &self.callbacks.1, p);
        let body = serde_json::json!({
            "participants": { "from": self.me.0, "to": [{ "id": id, "displayName": name }] },
            "links": {
                "removeParticipantSuccess": cb("conversation/removeParticipantSuccess/"),
                "removeParticipantFailure": cb("conversation/removeParticipantFailure/"),
            },
        });
        cc_post(&self.http, &self.skype_token, &link, &body, "Remove").await?;
        Ok(())
    }

    /// Mute one participant (Teams' Mute participant: MuteSpecifiedSync on
    /// the conversation's mute link, scope "specified"). Returns who the
    /// reply says the meeting muted (the full result comes later, to the
    /// muteUnmuteAsync callback).
    pub async fn mute_participant(&self, id: &str) -> Result<Vec<String>> {
        self.mute(&[id], "Mute participant").await
    }

    /// Teams' mute of others (calling-pluginless muteAsync with ECS
    /// SkypeCalling enableAsyncMute on): POST the body to the conversation's
    /// mute link with a muteUnmuteAsync callback and an operation id. The
    /// service answers 202 at once and sends the result to the callback.
    async fn mute(&self, ids: &[&str], what: &str) -> Result<Vec<String>> {
        let link = self
            .mute_link
            .clone()
            .context("This meeting can't mute others")?;
        let operation = uuid::Uuid::new_v4().to_string();
        let callback = mute_callback(&self.callbacks.0, &self.callbacks.1, &operation);
        let scope = if ids.is_empty() { "all" } else { "specified" };
        let body = mute_body(&self.me.0, scope, ids, &callback, &operation);
        let reply = cc_send_in_call(
            &self.http,
            reqwest::Method::POST,
            &self.skype_token,
            &link,
            &body,
            what,
            Some(&self.call_id),
        )
        .await?;
        Ok(muted_by_reply(&reply))
    }

    /// Change someone's meeting role (Teams' Make an attendee / Make a
    /// presenter: updateParticipantRole, scope "specified").
    pub async fn set_role(&self, id: &str, role: &str) -> Result<()> {
        let link = self
            .role_link
            .clone()
            .context("This meeting can't change roles")?;
        let body = serde_json::json!({
            "from": {
                "id": self.me.0["id"],
                "endpointId": self.me.0["endpointId"],
                "participantId": self.me.0["participantId"],
                "languageId": self.me.0["languageId"],
            },
            "scope": "specified",
            "to": [{ "id": id, "meetingRole": role }],
        });
        cc_post(&self.http, &self.skype_token, &link, &body, "Meeting role").await?;
        Ok(())
    }

    /// Presenter modes (Standout, Side-by-side, Reporter): Teams' publishState
    /// "weatherPerson" at user level for everyone, its content the layout
    /// (`{mode, x, y, width, height, zOrder: 2, background?}`), so each
    /// receiver composites our camera over the shared screen. `None` takes
    /// it back (removeState, scope "all", that state type), as Teams does
    /// on Content only or when sharing stops.
    pub async fn weather_person(&mut self, layout: Option<serde_json::Value>) -> Result<()> {
        self.state_seq += 1;
        let from = self.me.0.clone();
        match layout {
            Some(content) => {
                let link = self
                    .state_links
                    .0
                    .clone()
                    .context("This meeting doesn't take presenter modes")?;
                let body = serde_json::json!({
                    "from": from,
                    "publishedState": {
                        "content": content,
                        "level": "user",
                        "stateType": "weatherPerson",
                        "sequenceNumber": self.state_seq,
                    },
                });
                cc_post(
                    &self.http,
                    &self.skype_token,
                    &link,
                    &body,
                    "Presenter mode",
                )
                .await?;
            }
            None => {
                let link = self
                    .state_links
                    .1
                    .clone()
                    .context("This meeting doesn't take presenter modes")?;
                let body = serde_json::json!({
                    "from": from,
                    "sequenceNumber": self.state_seq,
                    "scope": "all",
                    "stateType": "weatherPerson",
                });
                cc_post(&self.http, &self.skype_token, &link, &body, "Content only").await?;
            }
        }
        Ok(())
    }

    /// Sign language mode in this meeting (527114 SignerMixin): publish your
    /// role, "dhhSigner" (content `{interpreterIds, showSignerIdentification
    /// ToOthers}`) or "signLanguageInterpreter" (`{}`), at user level with no
    /// scope; the earlier state is removed first (scope "specified", its
    /// id), and `None` only removes it.
    pub async fn sign_language_state(
        &mut self,
        state: Option<(&str, serde_json::Value)>,
    ) -> Result<()> {
        let from = self.me.0.clone();
        if let Some(id) = self.sign_state_id.take() {
            self.state_seq += 1;
            let link = self
                .state_links
                .1
                .clone()
                .context("This meeting doesn't take sign language states")?;
            let body = serde_json::json!({ "from": from, "sequenceNumber": self.state_seq, "scope": "specified", "stateIds": [id] });
            cc_post(
                &self.http,
                &self.skype_token,
                &link,
                &body,
                "Sign language state off",
            )
            .await?;
        }
        if let Some((kind, content)) = state {
            self.state_seq += 1;
            let link = self
                .state_links
                .0
                .clone()
                .context("This meeting doesn't take sign language states")?;
            let body = serde_json::json!({
                "from": from,
                "publishedState": { "content": content, "level": "user", "stateType": kind, "sequenceNumber": self.state_seq },
            });
            let reply = cc_post(
                &self.http,
                &self.skype_token,
                &link,
                &body,
                "Sign language state",
            )
            .await?;
            self.sign_state_id = reply
                .pointer("/publishStateResponse/stateId")
                .or_else(|| reply.pointer("/publishStateResponse/publishedState/stateId"))
                .or_else(|| reply.pointer("/stateId"))
                .and_then(|v| v.as_str())
                .map(str::to_string);
            tracing::info!(
                kind,
                has_id = self.sign_state_id.is_some(),
                "sign language state published"
            );
        }
        Ok(())
    }

    /// Remove someone's published state by its id (Teams' removeState,
    /// scope "specified"): stop their spotlight, or lower their raised hand
    /// (Teams' lowerOtherParticipantsHand from their tile or roster row).
    pub async fn remove_state(&mut self, state_id: &str, what: &str) -> Result<()> {
        self.state_seq += 1;
        let link = self
            .state_links
            .1
            .clone()
            .with_context(|| format!("{what}: this meeting has no removeState link"))?;
        let body = serde_json::json!({ "from": self.me.0.clone(), "sequenceNumber": self.state_seq, "scope": "specified", "stateIds": [state_id] });
        cc_post(&self.http, &self.skype_token, &link, &body, what).await?;
        Ok(())
    }

    /// Spotlight someone for everyone (Teams' publishState: "spotlight" at
    /// user level, scope "specified" with them), or stop (removeState of
    /// that state).
    pub async fn spotlight(&mut self, id: &str, state_id: Option<&str>) -> Result<()> {
        if let Some(state) = state_id {
            return self.remove_state(state, "Stop spotlight").await;
        }
        self.state_seq += 1;
        let from = self.me.0.clone();
        let link = self
            .state_links
            .0
            .clone()
            .context("This meeting can't spotlight")?;
        // Teams (enableContentShareQueueInManagedMode, on): what of theirs
        // is on screen, the person (and not their screen share). An object,
        // as Teams' calling stack posts a state's content.
        let content = serde_json::json!({ "isParticipantSpotlighted": true, "isScreenShareSpotlighted": false });
        let body = serde_json::json!({
            "from": from,
            "publishedState": {
                "content": content,
                "level": "user",
                "stateType": "spotlight",
                "sequenceNumber": self.state_seq,
            },
            "scope": "specified",
            "to": [{ "id": id }],
        });
        cc_post(&self.http, &self.skype_token, &link, &body, "Spotlight").await?;
        Ok(())
    }

    /// Held in the meeting's lobby.
    pub fn in_lobby(&self) -> bool {
        self.in_lobby
    }

    /// The meeting has started (someone is in it).
    pub fn meeting_started(&self) -> bool {
        self.meeting_started
    }

    /// Our leg was moved to another call (admitted from the lobby, the
    /// lobby's call hands us to the meeting's): from now on the leg's links
    /// are the new ones, so hanging up ends the leg we're really on.
    pub fn retarget(&mut self, links: LegLinks) {
        tracing::info!("call leg retargeted");
        self.call_leg = Some(links.call_leg);
        if links.hold.is_some() {
            self.hold_link = links.hold;
        }
        if links.transfer.is_some() {
            self.transfer_link = links.transfer;
        }
        if let Some(l) = links
            .renegotiation
            .filter(|l| super::incoming::is_service_link(l))
        {
            self.renegotiation_link = Some(l);
        }
        if let (Some(l), Some((old, _))) =
            (links.media_descriptions, self.media_descriptions.as_mut())
        {
            *old = l;
        }
    }

    /// Admitted from the lobby: take the conversation's links from the
    /// update that admitted us (the lobby's join response has only a few).
    pub fn admit_from_lobby(&mut self, update: &serde_json::Value) {
        let body = update.to_string();
        let link = |name: &str| conversation_link(&body, name);
        self.state_links = (
            link("publishState").or(self.state_links.0.take()),
            link("removeState"),
        );
        self.all_participants = link("getAllParticipants");
        self.admit_links = (link("admit"), link("admitAll"));
        self.remove_link = link("removeParticipant");
        self.properties_link = link("updateParticipantProperties");
        self.role_link = link("updateParticipantRole");
        self.settings_link = link("updateMeetingSettings");
        self.group_links = (
            link("joinMeetingGroup").or(self.group_links.0.take()),
            link("leaveMeetingGroup").or(self.group_links.1.take()),
        );
        self.mute_link = link("mute");
        self.metadata_link = link("updateEndpointMetadata").or(self.metadata_link.take());
        self.add_participant_link = link("addParticipant").or(self.add_participant_link.take());
        self.meeting_states_link = link("updateMeetingStates").or(self.meeting_states_link.take());
        self.live_state_link = link("updateMeetingLiveState").or(self.live_state_link.take());
        self.layout_link = link("setMeetingLayout").or(self.layout_link.take());
        if let Some(e) = super::live_event::live_event(update) {
            self.event = e;
        }
        self.add_modality_link =
            link("addParticipantAndModality").or(self.add_modality_link.take());
        self.content_link = link("addModality").or(self.content_link.take());
        self.apply_phone_audio(update);
        self.unmute_link = link("unmute");
        self.message_link = link("sendMessage");
        if let Some(l) = link("updateEndpointState") {
            self.endpoint_state = Some((l, std::sync::atomic::AtomicU64::new(0)));
        }
        if let Some(c) = controller_link(&body) {
            self.controller = Some(c);
        }
        if let Some(c) = super::meeting_options::meeting_capability(update) {
            self.capability = c;
        }
        self.lobby_thread = group_chat_field(&body, "lobbyThreadId").or(self.lobby_thread.take());
        // Joined by the meeting's ID while the lobby held us: its chat is
        // named now.
        if self.thread_id.is_empty()
            && let Some(t) = group_chat_field(&body, "threadId").filter(|t| t.starts_with("19:"))
        {
            tracing::info!("the meeting's chat is named on admission");
            self.thread_id = t;
        }
        self.in_lobby = false;
        tracing::info!(
            has_mute = self.mute_link.is_some(),
            has_admit = self.admit_links.0.is_some(),
            "admitted from the lobby"
        );
    }

    /// The meeting's lock and attendee restrictions, as last reported.
    pub fn capability(&self) -> super::meeting_options::MeetingCapability {
        self.capability
    }

    /// What the meeting's call recorder is doing now.
    pub fn processing(&self) -> super::roster::Processing {
        self.recorder.processing()
    }

    /// Note a roster update's call recorder state; true when what it does
    /// changed.
    pub fn apply_processing(&mut self, json: &serde_json::Value) -> bool {
        self.recorder.apply(json)
    }

    /// Teams' bar shows the AI indicator in this meeting.
    pub fn shows_ai_indicator(&self) -> bool {
        self.ai_indicator
    }

    /// The meeting is a Meet now.
    pub fn is_meet_now(&self) -> bool {
        self.meet_now
    }

    /// The meeting has a call recorder to command (Record and transcribe).
    pub fn has_recorder(&self) -> bool {
        self.recorder.has_recorder()
    }

    /// Ask the meeting's call recorder to start or stop the transcript or
    /// recording, as Teams' Record and transcribe menu does.
    pub async fn recorder_command(
        &self,
        command: super::recorder::Command,
        meeting: &super::recorder::Meeting,
    ) -> Result<()> {
        self.recorder
            .command(
                &self.http,
                &self.skype_token,
                &self.me.0,
                &self.call_id,
                command,
                meeting,
            )
            .await
    }

    /// Invite the meeting's recorder (Teams does when you start captions,
    /// the transcript or a recording and it isn't in the call yet). The
    /// roster then lists it with its command URL.
    pub async fn add_recorder(&self, meeting: &super::recorder::Meeting) -> Result<()> {
        let link = self
            .add_participant_link
            .clone()
            .context("No addParticipant link")?;
        if !super::incoming::is_service_link(&link) {
            bail!("addParticipant: not a Teams service link");
        }
        let (surl, epid) = &self.callbacks;
        let tc = |p: &str| signaling::trouter_callback(surl, epid, p);
        let links = serde_json::json!({
            "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
            "addParticipantFailure": tc("conversation/addParticipantFailure/"),
        });
        super::recorder::invite(
            &self.http,
            &link,
            &self.me.0,
            meeting,
            &self.call_id,
            &self.thread_id,
            links,
        )
        .await
    }

    /// Merge another call's people into this one (Teams' P2PAndP2P merge):
    /// this call becomes a group call on `thread_id` (the chat of everyone
    /// in both calls) and each person is added with the leg they replace in
    /// the other call ([`merge_body`]). The other call is left afterwards.
    pub async fn merge_in(&self, thread_id: &str, people: &[MergePerson]) -> Result<()> {
        let link = self
            .add_participant_link
            .clone()
            .context("No addParticipant link")?;
        if !super::incoming::is_service_link(&link) {
            bail!("addParticipant: not a Teams service link");
        }
        let config = Config::load()?;
        let ic3 = config
            .get_ic3_token()
            .context("No calling (IC3) token")?
            .token;
        let (surl, epid) = &self.callbacks;
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-US".into());
        }
        let body = merge_body(&from, thread_id, people, |p| {
            signaling::trouter_callback(surl, epid, p)
        });
        tracing::info!(people = people.len(), "merging calls");
        let resp = self
            .http
            .post(&link)
            .bearer_auth(ic3)
            .header("x-microsoft-skype-chain-id", &self.call_id)
            .header(
                "x-microsoft-skype-message-id",
                uuid::Uuid::new_v4().to_string(),
            )
            .header("x-microsoft-skype-client", signaling::SKYPE_CLIENT_HEADER)
            .header("ms-teams-partition", signaling::TEAMS_PARTITION)
            .header("ms-teams-region", signaling::TEAMS_REGION)
            .header("ms-teams-ring", signaling::TEAMS_RING)
            .json(&body)
            .send()
            .await
            .context("Merging calls")?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            bail!(
                "Merging calls failed ({status}): {}",
                &text[..text.len().min(300)]
            );
        }
        tracing::info!(%status, "merge requested");
        Ok(())
    }

    /// Tell the meeting whether we want live captions, as Teams does once
    /// they start or stop: `PUT updateEndpointMetadata` with our
    /// participant (and its language) and `transcriptionPrefs`.
    pub async fn publish_captions_pref(&self, on: bool) -> Result<()> {
        let link = self
            .metadata_link
            .clone()
            .context("No endpoint metadata link")?;
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let body = serde_json::json!({
            "participants": { "from": from },
            "endpointMetadata": { "transcriptionPrefs": { "closedCaptions": on } },
        });
        cc_send(
            &self.http,
            reqwest::Method::PUT,
            &self.skype_token,
            &link,
            &body,
            "Endpoint metadata",
        )
        .await?;
        Ok(())
    }

    /// After adding a nearby Teams Room (Cast, Room audio), say we joined
    /// in it, as Teams' endpoint does: `PUT updateEndpointMetadata` with
    /// our participant and `meetingRoom` {email, mri} (seen in the room's
    /// roster when Teams cast to OST Test Room, 2026-11-23). Everyone's
    /// roster then nests us under the room and counts us in the room.
    pub async fn publish_meeting_room(&self, room_mri: &str, room_email: &str) -> Result<()> {
        let link = self
            .metadata_link
            .clone()
            .context("No endpoint metadata link")?;
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let body = serde_json::json!({
            "participants": { "from": from },
            "endpointMetadata": { "holographicCapabilities": 3, "meetingRoom": { "email": room_email, "mri": room_mri } },
        });
        cc_send(
            &self.http,
            reqwest::Method::PUT,
            &self.skype_token,
            &link,
            &body,
            "Endpoint metadata",
        )
        .await?;
        tracing::info!(room = room_mri, "joined in the room (endpoint metadata)");
        Ok(())
    }

    /// The meeting's stored transcript and transcript starts and stops
    /// (Teams' Transcript pane, on opening).
    pub async fn transcript_history(&self) -> Result<Vec<super::transcript::Entry>> {
        let link = self
            .artifacts_link
            .clone()
            .context("The meeting has no transcript store")?;
        super::transcript::history(&self.http, &link, &self.call_id).await
    }

    /// Who answered the call, when the service named them.
    pub fn answered_by(&self) -> Option<&str> {
        self.answered_by.as_deref()
    }

    /// The tag in this call's callback URLs.
    pub fn call_tag(&self) -> &str {
        &self.call_tag
    }

    /// The meeting conversation's own URL: its controller, else its leave
    /// link without `/leave`.
    pub fn conversation_url(&self) -> Option<String> {
        self.controller.clone().or_else(|| {
            let l = self.leave_link.as_deref()?;
            let (path, query) = l.split_once('?').unwrap_or((l, ""));
            let path = path.trim_end_matches('/').strip_suffix("/leave")?;
            Some(if query.is_empty() {
                path.to_string()
            } else {
                format!("{path}?{query}")
            })
        })
    }

    /// Leave the meeting as Teams leaves one it moves out of (`POST
    /// links.leave`), else hang up.
    pub async fn leave_or_hang_up(self) -> Result<()> {
        if self.leave_link.is_some() {
            self.leave().await
        } else {
            self.hang_up().await
        }
    }

    /// Our participant id in the call.
    pub fn participant_id(&self) -> &str {
        self.me.0["participantId"].as_str().unwrap_or_default()
    }

    /// The call's id (the chain id everyone in it shares).
    pub fn call_id(&self) -> &str {
        &self.call_id
    }

    /// The chat thread the call is in.
    pub fn thread(&self) -> &str {
        &self.thread_id
    }

    /// The meeting's message in its chat (Teams' teamsMessageId: "0" for
    /// a meeting).
    pub fn message_id(&self) -> &str {
        self.group_message_id.as_deref().unwrap_or("0")
    }

    /// The meeting organizer's object id (the join response's meetingInfo).
    pub fn organizer_oid(&self) -> Option<&str> {
        self.notes_organizer
            .split('@')
            .next()
            .filter(|o| !o.is_empty())
    }

    /// The meeting's title, times, location and calendar link (Meeting info).
    pub fn meeting_info(&self) -> Option<super::meeting_info::MeetingInfo> {
        self.meeting_info.clone()
    }

    /// The meeting's dial-in details, when it has them.
    pub fn dial_in(&self) -> Option<&super::phone_audio::DialIn> {
        self.dial_in.as_ref()
    }

    /// Whether the meeting offers phone audio.
    pub fn phone_audio(&self) -> super::phone_audio::PhoneAudio {
        self.phone_audio
    }

    /// Note a conversation update's meeting details (dial-in, PSTN
    /// capability); true when they changed. An update without dial-in
    /// details keeps the ones the join gave.
    pub fn apply_phone_audio(&mut self, json: &serde_json::Value) -> bool {
        let Some(mut p) = super::phone_audio::phone_audio(json, false) else {
            return false;
        };
        let d = super::phone_audio::dial_in(json).or_else(|| self.dial_in.clone());
        if d.is_some() && super::phone_audio::dial_in(json).is_none() {
            p.available = p.dial_in && p.dial_out;
        }
        let changed = p != self.phone_audio || d != self.dial_in;
        self.phone_audio = p;
        self.dial_in = d;
        changed
    }

    /// The phone "Call me" is calling, if any.
    pub fn call_me_pending(&self) -> Option<&str> {
        self.call_me.as_deref()
    }

    /// Teams' "Call me": ask the meeting to call `phone_mri` ("4:+1…") and
    /// put it in the meeting as our audio
    /// (`POST links.addParticipantAndModality`). The outcome comes back as
    /// an addParticipantSuccess / addParticipantFailure event.
    pub async fn call_me_back(&mut self, phone_mri: &str) -> Result<()> {
        if !phone_mri.starts_with("4:") || phone_mri.len() < 4 {
            bail!("Not a phone number");
        }
        let link = self
            .add_modality_link
            .clone()
            .context("No addParticipantAndModality link")?;
        if !super::incoming::is_service_link(&link) {
            bail!("addParticipantAndModality: not a Teams service link");
        }
        let config = Config::load()?;
        let ic3 = config
            .get_ic3_token()
            .context("No calling (IC3) token")?
            .token;
        let (surl, epid) = &self.callbacks;
        let tc = |p: &str| signaling::trouter_callback(surl, epid, p);
        let links = serde_json::json!({
            "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
            "addParticipantFailure": tc("conversation/addParticipantFailure/"),
        });
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let body = super::phone_audio::call_me_back_body(
            &from,
            phone_mri,
            &self.thread_id,
            self.group_message_id.as_deref(),
            links,
        );
        tracing::info!("call me back");
        let resp = self
            .http
            .post(&link)
            .bearer_auth(ic3)
            .header("x-microsoft-skype-chain-id", &self.call_id)
            .header(
                "x-microsoft-skype-message-id",
                uuid::Uuid::new_v4().to_string(),
            )
            .header("x-microsoft-skype-client", signaling::SKYPE_CLIENT_HEADER)
            .header("ms-teams-partition", signaling::TEAMS_PARTITION)
            .header("ms-teams-region", signaling::TEAMS_REGION)
            .header("ms-teams-ring", signaling::TEAMS_RING)
            .json(&body)
            .send()
            .await
            .context("Call me")?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            bail!(
                "Call me failed ({status}): {}",
                &text[..text.len().min(300)]
            );
        }
        tracing::info!(%status, "call me back accepted");
        self.call_me = Some(phone_mri.to_string());
        Ok(())
    }

    /// Teams' "join with a room" (RoomAudio): once in the meeting, add the
    /// room account `room_mri` ("8:orgid:…") to it, as Teams'
    /// addRoomParticipant does. The conversation is asked to invite it
    /// (`POST links.addParticipantAndModality`) with Teams' invitation
    /// data: how the room was found (`proximitySource`: 1 Bluetooth, which
    /// Teams also sends for a room picked from a search, or 2 ultrasound),
    /// that a computer asks (`deviceType`), the Bluetooth beacon's
    /// validation code as `autoAcceptAuthorization` (a Teams Rooms device
    /// then joins by itself), and the meeting's organizer and tenant. The
    /// outcome comes back as addParticipantSuccess / addParticipantFailure.
    pub async fn add_room(
        &mut self,
        room_mri: &str,
        room_name: &str,
        validation_code: Option<u16>,
        ultrasound: bool,
    ) -> Result<()> {
        if crate::identity::work_object_id(room_mri).is_none() {
            bail!("Not a room account");
        }
        let link = self
            .add_modality_link
            .clone()
            .context("No addParticipantAndModality link")?;
        if !super::incoming::is_service_link(&link) {
            bail!("addParticipantAndModality: not a Teams service link");
        }
        let config = Config::load()?;
        let ic3 = config
            .get_ic3_token()
            .context("No calling (IC3) token")?
            .token;
        let (surl, epid) = &self.callbacks;
        let tc = |p: &str| signaling::trouter_callback(surl, epid, p);
        let links = serde_json::json!({
            "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
            "addParticipantFailure": tc("conversation/addParticipantFailure/"),
        });
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let meeting_info = self
            .notes_organizer
            .split_once('@')
            .map(|(o, t)| (o.to_string(), t.to_string()));
        let body = room_invite_body(
            &from,
            room_mri,
            room_name,
            &self.thread_id,
            self.group_message_id.as_deref(),
            validation_code,
            ultrasound,
            meeting_info,
            links,
        );
        tracing::info!(
            room = room_mri,
            code = validation_code.is_some(),
            "adding the room to the meeting"
        );
        let resp = self
            .http
            .post(&link)
            .bearer_auth(ic3)
            .header("x-microsoft-skype-chain-id", &self.call_id)
            .header(
                "x-microsoft-skype-message-id",
                uuid::Uuid::new_v4().to_string(),
            )
            .header("x-microsoft-skype-client", signaling::SKYPE_CLIENT_HEADER)
            .header("ms-teams-partition", signaling::TEAMS_PARTITION)
            .header("ms-teams-region", signaling::TEAMS_REGION)
            .header("ms-teams-ring", signaling::TEAMS_RING)
            .json(&body)
            .send()
            .await
            .context("Add the room")?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            bail!(
                "Adding the room failed ({status}): {}",
                &text[..text.len().min(300)]
            );
        }
        tracing::info!(%status, "room invitation accepted by the conversation");
        self.room_pending = Some(room_mri.to_string());
        Ok(())
    }

    /// Invite people into the call from the People pane, as Teams' roster
    /// people picker does (its `addParticipantsAsync`): `POST` the
    /// conversation's addParticipantAndModality link (`…/add`) with each
    /// person and the call's group chat ([`invite_body`]). The service
    /// rings them; a 1:1 call becomes a group call on `thread_id` (the
    /// chat of everyone in it). The outcome comes back as
    /// addParticipantSuccess / addParticipantFailure
    /// ([`Self::invite_outcome`]).
    pub async fn invite_people(&mut self, thread_id: &str, people: &[String]) -> Result<()> {
        let link = self
            .add_modality_link
            .clone()
            .context("No addParticipantAndModality link")?;
        if !super::incoming::is_service_link(&link) {
            bail!("addParticipantAndModality: not a Teams service link");
        }
        let config = Config::load()?;
        let ic3 = config
            .get_ic3_token()
            .context("No calling (IC3) token")?
            .token;
        let (surl, epid) = &self.callbacks;
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let to: Vec<(String, String)> = people
            .iter()
            .map(|m| (m.clone(), uuid::Uuid::new_v4().to_string()))
            .collect();
        let body = invite_body(&from, thread_id, &to, |p| {
            signaling::trouter_callback(surl, epid, p)
        });
        tracing::info!(people = people.len(), "inviting people into the call");
        let resp = self
            .http
            .post(&link)
            .bearer_auth(ic3)
            .header("x-microsoft-skype-chain-id", &self.call_id)
            .header(
                "x-microsoft-skype-message-id",
                uuid::Uuid::new_v4().to_string(),
            )
            .header("x-microsoft-skype-client", signaling::SKYPE_CLIENT_HEADER)
            .header("ms-teams-partition", signaling::TEAMS_PARTITION)
            .header("ms-teams-region", signaling::TEAMS_REGION)
            .header("ms-teams-ring", signaling::TEAMS_RING)
            .header("x-ms-migration", "True")
            .json(&body)
            .send()
            .await
            .context("Invite into the call")?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            bail!(
                "Inviting into the call failed ({status}): {}",
                &text[..text.len().min(300)]
            );
        }
        tracing::info!(%status, "invitation accepted by the conversation");
        // A 1:1 call goes on as the group chat's call.
        self.thread_id = thread_id.to_string();
        for m in people {
            if !self.invited.iter().any(|i| i.eq_ignore_ascii_case(m)) {
                self.invited.push(m.clone());
            }
        }
        Ok(())
    }

    /// The call's answer to someone we invited, if `event` is one: their
    /// MRI, and Ok when they joined or Err(Teams' message) when they
    /// couldn't be added (declined, no answer). Either way they stop being
    /// pending.
    pub fn invite_outcome(
        &mut self,
        event: &serde_json::Value,
    ) -> Option<(String, std::result::Result<(), String>)> {
        let (i, r) =
            self.invited.iter().enumerate().find_map(|(i, m)| {
                super::phone_audio::call_me_back_result(event, m).map(|r| (i, r))
            })?;
        Some((self.invited.remove(i), r))
    }

    /// The meeting's answer to adding the room, if `event` is it: Ok when
    /// the room joined, Err(Teams' message) when it couldn't.
    /// Ask the conversation service (`method` on `link`, a Teams service
    /// address) with the calling token and Teams' headers, plus a content
    /// session's chain id.
    async fn content_request(
        &self,
        method: reqwest::Method,
        link: &str,
        body: &serde_json::Value,
        chain: &str,
    ) -> Result<String> {
        if !super::incoming::is_service_link(link) {
            bail!("content sharing: not a Teams service link");
        }
        let config = Config::load()?;
        let ic3 = config
            .get_ic3_token()
            .context("No calling (IC3) token")?
            .token;
        let resp = self
            .http
            .request(method.clone(), link)
            .bearer_auth(ic3)
            .header(super::content_sharing::CHAIN_ID_HEADER, chain)
            .header("x-microsoft-skype-chain-id", &self.call_id)
            .header(
                "x-microsoft-skype-message-id",
                uuid::Uuid::new_v4().to_string(),
            )
            .header("x-microsoft-skype-client", signaling::SKYPE_CLIENT_HEADER)
            .header("ms-teams-partition", signaling::TEAMS_PARTITION)
            .header("ms-teams-region", signaling::TEAMS_REGION)
            .header("ms-teams-ring", signaling::TEAMS_RING)
            .json(body)
            .send()
            .await
            .context("content sharing")?;
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        if !status.is_success() {
            bail!(
                "content sharing {method} failed ({status}): {}",
                &text[..text.len().min(300)]
            );
        }
        tracing::info!(%method, %status, "content sharing request");
        Ok(text)
    }

    /// Our participant as content-sharing requests name it.
    fn content_from(&self) -> serde_json::Value {
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-US".into());
        }
        from
    }

    fn content_callback(&self) -> impl Fn(&str) -> String + '_ {
        let (surl, epid) = &self.callbacks;
        move |p: &str| signaling::trouter_callback(surl, epid, p)
    }

    /// Whether this call can present content-sharing sessions (the
    /// conversation gave its addModality link).
    pub fn can_share_content(&self) -> bool {
        self.content_link.is_some()
    }

    /// Start presenting `content` (Teams' sharing-content DTO) with an
    /// optional first state: `POST links.addModality`. The session is ours
    /// once `conversation/addModalitySuccess/` names its correlation id
    /// ([`OutgoingCall::content_started`]). Returns the correlation id.
    pub async fn start_content_sharing(
        &mut self,
        content: serde_json::Value,
        subject: &str,
        state: Option<&str>,
    ) -> Result<String> {
        use super::content_sharing as cs;
        let link = self
            .content_link
            .clone()
            .context("This call can't share content (no addModality link)")?;
        let correlation = uuid::Uuid::new_v4().to_string();
        let identifier = cs::encode_identifier(&content);
        let body = cs::add_modality_body(
            &self.content_from(),
            &identifier,
            subject,
            state,
            &self.content_callback(),
        );
        tracing::info!(kind = cs::content_type(&content), %correlation, "content sharing: adding the modality");
        self.content_request(reqwest::Method::POST, &link, &body, &correlation)
            .await?;
        self.my_content = Some(cs::Session {
            correlation_id: correlation.clone(),
            presenter: self
                .me
                .0
                .get("id")
                .and_then(|i| i.as_str())
                .unwrap_or_default()
                .to_ascii_lowercase(),
            content,
            identifier,
            subject: subject.to_string(),
            state: state.unwrap_or_default().to_string(),
            mine: true,
            ..Default::default()
        });
        Ok(correlation)
    }

    /// Our session's addModalitySuccess (true: it started) or failure
    /// (Err: Teams' phrase), if `event` is either for it.
    pub fn content_started(
        &mut self,
        event: &serde_json::Value,
    ) -> Option<std::result::Result<super::content_sharing::Session, String>> {
        use super::content_sharing as cs;
        let mine = self.my_content.as_mut()?;
        if let Some((corr, session, links, state)) = cs::add_modality_success(event) {
            if !corr.is_empty() && corr != mine.correlation_id {
                return None;
            }
            mine.session_id = session;
            mine.links = links;
            if let Some(s) = state {
                mine.state = s;
            }
            tracing::info!(session = %mine.session_id, update = mine.links.update_state.is_some(), "content sharing started");
            return Some(Ok(mine.clone()));
        }
        if let Some(why) = cs::add_modality_failure(event) {
            tracing::warn!(%why, "content sharing failed");
            self.my_content = None;
            return Some(Err(why));
        }
        None
    }

    /// The session we present, if any.
    pub fn my_content(&self) -> Option<&super::content_sharing::Session> {
        self.my_content.as_ref()
    }

    /// Send our session's new state (`POST links.updateSessionState`).
    pub async fn update_content_state(&mut self, state: &str) -> Result<()> {
        let from = self.content_from();
        let mine = self.my_content.as_mut().context("Not sharing content")?;
        let link = mine
            .links
            .update_state
            .clone()
            .context("The session has no updateSessionState link yet")?;
        mine.sequence += 1;
        mine.state = state.to_string();
        let body = super::content_sharing::update_state_body(
            &from,
            mine.sequence,
            state,
            &uuid::Uuid::new_v4().to_string(),
        );
        let chain = mine.correlation_id.clone();
        self.content_request(reqwest::Method::POST, &link, &body, &chain)
            .await
            .map(|_| ())
    }

    /// Stop presenting (`DELETE links.contentSharingController`).
    pub async fn stop_content_sharing(&mut self) -> Result<()> {
        let Some(mine) = self.my_content.take() else {
            return Ok(());
        };
        let link = mine
            .links
            .controller
            .clone()
            .context("The session has no controller link")?;
        let body = super::content_sharing::stop_body(&self.content_from());
        tracing::info!(correlation = %mine.correlation_id, "content sharing: stopping");
        self.content_request(reqwest::Method::DELETE, &link, &body, &mine.correlation_id)
            .await
            .map(|_| ())
    }

    /// Join a session someone else presents (from the roster), to get its
    /// state updates: `POST sessionInformation.contentSharingController`.
    pub async fn join_content(
        &mut self,
        mut session: super::content_sharing::Session,
    ) -> Result<super::content_sharing::Session> {
        if let Some(s) = self.joined_content.get(&session.correlation_id) {
            return Ok(s.clone());
        }
        let link = session
            .join_link
            .clone()
            .context("The session has no join link")?;
        let body =
            super::content_sharing::join_body(&self.content_from(), &self.content_callback());
        let text = self
            .content_request(reqwest::Method::POST, &link, &body, &session.correlation_id)
            .await?;
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
            let cs = v.get("contentSharing").unwrap_or(&v);
            session.links = super::content_sharing::SessionLinks::from(
                cs.get("links").unwrap_or(&serde_json::Value::Null),
            );
            if let Some(st) = cs
                .get("sessionState")
                .and_then(|s| s.as_str())
                .filter(|s| !s.is_empty())
            {
                session.state = st.to_string();
            }
            if let Some(n) = cs.get("sequenceNumber").and_then(|n| n.as_u64()) {
                session.sequence = n;
            }
        }
        tracing::info!(correlation = %session.correlation_id, kind = session.kind(), "content sharing: joined");
        self.joined_content
            .insert(session.correlation_id.clone(), session.clone());
        Ok(session)
    }

    /// A state update for a session we joined (newer than the last), or
    /// its end: (correlation id, Some(new state)) or (correlation id, None).
    pub fn content_event(&mut self, event: &serde_json::Value) -> Option<(String, Option<String>)> {
        use super::content_sharing as cs;
        if let Some((corr, state, seq)) = cs::session_update(event) {
            if let Some(s) = self.joined_content.get_mut(&corr) {
                if seq != 0 && seq <= s.sequence {
                    return None;
                }
                s.sequence = seq;
                s.state = state.clone();
            }
            return Some((corr, Some(state)));
        }
        if let Some(corr) = cs::session_end(event) {
            self.joined_content.remove(&corr);
            if self
                .my_content
                .as_ref()
                .is_some_and(|m| m.correlation_id == corr)
            {
                self.my_content = None;
            }
            return Some((corr, None));
        }
        None
    }

    /// Take over a session someone else presents (PowerPoint Live's Take
    /// control): `POST links.takeControl` from the session's join; once
    /// it answers the session is ours (its state goes out through our
    /// updateSessionState from then on).
    pub async fn take_content_control(
        &mut self,
        correlation: &str,
    ) -> Result<super::content_sharing::Session> {
        use super::content_sharing as cs;
        let s = self
            .joined_content
            .get(correlation)
            .cloned()
            .context("Not viewing that session")?;
        let link = s
            .links
            .take_control
            .clone()
            .context("The session has no takeControl link")?;
        let body = cs::take_control_body(&self.content_from());
        tracing::info!(%correlation, "content sharing: taking control");
        let text = self
            .content_request(reqwest::Method::POST, &link, &body, correlation)
            .await?;
        let mut mine = s;
        mine.mine = true;
        mine.presenter = self
            .me
            .0
            .get("id")
            .and_then(|i| i.as_str())
            .unwrap_or_default()
            .to_ascii_lowercase();
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
            let c = v.get("contentSharing").unwrap_or(&v);
            mine.links.merge(cs::SessionLinks::from(
                c.get("links").unwrap_or(&serde_json::Value::Null),
            ));
            if let Some(st) = c
                .get("sessionState")
                .and_then(|s| s.as_str())
                .filter(|s| !s.is_empty())
            {
                mine.state = st.to_string();
            }
            if let Some(n) = c.get("sequenceNumber").and_then(|n| n.as_u64()) {
                mine.sequence = mine.sequence.max(n);
            }
        }
        tracing::info!(
            update = mine.links.update_state.is_some(),
            "content sharing: we present now"
        );
        self.joined_content.remove(correlation);
        self.my_content = Some(mine.clone());
        Ok(mine)
    }

    /// A session's presenter changed (someone took control): if it was
    /// ours, it becomes one we view. (correlation id, the new presenter,
    /// whether it was taken from us.)
    pub fn content_presenter(
        &mut self,
        event: &serde_json::Value,
    ) -> Option<(String, String, bool)> {
        let (corr, presenter) = super::content_sharing::update_presenter(event)?;
        let me = self
            .me
            .0
            .get("id")
            .and_then(|i| i.as_str())
            .unwrap_or_default()
            .to_ascii_lowercase();
        if self
            .my_content
            .as_ref()
            .is_some_and(|m| m.correlation_id == corr)
            && presenter != me
        {
            let mut s = self.my_content.take()?;
            tracing::info!(%corr, "content sharing: someone took control");
            s.mine = false;
            s.presenter = presenter.clone();
            // We keep getting its updates (our session's callbacks).
            self.joined_content.insert(corr.clone(), s);
            return Some((corr, presenter, true));
        }
        if let Some(s) = self.joined_content.get_mut(&corr)
            && s.presenter != presenter
            && presenter != me
        {
            s.presenter = presenter.clone();
            return Some((corr, presenter, false));
        }
        None
    }

    /// What sends PowerPoint Live's pointer (laser, cursor) to everyone:
    /// proxied LiveInking messages (Teams' sendLiveInkingMessage), sent
    /// without holding the call.
    pub fn live_inking_sender(&self) -> Option<LiveInkingSender> {
        Some(LiveInkingSender {
            http: self.http.clone(),
            token: self.skype_token.clone(),
            link: self.message_link.clone()?,
            me: self.me.0.clone(),
        })
    }

    /// Forget a joined session that left the roster.
    pub fn forget_content(&mut self, correlation: &str) {
        self.joined_content.remove(correlation);
    }

    pub fn room_outcome(
        &mut self,
        event: &serde_json::Value,
    ) -> Option<std::result::Result<String, String>> {
        let mri = self.room_pending.clone()?;
        let r = super::phone_audio::call_me_back_result(event, &mri)?;
        self.room_pending = None;
        Some(r.map(|()| mri))
    }

    /// The meeting's answer to "Call me", if `event` is it: Ok(the phone's
    /// id) when it joined, Err(Teams' message) when it failed. The pending
    /// number is forgotten either way.
    pub fn call_me_outcome(
        &mut self,
        event: &serde_json::Value,
    ) -> Option<std::result::Result<String, String>> {
        let mri = self.call_me.clone()?;
        let r = super::phone_audio::call_me_back_result(event, &mri)?;
        self.call_me = None;
        Some(r.map(|()| mri))
    }

    /// Stop waiting for a Call me (Teams gives it 120 s).
    pub fn cancel_call_me(&mut self) {
        self.call_me = None;
    }

    /// Note a conversation update; true when the meeting's lock or
    /// attendee restrictions changed.
    /// The meeting timer as last received.
    pub fn timers(&self) -> &super::meeting_timer::Timers {
        &self.timers
    }

    /// Take a conversation update's meeting timer; true when it's new.
    pub fn apply_timer(&mut self, json: &serde_json::Value) -> bool {
        let Some(state) = super::meeting_timer::Timers::find(json) else {
            return false;
        };
        match super::meeting_timer::Timers::from_state(state, &self.timers) {
            Some(t) if t.sequence != self.timers.sequence || t != self.timers => {
                self.timers = t;
                true
            }
            _ => false,
        }
    }

    /// What Teams' meeting-notes service is told about this meeting
    /// (getOrCreateMeetingNotes): its chat thread, organizer (`oid@tid`),
    /// title, join link and calendar id.
    pub fn notes_context(&self) -> serde_json::Value {
        let info = self.meeting_info.clone();
        let s = |f: fn(&super::meeting_info::MeetingInfo) -> &String| {
            info.as_ref().map(|i| f(i).clone()).unwrap_or_default()
        };
        serde_json::json!({
            "threadId": self.thread_id,
            "organizer": self.notes_organizer,
            "meetingTitle": info.as_ref().map(|i| super::meeting_info::notes_title(i).to_string()).unwrap_or_default(),
            "meetingUrl": s(|i| &i.join_url),
            "iCalUid": s(|i| &i.ical_uid),
        })
    }

    /// The meeting's notes as last received.
    pub fn notes(&self) -> &super::meeting_notes::Notes {
        &self.notes
    }

    /// Take a conversation update's notes states; true when they changed.
    pub fn apply_notes(&mut self, json: &serde_json::Value) -> bool {
        self.notes.apply(json)
    }

    /// Set meeting states for everyone (Teams' updateMeetingStates), such
    /// as the notes' claim and link.
    pub async fn publish_meeting_states(
        &self,
        states: serde_json::Value,
        what: &str,
    ) -> Result<()> {
        let link = self
            .meeting_states_link
            .clone()
            .context("This call has no meeting states")?;
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let body = serde_json::json!({
            "from": from,
            "meetingStates": states,
            "updateMeetingStatesStatus": signaling::trouter_callback(
                &self.callbacks.0,
                &self.callbacks.1,
                "conversation/updateMeetingStatesStatus/",
            ),
            "operationId": uuid::Uuid::new_v4().to_string(),
        });
        tracing::info!(what, "meeting states: publishing");
        cc_post(&self.http, &self.skype_token, &link, &body, what).await?;
        Ok(())
    }

    /// Change the meeting's ad-hoc timer for everyone (Teams'
    /// updateMeetingStates with the three timers' JSON); the change shows
    /// when the update comes back.
    pub async fn publish_timer(&self, adhoc: &super::meeting_timer::Timer) -> Result<()> {
        self.publish_meeting_timers(self.timers.publish(adhoc), adhoc.state())
            .await
    }

    /// Change the meeting's agenda for everyone (an agenda edit).
    pub async fn publish_agenda(&self, agenda: &super::meeting_timer::Timer) -> Result<()> {
        self.publish_meeting_timers(self.timers.publish_agenda(agenda), agenda.state())
            .await
    }

    async fn publish_meeting_timers(&self, states: serde_json::Value, state: &str) -> Result<()> {
        let link = self
            .meeting_states_link
            .clone()
            .context("This meeting has no timer")?;
        let mut from = self.me.0.clone();
        if let Some(o) = from.as_object_mut() {
            o.entry("languageId").or_insert_with(|| "en-us".into());
        }
        let body = serde_json::json!({
            "from": from,
            "meetingStates": states,
            "updateMeetingStatesStatus": signaling::trouter_callback(
                &self.callbacks.0,
                &self.callbacks.1,
                "conversation/updateMeetingStatesStatus/",
            ),
            "operationId": uuid::Uuid::new_v4().to_string(),
        });
        tracing::info!(
            state,
            sequence = self.timers.sequence,
            "meeting timer: publishing"
        );
        cc_post(&self.http, &self.skype_token, &link, &body, "Meeting timer").await?;
        Ok(())
    }

    /// Watching a town hall's stream (no media call).
    pub fn streaming(&self) -> bool {
        self.streaming
    }

    /// The town hall's stream as last offered.
    pub fn stream(&self) -> Option<&super::live_stream::StreamChoice> {
        self.stream.as_ref()
    }

    /// Note a roster update: our place in the stream (its lobby, or
    /// watching) and the stream on offer; true when either changed.
    pub fn apply_stream(&mut self, json: &serde_json::Value) -> bool {
        if !self.streaming {
            return false;
        }
        let me = self.me.0["id"].as_str().unwrap_or_default().to_string();
        let ep = self.me.0["endpointId"]
            .as_str()
            .unwrap_or_default()
            .to_string();
        let mut changed = false;
        if let Some(lobby) = super::live_stream::self_streaming(json, &me, &ep)
            && lobby != self.in_lobby
        {
            tracing::info!(lobby, "town hall stream: our place changed");
            self.in_lobby = lobby;
            changed = true;
        }
        if let Some(all) = super::live_stream::streams(json, &me) {
            // What's on offer, without its addresses' paths or keys.
            let summary: Vec<String> = all
                .iter()
                .map(|s| {
                    let host = s
                        .urls
                        .first()
                        .and_then(|u| url::Url::parse(u).ok())
                        .and_then(|u| u.host_str().map(str::to_string))
                        .unwrap_or_default();
                    format!(
                        "{} primary={} host={} token={}",
                        s.delivery_pipeline_type,
                        s.is_primary,
                        host,
                        !s.key_authorization_token.is_empty()
                    )
                })
                .collect();
            tracing::info!(?summary, "town hall streams");
            let c = super::live_stream::choose_as_teams(&all);
            if self.stream.as_ref() != Some(&c) {
                tracing::info!(player = %c.player_type, has_url = c.url().is_some(), "town hall stream offered");
                self.stream = Some(c);
                changed = true;
            }
        }
        changed
    }

    /// The meeting as a town hall or webinar (its live state, green room,
    /// attendee view), as last reported.
    pub fn event(&self) -> super::live_event::LiveEvent {
        self.event.clone()
    }

    /// Note a conversation update's event facts; true when they changed.
    pub fn apply_event(&mut self, json: &serde_json::Value) -> bool {
        // The production layout comes on its own updates too; an update
        // without it keeps the last one (Teams keeps meetingLayoutDetails).
        let layout = super::live_event::production_layout(json);
        if let Some(l) = &layout {
            let raw = [
                "/body/layoutDetails",
                "/layoutDetails",
                "/body/conversationUpdate/layoutDetails",
            ]
            .iter()
            .find_map(|p| json.pointer(p))
            .map(|v| v.to_string().chars().take(3000).collect::<String>())
            .unwrap_or_default();
            tracing::info!(kind = %l.kind, seq = l.sequence, %raw, sources = ?l.participants.iter().map(|p| format!("{}:{}", p.participant_id, p.modality)).collect::<Vec<_>>(), "event production layout");
            if let Some(n) = json
                .pointer("/body/layoutDetails/sequenceNumber")
                .or_else(|| json.pointer("/layoutDetails/sequenceNumber"))
                .and_then(|v| v.as_u64())
            {
                self.layout_seq = self.layout_seq.max(n);
            }
        }
        let parsed = super::live_event::live_event(json).map(|mut e| {
            if layout.is_none() {
                e.layout = self.event.layout.clone();
            }
            e
        });
        let parsed = parsed.or_else(|| {
            layout.map(|l| super::live_event::LiveEvent {
                layout: l,
                ..self.event.clone()
            })
        });
        match parsed {
            Some(e) if e != self.event => {
                tracing::info!(phase = %e.phase, seq = e.seq, town_hall = e.town_hall, "event live state");
                self.event = e;
                true
            }
            _ => false,
        }
    }

    /// The curtain Teams shows while the event starts (`live`) or ends
    /// for attendees: a user-level "ufd" state; its state id.
    pub async fn publish_curtain(&mut self, live: bool) -> Result<Option<String>> {
        let link = self
            .state_links
            .0
            .clone()
            .context("This meeting can't start for attendees")?;
        self.state_seq += 1;
        let body = serde_json::json!({
            "from": self.me.0,
            "publishedState": super::live_event::curtain_state(live, &self.call_id, self.state_seq),
        });
        let reply = cc_post(&self.http, &self.skype_token, &link, &body, "Stage curtain").await?;
        Ok(reply
            .pointer("/publishStateResponse/stateId")
            .or_else(|| reply.pointer("/publishStateResponse/publishedState/stateId"))
            .or_else(|| reply.pointer("/stateId"))
            .and_then(|v| v.as_str())
            .map(str::to_string))
    }

    /// Remove a state we published (the curtain).
    pub async fn remove_own_state(&mut self, state_id: &str) -> Result<()> {
        let link = self
            .state_links
            .1
            .clone()
            .context("This meeting can't remove states")?;
        self.state_seq += 1;
        let body = serde_json::json!({ "from": self.me.0, "sequenceNumber": self.state_seq, "scope": "specified", "stateIds": [state_id] });
        cc_post(&self.http, &self.skype_token, &link, &body, "Remove state").await?;
        Ok(())
    }

    /// Send live ("On with preview"): put these sources on the live
    /// screen (Teams' setMeetingLayout with the production layout and the
    /// next layout sequence number, as its production studio counts them).
    pub async fn set_meeting_layout(
        &mut self,
        sources: &[super::live_event::LayoutSource],
    ) -> Result<()> {
        let link = self
            .layout_link
            .clone()
            .context("This meeting can't send a layout live")?;
        let status = signaling::trouter_callback(
            &self.callbacks.0,
            &self.callbacks.1,
            "conversation/setMeetingLayoutStatus/",
        );
        let op = uuid::Uuid::new_v4().to_string();
        let from = super::meeting_options::state_from(&self.me.0);
        self.layout_seq = self.layout_seq.max(self.event.layout.sequence);
        let seq = self.layout_seq;
        self.layout_seq += 1;
        // Teams names your own source by this call's endpoint (Ue: the
        // call's participantId and endpointId).
        let me_id = self.me.0["id"]
            .as_str()
            .unwrap_or_default()
            .to_ascii_lowercase();
        let sources: Vec<super::live_event::LayoutSource> = sources
            .iter()
            .cloned()
            .map(|mut s| {
                if s.id.eq_ignore_ascii_case(&me_id) {
                    s.participant_id = self.me.0["participantId"]
                        .as_str()
                        .unwrap_or_default()
                        .to_string();
                    s.endpoint_id = self.me.0["endpointId"]
                        .as_str()
                        .unwrap_or_default()
                        .to_string();
                }
                s
            })
            .collect();
        let body = super::live_event::set_layout_body(
            &from,
            &format!("{}_Preview", self.call_id),
            &sources,
            seq,
            &status,
            &op,
        );
        tracing::info!(seq, sources = sources.len(), body = %body, "send live: setting the meeting layout");
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "Meeting layout",
        )
        .await?;
        Ok(())
    }

    /// Start (`live`) or end the event for attendees: Teams'
    /// updateMeetingLiveState with the live state's sequence number.
    pub async fn update_live_state(&mut self, live: bool) -> Result<()> {
        let link = self
            .live_state_link
            .clone()
            .context("This meeting has no green room")?;
        let status = signaling::trouter_callback(
            &self.callbacks.0,
            &self.callbacks.1,
            "conversation/updateMeetingLiveStateStatus/",
        );
        let op = uuid::Uuid::new_v4().to_string();
        let from = super::meeting_options::state_from(&self.me.0);
        let body = super::live_event::live_state_body(&from, live, self.event.seq, &status, &op);
        tracing::info!(live, seq = self.event.seq, "event live state: updating");
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "Meeting live state",
        )
        .await?;
        Ok(())
    }

    /// A conversation update's Interpreter state; whether it changed.
    pub fn apply_interpretation(&mut self, json: &serde_json::Value) -> bool {
        match super::ai_interpreter::meeting_state(json) {
            Some(s) if s != self.interpretation => {
                self.interpretation = s;
                true
            }
            _ => false,
        }
    }

    pub fn interpretation(&self) -> &super::ai_interpreter::MeetingState {
        &self.interpretation
    }

    pub fn apply_capability(&mut self, json: &serde_json::Value) -> bool {
        match super::meeting_options::meeting_capability(json) {
            Some(c) if c != self.capability => {
                self.capability = c;
                true
            }
            _ => false,
        }
    }

    /// Change meeting settings (Teams' updateMeetingSettings): Lock the
    /// meeting `{"lockMeeting": true}`, attendee restrictions
    /// `{"attendeeRestrictions": bits}`.
    pub async fn update_meeting_settings(&mut self, settings: serde_json::Value) -> Result<()> {
        let link = self
            .settings_link
            .clone()
            .context("This meeting can't change its settings")?;
        self.state_seq += 1;
        let body = super::meeting_options::settings_body(&self.me.0, settings, self.state_seq);
        // Teams' calling stack PUTs this one.
        cc_send(
            &self.http,
            reqwest::Method::PUT,
            &self.skype_token,
            &link,
            &body,
            "Meeting settings",
        )
        .await?;
        Ok(())
    }

    /// Teams' Interpreter: turn it on for the meeting, or off for everyone
    /// (the organizer's Turn off for all).
    pub async fn set_ai_interpretation(&mut self, on: bool) -> Result<()> {
        self.update_meeting_settings(super::ai_interpreter::settings(on))
            .await
    }

    /// Teams' consecutive interpretation: on for everyone in two languages.
    pub async fn set_ai_interpretation_turn_by_turn(
        &mut self,
        first: &str,
        second: &str,
    ) -> Result<()> {
        self.update_meeting_settings(super::ai_interpreter::turn_by_turn_settings(first, second))
            .await
    }

    /// Listen to a language's interpretation: join its meeting group
    /// (Teams' joinMeetingGroup), retrying as Teams does on 404/6011 and
    /// 500/5406 (6 times, 1.5 s apart). Returns the operation id; the
    /// result comes back as a joinMeetingGroupStatus event.
    pub async fn join_meeting_group(&self, label: &str) -> Result<String> {
        let link = self
            .group_links
            .0
            .clone()
            .context("This meeting has no language groups")?;
        let op = uuid::Uuid::new_v4().to_string();
        let status = signaling::trouter_callback(
            &self.callbacks.0,
            &self.callbacks.1,
            "conversation/joinMeetingGroupStatus/",
        );
        let body = super::ai_interpreter::join_group_body(&self.me.0, label, &status, &op);
        let mut tries = 0;
        loop {
            match cc_post(
                &self.http,
                &self.skype_token,
                &link,
                &body,
                "Join meeting group",
            )
            .await
            {
                Ok(_) => break,
                Err(e) => {
                    let t = format!("{e:#}");
                    let again = (t.contains("404") && t.contains("6011"))
                        || (t.contains("500") && t.contains("5406"));
                    if !again || tries >= 6 {
                        return Err(e);
                    }
                    tries += 1;
                    tokio::time::sleep(std::time::Duration::from_millis(1500)).await;
                }
            }
        }
        tracing::info!(label, %op, "joined the meeting group");
        Ok(op)
    }

    /// Stop listening to the interpretation: leave the language group.
    pub async fn leave_meeting_group(&self, group: &str) -> Result<()> {
        let link = self
            .group_links
            .1
            .clone()
            .context("This meeting has no language groups")?;
        let op = uuid::Uuid::new_v4().to_string();
        let status = signaling::trouter_callback(
            &self.callbacks.0,
            &self.callbacks.1,
            "conversation/leaveMeetingGroupStatus/",
        );
        let body = super::ai_interpreter::leave_group_body(&self.me.0, group, &status, &op);
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "Leave meeting group",
        )
        .await?;
        Ok(())
    }

    /// Our AI voice choice for Interpreter (Teams' aiVoiceConsent
    /// participant property, scope self).
    pub async fn set_ai_voice_consent(&mut self, value: &str) -> Result<()> {
        let link = self
            .properties_link
            .clone()
            .context("This meeting can't update participants")?;
        self.state_seq += 1;
        let op = uuid::Uuid::new_v4().to_string();
        let from = serde_json::json!({
            "id": self.me.0["id"],
            "endpointId": self.me.0["endpointId"],
            "participantId": self.me.0["participantId"],
        });
        let body = serde_json::json!({
            "from": from.clone(),
            "to": [{ "id": from["id"], "propertyBag": super::ai_interpreter::voice_consent_property(value, self.state_seq) }],
            "scope": "self",
            "links": { "updateParticipantPropertiesStatus": signaling::trouter_callback(&self.callbacks.0, &self.callbacks.1, "conversation/updateParticipantPropertiesStatus/") },
            "operationId": op,
        });
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "AI voice consent",
        )
        .await?;
        Ok(())
    }

    /// Our MRI and endpoint id (for finding ourselves in the roster).
    pub fn my_endpoint(&self) -> (String, String) {
        (
            self.me.0["id"].as_str().unwrap_or_default().to_string(),
            self.me.0["endpointId"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
        )
    }

    /// Clear a state for everyone (Teams' removeState, scope "all"): Lower
    /// all hands ("raiseHands"), Stop all spotlights ("spotlight").
    pub async fn remove_state_for_everyone(&mut self, state_type: &str) -> Result<()> {
        let link = self
            .state_links
            .1
            .clone()
            .context("This meeting can't clear states")?;
        self.state_seq += 1;
        let body = super::meeting_options::remove_state_for_everyone_body(
            &self.me.0,
            state_type,
            self.state_seq,
        );
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "Remove state for everyone",
        )
        .await?;
        Ok(())
    }

    /// Teams' "Leave on all my devices": remove our other devices from the
    /// call (removeParticipant, scope "all" with this endpoint), then leave.
    pub async fn remove_my_other_devices(&self) -> Result<()> {
        let link = self
            .remove_link
            .clone()
            .context("This call can't remove devices")?;
        let cb = |p: &str| signaling::trouter_callback(&self.callbacks.0, &self.callbacks.1, p);
        let body = serde_json::json!({
            "participants": {
                "from": self.me.0,
                "scope": "all",
                "toEndpoints": [{ "id": self.me.0["id"], "endpointId": self.me.0["endpointId"] }],
            },
            "links": {
                "removeParticipantSuccess": cb("conversation/removeParticipantSuccess/"),
                "removeParticipantFailure": cb("conversation/removeParticipantFailure/"),
            },
        });
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &body,
            "Remove my other devices",
        )
        .await?;
        Ok(())
    }

    /// Admit everyone waiting (Teams' admitAll link).
    pub async fn admit_all(&self) -> Result<()> {
        let link = self
            .admit_links
            .1
            .clone()
            .context("This meeting has no lobby to admit from")?;
        let op = uuid::Uuid::new_v4().to_string();
        let body = serde_json::json!({
            "participants": { "from": self.me.0 },
            "links": { "admitAllStatus": signaling::trouter_callback(&self.callbacks.0, &self.callbacks.1, "conversation/admitAllStatus/") },
            "operationId": op,
            "debugContent": { "causeId": op },
        });
        cc_post(&self.http, &self.skype_token, &link, &body, "Admit all").await?;
        Ok(())
    }

    /// Our raised hand's state id, learned from the roster when the
    /// publish reply didn't carry it.
    /// Record each remote person's merge leg from a roster event, so a
    /// later merge can move them silently ([`roster_legs`]).
    pub fn note_roster_legs(&mut self, json: &str) {
        for (mri, leg) in roster_legs(json) {
            self.remote_legs.insert(mri, leg);
        }
    }

    /// The merge leg last seen for `mri` (an `8:orgid:` MRI).
    pub fn remote_leg(&self, mri: &str) -> Option<serde_json::Value> {
        self.remote_legs.get(&mri.to_ascii_lowercase()).cloned()
    }

    pub fn note_hand(&mut self, id: Option<String>) {
        if self.hand.is_none() {
            self.hand = id;
        }
    }

    /// Transfer the call to `target` (an `8:orgid:` MRI); `replaces`: our
    /// consult call with them (its `links.replace`), for consult then
    /// transfer.
    pub async fn transfer(&self, target: &str, replaces: Option<&str>) -> Result<()> {
        let link = self
            .transfer_link
            .as_deref()
            .context("This call can't be transferred")?;
        let mut details = self.me.0.clone();
        if let Some(o) = details.as_object_mut() {
            o.remove("displayName");
        }
        let (surl, epid) = self.callbacks.clone();
        super::incoming::request_transfer(
            &self.http,
            &self.skype_token,
            link,
            target,
            details,
            |p| signaling::trouter_callback(&surl, &epid, p),
            replaces,
        )
        .await
    }

    /// Park the call (Teams' Park Call); the pickup code comes on
    /// `call/transferCompletion`.
    pub async fn park(&self) -> Result<()> {
        let link = self
            .transfer_link
            .as_deref()
            .context("This call can't be parked")?;
        let mut details = self.me.0.clone();
        if let Some(o) = details.as_object_mut() {
            o.remove("displayName");
        }
        let me = details
            .get("id")
            .and_then(|i| i.as_str())
            .unwrap_or_default()
            .to_string();
        let (surl, epid) = self.callbacks.clone();
        super::incoming::request_park(&self.http, &self.skype_token, link, &me, details, |p| {
            signaling::trouter_callback(&surl, &epid, p)
        })
        .await
    }

    /// Where a transfer that replaces this call points (the callee's
    /// acceptance `links.replace`): what a consult then transfer names.
    pub fn replace_link(&self) -> Option<&str> {
        self.replace_link.as_deref()
    }

    /// Put the call on hold, or resume it (our media only).
    pub fn set_held(&self, held: bool) {
        if let Some(m) = &self.media {
            m.set_held(held);
        }
    }

    /// Whether our media is held (nothing sent or played).
    pub fn is_held(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_held())
    }

    pub fn can_dtmf(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.can_dtmf())
    }

    /// The call is end-to-end encrypted (both sides asked for it).
    pub fn is_e2ee(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_e2ee())
    }

    /// Teams' verification numbers when the call is end-to-end encrypted.
    pub fn e2ee_numbers(&self) -> Vec<String> {
        self.media
            .as_ref()
            .map(|m| m.e2ee_numbers())
            .unwrap_or_default()
    }

    /// The call negotiated video we can send (camera button usable).
    /// In a meeting or group call: show these cameras (roster
    /// `main-video` sourceIds, most wanted first). Returns sourceId ->
    /// frame key for each that has a receive slot.
    pub fn show_videos(&self, sources: &[(i64, u32)]) -> std::collections::HashMap<i64, String> {
        self.media
            .as_ref()
            .map(|m| m.show_videos(sources))
            .unwrap_or_default()
    }

    /// In a meeting or group call: receive this presenter's screen, or stop.
    pub fn show_share(&self, source: Option<i64>) {
        if let Some(m) = &self.media {
            m.show_share(source);
        }
    }

    /// Send what we typed for real-time text since the last; false when
    /// the call has no meeting data channel.
    pub fn send_real_time_text(&self, text: &str) -> bool {
        self.media
            .as_ref()
            .is_some_and(|m| m.send_real_time_text(text))
    }

    /// Sign language mode: whether we are signing; false when the call
    /// has no meeting data channel.
    pub fn send_sign_language(&self, detected: bool, duration_ms: u64) -> bool {
        self.media
            .as_ref()
            .is_some_and(|m| m.send_sign_language(detected, duration_ms))
    }

    /// Our data source id in the meeting (whose real-time text is ours).
    pub fn data_source_id(&self) -> Option<u32> {
        self.media.as_ref().and_then(|m| m.data_source_id())
    }

    /// Give / take control of a shared screen; false when the call has no
    /// meeting data channel.
    pub fn screen_control(&self, c: super::meeting_media::ControlCommand) -> bool {
        self.media.as_ref().is_some_and(|m| m.screen_control(c))
    }

    /// The processor asks for one of our streams (controlVideoStreaming).
    pub fn control_video(&self, source_id: i64, fmt_params: &str) {
        if let Some(m) = &self.media {
            m.control_video(source_id, fmt_params);
        }
    }

    /// Whether this call's camera and screen go on and off by media
    /// descriptions (a meeting's or group call's media processor), not
    /// re-offers.
    pub fn describes_media(&self) -> bool {
        self.media_descriptions.is_some()
    }

    /// In a meeting: tell the conversation what our camera and sharing
    /// lines now do, as Teams posts UpdateMediaDescriptions when they
    /// change (the roster then shows our camera, so others ask for it).
    pub async fn describe_media(&self, camera: bool, sharing: bool) -> Result<()> {
        let Some((link, seq)) = &self.media_descriptions else {
            return Ok(());
        };
        let request_id = seq.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        let tag = self.tags.tag(&self.call_id, camera, sharing);
        // The processor's mids for our lines (its own after it moved the
        // call to itself).
        use super::meeting_media::{CAMERA_MID, SHARE_MID};
        let mids = match &self.media {
            Some(m) => (m.wire_mid(CAMERA_MID), m.wire_mid(SHARE_MID)),
            None => (CAMERA_MID.to_string(), SHARE_MID.to_string()),
        };
        let body = media_descriptions_body(
            camera,
            sharing,
            tag.as_deref(),
            request_id,
            (&mids.0, &mids.1),
        );
        cc_post(
            &self.http,
            &self.skype_token,
            link,
            &body,
            "Media descriptions",
        )
        .await?;
        Ok(())
    }

    pub fn can_send_video(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.can_send_video())
    }

    /// We can share our screen in this call (Share usable).
    pub fn can_share(&self) -> bool {
        self.renegotiation_link.is_some() && self.media.as_ref().is_some_and(|m| m.can_share())
    }

    /// Whether we can change our media with re-offers (camera, screen).
    pub fn can_reoffer(&self) -> bool {
        self.renegotiation_link.is_some() && self.media.is_some()
    }

    /// Offer a change to what we send (camera or screen on or off); the
    /// answer comes back as a `call/mediaAnswer/` event for
    /// [`Self::take_reoffer_answer`].
    pub async fn offer_media(&mut self, change: super::webrtc_audio::Reoffer) -> Result<()> {
        let link = self
            .renegotiation_link
            .clone()
            .context("This call can't renegotiate media")?;
        let m = self.media.as_ref().context("No media to change")?;
        let sdp = m.reoffer(change)?;
        let (camera, share) = m.negotiated_after(change);
        super::incoming::debug_dump("sdp-reoffer-ours", &sdp);
        let (surl, epid) = self.callbacks.clone();
        let sent = super::incoming::request_reoffer(
            &self.http,
            &self.skype_token,
            &link,
            self.me.0.clone(),
            |p| signaling::trouter_callback(&surl, &epid, p),
            &sdp,
            super::incoming::share_modalities(share, camera),
        )
        .await;
        if sent.is_err() {
            m.cancel_reoffer();
        }
        sent
    }

    /// Whether a re-offer of ours is waiting for its answer.
    pub fn reoffer_pending(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.reoffer_pending())
    }

    /// Whether the meeting sends each speaker's own audio (x-much2).
    pub fn unmixed(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.unmixed())
    }

    /// Whether spatial audio wants the other way than what's negotiated
    /// (Teams renegotiates its audio codec when spatial audio is turned on
    /// or off mid-meeting): the change to re-offer, if any.
    pub fn unmixed_change(&self) -> Option<super::webrtc_audio::Reoffer> {
        let m = self.media.as_ref()?;
        if !m.is_meeting() || self.renegotiation_link.is_none() {
            return None;
        }
        let want = super::spatial::wants_unmixed();
        (want != m.unmixed()).then_some(super::webrtc_audio::Reoffer::Unmixed(want))
    }

    /// The answer to our re-offer: what it was for, and whether it was
    /// taken.
    pub fn take_reoffer_answer(
        &mut self,
        answer: &str,
    ) -> Result<(super::webrtc_audio::Reoffer, bool)> {
        super::incoming::debug_dump("sdp-reanswer-theirs", answer);
        self.media
            .as_ref()
            .context("No media to change")?
            .take_reoffer_answer(answer)
    }

    /// Acknowledge the answer to our re-offer, as Teams does.
    pub async fn acknowledge_answer(&self, link: &str) -> Result<()> {
        cc_post(
            &self.http,
            &self.skype_token,
            link,
            &serde_json::Value::Null,
            "Media acknowledgement",
        )
        .await?;
        Ok(())
    }

    /// The other side refused our re-offer.
    pub fn cancel_reoffer(&self) {
        if let Some(m) = self.media.as_ref() {
            m.cancel_reoffer();
        }
    }

    /// Start sending a screen capture.
    #[cfg(feature = "screencast")]
    pub fn start_share(
        &mut self,
        capture: super::screencast::ScreenCapture,
        frames: std::sync::mpsc::Receiver<super::camera::YuvFrame>,
    ) -> Result<()> {
        self.media
            .as_mut()
            .context("No media to share on")?
            .start_share(capture, frames)
    }

    /// Stop sending our screen.
    pub fn stop_share(&mut self) {
        if let Some(m) = self.media.as_mut() {
            m.stop_share();
        }
    }

    /// Whether we're sending our screen.
    /// Our camera is sending.
    pub fn camera_on(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.camera_on())
    }

    pub fn is_sharing(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_sharing())
    }

    /// Whether our shared screen went away by itself.
    pub fn share_ended(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.share_ended())
    }

    /// Teams' network strength for this call (Good while there's no media).
    pub fn network_strength(&self) -> super::network_quality::Strength {
        self.media
            .as_ref()
            .map_or(super::network_quality::Strength::Good, |m| {
                m.network_strength()
            })
    }

    /// Turn the camera on or off.
    pub fn set_camera(&mut self, on: bool, device: Option<String>) -> Result<()> {
        self.media
            .as_mut()
            .context("No video in this call")?
            .set_camera(on, device)
    }

    /// Send a dial-pad key as a tone.
    pub fn send_dtmf(&self, key: char) -> Result<()> {
        self.media
            .as_ref()
            .context("No audio in this call")?
            .send_dtmf(key)
    }

    /// Answer the other side's re-offer (hold, resume, camera); returns
    /// whether it now has us on hold.
    pub async fn answer_renegotiation(&mut self, event: &serde_json::Value) -> Result<bool> {
        let cb = |p: &str| signaling::trouter_callback(&self.callbacks.0, &self.callbacks.1, p);
        let controller = serde_json::json!({
            "controlVideoStreaming": cb("call/controlVideoStreaming/"),
            "csrcInfo": cb("call/csrcInfo/"),
        });
        super::incoming::answer_renegotiation(
            &self.http,
            &self.skype_token,
            &mut self.media,
            Some(self.me.clone()),
            Some(controller),
            event,
        )
        .await
    }

    pub fn is_held_by_peer(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_held_by_peer())
    }

    pub async fn stats(&self) -> Option<WebRtcStats> {
        match &self.media {
            Some(m) => Some(m.stats().await),
            None => None,
        }
    }

    /// Send a meeting reaction ("like", "heart", "applause", "laugh",
    /// "surprised"): Teams' proxied Reaction message to everyone.
    pub async fn send_reaction(&self, name: &str) -> Result<()> {
        let link = self
            .message_link
            .clone()
            .context("This meeting doesn't take reactions")?;
        let body = reaction_body(
            &self.me.0,
            name,
            &uuid::Uuid::new_v4().to_string(),
            &uuid::Uuid::new_v4().to_string(),
        );
        cc_post(&self.http, &self.skype_token, &link, &body, "Reaction").await?;
        Ok(())
    }

    /// Mute everyone else (Teams' Mute all: MuteAllSync on the
    /// conversation's mute link, scope "all" and no one named). Returns who
    /// the reply says the meeting muted.
    pub async fn mute_all(&self) -> Result<Vec<String>> {
        self.mute(&[], "Mute all").await
    }

    /// The meeting's link to share (Teams' Share invite).
    pub fn invite_url(&self) -> Option<&str> {
        self.invite_url.as_deref()
    }

    /// End the meeting for everyone (Teams' End meeting: a DELETE of the
    /// conversation controller saying ConversationEndForAllInitiated), then
    /// stop our media.
    pub async fn end_for_everyone(mut self) -> Result<()> {
        let url = self
            .controller
            .clone()
            .context("This call can't be ended for everyone")?;
        if !super::incoming::is_service_link(&url) {
            bail!("End meeting: not a Teams service link");
        }
        let resp = self
            .http
            .delete(&url)
            .header("X-Skypetoken", &self.skype_token)
            .json(&end_for_all_body(&self.me.0))
            .send()
            .await
            .context("End meeting failed to send")?;
        let status = resp.status();
        self.media = None;
        if !status.is_success() {
            bail!("End meeting failed: HTTP {status}");
        }
        tracing::info!("End meeting: HTTP {status}");
        Ok(())
    }

    /// Stop our media (nothing sent or played) and keep the leg: moving to
    /// another meeting, Teams leaves this one only once the next connects.
    pub fn stop_media(&mut self) {
        self.media = None;
    }

    /// Stop media and end the call for both sides.
    pub async fn hang_up(mut self) -> Result<()> {
        self.media = None;
        // A stream's watcher has no call leg: Teams leaves the conversation.
        if self.streaming && self.leave_link.is_some() {
            return self.leave().await;
        }
        if let Some(leg) = &self.call_leg {
            let body = serde_json::json!({
                "callEnd": { "code": 0, "subCode": 0, "phrase": "CallEndReasonLocalUserInitiated" }
            });
            let resp = self
                .http
                .delete(leg)
                .header("X-Skypetoken", &self.skype_token)
                .json(&body)
                .send()
                .await
                .context("Call end failed to send")?;
            if resp.status().is_success() {
                tracing::info!(tag = %self.call_tag, status = %resp.status(), "hung up the call leg");
                return Ok(());
            }
            tracing::info!("callLeg end returned {}, trying end link", resp.status());
        }
        let url = self.end_url.clone().context("No way to end this call")?;
        let resp = self
            .http
            .post(&url)
            .header("X-Skypetoken", &self.skype_token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .context("Call end failed to send")?;
        if !resp.status().is_success() {
            bail!("Call end failed: HTTP {}", resp.status());
        }
        Ok(())
    }
}

/// The 1:1 chat id's other member as an MRI: `19:<a>_<b>@unq.gbl.spaces`
/// with `me` = one of the two object ids.
pub fn callee_mri_for_chat(chat_id: &str, my_oid: &str) -> Option<String> {
    let inner = chat_id
        .strip_prefix("19:")?
        .strip_suffix("@unq.gbl.spaces")?;
    let (a, b) = inner.split_once('_')?;
    let other = if a.eq_ignore_ascii_case(my_oid) {
        b
    } else if b.eq_ignore_ascii_case(my_oid) {
        a
    } else {
        return None;
    };
    Some(crate::identity::user_mri(other))
}

/// The 1:1 chat two people share (Teams' `19:<oid>_<oid>@unq.gbl.spaces`,
/// the two object ids in sorted order): where a call to someone is placed.
pub fn one_to_one_chat_id(my_oid: &str, other_oid: &str) -> Option<String> {
    let (a, b) = (my_oid.to_ascii_lowercase(), other_oid.to_ascii_lowercase());
    if uuid::Uuid::parse_str(&a).is_err() || uuid::Uuid::parse_str(&b).is_err() || a == b {
        return None;
    }
    let (x, y) = if a <= b { (a, b) } else { (b, a) };
    Some(format!("19:{x}_{y}@unq.gbl.spaces"))
}

/// Someone a merge moves into the call: their MRI, the participant id
/// their new leg gets, and (Teams' `replacementDetails`) the leg of theirs
/// it replaces in the other call when the roster gave its call links:
/// `{replaces: <endpoint callLinks.replacement>, replacementTargetParticipantId}`.
#[derive(Debug, Clone, PartialEq)]
pub struct MergePerson {
    pub id: String,
    pub participant_id: String,
    pub display_name: Option<String>,
    pub replacement: Option<serde_json::Value>,
}

/// Teams' merge request (its `addParticipantsAsync` with ReplaceParticipant
/// for a P2P-into-P2P merge): `{participants: {from, to: [{id,
/// displayName, participantId, replacementDetails}]}, groupContext: null,
/// groupChat: {threadId, messageId: null}, links: {addParticipantSuccess,
/// addParticipantFailure}}`.
pub fn merge_body(
    from: &serde_json::Value,
    thread_id: &str,
    people: &[MergePerson],
    cb: impl Fn(&str) -> String,
) -> serde_json::Value {
    let to: Vec<serde_json::Value> = people
        .iter()
        .map(|p| {
            let mut t = serde_json::json!({ "id": p.id, "participantId": p.participant_id });
            if let Some(n) = &p.display_name {
                t["displayName"] = n.clone().into();
            }
            if let Some(r) = &p.replacement {
                t["replacementDetails"] = r.clone();
            }
            t
        })
        .collect();
    serde_json::json!({
        "participants": { "from": from, "to": to },
        "participantInvitationData": {},
        "groupContext": null,
        "groupChat": { "threadId": thread_id, "messageId": null },
        "links": {
            "addParticipantSuccess": cb("conversation/addParticipantSuccess/"),
            "addParticipantFailure": cb("conversation/addParticipantFailure/"),
        },
    })
}

/// Teams' roster invitation (its `addParticipantsAsync` from the people
/// picker, captured from Teams on the web 2026-11-26): `{disableUnmute:
/// false, participants: {from, to: [{id, participantId}]},
/// participantInvitationData: {}, replacementDetails: null, groupContext:
/// null, groupChat: {threadId, messageId: null}, links:
/// {addParticipantSuccess, addParticipantFailure}}`. `to` pairs each MRI
/// with a fresh participant id.
pub fn invite_body(
    from: &serde_json::Value,
    thread_id: &str,
    to: &[(String, String)],
    cb: impl Fn(&str) -> String,
) -> serde_json::Value {
    let to: Vec<serde_json::Value> = to
        .iter()
        .map(|(id, pid)| serde_json::json!({ "id": id, "participantId": pid }))
        .collect();
    serde_json::json!({
        "disableUnmute": false,
        "participants": { "from": from, "to": to },
        "participantInvitationData": {},
        "replacementDetails": null,
        "groupContext": null,
        "groupChat": { "threadId": thread_id, "messageId": null },
        "links": {
            "addParticipantSuccess": cb("conversation/addParticipantSuccess/"),
            "addParticipantFailure": cb("conversation/addParticipantFailure/"),
        },
    })
}

/// Each remote participant's merge leg from a roster event (their
/// `endpointDetails[].callLinks.replacement`), keyed by lowercase MRI:
/// what a silent merge names so the service moves them instead of ringing.
pub fn roster_legs(json: &str) -> Vec<(String, serde_json::Value)> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    if !v
        .get("callAgentPath")
        .and_then(|p| p.as_str())
        .is_some_and(|p| p.starts_with("conversation/rosterUpdate"))
    {
        return Vec::new();
    }
    let Some(parts) = v.pointer("/body/participants").and_then(|p| p.as_object()) else {
        return Vec::new();
    };
    parts
        .iter()
        .filter_map(|(mri, p)| {
            // A roster event keys endpoints by id (the parsed form uses
            // `endpointDetails`); each has a participantId and callLinks.
            let ep = p
                .get("endpoints")?
                .as_object()?
                .values()
                .find(|e| e.pointer("/callLinks/replacement").is_some())?;
            let replaces = ep.pointer("/callLinks/replacement")?.as_str()?;
            let leg = ep.get("participantId")?.as_str()?;
            Some((
                mri.to_ascii_lowercase(),
                serde_json::json!({ "replaces": replaces, "replacementTargetParticipantId": leg }),
            ))
        })
        .collect()
}

/// The leg a person has in a call, from a roster participant's
/// `endpointDetails[].callLinks.replacement` (Teams'
/// `setParticipantCallLinks`): what a merge names in `replacementDetails`.
pub fn leg_replacement(participant: &serde_json::Value) -> Option<serde_json::Value> {
    participant
        .get("endpointDetails")?
        .as_array()?
        .iter()
        .find_map(|e| {
            let replaces = e.pointer("/callLinks/replacement")?.as_str()?;
            let leg = e.get("participantId")?.as_str()?;
            Some(serde_json::json!({ "replaces": replaces, "replacementTargetParticipantId": leg }))
        })
}

/// POST JSON to a Teams service link; the JSON reply (Null when empty).
async fn cc_post(
    http: &reqwest::Client,
    skype_token: &str,
    url: &str,
    body: &serde_json::Value,
    what: &str,
) -> Result<serde_json::Value> {
    cc_send(http, reqwest::Method::POST, skype_token, url, body, what).await
}

/// The user's IC3 token for a conversation request. Teams' calling stack
/// signs its conversation requests with it (Skype token migration:
/// `Authorization: Bearer <token>` and `X-MS-Migration: True`; ECS
/// skypeTokenMigrationServiceInfo has Slimcore on CAE tokens for
/// ic3CaeResource https://ic3.teams.office.com), not the Skype token. The
/// call then acts for the user elsewhere: a Meet now's notes link is
/// committed to the collab service on their behalf, which a Skype-token
/// request fails (updateMeetingStates 500, subCode 6176, CollabCommitError
/// CrossTenantRequest; TASK-0212).
async fn cc_bearer() -> Option<String> {
    let mut config = Config::load().ok()?;
    if config.get_ic3_token().is_none_or(|t| t.is_expired()) {
        crate::auth::oauth::refresh().await.ok()?;
        config = Config::load().ok()?;
    }
    config
        .get_ic3_token()
        .filter(|t| !t.is_expired())
        .map(|t| t.token)
}

/// A conversation request with the given method (Teams PUTs some, such as
/// updateMeetingSettings).
async fn cc_send(
    http: &reqwest::Client,
    method: reqwest::Method,
    skype_token: &str,
    url: &str,
    body: &serde_json::Value,
    what: &str,
) -> Result<serde_json::Value> {
    cc_send_in_call(http, method, skype_token, url, body, what, None).await
}

/// A conversation request; with the call's chain id it carries the headers
/// Teams' calling stack puts on each request of the call (its chain and
/// message ids, client, partition, region and ring, as on the join).
async fn cc_send_in_call(
    http: &reqwest::Client,
    method: reqwest::Method,
    skype_token: &str,
    url: &str,
    body: &serde_json::Value,
    what: &str,
    chain_id: Option<&str>,
) -> Result<serde_json::Value> {
    if !super::incoming::is_service_link(url) {
        bail!("{what}: not a Teams service link");
    }
    let message_id = uuid::Uuid::new_v4().to_string();
    let send = |bearer: Option<String>| {
        let mut req = http.request(method.clone(), url).json(body);
        if let Some(chain) = chain_id {
            req = req
                .header("x-microsoft-skype-chain-id", chain)
                .header("x-microsoft-skype-message-id", &message_id)
                .header("x-microsoft-skype-client", signaling::SKYPE_CLIENT_HEADER)
                .header("Referer", "https://teams.microsoft.com/")
                .header("ms-teams-partition", signaling::TEAMS_PARTITION)
                .header("ms-teams-region", signaling::TEAMS_REGION)
                .header("ms-teams-ring", signaling::TEAMS_RING);
        }
        match bearer {
            Some(t) => req.bearer_auth(t).header("X-MS-Migration", "True"),
            None => req.header("X-Skypetoken", skype_token),
        }
        .send()
    };
    let bearer = cc_bearer().await;
    let signed = bearer.is_some();
    let mut resp = send(bearer)
        .await
        .with_context(|| format!("{what} failed to send"))?;
    // A conversation that doesn't take the user's token yet (Teams asks
    // the service's WWW-Authenticate for the token types it takes): the
    // Skype token.
    if signed && resp.status() == reqwest::StatusCode::UNAUTHORIZED {
        tracing::info!("{what}: the call refused the IC3 token, sending the Skype token");
        resp = send(None)
            .await
            .with_context(|| format!("{what} failed to send"))?;
    }
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        tracing::info!(
            "{what}: HTTP {status}: {}",
            text.chars().take(1500).collect::<String>()
        );
        bail!("{what} failed: HTTP {status}");
    }
    tracing::info!("{what}: HTTP {status}");
    Ok(serde_json::from_str(&text).unwrap_or(serde_json::Value::Null))
}

/// The people in a getAllParticipants reply: an array of {id, displayName,
/// participantScreening} or a map of roster entries keyed by MRI.
fn lobby_people(reply: &serde_json::Value) -> Vec<LobbyPerson> {
    let list = reply
        .pointer("/response/participants")
        .or_else(|| reply.get("participants"))
        .cloned()
        .unwrap_or_default();
    let person = |id: &str, p: &serde_json::Value| {
        let name = p
            .get("displayName")
            .or_else(|| p.pointer("/details/displayName"))
            .and_then(|n| n.as_str())
            .unwrap_or_default()
            .to_string();
        let flagged = p
            .pointer("/participantScreening/isBot")
            .or_else(|| p.pointer("/details/propertyBag/participantScreening/value/isBot"))
            .and_then(|b| b.as_bool())
            .unwrap_or(false);
        // Teams: only anonymous guests are screened (JOIN_SHIELD).
        LobbyPerson {
            id: id.to_string(),
            name,
            suspected: flagged && id.starts_with("8:teamsvisitor:"),
        }
    };
    match list {
        serde_json::Value::Array(a) => a
            .iter()
            .filter_map(|p| Some(person(p.get("id")?.as_str()?, p)))
            .collect(),
        serde_json::Value::Object(m) => m.iter().map(|(id, p)| person(id, p)).collect(),
        _ => Vec::new(),
    }
}

/// Teams' SendProxiedMessage body for a reaction (scope "all").
/// Sends PowerPoint Live's pointer as LiveInking messages
/// ([`OutgoingCall::live_inking_sender`]).
#[derive(Clone)]
pub struct LiveInkingSender {
    http: reqwest::Client,
    token: String,
    link: String,
    me: serde_json::Value,
}

impl LiveInkingSender {
    pub async fn send(&self, event_data: &str) -> Result<()> {
        let body = super::content_sharing::live_inking_body(
            &self.me,
            event_data,
            &uuid::Uuid::new_v4().to_string(),
        );
        cc_post(&self.http, &self.token, &self.link, &body, "LiveInking")
            .await
            .map(|_| ())
    }
}

fn reaction_body(
    me: &serde_json::Value,
    name: &str,
    operation: &str,
    id: &str,
) -> serde_json::Value {
    serde_json::json!({
        "from": {
            "displayName": me["displayName"],
            "endpointId": me["endpointId"],
            "id": me["id"],
            "languageId": me.get("languageId").cloned().unwrap_or(serde_json::json!("")),
            "participantId": me["participantId"],
        },
        "messageContent": [{
            "operationId": operation,
            "payload": { "values": [{ "id": id, "name": name, "count": 1, "attributes": {} }] },
            "scope": "all",
            "to": [],
            "type": "Reaction",
        }],
    })
}

/// Teams' joinPreheatedCall endpoint state: `preheatProperties` 0 (and
/// `state.isMuted` when joining muted).
fn preheat_join_body(from: &serde_json::Value, muted: bool, seq: u64) -> serde_json::Value {
    let mut state = serde_json::json!({
        "endpointStateSequenceNumber": seq,
        "endpointProperties": { "preheatProperties": 0 },
    });
    if muted {
        state["state"] = serde_json::json!({ "isMuted": true });
    }
    serde_json::json!({ "from": from, "endpointState": state })
}

/// Teams' leave body (the pre-join's Cancel, and leaving a meeting).
fn leave_body(from: &serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "participants": { "from": from },
        "conversationTransactionEnd": { "reason": "noError", "code": 0, "phrase": "ConversationEndNoModalityConnected" },
        "callTransactionEnd": { "code": 0, "subCode": 0, "phrase": "CallEndReasonLocalUserInitiated", "resultCategories": ["Success"] },
    })
}

/// Teams' updateEndpointState body: who we are, and whether we're muted.
fn endpoint_state_body(from: &serde_json::Value, muted: bool, seq: u64) -> serde_json::Value {
    serde_json::json!({
        "from": from,
        "endpointState": {
            "state": { "isMuted": muted },
            "endpointStateSequenceNumber": seq,
        },
    })
}

/// The negotiation tags Teams puts on UpdateMediaDescriptions: a share
/// is "<callId>;ss_<n>" and the camera, each time it goes on,
/// "<callId>;v_<n>" (the roster then carries the tag as the stream's
/// `metadata.negotiationTag`, as it does for Teams' own camera). A
/// description that changes nothing keeps the ongoing share's tag, else
/// the camera's.
#[derive(Default)]
pub(crate) struct MediaTags {
    described_sharing: std::sync::atomic::AtomicBool,
    described_camera: std::sync::atomic::AtomicBool,
    shares: std::sync::atomic::AtomicU64,
    cameras: std::sync::atomic::AtomicU64,
}

impl MediaTags {
    /// The tag for a description saying `camera` and `sharing`.
    pub(crate) fn tag(&self, call_id: &str, camera: bool, sharing: bool) -> Option<String> {
        use std::sync::atomic::Ordering::Relaxed;
        let share_started = !self.described_sharing.swap(sharing, Relaxed) && sharing;
        let camera_started = !self.described_camera.swap(camera, Relaxed) && camera;
        if share_started {
            self.shares.fetch_add(1, Relaxed);
        }
        if camera_started {
            self.cameras.fetch_add(1, Relaxed);
        }
        let share = || format!("{call_id};ss_{}", self.shares.load(Relaxed));
        let video = || format!("{call_id};v_{}", self.cameras.load(Relaxed));
        if share_started {
            Some(share())
        } else if camera_started {
            Some(video())
        } else if sharing {
            Some(share())
        } else if camera {
            Some(video())
        } else {
            None
        }
    }
}

/// Teams' UpdateMediaDescriptions: what our camera and sharing lines do
/// (both are sendrecv in our offer; a line described sending must be, else
/// 1047 "Invalid MediaDescriptions"). Off, a line is "recvonly"; a shared
/// screen is "sendonly". `tag`: the description's negotiation tag
/// ([`MediaTags`]). `mids`: the camera's and sharing line's.
pub(crate) fn media_descriptions_body(
    camera: bool,
    sharing: bool,
    tag: Option<&str>,
    request_id: u64,
    (camera_mid, share_mid): (&str, &str),
) -> serde_json::Value {
    let camera = if camera {
        serde_json::json!({"mid": camera_mid, "direction": "sendrecv", "label": "main-video"})
    } else {
        serde_json::json!({"mid": camera_mid, "direction": "recvonly"})
    };
    let share = if sharing {
        serde_json::json!({"mid": share_mid, "direction": "sendonly", "label": "applicationsharing-video"})
    } else {
        serde_json::json!({"mid": share_mid, "direction": "recvonly"})
    };
    let mut descriptions =
        serde_json::json!({"descriptions": [camera, share], "requestId": request_id});
    if let Some(tag) = tag {
        descriptions["negotiationTag"] = tag.into();
    }
    serde_json::json!({"UpdateMediaDescriptions": {"mediaDescriptions": descriptions}})
}

/// Teams' body for muting others (calling-pluginless IV, as Teams sent it
/// in a meeting, 2026-11-25): who we are, the scope ("specified" for
/// MuteSpecifiedSync; "all" for MuteAllSync, which names no one and mutes
/// everyone but you), the people as `{id}` objects, audio only, and the
/// callback and operation id the result comes back with.
fn mute_body(
    me: &serde_json::Value,
    scope: &str,
    ids: &[&str],
    callback: &str,
    operation: &str,
) -> serde_json::Value {
    let people: Vec<serde_json::Value> = ids
        .iter()
        .map(|id| serde_json::json!({ "id": id }))
        .collect();
    serde_json::json!({
        "from": super::meeting_options::state_from(me),
        "scope": scope,
        "muteParticipants": people,
        "mediaTypes": ["audio"],
        "links": { "clientCallback": callback },
        "operationId": operation,
    })
}

/// Teams' muteUnmuteAsync callback for one operation: the operation id is
/// the callback's own segment (`…/callAgent/<endpoint>/<operation>/
/// conversation/muteUnmuteAsync/`).
fn mute_callback(surl: &str, endpoint_id: &str, operation: &str) -> String {
    format!("{surl}callAgent/{endpoint_id}/{operation}/conversation/muteUnmuteAsync/")
}

/// Who a mute result says the meeting muted, from the event pushed to the
/// muteUnmuteAsync callback (`{muteUnmuteResponseAsync, operationId}`);
/// None for any other event.
pub fn muted_by_async_result(json: &str) -> Option<Vec<String>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    if !v
        .get("callAgentPath")?
        .as_str()?
        .starts_with("conversation/muteUnmuteAsync")
    {
        return None;
    }
    Some(muted_by_reply(v.get("body")?))
}

/// Who a mute reply says the meeting muted. Its `muteUnmuteResponse` (the
/// callback's `muteUnmuteResponseAsync`) maps each MRI to their endpoints'
/// results (`{participantId, reason, serverMuteVersion}`); Teams marks an
/// endpoint's audio server-muted for each `reason` "success" at once,
/// before the roster says so (calling-pluginless
/// handleParticipantsMutedUpdated). The lowercased MRIs of everyone all of
/// whose listed endpoints succeeded.
fn muted_by_reply(reply: &serde_json::Value) -> Vec<String> {
    reply
        .get("muteUnmuteResponse")
        .or_else(|| reply.get("muteUnmuteResponseAsync"))
        .and_then(|m| m.as_object())
        .into_iter()
        .flatten()
        .filter(|(_, endpoints)| {
            endpoints.as_array().is_some_and(|e| {
                !e.is_empty()
                    && e.iter()
                        .all(|x| x.get("reason").and_then(|r| r.as_str()) == Some("success"))
            })
        })
        .map(|(mri, _)| mri.to_ascii_lowercase())
        .collect()
}

/// Teams' body for deleting the conversation controller (End meeting).
fn end_for_all_body(me: &serde_json::Value) -> serde_json::Value {
    let reason = serde_json::json!({
        "code": 0,
        "subCode": 0,
        "phrase": "ConversationEndForAllInitiated",
        "resultCategories": ["Success"],
    });
    serde_json::json!({
        "participants": { "from": me },
        "conversationTransactionEnd": { "reason": "noError", "code": 0, "phrase": "ConversationEndForAllInitiated" },
        "callTransactionEnd": reason,
    })
}

/// The meeting's link to share from the create response's meetingDetails:
/// the short one (teams.microsoft.com/meet/…) when there is one, as Teams
/// shares it, else the join URL.
fn invite_url(create_response: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(create_response).ok()?;
    let details = v
        .pointer("/meetingDetails")
        .or_else(|| v.pointer("/conversationResponse/meetingDetails"))?;
    if let Some(o) = details.as_object() {
        tracing::debug!(keys = ?o.keys().collect::<Vec<_>>(), capability = %o.get("meetingCapability").map(|c| c.to_string()).unwrap_or_default(), "meetingDetails");
    }
    ["shortJoinUrl", "joinUrl"]
        .iter()
        .filter_map(|k| details.get(*k).and_then(|u| u.as_str()))
        .find(|u| u.starts_with("https://teams.microsoft.com/"))
        .map(str::to_string)
}

/// The conversation controller URL from the create response.
fn controller_link(create_response: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(create_response).ok()?;
    v.pointer("/conversationController")
        .or_else(|| v.pointer("/conversationResponse/conversationController"))
        .and_then(|u| u.as_str())
        .filter(|u| super::incoming::is_service_link(u))
        .map(str::to_string)
}

/// Teams' updateParticipantsProperties body for our own screen sharer
/// attributes (scope "self").
/// (Teams sends `source` 1 for a screen, 2 for a window, and the screen's
/// logical width, work-area height and full height.)
fn screen_sharer_body(
    from: serde_json::Value,
    source: u8,
    size: Option<(u32, u32, u32)>,
    seq: u64,
    op: &str,
    status_link: &str,
) -> serde_json::Value {
    let size = size.map(|(w, h, full)| serde_json::json!({ "width": w, "height": h, "offset": 0, "fullHeight": full }));
    serde_json::json!({
        "from": from.clone(),
        "to": [{
            "id": from["id"],
            "propertyBag": {
                "screenSharerAttributes": {
                    "value": { "source": source, "annotationWindowSize": size },
                    "sequenceNumber": seq,
                },
            },
        }],
        "scope": "self",
        "links": { "updateParticipantPropertiesStatus": status_link },
        "operationId": op,
    })
}

/// Teams' updateParticipantsProperties body clearing a guest's screening.
fn not_bot_body(
    from: serde_json::Value,
    id: &str,
    op: &str,
    now: &str,
    status_link: &str,
) -> serde_json::Value {
    serde_json::json!({
        "from": from,
        "to": [{
            "id": id,
            "propertyBag": {
                "participantScreening": {
                    "value": { "isBot": false, "source": "JoinShield", "detectedAt": now, "markedBy": "admitter" },
                    "sequenceNumber": 1,
                },
            },
        }],
        "links": { "updateParticipantPropertiesStatus": status_link },
        "operationId": op,
    })
}

/// A conversation link (`leave`, `publishState`, `removeState`…) from the
/// create response.
fn conversation_link(create_response: &str, name: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(create_response).ok()?;
    v.pointer(&format!("/links/{name}"))
        .or_else(|| v.pointer(&format!("/conversationResponse/links/{name}")))
        .and_then(|u| u.as_str())
        .filter(|u| super::incoming::is_service_link(u))
        .map(str::to_string)
}

/// A field of the conversation's group chat (`activeModalities.groupChat`):
/// threadId, messageId, lobbyThreadId…
fn group_chat_field(create_response: &str, name: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(create_response).ok()?;
    ["", "/conversationResponse"]
        .iter()
        .find_map(|p| v.pointer(&format!("{p}/activeModalities/groupChat/{name}")))
        .and_then(|t| t.as_str())
        .filter(|t| !t.is_empty())
        .map(str::to_string)
}

/// The conversation's `leave` link from the create response.
fn leave_link(create_response: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(create_response).ok()?;
    v.pointer("/links/leave")
        .or_else(|| v.pointer("/conversationResponse/links/leave"))
        .and_then(|u| u.as_str())
        .map(str::to_string)
}

/// How long an early (provisional) media answer waits for the callee's
/// acceptance before it is taken as the answer.
const EARLY_ANSWER_GRACE: std::time::Duration = std::time::Duration::from_secs(20);

/// What the callee's answer told us.
#[derive(Default)]
struct Acceptance {
    /// No answer comes: the roster put us in the meeting's stream (a town
    /// hall's attendee, live_stream.rs), in its lobby (`in_lobby`) before
    /// the event starts.
    streaming: bool,
    /// The roster that put us in the stream (its streams).
    stream_roster: Option<serde_json::Value>,
    sdp: String,
    acknowledgement: Option<String>,
    call_leg: Option<String>,
    hold: Option<String>,
    transfer: Option<String>,
    /// What a transfer replacing this call names (`links.replace`).
    replace: Option<String>,
    /// `acceptedBy.displayName`.
    answered_by: Option<String>,
    /// An early `mediaAnswer` (the callee's media before it accepted):
    /// Teams treats it as provisional and takes the call's links (callLeg,
    /// replacement…) from the `callAcceptance` that follows.
    provisional: bool,
    /// Where our re-offers go (screen sharing).
    renegotiation: Option<String>,
    end: Option<String>,
    /// Where a meeting is told what our lines do (Teams' camera and screen
    /// changes go there).
    media_descriptions: Option<String>,
    /// A meeting holding us in its lobby: the media processor accepts the
    /// call with no call modalities (Teams then shows "Someone will let you
    /// in shortly"); admitting us brings the call modality.
    in_lobby: bool,
}

/// Read a callee answer, a rejection, or a call end from a call event.
fn read_answer(json: &str) -> Option<std::result::Result<Acceptance, String>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let body = v.get("body").unwrap_or(&v);
    if super::incoming::is_call_end_event(json) {
        // callEnd {code, phrase} on call/end, or the same fields at the top
        // level on conversation/conversationEnd.
        let end = body.get("callEnd").unwrap_or(body);
        let code = end.get("code").and_then(|c| c.as_u64()).unwrap_or_default();
        let phrase = end
            .get("phrase")
            .and_then(|c| c.as_str())
            .unwrap_or("call ended");
        return Some(Err(format!("{phrase} ({code})")));
    }
    if let Some(r) = body.get("sessionRejection") {
        return Some(Err(format!("Call declined ({})", r)));
    }
    let blob = [
        "/callAcceptance/mediaContent/blob",
        "/mediaAnswer/mediaContent/blob",
        "/mediaContent/blob",
    ]
    .iter()
    .find_map(|p| body.pointer(p))
    .and_then(|b| b.as_str())?;
    let links = if body.get("callAcceptance").is_some() {
        body.pointer("/callAcceptance/links")
    } else {
        body.get("links")
    };
    let link = |name: &str| {
        links
            .and_then(|l| l.get(name))
            .and_then(|u| u.as_str())
            .map(str::to_string)
    };
    Some(Ok(Acceptance {
        sdp: blob.to_string(),
        acknowledgement: link("acknowledgement"),
        call_leg: link("callLeg"),
        hold: link("hold"),
        transfer: link("transfer"),
        replace: link("replace").or_else(|| link("replacement")),
        answered_by: body
            .pointer("/callAcceptance/acceptedBy/displayName")
            .and_then(|n| n.as_str())
            .filter(|n| !n.trim().is_empty())
            .map(str::to_string),
        provisional: body.get("mediaAnswer").is_some() && body.get("callAcceptance").is_none(),
        renegotiation: link("mediaRenegotiation"),
        end: link("end"),
        media_descriptions: link("updateMediaDescriptions"),
        in_lobby: body
            .pointer("/callAcceptance/acceptedCallModalities")
            .and_then(|m| m.as_array())
            .is_some_and(|m| m.is_empty()),
        ..Default::default()
    }))
}

/// The service ended a call before it was answered (`call/end` or
/// `conversation/conversationEnd`): its code, sub-code and phrase.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallEnded {
    pub code: u64,
    pub sub_code: u64,
    pub phrase: String,
}

impl CallEnded {
    /// The end in a call end event, if it is one.
    pub fn from_event(json: &str) -> Option<Self> {
        if !super::incoming::is_call_end_event(json) {
            return None;
        }
        let v: serde_json::Value = serde_json::from_str(json).ok()?;
        let body = v.get("body").filter(|b| !b.is_null()).unwrap_or(&v);
        let end = body.get("callEnd").unwrap_or(body);
        let num = |k: &str| end.get(k).and_then(|c| c.as_u64()).unwrap_or_default();
        Some(Self {
            code: num("code"),
            sub_code: num("subCode"),
            phrase: end
                .get("phrase")
                .and_then(|p| p.as_str())
                .unwrap_or("call ended")
                .to_string(),
        })
    }

    /// Teams' "not allowed to join breakout room" end (403, sub-code
    /// 5745: "Conversation ending after breakout room is not open."),
    /// which it shows as "You don't have access to this room".
    pub fn not_allowed_in_breakout_room(&self) -> bool {
        self.code == 403 && self.sub_code == 5745
    }
}

impl std::fmt::Display for CallEnded {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} ({})", self.phrase, self.code)
    }
}

impl std::error::Error for CallEnded {}

/// How long a failed or withdrawn call's late answer is watched for.
const LATE_LEG_WATCH: Duration = Duration::from_secs(30);

/// The callback tag a call event carries (`callTag`, from the
/// `…/x<tag>/callAgent/…` callback it came on).
fn event_call_tag(json: &str) -> Option<String> {
    if !json.contains("\"callTag\"") {
        return None;
    }
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    v.get("callTag")?.as_str().map(str::to_string)
}

/// Whether a call event is another placed call's (it carries a tag that
/// isn't `tag`). Untagged events (invitations) may be anyone's.
fn is_other_calls_event(json: &str, tag: &str) -> bool {
    event_call_tag(json).is_some_and(|t| t != tag)
}

/// A call whose join failed (or was withdrawn) after its request went out:
/// watch its events a little longer and hang up the leg of an answer that
/// still comes, so none is left behind in the meeting.
fn end_late_leg(
    mut events: tokio::sync::broadcast::Receiver<event_hub::Event>,
    tag: String,
    http: reqwest::Client,
    skype_token: String,
) {
    tokio::spawn(async move {
        let deadline = tokio::time::sleep(LATE_LEG_WATCH);
        tokio::pin!(deadline);
        loop {
            let ev = tokio::select! {
                _ = &mut deadline => return,
                ev = events.recv() => ev,
            };
            let ev = match ev {
                Ok(ev) => ev,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(_) => return,
            };
            if ev.kind != EventKind::Call
                || event_call_tag(&ev.json).as_deref() != Some(tag.as_str())
            {
                continue;
            }
            let Some(Ok(late)) = read_answer(&ev.json) else {
                continue;
            };
            tracing::info!("a failed join's call was answered late; hanging it up");
            let ended = match (&late.call_leg, &late.end) {
                (Some(leg), _) => http
                    .delete(leg)
                    .header("X-Skypetoken", &skype_token)
                    .json(&serde_json::json!({
                        "callEnd": { "code": 0, "subCode": 0, "phrase": "CallEndReasonLocalUserInitiated" }
                    }))
                    .send()
                    .await
                    .map(|r| r.status()),
                (None, Some(end)) => http
                    .post(end)
                    .header("X-Skypetoken", &skype_token)
                    .json(&serde_json::json!({}))
                    .send()
                    .await
                    .map(|r| r.status()),
                (None, None) => {
                    tracing::warn!("the late answer has no leg to end");
                    return;
                }
            };
            match ended {
                Ok(status) => tracing::info!(%status, "late call leg ended"),
                Err(e) => tracing::warn!("ending the late call leg: {e:#}"),
            }
            return;
        }
    });
}

/// Whether the join response holds our endpoint in the meeting's lobby:
/// its roster entry has the `lobby` modality and no `call` (the media
/// processor's acceptance carries no modalities either way, so it can't
/// tell).
fn endpoint_in_lobby(create_response: &str, endpoint_id: &str) -> bool {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(create_response) else {
        return false;
    };
    let Some(participants) = [
        "/roster/participants",
        "/conversationResponse/roster/participants",
    ]
    .iter()
    .find_map(|p| v.pointer(p))
    .and_then(|p| p.as_object()) else {
        return false;
    };
    participants
        .values()
        .filter_map(|p| p.pointer(&format!("/endpoints/{endpoint_id}")))
        .any(|ep| ep.get("lobby").is_some() && ep.get("call").is_none())
}

/// A call leg's links after the service moved it to another call.
#[derive(Debug, PartialEq)]
pub struct LegLinks {
    pub call_leg: String,
    pub hold: Option<String>,
    pub transfer: Option<String>,
    pub renegotiation: Option<String>,
    pub media_descriptions: Option<String>,
}

/// A `call/mediaAcknowledgement` that moved our leg ("Participant retarget
/// was successful." when the lobby admits us): its new links. The plain
/// acknowledgements of our re-offers carry `callLeg: null` and give none.
pub fn leg_retarget(json: &str) -> Option<LegLinks> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    if !v
        .get("callAgentPath")?
        .as_str()?
        .starts_with("call/mediaAcknowledgement")
    {
        return None;
    }
    let links = v.pointer("/body/links")?;
    let link = |name: &str| links.get(name).and_then(|u| u.as_str()).map(str::to_string);
    Some(LegLinks {
        call_leg: link("callLeg")?,
        hold: link("hold"),
        transfer: link("transfer"),
        renegotiation: link("mediaRenegotiation"),
        media_descriptions: link("updateMediaDescriptions"),
    })
}

/// A conversation update admitting us from a meeting's lobby (the call
/// modality appears in `activeModalities`): its body, whose links replace
/// the lobby's few.
pub fn lobby_admission(json: &str) -> Option<serde_json::Value> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let path = v.get("callAgentPath")?.as_str()?;
    if !path.starts_with("conversation/conversationUpdate") {
        return None;
    }
    let body = v.get("body")?;
    body.pointer("/activeModalities/call")
        .filter(|c| c.is_object())
        .map(|_| body.clone())
}

/// Call a Teams user. Resolves once the callee answers and audio is set
/// up, or fails if they decline, do not answer, or the call fails.
/// Sending on (or dropping) `cancel` while the callee is still ringing
/// withdraws the call, so their ringing stops. A video call offers our
/// camera from the start (its line is sendrecv), as Teams' Video call does;
/// the camera then starts with `set_camera` once answered.
pub async fn place_call(
    thread_id: &str,
    callee_mri: &str,
    video: bool,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start(thread_id, Target::Person(callee_mri, video), cancel).await
}

/// The call a transfer asks us to make (Teams' `onTransferRequested`: our
/// side of someone transferring or parking the call we're in): a 1:1 call
/// to the transfer's target carrying its `transferor` (with the service's
/// authorization token) and transfer context, with its own callback tag.
pub async fn place_transfer_call(
    thread_id: &str,
    target_mri: &str,
    extras: &signaling::CallExtras,
    call_tag: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start_tagged(
        thread_id,
        Target::PersonWith(target_mri, extras),
        Some(call_tag.to_string()),
        cancel,
    )
    .await
}

/// Retrieve a parked call with its pickup code (Teams' `startUnparkCall`:
/// a call to the park server, `4:*11`, with `unparkContent {pickupCode}`).
pub async fn unpark_call(
    thread_id: &str,
    pickup_code: i64,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    let extras = signaling::CallExtras {
        unpark_code: Some(pickup_code),
        ..Default::default()
    };
    start_tagged(
        thread_id,
        Target::PersonWith(signaling::CALL_PARK_MRI, &extras),
        None,
        cancel,
    )
    .await
}

/// Call your own voicemail (Teams' `startVoicemailCall`, from Settings ▸
/// Calls ▸ Record a greeting): a 1:1 call to yourself whose callee is your
/// voicemail endpoint, asking for its greeting resource, so the voicemail
/// service answers and lets you record your greeting.
pub async fn call_own_voicemail(
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    let config = Config::load()?;
    let me = config.self_mri().context("Signed-in user has no MRI")?;
    let extras = signaling::CallExtras {
        voicemail: Some(signaling::VOICEMAIL_GREETING.to_string()),
        ..Default::default()
    };
    start_tagged("", Target::PersonWith(&me, &extras), None, cancel).await
}

/// Teams' test call to your intelligent call delegation (its
/// `TestCallToPA` intent: a 1:1 call to yourself, no chat thread, audio
/// only, answered by your personal attendant).
pub async fn call_personal_attendant(
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    let config = Config::load()?;
    let me = config.self_mri().context("Signed-in user has no MRI")?;
    let extras = signaling::CallExtras {
        personal_attendant: true,
        ..Default::default()
    };
    start_tagged("", Target::PersonWith(&me, &extras), None, cancel).await
}

/// [`place_call`] with its callback tag chosen up front ([`new_call_tag`]):
/// a second call placed while another goes on (a consult call), whose
/// events must be told apart from the first call's from the start.
pub async fn place_call_tagged(
    thread_id: &str,
    callee_mri: &str,
    call_tag: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start_tagged(
        thread_id,
        Target::Person(callee_mri, false),
        Some(call_tag.to_string()),
        cancel,
    )
    .await
}

/// A Teams meeting, from its join link
/// (`https://teams.microsoft.com/l/meetup-join/<thread>/<message>?context=…`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeetingLink {
    /// The meeting's chat thread, `19:meeting_…@thread.v2`.
    pub thread_id: String,
    /// `0` for scheduled meetings.
    pub message_id: String,
    /// From the link's context: the organizer's object id and the tenant.
    pub organizer_id: Option<String>,
    pub tenant_id: Option<String>,
    /// A meeting known only by its ID and passcode (Teams' MeetingData
    /// join: `{meetingCode, passcode, meetingUrl}`), its thread still
    /// unknown: `thread_id` is empty until the meeting names it.
    pub meeting_data: Option<serde_json::Value>,
}

impl MeetingLink {
    /// A meeting by its short link (`https://teams.microsoft.com/meet/
    /// <ID>?p=<passcode>`), joined as Teams' Join with an ID does: by
    /// `meetingData`, its thread unknown until it's named.
    pub fn parse_short(url: &str) -> Option<Self> {
        let rest = url.strip_prefix("https://teams.microsoft.com/meet/")?;
        let (code, query) = rest.split_once('?').unwrap_or((rest, ""));
        let code = code.trim_end_matches('/');
        if code.is_empty() || !code.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        let pass = query
            .split('&')
            .find_map(|kv| kv.strip_prefix("p="))
            .and_then(percent_decode)
            .unwrap_or_default();
        Some(Self::by_code(code, &pass))
    }

    /// A meeting by its ID and passcode (see [`Self::parse_short`]).
    pub fn by_code(code: &str, pass: &str) -> Self {
        Self {
            thread_id: String::new(),
            message_id: "0".into(),
            organizer_id: None,
            tenant_id: None,
            meeting_data: Some(serde_json::json!({
                "meetingCode": code,
                "passcode": if pass.is_empty() { serde_json::Value::Null } else { pass.into() },
                "meetingUrl": format!("https://teams.microsoft.com/meet/{code}?p={pass}"),
            })),
        }
    }

    /// A join link of either kind ([`Self::parse`], [`Self::parse_short`]).
    pub fn parse_join(url: &str) -> Option<Self> {
        Self::parse(url).or_else(|| Self::parse_short(url))
    }

    pub fn parse(url: &str) -> Option<Self> {
        let rest = url
            .strip_prefix("https://teams.microsoft.com/l/meetup-join/")
            .or_else(|| url.strip_prefix("https://teams.live.com/l/meetup-join/"))?;
        let path = rest.split(['?', '#']).next()?;
        let (thread, message) = path.split_once('/')?;
        let thread = percent_decode(thread)?;
        let message = percent_decode(message.trim_end_matches('/'))?;
        // A scheduled meeting's chat (`@thread.v2`), or the channel a
        // channel meeting was started in (`@thread.tacv2`, the meeting
        // keyed by its post's message id).
        let body = thread.strip_prefix("19:").and_then(|t| {
            t.strip_suffix("@thread.v2")
                .or_else(|| t.strip_suffix("@thread.tacv2"))
        });
        let valid_thread = body.is_some_and(|b| {
            !b.is_empty()
                && b.chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_-=".contains(c))
        });
        if !valid_thread || message.is_empty() || !message.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        // context={"Tid":"…","Oid":"…"}, percent-encoded.
        let context = url
            .split_once("context=")
            .and_then(|(_, c)| percent_decode(c.split('&').next().unwrap_or_default()))
            .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok());
        let guid = |k: &str| {
            context
                .as_ref()
                .and_then(|c| c.get(k))
                .and_then(|v| v.as_str())
                .filter(|g| uuid::Uuid::parse_str(g).is_ok())
                .map(str::to_string)
        };
        Some(Self {
            thread_id: thread,
            message_id: message,
            organizer_id: guid("Oid"),
            tenant_id: guid("Tid"),
            meeting_data: None,
        })
    }

    /// Teams' meeting options page (Controls), when the link names the
    /// organizer and tenant.
    pub fn options_url(&self) -> Option<String> {
        let (o, t) = (self.organizer_id.as_ref()?, self.tenant_id.as_ref()?);
        Some(format!(
            "https://teams.microsoft.com/meetingOptions/?organizerId={o}&tenantId={t}&threadId={}&messageId={}&language=en-US",
            self.thread_id.replace(':', "%3A").replace('@', "%40"),
            self.message_id
        ))
    }

    /// The meeting's chat on Teams on the web (its Notes tab is there).
    pub fn chat_url(&self) -> String {
        format!(
            "https://teams.microsoft.com/l/chat/{}/conversations",
            self.thread_id.replace(':', "%3A").replace('@', "%40")
        )
    }
}

fn percent_decode(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let hex = std::str::from_utf8(b.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// A new call's callback tag (`…/x<tag>/callAgent/…`): its events carry it
/// as `callTag`, so they can't be taken for another call's.
pub fn new_call_tag() -> String {
    uuid::Uuid::new_v4().simple().to_string()[..12].to_string()
}

/// Join a Teams meeting (a breakout room is one too). Resolves once the
/// meeting's conference server answers and audio is set up; `cancel`
/// withdraws while it connects. `call_tag` (from [`new_call_tag`]) is the
/// call's callback tag, so the caller can tell its events, even after the
/// join failed, from those of the meeting it's in.
pub async fn join_meeting(
    link: &MeetingLink,
    call_tag: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    join_meeting_with(link, call_tag, JoinHow::default(), cancel).await
}

/// How a meeting is joined beyond its link ([`join_meeting_with`]).
#[derive(Default, Clone, Copy)]
pub struct JoinHow<'a> {
    /// Wait this long after the conversation join for the meeting's
    /// `meetingData`, which the call then carries (Teams' moves into a
    /// breakout room send the room's code and passcode).
    pub meeting_data_wait: Option<Duration>,
    /// The meeting's conversation we kept without a call (the main
    /// meeting while in a breakout room): the call goes straight to it,
    /// with its `meetingData`, as Teams goes back to the main meeting.
    pub kept: Option<&'a KeptConversation>,
    /// Teams' Preview as Attendee: join a town hall as its attendees do
    /// (the meeting then streams to us).
    pub as_attendee: bool,
}

/// [`join_meeting`], the way `how` says.
pub async fn join_meeting_with(
    link: &MeetingLink,
    call_tag: &str,
    how: JoinHow<'_>,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start_tagged(
        &link.thread_id,
        Target::Meeting(link, how),
        Some(call_tag.to_string()),
        cancel,
    )
    .await
}

/// A meeting's conversation we're in without a call: Teams keeps the main
/// meeting's this way while you're in one of its breakout rooms (captured
/// 2026-11-17: once the room's call is accepted it leaves the main
/// meeting and at once joins its conversation again without a call, a new
/// participant id), so the main meeting's updates keep coming; going back
/// posts the call straight to it.
pub struct KeptConversation {
    /// The meeting's join link.
    pub join_url: String,
    pub link: MeetingLink,
    controller: String,
    leave_link: Option<String>,
    participant_id: String,
    tag: String,
    meeting_data: Option<serde_json::Value>,
    me: serde_json::Value,
    http: reqwest::Client,
    skype_token: String,
}

impl KeptConversation {
    /// The tag of its callbacks (its events carry it as `callTag`).
    pub fn call_tag(&self) -> &str {
        &self.tag
    }

    /// Keep what the conversation's update says (its `meetingData`).
    pub fn note_event(&mut self, json: &str) {
        if let Some(md) = signaling::meeting_data_of(json, Some(&self.tag)) {
            self.meeting_data = Some(md);
        }
    }

    /// Leave the conversation (`POST links.leave`).
    pub async fn leave(self) -> Result<()> {
        let link = self.leave_link.clone().unwrap_or_else(|| {
            let (path, query) = self
                .controller
                .split_once('?')
                .unwrap_or((&self.controller, ""));
            let path = path.trim_end_matches('/');
            if query.is_empty() {
                format!("{path}/leave")
            } else {
                format!("{path}/leave?{query}")
            }
        });
        cc_post(
            &self.http,
            &self.skype_token,
            &link,
            &leave_body(&self.me),
            "Leave the kept conversation",
        )
        .await?;
        tracing::info!("left the main meeting's conversation");
        Ok(())
    }
}

/// Join a meeting's conversation again without a call, at its own URL
/// (`conversation_url`, from the call we just left there): see
/// [`KeptConversation`].
pub async fn keep_conversation(
    join_url: &str,
    link: &MeetingLink,
    conversation_url: &str,
) -> Result<KeptConversation> {
    let config = Config::load()?;
    let ic3_token = config
        .get_ic3_token()
        .context("No calling (IC3) token")?
        .token;
    let skype_token = config.get_skype_token().context("Not signed in")?.token;
    let oid = config
        .object_id()
        .context("Signed-in user has no object id")?;
    let tenant_id = config.tenant_id().context("No tenant id")?;
    let display_name = config.display_name().unwrap_or_default();
    let (surl, endpoint_id) =
        crate::trouter::current_endpoint().context("Push channel is not connected")?;
    let tag = new_call_tag();
    let surl = format!("{}/x{tag}/", surl.trim_end_matches('/'));
    let caller_mri = config.self_mri().context("Signed-in user has no MRI")?;
    let participant_id = uuid::Uuid::new_v4().to_string();
    let chain_id = uuid::Uuid::new_v4().to_string();
    let message_id = uuid::Uuid::new_v4().to_string();
    let params = signaling::ConversationCallParams {
        ic3_token: &ic3_token,
        trouter_surl: &surl,
        caller_mri: &caller_mri,
        caller_display_name: &display_name,
        endpoint_id: &endpoint_id,
        participant_id: &participant_id,
        thread_id: &link.thread_id,
        chain_id: &chain_id,
        message_id: &message_id,
        caller_oid: &oid,
        tenant_id: &tenant_id,
    };
    let http = reqwest::Client::new();
    let organizer = link.organizer_id.as_deref().zip(link.tenant_id.as_deref());
    let (controller, leave_link) = signaling::join_conversation_without_call(
        &http,
        conversation_url,
        &params,
        &link.message_id,
        organizer,
    )
    .await?;
    tracing::info!(tag = %tag, "kept the main meeting's conversation (no call)");
    Ok(KeptConversation {
        join_url: join_url.to_string(),
        link: link.clone(),
        controller,
        leave_link,
        me: serde_json::json!({
            "id": caller_mri,
            "displayName": display_name,
            "endpointId": endpoint_id,
            "participantId": participant_id,
            "languageId": "en-US",
        }),
        participant_id,
        tag,
        meeting_data: None,
        http,
        skype_token,
    })
}

/// Join a Teams meeting the way Teams' pre-join window does while it is
/// open (its preheat, Teams on the web 2026-11-16): the conversation, then
/// the call with `preheatProperties: 1`. The call and its media come up,
/// but nobody sees us (the roster leaves our endpoint out; held in a
/// lobby, only we see ourselves there) and nothing is sent or played.
/// The meeting's details arrive as for a real join (its dial-in, so
/// pre-join knows about Phone audio). [`OutgoingCall::join_preheated`]
/// then joins for real; [`OutgoingCall::leave`] cancels. `call_tag` is
/// the tag for its callback URLs, so its events can be told apart before
/// it resolves.
pub async fn preheat_meeting(
    link: &MeetingLink,
    call_tag: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start(
        &link.thread_id,
        Target::MeetingPreheat(link, call_tag),
        cancel,
    )
    .await
}

/// Teams' ECS `meetingJoin.joinOngoingMeetingInPreheatedFlow` (Teams
/// desktop's preheatService, read from its bundles 2026-11-17; default off,
/// on in ost-test1's settings): a pre-join's preheat of a meeting whose
/// call is going on joins that call (`call.join({conversationUrl,
/// conversationId})`, the active call Teams knows from the meeting chat's
/// `awareness_conversationLiveState`) instead of starting one
/// (`call.start`, the conversation first, then the call to it).
fn preheat_joins_ongoing() -> bool {
    crate::api::ecs::setting("meetingJoin", "joinOngoingMeetingInPreheatedFlow")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// Where an ongoing call is joined: its conversation's URL (a service
/// link) and the meeting's `meetingData` the liveness entry names.
fn ongoing_join(live: &crate::api::LiveCall) -> Option<(&str, Option<&serde_json::Value>)> {
    super::incoming::is_service_link(&live.conversation_url)
        .then_some((live.conversation_url.as_str(), live.meeting_data.as_ref()))
}

/// Join with an ID: the meeting a meeting ID and passcode stand for, as
/// Teams' calling stack finds it (the conversation joined with
/// `meetingData {meetingCode, passcode, meetingUrl}`, then left), as a
/// join link OST's pre-join and join take.
pub async fn resolve_meeting_id(meeting_id: &str, passcode: &str) -> Result<(MeetingLink, String)> {
    let code: String = meeting_id.chars().filter(|c| !c.is_whitespace()).collect();
    let pass: String = passcode.chars().filter(|c| !c.is_whitespace()).collect();
    if code.is_empty() || !code.bytes().all(|b| b.is_ascii_digit()) {
        bail!("Not a meeting ID");
    }
    let mut config = Config::load()?;
    if config.get_ic3_token().is_none_or(|t| t.is_expired()) {
        crate::auth::oauth::refresh()
            .await
            .context("Token refresh failed")?;
        config = Config::load()?;
    }
    let ic3_token = config
        .get_ic3_token()
        .context("No calling (IC3) token")?
        .token;
    let oid = config
        .object_id()
        .context("Signed-in user has no object id")?;
    let tenant_id = config.tenant_id().context("No tenant id")?;
    let display_name = config.display_name().unwrap_or_default();
    let region = config.get_region_gtms().context("No region endpoints")?;
    let epconv_url =
        call_test::derive_epconv_url(&region).context("No conversation service URL")?;
    let (surl, endpoint_id) =
        crate::trouter::current_endpoint().context("Push channel is not connected")?;
    let surl = format!("{}/x{}/", surl.trim_end_matches('/'), new_call_tag());
    let caller_mri = config.self_mri().context("Signed-in user has no MRI")?;
    let participant_id = uuid::Uuid::new_v4().to_string();
    let chain_id = uuid::Uuid::new_v4().to_string();
    let message_id = uuid::Uuid::new_v4().to_string();
    let params = signaling::ConversationCallParams {
        ic3_token: &ic3_token,
        trouter_surl: &surl,
        caller_mri: &caller_mri,
        caller_display_name: &display_name,
        endpoint_id: &endpoint_id,
        participant_id: &participant_id,
        thread_id: "",
        chain_id: &chain_id,
        message_id: &message_id,
        caller_oid: &oid,
        tenant_id: &tenant_id,
    };
    let by_code = MeetingLink::by_code(&code, &pass);
    let data = by_code.meeting_data.clone().unwrap_or_default();
    let (thread, organizer, tenant, subject) =
        signaling::resolve_meeting_code(&reqwest::Client::new(), &epconv_url, &params, &data)
            .await?;
    // The lobby holds us: the meeting names no thread until we're let
    // in, so it's joined by its meetingData, as Teams joins it.
    let Some(thread) = thread else {
        tracing::info!("join with an ID: no thread before the lobby; joining by meetingData");
        return Ok((by_code, subject));
    };
    Ok((
        MeetingLink {
            thread_id: thread,
            message_id: "0".into(),
            organizer_id: organizer,
            tenant_id: tenant,
            meeting_data: None,
        },
        subject,
    ))
}

/// Start or join a group chat's call (`19:…@thread.v2`), as Teams does:
/// Meet now (a huddle; members are nudged), Audio call (members are rung)
/// or Join (the chat's ongoing call).
pub async fn start_group_call(
    thread_id: &str,
    kind: signaling::GroupCallKind,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    if !is_group_chat(thread_id) {
        bail!("Not a group chat");
    }
    start(thread_id, Target::Group(kind), cancel).await
}

/// Start a meeting in a channel now (Teams' channel Meet now).
pub async fn start_channel_meeting(
    channel_id: &str,
    subject: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    if !(channel_id.starts_with("19:") && channel_id.ends_with("@thread.tacv2")) {
        bail!("Not a channel");
    }
    start(channel_id, Target::ChannelMeeting(subject), cancel).await
}

/// Teams' test call (Settings ▸ Devices ▸ Make a test call), as Teams'
/// `placeEchoBotCall`: make sure the chat with the Echo bot exists, start
/// a group call in it (scenario `UserInitiatedTestCall`, nobody rung) and
/// invite the bot, which plays its prompt, records you and plays it back.
pub async fn start_test_call(cancel: tokio::sync::oneshot::Receiver<()>) -> Result<OutgoingCall> {
    let config = Config::load()?;
    let oid = config
        .object_id()
        .context("Signed-in user has no object id")?;
    let thread = signaling::echo_thread_id(&oid);
    match crate::api::client::TeamsClient::new().await {
        Ok(client) => {
            if let Err(e) = crate::api::ensure_unique_chat(
                &client,
                &thread,
                &config.self_mri().context("Signed-in user has no MRI")?,
                signaling::ECHO_BOT_MRI,
                None,
            )
            .await
            {
                tracing::warn!("Echo chat: {:#}", e);
            }
        }
        Err(e) => tracing::warn!("Echo chat: {:#}", e),
    }
    start(&thread, Target::Echo, cancel).await
}

/// Group chats (not meetings, channels or 1:1 chats).
/// Teams' addRoomParticipant request: our participant inviting the room
/// account to the meeting with Teams' invitation data (see
/// `OutgoingCall::add_room`).
#[allow(clippy::too_many_arguments)]
pub fn room_invite_body(
    from: &serde_json::Value,
    room_mri: &str,
    room_name: &str,
    thread_id: &str,
    message_id: Option<&str>,
    validation_code: Option<u16>,
    ultrasound: bool,
    meeting_info: Option<(String, String)>,
    links: serde_json::Value,
) -> serde_json::Value {
    let mut invitation = serde_json::json!({
        "proximitySource": if ultrasound { 2 } else { 1 },
        "deviceType": "computer",
        "autoAcceptAuthorization": validation_code.map(|c| serde_json::json!({ "token": c })),
    });
    if let Some((organizer, tenant)) = meeting_info {
        invitation["meetingInfo"] =
            serde_json::json!({ "organizerId": organizer, "tenantId": tenant });
    }
    serde_json::json!({
        "participants": {
            "from": from,
            "to": [{ "id": room_mri, "displayName": room_name }],
        },
        "participantInvitationData": { "invitationData": invitation },
        "groupContext": null,
        "groupChat": { "threadId": thread_id, "messageId": message_id },
        "links": links,
    })
}

pub fn is_group_chat(thread_id: &str) -> bool {
    thread_id.starts_with("19:")
        && thread_id.ends_with("@thread.v2")
        && !thread_id.starts_with("19:meeting_")
}

enum Target<'a> {
    /// A 1:1 call to this MRI; a video call when true.
    Person(&'a str, bool),
    /// A 1:1 (audio) call carrying a transfer's or an unpark's extras.
    PersonWith(&'a str, &'a signaling::CallExtras),
    /// A group chat's call: Meet now, Audio call or Join.
    Group(signaling::GroupCallKind),
    /// The meeting a join link names (its message id on the thread and
    /// its organizer), joined as `JoinHow` says.
    Meeting(&'a MeetingLink, JoinHow<'a>),
    /// The same meeting joined preheated (pre-join), with the callback tag
    /// to use.
    MeetingPreheat(&'a MeetingLink, &'a str),
    /// A new meeting in a channel (Meet now), with this title.
    ChannelMeeting(&'a str),
    /// Teams' test call with the Echo bot.
    Echo,
}

async fn start(
    thread_id: &str,
    target: Target<'_>,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start_tagged(thread_id, target, None, cancel).await
}

async fn start_tagged(
    thread_id: &str,
    target: Target<'_>,
    call_tag: Option<String>,
    mut cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    let mut config = Config::load()?;
    if config.get_skype_token().is_none_or(|t| t.is_expired())
        || config.get_ic3_token().is_none_or(|t| t.is_expired())
    {
        crate::auth::oauth::refresh()
            .await
            .context("Token refresh failed")?;
        config = Config::load()?;
    }
    let skype_token = config.get_skype_token().context("Not signed in")?.token;
    let ic3_token = config
        .get_ic3_token()
        .context("No calling (IC3) token")?
        .token;
    let oid = config
        .object_id()
        .context("Signed-in user has no object id")?;
    let tenant_id = config.tenant_id().context("No tenant id")?;
    let display_name = config.display_name().unwrap_or_default();
    let region = config.get_region_gtms().context("No region endpoints")?;
    let epconv_url =
        call_test::derive_epconv_url(&region).context("No conversation service URL")?;
    let (surl, endpoint_id) =
        crate::trouter::current_endpoint().context("Push channel is not connected")?;
    // This call's own callback base (`…/x<tag>/callAgent/…`): its events
    // say which call they're for, so a meeting we're leaving while joining
    // the next (breakout rooms) can't end the new one.
    let call_tag = match &target {
        Target::MeetingPreheat(_, tag) => tag.to_string(),
        // Into the conversation we kept: its callbacks' tag, so its
        // conversation's events and the call's are one call's.
        Target::Meeting(_, JoinHow { kept: Some(k), .. }) => k.tag.clone(),
        _ => call_tag.unwrap_or_else(new_call_tag),
    };
    let surl = format!("{}/x{call_tag}/", surl.trim_end_matches('/'));

    let mut local = LocalAudio::prepare().await?;
    // 1:1 calls offer video too (Teams' calls do); meetings and group
    // calls stay audio-only, since a media processor sends video only to
    // those who subscribe to it.
    // Meetings and group calls offer receive slots and a data line, as
    // Teams does: others' video comes as the media control plane asks.
    let meeting_media =
        cfg!(feature = "video") && !matches!(target, Target::Person(..) | Target::PersonWith(..));
    let offer = if let (Target::Person(_, video), true) = (&target, cfg!(feature = "video")) {
        local.receive_video = true;
        local.camera_on = *video;
        local.offer_sdp_with_video()
    } else if meeting_media {
        local.receive_video = true;
        local.meeting = true;
        local.offer_sdp_meeting()
    } else {
        local.offer_sdp()
    };
    let caller_mri = config.self_mri().context("Signed-in user has no MRI")?;
    // Into the conversation we kept: as the participant we are there.
    let participant_id = match &target {
        Target::Meeting(_, JoinHow { kept: Some(k), .. }) => k.participant_id.clone(),
        _ => uuid::Uuid::new_v4().to_string(),
    };
    // Joining a call that's going on (a meeting's, or a chat's), Teams
    // uses that call's id as the chain id: it's the call's id for
    // everyone in it (shares are tagged with it). A new call gets a new id.
    // (A meeting known only by its ID has no thread to look up.)
    let joins_ongoing = !thread_id.is_empty()
        && matches!(
            target,
            Target::Meeting(..)
                | Target::MeetingPreheat(..)
                | Target::Group(signaling::GroupCallKind::Join)
        );
    let ongoing = if joins_ongoing {
        match crate::api::client::TeamsClient::new().await {
            Ok(client) => crate::api::thread_live_call(&client, thread_id)
                .await
                .unwrap_or_else(|e| {
                    tracing::warn!("Ongoing call unknown: {:#}", e);
                    None
                }),
            Err(e) => {
                tracing::warn!("Ongoing call unknown: {:#}", e);
                None
            }
        }
    } else {
        None
    };
    let chain_id = ongoing
        .as_ref()
        .map(|c| c.call_id.clone())
        .filter(|id| !id.is_empty())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let message_id = uuid::Uuid::new_v4().to_string();
    let params = signaling::ConversationCallParams {
        ic3_token: &ic3_token,
        trouter_surl: &surl,
        caller_mri: &caller_mri,
        caller_display_name: &display_name,
        endpoint_id: &endpoint_id,
        participant_id: &participant_id,
        thread_id,
        chain_id: &chain_id,
        message_id: &message_id,
        caller_oid: &oid,
        tenant_id: &tenant_id,
    };
    let http = reqwest::Client::new();

    // Listen before placing the call so the answer cannot be missed.
    let mut events = event_hub::subscribe();
    // A group call names the chat's members (rung, or nudged for Meet now).
    let members: Vec<String> = if matches!(target, Target::Group(_)) {
        match crate::api::client::TeamsClient::new().await {
            Ok(client) => match crate::api::files::member_mris(&client, thread_id).await {
                Ok(mris) => mris.into_iter().take(MAX_RING).collect(),
                Err(e) => {
                    tracing::warn!("Group members unavailable: {:#}", e);
                    Vec::new()
                }
            },
            Err(e) => {
                tracing::warn!("Group members unavailable: {:#}", e);
                Vec::new()
            }
        }
    } else {
        Vec::new()
    };
    let meeting_message_id = match &target {
        Target::Meeting(link, _) | Target::MeetingPreheat(link, _) => Some(link.message_id.clone()),
        _ => None,
    };
    let preheat = matches!(target, Target::MeetingPreheat(..));
    let meeting_join = matches!(target, Target::Meeting(..) | Target::MeetingPreheat(..));
    let (created, _joined) = match target {
        Target::Person(callee, _) => {
            signaling::create_1to1_call_to(&http, &epconv_url, &params, &offer, Some(callee))
                .await?
        }
        Target::PersonWith(callee, extras) => {
            signaling::create_1to1_call_with(&http, &epconv_url, &params, &offer, callee, extras)
                .await?
        }
        Target::Group(kind) => {
            signaling::create_group_call(&http, &epconv_url, &params, &offer, &members, kind)
                .await?
        }
        Target::Meeting(link, how) => {
            let organizer = link.organizer_id.as_deref().zip(link.tenant_id.as_deref());
            let opts = signaling::MeetingJoinOptions {
                preheat: false,
                meeting_data_wait: how.meeting_data_wait,
                // A meeting known by its ID only: its meetingData (Teams'
                // MeetingData join).
                meeting_data: how
                    .kept
                    .and_then(|k| k.meeting_data.clone())
                    .or_else(|| link.meeting_data.clone()),
                conversation_url: how.kept.map(|k| k.controller.as_str()),
                as_attendee: how.as_attendee,
            };
            signaling::join_meeting(
                &http,
                &epconv_url,
                &params,
                &offer,
                &link.message_id,
                organizer,
                &opts,
            )
            .await?
        }
        Target::MeetingPreheat(link, _) => {
            let organizer = link.organizer_id.as_deref().zip(link.tenant_id.as_deref());
            // A meeting whose call is going on: with Teams' ECS
            // joinOngoingMeetingInPreheatedFlow (on for ost-test1) the
            // preheat joins that call where it is, as Teams' join of an
            // ongoing meeting does (preheatService joinExistingCall).
            let live = preheat_joins_ongoing()
                .then_some(ongoing.as_ref())
                .flatten()
                .and_then(ongoing_join);
            let opts = signaling::MeetingJoinOptions {
                preheat: true,
                conversation_url: live.map(|(url, _)| url),
                meeting_data: live.and_then(|(_, md)| md.cloned()),
                ..Default::default()
            };
            if live.is_some() {
                tracing::info!(
                    "pre-join: the meeting is going on; preheating its call where it is"
                );
            }
            signaling::join_meeting(
                &http,
                &epconv_url,
                &params,
                &offer,
                &link.message_id,
                organizer,
                &opts,
            )
            .await?
        }
        Target::ChannelMeeting(subject) => {
            signaling::create_channel_meeting(&http, &epconv_url, &params, &offer, subject).await?
        }
        Target::Echo => {
            let created = signaling::create_echo_call(&http, &epconv_url, &params, &offer).await?;
            signaling::invite_echo_bot(&http, &created.0.conversation_controller, &params).await?;
            created
        }
    };
    let leave_url = leave_link(&created.response_body);

    let state_links = (
        conversation_link(&created.response_body, "publishState"),
        conversation_link(&created.response_body, "removeState"),
    );
    let all_participants = conversation_link(&created.response_body, "getAllParticipants");
    let admit_links = (
        conversation_link(&created.response_body, "admit"),
        conversation_link(&created.response_body, "admitAll"),
    );
    let remove_link = conversation_link(&created.response_body, "removeParticipant");
    let controller = controller_link(&created.response_body);
    let invite_url = invite_url(&created.response_body);
    let mute_link = conversation_link(&created.response_body, "mute");
    let unmute_link = conversation_link(&created.response_body, "unmute");
    let metadata_link = conversation_link(&created.response_body, "updateEndpointMetadata");
    let add_participant_link = conversation_link(&created.response_body, "addParticipant");
    let meeting_states_link = conversation_link(&created.response_body, "updateMeetingStates");
    let add_modality_link = conversation_link(&created.response_body, "addParticipantAndModality");
    let content_link = conversation_link(&created.response_body, "addModality");
    tracing::info!(content = content_link.is_some(), "content sharing link");
    let group_message_id =
        meeting_message_id.or_else(|| group_chat_field(&created.response_body, "messageId"));
    let (dial_in, phone_audio) = serde_json::from_str::<serde_json::Value>(&created.response_body)
        .ok()
        .map(|v| {
            let p = super::phone_audio::phone_audio(&v, false).unwrap_or_default();
            let d = super::phone_audio::dial_in(&v);
            tracing::info!(
                available = p.available,
                dial_in = p.dial_in,
                dial_out = p.dial_out,
                details = d.is_some(),
                "phone audio"
            );
            (d, p)
        })
        .unwrap_or_default();
    let timers = serde_json::from_str::<serde_json::Value>(&created.response_body)
        .ok()
        .and_then(|v| {
            let t = super::meeting_timer::Timers::find(&v)?.clone();
            super::meeting_timer::Timers::from_state(&t, &Default::default())
        })
        .unwrap_or_default();
    let notes_organizer = serde_json::from_str::<serde_json::Value>(&created.response_body)
        .ok()
        .and_then(|v| {
            let mi = ["/meetingInfo", "/conversationResponse/meetingInfo"]
                .iter()
                .find_map(|p| v.pointer(p).cloned())?;
            let o = mi.get("organizerId")?.as_str()?.to_string();
            let t = mi.get("tenantId")?.as_str()?.to_string();
            (!o.is_empty() && !t.is_empty()).then(|| format!("{o}@{t}"))
        })
        .unwrap_or_default();
    let notes = {
        let mut n = super::meeting_notes::Notes::default();
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&created.response_body) {
            n.apply(&v);
            tracing::debug!(details = %super::meeting_notes::debug_summary(&v), "meeting join: notes states");
            tracing::info!(
                collab = v
                    .pointer("/conversationResponse/meetingDetails/collabDetails")
                    .or_else(|| v.pointer("/meetingDetails/collabDetails"))
                    .is_some(),
                notes = !n.resource_uri.is_empty(),
                "meeting join: notes"
            );
        }
        n
    };
    if meeting_join && let Some(i) = created.response_body.find("\"breakoutDetails\"") {
        let tail: String = created.response_body[i..].chars().take(1200).collect();
        tracing::debug!(details = %tail, "meeting join: breakout details");
    }
    let lobby_thread = group_chat_field(&created.response_body, "lobbyThreadId");
    tracing::debug!(?lobby_thread, "meeting lobby chat");
    let message_link = conversation_link(&created.response_body, "sendMessage");
    let endpoint_state = conversation_link(&created.response_body, "updateEndpointState")
        .map(|l| (l, std::sync::atomic::AtomicU64::new(0)));
    tracing::info!(has_invite = invite_url.is_some(), "meeting link");
    tracing::info!(
        has_controller = controller.is_some(),
        "conversation controller"
    );
    let properties_link = conversation_link(&created.response_body, "updateParticipantProperties");
    let role_link = conversation_link(&created.response_body, "updateParticipantRole");
    let settings_link = conversation_link(&created.response_body, "updateMeetingSettings");
    if meeting_join {
        let names: Vec<String> = serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| {
                v.pointer("/links")
                    .or_else(|| v.pointer("/conversationResponse/links"))
                    .and_then(|l| l.as_object())
                    .map(|o| o.keys().cloned().collect())
            })
            .unwrap_or_default();
        tracing::info!(?names, "conversation links");
    }
    let capability = serde_json::from_str::<serde_json::Value>(&created.response_body)
        .ok()
        .and_then(|v| super::meeting_options::meeting_capability(&v));
    tracing::info!(
        ?capability,
        has_settings = settings_link.is_some(),
        "meeting capability"
    );
    tracing::info!(members = members.len(), "group call members named");
    tracing::info!("call placed; waiting for the answer");
    // A town hall's attendee isn't answered: the roster puts our endpoint
    // in the meeting's stream (Teams' configureStreamingMode).
    let streaming_in = |json: &serde_json::Value| {
        super::live_stream::self_streaming(json, params.caller_mri, params.endpoint_id).map(
            |lobby| Acceptance {
                streaming: true,
                in_lobby: lobby,
                stream_roster: Some(json.clone()),
                ..Default::default()
            },
        )
    };
    let joined_streaming = meeting_join
        .then(|| serde_json::from_str::<serde_json::Value>(&created.response_body).ok())
        .flatten()
        .and_then(|v| streaming_in(&v));

    let wait_answer = async {
        if let Some(a) = joined_streaming {
            return Ok(a);
        }
        // An early mediaAnswer waits for the callAcceptance after it (its
        // links); if none comes within EARLY_ANSWER_GRACE it is the answer.
        let mut early: Option<Acceptance> = None;
        loop {
            let ev = tokio::select! {
                ev = events.recv() => ev,
                _ = tokio::time::sleep(EARLY_ANSWER_GRACE), if early.is_some() => {
                    tracing::info!("no acceptance after the early answer; taking it");
                    return Ok(early.take().expect("early answer"));
                }
            };
            let ev = match ev {
                Ok(ev) => ev,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(e) => bail!("Push channel closed: {e}"),
            };
            // Another call's events (the meeting we're moving out of, or
            // the main meeting held under a breakout room) aren't ours.
            if ev.kind != EventKind::Call || is_other_calls_event(&ev.json, &call_tag) {
                continue;
            }
            if meeting_join
                && ev.json.contains("rosterUpdate")
                && let Some(a) = serde_json::from_str::<serde_json::Value>(&ev.json)
                    .ok()
                    .and_then(|v| streaming_in(&v))
            {
                tracing::info!(
                    lobby = a.in_lobby,
                    "the meeting streams to us (a town hall's attendee): streaming mode"
                );
                return Ok(a);
            }
            match read_answer(&ev.json) {
                Some(Ok(a)) if a.provisional => {
                    tracing::info!("early media answer; waiting for the acceptance");
                    early.get_or_insert(a);
                }
                Some(Ok(a)) => return Ok(a),
                Some(Err(reason)) => match CallEnded::from_event(&ev.json) {
                    Some(end) => {
                        tracing::info!(code = end.code, sub_code = end.sub_code, phrase = %end.phrase, "the call ended before it was answered");
                        return Err(anyhow::Error::new(end));
                    }
                    None => bail!("{reason}"),
                },
                None => continue,
            }
        }
    };
    // Withdrawn before an answer: leave the conversation as Teams does, so
    // the callee stops ringing.
    let withdraw = |code: u16, reason: &'static str| {
        let (http, params, leave_url) = (&http, &params, leave_url.as_deref());
        async move {
            match leave_url {
                Some(url) => {
                    if let Err(e) = signaling::leave_conversation(http, url, params, code).await {
                        tracing::warn!("Withdrawing the call failed: {:#}", e);
                    }
                }
                None => tracing::warn!("No leave link; the callee may keep ringing"),
            }
            anyhow::anyhow!(reason)
        }
    };
    let acceptance = tokio::select! {
        answer = wait_answer => answer,
        _ = tokio::time::sleep(RING_TIMEOUT) => Err(withdraw(408, "No answer").await),
        _ = &mut cancel => Err(withdraw(487, "Call cancelled").await),
    };
    let acceptance = match acceptance {
        Ok(a) => a,
        Err(e) => {
            // The call request is out: its answer can still come after the
            // conversation ended or we withdrew, and would leave a call leg
            // behind. End any that does.
            end_late_leg(events, call_tag, http, skype_token);
            return Err(e);
        }
    };
    tracing::info!(in_lobby = acceptance.in_lobby, "callee answered");

    // Teams acknowledges a meeting call's acceptance in its Trouter reply
    // only (captured joins, preheated or not, POST nothing to the
    // acknowledgement link); OST's reply carries the same links (with this
    // call's tag). Other calls are acknowledged here too.
    if let Some(ack) = &acceptance.acknowledgement
        && !meeting_join
        && let Err(e) = signaling::acknowledge_call_acceptance(&http, ack, &params).await
    {
        tracing::warn!("Acceptance acknowledgement failed: {:#}", e);
    }
    // Teams posts nothing else to the call leg here (it is for keep-alives
    // and hang-up); a callback re-registration on it is not something the
    // web client does.

    super::incoming::debug_dump("sdp-call-offer", &offer);
    super::incoming::debug_dump("sdp-call-answer", &acceptance.sdp);
    // TASK-0342 research: the processor's choice for our camera
    // (X-H264UC is 122) when a meeting offer puts it first. Any other call
    // sends H.264.
    #[cfg(feature = "video")]
    {
        let native = meeting_media && super::webrtc_audio::native_send();
        let pt = native
            .then(|| {
                super::webrtc_audio::answered_pt(&acceptance.sdp, super::meeting_media::CAMERA_MID)
            })
            .flatten();
        if native {
            tracing::info!(camera_pt = ?pt, "native send: the processor's answer");
        }
        super::webrtc_video::set_native_camera(pt == Some(super::webrtc_audio::PT_X_H264UC));
    }
    let parsed = if acceptance.streaming {
        None
    } else {
        WebRtcOffer::parse(&acceptance.sdp)
    };
    let media = match parsed {
        None if acceptance.streaming => None,
        Some(answer) => match WebRtcAudioSession::start_as_offerer(local, answer.clone()).await {
            Ok(m) => {
                m.set_local_sdp(&offer);
                // Preheated: Teams' call is muted with its speaker off
                // until Join now.
                if preheat {
                    m.set_held(true);
                }
                // We asked for E2EE and the callee's answer said yes.
                m.set_e2ee(
                    answer.e2ee
                        && offer
                            .lines()
                            .any(|l| l.trim_end() == super::webrtc_audio::E2EE_ATTRIBUTE),
                );
                Some(m)
            }
            Err(e) => {
                tracing::warn!("WebRTC audio failed: {:#}", e);
                None
            }
        },
        None => {
            tracing::warn!("Callee answered without DTLS-SRTP; no audio");
            None
        }
    };

    Ok(OutgoingCall {
        media_descriptions: acceptance
            .media_descriptions
            .clone()
            .filter(|_| meeting_media)
            .map(|l| (l, std::sync::atomic::AtomicU64::new(1))),
        joined_roster: super::roster::joined(&created.response_body),
        call_id: chain_id.clone(),
        call_tag: call_tag.clone(),
        tags: MediaTags::default(),
        http,
        skype_token,
        end_url: acceptance.end,
        call_leg: acceptance.call_leg,
        media,
        me: (
            serde_json::json!({
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US",
            }),
            signaling::trouter_callback(
                params.trouter_surl,
                params.endpoint_id,
                "call/mediaAcknowledgement/",
            ),
        ),
        callbacks: (
            params.trouter_surl.to_string(),
            params.endpoint_id.to_string(),
        ),
        hold_link: acceptance.hold,
        resume_link: None,
        transfer_link: acceptance.transfer,
        replace_link: acceptance.replace,
        answered_by: acceptance.answered_by,
        renegotiation_link: acceptance
            .renegotiation
            .filter(|l| super::incoming::is_service_link(l)),
        remote_legs: std::collections::HashMap::new(),
        state_links,
        hand: None,
        sign_state_id: None,
        state_seq: 0,
        all_participants,
        admit_links,
        remove_link,
        properties_link,
        role_link,
        settings_link,
        group_links: (
            conversation_link(&created.response_body, "joinMeetingGroup"),
            conversation_link(&created.response_body, "leaveMeetingGroup"),
        ),
        interpretation: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| super::ai_interpreter::meeting_state(&v))
            .unwrap_or_default(),
        capability: capability.unwrap_or_default(),
        recorder: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .map(|v| super::recorder::Tracker::from_join(&v))
            .unwrap_or_default(),
        meet_now: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .is_ok_and(|v| super::meeting_options::is_meet_now(&v)),
        ai_indicator: serde_json::from_str::<serde_json::Value>(&created.response_body).is_ok_and(
            |v| {
                let shown = super::meeting_options::shows_ai_indicator(&v);
                tracing::info!(
                    shown,
                    kind = v
                        .pointer("/meetingDetails/meetingType")
                        .and_then(|t| t.as_str())
                        .unwrap_or(""),
                    channel = v
                        .pointer("/meetingDetails/isChannelMeeting")
                        .and_then(|t| t.as_bool())
                        .unwrap_or(false),
                    private = v
                        .pointer("/meetingDetails/isPrivateMeeting")
                        .and_then(|t| t.as_bool())
                        .unwrap_or(false),
                    "AI indicator"
                );
                shown
            },
        ),
        meeting_info: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| {
                let keys: Vec<String> = ["/meetingDetails", "/conversationResponse/meetingDetails"]
                    .iter()
                    .find_map(|p| v.pointer(p).and_then(|d| d.as_object()))
                    .map(|o| o.keys().cloned().collect())
                    .unwrap_or_default();
                super::meeting_info::from_join_response(&v).inspect(|i| {
                    tracing::info!(
                        subject = !i.title.is_empty(),
                        instance_subject = !i.instance_subject.is_empty(),
                        ?keys,
                        "meeting info from the join"
                    )
                })
            }),
        artifacts_link: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| super::transcript::artifacts_link(&v)),
        controller,
        invite_url,
        mute_link,
        metadata_link,
        add_participant_link,
        meeting_states_link,
        event: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| super::live_event::live_event(&v))
            .unwrap_or_default(),
        live_state_link: conversation_link(&created.response_body, "updateMeetingLiveState"),
        layout_link: conversation_link(&created.response_body, "setMeetingLayout"),
        layout_seq: 0,
        add_modality_link,
        content_link,
        my_content: None,
        joined_content: Default::default(),
        dial_in,
        phone_audio,
        call_me: None,
        room_pending: None,
        invited: Vec::new(),
        group_message_id,
        timers,
        notes,
        notes_organizer,
        // Joined by the meeting's ID: its chat as the join names it (in
        // the lobby, not until we're let in).
        thread_id: if thread_id.is_empty() {
            group_chat_field(&created.response_body, "threadId")
                .filter(|t| t.starts_with("19:"))
                .unwrap_or_default()
        } else {
            thread_id.to_string()
        },
        unmute_link,
        lobby_thread,
        server_muted: std::sync::atomic::AtomicBool::new(false),
        message_link,
        endpoint_state,
        in_lobby: {
            let held = endpoint_in_lobby(&created.response_body, params.endpoint_id);
            tracing::info!(
                held,
                acceptance_without_modalities = acceptance.in_lobby,
                "lobby check"
            );
            held
        },
        meeting_started: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| {
                [
                    "/state/isMeetingActivated",
                    "/conversationResponse/state/isMeetingActivated",
                ]
                .iter()
                .find_map(|p| v.pointer(p).and_then(|b| b.as_bool()))
            })
            .unwrap_or(true),
        leave_link: leave_url.clone(),
        streaming: acceptance.streaming,
        stream: acceptance
            .stream_roster
            .clone()
            .or_else(|| serde_json::from_str::<serde_json::Value>(&created.response_body).ok())
            .and_then(|v| super::live_stream::streams(&v, params.caller_mri))
            .map(|all| super::live_stream::choose_as_teams(&all)),
        preheated: preheat,
        joined_details: serde_json::from_str::<serde_json::Value>(&created.response_body)
            .ok()
            .and_then(|v| {
                ["/meetingDetails", "/conversationResponse/meetingDetails"]
                    .iter()
                    .find_map(|p| v.pointer(p).cloned())
            })
            .map(|d| serde_json::json!({ "meetingDetails": d })),
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn room_invitation_as_teams_sends_it() {
        let b = room_invite_body(
            &serde_json::json!({"id": "8:orgid:me"}),
            "8:orgid:room",
            "OST Test Room",
            "19:meeting_x@thread.v2",
            Some("0"),
            Some(0x1234),
            false,
            Some(("o".into(), "t".into())),
            serde_json::json!({}),
        );
        assert_eq!(b["participants"]["to"][0]["id"], "8:orgid:room");
        let i = &b["participantInvitationData"]["invitationData"];
        assert_eq!(
            (i["proximitySource"].as_i64(), i["deviceType"].as_str()),
            (Some(1), Some("computer"))
        );
        assert_eq!(i["autoAcceptAuthorization"]["token"], 0x1234);
        assert_eq!(i["meetingInfo"]["tenantId"], "t");
        let b = room_invite_body(
            &serde_json::json!({}),
            "8:orgid:room",
            "",
            "19:x",
            None,
            None,
            true,
            None,
            serde_json::json!({}),
        );
        assert!(
            b["participantInvitationData"]["invitationData"]["autoAcceptAuthorization"].is_null()
        );
        assert_eq!(
            b["participantInvitationData"]["invitationData"]["proximitySource"],
            2
        );
    }

    use super::*;

    #[test]
    fn merge_requests_are_teams() {
        let from = serde_json::json!({ "id": "8:orgid:a", "participantId": "p-a" });
        let people = [
            MergePerson {
                id: "8:orgid:b".into(),
                participant_id: "new-b".into(),
                display_name: Some("B".into()),
                replacement: Some(
                    serde_json::json!({ "replaces": "https://cc/leg-b/replacement", "replacementTargetParticipantId": "leg-b" }),
                ),
            },
            MergePerson {
                id: "8:orgid:c".into(),
                participant_id: "new-c".into(),
                display_name: None,
                replacement: None,
            },
        ];
        let b = merge_body(&from, "19:x@thread.v2", &people, |p| format!("cb/{p}"));
        assert_eq!(
            b["groupChat"],
            serde_json::json!({ "threadId": "19:x@thread.v2", "messageId": null })
        );
        assert!(b["groupContext"].is_null());
        assert_eq!(b["participants"]["from"], from);
        assert_eq!(
            b["participants"]["to"][0]["replacementDetails"]["replaces"],
            "https://cc/leg-b/replacement"
        );
        assert_eq!(b["participants"]["to"][0]["participantId"], "new-b");
        assert!(
            b["participants"]["to"][1]
                .get("replacementDetails")
                .is_none()
        );
        assert_eq!(
            b["links"]["addParticipantSuccess"],
            "cb/conversation/addParticipantSuccess/"
        );
        // The leg comes from the roster's endpoint call links.
        let p = serde_json::json!({ "id": "8:orgid:b", "endpointDetails": [{ "participantId": "leg-b", "callLinks": { "replacement": "https://cc/leg-b/replacement" } }] });
        assert_eq!(leg_replacement(&p), people[0].replacement);
        assert_eq!(
            leg_replacement(&serde_json::json!({ "endpointDetails": [{ "participantId": "x" }] })),
            None
        );
    }

    #[test]
    fn invitations_are_teams() {
        // Teams on the web inviting OST Test 2 into a 1:1 call from the
        // People pane (2026-11-26), less the ids.
        let from = serde_json::json!({ "id": "8:orgid:a", "displayName": "A", "endpointId": "e", "participantId": "p", "languageId": "en-us" });
        let b = invite_body(
            &from,
            "19:abc@thread.v2",
            &[("8:orgid:b".into(), "pid-b".into())],
            |p| format!("cb/{p}"),
        );
        assert_eq!(
            b,
            serde_json::json!({
                "disableUnmute": false,
                "participants": { "from": from, "to": [{ "id": "8:orgid:b", "participantId": "pid-b" }] },
                "participantInvitationData": {},
                "replacementDetails": null,
                "groupContext": null,
                "groupChat": { "threadId": "19:abc@thread.v2", "messageId": null },
                "links": {
                    "addParticipantSuccess": "cb/conversation/addParticipantSuccess/",
                    "addParticipantFailure": "cb/conversation/addParticipantFailure/"
                }
            })
        );
    }

    #[test]
    fn roster_legs_read_each_persons_merge_leg() {
        // A roster event keys endpoints by id (measured); the leg is the
        // endpoint's participantId + callLinks.replacement.
        let ev = serde_json::json!({
            "callAgentPath": "conversation/rosterUpdate/",
            "body": { "participants": {
                "8:orgid:B": { "details": {}, "endpoints": {
                    "ep1": { "participantId": "leg-b", "callLinks": { "replacement": "https://cc/leg-b/replacement" } }
                } },
                "8:orgid:C": { "details": {}, "endpoints": { "ep2": { "participantId": "leg-c" } } }
            } }
        });
        let legs: std::collections::HashMap<_, _> =
            roster_legs(&ev.to_string()).into_iter().collect();
        assert_eq!(
            legs["8:orgid:b"],
            serde_json::json!({ "replaces": "https://cc/leg-b/replacement", "replacementTargetParticipantId": "leg-b" })
        );
        assert!(!legs.contains_key("8:orgid:c"));
        // Not a roster event.
        assert!(roster_legs(r#"{"callAgentPath":"call/end/","body":{}}"#).is_empty());
    }

    #[test]
    fn one_to_one_chats_sort_the_two_ids() {
        let a = "9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5";
        let b = "4287e791-1b98-4963-8b94-281c50472683";
        let want = format!("19:{b}_{a}@unq.gbl.spaces");
        assert_eq!(one_to_one_chat_id(a, b).as_deref(), Some(want.as_str()));
        assert_eq!(one_to_one_chat_id(b, a).as_deref(), Some(want.as_str()));
        assert_eq!(callee_mri_for_chat(&want, a), Some(format!("8:orgid:{b}")));
        assert_eq!(one_to_one_chat_id(a, a), None);
        assert_eq!(one_to_one_chat_id(a, "nope"), None);
    }

    /// A breakout room joined before it opened ends the conversation with
    /// 403 / 5745 (Teams' NotAllowedToJoinBreakoutRoom); other ends keep
    /// their message.
    #[test]
    fn call_ended_reads_the_end() {
        let room = r#"{"callAgentPath":"conversation/conversationEnd/","callTag":"0f3a9b2c4d5e","body":{"code":403,"subCode":5745,"phrase":"Conversation ending after breakout room is not open."}}"#;
        let end = CallEnded::from_event(room).expect("an end");
        assert_eq!((end.code, end.sub_code), (403, 5745));
        assert!(end.not_allowed_in_breakout_room());
        assert_eq!(
            end.to_string(),
            "Conversation ending after breakout room is not open. (403)"
        );
        let denied = r#"{"callAgentPath":"call/end/","body":{"callEnd":{"code":0,"subCode":5854,"phrase":"DeniedInLobby"}}}"#;
        let end = CallEnded::from_event(denied).expect("an end");
        assert_eq!((end.code, end.sub_code), (0, 5854));
        assert!(!end.not_allowed_in_breakout_room());
        assert!(
            CallEnded::from_event(r#"{"callAgentPath":"call/acceptance/","body":{}}"#).is_none()
        );
        // An error made from it still reads as before and can be told apart.
        let e = anyhow::Error::new(CallEnded::from_event(room).unwrap());
        assert!(
            e.downcast_ref::<CallEnded>()
                .is_some_and(CallEnded::not_allowed_in_breakout_room)
        );
    }

    /// A call's answer is only ever taken from its own callbacks: the
    /// meeting we're moving out of (or the held main meeting) has its own
    /// tag; untagged events (invitations) stay anyone's.
    #[test]
    fn events_of_other_calls() {
        let ours = r#"{"callAgentPath":"call/acceptance/","callTag":"aaaaaaaaaaaa","body":{}}"#;
        let theirs = r#"{"callAgentPath":"conversation/conversationEnd/","callTag":"bbbbbbbbbbbb","body":{"code":0}}"#;
        let untagged = r#"{"callAgentPath":"call/end/","body":{}}"#;
        assert_eq!(event_call_tag(ours).as_deref(), Some("aaaaaaaaaaaa"));
        assert!(!is_other_calls_event(ours, "aaaaaaaaaaaa"));
        assert!(is_other_calls_event(theirs, "aaaaaaaaaaaa"));
        assert!(!is_other_calls_event(untagged, "aaaaaaaaaaaa"));
        let tag = new_call_tag();
        assert_eq!(tag.len(), 12);
        assert!(tag.chars().all(|c| c.is_ascii_hexdigit()));
    }

    /// Shapes from a Teams web guest held in the test meeting's lobby
    /// (2026-11-08): the media processor accepts with no call modalities;
    /// admission is a conversation update carrying the call modality.
    #[test]
    fn lobby_acceptance_and_admission() {
        let lobby = r#"{"callAgentPath":"call/acceptance/","body":{"callAcceptance":{"acceptedCallModalities":[],"links":{"acknowledgement":"https://cc.skype.com/ack"},"mediaContent":{"contentType":"application/sdp-ngc-1.0","blob":"v=0"}}}}"#;
        let a = read_answer(lobby).expect("answer").expect("accepted");
        assert!(a.in_lobby);
        let joined = lobby.replace(
            r#""acceptedCallModalities":[]"#,
            r#""acceptedCallModalities":["Audio"]"#,
        );
        assert!(
            !read_answer(&joined)
                .expect("answer")
                .expect("accepted")
                .in_lobby
        );
        let admitted = r#"{"callAgentPath":"conversation/conversationUpdate/","body":{"activeModalities":{"call":{"links":{}},"lobby":null},"links":{"mute":"https://conv.skype.com/mute","admit":"https://conv.skype.com/admit"}}}"#;
        let body = lobby_admission(admitted).expect("admission");
        assert_eq!(
            conversation_link(&body.to_string(), "mute").as_deref(),
            Some("https://conv.skype.com/mute")
        );
        let roster = r#"{"roster":{"participants":{"8:teamsvisitor:x":{"endpoints":{"ep1":{"lobby":{}}}},"8:orgid:y":{"endpoints":{"ep2":{"call":{}}}}}}}"#;
        assert!(endpoint_in_lobby(roster, "ep1"));
        assert!(!endpoint_in_lobby(roster, "ep2"));
        assert!(!endpoint_in_lobby(roster, "ep3"));
        let still_waiting = r#"{"callAgentPath":"conversation/conversationUpdate/","body":{"activeModalities":null}}"#;
        assert!(lobby_admission(still_waiting).is_none());
        assert!(lobby_admission(r#"{"callAgentPath":"conversation/rosterUpdate/","body":{"activeModalities":{"call":{}}}}"#).is_none());
    }

    #[test]
    fn lobby_replies_mark_screened_guests() {
        // As the meeting's getAllParticipants (scope "lobby") answered.
        let reply = serde_json::json!({ "participants": [
            { "displayName": "OST Guest 1", "id": "8:teamsvisitor:8fec5b863b244e208df046cb684e190e",
              "participantScreening": { "detectedAt": "2026-11-08T01:29:46.0294623Z", "isBot": true, "source": "JoinShield" } },
            { "displayName": "Ada", "id": "8:teamsvisitor:aa" },
            { "displayName": "Bea", "id": "8:orgid:bb", "participantScreening": { "isBot": true } },
        ]});
        let people = lobby_people(&reply);
        assert_eq!(people.len(), 3);
        assert!(people[0].suspected);
        assert_eq!(people[0].name, "OST Guest 1");
        assert!(!people[1].suspected);
        // Only anonymous guests are screened.
        assert!(!people[2].suspected);
    }

    /// Teams' preheated join and its Cancel (Teams on the web, 2026-11-16).
    #[test]
    fn preheated_join_and_leave_bodies() {
        let me = serde_json::json!({ "id": "8:orgid:me", "displayName": "Me", "endpointId": "e", "participantId": "p", "languageId": "en-us" });
        assert_eq!(
            preheat_join_body(&me, false, 1),
            serde_json::json!({ "from": me, "endpointState": { "endpointStateSequenceNumber": 1, "endpointProperties": { "preheatProperties": 0 } } })
        );
        assert_eq!(
            preheat_join_body(&me, true, 1)["endpointState"]["state"],
            serde_json::json!({ "isMuted": true })
        );
        let leave = leave_body(&me);
        assert_eq!(leave["participants"]["from"], me);
        assert_eq!(
            leave["conversationTransactionEnd"]["phrase"],
            "ConversationEndNoModalityConnected"
        );
        assert_eq!(
            leave["callTransactionEnd"]["phrase"],
            "CallEndReasonLocalUserInitiated"
        );
    }

    #[test]
    fn reactions_go_to_everyone() {
        let me = serde_json::json!({ "id": "8:orgid:me", "displayName": "Me", "endpointId": "e", "participantId": "p" });
        let body = reaction_body(&me, "heart", "op", "r");
        let m = &body["messageContent"][0];
        assert_eq!(m["type"], "Reaction");
        assert_eq!(m["scope"], "all");
        assert_eq!(m["payload"]["values"][0]["name"], "heart");
        assert_eq!(body["from"]["id"], "8:orgid:me");
    }

    #[test]
    fn endpoint_state_says_whether_we_are_muted() {
        let from = serde_json::json!({"id": "8:orgid:me", "displayName": "OST Test 1"});
        let b = endpoint_state_body(&from, true, 3);
        assert_eq!(b["from"]["id"], "8:orgid:me");
        assert_eq!(b["endpointState"]["state"]["isMuted"], true);
        assert_eq!(b["endpointState"]["endpointStateSequenceNumber"], 3);
    }

    #[test]
    fn media_descriptions_say_what_the_lines_do() {
        let b = media_descriptions_body(true, false, None, 2, ("1", "11"));
        let d = &b["UpdateMediaDescriptions"]["mediaDescriptions"];
        assert_eq!(d["requestId"], 2);
        assert_eq!(
            d["descriptions"],
            serde_json::json!([
                {"mid": "1", "direction": "sendrecv", "label": "main-video"},
                {"mid": "11", "direction": "recvonly"}
            ])
        );
        assert!(d.get("negotiationTag").is_none());
        // A share is "sendonly", tagged as Teams tags it.
        let s = media_descriptions_body(false, true, Some("f74ff03b;ss_2"), 3, ("1", "11"));
        let d = &s["UpdateMediaDescriptions"]["mediaDescriptions"];
        assert_eq!(
            d["descriptions"],
            serde_json::json!([
                {"mid": "1", "direction": "recvonly"},
                {"mid": "11", "direction": "sendonly", "label": "applicationsharing-video"}
            ])
        );
        assert_eq!(d["negotiationTag"], "f74ff03b;ss_2");
    }

    #[test]
    fn the_camera_and_each_share_are_tagged_as_teams_tags_them() {
        let t = MediaTags::default();
        assert_eq!(t.tag("c", false, false), None);
        // Camera on: v_1, and again while it stays on.
        assert_eq!(t.tag("c", true, false).as_deref(), Some("c;v_1"));
        assert_eq!(t.tag("c", true, false).as_deref(), Some("c;v_1"));
        // A share starts: ss_1, kept while it goes on.
        assert_eq!(t.tag("c", true, true).as_deref(), Some("c;ss_1"));
        assert_eq!(t.tag("c", true, true).as_deref(), Some("c;ss_1"));
        // Camera off and on during the share: v_2 for that change.
        assert_eq!(t.tag("c", false, true).as_deref(), Some("c;ss_1"));
        assert_eq!(t.tag("c", true, true).as_deref(), Some("c;v_2"));
        // The share stops; the next one is ss_2. The camera off and on
        // again is v_3.
        assert_eq!(t.tag("c", true, false).as_deref(), Some("c;v_2"));
        assert_eq!(t.tag("c", true, true).as_deref(), Some("c;ss_2"));
        assert_eq!(t.tag("c", false, false), None);
        assert_eq!(t.tag("c", true, false).as_deref(), Some("c;v_3"));
    }

    #[test]
    fn mute_all_names_everyone_else() {
        let me = serde_json::json!({ "id": "8:orgid:me", "displayName": "Me", "endpointId": "e",
            "participantId": "p", "languageId": "en-US" });
        let cb = mute_callback("https://t.example/x1/", "ep", "op1");
        assert_eq!(
            cb,
            "https://t.example/x1/callAgent/ep/op1/conversation/muteUnmuteAsync/"
        );
        let body = mute_body(&me, "all", &[], &cb, "op1");
        assert_eq!(body["scope"], "all");
        assert_eq!(body["muteParticipants"], serde_json::json!([]));
        assert_eq!(body["mediaTypes"], serde_json::json!(["audio"]));
        assert_eq!(body["from"], me);
        assert_eq!(body["links"]["clientCallback"], cb);
        assert_eq!(body["operationId"], "op1");
    }

    #[test]
    fn mute_participant_names_them_as_objects() {
        let me = serde_json::json!({ "id": "8:orgid:me", "displayName": "Me", "endpointId": "e",
            "participantId": "p", "languageId": "en-US", "extra": 1 });
        let body = mute_body(&me, "specified", &["8:orgid:them"], "cb", "op");
        assert_eq!(body["scope"], "specified");
        assert_eq!(
            body["muteParticipants"],
            serde_json::json!([{ "id": "8:orgid:them" }])
        );
        assert!(body["from"].get("extra").is_none());
        assert_eq!(body["from"]["participantId"], "p");
    }

    #[test]
    fn mute_reply_names_who_was_muted() {
        let reply = serde_json::json!({ "muteUnmuteResponse": {
            "8:orgid:A": [{ "participantId": "1", "reason": "success", "serverMuteVersion": 2 }],
            "8:orgid:b": [{ "participantId": "2", "reason": "success", "serverMuteVersion": 2 },
                          { "participantId": "3", "reason": "notSupported", "serverMuteVersion": 0 }],
            "8:orgid:c": [] } });
        assert_eq!(muted_by_reply(&reply), vec!["8:orgid:a".to_string()]);
        assert!(muted_by_reply(&serde_json::Value::Null).is_empty());
        // The async operation's reply is empty; its result comes to the
        // callback.
        assert!(muted_by_reply(&serde_json::json!({ "muteUnmuteResponse": {} })).is_empty());
        let event = serde_json::json!({ "callAgentPath": "conversation/muteUnmuteAsync/",
            "body": { "operationId": "op", "muteUnmuteResponseAsync": {
                "8:teamsvisitor:g": [{ "participantId": "1", "reason": "success", "serverMuteVersion": 3 }] } } });
        assert_eq!(
            muted_by_async_result(&event.to_string()),
            Some(vec!["8:teamsvisitor:g".to_string()])
        );
        assert_eq!(
            muted_by_async_result(r#"{"callAgentPath":"call/end/","body":{}}"#),
            None
        );
    }

    #[test]
    fn not_bot_update_clears_the_screening() {
        let body = not_bot_body(
            serde_json::json!({ "id": "8:orgid:me" }),
            "8:teamsvisitor:x",
            "op",
            "now",
            "cb",
        );
        let bag = &body["to"][0]["propertyBag"]["participantScreening"];
        assert_eq!(bag["value"]["isBot"], false);
        assert_eq!(bag["value"]["markedBy"], "admitter");
        assert_eq!(bag["sequenceNumber"], 1);
        assert_eq!(body["links"]["updateParticipantPropertiesStatus"], "cb");
    }

    #[test]
    fn callee_is_the_other_member_of_a_1to1_chat() {
        let chat = "19:aaaa-1_bbbb-2@unq.gbl.spaces";
        assert_eq!(
            callee_mri_for_chat(chat, "aaaa-1").as_deref(),
            Some("8:orgid:bbbb-2")
        );
        assert_eq!(
            callee_mri_for_chat(chat, "bbbb-2").as_deref(),
            Some("8:orgid:aaaa-1")
        );
        assert!(callee_mri_for_chat(chat, "cccc").is_none());
        assert!(callee_mri_for_chat("19:x@thread.v2", "aaaa-1").is_none());
    }

    #[test]
    fn group_chats_are_told_apart() {
        assert!(is_group_chat("19:abc@thread.v2"));
        assert!(!is_group_chat("19:meeting_abc@thread.v2"));
        assert!(!is_group_chat("19:abc@thread.tacv2"));
        assert!(!is_group_chat("19:a_b@unq.gbl.spaces"));
    }

    #[test]
    fn meeting_links_name_the_thread_and_message() {
        let url = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_YTQyMzZlY2ItMDdjNC00MzIzLTg0NTYtMDA1YzA4YjY3MmUy%40thread.v2/0?context=%7b%22Tid%22%3a%22t%22%7d";
        let m = MeetingLink::parse(url).unwrap();
        assert_eq!(
            m.thread_id,
            "19:meeting_YTQyMzZlY2ItMDdjNC00MzIzLTg0NTYtMDA1YzA4YjY3MmUy@thread.v2"
        );
        assert_eq!(m.message_id, "0");
        // "t" isn't a GUID: no organizer or tenant, so no options page.
        assert!(m.tenant_id.is_none() && m.options_url().is_none());
        let full = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_YTQy%40thread.v2/0?context=%7b%22Tid%22%3a%222716d134-5614-4856-a48d-2002edd9a570%22%2c%22Oid%22%3a%224287e791-1b98-4963-8b94-281c50472683%22%7d";
        let f = MeetingLink::parse(full).unwrap();
        assert_eq!(
            f.organizer_id.as_deref(),
            Some("4287e791-1b98-4963-8b94-281c50472683")
        );
        assert_eq!(
            f.options_url().unwrap(),
            "https://teams.microsoft.com/meetingOptions/?organizerId=4287e791-1b98-4963-8b94-281c50472683&tenantId=2716d134-5614-4856-a48d-2002edd9a570&threadId=19%3Ameeting_YTQy%40thread.v2&messageId=0&language=en-US"
        );
        assert!(
            MeetingLink::parse("https://evil.example/l/meetup-join/19%3ameeting_x%40thread.v2/0")
                .is_none()
        );
        assert!(
            MeetingLink::parse(
                "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%22%40thread.v2/0"
            )
            .is_none()
        );
        assert!(
            MeetingLink::parse(
                "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/abc"
            )
            .is_none()
        );
        assert!(MeetingLink::parse("https://teams.microsoft.com/meet/299487569045?p=x").is_none());
        // A channel meeting: the channel's thread and the meeting post.
        let c = MeetingLink::parse("https://teams.microsoft.com/l/meetup-join/19%3aekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1%40thread.tacv2/1794372973956?context=%7b%22Tid%22%3a%222716d134-5614-4856-a48d-2002edd9a570%22%2c%22Oid%22%3a%224287e791-1b98-4963-8b94-281c50472683%22%7d").unwrap();
        assert_eq!(
            c.thread_id,
            "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2"
        );
        assert_eq!(c.message_id, "1794372973956");
        assert!(
            MeetingLink::parse("https://teams.microsoft.com/l/meetup-join/19%3a%40thread.tacv2/1")
                .is_none()
        );
    }

    #[test]
    fn a_short_link_is_a_meeting_known_by_its_id() {
        let s =
            MeetingLink::parse_join("https://teams.microsoft.com/meet/280904668281902?p=FQ9mZD%3D")
                .unwrap();
        assert!(s.thread_id.is_empty());
        assert_eq!(s.message_id, "0");
        assert_eq!(
            s.meeting_data,
            Some(serde_json::json!({
                "meetingCode": "280904668281902",
                "passcode": "FQ9mZD=",
                "meetingUrl": "https://teams.microsoft.com/meet/280904668281902?p=FQ9mZD=",
            }))
        );
        // No passcode: null, as Teams sends it.
        let n = MeetingLink::parse_short("https://teams.microsoft.com/meet/123").unwrap();
        assert_eq!(n.meeting_data.unwrap()["passcode"], serde_json::Value::Null);
        assert!(MeetingLink::parse_short("https://teams.microsoft.com/meet/12a3?p=x").is_none());
        assert!(MeetingLink::parse_short("https://evil.example/meet/123?p=x").is_none());
        // A full link still parses as one, with no meetingData.
        let full = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_YTQy%40thread.v2/0";
        assert_eq!(MeetingLink::parse_join(full).unwrap().meeting_data, None);
    }

    #[test]
    fn reads_acceptance_and_rejection() {
        let ok = r#"{"callAgentPath":"call/acceptance/","body":{"callAcceptance":{"mediaContent":{"blob":"v=0"},"links":{"acknowledgement":"https://a","callLeg":"https://leg"}}}}"#;
        let a = read_answer(ok).unwrap().unwrap();
        assert_eq!(a.sdp, "v=0");
        assert_eq!(a.call_leg.as_deref(), Some("https://leg"));
        let end =
            r#"{"callAgentPath":"call/end/","body":{"callEnd":{"code":603,"phrase":"Declined"}}}"#;
        assert_eq!(read_answer(end).unwrap().err().unwrap(), "Declined (603)");
        assert!(read_answer(r#"{"callAgentPath":"call/progress/","body":{}}"#).is_none());
        // An early mediaAnswer is provisional; the acceptance carries the
        // call's links (callLeg, replacement) and who answered.
        let early = r#"{"callAgentPath":"call/mediaAnswer/","body":{"mediaAnswer":{"mediaContent":{"blob":"v=0"},"links":{"mediaAcknowledgement":"https://m"}}}}"#;
        assert!(read_answer(early).unwrap().unwrap().provisional);
        let accepted = r#"{"callAgentPath":"call/acceptance/","body":{"callAcceptance":{"acceptedBy":{"displayName":"OST Test 3"},"mediaContent":{"blob":"v=0"},"links":{"callLeg":"https://leg","replacement":"https://r"}}}}"#;
        let a = read_answer(accepted).unwrap().unwrap();
        assert!(!a.provisional);
        assert_eq!(a.replace.as_deref(), Some("https://r"));
        assert_eq!(a.answered_by.as_deref(), Some("OST Test 3"));
    }

    #[test]
    fn a_retarget_gives_the_new_leg() {
        // Admitted from a meeting's lobby (OST Test 2, 2026-11-11): the
        // lobby call's leg moves to the meeting's call hub.
        let moved = r#"{"body":{"debugContent":{},"links":{"callLeg":"https://cc/v1/active/89306a7a/204715502/a4/","hold":"https://cc/v1/active/89306a7a/204715502/a4/hold","transfer":"https://cc/v1/active/89306a7a/204715502/a4/transfer","mediaRenegotiation":"https://cc/v1/active/89306a7a/204715502/a4/renegotiate","updateMediaDescriptions":"https://cc/v1/active/89306a7a/204715502/a4/updateMediaDescriptions"},"mediaAcknowledgement":{"code":0,"phrase":"Participant retarget was successful.","reason":"noError"}},"callAgentPath":"call/mediaAcknowledgement/"}"#;
        let links = leg_retarget(moved).unwrap();
        assert_eq!(
            links.call_leg,
            "https://cc/v1/active/89306a7a/204715502/a4/"
        );
        assert!(links.hold.unwrap().ends_with("/hold"));
        // A plain acknowledgement moves nothing.
        let ack = r#"{"body":{"debugContent":{},"links":{"callLeg":null},"mediaAcknowledgement":{"code":0,"phrase":"Success"}},"callAgentPath":"call/mediaAcknowledgement/"}"#;
        assert!(leg_retarget(ack).is_none());
        assert!(
            leg_retarget(
                r#"{"callAgentPath":"call/acceptance/","body":{"links":{"callLeg":"x"}}}"#
            )
            .is_none()
        );
    }

    #[test]
    fn finds_the_leave_link() {
        assert_eq!(
            leave_link(r#"{"links":{"leave":"https://conv/leave"}}"#).as_deref(),
            Some("https://conv/leave")
        );
        assert!(leave_link(r#"{"links":{}}"#).is_none());
    }
}
