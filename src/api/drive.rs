//! OneDrive and SharePoint document libraries through Microsoft Graph,
//! for the OneDrive app: recent files, folders, files shared with you,
//! the libraries of sites you follow, and upload, download, new folder
//! and delete. Ids that go into Graph paths are checked first.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;
use super::files::{MAX_FILE_BYTES, save_unique, seg, upload_in_session};

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
    /// SharePoint's address for it (site, list, item), for the share dialog.
    pub sp_site: String,
    pub sp_list: String,
    pub sp_item: String,
    /// The folder it is in (search results' Location).
    #[serde(default)]
    pub parent_name: String,
}

/// A document library (a SharePoint site's drive, or your OneDrive).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Library {
    pub drive_id: String,
    pub name: String,
    pub site: String,
    pub web_url: String,
}

const SELECT: &str = "$select=id,name,size,folder,file,lastModifiedDateTime,lastModifiedBy,shared,webUrl,parentReference,remoteItem,sharepointIds,specialFolder";

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
        sp_site: [s(v, "/sharepointIds/siteUrl"), s(r, "/sharepointIds/siteUrl")].into_iter().find(|u| !u.is_empty()).unwrap_or_default(),
        sp_list: [s(v, "/sharepointIds/listId"), s(r, "/sharepointIds/listId")].into_iter().find(|u| !u.is_empty()).unwrap_or_default(),
        sp_item: [s(v, "/sharepointIds/listItemUniqueId"), s(r, "/sharepointIds/listItemUniqueId")].into_iter().find(|u| !u.is_empty()).unwrap_or_default(),
        parent_name: [s(v, "/parentReference/name"), s(r, "/parentReference/name")].into_iter().find(|n| !n.is_empty()).unwrap_or_default(),
        name,
        kind,
    })
}

fn parse_items(v: &serde_json::Value) -> Vec<DriveItem> {
    v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        // OneDrive's Shortcuts folder (Add shortcut's) is hidden from the
        // list, as Teams' OneDrive app hides it.
        .filter(|x| x["specialFolder"]["name"].as_str() != Some("shortcuts"))
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

/// Favorites: the files and folders you follow.
pub async fn favorites(client: &TeamsClient) -> Result<Vec<DriveItem>> {
    get_items(client, &format!("/me/drive/following?{SELECT}")).await
}

/// Add an item to (or take it off) your favorites.
pub async fn set_favorite(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
    on: bool,
) -> Result<()> {
    let action = if on { "follow" } else { "unfollow" };
    client
        .graph_post(
            &format!("{}/{action}", item_path(drive_id, item_id)?),
            &serde_json::json!({}),
        )
        .await?;
    Ok(())
}

/// The Graph sharing id of a file's address (`u!` + its unpadded
/// base64url), for `/shares/{id}`.
pub fn share_id(url: &str) -> String {
    use base64::Engine;
    format!("u!{}", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(url))
}

/// The drive item at a SharePoint or OneDrive address (a search result's).
pub async fn item_by_url(client: &TeamsClient, url: &str) -> Result<DriveItem> {
    let v: serde_json::Value = client
        .graph_get(&format!("/shares/{}/driveItem?{SELECT}", share_id(url)))
        .await?
        .json()
        .await?;
    parse_item(&v).ok_or_else(|| anyhow::anyhow!("Not a file: {url}"))
}

/// Photos and videos in the files you can reach (Graph search).
pub async fn media(client: &TeamsClient) -> Result<Vec<DriveItem>> {
    let q = serde_json::json!({ "requests": [{
        "entityTypes": ["driveItem"],
        "query": { "queryString": "filetype:jpg OR filetype:jpeg OR filetype:png OR filetype:gif OR filetype:heic OR filetype:mp4 OR filetype:mov OR filetype:webm" },
        "size": 100
    }]});
    let v: serde_json::Value = client.graph_post("/search/query", &q).await?.json().await?;
    Ok(v.pointer("/value/0/hitsContainers/0/hits")
        .and_then(|h| h.as_array())
        .into_iter()
        .flatten()
        .filter_map(|h| h.get("resource"))
        .filter_map(parse_item)
        .collect())
}

/// Files shared with you, by who shared them: [(person, files)].
pub async fn by_people(client: &TeamsClient) -> Result<Vec<(String, Vec<DriveItem>)>> {
    let v: serde_json::Value = client
        .graph_get("/me/drive/sharedWithMe?$top=200")
        .await?
        .json()
        .await?;
    let mut out: Vec<(String, Vec<DriveItem>)> = Vec::new();
    for raw in v
        .get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
    {
        let Some(item) = parse_item(raw) else {
            continue;
        };
        let who = [
            "/remoteItem/shared/sharedBy/user/displayName",
            "/remoteItem/shared/owner/user/displayName",
            "/remoteItem/createdBy/user/displayName",
        ]
        .iter()
        .find_map(|p| {
            raw.pointer(p)
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
        })
        .unwrap_or("Someone")
        .to_string();
        match out.iter_mut().find(|(p, _)| *p == who) {
            Some((_, files)) => files.push(item),
            None => out.push((who, vec![item])),
        }
    }
    Ok(out)
}

/// Meeting files: the recordings Teams keeps in your OneDrive's
/// Recordings folder (empty when there are none).
pub async fn meetings(client: &TeamsClient) -> Result<Vec<DriveItem>> {
    match client
        .graph_get_opt(&format!(
            "/me/drive/root:/Recordings:/children?$top=200&{SELECT}"
        ))
        .await?
    {
        Some(r) => Ok(parse_items(&r.json().await?)),
        None => Ok(Vec::new()),
    }
}

/// A deleted item in your OneDrive's recycle bin.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Deleted {
    pub id: String,
    pub name: String,
    pub deleted: String,
    pub deleted_by: String,
    /// Where it was.
    pub from: String,
    pub size: u64,
}

