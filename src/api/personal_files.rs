//! Files and photos in a personal account's (Teams free) chats, as Teams
//! for personal use does them (captured on teams.live.com as OST Personal
//! 1 and 2, 2026-11-28; docs/research/personal-accounts-protocol.md §7.12):
//!
//! - Upload from this device: Graph `PUT /me/drive/root:/Microsoft Teams
//!   Chat Files/{name}:/content?@microsoft.graph.conflictBehavior=rename&
//!   select=*,sharepointIds`; the first time, the drive is read
//!   (`GET /me/drive`) and stored as the user property `personalFileSite`
//!   (`{"driveId":"…"}`).
//! - A picture (Upload from this device or Attach media) is also put in
//!   the media store (AMS `pish/image`, `sharingMode: Attached`, readable
//!   by the chat): the record's `filePreview` names its `imgo` view and
//!   size, and the message lists it in `amsreferences`.
//! - On send, `POST /drive/items/{id}/createLink {"type":"edit"}` (a
//!   personal OneDrive makes an "Anyone with the link can edit" link) and
//!   the record carries the link (`shareUrl`, `shareId`), the file's
//!   address on the personal site (`objectUrl`) and `state: active`.
//! - Attach cloud files: the same link on the picked item
//!   (`/drives/{drive}/items/{id}/createLink`), `state: reference`.
//! - Opening: the share link in the browser; Download redeems the link
//!   (`/shares/{shareId}/driveItem`, `prefer: redeemSharingLink`).
//! - The chat's Files and Photos tabs ask the message search service
//!   (`msgsearch.skype.com/v3/query`, Skype token) for the chat's
//!   messages with files, and with pictures.
//! - A full OneDrive (HTTP 507, `quotaLimitReached`) shows Teams' compose
//!   banner "Attachment storage is full".

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::Path;

use super::client::{HttpError, TeamsClient};
use super::files::seg;

/// Teams' folder for files shared in chats.
pub const CHAT_FILES_FOLDER: &str = "Microsoft Teams Chat Files";
/// What a personal OneDrive's chat link lets people do, as Teams words it
/// under the file in the compose box.
pub const LINK_DESCRIPTION: &str = "Anyone with the link can edit";
/// Teams free's message search (Files and Photos tabs).
pub const MESSAGE_SEARCH: &str = "https://msgsearch.skype.com/v3/query";
/// Where Teams' storage-full banner sends Manage and Get more storage.
pub const ONEDRIVE_LOGIN_URL: &str = "https://onedrive.live.com/?gologin=true";
pub const GET_MORE_STORAGE_URL: &str = "https://aka.ms/GetMoreStorage";

/// The upload failed because the sender's OneDrive is full (Teams'
/// SpQuotaReached: HTTP 507 or Graph's `quotaLimitReached`).
#[derive(Debug)]
pub struct StorageFull;

impl std::fmt::Display for StorageFull {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Attachment storage is full")
    }
}

impl std::error::Error for StorageFull {}

/// Whether an error is a full OneDrive (anywhere in its chain).
pub fn is_storage_full(e: &anyhow::Error) -> bool {
    e.chain().any(|c| {
        c.is::<StorageFull>()
            || c.downcast_ref::<HttpError>().is_some_and(|h| {
                h.status == 507
                    || h.body.contains("quotaLimitReached")
                    || h.body.contains("spQuotaReached")
            })
    })
}

/// The pictures Teams previews through the media store (the image types of
/// its Attach media list that a picture viewer can show).
pub fn is_preview_image(name: &str) -> bool {
    let ext = Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    matches!(
        ext.as_str(),
        "png" | "jpg" | "jpeg" | "jfif" | "gif" | "bmp" | "webp"
    )
}

