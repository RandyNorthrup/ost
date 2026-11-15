//! Add an app as Teams' Add does (debugging aid): for you, and to a chat or
//! a channel (with its team's thread id):
//! `cargo run --example add_app -- <app id> [<chat id> | <channel id> --team=<team thread id>]`,
//! or `-- <app id> --remove-from-team=<team thread id>`.
use teams_cli::api::client::TeamsClient;
use teams_cli::api::store_content::{AddTarget, add_app, remove_from_team};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let app = args.first().ok_or_else(|| anyhow::anyhow!("usage: add_app <app id> [<chat id> | <channel id> --team=<team thread id>]"))?;
    let team = args.iter().find_map(|a| a.strip_prefix("--team="));
    let conv = args.get(1).filter(|a| !a.starts_with("--"));
    let target = conv.map(|c| match team {
        Some(t) => AddTarget::Channel { channel: c, team_thread: t },
        None => AddTarget::Chat(c),
    });
    let client = TeamsClient::new().await?;
    // --remove-from-team=<team thread id>: take the app off a team instead.
    if let Some(t) = args.iter().find_map(|a| a.strip_prefix("--remove-from-team=")) {
        remove_from_team(&client, t, app).await?;
        println!("removed {app} from {t}");
        return Ok(());
    }
    let added = add_app(&client, app, target).await?;
    println!("{added:?}");
    Ok(())
}
