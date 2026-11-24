//! Quick views ▸ Followed threads and Saved, as Teams fills them: from your
//! `48:threads` and `48:saved` system conversations (checked on winpc,
//! 2026-11-09). Each holds activity records naming the source chat or
//! channel message; the newest record per thread (or per message) wins,
//! and a saved message counts until an "unSaved" record follows it.

use anyhow::Result;

use super::client::TeamsClient;

/// A row of Followed threads or Saved.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct QuickItem {
    /// The chat or channel.
    pub thread_id: String,
    /// The message (Saved) or the thread's newest reply (Followed threads).
    pub message_id: String,
    /// The thread's root post.
    pub reply_chain: String,
    /// The chat's topic, or the team's name for a channel.
    pub topic: String,
    pub channel: bool,
    pub sender: String,
    pub sender_mri: String,
    pub preview: String,
    /// Followed threads: the root post's preview and the reply count.
    pub parent_preview: String,
    /// Followed threads: the root post's subject (Teams' row shows it in
    /// place of the preview when it has one).
    pub parent_subject: String,
    /// Followed threads: the glyph before the root post's line, as Teams'
    /// thread slice (`getMessageType`): "deleted" (a deleted post) or
    /// "meeting" (a channel meeting's post); empty otherwise.
    pub parent_icon: String,
    pub replies: u64,
    pub time: String,
    pub unread: bool,
}

fn items_from(v: &serde_json::Value, saved: bool) -> Vec<QuickItem> {
    let mut seen = std::collections::HashSet::new();
    let mut msgs: Vec<&serde_json::Value> = v["messages"].as_array().into_iter().flatten().collect();
    msgs.sort_by(|a, b| b["originalarrivaltime"].as_str().cmp(&a["originalarrivaltime"].as_str()));
    let mut out = Vec::new();
    for m in msgs {
        let a = &m["properties"]["activity"];
        let s = |k: &str| a[k].as_str().unwrap_or_default().to_string();
        let n = |k: &str| a[k].as_i64().map(|x| x.to_string()).or_else(|| a[k].as_str().map(str::to_string)).unwrap_or_default();
        let thread = s("sourceThreadId");
        let key = if saved { format!("{thread}|{}", n("sourceMessageId")) } else { format!("{thread}|{}", n("sourceReplyChainId")) };
        if thread.is_empty() || !seen.insert(key) {
            continue;
        }
        // A deleted thread's newest record (activityReason "deleted", with
        // deleteActivityTimestamp and no preview): Teams drops the thread.
        if !saved && (s("activityReason") == "deleted" || !a["deleteActivityTimestamp"].is_null()) {
            continue;
        }
        if saved && s("activitySubtype") != "saved" {
            continue;
        }
        let ctx = &a["activityContext"];
        let c = |k: &str| ctx[k].as_str().unwrap_or_default().to_string();
        // A record for the root post itself carries no parent: Teams uses
        // the message's own preview, with no subject or glyph.
        let root = !saved && n("sourceMessageId") == n("sourceReplyChainId");
        let parent_icon = if root {
            String::new()
        } else if c("parentMessagePreviewTemplateOption").eq_ignore_ascii_case("deleted") {
            "deleted".to_string()
        } else if c("parentMessageType").eq_ignore_ascii_case("meeting") {
            "meeting".to_string()
        } else {
            String::new()
        };
        out.push(QuickItem {
            channel: thread.ends_with("@thread.tacv2") || s("sourceThreadType") == "space",
            thread_id: thread,
            message_id: n("sourceMessageId"),
            reply_chain: n("sourceReplyChainId"),
            topic: s("sourceThreadTopic"),
            sender: s("sourceUserImDisplayName"),
            sender_mri: s("sourceUserId"),
            preview: s("messagePreview"),
            parent_preview: if root { s("messagePreview") } else { c("parentMessagePreview") },
            parent_subject: if root { String::new() } else { c("parentMessageSubject") },
            parent_icon,
            replies: ctx["repliesCount"].as_str().and_then(|r| r.parse().ok()).or_else(|| ctx["repliesCount"].as_u64()).unwrap_or(0),
            time: m["originalarrivaltime"].as_str().unwrap_or_default().to_string(),
            unread: m["properties"]["isread"].as_bool() == Some(false) || m["properties"]["isread"].as_str() == Some("false"),
        });
    }
    out
}

pub fn saved_from(v: &serde_json::Value) -> Vec<QuickItem> {
    items_from(v, true)
}

pub fn followed_from(v: &serde_json::Value) -> Vec<QuickItem> {
    items_from(v, false)
}

async fn read(client: &TeamsClient, conv: &str) -> Result<serde_json::Value> {
    let url = format!("{}/v1/users/ME/conversations/{conv}/messages?view=msnp24Equivalent&pageSize=100", client.chat_service_url());
    Ok(client.chat_get(&url).await?.json().await?)
}

/// Saved messages, newest first.
pub async fn saved(client: &TeamsClient) -> Result<Vec<QuickItem>> {
    Ok(saved_from(&read(client, "48:saved").await?))
}