/// A picture's size from its header (PNG, GIF, BMP, JPEG, WebP).
pub fn image_size(b: &[u8]) -> Option<(u32, u32)> {
    let be16 = |i: usize| {
        b.get(i..i + 2)
            .map(|s| u16::from_be_bytes([s[0], s[1]]) as u32)
    };
    let le16 = |i: usize| {
        b.get(i..i + 2)
            .map(|s| u16::from_le_bytes([s[0], s[1]]) as u32)
    };
    let be32 = |i: usize| {
        b.get(i..i + 4)
            .map(|s| u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
    };
    let le32 = |i: usize| {
        b.get(i..i + 4)
            .map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
    };
    let some = |w: u32, h: u32| (w > 0 && h > 0).then_some((w, h));
    if b.starts_with(b"\x89PNG\r\n\x1a\n") && b.get(12..16) == Some(b"IHDR") {
        return some(be32(16)?, be32(20)?);
    }
    if b.starts_with(b"GIF8") {
        return some(le16(6)?, le16(8)?);
    }
    if b.starts_with(b"BM") {
        let h = le32(22)? as i32;
        return some(le32(18)?, h.unsigned_abs());
    }
    if b.starts_with(b"RIFF") && b.get(8..12) == Some(b"WEBP") {
        return match b.get(12..16)? {
            b"VP8 " => some(le16(26)? & 0x3fff, le16(28)? & 0x3fff),
            b"VP8L" => {
                let v = le32(21)?;
                some((v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1)
            }
            b"VP8X" => {
                let w = le32(24)? & 0xff_ffff;
                let h = le32(27)? & 0xff_ffff;
                some(w + 1, h + 1)
            }
            _ => None,
        };
    }
    if b.starts_with(&[0xff, 0xd8]) {
        let mut i = 2;
        while i + 4 <= b.len() {
            if b[i] != 0xff {
                i += 1;
                continue;
            }
            let marker = b[i + 1];
            if marker == 0xd8 || marker == 0x01 || (0xd0..=0xd7).contains(&marker) {
                i += 2;
                continue;
            }
            let len = be16(i + 2)? as usize;
            // Start of frame (not DHT c4, JPG c8 or DAC cc).
            if (0xc0..=0xcf).contains(&marker) && ![0xc4, 0xc8, 0xcc].contains(&marker) {
                return some(be16(i + 7)?, be16(i + 5)?);
            }
            i += 2 + len;
        }
    }
    None
}

/// The media store object id in an AMS view address
/// (`…/v1/objects/{id}/views/imgo`).
pub fn ams_object_id(url: &str) -> Option<String> {
    let rest = url.split("/v1/objects/").nth(1)?;
    let id = rest.split('/').next()?;
    (!id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'))
        .then(|| id.to_string())
}

/// Whether the drive has been named in `personalFileSite` this session.
fn file_site_done() -> &'static std::sync::Mutex<Option<String>> {
    static DONE: std::sync::OnceLock<std::sync::Mutex<Option<String>>> = std::sync::OnceLock::new();
    DONE.get_or_init(Default::default)
}

/// Teams' `personalFileSite` user property: the drive the chat files live
/// in (`GET /me/drive`, once a session).
pub async fn ensure_file_site(client: &TeamsClient) -> Result<()> {
    let me = client.self_mri().unwrap_or_default();
    if file_site_done().lock().unwrap().as_deref() == Some(me.as_str()) {
        return Ok(());
    }
    let drive: Value = client
        .graph_get("/me/drive")
        .await?
        .json()
        .await
        .context("Drive reply")?;
    let id = drive["id"].as_str().context("Drive has no id")?;
    let url = format!(
        "{}/v1/users/ME/properties?name=personalFileSite",
        client.chat_service_url()
    );
    client
        .chat_request(
            reqwest::Method::PUT,
            &url,
            &json!({ "personalFileSite": json!({ "driveId": id }).to_string() }),
        )
        .await?;
    *file_site_done().lock().unwrap() = Some(me);
    Ok(())
}

/// Make the chat's link to a file: `createLink {"type":"edit"}` (a
/// personal OneDrive's default scope is anyone). `item_path` is Graph's
/// address of the item (`/drive/items/{id}` for your own upload,
/// `/drives/{drive}/items/{id}` for a picked one). Returns the link and
/// its share id.
pub async fn create_link(client: &TeamsClient, item_path: &str) -> Result<(String, String)> {
    let v: Value = client
        .graph_post(
            &format!("{item_path}/createLink"),
            &json!({ "type": "edit" }),
        )
        .await?
        .json()
        .await
        .context("Link reply")?;
    let url = v
        .pointer("/link/webUrl")
        .and_then(|u| u.as_str())
        .context("No link")?
        .to_string();
    Ok((url, v["shareId"].as_str().unwrap_or_default().to_string()))
}

/// A picture's preview in the media store: its `imgo` view and size.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Preview {
    pub id: String,
    pub url: String,
    pub width: u32,
    pub height: u32,
}

/// The file's address on its personal site as Teams records it
/// (`{site}/Documents/{folder path}/{name}`), from Graph's item: the site
/// from `sharepointIds` (the item's or its parent's), the path from
/// `parentReference.path`; `encode` percent-encodes each segment (Teams'
/// reference record does, its upload record doesn't).
pub fn object_url(item: &Value, encode: bool) -> String {
    let site = [
        item.pointer("/sharepointIds/siteUrl"),
        item.pointer("/parentReference/sharepointIds/siteUrl"),
    ]
    .into_iter()
    .flatten()
    .filter_map(|v| v.as_str())
    .find(|u| u.starts_with("https://"))
    .unwrap_or_default()
    .trim_end_matches('/')
    .to_string();
    if site.is_empty() {
        return item["webUrl"].as_str().unwrap_or_default().to_string();
    }
    let folder = item
        .pointer("/parentReference/path")
        .and_then(|p| p.as_str())
        .and_then(|p| p.split_once("root:").map(|(_, r)| r.to_string()))
        .unwrap_or_default();
    let name = item["name"].as_str().unwrap_or_default();
    let mut parts: Vec<String> = folder
        .split('/')
        .filter(|s| !s.is_empty())
        .map(|s| {
            let s = percent_decode(s);
            if encode { seg(&s) } else { s }
        })
        .collect();
    parts.push(if encode { seg(name) } else { name.to_string() });
    format!("{site}/Documents/{}", parts.join("/"))
}

fn percent_decode(s: &str) -> String {
    url::form_urlencoded::parse(format!("x={}", s.replace('+', "%2B")).as_bytes())
        .next()
        .map(|(_, v)| v.into_owned())
        .unwrap_or_else(|| s.to_string())
}

/// The `properties.files` entry Teams free posts for a file uploaded to
/// your chat files (captured: OST TASK-0300 file and photo from Personal 1).
pub fn upload_record(item: &Value, link: (&str, &str), preview: Option<&Preview>) -> Value {
    let name = item["name"].as_str().unwrap_or_default();
    let unique = item
        .pointer("/sharepointIds/listItemUniqueId")
        .and_then(|u| u.as_str())
        .map(|u| u.to_ascii_lowercase())
        .unwrap_or_default();
    let site = item
        .pointer("/sharepointIds/siteUrl")
        .and_then(|u| u.as_str())
        .unwrap_or_default()
        .trim_end_matches('/');
    let object = object_url(item, false);
    let file_type = ext_of(name);
    json!({
        "itemid": unique,
        "fileName": name,
        "fileType": file_type,
        "fileInfo": {
            "itemId": item["id"].as_str().unwrap_or_default(),
            "fileUrl": object,
            "siteUrl": site,
            "serverRelativeUrl": "",
            "shareUrl": link.0,
            "shareId": link.1
        },
        "fileChicletState": { "serviceName": "p2p", "state": "active" },
        "@type": "http://schema.skype.com/File",
        "version": 2,
        "id": unique,
        "baseUrl": site,
        "objectUrl": object,
        "openUrl": null,
        "type": file_type,
        "title": name,
        "state": "active",
        "altText": null,
        "chicletBreadcrumbs": null,
        "providerData": "",
        "botFileProperties": {},
        "isUploadError": null,
        "progressComplete": null,
        "permissionScope": null,
        "filePreview": match preview {
            Some(p) => json!({ "previewUrl": p.url, "previewHeight": p.height, "previewWidth": p.width }),
            None => json!({ "previewUrl": "", "previewHeight": 0, "previewWidth": 0 }),
        },
        "sharepointIds": null,
        "publication": null,
        "site": null
    })
}

/// The entry for a file picked from your OneDrive (Attach cloud files):
/// a reference, with the drive named in `sharepointIds` (captured: OST
/// TASK-0300 cloud file from Personal 1).
pub fn reference_record(item: &Value, link: (&str, &str)) -> Value {
    let name = item["name"].as_str().unwrap_or_default();
    let unique = item
        .pointer("/sharepointIds/listItemUniqueId")
        .and_then(|u| u.as_str())
        .map(|u| u.to_ascii_lowercase())
        .unwrap_or_default();
    let site = [
        item.pointer("/sharepointIds/siteUrl"),
        item.pointer("/parentReference/sharepointIds/siteUrl"),
    ]
    .into_iter()
    .flatten()
    .filter_map(|v| v.as_str())
    .next()
    .unwrap_or_default()
    .trim_end_matches('/');
    let drive = item
        .pointer("/parentReference/driveId")
        .and_then(|d| d.as_str())
        .unwrap_or_default();
    let object = object_url(item, true);
    let file_type = ext_of(name);
    json!({
        "itemid": unique,
        "fileName": name,
        "fileType": file_type,
        "fileInfo": {
            "itemId": item["id"].as_str().unwrap_or_default(),
            "fileUrl": object,
            "siteUrl": site,
            "serverRelativeUrl": "",
            "shareUrl": link.0,
            "shareId": link.1
        },
        "fileChicletState": { "serviceName": "p2p", "state": "reference" },
        "@type": "http://schema.skype.com/File",
        "version": 2,
        "id": unique,
        "baseUrl": site,
        "objectUrl": object,
        "openUrl": null,
        "type": file_type,
        "title": name,
        "state": "reference",
        "altText": null,
        "chicletBreadcrumbs": null,
        "providerData": "",
        "botFileProperties": {},
        "isUploadError": false,
        "progressComplete": null,
        "permissionScope": null,
        "filePreview": { "previewUrl": "", "previewHeight": null, "previewWidth": null },
        "sharepointIds": { "driveId": drive, "listId": null, "listItemUniqueId": null, "siteId": null, "siteUrl": null, "webId": null },
        "publication": null,
        "site": null
    })
}

fn ext_of(name: &str) -> String {
    Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
}

/// Upload a file to your Teams chat files and make the chat's record for
/// it, as Teams free does (a picture also goes to the media store for its
/// preview).
pub async fn upload(client: &TeamsClient, chat_id: &str, path: &Path) -> Result<Value> {
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
    if meta.len() > super::files::MAX_FILE_BYTES {
        bail!(
            "{name} is larger than {} MB",
            super::files::MAX_FILE_BYTES / 1024 / 1024
        );
    }
    let bytes = std::fs::read(path).with_context(|| format!("Cannot read {}", path.display()))?;
    if let Err(e) = ensure_file_site(client).await {
        tracing::warn!("personalFileSite: {e:#}");
    }
    let item_path = format!("/me/drive/root:/{}/{}:", seg(CHAT_FILES_FOLDER), seg(&name));
    let preview_bytes = is_preview_image(&name).then(|| bytes.clone());
    let uploaded: Result<Value> = async {
        if bytes.len() <= 4 * 1024 * 1024 {
            client
                .graph_put_bytes(
                    &format!(
                        "{item_path}/content?@microsoft.graph.conflictBehavior=rename&select=*,sharepointIds"
                    ),
                    bytes,
                    "application/octet-stream",
                )
                .await?
                .json()
                .await
                .context("Upload reply")
        } else {
            let item = super::files::upload_in_session(client, &item_path, bytes).await?;
            // The session's reply has no SharePoint ids: read them.
            let id = item["id"].as_str().context("Upload reply has no id")?;
            client
                .graph_get(&format!("/me/drive/items/{id}?select=*,sharepointIds"))
                .await?
                .json()
                .await
                .context("File details")
        }
    }
    .await;
    let item = match uploaded {
        Ok(i) => i,
        Err(e) if is_storage_full(&e) => return Err(e.context(StorageFull)),
        Err(e) => return Err(e),
    };
    let id = item["id"].as_str().context("Upload reply has no id")?;
    let preview = match preview_bytes {
        Some(b) => {
            let size = image_size(&b).unwrap_or((0, 0));
            match client.ams_upload_image_attached(chat_id, b, &name).await {
                Ok(obj) => client.ams_url().map(|base| Preview {
                    url: format!("{base}/v1/objects/{obj}/views/imgo"),
                    id: obj,
                    width: size.0,
                    height: size.1,
                }),
                Err(e) => {
                    tracing::warn!("picture preview: {e:#}");
                    None
                }
            }
        }
        None => None,
    };
    let (url, share_id) = create_link(client, &format!("/drive/items/{id}")).await?;
    Ok(upload_record(&item, (&url, &share_id), preview.as_ref()))
}

/// The record for a file picked from your OneDrive (Attach cloud files).
pub async fn cloud_record(client: &TeamsClient, drive_id: &str, item_id: &str) -> Result<Value> {
    let base = if drive_id.is_empty() {
        format!("/me/drive/items/{item_id}")
    } else {
        format!("/drives/{drive_id}/items/{item_id}")
    };
    let item: Value = client
        .graph_get(&format!("{base}?select=*,sharepointIds"))
        .await?
        .json()
        .await
        .context("File details")?;
    let (url, share_id) = create_link(client, &base).await?;
    Ok(reference_record(&item, (&url, &share_id)))
}

/// A file or picture in a chat, as Teams free's Files and Photos tabs list
/// them (from the message search's `files` metadata).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ChatFile {
    pub name: String,
    pub file_type: String,
    pub object_url: String,
    pub share_url: String,
    pub site_url: String,
    /// The picture's media store view (a picture's file, or an inline
    /// picture), else empty.
    pub preview_url: String,
    pub width: u32,
    pub height: u32,
    /// "Shared on": the message's time (ISO).
    pub time: String,
    /// "Sent by".
    pub sender: String,
    pub sender_mri: String,
    pub message_id: String,
}

