//! In-process hub for Trouter push events, so embedders (the desktop app)
//! receive them as data instead of only seeing them printed.
//!
//! Based on the event hub and data-frame decoding by @mrowlinson in
//! eisbaw/ost#10 and eisbaw/ost#89. This version uses a broadcast channel,
//! so each subscriber is woken per event instead of polling a queue.

use std::sync::OnceLock;

use tokio::sync::broadcast;

/// What a pushed event is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventKind {
    /// A chat-service event: new or edited message, conversation update.
    Chat,
    /// A call notification (incoming call, call state).
    Call,
}

/// One pushed event; `json` is the decoded event body.
#[derive(Debug, Clone)]
pub struct Event {
    pub kind: EventKind,
    pub json: String,
}

/// Events buffered per slow subscriber before the oldest are dropped.
const CAPACITY: usize = 1024;

fn sender() -> &'static broadcast::Sender<Event> {
    static TX: OnceLock<broadcast::Sender<Event>> = OnceLock::new();
    TX.get_or_init(|| broadcast::channel(CAPACITY).0)
}

/// Publish one event. Never blocks; with no subscribers it is dropped.
pub fn publish(kind: EventKind, json: String) {
    let _ = sender().send(Event { kind, json });
}

/// Receive every event published from now on.
pub fn subscribe() -> broadcast::Receiver<Event> {
    sender().subscribe()
}

/// The conversation ids a chat-service event changed. Handles a single
/// event or an `eventMessages` batch, and reads the id from
/// `resource.conversationLink` (`…/conversations/<id>`), `resourceLink`, or
/// `resource.id` for conversation updates.
pub fn conversation_ids(json: &str) -> Vec<String> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let events: Vec<&serde_json::Value> = match v.get("eventMessages").and_then(|e| e.as_array()) {
        Some(list) => list.iter().collect(),
        None => vec![&v],
    };
    let mut ids = Vec::new();
    for ev in events {
        let resource = ev.get("resource");
        // Typing indicators and other control messages change nothing shown.
        let is_control = resource
            .and_then(|r| r.get("messagetype"))
            .and_then(|t| t.as_str())
            .is_some_and(|t| t.starts_with("Control/"));
        if is_control {
            continue;
        }
        let from_link = |link: Option<&serde_json::Value>| {
            link.and_then(|l| l.as_str())
                .and_then(|l| l.split("/conversations/").nth(1))
                .map(|rest| rest.split('/').next().unwrap_or(rest).to_string())
        };
        let id = from_link(resource.and_then(|r| r.get("conversationLink")))
            .or_else(|| from_link(ev.get("resourceLink")))
            .or_else(|| {
                let is_conv = ev
                    .get("resourceType")
                    .and_then(|t| t.as_str())
                    .is_some_and(|t| t.eq_ignore_ascii_case("ConversationUpdate"));
                is_conv
                    .then(|| resource.and_then(|r| r.get("id")).and_then(|i| i.as_str()))
                    .flatten()
                    .map(str::to_string)
            });
        if let Some(id) =
            id.filter(|i| i.starts_with("19:") || i.starts_with("48:") || i.starts_with("8:"))
        {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    ids
}

/// A chat message pushed to us.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushedMessage {
    pub conversation_id: String,
    pub sender_name: String,
    /// Sender MRI, e.g. `8:orgid:<oid>`.
    pub sender_mri: String,
    /// Plain text of the message.
    pub text: String,
}

/// New user messages (text and rich text) in a chat-service event; typing
/// and other control messages, edits and system events are skipped.
pub fn message_events(json: &str) -> Vec<PushedMessage> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let events: Vec<&serde_json::Value> = match v.get("eventMessages").and_then(|e| e.as_array()) {
        Some(list) => list.iter().collect(),
        None => vec![&v],
    };
    events
        .into_iter()
        .filter_map(|ev| {
            if ev.get("resourceType")?.as_str()? != "NewMessage" {
                return None;
            }
            let r = ev.get("resource")?;
            let kind = r.get("messagetype")?.as_str()?;
            if !(kind == "Text" || kind.starts_with("RichText")) {
                return None;
            }
            if r.get("skypeeditedid").is_some() || r.get("deletetime").is_some() {
                return None;
            }
            let link = r
                .get("conversationLink")
                .or_else(|| ev.get("resourceLink"))?
                .as_str()?;
            let conversation_id = link
                .split("/conversations/")
                .nth(1)?
                .split('/')
                .next()?
                .to_string();
            let text = crate::api::strip_html(r.get("content")?.as_str()?)
                .trim()
                .to_string();
            let sender_mri = r
                .get("from")
                .and_then(|f| f.as_str())
                .and_then(|f| f.rsplit("/contacts/").next())
                .unwrap_or_default()
                .to_string();
            let sender_name = r
                .get("imdisplayname")
                .and_then(|n| n.as_str())
                .unwrap_or_default()
                .to_string();
            Some(PushedMessage {
                conversation_id,
                sender_name,
                sender_mri,
                text,
            })
        })
        .collect()
}

/// A typing change pushed for a chat.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Typing {
    pub conversation_id: String,
    /// The typist's display name, if the event carries it.
    pub sender_name: String,
    /// `Control/ClearTyping`: they stopped.
    pub stopped: bool,
}

