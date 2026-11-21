//! Teams' Channel Agent (its "project agent", the StatusReportAgent) as
//! Create team's "Add Channel Agent" adds it (Teams 26304: the checkbox in
//! 785683, the installer hook 131175, its worker resolvers in the shared
//! worker; checked live on winpc 2026-11-20 with "OST TEST 206 agent").
//!
//! - The checkbox shows for a Copilot licence when ECS (Messaging) has
//!   `enableProjectAgentAutoCreationToggle` and `enableStatusReportAgent`
//!   on, `enableCreateTeamAgent` doesn't name "CreateTeam" (that is the
//!   Team Agent's switch) and `projectAgentSupportedLocales` is empty or
//!   names your language. It starts unticked.
//! - Ticked, once the team is made Teams checks that the tenant offers the
//!   agent (`GET {mt}/beta/users/apps/templatedApps` lists
//!   `projectAgentAppId`; if not it stops silently), then asks the Teams
//!   Copilot Aggregator to make it: `POST {tca}/agents?agentType=0` with
//!   the agent's name ("<channel> Agent", 30 characters at most), a
//!   weekly status report from an hour from now for 90 days, you as the
//!   approver, Teams' description prompt and the first channel (General's
//!   thread is the team's). The service adds the bot to the channel; the
//!   bot posts "Hi, I'm your Channel Agent…" and the channel shows "<name>
//!   has been added to the channel."
use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// The agent's app (and bot) id: ECS Messaging `projectAgentAppId`, else
/// Teams' default.
pub fn app_id() -> String {
    super::ecs::setting("Messaging", "projectAgentAppId")
        .and_then(|v| v.as_str().map(str::to_string))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "5ebb964d-4dd7-4ea6-acd5-a5f310390c5b".into())
}

/// The Teams Copilot Aggregator's resource (ECS
/// `teamsCopilotAggregatorResourceId`, else Teams' default).
fn resource() -> String {
    super::ecs::setting("Messaging", "teamsCopilotAggregatorResourceId")
        .and_then(|v| v.as_str().map(str::to_string))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "0e959cba-d60f-49b7-afe3-1b7c34563e37".into())
}

/// Whether Create team offers "Add Channel Agent", from the ECS settings
/// and the licence.
pub fn offered(flag: impl Fn(&str) -> Option<Value>, copilot: bool, locale: &str) -> bool {
    let on = |k: &str| flag(k).and_then(|v| v.as_bool()).unwrap_or(false);
    let team_agent = flag("enableCreateTeamAgent")
        .map(|v| match v {
            Value::Array(a) => a.iter().any(|x| x.as_str() == Some("CreateTeam")),
            Value::String(s) => s.split(',').any(|x| x.trim() == "CreateTeam"),
            _ => false,
        })
        .unwrap_or(false);
    let locales: Vec<String> = flag("projectAgentSupportedLocales")
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default()
        .iter()
        .filter_map(|x| x.as_str().map(|s| s.to_lowercase()))
        .collect();
    copilot
        && !team_agent
        && on("enableProjectAgentAutoCreationToggle")
        && on("enableStatusReportAgent")
        && (locales.is_empty() || locales.contains(&locale.to_lowercase()))
}

/// Whether the tenant offers the agent (its templated app is listed).
pub fn in_templated_apps(reply: &Value, app: &str) -> bool {
    reply["value"].as_array().into_iter().flatten().any(|t| t["id"].as_str().is_some_and(|id| id.eq_ignore_ascii_case(app)))
}

/// Teams' create request (the hook's input as the resolver sends it).
pub fn create_body(channel: &str, team_thread: &str, group: &str, me: &str, prompt: &str, image: &str, now: chrono::DateTime<chrono::Utc>) -> Value {
    let name: String = format!("{channel} Agent").chars().take(30).collect();
    let start = now + chrono::Duration::hours(1);
    let end = start + chrono::Duration::days(90);
    // Teams sends the UTC weekday as a number (Sunday 0: getUTCDay).
    let day = chrono::Datelike::weekday(&start).num_days_from_sunday();
    json!({
        "agentName": name,
        "agentType": "StatusReportAgent",
        "descriptionPrompt": prompt,
        "imageUrl": image,
        "groupId": group,
        "channelType": 0,
        "botId": app_id(),
        "recurrence": {
            "pattern": { "patternType": "Weekly", "weekly": { "interval": 1, "daysOfTheWeek": [day] } },
            "range": { "startDate": start.to_rfc3339_opts(chrono::SecondsFormat::Millis, true), "endDate": end.to_rfc3339_opts(chrono::SecondsFormat::Millis, true) }
        },
        "approvalList": [me],
        "threadListInformation": { "channelList": [{ "teamId": team_thread, "channelId": team_thread }] },
        "enableOnDemandReportGeneration": false,
        "generateReportFlowType": 1,
    })
}

