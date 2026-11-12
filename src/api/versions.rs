//! A file's Version history as Teams' Files apps show it
//! (docs/spec/version-history.md): SharePoint's list item versions, and
//! its RestoreByLabel and RecycleByLabel.

use anyhow::{Result, bail};
use chrono::{Local, NaiveDateTime, TimeZone, Utc};
use serde::Serialize;
use serde_json::{Value, json};

use super::sharing::{get, post};

/// One version, as the dialog lists it.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Version {
    /// "3.0".
    pub label: String,
    /// "11/11/2026 10:28 PM" (local time).
    pub modified: String,
    /// "56 bytes".
    pub size: String,
    pub by: String,
    pub by_email: String,
    /// Filled in from the directory, for the picture.
    pub by_oid: String,
    /// Where Open File goes: the old version's address, or the file's own.
    pub url: String,
    pub current: bool,
}

fn quote(s: &str) -> String {
    url::form_urlencoded::byte_serialize(format!("'{}'", s.replace('\'', "''")).as_bytes()).collect()
}

/// `https://host/a/b` into (`https://host`, `/a/b`).
fn split(url: &str) -> Result<(String, String)> {
    let host: String = url.split('/').take(3).collect::<Vec<_>>().join("/");
    let path = url.get(host.len()..).unwrap_or_default().to_string();
    if !host.starts_with("https://") || !path.starts_with('/') {
        bail!("Not a SharePoint address: {url}");
    }
    Ok((host, path))
}

/// The versions of the file at `file_url` (its own address, as
/// `copy_jobs::absolute_url` gives it); `site` is its site.
pub async fn list(site: &str, file_url: &str) -> Result<Vec<Version>> {
    let (_, path) = split(file_url)?;
    let url = format!(
        "{}/_api/web/GetListItemUsingPath(decodedUrl=@a1)/versions?@a1={}&$select=VersionId,VersionLabel,Created,CreatedBy/Title,CreatedBy/Email,FileVersion/Url,FileVersion/Length,SMTotalFileStreamSize,IsCurrentVersion&$expand=CreatedBy,FileVersion&$top=5000",
        site.trim_end_matches('/'),
        quote(&path)
    );
    Ok(parse(&get(&url).await?, site, file_url))
}

/// The versions reply, newest first as SharePoint gives it.
pub fn parse(reply: &Value, site: &str, file_url: &str) -> Vec<Version> {
    let s = |v: &Value| v.as_str().unwrap_or_default().to_string();
    reply["d"]["results"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|v| {
            let current = v["IsCurrentVersion"].as_bool().unwrap_or(false);
            let rel = s(&v["FileVersion"]["Url"]);
            let bytes: f64 = [&v["SMTotalFileStreamSize"], &v["FileVersion"]["Length"]]
                .iter()
                .find_map(|x| x.as_str().and_then(|n| n.parse().ok()).or(x.as_f64()))
                .unwrap_or(0.0);
            Version {
                label: s(&v["VersionLabel"]),
                modified: NaiveDateTime::parse_from_str(&s(&v["Created"]), "%Y-%m-%dT%H:%M:%S")
                    .map(|t| Utc.from_utc_datetime(&t).with_timezone(&Local).format("%-m/%-d/%Y %-I:%M %p").to_string())
                    .unwrap_or_default(),
                size: super::list_rows::size_text(bytes),
                by: s(&v["CreatedBy"]["Title"]),
                by_email: s(&v["CreatedBy"]["Email"]),
                by_oid: String::new(),
                url: if current || rel.is_empty() { file_url.to_string() } else { format!("{}/{rel}", site.trim_end_matches('/')) },
                current,
            }
        })
        .collect()
}

/// Restore (as a new version) or delete (to the recycle bin) one version.
pub async fn act(site: &str, file_url: &str, label: &str, restore: bool) -> Result<()> {
    let (_, path) = split(file_url)?;
    let url = format!(
        "{}/_api/web/GetFileByServerRelativePath(decodedUrl=@a1)/versions/{}(versionLabel=@a2)?@a1={}&@a2={}",
        site.trim_end_matches('/'),
        if restore { "RestoreByLabel" } else { "RecycleByLabel" },
        quote(&path),
        quote(label)
    );
    post(&url, &json!({})).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_parse_as_teams_lists_them() {
        // ost-share-test.txt's reply on 2026-11-12 (cut down).
        let reply = json!({"d": {"results": [
            {"CreatedBy": {"Title": "OST Test 1", "Email": "ost-test1@x.com"}, "FileVersion": {"__deferred": {}},
             "Created": "2026-11-12T06:28:11", "IsCurrentVersion": true, "VersionLabel": "3.0", "SMTotalFileStreamSize": "56"},
            {"CreatedBy": {"Title": "OST Test 1", "Email": "ost-test1@x.com"},
             "FileVersion": {"Length": "56", "Url": "_vti_history/1024/Documents/ost-share-test.txt"},
             "Created": "2026-11-12T05:57:40", "IsCurrentVersion": false, "VersionLabel": "2.0", "SMTotalFileStreamSize": "56"}
        ]}});
        let site = "https://x-my.sharepoint.com/personal/a";
        let file = "https://x-my.sharepoint.com/personal/a/Documents/ost-share-test.txt";
        let v = parse(&reply, site, file);
        assert_eq!(v.len(), 2);
        assert_eq!((v[0].label.as_str(), v[0].size.as_str(), v[0].by.as_str(), v[0].current, v[0].url.as_str()), ("3.0", "56 bytes", "OST Test 1", true, file));
        assert_eq!(v[1].url, "https://x-my.sharepoint.com/personal/a/_vti_history/1024/Documents/ost-share-test.txt");
        let expect = Utc.with_ymd_and_hms(2026, 11, 12, 5, 57, 40).unwrap().with_timezone(&Local).format("%-m/%-d/%Y %-I:%M %p").to_string();
        assert_eq!(v[1].modified, expect);
    }

    #[test]
    fn paths_split_from_addresses() {
        assert_eq!(split("https://h/personal/a/Documents/x y.txt").unwrap(), ("https://h".to_string(), "/personal/a/Documents/x y.txt".to_string()));
        assert!(split("file:///etc/passwd").is_err());
        assert_eq!(quote("/a/it's.txt"), "%27%2Fa%2Fit%27%27s.txt%27");
    }
}
