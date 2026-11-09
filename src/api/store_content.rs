//! Teams' Store data: its collections (the store content doc on the CDN,
//! over the burnt-in collection list), the ranked catalog, and the
//! in-context Store that "Add agent to the chat/channel" opens.
//! docs/spec/store.md has the measurements and sources.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

use anyhow::{Context, Result};
use serde::Serialize;

use super::app_details;
use super::client::TeamsClient;
use super::ecs;

const CDN: &str = "https://res.cdn.office.net/teamsappdata/evergreen-assets/storecontent";

/// Teams' burnt-in defaults for the settings the Store reads, its
/// collection list and the en-us strings of their titles.
fn defaults() -> &'static serde_json::Value {
    static D: OnceLock<serde_json::Value> = OnceLock::new();
    D.get_or_init(|| serde_json::from_str(include_str!("store_defaults.json")).unwrap_or_default())
}

/// An extensibility setting: ECS, else Teams' burnt-in default.
fn setting(key: &str) -> serde_json::Value {
    let base = defaults().pointer(&format!("/settings/{key}")).cloned();
    match (ecs::setting("extensibility", key), base) {
        // An object from ECS is laid over the default object, key by key,
        // as Teams merges its settings (BotTeam stays when ECS sends Bot).
        (Some(serde_json::Value::Object(over)), Some(serde_json::Value::Object(mut b))) => {
            b.extend(over);
            serde_json::Value::Object(b)
        }
        (Some(v), _) => v,
        (None, Some(b)) => b,
        (None, None) => serde_json::Value::Null,
    }
}

fn flag(key: &str) -> bool {
    setting(key).as_bool().unwrap_or(false)
}

/// A title key's English text (keys start with "_"); other titles as they are.
pub fn text(key: &str) -> String {
    if key.starts_with('_') {
        defaults()
            .pointer("/strings")
            .and_then(|s| s.get(key))
            .and_then(|v| v.as_str())
            .unwrap_or(key)
            .to_string()
    } else {
        key.to_string()
    }
}

/// Teams' activeFlags rule: every flag set, every "!flag" unset.
fn active(flags: Option<&serde_json::Value>) -> bool {
    flags
        .and_then(|f| f.as_array())
        .into_iter()
        .flatten()
        .filter_map(|f| f.as_str())
        .all(|f| match f.strip_prefix('!') {
            Some(off) => !flag(off),
            None => flag(f),
        })
}

/// The store content doc's path: `apps[/smb|/edu]/{doc}.json{?query}`.
pub fn content_path(doc: &str, license: Option<&serde_json::Value>, ts: u64) -> String {
    let sku = license
        .map(|l| {
            let cat = l
                .get("eduLicenseSkuAndCategory")
                .and_then(|c| c.as_str())
                .unwrap_or_default();
            if cat.contains("Student") || cat.contains("Teacher") {
                "/edu"
            } else if l
                .get("isTeamsSmb")
                .and_then(|b| b.as_bool())
                .unwrap_or(false)
            {
                "/smb"
            } else {
                ""
            }
        })
        .unwrap_or("");
    let (path, query) = match doc.find('?') {
        Some(i) => (&doc[..i], &doc[i..]),
        None => (doc, ""),
    };
    let file = if path.to_lowercase().ends_with(".json") {
        path.to_string()
    } else {
        format!("{path}.json")
    };
    let sep = if query.is_empty() { '?' } else { '&' };
    format!("apps{sku}/{file}{query}{sep}ts={ts}")
}

/// A collection as Teams merges it: the burnt-in entry (when its flags
/// hold) under the content doc's entry of the same id.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Collection {
    pub id: String,
    pub title: String,
    /// Catalog categories it lists (linkedEntities).
    pub linked: Vec<String>,
    /// Apps it lists by id (itemsList), when it isn't a category.
    pub items: Vec<String>,
    pub hidden: bool,
    /// A category's featured apps (a doc collection whose first item links
    /// this one, then "featured" items: Teams shows them first), and the
    /// id of that featured collection (its rank list orders them).
    pub featured: Vec<String>,
    pub featured_by: String,
}

