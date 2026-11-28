//! Call signaling HTTP operations — accept, send media answer, end call.
//!
//! Includes the two-phase conversation API for call placement via epconv.

use anyhow::{Context, Result};

use super::CallNotification;
use uuid;

/// What OST's calling stack supports (Teams' `ClientEndpointCapabilities`):
/// breakout rooms (2), attendance tracking (8), streaming (32), end-to-end
/// encryption (64), shared line appearance v2 (128), room distributions
/// (512), streaming promotion (1024), room moves (4096), presenter
/// capability reduction (8192), nudges from streaming into real time
/// (131072), lobby chat (262144), reactions (524288) and presenter slide
/// control (8388608). Teams on the web adds `blockPresenterJoinInEvents`
/// (16384): the service then refuses its presenters in town halls (403,
/// subCode 5131, "Joining a town hall as a presenter or organizer isn't
/// available on the web"); the desktop app, like OST, doesn't.
pub const CLIENT_ENDPOINT_CAPABILITIES: u64 =
    2 | 8 | 32 | 64 | 128 | 512 | 1024 | 4096 | 8192 | 131072 | 262144 | 524288 | 8388608;

/// Teams' `supportsCollabLeader`: the call may elect this endpoint to make
/// a Meet now's notes (the conversation's `collabDetails.collabLeaders`,
/// acknowledged with the `collabLeaders.notes` meeting state). Without it
/// the service refuses the acknowledgement (400, subCode 6179, "The leader
/// to be confirmed is not the same as who's elected").
pub const SUPPORTS_COLLAB_LEADER: u64 = 65536;

/// The capabilities a join or call sends: Teams adds supportsCollabLeader
/// when ECS `meetingNotes.enableMeetingNotesInMeetNowCall` is on.
pub fn client_endpoint_capabilities() -> u64 {
    let notes = crate::api::ecs::setting("meetingNotes", "enableMeetingNotesInMeetNowCall")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    CLIENT_ENDPOINT_CAPABILITIES | if notes { SUPPORTS_COLLAB_LEADER } else { 0 }
}

// Common headers for Teams calling API requests.
// TODO: region headers are hardcoded to AMER — derive from config for other tenants.
pub(crate) const SKYPE_CLIENT_HEADER: &str =
    "SkypeSpaces/1415/teams-cli/TsCallingVersion=2025.49.01.15";
pub(crate) const TEAMS_PARTITION: &str = "amer03";
pub(crate) const TEAMS_REGION: &str = "amer";
pub(crate) const TEAMS_RING: &str = "general";

/// The content type of the SDP offers Teams' own clients send. A call's
/// offers must all use the same one: the call controller ends a call whose
/// re-offer changes it (OfferContentTypeNotConsistent), and Teams' media
/// stack takes re-offers only in this one.
pub const OFFER_CONTENT_TYPE: &str = "application/sdp-ngc-1.0";

/// Response from phase 1 (create conversation).
#[derive(Debug)]
pub struct ConversationCreated {
    /// URL to POST phase 2 to (the conversationController).
    pub conversation_controller: String,
    /// The exact addParticipant URL from the response links (if present).
    pub add_participant_url: Option<String>,
    /// Full response body for debugging.
    pub response_body: String,
}

/// Response from phase 2 (join with SDP).
#[derive(Debug)]
pub struct ConversationJoined {
    /// CC active URL from response headers (x-microsoft-skype-proxy-cluster-context).
    pub cc_active_url: Option<String>,
    /// Full response body for debugging.
    pub response_body: String,
}

/// Parameters for the two-phase conversation call placement.
pub struct ConversationCallParams<'a> {
    pub ic3_token: &'a str,
    pub trouter_surl: &'a str,
    pub caller_mri: &'a str,
    pub caller_display_name: &'a str,
    pub endpoint_id: &'a str,
    pub participant_id: &'a str,
    pub thread_id: &'a str,
    pub chain_id: &'a str,
    pub message_id: &'a str,
    /// OID (object ID) extracted from caller MRI, e.g. the GUID part of "8:orgid:{guid}".
    pub caller_oid: &'a str,
    pub tenant_id: &'a str,
}

/// Build a Trouter callback URL for a specific path.
///
/// Each callback gets a unique 8-hex-char hash (matches Teams web client pattern).
/// Pattern: `{trouter_surl}callAgent/{endpoint_id}/{hash}/{path}`
/// Every `…/links/<name>` path in a response, for diagnostics.
fn link_names(v: &serde_json::Value) -> Vec<String> {
    fn walk(v: &serde_json::Value, path: &str, out: &mut Vec<String>) {
        if let Some(o) = v.as_object() {
            for (k, c) in o {
                let p = format!("{path}/{k}");
                if path.ends_with("/links") {
                    out.push(p.clone());
                }
                walk(c, &p, out);
            }
        }
    }
    let mut out = Vec::new();
    walk(v, "", &mut out);
    out
}

pub(crate) fn trouter_callback(trouter_surl: &str, endpoint_id: &str, path: &str) -> String {
    let hash = format!("{:08x}", {
        // Simple hash from endpoint_id + path to produce unique per-path values
        let mut h: u32 = 0x811c9dc5; // FNV-1a init
        for b in endpoint_id.bytes().chain(path.bytes()) {
            h ^= b as u32;
            h = h.wrapping_mul(0x01000193);
        }
        h
    });
    format!(
        "{}callAgent/{}/{}/{}",
        trouter_surl, endpoint_id, hash, path
    )
}

/// Phase 1: Create a conversation by POSTing to /api/v2/epconv.
///
/// Returns the conversationController URL from the response.
pub async fn create_conversation(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
) -> Result<ConversationCreated> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);
    let cause_id = &params.message_id[..8.min(params.message_id.len())];

    // Note: conversationRequest contains only subject/roster/properties/links.
    // Other fields (groupChat, participants, etc.) are siblings, not nested inside.
    let mut payload = serde_json::json!({
        "conversationRequest": {
            "subject": null,
            "roster": {
                "type": "Delta",
                "rosterUpdate": tc("conversation/rosterUpdate/")
            },
            "properties": {
                "allowConversationWithoutHost": true,
                "enableGroupCallEventMessages": true,
                "enableGroupCallUpgradeMessage": false,
                "enableGroupCallMeetupGeneration": true
            },
            "links": {
                "conversationEnd": tc("conversation/conversationEnd/"),
                "conversationUpdate": tc("conversation/conversationUpdate/"),
                "localParticipantUpdate": tc("conversation/localParticipantUpdate/"),
                "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
                "addParticipantFailure": tc("conversation/addParticipantFailure/"),
                "receiveMessage": tc("conversation/receiveMessage/")
            }
        },
        "groupContext": null,
        "groupChat": {
            "threadId": params.thread_id,
            "messageId": null
        },
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            }
        },
        "capabilities": null,
        // Capability bitmasks captured from Teams web client traffic
        "endpointCapabilities": 73463,
        "clientEndpointCapabilities": client_endpoint_capabilities(),
        "endpointMetadata": { "holographicCapabilities": 3 },
        "meetingInfo": null,
        "endpointState": {
            "endpointStateSequenceNumber": 0,
            "endpointProperties": {
                "additionalEndpointProperties": {
                    "infoShownInReportMode": "FullInformation"
                }
            }
        },
        "debugContent": {
            "ecsEtag": "\"0\"",
            "causeId": cause_id
        }
    });
    super::room_mode::mark_device(&mut payload);
    super::consumer::mark_application(&mut payload);

    tracing::info!("Phase 1: POST {} (create conversation)", epconv_url);
    tracing::debug!(
        "Phase 1 payload: {}",
        serde_json::to_string_pretty(&payload).unwrap_or_default()
    );

    let resp = http
        .post(epconv_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", params.message_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Phase 1 POST to epconv failed")?;

    let status = resp.status();

    // Extract conversationController from response headers or body
    let headers = resp.headers().clone();
    let body = resp.text().await.unwrap_or_default();

    tracing::info!("Phase 1 response: {} ({} bytes)", status, body.len());
    tracing::debug!("Phase 1 response body: {}", &body[..body.len().min(2000)]);
    for (k, v) in headers.iter() {
        tracing::debug!(
            "Phase 1 header: {}: {}",
            k,
            v.to_str().unwrap_or("(binary)")
        );
    }

    if !status.is_success() {
        anyhow::bail!("Phase 1 epconv failed ({}): {}", status, body);
    }

    // Parse conversationController from response body
    let resp_json: serde_json::Value =
        serde_json::from_str(&body).context("Phase 1 response is not valid JSON")?;

    let conv_controller = resp_json
        .pointer("/conversationController")
        .or_else(|| resp_json.pointer("/conversationResponse/conversationController"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    // Also check Location header
    let conv_controller = conv_controller
        .or_else(|| {
            headers
                .get("location")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string())
        })
        .context("No conversationController in phase 1 response")?;

    let add_participant_url = resp_json
        .pointer("/links/addParticipant")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    tracing::info!(
        "Phase 1 success: conversationController = {}, addParticipant link = {:?}",
        conv_controller,
        add_participant_url
    );

    Ok(ConversationCreated {
        conversation_controller: conv_controller,
        add_participant_url,
        response_body: body,
    })
}

