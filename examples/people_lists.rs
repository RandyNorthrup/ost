//! Teams' blocked and priority-access lists (debugging aid):
//! `cargo run --example people_lists [-- priority add|remove <mri>]`.
use teams_cli::api::client::TeamsClient;
use teams_cli::api::contacts::{PeopleList, manage_people_list, people_list};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() == 3 {
        let list = if args[0] == "blocked" {
            PeopleList::Blocked
        } else {
            PeopleList::Priority
        };
        manage_people_list(&client, list, &args[2], args[1] == "add").await?;
        println!("{} {} done", args[1], args[2]);
    }
    println!(
        "blocked: {:?}",
        people_list(&client, PeopleList::Blocked).await?
    );
    println!(
        "priority: {:?}",
        people_list(&client, PeopleList::Priority).await?
    );
    Ok(())
}
