//! A link's preview from Teams' URL preview service, as compose gets it:
//! `url_preview <url>`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let url = std::env::args().nth(1).expect("url");
    let client = TeamsClient::new().await?;
    let p = teams_cli::api::url_preview::fetch(&client, &url).await?;
    println!("{}", serde_json::to_string_pretty(&p)?);
    if let Some(p) = p.filter(|p| !p.thumbnail.is_empty()) {
        let bytes = client.ams_get(&p.thumbnail).await?;
        println!("picture: {} bytes", bytes.len());
    }
    Ok(())
}
