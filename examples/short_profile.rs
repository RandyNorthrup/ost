//! People's names by MRI, as Teams resolves them (debugging aid):
//! `cargo run --example short_profile -- [--raw] 8:orgid:<oid> [...]`.
use teams_cli::api::{client::TeamsClient, directory};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let mut mris: Vec<String> = std::env::args().skip(1).collect();
    if mris.first().map(String::as_str) == Some("--raw") {
        mris.remove(0);
        for p in directory::short_profile_records(&client, &mris).await? {
            println!("{p:#}");
        }
        return Ok(());
    }
    for (mri, name) in directory::short_profiles(&client, &mris).await? {
        println!("{mri} = {name}");
    }
    Ok(())
}
