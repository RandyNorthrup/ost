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

/// Search the organisation's directory by name or e-mail (you left out).
pub async fn search_people(client: &TeamsClient, query: &str) -> Result<Vec<Person>> {
    search_directory(client, query, false).await
}

/// Search the directory, with you among the results when `include_me`
/// (Teams' status message picker suggests you too).
pub async fn search_directory(
    client: &TeamsClient,
    query: &str,
    include_me: bool,
) -> Result<Vec<Person>> {
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
            (!id.is_empty() && (include_me || !id.eq_ignore_ascii_case(&me))).then(|| Person {
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
    #[test]
    fn short_names_as_teams() {
        use super::short_name;
        assert_eq!(short_name("en-us", "Test 2", "OST", "OST Test 2"), "OST");
        assert_eq!(
            short_name("en-us", "Northrup", "Randy", "Randy Northrup"),
            "Randy"
        );
        assert_eq!(
            short_name("en-us", "Northrup", "Randy", "Northrup, Randy (IT)"),
            "Northrup, Randy"
        );
        assert_eq!(short_name("en-us", "", "", "Someone"), "Someone");
        assert_eq!(
            short_name("ja-jp", "山田（営業）", "太郎", "山田 太郎"),
            "山田"
        );
    }

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
    /// A group chat without its own picture, by thread id: Teams' picture
    /// of its members in a split circle (`mergedProfilePicturev2`).
    Chat,
}

/// The members a group chat's picture shows (Teams' chat list, measured on
/// winpc 2026-11-15): the other people (not you, not bots), by display
/// name, the first three.
pub fn group_picture_members(mut people: Vec<(String, String)>, me: &str) -> Vec<(String, String)> {
    people.retain(|(mri, name)| {
        mri.starts_with("8:") && !mri.eq_ignore_ascii_case(me) && !name.is_empty()
    });
    people.sort_by(|a, b| {
        a.1.to_lowercase()
            .cmp(&b.1.to_lowercase())
            .then_with(|| a.0.cmp(&b.0))
    });
    people.truncate(3);
    people
}

/// The middle tier's `usersInfo` for those members, as Teams sends it.
pub fn merged_picture_users(members: &[(String, String)]) -> String {
    serde_json::Value::Array(
        members
            .iter()
            .map(|(mri, name)| serde_json::json!({ "userId": mri, "displayName": name, "avatarETag": "SignIn_1793893262864" }))
            .collect(),
    )
    .to_string()
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
    let url = if owner == PhotoOwner::Chat {
        // A group chat: its members (the chat service) and their names
        // (one short-profile request), then the merged picture (64 px, as
        // Teams asks for it).
        anyhow::ensure!(
            id.starts_with("19:") && !id.contains(['/', '?', '#']),
            "Not a chat id"
        );
        let me = client.self_mri().context("No signed-in user")?;
        let ids = super::chat::thread_member_ids(client, id).await?;
        let names: Vec<(String, String)> = short_profiles(client, &ids).await.unwrap_or_default();
        let members = group_picture_members(names, &me);
        anyhow::ensure!(!members.is_empty(), "No members to draw");
        let users: String =
            url::form_urlencoded::byte_serialize(merged_picture_users(&members).as_bytes())
                .collect();
        format!(
            "{base}/beta/users/{}/mergedProfilePicturev2?usersInfo={users}&size=HR64x64",
            crate::identity::mri_id(&me)
        )
    } else if owner == PhotoOwner::Named {
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
            _ => format!(
                "{}?displayname={name}&size=HR196x196",
                crate::identity::work_user_mri(id)
            ),
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

#[cfg(test)]
mod group_picture_tests {
    use super::*;

    #[test]
    fn group_pictures_show_the_first_three_others_by_name() {
        let me = "8:orgid:4287e791-1b98-4963-8b94-281c50472683";
        let people = vec![
            (me.to_string(), "OST Test 1".to_string()),
            ("8:orgid:9edcc62f".to_string(), "OST Test 2".to_string()),
            ("8:orgid:f20421b0".to_string(), "OST Guest 01".to_string()),
            ("28:fd931076".to_string(), "Polls".to_string()),
            ("8:orgid:21ffda01".to_string(), "OST Guest 02".to_string()),
            ("8:orgid:aaaa".to_string(), "Zed".to_string()),
        ];
        let got = group_picture_members(people, me);
        assert_eq!(
            got.iter().map(|p| p.1.as_str()).collect::<Vec<_>>(),
            ["OST Guest 01", "OST Guest 02", "OST Test 2"]
        );
        assert!(merged_picture_users(&got[..1]).contains(r#""displayName":"OST Guest 01""#));
    }
}

/// People's short profiles by MRI, as Teams resolves people it only knows
/// by MRI (`POST {mt}/beta/users/fetchShortProfile` with the MRIs; the
/// reply's `value` lists `{mri, displayName, userPrincipalName, ...}`).
/// Unknown MRIs are left out.
pub async fn short_profile_records(
    client: &TeamsClient,
    mris: &[String],
) -> Result<Vec<serde_json::Value>> {
    let mris: Vec<&String> = mris.iter().filter(|m| m.starts_with("8:")).collect();
    if mris.is_empty() {
        return Ok(Vec::new());
    }
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/users/fetchShortProfile?isMailAddress=false&enableGuest=true&skypeTeamsInfo=true"))
        .bearer_auth(&token)
        .json(&mris)
        .send()
        .await?
        .error_for_status()
        .context("Short profiles")?
        .json()
        .await?;
    Ok(v["value"].as_array().cloned().unwrap_or_default())
}

/// The short name Teams uses for someone in a group chat's notification
/// ("OST: hello" for OST Test 2; Teams' 99234 `ob`): the given name when
/// the display name starts with it (and not with the surname); the display
/// name up to any "(" when it starts with the surname instead; in Japanese
/// the surname; otherwise the display name.
pub fn short_name(locale: &str, surname: &str, given: &str, display: &str) -> String {
    let before_paren = |s: &str| {
        s.split(['(', '\u{FF08}'])
            .next()
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let starts_given = !given.is_empty() && display.starts_with(given);
    let starts_surname = !surname.is_empty() && display.starts_with(surname);
    let name = if !surname.is_empty() && locale.eq_ignore_ascii_case("ja-jp") {
        before_paren(surname)
    } else if starts_given && !starts_surname {
        given.to_string()
    } else if starts_surname && !starts_given {
        before_paren(display)
    } else {
        String::new()
    };
    if name.is_empty() {
        display.to_string()
    } else {
        name
    }
}

/// People's display names by MRI (short_profile_records' `displayName`).
pub async fn short_profiles(
    client: &TeamsClient,
    mris: &[String],
) -> Result<Vec<(String, String)>> {
    Ok(short_profile_records(client, mris)
        .await?
        .iter()
        .filter_map(|p| {
            let mri = p["mri"].as_str()?.to_string();
            let name = p["displayName"]
                .as_str()
                .filter(|n| !n.is_empty())?
                .to_string();
            Some((mri, name))
        })
        .collect())
}
