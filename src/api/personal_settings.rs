//! A personal account's own settings in Teams for personal use, as its
//! client reads and writes them (teams.live.com web client 1415/26101516645
//! and Teams desktop 26304, captured 2026-11-28 with OST Personal 1 and 2):
//!
//! - Privacy ▸ Manage how people can find you: your profile
//!   (`GET {mt}/beta/users/me/?skypeTeamsInfo=true&forceRefresh=true&
//!   ephemeralMeProfile=false&ggEnabled=true`: `searchableByProfile` and
//!   `emailsInfo[] {address, searchable, visibility}`); the name's switch
//!   posts `{mt}/beta/users/updateNameAndSkypeAvatar {searchableByProfile}`,
//!   an address's `{mt}/beta/scd/searchability?ggEnabled=true {msaEmails:
//!   [{address, searchable}], msaPhones: []}`;
//! - Privacy ▸ Your profile (Manage profile): an address Shown or Hidden on
//!   your profile card, `PATCH {mt}/beta/users/me {msaEmails: [{address,
//!   visibility: "Public" | "Private"}], msaPhones: []}`;
//! - Privacy ▸ Experiences that analyze your content: `GET/POST {mt}/beta/
//!   users/me/analyzecontentsettings {isAnalyzeContentSettingsEnabled}`;
//! - People ▸ Blocked users: `GET {mt}/beta/userSettings/blocklist?
//!   ggEnabled=true`, unblock `POST …/blocklist/manage?ggEnabled=true
//!   {remove: [mri]}`; People ▸ Sync contacts: `GET {mt}/beta/contacts/
//!   syncSettings`;
//! - Teams Insider: `GET {mt}/beta/users/insiders/status`, Join `POST
//!   {mt}/beta/users/insiders`, Leave `DELETE` (Teams free's
//!   TeamsInsiderMTService).
//!
//! - General ▸ Microsoft cloud storage: Graph `/me/drive` quota.
//!
//! Who can add you to groups and who can call you are user properties
//! (`disableNonContactAddToGroup`, `disableNonContactCall`; see
//! [`super::preferences`]).

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

async fn mt(client: &TeamsClient) -> Result<(String, String)> {
    anyhow::ensure!(client.is_personal(), "Not a personal account");
    super::tabs::middle_tier(client).await
}

async fn send(
    client: &TeamsClient,
    method: reqwest::Method,
    path: &str,
    body: Option<&Value>,
) -> Result<Value> {
    let (base, token) = mt(client).await?;
    let mut req = client.middle_tier_auth(
        client.http().request(method, format!("{base}/{path}")),
        &token,
    );
    if let Some(b) = body {
        req = req.json(b);
    }
    let r = req
        .send()
        .await?
        .error_for_status()
        .context(path.to_string())?;
    let text = r.text().await.unwrap_or_default();
    Ok(serde_json::from_str(&text).unwrap_or(Value::Null))
}

/// Your profile as Teams free's Privacy pages read it.
pub async fn me(client: &TeamsClient) -> Result<Value> {
    let v = send(
        client,
        reqwest::Method::GET,
        "beta/users/me/?skypeTeamsInfo=true&forceRefresh=true&ephemeralMeProfile=false&ggEnabled=true",
        None,
    )
    .await?;
    Ok(me_summary(&v))
}

/// What the pages show from `users/me`: the name's searchability and each
/// address's searchability and visibility.
pub fn me_summary(v: &Value) -> Value {
    let p = v.get("value").unwrap_or(v);
    let emails: Vec<Value> = p
        .get("emailsInfo")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let address = e.get("address")?.as_str()?;
            Some(json!({
                "address": address,
                "searchable": e.get("searchable").and_then(Value::as_bool).unwrap_or(false),
                "visible": e.get("visibility").and_then(Value::as_str) == Some("Public"),
            }))
        })
        .collect();
    json!({
        "displayName": p.get("displayName").cloned().unwrap_or(Value::Null),
        "searchableByProfile": p.get("searchableByProfile").and_then(Value::as_bool).unwrap_or(true),
        "emails": emails,
    })
}

