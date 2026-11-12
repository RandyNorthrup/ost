//! OneDrive's share dialog, as Teams opens it (docs/spec/onedrive-share.md):
//! SharePoint's sharing REST methods on a file's list item, with a token
//! for the file's SharePoint host.

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

/// A file as SharePoint's sharing methods address it: its site, list and
/// item (the search result's SpWebUrl / SiteName, ListId and UniqueId).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(default)]
pub struct ItemRef {
    pub site: String,
    pub list: String,
    pub item: String,
}

impl ItemRef {
    fn method(&self, name: &str) -> String {
        let quote = |s: &str| url::form_urlencoded::byte_serialize(format!("'{}'", s.trim_matches(|c| c == '{' || c == '}')).as_bytes()).collect::<String>();
        format!(
            "{}/_api/web/lists/getbyid(@a1)/GetItemByUniqueId(@a2)/{name}?@a1={}&@a2={}",
            self.site.trim_end_matches('/'),
            quote(&self.list),
            quote(&self.item)
        )
    }
}

/// A person with access: their name, address, sign-in name and role
/// (3 owner, 2 can edit, 1 can view), and how (direct or through a link).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Person {
    pub name: String,
    pub email: String,
    pub login: String,
    pub role: i64,
    pub direct: bool,
    /// Their directory id, for their picture (filled by `with_object_ids`).
    pub oid: String,
}

/// A sharing link.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Link {
    pub url: String,
    pub share_id: String,
    pub kind: i64,
    /// 0 anyone, 1 the organisation, 2 specific people.
    pub scope: i64,
    pub edit: bool,
    pub expiration: String,
    pub requires_password: bool,
    pub members: Vec<Person>,
}

/// What the dialog shows for a file.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct Info {
    pub name: String,
    pub tenant: String,
    pub direct_url: String,
    /// The default link: scope (0 anyone, 1 organisation, 2 people), edit,
    /// and whether it is "Only people with existing access".
    pub default_scope: i64,
    pub default_edit: bool,
    pub default_existing: bool,
    /// Owner first, then people through links, then direct access, each
    /// once with their highest role.
    pub people: Vec<Person>,
    pub links: Vec<Link>,
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

fn results(v: &Value) -> &[Value] {
    v.get("results").and_then(Value::as_array).or_else(|| v.as_array()).map(Vec::as_slice).unwrap_or_default()
}

fn person(p: &Value, role: i64, direct: bool) -> Person {
    Person {
        name: s(&p["name"]),
        email: s(&p["email"]),
        login: s(&p["loginName"]),
        role,
        direct,
        oid: String::new(),
    }
}

/// A link's scope from its kind (SharePoint's SharingLinkKind).
fn scope_of(kind: i64) -> i64 {
    match kind {
        4 | 5 => 0,
        2 | 3 => 1,
        _ => 2,
    }
}

/// GetSharingInformation's reply, as the dialog reads it.
pub fn parse_info(reply: &Value) -> Info {
    let d = reply.get("d").unwrap_or(reply);
    let pi = &d["permissionsInformation"];
    let links: Vec<Link> = results(&pi["links"])
        .iter()
        .filter(|l| !s(&l["linkDetails"]["Url"]).is_empty())
        .map(|l| {
            let ld = &l["linkDetails"];
            let kind = ld["LinkKind"].as_i64().unwrap_or_default();
            let edit = ld["IsEditLink"].as_bool().unwrap_or(matches!(kind, 3 | 5));
            Link {
                url: s(&ld["Url"]),
                share_id: s(&ld["ShareId"]),
                kind,
                scope: scope_of(kind),
                edit,
                expiration: s(&ld["Expiration"]),
                requires_password: ld["RequiresPassword"].as_bool().unwrap_or_default(),
                members: results(&l["linkMembers"]).iter().map(|m| person(m, if edit { 2 } else { 1 }, false)).collect(),
            }
        })
        .collect();
    let mut people: Vec<Person> = Vec::new();
    let mut add = |p: Person| {
        if p.login.is_empty() {
            return;
        }
        match people.iter_mut().find(|q| q.login.eq_ignore_ascii_case(&p.login)) {
            Some(q) => {
                q.role = q.role.max(p.role);
                q.direct |= p.direct;
            }
            None => people.push(p),
        }
    };
    for a in results(&pi["siteAdmins"]) {
        add(person(&a["principal"], 3, true));
    }
    for l in &links {
        for m in &l.members {
            add(m.clone());
        }
    }
    for p in results(&pi["principals"]) {
        add(person(&p["principal"], p["role"].as_i64().unwrap_or(1), true));
    }
    Info {
        name: s(&d["displayName"]),
        tenant: s(&d["tenantDisplayName"]),
        direct_url: s(&d["directUrl"]),
        default_scope: d["defaultShareLinkScope"].as_i64().unwrap_or(1),
        default_edit: d["defaultShareLinkPermission"].as_i64() == Some(2),
        default_existing: d["defaultShareLinkToExistingAccess"].as_bool().unwrap_or_default(),
        people,
        links,
    }
}

