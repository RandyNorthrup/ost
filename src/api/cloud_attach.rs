//! A file already in OneDrive or SharePoint attached to a message, as
//! Teams' Attach > Attach cloud files does it (captured on winpc
//! 2026-11-13, "OST TEST 117" in a group chat and "OST TEST 118" in a
//! channel):
//! - once picked, Teams reads the item through SharePoint's v2.0 `shares`
//!   API (its ids and default link) and its `driveItem/commands` (the
//!   default link's description, which the compose card shows);
//! - on send, in a chat, it invites the chat's other members
//!   (`driveItem/invite`, the default link's role, no other options) and
//!   puts the link SharePoint answers with in the record; in a channel it
//!   invites no one and sends no link;
//! - the `properties.files` record marks the file a "reference".

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::client::TeamsClient;
use super::drive::DriveItem;
use super::sharing;

/// A picked file, ready for the compose box and the record.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct CloudFile {
    pub name: String,
    /// Extension, lowercase ("txt").
    pub kind: String,
    /// The file's address ("…/Documents/ost-share-test.txt").
    pub object_url: String,
    /// Its site ("…/personal/ost-test1_scnetsolutions_com"), no slash.
    pub site_url: String,
    /// Graph's drive item id ("01BV…").
    pub item_id: String,
    pub drive_id: String,
    /// SharePoint's item id (a lowercase GUID), the record's `itemid`.
    pub unique_id: String,
    pub list_id: String,
    pub site_id: String,
    pub web_id: String,
    /// The default link's description ("Anyone with the link can edit").
    pub link_description: String,
    /// The default link's scope as Teams records it ("Anyone").
    pub scope: String,
    /// The invite's role: "write" for an edit link, else "read".
    pub role: String,
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

fn host(url: &str) -> String {
    url.split('/').take(3).collect::<Vec<_>>().join("/")
}

/// Teams' read of the item: `{host}/_api/v2.0/shares/u!…`.
pub fn shares_url(object_url: &str) -> String {
    format!(
        "{}/_api/v2.0/shares/{}/?expand=site,driveItem(select=@microsoft.graph.downloadUrl,file,id,webDavUrl,sharepointIds,eTag,publication,viewpoint/sharing,mainlink)",
        host(object_url),
        super::drive::share_id(object_url)
    )
}

/// The item under its site's v2.0 API (`…/sites/root/items/{id}/driveItem`).
fn item_api(site_url: &str, unique_id: &str) -> String {
    format!("{site_url}/_api/v2.0/sites/root/items/{unique_id}/driveItem")
}

/// The picked item, its default link and its description, from the two
/// replies Teams reads.
pub fn parse(item: &DriveItem, shares: &Value, commands: &Value) -> CloudFile {
    let d = &shares["driveItem"];
    let ids = &d["sharepointIds"];
    let link = &d["viewpoint"]["sharing"]["defaultSharingLink"];
    let edit = s(&link["role"]).eq_ignore_ascii_case("edit")
        || (link["role"].is_null() && s(&commands["invite"]["defaultType"]) == "edit");
    let kind = item.name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    CloudFile {
        name: item.name.clone(),
        kind,
        object_url: item.web_url.clone(),
        site_url: s(&ids["siteUrl"]).trim_end_matches('/').to_string(),
        item_id: if d["id"].is_string() { s(&d["id"]) } else { item.id.clone() },
        drive_id: item.drive_id.clone(),
        unique_id: s(&ids["listItemUniqueId"]).to_ascii_lowercase(),
        list_id: s(&ids["listId"]),
        site_id: s(&ids["siteId"]),
        web_id: s(&ids["webId"]),
        link_description: s(&commands["invite"]["defaultLinkDescription"]),
        scope: s(&link["scope"]),
        role: if edit { "write" } else { "read" }.to_string(),
    }
}