async fn my_site(client: &TeamsClient) -> Result<String> {
    let d: serde_json::Value = client
        .graph_get("/me/drive?$select=sharePointIds")
        .await?
        .json()
        .await?;
    let site = d
        .pointer("/sharePointIds/siteId")
        .and_then(|s| s.as_str())
        .unwrap_or_default()
        .to_string();
    if site.is_empty() || !site.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Your OneDrive's site is unknown");
    }
    Ok(site)
}

/// Your OneDrive's recycle bin (Graph beta).
pub async fn recycle_bin(client: &TeamsClient) -> Result<Vec<Deleted>> {
    let site = my_site(client).await?;
    let v: serde_json::Value = client
        .graph_beta(&format!("/sites/{site}/recycleBin/items?$top=200"), None)
        .await?
        .json()
        .await?;
    let s = |x: &serde_json::Value, p: &str| {
        x.pointer(p)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    Ok(v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter(|i| !s(i, "/id").is_empty())
        .map(|i| Deleted {
            id: s(i, "/id"),
            name: s(i, "/name"),
            deleted: s(i, "/deletedDateTime"),
            deleted_by: s(i, "/deletedBy/user/displayName"),
            from: s(i, "/deletedFromLocation"),
            size: i.get("size").and_then(|n| n.as_u64()).unwrap_or(0),
        })
        .collect())
}

/// Restore recycle-bin items to where they were (Graph beta).
pub async fn restore(client: &TeamsClient, ids: &[String]) -> Result<()> {
    let site = my_site(client).await?;
    for id in ids {
        if !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
            bail!("Not a recycle bin item");
        }
    }
    client
        .graph_beta(
            &format!("/sites/{site}/recycleBin/items/restore"),
            Some(&serde_json::json!({ "ids": ids })),
        )
        .await?;
    Ok(())
}

/// Delete recycle-bin items for good (Graph beta).
pub async fn purge(client: &TeamsClient, ids: &[String]) -> Result<()> {
    let site = my_site(client).await?;
    for id in ids {
        if !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
            bail!("Not a recycle bin item");
        }
    }
    client
        .graph_beta(
            &format!("/sites/{site}/recycleBin/items/delete"),
            Some(&serde_json::json!({ "ids": ids })),
        )
        .await?;
    Ok(())
}

