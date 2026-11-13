//! A cloud file as Teams' Attach reads it (debugging aid):
//! `cargo run --example cloud_attach -- <file url>`.
use teams_cli::api::{client::TeamsClient, cloud_attach, drive};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let url = std::env::args().nth(1).unwrap_or_default();
    let item = drive::item_by_url(&client, &url).await?;
    println!("{}", serde_json::to_string_pretty(&cloud_attach::prepare(&client, &item).await?)?);
    Ok(())
}
