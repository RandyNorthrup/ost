//! The columns Teams' OneDrive app reads from SharePoint rather than Graph
//! (docs/spec/onedrive-rows.md): its friendly Modified text, the
//! Activity column, the Sharing column's count and the "new" mark. Teams'
//! file list gets them from the folder's `RenderListDataAsStream` rows
//! (`Modified.FriendlyDisplay`, `_activity`, `PrincipalCount`,
//! `Created_x0020_Date.ifnew`); OST asks for the same rows and joins them to
//! Graph's items by their list item's unique id.

use std::collections::HashMap;

use anyhow::Result;
use chrono::{DateTime, Datelike, Duration, Local, NaiveDate, TimeZone};
use serde::Serialize;
use serde_json::{Value, json};

/// What one row adds to Graph's item.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct RowInfo {
    /// The Modified column ("Yesterday at 10:28 PM", "6 days ago").
    pub modified_text: String,
    /// Its tooltip, the full date ("11/11/2026 10:28 PM").
    pub modified_title: String,
    /// People with access (Sharing reads "Shared" when there are any).
    pub principal_count: u32,
    /// Created lately: the name gets OneDrive's "New" mark.
    pub is_new: bool,
    pub activity: Option<Activity>,
    /// A folder's colour (OneDrive's code "0"–"15"; empty is yellow).
    pub color: String,
}

/// The Activity column: the latest thing done to the file.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Activity {
    /// edit, comment, commentResponse, share, mention, createTask, completeTask.
    pub kind: String,
    /// "You shared this file", "Randy Northrup edited".
    pub text: String,
    /// ISO time of it.
    pub time: String,
}

// OneDrive's English strings (file-browser-odb-teams initial.resx, 2026-10-30).
const THIS_FILE: &str = "this file";
const COMMENT: &str = "comment";

/// "{0} other||{0} others" for n people.
fn others(n: usize) -> String {
    if n == 1 { "1 other".into() } else { format!("{n} others") }
}

fn fill(template: &str, args: &[&str]) -> String {
    let mut out = template.to_string();
    for (i, a) in args.iter().enumerate() {
        out = out.replace(&format!("{{{i}}}"), a);
    }
    out
}

/// Plural pick for "{0} x ago||{0} xs ago" with intervals "1||2-".
fn plural(n: i64, one: &str, many: &str) -> String {
    fill(if n == 1 { one } else { many }, &[&n.to_string()])
}

/// OneDrive's file size wording: "1 byte", "56 bytes", "26.0 KB", "7.66 MB"
/// (two decimals under 10, one under 100, none above).
pub fn size_text(n: f64) -> String {
    let f = |v: f64| {
        if v >= 100.0 || v == v.floor() { format!("{v:.0}") } else if v >= 10.0 { format!("{v:.1}") } else { format!("{v:.2}") }
    };
    match n {
        n if n == 1.0 => "1 byte".into(),
        n if n < 1024.0 => format!("{n:.0} bytes"),
        n if n < 1024e3 => format!("{} KB", f(n / 1024.0)),
        n if n < 1048576e3 => format!("{} MB", f(n / 1048576.0)),
        n if n < 1073741824e3 => format!("{} GB", f(n / 1073741824.0)),
        n => format!("{} TB", f(n / 1099511627776.0)),
    }
}

