//! A SharePoint REST call as OneDrive's share dialog makes it (debugging
//! aid): `cargo run --example sp_post -- <url> [json body]`
//! (`SP_MERGE=1` sends it as an item update; `SP_HEADERS` adds headers).
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let url = args.first().cloned().unwrap_or_default();
    let host = url.split('/').take(3).collect::<Vec<_>>().join("/");
    let token = teams_cli::auth::oauth::access_token_for(&format!("{host}/.default")).await?;
    let req = reqwest::Client::new()
        .request(if args.len() > 1 { reqwest::Method::POST } else { reqwest::Method::GET }, &url)
        .bearer_auth(token)
        .header("accept", "application/json;odata=verbose")
        .header("content-type", "application/json;odata=verbose");
    // SP_MERGE=1 updates an item the way OneDrive's Rename does.
    let req = if std::env::var_os("SP_MERGE").is_some() {
        req.header("x-http-method", "MERGE").header("if-match", "*")
    } else {
        req
    };
    // SP_HEADERS="name: value; name: value" adds headers (as a browser sends them).
    let mut req = if let Some(b) = args.get(1) { req.body(b.clone()) } else { req };
    for h in std::env::var("SP_HEADERS").unwrap_or_default().split(';') {
        if let Some((k, v)) = h.split_once(':') {
            req = req.header(k.trim(), v.trim());
        }
    }
    let resp = req.send().await?;
    println!("{}", resp.status());
    println!("{}", resp.text().await?);
    Ok(())
}