/// Add the Channel Agent to a new team's first channel as Teams does.
/// Ok(false) when the tenant doesn't offer it (Teams stops silently).
pub async fn add_to_new_team(client: &TeamsClient, channel: &str, team_thread: &str, group: &str, prompt: &str) -> Result<bool> {
    let mt = client.middle_tier_url().context("No Teams middle-tier endpoint")?;
    let mt_token = super::directory::middle_tier_token().await?;
    let templated: Value = client.http().get(format!("{mt}/beta/users/apps/templatedApps")).bearer_auth(&mt_token).send().await?.error_for_status().context("Templated apps")?.json().await?;
    let app = app_id();
    if !in_templated_apps(&templated, &app) {
        tracing::info!("channel agent: not offered in this tenant");
        return Ok(false);
    }
    let base = client
        .region_endpoint("calling_TeamsCopilotAggregatorUrl")
        .unwrap_or_else(|| "https://teams.cloud.microsoft/api/tca/api/v1".into());
    let base = base.trim_end_matches('/').to_string();
    let token = crate::auth::oauth::access_token_for(&format!("{}/.default", resource())).await.context("Channel Agent sign-in")?;
    let me = client.object_id().unwrap_or_default();
    let image = "https://teams.cloud.microsoft/v2/evergreen-assets/apps/project_agent_statusagentlogo.png?v=2.0.0";
    let body = create_body(channel, team_thread, group, &me, prompt, image, chrono::Utc::now());
    let r = client
        .http()
        .post(format!("{base}/agents?agentType=0"))
        .bearer_auth(&token)
        .header("content-type", "application/json;charset=UTF-8")
        .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
        .header("MS-CV", uuid::Uuid::new_v4().to_string())
        .header("x-ringoverride", super::ecs::setting("metadata", "ring").and_then(|r| r.get("id").and_then(|i| i.as_str()).map(str::to_string)).unwrap_or_else(|| "general".into()))
        .json(&body)
        .timeout(std::time::Duration::from_secs(180))
        .send()
        .await?;
    let status = r.status();
    let reply: Value = r.json().await.unwrap_or(Value::Null);
    // Teams takes 2xx and 500 with an agent id as made.
    let id = reply["agentId"].as_str().unwrap_or_default();
    tracing::info!("channel agent: {status} agent={}", !id.is_empty());
    anyhow::ensure!(!id.is_empty() && (status.is_success() || status.as_u16() == 500), "The Channel Agent wasn't made ({status})");
    Ok(true)
}

/// Whether a message is the agent's welcome (Teams watches the channel for
/// a bot message whose botMetadata names "Welcome-AddAgent").
pub fn is_welcome(message: &Value) -> bool {
    let meta = &message["properties"]["botMetadata"];
    let meta: Value = match meta {
        Value::String(s) => serde_json::from_str(s).unwrap_or(Value::Null),
        v => v.clone(),
    };
    meta["botTelemetryMessageType"] == "Welcome-AddAgent"
}

/// Wait for the agent's welcome in the channel, as Teams does before its
/// "Channel Agent has been added to this channel." toast: up to
/// `projectAgentWelcomeMessageWaitTimeoutSeconds` (600 s), looking at the
/// channel's newest messages every 20 s.
pub async fn wait_for_welcome(client: &TeamsClient, channel: &str) -> Result<bool> {
    let limit = super::ecs::setting("Messaging", "projectAgentWelcomeMessageWaitTimeoutSeconds").and_then(|v| v.as_u64()).unwrap_or(600);
    let url = format!("{}/v1/users/ME/conversations/{}/messages?pageSize=10&view=msnp24Equivalent", client.chat_service_url(), channel);
    let start = std::time::Instant::now();
    while start.elapsed().as_secs() < limit {
        tokio::time::sleep(std::time::Duration::from_secs(20)).await;
        let Ok(r) = client.chat_get(&url).await else { continue };
        let v: Value = r.json().await.unwrap_or(Value::Null);
        if v["messages"].as_array().into_iter().flatten().any(is_welcome) {
            return Ok(true);
        }
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offered_as_teams() {
        let ecs = |pairs: Vec<(&'static str, Value)>| move |k: &str| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.clone());
        let base = vec![("enableProjectAgentAutoCreationToggle", json!(true)), ("enableStatusReportAgent", json!(true))];
        assert!(offered(ecs(base.clone()), true, "en-us"));
        assert!(!offered(ecs(base.clone()), false, "en-us"));
        let mut team = base.clone();
        team.push(("enableCreateTeamAgent", json!(["CreateTeam"])));
        assert!(!offered(ecs(team), true, "en-us"));
        let mut loc = base.clone();
        loc.push(("projectAgentSupportedLocales", json!(["de-de"])));
        assert!(!offered(ecs(loc.clone()), true, "en-US"));
        assert!(offered(ecs(loc), true, "de-DE"));
        assert!(!offered(ecs(vec![("enableStatusReportAgent", json!(true))]), true, "en-us"));
    }

    #[test]
    fn create_body_as_teams() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-21T03:44:00Z").unwrap().with_timezone(&chrono::Utc);
        let b = create_body("A channel with a rather long name", "19:t@thread.tacv2", "g", "me", "p", "i", now);
        assert_eq!(b["agentName"], "A channel with a rather long n");
        assert_eq!(b["recurrence"]["pattern"]["weekly"]["daysOfTheWeek"][0], 6);
        assert_eq!(b["recurrence"]["range"]["startDate"], "2026-11-21T04:44:00.000Z");
        assert_eq!(b["threadListInformation"]["channelList"][0]["channelId"], "19:t@thread.tacv2");
        assert_eq!(b["approvalList"][0], "me");
        assert!(in_templated_apps(&json!({"value": [{"id": "5EBB964D-4dd7-4ea6-acd5-a5f310390c5b"}]}), "5ebb964d-4dd7-4ea6-acd5-a5f310390c5b"));
        assert!(!in_templated_apps(&json!({"value": []}), "x"));
    }
}
