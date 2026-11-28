//! What Teams' message ··· menu does (docs/spec/message-actions.md): copy
//! link, save, pin, mark as unread and read receipts.

use super::client::TeamsClient;
use anyhow::{Context, Result};
use std::collections::HashSet;

/// Teams' deep-link base for a native client (`deepLinkDomains[0]`).
pub const LINK_BASE: &str = "https://teams.microsoft.com";

/// JavaScript's encodeURIComponent.
fn enc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A chat message's link (495364 `v`).
pub fn chat_message_link(
    conv: &str,
    message_id: &str,
    parent: Option<&str>,
    my_oid: &str,
) -> String {
    let ctx = if conv == "48:notes" {
        format!("{{\"contextType\":\"chat\",\"oid\":\"{my_oid}\"}}")
    } else {
        "{\"contextType\":\"chat\"}".to_string()
    };
    match parent {
        Some(p) => format!(
            "{LINK_BASE}/l/message/{conv}/{message_id}?parentMessageId={p}&context={}",
            enc(&ctx)
        ),
        None => format!(
            "{LINK_BASE}/l/message/{conv}/{message_id}?context={}",
            enc(&ctx)
        ),
    }
}

/// A channel post's or reply's link (81601 `zn`).
#[allow(clippy::too_many_arguments)]
pub fn channel_message_link(
    channel: &str,
    message_id: &str,
    parent: &str,
    tenant: &str,
    group_id: &str,
    team_name: &str,
    channel_name: &str,
    created_ms: i64,
    private_or_shared: bool,
    shared: bool,
) -> String {
    let mut s = format!(
        "{LINK_BASE}/l/message/{channel}/{message_id}?tenantId={tenant}&groupId={group_id}&parentMessageId={parent}&teamName={}&channelName={}&createdTime={created_ms}",
        enc(team_name),
        enc(channel_name)
    );
    if private_or_shared {
        s.push_str("&ngc=true");
    }
    if shared {
        s.push_str("&allowXTenantAccess=true");
    }
    s
}

/// lodash `truncate(text, {length})`: at most `length` characters, ending
/// in "..." when cut.
pub fn truncate(text: &str, length: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= length {
        return text.to_string();
    }
    let keep = length.saturating_sub(3);
    format!("{}...", chars[..keep].iter().collect::<String>())
}

/// The copied link's text: "{name}: {message}" cut to 85 characters (a
/// channel adds " | {channel}").
pub fn copy_link_text(display_name: &str, message: &str, channel_name: Option<&str>) -> String {
    let collapsed = message.split_whitespace().collect::<Vec<_>>().join(" ");
    let text = truncate(&format!("{display_name}: {collapsed}"), 85);
    match channel_name {
        Some(c) if !c.is_empty() => format!("{text} | {c}"),
        _ => text,
    }
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

/// The HTML Teams puts on the clipboard with the link (223398); `title` only
/// for channel links.
pub fn copy_link_html(url: &str, text: &str, with_title: bool) -> String {
    let u = html_escape(url);
    let title = if with_title {
        format!(" title=\"{u}\"")
    } else {
        String::new()
    };
    format!(
        "<div itemprop=\"teams-copy-link\"><a href=\"{u}\"{title}>{}</a></div>",
        html_escape(text)
    )
}

/// Save or unsave a message (`PUT …/rcmetadata/{rcId||msgId}` with `{s, mid}`).
pub async fn set_saved(
    client: &TeamsClient,
    conv: &str,
    reply_chain: &str,
    message_id: &str,
    save: bool,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/rcmetadata/{}",
        client.chat_service_url(),
        conv,
        if reply_chain.is_empty() {
            message_id
        } else {
            reply_chain
        }
    );
    let mid: i64 = message_id.parse().context("message id")?;
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "s": if save { 1 } else { 0 }, "mid": mid }),
        )
        .await?;
    Ok(())
}

/// Set (or move) your reminder on a message, Teams' Remind me
/// (`createOrUpdateMessageReminder`): `PUT …/rcmetadata/{rcId||msgId}` with
/// `{r: due ms, mid}`; `r: 0` marks it completed (Teams' COMPLETE).
pub async fn set_reminder(
    client: &TeamsClient,
    conv: &str,
    reply_chain: &str,
    message_id: &str,
    due_ms: i64,
) -> Result<()> {
    put_rc_metadata(
        client,
        conv,
        reply_chain,
        message_id,
        |mid| serde_json::json!({ "r": due_ms, "mid": mid }),
    )
    .await
}

/// Remove your reminder on a message (Teams' `deleteMessageReminder`:
/// the same PUT with `{dr: true, mid}`).
///
/// A 404 (no metadata left for the thread) falls back to Teams' soft
/// delete: `isReminderDeleted` on the message's `48:reminders` records.
pub async fn remove_reminder(
    client: &TeamsClient,
    conv: &str,
    reply_chain: &str,
    message_id: &str,
) -> Result<()> {
    let removed = put_rc_metadata(
        client,
        conv,
        reply_chain,
        message_id,
        |mid| serde_json::json!({ "dr": true, "mid": mid }),
    )
    .await;
    match removed {
        Err(e) if e.to_string().contains("HTTP 404") => {
            soft_delete_reminder(client, conv, message_id).await
        }
        other => other,
    }
}

/// The `48:reminders` records of one message (stream message ids).
pub fn reminder_records_of(v: &serde_json::Value, conv: &str, message_id: &str) -> Vec<String> {
    let text = |x: &serde_json::Value| {
        x.as_str()
            .map(str::to_string)
            .or_else(|| x.as_i64().map(|n| n.to_string()))
            .unwrap_or_default()
    };
    v["messages"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|m| {
            let a = &m["properties"]["activity"];
            text(&a["sourceThreadId"]) == conv && text(&a["sourceMessageId"]) == message_id
        })
        .filter_map(|m| m["id"].as_str().map(str::to_string))
        .collect()
}

