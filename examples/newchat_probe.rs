//! Print what Substrate answers for the new chat form's typed search, and
//! how OST arranges it (debugging aid; names and kinds only):
//! `cargo run --example newchat_probe -- '<query>'`.
use teams_cli::api::search::{new_chat_arrange, new_chat_body};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let q = std::env::args().nth(1).unwrap_or_else(|| "OST".into());
    let token = teams_cli::auth::oauth::access_token_for("https://substrate.office.com/.default").await?;
    let reply: serde_json::Value = reqwest::Client::new()
        .post("https://substrate.office.com/search/api/v1/suggestions?scenario=peoplepicker.newChat")
        .bearer_auth(token)
        .json(&new_chat_body(&q))
        .send()
        .await?
        .json()
        .await?;
    for g in reply["Groups"].as_array().into_iter().flatten() {
        println!("group {} ({})", g["Type"], g["Suggestions"].as_array().map(|a| a.len()).unwrap_or(0));
        for r in g["Suggestions"].as_array().into_iter().flatten() {
            let name = r["DisplayName"].as_str().or(r["Name"].as_str()).unwrap_or("");
            println!(
                "  {name} | {} | oid {} | mri {}",
                r["PeopleSubtype"].as_str().or(r["ThreadType"].as_str()).unwrap_or(""),
                !r["ExternalDirectoryObjectId"].as_str().unwrap_or_default().is_empty(),
                r["MRI"].as_str().unwrap_or("").chars().take(9).collect::<String>()
            );
        }
    }
    for v in new_chat_arrange(&reply, "", &[], &q) {
        println!("arranged {}: {}", v["kind"], v["name"]);
    }
    Ok(())
}
