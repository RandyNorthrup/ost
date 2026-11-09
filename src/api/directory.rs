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

/// Microsoft's privacy statement: what Teams links when the tenant names
/// none of its own.
pub const MICROSOFT_PRIVACY_STATEMENT: &str = "https://go.microsoft.com/fwlink/p/?linkid=857875";

/// A privacy profile's statement link (`{"statementUrl": …}`), when it
/// names an https one.
fn privacy_statement_from(profile: &serde_json::Value) -> Option<String> {
    profile
        .get("statementUrl")
        .and_then(|u| u.as_str())
        .filter(|u| u.starts_with("https://"))
        .map(str::to_string)
}

/// The privacy statement Teams links from recording, transcript and RTT
/// notices: the tenant's (its privacy profile, as Teams reads it from the
/// middle tier), else Microsoft's.
pub async fn privacy_statement_url(client: &TeamsClient) -> String {
    let profile = async {
        let mt = client.middle_tier_url()?;
        let token = middle_tier_token().await.ok()?;
        let resp = client
            .http()
            .get(format!("{mt}/beta/tenant/privacyProfile"))
            .bearer_auth(token)
            .send()
            .await
            .ok()?;
        if !resp.status().is_success() {
            tracing::debug!(status = resp.status().as_u16(), "tenant privacy profile");
            return None;
        }
        resp.json::<serde_json::Value>().await.ok()
    }
    .await;
    profile
        .as_ref()
        .and_then(privacy_statement_from)
        .unwrap_or_else(|| MICROSOFT_PRIVACY_STATEMENT.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tenants_privacy_statement_wins_over_microsofts() {
        let tenant =
            serde_json::json!({"statementUrl": "https://contoso.com/privacy", "contactEmail": ""});
        assert_eq!(
            privacy_statement_from(&tenant).as_deref(),
            Some("https://contoso.com/privacy")
        );
        assert_eq!(
            privacy_statement_from(&serde_json::json!({"statementUrl": ""})),
            None
        );
        assert_eq!(
            privacy_statement_from(&serde_json::json!({"statementUrl": "javascript:x"})),
            None
        );
    }

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

/// Whose picture to fetch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PhotoOwner {
    /// A person, by Entra object id.
    User,
    /// A team, by its group id.
    Team,
    /// Someone known only by name (a meeting guest): Teams' initials
    /// picture for that name (`defaultProfilePictureV2`).
    Named,
}

/// A middle-tier token (audience api.spaces.skype.com), reused until close
/// to expiry so pictures don't each mint one.
pub(crate) async fn middle_tier_token() -> Result<String> {
    use std::sync::Mutex;
    use std::time::{Duration, Instant};
    static CACHE: Mutex<Option<(String, Instant)>> = Mutex::new(None);
    if let Some((t, at)) = CACHE.lock().unwrap().as_ref()
        && at.elapsed() < Duration::from_secs(45 * 60)
    {
        return Ok(t.clone());
    }
    let t = crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await?;
    *CACHE.lock().unwrap() = Some((t.clone(), Instant::now()));
    Ok(t)
}

/// A person's or team's picture as Teams shows it, from the Teams
/// middle-tier picture service: the profile photo, or the initials image
/// Teams generates (in its own colours) when there is none. `None` when the
/// service has nothing; the app then draws initials itself.
pub async fn photo(
    client: &TeamsClient,
    owner: PhotoOwner,
    id: &str,
    display_name: &str,
) -> Result<Option<Vec<u8>>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let name: String = url::form_urlencoded::byte_serialize(display_name.as_bytes()).collect();
    let url = if owner == PhotoOwner::Named {
        if display_name.trim().is_empty() {
            anyhow::bail!("No name to draw");
        }
        // Teams asks for a guest's picture by name (HR64 for its 32 px
        // avatars); 196 px keeps it sharp at every size OST draws.
        format!("{base}/beta/users/defaultProfilePictureV2?displayname={name}&size=HR196x196")
    } else {
        if id.len() != 36 || !id.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
            anyhow::bail!("Not an object id");
        }
        let me = client.object_id().context("No signed-in user")?;
        // 196 px is sharp for every avatar size (up to the 144 px call stage
        // at 1.5x scaling); teams come at one fixed size.
        let path = match owner {
            PhotoOwner::Team => format!("teams/{id}?displayName={name}"),
            _ => format!("8:orgid:{id}?displayname={name}&size=HR196x196"),
        };
        format!("{base}/beta/users/{me}/profilepicturev2/{path}")
    };
    let token = middle_tier_token().await?;
    let resp = client
        .http()
        .get(&url)
        .bearer_auth(token)
        .send()
        .await
        .context("Picture request")?;
    let status = resp.status();
    if status == reqwest::StatusCode::NOT_FOUND || status == reqwest::StatusCode::NO_CONTENT {
        return Ok(None);
    }
    if !status.is_success() {
        anyhow::bail!("Picture request failed: HTTP {}", status.as_u16());
    }
    let bytes = resp.bytes().await.context("Picture download")?;
    Ok((!bytes.is_empty()).then(|| bytes.to_vec()))
}
