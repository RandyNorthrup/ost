//! Teams' suggested replies (Cortana's "smart replies"): the service writes
//! them to the conversation's `quickReplyAugmentation` property as
//! `{suggestedActivities: [{id, timestamp, replyToId, suggestedActions:
//! {actions: [{type, title, value, channelData: {type, utcTime,
//! targetMessageId}}]}}]}` (read from OST Test 2's 1:1, 2026-11-13).
//! Teams (142420 `q`/`oe`) shows the newest set with a "reply" suggestion,
//! only for its target message, which must be the newest message.

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;

use super::client::TeamsClient;

/// One suggested reply.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Suggestion {
    pub title: String,
    pub value: String,
    /// "reply", "file_sharing", …
    pub kind: String,
    /// When the service made it (ISO), against the target's edit time.
    pub time: String,
}

/// The suggestions for one message.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SuggestionSet {
    pub target: String,
    pub timestamp: String,
    pub replies: Vec<Suggestion>,
}

fn s(v: &Value, k: &str) -> String {
    v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string()
}

/// The newest set that has a reply suggestion, from the property's text.
pub fn parse(prop: &str) -> Option<SuggestionSet> {
    let v: Value = serde_json::from_str(prop).ok()?;
    let sets = v.get("suggestedActivities").and_then(|a| a.as_array())?;
    sets.iter()
        .filter_map(|a| {
            let actions = a.pointer("/suggestedActions/actions")?.as_array()?;
            let replies: Vec<Suggestion> = actions
                .iter()
                .filter(|x| x.pointer("/channelData/utcTime").and_then(|t| t.as_str()).is_some())
                .map(|x| Suggestion {
                    title: Some(s(x, "title")).filter(|t| !t.is_empty()).unwrap_or_else(|| s(x, "value")),
                    value: Some(s(x, "value")).filter(|t| !t.is_empty()).unwrap_or_else(|| s(x, "title")),
                    kind: x.pointer("/channelData/type").and_then(|t| t.as_str()).unwrap_or("reply").to_string(),
                    time: x.pointer("/channelData/utcTime").and_then(|t| t.as_str()).unwrap_or_default().to_string(),
                })
                .collect();
            let target = actions
                .iter()
                .find_map(|x| x.pointer("/channelData/targetMessageId").and_then(|t| t.as_str()))
                .map(str::to_string)
                .unwrap_or_else(|| s(a, "replyToId"));
            replies.iter().any(|r| r.kind == "reply").then(|| SuggestionSet { target, timestamp: s(a, "timestamp"), replies })
        })
        .max_by(|a, b| a.timestamp.cmp(&b.timestamp))
}

/// The open chat's suggestions (None when the service has none).
pub async fn for_chat(client: &TeamsClient, chat_id: &str) -> Result<Option<SuggestionSet>> {
    let url = format!("{}/v1/users/ME/conversations/{}", client.chat_service_url(), chat_id);
    let v: Value = client.chat_get(&url).await?.json().await?;
    Ok(v.pointer("/properties/quickReplyAugmentation").and_then(|p| p.as_str()).and_then(parse))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_cortanas_suggestions() {
        // OST TEST 128's suggestions as the service wrote them.
        let prop = r#"{"suggestedActivities":[{"type":"suggestion","id":"Z.1","timestamp":"2026-11-14T02:51:30.8800727+00:00","from":{"id":"28:30005246-e706-444f-ba61-8647ef09db75","name":"Cortana"},"suggestedActions":{"actions":[{"type":"imBack","title":"Yes, I can do that","value":"Yes, I can do that","channelData":{"type":"reply","id":"0","utcTime":"2026-11-14T02:51:30.8800727Z","targetMessageId":"1794624690608"}},{"type":"imBack","title":"Yes","value":"Yes","channelData":{"type":"reply","id":"0","utcTime":"2026-11-14T02:51:30.8800727Z","targetMessageId":"1794624690608"}},{"type":"custom","title":"Share file","text":"","value":"0","channelData":{"type":"file_sharing","id":"0","utcTime":"2026-11-14T02:51:30.8800727Z","targetMessageId":"1794624690608"}}]},"replyToId":"1794624690608"}]}"#;
        let set = parse(prop).unwrap();
        assert_eq!(set.target, "1794624690608");
        assert_eq!(set.replies.iter().map(|r| (r.title.as_str(), r.kind.as_str())).collect::<Vec<_>>(),
            vec![("Yes, I can do that", "reply"), ("Yes", "reply"), ("Share file", "file_sharing")]);
        assert!(parse("{}").is_none());
        assert!(parse("nope").is_none());
    }
}
