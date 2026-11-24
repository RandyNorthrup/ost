//! Whether OST's sign-in can get a token for a resource, and its claims'
//! audience and scopes only (debugging aid): `cargo run --example token_aud -- <resource>`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    use base64::Engine;
    let resource = std::env::args().nth(1).expect("resource");
    let token = teams_cli::auth::oauth::access_token_for(&format!("{resource}/.default")).await?;
    let payload = token.split('.').nth(1).unwrap_or_default();
    let claims: serde_json::Value = serde_json::from_slice(&base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload.trim_end_matches('='))?)?;
    println!("aud={} scp={} appid={}", claims["aud"], claims["scp"], claims["appid"]);
    Ok(())
}
