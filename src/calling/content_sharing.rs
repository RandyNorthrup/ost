//! Teams' content-sharing sessions (docs/spec/content-sharing.md): what a
//! Microsoft Whiteboard, PowerPoint Live, Excel Live or Annotate share is
//! on the wire.
//!
//! A presenter adds a `contentSharing` modality to the call's conversation
//! (`POST links.addModality`, header `X-Microsoft-Skype-ContentSharing-
//! Chain-ID: <correlation id>`); its `identifier` is the base64 of the
//! UTF-8 JSON of the content (Teams' sharing-content DTO: `type`
//! "whiteboard", "ppt", "extensible_app" or "annotation", with the board's
//! or file's address). The conversation answers on the trouter callback
//! `conversation/addModalitySuccess/` with the session's links; everyone
//! else finds the session in the roster (the presenter's endpoint's
//! `contentSharing.sessionInformation`), joins it (`POST
//! sessionInformation.contentSharingController`) and from then on gets the
//! presenter's state updates (`conversation/contentSharingUpdate/`) until
//! it ends (`conversation/contentSharingEnd/`). The presenter changes the
//! state with `POST links.updateSessionState` and stops with `DELETE
//! links.contentSharingController`. (Teams' calling-pluginless `XV`, `rG`,
//! `QV`, `ZV`; 89637 `createContentSharingSession`, `buildSharingContentDto`.)

use base64::Engine;
use serde::Serialize;
use serde_json::{Value, json};

/// The header that carries a session's correlation id on its requests.
pub const CHAIN_ID_HEADER: &str = "X-Microsoft-Skype-ContentSharing-Chain-ID";

/// Microsoft Whiteboard's Teams app (the board's host app).
pub const WHITEBOARD_APP_ID: &str = "95de633a-083e-42f5-b444-a4295d8e9314";
/// Excel's Teams app (Excel Live: Teams' officeAppsMeetingConfigs).
pub const EXCEL_APP_ID: &str = "1c256a65-83a6-4b5c-9ccf-78f8afb6f1e8";
/// PowerPoint's Teams app.
pub const POWERPOINT_APP_ID: &str = "3e0a4fec-499b-4138-8e7c-71a9d88a62ed";

/// Teams' `meetingType` on a board's address (89637 `Tm`): 0 a scheduled
/// private meeting, 1 a private ad hoc (Meet now), 2 a scheduled channel
/// meeting, 3 a channel's Meet now, 4 a group call, 5 a 1:1 call, 6
/// anything else.
pub fn meeting_type(
    scheduled: bool,
    adhoc: bool,
    channel: bool,
    group_call: bool,
    p2p: bool,
) -> u8 {
    match (p2p, group_call, channel, scheduled, adhoc) {
        (true, ..) => 5,
        (_, true, ..) => 4,
        (_, _, true, true, _) => 2,
        (_, _, true, _, _) => 3,
        (_, _, _, true, _) => 0,
        (_, _, _, _, true) => 1,
        _ => 6,
    }
}

/// Teams' `meetingId` on a board's address: base64 of `0#{chat}#0`.
pub fn meeting_id(thread: &str) -> String {
    base64::engine::general_purpose::STANDARD.encode(format!("0#{thread}#0"))
}

/// The session identifier for `content`: base64 of its UTF-8 JSON (Teams'
/// `btoa(encodeURIComponent(json))` round trip).
pub fn encode_identifier(content: &Value) -> String {
    base64::engine::general_purpose::STANDARD.encode(content.to_string().as_bytes())
}

/// The content an identifier names, if it is one.
pub fn decode_identifier(identifier: &str) -> Option<Value> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(identifier.trim())
        .or_else(|_| {
            base64::engine::general_purpose::STANDARD_NO_PAD
                .decode(identifier.trim().trim_end_matches('='))
        })
        .ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// The content's type ("whiteboard", "ppt", "extensible_app",
/// "annotation"…; Teams' `getContentSharingType`).
pub fn content_type(content: &Value) -> &str {
    content.get("type").and_then(Value::as_str).unwrap_or("")
}

/// A Whiteboard share's content (89637 `WhiteboardProvider` / `UY`): the
/// meeting chat, its message ("0" for a meeting), the board's address.
pub fn whiteboard_content(
    conversation: &str,
    message_id: &str,
    url: &str,
    initiator_participant: &str,
) -> Value {
    json!({
        "appId": WHITEBOARD_APP_ID,
        "type": "whiteboard",
        "conversationId": conversation,
        "messageId": message_id,
        "url": url,
        "shareUrl": "",
        "loaderLabel": "",
        "initiatorParticipantId": initiator_participant,
        "permittedFileUsers": [],
        "initialNoteContent": [],
    })
}

