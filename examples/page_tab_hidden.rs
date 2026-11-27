//! Set or clear a channel's `defaultTabHiddenApps::ChannelPageTab` flag
//! (Teams keeps the stand-in Page away while it's set; test aid):
//! `cargo run --example page_tab_hidden -- <channel id> on|off`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    anyhow::ensure!(
        args.len() == 2 && matches!(args[1].as_str(), "on" | "off"),
        "usage: <channel id> on|off"
    );
    let client = teams_cli::api::client::TeamsClient::new().await?;
    teams_cli::api::tab_add::put_thread_flag(
        &client,
        &args[0],
        teams_cli::api::tabs::PAGE_HIDDEN_PROPERTY,
        args[1] == "on",
    )
    .await?;
    println!("{} {}", teams_cli::api::tabs::PAGE_HIDDEN_PROPERTY, args[1]);
    Ok(())
}
