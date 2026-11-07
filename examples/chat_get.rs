//! GET a chat-service path and print the JSON (debugging aid):
//! `cargo run --example chat_get -- '/v1/users/ME/conversations/<id>/rcmetadata?startTime=0&pageSize=50'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("path");
    let client = TeamsClient::new().await?;
    let url = format!("{}{}", client.chat_service_url(), path);
    let v: serde_json::Value = client.chat_get(&url).await?.json().await?;
    println!("{}", serde_json::to_string_pretty(&v)?);
    Ok(())
}
