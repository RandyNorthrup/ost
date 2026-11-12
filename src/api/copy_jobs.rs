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
/// a move sets IsMoveMode and keeps the version history.
pub fn create_body(sources: &[String], dest: &str, move_mode: bool, name: Option<&str>) -> Value {
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
    if let Some(n) = name {
        options["CustomizedItemName"] = json!({ "results": [n] });
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
/// `site` is the source's site; `name` renames the one item (Duplicate).
pub async fn run(site: &str, sources: &[String], dest: &str, move_mode: bool, name: Option<&str>) -> Result<()> {
    let site = site.trim_end_matches('/');
    let reply = post(&format!("{site}/_api/site/CreateCopyJobs"), &create_body(sources, dest, move_mode, name))
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
            Some("ost-share-test Copy.txt"),
        );
        assert_eq!(
            b,
            json!({"exportObjectUris":["https://x-my.sharepoint.com/personal/a/Documents/ost-share-test.txt"],
                   "destinationUri":"https://x-my.sharepoint.com/personal/a/Documents",
                   "options":{"IgnoreVersionHistory":true,"AllowSchemaMismatch":true,"BypassSharedLock":true,
                              "SameWebCopyMoveOptimization":true,"NameConflictBehavior":2,
                              "CustomizedItemName":{"results":["ost-share-test Copy.txt"]}}})
        );
        let m = create_body(&["s".into()], "d", true, None);
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
