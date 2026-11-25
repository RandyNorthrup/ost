//! Teams' app bar and its "View more apps" flyout as data, and the app
//! bar menu's Pin / Unpin, Move up / Move down and Uninstall, as Teams
//! desktop does them (docs/spec/store.md "App bar"; worker `appBarManager`
//! pinApp / unpinApp / reorderApp, measured on winpc 2026-11-20):
//! - your personal apps are your aggregated entitlements (`POST {mt}/beta/
//!   users/apps/aggregatedEntitlements?appbarview=userpinned`), each with
//!   `isAppBarPinned` and `appBarOrder`; the bar shows the pinned ones by
//!   order, the flyout the rest;
//! - pinning gives the app the highest order + 1; unpinning drops it and
//!   moves every app after it up one; a move gives the app the target's
//!   order and shifts the apps in between; the change is posted with every
//!   other pinned app (`POST {mt}/beta/users/apps/pinned {"appBarPinnedApps":
//!   [{appId, appBarOrder}, …]}`, changed apps first);
//! - Uninstall removes your personal app (`DELETE {mt}/beta/users/apps/
//!   entitlements/{app}`) after Teams' "Remove {app}" question.

use std::collections::HashMap;

use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::{Value, json};

use super::client::TeamsClient;
use super::tabs;

/// Teams' core apps (async-entry module 318854) and Copilot / Store.
pub const ACTIVITY: &str = "14d6962d-6eeb-4f48-8890-de55454bb136";
/// Chat in Teams' separate view.
pub const CHAT: &str = "86fcd49b-61a2-4701-b771-54728cd291fb";
/// Chat in Teams' unified view ("simple collab": chats and channels).
pub const SIMPLE_COLLAB: &str = "3b64df9d-7e97-4d9c-ac5c-2e0a5d8e6f40";
/// Teams (channels) in the separate view.
pub const CHANNEL: &str = "2a84919f-59d8-4441-a975-2a8c2643b741";
pub const CALENDAR: &str = "ef56c0de-36fc-4ef8-b417-3d82ba9d073c";
pub const CALLING: &str = "20c3440d-c67e-4420-9f80-0e50c39693df";
pub const FILES: &str = "5af6a76b-40fc-4ba1-af29-8f49b08e44fd";
pub const COPILOT: &str = "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162";
pub const STORE: &str = "ac40aa4a-fef1-4896-aea2-46d1c14dbfd5";

/// A personal app as the app bar and its flyout use it.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct BarApp {
    pub id: String,
    pub name: String,
    /// The colour icon (largeImageUrl) and the outline one (smallImageUrl).
    pub icon: String,
    pub outline: String,
    /// Its place on the bar (`appBarOrder`) when pinned.
    pub order: Option<i64>,
    /// One of Teams' own apps (definition `isCoreApp`).
    pub core: bool,
    /// The entitlement's state (Installed, AdminPreInstalled, …).
    pub state: String,
    /// Teams' canBeUnacquired: not core and not InstalledAndPermanent,
    /// AdminPreInstalled or RequireConsent.
    pub can_uninstall: bool,
    /// A bot app (Teams adds "Block bot conversation").
    pub bot: bool,
    /// Its bot's id (definition `bots[0].id`), for its 1:1 chat.
    pub bot_id: String,
    /// That chat, when you have one (Teams' hasBotChat), and whether you
    /// blocked it (filled by the caller).
    pub bot_chat: String,
    pub bot_blocked: bool,
    /// Has a personal tab Teams can open in its own window.
    pub personal_tab: bool,
    /// Teams lists it in View more apps when it isn't pinned.
    pub flyout: bool,
}

