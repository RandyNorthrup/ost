//! The columns Teams' OneDrive app reads from SharePoint rather than Graph
//! (docs/spec/onedrive-rows.md): its friendly Modified text, the
//! Activity column, the Sharing column's count and the "new" mark. Teams'
//! file list gets them from the folder's `RenderListDataAsStream` rows
//! (`Modified.FriendlyDisplay`, `_activity`, `PrincipalCount`,
//! `Created_x0020_Date.ifnew`); OST asks for the same rows and joins them to
//! Graph's items by their list item's unique id.

use std::collections::HashMap;

use anyhow::Result;
use jiff::ZonedDateTime;
use jiff::civil::Date;

use crate::clock;
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
    if n == 1 {
        "1 other".into()
    } else {
        format!("{n} others")
    }
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
        if v >= 100.0 || v == v.floor() {
            format!("{v:.0}")
        } else if v >= 10.0 {
            format!("{v:.1}")
        } else {
            format!("{v:.2}")
        }
    };
    match n {
        1.0 => "1 byte".into(),
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
        "1" => if future {
            "In a few seconds"
        } else {
            "A few seconds ago"
        }
        .into(),
        "2" => if future {
            "In about a minute"
        } else {
            "About a minute ago"
        }
        .into(),
        "3" if future => plural(n, "In {0} minute", "In {0} minutes"),
        "3" => plural(n, "{0} minute ago", "{0} minutes ago"),
        "4" => if future {
            "In about an hour"
        } else {
            "About an hour ago"
        }
        .into(),
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

fn time_of(t: &ZonedDateTime) -> String {
    clock::format(t, "%-I:%M %p")
}

/// The same wording from a time, for rows SharePoint didn't word (as its
/// server does: this week by weekday, then days, then the date).
pub fn friendly_at(t: &ZonedDateTime, now: &ZonedDateTime) -> String {
    let secs = now.duration_since(t).as_secs();
    let (day, today) = (t.date(), now.date());
    if secs < -300 {
        return date_words(day, today);
    }
    let days = clock::days_between(day, today);
    match secs {
        s if s < 60 => "A few seconds ago".into(),
        s if s < 120 => "About a minute ago".into(),
        s if s < 3600 => plural(s / 60, "{0} minute ago", "{0} minutes ago"),
        s if s < 7200 => "About an hour ago".into(),
        s if days == 0 => plural(s / 3600, "{0} hour ago", "{0} hours ago"),
        _ if days == 1 => format!("Yesterday at {}", time_of(t)),
        // Since Sunday: the weekday.
        _ if days < i64::from(today.weekday().to_sunday_zero_offset()) + 1 => {
            format!("{} at {}", clock::format(t, "%A"), time_of(t))
        }
        _ if days < 7 => plural(days, "{0} day ago", "{0} days ago"),
        _ => date_words(day, today),
    }
}

fn date_words(day: Date, today: Date) -> String {
    if day.year() == today.year() {
        clock::format(day, "%B %-d")
    } else {
        clock::format(day, "%B %-d, %Y")
    }
}

/// The Activity column's time ("Yesterday at 10:37 PM", "Sun at 3:41 PM",
/// "Nov 5"): OneDrive's client wording.
pub fn activity_time(t: &ZonedDateTime, now: &ZonedDateTime) -> String {
    let ms = now.duration_since(t).as_millis() as i64;
    let (day, today) = (t.date(), now.date());
    let short = |d: Date| {
        if d.year() == today.year() {
            clock::format(d, "%b %-d")
        } else {
            clock::format(d, "%b %-d, %Y")
        }
    };
    if ms < -300_000 {
        return clock::format(t, "%b %-d");
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
    if day >= clock::add_days(today, -1) {
        return format!("Yesterday at {}", time_of(t));
    }
    if day >= clock::add_days(today, -6) {
        return format!("{} at {}", clock::format(t, "%a"), time_of(t));
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
    let kind = match v["FileActivityType"]
        .as_str()
        .and_then(|t| t.parse::<u32>().ok())
        .or(v["FileActivityType"].as_u64().map(|n| n as u32))?
    {
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
                name: [u["DisplayName"].as_str(), Some(id)]
                    .into_iter()
                    .flatten()
                    .find(|s| !s.is_empty())
                    .unwrap_or_default()
                    .to_string(),
                me: !id.is_empty() && id.eq_ignore_ascii_case(me),
            }
        })
        .collect();
    // Mentions, shares and tasks: the first is who did it, the rest are
    // the people it was for.
    let recipients: Vec<Who> =
        if matches!(kind, "mention" | "share" | "createTask") && users.len() > 1 {
            users.split_off(1)
        } else {
            Vec::new()
        };
    // You first, then the others (OneDrive's _getFilteredActors).
    let sorted = |list: &[Who]| -> (bool, Vec<String>) {
        let you = list.iter().any(|w| w.me);
        let mut names: Vec<String> = list
            .iter()
            .filter(|w| w.me)
            .take(1)
            .map(|_| "you".to_string())
            .collect();
        names.extend(list.iter().filter(|w| !w.me).map(|w| w.name.clone()));
        (you, names)
    };
    let render = |names: &[String], cap: bool| {
        names
            .first()
            .cloned()
            .unwrap_or_else(|| if cap { "Someone" } else { "someone" }.into())
    };
    let (you, actors) = sorted(&users);
    let first = render(&actors, true);
    let text = match kind {
        "edit" => {
            if you {
                "You edited".into()
            } else {
                fill("{0} edited", &[&first])
            }
        }
        "comment" if actors.len() > 1 => fill(
            if you {
                "You + {0} commented"
            } else {
                "{0} + {1} commented"
            },
            &[&first, &others(actors.len() - 1)],
        ),
        "comment" => {
            if you {
                "You commented".into()
            } else {
                fill("{0} commented", &[&first])
            }
        }
        "commentResponse" if actors.len() > 1 => fill(
            if you {
                "You + {2} replied to a {0}"
            } else {
                "{1} + {2} replied to a {0}"
            },
            &[COMMENT, &first, &others(actors.len() - 1)],
        ),
        "commentResponse" => fill(
            if you {
                "You replied to a {0}"
            } else {
                "{1} replied to a {0}"
            },
            &[COMMENT, &first],
        ),
        "share" if recipients.is_empty() => fill(
            "{1} shared {0}",
            &[THIS_FILE, if you { "You" } else { &first }],
        ),
        "share" => {
            let (to_you, to) = sorted(&recipients);
            let them = render(&to, false);
            if to.len() > 1 {
                fill(
                    if you {
                        "You shared with {1} + {2}"
                    } else {
                        "{0} shared with {1} + {2}"
                    },
                    &[&first, &them, &others(to.len() - 1)],
                )
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
                fill(
                    if you {
                        "You mentioned {1} + {2}"
                    } else {
                        "{0} mentioned {1} + {2}"
                    },
                    &[&first, &them, &others(to.len() - 1)],
                )
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
            fill(
                if you {
                    "You created a task for {1}"
                } else {
                    "{0} created a task for {1}"
                },
                &[&first, &render(&to, false)],
            )
        }
        "createTask" => fill("{0} created a task", &[&render(&actors, false)]),
        _ => {
            if you {
                "You completed the task".into()
            } else {
                fill("{0} completed the task", &[&first])
            }
        }
    };
    Some(Activity {
        kind: kind.into(),
        text,
        time: v["FileActivityTimeStamp"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
    })
}

/// One `RenderListDataAsStream` row, keyed by its unique id (lowercase,
/// without braces, as Graph's `sharepointIds.listItemUniqueId`).
pub fn parse_row(row: &Value, me: &str, now: &ZonedDateTime) -> Option<(String, RowInfo)> {
    let id = row["UniqueId"]
        .as_str()?
        .trim_matches(|c| c == '{' || c == '}')
        .to_ascii_lowercase();
    let s = |k: &str| row[k].as_str().unwrap_or_default();
    let modified_text = match s("Modified.FriendlyDisplay") {
        "" => clock::parse_instant(s("Modified."))
            .map(|t| friendly_at(&clock::local(t), now))
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

// ------------------------------------------------------------- Filter by

/// One column's Filter by (Teams' OneDrive list: Modified and Modified By),
/// its chosen values in the order they were ticked: dates as SharePoint
/// gives them ("2026-11-11", shown "11/11/2026") or people's names, and
/// "@Me" for you.
#[derive(Debug, Clone, Default, PartialEq, serde::Deserialize, Serialize)]
pub struct ColumnFilter {
    /// The field's internal name: "Modified" or "Editor".
    pub field: String,
    pub values: Vec<String>,
    /// What each value shows ("11/11/2026", a name).
    #[serde(default)]
    pub labels: Vec<String>,
}

/// The token for "@Me" (you, whoever you are: CAML's `<UserID/>`).
pub const ME: &str = "@Me";

fn filter_type(field: &str) -> &'static str {
    if field == "Modified" {
        "DateTime"
    } else {
        "User"
    }
}

/// OneDrive's filters in its column order (Modified before Modified By),
/// empty ones left out.
fn ordered(filters: &[ColumnFilter]) -> Vec<&ColumnFilter> {
    let rank = |f: &str| match f {
        "Modified" => 0,
        "Editor" => 1,
        _ => 2,
    };
    let mut v: Vec<&ColumnFilter> = filters.iter().filter(|f| !f.values.is_empty()).collect();
    v.sort_by_key(|f| rank(&f.field));
    v
}

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes())
        .collect::<String>()
        .replace('+', "%20")
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// How OneDrive asks SharePoint for a filtered list: query parameters
/// (`FilterField1=Editor&FilterValue1=…&FilterType1=User`; with several
/// values `FilterFields1=…&FilterValues1=a;#b&FilterTypes1=…`; a date also
/// `FilterDisplay1`), or, once "@Me" is chosen, none of those but a CAML
/// `<Where>` (`OverrideViewXml`), an `<Or>` per column.
pub fn filter_request(filters: &[ColumnFilter]) -> (String, Option<String>) {
    let cols = ordered(filters);
    if cols.iter().any(|c| c.values.iter().any(|v| v == ME)) {
        let eq = |field: &str, v: &str| {
            let value = if v == ME {
                "<UserID/>".to_string()
            } else {
                xml_escape(v)
            };
            format!(
                r#"<Eq><FieldRef Name="{field}"/><Value Type="{}">{value}</Value></Eq>"#,
                filter_type(field)
            )
        };
        let col = |c: &ColumnFilter| {
            let mut it = c.values.iter();
            let mut acc = eq(&c.field, it.next().map(String::as_str).unwrap_or_default());
            let rest: Vec<&String> = it.collect();
            for (i, v) in rest.iter().enumerate() {
                let id = if i + 1 == rest.len() {
                    format!(r#" id="{}""#, c.field)
                } else {
                    String::new()
                };
                acc = format!("<Or{id}>{acc}{}</Or>", eq(&c.field, v));
            }
            acc
        };
        let mut where_ = String::new();
        for (i, c) in cols.iter().enumerate() {
            where_ = if i == 0 {
                col(c)
            } else {
                format!("<And>{where_}{}</And>", col(c))
            };
        }
        return (
            String::new(),
            Some(format!(
                "<View><Query><Where>{where_}</Where></Query></View>"
            )),
        );
    }
    let mut q = String::new();
    for (i, c) in cols.iter().enumerate() {
        let n = i + 1;
        let t = filter_type(&c.field);
        if c.values.len() == 1 {
            q.push_str(&format!(
                "&FilterField{n}={}&FilterValue{n}={}&FilterType{n}={t}",
                c.field,
                enc(&c.values[0])
            ));
            if t == "DateTime"
                && let Some(l) = c.labels.first()
            {
                q.push_str(&format!("&FilterDisplay{n}={}", enc(l)));
            }
        } else {
            q.push_str(&format!(
                "&FilterFields{n}={}&FilterValues{n}={}&FilterTypes{n}={t}",
                c.field,
                enc(&c.values.join(";#"))
            ));
        }
    }
    (q, None)
}

/// The values a column's Filter by pane offers (SharePoint's
/// `RenderListFilterData`: an HTML `<SELECT>`, base64 in its reply): each
/// `(value, label)`, (All) left out.
pub fn filter_options(html: &str) -> Vec<(String, String)> {
    let unescape = |s: &str| {
        s.replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")
    };
    let mut out = Vec::new();
    let mut rest = html;
    while let Some(p) = rest.find("<OPTION") {
        rest = &rest[p + 7..];
        let Some(gt) = rest.find('>') else { break };
        let attrs = &rest[..gt];
        let value = attrs
            .find("Value=\"")
            .and_then(|v| {
                attrs[v + 7..]
                    .find('"')
                    .map(|e| attrs[v + 7..v + 7 + e].to_string())
            })
            .unwrap_or_default();
        let body = &rest[gt + 1..];
        let label = body
            .find("</OPTION>")
            .map(|e| body[..e].to_string())
            .unwrap_or_default();
        if !value.is_empty() {
            out.push((unescape(&value), unescape(label.trim())));
        }
    }
    out
}

/// A folder's Filter by values for `field` ("Modified" or "Editor"), with
/// the filters already chosen (as OneDrive asks).
pub async fn filter_values(
    site: &str,
    list: &str,
    folder: &str,
    field: &str,
    filters: &[ColumnFilter],
) -> Result<Vec<(String, String)>> {
    let list = list.trim_matches(|c| c == '{' || c == '}');
    if list.is_empty() || !list.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        anyhow::bail!("Not a list id");
    }
    let (q, _) = filter_request(filters);
    let mut url = format!(
        "{}/_api/web/lists(guid'{list}')/RenderListFilterData?FieldInternalName='{field}'",
        site.trim_end_matches('/')
    );
    if !folder.is_empty() {
        url.push_str(&format!("&RootFolder={}", enc(folder)));
    }
    url.push_str(&q);
    // The reply is the HTML itself, or (as OneDrive's page gets it) JSON
    // holding it base64-encoded.
    let text = super::sharing::send_text(
        reqwest::Method::POST,
        &url,
        &json!({}),
        &[
            ("accept", "application/json;odata=nometadata"),
            ("user-agent", super::client::TEAMS_WEB_UA),
        ],
    )
    .await?;
    let html = if text.contains("<OPTION") {
        text
    } else {
        let v: Value = serde_json::from_str(&text).unwrap_or_default();
        let b64 = v
            .as_str()
            .or_else(|| v["value"].as_str())
            .or_else(|| v["d"]["RenderListFilterData"].as_str())
            .unwrap_or_default();
        use base64::Engine;
        base64::engine::general_purpose::STANDARD
            .decode(b64.trim())
            .ok()
            .and_then(|b| String::from_utf8(b).ok())
            .unwrap_or_default()
    };
    Ok(filter_options(&html))
}

/// The people Filter by's box suggests for `query` (OneDrive's people
/// picker, as its Modified By pane asks: people only, no e-mail addresses).
pub async fn filter_people(site: &str, query: &str) -> Result<Vec<Value>> {
    let url = format!(
        "{}/_api/SP.UI.ApplicationPages.ClientPeoplePickerWebServiceInterface.ClientPeoplePickerSearchUser",
        site.trim_end_matches('/')
    );
    let reply = super::sharing::post(
        &url,
        &json!({"queryParams": {
            "QueryString": query, "MaximumEntitySuggestions": 30, "AllowEmailAddresses": false,
            "PrincipalType": 13, "PrincipalSource": 15, "UseSubstrateSearch": true, "SharePointGroupID": 0
        }}),
    )
    .await?;
    Ok(super::sharing::parse_picker(&reply))
}

/// The rows of a library folder (`folder` is its server-relative path; empty
/// for the library's top).
pub async fn folder(
    site: &str,
    list: &str,
    folder: &str,
    me: &str,
) -> Result<HashMap<String, RowInfo>> {
    folder_filtered(site, list, folder, me, &[]).await
}

/// `folder`'s rows that pass the column filters (OneDrive's Filter by).
pub async fn folder_filtered(
    site: &str,
    list: &str,
    folder: &str,
    me: &str,
    filters: &[ColumnFilter],
) -> Result<HashMap<String, RowInfo>> {
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
    let (q, caml) = filter_request(filters);
    // OneDrive sends @Me's CAML as OverrideViewXml over its view; OST asks
    // with its own ViewXml (which OverrideViewXml doesn't apply to), so the
    // same <Query> goes into that.
    if let Some(caml) = caml {
        let query = caml
            .trim_start_matches("<View>")
            .trim_end_matches("</View>");
        params["ViewXml"] = json!(VIEW_XML.replacen("<View>", &format!("<View>{query}"), 1));
    }
    let url = format!(
        "{}/_api/web/lists(guid'{list}')/RenderListDataAsStream{}",
        site.trim_end_matches('/'),
        q.replacen('&', "?", 1)
    );
    let reply = super::sharing::post_with(
        &url,
        &json!({ "parameters": params }),
        &[("user-agent", super::client::TEAMS_WEB_UA)],
    )
    .await?;
    let now = clock::local_now();
    Ok(reply["Row"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|r| parse_row(r, me, &now))
        .collect())
}

/// The rows of a OneDrive app folder (the drive's top when `item_id` is
/// empty), as Graph addresses it.
pub async fn for_folder(
    client: &super::client::TeamsClient,
    drive_id: &str,
    item_id: &str,
) -> Result<HashMap<String, RowInfo>> {
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

/// `for_folder` with OneDrive's column filters; also the folder's site,
/// list and path (its Filter by panes ask there).
pub async fn for_folder_filtered(
    client: &super::client::TeamsClient,
    drive_id: &str,
    item_id: &str,
    filters: &[ColumnFilter],
) -> Result<HashMap<String, RowInfo>> {
    let (site, list, path) = folder_place(client, drive_id, item_id).await?;
    let me = client.user_principal_name().unwrap_or_default();
    folder_filtered(&site, &list, &path, &me, filters).await
}

/// A OneDrive app folder's SharePoint site, list id and server-relative
/// path (empty at the library's top).
pub async fn folder_place(
    client: &super::client::TeamsClient,
    drive_id: &str,
    item_id: &str,
) -> Result<(String, String, String)> {
    if item_id.is_empty() {
        let r = super::drive::root(client, drive_id).await?;
        Ok((r.sp_site, r.sp_list, String::new()))
    } else {
        let f = super::drive::item(client, drive_id, item_id).await?;
        let p = server_path(&f.web_url);
        Ok((f.sp_site, f.sp_list, p))
    }
}

/// RenderOptions as Teams' OneDrive list asks (its My files request,
/// captured 2026-11-26): with them SharePoint also returns the shortcuts
/// Add shortcut made (ProgId `AddToOneDrive.MountPoint`), which Graph's
/// children and the plain list rows leave out.
const SHORTCUT_RENDER_OPTIONS: u64 = 5_691_143;
const SHORTCUT_VIEW_XML: &str = r#"<View><ViewFields><FieldRef Name="FileLeafRef"/><FieldRef Name="FileRef"/><FieldRef Name="ProgId"/><FieldRef Name="RemoteItem"/><FieldRef Name="UniqueId"/><FieldRef Name="Modified"/><FieldRef Name="Editor"/></ViewFields><RowLimit Paged="TRUE">500</RowLimit></View>"#;

/// The shortcuts in a library folder (`folder`: its server-relative path,
/// empty at the top), as drive items of what they point to: the target's
/// drive and item, the shortcut's name, and "Owner: {site}" for Sharing as
/// Teams shows it.
pub async fn shortcuts(
    site: &str,
    list: &str,
    folder: &str,
) -> Result<Vec<super::drive::DriveItem>> {
    let list = list.trim_matches(|c| c == '{' || c == '}');
    if list.is_empty() || !list.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        anyhow::bail!("Not a list id");
    }
    let mut params = json!({
        "__metadata": { "type": "SP.RenderListDataParameters" },
        "RenderOptions": SHORTCUT_RENDER_OPTIONS,
        "ViewXml": SHORTCUT_VIEW_XML,
    });
    if !folder.is_empty() {
        params["FolderServerRelativeUrl"] = json!(folder);
    }
    let url = format!(
        "{}/_api/web/lists(guid'{list}')/RenderListDataAsStream",
        site.trim_end_matches('/')
    );
    let reply = super::sharing::post_with(
        &url,
        &json!({ "parameters": params }),
        &[("user-agent", super::client::TEAMS_WEB_UA)],
    )
    .await?;
    Ok(shortcut_items(&reply, site, list))
}

/// `shortcuts`' rows (the reply has them in `ListData.Row`, or `Row`);
/// `site` and `list` are the shortcut's own library.
pub fn shortcut_items(reply: &Value, site: &str, list: &str) -> Vec<super::drive::DriveItem> {
    let rows = reply["ListData"]["Row"]
        .as_array()
        .or_else(|| reply["Row"].as_array())
        .cloned()
        .unwrap_or_default();
    rows.iter()
        .filter(|r| r["ProgId"].as_str() == Some("AddToOneDrive.MountPoint"))
        .filter_map(|r| {
            let remote: Value = match &r["RemoteItem"] {
                Value::String(t) => serde_json::from_str(t).ok()?,
                v => v.clone(),
            };
            let g = |k: &str| remote[k].as_str().unwrap_or_default().to_string();
            let trim = |v: String| {
                v.trim_matches(|c| c == '{' || c == '}')
                    .to_ascii_lowercase()
            };
            let (drive, id) = (g("DriveId"), g("ItemId"));
            // The shortcut's own item: ".spItemUrl" is
            // ".../drives/{drive}/items/{id}?…".
            let own = r[".spItemUrl"].as_str().unwrap_or_default();
            let own = own.split('?').next().unwrap_or_default();
            let mut parts = own.rsplit('/');
            let (own_id, _, own_drive) = (
                parts.next().unwrap_or_default().to_string(),
                parts.next().unwrap_or_default(),
                parts.next().unwrap_or_default().to_string(),
            );
            if drive.is_empty() || id.is_empty() || own_id.is_empty() || own_drive.is_empty() {
                return None;
            }
            let folder = remote["FSObjType"].as_i64() == Some(1);
            // A file shortcut opens through its mount point (OneDrive's
            // "serverurl.progid", else the shortcut's own address, which
            // SharePoint sends on to the file).
            let host: String = r[".spItemUrl"]
                .as_str()
                .unwrap_or_default()
                .split('/')
                .take(3)
                .collect::<Vec<_>>()
                .join("/")
                .replace(":443", "");
            let web_url = match r["serverurl.progid"].as_str() {
                Some(u) if u.len() > 1 && u[1..].starts_with("https://") => u[1..].to_string(),
                _ => match r["FileRef"].as_str() {
                    Some(f) if !f.is_empty() && !host.is_empty() => format!("{host}{f}"),
                    _ => String::new(),
                },
            };
            let name = r["FileLeafRef"].as_str().unwrap_or_default().to_string();
            Some(super::drive::DriveItem {
                kind: if folder {
                    String::new()
                } else {
                    g("FileType").to_ascii_lowercase()
                },
                id: own_id,
                drive_id: own_drive,
                remote_id: id,
                remote_drive_id: drive,
                is_folder: folder,
                child_count: remote["FolderChildCount"].as_u64().unwrap_or(0),
                size: remote["SMTotalSize"].as_u64().unwrap_or(0),
                modified: r["Modified."].as_str().unwrap_or_default().to_string(),
                modified_by: r["Editor"][0]["title"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                sharing: match g("SiteTitle") {
                    t if t.is_empty() => "Shared".into(),
                    t => format!("Owner: {t}"),
                },
                // The shortcut's own SharePoint address (its row in your
                // library), so Move to, Copy to and the rest act on the
                // shortcut, never on the folder it points to.
                sp_site: site.trim_end_matches('/').to_string(),
                sp_list: list
                    .trim_matches(|c| c == '{' || c == '}')
                    .to_ascii_lowercase(),
                sp_item: trim(r["UniqueId"].as_str().unwrap_or_default().to_string()),
                special: "shortcut".into(),
                web_url,
                name,
                ..Default::default()
            })
        })
        .collect()
}

/// A drive item as the OneDrive app's table shows it: Graph's fields plus
/// the row's Modified wording, tooltip, Sharing, "new" mark and Activity
/// (SharePoint's where it has them, else worded here from Graph's time).
pub fn decorate(
    item: &super::drive::DriveItem,
    row: Option<&RowInfo>,
    now: &ZonedDateTime,
) -> Value {
    let mut v = serde_json::to_value(item).unwrap_or_default();
    let t = clock::parse_instant(&item.modified).map(clock::local);
    v["modified_text"] = json!(match row {
        Some(r) if !r.modified_text.is_empty() => r.modified_text.clone(),
        _ => t.as_ref().map(|t| friendly_at(t, now)).unwrap_or_default(),
    });
    v["modified_title"] = json!(match row {
        Some(r) if !r.modified_title.is_empty() => r.modified_title.clone(),
        _ => t
            .map(|t| clock::format(&t, "%-m/%-d/%Y %-I:%M %p"))
            .unwrap_or_default(),
    });
    if let Some(r) = row {
        v["sharing"] = json!(if r.principal_count > 0 {
            "Shared"
        } else {
            "Private"
        });
        v["is_new"] = json!(r.is_new);
        v["folder_color"] = json!(r.color);
        if let Some(a) = &r.activity {
            let when = clock::parse_instant(&a.time).map(|t| activity_time(&clock::local(t), now));
            v["activity"] =
                json!({ "kind": a.kind, "text": a.text, "time": when.unwrap_or_default() });
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
mod filter_tests {
    use super::*;

    fn col(field: &str, values: &[&str], labels: &[&str]) -> ColumnFilter {
        ColumnFilter {
            field: field.into(),
            values: values.iter().map(|s| s.to_string()).collect(),
            labels: labels.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn filters_as_onedrive_asks() {
        // as captured from Teams' OneDrive app on winpc (2026-11-20)
        assert_eq!(
            filter_request(&[col("Editor", &["SharePoint App"], &[])]).0,
            "&FilterField1=Editor&FilterValue1=SharePoint%20App&FilterType1=User"
        );
        assert_eq!(
            filter_request(&[
                col("Editor", &["SharePoint App", "OST Test 1"], &[]),
                col("Modified", &["2026-11-11"], &["11/11/2026"])
            ])
            .0,
            "&FilterField1=Modified&FilterValue1=2026-11-11&FilterType1=DateTime&FilterDisplay1=11%2F11%2F2026&FilterFields2=Editor&FilterValues2=SharePoint%20App%3B%23OST%20Test%201&FilterTypes2=User"
        );
        let (q, caml) =
            filter_request(&[col("Editor", &["SharePoint App", ME, "OST Test 2"], &[])]);
        assert_eq!(q, "");
        assert_eq!(
            caml.unwrap(),
            r#"<View><Query><Where><Or id="Editor"><Or><Eq><FieldRef Name="Editor"/><Value Type="User">SharePoint App</Value></Eq><Eq><FieldRef Name="Editor"/><Value Type="User"><UserID/></Value></Eq></Or><Eq><FieldRef Name="Editor"/><Value Type="User">OST Test 2</Value></Eq></Or></Where></Query></View>"#
        );
        assert_eq!(
            filter_request(&[col("Editor", &[], &[])]),
            (String::new(), None)
        );
    }

    #[test]
    fn filter_pane_values() {
        let html = r#"<SELECT id="diidFilterModified"><OPTION  Value="">(All)</OPTION><OPTION Value="2026-11-05" >11/5/2026</OPTION><OPTION Value="2026-11-11"  SELECTED>11/11/2026</OPTION></SELECT><br><a>Modified</a>"#;
        assert_eq!(
            filter_options(html),
            vec![
                ("2026-11-05".into(), "11/5/2026".into()),
                ("2026-11-11".into(), "11/11/2026".into())
            ]
        );
        let people = r#"<OPTION  Value="">(All)</OPTION><OPTION Value="OST Test 1" >OST Test 1</OPTION><OPTION Value="Smith &amp; Co"  SELECTED>Smith &amp; Co</OPTION>"#;
        assert_eq!(
            filter_options(people)[1],
            ("Smith & Co".into(), "Smith & Co".into())
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A shortcut row of Teams' My files request (2026-11-26), cut down.
    #[test]
    fn shortcuts_read_from_onedrives_rows() {
        let reply = json!({ "ListData": { "Row": [
            { "FileLeafRef": "Attachments", "ProgId": "", "UniqueId": "{1}" },
            { "FileLeafRef": "OST Test Team - General", "ProgId": "AddToOneDrive.MountPoint", "Modified.": "2026-11-25T22:06:08Z",
              "Editor": [{ "title": "OST Test 1" }], "UniqueId": "{A61FE7F5-7002}", "FileRef": "/personal/a/Documents/OST Test Team - General", ".spItemUrl": "https://x-my.sharepoint.com:443/_api/v2.0/drives/b!MwwW/items/01BV7C2BHV44?version=Published",
              "RemoteItem": "{\"DriveId\":\"b!08rs\",\"ItemId\":\"01ZLBLND\",\"SiteUrl\":\"https://x.sharepoint.com/sites/OSTTestTeam\",\"ListId\":\"{1725E7C5-6C9A}\",\"FSObjType\":1,\"FolderChildCount\":1,\"SiteTitle\":\"OST Test Team\",\"UniqueId\":\"{9E8F3F36}\",\"SMTotalSize\":12253}" }
        ] } });
        let items = shortcut_items(
            &reply,
            "https://x-my.sharepoint.com/personal/a/",
            "{0E0A18F3-101B}",
        );
        assert_eq!(items.len(), 1);
        let it = &items[0];
        assert_eq!(
            (it.name.as_str(), it.drive_id.as_str(), it.id.as_str()),
            ("OST Test Team - General", "b!MwwW", "01BV7C2BHV44")
        );
        assert_eq!(
            (it.remote_drive_id.as_str(), it.remote_id.as_str()),
            ("b!08rs", "01ZLBLND")
        );
        assert!(it.is_folder);
        assert_eq!(
            (
                it.child_count,
                it.sharing.as_str(),
                it.sp_list.as_str(),
                it.sp_item.as_str()
            ),
            (1, "Owner: OST Test Team", "0e0a18f3-101b", "a61fe7f5-7002")
        );
        // The shortcut's own library, never the target's.
        assert_eq!(it.sp_site, "https://x-my.sharepoint.com/personal/a");
        assert_eq!(it.special, "shortcut");
        assert_eq!(
            it.web_url,
            "https://x-my.sharepoint.com/personal/a/Documents/OST Test Team - General"
        );
    }

    fn at(y: i16, mo: i8, d: i8, h: i8, mi: i8) -> ZonedDateTime {
        clock::local_single(jiff::civil::datetime(y, mo, d, h, mi, 0, 0)).unwrap()
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
        assert_eq!(
            friendly_display("1|0|7|Sunday|3:41 PM"),
            "Sunday at 3:41 PM"
        );
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
        assert_eq!(
            friendly_at(&at(2026, 11, 11, 22, 28), &now),
            "Yesterday at 10:28 PM"
        );
        assert_eq!(
            friendly_at(&at(2026, 11, 8, 15, 41), &now),
            "Sunday at 3:41 PM"
        );
        assert_eq!(friendly_at(&at(2026, 11, 6, 8, 34), &now), "6 days ago");
        assert_eq!(friendly_at(&at(2026, 11, 5, 20, 4), &now), "November 5");
        assert_eq!(friendly_at(&at(2025, 3, 2, 9, 0), &now), "March 2, 2025");
        assert_eq!(
            friendly_at(&at(2026, 11, 12, 7, 26), &now),
            "About a minute ago"
        );
        assert_eq!(friendly_at(&at(2026, 11, 12, 7, 0), &now), "27 minutes ago");
        assert_eq!(friendly_at(&at(2026, 11, 12, 1, 0), &now), "6 hours ago");
    }

    #[test]
    fn wording_holds_across_dst_changes() {
        let tz = jiff::tz::TimeZone::posix("EST5EDT,M3.2.0,M11.1.0").unwrap();
        let at = |mo, d, h, mi| {
            clock::single(&tz, jiff::civil::datetime(2026, mo, d, h, mi, 0, 0)).unwrap()
        };
        // The day after the clocks went back: yesterday's times on their
        // own clock.
        let now = at(11, 2, 9, 0);
        assert_eq!(
            friendly_at(&at(11, 1, 0, 30), &now),
            "Yesterday at 12:30 AM"
        );
        assert_eq!(
            activity_time(&at(11, 1, 3, 0), &now),
            "Yesterday at 3:00 AM"
        );
        // Hours ago are real hours: 23:00 on the 25-hour day is 24 hours
        // after its midnight, 12:00 on the 23-hour day 11 hours.
        let now = at(11, 1, 23, 0);
        assert_eq!(friendly_at(&at(11, 1, 0, 0), &now), "24 hours ago");
        assert_eq!(activity_time(&at(11, 1, 0, 0), &now), "24h ago");
        let now = at(3, 8, 12, 0);
        assert_eq!(friendly_at(&at(3, 8, 0, 0), &now), "11 hours ago");
        assert_eq!(activity_time(&at(3, 8, 0, 0), &now), "11h ago");
        assert_eq!(
            activity_time(&at(3, 7, 23, 0), &now),
            "Yesterday at 11:00 PM"
        );
    }

    #[test]
    fn activity_times_read_as_teams() {
        let now = at(2026, 11, 12, 7, 31);
        assert_eq!(
            activity_time(&at(2026, 11, 11, 22, 37), &now),
            "Yesterday at 10:37 PM"
        );
        assert_eq!(
            activity_time(&at(2026, 11, 8, 15, 41), &now),
            "Sun at 3:41 PM"
        );
        assert_eq!(activity_time(&at(2026, 11, 5, 9, 0), &now), "Nov 5");
        assert_eq!(activity_time(&at(2026, 11, 12, 7, 30), &now), "Just now");
        assert_eq!(activity_time(&at(2026, 11, 12, 7, 1), &now), "30m ago");
        assert_eq!(activity_time(&at(2026, 11, 12, 2, 0), &now), "6h ago");
    }

    #[test]
    fn activities_read_as_teams() {
        let me = "ost-test1@scnetsolutions.com";
        let you_shared = r#"{"FileActivityType":"9","FileActivityTimeStamp":"2026-11-12T06:37:00.727Z","FileActivityUsersOnPage":[{"DisplayName":"OST Test 1","Id":"ost-test1@scnetsolutions.com"}],"FileActivityNavigationId":null}"#;
        let a = activity(you_shared, me).unwrap();
        assert_eq!(
            (a.kind.as_str(), a.text.as_str(), a.time.as_str()),
            ("share", "You shared this file", "2026-11-12T06:37:00.727Z")
        );
        // A recording in Recordings: "SharePoint App shared with Randy Northrup + 1 other".
        let app = r#"{"FileActivityType":"9","FileActivityUsersOnPage":[{"DisplayName":"SharePoint App","Id":"app@sharepoint"},{"DisplayName":"Randy Northrup","Id":"randy@x"},{"DisplayName":"OST Test 2","Id":"ost-test2@x"}]}"#;
        assert_eq!(
            activity(app, me).unwrap().text,
            "SharePoint App shared with Randy Northrup + 1 other"
        );
        let to_me = r#"{"FileActivityType":"9","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"},{"DisplayName":"OST Test 1","Id":"OST-Test1@scnetsolutions.com"}]}"#;
        assert_eq!(
            activity(to_me, me).unwrap().text,
            "Randy Northrup shared with you"
        );
        let edit = r#"{"FileActivityType":"5","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"}]}"#;
        assert_eq!(activity(edit, me).unwrap().text, "Randy Northrup edited");
        let mine = r#"{"FileActivityType":4,"FileActivityUsersOnPage":[{"DisplayName":"OST Test 1","Id":"ost-test1@scnetsolutions.com"}]}"#;
        assert_eq!(activity(mine, me).unwrap().text, "You edited");
        let reply = r#"{"FileActivityType":"8","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"}]}"#;
        assert_eq!(
            activity(reply, me).unwrap().text,
            "Randy Northrup replied to a comment"
        );
        let mention = r#"{"FileActivityType":"11","FileActivityUsersOnPage":[{"DisplayName":"Randy Northrup","Id":"randy@x"},{"DisplayName":"OST Test 1","Id":"ost-test1@scnetsolutions.com"}]}"#;
        assert_eq!(
            activity(mention, me).unwrap().text,
            "Randy Northrup mentioned you"
        );
        assert!(activity(r#"{"FileActivityType":"99"}"#, me).is_none());
        assert!(activity("not json", me).is_none());
    }

    #[test]
    fn rows_join_by_unique_id() {
        let row = json!({"UniqueId": "{1DD3508E-41D2-4FB6-8358-D55E775D08EB}", "Modified": "11/11/2026 10:28 PM",
            "Modified.": "2026-11-12T06:28:11Z", "Modified.FriendlyDisplay": "1|0|5|10:28 PM", "PrincipalCount": "1",
            "Created_x0020_Date.ifnew": "1", "_activity": ""});
        let (id, info) = parse_row(&row, "me@x", &at(2026, 11, 12, 7, 0)).unwrap();
        assert_eq!(id, "1dd3508e-41d2-4fb6-8358-d55e775d08eb");
        assert_eq!(
            info,
            RowInfo {
                modified_text: "Yesterday at 10:28 PM".into(),
                modified_title: "11/11/2026 10:28 PM".into(),
                principal_count: 1,
                is_new: true,
                activity: None,
                color: String::new()
            }
        );
    }

    #[test]
    fn folder_paths_come_from_web_addresses() {
        assert_eq!(
            server_path(
                "https://x-my.sharepoint.com/personal/a/Documents/Microsoft%20Teams%20Chat%20Files"
            ),
            "/personal/a/Documents/Microsoft Teams Chat Files"
        );
    }
}
