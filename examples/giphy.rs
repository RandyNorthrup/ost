//! Search Teams' GIFs or stickers as the fun picker does (debugging aid):
//! `cargo run --example giphy -- <query> [gifs|stickers]`; an empty query
//! is the trending list.
use teams_cli::api::{client::TeamsClient, funstuff};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let query = std::env::args().nth(1).unwrap_or_default();
    let kind = match std::env::args().nth(2).as_deref() {
        Some("stickers") => funstuff::FunKind::Stickers,
        _ => funstuff::FunKind::Gifs,
    };
    let client = TeamsClient::new().await?;
    let v = funstuff::search_raw(&client, kind, &query, "g", "en-us").await?;
    for it in funstuff::items(&v) {
        println!("{}x{} {} | {}", it.width, it.height, it.title, it.url);
    }
    Ok(())
}
