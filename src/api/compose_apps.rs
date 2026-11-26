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
    // An empty list is the default too (1st Reporting's `context: []`).
    match cmd
        .get("context")
        .and_then(Value::as_array)
        .filter(|a| !a.is_empty())
    {
        Some(a) => a
            .iter()
            .filter_map(|x| x.as_str().map(|s| s.to_lowercase()))
            .collect(),
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
    // Teams lists an app only for its compose commands (Power Automate
    // Actions, with none, isn't in its menu).
    if bot.is_empty() || commands.is_empty() {
        return None;
    }
    Some(json!({
        "id": def.get("id"),
        "name": def.get("shortName").or_else(|| def.get("name")),
        "icon": super::tabs::https_only(def.get("largeImageUrl").or_else(|| def.get("smallImageUrl")).and_then(Value::as_str).unwrap_or_default()),
        "color": def.get("color").and_then(Value::as_str).unwrap_or_default(),
        "botId": bot,
        "commands": commands,
    }))
}

/// Teams' order for the picker's recent section (shared worker
/// `sortExtensibilityAppPickerCategory`, sort ["MRU", "Alphabetical"]):
/// by place in your apps' most-recently-used list (the middle tier's apps
/// usage, which Teams shares), the rest by name as JavaScript compares
/// strings (lodash `lt`: code units, case-sensitive).
pub fn sort_recent(apps: &mut [Value], mru: &[String]) {
    let pos = |a: &Value| {
        let id = a.get("id").and_then(Value::as_str).unwrap_or_default();
        mru.iter()
            .position(|m| m.eq_ignore_ascii_case(id))
            .unwrap_or(usize::MAX)
    };
    let name = |a: &Value| {
        a.get("name")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .encode_utf16()
            .collect::<Vec<u16>>()
    };
    apps.sort_by(|a, b| pos(a).cmp(&pos(b)).then_with(|| name(a).cmp(&name(b))));
}

/// The apps you have here: yours, and the conversation's (Teams' `Be`:
/// a personal or in-context entitlement that is installed), lowercase ids.
async fn usable_ids(client: &TeamsClient, conversation: &str) -> Result<Vec<String>> {
    let ents = super::app_details::entitlements(client).await?;
    let mut ids: Vec<String> = ents
        .iter()
        .filter(|(_, st)| super::link_unfurl::installed_state(st))
        .map(|(id, _)| id.to_lowercase())
        .collect();
    if conversation.ends_with("@thread.v2") || conversation.ends_with("@unq.gbl.spaces") {
        for (id, st) in super::store_content::chat_apps(client, conversation)
            .await
            .unwrap_or_default()
        {
            if super::link_unfurl::installed_state(&st) && !ids.contains(&id.to_lowercase()) {
                ids.push(id.to_lowercase());
            }
        }
    }
    ids.sort();
    Ok(ids)
}

/// Your apps with compose commands here (yours and the conversation's),
/// most recently used first (then by name), as Teams' "+" lists them.
pub async fn installed(client: &TeamsClient, conversation: &str) -> Result<Vec<Value>> {
    let ids = usable_ids(client, conversation).await?;
    let mut out = Vec::new();
    for chunk in ids.chunks(40) {
        let defs = super::app_details::definitions(client, chunk)
            .await
            .unwrap_or_default();
        out.extend(defs.iter().filter_map(compose_entry));
    }
    let mru = super::tab_add::apps_usage(client).await;
    sort_recent(&mut out, &mru);
    Ok(out)
}

/// How many store apps Teams' "Add a new app" shows.
const SUGGESTED: usize = 10;

/// Teams' "Add a new app" (the picker's suggested section): Store apps
/// (collection `app:co:all`) whose message extension has compose commands
/// and that you haven't installed, sorted AISuggested / TenantAppRanking /
/// Alphabetical (by name here), the first ten; each with its Store rating
/// and agent mark, short description, and Privacy / Terms of use links.
pub async fn suggested(client: &TeamsClient, conversation: &str) -> Result<Vec<Value>> {
    let catalog = super::app_details::catalog(client).await?;
    let have = usable_ids(client, conversation).await.unwrap_or_default();
    let ranked = super::store_content::ranked(client, &["all".to_string()])
        .await
        .unwrap_or_default();
    let by_id: std::collections::HashMap<String, &super::store_content::Ranked> = ranked
        .values()
        .flatten()
        .map(|r| (r.id.to_lowercase(), r))
        .collect();
    // Every rated app's rating (the Store's ranked lists don't name them all).
    let ratings = super::app_details::all_ratings(client)
        .await
        .unwrap_or_default();
    let mut apps: Vec<(Vec<u16>, Value)> = catalog
        .iter()
        .filter(|d| {
            let id = d.get("id").and_then(Value::as_str).unwrap_or_default().to_lowercase();
            !have.contains(&id)
        })
        .filter_map(|d| {
            compose_entry(d)?;
            let id = d.get("id").and_then(Value::as_str).unwrap_or_default().to_lowercase();
            let mut app = super::store_content::store_app(d, by_id.get(&id).copied());
            if app.count == 0
                && let Some(r) = ratings.get(&id)
            {
                app.count = r.get("count").and_then(Value::as_u64).unwrap_or(0);
                app.average = r.get("average").and_then(Value::as_f64).unwrap_or(0.0);
                app.average_text = format!("{:.1}", app.average);
                app.count_text = super::app_details::compact(app.count);
            }
            let s = |k: &str| d.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
            let v = json!({
                "id": app.id, "name": app.name, "short": app.short, "icon": app.icon,
                "average": app.average, "count": app.count, "averageText": app.average_text, "countText": app.count_text,
                "agent": app.agent,
                "privacy": super::tabs::https_only(&s("privacyUrl")), "terms": super::tabs::https_only(&s("termsOfUseUrl")),
            });
            Some((app.name.encode_utf16().collect(), v))
        })
        .collect();
    apps.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(apps.into_iter().take(SUGGESTED).map(|(_, v)| v).collect())
}