/// Annotate's content, as Teams' sharer starts it (seen live 2026-11-18;
/// 89637 onSessionStarting): the meeting's annotation board with the
/// shared screen's facts — `shareUrl` the board's address, `url` the same
/// with a fresh `geometryId` — and no state until Whiteboard reports.
pub fn annotation_content(
    conversation: &str,
    message_id: &str,
    share_url: &str,
    url: &str,
) -> Value {
    json!({
        "appId": "annotation",
        "conversationId": conversation,
        "initialNoteContent": [],
        "loaderLabel": "annotation",
        "messageId": message_id,
        "permittedFileUsers": [],
        "shareUrl": share_url,
        "type": "annotation",
        "url": url,
    })
}

/// The shared screen, as Annotate's board is told about it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SharedScreen {
    /// Its size in device pixels (Teams: the screen's size × DPR).
    pub width: u32,
    pub height: u32,
    /// A whole screen (Teams' sharingSourceType 1) or a window (2).
    pub window: bool,
}

/// Annotate's board address for the session (89637 appendAnnotationInitUrl
/// and onSessionStarting): the meeting's board (`board`, with its
/// initiator), `annotation=true` if missing, `sharedScreenWidth`,
/// `sharedScreenFullHeight`, `isScreenSharerOnT2=true`,
/// `sharingSourceType` and `osType` (Teams' OS name and version, e.g.
/// "windowsNT 10.0"; "linux" here). Returns (shareUrl, url): the url adds
/// `geometryId`.
pub fn annotation_urls(
    board: &str,
    screen: SharedScreen,
    os_type: &str,
    geometry_id: &str,
) -> (String, String) {
    let mut base = board.to_string();
    if !base.contains("annotation=true") {
        base.push_str(if base.contains('?') {
            "&annotation=true"
        } else {
            "?annotation=true"
        });
    }
    base.push_str(&format!(
        "&sharedScreenWidth={}&sharedScreenFullHeight={}&isScreenSharerOnT2=true&sharingSourceType={}",
        screen.width,
        screen.height,
        if screen.window { 2 } else { 1 }
    ));
    let share = format!("{base}&osType={os_type}");
    let url = format!(
        "{base}&osType={}&geometryId={geometry_id}",
        os_type.replace(' ', "+")
    );
    (share, url)
}

/// An Excel Live share's content, as Teams presents it (seen live
/// 2026-11-18): the Excel app's meeting stage page for the file, its
/// context while the app preloads (`appLoadState` "preLoadApp", the file's
/// SharePoint unique id) and the file's substrate id.
pub fn excel_content(
    conversation: &str,
    message_id: &str,
    url: &str,
    app_name: &str,
    file_id: &str,
    substrate_id: &str,
) -> Value {
    let context =
        json!({ "permittedFileUsers": [], "appLoadState": "preLoadApp", "fileId": file_id })
            .to_string();
    json!({
        "appId": EXCEL_APP_ID,
        "conversationId": format!("{conversation}|{EXCEL_APP_ID}"),
        "extensibleAppContext": context,
        "initialNoteContent": [],
        "loaderLabel": app_name,
        "messageId": message_id,
        "permittedFileUsers": [],
        "shareUrl": "",
        "substrateId": substrate_id,
        "type": "extensible_app",
        "url": url,
    })
}

/// An Excel Live share's state once the workbook is shared with the
/// meeting (Teams' "fullLoadApp"): who may open it and the file.
pub fn excel_state(permitted: &[String], file_id: &str) -> String {
    json!({ "url": "", "extensibleAppContext": { "permittedFileUsers": permitted, "appLoadState": "fullLoadApp", "fileId": file_id } }).to_string()
}

/// A SharePoint file's substrate id (Teams' `substrateId`): "SPO_", the
/// unpadded base64 of "{siteId},{webId},{listId}", "_", the drive item id.
pub fn substrate_id(site_id: &str, web_id: &str, list_id: &str, item_id: &str) -> String {
    let ids = base64::engine::general_purpose::STANDARD_NO_PAD
        .encode(format!("{site_id},{web_id},{list_id}"));
    format!("SPO_{ids}_{item_id}")
}

