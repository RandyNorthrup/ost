//! Bot invokes as Teams sends them (services-bots-platform `executeBotInvoke`
//! → chat service `postInvoke`, captured on winpc 2026-11-13 with the Polls
//! app): `POST {chat service}/v1/agents/{bot MRI}/invoke` with
//! `{name, appId?, text, messageType, value, imdisplayname, userAadToken,
//! serverMessageId, clientMessageId, conversation: {id}}`.
//! - A card's `Action.Submit` whose data says `msteams.type: "invoke"`: no
//!   name; the value is the action's data without `msteams`, plus the card's
//!   inputs. The reply is empty; Teams shows "Your response was sent to the
//!   app" and the bot edits its message.
//! - `Action.Execute` (Universal Actions) and a card's `refresh`: name
//!   `adaptiveCard/action`, value `{action: {type, verb, data, id?, title?},
//!   trigger}`; an automatic refresh adds `X-MS-AutoRefreshRequestInThread:
//!   {thread}`. The reply carries the card to show, a message, or an error.
//! `userAadToken` is the middle tier's AAD token (Teams' MT_AAD_KEY).

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// The message whose card acts, and its bot.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Target {
    pub thread_id: String,
    pub server_message_id: String,
    #[serde(default)]
    pub client_message_id: String,
    pub bot_mri: String,
    #[serde(default)]
    pub app_id: String,
    #[serde(default)]
    pub message_type: String,
}

/// Teams' invoke body (925701 `jt`).
pub fn body(t: &Target, name: Option<&str>, value: &Value, display_name: &str, aad_token: &str) -> Value {
    let mut b = json!({
        "name": name,
        "messageType": if t.message_type.is_empty() { "RichText/Media_Card" } else { &t.message_type },
        "value": value,
        "imdisplayname": display_name,
        "userAadToken": aad_token,
        "serverMessageId": t.server_message_id,
        "clientMessageId": if t.client_message_id.is_empty() { Value::Null } else { json!(t.client_message_id) },
        "conversation": { "id": t.thread_id },
    });
    if !t.app_id.is_empty() {
        b["appId"] = json!(t.app_id);
    }
    // Teams drops nulls (JSON.stringify with a replacer that keeps them out).
    if let Some(o) = b.as_object_mut() {
        o.retain(|_, v| !v.is_null());
    }
    b
}

/// An `Action.Submit`'s invoke value: its data without `msteams`, then the
/// card's inputs (Teams merges them over the data).
pub fn submit_value(data: &Value, inputs: &Value) -> Value {
    let mut v = match data {
        Value::Object(o) => {
            let mut o = o.clone();
            o.remove("msteams");
            Value::Object(o)
        }
        Value::Null => json!({}),
        other => json!({ "data": other }),
    };
    if let (Some(o), Some(i)) = (v.as_object_mut(), inputs.as_object()) {
        for (k, val) in i {
            o.insert(k.clone(), val.clone());
        }
    }
    v
}

/// An `Action.Execute`'s (or refresh's) invoke value.
pub fn execute_value(action: &Value, inputs: &Value, automatic: bool) -> Value {
    let mut data = action.get("data").cloned().unwrap_or_else(|| json!({}));
    if let (Some(o), Some(i)) = (data.as_object_mut(), inputs.as_object()) {
        for (k, val) in i {
            o.insert(k.clone(), val.clone());
        }
    }
    let mut a = json!({ "type": "Action.Execute", "verb": action.get("verb").cloned().unwrap_or(Value::Null), "data": data });
    for k in ["id", "title"] {
        if let Some(v) = action.get(k).filter(|v| !v.is_null()) {
            a[k] = v.clone();
        }
    }
    json!({ "action": a, "trigger": if automatic { "automatic" } else { "manual" } })
}

/// Whether a card's `Action.Submit` goes to its bot as an invoke.
pub fn is_invoke_submit(data: &Value) -> bool {
    data.pointer("/msteams/type").and_then(|v| v.as_str()) == Some("invoke")
}

/// Send an invoke; the bot's reply (Null when empty).
pub async fn invoke(client: &TeamsClient, t: &Target, name: Option<&str>, value: Value, automatic: bool) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await.unwrap_or_default();
    let display = client.display_name().unwrap_or_default();
    let url = format!("{}/v1/agents/{}/invoke", client.chat_service_url(), t.bot_mri);
    let b = body(t, name, &value, &display, &token);
    let mut headers = vec![("content-type", "application/json")];
    if automatic {
        headers.push(("X-MS-AutoRefreshRequestInThread", t.thread_id.as_str()));
    }
    let resp = client.chat_request_with(reqwest::Method::POST, &url, &b, &headers).await.context("The app didn't answer")?;
    let text = resp.text().await.unwrap_or_default();
    Ok(serde_json::from_str(&text).unwrap_or(Value::Null))
}