/// Phase 2: Join the conversation with an SDP offer.
///
/// POSTs to the conversationController URL from phase 1.
pub async fn join_conversation_with_sdp(
    http: &reqwest::Client,
    conversation_controller: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
) -> Result<ConversationJoined> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);
    let cause_id = &params.message_id[..8.min(params.message_id.len())];

    // Same structure as phase 1: conversationRequest contains only
    // subject/roster/properties/links. Other fields are siblings.
    let mut payload = serde_json::json!({
        "conversationRequest": {
            "conversationType": null,
            "subject": "",
            "suppressDialout": true,
            "roster": {
                "type": "Delta",
                "rosterUpdate": tc("conversation/rosterUpdate/")
            },
            "properties": {
                "allowConversationWithoutHost": true,
                "enableGroupCallEventMessages": true,
                "enableGroupCallUpgradeMessage": false,
                "enableGroupCallMeetupGeneration": true
            },
            "links": {
                "conversationEnd": tc("conversation/conversationEnd/"),
                "conversationUpdate": tc("conversation/conversationUpdate/"),
                "localParticipantUpdate": tc("conversation/localParticipantUpdate/"),
                "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
                "addParticipantFailure": tc("conversation/addParticipantFailure/"),
                "addModalitySuccess": tc("conversation/addModalitySuccess/"),
                "addModalityFailure": tc("conversation/addModalityFailure/"),
                "confirmUnmute": tc("conversation/confirmUnmute/"),
                "receiveMessage": tc("conversation/receiveMessage/")
            }
        },
        "groupContext": null,
        "groupChat": {
            "threadId": params.thread_id,
            "messageId": null
        },
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            },
            "to": []
        },
        // Capability bitmasks captured from Teams web client traffic
        "capabilities": null,
        "endpointCapabilities": 73463,
        "clientEndpointCapabilities": client_endpoint_capabilities(),
        "endpointMetadata": { "holographicCapabilities": 3 },
        "meetingInfo": {
            "organizerId": params.caller_oid,
            "tenantId": params.tenant_id
        },
        "endpointState": {
            "endpointStateSequenceNumber": 0,
            "endpointProperties": {
                "preheatProperties": 1,
                "additionalEndpointProperties": {
                    "infoShownInReportMode": "FullInformation"
                }
            }
        },
        "callInvitation": {
            "callModalities": ["Audio"],
            "replaces": null,
            "transferor": null,
            "links": {
                "progress": tc("call/progress/"),
                "mediaAnswer": tc("call/mediaAnswer/"),
                "acceptance": tc("call/acceptance/"),
                "redirection": tc("call/redirection/"),
                "end": tc("call/end/")
            },
            "clientContentForMediaController": {
                "controlVideoStreaming": tc("call/controlVideoStreaming/"),
                "csrcInfo": tc("call/csrcInfo/"),
                "dominantSpeakerInfo": tc("call/dominantSpeakerInfo/")
            },
            "pstnContent": {
                "emergencyCallCountry": "",
                "platformName": "teams-cli",
                "publicApiCall": false
            },
            "mediaContent": {
                "contentType": "application/sdp",
                "blob": sdp_offer
            }
        },
        "debugContent": {
            "ecsEtag": "\"0\"",
            "causeId": cause_id
        }
    });
    super::room_mode::mark_device(&mut payload);
    super::consumer::mark_application(&mut payload);

    tracing::info!("Phase 2: POST {} (join with SDP)", conversation_controller);
    tracing::debug!(
        "Phase 2 payload: {}",
        serde_json::to_string_pretty(&payload).unwrap_or_default()
    );

    let resp = http
        .post(conversation_controller)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", params.message_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Phase 2 POST to conversationController failed")?;

    let status = resp.status();
    let headers = resp.headers().clone();
    let body = resp.text().await.unwrap_or_default();

    tracing::info!("Phase 2 response: {} ({} bytes)", status, body.len());
    tracing::debug!("Phase 2 response body: {}", &body[..body.len().min(2000)]);

    if !status.is_success() {
        anyhow::bail!("Phase 2 join failed ({}): {}", status, body);
    }

    let cc_active_url = headers
        .get("x-microsoft-skype-proxy-cluster-context")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    tracing::info!("Phase 2 success. CC active URL: {:?}", cc_active_url);

    Ok(ConversationJoined {
        cc_active_url,
        response_body: body,
    })
}

/// Accept an incoming call by POSTing to the acceptance URL (audio only,
/// microphone reported off, as the CLI's echo tests expect).
pub async fn accept_call(
    http: &reqwest::Client,
    skype_token: &str,
    notification: &CallNotification,
) -> Result<()> {
    accept_call_with(http, skype_token, notification, false, false).await
}

/// Accept an incoming call, stating which modalities we take and whether
/// our microphone is on.
pub async fn accept_call_with(
    http: &reqwest::Client,
    skype_token: &str,
    notification: &CallNotification,
    video: bool,
    microphone_on: bool,
) -> Result<()> {
    let invitation = notification
        .call_invitation
        .as_ref()
        .context("No callInvitation in notification")?;
    let links = invitation
        .links
        .as_ref()
        .context("No links in callInvitation")?;
    let acceptance_url = links
        .acceptance
        .as_ref()
        .context("No acceptance URL in links")?;

    let modalities: &[&str] = if video {
        &["Audio", "Video"]
    } else {
        &["Audio"]
    };
    let payload = serde_json::json!({
        "acceptedCallModalities": modalities,
        "endpointMetadata": {
            "isCallMediaCaptured": microphone_on,
            "isMicrophoneOn": microphone_on
        }
    });

    tracing::info!("Accepting call -> POST {}", acceptance_url);

    let resp = http
        .post(acceptance_url)
        .header("X-Skypetoken", skype_token)
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await
        .context("Failed to POST acceptance")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if status.is_success() {
        tracing::info!("Call accepted ({}): {}", status, body);
        Ok(())
    } else {
        anyhow::bail!("Call acceptance failed ({}): {}", status, body);
    }
}

/// Send the SDP media answer to the mediaAnswer URL.
pub async fn send_media_answer(
    http: &reqwest::Client,
    skype_token: &str,
    notification: &CallNotification,
    sdp_answer: &str,
) -> Result<()> {
    let invitation = notification
        .call_invitation
        .as_ref()
        .context("No callInvitation in notification")?;
    let links = invitation
        .links
        .as_ref()
        .context("No links in callInvitation")?;
    let media_answer_url = links
        .media_answer
        .as_ref()
        .context("No mediaAnswer URL in links")?;

    let payload = serde_json::json!({
        "mediaContent": {
            "blob": sdp_answer,
            "contentType": "application/sdp"
        }
    });

    tracing::info!("Sending media answer -> POST {}", media_answer_url);

    let resp = http
        .post(media_answer_url)
        .header("X-Skypetoken", skype_token)
        .header("Content-Type", "application/json")
        .json(&payload)
        .send()
        .await
        .context("Failed to POST media answer")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if status.is_success() {
        tracing::info!("Media answer sent ({}): {}", status, body);
        Ok(())
    } else {
        anyhow::bail!("Media answer failed ({}): {}", status, body);
    }
}

/// Build the standard CC signaling callback links for a call leg.
///
/// Used by both `acknowledge_call_acceptance` and `register_cc_callbacks`.
fn cc_call_links(tc: &dyn Fn(&str) -> String) -> serde_json::Value {
    serde_json::json!({
        "links": {
            "mediaAcknowledgement": tc("call/mediaAcknowledgement/"),
            "rejection": tc("call/rejection/"),
            "acknowledgement": tc("call/acknowledgement/"),
            "mediaRenegotiation": tc("call/mediaRenegotiation/"),
            "replacement": tc("call/replacement/"),
            "progress": tc("call/progress/"),
            "mediaAnswer": tc("call/mediaAnswer/"),
            "newMediaOffer": tc("call/newMediaOffer/"),
            "redirection": tc("call/redirection/"),
            "balanceUpdate": tc("call/balanceUpdate/"),
            "acceptance": tc("call/acceptance/"),
            "controlVideoStreaming": tc("call/controlVideoStreaming/"),
            "dominantSpeakerInfo": tc("call/dominantSpeakerInfo/"),
            "csrcInfo": tc("call/csrcInfo/"),
            "end": tc("call/end/"),
            "retargetCompletion": tc("call/retargetCompletion/"),
            "transfer": tc("call/transfer/"),
            "transferAcceptance": tc("call/transferAcceptance/"),
            "transferCompletion": tc("call/transferCompletion/"),
            "holdCompletion": tc("call/holdCompletion/"),
            "resumeCompletion": tc("call/resumeCompletion/"),
            "call": tc("call/updateMediaDescriptions"),
            "monitorCompletion": tc("call/monitorCompletion/")
        },
        "clientContentForMediaController": {
            "controlVideoStreaming": tc("call/controlVideoStreaming/"),
            "csrcInfo": tc("call/csrcInfo/")
        }
    })
}

/// Phase 3: Acknowledge call acceptance.
///
/// POST to the acknowledgement URL from the callAcceptance Trouter callback.
/// This tells the Call Controller we received the SDP answer and keeps the call alive.
/// Without this, CC times out and kills the call (error 430/subCode 10065).
/// Whether a 1:1 call's acceptance shows the callee never answered: the call
/// controller made it a hostless ad-hoc meeting (`state.isMultiParty`,
/// `isHostless`) holding only the caller. Seen with the Echo bot about 1
/// call in 5 (TASK-0018): the 1:1 POST got 201 Created instead of 200 OK,
/// the acceptance came 10 s later, and the media processor's stream sent
/// no packets because nobody else was in the conversation.
pub fn became_hostless_meeting(ack: &serde_json::Value) -> bool {
    let state = &ack["state"];
    state["isMultiParty"] == true && state["isHostless"] == true
}

