//! A channel's own settings and actions, as Teams' channel menu has them
//! (More channel options / a channel's row ··· in the chat list; captured
//! on winpc, 2026-11-09):
//! - Manage notifications: the channel conversation's properties
//!   `channelNotificationSettings` (`{"allNewPosts","tag","channelTeam",
//!   "dskNotif"}`), `alerts` and `followAllRc`;
//! - Hide / Show: `favorite` (General: `isGeneralChannelFavorite`) and your
//!   membership's `interest`;
//! - Edit channel: the middle tier's `PATCH beta/teams/{team}/channels/{id}`
//!   (`displayName`, `description`, `chatModalityType`, `csav1`);
//! - Copy link: Teams' channel deep link;
//! - Get email address: the middle tier's `beta/channels/{id}/email`.

use anyhow::{Context, Result, bail};

use super::client::TeamsClient;

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes())
        .collect::<String>()
        .replace('+', "%20")
}

/// Teams' "Select what content notifies you".
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum NotifyMode {
    /// "All new messages": new messages, all @mentions and replies to
    /// followed threads.
    All,
    /// "@mentions and replies" (Teams' default).
    #[default]
    Mentions,
    /// "Mute": only personal mentions and replies to followed threads.
    Mute,
}

/// A channel's notification settings (Teams' channelNotificationSettings,
/// with `alerts`).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Notify {
    pub mode: NotifyMode,
    /// "Tag mentions" (under @mentions and replies).
    pub tag: bool,
    /// "Channel and team mentions".
    pub channel_team: bool,
    /// "Set a preference for this channel" (desktop notifications); None:
    /// "Match settings used for all channels".
    pub dsk: Option<String>,
}

impl Notify {
    /// Read Teams' properties (the settings JSON text and `alerts`).
    pub fn from_properties(settings: &str, alerts: bool) -> Notify {
        let v: serde_json::Value = serde_json::from_str(settings).unwrap_or_default();
        let on = |k: &str| v.get(k).and_then(|x| x.as_str()) == Some("On");
        let all = on("allNewPosts");
        let tag = v.get("tag").map(|_| on("tag")).unwrap_or(true);
        let channel_team = v.get("channelTeam").map(|_| on("channelTeam")).unwrap_or(true);
        let mode = if !alerts {
            NotifyMode::Mute
        } else if all {
            NotifyMode::All
        } else {
            NotifyMode::Mentions
        };
        Notify {
            mode,
            tag,
            channel_team,
            dsk: v.get("dskNotif").and_then(|d| d.as_str()).map(str::to_string),
        }
    }

    /// A menu choice: Teams writes these values for it.
    pub fn for_mode(mode: NotifyMode, dsk: Option<String>) -> Notify {
        let on = mode != NotifyMode::Mute;
        Notify { mode, tag: on, channel_team: on, dsk }
    }

    /// The property's text, in Teams' key order.
    pub fn settings_json(&self) -> String {
        let s = |b: bool| if b { "\"On\"" } else { "\"Off\"" };
        let dsk = match &self.dsk {
            Some(d) => serde_json::Value::String(d.clone()).to_string(),
            None => "null".into(),
        };
        format!(
            "{{\"allNewPosts\":{},\"tag\":{},\"channelTeam\":{},\"dskNotif\":{}}}",
            s(self.mode == NotifyMode::All),
            s(self.tag && self.mode != NotifyMode::Mute),
            s(self.channel_team && self.mode != NotifyMode::Mute),
            dsk
        )
    }
}

fn conversation_url(client: &TeamsClient, channel: &str) -> String {
    format!(
        "{}/v1/users/ME/conversations/{}",
        client.chat_service_url(),
        enc(channel)
    )
}

/// Set one of your properties on the channel conversation.
async fn set_property(client: &TeamsClient, channel: &str, name: &str, value: &str) -> Result<()> {
    let url = format!("{}/properties?name={}", conversation_url(client, channel), enc(name));
    client
        .chat_request(reqwest::Method::PUT, &url, &serde_json::json!({ name: value }))
        .await?;
    Ok(())
}

/// Your channel properties (notifications, follow-all, favourite).
pub async fn properties(client: &TeamsClient, channel: &str) -> Result<serde_json::Value> {
    let url = format!("{}?view=msnp24Equivalent", conversation_url(client, channel));
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Channel")?;
    Ok(v.get("properties").cloned().unwrap_or_default())
}

/// What Manage notifications shows for a channel.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct NotifyState {
    #[serde(flatten)]
    pub notify: Notify,
    /// "Follow all new threads" (followAllRc set).
    pub follow_all: bool,
}

pub fn notify_state_from(props: &serde_json::Value) -> NotifyState {
    let s = |k: &str| props.get(k).and_then(|v| v.as_str()).unwrap_or_default();
    NotifyState {
        notify: Notify::from_properties(s("channelNotificationSettings"), s("alerts") != "false"),
        follow_all: !s("followAllRc").is_empty() && s("followAllRc") != "0",
    }
}

/// Save notification settings as Teams does: the settings, then `alerts`
/// (off only for Mute).
pub async fn set_notify(client: &TeamsClient, channel: &str, notify: &Notify) -> Result<()> {
    set_property(client, channel, "channelNotificationSettings", &notify.settings_json()).await?;
    let alerts = if notify.mode == NotifyMode::Mute { "false" } else { "true" };
    set_property(client, channel, "alerts", alerts).await
}

/// "Follow all new threads": follow every thread after the newest post
/// (`followAllRc` = its id), or stop ("").
pub async fn set_follow_all(client: &TeamsClient, channel: &str, newest_post: Option<&str>) -> Result<()> {
    set_property(client, channel, "followAllRc", newest_post.unwrap_or("")).await
}

/// Hide a channel from your list, or show it again (Teams' Hide / Show).
pub async fn set_hidden(client: &TeamsClient, channel: &str, general: bool, hidden: bool) -> Result<()> {
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .context("Not signed in")?;
    let favorite = if hidden { "false" } else { "true" };
    if general {
        set_property(client, channel, "isGeneralChannelFavorite", favorite).await?;
    }
    let member = format!(
        "{}/v1/threads/{}/members/{}",
        client.chat_service_url(),
        enc(channel),
        me
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &member,
            &serde_json::json!({ "interest": if hidden { "NotInterested" } else { "Interested" } }),
        )
        .await?;
    if hidden || !general {
        set_property(client, channel, "favorite", favorite).await?;
    }
    Ok(())
}

/// Teams' channel deep link, and the clipboard's HTML for it.
pub fn channel_link(channel: &str, name: &str, group_id: &str, tenant: &str) -> (String, String) {
    let url = format!(
        "https://teams.microsoft.com/l/channel/{}/{}?groupId={}&tenantId={}",
        enc(channel),
        enc(name),
        group_id,
        tenant
    );
    let esc = |s: &str| {
        s.replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
    };
    let html = format!("<a href=\"{}\">{}</a>", esc(&url), esc(name));
    (url, html)
}

async fn middle_tier(client: &TeamsClient) -> Result<(String, String)> {
    super::tabs::middle_tier(client).await
}

/// Teams' Copy link for a team (the team row's menu): the team's thread
/// (its General channel) in /l/team/…/conversations, and as HTML an anchor
/// reading "{General's name} | {team}".
pub fn team_link(team_thread: &str, general_name: &str, team_name: &str, group_id: &str, tenant: &str) -> (String, String) {
    let url = format!(
        "https://teams.microsoft.com/l/team/{}/conversations?groupId={}&tenantId={}",
        enc(team_thread),
        group_id,
        tenant
    );
    let esc = |s: &str| {
        s.replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
    };
    let html = format!("<a href=\"{}\">{} | {}</a>", esc(&url), esc(general_name), esc(team_name));
    (url, html)
}

