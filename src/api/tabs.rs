//! A channel's tabs (Graph `/teams/{id}/channels/{id}/tabs`): Page (a
//! Loop page), Notes (OneNote) and any apps added to the channel, with
//! what each shows.

use anyhow::{Result, bail};
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
}

/// Only Microsoft 365 pages over https are shown in a tab.
fn safe_url(url: &str) -> String {
    let ok = reqwest::Url::parse(url).is_ok_and(|u| {
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

fn tabs_from(v: &serde_json::Value) -> Vec<Tab> {
    let s = |t: &serde_json::Value, p: &str| {
        t.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(|t| {
            let name = s(t, "/displayName");
            (!name.is_empty()).then(|| Tab {
                id: s(t, "/id"),
                url: safe_url(&s(t, "/configuration/contentUrl")),
                app: s(t, "/teamsApp/displayName"),
                name,
            })
        })
        .collect()
}

/// The tabs of a channel, in the channel's order.
pub async fn channel_tabs(
    client: &TeamsClient,
    team_id: &str,
    channel_id: &str,
) -> Result<Vec<Tab>> {
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
    let v: serde_json::Value = client
        .graph_get(&format!(
            "/teams/{team_id}/channels/{channel}/tabs?$expand=teamsApp"
        ))
        .await?
        .json()
        .await?;
    Ok(tabs_from(&v))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tabs_keep_microsoft_pages_only() {
        let v = serde_json::json!({"value": [
            {"id": "1", "displayName": "Page", "teamsApp": {"displayName": "Channel Pages"},
             "configuration": {"contentUrl": "https://contoso.sharepoint.com/:fl:/r/sites/x/General/Page.loop?web=1"}},
            {"id": "2", "displayName": "Odd", "teamsApp": {"displayName": "Website"},
             "configuration": {"contentUrl": "https://evil.example/sharepoint.com"}},
            {"id": "3", "displayName": "Plain", "teamsApp": {"displayName": "X"},
             "configuration": {"contentUrl": "http://contoso.sharepoint.com/x"}},
            {"id": "4", "displayName": ""}
        ]});
        let t = tabs_from(&v);
        assert_eq!(t.len(), 3);
        assert_eq!(
            (t[0].name.as_str(), t[0].app.as_str()),
            ("Page", "Channel Pages")
        );
        assert!(t[0].url.starts_with("https://contoso.sharepoint.com/"));
        assert!(t[1].url.is_empty() && t[2].url.is_empty());
    }
}
