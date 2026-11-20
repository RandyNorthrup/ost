//! Stream playlists for a video's "Add to playlist", as Teams' Files app
//! does it (OneDrive's AddToPlaylistFilePicker; captured on winpc
//! 2026-11-19, docs/spec/file-actions.md "Add to playlist").
//!
//! - The picker lists your playlists (personal lists made from the
//!   playlist template) with `SP.PersonalListsProxy.GetPersonalListsProxy`
//!   and the recent ones with `sp.RecentListProxy.GetRecentListsProxy`,
//!   both with `templateTypeId='{TEMPLATE}'` on your OneDrive's host.
//! - New playlist applies the template's list design
//!   (`SiteScriptUtility.ApplyListDesign()`, `store` 1) in your OneDrive:
//!   the list is `{personal}/Lists/{name}`.
//! - Adding a video adds an item to the playlist with
//!   `AddValidateUpdateItemUsingPath()`: its thumbnail, title (the name
//!   without its extension), owner, duration and the video's ids
//!   (`VideoIdentifiers`).

use anyhow::{Context, Result, bail};
use serde::Serialize;
use serde_json::{Value, json};

use super::sharing::{get_with, post};

/// The playlist list template.
pub const TEMPLATE: &str = "3a867b4a-7429-0e1a-b02e-bf4b240ff1ce";

/// A playlist as the picker lists it.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Playlist {
    pub title: String,
    pub id: String,
    /// The list's address ("https://…/personal/me/Lists/Name").
    pub url: String,
    /// The site it lives in.
    pub web: String,
    /// ISO time of the last change (My lists) or visit (Recent lists).
    pub when: String,
}

fn host(url: &str) -> String {
    url.split('/').take(3).collect::<Vec<_>>().join("/")
}

fn s(v: &Value, keys: &[&str]) -> String {
    keys.iter().find_map(|k| v.get(*k).and_then(|x| x.as_str()).filter(|x| !x.is_empty())).unwrap_or_default().to_string()
}

/// The lists in a proxy's answer (plain JSON or OData-verbose), whatever
/// it names its fields.
pub fn parse_lists(v: &Value) -> Vec<Playlist> {
    let arr = v["value"]
        .as_array()
        .or_else(|| v["d"]["results"].as_array())
        .or_else(|| v.as_array())
        .or_else(|| v["Lists"].as_array())
        .or_else(|| v["lists"].as_array())
        .or_else(|| v["d"]["GetPersonalListsProxy"]["results"].as_array())
        .or_else(|| v["d"]["GetRecentListsProxy"]["results"].as_array())
        .cloned()
        .unwrap_or_default();
    arr.iter()
        .map(|l| {
            let url = decode(&s(l, &["ListUrl", "listUrl", "Url", "url", "AbsoluteUrl"]));
            Playlist {
                title: s(l, &["listTitle", "Title", "title", "ListTitle", "Name", "name"]),
                id: s(l, &["ListId", "listId", "Id", "id"]).trim_matches(|c| c == '{' || c == '}').to_string(),
                web: {
                    let w = s(l, &["WebUrl", "webUrl", "SiteUrl", "siteUrl", "WebAbsoluteUrl"]);
                    if w.is_empty() { url.split("/Lists/").next().unwrap_or_default().to_string() } else { w }
                },
                url,
                when: s(l, &["lastviewDateTime", "lastViewDate", "lastModifiedDate", "LastModifiedTime", "lastModifiedDateTime", "Modified"]),
            }
        })
        .filter(|p| !p.title.is_empty())
        .collect()
}

/// Your playlists (My lists).
pub async fn my_lists(personal: &str) -> Result<Vec<Playlist>> {
    let url = format!("{}/_api/SP.PersonalListsProxy.GetPersonalListsProxy?templateTypeId=%27{TEMPLATE}%27", host(personal));
    Ok(parse_lists(&get_with(&url, &[("accept", "application/json")]).await?))
}

/// Playlists you opened lately (Recent lists).
pub async fn recent_lists(personal: &str) -> Result<Vec<Playlist>> {
    let url = format!("{}/_api/sp.RecentListProxy.GetRecentListsProxy?templateTypeId=%27{TEMPLATE}%27", host(personal));
    Ok(parse_lists(&get_with(&url, &[("accept", "application/json")]).await?))
}

