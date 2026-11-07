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

/// A conversation's saved messages and thread follow states, from one
/// rcmetadata read.
pub async fn rc_metadata(
    client: &TeamsClient,
    conv: &str,
) -> Result<(HashSet<String>, std::collections::HashMap<String, i64>)> {
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
    Ok((saved_from(&v), follow_from(&v)))
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
    let value = format!(
        "{};{};{}",
        arrival_ms - 1,
        chrono::Utc::now().timestamp_millis(),
        cmid
    );
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
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
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
    let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
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

/// Translate a chat message into `lang` on demand (Teams' Translate):
/// `POST {csa}/api/v1/chats/{conv}/messages/languages/{lang}` with
/// `[{"id": …}]`.
pub async fn translate(
    client: &TeamsClient,
    conv: &str,
    message_id: &str,
    lang: &str,
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
        .header("x-ms-use-acs-translation", "true")
        .header("x-ms-on-demand-translation", "true")
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
