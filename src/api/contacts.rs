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
#[serde(default)]
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
    /// On speed dial (the "Favorites" system tag; Add to speed dial).
    pub speed_dial: bool,
    /// Every address and number, for Find a contact (Teams matches any).
    pub emails: Vec<String>,
    pub phones: Vec<String>,
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
/// Speed dial's system tag (Teams' calling `ZA.Favorites`).
const SPEED_DIAL: &str = "Favorites";

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
        speed_dial: has_tag(c, "systemTags", SPEED_DIAL),
        emails: list_of(c, "emails")
            .map(|e| s(e, "/address"))
            .filter(|a| !a.is_empty())
            .collect(),
        phones: list_of(c, "phones")
            .map(|p| s(p, "/number"))
            .filter(|n| !n.is_empty())
            .collect(),
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
    cats.sort_by_key(|c| c.name.to_lowercase());
    (contacts, cats)
}

/// All your contacts, by first name, and your categories.
pub async fn list(client: &TeamsClient) -> Result<(Vec<Contact>, Vec<Category>)> {
    let (mut contacts, cats) = from_service(&fetch_all(client).await?);
    // Someone added from the directory may have no name of their own in
    // the contact (the service answers Teams' add with an empty name):
    // Teams shows their profile's, as here.
    let unnamed: Vec<String> = contacts
        .iter()
        .filter(|c| needs_profile_name(c))
        .map(|c| c.mri.clone())
        .collect();
    if !unnamed.is_empty()
        && let Ok(records) = super::directory::short_profile_records(client, &unnamed).await
    {
        apply_profile_names(&mut contacts, &records);
        contacts.sort_by(by_first_name);
    }
    Ok((contacts, cats))
}

fn needs_profile_name(c: &Contact) -> bool {
    !c.mri.is_empty()
        && c.first.is_empty()
        && c.last.is_empty()
        && (c.name == c.email || c.name == "(No name)")
}

/// Profile names (fetchShortProfile records) for contacts without one.
fn apply_profile_names(contacts: &mut [Contact], records: &[Value]) {
    for c in contacts.iter_mut().filter(|c| needs_profile_name(c)) {
        let Some(p) = records.iter().find(|p| {
            p["mri"]
                .as_str()
                .is_some_and(|m| m.eq_ignore_ascii_case(&c.mri))
        }) else {
            continue;
        };
        let g = |k: &str| p[k].as_str().unwrap_or_default().to_string();
        if !g("displayName").is_empty() {
            c.name = g("displayName");
            c.first = g("givenName");
            c.last = g("surname");
        }
    }
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
    patch(
        client,
        id,
        &favorite_body(id, mri, email, on),
        "changing favorites",
    )
    .await
}

/// A contact's change in the contacts service:
/// `PATCH {mt}/beta/contactsv3/{id}?isConcatenatedId=false`, as Teams
/// sends favorites, speed dial, categories and edits.
async fn patch(client: &TeamsClient, id: &str, body: &Value, what: &str) -> Result<()> {
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
        .json(body)
        .send()
        .await
        .context("Contact change")?;
    if !resp.status().is_success() {
        bail!("HTTP {} {what}", resp.status().as_u16());
    }
    Ok(())
}

/// Teams' tag change for one contact: `key` "systemTags" (favorites,
/// speed dial) or "tags" (categories), the tag added ("Post") or removed
/// ("Delete"); someone in a directory goes by their MRI and email too.
pub fn tag_body(id: &str, mri: &str, email: &str, key: &str, tag: Value) -> Value {
    let mut body = serde_json::json!({ "id": id });
    body[key] = serde_json::json!([tag]);
    if !mri.is_empty() {
        body["mri"] = serde_json::json!(mri);
        if !email.is_empty() {
            body["defaultEmail"] = serde_json::json!(email);
        }
    }
    body
}

/// Add to speed dial / Remove from speed dial (the "Favorites" system tag).
pub async fn set_speed_dial(
    client: &TeamsClient,
    id: &str,
    mri: &str,
    email: &str,
    on: bool,
) -> Result<()> {
    let tag = serde_json::json!({ "displayName": SPEED_DIAL, "action": if on { "Post" } else { "Delete" } });
    patch(
        client,
        id,
        &tag_body(id, mri, email, "systemTags", tag),
        "changing speed dial",
    )
    .await
}

