//! Post a card message as a message extension does (`RichText/Html` with
//! `properties.cards`; users may not send `RichText/Media_Card`) into a chat,
//! for comparing renderers (debugging aid):
//! `cargo run --example post_card -- <chat id> <card.json> [type]`.
//! The JSON file is the card's content; `type` defaults to
//! `application/vnd.microsoft.card.adaptive`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let chat = args.next().expect("chat id");
    let file = args.next().expect("card json");
    let content_type = args
        .next()
        .unwrap_or_else(|| "application/vnd.microsoft.card.adaptive".into());
    let card: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(file)?)?;
    let id = format!("ostcard{}", std::process::id());
    let cards =
        serde_json::json!([{ "cardClientId": id, "contentType": content_type, "content": card }]);
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
        "content": format!("<span itemid=\"{id}\" itemscope=\"\" itemtype=\"http://schema.skype.com/InputExtension\"><span itemprop=\"cardId\" content=\"{id}\"></span></span>"),
        "messagetype": "RichText/Html",
        "contenttype": "text",
        "clientmessageid": now.to_string(),
        "imdisplayname": client.display_name().unwrap_or_default(),
        "properties": { "cards": cards.to_string(), "formatVariant": "TEAMS" },
    });
    let resp = client
        .chat_request(reqwest::Method::POST, &url, &body)
        .await?;
    println!("{}", resp.status());
    Ok(())
}
