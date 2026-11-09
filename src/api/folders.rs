//! The chat list's sections, as Teams keeps them on the server
//! (conversation folders): which sections there are, their order, whether
//! each is expanded, and the chats in your own sections and Favorites.
//!
//! `{csa}/api/v1/teams/users/me/conversationFolders` with an AAD token for
//! chatsvcagg. Every change carries the last `folderHierarchyVersion`.
//! Spec: docs/spec/chat-list-and-header.md §3.

use anyhow::{Context, Result};
use serde::Serialize;

use super::client::TeamsClient;

const CSA_SCOPE: &str = "https://chatsvcagg.teams.microsoft.com/.default";
const QUERY: &str = "supportsAdditionalSystemGeneratedFolders=true&supportsSliceItems=true";

/// A section of the chat list.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Folder {
    pub id: String,
    /// Teams' folder type: QuickViews, Favorites, RecentChats,
    /// TeamsAndChannels, EngageCommunities, MeetingChats, MutedChats,
    /// HiddenChannels, or UserCreated for your own sections.
    pub kind: String,
    /// The section's title as Teams shows it.
    pub title: String,
    /// MostRecent, UserDefinedCustomOrder or NameAlphabetical.
    pub sort: String,
    pub expanded: bool,
    /// Conversations (or Quick views' slices) in the section, in order.
    pub items: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Folders {
    /// The hierarchy version changes must carry.
    pub version: i64,
    /// The sections Teams shows, in the server's order.
    pub folders: Vec<Folder>,
}

fn title_of(kind: &str, name: &str) -> String {
    match kind {
        "QuickViews" => "Quick views".into(),
        "Favorites" => "Favorites".into(),
        "RecentChats" => "Chats".into(),
        "TeamsAndChannels" => "Teams and channels".into(),
        "EngageCommunities" => "Communities".into(),
        "MeetingChats" => "Meeting chats".into(),
        "MutedChats" => "Muted chats".into(),
        "HiddenChannels" => "Hidden channels".into(),
        _ => name.into(),
    }
}

/// Whether Teams lists a folder as a section. Meeting chats and Muted
/// chats need their settings (off by default: enableMeetingChatsFolder and
/// enableMutedChatsFolder are false in production); hidden channels live
/// under their team; deleted folders go.
fn shown(kind: &str, deleted: bool) -> bool {
    !deleted
        && !matches!(
            kind,
            "MeetingChats" | "MutedChats" | "HiddenChannels" | "Unknown"
        )
}

