//! Your organisation's custom emoji (docs/spec/custom-emoji.md): listed,
//! added and deleted on the chat service aggregator
//! (`{csa}/api/v1/customemoji/metadata`, AAD token for chatsvcagg), with the
//! pictures on AMS (uploaded readable by the whole tenant, served from the
//! asyncgw `imgt2` views).

use anyhow::{Context, Result};

use super::client::TeamsClient;

const CSA: &str = "https://teams.microsoft.com/api/csa/api/v1/customemoji/metadata";
const CSA_SCOPE: &str = "https://chatsvcagg.teams.microsoft.com/.default";

/// One custom emoji.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct CustomEmoji {
    /// `"{shortcut};{documentId}"`, used as its key in messages and reactions.
    pub id: String,
    pub shortcut: String,
    /// The AMS object id of its picture.
    pub document_id: String,
    /// Who added it (an object id or MRI).
    pub creator: String,
    /// When, in ms since the epoch (0 when unknown).
    pub created_on: i64,
}

impl CustomEmoji {
    /// One from its id alone (what messages and reactions carry).
    pub fn from_id(id: &str) -> Option<Self> {
        let (shortcut, doc) = id.split_once(';')?;
        (!shortcut.is_empty() && !doc.is_empty() && !doc.contains(';')).then(|| CustomEmoji {
            id: id.to_string(),
            shortcut: shortcut.to_string(),
            document_id: doc.to_string(),
            ..Default::default()
        })
    }
}

