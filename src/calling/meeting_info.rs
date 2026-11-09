//! Teams' "Meeting info" pane (More ▸ Meeting info, Teams' calling meeting
//! info panel), from the same data Teams uses:
//!
//! - The title, start and end, and location come from the join response's
//!   `meetingDetails` (`meetingChatProperties` subject and location,
//!   `startTime` / `endTime`).
//! - The body is the calendar event's, found by the meeting's `iCalUid`
//!   (Teams' calendar service `userEventUsingICalUId`). Its recurrence
//!   gives the schedule line of a recurring meeting.
//! - "Copy join info" copies the invitation block of that body
//!   (`div.me-email-text`), else the `WordSection1` paragraph holding the
//!   join link, else a "Join Teams meeting" link.
//!
//! The lines read as Teams writes them in en-US:
//! - "3:00 PM - 3:30 PM (30 minutes)"
//! - "November 6, 2026 at 3:00 PM - 3:30 PM" for a single meeting
//! - "Occurs every Mon - Fri @ 9:00 AM until December 31" for a series

use chrono::{DateTime, Datelike, TimeZone, Utc};
use serde_json::Value;

/// What the join response says about the meeting.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MeetingInfo {
    pub title: String,
    pub start: Option<DateTime<Utc>>,
    pub end: Option<DateTime<Utc>>,
    pub location: String,
    pub ical_uid: String,
    /// The join link Teams copies (the short /meet/ link when there is
    /// one) and matches the body's paragraphs against.
    pub join_url: String,
}

fn details(json: &Value) -> Option<&Value> {
    [
        "/meetingDetails",
        "/conversationResponse/meetingDetails",
        "/conversation/meetingDetails",
    ]
    .iter()
    .find_map(|p| json.pointer(p))
}

/// The meeting info in a join (conversation) response.
pub fn from_join_response(json: &Value) -> Option<MeetingInfo> {
    let d = details(json)?;
    let props: Value = d
        .get("meetingChatProperties")
        .and_then(Value::as_str)
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();
    let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let time = |k: &str| {
        [d.get(k), props.get(k)]
            .into_iter()
            .flatten()
            .find_map(|t| t.as_str())
            .and_then(|t| DateTime::parse_from_rfc3339(t).ok())
            .map(|t| t.with_timezone(&Utc))
    };
    Some(MeetingInfo {
        title: s(&props, "subject"),
        start: time("startTime"),
        end: time("endTime"),
        location: s(&props, "location"),
        ical_uid: [s(d, "iCalUid"), s(&props, "iCalUid")]
            .into_iter()
            .find(|u| !u.is_empty())
            .unwrap_or_default(),
        // Teams copies the short /meet/ link when the meeting has one.
        join_url: [s(d, "shortJoinUrl"), s(&props, "meetingJoinUrl"), s(d, "joinUrl")]
            .into_iter()
            .find(|u| !u.is_empty())
            .unwrap_or_default(),
    })
}

fn time_of_day<Tz: TimeZone>(t: &DateTime<Tz>) -> String
where
    Tz::Offset: std::fmt::Display,
{
    t.format("%-I:%M %p").to_string()
}

/// Teams' `duration_full_mf` without days' seconds: "30 minutes",
/// "1 hour 30 minutes", "1 day 2 hours". Empty when it has no hours or
/// minutes (Teams then shows no hours line).
fn duration_text(seconds: i64) -> String {
    let (days, hours, mins) = (seconds / 86_400, seconds % 86_400 / 3600, seconds % 3600 / 60);
    if hours == 0 && mins == 0 {
        return String::new();
    }
    let part = |n: i64, one: &str, many: &str| match n {
        0 => None,
        1 => Some(format!("1 {one}")),
        n => Some(format!("{n} {many}")),
    };
    [part(days, "day", "days"), part(hours, "hour", "hours"), part(mins, "minute", "minutes")]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" ")
}

/// "3:00 PM - 3:30 PM (30 minutes)" in `tz`.
pub fn hours_text<Tz: TimeZone>(start: DateTime<Utc>, end: DateTime<Utc>, tz: &Tz) -> Option<String>
where
    Tz::Offset: std::fmt::Display,
{
    let d = duration_text((end - start).num_seconds());
    (!d.is_empty()).then(|| {
        format!(
            "{} - {} ({d})",
            time_of_day(&start.with_timezone(tz)),
            time_of_day(&end.with_timezone(tz))
        )
    })
}

