//! What Teams' Add a tab picker is built from (debugging aid): your apps
//! and their states, whether each has a tab for a chat, a meeting chat and
//! a channel, your apps' most-recently-used order, and, with a thread id,
//! its `meeting` and `tab::` properties.
//! `cargo run --example tab_probe -- [<thread id>] [<app id>…]`
use teams_cli::api::client::TeamsClient;
use teams_cli::api::store_content::IcKind;
use teams_cli::api::tab_add;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let apps = tab_add::your_apps(&client).await?;
    let mut ids: Vec<String> = apps.iter().map(|(i, _)| i.clone()).collect();
    ids.extend(args.iter().filter(|a| !a.starts_with("19:")).cloned());
    let defs = tab_add::definitions(&client, &ids).await?;
    for id in &ids {
        let state = apps.iter().find(|(i, _)| i == id).map(|(_, s)| s.as_str()).unwrap_or("-");
        let Some(d) = defs.get(&id.to_lowercase()) else {
            println!("{id} {state}: no definition");
            continue;
        };
        let has = |k: IcKind| if k.supports(d) { "y" } else { "n" };
        let tabs = |k: &str| d.get(k).map(|v| v.to_string()).unwrap_or_default();
        println!(
            "{id} {state} {:?} chat={} meeting={} channel={} gallery={} configurable={} static={}",
            d.get("name").and_then(|n| n.as_str()).unwrap_or(""),
            has(IcKind::TabChat),
            has(IcKind::TabMeeting),
            has(IcKind::TabChannel),
            tabs("galleryTabs").chars().take(200).collect::<String>(),
            tabs("configurableTabs").chars().take(200).collect::<String>(),
            tabs("staticTabs").chars().take(120).collect::<String>(),
        );
    }
    println!("MRU {:?}", tab_add::apps_usage(&client).await);
    if let Some(t) = args.iter().find_map(|a| a.strip_prefix("--team=")) {
        for (id, state) in teams_cli::api::store_content::channel_apps(&client, t).await? {
            if !state.is_empty() && state != "None" {
                println!("team {id} {state}");
            }
        }
        for d in tab_add::conversation_apps(&client, t).await?.iter() {
            let state = d.get("state").and_then(|s| s.as_str()).unwrap_or("");
            if !state.is_empty() && state != "None" {
                println!("conv {} {state} {:?} core={:?}", d["id"], d.get("name"), d.get("isCoreApp"));
            }
        }
    }
    if let Some(t) = args.iter().find(|a| a.starts_with("19:")) {
        let props = tab_add::thread_properties(&client, t).await?;
        let keys: Vec<&String> = props.as_object().map(|o| o.keys().collect()).unwrap_or_default();
        println!("thread keys {keys:?}");
        println!("meeting {}", props.get("meeting").map(|m| m.to_string()).unwrap_or_default());
        for k in keys.iter().filter(|k| k.starts_with("tab::")) {
            println!("{k} {}", props[k.as_str()]);
        }
    }
    Ok(())
}
