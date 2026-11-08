//! Files in chats, as Teams does them: the sender uploads to their own
//! OneDrive ("Microsoft Teams Chat Files"), shares the file with the chat's
//! members, and posts the message with a `properties.files` record. The
//! record format here mirrors what the Teams desktop client sends.

use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};

use super::client::TeamsClient;

/// Teams' folder for files shared in chats.
const CHAT_FILES_FOLDER: &str = "Microsoft Teams Chat Files";
/// Graph's limit for a single-request upload; larger files use a session.
const SIMPLE_UPLOAD_MAX: usize = 4 * 1024 * 1024;
/// Upload session chunk: a multiple of 320 KiB, as Graph requires.
const CHUNK: usize = 16 * 320 * 1024;
/// The largest file OST will send.
pub const MAX_FILE_BYTES: u64 = 250 * 1024 * 1024;

/// A file attached to a message.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct FileAttachment {
    pub name: String,
    /// Extension, e.g. "txt", "docx".
    pub file_type: String,
    /// The file in its owner's OneDrive/SharePoint.
    pub object_url: String,
    /// A sharing link, when the sender made one.
    pub share_url: String,
}

/// The attachments in a message's `properties.files` (JSON text or array).
pub fn parse_files(files: &serde_json::Value) -> Vec<FileAttachment> {
    let list = match files {
        serde_json::Value::String(s) => {
            serde_json::from_str::<serde_json::Value>(s).unwrap_or_default()
        }
        other => other.clone(),
    };
    list.as_array()
        .into_iter()
        .flatten()
        .filter_map(|f| {
            let s = |k: &str| {
                f.get(k)
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string()
            };
            let name = Some(s("fileName"))
                .filter(|n| !n.is_empty())
                .unwrap_or_else(|| s("title"));
            if name.is_empty() {
                return None;
            }
            let object_url = Some(s("objectUrl"))
                .filter(|u| !u.is_empty())
                .or_else(|| {
                    f.pointer("/fileInfo/fileUrl")
                        .and_then(|u| u.as_str())
                        .map(str::to_string)
                })
                .unwrap_or_default();
            let share_url = f
                .pointer("/fileInfo/shareUrl")
                .and_then(|u| u.as_str())
                .unwrap_or_default()
                .to_string();
            let file_type = Some(s("fileType"))
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| ext_of(&name));
            Some(FileAttachment {
                name,
                file_type,
                object_url,
                share_url,
            })
        })
        .collect()
}

fn ext_of(name: &str) -> String {
    Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
}

/// Percent-encode one path segment for a Graph `root:/…:` path.
pub(crate) fn seg(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes())
        .collect::<String>()
        .replace('+', "%20")
}

/// Upload a file to your Teams chat files, share it with the chat's other
/// members, and return the `properties.files` entry for the message.
pub async fn upload_for_chat(
    client: &TeamsClient,
    chat_id: &str,
    path: &Path,
) -> Result<serde_json::Value> {
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
    let bytes = std::fs::read(path).with_context(|| format!("Cannot read {}", path.display()))?;
    let item_path = format!("/me/drive/root:/{}/{}:", seg(CHAT_FILES_FOLDER), seg(&name));
    let item: serde_json::Value = if bytes.len() <= SIMPLE_UPLOAD_MAX {
        client
            .graph_put_bytes(
                &format!("{item_path}/content?@microsoft.graph.conflictBehavior=rename"),
                bytes,
                "application/octet-stream",
            )
            .await?
            .json()
            .await
            .context("Upload reply")?
    } else {
        upload_in_session(client, &item_path, bytes).await?
    };
    let item_id = item["id"]
        .as_str()
        .context("Upload reply has no id")?
        .to_string();

    // Share with the chat's other members, as Teams does (write access, no
    // invitation e-mail).
    let emails = member_emails(client, chat_id).await.unwrap_or_default();
    let mut share_url = String::new();
    if !emails.is_empty() {
        let recipients: Vec<_> = emails
            .iter()
            .map(|e| serde_json::json!({ "email": e }))
            .collect();
        let invite: serde_json::Value = client
            .graph_post(
                &format!("/me/drive/items/{item_id}/invite"),
                &serde_json::json!({
                    "recipients": recipients,
                    "roles": ["write"],
                    "requireSignIn": true,
                    "sendInvitation": false
                }),
            )
            .await?
            .json()
            .await
            .unwrap_or_default();
        share_url = invite
            .pointer("/value/0/link/webUrl")
            .and_then(|u| u.as_str())
            .unwrap_or_default()
            .to_string();
    }

    // The ids and URLs Teams puts in the record.
    let full: serde_json::Value = client
        .graph_get(&format!(
            "/me/drive/items/{item_id}?$select=id,name,webUrl,sharepointIds"
        ))
        .await?
        .json()
        .await
        .context("File details")?;
    let web_url = full["webUrl"].as_str().unwrap_or_default().to_string();
    let ids = full.get("sharepointIds").cloned().unwrap_or_default();
    let site_url = ids["siteUrl"]
        .as_str()
        .unwrap_or_default()
        .trim_end_matches('/')
        .to_string();
    let unique = ids["listItemUniqueId"]
        .as_str()
        .map(|u| u.to_ascii_lowercase())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let final_name = full["name"].as_str().unwrap_or(&name).to_string();
    let file_type = ext_of(&final_name);
    Ok(serde_json::json!({
        "itemid": unique,
        "fileName": final_name,
        "fileType": file_type,
        "fileInfo": {
            "itemId": item_id,
            "fileUrl": web_url,
            "siteUrl": format!("{site_url}/"),
            "serverRelativeUrl": "",
            "shareUrl": if share_url.is_empty() { web_url.clone() } else { share_url },
            "shareId": ""
        },
        "fileChicletState": { "serviceName": "p2p", "state": "active" },
        "@type": "http://schema.skype.com/File",
        "version": 2,
        "id": unique,
        "baseUrl": format!("{site_url}/"),
        "objectUrl": web_url,
        "openUrl": null,
        "type": file_type,
        "title": final_name,
        "state": "active",
        "providerData": "",
        "botFileProperties": {},
        "permissionScope": "users",
        "filePreview": { "previewUrl": "", "previewHeight": 0, "previewWidth": 0 },
        "sharepointIds": ids
    }))
}

