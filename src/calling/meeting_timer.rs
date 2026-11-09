//! Teams' meeting timer (More ▸ Timer), as its lazy-meeting-timer bundle
//! keeps it (research: scratchpad timer/spec.md, session 744c3998).
//!
//! - **Shared state.** The conversation's meeting state `timer`:
//!   `{sequenceNumber, value: {data: "<JSON {adhocTimer, agendaTimer,
//!   rosTimer}>", lastEditTime}}`. The service stamps the outer
//!   `lastEditTime`; a client writes only `data` (with the last
//!   `sequenceNumber` it saw) to the conversation's `updateMeetingStates`
//!   link, and sees its change when the update comes back to everyone.
//! - **A timer.** `{state: InProgress | Paused | Cancelled,
//!   remainingDuration (ms, as of lastEditTime), lastEditTime,
//!   previousState, sections: [{title, originalDuration}], pendingConsent,
//!   consentRequested, …}`. Leaving `lastEditTime` out means "from now":
//!   the service's stamp anchors it.
//! - **Receiving** ([`normalise`]): a timer that was running since its own
//!   `lastEditTime` loses the time up to the service's stamp, which becomes
//!   its `lastEditTime`.
//! - The ad-hoc timer has exactly one section, titled "". Agenda and Run
//!   of Show need Teams' Facilitator (Copilot) and are kept as they come.

use serde_json::{Value, json};

/// The longest ad-hoc timer, 99:59 (Teams' `rG`).
pub const MAX_MS: i64 = (99 * 60 + 59) * 1000;
/// A new timer's length until one has run (05:00).
pub const DEFAULT_MS: i64 = 5 * 60 * 1000;
/// "+1 min", "+5 min", "+10 min".
pub const ADD_MINUTES: [i64; 3] = [1, 5, 10];

pub const IN_PROGRESS: &str = "InProgress";
pub const PAUSED: &str = "Paused";
pub const CANCELLED: &str = "Cancelled";

/// A timer's state as it came (an object Teams would accept, or a default).
#[derive(Debug, Clone, PartialEq)]
pub struct Timer(pub Value);

impl Timer {
    /// Teams' local default: Cancelled, 5:00 (an agenda has no sections).
    pub fn default_adhoc() -> Self {
        Self(json!({
            "state": CANCELLED,
            "remainingDuration": DEFAULT_MS,
            "sections": [{"title": "", "originalDuration": DEFAULT_MS}],
            "pendingConsent": false,
            "consentRequested": false,
        }))
    }

    pub fn default_agenda() -> Self {
        let mut t = Self::default_adhoc();
        t.0["sections"] = json!([]);
        t
    }

    pub fn state(&self) -> &str {
        self.0
            .get("state")
            .and_then(Value::as_str)
            .unwrap_or(CANCELLED)
    }

    pub fn remaining_ms(&self) -> i64 {
        self.0
            .get("remainingDuration")
            .and_then(Value::as_f64)
            .unwrap_or(0.0) as i64
    }

    pub fn last_edit_ms(&self) -> Option<i64> {
        self.0
            .get("lastEditTime")
            .and_then(Value::as_str)
            .and_then(parse_time)
    }