pub async fn acknowledge_call_acceptance(
    http: &reqwest::Client,
    acknowledgement_url: &str,
    params: &ConversationCallParams<'_>,
) -> Result<serde_json::Value> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);

    tracing::info!(
        "Phase 3a: Acknowledging call acceptance -> POST {}",
        acknowledgement_url
    );

    let resp = http
        .post(acknowledgement_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", params.message_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .json(&serde_json::json!({
            "callAcceptanceAcknowledgement": cc_call_links(&tc)
        }))
        .send()
        .await
        .context("Failed to POST call acceptance acknowledgement")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if status.is_success() {
        tracing::info!("Call acceptance acknowledged ({}): {}", status, body);
        // 202 Accepted carries no body; 201 Created describes the
        // conversation the call became.
        Ok(serde_json::from_str(&body).unwrap_or(serde_json::Value::Null))
    } else {
        anyhow::bail!(
            "Call acceptance acknowledgement failed ({}): {}",
            status,
            body
        );
    }
}

/// Phase 3b: Register CC signaling callbacks on the call leg.
///
/// POST callParticipantUpdate with Trouter callback links to the callLeg URL.
/// This tells the Call Controller where to send subsequent signaling events
/// (media renegotiation, call end, transfer, etc.).
pub async fn register_cc_callbacks(
    http: &reqwest::Client,
    call_leg_url: &str,
    params: &ConversationCallParams<'_>,
) -> Result<()> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);

    let payload = serde_json::json!({
        "callAcceptanceAcknowledgement": cc_call_links(&tc),
        "callParticipantUpdate": cc_call_links(&tc)
    });

    tracing::info!(
        "Phase 3b: Registering CC callbacks -> POST {}",
        call_leg_url
    );
    tracing::debug!(
        "Phase 3b payload: {}",
        serde_json::to_string_pretty(&payload).unwrap_or_default()
    );

    let resp = http
        .post(call_leg_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", params.message_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .json(&payload)
        .send()
        .await
        .context("Failed to POST CC callback registration")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if status.is_success() {
        tracing::info!("CC callbacks registered ({}): {}", status, body);
        Ok(())
    } else {
        anyhow::bail!("CC callback registration failed ({}): {}", status, body);
    }
}

/// Echo bot MRI (Call Quality Tester).
pub const ECHO_BOT_MRI: &str = "28:cf28171e-fcfd-47e4-a1d6-79460b0b3ca0";

/// Echo bot OID (extracted from the MRI).
const ECHO_BOT_OID: &str = "cf28171e-fcfd-47e4-a1d6-79460b0b3ca0";

/// Build the 1:1 thread ID for a call to the Echo bot.
pub fn echo_thread_id(caller_oid: &str) -> String {
    format!("19:{}_{}@unq.gbl.spaces", caller_oid, ECHO_BOT_OID)
}

/// Start Teams' test call (Settings ▸ Devices ▸ Make a test call): as
/// Teams' `placeEchoBotCall` does, a group call in the 1:1 chat with the
/// Echo bot (`echo_thread_id`), nobody rung, scenario
/// `UserInitiatedTestCall`; the bot is invited next ([`invite_echo_bot`]).
pub async fn create_echo_call(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
) -> Result<(ConversationCreated, ConversationJoined)> {
    let opts = CreateOptions {
        group_chat: true,
        meeting_message_id: None,
        to: Vec::new(),
        conversation_type: None,
        invitation_type: None,
        suppress_dialout: true,
        subject: None,
        meetup: false,
        meeting_info: None,
        scenario: Some("UserInitiatedTestCall"),
        two_step: false,
        preheat: false,
        extras: None,
        meeting_data: None,
        meeting_data_wait: None,
        conversation_url: None,
        as_attendee: false,
    };
    create_call_with(http, epconv_url, params, sdp_offer, &opts).await
}

/// Invite the Echo bot into the conversation via POST /conv/{id}/add.
///
/// This is step 3 of the Echo call flow: after creating the conversation (epconv)
/// and joining with SDP, we add the Echo bot as a participant with the 1:1 thread context.
pub async fn invite_echo_bot(
    http: &reqwest::Client,
    conversation_controller: &str,
    params: &ConversationCallParams<'_>,
) -> Result<()> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);

    // Derive /add URL from conversation controller
    let add_url = if let Some(idx) = conversation_controller.find('?') {
        let (path, query) = conversation_controller.split_at(idx);
        format!("{}/add{}", path.trim_end_matches('/'), query)
    } else {
        format!("{}/add", conversation_controller.trim_end_matches('/'))
    };

    let echo_participant_id = uuid::Uuid::new_v4().to_string();

    let payload = serde_json::json!({
        "disableUnmute": false,
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            },
            "to": [{
                "id": ECHO_BOT_MRI,
                "participantId": echo_participant_id
            }]
        },
        "participantInvitationData": {},
        "replacementDetails": null,
        "groupContext": null,
        "groupChat": {
            "threadId": params.thread_id,
            "messageId": null
        },
        "links": {
            "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
            "addParticipantFailure": tc("conversation/addParticipantFailure/")
        }
    });

    // Fresh message-id: the conv server uses this for deduplication; reusing the
    // epconv message-id would cause a cached empty response.
    let echo_bot_msg_id = uuid::Uuid::new_v4().to_string();

    tracing::info!(
        "Inviting Echo bot -> POST {} (msg_id={})",
        add_url,
        echo_bot_msg_id
    );
    tracing::debug!(
        "Echo bot invite payload: {}",
        serde_json::to_string_pretty(&payload).unwrap_or_default()
    );

    let resp = http
        .post(&add_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", &echo_bot_msg_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Failed to POST echo bot invite")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    tracing::info!(
        "Echo bot invite response: {} ({} bytes)",
        status,
        body.len()
    );
    tracing::debug!("Echo bot invite response body: {}", body);

    if !status.is_success() {
        anyhow::bail!("Echo bot invite failed ({}): {}", status, body);
    }

    Ok(())
}

/// Create a 1:1 call in a single epconv POST.
///
/// Similar to create_echo_call but without the UserInitiatedTestCall scenario.
/// Used for calling real users by their 1:1 thread ID.
pub async fn create_1to1_call(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
) -> Result<(ConversationCreated, ConversationJoined)> {
    create_1to1_call_to(http, epconv_url, params, sdp_offer, None).await
}

/// Like [`create_1to1_call`], naming the callee in `participants.to` so the
/// conversation service dials them out (as the Teams clients do), instead
/// of inviting them in a second request.
pub async fn create_1to1_call_to(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    callee_mri: Option<&str>,
) -> Result<(ConversationCreated, ConversationJoined)> {
    create_call(http, epconv_url, params, sdp_offer, callee_mri, None).await
}

/// [`create_1to1_call_to`] with a transfer's or an unpark's [`CallExtras`].
pub async fn create_1to1_call_with(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    callee_mri: &str,
    extras: &CallExtras,
) -> Result<(ConversationCreated, ConversationJoined)> {
    create_call(
        http,
        epconv_url,
        params,
        sdp_offer,
        Some(callee_mri),
        Some(extras),
    )
    .await
}

/// Join a scheduled Teams meeting: a call request with no callee, tied to
/// the meeting's chat thread and its message id (`0` for scheduled
/// meetings, from the join link), so the conversation service puts us in
/// the meeting's conversation. The conversation is joined first, then the
/// call, as Teams joins every meeting (from its pre-join screen, and when
/// it moves into a breakout room or back). `preheat`: join it as Teams'
/// pre-join does while its window is open (`endpointProperties.
/// preheatProperties: 1`): the call and its media are set up, but nobody
/// sees us until we make ourselves visible (`OutgoingCall::join_preheated`).
pub async fn join_meeting(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    meeting_message_id: &str,
    organizer: Option<(&str, &str)>,
    how: &MeetingJoinOptions<'_>,
) -> Result<(ConversationCreated, ConversationJoined)> {
    let preheat = how.preheat;
    let opts = CreateOptions {
        group_chat: true,
        meeting_message_id: Some(meeting_message_id),
        to: Vec::new(),
        conversation_type: None,
        invitation_type: None,
        // Nobody is rung when joining a meeting.
        suppress_dialout: true,
        subject: None,
        meetup: false,
        meeting_info: Some(meeting_info(
            organizer,
            (params.caller_oid, params.tenant_id),
        )),
        scenario: None,
        two_step: true,
        preheat,
        extras: None,
        meeting_data: how.meeting_data.clone(),
        meeting_data_wait: how.meeting_data_wait,
        conversation_url: how.conversation_url,
        as_attendee: how.as_attendee,
    };
    create_call_with(http, epconv_url, params, sdp_offer, &opts).await
}

