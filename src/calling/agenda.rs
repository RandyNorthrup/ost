//! Teams' agenda timer (the Facilitator's agenda in the meeting timer
//! strip): the edits its editor makes to `agendaTimer.sections`, as its
//! lazy-meeting-timer bundle does them (research: scratchpad
//! c073/agenda.md §3–4, session 744c3998).
//!
//! A section is `{title, originalDuration (ms), isDiscussed,
//! topicRelevanceUserOverride, relevanceScore?, …}`; unknown fields travel
//! with it. Every edit keeps the agenda's total (whole minutes), and the
//! result goes out as the whole `agendaTimer` ([`with_sections`]).

use serde_json::{Value, json};

use super::meeting_timer::{CANCELLED, IN_PROGRESS, Timer};

const MINUTE: i64 = 60_000;
/// The longest topic (Teams' `M.x`), in minutes.
const MAX_MINUTES: i64 = 999;
/// What a new topic takes at most (Teams' `Ht`), in minutes.
const NEW_TOPIC_MINUTES: i64 = 5;
/// The longest title (Teams' `M.M0`).
const MAX_TITLE: usize = 100;
/// A relevance score that counts as discussed (Teams' `M._C`).
const DISCUSSED_SCORE: f64 = 3.0;
/// Teams' time reservoir topic (`mt_agenda_open_discussion_title`), as the
/// Facilitator names it.
pub const OPEN_DISCUSSION: &str = "Open discussion";
/// A title left empty (`mt_agenda_unnamed_topic_title`).
pub const UNNAMED: &str = "Unnamed Topic";

pub fn duration(s: &Value) -> i64 {
    s.get("originalDuration").and_then(Value::as_f64).unwrap_or(0.0) as i64
}

pub fn title(s: &Value) -> &str {
    s.get("title").and_then(Value::as_str).unwrap_or_default()
}

/// A topic's lifecycle stage as Teams shows it (NotStarted, InProgress,
/// Done; the Facilitator sets `topicLifecycleStage` as the meeting goes,
/// a person's mark goes in `topicLifecycleUserOverride`, which wins).
/// Teams 26304 checks topics off by this when a topic has one (seen live
/// 2026-11-20 in "OST TEST 73 sync").
pub fn lifecycle(s: &Value) -> Option<&str> {
    // Only the stages Teams knows count: a topic with another value
    // ("InProgress" tried live) is shown the older way, discussed or not.
    fn known(v: &Value) -> Option<&str> {
        v.as_str().filter(|v| *v == DONE || *v == NOT_STARTED)
    }
    s.get("topicLifecycleUserOverride")
        .and_then(known)
        .or_else(|| s.get("topicLifecycleStage").and_then(known))
}

pub const DONE: &str = "Done";
pub const NOT_STARTED: &str = "NotStarted";

/// Whether a topic counts as discussed: its lifecycle stage is Done when it
/// has one; otherwise (Teams' module 624328 `g`) the first of the user's
/// override, `isDiscussed` and the relevance score that is set.
pub fn discussed(s: &Value) -> bool {
    if let Some(stage) = lifecycle(s) {
        return stage == DONE;
    }
    if let Some(v) = s.get("topicRelevanceUserOverride").and_then(Value::as_bool) {
        return v;
    }
    if let Some(v) = s.get("isDiscussed").and_then(Value::as_bool) {
        return v;
    }
    s.get("relevanceScore").and_then(Value::as_f64).is_some_and(|r| r >= DISCUSSED_SCORE)
}

fn is_open_discussion(s: &Value) -> bool {
    title(s).trim().eq_ignore_ascii_case(OPEN_DISCUSSION)
}

/// A duration in whole minutes, at least 1 (Teams' `max(1, round)`).
pub fn minutes(ms: i64) -> i64 {
    ((ms as f64 / MINUTE as f64).round() as i64).max(1)
}

/// The time of each topic already used up: `clamp(elapsed − start, 0,
/// duration)`.
fn elapsed_within(sections: &[Value], elapsed_ms: i64) -> Vec<i64> {
    let mut start = 0;
    sections
        .iter()
        .map(|s| {
            let d = duration(s);
            let e = (elapsed_ms - start).clamp(0, d.max(0));
            start += d;
            e
        })
        .collect()
}

