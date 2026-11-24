//! Drafts roamed between devices, as Teams does it (read from Teams
//! desktop 26288's code and checked against the chat service on
//! 2026-11-16; docs/spec/messages-and-composer.md §18).
//!
//! Teams keeps every unsent draft on the device first: a message in its
//! local `48:drafts` stream, in reply chain `-4.{chat}` (`-4.{root}` for a
//! channel reply), with the message's HTML as it would be sent and its
//! properties (mentions, cards, files, links). Only when the setting
//! `messaging.enableRoamMessageDraft` is on (off in every cloud's built-in
//! config, so only Microsoft's ECS rollout turns it on) does Teams also
//! roam it to the chat service's drafts resource, the one scheduled
//! messages use:
//! - a new draft is `POST v1/users/ME/drafts` with
//!   `{draftType: "RegularDraft", innerThreadId, message}`; the reply's
//!   Location names the draft's id;
//! - a changed one is `PUT v1/users/ME/drafts/{id}` (the message carries
//!   the id);
//! - sending or clearing it is `DELETE v1/users/ME/drafts/{id}`;
//! - other devices read it from `GET v1/users/ME/drafts` (and its delta
//!   sync), where a `RegularDraft` without a send time lands in the same
//!   `-4.{chat}` reply chain. When this device already has a different
//!   draft there, its own stays and the other shows as a conflict
//!   ("There's a draft saved from another platform").

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// Whether drafts roam (Teams' `messaging.enableRoamMessageDraft`).
/// `OST_ROAM_DRAFTS=1` (or `0`) overrides it, for testing.
pub fn roaming_enabled() -> bool {
    match std::env::var("OST_ROAM_DRAFTS").ok().as_deref() {
        Some("1") | Some("true") => return true,
        Some("0") | Some("false") => return false,
        _ => {}
    }
    super::ecs::setting("messaging", "enableRoamMessageDraft")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// A draft as it roams: what the chat service keeps for it.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Roamed {
    /// The service's id (for PUT and DELETE).
    pub id: String,
    /// The chat (or channel) it belongs to.
    pub chat: String,
    /// The channel post it replies to, if any.
    pub reply_to: String,
    pub client_message_id: String,
    /// Its HTML, as it would be sent.
    pub content: String,
    /// Its `properties.mentions` (Teams' JSON string).
    pub mentions: String,
    /// When it was last saved (epoch ms; the service's version).
    pub time_ms: i64,
    /// Deleted (sent or cleared) on some device.
    pub deleted: bool,
}

/// What a draft needs to roam.
#[derive(Debug, Clone, Default)]
pub struct Outgoing<'a> {
    pub chat: &'a str,
    /// The channel post a reply draft belongs to ("" for none).
    pub reply_to: &'a str,
    pub client_message_id: &'a str,
    pub content: &'a str,
    /// Teams' mentions JSON ("" for none).
    pub mentions: &'a str,
    pub display_name: &'a str,
    pub now_ms: i64,
    /// Set when it replaces a draft the service has (PUT).
    pub id: Option<&'a str>,
}

/// `chat` or `chat;messageid=root`, as Teams names a draft's thread.
fn inner_thread(chat: &str, reply_to: &str) -> String {
    if reply_to.is_empty() { chat.to_string() } else { format!("{chat};messageid={reply_to}") }
}

