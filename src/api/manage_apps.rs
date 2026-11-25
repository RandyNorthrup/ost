//! Teams' "Manage your apps" (the Store header's gear), as Teams desktop
//! builds it (GraphQL installedAppsForUser, worker `j$t` / `b$t`; measured
//! on winpc 2026-11-20, docs/spec/store.md "Manage your apps"):
//! - your apps: your personal entitlements in the states Installed,
//!   AdminPreInstalled, InstalledAndFavorited or PreConsented
//!   (`disablePreConsentedAppsInManageApps` off), the apps shared with you
//!   (`GET {mt}/beta/users/apps/entitlements`,
//!   enableSharedInstalledAppsInManageApps), and the apps installed in your
//!   teams (`GET {mt}/beta/chats/{team thread}/apps/entitlements`, states
//!   Installed / AdminPreInstalled / InstalledAndFavorited);
//! - the multimodal AI bot left out (ECS `calling.multiModalAiBotId`);
//! - sorted Recently used (your apps usage order, the rest after), A-Z or
//!   Z-A, apps with an update first;
//! - each row expands to where the app is: "Personal app" and the teams.

use std::collections::HashMap;

use anyhow::{Context, Result};
use serde::Serialize;

use super::client::TeamsClient;
use super::tabs;

/// A team (or your personal scope) an app is installed in.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct AppPlace {
    /// The team's thread; empty for your personal app.
    pub thread: String,
    pub name: String,
    pub group_id: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct InstalledApp {
    pub id: String,
    pub name: String,
    pub developer: String,
    pub icon: String,
    /// You have it for yourself ("Personal app").
    pub personal: bool,
    pub teams: Vec<AppPlace>,
    /// Teams' Copy link: `https://teams.microsoft.com/l/app/{id}?source=…`.
    pub link: String,
    /// Shared with you (Taos): Teams can't copy a link for an external app.
    pub shared: bool,
    /// How you got it, for "Your agents and apps"' chips: `you` (Added by
    /// you), `org` (Added by your org: preinstalled or pre-consented),
    /// `built` (Built for your org: your org's own app), `shared` (Shared
    /// with you), or `team` (only in your teams).
    pub source: String,
}

/// Teams' burnt-in multimodal AI bot (config-prod multiModalAiBotId).
const MULTIMODAL_AI_BOT: &str = "875394b0-da93-4f18-8a00-33dd8c4c4613";

const PERSONAL_STATES: [&str; 4] = [
    "Installed",
    "AdminPreInstalled",
    "InstalledAndFavorited",
    "PreConsented",
];
const TEAM_STATES: [&str; 3] = ["Installed", "AdminPreInstalled", "InstalledAndFavorited"];

/// Teams' copy link for an app (`$$t`: `{deepLinkDomain}/l/app/{id}` with
/// `source=manage-apps-copy-link`).
pub fn copy_link(id: &str) -> String {
    format!(
        "https://teams.microsoft.com/l/app/{}?source=manage-apps-copy-link",
        tabs::encode_uri_component(id)
    )
}