/// Teams' markMessageReminderAsDeleted: `PUT …/48:reminders/messages/{id}
/// /properties?name=isReminderDeleted` with `{"isReminderDeleted":"true"}`.
async fn soft_delete_reminder(client: &TeamsClient, conv: &str, message_id: &str) -> Result<()> {
    let base = format!(
        "{}/v1/users/ME/conversations/48:reminders",
        client.chat_service_url()
    );
    let (records, _) = super::quick_views::reminder_records(client).await?;
    let ids = reminder_records_of(
        &serde_json::json!({ "messages": records }),
        conv,
        message_id,
    );
    if ids.is_empty() {
        anyhow::bail!("no reminder to remove");
    }
    for id in ids {
        client
            .chat_request(
                reqwest::Method::PUT,
                &format!("{base}/messages/{id}/properties?name=isReminderDeleted"),
                &serde_json::json!({ "isReminderDeleted": "true" }),
            )
            .await?;
    }
    Ok(())
}

async fn put_rc_metadata(
    client: &TeamsClient,
    conv: &str,
    reply_chain: &str,
    message_id: &str,
    body: impl FnOnce(i64) -> serde_json::Value,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/rcmetadata/{}",
        client.chat_service_url(),
        conv,
        if reply_chain.is_empty() {
            message_id
        } else {
            reply_chain
        }
    );
    let mid: i64 = message_id.parse().context("message id")?;
    client
        .chat_request(reqwest::Method::PUT, &url, &body(mid))
        .await?;
    Ok(())
}

/// Your reminders' due times (ms) by message id: a thread's root from
/// `r`, its replies from `rl2` (`{replyId: due}`); 0 or none is no
/// reminder.
pub fn reminders_from(v: &serde_json::Value) -> std::collections::HashMap<String, i64> {
    let mut out = std::collections::HashMap::new();
    let num = |x: &serde_json::Value| {
        x.as_i64()
            .or_else(|| x.as_f64().map(|f| f as i64))
            .or_else(|| x.as_str().and_then(|s| s.parse().ok()))
            .unwrap_or(0)
    };
    for item in v
        .get("rcMetadataList")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
    {
        let root = item
            .get("rootMessageId")
            .map(|r| r.to_string().trim_matches('"').to_string())
            .unwrap_or_default();
        let md = item.get("rcMetadata");
        if let Some(r) = md.and_then(|m| m.get("r")).map(num).filter(|r| *r > 0) {
            out.insert(root, r);
        }
        for (id, due) in md
            .and_then(|m| m.get("rl2"))
            .and_then(|l| l.as_object())
            .into_iter()
            .flatten()
        {
            let due = num(due);
            if due > 0 {
                out.insert(id.clone(), due);
            }
        }
    }
    out
}

/// The ids of a conversation's saved messages (roots with `s == 1`, plus
/// saved replies `sl2`). No metadata yet (404) means none.
pub async fn saved_ids(client: &TeamsClient, conv: &str) -> Result<HashSet<String>> {
    Ok(rc_metadata(client, conv).await?.0)
}

/// The follow state of each thread with rcmetadata (`f`: 1 follows, 3
/// unfollowed), by root message id.
pub fn follow_from(v: &serde_json::Value) -> std::collections::HashMap<String, i64> {
    let mut out = std::collections::HashMap::new();
    for item in v
        .get("rcMetadataList")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
    {
        let root = item
            .get("rootMessageId")
            .map(|r| r.to_string().trim_matches('"').to_string())
            .unwrap_or_default();
        if let Some(f) = item.pointer("/rcMetadata/f").and_then(|f| f.as_i64()) {
            out.insert(root, f);
        }
    }
    out
}

/// A thread's read state from its rcmetadata (measured on winpc
/// 2026-11-10): `ch`, read to; `chb`, Mark as unread's bookmark (0 once
/// cleared).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ThreadHorizon {
    pub read_to: i64,
    pub bookmark: i64,
}

impl ThreadHorizon {
    /// Replies after this are unread: the bookmark while set, else `ch`.
    pub fn unread_after(&self) -> i64 {
        if self.bookmark > 0 {
            self.bookmark
        } else {
            self.read_to
        }
    }
}

/// Each thread's read state, by root message id.
pub fn horizons_from(v: &serde_json::Value) -> std::collections::HashMap<String, ThreadHorizon> {
    let mut out = std::collections::HashMap::new();
    for item in v
        .get("rcMetadataList")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
    {
        let root = item
            .get("rootMessageId")
            .map(|r| r.to_string().trim_matches('"').to_string())
            .unwrap_or_default();
        let n = |k: &str| {
            item.pointer(&format!("/rcMetadata/{k}"))
                .and_then(|x| x.as_i64())
                .unwrap_or(0)
        };
        let h = ThreadHorizon {
            read_to: n("ch"),
            bookmark: n("chb"),
        };
        if h.unread_after() > 0 {
            out.insert(root, h);
        }
    }
    out
}

/// The rcmetadata of a conversation: saved messages, thread follow states,
/// thread read states and your reminders' due times.
pub type RcMetadata = (
    HashSet<String>,
    std::collections::HashMap<String, i64>,
    std::collections::HashMap<String, ThreadHorizon>,
    std::collections::HashMap<String, i64>,
);

/// A conversation's saved messages, thread follow states, thread read
/// states and reminders, from one rcmetadata read.
pub async fn rc_metadata(client: &TeamsClient, conv: &str) -> Result<RcMetadata> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/rcmetadata?startTime=0&pageSize=200",
        client.chat_service_url(),
        conv
    );
    let resp = match client.chat_get(&url).await {
        Ok(r) => r,
        Err(e) if e.to_string().contains("HTTP 404") => return Ok(Default::default()),
        Err(e) => return Err(e),
    };
    let v: serde_json::Value = resp.json().await?;
    Ok((
        saved_from(&v),
        follow_from(&v),
        horizons_from(&v),
        reminders_from(&v),
    ))
}

/// A change to a Threads-layout thread's read state, as Teams sends it
/// (measured on winpc 2026-11-10).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HorizonChange {
    /// Opening the thread reads it to its newest reply (`ch`).
    ReadTo(i64),
    /// Opening a thread marked unread clears the bookmark (`chb: 0`).
    ClearBookmark,
    /// Mark as unread: the bookmark just before the newest reply.
    UnreadFrom(i64),
}

impl HorizonChange {
    pub fn body(self) -> serde_json::Value {
        match self {
            HorizonChange::ReadTo(id) => serde_json::json!({ "ch": id }),
            HorizonChange::ClearBookmark => serde_json::json!({ "chb": 0 }),
            HorizonChange::UnreadFrom(id) => serde_json::json!({ "chb": id - 1 }),
        }
    }
}

