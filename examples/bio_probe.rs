//! Teams' biometric service, read-only (debugging aid):
//! `cargo run --example bio_probe -- <path>` GETs `{biometricService}/<path>`
//! (e.g. `v2/voice/enroll/status?enrollmentFilter=Enrolled&checkVoiceRecording=true`).
use teams_cli::api::client::TeamsClient;

const RESOURCE: &str = "00edd498-7c0c-4e68-859c-5a55d518c9c0";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let base = client.region_endpoint("biometricService").expect("biometricService");
    let token = teams_cli::auth::oauth::access_token_for(&format!("{RESOURCE}/.default")).await?;
    for path in std::env::args().skip(1) {
        let url = format!("{base}/{}", path.trim_start_matches('/'));
        let r = client
            .http()
            .get(&url)
            .bearer_auth(&token)
            .header("x-ms-correlation-id", uuid::Uuid::new_v4().to_string())
            .header("x-ringoverride", "general")
            .header("Accept", "application/json")
            .send()
            .await?;
        let status = r.status();
        let body = r.text().await.unwrap_or_default();
        println!("{path} -> {status}\n{}", body.chars().take(1500).collect::<String>());
    }
    Ok(())
}
