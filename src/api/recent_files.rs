//! Your recent files, as Teams' OneDrive app and its file pickers list
//! them. Graph's `/me/drive/recent` is retired (it returns nothing after
//! November 2026, with no Graph replacement); Teams never used it. Its
//! OneDrive app (OneDrive's `filebrowser.aspx`) reads SharePoint's recent
//! files service on your OneDrive's site, `sp.RecentFileCollection.
//! DeltaSync?top=500` (captured on winpc 2026-11-25), and leaves out what
//! OneDrive's `isInvalidOdbRecentItem` rejects: hidden or deleted files,
//! files never opened, folders other than OneNote notebooks, images,
//! classic attachments, other sources and a few file types. The rows come
//! newest opened first.

use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::{Value, json};

use super::client::TeamsClient;
use super::drive::DriveItem;
use super::sharing;

/// One recent file.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Recent {
    /// The file's name ("ost-share-test.txt"; a notebook's folder name).
    pub name: String,
    /// The name Teams shows: without the extension, or the title.
    pub title: String,
    /// Extension, lowercase; "one" for a OneNote notebook.
    pub kind: String,
    pub notebook: bool,
    /// The file's address in its library.
    pub web_url: String,
    /// Where OneDrive opens it (Doc.aspx, Loop), else `web_url`.
    pub open_url: String,
    /// Its place: the site's title ("OST Test Team"), "My Files", or
    /// "OST Test 3's Files" for someone else's OneDrive.
    pub location: String,
    /// When you last opened it (ISO).
    pub opened: String,
    /// The Owner column.
    pub owner: String,
    pub size: u64,
    /// The file's last change (ISO) and who made it.
    pub modified: String,
    pub modified_by: String,
    /// The Activity column, when there is one.
    pub activity: Option<Activity>,
    /// SharePoint's address for it.
    pub site_url: String,
    pub site_id: String,
    pub web_id: String,
    pub list_id: String,
    pub list_item_id: String,
    pub unique_id: String,
}

/// The recent service's activity for a file.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Activity {
    /// OneDrive's icon for it, as OST names them: "edit", "comment",
    /// "commentResponse", "share", "mention", "createTask", or "" (none).
    pub kind: String,
    /// The message with the people's names in ("OST Test 3 shared this in
    /// a Teams chat").
    pub text: String,
    /// The raw message ("{0} edited this") and its first person.
    pub format: String,
    pub user: String,
    /// When (ISO).
    pub time: String,
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

fn first(vals: &[&Value]) -> String {
    vals.iter()
        .map(|v| s(v))
        .find(|t| !t.is_empty())
        .unwrap_or_default()
}

/// The reply's entries (its `value` is JSON text).
pub fn entries(reply: &Value) -> Vec<Value> {
    let v: Value = match &reply["value"] {
        Value::String(t) => serde_json::from_str(t).unwrap_or_default(),
        other => other.clone(),
    };
    v["files"].as_array().cloned().unwrap_or_default()
}

/// When you last opened it (OneDrive: the user relationship's last
/// access, else the client access recorded in your mailbox).
pub fn opened(entry: &Value) -> String {
    let x = &entry["file"];
    first(&[
        &x["UserRelationship"]["LastAccessDateTime"],
        &x["ItemProperties"]["ClientAccessByMailboxOwner"]["LastAccessDateTime"],
    ])
}

/// A real GUID (OneDrive's check of SharePoint ids).
fn guid(v: &Value) -> bool {
    v.as_str()
        .is_some_and(|g| !g.is_empty() && g != "00000000-0000-0000-0000-000000000000")
}

fn is_notebook(x: &Value) -> bool {
    x["ItemProperties"]["Default"]["ProgID"].as_str() == Some("OneNote.Notebook")
        || x["FileExtension"].as_str() == Some("note")
}

