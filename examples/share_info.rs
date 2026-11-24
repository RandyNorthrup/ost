//! A file's sharing as OneDrive's share dialog reads it (debugging aid):
//! `cargo run --example share_info -- <site> <list id> <item id>`.
use teams_cli::api::sharing;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let item = sharing::ItemRef { site: a[0].clone(), list: a[1].clone(), item: a[2].clone() };
    println!("{}", serde_json::to_string_pretty(&sharing::info(&item).await?)?);
    Ok(())
}
