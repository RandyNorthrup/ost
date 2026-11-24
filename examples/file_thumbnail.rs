//! A file's search-card thumbnail, as Teams fetches it (debugging aid):
//! `cargo run --example file_thumbnail -- <file url> [out.png]`.
use teams_cli::api::{client::TeamsClient, files};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let mut args = std::env::args().skip(1);
    let url = args.next().unwrap_or_default();
    match files::thumbnail(&client, &url).await? {
        Some(bytes) => {
            println!("{} bytes", bytes.len());
            if let Some(out) = args.next() {
                std::fs::write(out, bytes)?;
            }
        }
        None => println!("no thumbnail"),
    }
    Ok(())
}