const WEEKDAYS: [&str; 7] = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
const SHORT_DAYS: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const LONG_DAYS: [&str; 7] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS: [&str; 12] = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
    "November", "December",
];

fn plural_interval(n: i64, one: &str, two: &str, many: impl Fn(i64) -> String) -> String {
    match n {
        1 => one.to_string(),
        2 => two.to_string(),
        n => many(n),
    }
}

/// Teams' week-day range ("Mon - Fri") for three or more days that run
/// together (wrapping over the weekend), else None.
fn day_range(days: &[usize]) -> Option<String> {
    if days.len() < 3 {
        return None;
    }
    let mut runs = 1;
    let mut gap = false;
    let wraps = days[0] == 0 && days[days.len() - 1] == 6;
    let mut first = days[0];
    let mut last = days[days.len() - 1];
    for j in 0..days.len() - 1 {
        if days[j + 1] == days[j] + 1 {
            if gap {
                runs += 1;
                gap = false;
                first = days[j];
            }
            continue;
        }
        if !gap {
            last = days[j];
        }
        gap = true;
    }
    if (runs > 1 && !wraps) || (wraps && runs != 2) {
        return None;
    }
    Some(format!("{} - {}", SHORT_DAYS[first], SHORT_DAYS[last]))
}

/// "Mon", "Mon and Wed", "Mon, Wed and Fri".
fn day_list(days: &[usize]) -> String {
    let names: Vec<&str> = days.iter().map(|&d| SHORT_DAYS[d]).collect();
    match names.len() {
        0 => String::new(),
        1 => names[0].to_string(),
        n => format!("{} and {}", names[..n - 1].join(", "), names[n - 1]),
    }
}

fn week_index(i: &str) -> &'static str {
    match i {
        "second" => "Second",
        "third" => "Third",
        "fourth" => "Fourth",
        "last" => "Last",
        _ => "First",
    }
}

/// Teams' recurrence pattern text for a Graph event's `recurrence`
/// (`pattern` and `range`), with its start time and end date: "Occurs
/// every Mon - Fri @ 9:00 AM until December 31". None for no pattern.
pub fn recurrence_text<Tz: TimeZone>(recurrence: &Value, start: DateTime<Utc>, tz: &Tz) -> Option<String>
where
    Tz::Offset: std::fmt::Display,
{
    let p = recurrence.get("pattern")?;
    let interval = p.get("interval").and_then(Value::as_i64).filter(|&i| i > 0).unwrap_or(1);
    let day_of = |name: &str| WEEKDAYS.iter().position(|d| d.eq_ignore_ascii_case(name));
    let mut days: Vec<usize> = p
        .get("daysOfWeek")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|d| d.as_str().and_then(day_of))
        .collect();
    days.sort_unstable();
    days.dedup();
    let month = p.get("month").and_then(Value::as_u64).filter(|m| (1..=12).contains(m));
    let day_of_month = p.get("dayOfMonth").and_then(Value::as_i64).unwrap_or(1);
    let index = week_index(p.get("index").and_then(Value::as_str).unwrap_or("first"));
    let first_day = days.first().map(|&d| LONG_DAYS[d]).unwrap_or("Sunday");
    let text = match p.get("type").and_then(Value::as_str)? {
        "daily" => plural_interval(interval, "Occurs daily", "Occurs every other day", |n| {
            format!("Occurs every {n} days")
        }),
        "weekly" => {
            let d = day_range(&days).unwrap_or_else(|| day_list(&days));
            plural_interval(
                interval,
                &format!("Occurs every {d}"),
                &format!("Occurs every other {d}"),
                |n| format!("Occurs every {n} weeks on {d}"),
            )
        }
        "absoluteMonthly" => plural_interval(
            interval,
            &format!("Occurs every month on day {day_of_month}"),
            &format!("Occurs every other month on day {day_of_month}"),
            |n| format!("Occurs every {n} months on day {day_of_month}"),
        ),
        "relativeMonthly" => plural_interval(
            interval,
            &format!("Occurs every month on {index} {first_day}"),
            &format!("Occurs every other month on {index} {first_day}"),
            |n| format!("Occurs every {n} months on {index} {first_day}"),
        ),
        "absoluteYearly" => format!("Occurs every {} {day_of_month}", MONTHS[month? as usize - 1]),
        "relativeYearly" => format!("Occurs every {index} {first_day} of {}", MONTHS[month? as usize - 1]),
        _ => return None,
    };
    let starttime = time_of_day(&start.with_timezone(tz));
    let until = recurrence
        .pointer("/range/type")
        .and_then(Value::as_str)
        .filter(|t| *t == "endDate")
        .and_then(|_| recurrence.pointer("/range/endDate")?.as_str())
        .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());
    Some(match until {
        Some(u) => format!("{text} @ {starttime} until {} {}", MONTHS[u.month0() as usize], u.day()),
        None => format!("{text} @ {starttime}"),
    })
}

