//! A meeting's attendance reports, as Teams' Attendance view reads them
//! (test aid): `cargo run --example attendance -- <thread> <organizer oid>
//! [<post id>]` lists the reports and prints the newest in full.
use anyhow::Context;
use teams_cli::api::{attendance, client::TeamsClient};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let thread = args.first().context("thread id")?;
    let organizer = args.get(1).context("organizer object id")?;
    let message = args.get(2).map(String::as_str);
    let reports = attendance::history(&client, thread, organizer, message).await?;
    for r in &reports {
        println!("{} {} – {} ({} attended)", r["callId"], r["startTimeUtc"], r["endTimeUtc"], r["attendeeCount"]);
    }
    if let Some(call) = reports.first().and_then(|r| r["callId"].as_str()) {
        println!("{:#}", attendance::report(&client, thread, call, organizer, message).await?);
        let (name, bytes) = attendance::file(&client, thread, call, organizer).await?;
        println!("file {name:?}, {} bytes, starts {:02x?}", bytes.len(), &bytes[..bytes.len().min(8)]);
    }
    Ok(())
}