/// Teams' own apps that can sit on the bar or in View more apps.
const BAR_CORE: [&str; 9] = [
    ACTIVITY,
    CHAT,
    SIMPLE_COLLAB,
    CHANNEL,
    CALENDAR,
    CALLING,
    "a63f7012-8cc9-42d5-99c3-e35f526fab17", // Events (meetForWork)
    "7831feaf-c4c4-4669-ba64-ce4ea0b56d31", // People
    "981bbfd0-5eb8-4393-8158-bfff69d2d6b5", // Meeting Recaps
];
/// The Microsoft 365 calendar Teams' Calendar stands for.
const CALENDAR_M365: &str = "5966c135-e05f-4ce0-81e0-e138fe8e9583";
/// Teams' burnt-in ECS extensibility.appIdList (config-prod): global apps it
/// leaves out of the bar and its flyout.
const APP_ID_LIST: [&str; 22] = [
    "com.microsoft.teamspace.tab.wiki",
    "90a27c51-5c74-453b-944a-134ba86da790",
    "ff2e639a-73e0-4dac-b55a-8cec27c9c826",
    "8ad5fc1b-251b-4d14-aceb-2624bcab0e85",
    "5a2715fe-ed49-4658-9212-64b70baa6ed6",
    "4491fd19-044b-45b2-9159-baa2ced6d4c5",
    "51126dcf-e4fc-48f9-8605-2d219f1f1cea",
    "c3c1cd11-5b38-4de4-9081-44573d9383bf",
    "d03f7a77-36dc-469a-a821-f86a20926944",
    "5e7a1100-1937-0c58-bac5-a0c48e77f001",
    "d5305801-d9c4-4dd1-aadf-d3cdb0d9d893",
    "7a78fde8-7c5c-445d-945e-9354649f9562",
    "9a1f0cd2-ff89-443f-9618-01993b1c5ff0",
    "42da7003-809a-4ef5-9a65-39c5a4c5cb08",
    "cd22c4a1-3135-48c5-b1c3-26de0785b5ae",
    "35af9cb3-8392-4473-9dd0-9295bab6a199",
    "100e3882-b881-4b6e-8dba-2cc8884af5d3",
    "592fa50f-40f2-46f4-a969-a6c75a9a32bb",
    "8c460194-2edf-4717-a5cc-be51ae478720",
    "0cca78c7-fa3e-4277-8e25-ca38a9f9d6cd",
    "a9f14e49-d497-429a-9d3d-0ac0ddba6ea3",
    "641d9d52-a4d5-41d7-89c8-210c1dc9dc07",
];

fn blocked_ids() -> Vec<String> {
    super::ecs::setting("extensibility", "appIdList")
        .and_then(|v| {
            v.as_str()
                .and_then(|s| serde_json::from_str::<Vec<String>>(s).ok())
        })
        .unwrap_or_else(|| APP_ID_LIST.iter().map(|s| s.to_string()).collect())
}

fn has_personal(list: Option<&Value>) -> bool {
    list.and_then(Value::as_array)
        .into_iter()
        .flatten()
        .any(|t| {
            t.get("scopes")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .any(|s| {
                    s.as_str()
                        .is_some_and(|s| s.eq_ignore_ascii_case("personal"))
                })
        })
}

/// Teams' View more apps: its own bar apps; others when your entitlement
/// is installed (not just pre-consented) and the app has a personal tab, or
/// a personal bot you installed; never mobile-only apps, the M365 calendar
/// or the global apps ECS' appIdList names.
fn in_flyout(id: &str, core: bool, state: &str, d: Option<&Value>, blocked: &[String]) -> bool {
    let l = id.to_lowercase();
    if core {
        return BAR_CORE.contains(&l.as_str());
    }
    if l == CALENDAR_M365 || blocked.iter().any(|b| b.eq_ignore_ascii_case(id)) {
        return false;
    }
    let Some(d) = d else { return false };
    if d.get("isMobileOnly")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return false;
    }
    let installed = matches!(
        state,
        "Installed" | "InstalledAndPermanent" | "AdminPreInstalled" | "InstalledAndFavorited"
    );
    installed
        && (has_personal(d.get("staticTabs"))
            || (has_personal(d.get("bots"))
                && matches!(state, "Installed" | "InstalledAndFavorited")))
}

const HIDDEN_STATES: [&str; 4] = [
    "NotInstalled",
    "InstalledAndHidden",
    "InstalledAndDeprecated",
    "Featured",
];

/// Your personal apps from an aggregatedEntitlements answer, in its order.
pub fn apps_from(v: &Value) -> Vec<BarApp> {
    apps_with(v, &blocked_ids())
}