/// Why OneDrive's Home leaves an entry out (`isInvalidOdbRecentItem`,
/// with `isInvalidRecentItem` and `isInvalidODBItem`), None when it is
/// listed.
pub fn left_out(entry: &Value) -> Option<&'static str> {
    let x = &entry["file"];
    let kind = x["Visualization"]["Type"].as_str().unwrap_or_default();
    let facet = x["SharePointOnlineFacetStatus"]
        .as_str()
        .unwrap_or_default();
    let hidden = x["IsHidden"]
        .as_bool()
        .or_else(|| x["ItemProperties"]["AggregatedActivities"]["IsHidden"].as_bool())
        .unwrap_or(false);
    if hidden {
        return Some("hidden");
    }
    // A deleted file stays behind as an empty copy (links and attachments
    // whose file is gone are not counted as deleted).
    let deleted = x["IsDeleted"].as_bool().unwrap_or_else(|| {
        let link = matches!(
            x["StorageProviderContext"].as_u64().unwrap_or(0),
            5 | 6 | 8 | 9 | 11 | 12
        );
        let gone = facet == "NotPresent" || facet == "Partial";
        !(gone && link) && x["IsEmptyCopy"].as_bool().unwrap_or(false)
    });
    if deleted {
        return Some("deleted");
    }
    if !facet.is_empty() && facet != "Present" {
        return Some("NotPresent");
    }
    if opened(entry).is_empty() {
        return Some("NotOpened");
    }
    if kind == "Folder" && !is_notebook(x) {
        return Some("Folder");
    }
    if kind == "Image" {
        return Some("Image");
    }
    if s(&x["SubstrateContentDomainId"]).is_empty()
        && kind != "GenericList"
        && kind != "Playlist"
        && !sp_ids(x)
    {
        return Some("ClassicAttachment");
    }
    let source = x["Source"].as_str().unwrap_or_default();
    if !source.is_empty() && source != "SharePoint" && source != "OneDriveForBusiness" {
        return Some("Source");
    }
    invalid_odb(x)
}

/// A real GUID for each of SharePoint's ids (OneDrive's check).
pub(crate) fn sp_ids(x: &Value) -> bool {
    let sp = &x["SharePointItem"];
    guid(&sp["SiteId"]) && guid(&sp["WebId"]) && guid(&sp["ListId"]) && guid(&sp["UniqueId"])
}

/// OneDrive's `isInvalidODBItem` over an entry's `file`: why a OneDrive
/// for work list leaves it out, None when it may be listed.
pub(crate) fn invalid_odb(x: &Value) -> Option<&'static str> {
    let kind = x["Visualization"]["Type"].as_str().unwrap_or_default();
    let scd = s(&x["SubstrateContentDomainId"]);
    let ids = sp_ids(x);
    if s(&x["Visualization"]["Title"]).is_empty() {
        return Some("Missing Title property");
    }
    let container = s(&x["Visualization"]["ContainerUrl"]);
    if container
        .split('/')
        .skip(3)
        .take(2)
        .any(|seg| seg.eq_ignore_ascii_case("contentstorage"))
    {
        return Some("RaasFile");
    }
    if x["ItemProperties"]["Default"]["BaseType"].as_str() == Some("GenericList")
        && kind == "Folder"
    {
        return Some("BadListType");
    }
    let scd_item = match x["IsSCDItem"].as_bool() {
        Some(b) => b && !scd.is_empty(),
        None => !scd.is_empty() && !ids,
    };
    if scd_item {
        let app = s(&x["ContentSourceApplication"]);
        let sem = &x["ItemProperties"]["SemanticProperties"];
        let complete = ["Title", "Url", "IconUrl"]
            .iter()
            .all(|k| !s(&sem[*k]).is_empty());
        if !app.is_empty() && app != "App.SCD.Microsoft.PowerBI" || !complete {
            return Some("UnsupportedFileType");
        }
    }
    let ext = x["FileExtension"]
        .as_str()
        .unwrap_or_default()
        .to_ascii_lowercase();
    if ["ics", "eml", "aspx"].contains(&ext.as_str()) {
        return Some("UnsupportedFileType");
    }
    None
}

