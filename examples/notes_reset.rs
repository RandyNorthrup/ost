//! Put a channel's Notes tab back to its first-opening state, to test the
//! Notes provisioning again (docs/spec/app-host.md): the tab's thread
//! property pointed at OneNote's ChannelNotes page with entityId NOTES (in
//! the form Teams writes tabs; the chat service refuses the original
//! `isUnconfigured` form), and the channel's section file removed from the
//! team notebook (Site Assets/<Team> Notebook/<channel>.one).
//! usage: OST_PROFILE=<profile> cargo run --example notes_reset -- <channel thread> <tab id> <group id> <channel name> [--keep-section]
use teams_cli::api::client::TeamsClient;

const CHANNEL_NOTES: &str = "https://www.onenote.com/teams/ChannelNotes?ui={locale}&tenantId={tid}&upn={upn}&groupId={groupId}&theme={theme}&entityId={entityId}&subEntityId={subEntityId}&sessionId={sessionId}&ringId={ringId}&teamSiteUrl={teamSiteUrl}&channelType={channelType}&trackingId={appSessionId}&hostClientType={hostClientType}&channelName={channelName}&teamType={teamType}";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let a: Vec<String> = std::env::args().collect();
    anyhow::ensure!(a.len() >= 5, "usage: notes_reset <channel thread> <tab id> <group id> <channel name> [--keep-section]");
    let (thread, tab, group, name) = (&a[1], &a[2], &a[3], &a[4]);
    let client = TeamsClient::new().await?;
    let settings = serde_json::json!({"entityId": "NOTES", "contentUrl": CHANNEL_NOTES, "websiteUrl": "https://www.onenote.com", "removeUrl": ""});
    teams_cli::api::tab_add::set_settings(&client, thread, tab, &settings).await?;
    println!("tab reset to ChannelNotes");
    if a.iter().any(|x| x == "--keep-section") {
        return Ok(());
    }
    // Site Assets is hidden from the site's drive list; its list is
    // addressed by title.
    let site: serde_json::Value = client.graph_get(&format!("/groups/{group}/sites/root?$select=id")).await?.json().await?;
    let site = site["id"].as_str().unwrap_or_default().to_string();
    let d: serde_json::Value = client.graph_get(&format!("/sites/{site}/lists/Site%20Assets/drive?$select=id")).await?.json().await?;
    let drive = d["id"].as_str().unwrap_or_default().to_string();
    let kids: serde_json::Value = client.graph_get(&format!("/drives/{drive}/root/children?$select=id,name")).await?.json().await?;
    for nb in kids["value"].as_array().into_iter().flatten().filter(|k| k["name"].as_str().is_some_and(|n| n.ends_with(" Notebook"))) {
        let id = nb["id"].as_str().unwrap_or_default();
        let files: serde_json::Value = client.graph_get(&format!("/drives/{drive}/items/{id}/children?$select=id,name")).await?.json().await?;
        for f in files["value"].as_array().into_iter().flatten() {
            if f["name"].as_str() == Some(format!("{name}.one").as_str()) {
                client.graph_delete(&format!("/drives/{drive}/items/{}", f["id"].as_str().unwrap_or_default())).await?;
                println!("deleted section {name}.one");
            }
        }
    }
    Ok(())
}
