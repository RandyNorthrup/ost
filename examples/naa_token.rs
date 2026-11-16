//! Teams' broker (NAA) from OST's browser sign-in: mint a token for an
//! embedded app and print what it is for (never the token).
//! usage: OST_PROFILE=<signed-in profile> cargo run --example naa_token -- <app client id> <app origin> "<scopes>"
use base64::Engine as _;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let (app, origin, scope) = (args.get(1).expect("app client id"), args.get(2).expect("app origin"), args.get(3).expect("scopes"));
    let (token, exp) = teams_cli::auth::brokered_token(app, origin, scope, None).await?;
    let payload = token.split('.').nth(1).unwrap_or_default();
    let claims: serde_json::Value = serde_json::from_slice(&base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload.trim_end_matches('='))?)?;
    println!("ok: aud={} appid={} scp={} expires_in={:?}", claims["aud"], claims["appid"], claims["scp"], exp);
    Ok(())
}
