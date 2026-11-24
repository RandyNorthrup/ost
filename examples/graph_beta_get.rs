//! GET a Graph beta path and print the JSON (debugging aid):
//! `cargo run --example graph_beta_get -- '/me/settings/regionalAndLanguageSettings'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("path");
    let client = TeamsClient::new().await?;
    match client.graph_beta(&path, None).await {
        Ok(r) => println!("{}", serde_json::to_string_pretty(&r.json::<serde_json::Value>().await?)?),
        Err(e) => println!("error: {e:#}"),
    }
    Ok(())
}
