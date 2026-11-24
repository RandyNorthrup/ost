//! Teams' Room audio rooms (debugging aid): Other Suggestions, or a search
//! (`cargo run --example rooms -- [query]`), through `api::rooms`, with the
//! findmeetinglocations reply's room addresses.
use teams_cli::api::{client::TeamsClient, rooms};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let query = std::env::args().nth(1);
    let found = rooms::meeting_locations(&client, 10, query.as_deref()).await?;
    println!("locations: {found:?}");
    for r in rooms::rooms(&client, query.as_deref()).await? {
        println!("room: {}  {}  {}", r.mri, r.name, r.email);
    }
    Ok(())
}