/// What a PowerPoint Live share names (89637 `buildSharingContentDto`).
#[derive(Debug, Clone, Default)]
pub struct PptFile {
    /// `siteId_listId_listItemUniqueId`.
    pub id: String,
    pub name: String,
    /// The file's address (its webDavUrl).
    pub url: String,
    /// A download address (`@content.downloadUrl`).
    pub download_url: String,
    pub web_dav_url: String,
    pub web_url: String,
    pub size: u64,
    pub etag: String,
    pub site_id: String,
    pub list_item_unique_id: String,
    /// openWith.wac.applicationUrl and bootstrapperUrl.
    pub wac_url: String,
    pub bootstrapper_url: String,
    pub major_version: u64,
    /// The snap service's presentation address (attendees render it).
    pub snap_url: String,
    pub correlation_id: String,
    pub presenter_start: u64,
}

pub fn ppt_content(f: &PptFile) -> Value {
    json!({
        "type": "ppt",
        "id": f.id,
        "name": f.name,
        "url": f.url,
        "fileGetUrl": f.download_url,
        "canonicalFileUrl": format!("{}/_vti_bin/cellstorage.svc/CellStorageService", f.web_dav_url),
        "customFontCatalogUrl": "",
        "majorVersion": f.major_version.max(1),
        "fileSize": f.size,
        "etag": f.etag,
        "siteId": f.site_id,
        "listItemUniqueId": f.list_item_unique_id,
        "wacUrl": f.wac_url,
        "webUrl": f.web_url,
        "bootstrapperUrl": f.bootstrapper_url,
        "source": "onedrive",
        "preRefreshSlide": false,
        "correlationId": f.correlation_id,
        "contentBundleUrl": "dummy-url",
        "isPresentationUrlEnabledForPresenter": false,
        "disablePrivatePreview": false,
        "presenterStartTime": f.presenter_start,
        "snapPresentationUrl": f.snap_url,
        "snapPresentationUrlCreationTime": f.presenter_start,
    })
}

/// `POST links.addModality`: start sharing `identifier` (calling-pluginless
/// `XV`). `cb(path)` makes a trouter callback address.
pub fn add_modality_body(
    from: &Value,
    identifier: &str,
    subject: &str,
    state: Option<&str>,
    cb: &dyn Fn(&str) -> String,
) -> Value {
    json!({
        "participants": { "from": from, "to": [] },
        "contentSharing": {
            "identifier": identifier,
            "subject": subject,
            "sessionState": state,
            "sequenceNumber": 1,
            "links": {
                "sessionUpdate": cb("conversation/contentSharingUpdate/"),
                "sessionEnd": cb("conversation/contentSharingEnd/"),
            },
        },
        "links": {
            "addModalitySuccess": cb("conversation/addModalitySuccess/"),
            "addModalityFailure": cb("conversation/addModalityFailure/"),
        },
    })
}

/// `POST links.updateSessionState` (calling-pluginless `rG`): the
/// presenter's new state, numbered from 1.
pub fn update_state_body(from: &Value, sequence: u64, state: &str, operation_id: &str) -> Value {
    json!({
        "operationId": operation_id,
        "sessionUpdateSequenceNumber": sequence,
        "sessionState": state,
        "participants": { "from": from },
    })
}

/// `POST sessionInformation.contentSharingController` (calling-pluginless
/// `QV`): a viewer joins the session to get its updates.
pub fn join_body(from: &Value, cb: &dyn Fn(&str) -> String) -> Value {
    json!({
        "contentSharing": { "links": {
            "sessionUpdate": cb("conversation/contentSharingUpdate/"),
            "sessionEnd": cb("conversation/contentSharingEnd/"),
        } },
        "participants": { "from": from },
    })
}

/// `DELETE links.contentSharingController` (calling-pluginless `ZV`):
/// Stop presenting.
pub fn stop_body(from: &Value) -> Value {
    json!({
        "contentSharingTransactionEnd": { "code": 0, "subCode": 0, "phrase": "CallEndReasonLocalUserInitiated" },
        "participants": { "from": from },
    })
}

/// `POST links.takeControl` (Teams' PPTSharingSession.takeControl,
/// calling-pluginless `eG`): an attendee takes the presentation over. The
/// answer names the new presenter; everyone (the old presenter too) then
/// gets a `contentSharingUpdate` naming them.
pub fn take_control_body(from: &Value) -> Value {
    json!({ "participants": { "from": from } })
}

/// Who presents a session now, from a `contentSharingUpdate` or a take
/// control answer: (correlation id, the presenter's MRI, lower case).
pub fn update_presenter(event: &Value) -> Option<(String, String)> {
    let b = body(event);
    let b = b.get("contentSharing").unwrap_or(b);
    let p = b.get("presenter")?;
    let id = p
        .get("id")
        .or(Some(p))
        .and_then(Value::as_str)?
        .to_ascii_lowercase();
    let corr = b
        .get("contentSharingCorrelationId")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    (!id.is_empty()).then_some((corr, id))
}

