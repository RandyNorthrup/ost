//! Teams' fun picker content: GIFs (GIPHY) and stickers (Tenor), served by
//! the middle tier's input-extension commands (services-giphy 757304):
//! `POST {mt}/beta/commands/com.microsoft.teamspace.inputextension.{giphy|
//! tenorstickers}/execute?version=1.0` with name/value parameters.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// Which collection to search.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FunKind {
    Gifs,
    Stickers,
}

impl FunKind {
    fn extension(self) -> &'static str {
        match self {
            FunKind::Gifs => "giphy",
            FunKind::Stickers => "tenorstickers",
        }
    }
}

/// Teams asks for 27 results at a time (GIPHYS_RESULT_LIMIT).
pub const RESULT_LIMIT: &str = "27";

/// The command's result for a query (`rating` is the tenant's GIPHY rating:
/// "y" strict, "g" moderate, "pg-13" no restriction).
pub async fn search_raw(
    client: &TeamsClient,
    kind: FunKind,
    query: &str,
    rating: &str,
    lang: &str,
) -> Result<serde_json::Value> {
    let mt = client
        .middle_tier_url()
        .context("No middle-tier address for this account")?;
    let token = super::directory::middle_tier_token().await?;
    let body = serde_json::json!([
        { "name": "query", "value": query },
        { "name": "rating", "value": rating },
        { "name": "limit", "value": RESULT_LIMIT },
        { "name": "lang", "value": lang },
    ]);
    let resp = client
        .http()
        .post(format!(
            "{mt}/beta/commands/com.microsoft.teamspace.inputextension.{}/execute?version=1.0",
            kind.extension()
        ))
        .bearer_auth(token)
        .json(&body)
        .send()
        .await
        .context("fun picker request")?;
    let status = resp.status();
    let v: serde_json::Value = resp.json().await.context("fun picker reply")?;
    if !status.is_success() {
        anyhow::bail!("HTTP {} from the fun picker", status.as_u16());
    }
    Ok(v.get("result").cloned().unwrap_or(v))
}

/// One GIF or sticker result.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct FunItem {
    /// What's sent (the full GIF).
    pub url: String,
    /// What the picker shows (GIPHY's 200 px wide rendition).
    pub preview: String,
    /// The full GIF's size.
    pub width: u32,
    pub height: u32,
    pub title: String,
}

/// The items in a command result (`[{result: [{composeValue, fieldValues:
/// [{fieldName, fieldValue}]}]}]` or the inner list).
pub fn items(result: &serde_json::Value) -> Vec<FunItem> {
    let list = result
        .as_array()
        .and_then(|a| a.first())
        .and_then(|f| f.get("result"))
        .or(Some(result))
        .and_then(|r| r.as_array())
        .cloned()
        .unwrap_or_default();
    list.iter()
        .filter_map(|it| {
            let fields: std::collections::HashMap<&str, &str> = it
                .get("fieldValues")?
                .as_array()?
                .iter()
                .filter_map(|f| {
                    Some((
                        f.get("fieldName")?.as_str()?,
                        f.get("fieldValue")?.as_str()?,
                    ))
                })
                .collect();
            let url = it
                .get("composeValue")
                .and_then(|v| v.as_str())
                .or_else(|| fields.get("image").copied())?
                .to_string();
            let num = |k: &str| fields.get(k).and_then(|v| v.parse().ok()).unwrap_or(0);
            Some(FunItem {
                preview: fields
                    .get("previewImageFW")
                    .or_else(|| fields.get("previewImage"))
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| url.clone()),
                url,
                width: num("width"),
                height: num("height"),
                title: fields
                    .get("title")
                    .map(|s| s.to_string())
                    .unwrap_or_default(),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gif_results_are_read() {
        // Trimmed from a live trending reply.
        let reply = serde_json::json!([{ "result": [{
            "composeType": "Image",
            "composeValue": "https://media3.giphy.com/media/v1.x/l0y6gXwXCDPAQ/giphy.gif",
            "fieldValues": [
                {"fieldName": "title", "fieldValue": "reggie wayne week GIF"},
                {"fieldName": "image", "fieldValue": "https://media3.giphy.com/media/v1.x/l0y6gXwXCDPAQ/giphy.gif"},
                {"fieldName": "previewImageFW", "fieldValue": "https://media3.giphy.com/media/v1.x/l0y6gXwXCDPAQ/200w.gif"},
                {"fieldName": "width", "fieldValue": "499"},
                {"fieldName": "height", "fieldValue": "699"}
            ]
        }]}]);
        let got = items(&reply);
        assert_eq!(got.len(), 1);
        assert_eq!(
            (got[0].width, got[0].height, got[0].title.as_str()),
            (499, 699, "reggie wayne week GIF")
        );
        assert!(got[0].preview.ends_with("200w.gif") && got[0].url.ends_with("giphy.gif"));
        assert!(items(&serde_json::json!({})).is_empty());
    }
}