/// Your use of an app, kept where Teams keeps it (the middle tier's apps
/// usage: the app first in `appsMru` with the time, and in `apps`), so the
/// order is the same in Teams.
pub async fn record_usage(client: &TeamsClient, app_id: &str) -> Result<()> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let url = format!("{base}/beta/users/apps/usage");
    let v: Value = client
        .http()
        .get(&url)
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let mut usage = v
        .get("value")
        .filter(|x| x.is_object())
        .cloned()
        .unwrap_or_else(|| json!({}));
    let now = crate::clock::now_iso_ms();
    bump_usage(&mut usage, app_id, &now);
    client
        .http()
        .post(&url)
        .bearer_auth(&token)
        .json(&usage)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// `usage` with `app_id` used at `now`: first in `appsMru` (with its time)
/// and in `apps`, the lists kept to Teams' sizes (apps 300, appsMru 150,
/// appActions / appCommands / appScenes 75).
pub fn bump_usage(usage: &mut Value, app_id: &str, now: &str) {
    if !usage.is_object() {
        *usage = json!({});
    }
    let list = |u: &mut Value, k: &str| -> Vec<Value> {
        u.get(k)
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
    };
    let mut mru = list(usage, "appsMru");
    mru.retain(|e| {
        !e.get("appId")
            .and_then(Value::as_str)
            .is_some_and(|a| a.eq_ignore_ascii_case(app_id))
    });
    mru.insert(0, json!({ "appId": app_id, "lastUsedTimeStamp": now }));
    mru.truncate(150);
    let mut apps = list(usage, "apps");
    apps.retain(|e| !e.as_str().is_some_and(|a| a.eq_ignore_ascii_case(app_id)));
    apps.insert(0, json!(app_id));
    apps.truncate(300);
    usage["appsMru"] = json!(mru);
    usage["apps"] = json!(apps);
    for (k, n) in [("appActions", 75), ("appCommands", 75), ("appScenes", 75)] {
        let mut l = list(usage, k);
        l.truncate(n);
        usage[k] = json!(l);
    }
}

/// A bot is addressed by its id only (no `28:` in the path).
fn plain_bot(bot: &str) -> bool {
    !bot.is_empty() && bot.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

/// The invoke body Teams sends for a compose action.
pub fn invoke_body(
    name: &str,
    app_id: &str,
    value: Value,
    conversation: &str,
    display_name: &str,
    aad_token: &str,
) -> Value {
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
        "fetchTask" => {
            json!({ "commandId": command, "commandContext": "compose", "context": { "theme": "default" } })
        }
        "submitAction" => {
            json!({ "commandId": command, "commandContext": "compose", "context": { "theme": "default" }, "data": args.get("data").cloned().unwrap_or(Value::Null) })
        }
        "query" => {
            let text = args.get("text").and_then(Value::as_str).unwrap_or_default();
            let param = args
                .get("parameter")
                .and_then(Value::as_str)
                .unwrap_or("query");
            let skip = args.get("skip").and_then(Value::as_u64).unwrap_or(0);
            let parameters = if text.is_empty() {
                json!([{ "name": "initialRun", "value": "true" }])
            } else {
                json!([{ "name": param, "value": text }])
            };
            json!({ "commandId": command, "parameters": parameters, "queryOptions": { "count": 25, "skip": skip } })
        }
        _ => json!({ "commandContext": "Compose" }),
    }
}

