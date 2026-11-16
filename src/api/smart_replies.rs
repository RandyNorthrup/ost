//! Teams' suggested replies (Cortana's "smart replies"): the service writes
//! them to the conversation's `quickReplyAugmentation` property as
//! `{suggestedActivities: [{id, timestamp, replyToId, suggestedActions:
//! {actions: [{type, title, value, channelData: {type, utcTime,
//! targetMessageId, startTime?, endTime?}}]}}]}` (read from OST Test 2's
//! 1:1, 2026-11-13).
//! - **Which set** (701487 `Li`): the newest that has a suggestion Teams
//!   shows: a reply, or (when their features are on) a file to share, a
//!   meeting to schedule or a workflow.
//! - **The kinds**: `reply` (text chips), `file_sharing` ("Share a file"),
//!   `meeting` (a chip that opens the scheduling form for its
//!   `startTime`/`endTime`) and `workflow` (its value is JSON:
//!   `{recommendedToolName, prefilledInputs, toolExecutorName}`).
//! - **Features** (ECS, Teams' commercial defaults in config-prod):
//!   `messaging.enableSmartFilesSuggestions` (on),
//!   `messaging.enableSmartSchedulingSuggestions` (off) and
//!   `extensibility.enableProactiveSuggestionPrompt` (off, workflows);
//!   `messaging.enableSmartRepliesFeedback` (on) shows the feedback button.
//!
//! Which message a set is for, and when each chip shows, is decided where
//! the messages are (the conversation view), as Teams' `E6`/`Zw` do.

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;

use super::client::TeamsClient;

/// One suggestion.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Suggestion {
    pub title: String,
    pub value: String,
    /// "reply", "file_sharing", "meeting", "workflow", …
    pub kind: String,
    /// When the service made it (ISO), against the target's edit time.
    pub time: String,
    /// The message it answers.
    pub target: String,
    /// A meeting suggestion's proposed times (ISO), when it has them.
    pub start_time: String,
    pub end_time: String,
}

/// The suggestions for one message.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SuggestionSet {
    pub target: String,
    pub timestamp: String,
    pub replies: Vec<Suggestion>,
    /// Teams shows its feedback button with these suggestions.
    pub feedback: bool,
}

/// The features that decide which suggestions Teams shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Features {
    pub files: bool,
    pub meetings: bool,
    pub workflows: bool,
    pub feedback: bool,
}

impl Default for Features {
    /// Teams' commercial defaults.
    fn default() -> Self {
        Features { files: true, meetings: false, workflows: false, feedback: true }
    }
}

impl Features {
    /// The account's features: ECS, else Teams' defaults.
    pub fn current() -> Self {
        let d = Features::default();
        let flag = |ns: &str, k: &str, def: bool| super::ecs::setting(ns, k).and_then(|v| v.as_bool()).unwrap_or(def);
        Features {
            files: flag("messaging", "enableSmartFilesSuggestions", d.files),
            meetings: flag("messaging", "enableSmartSchedulingSuggestions", d.meetings),
            workflows: flag("extensibility", "enableProactiveSuggestionPrompt", d.workflows),
            feedback: flag("messaging", "enableSmartRepliesFeedback", d.feedback),
        }
    }

    /// Whether Teams shows a suggestion of this kind.
    pub fn shows(&self, kind: &str) -> bool {
        match kind {
            "reply" => true,
            "file_sharing" => self.files,
            "meeting" => self.meetings,
            "workflow" => self.workflows,
            _ => false,
        }
    }
}

fn s(v: &Value, k: &str) -> String {
    v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string()
}

/// The newest set with a suggestion Teams shows, from the property's text,
/// keeping only the kinds it shows.
pub fn parse_with(prop: &str, f: Features) -> Option<SuggestionSet> {
    let v: Value = serde_json::from_str(prop).ok()?;
    let sets = v.get("suggestedActivities").and_then(|a| a.as_array())?;
    sets.iter()
        .filter_map(|a| {
            let actions = a.pointer("/suggestedActions/actions")?.as_array()?;
            let reply_to = s(a, "replyToId");
            let replies: Vec<Suggestion> = actions
                .iter()
                .filter(|x| x.pointer("/channelData/utcTime").and_then(|t| t.as_str()).is_some())
                .map(|x| {
                    let cd = |k: &str| x.pointer(&format!("/channelData/{k}")).and_then(|t| t.as_str()).unwrap_or_default().to_string();
                    let kind = Some(cd("type")).filter(|k| !k.is_empty()).unwrap_or_else(|| "reply".into());
                    Suggestion {
                        title: Some(s(x, "title")).filter(|t| !t.is_empty()).unwrap_or_else(|| s(x, "value")),
                        value: Some(s(x, "value")).filter(|t| !t.is_empty()).unwrap_or_else(|| s(x, "title")),
                        kind,
                        time: cd("utcTime"),
                        target: Some(cd("targetMessageId")).filter(|t| !t.is_empty()).unwrap_or_else(|| reply_to.clone()),
                        start_time: cd("startTime"),
                        end_time: cd("endTime"),
                    }
                })
                .filter(|r| f.shows(&r.kind))
                .collect();
            if replies.is_empty() {
                return None;
            }
            let target = replies.first().map(|r| r.target.clone()).unwrap_or(reply_to);
            Some(SuggestionSet { target, timestamp: s(a, "timestamp"), replies, feedback: f.feedback })
        })
        .max_by(|a, b| a.timestamp.cmp(&b.timestamp))
}

