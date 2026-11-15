//! Teams' ringtone for your calls (debugging aid): `cargo run --example
//! ringtone -- [Ring|Bop|…]` sets it (when given), then prints the setting.
use teams_cli::api::{client::TeamsClient, preferences};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    if let Some(name) = std::env::args().nth(1) {
        let current = preferences::ringtone_settings(&client).await?;
        let body = preferences::ringtone_body(&current, &name);
        preferences::set_voice_setting(&client, "ringtone", &body).await?;
    }
    println!("{}", preferences::ringtone_settings(&client).await?);
    Ok(())
}