/// Change where you've read a Threads-layout thread to (its rcmetadata).
pub async fn set_thread_horizon(
    client: &TeamsClient,
    conv: &str,
    root_id: &str,
    change: HorizonChange,
) -> Result<()> {
    anyhow::ensure!(
        root_id.bytes().all(|b| b.is_ascii_digit()) && !root_id.is_empty(),
        "Not a thread: {root_id}"
    );
    let body = change.body();
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!(
                "{}/v1/users/ME/conversations/{}/rcmetadata/{root_id}",
                client.chat_service_url(),
                conv
            ),
            &body,
        )
        .await?;
    Ok(())
}

/// Follow or unfollow a channel thread, as Teams does: the thread's
/// rcmetadata `f` (1 / 3) and the post's `follow` emotion (1 / 0).
pub async fn set_following(
    client: &TeamsClient,
    conv: &str,
    root_id: &str,
    follow: bool,
) -> Result<()> {
    let base = format!(
        "{}/v1/users/ME/conversations/{}",
        client.chat_service_url(),
        conv
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!("{base}/rcmetadata/{root_id}"),
            &serde_json::json!({ "f": if follow { 1 } else { 3 } }),
        )
        .await?;
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!("{base}/messages/{root_id}/properties?name=emotions"),
            &serde_json::json!({ "emotions": { "key": "follow", "value": if follow { 1 } else { 0 } } }),
        )
        .await?;
    Ok(())
}

pub fn saved_from(v: &serde_json::Value) -> HashSet<String> {
    let mut out = HashSet::new();
    for item in v
        .get("rcMetadataList")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
    {
        let root = item
            .get("rootMessageId")
            .map(|r| r.to_string().trim_matches('"').to_string())
            .unwrap_or_default();
        let md = item.get("rcMetadata");
        if md.and_then(|m| m.get("s")).and_then(|s| s.as_i64()) == Some(1) {
            out.insert(root);
        }
        for id in md
            .and_then(|m| m.get("sl2"))
            .and_then(|l| l.as_array())
            .into_iter()
            .flatten()
        {
            out.insert(id.to_string().trim_matches('"').to_string());
        }
    }
    out
}

/// Mark a message unread (L1): Teams writes the consumption-horizon
/// bookmark `"{arrival−1};{now};{clientMessageId}"`, not the horizon.
pub async fn mark_unread(
    client: &TeamsClient,
    conv: &str,
    arrival_ms: i64,
    client_message_id: &str,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/properties?name=consumptionHorizonBookmark",
        client.chat_service_url(),
        conv
    );
    let cmid = match client_message_id.split_once('_') {
        Some((_, after)) => after,
        None if client_message_id.is_empty() => "0",
        None => client_message_id,
    };
    let value = format!("{};{};{}", arrival_ms - 1, crate::clock::now_ms(), cmid);
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "consumptionHorizonBookmark": value }),
        )
        .await?;
    Ok(())
}

/// A thread's pinned messages, newest first (`threadProperties.pinnedItems`,
/// a JSON string of `{itemId, itemType}`).
pub async fn pinned_ids(client: &TeamsClient, conv: &str) -> Result<Vec<String>> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        conv
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await?;
    Ok(pinned_from(&v))
}

pub fn pinned_from(thread: &serde_json::Value) -> Vec<String> {
    thread
        .pointer("/properties/pinnedItems")
        .and_then(|p| p.as_str())
        .and_then(|s| serde_json::from_str::<Vec<serde_json::Value>>(s).ok())
        .unwrap_or_default()
        .into_iter()
        .filter_map(|i| {
            i.get("itemId")
                .map(|v| v.to_string().trim_matches('"').to_string())
        })
        .collect()
}

/// Teams' limit on pinned messages (`maxNumberOfMultiplePinnedMessages`).
pub const MAX_PINNED: usize = 10;

/// Pin (newest first) or unpin a message; returns the new list.
pub async fn set_pinned(
    client: &TeamsClient,
    conv: &str,
    message_id: &str,
    pin: bool,
) -> Result<Vec<String>> {
    let mut ids = pinned_ids(client, conv).await?;
    ids.retain(|i| i != message_id);
    if pin {
        ids.insert(0, message_id.to_string());
    }
    let items: Vec<serde_json::Value> = ids
        .iter()
        .map(|i| serde_json::json!({ "itemId": i, "itemType": "Message" }))
        .collect();
    let url = format!(
        "{}/v1/threads/{}/properties?name=pinnedItems",
        client.chat_service_url(),
        conv
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "pinnedItems": serde_json::to_string(&items)? }),
        )
        .await?;
    Ok(ids)
}

/// Who has read a message (298781 `F`): members other than me whose horizon
/// has passed it and who could see it. Returns (readers' MRIs, total).
pub async fn readers(
    client: &TeamsClient,
    conv: &str,
    arrival_ms: u64,
) -> Result<(Vec<String>, usize)> {
    let url = format!(
        "{}/v1/threads/{}/consumptionhorizons",
        client.chat_service_url(),
        conv
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await?;
    let me = client.self_mri().unwrap_or_default();
    Ok(readers_from(&v, &me, arrival_ms))
}

pub fn readers_from(v: &serde_json::Value, me: &str, arrival_ms: u64) -> (Vec<String>, usize) {
    let all: Vec<&serde_json::Value> = v
        .get("consumptionhorizons")
        .and_then(|h| h.as_array())
        .into_iter()
        .flatten()
        .filter(|h| {
            h.get("id")
                .and_then(|i| i.as_str())
                .is_some_and(|i| !i.eq_ignore_ascii_case(me))
        })
        .collect();
    let num = |x: Option<&serde_json::Value>| -> u64 {
        x.and_then(|t| {
            t.as_u64()
                .or_else(|| t.as_str().and_then(|s| s.split(';').next()?.parse().ok()))
        })
        .unwrap_or(0)
    };
    let readers = all
        .iter()
        .filter(|h| {
            let read_to = num(h.get("consumptionhorizon"));
            let visible = num(h.get("messageVisibilityTime"));
            arrival_ms <= read_to && arrival_ms >= visible
        })
        .filter_map(|h| h.get("id").and_then(|i| i.as_str()).map(str::to_string))
        .collect();
    (readers, all.len())
}

/// Forward messages (Teams' forward): `POST …/conversations/{SOURCE}/messages/forward`
/// with the target in the body and the optional note as an ordinary message.
/// Returns the new message ids.
pub async fn forward(
    client: &TeamsClient,
    source: &str,
    message_ids: &[String],
    target: &str,
    note_html: &str,
) -> Result<Vec<String>> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/forward",
        client.chat_service_url(),
        source
    );
    let additional = serde_json::json!({
        "content": note_html,
        "messagetype": "RichText/Html",
        "contenttype": "Text",
        "clientmessageid": super::outbox::new_client_message_id(),
        "imdisplayname": client.display_name().unwrap_or_default(),
        "properties": { "importance": "", "formatVariant": "TEAMS" },
    });
    let body = serde_json::json!({
        "targetThreadIds": [target],
        "messageIds": message_ids,
        "additionalMessage": additional,
        "templateId": "basic_forward_message_template",
    });
    let resp = client
        .chat_request(reqwest::Method::POST, &url, &body)
        .await?;
    let v: serde_json::Value = resp.json().await.unwrap_or_default();
    let results = v.as_array().cloned().unwrap_or_default();
    let mut ids = Vec::new();
    for r in &results {
        let status = r.get("statusCode").and_then(|s| s.as_u64()).unwrap_or(200);
        if !(200..300).contains(&status) || r.get("error").is_some_and(|e| !e.is_null()) {
            anyhow::bail!("Failed to forward ({status})");
        }
        if let Some(id) = r.get("messageId") {
            ids.push(id.to_string().trim_matches('"').to_string());
        }
    }
    Ok(ids)
}