/// The list design's runtime parameters, as OneDrive sends them.
pub fn design_body(name: &str, description: &str) -> Value {
    // In OneDrive's order.
    let params = format!(
        r#"{{"Playlist_listName":{},"Playlist_description":{},"Playlist_color":0,"Playlist_addNavLink":false,"Playlist_icon":12}}"#,
        Value::String(name.into()),
        Value::String(description.into())
    );
    json!({"listDesignId": TEMPLATE, "store": 1, "runtimeParameters": params})
}

fn server_relative(url: &str) -> String {
    let h = host(url);
    url.strip_prefix(&h).unwrap_or(url).to_string()
}

fn quoted(s: &str) -> String {
    url::form_urlencoded::byte_serialize(format!("'{}'", s.replace('\'', "''")).as_bytes()).collect()
}

/// New playlist: OneDrive's list design applied in your OneDrive.
pub async fn create(personal: &str, name: &str, description: &str) -> Result<Playlist> {
    let personal = personal.trim_end_matches('/');
    post(&format!("{personal}/_api/Microsoft.Sharepoint.Utilities.WebTemplateExtensions.SiteScriptUtility.ApplyListDesign()"), &design_body(name, description))
        .await
        .context("The playlist wasn't made")?;
    let url = format!("{personal}/Lists/{name}");
    let v = get_with(&format!("{personal}/_api/web/GetList(@a1)?@a1={}&$select=Id,Title,LastItemModifiedDate", quoted(&server_relative(&url))), &[]).await?;
    Ok(Playlist { title: s(&v["d"], &["Title"]), id: s(&v["d"], &["Id"]), url, web: personal.to_string(), when: s(&v["d"], &["LastItemModifiedDate"]) })
}

/// The video's facts the playlist item needs (from Graph).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Video {
    pub drive_id: String,
    pub item_id: String,
    pub name: String,
    pub etag: String,
    /// Milliseconds.
    pub duration_ms: u64,
    pub owner_email: String,
    pub owner_name: String,
    pub unique_id: String,
    pub list_item_id: String,
    pub web: String,
    pub list_url: String,
    pub file_url: String,
}

/// OneDrive's duration: "HH:MM:SS".
pub fn duration_text(ms: u64) -> String {
    if ms == 0 {
        return String::new();
    }
    let t = (ms as f64 / 1000.0).round() as u64;
    format!("{:02}:{:02}:{:02}", t / 3600, t % 3600 / 60, t % 60)
}

/// The item OneDrive adds to a playlist for a video.
pub fn item_body(list_server_url: &str, v: &Video, with_owner: bool) -> Value {
    let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>().replace('+', "%20");
    let thumb = format!(
        "{}/_api/v2.0/drives/{}/items/{}/thumbnails/0/c90x150/content?prefer=noredirect%2Cclosestavailablesize&cb={}",
        host(&v.web),
        v.drive_id,
        v.item_id,
        enc(&v.etag)
    );
    let title = v.name.rsplit_once('.').map(|(a, _)| a).unwrap_or(&v.name);
    // Both JSON strings in OneDrive's key order.
    let q = |s: &str| Value::String(s.to_string()).to_string();
    let owner = format!(
        r#"[{{"email":{},"name":{},"userId":{},"isResolved":true,"Key":{},"DisplayText":{}}}]"#,
        q(&v.owner_email),
        q(&v.owner_name),
        q(&v.owner_email),
        q(&format!("i:0#.f|membership|{}", v.owner_email)),
        q(&v.owner_name)
    );
    let ids = format!(
        r#"{{"UniqueId":{},"Id":{},"WebAbsoluteUrl":{},"ListFullUrl":{},"WebDavUrl":{}}}"#,
        q(&v.unique_id),
        q(&v.list_item_id),
        q(&v.web),
        q(&v.list_url),
        q(&v.file_url)
    );
    let mut values = vec![
        json!({"FieldName": "Thumbnail", "FieldValue": thumb, "HasException": false}),
        json!({"FieldName": "Title", "FieldValue": title, "HasException": false}),
    ];
    if with_owner && !v.owner_email.is_empty() {
        values.push(json!({"FieldName": "Owner", "FieldValue": owner, "HasException": false}));
    }
    values.push(json!({"FieldName": "Duration", "FieldValue": duration_text(v.duration_ms), "HasException": false}));
    values.push(json!({"FieldName": "VideoIdentifiers", "FieldValue": ids, "HasException": false}));
    values.push(json!({"FieldName": "ContentType", "FieldValue": "Item", "HasException": false}));
    json!({"listItemCreateInfo": {"__metadata": {"type": "SP.ListItemCreationInformationUsingPath"},
            "FolderPath": {"__metadata": {"type": "SP.ResourcePath"}, "DecodedUrl": list_server_url}},
        "formValues": values, "bNewDocumentUpdate": false})
}