/// Teams' flyout order: your apps usage first (`GET {mt}/beta/users/apps/
/// usage`), the rest in the entitlements' order.
pub fn sort_by_usage(apps: &mut [BarApp], usage: &[String]) {
    let pos: HashMap<String, usize> = usage
        .iter()
        .enumerate()
        .map(|(i, a)| (a.to_lowercase(), i))
        .collect();
    apps.sort_by_key(|a| pos.get(&a.id.to_lowercase()).copied().unwrap_or(usize::MAX));
}

fn apps_with(v: &Value, blocked: &[String]) -> Vec<BarApp> {
    let defs = v.pointer("/value/definitions").cloned().unwrap_or_default();
    let def_of = |id: &str| -> Option<&Value> {
        defs.get(id).or_else(|| {
            defs.as_object()?
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case(id))
                .map(|(_, d)| d)
        })
    };
    let mut out: Vec<BarApp> = Vec::new();
    for list in v
        .pointer("/value/userEntitlements")
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|o| o.values())
    {
        for e in list.as_array().into_iter().flatten() {
            let Some(id) = e.get("id").and_then(Value::as_str) else {
                continue;
            };
            if out.iter().any(|a| a.id.eq_ignore_ascii_case(id)) {
                continue;
            }
            let state = e
                .get("state")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            if HIDDEN_STATES.contains(&state.as_str()) {
                continue;
            }
            let d = def_of(id);
            let s = |k: &str| {
                d.and_then(|d| d.get(k))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
            let core = d
                .and_then(|d| d.get("isCoreApp"))
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let pinned = e
                .get("isAppBarPinned")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let order = e
                .get("appBarOrder")
                .and_then(Value::as_f64)
                .map(|o| o as i64)
                .filter(|_| pinned);
            out.push(BarApp {
                id: id.to_string(),
                name: s("name"),
                icon: tabs::https_url(&s("largeImageUrl")),
                outline: tabs::https_url(&s("smallImageUrl")),
                order,
                core,
                can_uninstall: !core
                    && !matches!(
                        state.as_str(),
                        "InstalledAndPermanent" | "AdminPreInstalled" | "RequireConsent"
                    ),
                bot: d.and_then(|d| d.pointer("/bots/0")).is_some(),
                bot_id: d
                    .and_then(|d| d.pointer("/bots/0/id"))
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                bot_chat: String::new(),
                bot_blocked: false,
                personal_tab: has_personal(d.and_then(|d| d.get("staticTabs"))),
                flyout: in_flyout(id, core, &state, d, blocked),
                state,
            });
        }
    }
    out
}

/// Pin: the app goes last (Teams' max order + 1).
pub fn pin_changes(apps: &[BarApp], id: &str) -> Vec<(String, Option<i64>)> {
    let next = apps.iter().filter_map(|a| a.order).max().unwrap_or(-1) + 1;
    vec![(id.to_string(), Some(next.max(1)))]
}

/// Unpin: the app leaves, every app after it moves up one.
pub fn unpin_changes(apps: &[BarApp], id: &str) -> Vec<(String, Option<i64>)> {
    let Some(at) = apps
        .iter()
        .find(|a| a.id.eq_ignore_ascii_case(id))
        .and_then(|a| a.order)
    else {
        return Vec::new();
    };
    let mut out = vec![(id.to_string(), None)];
    out.extend(apps.iter().filter_map(|a| {
        a.order
            .filter(|o| *o > at)
            .map(|o| (a.id.clone(), Some(o - 1)))
    }));
    out
}

/// Move to `target` (an order): the apps in between shift by one.
pub fn reorder_changes(apps: &[BarApp], id: &str, target: i64) -> Vec<(String, Option<i64>)> {
    let from = apps
        .iter()
        .find(|a| a.id.eq_ignore_ascii_case(id))
        .and_then(|a| a.order)
        .unwrap_or(i64::MAX);
    let mut out = vec![(id.to_string(), Some(target))];
    for a in apps.iter().filter(|a| !a.id.eq_ignore_ascii_case(id)) {
        let Some(o) = a.order else { continue };
        if o > from && o <= target {
            out.push((a.id.clone(), Some(o - 1)));
        } else if o < from && o >= target {
            out.push((a.id.clone(), Some(o + 1)));
        }
    }
    out
}