/// Teams' security report body for a message (`reportMessageToUnified`).
pub fn security_report_body(
    conv: &str,
    message_id: &str,
    comment: &str,
    now_iso: &str,
) -> serde_json::Value {
    serde_json::json!({
        "reportTimestamp": now_iso,
        "reportType": "message",
        "threadId": conv,
        "messageId": message_id.parse::<i64>().unwrap_or(0),
        "actions": [],
        "category": "Security",
        "comment": comment,
    })
}

/// Report a message as a security risk (Teams' unified report API:
/// `POST {mt}/beta/reports`). This reaches the tenant's admins and
/// Microsoft.
pub async fn report_security(
    client: &TeamsClient,
    conv: &str,
    message_id: &str,
    comment: &str,
) -> Result<()> {
    let mt = client
        .middle_tier_url()
        .context("No middle-tier address for this account")?;
    let token = super::directory::middle_tier_token().await?;
    let now = crate::clock::now_iso_ms();
    let resp = client
        .http()
        .post(format!("{mt}/beta/reports"))
        .bearer_auth(token)
        .json(&security_report_body(conv, message_id, comment, &now))
        .send()
        .await
        .context("report request")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} reporting", resp.status().as_u16());
    }
    Ok(())
}

/// Teams' security report body for a meeting (More ▸ Report a concern:
/// the unified report service's `reportType: "Meeting"`), naming the
/// participants you chose (MRIs).
pub fn meeting_report_body(
    thread_id: &str,
    call_id: &str,
    ical_uid: &str,
    reported_users: &[String],
    comment: &str,
    now_iso: &str,
) -> serde_json::Value {
    let mut b = serde_json::json!({
        "reportTimestamp": now_iso,
        "reportType": "Meeting",
        "reportedUsers": reported_users,
        "actions": [],
        "category": "Security",
        "comment": comment,
    });
    if !call_id.is_empty() {
        b["callId"] = call_id.into();
    }
    if !ical_uid.is_empty() {
        b["iCalUId"] = ical_uid.into();
    }
    b["threadId"] = thread_id.into();
    b
}

/// Report a meeting as a security concern (the unified report API, as
/// messages are reported). This reaches the tenant's admins and Microsoft.
pub async fn report_meeting(
    client: &TeamsClient,
    thread_id: &str,
    call_id: &str,
    ical_uid: &str,
    reported_users: &[String],
    comment: &str,
) -> Result<()> {
    let mt = client
        .middle_tier_url()
        .context("No middle-tier address for this account")?;
    let token = super::directory::middle_tier_token().await?;
    let now = crate::clock::now_iso_ms();
    let resp = client
        .http()
        .post(format!("{mt}/beta/reports"))
        .bearer_auth(token)
        .json(&meeting_report_body(
            thread_id,
            call_id,
            ical_uid,
            reported_users,
            comment,
            &now,
        ))
        .send()
        .await
        .context("report request")?;
    if !resp.status().is_success() {
        anyhow::bail!("HTTP {} reporting", resp.status().as_u16());
    }
    Ok(())
}

/// An AAD token for CSA (the chat service aggregator's resource), cached
/// for 45 minutes.
async fn csa_token() -> Result<String> {
    use std::sync::Mutex;
    use std::time::{Duration, Instant};
    static CACHE: Mutex<Option<(String, Instant)>> = Mutex::new(None);
    if let Some((t, at)) = CACHE.lock().unwrap().as_ref()
        && at.elapsed() < Duration::from_secs(45 * 60)
    {
        return Ok(t.clone());
    }
    let t = crate::auth::oauth::access_token_for("https://chatsvcagg.teams.microsoft.com/.default")
        .await?;
    *CACHE.lock().unwrap() = Some((t.clone(), Instant::now()));
    Ok(t)
}

/// One message's on-demand translation (CSA's reply item).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Translation {
    /// Teams' status: Done, TranslationNotNeeded, MessageNotFound,
    /// VersionNotFound, LanguageDetectionFailed or UnknownError.
    pub status: String,
    pub content: String,
    pub detected_language: String,
}

/// The languages Teams translates into, named in `locale` (Teams'
/// GetSupportedTranslationLanguages): `[(code, name)]` from
/// `GET {csa}/api/v1/translator/languages?locale=…`.
pub async fn translation_languages(
    client: &TeamsClient,
    locale: &str,
) -> Result<Vec<(String, String)>> {
    let locale: String = locale
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
        .collect();
    let url = format!(
        "{}/api/v1/translator/languages?locale={}",
        client.chatsvcagg_url(),
        locale
    );
    let token = csa_token().await?;
    let resp = client
        .http()
        .get(&url)
        .bearer_auth(token)
        .header("x-ms-use-acs-translation", "true")
        .send()
        .await
        .context("translation languages request")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!(
            "HTTP {} for translation languages: {}",
            status.as_u16(),
            text.chars().take(200).collect::<String>()
        );
    }
    Ok(parse_translation_languages(
        &serde_json::from_str(&text).context("translation languages")?,
    ))
}