/// The topic whose span holds `elapsed_ms` (the last one once the agenda
/// is over time; the first before it starts).
pub fn current_index(sections: &[Value], elapsed_ms: i64) -> usize {
    let mut end = 0;
    for (i, s) in sections.iter().enumerate() {
        end += duration(s);
        if elapsed_ms < end {
            return i;
        }
    }
    sections.len().saturating_sub(1)
}

fn set_minutes(sections: &[Value], mins: &[i64]) -> Vec<Value> {
    sections
        .iter()
        .zip(mins)
        .map(|(s, m)| {
            let mut s = s.clone();
            s["originalDuration"] = json!(m * MINUTE);
            s
        })
        .collect()
}

/// How many minutes Add topic can free (Teams' `In`): at most 5, from
/// Open discussion and from every other topic down to 1 minute.
pub fn add_available(sections: &[Value]) -> i64 {
    let open: i64 = sections.iter().filter(|s| is_open_discussion(s)).map(|s| minutes(duration(s))).sum();
    let others: i64 = sections.iter().filter(|s| !is_open_discussion(s)).map(|s| minutes(duration(s)) - 1).sum();
    (open + others).min(NEW_TOPIC_MINUTES)
}

/// Add topic (Teams' `Gi`): a new, untitled topic of up to 5 minutes taken
/// one minute at a time from the largest donor — Open discussion first,
/// then topics not yet over, down to 5 minutes (or what has run), then any
/// topic, down to 1 minute (or what has run). It goes where Open discussion
/// was, else last; Open discussion goes once empty. `None` when no minute
/// can be freed. Returns the sections and the new topic's index.
pub fn add_topic(sections: &[Value], elapsed_ms: i64) -> Option<(Vec<Value>, usize)> {
    let want = add_available(sections);
    if want < 1 {
        return None;
    }
    let ran = elapsed_within(sections, elapsed_ms);
    let ran_min: Vec<i64> = ran.iter().map(|e| (*e as f64 / MINUTE as f64).ceil() as i64).collect();
    let mut mins: Vec<i64> = sections
        .iter()
        .map(|s| if is_open_discussion(s) { (duration(s) as f64 / MINUTE as f64).round() as i64 } else { minutes(duration(s)) })
        .collect();
    let open = sections.iter().position(is_open_discussion);
    let mut taken = 0;
    while taken < want {
        let donor = if let Some(o) = open.filter(|o| mins[*o] > 0) {
            Some(o)
        } else {
            let pick = |floor: &dyn Fn(usize) -> i64, only_open: bool| {
                (0..sections.len())
                    .filter(|i| Some(*i) != open)
                    .filter(|i| !only_open || ran[*i] < duration(&sections[*i]))
                    .filter(|i| mins[*i] > floor(*i))
                    .max_by_key(|i| (mins[*i], std::cmp::Reverse(*i)))
            };
            pick(&|i| ran_min[i].max(NEW_TOPIC_MINUTES), true).or_else(|| pick(&|i| ran_min[i].max(1), false))
        };
        let Some(d) = donor else { break };
        mins[d] -= 1;
        taken += 1;
    }
    if taken < 1 {
        return None;
    }
    let mut out = set_minutes(sections, &mins);
    let at = open.unwrap_or(out.len());
    out.insert(
        at,
        json!({"title": "", "originalDuration": taken * MINUTE, "isDiscussed": false, "topicRelevanceUserOverride": false}),
    );
    if let Some(o) = open
        && mins[o] <= 0
    {
        out.remove(o + 1);
    }
    Some((out, at))
}