/// Create a channel (Teams' Create a channel, captured 2026-11-09):
/// `POST {mt}/beta/teams/{teamThread}/channels` with the name, description,
/// group, type ("Standard", "Shared", "Private") and layout; then, as Teams
/// does, show it for its creator (`favorite`), and with Recommend, show it
/// for everyone (`PUT {mt}/beta/teams/{channel}/setDefaultChannel`, then
/// `lastTimeFavorited`). Returns the new channel's id.
pub async fn create_channel(
    client: &TeamsClient,
    team_thread: &str,
    group_id: &str,
    name: &str,
    description: &str,
    channel_type: &str,
    layout: &str,
    recommend: bool,
) -> Result<String> {
    if let Some(e) = name_error(name, false) {
        bail!(e);
    }
    if channel_type != "Standard" {
        return create_private_channel(client, team_thread, group_id, name, description, channel_type, layout).await;
    }
    let (base, token) = middle_tier(client).await?;
    let body = serde_json::json!({
        "displayName": name.trim(),
        "description": description,
        "groupId": group_id,
        "channelType": channel_type,
        "chatModalityType": layout,
    });
    let resp = client
        .http()
        .post(format!("{base}/beta/teams/{team_thread}/channels"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        // A name in use (also by a recently deleted channel) comes back as
        // a 400/409 that names it; Teams says "Channel name is already
        // taken."
        let lower = text.to_lowercase();
        if status.as_u16() == 409 || lower.contains("already") || lower.contains("duplicate") || lower.contains("namealready") {
            bail!("Channel name is already taken. ({status})");
        }
        bail!("Create channel: {status} {}", text.chars().take(200).collect::<String>());
    }
    let v: serde_json::Value = serde_json::from_str(&text).context("Create channel")?;
    let id = v.pointer("/value/objectId").and_then(|i| i.as_str()).context("No channel id")?.to_string();
    let favorite = format!(
        "{}/properties?name=favorite&requirePermanentJoinedState=true",
        conversation_url(client, &id)
    );
    client
        .chat_request(reqwest::Method::PUT, &favorite, &serde_json::json!({ "favorite": "true" }))
        .await?;
    if recommend {
        client
            .http()
            .put(format!("{base}/beta/teams/{id}/setDefaultChannel"))
            .bearer_auth(&token)
            .header(reqwest::header::CONTENT_LENGTH, "0")
            .send()
            .await?
            .error_for_status()
            .context("Recommend the channel")?;
        let now = chrono::Utc::now().timestamp_millis().to_string();
        set_property(client, &id, "lastTimeFavorited", &now).await?;
    }
    Ok(id)
}

/// Teams' body for a private or shared channel.
pub fn private_channel_body(team_thread: &str, name: &str, description: &str, channel_type: &str, layout: &str, session: &str) -> serde_json::Value {
    serde_json::json!({
        "spaceThreadId": team_thread,
        "displayName": name.trim(),
        "description": description,
        "channelType": channel_type,
        "sharedWithParentTeam": true,
        "sessionKey": session,
        "chatModalityType": layout,
    })
}

/// Create a private or shared channel as Teams does (captured 2026-11-09):
/// through the provisioning service, `POST …/teams/{group}/channelsWarmup`
/// then `POST …/teams/{group}/channels?forceSync=false` with the team thread,
/// name, type, a session key and layout. Its reply has no thread id, so the
/// channel is found by name in the team's list once it shows there; it is
/// then shown for its creator (`favorite`), as Teams does.
async fn create_private_channel(
    client: &TeamsClient,
    team_thread: &str,
    group_id: &str,
    name: &str,
    description: &str,
    channel_type: &str,
    layout: &str,
) -> Result<String> {
    let (base, token) = provisioning(client).await?;
    let session = uuid::Uuid::new_v4().to_string();
    let _ = client
        .http()
        .post(format!("{base}/teams/{group_id}/channelsWarmup"))
        .bearer_auth(&token)
        .header(reqwest::header::CONTENT_LENGTH, "0")
        .send()
        .await;
    let resp = client
        .http()
        .post(format!("{base}/teams/{group_id}/channels?forceSync=false"))
        .bearer_auth(&token)
        .json(&private_channel_body(team_thread, name, description, channel_type, layout, &session))
        .send()
        .await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        let lower = text.to_lowercase();
        if status.as_u16() == 409 || lower.contains("already") || lower.contains("duplicate") {
            bail!("Channel name is already taken. ({status})");
        }
        bail!("Create channel: {status} {}", text.chars().take(200).collect::<String>());
    }
    // Wait for it to show in the team's list (Teams picks it up from sync).
    let wanted = name.trim().to_lowercase();
    for attempt in 0..20 {
        if attempt > 0 {
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        }
        if let Ok(teams) = super::teams::list_teams_csa(client).await
            && let Some(ch) = teams
                .iter()
                .find(|t| t.thread_id == team_thread)
                .and_then(|t| t.channels.iter().find(|c| c.name.to_lowercase() == wanted))
        {
            let favorite = format!(
                "{}/properties?name=favorite&requirePermanentJoinedState=true",
                conversation_url(client, &ch.id)
            );
            let _ = client.chat_request(reqwest::Method::PUT, &favorite, &serde_json::json!({ "favorite": "true" })).await;
            return Ok(ch.id.clone());
        }
    }
    bail!("The channel was made but hasn't shown up yet")
}

/// Add people to a private channel (its member step; Teams'
/// `PUT {mt}/beta/teams/{teamThread}/channels/{channel}/members` with
/// `{"value": [{mri, role}]}`, role 0 member, 1 owner).
pub async fn add_private_channel_members(client: &TeamsClient, team_thread: &str, channel: &str, users: &[(String, bool)]) -> Result<()> {
    if users.is_empty() {
        return Ok(());
    }
    let (base, token) = middle_tier(client).await?;
    let value: Vec<serde_json::Value> = users
        .iter()
        .map(|(mri, owner)| serde_json::json!({ "mri": mri, "role": u8::from(*owner) }))
        .collect();
    client
        .http()
        .put(format!("{base}/beta/teams/{}/channels/{}/members", enc(team_thread), enc(channel)))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "value": value }))
        .send()
        .await?
        .error_for_status()
        .context("Add channel members")?;
    Ok(())
}

/// Teams' provisioning service and a token for it (its resource is
/// teamsAndChannelsProvisioningServiceConstants.resource, prod
/// https://templates.teams.microsoft.com).
async fn provisioning(client: &TeamsClient) -> Result<(String, String)> {
    let base = client
        .region_endpoint("teamsAndChannelsProvisioningService")
        .context("No Teams provisioning endpoint")?;
    let token = crate::auth::oauth::access_token_for("https://templates.teams.microsoft.com/.default").await?;
    Ok((base.trim_end_matches('/').to_string(), token))
}

/// Archive a channel (Teams' Archive channel; Restore with `restore`):
/// `POST {teamsAndChannelsProvisioningService}/teams/{group}/channels/
/// {channel}/archive[?setSpoSiteReadOnlyForMembers=true]` or `/unarchive`.
pub async fn archive_channel(client: &TeamsClient, group_id: &str, channel: &str, restore: bool, read_only: bool) -> Result<()> {
    let (base, token) = provisioning(client).await?;
    let mut url = format!(
        "{base}/teams/{group_id}/channels/{channel}/{}",
        if restore { "unarchive" } else { "archive" }
    );
    if !restore && read_only {
        url.push_str("?setSpoSiteReadOnlyForMembers=true");
    }
    client
        .http()
        .post(url)
        .bearer_auth(&token)
        .header(reqwest::header::CONTENT_LENGTH, "0")
        .send()
        .await?
        .error_for_status()
        .context(if restore { "Restore channel" } else { "Archive channel" })?;
    Ok(())
}

/// Archive a team (the team menu's Archive; Restore with `restore`), as
/// Teams does through the provisioning service:
/// `POST …/groups/{group}/archive[?setSpoSiteReadOnlyForMembers=true]` or
/// `/unarchive`.
pub async fn archive_team(client: &TeamsClient, group_id: &str, restore: bool, read_only: bool) -> Result<()> {
    let (base, token) = provisioning(client).await?;
    let mut url = format!("{base}/groups/{}/{}", enc(group_id), if restore { "unarchive" } else { "archive" });
    if !restore && read_only {
        url.push_str("?setSpoSiteReadOnlyForMembers=true");
    }
    client
        .http()
        .post(url)
        .bearer_auth(&token)
        .header(reqwest::header::CONTENT_LENGTH, "0")
        .send()
        .await?
        .error_for_status()
        .context(if restore { "Restore team" } else { "Archive team" })?;
    Ok(())
}

/// Teams' body for a membership change (`updateType` Promoted, Demoted,
/// Left or DemotedAndLeft).
pub fn membership_body(mri: &str, update_type: &str, group_id: &str) -> serde_json::Value {
    serde_json::json!({ "userMri": mri, "updateType": update_type, "groupId": group_id })
}

/// Change someone's membership of a team (`PUT {mt}/beta/teams/{teamThread}/members`):
/// make them an owner (Promoted) or a member (Demoted), remove them (Left),
/// or leave yourself (DemotedAndLeft). The service's error code when it
/// says no (`OperationDeniedAsMemberIsLastAdminInTeam` for the last owner).
pub async fn update_membership(client: &TeamsClient, team_thread: &str, group_id: &str, mri: &str, update_type: &str) -> Result<Option<String>> {
    let (base, token) = middle_tier(client).await?;
    let resp = client
        .http()
        .put(format!("{base}/beta/teams/{}/members", enc(team_thread)))
        .bearer_auth(&token)
        .json(&membership_body(mri, update_type, group_id))
        .send()
        .await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    let v: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    let code = v["errorCode"]
        .as_str()
        .or_else(|| v.pointer("/value/errorCode").and_then(|c| c.as_str()))
        .or_else(|| v.pointer("/error/code").and_then(|c| c.as_str()))
        .filter(|c| !c.is_empty())
        .map(str::to_string);
    if code.is_some() {
        return Ok(code);
    }
    if !status.is_success() {
        bail!("Team membership: {status} {}", text.chars().take(200).collect::<String>());
    }
    Ok(None)
}

/// Leave a team (DemotedAndLeft for yourself).
pub async fn leave_team(client: &TeamsClient, team_thread: &str, group_id: &str) -> Result<Option<String>> {
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .context("Who you are")?;
    update_membership(client, team_thread, group_id, &me, "DemotedAndLeft").await
}

/// Someone on Manage team ▸ Members.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct RosterMember {
    pub mri: String,
    /// Admin (owner), User or Guest.
    pub role: String,
    pub name: String,
    pub title: String,
    pub location: String,
    pub tags: Vec<String>,
}

/// The people of a roster reply (bots, `28:`, left out).
pub fn roster_from(v: &serde_json::Value) -> Vec<RosterMember> {
    v["members"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| {
            let mri = m["id"].as_str()?;
            (!mri.starts_with("28:")).then(|| RosterMember {
                mri: mri.to_string(),
                role: m["role"].as_str().unwrap_or("User").to_string(),
                ..Default::default()
            })
        })
        .collect()
}

