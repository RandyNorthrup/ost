//! Files shared with you, and who shared them, as Teams' OneDrive app and
//! its file pickers list them (Shared ▸ With you, Browse files by People,
//! a person's page). Graph's `/me/drive/sharedWithMe` is retired (it
//! returns nothing after November 2026); Teams never used it. OneDrive's
//! `SharedWithMeDataManager` (captured on winpc 2026-11-25) reads the
//! recent files service on your OneDrive's site (`sp.RecentFileCollection.
//! DeltaSync`, the same reply as Home), adds the folders shared with you
//! (`sp.SharedWithMeItemCollection.GetSharedWithMeItems?fileType='folder'`)
//! and files from outside your organization (`GetSharedWithMeExternalItems`),
//! keeps what its `isInvalidSWMItem` accepts, and orders them newest shared
//! first. People come from the same files: each one's sharer and sharing
//! history, in the order of your collaborators
//! (`sp.PeopleCollection.GetCollaboratorsAsStream`).

use anyhow::Result;
use serde::Serialize;
use serde_json::{Value, json};

use super::client::TeamsClient;
use super::drive::DriveItem;
use super::recent_files::{self, Recent};
use super::sharing;

/// Someone who shared a file with you, and when.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Sharer {
    /// Their Entra object id, lowercase.
    pub id: String,
    pub name: String,
    pub smtp: String,
    /// When (ISO).
    pub time: String,
}

/// One file shared with you.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct SharedFile {
    /// The file as the recent files service describes it (name, title,
    /// place line, Activity, SharePoint's ids).
    pub file: Recent,
    /// The service's id for it (OneDrive's item key).
    pub key: String,
    /// Its Visualization title (People's chips name files by it: a
    /// recording's meeting name).
    pub visual_title: String,
    /// Date shared (ISO): the last time someone shared it.
    pub shared: String,
    /// Who shared it last (Shared by).
    pub by: Sharer,
    /// Every time it was shared (OneDrive's sharing history).
    pub history: Vec<Sharer>,
    /// Its owner's address.
    pub owner_smtp: String,
}

/// A person who shared files with you.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Person {
    pub id: String,
    pub name: String,
    pub smtp: String,
    /// The files on their People row, newest shared first (dates are when
    /// this person shared them).
    pub files: Vec<SharedFile>,
    /// Their page: what they shared with you and files they own.
    pub items: Vec<SharedFile>,
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_string()
}

fn low(v: &Value) -> String {
    s(v).to_lowercase()
}

/// A time's milliseconds (0 when there is none), as OneDrive compares
/// `new Date(...)`.
fn millis(t: &str) -> i64 {
    chrono::DateTime::parse_from_rfc3339(t)
        .map(|t| t.timestamp_millis())
        .unwrap_or(0)
}

/// The entries of a shared-with-you reply (`d.GetSharedWithMeItems` or
/// `value`, each JSON text or an array).
pub fn list_entries(reply: &Value) -> Vec<Value> {
    let raw = reply["d"]
        .as_object()
        .and_then(|d| d.values().next())
        .unwrap_or(&reply["value"]);
    let v: Value = match raw {
        Value::String(t) => serde_json::from_str(t).unwrap_or_default(),
        other => other.clone(),
    };
    v.as_array().cloned().unwrap_or_default()
}

fn mark_hidden(mut e: Value) -> Value {
    e["file"]["ItemProperties"]["UserOptions"]["HiddenFromSharedWithMe"] = json!(true);
    e
}

