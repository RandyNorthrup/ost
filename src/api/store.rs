//! The Store: Teams apps in your organization's app catalog (Graph's
//! appCatalogs), with their descriptions and icons.

use anyhow::Result;
use serde::Serialize;

use super::client::TeamsClient;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct App {
    pub id: String,
    pub name: String,
    pub short: String,
    pub description: String,
    /// "store" (Teams store) or "organization" (added by your org).
    pub distribution: String,
    /// The app's colour icon on Microsoft's CDN (https), or empty.
    pub icon: String,
}

fn s(v: &serde_json::Value, p: &str) -> String {
    v.pointer(p)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

/// Icons only from Microsoft's CDN over https (they're shown as images).
fn safe_icon(url: &str) -> String {
    let ok = reqwest::Url::parse(url).is_ok_and(|u| {
        u.scheme() == "https"
            && u.host_str().is_some_and(|h| {
                h.ends_with(".cdn.office.net")
                    || h.ends_with(".office.net")
                    || h.ends_with(".microsoft.com")
            })
    });
    if ok { url.to_string() } else { String::new() }
}

/// The first sentence of a (markdown) description, for a card's line.
fn first_sentence(d: &str) -> String {
    let line = d
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty() && !l.starts_with('#'))
        .unwrap_or_default();
    let plain: String = line.chars().filter(|c| !"*_`".contains(*c)).collect();
    let end = plain.find(". ").map(|i| i + 1).unwrap_or(plain.len());
    plain[..end].chars().take(140).collect()
}

/// Every app in the catalog, by name (Graph beta, which carries icons).
pub async fn apps(client: &TeamsClient) -> Result<Vec<App>> {
    let v: serde_json::Value = client
        .graph_beta(
            "/appCatalogs/teamsApps?$expand=appDefinitions($select=displayName,shortDescription,description;$expand=colorIcon($select=webUrl))",
            None,
        )
        .await?
        .json()
        .await?;
    let mut out: Vec<App> = v
        .get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(|a| {
            let id = s(a, "/id");
            let name = s(a, "/displayName");
            (!id.is_empty() && !name.is_empty()).then(|| App {
                id,
                name,
                short: {
                    let short = s(a, "/appDefinitions/0/shortDescription");
                    if short.is_empty() {
                        first_sentence(&s(a, "/appDefinitions/0/description"))
                    } else {
                        short
                    }
                },
                description: s(a, "/appDefinitions/0/description"),
                distribution: s(a, "/distributionMethod"),
                icon: safe_icon(&s(a, "/appDefinitions/0/colorIcon/webUrl")),
            })
        })
        .collect();
    out.sort_by_key(|a| a.name.to_lowercase());
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cards_get_a_first_sentence() {
        assert_eq!(
            first_sentence("**The** Microsoft Whiteboard app in Teams brings ideas. More text."),
            "The Microsoft Whiteboard app in Teams brings ideas."
        );
        assert_eq!(first_sentence("\n# Title\nOne line"), "One line");
        assert_eq!(first_sentence(""), "");
    }

    #[test]
    fn icons_come_only_from_microsoft_over_https() {
        assert!(!safe_icon("https://res.cdn.office.net/teamsappdata/x.png").is_empty());
        assert!(safe_icon("http://res.cdn.office.net/x.png").is_empty());
        assert!(safe_icon("https://evil.example/x.png").is_empty());
        assert!(safe_icon("https://office.net.evil.example/x.png").is_empty());
        assert!(safe_icon("").is_empty());
    }
}