/// How a meeting is joined ([`join_meeting`]).
#[derive(Debug, Default, Clone)]
pub struct MeetingJoinOptions<'a> {
    /// Teams' pre-join preheat (hidden until Join now).
    pub preheat: bool,
    /// Wait this long after the conversation join for its `meetingData`
    /// (Teams' moves into a breakout room send the room's).
    pub meeting_data_wait: Option<std::time::Duration>,
    /// `meetingData` known already.
    pub meeting_data: Option<serde_json::Value>,
    /// The conversation we're in already without a call: the call goes
    /// straight to it (Teams going back to the main meeting it kept).
    pub conversation_url: Option<&'a str>,
    /// Teams' "Preview as Attendee" (a town hall's organizer or presenter
    /// joining as its attendees do, joinEventAsAttendee): the join asks
    /// for the attendee role (`participationPreferences.
    /// requestedEndpointMeetingRoles ["attendee"]`), and the meeting
    /// streams to us.
    pub as_attendee: bool,
}

/// Teams' `participationPreferences` for a join as an attendee.
pub fn attendee_preferences() -> serde_json::Value {
    serde_json::json!({ "requestedEndpointMeetingRoles": ["attendee"] })
}

/// A scheduled meeting's `meetingInfo`, as Teams sends it when joining:
/// the organizer and tenant from the join link's context (ours when the
/// link has none, as for meetings we organize).
pub fn meeting_info(organizer: Option<(&str, &str)>, me: (&str, &str)) -> serde_json::Value {
    let (organizer_id, tenant_id) = organizer.unwrap_or(me);
    serde_json::json!({ "tenantId": tenant_id, "organizerId": organizer_id })
}

/// How a group chat's call is placed (Teams' calling stack 361315 `KX`).
pub enum GroupCallKind {
    /// "Audio call": the members are rung (`participants.to`).
    Ring,
    /// Meet now: a `huddleGroupCall`; the members are nudged
    /// (`participants.invitationType: "nudge"`), not rung.
    Huddle,
    /// Joining the chat's ongoing call (nobody is rung).
    Join,
}

/// Start or join a group chat's call (`groupChat.threadId`), as Teams
/// does for Meet now, Audio call and Join.
pub async fn create_group_call(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    members: &[String],
    kind: GroupCallKind,
) -> Result<(ConversationCreated, ConversationJoined)> {
    let to: Vec<&str> = match kind {
        GroupCallKind::Join => Vec::new(),
        _ => members.iter().map(String::as_str).collect(),
    };
    let opts = CreateOptions {
        group_chat: true,
        meeting_message_id: None,
        to,
        conversation_type: match kind {
            GroupCallKind::Huddle => Some("huddleGroupCall"),
            _ => None,
        },
        invitation_type: match kind {
            GroupCallKind::Huddle => Some("nudge"),
            _ => None,
        },
        suppress_dialout: matches!(kind, GroupCallKind::Join),
        subject: None,
        meetup: false,
        meeting_info: None,
        scenario: None,
        two_step: false,
        preheat: false,
        extras: None,
        meeting_data: None,
        meeting_data_wait: None,
        conversation_url: None,
        as_attendee: false,
    };
    create_call_with(http, epconv_url, params, sdp_offer, &opts).await
}

/// Start a channel's meeting (Teams' Meet now in a channel): an ad hoc
/// meeting on the channel thread, nobody rung, its title as the subject.
/// The call service posts the meeting in the channel (meetup generation)
/// and the meeting is keyed by that post.
pub async fn create_channel_meeting(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    subject: &str,
) -> Result<(ConversationCreated, ConversationJoined)> {
    let opts = CreateOptions {
        group_chat: true,
        meeting_message_id: None,
        to: Vec::new(),
        conversation_type: Some("adHocMeeting"),
        invitation_type: None,
        suppress_dialout: true,
        subject: Some(subject),
        meetup: true,
        meeting_info: None,
        scenario: None,
        two_step: false,
        preheat: false,
        extras: None,
        meeting_data: None,
        meeting_data_wait: None,
        conversation_url: None,
        as_attendee: false,
    };
    create_call_with(http, epconv_url, params, sdp_offer, &opts).await
}

struct CreateOptions<'a> {
    group_chat: bool,
    meeting_message_id: Option<&'a str>,
    to: Vec<&'a str>,
    conversation_type: Option<&'a str>,
    invitation_type: Option<&'a str>,
    suppress_dialout: bool,
    /// The conversation's subject (a channel meeting's title).
    subject: Option<&'a str>,
    /// Have the call service post the meeting in the thread.
    meetup: bool,
    /// A scheduled meeting's `meetingInfo` (its organizer and tenant):
    /// without it the call service starts a new ad hoc meeting organized
    /// by whoever joins.
    meeting_info: Option<serde_json::Value>,
    /// The call's scenario (`UserInitiatedTestCall` for the test call).
    scenario: Option<&'a str>,
    /// Join the meeting's conversation first, then its call (Teams on the
    /// web, captured 2026-11-16: `POST epconv` without a call, then the
    /// call `POST`ed to the conversation it answers with). Joined that
    /// way the meeting's details carry its dial-in (`pstnDetails`) and
    /// PSTN capability; created and joined in one go they come without.
    two_step: bool,
    /// Teams' pre-join preheat (`endpointState.endpointProperties.
    /// preheatProperties: 1`, captured 2026-11-16): the call is joined
    /// hidden (no roster entry for anyone, our own included) until an
    /// updateEndpointState sets it to 0.
    preheat: bool,
    /// What a 1:1 call carries besides its callee ([`CallExtras`]).
    extras: Option<&'a CallExtras>,
    /// The meeting's `meetingData {meetingCode, passcode}` to send with
    /// the call, when known already (the main meeting's, going back to
    /// it from a breakout room).
    meeting_data: Option<serde_json::Value>,
    /// Join as an attendee (Teams' Preview as Attendee).
    as_attendee: bool,
    /// Two-step joins: how long to wait after the conversation join for
    /// the conversation's update that names its `meetingData`, which
    /// Teams then sends with the call (it moves into a breakout room 1.8 s
    /// after joining its conversation, by when that update is in). Without
    /// a wait the call carries it only if the update is already there.
    meeting_data_wait: Option<std::time::Duration>,
    /// Post the call straight to this conversation, which we're in
    /// already without a call (Teams going back from a breakout room to
    /// the main meeting it kept: `groupChat: null`, its `meetingData`).
    conversation_url: Option<&'a str>,
}

/// Teams' `participantPropertyBag` on a meeting call: its AI interpreter
/// voice consent (`aiVoiceConsentValue` "0": no simulated voice, as
/// ost-test1's policy and preference give it in Teams' captured joins).
fn participant_property_bag() -> serde_json::Value {
    serde_json::json!({
        "aiVoiceConsent": { "value": { "aiVoiceConsentValue": "0" }, "sequenceNumber": 0 }
    })
}

/// Teams' `mediaContent.mediaDescriptions` for a call it joins sending no
/// video (a preheated pre-join): its video lines offered `sendrecv` (the
/// camera's and sharing's, which media descriptions turn on and off) each
/// described `recvonly`, `requestId` 1. Audio, receive-only slots and the
/// data line aren't described (Teams' capture: mids 1-6 and 18 of its
/// offer, exactly its sendrecv video lines).
fn recvonly_media_descriptions(sdp_offer: &str) -> serde_json::Value {
    let mut descriptions: Vec<serde_json::Value> = Vec::new();
    let mut video = false;
    let mut mid: Option<&str> = None;
    let mut sendrecv = false;
    let mut flush = |video: bool, mid: Option<&str>, sendrecv: bool| {
        if let (true, Some(m), true) = (video, mid, sendrecv) {
            descriptions.push(serde_json::json!({ "mid": m, "direction": "recvonly" }));
        }
    };
    for line in sdp_offer.lines().map(str::trim_end) {
        if line.starts_with("m=") {
            flush(video, mid, sendrecv);
            video = line.starts_with("m=video");
            mid = None;
            sendrecv = false;
        } else if let Some(m) = line.strip_prefix("a=mid:") {
            mid = Some(m);
        } else if line == "a=sendrecv" {
            sendrecv = true;
        }
    }
    flush(video, mid, sendrecv);
    serde_json::json!({ "descriptions": descriptions, "requestId": 1 })
}

/// The `meetingData` a just-joined conversation's update names: what has
/// come already, or (with `wait`) what comes within it.
async fn await_meeting_data(
    updates: &mut tokio::sync::broadcast::Receiver<crate::event_hub::Event>,
    tag: Option<&str>,
    wait: Option<std::time::Duration>,
) -> Option<serde_json::Value> {
    let deadline = tokio::time::Instant::now() + wait.unwrap_or_default();
    loop {
        let ev = match updates.try_recv() {
            Ok(ev) => ev,
            Err(tokio::sync::broadcast::error::TryRecvError::Lagged(_)) => continue,
            Err(tokio::sync::broadcast::error::TryRecvError::Empty) => {
                let left = deadline.saturating_duration_since(tokio::time::Instant::now());
                if left.is_zero() {
                    return None;
                }
                match tokio::time::timeout(left, updates.recv()).await {
                    Ok(Ok(ev)) => ev,
                    Ok(Err(tokio::sync::broadcast::error::RecvError::Lagged(_))) => continue,
                    _ => return None,
                }
            }
            Err(_) => return None,
        };
        if let Some(md) = meeting_data_of(&ev.json, tag) {
            return Some(md);
        }
    }
}

