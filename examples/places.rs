//! Microsoft Places as Teams reads it (debugging aid): the tenant's
//! buildings (findPlaces, or `--new` for Teams' getBuildings flight), the
//! raw records for a filter, or one building by id:
//! `cargo run --example places -- [--new | --raw '<filter>' | --id <id>]`.
use teams_cli::api::{client::TeamsClient, places};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("--raw") => {
            let filter = args.get(1).map(String::as_str).unwrap_or(places::BUILDINGS_FILTER);
            for p in places::find_places(&client, filter).await? {
                println!("{p:#}");
            }
            return Ok(());
        }
        Some("--raw-new") => {
            for p in places::get_buildings(&client).await? {
                println!("{p:#}");
            }
            return Ok(());
        }
        Some("--id") => {
            println!("{:?}", places::building_by_id(&client, args.get(1).map(String::as_str).unwrap_or_default()).await?);
            return Ok(());
        }
        _ => {}
    }
    let new_api = args.first().map(String::as_str) == Some("--new");
    for b in places::buildings(&client, new_api).await? {
        println!("{}  {}  ({}, {}, {})", b.id, b.name, b.city, b.state, b.country);
    }
    Ok(())
}