/// The message search's question for a chat's files (Teams free's Files
/// tab: files and file/video URI objects, no tab links).
pub fn files_query(thread: &str, base: u32, count: u32) -> Value {
    json!({
        "OPTION": { "RESULTBASE": base, "RESULTCOUNT": count },
        "QUERYSTRING": { "and": [
            { "ThreadId": thread },
            { "or": [
                { "Annotation": { "TYPE": "files" } },
                { "Annotation": { "TYPE": "URIObject", "VALUE": { "type": "File.1" } } },
                { "Annotation": { "TYPE": "URIObject", "VALUE": { "type": "Video.1" } } }
            ] },
            { "not": { "Annotation": { "TYPE": "files", "VALUE": { "fileType": "deeplinkChiclet" } } } }
        ] }
    })
}

/// …and for its pictures (the Photos tab: inline pictures, picture files
/// and picture URI objects).
pub fn photos_query(thread: &str, base: u32, count: u32) -> Value {
    json!({
        "OPTION": { "RESULTBASE": base, "RESULTCOUNT": count },
        "QUERYSTRING": { "and": [
            { "ThreadId": thread },
            { "or": [
                { "Annotation": { "TYPE": "images" } },
                { "Annotation": { "TYPE": "files", "VALUE": { "fileType": "png" } } },
                { "Annotation": { "TYPE": "files", "VALUE": { "fileType": "jpg" } } },
                { "Annotation": { "TYPE": "files", "VALUE": { "fileType": "jpeg" } } },
                { "Annotation": { "TYPE": "URIObject", "VALUE": { "type": "Picture.1" } } }
            ] }
        ] }
    })
}