/// Merge the burnt-in collections with the content doc's.
pub fn collections_from(content: &serde_json::Value) -> Vec<Collection> {
    let s = |v: &serde_json::Value, k: &str| {
        v.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let list = |v: &serde_json::Value, k: &str| -> Vec<String> {
        v.get(k)
            .and_then(|x| x.as_array())
            .into_iter()
            .flatten()
            .filter_map(|x| x.as_str().map(str::to_string))
            .collect()
    };
    let mut out: Vec<Collection> = defaults()
        .pointer("/collections")
        .and_then(|c| c.as_array())
        .into_iter()
        .flatten()
        .filter(|c| active(c.get("activeFlags")))
        .map(|c| Collection {
            id: s(c, "collectionId"),
            title: s(c, "title"),
            linked: list(c, "linkedEntities"),
            items: Vec::new(),
            hidden: c.get("isHidden").and_then(|h| h.as_bool()).unwrap_or(false),
            ..Default::default()
        })
        .collect();
    let mut featured: Vec<(String, String, Vec<String>)> = Vec::new();
    for c in content
        .get("collectionsList")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
    {
        let id = s(c, "id");
        let typed: Vec<(String, String)> = c
            .get("itemsList")
            .and_then(|l| l.as_array())
            .into_iter()
            .flatten()
            .filter_map(|i| Some((i.get("id")?.as_str()?.to_string(), s(i, "type"))))
            .collect();
        if let Some((target, kind)) = typed.first()
            && kind == "linkedCollectionId"
        {
            let picks = typed
                .iter()
                .skip(1)
                .filter(|(_, k)| k == "featured")
                .map(|(i, _)| i.clone())
                .collect();
            featured.push((target.clone(), id.clone(), picks));
        }
        let items: Vec<String> = c
            .get("itemsList")
            .and_then(|l| l.as_array())
            .into_iter()
            .flatten()
            .filter_map(|i| i.get("id")?.as_str().map(str::to_string))
            .collect();
        // A single item named as the collection links that category.
        let self_link = items.len() == 1 && items[0].eq_ignore_ascii_case(&id);
        let hidden = c.get("isHidden").and_then(|h| h.as_bool());
        match out.iter_mut().find(|o| o.id == id) {
            // Teams' merge keeps the burnt-in title (the doc sets order,
            // description, visibility and, for an empty entry, its items).
            Some(o) => {
                if let Some(h) = hidden {
                    o.hidden = o.hidden || h;
                }
                if o.linked.is_empty() && o.items.is_empty() && !self_link {
                    o.items = items;
                }
            }
            None => out.push(Collection {
                title: s(c, "title"),
                linked: if self_link {
                    vec![id.clone()]
                } else {
                    Vec::new()
                },
                items: if self_link { Vec::new() } else { items },
                hidden: hidden.unwrap_or(false),
                id,
                ..Default::default()
            }),
        }
    }
    for (target, by, picks) in featured {
        if let Some(o) = out.iter_mut().find(|o| o.id.eq_ignore_ascii_case(&target)) {
            o.featured = picks;
            o.featured_by = by;
        }
    }
    for c in &mut out {
        c.title = text(&c.title);
    }
    out
}

async fn content(client: &TeamsClient) -> Result<serde_json::Value> {
    static CACHE: Mutex<Option<(serde_json::Value, std::time::Instant)>> = Mutex::new(None);
    if let Some((v, at)) = CACHE.lock().unwrap_or_else(|e| e.into_inner()).as_ref()
        && at.elapsed() < std::time::Duration::from_secs(480 * 60)
    {
        return Ok(v.clone());
    }
    let doc = setting("storeAppsCollectionsDoc");
    let doc = doc.as_str().unwrap_or("storev2?v=2");
    let ts = (chrono::Utc::now().timestamp_millis() / 7_200_000) as u64;
    let url = format!(
        "{CDN}/{}",
        content_path(doc, client.license_details().as_ref(), ts)
    );
    let v: serde_json::Value = client
        .http()
        .get(&url)
        .send()
        .await?
        .error_for_status()
        .context("Store content")?
        .json()
        .await?;
    *CACHE.lock().unwrap_or_else(|e| e.into_inner()) = Some((v.clone(), std::time::Instant::now()));
    Ok(v)
}

/// A ranked app as the Store API gives it.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Ranked {
    pub id: String,
    pub caps: Vec<String>,
    pub average: f64,
    pub count: u64,
}

