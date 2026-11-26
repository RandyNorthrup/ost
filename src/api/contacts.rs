//! Contacts for the People app, as Teams' People app shows them: your
//! contacts (All contacts), the ones you marked as favorites, and your
//! contact categories.
//!
//! Teams reads them from its middle tier's contacts service (contacts v3,
//! `GET {mt}/beta/contactsv3/?pageSize=200` with the Teams token, captured
//! on winpc 2026-11-26), not from Graph: OST's Graph token has no
//! Contacts.Read, so Graph's `/me/contacts` answers 403. Favorites are the
//! "SfbFavorites" system tag and categories the contacts' own tags.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::client::TeamsClient;

/// One contact.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Contact {
    pub id: String,
    /// The person's Teams id when the contact is someone in a directory.
    pub mri: String,
    pub name: String,
    pub first: String,
    pub last: String,
    pub email: String,
    pub mobile: String,
    pub phone: String,
    pub company: String,
    pub job_title: String,
    pub office_location: String,
    pub categories: Vec<String>,
    pub favorite: bool,
    /// When it was added (ISO), for Sort ▸ Recently added.
    pub created: String,
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

/// A contact category (its name and colour).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Category {
    pub name: String,
    pub color: String,
}

/// Teams' favorites tag in the contacts service (the People app's
/// Favorites; "Favorites" is speed dial).
const FAVORITES: &str = "SfbFavorites";

/// Contact ids are base64: letters, digits, `-`, `_`, `=`, `+`, `/`.
fn check_id(id: &str) -> Result<&str> {
    if id.is_empty()
        || id.len() > 512
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_=+/".contains(&b))
    {
        bail!("Not a contact id");
    }
    Ok(id)
}

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

fn s(v: &Value, p: &str) -> String {
    v.pointer(p)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

fn list_of<'a>(c: &'a Value, key: &str) -> impl Iterator<Item = &'a Value> {
    c.get(key).and_then(|v| v.as_array()).into_iter().flatten()
}

fn has_tag(c: &Value, key: &str, name: &str) -> bool {
    list_of(c, key).any(|t| t["displayName"].as_str() == Some(name))
}

/// A contact as the contacts service gives it. Its name is the first
/// entry with a name in it (the person's profile name comes first for
/// someone in a directory), else its email.
fn parse(c: &Value) -> Option<Contact> {
    let id = s(c, "/id");
    if id.is_empty() {
        return None;
    }
    let name_of = |n: &Value| {
        let d = s(n, "/displayName");
        if !d.is_empty() {
            return d;
        }
        [s(n, "/first"), s(n, "/last")]
            .into_iter()
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>()
            .join(" ")
    };
    let names: Vec<&Value> = list_of(c, "names")
        .filter(|n| !name_of(n).is_empty())
        .collect();
    let email = Some(s(c, "/defaultEmail"))
        .filter(|e| !e.is_empty())
        .or_else(|| {
            list_of(c, "emails")
                .map(|e| s(e, "/address"))
                .find(|a| !a.is_empty())
        })
        .unwrap_or_default();
    let mut name = names.first().map(|n| name_of(n)).unwrap_or_default();
    if name.is_empty() {
        name = if email.is_empty() {
            "(No name)".into()
        } else {
            email.clone()
        };
    }
    let phone_of = |kind: Option<&str>| {
        list_of(c, "phones")
            .filter(|p| kind.is_none_or(|k| p["type"].as_str() == Some(k)))
            .map(|p| s(p, "/number"))
            .find(|n| !n.is_empty())
            .unwrap_or_default()
    };
    let mobile = phone_of(Some("Mobile"));
    let phone = Some(phone_of(Some("Business")))
        .filter(|p| !p.is_empty())
        .unwrap_or_else(|| {
            list_of(c, "phones")
                .filter(|p| p["type"].as_str() != Some("Mobile"))
                .map(|p| s(p, "/number"))
                .find(|n| !n.is_empty())
                .unwrap_or_default()
        });
    let position = list_of(c, "positions").find(|p| {
        !s(p, "/detail/jobTitle").is_empty()
            || !s(p, "/detail/company/displayName").is_empty()
            || !s(p, "/detail/company/officeLocation").is_empty()
    });
    let pos = |p: &str| position.map(|x| s(x, p)).unwrap_or_default();
    Some(Contact {
        id,
        mri: s(c, "/mri"),
        name,
        first: names.first().map(|n| s(n, "/first")).unwrap_or_default(),
        last: names.first().map(|n| s(n, "/last")).unwrap_or_default(),
        email,
        mobile,
        phone,
        company: pos("/detail/company/displayName"),
        job_title: pos("/detail/jobTitle"),
        office_location: pos("/detail/company/officeLocation"),
        categories: list_of(c, "tags")
            .filter_map(|t| t["displayName"].as_str().map(str::to_string))
            .filter(|t| !t.is_empty())
            .collect(),
        favorite: has_tag(c, "systemTags", FAVORITES),
        created: s(c, "/createdDateTime"),
    })
}