/// SharePoint's `Modified.FriendlyDisplay` as OneDrive's list words it
/// ("1|0|5|10:28 PM" is "Yesterday at 10:28 PM"; "0|November 5" is as is).
pub fn friendly_display(code: &str) -> String {
    let a: Vec<&str> = code.split('|').collect();
    if a.first() == Some(&"0") {
        return code.get(2..).unwrap_or_default().to_string();
    }
    let future = a.get(1) == Some(&"1");
    let c = a.get(3).copied().unwrap_or_default();
    let d = a.get(4).copied().unwrap_or_default();
    let n: i64 = c.parse().unwrap_or(0);
    match a.get(2).copied().unwrap_or_default() {
        "1" => if future { "In a few seconds" } else { "A few seconds ago" }.into(),
        "2" => if future { "In about a minute" } else { "About a minute ago" }.into(),
        "3" if future => plural(n, "In {0} minute", "In {0} minutes"),
        "3" => plural(n, "{0} minute ago", "{0} minutes ago"),
        "4" => if future { "In about an hour" } else { "About an hour ago" }.into(),
        "5" if c.is_empty() => if future { "Tomorrow" } else { "Yesterday" }.into(),
        "5" => format!("{} at {c}", if future { "Tomorrow" } else { "Yesterday" }),
        "6" if future => plural(n, "In {0} hour", "In {0} hours"),
        "6" => plural(n, "{0} hour ago", "{0} hours ago"),
        "7" if !d.is_empty() => format!("{c} at {d}"),
        "7" => c.to_string(),
        "8" if future => plural(n, "{0} day from now", "{0} days from now"),
        "8" => plural(n, "{0} day ago", "{0} days ago"),
        "9" => "Today".into(),
        _ => String::new(),
    }
}

fn time_of(t: &DateTime<Local>) -> String {
    t.format("%-I:%M %p").to_string()
}

/// The same wording from a time, for rows SharePoint didn't word (as its
/// server does: this week by weekday, then days, then the date).
pub fn friendly_at(t: DateTime<Local>, now: DateTime<Local>) -> String {
    let secs = (now - t).num_seconds();
    let (day, today) = (t.date_naive(), now.date_naive());
    if secs < -300 {
        return date_words(day, today);
    }
    let days = (today - day).num_days();
    match secs {
        s if s < 60 => "A few seconds ago".into(),
        s if s < 120 => "About a minute ago".into(),
        s if s < 3600 => plural(s / 60, "{0} minute ago", "{0} minutes ago"),
        s if s < 7200 => "About an hour ago".into(),
        s if days == 0 => plural(s / 3600, "{0} hour ago", "{0} hours ago"),
        _ if days == 1 => format!("Yesterday at {}", time_of(&t)),
        // Since Sunday: the weekday.
        _ if days < i64::from(today.weekday().num_days_from_sunday()) + 1 => {
            format!("{} at {}", t.format("%A"), time_of(&t))
        }
        _ if days < 7 => plural(days, "{0} day ago", "{0} days ago"),
        _ => date_words(day, today),
    }
}

fn date_words(day: NaiveDate, today: NaiveDate) -> String {
    if day.year() == today.year() {
        day.format("%B %-d").to_string()
    } else {
        day.format("%B %-d, %Y").to_string()
    }
}

/// The Activity column's time ("Yesterday at 10:37 PM", "Sun at 3:41 PM",
/// "Nov 5"): OneDrive's client wording.
pub fn activity_time(t: DateTime<Local>, now: DateTime<Local>) -> String {
    let ms = (now - t).num_milliseconds();
    let (day, today) = (t.date_naive(), now.date_naive());
    let short = |d: NaiveDate| {
        if d.year() == today.year() { d.format("%b %-d").to_string() } else { d.format("%b %-d, %Y").to_string() }
    };
    if ms < -300_000 {
        return t.format("%b %-d").to_string();
    }
    if ms < 120_000 {
        return "Just now".into();
    }
    if ms < 3_600_000 {
        return format!("{}m ago", (ms as f64 / 60_000.0).round() as i64);
    }
    if day == today {
        return format!("{}h ago", (ms as f64 / 3_600_000.0).round() as i64);
    }
    if day >= today - Duration::days(1) {
        return format!("Yesterday at {}", time_of(&t));
    }
    if day >= today - Duration::days(6) {
        return format!("{} at {}", t.format("%a"), time_of(&t));
    }
    short(day)
}

struct Who {
    name: String,
    me: bool,
}

