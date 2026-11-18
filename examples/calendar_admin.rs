//! Make or delete a calendar of your own (test aid for Split view):
//! `cargo run --example calendar_admin -- create 'OST TEST …'`, `… -- delete <id>`,
//! `… -- list`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let client = TeamsClient::new().await?;
    match (args.next().as_deref(), args.next()) {
        (Some("create"), Some(name)) => println!("{}", teams_cli::api::calendar::create_calendar(&client, &name).await?),
        (Some("delete"), Some(id)) => {
            teams_cli::api::calendar::delete_calendar(&client, &id).await?;
            println!("deleted");
        }
        (Some("list"), _) => {
            for c in teams_cli::api::calendar::calendars(&client).await? {
                println!("{}\t{}\t{}", c.section, c.name, c.id);
            }
        }
        _ => anyhow::bail!("usage: create <name> | delete <id> | list"),
    }
    Ok(())
}
