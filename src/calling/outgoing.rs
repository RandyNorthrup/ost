//! Outgoing 1:1 calls to Teams users, with WebRTC (DTLS-SRTP) audio.
//!
//! The call is created on the conversation service with our offer, the
//! callee is invited, and the callee's answer comes back over Trouter as a
//! callback on one of the links in our call invitation
//! (`…/callAgent/…/call/acceptance/`). Callbacks arrive through
//! [`crate::event_hub`], so the shared push connection must be running.

use anyhow::{bail, Context, Result};
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
        end: link("end"),
    }))
}

/// Call a Teams user. Resolves once the callee answers and audio is set
/// up, or fails if they decline, do not answer, or the call fails.
/// Sending on (or dropping) `cancel` while the callee is still ringing
/// withdraws the call, so their ringing stops.
pub async fn place_call(
    thread_id: &str,
    callee_mri: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    start(thread_id, Target::Person(callee_mri), cancel).await
}

/// A Teams meeting, from its join link
/// (`https://teams.microsoft.com/l/meetup-join/<thread>/<message>?context=…`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeetingLink {
    /// The meeting's chat thread, `19:meeting_…@thread.v2`.
    pub thread_id: String,
    /// `0` for scheduled meetings.
    pub message_id: String,
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
        Some(Self {
            thread_id: thread,
            message_id: message,
        })
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

/// Start a group call in a group chat (`19:…@thread.v2`): the call is
/// tied to the chat, so Teams rings its members and they join it.
pub async fn start_group_call(
    thread_id: &str,
    cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<OutgoingCall> {
    if !is_group_chat(thread_id) {
        bail!("Not a group chat");
    }
    start(thread_id, Target::Group, cancel).await
}

/// Group chats (not meetings, channels or 1:1 chats).
pub fn is_group_chat(thread_id: &str) -> bool {
    thread_id.starts_with("19:")
        && thread_id.ends_with("@thread.v2")
        && !thread_id.starts_with("19:meeting_")
}

enum Target<'a> {
    /// A 1:1 call to this MRI.
    Person(&'a str),
    /// A group call in a group chat (Teams rings its members).
    Group,
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

    let local = LocalAudio::prepare().await?;
    let offer = local.offer_sdp();
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
    let (created, _joined) = match target {
        Target::Person(callee) => {
            signaling::create_1to1_call_to(&http, &epconv_url, &params, &offer, Some(callee))
                .await?
        }
        Target::Group => {
            signaling::create_1to1_call_to(&http, &epconv_url, &params, &offer, None).await?
        }
        Target::Meeting(message_id) => {
            signaling::join_meeting(&http, &epconv_url, &params, &offer, message_id).await?
        }
    };
    let leave_url = leave_link(&created.response_body);
    // A group call rings the chat's members, as Teams' does.
    if matches!(target, Target::Group) {
        match crate::api::client::TeamsClient::new().await {
            Ok(client) => match crate::api::files::member_oids(&client, thread_id).await {
                Ok(oids) => {
                    for oid in oids.iter().take(MAX_RING) {
                        let mri = format!("8:orgid:{oid}");
                        if let Err(e) = signaling::invite_user(
                            &http,
                            &created.conversation_controller,
                            &params,
                            &mri,
                            false,
                        )
                        .await
                        {
                            tracing::warn!("Ringing a member failed: {:#}", e);
                        }
                    }
                    tracing::info!(rung = oids.len().min(MAX_RING), "group call members rung");
                }
                Err(e) => tracing::warn!("Group members unavailable: {:#}", e),
            },
            Err(e) => tracing::warn!("Group members unavailable: {:#}", e),
        }
    }
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

    if let Some(ack) = &acceptance.acknowledgement {
        if let Err(e) = signaling::acknowledge_call_acceptance(&http, ack, &params).await {
            tracing::warn!("Acceptance acknowledgement failed: {:#}", e);
        }
    }
    // Teams posts nothing else to the call leg here (it is for keep-alives
    // and hang-up); a callback re-registration on it is not something the
    // web client does.

    let media = match WebRtcOffer::parse(&acceptance.sdp) {
        Some(answer) => match WebRtcAudioSession::start_as_offerer(local, answer).await {
            Ok(m) => Some(m),
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
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(MeetingLink::parse(
            "https://evil.example/l/meetup-join/19%3ameeting_x%40thread.v2/0"
        )
        .is_none());
        assert!(MeetingLink::parse(
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%22%40thread.v2/0"
        )
        .is_none());
        assert!(MeetingLink::parse(
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/abc"
        )
        .is_none());
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
