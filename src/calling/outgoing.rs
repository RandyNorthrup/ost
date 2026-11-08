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
    /// Where our own re-offers go (`links.mediaRenegotiation`).
    renegotiation_link: Option<String>,
    /// Meetings: the conversation's publishState / removeState links
    /// (Raise hand), and the id of our raised hand.
    state_links: (Option<String>, Option<String>),
    hand: Option<String>,
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

    pub fn is_muted(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_muted())
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
            &chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
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
    pub fn note_hand(&mut self, id: Option<String>) {
        if self.hand.is_none() {
            self.hand = id;
        }
    }

    /// Transfer the call to `target` (an `8:orgid:` MRI).
    pub async fn transfer(&self, target: &str) -> Result<()> {
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
        )
        .await
    }

    /// Put the call on hold, or resume it (our media only).
    pub fn set_held(&self, held: bool) {
        if let Some(m) = &self.media {
            m.set_held(held);
        }
    }

    pub fn can_dtmf(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.can_dtmf())
    }

    /// The call negotiated video we can send (camera button usable).
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
    pub fn is_sharing(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.is_sharing())
    }

    /// Whether our shared screen went away by itself.
    pub fn share_ended(&self) -> bool {
        self.media.as_ref().is_some_and(|m| m.share_ended())
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
        super::incoming::answer_renegotiation(
            &self.http,
            &self.skype_token,
            &mut self.media,
            Some(self.me.clone()),
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

    /// Stop media and end the call for both sides.
    pub async fn hang_up(mut self) -> Result<()> {
        self.media = None;
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
    Some(format!("8:orgid:{other}"))
}

/// POST JSON to a Teams service link; the JSON reply (Null when empty).
async fn cc_post(
    http: &reqwest::Client,
    skype_token: &str,
    url: &str,
    body: &serde_json::Value,
    what: &str,
) -> Result<serde_json::Value> {
    if !super::incoming::is_service_link(url) {
        bail!("{what}: not a Teams service link");
    }
    let resp = http
        .post(url)
        .header("X-Skypetoken", skype_token)
        .json(body)
        .send()
        .await
        .with_context(|| format!("{what} failed to send"))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        tracing::info!(
            "{what}: HTTP {status}: {}",
            text.chars().take(300).collect::<String>()
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

/// The conversation's `leave` link from the create response.
fn leave_link(create_response: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(create_response).ok()?;
    v.pointer("/links/leave")
        .or_else(|| v.pointer("/conversationResponse/links/leave"))
        .and_then(|u| u.as_str())
        .map(str::to_string)
}

/// What the callee's answer told us.
struct Acceptance {
    sdp: String,
    acknowledgement: Option<String>,
    call_leg: Option<String>,
    hold: Option<String>,
    transfer: Option<String>,
    /// Where our re-offers go (screen sharing).
    renegotiation: Option<String>,
    end: Option<String>,
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
        renegotiation: link("mediaRenegotiation"),
        end: link("end"),
    }))
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
}

impl MeetingLink {
    pub fn parse(url: &str) -> Option<Self> {
        let rest = url
            .strip_prefix("https://teams.microsoft.com/l/meetup-join/")
            .or_else(|| url.strip_prefix("https://teams.live.com/l/meetup-join/"))?;
        let path = rest.split(['?', '#']).next()?;
        let (thread, message) = path.split_once('/')?;
        let thread = percent_decode(thread)?;
        let message = percent_decode(message.trim_end_matches('/'))?;
        let valid_thread = thread.starts_with("19:")
            && thread.ends_with("@thread.v2")
            && thread[3..thread.len() - 10]
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "_-=".contains(c));
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

/// Join a Teams meeting. Resolves once the meeting's conference server
/// answers and audio is set up; `cancel` withdraws while it connects.
pub async fn join_meeting(
    link: &MeetingLink,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start(&link.thread_id, Target::Meeting(&link.message_id), cancel).await
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

/// Group chats (not meetings, channels or 1:1 chats).
pub fn is_group_chat(thread_id: &str) -> bool {
    thread_id.starts_with("19:")
        && thread_id.ends_with("@thread.v2")
        && !thread_id.starts_with("19:meeting_")
}

enum Target<'a> {
    /// A 1:1 call to this MRI; a video call when true.
    Person(&'a str, bool),
    /// A group chat's call: Meet now, Audio call or Join.
    Group(signaling::GroupCallKind),
    /// The meeting with this message id on the thread.
    Meeting(&'a str),
}

async fn start(
    thread_id: &str,
    target: Target<'_>,
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

    let mut local = LocalAudio::prepare().await?;
    // 1:1 calls offer video too (Teams' calls do); meetings and group
    // calls stay audio-only, since a media processor sends video only to
    // those who subscribe to it.
    let offer = if let (Target::Person(_, video), true) = (&target, cfg!(feature = "video")) {
        local.receive_video = true;
        local.camera_on = *video;
        local.offer_sdp_with_video()
    } else {
        local.offer_sdp()
    };
    let caller_mri = format!("8:orgid:{oid}");
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
            Ok(client) => match crate::api::files::member_oids(&client, thread_id).await {
                Ok(oids) => oids
                    .iter()
                    .take(MAX_RING)
                    .map(|o| format!("8:orgid:{o}"))
                    .collect(),
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
    let (created, _joined) = match target {
        Target::Person(callee, _) => {
            signaling::create_1to1_call_to(&http, &epconv_url, &params, &offer, Some(callee))
                .await?
        }
        Target::Group(kind) => {
            signaling::create_group_call(&http, &epconv_url, &params, &offer, &members, kind)
                .await?
        }
        Target::Meeting(message_id) => {
            signaling::join_meeting(&http, &epconv_url, &params, &offer, message_id).await?
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
    let properties_link = conversation_link(&created.response_body, "updateParticipantProperties");
    tracing::info!(members = members.len(), "group call members named");
    tracing::info!("call placed; waiting for the answer");

    let wait_answer = async {
        loop {
            let ev = match events.recv().await {
                Ok(ev) => ev,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(e) => bail!("Push channel closed: {e}"),
            };
            if ev.kind != EventKind::Call {
                continue;
            }
            match read_answer(&ev.json) {
                Some(Ok(a)) => return Ok(a),
                Some(Err(reason)) => bail!("{reason}"),
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
        answer = wait_answer => answer?,
        _ = tokio::time::sleep(RING_TIMEOUT) => return Err(withdraw(408, "No answer").await),
        _ = &mut cancel => return Err(withdraw(487, "Call cancelled").await),
    };
    tracing::info!("callee answered");

    if let Some(ack) = &acceptance.acknowledgement
        && let Err(e) = signaling::acknowledge_call_acceptance(&http, ack, &params).await
    {
        tracing::warn!("Acceptance acknowledgement failed: {:#}", e);
    }
    // Teams posts nothing else to the call leg here (it is for keep-alives
    // and hang-up); a callback re-registration on it is not something the
    // web client does.

    super::incoming::debug_dump("sdp-call-offer", &offer);
    super::incoming::debug_dump("sdp-call-answer", &acceptance.sdp);
    let media = match WebRtcOffer::parse(&acceptance.sdp) {
        Some(answer) => match WebRtcAudioSession::start_as_offerer(local, answer).await {
            Ok(m) => {
                m.set_local_sdp(&offer);
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
        renegotiation_link: acceptance
            .renegotiation
            .filter(|l| super::incoming::is_service_link(l)),
        state_links,
        hand: None,
        state_seq: 0,
        all_participants,
        admit_links,
        remove_link,
        properties_link,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
