//! Scheduled messages, as Teams' "Schedule message" sends them (measured on
//! winpc 2026-11-10, "OST TEST 90"): the message goes to the chat service's
//! drafts (`POST v1/users/ME/drafts`, a `ScheduledDraft` with its send
//! time), waits in your `48:drafts` stream until then, and is cancelled
//! with `DELETE v1/users/ME/drafts/{id}`.

use anyhow::{Context, Result};

use super::client::TeamsClient;
use super::messages::MessageView;
use super::outbox::Outgoing;

/// A message waiting to be sent.
#[derive(Debug, Clone, serde::Serialize)]
pub struct Scheduled {
    /// The draft's id (to cancel it).
    pub id: String,
    /// The chat or channel it goes to.
    pub conversation: String,
    /// When it goes (epoch ms).
    pub send_at_ms: i64,
    /// The message as it will show.
    pub message: MessageView,
}

/// Teams' POST body: the message as it would be sent, marked as a draft of
/// the `48:drafts` stream, inside the scheduling envelope.
pub fn schedule_body(o: &Outgoing, send_at_ms: i64) -> serde_json::Value {
    let iso = chrono::DateTime::from_timestamp_millis(send_at_ms)
        .map(|t| t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
        .unwrap_or_default();
    let mut message = super::outbox::post_body(o);
    message["properties"]["draftId"] = o.client_message_id.clone().into();
    message["draftDetails"] = serde_json::json!({ "sendAt": iso });
    message["threadtype"] = "streamofdrafts".into();
    message["innerThreadId"] = o.conversation_id.clone().into();
    if message.get("crossPostChannels").is_none() {
        message["crossPostChannels"] = serde_json::json!([]);
    }
    serde_json::json!({
        "draftDetails": { "sendAt": send_at_ms.to_string() },
        "draftType": "ScheduledDraft",
        "innerThreadId": o.conversation_id,
        "message": message,
    })
}

/// Schedule `o` to go at `send_at_ms`; the draft's id.
pub async fn schedule(client: &TeamsClient, o: &Outgoing, send_at_ms: i64) -> Result<String> {
    let url = format!("{}/v1/users/ME/drafts", client.chat_service_url());
    let resp = client.chat_post(&url, &schedule_body(o, send_at_ms)).await?;
    let from_location = resp
        .headers()
        .get("location")
        .and_then(|l| l.to_str().ok())
        .and_then(|l| l.trim_end_matches('/').rsplit('/').next())
        .map(str::to_string);
    let body: serde_json::Value = resp.json().await.unwrap_or_default();
    Ok(from_location
        .or_else(|| {
            body.pointer("/message/id")
                .or_else(|| body.get("id"))
                .map(|v| v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string()))
        })
        .unwrap_or_default())
}

/// Teams' PUT body for an edited scheduled message (measured, "OST TEST
/// 93"): the same envelope, the message carrying the draft's id (as its id
/// and draftId), the edit time and a new version.
pub fn edit_body(id: &str, o: &Outgoing, send_at_ms: i64, now_ms: i64) -> serde_json::Value {
    let mut b = schedule_body(o, send_at_ms);
    let m = &mut b["message"];
    m["id"] = id.into();
    m["properties"]["draftId"] = id.into();
    m["properties"]["edittime"] = now_ms.into();
    m["version"] = chrono::DateTime::from_timestamp_millis(now_ms)
        .map(|t| t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
        .unwrap_or_default()
        .into();
    b
}

/// Change a scheduled message (its text or its time).
pub async fn edit(client: &TeamsClient, id: &str, o: &Outgoing, send_at_ms: i64) -> Result<()> {
    anyhow::ensure!(!id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()), "Not a draft: {id}");
    let url = format!("{}/v1/users/ME/drafts/{id}", client.chat_service_url());
    let body = edit_body(id, o, send_at_ms, chrono::Utc::now().timestamp_millis());
    client.chat_request(reqwest::Method::PUT, &url, &body).await?;
    Ok(())
}

