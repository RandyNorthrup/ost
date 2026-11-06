//! Incoming calls: inspect an invitation, then answer, decline or hang up.
//!
//! This is the call flow the CLI used to run inline when auto-answering,
//! made reusable so a UI can ring first and let the user choose. Media runs
//! for as long as the returned [`ActiveCall`] is alive.

use std::time::Instant;

use anyhow::{Context, Result};

use super::media::{MediaSession, MediaStats, VideoMediaSession};
use super::{CallNotification, ice, sdp, signaling, srtp, turn, webrtc_audio};

/// A call invitation pushed over Trouter, not yet answered.
///
/// Two shapes exist. The legacy one carries a `callInvitation` (SDP offer
/// and acceptance links) directly. Current Teams sends a forked
/// `callNotification` (evt 107) with only `attach` / `reject` links: the
/// callee attaches to the call first and gets the `callInvitation` back.
#[derive(Debug, Clone)]
pub struct IncomingCall {
    notification: Option<CallNotification>,
    forked: Option<serde_json::Value>,
    /// A forked call's full invitation, fetched while it rings
    /// ([`CallAuth::probe_video`]) so we know whether it's a video call.
    attached: Option<CallNotification>,
}

impl IncomingCall {
    /// Parse a call event. Only invitations that can be answered qualify;
    /// other call-signalling events return `None`.
    pub fn parse(json: &str) -> Option<Self> {
        let v: serde_json::Value = serde_json::from_str(json).ok()?;
        if v.pointer("/callNotification/links/attach")
            .and_then(|a| a.as_str())
            .is_some()
        {
            return Some(Self {
                notification: None,
                forked: Some(v),
                attached: None,
            });
        }
        let notification = super::parse_call_notification(json)?;
        notification
            .call_invitation
            .as_ref()?
            .links
            .as_ref()?
            .acceptance
            .as_ref()?;
        Some(Self {
            notification: Some(notification),
            forked: None,
            attached: None,
        })
    }

    /// The caller's display name, or "Unknown caller".
    pub fn caller_name(&self) -> String {
        self.caller_field("displayName")
            .filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| "Unknown caller".to_string())
    }

    /// The caller's MRI (for example `8:orgid:<oid>`).
    pub fn caller_id(&self) -> Option<String> {
        self.caller_field("id")
    }

    /// The service's call id, stable across the events of one call.
    pub fn call_id(&self) -> Option<String> {
        match (&self.notification, &self.forked) {
            (Some(n), _) => n.debug_content.as_ref().and_then(|d| d.call_id.clone()),
            (None, Some(v)) => str_at(v, "/debugContent/callId"),
            _ => None,
        }
    }

    /// Whether the caller offered video (known up front only for legacy
    /// invitations; forked ones reveal it after attaching).
    pub fn has_video(&self) -> bool {
        let modalities = self
            .notification
            .as_ref()
            .and_then(|n| n.call_invitation.as_ref())
            .and_then(|inv| inv.call_modalities.as_ref())
            .is_some_and(|mods| mods.iter().any(|m| m.eq_ignore_ascii_case("video")));
        // Forked calls: the attached invitation's offer says.
        let offered = self
            .attached
            .as_ref()
            .and_then(|n| {
                n.call_invitation
                    .as_ref()?
                    .media_content
                    .as_ref()?
                    .blob
                    .clone()
            })
            .and_then(|b| webrtc_audio::WebRtcOffer::parse(&b))
            .and_then(|o| o.video)
            .is_some_and(|v| v.sends);
        modalities || offered
    }

    fn caller_field(&self, field: &str) -> Option<String> {
        match (&self.notification, &self.forked) {
            (Some(n), _) => {
                let from = n.participants.as_ref()?.from.as_ref()?;
                match field {
                    "id" => from.id.clone(),
                    _ => from.display_name.clone(),
                }
            }
            (None, Some(v)) => str_at(v, &format!("/callNotification/from/{field}")),
            _ => None,
        }
    }
}

fn str_at(v: &serde_json::Value, pointer: &str) -> Option<String> {
    v.pointer(pointer)
        .and_then(|x| x.as_str())
        .map(str::to_string)
}

/// Developer aid: with `OST_TROUTER_DUMP_DIR` set, keep call SDP for
/// protocol work (owner-only files; off by default).
pub(crate) fn debug_dump(kind: &str, text: &str) {
    let Some(dir) = std::env::var_os("OST_TROUTER_DUMP_DIR") else {
        return;
    };
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    if let Ok(mut f) = opts.open(std::path::Path::new(&dir).join(format!("{kind}-{ts}.txt"))) {
        use std::io::Write;
        let _ = f.write_all(text.as_bytes());
    }
}

/// Who we are in call signalling.
#[derive(Clone)]
struct LocalParticipant {
    id: String,
    display_name: String,
    endpoint_id: String,
    participant_id: String,
    trouter_surl: String,
}

impl LocalParticipant {
    fn json(&self) -> serde_json::Value {
        serde_json::json!({
            "id": self.id,
            "displayName": self.display_name,
            "endpointId": self.endpoint_id,
            "participantId": self.participant_id,
            "languageId": "en-US",
        })
    }

    /// A callback URL on our Trouter socket, as Teams builds them.
    fn callback(&self, path: &str) -> String {
        signaling::trouter_callback(&self.trouter_surl, &self.endpoint_id, path)
    }
}

/// Capabilities the Teams web client advertises for an answering endpoint.
const ENDPOINT_CAPABILITIES: u64 = 73463;

/// Whether a link from a call push is one of Teams' services (our Skype
/// token goes only there): https on teams.microsoft.com, skype.com or
/// trouter.io.
pub(crate) fn is_service_link(url: &str) -> bool {
    let Ok(u) = reqwest::Url::parse(url) else {
        return false;
    };
    let host = u.host_str().unwrap_or_default().to_ascii_lowercase();
    u.scheme() == "https"
        && [
            ".teams.microsoft.com",
            ".skype.com",
            ".trouter.io",
            ".teams.cloud.microsoft",
        ]
        .iter()
        .any(|d| host.ends_with(d))
}

