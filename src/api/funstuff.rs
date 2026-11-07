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