/// A channel's files folder (its folder in the team's SharePoint library),
/// as Teams' channel Shared tab shows it.
pub async fn channel_folder(
    client: &TeamsClient,
    team_id: &str,
    channel_id: &str,
) -> Result<DriveItem> {
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
    let path = format!("/teams/{team_id}/channels/{channel}/filesFolder");
    // The first look at a channel's folder can make SharePoint create it,
    // which may time out (504) once; it's there on the next try.
    let resp = match client.graph_get(&path).await {
        Ok(r) => r,
        Err(e) if format!("{e:#}").contains("HTTP 504") => {
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            client.graph_get(&path).await?
        }
        Err(e) => return Err(e),
    };
    let v: serde_json::Value = resp.json().await?;
    let mut folder = parse_item(&v).context("The channel has no files folder")?;
    // filesFolder takes no $select: its SharePoint address (for Share)
    // comes from the item itself.
    if folder.sp_item.is_empty()
        && !folder.drive_id.is_empty()
        && let Ok(r) = client.graph_get(&format!("/drives/{}/items/{}?$select=sharepointIds", folder.drive_id, folder.id)).await
    {
        let ids: serde_json::Value = r.json().await.unwrap_or_default();
        let g = |k: &str| ids["sharepointIds"][k].as_str().unwrap_or_default().to_string();
        folder.sp_site = g("siteUrl");
        folder.sp_list = g("listId");
        folder.sp_item = g("listItemUniqueId");
    }
    Ok(folder)
}

/// Add a shortcut to a shared folder in your OneDrive (Teams' "Add
/// shortcut to OneDrive").
pub async fn add_shortcut(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
    name: &str,
) -> Result<()> {
    item_path(drive_id, item_id)?;
    let body = serde_json::json!({
        "name": name,
        "remoteItem": { "id": item_id, "parentReference": { "driveId": drive_id } },
        "@microsoft.graph.conflictBehavior": "rename"
    });
    client.graph_post("/me/drive/root/children", &body).await?;
    Ok(())
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

/// Characters OneDrive refuses in a name.
pub fn bad_name(name: &str) -> bool {
    let n = name.trim();
    n.is_empty() || n.ends_with('.') || n.contains(['/', '\\', ':', '*', '?', '"', '<', '>', '|'])
}

/// Rename an item (Teams' Rename: the name with its extension).
pub async fn rename(client: &TeamsClient, drive_id: &str, item_id: &str, name: &str) -> Result<()> {
    if bad_name(name) {
        bail!("That name isn't allowed");
    }
    client
        .graph_patch(&item_path(drive_id, item_id)?, &serde_json::json!({ "name": name.trim() }))
        .await?;
    Ok(())
}

/// One item, by id.
pub async fn item(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<DriveItem> {
    let v: serde_json::Value = client
        .graph_get(&format!("{}?{SELECT}", item_path(drive_id, item_id)?))
        .await?
        .json()
        .await?;
    parse_item(&v).context("The item didn't come back")
}

/// A drive's top folder (your OneDrive's when `drive_id` is empty), for the
/// Move to / Copy to picker.
pub async fn root(client: &TeamsClient, drive_id: &str) -> Result<DriveItem> {
    let path = if drive_id.is_empty() {
        "/me/drive/root".to_string()
    } else {
        format!("/drives/{}/root", check_id(drive_id)?)
    };
    let v: serde_json::Value = client.graph_get(&format!("{path}?{SELECT}")).await?.json().await?;
    let mut item = parse_item(&v).context("The drive's folder didn't come back")?;
    // The root's own name is "root"; the picker shows the drive's.
    item.name = String::new();
    Ok(item)
}

/// The item's 320 x 180 picture (the Details pane's), saved in OST's cache;
/// None when it has none.
pub async fn thumbnail(client: &TeamsClient, item: &DriveItem) -> Result<Option<PathBuf>> {
    thumbnail_sized(client, item, "c320x180").await
}

/// The item's picture at one of Graph's sizes ("medium", "c320x180"),
/// cached; None when it has none.
pub async fn thumbnail_sized(client: &TeamsClient, item: &DriveItem, size: &str) -> Result<Option<PathBuf>> {
    if !size.bytes().all(|b| b.is_ascii_alphanumeric()) {
        bail!("Not a thumbnail size");
    }
    let dir = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .context("No cache folder")?
        .join("ost/thumbs");
    std::fs::create_dir_all(&dir)?;
    let Some(resp) = client
        .graph_get_opt(&format!("{}/thumbnails/0/{size}/content", item_path(&item.drive_id, &item.id)?))
        .await?
    else {
        return Ok(None);
    };
    let bytes = resp.bytes().await.context("Thumbnail")?;
    if bytes.is_empty() {
        return Ok(None);
    }
    let path = dir.join(format!("{}-{size}.jpg", check_id(&item.id)?));
    std::fs::write(&path, &bytes)?;
    Ok(Some(path))
}

/// What Preview shows for a file: its text, a picture, or PDF pages (Office
/// files converted by Graph, as OST can't embed Office for the web).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Preview {
    /// "text", "image", "pdf" or "none".
    pub kind: String,
    pub text: String,
    pub path: String,
}

const TEXT_KINDS: &[&str] = &["txt", "md", "json", "xml", "log", "csv", "css", "js", "ts", "html", "htm", "yaml", "yml", "ini", "cfg", "py", "rs", "sh", "c", "h", "cpp", "java", "cs", "sql", "toml"];
const IMAGE_KINDS: &[&str] = &["png", "jpg", "jpeg", "gif", "bmp", "webp"];
const OFFICE_KINDS: &[&str] = &["doc", "docx", "docm", "dot", "dotx", "rtf", "odt", "ppt", "pptx", "pptm", "pps", "ppsx", "odp", "xls", "xlsx", "xlsm", "xlsb", "ods"];
/// Text previews stop here.
const TEXT_LIMIT: usize = 1 << 20;

pub fn preview_kind(kind: &str) -> &'static str {
    let k = kind.to_ascii_lowercase();
    if TEXT_KINDS.contains(&k.as_str()) {
        "text"
    } else if IMAGE_KINDS.contains(&k.as_str()) {
        "image"
    } else if k == "pdf" || OFFICE_KINDS.contains(&k.as_str()) {
        "pdf"
    } else {
        "none"
    }
}