pub fn ranked_from(v: &serde_json::Value) -> HashMap<String, Vec<Ranked>> {
    v.get("appCategoriesDictionary")
        .and_then(|d| d.as_object())
        .into_iter()
        .flatten()
        .map(|(cat, c)| {
            let apps = c
                .get("apps")
                .and_then(|a| a.as_array())
                .into_iter()
                .flatten()
                .filter_map(|a| {
                    Some(Ranked {
                        id: a.get("id")?.as_str()?.to_string(),
                        caps: a
                            .get("metaCapabilities")
                            .and_then(|m| m.as_array())
                            .into_iter()
                            .flatten()
                            .filter_map(|m| m.as_str().map(str::to_string))
                            .collect(),
                        average: a
                            .pointer("/rating/average")
                            .and_then(|x| x.as_f64())
                            .unwrap_or(0.0),
                        count: a
                            .pointer("/rating/count")
                            .and_then(|x| x.as_u64())
                            .unwrap_or(0),
                    })
                })
                .collect();
            (cat.to_lowercase(), apps)
        })
        .collect()
}

/// The Store API's ranked lists for these categories (Teams' store data
/// request, RankedByLocale), by lowercase category.
pub async fn ranked(
    client: &TeamsClient,
    categories: &[String],
) -> Result<HashMap<String, Vec<Ranked>>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let body = serde_json::json!({
        "appCategories": categories,
        "defaultAppsSortType": "RankedByLocale",
        "appsStoreOptions": {
            "includeIndustries": true,
            "includeSuggestedApps": false,
            "includeSubscriptionApps": flag("enableSubscriptionAppsCategory"),
            "includeTotalAppsCount": true,
            "includeFrequentCollaboratorsApps": flag("enableFrequentCollaborators"),
            "includePluginsForCopilot": flag("enableCopilotExtensions") || flag("includeOpenAIPlugins"),
            "includePreinstalledApps": flag("enablePreinstalledApps"),
            "includeAgentBlueprints": flag("enableStoreAgentBlueprints"),
        },
    });
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/users/apps/store"))
        .bearer_auth(token)
        .header("x-client-ui-language", "en-us")
        .header("x-ms-client-caller", "StoreAppsStoreDataSync")
        .header(
            "x-ringoverride",
            ecs::segment("TeamsRing").unwrap_or_default(),
        )
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("Store data")?
        .json()
        .await?;
    Ok(ranked_from(&v))
}

/// Teams' collection item ranking (`POST {suggestions}/api/v2/apps/rank`).
pub async fn items_rank(
    client: &TeamsClient,
    collections: &HashMap<String, Vec<String>>,
) -> HashMap<String, Vec<String>> {
    if !flag("enableStoreAppsContentCollectionsItemsRank") || collections.is_empty() {
        return HashMap::new();
    }
    let r = async {
        let url = format!(
            "{}/api/v2/apps/rank",
            app_details::suggestions_base(client)?
        );
        let token = app_details::suggestions_token().await?;
        let v: serde_json::Value = client
            .http()
            .post(url)
            .bearer_auth(token)
            .header("clientInfo", app_details::client_info())
            .header("X-Client-UI-Language", "en-us")
            .json(&serde_json::json!({ "collections": collections }))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        anyhow::Ok(
            v.get("collections")
                .and_then(|c| c.as_object())
                .into_iter()
                .flatten()
                .map(|(k, l)| {
                    (
                        k.clone(),
                        l.as_array()
                            .into_iter()
                            .flatten()
                            .filter_map(|i| i.as_str().map(str::to_string))
                            .collect(),
                    )
                })
                .collect(),
        )
    }
    .await;
    r.unwrap_or_default()
}

/// What Teams asks the rank service about: every doc collection's item
/// ids (its worker's `entityId -> itemsIdList` map).
pub fn rank_input(content: &serde_json::Value) -> HashMap<String, Vec<String>> {
    content
        .get("collectionsList")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let id = c.get("id")?.as_str()?.to_string();
            let items: Vec<String> = c
                .get("itemsList")
                .and_then(|l| l.as_array())
                .into_iter()
                .flatten()
                .filter_map(|i| i.get("id")?.as_str().map(str::to_string))
                .collect();
            Some((id, items))
        })
        .collect()
}

