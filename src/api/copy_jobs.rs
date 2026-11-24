//! Copy to, Move to and Duplicate as Teams' Files apps do them
//! (docs/spec/file-actions.md): SharePoint's copy jobs on the source's site
//! (`_api/site/CreateCopyJobs`, then `GetCopyJobProgress` until the job is
//! idle), with a token for the site's host.

use std::time::Duration;

use anyhow::{Result, bail};
use serde_json::{Value, json};

use super::sharing::{ItemRef, get, post};

/// SharePoint's NameConflictBehavior: keep both (the new one gets a
/// numbered name), as Teams' Duplicate sends.
const KEEP_BOTH: i64 = 2;
/// How long to wait for a job before giving up.
const JOB_TIMEOUT: Duration = Duration::from_secs(180);

/// The item's own address (`https://host/<FileRef>`), which copy jobs take.
pub async fn absolute_url(item: &ItemRef) -> Result<String> {
    let quote = |s: &str| {
        url::form_urlencoded::byte_serialize(format!("'{}'", s.trim_matches(|c| c == '{' || c == '}')).as_bytes())
            .collect::<String>()
    };
    let reply = get(&format!(
        "{}/_api/web/lists/getbyid(@a1)/GetItemByUniqueId(@a2)?$select=FileRef&@a1={}&@a2={}",
        item.site.trim_end_matches('/'),
        quote(&item.list),
        quote(&item.item)
    ))
    .await?;
    let rel = reply["d"]["FileRef"].as_str().unwrap_or_default();
    if !rel.starts_with('/') {
        bail!("The item's address didn't come back");
    }
    Ok(format!("{}{rel}", host(&item.site)))
}

/// Folder color: OneDrive's code ("0" yellow … "15" light pink) stamped on
/// the folder at `folder_url` (its own address).
pub async fn stamp_color(site: &str, folder_url: &str, code: &str) -> Result<()> {
    if code.parse::<u8>().map_or(true, |n| n > 15) {
        bail!("Not a folder color");
    }
    let path = folder_url.get(host(folder_url).len()..).unwrap_or_default();
    let q: String = url::form_urlencoded::byte_serialize(format!("'{}'", path.replace('\'', "''")).as_bytes()).collect();
    post(
        &format!("{}/_api/foldercoloring/stampcolor(DecodedUrl=@a1)?@a1={q}", site.trim_end_matches('/')),
        &json!({ "coloringInformation": { "__metadata": { "type": "SP.FolderColoringInformation" }, "ColorHex": code } }),
    )
    .await?;
    Ok(())
}

/// A site's and web's ids (`_api/site/id`, `_api/web/id`).
pub async fn site_ids(site: &str) -> Result<(String, String)> {
    let site = site.trim_end_matches('/');
    let (a, b) = (format!("{site}/_api/site/id"), format!("{site}/_api/web/id"));
    let (x, y) = tokio::join!(get(&a), get(&b));
    let id = |v: Result<Value>| v.ok().and_then(|v| v["d"]["Id"].as_str().map(str::to_string)).unwrap_or_default();
    Ok((id(x), id(y)))
}

/// Where Add shortcut puts the shortcut: OneDrive's Shortcuts, your My
/// files, or a folder (`drive`, its unique id; empty for the drive's top)
/// on a site.
pub enum ShortcutPlace {
    Shortcuts,
    MyFiles,
    Folder { site: String, drive: String, folder: String },
}

/// The body OneDrive's Add shortcut posts (its "Stasher").
pub fn shortcut_body(name: &str, item: &ItemRef, site_id: &str, web_id: &str) -> Value {
    json!({
        "name": name,
        "remoteItem": { "sharepointIds": {
            "listId": item.list.trim_matches(|c| c == '{' || c == '}'),
            "listItemUniqueId": item.item.trim_matches(|c| c == '{' || c == '}'),
            "siteId": site_id, "siteUrl": item.site.trim_end_matches('/'), "webId": web_id,
        }},
        "file": {},
        "@microsoft.graph.conflictBehavior": "rename",
    })
}