/// OneDrive's item store: the recent files service's entries, external
/// files (those also listed as hidden are marked hidden) and shared
/// folders; a later entry for the same file replaces an earlier one.
pub fn merge(recent: &Value, external: &Value, hidden: &Value, folders: &Value) -> Vec<Value> {
    let hidden = list_entries(hidden);
    let hidden_ids: Vec<String> = hidden.iter().map(|e| s(&e["file"]["Id"])).collect();
    let all = recent_files::entries(recent)
        .into_iter()
        .chain(
            list_entries(external)
                .into_iter()
                .filter(|e| !hidden_ids.contains(&s(&e["file"]["Id"]))),
        )
        .chain(hidden.into_iter().map(mark_hidden))
        .chain(list_entries(folders));
    let mut out: Vec<Value> = Vec::new();
    for e in all {
        let id = s(&e["file"]["Id"]);
        match out
            .iter_mut()
            .find(|x| !id.is_empty() && s(&x["file"]["Id"]) == id)
        {
            Some(x) => *x = e,
            None => out.push(e),
        }
    }
    out
}

/// Why OneDrive's shared views leave an entry out (`_shouldRemoveItem`,
/// `isInvalidSWMItem` and `isInvalidODBItem`), None when it is listed.
pub fn left_out(entry: &Value) -> Option<&'static str> {
    let x = &entry["file"];
    let facet = low(&x["SharePointOnlineFacetStatus"]);
    if !facet.is_empty() && facet != "present" && facet != "partial" {
        return Some("Removed");
    }
    let kind = x["Visualization"]["Type"].as_str().unwrap_or_default();
    if s(&x["SubstrateContentDomainId"]).is_empty()
        && kind != "GenericList"
        && kind != "Playlist"
        && !recent_files::sp_ids(x)
    {
        return Some("UnsupportedFileType");
    }
    let ext = s(&x["FileExtension"]);
    if s(&x["ItemProperties"]["Shared"]["LastSharedWithMailboxOwnerDateTime"]).is_empty()
        || ["ics", "eml", "aspx", "zip"].contains(&ext.as_str())
        || kind.is_empty()
        || kind == "GenericList"
        || kind == "Lists"
    {
        return Some("Missing required properties");
    }
    recent_files::invalid_odb(x)
}

fn hidden(entry: &Value) -> bool {
    entry["file"]["ItemProperties"]["UserOptions"]["HiddenFromSharedWithMe"]
        .as_bool()
        .unwrap_or(false)
}

/// Its owner's sign-in name (OneDrive: the creator's UPN, the file's
/// owner, else the last part of the author field).
fn owner_upn(x: &Value) -> String {
    let creator = s(&x["CreationInfo"]["User"]["Upn"]);
    if !creator.is_empty() {
        return creator;
    }
    let owner = s(&x["FileOwner"]);
    if !owner.is_empty() {
        return owner;
    }
    s(&x["ItemProperties"]["Default"]["AuthorOWSUSER"])
        .rsplit('|')
        .next()
        .unwrap_or_default()
        .trim()
        .to_string()
}

/// One listed entry; `personal` is your OneDrive's site.
pub fn parse(entry: &Value, personal: &str) -> SharedFile {
    let x = &entry["file"];
    let shared = &x["ItemProperties"]["Shared"];
    let when = s(&x["UserRelationship"]["LastSharedDateTime"]);
    SharedFile {
        file: recent_files::parse(entry, personal),
        key: s(&x["Id"]),
        visual_title: s(&x["Visualization"]["Title"]),
        by: Sharer {
            id: low(&x["UserRelationship"]["LastSharedById"]),
            name: s(&shared["LastSharedWithMailboxOwnerByDisplayName"]),
            smtp: s(&shared["LastSharedWithMailboxOwnerBySmtp"]),
            time: when.clone(),
        },
        shared: when,
        history: x["AllExtensions"]["SharingHistory"]["Instances"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|i| Sharer {
                id: low(&i["SharedByAadId"]),
                name: s(&i["SharedByDisplayName"]),
                smtp: s(&i["SharedBySmtp"]),
                time: s(&i["SharedByTime"]),
            })
            .collect(),
        owner_smtp: s(&x["FileOwner"]),
    }
}

/// You: your object id and sign-in name.
#[derive(Debug, Clone, Default)]
pub struct Me {
    pub id: String,
    pub upn: String,
}