/// Teams' body for a roamed draft: the message as it would be sent, put in
/// the `48:drafts` stream, inside the `RegularDraft` envelope (no send
/// time, unlike a scheduled message). The client draft properties are the
/// ones Teams keeps with a local draft (captured from its IndexedDB).
pub fn roam_body(o: &Outgoing) -> serde_json::Value {
    let inner = inner_thread(o.chat, o.reply_to);
    let client_draft_id = format!("draft.{}.-4.{}", o.chat, if o.reply_to.is_empty() { o.chat } else { o.reply_to });
    let mut message = serde_json::json!({
        "clientmessageid": o.client_message_id,
        "content": o.content,
        "messagetype": "RichText/Html",
        "contenttype": "text",
        "imdisplayname": o.display_name,
        "properties": {
            "importance": "",
            "subject": "",
            "title": "",
            "cards": "[]",
            "links": "[]",
            "mentions": if o.mentions.is_empty() { "[]" } else { o.mentions },
            "files": "[]",
            "formatVariant": "TEAMS",
            "timestamp": o.now_ms.to_string(),
        },
        "threadtype": "streamofdrafts",
        "conversationid": "48:drafts",
        "innerThreadId": inner,
        "draftType": "RegularDraft",
        "draftDetails": { "clientDraftProperties": {
            "clientDraftId": client_draft_id,
            "isLoading": false,
            "lastEditTimestamp": o.now_ms,
            "versioningTimestamp": o.now_ms.to_string(),
            "composeCopilotData": "{}",
            "isExpanded": false,
            "offlineAssets": "[]",
            "urlPreview": "null",
            "fluidProperties": "null",
            "fluidUrlPermissionInfo": "null",
            "forwardAppIdsToInstall": "[]",
            "forwardMessageCardContents": "null",
            "forwardMessageIds": "[]",
            "forwardMessageRecipients": "[]",
            "forwardPrivateReply": false,
            "isForwardedMessage": false,
            "scheduledSendTime": null,
            "sendPostAsEmail": false,
            "shareToL1": false,
            "suggestedActions": "null",
            "crossPostChannels": "[]",
            "crossPostChannelsIncludesPrivateOrSharedChannel": false,
        } },
    });
    if let Some(id) = o.id {
        // As Teams' edit of a draft (a scheduled one, captured with OST
        // TEST 93): the id, the edit time and a new ISO version, without
        // which the service keeps the old text.
        message["id"] = id.into();
        message["properties"]["draftId"] = id.into();
        message["properties"]["edittime"] = o.now_ms.into();
        message["version"] = chrono::DateTime::from_timestamp_millis(o.now_ms)
            .map(|t| t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
            .unwrap_or_default()
            .into();
    }
    serde_json::json!({
        "draftType": "RegularDraft",
        "innerThreadId": inner,
        "message": message,
    })
}

fn epoch_ms(v: Option<&serde_json::Value>) -> Option<i64> {
    let v = v?;
    v.as_i64().or_else(|| v.as_str().and_then(|s| s.parse().ok()))
}

/// The roamed drafts in a drafts list (`{"drafts": [...]}`), deleted ones
/// included (as `deleted`), scheduled messages left out.
pub fn roamed_from(page: &serde_json::Value) -> Vec<Roamed> {
    let mut out = Vec::new();
    for m in page["drafts"].as_array().into_iter().flatten() {
        let props = &m["properties"];
        let kind = m.get("draftType").or_else(|| props.get("draftType")).and_then(|k| k.as_str()).unwrap_or("");
        // A send time makes it a scheduled message (Teams' isDraft).
        let scheduled = m.pointer("/draftDetails/sendAt").is_some_and(|v| !v.is_null());
        if kind != "RegularDraft" || scheduled {
            continue;
        }
        let inner = m["innerThreadId"].as_str().unwrap_or_default();
        let (chat, reply_to) = match inner.split_once(";messageid=") {
            Some((c, r)) => (c.to_string(), r.to_string()),
            None => (inner.to_string(), String::new()),
        };
        if chat.is_empty() {
            continue;
        }
        let content = m["content"].as_str().unwrap_or_default().to_string();
        out.push(Roamed {
            id: m["id"].as_str().map(str::to_string).unwrap_or_else(|| m["id"].to_string()),
            chat,
            reply_to,
            client_message_id: m["clientmessageid"].as_str().unwrap_or_default().to_string(),
            deleted: content.is_empty() || props.get("deletetime").is_some(),
            content,
            mentions: props["mentions"].as_str().unwrap_or("[]").to_string(),
            time_ms: epoch_ms(m.get("version"))
                .or_else(|| epoch_ms(props.get("edittime")))
                .unwrap_or_default(),
        });
    }
    out
}

/// The drafts list (scheduled messages and roamed drafts):
/// `GET v1/users/ME/drafts`.
pub async fn page(client: &TeamsClient) -> Result<serde_json::Value> {
    let url = format!("{}/v1/users/ME/drafts?pageSize=200", client.chat_service_url());
    let resp = match client.chat_get(&url).await {
        Ok(r) => r,
        Err(e) if e.to_string().contains("HTTP 404") => return Ok(serde_json::json!({ "drafts": [] })),
        Err(e) => return Err(e),
    };
    resp.json().await.context("Drafts reply")
}

/// Roam a new draft; the service's id for it.
pub async fn create(client: &TeamsClient, o: &Outgoing<'_>) -> Result<String> {
    let url = format!("{}/v1/users/ME/drafts", client.chat_service_url());
    let resp = client.chat_post(&url, &roam_body(o)).await?;
    let id = resp
        .headers()
        .get("location")
        .and_then(|l| l.to_str().ok())
        .and_then(|l| l.trim_end_matches('/').rsplit('/').next())
        .map(str::to_string)
        .filter(|id| !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()));
    id.context("The drafts service gave no id")
}