/// Manage team ▸ Members: owners and members and guests as Teams reads them
/// (`…/threads/{team}/members?…&selectMemberRoles=Admin` and `User|Guest`),
/// with names, titles and locations (Graph) and their tags (CSA memberTags).
pub async fn team_roster(client: &TeamsClient, team_thread: &str) -> Result<Vec<RosterMember>> {
    let mut out = Vec::new();
    for roles in ["Admin", "User%7CGuest"] {
        let url = format!(
            "{}/v1/threads/{}/members?view=msnp24Equivalent&pageSize=100&selectMemberRoles={roles}",
            client.chat_service_url(),
            enc(team_thread)
        );
        let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Members")?;
        out.extend(roster_from(&v));
    }
    for m in out.iter_mut() {
        if let Some(oid) = m.mri.strip_prefix("8:orgid:")
            && uuid::Uuid::parse_str(oid).is_ok()
            && let Ok(resp) = client
                .graph_get(&format!("/users/{oid}?$select=displayName,jobTitle,officeLocation"))
                .await
            && let Ok(u) = resp.json::<serde_json::Value>().await
        {
            let s = |k: &str| u[k].as_str().unwrap_or_default().to_string();
            m.name = s("displayName");
            m.title = s("jobTitle");
            m.location = s("officeLocation");
        }
    }
    let ids: Vec<String> = out.iter().map(|m| m.mri.clone()).collect();
    if let Ok(tags) = super::teams::member_tags(client, team_thread, &ids).await {
        for m in out.iter_mut() {
            if let Some(t) = tags.iter().find(|(id, _)| id.eq_ignore_ascii_case(&m.mri)) {
                m.tags = t.1.clone();
            }
        }
    }
    Ok(out)
}

/// A request to join a team (Manage team ▸ Pending requests).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct JoinRequest {
    pub mri: String,
    pub name: String,
    pub title: String,
    pub location: String,
    /// Who asked for them (names), when someone did.
    pub requested_by: Vec<String>,
}

/// The requests in a `findJoinRequests` reply for one team.
pub fn join_requests_from(v: &serde_json::Value, group_id: &str) -> Vec<JoinRequest> {
    let s = |x: &serde_json::Value, k: &str| x[k].as_str().unwrap_or_default().to_string();
    let per = &v["joinRequestsPerTeam"];
    let list = per[group_id]
        .as_array()
        .or_else(|| per.as_array())
        .cloned()
        .unwrap_or_default();
    list.iter()
        .filter_map(|r| {
            let u = &r["user"];
            let mri = u["mri"].as_str().or_else(|| r["userMri"].as_str())?.to_string();
            Some(JoinRequest {
                mri,
                name: s(u, "displayName"),
                title: s(u, "jobTitle"),
                location: s(u, "userLocation"),
                requested_by: r["sponsors"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|p| p["displayName"].as_str().map(str::to_string))
                    .collect(),
            })
        })
        .collect()
}

/// A team's pending join requests (`POST {mt}/beta/teams/findJoinRequests`
/// `{"GroupIdList": [group]}`).
pub async fn join_requests(client: &TeamsClient, group_id: &str) -> Result<Vec<JoinRequest>> {
    let (base, token) = middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/teams/findJoinRequests"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "GroupIdList": [group_id] }))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await
        .context("Join requests")?;
    Ok(join_requests_from(&v, group_id))
}

/// Accept or deny join requests: one (`joinRequestAdminAction`, `UserMri`)
/// or several (`bulkJoinRequestAdminAction`, `UserMris`), as Teams sends
/// them (`silentAction=false`).
pub async fn answer_join_requests(client: &TeamsClient, group_id: &str, mris: &[String], accept: bool) -> Result<()> {
    let (base, token) = middle_tier(client).await?;
    let action = if accept { "Accept" } else { "Reject" };
    let (path, body) = if mris.len() == 1 {
        ("joinRequestAdminAction", serde_json::json!({ "GroupId": group_id, "UserMri": mris[0], "ActionType": action }))
    } else {
        ("bulkJoinRequestAdminAction", serde_json::json!({ "GroupId": group_id, "UserMris": mris, "ActionType": action }))
    };
    client
        .http()
        .post(format!("{base}/beta/teams/{path}?silentAction=false"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("Join request")?;
    Ok(())
}

/// Delete a team: `DELETE {mt}/beta/teams/{teamThread}/delete`.
pub async fn delete_team(client: &TeamsClient, team_thread: &str) -> Result<()> {
    let (base, token) = middle_tier(client).await?;
    client
        .http()
        .delete(format!("{base}/beta/teams/{}/delete", enc(team_thread)))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Delete team")?;
    Ok(())
}

/// A private or shared channel's own group, as the provisioning service
/// names it: `OID:{substrateGroupId}@{tenantid}` (its thread properties).
/// `None` for a standard channel.
pub fn private_channel_group(properties: &serde_json::Value) -> Option<String> {
    let sub = properties["threadSubType"].as_str().unwrap_or_default();
    if sub != "PrivateChannel" && sub != "SharedChannel" {
        return None;
    }
    let group = properties["substrateGroupId"].as_str().filter(|s| !s.is_empty())?;
    let tenant = properties["tenantid"].as_str().filter(|s| !s.is_empty())?;
    Some(format!("OID:{group}@{tenant}"))
}

/// Delete a channel. A standard one: `DELETE {mt}/beta/teams/{team}/
/// channels/{channel}`. A private or shared one, as Teams does (captured
/// 2026-11-09): `DELETE {teamsAndChannelsProvisioningService}/teams/{group}/
/// channels/OID:{its group}@{tenant}?forceSync=false`.
pub async fn delete_channel(client: &TeamsClient, team_thread: &str, group_id: &str, channel: &str) -> Result<()> {
    let thread_url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        enc(channel)
    );
    let thread: serde_json::Value = client.chat_get(&thread_url).await?.json().await.context("Channel")?;
    if let Some(own) = private_channel_group(&thread["properties"]) {
        let (base, token) = provisioning(client).await?;
        client
            .http()
            .delete(format!("{base}/teams/{group_id}/channels/{}?forceSync=false", enc(&own)))
            .bearer_auth(&token)
            .send()
            .await?
            .error_for_status()
            .context("Delete channel")?;
        return Ok(());
    }
    let (base, token) = middle_tier(client).await?;
    client
        .http()
        .delete(format!("{base}/beta/teams/{}/channels/{}", enc(team_thread), enc(channel)))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Delete channel")?;
    Ok(())
}

/// Recommend a channel for everyone's list, or stop:
/// `PUT` / `DELETE {mt}/beta/teams/{channel}/setDefaultChannel`.
pub async fn recommend_channel(client: &TeamsClient, channel: &str, on: bool) -> Result<()> {
    let (base, token) = middle_tier(client).await?;
    let url = format!("{base}/beta/teams/{channel}/setDefaultChannel");
    let req = if on {
        client.http().put(url).header(reqwest::header::CONTENT_LENGTH, "0")
    } else {
        client.http().delete(url)
    };
    req.bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Recommend for everyone")?;
    Ok(())
}

/// Hide all channels (the team row's menu): Teams' provisioning service,
/// `PUT {teamsAndChannelsProvisioningService}/team/{teamThread}/hide`.
pub async fn hide_all_channels(client: &TeamsClient, team_thread: &str) -> Result<()> {
    let (base, token) = provisioning(client).await?;
    client
        .http()
        .put(format!("{base}/team/{}/hide", enc(team_thread)))
        .bearer_auth(&token)
        .header(reqwest::header::CONTENT_LENGTH, "0")
        .send()
        .await?
        .error_for_status()
        .context("Hide all channels")?;
    Ok(())
}

/// Edit channel: what changed (Teams sends only those, with `csav1`).
#[derive(Debug, Clone, Default, serde::Deserialize, serde::Serialize)]
pub struct Edit {
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "displayName")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// "Conversational" (Threads) or "PostReply" (Posts).
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "chatModalityType")]
    pub layout: Option<String>,
}

/// Teams' channel-name rules (the Edit and Create dialogs' messages, from
/// Teams' teamsAndChannels strings). An empty name only disables Save; the
/// field takes at most 50 characters.
pub fn name_error(name: &str, general: bool) -> Option<&'static str> {
    let n = name.trim();
    if general || n.is_empty() {
        return None;
    }
    if n.starts_with('_') || n.starts_with('.') {
        return Some("Channel name cannot start with an underscore (_) or a period (.)");
    }
    if n.chars().any(|c| "~#%&*{}+/\\:<>?|'\"".contains(c)) || n.contains("..") {
        return Some("We don't support these characters: ~#%&*{}+/\\:<>?|'\"..");
    }
    if n.ends_with('.') {
        return Some("Channel name cannot end with a period (.)");
    }
    let lower = n.to_lowercase();
    if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
        return Some("Links are not allowed in the channel name");
    }
    None
}

pub async fn edit(client: &TeamsClient, team_thread: &str, channel: &str, change: &Edit) -> Result<()> {
    if let Some(n) = &change.name
        && let Some(e) = name_error(n, false)
    {
        bail!(e);
    }
    let (base, token) = middle_tier(client).await?;
    let mut body = serde_json::to_value(change)?;
    body.as_object_mut()
        .context("Edit")?
        .insert("csav1".into(), serde_json::Value::Bool(true));
    client
        .http()
        .patch(format!(
            "{base}/beta/teams/{}/channels/{}",
            enc(team_thread),
            enc(channel)
        ))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("Edit channel")?;
    Ok(())
}

