//! Talk to the chat service's drafts resource as Teams does (debugging aid):
//! `cargo run --example drafts_raw -- GET`                      list `v1/users/ME/drafts`
//! `cargo run --example drafts_raw -- POST body.json`           create a draft
//! `cargo run --example drafts_raw -- PUT <id> body.json`       replace one
//! `cargo run --example drafts_raw -- DELETE <id>`              delete one
//! Prints the status, the Location header and the reply.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let method = args.first().map(String::as_str).unwrap_or("GET").to_ascii_uppercase();
    let client = TeamsClient::new().await?;
    let base = format!("{}/v1/users/ME/drafts", client.chat_service_url());
    let read = |p: &str| -> anyhow::Result<serde_json::Value> { Ok(serde_json::from_str(&std::fs::read_to_string(p)?)?) };
    let resp = match method.as_str() {
        "GET" => client.chat_get(&format!("{base}?pageSize=200")).await?,
        "POST" => client.chat_post(&base, &read(&args[1])?).await?,
        "PUT" => client.chat_request(reqwest::Method::PUT, &format!("{base}/{}", args[1]), &read(&args[2])?).await?,
        "DELETE" => client.chat_request(reqwest::Method::DELETE, &format!("{base}/{}", args[1]), &serde_json::Value::Null).await?,
        m => anyhow::bail!("unknown method {m}"),
    };
    println!("status {}", resp.status());
    if let Some(l) = resp.headers().get("location") {
        println!("location {}", l.to_str().unwrap_or_default());
    }
    let text = resp.text().await?;
    match serde_json::from_str::<serde_json::Value>(&text) {
        Ok(v) => println!("{}", serde_json::to_string_pretty(&v)?),
        Err(_) => println!("{text}"),
    }
    Ok(())
}