/// A category's tag as Teams adds it (its colour as background and text;
/// a new category has none, "DEFAULT").
pub fn category_tag(name: &str, color: &str, on: bool) -> Value {
    let color = if color.trim().is_empty() {
        "DEFAULT"
    } else {
        color.trim()
    };
    if on {
        serde_json::json!({ "displayName": name.trim(), "color": { "backgroundColor": color, "textColor": color }, "action": "Post" })
    } else {
        serde_json::json!({ "displayName": name.trim(), "action": "Delete" })
    }
}

/// Add category ▸ a category (or a new one) / remove it from a contact.
pub async fn set_category(
    client: &TeamsClient,
    c: &Contact,
    name: &str,
    color: &str,
    on: bool,
) -> Result<()> {
    if name.trim().is_empty() || name.len() > 255 {
        bail!("A category needs a name");
    }
    let raw = raw_contact(client, &c.id).await?;
    patch(
        client,
        &c.id,
        &category_body(&raw, c, name, color, on),
        "changing the category",
    )
    .await
}

/// Teams' category change (its tag mutation): the contact's other tags as
/// they are, then this one — added ("Post"), or removed ("Delete", with
/// the tag's id).
pub fn category_body(raw: &Value, c: &Contact, name: &str, color: &str, on: bool) -> Value {
    let name = name.trim();
    let mut tags: Vec<Value> = list_of(raw, "tags")
        .filter(|t| t["displayName"].as_str() != Some(name))
        .cloned()
        .collect();
    let mut tag = category_tag(name, color, on);
    if !on
        && let Some(id) = list_of(raw, "tags")
            .find(|t| t["displayName"].as_str() == Some(name))
            .and_then(|t| t["id"].as_str())
    {
        tag["id"] = serde_json::json!(id);
    }
    tags.push(tag);
    let mut body = tag_body(&c.id, &c.mri, &c.email, "tags", Value::Null);
    body["tags"] = Value::Array(tags);
    body
}

/// Edit contact's fields (Teams' form: First name, Last name, Email,
/// Phone, Company). Someone in a directory keeps the name, email and
/// phone from their profile: only Company changes.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct ContactEdit {
    #[serde(default)]
    pub first: String,
    #[serde(default)]
    pub last: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub phone: String,
    #[serde(default)]
    pub company: String,
}

fn check_email(email: &str) -> Result<()> {
    if !email.is_empty() && (!email.contains('@') || email.contains(char::is_whitespace)) {
        bail!("That email address doesn't look right");
    }
    Ok(())
}

fn joined(first: &str, last: &str) -> String {
    [first, last]
        .iter()
        .filter(|p| !p.is_empty())
        .cloned()
        .collect::<Vec<_>>()
        .join(" ")
}

fn company_positions(company: &str) -> Value {
    if company.trim().is_empty() {
        serde_json::json!([])
    } else {
        serde_json::json!([{ "detail": { "company": { "displayName": company.trim() } }, "source": { "type": "UserProvided" } }])
    }
}

fn typed_phones(phone: &str) -> Value {
    if phone.trim().is_empty() {
        serde_json::json!([])
    } else {
        serde_json::json!([{ "number": phone.trim(), "type": "Mobile", "source": { "type": "UserProvided" } }])
    }
}