/// The People app's order: first name, then the whole name (Teams'
/// default sort, "First name" ascending).
fn by_first_name(a: &Contact, b: &Contact) -> std::cmp::Ordering {
    let key = |c: &Contact| {
        if c.first.is_empty() {
            c.name.to_lowercase()
        } else {
            c.first.to_lowercase()
        }
    };
    key(a)
        .cmp(&key(b))
        .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
}

/// The service's contacts (`contacts`, else `value`).
fn contacts_of(v: &Value) -> Vec<Value> {
    ["contacts", "value", "items"]
        .iter()
        .find_map(|k| v.get(*k).and_then(|x| x.as_array()))
        .or_else(|| v.as_array())
        .cloned()
        .unwrap_or_default()
}

/// Every page of the contacts service (Teams pages by 200).
async fn fetch_all(client: &TeamsClient) -> Result<Vec<Value>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let mut out = Vec::new();
    let mut skip = String::new();
    for _ in 0..150 {
        let mut url = format!("{base}/beta/contactsv3/?pageSize=200");
        if !skip.is_empty() {
            url.push_str(&format!("&skipToken={}", enc(&skip)));
        }
        let resp = client
            .http()
            .get(url)
            .bearer_auth(&token)
            .header("x-ms-client-caller", "PeopleApp")
            .send()
            .await
            .context("Contacts")?;
        if !resp.status().is_success() {
            bail!("HTTP {} for contacts", resp.status().as_u16());
        }
        let v: Value = resp.json().await.context("Contacts reply")?;
        out.extend(contacts_of(&v));
        skip = v["skipToken"]
            .as_str()
            .or(v["nextSkipToken"].as_str())
            .unwrap_or_default()
            .to_string();
        if skip.is_empty() {
            break;
        }
    }
    Ok(out)
}

/// The People app's lists from the contacts service's reply: the contacts
/// by first name, and the categories (their tags, by name).
pub fn from_service(raw: &[Value]) -> (Vec<Contact>, Vec<Category>) {
    let mut contacts: Vec<Contact> = raw.iter().filter_map(parse).collect();
    contacts.sort_by(by_first_name);
    let mut cats: Vec<Category> = Vec::new();
    for c in raw {
        for t in list_of(c, "tags") {
            let name = s(t, "/displayName");
            if name.is_empty() || cats.iter().any(|x| x.name == name) {
                continue;
            }
            let color = Some(s(t, "/color/backgroundColor"))
                .filter(|x| !x.is_empty())
                .or_else(|| t["color"].as_str().map(str::to_string))
                .unwrap_or_else(|| "Default".into());
            cats.push(Category { name, color });
        }
    }
    cats.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    (contacts, cats)
}

/// All your contacts, by first name, and your categories.
pub async fn list(client: &TeamsClient) -> Result<(Vec<Contact>, Vec<Category>)> {
    Ok(from_service(&fetch_all(client).await?))
}

