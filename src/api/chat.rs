//! Native Teams chat API (chatsvcagg / chat service)
//!
//! Uses the Skype token with `Authentication: skypetoken={token}` header,
//! bypassing Graph API which requires tenant admin consent for Chat.Read.

use anyhow::{Context, Result};
use serde::Deserialize;

use super::client::TeamsClient;

// -- Response types for the native chat API --

#[derive(Debug, Deserialize)]
struct ConversationsResponse {
    conversations: Option<Vec<Conversation>>,
}

#[derive(Debug, Deserialize)]
struct Conversation {
    id: Option<String>,
    #[serde(rename = "threadProperties")]
    thread_properties: Option<ThreadProperties>,
    #[serde(rename = "lastMessage")]
    last_message: Option<NativeMessage>,
}

#[derive(Debug, Deserialize)]
struct ThreadProperties {
    topic: Option<String>,
    #[serde(rename = "lastjoinat")]
    last_join_at: Option<String>,
    /// For 1:1 chats, contains member MRIs
    members: Option<String>,
}

#[derive(Debug, Deserialize)]
struct NativeMessage {
    id: Option<String>,
    #[serde(rename = "composetime")]
    compose_time: Option<String>,
    #[serde(rename = "originalarrivaltime")]
    original_arrival_time: Option<String>,
    #[serde(rename = "imdisplayname")]
    im_display_name: Option<String>,
    content: Option<String>,
    messagetype: Option<String>,
    from: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MessagesResponse {
    messages: Option<Vec<NativeMessage>>,
}

/// Who sent a message: its `imdisplayname`, else the signed-in user's own
/// name when the sender is them, else "Unknown".
fn sender_name(msg: &NativeMessage, own_oid: Option<&str>, own_name: Option<&str>) -> String {
    if let Some(name) = msg
        .im_display_name
        .as_deref()
        .filter(|n| !n.trim().is_empty())
    {
        return name.to_string();
    }
    let is_own = match (msg.from.as_deref(), own_oid) {
        (Some(from), Some(oid)) => from.ends_with(&format!("8:orgid:{oid}")),
        _ => false,
    };
    match (is_own, own_name) {
        (true, Some(name)) => name.to_string(),
        (true, None) => "You".to_string(),
        _ => "Unknown".to_string(),
    }
}

/// Strip HTML tags from message content and decode the common entities.
/// `&amp;` is decoded last so `&amp;lt;` stays the text `&lt;`.
pub fn strip_html(html: &str) -> String {
    let mut result = String::with_capacity(html.len());
    let mut in_tag = false;
    for ch in html.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => result.push(ch),
            _ => {}
        }
    }
    result
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
}

/// Display name for a conversation.
fn conversation_name(conv: &Conversation) -> String {
    if let Some(ref props) = conv.thread_properties {
        if let Some(ref topic) = props.topic {
            if !topic.is_empty() {
                return topic.clone();
            }
        }
    }
    // Fall back to last message sender or the thread ID
    if let Some(ref msg) = conv.last_message {
        if let Some(ref name) = msg.im_display_name {
            if !name.is_empty() {
                return name.clone();
            }
        }
    }
    conv.id.as_deref().unwrap_or("[unknown]").to_string()
}

fn has_topic(conv: &Conversation) -> bool {
    conv.thread_properties
        .as_ref()
        .and_then(|p| p.topic.as_deref())
        .is_some_and(|t| !t.is_empty())
}

/// The other participant of a 1:1 chat, from its id
/// `19:<oid>_<oid>@unq.gbl.spaces`. None if the id is not that shape or
/// does not include `me`.
fn other_member_oid(chat_id: &str, me: &str) -> Option<String> {
    let inner = chat_id
        .strip_prefix("19:")?
        .strip_suffix("@unq.gbl.spaces")?;
    let (a, b) = inner.split_once('_')?;
    let valid = |s: &str| s.len() == 36 && s.chars().all(|c| c == '-' || c.is_ascii_hexdigit());
    if !valid(a) || !valid(b) {
        return None;
    }
    if a.eq_ignore_ascii_case(me) {
        Some(b.to_string())
    } else if b.eq_ignore_ascii_case(me) {
        Some(a.to_string())
    } else {
        None
    }
}