/// Teams' rule for a custom emoji's name (280767 `qz`).
pub fn valid_name(name: &str) -> bool {
    (1..=50).contains(&name.len())
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

/// The name Teams suggests from a file name: no extension, lowercase,
/// non-word characters and `_` as `-`, runs of `-` collapsed and trimmed;
/// empty unless it is a valid name.
pub fn default_name(file_name: &str) -> String {
    let stem = file_name
        .rsplit_once('.')
        .map(|(s, _)| s)
        .unwrap_or(file_name);
    let mut out = String::new();
    for c in stem.to_lowercase().chars() {
        let c = if c.is_alphanumeric() && c.is_ascii() {
            c
        } else {
            '-'
        };
        if !(c == '-' && out.ends_with('-')) {
            out.push(c);
        }
    }
    let out = out.trim_matches('-').to_string();
    if valid_name(&out) { out } else { String::new() }
}

fn parse(v: &serde_json::Value) -> Option<CustomEmoji> {
    let s = |k: &str| {
        v.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let id = s("id");
    let mut e = CustomEmoji::from_id(&id)?;
    if let Some(doc) = v.get("documentId").and_then(|d| d.as_str()) {
        e.document_id = doc.to_string();
    }
    if let Some(sc) = v.pointer("/shortcuts/0").and_then(|d| d.as_str()) {
        e.shortcut = sc.to_string();
    }
    e.creator = s("creator");
    e.created_on = v
        .get("createdOn")
        .and_then(|c| {
            c.as_i64()
                .or_else(|| c.as_str().and_then(|s| s.parse().ok()))
        })
        .unwrap_or(0);
    Some(e)
}

/// The org's emoji from a list reply (`{categories: [{emoticons: […]}]}`),
/// without deleted ones, newest first.
pub fn parse_list(v: &serde_json::Value) -> Vec<CustomEmoji> {
    let mut out: Vec<CustomEmoji> = v
        .get("categories")
        .and_then(|c| c.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| c.get("emoticons")?.as_array())
        .flatten()
        .filter(|e| e.get("isDeleted").and_then(|d| d.as_bool()) != Some(true))
        .filter_map(parse)
        .collect();
    out.sort_by_key(|e| std::cmp::Reverse(e.created_on));
    out
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for(CSA_SCOPE).await
}

fn headers(req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
    req.header("x-ms-client-type", "web")
        .header("x-ms-request-id", uuid::Uuid::new_v4().to_string())
}

/// The org's custom emoji.
pub async fn list(client: &TeamsClient) -> Result<Vec<CustomEmoji>> {
    let resp = headers(client.http().get(CSA))
        .bearer_auth(token().await?)
        .send()
        .await
        .context("Custom emoji list")?;
    anyhow::ensure!(
        resp.status().is_success(),
        "HTTP {} listing custom emoji",
        resp.status().as_u16()
    );
    Ok(parse_list(
        &resp.json().await.context("Custom emoji reply")?,
    ))
}

/// Why adding failed, as Teams tells it.
#[derive(Debug, Clone, PartialEq)]
pub enum AddError {
    /// 409: the name is taken.
    AlreadyPresent,
    /// 400 "Max number of emojis N has been exceeded".
    MaxLimitReached(u32),
    /// 403: policy doesn't allow it.
    NotAllowed,
    Other(String),
}

/// Add a custom emoji: the picture to AMS for the tenant, then the
/// metadata `{shortcuts: [name], documentId}`.
pub async fn add(
    client: &TeamsClient,
    name: &str,
    picture: Vec<u8>,
) -> Result<CustomEmoji, AddError> {
    let tenant = client
        .tenant_id()
        .ok_or_else(|| AddError::Other("No tenant".into()))?;
    let doc = client
        .ams_upload_image_for(&format!("*:tid:{tenant}"), picture, &format!("{name}.png"))
        .await
        .map_err(|e| AddError::Other(format!("{e:#}")))?;
    let tok = token()
        .await
        .map_err(|e| AddError::Other(format!("{e:#}")))?;
    let resp = headers(client.http().post(CSA))
        .bearer_auth(tok)
        .header("Accept", "application/json")
        .json(&serde_json::json!({ "shortcuts": [name], "documentId": doc }))
        .send()
        .await
        .map_err(|e| AddError::Other(format!("{e:#}")))?;
    let status = resp.status().as_u16();
    let body = resp.text().await.unwrap_or_default();
    match status {
        200..=299 => {
            let v: serde_json::Value = serde_json::from_str(&body).unwrap_or_default();
            Ok(parse(&v).unwrap_or_else(|| CustomEmoji {
                id: format!("{name};{doc}"),
                shortcut: name.into(),
                document_id: doc,
                ..Default::default()
            }))
        }
        409 => Err(AddError::AlreadyPresent),
        403 => Err(AddError::NotAllowed),
        400 => {
            let title = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|v| v.get("title").and_then(|t| t.as_str()).map(str::to_string))
                .unwrap_or(body);
            match title
                .split("Max number of emojis ")
                .nth(1)
                .and_then(|r| r.split(' ').next())
                .and_then(|n| n.parse().ok())
            {
                Some(n) => Err(AddError::MaxLimitReached(n)),
                None => Err(AddError::Other(title)),
            }
        }
        _ => Err(AddError::Other(format!("HTTP {status}"))),
    }
}

/// Delete one for the org (`DELETE …/metadata/{id}`, the id unencoded).
pub async fn delete(client: &TeamsClient, id: &str) -> Result<()> {
    anyhow::ensure!(CustomEmoji::from_id(id).is_some(), "Not a custom emoji id");
    let resp = headers(client.http().delete(format!("{CSA}/{id}")))
        .bearer_auth(token().await?)
        .send()
        .await
        .context("Custom emoji delete")?;
    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!(
            "HTTP {} deleting the emoji: {}",
            status.as_u16(),
            body.chars().take(300).collect::<String>()
        );
    }
    Ok(())
}

/// Its picture's URL (`imgt2_anim` animates, `imgt2` doesn't).
pub fn picture_url(ams_v2: &str, document_id: &str, animated: bool) -> String {
    format!(
        "{ams_v2}/v1/objects/{document_id}/views/{}",
        if animated { "imgt2_anim" } else { "imgt2" }
    )
}

/// Its picture, fetched with the skype token (Teams' blob mode).
pub async fn picture(client: &TeamsClient, document_id: &str) -> Result<Vec<u8>> {
    anyhow::ensure!(
        document_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-'),
        "Bad document id"
    );
    let base = client.ams_v2_url().context("No media gateway address")?;
    client.ams_get(&picture_url(&base, document_id, true)).await
}