/// OneDrive's item store for the shared views: the entries it keeps,
/// parsed.
pub fn store(entries: &[Value], personal: &str) -> Vec<(SharedFile, bool)> {
    entries
        .iter()
        .filter(|e| left_out(e).is_none())
        .map(|e| (parse(e, personal), hidden(e)))
        .collect()
}

/// Shared ▸ With you: the store less hidden files and those you shared
/// yourself (`swmFilterHelper`), newest shared first.
pub fn with_you(entries: &[Value], personal: &str, me: &Me) -> Vec<SharedFile> {
    let (id, upn) = (me.id.to_lowercase(), me.upn.to_lowercase());
    let mut rows: Vec<SharedFile> = entries
        .iter()
        .filter(|e| left_out(e).is_none() && !hidden(e))
        .filter(|e| {
            let x = &e["file"];
            (id.is_empty() && upn.is_empty())
                || low(&x["UserRelationship"]["LastSharedById"]) != id
                || owner_upn(x).to_lowercase() != upn
        })
        .map(|e| parse(e, personal))
        .collect();
    rows.sort_by_key(|r| std::cmp::Reverse(millis(&r.shared)));
    rows
}

/// OneDrive's per-person match (`(userId, userSmtp)` against a sharer).
fn same(id: &str, smtp: &str, other: &Sharer) -> bool {
    !id.is_empty() && id == other.id || !smtp.is_empty() && smtp.eq_ignore_ascii_case(&other.smtp)
}

/// When `who` shared the file, and their name as Shared by shows it, on
/// a person's page (`DateSharedCell` / `SharedByCell`); the last share
/// when they never did.
pub fn shared_by(f: &SharedFile, id: &str, smtp: &str) -> (String, String) {
    if (!id.is_empty() || !smtp.is_empty()) && same(id, smtp, &f.by) {
        return (f.shared.clone(), f.by.name.clone());
    }
    for h in &f.history {
        if same(id, smtp, h) {
            return (h.time.clone(), h.name.clone());
        }
    }
    (f.shared.clone(), f.by.name.clone())
}

/// Browse files by People: each person who shared files with you (not
/// you), with their row's files and their page; ordered as your
/// collaborators (`order`: object ids), then by how many files.
pub fn people(entries: &[Value], personal: &str, me: &Me, order: &[String]) -> Vec<Person> {
    let me_id = me.id.to_lowercase();
    let store: Vec<SharedFile> = store(entries, personal)
        .into_iter()
        .filter(|(_, h)| !h)
        .map(|(f, _)| f)
        .collect();
    let mut people: Vec<Person> = Vec::new();
    let mut add = |who: &Sharer, f: &SharedFile| {
        if who.id.is_empty() || who.id == me_id {
            return;
        }
        let mut f = f.clone();
        f.shared = who.time.clone();
        let p = match people.iter_mut().position(|p| p.id == who.id) {
            Some(i) => &mut people[i],
            None => {
                people.push(Person {
                    id: who.id.clone(),
                    name: who.name.clone(),
                    smtp: who.smtp.clone(),
                    ..Default::default()
                });
                people.last_mut().unwrap()
            }
        };
        if !p.files.iter().any(|x| x.key == f.key) {
            p.files.push(f);
        }
    };
    for f in &store {
        add(&f.by, f);
        for h in &f.history {
            add(h, f);
        }
    }
    for p in &mut people {
        p.files
            .sort_by_key(|f| std::cmp::Reverse(millis(&f.shared)));
    }
    let order: Vec<String> = order.iter().map(|o| o.to_lowercase()).collect();
    let pos = |p: &Person| order.iter().position(|o| *o == p.id);
    people.sort_by(|a, b| {
        if order.is_empty() {
            let first = |p: &Person| p.files.first().map(|f| millis(&f.shared)).unwrap_or(0);
            return first(b).cmp(&first(a));
        }
        match (pos(a), pos(b)) {
            (Some(x), Some(y)) => x.cmp(&y),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => b.files.len().cmp(&a.files.len()),
        }
    });
    for p in &mut people {
        p.items = page(&store, p, &me.id, &me.upn);
    }
    people
}