/// Look up a user's display name in Graph, once per oid per listing.
async fn resolve_user_name(
    client: &TeamsClient,
    oid: &str,
    cache: &mut std::collections::HashMap<String, Option<String>>,
) -> Option<String> {
    if let Some(hit) = cache.get(oid) {
        return hit.clone();
    }
    #[derive(Deserialize)]
    struct User {
        #[serde(rename = "displayName")]
        display_name: Option<String>,
    }
    let name = match client
        .graph_get(&format!("/users/{oid}?$select=displayName"))
        .await
    {
        Ok(resp) => resp.json::<User>().await.ok().and_then(|u| u.display_name),
        Err(e) => {
            tracing::debug!("Could not resolve user {oid}: {e:#}");
            None
        }
    };
    cache.insert(oid.to_string(), name.clone());
    name
}

/// List recent chats using the native Teams API (prints to stdout).
pub async fn list_chats(limit: usize) -> Result<()> {
    let client = TeamsClient::new().await?;
    let chats = list_chats_data(&client, limit).await?;

    println!("\nRecent Chats:");
    println!("{:-<60}", "");

    if chats.is_empty() {
        println!("  (no chats found)");
        return Ok(());
    }

    for chat in &chats {
        println!("{}", chat.name);
        println!("  ID: {}", chat.id);

        if let Some(ref time) = chat.last_message_time {
            println!("  Last: {}", time);
        }
        if let Some(ref preview) = chat.last_message_preview {
            if !preview.trim().is_empty() {
                let sender = chat.last_message_sender.as_deref().unwrap_or("?");
                println!("  [{}]: {}", sender, preview.trim());
            }
        }

        println!();
    }

    Ok(())
}

/// Read messages from a specific chat thread (prints to stdout).
pub async fn read_messages(chat_id: &str, limit: usize) -> Result<()> {
    let client = TeamsClient::new().await?;
    let msgs = read_messages_data(&client, chat_id, limit).await?;

    if msgs.is_empty() {
        println!("(no messages)");
        return Ok(());
    }

    for msg in &msgs {
        println!("[{}] {}: {}", msg.timestamp, msg.sender, msg.content);
    }

    Ok(())
}

/// Send a message to a chat thread using the native API.
pub async fn send_message(chat_id: &str, message: &str) -> Result<()> {
    let client = TeamsClient::new().await?;
    send_message_with_client(&client, chat_id, message).await?;
    println!("Message sent.");
    Ok(())
}

/// HTML-escape text for embedding in Teams RichText/Html messages.
fn html_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

/// Send a message using an existing client (shared helper).
pub async fn send_message_with_client(
    client: &TeamsClient,
    chat_id: &str,
    message: &str,
) -> Result<()> {
    let base = client.chat_service_url();
    let url = format!("{}/v1/users/ME/conversations/{}/messages", base, chat_id);

    let escaped = html_escape(message);
    let mut body = serde_json::json!({
        "content": format!("<p>{}</p>", escaped),
        "messagetype": "RichText/Html",
        "contenttype": "text"
    });
    // Teams clients send the sender's display name with every message; the
    // service stores it as-is, and clients that do not look the sender up
    // themselves show a blank name without it.
    if let Some(name) = client.display_name() {
        body["imdisplayname"] = serde_json::Value::String(name);
    }

    tracing::debug!("Sending message to {}", url);
    client.chat_post(&url, &body).await?;
    Ok(())
}

