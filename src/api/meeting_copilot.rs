//! Copilot in a meeting, as Teams desktop opens it for a licensed user
//! (measured on winpc 2026-11-16, ost-test1 with a Microsoft 365 Copilot
//! licence; docs/spec/call-and-meeting-window.md §1.8j).
//!
//! The meeting bar's Copilot (`meeting-collab-button`) opens a 320-wide
//! side pane hosting the Microsoft 365 Copilot app (its "bizChat"
//! variant: app `b5abf2ae-…`, the same app as the rail's Copilot) as a
//! TeamsJS app in its `copilotSidePanel` surface:
//! - the frame loads `https://m365copilotapp.svc.cloud.microsoft/chat`
//!   with the user, culture, host and sessions in its query;
//! - its context's `subEntityId` carries Teams' launch payload (base64
//!   JSON): `callerInfo {scope "Meeting", entryPoint
//!   "PrivateViewDuringMeeting", copilotReferenceId}` — the reference is
//!   the SHA-256 (hex) of the call's id (Teams' `A()` in module 539064);
//! - once the app is up, the host posts `contextualChatChanged` with the
//!   meeting (call id, organizer `<oid>@<tid>`, thread, iCalUid, message
//!   id, subject, whether the transcript runs; scenario
//!   `TeamsMeetingSidepaneWorkCopilot`) and `updateCapabilities`
//!   (`disableGPT5`, `disableVoiceInput`), and again whenever the
//!   transcript starts or stops.
//!
//! Copilot then answers about the meeting itself (its own requests, with
//! the tokens the host gives it over nested app auth).

use base64::Engine as _;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

/// The Microsoft 365 Copilot app (Teams' bizChatCopilotMetaOsAppId).
pub const APP_ID: &str = "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162";
/// The app's chat page.
pub const CHAT_URL: &str = "https://m365copilotapp.svc.cloud.microsoft/chat";
/// The CMM id Teams' meeting entry point refers the app with.
pub const MEETING_CMMID: &str = "cmm35g04qbs";

/// What the pane knows about the meeting and the user.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Meeting {
    pub call_id: String,
    pub thread_id: String,
    /// The organizer's object id and tenant.
    pub organizer_id: String,
    pub organizer_tenant: String,
    pub ical_uid: String,
    pub message_id: String,
    pub subject: String,
    pub transcript_running: bool,
    /// The signed-in user (OID@tid in the frame's address).
    pub user_oid: String,
    pub tenant_id: String,
    /// The user's OneDrive host (`<tenant>-my.sharepoint.com`).
    pub my_site: String,
    pub culture: String,
    /// TeamsJS theme name (default, dark, contrast).
    pub theme: String,
    /// The app's session and the host's (Teams' sessionId / parent).
    pub app_session: String,
    pub host_session: String,
}

