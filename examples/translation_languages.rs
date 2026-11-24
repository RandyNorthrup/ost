//! Print Teams' translation languages for a locale (debugging aid):
//! `cargo run --example translation_languages -- en-us`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let locale = std::env::args().nth(1).unwrap_or_else(|| "en-us".into());
    let client = TeamsClient::new().await?;
    for (code, name) in teams_cli::api::msgactions::translation_languages(&client, &locale).await? {
        println!("{code}\t{name}");
    }
    Ok(())
}
