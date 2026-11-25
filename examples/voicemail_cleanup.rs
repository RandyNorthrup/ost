//! Your voicemails from one caller since a time (test cleanup): lists
//! them, and with `--delete` deletes them. Prints subjects and times only.
//! `cargo run --example voicemail_cleanup -- "<caller name>" <since ISO> [--delete]`
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let caller = args.get(1).expect("caller name").to_lowercase();
    let since = args.get(2).expect("since").clone();
    let delete = args.iter().any(|a| a == "--delete");
    let client = TeamsClient::new().await?;
    let path = format!(
        "/me/messages?$filter=receivedDateTime%20ge%20{since}&$select=id,subject,receivedDateTime,from&$top=50&$orderby=receivedDateTime%20desc"
    );
    let v: serde_json::Value = client.graph_beta(&path, None).await?.json().await?;
    for m in v["value"].as_array().into_iter().flatten() {
        let subject = m["subject"].as_str().unwrap_or_default();
        let from = m
            .pointer("/from/emailAddress/name")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_lowercase();
        let voicemail = subject.to_lowercase().starts_with("voicemail")
            || subject.to_lowercase().contains("voice mail");
        println!(
            "{} | {} | from {} | voicemail {}",
            m["receivedDateTime"].as_str().unwrap_or_default(),
            subject,
            from,
            voicemail
        );
        if delete
            && voicemail
            && (from.contains(&caller) || subject.to_lowercase().contains(&caller))
        {
            let id = m["id"].as_str().unwrap_or_default();
            match client.graph_delete(&format!("/me/messages/{id}")).await {
                Ok(r) => println!("  deleted ({})", r.status()),
                Err(e) => println!("  delete failed: {e:#}"),
            }
        }
    }
    Ok(())
}