/// OneDrive's `_activity` field as its Activity column words it. `me` is
/// the signed-in user's sign-in name.
pub fn activity(raw: &str, me: &str) -> Option<Activity> {
    let v: Value = serde_json::from_str(raw).ok()?;
    let kind = match v["FileActivityType"].as_str().and_then(|t| t.parse::<u32>().ok()).or(v["FileActivityType"].as_u64().map(|n| n as u32))? {
        4 | 5 | 16 => "edit",
        6 | 7 => "comment",
        8 | 13 | 15 => "commentResponse",
        9 => "share",
        11 | 12 => "mention",
        28 | 29 | 31 => "createTask",
        30 => "completeTask",
        _ => return None,
    };
    let mut users: Vec<Who> = v["FileActivityUsersOnPage"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|u| {
            let id = u["Id"].as_str().unwrap_or_default();
            Who {
                name: [u["DisplayName"].as_str(), Some(id)].into_iter().flatten().find(|s| !s.is_empty()).unwrap_or_default().to_string(),
                me: !id.is_empty() && id.eq_ignore_ascii_case(me),
            }
        })
        .collect();
    // Mentions, shares and tasks: the first is who did it, the rest are
    // the people it was for.
    let recipients: Vec<Who> = if matches!(kind, "mention" | "share" | "createTask") && users.len() > 1 {
        users.split_off(1)
    } else {
        Vec::new()
    };
    // You first, then the others (OneDrive's _getFilteredActors).
    let sorted = |list: &[Who]| -> (bool, Vec<String>) {
        let you = list.iter().any(|w| w.me);
        let mut names: Vec<String> = list.iter().filter(|w| w.me).take(1).map(|_| "you".to_string()).collect();
        names.extend(list.iter().filter(|w| !w.me).map(|w| w.name.clone()));
        (you, names)
    };
    let render = |names: &[String], cap: bool| names.first().cloned().unwrap_or_else(|| if cap { "Someone" } else { "someone" }.into());
    let (you, actors) = sorted(&users);
    let first = render(&actors, true);
    let text = match kind {
        "edit" => if you { "You edited".into() } else { fill("{0} edited", &[&first]) },
        "comment" if actors.len() > 1 => {
            fill(if you { "You + {0} commented" } else { "{0} + {1} commented" }, &[&first, &others(actors.len() - 1)])
        }
        "comment" => if you { "You commented".into() } else { fill("{0} commented", &[&first]) },
        "commentResponse" if actors.len() > 1 => fill(
            if you { "You + {2} replied to a {0}" } else { "{1} + {2} replied to a {0}" },
            &[COMMENT, &first, &others(actors.len() - 1)],
        ),
        "commentResponse" => fill(if you { "You replied to a {0}" } else { "{1} replied to a {0}" }, &[COMMENT, &first]),
        "share" if recipients.is_empty() => {
            fill("{1} shared {0}", &[THIS_FILE, if you { "You" } else { &first }])
        }
        "share" => {
            let (to_you, to) = sorted(&recipients);
            let them = render(&to, false);
            if to.len() > 1 {
                fill(if you { "You shared with {1} + {2}" } else { "{0} shared with {1} + {2}" }, &[&first, &them, &others(to.len() - 1)])
            } else {
                let t = match (to_you, you) {
                    (true, true) => "You shared with yourself",
                    (true, false) => "{0} shared with you",
                    (false, true) => "You shared with {1}",
                    (false, false) => "{0} shared with {1}",
                };
                fill(t, &[&first, &them])
            }
        }
        "mention" => {
            let (to_you, to) = sorted(&recipients);
            let them = render(&to, false);
            if to.len() > 1 {
                fill(if you { "You mentioned {1} + {2}" } else { "{0} mentioned {1} + {2}" }, &[&first, &them, &others(to.len() - 1)])
            } else {
                let t = match (to_you, you) {
                    (true, true) => "You mentioned yourself",
                    (true, false) => "{0} mentioned you",
                    (false, true) => "You mentioned {1}",
                    (false, false) => "{0} mentioned {1}",
                };
                fill(t, &[&first, &them])
            }
        }
        "createTask" if !recipients.is_empty() => {
            let (_, to) = sorted(&recipients);
            fill(if you { "You created a task for {1}" } else { "{0} created a task for {1}" }, &[&first, &render(&to, false)])
        }
        "createTask" => fill("{0} created a task", &[&render(&actors, false)]),
        _ => if you { "You completed the task".into() } else { fill("{0} completed the task", &[&first]) },
    };
    Some(Activity { kind: kind.into(), text, time: v["FileActivityTimeStamp"].as_str().unwrap_or_default().to_string() })
}

