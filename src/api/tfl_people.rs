//! A personal account's People app, as Teams for personal use (Teams free)
//! keeps it, captured on teams.live.com and Teams 26304 on 2026-11-28
//! (TASK-0295):
//!
//! - Contacts are the middle tier's buddy list (`GET {mt}/beta/contacts/
//!   buddylist?migrationRequested=true&federatedContactsSupported=true&
//!   ggEnabled=true`, bearer plus Skype token), whose `value` holds buddy
//!   groups `{id, displayName, groupType, buddies: [{mri, displayName,
//!   email, phone, phones, companyName, jobTitle, isFederated}]}`; your
//!   contacts are the `TflContacts` group.
//! - The block list is `GET {mt}/beta/userSettings/blocklist?ggEnabled=true`
//!   (`{"value": [mri, …]}`), changed with `POST …/blocklist/manage?
//!   ggEnabled=true` and `{"add": [mri]}` or `{"remove": [mri]}` (202,
//!   `{"value": {"status": "InProgress"}}`).
//! - Delete puts the person on the block list, then takes them out of the
//!   buddy group (`POST {mt}/beta/contacts/buddylist/TflContacts/
//!   managebuddies?ggEnabled=true&skipBuddylistFetch=true` with `{"delete":
//!   [{mri, displayName: mri}]}`), which also takes them off the block list
//!   ("When you delete a contact they'll no longer show up in your contacts
//!   and will be removed from your blocked list."). Blocked users' Delete
//!   is the second step alone.
//! - Invite to Teams copies the link of `POST {mt}/beta/join/template`
//!   `{"messageType": "general"}` → `{"joinUrl": "https://teams.live.com/
//!   l/invite/<id>?v=g1", "template": …}`.

use anyhow::{Context, Result, bail};
use serde::Serialize;
use serde_json::{Value, json};

use super::client::TeamsClient;

/// One of your contacts, as Teams free's People app lists it.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct TflContact {
    pub mri: String,
    pub name: String,
    /// The address they share (empty when they keep it private).
    pub email: String,
    pub phone: String,
    pub company: String,
    pub job_title: String,
    /// A work user (Teams free lists them with their address).
    pub federated: bool,
}

/// Teams free's buddy group of your contacts.
const CONTACTS_GROUP: &str = "TflContacts";

fn s(v: &Value, k: &str) -> String {
    v[k].as_str().unwrap_or_default().trim().to_string()
}

/// A buddy as a contact, or None for one without a person's MRI.
fn buddy(b: &Value) -> Option<TflContact> {
    let mri = s(b, "mri");
    if !crate::identity::is_person_mri(&mri) {
        return None;
    }
    let phone = Some(s(b, "phone")).filter(|p| !p.is_empty()).or_else(|| {
        b["phones"].as_array().and_then(|l| {
            l.iter()
                .find_map(|p| p["number"].as_str().or(p.as_str()).map(str::to_string))
        })
    });
    let name = s(b, "displayName");
    Some(TflContact {
        // (Teams free names a buddy it has no name for by its MRI.)
        name: if name == mri { String::new() } else { name },
        email: s(b, "email"),
        phone: phone.unwrap_or_default(),
        company: s(b, "companyName"),
        job_title: s(b, "jobTitle"),
        federated: b["isFederated"].as_bool().unwrap_or(false)
            || crate::identity::work_object_id(&mri).is_some(),
        mri,
    })
}

/// Your contacts from the buddy list's answer (`{"value": [groups]}`) or
/// a managebuddies answer (one group): the TflContacts group's buddies,
/// once each.
pub fn contacts_from(v: &Value) -> Vec<TflContact> {
    let groups: Vec<&Value> = match v["value"].as_array() {
        Some(l) => l.iter().collect(),
        None if v["buddies"].is_array() => vec![v],
        None => Vec::new(),
    };
    let mut seen = std::collections::HashSet::new();
    groups
        .into_iter()
        .filter(|g| {
            s(g, "groupType").eq_ignore_ascii_case(CONTACTS_GROUP)
                || s(g, "id").eq_ignore_ascii_case(CONTACTS_GROUP)
        })
        .flat_map(|g| g["buddies"].as_array().into_iter().flatten())
        .filter_map(buddy)
        .filter(|c| seen.insert(c.mri.to_ascii_lowercase()))
        .collect()
}

/// The MRIs on a block list answer (`{"value": [mri, …]}`; also takes
/// `{"value": [{"mri": …}]}`).
pub fn blocked_from(v: &Value) -> Vec<String> {
    v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| e.as_str().or_else(|| e["mri"].as_str()))
        .map(str::to_string)
        .filter(|m| crate::identity::is_person_mri(m))
        .collect()
}

fn check_mri(mri: &str) -> Result<()> {
    if !crate::identity::is_person_mri(mri)
        || mri.len() > 256
        || mri.contains(['/', '?', '#', '&', ' '])
    {
        bail!("Not a person");
    }
    Ok(())
}