/// The search's answer as files: each message's `files` metadata (one per
/// file), newest first as the service answers.
pub fn parse_files(reply: &Value) -> Vec<ChatFile> {
    let mut out = Vec::new();
    for m in reply.as_array().into_iter().flatten() {
        let msg = |k: &str| m[k].as_str().unwrap_or_default().to_string();
        let lists = m["MetadataList"].as_array().cloned().unwrap_or_default();
        for meta in lists.iter().filter(|x| x["MetadataType"] == "files") {
            let props: std::collections::HashMap<String, String> = meta["MetadataPropertyList"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|p| {
                    Some((
                        p["Key"].as_str()?.to_string(),
                        p["Value"].as_str().unwrap_or_default().to_string(),
                    ))
                })
                .collect();
            let get = |k: &str| props.get(k).cloned().unwrap_or_default();
            let name = get("fileName");
            if name.is_empty() || get("fileType") == "deeplinkChiclet" {
                continue;
            }
            let preview = get("filePreviewpreviewUrl");
            out.push(ChatFile {
                file_type: Some(get("fileType"))
                    .filter(|t| !t.is_empty())
                    .unwrap_or_else(|| ext_of(&name)),
                name,
                object_url: get("fileInfofileUrl"),
                share_url: get("fileInfoshareUrl"),
                site_url: get("fileInfositeUrl"),
                preview_url: if super::messages::is_ams_url(&preview) {
                    preview
                } else {
                    String::new()
                },
                width: get("filePreviewpreviewWidth").parse().unwrap_or(0),
                height: get("filePreviewpreviewHeight").parse().unwrap_or(0),
                time: msg("CreationDate"),
                sender: msg("SenderDisplayName"),
                sender_mri: msg("From"),
                message_id: msg("MessageId"),
            });
        }
    }
    out
}

