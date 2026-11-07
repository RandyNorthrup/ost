//! A channel's tabs (Graph `/teams/{id}/channels/{id}/tabs`): Page (a
//! Loop page), Notes (OneNote) and any apps added to the channel, with
//! what each shows.

use anyhow::{Context, Result, bail};
use serde::Serialize;

use super::client::TeamsClient;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Tab {
    pub id: String,
    /// The tab's name ("Page", "Notes", ...).
    pub name: String,
    /// The app behind it ("Channel Pages", "OneNote", "Files", ...).
    pub app: String,
    /// What the tab shows, when it's a page on Microsoft's own hosts
    /// (https only); empty otherwise.
    pub url: String,
    /// The tab's Teams link (Copy link to tab).
    pub link: String,
    /// Its place among the channel's tabs (Teams' sortOrderIndex).
    pub order: i64,
}

/// What a tab's page may be told about where it is, as Teams fills its
/// `{placeholders}` (the tab context).
#[derive(Debug, Clone, Default)]
pub struct TabContext {
    pub tenant: String,
    pub upn: String,
    pub team: String,
    pub channel: String,
    pub channel_name: String,
}

/// Fill a tab's content URL as Teams does: each `{name}` it knows becomes
/// its (URL-encoded) value; unknown ones become empty.
fn fill(url: &str, ctx: &TabContext, entity_id: &str) -> String {
    let enc = |v: &str| url::form_urlencoded::byte_serialize(v.as_bytes()).collect::<String>();
    let session = uuid::Uuid::new_v4().to_string();
    let mut out = String::new();
    let mut rest = url;
    while let Some(i) = rest.find('{') {
        let Some(j) = rest[i..].find('}') else { break };
        out.push_str(&rest[..i]);
        let value = match &rest[i + 1..i + j] {
            "locale" => "en-us".to_string(),
            "tid" | "tenantId" => ctx.tenant.clone(),
            "upn" | "userPrincipalName" | "loginHint" => ctx.upn.clone(),
            "groupId" | "teamId" => ctx.team.clone(),
            "channelId" => ctx.channel.clone(),
            "channelName" => ctx.channel_name.clone(),
            "entityId" => entity_id.to_string(),
            "theme" => "default".to_string(),
            "hostClientType" => "web".to_string(),
            "channelType" | "teamType" => "Standard".to_string(),
            "ringId" => "general".to_string(),
            "sessionId" | "appSessionId" => session.clone(),
            _ => String::new(),
        };
        out.push_str(&enc(&value));
        rest = &rest[i + j + 1..];
    }
    out.push_str(rest);
    out
}

/// Only Microsoft 365 pages over https are shown in a tab, once filled in.
fn safe_url(url: &str) -> String {
    let ok = !url.contains('{')
        && reqwest::Url::parse(url).is_ok_and(|u| {
            u.scheme() == "https"
                && u.host_str().is_some_and(|h| {
                    h.ends_with(".sharepoint.com")
                        || h.ends_with(".cloud.microsoft")
                        || h == "www.onenote.com"
                        || h.ends_with(".office.com")
                })
        });
    if ok { url.to_string() } else { String::new() }
}

fn tabs_from(v: &serde_json::Value, ctx: &TabContext) -> Vec<Tab> {
    let s = |t: &serde_json::Value, p: &str| {
        t.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let mut tabs: Vec<Tab> = v
        .get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(|t| {
            let name = s(t, "/displayName");
            (!name.is_empty()).then(|| Tab {
                id: s(t, "/id"),
                url: safe_url(&fill(
                    &s(t, "/configuration/contentUrl"),
                    ctx,
                    &s(t, "/configuration/entityId"),
                )),
                app: s(t, "/teamsApp/displayName"),
                link: teams_link(&s(t, "/webUrl")),
                order: s(t, "/sortOrderIndex").parse().unwrap_or(i64::MAX),
                name,
            })
        })
        .collect();
    tabs.sort_by_key(|t| t.order);
    tabs
}

/// A tab's link, when it's a Teams link (https, teams.microsoft.com).
fn teams_link(url: &str) -> String {
    let ok = reqwest::Url::parse(url)
        .is_ok_and(|u| u.scheme() == "https" && u.host_str() == Some("teams.microsoft.com"));
    if ok { url.to_string() } else { String::new() }
}

/// The Graph path of a channel (checked ids), for its tabs.
fn channel_path(team_id: &str, channel_id: &str) -> Result<String> {
    if uuid::Uuid::parse_str(team_id).is_err() {
        bail!("Not a team");
    }
    let ok = channel_id.starts_with("19:")
        && channel_id.len() < 200
        && channel_id[3..]
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.@=".contains(&b));
    if !ok {
        bail!("Not a channel");
    }
    let channel = channel_id.replace(':', "%3A").replace('@', "%40");
    Ok(format!("/teams/{team_id}/channels/{channel}/tabs"))
}

/// A tab id as Graph gives it (a GUID, or Teams' own ids for built-in tabs).
fn tab_id(id: &str) -> Result<&str> {
    let ok = !id.is_empty()
        && id.len() < 100
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b));
    if ok { Ok(id) } else { bail!("Not a tab") }
}

