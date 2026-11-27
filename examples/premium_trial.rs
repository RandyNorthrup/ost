//! Teams Premium trial state as Teams reads it (debugging aid; read-only):
//! `cargo run --example premium_trial`. Licensed: pass `--licensed` to read
//! the trial entity instead of the eligibility reply, as Teams does with a
//! Premium or trial licence.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let http = reqwest::Client::new();
    let licensed = std::env::args().any(|a| a == "--licensed");
    let policy = teams_cli::api::premium::policy(&http).await?;
    let trial = teams_cli::api::premium::trial(&http, licensed).await?;
    println!("policy: {policy:?}\ntrial: {trial:#?}");
    if let Some(t) = &trial {
        println!("ended: {}", t.is_ended());
    }
    Ok(())
}
