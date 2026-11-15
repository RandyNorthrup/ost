//! Print a region GTM endpoint by key (debugging aid):
//! `cargo run --example region_gtm -- biometricService`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    for key in std::env::args().skip(1) {
        println!("{key} = {:?}", client.region_endpoint(&key));
    }
    Ok(())
}