/// Answer a re-offer from the other side. A plain re-offer (the same
/// media, directions changed) gets our earlier SDP mirrored. A new offer
/// (`newOffer`: Teams moving the call onto a media processor, as its Hold
/// does to play music, or escalating to a group call) gets a fresh answer,
/// and the media moves to a new session with ICE and DTLS against it.
/// `me`: our participant JSON and media-acknowledgement callback.
/// Returns whether the other side has us on hold.
pub(crate) async fn answer_renegotiation(
    http: &reqwest::Client,
    skype_token: &str,
    session: &mut Option<webrtc_audio::WebRtcAudioSession>,
    me: Option<(serde_json::Value, String)>,
    event: &serde_json::Value,
) -> Result<bool> {
    let neg = event
        .pointer("/body/mediaNegotiation")
        .or_else(|| event.get("mediaNegotiation"))
        .context("Not a renegotiation")?;
    let offer = str_at(neg, "/mediaContent/blob").context("Re-offer without SDP")?;
    let url = str_at(neg, "/links/mediaAnswer").context("Re-offer without a mediaAnswer link")?;
    let current = session.as_ref().context("No WebRTC media to renegotiate")?;
    debug_dump("sdp-reoffer", &offer);
    let new_offer = neg
        .pointer("/mediaContent/newOffer")
        .and_then(|v| v.as_bool())
        == Some(true);
    let mut moved = None;
    let sdp = if new_offer {
        let parsed =
            webrtc_audio::WebRtcOffer::parse(&offer).context("New offer without DTLS-SRTP")?;
        let local = webrtc_audio::LocalAudio::prepare().await?;
        let sdp = local.answer_sdp_with(&parsed, false);
        moved = Some((local, parsed));
        sdp
    } else {
        current.answer_reoffer(&offer)?
    };
    debug_dump("sdp-reanswer", &sdp);
    let mut answer = serde_json::json!({
        "callModalities": neg.get("callModalities").cloned().unwrap_or(serde_json::json!(["audio"])),
        "mediaContent": { "blob": sdp, "contentType": "application/sdp" },
    });
    if let Some((sender, ack)) = me {
        answer["sender"] = sender;
        answer["links"] = serde_json::json!({ "mediaAcknowledgement": ack });
    }
    cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        &url,
        &serde_json::json!({ "mediaAnswer": answer }),
        "Re-answer",
    )
    .await?;
    if let Some((local, parsed)) = moved {
        let muted = current.is_muted();
        let held = current.is_held();
        let fresh = webrtc_audio::WebRtcAudioSession::start(local, parsed).await?;
        fresh.set_local_sdp(&sdp);
        fresh.set_muted(muted);
        fresh.set_held(held);
        tracing::info!("media moved to the new offer");
        // The old session (its socket, camera and tasks) stops here.
        *session = Some(fresh);
    }
    Ok(session.as_ref().is_some_and(|s| s.is_held_by_peer()))
}

/// What a share re-offer says the call carries (Teams' media types).
pub(crate) fn share_modalities(sharing: bool, camera: bool) -> serde_json::Value {
    let mut m = vec!["Audio"];
    if camera {
        m.push("Video");
    }
    m.push(if sharing {
        "ScreenSharer"
    } else {
        "ScreenViewer"
    });
    serde_json::json!(m)
}

/// Offer a change to the call's media ourselves (Teams'
/// `mediaRenegotiation`), as Teams does to start or stop sharing a screen.
/// The answer comes back to our `call/mediaAnswer/` callback (or a
/// refusal to `call/rejection/`).
pub(crate) async fn request_reoffer(
    http: &reqwest::Client,
    skype_token: &str,
    link: &str,
    sender: serde_json::Value,
    cb: impl Fn(&str) -> String,
    sdp: &str,
    modalities: serde_json::Value,
) -> Result<()> {
    if !is_service_link(link) {
        anyhow::bail!("The renegotiation link isn't a Teams service");
    }
    let body = serde_json::json!({
        "mediaNegotiation": {
            "callModalities": modalities,
            "sender": sender,
            "links": {
                "mediaAnswer": cb("call/mediaAnswer/"),
                "rejection": cb("call/rejection/"),
            },
            "mediaContent": {
                "blob": sdp,
                "contentType": signaling::OFFER_CONTENT_TYPE,
                "newOffer": false,
                "escalationOccurring": false,
            },
        }
    });
    cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        link,
        &body,
        "Re-offer",
    )
    .await?;
    Ok(())
}

/// The other side's answer to our re-offer, and where to acknowledge it
/// (Teams waits for the acknowledgement before it calls the change done).
#[derive(Debug, PartialEq)]
pub struct ReofferAnswer {
    pub sdp: String,
    pub ack: Option<String>,
}

/// The other side's reply to our re-offer: `Some(Ok(answer))`, or
/// `Some(Err(..))` when it refused; `None` for other events.
pub fn reoffer_reply(json: &str) -> Option<Result<ReofferAnswer>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let path = v.get("callAgentPath")?.as_str()?;
    if path.starts_with("call/mediaAnswer") {
        let blob = v
            .pointer("/body/mediaAnswer/mediaContent/blob")
            .and_then(|b| b.as_str())
            .map(str::to_string);
        let ack = str_at(&v, "/body/mediaAnswer/links/mediaAcknowledgement")
            .filter(|l| is_service_link(l));
        Some(
            blob.context("Answer without SDP")
                .map(|sdp| ReofferAnswer { sdp, ack }),
        )
    } else if path.starts_with("call/rejection") {
        let body = v.get("body").cloned().unwrap_or_default();
        let why = [
            "/mediaRejection/phrase",
            "/rejection/phrase",
            "/mediaNegotiationFailure/phrase",
        ]
        .iter()
        .find_map(|p| body.pointer(p).and_then(|x| x.as_str()))
        .map(str::to_string)
        .unwrap_or_else(|| {
            let mut s = body.to_string();
            s.truncate(300);
            format!("refused: {s}")
        });
        Some(Err(anyhow::anyhow!("The other side {why}")))
    } else {
        None
    }
}

/// Put the other person on hold as Teams does (its "serverHoldV2"): the
/// call controller moves them onto music, and returns the resume link.
pub(crate) async fn request_hold(
    http: &reqwest::Client,
    skype_token: &str,
    hold_link: &str,
    completion: &str,
) -> Result<String> {
    let body = serde_json::json!({
        "hold": { "holdType": "musicOnHold", "links": { "holdCompletion": completion } }
    });
    let reply = cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        hold_link,
        &body,
        "Hold",
    )
    .await?;
    let resume =
        str_at(&reply, "/holdResponse/links/resume").context("Hold reply without a resume link")?;
    if !is_service_link(&resume) {
        anyhow::bail!("Hold reply's resume link isn't a Teams service");
    }
    Ok(resume)
}

/// Take the call off hold (the resume link from `request_hold`).
pub(crate) async fn request_resume(
    http: &reqwest::Client,
    skype_token: &str,
    resume_link: &str,
    completion: &str,
) -> Result<()> {
    let body = serde_json::json!({ "resume": { "links": { "resumeCompletion": completion } } });
    cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        resume_link,
        &body,
        "Resume",
    )
    .await?;
    Ok(())
}