/// The body of a new contact as the contacts service takes it.
pub fn new_body(c: &NewContact) -> Result<Value> {
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
    let mut body = serde_json::json!({
        "names": [{ "displayName": display, "first": first, "last": last, "source": { "type": "UserProvided" } }],
    });
    if !email.is_empty() {
        if !email.contains('@') || email.contains(char::is_whitespace) {
            bail!("That email address doesn't look right");
        }
        body["emails"] = serde_json::json!([{ "address": email, "type": "Main", "source": { "type": "UserProvided" } }]);
        // The service takes a default email only with an MRI (someone in a
        // directory); a typed contact keeps its email in `emails`.
    }
    if !c.mobile.trim().is_empty() {
        body["phones"] = serde_json::json!([{ "number": c.mobile.trim(), "type": "Mobile", "source": { "type": "UserProvided" } }]);
    }
    if !c.company.trim().is_empty() || !c.job_title.trim().is_empty() {
        body["positions"] = serde_json::json!([{ "detail": { "jobTitle": c.job_title.trim(),
            "company": { "displayName": c.company.trim() } }, "source": { "type": "UserProvided" } }]);
    }
    Ok(body)
}

/// Add a contact (Add new contact): `POST {mt}/beta/contactsv3/`.
pub async fn create(client: &TeamsClient, c: &NewContact) -> Result<Contact> {
    let body = new_body(c)?;
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let resp = client
        .http()
        .post(format!("{base}/beta/contactsv3/"))
        .bearer_auth(&token)
        .header("x-ms-client-caller", "PeopleApp")
        .json(&body)
        .send()
        .await
        .context("Add contact")?;
    if !resp.status().is_success() {
        let code = resp.status().as_u16();
        let text = resp.text().await.unwrap_or_default();
        bail!(
            "HTTP {code} adding the contact: {}",
            text.chars().take(300).collect::<String>()
        );
    }
    let v: Value = resp.json().await.context("Add contact reply")?;
    parse(&v).context("The new contact came back empty")
}

/// Teams' tag change for one contact: the system tag added ("Post") or
/// removed ("Delete").
pub fn favorite_body(id: &str, mri: &str, email: &str, on: bool) -> Value {
    let mut body = serde_json::json!({
        "id": id,
        "systemTags": [{ "displayName": FAVORITES, "action": if on { "Post" } else { "Delete" } }],
    });
    if !mri.is_empty() {
        body["mri"] = serde_json::json!(mri);
        if !email.is_empty() {
            body["defaultEmail"] = serde_json::json!(email);
        }
    }
    body
}

/// Add to favorites / Remove from favorites: `PATCH {mt}/beta/contactsv3/{id}?isConcatenatedId=false`.
pub async fn set_favorite(
    client: &TeamsClient,
    id: &str,
    mri: &str,
    email: &str,
    on: bool,
) -> Result<()> {
    let id = check_id(id)?;
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let path = enc(&id.replace('/', "-"));
    let resp = client
        .http()
        .patch(format!(
            "{base}/beta/contactsv3/{path}?isConcatenatedId=false"
        ))
        .bearer_auth(&token)
        .header("x-ms-client-caller", "PeopleApp")
        .json(&favorite_body(id, mri, email, on))
        .send()
        .await
        .context("Favorites")?;
    if !resp.status().is_success() {
        bail!("HTTP {} changing favorites", resp.status().as_u16());
    }
    Ok(())
}

