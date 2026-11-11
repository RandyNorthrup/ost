//! A meeting's options, as Teams' Meeting options dialog reads and saves
//! them (test aid):
//! `cargo run --example meeting_options -- <join link> [Name=Value ...]`
//! prints each option's current value and saves the given ones (a value
//! is JSON, or a bare string). `create "<subject>"` instead schedules a
//! 30-minute Teams meeting from now and prints its join link.
use anyhow::Context;
use teams_cli::api::{calendar, client::TeamsClient, meeting_options};
use teams_cli::calling::outgoing::MeetingLink;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    let first = args.first().context("a join link, or create")?;
    if first == "cleanup" {
        // Delete your own events with this exact subject (test leftovers),
        // and show what your calendar allows for online meetings.
        let subject = args.get(1).context("subject")?;
        let cal: serde_json::Value = client.graph_get("/me/calendar?$select=allowedOnlineMeetingProviders,defaultOnlineMeetingProvider").await?.json().await?;
        println!("calendar: {} / {}", cal["allowedOnlineMeetingProviders"], cal["defaultOnlineMeetingProvider"]);
        let v: serde_json::Value = client.graph_get("/me/events?$select=id,subject,isOrganizer&$top=50").await?.json().await?;
        for e in v["value"].as_array().into_iter().flatten() {
            if e["subject"].as_str() == Some(subject.as_str()) && e["isOrganizer"] == serde_json::json!(true) {
                calendar::delete_event(&client, e["id"].as_str().unwrap_or_default()).await?;
                println!("deleted {}", e["subject"]);
            }
        }
        return Ok(());
    }
    if first == "create" {
        let now = chrono::Utc::now();
        let fmt = |t: chrono::DateTime<chrono::Utc>| t.format("%Y-%m-%dT%H:%M:%S").to_string();
        let ev = calendar::create_event(&client, args.get(1).context("subject")?, &fmt(now), &fmt(now + chrono::Duration::minutes(30)), &[], true).await?;
        // Teams provisions the online meeting a moment after the event.
        let mut url = ev.join_url.unwrap_or_default();
        for _ in 0..15 {
            if !url.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            let v: serde_json::Value = client.graph_get(&format!("/me/events/{}?$select=onlineMeeting", ev.id)).await?.json().await?;
            url = v.pointer("/onlineMeeting/joinUrl").and_then(|u| u.as_str()).unwrap_or_default().to_string();
        }
        if url.is_empty() {
            let v: serde_json::Value = client.graph_get(&format!("/me/events/{}?$select=isOnlineMeeting,onlineMeetingProvider,onlineMeeting,allowNewTimeProposals", ev.id)).await?.json().await?;
            anyhow::bail!("no Teams link yet: {v}");
        }
        println!("{url}");
        return Ok(());
    }
    let link = MeetingLink::parse(first).context("not a meeting join link")?;
    let (tenant, organizer) = (link.tenant_id.clone().context("no tenant")?, link.organizer_id.clone().context("no organizer")?);
    let changes: Vec<(String, serde_json::Value)> = args[1..]
        .iter()
        .filter_map(|a| a.split_once('='))
        .map(|(k, v)| (k.to_string(), serde_json::from_str(v).unwrap_or_else(|_| serde_json::json!(v))))
        .collect();
    let options = if changes.is_empty() {
        meeting_options::get(&client, &tenant, &organizer, &link.thread_id, &link.message_id).await?
    } else {
        let c: Vec<(&str, serde_json::Value)> = changes.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
        meeting_options::set(&client, &tenant, &organizer, &link.thread_id, &link.message_id, &c).await?
    };
    for o in options {
        println!("{} = {}", o["name"].as_str().unwrap_or_default(), o["currentValue"]);
    }
    Ok(())
}
