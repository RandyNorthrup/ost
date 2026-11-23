//! Print the chat service's user properties (debugging aid; values of
//! secrets are not printed): `cargo run --example user_properties [key]`.
//! `--set <key> <json>` replaces a JSON property whole (test set-up and
//! restore, e.g. placesSettings for TASK-0249's first-run banner).
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let client = TeamsClient::new().await?;
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
    if args.get(1).map(String::as_str) == Some("--set") {
        let (Some(name), Some(value)) = (args.get(2), args.get(3)) else { anyhow::bail!("--set <key> <json>") };
        let v: serde_json::Value = serde_json::from_str(value)?;
        let put = format!("{url}?name={name}");
        client.chat_request(reqwest::Method::PUT, &put, &serde_json::json!({ name: v.to_string() })).await?;
        println!("set {name} = {v}");
        return Ok(());
    }
    let key = args.get(1).cloned();
    let v: serde_json::Value = client.chat_get(&url).await?.json().await?;
    for (k, val) in v.as_object().into_iter().flatten() {
        match &key {
            Some(want) if want == k => println!("{k} = {val}"),
            Some(_) => {}
            None => println!(
                "{k}: {}",
                val.to_string().chars().take(120).collect::<String>()
            ),
        }
    }
    Ok(())
}
