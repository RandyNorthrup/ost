//! Contacts for the People app, as Teams' People app shows them: your
//! Outlook contacts (All contacts), the ones you marked as favorites, and
//! your Outlook categories. Ids that go into Graph paths are checked
//! first.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;

/// One contact.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Contact {
    pub id: String,
    pub name: String,
    pub email: String,
    pub mobile: String,
    pub phone: String,
    pub company: String,
    pub job_title: String,
    pub categories: Vec<String>,
    pub favorite: bool,
}

/// What a new contact needs.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct NewContact {
    #[serde(default)]
    pub first: String,
    #[serde(default)]
    pub last: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub mobile: String,
    #[serde(default)]
    pub company: String,
    #[serde(default)]
    pub job_title: String,
}

/// An Outlook category (name and Outlook's colour preset).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Category {
    pub name: String,
    pub color: String,
}

/// Graph ids are base64url-ish: letters, digits, `-`, `_`, `=`.
fn check_id(id: &str) -> Result<&str> {
    if id.is_empty()
        || id.len() > 512
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_=".contains(&b))
    {
        bail!("Not a contact id");
    }
    Ok(id)
}

fn s(v: &serde_json::Value, p: &str) -> String {
    v.pointer(p)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

fn phone_of(c: &serde_json::Value, kind: &str) -> Option<String> {
    c.get("phones")?
        .as_array()?
        .iter()
        .find(|p| p.get("type").and_then(|t| t.as_str()) == Some(kind))
        .and_then(|p| p.get("number")?.as_str())
        .map(str::to_string)
}

fn parse(c: &serde_json::Value) -> Option<Contact> {
    let id = s(c, "/id");
    if id.is_empty() {
        return None;
    }
    let email = s(c, "/emailAddresses/0/address");
    let mut name = s(c, "/displayName");
    if name.is_empty() {
        name = if email.is_empty() {
            "(No name)".into()
        } else {
            email.clone()
        };
    }
    Some(Contact {
        id,
        name,
        email,
        // Beta lists phones by type; v1 (what create returns) has fields.
        mobile: phone_of(c, "mobile").unwrap_or_else(|| s(c, "/mobilePhone")),
        phone: phone_of(c, "business").unwrap_or_else(|| s(c, "/businessPhones/0")),
        company: s(c, "/companyName"),
        job_title: s(c, "/jobTitle"),
        categories: c
            .get("categories")
            .and_then(|v| v.as_array())
            .into_iter()
            .flatten()
            .filter_map(|x| x.as_str().map(str::to_string))
            .collect(),
        favorite: c
            .get("isFavorite")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
    })
}

const SELECT: &str =
    "$select=id,displayName,emailAddresses,phones,companyName,jobTitle,categories,isFavorite";

/// All your contacts, by name (Graph beta, which carries isFavorite).
pub async fn list(client: &TeamsClient) -> Result<Vec<Contact>> {
    let v: serde_json::Value = client
        .graph_beta(
            &format!("/me/contacts?$top=500&$orderby=displayName&{SELECT}"),
            None,
        )
        .await?
        .json()
        .await?;
    Ok(v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .filter_map(parse)
        .collect())
}

/// Your Outlook categories.
pub async fn categories(client: &TeamsClient) -> Result<Vec<Category>> {
    let v: serde_json::Value = client
        .graph_get("/me/outlook/masterCategories")
        .await?
        .json()
        .await?;
    Ok(v.get("value")
        .and_then(|x| x.as_array())
        .into_iter()
        .flatten()
        .map(|c| Category {
            name: s(c, "/displayName"),
            color: s(c, "/color"),
        })
        .filter(|c| !c.name.is_empty())
        .collect())
}

/// Add a contact (Add new contact).
pub async fn create(client: &TeamsClient, c: &NewContact) -> Result<Contact> {
    let (first, last, email) = (c.first.trim(), c.last.trim(), c.email.trim());
    if first.is_empty() && last.is_empty() && email.is_empty() {
        bail!("A contact needs a name or an email");
    }
    let display = [first, last]
        .iter()
        .filter(|p| !p.is_empty())
        .cloned()
        .collect::<Vec<_>>()
        .join(" ");
    let display = if display.is_empty() {
        email.to_string()
    } else {
        display
    };
    let mut body = serde_json::json!({
        "givenName": first,
        "surname": last,
        "displayName": display,
        "companyName": c.company.trim(),
        "jobTitle": c.job_title.trim(),
    });
    if !email.is_empty() {
        if !email.contains('@') || email.contains(char::is_whitespace) {
            bail!("That email address doesn't look right");
        }
        body["emailAddresses"] = serde_json::json!([{ "address": email, "name": display }]);
    }
    if !c.mobile.trim().is_empty() {
        body["mobilePhone"] = serde_json::json!(c.mobile.trim());
    }
    let v: serde_json::Value = client
        .graph_post("/me/contacts", &body)
        .await?
        .json()
        .await?;
    parse(&v).context("The new contact came back empty")
}

/// Mark a contact as a favorite, or not (Graph beta's isFavorite).
pub async fn set_favorite(client: &TeamsClient, id: &str, on: bool) -> Result<()> {
    let id = check_id(id)?;
    client
        .graph_beta_patch(
            &format!("/me/contacts/{id}"),
            &serde_json::json!({ "isFavorite": on }),
        )
        .await?;
    Ok(())
}

/// Delete a contact.
pub async fn delete(client: &TeamsClient, id: &str) -> Result<()> {
    let id = check_id(id)?;
    client.graph_delete(&format!("/me/contacts/{id}")).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contacts_parse_with_fallbacks() {
        let c = parse(&serde_json::json!({
            "id": "AAMk-1_=", "displayName": "", "emailAddresses": [{"address": "a@b.c"}],
            "categories": ["Red category"], "isFavorite": true
        }))
        .unwrap();
        assert_eq!(c.name, "a@b.c");
        assert!(c.favorite);
        assert_eq!(c.categories, vec!["Red category".to_string()]);
        assert!(parse(&serde_json::json!({"displayName": "x"})).is_none());
    }

    #[test]
    fn ids_are_checked() {
        assert!(check_id("AAMkAGI2T-_=").is_ok());
        assert!(check_id("../me").is_err());
        assert!(check_id("a/b").is_err());
        assert!(check_id("").is_err());
    }
}

// ---- Notify when available (Teams' contacts v3 "Tagged" system tag) ----

/// The people you get a notice about when they become available, by MRI,
/// with their contact id (`GET {mt}/beta/contactsv3/?pageSize=1000`, the
/// contacts whose systemTags include "Tagged").
pub fn tagged_from(v: &serde_json::Value) -> Vec<(String, String, String)> {
    let list = ["contacts", "value", "items"]
        .iter()
        .find_map(|k| v.get(*k).and_then(|x| x.as_array()))
        .or_else(|| v.as_array())
        .cloned()
        .unwrap_or_default();
    list.iter()
        .filter(|c| {
            c["systemTags"].as_array().into_iter().flatten().any(|t| t["displayName"].as_str() == Some("Tagged"))
        })
        .filter_map(|c| {
            Some((
                c["mri"].as_str()?.to_lowercase(),
                c["id"].as_str()?.to_string(),
                c["defaultEmail"].as_str().unwrap_or_default().to_string(),
            ))
        })
        .collect()
}

pub async fn tagged(client: &TeamsClient) -> Result<Vec<(String, String, String)>> {
    let base = client.middle_tier_url().context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let mut out = Vec::new();
    let mut skip = String::new();
    for _ in 0..20 {
        let mut url = format!("{base}/beta/contactsv3/?pageSize=1000");
        if !skip.is_empty() {
            url.push_str(&format!("&skipToken={skip}"));
        }
        let v: serde_json::Value = client.http().get(url).bearer_auth(&token).send().await?.error_for_status().context("Contacts")?.json().await?;
        out.extend(tagged_from(&v));
        skip = v["skipToken"].as_str().or(v["nextSkipToken"].as_str()).unwrap_or_default().to_string();
        if skip.is_empty() {
            break;
        }
    }
    Ok(out)
}

/// Teams' Notify when available body: the person as a contact with the
/// "Tagged" system tag.
pub fn notify_body(mri: &str, tenant: &str) -> serde_json::Value {
    let oid = mri.trim_start_matches("8:orgid:");
    serde_json::json!({
        "mri": mri,
        "names": [],
        "webAccounts": [{ "userId": format!("OID:{oid}@{tenant}"), "service": { "name": "Profile" }, "source": { "type": "Profile" } }],
        "systemTags": [{ "displayName": "Tagged" }],
    })
}

/// Notify when available: `POST {mt}/beta/contactsv3/`; returns the
/// contact's id.
pub async fn notify_when_available(client: &TeamsClient, mri: &str) -> Result<String> {
    let base = client.middle_tier_url().context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let tenant = client.tenant_id().unwrap_or_default();
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/contactsv3/"))
        .bearer_auth(&token)
        .json(&notify_body(mri, &tenant))
        .send()
        .await?
        .error_for_status()
        .context("Notify when available")?
        .json()
        .await?;
    Ok(v["id"].as_str().unwrap_or_default().to_string())
}

/// Turn off notifications: `PATCH {mt}/beta/contactsv3/{id}?isConcatenatedId=false`
/// with the tag deleted, as Teams does.
pub async fn stop_notify(client: &TeamsClient, contact_id: &str, mri: &str, email: &str) -> Result<()> {
    let base = client.middle_tier_url().context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let id = contact_id.replace('/', "-");
    let enc: String = url::form_urlencoded::byte_serialize(id.as_bytes()).collect();
    client
        .http()
        .patch(format!("{base}/beta/contactsv3/{enc}?isConcatenatedId=false"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "id": contact_id, "mri": mri, "defaultEmail": email, "systemTags": [{ "displayName": "Tagged", "action": "Delete" }] }))
        .send()
        .await?
        .error_for_status()
        .context("Turn off notifications")?;
    Ok(())
}

#[cfg(test)]
mod tagged_tests {
    use super::*;

    #[test]
    fn notify_when_available_is_teams() {
        // Teams' request for ost-test1's 1:1 (2026-11-09).
        assert_eq!(
            notify_body("8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3", "2716d134-5614-4856-a48d-2002edd9a570").to_string(),
            r#"{"mri":"8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3","names":[],"systemTags":[{"displayName":"Tagged"}],"webAccounts":[{"service":{"name":"Profile"},"source":{"type":"Profile"},"userId":"OID:5050c9d6-b8a7-41f2-830a-0c51777b7dc3@2716d134-5614-4856-a48d-2002edd9a570"}]}"#
        );
        let v = serde_json::json!({"contacts": [
            {"id": "c1", "mri": "8:orgid:A", "defaultEmail": "a@x", "systemTags": [{"displayName": "Tagged"}]},
            {"id": "c2", "mri": "8:orgid:b", "systemTags": []}]});
        assert_eq!(tagged_from(&v), vec![("8:orgid:a".to_string(), "c1".to_string(), "a@x".to_string())]);
    }
}
