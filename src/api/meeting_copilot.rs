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
    Sha256::digest(call_id.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
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
            .append_pair("culture", if m.culture.is_empty() { "en-us" } else { &m.culture });
        if !m.my_site.is_empty() {
            q.append_pair("mysite", &m.my_site);
        }
        q.append_pair("hostName", "TeamsModern")
            .append_pair("hostClientType", "desktop")
            .append_pair("sessionId", &m.app_session)
            .append_pair("renderingSurface", "copilotSidePanel")
            .append_pair("theme", if m.theme.is_empty() { "default" } else { &m.theme })
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
            "isFullScreen": true,
            "userLicenseType": "Copilot",
            "mySiteDomain": m.my_site,
        },
        "contextualChat": contextual_chat(m),
        "capabilities": capabilities(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert_eq!(reference_id("58ff6acc-d237-4fe8-a41a-f228efde81f1"), "0f8806193913b2cf161b4626f94ae72a0089671aeebaed0a42013e628eeba16c");
    }

    #[test]
    fn the_payload_is_teams_own() {
        // Teams' payload for that call, byte for byte.
        let teams = "eyJpZCI6IiIsInNjZW5hcmlvIjoiRGVmYXVsdCIsImNoYXRUeXBlIjoiIiwicHJvcGVydGllcyI6e30sInZlcnNpb24iOjEsInJlZmVycmFsIjp7ImNtbWlkIjoiY21tMzVnMDRxYnMifSwiY2FsbGVySW5mbyI6eyJzY29wZSI6Ik1lZXRpbmciLCJlbnRyeVBvaW50IjoiUHJpdmF0ZVZpZXdEdXJpbmdNZWV0aW5nIiwiY29waWxvdFJlZmVyZW5jZUlkIjoiMGY4ODA2MTkzOTEzYjJjZjE2MWI0NjI2Zjk0YWU3MmEwMDg5NjcxYWVlYmFlZDBhNDIwMTNlNjI4ZWViYTE2YyJ9LCJzZXJ2ZXJWYXJpYW50cyI6W119";
        let decode = |s: &str| serde_json::from_slice::<Value>(&base64::engine::general_purpose::STANDARD.decode(s).unwrap()).unwrap();
        assert_eq!(decode(&launch_payload(&meeting())), decode(teams));
    }

    #[test]
    fn the_frame_address_and_events() {
        let m = meeting();
        let u = content_url(&m);
        assert!(u.starts_with("https://m365copilotapp.svc.cloud.microsoft/chat?OID=4287e791-1b98-4963-8b94-281c50472683%402716d134"));
        assert!(u.contains("renderingSurface=copilotSidePanel") && u.contains("mysite=scnetsolutions-my.sharepoint.com"));
        let c = contextual_chat(&m);
        assert_eq!(c["contentItems"][0]["meetingContext"]["organizerId"], "4287e791-1b98-4963-8b94-281c50472683@2716d134-5614-4856-a48d-2002edd9a570");
        assert_eq!(c["contentItems"][0]["meetingContext"]["isTranscriptRunningDuringMeeting"], true);
        assert_eq!(c["contentItems"][0]["scenarioName"], "TeamsMeetingSidepaneWorkCopilot");
        let sub: Value = serde_json::from_str(&sub_entity_id(&m)).unwrap();
        assert_eq!(sub["hostSettings"]["focusOnLoad"], "Compose");
        assert_eq!(launch(&m)["context"]["renderingSurface"], "copilotSidePanel");
    }
}
