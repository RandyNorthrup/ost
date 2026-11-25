//! PowerPoint Live and Excel Live, as Teams starts them
//! (docs/spec/content-sharing.md §3–4): the file is redeemed in SharePoint
//! (its download address and Office for the web's application address),
//! PowerPoint's snap service makes the presentation's address, and the
//! share goes out as a content-sharing session.

use anyhow::{Context, Result};

use super::client::TeamsClient;
use crate::calling::content_sharing::PptFile;

/// The SharePoint host of a file address.
fn sp_host(url: &str) -> Option<String> {
    let u = url::Url::parse(url).ok()?;
    if u.scheme() != "https" || !u.username().is_empty() || u.password().is_some() {
        return None;
    }
    let host = u.host_str()?;
    (host.len() > ".sharepoint.com".len() && host.ends_with(".sharepoint.com"))
        .then(|| host.to_string())
}

/// A share id for SharePoint's `shares/u!…` (base64url of the address,
/// unpadded).
fn share_token(url: &str) -> String {
    use base64::Engine;
    format!(
        "u!{}",
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(url.as_bytes())
    )
}

/// Teams' redeem (r_data-resolvers-browser-files `getFileDetailsForPptSharing`):
/// `GET {site}/_api/v2.0/shares/u!<b64 url>/driveItem?select=…` with a
/// SharePoint token, preferring caller-agnostic download addresses.
pub async fn redeem(url: &str) -> Result<serde_json::Value> {
    let host = sp_host(url).context("Not a SharePoint or OneDrive file")?;
    let token = crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
    let select = "id,file,webDavUrl,sharepointIds,size,name,@content.downloadUrl,etag,webUrl,OpenWith,officeBundle,currentUserRole";
    let resp = reqwest::Client::new()
        .get(format!(
            "https://{host}/_api/v2.0/shares/{}/driveItem?select={select}",
            share_token(url)
        ))
        .bearer_auth(token)
        .header(
            "Prefer",
            "redeemSharingLink, getCallerAgnosticDownloadUrl, includeSubstrateId",
        )
        .header("Accept", "application/json")
        .send()
        .await?;
    let status = resp.status();
    let v: serde_json::Value = resp.json().await.unwrap_or_default();
    anyhow::ensure!(
        status.is_success(),
        "The file couldn't be opened ({status})"
    );
    Ok(v)
}

/// Office for the web's regional hosts for a WAC application address
/// (`https://usc-powerpoint.officeapps.live.com/p/…`): (region as the
/// snap and pods services name it, the region as the WAC host has it).
/// Teams' WacToPodsPreviewerMap renames a few (cac → canc, auc and nzc →
/// ausc, twc and myc → sgc).
pub fn wac_region(wac_url: &str) -> Option<(String, String)> {
    let rest = wac_url.strip_prefix("https://")?;
    let host = &rest[..rest.find(['/', '?']).unwrap_or(rest.len())];
    let region = host.split('-').next()?.to_ascii_lowercase();
    if region.is_empty()
        || !host.ends_with(".officeapps.live.com")
        || !region.chars().all(|c| c.is_ascii_alphanumeric())
    {
        return None;
    }
    let pods = match region.as_str() {
        "cac" => "canc",
        "auc" | "nzc" => "ausc",
        "twc" | "myc" => "sgc",
        r => r,
    }
    .to_string();
    Some((pods, region))
}

