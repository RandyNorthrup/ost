//! Microsoft Places as Teams reads it (debugging aid): the tenant's
//! buildings, or the raw records for a filter:
//! `cargo run --example places -- [--raw '<filter>']`.
use teams_cli::api::{client::TeamsClient, places};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--raw") {
        let filter = args.get(1).map(String::as_str).unwrap_or("Type = \"Building\"");
        for p in places::find_places(&client, filter).await? {
            println!("{p:#}");
        }
        return Ok(());
    }
    for b in places::buildings(&client).await? {
        println!("{}  {}  ({})", b.id, b.name, b.address);
    }
    Ok(())
}