/// Threads you follow, by newest activity.
pub async fn followed(client: &TeamsClient) -> Result<Vec<QuickItem>> {
    Ok(followed_from(&read(client, "48:threads").await?))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(time: &str, sub: &str, thread: &str, msg: i64, chain: i64, preview: &str) -> serde_json::Value {
        serde_json::json!({"originalarrivaltime": time, "properties": {"isread": true, "activity": {
            "activitySubtype": sub, "sourceThreadId": thread, "sourceMessageId": msg, "sourceReplyChainId": chain,
            "sourceUserImDisplayName": "Randy Northrup", "sourceUserId": "8:orgid:x", "messagePreview": preview,
            "sourceThreadTopic": "OST group test", "sourceThreadType": "chat",
            "activityContext": {"repliesCount": "3", "parentMessagePreview": "root"}}}})
    }

    #[test]
    fn saved_keeps_the_newest_record_per_message() {
        // OST group test as Teams had it: one message unsaved, one saved.
        let v = serde_json::json!({"messages": [
            rec("2026-11-07T09:04:58Z", "unSaved", "19:a@thread.v2", 1794039440533, 1794039440533, ""),
            rec("2026-11-07T09:14:55Z", "saved", "19:a@thread.v2", 1794032815852, 1794032815852, "OST test 43: typing clears on send"),
            rec("2026-11-07T09:00:00Z", "saved", "19:a@thread.v2", 1794039440533, 1794039440533, "was saved"),
        ]});
        let s = saved_from(&v);
        assert_eq!(s.len(), 1);
        assert_eq!((s[0].preview.as_str(), s[0].message_id.as_str(), s[0].channel), ("OST test 43: typing clears on send", "1794032815852", false));
    }

    #[test]
    fn followed_has_one_row_per_thread() {
        let v = serde_json::json!({"messages": [
            rec("2026-11-05T18:58:54Z", "reply", "19:c@thread.tacv2", 1794244337587, 1793889784763, "71"),
            rec("2026-11-09T17:47:10Z", "reply", "19:c@thread.tacv2", 1794246428605, 1794245518435, "72"),
            rec("2026-11-04T10:00:00Z", "reply", "19:c@thread.tacv2", 1, 1793889784763, "older"),
        ]});
        let f = followed_from(&v);
        assert_eq!(f.iter().map(|i| i.preview.as_str()).collect::<Vec<_>>(), vec!["72", "71"]);
        assert!(f[0].channel);
        assert_eq!((f[0].replies, f[0].parent_preview.as_str()), (3, "root"));
    }

    #[test]
    fn followed_marks_meeting_and_deleted_roots() {
        let mut meeting = rec("2026-11-24T18:00:00Z", "reply", "19:c@thread.tacv2", 2, 1, "reply");
        let ctx = &mut meeting["properties"]["activity"]["activityContext"];
        ctx["parentMessageType"] = "Meeting".into();
        ctx["parentMessageSubject"] = "OST TEST 272 channel meeting".into();
        let mut deleted = rec("2026-11-24T17:00:00Z", "reply", "19:c@thread.tacv2", 4, 3, "reply");
        deleted["properties"]["activity"]["activityContext"]["parentMessagePreviewTemplateOption"] = "deleted".into();
        let root = rec("2026-11-24T16:00:00Z", "reply", "19:c@thread.tacv2", 5, 5, "the post");
        let f = followed_from(&serde_json::json!({"messages": [meeting, deleted, root]}));
        let got: Vec<_> = f.iter().map(|i| (i.parent_icon.as_str(), i.parent_subject.as_str(), i.parent_preview.as_str())).collect();
        assert_eq!(got, vec![("meeting", "OST TEST 272 channel meeting", "root"), ("deleted", "", "root"), ("", "", "the post")]);
    }

    #[test]
    fn followed_drops_deleted_threads() {
        // As 48:threads had "OST TEST 272 channel meeting" once its post was
        // deleted: a "deleted" record newer than the thread's reply.
        let reply = rec("2026-11-24T10:04:00Z", "reply", "19:c@thread.tacv2", 2, 1, "reply");
        let deleted = serde_json::json!({"originalarrivaltime": "2026-11-24T10:04:47.573Z", "properties": {"isread": true, "activity": {
            "activityReason": "deleted", "activityType": "threads", "deleteActivityTimestamp": 1795518032624_i64,
            "sourceMessageId": 1, "sourceReplyChainId": 1, "sourceThreadId": "19:c@thread.tacv2", "sourceThreadType": "topic",
            "activityContext": {"parentMessagePreviewTemplateOption": "deleted", "repliesCount": "0"}}}});
        let other = rec("2026-11-17T12:41:16Z", "reply", "19:c@thread.tacv2", 4, 3, "kept");
        let f = followed_from(&serde_json::json!({"messages": [reply, deleted, other]}));
        assert_eq!(f.iter().map(|i| i.preview.as_str()).collect::<Vec<_>>(), vec!["kept"]);
    }
}