/// The newest set Teams shows with this account's features.
pub fn parse(prop: &str) -> Option<SuggestionSet> {
    parse_with(prop, Features::current())
}

/// The open chat's suggestions (None when the service has none).
pub async fn for_chat(client: &TeamsClient, chat_id: &str) -> Result<Option<SuggestionSet>> {
    let url = format!("{}/v1/users/ME/conversations/{}", client.chat_service_url(), chat_id);
    let v: Value = client.chat_get(&url).await?.json().await?;
    Ok(v.pointer("/properties/quickReplyAugmentation").and_then(|p| p.as_str()).and_then(parse))
}

/// The issue OST opens for Teams' suggested-reply feedback (Teams sends it
/// to Microsoft's OCV with `sendSmartRepliesOCVFeedback`): the categories
/// chosen, the comment, the suggestion kinds, and — only when "Attach my
/// last message" is checked — the suggestions and the message they were
/// for (Teams' `Zt` sends those only then too).
pub fn feedback_report(
    categories: &[String],
    comment: &str,
    kinds: &[String],
    attach: Option<(&[String], &str)>,
) -> crate::feedback::Report {
    let liked = !categories.is_empty()
        && categories.iter().all(|c| c.starts_with("They're great") || c.starts_with("The suggestion is great"));
    let mut context = String::from("How would you describe the suggestions we provided?\n");
    for c in categories {
        context.push_str(&format!("- {c}\n"));
    }
    let kinds: Vec<&str> = kinds.iter().map(|k| if k == "reply" { "text" } else { k.as_str() }).collect();
    context.push_str(&format!("\nSuggestion types: {}\n", kinds.join(", ")));
    if let Some((suggestions, last)) = attach {
        context.push_str(&format!("\nSuggestions: {}\n", suggestions.join(" | ")));
        // Teams strips the message's HTML tags.
        let plain = regex::Regex::new(r"</?[^>]+(>|$)").map(|re| re.replace_all(last, "").to_string()).unwrap_or_default();
        context.push_str(&format!("Last message: {}\n", plain.trim()));
    }
    let text = if comment.trim().is_empty() { categories.join("; ") } else { comment.trim().to_string() };
    crate::feedback::Report {
        kind: if liked { "compliment".into() } else { "problem".into() },
        text,
        area: "Suggested replies".into(),
        context,
        share_logs: false,
        contact: false,
        files: Vec::new(),
    }
}