/// A person's page (`filterByPerson`): files they shared with you and
/// files they own, each dated as when they shared it; ordered newest
/// first by your own share dates, as OneDrive sorts it.
fn page(store: &[SharedFile], p: &Person, me_id: &str, me_upn: &str) -> Vec<SharedFile> {
    // OneDrive takes the person's address from their first file.
    let smtp = store
        .iter()
        .find_map(|f| {
            std::iter::once(&f.by)
                .chain(&f.history)
                .find(|h| h.id == p.id)
                .map(|h| h.smtp.clone())
        })
        .unwrap_or_else(|| p.smtp.clone());
    let (me_id, me_upn) = (me_id.to_lowercase(), me_upn.to_lowercase());
    let mut rows: Vec<(i64, SharedFile)> = store
        .iter()
        .filter(|f| {
            f.by.id == p.id
                || f.history.iter().any(|h| h.id == p.id)
                || !smtp.is_empty() && smtp.eq_ignore_ascii_case(&f.owner_smtp)
        })
        .map(|f| {
            let key = millis(&shared_by(f, &me_id, &me_upn).0);
            let (when, name) = shared_by(f, &p.id, &smtp);
            let mut f = f.clone();
            f.shared = when;
            f.by = Sharer { name, ..f.by };
            (key, f)
        })
        .collect();
    rows.sort_by_key(|(k, _)| std::cmp::Reverse(*k));
    rows.into_iter().map(|(_, f)| f).collect()
}

/// The replies OneDrive's shared views read: the recent files service,
/// external files (and those hidden), shared folders; with your
/// OneDrive's site. Only the recent files service must answer.
pub async fn fetch_entries(client: &TeamsClient) -> Result<(Vec<Value>, String)> {
    let (recent, personal) = recent_files::fetch_reply(client).await?;
    let api = format!("{personal}/_api/sp.SharedWithMeItemCollection");
    let get = |path: String| async move {
        sharing::get_with(&path, &[("accept", "application/json")])
            .await
            .unwrap_or_else(|e| {
                tracing::debug!("Shared with you: {e:#}");
                Value::Null
            })
    };
    let (external, hidden, folders) = tokio::join!(
        get(format!("{api}.GetSharedWithMeExternalItems?top=100")),
        get(format!("{api}.GetSharedWithMeExternalItems?hidden=true")),
        get(format!(
            "{api}.GetSharedWithMeItems?top=500&fileType=%27folder%27"
        )),
    );
    Ok((merge(&recent, &external, &hidden, &folders), personal))
}

/// Your collaborators' object ids, as OneDrive orders People.
pub async fn collaborator_ids(personal: &str) -> Vec<String> {
    match sharing::get_with(
        &format!("{personal}/_api/sp.PeopleCollection.GetCollaboratorsAsStream?top=100"),
        &[("accept", "application/json")],
    )
    .await
    {
        Ok(v) => parse_collaborator_ids(&v),
        Err(e) => {
            tracing::warn!("Collaborators: {e:#}");
            Vec::new()
        }
    }
}

pub fn parse_collaborator_ids(reply: &Value) -> Vec<String> {
    reply["Groups"][0]["Suggestions"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|p| p["Id"].as_str())
        .map(|id| id.split('@').next().unwrap_or_default().to_lowercase())
        .filter(|id| !id.is_empty())
        .collect()
}

pub fn me(client: &TeamsClient) -> Me {
    Me {
        id: client.object_id().unwrap_or_default(),
        upn: client.user_principal_name().unwrap_or_default(),
    }
}

