//! One Outlook web service request as Teams' hosted calendar sends it,
//! through OST's code (`api::calendar::ows`), and the raw answer
//! (debugging aid; needs the browser sign-in):
//! `cargo run --example ows_get -- GET ows/v1.0/OutlookOptions [body json]`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter("info").init();
    let mut args = std::env::args().skip(1);
    let method: reqwest::Method = args.next().expect("method").parse()?;
    let path = args.next().expect("path");
    let body: Option<serde_json::Value> = args.next().map(|b| serde_json::from_str(&b)).transpose()?;
    match teams_cli::api::calendar::ows(method, &path, body.as_ref()).await {
        Ok(v) => println!("ok {}", v.to_string().chars().take(4000).collect::<String>()),
        Err(e) => println!("error: {e:#}"),
    }
    Ok(())
}