/// CSA's language list: `[{languageTag, languageName}]` (possibly under
/// `languages` or `value`).
fn parse_translation_languages(v: &serde_json::Value) -> Vec<(String, String)> {
    let list = v
        .as_array()
        .or_else(|| v.get("languages").and_then(|l| l.as_array()))
        .or_else(|| v.get("value").and_then(|l| l.as_array()));
    list.into_iter()
        .flatten()
        .filter_map(|l| {
            Some((
                l.get("languageTag")?.as_str()?.to_string(),
                l.get("languageName")?.as_str()?.to_string(),
            ))
        })
        .collect()
}

/// Translate a chat message into `lang` on demand (Teams' Translate):
/// `POST {csa}/api/v1/chats/{conv}/messages/languages/{lang}` with
/// `[{"id": …}]`.
pub async fn translate(
    client: &TeamsClient,
    conv: &str,
    message_id: &str,
    lang: &str,
) -> Result<Translation> {
    translate_with(client, conv, message_id, lang, None).await
}

/// Teams' translation request: on demand (`known` None, Teams'
/// x-ms-on-demand-translation) or automatic (Auto-translate all messages),
/// which sends the languages you never want translated
/// (x-ms-knownLanguages) so CSA skips those.
pub async fn translate_with(
    client: &TeamsClient,
    conv: &str,
    message_id: &str,
    lang: &str,
    known: Option<&[String]>,
) -> Result<Translation> {
    let url = format!(
        "{}/api/v1/chats/{}/messages/languages/{}",
        client.chatsvcagg_url(),
        conv,
        lang
    );
    let request_id = uuid::Uuid::new_v4().to_string();
    let token = csa_token().await?;
    let resp = client
        .http()
        .post(&url)
        .bearer_auth(token)
        .header("x-ms-request-id", request_id.as_str())
        .header("x-ms-use-acs-translation", "true");
    let resp = match known {
        None => resp.header("x-ms-on-demand-translation", "true"),
        Some(k) => resp.header("x-ms-knownLanguages", k.join(",")),
    }
    .json(&serde_json::json!([{ "id": message_id }]))
    .send()
    .await
    .context("translation request")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!(
            "HTTP {} translating: {}",
            status.as_u16(),
            text.chars().take(200).collect::<String>()
        );
    }
    tracing::debug!(reply = %text, "translation reply");
    let v: serde_json::Value = serde_json::from_str(&text).context("translation reply")?;
    let item = v
        .as_array()
        .and_then(|a| {
            a.iter().find(|i| {
                i.get("id")
                    .map(|x| x.to_string().trim_matches('"').to_string())
                    == Some(message_id.to_string())
            })
        })
        .cloned()
        .unwrap_or_default();
    let code = item
        .get("resultCode")
        .and_then(|c| c.as_str())
        .unwrap_or_default();
    let status = match code {
        "Success" => "Done",
        "MessageNotFound" => "MessageNotFound",
        "VersionNotFound" => "VersionNotFound",
        "LanguageDetectionFailed" => "LanguageDetectionFailed",
        "SkipTranslation" | "ContentIsEmpty" => "TranslationNotNeeded",
        _ => "UnknownError",
    };
    Ok(Translation {
        status: status.into(),
        content: item
            .get("translatedContent")
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .to_string(),
        detected_language: item
            .pointer("/detectedLanguage/languageId")
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_messages_reminder_records_are_found() {
        let rec = |id: &str, conv: &str, msg: serde_json::Value| serde_json::json!({ "id": id, "properties": { "activity": { "sourceThreadId": conv, "sourceMessageId": msg } } });
        let v = serde_json::json!({ "messages": [
            rec("1", "19:a", serde_json::json!(5)),
            rec("2", "19:a", serde_json::json!("5")),
            rec("3", "19:a", serde_json::json!(6)),
            rec("4", "19:b", serde_json::json!(5)),
        ]});
        assert_eq!(reminder_records_of(&v, "19:a", "5"), ["1", "2"]);
    }

    #[test]
    fn reminders_come_from_r_and_rl2() {
        let v = serde_json::json!({ "rcMetadataList": [
            { "rootMessageId": 100, "rcMetadata": { "s": 1, "r": 1_800_000_000_000i64, "rl2": { "101": 1_800_000_100_000i64, "102": 0 } } },
            { "rootMessageId": "200", "rcMetadata": { "r": 0 } },
            { "rootMessageId": "300", "rcMetadata": { "f": 1 } },
        ]});
        let r = reminders_from(&v);
        assert_eq!(r.get("100"), Some(&1_800_000_000_000));
        assert_eq!(r.get("101"), Some(&1_800_000_100_000));
        assert_eq!(r.len(), 2);
    }

    #[test]
    fn chat_requests_are_answered_as_teams_does() {
        let mri = "8:live:.cid.ca2738c364862c6";
        let (path, body) = request_list_call(RequestAnswer::Accept, mri);
        assert_eq!(path, "/beta/userSettings/acceptlist/manage");
        assert_eq!(body, serde_json::json!({ "add": [mri] }));
        let (path, body) = request_list_call(RequestAnswer::Block, mri);
        assert_eq!(path, "/beta/userSettings/blocklist/manage");
        assert_eq!(body["add"][0], mri);
    }

    #[test]
    fn meeting_report_as_teams_sends_it() {
        let b = meeting_report_body(
            "19:meeting_x@thread.v2",
            "call-1",
            "0400",
            &["8:teamsvisitor:abc".to_string()],
            "why",
            "2026-11-09T00:00:00.000Z",
        );
        let mut keys: Vec<_> = b.as_object().unwrap().keys().cloned().collect();
        keys.sort();
        assert_eq!(
            keys,
            [
                "actions",
                "callId",
                "category",
                "comment",
                "iCalUId",
                "reportTimestamp",
                "reportType",
                "reportedUsers",
                "threadId"
            ]
        );
        assert_eq!(b["reportType"], "Meeting");
        assert_eq!(b["category"], "Security");
        assert_eq!(
            b["reportedUsers"],
            serde_json::json!(["8:teamsvisitor:abc"])
        );
        let c = meeting_report_body("19:x", "", "", &[], "", "t");
        assert!(c.get("callId").is_none() && c.get("iCalUId").is_none());
    }

    #[test]
    fn links_are_teams() {
        assert_eq!(
            chat_message_link("19:a@thread.v2", "1794", None, "x"),
            "https://teams.microsoft.com/l/message/19:a@thread.v2/1794?context=%7B%22contextType%22%3A%22chat%22%7D"
        );
        assert!(chat_message_link("48:notes", "1", None, "me").contains("%22oid%22%3A%22me%22"));
        let c = channel_message_link(
            "19:c@thread.tacv2",
            "5",
            "5",
            "t",
            "g",
            "Team A",
            "General",
            7,
            false,
            false,
        );
        assert_eq!(
            c,
            "https://teams.microsoft.com/l/message/19:c@thread.tacv2/5?tenantId=t&groupId=g&parentMessageId=5&teamName=Team%20A&channelName=General&createdTime=7"
        );
        assert_eq!(truncate("abcdef", 5), "ab...");
        assert_eq!(copy_link_text("Ann", "hi   there", None), "Ann: hi there");
        assert_eq!(
            copy_link_html("https://x/?a=1&b=2", "Ann: <hi>", false),
            "<div itemprop=\"teams-copy-link\"><a href=\"https://x/?a=1&amp;b=2\">Ann: &lt;hi&gt;</a></div>"
        );
    }

    #[test]
    fn forwards_parse_as_teams_cards() {
        let content = "<blockquote itemtype=\"http://schema.skype.com/Forward\"><p>hello</p></blockquote><p>note</p>";
        let props: serde_json::Value = serde_json::json!({"originalMessageContext": "{\"originalSender\":\"8:orgid:a\",\"originalSentTime\":\"2026-11-07T06:26:55.852Z\",\"messageId\":\"1794032815852\",\"originalThreadId\":\"19:x@thread.v2\"}"});
        let (f, rest) = super::super::messages::split_forward(content, Some(&props));
        let f = f.unwrap();
        assert_eq!(
            (
                f.sender_mri.as_str(),
                f.arrival_ms,
                f.text.as_str(),
                f.thread_id.as_str()
            ),
            ("8:orgid:a", 1794032815852, "hello", "19:x@thread.v2")
        );
        assert_eq!(rest, "<p>note</p>");
        // Without the context the blockquote stays ordinary HTML.
        assert!(
            super::super::messages::split_forward(content, None)
                .0
                .is_none()
        );
    }

    #[test]
    fn security_reports_are_teams_body() {
        let b = security_report_body("19:a@thread.v2", "1794", "spam", "2026-11-07T00:00:00.000Z");
        assert_eq!(b["reportType"], "message");
        assert_eq!(b["messageId"], 1794);
        assert_eq!(b["category"], "Security");
        assert_eq!(b["threadId"], "19:a@thread.v2");
        assert_eq!(b["actions"], serde_json::json!([]));
    }

    #[test]
    fn saved_pinned_and_readers_parse() {
        let v: serde_json::Value = serde_json::from_str(r#"{"rcMetadataList":[{"rootMessageId":1794039440533,"rcMetadata":{"s":1,"sl2":[]}},{"rootMessageId":5,"rcMetadata":{"s":0,"sl2":[6]}}]}"#).unwrap();
        let s = saved_from(&v);
        assert!(s.contains("1794039440533") && s.contains("6") && !s.contains("5"));
        let t: serde_json::Value = serde_json::from_str(r#"{"properties":{"pinnedItems":"[{\"itemId\":\"9\",\"itemType\":\"Message\"},{\"itemId\":\"3\",\"itemType\":\"Message\"}]"}}"#).unwrap();
        assert_eq!(pinned_from(&t), vec!["9", "3"]);
        let h: serde_json::Value = serde_json::from_str(r#"{"consumptionhorizons":[{"id":"8:orgid:me","consumptionhorizon":"100;1;x"},{"id":"8:orgid:a","consumptionhorizon":"100;1;x","messageVisibilityTime":0},{"id":"8:orgid:b","consumptionhorizon":"50;1;x"}]}"#).unwrap();
        assert_eq!(
            readers_from(&h, "8:orgid:me", 80),
            (vec!["8:orgid:a".to_string()], 2)
        );
    }
}

/// Teams' link to a chat (Copy link in the chat's ··· menu).
pub fn chat_link(chat_id: &str) -> String {
    let enc: String = chat_id
        .bytes()
        .map(|b| match b {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'_'
            | b'.'
            | b'!'
            | b'~'
            | b'*'
            | b'\''
            | b'('
            | b')' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect();
    format!(
        "https://teams.microsoft.com/l/chat/{enc}/conversations?context=%7B%22contextType%22%3A%22chat%22%7D"
    )
}

/// Rename a group chat as Teams does: `PUT /v1/threads/{id}/properties?name=topic`.
pub async fn set_chat_topic(client: &TeamsClient, chat_id: &str, topic: &str) -> Result<()> {
    let url = format!(
        "{}/v1/threads/{}/properties?name=topic",
        client.chat_service_url(),
        chat_id
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "topic": topic }),
        )
        .await?;
    Ok(())
}

/// How you answer a chat request (Teams' Block / Accept).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequestAnswer {
    Accept,
    Block,
}

/// The middle-tier list call and body behind an answer: Accept puts the
/// person on your accept list (`POST {mt}/beta/userSettings/acceptlist/
/// manage`, `{"add": [mri]}`, Teams' AcceptListService), Block on your
/// block list (`…/blocklist/manage`, the same body, Teams' blockService).
pub fn request_list_call(answer: RequestAnswer, mri: &str) -> (&'static str, serde_json::Value) {
    let path = match answer {
        RequestAnswer::Accept => "/beta/userSettings/acceptlist/manage",
        RequestAnswer::Block => "/beta/userSettings/blocklist/manage",
    };
    (path, serde_json::json!({ "add": [mri] }))
}

/// Answer a one-on-one chat request from `mri` (someone on Teams free) as
/// Teams' work client does (shared worker `acceptBlockUnblockChat`, Teams
/// 26304): the person goes on your accept or block list in the middle
/// tier; the chat service then lifts the chat's quarantine
/// (`relationshipState.inQuarantine` false after Accept, live check
/// 2026-11-27). Teams also records the chat's `interopconversationstatus`
/// (Accepted / Blocked), but only in its own store: the chat service
/// refuses that property (400 ThreadPropertyNotAllowed).
pub async fn answer_chat_request(
    client: &TeamsClient,
    chat_id: &str,
    mri: &str,
    answer: RequestAnswer,
) -> Result<()> {
    anyhow::ensure!(
        crate::identity::is_person_mri(mri) && !mri.contains(['/', '?', '#']),
        "Not a person"
    );
    anyhow::ensure!(
        chat_id.starts_with("19:") && !chat_id.contains(['/', '?', '#']),
        "Not a chat id"
    );
    if client.is_personal() {
        return answer_personal_request(client, chat_id, mri, answer).await;
    }
    let (base, token) = super::tabs::middle_tier(client).await?;
    let (path, body) = request_list_call(answer, mri);
    let req = client.http().post(format!("{base}{path}"));
    client
        .middle_tier_auth(req, &token)
        .header("x-ms-client-caller", "acceptBlockUnblockChat")
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("Accept or block list")?;
    Ok(())
}

/// A personal account's answer, as Teams free's worker gives it
/// (`acceptBlockUnblockChat` in its life build, read 2026-11-28; Teams
/// free's middle tier has no accept list: 405):
/// - Accept a 1:1 request: the person goes in your contacts (`POST
///   {mt}/beta/contacts/buddylist/TflContacts/managebuddies`), which lifts
///   the chat's quarantine;
/// - Accept a group request: your membership's `relationshipState` becomes
///   "Accepted" (`PUT {chat}/v1/threads/{id}/members/{you}`);
/// - Block: the person goes on your block list (`POST {mt}/beta/
///   userSettings/blocklist/manage?ggEnabled=true`, `{"add": [mri]}`).
async fn answer_personal_request(
    client: &TeamsClient,
    chat_id: &str,
    mri: &str,
    answer: RequestAnswer,
) -> Result<()> {
    match answer {
        RequestAnswer::Accept if super::chat::known_one_on_one_thread(chat_id) => {
            super::chat::add_contact(client, mri).await
        }
        RequestAnswer::Accept => {
            let me = client.self_mri().context("No signed-in user")?;
            let url = crate::auth::token_hosts::service_url(
                &client.chat_service_url(),
                crate::auth::token_hosts::Audience::Teams,
                &["v1", "threads", chat_id, "members", &me],
                &[],
            )?;
            client
                .chat_request(
                    reqwest::Method::PUT,
                    url.as_str(),
                    &serde_json::json!({ "relationshipState": "Accepted" }),
                )
                .await
                .context("Group chat request")?;
            Ok(())
        }
        RequestAnswer::Block => {
            let (base, token) = super::tabs::middle_tier(client).await?;
            let req = client
                .http()
                .post(format!(
                    "{base}/beta/userSettings/blocklist/manage?ggEnabled=true"
                ))
                .header("x-ms-client-caller", "acceptBlockUnblockChat")
                .header("x-ms-counter", "postBlockedContacts");
            client
                .middle_tier_auth(req, &token)
                .json(&serde_json::json!({ "add": [mri] }))
                .send()
                .await?
                .error_for_status()
                .context("Block list")?;
            Ok(())
        }
    }
}

/// Mute or unmute a chat as Teams does: the conversation property
/// `alerts`, "false" when muted (`PUT /v1/users/ME/conversations/{id}/
/// properties?name=alerts`, measured on winpc).
pub async fn set_chat_muted(client: &TeamsClient, chat_id: &str, muted: bool) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/properties?name=alerts",
        client.chat_service_url(),
        chat_id
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "alerts": if muted { "false" } else { "true" } }),
        )
        .await?;
    Ok(())
}