/// OneDrive's icon for an activity type (its ActivityType enum mapped to
/// glyphs), as OST's Activity column names them.
fn activity_kind(t: u64) -> &'static str {
    match t {
        4 | 5 | 16 | 17 => "edit",
        6 | 7 | 18 | 19 => "comment",
        8 | 13 | 15 => "commentResponse",
        9 => "share",
        11 | 12 | 20 | 21 | 26 | 27 => "mention",
        28..=35 => "createTask",
        _ => "",
    }
}

fn activity(entry: &Value) -> Option<Activity> {
    let a = &entry["activity"];
    let format = s(&a["message_format"]);
    // Home never shows "You recently opened this" (RecentlyOpen).
    let t = a["type"].as_u64().unwrap_or(0);
    if format.is_empty() || t == 2 {
        return None;
    }
    let users: Vec<String> = a["users"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|u| s(&u["display_name"]))
        .collect();
    let mut text = format.clone();
    for (i, u) in users.iter().enumerate() {
        text = text.replace(&format!("{{{i}}}"), u);
    }
    Some(Activity {
        kind: activity_kind(t).into(),
        text,
        format,
        user: users.first().cloned().unwrap_or_default(),
        time: s(&a["timestamp"]),
    })
}

/// OneDrive's place line: a OneDrive's files are "My Files" (yours) or
/// "{0}'s Files"; a site's, its title.
fn location(x: &Value, personal: &str) -> String {
    let title = s(&x["Visualization"]["ContainerTitle"]);
    let site = s(&x["SharePointItem"]["SitePath"]);
    let trim = |u: &str| u.trim_end_matches('/').to_ascii_lowercase();
    if !personal.is_empty() && trim(&site) == trim(personal) {
        "My Files".into()
    } else if site.contains("/personal/") && !title.is_empty() {
        format!("{title}'s Files")
    } else {
        title
    }
}

/// One listed entry; `personal` is your OneDrive's site.
pub fn parse(entry: &Value, personal: &str) -> Recent {
    let x = &entry["file"];
    let sp = &x["SharePointItem"];
    let name = s(&x["FileName"]);
    let notebook = is_notebook(x);
    let ext = s(&x["FileExtension"]).to_ascii_lowercase();
    let folder = x["Visualization"]["Type"].as_str() == Some("Folder");
    // OneDrive's name: a folder's name, a file's name without its
    // extension, else the title.
    let title = if folder {
        name.clone()
    } else {
        match name.rsplit_once('.') {
            Some((stem, e)) if !ext.is_empty() && e.eq_ignore_ascii_case(&ext) => stem.to_string(),
            _ => first(&[&x["Visualization"]["Title"], &x["FileName"]]),
        }
    };
    let web_url = first(&[
        &sp["FileUrl"],
        &x["ItemProperties"]["Default"]["DocumentLink"],
    ]);
    Recent {
        title,
        kind: if notebook { "one".into() } else { ext },
        notebook,
        open_url: first(&[
            &x["Visualization"]["AccessUrl"],
            &x["ItemProperties"]["SemanticProperties"]["Url"],
            &sp["FileUrl"],
        ]),
        web_url,
        location: location(x, personal),
        opened: opened(entry),
        owner: s(&x["Document"]["Author"]),
        size: x["FileSize"].as_u64().unwrap_or(0),
        modified: s(&x["FileModifiedTime"]),
        modified_by: s(&sp["ModifiedByDisplayName"]),
        activity: activity(entry),
        site_url: s(&sp["SitePath"]),
        site_id: s(&sp["SiteId"]),
        web_id: s(&sp["WebId"]),
        list_id: s(&sp["ListId"]),
        list_item_id: s(&sp["ListItemId"]),
        unique_id: s(&sp["UniqueId"]),
        name,
    }
}