/// Tell the chat's other members you are typing (Teams clients send this
/// every few seconds while the compose box changes).
pub async fn send_typing(client: &TeamsClient, chat_id: &str) -> Result<()> {
    let base = client.chat_service_url();
    let url = format!("{}/v1/users/ME/conversations/{}/messages", base, chat_id);
    let mut body = serde_json::json!({
        "content": "",
        "messagetype": "Control/Typing",
        "contenttype": "text",
    });
    if let Some(name) = client.display_name() {
        body["imdisplayname"] = serde_json::Value::String(name);
    }
    client.chat_post(&url, &body).await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Data-returning API functions for TUI integration
// ---------------------------------------------------------------------------

/// Chat metadata for TUI display.
#[allow(dead_code)]
pub struct ChatInfo {
    pub id: String,
    pub name: String,
    pub is_group: bool,
    pub last_message_time: Option<String>,
    pub last_message_sender: Option<String>,
    pub last_message_preview: Option<String>,
}

/// A single message for TUI display.
pub struct MessageInfo {
    pub sender: String,
    pub timestamp: String,
    pub content: String,
}

/// List recent chats and return structured data.
pub async fn list_chats_data(client: &TeamsClient, limit: usize) -> Result<Vec<ChatInfo>> {
    // Strategy 1: CSA AFD endpoint with Bearer auth
    let csa_url = format!(
        "https://teams.microsoft.com/api/csa/api/v1/teams/users/ME/conversations?view=mychats&pageSize={}",
        limit
    );
    tracing::debug!("Trying CSA endpoint: {}", csa_url);
    let resp = match client.csa_get(&csa_url).await {
        Ok(r) => r,
        Err(e) => {
            tracing::debug!("CSA endpoint failed: {:#}, trying chatsvcagg", e);
            // Strategy 2: chatsvcagg with skypetoken auth
            let base = client.chatsvcagg_url();
            let url = format!(
                "{}/api/v2/users/ME/conversations?view=mychats&pageSize={}",
                base, limit
            );
            tracing::debug!("Trying chatsvcagg: {}", url);
            match client.chat_get(&url).await {
                Ok(r) => r,
                Err(e2) => {
                    tracing::debug!("chatsvcagg failed: {:#}, trying chat service", e2);
                    // Strategy 3: chat service (amer.ng.msg) with skypetoken auth
                    let base = client.chat_service_url();
                    let url = format!(
                        "{}/v1/users/ME/conversations?view=mychats&pageSize={}",
                        base, limit
                    );
                    client.chat_get(&url).await?
                }
            }
        }
    };

    let body: ConversationsResponse = resp
        .json()
        .await
        .context("Failed to parse conversations response")?;

    let conversations = body.conversations.unwrap_or_default();

    let own_oid = client.object_id();
    let mut names: std::collections::HashMap<String, Option<String>> = Default::default();
    let mut chats = Vec::new();
    for conv in &conversations {
        let id = conv.id.as_deref().unwrap_or("").to_string();
        if id.is_empty() {
            continue;
        }

        let is_group = id.contains("thread") || id.contains("meeting");
        let mut name = conversation_name(conv);
        // A 1:1 chat has no topic, and its last sender may be the signed-in
        // user; name it after the other person instead.
        if !is_group && !has_topic(conv) {
            if let Some(other) = own_oid.as_deref().and_then(|me| other_member_oid(&id, me)) {
                if let Some(display) = resolve_user_name(client, &other, &mut names).await {
                    name = display;
                }
            }
        }

        let (last_time, last_sender, last_preview) = if let Some(ref msg) = conv.last_message {
            let time = msg
                .original_arrival_time
                .as_deref()
                .or(msg.compose_time.as_deref())
                .map(String::from);
            let sender = msg.im_display_name.clone();
            let preview = msg.content.as_deref().map(|c| {
                let text = strip_html(c);
                if text.len() > 80 {
                    let end = text
                        .char_indices()
                        .map(|(i, _)| i)
                        .take_while(|&i| i <= 77)
                        .last()
                        .unwrap_or(0);
                    format!("{}...", &text[..end])
                } else {
                    text
                }
            });
            (time, sender, preview)
        } else {
            (None, None, None)
        };

        chats.push(ChatInfo {
            id,
            name,
            is_group,
            last_message_time: last_time,
            last_message_sender: last_sender,
            last_message_preview: last_preview,
        });
    }

    Ok(chats)
}

/// Read messages from a specific chat thread and return structured data.
pub async fn read_messages_data(
    client: &TeamsClient,
    chat_id: &str,
    limit: usize,
) -> Result<Vec<MessageInfo>> {
    let base = client.chat_service_url();
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages?pageSize={}",
        base, chat_id, limit
    );

    tracing::debug!("Reading messages from {}", url);
    let resp = client.chat_get(&url).await?;
    let body: MessagesResponse = resp
        .json()
        .await
        .context("Failed to parse messages response")?;

    let messages = body.messages.unwrap_or_default();

    // Messages come newest-first; reverse for chronological display
    let mut msgs: Vec<&NativeMessage> = messages.iter().collect();
    msgs.reverse();

    let own_oid = client.object_id();
    let own_name = client.display_name();
    let mut result = Vec::new();
    for msg in &msgs {
        let msgtype = msg.messagetype.as_deref().unwrap_or("");
        // Skip non-text messages (e.g. ThreadActivity/*)
        if !msgtype.contains("Text") && !msgtype.contains("RichText") {
            continue;
        }

        let sender = sender_name(msg, own_oid.as_deref(), own_name.as_deref());
        let time = msg
            .original_arrival_time
            .as_deref()
            .or(msg.compose_time.as_deref())
            .unwrap_or("")
            .to_string();
        let content = msg.content.as_deref().unwrap_or("");
        let text = strip_html(content);

        if text.trim().is_empty() {
            continue;
        }

        result.push(MessageInfo {
            sender,
            timestamp: time,
            content: text.trim().to_string(),
        });
    }

    Ok(result)
}