    /// The sections' total, at least 1 ms (Teams' `t1`).
    pub fn total_ms(&self) -> i64 {
        let sum: i64 = self
            .0
            .get("sections")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|s| s.get("originalDuration").and_then(Value::as_f64))
            .map(|d| d as i64)
            .sum();
        sum.max(1)
    }

    /// How long it has run (Teams' `Yh`): the part already used up, plus,
    /// while it runs, the time since `lastEditTime` (less the clock skew).
    pub fn elapsed_ms(&self, now_ms: i64, skew_ms: i64) -> i64 {
        let mut e = self.total_ms() - self.remaining_ms();
        if self.state() == IN_PROGRESS
            && let Some(at) = self.last_edit_ms()
        {
            e += (now_ms - at - skew_ms).max(0);
        }
        e
    }

    /// Running or paused past its end (Teams keeps counting below zero).
    pub fn over_time(&self, now_ms: i64, skew_ms: i64) -> bool {
        matches!(self.state(), IN_PROGRESS | PAUSED)
            && self.elapsed_ms(now_ms, skew_ms) >= self.total_ms()
    }

    fn with(&self, f: impl FnOnce(&mut serde_json::Map<String, Value>)) -> Self {
        let mut v = self.0.clone();
        if let Some(o) = v.as_object_mut() {
            f(o);
        }
        Self(v)
    }

    fn section_title(&self) -> String {
        self.0
            .pointer("/sections/0/title")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    }

    /// ▶ on a cancelled timer: run its configured length from now.
    pub fn start(&self) -> Self {
        let total = self.total_ms();
        let title = self.section_title();
        self.with(|o| {
            o.insert("state".into(), IN_PROGRESS.into());
            o.insert("remainingDuration".into(), total.into());
            o.remove("lastEditTime");
            o.insert(
                "sections".into(),
                json!([{"title": title, "originalDuration": total}]),
            );
        })
    }

    pub fn pause(&self) -> Self {
        self.with(|o| {
            o.insert("state".into(), PAUSED.into());
        })
    }

    pub fn resume(&self) -> Self {
        self.with(|o| {
            o.insert("state".into(), IN_PROGRESS.into());
        })
    }

    /// ↻: back to its full length, running.
    pub fn reset(&self) -> Self {
        let total = self.total_ms();
        self.with(|o| {
            o.insert("state".into(), IN_PROGRESS.into());
            o.insert("remainingDuration".into(), total.into());
            o.remove("lastEditTime");
        })
    }

    /// "Cancel timer for everyone" once it's over time.
    pub fn cancel_over_time(&self) -> Self {
        self.with(|o| {
            o.insert("state".into(), CANCELLED.into());
            o.insert("remainingDuration".into(), 0.into());
            o.remove("lastEditTime");
        })
    }

    /// The popover's "Cancel timer": stopped, its length kept as the next
    /// timer's.
    pub fn cancel(&self) -> Self {
        let length = self
            .0
            .pointer("/sections/0/originalDuration")
            .and_then(Value::as_f64)
            .unwrap_or(0.0) as i64;
        self.with(|o| {
            o.insert("state".into(), CANCELLED.into());
            o.remove("lastEditTime");
            o.insert("remainingDuration".into(), length.into());
            o.remove("previousState");
        })
    }

    /// The popover's Start: a new timer of `ms`.
    pub fn start_with(&self, ms: i64) -> Self {
        let title = self.section_title();
        self.with(|o| {
            o.insert("state".into(), IN_PROGRESS.into());
            o.insert(
                "sections".into(),
                json!([{"title": title, "originalDuration": ms}]),
            );
            o.insert("remainingDuration".into(), ms.into());
            o.remove("lastEditTime");
        })
    }

    /// "+N min" outside edit mode. It always runs afterwards (adding time
    /// to a paused timer resumes it).
    pub fn add_minutes(&self, minutes: i64, now_ms: i64, skew_ms: i64) -> Self {
        let d = minutes * 60_000;
        let total = self.total_ms();
        let title = self.section_title();
        let (remaining, original, keep_time) = if self.state() == CANCELLED {
            (total + d, total + d, false)
        } else if self.over_time(now_ms, skew_ms) {
            (d, total.max(d), false)
        } else {
            (self.remaining_ms() + d, (total + d).min(MAX_MS), true)
        };
        self.with(|o| {
            o.insert("state".into(), IN_PROGRESS.into());
            o.insert("remainingDuration".into(), remaining.into());
            o.insert(
                "sections".into(),
                json!([{"title": title, "originalDuration": original}]),
            );
            if !keep_time {
                o.remove("lastEditTime");
            }
        })
    }

    /// Whether "+N min" is offered outside edit mode (Teams disables it
    /// past 99:59; never once over time).
    pub fn can_add(&self, minutes: i64, now_ms: i64, skew_ms: i64) -> bool {
        if self.over_time(now_ms, skew_ms) {
            return true;
        }
        let left = if self.state() == CANCELLED {
            self.total_ms()
        } else {
            self.total_ms() - self.elapsed_ms(now_ms, skew_ms)
        };
        left + minutes * 60_000 <= MAX_MS
    }

    /// Teams' check of an ad-hoc timer that came in; None when it's fine.
    pub fn adhoc_error(&self) -> Option<&'static str> {
        let o = self.0.as_object()?;
        if !matches!(
            self.0.get("state").and_then(Value::as_str),
            Some(IN_PROGRESS | PAUSED | CANCELLED)
        ) {
            return Some("InvalidState");
        }
        if o.get("lastEditTime").is_some_and(|t| !t.is_string()) {
            return Some("InvalidLastEditTime");
        }
        let Some(remaining) = o.get("remainingDuration").and_then(Value::as_f64) else {
            return Some("InvalidRemainingDuration");
        };
        if remaining as i64 > MAX_MS {
            return Some("RemainingDurationTooLong");
        }
        let Some(sections) = o.get("sections").and_then(Value::as_array) else {
            return Some("InvalidSections");
        };
        if sections.len() != 1 {
            return Some("AdhocTimerMultipleSections");
        }
        let s = &sections[0];
        if s.get("title").and_then(Value::as_str) != Some("") {
            return Some("AdhocTimerNonEmptyTitle");
        }
        match s.get("originalDuration").and_then(Value::as_f64) {
            Some(d) if (0.0..=MAX_MS as f64).contains(&d) => {}
            _ => return Some("InvalidSectionDuration"),
        }
        if self.total_ms() < remaining as i64 {
            return Some("RemainingTimeGreaterThanTotalDuration");
        }
        None
    }
}