/// Read a picked file as Teams does when it lands in the compose box (a
/// Home or search pick carries only its address: Graph finds its drive).
pub async fn prepare(client: &TeamsClient, item: &DriveItem) -> Result<CloudFile> {
    let found;
    let item = if item.drive_id.is_empty() {
        found = super::drive::item_by_url(client, &item.web_url).await.unwrap_or_else(|_| item.clone());
        &found
    } else {
        item
    };
    let json = [("accept", "application/json")];
    let shares = sharing::get_with(&shares_url(&item.web_url), &json).await.context("Reading the file")?;
    let ids = &shares["driveItem"]["sharepointIds"];
    let site = s(&ids["siteUrl"]).trim_end_matches('/').to_string();
    let unique = s(&ids["listItemUniqueId"]).to_ascii_lowercase();
    let commands = if site.is_empty() || unique.is_empty() {
        Value::Null
    } else {
        sharing::get_with(&format!("{}/commands", item_api(&site, &unique)), &json).await.unwrap_or_default()
    };
    Ok(parse(item, &shares, &commands))
}

/// Teams' invite of a chat's other members.
pub fn invite_body(emails: &[String], role: &str) -> Value {
    json!({
        "recipients": emails.iter().map(|e| json!({ "email": e })).collect::<Vec<_>>(),
        "roles": [role]
    })
}

/// The link and its id from the invite's reply.
pub fn invited_link(reply: &Value) -> (String, String) {
    let p = reply["value"].as_array().and_then(|v| v.iter().find(|p| p["link"]["webUrl"].is_string()));
    p.map(|p| (s(&p["link"]["webUrl"]), s(&p["id"]))).unwrap_or_default()
}

/// The chiclet's breadcrumbs: the site address's last two segments
/// (".../personal/ost-test1_scnetsolutions_com" is "personal" and
/// "ost-test1_scnetsolutions_com").
pub fn breadcrumbs(site_url: &str) -> Value {
    let path: Vec<&str> = site_url.splitn(4, '/').nth(3).unwrap_or_default().split('/').filter(|p| !p.is_empty()).collect();
    let (team, channel) = match path.as_slice() {
        [.., a, b] => (*a, *b),
        [a] => (*a, ""),
        [] => ("", ""),
    };
    json!({ "sourceChannelName": channel, "sourceTeamName": team })
}

/// The `properties.files` entry Teams sends: `share` is the invite's link
/// and its id (empty in a channel), `channel` a channel post.
pub fn record(f: &CloudFile, share: (&str, &str), channel: bool) -> Value {
    let mut r = json!({
        "itemid": f.unique_id,
        "fileName": f.name,
        "fileType": f.kind,
        "fileInfo": {
            "itemId": f.item_id,
            "fileUrl": f.object_url,
            "siteUrl": f.site_url,
            "serverRelativeUrl": "",
            "shareUrl": share.0,
            "shareId": share.1
        },
        "fileChicletState": { "serviceName": if channel { "teams" } else { "p2p" }, "state": "reference" },
        "@type": "http://schema.skype.com/File",
        "version": 2,
        "id": f.unique_id,
        "baseUrl": f.site_url,
        "objectUrl": f.object_url,
        "openUrl": null,
        "type": f.kind,
        "title": f.name,
        "state": "reference",
        "altText": null,
        "chicletBreadcrumbs": breadcrumbs(&f.site_url),
        "providerData": "",
        "botFileProperties": {},
        "isUploadError": false,
        "progressComplete": null,
        "permissionScope": f.scope,
        "filePreview": { "previewUrl": "", "previewHeight": null, "previewWidth": null },
        "sharepointIds": {
            "driveId": f.drive_id,
            "listId": f.list_id,
            "listItemUniqueId": f.unique_id,
            "siteId": f.site_id,
            "siteUrl": f.site_url,
            "webId": f.web_id
        },
        "publication": { "level": null, "versionId": null },
        "site": { "dataLocationCode": null, "template": { "id": null } }
    });
    if f.drive_id.is_empty() {
        r["sharepointIds"].as_object_mut().map(|o| o.remove("driveId"));
    }
    r
}

