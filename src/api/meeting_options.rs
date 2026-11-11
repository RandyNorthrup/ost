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

/// The meeting's options, as Teams lists them.
pub async fn get(client: &TeamsClient, tenant: &str, organizer: &str, thread: &str, message: &str) -> Result<Vec<Value>> {
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
    Ok(v["options"].as_array().cloned().unwrap_or_default())
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
            "selectedPeople": value.cloned().or_else(|| o.get("selectedPeople").cloned()).unwrap_or_else(|| json!([])),
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
/// the whole set. Returns the options as saved.
pub async fn set(
    client: &TeamsClient,
    tenant: &str,
    organizer: &str,
    thread: &str,
    message: &str,
    changes: &[(&str, Value)],
) -> Result<Vec<Value>> {
    let options = get(client, tenant, organizer, thread, message).await?;
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
    Ok(v["options"].as_array().cloned().unwrap_or_default())
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
    fn rejects_bad_ids() {
        assert!(check_ids("x", "y", "19:meeting_a@thread.v2", "0").is_err());
        let g = "2716d134-5614-4856-a48d-2002edd9a570";
        assert!(check_ids(g, g, "19:meeting_a@thread.v2", "0").is_ok());
        assert!(check_ids(g, g, "19:a@thread.tacv2", "1794372973956").is_ok());
        assert!(check_ids(g, g, "19:meeting_a/../x@thread.v2", "0").is_err());
        assert!(check_ids(g, g, "19:meeting_a@thread.v2", "0/x").is_err());
    }
}