fn app_from(d: &serde_json::Value) -> InstalledApp {
    let s = |k: &str| {
        d.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let id = s("id");
    InstalledApp {
        link: copy_link(&id),
        id,
        name: s("name"),
        developer: s("developerName"),
        icon: tabs::https_url(&s("largeImageUrl")),
        ..Default::default()
    }
}

/// The list as Teams builds it from its three sources (personal
/// entitlements with their definitions, shared apps, and each team's
/// installed apps with the team's name), before sorting.
pub fn merge(
    personal: &[(String, String)],
    definitions: &serde_json::Value,
    shared: &[serde_json::Value],
    teams: &[(AppPlace, Vec<serde_json::Value>)],
    hidden: &[String],
) -> Vec<InstalledApp> {
    let mut out: Vec<InstalledApp> = Vec::new();
    let mut index: HashMap<String, usize> = HashMap::new();
    let put =
        |app: InstalledApp, out: &mut Vec<InstalledApp>, index: &mut HashMap<String, usize>| {
            let key = app.id.to_lowercase();
            if let Some(&i) = index.get(&key) {
                out[i] = app;
            } else {
                index.insert(key, out.len());
                out.push(app);
            }
        };
    // Shared apps first, your own over them (Teams' Map([...shared,
    // ...personal]), by app id only: a shared Planner beside your own
    // Planner shows twice in Teams, measured on winpc 2026-11-21).
    // Teams keeps shared apps in its store by id, so that's their order.
    let mut shared_sorted: Vec<&serde_json::Value> = shared.iter().collect();
    shared_sorted.sort_by_key(|d| {
        d.get("id")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_lowercase()
    });
    for d in shared_sorted {
        if d.get("state")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s != "Installed")
        {
            continue;
        }
        let mut a = app_from(d);
        a.personal = true;
        a.shared = true;
        a.source = "shared".into();
        if !a.id.is_empty() {
            put(a, &mut out, &mut index);
        }
    }
    for (id, state) in personal {
        if !PERSONAL_STATES.contains(&state.as_str()) {
            continue;
        }
        let Some(d) = definitions.get(id) else {
            continue;
        };
        let mut a = app_from(d);
        a.personal = true;
        let own = d
            .get("tenantId")
            .and_then(|v| v.as_str())
            .is_some_and(|t| !t.is_empty())
            && d.get("externalId").is_some();
        a.source = if own {
            "built"
        } else if state == "AdminPreInstalled" || state == "PreConsented" {
            "org"
        } else {
            "you"
        }
        .into();
        put(a, &mut out, &mut index);
    }
    for (place, apps) in teams {
        for d in apps {
            let state = d.get("state").and_then(|v| v.as_str()).unwrap_or_default();
            if !TEAM_STATES.contains(&state) {
                continue;
            }
            let id = d
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_lowercase();
            if let Some(&i) = index.get(&id) {
                out[i].teams.push(place.clone());
            } else {
                let mut a = app_from(d);
                a.source = "team".into();
                a.teams.push(place.clone());
                put(a, &mut out, &mut index);
            }
        }
    }
    let bot_of = |id: &str| -> String {
        definitions
            .get(id)
            .or_else(|| {
                shared
                    .iter()
                    .find(|d| d.get("id").and_then(|v| v.as_str()) == Some(id))
            })
            .and_then(|d| {
                d.pointer("/bots/0/botId")
                    .or_else(|| d.pointer("/bots/0/id"))
                    .and_then(|v| v.as_str())
            })
            .unwrap_or_default()
            .to_lowercase()
    };
    out.retain(|a| {
        let bot = bot_of(&a.id);
        !a.id.is_empty()
            && !hidden.iter().any(|h| {
                h.eq_ignore_ascii_case(&a.id)
                    || (!bot.is_empty() && h.to_lowercase().trim_start_matches("28:") == bot)
            })
    });
    out
}

/// A team's apps from an aggregatedEntitlements answer asked with team
/// threads: each `teamsEntitlements[thread]` entry's definition with its
/// state.
pub fn team_apps_from(agg: &serde_json::Value, thread: &str) -> Vec<serde_json::Value> {
    let defs = agg
        .pointer("/value/definitions")
        .cloned()
        .unwrap_or_default();
    agg.pointer("/value/teamsEntitlements")
        .and_then(|t| t.get(thread))
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let id = e.get("id")?.as_str()?;
            let mut d = defs
                .get(id)
                .cloned()
                .filter(|d| d.is_object())
                .unwrap_or_else(|| serde_json::json!({ "id": id }));
            d["state"] = e.get("state").cloned().unwrap_or_default();
            Some(d)
        })
        .collect()
}

/// Teams' sorts: "Recently used" (the usage order, the rest after in
/// their own order), "A-Z" or "Z-A" by name.
pub fn sort(apps: &mut [InstalledApp], how: &str, mru: &[String]) {
    match how {
        "az" => apps.sort_by_key(|a| a.name.to_lowercase()),
        "za" => {
            apps.sort_by_key(|a| a.name.to_lowercase());
            apps.reverse()
        }
        _ => {
            let pos: HashMap<String, usize> = mru
                .iter()
                .enumerate()
                .map(|(i, a)| (a.to_lowercase(), i))
                .collect();
            apps.sort_by_key(|a| pos.get(&a.id.to_lowercase()).copied().unwrap_or(usize::MAX));
        }
    }
}

