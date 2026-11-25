//! Print the app catalog's definitions whose name contains a text (debugging aid):
//! `cargo run --example catalog_find -- '<name part>'`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let part = std::env::args().nth(1).expect("name part").to_lowercase();
    let client = TeamsClient::new().await?;
    let all = teams_cli::api::app_details::catalog(&client).await?;
    println!("{} apps", all.len());
    for d in all.iter() {
        let name = d.get("name").and_then(|v| v.as_str()).unwrap_or_default();
        if name.to_lowercase().contains(&part) {
            let keep = ["id", "name", "inputExtensions", "bots", "connectors"];
            let slim: serde_json::Map<String, serde_json::Value> = d
                .as_object()
                .into_iter()
                .flatten()
                .filter(|(k, _)| keep.contains(&k.as_str()))
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect();
            println!(
                "{}",
                serde_json::to_string(&slim)?
                    .chars()
                    .take(1500)
                    .collect::<String>()
            );
        }
    }
    Ok(())
}