/// The schedule line of a meeting that doesn't recur: "November 6, 2026
/// at 3:00 PM - 3:30 PM".
pub fn single_schedule_text<Tz: TimeZone>(start: DateTime<Utc>, end: DateTime<Utc>, tz: &Tz) -> String
where
    Tz::Offset: std::fmt::Display,
{
    let s = start.with_timezone(tz);
    format!(
        "{} {}, {} at {} - {}",
        MONTHS[s.month0() as usize],
        s.day(),
        s.year(),
        time_of_day(&s),
        time_of_day(&end.with_timezone(tz))
    )
}

/// The HTML between a tag's start and its matching end tag, given the
/// byte offset where its start tag begins.
fn element_inner<'a>(html: &'a str, at: usize, tag: &str) -> Option<(&'a str, usize)> {
    let lower = html.to_ascii_lowercase();
    let open = format!("<{tag}");
    let close = format!("</{tag}");
    let start = at + lower[at..].find('>')? + 1;
    let mut depth = 1;
    let mut i = start;
    while depth > 0 {
        let next_open = lower[i..].find(&open).map(|p| p + i);
        let next_close = lower[i..].find(&close).map(|p| p + i)?;
        match next_open {
            Some(o) if o < next_close => {
                depth += 1;
                i = o + open.len();
            }
            _ => {
                depth -= 1;
                if depth == 0 {
                    let end = next_close + lower[next_close..].find('>')? + 1;
                    return Some((&html[start..next_close], end));
                }
                i = next_close + close.len();
            }
        }
    }
    None
}

/// The first `<div>` whose class list has `class`.
fn find_div_with_class(html: &str, class: &str) -> Option<usize> {
    let lower = html.to_ascii_lowercase();
    let want = class.to_ascii_lowercase();
    let mut from = 0;
    while let Some(p) = lower[from..].find("<div").map(|p| p + from) {
        let tag_end = p + lower[p..].find('>')?;
        let tag = &lower[p..tag_end];
        if let Some(c) = tag.find("class=") {
            let rest = &tag[c + 6..];
            // Quoted, or (as Word writes it) bare up to a space.
            let classes = match rest.chars().next() {
                Some(q @ ('"' | '\'')) => rest[1..].split(q).next().unwrap_or(""),
                _ => rest.split(|ch: char| ch.is_whitespace() || ch == '>').next().unwrap_or(""),
            };
            if classes.split_whitespace().any(|x| x == want) {
                return Some(p);
            }
        }
        from = tag_end;
    }
    None
}

/// Text with the tags taken out and the common entities read (the DOM's
/// textContent).
pub fn text_content(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut in_tag = false;
    for c in html.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            c if !in_tag => out.push(c),
            _ => {}
        }
    }
    out.replace("&nbsp;", "\u{a0}")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
}

/// What "Copy join info" copies, as (HTML, plain text).
pub fn copy_join_info(body: &str, join_url: &str) -> (String, String) {
    if let Some(at) = find_div_with_class(body, "me-email-text")
        && let Some((inner, _)) = element_inner(body, at, "div")
        && !inner.trim().is_empty()
    {
        return (inner.to_string(), text_content(inner));
    }
    if !join_url.is_empty()
        && let Some(at) = find_div_with_class(body, "WordSection1")
        && let Some((section, _)) = element_inner(body, at, "div")
    {
        // Its child elements, in order: the one holding the join link.
        let lower = section.to_ascii_lowercase();
        let mut i = 0;
        while let Some(p) = lower[i..].find('<').map(|p| p + i) {
            let name: String = lower[p + 1..]
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric())
                .collect();
            if name.is_empty() {
                i = p + 1;
                continue;
            }
            let Some((inner, end)) = element_inner(section, p, &name) else { break };
            if inner.contains(join_url) {
                return (inner.to_string(), text_content(inner));
            }
            i = end;
        }
    }
    if join_url.is_empty() {
        return (String::new(), String::new());
    }
    let html = format!(
        "<div>\n    <a style=\"font-size: 18px; font-weight: 600; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Web', sans-serif; text-decoration: underline;color: #6264a7;\" href=\"{join_url}\" target=\"_blank\" rel=\"noreferrer noopener\">Join Teams meeting</a>\n  </div>"
    );
    (html, join_url.to_string())
}

