//! People search and 1:1 chat ids.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// A person from the directory.
#[derive(Debug, Clone, serde::Serialize)]
pub struct Person {
    /// AAD object id.
    pub id: String,
    pub name: String,
    pub mail: String,
    pub job_title: String,
}

/// Search the organisation's directory by name or e-mail.
pub async fn search_people(client: &TeamsClient, query: &str) -> Result<Vec<Person>> {
    let q = query.trim();
    if q.is_empty() {
        return Ok(Vec::new());
    }
    // $search terms are quoted; quotes and backslashes inside are dropped.
    let term: String = q.chars().filter(|c| *c != '"' && *c != '\\').collect();
    let search = format!("\"displayName:{term}\" OR \"mail:{term}\"");
    let path = format!(
        "/users?$search={}&$top=10&$select=id,displayName,mail,jobTitle",
        url::form_urlencoded::byte_serialize(search.as_bytes()).collect::<String>()
    );
    let v: serde_json::Value = client
        .graph_get_with(&path, &[("ConsistencyLevel", "eventual")])
        .await?
        .json()
        .await
        .context("People search reply")?;
    let me = client.object_id().unwrap_or_default();
    Ok(v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(|p| {
            let s = |k: &str| {
                p.get(k)
                    .and_then(|x| x.as_str())
                    .unwrap_or_default()
                    .to_string()
            };
            let id = s("id");
            (!id.is_empty() && !id.eq_ignore_ascii_case(&me)).then(|| Person {
                id,
                name: s("displayName"),
                mail: s("mail"),
                job_title: s("jobTitle"),
            })
        })
        .collect())
}

/// The 1:1 chat id Teams uses for two users: their object ids, sorted.
pub fn one_on_one_chat_id(a: &str, b: &str) -> String {
    let (a, b) = (a.to_ascii_lowercase(), b.to_ascii_lowercase());
    let (x, y) = if a <= b { (a, b) } else { (b, a) };
    format!("19:{x}_{y}@unq.gbl.spaces")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chat_id_matches_teams_ordering() {
        // The live chat between the test account and Randy.
        let me = "4287e791-1b98-4963-8b94-281c50472683";
        let them = "5050c9d6-b8a7-41f2-830a-0c51777b7dc3";
        let expected = "19:4287e791-1b98-4963-8b94-281c50472683_5050c9d6-b8a7-41f2-830a-0c51777b7dc3@unq.gbl.spaces";
        assert_eq!(one_on_one_chat_id(me, them), expected);
        assert_eq!(one_on_one_chat_id(them, me), expected);
    }
}
