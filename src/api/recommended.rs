//! OneDrive Home's "For you" cards, as Teams' OneDrive app shows them:
//! your OneDrive's recommendations service
//! (`{personal}/_api/sp.RecentFileCollection.GetRecommendations`, captured
//! on winpc 2026-11-26; its `d.GetRecommendations` is JSON text), less
//! Loop files kept in a Loop workspace (OneDrive's RaaS rule), each with
//! its reason badge, people, time and button as OneDrive's
//! RecommendedStrip words them.

use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;

use super::client::TeamsClient;
use super::sharing;

/// One For you card.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Card {
    pub title: String,
    pub file_name: String,
    /// Extension, lowercase.
    pub kind: String,
    /// OneDrive's type ("Fluid", "Pdf", "Whiteboard", …).
    pub vis_type: String,
    /// The badge's message with the people's names in ("OST Test 3
    /// shared this in a Teams chat"), its first person, and the rest.
    pub reason: String,
    pub actor: String,
    pub rest: String,
    /// The first person's sign-in name (their picture), when there is one.
    pub actor_upn: String,
    /// When (ISO).
    pub time: String,
    /// OneDrive's badge type (1 frequently opened, 2 recently opened, 4
    /// you edited, 9 shared with you, …).
    pub badge: i64,
    /// The badge's glyph, as OneDrive names it ("view", "edit", "share",
    /// "OfficeCatchUp", …).
    pub icon: String,
    /// The button: "open", "comment", "task", "recording" (Go to comment,
    /// Go to task, Watch recording: an activity link), else "open"; with
    /// `summarize` / `recap` when Copilot can summarize it or recap the
    /// meeting (Teams shows those buttons when Copilot is on).
    pub button: String,
    pub summarize: bool,
    pub recap: bool,
    /// Where Open goes (Loop and Whiteboard open on the web), and the
    /// activity link.
    pub url: String,
    pub nav_url: String,
    /// The file's address in its library.
    pub file_url: String,
    /// Graph's ids (row actions, thumbnail) and SharePoint's.
    pub drive_id: String,
    pub item_id: String,
    pub site_url: String,
    pub list_id: String,
    pub unique_id: String,
    /// A picture from the file (OneDrive draws an icon for Loop, OneNote
    /// and Whiteboard).
    pub thumbnail: bool,
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

/// OneDrive's badge glyphs (its activity icon map; FrequentlyOpen and
/// the rest fall back to "OfficeCatchUp").
fn icon(badge: i64) -> &'static str {
    match badge {
        2 => "view",
        4 | 5 | 16 | 17 => "edit",
        6 | 7 | 18 | 19 => "comment",
        8 | 13 | 15 => "reply",
        9 => "share",
        10 => "attach",
        11 | 12 | 20 | 21 | 26 | 27 => "accounts",
        22 => "trending12",
        23 => "calendar",
        28..=35 => "groupedlist",
        _ => "OfficeCatchUp",
    }
}

/// The button an activity link gets (OneDrive's OE map).
fn nav_button(badge: i64) -> &'static str {
    match badge {
        6 | 8 | 11 | 12 | 13 | 15 | 18 | 20 | 21 | 26 | 27 => "comment",
        28..=32 | 34 => "task",
        40 => "recording",
        _ => "open",
    }
}

/// Files Copilot can summarize (OneDrive's list).
const SUMMARIZABLE: &[&str] = &[
    "pdf", "docx", "xlsx", "doc", "odt", "ppt", "pptx", "odp", "rtf", "txt", "htm", "html", "aspx",
    "loop", "fluid", "page",
];

/// A Loop file kept in a Loop workspace (OneDrive leaves these out).
fn raas(src: &Value) -> bool {
    let container = s(&src["ContainerUrl"]);
    src["VisualizationType"].as_str() == Some("Fluid")
        && container
            .split('/')
            .skip(3)
            .take(2)
            .any(|seg| seg.eq_ignore_ascii_case("contentstorage"))
}