/// The body that makes `address` searchable (or not).
pub fn searchability_body(address: &str, on: bool) -> Value {
    json!({ "msaEmails": [{ "address": address, "searchable": on }], "msaPhones": [] })
}

/// The body that shows (or hides) `address` on your profile card.
pub fn visibility_body(address: &str, shown: bool) -> Value {
    let v = if shown { "Public" } else { "Private" };
    json!({ "msaEmails": [{ "address": address, "visibility": v }], "msaPhones": [] })
}

pub async fn set_name_searchable(client: &TeamsClient, on: bool) -> Result<()> {
    send(
        client,
        reqwest::Method::POST,
        "beta/users/updateNameAndSkypeAvatar",
        Some(&json!({ "searchableByProfile": on })),
    )
    .await
    .map(|_| ())
}

pub async fn set_email_searchable(client: &TeamsClient, address: &str, on: bool) -> Result<()> {
    send(
        client,
        reqwest::Method::POST,
        "beta/scd/searchability?ggEnabled=true",
        Some(&searchability_body(address, on)),
    )
    .await
    .map(|_| ())
}

pub async fn set_email_visible(client: &TeamsClient, address: &str, shown: bool) -> Result<()> {
    send(
        client,
        reqwest::Method::PATCH,
        "beta/users/me",
        Some(&visibility_body(address, shown)),
    )
    .await
    .map(|_| ())
}

/// Experiences that analyze your content (on unless saved off).
pub async fn analyze_content(client: &TeamsClient) -> Result<bool> {
    let v = send(
        client,
        reqwest::Method::GET,
        "beta/users/me/analyzecontentsettings",
        None,
    )
    .await?;
    Ok(v.get("isAnalyzeContentSettingsEnabled")
        .and_then(Value::as_bool)
        .unwrap_or(true))
}

pub async fn set_analyze_content(client: &TeamsClient, on: bool) -> Result<()> {
    send(
        client,
        reqwest::Method::POST,
        "beta/users/me/analyzecontentsettings",
        Some(&json!({ "isAnalyzeContentSettingsEnabled": on })),
    )
    .await
    .map(|_| ())
}

/// The people you blocked (their MRIs and names, when the list has them).
pub async fn blocked(client: &TeamsClient) -> Result<Vec<Value>> {
    let v = send(
        client,
        reqwest::Method::GET,
        "beta/userSettings/blocklist?ggEnabled=true",
        None,
    )
    .await?;
    Ok(blocked_list(&v))
}

pub fn blocked_list(v: &Value) -> Vec<Value> {
    v.get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|b| {
            let mri = b
                .get("mri")
                .or_else(|| b.get("id"))
                .and_then(Value::as_str)
                .or_else(|| b.as_str())?;
            let name = b
                .get("displayName")
                .and_then(Value::as_str)
                .unwrap_or_default();
            Some(json!({ "mri": mri, "name": name }))
        })
        .collect()
}

pub async fn unblock(client: &TeamsClient, mri: &str) -> Result<()> {
    anyhow::ensure!(
        mri.starts_with("8:") && mri.len() < 200,
        "Not a person: {mri}"
    );
    send(
        client,
        reqwest::Method::POST,
        "beta/userSettings/blocklist/manage?ggEnabled=true",
        Some(&json!({ "remove": [mri] })),
    )
    .await
    .map(|_| ())
}

/// The accounts your contacts are synced from (Teams lists the ones it
/// still syncs: Skype and Google sync ended).
pub async fn contact_syncs(client: &TeamsClient) -> Result<Vec<Value>> {
    let v = send(
        client,
        reqwest::Method::GET,
        "beta/contacts/syncSettings",
        None,
    )
    .await?;
    Ok(synced_accounts(&v))
}

pub fn synced_accounts(v: &Value) -> Vec<Value> {
    v.get("value")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|s| s.get("source").and_then(Value::as_str) == Some("Outlook"))
        .filter(|s| s.get("isSyncAllowed").and_then(Value::as_bool) != Some(false))
        .map(|s| {
            json!({
                "source": s.get("source").cloned().unwrap_or(Value::Null),
                "account": s.get("accountId").cloned().unwrap_or(Value::Null),
            })
        })
        .collect()
}