/// Read the folders reply.
pub fn folders_from(v: &serde_json::Value) -> Folders {
    let s = |f: &serde_json::Value, k: &str| {
        f.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let all: Vec<&serde_json::Value> = v
        .get("conversationFolders")
        .and_then(|f| f.as_array())
        .into_iter()
        .flatten()
        .collect();
    let order: Vec<String> = v
        .get("conversationFolderOrder")
        .and_then(|o| o.as_array())
        .into_iter()
        .flatten()
        .filter_map(|i| i.as_str().map(str::to_string))
        .collect();
    let mut folders: Vec<Folder> = all
        .iter()
        .filter(|f| {
            shown(
                &s(f, "folderType"),
                f.get("isDeleted")
                    .and_then(|d| d.as_bool())
                    .unwrap_or(false),
            )
        })
        .map(|f| {
            let kind = s(f, "folderType");
            Folder {
                id: s(f, "id"),
                title: title_of(&kind, &s(f, "name")),
                sort: s(f, "sortType"),
                expanded: f
                    .get("isExpanded")
                    .and_then(|e| e.as_bool())
                    .unwrap_or(true),
                items: f
                    .get("conversationFolderItems")
                    .and_then(|i| i.as_array())
                    .into_iter()
                    .flatten()
                    .filter_map(|i| {
                        i.get("conversationId")
                            .and_then(|c| c.as_str())
                            .map(str::to_string)
                    })
                    .collect(),
                kind,
            }
        })
        .collect();
    // Sections not in the order (new on the server) go last, as Teams adds them.
    folders.sort_by_key(|f| order.iter().position(|o| *o == f.id).unwrap_or(usize::MAX));
    Folders {
        version: v
            .get("folderHierarchyVersion")
            .and_then(|x| x.as_i64())
            .unwrap_or(0),
        folders,
    }
}

fn base(client: &TeamsClient) -> String {
    // Teams' CSA through the AFD front door, by region.
    let region = client
        .chat_service_url()
        .split("//")
        .nth(1)
        .and_then(|h| h.split('.').next())
        .unwrap_or("amer")
        .to_string();
    format!(
        "https://teams.microsoft.com/api/csa/{region}/api/v1/teams/users/me/conversationFolders"
    )
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for(CSA_SCOPE).await
}

/// Your sections.
pub async fn folders(client: &TeamsClient) -> Result<Folders> {
    let v: serde_json::Value = client
        .http()
        .get(format!("{}?{QUERY}", base(client)))
        .bearer_auth(token().await?)
        .send()
        .await?
        .error_for_status()
        .context("Conversation folders")?
        .json()
        .await?;
    Ok(folders_from(&v))
}

async fn send(
    client: &TeamsClient,
    method: reqwest::Method,
    path: &str,
    body: serde_json::Value,
) -> Result<()> {
    let url = format!("{}{path}?{QUERY}", base(client));
    client
        .http()
        .request(method, url)
        .bearer_auth(token().await?)
        .json(&body)
        .send()
        .await?
        .error_for_status()
        .context("Conversation folders")?;
    Ok(())
}

fn encode(id: &str) -> String {
    url::form_urlencoded::byte_serialize(id.as_bytes())
        .collect::<String>()
        .replace('+', "%20")
}

/// Expand or collapse one section (Teams' updateConversationFolder).
pub async fn set_expanded(
    client: &TeamsClient,
    version: i64,
    folder: &Folder,
    expanded: bool,
) -> Result<()> {
    send(
        client,
        reqwest::Method::PUT,
        &format!("/{}", encode(&folder.id)),
        serde_json::json!({"folderHierarchyVersion": version, "folderName": folder.title_for_server(), "isExpanded": expanded, "sortType": folder.sort}),
    )
    .await
}

/// Expand or collapse several sections at once (Collapse all sections).
pub async fn set_all_expanded(
    client: &TeamsClient,
    version: i64,
    ids: &[String],
    expanded: bool,
) -> Result<()> {
    send(
        client,
        reqwest::Method::PATCH,
        "/batchUpdateExpandedState",
        serde_json::json!({"folderHierarchyVersion": version, "folderIds": ids, "isExpanded": expanded}),
    )
    .await
}

/// Rename one of your sections.
pub async fn rename(client: &TeamsClient, version: i64, folder: &Folder, name: &str) -> Result<()> {
    send(
        client,
        reqwest::Method::PUT,
        &format!("/{}", encode(&folder.id)),
        serde_json::json!({"folderHierarchyVersion": version, "folderName": name, "isExpanded": folder.expanded, "sortType": folder.sort}),
    )
    .await
}

/// Create a section, optionally moving a conversation into it (Move to
/// section ▸ New section), out of the section it was in.
pub async fn create(
    client: &TeamsClient,
    version: i64,
    name: &str,
    item: Option<&str>,
    from: Option<&str>,
) -> Result<()> {
    let mut actions = vec![serde_json::json!({"action": "AddFolder", "itemId": item})];
    if let (Some(item), Some(from)) = (item, from) {
        actions.push(serde_json::json!({"action": "RemoveItem", "folderId": from, "itemId": item}));
    }
    send(
        client,
        reqwest::Method::POST,
        "",
        serde_json::json!({"folderHierarchyVersion": version, "folderName": name, "sortType": "UserDefinedCustomOrder", "isExpanded": true, "actions": actions}),
    )
    .await
}

/// Remove one of your sections (its chats stay in the list).
pub async fn delete(client: &TeamsClient, version: i64, folder_id: &str) -> Result<()> {
    send(
        client,
        reqwest::Method::DELETE,
        &format!("/{}", encode(folder_id)),
        serde_json::json!({"folderHierarchyVersion": version}),
    )
    .await
}

/// Put a conversation into a section (first), taking it out of `from`.
pub async fn move_item(
    client: &TeamsClient,
    version: i64,
    item: &str,
    to: &str,
    from: Option<&str>,
) -> Result<()> {
    let mut actions = vec![
        serde_json::json!({"action": "AddItem", "folderId": to, "itemId": item, "itemIndex": 0}),
    ];
    if let Some(from) = from {
        actions.push(serde_json::json!({"action": "RemoveItem", "folderId": from, "itemId": item}));
    }
    send(
        client,
        reqwest::Method::POST,
        "",
        serde_json::json!({"folderHierarchyVersion": version, "actions": actions}),
    )
    .await
}

/// Take a conversation out of a section.
pub async fn remove_item(client: &TeamsClient, version: i64, item: &str, from: &str) -> Result<()> {
    send(
        client,
        reqwest::Method::POST,
        "",
        serde_json::json!({"folderHierarchyVersion": version, "actions": [{"action": "RemoveItem", "folderId": from, "itemId": item}]}),
    )
    .await
}

impl Folder {
    /// One of your own sections (the server says UserCreated; older
    /// clients UserDefined).
    pub fn is_users(&self) -> bool {
        matches!(self.kind.as_str(), "UserCreated" | "UserDefined")
    }

    /// The name the server keeps (system sections keep their type name).
    fn title_for_server(&self) -> String {
        if self.is_users() {
            self.title.clone()
        } else {
            self.kind.clone()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folders_read_in_server_order_without_hidden_sections() {
        // ost-test1's folders (2026-11-09), trimmed.
        let v = serde_json::json!({
            "folderHierarchyVersion": 1793898075182i64,
            "conversationFolders": [
                {"id": "t~u~Favorites", "sortType": "UserDefinedCustomOrder", "name": "Favorites", "folderType": "Favorites", "isExpanded": true, "isDeleted": false,
                 "conversationFolderItems": [{"conversationId": "48:notes"}]},
                {"id": "t~u~RecentChats", "sortType": "MostRecent", "name": "RecentChats", "folderType": "RecentChats", "isExpanded": true, "isDeleted": false},
                {"id": "t~u~TeamsAndChannels", "sortType": "NameAlphabetical", "name": "TeamsAndChannels", "folderType": "TeamsAndChannels", "isExpanded": false, "isDeleted": false},
                {"id": "t~u~MeetingChats", "sortType": "MostRecent", "name": "MeetingChats", "folderType": "MeetingChats", "isExpanded": true, "isDeleted": false},
                {"id": "t~u~QuickViews", "sortType": "UserDefinedCustomOrder", "name": "QuickViews", "folderType": "QuickViews", "isExpanded": true, "isDeleted": false,
                 "conversationFolderItems": [{"conversationId": "slice-activities-mentions", "itemType": "Slice"}]},
                {"id": "t~u~abc", "sortType": "UserDefinedCustomOrder", "name": "Projects", "folderType": "UserCreated", "isExpanded": true, "isDeleted": false,
                 "conversationFolderItems": [{"conversationId": "19:x@thread.v2"}]},
                {"id": "t~u~gone", "name": "Old", "folderType": "UserDefined", "isDeleted": true},
            ],
            "conversationFolderOrder": ["t~u~QuickViews", "t~u~Favorites", "t~u~abc", "t~u~RecentChats", "t~u~MeetingChats", "t~u~TeamsAndChannels"],
        });
        let f = folders_from(&v);
        assert_eq!(f.version, 1793898075182);
        let titles: Vec<&str> = f.folders.iter().map(|x| x.title.as_str()).collect();
        assert_eq!(
            titles,
            vec![
                "Quick views",
                "Favorites",
                "Projects",
                "Chats",
                "Teams and channels"
            ]
        );
        assert_eq!(f.folders[1].items, vec!["48:notes"]);
        assert!(!f.folders[4].expanded);
        assert_eq!(f.folders[2].title_for_server(), "Projects");
        assert_eq!(f.folders[3].title_for_server(), "RecentChats");
    }
}
