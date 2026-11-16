//! Word, Excel and PowerPoint files in Office for the web inside Teams, as
//! Teams' "Teams" choice in Settings ▸ Files and links opens them
//! (measured in Teams on the web 2026-11-16, docs/spec/app-host.md "Office
//! files in Teams"): the file opens in the Office app's personal page
//! (Word `d7958adf…`, Excel `1c256a65…`, PowerPoint `3e0a4fec…`, Teams'
//! file-viewer routing) in Teams' app host, full screen beside the app
//! bar; the page reads which file from its context's `subEntityId`.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// Word's, Excel's and PowerPoint's Teams apps (Teams' file-type map).
pub const WORD: &str = "d7958adf-f419-46fa-941b-1b946497ef84";
pub const EXCEL: &str = "1c256a65-83a6-4b5c-9ccf-78f8afb6f1e8";
pub const POWERPOINT: &str = "3e0a4fec-499b-4138-8e7c-71a9d88a62ed";

/// The Office app Teams opens a file in, by its extension.
pub fn app_for(name: &str) -> Option<(&'static str, &'static str)> {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    match ext.as_str() {
        "docx" | "doc" | "docm" | "dotx" | "dotm" | "dot" | "odt" | "rtf" => Some((WORD, "Word")),
        "xlsx" | "xls" | "xlsm" | "xlsb" | "xltx" | "xltm" | "ods" | "csv" => Some((EXCEL, "Excel")),
        "pptx" | "ppt" | "pptm" | "ppsx" | "pps" | "ppsm" | "potx" | "potm" | "odp" => Some((POWERPOINT, "PowerPoint")),
        _ => None,
    }
}

/// The file as the Office page's `subEntityId` names it (measured, a
/// file opened with Edit in Teams from the OneDrive app):
/// `{title, fileId (the item's unique id), objectUrl (its WebDAV address),
/// siteUrl, serviceName "teamsSdk_<opening app>_ns", fileType, shareId,
/// shareUrl, subEntityId, context "bim", ctx "rwc", viewerAction "edit",
/// atpSharepointData null, baseUrl}`.
pub fn sub_entity(title: &str, unique_id: &str, object_url: &str, site_url: &str, caller_app: &str) -> serde_json::Value {
    let file_type = title.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    serde_json::json!({
        "title": title,
        "fileId": unique_id.trim_matches(|c| c == '{' || c == '}').to_ascii_lowercase(),
        "objectUrl": object_url,
        "siteUrl": site_url,
        "serviceName": format!("teamsSdk_{caller_app}_ns"),
        "fileType": file_type,
        "shareId": "",
        "shareUrl": "",
        "subEntityId": "",
        "context": "bim",
        "ctx": "rwc",
        "viewerAction": "edit",
        "atpSharepointData": null,
        "baseUrl": site_url,
    })
}

/// What OST needs to open a file as Teams does: `{appId, appName, entityId,
/// subEntityId (a JSON string), serviceName, ctx}`, from the item (drive
/// and item ids) or its address.
pub async fn open_info(client: &TeamsClient, url: &str, drive_id: &str, item_id: &str, caller_app: &str) -> Result<serde_json::Value> {
    const SELECT: &str = "$select=name,webDavUrl,webUrl,sharepointIds";
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "!-_.".contains(c));
    let v: serde_json::Value = if ok(drive_id) && ok(item_id) {
        client.graph_get(&format!("/drives/{drive_id}/items/{item_id}?{SELECT}")).await?.json().await?
    } else {
        anyhow::ensure!(url.starts_with("https://"), "No file address");
        client.graph_get(&format!("/shares/{}/driveItem?{SELECT}", super::drive::share_id(url))).await?.json().await?
    };
    let s = |p: &str| v.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    let name = s("/name");
    let (app, app_name) = app_for(&name).context("Not a Word, Excel or PowerPoint file")?;
    let unique = s("/sharepointIds/listItemUniqueId");
    let site = s("/sharepointIds/siteUrl");
    anyhow::ensure!(!unique.is_empty() && !site.is_empty(), "The file isn't in SharePoint or OneDrive");
    let caller = if caller_app.is_empty() { "5af6a76b-40fc-4ba1-af29-8f49b08e44fd" } else { caller_app };
    let sub = sub_entity(&name, &unique, &s("/webDavUrl"), &site, caller);
    Ok(serde_json::json!({
        "appId": app,
        "appName": app_name,
        // (Teams' entity for the Office apps' file page, as measured.)
        "entityId": "MyNotebook",
        "subEntityId": sub.to_string(),
        "serviceName": format!("teamsSdk_{caller}_ns"),
        "ctx": "rwc",
        "title": name,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn office_files_open_in_their_apps() {
        assert_eq!(app_for("Report.DOCX").unwrap().0, WORD);
        assert_eq!(app_for("budget.xlsx").unwrap().1, "Excel");
        assert_eq!(app_for("deck.pptx").unwrap().0, POWERPOINT);
        assert!(app_for("notes.txt").is_none());
        assert!(app_for("noext").is_none());
        let s = sub_entity("ost-open-test.docx", "{A86708F4-3A18-4EA3-AB6D-2D698DABC45F}", "https://x-my.sharepoint.com/personal/u/Documents/ost-open-test.docx",
            "https://x-my.sharepoint.com/personal/u", "5af6a76b-40fc-4ba1-af29-8f49b08e44fd");
        assert_eq!(s["fileId"], "a86708f4-3a18-4ea3-ab6d-2d698dabc45f");
        assert_eq!(s["fileType"], "docx");
        assert_eq!(s["serviceName"], "teamsSdk_5af6a76b-40fc-4ba1-af29-8f49b08e44fd_ns");
        assert_eq!(s["viewerAction"], "edit");
        assert_eq!(s["baseUrl"], "https://x-my.sharepoint.com/personal/u");
    }
}
