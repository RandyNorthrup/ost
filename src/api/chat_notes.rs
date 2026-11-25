//! A chat's Notes tab (Teams' "FluidThread", docs/spec/chat-tabs.md).
//!
//! The notes are one Loop page per chat, `loop_loopThread.loop`, which the
//! chat service keeps in a SharePoint Embedded container (Loop's) in a
//! folder named after the thread. The thread lists it under
//! `fileReferences` (`GET /v1/threads/{id}`); opening the tab when there is
//! none asks the chat service to make it (`POST /v1/threads/{id}/files`,
//! `{"type":"loop","subType":"loopThread"}`), which also posts the chat's
//! "Notes have been created in this chat." row (ThreadActivity/FileAdd).

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::client::TeamsClient;

/// A chat's notes file, from the thread's `fileReferences`.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct NotesFile {
    pub id: String,
    /// The `.loop` file (its address in the container, with Loop's `nav`).
    pub uri: String,
    /// INPROGRESS, FILECREATEDWITHINITIATORPERMISSION, COMPLETED, FAILED or
    /// DELETED (upper case, as Teams compares them).
    pub status: String,
    /// The creator's MRI.
    pub creator: String,
    pub drive_id: String,
    pub item_id: String,
}

/// What the tab shows (Teams' FluidThread container and its pages).
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum NotesState {
    /// The page, at `url`.
    Ready { url: String, file: NotesFile },
    /// "Give us a moment while we get things ready for you..." (the file
    /// is being made, or its creator's permission hasn't reached you yet).
    Preparing,
    /// "Your notes have been deleted." with Create new.
    Deleted,
    /// "Your notes are temporarily not available." with Retry.
    Failed,
}