/// Teams' copilotReferenceId for a meeting: SHA-256 of its call id, hex.
pub fn reference_id(call_id: &str) -> String {
    Sha256::digest(call_id.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// The launch payload Teams puts in the app's subEntityId (base64 of
/// this JSON, keys in Teams' order).
pub fn launch_payload(m: &Meeting) -> String {
    let payload = json!({
        "id": "", "scenario": "Default", "chatType": "", "properties": {}, "version": 1,
        "referral": { "cmmid": MEETING_CMMID },
        "callerInfo": { "scope": "Meeting", "entryPoint": "PrivateViewDuringMeeting", "copilotReferenceId": reference_id(&m.call_id) },
        "serverVariants": [],
    });
    base64::engine::general_purpose::STANDARD.encode(payload.to_string())
}

/// The context's subEntityId (a JSON string, as Teams sends it).
pub fn sub_entity_id(m: &Meeting) -> String {
    json!({
        "hostSettings": { "enableDeeplinks": "true", "focusOnLoad": "Compose" },
        "launchOptionPayload": launch_payload(m),
    })
    .to_string()
}

/// The frame's address.
pub fn content_url(m: &Meeting) -> String {
    let mut u = url::Url::parse(CHAT_URL).expect("chat url");
    {
        let mut q = u.query_pairs_mut();
        q.append_pair("OID", &format!("{}@{}", m.user_oid, m.tenant_id))
            .append_pair("hostApp", "hub")
            .append_pair("isanonymous", "true")
            .append_pair(
                "culture",
                if m.culture.is_empty() {
                    "en-us"
                } else {
                    &m.culture
                },
            );
        if !m.my_site.is_empty() {
            q.append_pair("mysite", &m.my_site);
        }
        q.append_pair("hostName", "TeamsModern")
            .append_pair("hostClientType", "desktop")
            .append_pair("sessionId", &m.app_session)
            .append_pair("renderingSurface", "copilotSidePanel")
            .append_pair(
                "theme",
                if m.theme.is_empty() {
                    "default"
                } else {
                    &m.theme
                },
            )
            // Teams names the user's ring (ECS Segmentation.TeamsRing,
            // "ring3_6" for ost-test1; the ringId OST's context gives apps).
            .append_pair("hostRing", &super::ecs::ring())
            .append_pair("parentSessionId", &m.host_session);
    }
    u.to_string()
}

/// The `contextualChatChanged` event's argument.
pub fn contextual_chat(m: &Meeting) -> Value {
    json!({
        "contentType": "teams",
        "contentItems": [{
            "contextType": "Meeting",
            "meetingContext": {
                "context": "Meeting",
                "callId": m.call_id,
                "organizerId": format!("{}@{}", m.organizer_id, m.organizer_tenant),
                "threadId": m.thread_id,
                "iCalUid": m.ical_uid,
                "messageId": if m.message_id.is_empty() { "0" } else { &m.message_id },
                "sessionType": "PrivateViewDuringMeeting",
                "groupId": "",
                "vroomId": "",
                "exchangeEventId": "",
                "subject": m.subject,
                "isTranscriptRunningDuringMeeting": m.transcript_running,
                "isTemporaryStorageForMeetingTranscript": false,
            },
            "scenarioName": "TeamsMeetingSidepaneWorkCopilot",
        }],
    })
}

/// The `updateCapabilities` event's argument.
pub fn capabilities() -> Value {
    json!([{ "name": "disableGPT5" }, { "name": "disableVoiceInput" }])
}

/// Everything the pane needs: the frame's address, the context overrides
/// and the two events.
pub fn launch(m: &Meeting) -> Value {
    json!({
        "url": content_url(m),
        "context": {
            "subEntityId": sub_entity_id(m),
            "entityId": format!("entity1-{}", uuid::Uuid::new_v4()),
            "frameContext": "sidePanel",
            "renderingSurface": "copilotSidePanel",
            // Teams' appIconPosition for the Copilot side panel (-17 in
            // every capture: chat, meeting, channel thread, post view and
            // its window; winpc 2026-11-21..24).
            "appIconPosition": -17,
            "isFullScreen": true,
            "userLicenseType": "Copilot",
            "mySiteDomain": m.my_site,
        },
        "contextualChat": contextual_chat(m),
        "capabilities": capabilities(),
    })
}

/// Copilot in a meeting's recap (Teams 991291: the recap's Copilot button,
/// bizChat variant from a recap card): the same app and pane with
/// entryPoint "Recap" and the recap's CMM id (ECS Copilot.
/// copilotEntryPointsCMMIds.meetingRecap), the meeting context's session
/// "Recap" (a call without an iCalUid: "RecapCall") and the recording as
/// its vroomId.
pub fn launch_recap(m: &Meeting, vroom_id: &str, cmmid: &str) -> Value {
    let call = m.ical_uid.is_empty();
    let entry = if call { "RecapCall" } else { "Recap" };
    let payload = json!({
        "id": "", "scenario": "Default", "chatType": "", "properties": {}, "version": 1,
        "referral": { "cmmid": cmmid },
        "callerInfo": { "scope": "Meeting", "entryPoint": entry, "copilotReferenceId": reference_id(&m.call_id) },
        "serverVariants": [],
    });
    let sub = json!({
        "hostSettings": { "enableDeeplinks": "true", "focusOnLoad": "Compose" },
        "launchOptionPayload": base64::engine::general_purpose::STANDARD.encode(payload.to_string()),
    })
    .to_string();
    let mut v = launch(m);
    v["context"]["subEntityId"] = Value::String(sub);
    let mc = &mut v["contextualChat"]["contentItems"][0]["meetingContext"];
    mc["sessionType"] = Value::String(entry.into());
    mc["vroomId"] = Value::String(vroom_id.into());
    v["contextualChat"]["contentItems"][0]["scenarioName"] =
        Value::String("TeamsMeetingRecapCopilot".into());
    v
}

/// Copilot asked from search (Teams' "Ask Copilot about …" suggestion,
/// search-app 403263 `handleCatalystInSerpClick`): the same app in the
/// search results' right pane. The launch payload names scope "Search",
/// entry point "SearchAutosuggestAskCopilot" and ECS Copilot.
/// copilotEntryPointsCMMIds.searchAutosuggestAskCopilot; its
/// copilotReferenceId is the SHA-256 of the search session's id, which the
/// frame's address also anchors on (`chat/sessionanchor/<id>`, measured
/// 2026-11-20). Once the app is up the host tells it the Search context
/// and hands it the query as a SearchPrompt (`updatePromptInputData`, with
/// Teams' CopilotSearch annotation for the All tab).
pub fn launch_search(m: &Meeting, search_session: &str, query: &str, cmmid: &str) -> Value {
    let reference = reference_id(search_session);
    let payload = json!({
        "id": "", "scenario": "Default", "chatType": "", "properties": {}, "version": 1,
        "referral": { "cmmid": cmmid },
        "callerInfo": { "scope": "Search", "entryPoint": "SearchAutosuggestAskCopilot", "copilotReferenceId": reference },
        "serverVariants": [],
    });
    let sub = json!({
        "hostSettings": { "enableDeeplinks": "true", "focusOnLoad": "Compose" },
        "launchOptionPayload": base64::engine::general_purpose::STANDARD.encode(payload.to_string()),
    })
    .to_string();
    let mut v = launch(m);
    v["url"] = Value::String(content_url(m).replacen(
        "/chat?",
        &format!("/chat/sessionanchor/{reference}?"),
        1,
    ));
    v["context"]["subEntityId"] = Value::String(sub);
    v["contextualChat"] =
        json!({ "contentType": "teams", "contentItems": [{ "contextType": "Search" }] });
    // Search adds no capabilities of its own (Teams' addConfiguredCapabilities
    // for the Search context): voice input stays.
    v["capabilities"] = json!([]);
    v["prompt"] = json!({
        "promptText": query,
        "isDraft": false,
        "conversationId": "",
        "queryAnnotations": [{
            "id": uuid::Uuid::new_v4().to_string(),
            "queryAnnotationType": "CopilotSearch",
            "messageAnnotationSource": "ClientAnnotated",
            "messageAnnotationMetadata": { "@type": "CopilotSearch", "annotationType": "CopilotSearch", "searchType": "AllTab", "entityTypes": ["All"], "appName": "Teams" },
        }],
    });
    v
}

/// Teams' built-in CMM ids for the chat and channel entry points
/// (`copilotEntryPointsCMMIds`, when ECS doesn't set them).
pub const CHAT_PANEL_CMMID: &str = "cmmnho609kr";
pub const MEETING_CHAT_PANEL_CMMID: &str = "cmm4p9gchbg";
pub const MEETING_CHAT_NO_TRANSCRIPT_CMMID: &str = "cmm72vlwwfw";
pub const CHANNEL_L2_CMMID: &str = "cmmce9gzagp";

/// Who opened the pane, as Teams' launch payload names it
/// (`createSubPageEntityIdForBizChat`, module 539064).
struct Caller<'a> {
    scope: &'a str,
    entry_point: &'a str,
    sub_entry_point: Option<&'a str>,
    reference: String,
}

/// The subEntityId Teams gives the app for a pane opened from a
/// conversation: the host settings, the context attributes (module 36414:
/// SupportedScenario for a chat or channel, HasUnreadMessageTime when the
/// conversation's unread time is known) and the base64 launch payload.
fn conversation_sub_entity(
    caller: &Caller,
    cmmid: &str,
    variants: &[String],
    attributes: &Value,
) -> String {
    let mut info = json!({ "scope": caller.scope, "entryPoint": caller.entry_point, "copilotReferenceId": caller.reference });
    if let Some(s) = caller.sub_entry_point {
        info["subEntryPoint"] = json!(s);
    }
    let mut payload =
        json!({ "id": "", "scenario": "Default", "chatType": "", "properties": {}, "version": 1 });
    if !cmmid.is_empty() {
        payload["referral"] = json!({ "cmmid": cmmid });
    }
    payload["callerInfo"] = info;
    payload["serverVariants"] = json!(variants);
    let mut sub =
        json!({ "hostSettings": { "enableDeeplinks": "true", "focusOnLoad": "Compose" } });
    if attributes.as_array().is_some_and(|a| !a.is_empty()) {
        sub["contextAttributes"] = attributes.clone();
    }
    sub["launchOptionPayload"] =
        json!(base64::engine::general_purpose::STANDARD.encode(payload.to_string()));
    sub.to_string()
}

/// Teams' context attributes for a chat ("ViewChat") or a channel thread
/// ("ViewChannel"); HasUnreadMessageTime says whether the conversation had
/// unread messages when the pane opened (its unread time, when known).
pub fn context_attributes(scenario: &str, unread_ms: Option<i64>) -> Value {
    let mut a = vec![json!({ "key": "SupportedScenario", "value": scenario })];
    if let Some(t) = unread_ms {
        a.push(
            json!({ "key": "HasUnreadMessageTime", "value": if t > 0 { "true" } else { "false" } }),
        );
    }
    Value::Array(a)
}

/// The pane's address: the chat page anchored on the conversation's
/// reference (`chat/sessionanchor/<reference>`, as Teams opens it).
fn anchored_url(m: &Meeting, reference: &str) -> String {
    content_url(m).replacen("/chat?", &format!("/chat/sessionanchor/{reference}?"), 1)
}

/// Copilot from a chat's header (Teams' CopilotFromChatHeader with
/// copilot.enableBizChatCopilotInChatLicensed: the Microsoft 365 Copilot
/// app as the chat's side pane; measured on winpc 2026-11-23). The launch
/// payload names scope "Chat", entry point "ChatPanel" and the chat's
/// reference (SHA-256 of its id); once the app is up the host tells it the
/// chat (`contextualChatChanged`, with the chat's unread time when it had
/// unread messages) and `updateCapabilities` [disableGPT5].
pub fn launch_chat(
    m: &Meeting,
    chat_id: &str,
    unread_ms: Option<i64>,
    cmmid: &str,
    variants: &[String],
) -> Value {
    let caller = Caller {
        scope: "Chat",
        entry_point: "ChatPanel",
        sub_entry_point: None,
        reference: reference_id(chat_id),
    };
    let attributes = context_attributes("ViewChat", unread_ms);
    let mut v = launch(m);
    v["url"] = json!(anchored_url(m, &caller.reference));
    v["context"]["subEntityId"] = json!(conversation_sub_entity(
        &caller,
        cmmid,
        variants,
        &attributes
    ));
    let mut chat = json!({ "context": "Chat", "chatId": chat_id });
    if let Some(t) = unread_ms.filter(|t| *t > 0) {
        chat["unreadMessageTime"] = json!(t);
    }
    v["contextualChat"] = json!({
        "contentType": "teams",
        "contentItems": [{ "contextType": "Chat", "chatContext": chat }],
        "contextAttributes": attributes,
    });
    v["capabilities"] = json!([{ "name": "disableGPT5" }]);
    v
}

/// A channel thread, as Copilot's pane names it.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ChannelThread {
    /// The team's thread (`19:…@thread.tacv2`).
    pub team_id: String,
    pub channel_id: String,
    /// The thread's first message.
    pub reply_chain_id: String,
    /// The team's group (AAD) id.
    pub group_id: String,
    pub tenant_id: String,
    /// The reference names the team too: a post's view (Teams' channel L2
    /// view: See details, Followed threads, a post's own window) hashes
    /// "{team}-{channel}-{post}" (measured 2026-11-23, TASK-0263).
    pub team_in_reference: bool,
}