/// Add shortcut: `personal` is your OneDrive's host (`https://x-my…`).
pub async fn add_shortcut(item: &ItemRef, name: &str, personal: &str, place: &ShortcutPlace) -> Result<()> {
    let ok = |s: &str| s.bytes().all(|b| b.is_ascii_alphanumeric() || b"!-_.".contains(&b));
    let url = match place {
        ShortcutPlace::Shortcuts => format!("{}/_api/v2.1/drives/me/special/shortcuts/children", host(personal)),
        ShortcutPlace::MyFiles => format!("{}/_api/v2.1/drives/me/items/root/children", host(personal)),
        ShortcutPlace::Folder { site, drive, folder } => {
            let f = folder.trim_matches(|c| c == '{' || c == '}');
            if !ok(drive) || !(f.is_empty() || f.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-')) {
                bail!("Not a folder");
            }
            let target = if f.is_empty() { "root".to_string() } else { format!("{{{f}}}") };
            format!("{}/_api/v2.1/drives/{drive}/items/{target}/children", host(site))
        }
    };
    let (site_id, web_id) = site_ids(&item.site).await?;
    super::sharing::post_with(&url, &shortcut_body(name, item, &site_id, &web_id), &[("accept", "application/json"), ("content-type", "application/json")])
        .await
        .map_err(sp_message)?;
    Ok(())
}

/// `https://host` of an address.
fn host(url: &str) -> String {
    url.split('/').take(3).collect::<Vec<_>>().join("/")
}