/// Remove `<name …>…</name>` elements (and their content).
fn strip_elements(html: &str, name: &str) -> String {
    let mut s = html.to_string();
    loop {
        let lower = s.to_ascii_lowercase();
        let Some(p) = lower.find(&format!("<{name}")) else { break };
        let close = format!("</{name}>");
        let end = lower[p..].find(&close).map(|e| p + e + close.len()).unwrap_or(s.len());
        s.replace_range(p..end, "");
    }
    s
}

/// The event body as the pane shows it: the document's body, without
/// styles, scripts, comments or pictures, with line breaks as spaces
/// (Teams' meeting body rendering).
pub fn body_for_display(body: &str) -> String {
    let lower = body.to_ascii_lowercase();
    let inner = match lower.find("<body") {
        Some(p) => element_inner(body, p, "body").map(|(i, _)| i).unwrap_or(body),
        None => body,
    };
    let mut s = strip_elements(inner, "style");
    s = strip_elements(&s, "script");
    while let Some(p) = s.find("<!--") {
        let end = s[p..].find("-->").map(|e| p + e + 3).unwrap_or(s.len());
        s.replace_range(p..end, "");
    }
    // Pictures: Teams keeps only images it can load from its own media
    // service; the calendar's inline ones aren't, so none stay.
    loop {
        let lower = s.to_ascii_lowercase();
        let Some(p) = lower.find("<img") else { break };
        let end = lower[p..].find('>').map(|e| p + e + 1).unwrap_or(s.len());
        s.replace_range(p..end, "");
    }
    glue_link_text(&pt_to_px(&drop_font_sizes(&s.replace(['\r', '\n'], " "))))
}

/// Links' text wraps as Chrome wraps a URL: only after "-" and "?" (and
/// at spaces), else at the edge of the line (Teams' overflow-wrap). Qt's
/// line breaker also breaks after "/" and around "."; a word joiner
/// (U+2060) between the other characters stops that.
fn glue_link_text(html: &str) -> String {
    let mut out = String::with_capacity(html.len() * 2);
    let lower = html.to_ascii_lowercase();
    let (mut in_tag, mut in_link, mut in_entity) = (false, false, false);
    let mut prev: Option<char> = None;
    for (i, c) in html.char_indices() {
        if c == '<' {
            in_tag = true;
            let rest = &lower[i..];
            if rest.starts_with("<a ") || rest.starts_with("<a>") {
                in_link = true;
            } else if rest.starts_with("</a") {
                in_link = false;
            }
            prev = None;
        }
        if in_link && !in_tag {
            // Not inside an entity ("&amp;" stays whole).
            if c == '&' {
                in_entity = true;
            }
            if !in_entity
                && let Some(p) = prev
                && !matches!(p, '-' | '?')
                && !p.is_whitespace()
                && !c.is_whitespace()
            {
                out.push('\u{2060}');
            }
            if c == ';' {
                in_entity = false;
            }
            prev = Some(c);
        }
        out.push(c);
        if c == '>' {
            in_tag = false;
        }
    }
    out
}

/// `<font size=…>` without its size: Outlook wraps its 11pt spans in
/// `<font size="2">`, which a browser overrides with the span's size but
/// Qt's rich text applies on top of it (as "small").
fn drop_font_sizes(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    while let Some(p) = rest.to_ascii_lowercase().find("<font") {
        out.push_str(&rest[..p]);
        let end = rest[p..].find('>').map(|e| p + e + 1).unwrap_or(rest.len());
        let tag = &rest[p..end];
        let lower = tag.to_ascii_lowercase();
        match lower.find(" size=") {
            Some(a) => {
                let v = &tag[a + 6..];
                let len = match v.chars().next() {
                    Some(q @ ('"' | '\'')) => v[1..].find(q).map(|e| e + 2).unwrap_or(v.len()),
                    _ => v.find(|c: char| c.is_whitespace() || c == '>').unwrap_or(v.len()),
                };
                out.push_str(&tag[..a]);
                out.push_str(&tag[a + 6 + len..]);
            }
            None => out.push_str(tag),
        }
        rest = &rest[end..];
    }
    out.push_str(rest);
    out
}

