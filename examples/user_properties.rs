//! Print the chat service's user properties (debugging aid; values of
//! secrets are not printed): `cargo run --example user_properties [key]`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let key = std::env::args().nth(1);
    let client = TeamsClient::new().await?;
    let url = format!("{}/v1/users/ME/properties", client.chat_service_url());
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