/// Fetch what Preview shows for `item`.
pub async fn preview(client: &TeamsClient, item: &DriveItem) -> Result<Preview> {
    let kind = preview_kind(&item.kind);
    if kind == "none" || item.is_folder {
        return Ok(Preview { kind: "none".into(), text: String::new(), path: String::new() });
    }
    let convert = kind == "pdf" && item.kind.to_ascii_lowercase() != "pdf";
    let url = format!("{}/content{}", item_path(&item.drive_id, &item.id)?, if convert { "?format=pdf" } else { "" });
    let bytes = client.graph_get(&url).await?.bytes().await.context("Preview")?;
    if kind == "text" {
        let cut = &bytes[..bytes.len().min(TEXT_LIMIT)];
        return Ok(Preview { kind: "text".into(), text: String::from_utf8_lossy(cut).into_owned(), path: String::new() });
    }
    let dir = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .context("No cache folder")?
        .join("ost/preview");
    std::fs::create_dir_all(&dir)?;
    let ext = if kind == "pdf" { "pdf".to_string() } else { item.kind.to_ascii_lowercase() };
    let path = dir.join(format!("{}.{ext}", check_id(&item.id)?));
    std::fs::write(&path, &bytes)?;
    Ok(Preview { kind: kind.into(), text: String::new(), path: format!("file://{}", path.display()) })
}

