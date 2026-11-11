//! A meeting's options (Teams' Meeting options dialog, captured from Teams
//! desktop on 2026-11-10): `GET {mt}/beta/meetings/v1/options/{tenant}/
//! {organizer}/{thread}/0/0?monarch=true` lists every option (`name`,
//! `type`, `values`, `currentValue`, `category`, `isDisabled`); Apply POSTs
//! all of them back to the same URL, each in its type's shape, and the
//! reply carries them again with `success` on each.
//!
//! The thread goes in the path with its `:` as `_` (`19_meeting_…`), as
//! the dialog sends it, then the meeting's message id twice: `0/0` for a
//! scheduled meeting, the meeting post's id for a channel meeting
//! (`19_…@thread.tacv2/1794372973956/1794372973956`).

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// The options URL's path under the middle tier.
pub fn options_path(tenant: &str, organizer: &str, thread: &str, message: &str) -> String {
    format!(
        "/beta/meetings/v1/options/{tenant}/{organizer}/{}/{message}/{message}?monarch=true",
        thread.replace(':', "_")
    )
}

fn check_ids(tenant: &str, organizer: &str, thread: &str, message: &str) -> Result<()> {
    let guid = |s: &str| uuid::Uuid::parse_str(s).is_ok();
    let thread_ok = thread.starts_with("19:")
        && (thread.ends_with("@thread.v2") || thread.ends_with("@thread.tacv2"))
        && thread[3..].chars().all(|c| c.is_ascii_alphanumeric() || "_-=@.".contains(c));
    let message_ok = !message.is_empty() && message.bytes().all(|b| b.is_ascii_digit());
    if !guid(tenant) || !guid(organizer) || !thread_ok || !message_ok {
        bail!("Not a meeting");
    }
    Ok(())
}

/// The meeting's options and its invitees (whom the people pickers
/// offer: `{mri, upn, objectId, tenantId, meetingRole, ...}`; Teams'
/// dialog resolves their names itself).
/// `translations` holds the dialog's strings by key
/// (`meetingsOptions_<option>[_<value>]_Info` and the like).
#[derive(Debug, Clone, Default)]
pub struct MeetingOptions {
    pub options: Vec<Value>,
    pub invitees: Vec<Value>,
    pub translations: Value,
}

impl MeetingOptions {
    fn from_reply(v: &Value) -> Self {
        let list = |k: &str| v[k].as_array().cloned().unwrap_or_default();
        MeetingOptions { options: list("options"), invitees: list("invitees"), translations: v["translations"].clone() }
    }
}

/// The meeting's options, as Teams lists them.
pub async fn get(client: &TeamsClient, tenant: &str, organizer: &str, thread: &str, message: &str) -> Result<MeetingOptions> {
    check_ids(tenant, organizer, thread, message)?;
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .get(format!("{base}{}", options_path(tenant, organizer, thread, message)))
        .bearer_auth(&token)
        .send()
        .await?
        .error_for_status()
        .context("Meeting options")?
        .json()
        .await?;
    Ok(MeetingOptions::from_reply(&v))
}

/// The meeting's lobby chat (Teams' organizers messaging people in the
/// lobby; captured from Teams desktop 2026-11-11): `POST {mt}/beta/
/// meetings/lobby/getOrCreateLobbyChatThreadId` with `{messageId,
/// organizerId, tenantId, threadId}` answers `{lobbyThreadId}`, a
/// LobbyChat thread the people waiting join as masked, read-only members.
pub async fn lobby_chat_thread(client: &TeamsClient, tenant: &str, organizer: &str, thread: &str, message: &str) -> Result<String> {
    check_ids(tenant, organizer, thread, message)?;
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .post(format!("{base}/beta/meetings/lobby/getOrCreateLobbyChatThreadId"))
        .bearer_auth(&token)
        .json(&json!({ "messageId": message, "organizerId": organizer, "tenantId": tenant, "threadId": thread }))
        .send()
        .await?
        .error_for_status()
        .context("Lobby chat")?
        .json()
        .await?;
    let id = v["lobbyThreadId"].as_str().unwrap_or_default();
    if !id.starts_with("19:") || !id.ends_with("@thread.v2") {
        bail!("No lobby chat");
    }
    Ok(id.to_string())
}

