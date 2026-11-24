//! Ask Copilot for a file's Suggested names as OneDrive's Rename does
//! (debugging aid): `cargo run --example rename_suggest -- <drive id> <item id>`
//! (or `me <path>` for a file in your OneDrive). Prints the names as they
//! stream, then the outcome.
use teams_cli::api::{client::TeamsClient, rename_suggestions};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let (drive, item) = if a[0] == "me" {
        let v: serde_json::Value = client.graph_get(&format!("/me/drive/root:/{}?$select=id,parentReference", a[1])).await?.json().await?;
        (v["parentReference"]["driveId"].as_str().unwrap_or_default().to_string(), v["id"].as_str().unwrap_or_default().to_string())
    } else {
        (a[0].clone(), a[1].clone())
    };
    let (info, origin, confidential) = rename_suggestions::file_info(&client, &drive, &item).await?;
    println!("file {} offered {} confidential {confidential}", info.file_name, rename_suggestions::offered_for(&info.file_name));
    let out = rename_suggestions::suggest(&info, &origin, "en-us", |names| println!("partial {names:?}")).await?;
    println!("outcome {out:?}");
    Ok(())
}
