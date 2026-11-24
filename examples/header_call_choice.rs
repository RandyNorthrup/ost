//! Set the 1:1 chat header's remembered call choice (Teams'
//! mruChatHeaderCallOption), as a test aid: `cargo run --example
//! header_call_choice -- audio|video`.
use teams_cli::api::{client::TeamsClient, preferences};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let video = std::env::args().nth(1).as_deref() == Some("video");
    let client = TeamsClient::new().await?;
    preferences::update_personal_settings(&client, &preferences::header_call_patch(video)).await?;
    let now = preferences::personal_settings(&client).await?;
    println!("video call: {}", preferences::header_call_is_video(&now));
    Ok(())
}