/// Delete topic (Teams' `Ki`): its minutes go one at a time to the
/// smallest undiscussed topic (not Open discussion), else to the topics
/// before it (the nearest first, filling each), else to the smallest
/// topic; none above 999 minutes. The last topic can't go.
pub fn delete_topic(sections: &[Value], index: usize) -> Option<Vec<Value>> {
    if sections.len() <= 1 || index >= sections.len() {
        return None;
    }
    let give = minutes(duration(&sections[index]));
    let mut rest: Vec<Value> = sections.to_vec();
    rest.remove(index);
    let mut mins: Vec<i64> = rest.iter().map(|s| minutes(duration(s))).collect();
    for _ in 0..give {
        let room = |i: usize, m: &[i64]| m[i] < MAX_MINUTES;
        let undiscussed = (0..rest.len())
            .filter(|i| !discussed(&rest[*i]) && !is_open_discussion(&rest[*i]) && room(*i, &mins))
            .min_by_key(|i| (mins[*i], *i));
        let before = (0..index.min(rest.len())).rev().find(|i| room(*i, &mins));
        let any = (0..rest.len()).filter(|i| room(*i, &mins)).min_by_key(|i| (mins[*i], *i));
        let Some(t) = undiscussed.or(before).or(any) else { break };
        mins[t] += 1;
    }
    Some(set_minutes(&rest, &mins))
}

/// Rename (Teams' `Fi`): trimmed, at most 100 characters, "Unnamed Topic"
/// when empty, and unique (case-insensitive) with " 2", " 3", … appended.
/// `None` when the title doesn't change.
pub fn rename(sections: &[Value], index: usize, draft: &str) -> Option<Vec<Value>> {
    let old = sections.get(index)?;
    let mut t: String = draft.trim().chars().take(MAX_TITLE).collect();
    if t.is_empty() {
        t = UNNAMED.to_string();
    }
    let taken: Vec<String> = sections
        .iter()
        .enumerate()
        .filter(|(i, _)| *i != index)
        .map(|(_, s)| title(s).trim().to_lowercase())
        .collect();
    if taken.contains(&t.to_lowercase()) {
        // "Budget 2" when "Budget" exists counts from "Budget".
        let base = match t.rsplit_once(' ') {
            Some((b, n)) if n.parse::<u32>().is_ok() && taken.contains(&b.to_lowercase()) => b.to_string(),
            _ => t.clone(),
        };
        if let Some(n) = (2..=999).find(|n| !taken.contains(&format!("{base} {n}").to_lowercase())) {
            t = format!("{base} {n}");
        }
    }
    if t == title(old).trim() {
        return None;
    }
    let mut out = sections.to_vec();
    out[index]["title"] = json!(t);
    Some(out)
}

/// Mark discussed / not discussed: both `isDiscussed` and the user's
/// override.
pub fn toggle_discussed(sections: &[Value], index: usize) -> Option<Vec<Value>> {
    let section = sections.get(index)?;
    let v = !discussed(section);
    let staged = lifecycle(section).is_some();
    let mut out = sections.to_vec();
    out[index]["isDiscussed"] = json!(v);
    out[index]["topicRelevanceUserOverride"] = json!(v);
    // With a lifecycle stage, Teams marks it Done (the person's override
    // too) or puts it back to NotStarted, dropping the override.
    if staged && let Some(o) = out[index].as_object_mut() {
        o.insert("topicLifecycleStage".into(), json!(if v { DONE } else { NOT_STARTED }));
        if v {
            o.insert("topicLifecycleUserOverride".into(), json!(DONE));
        } else {
            o.remove("topicLifecycleUserOverride");
        }
    }
    Some(out)
}

/// Move left / Move right (and keyboard or drag reorders): the topic
/// changes place; its time goes with it.
pub fn move_topic(sections: &[Value], from: usize, to: usize) -> Option<Vec<Value>> {
    if from >= sections.len() || to >= sections.len() || from == to {
        return None;
    }
    let mut out = sections.to_vec();
    let s = out.remove(from);
    out.insert(to, s);
    Some(out)
}

/// Resize at the divider after topic `divider` by `delta_ms` (snapped to
/// whole minutes): to the right the left topic grows, taking from the next
/// topic, then the one after, …; to the left the right topic grows,
/// taking from the topic before, then the one before that. Every topic
/// stays within 1–999 minutes.
pub fn resize(sections: &[Value], divider: usize, delta_ms: i64) -> Option<Vec<Value>> {
    if divider + 1 >= sections.len() {
        return None;
    }
    let mut mins: Vec<i64> = sections.iter().map(|s| minutes(duration(s)).min(MAX_MINUTES)).collect();
    let steps = (delta_ms as f64 / MINUTE as f64).round() as i64;
    let (grow, donors): (usize, Vec<usize>) = if steps >= 0 {
        (divider, (divider + 1..sections.len()).collect())
    } else {
        (divider + 1, (0..=divider).rev().collect())
    };
    for _ in 0..steps.abs() {
        if mins[grow] >= MAX_MINUTES {
            break;
        }
        let Some(d) = donors.iter().copied().find(|d| mins[*d] > 1) else { break };
        mins[d] -= 1;
        mins[grow] += 1;
    }
    Some(set_minutes(sections, &mins))
}