/// Delete a contact: `DELETE {mt}/beta/contactsv3/{id}`.
pub async fn delete(client: &TeamsClient, id: &str) -> Result<()> {
    let id = check_id(id)?;
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let resp = client
        .http()
        .delete(format!("{base}/beta/contactsv3/{}", enc(id)))
        .bearer_auth(&token)
        .header("x-ms-client-caller", "PeopleApp")
        .send()
        .await
        .context("Delete contact")?;
    // Teams counts "not found" as already gone.
    if !resp.status().is_success() && resp.status().as_u16() != 404 {
        bail!("HTTP {} deleting the contact", resp.status().as_u16());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ost-test1's contact as Teams' contacts store held it (winpc,
    /// 2026-11-26), cut down.
    fn randy() -> Value {
        serde_json::json!({
            "mri": "8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3",
            "defaultEmail": "Randy@scnetsolutions.com",
            "systemTags": [],
            "names": [
                { "displayName": "", "pronunciation": {}, "source": { "type": "UserProvided" } },
                { "displayName": "Randy Northrup", "first": "Randy", "last": "Northrup", "source": { "type": "Profile" } }
            ],
            "emails": [{ "address": "Randy@scnetsolutions.com", "type": "Main" }],
            "phones": [{ "number": "8057942764", "type": "Business" }],
            "positions": [{ "detail": { "jobTitle": "", "company": { "displayName": "", "department": "", "officeLocation": "" } } }],
            "tags": [],
            "id": "RgAAAAA0muypPkEfSo1TIDo1hz1JBwAoeJYpky6cRJa_x7eslmJiAAAAAAElAAAoeJYpky6cRJa_x7eslmJiAAAAACiSAAAA0",
            "createdDateTime": "2026-11-05T06:09:33.8442932+00:00"
        })
    }

    #[test]
    fn contacts_read_as_teams_shows_them() {
        let other = serde_json::json!({
            "id": "AAA=", "emails": [{ "address": "amy@x.com" }],
            "names": [{ "first": "Amy", "last": "Able" }],
            "phones": [{ "number": "555", "type": "Mobile" }],
            "positions": [{ "detail": { "jobTitle": "Lead", "company": { "displayName": "Contoso", "officeLocation": "B1" } } }],
            "tags": [{ "displayName": "Red category", "color": { "backgroundColor": "Red" } }],
            "systemTags": [{ "displayName": "SfbFavorites" }, { "displayName": "Tagged" }]
        });
        let (list, cats) = from_service(&[randy(), other, serde_json::json!({ "names": [] })]);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].name, "Amy Able");
        assert!(list[0].favorite);
        assert_eq!(
            (
                list[0].company.as_str(),
                list[0].office_location.as_str(),
                list[0].mobile.as_str()
            ),
            ("Contoso", "B1", "555")
        );
        assert_eq!(list[1].name, "Randy Northrup");
        assert_eq!(list[1].email, "Randy@scnetsolutions.com");
        assert_eq!(list[1].phone, "8057942764");
        assert!(!list[1].favorite);
        assert_eq!(
            cats,
            vec![Category {
                name: "Red category".into(),
                color: "Red".into()
            }]
        );
    }

    #[test]
    fn changes_are_teams_bodies() {
        assert_eq!(
            favorite_body("c1", "8:orgid:a", "a@x", true).to_string(),
            r#"{"defaultEmail":"a@x","id":"c1","mri":"8:orgid:a","systemTags":[{"action":"Post","displayName":"SfbFavorites"}]}"#
        );
        assert_eq!(
            favorite_body("c1", "", "a@x", false).to_string(),
            r#"{"id":"c1","systemTags":[{"action":"Delete","displayName":"SfbFavorites"}]}"#
        );
        let b = new_body(&NewContact {
            first: "Amy".into(),
            email: "amy@x.com".into(),
            ..Default::default()
        })
        .unwrap();
        assert_eq!(b["names"][0]["displayName"], "Amy");
        assert_eq!(b["emails"][0]["address"], "amy@x.com");
        assert!(b.get("defaultEmail").is_none());
        assert!(new_body(&NewContact::default()).is_err());
        assert!(
            new_body(&NewContact {
                email: "nope".into(),
                ..Default::default()
            })
            .is_err()
        );
    }

    #[test]
    fn ids_are_checked() {
        assert!(check_id("AAMkAGI2T-_=").is_ok());
        assert!(check_id("RgAA+b/c=").is_ok());
        assert!(check_id("../me").is_err());
        assert!(check_id("a b").is_err());
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
            c["systemTags"]
                .as_array()
                .into_iter()
                .flatten()
                .any(|t| t["displayName"].as_str() == Some("Tagged"))
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
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let mut out = Vec::new();
    let mut skip = String::new();
    for _ in 0..20 {
        let mut url = format!("{base}/beta/contactsv3/?pageSize=1000");
        if !skip.is_empty() {
            url.push_str(&format!("&skipToken={skip}"));
        }
        let v: serde_json::Value = client
            .http()
            .get(url)
            .bearer_auth(&token)
            .send()
            .await?
            .error_for_status()
            .context("Contacts")?
            .json()
            .await?;
        out.extend(tagged_from(&v));
        skip = v["skipToken"]
            .as_str()
            .or(v["nextSkipToken"].as_str())
            .unwrap_or_default()
            .to_string();
        if skip.is_empty() {
            break;
        }
    }
    Ok(out)
}

/// Teams' Notify when available body: the person as a contact with the
/// "Tagged" system tag.
pub fn notify_body(mri: &str, tenant: &str) -> serde_json::Value {
    let oid = crate::identity::work_object_id(mri).unwrap_or(mri);
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
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
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
pub async fn stop_notify(
    client: &TeamsClient,
    contact_id: &str,
    mri: &str,
    email: &str,
) -> Result<()> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
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
            notify_body(
                "8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3",
                "2716d134-5614-4856-a48d-2002edd9a570"
            )
            .to_string(),
            r#"{"mri":"8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3","names":[],"systemTags":[{"displayName":"Tagged"}],"webAccounts":[{"service":{"name":"Profile"},"source":{"type":"Profile"},"userId":"OID:5050c9d6-b8a7-41f2-830a-0c51777b7dc3@2716d134-5614-4856-a48d-2002edd9a570"}]}"#
        );
        let v = serde_json::json!({"contacts": [
            {"id": "c1", "mri": "8:orgid:A", "defaultEmail": "a@x", "systemTags": [{"displayName": "Tagged"}]},
            {"id": "c2", "mri": "8:orgid:b", "systemTags": []}]});
        assert_eq!(
            tagged_from(&v),
            vec![("8:orgid:a".to_string(), "c1".to_string(), "a@x".to_string())]
        );
    }
}