/// The cards of a GetRecommendations reply (`me`: your sign-in name).
pub fn cards(reply: &Value, me: &str) -> Vec<Card> {
    // Verbose OData wraps it in `d.GetRecommendations`, plain JSON in
    // `value`; either holds the reply as JSON text.
    let raw = if reply["d"]["GetRecommendations"].is_null() {
        &reply["value"]
    } else {
        &reply["d"]["GetRecommendations"]
    };
    let v: Value = match raw {
        Value::String(t) => serde_json::from_str(t).unwrap_or_default(),
        other => other.clone(),
    };
    let results = v["EntitySets"][0]["ResultSets"][0]["Results"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    results
        .iter()
        .filter(|r| !raas(&r["Source"]))
        .map(|r| card(r, me))
        .collect()
}

fn card(r: &Value, me: &str) -> Card {
    let src = &r["Source"];
    let marker: Value = r["SubstrateSearchExtendedProperties"]["ReasonMarker"]
        .as_str()
        .and_then(|t| serde_json::from_str(t).ok())
        .unwrap_or_default();
    let badge = &marker["Badge"];
    let users: Vec<&Value> = badge["Users"].as_array().into_iter().flatten().collect();
    let format = s(&badge["MessageFormat"]);
    let names: Vec<String> = users.iter().map(|u| s(&u["DisplayName"])).collect();
    let mut reason = format.clone();
    for (i, n) in names.iter().enumerate() {
        reason = reason.replace(&format!("{{{i}}}"), n);
    }
    let (actor, rest) = match format.strip_prefix("{0}") {
        Some(rest) if !names.is_empty() => (names[0].clone(), rest.trim_start().to_string()),
        _ => (String::new(), reason.clone()),
    };
    let kind = s(&src["FileExtension"]).to_ascii_lowercase();
    let vis = s(&src["VisualizationType"]);
    let badge_type = badge["Type"].as_i64().unwrap_or(0);
    let nav_id = s(&badge["NavigationInfo"]["Id"]);
    let web_url = s(&src["WebUrl"]);
    // OneDrive's Copilot rule: prep for a meeting, or shared with you by
    // someone else.
    let shared_by = s(&src["LastShared"]["SharedBy"]["EmailAddresses"][0]["Address"]);
    let copilot_item = badge_type == 23
        || badge_type == 9 && !(shared_by.eq_ignore_ascii_case(me) && !me.is_empty());
    Card {
        title: s(&src["Title"]),
        file_name: s(&src["FileName"]),
        vis_type: vis.clone(),
        reason,
        actor,
        rest,
        actor_upn: users
            .first()
            .map(|u| s(&u["Upn"]))
            .filter(|u| !names.is_empty() && !u.is_empty())
            .unwrap_or_default(),
        time: s(&badge["Timestamp"]),
        badge: badge_type,
        icon: icon(badge_type).into(),
        button: if !web_url.is_empty() && !nav_id.is_empty() {
            nav_button(badge_type).into()
        } else {
            "open".into()
        },
        summarize: copilot_item && SUMMARIZABLE.contains(&kind.as_str()),
        recap: copilot_item && kind == "mp4" && s(&src["ProgId"]) == "Media.Meeting",
        nav_url: if nav_id.is_empty() || web_url.is_empty() {
            String::new()
        } else {
            format!("{web_url}&nav={nav_id}")
        },
        url: if web_url.is_empty() {
            s(&src["Url"])
        } else {
            web_url
        },
        file_url: s(&src["Url"]),
        drive_id: s(&src["OneDriveDriveId"]),
        item_id: s(&src["OneDriveItemId"]),
        site_url: s(&src["SitePath"]),
        list_id: s(&src["ListId"]),
        unique_id: s(&src["UniqueId"]),
        thumbnail: !["Fluid", "Loop", "OneNote", "Whiteboard", "FluidNote"].contains(&vis.as_str()),
        kind,
    }
}

/// How many cards fit (OneDrive: 312 wide cards 16 apart, 354 from a
/// 1464 px strip; at least 3, at most 8; the strip scrolls sideways).
pub fn tiles(width: f64) -> usize {
    let tile = if width < 1464.0 { 312.0 } else { 354.0 };
    (((width + 16.0) / (tile + 16.0)).floor() as usize).clamp(3, 8)
}

/// Your For you cards.
pub async fn load(client: &TeamsClient) -> Result<Vec<Card>> {
    let personal = super::quick_access::personal_site(client).await?;
    let reply = sharing::get_with(
        &format!("{personal}/_api/sp.RecentFileCollection.GetRecommendations"),
        // As Teams asks (verbose OData). Its prefetch's "prefer: useSmartCache"
        // answers from a cache that lacks the Loop and Whiteboard cards.
        &[("accept", "application/json;odata=verbose")],
    )
    .await
    .context("For you")?;
    Ok(cards(
        &reply,
        &client.user_principal_name().unwrap_or_default(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn result(title: &str, ext: &str, vis: &str, badge: Value, extra: Value) -> Value {
        let mut src = json!({ "Title": title, "FileName": format!("{title}.{ext}"), "FileExtension": ext,
            "VisualizationType": vis, "Url": format!("https://x-my.sharepoint.com/personal/a/Documents/{title}.{ext}"),
            "OneDriveItemId": "01ID", "OneDriveDriveId": "b!d", "SitePath": "https://x-my.sharepoint.com/personal/a",
            "ListId": "l", "UniqueId": "u",
            "ContainerUrl": "https://x-my.sharepoint.com/personal/a/Documents" });
        for (k, v) in extra.as_object().unwrap() {
            src[k] = v.clone();
        }
        json!({ "Source": src, "SubstrateSearchExtendedProperties": { "ReasonMarker": json!({ "Badge": badge }).to_string() } })
    }

    /// ost-test1's first cards (winpc, 2026-11-26).
    #[test]
    fn cards_read_as_teams_shows_them() {
        let reply = json!({ "d": { "GetRecommendations": json!({ "EntitySets": [{ "ResultSets": [{ "Results": [
            result("Release tasks", "loop", "Fluid",
                json!({ "MessageFormat": "You frequently open", "Type": 1, "Timestamp": "2026-11-26T12:34:44Z", "Users": [] }),
                json!({ "WebUrl": "https://loop.cloud.microsoft/p/x" })),
            result("0.2.0 release checklist", "loop", "Fluid",
                json!({ "MessageFormat": "{0} shared this in a Teams chat", "Type": 9, "Timestamp": "2026-11-23T15:11:17Z",
                        "Users": [{ "DisplayName": "OST Test 3", "Upn": "ost-test3@x.com" }] }),
                json!({ "WebUrl": "https://loop.cloud.microsoft/p/y", "LastShared": { "SharedBy": { "EmailAddresses": [{ "Address": "ost-test3@x.com" }] } } })),
            result("Weekly team sync", "whiteboard", "Whiteboard",
                json!({ "MessageFormat": "You edited", "Type": 4, "Timestamp": "2026-11-25T16:59:44Z" }), json!({})),
            result("Workspace page", "loop", "Fluid", json!({ "Type": 4 }),
                json!({ "ContainerUrl": "https://x.sharepoint.com/contentstorage/CSP_1" })),
            result("Release-notes-0.3", "pdf", "Pdf",
                json!({ "MessageFormat": "{0} shared this in a Teams chat", "Type": 9, "Users": [{ "DisplayName": "OST Test 3", "Upn": "ost-test3@x.com" }] }),
                json!({ "LastShared": { "SharedBy": { "EmailAddresses": [{ "Address": "me@x.com" }] } } })),
        ] }] }] }).to_string() } });
        let c = cards(&reply, "me@x.com");
        assert_eq!(c.len(), 4, "the workspace page is left out");
        assert_eq!(
            (
                c[0].reason.as_str(),
                c[0].icon.as_str(),
                c[0].button.as_str(),
                c[0].summarize
            ),
            ("You frequently open", "OfficeCatchUp", "open", false)
        );
        assert_eq!(c[0].url, "https://loop.cloud.microsoft/p/x");
        assert!(!c[0].thumbnail);
        assert_eq!(
            (
                c[1].actor.as_str(),
                c[1].rest.as_str(),
                c[1].actor_upn.as_str()
            ),
            (
                "OST Test 3",
                "shared this in a Teams chat",
                "ost-test3@x.com"
            )
        );
        assert_eq!((c[1].icon.as_str(), c[1].summarize), ("share", true));
        assert_eq!(
            (c[2].reason.as_str(), c[2].icon.as_str()),
            ("You edited", "edit")
        );
        // Shared by you: no Summarize.
        assert!(!c[3].summarize);
        assert!(c[3].thumbnail);
        assert_eq!(
            c[3].url,
            "https://x-my.sharepoint.com/personal/a/Documents/Release-notes-0.3.pdf"
        );
        // The same reply as plain JSON.
        let plain = json!({ "value": reply["d"]["GetRecommendations"].clone() });
        assert_eq!(cards(&plain, "me@x.com").len(), 4);
    }

    #[test]
    fn strip_fits_onedrives_tiles() {
        assert_eq!(tiles(932.0), 3);
        assert_eq!(tiles(1400.0), 4);
        assert_eq!(tiles(1600.0), 4);
        assert_eq!(tiles(5000.0), 8);
    }
}