/// The call tag in a callback base (`…/x<tag>/`), if it has one.
fn surl_tag(surl: &str) -> Option<&str> {
    surl.trim_end_matches('/')
        .rsplit('/')
        .next()
        .and_then(|s| s.strip_prefix('x'))
        .filter(|t| !t.is_empty() && t.bytes().all(|b| b.is_ascii_hexdigit()))
}

/// A conversation update's `meetingData {meetingCode, passcode}` (the
/// meeting's code and passcode, as Teams keeps them from its conversation
/// and sends them with its call), for the call tagged `tag`.
pub fn meeting_data_of(event_json: &str, tag: Option<&str>) -> Option<serde_json::Value> {
    if !event_json.contains("\"meetingData\"") {
        return None;
    }
    let v: serde_json::Value = serde_json::from_str(event_json).ok()?;
    if let Some(tag) = tag
        && v.get("callTag").and_then(|t| t.as_str()) != Some(tag)
    {
        return None;
    }
    if !v
        .get("callAgentPath")
        .and_then(|p| p.as_str())
        .is_some_and(|p| p.starts_with("conversation/"))
    {
        return None;
    }
    let md = v.pointer("/body/meetingData")?;
    let code = md.get("meetingCode")?.as_str().filter(|c| !c.is_empty())?;
    Some(
        serde_json::json!({ "meetingCode": code, "passcode": md.get("passcode").cloned().unwrap_or(serde_json::Value::Null) }),
    )
}

/// What a 1:1 call request can carry besides its callee (Teams' web calling
/// stack, `callInvitation`): `transferor` and `clientTransferContext` when
/// the call is the one a transfer asked us to make (our side of someone's
/// transfer or park, `call/transfer/`), and `unparkContent {pickupCode}`
/// when it retrieves a parked call (the callee is then `4:*11`).
/// `voicemail`: a call to the callee's voicemail (Teams' `startCallToVoicemail`:
/// the callee carries `endpointType: "voicemail"` and the invitation
/// `voicemailSettings {localResourcePath}`, `"greeting"` to record your
/// greeting, as Settings ▸ Calls ▸ Record a greeting does).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct CallExtras {
    pub transferor: Option<serde_json::Value>,
    pub transfer_context: Option<serde_json::Value>,
    pub unpark_code: Option<i64>,
    pub voicemail: Option<String>,
    /// Teams' test call to your intelligent call delegation (Settings ▸
    /// Calls ▸ Intelligent call delegation ▸ Make a test call: SlimCore's
    /// `callToPersonalAttendant`, botType `personalAttendant`): a 1:1 call
    /// to yourself whose callee is your personal attendant endpoint.
    pub personal_attendant: bool,
}

/// Teams' voicemail service (`KNOWN_BOTS.VOICEMAIL_BOT_ID`): who answers a
/// call to a voicemail.
pub const VOICEMAIL_BOT_MRI: &str = "28:14524421-25b4-403a-a0f7-e62d4379cabc";

/// The voicemail resource Teams' Record a greeting asks for (`qr.WV`).
pub const VOICEMAIL_GREETING: &str = "greeting";

/// Teams' park server for its Park Call ("teamPark", its `ParkContext.
/// Team`), the callee of a call that retrieves a parked call (Teams'
/// `Kd.PARK`; `*14` is the call queue's CallParkV2, `*13` music on hold).
pub const CALL_PARK_MRI: &str = "4:*11";

/// Put [`CallExtras`] into a call request's `callInvitation`.
pub fn apply_call_extras(invitation: &mut serde_json::Value, extras: &CallExtras) {
    if let Some(t) = &extras.transferor {
        invitation["transferor"] = t.clone();
    }
    if let Some(c) = &extras.transfer_context {
        invitation["clientTransferContext"] = c.clone();
    }
    if let Some(code) = extras.unpark_code {
        invitation["unparkContent"] = serde_json::json!({ "pickupCode": code });
    }
    if let Some(path) = &extras.voicemail {
        invitation["voicemailSettings"] = if path.is_empty() {
            serde_json::json!({})
        } else {
            serde_json::json!({ "localResourcePath": path })
        };
    }
}

/// One callee of a call request: its id, and the endpoint a call to your
/// voicemail or to your personal attendant asks for.
fn callee_entry(id: &str, voicemail: bool, attendant: bool) -> serde_json::Value {
    if voicemail {
        serde_json::json!({ "id": id, "endpointType": "voicemail" })
    } else if attendant {
        serde_json::json!({ "id": id, "endpointType": "personalAttendant" })
    } else {
        serde_json::json!({ "id": id })
    }
}

/// Our endpoint's properties in a call request: preheated (Teams'
/// pre-join) or not.
fn endpoint_properties(preheat: bool) -> serde_json::Value {
    let mut p = serde_json::json!({
        "additionalEndpointProperties": { "infoShownInReportMode": "FullInformation" }
    });
    if preheat {
        p["preheatProperties"] = 1.into();
    }
    p
}

/// Teams' conversation-only join (the first of its two meeting requests):
/// our participant and the conversation's callbacks, no call. Answers the
/// conversation's controller URL and its leave link.
async fn join_conversation_only(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    opts: &CreateOptions<'_>,
) -> Result<(String, Option<String>)> {
    // A meeting known only by its ID: joined by its meetingData (Teams'
    // joinType MeetingData), no thread.
    let by_code = params
        .thread_id
        .is_empty()
        .then_some(opts.meeting_data.as_ref())
        .flatten();
    join_conversation_with(http, epconv_url, params, opts, by_code)
        .await
        .map(|(c, l, _)| (c, l))
}

/// Join a meeting's conversation again, without a call, at its own URL
/// (Teams keeping the main meeting while in a breakout room, captured
/// 2026-11-17: once the room's call is accepted it leaves the main meeting
/// and at once `POST`s this to the main conversation, a new participant
/// id, so the main meeting's updates keep coming). Answers the
/// conversation's controller and its leave link.
pub async fn join_conversation_without_call(
    http: &reqwest::Client,
    conversation_url: &str,
    params: &ConversationCallParams<'_>,
    meeting_message_id: &str,
    organizer: Option<(&str, &str)>,
) -> Result<(String, Option<String>)> {
    let opts = CreateOptions {
        group_chat: true,
        meeting_message_id: Some(meeting_message_id),
        to: Vec::new(),
        conversation_type: None,
        invitation_type: None,
        suppress_dialout: true,
        subject: None,
        meetup: false,
        meeting_info: Some(meeting_info(
            organizer,
            (params.caller_oid, params.tenant_id),
        )),
        scenario: None,
        two_step: true,
        preheat: false,
        extras: None,
        meeting_data: None,
        meeting_data_wait: None,
        conversation_url: None,
        as_attendee: false,
    };
    join_conversation_with(http, conversation_url, params, &opts, None)
        .await
        .map(|(c, l, _)| (c, l))
}

/// The conversation-only join, by thread or (Teams' Join with an ID,
/// joinType MeetingData) by `meetingData {meetingCode, passcode,
/// meetingUrl}` and no thread. Answers the controller, the leave link and
/// the service's answer.
async fn join_conversation_with(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    opts: &CreateOptions<'_>,
    meeting_data: Option<&serde_json::Value>,
) -> Result<(String, Option<String>, serde_json::Value)> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);
    let mut payload = serde_json::json!({
        "conversationRequest": {
            "subject": null,
            "roster": { "type": "Delta", "rosterUpdate": tc("conversation/rosterUpdate/") },
            "properties": {
                "allowConversationWithoutHost": true,
                "enableGroupCallEventMessages": true,
                "enableGroupCallUpgradeMessage": false,
                "enableGroupCallMeetupGeneration": opts.meetup
            },
            "links": {
                "conversationEnd": tc("conversation/conversationEnd/"),
                "conversationUpdate": tc("conversation/conversationUpdate/"),
                "localParticipantUpdate": tc("conversation/localParticipantUpdate/"),
                "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
                "addParticipantFailure": tc("conversation/addParticipantFailure/"),
                "receiveMessage": tc("conversation/receiveMessage/")
            }
        },
        "groupContext": null,
        "groupChat": { "threadId": params.thread_id, "messageId": opts.meeting_message_id },
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            }
        },
        "capabilities": null,
        "endpointCapabilities": 73463,
        "clientEndpointCapabilities": client_endpoint_capabilities(),
        "endpointMetadata": { "holographicCapabilities": 3 },
        "meetingInfo": opts.meeting_info,
        "endpointState": {
            "endpointStateSequenceNumber": 0,
            "endpointProperties": { "additionalEndpointProperties": { "infoShownInReportMode": "FullInformation" } }
        },
        "debugContent": { "ecsEtag": "\"0\"", "causeId": &params.message_id[..8.min(params.message_id.len())] }
    });
    super::room_mode::mark_device(&mut payload);
    super::consumer::mark_application(&mut payload);
    if let Some(md) = meeting_data {
        payload["groupChat"] = serde_json::Value::Null;
        payload["meetingInfo"] = serde_json::Value::Null;
        payload["meetingData"] = md.clone();
        // A personal meeting link stays usable after its meeting ended:
        // Teams for personal use asks the service to bring it back.
        if super::consumer::is_personal() {
            payload["meetingPreferences"] = serde_json::json!({ "shouldResurrect": "resurrect" });
        }
    }
    let resp = http
        .post(epconv_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header(
            "x-microsoft-skype-message-id",
            uuid::Uuid::new_v4().to_string(),
        )
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Joining the meeting's conversation")?;
    let status = resp.status();
    let headers = resp.headers().clone();
    let body = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!(
            "Joining the meeting's conversation failed ({status}): {}",
            &body[..body.len().min(300)]
        );
    }
    tracing::debug!(body = %&body[..body.len().min(4000)], "conversation-only join response");
    let v: serde_json::Value = serde_json::from_str(&body).unwrap_or_default();
    let controller = v
        .pointer("/conversationController")
        .and_then(|c| c.as_str())
        .map(str::to_string)
        .or_else(|| {
            headers
                .get("location")
                .and_then(|h| h.to_str().ok())
                .map(str::to_string)
        })
        // Joined again at the conversation's own URL: that is its controller.
        .or_else(|| {
            epconv_url
                .contains("/conv/")
                .then(|| epconv_url.to_string())
        })
        .filter(|c| super::incoming::is_service_link(c))
        .context("No conversationController for the meeting's conversation")?;
    let leave = v
        .pointer("/links/leave")
        .and_then(|l| l.as_str())
        .filter(|l| super::incoming::is_service_link(l))
        .map(str::to_string);
    tracing::info!("joined the meeting's conversation");
    Ok((controller, leave, v))
}