async fn mt_get(client: &TeamsClient, path: &str, caller: &str) -> Result<Value> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let req = client
        .http()
        .get(format!("{base}/beta/{path}"))
        .header("x-ms-client-type", "cdlworker")
        .header("x-ms-client-caller", caller);
    client
        .middle_tier_auth(req, &token)
        .send()
        .await?
        .error_for_status()
        .with_context(|| format!("People ({caller})"))?
        .json()
        .await
        .context("People reply")
}

async fn mt_post(client: &TeamsClient, path: &str, caller: &str, body: &Value) -> Result<Value> {
    let (base, token) = super::tabs::middle_tier(client).await?;
    let req = client
        .http()
        .post(format!("{base}/beta/{path}"))
        .header("x-ms-client-type", "cdlworker")
        .header("x-ms-client-caller", caller);
    let resp = client
        .middle_tier_auth(req, &token)
        .json(body)
        .send()
        .await?
        .error_for_status()
        .with_context(|| format!("People ({caller})"))?;
    Ok(resp.json().await.unwrap_or(Value::Null))
}

/// Your contacts, with names and addresses from their profiles where the
/// buddy list has none (Teams free fills them from fetchShortProfile; an
/// address the person keeps private isn't shown).
pub async fn contacts(client: &TeamsClient) -> Result<Vec<TflContact>> {
    let v = mt_get(
        client,
        "contacts/buddylist?migrationRequested=true&federatedContactsSupported=true&ggEnabled=true",
        "ContactsApp:getBuddyList",
    )
    .await?;
    let mut list = contacts_from(&v);
    let mris: Vec<String> = list.iter().map(|c| c.mri.clone()).collect();
    if !mris.is_empty() {
        let records = super::directory::short_profile_records(client, &mris)
            .await
            .unwrap_or_else(|e| {
                tracing::debug!("contact profiles: {e:#}");
                Vec::new()
            });
        apply_profiles(&mut list, &records);
    }
    Ok(list)
}

/// Fill contacts' names (and shared addresses) from their profiles.
pub fn apply_profiles(list: &mut [TflContact], records: &[Value]) {
    for c in list.iter_mut() {
        let Some(r) = records.iter().find(|r| {
            r["mri"]
                .as_str()
                .is_some_and(|m| m.eq_ignore_ascii_case(&c.mri))
        }) else {
            continue;
        };
        if let Some(n) = r["displayName"].as_str().filter(|n| !n.trim().is_empty()) {
            c.name = n.trim().to_string();
        }
        if c.email.is_empty()
            && !r["emailPrivate"].as_bool().unwrap_or(false)
            && let Some(e) = r["email"].as_str().filter(|e| e.contains('@'))
        {
            c.email = e.to_string();
        }
    }
}

/// Who you blocked (MRIs).
pub async fn blocked(client: &TeamsClient) -> Result<Vec<String>> {
    Ok(blocked_from(
        &mt_get(
            client,
            "userSettings/blocklist?ggEnabled=true",
            "ContactsApp:getBlockList",
        )
        .await?,
    ))
}

/// The block list change Teams free posts.
pub fn block_body(mri: &str, on: bool) -> Value {
    if on {
        json!({ "add": [mri] })
    } else {
        json!({ "remove": [mri] })
    }
}

/// Block or unblock someone.
pub async fn set_blocked(client: &TeamsClient, mri: &str, on: bool) -> Result<()> {
    check_mri(mri)?;
    mt_post(
        client,
        "userSettings/blocklist/manage?ggEnabled=true",
        "ContactsApp:blockUnblockContact",
        &block_body(mri, on),
    )
    .await
    .map(|_| ())
}

/// The buddy group change that removes someone (Teams free names them by
/// their MRI there).
pub fn remove_body(mri: &str) -> Value {
    json!({ "delete": [{ "mri": mri, "displayName": mri }] })
}

/// Take someone out of your contacts and off your block list (Blocked
/// users' Delete).
pub async fn forget(client: &TeamsClient, mri: &str) -> Result<()> {
    check_mri(mri)?;
    mt_post(
        client,
        "contacts/buddylist/TflContacts/managebuddies?ggEnabled=true&skipBuddylistFetch=true",
        "ContactsApp:deleteContact",
        &remove_body(mri),
    )
    .await
    .map(|_| ())
}

/// The People app's Delete: blocked first, then removed (Teams free's
/// order).
pub async fn delete(client: &TeamsClient, mri: &str) -> Result<()> {
    set_blocked(client, mri, true).await?;
    forget(client, mri).await
}

/// Put someone in your contacts (Teams free does it when you start a chat
/// with them or accept their request).
pub async fn add(client: &TeamsClient, mri: &str) -> Result<()> {
    check_mri(mri)?;
    super::chat::add_contact(client, mri).await
}

/// The invite link from a join/template answer.
pub fn invite_link_from(v: &Value) -> Option<String> {
    v["joinUrl"]
        .as_str()
        .filter(|u| u.starts_with("https://teams.live.com/"))
        .map(str::to_string)
}