/// The agenda with new sections, as Teams publishes an edit
/// (`applySectionsUpdate`): a cancelled agenda's remaining time becomes the
/// new total; a running one gains any growth of the total.
pub fn with_sections(agenda: &Timer, sections: Vec<Value>) -> Timer {
    let total: i64 = sections.iter().map(duration).sum();
    let mut v = agenda.0.clone();
    if !v.is_object() {
        v = json!({});
    }
    let state = agenda.state().to_string();
    if state == CANCELLED {
        v["remainingDuration"] = json!(total);
    } else if state == IN_PROGRESS {
        let growth = (total - agenda.total_ms()).max(0);
        if growth > 0 {
            v["remainingDuration"] = json!(agenda.remaining_ms() + growth);
        }
    }
    v["sections"] = Value::Array(sections);
    Timer(v)
}

/// Cancel tracker for all (Teams' `Ac.ae`): cancelled, no sections, no
/// time stamp.
pub fn cancel(agenda: &Timer) -> Timer {
    let mut v = agenda.0.clone();
    if let Some(o) = v.as_object_mut() {
        o.insert("state".into(), CANCELLED.into());
        o.remove("lastEditTime");
        o.remove("previousState");
        o.insert("remainingDuration".into(), 0.into());
        o.insert("sections".into(), json!([]));
        o.insert("generatingAgenda".into(), false.into());
    }
    Timer(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn agenda(spec: &[(&str, i64)]) -> Vec<Value> {
        spec.iter().map(|(t, m)| json!({"title": t, "originalDuration": m * MINUTE})).collect()
    }

    fn mins(s: &[Value]) -> Vec<i64> {
        s.iter().map(|x| duration(x) / MINUTE).collect()
    }

    #[test]
    fn discussed_takes_the_first_set_flag() {
        assert!(discussed(&json!({"relevanceScore": 3})));
        assert!(!discussed(&json!({"relevanceScore": 3, "isDiscussed": false})));
        assert!(discussed(&json!({"isDiscussed": false, "topicRelevanceUserOverride": true})));
        assert!(!discussed(&json!({})));
    }

    #[test]
    fn add_takes_from_the_largest_topics() {
        let s = agenda(&[("A", 5), ("B", 10), ("C", 10), ("D", 5)]);
        let (out, at) = add_topic(&s, 0).unwrap();
        assert_eq!(at, 4);
        // 5 minutes, one at a time from the largest (B, C, B, C, B).
        assert_eq!(mins(&out), vec![5, 7, 8, 5, 5]);
        assert_eq!(title(&out[4]), "");
        assert_eq!(mins(&out).iter().sum::<i64>(), 30);
    }

    #[test]
    fn add_uses_open_discussion_first() {
        let s = agenda(&[("A", 10), ("Open discussion", 3)]);
        let (out, at) = add_topic(&s, 0).unwrap();
        assert_eq!(at, 1);
        // 3 from Open discussion (then gone), 2 from A.
        assert_eq!(mins(&out), vec![8, 5]);
        assert_eq!(out.len(), 2);
    }

    #[test]
    fn add_needs_a_free_minute() {
        assert!(add_topic(&agenda(&[("A", 1)]), 0).is_none());
        assert_eq!(add_available(&agenda(&[("A", 2), ("B", 1)])), 1);
    }

    #[test]
    fn delete_gives_to_undiscussed_then_earlier_topics() {
        let mut s = agenda(&[("A", 5), ("B", 10), ("C", 10), ("D", 5)]);
        let out = delete_topic(&s, 1).unwrap();
        // 10 minutes to the smallest undiscussed, one at a time.
        assert_eq!(mins(&out), vec![10, 10, 10]);
        s[0]["isDiscussed"] = json!(true);
        s[2]["isDiscussed"] = json!(true);
        s[3]["isDiscussed"] = json!(true);
        let out = delete_topic(&s, 1).unwrap();
        // No undiscussed topic left: the one before it takes them all.
        assert_eq!(mins(&out), vec![15, 10, 5]);
        assert!(delete_topic(&agenda(&[("A", 5)]), 0).is_none());
    }

    #[test]
    fn rename_trims_and_numbers_duplicates() {
        let s = agenda(&[("Budget", 5), ("Next", 5), ("Budget 2", 5)]);
        assert_eq!(title(&rename(&s, 1, "  budget ").unwrap()[1]), "budget 3");
        assert_eq!(title(&rename(&s, 1, "").unwrap()[1]), UNNAMED);
        assert!(rename(&s, 1, " Next ").is_none());
    }

    #[test]
    fn lifecycle_stage_decides_discussed_and_is_toggled() {
        let s = vec![json!({"title": "A", "originalDuration": 300000, "isDiscussed": true, "topicLifecycleStage": "NotStarted"})];
        assert!(!discussed(&s[0]));
        let done = toggle_discussed(&s, 0).unwrap();
        assert_eq!(done[0]["topicLifecycleStage"], json!("Done"));
        assert_eq!(done[0]["topicLifecycleUserOverride"], json!("Done"));
        assert!(discussed(&done[0]));
        let back = toggle_discussed(&done, 0).unwrap();
        assert_eq!(back[0]["topicLifecycleStage"], json!("NotStarted"));
        assert!(back[0].get("topicLifecycleUserOverride").is_none());
        assert_eq!(back[0]["isDiscussed"], json!(false));
        // The person's override wins over the Facilitator's stage.
        assert!(discussed(&json!({"topicLifecycleStage": "InProgress", "topicLifecycleUserOverride": "Done"})));
        // A stage Teams doesn't know: the older rule.
        assert!(discussed(&json!({"topicLifecycleStage": "InProgress", "isDiscussed": true})));
    }

    #[test]
    fn toggles_and_moves() {
        let s = agenda(&[("A", 5), ("B", 10)]);
        let t = toggle_discussed(&s, 0).unwrap();
        assert!(discussed(&t[0]) && t[0]["isDiscussed"] == json!(true));
        assert!(!discussed(&toggle_discussed(&t, 0).unwrap()[0]));
        assert_eq!(title(&move_topic(&s, 1, 0).unwrap()[0]), "B");
    }

    #[test]
    fn resize_cascades_and_keeps_a_minute() {
        let s = agenda(&[("A", 5), ("B", 2), ("C", 10)]);
        // Right: A grows from B (down to 1), then C.
        assert_eq!(mins(&resize(&s, 0, 4 * MINUTE).unwrap()), vec![9, 1, 7]);
        // Left at B|C: C grows from B, then A.
        assert_eq!(mins(&resize(&s, 1, -3 * MINUTE).unwrap()), vec![3, 1, 13]);
        assert_eq!(mins(&resize(&s, 0, 20 * MINUTE).unwrap()), vec![15, 1, 1]);
    }

    #[test]
    fn edits_publish_the_whole_agenda() {
        let t = Timer(json!({"state": "InProgress", "remainingDuration": 600000, "sections": agenda(&[("A", 10)])}));
        let grown = with_sections(&t, agenda(&[("A", 12)]));
        assert_eq!(grown.remaining_ms(), 720000);
        let c = Timer(json!({"state": "Cancelled", "remainingDuration": 0, "sections": []}));
        assert_eq!(with_sections(&c, agenda(&[("A", 7)])).remaining_ms(), 420000);
        let gone = cancel(&grown);
        assert_eq!(gone.state(), "Cancelled");
        assert_eq!(gone.0["sections"], json!([]));
        assert!(gone.0.get("lastEditTime").is_none());
    }

    #[test]
    fn current_topic_follows_the_time() {
        let s = agenda(&[("A", 5), ("B", 10)]);
        assert_eq!(current_index(&s, -1000), 0);
        assert_eq!(current_index(&s, 6 * MINUTE), 1);
        assert_eq!(current_index(&s, 99 * MINUTE), 1);
    }
}
