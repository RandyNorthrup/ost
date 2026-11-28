//! OneDrive checks for Teams parity work (debugging aid; prints no tokens):
//! - `files_probe recent`: each recent-files entry with the reason OST's
//!   Home leaves it out ("-" when listed);
//! - `files_probe favorites`: OneDrive's favorites
//!   (`sp.FavoriteItemCollection.GetFavoriteItems`) and Graph's followed
//!   items;
//! - `files_probe pagectx <page url>`: a few `_spPageContextInfo` fields of
//!   a SharePoint page (knowledge agent and Copilot switches).
use serde_json::Value;
use teams_cli::api::{client::TeamsClient, quick_access, recent_files};

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0";

async fn sp_get(url: &str, accept: &str) -> anyhow::Result<String> {
    let host = url.split('/').take(3).collect::<Vec<_>>().join("/");
    let token = teams_cli::auth::oauth::access_token_for(&format!("{host}/.default")).await?;
    let mut req = reqwest::Client::new()
        .get(url)
        .bearer_auth(token)
        .header("accept", accept)
        .header("user-agent", UA);
    // SP_PREFER: OneDrive's Prefer header (`useSmartCache, filetypes="…"`).
    if let Ok(p) = std::env::var("SP_PREFER") {
        req = req.header("prefer", p);
    }
    let r = req.send().await?;
    println!(
        "GET {} -> {}",
        url.split('?').next().unwrap_or(url),
        r.status()
    );
    Ok(r.text().await?)
}

fn s(v: &Value) -> &str {
    v.as_str().unwrap_or("")
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    match args.first().map(String::as_str) {
        Some("recent") => {
            // An extra query (`files_probe recent '&apps=Word,Fluid'`) asks
            // as OneDrive's Home does.
            let (reply, personal) = match args.get(1) {
                Some(q) => {
                    let personal = quick_access::personal_site(&client).await?;
                    let text = sp_get(
                        &format!("{personal}/_api/sp.RecentFileCollection.DeltaSync?top=500{q}"),
                        "application/json",
                    )
                    .await?;
                    (serde_json::from_str(&text).unwrap_or_default(), personal)
                }
                None => recent_files::fetch_reply(&client).await?,
            };
            println!("personal site: {personal}");
            for e in recent_files::entries(&reply) {
                let x = &e["file"];
                println!(
                    "{:<18} {:<10} {:<9} {} | {} | {}",
                    recent_files::left_out(&e).unwrap_or("-"),
                    s(&x["Visualization"]["Type"]),
                    s(&x["SharePointOnlineFacetStatus"]),
                    s(&x["FileName"]),
                    s(&x["Visualization"]["ContainerUrl"]),
                    recent_files::opened(&e),
                );
            }
        }
        Some("favorites") => {
            let personal = quick_access::personal_site(&client).await?;
            let text = sp_get(
                &format!("{personal}/_api/sp.FavoriteItemCollection.GetFavoriteItems?top=500"),
                "application/json;odata=verbose",
            )
            .await?;
            let v: Value = serde_json::from_str(&text).unwrap_or_default();
            let inner: Value =
                serde_json::from_str(s(&v["d"]["GetFavoriteItems"])).unwrap_or_default();
            let files = inner["files"].as_array().cloned().unwrap_or_default();
            println!("GetFavoriteItems: {} entries", files.len());
            for e in files {
                let x = &e["file"];
                println!(
                    "  {:<10} {} | {} | ids {} {}",
                    s(&x["Visualization"]["Type"]),
                    s(&x["FileName"]),
                    s(&x["SharePointItem"]["FileUrl"]),
                    s(&x["SharePointItem"]["ListId"]),
                    s(&x["SharePointItem"]["UniqueId"]),
                );
            }
            if files_is_empty(&inner) && !text.is_empty() {
                println!(
                    "  (reply keys: {:?}; start: {})",
                    inner.as_object().map(|o| o.keys().collect::<Vec<_>>()),
                    text.chars().take(300).collect::<String>()
                );
            }
            let g: Value = client
                .graph_get("/me/drive/following?$select=id,name,folder,file,webUrl")
                .await?
                .json()
                .await?;
            let list = g["value"].as_array().cloned().unwrap_or_default();
            println!("Graph following: {} items", list.len());
            for it in list {
                println!(
                    "  {} {}",
                    if it["folder"].is_object() {
                        "folder"
                    } else {
                        "file  "
                    },
                    s(&it["name"])
                );
            }
        }
        Some("pagectx") => {
            let url = args.get(1).cloned().unwrap_or_default();
            let html = sp_get(&url, "text/html").await?;
            for key in [
                "isKnowledgeAgentEnabled",
                "canUserUseSPCopilot",
                "kaToolsUrls",
                "kaToolsDevMode",
                "isSPOCopilotEnabled",
                "IsUserInNgspGroup",
                "webTemplate",
                "isMySiteOwner",
            ] {
                let pat = format!("\"{key}\":");
                match html.find(&pat) {
                    Some(i) => {
                        let rest = &html[i + pat.len()..];
                        let end = rest.find([',', '}']).unwrap_or(rest.len()).min(200);
                        println!("{key} = {}", &rest[..end]);
                    }
                    None => println!("{key} (absent)"),
                }
            }
        }
        Some("spget") => {
            // A SharePoint GET's raw reply (`{me}` is your OneDrive's site).
            let personal = quick_access::personal_site(&client).await?;
            let url = args
                .get(1)
                .cloned()
                .unwrap_or_default()
                .replace("{me}", &personal);
            println!("{}", sp_get(&url, "application/json").await?);
        }
        Some("graph") => {
            // A Graph GET's reply (for chat members' tenants and the like).
            let path = args.get(1).cloned().unwrap_or_default();
            let v: Value = client.graph_get(&path).await?.json().await?;
            println!("{}", serde_json::to_string_pretty(&v)?);
        }
        Some("chats") => {
            for c in teams_cli::api::list_chats_data(&client, 50).await? {
                let flags = [
                    ("unlisted", c.unlisted),
                    ("hidden", c.hidden),
                    ("empty", c.empty),
                    ("external", c.external),
                    ("request", c.request),
                    ("muted", c.muted),
                    ("disabled", c.messaging_disabled),
                ]
                .iter()
                .filter(|(_, on)| *on)
                .map(|(k, _)| *k)
                .collect::<Vec<_>>()
                .join(",");
                println!("{:<60} {:<32} {}", c.id, c.name, flags);
            }
        }
        _ => eprintln!("usage: files_probe recent [query] | favorites | pagectx <url> | chats"),
    }
    Ok(())
}

fn files_is_empty(v: &Value) -> bool {
    v["files"].as_array().is_none_or(|a| a.is_empty())
}
