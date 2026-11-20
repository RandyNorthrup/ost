//! Installed apps' compose actions: what Teams' "Actions and apps" ("+")
//! lists after its own items, and what picking one does (measured on winpc
//! 2026-11-20 in OST group test, and read from Teams' message extension
//! host):
//!
//! - **Which apps.** Your installed apps (the middle tier's
//!   aggregatedEntitlements) whose message extension
//!   (`inputExtensions` / `messageExtensions`) has a command for the compose
//!   box: a command's `context` holds "compose" (no context means compose
//!   and the command box). Teams shows them as 36 px rows (the 20 px app
//!   icon, the name) under its own items, most recently used first.
//! - **An action command** (`type` "action"):
//!   - with `fetchTask`, Teams asks the app's bot `composeExtension/fetchTask`
//!     `{commandId, commandContext: "compose", context: {theme}}` and opens
//!     the task module it answers (`task.value {url | card, width, height,
//!     title}`, e.g. Polls' Microsoft Forms page 600 x 600, Polly's
//!     authoring page);
//!   - else the command's own `taskInfo` (Praise, Clipchamp: their pages).
//!   - The page's submit goes back as `composeExtension/submitAction`
//!     `{commandId, commandContext: "compose", context: {theme}, data}`; the
//!     app answers with cards for the compose box (`composeExtension
//!     {type: "result", attachments}`), another task, or nothing (it posts
//!     itself).
//! - **A search command** (`type` "query"): Teams opens a panel in place of
//!   the menu (the 32 px icon and the name 14/700, a "Search here" box,
//!   then the results) and asks `composeExtension/query` `{commandId,
//!   parameters: [{name: "initialRun", value: "true"}], queryOptions:
//!   {count: 25, skip: 0}}` (then the typed text as the command's first
//!   parameter). Results are `attachments` with a `preview` (a hero or
//!   thumbnail card) shown in the list; picking one puts its card in the
//!   box. An error reads "Unable to reach app. Please try again."
//! - **Dynamic commands** (`fetchCommands`, Workflows, Updates): Teams asks
//!   `composeExtension/fetchCommands {commandContext: "Compose"}` and lists
//!   what comes back.
//! - Every call is `POST {chat service}/v1/agents/28:{bot}/invoke` with
//!   `{name, appId, value, imdisplayname, userAadToken, conversation: {id}}`.

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// A command's contexts (none listed: compose and the command box).
fn contexts(cmd: &Value) -> Vec<String> {
    match cmd.get("context").and_then(Value::as_array) {
        Some(a) => a.iter().filter_map(|x| x.as_str().map(|s| s.to_lowercase())).collect(),
        None => vec!["compose".into(), "commandbox".into()],
    }
}

/// An app's compose entry from its definition: id, name, icon, bot and its
/// compose commands (None when it has none).
pub fn compose_entry(def: &Value) -> Option<Value> {
    let ext = def
        .get("inputExtensions")
        .or_else(|| def.get("messageExtensions"))
        .and_then(Value::as_array)
        .and_then(|a| a.first())?;
    let bot = ext.get("botId").and_then(Value::as_str).unwrap_or_default();
    let commands: Vec<Value> = ext
        .get("commands")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|c| contexts(c).iter().any(|x| x == "compose"))
        .map(|c| {
            json!({
                "id": c.get("id"), "type": c.get("type").and_then(Value::as_str).unwrap_or("query"),
                "title": c.get("title"), "description": c.get("description"),
                "initialRun": c.get("initialRun").and_then(Value::as_bool).unwrap_or(false),
                "fetchTask": c.get("fetchTask").and_then(Value::as_bool).unwrap_or(false),
                "taskInfo": c.get("taskInfo").cloned().unwrap_or(Value::Null),
                "parameters": c.get("parameters").cloned().unwrap_or(json!([])),
            })
        })
        .collect();
    let dynamic = ext.get("supportsDynamicCommands").and_then(Value::as_bool).unwrap_or(false)
        || ext.get("canUpdateConfiguration").is_some() && commands.is_empty() && ext.get("fetchCommands").is_some();
    if bot.is_empty() || (commands.is_empty() && !dynamic) {
        return None;
    }
    Some(json!({
        "id": def.get("id"),
        "name": def.get("shortName").or_else(|| def.get("name")),
        "icon": super::tabs::https_only(def.get("smallImageUrl").or_else(|| def.get("largeImageUrl")).and_then(Value::as_str).unwrap_or_default()),
        "color": def.get("color").and_then(Value::as_str).unwrap_or_default(),
        "botId": bot,
        "commands": commands,
    }))
}

