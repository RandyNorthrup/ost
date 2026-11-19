//! Town halls and webinars for live tests (test aid; never invites anyone
//! but the OST test accounts):
//! - `virtual_event create <Townhall|Webinar> '<title>' <start> <end>
//!   [--registration] [--open] [--attendee <upn>]... [--presenter <upn>]...`
//!   saves a draft (green room and Q&A on, Teams' defaults otherwise) and
//!   prints its id and join link. Without `--open` it is Private (only the
//!   people named); with it, people in your organization.
//! - `virtual_event publish|overview|cancel <id>`; `virtual_event manage`.
use anyhow::{Context, bail, ensure};
use teams_cli::api::{client::TeamsClient, events};

/// The only people a test event may name.
const TEST_ACCOUNTS: [&str; 3] = [
    "ost-test1@scnetsolutions.com",
    "ost-test2@scnetsolutions.com",
    "ost-test3@scnetsolutions.com",
];

async fn person(client: &TeamsClient, upn: &str) -> anyhow::Result<events::Person> {
    ensure!(TEST_ACCOUNTS.contains(&upn.to_lowercase().as_str()), "{upn} is not a test account");
    let u: serde_json::Value = client
        .graph_get(&format!("/users/{upn}?$select=id,displayName,userPrincipalName"))
        .await?
        .json()
        .await?;
    let id = u["id"].as_str().context("user id")?;
    Ok(events::Person {
        name: u["displayName"].as_str().unwrap_or(upn).to_string(),
        email: upn.to_string(),
        mri: format!("8:orgid:{id}"),
        object_id: id.to_string(),
        tenant_id: client.tenant_id().unwrap_or_default(),
        upn: upn.to_string(),
        user_type: "ADUser".into(),
        ..Default::default()
    })
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("create") => {
            ensure!(args.len() >= 5, "create <Townhall|Webinar> <title> <start> <end> [...]");
            ensure!(args[2].starts_with("OST TEST"), "test events are named OST TEST ...");
            let town_hall = args[1] == "Townhall";
            let mut e = events::NewEvent {
                event_type: args[1].clone(),
                title: args[2].clone(),
                start: args[3].clone(),
                end: args[4].clone(),
                access: "Private".into(),
                green_room: true,
                qna: true,
                ..Default::default()
            };
            if town_hall {
                e.capacity = 3000;
                e.large_audience = true;
            } else {
                (e.allow_mic, e.allow_camera, e.reactions, e.chat) = (true, true, true, true);
            }
            let mut i = 5;
            while i < args.len() {
                match args[i].as_str() {
                    "--registration" => e.registration = true,
                    "--open" => e.access = "Organization".into(),
                    "--attendee" => {
                        i += 1;
                        e.attendees.push(person(&client, args.get(i).context("upn")?).await?);
                    }
                    "--presenter" => {
                        i += 1;
                        e.presenters.push(person(&client, args.get(i).context("upn")?).await?);
                    }
                    other => bail!("unknown option {other}"),
                }
                i += 1;
            }
            let d = events::create_draft(&client, &e).await?;
            let id = d["id"].as_str().unwrap_or_default().to_string();
            println!("{id}");
            let o = events::overview(&client, &id).await?;
            println!("{}", o["card"]["join_url"].as_str().unwrap_or_default());
        }
        Some("publish") => println!("{}", events::publish(&client, args.get(1).context("id")?).await?),
        Some("overview") => println!("{:#}", events::overview(&client, args.get(1).context("id")?).await?),
        Some("cancel") => {
            events::cancel(&client, args.get(1).context("id")?).await?;
            println!("cancelled");
        }
        Some("manage") => println!("{:#}", events::manage(&client).await?),
        Some("discoverable") => {
            let on = args.get(2).map(String::as_str) == Some("on");
            println!("{}", events::set_discoverable(&client, args.get(1).context("id")?, on).await?);
        }
        // PATCH an event with a JSON body (Teams' updateVirtualEvent).
        Some("patch") => {
            let body: serde_json::Value = serde_json::from_str(args.get(2).context("json body")?)?;
            events::patch(&client, args.get(1).context("id")?, &body).await?;
            println!("patched");
        }
        // Discover's lists as you see them (titles, ids, discoverable).
        Some("discover") => {
            let d = events::discover(&client, &events::DiscoverFilter::default()).await?;
            for list in ["now", "upcoming", "past"] {
                for c in d[list].as_array().into_iter().flatten() {
                    println!("{list}: {} | {} | {}", c["title"].as_str().unwrap_or_default(), c["id"].as_str().unwrap_or_default(), c["start"].as_str().unwrap_or_default());
                }
            }
        }
        // Your registration for an event (Teams' get-virtual-event-
        // attendee-registration-by-user).
        Some("registration") => println!("{:#}", events::my_registration(&client, args.get(1).context("id")?).await?),
        // Remove the calendar entries test events left (cancelled copies
        // included) whose subject contains the given "OST TEST …" text.
        Some("purge") => {
            let needle = args.get(1).context("text")?;
            ensure!(needle.starts_with("OST TEST"), "only OST TEST entries");
            let v: serde_json::Value = client.graph_get("/me/events?$select=id,subject&$top=100&$orderby=createdDateTime desc").await?.json().await?;
            for e in v["value"].as_array().into_iter().flatten() {
                let subject = e["subject"].as_str().unwrap_or_default();
                if subject.contains(needle.as_str()) {
                    teams_cli::api::calendar::delete_event(&client, e["id"].as_str().unwrap_or_default()).await?;
                    println!("deleted {subject}");
                }
            }
        }
        _ => bail!("create | publish | overview | cancel | manage | discoverable | registration | purge"),
    }
    Ok(())
}