/// A folder address as copy jobs take it: Graph's webUrl, decoded.
pub fn folder_url(web_url: &str) -> String {
    percent_decode(web_url.trim_end_matches('/'))
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Some(v) = std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Duplicate's name: "<stem> Copy.<ext>" ("ost-share-test Copy.txt"; a
/// folder "Notes Copy").
pub fn duplicate_name(name: &str, is_folder: bool) -> String {
    match name.rfind('.').filter(|&i| i > 0 && !is_folder) {
        Some(i) => format!("{} Copy{}", &name[..i], &name[i..]),
        None => format!("{name} Copy"),
    }
}

/// The body of CreateCopyJobs, as Teams sends it (Duplicate, 2026-11-11);
/// a move sets IsMoveMode and keeps the version history. `names` renames
/// the items, in order (Duplicate).
pub fn create_body(sources: &[String], dest: &str, move_mode: bool, names: &[String]) -> Value {
    let mut options = json!({
        "IgnoreVersionHistory": !move_mode,
        "AllowSchemaMismatch": true,
        "BypassSharedLock": true,
        "SameWebCopyMoveOptimization": true,
        "NameConflictBehavior": KEEP_BOTH,
    });
    if move_mode {
        options["IsMoveMode"] = json!(true);
    }
    if !names.is_empty() {
        options["CustomizedItemName"] = json!({ "results": names });
    }
    json!({ "exportObjectUris": sources, "destinationUri": dest, "options": options })
}

/// The errors in a GetCopyJobProgress reply's logs (each log line is a
/// JSON object; failures are JobError / JobFatalError events).
pub fn job_errors(reply: &Value) -> Vec<String> {
    reply["d"]["GetCopyJobProgress"]["Logs"]["results"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|l| serde_json::from_str::<Value>(l.as_str()?).ok())
        .filter(|e| matches!(e["Event"].as_str(), Some("JobError" | "JobFatalError")))
        .map(|e| e["Message"].as_str().unwrap_or("The job failed").to_string())
        .collect()
}

/// Copy (or move) items into a folder and wait for SharePoint to finish.
/// `site` is the sources' site; `names` renames them (Duplicate).
pub async fn run(site: &str, sources: &[String], dest: &str, move_mode: bool, names: &[String]) -> Result<()> {
    let site = site.trim_end_matches('/');
    let reply = post(&format!("{site}/_api/site/CreateCopyJobs"), &create_body(sources, dest, move_mode, names))
        .await
        .map_err(sp_message)?;
    let jobs = reply["d"]["CreateCopyJobs"]["results"].as_array().cloned().unwrap_or_default();
    if jobs.is_empty() {
        bail!("SharePoint didn't start the copy");
    }
    let started = std::time::Instant::now();
    for job in jobs {
        let mut info = json!({ "__metadata": { "type": "SP.CopyMigrationInfo" } });
        for k in ["EncryptionKey", "JobId", "JobQueueUri"] {
            info[k] = job[k].clone();
        }
        loop {
            tokio::time::sleep(Duration::from_millis(700)).await;
            let p = post(&format!("{site}/_api/site/GetCopyJobProgress"), &json!({ "copyJobInfo": info }))
                .await
                .map_err(sp_message)?;
            if let Some(e) = job_errors(&p).into_iter().next() {
                bail!(e);
            }
            // JobState 0: done (4 while it runs).
            if p["d"]["GetCopyJobProgress"]["JobState"].as_i64() == Some(0) {
                break;
            }
            if started.elapsed() > JOB_TIMEOUT {
                bail!("SharePoint is still working on it");
            }
        }
    }
    Ok(())
}

/// SharePoint's own message, as Teams shows it under "1 item wasn't
/// copied" (without OST's "SharePoint 500:" prefix).
fn sp_message(e: anyhow::Error) -> anyhow::Error {
    let t = e.to_string();
    match t.strip_prefix("SharePoint ").and_then(|r| r.split_once(": ")) {
        Some((_, msg)) => anyhow::anyhow!(msg.to_string()),
        None => e,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shortcut_bodies_are_onedrives() {
        let it = ItemRef { site: "https://x-my.sharepoint.com/personal/a/".into(), list: "{0E0A}".into(), item: "1dd3".into() };
        assert_eq!(shortcut_body("ost-share-test", &it, "S", "W"), json!({"name":"ost-share-test","remoteItem":{"sharepointIds":{"listId":"0E0A","listItemUniqueId":"1dd3","siteId":"S","siteUrl":"https://x-my.sharepoint.com/personal/a","webId":"W"}},"file":{},"@microsoft.graph.conflictBehavior":"rename"}));
    }

    #[test]
    fn duplicate_names_follow_onedrive() {
        assert_eq!(duplicate_name("ost-share-test.txt", false), "ost-share-test Copy.txt");
        assert_eq!(duplicate_name("Notes.v2", true), "Notes.v2 Copy");
        assert_eq!(duplicate_name(".env", false), ".env Copy");
        assert_eq!(duplicate_name("README", false), "README Copy");
    }

    #[test]
    fn bodies_are_teams_bodies() {
        // Teams' Duplicate of ost-share-test.txt (2026-11-11).
        let b = create_body(
            &["https://x-my.sharepoint.com/personal/a/Documents/ost-share-test.txt".into()],
            "https://x-my.sharepoint.com/personal/a/Documents",
            false,
            &["ost-share-test Copy.txt".into()],
        );
        assert_eq!(
            b,
            json!({"exportObjectUris":["https://x-my.sharepoint.com/personal/a/Documents/ost-share-test.txt"],
                   "destinationUri":"https://x-my.sharepoint.com/personal/a/Documents",
                   "options":{"IgnoreVersionHistory":true,"AllowSchemaMismatch":true,"BypassSharedLock":true,
                              "SameWebCopyMoveOptimization":true,"NameConflictBehavior":2,
                              "CustomizedItemName":{"results":["ost-share-test Copy.txt"]}}})
        );
        let m = create_body(&["s".into()], "d", true, &[]);
        assert_eq!((m["options"]["IsMoveMode"].as_bool(), m["options"]["IgnoreVersionHistory"].as_bool()), (Some(true), Some(false)));
        assert!(m["options"].get("CustomizedItemName").is_none());
    }

    #[test]
    fn progress_errors_come_from_the_logs() {
        let reply = json!({"d": {"GetCopyJobProgress": {"JobState": 0, "Logs": {"results": [
            "{\"Event\": \"JobQueued\", \"JobId\": \"a\"}",
            "{\"Event\": \"JobError\", \"Message\": \"A file with this name already exists.\"}",
        ]}}}});
        assert_eq!(job_errors(&reply), ["A file with this name already exists."]);
        assert!(job_errors(&json!({})).is_empty());
    }

    #[test]
    fn folder_urls_are_decoded() {
        assert_eq!(
            folder_url("https://x-my.sharepoint.com/personal/a/Documents/Microsoft%20Teams%20Chat%20Files/"),
            "https://x-my.sharepoint.com/personal/a/Documents/Microsoft Teams Chat Files"
        );
        assert_eq!(folder_url("https://x/a%2"), "https://x/a%2");
    }
}
