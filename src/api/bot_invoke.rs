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
//! - A plain `Action.Submit` (no `msteams`), a submit whose data says
//!   `msteams.type: "messageBack"`, and a hero card's `messageBack` button
//!   are Teams' messageBack (adaptivecard-react `Ne` and the messageBack
//!   case; 455054 `UF` -> 730589 `SQ`): when the action has a `displayText`,
//!   that text is posted to the chat first as a `Text` message with
//!   `properties.skipfanouttobots` (Teams' BotMessageBack); then the invoke
//!   goes with name `messageback`, the action's `text`, and the value (the
//!   data and inputs, merged over `msteams.value`; a string value is sent
//!   as `{}`, as Teams' JSON.parse leaves it). The bot answers in the chat.
//!
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
pub fn body(
    t: &Target,
    name: Option<&str>,
    text: Option<&str>,
    value: &Value,
    display_name: &str,
    aad_token: &str,
) -> Value {
    let mut b = json!({
        "name": name,
        "text": text,
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

/// A messageBack as Teams makes it from a card action.
#[derive(Debug, Clone, PartialEq)]
pub struct MessageBack {
    /// The invoke's value (an object; `{}` for a string value).
    pub value: Value,
    pub text: Option<String>,
    /// Posted to the chat first (BotMessageBack) when not empty.
    pub display_text: Option<String>,
}

fn str_opt(v: Option<&Value>) -> Option<String> {
    v.and_then(|x| x.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// A JSON value as Teams sends it: an object stays, a string holding an
/// object is read, anything else is sent as {} (Teams' JSON.parse of a
/// non-object).
fn as_object(v: &Value) -> Value {
    match v {
        Value::Object(_) => v.clone(),
        Value::String(s) => serde_json::from_str::<Value>(s)
            .ok()
            .filter(|x| x.is_object())
            .unwrap_or_else(|| json!({})),
        _ => json!({}),
    }
}

/// The messageBack for an `Action.Submit` (with the card's inputs) or a
/// hero card's `messageBack` button ({type, text, displayText, value});
/// None when the action is not one (invoke, imBack, signin, task/fetch).
pub fn message_back(action: &Value, inputs: &Value) -> Option<MessageBack> {
    let kind = action
        .get("type")
        .and_then(|t| t.as_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if kind == "messageback" {
        return Some(MessageBack {
            value: as_object(action.get("value").unwrap_or(&Value::Null)),
            text: str_opt(action.get("text")),
            display_text: str_opt(action.get("displayText")),
        });
    }
    if kind != "action.submit" {
        return None;
    }
    // The renderer merges the inputs into the data (an object's).
    let mut data = action.get("data").cloned().unwrap_or(Value::Null);
    if let (Some(o), Some(i)) = (data.as_object_mut(), inputs.as_object()) {
        for (k, v) in i {
            o.insert(k.clone(), v.clone());
        }
    } else if data.is_null() && inputs.as_object().is_some_and(|i| !i.is_empty()) {
        data = inputs.clone();
    }
    let ms = data.get("msteams").or_else(|| data.get("msTeams")).cloned();
    match ms
        .as_ref()
        .and_then(|m| m.get("type"))
        .and_then(|t| t.as_str())
        .map(str::to_ascii_lowercase)
    {
        None => {
            // Teams' `Ne`: a string's data is the text, the value and the
            // text shown; an object's is the value.
            if let Value::String(s) = &data {
                Some(MessageBack {
                    value: json!({}),
                    text: Some(s.clone()),
                    display_text: Some(s.clone()).filter(|s| !s.is_empty()),
                })
            } else {
                Some(MessageBack {
                    value: if data.is_object() { data } else { json!({}) },
                    text: None,
                    display_text: None,
                })
            }
        }
        Some(t) if t == "messageback" => {
            let ms = ms.unwrap_or_default();
            // The data without msteams, with msteams.value's keys filled in
            // where the data has none (lodash defaults).
            let mut v = data.clone();
            if let Some(o) = v.as_object_mut() {
                o.remove("msteams");
                o.remove("msTeams");
                if let Value::Object(extra) = as_object(ms.get("value").unwrap_or(&Value::Null)) {
                    for (k, x) in extra {
                        o.entry(k).or_insert(x);
                    }
                }
            }
            Some(MessageBack {
                value: as_object(&v),
                text: str_opt(ms.get("text")),
                display_text: str_opt(ms.get("displayText")),
            })
        }
        _ => None,
    }
}

/// Whether a card's `Action.Submit` goes to its bot as an invoke.
pub fn is_invoke_submit(data: &Value) -> bool {
    data.pointer("/msteams/type").and_then(|v| v.as_str()) == Some("invoke")
}

/// Send an invoke; the bot's reply (Null when empty).
pub async fn invoke(
    client: &TeamsClient,
    t: &Target,
    name: Option<&str>,
    text: Option<&str>,
    value: Value,
    automatic: bool,
) -> Result<Value> {
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default")
        .await
        .unwrap_or_default();
    let display = client.display_name().unwrap_or_default();
    let url = format!(
        "{}/v1/agents/{}/invoke",
        client.chat_service_url(),
        t.bot_mri
    );
    let b = body(t, name, text, &value, &display, &token);
    let mut headers = vec![("content-type", "application/json")];
    if automatic {
        headers.push(("X-MS-AutoRefreshRequestInThread", t.thread_id.as_str()));
    }
    let resp = client
        .chat_request_with(reqwest::Method::POST, &url, &b, &headers)
        .await
        .context("The app didn't answer")?;
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
            let card = if let Value::String(s) = &value {
                serde_json::from_str(s).unwrap_or(Value::Null)
            } else {
                value
            };
            if card.is_object() {
                Outcome::Card(card)
            } else {
                Outcome::Sent
            }
        }
        "application/vnd.microsoft.activity.message" => {
            Outcome::Message(value.as_str().unwrap_or_default().to_string())
        }
        "application/vnd.microsoft.error"
        | "application/vnd.microsoft.error.preconditionFailed" => Outcome::Error(
            value
                .get("message")
                .and_then(|m| m.as_str())
                .unwrap_or("Something went wrong. Please try again.")
                .to_string(),
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
        assert_eq!(
            v,
            json!({ "data": { "Type": "QuickPoll.SubmitVote", "Options": ["Red", "Blue"], "FormId": "F", "QuestionId": "Q" }, "choice": "1" })
        );
        let b = body(&t, None, None, &v, "OST Test 1", "tok");
        assert_eq!(
            b,
            json!({
                "appId": "0e3bedea-4720-48b5-9e13-5a1ce1387d45", "messageType": "RichText/Media_Card", "value": v,
                "imdisplayname": "OST Test 1", "userAadToken": "tok", "serverMessageId": "1794621026819",
                "clientMessageId": "13086358480879058679", "conversation": { "id": "19:a@thread.v2" }
            })
        );
    }

    #[test]
    fn message_back_is_teams() {
        // A plain Action.Submit: its data and inputs as the value, no text.
        let plain =
            json!({ "type": "Action.Submit", "title": "Go", "data": { "action": "go", "id": 7 } });
        let mb = message_back(&plain, &json!({ "comment": "hi" })).unwrap();
        assert_eq!(
            mb,
            MessageBack {
                value: json!({ "action": "go", "id": 7, "comment": "hi" }),
                text: None,
                display_text: None
            }
        );
        // A string's data is the text and is shown in the chat.
        let s = json!({ "type": "Action.Submit", "data": "help" });
        assert_eq!(
            message_back(&s, &json!({})).unwrap(),
            MessageBack {
                value: json!({}),
                text: Some("help".into()),
                display_text: Some("help".into())
            }
        );
        // msteams messageBack: the data without msteams over msteams.value.
        let m = json!({ "type": "Action.Submit", "data": { "a": 1, "msteams": { "type": "messageBack", "text": "do", "displayText": "Doing it", "value": "{\"a\":0,\"b\":2}" } } });
        assert_eq!(
            message_back(&m, &json!({})).unwrap(),
            MessageBack {
                value: json!({ "a": 1, "b": 2 }),
                text: Some("do".into()),
                display_text: Some("Doing it".into())
            }
        );
        // A hero card's messageBack button.
        let h = json!({ "type": "messageBack", "title": "List", "text": "list", "displayText": "List my flows", "value": { "k": "v" } });
        assert_eq!(
            message_back(&h, &json!({})).unwrap(),
            MessageBack {
                value: json!({ "k": "v" }),
                text: Some("list".into()),
                display_text: Some("List my flows".into())
            }
        );
        // Invoke, imBack and signin aren't messageBacks.
        for t in ["invoke", "imBack", "signin", "task/fetch"] {
            assert!(
                message_back(
                    &json!({ "type": "Action.Submit", "data": { "msteams": { "type": t } } }),
                    &json!({})
                )
                .is_none()
            );
        }
        let t = Target {
            thread_id: "19:a@unq.gbl.spaces".into(),
            server_message_id: "1".into(),
            bot_mri: "28:b".into(),
            app_id: "app".into(),
            ..Default::default()
        };
        let b = body(
            &t,
            Some("messageback"),
            Some("do"),
            &json!({ "a": 1 }),
            "OST Test 1",
            "tok",
        );
        assert_eq!(b["name"], "messageback");
        assert_eq!(b["text"], "do");
        assert!(
            body(
                &t,
                Some("messageback"),
                None,
                &json!({}),
                "OST Test 1",
                "tok"
            )
            .get("text")
            .is_none()
        );
    }

    #[test]
    fn refreshes_and_replies_read_as_teams() {
        let action = json!({ "verb": "fetchAuthorVoteCard", "data": { "FormId": "F", "QuestionId": null }, "title": "Refresh", "type": "Action.Execute" });
        assert_eq!(
            execute_value(&action, &json!({}), true),
            json!({ "action": { "type": "Action.Execute", "verb": "fetchAuthorVoteCard", "data": { "FormId": "F", "QuestionId": null }, "title": "Refresh" }, "trigger": "automatic" })
        );
        let card = json!({ "type": "AdaptiveCard", "body": [] });
        assert_eq!(
            outcome(
                &json!({ "statusCode": 200, "type": "application/vnd.microsoft.card.adaptive", "value": card })
            ),
            Outcome::Card(card)
        );
        assert_eq!(
            outcome(
                &json!({ "statusCode": 200, "type": "application/vnd.microsoft.activity.message", "value": "Thanks" })
            ),
            Outcome::Message("Thanks".into())
        );
        assert_eq!(
            outcome(
                &json!({ "statusCode": 400, "type": "application/vnd.microsoft.error", "value": { "code": "x", "message": "Nope" } })
            ),
            Outcome::Error("Nope".into())
        );
        assert_eq!(outcome(&Value::Null), Outcome::Sent);
    }
}