/// Hand the call to someone else (Teams' Transfer): the call controller
/// rings `target` (an `8:orgid:` MRI) and connects them in our place.
/// `transferor`: our participant details; `cb`: makes our callback URLs.
pub(crate) async fn request_transfer(
    http: &reqwest::Client,
    skype_token: &str,
    transfer_link: &str,
    target: &str,
    transferor: serde_json::Value,
    cb: impl Fn(&str) -> String,
) -> Result<()> {
    let oid = target
        .strip_prefix("8:orgid:")
        .context("Not a person to transfer to")?;
    if uuid::Uuid::parse_str(oid).is_err() {
        anyhow::bail!("Not a person to transfer to");
    }
    let body = serde_json::json!({
        "callTransfer": {
            "target": { "id": target },
            "transferor": { "details": transferor, "authorizationToken": null },
            "links": {
                "transferAcceptance": cb("call/transferAcceptance/"),
                "transferCompletion": cb("call/transferCompletion/"),
            },
        }
    });
    cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        transfer_link,
        &body,
        "Transfer",
    )
    .await?;
    Ok(())
}

/// A transfer's outcome from `call/transferCompletion`: Some(Ok) when the
/// target took the call, Some(Err(phrase)) when it failed.
pub fn transfer_outcome(json: &str) -> Option<std::result::Result<(), String>> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let path = v
        .get("callAgentPath")
        .and_then(|p| p.as_str())
        .unwrap_or_default();
    let t = v
        .pointer("/body/transferCompletion")
        .or_else(|| v.get("transferCompletion"))
        .filter(|_| path.is_empty() || path.starts_with("call/transferCompletion"))?;
    let code = t.get("code").and_then(|c| c.as_u64()).unwrap_or(0);
    if code < 300 {
        Some(Ok(()))
    } else {
        Some(Err(t
            .get("phrase")
            .and_then(|p| p.as_str())
            .unwrap_or("Transfer failed")
            .to_string()))
    }
}

/// Teams' Hold moves the held side onto a media processor that plays
/// music; `call/retargetCompletion` tells which bot it went to. Returns
/// Some(on hold) for a retarget event.
pub fn retarget_hold(json: &str) -> Option<bool> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let r = v
        .pointer("/body/retargetCompleted")
        .or_else(|| v.get("retargetCompleted"))?;
    let ok = r.get("code").and_then(|c| c.as_u64()).unwrap_or(0) < 300;
    Some(ok && r.get("audioBotType").and_then(|b| b.as_str()) == Some("audioPlayback"))
}

/// POST a JSON body to a call-controller link and return the JSON reply
/// (or `Null` for an empty one). Errors carry only the HTTP status.
async fn cc_request(
    http: &reqwest::Client,
    skype_token: &str,
    method: reqwest::Method,
    url: &str,
    body: &serde_json::Value,
    what: &str,
) -> Result<serde_json::Value> {
    if !is_service_link(url) {
        anyhow::bail!("{what}: not a Teams service link");
    }
    let resp = http
        .request(method, url)
        .header("X-Skypetoken", skype_token)
        .json(body)
        .send()
        .await
        .with_context(|| format!("{what} failed to send"))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!("{what} failed: HTTP {status}");
    }
    tracing::info!("{what}: HTTP {status}");
    Ok(serde_json::from_str(&text).unwrap_or(serde_json::Value::Null))
}

/// Attach to a forked call: the reply holds the `callInvitation` (SDP offer
/// and links) that legacy notifications carried directly.
async fn attach(
    http: &reqwest::Client,
    skype_token: &str,
    forked: &serde_json::Value,
    me: &LocalParticipant,
) -> Result<CallNotification> {
    let attach_url = str_at(forked, "/callNotification/links/attach").context("No attach link")?;
    let conversation = str_at(forked, "/conversationInvitation/conversationController")
        .context("No conversation controller")?;
    let mut body = serde_json::json!({
        "attach": {
            "requireMediaContent": true,
            "links": { "end": me.callback("call/end/") },
        },
        "capabilities": null,
        "endpointCapabilities": ENDPOINT_CAPABILITIES,
        "additionalActions": [{
            "input": {
                "capabilities": null,
                "endpointCapabilities": ENDPOINT_CAPABILITIES,
                "conversationRequest": {
                    "roster": { "type": "Delta", "rosterUpdate": me.callback("conversation/rosterUpdate/") },
                    "links": {
                        "conversationEnd": me.callback("conversation/conversationEnd/"),
                        "conversationUpdate": me.callback("conversation/conversationUpdate/"),
                        "localParticipantUpdate": me.callback("conversation/localParticipantUpdate/"),
                        "addParticipantSuccess": me.callback("conversation/addParticipantSuccess/"),
                        "addParticipantFailure": me.callback("conversation/addParticipantFailure/"),
                        "receiveMessage": me.callback("conversation/receiveMessage/"),
                    },
                },
                "endpointMetadata": { "holographicCapabilities": 3 },
                "participants": { "from": me.json() },
            },
            "name": "join",
            "url": conversation,
            "waitForResponse": true,
        }],
    });
    if let Some(etag) = str_at(forked, "/debugContent/ecsEtag") {
        body["debugContent"] = serde_json::json!({ "ecsEtag": etag });
    }
    let reply = cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        &attach_url,
        &body,
        "Call attach",
    )
    .await?;
    let shape: Vec<&String> = reply
        .as_object()
        .map(|o| o.keys().collect())
        .unwrap_or_default();
    tracing::info!(?shape, "attach reply");
    let invitation = reply
        .get("callInvitation")
        .cloned()
        .context("Attach reply has no callInvitation")?;
    let mut notification: CallNotification = serde_json::from_value(serde_json::json!({
        "callInvitation": invitation,
        // `to` is an object here, not the legacy list; only `from` is used.
        "participants": { "from": reply.pointer("/participants/from").cloned() },
        "debugContent": forked.get("debugContent").cloned(),
    }))
    .context("Unexpected callInvitation shape")?;
    // The forked notification's reject link ends a call that was never set up.
    if let Some(links) = notification
        .call_invitation
        .as_mut()
        .and_then(|i| i.links.as_mut())
        && links.end.is_none()
    {
        links.end = str_at(forked, "/callNotification/links/reject");
    }
    Ok(notification)
}

/// An answered call. Dropping it stops the media; call [`ActiveCall::hang_up`]
/// to also end the call for the other side.
pub struct ActiveCall {
    notification: CallNotification,
    forked: bool,
    /// Forked calls: the accepted leg, for keep-alives and hang-up.
    call_leg: Option<String>,
    keep_alive: Option<tokio::task::JoinHandle<()>>,
    audio: Option<MediaSession>,
    /// Audio with a WebRTC (DTLS-SRTP) caller.
    webrtc: Option<webrtc_audio::WebRtcAudioSession>,
    video: Option<VideoMediaSession>,
    started: Instant,
    /// Who we are in a forked call (sender of re-answers).
    me: Option<LocalParticipant>,
    /// Hold's link, and Resume's once on hold.
    hold_link: Option<String>,
    resume_link: Option<String>,
    transfer_link: Option<String>,
    /// Where our own re-offers go (`links.mediaRenegotiation`).
    renegotiation_link: Option<String>,
}