/// These files as the OneDrive app's rows take them, with Graph's items
/// for their actions (one `$batch` per 20).
pub async fn with_items(
    client: &TeamsClient,
    files: Vec<SharedFile>,
) -> Vec<(SharedFile, DriveItem)> {
    let recents: Vec<Recent> = files.iter().map(|f| f.file.clone()).collect();
    let items = recent_files::graph_items(client, &recents).await;
    files
        .into_iter()
        .zip(items)
        .map(|(f, g)| {
            let it = recent_files::drive_item(&f.file, g);
            (f, it)
        })
        .collect()
}

/// A shared file's row: Date shared, Shared by and Activity as Teams
/// shows them.
pub fn row(f: &SharedFile, item: &DriveItem, now: chrono::DateTime<chrono::Local>) -> Value {
    use super::list_rows::{activity_time, decorate};
    let local = |t: &str| {
        chrono::DateTime::parse_from_rfc3339(t)
            .ok()
            .map(|t| t.with_timezone(&chrono::Local))
    };
    let mut v = decorate(item, None, now);
    v["title"] = json!(f.file.title);
    v["visual_title"] = json!(f.visual_title);
    v["location"] = json!(f.file.location);
    v["owner"] = json!(f.file.owner);
    v["modified_by"] = json!(f.by.name);
    v["shared"] = json!(f.shared);
    match local(&f.shared) {
        Some(t) => {
            v["modified_text"] = json!(activity_time(t, now));
            v["modified_title"] = json!(t.format("%-m/%-d/%Y %-I:%M %p").to_string());
        }
        None => {
            v["modified_text"] = json!("");
            v["modified_title"] = json!("");
        }
    }
    v["activity"] = match &f.file.activity {
        Some(a) => json!({
            "kind": a.kind,
            "text": a.text,
            "time": local(&a.time).map(|t| recent_files::activity_day(t, now)).unwrap_or_default(),
        }),
        None => Value::Null,
    };
    v
}

/// Files shared with you, as rows with Graph's items (Shared ▸ With you).
pub async fn with_you_rows(client: &TeamsClient) -> Result<Vec<(SharedFile, DriveItem)>> {
    let (entries, personal) = fetch_entries(client).await?;
    let files = with_you(&entries, &personal, &me(client));
    Ok(with_items(client, files).await)
}

/// Browse files by People, each person's files with Graph's items:
/// [(person, row files, page items)].
pub async fn people_rows(
    client: &TeamsClient,
) -> Result<
    Vec<(
        Person,
        Vec<(SharedFile, DriveItem)>,
        Vec<(SharedFile, DriveItem)>,
    )>,