/// On send: in a chat, share the file with the other members as Teams
/// does and return the record; in a channel, the record alone.
pub async fn send_record(client: &TeamsClient, chat_id: &str, f: &CloudFile) -> Result<Value> {
    let channel = chat_id.contains("@thread.tacv2");
    if channel {
        return Ok(record(f, ("", ""), true));
    }
    let emails = super::files::member_emails(client, chat_id).await.unwrap_or_default();
    let mut share = (String::new(), String::new());
    if !emails.is_empty() && !f.site_url.is_empty() && !f.unique_id.is_empty() {
        // Teams' headers: getDefaultLink shares through the default link
        // (SharePoint refuses the bare body otherwise: "RequireSignIn and
        // SendInvitation cannot both be false").
        let json = [
            ("accept", "application/json"),
            ("content-type", "application/json"),
            ("prefer", "ReturnSpecificErrorCode,getDefaultLink"),
            ("scenario", "TeamsFiles"),
            ("application", "Teams_Maglev"),
        ];
        let reply = sharing::post_with(&format!("{}/invite", item_api(&f.site_url, &f.unique_id)), &invite_body(&emails, &f.role), &json)
            .await
            .context("Sharing the file with the chat")?;
        share = invited_link(&reply);
    }
    Ok(record(f, (&share.0, &share.1), false))
}

/// A file on the picker's Home (OneDrive's recent files) or in the Attach
/// popover's suggestions.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct RecentFile {
    pub name: String,
    pub kind: String,
    pub web_url: String,
    /// Where it is: its site's title ("OST Test Team").
    pub location: String,
    /// Opened: when you last opened it ("Mon at 11:38 PM").
    pub opened: String,
    pub opened_title: String,
    pub owner: String,
    /// The Activity column: "You edited this", or "{0} edited this" with
    /// `activity_user` for {0}; and when ("Nov 6").
    pub activity: String,
    pub activity_user: String,
    pub activity_time: String,
}

fn local(t: &str) -> Option<chrono::DateTime<chrono::Local>> {
    chrono::DateTime::parse_from_rfc3339(t).ok().map(|t| t.with_timezone(&chrono::Local))
}

/// Home's rows from `sp.RecentFileCollection.DeltaSync` (the picker's own
/// call): the files you opened, newest first.
pub fn parse_recent(reply: &Value, now: chrono::DateTime<chrono::Local>) -> Vec<RecentFile> {
    // The reply's `value` is JSON text.
    let v: Value = match &reply["value"] {
        Value::String(t) => serde_json::from_str(t).unwrap_or_default(),
        other => other.clone(),
    };
    let mut rows: Vec<(String, RecentFile)> = v["files"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|f| {
            let x = &f["file"];
            let opened = [&x["UserRelationship"]["LastAccessDateTime"], &x["ItemProperties"]["AccessedByMailboxOwner"]["LastAccessDateTime"]]
                .into_iter()
                .map(s)
                .find(|t| !t.is_empty())?;
            let t = local(&opened)?;
            let name = s(&x["FileName"]);
            let a = &f["activity"];
            Some((opened, RecentFile {
                kind: s(&x["FileExtension"]).to_ascii_lowercase(),
                web_url: [&x["SharePointItem"]["FileUrl"], &x["ItemProperties"]["Default"]["DocumentLink"]].into_iter().map(s).find(|u| !u.is_empty()).unwrap_or_default(),
                location: s(&x["Visualization"]["ContainerTitle"]),
                opened: super::list_rows::activity_time(t, now),
                opened_title: t.format("%-m/%-d/%Y %-I:%M %p").to_string(),
                owner: s(&x["Document"]["Author"]),
                activity: s(&a["message_format"]),
                activity_user: a["users"].get(0).map(|u| s(&u["display_name"])).unwrap_or_default(),
                activity_time: local(&s(&a["timestamp"])).map(|t| super::list_rows::activity_time(t, now)).unwrap_or_default(),
                name,
            }))
        })
        .collect();
    rows.sort_by(|a, b| b.0.cmp(&a.0));
    rows.into_iter().map(|(_, r)| r).collect()
}

