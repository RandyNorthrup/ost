//! Download of a folder or of several items as one zip, as Teams' Files
//! apps do it (docs/spec/zip-download.md): OneDrive's media service
//! (`{mediaBaseUrl}/transform/zip`) zips the items it is given, each
//! addressed with the library's drive access token from SharePoint's list
//! data.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use super::drive::DriveItem;
use super::files::save_unique;

/// OneDrive numbers its zips from 1 in each session ("OneDrive_1_…").
static ZIPS: AtomicU32 = AtomicU32::new(0);

/// The zip's name: the one item's ("Notebooks.zip"), else
/// "OneDrive_{n}_{M-D-YYYY}.zip".
pub fn zip_name(items: &[DriveItem], n: u32, today: chrono::NaiveDate) -> String {
    match items {
        [one] => format!("{}.zip", one.name),
        _ => format!("OneDrive_{n}_{}.zip", today.format("%-m-%-d-%Y")),
    }
}

/// The form's `files`: each item addressed through SharePoint's v2.0 API
/// with the drive access token (`access_token=…`).
pub fn files_json(items: &[DriveItem], host: &str, drive_token: &str) -> String {
    let host = host.trim_end_matches('/');
    json!({ "items": items.iter().map(|it| json!({
        "name": it.name,
        "size": if it.is_folder { 0 } else { it.size },
        "docId": format!("{host}:443/_api/v2.0/drives/{}/items/{}?version=Published&{drive_token}", it.drive_id, it.id),
        "isFolder": it.is_folder,
    })).collect::<Vec<_>>() })
    .to_string()
}

/// The media service's address, its caller stack and the drive access
/// token, from the list's schema (`.mediaBaseUrl`, `.callerStack`,
/// `.driveAccessToken`).
async fn list_tokens(item: &DriveItem) -> Result<(String, String, String)> {
    let list = item.sp_list.trim_matches(|c| c == '{' || c == '}');
    if list.is_empty() || !list.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Not a list id");
    }
    let url = format!("{}/_api/web/lists(guid'{list}')/RenderListDataAsStream", item.sp_site.trim_end_matches('/'));
    let body = json!({ "parameters": {
        "__metadata": { "type": "SP.RenderListDataParameters" },
        // Teams' value: list data and schema with the drive tokens.
        "RenderOptions": 5691143,
        "ViewXml": "<View><ViewFields><FieldRef Name=\"UniqueId\"/></ViewFields><RowLimit>1</RowLimit></View>",
    }});
    let reply: Value = super::sharing::post_with(&url, &body, &[("user-agent", super::client::TEAMS_WEB_UA)]).await?;
    let schema = if reply.get("ListSchema").is_some() { &reply["ListSchema"] } else { &reply };
    let s = |k: &str| schema[k].as_str().unwrap_or_default().to_string();
    let (media, stack, token) = (s(".mediaBaseUrl"), s(".callerStack"), s(".driveAccessToken"));
    if !media.starts_with("https://") || !token.starts_with("access_token=") {
        bail!("OneDrive's download service didn't answer");
    }
    Ok((media, stack, token))
}

/// Zip `items` (one library) and save the zip in `dir` (as `name` when
/// given, else OneDrive's name).
pub async fn download(items: &[DriveItem], dir: &Path, name: Option<&str>) -> Result<PathBuf> {
    let first = items.first().context("Nothing to download")?;
    if items.iter().any(|i| i.sp_list != first.sp_list || i.sp_site != first.sp_site) {
        bail!("These items are in different libraries");
    }
    let (media, stack, token) = list_tokens(first).await?;
    let host = first.sp_site.split('/').take(3).collect::<Vec<_>>().join("/");
    let name = match name.filter(|n| n.ends_with(".zip") && !n.contains(['/', '\\'])) {
        Some(n) => n.to_string(),
        None => zip_name(items, ZIPS.fetch_add(1, Ordering::SeqCst) + 1, chrono::Local::now().date_naive()),
    };
    let form = [
        ("zipFileName", name.clone()),
        ("guid", uuid::Uuid::new_v4().to_string()),
        ("provider", "spo".to_string()),
        ("files", files_json(items, &host, &token)),
        ("oAuthToken", String::new()),
        ("pacToken", String::new()),
        ("notificationUrl", String::new()),
    ];
    let cs: String = url::form_urlencoded::byte_serialize(stack.as_bytes()).collect();
    let resp = reqwest::Client::new()
        .post(format!("{}/transform/zip?cs={cs}", media.trim_end_matches('/')))
        .header(reqwest::header::USER_AGENT, super::client::TEAMS_WEB_UA)
        .form(&form)
        .send()
        .await
        .context("OneDrive's download service")?;
    let status = resp.status();
    if !status.is_success() {
        bail!("The zip wasn't made ({status})");
    }
    let bytes = resp.bytes().await.context("The zip")?;
    save_unique(dir, &name, &bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(name: &str, folder: bool) -> DriveItem {
        DriveItem { id: format!("ID{}", name.len()), drive_id: "b!d".into(), name: name.into(), is_folder: folder, size: 56, ..Default::default() }
    }

    #[test]
    fn zips_are_named_as_onedrive_names_them() {
        let day = chrono::NaiveDate::from_ymd_opt(2026, 11, 12).unwrap();
        assert_eq!(zip_name(&[item("Notebooks", true)], 1, day), "Notebooks.zip");
        assert_eq!(zip_name(&[item("a.txt", false), item("b.docx", false)], 1, day), "OneDrive_1_11-12-2026.zip");
    }

    #[test]
    fn files_are_addressed_with_the_drive_token() {
        let j: Value = serde_json::from_str(&files_json(&[item("ost-share-test.txt", false), item("Notebooks", true)], "https://x-my.sharepoint.com", "access_token=T")).unwrap();
        assert_eq!(j["items"][0], json!({"name": "ost-share-test.txt", "size": 56, "docId": "https://x-my.sharepoint.com:443/_api/v2.0/drives/b!d/items/ID18?version=Published&access_token=T", "isFolder": false}));
        assert_eq!((j["items"][1]["isFolder"].as_bool(), j["items"][1]["size"].as_u64()), (Some(true), Some(0)));
    }
}
