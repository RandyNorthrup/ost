//! The user's registrar registrations, as Better Together's discover sees
//! them (debugging aid for TASK-0162): `cargo run --example bt_registrar --
//! [<registrar url>]`. Trouter paths are shown without their socket ids.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let token = client.skype_token_value()?;
    // `--delete <id>...`: unregister those registrations (test leftovers).
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--delete") {
        for id in &args[1..] {
            let url = format!(
                "https://communications.svc.cloud.microsoft/registrar/noam/v3/registrations/{id}"
            );
            let r = client
                .http()
                .delete(&url)
                .header("X-Skypetoken", &token)
                .send()
                .await?;
            println!("DELETE {id}: {}", r.status());
        }
        return Ok(());
    }
    let urls: Vec<String> = match std::env::args().nth(1) {
        Some(u) => vec![u],
        None => vec![
            "https://communications.svc.cloud.microsoft/registrar/noam/v3/registrations".into(),
            "https://prod.registrar.skype.com/v2/registrations".into(),
        ],
    };
    let scrub = |s: &str| {
        let re = regex::Regex::new(r"/v4/f/[^/]+").unwrap();
        re.replace(s, "/v4/f/<id>").to_string()
    };
    for url in urls {
        let r = client
            .http()
            .get(&url)
            .header("X-Skypetoken", &token)
            .send()
            .await?;
        let status = r.status();
        let text = r.text().await.unwrap_or_default();
        println!("== GET {url}: {status}");
        let v: serde_json::Value = serde_json::from_str(&text)
            .unwrap_or(serde_json::Value::String(text.chars().take(400).collect()));
        let list = v
            .get("registrations")
            .cloned()
            .or_else(|| v.as_array().map(|a| serde_json::Value::Array(a.clone())));
        match list.and_then(|l| l.as_array().cloned()) {
            Some(regs) => {
                for reg in regs {
                    let mut reg = reg.clone();
                    if let Some(t) = reg.pointer_mut("/transports") {
                        let s = scrub(&t.to_string());
                        *t = serde_json::from_str(&s).unwrap_or_default();
                    }
                    println!("{}", serde_json::to_string(&reg)?);
                }
            }
            None => println!("{}", scrub(&v.to_string())),
        }
    }
    Ok(())
}
