//! Microsoft's stock content (Hubble) over AugLoop, as the video clip
//! recorder in Teams (Microsoft Stream's OneCamera) asks for it: its
//! Backdrops panel (stock images and videos tagged "background") and its
//! Stickers panel (Fluent emoji by category).
//!
//! Measured on winpc (2026-11-20): Stream opens `wss://augloop.svc.cloud.microsoft/`
//! with no account token, sends a SessionInit (appName "Testing"), activates
//! `AugLoop_Hubble_ProviderContentAnnotation` and seeds a document `doc`;
//! each search is an `AugLoop_Hubble_ContentSearchSignal` added under
//! `["session", "doc"]`, answered by a ProviderContentAnnotation whose
//! `data.Result.PartGroups` are the items (image/video parts, texts).

use futures::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio_tungstenite::tungstenite::Message;

/// Stream's pivots.
pub const STOCK_IMAGES: &str = "f8218404-63dd-4670-b0f5-f8b50674f963";
pub const STOCK_VIDEOS: &str = "32318599-a475-448c-a583-7aadf5e41c8c";
pub const EMOJI: &str = "84e04d41-3574-4764-a2d3-c24ae80c75eb";
/// The one item Stream leaves out of its backdrop lists.
const SKIPPED: &str = "e60356ca-b7cc-4160-98b5-4b220a02ac35";

/// One search: what Stream's panels send.
#[derive(Debug, Clone, PartialEq)]
pub struct Search {
    pub query: String,
    pub pivot: String,
    /// The sticker category ("Smilies", …) for emoji; none for backdrops.
    pub category: Option<String>,
    pub page_size: u32,
    pub page_offset: u32,
}

/// One item of a result.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Item {
    pub id: String,
    pub name: String,
    /// "image", "video" or "sticker".
    pub kind: String,
    /// The picture for the panel's tile.
    pub thumb: String,
    /// What is applied: the full image, the video or the sticker's SVG.
    pub url: String,
    pub width: u32,
    pub height: u32,
}

fn h(t: &str, b: &[&str]) -> Value {
    json!({"T_": t, "B_": b})
}

/// The signal's body, as Stream builds it.
pub fn signal_body(s: &Search, correlation: &str) -> Value {
    let params = if s.pivot == EMOJI {
        json!([
            {"key": "select", "value": "svg3D, skins/svg3D, thumbnailInfo/size100"},
            {"key": "filter", "value": format!("pivotNames/any(p: p eq '{}')", s.category.as_deref().unwrap_or("Smilies").replace('\'', "''"))},
            {"key": "app", "value": "1010"}
        ])
    } else {
        json!([
            {"key": "orderBy", "value": "modifiedDate"},
            {"key": "filter", "value": "tags/any(p: p eq 'background')"}
        ])
    };
    json!({
        "query": s.query,
        "contentProviders": [{"provider": "Hubble", "queryParams": params, "contentType": "Image", "pivotIds": [s.pivot],
            "contentSource": "Stock", "pageSize": s.page_size, "pageOffset": s.page_offset.to_string()}],
        "correlationId": correlation,
        "H_": h("AugLoop_Hubble_ContentSearchSignal", &["AugLoop_Hubble_BaseContentSignal", "AugLoop_Signals_Signal"])
    })
}

/// The items of a ProviderContentAnnotation's `data`.
pub fn parse_items(data: &Value) -> Vec<Item> {
    let groups = data.pointer("/Result/PartGroups").and_then(|g| g.as_array()).cloned().unwrap_or_default();
    let mut out = Vec::new();
    for g in groups {
        let text = |cat: &str| {
            g["TextParts"].as_array().into_iter().flatten().find(|t| t["TextCategory"] == cat).and_then(|t| t["Text"].as_str()).unwrap_or_default().to_string()
        };
        let id = text("Id");
        if id == SKIPPED {
            continue;
        }
        let image = |cat: &str| g["ImageParts"].as_array().into_iter().flatten().find(|p| p["ImageCategory"] == cat).cloned();
        let video = g["VideoParts"].as_array().into_iter().flatten().find(|p| p["VideoCategory"] == "Video").cloned();
        let pivot = text("PivotId");
        let (kind, main) = if let Some(v) = video {
            ("video", Some(v))
        } else if pivot == EMOJI {
            ("sticker", image("SVG"))
        } else {
            ("image", image("Image"))
        };
        let Some(main) = main else { continue };
        let thumb = image("LargeThumbnail").or_else(|| image("MediumThumbnail")).and_then(|p| p["SourceUrl"].as_str().map(str::to_string)).unwrap_or_default();
        let Some(url) = main["SourceUrl"].as_str() else { continue };
        out.push(Item {
            id,
            name: text("Description"),
            kind: kind.into(),
            thumb,
            url: url.into(),
            width: main["Width"].as_u64().unwrap_or(0) as u32,
            height: main["Height"].as_u64().unwrap_or(0) as u32,
        });
    }
    out
}