/// An ISO time as Unix ms (Teams' times carry up to 7 fraction digits).
pub fn parse_time(s: &str) -> Option<i64> {
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|t| t.timestamp_millis())
}

/// Teams' normalisation of a timer that came in, with the service's stamp
/// `stamp` (its module 357072 `H`).
pub fn normalise(timer: &Timer, stamp: &str) -> Timer {
    let Some(stamp_ms) = parse_time(stamp) else {
        return timer.clone();
    };
    let no_time = timer.last_edit_ms().is_none();
    let previous = timer.0.get("previousState").and_then(Value::as_str);
    let was_running = previous == Some(IN_PROGRESS);
    let changed = previous != Some(timer.state());
    let adjust = !no_time && was_running;
    let mut v = timer.0.clone();
    if let Some(o) = v.as_object_mut() {
        if adjust {
            let since = stamp_ms - timer.last_edit_ms().unwrap_or(stamp_ms);
            o.insert(
                "remainingDuration".into(),
                (timer.remaining_ms() - since).into(),
            );
        }
        if adjust || changed || no_time {
            o.insert("lastEditTime".into(), stamp.into());
            o.insert("previousState".into(), timer.state().into());
        }
    }
    Timer(v)
}

/// The meeting's three timers as last received.
#[derive(Debug, Clone, PartialEq)]
pub struct Timers {
    pub sequence: u64,
    /// The service's stamp of this state (Unix ms).
    pub stamp_ms: Option<i64>,
    pub adhoc: Timer,
    pub agenda: Timer,
    pub ros: Timer,
}

impl Default for Timers {
    fn default() -> Self {
        Self {
            sequence: 0,
            stamp_ms: None,
            adhoc: Timer::default_adhoc(),
            agenda: Timer::default_agenda(),
            ros: Timer::default_adhoc(),
        }
    }
}

impl Timers {
    /// The `timer` meeting state (`{sequenceNumber, value}`, the value as
    /// an object or a JSON string), normalised. `previous` supplies what an
    /// update leaves out or Teams would refuse.
    pub fn from_state(state: &Value, previous: &Timers) -> Option<Self> {
        let sequence = state.get("sequenceNumber").and_then(Value::as_u64)?;
        let value = match state.get("value")? {
            Value::String(s) => serde_json::from_str::<Value>(s).ok()?,
            v => v.clone(),
        };
        let stamp = value
            .get("lastEditTime")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let data: Value = match value.get("data")? {
            Value::String(s) => serde_json::from_str(s).ok()?,
            v => v.clone(),
        };
        let take = |key: &str, before: &Timer, check: bool| -> Timer {
            match data.get(key) {
                Some(t) if t.is_object() => {
                    let t = Timer(t.clone());
                    if check && let Some(err) = t.adhoc_error() {
                        tracing::warn!(
                            err,
                            "meeting timer: ignoring an ad-hoc timer Teams would refuse"
                        );
                        return before.clone();
                    }
                    normalise(&t, &stamp)
                }
                _ => before.clone(),
            }
        };
        Some(Self {
            sequence,
            stamp_ms: parse_time(&stamp),
            adhoc: take("adhocTimer", &previous.adhoc, true),
            agenda: take("agendaTimer", &previous.agenda, false),
            ros: take("rosTimer", &previous.ros, false),
        })
    }

