//! Delete your own test message as Teams does (a soft delete; debugging
//! aid): `cargo run --example delete_message -- <chat id> <message id>`.
use teams_cli::api::{client::TeamsClient, messages};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let chat = args.next().expect("chat id");
    let id = args.next().expect("message id");
    let client = TeamsClient::new().await?;
    messages::delete_message(&client, &chat, &id).await?;
    println!("deleted {id}");
    Ok(())
}