/// Hide a chat from the list until something newer is said, or show it
/// again, as Teams does (measured on winpc): Hide writes the conversation
/// properties `unpinnedTime` (ms) and `historyHiddenTime` (ms, as a
/// string); Unhide writes both as null.
pub async fn set_chat_hidden(client: &TeamsClient, chat_id: &str, hidden: bool) -> Result<()> {
    let now = crate::clock::now_ms();
    let base = format!(
        "{}/v1/users/ME/conversations/{}/properties",
        client.chat_service_url(),
        chat_id
    );
    let (unpinned, history) = if hidden {
        (serde_json::json!(now), serde_json::json!(now.to_string()))
    } else {
        (serde_json::Value::Null, serde_json::Value::Null)
    };
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!("{base}?name=unpinnedTime"),
            &serde_json::json!({ "unpinnedTime": unpinned }),
        )
        .await?;
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!("{base}?name=historyHiddenTime"),
            &serde_json::json!({ "historyHiddenTime": history }),
        )
        .await?;
    Ok(())
}

/// Remove a chat's history for you, as Teams' Remove chat history does
/// (captured from Teams desktop 2026-11-11): the conversation property
/// `clearHistoryTime` (ms) set to now. The chat leaves your list and its
/// messages up to then are no longer shown; others keep theirs.
pub async fn clear_chat_history(client: &TeamsClient, chat_id: &str) -> Result<i64> {
    let now = crate::clock::now_ms();
    let url = format!(
        "{}/v1/users/ME/conversations/{}/properties?name=clearHistoryTime",
        client.chat_service_url(),
        chat_id
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "clearHistoryTime": now }),
        )
        .await?;
    Ok(now)
}