/// A picked person as Teams' pickers send them: `upn`, `mri`, `objectId`,
/// `userType` ("Member") and the `tenantId` when known.
pub fn picked_person(p: &Value) -> Value {
    let mut out = json!({
        "upn": p["upn"], "mri": p["mri"], "objectId": p["objectId"],
        "userType": p.get("userType").filter(|t| t.is_string()).cloned().unwrap_or(json!("Member")),
    });
    if let Some(t) = p.get("tenantId").filter(|t| t.is_string()) {
        out["tenantId"] = t.clone();
    }
    out
}

/// One option as Apply sends it back: its name and type, the value (people
/// pickers send `selectedPeople`), `isRecommended: null`, plus the fields
/// Teams adds for its type.
pub fn post_option(o: &Value, value: Option<&Value>) -> Value {
    let name = o["name"].clone();
    let ty = o["type"].as_str().unwrap_or_default();
    let current = value.cloned().unwrap_or_else(|| o["currentValue"].clone());
    match ty {
        "PeopleSelection" | "PresenterSelection" => json!({
            "name": name, "type": ty,
            "selectedPeople": value
                .or_else(|| o.get("selectedPeople"))
                .and_then(|v| v.as_array())
                .map(|people| people.iter().map(picked_person).collect::<Vec<_>>())
                .unwrap_or_default(),
            "isValid": true, "isRecommended": null,
        }),
        "Interpretation" => json!({
            "name": name, "type": ty, "currentValue": current,
            "isValid": true, "category": o["category"], "isRecommended": null,
        }),
        "ExternalFeed" => json!({
            "name": name, "type": ty, "currentValue": current,
            "refreshKey": false,
            "isBackupEnabled": o.get("isBackupEnabled").cloned().unwrap_or(json!(false)),
            "sslEnabled": o.get("sslEnabled").cloned().unwrap_or(json!(false)),
            "isRecommended": null,
        }),
        _ => json!({ "name": name, "type": ty, "currentValue": current, "isRecommended": null }),
    }
}

/// Apply's body: every option, with `changes` (name, new value) applied.
pub fn post_body(options: &[Value], changes: &[(&str, Value)]) -> Value {
    json!({
        "options": options
            .iter()
            .map(|o| {
                let change = changes.iter().find(|(n, _)| o["name"].as_str() == Some(*n)).map(|(_, v)| v);
                post_option(o, change)
            })
            .collect::<Vec<_>>()
    })
}

