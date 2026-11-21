//! Add a channel Page tab whose page isn't made yet (no componentUrl), as a
//! New page leaves it, to see what Teams and OST do with it; or remove a
//! tab again (test aid):
//! `cargo run --example page_tab_linkless -- <channel id> <creator MRI | me> "<name>"`
//! `cargo run --example page_tab_linkless -- <channel id> --remove <tab id>`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    anyhow::ensure!(args.len() == 3, "usage: <channel id> <creator MRI|me|--remove> <name|tab id>");
    let client = teams_cli::api::client::TeamsClient::new().await?;
    if args[1] == "--remove" {
        teams_cli::api::tab_add::remove_property(&client, &args[0], &args[2]).await?;
        println!("removed {}", args[2]);
        return Ok(());
    }
    let creator = if args[1] == "me" { format!("8:orgid:{}", client.object_id().unwrap_or_default()) } else { args[1].clone() };
    let id = teams_cli::api::tab_add::add_page_tab_without_link(&client, &args[0], &creator, &args[2]).await?;
    println!("added {id}");
    Ok(())
}