/// Home's files, as the picker reads them from your OneDrive.
pub async fn recent(client: &TeamsClient) -> Result<Vec<RecentFile>> {
    let personal = super::quick_access::personal_site(client).await?;
    let reply = sharing::get_with(&format!("{personal}/_api/sp.RecentFileCollection.DeltaSync?top=500"), &[("accept", "application/json")]).await?;
    Ok(parse_recent(&reply, chrono::Local::now()))
}

/// Meetings: the files shared in your meetings, as the picker asks
/// OneDrive (`GetSmartCacheData`, "calendarevents" and
/// "sharedmeetingfiles"; each answer is JSON text, empty when there are
/// none).
pub fn parse_meeting_files(reply: &Value) -> Vec<RecentFile> {
    let shared = reply["value"].get(1).and_then(|v| v.as_str()).unwrap_or_default();
    let v: Value = serde_json::from_str(shared).unwrap_or_default();
    let list = v.as_array().cloned().or_else(|| v["files"].as_array().cloned()).or_else(|| v["value"].as_array().cloned()).unwrap_or_default();
    parse_suggestions(&json!({ "Groups": [{ "Suggestions": list }] }))
}

pub async fn meeting_files(client: &TeamsClient) -> Result<Vec<RecentFile>> {
    let personal = super::quick_access::personal_site(client).await?;
    let json = [("accept", "application/json"), ("content-type", "application/json")];
    let reply = sharing::post_with(&format!("{personal}/_api/sp.OneDriveItemCollection.GetSmartCacheData"), &json!({ "names": ["calendarevents", "sharedmeetingfiles"] }), &json).await?;
    Ok(parse_meeting_files(&reply))
}

/// The first string among `keys` in `v`.
fn first(v: &Value, keys: &[&str]) -> String {
    keys.iter().map(|k| s(&v[*k])).find(|x| !x.is_empty()).unwrap_or_default()
}

/// Files in a substrate reply: suggestions' `Groups[].Suggestions[]` or
/// recommendations' `EntitySets[].ResultSets[].Results[]` (each maybe
/// under `Source` or `Resource`).
pub fn parse_suggestions(reply: &Value) -> Vec<RecentFile> {
    let mut hits: Vec<&Value> = Vec::new();
    for g in reply["Groups"].as_array().into_iter().flatten() {
        hits.extend(g["Suggestions"].as_array().into_iter().flatten());
    }
    for e in reply["EntitySets"].as_array().into_iter().flatten() {
        for r in e["ResultSets"].as_array().into_iter().flatten() {
            hits.extend(r["Results"].as_array().into_iter().flatten());
        }
    }
    hits.into_iter()
        .map(|h| if h["Source"].is_object() { &h["Source"] } else if h["Resource"].is_object() { &h["Resource"] } else { h })
        .filter_map(|h| {
            let url = first(h, &["AccessUrl", "FileUrl", "DocumentLink", "WebUrl", "Url", "Path"]);
            let name = first(h, &["FileName", "Name", "Title", "Text", "DisplayName"]);
            if url.is_empty() || name.is_empty() {
                return None;
            }
            let kind = first(h, &["FileExtension", "FileType", "Extension"]).trim_start_matches('.').to_ascii_lowercase();
            Some(RecentFile {
                kind: if kind.is_empty() { name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default() } else { kind },
                location: first(h, &["ContainerTitle", "SiteTitle", "ContainerName"]),
                owner: first(h, &["Author", "FileOwner", "CreatedBy"]),
                web_url: url,
                name,
                ..Default::default()
            })
        })
        .collect()
}