/// What a bot's reply asks Teams to show.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// Nothing: Teams says "Your response was sent to the app".
    Sent,
    /// A card to show in place of the message's (Universal Actions).
    Card(Value),
    /// A message for the footer.
    Message(String),
    /// An error for the footer.
    Error(String),
}

impl Outcome {
    pub fn kind(&self) -> &'static str {
        match self {
            Outcome::Sent => "sent",
            Outcome::Card(_) => "card",
            Outcome::Message(_) => "message",
            Outcome::Error(_) => "error",
        }
    }
}

/// Read a bot's invoke reply (`{statusCode, type, value}`, possibly under
/// `body`).
pub fn outcome(reply: &Value) -> Outcome {
    let r = reply.get("body").filter(|b| b.is_object()).unwrap_or(reply);
    let kind = r.get("type").and_then(|v| v.as_str()).unwrap_or_default();
    let value = r.get("value").cloned().unwrap_or(Value::Null);
    match kind {
        "application/vnd.microsoft.card.adaptive" => {
            let card = if let Value::String(s) = &value { serde_json::from_str(s).unwrap_or(Value::Null) } else { value };
            if card.is_object() { Outcome::Card(card) } else { Outcome::Sent }
        }
        "application/vnd.microsoft.activity.message" => Outcome::Message(value.as_str().unwrap_or_default().to_string()),
        "application/vnd.microsoft.error" | "application/vnd.microsoft.error.preconditionFailed" => Outcome::Error(
            value.get("message").and_then(|m| m.as_str()).unwrap_or("Something went wrong. Please try again.").to_string(),
        ),
        _ => Outcome::Sent,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn polls_vote_is_teams_body() {
        // The vote Teams sent (OST TEST 126, 2026-11-13).
        let t = Target {
            thread_id: "19:a@thread.v2".into(),
            server_message_id: "1794621026819".into(),
            client_message_id: "13086358480879058679".into(),
            bot_mri: "28:fd931076-bbfb-4a38-a85c-1f0fb5b61bee".into(),
            app_id: "0e3bedea-4720-48b5-9e13-5a1ce1387d45".into(),
            message_type: "RichText/Media_Card".into(),
        };
        let data = json!({ "msteams": { "type": "invoke", "title": null, "value": null }, "data": { "Type": "QuickPoll.SubmitVote", "Options": ["Red", "Blue"], "FormId": "F", "QuestionId": "Q" } });
        assert!(is_invoke_submit(&data));
        let v = submit_value(&data, &json!({ "choice": "1" }));
        assert_eq!(v, json!({ "data": { "Type": "QuickPoll.SubmitVote", "Options": ["Red", "Blue"], "FormId": "F", "QuestionId": "Q" }, "choice": "1" }));
        let b = body(&t, None, &v, "OST Test 1", "tok");
        assert_eq!(b, json!({
            "appId": "0e3bedea-4720-48b5-9e13-5a1ce1387d45", "messageType": "RichText/Media_Card", "value": v,
            "imdisplayname": "OST Test 1", "userAadToken": "tok", "serverMessageId": "1794621026819",
            "clientMessageId": "13086358480879058679", "conversation": { "id": "19:a@thread.v2" }
        }));
    }

    #[test]
    fn refreshes_and_replies_read_as_teams() {
        let action = json!({ "verb": "fetchAuthorVoteCard", "data": { "FormId": "F", "QuestionId": null }, "title": "Refresh", "type": "Action.Execute" });
        assert_eq!(execute_value(&action, &json!({}), true),
            json!({ "action": { "type": "Action.Execute", "verb": "fetchAuthorVoteCard", "data": { "FormId": "F", "QuestionId": null }, "title": "Refresh" }, "trigger": "automatic" }));
        let card = json!({ "type": "AdaptiveCard", "body": [] });
        assert_eq!(outcome(&json!({ "statusCode": 200, "type": "application/vnd.microsoft.card.adaptive", "value": card })), Outcome::Card(card));
        assert_eq!(outcome(&json!({ "statusCode": 200, "type": "application/vnd.microsoft.activity.message", "value": "Thanks" })), Outcome::Message("Thanks".into()));
        assert_eq!(outcome(&json!({ "statusCode": 400, "type": "application/vnd.microsoft.error", "value": { "code": "x", "message": "Nope" } })), Outcome::Error("Nope".into()));
        assert_eq!(outcome(&Value::Null), Outcome::Sent);
    }
}