/// Teams' sort of a collection's items by the rank list: ranked items
/// first in rank order, the rest after in their own order.
pub fn sort_by_rank(items: &[String], rank: &[String]) -> Vec<String> {
    let pos: HashMap<&str, usize> = rank
        .iter()
        .enumerate()
        .map(|(i, r)| (r.as_str(), i))
        .collect();
    let mut v: Vec<(usize, usize, String)> = items
        .iter()
        .enumerate()
        .map(|(i, x)| {
            (
                pos.get(x.as_str()).copied().unwrap_or(rank.len()),
                i,
                x.clone(),
            )
        })
        .collect();
    v.sort();
    v.into_iter().map(|(_, _, x)| x).collect()
}

/// An app as the Store draws it.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct StoreApp {
    pub id: String,
    pub name: String,
    pub developer: String,
    pub short: String,
    pub icon: String,
    pub average: f64,
    pub count: u64,
    /// As Teams writes them: "4.1" and "73.5K".
    pub average_text: String,
    pub count_text: String,
    /// Teams' agent mark (sparkle) after the name.
    pub agent: bool,
}

/// One of the in-context Store's collections.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct IcCollection {
    pub id: String,
    pub title: String,
    pub apps: Vec<StoreApp>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct InContext {
    /// Bots already in the conversation (the top grid).
    pub installed: Vec<StoreApp>,
    pub collections: Vec<IcCollection>,
}

/// Whether an app's bot works in this scope ("groupchat" or "team").
pub fn bot_supports(def: &serde_json::Value, scope: &str) -> bool {
    def.get("bots")
        .and_then(|b| b.as_array())
        .into_iter()
        .flatten()
        .any(|b| {
            b.get("scopes")
                .and_then(|s| s.as_array())
                .into_iter()
                .flatten()
                .any(|s| s.as_str().is_some_and(|s| s.eq_ignore_ascii_case(scope)))
        })
}

const COPILOT_CAPS: [&str; 3] = ["CopilotPlugins", "CopilotExtensions", "PowerPlatform"];

fn is_agent(caps: &[String]) -> bool {
    caps.iter()
        .any(|c| COPILOT_CAPS.iter().any(|k| k.eq_ignore_ascii_case(c)))
}

