//! The Activity feed: Teams' `48:notifications` stream. Each message
//! carries a `properties.activity` record (what happened, who did it,
//! where, and a preview), which Teams words as "Randy reacted to your
//! message", "Missed call from Randy", and so on.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One notification, ready to show.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct ActivityItem {
    pub id: String,
    /// "reaction", "mention", "reply", "missedCall", "voicemail",
    /// "addedToTeam", or the service's own type for anything else.
    pub kind: String,
    /// The headline, as Teams words it.
    pub title: String,
    /// Message preview (may be empty).
    pub preview: String,
    /// "In chat with you", "Teams call", a channel name, …
    pub context: String,
    pub time: String,
    pub unread: bool,
    /// Who did it (MRI) and their name, for the picture.
    pub actor_mri: String,
    pub actor_name: String,
    /// Where to go: the chat or channel thread, and the message in it.
    pub thread_id: String,
    pub message_id: String,
    /// For reactions: the emoji (Teams shows it on the picture).
    pub emoji: String,
}

/// The newest notifications, newest first.
pub async fn feed(client: &TeamsClient, limit: usize) -> Result<Vec<ActivityItem>> {
    let url = format!(
        "{}/v1/users/ME/conversations/48:notifications/messages?pageSize={}&view=msnp24Equivalent",
        client.chat_service_url(),
        limit
    );
    let text = client
        .chat_get(&url)
        .await?
        .text()
        .await
        .context("Activity reply")?;
    Ok(parse_feed(&text))
}

/// Mark one notification read (Teams does this when it is opened).
pub async fn mark_item_read(client: &TeamsClient, id: &str) -> Result<()> {
    if !id.chars().all(|c| c.is_ascii_digit()) {
        anyhow::bail!("Not a message id");
    }
    let url = format!(
        "{}/v1/users/ME/conversations/48:notifications/messages/{}/properties?name=isread",
        client.chat_service_url(),
        id
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "isread": "true" }),
        )
        .await?;
    Ok(())
}

/// Mark the feed read up to its newest item (Teams does this when the
/// Activity view is shown).
pub async fn mark_read(client: &TeamsClient, newest_id: &str) -> Result<()> {
    super::messages::mark_read(client, "48:notifications", newest_id, newest_id).await
}

/// Parse a `48:notifications/messages` reply.
pub fn parse_feed(json: &str) -> Vec<ActivityItem> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let mut items: Vec<ActivityItem> = v
        .get("messages")
        .and_then(|m| m.as_array())
        .into_iter()
        .flatten()
        .filter_map(item_of)
        .collect();
    items.sort_by(|a, b| b.time.cmp(&a.time));
    items
}

