//! Settings ▸ App permissions' list (debugging aid):
//! `cargo run --example permission_apps -- <team thread,team thread>`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let teams: Vec<String> = std::env::args().nth(1).unwrap_or_default().split(',').filter(|s| !s.is_empty()).map(str::to_string).collect();
    let client = teams_cli::api::client::TeamsClient::new().await?;
    for a in teams_cli::api::app_details::permission_apps(&client, &teams, &[]).await? {
        println!("{} {:?}", a.name, a.permissions.iter().map(|p| p.kind.as_str()).collect::<Vec<_>>());
    }
    Ok(())
}