impl Drop for ActiveCall {
    fn drop(&mut self) {
        if let Some(k) = self.keep_alive.take() {
            k.abort();
        }
    }
}

impl ActiveCall {
    /// When the call was answered.
    pub fn started(&self) -> Instant {
        self.started
    }

    /// Whether audio media is flowing (ICE and SRTP were set up).
    pub fn has_audio(&self) -> bool {
        self.audio.is_some() || self.webrtc.is_some()
    }

    pub fn set_muted(&self, muted: bool) {
        if let Some(a) = &self.audio {
            a.set_muted(muted);
        }
        if let Some(w) = &self.webrtc {
            w.set_muted(muted);
        }
    }

    pub fn is_muted(&self) -> bool {
        self.audio.as_ref().is_some_and(|a| a.is_muted())
            || self.webrtc.as_ref().is_some_and(|w| w.is_muted())
    }

    /// Hold or resume the call with the call controller (the other person
    /// hears Teams' hold music), then stop or restart our own audio.
    pub async fn hold(&mut self, auth: &CallAuth, held: bool) -> Result<()> {
        let me = self.me.as_ref().context("Hold needs a Teams call")?;
        if held {
            let link = self
                .hold_link
                .as_deref()
                .context("This call can't be put on hold")?;
            let resume = request_hold(
                &auth.http,
                &auth.skype_token,
                link,
                &me.callback("call/holdCompletion/"),
            )
            .await?;
            self.resume_link = Some(resume);
        } else {
            let link = self.resume_link.take().context("The call isn't on hold")?;
            request_resume(
                &auth.http,
                &auth.skype_token,
                &link,
                &me.callback("call/resumeCompletion/"),
            )
            .await?;
        }
        self.set_held(held);
        Ok(())
    }

    /// Transfer the call to `target` (an `8:orgid:` MRI).
    pub async fn transfer(&self, auth: &CallAuth, target: &str) -> Result<()> {
        let me = self.me.as_ref().context("Transfer needs a Teams call")?;
        let link = self
            .transfer_link
            .as_deref()
            .context("This call can't be transferred")?;
        let details = serde_json::json!({
            "id": me.id, "endpointId": me.endpoint_id,
            "participantId": me.participant_id, "languageId": "en-US",
        });
        request_transfer(&auth.http, &auth.skype_token, link, target, details, |p| {
            me.callback(p)
        })
        .await
    }

    /// Put the call on hold, or resume it (our media only).
    pub fn set_held(&self, held: bool) {
        if let Some(w) = &self.webrtc {
            w.set_held(held);
        }
        if let Some(a) = &self.audio {
            a.set_muted(held || self.is_muted());
        }
    }

    /// The other side has the call on hold.
    pub fn is_held_by_peer(&self) -> bool {
        self.webrtc.as_ref().is_some_and(|w| w.is_held_by_peer())
    }

    /// Answer the other side's re-offer (`call/mediaRenegotiation`: hold,
    /// resume, a camera turned on) so the call carries on. Returns whether
    /// it now has us on hold.
    pub async fn answer_renegotiation(
        &mut self,
        auth: &CallAuth,
        event: &serde_json::Value,
    ) -> Result<bool> {
        let me = self
            .me
            .as_ref()
            .map(|m| (m.json(), m.callback("call/mediaAcknowledgement/")));
        answer_renegotiation(&auth.http, &auth.skype_token, &mut self.webrtc, me, event).await
    }

    /// The call takes dial-pad tones.
    pub fn can_dtmf(&self) -> bool {
        self.webrtc.as_ref().is_some_and(|w| w.can_dtmf())
    }

    /// We can share our screen in this call (Share usable).
    pub fn can_share(&self) -> bool {
        self.me.is_some()
            && self.renegotiation_link.is_some()
            && self.webrtc.as_ref().is_some_and(|w| w.can_share())
    }

    /// Offer to start (or stop) sending our screen; the answer comes back
    /// as a `call/mediaAnswer/` event for [`Self::take_share_answer`].
    pub async fn offer_share(&mut self, auth: &CallAuth, on: bool) -> Result<()> {
        let me = self.me.as_ref().context("Sharing needs a Teams call")?;
        let link = self
            .renegotiation_link
            .as_deref()
            .context("This call can't renegotiate media")?;
        let w = self.webrtc.as_ref().context("No media to share on")?;
        let sdp = w.share_reoffer(on)?;
        debug_dump("sdp-share-offer", &sdp);
        request_reoffer(
            &auth.http,
            &auth.skype_token,
            link,
            me.json(),
            |p| me.callback(p),
            &sdp,
            share_modalities(on, w.camera_on()),
        )
        .await
    }

    /// Acknowledge the other side's answer to our re-offer, as Teams does
    /// (an empty POST to the answer's `mediaAcknowledgement` link).
    pub async fn acknowledge_answer(&self, auth: &CallAuth, link: &str) -> Result<()> {
        cc_request(
            &auth.http,
            &auth.skype_token,
            reqwest::Method::POST,
            link,
            &serde_json::Value::Null,
            "Media acknowledgement",
        )
        .await?;
        Ok(())
    }

    /// The other side refused our share re-offer.
    pub fn cancel_share_offer(&self) {
        if let Some(w) = self.webrtc.as_ref() {
            w.cancel_share_offer();
        }
    }

    /// Whether our share re-offer is waiting for its answer.
    pub fn share_offer_pending(&self) -> bool {
        self.webrtc
            .as_ref()
            .is_some_and(|w| w.share_offer_pending())
    }

    /// The answer to our share re-offer: whether it takes our screen.
    pub fn take_share_answer(&mut self, answer: &str) -> Result<bool> {
        debug_dump("sdp-share-answer", answer);
        self.webrtc
            .as_ref()
            .context("No media to share on")?
            .take_share_answer(answer)
    }

    /// Start sending a screen capture.
    #[cfg(feature = "screencast")]
    pub fn start_share(
        &mut self,
        capture: super::screencast::ScreenCapture,
        frames: std::sync::mpsc::Receiver<super::camera::YuvFrame>,
    ) -> Result<()> {
        self.webrtc
            .as_mut()
            .context("No media to share on")?
            .start_share(capture, frames)
    }

    /// Stop sending our screen.
    pub fn stop_share(&mut self) {
        if let Some(w) = self.webrtc.as_mut() {
            w.stop_share();
        }
    }

