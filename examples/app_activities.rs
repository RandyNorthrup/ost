//! The apps with activity notifications (Settings ▸ Notifications ▸ Apps)
//! and their activity types, your saved Graph-app notification settings,
//! and the voice admin settings' delegation and intelligent call
//! delegation keys (debugging aid): `cargo run --example app_activities`.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = teams_cli::api::client::TeamsClient::new().await?;
    let ents = teams_cli::api::app_details::entitlements(&client).await?;
    let mut ids: Vec<String> = ents.keys().cloned().collect();
    for core in [
        "981bbfd0-5eb8-4393-8158-bfff69d2d6b5",
        "5db56dd0-534d-467b-aeda-d622bee2574a",
    ] {
        if !ids.iter().any(|i| i == core) {
            println!("not entitled: {core}");
            ids.push(core.to_string());
        }
    }
    for chunk in ids.chunks(40) {
        for d in teams_cli::api::app_details::definitions(&client, chunk).await? {
            let id = d["id"].as_str().unwrap_or_default();
            if id.is_empty() {
                let s = d.to_string();
                let i = s.find("ctivit").unwrap_or(0);
                println!(
                    "CORE {id} keys {:?} … {}",
                    d.as_object().map(|o| o.keys().cloned().collect::<Vec<_>>()),
                    &s[i.saturating_sub(30)..(i + 1500).min(s.len())]
                );
            }
            let acts = d.pointer("/activities/activityItems");
            if let Some(a) = acts.and_then(|a| a.as_array()).filter(|a| !a.is_empty()) {
                let types: Vec<String> = a
                    .iter()
                    .map(|t| {
                        format!(
                            "{}={}",
                            t["type"].as_str().unwrap_or("?"),
                            t["description"].as_str().unwrap_or("")
                        )
                    })
                    .collect();
                println!(
                    "APP {} {} [{}] {:?}",
                    d["id"].as_str().unwrap_or("?"),
                    d["name"]
                        .as_str()
                        .or(d.pointer("/name/short").and_then(|x| x.as_str()))
                        .unwrap_or("?"),
                    ents.get(d["id"].as_str().unwrap_or(""))
                        .cloned()
                        .unwrap_or_default(),
                    types
                );
            }
        }
    }
    let url = format!(
        "{}/v1/users/ME/conversations/48:notifications/messages?pageSize=200&view=msnp24Equivalent",
        client.chat_service_url()
    );
    let feed: serde_json::Value = client.chat_get(&url).await?.json().await?;
    for m in feed["messages"].as_array().into_iter().flatten() {
        let a = &m["properties"]["activity"];
        let a: serde_json::Value = a
            .as_str()
            .and_then(|s| serde_json::from_str(s).ok())
            .unwrap_or_else(|| a.clone());
        let keys: Vec<String> = a
            .as_object()
            .map(|o| {
                o.iter()
                    .filter(|(k, _)| k.to_lowercase().contains("app"))
                    .map(|(k, v)| format!("{k}={v}"))
                    .collect()
            })
            .unwrap_or_default();
        if a["activityType"] == "msGraph" {
            println!(
                "RAW {}",
                a.to_string().chars().take(900).collect::<String>()
            );
        }
        if !keys.is_empty() {
            println!(
                "FEED {} {} {:?}",
                a["activityType"], a["activitySubtype"], keys
            );
        }
    }
    let props = teams_cli::api::preferences::all_properties(&client).await?;
    println!(
        "userGraphSettings {}",
        props
            .get("userGraphSettings")
            .map(|v| v.to_string())
            .unwrap_or_default()
    );
    println!("callViewMode {:?}", props.get("callViewMode"));
    let admin = teams_cli::api::preferences::voice_admin_settings(&client).await?;
    println!("delegationSettings {}", admin["delegationSettings"]);
    let pa = &admin["personalAttendantSettings"];
    println!(
        "personalAttendant keys {:?} isEnabled {}",
        pa.as_object()
            .map(|o| o.keys().cloned().collect::<Vec<_>>()),
        pa["isEnabled"]
    );
    let pol = teams_cli::api::custom_emoji::effective_policies(
        &client,
        &["teamsPersonalAttendantPolicy"],
    )
    .await?;
    println!("policy {}", pol);
    Ok(())
}
