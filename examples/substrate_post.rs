//! A substrate.office.com search call as Teams makes it (debugging aid):
//! `cargo run --example substrate_post -- <path?query> <json body>`, e.g.
//! `search/api/v1/suggestions?scenario=slimpicker.compose '{...}'`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let token = teams_cli::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let resp = reqwest::Client::new()
        .post(format!("https://substrate.office.com/{}", args[0]))
        .bearer_auth(token)
        .header("content-type", "application/json")
        .body(args.get(1).cloned().unwrap_or_default())
        .send()
        .await?;
    println!("{}", resp.status());
    println!("{}", resp.text().await?);
    Ok(())
}