    /// Whether we're sending our screen.
    pub fn is_sharing(&self) -> bool {
        self.webrtc.as_ref().is_some_and(|w| w.is_sharing())
    }

    /// Whether our shared screen went away by itself.
    pub fn share_ended(&self) -> bool {
        self.webrtc.as_ref().is_some_and(|w| w.share_ended())
    }

    /// Send a dial-pad key as a tone.
    pub fn send_dtmf(&self, key: char) -> Result<()> {
        self.webrtc
            .as_ref()
            .context("This call doesn't take dial-pad tones")?
            .send_dtmf(key)
    }

    /// The call negotiated video we can send (camera button usable).
    pub fn can_send_video(&self) -> bool {
        self.webrtc.as_ref().is_some_and(|w| w.can_send_video())
    }

    /// Turn the camera on or off.
    pub fn set_camera(&mut self, on: bool, device: Option<String>) -> Result<()> {
        self.webrtc
            .as_mut()
            .context("No video in this call")?
            .set_camera(on, device)
    }

    pub async fn audio_stats(&self) -> Option<MediaStats> {
        if let Some(w) = &self.webrtc {
            let s = w.stats().await;
            return Some(MediaStats {
                packets_sent: s.packets_sent,
                packets_received: s.packets_received,
                bytes_received: s.bytes_received,
                ..Default::default()
            });
        }
        match &self.audio {
            Some(a) => Some(a.stats().await),
            None => None,
        }
    }

    pub async fn video_stats(&self) -> Option<super::media::VideoStats> {
        match &self.video {
            Some(v) => Some(v.stats().await),
            None => None,
        }
    }

    /// Stop media and end the call.
    pub async fn hang_up(mut self, http: &reqwest::Client, skype_token: &str) -> Result<()> {
        if let Some(a) = self.audio.as_mut() {
            a.stop().await;
        }
        if let Some(v) = self.video.as_mut() {
            v.stop().await;
        }
        self.webrtc = None;
        if let Some(k) = self.keep_alive.take() {
            k.abort();
        }
        if self.forked {
            let url = self.call_leg.clone().context("No call leg to hang up")?;
            let body = serde_json::json!({
                "callEnd": { "code": 0, "subCode": 0, "phrase": "CallEndReasonLocalUserInitiated" }
            });
            cc_request(
                http,
                skype_token,
                reqwest::Method::DELETE,
                &url,
                &body,
                "Call end",
            )
            .await?;
            return Ok(());
        }
        signaling::end_call(http, skype_token, &self.notification).await
    }
}

/// Decline a ringing call.
pub async fn decline(http: &reqwest::Client, skype_token: &str, call: &IncomingCall) -> Result<()> {
    match (&call.notification, &call.forked) {
        (Some(n), _) => signaling::end_call(http, skype_token, n).await,
        (None, Some(v)) => {
            let url = str_at(v, "/callNotification/links/reject").context("No reject link")?;
            let body = serde_json::json!({ "callEnd": { "code": 603, "subCode": 0, "phrase": "RejectCall" } });
            cc_request(
                http,
                skype_token,
                reqwest::Method::DELETE,
                &url,
                &body,
                "Call reject",
            )
            .await?;
            Ok(())
        }
        _ => Ok(()),
    }
}

/// Answer a call: send the SDP answer, start audio (and video when asked
/// for and offered), then accept. `microphone_on` is what the caller is told
/// about our microphone; the session itself starts unmuted unless it is false.
pub async fn answer(
    http: &reqwest::Client,
    skype_token: &str,
    call: IncomingCall,
    with_video: bool,
    microphone_on: bool,
) -> Result<ActiveCall> {
    let forked = call.forked.is_some();
    let me = if forked {
        Some(local_participant(call.forked.as_ref())?)
    } else {
        None
    };
    let notification = match (call.notification, call.attached, &call.forked, &me) {
        (Some(n), _, _, _) => n,
        (None, Some(n), _, _) => n,
        (None, None, Some(v), Some(me)) => attach(http, skype_token, v, me).await?,
        _ => anyhow::bail!("Not a call invitation"),
    };
    let blob = notification
        .call_invitation
        .as_ref()
        .and_then(|inv| inv.media_content.as_ref())
        .and_then(|mc| mc.blob.clone());

    // WebRTC callers (Teams web) secure media with DTLS-SRTP.
    if let Some(offer) = blob.as_deref().and_then(webrtc_audio::WebRtcOffer::parse) {
        debug_dump("sdp-offer", blob.as_deref().unwrap_or_default());
        return answer_webrtc(
            http,
            skype_token,
            notification,
            me,
            offer,
            with_video,
            microphone_on,
        )
        .await;
    }

    // TURN relay credentials are best-effort: without them we offer only
    // direct and server-reflexive candidates.
    let relay_candidate = match turn::acquire_relay_credentials(http, skype_token).await {
        Ok(config) => {
            tracing::info!(
                "Acquired relay credentials: {} servers, ttl={}s",
                config.servers.len(),
                config.ttl
            );
            turn::gather_relay_candidate(&config).await.map(|(c, _)| c)
        }
        Err(e) => {
            tracing::info!("Relay credentials unavailable (direct/srflx only): {:#}", e);
            None
        }
    };

    let mut audio_task = None;
    let mut video = None;

    if let Some(blob) = blob {
        debug_dump("sdp-offer", &blob);
        match sdp::parse_sdp_offer(&blob) {
            Ok(offer) => {
                let local_ip = sdp::get_local_ip();
                let remote_audio_crypto = offer
                    .crypto_lines
                    .iter()
                    .find_map(|l| srtp::parse_crypto_line(l).ok());
                let remote_video_crypto = offer.video.as_ref().and_then(|v| {
                    v.crypto_lines
                        .iter()
                        .find_map(|l| srtp::parse_crypto_line(l).ok())
                });
                let local_cands: Vec<ice::IceCandidate> = relay_candidate.into_iter().collect();
                let answer =
                    sdp::generate_sdp_answer_full(&local_ip, 0, 0, &offer, &local_cands, &[]);
                let local_audio_crypto = srtp::parse_crypto_line(&answer.audio_crypto_line).ok();
                let local_video_crypto = answer
                    .video_crypto_line
                    .as_ref()
                    .and_then(|l| srtp::parse_crypto_line(l).ok());

                // Protocol order: media answer before acceptance.
                let sent = match &me {
                    Some(me) => {
                        send_media_answer_v2(
                            http,
                            skype_token,
                            &notification,
                            me,
                            &answer.sdp,
                            with_video,
                        )
                        .await
                    }
                    None => {
                        signaling::send_media_answer(http, skype_token, &notification, &answer.sdp)
                            .await
                    }
                };
                if let Err(e) = sent {
                    tracing::warn!("Failed to send media answer: {:#}", e);
                }

                match (local_audio_crypto, remote_audio_crypto) {
                    (Some(local), Some(remote)) => {
                        let candidates = ice::parse_candidates_from_sdp(&blob);
                        if candidates
                            .iter()
                            .any(|c| c.transport == ice::Transport::Udp && c.component == 1)
                        {
                            let local_creds = ice::IceCredentials {
                                ufrag: answer.audio_ice_ufrag.clone(),
                                pwd: answer.audio_ice_pwd.clone(),
                            };
                            let remote_creds = ice::IceCredentials {
                                ufrag: offer.ice_ufrag.clone(),
                                pwd: offer.ice_pwd.clone(),
                            };
                            // ICE runs while we accept, as the peer only
                            // starts its checks once the call is accepted.
                            audio_task = Some(tokio::spawn(async move {
                                MediaSession::start_with_ice(
                                    0,
                                    &candidates,
                                    &local_creds,
                                    &remote_creds,
                                    &local,
                                    &remote,
                                )
                                .await
                            }));
                        } else {
                            tracing::warn!("No suitable audio ICE candidate found");
                        }
                    }
                    _ => tracing::warn!("Missing audio SRTP keying material; no audio"),
                }

                if with_video
                    && offer.video.is_some()
                    && let (Some(local), Some(remote)) = (local_video_crypto, remote_video_crypto)
                {
                    let cands = ice::parse_candidates_from_sdp_section(&blob, "video");
                    if let Some(addr) = ice::select_remote_candidate(&cands) {
                        match VideoMediaSession::start(0, addr, &local, &remote).await {
                            Ok(v) => video = Some(v),
                            Err(e) => tracing::warn!("Video session failed: {:#}", e),
                        }
                    }
                }
            }
            Err(e) => tracing::warn!("Could not parse SDP offer: {:#}", e),
        }
    }

    let (leg, keep_alive) = accept_with_keep_alive(
        http,
        skype_token,
        &notification,
        me.as_ref(),
        with_video,
        microphone_on,
    )
    .await?;

    let audio = match audio_task {
        Some(task) => match task.await {
            Ok(Ok(session)) => {
                session.set_muted(!microphone_on);
                Some(session)
            }
            Ok(Err(e)) => {
                tracing::warn!("Audio session failed: {:#}", e);
                None
            }
            Err(e) => {
                tracing::warn!("Audio session task failed: {e}");
                None
            }
        },
        None => None,
    };

    Ok(ActiveCall {
        notification,
        forked,
        call_leg: leg.url,
        keep_alive,
        audio,
        webrtc: None,
        video,
        started: Instant::now(),
        me,
        hold_link: leg.hold,
        resume_link: None,
        transfer_link: leg.transfer,
        renegotiation_link: leg.renegotiation,
    })
}

