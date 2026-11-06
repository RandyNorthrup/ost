//! Contacts for the People app, as Teams' People app shows them: your
//! Outlook contacts (All contacts), the ones you marked as favorites, and
//! your Outlook categories. Ids that go into Graph paths are checked
//! first.

use anyhow::{bail, Context, Result};
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