/// A channel's email address (Get email address) and who may send to it.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Email {
    pub address: String,
    /// "anyone", "members" or "domains".
    pub allowed: String,
    pub domains: Vec<String>,
}

pub fn email_from(v: &serde_json::Value) -> Option<Email> {
    let address = v.pointer("/emailAddressDetails/emailId")?.as_str()?.to_string();
    if address.is_empty() {
        return None;
    }
    Some(Email {
        address,
        allowed: v
            .pointer("/allowedSenders/allowedSenderType")
            .and_then(|a| a.as_str())
            .unwrap_or("members")
            .to_string(),
        domains: v
            .pointer("/allowedSenders/allowedDomains")
            .and_then(|d| d.as_array())
            .into_iter()
            .flatten()
            .filter_map(|d| d.as_str().map(str::to_string))
            .collect(),
    })
}

fn senders_body(allowed: &str, domains: &[String]) -> serde_json::Value {
    let mut s = serde_json::json!({ "allowedSenderType": allowed });
    if allowed == "domains" {
        s["allowedDomains"] = serde_json::json!(domains);
    }
    serde_json::json!({ "allowedSenders": s })
}

async fn email_request(
    client: &TeamsClient,
    channel: &str,
    method: reqwest::Method,
    body: Option<serde_json::Value>,
) -> Result<serde_json::Value> {
    let (base, token) = middle_tier(client).await?;
    let mut req = client
        .http()
        .request(method, format!("{base}/beta/channels/{channel}/email"))
        .bearer_auth(&token);
    if let Some(b) = body {
        req = req.json(&b);
    }
    let resp = req.send().await?.error_for_status().context("Channel email")?;
    let text = resp.text().await.unwrap_or_default();
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

/// The channel's address, creating it (members only, as Teams does) when
/// it has none.
pub async fn email(client: &TeamsClient, channel: &str) -> Result<Email> {
    let v = email_request(client, channel, reqwest::Method::GET, None).await?;
    if let Some(e) = email_from(&v) {
        return Ok(e);
    }
    let v = email_request(client, channel, reqwest::Method::POST, Some(senders_body("members", &[]))).await?;
    email_from(&v).context("No email address")
}

pub async fn set_email_senders(client: &TeamsClient, channel: &str, allowed: &str, domains: &[String]) -> Result<Email> {
    let v = email_request(client, channel, reqwest::Method::PUT, Some(senders_body(allowed, domains))).await?;
    Ok(email_from(&v).unwrap_or_else(|| Email { address: String::new(), allowed: allowed.into(), domains: domains.to_vec() }))
}

pub async fn remove_email(client: &TeamsClient, channel: &str) -> Result<()> {
    email_request(client, channel, reqwest::Method::DELETE, None).await?;
    Ok(())
}

/// Whether new posts show at the bottom (Teams' `enableChannelsV2` user
/// property; the new layout when it isn't set).
pub async fn new_posts_at_bottom(client: &TeamsClient) -> Result<bool> {
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("User properties")?;
    Ok(v.get("enableChannelsV2").and_then(|x| x.as_str()) != Some("false"))
}

/// See new posts at top / at bottom: Teams' user property
/// `enableChannelsV2` ("false": newest at the top).
pub async fn set_new_posts_at_bottom(client: &TeamsClient, bottom: bool) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/properties?name=enableChannelsV2",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "enableChannelsV2": if bottom { "true" } else { "false" } }),
        )
        .await?;
    Ok(())
}

/// The team's admin settings (its `spaceAdminSettings` thread property, a
/// JSON string Teams writes back whole).
pub async fn space_admin_settings(client: &TeamsClient, team_thread: &str) -> Result<String> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        enc(team_thread)
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Team")?;
    Ok(v["properties"]["spaceAdminSettings"].as_str().unwrap_or_default().to_string())
}

/// Who may post in General (Manage channel ▸ Settings ▸ Moderation):
/// `userSettings.generalChannelSetting`, 0 anyone, 1 anyone with the
/// notify-everyone alert, 2 owners only. Teams' default is anyone.
pub fn general_channel_setting(settings: &str) -> u8 {
    serde_json::from_str::<serde_json::Value>(settings)
        .ok()
        .and_then(|v| v["userSettings"]["generalChannelSetting"].as_u64())
        .map(|n| n.min(2) as u8)
        .unwrap_or(0)
}

/// The settings with General's posting choice changed and everything else
/// (order included) as it was, as Teams writes them.
pub fn with_general_channel_setting(settings: &str, value: u8) -> Result<String> {
    const KEY: &str = "\"generalChannelSetting\":";
    if let Some(at) = settings.find(KEY) {
        let start = at + KEY.len();
        let end = start
            + settings[start..]
                .find(|c: char| !c.is_ascii_digit())
                .unwrap_or(settings.len() - start);
        if end > start {
            return Ok(format!("{}{}{}", &settings[..start], value, &settings[end..]));
        }
    }
    let mut v: serde_json::Value = if settings.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(settings).context("spaceAdminSettings")?
    };
    let obj = v.as_object_mut().context("spaceAdminSettings")?;
    let user = obj
        .entry("userSettings")
        .or_insert_with(|| serde_json::json!({}));
    user.as_object_mut()
        .context("userSettings")?
        .insert("generalChannelSetting".into(), serde_json::json!(value));
    Ok(v.to_string())
}

/// The settings with one key of `userSettings` or `guestSettings` set to a
/// JSON value, everything else (order included) as it was. A missing key is
/// added to its section.
pub fn with_space_setting(settings: &str, section: &str, key: &str, value: &serde_json::Value) -> Result<String> {
    let head = format!("\"{section}\":{{");
    if let Some(start) = settings.find(&head) {
        let body_start = start + head.len();
        // The section's end: its matching brace.
        let mut depth = 1;
        let mut end = body_start;
        for (i, c) in settings[body_start..].char_indices() {
            match c {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = body_start + i;
                        break;
                    }
                }
                _ => {}
            }
        }
        let body = &settings[body_start..end];
        let k = format!("\"{key}\":");
        if let Some(at) = body.find(&k) {
            let vstart = body_start + at + k.len();
            let rest = &settings[vstart..end];
            let vlen = rest.find([',', '}']).unwrap_or(rest.len());
            return Ok(format!("{}{}{}", &settings[..vstart], value, &settings[vstart + vlen..]));
        }
        let sep = if body.trim().is_empty() { "" } else { "," };
        return Ok(format!("{}{sep}\"{key}\":{value}{}", &settings[..end], &settings[end..]));
    }
    let mut v: serde_json::Value = if settings.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(settings).context("spaceAdminSettings")?
    };
    v.as_object_mut()
        .context("spaceAdminSettings")?
        .entry(section)
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .context(section.to_string())?
        .insert(key.into(), value.clone());
    Ok(v.to_string())
}

/// Change team settings (Manage team ▸ Settings): `changes` is
/// `{"userSettings": {key: value}, "guestSettings": {…}}`; the team thread's
/// spaceAdminSettings is read fresh, changed in place and written back whole
/// as Teams does. Returns the new settings.
pub async fn set_team_settings(client: &TeamsClient, team_thread: &str, changes: &serde_json::Value) -> Result<String> {
    let mut s = space_admin_settings(client, team_thread).await?;
    for section in ["userSettings", "guestSettings"] {
        if let Some(map) = changes[section].as_object() {
            for (k, v) in map {
                s = with_space_setting(&s, section, k, v)?;
            }
        }
    }
    let url = format!(
        "{}/v1/threads/{}/properties?name=spaceAdminSettings",
        client.chat_service_url(),
        enc(team_thread)
    );
    client
        .chat_request(reqwest::Method::PUT, &url, &serde_json::json!({ "spaceAdminSettings": s }))
        .await?;
    Ok(s)
}

/// Teams' body for Edit team details: the changed fields with Teams'
/// naming-policy fields.
pub fn edit_team_body(name: Option<&str>, description: Option<&str>, public: Option<bool>) -> serde_json::Value {
    let mut b = serde_json::Map::new();
    if let Some(n) = name {
        b.insert("displayName".into(), serde_json::json!(n.trim()));
    }
    if let Some(d) = description {
        b.insert("description".into(), serde_json::json!(d));
    }
    if let Some(p) = public {
        b.insert("accessType".into(), serde_json::json!(if p { "Public" } else { "Private" }));
    }
    b.insert("displayNamePrefix".into(), serde_json::json!(""));
    b.insert("displayNameSuffix".into(), serde_json::json!(""));
    b.insert("validationRequired".into(), serde_json::json!(false));
    serde_json::Value::Object(b)
}

/// Edit a team's name, description or privacy
/// (`PATCH {mt}/beta/teams/{teamThread}`).
pub async fn edit_team(client: &TeamsClient, team_thread: &str, name: Option<&str>, description: Option<&str>, public: Option<bool>) -> Result<()> {
    let (base, token) = middle_tier(client).await?;
    client
        .http()
        .patch(format!("{base}/beta/teams/{team_thread}"))
        .bearer_auth(&token)
        .json(&edit_team_body(name, description, public))
        .send()
        .await?
        .error_for_status()
        .context("Edit team")?;
    Ok(())
}