/// A web address with its %-escapes undone (OneDrive's WebDavUrl and
/// ListFullUrl are decoded).
fn decode(u: &str) -> String {
    let mut out = Vec::with_capacity(u.len());
    let b = u.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%'
            && i + 2 < b.len()
            && let Ok(x) = u8::from_str_radix(&u[i + 1..i + 3], 16)
        {
            out.push(x);
            i += 3;
            continue;
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

/// The video's facts, read from Graph.
pub async fn video(client: &super::client::TeamsClient, drive: &str, item: &str) -> Result<Video> {
    let v: Value = client
        .graph_get(&format!("/drives/{drive}/items/{item}?$select=id,name,eTag,webUrl,sharepointIds,video,createdBy,parentReference"))
        .await?
        .error_for_status()?
        .json()
        .await?;
    let d: Value = client.graph_get(&format!("/drives/{drive}?$select=webUrl")).await?.error_for_status()?.json().await?;
    let g = |p: &str| v.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
    Ok(Video {
        drive_id: drive.to_string(),
        item_id: g("/id"),
        name: g("/name"),
        etag: g("/eTag"),
        duration_ms: v.pointer("/video/duration").and_then(|x| x.as_u64()).unwrap_or(0),
        owner_email: g("/createdBy/user/email"),
        owner_name: g("/createdBy/user/displayName"),
        unique_id: g("/sharepointIds/listItemUniqueId"),
        list_item_id: g("/sharepointIds/listItemId"),
        web: g("/sharepointIds/siteUrl"),
        list_url: decode(d["webUrl"].as_str().unwrap_or_default()),
        file_url: decode(&g("/webUrl")),
    })
}

/// Add the video to the playlist, as OneDrive does (without the owner when
/// the list refuses it, as OneDrive retries).
pub async fn add(list: &Playlist, video: &Video) -> Result<()> {
    let web = if list.web.is_empty() { list.url.split("/Lists/").next().unwrap_or_default().to_string() } else { list.web.clone() };
    let rel = server_relative(&list.url);
    let url = format!("{}/_api/web/GetList(@a1)/AddValidateUpdateItemUsingPath()?@a1={}", web.trim_end_matches('/'), quoted(&rel));
    let check = |r: &Value| -> Result<bool> {
        // Field errors come back as HasException entries.
        let vals = r["d"]["AddValidateUpdateItemUsingPath"]["results"].as_array().or_else(|| r["value"].as_array()).cloned().unwrap_or_default();
        if let Some(bad) = vals.iter().find(|x| x["HasException"].as_bool() == Some(true)) {
            let code = bad["ErrorCode"].as_i64().unwrap_or(0);
            if code == -2130575276 && bad["FieldName"] == "Owner" {
                return Ok(false);
            }
            bail!("{}: {}", bad["FieldName"].as_str().unwrap_or("field"), bad["ErrorMessage"].as_str().unwrap_or("refused"));
        }
        Ok(true)
    };
    let r = post(&url, &item_body(&rel, video, true)).await?;
    if !check(&r)? {
        let r = post(&url, &item_body(&rel, video, false)).await?;
        check(&r)?;
    }
    Ok(())
}

/// Delete a playlist (test clean-up): its list goes to the recycle bin.
pub async fn delete(list: &Playlist) -> Result<()> {
    let web = list.url.split("/Lists/").next().unwrap_or_default();
    // SharePoint deletes a list only with If-Match (any version).
    let url = format!("{web}/_api/web/lists(guid'{}')", list.id.trim_matches(|c| c == '{' || c == '}'));
    super::sharing::post_with(&url, &json!({}), &[("if-match", "*"), ("x-http-method", "DELETE")]).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clip() -> Video {
        Video {
            drive_id: "b!MwwW".into(),
            item_id: "01BV7C2BDQZT3NVLDHBBB2SJ7LMDN3NLE2".into(),
            name: "OST TEST 123 clip.mp4".into(),
            etag: "\"{DAF6CC70-67AC-4308-A927-EB60DBB6AC9A},2\"".into(),
            duration_ms: 6000,
            owner_email: "ost-test1@scnetsolutions.com".into(),
            owner_name: "OST Test 1".into(),
            unique_id: "daf6cc70-67ac-4308-a927-eb60dbb6ac9a".into(),
            list_item_id: "135".into(),
            web: "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com".into(),
            list_url: "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com/Documents".into(),
            file_url: "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com/Documents/OST TEST 123 clip.mp4".into(),
        }
    }

    #[test]
    fn item_is_onedrives() {
        // Teams' request on 2026-11-19 ("OST TEST 123 playlist").
        let b = item_body("/personal/ost-test1_scnetsolutions_com/Lists/OST TEST 123 playlist", &clip(), true);
        assert_eq!(b["listItemCreateInfo"]["FolderPath"]["DecodedUrl"], "/personal/ost-test1_scnetsolutions_com/Lists/OST TEST 123 playlist");
        let f = b["formValues"].as_array().unwrap();
        let get = |n: &str| f.iter().find(|x| x["FieldName"] == n).map(|x| x["FieldValue"].as_str().unwrap().to_string()).unwrap();
        assert_eq!(get("Thumbnail"), "https://scnetsolutions-my.sharepoint.com/_api/v2.0/drives/b!MwwW/items/01BV7C2BDQZT3NVLDHBBB2SJ7LMDN3NLE2/thumbnails/0/c90x150/content?prefer=noredirect%2Cclosestavailablesize&cb=%22%7BDAF6CC70-67AC-4308-A927-EB60DBB6AC9A%7D%2C2%22");
        assert_eq!(get("Title"), "OST TEST 123 clip");
        assert_eq!(get("Duration"), "00:00:06");
        assert_eq!(get("Owner"), r#"[{"email":"ost-test1@scnetsolutions.com","name":"OST Test 1","userId":"ost-test1@scnetsolutions.com","isResolved":true,"Key":"i:0#.f|membership|ost-test1@scnetsolutions.com","DisplayText":"OST Test 1"}]"#);
        assert!(get("VideoIdentifiers").starts_with(r#"{"UniqueId":"daf6cc70-67ac-4308-a927-eb60dbb6ac9a","Id":"135","WebAbsoluteUrl":"#));
        let ids: Value = serde_json::from_str(&get("VideoIdentifiers")).unwrap();
        assert_eq!(ids["Id"], "135");
        assert_eq!(get("ContentType"), "Item");
        assert!(item_body("/x", &clip(), false)["formValues"].as_array().unwrap().iter().all(|x| x["FieldName"] != "Owner"));
    }

    #[test]
    fn lists_read_as_the_proxy_answers() {
        // GetPersonalListsProxy for ost-test1 (2026-11-20).
        let v = json!({"value": [{"TemplateTypeId": TEMPLATE, "listId": "52f54550-1720-4b90-8487-02cbfaa22e36", "listTitle": "OST TEST 123 playlist",
            "listUrl": "https://x-my.sharepoint.com/personal/a_b_com/Lists/OST%20TEST%20123%20playlist", "siteUrl": "https://x-my.sharepoint.com/personal/a_b_com",
            "lastModifiedDate": "2026-11-20T07:41:28.0000000Z", "lastviewDateTime": null}]});
        let l = parse_lists(&v);
        assert_eq!(l.len(), 1);
        assert_eq!(l[0].title, "OST TEST 123 playlist");
        assert_eq!(l[0].url, "https://x-my.sharepoint.com/personal/a_b_com/Lists/OST TEST 123 playlist");
        assert_eq!(l[0].web, "https://x-my.sharepoint.com/personal/a_b_com");
        assert_eq!(l[0].when, "2026-11-20T07:41:28.0000000Z");
    }

    #[test]
    fn design_is_onedrives() {
        assert_eq!(
            design_body("OST TEST 123 playlist", ""),
            json!({"listDesignId":"3a867b4a-7429-0e1a-b02e-bf4b240ff1ce","store":1,"runtimeParameters":"{\"Playlist_listName\":\"OST TEST 123 playlist\",\"Playlist_description\":\"\",\"Playlist_color\":0,\"Playlist_addNavLink\":false,\"Playlist_icon\":12}"})
        );
        assert_eq!(duration_text(3_725_400), "01:02:05");
    }
}
