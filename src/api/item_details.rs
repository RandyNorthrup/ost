//! The Details pane of Teams' Files apps (docs/spec/details-pane.md): the
//! item's activity feed worded as OneDrive words it, its notification bell,
//! comments, and More details. OneDrive's pane reads SharePoint's v2.0
//! `activities` and v2.1 `notificationPreferences`, and sets the bell
//! through `ActivityLogger/FeedbackDirect`.

use anyhow::{Result, bail};
use chrono::{DateTime, Datelike, Duration, Local, TimeZone};
use serde::Serialize;
use serde_json::{Value, json};

use super::drive::DriveItem;
use super::list_rows::friendly_display;
use super::sharing::{get_with, post};

/// One card of the activity list.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct FeedItem {
    /// edit, move, rename, share, create, delete, version, restore, comment,
    /// commentResponse, mention, copy.
    pub kind: String,
    /// The text, with folder and file names in `<b>` (StyledText).
    pub text: String,
    /// "About a minute ago", "Yesterday at 10:37 PM".
    pub time: String,
    /// "Nov 12 at 8:48 AM".
    pub tip: String,
    /// "Today", "Yesterday", "This week", ...
    pub group: String,
    /// A comment card (from the item's comments): its id, author and
    /// whether it is yours; `text` is then the comment.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub comment_id: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub author: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub author_email: String,
    pub mine: bool,
    /// A comment's text as typed (mentions as names), for Edit comment.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub source: String,
    /// A comment changed since it was posted ("{time} • Edited").
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub edited: bool,
    /// A comment's replies, oldest first.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub replies: Vec<Reply>,
    #[serde(skip)]
    pub at: i64,
}

/// A reply under a comment card: "You replied" / "{name} replied", the text
/// and the time in the client's wording ("Just now").
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Reply {
    pub id: String,
    pub author: String,
    pub author_email: String,
    pub mine: bool,
    pub text: String,
    pub time: String,
    pub edited: bool,
}

/// What the pane shows beyond the list's row.
#[derive(Debug, Clone, Default, Serialize)]
pub struct Details {
    pub activities: Vec<FeedItem>,
    /// The bell: notifications for this item's activity.
    pub notify: bool,
    /// "11/11/2026 08:11 PM".
    pub created: String,
    /// "11/11/2026 10:28 PM".
    pub modified: String,
    /// "txt File".
    pub type_text: String,
    /// ["My files", "ost-share-test.txt"].
    pub path: Vec<String>,
    pub comments_disabled: bool,
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}
fn bold(s: &str) -> String {
    format!("<b>{}</b>", esc(s))
}
fn fill(template: &str, args: &[&str]) -> String {
    let mut out = template.to_string();
    for (i, a) in args.iter().enumerate() {
        out = out.replace(&format!("{{{i}}}"), a);
    }
    out
}
/// OneDrive's "a||b||c" list forms (intervals 1||2||3).
fn pick<'a>(forms: &'a str, n: usize) -> &'a str {
    let v: Vec<&str> = forms.split("||").collect();
    v[n.clamp(1, v.len()) - 1]
}

struct Person {
    name: String,
    me: bool,
}

fn person(u: &Value, me: &str) -> Person {
    let email = u["email"].as_str().or(u["userPrincipalName"].as_str()).unwrap_or_default();
    Person {
        name: esc(u["displayName"].as_str().filter(|s| !s.is_empty()).unwrap_or(if email.is_empty() { "Someone" } else { email })),
        me: u.get("self").is_some() || (!email.is_empty() && email.eq_ignore_ascii_case(me)),
    }
}

/// The last name in a path ("personal/a/Documents/x.txt" → its folder
/// "Documents" when `dir`).
fn last(path: &str, dir: bool) -> String {
    let p = if dir { path.rsplit_once('/').map(|(d, _)| d).unwrap_or_default() } else { path };
    p.rsplit('/').next().unwrap_or_default().to_string()
}