/// Upload larger files in chunks through a Graph upload session.
pub(crate) async fn upload_in_session(
    client: &TeamsClient,
    item_path: &str,
    bytes: Vec<u8>,
) -> Result<serde_json::Value> {
    let session: serde_json::Value = client
        .graph_post(
            &format!("{item_path}/createUploadSession"),
            &serde_json::json!({ "item": { "@microsoft.graph.conflictBehavior": "rename" } }),
        )
        .await?
        .json()
        .await
        .context("Upload session reply")?;
    let url = session["uploadUrl"]
        .as_str()
        .context("No upload URL")?
        .to_string();
    // The upload URL is pre-authorised; it must not get a bearer token.
    let http = reqwest::Client::new();
    let total = bytes.len();
    let mut start = 0;
    loop {
        let end = (start + CHUNK).min(total);
        let resp = http
            .put(&url)
            .header("Content-Length", (end - start).to_string())
            .header(
                "Content-Range",
                format!("bytes {}-{}/{}", start, end - 1, total),
            )
            .body(bytes[start..end].to_vec())
            .send()
            .await
            .context("Upload chunk failed")?;
        let status = resp.status();
        if !status.is_success() {
            bail!("Upload failed: HTTP {}", status.as_u16());
        }
        if end == total {
            return resp.json().await.context("Upload reply");
        }
        start = end;
    }
}

/// The e-mail addresses of a chat's other members (for sharing a file).
async fn member_emails(client: &TeamsClient, chat_id: &str) -> Result<Vec<String>> {
    let oids = member_oids(client, chat_id).await?;
    let mut emails = Vec::new();
    for oid in oids.iter().take(50) {
        if let Ok(r) = client
            .graph_get(&format!("/users/{oid}?$select=mail,userPrincipalName"))
            .await
        {
            let u: serde_json::Value = r.json().await.unwrap_or_default();
            if let Some(m) = u["mail"]
                .as_str()
                .or_else(|| u["userPrincipalName"].as_str())
            {
                emails.push(m.to_string());
            }
        }
    }
    Ok(emails)
}

/// The object ids of a chat's other members (people only; checked to be
/// object ids).
pub async fn member_oids(client: &TeamsClient, chat_id: &str) -> Result<Vec<String>> {
    let me = client.object_id().unwrap_or_default();
    let oids: Vec<String> = if let Some(inner) = chat_id
        .strip_prefix("19:")
        .and_then(|c| c.strip_suffix("@unq.gbl.spaces"))
    {
        inner
            .split('_')
            .filter(|o| !o.eq_ignore_ascii_case(&me))
            .map(str::to_string)
            .collect()
    } else {
        let url = format!(
            "{}/v1/threads/{}?view=msnp24Equivalent",
            client.chat_service_url(),
            chat_id
        );
        let v: serde_json::Value = client
            .chat_get(&url)
            .await?
            .json()
            .await
            .context("Thread reply")?;
        v.get("members")
            .and_then(|m| m.as_array())
            .into_iter()
            .flatten()
            .filter_map(|m| m.get("id").and_then(|i| i.as_str()))
            .filter_map(|id| id.strip_prefix("8:orgid:"))
            .filter(|o| !o.eq_ignore_ascii_case(&me))
            .map(str::to_string)
            .collect()
    };
    Ok(oids
        .into_iter()
        .filter(|o| !o.is_empty() && o.chars().all(|c| c.is_ascii_hexdigit() || c == '-'))
        .collect())
}