/// Teams' Join with an ID: the meeting's conversation joined by its
/// meeting ID and passcode (`meetingData`, as Teams' calling stack sends it
/// for joinType MeetingData; no thread, no meetingInfo), read for the
/// meeting's thread, organizer and tenant, then left. Answers (thread id,
/// organizer id, tenant id, subject); no thread while the lobby holds us
/// (the meeting names it only once we're let in).
pub async fn resolve_meeting_code(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    meeting_data: &serde_json::Value,
) -> Result<(Option<String>, Option<String>, Option<String>, String)> {
    let opts = CreateOptions {
        group_chat: true,
        meeting_message_id: None,
        to: Vec::new(),
        conversation_type: None,
        invitation_type: None,
        suppress_dialout: true,
        subject: None,
        meetup: false,
        meeting_info: None,
        scenario: None,
        two_step: true,
        preheat: false,
        extras: None,
        meeting_data: None,
        meeting_data_wait: None,
        conversation_url: None,
        as_attendee: false,
    };
    let (_controller, leave, v) =
        join_conversation_with(http, epconv_url, params, &opts, Some(meeting_data)).await?;
    let text = v.to_string();
    let keys: Vec<&String> = v
        .as_object()
        .map(|o| o.keys().collect())
        .unwrap_or_default();
    tracing::info!(?keys, "meeting code conversation");
    let thread = find_thread(&text);
    let organizer = find_uuid_after(&text, "\"organizerId\":\"");
    let tenant = find_uuid_after(&text, "\"tenantId\":\"");
    let subject = v
        .get("subject")
        .and_then(|s| s.as_str())
        .unwrap_or_default()
        .to_string();
    if let Some(leave) = leave {
        let _ = http
            .delete(&leave)
            .headers(super::consumer::auth_headers(params.ic3_token))
            .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
            .send()
            .await;
    }
    Ok((thread, organizer, tenant, subject))
}

/// The first meeting thread (`19:…@thread.v2` or `@thread.tacv2`) in a
/// service answer.
fn find_thread(text: &str) -> Option<String> {
    let i = text
        .find("19:meeting_")
        .or_else(|| text.find("\"19:").map(|i| i + 1))?;
    let rest = &text[i..];
    let end = rest
        .find("@thread.v2")
        .map(|e| e + "@thread.v2".len())
        .or_else(|| {
            rest.find("@thread.tacv2")
                .map(|e| e + "@thread.tacv2".len())
        })?;
    let t = &rest[..end];
    t.bytes()
        .all(|b| b.is_ascii_alphanumeric() || b"_-:@.=".contains(&b))
        .then(|| t.to_string())
}

fn find_uuid_after(text: &str, key: &str) -> Option<String> {
    let i = text.find(key)? + key.len();
    let v: String = text[i..].chars().take_while(|c| *c != '"').collect();
    uuid::Uuid::parse_str(&v).is_ok().then_some(v)
}

async fn create_call(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    callee_mri: Option<&str>,
    extras: Option<&CallExtras>,
) -> Result<(ConversationCreated, ConversationJoined)> {
    let opts = CreateOptions {
        group_chat: callee_mri.is_none(),
        meeting_message_id: None,
        to: callee_mri.into_iter().collect(),
        conversation_type: None,
        invitation_type: None,
        // false = ring the callee.
        suppress_dialout: false,
        subject: None,
        meetup: false,
        meeting_info: None,
        scenario: None,
        two_step: false,
        preheat: false,
        extras,
        meeting_data: None,
        meeting_data_wait: None,
        conversation_url: None,
        as_attendee: false,
    };
    create_call_with(http, epconv_url, params, sdp_offer, &opts).await
}