/// One `RenderListDataAsStream` row, keyed by its unique id (lowercase,
/// without braces, as Graph's `sharepointIds.listItemUniqueId`).
pub fn parse_row(row: &Value, me: &str, now: DateTime<Local>) -> Option<(String, RowInfo)> {
    let id = row["UniqueId"].as_str()?.trim_matches(|c| c == '{' || c == '}').to_ascii_lowercase();
    let s = |k: &str| row[k].as_str().unwrap_or_default();
    let modified_text = match s("Modified.FriendlyDisplay") {
        "" => DateTime::parse_from_rfc3339(s("Modified."))
            .map(|t| friendly_at(Local.from_utc_datetime(&t.naive_utc()), now))
            .unwrap_or_default(),
        code => friendly_display(code),
    };
    Some((
        id,
        RowInfo {
            modified_text,
            modified_title: s("Modified").to_string(),
            principal_count: s("PrincipalCount").parse().unwrap_or(0),
            is_new: s("Created_x0020_Date.ifnew") == "1",
            color: s("_ColorHex").to_string(),
            activity: match s("_activity") {
                "" => None,
                raw => activity(raw, me),
            },
        },
    ))
}

/// Teams' file list asks with a browser's User-Agent; SharePoint words
/// `FriendlyDisplay` only for browsers.
const VIEW_XML: &str = r#"<View><ViewFields><FieldRef Name="UniqueId"/><FieldRef Name="Modified"/><FieldRef Name="Created_x0020_Date"/><FieldRef Name="_activity"/><FieldRef Name="PrincipalCount"/><FieldRef Name="_ColorHex"/></ViewFields><RowLimit Paged="TRUE">500</RowLimit></View>"#;

/// The rows of a library folder (`folder` is its server-relative path; empty
/// for the library's top).
pub async fn folder(site: &str, list: &str, folder: &str, me: &str) -> Result<HashMap<String, RowInfo>> {
    let list = list.trim_matches(|c| c == '{' || c == '}');
    if list.is_empty() || !list.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        anyhow::bail!("Not a list id");
    }
    let mut params = json!({
        "__metadata": { "type": "SP.RenderListDataParameters" },
        "RenderOptions": 2,
        "ViewXml": VIEW_XML,
    });
    if !folder.is_empty() {
        params["FolderServerRelativeUrl"] = json!(folder);
    }
    let url = format!("{}/_api/web/lists(guid'{list}')/RenderListDataAsStream", site.trim_end_matches('/'));
    let reply = super::sharing::post_with(&url, &json!({ "parameters": params }), &[("user-agent", super::client::TEAMS_WEB_UA)]).await?;
    let now = Local::now();
    Ok(reply["Row"].as_array().into_iter().flatten().filter_map(|r| parse_row(r, me, now)).collect())
}

/// The rows of a OneDrive app folder (the drive's top when `item_id` is
/// empty), as Graph addresses it.
pub async fn for_folder(client: &super::client::TeamsClient, drive_id: &str, item_id: &str) -> Result<HashMap<String, RowInfo>> {
    let (here, path) = if item_id.is_empty() {
        (super::drive::root(client, drive_id).await?, String::new())
    } else {
        let f = super::drive::item(client, drive_id, item_id).await?;
        let p = server_path(&f.web_url);
        (f, p)
    };
    let me = client.user_principal_name().unwrap_or_default();
    folder(&here.sp_site, &here.sp_list, &path, &me).await
}