/// The Attach popover's files: with a query, Teams' search
/// (`suggestions`, slimpicker.compose); without, its recent-file
/// suggestions (`recommendations`, teamsDesktop.AttachFile) given the
/// conversation's last messages.
pub async fn suggest(query: &str, context: &Value) -> Result<Vec<RecentFile>> {
    let token = crate::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let id = uuid::Uuid::new_v4().to_string();
    let (url, body) = if query.trim().is_empty() {
        (
            "https://substrate.office.com/search/api/v1/recommendations?setflight=recDisableExchangeAttachments%2CrecDisableReceivedExchangeAttachments%2CrecEnable6ResultsInResponse%2CrecSaDocumentRankingThreshold4Compose%2CrecEnableIsTeamsMessage%2CrecDisableLocaleCheck",
            json!({ "EntityRequests": [{ "Context": { "EntityContext": context.as_array().cloned().unwrap_or_default() } }],
                    "Scenario": { "Name": "teamsDesktop.AttachFile" }, "AppName": "Microsoft Teams", "LogicalId": id }),
        )
    } else {
        (
            "https://substrate.office.com/search/api/v1/suggestions?scenario=slimpicker.compose&setflight=TurnOffMPLSuppressionTeams&domain=File",
            json!({ "EntityRequests": [{ "Query": { "QueryString": query, "NormalizedQueryString": query.trim().to_lowercase() }, "EntityType": "File", "Size": 25 }],
                    "Scenario": { "Name": "slimpicker.compose" }, "Cvid": uuid::Uuid::new_v4().to_string(), "AppName": "Microsoft Teams", "LogicalId": id }),
        )
    };
    let resp = reqwest::Client::new().post(url).bearer_auth(token).json(&body).send().await.context("File suggestions")?;
    let status = resp.status();
    let v: Value = resp.json().await.unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!("File suggestions: {status}");
    }
    Ok(parse_suggestions(&v))
}