/// Answer a DTLS-SRTP (WebRTC) offer: bundled audio (PCMU), plus the
/// caller's video when `with_video`.
async fn answer_webrtc(
    http: &reqwest::Client,
    skype_token: &str,
    notification: CallNotification,
    me: Option<LocalParticipant>,
    offer: webrtc_audio::WebRtcOffer,
    with_video: bool,
    microphone_on: bool,
) -> Result<ActiveCall> {
    let mut local = webrtc_audio::LocalAudio::prepare().await?;
    // Accept the caller's video whenever it's offered (Teams shows it even
    // to someone who answers with audio, and lets them turn their camera
    // on later); `with_video` only decides whether our camera starts on.
    let _ = with_video;
    let video = cfg!(feature = "video") && offer.video.is_some();
    local.receive_video = video;
    let sdp = local.answer_sdp_with(&offer, video);
    debug_dump("sdp-answer", &sdp);
    match &me {
        Some(me) => send_media_answer_v2(http, skype_token, &notification, me, &sdp, false).await,
        None => signaling::send_media_answer(http, skype_token, &notification, &sdp).await,
    }
    .context("Media answer failed")?;
    // ICE and DTLS run while we accept: the caller starts its checks once
    // the call is accepted.
    let media = tokio::spawn(webrtc_audio::WebRtcAudioSession::start(local, offer));
    let (leg, keep_alive) = accept_with_keep_alive(
        http,
        skype_token,
        &notification,
        me.as_ref(),
        video,
        microphone_on,
    )
    .await?;
    let webrtc = match media.await {
        Ok(Ok(session)) => {
            session.set_muted(!microphone_on);
            session.set_local_sdp(&sdp);
            Some(session)
        }
        Ok(Err(e)) => {
            tracing::warn!("WebRTC audio failed: {:#}", e);
            None
        }
        Err(e) => {
            tracing::warn!("WebRTC audio task failed: {e}");
            None
        }
    };
    Ok(ActiveCall {
        notification,
        forked: me.is_some(),
        call_leg: leg.url,
        keep_alive,
        audio: None,
        webrtc,
        video: None,
        started: Instant::now(),
        me,
        hold_link: leg.hold,
        resume_link: None,
        transfer_link: leg.transfer,
        renegotiation_link: leg.renegotiation,
    })
}

/// Accept the call and, for forked calls, keep the accepted leg alive.
async fn accept_with_keep_alive(
    http: &reqwest::Client,
    skype_token: &str,
    notification: &CallNotification,
    me: Option<&LocalParticipant>,
    with_video: bool,
    microphone_on: bool,
) -> Result<(CallLeg, Option<tokio::task::JoinHandle<()>>)> {
    let leg = match me {
        Some(me) => accept_v2(http, skype_token, notification, me, with_video).await,
        None => {
            signaling::accept_call_with(http, skype_token, notification, with_video, microphone_on)
                .await
                .map(|()| CallLeg::default())
        }
    }
    .context("Call acceptance failed")?;
    // The call controller drops legs that stop sending keep-alives.
    let keep_alive = leg.url.clone().map(|url| {
        let secs = leg
            .keep_alive_secs
            .unwrap_or(DEFAULT_KEEP_ALIVE_SECS)
            .clamp(15, 600);
        let (http, token) = (http.clone(), skype_token.to_string());
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(std::time::Duration::from_secs(secs)).await;
                let body = serde_json::json!({});
                let sent = cc_request(
                    &http,
                    &token,
                    reqwest::Method::POST,
                    &url,
                    &body,
                    "Call keep-alive",
                );
                if let Err(e) = sent.await {
                    tracing::warn!("{:#}", e);
                }
            }
        })
    });

    Ok((leg, keep_alive))
}

fn modalities(video: bool) -> serde_json::Value {
    if video {
        serde_json::json!(["Audio", "Video"])
    } else {
        serde_json::json!(["Audio"])
    }
}