/// Cancel a scheduled message.
pub async fn cancel(client: &TeamsClient, id: &str) -> Result<()> {
    anyhow::ensure!(!id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()), "Not a draft: {id}");
    let url = format!("{}/v1/users/ME/drafts/{id}", client.chat_service_url());
    client.chat_request(reqwest::Method::DELETE, &url, &serde_json::Value::Null).await?;
    Ok(())
}

/// A field that the service may give as an object or as a JSON string.
fn object(v: Option<&serde_json::Value>) -> serde_json::Value {
    match v {
        Some(serde_json::Value::String(s)) => serde_json::from_str(s).unwrap_or_default(),
        Some(v) => v.clone(),
        None => serde_json::Value::Null,
    }
}

/// When a draft goes: `sendAt` as epoch ms (a number or its string) or an
/// ISO time.
fn send_at(details: &serde_json::Value) -> Option<i64> {
    let v = details.get("sendAt")?;
    v.as_i64().or_else(|| {
        let s = v.as_str()?;
        s.parse().ok().or_else(|| {
            chrono::DateTime::parse_from_rfc3339(s)
                .ok()
                .map(|t| t.timestamp_millis())
        })
    })
}

/// The scheduled messages in a drafts list (`{"drafts": [...]}`; each
/// draft carries draftType, innerThreadId and draftDetails itself).
pub fn scheduled_from(page: &serde_json::Value, me: &str, own_name: &str) -> Vec<Scheduled> {
    let mut out = Vec::new();
    for m in page["drafts"].as_array().into_iter().flatten() {
        let props = &m["properties"];
        // Deleted (cancelled or sent) drafts stay in the stream, emptied.
        if m["content"].as_str().unwrap_or_default().is_empty() || props.get("deletetime").is_some() {
            continue;
        }
        let kind = props
            .get("draftType")
            .or_else(|| m.get("draftType"))
            .and_then(|k| k.as_str())
            .unwrap_or("ScheduledDraft");
        if kind != "ScheduledDraft" {
            continue;
        }
        let conversation = props
            .get("innerThreadId")
            .or_else(|| m.get("innerThreadId"))
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .to_string();
        let details = {
            let d = object(props.get("draftDetails"));
            if d.is_null() { object(m.get("draftDetails")) } else { d }
        };
        let (Some(send_at_ms), false) = (send_at(&details), conversation.is_empty()) else {
            continue;
        };
        let Some(message) = super::messages::message_view(m, me, own_name) else {
            continue;
        };
        out.push(Scheduled {
            id: m["id"].as_str().unwrap_or_default().to_string(),
            conversation,
            send_at_ms,
            message,
        });
    }
    out.sort_by_key(|s| s.send_at_ms);
    out
}