> {
    let (entries, personal) = fetch_entries(client).await?;
    let order = collaborator_ids(&personal).await;
    let people = people(&entries, &personal, &me(client), &order);
    // One lookup per file, however many people list it.
    let mut unique: Vec<SharedFile> = Vec::new();
    for p in &people {
        for f in p.files.iter().chain(&p.items) {
            if !unique.iter().any(|u| u.key == f.key) {
                unique.push(f.clone());
            }
        }
    }
    let looked = with_items(client, unique).await;
    let item = |f: &SharedFile| {
        looked
            .iter()
            .find(|(u, _)| u.key == f.key)
            .map(|(_, it)| it.clone())
            .unwrap_or_default()
    };
    Ok(people
        .into_iter()
        .map(|p| {
            let files = p.files.iter().map(|f| (f.clone(), item(f))).collect();
            let items = p.items.iter().map(|f| (f.clone(), item(f))).collect();
            (p, files, items)
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    const ME_SITE: &str =
        "https://scnetsolutions-my.sharepoint.com/personal/ost-test1_scnetsolutions_com";
    const T1: &str = "4287e791-1b98-4963-8b94-281c50472683";
    const T2: &str = "9edcc62f-2f4b-4f55-bbf9-02c7cbaadbb5";
    const T3: &str = "01c4860d-0000-4000-8000-000000000003";

    fn me() -> Me {
        Me {
            id: T1.into(),
            upn: "ost-test1@scnetsolutions.com".into(),
        }
    }

    /// An entry shaped as ost-test1's DeltaSync reply (captured on winpc
    /// 2026-11-25).
    #[allow(clippy::too_many_arguments)]
    fn entry(
        id: &str,
        name: &str,
        kind: &str,
        owner: &str,
        shared: Option<(&str, &str, &str, &str)>,
        history: &[(&str, &str, &str, &str)],
        facet: &str,
        activity: Option<(&str, u64, &str)>,
    ) -> Value {
        let site = format!(
            "https://scnetsolutions-my.sharepoint.com/personal/{}",
            owner.replace(['@', '.'], "_")
        );
        let ext = name.rsplit_once('.').map(|(_, e)| e).unwrap_or_default();
        let mut file = json!({
            "Id": id, "FileName": name, "FileExtension": ext, "FileOwner": owner,
            "SharePointOnlineFacetStatus": facet,
            "SharePointItem": { "SiteId": "86beb970-8c88-4ae2-acce-d51c851ec061", "WebId": "a3305c60-5edd-4721-8f56-1352f4b64bcf",
                                "ListId": "c300f6d2-5ee5-4f38-a11c-6a78cbe2bf1d", "UniqueId": format!("{id}-cd62-416f-b275-829111b2ccd7"),
                                "ListItemId": "20", "SitePath": site, "FileUrl": format!("{site}/Documents/{name}") },
            "Visualization": { "Title": name.rsplit_once('.').map(|(t, _)| t).unwrap_or(name), "Type": kind,
                               "ContainerTitle": if owner.starts_with("ost-test2") { "OST Test 2" } else if owner.starts_with("ost-test3") { "OST Test 3" } else { "OST Test 1" } },
            "UserRelationship": {},
            "ItemProperties": {},
        });
        if let Some((by, name, smtp, when)) = shared {
            file["UserRelationship"] = json!({ "LastSharedById": by, "LastSharedDateTime": when });
            file["ItemProperties"]["Shared"] =
                json!({ "LastSharedWithMailboxOwnerDateTime": when });
            if !name.is_empty() {
                file["ItemProperties"]["Shared"]["LastSharedWithMailboxOwnerByDisplayName"] =
                    json!(name);
                file["ItemProperties"]["Shared"]["LastSharedWithMailboxOwnerBySmtp"] = json!(smtp);
            }
        }
        if !history.is_empty() {
            file["AllExtensions"]["SharingHistory"]["Instances"] = json!(history
                .iter()
                .map(|(id, name, smtp, t)| json!({ "SharedByAadId": id, "SharedByDisplayName": name, "SharedBySmtp": smtp, "SharedByTime": t }))
                .collect::<Vec<_>>());
        }
        let mut e = json!({ "file": file });
        if let Some((format, t, user)) = activity {
            e["activity"] = json!({ "message_format": format, "type": t, "users": [{ "display_name": user }], "timestamp": "2026-11-23T15:11:17Z" });
        }
        e
    }

    fn reply() -> Value {
        let t2 = "ost-test2@scnetsolutions.com";
        let t3 = "ost-test3@scnetsolutions.com";
        let t1 = "ost-test1@scnetsolutions.com";
        let files = vec![
            // Teams' With you, in its order (a few listed out of order here).
            entry(
                "01",
                "0.2.0 release checklist.loop",
                "Fluid",
                t3,
                Some((T3, "OST Test 3", t3, "2026-11-23T15:11:17Z")),
                &[],
                "Present",
                Some(("{0} shared this in a Teams chat", 9, "OST Test 3")),
            ),
            entry(
                "02",
                "Release-notes-0.3.pdf",
                "Pdf",
                t3,
                Some((T3, "OST Test 3", t3, "2026-11-25T17:11:46Z")),
                &[],
                "Present",
                Some(("{0} shared this in a Teams chat", 9, "OST Test 3")),
            ),
            entry(
                "03",
                "OST-0.2.0-release-notes.md",
                "Text",
                t2,
                Some((T2, "OST Test 2", t2, "2026-11-23T15:08:19Z")),
                &[],
                "Present",
                None,
            ),
            entry(
                "04",
                "OST TEST 217 r3 town hall B-20261119_132749UTC-Meeting Recording.mp4",
                "Video",
                t2,
                Some((T2, "OST Test 2", t2, "2026-11-19T13:31:57Z")),
                &[],
                "Present",
                Some(("{0} recorded a meeting", 9, "OST Test 2")),
            ),
            // No sharer: listed without Shared by; on OST Test 2's page as
            // its owner.
            entry(
                "05",
                "OST TEST 217 town hall B2-20261119_095522UTC-Meeting Recording.mp4",
                "Video",
                t2,
                Some(("", "", "", "2026-11-19T09:57:59Z")),
                &[],
                "Present",
                None,
            ),
            // Yours, shared by you (OST Test 2 shared it too): not in With
            // you, but on OST Test 2's row and page.
            entry(
                "06",
                "ost-share-test.txt",
                "Text",
                t1,
                Some((T1, "OST Test 1", t1, "2026-11-13T21:42:17.131Z")),
                &[
                    (T1, "OST Test 1", t1, "2026-11-13T13:42:17.131-08:00"),
                    (T2, "OST Test 2", t2, "2026-11-11T21:50:20-08:00"),
                ],
                "Present",
                Some(("You replied to a comment", 8, "")),
            ),
            // Left out: never shared with you (opened only).
            entry(
                "07",
                "ost-open-test.docx",
                "Word",
                t1,
                None,
                &[],
                "Present",
                None,
            ),
            // Left out: deleted.
            entry(
                "08",
                "gone.docx",
                "Word",
                t2,
                Some((T2, "OST Test 2", t2, "2026-11-24T10:00:00Z")),
                &[],
                "Deleted",
                None,
            ),
            // Left out: a zip.
            entry(
                "09",
                "logs.zip",
                "Archive",
                t2,
                Some((T2, "OST Test 2", t2, "2026-11-24T10:00:00Z")),
                &[],
                "Present",
                None,
            ),
        ];
        json!({ "value": json!({ "files": files }).to_string() })
    }

    #[test]
    fn with_you_lists_what_teams_lists_in_its_order() {
        let entries = merge(
            &reply(),
            &Value::Null,
            &Value::Null,
            &json!({ "d": { "GetSharedWithMeItems": "[]" } }),
        );
        let rows = with_you(&entries, ME_SITE, &me());
        assert_eq!(
            rows.iter()
                .map(|r| r.file.title.as_str())
                .collect::<Vec<_>>(),
            [
                "Release-notes-0.3",
                "0.2.0 release checklist",
                "OST-0.2.0-release-notes",
                "OST TEST 217 r3 town hall B-20261119_132749UTC-Meeting Recording",
                "OST TEST 217 town hall B2-20261119_095522UTC-Meeting Recording",
            ]
        );
        assert_eq!(rows[0].by.name, "OST Test 3");
        assert_eq!(rows[0].file.location, "OST Test 3's Files");
        assert_eq!(rows[4].by.name, "");
        let why: Vec<_> = entries.iter().map(left_out).collect();
        assert_eq!(why[6], Some("Missing required properties"));
        assert_eq!(why[7], Some("Removed"));
        assert_eq!(why[8], Some("Missing required properties"));
    }

    #[test]
    fn hidden_and_folders_merge_as_onedrive_does() {
        let folder = entry(
            "10",
            "Plans",
            "Folder",
            "ost-test2@scnetsolutions.com",
            Some((
                T2,
                "OST Test 2",
                "ost-test2@scnetsolutions.com",
                "2026-11-25T18:00:00Z",
            )),
            &[],
            "Present",
            None,
        );
        let mut ext = entry(
            "11",
            "Partner.docx",
            "Word",
            "x@partner.com",
            Some(("", "Partner", "x@partner.com", "2026-11-25T19:00:00Z")),
            &[],
            "Present",
            None,
        );
        ext["file"]["SharePointItem"]["SitePath"] =
            json!("https://partner-my.sharepoint.com/personal/x");
        let folders = json!({ "value": json!([folder]).to_string() });
        let hidden = json!({ "value": [ext.clone()] });
        let external = json!({ "value": [ext] });
        let entries = merge(&reply(), &external, &hidden, &folders);
        let rows = with_you(&entries, ME_SITE, &me());
        // The hidden external file is not listed; the shared folder is,
        // newest first.
        assert_eq!(rows[0].file.name, "Plans");
        assert!(!rows.iter().any(|r| r.file.name == "Partner.docx"));
    }

    #[test]
    fn people_rows_and_pages_match_teams() {
        let entries = merge(&reply(), &Value::Null, &Value::Null, &Value::Null);
        // GetCollaborators' order: OST Test 2 before OST Test 3.
        let order = parse_collaborator_ids(&json!({ "Groups": [{ "Suggestions": [
            { "Id": format!("{T2}@2716d134"), "DisplayName": "OST Test 2" },
            { "Id": format!("{T1}@2716d134"), "DisplayName": "OST Test 1" },
            { "Id": format!("{T3}@2716d134"), "DisplayName": "OST Test 3" } ] }] }));
        let people = people(&entries, ME_SITE, &me(), &order);
        assert_eq!(
            people.iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
            ["OST Test 2", "OST Test 3"]
        );
        let t2 = &people[0];
        assert_eq!(
            t2.files
                .iter()
                .map(|f| f.file.name.as_str())
                .collect::<Vec<_>>(),
            [
                "OST-0.2.0-release-notes.md",
                "OST TEST 217 r3 town hall B-20261119_132749UTC-Meeting Recording.mp4",
                "ost-share-test.txt"
            ]
        );
        // Their page adds the recording they own, without a sharer; your
        // file shows when OST Test 2 shared it.
        let page: Vec<_> = t2
            .items
            .iter()
            .map(|f| (f.file.name.as_str(), f.by.name.as_str(), f.shared.as_str()))
            .collect();
        assert_eq!(page.len(), 4);
        assert_eq!(
            page[2].0,
            "OST TEST 217 town hall B2-20261119_095522UTC-Meeting Recording.mp4"
        );
        assert_eq!(page[2].1, "");
        assert_eq!(
            page[3],
            (
                "ost-share-test.txt",
                "OST Test 2",
                "2026-11-11T21:50:20-08:00"
            )
        );
        assert_eq!(
            people[1]
                .files
                .iter()
                .map(|f| f.file.title.as_str())
                .collect::<Vec<_>>(),
            ["Release-notes-0.3", "0.2.0 release checklist"]
        );
        // Without collaborators: newest first file first.
        let people = super::people(&entries, ME_SITE, &me(), &[]);
        assert_eq!(people[0].name, "OST Test 3");
    }

    #[test]
    fn rows_word_date_shared_and_activity() {
        let entries = merge(&reply(), &Value::Null, &Value::Null, &Value::Null);
        let rows = with_you(&entries, ME_SITE, &me());
        let at = |s: &str| {
            chrono::DateTime::parse_from_rfc3339(s)
                .unwrap()
                .with_timezone(&chrono::Local)
        };
        let now = at("2026-11-25T18:30:00Z");
        let it = recent_files::drive_item(&rows[0].file, None);
        let v = row(&rows[0], &it, now);
        assert_eq!(v["title"], "Release-notes-0.3");
        assert_eq!(v["modified_by"], "OST Test 3");
        assert_eq!(v["modified_text"], "1h ago");
        assert_eq!(v["activity"]["kind"], "share");
        assert_eq!(
            v["activity"]["text"],
            "OST Test 3 shared this in a Teams chat"
        );
        let v = row(
            &rows[4],
            &recent_files::drive_item(&rows[4].file, None),
            now,
        );
        assert!(v["activity"].is_null());
    }
}
