//! Send a bot invoke as Teams does and print the reply's shape (debugging
//! aid): `cargo run --example bot_invoke -- <chat id> <message id> <bot mri>
//! <name or -> <value json> [app id]`. Long strings in the reply are cut.
use teams_cli::api::bot_invoke::{self, Target};
use teams_cli::api::client::TeamsClient;

fn shape(v: &serde_json::Value) -> serde_json::Value {
    match v {
        serde_json::Value::Object(o) => o.iter().map(|(k, v)| (k.clone(), if k.to_lowercase().contains("token") { "<secret>".into() } else { shape(v) })).collect(),
        serde_json::Value::Array(a) => a.iter().take(6).map(shape).collect(),
        serde_json::Value::String(s) if s.len() > 120 => format!("<str {}>", s.len()).into(),
        other => other.clone(),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let target = Target {
        thread_id: a[0].clone(),
        server_message_id: a[1].clone(),
        client_message_id: String::new(),
        bot_mri: a[2].clone(),
        app_id: a.get(5).cloned().unwrap_or_default(),
        message_type: "RichText/Media_Card".into(),
    };
    let name = (a[3] != "-").then(|| a[3].clone());
    let value: serde_json::Value = serde_json::from_str(&a[4])?;
    let reply = bot_invoke::invoke(&client, &target, name.as_deref(), value, true).await?;
    println!("{}", serde_json::to_string_pretty(&shape(&reply))?);
    println!("outcome: {:?}", bot_invoke::outcome(&reply).kind());
    Ok(())
}
