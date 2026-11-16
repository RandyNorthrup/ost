//! Print your effective Teams policies (middle tier; debugging aid):
//! `cargo run --example messaging_policy -- [namespace ...]` (default
//! teamsMessagingPolicy).
use teams_cli::api::client::TeamsClient;
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let ns: Vec<&str> = if args.is_empty() { vec!["teamsMessagingPolicy"] } else { args.iter().map(String::as_str).collect() };
    let v = teams_cli::api::custom_emoji::effective_policies(&client, &ns).await?;
    println!("{}", serde_json::to_string_pretty(&v)?);
    Ok(())
}
