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
    let (created, _joined) =
        signaling::create_1to1_call_to(&http, &epconv_url, &params, &offer, Some(callee_mri))
            .await?;
    let leave_url = leave_link(&created.response_body);
    tracing::info!("call placed; ringing");

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
