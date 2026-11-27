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
    let mut msgs: Vec<&serde_json::Value> =
        v["messages"].as_array().into_iter().flatten().collect();
    msgs.sort_by(|a, b| {
        b["originalarrivaltime"]
            .as_str()
            .cmp(&a["originalarrivaltime"].as_str())
    });
    let mut out = Vec::new();
    for m in msgs {
        let a = &m["properties"]["activity"];
        let s = |k: &str| a[k].as_str().unwrap_or_default().to_string();
        let n = |k: &str| {
            a[k].as_i64()
                .map(|x| x.to_string())
                .or_else(|| a[k].as_str().map(str::to_string))
                .unwrap_or_default()
        };
        let thread = s("sourceThreadId");
        let key = if saved {
            format!("{thread}|{}", n("sourceMessageId"))
        } else {
            format!("{thread}|{}", n("sourceReplyChainId"))
        };
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
            parent_preview: if root {
                s("messagePreview")
            } else {
                c("parentMessagePreview")
            },
            parent_subject: if root {
                String::new()
            } else {
                c("parentMessageSubject")
            },
            parent_icon,
            replies: ctx["repliesCount"]
                .as_str()
                .and_then(|r| r.parse().ok())
                .or_else(|| ctx["repliesCount"].as_u64())
                .unwrap_or(0),
            time: m["originalarrivaltime"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
            unread: m["properties"]["isread"].as_bool() == Some(false)
                || m["properties"]["isread"].as_str() == Some("false"),
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

/// A row of Chat ▸ Reminders (Teams' RemindersSliceManager over your
/// `48:reminders` stream): the message the reminder is on, its due time
/// and, once done, when it was completed.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct ReminderItem {
    #[serde(flatten)]
    pub item: QuickItem,
    /// The stream message (the slice item's id).
    pub stream_id: String,
    /// Due time, ms since the epoch.
    pub due: i64,
    /// Completed at (ms; 0 while open).
    pub completed: i64,
    /// Due: the service marked it (`isdue`) or its time has come.
    pub is_due: bool,
    /// Its due record asks for a banner (activityContext.displayBanner).
    pub banner: bool,
}

/// Your reminders from `48:reminders` (Teams' nF.isMessageValid and
/// cF.toMetadata): `duedate` must be a number; `isReminderDeleted` (true
/// or "true") drops the item; `completeddate` ends it. The service posts a
/// record per change (newReminder, editReminder, then reminderDue, which
/// carries no preview or sender name; seen for OST Test 3, 2026-11-27):
/// one item per source message, the newest record's state, with what it
/// leaves out taken from the older ones. Completed items older than
/// 7 days are gone (remindersMaxCompletedRetentionInDays). Open items
/// come first, soonest due at the top, then completed ones, the latest
/// first.
pub fn reminders_from(v: &serde_json::Value, now_ms: i64) -> Vec<ReminderItem> {
    const WEEK_MS: i64 = 7 * 24 * 3600 * 1000;
    let mut msgs: Vec<&serde_json::Value> =
        v["messages"].as_array().into_iter().flatten().collect();
    msgs.sort_by(|a, b| {
        b["originalarrivaltime"]
            .as_str()
            .cmp(&a["originalarrivaltime"].as_str())
    });
    let num = |x: &serde_json::Value| {
        x.as_i64()
            .or_else(|| x.as_f64().map(|f| f as i64))
            .or_else(|| x.as_str().and_then(|s| s.parse().ok()))
    };
    let truthy = |x: &serde_json::Value| x.as_bool() == Some(true) || x.as_str() == Some("true");
    // Each source message's item in `out` (None: its newest record
    // dropped it).
    let mut seen: std::collections::HashMap<String, Option<usize>> = Default::default();
    let mut out: Vec<ReminderItem> = Vec::new();
    for m in msgs {
        let p = &m["properties"];
        let a = if p["activity"].is_string() {
            serde_json::from_str(p["activity"].as_str().unwrap_or_default()).unwrap_or_default()
        } else {
            p["activity"].clone()
        };
        let text = |k: &str| {
            a[k].as_str()
                .map(str::to_string)
                .or_else(|| a[k].as_i64().map(|n| n.to_string()))
                .unwrap_or_default()
        };
        let thread = text("sourceThreadId");
        if thread.is_empty() {
            continue;
        }
        let key = format!("{thread}|{}", text("sourceMessageId"));
        if let Some(at) = seen.get(&key) {
            // An older record: only what the newer one left out.
            if let Some(r) = at.and_then(|i| out.get_mut(i)) {
                let fill = |f: &mut String, v: String| {
                    if f.is_empty() {
                        *f = v;
                    }
                };
                fill(&mut r.item.sender, text("sourceUserImDisplayName"));
                fill(&mut r.item.sender_mri, text("sourceUserId"));
                fill(&mut r.item.preview, text("messagePreview"));
                fill(&mut r.item.topic, text("sourceThreadTopic"));
            }
            continue;
        }
        let completed = num(&p["completeddate"]).unwrap_or(0).max(0);
        let due = num(&p["duedate"]).filter(|d| *d > 0);
        // Removed: the service rewrites the newest record as a deletion
        // (activityReason "deleted", activitySubtype deleteReminder, with
        // deleteActivityTimestamp; seen 2026-11-27); Teams' own soft
        // delete is isReminderDeleted.
        let removed = text("activityReason") == "deleted"
            || text("activitySubtype") == "deleteReminder"
            || !a["deleteActivityTimestamp"].is_null();
        if truthy(&p["isReminderDeleted"])
            || removed
            || due.is_none()
            || (completed > 0 && now_ms - completed > WEEK_MS)
        {
            seen.insert(key, None);
            continue;
        }
        let due = due.unwrap_or_default();
        seen.insert(key, Some(out.len()));
        let item = QuickItem {
            channel: thread.ends_with("@thread.tacv2") || text("sourceThreadType") == "space",
            thread_id: thread,
            message_id: text("sourceMessageId"),
            reply_chain: text("sourceReplyChainId"),
            topic: text("sourceThreadTopic"),
            sender: text("sourceUserImDisplayName"),
            sender_mri: text("sourceUserId"),
            preview: text("messagePreview"),
            time: m["originalarrivaltime"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
            unread: !truthy(&p["isRead"]) && p["isRead"].as_bool() == Some(false),
            ..Default::default()
        };
        out.push(ReminderItem {
            item,
            stream_id: m["id"].as_str().unwrap_or_default().to_string(),
            due,
            completed,
            is_due: completed == 0 && (truthy(&p["isdue"]) || due <= now_ms),
            banner: a["activityContext"]["displayBanner"].as_str() != Some("false"),
        });
    }
    out.sort_by(|a, b| match (a.completed > 0, b.completed > 0) {
        (false, false) => a.due.cmp(&b.due),
        (true, true) => b.completed.cmp(&a.completed),
        (a_done, _) => a_done.cmp(&!a_done),
    });
    out
}

/// Your reminders (Chat ▸ Reminders), and whether that was the whole
/// stream. Each set, edit and due event is a record, so the stream is read
/// page by page (its `_metadata.backwardLink`), up to 10 pages: room for
/// Teams' 200 open reminders and their changes.
pub async fn reminders(client: &TeamsClient, now_ms: i64) -> Result<(Vec<ReminderItem>, bool)> {
    let mut v = read(client, "48:reminders").await?;
    let mut all: Vec<serde_json::Value> = v["messages"].as_array().cloned().unwrap_or_default();
    let mut whole = false;
    for _ in 0..10 {
        let back = v
            .pointer("/_metadata/backwardLink")
            .and_then(|l| l.as_str())
            .unwrap_or_default()
            .to_string();
        let page = v["messages"].as_array().map_or(0, |m| m.len());
        if back.is_empty() || page < 100 {
            whole = true;
            break;
        }
        let url = if back.contains("pageSize=") {
            back
        } else {
            format!("{back}&pageSize=100")
        };
        v = client.chat_get(&url).await?.json().await?;
        all.extend(v["messages"].as_array().cloned().unwrap_or_default());
    }
    Ok((
        reminders_from(&serde_json::json!({ "messages": all }), now_ms),
        whole,
    ))
}

async fn read(client: &TeamsClient, conv: &str) -> Result<serde_json::Value> {
    let url = format!(
        "{}/v1/users/ME/conversations/{conv}/messages?view=msnp24Equivalent&pageSize=100",
        client.chat_service_url()
    );
    match client.chat_get(&url).await {
        Ok(r) => Ok(r.json().await?),
        // Someone who has never saved (or followed) anything has no such
        // stream yet: the chat service answers 404, and the list is empty.
        Err(e) if is_missing(&e) => Ok(serde_json::json!({ "messages": [] })),
        Err(e) => Err(e),
    }
}

fn is_missing(e: &anyhow::Error) -> bool {
    format!("{e:#}").contains("HTTP 404")
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

    #[test]
    fn reminders_read_like_teams() {
        let now = 1_000_000_000_000i64;
        let rec = |id: &str, t: &str, msg: i64, props: serde_json::Value| {
            let mut p = props;
            p["activity"] = serde_json::json!({
                "sourceThreadId": "19:a@unq.gbl.spaces", "sourceMessageId": msg,
                "sourceUserImDisplayName": "OST Test 3", "sourceUserId": "8:orgid:x",
                "messagePreview": format!("m{msg}"), "activitySubtype": "newReminder"
            });
            serde_json::json!({ "id": id, "originalarrivaltime": t, "properties": p })
        };
        let v = serde_json::json!({ "messages": [
            // Edited later: the newest record wins.
            rec("1", "2026-11-27T10:00:00Z", 11, serde_json::json!({ "duedate": now + 10 })),
            rec("2", "2026-11-27T11:00:00Z", 11, serde_json::json!({ "duedate": now + 5000 })),
            // Due (its time has come), and one flagged due.
            rec("3", "2026-11-27T10:00:00Z", 12, serde_json::json!({ "duedate": now - 5 })),
            rec("4", "2026-11-27T10:00:00Z", 13, serde_json::json!({ "duedate": now + 9, "isdue": true })),
            // Deleted, a duedate that isn't a number, an old completion.
            rec("5", "2026-11-27T10:00:00Z", 14, serde_json::json!({ "duedate": now, "isReminderDeleted": "true" })),
            rec("6", "2026-11-27T10:00:00Z", 15, serde_json::json!({ "duedate": "x" })),
            rec("7", "2026-11-27T10:00:00Z", 16, serde_json::json!({ "duedate": now - 9, "completeddate": now - 8 * 86_400_000 })),
            rec("8", "2026-11-27T10:00:00Z", 17, serde_json::json!({ "duedate": now - 9, "completeddate": now - 60_000 })),
        ]});
        let r = reminders_from(&v, now);
        let ids: Vec<&str> = r.iter().map(|x| x.item.message_id.as_str()).collect();
        assert_eq!(ids, ["12", "13", "11", "17"]);
        assert_eq!(r[2].due, now + 5000);
        assert!(r[0].is_due && r[1].is_due && !r[2].is_due && !r[3].is_due);
        assert_eq!(r[3].completed, now - 60_000);
        assert_eq!(r[0].item.sender, "OST Test 3");
        assert_eq!(r[0].stream_id, "3");

        // The due record (no preview, no name) over the newReminder one.
        let mut due = rec(
            "9",
            "2026-11-27T12:00:00Z",
            20,
            serde_json::json!({ "duedate": now - 1, "isdue": true }),
        );
        due["properties"]["activity"]["messagePreview"] = serde_json::json!("");
        due["properties"]["activity"]["sourceUserImDisplayName"] = serde_json::Value::Null;
        due["properties"]["activity"]["activityContext"] =
            serde_json::json!({ "displayBanner": "true" });
        let set = rec(
            "8",
            "2026-11-27T11:59:58Z",
            20,
            serde_json::json!({ "duedate": now - 1, "isdue": false }),
        );
        let r = reminders_from(&serde_json::json!({ "messages": [set, due] }), now);
        assert_eq!(r.len(), 1);
        assert!(r[0].is_due && r[0].banner);
        assert_eq!(r[0].stream_id, "9");
        assert_eq!(r[0].item.sender, "OST Test 3");
        assert_eq!(r[0].item.preview, "m20");

        // Removed: the newest record says so, and the older ones don't
        // bring it back.
        let mut gone = rec(
            "10",
            "2026-11-27T12:05:00Z",
            20,
            serde_json::json!({ "duedate": now - 1, "isdue": false }),
        );
        gone["properties"]["activity"]["activityReason"] = serde_json::json!("deleted");
        gone["properties"]["activity"]["activitySubtype"] = serde_json::json!("deleteReminder");
        let set = rec(
            "8",
            "2026-11-27T11:59:58Z",
            20,
            serde_json::json!({ "duedate": now - 1 }),
        );
        assert!(reminders_from(&serde_json::json!({ "messages": [set, gone] }), now).is_empty());
    }

    fn rec(
        time: &str,
        sub: &str,
        thread: &str,
        msg: i64,
        chain: i64,
        preview: &str,
    ) -> serde_json::Value {
        serde_json::json!({"originalarrivaltime": time, "properties": {"isread": true, "activity": {
            "activitySubtype": sub, "sourceThreadId": thread, "sourceMessageId": msg, "sourceReplyChainId": chain,
            "sourceUserImDisplayName": "Randy Northrup", "sourceUserId": "8:orgid:x", "messagePreview": preview,
            "sourceThreadTopic": "OST group test", "sourceThreadType": "chat",
            "activityContext": {"repliesCount": "3", "parentMessagePreview": "root"}}}})
    }

    #[test]
    fn a_missing_stream_reads_as_empty() {
        assert!(is_missing(&anyhow::anyhow!(
            "HTTP 404 for https://amer.ng.msg.teams.microsoft.com/v1/users/ME/conversations/48:saved/messages: {{}}"
        )));
        assert!(!is_missing(&anyhow::anyhow!("HTTP 500 for https://x")));
        assert!(saved_from(&serde_json::json!({ "messages": [] })).is_empty());
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
        assert_eq!(
            (
                s[0].preview.as_str(),
                s[0].message_id.as_str(),
                s[0].channel
            ),
            ("OST test 43: typing clears on send", "1794032815852", false)
        );
    }

    #[test]
    fn followed_has_one_row_per_thread() {
        let v = serde_json::json!({"messages": [
            rec("2026-11-05T18:58:54Z", "reply", "19:c@thread.tacv2", 1794244337587, 1793889784763, "71"),
            rec("2026-11-09T17:47:10Z", "reply", "19:c@thread.tacv2", 1794246428605, 1794245518435, "72"),
            rec("2026-11-04T10:00:00Z", "reply", "19:c@thread.tacv2", 1, 1793889784763, "older"),
        ]});
        let f = followed_from(&v);
        assert_eq!(
            f.iter().map(|i| i.preview.as_str()).collect::<Vec<_>>(),
            vec!["72", "71"]
        );
        assert!(f[0].channel);
        assert_eq!((f[0].replies, f[0].parent_preview.as_str()), (3, "root"));
    }

    #[test]
    fn followed_marks_meeting_and_deleted_roots() {
        let mut meeting = rec(
            "2026-11-24T18:00:00Z",
            "reply",
            "19:c@thread.tacv2",
            2,
            1,
            "reply",
        );
        let ctx = &mut meeting["properties"]["activity"]["activityContext"];
        ctx["parentMessageType"] = "Meeting".into();
        ctx["parentMessageSubject"] = "OST TEST 272 channel meeting".into();
        let mut deleted = rec(
            "2026-11-24T17:00:00Z",
            "reply",
            "19:c@thread.tacv2",
            4,
            3,
            "reply",
        );
        deleted["properties"]["activity"]["activityContext"]["parentMessagePreviewTemplateOption"] =
            "deleted".into();
        let root = rec(
            "2026-11-24T16:00:00Z",
            "reply",
            "19:c@thread.tacv2",
            5,
            5,
            "the post",
        );
        let f = followed_from(&serde_json::json!({"messages": [meeting, deleted, root]}));
        let got: Vec<_> = f
            .iter()
            .map(|i| {
                (
                    i.parent_icon.as_str(),
                    i.parent_subject.as_str(),
                    i.parent_preview.as_str(),
                )
            })
            .collect();
        assert_eq!(
            got,
            vec![
                ("meeting", "OST TEST 272 channel meeting", "root"),
                ("deleted", "", "root"),
                ("", "", "the post")
            ]
        );
    }

    #[test]
    fn followed_drops_deleted_threads() {
        // As 48:threads had "OST TEST 272 channel meeting" once its post was
        // deleted: a "deleted" record newer than the thread's reply.
        let reply = rec(
            "2026-11-24T10:04:00Z",
            "reply",
            "19:c@thread.tacv2",
            2,
            1,
            "reply",
        );
        let deleted = serde_json::json!({"originalarrivaltime": "2026-11-24T10:04:47.573Z", "properties": {"isread": true, "activity": {
            "activityReason": "deleted", "activityType": "threads", "deleteActivityTimestamp": 1795518032624_i64,
            "sourceMessageId": 1, "sourceReplyChainId": 1, "sourceThreadId": "19:c@thread.tacv2", "sourceThreadType": "topic",
            "activityContext": {"parentMessagePreviewTemplateOption": "deleted", "repliesCount": "0"}}}});
        let other = rec(
            "2026-11-17T12:41:16Z",
            "reply",
            "19:c@thread.tacv2",
            4,
            3,
            "kept",
        );
        let f = followed_from(&serde_json::json!({"messages": [reply, deleted, other]}));
        assert_eq!(
            f.iter().map(|i| i.preview.as_str()).collect::<Vec<_>>(),
            vec!["kept"]
        );
    }
}