/// Save options (Teams' Apply): re-reads them, applies `changes` and posts
/// the whole set. Returns the options as saved. A people picker's value
/// is its list of people (`{mri, upn, objectId, tenantId}`).
pub async fn set(
    client: &TeamsClient,
    tenant: &str,
    organizer: &str,
    thread: &str,
    message: &str,
    changes: &[(&str, Value)],
) -> Result<MeetingOptions> {
    let before = get(client, tenant, organizer, thread, message).await?;
    let options = before.options;
    for (name, _) in changes {
        if !options.iter().any(|o| o["name"].as_str() == Some(*name)) {
            bail!("This meeting has no option {name}");
        }
    }
    let (base, token) = super::tabs::middle_tier(client).await?;
    let v: Value = client
        .http()
        .post(format!("{base}{}", options_path(tenant, organizer, thread, message)))
        .bearer_auth(&token)
        .json(&post_body(&options, changes))
        .send()
        .await?
        .error_for_status()
        .context("Meeting options")?
        .json()
        .await?;
    if v["success"] != json!(true) {
        bail!("Meeting options weren't saved");
    }
    // The reply lists the options; the invitees and strings only when it
    // has them.
    let mut saved = MeetingOptions::from_reply(&v);
    if v.get("invitees").is_none() {
        saved.invitees = before.invitees;
    }
    if !saved.translations.is_object() {
        saved.translations = before.translations;
    }
    Ok(saved)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_uses_underscored_thread() {
        assert_eq!(
            options_path("t", "o", "19:meeting_YTQy@thread.v2", "0"),
            "/beta/meetings/v1/options/t/o/19_meeting_YTQy@thread.v2/0/0?monarch=true"
        );
        assert_eq!(
            options_path("t", "o", "19:ekCP@thread.tacv2", "1794372973956"),
            "/beta/meetings/v1/options/t/o/19_ekCP@thread.tacv2/1794372973956/1794372973956?monarch=true"
        );
    }

    #[test]
    fn apply_body_as_teams() {
        // Shapes from Teams' own Apply (winpc, 2026-11-10).
        let got = vec![
            json!({"values":["Everyone","OrganizerOnly"],"currentValue":"Everyone","name":"AutoAdmittedUsers","type":"List","category":"MEETING_ACCESS","isDisabled":false}),
            json!({"values":[true,false],"currentValue":false,"name":"AllowPstnUsersToBypassLobby","type":"Boolean","category":"MEETING_ACCESS","isDisabled":false}),
            json!({"maxPeopleSelectionAllowed":10,"name":"CoOrganizers","type":"PeopleSelection","category":"ROLES","isDisabled":false}),
            json!({"values":[true,false],"currentValue":false,"name":"Interpretation","type":"Interpretation","category":"ROLES","isDisabled":false}),
            json!({"values":[true,false],"currentValue":false,"showKeyField":false,"isSslSupported":false,"isBackupSupported":false,"name":"CARTExternalFeed","type":"ExternalFeed","category":"ACCESSIBILITY","isDisabled":false}),
        ];
        let body = post_body(&got, &[("AutoAdmittedUsers", json!("OrganizerOnly"))]);
        assert_eq!(
            body,
            json!({"options":[
                {"name":"AutoAdmittedUsers","type":"List","currentValue":"OrganizerOnly","isRecommended":null},
                {"name":"AllowPstnUsersToBypassLobby","type":"Boolean","currentValue":false,"isRecommended":null},
                {"name":"CoOrganizers","type":"PeopleSelection","selectedPeople":[],"isValid":true,"isRecommended":null},
                {"name":"Interpretation","type":"Interpretation","currentValue":false,"isValid":true,"category":"ROLES","isRecommended":null},
                {"name":"CARTExternalFeed","type":"ExternalFeed","currentValue":false,"refreshKey":false,"isBackupEnabled":false,"sslEnabled":false,"isRecommended":null}
            ]})
        );
    }

    #[test]
    fn picked_people_as_teams() {
        // The GET lists picked people without userType; Apply sends them
        // as Teams' picker does.
        let got = vec![json!({"name":"CoOrganizers","type":"PeopleSelection","selectedPeople":[{"mri":"8:orgid:b","objectId":"b","tenantId":"t","upn":"b@x"}]})];
        assert_eq!(
            post_body(&got, &[])["options"][0]["selectedPeople"],
            json!([{"upn":"b@x","mri":"8:orgid:b","objectId":"b","userType":"Member","tenantId":"t"}])
        );
        let picked = json!([{"mri":"8:orgid:c","objectId":"c","upn":"c@x","name":"C"}]);
        assert_eq!(
            post_body(&got, &[("CoOrganizers", picked)])["options"][0]["selectedPeople"],
            json!([{"upn":"c@x","mri":"8:orgid:c","objectId":"c","userType":"Member"}])
        );
    }

    #[test]
    fn rejects_bad_ids() {
        assert!(check_ids("x", "y", "19:meeting_a@thread.v2", "0").is_err());
        let g = "2716d134-5614-4856-a48d-2002edd9a570";
        assert!(check_ids(g, g, "19:meeting_a@thread.v2", "0").is_ok());
        assert!(check_ids(g, g, "19:a@thread.tacv2", "1794372973956").is_ok());
        assert!(check_ids(g, g, "19:meeting_a/../x@thread.v2", "0").is_err());
        assert!(check_ids(g, g, "19:meeting_a@thread.v2", "0/x").is_err());
    }
}