/// A drive item as the OneDrive app's table shows it: Graph's fields plus
/// the row's Modified wording, tooltip, Sharing, "new" mark and Activity
/// (SharePoint's where it has them, else worded here from Graph's time).
pub fn decorate(item: &super::drive::DriveItem, row: Option<&RowInfo>, now: DateTime<Local>) -> Value {
    let mut v = serde_json::to_value(item).unwrap_or_default();
    let t = DateTime::parse_from_rfc3339(&item.modified).ok().map(|t| t.with_timezone(&Local));
    v["modified_text"] = json!(match row {
        Some(r) if !r.modified_text.is_empty() => r.modified_text.clone(),
        _ => t.map(|t| friendly_at(t, now)).unwrap_or_default(),
    });
    v["modified_title"] = json!(match row {
        Some(r) if !r.modified_title.is_empty() => r.modified_title.clone(),
        _ => t.map(|t| t.format("%-m/%-d/%Y %-I:%M %p").to_string()).unwrap_or_default(),
    });
    if let Some(r) = row {
        v["sharing"] = json!(if r.principal_count > 0 { "Shared" } else { "Private" });
        v["is_new"] = json!(r.is_new);
        v["folder_color"] = json!(r.color);
        if let Some(a) = &r.activity {
            let when = DateTime::parse_from_rfc3339(&a.time).ok().map(|t| activity_time(t.with_timezone(&Local), now));
            v["activity"] = json!({ "kind": a.kind, "text": a.text, "time": when.unwrap_or_default() });
        }
    }
    v
}