/// Rename a tab (Rename).
pub async fn rename(
    client: &TeamsClient,
    team_id: &str,
    channel_id: &str,
    tab: &str,
    name: &str,
) -> Result<()> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 128 {
        bail!("A tab needs a name of up to 128 characters");
    }
    let path = format!("{}/{}", channel_path(team_id, channel_id)?, tab_id(tab)?);
    client
        .graph_beta_patch(&path, &serde_json::json!({ "displayName": name }))
        .await?;
    Ok(())
}

/// The places to give tabs so that tab `from` moves to index `to` of
/// `tabs` (in their current order): just the two changed values when
/// they differ, else the whole list renumbered (tabs added together can
/// share one place, and then swapping changes nothing).
pub fn reorder(tabs: &[(String, i64)], from: usize, to: usize) -> Vec<(String, i64)> {
    let mut moved: Vec<(String, i64)> = tabs.to_vec();
    if from >= moved.len() || to >= moved.len() || from == to {
        return Vec::new();
    }
    let distinct = moved[from].1 != moved[to].1 && (from as i64 - to as i64).abs() == 1;
    if distinct {
        let (a, b) = (moved[from].clone(), moved[to].clone());
        return vec![(a.0, b.1), (b.0, a.1)];
    }
    let t = moved.remove(from);
    moved.insert(to, t);
    moved
        .into_iter()
        .enumerate()
        .map(|(k, (id, _))| (id, (k as i64 + 1) * 100))
        .collect()
}