/// Font sizes in points as CSS pixels (96 per inch), as the browser
/// renders Outlook's `font-size:11pt` (14.67 px; 15 in whole pixels).
fn pt_to_px(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut rest = html;
    while let Some(p) = rest.to_ascii_lowercase().find("font-size:") {
        let after = p + "font-size:".len();
        out.push_str(&rest[..after]);
        let tail = &rest[after..];
        let ws = tail.len() - tail.trim_start().len();
        let num: String = tail[ws..].chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
        let unit_at = ws + num.len();
        match num.parse::<f64>() {
            Ok(n) if tail[unit_at..].to_ascii_lowercase().starts_with("pt") => {
                // Qt's rich text takes whole pixels.
                let px = (n * 96.0 / 72.0).round();
                out.push_str(&format!("{px}px"));
                rest = &tail[unit_at + 2..];
            }
            _ => rest = tail,
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utc(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    #[test]
    fn reads_the_join_response() {
        let props = serde_json::json!({"subject":"OST calendar test: created from OST","startTime":"2026-11-06T23:00:00Z","location":"Microsoft Teams Meeting","endTime":"2026-11-06T23:30:00Z","iCalUid":"040000","meetingJoinUrl":"https://teams.microsoft.com/l/meetup-join/x"});
        let mut v = serde_json::json!({"meetingDetails":{"startTime":"2026-11-06T23:00:00Z","endTime":"2026-11-06T23:30:00Z","iCalUid":"040000","meetingChatProperties": props.to_string()}});
        let m = from_join_response(&v).unwrap();
        assert_eq!(m.title, "OST calendar test: created from OST");
        assert_eq!(m.location, "Microsoft Teams Meeting");
        assert_eq!(m.ical_uid, "040000");
        assert_eq!(m.start, Some(utc("2026-11-06T23:00:00Z")));
        assert_eq!(m.join_url, "https://teams.microsoft.com/l/meetup-join/x");
        v["meetingDetails"]["shortJoinUrl"] = "https://teams.microsoft.com/meet/29?p=a".into();
        assert_eq!(from_join_response(&v).unwrap().join_url, "https://teams.microsoft.com/meet/29?p=a");
    }

    #[test]
    fn lines_as_teams_writes_them() {
        let pst = chrono::FixedOffset::west_opt(8 * 3600).unwrap();
        let (s, e) = (utc("2026-11-06T23:00:00Z"), utc("2026-11-06T23:30:00Z"));
        assert_eq!(hours_text(s, e, &pst).as_deref(), Some("3:00 PM - 3:30 PM (30 minutes)"));
        assert_eq!(single_schedule_text(s, e, &pst), "November 6, 2026 at 3:00 PM - 3:30 PM");
        assert_eq!(hours_text(s, utc("2026-11-07T00:30:00Z"), &pst).as_deref(), Some("3:00 PM - 4:30 PM (1 hour 30 minutes)"));
        assert_eq!(hours_text(s, utc("2026-11-08T00:00:00Z"), &pst).as_deref(), Some("3:00 PM - 4:00 PM (1 day 1 hour)"));
        // A whole day has no hours line.
        assert_eq!(hours_text(s, utc("2026-11-07T23:00:00Z"), &pst), None);
    }

    #[test]
    fn recurrence_as_teams_writes_it() {
        let pst = chrono::FixedOffset::west_opt(8 * 3600).unwrap();
        let s = utc("2026-11-09T17:00:00Z");
        let r = |p: Value, range: Value| recurrence_text(&serde_json::json!({"pattern": p, "range": range}), s, &pst);
        let none = serde_json::json!({"type":"noEnd"});
        let weekdays = serde_json::json!({"type":"weekly","interval":1,"daysOfWeek":["monday","tuesday","wednesday","thursday","friday"]});
        assert_eq!(r(weekdays.clone(), none.clone()).as_deref(), Some("Occurs every Mon - Fri @ 9:00 AM"));
        assert_eq!(
            r(weekdays, serde_json::json!({"type":"endDate","endDate":"2026-12-31"})).as_deref(),
            Some("Occurs every Mon - Fri @ 9:00 AM until December 31")
        );
        assert_eq!(r(serde_json::json!({"type":"weekly","interval":2,"daysOfWeek":["wednesday","monday"]}), none.clone()).as_deref(), Some("Occurs every other Mon and Wed @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"weekly","interval":3,"daysOfWeek":["monday","tuesday"]}), none.clone()).as_deref(), Some("Occurs every 3 weeks on Mon and Tue @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"weekly","interval":1,"daysOfWeek":["monday","tuesday","thursday","friday"]}), none.clone()).as_deref(), Some("Occurs every Mon, Tue, Thu and Fri @ 9:00 AM"));
        // Teams' range check (197544 `O`) only lists days when it finds a
        // second run of consecutive days; three days with no two in a row
        // read as a range from the first, as Teams' code has it.
        assert_eq!(r(serde_json::json!({"type":"weekly","interval":1,"daysOfWeek":["monday","wednesday","friday"]}), none.clone()).as_deref(), Some("Occurs every Mon - Mon @ 9:00 AM"));
        // Days across the weekend need two runs to read as a range.
        assert_eq!(r(serde_json::json!({"type":"weekly","interval":1,"daysOfWeek":["saturday","sunday","monday"]}), none.clone()).as_deref(), Some("Occurs every Sun, Mon and Sat @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"daily","interval":1}), none.clone()).as_deref(), Some("Occurs daily @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"daily","interval":4}), none.clone()).as_deref(), Some("Occurs every 4 days @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"absoluteMonthly","interval":1,"dayOfMonth":15}), none.clone()).as_deref(), Some("Occurs every month on day 15 @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"relativeMonthly","interval":2,"daysOfWeek":["tuesday"],"index":"last"}), none.clone()).as_deref(), Some("Occurs every other month on Last Tuesday @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"absoluteYearly","interval":1,"month":11,"dayOfMonth":9}), none.clone()).as_deref(), Some("Occurs every November 9 @ 9:00 AM"));
        assert_eq!(r(serde_json::json!({"type":"relativeYearly","interval":1,"month":11,"daysOfWeek":["monday"],"index":"second"}), none).as_deref(), Some("Occurs every Second Monday of November @ 9:00 AM"));
        assert_eq!(recurrence_text(&Value::Null, s, &pst), None);
    }

    #[test]
    fn copies_the_invitation_block() {
        let body = r#"<html><head><style>p{}</style></head><body><div class="x"><div style="max-width: 1024px" class="me-email-text" lang="en-US"><div>Microsoft Teams meeting</div><div>Join: <a href="https://teams.microsoft.com/meet/1">link</a></div></div></div></body></html>"#;
        let (html, text) = copy_join_info(body, "https://teams.microsoft.com/meet/1");
        assert_eq!(html, r#"<div>Microsoft Teams meeting</div><div>Join: <a href="https://teams.microsoft.com/meet/1">link</a></div>"#);
        assert_eq!(text, "Microsoft Teams meetingJoin: link");
        let word = r#"<div class=WordSection1><p>Agenda</p><p>Join: <a href="https://j/1">https://j/1</a></p></div>"#;
        assert_eq!(copy_join_info(word, "https://j/1").1, "Join: https://j/1");
        let (html, text) = copy_join_info("<p>no invite</p>", "https://j/2");
        assert!(html.contains(">Join Teams meeting</a>") && html.contains("href=\"https://j/2\""));
        assert_eq!(text, "https://j/2");
        assert_eq!(copy_join_info("", ""), (String::new(), String::new()));
    }

    #[test]
    fn body_shown_without_styles_or_pictures() {
        let body = "<html><head><style>.a{}</style></head><body><!-- c --><font size=\"2\"><span style=\"font-size:11pt;\">Hi<br>\r\nthere<img src=\"cid:1\"></span></font></body></html>";
        assert_eq!(body_for_display(body), "<font><span style=\"font-size:15px;\">Hi<br>  there</span></font>");
        assert_eq!(
            glue_link_text("Join: <a href=\"https://x/1\">h/1-a?b&amp;c</a> c/d"),
            "Join: <a href=\"https://x/1\">h\u{2060}/\u{2060}1\u{2060}-a\u{2060}?b&amp;\u{2060}c</a> c/d"
        );
        assert_eq!(drop_font_sizes("<font size=2 color=\"red\">a</font>"), "<font color=\"red\">a</font>");
        assert_eq!(pt_to_px("<p style=\"font-size: 10.5pt\">a</p><p style=\"font-size:12px\">"), "<p style=\"font-size:14px\">a</p><p style=\"font-size:12px\">");
    }
}