/// The search's answer as pictures: picture files with a media store
/// preview, and a message's inline pictures.
pub fn parse_photos(reply: &Value) -> Vec<ChatFile> {
    let mut out: Vec<ChatFile> = parse_files(reply)
        .into_iter()
        .filter(|f| !f.preview_url.is_empty())
        .collect();
    for m in reply.as_array().into_iter().flatten() {
        let content = m["Content"].as_str().unwrap_or_default();
        for img in super::messages::inline_images_of(content) {
            out.push(ChatFile {
                name: String::new(),
                file_type: "image".into(),
                preview_url: img.url,
                width: img.width,
                height: img.height,
                time: m["CreationDate"].as_str().unwrap_or_default().to_string(),
                sender: m["SenderDisplayName"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                sender_mri: m["From"].as_str().unwrap_or_default().to_string(),
                message_id: m["MessageId"].as_str().unwrap_or_default().to_string(),
                ..Default::default()
            });
        }
    }
    // Newest first, as the tab groups them.
    out.sort_by(|a, b| b.time.cmp(&a.time));
    out
}

async fn search(client: &TeamsClient, body: &Value) -> Result<Value> {
    super::client::retry_throttled(|| async {
        client
            .teams_post(MESSAGE_SEARCH, body)
            .await?
            .json::<Value>()
            .await
            .context("Message search reply")
    })
    .await
}

/// The chat's files (Teams free's Files tab asks for 50).
pub async fn chat_files(client: &TeamsClient, thread: &str) -> Result<Vec<ChatFile>> {
    Ok(parse_files(
        &search(client, &files_query(thread, 0, 50)).await?,
    ))
}

/// A page of the chat's pictures (Teams free's Photos tab asks for 5 at a
/// time as it scrolls); `more` when the page was full.
pub async fn chat_photos(
    client: &TeamsClient,
    thread: &str,
    base: u32,
    count: u32,
) -> Result<(Vec<ChatFile>, bool)> {
    let reply = search(client, &photos_query(thread, base, count)).await?;
    let full = reply.as_array().map(|a| a.len()).unwrap_or(0) >= count as usize;
    Ok((parse_photos(&reply), full))
}

/// The media store's small thumbnail of a picture (the Photos tab's
/// tiles): `img_thumb_small` beside its `imgo` view.
pub fn thumb_url(preview_url: &str) -> String {
    match preview_url.rsplit_once("/views/") {
        Some((base, _)) => format!("{base}/views/img_thumb_small?v=1"),
        None => preview_url.to_string(),
    }
}

/// Graph's share id for a link (`u!` and the link in unpadded base64url).
pub fn share_id_of(url: &str) -> String {
    use base64::Engine;
    format!(
        "u!{}",
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(url.as_bytes())
    )
}

/// Download a file shared in a personal chat: redeem its link (Teams'
/// `prefer: redeemSharingLink`) for the item's download address, then get
/// the bytes from there (pre-authorised: no token goes with it).
pub async fn download_shared(client: &TeamsClient, share_url: &str) -> Result<Vec<u8>> {
    if !share_url.starts_with("https://") {
        bail!("No link to download");
    }
    let item: Value = client
        .graph_get_with(
            &format!(
                "/shares/{}/driveItem?select=id,name,%40microsoft.graph.downloadUrl",
                share_id_of(share_url)
            ),
            &[("prefer", "redeemSharingLink")],
        )
        .await?
        .json()
        .await
        .context("File reply")?;
    let url = item["@microsoft.graph.downloadUrl"]
        .as_str()
        .filter(|u| u.starts_with("https://"))
        .context("No download address")?;
    let resp = reqwest::Client::new()
        .get(url)
        .send()
        .await
        .context("Download")?;
    if !resp.status().is_success() {
        bail!("Download failed: HTTP {}", resp.status().as_u16());
    }
    Ok(resp.bytes().await.context("Download")?.to_vec())
}

/// A row of the personal OneDrive picker (Attach cloud files: My files,
/// Recent, Photos, Shared).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct PickerItem {
    pub id: String,
    pub drive_id: String,
    pub name: String,
    pub kind: String,
    pub is_folder: bool,
    pub child_count: u64,
    pub size: u64,
    /// Modified (My files) or Accessed (Recent), ISO.
    pub time: String,
    pub modified_by: String,
    pub web_url: String,
}

