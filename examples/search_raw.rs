//! A search tab's raw reply, as the search page sends it (debugging aid):
//! `cargo run --example search_raw -- <tab> <keywords>`.
use teams_cli::api::{client::TeamsClient, find, search};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (tab, keywords) = (args.first().cloned().unwrap_or_default(), args[1..].join(" "));
    let oid = client.object_id().unwrap_or_default();
    let tenant = client.tenant_id().unwrap_or_default();
    let anchor = format!("OID:{oid}@{tenant}");
    for body in search::bodies(&tab, &keywords, &search::Filters::default(), 0, &find::local_timezone(), &oid, &tenant) {
        println!("{:#}", find::search_raw(&body, &anchor).await?);
    }
    Ok(())
}
