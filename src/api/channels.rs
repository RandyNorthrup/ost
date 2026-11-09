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
}