/// Your Invite to Teams link.
pub async fn invite_link(client: &TeamsClient) -> Result<String> {
    // (Teams free's page asks it, not its worker, with the page's client
    // type and UI language: the template is localized; the worker's
    // headers alone get a 500.)
    let (base, token) = super::tabs::middle_tier(client).await?;
    let locale = crate::i18n::locale().to_ascii_lowercase().replace('_', "-");
    let req = client
        .http()
        .post(format!("{base}/beta/join/template"))
        .header("x-ms-client-type", "web")
        .header("x-ms-client-version", TFL_WEB_VERSION)
        .header(
            "x-client-ui-language",
            if locale.is_empty() {
                "en-us".to_string()
            } else {
                locale
            },
        )
        .header("x-ms-client-caller", "");
    let v: Value = client
        .middle_tier_auth(req, &token)
        .json(&json!({ "messageType": "general" }))
        .send()
        .await?
        .error_for_status()
        .context("Invite link")?
        .json()
        .await
        .context("Invite link reply")?;
    invite_link_from(&v).context("Teams didn't give an invite link")
}

/// The Teams free web client whose requests these are (captured
/// 2026-11-28).
const TFL_WEB_VERSION: &str = "1415/26101516645";

#[cfg(test)]
mod tests {
    use super::*;

    const P2: &str = "8:live:.cid.ca2738c364862c6";

    #[test]
    fn reads_the_contacts_group() {
        let v = json!({ "value": [
            { "id": "TflContacts", "displayName": "TflContacts", "groupType": "TflContacts", "buddies": [
                { "mri": P2, "displayName": "OST Personal 2", "email": "", "phones": [{ "number": "+15550100", "type": "Mobile" }] },
                { "mri": "8:orgid:4287e791-1b98-4963-8b94-281c50472683", "displayName": "OST Test 1", "email": "ost-test1@example.com", "isFederated": true },
                { "mri": P2, "displayName": "OST Personal 2" },
                { "mri": "", "displayName": "nobody" }
            ] },
            { "id": "TflBlocked", "groupType": "TflBlocked", "buddies": [{ "mri": "8:live:.cid.1", "displayName": "X" }] }
        ] });
        let l = contacts_from(&v);
        assert_eq!(l.len(), 2);
        assert_eq!(l[0].name, "OST Personal 2");
        assert_eq!(l[0].phone, "+15550100");
        assert!(!l[0].federated);
        assert!(l[1].federated);
        assert_eq!(l[1].email, "ost-test1@example.com");
    }

    #[test]
    fn reads_a_managebuddies_answer_and_unnamed_buddies() {
        let v = json!({ "id": "TflContacts", "groupType": "TflContacts", "buddies": [{ "mri": P2, "displayName": P2 }] });
        let l = contacts_from(&v);
        assert_eq!(l.len(), 1);
        assert_eq!(l[0].name, "");
        assert!(contacts_from(&json!({ "id": "TflContacts", "buddies": [] })).is_empty());
    }

    #[test]
    fn profiles_fill_names_but_not_private_addresses() {
        let mut l = vec![TflContact {
            mri: P2.into(),
            ..Default::default()
        }];
        apply_profiles(
            &mut l,
            &[
                json!({ "mri": P2, "displayName": "OST Personal 2", "email": "p2@outlook.com", "emailPrivate": true }),
            ],
        );
        assert_eq!(l[0].name, "OST Personal 2");
        assert_eq!(l[0].email, "");
        apply_profiles(
            &mut l,
            &[json!({ "mri": P2, "displayName": "OST Personal 2", "email": "p2@outlook.com" })],
        );
        assert_eq!(l[0].email, "p2@outlook.com");
    }

    #[test]
    fn block_list_and_bodies() {
        assert_eq!(
            blocked_from(&json!({ "value": [P2, "nope"] })),
            vec![P2.to_string()]
        );
        assert_eq!(blocked_from(&json!({ "value": [] })), Vec::<String>::new());
        assert_eq!(block_body(P2, true), json!({ "add": [P2] }));
        assert_eq!(block_body(P2, false), json!({ "remove": [P2] }));
        assert_eq!(
            remove_body(P2),
            json!({ "delete": [{ "mri": P2, "displayName": P2 }] })
        );
        assert!(check_mri("8:live:.cid.1/../x").is_err());
        assert!(check_mri(P2).is_ok());
    }

    #[test]
    fn invite_link() {
        let v = json!({ "joinUrl": "https://teams.live.com/l/invite/FBAACoK98JzIlvGjQ?v=g1", "template": "Let's chat… %%joinurl%%", "statusCode": "OK" });
        assert_eq!(
            invite_link_from(&v).as_deref(),
            Some("https://teams.live.com/l/invite/FBAACoK98JzIlvGjQ?v=g1")
        );
        assert_eq!(
            invite_link_from(&json!({ "joinUrl": "https://evil.example/x" })),
            None
        );
    }
}