/// Teams' PowerPoint Live pointer events (laser, cursor) go to the
/// meeting as a proxied "LiveInking" message (89637 `sendLiveInkingMessage`)
/// on the conversation's message link, like reactions: the annotation
/// event as a JSON string in `payload.EventData`.
pub fn live_inking_body(me: &Value, event_data: &str, operation: &str) -> Value {
    json!({
        "from": {
            "displayName": me["displayName"],
            "endpointId": me["endpointId"],
            "id": me["id"],
            "languageId": me.get("languageId").cloned().unwrap_or(json!("")),
            "participantId": me["participantId"],
        },
        "messageContent": [{
            "operationId": operation,
            "payload": { "EventData": event_data },
            "scope": "all",
            "to": [],
            "type": "LiveInking",
        }],
    })
}

/// LiveInking messages in a call event (`conversation/receiveMessage/`):
/// (sender participant id, sender MRI, the EventData JSON string).
pub fn live_inking(event: &Value) -> Vec<(String, String, String)> {
    if !path(event).starts_with("conversation/receiveMessage") {
        return Vec::new();
    }
    let b = body(event);
    let list: Vec<&Value> = match b.get("messageContent").and_then(Value::as_array) {
        Some(l) => l.iter().collect(),
        None => vec![b],
    };
    let from = b.get("from").or_else(|| event.get("from"));
    list.into_iter()
        .filter(|m| m.get("type").and_then(Value::as_str) == Some("LiveInking"))
        .filter_map(|m| {
            let data = m
                .pointer("/payload/EventData")
                .and_then(Value::as_str)?
                .to_string();
            let f = m.get("from").or(from);
            let s = |k: &str| {
                f.and_then(|f| f.get(k))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
            Some((s("participantId"), s("id").to_ascii_lowercase(), data))
        })
        .collect()
}

/// A session's links, from addModalitySuccess or a join's answer.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SessionLinks {
    pub controller: Option<String>,
    pub update_state: Option<String>,
    pub take_control: Option<String>,
    pub leave: Option<String>,
}

impl SessionLinks {
    /// Take the links `other` has (a take control answer's) over ours.
    pub fn merge(&mut self, other: SessionLinks) {
        for (mine, theirs) in [
            (&mut self.controller, other.controller),
            (&mut self.update_state, other.update_state),
            (&mut self.take_control, other.take_control),
            (&mut self.leave, other.leave),
        ] {
            if theirs.is_some() {
                *mine = theirs;
            }
        }
    }

    pub fn from(links: &Value) -> SessionLinks {
        let s = |k: &str| {
            links
                .get(k)
                .and_then(Value::as_str)
                .filter(|u| super::incoming::is_service_link(u))
                .map(str::to_string)
        };
        SessionLinks {
            controller: s("contentSharingController"),
            update_state: s("updateSessionState"),
            take_control: s("takeControl"),
            leave: s("leave"),
        }
    }
}

/// A content-sharing session as OST shows it (the call window's
/// `callContentJson`).
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub correlation_id: String,
    pub session_id: String,
    /// Who presents (an MRI) and their name.
    pub presenter: String,
    pub presenter_name: String,
    /// The content (the decoded identifier).
    pub content: Value,
    #[serde(skip)]
    pub identifier: String,
    pub subject: String,
    /// The latest session state (a JSON string, as Teams keeps it).
    pub state: String,
    pub sequence: u64,
    /// We present it.
    pub mine: bool,
    /// The address a viewer joins at.
    #[serde(skip)]
    pub join_link: Option<String>,
    #[serde(skip)]
    pub links: SessionLinks,
}

impl Session {
    pub fn kind(&self) -> &str {
        content_type(&self.content)
    }
}

/// The trouter path of a call event.
fn path(event: &Value) -> &str {
    event
        .get("callAgentPath")
        .and_then(Value::as_str)
        .unwrap_or("")
}

fn body(event: &Value) -> &Value {
    event.get("body").unwrap_or(event)
}