    /// The `timer` meeting state in a conversation update or join response.
    pub fn find(event: &Value) -> Option<&Value> {
        [
            "/body/meetingStates/timer",
            "/meetingStates/timer",
            "/conversationResponse/meetingStates/timer",
        ]
        .iter()
        .find_map(|p| event.pointer(p))
    }

    /// What to send for a new ad-hoc timer: the three timers' JSON (the
    /// others as last received), with the last sequence number seen.
    pub fn publish(&self, adhoc: &Timer) -> Value {
        let data = json!({
            "adhocTimer": adhoc.0,
            "agendaTimer": self.agenda.0,
            "rosTimer": self.ros.0,
        });
        json!({
            "timer": {
                "sequenceNumber": self.sequence,
                "value": {"data": data.to_string()},
            }
        })
    }
}

/// The countdown as Teams writes it (`zs`): mm:ss with the seconds rounded
/// up, "-" once over time, at most 99:59.
pub fn countdown(remaining_ms: i64) -> String {
    let neg = remaining_ms <= -1000;
    let mut m = remaining_ms.abs() / 60_000;
    // JavaScript's ceil of the signed rest: up while counting down, toward
    // zero once over time.
    let mut s = ((remaining_ms % 60_000) as f64 / 1000.0).ceil().abs() as i64;
    if s == 60 {
        m += 1;
        s = 0;
    }
    if neg && (m > 99 || (m == 99 && s > 59)) {
        m = 99;
        s = 59;
    }
    format!("{}{m:02}:{s:02}", if neg { "-" } else { "" })
}