/// Search for the Move/Copy picker: your OneDrive ("My files") with
/// Graph's drive search, or everything you can reach ("All files") with
/// Graph's search query. Folders first.
pub async fn search_items(client: &TeamsClient, query: &str, all: bool) -> Result<Vec<DriveItem>> {
    let q = query.trim();
    if q.is_empty() {
        return Ok(Vec::new());
    }
    let mut items = if all {
        let body = serde_json::json!({ "requests": [{ "entityTypes": ["driveItem"], "query": { "queryString": q }, "from": 0, "size": 25 }] });
        let v: serde_json::Value = client.graph_post("/search/query", &body).await?.json().await.context("Search reply")?;
        v["value"][0]["hitsContainers"][0]["hits"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|h| {
                let r = &h["resource"];
                let mut it = parse_item(r)?;
                if it.drive_id.is_empty() {
                    it.drive_id = r["parentReference"]["driveId"].as_str().unwrap_or_default().to_string();
                }
                Some(it)
            })
            .collect::<Vec<_>>()
    } else {
        get_items(client, &format!("{}?$top=50&{SELECT}", search_path(q))).await?
    };
    items.sort_by(|a, b| b.is_folder.cmp(&a.is_folder));
    Ok(items)
}

/// My files' search address: the query quoted for OData ('' for ') and
/// percent-encoded for a path (a space is %20, not +).
fn search_path(q: &str) -> String {
    let enc: String = url::form_urlencoded::byte_serialize(q.replace('\'', "''").as_bytes()).collect();
    format!("/me/drive/root/search(q='{}')", enc.replace('+', "%20"))
}

/// Open in app: a copy of the file in OST's cache (replaced each time), for
/// the desktop's own app to open.
pub async fn local_copy(client: &TeamsClient, item: &DriveItem) -> Result<PathBuf> {
    if item.is_folder {
        bail!("{} is a folder", item.name);
    }
    let dir = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .context("No cache folder")?
        .join("ost/open")
        .join(check_id(&item.id)?);
    std::fs::create_dir_all(&dir)?;
    let name = Path::new(&item.name).file_name().and_then(|n| n.to_str()).context("Bad file name")?;
    let bytes = client
        .graph_get(&format!("{}/content", item_path(&item.drive_id, &item.id)?))
        .await?
        .bytes()
        .await
        .context("Download")?;
    let path = dir.join(name);
    std::fs::write(&path, &bytes)?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn my_files_search_quotes_and_encodes_the_query() {
        assert_eq!(search_path("ost picker"), "/me/drive/root/search(q='ost%20picker')");
        assert_eq!(search_path("Randy's & co"), "/me/drive/root/search(q='Randy%27%27s%20%26%20co')");
    }

    #[test]
    fn share_ids_are_graph_encoded() {
        assert_eq!(share_id("https://onedrive.live.com/redir?resid=1231244193912!12&authKey=1201919!12921!1"),
            "u!aHR0cHM6Ly9vbmVkcml2ZS5saXZlLmNvbS9yZWRpcj9yZXNpZD0xMjMxMjQ0MTkzOTEyITEyJmF1dGhLZXk9MTIwMTkxOSExMjkyMSEx");
    }

    #[test]
    fn items_parse_from_children_shared_and_recent_shapes() {
        let v = serde_json::json!({ "value": [
            { "id": "01F", "name": "Microsoft Teams Chat Files", "folder": { "childCount": 3 },
              "lastModifiedDateTime": "2026-11-05T17:00:00Z", "lastModifiedBy": { "user": { "displayName": "OST Test 1" } },
              "parentReference": { "driveId": "b!abc" }, "webUrl": "https://x/f" },
            { "id": "local", "name": "Plan.docx", "size": 10,
              "remoteItem": { "id": "01R", "parentReference": { "driveId": "b!other" }, "shared": { "scope": "users" },
                              "webUrl": "https://x/p" } },
            { "name": "no id" },
            { "id": "01S", "name": "Shortcuts", "folder": { "childCount": 0 }, "specialFolder": { "name": "shortcuts" } }
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
    fn previews_by_kind() {
        assert_eq!(preview_kind("TXT"), "text");
        assert_eq!(preview_kind("docx"), "pdf");
        assert_eq!(preview_kind("pdf"), "pdf");
        assert_eq!(preview_kind("png"), "image");
        assert_eq!(preview_kind("zip"), "none");
    }

    #[test]
    fn ids_are_checked_before_going_into_paths() {
        assert!(item_path("b!a-b_c", "01ABC").is_ok());
        assert!(item_path("", "../../me").is_err());
        assert!(item_path("b!x/../y", "1").is_err());
    }
}