/// The recommendations' context: a message as Teams describes it.
pub fn context_message(id: &str, text: &str, sender: &str, time: &str, to: &[String]) -> Value {
    json!({
        "@odata.type": "Microsoft.OutlookServices.Message",
        "Id": id,
        "Body": { "ContentType": 0, "Content": text },
        "Sender": { "EmailAddress": { "ExternalId": sender } },
        "ReceivedDateTime": time,
        "SentDateTime": time,
        "ToRecipients": to.iter().map(|o| json!({ "EmailAddress": { "ExternalId": o } })).collect::<Vec<_>>()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn home_lists_the_files_you_opened() {
        // Two files from ost-test1's DeltaSync reply (2026-11-13), cut: a
        // Loop paragraph Randy edited, opened Nov 6, and a shared file
        // never opened (Teams' Home leaves it out).
        let files = json!({ "files": [
            { "file": { "FileName": "ost-share-test.txt", "FileExtension": "txt", "SharePointItem": { "FileUrl": "https://x/ost-share-test.txt" },
                        "Visualization": { "ContainerTitle": "OST Test 1" }, "Document": { "Author": "OST Test 1" } },
              "activity": { "message_format": "You shared this", "users": [], "timestamp": "2026-11-13T20:00:35Z" } },
            { "file": { "FileName": "Loop paragraph.loop", "FileExtension": "loop", "SharePointItem": { "FileUrl": "https://x/Loop paragraph.loop" },
                        "UserRelationship": { "LastAccessDateTime": "2026-11-06T18:06:35Z" },
                        "Visualization": { "ContainerTitle": "Secure Coast Network Solutions" }, "Document": { "Author": "Randy Northrup" } },
              "activity": { "message_format": "{0} edited this", "users": [{ "display_name": "Randy Northrup" }], "timestamp": "2026-11-06T06:42:01Z" } }
        ] });
        let now = local("2026-11-13T20:30:00Z").unwrap();
        let rows = parse_recent(&json!({ "value": files.to_string() }), now);
        assert_eq!(rows.len(), 1);
        let r = &rows[0];
        assert_eq!((r.name.as_str(), r.location.as_str(), r.owner.as_str(), r.activity.as_str(), r.activity_user.as_str()),
            ("Loop paragraph.loop", "Secure Coast Network Solutions", "Randy Northrup", "{0} edited this", "Randy Northrup"));
        assert_eq!(r.opened, super::super::list_rows::activity_time(local("2026-11-06T18:06:35Z").unwrap(), now));
    }

    #[test]
    fn meetings_read_onedrives_cache() {
        // ost-test1's answer (2026-11-13): no meetings' files.
        assert!(parse_meeting_files(&json!({"value":["[]",""]})).is_empty());
        let f = parse_meeting_files(&json!({"value":["[]","[{\"FileName\":\"Deck.pptx\",\"FileUrl\":\"https://x/Deck.pptx\"}]"]}));
        assert_eq!((f[0].name.as_str(), f[0].kind.as_str()), ("Deck.pptx", "pptx"));
    }

    #[test]
    fn suggestions_read_either_reply() {
        assert!(parse_suggestions(&json!({"Groups":[],"LayoutHints":{"BestMatchSuggestions":[]}})).is_empty());
        let s = parse_suggestions(&json!({"Groups":[{"Suggestions":[{"Text":"Plan","FileName":"Plan.docx","AccessUrl":"https://x/Plan.docx","FileType":"Docx"}]}]}));
        assert_eq!((s[0].name.as_str(), s[0].kind.as_str(), s[0].web_url.as_str()), ("Plan.docx", "docx", "https://x/Plan.docx"));
        let r = parse_suggestions(&json!({"EntitySets":[{"ResultSets":[{"Results":[{"Source":{"Title":"Notes.txt","WebUrl":"https://x/Notes.txt"}}]}]}]}));
        assert_eq!((r[0].name.as_str(), r[0].kind.as_str()), ("Notes.txt", "txt"));
    }

    const SITE: &str = "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com";
    const FILE: &str = "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com/Documents/ost-share-test.txt";

    fn picked() -> CloudFile {
        // The shares and commands replies for ost-share-test.txt
        // (2026-11-13), cut to what OST reads.
        let shares = json!({ "driveItem": {
            "id": "01BV7C2BEOKDJR3USBWZHYGWGVLZ3V2CHL",
            "sharepointIds": { "listId": "0e0a18f3-101b-4090-a53e-1e24c4d98efd", "listItemId": "34",
                "listItemUniqueId": "1dd3508e-41d2-4fb6-8358-d55e775d08eb", "siteId": "fa160c33-a34a-4705-87b6-1f62802d97df",
                "siteUrl": SITE, "webId": "21b0d3cf-2b9e-45f6-a12e-fcf782c99233" },
            "viewpoint": { "sharing": { "defaultSharingLink": { "defaultToExistingAccess": false, "role": "Edit", "scope": "Anyone" } } } } });
        let commands = json!({ "invite": { "defaultLinkDescription": "Anyone with the link can edit", "defaultScope": "anonymous", "defaultType": "edit" } });
        let item = DriveItem {
            id: "01BV7C2BEOKDJR3USBWZHYGWGVLZ3V2CHL".into(),
            drive_id: "b!MwwW-kqjBUeHth9igC2X38_TsCGeK_ZFoS7894LJkjPzGAoOGxCQQKU-HiTE2Y79".into(),
            name: "ost-share-test.txt".into(),
            web_url: FILE.into(),
            ..Default::default()
        };
        parse(&item, &shares, &commands)
    }

    #[test]
    fn picked_files_read_as_teams_reads_them() {
        assert_eq!(
            shares_url(FILE),
            "https://scnetsolutions-my.sharepoint.com/_api/v2.0/shares/u!aHR0cHM6Ly9zY25ldHNvbHV0aW9ucy1teS5zaGFyZXBvaW50LmNvbS9wZXJzb25hbC9vc3QtdGVzdDFfc2NuZXRzb2x1dGlvbnNfY29tL0RvY3VtZW50cy9vc3Qtc2hhcmUtdGVzdC50eHQ/?expand=site,driveItem(select=@microsoft.graph.downloadUrl,file,id,webDavUrl,sharepointIds,eTag,publication,viewpoint/sharing,mainlink)"
        );
        let f = picked();
        assert_eq!((f.link_description.as_str(), f.scope.as_str(), f.role.as_str(), f.kind.as_str()), ("Anyone with the link can edit", "Anyone", "write", "txt"));
        assert_eq!(item_api(&f.site_url, &f.unique_id), format!("{SITE}/_api/v2.0/sites/root/items/1dd3508e-41d2-4fb6-8358-d55e775d08eb/driveItem"));
    }

    #[test]
    fn chat_records_are_teams_own() {
        // "OST TEST 117": the record Teams sent after inviting Randy.
        assert_eq!(invite_body(&["Randy@scnetsolutions.com".into()], "write"), json!({"recipients":[{"email":"Randy@scnetsolutions.com"}],"roles":["write"]}));
        let share = "https://scnetsolutions-my.sharepoint.com/:t:/p/ost-test1/IQCOUNMd0kG2T4NY1V53XQjrAZeu6_xTBRHxjxCSb09jm7Y";
        let r = record(&picked(), (share, "67083923-f796-4541-805a-e20842b2727f"), false);
        let teams = json!({"itemid":"1dd3508e-41d2-4fb6-8358-d55e775d08eb","fileName":"ost-share-test.txt","fileType":"txt","fileInfo":{"itemId":"01BV7C2BEOKDJR3USBWZHYGWGVLZ3V2CHL","fileUrl":FILE,"siteUrl":SITE,"serverRelativeUrl":"","shareUrl":share,"shareId":"67083923-f796-4541-805a-e20842b2727f"},"fileChicletState":{"serviceName":"p2p","state":"reference"},"@type":"http://schema.skype.com/File","version":2,"id":"1dd3508e-41d2-4fb6-8358-d55e775d08eb","baseUrl":SITE,"objectUrl":FILE,"openUrl":null,"type":"txt","title":"ost-share-test.txt","state":"reference","altText":null,"chicletBreadcrumbs":{"sourceChannelName":"ost-test1_scnetsolutions_com","sourceTeamName":"personal"},"providerData":"","botFileProperties":{},"isUploadError":false,"progressComplete":null,"permissionScope":"Anyone","filePreview":{"previewUrl":"","previewHeight":null,"previewWidth":null},"sharepointIds":{"driveId":"b!MwwW-kqjBUeHth9igC2X38_TsCGeK_ZFoS7894LJkjPzGAoOGxCQQKU-HiTE2Y79","listId":"0e0a18f3-101b-4090-a53e-1e24c4d98efd","listItemUniqueId":"1dd3508e-41d2-4fb6-8358-d55e775d08eb","siteId":"fa160c33-a34a-4705-87b6-1f62802d97df","siteUrl":SITE,"webId":"21b0d3cf-2b9e-45f6-a12e-fcf782c99233"},"publication":{"level":null,"versionId":null},"site":{"dataLocationCode":null,"template":{"id":null}}});
        assert_eq!(r, teams);
    }

    #[test]
    fn channel_records_carry_no_link() {
        // "OST TEST 118": no invite, no link, the "teams" service.
        let r = record(&picked(), ("", ""), true);
        assert_eq!((r["fileInfo"]["shareUrl"].as_str(), r["fileInfo"]["shareId"].as_str()), (Some(""), Some("")));
        assert_eq!(r["fileChicletState"], json!({"serviceName":"teams","state":"reference"}));
    }

    #[test]
    fn invite_replies_give_the_link() {
        let reply = json!({"value":[{"id":"67083923-f796-4541-805a-e20842b2727f","roles":["write"],"link":{"scope":"anonymous","type":"edit","webUrl":"https://x/:t:/p/a/IQ"}}]});
        assert_eq!(invited_link(&reply), ("https://x/:t:/p/a/IQ".to_string(), "67083923-f796-4541-805a-e20842b2727f".to_string()));
        assert_eq!(invited_link(&json!({})), (String::new(), String::new()));
        assert_eq!(breadcrumbs("https://x.sharepoint.com/sites/OSTTestTeam"), json!({"sourceChannelName":"OSTTestTeam","sourceTeamName":"sites"}));
    }
}