/// Our identity for a forked call: MRI and name from the sign-in, the
/// participant id the service assigned us, and the live Trouter endpoint.
fn local_participant(forked: Option<&serde_json::Value>) -> Result<LocalParticipant> {
    let config = crate::config::Config::load()?;
    let oid = config
        .object_id()
        .context("Signed-in user has no object id")?;
    let (trouter_surl, endpoint_id) =
        crate::trouter::current_endpoint().context("Push channel is not connected")?;
    let participant_id = forked
        .and_then(|v| str_at(v, "/callNotification/to/participantId"))
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    Ok(LocalParticipant {
        id: format!("8:orgid:{oid}"),
        display_name: config.display_name().unwrap_or_default(),
        endpoint_id,
        participant_id,
        trouter_surl,
    })
}

fn invitation_link(
    n: &CallNotification,
    pick: fn(&super::CallLinks) -> Option<String>,
) -> Option<String> {
    n.call_invitation.as_ref()?.links.as_ref().and_then(pick)
}

async fn send_media_answer_v2(
    http: &reqwest::Client,
    skype_token: &str,
    n: &CallNotification,
    me: &LocalParticipant,
    sdp: &str,
    video: bool,
) -> Result<()> {
    let url = invitation_link(n, |l| l.media_answer.clone()).context("No mediaAnswer link")?;
    let body = serde_json::json!({
        "mediaAnswer": {
            "callModalities": modalities(video),
            "sender": me.json(),
            "links": { "mediaAcknowledgement": me.callback("call/mediaAcknowledgement/") },
            "mediaContent": { "blob": sdp, "contentType": "application/sdp" },
        },
        "debugContent": { "endpointId": me.endpoint_id },
    });
    cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        &url,
        &body,
        "Media answer",
    )
    .await?;
    Ok(())
}

async fn accept_v2(
    http: &reqwest::Client,
    skype_token: &str,
    n: &CallNotification,
    me: &LocalParticipant,
    video: bool,
) -> Result<CallLeg> {
    let url = invitation_link(n, |l| l.acceptance.clone()).context("No acceptance link")?;
    let body = serde_json::json!({
        "callAcceptance": {
            "acceptedBy": me.json(),
            "acceptedCallModalities": modalities(video),
            "capabilities": null,
            "endpointCapabilities": ENDPOINT_CAPABILITIES,
            "links": {
                "mediaRenegotiation": me.callback("call/mediaRenegotiation/"),
                "transfer": me.callback("call/transfer/"),
                "replacement": me.callback("call/replacement/"),
                "balanceUpdate": me.callback("call/balanceUpdate/"),
                "retargetCompletion": me.callback("call/retargetCompletion/"),
                "controlVideoStreaming": me.callback("call/controlVideoStreaming/"),
                "updateMediaDescriptions": me.callback("call/updateMediaDescriptions/"),
            },
        },
    });
    let reply = cc_request(
        http,
        skype_token,
        reqwest::Method::POST,
        &url,
        &body,
        "Call acceptance",
    )
    .await?;
    let ack = reply.get("callAcceptanceAcknowledgement").unwrap_or(&reply);
    let shape: Vec<&String> = ack
        .as_object()
        .map(|o| o.keys().collect())
        .unwrap_or_default();
    let links: Vec<&String> = ack
        .get("links")
        .and_then(|l| l.as_object())
        .map(|o| o.keys().collect())
        .unwrap_or_default();
    tracing::info!(?shape, ?links, "acceptance reply");
    Ok(CallLeg {
        url: str_at(ack, "/links/callLeg"),
        hold: str_at(ack, "/links/hold"),
        transfer: str_at(ack, "/links/transfer"),
        renegotiation: str_at(ack, "/links/mediaRenegotiation").filter(|l| is_service_link(l)),
        keep_alive_secs: ack.get("callKeepAliveInterval").and_then(|v| v.as_u64()),
    })
}

/// The accepted call leg: where keep-alives and the hang-up go.
#[derive(Debug, Clone, Default)]
struct CallLeg {
    url: Option<String>,
    /// Where Hold goes (`links.hold`).
    hold: Option<String>,
    /// Where Transfer goes (`links.transfer`).
    transfer: Option<String>,
    /// Where our re-offers go (`links.mediaRenegotiation`).
    renegotiation: Option<String>,
    keep_alive_secs: Option<u64>,
}

/// Keep-alive period when the service does not name one.
const DEFAULT_KEEP_ALIVE_SECS: u64 = 45;

/// Whether a call event is the other side's re-offer.
pub fn is_renegotiation_event(json: &str) -> bool {
    serde_json::from_str::<serde_json::Value>(json).is_ok_and(|v| {
        v.get("callAgentPath")
            .and_then(|p| p.as_str())
            .is_some_and(|p| p.starts_with("call/mediaRenegotiation"))
            || v.pointer("/body/mediaNegotiation").is_some()
    })
}

/// Whether a call event says the call is over (remote hang-up, cancel
/// while ringing, or the conversation ending).
pub fn is_call_end_event(json: &str) -> bool {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return false;
    };
    let path = v
        .get("callAgentPath")
        .and_then(|p| p.as_str())
        .unwrap_or_default();
    path.starts_with("call/end")
        || path.starts_with("conversation/conversationEnd")
        || v.get("callEnd").is_some()
        || v.pointer("/body/callEnd").is_some()
}

/// The HTTP client and Skype token call signalling needs, loaded (and
/// renewed when expired) from the stored sign-in.
pub struct CallAuth {
    http: reqwest::Client,
    skype_token: String,
}

impl CallAuth {
    pub async fn load() -> Result<Self> {
        use crate::config::Config;
        let mut config = Config::load()?;
        if config.get_skype_token().is_none_or(|t| t.is_expired()) {
            crate::auth::oauth::refresh()
                .await
                .context("Token refresh failed")?;
            config = Config::load()?;
        }
        let skype_token = config.get_skype_token().context("Not signed in")?.token;
        Ok(Self {
            http: reqwest::Client::new(),
            skype_token,
        })
    }

    pub async fn answer(
        &self,
        call: IncomingCall,
        with_video: bool,
        microphone_on: bool,
    ) -> Result<ActiveCall> {
        answer(
            &self.http,
            &self.skype_token,
            call,
            with_video,
            microphone_on,
        )
        .await
    }

    pub async fn decline(&self, call: &IncomingCall) -> Result<()> {
        decline(&self.http, &self.skype_token, call).await
    }

    /// For a forked call (Teams web's), fetch the full invitation while it
    /// rings, as Teams does, so the toast can tell a video call; answering
    /// then reuses it. Returns whether the caller is sending video.
    pub async fn probe_video(&self, call: &mut IncomingCall) -> bool {
        if call.notification.is_none()
            && call.attached.is_none()
            && let Some(v) = call.forked.clone()
        {
            let attached = async {
                let me = local_participant(Some(&v))?;
                attach(&self.http, &self.skype_token, &v, &me).await
            }
            .await;
            match attached {
                Ok(n) => call.attached = Some(n),
                Err(e) => tracing::info!("Early attach failed: {:#}", e),
            }
        }
        call.has_video()
    }