/// Leave a group chat (Teams' chat service `DELETE v1/threads/{id}/members/{mri}`).
pub async fn leave_chat(client: &TeamsClient, chat_id: &str, my_mri: &str) -> Result<()> {
    let url = format!(
        "{}/v1/threads/{}/members/{}",
        client.chat_service_url(),
        chat_id,
        my_mri
    );
    client
        .chat_request(reqwest::Method::DELETE, &url, &serde_json::Value::Null)
        .await?;
    Ok(())
}

/// How much of the chat's history people added to it see (Teams' Add
/// dialog): none, the past `n` days, or all of it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SharedHistory {
    None,
    Days(u32),
    All,
}

impl SharedHistory {
    /// Teams' `shareHistoryTime`: -1 for none, 0 for all, else the time
    /// (ms) from which history is shared.
    pub fn share_history_time(self, now_ms: i64) -> i64 {
        match self {
            Self::None => -1,
            Self::All => 0,
            Self::Days(d) => now_ms - i64::from(d) * 86_400_000,
        }
    }
}

/// The body Teams sends to add people to a chat.
pub fn add_members_body(mris: &[String], history: SharedHistory, now_ms: i64) -> serde_json::Value {
    let t = history.share_history_time(now_ms);
    serde_json::json!({
        "members": mris.iter().map(|m| serde_json::json!({"id": m, "role": "Admin", "shareHistoryTime": t})).collect::<Vec<_>>()
    })
}

