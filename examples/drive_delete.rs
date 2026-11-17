//! Move one of your OneDrive items to the recycle bin by id (cleanup aid
//! for test leftovers such as a test meeting's recording or notes):
//! `cargo run --example drive_delete -- '<item id>'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let id = std::env::args().nth(1).expect("item id");
    let client = TeamsClient::new().await?;
    teams_cli::api::drive::delete(&client, "", &id).await?;
    println!("deleted");
    Ok(())
}
