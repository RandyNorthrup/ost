//! GET a Teams middle-tier path and print the reply (debugging aid):
//! `cargo run --example mt_get -- '/beta/users/languageAccountSettings'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("path");
    let client = TeamsClient::new().await?;
    let (base, token) = teams_cli::api::tabs::middle_tier(&client).await?;
    let r = client
        .http()
        .get(format!("{base}{path}"))
        .bearer_auth(&token)
        .send()
        .await?;
    println!("{} {}", r.status(), r.text().await?);
    Ok(())
}
