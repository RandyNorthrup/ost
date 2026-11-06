//! OneDrive and SharePoint document libraries through Microsoft Graph,
//! for the OneDrive app: recent files, folders, files shared with you,
//! the libraries of sites you follow, and upload, download, new folder
//! and delete. Ids that go into Graph paths are checked first.

use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;
use super::files::{save_unique, seg, upload_in_session, MAX_FILE_BYTES};

/// One file or folder.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct DriveItem {
    pub id: String,
    pub drive_id: String,
    pub name: String,
    pub is_folder: bool,
    /// Items in a folder.
    pub child_count: u64,
    pub size: u64,
    /// ISO time of the last change.
    pub modified: String,
    pub modified_by: String,
    /// "Private", "Shared" (as Teams labels its Sharing column).
    pub sharing: String,
    pub web_url: String,
    /// File extension, lowercase ("docx"); empty for folders.
    pub kind: String,
}

/// A document library (a SharePoint site's drive, or your OneDrive).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Library {
    pub drive_id: String,
    pub name: String,
    pub site: String,
    pub web_url: String,
}

const SELECT: &str = "$select=id,name,size,folder,file,lastModifiedDateTime,lastModifiedBy,shared,webUrl,parentReference,remoteItem";

/// Graph ids for drives and items: letters, digits and `!-_.` only.
fn check_id(id: &str) -> Result<&str> {
    if id.is_empty()
        || id.len() > 200
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"!-_.".contains(&b))
    {
        bail!("Not a drive id");
    }
    Ok(id)
}

fn item_path(drive_id: &str, item_id: &str) -> Result<String> {
    Ok(if drive_id.is_empty() {
        format!("/me/drive/items/{}", check_id(item_id)?)
    } else {
        format!(
            "/drives/{}/items/{}",
            check_id(drive_id)?,
            check_id(item_id)?
        )
    })
}

