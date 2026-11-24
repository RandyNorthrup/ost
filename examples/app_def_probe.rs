//! Print an app's definition (debugging aid): `cargo run --example app_def_probe -- <app id>`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let id = std::env::args().nth(1).expect("app id");
    let client = teams_cli::api::client::TeamsClient::new().await?;
    let d = teams_cli::api::app_details::definition(&client, &id).await?;
    println!("{}", serde_json::to_string_pretty(&d)?);
    Ok(())
}