fn store_app(def: &serde_json::Value, r: Option<&Ranked>) -> StoreApp {
    let s = |k: &str| {
        def.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    StoreApp {
        id: s("id"),
        name: s("name"),
        developer: s("developerName"),
        short: s("shortDescription"),
        icon: super::tabs::https_only(&s("largeImageUrl")),
        average: r.map(|r| r.average).unwrap_or(0.0),
        count: r.map(|r| r.count).unwrap_or(0),
        // The Store's cards keep one decimal ("3.0").
        average_text: format!("{:.1}", r.map(|r| r.average).unwrap_or(0.0)),
        count_text: app_details::compact(r.map(|r| r.count).unwrap_or(0)),
        agent: r.is_some_and(|r| is_agent(&r.caps)),
    }
}

/// The ids in a collection, before filtering: a linked category's ranked
/// list (Agents is the ranked catalog's copilot apps), or its own items.
pub fn collection_ids(
    c: &Collection,
    ranked: &HashMap<String, Vec<Ranked>>,
    rank: &HashMap<String, Vec<String>>,
) -> Vec<String> {
    if let Some(cat) = c.linked.first() {
        // A category's featured apps lead (ranked by their collection).
        let lead = match rank.get(&c.featured_by) {
            Some(r) => sort_by_rank(&c.featured, r),
            None => c.featured.clone(),
        };
        let cat = cat.to_lowercase();
        if cat.starts_with("cp_copilot") || cat == "copilotplugins" {
            return lead
                .into_iter()
                .chain(
                    ranked
                        .get("popularapps")
                        .into_iter()
                        .flatten()
                        .filter(|r| is_agent(&r.caps))
                        .map(|r| r.id.clone()),
                )
                .collect();
        }
        return lead
            .into_iter()
            .chain(ranked.get(&cat).into_iter().flatten().map(|r| r.id.clone()))
            .collect();
    }
    match rank.get(&c.id) {
        Some(r) => sort_by_rank(&c.items, r),
        None => c.items.clone(),
    }
}

/// Teams' "Add agent to the chat/channel" Store: `team` for a channel.
/// `apps` are the conversation's apps and states: its installed bots make
/// the top grid, and none of its apps is offered again.
pub async fn in_context(
    client: &TeamsClient,
    team: bool,
    apps: &[(String, String)],
) -> Result<InContext> {
    let kind = if team { "BotTeam" } else { "BotGroupChat" };
    let scope = if team { "team" } else { "groupchat" };
    // Teams looks up `{capability}{scope}` ("botteam", "botgroupchat"),
    // then the capability alone ("bot"), ignoring case.
    let overwrite = setting("inContextStoreCollectionIdsOverwrite");
    let lists: HashMap<String, &serde_json::Value> = overwrite
        .as_object()
        .into_iter()
        .flatten()
        .filter(|(_, v)| v.as_array().is_some_and(|a| !a.is_empty()))
        .map(|(k, v)| (k.to_lowercase(), v))
        .collect();
    let ids: Vec<String> = lists
        .get(&kind.to_lowercase())
        .or_else(|| lists.get("bot"))
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
        .filter_map(|x| x.as_str()?.strip_prefix("app:co:").map(str::to_string))
        .collect();
    let doc = content(client).await?;
    let all = collections_from(&doc);
    let chosen: Vec<Collection> = ids
        .iter()
        .filter_map(|id| all.iter().find(|c| &c.id == id).cloned())
        .collect();
    let mut cats: Vec<String> = vec!["popularApps".into()];
    for c in &chosen {
        if let Some(l) = c.linked.first()
            && !l.to_lowercase().starts_with("cp_")
            && !cats.iter().any(|x| x.eq_ignore_ascii_case(l))
        {
            cats.push(l.clone());
        }
    }
    let ranked = ranked(client, &cats).await?;
    let rank = items_rank(client, &rank_input(&doc)).await;
    let catalog = app_details::catalog(client).await?;
    let defs: HashMap<String, &serde_json::Value> = catalog
        .iter()
        .filter_map(|d| Some((d.get("id")?.as_str()?.to_lowercase(), d)))
        .collect();
    let by_id: HashMap<String, &Ranked> = ranked
        .values()
        .flatten()
        .map(|r| (r.id.to_lowercase(), r))
        .collect();
    // Apps already added (the grid's) aren't offered again.
    let mut excluded: HashSet<String> = apps
        .iter()
        .filter(|(_, state)| state == "Installed")
        .map(|(i, _)| i.to_lowercase())
        .collect();
    for h in setting("inContextStoreHiddenApps")
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|x| x.as_str())
    {
        excluded.insert(h.to_lowercase());
    }
    let min_apps = defaults()
        .get("inContextStoreMinAppsCategory")
        .and_then(|v| v.as_u64())
        .unwrap_or(6) as usize;
    let min_agents = setting("inContextStoreMinAgentsCategory")
        .as_u64()
        .unwrap_or(1) as usize;
    let mut collections = Vec::new();
    for c in &chosen {
        let mut seen = HashSet::new();
        let apps: Vec<StoreApp> = collection_ids(c, &ranked, &rank)
            .into_iter()
            .filter(|id| seen.insert(id.to_lowercase()) && !excluded.contains(&id.to_lowercase()))
            .filter_map(|id| {
                let d = defs.get(&id.to_lowercase())?;
                bot_supports(d, scope).then(|| store_app(d, by_id.get(&id.to_lowercase()).copied()))
            })
            .collect();
        let min = if c.id == "copilotplugins" {
            min_agents
        } else {
            min_apps
        };
        if apps.len() >= min {
            collections.push(IcCollection {
                id: c.id.clone(),
                title: c.title.clone(),
                apps,
            });
        }
    }
    // The grid: bots added to this conversation ("Installed"; Teams'
    // pre-consented and permanent apps don't show).
    let mut installed: Vec<StoreApp> = apps
        .iter()
        .filter(|(_, state)| state == "Installed")
        .filter_map(|(id, _)| {
            let d = defs.get(&id.to_lowercase())?;
            bot_supports(d, scope).then(|| store_app(d, by_id.get(&id.to_lowercase()).copied()))
        })
        .collect();
    // By name, as Teams lists them (Forms, Power BI, Updates).
    installed.sort_by_key(|a| a.name.to_lowercase());
    Ok(InContext {
        installed,
        collections,
    })
}