/// Post a message with files (and optional text), as Teams does.
pub async fn send_with_files(
    client: &TeamsClient,
    chat_id: &str,
    text: &str,
    files: Vec<serde_json::Value>,
) -> Result<()> {
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages",
        client.chat_service_url(),
        chat_id
    );
    let content = if text.trim().is_empty() {
        String::new()
    } else {
        format!("<p>{}</p>", super::chat::html_escape(text))
    };
    let mut body = serde_json::json!({
        "content": content,
        "messagetype": "RichText/Html",
        "contenttype": "text",
        "clientmessageid": format!("{}", rand_id()),
        "properties": {
            "importance": "",
            "subject": "",
            "title": "",
            "cards": "[]",
            "links": "[]",
            "mentions": "[]",
            "files": serde_json::Value::Array(files).to_string(),
            "formatVariant": "TEAMS"
        }
    });
    if let Some(name) = client.display_name() {
        body["imdisplayname"] = serde_json::Value::String(name);
    }
    client.chat_post(&url, &body).await?;
    Ok(())
}

fn rand_id() -> u64 {
    let n = uuid::Uuid::new_v4().as_u128();
    (n as u64) & 0x7fff_ffff_ffff_ffff
}

/// Download an attachment into `dir`, keeping its name (adding " (1)" etc.
/// when that name is taken). Returns the saved path.
pub async fn download(client: &TeamsClient, file: &FileAttachment, dir: &Path) -> Result<PathBuf> {
    let source = if file.object_url.is_empty() {
        &file.share_url
    } else {
        &file.object_url
    };
    if !source.starts_with("https://") {
        bail!("No download link for {}", file.name);
    }
    use base64::Engine;
    let token = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(source.as_bytes());
    let resp = client
        .graph_get(&format!("/shares/u!{token}/driveItem/content"))
        .await?;
    let bytes = resp.bytes().await.context("Download")?;
    save_unique(dir, &file.name, &bytes)
}

/// Save `bytes` as `name` in `dir`, never outside it, adding " (n)" when
/// the name is taken.
pub fn save_unique(dir: &Path, name: &str, bytes: &[u8]) -> Result<PathBuf> {
    std::fs::create_dir_all(dir)?;
    // Never let a remote name escape the folder.
    let safe = Path::new(name)
        .file_name()
        .and_then(|n| n.to_str())
        .filter(|n| !n.is_empty() && *n != "." && *n != "..")
        .unwrap_or("download")
        .to_string();
    let mut target = dir.join(&safe);
    let stem = Path::new(&safe)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("download")
        .to_string();
    let ext = Path::new(&safe)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{e}"))
        .unwrap_or_default();
    let mut n = 1;
    while target.exists() {
        target = dir.join(format!("{stem} ({n}){ext}"));
        n += 1;
    }
    std::fs::write(&target, bytes)?;
    Ok(target)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_teams_file_records() {
        let files = serde_json::json!([{
            "fileName": "ost-attachment-test.txt", "fileType": "txt",
            "objectUrl": "https://x.sharepoint.com/personal/a/Documents/Microsoft%20Teams%20Chat%20Files/ost-attachment-test.txt",
            "fileInfo": { "shareUrl": "https://x.sharepoint.com/:t:/p/a/abc" }
        }]).to_string();
        let got = parse_files(&serde_json::Value::String(files));
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name, "ost-attachment-test.txt");
        assert_eq!(got[0].file_type, "txt");
        assert!(got[0].share_url.ends_with("/abc"));
        assert!(parse_files(&serde_json::json!("not json")).is_empty());
        assert!(parse_files(&serde_json::json!([{ "fileType": "txt" }])).is_empty());
    }

    #[test]
    fn upload_paths_are_encoded() {
        assert_eq!(
            seg("Microsoft Teams Chat Files"),
            "Microsoft%20Teams%20Chat%20Files"
        );
        assert_eq!(seg("a/b#c?.txt"), "a%2Fb%23c%3F.txt");
    }
}