/// The edit as Teams makes it (its PersonUpdateContact resolver): the
/// contact as the service holds it, with each changed entry marked — a
/// new one "Post" (UserProvided), a changed one "Patch" (its id kept), an
/// emptied one "Delete" — sent back whole.
pub fn edit_body(raw: &Value, c: &Contact, e: &ContactEdit) -> Result<Value> {
    let mut body = raw.clone();
    // `shown`: the entry the form showed (its value as the contact read
    // it), else the contact's own first one.
    let mut change = |key: &str,
                      new: Option<Value>,
                      same: &dyn Fn(&Value) -> bool,
                      shown: &dyn Fn(&Value) -> bool| {
        let mut list = body
            .get_mut(key)
            .and_then(|v| v.as_array_mut())
            .map(std::mem::take)
            .unwrap_or_default();
        let own = list
            .iter()
            .position(shown)
            .or_else(|| {
                list.iter()
                    .position(|x| x["source"]["type"].as_str() == Some("UserProvided"))
            })
            .or(if list.is_empty() { None } else { Some(0) });
        match (own, new) {
            (Some(i), Some(n)) if !same(&list[i]) => {
                let mut merged = list[i].clone();
                if let (Some(m), Some(n)) = (merged.as_object_mut(), n.as_object()) {
                    for (k, v) in n {
                        // (A number keeps its own kind: Business stays Business.)
                        if k == "type" && m.contains_key("type") {
                            continue;
                        }
                        m.insert(k.clone(), v.clone());
                    }
                    m.insert(
                        "source".into(),
                        serde_json::json!({ "type": "UserProvided" }),
                    );
                    m.insert("action".into(), serde_json::json!("Patch"));
                }
                list[i] = merged;
            }
            (Some(i), None) => list[i]["action"] = serde_json::json!("Delete"),
            (None, Some(mut n)) => {
                n["source"] = serde_json::json!({ "type": "UserProvided" });
                n["action"] = serde_json::json!("Post");
                list.push(n);
            }
            _ => {}
        }
        body[key] = Value::Array(list);
    };
    if c.mri.is_empty() {
        let (first, last, email, phone) = (
            e.first.trim(),
            e.last.trim(),
            e.email.trim(),
            e.phone.trim(),
        );
        if first.is_empty() {
            bail!("A contact needs a first name");
        }
        check_email(email)?;
        let display = joined(first, last);
        // The form shows the business number, else the mobile one.
        let shown_phone = if c.phone.is_empty() {
            c.mobile.clone()
        } else {
            c.phone.clone()
        };
        change(
            "names",
            Some(serde_json::json!({ "displayName": display, "first": first, "last": last })),
            &|x| s(x, "/first") == first && s(x, "/last") == last,
            &|x| s(x, "/first") == c.first && s(x, "/last") == c.last,
        );
        change(
            "emails",
            (!email.is_empty()).then(|| serde_json::json!({ "address": email, "type": "Main" })),
            &|x| s(x, "/address") == email,
            &|x| !c.email.is_empty() && s(x, "/address") == c.email,
        );
        change(
            "phones",
            (!phone.is_empty()).then(|| serde_json::json!({ "number": phone, "type": "Mobile" })),
            &|x| s(x, "/number") == phone,
            &|x| !shown_phone.is_empty() && s(x, "/number") == shown_phone.as_str(),
        );
    }
    // Company: only when it changed, and only the company's name in the
    // position the contact read (its job title and office stay).
    let company = e.company.trim();
    if company != c.company {
        let company_of = |x: &Value| s(x, "/detail/company/displayName");
        let mut list = body
            .get_mut("positions")
            .and_then(|v| v.as_array_mut())
            .map(std::mem::take)
            .unwrap_or_default();
        let at = list
            .iter()
            .position(|x| !c.company.is_empty() && company_of(x) == c.company)
            .or_else(|| {
                list.iter()
                    .position(|x| x["source"]["type"].as_str() == Some("UserProvided"))
            })
            .or(if list.is_empty() { None } else { Some(0) });
        match at {
            Some(i) => {
                let p = &mut list[i];
                p["detail"]["company"]["displayName"] = serde_json::json!(company);
                p["source"] = serde_json::json!({ "type": "UserProvided" });
                p["action"] = serde_json::json!("Patch");
            }
            None => list.push(serde_json::json!({ "detail": { "company": { "displayName": company } },
                                                 "source": { "type": "UserProvided" }, "action": "Post" })),
        }
        body["positions"] = Value::Array(list);
    }
    Ok(body)
}

/// The contact as the service holds it.
async fn raw_contact(client: &TeamsClient, id: &str) -> Result<Value> {
    fetch_all(client)
        .await?
        .into_iter()
        .find(|c| c["id"].as_str() == Some(id))
        .context("That contact is gone")
}

/// Save Edit contact.
pub async fn edit(client: &TeamsClient, c: &Contact, e: &ContactEdit) -> Result<()> {
    let raw = raw_contact(client, &c.id).await?;
    patch(client, &c.id, &edit_body(&raw, c, e)?, "saving the contact").await
}

// ---- Add to contacts: Teams' people picker ("Type a name or number") ----

