//! List the org's custom emoji, or delete one (debugging aid):
//! `cargo run --example custom_emoji -- [delete <name;documentId>]`.
use teams_cli::api::{client::TeamsClient, custom_emoji};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("delete") {
        custom_emoji::delete(&client, &args[1]).await?;
        println!("deleted");
    }
    let policy = custom_emoji::messaging_policy(&client).await?;
    for k in ["createCustomEmojis", "deleteCustomEmojis", "customEmojis"] {
        println!("{k}: {:?}", custom_emoji::find_bool(&policy, k));
    }
    for e in custom_emoji::list(&client).await? {
        println!("{} by {} at {}", e.id, e.creator, e.created_on);
    }
    Ok(())
}
