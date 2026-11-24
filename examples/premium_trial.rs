//! Teams Premium trial state (debugging aid; read-only):
//! `cargo run --example premium_trial`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let s = teams_cli::api::premium::state(&reqwest::Client::new()).await?;
    println!("{s:#?}\noffered: {}", s.offered());
    Ok(())
}
