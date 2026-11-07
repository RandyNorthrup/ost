//! Post a plain message with a delivery option into a chat (debugging aid):
//! `cargo run --example post_text -- <chat id> <text> [high|urgent]`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let chat = args.next().expect("chat id");
    let text = args.next().expect("text");
    let importance = args.next().unwrap_or_default();
    let client = TeamsClient::new().await?;
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages",
        client.chat_service_url(),
        chat
    );
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_millis();
    let body = serde_json::json!({
        "content": format!("<p>{}</p>", text.replace('&', "&amp;").replace('<', "&lt;")),
        "messagetype": "RichText/Html",
        "contenttype": "text",
        "clientmessageid": now.to_string(),
        "imdisplayname": client.display_name().unwrap_or_default(),
        "properties": { "importance": importance, "formatVariant": "TEAMS" },
    });
    let resp = client
        .chat_request(reqwest::Method::POST, &url, &body)
        .await?;
    println!("{}", resp.status());
    Ok(())
}