/// Teams' HTML for one in a message (CustomEmojiSerializer).
pub fn message_html(ams_v2: &str, e: &CustomEmoji) -> String {
    format!(
        "<span contenteditable=\"false\"><img alt=\"{n}\" itemid=\"{id}\" itemtype=\"http://schema.skype.com/CustomEmoji\" src=\"{src}\" style=\"width:20px;height:20px;\"></span>",
        n = e.shortcut,
        id = e.id,
        src = picture_url(ams_v2, &e.document_id, true)
    )
}

/// Your Teams messaging policy, from the middle tier's effective policies
/// (`POST beta/users/effectivePolicies` with the namespaces wanted,
/// services-policies 929782).
pub async fn messaging_policy(client: &TeamsClient) -> Result<serde_json::Value> {
    let mt = client.middle_tier_url().context("No middle-tier address")?;
    let token = super::directory::middle_tier_token().await?;
    let resp = client
        .http()
        .post(format!("{mt}/beta/users/effectivePolicies"))
        .bearer_auth(token)
        .json(&serde_json::json!(["teamsMessagingPolicy"]))
        .send()
        .await
        .context("Effective policies")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    anyhow::ensure!(
        status.is_success(),
        "HTTP {} for effective policies: {}",
        status.as_u16(),
        text.chars().take(300).collect::<String>()
    );
    serde_json::from_str(&text).context("Effective policies reply")
}

/// Whether you may delete custom emoji for the org: the messaging policy's
/// `deleteCustomEmojis` (Teams' `enableCustomEmojiDeletion`); off unless set.
pub async fn deletion_allowed(client: &TeamsClient) -> Result<bool> {
    Ok(find_bool(&messaging_policy(client).await?, "deleteCustomEmojis").unwrap_or(false))
}

/// The first boolean named `key` anywhere in `v`.
pub fn find_bool(v: &serde_json::Value, key: &str) -> Option<bool> {
    match v {
        serde_json::Value::Object(m) => m
            .get(key)
            .and_then(|b| b.as_bool())
            .or_else(|| m.values().find_map(|c| find_bool(c, key))),
        serde_json::Value::Array(a) => a.iter().find_map(|c| find_bool(c, key)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_names_and_lists() {
        let e = CustomEmoji::from_id("ost-test;0-wus-d1-abc").unwrap();
        assert_eq!(
            (e.shortcut.as_str(), e.document_id.as_str()),
            ("ost-test", "0-wus-d1-abc")
        );
        assert!(CustomEmoji::from_id("laugh").is_none());
        assert!(CustomEmoji::from_id("a;b;c").is_none());
        assert!(
            valid_name("ost-test") && !valid_name("OST") && !valid_name("a b") && !valid_name("")
        );
        assert_eq!(default_name("OST_Test logo.PNG"), "ost-test-logo");
        assert_eq!(default_name("!!!.png"), "");
        // As the live list read with nothing in it, and with two.
        let empty = serde_json::json!({"categories": [{"id": "customEmoji", "emoticons": []}], "continuationToken": "1794076212"});
        assert!(parse_list(&empty).is_empty());
        let two = serde_json::json!({"categories": [{"emoticons": [
            {"id": "old;0-a", "documentId": "0-a", "shortcuts": ["old"], "createdOn": 1, "creator": "x"},
            {"id": "new;0-b", "documentId": "0-b", "shortcuts": ["new"], "createdOn": 2},
            {"id": "gone;0-c", "isDeleted": true}
        ]}]});
        let got = parse_list(&two);
        assert_eq!(
            got.iter().map(|e| e.shortcut.as_str()).collect::<Vec<_>>(),
            ["new", "old"]
        );
        assert_eq!(
            message_html("https://gw", &got[0]),
            r#"<span contenteditable="false"><img alt="new" itemid="new;0-b" itemtype="http://schema.skype.com/CustomEmoji" src="https://gw/v1/objects/0-b/views/imgt2_anim" style="width:20px;height:20px;"></span>"#
        );
    }
}
