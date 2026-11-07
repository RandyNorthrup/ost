//! Translate one chat message and print the result (debugging aid):
//! `cargo run --example translate_raw -- <conv> <message id> <target lang>`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let a: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let t = teams_cli::api::msgactions::translate(&client, &a[0], &a[1], &a[2]).await?;
    println!("{t:?}");
    Ok(())
}