/// Replace a roamed draft with its new text.
pub async fn update(client: &TeamsClient, o: &Outgoing<'_>) -> Result<()> {
    let id = o.id.unwrap_or_default();
    anyhow::ensure!(!id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()), "Not a draft: {id}");
    let url = format!("{}/v1/users/ME/drafts/{id}", client.chat_service_url());
    client.chat_request(reqwest::Method::PUT, &url, &roam_body(o)).await?;
    Ok(())
}

/// Remove a roamed draft (sent or cleared).
pub async fn delete(client: &TeamsClient, id: &str) -> Result<()> {
    anyhow::ensure!(!id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()), "Not a draft: {id}");
    let url = format!("{}/v1/users/ME/drafts/{id}", client.chat_service_url());
    match client.chat_request(reqwest::Method::DELETE, &url, &serde_json::Value::Null).await {
        Err(e) if e.to_string().contains("HTTP 404") => Ok(()),
        r => r.map(|_| ()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CHAT: &str = "19:4287e791-1b98-4963-8b94-281c50472683_9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5@unq.gbl.spaces";

    fn outgoing() -> Outgoing<'static> {
        Outgoing {
            chat: CHAT,
            reply_to: "",
            client_message_id: "3484786220620915912",
            content: "<p>OST draft probe B</p>",
            mentions: "",
            display_name: "OST Test 1",
            now_ms: 1_794_831_861_119,
            id: None,
        }
    }

    #[test]
    fn a_new_draft_is_teams_regular_draft() {
        let b = roam_body(&outgoing());
        assert_eq!(b["draftType"], "RegularDraft");
        assert_eq!(b["innerThreadId"], CHAT);
        assert!(b.get("draftDetails").is_none(), "no send time: not a scheduled message");
        let m = &b["message"];
        assert_eq!(m["conversationid"], "48:drafts");
        assert_eq!(m["threadtype"], "streamofdrafts");
        assert_eq!(m["draftType"], "RegularDraft");
        assert_eq!(m["innerThreadId"], CHAT);
        assert_eq!(m["content"], "<p>OST draft probe B</p>");
        assert_eq!(m["properties"]["mentions"], "[]");
        assert_eq!(m["draftDetails"]["clientDraftProperties"]["clientDraftId"], format!("draft.{CHAT}.-4.{CHAT}"));
        assert!(m.get("id").is_none());
    }

    #[test]
    fn a_changed_draft_carries_its_id_and_a_reply_its_thread() {
        let o = Outgoing { id: Some("1794831861119"), reply_to: "1794000000000", ..outgoing() };
        let b = roam_body(&o);
        assert_eq!(b["message"]["id"], "1794831861119");
        assert_eq!(b["message"]["properties"]["draftId"], "1794831861119");
        assert_eq!(b["innerThreadId"], format!("{CHAT};messageid=1794000000000"));
    }

    #[test]
    fn roamed_drafts_come_from_the_drafts_list() {
        // As the service listed the draft OST roamed ("OST draft probe B")
        // next to a cancelled scheduled message.
        let page = serde_json::json!({"drafts": [
            {"clientmessageid": "3484786220620915912", "content": "<p>OST draft probe B</p>",
             "conversationid": "48:drafts", "draftType": "RegularDraft", "id": "1794831861119",
             "innerThreadId": CHAT, "messagetype": "RichText/Html",
             "properties": {"cards": "[]", "files": "[]", "links": "[]", "mentions": "[]"},
             "version": "1794831861119"},
            {"content": "", "draftType": "ScheduledDraft", "draftDetails": {"sendAt": "1794414600000"},
             "id": "1794324386456", "innerThreadId": "19:ef@thread.v2", "properties": {"deletetime": 1794324425826_i64}},
            {"content": "", "draftType": "RegularDraft", "id": "1794831900000",
             "innerThreadId": "19:c@thread.tacv2;messageid=1794", "properties": {"deletetime": 1794831999999_i64},
             "version": "1794831999999"},
        ]});
        let r = roamed_from(&page);
        assert_eq!(r.len(), 2, "scheduled messages are left out");
        assert_eq!(r[0].id, "1794831861119");
        assert_eq!(r[0].chat, CHAT);
        assert_eq!(r[0].content, "<p>OST draft probe B</p>");
        assert_eq!(r[0].time_ms, 1_794_831_861_119);
        assert!(!r[0].deleted);
        assert_eq!((r[1].chat.as_str(), r[1].reply_to.as_str(), r[1].deleted), ("19:c@thread.tacv2", "1794", true));
    }
}