/// Move a channel's tab one place left or right among its own tabs (not
/// Files, which is Shared), as Teams does: through Teams' middle tier
/// (its pinned tabs, PATCHed with the tabs whose places change); Graph
/// takes a tab's place but ignores it.
pub async fn move_tab(
    client: &TeamsClient,
    channel_id: &str,
    tab: &str,
    right: bool,
) -> Result<()> {
    // Checked as a channel id (the team id is not needed here).
    channel_path("00000000-0000-0000-0000-000000000000", channel_id)?;
    let tab = tab_id(tab)?;
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let list: serde_json::Value = client
        .http()
        .get(format!("{base}/v1.0/channels/{channel_id}/tabs"))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let mut tabs: Vec<serde_json::Value> = list
        .get("value")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
        .into_iter()
        // Files (Shared) is fixed; its id is its app's.
        .filter(|t| t.get("id") != t.get("appId"))
        .collect();
    let order =
        |t: &serde_json::Value| t.get("order").and_then(|o| o.as_f64()).unwrap_or(f64::MAX) as i64;
    tabs.sort_by_key(order);
    let id_of = |t: &serde_json::Value| {
        t.get("id")
            .and_then(|i| i.as_str())
            .map(|i| i.trim_start_matches("tab::").to_string())
            .unwrap_or_default()
    };
    let i = tabs
        .iter()
        .position(|t| id_of(t) == tab)
        .context("No such tab")?;
    let j = if right { Some(i + 1) } else { i.checked_sub(1) }
        .filter(|j| *j < tabs.len())
        .context("The tab is already at that end")?;
    let places = reorder(
        &tabs
            .iter()
            .map(|t| (id_of(t), order(t)))
            .collect::<Vec<_>>(),
        i,
        j,
    );
    let changed: Vec<serde_json::Value> = places
        .iter()
        .filter_map(|(id, place)| {
            let mut t = tabs.iter().find(|t| id_of(t) == *id)?.clone();
            t["order"] = serde_json::json!(*place as f64);
            Some(t)
        })
        .collect();
    client
        .http()
        .patch(format!("{base}/beta/channels/{channel_id}/tabs"))
        .bearer_auth(&token)
        .json(&changed)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// Remove a tab from the channel (Remove).
pub async fn remove(
    client: &TeamsClient,
    team_id: &str,
    channel_id: &str,
    tab: &str,
) -> Result<()> {
    let path = format!("{}/{}", channel_path(team_id, channel_id)?, tab_id(tab)?);
    client.graph_delete(&path).await?;
    Ok(())
}

/// The tabs of a channel, in the channel's order (Graph beta, which has
/// each tab's place).
pub async fn channel_tabs(
    client: &TeamsClient,
    team_id: &str,
    channel_id: &str,
    channel_name: &str,
) -> Result<Vec<Tab>> {
    let path = channel_path(team_id, channel_id)?;
    let v: serde_json::Value = client
        .graph_beta(&format!("{path}?$expand=teamsApp"), None)
        .await?
        .json()
        .await?;
    let ctx = TabContext {
        tenant: client.tenant_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
        team: team_id.to_string(),
        channel: channel_id.to_string(),
        channel_name: channel_name.to_string(),
    };
    Ok(tabs_from(&v, &ctx))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tabs_keep_microsoft_pages_only() {
        let v = serde_json::json!({"value": [
            {"id": "5", "displayName": "Notes", "sortOrderIndex": "10000", "teamsApp": {"displayName": "OneNote"},
             "webUrl": "https://teams.microsoft.com/l/entity/x", "configuration": {}},
            {"id": "1", "displayName": "Page", "sortOrderIndex": "10", "teamsApp": {"displayName": "Channel Pages"},
             "webUrl": "https://evil.example/l/channel",
             "configuration": {"contentUrl": "https://contoso.sharepoint.com/:fl:/r/sites/x/General/Page.loop?web=1"}},
            {"id": "2", "displayName": "Odd", "teamsApp": {"displayName": "Website"},
             "configuration": {"contentUrl": "https://evil.example/sharepoint.com"}},
            {"id": "3", "displayName": "Plain", "teamsApp": {"displayName": "X"},
             "configuration": {"contentUrl": "http://contoso.sharepoint.com/x"}},
            {"id": "4", "displayName": ""}
        ]});
        let t = tabs_from(&v, &TabContext::default());
        assert_eq!(t.len(), 4);
        // In the channel's order; tabs without a place go last.
        assert_eq!(t[0].name, "Page");
        assert_eq!(
            (t[1].name.as_str(), t[1].link.as_str()),
            ("Notes", "https://teams.microsoft.com/l/entity/x")
        );
        assert!(t[0].link.is_empty(), "links only to Teams");
        let t: Vec<Tab> = t.into_iter().filter(|x| x.name != "Notes").collect();
        assert_eq!(
            (t[0].name.as_str(), t[0].app.as_str()),
            ("Page", "Channel Pages")
        );
        assert!(t[0].url.starts_with("https://contoso.sharepoint.com/"));
        assert!(t[1].url.is_empty() && t[2].url.is_empty());
    }
}

#[cfg(test)]
mod id_tests {
    use super::*;

    #[test]
    fn content_urls_are_filled_as_teams_does() {
        let ctx = TabContext {
            tenant: "t-1".into(),
            upn: "a b@x.com".into(),
            team: "g-1".into(),
            channel: "19:c@thread.tacv2".into(),
            channel_name: "General".into(),
        };
        let u = fill(
            "https://www.onenote.com/teams/ChannelNotes?ui={locale}&tenantId={tid}&upn={upn}&groupId={groupId}&entityId={entityId}&x={unknown}",
            &ctx,
            "NOTES",
        );
        assert_eq!(
            u,
            "https://www.onenote.com/teams/ChannelNotes?ui=en-us&tenantId=t-1&upn=a+b%40x.com&groupId=g-1&entityId=NOTES&x="
        );
        assert_eq!(safe_url(&u), u);
        assert!(safe_url("https://x/{left}").is_empty() && safe_url("http://x/").is_empty());
    }

    #[test]
    fn moves_swap_places_or_renumber() {
        let t = |v: &[(&str, i64)]| {
            v.iter()
                .map(|(a, b)| (a.to_string(), *b))
                .collect::<Vec<_>>()
        };
        // Distinct neighbours: just the two swap.
        assert_eq!(
            reorder(&t(&[("p", 10), ("n", 50), ("a", 90)]), 0, 1),
            t(&[("p", 50), ("n", 10)])
        );
        // Shared places: the list is renumbered in the new order.
        assert_eq!(
            reorder(&t(&[("p", 10), ("a", 90), ("b", 90)]), 1, 2),
            t(&[("p", 100), ("b", 200), ("a", 300)])
        );
        assert!(reorder(&t(&[("p", 10)]), 0, 1).is_empty());
    }

    #[test]
    fn ids_are_checked_before_they_reach_a_path() {
        assert!(tab_id("7d08c880-6b49-43d4-b45c-e38c27b69726").is_ok());
        assert!(tab_id("tab::x").is_err() && tab_id("../x").is_err() && tab_id("").is_err());
        assert!(channel_path("not-a-team", "19:x@thread.tacv2").is_err());
        assert!(channel_path("1fac3ae3-c9c0-4ddb-90bb-58f52209c181", "19:a/b@thread").is_err());
        assert_eq!(
            channel_path("1fac3ae3-c9c0-4ddb-90bb-58f52209c181", "19:ab@thread.tacv2").unwrap(),
            "/teams/1fac3ae3-c9c0-4ddb-90bb-58f52209c181/channels/19%3Aab%40thread.tacv2/tabs"
        );
    }
}
