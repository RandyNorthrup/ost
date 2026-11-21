//! List your audio recaps (Teams' podcasts) and delete the test ones (test
//! aid): `cargo run --example podcast_delete -- [region] [--delete]` lists
//! each id, status and meeting subject; with --delete it deletes those made
//! from "OST TEST …" meetings, as Teams' deletePodcasts does.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let region = args.iter().find(|a| !a.starts_with("--")).cloned().unwrap_or_else(|| "us".into());
    let list = teams_cli::api::recaps::podcasts(&region).await?;
    let mut test = Vec::new();
    for p in list["items"].as_array().into_iter().flatten() {
        let subject = p.pointer("/params/eventsWithTranscripts/0/event/subject").and_then(|s| s.as_str()).unwrap_or_default();
        let id = p["id"].as_str().unwrap_or_default();
        println!("{id} {} {subject}", p["status"].as_str().unwrap_or_default());
        if subject.starts_with("OST TEST") && !id.is_empty() {
            test.push(id.to_string());
        }
    }
    if args.iter().any(|a| a == "--delete") && !test.is_empty() {
        let deleted = teams_cli::api::podcast::delete(&test, "en-us").await?;
        println!("deleted {} of {}", deleted.len(), test.len());
    }
    Ok(())
}
