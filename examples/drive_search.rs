//! The Move / Copy picker's folder search (debugging aid):
//! `cargo run --example drive_search -- [--all] [--days=N] <query>`.
use teams_cli::api::{client::TeamsClient, drive};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let all = args.first().is_some_and(|a| a == "--all");
    if all {
        args.remove(0);
    }
    let days = args.first().and_then(|a| a.strip_prefix("--days=")).and_then(|d| d.parse().ok());
    if days.is_some() {
        args.remove(0);
    }
    for h in drive::search_folders(&client, &args.join(" "), all, days).await? {
        println!("{} | {} | {} | {}", h.item.name, h.modified_text, h.created_by, h.location.join(" › "));
    }
    Ok(())
}
