//! Quick views ▸ Discover, as Teams fills it (read from Teams 26304's
//! worker, `discoverSurfaceServiceV2`, and checked on Teams web as OST
//! Test 2, 2026-11-27): CSA's suggested channel posts, your feedback on
//! them and what you've asked not to see.
//!
//! - `GET {csa}/api/v1/teams/users/me/discover?pageSize=…&continuationToken=…`
//!   answers `feedResults` (each a channel post: its channel and team,
//!   author, post id and why it's there) and the next page's token.
//! - `POST …/discover/feedback` takes "Is this useful?" (USEFUL /
//!   NOT_USEFUL) for one post.
//! - `GET / POST / DELETE …/discover/preferences`: the authors, channels
//!   and posts left out ("Don't show …"; Settings lists and removes them).
//!
//! The posts themselves come from the chat service, as any channel post's.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;

const CSA_SCOPE: &str = "https://chatsvcagg.teams.microsoft.com/.default";

/// Teams' page size for the feed (its first page and each scroll).
pub const PAGE_SIZE: u32 = 10;

/// A suggested post.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct DiscoverItem {
    /// Feedback and preferences name the post by these.
    pub feedback_id: String,
    pub feed_id: String,
    pub feed_type: String,
    /// The post's Teams link.
    pub uri: String,
    /// Why it's suggested (Teams' detailedInclusionReason, upper case:
    /// CHANNEL_YOU_ENGAGE_WITH, POST_POPULARITY, …; "UNKNOWN" otherwise).
    pub reason: String,
    /// The reason as CSA sent it (feedback hands it back).
    pub reason_code: String,
    /// The channel (19:…@thread.tacv2) and its team.
    pub channel_id: String,
    pub channel_name: String,
    pub team_name: String,
    /// The team's group id and thread id.
    pub team_group_id: String,
    pub team_thread: String,
    /// The post (its message id).
    pub post_id: String,
    pub author_id: String,
    pub author_name: String,
    pub author_email: String,
    pub created: String,
}

/// One page of the feed.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct DiscoverPage {
    pub items: Vec<DiscoverItem>,
    /// The next page's token ("" when there is none).
    pub continuation: String,
    /// What feedback carries back (instrumentationDetails).
    pub trace_id: String,
    pub logical_id: String,
}

/// Teams' reasons, upper case as its client keys them.
fn reason_of(code: &str) -> String {
    let known = [
        "POST_POPULARITY",
        "AUTHOR_YOU_COLLABORATE_WITH",
        "AUTHOR_POPULARITY",
        "CHANNEL_YOU_ENGAGE_WITH",
        "CHANNEL_POPULARITY",
        "CHANNEL_YOU_VISIT",
        "AUTHOR_YOU_INTERACT_WITH",
        "ACTIVE_AUTHOR",
    ];
    // (CSA answers "Unknown" for most; any spelling of a known one counts.)
    let up: String = code
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_uppercase();
    known
        .iter()
        .find(|k| k.replace('_', "") == up)
        .map_or_else(|| "UNKNOWN".to_string(), |k| (*k).to_string())
}