/// A folder's server-relative path from its web address.
pub fn server_path(web_url: &str) -> String {
    let rest = web_url.splitn(4, '/').nth(3).unwrap_or_default();
    super::copy_jobs::folder_url(&format!("/{rest}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(y: i32, mo: u32, d: u32, h: u32, mi: u32) -> DateTime<Local> {
        Local.with_ymd_and_hms(y, mo, d, h, mi, 0).unwrap()
    }

    #[test]
    fn sizes_read_as_onedrive() {
        assert_eq!(size_text(1.0), "1 byte");
        assert_eq!(size_text(56.0), "56 bytes");
        assert_eq!(size_text(26.02 * 1024.0), "26.0 KB");
        assert_eq!(size_text(26.0 * 1024.0), "26 KB");
        assert_eq!(size_text(82.7 * 1024.0), "82.7 KB");
        assert_eq!(size_text(7.66 * 1048576.0), "7.66 MB");
        assert_eq!(size_text(37.5 * 1048576.0), "37.5 MB");
        assert_eq!(size_text(150.0 * 1048576.0), "150 MB");
    }

    #[test]
    fn friendly_codes_read_as_teams() {
        // Seen in OST Test 1's My files on Thursday 2026-11-12.
        assert_eq!(friendly_display("1|0|5|10:28 PM"), "Yesterday at 10:28 PM");
        assert_eq!(friendly_display("1|0|7|Sunday|3:41 PM"), "Sunday at 3:41 PM");
        assert_eq!(friendly_display("1|0|8|6"), "6 days ago");
        assert_eq!(friendly_display("0|November 5"), "November 5");
        assert_eq!(friendly_display("1|0|3|1"), "1 minute ago");
        assert_eq!(friendly_display("1|0|6|5"), "5 hours ago");
        assert_eq!(friendly_display("1|0|1"), "A few seconds ago");
        assert_eq!(friendly_display("1|1|8|2"), "2 days from now");
    }

    #[test]
    fn local_wording_matches_the_server_on_the_same_dates() {
        let now = at(2026, 11, 12, 7, 27);
        assert_eq!(friendly_at(at(2026, 11, 11, 22, 28), now), "Yesterday at 10:28 PM");
        assert_eq!(friendly_at(at(2026, 11, 8, 15, 41), now), "Sunday at 3:41 PM");
        assert_eq!(friendly_at(at(2026, 11, 6, 8, 34), now), "6 days ago");
        assert_eq!(friendly_at(at(2026, 11, 5, 20, 4), now), "November 5");
        assert_eq!(friendly_at(at(2025, 3, 2, 9, 0), now), "March 2, 2025");
        assert_eq!(friendly_at(at(2026, 11, 12, 7, 26), now), "About a minute ago");
        assert_eq!(friendly_at(at(2026, 11, 12, 7, 0), now), "27 minutes ago");
        assert_eq!(friendly_at(at(2026, 11, 12, 1, 0), now), "6 hours ago");
    }

    #[test]
    fn activity_times_read_as_teams() {
        let now = at(2026, 11, 12, 7, 31);
        assert_eq!(activity_time(at(2026, 11, 11, 22, 37), now), "Yesterday at 10:37 PM");
        assert_eq!(activity_time(at(2026, 11, 8, 15, 41), now), "Sun at 3:41 PM");
        assert_eq!(activity_time(at(2026, 11, 5, 9, 0), now), "Nov 5");
        assert_eq!(activity_time(at(2026, 11, 12, 7, 30), now), "Just now");
        assert_eq!(activity_time(at(2026, 11, 12, 7, 1), now), "30m ago");
        assert_eq!(activity_time(at(2026, 11, 12, 2, 0), now), "6h ago");
    }

    #[test]
    fn activities_read_as_teams() {
        let me = "ost-test1@scnetsolutions.com";
        let you_shared = r#"{"FileActivityType":"9","FileActivityTimeStamp":"2026-11-12T06:37:00.727Z","FileActivityUsersOnPage":[{"DisplayName":"OST Test 1","Id":"ost-test1@scnetsolutions.com"}],"FileActivityNavigationId":null}"#;
        let a = activity(you_shared, me).unwrap();
        assert_eq!((a.kind.as_str(), a.text.as_str(), a.time.as_str()), ("share", "You shared this file", "2026-11-12T06:37:00.727Z"));
        // A recording in Recordings: "SharePoint App shared with Randy Northrup + 1 other".
        let app = r#"{"FileActivityType":"9","FileActivityUsersOnPage":[{"DisplayName":"SharePoint App","Id":"app@sharepoint"},{"DisplayName":"Randy Northrup","Id":"randy@x"},{"DisplayName":"OST Test 2","Id":"ost-test2@x"}]}"#;
        assert_eq!(activity(app, me).unwrap().text, "SharePoint App shared with Randy Northrup + 1 other");
        let to_me = r#"{"FileActivityType":"9","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"},{"DisplayName":"OST Test 1","Id":"OST-Test1@scnetsolutions.com"}]}"#;
        assert_eq!(activity(to_me, me).unwrap().text, "Randy Northrup shared with you");
        let edit = r#"{"FileActivityType":"5","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"}]}"#;
        assert_eq!(activity(edit, me).unwrap().text, "Randy Northrup edited");
        let mine = r#"{"FileActivityType":4,"FileActivityUsersOnPage":[{"DisplayName":"OST Test 1","Id":"ost-test1@scnetsolutions.com"}]}"#;
        assert_eq!(activity(mine, me).unwrap().text, "You edited");
        let reply = r#"{"FileActivityType":"8","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"}]}"#;
        assert_eq!(activity(reply, me).unwrap().text, "Randy Northrup replied to a comment");
        let mention = r#"{"FileActivityType":"11","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"},{"DisplayName":"OST Test 1","Id":"ost-test1@scnetsolutions.com"}]}"#;
        assert_eq!(activity(mention, me).unwrap().text, "Randy Northrup mentioned you");
        assert!(activity(r#"{"FileActivityType":"99"}"#, me).is_none());
        assert!(activity("not json", me).is_none());
    }

    #[test]
    fn rows_join_by_unique_id() {
        let row = json!({"UniqueId": "{1DD3508E-41D2-4FB6-8358-D55E775D08EB}", "Modified": "11/11/2026 10:28 PM",
            "Modified.": "2026-11-12T06:28:11Z", "Modified.FriendlyDisplay": "1|0|5|10:28 PM", "PrincipalCount": "1",
            "Created_x0020_Date.ifnew": "1", "_activity": ""});
        let (id, info) = parse_row(&row, "me@x", at(2026, 11, 12, 7, 0)).unwrap();
        assert_eq!(id, "1dd3508e-41d2-4fb6-8358-d55e775d08eb");
        assert_eq!(info, RowInfo { modified_text: "Yesterday at 10:28 PM".into(), modified_title: "11/11/2026 10:28 PM".into(),
            principal_count: 1, is_new: true, activity: None, color: String::new() });
    }

    #[test]
    fn folder_paths_come_from_web_addresses() {
        assert_eq!(server_path("https://x-my.sharepoint.com/personal/a/Documents/Microsoft%20Teams%20Chat%20Files"),
            "/personal/a/Documents/Microsoft Teams Chat Files");
    }
}