/// Your scheduled messages (all chats): `GET v1/users/ME/drafts`.
pub async fn list(client: &TeamsClient, me: &str, own_name: &str) -> Result<Vec<Scheduled>> {
    // (The 48:drafts stream can't be read as a conversation; the drafts
    // list is its own resource.)
    let url = format!("{}/v1/users/ME/drafts?pageSize=200", client.chat_service_url());
    let resp = match client.chat_get(&url).await {
        Ok(r) => r,
        Err(e) if e.to_string().contains("HTTP 404") => return Ok(Vec::new()),
        Err(e) => return Err(e),
    };
    let page: serde_json::Value = resp.json().await.context("Drafts reply")?;
    Ok(scheduled_from(&page, me, own_name))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outgoing() -> Outgoing {
        Outgoing {
            conversation_id: "19:ef213c7c46cf4036b11608300e96fee4@thread.v2".into(),
            client_message_id: "1604876585425334945".into(),
            content: "<p>OST TEST 90 scheduled</p>".into(),
            display_name: "OST Test 1".into(),
            sender_mri: "8:orgid:4287e791-1b98-4963-8b94-281c50472683".into(),
            compose_time: "2026-11-10T14:35:03.399Z".into(),
            arrival_ms: 1_794_321_303_399,
            created_ms: 0,
            state: super::super::outbox::SendState::Sending,
            pipeline_status: None,
            failures: 0,
            queued: false,
            server_id: None,
            quote: None,
            importance: String::new(),
            mentions: String::new(),
            subject: String::new(),
            title: String::new(),
            banner_theme: None,
            banner_image: None,
            shared_in_main: false,
            threads_layout: false,
        }
    }

    #[test]
    fn the_body_is_teams_scheduled_draft() {
        // As Teams sent "OST TEST 90" for 8:00 AM Pacific (16:00 UTC).
        let b = schedule_body(&outgoing(), 1_794_326_400_000);
        assert_eq!(b["draftType"], "ScheduledDraft");
        assert_eq!(b["draftDetails"]["sendAt"], "1794326400000");
        assert_eq!(b["innerThreadId"], "19:ef213c7c46cf4036b11608300e96fee4@thread.v2");
        let m = &b["message"];
        assert_eq!(m["threadtype"], "streamofdrafts");
        assert_eq!(m["innerThreadId"], b["innerThreadId"]);
        assert_eq!(m["draftDetails"]["sendAt"], "2026-11-10T16:00:00.000Z");
        assert_eq!(m["properties"]["draftId"], "1604876585425334945");
        assert_eq!(m["clientmessageid"], "1604876585425334945");
        assert_eq!(m["content"], "<p>OST TEST 90 scheduled</p>");
        assert_eq!(m["crossPostChannels"], serde_json::json!([]));
    }

    #[test]
    fn an_edit_is_teams_put() {
        let b = edit_body("1794323757462", &outgoing(), 1_794_326_400_000, 1_794_323_778_362);
        assert_eq!(b["draftType"], "ScheduledDraft");
        assert_eq!(b["message"]["id"], "1794323757462");
        assert_eq!(b["message"]["properties"]["draftId"], "1794323757462");
        assert_eq!(b["message"]["properties"]["edittime"], 1_794_323_778_362_i64);
        assert_eq!(b["message"]["version"], "2026-11-10T15:16:18.362Z");
        assert_eq!(b["message"]["draftDetails"]["sendAt"], "2026-11-10T16:00:00.000Z");
    }

    #[test]
    fn scheduled_messages_come_from_the_drafts_stream() {
        // As the service listed "OST TEST 91" (scheduled from OST).
        let page = serde_json::json!({"drafts": [
            {"sequenceId": 2, "conversationid": "48:drafts", "draftType": "ScheduledDraft",
             "innerThreadId": "19:c@thread.v2", "draftDetails": {"sendAt": "1794326400000", "shouldCloneAmsReferences": true},
             "id": "1794321304556", "clientmessageid": "1327593053201991005", "messagetype": "RichText/Html",
             "content": "<p>OST TEST 90 scheduled</p>", "from": "https://x/contacts/8:orgid:me", "imdisplayname": "OST Test 1",
             "composetime": "2026-11-10T14:50:52.3010000Z", "originalarrivaltime": "2026-11-10T14:50:52.3010000Z",
             "properties": {"mentions": "[]", "cards": "[]", "draftId": "1327593053201991005"}},
            {"id": "1794321300000", "messagetype": "RichText/Html", "content": "",
             "from": "https://x/contacts/8:orgid:me", "properties": {"deletetime": "1794321399999"}},
        ]});
        let s = scheduled_from(&page, "8:orgid:me", "OST Test 1");
        assert_eq!(s.len(), 1, "cancelled drafts are left out");
        assert_eq!(s[0].id, "1794321304556");
        assert_eq!(s[0].conversation, "19:c@thread.v2");
        assert_eq!(s[0].send_at_ms, 1_794_326_400_000);
        assert_eq!(s[0].message.text, "OST TEST 90 scheduled");
    }
}
