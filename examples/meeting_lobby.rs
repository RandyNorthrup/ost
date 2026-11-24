//! Read or set who bypasses the lobby of a meeting you organize (test aid):
//! `cargo run --example meeting_lobby -- <meeting thread id> [Everyone|OrganizerOnly|…]`.
//! Without a value it prints the current one (Meeting options' AutoAdmittedUsers).
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let thread = args.next().ok_or_else(|| anyhow::anyhow!("usage: <thread id> [value]"))?;
    let client = TeamsClient::new().await?;
    let tenant = client.tenant_id().ok_or_else(|| anyhow::anyhow!("no tenant"))?;
    let me = client.object_id().ok_or_else(|| anyhow::anyhow!("no user id"))?;
    let options = match args.next() {
        Some(v) => teams_cli::api::meeting_options::set(&client, &tenant, &me, &thread, "0", &[("AutoAdmittedUsers", serde_json::json!(v))]).await?,
        None => teams_cli::api::meeting_options::get(&client, &tenant, &me, &thread, "0").await?,
    };
    for o in &options.options {
        if o["name"].as_str() == Some("AutoAdmittedUsers") {
            println!("AutoAdmittedUsers {}", o["currentValue"]);
        }
    }
    Ok(())
}