/// One activity as the pane words it (about one item: "this file").
/// `name` is the item the pane is about (a rename's new name when the
/// activity leaves it out, as OneDrive's pane does).
pub fn describe(a: &Value, me: &str, name: &str) -> Option<(String, String)> {
    let act = &a["action"];
    let has = |k: &str| act.get(k).is_some();
    let comment = &act["comment"];
    let kind = if has("mention") {
        "mention"
    } else if comment.is_object() && !comment["isReply"].as_bool().unwrap_or(false) {
        "comment"
    } else if comment.is_object() {
        "commentResponse"
    } else {
        ["create", "archive", "reactivate", "delete", "edit", "move", "rename", "restore", "restoreVersion", "share", "version", "copy"]
            .into_iter()
            .find(|k| has(k))?
    };
    let actor = person(&a["actor"]["user"], me);
    let you = actor.me;
    let who = actor.name.as_str();
    let this = "this file";
    let text = match kind {
        "edit" | "restoreVersion" => if you { fill(pick("You edited {0}||You and {2} edited {0}||You, {2}, and {3} edited {0}", 1), &[this]) } else { fill(pick("{1} edited {0}||{1} and {2} edited {0}||{1}, {2}, and {3} edited {0}", 1), &[this, who]) },
        "move" => {
            let m = &act["move"];
            let from = m["From"].as_str().or(m["from"].as_str()).map(|p| bold(&last(p, true)));
            let to = m["to"].as_str().map(|p| bold(&last(p, true)));
            match (from, to) {
                (Some(f), Some(t)) => fill(if you { "You moved {0} from {2} to {3}" } else { "{1} moved {0} from {2} to {3}" }, &[this, who, &f, &t]),
                (Some(f), None) => fill(if you { "You moved {0} from {2}" } else { "{1} moved {0} from {2}" }, &[this, who, &f]),
                (None, Some(t)) => fill(if you { "You moved {0} to {3}" } else { "{1} moved {0} to {3}" }, &[this, who, "", &t]),
                _ => fill(if you { "You moved {0}" } else { "{1} moved {0}" }, &[this, who]),
            }
        }
        "rename" => {
            let r = &act["rename"];
            match r["oldName"].as_str() {
                Some(old) => {
                    let new = [r["newName"].as_str(), a["driveItem"]["name"].as_str(), Some(name)].into_iter().flatten().find(|s| !s.is_empty()).unwrap_or_default();
                    fill(if you { "You renamed {1} to {2}" } else { "{0} renamed {1} to {2}" }, &[who, &bold(old), &bold(new)])
                }
                None => fill(if you { "You renamed {0}" } else { "{1} renamed {0}" }, &[this, who]),
            }
        }
        "share" => {
            let to: Vec<Person> = act["share"]["recipients"].as_array().into_iter().flatten().map(|r| person(&r["user"], me)).collect();
            if to.is_empty() {
                fill(if you { pick("You shared {0}||You and {2} shared {0}||You, {2}, and {3} shared {0}", 1).to_string() } else { pick("{1} shared {0}||{1} and {2} shared {0}||{1}, {2}, and {3} shared {0}", 1).to_string() }.as_str(), &[this, who])
            } else {
                // You first, then the others.
                let to_you = to.iter().any(|p| p.me);
                let names: Vec<String> = to.iter().filter(|p| !p.me).map(|p| p.name.clone()).collect();
                if to.len() > 3 {
                    let rest = to.len() - 3;
                    let more = if rest == 1 { "1 other".to_string() } else { format!("{rest} others") };
                    let t = match (to_you, you) {
                        (true, true) => "You shared {0} with yourself, {3}, {4}, and {5}",
                        (true, false) => "{1} shared {0} with you, {3}, {4}, and {5}",
                        (false, true) => "You shared {0} with {2}, {3}, {4}, and {5}",
                        (false, false) => "{1} shared {0} with {2}, {3}, {4}, and {5}",
                    };
                    let n = |i: usize| names.get(i).cloned().unwrap_or_default();
                    if to_you { fill(t, &[this, who, "", &n(0), &n(1), &more]) } else { fill(t, &[this, who, &n(0), &n(1), &n(2), &more]) }
                } else {
                    let forms = match (to_you, you) {
                        (true, true) => "You shared {0} with yourself||You shared {0} with yourself and {3}||You shared {0} with yourself, {3}, and {4}",
                        (true, false) => "{1} shared {0} with you||{1} shared {0} with you and {3}||{1} shared {0} with you, {3}, and {4}",
                        (false, true) => "You shared {0} with {2}||You shared {0} with {2} and {3}||You shared {0} with {2}, {3}, and {4}",
                        (false, false) => "{1} shared {0} with {2}||{1} shared {0} with {2} and {3}||{1} shared {0} with {2}, {3}, and {4}",
                    };
                    let mut args: Vec<&str> = vec![this, who];
                    if to_you { args.push(""); }
                    args.extend(names.iter().map(String::as_str));
                    fill(pick(forms, to.len()), &args)
                }
            }
        }
        "create" => fill(if you { "You created {0}" } else { "{1} created {0}" }, &[this, who]),
        "delete" => fill(if you { "You deleted {0}" } else { "{1} deleted {0}" }, &[this, who]),
        "archive" => fill(if you { "You archived {0}" } else { "{1} archived {0}" }, &[this, who]),
        "reactivate" => fill(if you { "You reactivated {0}" } else { "{1} reactivated {0}" }, &[this, who]),
        "version" => {
            let v = act["version"]["newVersion"].as_str()?;
            fill(if you { "You created {2} of this file" } else { "{1} created {2} of this file" }, &[this, who, v])
        }
        "restore" => "This file was restored".into(),
        "comment" => if you { "You commented".into() } else { fill("{1} commented", &[this, who]) },
        "commentResponse" => if you { "You replied to a comment".into() } else { fill("{1} replied to a comment", &[COMMENT, who]) },
        "mention" => {
            let to: Vec<Person> = act["mention"]["mentionees"].as_array().into_iter().flatten().map(|m| person(&m["user"], me)).collect();
            let first = to.iter().find(|p| !p.me).map(|p| p.name.clone()).unwrap_or_default();
            match (to.iter().any(|p| p.me), you) {
                (true, true) => "You mentioned yourself".into(),
                (true, false) => fill("{1} mentioned you", &[this, who]),
                (false, true) => fill("You mentioned {2}", &[this, who, &first]),
                (false, false) => fill("{1} mentioned {2}", &[this, who, &first]),
            }
        }
        _ => return None,
    };
    let kind = if kind == "restoreVersion" { "edit" } else { kind };
    Some((kind.to_string(), text))
}

const COMMENT: &str = "comment";