// ---- Blocked people and priority access (Settings ▸ Privacy) ----

/// Teams' two people lists in its user settings: who you blocked
/// ("blocklist") and who can reach you in Do not disturb
/// ("breakthroughlist", Manage priority access).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeopleList {
    Blocked,
    Priority,
}

impl PeopleList {
    fn path(self) -> &'static str {
        match self {
            PeopleList::Blocked => "blocklist",
            PeopleList::Priority => "breakthroughlist",
        }
    }
}

/// The list's MRIs (`GET {mt}/beta/userSettings/{list}`: `{value: [mri]}`).
pub async fn people_list(client: &TeamsClient, list: PeopleList) -> Result<Vec<String>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let resp = client
        .http()
        .get(format!("{base}/beta/userSettings/{}", list.path()))
        .bearer_auth(&token)
        .header("x-ms-client-caller", "settings")
        .send()
        .await
        .context("people list")?;
    if !resp.status().is_success() {
        bail!("HTTP {} for {}", resp.status().as_u16(), list.path());
    }
    let v: serde_json::Value = resp.json().await.context("people list reply")?;
    Ok(list_mris(&v))
}

fn list_mris(v: &serde_json::Value) -> Vec<String> {
    v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| m.as_str().map(str::to_lowercase))
        .collect()
}

/// Add or remove someone (`POST {mt}/beta/userSettings/{list}/manage` with
/// `{add: [mri]}` or `{remove: [mri]}`).
pub async fn manage_people_list(
    client: &TeamsClient,
    list: PeopleList,
    mri: &str,
    add: bool,
) -> Result<()> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let body = if add {
        serde_json::json!({ "add": [mri] })
    } else {
        serde_json::json!({ "remove": [mri] })
    };
    let resp = client
        .http()
        .post(format!("{base}/beta/userSettings/{}/manage", list.path()))
        .bearer_auth(&token)
        .header("x-ms-client-caller", "settings")
        .json(&body)
        .send()
        .await
        .context("people list change")?;
    if !resp.status().is_success() {
        bail!("HTTP {} changing {}", resp.status().as_u16(), list.path());
    }
    Ok(())
}

#[cfg(test)]
mod people_list_tests {
    #[test]
    fn mris_as_the_list_sends_them() {
        let v = serde_json::json!({"value": ["8:orgid:ABC", "8:orgid:def"], "type": "System.Collections.Generic.List"});
        assert_eq!(super::list_mris(&v), ["8:orgid:abc", "8:orgid:def"]);
        assert!(super::list_mris(&serde_json::json!({})).is_empty());
    }
}
