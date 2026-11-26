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
// Any field may be missing (a picked file can carry only its address).
#[serde(default)]
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
    /// That folder's id (Graph's parentReference), for a place line's link.
    #[serde(default)]
    pub parent_id: String,
    /// A shortcut (Add shortcut's): what it points to. The item's own
    /// `drive_id` / `id` are the shortcut's, so Delete or Rename act on the
    /// shortcut, never on the folder it opens.
    #[serde(default)]
    pub remote_drive_id: String,
    #[serde(default)]
    pub remote_id: String,
    /// OneDrive's special folder it is ("shortcuts" for Add shortcut's
    /// Shortcuts folder), else empty.
    #[serde(default)]
    pub special: String,
}

/// A document library (a SharePoint site's drive, or your OneDrive).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Library {
    pub drive_id: String,
    pub name: String,
    pub site: String,
    pub web_url: String,
}

pub(crate) const SELECT: &str = "$select=id,name,size,folder,file,lastModifiedDateTime,lastModifiedBy,shared,webUrl,parentReference,remoteItem,sharepointIds,specialFolder";

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

pub(crate) fn parse_item(v: &serde_json::Value) -> Option<DriveItem> {
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
        sp_site: [
            s(v, "/sharepointIds/siteUrl"),
            s(r, "/sharepointIds/siteUrl"),
        ]
        .into_iter()
        .find(|u| !u.is_empty())
        .unwrap_or_default(),
        sp_list: [s(v, "/sharepointIds/listId"), s(r, "/sharepointIds/listId")]
            .into_iter()
            .find(|u| !u.is_empty())
            .unwrap_or_default(),
        sp_item: [
            s(v, "/sharepointIds/listItemUniqueId"),
            s(r, "/sharepointIds/listItemUniqueId"),
        ]
        .into_iter()
        .find(|u| !u.is_empty())
        .unwrap_or_default(),
        parent_name: [s(v, "/parentReference/name"), s(r, "/parentReference/name")]
            .into_iter()
            .find(|n| !n.is_empty())
            .unwrap_or_default(),
        parent_id: [s(v, "/parentReference/id"), s(r, "/parentReference/id")]
            .into_iter()
            .find(|n| !n.is_empty())
            .unwrap_or_default(),
        special: s(v, "/specialFolder/name"),
        remote_drive_id: String::new(),
        remote_id: String::new(),
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

/// Files you opened lately (OneDrive Home), as Teams lists them: from
/// your OneDrive's recent files service (Graph's `/me/drive/recent` is
/// retired), with Graph's items for the rows' actions.
pub async fn recent(client: &TeamsClient) -> Result<Vec<(super::recent_files::Recent, DriveItem)>> {
    use super::recent_files;
    let files = recent_files::fetch(client).await?;
    let items = recent_files::graph_items(client, &files).await;
    Ok(files
        .into_iter()
        .zip(items)
        .map(|(r, g)| {
            let it = recent_files::drive_item(&r, g);
            (r, it)
        })
        .collect())
}

/// Files and folders others shared with you (Shared ▸ With you), as Teams
/// lists them: from your OneDrive's recent files service and shared
/// folders (Graph's `/me/drive/sharedWithMe` is retired), with Graph's
/// items for the rows' actions.
pub async fn shared_with_me(
    client: &TeamsClient,
) -> Result<Vec<(super::shared_files::SharedFile, DriveItem)>> {
    super::shared_files::with_you_rows(client).await
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

/// Where OneDrive keeps your favorites for a file on `site_url`: your
/// OneDrive's host ("{tenant}-my.sharepoint.com").
pub fn favorites_host(site_url: &str) -> Option<String> {
    let host = site_url.strip_prefix("https://")?.split('/').next()?;
    let (tenant, rest) = host.split_once('.')?;
    let tenant = tenant.strip_suffix("-my").unwrap_or(tenant);
    Some(format!("https://{tenant}-my.{rest}"))
}

/// Teams' Favorite / Unfavorite on a message's file card: OneDrive's
/// `favorites/followedListItems/oneDrive.add` (or `.remove`) with the
/// file's site and address.
pub async fn set_favorite_by_url(site_url: &str, url: &str, on: bool) -> Result<()> {
    let host = favorites_host(site_url)
        .ok_or_else(|| anyhow::anyhow!("Not a SharePoint address: {site_url}"))?;
    let action = if on { "add" } else { "remove" };
    let body = serde_json::json!({ "value": [{ "siteUrl": format!("{}/", site_url.trim_end_matches('/')), "url": url }] });
    let json = [
        ("accept", "application/json"),
        ("content-type", "application/json"),
    ];
    super::sharing::post_with(
        &format!("{host}/_api/v2.1/favorites/followedListItems/oneDrive.{action}"),
        &body,
        &json,
    )
    .await?;
    Ok(())
}

/// The Graph sharing id of a file's address (`u!` + its unpadded
/// base64url), for `/shares/{id}`.
pub fn share_id(url: &str) -> String {
    use base64::Engine;
    format!(
        "u!{}",
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(url)
    )
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

/// The cloud file picker's Media (OneDrive Photos' AllPhotosView, as
/// Teams' picker asks, measured 2026-11-20): your OneDrive's pictures and
/// videos newest first by when they were taken (`{my site}/_api/v2.1/
/// drives/me/items/root/items?$filter=photo ne null and
/// photo/takenDateTime ge 1900-01-01…&orderby=photo/takenDateTime desc`,
/// 100), each with its size in pixels, when it was taken and a video's
/// length: (item, raw extras {w, h, taken, duration}).
pub async fn photos(client: &TeamsClient) -> Result<Vec<(DriveItem, serde_json::Value)>> {
    let drive: serde_json::Value = client
        .graph_get("/me/drive?$select=webUrl")
        .await?
        .json()
        .await?;
    let web = drive["webUrl"].as_str().unwrap_or_default();
    let site = web
        .rsplit_once('/')
        .map(|(s, _)| s)
        .unwrap_or(web)
        .to_string();
    let host = url::Url::parse(&site)
        .ok()
        .and_then(|u| u.host_str().map(str::to_string))
        .context("Your OneDrive")?;
    anyhow::ensure!(host.ends_with(".sharepoint.com"), "Your OneDrive");
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let url = format!(
        "{site}/_api/v2.1/drives/me/items/root/items?%24filter=photo+ne+null+and+photo%2FtakenDateTime+ge+1900-01-01T00%3A00%3A00.000Z&orderby=photo%2FtakenDateTime+desc&select=createdBy%2CcreatedDateTime%2CcTag%2Cdescription%2CdriveId%2Cfile%2CfileSystemInfo%2Cid%2Cimage%2ClastModifiedDateTime%2Clocation%2Cname%2CparentReference%2Cphoto%2Cshared%2CsharepointIds%2Csize%2Cvideo%2CwebUrl&top=100"
    );
    let v: serde_json::Value = reqwest::Client::new()
        .get(url)
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(photos_from(&v))
}

pub fn photos_from(v: &serde_json::Value) -> Vec<(DriveItem, serde_json::Value)> {
    v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(|raw| {
            let mut item = parse_item(raw)?;
            if item.drive_id.is_empty() {
                item.drive_id = raw["driveId"].as_str().unwrap_or_default().to_string();
            }
            let dims = raw.get("image").or_else(|| raw.get("video")).cloned().unwrap_or_default();
            let extras = serde_json::json!({
                "w": dims["width"].as_f64().unwrap_or(0.0), "h": dims["height"].as_f64().unwrap_or(0.0),
                "taken": raw["photo"]["takenDateTime"].as_str().unwrap_or_default(),
                "duration": raw["video"]["duration"].as_f64().unwrap_or(0.0),
                "video": raw.get("video").is_some(),
            });
            Some((item, extras))
        })
        .collect()
}

/// Browse files by People: who shared files with you, in Teams' order,
/// each with their People row's files and their page, as rows (Date
/// shared, Shared by, Activity) carrying Graph's ids for their actions.
pub async fn by_people(client: &TeamsClient) -> Result<Vec<PersonRows>> {
    let now = crate::clock::local_now();
    let rows = |v: Vec<(super::shared_files::SharedFile, DriveItem)>| {
        v.iter()
            .map(|(f, it)| super::shared_files::row(f, it, &now))
            .collect::<Vec<_>>()
    };
    Ok(super::shared_files::people_rows(client)
        .await?
        .into_iter()
        .map(|(p, files, items)| PersonRows {
            name: p.name,
            id: p.id,
            files: rows(files),
            items: rows(items),
        })
        .collect())
}

/// A person in Browse files by People.
#[derive(Debug, Clone, Serialize)]
pub struct PersonRows {
    pub name: String,
    pub id: String,
    /// Their People row's files.
    pub files: Vec<serde_json::Value>,
    /// Their page's files.
    pub items: Vec<serde_json::Value>,
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
        && let Ok(r) = client
            .graph_get(&format!(
                "/drives/{}/items/{}?$select=sharepointIds",
                folder.drive_id, folder.id
            ))
            .await
    {
        let ids: serde_json::Value = r.json().await.unwrap_or_default();
        let g = |k: &str| {
            ids["sharepointIds"][k]
                .as_str()
                .unwrap_or_default()
                .to_string()
        };
        folder.sp_site = g("siteUrl");
        folder.sp_list = g("listId");
        folder.sp_item = g("listItemUniqueId");
    }
    Ok(folder)
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
        .graph_patch(
            &item_path(drive_id, item_id)?,
            &serde_json::json!({ "name": name.trim() }),
        )
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
    let v: serde_json::Value = client
        .graph_get(&format!("{path}?{SELECT}"))
        .await?
        .json()
        .await?;
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
pub async fn thumbnail_sized(
    client: &TeamsClient,
    item: &DriveItem,
    size: &str,
) -> Result<Option<PathBuf>> {
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
        .graph_get_opt(&format!(
            "{}/thumbnails/0/{size}/content",
            item_path(&item.drive_id, &item.id)?
        ))
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

const TEXT_KINDS: &[&str] = &[
    "txt", "md", "json", "xml", "log", "csv", "css", "js", "ts", "html", "htm", "yaml", "yml",
    "ini", "cfg", "py", "rs", "sh", "c", "h", "cpp", "java", "cs", "sql", "toml",
];
const IMAGE_KINDS: &[&str] = &["png", "jpg", "jpeg", "gif", "bmp", "webp"];
const OFFICE_KINDS: &[&str] = &[
    "doc", "docx", "docm", "dot", "dotx", "rtf", "odt", "ppt", "pptx", "pptm", "pps", "ppsx",
    "odp", "xls", "xlsx", "xlsm", "xlsb", "ods",
];
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
        return Ok(Preview {
            kind: "none".into(),
            text: String::new(),
            path: String::new(),
        });
    }
    let convert = kind == "pdf" && !item.kind.eq_ignore_ascii_case("pdf");
    let url = format!(
        "{}/content{}",
        item_path(&item.drive_id, &item.id)?,
        if convert { "?format=pdf" } else { "" }
    );
    let bytes = client
        .graph_get(&url)
        .await?
        .bytes()
        .await
        .context("Preview")?;
    if kind == "text" {
        let cut = &bytes[..bytes.len().min(TEXT_LIMIT)];
        return Ok(Preview {
            kind: "text".into(),
            text: String::from_utf8_lossy(cut).into_owned(),
            path: String::new(),
        });
    }
    let dir = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .context("No cache folder")?
        .join("ost/preview");
    std::fs::create_dir_all(&dir)?;
    let ext = if kind == "pdf" {
        "pdf".to_string()
    } else {
        item.kind.to_ascii_lowercase()
    };
    let path = dir.join(format!("{}.{ext}", check_id(&item.id)?));
    std::fs::write(&path, &bytes)?;
    Ok(Preview {
        kind: kind.into(),
        text: String::new(),
        path: format!("file://{}", path.display()),
    })
}

/// A folder the Move / Copy picker's search found, as Teams lists it.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct FolderHit {
    #[serde(flatten)]
    pub item: DriveItem,
    /// "Created by: {name}" under the name.
    pub created_by: String,
    /// Modified as OneDrive's search words it ("Sun at 3:41 PM").
    pub modified_text: String,
    /// Location's parts: "My files", "{name}'s OneDrive" or the site, then
    /// the folders under the library (the item itself left out).
    pub location: Vec<String>,
    /// In your own OneDrive (Location then has no site picture).
    pub same_site: bool,
    /// The folder it is in, which its Location opens.
    pub parent_id: String,
    /// Location's picture: the site ("site": its logo) or the person
    /// whose OneDrive it is ("person"); none in your own OneDrive.
    pub location_web: String,
    pub location_kind: String,
    /// For a person's OneDrive, whose picture Location shows: the hit's
    /// author account (OneDrive reads `AuthorOWSUSER`, "account|name|…").
    pub location_author: String,
}

/// The picker's date filter: All dates, Today, Last 7 days, Last 30 days,
/// Last 3 months, In the last year (OneDrive counts 0, 7, 30, 90 and 365
/// days back).
pub fn date_filter_days(key: &str) -> Option<i64> {
    match key {
        "today" => Some(0),
        "last7Days" => Some(7),
        "last30Days" => Some(30),
        "last3Months" => Some(90),
        "lastYear" => Some(365),
        _ => None,
    }
}

/// The picker's search as Teams' file picker asks SharePoint search:
/// folders only (no OneNote notebooks or Site Assets), My files limited to
/// your OneDrive's library (`docs`), and the date filter as " AND
/// (LastModifiedTime>=…)" from midnight UTC that many days back.
fn folder_query(
    q: &str,
    docs: Option<&str>,
    people: &[String],
    since_ms: Option<i64>,
) -> (String, String) {
    let mut query = q.to_string();
    if let Some(d) = docs {
        query += &format!(" (path:\"{d}\" OR ParentLink:\"{d}*\" OR DocumentLink:\"{d}*\")");
    }
    // The Person filter (OneDrive's): each name as editor or author.
    if !people.is_empty() {
        let names: Vec<String> = people
            .iter()
            .map(|n| format!("ModifiedBy:\"{n}\" OR author:\"{n}\""))
            .collect();
        query += &format!(" AND ({})", names.join(" OR "));
    }
    if let Some(ms) = since_ms {
        let day = ms - ms.rem_euclid(86_400_000);
        if let Some(t) = crate::clock::from_ms(day) {
            query += &format!(" AND (LastModifiedTime>={} )", crate::clock::iso_ms(t));
        }
    }
    let template = "({searchterms}) ContentTypeId:0x0120* NOT HtmlFileType:\"OneNote.Notebook\" NOT ParentLink:SiteAssets".to_string();
    (query, template)
}

/// Location as OneDrive's search draws it: the item's path under its web
/// (`web`), first "My files" for your own OneDrive (`personal`), "{site}'s
/// OneDrive" for someone else's ("Shared" when unnamed), else the site's
/// title (else the web address's last two parts); then its folders, with
/// the library itself left out when it is Documents or Shared Documents.
fn location(
    item_url: &str,
    web: &str,
    site_title: &str,
    template: i64,
    personal: &str,
) -> (Vec<String>, bool) {
    let (item, web) = (
        super::copy_jobs::folder_url(item_url),
        super::copy_jobs::folder_url(web),
    );
    if web.is_empty() {
        return (Vec::new(), false);
    }
    // Under its web, else (a Loop workspace's items) just the site.
    let rel = item
        .get(web.len() + 1..)
        .filter(|_| item.to_lowercase().starts_with(&(web.to_lowercase() + "/")))
        .unwrap_or_default();
    let parts: Vec<&str> = rel.split('/').filter(|p| !p.is_empty()).collect();
    let same = !personal.is_empty()
        && web
            .trim_end_matches('/')
            .eq_ignore_ascii_case(personal.trim_end_matches('/'));
    let first = if same {
        "My files".to_string()
    } else if template == 21 {
        if site_title.is_empty() {
            "Shared".to_string()
        } else {
            format!("{site_title}'s OneDrive")
        }
    } else if !site_title.is_empty() {
        site_title.to_string()
    } else {
        let w: Vec<&str> = web.split('/').collect();
        if w.len() >= 2 {
            format!("{}-{}", w[w.len() - 2], w[w.len() - 1])
        } else {
            String::new()
        }
    };
    let mut out = vec![first];
    let folders = &parts[..parts.len().saturating_sub(1)];
    let lib = |p: &str| p == "Documents" || p == "Shared Documents";
    if !(folders.is_empty() || folders.len() == 1 && lib(folders[0])) {
        let from = usize::from(lib(folders[0]));
        out.extend(folders[from..].iter().map(|p| p.to_string()));
    }
    (out, same)
}

fn hit(h: &serde_json::Value, personal: &str, now: &jiff::ZonedDateTime) -> Option<FolderHit> {
    let r = &h["resource"];
    let f = &r["listItem"]["fields"];
    let mut item = parse_item(r)?;
    item.is_folder = true;
    item.kind.clear();
    if item.drive_id.is_empty() {
        item.drive_id = r["parentReference"]["driveId"]
            .as_str()
            .unwrap_or_default()
            .to_string();
    }
    let st = |k: &str| f[k].as_str().unwrap_or_default().to_string();
    let web = [st("spWebUrl"), st("spSiteURL")]
        .into_iter()
        .find(|w| !w.is_empty())
        .unwrap_or_default();
    let template = f["siteTemplateId"]
        .as_i64()
        .or_else(|| f["siteTemplateId"].as_str().and_then(|t| t.parse().ok()))
        .unwrap_or(0);
    let (location, same_site) = location(&item.web_url, &web, &st("siteTitle"), template, personal);
    let modified_text = crate::clock::parse_instant(&item.modified)
        .map(|t| super::list_rows::activity_time(&crate::clock::local(t), now))
        .unwrap_or_default();
    Some(FolderHit {
        created_by: r["createdBy"]["user"]["displayName"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        modified_text,
        location,
        same_site,
        parent_id: r["parentReference"]["id"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        location_kind: if same_site || web.is_empty() {
            String::new()
        } else if template == 21 {
            "person".into()
        } else {
            "site".into()
        },
        location_web: web,
        location_author: st("authorOWSUSER")
            .split('|')
            .next()
            .unwrap_or_default()
            .trim()
            .to_string(),
        item,
    })
}

/// Search for the Move/Copy picker, as Teams': folders only, in your
/// OneDrive ("My files") or everything you can reach ("All files"), 25 by
/// relevance; `days` is the date filter (see `date_filter_days`).
pub async fn search_folders(
    client: &TeamsClient,
    query: &str,
    all: bool,
    days: Option<i64>,
    people: &[String],
) -> Result<Vec<FolderHit>> {
    let q = query.trim();
    if q.is_empty() {
        return Ok(Vec::new());
    }
    let personal = super::quick_access::personal_site(client)
        .await
        .unwrap_or_default();
    if !all && personal.is_empty() {
        bail!("Your OneDrive's address is unknown");
    }
    let docs = format!("{personal}/Documents");
    let now = crate::clock::local_now();
    let since = days.map(|d| crate::clock::millis(now.timestamp()) - 86_400_000 * d);
    let (query_string, template) = folder_query(q, (!all).then_some(docs.as_str()), people, since);
    let body = serde_json::json!({ "requests": [{
        "entityTypes": ["driveItem"],
        "query": { "queryString": query_string, "queryTemplate": template },
        "from": 0, "size": 25,
        "fields": ["id", "name", "size", "webUrl", "parentReference", "lastModifiedDateTime", "lastModifiedBy", "createdBy", "folder", "file", "sharepointIds",
            "IsContainer", "SiteTitle", "SPWebUrl", "SPSiteURL", "SiteTemplateId", "ParentLink", "AuthorOWSUSER"]
    }] });
    let v: serde_json::Value = client
        .graph_post("/search/query", &body)
        .await?
        .json()
        .await
        .context("Search reply")?;
    Ok(v["value"][0]["hitsContainers"][0]["hits"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|h| hit(h, &personal, &now))
        .collect())
}

/// People for the picker search's Person filter: your organization's people
/// (and guests) matching what you type, or your most relevant ones before
/// you type (OneDrive asks its people picker for 30 at most).
pub async fn people_search(client: &TeamsClient, query: &str) -> Result<Vec<serde_json::Value>> {
    let q = query.trim().replace('"', "");
    let path = if q.is_empty() {
        "/me/people?$top=10&$select=id,displayName,scoredEmailAddresses,userPrincipalName,personType".to_string()
    } else {
        format!(
            "/me/people?$search=%22{}%22&$top=30&$select=id,displayName,scoredEmailAddresses,userPrincipalName,personType",
            url::form_urlencoded::byte_serialize(q.as_bytes()).collect::<String>()
        )
    };
    let v: serde_json::Value = client
        .graph_get(&path)
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|p| p["personType"]["class"] == "Person" && matches!(p["personType"]["subclass"].as_str(), Some("OrganizationUser") | Some("Guest")))
        .map(|p| {
            serde_json::json!({ "name": p["displayName"], "id": p["id"],
                "email": p["scoredEmailAddresses"][0]["address"].as_str().or_else(|| p["userPrincipalName"].as_str()).unwrap_or_default() })
        })
        .collect())
}

/// Location's picture for a search hit (OneDrive's): a site's logo from
/// your OneDrive's `siteiconmanager/getsitelogo` (saved in OST's cache), or
/// the directory id of the person whose OneDrive it is (their drive's owner).
pub async fn location_picture(
    client: &TeamsClient,
    web: &str,
    person: bool,
    author: &str,
) -> Result<serde_json::Value> {
    let web = web.trim_end_matches('/');
    let host = web.split('/').take(3).collect::<Vec<_>>().join("/");
    // OneDrive's picker shows the hit's author (AuthorOWSUSER's account) for
    // a person's OneDrive; the drive's owner when that's missing (a drive
    // you can't open whole has no owner to read).
    if person && !author.is_empty() && !author.contains('/') {
        let v: serde_json::Value = client
            .graph_get(&format!(
                "/users/{}?$select=id,displayName",
                url::form_urlencoded::byte_serialize(author.as_bytes()).collect::<String>()
            ))
            .await?
            .error_for_status()?
            .json()
            .await?;
        return Ok(serde_json::json!({ "oid": v["id"], "name": v["displayName"] }));
    }
    if person {
        let hostname = host.trim_start_matches("https://");
        let path = web.strip_prefix(&host).unwrap_or_default();
        let v: serde_json::Value = client
            .graph_get(&format!("/sites/{hostname}:{path}:/drive?$select=owner"))
            .await?
            .error_for_status()?
            .json()
            .await?;
        return Ok(
            serde_json::json!({ "oid": v["owner"]["user"]["id"], "name": v["owner"]["user"]["displayName"] }),
        );
    }
    let personal = super::quick_access::personal_site(client).await?;
    let q: String = url::form_urlencoded::byte_serialize(format!("'{web}'").as_bytes()).collect();
    let url = format!(
        "{}/_api/siteiconmanager/getsitelogo?siteUrl={q}",
        personal.trim_end_matches('/')
    );
    let phost = url.split('/').take(3).collect::<Vec<_>>().join("/");
    let token = crate::auth::oauth::access_token_for(&format!("{phost}/.default")).await?;
    let resp = reqwest::Client::new()
        .get(&url)
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?;
    let bytes = resp.bytes().await?;
    if bytes.is_empty() {
        bail!("No logo");
    }
    let dir = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .context("No cache folder")?
        .join("ost/sitelogos");
    std::fs::create_dir_all(&dir)?;
    let name: String = web
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect();
    let path = dir.join(format!("{name}.img"));
    std::fs::write(&path, &bytes)?;
    Ok(serde_json::json!({ "path": format!("file://{}", path.display()) }))
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
    let name = Path::new(&item.name)
        .file_name()
        .and_then(|n| n.to_str())
        .context("Bad file name")?;
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
    fn favorites_go_to_your_onedrive() {
        assert_eq!(
            favorites_host("https://x-my.sharepoint.com/personal/a_x_com").as_deref(),
            Some("https://x-my.sharepoint.com")
        );
        assert_eq!(
            favorites_host("https://x.sharepoint.com/sites/OSTTestTeam").as_deref(),
            Some("https://x-my.sharepoint.com")
        );
        assert_eq!(favorites_host("not a url"), None);
    }

    #[test]
    fn picker_search_asks_for_folders_as_teams_does() {
        let (q, t) = folder_query(
            "Recordings",
            Some("https://x-my.sharepoint.com/personal/a_b_com/Documents"),
            &[],
            None,
        );
        assert_eq!(
            q,
            "Recordings (path:\"https://x-my.sharepoint.com/personal/a_b_com/Documents\" OR ParentLink:\"https://x-my.sharepoint.com/personal/a_b_com/Documents*\" OR DocumentLink:\"https://x-my.sharepoint.com/personal/a_b_com/Documents*\")"
        );
        assert_eq!(
            t,
            "({searchterms}) ContentTypeId:0x0120* NOT HtmlFileType:\"OneNote.Notebook\" NOT ParentLink:SiteAssets"
        );
        // Last 7 days from 2026-11-13 16:20 UTC: from midnight on the 6th.
        let now =
            crate::clock::millis(crate::clock::parse_instant("2026-11-13T16:20:00Z").unwrap());
        let (q, _) = folder_query("ost", None, &[], Some(now - 7 * 86_400_000));
        assert_eq!(q, "ost AND (LastModifiedTime>=2026-11-06T00:00:00.000Z )");
        // The Person filter, as OneDrive's search builds it.
        let (q, _) = folder_query("ost", None, &["OST Test 2".to_string()], None);
        assert_eq!(
            q,
            "ost AND (ModifiedBy:\"OST Test 2\" OR author:\"OST Test 2\")"
        );
        assert_eq!(date_filter_days("last3Months"), Some(90));
        assert_eq!(date_filter_days("all"), None);
    }

    #[test]
    fn search_locations_read_as_onedrive_draws_them() {
        let me = "https://x-my.sharepoint.com/personal/a_b_com";
        let l = |u: &str, w: &str, t: &str, tpl: i64| location(u, w, t, tpl, me);
        assert_eq!(
            l(&format!("{me}/Documents/Recordings"), me, "OST Test 1", 21),
            (vec!["My files".to_string()], true)
        );
        assert_eq!(
            l(
                &format!("{me}/Documents/Recordings/Old%20ones"),
                me,
                "OST Test 1",
                21
            ),
            (vec!["My files".to_string(), "Recordings".to_string()], true)
        );
        let team = "https://x.sharepoint.com/sites/OSTTestTeam";
        assert_eq!(
            l(
                &format!("{team}/Shared%20Documents/OST%20threads%20test"),
                team,
                "OST Test Team",
                64
            ),
            (vec!["OST Test Team".to_string()], false)
        );
        assert_eq!(
            l(
                &format!("{team}/Shared%20Documents/General/Notes"),
                team,
                "OST Test Team",
                64
            )
            .0,
            ["OST Test Team", "General"]
        );
        assert_eq!(
            l(
                &format!("{team}/SiteAssets/Notebook"),
                team,
                "OST Test Team",
                64
            )
            .0,
            ["OST Test Team", "SiteAssets"]
        );
        let other = "https://x-my.sharepoint.com/personal/c_b_com";
        assert_eq!(
            l(
                &format!("{other}/Documents/Plans"),
                other,
                "Randy Northrup",
                21
            )
            .0,
            ["Randy Northrup's OneDrive"]
        );
        assert_eq!(
            l(&format!("{other}/Documents/Plans"), other, "", 21).0,
            ["Shared"]
        );
        assert_eq!(
            l(&format!("{team}/Shared%20Documents/X"), team, "", 64).0,
            ["sites-OSTTestTeam"]
        );
        assert_eq!(
            l(
                "https://loop.cloud.microsoft/c/eyJz",
                "https://x.sharepoint.com/contentstorage/x8F",
                "My workspace",
                70
            )
            .0,
            ["My workspace"]
        );
        assert!(l(&format!("{team}/X"), "", "T", 64).0.is_empty());
    }

    #[test]
    fn search_hits_are_folders_with_their_location() {
        let me = "https://x-my.sharepoint.com/personal/a_b_com";
        let h = serde_json::json!({ "resource": {
            "id": "01ABC", "name": "Recordings", "size": 0, "file": { "mimeType": "application/octet-stream" },
            "lastModifiedDateTime": "2026-11-08T23:41:42Z", "lastModifiedBy": { "user": { "displayName": "SharePoint App" } },
            "createdBy": { "user": { "displayName": "SharePoint App" } },
            "webUrl": format!("{me}/Documents/Recordings"),
            "parentReference": { "driveId": "b!d", "id": "01ROOT" },
            "listItem": { "fields": { "isContainer": true, "siteTitle": "OST Test 1", "spWebUrl": me, "siteTemplateId": 21 } }
        }});
        let now = crate::clock::local(crate::clock::parse_instant("2026-11-13T16:20:00Z").unwrap());
        let f = hit(&h, me, &now).unwrap();
        assert!(f.item.is_folder);
        assert_eq!(f.item.kind, "");
        assert_eq!(
            (
                f.item.drive_id.as_str(),
                f.parent_id.as_str(),
                f.created_by.as_str()
            ),
            ("b!d", "01ROOT", "SharePoint App")
        );
        assert_eq!(f.location, ["My files"]);
        assert!(f.same_site);
        assert!(
            f.modified_text.ends_with("PM") || f.modified_text.ends_with("AM"),
            "{}",
            f.modified_text
        );
    }

    #[test]
    fn share_ids_are_graph_encoded() {
        assert_eq!(
            share_id(
                "https://onedrive.live.com/redir?resid=1231244193912!12&authKey=1201919!12921!1"
            ),
            "u!aHR0cHM6Ly9vbmVkcml2ZS5saXZlLmNvbS9yZWRpcj9yZXNpZD0xMjMxMjQ0MTkzOTEyITEyJmF1dGhLZXk9MTIwMTkxOSExMjkyMSEx"
        );
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
        // Teams lists OneDrive's Shortcuts folder too (its own icon).
        assert_eq!(items.len(), 3);
        assert_eq!(
            (items[2].name.as_str(), items[2].special.as_str()),
            ("Shortcuts", "shortcuts")
        );
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
