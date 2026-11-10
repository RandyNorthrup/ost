//! Creating and joining teams as Teams does (Your teams and channels'
//! Create team / Join Team; read from Teams' client code and checked
//! against its requests on winpc, 2026-11-09):
//!
//! - From scratch: `POST {mt}/beta/teams/create` (Teams' createTeam; its
//!   provisioning v2 route is off for this tenant).
//! - From a template: the template list and details from the provisioning
//!   service (`teamtemplates/v1.0/…`), then `POST {provisioning}/team`.
//! - From another team: `POST {provisioning}/groups/{group}/clone/v2` (the
//!   template service clone, on for this tenant).
//! - From a group: your groups from `GET {mt}/beta/teams/usergroups`, then
//!   `PUT {mt}/beta/teams/migrateGroup/{group}`.
//! - Join: suggestions `GET {mt}/beta/teams/suggested`, search `GET
//!   {mt}/beta/teams/find`, `POST {mt}/beta/teams/joinRequest/{group}`, and
//!   `POST {mt}/beta/teams/joinByCode` with the code as a JSON string.

use anyhow::Result;

use super::channels::{middle_tier, provisioning};
use super::client::TeamsClient;

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes())
        .collect::<String>()
        .replace('+', "%20")
}

/// Teams' Create a team (from scratch) body: the name, description and
/// privacy; the first channel's name unless it is General (Teams leaves
/// `topicThreadTopic` out then).
pub fn scratch_body(name: &str, description: &str, public: bool, first_channel: &str) -> serde_json::Value {
    let mut b = serde_json::json!({
        "displayName": name.trim(),
        "description": description,
        "accessType": if public { "Public" } else { "Private" },
        "isTenantWide": false,
        "sensitivityLabelId": null,
        "validationRequired": false,
    });
    if first_channel.trim().to_lowercase() != "general" {
        b["topicThreadTopic"] = serde_json::json!(first_channel);
    }
    b
}

/// What a create gives back: the new team's group and thread ids (either
/// may be missing until the team is provisioned).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Created {
    pub group_id: String,
    pub thread_id: String,
}

fn created_from(v: &serde_json::Value) -> Created {
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    let thread = [s("threadId"), s("skypeThreadId"), s("id")]
        .into_iter()
        .find(|t| t.starts_with("19:"))
        .unwrap_or_default();
    let group = [s("groupId"), s("teamId"), s("internalId"), s("id")]
        .into_iter()
        .find(|g| g.len() == 36 && !g.starts_with("19:"))
        .unwrap_or_default();
    Created { group_id: group, thread_id: thread }
}

async fn send(req: reqwest::RequestBuilder, what: &str) -> Result<serde_json::Value> {
    let resp = req.send().await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!("{what}: {status} {}", text.chars().take(200).collect::<String>());
    }
    Ok(serde_json::from_str(&text).unwrap_or(serde_json::Value::Null))
}

/// Create a team from scratch.
pub async fn create_from_scratch(client: &TeamsClient, body: &serde_json::Value) -> Result<Created> {
    let (base, token) = middle_tier(client).await?;
    let v = send(client.http().post(format!("{base}/beta/teams/create")).bearer_auth(&token).json(body), "Create team").await?;
    Ok(created_from(&v))
}

/// A team template as the gallery lists it.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Template {
    pub id: String,
    pub name: String,
    pub short_description: String,
    pub description: String,
    pub icon: String,
    pub category: String,
    pub channels: u64,
    pub apps: u64,
    /// Its details' path (`@odata.id`, "/api/teamtemplates/…").
    pub path: String,
    pub visibility: String,
}

pub fn templates_from(v: &serde_json::Value) -> Vec<Template> {
    let s = |x: &serde_json::Value, k: &str| x.get(k).and_then(|v| v.as_str()).unwrap_or_default().to_string();
    v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|t| Template {
            id: s(t, "id"),
            name: s(t, "name"),
            short_description: s(t, "shortDescription"),
            description: s(t, "description"),
            icon: s(t, "iconUri"),
            category: t["categories"].as_array().and_then(|c| c.first()).and_then(|c| c.as_str()).unwrap_or_default().to_string(),
            channels: t["channelCount"].as_u64().unwrap_or(0),
            apps: t["appCount"].as_u64().unwrap_or(0),
            path: s(t, "@odata.id"),
            visibility: s(t, "visibility"),
        })
        .collect()
}