/// The listed files of a reply, newest opened first.
pub fn listed(reply: &Value, personal: &str) -> Vec<Recent> {
    let mut rows: Vec<Recent> = entries(reply)
        .iter()
        .filter(|e| left_out(e).is_none())
        .map(|e| parse(e, personal))
        .collect();
    // ISO times in UTC sort as text; parse anyway for odd offsets.
    let key = |r: &Recent| {
        chrono::DateTime::parse_from_rfc3339(&r.opened)
            .map(|t| t.timestamp_millis())
            .unwrap_or(0)
    };
    rows.sort_by_key(|r| std::cmp::Reverse(key(r)));
    rows
}

/// Your OneDrive's recent files service's reply, and your OneDrive's
/// site.
pub async fn fetch_reply(client: &TeamsClient) -> Result<(Value, String)> {
    let personal = super::quick_access::personal_site(client).await?;
    let reply = sharing::get_with(
        &format!("{personal}/_api/sp.RecentFileCollection.DeltaSync?top=500"),
        &[("accept", "application/json")],
    )
    .await
    .context("Recent files")?;
    Ok((reply, personal))
}

/// Your recent files from your OneDrive's recent files service.
pub async fn fetch(client: &TeamsClient) -> Result<Vec<Recent>> {
    let (reply, personal) = fetch_reply(client).await?;
    Ok(listed(&reply, &personal))
}

/// Graph's path to a recent file's drive item (by its SharePoint ids).
pub fn graph_path(r: &Recent) -> Option<String> {
    let host = r.site_url.split('/').nth(2).filter(|h| !h.is_empty())?;
    let ok = |id: &str| {
        !id.is_empty() && id.len() <= 64 && id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-')
    };
    let item_ok = !r.list_item_id.is_empty() && r.list_item_id.bytes().all(|b| b.is_ascii_digit());
    let host_ok = host
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b".-".contains(&b));
    if !(ok(&r.site_id) && ok(&r.web_id) && ok(&r.list_id) && item_ok && host_ok) {
        return None;
    }
    Some(format!(
        "/sites/{host},{},{}/lists/{}/items/{}/driveItem",
        r.site_id, r.web_id, r.list_id, r.list_item_id
    ))
}

/// A recent file as the OneDrive app's rows take it, from Graph's item
/// when there is one (its ids serve the row's actions), with the recent
/// service's name, kind and addresses.
pub fn drive_item(r: &Recent, graph: Option<DriveItem>) -> DriveItem {
    let mut it = graph.unwrap_or_else(|| DriveItem {
        // Without Graph's ids: SharePoint's unique id keeps rows apart.
        id: r.unique_id.clone(),
        size: r.size,
        modified: r.modified.clone(),
        modified_by: r.modified_by.clone(),
        sharing: "Private".into(),
        ..Default::default()
    });
    it.name = r.name.clone();
    it.kind = r.kind.clone();
    // A notebook opens in OneNote, not as a folder.
    if r.notebook {
        it.is_folder = false;
        it.child_count = 0;
    }
    if r.notebook || it.web_url.is_empty() {
        it.web_url = r.open_url.clone();
    }
    it.sp_site = r.site_url.clone();
    it.sp_list = r.list_id.clone();
    it.sp_item = r.unique_id.clone();
    it
}

