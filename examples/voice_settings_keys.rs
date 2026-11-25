//! The keys of Teams' voice settings, and any ringtone in them (debugging
//! aid): `cargo run --example voice_settings_keys`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = teams_cli::api::client::TeamsClient::new().await?;
    let v = teams_cli::api::preferences::voice_settings(&client).await?;
    let keys: Vec<&String> = v
        .as_object()
        .map(|o| o.keys().collect())
        .unwrap_or_default();
    println!("{keys:?}");
    let s = v.to_string();
    if let Some(i) = s.find("ingtone") {
        println!("{}", &s[i.saturating_sub(40)..(i + 300).min(s.len())]);
    }
    Ok(())
}