/// Someone the picker offers: a person in the directory (or a guest), or
/// the number typed ("External").
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Candidate {
    #[serde(default)]
    pub mri: String,
    #[serde(default)]
    pub object_id: String,
    #[serde(default)]
    pub tenant_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub given: String,
    #[serde(default)]
    pub surname: String,
    #[serde(default)]
    pub mail: String,
    #[serde(default)]
    pub upn: String,
    /// The second line: the address's name in capitals ("OST-TEST2").
    #[serde(default)]
    pub detail: String,
    #[serde(default)]
    pub guest: bool,
    /// A number typed into the picker, as Teams shows it ("+1 555-123-4567").
    #[serde(default)]
    pub phone: String,
}

/// A searchV2 result as the picker shows it.
pub fn candidate_from(v: &Value) -> Option<Candidate> {
    let g = |k: &str| v[k].as_str().unwrap_or_default().to_string();
    let object_id = g("objectId");
    if object_id.is_empty() || v["objectType"].as_str().is_some_and(|t| t != "User") {
        return None;
    }
    let mail = [g("email"), g("mail"), g("userPrincipalName")]
        .into_iter()
        .find(|m| !m.is_empty())
        .unwrap_or_default();
    let tenant_id = g("id")
        .split_once('@')
        .map(|(_, t)| t.to_string())
        .unwrap_or_default();
    Some(Candidate {
        mri: v["mri"]
            .as_str()
            .map(str::to_string)
            .unwrap_or_else(|| crate::identity::work_user_mri(&object_id)),
        object_id,
        tenant_id,
        name: g("displayName"),
        given: g("givenName"),
        surname: g("surname"),
        detail: mail.split('@').next().unwrap_or_default().to_uppercase(),
        guest: g("userType").eq_ignore_ascii_case("guest")
            || g("role").eq_ignore_ascii_case("guest"),
        upn: g("userPrincipalName"),
        mail,
        phone: String::new(),
    })
}

/// The picker's people: Teams searches as `POST {mt}/beta/users/searchV2
/// ?includeDLs=false&enableGuest=true&includeBots=true&skypeTeamsInfo=true
/// &source=allTrue` with the typed text as the body (winpc, 2026-11-26).
pub async fn search_people(client: &TeamsClient, query: &str) -> Result<Vec<Candidate>> {
    let q = query.trim();
    if q.is_empty() {
        return Ok(Vec::new());
    }
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let v: Value = client
        .http()
        .post(format!(
            "{base}/beta/users/searchV2?includeDLs=false&enableGuest=true&includeBots=true&skypeTeamsInfo=true&source=allTrue"
        ))
        .bearer_auth(&token)
        .header("content-type", "text/plain")
        .body(q.to_string())
        .send()
        .await?
        .error_for_status()?
        .json()
        .await
        .context("Search")?;
    Ok(v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(candidate_from)
        .collect())
}

/// The number Teams reads in the typed text, as its picker shows it: the
/// letters as on a phone's keypad (OST → +1678), a 10-digit number as
/// "+1 555-123-4567", otherwise "+1" and the digits ("+" keeps its own
/// country). None when the text holds anything but letters, digits,
/// spaces and + ( ) - . characters.
pub fn typed_number(text: &str) -> Option<String> {
    let t = text.trim();
    if t.is_empty()
        || !t
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || " +()-.".contains(c))
    {
        return None;
    }
    let keypad = |c: char| -> Option<char> {
        let c = c.to_ascii_lowercase();
        Some(match c {
            '0'..='9' => c,
            'a'..='c' => '2',
            'd'..='f' => '3',
            'g'..='i' => '4',
            'j'..='l' => '5',
            'm'..='o' => '6',
            'p'..='s' => '7',
            't'..='v' => '8',
            'w'..='z' => '9',
            _ => return None,
        })
    };
    let digits: String = t.chars().filter_map(keypad).collect();
    if digits.is_empty() {
        return None;
    }
    if t.starts_with('+') {
        return Some(format!("+{digits}"));
    }
    let national = digits
        .strip_prefix('1')
        .filter(|d| d.len() == 10)
        .unwrap_or(&digits);
    if national.len() == 10 {
        return Some(format!(
            "+1 {}-{}-{}",
            &national[..3],
            &national[3..6],
            &national[6..]
        ));
    }
    Some(format!("+1{digits}"))
}

/// Add contact's form after the picker (First name, Last name, Email,
/// Phone, Company).
#[derive(Debug, Clone, Default, Deserialize)]
pub struct PickedContact {
    #[serde(default)]
    pub person: Candidate,
    #[serde(default)]
    pub first: String,
    #[serde(default)]
    pub last: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub phone: String,
    #[serde(default)]
    pub company: String,
}