/// Graph's items for these files, in one `$batch` per 20 (None where
/// Graph has none).
pub async fn graph_items(client: &TeamsClient, files: &[Recent]) -> Vec<Option<DriveItem>> {
    let mut out: Vec<Option<DriveItem>> = vec![None; files.len()];
    let paths: Vec<(usize, String)> = files
        .iter()
        .enumerate()
        .filter_map(|(i, r)| graph_path(r).map(|p| (i, p)))
        .collect();
    for chunk in paths.chunks(20) {
        let body = json!({ "requests": chunk.iter().map(|(i, p)| json!({
            "id": i.to_string(),
            "method": "GET",
            "url": format!("{p}?{}", super::drive::SELECT),
        })).collect::<Vec<_>>() });
        let reply: Value = match client.graph_post("/$batch", &body).await {
            Ok(r) => r.json().await.unwrap_or_default(),
            Err(e) => {
                tracing::warn!("Recent files' items: {e:#}");
                continue;
            }
        };
        for r in reply["responses"].as_array().into_iter().flatten() {
            let Some(i) = r["id"].as_str().and_then(|i| i.parse::<usize>().ok()) else {
                continue;
            };
            if r["status"].as_u64() == Some(200) && i < out.len() {
                out[i] = super::drive::parse_item(&r["body"]);
            }
        }
    }
    out
}

/// The OneDrive app's Home rows: its recent files as drive items, with
/// Opened, Owner and Activity as Teams shows them.
pub fn home_row(r: &Recent, item: &DriveItem, now: chrono::DateTime<chrono::Local>) -> Value {
    use super::list_rows::{activity_time, decorate};
    let local = |t: &str| {
        chrono::DateTime::parse_from_rfc3339(t)
            .ok()
            .map(|t| t.with_timezone(&chrono::Local))
    };
    let mut v = decorate(item, None, now);
    v["title"] = json!(r.title);
    v["location"] = json!(r.location);
    v["owner"] = json!(r.owner);
    if let Some(t) = local(&r.opened) {
        v["modified_text"] = json!(activity_time(t, now));
        v["modified_title"] = json!(t.format("%-m/%-d/%Y %-I:%M %p").to_string());
    }
    if let Some(a) = &r.activity {
        v["activity"] = json!({
            "kind": a.kind,
            "text": a.text,
            "time": local(&a.time).map(|t| activity_day(t, now)).unwrap_or_default(),
        });
    }
    v
}