/// Teams' templates for your language (`teamtemplates/v1.0/{locale}`).
pub async fn templates(client: &TeamsClient, locale: &str) -> Result<Vec<Template>> {
    let (base, token) = provisioning(client).await?;
    let v = send(
        client.http().get(format!("{base}/teamtemplates/v1.0/{}", locale.to_lowercase())).bearer_auth(&token),
        "Templates",
    )
    .await?;
    Ok(templates_from(&v))
}

/// A template's channels and apps (its `teamDefinition`), as the details
/// dialog shows them.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct TemplateDetails {
    pub id: String,
    pub name: String,
    pub description: String,
    pub locale: String,
    /// {id, displayName}, in the template's order.
    pub channels: Vec<serde_json::Value>,
    /// The same, as the details list them (General, then by name).
    pub listed_channels: Vec<serde_json::Value>,
    /// The apps the details list: {id, name, icon, items: [SharePoint
    /// lists or pages it adds]}.
    pub apps: Vec<serde_json::Value>,
    /// Every app the template installs (the create body sends them all).
    pub app_ids: Vec<String>,
    pub visibility: String,
}

pub fn template_details_from(v: &serde_json::Value, locale: &str) -> TemplateDetails {
    let v = &v["value"];
    let def = &v["teamDefinition"];
    let channels: Vec<serde_json::Value> = def["channels"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| serde_json::json!({ "id": c["id"], "displayName": c["displayName"] }))
        .collect();
    // The details list them General first, then by name; Customize
    // channels and the create body keep the template's order.
    let mut listed = channels.clone();
    listed.sort_by(|a, b| {
        let g = |c: &serde_json::Value| c["id"].as_str() != Some("General");
        let n = |c: &serde_json::Value| c["displayName"].as_str().unwrap_or_default().to_lowercase();
        g(a).cmp(&g(b)).then_with(|| n(a).cmp(&n(b)))
    });
    // Apps: the template's apps, each with the SharePoint lists or pages
    // it adds (extendedProperties.sharePointTemplateInfo), as Teams' details
    // list them; names and icons come from the app definitions.
    let assets: Vec<&serde_json::Value> = v
        .pointer("/extendedProperties/sharePointTemplateInfo/sharePointAssets")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .flat_map(|c| c["sharePointAssetList"].as_array().into_iter().flatten())
        .collect();
    let apps: Vec<serde_json::Value> = def["apps"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|a| {
            let id = a["id"].as_str().unwrap_or_default();
            let items: Vec<String> = assets
                .iter()
                .filter(|x| x["sharePointAssetAppId"].as_str() == Some(id))
                .filter_map(|x| x["sharePointAssetName"].as_str().map(str::to_string))
                .collect();
            serde_json::json!({ "id": id, "name": "", "icon": "", "items": items })
        })
        .collect();
    TemplateDetails {
        id: v["templateId"].as_str().unwrap_or_default().to_string(),
        name: v["displayName"].as_str().unwrap_or_default().to_string(),
        description: v["description"].as_str().unwrap_or_default().to_string(),
        locale: locale.to_string(),
        channels,
        listed_channels: listed,
        app_ids: def["apps"].as_array().into_iter().flatten().filter_map(|a| a["id"].as_str().map(str::to_string)).collect(),
        apps,
        visibility: def["visibility"].as_str().unwrap_or("Private").to_string(),
    }
}

/// A template's details: Teams drops "/api/" from its `@odata.id`. Its
/// apps get their names and icons from the middle tier's definitions, and
/// are listed by name.
pub async fn template_details(client: &TeamsClient, path: &str, locale: &str) -> Result<TemplateDetails> {
    let (base, token) = provisioning(client).await?;
    let rel = path.trim_start_matches('/').trim_start_matches("api/");
    let v = send(client.http().get(format!("{base}/{rel}")).bearer_auth(&token), "Template").await?;
    let mut d = template_details_from(&v, locale);
    let ids: Vec<String> = d.apps.iter().filter_map(|a| a["id"].as_str().map(str::to_string)).collect();
    if let Ok(defs) = definitions(client, &ids).await {
        name_apps(&mut d.apps, &defs);
    }
    Ok(d)
}