/// The notes file Teams opens among a thread's `fileReferences`: the Loop
/// thread references that aren't deleted, the first by id (Teams' `FF`).
/// `Err(())` when there are only deleted ones.
#[allow(
    clippy::result_unit_err,
    reason = "Err(()) only means every reference is deleted; there is nothing more to say"
)]
pub fn notes_file(thread: &Value) -> Result<Option<NotesFile>, ()> {
    let Some(refs) = thread.get("fileReferences").and_then(Value::as_object) else {
        return Ok(None);
    };
    let s = |v: &Value, k: &str| {
        v.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let mut files: Vec<NotesFile> = refs
        .values()
        .filter(|r| {
            s(r, "type").eq_ignore_ascii_case("loop")
                && s(r, "subType").eq_ignore_ascii_case("loopThread")
        })
        .map(|r| NotesFile {
            id: s(r, "id"),
            uri: s(r, "uri"),
            status: s(r, "provisioningStatus").to_uppercase(),
            creator: s(r, "creator"),
            drive_id: s(r, "driveId"),
            item_id: s(r, "fileReferenceId"),
        })
        .collect();
    if files.is_empty() {
        return Ok(None);
    }
    files.retain(|f| f.status != "DELETED");
    files.sort_by(|a, b| a.id.cmp(&b.id));
    files.into_iter().next().map(Some).ok_or(())
}

/// What to show for a notes file, for the user `me` (an MRI): Teams keeps
/// the page from everyone but its creator until the file has their
/// permission (FILECREATEDWITHINITIATORPERMISSION), and shows it once the
/// file has an address.
pub fn state_of(file: &NotesFile, me: &str) -> NotesState {
    match file.status.as_str() {
        "FAILED" => NotesState::Failed,
        "DELETED" => NotesState::Deleted,
        "FILECREATEDWITHINITIATORPERMISSION" if !file.creator.eq_ignore_ascii_case(me) => {
            NotesState::Preparing
        }
        _ if file.uri.is_empty() => NotesState::Preparing,
        _ => NotesState::Ready {
            url: file.uri.clone(),
            file: file.clone(),
        },
    }
}

/// Teams' request to make a chat's notes (worker `thread_file_reference`):
/// the address and body. `recreate` is Create new after the notes were
/// deleted (`forceCreateFile`, with Teams' reason).
pub fn create_request(chat_service: &str, thread: &str, recreate: bool) -> (String, &'static str) {
    let mut url = format!(
        "{chat_service}/v1/threads/{}/files",
        super::tabs::encode_uri_component(thread)
    );
    if recreate {
        url.push_str("?forceCreateFile=true&forceCreateReason=ClientFileNotFound");
    }
    (url, r#"{"type":"loop","subType":"loopThread"}"#)
}

/// The thread, as the chat service gives it (its `fileReferences` too).
async fn thread(client: &TeamsClient, thread: &str) -> Result<Value> {
    let url = format!(
        "{}/v1/threads/{}?view=msnp24Equivalent",
        client.chat_service_url(),
        thread
    );
    client
        .chat_get(&url)
        .await?
        .json()
        .await
        .context("Thread reply")
}

/// The chat's notes as the tab shows them; makes them first when the chat
/// has none (or, with `recreate`, again after they were deleted), as
/// opening Teams' tab does.
pub async fn open(client: &TeamsClient, thread_id: &str, recreate: bool) -> Result<NotesState> {
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    if !recreate {
        match notes_file(&thread(client, thread_id).await?) {
            Ok(Some(f)) => return Ok(state_of(&f, &me)),
            Err(()) => return Ok(NotesState::Deleted),
            Ok(None) => {}
        }
    }
    let (url, body) = create_request(&client.chat_service_url(), thread_id, recreate);
    let reply: Value = client
        .chat_post_text(&url, body)
        .await?
        .json()
        .await
        .unwrap_or(Value::Null);
    // The reply is the new file reference; otherwise read it back.
    let wrapped = json!({ "fileReferences": { "new": reply } });
    match notes_file(&wrapped) {
        Ok(Some(f)) => Ok(state_of(&f, &me)),
        _ => match notes_file(&thread(client, thread_id).await?) {
            Ok(Some(f)) => Ok(state_of(&f, &me)),
            Err(()) => Ok(NotesState::Deleted),
            Ok(None) => Ok(NotesState::Preparing),
        },
    }
}

/// The chat's notes without making any (to follow a file being made).
pub async fn read(client: &TeamsClient, thread_id: &str) -> Result<NotesState> {
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    Ok(match notes_file(&thread(client, thread_id).await?) {
        Ok(Some(f)) => state_of(&f, &me),
        Err(()) => NotesState::Deleted,
        Ok(None) => NotesState::Preparing,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // The thread of OST group test after Teams made its notes (captured
    // 2026-11-16, ids shortened).
    fn group_thread(status: &str) -> Value {
        json!({ "id": "19:ef21@thread.v2", "fileReferences": { "fd75f050-b707-4ddf-bd19-1a0b1786ae91": {
            "createdAt": 1794824028156u64, "creator": "8:orgid:4287e791", "driveId": "b!sibJ",
            "fileReferenceId": "01VTZ3ZQTXVFX", "id": "fd75f050-b707-4ddf-bd19-1a0b1786ae91",
            "provisioningStatus": status, "subType": "loopthread", "type": "loop",
            "uri": "https://x.sharepoint.com/contentstorage/CSP_b2c9/Document%20Library/19_ef21_thread_v2/loop_loopThread.loop?nav=cz0" } } })
    }

    #[test]
    fn reads_the_threads_notes_file() {
        let f = notes_file(&group_thread("completed")).unwrap().unwrap();
        assert_eq!(f.status, "COMPLETED");
        assert_eq!(f.item_id, "01VTZ3ZQTXVFX");
        assert_eq!(f.creator, "8:orgid:4287e791");
        assert!(
            matches!(state_of(&f, "8:orgid:other"), NotesState::Ready { ref url, .. } if url.ends_with("loop_loopThread.loop?nav=cz0"))
        );
        assert_eq!(notes_file(&json!({ "id": "19:x" })), Ok(None));
    }

    #[test]
    fn follows_teams_provisioning_states() {
        let f = |s: &str| notes_file(&group_thread(s)).unwrap().unwrap();
        let initiator = f("FileCreatedWithInitiatorPermission");
        assert!(matches!(
            state_of(&initiator, "8:orgid:4287E791"),
            NotesState::Ready { .. }
        ));
        assert_eq!(state_of(&initiator, "8:orgid:other"), NotesState::Preparing);
        assert_eq!(
            state_of(&f("failed"), "8:orgid:4287e791"),
            NotesState::Failed
        );
        let mut in_progress = f("inProgress");
        in_progress.uri.clear();
        assert_eq!(
            state_of(&in_progress, "8:orgid:4287e791"),
            NotesState::Preparing
        );
        // Only deleted notes: Teams' "Your notes have been deleted."
        assert_eq!(notes_file(&group_thread("deleted")), Err(()));
    }

    #[test]
    fn picks_the_first_live_reference_by_id() {
        let t = json!({ "fileReferences": {
            "b": { "id": "b", "type": "loop", "subType": "loopthread", "provisioningStatus": "completed", "uri": "https://b" },
            "a": { "id": "a", "type": "loop", "subType": "loopthread", "provisioningStatus": "deleted", "uri": "https://a" },
            "c": { "id": "c", "type": "loop", "subType": "loopthread", "provisioningStatus": "completed", "uri": "https://c" },
            "d": { "id": "0", "type": "fluid", "subType": "other", "provisioningStatus": "completed", "uri": "https://d" } } });
        assert_eq!(notes_file(&t).unwrap().unwrap().uri, "https://b");
    }

    #[test]
    fn create_request_is_teams() {
        let (url, body) = create_request(
            "https://amer.ng.msg.teams.microsoft.com",
            "19:ef21@thread.v2",
            false,
        );
        assert_eq!(
            url,
            "https://amer.ng.msg.teams.microsoft.com/v1/threads/19%3Aef21%40thread.v2/files"
        );
        assert_eq!(body, r#"{"type":"loop","subType":"loopThread"}"#);
        let (url, _) = create_request("https://c", "48:notes", true);
        assert_eq!(
            url,
            "https://c/v1/threads/48%3Anotes/files?forceCreateFile=true&forceCreateReason=ClientFileNotFound"
        );
    }
}
