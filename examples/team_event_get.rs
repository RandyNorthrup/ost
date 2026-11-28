//! GET a channel meeting from its team's calendar as Teams' form loads it
//! (middle tier GET_CHANNEL_EVENT_WITH_ICALUID) and print it (debugging aid):
//! `cargo run --example team_event_get -- <team mail> <iCalUId> <start ISO .000Z>`.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let (base, token) = teams_cli::api::tabs::middle_tier(&client).await?;
    let group = format!("smtp:{}", a[0]);
    let url = teams_cli::auth::token_hosts::service_url(
        &base,
        teams_cli::auth::token_hosts::Audience::Teams,
        &[
            "v2.0",
            "groups",
            &group,
            "calendars",
            "events",
            "iCalUId",
            &a[1],
        ],
        &[
            ("eventStartDateTime", a[2].as_str()),
            ("shouldDecryptData", "false"),
        ],
    )?;
    let r = client.http().get(url).bearer_auth(&token).send().await?;
    println!("{}", r.status());
    println!("{}", r.text().await?);
    Ok(())
}