async fn create_call_with(
    http: &reqwest::Client,
    epconv_url: &str,
    params: &ConversationCallParams<'_>,
    sdp_offer: &str,
    opts: &CreateOptions<'_>,
) -> Result<(ConversationCreated, ConversationJoined)> {
    let meeting_message_id = opts.meeting_message_id;
    let group_chat = if opts.group_chat {
        serde_json::json!({ "threadId": params.thread_id, "messageId": meeting_message_id })
    } else {
        serde_json::Value::Null
    };
    // A call to a voicemail names its callee's voicemail endpoint.
    let to_voicemail = opts.extras.is_some_and(|e| e.voicemail.is_some());
    // A test call to your personal attendant names that endpoint.
    let to_attendant = opts.extras.is_some_and(|e| e.personal_attendant);
    let to: Vec<serde_json::Value> = opts
        .to
        .iter()
        .map(|id| callee_entry(id, to_voicemail, to_attendant))
        .collect();
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);
    let cause_id = &params.message_id[..8.min(params.message_id.len())];

    let payload = serde_json::json!({
        "conversationRequest": {
            "conversationType": opts.conversation_type,
            "subject": opts.subject.unwrap_or(""),
            "suppressDialout": opts.suppress_dialout,
            "roster": {
                "type": "Delta",
                "rosterUpdate": tc("conversation/rosterUpdate/")
            },
            "properties": {
                "allowConversationWithoutHost": true,
                "enableGroupCallEventMessages": true,
                "enableGroupCallUpgradeMessage": false,
                "enableGroupCallMeetupGeneration": opts.meetup
            },
            "links": {
                "conversationEnd": tc("conversation/conversationEnd/"),
                "conversationUpdate": tc("conversation/conversationUpdate/"),
                "localParticipantUpdate": tc("conversation/localParticipantUpdate/"),
                "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
                "addParticipantFailure": tc("conversation/addParticipantFailure/"),
                "addModalitySuccess": tc("conversation/addModalitySuccess/"),
                "addModalityFailure": tc("conversation/addModalityFailure/"),
                "confirmUnmute": tc("conversation/confirmUnmute/"),
                "receiveMessage": tc("conversation/receiveMessage/")
            }
        },
        "groupContext": null,
        // A 1:1 call to a named callee is peer to peer, like Teams'; tying
        // it to the chat thread makes it a chat-hosted meeting instead.
        "groupChat": group_chat,
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            },
            "to": to
        },
        "capabilities": null,
        "endpointCapabilities": 73463,
        "clientEndpointCapabilities": client_endpoint_capabilities(),
        "endpointMetadata": { "holographicCapabilities": 3 },
        "meetingInfo": opts.meeting_info,
        "endpointState": {
            "endpointStateSequenceNumber": 0,
            "endpointProperties": endpoint_properties(opts.preheat)
        },
        "callInvitation": {
            "callModalities": ["Audio", "Video", "ScreenViewer"],
            "replaces": null,
            "transferor": null,
            "links": {
                "progress": tc("call/progress/"),
                "mediaAnswer": tc("call/mediaAnswer/"),
                "acceptance": tc("call/acceptance/"),
                "redirection": tc("call/redirection/"),
                "end": tc("call/end/")
            },
            "clientContentForMediaController": {
                "controlVideoStreaming": tc("call/controlVideoStreaming/"),
                "csrcInfo": tc("call/csrcInfo/"),
                "dominantSpeakerInfo": tc("call/dominantSpeakerInfo/")
            },
            "pstnContent": {
                "emergencyCallCountry": "",
                "platformName": "teams-cli",
                "publicApiCall": false
            },
            "mediaContent": {
                "contentType": OFFER_CONTENT_TYPE,
                "blob": sdp_offer
            }
        },
        "debugContent": {
            "ecsEtag": "\"0\"",
            "causeId": cause_id
        }
    });

    let mut payload = payload;
    super::room_mode::mark_device(&mut payload);
    super::consumer::mark_application(&mut payload);
    if let Some(scenario) = opts.scenario {
        payload["scenario"] = scenario.into();
    }
    if let Some(t) = opts.invitation_type {
        payload["participants"]["invitationType"] = t.into();
    }
    if let Some(extras) = opts.extras {
        apply_call_extras(&mut payload["callInvitation"], extras);
    }
    // Teams' preheated pre-join call (captured 2026-11-16): audio and
    // sharing only, every m-line recvonly (muted, nothing sent), its
    // participant property bag, and the media fields its join carries.
    if opts.preheat {
        let inv = &mut payload["callInvitation"];
        inv["callModalities"] = serde_json::json!(["Audio", "ScreenViewer"]);
        inv["clientTransferContext"] = serde_json::Value::Null;
        inv["customContext"] = serde_json::Value::Null;
        inv["emergencyContent"] = serde_json::Value::Null;
        inv["voicemailSettings"] = serde_json::json!({});
        inv["locationContent"] = serde_json::Value::Null;
        inv["networkContent"] = serde_json::Value::Null;
        inv["areaContent"] = serde_json::Value::Null;
        inv["mediaContent"]["mediaDescriptions"] = recvonly_media_descriptions(sdp_offer);
        payload["contentSharing"] = serde_json::Value::Null;
    }
    if opts.meeting_info.is_some() {
        payload["participantPropertyBag"] = participant_property_bag();
    }
    if opts.as_attendee {
        payload["participationPreferences"] = attendee_preferences();
    }

    // Meetings: the conversation first, then the call to it (Teams'). Its
    // update names the meeting's code and passcode, which the call carries.
    let mut meeting_data = opts.meeting_data.clone();
    let (target_url, conversation_leave) = if let Some(url) = opts.conversation_url {
        // Already in that conversation (without a call): straight to it.
        payload["groupChat"] = serde_json::Value::Null;
        (url.to_string(), None)
    } else if opts.two_step {
        let mut updates = crate::event_hub::subscribe();
        match join_conversation_only(http, epconv_url, params, opts).await {
            Ok((c, leave)) => {
                if meeting_data.is_none() {
                    meeting_data = await_meeting_data(
                        &mut updates,
                        surl_tag(params.trouter_surl),
                        opts.meeting_data_wait,
                    )
                    .await;
                }
                (c, leave)
            }
            Err(e) => {
                tracing::warn!("conversation-only join: {e:#}; joining in one request");
                (epconv_url.to_string(), None)
            }
        }
    } else {
        (epconv_url.to_string(), None)
    };
    if let Some(md) = meeting_data {
        tracing::info!("the call carries the meeting's meetingData");
        payload["meetingData"] = md;
        // Known only by its ID (no thread yet): no group chat or
        // meetingInfo, as Teams' MeetingData join.
        if params.thread_id.is_empty() {
            payload["groupChat"] = serde_json::Value::Null;
            payload["meetingInfo"] = serde_json::Value::Null;
        }
    }
    // The call request failed after we joined the conversation: leave it,
    // so no participant without a call stays behind.
    let leave_joined_conversation = || async {
        if let Some(url) = &conversation_leave
            && let Err(e) = leave_conversation(http, url, params, 0).await
        {
            tracing::warn!("leaving the meeting's conversation: {e:#}");
        }
    };
    tracing::info!(
        "1:1 call: POST {} (single-shot epconv with SDP)",
        if opts.two_step {
            "the meeting's conversation"
        } else {
            epconv_url
        }
    );

    let resp = http
        .post(&target_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", params.message_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await;
    let resp = match resp {
        Ok(r) => r,
        Err(e) => {
            leave_joined_conversation().await;
            return Err(anyhow::Error::new(e).context("1:1 call POST to epconv failed"));
        }
    };

    let status = resp.status();
    let headers = resp.headers().clone();
    let body = resp.text().await.unwrap_or_default();

    tracing::info!("1:1 call response: {} ({} bytes)", status, body.len());
    tracing::debug!("1:1 call response body: {}", &body[..body.len().min(2000)]);

    if !status.is_success() {
        leave_joined_conversation().await;
        anyhow::bail!("1:1 call epconv failed ({}): {}", status, body);
    }

    // Parse conversationController from response
    let resp_json: serde_json::Value =
        serde_json::from_str(&body).context("1:1 call response is not valid JSON")?;

    let conv_controller = resp_json
        .pointer("/conversationController")
        .or_else(|| resp_json.pointer("/conversationResponse/conversationController"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| {
            headers
                .get("location")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string())
        })
        .context("No conversationController in 1:1 call response")?;

    let add_participant_url = resp_json
        .pointer("/links/addParticipant")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    tracing::debug!("1:1 call response links: {:?}", link_names(&resp_json));
    tracing::info!(
        "1:1 call: conversationController = {}, addParticipant link = {:?}",
        conv_controller,
        add_participant_url
    );

    let cc_active_url = resp_json
        .pointer("/links/active")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let created = ConversationCreated {
        conversation_controller: conv_controller,
        add_participant_url,
        response_body: body.clone(),
    };
    let joined = ConversationJoined {
        cc_active_url,
        response_body: body,
    };

    Ok((created, joined))
}

/// Invite a user into the conversation via POST /conv/{id}/add.
///
/// This is step 3 of the 1:1 call flow: after creating the conversation (epconv)
/// and joining with SDP, we add the callee as a participant.
///
/// If `include_video` is true, the call invitation will include Video modality.
pub async fn invite_user(
    http: &reqwest::Client,
    conversation_controller: &str,
    params: &ConversationCallParams<'_>,
    callee_mri: &str,
    include_video: bool,
) -> Result<()> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);

    // Derive /add URL from conversation controller
    let add_url = if let Some(idx) = conversation_controller.find('?') {
        let (path, query) = conversation_controller.split_at(idx);
        format!("{}/add{}", path.trim_end_matches('/'), query)
    } else {
        format!("{}/add", conversation_controller.trim_end_matches('/'))
    };

    let callee_participant_id = uuid::Uuid::new_v4().to_string();
    let call_modalities: Vec<&str> = if include_video {
        vec!["Audio", "Video"]
    } else {
        vec!["Audio"]
    };

    let payload = serde_json::json!({
        "disableUnmute": false,
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            },
            "to": [{
                "id": callee_mri,
                "participantId": callee_participant_id
            }]
        },
        // Include call invitation data to trigger ringing on callee's device
        "participantInvitationData": {
            "callModalities": call_modalities,
            "callDirection": "Outgoing"
        },
        "callInvitation": {
            "callModalities": call_modalities,
            "replaces": null,
            "transferor": null
        },
        "replacementDetails": null,
        "groupContext": null,
        "groupChat": {
            "threadId": params.thread_id,
            "messageId": null
        },
        "links": {
            "addParticipantSuccess": tc("conversation/addParticipantSuccess/"),
            "addParticipantFailure": tc("conversation/addParticipantFailure/")
        }
    });

    // Fresh message-id for deduplication
    let invite_msg_id = uuid::Uuid::new_v4().to_string();

    tracing::info!(
        "Inviting user {} -> POST {} (msg_id={})",
        callee_mri,
        add_url,
        invite_msg_id
    );
    tracing::debug!(
        "User invite payload: {}",
        serde_json::to_string_pretty(&payload).unwrap_or_default()
    );

    let resp = http
        .post(&add_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", &invite_msg_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Failed to POST user invite")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    tracing::info!("User invite response: {} ({} bytes)", status, body.len());
    tracing::debug!("User invite response body: {}", body);

    if !status.is_success() {
        anyhow::bail!("User invite failed ({}): {}", status, body);
    }

    Ok(())
}

/// Leave a conversation we created, as the Teams client does to cancel an
/// outgoing call that is still ringing (`code` 487) or has gone
/// unanswered (408). The callee's ringing stops at once.
/// Watch a chat's ongoing call without joining it, as Teams does to show
/// who is in it (calling-pluginless `subscribeToCall`): a conversation
/// request with `subscribe` semantics (no call invitation) to the call's
/// `conversationUrl`. The response lists the roster; updates come to our
/// `subscription/…` callbacks. Returns the response body.
pub async fn subscribe_conversation(
    http: &reqwest::Client,
    conversation_url: &str,
    params: &ConversationCallParams<'_>,
) -> Result<String> {
    let tc = |path: &str| trouter_callback(params.trouter_surl, params.endpoint_id, path);
    let payload = serde_json::json!({
        "conversationRequest": {
            "roster": { "type": "Delta", "rosterUpdate": tc("subscription/rosterUpdate/") },
            "properties": {
                "allowConversationWithoutHost": true,
                "enableGroupCallEventMessages": true,
                "enableGroupCallUpgradeMessage": false,
                "enableGroupCallMeetupGeneration": false
            },
            "links": {
                "conversationEnd": tc("subscription/conversationEnd/"),
                "conversationUpdate": tc("subscription/conversationUpdate/"),
                "localParticipantUpdate": tc("subscription/localParticipantUpdate/"),
                "addParticipantSuccess": tc("subscription/addParticipantSuccess/"),
                "addParticipantFailure": tc("subscription/addParticipantFailure/"),
                "receiveMessage": tc("subscription/receiveMessage/")
            }
        },
        "groupContext": null,
        "groupChat": { "threadId": params.thread_id, "messageId": null },
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            }
        },
        "capabilities": null,
        "endpointCapabilities": 73463,
        "clientEndpointCapabilities": client_endpoint_capabilities(),
        "endpointMetadata": { "holographicCapabilities": 3 },
        "meetingInfo": null,
        "endpointState": {
            "endpointStateSequenceNumber": 0,
            "endpointProperties": {
                "additionalEndpointProperties": { "infoShownInReportMode": "FullInformation" }
            }
        }
    });
    let resp = http
        .post(conversation_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header("x-microsoft-skype-message-id", params.message_id)
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Subscribing to the call failed")?;
    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();
    tracing::info!(
        "Call roster subscription: {} ({} bytes)",
        status,
        body.len()
    );
    if !status.is_success() {
        anyhow::bail!(
            "Subscribing to the call failed ({status}): {}",
            &body[..body.len().min(300)]
        );
    }
    Ok(body)
}