/// Add people to a group chat as Teams does: `PUT /v1/threads/{id}/members`
/// with `{"members": [{id, role: "Admin", shareHistoryTime}]}`.
pub async fn add_chat_members(
    client: &TeamsClient,
    chat_id: &str,
    mris: &[String],
    history: SharedHistory,
) -> Result<()> {
    let url = format!(
        "{}/v1/threads/{}/members",
        client.chat_service_url(),
        chat_id
    );
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or_default();
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &add_members_body(mris, history, now),
        )
        .await?;
    Ok(())
}

/// The body Teams' calling sends to add someone it rings into a chat's
/// call to that chat (`addMembersToConversation` without a history
/// choice): `{"members": [{id, role: "Admin"}]}`, no `shareHistoryTime`.
/// The chat service then shares the chat from the moment they're added
/// (captured from Teams on the web 2026-11-27: the member came back with
/// `shareHistoryTime` = the time of the add).
pub fn call_invitee_body(mri: &str) -> serde_json::Value {
    serde_json::json!({ "members": [{ "id": mri, "role": "Admin" }] })
}

/// Whether Teams adds someone invited into a call on `thread` to that chat
/// (`CallingAddParticipantService.handleAddParticipant`): only when they
/// aren't a member, and not in a channel or a meeting's own chat (ECS
/// `addNudgedUserToThread`, off). `members` are the thread's MRIs.
pub fn adds_call_invitee(
    thread: &str,
    thread_type: Option<&str>,
    members: &[String],
    mri: &str,
) -> bool {
    use crate::calling::room_mode::{ConversationKind, conversation_kind};
    !matches!(
        conversation_kind(thread, thread_type),
        ConversationKind::Channel | ConversationKind::PrivateMeeting
    ) && !members.iter().any(|m| m.eq_ignore_ascii_case(mri))
}

/// Add someone being invited into the call on `thread` to that chat, as
/// Teams does alongside ringing them ([`adds_call_invitee`],
/// [`call_invitee_body`]): `PUT /v1/threads/{id}/members`. Returns whether
/// they were added (false: already a member, or a chat Teams leaves alone).
pub async fn add_call_invitee_to_chat(
    client: &TeamsClient,
    thread: &str,
    mri: &str,
) -> Result<bool> {
    let base = format!("{}/v1/threads/{}", client.chat_service_url(), thread);
    let v: serde_json::Value = client
        .chat_get(&format!("{base}?view=msnp24Equivalent"))
        .await?
        .json()
        .await
        .context("The call's chat")?;
    let members: Vec<String> = v["members"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| m["id"].as_str().map(str::to_string))
        .collect();
    let thread_type = v.pointer("/properties/threadType").and_then(|t| t.as_str());
    if !adds_call_invitee(thread, thread_type, &members, mri) {
        return Ok(false);
    }
    client
        .chat_request(
            reqwest::Method::PUT,
            &format!("{base}/members"),
            &call_invitee_body(mri),
        )
        .await?;
    Ok(true)
}

/// Remove someone from a group chat as Teams does:
/// `DELETE /v1/threads/{id}/members/{mri}`.
pub async fn remove_chat_member(client: &TeamsClient, chat_id: &str, mri: &str) -> Result<()> {
    let url = format!(
        "{}/v1/threads/{}/members/{}",
        client.chat_service_url(),
        chat_id,
        mri
    );
    client
        .chat_request(reqwest::Method::DELETE, &url, &serde_json::json!({}))
        .await?;
    Ok(())
}

#[cfg(test)]
mod add_members_tests {
    use super::*;

    #[test]
    fn history_choices_are_teams_share_history_times() {
        let m = vec!["8:orgid:a".to_string()];
        let now = 1_794_000_000_000;
        assert_eq!(
            add_members_body(&m, SharedHistory::None, now),
            serde_json::json!({"members": [{"id": "8:orgid:a", "role": "Admin", "shareHistoryTime": -1}]})
        );
        assert_eq!(
            add_members_body(&m, SharedHistory::All, now)["members"][0]["shareHistoryTime"],
            0
        );
        assert_eq!(
            add_members_body(&m, SharedHistory::Days(3), now)["members"][0]["shareHistoryTime"],
            now - 3 * 86_400_000
        );
    }

    #[test]
    fn call_invitees_join_group_chats_as_teams_adds_them() {
        let t2 = "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5";
        // Captured from Teams on the web (2026-11-27).
        assert_eq!(
            call_invitee_body(t2),
            serde_json::json!({"members": [{"id": t2, "role": "Admin"}]})
        );
        let chat = "19:e201a9bbafb941039539cddc43c16d5c@thread.v2";
        let members = vec!["8:orgid:01c4860d-5776-4b16-8736-6a739fcc8b34".to_string()];
        assert!(adds_call_invitee(chat, Some("chat"), &members, t2));
        // Already a member (MRIs compared without case).
        assert!(!adds_call_invitee(
            chat,
            Some("chat"),
            &[t2.to_uppercase()],
            t2
        ));
        // A meeting's chat or a channel: rung only.
        assert!(!adds_call_invitee(
            "19:meeting_abc@thread.v2",
            Some("meeting"),
            &members,
            t2
        ));
        assert!(!adds_call_invitee(
            "19:abc@thread.tacv2",
            Some("topic"),
            &members,
            t2
        ));
    }
}

#[cfg(test)]
mod chat_link_tests {
    #[test]
    fn chat_links_are_teams_links() {
        assert_eq!(
            super::chat_link("19:ef21@thread.v2"),
            "https://teams.microsoft.com/l/chat/19%3Aef21%40thread.v2/conversations?context=%7B%22contextType%22%3A%22chat%22%7D"
        );
    }
}