/// Copilot from a channel thread's header (Teams' CopilotFromChannelsL2Header
/// with copilot.enableBizChatCopilotInChannelLicensed, measured on winpc
/// 2026-11-23): scope "Channel", entry point "ChannelL2", the reference the
/// SHA-256 of "{team}-{channel}-{thread}" with the team left empty as Teams
/// parses it from the thread's key (a post's view names the team); the
/// host then tells the app the thread (`channelContext`, "ViewChannel") and
/// [disableGPT5].
pub fn launch_channel(m: &Meeting, t: &ChannelThread, cmmid: &str, variants: &[String]) -> Value {
    let team = if t.team_in_reference {
        t.team_id.as_str()
    } else {
        ""
    };
    let reference = reference_id(&format!("{team}-{}-{}", t.channel_id, t.reply_chain_id));
    let caller = Caller {
        scope: "Channel",
        entry_point: "ChannelL2",
        sub_entry_point: None,
        reference,
    };
    let attributes = context_attributes("ViewChannel", None);
    let mut v = launch(m);
    v["url"] = json!(anchored_url(m, &caller.reference));
    v["context"]["subEntityId"] = json!(conversation_sub_entity(
        &caller,
        cmmid,
        variants,
        &attributes
    ));
    v["contextualChat"] = json!({
        "contentType": "teams",
        "contentItems": [{ "contextType": "Channel", "channelContext": {
            "context": "Channel", "channelId": t.channel_id, "replyChainId": t.reply_chain_id,
            "groupId": t.group_id, "teamId": t.team_id, "tenantId": t.tenant_id,
        } }],
        "contextAttributes": attributes,
    });
    v["capabilities"] = json!([{ "name": "disableGPT5" }]);
    v
}