/// Your installed apps for Manage your apps, sorted `how` ("recent",
/// "az", "za").
pub async fn installed(client: &TeamsClient, how: &str) -> Result<Vec<InstalledApp>> {
    let (base, token) = tabs::middle_tier(client).await?;
    let agg: serde_json::Value = client
        .http()
        .post(format!(
            "{base}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned"
        ))
        .bearer_auth(&token)
        .json(&serde_json::json!([]))
        .send()
        .await?
        .error_for_status()
        .context("Your apps")?
        .json()
        .await?;
    let personal: Vec<(String, String)> = agg
        .pointer("/value/userEntitlements")
        .and_then(|u| u.as_object())
        .into_iter()
        .flat_map(|o| o.values())
        .filter_map(|l| l.as_array())
        .flatten()
        .filter_map(|e| {
            Some((
                e.get("id")?.as_str()?.to_string(),
                e.get("state")?.as_str()?.to_string(),
            ))
        })
        .collect();
    let definitions = agg
        .pointer("/value/definitions")
        .cloned()
        .unwrap_or_default();
    let shared: Vec<serde_json::Value> = async {
        let v: serde_json::Value = client
            .http()
            .get(format!("{base}/beta/users/apps/entitlements"))
            .bearer_auth(&token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        anyhow::Ok(v.as_array().cloned().unwrap_or_default())
    }
    .await
    .unwrap_or_default();
    // Your teams (not archived), as the team list has them.
    let joined: serde_json::Value = client
        .graph_get("/me/joinedTeams?$select=id,displayName,internalId,isArchived")
        .await?
        .json()
        .await?;
    let mut teams = Vec::new();
    for t in joined
        .get("value")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
    {
        if t.get("isArchived")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            continue;
        }
        let group = t
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        if uuid::Uuid::parse_str(&group).is_err() {
            continue;
        }
        // The team's thread (Graph leaves internalId empty here): its
        // General channel's id.
        let mut thread = t
            .get("internalId")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        if thread.is_empty() {
            thread = async {
                let v: serde_json::Value = client
                    .graph_get(&format!("/teams/{group}/primaryChannel?$select=id"))
                    .await?
                    .json()
                    .await?;
                anyhow::Ok(
                    v.get("id")
                        .and_then(|i| i.as_str())
                        .unwrap_or_default()
                        .to_string(),
                )
            }
            .await
            .unwrap_or_default();
        }
        if !thread.starts_with("19:") || thread.len() > 200 {
            continue;
        }
        let place = AppPlace {
            thread,
            name: t
                .get("displayName")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            group_id: group,
        };
        teams.push((place, Vec::new()));
    }
    // The apps installed in your teams, as Teams' teamInstalledAppsManager
    // gets them: the same aggregated entitlements with the teams' threads
    // as the body (`teamsEntitlements`: thread → [{id, state}], with their
    // definitions).
    let threads: Vec<String> = teams.iter().map(|(p, _)| p.thread.clone()).collect();
    if !threads.is_empty() {
        let agg: serde_json::Value = client
            .http()
            .post(format!(
                "{base}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned"
            ))
            .bearer_auth(&token)
            .json(&threads)
            .send()
            .await?
            .error_for_status()
            .context("Your teams' apps")?
            .json()
            .await?;
        for (place, apps) in teams.iter_mut() {
            *apps = team_apps_from(&agg, &place.thread);
        }
    }
    // Teams hides the multimodal AI bot (ECS calling.enableMultiModalAiHideBot,
    // on; multiModalAiBotId, Teams' default below when ECS leaves it out).
    let hide = super::ecs::setting("calling", "enableMultiModalAiHideBot")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let hidden: Vec<String> = if hide {
        vec![
            super::ecs::setting("calling", "multiModalAiBotId")
                .and_then(|v| v.as_str().map(str::to_string))
                .unwrap_or_else(|| MULTIMODAL_AI_BOT.to_string()),
        ]
    } else {
        Vec::new()
    };
    let mut apps = merge(&personal, &definitions, &shared, &teams, &hidden);
    let mru = super::tab_add::apps_usage(client).await;
    sort(&mut apps, how, &mru);
    Ok(apps)
}

/// Remove an app from where it is: your personal app (`DELETE {mt}/beta/
/// users/apps/entitlements/{app}`) or a team (`DELETE {mt}/beta/teams/
/// {team thread}/apps/entitlements/{app}`), as Teams. Remove does.
pub async fn uninstall(client: &TeamsClient, app_id: &str, thread: &str) -> Result<()> {
    anyhow::ensure!(
        !app_id.is_empty() && app_id.len() < 200 && !app_id.contains(['/', '?', '#']),
        "Not an app"
    );
    let (base, token) = tabs::middle_tier(client).await?;
    let app = tabs::encode_uri_component(app_id);
    let url = if thread.is_empty() {
        format!("{base}/beta/users/apps/entitlements/{app}")
    } else {
        anyhow::ensure!(
            thread.starts_with("19:") && thread.len() < 200,
            "Not a team"
        );
        format!(
            "{base}/beta/teams/{}/apps/entitlements/{app}",
            tabs::encode_uri_component(thread)
        )
    };
    client
        .http()
        .delete(url)
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("Remove app")?;
    Ok(())
}