/// Teams' default picture for a team name (the initials picture Remove puts
/// back): `GET {mt}/beta/teams/defaultProfilePicture?displayName=…&highResolution=true`.
pub async fn team_default_picture(client: &TeamsClient, name: &str) -> Result<Vec<u8>> {
    let (base, token) = middle_tier(client).await?;
    let bytes = client
        .http()
        .get(format!(
            "{base}/beta/teams/defaultProfilePicture?displayName={}&highResolution=true",
            url::form_urlencoded::byte_serialize(name.as_bytes()).collect::<String>()
        ))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Default team picture")?
        .bytes()
        .await?;
    // Teams' service answers with the picture's bytes or, in some regions,
    // with them base64-encoded.
    use base64::Engine as _;
    if let Ok(text) = std::str::from_utf8(&bytes)
        && let Ok(raw) = base64::engine::general_purpose::STANDARD.decode(text.trim().trim_matches('"'))
    {
        return Ok(raw);
    }
    Ok(bytes.to_vec())
}

/// Set a team's picture (`POST {mt}/beta/teams/{group}/profilepicture?threadId={teamThread}`
/// with the image as the body, as Teams sends it).
pub async fn set_team_picture(client: &TeamsClient, group_id: &str, team_thread: &str, image: Vec<u8>) -> Result<()> {
    let (base, token) = middle_tier(client).await?;
    client
        .http()
        .post(format!("{base}/beta/teams/{group_id}/profilepicture?threadId={team_thread}"))
        .bearer_auth(&token)
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(image)
        .send()
        .await?
        .error_for_status()
        .context("Team picture")?;
    Ok(())
}

/// A team's join code: read (GET), make or reset (PUT), remove (DELETE)
/// at `{mt}/beta/teams/{teamThread}/joinCode`. The code, when there is one.
pub async fn team_join_code(client: &TeamsClient, team_thread: &str, method: reqwest::Method) -> Result<Option<String>> {
    let (base, token) = middle_tier(client).await?;
    let mut req = client
        .http()
        .request(method.clone(), format!("{base}/beta/teams/{team_thread}/joinCode"))
        .bearer_auth(&token);
    if method != reqwest::Method::GET {
        req = req.header(reqwest::header::CONTENT_TYPE, "application/json").body("");
    }
    let resp = req.send().await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if status.as_u16() == 404 || status.as_u16() == 204 {
        return Ok(None);
    }
    if !status.is_success() {
        bail!("Team code: {status} {}", text.chars().take(200).collect::<String>());
    }
    Ok(join_code_from(&text))
}

/// The code in a joinCode reply (a JSON string, `{value}` or `{joinCode}`).
pub fn join_code_from(text: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(text).unwrap_or(serde_json::Value::String(text.trim().to_string()));
    let code = v
        .as_str()
        .or_else(|| v["value"].as_str())
        .or_else(|| v["joinCode"].as_str())
        .or_else(|| v["value"]["joinCode"].as_str())
        .unwrap_or_default()
        .trim()
        .trim_matches('"')
        .to_string();
    (!code.is_empty() && code != "null").then_some(code)
}

/// Set who may post in General: the team thread's spaceAdminSettings,
/// read fresh and written back whole (PUT …/threads/{team}/properties).
pub async fn set_general_channel_setting(client: &TeamsClient, team_thread: &str, value: u8) -> Result<()> {
    let current = space_admin_settings(client, team_thread).await?;
    let updated = with_general_channel_setting(&current, value.min(2))?;
    let url = format!(
        "{}/v1/threads/{}/properties?name=spaceAdminSettings",
        client.chat_service_url(),
        enc(team_thread)
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "spaceAdminSettings": updated }),
        )
        .await?;
    Ok(())
}

/// A channel's moderation settings (Manage channel ▸ Settings ▸ Moderation
/// for a channel other than General): the channel thread's
/// `channelSettings` property, a JSON string of numbers Teams writes back
/// whole (captured 2026-11-09).
/// - `post`: who can start a new post: 0 everyone, 1 only moderators
///   (moderation On), 2 everyone except guests.
/// - `replies` / `pins`: whether members may reply / pin (0 everyone, 1
///   moderators only, on the wire).
/// - `bots` / `connectors`: whether bots / connectors may post (1 allowed).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct ChannelSettings {
    pub post: u8,
    pub replies: bool,
    pub pins: bool,
    pub bots: bool,
    pub connectors: bool,
}

impl Default for ChannelSettings {
    /// Teams' defaults (an unset property): everyone posts, replies and
    /// pins; bots and connectors may post.
    fn default() -> Self {
        Self { post: 0, replies: true, pins: true, bots: true, connectors: true }
    }
}

impl ChannelSettings {
    /// Whether the channel is moderated (only moderators start posts).
    pub fn moderated(&self) -> bool {
        self.post == 1
    }
}

/// The settings in a `channelSettings` property (Teams' defaults for
/// anything missing or unreadable).
pub fn channel_settings_from(s: &str) -> ChannelSettings {
    let d = ChannelSettings::default();
    let Ok(v) = serde_json::from_str::<serde_json::Value>(s) else {
        return d;
    };
    let n = |k: &str| v[k].as_u64();
    ChannelSettings {
        post: n("postPermissions").map(|p| p.min(2) as u8).unwrap_or(d.post),
        replies: n("allowReplies").map(|x| x == 0).unwrap_or(d.replies),
        pins: n("allowPinPosts").map(|x| x == 0).unwrap_or(d.pins),
        bots: n("allowBotsPost").map(|x| x != 0).unwrap_or(d.bots),
        connectors: n("allowConnectorsPost").map(|x| x != 0).unwrap_or(d.connectors),
    }
}

/// The property as Teams writes it (its key order).
pub fn channel_settings_wire(s: &ChannelSettings) -> String {
    format!(
        "{{\"allowReplies\":{},\"allowPinPosts\":{},\"allowBotsPost\":{},\"allowConnectorsPost\":{},\"postPermissions\":{}}}",
        u8::from(!s.replies),
        u8::from(!s.pins),
        u8::from(s.bots),
        u8::from(s.connectors),
        s.post.min(2)
    )
}

/// A channel's moderation settings, read from its thread.
pub async fn channel_settings(client: &TeamsClient, channel: &str) -> Result<ChannelSettings> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        enc(channel)
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Channel")?;
    Ok(channel_settings_from(v["properties"]["channelSettings"].as_str().unwrap_or_default()))
}

/// Write a channel's moderation settings (PUT
/// …/threads/{channel}/properties?name=channelSettings).
pub async fn set_channel_settings(client: &TeamsClient, channel: &str, s: &ChannelSettings) -> Result<()> {
    let url = format!(
        "{}/v1/threads/{}/properties?name=channelSettings",
        client.chat_service_url(),
        enc(channel)
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &serde_json::json!({ "channelSettings": channel_settings_wire(s) }),
        )
        .await?;
    Ok(())
}

/// Someone in a moderation list: a team owner, a moderator, or a team
/// member found by name.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct ModerationPerson {
    pub mri: String,
    pub name: String,
    pub mail: String,
    /// What Teams shows under the name in search results: "(ALIAS) job
    /// title", or the job title alone.
    pub detail: String,
}

/// The people of a thread's member list with their names (Graph).
async fn named_members(client: &TeamsClient, url: &str) -> Result<Vec<ModerationPerson>> {
    let v: serde_json::Value = client.chat_get(url).await?.json().await.context("Members")?;
    let mut out = Vec::new();
    for m in v["members"].as_array().into_iter().flatten() {
        let Some(mri) = m["id"].as_str() else { continue };
        let mut p = ModerationPerson { mri: mri.to_string(), ..Default::default() };
        if let Some(oid) = mri.strip_prefix("8:orgid:")
            && uuid::Uuid::parse_str(oid).is_ok()
            && let Ok(resp) = client
                .graph_get(&format!("/users/{oid}?$select=displayName,mail,userPrincipalName"))
                .await
            && let Ok(u) = resp.json::<serde_json::Value>().await
        {
            p.name = u["displayName"].as_str().unwrap_or_default().to_string();
            p.mail = u["mail"]
                .as_str()
                .or_else(|| u["userPrincipalName"].as_str())
                .unwrap_or_default()
                .to_string();
        }
        out.push(p);
    }
    Ok(out)
}

/// A channel's added moderators (its thread's members flagged
/// `isModerator`, as Teams asks for them).
pub async fn channel_moderators(client: &TeamsClient, channel: &str) -> Result<Vec<ModerationPerson>> {
    let url = format!(
        "{}/v1/threads/{}/members?view=msnp24Equivalent&pageSize=100&filterOnIsModerator=true",
        client.chat_service_url(),
        enc(channel)
    );
    named_members(client, &url).await
}

/// A team's owners (its thread's Admin members); in a standard channel
/// they are always moderators.
pub async fn team_owners(client: &TeamsClient, team_thread: &str) -> Result<Vec<ModerationPerson>> {
    let url = format!(
        "{}/v1/threads/{}/members?view=msnp24Equivalent&pageSize=100&selectMemberRoles=Admin",
        client.chat_service_url(),
        enc(team_thread)
    );
    named_members(client, &url).await
}

/// "(ALIAS) job title" as Teams' moderator search shows it under a name:
/// the part of the UPN before "@" in capitals, then the job title.
pub fn moderation_detail(upn: &str, job_title: &str) -> String {
    match upn.split_once('@') {
        Some((alias, _)) => format!("({}) {}", alias.to_uppercase(), job_title).trim_end().to_string(),
        None => job_title.to_string(),
    }
}