/// Teams' feedback categories for these kinds of suggestions (79624 `Fs`),
/// in its order.
pub fn feedback_categories(kinds: &[String]) -> Vec<&'static str> {
    let has = |k: &str| kinds.iter().any(|x| x == k);
    let text = has("reply");
    if has("file_sharing") && text {
        vec!["They're great. Keep em' coming!", "They don't sound like me", "They're inappropriate or offensive", "They're not relevant to my chat", "I don't need to share a file", "Someone else should share the file", "I can't find the file I need"]
    } else if has("meeting") && text {
        vec!["They're great. Keep em' coming!", "They don't sound like me", "They're inappropriate or offensive", "They're not relevant to my chat", "I don't need to schedule a meeting", "Someone else should schedule the meeting", "These suggestions aren't helpful"]
    } else if text {
        vec!["They're great. Keep em' coming!", "They don't sound like me", "They're not relevant to my chat", "The choices are repetitive", "They're inappropriate or offensive", "I don’t like these suggestions"]
    } else if has("file_sharing") {
        vec!["The suggestion is great!", "I don't need to share a file", "Someone else should share the file", "I can't find the file I need", "I didn't get any file suggestions", "I'm not ready to share a file"]
    } else if has("meeting") {
        vec!["The suggestion is great!", "I don't need to schedule a meeting", "Someone else should schedule the meeting", "These suggestions aren't helpful", "I'm not ready to schedule a meeting"]
    } else {
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // OST TEST 128's suggestions as the service wrote them.
    const PROP: &str = r#"{"suggestedActivities":[{"type":"suggestion","id":"Z.1","timestamp":"2026-11-14T02:51:30.8800727+00:00","from":{"id":"28:30005246-e706-444f-ba61-8647ef09db75","name":"Cortana"},"suggestedActions":{"actions":[{"type":"imBack","title":"Yes, I can do that","value":"Yes, I can do that","channelData":{"type":"reply","id":"0","utcTime":"2026-11-14T02:51:30.8800727Z","targetMessageId":"1794624690608"}},{"type":"imBack","title":"Yes","value":"Yes","channelData":{"type":"reply","id":"0","utcTime":"2026-11-14T02:51:30.8800727Z","targetMessageId":"1794624690608"}},{"type":"custom","title":"Share file","text":"","value":"0","channelData":{"type":"file_sharing","id":"0","utcTime":"2026-11-14T02:51:30.8800727Z","targetMessageId":"1794624690608"}}]},"replyToId":"1794624690608"}]}"#;

    #[test]
    fn reads_cortanas_suggestions() {
        let set = parse_with(PROP, Features::default()).unwrap();
        assert_eq!(set.target, "1794624690608");
        assert_eq!(set.replies.iter().map(|r| (r.title.as_str(), r.kind.as_str())).collect::<Vec<_>>(),
            vec![("Yes, I can do that", "reply"), ("Yes", "reply"), ("Share file", "file_sharing")]);
        assert!(set.feedback);
        assert!(parse("{}").is_none());
        assert!(parse("nope").is_none());
        // With file suggestions off, only the replies.
        let off = parse_with(PROP, Features { files: false, ..Features::default() }).unwrap();
        assert_eq!(off.replies.len(), 2);
    }

    #[test]
    fn meeting_and_workflow_suggestions_follow_their_features() {
        let prop = r#"{"suggestedActivities":[{"timestamp":"2026-11-16T02:00:00Z","replyToId":"9","suggestedActions":{"actions":[
            {"type":"custom","title":"Schedule a meeting","value":"Schedule a meeting","channelData":{"type":"meeting","utcTime":"2026-11-16T02:00:00Z","targetMessageId":"9","startTime":"2026-11-17T22:00:00Z","endTime":"2026-11-17T22:30:00Z"}},
            {"type":"custom","value":"{\"recommendedToolName\":\"remind_me\",\"toolExecutorName\":\"OST Test 1\"}","channelData":{"type":"workflow","utcTime":"2026-11-16T02:00:00Z","targetMessageId":"9"}}]}}]}"#;
        // Teams' defaults: neither shows, so there is no set.
        assert!(parse_with(prop, Features::default()).is_none());
        let on = parse_with(prop, Features { meetings: true, workflows: true, ..Features::default() }).unwrap();
        assert_eq!(on.replies[0].kind, "meeting");
        assert_eq!((on.replies[0].start_time.as_str(), on.replies[0].end_time.as_str()), ("2026-11-17T22:00:00Z", "2026-11-17T22:30:00Z"));
        assert_eq!(on.replies[1].kind, "workflow");
        assert!(on.replies[1].value.contains("remind_me"));
    }

    #[test]
    fn feedback_goes_to_an_issue_without_chat_text_unless_attached() {
        let kinds = vec!["reply".to_string(), "file_sharing".to_string()];
        assert_eq!(feedback_categories(&kinds)[4], "I don't need to share a file");
        assert_eq!(feedback_categories(&["meeting".to_string()]).len(), 5);
        let r = feedback_report(&["They don't sound like me".into()], "", &kinds, None);
        assert_eq!((r.kind.as_str(), r.area.as_str(), r.text.as_str()), ("problem", "Suggested replies", "They don't sound like me"));
        assert!(r.context.contains("Suggestion types: text, file_sharing"));
        assert!(!r.context.contains("Last message"));
        let sugg = vec!["Yes".to_string()];
        let r = feedback_report(&["They're great. Keep em' coming!".into()], "Nice", &kinds, Some((&sugg, "<p>Can you do it?</p>")));
        assert_eq!(r.kind, "compliment");
        assert!(r.context.contains("Last message: Can you do it?"));
        assert!(r.context.contains("Suggestions: Yes"));
    }
}