/// Whether you're in the Teams Insider program.
pub async fn insider(client: &TeamsClient) -> Result<bool> {
    let v = send(
        client,
        reqwest::Method::GET,
        "beta/users/insiders/status",
        None,
    )
    .await?;
    Ok(insider_from(&v))
}

pub fn insider_from(v: &Value) -> bool {
    let p = v.get("value").unwrap_or(v);
    p.as_bool()
        .or_else(|| p.get("isInsider").and_then(Value::as_bool))
        .or_else(|| p.get("isTeamsInsider").and_then(Value::as_bool))
        .unwrap_or(false)
}

pub async fn set_insider(client: &TeamsClient, on: bool) -> Result<()> {
    let method = if on {
        reqwest::Method::POST
    } else {
        reqwest::Method::DELETE
    };
    send(client, method, "beta/users/insiders", None)
        .await
        .map(|_| ())
}

/// General ▸ Microsoft cloud storage: your OneDrive's used and total
/// bytes (Graph `/me/drive` quota; 5 GB on a free account).
pub async fn storage(client: &TeamsClient) -> Result<Value> {
    let v: Value = client
        .graph_get("/me/drive?$select=quota")
        .await?
        .json()
        .await?;
    Ok(json!({
        "used": v.pointer("/quota/used").and_then(Value::as_f64).unwrap_or(0.0),
        "total": v.pointer("/quota/total").and_then(Value::as_f64).unwrap_or(0.0),
    }))
}

/// Everything the personal pages read, for Settings (each part left out
/// when its call fails).
pub async fn load_all(client: &TeamsClient) -> Value {
    let (me, analyze, blocked, syncs, insider, storage) = tokio::join!(
        me(client),
        analyze_content(client),
        blocked(client),
        contact_syncs(client),
        insider(client),
        storage(client)
    );
    let mut out = json!({});
    if let Ok(v) = me {
        out["me"] = v;
    }
    if let Ok(v) = analyze {
        out["analyzeContent"] = json!(v);
    }
    if let Ok(v) = blocked {
        out["blocked"] = json!(v);
    }
    if let Ok(v) = syncs {
        out["contactSyncs"] = json!(v);
    }
    if let Ok(v) = insider {
        out["insider"] = json!(v);
    }
    if let Ok(v) = storage {
        out["storage"] = v;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_profile_as_the_pages_show_it() {
        // OST Personal 1's users/me, 2026-11-28 (trimmed).
        let v = json!({ "value": { "searchableByProfile": true, "displayName": "OST Personal 1",
            "emailsInfo": [{ "address": "ost-personal1-5135@outlook.com", "searchable": false, "visibility": "Private" }] } });
        let s = me_summary(&v);
        assert_eq!(s["searchableByProfile"], json!(true));
        assert_eq!(s["emails"][0]["searchable"], json!(false));
        assert_eq!(s["emails"][0]["visible"], json!(false));
    }

    #[test]
    fn bodies_as_teams_free_sends_them() {
        assert_eq!(
            searchability_body("a@outlook.com", true),
            json!({ "msaEmails": [{ "address": "a@outlook.com", "searchable": true }], "msaPhones": [] })
        );
        assert_eq!(
            visibility_body("a@outlook.com", false)["msaEmails"][0]["visibility"],
            json!("Private")
        );
    }

    #[test]
    fn lists_blocked_people_and_synced_accounts() {
        assert!(blocked_list(&json!({ "value": [] })).is_empty());
        let b = blocked_list(
            &json!({ "value": [{ "mri": "8:live:.cid.1", "displayName": "X" }, "8:live:.cid.2"] }),
        );
        assert_eq!(b.len(), 2);
        assert_eq!(b[1]["mri"], json!("8:live:.cid.2"));
        // OST Personal 1's sync settings: the Skype one is no longer shown.
        let s = synced_accounts(&json!({ "value": [
            { "source": "Skype", "accountId": "p@outlook.com" },
            { "source": "Outlook", "accountId": "p@outlook.com", "isSyncAllowed": true }] }));
        assert_eq!(
            s,
            vec![json!({ "source": "Outlook", "account": "p@outlook.com" })]
        );
        assert!(insider_from(&json!({ "value": true })));
        assert!(!insider_from(&json!({})));
    }
}