/// Team members matching a name, for Add or remove moderators: the user
/// profile service's team profile search (POST
/// …/userprofilesvc/…/api/v1.0/teams/{teamThread}/users/profilesearch,
/// `{"keyword"}`, guests left out), as Teams searches.
pub async fn search_team_members(client: &TeamsClient, team_thread: &str, query: &str) -> Result<Vec<ModerationPerson>> {
    let base = client
        .region_endpoint("userProfileService")
        .unwrap_or_else(|| "https://teams.microsoft.com/api/userprofilesvc/amer".to_string());
    let token = super::directory::middle_tier_token().await?;
    let resp = client
        .http()
        .post(format!(
            "{base}/api/v1.0/teams/{}/users/profilesearch?top=100&includeDLs=false&includeBots=false&enableGuest=false",
            enc(team_thread)
        ))
        .bearer_auth(&token)
        .header("x-ms-client-type", "web")
        .json(&serde_json::json!({ "keyword": query }))
        .send()
        .await?
        .error_for_status()?;
    let v: serde_json::Value = resp.json().await.context("Profile search")?;
    Ok(v.as_array()
        .into_iter()
        .flatten()
        .filter_map(|u| {
            Some(ModerationPerson {
                mri: u["mri"].as_str()?.to_string(),
                name: u["displayName"].as_str().unwrap_or_default().to_string(),
                mail: u["email"].as_str().unwrap_or_default().to_string(),
                detail: moderation_detail(
                    u["userPrincipalName"].as_str().unwrap_or_default(),
                    u["jobTitle"].as_str().unwrap_or_default(),
                ),
            })
        })
        .collect())
}

/// The members body for adding and removing moderators: added ones
/// `{id, isModerator: true, expiration: 0}`, removed ones `{id,
/// isModerator: false}` (Teams' channel-thread roster update, no role).
pub fn moderators_body(add: &[String], remove: &[String]) -> serde_json::Value {
    let members: Vec<serde_json::Value> = add
        .iter()
        .map(|id| serde_json::json!({ "id": id, "isModerator": true, "expiration": 0 }))
        .chain(remove.iter().map(|id| serde_json::json!({ "id": id, "isModerator": false })))
        .collect();
    serde_json::json!({ "members": members })
}

/// Add and remove a standard channel's moderators (PUT
/// …/threads/{channel}/members).
pub async fn set_moderators(client: &TeamsClient, channel: &str, add: &[String], remove: &[String]) -> Result<()> {
    if add.is_empty() && remove.is_empty() {
        return Ok(());
    }
    let url = format!("{}/v1/threads/{}/members", client.chat_service_url(), enc(channel));
    client
        .chat_request(reqwest::Method::PUT, &url, &moderators_body(add, remove))
        .await?;
    Ok(())
}

/// Someone (or a group) offered by Add members to {team}.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct AddCandidate {
    /// `8:orgid:{objectId}` (empty for a group).
    pub mri: String,
    pub object_id: String,
    pub name: String,
    pub mail: String,
    /// The second line: a person's alias in capitals (Teams' "RANDY"), a
    /// group's e-mail address.
    pub detail: String,
    pub group: bool,
}

/// A searchV2 result as Add members shows it.
pub fn add_candidate_from(v: &serde_json::Value) -> Option<AddCandidate> {
    let s = |k: &str| v[k].as_str().unwrap_or_default().to_string();
    let object_id = s("objectId");
    if object_id.is_empty() {
        return None;
    }
    let group = v["objectType"].as_str() == Some("Group") || v["type"].as_str() == Some("Group");
    let mail = [s("email"), s("mail"), s("userPrincipalName")]
        .into_iter()
        .find(|m| !m.is_empty())
        .unwrap_or_default();
    let detail = if group {
        mail.clone()
    } else {
        s("userPrincipalName").split('@').next().unwrap_or_default().to_uppercase()
    };
    Some(AddCandidate {
        mri: if group {
            String::new()
        } else {
            v["mri"].as_str().map(str::to_string).unwrap_or_else(|| format!("8:orgid:{object_id}"))
        },
        object_id,
        name: s("displayName"),
        mail,
        detail,
        group,
    })
}

/// People, groups and distribution lists for Add members, as Teams
/// searches (`POST {mt}/beta/users/searchV2?…&source=addToTeam`, the query
/// as the body).
pub async fn search_add_candidates(client: &TeamsClient, query: &str) -> Result<Vec<AddCandidate>> {
    let (base, token) = middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!(
            "{base}/beta/users/searchV2?includeDLs=true&enableGuest=true&includeBots=true&skypeTeamsInfo=true&source=addToTeam"
        ))
        .bearer_auth(&token)
        .header("content-type", "text/plain")
        .body(query.to_string())
        .send()
        .await?
        .error_for_status()?
        .json()
        .await
        .context("Search")?;
    Ok(v["value"].as_array().into_iter().flatten().filter_map(add_candidate_from).collect())
}

/// A group's people (the members a group brings to the team).
pub async fn group_people(client: &TeamsClient, group_id: &str) -> Result<Vec<AddCandidate>> {
    if uuid::Uuid::parse_str(group_id).is_err() {
        bail!("Not a group");
    }
    let v: serde_json::Value = client
        .graph_get(&format!(
            "/groups/{group_id}/transitiveMembers/microsoft.graph.user?$select=id,displayName,mail,userPrincipalName&$top=999"
        ))
        .await?
        .json()
        .await
        .context("Group members")?;
    Ok(v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|u| {
            let id = u["id"].as_str()?.to_string();
            let upn = u["userPrincipalName"].as_str().unwrap_or_default();
            Some(AddCandidate {
                mri: format!("8:orgid:{id}"),
                object_id: id,
                name: u["displayName"].as_str().unwrap_or_default().to_string(),
                mail: u["mail"].as_str().unwrap_or(upn).to_string(),
                detail: upn.split('@').next().unwrap_or_default().to_uppercase(),
                group: false,
            })
        })
        .collect())
}

/// The members of a team (its thread's roster, MRIs in lower case).
pub async fn team_member_mris(client: &TeamsClient, team_thread: &str) -> Result<Vec<String>> {
    let url = format!(
        "{}/v1/threads/{}/members?view=msnp24Equivalent&pageSize=100",
        client.chat_service_url(),
        enc(team_thread)
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await.context("Members")?;
    Ok(v["members"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| m["id"].as_str().map(|s| s.to_ascii_lowercase()))
        .collect())
}

/// Teams' body for adding people with their roles (the middle tier's
/// numbering: 0 member, 1 owner): `{"users": [{mri, role}], "groupId"}`.
pub fn add_members_body(group_id: &str, users: &[(String, bool)]) -> serde_json::Value {
    serde_json::json!({
        "users": users
            .iter()
            .map(|(mri, owner)| serde_json::json!({ "mri": mri, "role": u8::from(*owner) }))
            .collect::<Vec<_>>(),
        "groupId": group_id,
    })
}

/// What adding people did: who joined and who couldn't be added.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct AddOutcome {
    pub added: usize,
    pub failed: usize,
}

/// Add people to a team (`PUT {mt}/beta/teams/{teamThread}/bulkUpdateRoledMembers?allowAsyncAddition=true`).
pub async fn add_team_members(client: &TeamsClient, team_thread: &str, group_id: &str, users: &[(String, bool)]) -> Result<AddOutcome> {
    if users.is_empty() {
        return Ok(AddOutcome::default());
    }
    let (base, token) = middle_tier(client).await?;
    let resp = client
        .http()
        .put(format!("{base}/beta/teams/{}/bulkUpdateRoledMembers?allowAsyncAddition=true", enc(team_thread)))
        .bearer_auth(&token)
        .json(&add_members_body(group_id, users))
        .send()
        .await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("Add members: {status} {}", text.chars().take(200).collect::<String>());
    }
    let v: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    let count = |k: &str| v["value"][k].as_array().or_else(|| v[k].as_array()).map(|a| a.len());
    let failed = count("erroredMembers").unwrap_or(0);
    Ok(AddOutcome { added: users.len().saturating_sub(failed), failed })
}

/// Invite someone outside the organisation as a guest of the team
/// (`PUT {mt}/beta/teams/{teamThread}/{groupId}/inviteAndAddGuest`).
pub async fn invite_guest(client: &TeamsClient, team_thread: &str, group_id: &str, email: &str, name: &str) -> Result<()> {
    let (base, token) = middle_tier(client).await?;
    let resp = client
        .http()
        .put(format!("{base}/beta/teams/{}/{}/inviteAndAddGuest", enc(team_thread), enc(group_id)))
        .bearer_auth(&token)
        .json(&guest_body(email, name))
        .send()
        .await?;
    let status = resp.status();
    if !status.is_success() {
        bail!("Invite guest: {status}");
    }
    Ok(())
}

/// Teams' guest invitation: the address and name, with Teams' notice.
pub fn guest_body(email: &str, name: &str) -> serde_json::Value {
    serde_json::json!({
        "emailAddress": email.trim(),
        "displayName": name.trim(),
        "enableInviteTeamsNotification": true,
        "userType": "Guest",
    })
}

/// One analytics metric: its total and its days.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Metric {
    pub value: Option<f64>,
    pub series: Vec<(String, f64)>,
}