/// Ask the app's bot (fetchTask, submitAction, query or fetchCommands).
pub async fn invoke(
    client: &TeamsClient,
    bot: &str,
    app_id: &str,
    kind: &str,
    command: &str,
    args: &Value,
    conversation: &str,
) -> Result<Value> {
    anyhow::ensure!(plain_bot(bot), "Not an app");
    anyhow::ensure!(
        matches!(
            kind,
            "fetchTask" | "submitAction" | "query" | "fetchCommands"
        ),
        "Not a compose action"
    );
    let token = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default")
        .await
        .unwrap_or_default();
    let display = client.display_name().unwrap_or_default();
    let endpoint = format!("{}/v1/agents/28:{}/invoke", client.chat_service_url(), bot);
    let body = invoke_body(
        &format!("composeExtension/{kind}"),
        app_id,
        value_for(kind, command, args),
        conversation,
        &display,
        &token,
    );
    let resp = client
        .chat_request_with(
            reqwest::Method::POST,
            &endpoint,
            &body,
            &[("content-type", "application/json")],
        )
        .await
        .context("Unable to reach app. Please try again.")?;
    let text = resp.text().await.unwrap_or_default();
    let reply: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
    tracing::info!(
        "compose app {kind}: answered {}",
        if reply.get("errorCode").is_some() {
            "an error"
        } else {
            "ok"
        }
    );
    Ok(reply)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_context_is_compose() {
        // 1st Reporting's search command lists `context: []`.
        let def = json!({ "id": "a", "name": "1st Reporting ", "inputExtensions": [{ "botId": "b-1", "commands": [{ "id": "findReport", "context": [], "title": "Find" }] }] });
        assert_eq!(
            compose_entry(&def).unwrap()["commands"][0]["id"],
            "findReport"
        );
    }

    #[test]
    fn recent_apps_in_teams_order() {
        let mut apps = vec![
            json!({"id": "p", "name": "Polly"}),
            json!({"id": "c", "name": "Clipchamp"}),
            json!({"id": "w", "name": "Workflows"}),
            json!({"id": "v", "name": "Viva Learning"}),
            json!({"id": "b", "name": "Power BI"}),
        ];
        // never used: by name
        sort_recent(&mut apps, &[]);
        let names = |a: &[Value]| {
            a.iter()
                .map(|x| x["name"].as_str().unwrap().to_string())
                .collect::<Vec<_>>()
        };
        assert_eq!(
            names(&apps),
            [
                "Clipchamp",
                "Polly",
                "Power BI",
                "Viva Learning",
                "Workflows"
            ]
        );
        // used ones first, newest first
        sort_recent(&mut apps, &["W".into(), "p".into()]);
        assert_eq!(
            names(&apps),
            [
                "Workflows",
                "Polly",
                "Clipchamp",
                "Power BI",
                "Viva Learning"
            ]
        );
    }

    #[test]
    fn usage_puts_the_app_first() {
        let mut u = json!({"apps": ["a", "b"], "appsMru": [{"appId": "a", "lastUsedTimeStamp": "t1"}, {"appId": "b", "lastUsedTimeStamp": "t0"}], "appActions": [], "appCommands": [], "appScenes": []});
        bump_usage(&mut u, "B", "t2");
        assert_eq!(u["apps"], json!(["B", "a"]));
        assert_eq!(
            u["appsMru"][0],
            json!({"appId": "B", "lastUsedTimeStamp": "t2"})
        );
        assert_eq!(u["appsMru"].as_array().unwrap().len(), 2);
        let mut empty = Value::Null;
        bump_usage(&mut empty, "x", "t");
        assert_eq!(empty["appsMru"][0]["appId"], "x");
    }

    #[test]
    fn lists_compose_commands_only() {
        let def = json!({ "id": "a", "name": "Polls", "smallImageUrl": "https://x/i.png", "inputExtensions": [{ "botId": "b-1",
            "commands": [ { "id": "collectFormData", "type": "action", "fetchTask": true, "context": ["compose", "commandBox"] },
                          { "id": "msg", "type": "action", "context": ["message"] },
                          { "id": "search", "type": "query" } ] }] });
        let e = compose_entry(&def).unwrap();
        let ids: Vec<&str> = e["commands"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, ["collectFormData", "search"]);
        assert_eq!(e["botId"], "b-1");
        assert!(compose_entry(&json!({ "id": "x", "inputExtensions": [{ "botId": "b", "commands": [{ "id": "m", "context": ["message"] }] }] })).is_none());
    }

    #[test]
    fn asks_as_teams() {
        // Captured 2026-11-20 (Polls, Power BI).
        assert_eq!(
            value_for("fetchTask", "collectFormData", &json!({})),
            json!({"commandId":"collectFormData","commandContext":"compose","context":{"theme":"default"}})
        );
        assert_eq!(
            value_for("query", "search", &json!({})),
            json!({"commandId":"search","parameters":[{"name":"initialRun","value":"true"}],"queryOptions":{"count":25,"skip":0}})
        );
        assert_eq!(
            value_for(
                "query",
                "search",
                &json!({"text": "q", "parameter": "searchQuery"})
            )["parameters"],
            json!([{"name":"searchQuery","value":"q"}])
        );
        assert_eq!(
            value_for("fetchCommands", "", &json!({})),
            json!({"commandContext":"Compose"})
        );
        let b = invoke_body(
            "composeExtension/fetchTask",
            "app",
            json!({}),
            "19:x@thread.v2",
            "OST Test 1",
            "t",
        );
        assert_eq!(b["conversation"]["id"], "19:x@thread.v2");
    }
}
