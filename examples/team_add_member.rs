//! Add someone to one of your teams as Teams' Add member does (test aid):
//! `cargo run --example team_add_member -- "<team name>" <8:orgid:oid> [owner]`.
//! Without the person it lists the team's ids.
use anyhow::Context;
use teams_cli::api::{channels, client::TeamsClient, teams};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let name = args.first().context("team name")?;
    let team = teams::list_teams_csa(&client)
        .await?
        .into_iter()
        .find(|t| &t.name == name)
        .context("no such team")?;
    println!("{} group {} thread {}", team.name, team.id, team.thread_id);
    if let Some(mri) = args.get(1) {
        let owner = args.get(2).map(String::as_str) == Some("owner");
        let out = channels::add_team_members(&client, &team.thread_id, &team.id, &[(mri.clone(), owner)]).await?;
        println!("added {} failed {}", out.added, out.failed);
    }
    Ok(())
}
