//! GET a chat service aggregator (CSA) path with an AAD token for
//! chatsvcagg and print the JSON (debugging aid):
//! `cargo run --example csa_get -- api/v1/customemoji/metadata`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("path");
    let token =
        teams_cli::auth::oauth::access_token_for("https://chatsvcagg.teams.microsoft.com/.default")
            .await?;
    let url = format!("https://teams.microsoft.com/api/csa/{path}");
    let resp = reqwest::Client::new()
        .get(&url)
        .bearer_auth(&token)
        .header("x-ms-client-type", "windows")
        .send()
        .await?;
    println!("{}", resp.status());
    let text = resp.text().await?;
    match serde_json::from_str::<serde_json::Value>(&text) {
        Ok(v) => println!("{}", serde_json::to_string_pretty(&v)?),
        Err(_) => println!("{}", text.chars().take(2000).collect::<String>()),
    }
    Ok(())
}
