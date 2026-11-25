//! The profile card's (Live Persona Card) strings file for each language
//! (test aid, TASK-0233): Teams loads `livepersonacardstrings_<hash>.js`
//! from res.cdn.office.net/midgard/versionless, named by Loki's card
//! configuration for the culture. Prints `{culture: url}` as JSON:
//! `cargo run --example lpc_strings -- en-us de-de …`
use anyhow::Context;
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let token =
        teams_cli::auth::oauth::access_token_for("https://loki.delve.office.com//.default").await?;
    let region = std::env::var("OST_LOKI_REGION").unwrap_or_else(|_| "nam".to_string());
    let mut out = serde_json::Map::new();
    for culture in std::env::args().skip(1) {
        let url = format!(
            "https://{region}.loki.delve.office.com/api/v1/livepersonacard/configuration?cultureName={culture}"
        );
        let r = client
            .http()
            .get(&url)
            .bearer_auth(&token)
            .header("accept", "application/json")
            .header("x-clientfeature", "LivePersonaCard")
            // Teams' card configuration names itself "MicrosoftTeams" (its
            // people config); "Teams" gets an older card build's files.
            .header(
                "x-clienttype",
                std::env::var("OST_LPC_CLIENTTYPE").unwrap_or_else(|_| "MicrosoftTeams".into()),
            )
            .header("x-clientarchitectureversion", "v2")
            .header("x-clientscenario", "GetConfiguration");
        // Test aid: extra or replacing headers, "Name: value; Name: value".
        let mut r = r;
        if let Ok(extra) = std::env::var("OST_LPC_HEADERS") {
            for kv in extra.split(';') {
                if let Some((k, v)) = kv.split_once(':') {
                    r = r.header(k.trim(), v.trim());
                }
            }
        }
        let r = r.send().await?;
        let status = r.status();
        let text = r.text().await.context("configuration")?;
        // The reply names the strings bundle somewhere in its JSON.
        let file = text
            .split('"')
            .find(|s| s.contains("livepersonacardstrings_"))
            .map(|s| s.replace("\\/", "/"))
            .unwrap_or_default();
        if file.is_empty() {
            eprintln!(
                "{culture}: {status}, no strings file ({} bytes)",
                text.len()
            );
        }
        out.insert(culture, serde_json::json!(file));
    }
    println!("{}", serde_json::Value::Object(out));
    Ok(())
}