/// Typing indicators in a chat-service event (`Control/Typing` and
/// `Control/ClearTyping` messages).
pub fn typing_events(json: &str) -> Vec<Typing> {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let events: Vec<&serde_json::Value> = match v.get("eventMessages").and_then(|e| e.as_array()) {
        Some(list) => list.iter().collect(),
        None => vec![&v],
    };
    events
        .into_iter()
        .filter_map(|ev| {
            let r = ev.get("resource")?;
            let kind = r.get("messagetype")?.as_str()?;
            let stopped = match kind {
                "Control/Typing" => false,
                "Control/ClearTyping" => true,
                _ => return None,
            };
            let link = r
                .get("conversationLink")
                .or_else(|| ev.get("resourceLink"))?
                .as_str()?;
            let conversation_id = link
                .split("/conversations/")
                .nth(1)?
                .split('/')
                .next()?
                .to_string();
            let sender_name = r
                .get("imdisplayname")
                .and_then(|n| n.as_str())
                .unwrap_or_default()
                .to_string();
            Some(Typing {
                conversation_id,
                sender_name,
                stopped,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subscribers_receive_published_events() {
        let mut rx = subscribe();
        publish(EventKind::Chat, "{\"a\":1}".into());
        let ev = rx.try_recv().unwrap();
        assert_eq!(ev.kind, EventKind::Chat);
        assert_eq!(ev.json, "{\"a\":1}");
    }

    #[test]
    fn conversation_ids_from_new_message_and_batches() {
        let one = r#"{"resourceType":"NewMessage","resourceLink":"https://amer.ng.msg.teams.microsoft.com/v1/users/ME/conversations/19:a_b@unq.gbl.spaces/messages/17","resource":{"conversationLink":"https://amer.ng.msg.teams.microsoft.com/v1/users/ME/conversations/19:a_b@unq.gbl.spaces","content":"hi"}}"#;
        assert_eq!(conversation_ids(one), vec!["19:a_b@unq.gbl.spaces"]);
        let batch = r#"{"eventMessages":[
            {"resourceType":"NewMessage","resourceLink":"https://x/v1/users/ME/conversations/19:c@thread.v2/messages/1"},
            {"resourceType":"ConversationUpdate","resource":{"id":"19:d@thread.v2"}},
            {"resourceType":"NewMessage","resourceLink":"https://x/v1/users/ME/conversations/19:c@thread.v2/messages/2"}]}"#;
        assert_eq!(
            conversation_ids(batch),
            vec!["19:c@thread.v2", "19:d@thread.v2"]
        );
    }

    #[test]
    fn conversation_ids_skips_typing_indicators() {
        let typing = r#"{"resourceType":"NewMessage","resourceLink":"https://x/v1/users/ME/conversations/19:a@thread.v2/messages/1","resource":{"messagetype":"Control/Typing","content":""}}"#;
        assert!(conversation_ids(typing).is_empty());
        let text = r#"{"resourceType":"NewMessage","resourceLink":"https://x/v1/users/ME/conversations/19:a@thread.v2/messages/2","resource":{"messagetype":"RichText/Html","content":"<p>hi</p>"}}"#;
        assert_eq!(conversation_ids(text), vec!["19:a@thread.v2"]);
    }

    #[test]
    fn message_events_extract_sender_and_text() {
        let m = r#"{"resourceType":"NewMessage","resource":{"messagetype":"RichText/Html","content":"<p>Hi &amp; bye</p>","imdisplayname":"Randy Northrup","from":"https://amer.ng.msg.teams.microsoft.com/v1/users/ME/contacts/8:orgid:abc","conversationLink":"https://x/v1/users/ME/conversations/19:a_b@unq.gbl.spaces"}}"#;
        let got = message_events(m);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].text, "Hi & bye");
        assert_eq!(got[0].sender_mri, "8:orgid:abc");
        assert_eq!(got[0].conversation_id, "19:a_b@unq.gbl.spaces");
        let typing = m.replace("RichText/Html", "Control/Typing");
        assert!(message_events(&typing).is_empty());
    }

    #[test]
    fn typing_events_start_and_stop() {
        let start = r#"{"resourceType":"NewMessage","resource":{"messagetype":"Control/Typing","imdisplayname":"Randy Northrup","conversationLink":"https://x/v1/users/ME/conversations/19:a_b@unq.gbl.spaces"}}"#;
        assert_eq!(
            typing_events(start),
            vec![Typing {
                conversation_id: "19:a_b@unq.gbl.spaces".into(),
                sender_name: "Randy Northrup".into(),
                stopped: false
            }]
        );
        let stop = start.replace("Control/Typing", "Control/ClearTyping");
        assert!(typing_events(&stop)[0].stopped);
        assert!(typing_events(r#"{"resource":{"messagetype":"RichText/Html"}}"#).is_empty());
    }

    #[test]
    fn conversation_ids_ignores_unrelated_payloads() {
        assert!(conversation_ids("not json").is_empty());
        assert!(
            conversation_ids(r#"{"resourceType":"UserPresence","resource":{"id":"x"}}"#).is_empty()
        );
    }
}