fn item_of(m: &serde_json::Value) -> Option<ActivityItem> {
    let props = m.get("properties")?;
    // `activity` is JSON text (sometimes already an object).
    let act = match props.get("activity")? {
        serde_json::Value::String(s) => serde_json::from_str::<serde_json::Value>(s).ok()?,
        other => other.clone(),
    };
    let s = |k: &str| {
        act.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let kind_raw = s("activityType");
    let sub = s("activitySubtype");
    let actor_mri = s("sourceUserId");
    let actor = s("sourceUserImDisplayName");
    let topic = s("sourceThreadTopic");
    let thread_type = s("sourceThreadType");
    let is_app = actor_mri.starts_with("28:");
    let who = if actor.is_empty() {
        "Someone".to_string()
    } else {
        actor.clone()
    };
    let (kind, title, context) = match (kind_raw.as_str(), sub.as_str()) {
        ("teamMembershipChange", "addedToTeam") => (
            "addedToTeam",
            if is_app || actor.is_empty() {
                format!("A team owner added you to {topic}")
            } else {
                format!("{who} added you to {topic}")
            },
            String::new(),
        ),
        ("reactionInChat" | "reaction", _) => (
            "reaction",
            format!("{who} reacted to your message"),
            in_where(&thread_type, &topic),
        ),
        ("mention" | "mentionInChat", _) => (
            "mention",
            format!("{who} mentioned you"),
            in_where(&thread_type, &topic),
        ),
        ("reply" | "replyToReply", _) => (
            "reply",
            format!("{who} replied to your message"),
            in_where(&thread_type, &topic),
        ),
        ("call", "missedCall") => (
            "missedCall",
            format!("Missed call from {who}"),
            "Teams call".into(),
        ),
        ("call", "voicemail") => ("voicemail", format!("Voicemail from {who}"), String::new()),
        _ => {
            let k = if kind_raw.is_empty() {
                "activity"
            } else {
                kind_raw.as_str()
            };
            (
                k,
                format!("{who}: {}", if sub.is_empty() { k } else { sub.as_str() }),
                String::new(),
            )
        }
    };
    // `isread` is a JSON boolean until the item is opened, then "true".
    let unread = match props.get("isread") {
        Some(serde_json::Value::Bool(b)) => !b,
        Some(serde_json::Value::String(r)) => r.eq_ignore_ascii_case("false"),
        _ => false,
    };
    let time = {
        let t = s("activityTimestamp");
        if t.is_empty() {
            m.get("composetime")
                .and_then(|t| t.as_str())
                .unwrap_or_default()
                .to_string()
        } else {
            t
        }
    };
    Some(ActivityItem {
        id: m
            .get("id")
            .and_then(|i| i.as_str())
            .unwrap_or_default()
            .to_string(),
        kind: kind.to_string(),
        title,
        preview: s("messagePreview"),
        context,
        time,
        unread,
        actor_mri,
        actor_name: actor,
        thread_id: s("sourceThreadId"),
        message_id: s("sourceMessageId"),
        emoji: if kind == "reaction" {
            super::messages::reaction_emoji(&sub).to_string()
        } else {
            String::new()
        },
    })
}

/// "In chat with you" for chats, the channel or team name otherwise.
fn in_where(thread_type: &str, topic: &str) -> String {
    match thread_type {
        "chat" => "In chat with you".into(),
        _ if !topic.is_empty() => topic.to_string(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(id: &str, activity: serde_json::Value, read: bool) -> serde_json::Value {
        serde_json::json!({
            "id": id,
            "properties": {
                "activity": activity.to_string(),
                "isread": read
            }
        })
    }

    #[test]
    fn words_items_like_teams() {
        let feed = serde_json::json!({ "messages": [
            msg("1", serde_json::json!({"activityType":"call","activitySubtype":"missedCall",
                "activityTimestamp":"2026-11-05T04:42:03Z","sourceUserId":"8:orgid:a",
                "sourceUserImDisplayName":"Randy Northrup"}), true),
            msg("2", serde_json::json!({"activityType":"reactionInChat","activitySubtype":"like",
                "activityTimestamp":"2026-11-05T06:09:29Z","messagePreview":"OST test 5",
                "sourceThreadType":"chat","sourceThreadId":"19:x@unq.gbl.spaces",
                "sourceMessageId":"17","sourceUserId":"8:orgid:a",
                "sourceUserImDisplayName":"Randy Northrup"}), false),
            msg("3", serde_json::json!({"activityType":"teamMembershipChange","activitySubtype":"addedToTeam",
                "activityTimestamp":"2026-11-05T06:54:31Z","sourceThreadTopic":"Secure Coast",
                "sourceUserId":"28:app:x"}), false),
        ]});
        let items = parse_feed(&feed.to_string());
        let titles: Vec<_> = items.iter().map(|i| i.title.as_str()).collect();
        assert_eq!(
            titles,
            [
                "A team owner added you to Secure Coast",
                "Randy Northrup reacted to your message",
                "Missed call from Randy Northrup",
            ]
        );
        assert!(items[0].unread && items[1].unread && !items[2].unread);
        assert_eq!(items[1].context, "In chat with you");
        assert_eq!(items[1].thread_id, "19:x@unq.gbl.spaces");
        assert_eq!(items[2].context, "Teams call");
        assert!(parse_feed("not json").is_empty());
    }
}