/// Your installed apps with compose commands, in the catalog's order.
pub async fn installed(client: &TeamsClient) -> Result<Vec<Value>> {
    let ents = super::app_details::entitlements(client).await?;
    let mut ids: Vec<String> = ents
        .iter()
        .filter(|(_, st)| super::link_unfurl::installed_state(st))
        .map(|(id, _)| id.clone())
        .collect();
    ids.sort();
    let mut out = Vec::new();
    for chunk in ids.chunks(40) {
        let defs = super::app_details::definitions(client, chunk).await.unwrap_or_default();
        out.extend(defs.iter().filter_map(compose_entry));
    }
    Ok(out)
}

/// A bot is addressed by its id only (no `28:` in the path).
fn plain_bot(bot: &str) -> bool {
    !bot.is_empty() && bot.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

/// The invoke body Teams sends for a compose action.
pub fn invoke_body(name: &str, app_id: &str, value: Value, conversation: &str, display_name: &str, aad_token: &str) -> Value {
    json!({
        "name": name,
        "appId": app_id,
        "value": value,
        "imdisplayname": display_name,
        "userAadToken": aad_token,
        "conversation": { "id": conversation },
    })
}

/// The value of each compose invoke, as Teams sends it.
pub fn value_for(kind: &str, command: &str, args: &Value) -> Value {
    match kind {
        "fetchTask" => json!({ "commandId": command, "commandContext": "compose", "context": { "theme": "default" } }),
        "submitAction" => json!({ "commandId": command, "commandContext": "compose", "context": { "theme": "default" }, "data": args.get("data").cloned().unwrap_or(Value::Null) }),
        "query" => {
            let text = args.get("text").and_then(Value::as_str).unwrap_or_default();
            let param = args.get("parameter").and_then(Value::as_str).unwrap_or("query");
            let skip = args.get("skip").and_then(Value::as_u64).unwrap_or(0);
            let parameters = if text.is_empty() { json!([{ "name": "initialRun", "value": "true" }]) } else { json!([{ "name": param, "value": text }]) };
            json!({ "commandId": command, "parameters": parameters, "queryOptions": { "count": 25, "skip": skip } })
        }
        _ => json!({ "commandContext": "Compose" }),
    }
}

/// Ask the app's bot (fetchTask, submitAction, query or fetchCommands).
pub async fn invoke(client: &TeamsClient, bot: &str, app_id: &str, kind: &str, command: &str, args: &Value, conversation: &str) -> Result<Value> {
    anyhow::ensure!(plain_bot(bot), "Not an app");
    anyhow::ensure!(matches!(kind, "fetchTask" | "submitAction" | "query" | "fetchCommands"), "Not a compose action");
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await.unwrap_or_default();
    let display = client.display_name().unwrap_or_default();
    let endpoint = format!("{}/v1/agents/28:{}/invoke", client.chat_service_url(), bot);
    let body = invoke_body(&format!("composeExtension/{kind}"), app_id, value_for(kind, command, args), conversation, &display, &token);
    let resp = client
        .chat_request_with(reqwest::Method::POST, &endpoint, &body, &[("content-type", "application/json")])
        .await
        .context("Unable to reach app. Please try again.")?;
    let text = resp.text().await.unwrap_or_default();
    let reply: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
    tracing::info!("compose app {kind}: answered {}", if reply.get("errorCode").is_some() { "an error" } else { "ok" });
    Ok(reply)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_compose_commands_only() {
        let def = json!({ "id": "a", "name": "Polls", "smallImageUrl": "https://x/i.png", "inputExtensions": [{ "botId": "b-1",
            "commands": [ { "id": "collectFormData", "type": "action", "fetchTask": true, "context": ["compose", "commandBox"] },
                          { "id": "msg", "type": "action", "context": ["message"] },
                          { "id": "search", "type": "query" } ] }] });
        let e = compose_entry(&def).unwrap();
        let ids: Vec<&str> = e["commands"].as_array().unwrap().iter().map(|c| c["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["collectFormData", "search"]);
        assert_eq!(e["botId"], "b-1");
        assert!(compose_entry(&json!({ "id": "x", "inputExtensions": [{ "botId": "b", "commands": [{ "id": "m", "context": ["message"] }] }] })).is_none());
    }

    #[test]
    fn asks_as_teams() {
        // Captured 2026-11-20 (Polls, Power BI).
        assert_eq!(value_for("fetchTask", "collectFormData", &json!({})), json!({"commandId":"collectFormData","commandContext":"compose","context":{"theme":"default"}}));
        assert_eq!(value_for("query", "search", &json!({})), json!({"commandId":"search","parameters":[{"name":"initialRun","value":"true"}],"queryOptions":{"count":25,"skip":0}}));
        assert_eq!(value_for("query", "search", &json!({"text": "q", "parameter": "searchQuery"}))["parameters"], json!([{"name":"searchQuery","value":"q"}]));
        assert_eq!(value_for("fetchCommands", "", &json!({})), json!({"commandContext":"Compose"}));
        let b = invoke_body("composeExtension/fetchTask", "app", json!({}), "19:x@thread.v2", "OST Test 1", "t");
        assert_eq!(b["conversation"]["id"], "19:x@thread.v2");
    }
}