/// The body Teams posts for the picked person (captured on winpc
/// 2026-11-26): the profile's name, the address, and the person's
/// profile accounts; a number gets the form's name and the number.
pub fn picked_body(p: &PickedContact) -> Result<Value> {
    let person = &p.person;
    let phones = typed_phones(&p.phone);
    let positions = company_positions(&p.company);
    if person.mri.is_empty() {
        let (first, last, email) = (p.first.trim(), p.last.trim(), p.email.trim());
        if first.is_empty() {
            bail!("A contact needs a first name");
        }
        check_email(email)?;
        let emails = if email.is_empty() {
            serde_json::json!([])
        } else {
            serde_json::json!([{ "address": email, "type": "Main", "source": { "type": "UserProvided" } }])
        };
        return Ok(serde_json::json!({
            "names": [{ "displayName": joined(first, last), "first": first, "last": last, "middle": "", "nickname": "", "suffix": "", "title": "",
                        "pronunciation": { "first": "", "last": "" }, "source": { "type": "UserProvided" } }],
            "emails": emails,
            "phones": phones,
            "addresses": [], "positions": positions, "notes": [], "anniversaries": [], "relationships": [], "websites": [],
            "webAccounts": [], "tags": []
        }));
    }
    if !person.mri.starts_with("8:") {
        bail!("Not a person");
    }
    let mail = if person.mail.is_empty() {
        person.upn.clone()
    } else {
        person.mail.clone()
    };
    let user = if person.upn.is_empty() {
        mail.clone()
    } else {
        person.upn.clone()
    };
    let mut accounts = vec![serde_json::json!({ "userId": user, "source": { "type": "Profile" } })];
    if !person.object_id.is_empty() && !person.tenant_id.is_empty() {
        accounts.push(serde_json::json!({ "userId": format!("OID:{}@{}", person.object_id, person.tenant_id),
                                          "service": { "name": "Profile" }, "source": { "type": "Profile" } }));
    }
    let emails = if mail.is_empty() {
        serde_json::json!([])
    } else {
        serde_json::json!([{ "address": mail, "type": "Main", "source": { "type": "UserProvided" } }])
    };
    Ok(serde_json::json!({
        "mri": person.mri,
        "defaultEmail": mail,
        "names": [{ "displayName": person.name, "first": person.given, "last": person.surname, "middle": "", "nickname": "", "suffix": "",
                    "title": "", "pronunciation": { "first": "", "last": "" }, "source": { "type": "Profile" } }],
        "emails": emails,
        "phones": phones,
        "addresses": [], "positions": positions, "notes": [], "anniversaries": [], "relationships": [], "websites": [],
        "webAccounts": accounts,
        "tags": []
    }))
}

