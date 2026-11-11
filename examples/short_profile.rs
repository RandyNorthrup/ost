//! People's names by MRI, as Teams resolves them (debugging aid):
//! `cargo run --example short_profile -- 8:orgid:<oid> [...]`.
use teams_cli::api::{client::TeamsClient, directory};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let mris: Vec<String> = std::env::args().skip(1).collect();
    for (mri, name) in directory::short_profiles(&client, &mris).await? {
        println!("{mri} = {name}");
    }
    Ok(())
}