/// Fill in apps' names and icons from definitions ({id, name,
/// largeImageUrl}) and sort them by name; apps without a definition stay
/// out, as Teams shows only apps it knows.
pub fn name_apps(apps: &mut Vec<serde_json::Value>, defs: &[serde_json::Value]) {
    for a in apps.iter_mut() {
        let id = a["id"].as_str().unwrap_or_default().to_lowercase();
        if let Some(d) = defs.iter().find(|d| d["id"].as_str().map(str::to_lowercase).as_deref() == Some(id.as_str())) {
            a["name"] = d["name"].clone();
            a["icon"] = serde_json::json!(
                [d["largeImageUrl"].as_str(), d["smallImageUrl"].as_str()].into_iter().flatten().find(|u| !u.is_empty()).unwrap_or_default()
            );
        }
    }
    apps.retain(|a| a["name"].as_str().is_some_and(|n| !n.is_empty()));
    apps.sort_by_key(|a| a["name"].as_str().unwrap_or_default().to_lowercase());
}

/// App definitions from the middle tier (Teams' batchedDefinitions).
pub async fn definitions(client: &TeamsClient, ids: &[String]) -> Result<Vec<serde_json::Value>> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let (base, token) = middle_tier(client).await?;
    let v = send(client.http().post(format!("{base}/beta/users/apps/batchedDefinitions")).bearer_auth(&token).json(&ids), "Apps").await?;
    Ok(v.get("value").cloned().unwrap_or(v).as_array().cloned().unwrap_or_default())
}

/// Teams' create-from-template body.
pub fn template_body(
    template_id: &str,
    locale: &str,
    name: &str,
    description: &str,
    public: bool,
    channels: &[serde_json::Value],
    app_ids: &[String],
) -> serde_json::Value {
    serde_json::json!({
        "templateId": template_id,
        "displayName": name.trim(),
        "description": description,
        "visibility": if public { "Public" } else { "Private" },
        "channels": channels.iter().map(|c| serde_json::json!({ "id": c["id"], "displayName": c["displayName"] })).collect::<Vec<_>>(),
        "apps": app_ids.iter().map(|a| serde_json::json!({ "id": a })).collect::<Vec<_>>(),
        "isTenantWide": false,
        "sensitivityLabelId": null,
        "locale": locale,
    })
}

pub async fn create_from_template(client: &TeamsClient, body: &serde_json::Value) -> Result<Created> {
    let (base, token) = provisioning(client).await?;
    let v = send(client.http().post(format!("{base}/team")).bearer_auth(&token).json(body), "Create team").await?;
    Ok(created_from(&v))
}

/// What a copy of a team takes from the original (Teams' checkboxes;
/// channels and apps always).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ClonePick {
    pub tabs: bool,
    pub settings: bool,
    pub members: bool,
}

/// Teams' clone body for the template service.
pub fn clone_body(group_id: &str, owner: &str, name: &str, description: &str, public: bool, pick: ClonePick) -> serde_json::Value {
    serde_json::json!({
        "displayName": name.trim(),
        "description": description,
        "ownerObjectId": owner,
        "teamGroupId": group_id,
        "visibility": if public { "Public" } else { "Private" },
        "sensitivityLabelId": "",
        "includeRoster": pick.members,
        "includeChannels": true,
        "includeAppEntitlements": true,
        "includeSettings": pick.settings,
        "includeTabs": pick.tabs,
    })
}

pub async fn clone_team(client: &TeamsClient, group_id: &str, body: &serde_json::Value) -> Result<Created> {
    let (base, token) = provisioning(client).await?;
    let v = send(
        client.http().post(format!("{base}/groups/{}/clone/v2", enc(group_id))).bearer_auth(&token).json(body),
        "Create team",
    )
    .await?;
    Ok(created_from(&v))
}

/// A Microsoft 365 group you own that has no team yet.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub description: String,
    pub mail: String,
    pub members: u64,
}

pub fn groups_from(v: &serde_json::Value) -> Vec<Group> {
    let list = v.as_array().or_else(|| v["value"].as_array()).cloned().unwrap_or_default();
    list.iter()
        .map(|g| {
            let s = |k: &str| g.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
            Group {
                id: [s("groupId"), s("id")].into_iter().find(|x| !x.is_empty()).unwrap_or_default(),
                name: s("displayName"),
                description: s("description"),
                mail: [s("smtpAddress"), s("mail")].into_iter().find(|x| !x.is_empty()).unwrap_or_default(),
                members: g.get("memberCount").and_then(|x| x.as_u64()).unwrap_or(0),
            }
        })
        .collect()
}

pub async fn my_groups(client: &TeamsClient) -> Result<Vec<Group>> {
    let (base, token) = middle_tier(client).await?;
    let v = send(client.http().get(format!("{base}/beta/teams/usergroups?teamType=undefined")).bearer_auth(&token), "Groups").await?;
    Ok(groups_from(&v))
}