/// POST a SharePoint REST method with a token for the site's host.
async fn post(url: &str, body: &Value) -> Result<Value> {
    let host = url.split('/').take(3).collect::<Vec<_>>().join("/");
    if !host.starts_with("https://") {
        bail!("Not a SharePoint address: {url}");
    }
    let token = crate::auth::oauth::access_token_for(&format!("{host}/.default")).await?;
    let resp = reqwest::Client::new()
        .post(url)
        .bearer_auth(token)
        .header("accept", "application/json;odata=verbose")
        .header("content-type", "application/json;odata=verbose")
        .body(body.to_string())
        .send()
        .await
        .with_context(|| format!("SharePoint {url}"))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        let msg = serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|v| v["error"]["message"]["value"].as_str().map(str::to_string))
            .unwrap_or_else(|| text.chars().take(200).collect());
        bail!("SharePoint {status}: {msg}");
    }
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

/// The file's sharing: who has access, its links and the default link.
pub async fn info(item: &ItemRef) -> Result<Info> {
    let url = item.method("GetSharingInformation") + "&$Expand=pickerSettings,permissionsInformation,sharingLinkTemplates";
    let reply = post(&url, &json!({"request": {"maxPrincipalsToReturn": 100, "maxLinkMembersToReturn": 100}})).await?;
    Ok(parse_info(&reply))
}

/// Fill in people's directory ids (Graph, by address) so their pictures
/// show; those Graph can't find keep initials.
pub async fn with_object_ids(client: &super::client::TeamsClient, info: &mut Info) {
    use futures::StreamExt;
    let mut emails: Vec<String> = info.people.iter().chain(info.links.iter().flat_map(|l| l.members.iter())).map(|p| p.email.to_ascii_lowercase()).filter(|e| !e.is_empty()).collect();
    emails.sort();
    emails.dedup();
    let found: std::collections::HashMap<String, String> = futures::stream::iter(emails)
        .map(|e| async move {
            let id = match client.graph_get_opt(&format!("/users/{}?$select=id", url::form_urlencoded::byte_serialize(e.as_bytes()).collect::<String>())).await {
                Ok(Some(r)) => r.json::<Value>().await.ok().map(|v| s(&v["id"])).unwrap_or_default(),
                _ => String::new(),
            };
            (e, id)
        })
        .buffer_unordered(6)
        .collect()
        .await;
    let fill = |p: &mut Person| p.oid = found.get(&p.email.to_ascii_lowercase()).cloned().unwrap_or_default();
    info.people.iter_mut().for_each(fill);
    info.links.iter_mut().flat_map(|l| l.members.iter_mut()).for_each(fill);
}

/// The people picker's suggestions for `query` (SharePoint's entities,
/// kept whole: Send passes them back).
pub async fn search_people(site: &str, query: &str) -> Result<Vec<Value>> {
    let url = format!("{}/_api/SP.UI.ApplicationPages.ClientPeoplePickerWebServiceInterface.ClientPeoplePickerSearchUser", site.trim_end_matches('/'));
    let reply = post(
        &url,
        &json!({"queryParams": {
            "QueryString": query, "MaximumEntitySuggestions": 30, "AllowEmailAddresses": true,
            "PrincipalType": 13, "PrincipalSource": 15, "UseSubstrateSearch": true,
            "QuerySettings": {"__metadata": {"type": "SP.UI.ApplicationPages.PeoplePickerQuerySettings"}, "ExcludeAllUsersOnTenantClaim": false, "IsSharing": true}
        }}),
    )
    .await?;
    Ok(parse_picker(&reply))
}