/// The ranked catalog (all apps, by Teams' ranking), kept 30 minutes.
async fn popular(client: &TeamsClient) -> Result<std::sync::Arc<Vec<Ranked>>> {
    static CACHE: Mutex<Option<(std::sync::Arc<Vec<Ranked>>, std::time::Instant)>> =
        Mutex::new(None);
    if let Some((v, at)) = CACHE.lock().unwrap_or_else(|e| e.into_inner()).as_ref()
        && at.elapsed() < std::time::Duration::from_secs(30 * 60)
    {
        return Ok(v.clone());
    }
    let mut r = ranked(client, &["popularApps".to_string()]).await?;
    let v = std::sync::Arc::new(r.remove("popularapps").unwrap_or_default());
    *CACHE.lock().unwrap_or_else(|e| e.into_inner()) = Some((v.clone(), std::time::Instant::now()));
    Ok(v)
}

/// App ids from a Store search reply, in its order.
pub fn search_ids(v: &serde_json::Value) -> Vec<String> {
    v.get("results")
        .and_then(|r| r.as_array())
        .into_iter()
        .flatten()
        .filter_map(|r| r.get("appId").or(r.get("id"))?.as_str().map(str::to_string))
        .collect()
}

/// Search the Store for agents and bots for a conversation, as Teams'
/// server search (`POST {mt}/beta/users/apps/search`), keeping bots that
/// work in the conversation and aren't in it already.
pub async fn search_agents(
    client: &TeamsClient,
    query: &str,
    team: bool,
    apps: &[(String, String)],
) -> Result<Vec<StoreApp>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/users/apps/search"))
        .bearer_auth(token)
        .header("x-client-ui-language", "en-us")
        .header("x-ms-client-caller", "SearchStoreAppsJob")
        .header(
            "x-ringoverride",
            ecs::segment("TeamsRing").unwrap_or_default(),
        )
        .json(&serde_json::json!({
            "searchQuery": query,
            "includeOpenAiPlugins": flag("includeOpenAIPlugins") || flag("enableCopilotExtensions"),
            "includeSharedApps": flag("enableCopilotExtensions"),
        }))
        .send()
        .await?
        .error_for_status()
        .context("Store search")?
        .json()
        .await?;
    let scope = if team { "team" } else { "groupchat" };
    let catalog = app_details::catalog(client).await?;
    let ranked = popular(client).await.unwrap_or_default();
    let excluded: HashSet<String> = apps
        .iter()
        .filter(|(_, state)| state == "Installed")
        .map(|(i, _)| i.to_lowercase())
        .collect();
    Ok(search_ids(&v)
        .into_iter()
        .filter(|id| !excluded.contains(&id.to_lowercase()))
        .filter_map(|id| {
            let d = catalog.iter().find(|d| {
                d.get("id")
                    .and_then(|i| i.as_str())
                    .is_some_and(|i| i.eq_ignore_ascii_case(&id))
            })?;
            bot_supports(d, scope)
                .then(|| store_app(d, ranked.iter().find(|r| r.id.eq_ignore_ascii_case(&id))))
        })
        .collect())
}

/// What adding an app did.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Added {
    pub app: String,
    pub name: String,
    /// Its bot's id ("28:{id}" is its mention mri), if it has one.
    pub bot: String,
    /// The bot only sends notifications: Teams says "About this bot"
    /// instead of starting an @mention.
    pub notification_only: bool,
}

/// The app's bot: (id, notification only).
pub fn bot_of(def: &serde_json::Value) -> Option<(String, bool)> {
    let b = def.get("bots")?.as_array()?.first()?;
    Some((
        b.get("id")?.as_str()?.to_string(),
        b.get("isNotificationOnly").and_then(|n| n.as_bool()).unwrap_or(false),
    ))
}

