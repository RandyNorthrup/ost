//! List the catalog's apps that unfurl links (input extensions with
//! `messageHandlers` domains) with your entitlement state, and the ECS
//! settings link unfurling and suggested replies read (debugging aid):
//! `cargo run --example link_apps [-- <app id to dump> | <url to match>]`.
use teams_cli::api::{app_details, client::TeamsClient, ecs, link_unfurl};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let dir = std::env::temp_dir().join("ost-link-apps");
    ecs::load(&client, &dir).await?;
    for (ns, k) in [
        ("extensibility", "enableAnonymousAppBasedLink"),
        ("extensibility", "anonymousAppBasedLinkApps"),
        ("messaging", "enableSmartFilesSuggestions"),
        ("messaging", "enableSmartSchedulingSuggestions"),
        ("messaging", "enableSmartRepliesFeedback"),
        ("messaging", "enableSmartReplies"),
    ] {
        println!("ECS {ns}.{k} = {:?}", ecs::setting(ns, k));
    }
    let cat = app_details::catalog(&client).await?;
    let ents = app_details::entitlements(&client).await.unwrap_or_default();
    if let Some(arg) = std::env::args().nth(1) {
        if arg.starts_with("https://") {
            println!("match: {:?}", link_unfurl::app_for(&client, &arg).await?);
            return Ok(());
        }
        match cat
            .iter()
            .find(|d| d.get("id").and_then(|v| v.as_str()) == Some(arg.as_str()))
        {
            Some(d) => println!("{}", serde_json::to_string_pretty(d)?),
            None => println!(
                "{}",
                serde_json::to_string_pretty(&app_details::definition(&client, &arg).await?)?
            ),
        }
        return Ok(());
    }
    println!("catalog {} apps, {} entitlements", cat.len(), ents.len());
    for d in cat.iter() {
        let Some((bot, domains, anon)) = link_unfurl::link_handler(d) else {
            continue;
        };
        let id = d.get("id").and_then(|v| v.as_str()).unwrap_or_default();
        println!(
            "{id} {:?} bot={bot} anon={anon} domains={domains:?} ent={:?}",
            d.get("name").and_then(|v| v.as_str()).unwrap_or_default(),
            ents.get(&id.to_lowercase()),
        );
    }
    for (id, state) in ents.iter() {
        let name = cat
            .iter()
            .find(|d| {
                d.get("id")
                    .and_then(|v| v.as_str())
                    .map(str::to_lowercase)
                    .as_deref()
                    == Some(id.as_str())
            })
            .and_then(|d| d.get("name").and_then(|v| v.as_str()).map(str::to_string))
            .unwrap_or_default();
        println!("ENT {id} {state} {name:?}");
    }
    Ok(())
}
