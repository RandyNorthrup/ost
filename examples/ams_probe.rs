//! Which views of a media-store (AMS) object OST can read, with each
//! reply's status, type and size (debugging aid; prints no secrets):
//! `cargo run --example ams_probe -- <object id> [view …]`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let id = args.next().expect("object id");
    let mut views: Vec<String> = args.collect();
    if views.is_empty() {
        views = ["", "views/video.mpd", "views/video", "views/original", "views/thumbnail", "views/thumbnail_resized?v=1", "views/video/status", "views/transcript/status"]
            .iter().map(|s| s.to_string()).collect();
    }
    let client = TeamsClient::new().await?;
    let base = client.ams_url().expect("ams");
    for v in views {
        let url = format!("{base}/v1/objects/{id}/{v}");
        match client.ams_get(&url).await {
            Ok(b) => {
                let head = String::from_utf8_lossy(&b[..b.len().min(4000)]).to_string();
                let text = head.chars().all(|c| !c.is_control() || c == '\n' || c == '\r' || c == '\t');
                println!("{v}: {} bytes{}", b.len(), if text { format!("\n{head}") } else { format!(" (binary, starts {:02x?})", &b[..b.len().min(12)]) });
            }
            Err(e) => println!("{v}: {}", e.to_string().lines().next().unwrap_or_default()),
        }
    }
    Ok(())
}
