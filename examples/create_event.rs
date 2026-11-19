//! Schedule a Teams meeting in your calendar (test aid; delete it again
//! with `delete_event`): `cargo run --example create_event -- '<subject>'
//! <start UTC YYYY-MM-DDTHH:MM:SSZ> <end> [attendee e-mail ...]`. Prints the
//! event's id and join link.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    anyhow::ensure!(args.len() >= 3, "usage: create_event <subject> <start> <end> [attendees...]");
    let client = TeamsClient::new().await?;
    let e = teams_cli::api::calendar::create_event(&client, &args[0], &args[1], &args[2], &args[3..], true).await?;
    println!("{}\n{}", e.id, e.join_url.unwrap_or_default());
    Ok(())
}