/// Copilot from a meeting chat's header (Teams' CopilotFromMeetingChatHeader
/// with meetingCollaboration.enableBizChatCopilotForMeetingChat and
/// enableAlwaysOpenMeetingCopilotInChatSwitch, measured on winpc
/// 2026-11-23 with OST TEST 240 recap meeting): the app reads the meeting
/// (its transcript and recap) rather than the chat. Scope "Meeting", entry
/// point "ChatPanel" when the meeting has a transcript, else
/// "MeetingChatNoTranscript" (also its sub entry point), the reference the
/// SHA-256 of the call id; the meeting context's session is the live
/// meeting's (PrivateViewDuringMeeting) or "Recap", with the recording as
/// its vroomId, and no capabilities.
pub fn launch_meeting_chat(
    m: &Meeting,
    vroom_id: &str,
    live: bool,
    transcript: bool,
    cmmid: &str,
    variants: &[String],
) -> Value {
    let entry = if transcript {
        "ChatPanel"
    } else {
        "MeetingChatNoTranscript"
    };
    let caller = Caller {
        scope: "Meeting",
        entry_point: entry,
        sub_entry_point: (!transcript).then_some(entry),
        reference: reference_id(&m.call_id),
    };
    let mut v = launch(m);
    v["url"] = json!(anchored_url(m, &caller.reference));
    v["context"]["subEntityId"] = json!(conversation_sub_entity(
        &caller,
        cmmid,
        variants,
        &json!([])
    ));
    v["contextualChat"] = json!({
        "contentType": "teams",
        "contentItems": [{
            "contextType": "Meeting",
            "meetingContext": {
                "context": "Meeting",
                "callId": m.call_id,
                "organizerId": format!("{}@{}", m.organizer_id, m.organizer_tenant),
                "threadId": m.thread_id,
                "iCalUid": m.ical_uid,
                "sessionType": if live { "PrivateViewDuringMeeting" } else { "Recap" },
                "exchangeEventId": "",
                "vroomId": vroom_id,
                "subject": m.subject,
                "eventId": "",
            },
            "scenarioName": "TeamsMeetingSidepaneWorkCopilot",
        }],
    });
    v["capabilities"] = json!([]);
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode_sub(v: &Value) -> (Value, Value) {
        let sub: Value =
            serde_json::from_str(v["context"]["subEntityId"].as_str().unwrap()).unwrap();
        let payload: Value = serde_json::from_slice(
            &base64::engine::general_purpose::STANDARD
                .decode(sub["launchOptionPayload"].as_str().unwrap())
                .unwrap(),
        )
        .unwrap();
        (sub, payload)
    }

    #[test]
    fn chat_launch_is_teams_own() {
        // Measured: OST TEST group call's header Copilot on winpc.
        let variants: Vec<String> = ["feature.enableChatPrefetch", "cdxteamsimplicitlong"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let v = launch_chat(
            &meeting(),
            "19:0786033da79d46d5969877f18eb9bcc1@thread.v2",
            Some(1795036427598),
            CHAT_PANEL_CMMID,
            &variants,
        );
        let r = "caec159e3cf54080815034f4a13c3ecdd10201400fb79874b77c80a3af339be1";
        assert!(v["url"].as_str().unwrap().starts_with(&format!(
            "https://m365copilotapp.svc.cloud.microsoft/chat/sessionanchor/{r}?OID="
        )));
        let (sub, payload) = decode_sub(&v);
        assert_eq!(
            sub["contextAttributes"],
            json!([{ "key": "SupportedScenario", "value": "ViewChat" }, { "key": "HasUnreadMessageTime", "value": "true" }])
        );
        assert_eq!(
            payload,
            json!({ "id": "", "scenario": "Default", "chatType": "", "properties": {}, "version": 1, "referral": { "cmmid": "cmmnho609kr" },
            "callerInfo": { "scope": "Chat", "entryPoint": "ChatPanel", "copilotReferenceId": r }, "serverVariants": variants })
        );
        assert_eq!(
            v["contextualChat"]["contentItems"][0]["chatContext"],
            json!({ "context": "Chat", "chatId": "19:0786033da79d46d5969877f18eb9bcc1@thread.v2", "unreadMessageTime": 1795036427598_i64 })
        );
        assert_eq!(v["capabilities"], json!([{ "name": "disableGPT5" }]));
        // Nothing unread: no unread time.
        let v = launch_chat(&meeting(), "19:x@thread.v2", None, CHAT_PANEL_CMMID, &[]);
        assert_eq!(
            v["contextualChat"]["contextAttributes"],
            json!([{ "key": "SupportedScenario", "value": "ViewChat" }])
        );
        assert!(
            v["contextualChat"]["contentItems"][0]["chatContext"]
                .get("unreadMessageTime")
                .is_none()
        );
    }

    #[test]
    fn channel_launch_anchors_on_the_thread() {
        let t = ChannelThread {
            team_id: "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2".into(),
            channel_id: "19:327472fdfc5b4b6da9cf41c04467868c@thread.tacv2".into(),
            reply_chain_id: "1794312901896".into(),
            group_id: "1fac3ae3-c9c0-4ddb-90bb-58f52209c181".into(),
            tenant_id: "2716d134-5614-4856-a48d-2002edd9a570".into(),
            team_in_reference: false,
        };
        let v = launch_channel(&meeting(), &t, CHANNEL_L2_CMMID, &[]);
        // Measured: the frame's anchor for OST threads test's OST TEST 81 thread.
        assert!(v["url"].as_str().unwrap().contains(
            "/chat/sessionanchor/73c5697eb7fd8d3af336cb8d0c86fc7e53d9b4d960f7fc8ada3a0952ae2bef74?"
        ));
        let (sub, payload) = decode_sub(&v);
        assert_eq!(
            sub["contextAttributes"],
            json!([{ "key": "SupportedScenario", "value": "ViewChannel" }])
        );
        assert_eq!(
            (
                payload["callerInfo"]["scope"].as_str(),
                payload["callerInfo"]["entryPoint"].as_str()
            ),
            (Some("Channel"), Some("ChannelL2"))
        );
        let c = &v["contextualChat"]["contentItems"][0];
        assert_eq!(c["contextType"], "Channel");
        assert_eq!(c["channelContext"]["teamId"], t.team_id.as_str());
        assert_eq!(c["channelContext"]["replyChainId"], "1794312901896");
    }

    #[test]
    fn post_view_anchors_on_team_channel_and_post() {
        // Measured: OST Test Team > General, a meeting post's See details
        // (Posts layout), its Open Copilot frame's anchor.
        let general = "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2";
        let t = ChannelThread {
            team_id: general.into(),
            channel_id: general.into(),
            reply_chain_id: "1794379759264".into(),
            group_id: "1fac3ae3-c9c0-4ddb-90bb-58f52209c181".into(),
            tenant_id: "2716d134-5614-4856-a48d-2002edd9a570".into(),
            team_in_reference: true,
        };
        let v = launch_channel(&meeting(), &t, CHANNEL_L2_CMMID, &[]);
        assert!(v["url"].as_str().unwrap().contains(
            "/chat/sessionanchor/a375eae6b9882b4c9e417115f0f2e0a8c76312fb8d16c6283db259045a75130a?"
        ));
        let (_, payload) = decode_sub(&v);
        assert_eq!(payload["referral"]["cmmid"], "cmmce9gzagp");
        assert_eq!(payload["callerInfo"]["entryPoint"], "ChannelL2");
        assert_eq!(
            v["contextualChat"]["contentItems"][0]["channelContext"]["groupId"],
            "1fac3ae3-c9c0-4ddb-90bb-58f52209c181"
        );
    }

    #[test]
    fn meeting_chat_reads_the_meeting() {
        let mut m = meeting();
        m.call_id = "26943b81-750d-4061-abcb-3681fb8b4122".into();
        let v = launch_meeting_chat(&m, "SPO_x_01T", false, true, MEETING_CHAT_PANEL_CMMID, &[]);
        assert!(v["url"].as_str().unwrap().contains(
            "/chat/sessionanchor/2bc77d8763fe657bdef3fe99bbaa30cb3ba852aa44d0b674c90f7a28992063dc?"
        ));
        let (sub, payload) = decode_sub(&v);
        assert!(sub.get("contextAttributes").is_none());
        assert_eq!(
            payload["callerInfo"],
            json!({ "scope": "Meeting", "entryPoint": "ChatPanel", "copilotReferenceId": reference_id(&m.call_id) })
        );
        assert_eq!(payload["serverVariants"], json!([]));
        let mc = &v["contextualChat"]["contentItems"][0]["meetingContext"];
        assert_eq!(
            (
                mc["sessionType"].as_str(),
                mc["vroomId"].as_str(),
                mc["eventId"].as_str()
            ),
            (Some("Recap"), Some("SPO_x_01T"), Some(""))
        );
        assert!(mc.get("isTranscriptRunningDuringMeeting").is_none());
        assert_eq!(v["capabilities"], json!([]));
        let v = launch_meeting_chat(&m, "", true, false, MEETING_CHAT_NO_TRANSCRIPT_CMMID, &[]);
        let (_, payload) = decode_sub(&v);
        assert_eq!(
            payload["callerInfo"]["subEntryPoint"],
            "MeetingChatNoTranscript"
        );
        assert_eq!(
            v["contextualChat"]["contentItems"][0]["meetingContext"]["sessionType"],
            "PrivateViewDuringMeeting"
        );
    }

    fn meeting() -> Meeting {
        Meeting {
            call_id: "58ff6acc-d237-4fe8-a41a-f228efde81f1".into(),
            thread_id: "19:meeting_x@thread.v2".into(),
            organizer_id: "4287e791-1b98-4963-8b94-281c50472683".into(),
            organizer_tenant: "2716d134-5614-4856-a48d-2002edd9a570".into(),
            ical_uid: "0400".into(),
            message_id: "0".into(),
            subject: "OST calendar test: created from OST".into(),
            transcript_running: true,
            user_oid: "4287e791-1b98-4963-8b94-281c50472683".into(),
            tenant_id: "2716d134-5614-4856-a48d-2002edd9a570".into(),
            my_site: "scnetsolutions-my.sharepoint.com".into(),
            culture: "en-us".into(),
            theme: "default".into(),
            app_session: "s1".into(),
            host_session: "s0".into(),
        }
    }

    #[test]
    fn the_reference_is_the_call_ids_hash() {
        // Measured: this call's copilotReferenceId in Teams' launch payload.
        assert_eq!(
            reference_id("58ff6acc-d237-4fe8-a41a-f228efde81f1"),
            "0f8806193913b2cf161b4626f94ae72a0089671aeebaed0a42013e628eeba16c"
        );
    }

    #[test]
    fn the_payload_is_teams_own() {
        // Teams' payload for that call, byte for byte.
        let teams = "eyJpZCI6IiIsInNjZW5hcmlvIjoiRGVmYXVsdCIsImNoYXRUeXBlIjoiIiwicHJvcGVydGllcyI6e30sInZlcnNpb24iOjEsInJlZmVycmFsIjp7ImNtbWlkIjoiY21tMzVnMDRxYnMifSwiY2FsbGVySW5mbyI6eyJzY29wZSI6Ik1lZXRpbmciLCJlbnRyeVBvaW50IjoiUHJpdmF0ZVZpZXdEdXJpbmdNZWV0aW5nIiwiY29waWxvdFJlZmVyZW5jZUlkIjoiMGY4ODA2MTkzOTEzYjJjZjE2MWI0NjI2Zjk0YWU3MmEwMDg5NjcxYWVlYmFlZDBhNDIwMTNlNjI4ZWViYTE2YyJ9LCJzZXJ2ZXJWYXJpYW50cyI6W119";
        let decode = |s: &str| {
            serde_json::from_slice::<Value>(
                &base64::engine::general_purpose::STANDARD.decode(s).unwrap(),
            )
            .unwrap()
        };
        assert_eq!(decode(&launch_payload(&meeting())), decode(teams));
    }

    #[test]
    fn the_frame_address_and_events() {
        let m = meeting();
        let u = content_url(&m);
        assert!(u.starts_with("https://m365copilotapp.svc.cloud.microsoft/chat?OID=4287e791-1b98-4963-8b94-281c50472683%402716d134"));
        assert!(
            u.contains("renderingSurface=copilotSidePanel")
                && u.contains("mysite=scnetsolutions-my.sharepoint.com")
        );
        // Teams names the ring between the theme and the parent session
        // ("general" until the ECS settings are in).
        assert!(u.contains("&theme=default&hostRing=general&parentSessionId=s0"));
        let c = contextual_chat(&m);
        assert_eq!(
            c["contentItems"][0]["meetingContext"]["organizerId"],
            "4287e791-1b98-4963-8b94-281c50472683@2716d134-5614-4856-a48d-2002edd9a570"
        );
        assert_eq!(
            c["contentItems"][0]["meetingContext"]["isTranscriptRunningDuringMeeting"],
            true
        );
        assert_eq!(
            c["contentItems"][0]["scenarioName"],
            "TeamsMeetingSidepaneWorkCopilot"
        );
        let sub: Value = serde_json::from_str(&sub_entity_id(&m)).unwrap();
        assert_eq!(sub["hostSettings"]["focusOnLoad"], "Compose");
        assert_eq!(
            launch(&m)["context"]["renderingSurface"],
            "copilotSidePanel"
        );
        assert_eq!(launch(&m)["context"]["appIconPosition"], -17);
    }
    #[test]
    fn search_launch_anchors_on_the_session() {
        let m = meeting();
        let v = launch_search(
            &m,
            "session-1",
            "what meetings do I have today",
            "cmmi7lmhneb",
        );
        let r = reference_id("session-1");
        assert!(v["url"].as_str().unwrap().starts_with(&format!(
            "https://m365copilotapp.svc.cloud.microsoft/chat/sessionanchor/{r}?OID="
        )));
        let sub: Value =
            serde_json::from_str(v["context"]["subEntityId"].as_str().unwrap()).unwrap();
        let payload: Value = serde_json::from_slice(
            &base64::engine::general_purpose::STANDARD
                .decode(sub["launchOptionPayload"].as_str().unwrap())
                .unwrap(),
        )
        .unwrap();
        assert_eq!(payload["callerInfo"]["scope"], "Search");
        assert_eq!(
            payload["callerInfo"]["entryPoint"],
            "SearchAutosuggestAskCopilot"
        );
        assert_eq!(payload["callerInfo"]["copilotReferenceId"], r.as_str());
        assert_eq!(payload["referral"]["cmmid"], "cmmi7lmhneb");
        assert_eq!(
            v["contextualChat"]["contentItems"][0]["contextType"],
            "Search"
        );
        assert_eq!(v["prompt"]["promptText"], "what meetings do I have today");
        assert_eq!(
            v["prompt"]["queryAnnotations"][0]["messageAnnotationMetadata"]["searchType"],
            "AllTab"
        );
    }
}