/// `conversation/addModalitySuccess/` for a content-sharing session:
/// (correlation id, session id, links, state).
pub fn add_modality_success(
    event: &Value,
) -> Option<(String, String, SessionLinks, Option<String>)> {
    if !path(event).contains("addModalitySuccess") {
        return None;
    }
    let cs = body(event)
        .pointer("/modalitySuccess/contentSharing")
        .or_else(|| body(event).get("contentSharing"))?;
    let s = |k: &str| {
        cs.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    Some((
        s("contentSharingCorrelationId"),
        s("sessionId"),
        SessionLinks::from(cs.get("links").unwrap_or(&Value::Null)),
        cs.get("sessionState")
            .and_then(Value::as_str)
            .map(str::to_string),
    ))
}

/// `conversation/addModalityFailure/` for a content-sharing session:
/// Teams' phrase (or code) for why it failed.
pub fn add_modality_failure(event: &Value) -> Option<String> {
    if !path(event).contains("addModalityFailure") {
        return None;
    }
    let f = body(event)
        .pointer("/modalityFailure/contentSharing")
        .or_else(|| body(event).get("contentSharing"))?;
    let end = f
        .get("transactionEnd")
        .or_else(|| f.get("contentSharingTransactionEnd"))
        .unwrap_or(f);
    Some(
        end.get("phrase")
            .and_then(Value::as_str)
            .map(str::to_string)
            .unwrap_or_else(|| {
                format!(
                    "{} / {}",
                    end.get("code").unwrap_or(&Value::Null),
                    end.get("subCode").unwrap_or(&Value::Null)
                )
            }),
    )
}

/// A state update (`conversation/contentSharingUpdate/`): (correlation
/// id, state, sequence number).
pub fn session_update(event: &Value) -> Option<(String, String, u64)> {
    if !path(event).contains("contentSharingUpdate") {
        return None;
    }
    let b = body(event);
    let b = b.get("contentSharing").unwrap_or(b);
    Some((
        b.get("contentSharingCorrelationId")
            .and_then(Value::as_str)?
            .to_string(),
        b.get("sessionState")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        b.get("sequenceNumber")
            .or_else(|| b.get("sessionUpdateSequenceNumber"))
            .and_then(Value::as_u64)
            .unwrap_or(0),
    ))
}

/// The end of a session (`conversation/contentSharingEnd/`): its
/// correlation id.
pub fn session_end(event: &Value) -> Option<String> {
    if !path(event).contains("contentSharingEnd") {
        return None;
    }
    let b = body(event);
    let b = b.get("contentSharing").unwrap_or(b);
    b.get("contentSharingCorrelationId")
        .and_then(Value::as_str)
        .map(str::to_string)
}

/// The sessions a roster participant presents (Teams'
/// `handleIncomingContentSharingFromRoster`): each endpoint's
/// `contentSharing.sessionInformation` with role "presenter", as JSON.
pub fn presenter_sessions(participant: &Value) -> Vec<String> {
    participant
        .get("endpoints")
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|e| e.values())
        .filter_map(|ep| ep.pointer("/contentSharing/sessionInformation"))
        .filter(|s| {
            s.get("role")
                .and_then(Value::as_str)
                .is_some_and(|r| r.eq_ignore_ascii_case("presenter"))
        })
        .map(Value::to_string)
        .collect()
}