/// The file as a PowerPoint Live share names it, from its redeemed item.
pub fn ppt_file(item: &serde_json::Value, correlation: &str, now_ms: u64) -> Result<PptFile> {
    let s = |p: &str| {
        item.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let site_id = s("/sharepointIds/siteId");
    let list_id = s("/sharepointIds/listId");
    let unique = s("/sharepointIds/listItemUniqueId");
    anyhow::ensure!(
        !site_id.is_empty() && !unique.is_empty(),
        "The file isn't in SharePoint or OneDrive"
    );
    let download = item
        .get("@content.downloadUrl")
        .or_else(|| item.get("@microsoft.graph.downloadUrl"))
        .and_then(|d| d.as_str())
        .unwrap_or_default()
        .to_string();
    anyhow::ensure!(
        download.starts_with("https://"),
        "The file can't be downloaded"
    );
    let wac = [
        "/openWith/wac/applicationUrl",
        "/OpenWith/wac/applicationUrl",
        "/openWith/wac/applicationurl",
    ]
    .iter()
    .find_map(|p| item.pointer(p).and_then(|x| x.as_str()))
    .unwrap_or("https://usc-powerpoint.officeapps.live.com/p/PowerPointFrame.aspx")
    .to_string();
    let boot = [
        "/openWith/wac/bootstrapperUrl",
        "/OpenWith/wac/bootstrapperUrl",
    ]
    .iter()
    .find_map(|p| item.pointer(p).and_then(|x| x.as_str()))
    .unwrap_or_default()
    .to_string();
    Ok(PptFile {
        id: format!("{site_id}_{list_id}_{unique}"),
        name: s("/name"),
        url: s("/webDavUrl"),
        download_url: download,
        web_dav_url: s("/webDavUrl"),
        web_url: s("/webUrl"),
        size: item.get("size").and_then(|x| x.as_u64()).unwrap_or(0),
        etag: Some(s("/eTag"))
            .filter(|e| !e.is_empty())
            .unwrap_or_else(|| s("/etag")),
        site_id,
        list_item_unique_id: unique,
        wac_url: wac,
        bootstrapper_url: boot,
        major_version: item
            .pointer("/officeBundle/version")
            .and_then(|x| x.as_u64())
            .unwrap_or(1),
        snap_url: String::new(),
        correlation_id: correlation.to_string(),
        presenter_start: now_ms,
    })
}

/// PowerPoint's snap service (89637 `getSnapUrlWithRetry`, captured):
/// `POST https://<region>.snap.officeapps.live.com/GetDownloadUrl.ashx`
/// → `{FSuccess, SnapUrl}`, the presentation's address attendees render.
pub async fn snap_url(file: &PptFile, call_id: &str) -> Result<String> {
    let (region, wac_region) =
        wac_region(&file.wac_url).context("No Office for the web region for the file")?;
    let ext = file
        .name
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_else(|| "pptx".into());
    let body = serde_json::json!({
        "CallID": call_id,
        "ContentId": file.id,
        "DownloadUrl": file.download_url,
        "CustomFontCatalogUrl": "",
        "FileExtension": ext,
        "FileLengthHint": file.size,
        "ETag": file.etag,
        "DocId": file.id,
        "MultiRangeEnabled": false,
        "TailRangeEnabled": true,
        "AuthHeaderForHostDownloadEnabled": false,
        "GuaranteeLevel": 1,
        "FileEnvironment": format!("{}-powerpoint.officeapps.live.com", wac_region.to_ascii_uppercase()),
    });
    let mut last = String::new();
    for attempt in 0..3 {
        let resp = reqwest::Client::new()
            .post(format!(
                "https://{region}.snap.officeapps.live.com/GetDownloadUrl.ashx"
            ))
            .header("X-UserSessionId", &file.correlation_id)
            .header(
                "callercorrelationid",
                format!("snapRequestID_{}", uuid::Uuid::new_v4()),
            )
            .header("X-WacNoAuth", "1")
            .header("Scenario", "Previewer")
            .header("Client", "MSTeams--Bootstrapper")
            .header("CallId", call_id)
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        let v: serde_json::Value = resp.json().await.unwrap_or_default();
        if status.is_success()
            && v.get("FSuccess").and_then(|b| b.as_bool()) == Some(true)
            && let Some(u) = v
                .get("SnapUrl")
                .and_then(|u| u.as_str())
                .filter(|u| u.starts_with("https://"))
        {
            return Ok(u.to_string());
        }
        last = format!(
            "{status} {}",
            v.get("ErrorCode").and_then(|e| e.as_str()).unwrap_or("")
        );
        // Teams retries twice, a second apart, on 403, 404 and 503.
        if attempt < 2 && matches!(status.as_u16(), 403 | 404 | 503) {
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            continue;
        }
        break;
    }
    anyhow::bail!("PowerPoint couldn't prepare the presentation ({last})")
}

/// The tray's recent decks or workbooks (Teams' `services-io-mru`,
/// captured): Office's MRU, `GET https://ocws.officeapps.live.com/ocs/v2/
/// recent/docs?sort=date&show=12&apps=<PowerPoint|Excel>&exts=…` (token for
/// api.office.net). Falls back to your OneDrive's recent files. Each:
/// `{name, url, driveId, itemId}`.
pub async fn recent_docs(client: &TeamsClient, excel: bool) -> Result<Vec<serde_json::Value>> {
    let (app, exts) = if excel {
        ("Excel", "xlsx,xlsm,xlsb")
    } else {
        (
            "PowerPoint",
            "pptx,ppsx,ppt,pps,pot,potx,pptm,potm,ppam,ppsm,ppa,odp",
        )
    };
    let mru = async {
        let token = crate::auth::oauth::access_token_for("https://api.office.net/.default").await?;
        let v: serde_json::Value = reqwest::Client::new()
            .get(format!("https://ocws.officeapps.live.com/ocs/v2/recent/docs?sort=date&show=12&apps={app}&exts={exts}"))
            .bearer_auth(token)
            .header("X-Office-Platform", "Microsoft Teams")
            .header("X-Office-Application", "107")
            .header("X-Office-Version", "1415/1.0.0.2022020421")
            .header("X-CorrelationId", uuid::Uuid::new_v4().to_string())
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let items: Vec<serde_json::Value> = v
            .pointer("/documents/items")
            .and_then(|i| i.as_array())
            .into_iter()
            .flatten()
            .filter_map(|i| {
                let s = |p: &str| i.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
                let url = Some(s("/url")).filter(|u| !u.is_empty()).unwrap_or_else(|| s("/web_url"));
                (!url.is_empty()).then(|| serde_json::json!({ "name": s("/title"), "url": url, "driveId": s("/onedrive_info/drive_id"), "itemId": s("/onedrive_info/item_id") }))
            })
            .collect();
        anyhow::Ok(items)
    }
    .await;
    match mru {
        Ok(items) => return Ok(items),
        Err(e) => tracing::info!("Office recent files: {e:#}; using OneDrive's"),
    }
    // OneDrive's recent files (Graph's drive/recent is retired), with
    // Graph's ids for Excel Live.
    let files: Vec<super::recent_files::Recent> = super::recent_files::fetch(client)
        .await?
        .into_iter()
        .filter(|r| exts.split(',').any(|x| x.eq_ignore_ascii_case(&r.kind)))
        .take(12)
        .collect();
    let items = super::recent_files::graph_items(client, &files).await;
    Ok(files
        .iter()
        .zip(items)
        .map(|(r, g)| tray_file(&super::recent_files::drive_item(r, g)))
        .collect())
}

/// A recent file as the tray lists it.
fn tray_file(it: &super::drive::DriveItem) -> serde_json::Value {
    serde_json::json!({ "name": it.name, "url": it.web_url, "driveId": it.drive_id,
                        "itemId": if it.drive_id.is_empty() { "" } else { it.id.as_str() } })
}

/// Excel Live's page for the workbook (calling-app `NP`): Excel's Teams app
/// staticTabs[0].contentUrl with `{sourceOrigin}` = `Teams.<source>.MeetingStage`,
/// then `callId` and the file as `subEntityId`.
pub fn excel_stage_url(
    content_url: &str,
    source: &str,
    call_id: &str,
    sub_entity: &serde_json::Value,
) -> String {
    let base = content_url.replace("{sourceOrigin}", &format!("Teams.{source}.MeetingStage"));
    let sep = if base.contains('?') { '&' } else { '?' };
    format!(
        "{base}{sep}callId={}&subEntityId={}",
        super::tabs::encode_uri_component(call_id),
        super::tabs::encode_uri_component(&sub_entity.to_string())
    )
}

/// Excel Live's file context (`subEntityId`): `{fileType, shareUrl,
/// objectUrl, baseUrl, fileId, ctx, tenantId}`.
pub fn excel_sub_entity(
    file_type: &str,
    share_url: &str,
    object_url: &str,
    site_url: &str,
    file_id: &str,
    source: &str,
    tenant: &str,
) -> serde_json::Value {
    serde_json::json!({
        "fileType": file_type,
        "shareUrl": share_url,
        "objectUrl": object_url,
        "baseUrl": site_url,
        "fileId": file_id,
        "ctx": source,
        "tenantId": tenant,
    })
}

/// Everything an Excel Live share needs: the meeting's people get edit
/// access (a link for them: Teams' createFilesShareLink with scope users,
/// type edit), and Excel's meeting stage page for the workbook.
pub async fn excel_share(
    client: &TeamsClient,
    drive_id: &str,
    item_id: &str,
    people: &[String],
    call_id: &str,
) -> Result<serde_json::Value> {
    let ok = |s: &str| {
        !s.is_empty()
            && s.chars()
                .all(|c| c.is_ascii_alphanumeric() || "!-_.".contains(c))
    };
    anyhow::ensure!(ok(drive_id) && ok(item_id), "No workbook");
    let item: serde_json::Value = client
        .graph_get(&format!(
            "/drives/{drive_id}/items/{item_id}?$select=id,name,webDavUrl,webUrl,sharepointIds"
        ))
        .await?
        .json()
        .await?;
    let s = |p: &str| {
        item.pointer(p)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let name = s("/name");
    // Only the people who can't open it yet need the link (with nobody
    // else in the meeting, the workbook's own address).
    let share_url = if people.is_empty() {
        s("/webUrl")
    } else {
        let recipients: Vec<serde_json::Value> = people
            .iter()
            .map(|o| serde_json::json!({ "objectId": o }))
            .collect();
        let link: serde_json::Value = client
            .graph_post(
                &format!("/drives/{drive_id}/items/{item_id}/createLink"),
                &serde_json::json!({ "type": "edit", "scope": "users", "recipients": recipients, "sendNotification": false }),
            )
            .await?
            .json()
            .await?;
        link.pointer("/link/webUrl")
            .and_then(|u| u.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let def = super::app_details::definition(client, crate::calling::content_sharing::EXCEL_APP_ID)
        .await?;
    let content_url = def
        .pointer("/staticTabs/0/contentUrl")
        .and_then(|u| u.as_str())
        .context("Excel's app has no page")?
        .to_string();
    let file_type = name
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_default();
    let unique = s("/sharepointIds/listItemUniqueId");
    let sub = excel_sub_entity(
        &file_type,
        &share_url,
        &s("/webDavUrl"),
        &s("/sharepointIds/siteUrl"),
        &unique,
        "onedrive",
        &client.tenant_id().unwrap_or_default(),
    );
    Ok(serde_json::json!({
        "name": name,
        "url": excel_stage_url(&content_url, "onedrive", call_id, &sub),
        "shareUrl": share_url,
        "fileId": unique,
        "substrateId": crate::calling::content_sharing::substrate_id(&s("/sharepointIds/siteId"), &s("/sharepointIds/webId"), &s("/sharepointIds/listId"), &s("/id")),
        "subEntityId": sub,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn regions_follow_teams_map() {
        assert_eq!(
            wac_region("https://usc-powerpoint.officeapps.live.com/p/PowerPointFrame.aspx"),
            Some(("usc".into(), "usc".into()))
        );
        assert_eq!(
            wac_region("https://cac-powerpoint.officeapps.live.com/p/x"),
            Some(("canc".into(), "cac".into()))
        );
        assert_eq!(
            wac_region("https://nzc-powerpoint.officeapps.live.com/p/x"),
            Some(("ausc".into(), "nzc".into()))
        );
        assert_eq!(wac_region("https://evil.example/p/x"), None);
        assert_eq!(
            share_token("https://a.sharepoint.com/x"),
            "u!aHR0cHM6Ly9hLnNoYXJlcG9pbnQuY29tL3g"
        );
        assert_eq!(
            sp_host("https://x-my.sharepoint.com/personal/u/Documents/a.pptx").as_deref(),
            Some("x-my.sharepoint.com")
        );
        assert_eq!(sp_host("https://evil.example/a"), None);
    }

    #[test]
    fn ppt_files_and_excel_pages() {
        let item = serde_json::json!({
            "name": "OST TEST 214 deck.pptx", "size": 36656, "eTag": "\"{A5EC},1\"", "webDavUrl": "https://x-my.sharepoint.com/personal/u/Documents/d.pptx",
            "@content.downloadUrl": "https://x-my.sharepoint.com/personal/u/_layouts/15/download.aspx?UniqueId=a5ec",
            "sharepointIds": {"siteId": "s", "listId": "l", "listItemUniqueId": "u"},
            "openWith": {"wac": {"applicationUrl": "https://usc-powerpoint.officeapps.live.com/p/PowerPointFrame.aspx"}}
        });
        let f = ppt_file(&item, "c", 5).unwrap();
        assert_eq!(f.id, "s_l_u");
        assert_eq!(f.etag, "\"{A5EC},1\"");
        let c = crate::calling::content_sharing::ppt_content(&f);
        assert_eq!(c["type"], "ppt");
        assert_eq!(
            c["canonicalFileUrl"],
            "https://x-my.sharepoint.com/personal/u/Documents/d.pptx/_vti_bin/cellstorage.svc/CellStorageService"
        );
        let sub = excel_sub_entity(
            "xlsx",
            "https://share",
            "https://obj",
            "https://site",
            "u",
            "onedrive",
            "t",
        );
        let url = excel_stage_url(
            "https://excel.officeapps.live.com/x/_layouts/xlembed.aspx?ui={locale}&src={sourceOrigin}",
            "onedrive",
            "call",
            &sub,
        );
        assert!(url.starts_with("https://excel.officeapps.live.com/x/_layouts/xlembed.aspx?ui={locale}&src=Teams.onedrive.MeetingStage&callId=call&subEntityId=%7B"));
    }
}