/// Teams' create-from-group body (teamType Team = 0).
pub fn group_body(group: &Group) -> serde_json::Value {
    serde_json::json!({
        "groupId": group.id,
        "teamType": 0,
        "displayName": group.name,
        "description": group.description,
        "smtpAddress": group.mail,
    })
}

pub async fn create_from_group(client: &TeamsClient, group: &Group) -> Result<Created> {
    let (base, token) = middle_tier(client).await?;
    let v = send(
        client.http().put(format!("{base}/beta/teams/migrateGroup/{}", enc(&group.id))).bearer_auth(&token).json(&group_body(group)),
        "Create team",
    )
    .await?;
    let mut c = created_from(&v);
    if c.group_id.is_empty() {
        c.group_id = group.id.clone();
    }
    Ok(c)
}

/// A team the join gallery offers (suggested or found).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct JoinableTeam {
    pub group_id: String,
    pub name: String,
    pub description: String,
    pub private: bool,
    pub members: u64,
    /// "NotJoined", "Pending" or "Joined".
    pub status: String,
    /// People you know in it: {id, name, email}.
    pub people: Vec<serde_json::Value>,
}

pub fn joinable_from(v: &serde_json::Value) -> (Vec<JoinableTeam>, String) {
    let teams = v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|t| {
            let s = |k: &str| t.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
            let access = t.get("accessType").map(|a| a.as_str().map(str::to_string).unwrap_or_else(|| a.to_string())).unwrap_or_default();
            JoinableTeam {
                group_id: [s("groupId"), s("id")].into_iter().find(|x| !x.is_empty()).unwrap_or_default(),
                name: s("displayName"),
                description: s("description"),
                private: access.eq_ignore_ascii_case("private") || access == "1",
                members: t.get("memberCount").and_then(|x| x.as_u64()).unwrap_or(0),
                status: Some(s("joinStatus")).filter(|x| !x.is_empty()).unwrap_or_else(|| "NotJoined".into()),
                people: t["relevantUsers"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|u| serde_json::json!({ "id": u["id"], "name": u["displayName"], "email": u["email"] }))
                    .collect(),
            }
        })
        .collect();
    (teams, v["skipToken"].as_str().unwrap_or_default().to_string())
}

pub async fn suggested(client: &TeamsClient) -> Result<Vec<JoinableTeam>> {
    let (base, token) = middle_tier(client).await?;
    let v = send(client.http().get(format!("{base}/beta/teams/suggested?accessType=All&enableFallback=true")).bearer_auth(&token), "Teams for you").await?;
    Ok(joinable_from(&v).0)
}

pub async fn find(client: &TeamsClient, keywords: &str, skip: &str) -> Result<(Vec<JoinableTeam>, String)> {
    let (base, token) = middle_tier(client).await?;
    let v = send(
        client
            .http()
            .get(format!(
                "{base}/beta/teams/find?keywords={}&accessType=All&enableKeywordSearch=false&top=100&skipToken={}",
                enc(keywords),
                enc(skip)
            ))
            .bearer_auth(&token),
        "Search teams",
    )
    .await?;
    Ok(joinable_from(&v))
}

/// Join a public team, or ask to join a private one.
pub async fn join(client: &TeamsClient, group_id: &str) -> Result<serde_json::Value> {
    let (base, token) = middle_tier(client).await?;
    send(
        client
            .http()
            .post(format!("{base}/beta/teams/joinRequest/{}", enc(group_id)))
            .bearer_auth(&token)
            .header(reqwest::header::CONTENT_TYPE, "application/json"),
        "Join team",
    )
    .await
}