/// OneDrive's date groups for the activity list.
pub fn group(t: DateTime<Local>, now: DateTime<Local>) -> String {
    let day = |d: DateTime<Local>| d.date_naive();
    let today = now.date_naive();
    let start = |d: chrono::NaiveDate| Local.from_local_datetime(&d.and_hms_opt(0, 0, 0).unwrap()).earliest().unwrap_or(now);
    let sunday = start(today) - Duration::days(i64::from(today.weekday().num_days_from_sunday()));
    if day(t) == today {
        return "Today".into();
    }
    if day(t) == today - Duration::days(1) {
        return "Yesterday".into();
    }
    if t > sunday {
        return "This week".into();
    }
    if t > sunday - Duration::days(7) {
        return "Last week".into();
    }
    if t > start(today) - Duration::days(14) {
        return "Two weeks ago".into();
    }
    if t > start(today) - Duration::days(21) {
        return "Three weeks ago".into();
    }
    if t.year() == now.year() && t.month() == now.month() {
        return "This month".into();
    }
    if t.year() == now.year() && now.month() - t.month() == 1 {
        return "Last month".into();
    }
    if t.year() == now.year() {
        return t.format("%B").to_string();
    }
    t.format("%B %Y").to_string()
}

/// "Nov 12 at 8:48 AM" (and the year when it isn't this one).
pub fn tip(t: DateTime<Local>, now: DateTime<Local>) -> String {
    let date = if t.year() == now.year() { t.format("%b %-d").to_string() } else { t.format("%b %-d, %Y").to_string() };
    format!("{date} at {}", t.format("%-I:%M %p"))
}

/// The activities reply as the pane lists them. Back-to-back edits by the
/// same person read as one (comments, shown as their own cards, don't
/// separate them), as in Teams.
pub fn feed(reply: &Value, me: &str, name: &str, now: DateTime<Local>) -> Vec<FeedItem> {
    let mut last_editor: Option<String> = None;
    reply["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|a| {
            let (kind, text) = describe(a, me, name)?;
            match kind.as_str() {
                "edit" => {
                    let who = a["actor"]["user"]["email"].as_str().unwrap_or_default().to_ascii_lowercase();
                    if last_editor.as_deref() == Some(who.as_str()) {
                        return None;
                    }
                    last_editor = Some(who);
                }
                "comment" | "commentResponse" => {}
                _ => last_editor = None,
            }
            let when = a["times"]["recordedTime"].as_str().or(a["times"]["recordedDateTime"].as_str()).or(a["activityDateTime"].as_str())?;
            let t = DateTime::parse_from_rfc3339(when).ok()?.with_timezone(&Local);
            let time = match a["@sharePoint.localizedRelativeTime"].as_str() {
                Some(code) if !code.is_empty() => friendly_display(code),
                _ => super::list_rows::friendly_at(t, now),
            };
            Some(FeedItem { kind, text, time, tip: tip(t, now), group: group(t, now), comment_id: String::new(), author: String::new(), author_email: String::new(), mine: false, source: String::new(), edited: false, replies: Vec::new(), at: t.timestamp() })
        })
        .collect()
}

/// A comment's text with its `@mention{n}` marks as the people's names
/// (OneDrive's `_formatMentionedComment`), HTML-escaped.
pub fn comment_text(c: &Value) -> String {
    esc(&comment_source(c))
}

