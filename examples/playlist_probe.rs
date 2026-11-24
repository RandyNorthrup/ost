//! Print the raw answers of OneDrive's playlist calls (debugging aid for
//! Add to playlist): `cargo run --example playlist_probe -- <personal site url>`
//! (e.g. https://contoso-my.sharepoint.com/personal/me_contoso_com).
use serde_json::Value;

async fn get(url: &str) -> anyhow::Result<Value> {
    let host = url.split('/').take(3).collect::<Vec<_>>().join("/");
    let token = teams_cli::auth::oauth::access_token_for(&format!("{host}/.default")).await?;
    let r = reqwest::Client::new().get(url).bearer_auth(token).header("accept", "application/json").send().await?;
    let st = r.status();
    let t = r.text().await?;
    println!("{st} {url}");
    Ok(serde_json::from_str(&t).unwrap_or(Value::String(t.chars().take(400).collect())))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let personal = std::env::args().nth(1).unwrap_or_default();
    let host = personal.split('/').take(3).collect::<Vec<_>>().join("/");
    // `delete <title>`: remove that test playlist (to the recycle bin).
    if std::env::args().nth(2).as_deref() == Some("delete") {
        let title = std::env::args().nth(3).unwrap_or_default();
        anyhow::ensure!(title.starts_with("OST TEST"), "Only OST TEST playlists");
        let v = get(&format!("{personal}/_api/web/lists/GetByTitle('{}')?$select=Id", title.replace('\'', "''"))).await?;
        let id = v["Id"].as_str().or_else(|| v["d"]["Id"].as_str()).unwrap_or_default().to_string();
        let list = teams_cli::api::playlists::Playlist { title: title.clone(), id, url: format!("{personal}/Lists/{title}"), web: personal.clone(), when: String::new() };
        teams_cli::api::playlists::delete(&list).await?;
        println!("deleted {title}");
        return Ok(());
    }
    let t = "templateTypeId=%273a867b4a-7429-0e1a-b02e-bf4b240ff1ce%27";
    for u in [
        format!("{personal}/_api/SP.PersonalListsProxy.GetPersonalListsProxy"),
        format!("{host}/_api/SP.PersonalListsProxy.GetPersonalListsProxy?{t}"),
        format!("{host}/_api/sp.RecentListProxy.GetRecentListsProxy?{t}"),
    ] {
        let v = get(&u).await?;
        println!("{}", serde_json::to_string_pretty(&v)?.chars().take(3000).collect::<String>());
    }
    Ok(())
}