pub async fn leave_conversation(
    http: &reqwest::Client,
    leave_url: &str,
    params: &ConversationCallParams<'_>,
    code: u16,
) -> Result<()> {
    let payload = leave_payload(params, code);
    let resp = http
        .post(leave_url)
        .headers(super::consumer::auth_headers(params.ic3_token))
        .header("Content-Type", "application/json")
        .header("x-microsoft-skype-chain-id", params.chain_id)
        .header(
            "x-microsoft-skype-message-id",
            uuid::Uuid::new_v4().to_string(),
        )
        .header("x-microsoft-skype-client", SKYPE_CLIENT_HEADER)
        .header("Referer", "https://teams.microsoft.com/")
        .header("ms-teams-partition", TEAMS_PARTITION)
        .header("ms-teams-region", TEAMS_REGION)
        .header("ms-teams-ring", TEAMS_RING)
        .header("x-ms-migration", "True")
        .json(&payload)
        .send()
        .await
        .context("Failed to leave the conversation")?;
    let status = resp.status();
    tracing::info!("Leave conversation: {}", status);
    if !status.is_success() {
        anyhow::bail!("Leaving the conversation failed ({status})");
    }
    Ok(())
}

fn leave_payload(params: &ConversationCallParams<'_>, code: u16) -> serde_json::Value {
    serde_json::json!({
        "participants": {
            "from": {
                "id": params.caller_mri,
                "displayName": params.caller_display_name,
                "endpointId": params.endpoint_id,
                "participantId": params.participant_id,
                "languageId": "en-US"
            }
        },
        "conversationTransactionEnd": {
            "reason": "noError",
            "code": 0,
            "phrase": "ConversationEndNoModalityConnected"
        },
        "callTransactionEnd": {
            "code": code,
            "subCode": 0,
            "phrase": "CallEndReasonLocalUserInitiated",
            "resultCategories": ["Success"]
        }
    })
}

/// End a call by POSTing to the end URL.
pub async fn end_call(
    http: &reqwest::Client,
    skype_token: &str,
    notification: &CallNotification,
) -> Result<()> {
    let invitation = notification
        .call_invitation
        .as_ref()
        .context("No callInvitation in notification")?;
    let links = invitation
        .links
        .as_ref()
        .context("No links in callInvitation")?;
    let end_url = links.end.as_ref().context("No end URL in links")?;

    tracing::info!("Ending call -> POST {}", end_url);

    let resp = http
        .post(end_url)
        .header("X-Skypetoken", skype_token)
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({}))
        .send()
        .await
        .context("Failed to POST end call")?;

    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if status.is_success() {
        tracing::info!("Call ended ({}): {}", status, body);
        Ok(())
    } else {
        anyhow::bail!("Call end failed ({}): {}", status, body);
    }
}

#[cfg(test)]
mod hostless_tests {
    use super::became_hostless_meeting;

    #[test]
    fn an_unanswered_echo_call_is_recognised() {
        // The acknowledgement Echo call 1 got (2026-11-10, trimmed): 201
        // Created, a hostless ad-hoc meeting with only the caller.
        let ack = serde_json::json!({"sequenceNumber": 2, "state": {"isMultiParty": true,
            "groupCallInitiator": "8:orgid:4287e791-1b98-4963-8b94-281c50472683", "isHostless": true,
            "conversationType": "adHocMeeting", "isBroadcast": false, "isMeetingActivated": false}});
        assert!(became_hostless_meeting(&ack));
        // 202 Accepted (the answered calls) has no body.
        assert!(!became_hostless_meeting(&serde_json::Value::Null));
    }
}

#[cfg(test)]
mod meeting_info_tests {
    use super::meeting_info;

    #[test]
    fn joins_name_the_links_organizer() {
        // Someone else's meeting: the organizer and tenant from the link
        // (joining as ourselves would start a new ad hoc meeting).
        assert_eq!(
            meeting_info(Some(("org-oid", "tenant")), ("my-oid", "my-tenant")),
            serde_json::json!({ "tenantId": "tenant", "organizerId": "org-oid" })
        );
        assert_eq!(
            meeting_info(None, ("my-oid", "my-tenant")),
            serde_json::json!({ "tenantId": "my-tenant", "organizerId": "my-oid" })
        );
    }
}

#[cfg(test)]
mod preheat_tests {
    use super::endpoint_properties;

    #[test]
    fn a_preheated_join_says_so_in_its_endpoint_properties() {
        // Teams' pre-join call request (Teams on the web, 2026-11-16).
        assert_eq!(
            endpoint_properties(true),
            serde_json::json!({ "preheatProperties": 1, "additionalEndpointProperties": { "infoShownInReportMode": "FullInformation" } })
        );
        assert!(
            endpoint_properties(false)
                .get("preheatProperties")
                .is_none()
        );
    }

    #[test]
    fn a_preheated_call_describes_its_sendrecv_video_lines_as_recvonly() {
        // Audio, a receive-only slot and the data line aren't described.
        let sdp = "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\na=sendrecv\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:1\r\na=sendrecv\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:2\r\na=recvonly\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:11\r\na=sendrecv\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=mid:12\r\n";
        assert_eq!(
            super::recvonly_media_descriptions(sdp),
            serde_json::json!({ "descriptions": [
                { "mid": "1", "direction": "recvonly" },
                { "mid": "11", "direction": "recvonly" }
            ], "requestId": 1 })
        );
        assert_eq!(
            super::participant_property_bag(),
            serde_json::json!({ "aiVoiceConsent": { "value": { "aiVoiceConsentValue": "0" }, "sequenceNumber": 0 } })
        );
    }

    #[test]
    fn the_conversation_update_names_the_meeting_code() {
        // Teams' room conversation update (captured 2026-11-17, values made up).
        let ev = r#"{"callAgentPath":"conversation/conversationUpdate/","callTag":"abc123","body":{"meetingInfo":{},"meetingData":{"meetingCode":"2804365176741122","passcode":"wG7nz3CB"}}}"#;
        assert_eq!(
            super::meeting_data_of(ev, Some("abc123")),
            Some(serde_json::json!({ "meetingCode": "2804365176741122", "passcode": "wG7nz3CB" }))
        );
        // Another call's, or a chat message's meetingData: null, isn't it.
        assert!(super::meeting_data_of(ev, Some("def456")).is_none());
        assert!(super::meeting_data_of(r#"{"callAgentPath":"conversation/conversationUpdate/","body":{"meetingData":null}}"#, None).is_none());
        assert_eq!(
            super::surl_tag("https://t/v4/f/abc/xabc123/"),
            Some("abc123")
        );
        assert_eq!(super::surl_tag("https://t/v4/f/abc/"), None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transfer_and_unpark_calls_carry_teams_extras() {
        let mut inv = serde_json::json!({ "replaces": null, "transferor": null });
        apply_call_extras(
            &mut inv,
            &CallExtras {
                transferor: Some(
                    serde_json::json!({ "details": { "id": "8:orgid:a" }, "authorizationToken": "t" }),
                ),
                transfer_context: None,
                unpark_code: None,
                voicemail: None,
                personal_attendant: false,
            },
        );
        assert_eq!(inv["transferor"]["authorizationToken"], "t");
        assert!(inv.get("unparkContent").is_none());
        let mut inv = serde_json::json!({ "transferor": null });
        apply_call_extras(
            &mut inv,
            &CallExtras {
                unpark_code: Some(42),
                ..Default::default()
            },
        );
        assert_eq!(
            inv["unparkContent"],
            serde_json::json!({ "pickupCode": 42 })
        );
        assert!(inv["transferor"].is_null());
        assert_eq!(CALL_PARK_MRI, "4:*11");
    }

    /// Teams' Record a greeting: the invitation asks the voicemail for its
    /// greeting resource.
    #[test]
    fn attendant_test_call_names_the_attendant_endpoint() {
        assert_eq!(
            callee_entry("8:orgid:me", false, true),
            serde_json::json!({ "id": "8:orgid:me", "endpointType": "personalAttendant" })
        );
        assert_eq!(
            callee_entry("8:orgid:me", true, false),
            serde_json::json!({ "id": "8:orgid:me", "endpointType": "voicemail" })
        );
        assert_eq!(
            callee_entry("8:orgid:x", false, false),
            serde_json::json!({ "id": "8:orgid:x" })
        );
    }

    #[test]
    fn voicemail_call_asks_for_the_greeting() {
        let mut inv = serde_json::json!({});
        apply_call_extras(
            &mut inv,
            &CallExtras {
                voicemail: Some(VOICEMAIL_GREETING.into()),
                ..Default::default()
            },
        );
        assert_eq!(
            inv["voicemailSettings"],
            serde_json::json!({ "localResourcePath": "greeting" })
        );
        let mut inv = serde_json::json!({});
        apply_call_extras(
            &mut inv,
            &CallExtras {
                voicemail: Some(String::new()),
                ..Default::default()
            },
        );
        assert_eq!(inv["voicemailSettings"], serde_json::json!({}));
    }
}