/// Teams' body: the changed apps (removed ones dropped), then every other
/// pinned app with its order.
pub fn pinned_body(apps: &[BarApp], changes: &[(String, Option<i64>)]) -> Value {
    let changed: HashMap<String, Option<i64>> = changes
        .iter()
        .map(|(i, o)| (i.to_lowercase(), *o))
        .collect();
    let mut list: Vec<Value> = changes
        .iter()
        .filter_map(|(i, o)| o.map(|o| json!({ "appId": i, "appBarOrder": o })))
        .collect();
    list.extend(
        apps.iter()
            .filter(|a| !changed.contains_key(&a.id.to_lowercase()))
            .filter_map(|a| a.order.map(|o| json!({ "appId": a.id, "appBarOrder": o }))),
    );
    json!({ "appBarPinnedApps": list })
}

/// Your personal apps (the bar's and the flyout's).
pub async fn load(client: &TeamsClient) -> Result<Vec<BarApp>> {
    let (base, token) = tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .post(format!(
            "{base}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned"
        ))
        .bearer_auth(&token)
        .json(&json!([]))
        .send()
        .await?
        .error_for_status()
        .context("Your apps")?
        .json()
        .await?;
    let mut apps = apps_from(&v);
    sort_by_usage(&mut apps, &super::tab_add::apps_usage(client).await);
    Ok(apps)
}

