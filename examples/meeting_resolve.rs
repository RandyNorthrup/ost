//! Find a meeting from its ID and passcode as Teams' Join with an ID does
//! (test aid): `cargo run --example meeting_resolve -- <id> <passcode>`;
//! prints its join link.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let id = args.next().expect("meeting id");
    let passcode = args.next().expect("passcode");
    let (link, subject) = teams_cli::calling::outgoing::resolve_meeting_id(&id, &passcode).await?;
    let enc = |t: &str| t.replace(':', "%3a").replace('@', "%40");
    let ctx = match (&link.tenant_id, &link.organizer_id) {
        (Some(t), Some(o)) => {
            format!("?context=%7b%22Tid%22%3a%22{t}%22%2c%22Oid%22%3a%22{o}%22%7d")
        }
        _ => String::new(),
    };
    println!("{subject}");
    println!(
        "https://teams.microsoft.com/l/meetup-join/{}/{}{ctx}",
        enc(&link.thread_id),
        link.message_id
    );
    Ok(())
}