#[cfg(test)]
mod chat_name_tests {
    use super::other_member_oid;

    const ME: &str = "4287e791-1b98-4963-8b94-281c50472683";
    const THEM: &str = "5050c9d6-b8a7-41f2-830a-0c51777b7dc3";

    #[test]
    fn finds_the_other_member_in_either_position() {
        let id = format!("19:{ME}_{THEM}@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME).as_deref(), Some(THEM));
        let id = format!("19:{THEM}_{ME}@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME).as_deref(), Some(THEM));
    }

    #[test]
    fn rejects_other_shapes() {
        assert_eq!(other_member_oid("19:abc@thread.v2", ME), None);
        let id = format!("19:{THEM}_{THEM}@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME), None);
        let id = format!("19:{ME}_../users@unq.gbl.spaces");
        assert_eq!(other_member_oid(&id, ME), None);
    }
}

#[cfg(test)]
mod sender_name_tests {
    use super::*;

    fn msg(name: Option<&str>, from: Option<&str>) -> NativeMessage {
        NativeMessage {
            id: None,
            compose_time: None,
            original_arrival_time: None,
            im_display_name: name.map(String::from),
            content: None,
            messagetype: None,
            from: from.map(String::from),
        }
    }

    const OID: &str = "4287e791-1b98-4963-8b94-281c50472683";
    const OWN: &str =
        "https://amer.ng.msg.teams.microsoft.com/v1/users/ME/contacts/8:orgid:4287e791-1b98-4963-8b94-281c50472683";

    #[test]
    fn uses_the_name_the_message_carries() {
        assert_eq!(
            sender_name(&msg(Some("Randy Northrup"), None), Some(OID), None),
            "Randy Northrup"
        );
    }

    #[test]
    fn blank_name_on_own_message_shows_own_name() {
        assert_eq!(
            sender_name(&msg(Some(""), Some(OWN)), Some(OID), Some("OST Test 1")),
            "OST Test 1"
        );
        assert_eq!(sender_name(&msg(None, Some(OWN)), Some(OID), None), "You");
    }

    #[test]
    fn blank_name_from_someone_else_is_unknown() {
        let other = OWN.replace("4287e791", "00000000");
        assert_eq!(
            sender_name(&msg(Some(" "), Some(&other)), Some(OID), Some("OST Test 1")),
            "Unknown"
        );
    }
}

#[cfg(test)]
mod strip_html_tests {
    use super::strip_html;

    #[test]
    fn strips_tags_and_decodes_entities_once() {
        assert_eq!(strip_html("<p>Tom &amp; Jerry</p>"), "Tom & Jerry");
        assert_eq!(
            strip_html("<p>write &amp;lt;b&amp;gt;</p>"),
            "write &lt;b&gt;"
        );
        assert_eq!(strip_html("a&nbsp;&lt;b&gt;"), "a <b>");
    }
}
