//! One Outlook on the web calendar action as Teams' hosted calendar sends
//! it, through OST's code (`api::calendar::owa_action`), and the raw
//! answer (debugging aid; needs the browser sign-in):
//! `cargo run --example owa_action -- RespondToCalendarEvent '<request json>'`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter("info").init();
    let mut args = std::env::args().skip(1);
    let action = args.next().expect("action");
    let body: serde_json::Value = serde_json::from_str(&args.next().expect("request json"))?;
    match teams_cli::api::calendar::owa_action(&action, &body).await {
        Ok(v) => println!(
            "ok {}",
            v.to_string().chars().take(2000).collect::<String>()
        ),
        Err(e) => println!("error: {e:#}"),
    }
    Ok(())
}
