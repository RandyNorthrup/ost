//! Print a chat's newest raw messages (debugging aid):
//! `cargo run --example raw_messages -- <chat id> [text filter]`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let chat = args.next().expect("chat id");
    let filter = args.next().unwrap_or_default();
    let client = TeamsClient::new().await?;
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages?view=msnp24Equivalent&pageSize=30&startTime=1",
        client.chat_service_url(),
        chat
    );
    let v: serde_json::Value = client.chat_get(&url).await?.json().await?;
    for m in v["messages"].as_array().into_iter().flatten() {
        if m["content"].as_str().unwrap_or("").contains(&filter) {
            println!("{}", serde_json::to_string_pretty(m)?);
        }
    }
    Ok(())
}