/// Add an app as Teams' Add does (captured on winpc, 2026-11-09): for you
/// (`POST {mt}/beta/users/apps/entitlements`, unless you have it), then,
/// for a conversation, to it (`POST {mt}/beta/chats/{id}/apps/entitlements`,
/// or the team's for a channel). Each body is the app's definition.
pub async fn add_app(client: &TeamsClient, app_id: &str, conversation: Option<(&str, bool)>) -> Result<Added> {
    let base = client.middle_tier_url().context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let def = app_details::definition(client, app_id).await?;
    let mine = app_details::entitlements(client).await.unwrap_or_default();
    let have = mine.get(&app_id.to_lowercase()).is_some_and(|s| s.starts_with("Installed"));
    let post = |url: String, channel: Option<&str>| {
        let mut rq = client.http().post(url).bearer_auth(&token).header("x-client-ui-language", "en-us");
        if let Some(c) = channel {
            // Teams names the channel it was added from.
            rq = rq.header("X-Ms-Appinstall-Channelid", c);
        }
        rq.json(&def).send()
    };
    if !have {
        post(format!("{base}/beta/users/apps/entitlements"), None).await?.error_for_status().context("Add the app")?;
    }
    if let Some((conv, channel)) = conversation {
        let scope = if channel { "teams" } else { "chats" };
        post(format!("{base}/beta/{scope}/{conv}/apps/entitlements"), channel.then_some(conv))
            .await?
            .error_for_status()
            .context("Add the app to the conversation")?;
    }
    let (bot, notification_only) = bot_of(&def).unwrap_or_default();
    Ok(Added {
        app: app_id.to_string(),
        name: def.get("name").and_then(|n| n.as_str()).unwrap_or_default().to_string(),
        bot,
        notification_only,
    })
}

/// Remove an app from a chat (Manage apps ▸ Remove:
/// `DELETE {mt}/beta/chats/{id}/apps/entitlements/{appId}`).
pub async fn remove_from_chat(client: &TeamsClient, thread_id: &str, app_id: &str) -> Result<()> {
    let base = client.middle_tier_url().context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    client
        .http()
        .delete(format!("{base}/beta/chats/{thread_id}/apps/entitlements/{app_id}"))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("Remove the app")?;
    Ok(())
}

/// A group chat's apps and their states (Teams' chat entitlements:
/// `GET {mt}/beta/chats/{threadId}/apps/chatentitlements`).
pub async fn chat_apps(client: &TeamsClient, thread_id: &str) -> Result<Vec<(String, String)>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let v: serde_json::Value = client
        .http()
        .get(format!(
            "{base}/beta/chats/{thread_id}/apps/chatentitlements"
        ))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("Chat apps")?
        .json()
        .await?;
    Ok(entitlements_from(&v))
}

/// A team's apps and states, for a channel (Teams' team app definitions:
/// `GET {mt}/beta/teams/{teamThreadId}/apps/definitions`, each with its
/// `state`; the General channel's thread is the team's).
pub async fn channel_apps(client: &TeamsClient, thread_id: &str) -> Result<Vec<(String, String)>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let v: serde_json::Value = client
        .http()
        .get(format!("{base}/beta/teams/{thread_id}/apps/definitions"))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("Team apps")?
        .json()
        .await?;
    Ok(entitlements_from(&v))
}