fn comment_source(c: &Value) -> String {
    let text = c["text"].as_str().unwrap_or_default();
    let names: Vec<String> = c["mentions"]["results"]
        .as_array()
        .or_else(|| c["mentions"].as_array())
        .into_iter()
        .flatten()
        .map(|m| m["name"].as_str().unwrap_or_default().to_string())
        .collect();
    let mut out = String::new();
    let mut rest = text;
    while let Some(i) = rest.find("@mention{") {
        out.push_str(&rest[..i]);
        let after = &rest[i + 9..];
        match after.find('}').and_then(|j| after[..j].parse::<usize>().ok().map(|n| (j, n))) {
            Some((j, n)) if n < names.len() => {
                out.push_str(&names[n]);
                rest = &after[j + 1..];
            }
            _ => {
                out.push_str("@mention{");
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

fn id_of(v: &Value) -> String {
    v["id"].as_str().map(str::to_string).or(v["id"].as_i64().map(|n| n.to_string())).unwrap_or_default()
}

/// The item's comments as the pane's comment cards. A comment's time reads
/// as the files list words it ("A few seconds ago", "About a minute ago"),
/// a reply's in the client's wording ("Just now", "5m ago"); either is
/// "Edited" once `modifiedDate` is set.
pub fn comment_cards(reply: &Value, me: &str, now: DateTime<Local>) -> Vec<FeedItem> {
    let author = |c: &Value| {
        let email = c["author"]["email"].as_str().unwrap_or_default().to_string();
        let mine = !email.is_empty() && email.eq_ignore_ascii_case(me);
        let name = if mine { "You".to_string() } else { c["author"]["name"].as_str().unwrap_or("Someone").to_string() };
        (name, email, mine)
    };
    let edited = |c: &Value| c["modifiedDate"].as_str().is_some_and(|m| !m.is_empty());
    let when = |c: &Value| DateTime::parse_from_rfc3339(c["createdDate"].as_str()?).ok().map(|t| t.with_timezone(&Local));
    reply["d"]["results"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let t = when(c)?;
            let (name, email, mine) = author(c);
            let mut replies: Vec<(DateTime<Local>, Reply)> = c["replies"]["results"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|r| {
                    let rt = when(r)?;
                    let (name, email, mine) = author(r);
                    Some((rt, Reply { id: id_of(r), author: name, author_email: email, mine, text: comment_text(r), time: super::list_rows::activity_time(rt, now), edited: edited(r) }))
                })
                .collect();
            replies.sort_by_key(|(rt, _)| *rt);
            Some(FeedItem {
                kind: "comment".into(),
                text: comment_text(c),
                source: comment_source(c),
                time: super::list_rows::friendly_at(t, now),
                tip: tip(t, now),
                group: group(t, now),
                comment_id: id_of(c),
                author: name,
                author_email: email,
                mine,
                edited: edited(c),
                replies: replies.into_iter().map(|(_, r)| r).collect(),
                at: t.timestamp(),
            })
        })
        .collect()
}

/// The activity feed with the comment cards in place of comment
/// activities (replies show under their comment, so their activities go
/// too), newest first.
pub fn merge(mut acts: Vec<FeedItem>, comments: Vec<FeedItem>) -> Vec<FeedItem> {
    acts.retain(|a| a.kind != "comment" && a.kind != "commentResponse");
    acts.extend(comments);
    acts.sort_by(|a, b| b.at.cmp(&a.at));
    acts
}

fn comments_url(item: &DriveItem, tail: &str) -> String {
    let q = |s: &str| url::form_urlencoded::byte_serialize(format!("'{}'", s.trim_matches(|c| c == '{' || c == '}')).as_bytes()).collect::<String>();
    format!("{}/_api/web/lists(@a1)/GetItemByUniqueId(@a2)/{tail}?@a1={}&@a2={}", item.sp_site.trim_end_matches('/'), q(&item.sp_list), q(&item.sp_item))
}

/// Delete one of the item's comments.
pub async fn delete_comment(item: &DriveItem, id: &str) -> Result<()> {
    super::sharing::delete(&comments_url(item, &format!("Comments({})", check_id(id)?))).await
}

/// One activity as a folder's Details pane words it (about the items in it:
/// their names in bold). `to` is the destination folder of a move that the
/// next activity completes.
pub fn describe_in_folder(a: &Value, me: &str, to: Option<&str>) -> Option<(String, String)> {
    let act = &a["action"];
    let has = |k: &str| act.get(k).is_some();
    let actor = person(&a["actor"]["user"], me);
    let (you, who) = (actor.me, actor.name.as_str());
    let item = a["driveItem"]["name"].as_str().unwrap_or_default();
    let it = bold(item);
    // The folder the item is in (by its parent's path), "" for the top.
    let parent = a["driveItem"]["parentReference"]["path"].as_str().and_then(|p| p.split_once(':')).map(|(_, r)| r.rsplit('/').next().unwrap_or_default().to_string()).unwrap_or_default();
    let comment = &act["comment"];
    let (kind, text) = if has("mention") {
        ("mention", if you { fill("You mentioned someone in {0}", &[&it]) } else { fill("{1} mentioned you in {0}", &[&it, who]) })
    } else if comment.is_object() && !comment["isReply"].as_bool().unwrap_or(false) {
        ("comment", fill(if you { "You commented on {0}" } else { "{1} commented on {0}" }, &[&it, who]))
    } else if comment.is_object() {
        ("commentResponse", fill(if you { "You replied to a comment on {0}" } else { "{1} replied to a comment on {0}" }, &[&it, who]))
    } else if has("create") {
        let t = if parent.is_empty() { if you { "You created {0}" } else { "{1} created {0}" } } else if you { "You created {0} in {2}" } else { "{1} created {0} in {2}" };
        ("create", fill(t, &[&it, who, &bold(&parent)]))
    } else if has("delete") {
        let gone = bold(act["delete"]["name"].as_str().unwrap_or(item));
        // Deleted from a folder: the activity's item is that folder.
        let from = if a["driveItem"].is_object() { item.to_string() } else { String::new() };
        let t = if from.is_empty() { if you { "You deleted {0}" } else { "{1} deleted {0}" } } else if you { "You deleted {0} from {2}" } else { "{1} deleted {0} from {2}" };
        ("delete", fill(t, &[&gone, who, &bold(&from)]))
    } else if has("edit") {
        ("edit", fill(if you { "You edited {0}" } else { "{1} edited {0}" }, &[&it, who]))
    } else if has("move") {
        let m = &act["move"];
        let from = m["From"].as_str().or(m["from"].as_str()).map(|p| bold(&last(p, true)));
        let to = to.map(bold);
        let t = match (&from, &to) {
            (Some(_), Some(_)) => if you { "You moved {0} from {2} to {3}" } else { "{1} moved {0} from {2} to {3}" },
            (Some(_), None) => if you { "You moved {0} from {2}" } else { "{1} moved {0} from {2}" },
            _ => if you { "You moved {0}" } else { "{1} moved {0}" },
        };
        ("move", fill(t, &[&it, who, from.as_deref().unwrap_or_default(), to.as_deref().unwrap_or_default()]))
    } else if has("rename") {
        let old = act["rename"]["oldName"].as_str().unwrap_or_default();
        ("rename", fill(if you { "You renamed {1} to {2}" } else { "{0} renamed {1} to {2}" }, &[who, &bold(old), &it]))
    } else if has("restore") {
        ("restore", fill("{0} was restored", &[&it]))
    } else if has("share") {
        ("share", fill(if you { "You shared {0}" } else { "{1} shared {0}" }, &[&it, who]))
    } else if has("version") {
        let v = act["version"]["newVersion"].as_str().unwrap_or_default();
        ("version", fill(if you { "You created {2} of {0}" } else { "{1} created {2} of {0}" }, &[&it, who, v]))
    } else {
        return None;
    };
    Some((kind.to_string(), text))
}

/// A folder's activity as its Details pane lists it: a move's "from" and
/// its matching "to" read as one, and repeated edits of one item by one
/// person show once.
pub fn folder_feed(reply: &Value, me: &str, now: DateTime<Local>) -> Vec<FeedItem> {
    let acts: Vec<&Value> = reply["value"].as_array().into_iter().flatten().collect();
    let mut out: Vec<FeedItem> = Vec::new();
    let mut used = vec![false; acts.len()];
    let mut last_edit: Option<(String, String)> = None;
    for i in 0..acts.len() {
        if used[i] {
            continue;
        }
        let a = acts[i];
        let m = &a["action"]["move"];
        // A move's "to" half: folded into its "from" half.
        if m.is_object() && m.get("to").is_some() && m.get("From").is_none() && m.get("from").is_none() {
            continue;
        }
        let mut to = None;
        if let Some(from) = m["From"].as_str() {
            let file = last(from, false);
            let time = a["@sharePoint.localizedRelativeTime"].as_str();
            if let Some(j) = (0..acts.len()).find(|&j| !used[j] && j != i && acts[j]["action"]["move"]["to"].as_str().is_some_and(|t| last(t, false) == file) && acts[j]["@sharePoint.localizedRelativeTime"].as_str() == time) {
                used[j] = true;
                to = acts[j]["action"]["move"]["to"].as_str().map(|t| last(t, true));
            }
        }
        let Some((kind, text)) = describe_in_folder(a, me, to.as_deref()) else { continue };
        if kind == "edit" {
            let key = (a["driveItem"]["id"].as_str().unwrap_or_default().to_string(), a["actor"]["user"]["email"].as_str().unwrap_or_default().to_string());
            if last_edit.as_ref() == Some(&key) {
                continue;
            }
            last_edit = Some(key);
        } else {
            last_edit = None;
        }
        let Some(when) = a["times"]["recordedTime"].as_str() else { continue };
        let Ok(t) = DateTime::parse_from_rfc3339(when) else { continue };
        let t = t.with_timezone(&Local);
        let time = match a["@sharePoint.localizedRelativeTime"].as_str() {
            Some(code) if !code.is_empty() => friendly_display(code),
            _ => super::list_rows::friendly_at(t, now),
        };
        out.push(FeedItem { kind, text, time, tip: tip(t, now), group: group(t, now), comment_id: String::new(), author: String::new(), author_email: String::new(), mine: false, source: String::new(), edited: false, replies: Vec::new(), at: t.timestamp() });
    }
    out
}

/// The current folder's activity (the Details pane with nothing selected).
/// `item_id` empty is the drive's top.
pub async fn folder_activity(host: &str, drive_id: &str, item_id: &str, me: &str) -> Result<Vec<FeedItem>> {
    let ok = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"!-_.".contains(&b));
    if !host.starts_with("https://") || !ok(drive_id) || !(item_id.is_empty() || ok(item_id)) {
        bail!("No activity for this folder");
    }
    let target = if item_id.is_empty() { "root".to_string() } else { format!("items/{item_id}") };
    let url = format!("{host}/_api/v2.0/drives/{drive_id}/{target}/activities?%24expand=driveItem(%24select%3Did%2Cname%2CwebUrl%2CparentReference%2Cfile%2Cfolder)&%24top=25");
    let reply = get_with(&url, &[("user-agent", super::client::TEAMS_WEB_UA), ("accept", "application/json")]).await?;
    Ok(folder_feed(&reply, me, Local::now()))
}

/// `https://host` of an address.
fn host(url: &str) -> String {
    url.split('/').take(3).collect::<Vec<_>>().join("/")
}

/// Everything the pane needs for one item (besides its sharing, which comes
/// from the share dialog's call).
pub async fn load(item: &DriveItem, me: &str) -> Result<Details> {
    let h = host(&item.sp_site);
    if !h.starts_with("https://") || item.drive_id.is_empty() || item.id.is_empty() {
        bail!("No details for this item");
    }
    let base2 = format!("{h}/_api/v2.0/drives/{}/items/{}", item.drive_id, item.id);
    let base21 = format!("{h}/_api/v2.1/drives/{}/items/{}", item.drive_id, item.id);
    let acts_url = format!("{base2}/activities?%24expand=driveItem(%24select%3Did%2Cname%2CwebUrl%2CparentReference%2Cfile%2Cfolder)&%24top=25");
    let prefs_url = format!("{base21}/?%24expand=notificationPreferences");
    let ua = [("user-agent", super::client::TEAMS_WEB_UA), ("accept", "application/json")];
    // As Teams asks: with each comment's replies and likes.
    let comments = comments_url(item, "GetComments()") + "&$top=25&$expand=replies,likedBy,replies/likedBy";
    let disabled_url = comments_url(item, "CommentsDisabled");
    let (acts, prefs, comments, disabled) = tokio::join!(
        get_with(&acts_url, &ua),
        get_with(&prefs_url, &ua),
        get_with(&comments, &[]),
        get_with(&disabled_url, &[])
    );
    let now = Local::now();
    let prefs = prefs.unwrap_or_default();
    let p = prefs["notificationPreferences"].as_array().cloned().unwrap_or_default();
    let local = |s: &str| DateTime::parse_from_rfc3339(s).ok().map(|t| t.with_timezone(&Local));
    let created = prefs["createdDateTime"].as_str().and_then(local);
    let modified = local(&item.modified);
    // The path from the library's top: "My files" for your OneDrive.
    let parent = prefs["parentReference"]["path"].as_str().unwrap_or_default();
    let mut path = vec![if h.contains("-my.sharepoint.com") { "My files".to_string() } else { "Documents".to_string() }];
    path.extend(parent.split_once("root:").map(|(_, p)| p).unwrap_or_default().split('/').filter(|s| !s.is_empty()).map(|s| s.to_string()));
    path.push(item.name.clone());
    Ok(Details {
        activities: merge(
            acts.map(|a| feed(&a, me, &item.name, now)).unwrap_or_default(),
            comments.map(|c| comment_cards(&c, me, now)).unwrap_or_default(),
        ),
        // SharePoint leaves the preferences out of some replies to OST's
        // token; then the bell keeps its default (on).
        notify: prefs.get("notificationPreferences").is_none() || p.iter().all(|x| x["name"].as_str() != Some("None")),
        created: created.map(|t| t.format("%m/%d/%Y %I:%M %p").to_string()).unwrap_or_default(),
        modified: modified.map(|t| t.format("%-m/%-d/%Y %-I:%M %p").to_string()).unwrap_or_default(),
        type_text: if item.is_folder { "Folder".into() } else { format!("{} File", item.kind) },
        path,
        comments_disabled: disabled.ok().and_then(|v| v["d"]["CommentsDisabled"].as_bool()).unwrap_or(false),
    })
}

/// The bell: notifications for the item's activity on ("Comments") or off
/// ("None"), as OneDrive's pane sets it.
pub async fn set_notify(item: &DriveItem, file_url: &str, on: bool) -> Result<()> {
    let site = item.sp_site.trim_end_matches('/');
    let rel = file_url.strip_prefix(&format!("{site}/")).unwrap_or_default();
    let (folder, name) = rel.rsplit_once('/').unwrap_or(("", rel));
    // SharePoint refuses the change without the site's and web's ids.
    let (site_url, web_url) = (format!("{site}/_api/site/id"), format!("{site}/_api/web/id"));
    let (site_id, web_id) = tokio::join!(get_with(&site_url, &[]), get_with(&web_url, &[]));
    let id = |v: Result<Value>| v.ok().and_then(|v| v["d"]["Id"].as_str().map(str::to_string)).unwrap_or_default();
    let ids = (id(site_id), id(web_id));
    let inner = json!({
        "Scenario": "NotificationPreference",
        "NotificationPreference": if on { "Comments" } else { "None" },
        "ClientUTCOffsetInMinutes": -Local::now().offset().local_minus_utc() / 60,
        "ClientApplication": "ODBWeb", "ClientVersion": "1", "Workload": "ODB", "Canvas": "DetailsPane",
        "SiteId": ids.0, "WebId": ids.1,
        "SiteUrl": site, "SourceRelativeUrl": folder, "SourceFileExtension": item.kind, "SourceFileName": name,
    });
    post(&format!("{site}/_api/web/ActivityLogger/FeedbackDirect"), &json!({
        "ListId": item.sp_list.trim_matches(|c| c == '{' || c == '}'),
        "ListItemUniqueId": item.sp_item.trim_matches(|c| c == '{' || c == '}').to_ascii_uppercase(),
        "Operation": "NotificationPreferenceChanged",
        "AffectedResourceUrl": file_url,
        "ItemType": if item.is_folder { "Folder" } else { "File" },
        "json": inner.to_string(),
    })).await?;
    Ok(())
}

/// Add a comment to the item (OneDrive's comment box: at most 2000
/// characters).
pub async fn add_comment(item: &DriveItem, text: &str) -> Result<()> {
    let text = check_text(text)?;
    post(
        &comments_url(item, "Comments()"),
        &json!({ "__metadata": { "type": "Microsoft.SharePoint.Comments.comment" }, "text": text }),
    )
    .await?;
    Ok(())
}

fn check_text(text: &str) -> Result<&str> {
    let text = text.trim();
    if text.is_empty() || text.chars().count() > 2000 {
        bail!("Maximum character limit exceeded");
    }
    Ok(text)
}

fn check_id(id: &str) -> Result<&str> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
        bail!("Not a comment id");
    }
    Ok(id)
}