/// A session from a roster's `sessionInformation` (its JSON as
/// [`presenter_sessions`] keeps it).
pub fn session_from_roster(info: &str, presenter: &str, presenter_name: &str) -> Option<Session> {
    let v: Value = serde_json::from_str(info).ok()?;
    let s = |k: &str| {
        v.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let identifier = s("identifier");
    Some(Session {
        correlation_id: s("contentSharingCorrelationId"),
        session_id: s("contentSharingSessionId"),
        presenter: presenter.to_string(),
        presenter_name: presenter_name.to_string(),
        content: decode_identifier(&identifier).unwrap_or(Value::Null),
        identifier,
        subject: s("subject"),
        state: s("sessionState"),
        sequence: 0,
        mine: false,
        join_link: v
            .get("contentSharingController")
            .and_then(Value::as_str)
            .filter(|u| super::incoming::is_service_link(u))
            .map(str::to_string),
        links: SessionLinks::default(),
    })
}

/// A Whiteboard state (Teams' `sendSessionUpdate`): the board's address,
/// Whiteboard's pass-through data and who started the board.
pub fn board_state(url: &str, pass_through: Option<&Value>, initiator: Option<&str>) -> String {
    let mut v = json!({ "url": url });
    if let Some(p) = pass_through {
        v["passThrough"] = p.clone();
    }
    if let Some(i) = initiator.filter(|i| !i.is_empty()) {
        v["initiatorParticipantId"] = i.into();
    }
    v.to_string()
}

/// The board address a state names, if any.
pub fn state_url(state: &str) -> Option<String> {
    serde_json::from_str::<Value>(state)
        .ok()?
        .get("url")?
        .as_str()
        .filter(|u| !u.is_empty())
        .map(str::to_string)
}

/// Whether `url` is one of Whiteboard's addresses (ECS
/// `whiteboardUrlRegexp`: `^https://((int.|app.|app.int.|dev.)?whiteboard
/// .microsoft.com|whiteboard.cloud(.dev)?.microsoft)(:443)?([/?#]|$)`).
pub fn is_whiteboard_url(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("https://") else {
        return false;
    };
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let host = rest[..end].strip_suffix(":443").unwrap_or(&rest[..end]);
    matches!(
        host,
        "whiteboard.microsoft.com"
            | "int.whiteboard.microsoft.com"
            | "app.whiteboard.microsoft.com"
            | "app.int.whiteboard.microsoft.com"
            | "dev.whiteboard.microsoft.com"
            | "whiteboard.cloud.microsoft"
            | "whiteboard.cloud.dev.microsoft"
    )
}

/// A board's address with Teams' stage parameters (89637 `Tm`):
/// `meetingType`, `meetingTenantId` and, for a viewer,
/// `participantTimestamp`.
pub fn stage_url(
    url: &str,
    meeting_type: u8,
    tenant: &str,
    presenter: bool,
    now_ms: u64,
) -> String {
    let mut out = url.to_string();
    let sep = |s: &str| if s.contains('?') { '&' } else { '?' };
    out.push(sep(&out));
    out.push_str(&format!(
        "meetingType={meeting_type}&meetingTenantId={tenant}"
    ));
    if !presenter {
        out.push_str(&format!("&participantTimestamp={now_ms}"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identifiers_round_trip_utf8() {
        let c = whiteboard_content(
            "19:meeting_x@thread.v2",
            "0",
            "https://app.whiteboard.microsoft.com/meeting?embed=1&meetingTitle=Café",
            "p1",
        );
        let id = encode_identifier(&c);
        assert_eq!(decode_identifier(&id), Some(c.clone()));
        assert_eq!(content_type(&c), "whiteboard");
        // Teams' btoa(encodeURIComponent) of {"type":"ppt"}.
        assert_eq!(
            decode_identifier("eyJ0eXBlIjoicHB0In0="),
            Some(json!({"type": "ppt"}))
        );
        assert_eq!(decode_identifier("not base64!"), None);
    }

    #[test]
    fn add_modality_matches_teams() {
        let cb = |p: &str| format!("https://trouter/cb/{p}");
        let from = json!({"id": "8:orgid:a", "displayName": "A", "endpointId": "e", "participantId": "p", "languageId": "en-US"});
        let b = add_modality_body(&from, "ID", "deck.pptx", None, &cb);
        assert_eq!(b["contentSharing"]["identifier"], "ID");
        assert_eq!(b["contentSharing"]["subject"], "deck.pptx");
        assert!(b["contentSharing"]["sessionState"].is_null());
        assert_eq!(b["contentSharing"]["sequenceNumber"], 1);
        assert_eq!(
            b["contentSharing"]["links"]["sessionUpdate"],
            "https://trouter/cb/conversation/contentSharingUpdate/"
        );
        assert_eq!(
            b["links"]["addModalitySuccess"],
            "https://trouter/cb/conversation/addModalitySuccess/"
        );
        assert_eq!(b["participants"]["to"], json!([]));
        let s = stop_body(&from);
        assert_eq!(
            s["contentSharingTransactionEnd"]["phrase"],
            "CallEndReasonLocalUserInitiated"
        );
        let u = update_state_body(&from, 3, "{\"url\":\"x\"}", "op");
        assert_eq!(u["sessionUpdateSequenceNumber"], 3);
        assert_eq!(u["sessionState"], "{\"url\":\"x\"}");
    }

    #[test]
    fn events_parse() {
        let ok = json!({"callAgentPath": "conversation/addModalitySuccess/", "body": {"modalitySuccess": {"contentSharing": {
            "sessionId": "s1", "contentSharingCorrelationId": "c1", "sessionState": null,
            "links": {"contentSharingController": "https://api.flightproxy.teams.microsoft.com/a", "updateSessionState": "https://api.flightproxy.teams.microsoft.com/b"}}}}});
        let (c, s, links, state) = add_modality_success(&ok).unwrap();
        assert_eq!((c.as_str(), s.as_str(), state), ("c1", "s1", None));
        assert!(links.update_state.is_some() && links.controller.is_some());
        let up = json!({"callAgentPath": "conversation/contentSharingUpdate/", "body": {"contentSharingCorrelationId": "c1", "sessionState": "{\"url\":\"u\"}", "sequenceNumber": 4}});
        assert_eq!(
            session_update(&up),
            Some(("c1".into(), "{\"url\":\"u\"}".into(), 4))
        );
        let end = json!({"callAgentPath": "conversation/contentSharingEnd/", "body": {"contentSharingCorrelationId": "c1"}});
        assert_eq!(session_end(&end), Some("c1".into()));
        assert_eq!(session_end(&up), None);
        let fail = json!({"callAgentPath": "conversation/addModalityFailure/", "body": {"modalityFailure": {"contentSharing": {"transactionEnd": {"code": 403, "subCode": 1, "phrase": "Forbidden"}}}}});
        assert_eq!(add_modality_failure(&fail), Some("Forbidden".into()));
    }

    #[test]
    fn roster_sessions() {
        let id = encode_identifier(&json!({"type": "whiteboard", "url": ""}));
        let p = json!({"endpoints": {"e1": {"contentSharing": {"sessionInformation": {
            "role": "presenter", "contentSharingCorrelationId": "c1", "contentSharingSessionId": "s1", "identifier": id,
            "contentSharingController": "https://api.flightproxy.teams.microsoft.com/j", "subject": "", "sessionState": "{\"url\":\"https://app.whiteboard.microsoft.com/me/x\"}"}}},
            "e2": {"contentSharing": {"sessionInformation": {"role": "viewer"}}}}});
        let infos = presenter_sessions(&p);
        assert_eq!(infos.len(), 1);
        let s = session_from_roster(&infos[0], "8:orgid:a", "A").unwrap();
        assert_eq!(s.kind(), "whiteboard");
        assert_eq!(s.correlation_id, "c1");
        assert!(s.join_link.is_some());
        assert_eq!(
            state_url(&s.state).as_deref(),
            Some("https://app.whiteboard.microsoft.com/me/x")
        );
    }

    #[test]
    fn whiteboard_urls_and_stage() {
        assert!(is_whiteboard_url(
            "https://app.whiteboard.microsoft.com/meeting?embed=1"
        ));
        assert!(is_whiteboard_url(
            "https://whiteboard.cloud.microsoft:443/x"
        ));
        assert!(!is_whiteboard_url(
            "https://app.whiteboard.microsoft.com.evil.example/x"
        ));
        assert!(!is_whiteboard_url("http://app.whiteboard.microsoft.com/"));
        assert_eq!(meeting_type(false, true, false, false, false), 1);
        assert_eq!(meeting_type(true, false, false, false, false), 0);
        assert_eq!(meeting_type(false, true, true, false, false), 3);
        assert_eq!(meeting_type(false, false, false, true, false), 4);
        assert_eq!(
            stage_url(
                "https://app.whiteboard.microsoft.com/meeting?embed=1",
                1,
                "t",
                false,
                5
            ),
            "https://app.whiteboard.microsoft.com/meeting?embed=1&meetingType=1&meetingTenantId=t&participantTimestamp=5"
        );
        assert_eq!(
            serde_json::from_str::<Value>(&board_state("u", None, Some("p"))).unwrap(),
            json!({"url": "u", "initiatorParticipantId": "p"})
        );
    }

    #[test]
    fn take_control_and_presenter_changes() {
        let from = json!({"id": "8:orgid:a", "participantId": "p"});
        assert_eq!(
            take_control_body(&from),
            json!({"participants": {"from": from}})
        );
        let ev = json!({"callAgentPath": "conversation/contentSharingUpdate/", "body": {"contentSharing": {
            "contentSharingCorrelationId": "c1", "presenter": {"id": "8:orgid:B", "participantId": "q"}, "sessionState": "{}"}}});
        assert_eq!(
            update_presenter(&ev),
            Some(("c1".into(), "8:orgid:b".into()))
        );
        assert_eq!(
            update_presenter(&json!({"body": {"contentSharingCorrelationId": "c"}})),
            None
        );
        let answer = json!({"identifier": "x", "presenter": {"id": "8:orgid:a"}, "subject": "", "sessionState": "{}"});
        assert_eq!(
            update_presenter(&answer).map(|p| p.1),
            Some("8:orgid:a".into())
        );
        let mut l = SessionLinks {
            controller: Some("c".into()),
            ..Default::default()
        };
        l.merge(SessionLinks {
            update_state: Some("u".into()),
            ..Default::default()
        });
        assert_eq!(
            (l.controller.as_deref(), l.update_state.as_deref()),
            (Some("c"), Some("u"))
        );
    }

    #[test]
    fn annotation_session_as_teams() {
        let board = "https://app.whiteboard.microsoft.com/meeting?embed=1&encodedShareLink=x&meetingTitle=M&annotation=true&initiatorId=o&initiatorTimestamp=1";
        let (share, url) = annotation_urls(
            board,
            SharedScreen {
                width: 1920,
                height: 1080,
                window: false,
            },
            "windowsNT 10.0",
            "g",
        );
        assert_eq!(
            share,
            format!(
                "{board}&sharedScreenWidth=1920&sharedScreenFullHeight=1080&isScreenSharerOnT2=true&sharingSourceType=1&osType=windowsNT 10.0"
            )
        );
        assert_eq!(
            url,
            format!(
                "{board}&sharedScreenWidth=1920&sharedScreenFullHeight=1080&isScreenSharerOnT2=true&sharingSourceType=1&osType=windowsNT+10.0&geometryId=g"
            )
        );
        let c = annotation_content("19:m", "0", &share, &url);
        assert_eq!(c["appId"], "annotation");
        assert_eq!(c["loaderLabel"], "annotation");
        assert_eq!(c["initialNoteContent"], json!([]));
        assert_eq!(c["url"], url);
        let (s2, _) = annotation_urls(
            "https://b/meeting?embed=1",
            SharedScreen {
                width: 800,
                height: 600,
                window: true,
            },
            "linux",
            "g",
        );
        assert!(s2.ends_with("?embed=1&annotation=true&sharedScreenWidth=800&sharedScreenFullHeight=600&isScreenSharerOnT2=true&sharingSourceType=2&osType=linux"));
    }

    #[test]
    fn excel_content_as_teams() {
        // The substrate id Teams sent for OST TEST 214 workbook.xlsx (2026-11-18).
        assert_eq!(
            substrate_id(
                "fa160c33-a34a-4705-87b6-1f62802d97df",
                "21b0d3cf-2b9e-45f6-a12e-fcf782c99233",
                "0e0a18f3-101b-4090-a53e-1e24c4d98efd",
                "01BV7C2BGPBMSL2ZCLX5GYAJ4JTMY7ICRO"
            ),
            "SPO_ZmExNjBjMzMtYTM0YS00NzA1LTg3YjYtMWY2MjgwMmQ5N2RmLDIxYjBkM2NmLTJiOWUtNDVmNi1hMTJlLWZjZjc4MmM5OTIzMywwZTBhMThmMy0xMDFiLTQwOTAtYTUzZS0xZTI0YzRkOThlZmQ_01BV7C2BGPBMSL2ZCLX5GYAJ4JTMY7ICRO"
        );
        let c = excel_content(
            "19:m@thread.v2",
            "0",
            "https://x/",
            "Excel",
            "f1",
            "SPO_a_b",
        );
        assert_eq!(c["appId"], EXCEL_APP_ID);
        assert_eq!(
            c["conversationId"],
            format!("19:m@thread.v2|{EXCEL_APP_ID}")
        );
        let ctx: Value = serde_json::from_str(c["extensibleAppContext"].as_str().unwrap()).unwrap();
        assert_eq!(
            ctx,
            json!({"permittedFileUsers": [], "appLoadState": "preLoadApp", "fileId": "f1"})
        );
        let st: Value = serde_json::from_str(&excel_state(&["a".into()], "f1")).unwrap();
        assert_eq!(st["extensibleAppContext"]["appLoadState"], "fullLoadApp");
        assert_eq!(st["url"], "");
    }

    #[test]
    fn live_inking_messages() {
        let me =
            json!({"displayName": "A", "endpointId": "e", "id": "8:orgid:a", "participantId": "p"});
        let b = live_inking_body(&me, "{\"eventType\":7}", "op");
        assert_eq!(b["messageContent"][0]["type"], "LiveInking");
        assert_eq!(
            b["messageContent"][0]["payload"]["EventData"],
            "{\"eventType\":7}"
        );
        assert_eq!(b["messageContent"][0]["scope"], "all");
        assert_eq!(b["from"]["participantId"], "p");
        let ev = json!({"callAgentPath": "conversation/receiveMessage/", "body": {"from": {"id": "8:orgid:B", "participantId": "q"},
            "messageContent": [{"type": "Reaction", "payload": {}}, {"type": "LiveInking", "payload": {"EventData": "{\"eventType\":6}"}}]}});
        assert_eq!(
            live_inking(&ev),
            vec![(
                "q".to_string(),
                "8:orgid:b".to_string(),
                "{\"eventType\":6}".to_string()
            )]
        );
        assert!(live_inking(&json!({"callAgentPath": "conversation/update/"})).is_empty());
    }
}
