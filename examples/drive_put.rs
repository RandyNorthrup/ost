//! Put a small text file in your OneDrive's root (debugging aid, for
//! sharing tests): `cargo run --example drive_put -- <name> <text>`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let resp = client.graph_put_bytes(&format!("/me/drive/root:/{}:/content", a[0]), a[1].clone().into_bytes(), "text/plain").await?;
    let v: serde_json::Value = resp.json().await?;
    println!("{} {} {}", v["id"], v["webUrl"], v["sharepointIds"]);
    Ok(())
}