/// Edit comment: `PATCH …/Comments({id})` with the new text (and no
/// mentions, as Teams' box sends), 204.
pub async fn edit_comment(item: &DriveItem, id: &str, text: &str) -> Result<()> {
    super::sharing::send_with(
        reqwest::Method::PATCH,
        &comments_url(item, &format!("Comments({})", check_id(id)?)),
        &json!({ "mentions": [], "text": check_text(text)? }),
        &[("content-type", "application/json;charset=UTF-8"), ("accept", "application/json")],
    )
    .await?;
    Ok(())
}

/// The Reply box: `POST …/Comments({id})/replies` with `{"text":…}`, 201.
pub async fn add_reply(item: &DriveItem, id: &str, text: &str) -> Result<()> {
    super::sharing::post_with(
        &comments_url(item, &format!("Comments({})/replies", check_id(id)?)),
        &json!({ "text": check_text(text)? }),
        &[("content-type", "application/json;charset=UTF-8"), ("accept", "application/json")],
    )
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn me() -> &'static str { "ost-test1@x.com" }
    fn you() -> Value { json!({"user": {"email": "ost-test1@x.com", "displayName": "OST Test 1", "self": {}}}) }

    #[test]
    fn activities_read_as_the_pane() {
        // From ost-share-test.txt's feed on 2026-11-12.
        let a = |action: Value| json!({"action": action, "actor": you(), "times": {"recordedTime": "2026-11-12T16:48:26Z"}});
        let d = |action: Value| describe(&a(action), me(), "ost-share-test.txt").unwrap();
        assert_eq!(d(json!({"edit": {}, "restoreVersion": {"fromVersion": "2.0"}, "version": {"newVersion": "4.0"}})), ("edit".into(), "You edited this file".into()));
        assert_eq!(d(json!({"move": {"From": "personal/a/Documents/Attachments/ost-share-test.txt"}})).1, "You moved this file from <b>Attachments</b>");
        assert_eq!(d(json!({"move": {"From": "personal/a/Documents/ost-share-test.txt"}})).1, "You moved this file from <b>Documents</b>");
        assert_eq!(d(json!({"share": {}})).1, "You shared this file");
        assert_eq!(d(json!({"share": {"recipients": [{"user": {"displayName": "OST Test 2", "email": "t2@x"}}]}})).1, "You shared this file with OST Test 2");
        assert_eq!(d(json!({"rename": {"oldName": "ost-share-test-ost.txt"}})).1, "You renamed <b>ost-share-test-ost.txt</b> to <b>ost-share-test.txt</b>");
        assert_eq!(d(json!({"create": {}})).1, "You created this file");
        let other = json!({"action": {"edit": {}}, "actor": {"user": {"email": "r@x", "displayName": "Randy Northrup"}}});
        assert_eq!(describe(&other, me(), "x").unwrap().1, "Randy Northrup edited this file");
        let to_me = json!({"action": {"share": {"recipients": [{"user": {"email": "OST-Test1@x.com", "displayName": "OST Test 1"}}]}}, "actor": {"user": {"email": "r@x", "displayName": "Randy Northrup"}}});
        assert_eq!(describe(&to_me, me(), "x").unwrap().1, "Randy Northrup shared this file with you");
        assert!(describe(&json!({"action": {"unknown": {}}}), me(), "x").is_none());
    }

    #[test]
    fn groups_follow_onedrive() {
        let at = |m: u32, d: u32, h: u32| Local.with_ymd_and_hms(2026, m, d, h, 0, 0).unwrap();
        let now = at(11, 12, 9); // a Thursday
        assert_eq!(group(at(11, 12, 8), now), "Today");
        assert_eq!(group(at(11, 11, 22), now), "Yesterday");
        assert_eq!(group(at(11, 8, 15), now), "This week");
        assert_eq!(group(at(11, 5, 15), now), "Last week");
        assert_eq!(group(at(10, 30, 15), now), "Two weeks ago");
        assert_eq!(group(at(10, 25, 15), now), "Three weeks ago");
        assert_eq!(group(at(10, 3, 15), now), "Last month");
        assert_eq!(group(at(3, 3, 15), now), "March");
        assert_eq!(group(Local.with_ymd_and_hms(2025, 3, 3, 1, 0, 0).unwrap(), now), "March 2025");
        assert_eq!(tip(at(11, 12, 8), now), "Nov 12 at 8:00 AM");
    }

    #[test]
    fn comments_become_cards_in_place_of_their_activities() {
        let now = Local::now();
        let reply = json!({"d": {"results": [{"author": {"email": "ost-test1@x.com", "name": "OST Test 1"}, "createdDate": (now - Duration::seconds(30)).to_rfc3339(), "id": "1", "text": "OST test 111 <b>"}]}});
        let cards = comment_cards(&reply, me(), now);
        assert_eq!((cards[0].author.as_str(), cards[0].text.as_str(), cards[0].time.as_str(), cards[0].comment_id.as_str()), ("You", "OST test 111 &lt;b&gt;", "A few seconds ago", "1"));
        let mut act = feed(&json!({"value": [{"action": {"comment": {}}, "actor": you(), "times": {"recordedTime": now.to_rfc3339()}},
            {"action": {"comment": {"isReply": true}}, "actor": you(), "times": {"recordedTime": now.to_rfc3339()}},
            {"action": {"edit": {}}, "actor": you(), "times": {"recordedTime": (now - Duration::hours(1)).to_rfc3339()}}]}), me(), "x", now);
        assert_eq!(act.iter().map(|a| a.kind.as_str()).collect::<Vec<_>>(), ["comment", "commentResponse", "edit"]);
        // Two edits in a row by one person read as one; a move between them
        // keeps both.
        let e = |h: i64| json!({"action": {"edit": {}}, "actor": you(), "times": {"recordedTime": (now - Duration::hours(h)).to_rfc3339()}});
        let mv = json!({"action": {"move": {"From": "personal/a/Documents/x.txt"}}, "actor": you(), "times": {"recordedTime": (now - Duration::hours(4)).to_rfc3339()}});
        let kinds = |v: Value| feed(&v, me(), "x", now).iter().map(|a| a.kind.clone()).collect::<Vec<_>>();
        assert_eq!(kinds(json!({"value": [e(1), e(2), mv.clone(), e(5)]})), ["edit", "move", "edit"]);
        act = merge(act, cards);
        assert_eq!(act.iter().map(|a| a.kind.as_str()).collect::<Vec<_>>(), ["comment", "edit"]);
        assert_eq!(act[0].comment_id, "1");
    }

    #[test]
    fn comments_carry_replies_edits_and_mention_names() {
        // ost-share-test.txt's comment 3 on 2026-11-12 (Teams' $expand=replies).
        let now = Local::now();
        let t = |s: i64| (now - Duration::seconds(s)).to_rfc3339();
        let reply = json!({"d": {"results": [{
            "author": {"email": "ost-test1@x.com", "name": "OST Test 1"}, "createdDate": t(90), "modifiedDate": t(10), "id": "3",
            "text": "OST comment test 1 edited", "mentions": {"results": []},
            "replies": {"results": [
                {"author": {"email": "t2@x.com", "name": "OST Test 2"}, "createdDate": t(20), "modifiedDate": null, "id": "5",
                 "text": "thanks @mention{0}", "mentions": {"results": [{"name": "OST Test 1", "email": "ost-test1@x.com"}]}},
                {"author": {"email": "ost-test1@x.com", "name": "OST Test 1"}, "createdDate": t(40), "modifiedDate": null, "id": "4", "text": "OST reply test 1"}
            ]}
        }]}});
        let c = &comment_cards(&reply, me(), now)[0];
        assert!(c.edited);
        assert_eq!(c.time, "About a minute ago");
        assert_eq!(c.replies.iter().map(|r| (r.id.as_str(), r.author.as_str(), r.text.as_str(), r.time.as_str())).collect::<Vec<_>>(),
            [("4", "You", "OST reply test 1", "Just now"), ("5", "OST Test 2", "thanks OST Test 1", "Just now")]);
        assert_eq!(comment_text(&json!({"text": "@mention{3} hi", "mentions": []})), "@mention{3} hi");
    }

    #[test]
    fn folder_feed_reads_as_teams() {
        // My files' activity on 2026-11-12, cut down: Teams lists "You
        // commented on …", one edit, and the move pairs as one.
        let root = "/drives/b!x/root:";
        let item = |n: &str| json!({"id": n, "name": n, "parentReference": {"path": root}});
        let a = |action: Value, it: Value, code: &str| json!({"@sharePoint.localizedRelativeTime": code, "action": action, "actor": you(), "times": {"recordedTime": "2026-11-12T16:00:00Z"}, "driveItem": it});
        let reply = json!({"value": [
            a(json!({"comment": {"commentId": "2", "isReply": false}}), item("ost-share-test.txt"), "1|0|4"),
            a(json!({"edit": {}, "version": {"newVersion": "5.0"}}), item("ost-share-test.txt"), "1|0|4"),
            a(json!({"edit": {}, "version": {"newVersion": "4.0"}}), item("ost-share-test.txt"), "1|0|4"),
            a(json!({"move": {"From": "personal/a/Documents/Attachments/ost-share-test.txt"}}), item("ost-share-test.txt"), "1|0|6|3"),
            a(json!({"move": {"to": "personal/a/Documents/ost-share-test.txt"}}), item("Attachments"), "1|0|6|3"),
            json!({"@sharePoint.localizedRelativeTime": "1|0|6|3", "action": {"delete": {"name": "ost-share-test Copy.txt"}}, "actor": you(), "times": {"recordedTime": "2026-11-12T16:00:00Z"}}),
            a(json!({"delete": {"name": "ost-share-test.txt"}}), item("Attachments"), "1|0|5|10:28 PM"),
            a(json!({"create": {}}), item("ost-open-test.docx"), "1|0|5|10:46 PM"),
        ]});
        let f: Vec<String> = folder_feed(&reply, me(), Local::now()).into_iter().map(|i| i.text).collect();
        assert_eq!(f, [
            "You commented on <b>ost-share-test.txt</b>",
            "You edited <b>ost-share-test.txt</b>",
            "You moved <b>ost-share-test.txt</b> from <b>Attachments</b> to <b>Documents</b>",
            "You deleted <b>ost-share-test Copy.txt</b>",
            "You deleted <b>ost-share-test.txt</b> from <b>Attachments</b>",
            "You created <b>ost-open-test.docx</b>",
        ]);
    }

    #[test]
    fn feed_uses_sharepoints_wording_for_times() {
        let reply = json!({"value": [{"@sharePoint.localizedRelativeTime": "1|0|5|10:37 PM", "action": {"share": {}}, "actor": you(), "times": {"recordedTime": "2026-11-12T06:37:00Z"}}]});
        let f = feed(&reply, me(), "x", Local::now());
        assert_eq!((f[0].kind.as_str(), f[0].time.as_str()), ("share", "Yesterday at 10:37 PM"));
    }
}
