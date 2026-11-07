//! Forward one message and print the service's raw reply (debugging aid):
//! `cargo run --example forward_raw -- <source conv> <message id> <target conv>`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages/forward",
        client.chat_service_url(),
        a[0]
    );
    let body = serde_json::json!({
        "targetThreadIds": [a[2]],
        "messageIds": [a[1]],
        "additionalMessage": {
            "content": "", "messagetype": "RichText/Html", "contenttype": "Text",
            "clientmessageid": teams_cli::api::outbox::new_client_message_id(),
            "imdisplayname": client.display_name().unwrap_or_default(),
            "properties": { "importance": "", "formatVariant": "TEAMS" }
        },
        "templateId": "basic_forward_message_template"
    });
    let resp = client.chat_post_unchecked(&url, &body, &[]).await?;
    println!("status {}", resp.status());
    println!("{}", resp.text().await?);
    Ok(())
}
