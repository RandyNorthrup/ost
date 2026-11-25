//! POST JSON to a Teams middle-tier path and print the reply (debugging
//! aid): `cargo run --example mt_post -- '/beta/users/useraggregatesettings' '{"tags":["userLanguageAccountSettings"]}'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("path");
    let body: serde_json::Value = serde_json::from_str(&std::env::args().nth(2).expect("body"))?;
    let client = TeamsClient::new().await?;
    let (base, token) = teams_cli::api::tabs::middle_tier(&client).await?;
    let r = client
        .http()
        .post(format!("{base}{path}"))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?;
    println!("{} {}", r.status(), r.text().await?);
    Ok(())
}
