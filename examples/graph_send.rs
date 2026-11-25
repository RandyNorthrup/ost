//! Send a Graph v1.0 request with a JSON body and print the reply (test
//! data aid): `cargo run --example graph_send -- POST /me/events '{...}'`.
//! Methods: POST, PATCH, DELETE.
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let method = args.next().expect("method");
    let path = args.next().expect("path");
    let body: serde_json::Value =
        serde_json::from_str(&args.next().unwrap_or_else(|| "{}".into()))?;
    let client = TeamsClient::new().await?;
    let reply = match method.as_str() {
        "POST" => client.graph_post(&path, &body).await,
        "PATCH" => client.graph_patch(&path, &body).await,
        "DELETE" => client.graph_delete(&path).await,
        m => anyhow::bail!("unknown method {m}"),
    };
    match reply {
        Ok(r) => {
            println!("{}", r.status());
            let t = r.text().await.unwrap_or_default();
            match serde_json::from_str::<serde_json::Value>(&t) {
                Ok(v) => println!("{}", serde_json::to_string_pretty(&v)?),
                Err(_) => println!("{t}"),
            }
        }
        Err(e) => println!("error: {e:#}"),
    }
    Ok(())
}
