//! Delete one of your calendar events by id (cleanup aid for test events):
//! `cargo run --example delete_event -- '<event id>'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let id = std::env::args().nth(1).expect("event id");
    let client = TeamsClient::new().await?;
    teams_cli::api::calendar::delete_event(&client, &id).await?;
    println!("deleted");
    Ok(())
}