/// Join with a team code: Teams posts the code as a JSON string and gets
/// {skypeThreadId, siteInfo: {groupId}, isTeamOwnerApprovalRequired}.
pub async fn join_by_code(client: &TeamsClient, code: &str) -> Result<serde_json::Value> {
    let (base, token) = middle_tier(client).await?;
    send(
        client
            .http()
            .post(format!("{base}/beta/teams/joinByCode?restrictJoinToPublicTeam=false"))
            .bearer_auth(&token)
            .json(&serde_json::Value::String(code.trim().to_string())),
        "Join team",
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scratch_body_is_teams() {
        let b = scratch_body(" OST draft ", "", false, "General");
        assert_eq!(
            b.to_string(),
            r#"{"accessType":"Private","description":"","displayName":"OST draft","isTenantWide":false,"sensitivityLabelId":null,"validationRequired":false}"#
        );
        let b = scratch_body("T", "d", true, "Planning");
        assert_eq!((b["accessType"].as_str(), b["topicThreadTopic"].as_str()), (Some("Public"), Some("Planning")));
    }

    #[test]
    fn templates_read_as_teams() {
        let v = serde_json::json!({"value": [{"id": "com.microsoft.teams.template.ManageAProject", "locale": "en-US", "name": "Manage a Project",
            "description": "Manage tasks…", "shortDescription": "Coordinate your project.",
            "iconUri": "https://statics.teams.cdn.office.net/evergreen-assets/teamtemplates/icons/project_management.svg",
            "channelCount": 4, "appCount": 7, "visibility": "Private", "categories": ["General"],
            "@odata.id": "/api/teamtemplates/v1.0/com.microsoft.teams.template.ManageAProject/Public/en-US"}]});
        let t = &templates_from(&v)[0];
        assert_eq!((t.name.as_str(), t.category.as_str(), t.channels, t.apps), ("Manage a Project", "General", 4, 7));
        let d = serde_json::json!({"value": {"templateId": "x", "displayName": "Manage a Project", "description": "d",
            "teamDefinition": {"visibility": "Private", "channels": [
                {"id": "General", "displayName": "General", "tabs": [{"teamsAppId": "app1", "name": "Power Automate"}]},
                {"id": "c1", "displayName": "Planning", "tabs": [{"teamsAppId": "app2", "name": "Planning Notes"}]}],
              "apps": [{"id": "app2"}, {"id": "lists"}, {"id": "unknown"}]},
            "extendedProperties": {"sharePointTemplateInfo": {"sharePointAssets": [{"channelId": "General", "sharePointAssetList": [
                {"sharePointAssetAppId": "lists", "sharePointAssetName": "Issue Tracker"},
                {"sharePointAssetAppId": "lists", "sharePointAssetName": "Project Tracker"}]}]}}}});
        let mut d = template_details_from(&d, "en-US");
        assert_eq!(d.channels.len(), 2);
        name_apps(&mut d.apps, &[serde_json::json!({"id": "APP2", "name": "OneNote", "largeImageUrl": "https://x/o.png"}), serde_json::json!({"id": "lists", "name": "Lists"})]);
        assert_eq!(d.apps.iter().map(|a| a["name"].as_str().unwrap()).collect::<Vec<_>>(), vec!["Lists", "OneNote"]);
        assert_eq!(d.apps[0]["items"], serde_json::json!(["Issue Tracker", "Project Tracker"]));
        let b = template_body("x", "en-US", "T", "", false, &d.channels, &d.app_ids);
        assert_eq!(b["channels"][1], serde_json::json!({"id": "c1", "displayName": "Planning"}));
        assert_eq!(b["apps"], serde_json::json!([{"id": "app2"}, {"id": "lists"}, {"id": "unknown"}]));
        assert_eq!(b["visibility"], "Private");
    }

    #[test]
    fn clone_and_group_bodies_are_teams() {
        let b = clone_body("g", "me", "OST Test Team [copy]", "", false, ClonePick { tabs: true, settings: true, members: false });
        assert_eq!(b["includeRoster"], false);
        assert_eq!(b["includeChannels"], true);
        assert_eq!(b["visibility"], "Private");
        let g = Group { id: "g".into(), name: "G".into(), description: "".into(), mail: "g@x".into(), members: 3 };
        assert_eq!(group_body(&g)["teamType"], 0);
        assert!(groups_from(&serde_json::json!([])).is_empty());
    }

    #[test]
    fn joinable_and_created_read() {
        let (t, skip) = joinable_from(&serde_json::json!({"type": "Microsoft.Teams.MiddleTier.TeamsAndChannels.Contracts.Models.SearchTeam", "value": []}));
        assert!(t.is_empty() && skip.is_empty());
        let (t, _) = joinable_from(&serde_json::json!({"value": [{"groupId": "g", "displayName": "D", "accessType": "Private", "memberCount": 4}]}));
        assert!(t[0].private && t[0].status == "NotJoined");
        let c = created_from(&serde_json::json!({"groupId": "1fac3ae3-c9c0-4ddb-90bb-58f52209c181", "threadId": "19:x@thread.tacv2"}));
        assert_eq!(c.thread_id, "19:x@thread.tacv2");
        assert_eq!(c.group_id.len(), 36);
    }
}