/// A channel's (or team's) analytics for a period, as Teams' dashboard
/// reads them: totals and per-day series of active users, posts, replies,
/// reactions, mentions, meetings organized (and guests for a team).
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Analytics {
    pub start: String,
    pub end: String,
    pub metrics: std::collections::BTreeMap<String, Metric>,
}

/// Teams' summary-timeseries answer ({channels|teams: {metrics: {name:
/// {value, timeSeries: [{value, date}]}}}, startDate, endDate, errorCode}).
/// Like Teams, any errorCode but 2 (nothing to report) is a failure.
pub fn analytics_from(v: &serde_json::Value) -> Result<Analytics> {
    if let Some(code) = v.get("errorCode").filter(|c| !c.is_null())
        && code.as_str() != Some("")
        && !matches!(code.as_i64(), Some(0) | Some(2))
    {
        bail!("Analytics error {code}");
    }
    let holder = v.get("channels").or_else(|| v.get("teams")).cloned().unwrap_or_default();
    let holder = holder.as_array().and_then(|a| a.first().cloned()).unwrap_or(holder);
    let mut metrics = std::collections::BTreeMap::new();
    if let Some(m) = holder["metrics"].as_object() {
        for (name, metric) in m {
            let series = metric["timeSeries"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|p| {
                    (
                        p["date"].as_str().unwrap_or_default().to_string(),
                        p["value"].as_f64().unwrap_or(0.0),
                    )
                })
                .collect();
            metrics.insert(name.clone(), Metric { value: metric["value"].as_f64(), series });
        }
    }
    Ok(Analytics {
        start: v["startDate"].as_str().unwrap_or_default().to_string(),
        end: v["endDate"].as_str().unwrap_or_default().to_string(),
        metrics,
    })
}

/// Teams' periods: "last-seven-days", "last-thirty-days", "last-ninety-days".
pub fn analytics_period(p: &str) -> &'static str {
    match p {
        "last-thirty-days" | "LAST_THIRTY_DAYS" => "last-thirty-days",
        "last-ninety-days" | "LAST_NINETY_DAYS" => "last-ninety-days",
        _ => "last-seven-days",
    }
}