fn parse_item(v: &serde_json::Value) -> Option<DriveItem> {
    // Shared and recent lists point at the real item through remoteItem.
    let r = v.get("remoteItem").unwrap_or(v);
    let s = |x: &serde_json::Value, p: &str| {
        x.pointer(p)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let name = s(v, "/name");
    let id = s(r, "/id");
    if id.is_empty() || name.is_empty() {
        return None;
    }
    let folder = r.get("folder").or_else(|| v.get("folder"));
    let kind = if folder.is_some() {
        String::new()
    } else {
        Path::new(&name)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase()
    };
    let scope = s(r, "/shared/scope");
    Some(DriveItem {
        drive_id: [
            s(r, "/parentReference/driveId"),
            s(v, "/parentReference/driveId"),
        ]
        .into_iter()
        .find(|d| !d.is_empty())
        .unwrap_or_default(),
        id,
        is_folder: folder.is_some(),
        child_count: folder
            .and_then(|f| f.get("childCount"))
            .and_then(|c| c.as_u64())
            .unwrap_or(0),
        size: v
            .get("size")
            .or_else(|| r.get("size"))
            .and_then(|n| n.as_u64())
            .unwrap_or(0),
        modified: [s(v, "/lastModifiedDateTime"), s(r, "/lastModifiedDateTime")]
            .into_iter()
            .find(|d| !d.is_empty())
            .unwrap_or_default(),
        modified_by: [
            s(v, "/lastModifiedBy/user/displayName"),
            s(r, "/lastModifiedBy/user/displayName"),
        ]
        .into_iter()
        .find(|d| !d.is_empty())
        .unwrap_or_default(),
        sharing: if scope.is_empty() || scope == "users" && r.get("shared").is_none() {
            "Private".into()
        } else {
            "Shared".into()
        },
        web_url: [s(v, "/webUrl"), s(r, "/webUrl")]
            .into_iter()
            .find(|u| u.starts_with("https://"))
            .unwrap_or_default(),
        name,
        kind,
    })
}

fn parse_items(v: &serde_json::Value) -> Vec<DriveItem> {
    v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(parse_item)
        .collect()
}

async fn get_items(client: &TeamsClient, path: &str) -> Result<Vec<DriveItem>> {
    let v: serde_json::Value = client
        .graph_get(path)
        .await?
        .json()
        .await
        .context("Drive reply")?;
    Ok(parse_items(&v))
}

/// Files you opened or changed lately (OneDrive Home).
pub async fn recent(client: &TeamsClient) -> Result<Vec<DriveItem>> {
    get_items(client, "/me/drive/recent?$top=50").await
}

/// Files and folders others shared with you.
pub async fn shared_with_me(client: &TeamsClient) -> Result<Vec<DriveItem>> {
    get_items(client, "/me/drive/sharedWithMe?$top=100").await
}

/// A folder's contents: your OneDrive's root when `item_id` is empty,
/// else that folder (in `drive_id`, or your OneDrive when empty).
pub async fn children(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
) -> Result<Vec<DriveItem>> {
    let base = match (drive_id.is_empty(), item_id.is_empty()) {
        (true, true) => "/me/drive/root".to_string(),
        (false, true) => format!("/drives/{}/root", check_id(drive_id)?),
        _ => item_path(drive_id, item_id)?,
    };
    let mut items = get_items(client, &format!("{base}/children?$top=200&{SELECT}")).await?;
    // Folders first, then by name, as Teams lists them.
    items.sort_by(|a, b| {
        b.is_folder
            .cmp(&a.is_folder)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(items)
}

/// Document libraries: each of your teams' SharePoint library (its
/// group drive, which holds the channels' files).
pub async fn libraries(client: &TeamsClient) -> Result<Vec<Library>> {
    let mut out = Vec::new();
    for team in super::list_teams_data(client).await?.into_iter().take(50) {
        // Team (group) ids are GUIDs.
        if team.id.is_empty() || !team.id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
            continue;
        }
        let Ok(r) = client
            .graph_get(&format!("/groups/{}/drive?$select=id,name,webUrl", team.id))
            .await
        else {
            continue;
        };
        let d: serde_json::Value = r.json().await.unwrap_or_default();
        if let (Some(id), Some(name)) = (d["id"].as_str(), d["name"].as_str()) {
            out.push(Library {
                drive_id: id.to_string(),
                name: name.to_string(),
                site: team.name.clone(),
                web_url: d["webUrl"].as_str().unwrap_or_default().to_string(),
            });
        }
    }
    Ok(out)
}

/// Download a file into `dir` (a free name is chosen if it exists).
pub async fn download(client: &TeamsClient, item: &DriveItem, dir: &Path) -> Result<PathBuf> {
    if item.is_folder {
        bail!("{} is a folder", item.name);
    }
    let bytes = client
        .graph_get(&format!("{}/content", item_path(&item.drive_id, &item.id)?))
        .await?
        .bytes()
        .await
        .context("Download")?;
    save_unique(dir, &item.name, &bytes)
}

/// Upload a local file into a folder (`folder_id` empty: your OneDrive's
/// root). An existing name gets a numbered copy, as OneDrive does.
pub async fn upload(
    client: &TeamsClient,
    drive_id: &str,
    folder_id: &str,
    path: &Path,
) -> Result<DriveItem> {
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .context("File has no name")?
        .to_string();
    let meta =
        std::fs::metadata(path).with_context(|| format!("Cannot read {}", path.display()))?;
    if !meta.is_file() {
        bail!("Not a file: {}", path.display());
    }
    if meta.len() > MAX_FILE_BYTES {
        bail!("{name} is larger than {} MB", MAX_FILE_BYTES / 1024 / 1024);
    }
    let bytes = std::fs::read(path)?;
    let parent = if folder_id.is_empty() && drive_id.is_empty() {
        "/me/drive/root".to_string()
    } else if folder_id.is_empty() {
        format!("/drives/{}/root", check_id(drive_id)?)
    } else {
        item_path(drive_id, folder_id)?
    };
    let target = format!("{parent}:/{}:", seg(&name));
    let v: serde_json::Value = if bytes.len() <= 4 * 1024 * 1024 {
        client
            .graph_put_bytes(
                &format!("{target}/content?@microsoft.graph.conflictBehavior=rename"),
                bytes,
                "application/octet-stream",
            )
            .await?
            .json()
            .await
            .context("Upload reply")?
    } else {
        upload_in_session(client, &target, bytes).await?
    };
    parse_item(&v).context("Upload reply had no item")
}

/// Make a folder (a numbered name if it exists).
pub async fn new_folder(
    client: &TeamsClient,
    drive_id: &str,
    parent_id: &str,
    name: &str,
) -> Result<DriveItem> {
    let name = name.trim();
    if name.is_empty() || name.contains(['/', '\\', ':', '*', '?', '"', '<', '>', '|']) {
        bail!("That folder name isn't allowed");
    }
    let parent = if parent_id.is_empty() && drive_id.is_empty() {
        "/me/drive/root".to_string()
    } else if parent_id.is_empty() {
        format!("/drives/{}/root", check_id(drive_id)?)
    } else {
        item_path(drive_id, parent_id)?
    };
    let body = serde_json::json!({ "name": name, "folder": {}, "@microsoft.graph.conflictBehavior": "rename" });
    let v: serde_json::Value = client
        .graph_post(&format!("{parent}/children"), &body)
        .await?
        .json()
        .await?;
    parse_item(&v).context("New folder reply had no item")
}

/// Move an item to the recycle bin.
pub async fn delete(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<()> {
    client.graph_delete(&item_path(drive_id, item_id)?).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn items_parse_from_children_shared_and_recent_shapes() {
        let v = serde_json::json!({ "value": [
            { "id": "01F", "name": "Microsoft Teams Chat Files", "folder": { "childCount": 3 },
              "lastModifiedDateTime": "2026-11-05T17:00:00Z", "lastModifiedBy": { "user": { "displayName": "OST Test 1" } },
              "parentReference": { "driveId": "b!abc" }, "webUrl": "https://x/f" },
            { "id": "local", "name": "Plan.docx", "size": 10,
              "remoteItem": { "id": "01R", "parentReference": { "driveId": "b!other" }, "shared": { "scope": "users" },
                              "webUrl": "https://x/p" } },
            { "name": "no id" }
        ]});
        let items = parse_items(&v);
        assert_eq!(items.len(), 2);
        assert!(items[0].is_folder && items[0].child_count == 3 && items[0].sharing == "Private");
        assert_eq!(items[0].modified_by, "OST Test 1");
        assert_eq!(
            (
                items[1].id.as_str(),
                items[1].drive_id.as_str(),
                items[1].kind.as_str()
            ),
            ("01R", "b!other", "docx")
        );
        assert_eq!(items[1].sharing, "Shared");
    }

    #[test]
    fn ids_are_checked_before_going_into_paths() {
        assert!(item_path("b!a-b_c", "01ABC").is_ok());
        assert!(item_path("", "../../me").is_err());
        assert!(item_path("b!x/../y", "1").is_err());
    }
}