    pub async fn hang_up(&self, call: ActiveCall) -> Result<()> {
        call.hang_up(&self.http, &self.skype_token).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn invitation(modalities: &str, name: &str) -> String {
        format!(
            r#"{{"callInvitation":{{"callModalities":{modalities},"links":{{"acceptance":"https://cc/accept","end":"https://cc/end"}}}},
               "participants":{{"from":{{"id":"8:orgid:abc","displayName":"{name}"}}}},
               "debugContent":{{"callId":"call-1"}}}}"#
        )
    }

    #[test]
    fn replies_to_our_reoffers_are_recognised() {
        let ok = r#"{"callAgentPath":"call/mediaAnswer/","body":{"mediaAnswer":{"mediaContent":{"blob":"v=0 answer"},"links":{"mediaAcknowledgement":"https://api.flightproxy.teams.microsoft.com/ack"}}}}"#;
        assert_eq!(
            reoffer_reply(ok).unwrap().unwrap(),
            ReofferAnswer {
                sdp: "v=0 answer".into(),
                ack: Some("https://api.flightproxy.teams.microsoft.com/ack".into())
            }
        );
        // An acknowledgement link that isn't Teams' is dropped.
        let elsewhere = ok.replace("api.flightproxy.teams.microsoft.com", "evil.example");
        assert_eq!(reoffer_reply(&elsewhere).unwrap().unwrap().ack, None);
        let no = r#"{"callAgentPath":"call/rejection/","body":{"mediaRejection":{"code":488,"phrase":"declined"}}}"#;
        assert!(
            reoffer_reply(no)
                .unwrap()
                .unwrap_err()
                .to_string()
                .contains("declined")
        );
        let empty = r#"{"callAgentPath":"call/mediaAnswer/","body":{}}"#;
        assert!(reoffer_reply(empty).unwrap().is_err());
        assert!(reoffer_reply(r#"{"callAgentPath":"call/end/","body":{}}"#).is_none());
        assert_eq!(
            share_modalities(true, false),
            serde_json::json!(["Audio", "ScreenSharer"])
        );
        assert_eq!(
            share_modalities(false, true),
            serde_json::json!(["Audio", "Video", "ScreenViewer"])
        );
    }

    #[test]
    fn parses_caller_and_modalities() {
        let call =
            IncomingCall::parse(&invitation(r#"["Audio","Video"]"#, "Ada Lovelace")).unwrap();
        assert_eq!(call.caller_name(), "Ada Lovelace");
        assert_eq!(call.caller_id().as_deref(), Some("8:orgid:abc"));
        assert_eq!(call.call_id().as_deref(), Some("call-1"));
        assert!(call.has_video());
        let audio_only = IncomingCall::parse(&invitation(r#"["Audio"]"#, " ")).unwrap();
        assert!(!audio_only.has_video());
        assert_eq!(audio_only.caller_name(), "Unknown caller");
    }

    #[test]
    fn parses_forked_call_notifications() {
        let forked = r#"{"callNotification":{"from":{"id":"8:orgid:abc","displayName":"Grace Hopper"},
            "to":{"participantId":"p-1"},"links":{"attach":"https://cc/attach","reject":"https://cc/reject"}},
            "conversationInvitation":{"conversationController":"https://conv/1"},
            "debugContent":{"callId":"call-2"}}"#;
        let call = IncomingCall::parse(forked).unwrap();
        assert_eq!(call.caller_name(), "Grace Hopper");
        assert_eq!(call.caller_id().as_deref(), Some("8:orgid:abc"));
        assert_eq!(call.call_id().as_deref(), Some("call-2"));
        assert!(!call.has_video());
    }

    #[test]
    fn recognises_call_end_events() {
        assert!(is_call_end_event(
            r#"{"callAgentPath":"call/end/","body":{}}"#
        ));
        assert!(is_call_end_event(
            r#"{"callAgentPath":"conversation/conversationEnd/","body":null}"#
        ));
        assert!(is_call_end_event(r#"{"callEnd":{"code":487}}"#));
        assert!(is_renegotiation_event(
            r#"{"callAgentPath":"call/mediaRenegotiation/","body":{}}"#
        ));
        assert_eq!(
            retarget_hold(
                r#"{"body":{"retargetCompleted":{"code":0,"audioBotType":"audioPlayback"}}}"#
            ),
            Some(true)
        );
        assert_eq!(
            retarget_hold(
                r#"{"body":{"retargetCompleted":{"code":410,"audioBotType":"audioPlayback"}}}"#
            ),
            Some(false)
        );
        assert_eq!(
            retarget_hold(r#"{"body":{"retargetCompleted":{"code":0}}}"#),
            Some(false)
        );
        assert_eq!(retarget_hold(r#"{"body":{}}"#), None);
        assert_eq!(
            transfer_outcome(
                r#"{"callAgentPath":"call/transferCompletion/","body":{"transferCompletion":{"code":0}}}"#
            ),
            Some(Ok(()))
        );
        assert_eq!(
            transfer_outcome(
                r#"{"callAgentPath":"call/transferCompletion/","body":{"transferCompletion":{"code":480,"phrase":"No answer"}}}"#
            ),
            Some(Err("No answer".into()))
        );
        assert_eq!(
            transfer_outcome(r#"{"callAgentPath":"call/end/","body":{}}"#),
            None
        );
        assert!(!is_renegotiation_event(
            r#"{"callAgentPath":"call/end/","body":{}}"#
        ));
        assert!(is_service_link(
            "https://api.flightproxy.teams.microsoft.com/api/v2/ep/x/answer"
        ));
        assert!(is_service_link("https://cc-uswe-01.cc.skype.com/cc/v1/x"));
        assert!(!is_service_link(
            "http://api.flightproxy.teams.microsoft.com/x"
        ));
        assert!(!is_service_link(
            "https://teams.microsoft.com.evil.example/x"
        ));
        assert!(!is_service_link(
            "https://evil.example/?h=.teams.microsoft.com"
        ));
        assert!(!is_call_end_event(
            r#"{"callAgentPath":"call/mediaAcknowledgement/","body":{}}"#
        ));
        assert!(!is_call_end_event("nope"));
    }

    #[test]
    fn events_without_an_acceptance_link_are_not_invitations() {
        let no_accept = r#"{"callInvitation":{"links":{"end":"https://cc/end"}}}"#;
        assert!(IncomingCall::parse(no_accept).is_none());
        assert!(IncomingCall::parse(r#"{"callEnded":{}}"#).is_none());
    }
}