/// Pin (`on`) or unpin an app, or move it to `target`, as Teams does;
/// returns your apps afterwards.
pub async fn change(client: &TeamsClient, id: &str, op: &str, target: i64) -> Result<Vec<BarApp>> {
    anyhow::ensure!(!id.is_empty() && id.len() < 200, "Not an app");
    let mut apps = load(client).await?;
    let changes = match op {
        "pin" => {
            anyhow::ensure!(
                !apps
                    .iter()
                    .any(|a| a.id.eq_ignore_ascii_case(id) && a.order.is_some()),
                "Already pinned"
            );
            pin_changes(&apps, id)
        }
        "unpin" => unpin_changes(&apps, id),
        "move" => reorder_changes(&apps, id, target),
        _ => anyhow::bail!("unknown"),
    };
    anyhow::ensure!(!changes.is_empty(), "Not pinned");
    let (base, token) = tabs::middle_tier(client).await?;
    client
        .http()
        .post(format!("{base}/beta/users/apps/pinned"))
        .bearer_auth(&token)
        .json(&pinned_body(&apps, &changes))
        .send()
        .await?
        .error_for_status()
        .context("Pin app")?;
    for (cid, o) in &changes {
        if let Some(a) = apps.iter_mut().find(|a| a.id.eq_ignore_ascii_case(cid)) {
            a.order = *o;
        }
    }
    Ok(apps)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bar(list: &[(&str, Option<i64>)]) -> Vec<BarApp> {
        list.iter()
            .map(|(i, o)| BarApp {
                id: i.to_string(),
                order: *o,
                ..Default::default()
            })
            .collect()
    }

    #[test]
    fn pinning_goes_last_as_teams() {
        // Captured 2026-11-20: Word pinned after Copilot's 9 got 10.
        let apps = bar(&[
            ("chat", Some(3)),
            ("copilot", Some(9)),
            ("word", None),
            ("activity", Some(1)),
        ]);
        let ch = pin_changes(&apps, "word");
        assert_eq!(ch, vec![("word".to_string(), Some(10))]);
        let b = pinned_body(&apps, &ch);
        assert_eq!(
            b["appBarPinnedApps"][0],
            json!({ "appId": "word", "appBarOrder": 10 })
        );
        assert_eq!(b["appBarPinnedApps"].as_array().unwrap().len(), 4);
    }

    #[test]
    fn unpinning_closes_the_gap() {
        // Word 9, Copilot 10 → unpin Word: Copilot 9 (captured).
        let apps = bar(&[
            ("chat", Some(3)),
            ("word", Some(9)),
            ("copilot", Some(10)),
            ("activity", Some(1)),
        ]);
        let ch = unpin_changes(&apps, "word");
        let b = pinned_body(&apps, &ch);
        let list = b["appBarPinnedApps"].as_array().unwrap();
        assert_eq!(list[0], json!({ "appId": "copilot", "appBarOrder": 9 }));
        assert!(!list.iter().any(|e| e["appId"] == "word"));
        assert_eq!(list.len(), 3);
    }

    #[test]
    fn the_flyout_lists_what_teams_does() {
        let v = json!({ "value": {
            "userEntitlements": { "c": [
                { "id": "word", "state": "InstalledAndPermanent" },
                { "id": "powerapps", "state": "PreConsented" },
                { "id": "polly", "state": "Installed" },
                { "id": "agent", "state": "InstalledAndPermanent" },
                { "id": "90a27c51-5c74-453b-944a-134ba86da790", "state": "InstalledAndPermanent" },
                { "id": "7831feaf-c4c4-4669-ba64-ce4ea0b56d31", "state": "InstalledAndPermanent" },
                { "id": "34b01851-c13d-4604-bb3b-5de1ecbf0288", "state": "InstalledAndPermanent" },
                { "id": "camera", "state": "InstalledAndPermanent" },
                { "id": "news", "state": "Featured" }
            ] },
            "definitions": {
                "word": { "name": "Word", "staticTabs": [{ "scopes": ["Personal"] }] },
                "powerapps": { "name": "Power Apps", "staticTabs": [{ "scopes": ["Personal"] }] },
                "polly": { "name": "Polly", "bots": [{ "scopes": ["Personal", "Team"] }] },
                "agent": { "name": "Agent", "bots": [{ "scopes": ["Personal"] }] },
                "90a27c51-5c74-453b-944a-134ba86da790": { "name": "Help", "staticTabs": [{ "scopes": ["Personal"] }] },
                "7831feaf-c4c4-4669-ba64-ce4ea0b56d31": { "name": "People", "isCoreApp": true },
                "34b01851-c13d-4604-bb3b-5de1ecbf0288": { "name": "Saved", "isCoreApp": true },
                "camera": { "name": "Camera", "isMobileOnly": true, "staticTabs": [{ "scopes": ["Personal"] }] }
            }
        }});
        let apps = apps_with(&v, &blocked_ids());
        let shown: Vec<&str> = apps
            .iter()
            .filter(|a| a.flyout)
            .map(|a| a.name.as_str())
            .collect();
        assert_eq!(shown, vec!["Word", "Polly", "People"]);
        assert!(!apps.iter().any(|a| a.name == "News"));
        let mut apps = apps;
        sort_by_usage(&mut apps, &["polly".to_string()]);
        assert_eq!(apps[0].name, "Polly");
        assert_eq!(apps[1].name, "Word");
        assert!(
            apps.iter()
                .find(|a| a.name == "Polly")
                .unwrap()
                .can_uninstall
        );
        assert!(
            !apps
                .iter()
                .find(|a| a.name == "Word")
                .unwrap()
                .can_uninstall
        );
    }

    #[test]
    fn moves_shift_the_apps_between() {
        // Calendar 6 moved up to Chat's 3: Chat 4, chat-split 5, Teams 6 (captured).
        let apps = bar(&[
            ("activity", Some(1)),
            ("chat", Some(3)),
            ("chat2", Some(4)),
            ("teams", Some(5)),
            ("calendar", Some(6)),
            ("calls", Some(7)),
        ]);
        let ch = reorder_changes(&apps, "calendar", 3);
        assert_eq!(
            ch,
            vec![
                ("calendar".into(), Some(3)),
                ("chat".into(), Some(4)),
                ("chat2".into(), Some(5)),
                ("teams".into(), Some(6))
            ]
        );
        // and back down to Chat's 4: Chat 3.
        let apps = bar(&[
            ("activity", Some(1)),
            ("calendar", Some(3)),
            ("chat", Some(4)),
            ("chat2", Some(5)),
            ("teams", Some(6)),
        ]);
        assert_eq!(
            reorder_changes(&apps, "calendar", 4),
            vec![("calendar".into(), Some(4)), ("chat".into(), Some(3))]
        );
    }
}
