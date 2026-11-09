//! Microsoft Graph API: joined teams and channels

use anyhow::{Context, Result};
use serde::Deserialize;

use super::client::TeamsClient;

#[derive(Debug, Deserialize)]
struct TeamsResponse {
    value: Vec<Team>,
}

#[derive(Debug, Deserialize)]
struct Team {
    id: String,
    #[serde(rename = "displayName")]
    display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ChannelsResponse {
    value: Vec<Channel>,
}

#[derive(Debug, Deserialize)]
struct Channel {
    id: String,
    #[serde(rename = "displayName")]
    display_name: Option<String>,
}

/// List joined teams and channels (prints to stdout).
pub async fn list_teams() -> Result<()> {
    let client = TeamsClient::new().await?;
    let teams = list_teams_data(&client).await?;

    println!("\nTeams and Channels:");
    println!("{:-<60}", "");

    if teams.is_empty() {
        println!("  (no teams found)");
        return Ok(());
    }

    for team in &teams {
        println!("Team: {} ({} channels)", team.name, team.channels.len());
        for ch in &team.channels {
            println!("  {:<30} {}", ch.name, ch.id);
        }
        println!();
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Data-returning API functions for TUI integration
// ---------------------------------------------------------------------------

/// Team metadata for TUI display.
pub struct TeamInfo {
    pub id: String,
    pub name: String,
    pub channels: Vec<ChannelInfo>,
}

/// Channel metadata for TUI display.
pub struct ChannelInfo {
    pub id: String,
    pub name: String,
}

/// List joined teams with their channels and return structured data.
pub async fn list_teams_data(client: &TeamsClient) -> Result<Vec<TeamInfo>> {
    tracing::debug!("Fetching joined teams...");
    let resp = client.graph_get("/me/joinedTeams").await?;
    let teams: TeamsResponse = resp
        .json()
        .await
        .context("Failed to parse joinedTeams response")?;

    let mut result = Vec::new();

    for team in &teams.value {
        let team_name = team.display_name.as_deref().unwrap_or(&team.id).to_string();
        tracing::debug!("Fetching channels for team: {} ({})", team_name, team.id);

        let path = format!("/teams/{}/channels", team.id);
        let channels = match client.graph_get(&path).await {
            Ok(resp) => {
                let channels_resp: ChannelsResponse = resp
                    .json()
                    .await
                    .context("Failed to parse channels response")?;
                channels_resp
                    .value
                    .into_iter()
                    .map(|ch| ChannelInfo {
                        name: ch.display_name.unwrap_or_else(|| ch.id.clone()),
                        id: ch.id,
                    })
                    .collect()
            }
            Err(e) => {
                tracing::warn!("Failed to fetch channels for {}: {:#}", team_name, e);
                Vec::new()
            }
        };

        result.push(TeamInfo {
            id: team.id.clone(),
            name: team_name,
            channels,
        });
    }

    Ok(result)
}

/// A channel as the chat list shows it (Teams' CSA team list).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct ListChannel {
    pub id: String,
    pub name: String,
    /// Shown in the list (Teams' isFavorite); hidden channels aren't listed.
    pub shown: bool,
    pub unread: bool,
    pub muted: bool,
    pub general: bool,
    /// Never opened (Teams' "New" badge; never on General).
    pub new: bool,
    pub description: String,
    /// Manage notifications: "all", "mentions" or "mute".
    pub notify: crate::api::channels::NotifyMode,
    /// You own it (Edit channel, Manage channel, the email address).
    pub owner: bool,
    /// Its layout: "PostReply" (Posts) or "Conversational" (Threads).
    pub layout: String,
    /// When it was last active (its last message's compose time, ISO);
    /// Manage team's "Last active".
    pub last_active: String,
    /// Teams' channelType: 0 standard, 1 private, 2 shared.
    pub channel_type: u8,
    pub archived: bool,
    /// Shared into this team from another one.
    pub shared_in: bool,
    /// Recommended for everyone's list (Teams' isFavoriteByDefault;
    /// Manage team shows "Recommended").
    pub recommended: bool,
}

/// A team as the chat list shows it.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct ListTeam {
    /// The team's group id (as Graph names teams).
    pub id: String,
    /// The team's thread id (19:…@thread.tacv2).
    pub thread_id: String,
    pub name: String,
    /// Expanded in the list (Teams keeps isCollapsed per team).
    pub expanded: bool,
    pub archived: bool,
    /// Joined and never read in (Teams' isNewForUser: no channel has a
    /// read horizon).
    pub new: bool,
    pub channels: Vec<ListChannel>,
    /// Deleted channels (Manage team ▸ Channels ▸ Deleted).
    pub deleted_channels: Vec<ListChannel>,
    /// The team's description.
    pub description: String,
    /// Its SharePoint site (teamSiteInformation.sharepointSiteUrl).
    pub site_url: String,
    /// You own the team (memberRoleString "admin").
    pub owner: bool,
}

fn read_horizon(c: &serde_json::Value) -> bool {
    c.pointer("/consumptionHorizon/originalArrivalTime")
        .and_then(|t| t.as_i64())
        .is_some_and(|t| t > 0)
}

/// Read Teams' team list (`{csa}/api/v1/teams/users/me/teams`).
pub fn list_teams_from(v: &serde_json::Value) -> Vec<ListTeam> {
    let b = |x: &serde_json::Value, k: &str| x.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
    let s = |x: &serde_json::Value, k: &str| x.get(k).and_then(|v| v.as_str()).unwrap_or_default().to_string();
    v.as_array()
        .into_iter()
        .flatten()
        .filter(|t| !b(t, "isDeleted"))
        .map(|t| {
            let all: Vec<&serde_json::Value> = t
                .get("channels")
                .and_then(|c| c.as_array())
                .into_iter()
                .flatten()
                .collect();
            let channels: Vec<&serde_json::Value> = all.iter().copied().filter(|c| !b(c, "isDeleted")).collect();
            let thread = s(t, "id");
            let channel_of = |c: &&serde_json::Value| ListChannel {
                    id: s(c, "id"),
                    name: s(c, "displayName"),
                    // General's place in the list is the team's
                    // isGeneralChannelFavorite (Hide / Show set it there).
                    shown: if b(c, "isGeneral") {
                        t.get("isGeneralChannelFavorite").and_then(|v| v.as_bool()).unwrap_or(true)
                    } else {
                        b(c, "isFavorite")
                    },
                    unread: c.get("isMessageRead").and_then(|r| r.as_bool()) == Some(false),
                    muted: b(c, "isMuted"),
                    general: b(c, "isGeneral"),
                    new: !b(c, "isGeneral") && !read_horizon(c),
                    description: s(c, "description"),
                    notify: crate::api::channels::Notify::from_properties(
                        &s(c, "channelNotificationSettings"),
                        c.get("alerts").and_then(|a| a.as_bool()).unwrap_or(true),
                    )
                    .mode,
                    owner: s(c, "memberRoleString") == "admin",
                    layout: Some(s(c, "modality")).filter(|m| !m.is_empty()).unwrap_or_else(|| "PostReply".into()),
                    // Its last message, else when it was made (Teams shows a
                    // new channel as active since then).
                    last_active: c
                        .pointer("/lastMessage/composeTime")
                        .and_then(|v| v.as_str())
                        .filter(|t| !t.is_empty())
                        .or_else(|| c.get("creationTime").and_then(|v| v.as_str()))
                        .unwrap_or_default()
                        .to_string(),
                    channel_type: c.get("channelType").and_then(|v| v.as_u64()).unwrap_or(0).min(2) as u8,
                    archived: b(c, "isArchived"),
                    shared_in: b(c, "isShared") && !s(c, "parentTeamId").is_empty() && s(c, "parentTeamId") != thread,
                    recommended: b(c, "isFavoriteByDefault") && !b(c, "isGeneral"),
                };
            let mut list: Vec<ListChannel> = channels.iter().map(channel_of).collect();
            let deleted: Vec<ListChannel> = all.iter().filter(|c| b(c, "isDeleted")).map(channel_of).collect();
            // General first, then by name (Teams' channel order).
            list.sort_by(|a, b| b.general.cmp(&a.general).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
            let group = channels
                .iter()
                .map(|c| s(c, "groupId"))
                .find(|g| !g.is_empty())
                .or_else(|| t.pointer("/teamSiteInformation/groupId").and_then(|g| g.as_str()).map(str::to_string))
                .unwrap_or_default();
            ListTeam {
                id: if group.is_empty() { s(t, "id") } else { group },
                thread_id: s(t, "id"),
                name: s(t, "displayName"),
                expanded: !b(t, "isCollapsed"),
                archived: b(t, "isArchived"),
                new: !channels.iter().any(|c| read_horizon(c)),
                channels: list,
                deleted_channels: deleted,
                description: s(t, "description"),
                site_url: t.pointer("/teamSiteInformation/sharepointSiteUrl").and_then(|u| u.as_str()).unwrap_or_default().to_string(),
                owner: s(t, "memberRoleString") == "admin",
            }
        })
        .collect()
}

/// Your teams and their channels as Teams' chat list has them.
pub async fn list_teams_csa(client: &TeamsClient) -> Result<Vec<ListTeam>> {
    let token = crate::auth::oauth::access_token_for("https://chatsvcagg.teams.microsoft.com/.default").await?;
    let region = client
        .chat_service_url()
        .split("//")
        .nth(1)
        .and_then(|h| h.split('.').next())
        .unwrap_or("amer")
        .to_string();
    let v: serde_json::Value = client
        .http()
        .get(format!(
            "https://teams.microsoft.com/api/csa/{region}/api/v1/teams/users/me/teams?enableMembershipSummary=true"
        ))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("Teams list")?
        .json()
        .await?;
    let mut teams = list_teams_from(&v);
    teams.sort_by_key(|t| t.name.to_lowercase());
    Ok(teams)
}

/// A team tag, as Teams' @ picker offers it (CSA `tagCards`).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct TeamTag {
    /// `tagId`, the mention's `mri`.
    pub id: String,
    pub name: String,
    /// `memberCount` ("1 person", "N people").
    pub count: u64,
    /// `currentMemberIsPartOfTag`: a mention of it mentions you.
    pub mine: bool,
}

/// The tags in a CSA `tagCards` reply.
pub fn team_tags_from(v: &serde_json::Value) -> Vec<TeamTag> {
    v.get("tagCards")
        .and_then(|t| t.as_array())
        .into_iter()
        .flatten()
        .filter_map(|t| {
            Some(TeamTag {
                id: t.get("tagId")?.as_str()?.to_string(),
                name: t.get("tagName")?.as_str()?.to_string(),
                count: t.get("memberCount").and_then(|c| c.as_u64()).unwrap_or(0),
                mine: t
                    .get("currentMemberIsPartOfTag")
                    .and_then(|m| m.as_bool())
                    .unwrap_or(false),
            })
        })
        .collect()
}

/// The ids of the tags you are in, from every team whose tags were read
/// (Teams' `currentUserTagIds`: a mention of one of them mentions you).
static MY_TAGS: std::sync::RwLock<Vec<String>> = std::sync::RwLock::new(Vec::new());

/// Whether `id` is a tag you are in (as far as the tags read so far say).
pub fn is_my_tag(id: &str) -> bool {
    MY_TAGS.read().is_ok_and(|t| t.iter().any(|x| x == id))
}

#[cfg(test)]
pub(crate) fn note_tags_for_test(tags: &[TeamTag]) {
    note_tags(tags)
}

fn note_tags(tags: &[TeamTag]) {
    if let Ok(mut mine) = MY_TAGS.write() {
        for t in tags {
            mine.retain(|x| x != &t.id);
            if t.mine {
                mine.push(t.id.clone());
            }
        }
    }
}

/// A team's tags (`team_thread_id` is its General channel's thread), as
/// Teams reads them for the @ picker:
/// `GET {csa}/api/v1/teams/{id}/tagCards?tagType=any`.
pub async fn team_tags(client: &TeamsClient, team_thread_id: &str) -> Result<Vec<TeamTag>> {
    let token = crate::auth::oauth::access_token_for("https://chatsvcagg.teams.microsoft.com/.default").await?;
    let region = client
        .chat_service_url()
        .split("//")
        .nth(1)
        .and_then(|h| h.split('.').next())
        .unwrap_or("amer")
        .to_string();
    let v: serde_json::Value = client
        .http()
        .get(format!(
            "https://teams.microsoft.com/api/csa/{region}/api/v1/teams/{team_thread_id}/tagCards?tagType=any"
        ))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()
        .context("Team tags")?
        .json()
        .await?;
    let tags = team_tags_from(&v);
    note_tags(&tags);
    Ok(tags)
}

#[cfg(test)]
mod list_tests {
    use super::*;