/// Add contact's Save: `POST {mt}/beta/contactsv3/` with Teams' body.
pub async fn add_picked(client: &TeamsClient, p: &PickedContact) -> Result<()> {
    let body = picked_body(p)?;
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
        bail!("HTTP {} adding the contact", resp.status().as_u16());
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
    fn picker_reads_numbers_as_teams() {
        // Teams' picker on winpc (2026-11-26): "OST" → "+1678",
        // "5551234567" → "+1 555-123-4567", "OST Test 2" → "+167883782".
        assert_eq!(typed_number("OST").as_deref(), Some("+1678"));
        assert_eq!(
            typed_number("5551234567").as_deref(),
            Some("+1 555-123-4567")
        );
        assert_eq!(typed_number("OST Test 2").as_deref(), Some("+167883782"));
        assert_eq!(typed_number("+44 20 7946").as_deref(), Some("+44207946"));
        assert_eq!(typed_number("amy@x.com"), None);
        assert_eq!(typed_number("  "), None);
    }

    /// OST Test 2 as Teams' picker search (searchV2) returned it.
    fn test2() -> Value {
        serde_json::json!({
            "alias": "ost-test2", "mail": "ost-test2@scnetsolutions.com", "objectType": "User",
            "id": "9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5@2716d134-5614-4856-a48d-2002edd9a570",
            "userPrincipalName": "ost-test2@scnetsolutions.com", "givenName": "OST", "surname": "Test 2",
            "email": "ost-test2@scnetsolutions.com", "userType": "Member", "displayName": "OST Test 2",
            "type": "ADUser", "mri": "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5",
            "objectId": "9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5"
        })
    }

    #[test]
    fn picked_person_is_teams_body() {
        let c = candidate_from(&test2()).unwrap();
        assert_eq!((c.detail.as_str(), c.guest), ("OST-TEST2", false));
        let guest = candidate_from(&serde_json::json!({
            "objectType": "User", "role": "Guest", "objectId": "21ff", "displayName": "OST Guest 02",
            "mail": "ostguest02@osttestlab2611.onmicrosoft.com", "userType": "Guest",
            "userPrincipalName": "ostguest02_osttestlab2611.onmicrosoft.com#EXT#@scnetsolutions.onmicrosoft.com"
        }))
        .unwrap();
        assert_eq!((guest.detail.as_str(), guest.guest), ("OSTGUEST02", true));
        // The body Teams posted for OST Test 2 (winpc, 2026-11-26).
        let teams: Value = serde_json::from_str(r#"{"mri":"8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5","defaultEmail":"ost-test2@scnetsolutions.com","names":[{"displayName":"OST Test 2","first":"OST","last":"Test 2","middle":"","nickname":"","suffix":"","title":"","pronunciation":{"first":"","last":""},"source":{"type":"Profile"}}],"emails":[{"address":"ost-test2@scnetsolutions.com","type":"Main","source":{"type":"UserProvided"}}],"phones":[],"addresses":[],"positions":[],"notes":[],"anniversaries":[],"relationships":[],"websites":[],"webAccounts":[{"userId":"ost-test2@scnetsolutions.com","source":{"type":"Profile"}},{"userId":"OID:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5@2716d134-5614-4856-a48d-2002edd9a570","service":{"name":"Profile"},"source":{"type":"Profile"}}],"tags":[]}"#).unwrap();
        let body = picked_body(&PickedContact {
            person: c,
            ..Default::default()
        })
        .unwrap();
        assert_eq!(body, teams);
        // A number: the form's name, the number.
        let n = picked_body(&PickedContact {
            person: Candidate {
                phone: "+1 555-123-4567".into(),
                ..Default::default()
            },
            first: "Amy".into(),
            phone: "+1 555-123-4567".into(),
            ..Default::default()
        })
        .unwrap();
        assert_eq!(n["names"][0]["displayName"], "Amy");
        assert_eq!(n["phones"][0]["number"], "+1 555-123-4567");
        assert!(n.get("mri").is_none());
        assert!(
            picked_body(&PickedContact {
                phone: "1".into(),
                ..Default::default()
            })
            .is_err()
        );
    }

    #[test]
    fn unnamed_directory_contacts_take_profile_names() {
        // The contact Teams' add made for OST Test 2: no name of its own.
        let raw = serde_json::json!({
            "id": "RgAA=", "mri": "8:orgid:9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5",
            "names": [{ "displayName": "", "pronunciation": {} }],
            "emails": [{ "address": "ost-test2@scnetsolutions.com" }]
        });
        let (mut list, _) = from_service(&[raw]);
        assert_eq!(list[0].name, "ost-test2@scnetsolutions.com");
        assert!(needs_profile_name(&list[0]));
        apply_profile_names(
            &mut list,
            &[
                serde_json::json!({ "mri": "8:orgid:9EDCC62F-2F4B-4F55-BBF9-02C7CBAADBB5", "displayName": "OST Test 2", "givenName": "OST", "surname": "Test 2" }),
            ],
        );
        assert_eq!(
            (list[0].name.as_str(), list[0].first.as_str()),
            ("OST Test 2", "OST")
        );
    }

    #[test]
    fn edits_and_tags_are_teams_bodies() {
        let raw = randy();
        let (list, _) = from_service(std::slice::from_ref(&raw));
        let r = &list[0];
        let b = edit_body(
            &raw,
            r,
            &ContactEdit {
                first: "X".into(),
                company: "Contoso".into(),
                ..Default::default()
            },
        )
        .unwrap();
        // Someone in a directory: only Company changes, the contact's
        // position patched in place; the rest goes back as it was.
        assert_eq!(b["names"], raw["names"]);
        assert_eq!(
            b["positions"][0]["detail"]["company"]["displayName"],
            "Contoso"
        );
        assert_eq!(b["positions"][0]["action"], "Patch");
        assert_eq!(b["mri"], "8:orgid:5050c9d6-b8a7-41f2-830a-0c51777b7dc3");
        // A typed contact's emptied email is deleted, a new phone posted.
        let typed = serde_json::json!({ "id": "AAA=", "names": [{ "id": "1", "first": "Amy", "source": { "type": "UserProvided" } }],
                                        "emails": [{ "id": "2", "address": "amy@x.com", "source": { "type": "UserProvided" } }] });
        let (tl, _) = from_service(std::slice::from_ref(&typed));
        let t = edit_body(
            &typed,
            &tl[0],
            &ContactEdit {
                first: "Amy".into(),
                phone: "555".into(),
                ..Default::default()
            },
        )
        .unwrap();
        assert!(t["names"][0].get("action").is_none());
        assert_eq!(t["emails"][0]["action"], "Delete");
        // Two numbers: the form shows (and edits) the business one; the
        // mobile one is left alone.
        let two = serde_json::json!({ "id": "BBB=", "names": [{ "first": "Bo", "source": { "type": "UserProvided" } }],
                                      "phones": [{ "id": "m", "number": "111", "type": "Mobile", "source": { "type": "UserProvided" } },
                                                 { "id": "b", "number": "222", "type": "Business", "source": { "type": "UserProvided" } }] });
        let (bl, _) = from_service(std::slice::from_ref(&two));
        assert_eq!(bl[0].phone, "222");
        let same = edit_body(
            &two,
            &bl[0],
            &ContactEdit {
                first: "Bo".into(),
                phone: "222".into(),
                company: "X".into(),
                ..Default::default()
            },
        )
        .unwrap();
        assert!(
            same["phones"]
                .as_array()
                .unwrap()
                .iter()
                .all(|p| p.get("action").is_none())
        );
        let changed = edit_body(
            &two,
            &bl[0],
            &ContactEdit {
                first: "Bo".into(),
                phone: "333".into(),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(changed["phones"][0]["number"], "111");
        // A job title without a company is left alone by an unrelated edit,
        // and a company goes into it without losing the title.
        let titled = serde_json::json!({ "id": "CCC=", "names": [{ "first": "Cy", "source": { "type": "UserProvided" } }],
                                         "positions": [{ "id": "p", "detail": { "jobTitle": "Lead" }, "source": { "type": "UserProvided" } }] });
        let (cy, _) = from_service(std::slice::from_ref(&titled));
        let edit = |company: &str| {
            edit_body(
                &titled,
                &cy[0],
                &ContactEdit {
                    first: "Cy".into(),
                    phone: "9".into(),
                    company: company.into(),
                    ..Default::default()
                },
            )
            .unwrap()
        };
        assert_eq!(edit("")["positions"], titled["positions"]);
        let with = edit("Contoso");
        assert_eq!(
            (
                with["positions"][0]["detail"]["jobTitle"].as_str(),
                with["positions"][0]["detail"]["company"]["displayName"].as_str(),
                with["positions"][0]["action"].as_str()
            ),
            (Some("Lead"), Some("Contoso"), Some("Patch"))
        );
        assert_eq!(
            (
                changed["phones"][1]["number"].as_str(),
                changed["phones"][1]["type"].as_str(),
                changed["phones"][1]["action"].as_str()
            ),
            (Some("333"), Some("Business"), Some("Patch"))
        );
        assert_eq!(
            (
                t["phones"][0]["number"].as_str(),
                t["phones"][0]["action"].as_str()
            ),
            (Some("555"), Some("Post"))
        );
        // Categories: the others as they are, this one added or removed
        // with its id.
        let tagged = serde_json::json!({ "id": "c1", "tags": [{ "id": "t1", "displayName": "Family" }, { "id": "t2", "displayName": "Work" }] });
        let (cl, _) = from_service(std::slice::from_ref(&tagged));
        assert_eq!(
            category_body(&tagged, &cl[0], "Family", "", false).to_string(),
            r#"{"id":"c1","tags":[{"displayName":"Work","id":"t2"},{"action":"Delete","displayName":"Family","id":"t1"}]}"#
        );
        assert_eq!(
            category_body(&tagged, &cl[0], "New", "", true)["tags"][2],
            serde_json::json!({ "action": "Post", "color": { "backgroundColor": "DEFAULT", "textColor": "DEFAULT" }, "displayName": "New" })
        );
        assert!(!r.speed_dial);
        assert_eq!(r.phones, vec!["8057942764".to_string()]);
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