/// The Activity column's day on Home ("Mon", "Nov 17"): today and
/// yesterday as OneDrive words them, this week by weekday, then the date.
pub fn activity_day(
    t: chrono::DateTime<chrono::Local>,
    now: chrono::DateTime<chrono::Local>,
) -> String {
    let (day, today) = (t.date_naive(), now.date_naive());
    let days = (today - day).num_days();
    if days <= 0 {
        return super::list_rows::activity_time(t, now);
    }
    if days == 1 {
        return "Yesterday".into();
    }
    if days <= 6 {
        return t.format("%a").to_string();
    }
    if t.format("%Y").to_string() == now.format("%Y").to_string() {
        t.format("%b %-d").to_string()
    } else {
        t.format("%b %-d, %Y").to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ME: &str =
        "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com";

    /// Entries cut from ost-test1's DeltaSync reply (captured on winpc
    /// 2026-11-25), each with what Teams' Home did with it.
    fn reply() -> Value {
        let sp = |site: &str, id: &str| {
            json!({
            "SiteId": "86beb970-8c88-4ae2-acce-d51c851ec061", "WebId": "a3305c60-5edd-4721-8f56-1352f4b64bcf",
            "ListId": "c300f6d2-5ee5-4f38-a11c-6a78cbe2bf1d", "UniqueId": id, "ListItemId": "20",
            "SitePath": site, "FileUrl": format!("{site}/Documents/f"), "ModifiedByDisplayName": "OST Test 3" })
        };
        let me = "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com";
        let files = json!({ "files": [
            // Shown: opened, shared in a chat.
            { "file": { "FileName": "0.2.0 release checklist.loop", "FileExtension": "loop", "SharePointOnlineFacetStatus": "Present",
                        "IsEmptyCopy": false, "StorageProviderContext": 11, "FileSize": 1354,
                        "SharePointItem": sp("https://scnetsolutions-my.sharepoint.com/personal/ost-test3_scnetsolutions_com", "d9840407-cd62-416f-b275-829111b2ccd7"),
                        "ItemProperties": { "AggregatedActivities": { "IsHidden": false } },
                        "UserRelationship": { "LastAccessDateTime": "2026-11-25T15:31:45Z" },
                        "Visualization": { "Title": "0.2.0 release checklist", "Type": "Fluid", "ContainerTitle": "OST Test 3", "AccessUrl": "https://loop.cloud.microsoft/p/x" },
                        "Document": { "Author": "OST Test 3" } },
              "activity": { "message_format": "{0} shared this in a Teams chat", "type": 9, "users": [{ "display_name": "OST Test 3" }], "timestamp": "2026-11-23T15:11:17Z" } },
            // Left out: opened, but its file is only partly there.
            { "file": { "FileName": "OST TEST frmY Y1 1.loop", "FileExtension": "loop", "SharePointOnlineFacetStatus": "Partial",
                        "SharePointItem": sp(me, "aaaaaaaa-cd62-416f-b275-829111b2ccd7"),
                        "UserRelationship": { "LastAccessDateTime": "2026-11-24T13:09:31Z" },
                        "Visualization": { "Title": "OST TEST frmY Y1 1", "Type": "Fluid" } },
              "activity": { "message_format": "You recently opened this", "type": 2 } },
            // Left out: a recording never opened.
            { "file": { "FileName": "OST TEST 73 sync-20261121_054413UTC-Meeting Recording.mp4", "FileExtension": "mp4",
                        "SharePointOnlineFacetStatus": "Present", "SharePointItem": sp(me, "bbbbbbbb-cd62-416f-b275-829111b2ccd7"),
                        "Visualization": { "Title": "OST TEST 73 sync", "Type": "Video" } },
              "activity": { "message_format": "You recorded a meeting", "type": 9 } },
            // Shown: a notebook (a folder), opened by the client.
            { "file": { "FileName": "OST Notebook", "SharePointOnlineFacetStatus": "Present", "SharePointItem": sp(me, "cccccccc-cd62-416f-b275-829111b2ccd7"),
                        "ItemProperties": { "Default": { "ProgID": "OneNote.Notebook" }, "ClientAccessByMailboxOwner": { "LastAccessDateTime": "2026-11-16T16:21:37Z" } },
                        "Visualization": { "Title": "OST Notebook", "Type": "Folder", "ContainerTitle": "OST Test 1",
                                           "AccessUrl": format!("{me}/_layouts/15/Doc.aspx?sourcedoc=%7BCF5E%7D") },
                        "Document": { "Author": "OST Test 1" } } },
            // Left out: a plain folder.
            { "file": { "FileName": "Attachments", "SharePointOnlineFacetStatus": "Present", "SharePointItem": sp(me, "dddddddd-cd62-416f-b275-829111b2ccd7"),
                        "UserRelationship": { "LastAccessDateTime": "2026-11-20T16:43:00Z" },
                        "Visualization": { "Title": "Attachments", "Type": "Folder" } } },
            // Shown: you opened it later than the notebook; "recently
            // opened" is no Activity.
            { "file": { "FileName": "ost-share-test.txt", "FileExtension": "txt", "SharePointOnlineFacetStatus": "Present",
                        "SharePointItem": sp(me, "eeeeeeee-cd62-416f-b275-829111b2ccd7"),
                        "UserRelationship": { "LastAccessDateTime": "2026-11-20T07:16:31Z" },
                        "Visualization": { "Title": "ost-share-test", "Type": "Text", "ContainerTitle": "OST Test 1" },
                        "Document": { "Author": "OST Test 1" } },
              "activity": { "message_format": "You recently opened this", "type": 2, "timestamp": "2026-11-20T07:16:31Z" } },
            // Left out: hidden.
            { "file": { "FileName": "hidden.docx", "FileExtension": "docx", "SharePointItem": sp(me, "ffffffff-cd62-416f-b275-829111b2ccd7"),
                        "ItemProperties": { "AggregatedActivities": { "IsHidden": true } },
                        "UserRelationship": { "LastAccessDateTime": "2026-11-25T00:00:00Z" },
                        "Visualization": { "Title": "hidden", "Type": "Word" } } },
            // Left out: a photo.
            { "file": { "FileName": "p.png", "FileExtension": "png", "SharePointItem": sp(me, "11111111-cd62-416f-b275-829111b2ccd7"),
                        "UserRelationship": { "LastAccessDateTime": "2026-11-25T00:00:00Z" },
                        "Visualization": { "Title": "p", "Type": "Image" } } },
            // Left out: an attachment without SharePoint ids.
            { "file": { "FileName": "a.docx", "FileExtension": "docx",
                        "UserRelationship": { "LastAccessDateTime": "2026-11-25T00:00:00Z" },
                        "Visualization": { "Title": "a", "Type": "Word" } } }
        ] });
        json!({ "value": files.to_string() })
    }

    #[test]
    fn home_lists_what_teams_lists_in_its_order() {
        let rows = listed(&reply(), ME);
        assert_eq!(
            rows.iter().map(|r| r.title.as_str()).collect::<Vec<_>>(),
            ["0.2.0 release checklist", "ost-share-test", "OST Notebook"]
        );
        let why: Vec<_> = entries(&reply()).iter().map(left_out).collect();
        assert_eq!(
            why,
            [
                None,
                Some("NotPresent"),
                Some("NotOpened"),
                None,
                Some("Folder"),
                None,
                Some("hidden"),
                Some("Image"),
                Some("ClassicAttachment")
            ]
        );
    }

    #[test]
    fn rows_carry_teams_columns() {
        let rows = listed(&reply(), ME);
        let (loop_, txt, nb) = (&rows[0], &rows[1], &rows[2]);
        assert_eq!(loop_.owner, "OST Test 3");
        assert_eq!(loop_.location, "OST Test 3's Files");
        assert_eq!(txt.location, "My Files");
        let a = loop_.activity.as_ref().unwrap();
        assert_eq!(
            (a.kind.as_str(), a.text.as_str()),
            ("share", "OST Test 3 shared this in a Teams chat")
        );
        assert!(txt.activity.is_none());
        assert_eq!(
            (txt.name.as_str(), txt.kind.as_str()),
            ("ost-share-test.txt", "txt")
        );
        // The notebook opens in OneNote, from the client's access time.
        assert!(nb.notebook);
        assert_eq!(nb.kind, "one");
        assert_eq!(nb.opened, "2026-11-16T16:21:37Z");
        let it = drive_item(nb, None);
        assert!(!it.is_folder);
        assert!(it.web_url.contains("Doc.aspx"));
        assert_eq!(it.sp_item, "cccccccc-cd62-416f-b275-829111b2ccd7");
        assert_eq!(
            graph_path(nb).unwrap(),
            "/sites/scnetsolutions-my.sharepoint.com,86beb970-8c88-4ae2-acce-d51c851ec061,a3305c60-5edd-4721-8f56-1352f4b64bcf/lists/c300f6d2-5ee5-4f38-a11c-6a78cbe2bf1d/items/20/driveItem"
        );
    }

    #[test]
    fn graph_paths_take_only_ids() {
        let mut r = listed(&reply(), ME).remove(0);
        r.list_item_id = "20/../x".into();
        assert!(graph_path(&r).is_none());
    }

    #[test]
    fn home_words_times_as_teams() {
        let at = |s: &str| {
            chrono::DateTime::parse_from_rfc3339(s)
                .unwrap()
                .with_timezone(&chrono::Local)
        };
        let now = at("2026-11-25T12:00:00-08:00");
        assert_eq!(activity_day(at("2026-11-23T07:11:17-08:00"), now), "Mon");
        assert_eq!(activity_day(at("2026-11-17T07:11:17-08:00"), now), "Nov 17");
        assert_eq!(
            activity_day(at("2026-11-24T07:11:17-08:00"), now),
            "Yesterday"
        );
    }
}