fn picker_item(v: &Value) -> PickerItem {
    // Recent and Shared answer with the item under remoteItem.
    let r = if v["remoteItem"].is_object() && v["folder"].is_null() && v["file"].is_null() {
        &v["remoteItem"]
    } else {
        v
    };
    let name = v["name"]
        .as_str()
        .or(r["name"].as_str())
        .unwrap_or_default();
    let is_folder = r["folder"].is_object() || v["folder"].is_object();
    PickerItem {
        id: r["id"].as_str().unwrap_or_default().to_string(),
        drive_id: r
            .pointer("/parentReference/driveId")
            .and_then(|d| d.as_str())
            .unwrap_or_default()
            .to_string(),
        name: name.to_string(),
        kind: if is_folder {
            String::new()
        } else {
            ext_of(name)
        },
        is_folder,
        child_count: r
            .pointer("/folder/childCount")
            .and_then(|c| c.as_u64())
            .unwrap_or(0),
        size: r["size"].as_u64().or(v["size"].as_u64()).unwrap_or(0),
        time: v
            .pointer("/fileSystemInfo/lastAccessedDateTime")
            .or(v.get("lastModifiedDateTime"))
            .and_then(|t| t.as_str())
            .unwrap_or_default()
            .to_string(),
        modified_by: v
            .pointer("/lastModifiedBy/user/displayName")
            .and_then(|n| n.as_str())
            .filter(|n| *n != "System Account")
            .unwrap_or_default()
            .to_string(),
        web_url: r["webUrl"]
            .as_str()
            .or(v["webUrl"].as_str())
            .unwrap_or_default()
            .to_string(),
    }
}