/// The spoken form ("4 min, 30 sec", "5 min", "10 sec"; seconds rounded up).
pub fn spoken(ms: i64) -> String {
    if ms <= 0 {
        return "0 sec".into();
    }
    let total_s = (ms + 999) / 1000;
    let (m, s) = (total_s / 60, total_s % 60);
    match (m, s) {
        (0, s) => format!("{s} sec"),
        (m, 0) => format!("{m} min"),
        (m, s) => format!("{m} min, {s} sec"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const UPDATE: &str = r#"{"sequenceNumber":4,"value":{"data":"{\"adhocTimer\":{\"state\":\"Paused\",\"remainingDuration\":263298,\"sections\":[{\"title\":\"\",\"originalDuration\":300000}],\"pendingConsent\":false,\"consentRequested\":false,\"lastEditTime\":\"2026-11-09T05:13:16.6997832Z\",\"previousState\":\"InProgress\"},\"agendaTimer\":{\"state\":\"Cancelled\",\"remainingDuration\":300000,\"sections\":[],\"pendingConsent\":false,\"consentRequested\":false,\"lastEditTime\":\"2026-11-09T05:12:08.0257906Z\",\"previousState\":\"Cancelled\"},\"rosTimer\":{\"state\":\"Cancelled\",\"remainingDuration\":300000,\"sections\":[{\"title\":\"\",\"originalDuration\":300000}],\"pendingConsent\":false,\"consentRequested\":false,\"lastEditTime\":\"2026-11-09T05:12:08.0257906Z\",\"previousState\":\"Cancelled\"}}","lastEditTime":"2026-11-09T05:16:14.1413712Z"}}"#;

    #[test]
    fn a_paused_timer_loses_the_time_it_ran_before_the_pause() {
        let state: Value = serde_json::from_str(UPDATE).unwrap();
        let t = Timers::from_state(&state, &Timers::default()).unwrap();
        assert_eq!(t.sequence, 4);
        // Ran from 05:13:16.699 to the stamp 05:16:14.141 (ms, as JavaScript
        // reads them): 177.442 s.
        assert_eq!(t.adhoc.remaining_ms(), 263_298 - 177_442);
        assert_eq!(t.adhoc.state(), PAUSED);
        assert_eq!(t.adhoc.0["previousState"], PAUSED);
        assert_eq!(
            t.adhoc.last_edit_ms(),
            parse_time("2026-11-09T05:16:14.1413712Z")
        );
        // Paused: the clock doesn't move it.
        let later = t.adhoc.last_edit_ms().unwrap() + 60_000;
        assert_eq!(t.adhoc.elapsed_ms(later, 0), 300_000 - 85_856);
        assert_eq!(
            countdown(t.adhoc.total_ms() - t.adhoc.elapsed_ms(later, 0)),
            "01:26"
        );
    }

    #[test]
    fn actions_send_what_teams_sends() {
        let t = Timer::default_adhoc();
        let started = t.start();
        assert_eq!(started.state(), IN_PROGRESS);
        assert_eq!(started.remaining_ms(), 300_000);
        assert!(started.0.get("lastEditTime").is_none());
        let running = normalise(&started, "2026-11-09T06:00:00Z");
        let now = parse_time("2026-11-09T06:01:00Z").unwrap();
        assert_eq!(
            countdown(running.total_ms() - running.elapsed_ms(now, 0)),
            "04:00"
        );
        // +5 min on a running timer keeps its anchor.
        let added = running.add_minutes(5, now, 0);
        assert_eq!(added.remaining_ms(), 600_000);
        assert_eq!(added.total_ms(), 600_000);
        assert!(added.0.get("lastEditTime").is_some());
        // Adding to a paused timer resumes it.
        assert_eq!(running.pause().add_minutes(1, now, 0).state(), IN_PROGRESS);
        // Reset runs it from the top.
        let reset = running.reset();
        assert_eq!(
            (reset.state(), reset.remaining_ms()),
            (IN_PROGRESS, 300_000)
        );
        // The popover's Cancel keeps the length for next time.
        let cancelled = running.cancel();
        assert_eq!(
            (cancelled.state(), cancelled.remaining_ms()),
            (CANCELLED, 300_000)
        );
        assert!(cancelled.0.get("previousState").is_none());
        let new = cancelled.start_with(90_000);
        assert_eq!((new.total_ms(), new.remaining_ms()), (90_000, 90_000));
        assert_eq!(new.adhoc_error(), None);
    }

    #[test]
    fn over_time_counts_below_zero() {
        let running = normalise(
            &Timer::default_adhoc().start_with(60_000),
            "2026-11-09T06:00:00Z",
        );
        let now = parse_time("2026-11-09T06:01:30Z").unwrap();
        assert!(running.over_time(now, 0));
        assert_eq!(
            countdown(running.total_ms() - running.elapsed_ms(now, 0)),
            "-00:30"
        );
        let after = running.add_minutes(10, now, 0);
        assert_eq!((after.remaining_ms(), after.total_ms()), (600_000, 600_000));
        assert!(after.0.get("lastEditTime").is_none());
        assert_eq!(running.cancel_over_time().remaining_ms(), 0);
    }

    #[test]
    fn display_rounds_seconds_up_and_caps() {
        assert_eq!(countdown(299_200), "05:00");
        assert_eq!(countdown(59_001), "01:00");
        assert_eq!(countdown(0), "00:00");
        assert_eq!(countdown(-500), "00:00");
        assert_eq!(countdown(-30_500), "-00:30");
        assert_eq!(countdown(-200 * 60_000), "-99:59");
        assert_eq!(spoken(270_000), "4 min, 30 sec");
        assert_eq!(spoken(300_000), "5 min");
        assert_eq!(spoken(9_200), "10 sec");
    }

    #[test]
    fn refused_and_partial_updates_keep_what_was_known() {
        let bad = json!({"sequenceNumber": 7, "value": {"data": "{\"adhocTimer\":{\"state\":\"Configuring\",\"remainingDuration\":1,\"sections\":[{\"title\":\"\",\"originalDuration\":1}]}}", "lastEditTime": "2026-11-09T06:00:00Z"}});
        let t = Timers::from_state(&bad, &Timers::default()).unwrap();
        assert_eq!(t.adhoc, Timer::default_adhoc());
        assert_eq!(t.sequence, 7);
        let body = t.publish(&t.adhoc.start());
        assert_eq!(body["timer"]["sequenceNumber"], 7);
        let data: Value =
            serde_json::from_str(body["timer"]["value"]["data"].as_str().unwrap()).unwrap();
        assert_eq!(data["adhocTimer"]["state"], IN_PROGRESS);
        assert!(
            data["agendaTimer"]["sections"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    }
}