/// Read a feed page.
pub fn page_from(v: &serde_json::Value) -> DiscoverPage {
    let s = |v: &serde_json::Value, p: &str| {
        v.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let items = v["feedResults"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|r| r["feedType"].as_str() == Some("TeamsChannelMessage"))
        .filter_map(|r| {
            let info = &r["channelMessageInfo"];
            let item = DiscoverItem {
                feedback_id: s(r, "/feedbackId"),
                feed_id: s(r, "/feedId"),
                feed_type: s(r, "/feedType"),
                uri: s(r, "/uri"),
                reason: reason_of(&s(r, "/inclusionReasons/0/reasonCode")),
                reason_code: s(r, "/inclusionReasons/0/reasonCode"),
                channel_id: s(info, "/channel/channelId"),
                channel_name: s(info, "/channel/displayName"),
                team_name: s(info, "/channel/team/displayName"),
                team_group_id: s(info, "/channel/team/groupId"),
                team_thread: s(info, "/channel/team/teamId"),
                post_id: s(info, "/post/postId"),
                author_id: s(info, "/author/id"),
                author_name: s(info, "/author/displayName"),
                author_email: s(info, "/author/email"),
                created: s(info, "/createdDateTime"),
            };
            (!item.channel_id.is_empty() && !item.post_id.is_empty()).then_some(item)
        })
        .collect();
    let token = s(v, "/continuationToken");
    DiscoverPage {
        items,
        continuation: if token == "null" {
            String::new()
        } else {
            token
        },
        trace_id: s(v, "/instrumentationDetails/traceId"),
        logical_id: s(v, "/instrumentationDetails/logicalId"),
    }
}

fn base(client: &TeamsClient) -> String {
    // CSA through the AFD front door, by region (as conversationFolders).
    let region = client
        .chat_service_url()
        .split("//")
        .nth(1)
        .and_then(|h| h.split('.').next())
        .unwrap_or("amer")
        .to_string();
    format!("https://teams.microsoft.com/api/csa/{region}/api/v1/teams/users/me/discover")
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for(CSA_SCOPE).await
}

fn encode(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// The headers Teams' discover calls carry besides the token.
fn headers(rb: reqwest::RequestBuilder, scenario: &str) -> reqwest::RequestBuilder {
    rb.header("Accept", "application/json")
        .header("x-ms-client-type", "Web")
        .header("x-ms-application", "TeamsActivity_Web")
        .header("x-ms-application-feed-source", "unknown")
        .header("x-ms-client-scenario", scenario)
        .header("x-ms-request-id", uuid::Uuid::new_v4().to_string())
}

/// A page of suggested posts: the first (`continuation` empty) or the next.
pub async fn feed(client: &TeamsClient, continuation: &str) -> Result<DiscoverPage> {
    let url = format!(
        "{}?pageSize={PAGE_SIZE}&continuationToken={}",
        base(client),
        encode(continuation)
    );
    let scenario = if continuation.is_empty() {
        "TeamsFeed_Switch"
    } else {
        "TeamsFeed_Scroll"
    };
    let v: serde_json::Value = headers(client.http().get(url), scenario)
        .bearer_auth(token().await?)
        .send()
        .await?
        .error_for_status()
        .context("Discover feed")?
        .json()
        .await?;
    Ok(page_from(&v))
}

/// "Is this useful?" Yes (USEFUL) or No (NOT_USEFUL) for a post at
/// `position` (from the top of the feed, as Teams counts it).
pub fn feedback_body(
    item: &DiscoverItem,
    page: &DiscoverPage,
    useful: bool,
    position: u32,
    now: &str,
) -> serde_json::Value {
    serde_json::json!({
        "feedbackType": if useful { "USEFUL" } else { "NOT_USEFUL" },
        "currentClientTimeStamp": now,
        "instrumentationDetails": [{"traceId": page.trace_id, "logicalId": page.logical_id}],
        "feed": {
            "feedbackId": item.feedback_id,
            "feedId": item.feed_id,
            "feedType": item.feed_type,
            "inclusionReasons": [{"reasonCode": item.reason_code}],
            "createdDateTime": now,
            "feedLocationFromTop": position,
        },
    })
}

pub async fn feedback(client: &TeamsClient, body: &serde_json::Value) -> Result<()> {
    headers(
        client.http().post(format!("{}/feedback", base(client))),
        "TeamsFeed_Background",
    )
    .bearer_auth(token().await?)
    .json(body)
    .send()
    .await?
    .error_for_status()
    .context("Discover feedback")?;
    Ok(())
}

/// Something left out of Discover.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Excluded {
    /// "AUTHOR", "CHANNEL" or "POST".
    pub kind: String,
    /// An author's MRI (8:orgid:…), a channel's uri://channel/{group}/{channel}
    /// or a post's id.
    pub id: String,
    /// An author's name.
    pub name: String,
}

/// What `POST` / `DELETE …/preferences` take for an author, a channel or a post.
pub fn preference_body(kind: &str, id: &str, name: &str, feedback_id: &str) -> serde_json::Value {
    match kind {
        "AUTHOR" => {
            serde_json::json!({"entityKind": "AUTHOR", "id": id, "author": {"id": id, "displayName": name}})
        }
        "POST" => serde_json::json!({"entityKind": "POST", "id": id, "feedbackId": feedback_id}),
        _ => serde_json::json!({"entityKind": "CHANNEL", "id": id}),
    }
}

/// A channel's id as preferences name it.
pub fn channel_uri(team_group_id: &str, channel_id: &str) -> String {
    format!("uri://channel/{team_group_id}/{channel_id}")
}

pub fn excluded_from(v: &serde_json::Value) -> Vec<Excluded> {
    v["userPreferences"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|p| Excluded {
            kind: p["entityKind"]
                .as_str()
                .unwrap_or_default()
                .to_ascii_uppercase(),
            id: p["id"].as_str().unwrap_or_default().to_string(),
            name: p["author"]["displayName"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
        })
        .filter(|e| !e.id.is_empty())
        .collect()
}

/// The authors and channels you've left out.
pub async fn excluded(client: &TeamsClient) -> Result<Vec<Excluded>> {
    let v: serde_json::Value = headers(
        client.http().get(format!("{}/preferences", base(client))),
        "TeamsFeed_Background",
    )
    .bearer_auth(token().await?)
    .send()
    .await?
    .error_for_status()
    .context("Discover preferences")?
    .json()
    .await?;
    Ok(excluded_from(&v))
}

/// Leave something out (`exclude`) or show it again.
pub async fn set_excluded(
    client: &TeamsClient,
    body: &serde_json::Value,
    exclude: bool,
) -> Result<()> {
    let method = if exclude {
        reqwest::Method::POST
    } else {
        reqwest::Method::DELETE
    };
    headers(
        client
            .http()
            .request(method, format!("{}/preferences", base(client))),
        "TeamsFeed_Background",
    )
    .bearer_auth(token().await?)
    .json(body)
    .send()
    .await?
    .error_for_status()
    .context("Discover preferences")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_page_as_csa_answers_it() {
        // Trimmed from OST Test 2's feed (Teams web, 2026-11-27).
        let v = serde_json::json!({
            "continuationToken": "eyJQ",
            "previousContinuationToken": null,
            "instrumentationDetails": {"traceId": "8768aad6", "logicalId": null},
            "feedResults": [{
                "feedType": "TeamsChannelMessage",
                "feedId": "uri://message/1fac/19:327@thread.tacv2/1795757942761",
                "feedbackId": "eyJB",
                "uri": "https://teams.microsoft.com/l/message/19:327@thread.tacv2/1795757942761",
                "inclusionReasons": [{"reasonCode": "Unknown"}],
                "channelMessageInfo": {
                    "channel": {"channelId": "19:327@thread.tacv2", "displayName": "",
                                "team": {"teamId": "19:ekC@thread.tacv2", "groupId": "1fac", "displayName": "OST Test Team"}},
                    "author": {"id": "01c4", "displayName": "OST Test 3", "email": "ost-test3@example.com"},
                    "post": {"postId": "1795757942761"},
                    "createdDateTime": "2026-11-27T05:39:02.761"
                }
            }, {"feedType": "Other", "channelMessageInfo": {}}]
        });
        let p = page_from(&v);
        assert_eq!(p.continuation, "eyJQ");
        assert_eq!(p.trace_id, "8768aad6");
        assert_eq!(p.items.len(), 1);
        let i = &p.items[0];
        assert_eq!(
            (
                i.channel_id.as_str(),
                i.post_id.as_str(),
                i.team_name.as_str(),
                i.team_group_id.as_str(),
                i.reason.as_str()
            ),
            (
                "19:327@thread.tacv2",
                "1795757942761",
                "OST Test Team",
                "1fac",
                "UNKNOWN"
            )
        );
    }

    #[test]
    fn reasons_keep_teams_names() {
        assert_eq!(
            reason_of("CHANNEL_YOU_ENGAGE_WITH"),
            "CHANNEL_YOU_ENGAGE_WITH"
        );
        assert_eq!(reason_of("ChannelYouEngageWith"), "CHANNEL_YOU_ENGAGE_WITH");
        assert_eq!(reason_of("Unknown"), "UNKNOWN");
        assert_eq!(reason_of(""), "UNKNOWN");
    }

    #[test]
    fn bodies_as_teams_sends_them() {
        assert_eq!(
            preference_body("AUTHOR", "8:orgid:01c4", "OST Test 3", ""),
            serde_json::json!({"entityKind": "AUTHOR", "id": "8:orgid:01c4", "author": {"id": "8:orgid:01c4", "displayName": "OST Test 3"}})
        );
        assert_eq!(
            preference_body(
                "CHANNEL",
                &channel_uri("1fac", "19:327@thread.tacv2"),
                "",
                ""
            ),
            serde_json::json!({"entityKind": "CHANNEL", "id": "uri://channel/1fac/19:327@thread.tacv2"})
        );
        assert_eq!(
            preference_body("POST", "1795757942761", "", "eyJB"),
            serde_json::json!({"entityKind": "POST", "id": "1795757942761", "feedbackId": "eyJB"})
        );
        let item = DiscoverItem {
            feedback_id: "f".into(),
            feed_id: "d".into(),
            feed_type: "TeamsChannelMessage".into(),
            reason_code: "Unknown".into(),
            ..Default::default()
        };
        let page = DiscoverPage {
            trace_id: "t".into(),
            ..Default::default()
        };
        let b = feedback_body(&item, &page, true, 2, "2026-11-27T10:00:00.000Z");
        assert_eq!(b["feedbackType"], "USEFUL");
        assert_eq!(b["feed"]["feedLocationFromTop"], 2);
        assert_eq!(b["feed"]["inclusionReasons"][0]["reasonCode"], "Unknown");
        assert_eq!(b["instrumentationDetails"][0]["traceId"], "t");
    }

    #[test]
    fn reads_preferences() {
        let v = serde_json::json!({"userPreferences": [
            {"entityKind": "author", "id": "8:orgid:01c4", "author": {"id": "8:orgid:01c4", "displayName": "OST Test 3"}},
            {"entityKind": "CHANNEL", "id": "uri://channel/1fac/19:327@thread.tacv2"}
        ]});
        let e = excluded_from(&v);
        assert_eq!(e.len(), 2);
        assert_eq!(
            (e[0].kind.as_str(), e[0].name.as_str()),
            ("AUTHOR", "OST Test 3")
        );
        assert_eq!(e[1].kind, "CHANNEL");
    }
}
