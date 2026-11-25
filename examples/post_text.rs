//! Post a plain message with a delivery option into a chat (debugging aid):
//! `cargo run --example post_text -- <chat id> <text> [high|urgent]`.
//! OST_POST_HEADERS="name: value;; name: value" adds request headers;
//! OST_POST_HTML=1 sends the text as the message's HTML.
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
        // OST_POST_HTML=1 posts the text as HTML (a test link).
        "content": if std::env::var("OST_POST_HTML").as_deref() == Ok("1") {
            text.clone()
        } else {
            format!("<p>{}</p>", text.replace('&', "&amp;").replace('<', "&lt;"))
        },
        "messagetype": "RichText/Html",
        "contenttype": "text",
        "clientmessageid": now.to_string(),
        "imdisplayname": client.display_name().unwrap_or_default(),
        "properties": { "importance": importance, "formatVariant": "TEAMS" },
    });
    let extra = std::env::var("OST_POST_HEADERS").unwrap_or_default();
    let headers: Vec<(&str, &str)> = extra
        .split(";;")
        .filter_map(|h| h.split_once(':'))
        .map(|(k, v)| (k.trim(), v.trim()))
        .collect();
    let resp = client
        .chat_request_with(reqwest::Method::POST, &url, &body, &headers)
        .await?;
    println!(
        "{} {}",
        resp.status(),
        resp.headers()
            .get("location")
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
    );
    Ok(())
}