/// The picker's rows for a place: "myfiles" (a folder's children, `folder`
/// an item id or empty for the top), "recent", "photos" (the Pictures
/// folder) or "shared". Folders first, then by name (My files).
pub async fn picker_list(
    client: &TeamsClient,
    place: &str,
    folder: &str,
) -> Result<Vec<PickerItem>> {
    let path = match place {
        "recent" => "/me/drive/recent?$top=100".to_string(),
        "shared" => "/me/drive/sharedWithMe?$top=100".to_string(),
        "photos" => "/me/drive/special/photos/children?$top=200".to_string(),
        _ if folder.is_empty() => "/me/drive/root/children?$top=200".to_string(),
        _ => {
            anyhow::ensure!(
                folder
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '!' || c == '-'),
                "Unexpected folder id"
            );
            format!("/me/drive/items/{folder}/children?$top=200")
        }
    };
    let v: Value = client
        .graph_get(&path)
        .await?
        .json()
        .await
        .context("Folder reply")?;
    let mut items: Vec<PickerItem> = v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .map(picker_item)
        .filter(|i| !i.id.is_empty())
        .collect();
    if place == "myfiles" || place.is_empty() || place == "photos" {
        items.sort_by(|a, b| {
            b.is_folder
                .cmp(&a.is_folder)
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
    }
    if place == "photos" {
        items.retain(|i| i.is_folder || is_preview_image(&i.name));
    }
    Ok(items)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn uploaded() -> Value {
        // Graph's reply to OST TASK-0300's upload (Personal 1, 2026-11-28).
        json!({
            "id": "77AC230600C33285!s2b4515818ef1451ebdb724b8751bad5a",
            "name": "ost-tperF-test-1.txt",
            "webUrl": "https://onedrive.live.com?cid=77ac230600c33285&id=77AC230600C33285!s2b4515818ef1451ebdb724b8751bad5a",
            "parentReference": { "driveType": "personal", "driveId": "77ac230600c33285", "path": "/drive/root:/Microsoft Teams Chat Files" },
            "sharepointIds": { "listItemUniqueId": "2B451581-8ef1-451e-bdb7-24b8751bad5a",
                "siteUrl": "https://my.microsoftpersonalcontent.com/personal/77ac230600c33285" }
        })
    }

    #[test]
    fn upload_records_are_teams_frees() {
        let r = upload_record(
            &uploaded(),
            ("https://1drv.ms/t/c/77ac230600c33285/IQCB", "u!aHR0"),
            None,
        );
        assert_eq!(r["itemid"], "2b451581-8ef1-451e-bdb7-24b8751bad5a");
        assert_eq!(
            r["objectUrl"],
            "https://my.microsoftpersonalcontent.com/personal/77ac230600c33285/Documents/Microsoft Teams Chat Files/ost-tperF-test-1.txt"
        );
        assert_eq!(r["fileInfo"]["fileUrl"], r["objectUrl"]);
        assert_eq!(
            r["fileInfo"]["siteUrl"],
            "https://my.microsoftpersonalcontent.com/personal/77ac230600c33285"
        );
        assert_eq!(
            r["fileInfo"]["shareUrl"],
            "https://1drv.ms/t/c/77ac230600c33285/IQCB"
        );
        assert_eq!(r["fileInfo"]["shareId"], "u!aHR0");
        assert_eq!(
            r["fileInfo"]["itemId"],
            "77AC230600C33285!s2b4515818ef1451ebdb724b8751bad5a"
        );
        assert_eq!(r["state"], "active");
        assert_eq!(r["fileChicletState"]["state"], "active");
        assert_eq!(r["permissionScope"], Value::Null);
        assert_eq!(r["filePreview"]["previewUrl"], "");
        // A picture names its media store preview.
        let p = Preview {
            id: "0-wus-d2-ca4a".into(),
            url: "https://us-api.asm.skype.com/v1/objects/0-wus-d2-ca4a/views/imgo".into(),
            width: 64,
            height: 48,
        };
        let r = upload_record(&uploaded(), ("a", "b"), Some(&p));
        assert_eq!(r["filePreview"]["previewWidth"], 64);
        assert_eq!(r["filePreview"]["previewHeight"], 48);
        let files = super::super::files::parse_files(&json!([r]));
        assert_eq!(files[0].preview_url, p.url);
        assert_eq!((files[0].preview_width, files[0].preview_height), (64, 48));
    }

    #[test]
    fn picked_files_are_references_with_encoded_addresses() {
        let mut item = uploaded();
        item["sharepointIds"] = Value::Null;
        item["parentReference"]["sharepointIds"] = json!({ "siteUrl": "https://my.microsoftpersonalcontent.com/personal/77ac230600c33285" });
        let r = reference_record(&item, ("https://1drv.ms/t/x", "u!x"));
        assert_eq!(
            r["objectUrl"],
            "https://my.microsoftpersonalcontent.com/personal/77ac230600c33285/Documents/Microsoft%20Teams%20Chat%20Files/ost-tperF-test-1.txt"
        );
        assert_eq!(r["state"], "reference");
        assert_eq!(r["sharepointIds"]["driveId"], "77ac230600c33285");
        assert_eq!(r["isUploadError"], false);
    }

    #[test]
    fn full_onedrive_is_storage_full() {
        let e = anyhow::Error::new(HttpError {
            status: 507,
            url: "x".into(),
            body: String::new(),
            retry_after: None,
        });
        assert!(is_storage_full(&e));
        let e = anyhow::Error::new(HttpError {
            status: 403,
            url: "x".into(),
            body: r#"{"error":{"code":"quotaLimitReached"}}"#.into(),
            retry_after: None,
        });
        assert!(is_storage_full(&e.context(StorageFull)));
        assert!(!is_storage_full(&anyhow::anyhow!("HTTP 500")));
    }

    #[test]
    fn picture_sizes_from_headers() {
        // A 64 x 48 PNG header.
        let mut png = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        png.extend_from_slice(&64u32.to_be_bytes());
        png.extend_from_slice(&48u32.to_be_bytes());
        assert_eq!(image_size(&png), Some((64, 48)));
        let gif = b"GIF89a\x20\x03\x58\x02".to_vec();
        assert_eq!(image_size(&gif), Some((800, 600)));
        // JPEG: SOI, APP0 (2 + 16), SOF0 with 600 x 800.
        let mut jpg = vec![0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
        jpg.extend_from_slice(&[0; 14]);
        jpg.extend_from_slice(&[0xff, 0xc0, 0x00, 0x11, 0x08, 0x02, 0x58, 0x03, 0x20]);
        assert_eq!(image_size(&jpg), Some((800, 600)));
        assert_eq!(image_size(b"not a picture"), None);
        assert!(is_preview_image("a.JPG") && is_preview_image("b.png"));
        assert!(!is_preview_image("c.txt") && !is_preview_image("d.mp4"));
    }

    #[test]
    fn search_answers_list_files_and_photos() {
        // msgsearch's answer for the 1:1 (Personal 1, 2026-11-28), cut down.
        let reply = json!([
            { "Content": "<p>OST TASK-0300 photo from Personal 1</p>", "CreationDate": "2026-11-28T06:50:01.197Z",
              "MessageId": "2919443237223226877", "From": "8:live:.cid.77ac230600c33285", "SenderDisplayName": "OST Personal 1",
              "MetadataList": [
                { "MetadataType": "DisplayName", "MetadataPropertyList": [{ "Key": "Sender", "Value": "OST Personal 1" }] },
                { "MetadataType": "files", "MetadataPropertyList": [
                    { "Key": "fileName", "Value": "ost-tperF-photo-1.png" }, { "Key": "fileType", "Value": "png" },
                    { "Key": "fileInfofileUrl", "Value": "https://my.microsoftpersonalcontent.com/personal/77ac230600c33285/Documents/Microsoft Teams Chat Files/ost-tperF-photo-1.png" },
                    { "Key": "fileInfoshareUrl", "Value": "https://1drv.ms/i/c/77ac230600c33285/IQDv" },
                    { "Key": "filePreviewpreviewUrl", "Value": "https://us-api.asm.skype.com/v1/objects/0-wus-d2-ca4ae59d/views/imgo" },
                    { "Key": "filePreviewpreviewHeight", "Value": "48" }, { "Key": "filePreviewpreviewWidth", "Value": "64" }] }] },
            { "Content": "<p>OST TASK-0300 file from Personal 1</p>", "CreationDate": "2026-11-28T06:47:25.019Z",
              "MessageId": "2718778924348568445", "From": "8:live:.cid.77ac230600c33285", "SenderDisplayName": "OST Personal 1",
              "MetadataList": [{ "MetadataType": "files", "MetadataPropertyList": [
                    { "Key": "fileName", "Value": "ost-tperF-test-1.txt" }, { "Key": "fileType", "Value": "txt" },
                    { "Key": "fileInfoshareUrl", "Value": "https://1drv.ms/t/c/77ac230600c33285/IQCB" },
                    { "Key": "filePreviewpreviewUrl", "Value": "" }] }] },
            { "Content": "<p><img itemtype=\"http://schema.skype.com/AMSImage\" src=\"https://us-api.asm.skype.com/v1/objects/0-wus-d1-aa/views/imgo\" itemid=\"0-wus-d1-aa\" width=\"250\" height=\"100\"></p>",
              "CreationDate": "2026-11-28T06:40:00.000Z", "MessageId": "1", "From": "8:live:.cid.0ca2738c364862c6", "SenderDisplayName": "OST Personal 2", "MetadataList": [] }
        ]);
        let files = parse_files(&reply);
        assert_eq!(files.len(), 2);
        assert_eq!(files[0].name, "ost-tperF-photo-1.png");
        assert_eq!(files[0].sender, "OST Personal 1");
        assert_eq!(files[0].time, "2026-11-28T06:50:01.197Z");
        assert_eq!((files[0].width, files[0].height), (64, 48));
        assert_eq!(
            files[1].share_url,
            "https://1drv.ms/t/c/77ac230600c33285/IQCB"
        );
        let photos = parse_photos(&reply);
        assert_eq!(photos.len(), 2);
        assert_eq!(photos[0].name, "ost-tperF-photo-1.png");
        assert_eq!(
            photos[1].preview_url,
            "https://us-api.asm.skype.com/v1/objects/0-wus-d1-aa/views/imgo"
        );
        assert_eq!(photos[1].sender, "OST Personal 2");
        assert_eq!(
            thumb_url(&photos[0].preview_url),
            "https://us-api.asm.skype.com/v1/objects/0-wus-d2-ca4ae59d/views/img_thumb_small?v=1"
        );
        assert_eq!(
            ams_object_id(&photos[0].preview_url).as_deref(),
            Some("0-wus-d2-ca4ae59d")
        );
        let q = files_query("19:x@thread.v2", 0, 50);
        assert_eq!(q["OPTION"]["RESULTCOUNT"], 50);
        assert_eq!(q["QUERYSTRING"]["and"][0]["ThreadId"], "19:x@thread.v2");
        assert_eq!(
            photos_query("19:x@thread.v2", 5, 5)["OPTION"]["RESULTBASE"],
            5
        );
    }

    #[test]
    fn share_ids_are_graphs() {
        // Teams' shareId for the link above (createLink's answer).
        assert_eq!(
            share_id_of(
                "https://1drv.ms/t/c/77ac230600c33285/IQCBFUUr8Y4eRb23JLh1G61aAXdCuT_CEzaEFHK-QNdUXQY"
            ),
            "u!aHR0cHM6Ly8xZHJ2Lm1zL3QvYy83N2FjMjMwNjAwYzMzMjg1L0lRQ0JGVVVyOFk0ZVJiMjNKTGgxRzYxYUFYZEN1VF9DRXphRUZISy1RTmRVWFFZ"
        );
    }

    #[test]
    fn picker_rows_from_graph() {
        let recent = json!({ "id": "x", "name": "ost-test-287.txt", "fileSystemInfo": { "lastAccessedDateTime": "2026-11-27T18:20:26Z" },
            "lastModifiedBy": { "user": { "displayName": "ost-personal2-0238@outlook.com" } },
            "remoteItem": { "id": "0CA2738C364862C6!sc591", "name": "ost-test-287.txt", "size": 29, "file": {},
                "parentReference": { "driveId": "0CA2738C364862C6" }, "webUrl": "https://d.docs.live.net/x" } });
        let r = picker_item(&recent);
        assert_eq!(
            (r.id.as_str(), r.drive_id.as_str(), r.kind.as_str()),
            ("0CA2738C364862C6!sc591", "0CA2738C364862C6", "txt")
        );
        assert_eq!(r.time, "2026-11-27T18:20:26Z");
        let folder = json!({ "id": "f", "name": "Documents", "folder": { "childCount": 3 }, "lastModifiedDateTime": "2026-11-27T18:18:59Z",
            "lastModifiedBy": { "user": { "displayName": "System Account" } }, "parentReference": { "driveId": "d" } });
        let f = picker_item(&folder);
        assert!(f.is_folder && f.child_count == 3 && f.modified_by.is_empty() && f.kind.is_empty());
    }
}
