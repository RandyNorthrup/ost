//! Search Teams' GIFs or stickers as the fun picker does (debugging aid):
//! `cargo run --example giphy -- <query> [gifs|stickers]`.
use teams_cli::api::{client::TeamsClient, funstuff};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let query = std::env::args().nth(1).unwrap_or_else(|| "trending".into());
    let kind = match std::env::args().nth(2).as_deref() {
        Some("stickers") => funstuff::FunKind::Stickers,
        _ => funstuff::FunKind::Gifs,
    };
    let client = TeamsClient::new().await?;
    let v = funstuff::search_raw(&client, kind, &query, "g", "en-us").await?;
    println!(
        "{}",
        serde_json::to_string_pretty(&v)?
            .chars()
            .take(5000)
            .collect::<String>()
    );
    Ok(())
}
