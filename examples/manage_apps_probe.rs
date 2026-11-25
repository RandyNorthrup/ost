//! Where Manage your apps' rows come from (debugging aid, TASK-0237): your
//! shared app entitlements and, for each of your teams, the middle tier's
//! team entitlements under the given path patterns ({t} = the team thread),
//! printed as `name | id | state`. No tokens are printed.
//! `cargo run --example manage_apps_probe -- 'beta/chats/{t}/apps/entitlements' 'beta/teams/{t}/apps/entitlements'`
use teams_cli::api::client::TeamsClient;

fn rows(v: &serde_json::Value) -> Vec<String> {
    let list = v
        .as_array()
        .cloned()
        .or_else(|| v.get("value").and_then(|x| x.as_array()).cloned())
        .unwrap_or_default();
    list.iter()
        .map(|e| {
            let s = |k: &str| e.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
            let name = if s("name").is_empty() {
                e.pointer("/appDefinition/name")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string()
            } else {
                s("name")
            };
            format!("{} | {} | {}", name, s("id"), s("state"))
        })
        .collect()
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let patterns: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let (base, token) = teams_cli::api::tabs::middle_tier(&client).await?;
    let get = |url: String| {
        let (c, t) = (client.http().clone(), token.clone());
        async move {
            let r = c.get(&url).bearer_auth(t).send().await?;
            let st = r.status();
            let v: serde_json::Value = r.json().await.unwrap_or_default();
            anyhow::Ok((st, v))
        }
    };
    let (st, v) = get(format!("{base}/beta/users/apps/entitlements")).await?;
    println!("== shared {st}");
    for r in rows(&v) {
        println!("  {r}");
    }
    let joined: serde_json::Value = client
        .graph_get("/me/joinedTeams?$select=id,displayName")
        .await?
        .json()
        .await?;
    for t in joined
        .get("value")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
    {
        let group = t.get("id").and_then(|v| v.as_str()).unwrap_or_default();
        let name = t
            .get("displayName")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let pc: serde_json::Value = client
            .graph_get(&format!("/teams/{group}/primaryChannel?$select=id"))
            .await?
            .json()
            .await?;
        let thread = pc
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        for p in &patterns {
            let path = p
                .replace("{t}", &teams_cli::api::tabs::encode_uri_component(&thread))
                .replace("{g}", group);
            let (st, v) = get(format!("{base}/{path}")).await?;
            println!("== {name} {path} {st}");
            for r in rows(&v) {
                println!("  {r}");
            }
        }
    }
    Ok(())
}