/// (app id, state) pairs from a chat entitlements reply.
pub fn entitlements_from(v: &serde_json::Value) -> Vec<(String, String)> {
    v.pointer("/value/entitlements")
        .or_else(|| v.get("value").filter(|x| x.is_array()))
        .or_else(|| v.get("entitlements"))
        .or(Some(v).filter(|x| x.is_array()))
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
        .filter_map(|e| {
            Some((
                e.get("id")?.as_str()?.to_string(),
                e.get("state")
                    .and_then(|s| s.as_str())
                    .unwrap_or_default()
                    .to_string(),
            ))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn content_path_as_teams() {
        let smb = serde_json::json!({"isTeamsSmb": true, "eduLicenseSkuAndCategory": ""});
        assert_eq!(
            content_path(
                "Enterprise/NewStoreCustomization/storev3",
                Some(&smb),
                249198
            ),
            "apps/smb/Enterprise/NewStoreCustomization/storev3.json?ts=249198"
        );
        assert_eq!(
            content_path("storev2?v=2", None, 7),
            "apps/storev2.json?v=2&ts=7"
        );
    }

    #[test]
    fn collections_merge_and_rank_as_teams() {
        // Shaped as storev3 on 2026-11-09: abcbot1 lists apps, copilotplugins
        // links its category, popularapps takes its title from the defaults.
        let content = serde_json::json!({"collectionsList": [
            {"id": "abcbot1", "title": "Simplify scheduling meetings", "isHidden": true, "itemsList": [{"id": "a"}, {"id": "b"}, {"id": "c"}]},
            {"id": "copilotplugins", "title": "Agents", "itemsList": [{"id": "copilotplugins"}]},
            {"id": "popularapps", "isHidden": true, "itemsList": [{"id": "popularapps"}]},
            {"id": "productivity", "title": "_extensibility_apps_store_category_productivity", "itemsList": [{"id": "productivity"}]},
            {"id": "FAproductivity", "isHidden": true, "itemsList": [{"id": "productivity", "type": "linkedCollectionId"}, {"id": "helio", "type": "featured"}, {"id": "fuze", "type": "featured"}]}
        ]});
        let all = collections_from(&content);
        let get = |id: &str| all.iter().find(|c| c.id == id).unwrap();
        assert_eq!(get("abcbot1").items, ["a", "b", "c"]);
        assert_eq!(get("copilotplugins").title, "Agents");
        assert_eq!(get("productivity").title, "Productivity tools");
        // Its featured apps lead the ranked category ("Helio", "Fuze").
        let p = get("productivity");
        assert_eq!(
            (p.featured.as_slice(), p.featured_by.as_str()),
            (
                ["helio".to_string(), "fuze".to_string()].as_slice(),
                "FAproductivity"
            )
        );
        let ranked: HashMap<String, Vec<Ranked>> = [(
            "productivity".to_string(),
            vec![Ranked {
                id: "polls".into(),
                ..Default::default()
            }],
        )]
        .into();
        assert_eq!(
            collection_ids(p, &ranked, &HashMap::new()),
            ["helio", "fuze", "polls"]
        );
        assert_eq!(get("popularapps").title, "Popular on Teams");
        assert_eq!(get("popularapps").linked, ["popularApps"]);
        // Birdy-AI was ranked, so it led "Simplify scheduling meetings".
        assert_eq!(
            sort_by_rank(
                &["a".into(), "b".into(), "c".into()],
                &["x".into(), "c".into()]
            ),
            ["c", "a", "b"]
        );
    }

    #[test]
    fn chat_entitlements_read_with_their_states() {
        let v = serde_json::json!({"value": {"entitlements": [
            {"id": "1c4340de-2a85-40e5-8eb0-4f295368978b", "state": "Installed"},
            {"id": "4046041d-19bb-4afe-a8d6-f464d894f139", "state": "PreConsented"}
        ], "definitions": []}});
        assert_eq!(
            entitlements_from(&v),
            [
                (
                    "1c4340de-2a85-40e5-8eb0-4f295368978b".to_string(),
                    "Installed".to_string()
                ),
                (
                    "4046041d-19bb-4afe-a8d6-f464d894f139".to_string(),
                    "PreConsented".to_string()
                )
            ]
        );
    }

    #[test]
    fn bots_say_whether_they_only_notify() {
        // Polls' definition (its bot only notifies, so Teams shows "About
        // this bot" after adding it).
        let polls = serde_json::json!({"bots": [{"id": "fd931076-bbfb-4a38-a85c-1f0fb5b61bee", "isNotificationOnly": true, "scopes": ["GroupChat", "Team"]}]});
        assert_eq!(bot_of(&polls), Some(("fd931076-bbfb-4a38-a85c-1f0fb5b61bee".to_string(), true)));
        assert_eq!(bot_of(&serde_json::json!({})), None);
    }

    #[test]
    fn bots_by_scope() {
        let jira = serde_json::json!({"bots": [{"scopes": ["Team", "Personal", "GroupChat"]}]});
        let workday = serde_json::json!({"bots": [{"scopes": ["Personal", "Copilot"]}]});
        assert!(bot_supports(&jira, "groupchat") && bot_supports(&jira, "team"));
        assert!(!bot_supports(&workday, "groupchat"));
    }
}
