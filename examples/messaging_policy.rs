//! Print your effective Teams messaging policy (middle tier).
use teams_cli::api::client::TeamsClient;
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let v = teams_cli::api::custom_emoji::messaging_policy(&client).await?;
    println!("{}", serde_json::to_string_pretty(&v)?);
    Ok(())
}