/// Only Hubble's own CDN is fetched from.
pub fn is_hubble_url(url: &str) -> bool {
    url.starts_with("https://cdn.hubblecontent.osi.office.net/")
}

/// Run the searches in one AugLoop session; the results in the same order
/// (an empty list for a search that failed or timed out).
pub async fn search(searches: &[Search], ui_language: &str) -> anyhow::Result<Vec<Vec<Item>>> {
    let mut req = tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request("wss://augloop.svc.cloud.microsoft/")?;
    req.headers_mut().insert("Origin", "https://teams.microsoft.com".parse()?);
    let (mut ws, _) = tokio_tungstenite::connect_async(req).await?;
    let group = uuid::Uuid::new_v4().simple().to_string();
    let mut n = 0u32;
    let next = |n: &mut u32| {
        *n += 1;
        (format!("{}.{}", &group[..22], n), format!("c{n}"))
    };
    let (cv, mid) = next(&mut n);
    let init = json!({"protocolVersion": 2,
        "clientMetadata": {"appName": "Testing", "appPlatform": "Client", "sessionId": uuid::Uuid::new_v4().simple().to_string(), "uiLanguage": ui_language,
            "runtimeVersion": "3.0.211", "docSessionId": uuid::Uuid::new_v4().simple().to_string(), "flights": "_acceptsClaimsChallengeMessages;_acceptsSeedingStatusChangeMessages"},
        "extensionConfigs": [], "returnWorkflowInputTypes": false, "enableRemoteExecutionNotification": false, "createBlobStorageContainer": false,
        "H_": h("AugLoop_Session_Protocol_SessionInitMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid});
    ws.send(Message::Text(init.to_string().into())).await?;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(20);
    // The session's answer.
    loop {
        let Some(m) = tokio::time::timeout_at(deadline, ws.next()).await? else { anyhow::bail!("AugLoop closed") };
        if let Message::Text(t) = m? {
            let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
            if v.get("sessionKey").is_some() {
                break;
            }
            if v.pointer("/H_/T_").and_then(|x| x.as_str()).is_some_and(|t| t.contains("Error")) {
                anyhow::bail!("AugLoop refused the session");
            }
        }
    }
    let (cv, mid) = next(&mut n);
    let activate = json!({"annotationType": "AugLoop_Hubble_ProviderContentAnnotation", "token": uuid::Uuid::new_v4().simple().to_string(), "ignoreExistingAnnotations": false,
        "returnAnnotationDoesNotExist": true, "sendApologies": false,
        "H_": h("AugLoop_Session_Protocol_AnnotationActivationMessage", &["AugLoop_Session_Protocol_Message"]), "cv": cv, "messageId": mid});
    ws.send(Message::Text(activate.to_string().into())).await?;
    let (cv, mid) = next(&mut n);
    let seed = json!({"cv": cv, "seq": 0, "ops": [{"parentPath": ["session"], "items": [{"id": "doc", "revId": "0", "body": {"isReadonly": false, "H_": h("AugLoop_Core_Document", &["AugLoop_Core_TileGroup"])}}],
        "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])}], "groupId": "Seed", "groupSize": 1, "groupComplete": true,
        "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid});
    ws.send(Message::Text(seed.to_string().into())).await?;
    let correlations: Vec<String> = searches.iter().map(|_| uuid::Uuid::new_v4().to_string()).collect();
    let ops: Vec<Value> = searches
        .iter()
        .zip(&correlations)
        .enumerate()
        .map(|(i, (s, c))| {
            json!({"parentPath": ["session", "doc"], "items": [{"id": uuid::Uuid::new_v4().simple().to_string(), "body": signal_body(s, c), "contextId": format!("C{}", i * 3 + 1)}],
                "H_": h("AugLoop_Core_AddOperation", &["AugLoop_Core_OperationWithSiblingContext", "AugLoop_Core_Operation"])})
        })
        .collect();
    let (cv, mid) = next(&mut n);
    let sync = json!({"cv": cv, "seq": 1, "ops": ops, "H_": h("AugLoop_Session_Protocol_SyncMessage", &["AugLoop_Session_Protocol_Message"]), "messageId": mid});
    ws.send(Message::Text(sync.to_string().into())).await?;
    let mut results: Vec<Option<Vec<Item>>> = vec![None; searches.len()];
    while results.iter().any(|r| r.is_none()) {
        let Ok(Some(m)) = tokio::time::timeout_at(deadline, ws.next()).await else { break };
        let Message::Text(t) = m? else { continue };
        if t.as_str() == "~" {
            ws.send(Message::Text("~".into())).await?;
            continue;
        }
        let v: Value = serde_json::from_str(t.as_str()).unwrap_or_default();
        // Server messages ("s…") are acknowledged.
        if let Some(id) = v["messageId"].as_str()
            && id.starts_with('s')
        {
            let ack = json!({"H_": h("AugLoop_Session_Protocol_Response", &[]), "messageId": id});
            ws.send(Message::Text(ack.to_string().into())).await?;
        }
        for op in v["ops"].as_array().into_iter().flatten() {
            for it in op["items"].as_array().into_iter().flatten() {
                let body = &it["body"];
                let Some(c) = body["correlationId"].as_str() else { continue };
                if let Some(i) = correlations.iter().position(|x| x == c)
                    && body.pointer("/data/Result").is_some()
                {
                    results[i] = Some(parse_items(&body["data"]));
                }
            }
        }
    }
    let _ = ws.close(None).await;
    Ok(results.into_iter().map(Option::unwrap_or_default).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signals_as_stream_sends_them() {
        let b = signal_body(&Search { query: "beach".into(), pivot: STOCK_IMAGES.into(), category: None, page_size: 50, page_offset: 0 }, "c1");
        assert_eq!(b["contentProviders"][0]["queryParams"][1]["value"], "tags/any(p: p eq 'background')");
        assert_eq!(b["contentProviders"][0]["pageOffset"], "0");
        assert_eq!(b["H_"]["T_"], "AugLoop_Hubble_ContentSearchSignal");
        let e = signal_body(&Search { query: String::new(), pivot: EMOJI.into(), category: Some("Hand gestures".into()), page_size: 50, page_offset: 0 }, "c2");
        assert_eq!(e["contentProviders"][0]["queryParams"][1]["value"], "pivotNames/any(p: p eq 'Hand gestures')");
        assert_eq!(e["contentProviders"][0]["queryParams"][2]["value"], "1010");
    }

    #[test]
    fn items_from_part_groups() {
        let data = json!({"Result": {"PartGroups": [
            {"Type": "Image", "ImageParts": [
                {"ImageCategory": "Image", "SourceUrl": "https://cdn.hubblecontent.osi.office.net/m365content/publish/a/1_medium.jpg", "Width": 2048, "Height": 1365},
                {"ImageCategory": "LargeThumbnail", "SourceUrl": "https://cdn.hubblecontent.osi.office.net/m365content/publish/a/thumbnails/large.jpg", "Width": 270, "Height": 180}],
             "VideoParts": [], "TextParts": [{"TextCategory": "PivotId", "Text": STOCK_IMAGES}, {"TextCategory": "Description", "Text": "Stones"}, {"TextCategory": "Id", "Text": "a"}]},
            {"Type": "Video", "ImageParts": [{"ImageCategory": "LargeThumbnail", "SourceUrl": "https://cdn.hubblecontent.osi.office.net/videos/publish/b/thumbnails/large.jpg"}],
             "VideoParts": [{"VideoCategory": "SmallPreview", "SourceUrl": "x"}, {"VideoCategory": "Video", "SourceUrl": "https://cdn.hubblecontent.osi.office.net/videos/publish/b/1.mp4", "Width": 1920, "Height": 1080}],
             "TextParts": [{"TextCategory": "PivotId", "Text": STOCK_VIDEOS}, {"TextCategory": "Description", "Text": "Waves"}, {"TextCategory": "Id", "Text": "b"}]},
            {"Type": "Image", "ImageParts": [{"ImageCategory": "SVG", "SourceUrl": "https://cdn.hubblecontent.osi.office.net/emojis/publish/c/svg/grin_color.svg", "Width": 96, "Height": 96},
                {"ImageCategory": "LargeThumbnail", "SourceUrl": "https://cdn.hubblecontent.osi.office.net/emojis/publish/c/png/thumbnails/100/s1.png"}],
             "TextParts": [{"TextCategory": "PivotId", "Text": EMOJI}, {"TextCategory": "Description", "Text": "Grinning face"}, {"TextCategory": "Id", "Text": "c"}]},
            {"Type": "Image", "ImageParts": [{"ImageCategory": "Image", "SourceUrl": "https://x/y.jpg"}], "TextParts": [{"TextCategory": "Id", "Text": SKIPPED}]}
        ]}});
        let items = parse_items(&data);
        assert_eq!(items.len(), 3);
        assert_eq!((items[0].kind.as_str(), items[0].name.as_str(), items[0].width), ("image", "Stones", 2048));
        assert!(items[0].thumb.ends_with("large.jpg"));
        assert_eq!((items[1].kind.as_str(), items[1].url.as_str()), ("video", "https://cdn.hubblecontent.osi.office.net/videos/publish/b/1.mp4"));
        assert_eq!((items[2].kind.as_str(), items[2].name.as_str()), ("sticker", "Grinning face"));
        assert!(items[2].url.ends_with("grin_color.svg"));
        assert!(is_hubble_url(&items[2].thumb) && !is_hubble_url("https://evil/x"));
    }
}
