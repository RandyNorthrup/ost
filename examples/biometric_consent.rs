//! Teams' biometric settings in the middle tier (passive enrollment
//! consent), read-only (debugging aid): `cargo run --example biometric_consent`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let (base, token) = teams_cli::api::tabs::middle_tier(&client).await?;
    let url = format!(
        "{base}/beta/users/getUserBiometricSettings/tenant/{}/user/{}",
        client.tenant_id().unwrap_or_default(),
        client.object_id().unwrap_or_default()
    );
    let r = client.http().get(&url).bearer_auth(&token).send().await?;
    println!("{} {}", r.status(), r.text().await.unwrap_or_default());
    Ok(())
}