/// ClientPeoplePickerSearchUser's reply: a JSON string of entities.
pub fn parse_picker(reply: &Value) -> Vec<Value> {
    let text = reply["d"]["ClientPeoplePickerSearchUser"].as_str().unwrap_or("[]");
    serde_json::from_str::<Vec<Value>>(text).unwrap_or_default()
}

/// Send: give the picked people access (edit or view) and mail them the
/// message.
pub async fn send(item: &ItemRef, people: &[Value], edit: bool, message: &str) -> Result<()> {
    let reply = post(&item.method("ShareObject"), &share_object_body(people, edit, message)).await?;
    let d = reply.get("d").unwrap_or(&reply);
    if let Some(err) = d["ErrorMessage"].as_str().filter(|e| !e.is_empty()) {
        bail!("{err}");
    }
    Ok(())
}

pub fn share_object_body(people: &[Value], edit: bool, message: &str) -> Value {
    json!({
        "peoplePickerInput": Value::Array(people.to_vec()).to_string(),
        "roleValue": if edit { "role:1073741827" } else { "role:1073741826" },
        "sendEmail": true,
        "emailBody": message,
        "includeAnonymousLinkInEmail": false,
        "propagateAcl": true,
        "useSimplifiedRoles": true,
    })
}

/// A link's kind for a scope and role.
pub fn link_kind(scope: i64, edit: bool) -> i64 {
    match (scope, edit) {
        (0, true) => 5,
        (0, false) => 4,
        (1, true) => 3,
        (1, false) => 2,
        _ => 6,
    }
}

/// Copy link: make (or reuse) the link for a scope and role; its address.
pub async fn create_link(item: &ItemRef, scope: i64, edit: bool, expiration: &str, password: &str) -> Result<String> {
    let reply = post(&item.method("ShareLink"), &share_link_body(scope, edit, expiration, password)).await?;
    let url = s(&reply["d"]["ShareLink"]["sharingLinkInfo"]["Url"]);
    if url.is_empty() {
        bail!("No link came back");
    }
    Ok(url)
}

pub fn share_link_body(scope: i64, edit: bool, expiration: &str, password: &str) -> Value {
    json!({"request": {"createLink": true, "settings": {
        "allowAnonymousAccess": scope == 0,
        "linkKind": link_kind(scope, edit),
        "expiration": if expiration.is_empty() { Value::Null } else { Value::from(expiration) },
        "role": if edit { 2 } else { 1 },
        "restrictShareMembership": false,
        "updatePassword": !password.is_empty(),
        "password": password,
        "scope": scope,
        "nav": "",
    }}})
}

/// A person's direct access: 2 edit, 1 view, 0 none.
pub async fn set_role(item: &ItemRef, login: &str, role: i64) -> Result<()> {
    post(
        &item.method("UpdateDocumentSharingInfo"),
        &json!({
            "userRoleAssignments": [{"UserId": login, "Role": role}],
            "validateExistingPermissions": false, "additiveMode": false,
            "sendServerManagedNotification": false, "customMessage": null,
            "includeAnonymousLinksInNotification": false, "propagateAcl": true,
        }),
    )
    .await?;
    Ok(())
}

/// Delete a link.
pub async fn delete_link(item: &ItemRef, kind: i64, share_id: &str) -> Result<()> {
    post(&item.method("UnshareLink"), &json!({"linkKind": kind, "shareId": share_id})).await?;
    Ok(())
}

/// Stop sharing: only the owners keep access (SharePoint's UnshareObject,
/// with the address of the file's library).
pub async fn stop_sharing(item: &ItemRef) -> Result<()> {
    let root = get(&format!(
        "{}/_api/web/lists(guid'{}')/RootFolder?$select=ServerRelativeUrl",
        item.site.trim_end_matches('/'),
        item.list.trim_matches(|c| c == '{' || c == '}')
    ))
    .await?;
    let rel = s(&root["d"]["ServerRelativeUrl"]);
    let host = item.site.split('/').take(3).collect::<Vec<_>>().join("/");
    post(&item.method("UnshareObject"), &json!({ "url": format!("{host}{rel}") })).await?;
    Ok(())
}