    #[test]
    fn tag_cards_read_as_teams_picker_shows_them() {
        // As Teams read OST Test Team's tags on winpc.
        let v = serde_json::json!({"tagCards":[{"tagId":"tmu3aacUko","tagName":"OST test tag","memberIds":["8:orgid:4287e791-1b98-4963-8b94-281c50472683"],"memberCount":1,"tagType":"team","currentMemberIsPartOfTag":true,"scheduledMembers":[],"version":1}],"continuationToken":""});
        let tags = team_tags_from(&v);
        assert_eq!(
            tags,
            vec![TeamTag { id: "tmu3aacUko".into(), name: "OST test tag".into(), count: 1, mine: true }]
        );
        note_tags(&tags);
        // (Another id, as the messages tests use this one.)
        let t = TeamTag { id: "listTestTag".into(), ..tags[0].clone() };
        note_tags(std::slice::from_ref(&t));
        assert!(is_my_tag("listTestTag") && !is_my_tag("other"));
        note_tags(&[TeamTag { mine: false, ..t }]);
        assert!(!is_my_tag("listTestTag"));
    }

    #[test]
    fn teams_list_reads_shown_channels_unread_and_new() {
        let v = serde_json::json!([
            {"id": "t1", "displayName": "OST Test Team", "isCollapsed": false, "isArchived": false, "channels": [
                {"id": "c1", "displayName": "General", "groupId": "g1", "isFavorite": true, "isGeneral": true, "isMessageRead": true,
                 "consumptionHorizon": {"originalArrivalTime": 1794089841241i64}},
                {"id": "c2", "displayName": "Hidden one", "isFavorite": false, "isMessageRead": false},
                {"id": "c3", "displayName": "Alpha", "isFavorite": true, "isMessageRead": false}
            ]},
            {"id": "t2", "displayName": "Secure Coast", "isCollapsed": true, "channels": [
                {"id": "c4", "displayName": "General", "isFavorite": true, "isGeneral": true, "isMessageRead": true}
            ]}
        ]);
        let t = list_teams_from(&v);
        assert!(!t[0].new && t[1].new);
        assert_eq!((t[0].id.as_str(), t[0].thread_id.as_str()), ("g1", "t1"));
        assert!(t[0].expanded && !t[1].expanded);
        let names: Vec<&str> = t[0].channels.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, vec!["General", "Alpha", "Hidden one"]);
        assert!(!t[0].channels[2].shown);
        assert!(t[0].channels[1].unread && t[0].channels[1].new);
        assert!(!t[1].channels[0].new);
        // A hidden General: the team's isGeneralChannelFavorite (Teams
        // keeps the channel's isFavorite), as captured after Hide.
        let hidden = serde_json::json!([{"id": "t1", "displayName": "T", "isGeneralChannelFavorite": false, "channels": [
            {"id": "c1", "displayName": "General", "isFavorite": true, "isGeneral": true}]}]);
        assert!(!list_teams_from(&hidden)[0].channels[0].shown);
    }
}
