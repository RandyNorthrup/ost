//! Fetch a message's video clip as Teams' player plays it (debugging aid):
//! `cargo run --example video_clip -- <clip url> <out.mp4> [rendition]`.
use teams_cli::api::{client::TeamsClient, video_clips};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut a = std::env::args().skip(1);
    let (url, out, rep) = (a.next().expect("clip url"), a.next().expect("out"), a.next());
    let client = TeamsClient::new().await?;
    let mpd = video_clips::manifest(&client, &url).await?;
    println!("renditions: {:?}", video_clips::renditions(&mpd));
    let bytes = video_clips::playable(&client, &url, rep.as_deref(), Some(&mpd)).await?;
    std::fs::write(&out, &bytes)?;
    println!("{} bytes", bytes.len());
    Ok(())
}