/// Upload an app ▸ Submit an app to your org: the app package (.zip)
/// goes to your admin for approval, as Teams' uploadTenantStagedApp sends
/// a new one (`POST {mt}/beta/users/tenantapps/definitions/appPackage`,
/// the zip as the body). Returns the staged app's id.
pub async fn submit_app(client: &TeamsClient, package: &std::path::Path) -> Result<String> {
    anyhow::ensure!(
        package
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("zip")),
        "Choose an app package (.zip)"
    );
    let body = std::fs::read(package).context("Read the app package")?;
    anyhow::ensure!(
        body.len() < 50 * 1024 * 1024,
        "The app package is too large"
    );
    let (base, token) = tabs::middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!(
            "{base}/beta/users/tenantapps/definitions/appPackage"
        ))
        .bearer_auth(token)
        .header("content-type", "application/zip")
        .body(body)
        .send()
        .await?
        .error_for_status()
        .context("Submit app")?
        .json()
        .await
        .unwrap_or_default();
    Ok(v.get("id")
        .and_then(|i| i.as_str())
        .unwrap_or_default()
        .to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_list_merges_like_teams() {
        let defs = serde_json::json!({
            "p1": {"id": "p1", "name": "Praise", "developerName": "Microsoft Corporation", "largeImageUrl": "https://x/p.png"},
            "pl": {"id": "pl", "name": "Planner", "officeAssetId": "WA1"},
            "perm": {"id": "perm", "name": "Chat"},
        });
        let personal = vec![
            ("p1".to_string(), "Installed".to_string()),
            ("pl".to_string(), "Installed".to_string()),
            ("perm".to_string(), "InstalledAndPermanent".to_string()),
        ];
        let shared = vec![
            serde_json::json!({"id": "s1", "name": "Surveys", "state": "Installed"}),
            serde_json::json!({"id": "s2", "name": "Planner", "officeAssetId": "WA1", "state": "Installed"}),
        ];
        let team = AppPlace {
            thread: "19:t@thread.tacv2".into(),
            name: "OST Test Team".into(),
            group_id: "g".into(),
        };
        let teams = vec![(
            team.clone(),
            vec![
                serde_json::json!({"id": "p1", "name": "Praise", "state": "Installed"}),
                serde_json::json!({"id": "l1", "name": "Lists", "state": "Installed"}),
                serde_json::json!({"id": "c1", "name": "Copilot", "state": "PreConsented"}),
                serde_json::json!({"id": "w1", "name": "Website", "state": "InstalledAndPermanent"}),
            ],
        )];
        let mut apps = merge(&personal, &defs, &shared, &teams, &[]);
        let names: Vec<&str> = apps.iter().map(|a| a.name.as_str()).collect();
        // A shared Planner and your own Planner are two rows, as in Teams.
        assert_eq!(names, ["Surveys", "Planner", "Praise", "Planner", "Lists"]);
        assert_eq!(apps[2].teams, vec![team.clone()]);
        assert!(apps[2].personal && !apps[4].personal);
        assert_eq!(
            apps[2].link,
            "https://teams.microsoft.com/l/app/p1?source=manage-apps-copy-link"
        );
        sort(&mut apps, "recent", &["l1".to_string(), "p1".to_string()]);
        assert_eq!(
            apps.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(),
            ["l1", "p1", "s1", "s2", "pl"]
        );
        sort(&mut apps, "za", &[]);
        assert_eq!(apps[0].name, "Surveys");
        sort(&mut apps, "az", &[]);
        assert_eq!(apps[0].name, "Lists");
    }

    #[test]
    fn team_apps_come_with_their_definitions() {
        let agg = serde_json::json!({ "value": {
            "teamsEntitlements": { "19:t@thread.tacv2": [{ "id": "l1", "state": "Installed" }, { "id": "x", "state": "NotInstalled" }] },
            "definitions": { "l1": { "id": "l1", "name": "Lists", "developerName": "Microsoft Corporation" } }
        }});
        let apps = team_apps_from(&agg, "19:t@thread.tacv2");
        assert_eq!(apps.len(), 2);
        assert_eq!(apps[0]["name"], "Lists");
        assert_eq!(apps[0]["state"], "Installed");
        assert_eq!(apps[1]["id"], "x");
        assert!(team_apps_from(&agg, "19:other@thread.tacv2").is_empty());
    }
}
