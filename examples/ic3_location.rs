//! Workplace check-in's location service (TASK-0149): the tenant's office
//! networks (SSID allow list) and, with `--report <bssid> [ssid]`, what the
//! service makes of a network. Prints statuses and replies, never tokens.
//! `cargo run --example ic3_location [--report <bssid> [ssid]]`
use teams_cli::api::{client::TeamsClient, places};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let epid = uuid::Uuid::new_v4().to_string();
    match places::ssid_allow_list(&client, &epid).await {
        Ok(list) => println!("SSID allow list: {} entries {:?}", list.len(), list),
        Err(e) => println!("SSID allow list failed: {e:#}"),
    }
    let args: Vec<String> = std::env::args().collect();
    if let Some(i) = args.iter().position(|a| a == "--report") {
        let bssid = args.get(i + 1).cloned().unwrap_or_default();
        let ssid = args.get(i + 2).cloned();
        let body = places::network_body(&bssid, ssid.as_deref(), jiff::Timestamp::now());
        match places::report_network(&client, &epid, &body).await {
            Ok(r) => println!("report: {r:?}"),
            Err(e) => println!("report failed: {e:#}"),
        }
    }
    Ok(())
}