/// GET a SharePoint REST resource with a token for the site's host.
async fn get(url: &str) -> Result<Value> {
    let host = url.split('/').take(3).collect::<Vec<_>>().join("/");
    let token = crate::auth::oauth::access_token_for(&format!("{host}/.default")).await?;
    let resp = reqwest::Client::new()
        .get(url)
        .bearer_auth(token)
        .header("accept", "application/json;odata=verbose")
        .send()
        .await
        .with_context(|| format!("SharePoint {url}"))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("SharePoint {status}: {}", text.chars().take(200).collect::<String>());
    }
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn methods_address_the_item() {
        let item = ItemRef {
            site: "https://x-my.sharepoint.com/personal/a_b_com".into(),
            list: "0e0a18f3-101b-4090-a53e-1e24c4d98efd".into(),
            item: "{f8d1feba-9776-4860-85bf-de05ef77a4ad}".into(),
        };
        assert_eq!(
            item.method("ShareLink"),
            "https://x-my.sharepoint.com/personal/a_b_com/_api/web/lists/getbyid(@a1)/GetItemByUniqueId(@a2)/ShareLink?@a1=%270e0a18f3-101b-4090-a53e-1e24c4d98efd%27&@a2=%27f8d1feba-9776-4860-85bf-de05ef77a4ad%27"
        );
    }

    #[test]
    fn info_reads_people_and_links() {
        // ost-attachment-test.txt with its Anyone link (2026-11-11), plus a
        // direct viewer.
        let reply = json!({"d": {
            "displayName": "ost-attachment-test.txt", "tenantDisplayName": "Secure Coast Network Solutions",
            "directUrl": "https://x/:t:/r/f.txt", "defaultShareLinkScope": 0, "defaultShareLinkPermission": 2,
            "defaultShareLinkToExistingAccess": false,
            "permissionsInformation": {
                "siteAdmins": {"results": [{"principal": {"name": "OST Test 1", "email": "ost-test1@x.com", "loginName": "i:0#.f|membership|ost-test1@x.com"}, "role": 3}]},
                "principals": {"results": [{"principal": {"name": "OST Test 2", "email": "ost-test2@x.com", "loginName": "i:0#.f|membership|ost-test2@x.com"}, "role": 1}]},
                "links": {"results": [
                    {"linkDetails": {"Url": null, "LinkKind": 2, "ShareId": "00000000-0000-0000-0000-000000000000"}, "linkMembers": {"results": []}},
                    {"linkDetails": {"Url": "https://x/:t:/p/a/IQC", "LinkKind": 5, "IsEditLink": true, "ShareId": "1998683b", "Expiration": "", "RequiresPassword": false},
                     "linkMembers": {"results": [{"name": "Randy Northrup", "email": "Randy@x.com", "loginName": "i:0#.f|membership|randy@x.com"}]}}
                ]}
            }
        }});
        let i = parse_info(&reply);
        assert_eq!((i.default_scope, i.default_edit, i.default_existing), (0, true, false));
        assert_eq!(i.links.len(), 1);
        assert_eq!((i.links[0].scope, i.links[0].edit, i.links[0].share_id.as_str()), (0, true, "1998683b"));
        let roles: Vec<(&str, i64, bool)> = i.people.iter().map(|p| (p.name.as_str(), p.role, p.direct)).collect();
        assert_eq!(roles, [("OST Test 1", 3, true), ("Randy Northrup", 2, false), ("OST Test 2", 1, true)]);
    }

    #[test]
    fn bodies_are_teams_bodies() {
        // As OneDrive's dialog sent them in Teams (2026-11-11).
        let link = share_link_body(1, false, "", "");
        assert_eq!(
            link,
            json!({"request": {"createLink": true, "settings": {"allowAnonymousAccess": false, "linkKind": 2, "expiration": null, "role": 1, "restrictShareMembership": false, "updatePassword": false, "password": "", "scope": 1, "nav": ""}}})
        );
        let who = json!({"Key": "i:0#.f|membership|ost-test2@x.com", "DisplayText": "OST Test 2", "IsResolved": true});
        let send = share_object_body(std::slice::from_ref(&who), false, "OST test 105");
        assert_eq!(send["roleValue"], "role:1073741826");
        assert_eq!(send["peoplePickerInput"], format!("[{who}]"));
        let picked = parse_picker(&json!({"d": {"ClientPeoplePickerSearchUser": format!("[{who}]")}}));
        assert_eq!(picked, [who]);
    }
}