/// Analytics for a channel (`channel` set) or the whole team, from the
/// middle tier's summary-timeseries, with the series Teams asks for.
pub async fn analytics(client: &TeamsClient, team_id: &str, channel: Option<&str>, period: &str) -> Result<Analytics> {
    let (base, token) = middle_tier(client).await?;
    let url = match channel {
        Some(c) => format!(
            "{base}/beta/analytics/teams/{team_id}/channels/{c}/summary-timeseries?metric=all&timeperiod={}&includeTimeseries={}",
            analytics_period(period),
            enc("activeUsers,postMessages,replyMessages,reactions,mentions,meetingsOrganized")
        ),
        None => format!(
            "{base}/beta/analytics/teams/{team_id}/summary-timeseries?metric=all&timeperiod={}&includeTimeseries={}",
            analytics_period(period),
            enc("activeUsers,postMessages,replyMessages,reactions,mentions,meetingsOrganized,guests")
        ),
    };
    let v: serde_json::Value = client
        .http()
        .get(url)
        .bearer_auth(&token)
        .header("x-ms-client-caller", if channel.is_some() { "tca-pc" } else { "tca-pt" })
        .send()
        .await?
        .error_for_status()
        .context("Analytics")?
        .json()
        .await
        .context("Analytics")?;
    analytics_from(&v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notification_settings_are_teams() {
        // Teams' values for each choice (captured).
        assert_eq!(
            Notify::for_mode(NotifyMode::All, None).settings_json(),
            r#"{"allNewPosts":"On","tag":"On","channelTeam":"On","dskNotif":null}"#
        );
        assert_eq!(
            Notify::for_mode(NotifyMode::Mentions, None).settings_json(),
            r#"{"allNewPosts":"Off","tag":"On","channelTeam":"On","dskNotif":null}"#
        );
        assert_eq!(
            Notify::for_mode(NotifyMode::Mute, None).settings_json(),
            r#"{"allNewPosts":"Off","tag":"Off","channelTeam":"Off","dskNotif":null}"#
        );
        let read = Notify::from_properties(r#"{"allNewPosts":"Off","tag":"On","channelTeam":"On","dskNotif":null}"#, true);
        assert_eq!(read.mode, NotifyMode::Mentions);
        assert_eq!(Notify::from_properties(r#"{"allNewPosts":"On","tag":"On","channelTeam":"On"}"#, true).mode, NotifyMode::All);
        assert_eq!(Notify::from_properties("", false).mode, NotifyMode::Mute);
        let s = notify_state_from(&serde_json::json!({"alerts": "true", "followAllRc": "1794248093719"}));
        assert!(s.follow_all && s.notify.mode == NotifyMode::Mentions);
    }

    #[test]
    fn channel_settings_are_teams() {
        // Teams' writes on "OST test channel" (2026-11-09): moderation On,
        // then Off.
        let on = ChannelSettings { post: 1, ..Default::default() };
        assert_eq!(
            channel_settings_wire(&on),
            r#"{"allowReplies":0,"allowPinPosts":0,"allowBotsPost":1,"allowConnectorsPost":1,"postPermissions":1}"#
        );
        assert_eq!(
            channel_settings_wire(&ChannelSettings::default()),
            r#"{"allowReplies":0,"allowPinPosts":0,"allowBotsPost":1,"allowConnectorsPost":1,"postPermissions":0}"#
        );
        // Read back, and Teams' defaults for an unset property.
        assert_eq!(channel_settings_from(&channel_settings_wire(&on)), on);
        assert!(channel_settings_from(&channel_settings_wire(&on)).moderated());
        assert_eq!(channel_settings_from(""), ChannelSettings::default());
        let s = channel_settings_from(r#"{"allowReplies":1,"allowPinPosts":1,"allowBotsPost":0,"allowConnectorsPost":0,"postPermissions":2}"#);
        assert_eq!(s, ChannelSettings { post: 2, replies: false, pins: false, bots: false, connectors: false });
    }

    #[test]
    fn add_members_are_teams() {
        // searchV2 results captured from Teams' Add members (2026-11-09).
        let group: serde_json::Value = serde_json::from_str(r#"{"isUnified":true,"alias":"OSTTestTeam","mail":"OSTTestTeam@scnetsolutions.com","objectType":"Group","id":"1fac3ae3-c9c0-4ddb-90bb-58f52209c181@2716d134-5614-4856-a48d-2002edd9a570","peopleType":"Group","text":"OST Test Team","userPrincipalName":"OSTTestTeam@scnetsolutions.com","email":"OSTTestTeam@scnetsolutions.com","displayName":"OST Test Team","type":"Group","objectId":"1fac3ae3-c9c0-4ddb-90bb-58f52209c181"}"#).unwrap();
        let g = add_candidate_from(&group).unwrap();
        assert!(g.group && g.mri.is_empty());
        assert_eq!(g.detail, "OSTTestTeam@scnetsolutions.com");
        let person: serde_json::Value = serde_json::from_str(r#"{"alias":"RandyNorthrup","mail":"Randy@scnetsolutions.com","objectType":"User","userPrincipalName":"Randy@scnetsolutions.com","email":"Randy@scnetsolutions.com","displayName":"Randy Northrup","type":"ADUser","mri":"8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3","objectId":"5050c9d6-b8a7-41f2-830a-0c51777b7dc3"}"#).unwrap();
        let p = add_candidate_from(&person).unwrap();
        assert_eq!((p.mri.as_str(), p.detail.as_str(), p.group), ("8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3", "RANDY", false));
        // The roles in the middle tier's numbering.
        assert_eq!(
            add_members_body("g", &[("8:orgid:a".into(), false), ("8:orgid:b".into(), true)]).to_string(),
            r#"{"groupId":"g","users":[{"mri":"8:orgid:a","role":0},{"mri":"8:orgid:b","role":1}]}"#
        );
        assert_eq!(guest_body(" a@example.com ", "A")["emailAddress"], "a@example.com");
    }

    #[test]
    fn private_channel_body_is_teams() {
        // Teams' Create a channel for a private channel (2026-11-09).
        assert_eq!(
            private_channel_body("19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2", "OST private test", "", "Private", "Conversational", "b3aabdfd-cc3d-44fa-a183-81c1891c3847").to_string(),
            r#"{"channelType":"Private","chatModalityType":"Conversational","description":"","displayName":"OST private test","sessionKey":"b3aabdfd-cc3d-44fa-a183-81c1891c3847","sharedWithParentTeam":true,"spaceThreadId":"19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2"}"#
        );
    }

    #[test]
    fn private_channel_group_from_properties() {
        let p = serde_json::json!({
            "threadSubType": "PrivateChannel",
            "substrateGroupId": "a46d52cc-4d7c-4003-976b-9952e3f71ea7",
            "tenantid": "2716d134-5614-4856-a48d-2002edd9a570",
            "groupId": "1fac3ae3-c9c0-4ddb-90bb-58f52209c181",
        });
        assert_eq!(
            private_channel_group(&p).as_deref(),
            Some("OID:a46d52cc-4d7c-4003-976b-9952e3f71ea7@2716d134-5614-4856-a48d-2002edd9a570")
        );
        assert_eq!(enc("OID:a@b"), "OID%3Aa%40b");
        assert_eq!(private_channel_group(&serde_json::json!({ "threadSubType": "Space" })), None);
    }

    #[test]
    fn team_settings_change_in_place() {
        let s = r#"{"userSettings":{"generalChannelSetting":0,"teamMention":true,"uploadCustomApp":true,"createTab":true},"guestSettings":{"createTopic":false,"deleteTopic":false}}"#;
        let t = with_space_setting(s, "userSettings", "uploadCustomApp", &serde_json::json!(false)).unwrap();
        assert_eq!(t, r#"{"userSettings":{"generalChannelSetting":0,"teamMention":true,"uploadCustomApp":false,"createTab":true},"guestSettings":{"createTopic":false,"deleteTopic":false}}"#);
        let t = with_space_setting(&t, "guestSettings", "deleteTopic", &serde_json::json!(true)).unwrap();
        assert!(t.ends_with(r#""deleteTopic":true}}"#));
        let t = with_space_setting(&t, "userSettings", "giphyRating", &serde_json::json!(0)).unwrap();
        assert!(t.contains(r#""createTab":true,"giphyRating":0}"#));
        // Teams' Edit team details body (captured 2026-11-09).
        assert_eq!(
            edit_team_body(None, Some("Test team for the OST desktop client (safe to delete). X"), None).to_string(),
            r#"{"description":"Test team for the OST desktop client (safe to delete). X","displayNamePrefix":"","displayNameSuffix":"","validationRequired":false}"#
        );
        assert_eq!(join_code_from(r#""ab12cd""#).as_deref(), Some("ab12cd"));
        assert_eq!(join_code_from(r#"{"value":"xy"}"#).as_deref(), Some("xy"));
        assert_eq!(join_code_from("null"), None);
    }

    #[test]
    fn join_requests_are_teams() {
        // Teams' empty reply for OST Test Team, and the shape Teams reads.
        assert!(join_requests_from(&serde_json::json!({"joinRequestsPerTeam":{}}), "g").is_empty());
        let v = serde_json::json!({"joinRequestsPerTeam":{"g":[{"user":{"mri":"8:orgid:a","displayName":"A","jobTitle":"T","userLocation":"L"},"sponsors":[{"displayName":"S"}]}]}});
        assert_eq!(join_requests_from(&v, "g"), vec![JoinRequest { mri: "8:orgid:a".into(), name: "A".into(), title: "T".into(), location: "L".into(), requested_by: vec!["S".into()] }]);
    }

    #[test]
    fn roster_and_membership_are_teams() {
        // Teams' Members tab reads (2026-11-09): bots are left out.
        let v = serde_json::json!({"members":[
            {"id":"28:0af95b67-5890-4306-9c1c-a8591cead09e","role":"User"},
            {"id":"8:orgid:4287e791-1b98-4963-8b94-281c50472683","role":"Admin"}]});
        let r = roster_from(&v);
        assert_eq!(r.len(), 1);
        assert_eq!((r[0].mri.as_str(), r[0].role.as_str()), ("8:orgid:4287e791-1b98-4963-8b94-281c50472683", "Admin"));
        assert_eq!(
            membership_body("8:orgid:a", "DemotedAndLeft", "g").to_string(),
            r#"{"groupId":"g","updateType":"DemotedAndLeft","userMri":"8:orgid:a"}"#
        );
    }

    #[test]
    fn moderator_changes_are_teams() {
        let b = moderators_body(&["8:orgid:a".into()], &["8:orgid:b".into()]);
        assert_eq!(
            b.to_string(),
            r#"{"members":[{"expiration":0,"id":"8:orgid:a","isModerator":true},{"id":"8:orgid:b","isModerator":false}]}"#
        );
        // Search results' second line, as Teams builds it.
        assert_eq!(moderation_detail("ost-test1@scnetsolutions.com", ""), "(OST-TEST1)");
        assert_eq!(moderation_detail("ab@x.com", "Engineer"), "(AB) Engineer");
        assert_eq!(moderation_detail("", "Engineer"), "Engineer");
    }

    #[test]
    fn team_link_is_teams() {
        // Teams' Copy link on OST Test Team's row (winpc clipboard,
        // 2026-11-09).
        let (url, html) = team_link(
            "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2",
            "General",
            "OST Test Team",
            "1fac3ae3-c9c0-4ddb-90bb-58f52209c181",
            "2716d134-5614-4856-a48d-2002edd9a570",
        );
        assert_eq!(url, "https://teams.microsoft.com/l/team/19%3AekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1%40thread.tacv2/conversations?groupId=1fac3ae3-c9c0-4ddb-90bb-58f52209c181&tenantId=2716d134-5614-4856-a48d-2002edd9a570");
        assert_eq!(html, "<a href=\"https://teams.microsoft.com/l/team/19%3AekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1%40thread.tacv2/conversations?groupId=1fac3ae3-c9c0-4ddb-90bb-58f52209c181&amp;tenantId=2716d134-5614-4856-a48d-2002edd9a570\">General | OST Test Team</a>");
    }

    #[test]
    fn channel_link_is_teams() {
        // Teams' Copy link for OST Test Team > General (read from the
        // clipboard on winpc).
        let (url, html) = channel_link(
            "19:ekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1@thread.tacv2",
            "General",
            "1fac3ae3-c9c0-4ddb-90bb-58f52209c181",
            "2716d134-5614-4856-a48d-2002edd9a570",
        );
        assert_eq!(url, "https://teams.microsoft.com/l/channel/19%3AekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1%40thread.tacv2/General?groupId=1fac3ae3-c9c0-4ddb-90bb-58f52209c181&tenantId=2716d134-5614-4856-a48d-2002edd9a570");
        assert_eq!(html, "<a href=\"https://teams.microsoft.com/l/channel/19%3AekCPvoD9glVOIeBqbQQXdfV-vTnBPkGFtas97c_IYnA1%40thread.tacv2/General?groupId=1fac3ae3-c9c0-4ddb-90bb-58f52209c181&amp;tenantId=2716d134-5614-4856-a48d-2002edd9a570\">General</a>");
        assert!(channel_link("19:a@thread.tacv2", "Q&A team", "g", "t").0.contains("/Q%26A%20team?"));
    }

    #[test]
    fn edits_send_only_what_changed() {
        let e = Edit { layout: Some("Conversational".into()), ..Default::default() };
        assert_eq!(serde_json::to_string(&e).unwrap(), r#"{"chatModalityType":"Conversational"}"#);
        assert_eq!(name_error("", false), None);
        assert_eq!(name_error("a/b", false), Some("We don't support these characters: ~#%&*{}+/\\:<>?|'\".."));
        assert_eq!(name_error("a..b", false), name_error("a/b", false));
        assert_eq!(name_error("_x", false), Some("Channel name cannot start with an underscore (_) or a period (.)"));
        assert_eq!(name_error("x.", false), Some("Channel name cannot end with a period (.)"));
        assert_eq!(name_error("see www.example.com", false), Some("Links are not allowed in the channel name"));
        assert_eq!(name_error("Weekly sync", false), None);
        assert_eq!(name_error("x/", true), None);
        let v = serde_json::json!({"emailAddressDetails":{"emailId":"8156404b.scnetsolutions.com@amer.teams.ms"},"allowedSenders":{"allowedSenderType":"members"}});
        assert_eq!(email_from(&v).unwrap().allowed, "members");
        assert_eq!(senders_body("domains", &["a.com".into()]), serde_json::json!({"allowedSenders":{"allowedSenderType":"domains","allowedDomains":["a.com"]}}));
    }

    #[test]
    fn general_setting_is_changed_in_place() {
        // Teams' captured property (abridged): only the number changes.
        let teams = r#"{"userSettings":{"generalChannelSetting":0,"teamMention":true,"channelMention":true},"memberSettings":{}}"#;
        assert_eq!(general_channel_setting(teams), 0);
        let one = with_general_channel_setting(teams, 1).unwrap();
        assert_eq!(one, teams.replace("\"generalChannelSetting\":0", "\"generalChannelSetting\":1"));
        assert_eq!(general_channel_setting(&one), 1);
        assert_eq!(general_channel_setting(""), 0);
        let fresh = with_general_channel_setting("", 2).unwrap();
        assert_eq!(general_channel_setting(&fresh), 2);
    }

    #[test]
    fn analytics_are_read_as_teams() {
        let v = serde_json::json!({
            "channels": { "metrics": {
                "activeUsers": { "value": 1, "timeSeries": [{ "value": 0, "date": "2026-10-30T00:00:00" }, { "value": 1, "date": "2026-10-31T00:00:00" }] },
                "postMessages": { "value": 0, "timeSeries": [] }
            }},
            "startDate": "2026-10-30T00:00:00", "endDate": "2026-11-05T00:00:00", "errorCode": null
        });
        let a = analytics_from(&v).unwrap();
        assert_eq!(a.start, "2026-10-30T00:00:00");
        assert_eq!(a.metrics["activeUsers"].value, Some(1.0));
        assert_eq!(a.metrics["activeUsers"].series.len(), 2);
        assert_eq!(a.metrics["postMessages"].series.len(), 0);
        assert!(analytics_from(&serde_json::json!({ "errorCode": "NotFound" })).is_err());
        assert!(analytics_from(&serde_json::json!({ "errorCode": 5 })).is_err());
        // Teams' "no data" (the test channel's answer): an empty dashboard.
        let none = analytics_from(&serde_json::json!({ "errorCode": 2, "startDate": "2026-10-30T00:00:00" })).unwrap();
        assert!(none.metrics.is_empty());
        assert_eq!(analytics_from(&serde_json::json!({})).unwrap().metrics.len(), 0);
    }
}
