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

/// Hide all channels (the team row's menu): Teams' provisioning service,
/// `PUT {teamsAndChannelsProvisioningService}/team/{teamThread}/hide`.
pub async fn hide_all_channels(client: &TeamsClient, team_thread: &str) -> Result<()> {
    let base = client
        .region_endpoint("teamsAndChannelsProvisioningService")
        .context("No Teams provisioning endpoint")?;
    let (_, token) = middle_tier(client).await?;
    client
        .http()
        .put(format!("{}/team/{}/hide", base.trim_end_matches('/'), enc(team_thread)))
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
