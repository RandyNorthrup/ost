//! Real-time text (RTT) in meetings, as Teams does it (calling's
//! RealTimeTextMixin and its captions window; measured on winpc,
//! 2026-11-09).
//!
//! - **On.** More ▸ Language and speech ▸ "Turn on RTT for this call" (after
//!   Teams' "RTT (real-time text) will be turned on for everyone in the
//!   call." confirmation) turns it on here. Nothing is signalled: everyone
//!   else's turns on with the first words they receive. It stays on for
//!   the call.
//! - **The wire.** `{"s": "…"}` as UTF-8 under data id 24 on the meeting's
//!   main-channel ([`super::mcp::RTT_DATA_ID`]), to everyone, from our
//!   data source. `s` is what was typed since the last: characters, a
//!   backspace (U+0008) for each one deleted, a newline ending the line.
//! - **Typing.** Teams sends what changed every 300 ms ([`input_delta`]);
//!   Enter ends the line, and so do 3 s without a key; 2000 characters at
//!   most.
//! - **Receiving.** A line per sender's data source ([`Lines`]); someone's
//!   line shows "RTT Typing" until it ends, and stays in the captions
//!   window then ([`show`]).

use std::collections::HashMap;

use super::transcript::{Entry, Kind};

/// How often what was typed goes out (Teams' realTimeTextAutoSendInterval).
pub const AUTO_SEND_MS: u64 = 300;
/// A line ends this long after the last key (realTimeTextAutoCommitTimeout).
pub const AUTO_COMMIT_MS: u64 = 3_000;
/// The longest line (realTimeTextMaxInputLength).
pub const MAX_INPUT: usize = 2_000;
const BACKSPACE: char = '\u{8}';
const NEWLINE: char = '\n';

/// What to send when the input changed from `old` to `new`: a backspace
/// for each character after what they share, then the new end (Teams'
/// diff of the two).
pub fn input_delta(old: &str, new: &str) -> String {
    let shared = old
        .chars()
        .zip(new.chars())
        .take_while(|(a, b)| a == b)
        .count();
    let erased = old.chars().count() - shared;
    std::iter::repeat_n(BACKSPACE, erased)
        .chain(new.chars().skip(shared))
        .collect()
}

/// Enter found nothing but spaces: Teams says "Please type a message to
/// continue." and sends nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OnlySpaces;

/// The RTT box (Teams' RealTimeTextInputRenderer): what it says, and what
/// changed since the last send.
#[derive(Debug, Default)]
pub struct Input {
    text: String,
    pending: String,
}

impl Input {
    pub fn new() -> Self {
        Self::default()
    }

    /// The box now says `text`; false (and nothing changes) past
    /// [`MAX_INPUT`] characters (UTF-16, as the browser counts them).
    pub fn changed(&mut self, text: &str) -> bool {
        if text.encode_utf16().count() > MAX_INPUT {
            return false;
        }
        self.pending.push_str(&input_delta(&self.text, text));
        self.text = text.to_string();
        true
    }

    /// What to send on [`AUTO_SEND_MS`]'s tick: what changed, unless it's
    /// only spaces so far.
    pub fn flush(&mut self) -> Option<String> {
        (!self.pending.trim().is_empty()).then(|| std::mem::take(&mut self.pending))
    }

    /// End the line and empty the box: Enter (`manual`) sends what's left
    /// and a newline, when the box has anything; [`AUTO_COMMIT_MS`] without
    /// a key sends the newline.
    pub fn commit(&mut self, manual: bool) -> Result<Option<String>, OnlySpaces> {
        let text = std::mem::take(&mut self.text);
        let pending = std::mem::take(&mut self.pending);
        if !manual {
            return Ok(Some(NEWLINE.to_string()));
        }
        if text.is_empty() {
            return Ok(None);
        }
        let chunk = format!("{pending}{NEWLINE}");
        if chunk.trim().is_empty() && text.trim().is_empty() {
            return Err(OnlySpaces);
        }
        Ok(Some(chunk))
    }

    /// Empty the box without sending (you typed on another device).
    pub fn clear(&mut self) {
        self.text.clear();
        self.pending.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.text.is_empty()
    }
}

/// A line after `chunk`: (its text, whether a newline ended it). An ended
/// line of nothing but spaces is empty.
pub fn apply(line: &str, chunk: &str) -> (String, bool) {
    let mut text = line.to_string();
    for c in chunk.chars() {
        match c {
            BACKSPACE => {
                text.pop();
            }
            NEWLINE => {
                if text.trim().is_empty() {
                    text.clear();
                }
                return (text, true);
            }
            c => text.push(c),
        }
    }
    (text, false)
}

/// Someone's line as it changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Update {
    pub source: u32,
    /// Their MRI.
    pub user_id: String,
    pub name: String,
    pub text: String,
    /// The line ended (what it says stays; empty: it's gone).
    pub is_final: bool,
    /// When they began it (Unix ms).
    pub at_ms: i64,
}

#[derive(Debug, Clone)]
struct Line {
    user_id: String,
    name: String,
    text: String,
    at_ms: i64,
}

/// The lines being typed, by data source (Teams' sourceIdToEntryMap).
#[derive(Debug, Default)]
pub struct Lines {
    by_source: HashMap<u32, Line>,
}

impl Lines {
    pub fn new() -> Self {
        Self::default()
    }

    /// Forget everything (a new call).
    pub fn clear(&mut self) {
        self.by_source.clear();
    }

    /// Who typed from `source`, if a line from it is known.
    pub fn sender(&self, source: u32) -> Option<(String, String)> {
        self.by_source
            .get(&source)
            .map(|l| (l.user_id.clone(), l.name.clone()))
    }

    /// `chunk` from `source` (`user_id` / `name`, as the roster names whose
    /// data stream it is): what changes. Someone typing on two devices at
    /// once ends the line on the other first, as Teams does.
    pub fn receive(
        &mut self,
        source: u32,
        user_id: &str,
        name: &str,
        chunk: &str,
        now_ms: i64,
    ) -> Vec<Update> {
        let (user_id, name) = self
            .sender(source)
            .unwrap_or_else(|| (user_id.to_string(), name.to_string()));
        let before = self.by_source.get(&source);
        let at_ms = before
            .filter(|l| !l.text.is_empty())
            .map_or(now_ms, |l| l.at_ms);
        let (text, is_final) = apply(before.map_or("", |l| l.text.as_str()), chunk);
        let mut out = Vec::new();
        let others: Vec<u32> = self
            .by_source
            .iter()
            .filter(|(s, l)| **s != source && l.user_id == user_id && !l.text.is_empty())
            .map(|(s, _)| *s)
            .collect();
        // Teams counts this source too while its line has words.
        if others.len() + usize::from(!text.is_empty()) > 1 {
            for s in others {
                out.extend(self.end(s));
            }
        }
        out.push(Update {
            source,
            user_id: user_id.clone(),
            name: name.clone(),
            text: text.clone(),
            is_final,
            at_ms,
        });
        self.by_source.insert(
            source,
            Line {
                user_id,
                name,
                text: if is_final { String::new() } else { text },
                at_ms,
            },
        );
        out
    }

    /// End the line from `source` where it stands.
    fn end(&mut self, source: u32) -> Option<Update> {
        let l = self.by_source.get_mut(&source)?;
        let u = Update {
            source,
            user_id: l.user_id.clone(),
            name: l.name.clone(),
            text: std::mem::take(&mut l.text),
            is_final: true,
            at_ms: l.at_ms,
        };
        Some(u)
    }

    /// Someone left (or put the call on hold): their lines end.
    pub fn end_user(&mut self, user_id: &str) -> Vec<Update> {
        let sources: Vec<u32> = self
            .by_source
            .iter()
            .filter(|(_, l)| l.user_id == user_id)
            .map(|(s, _)| *s)
            .collect();
        let out = sources.iter().filter_map(|s| self.end(*s)).collect();
        self.by_source.retain(|_, l| l.user_id != user_id);
        out
    }

    /// The call is held or ending: everyone's lines end.
    pub fn end_all(&mut self) -> Vec<Update> {
        let sources: Vec<u32> = self.by_source.keys().copied().collect();
        let out = sources.iter().filter_map(|s| self.end(*s)).collect();
        self.by_source.clear();
        out
    }
}

/// Show an update in the captions window, as Teams' list does: one line
/// being typed per person (`typing`); an ended line joins the captions
/// (`window`) at the time it ended; one ended or erased to nothing goes.
pub fn show(u: &Update, typing: &mut Vec<Entry>, window: &mut Vec<Entry>, now_ms: i64) {
    typing.retain(|e| e.user_id != u.user_id);
    if u.text.is_empty() {
        return;
    }
    let entry = Entry {
        id: format!("rtt-{}-{}", u.user_id, u.at_ms),
        kind: Kind::RealTimeText,
        user_id: u.user_id.clone(),
        name: u.name.clone(),
        text: u.text.clone(),
        raw_text: None,
        is_final: u.is_final,
        at_ms: if u.is_final { now_ms } else { u.at_ms },
        updated_ms: now_ms,
    };
    if u.is_final {
        super::transcript::merge_captions(window, vec![entry], now_ms);
    } else {
        typing.push(entry);
    }
}

/// The lines being typed in the order the window lists them, top to
/// bottom: others' (the one begun last on top), then yours at the bottom.
pub fn typing_order(typing: &[Entry], me: &str) -> Vec<Entry> {
    let mut out = typing.to_vec();
    out.sort_by_key(|e| {
        (
            e.user_id.eq_ignore_ascii_case(me),
            std::cmp::Reverse(e.at_ms),
        )
    });
    out
}

/// The card that opens the captions window's list when RTT turns on.
pub fn intro(now_ms: i64) -> Entry {
    Entry {
        id: "rtt-intro".into(),
        kind: Kind::RealTimeTextIntro,
        user_id: String::new(),
        name: String::new(),
        text: String::new(),
        raw_text: None,
        is_final: true,
        at_ms: now_ms,
        updated_ms: now_ms,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_changes_go_as_teams_sends_them() {
        assert_eq!(input_delta("", "Hello"), "Hello");
        assert_eq!(input_delta("Hello", "Hello w"), " w");
        assert_eq!(input_delta("Hello", "Help"), "\u{8}\u{8}p");
        assert_eq!(input_delta("abc", ""), "\u{8}\u{8}\u{8}");
        assert_eq!(input_delta("héllo", "hé"), "\u{8}\u{8}\u{8}");
    }

    #[test]
    fn the_box_sends_changes_and_ends_lines_as_teams() {
        let mut b = Input::new();
        assert!(b.changed("Hel"));
        assert!(b.changed("Hello"));
        assert_eq!(b.flush().as_deref(), Some("Hello"));
        assert_eq!(b.flush(), None, "nothing new");
        assert!(b.changed("Help"));
        assert_eq!(b.flush().as_deref(), Some("\u{8}\u{8}p"));
        assert!(b.changed("Help "));
        assert_eq!(b.flush(), None, "a space waits for more");
        assert!(b.changed("Help m"));
        assert_eq!(b.commit(true), Ok(Some(" m\n".into())));
        assert!(b.is_empty());
        assert_eq!(
            b.commit(true),
            Ok(None),
            "Enter in an empty box does nothing"
        );
        b.changed("   ");
        assert_eq!(b.commit(true), Err(OnlySpaces));
        assert!(b.is_empty());
        b.changed("Later");
        b.flush();
        assert_eq!(b.commit(false), Ok(Some("\n".into())), "3 s without a key");
        assert!(!b.changed(&"x".repeat(MAX_INPUT + 1)));
        assert!(b.changed(&"x".repeat(MAX_INPUT)));
    }

    #[test]
    fn chunks_build_and_end_lines() {
        assert_eq!(apply("", "Hi"), ("Hi".into(), false));
        assert_eq!(apply("Hi", "\u{8}o"), ("Ho".into(), false));
        assert_eq!(apply("Ho", " there\n"), ("Ho there".into(), true));
        assert_eq!(apply("   ", "\n"), (String::new(), true));
        assert_eq!(apply("", "\u{8}"), (String::new(), false));
    }

    #[test]
    fn a_senders_line_grows_then_ends() {
        let mut l = Lines::new();
        let u = l.receive(7, "8:orgid:a", "Ann", "He", 1000);
        assert_eq!(u.len(), 1);
        assert_eq!(
            (u[0].text.as_str(), u[0].is_final, u[0].at_ms),
            ("He", false, 1000)
        );
        let u = l.receive(7, "8:orgid:a", "Ann", "llo", 1300);
        assert_eq!(
            (u[0].text.as_str(), u[0].at_ms),
            ("Hello", 1000),
            "a line keeps when it began"
        );
        let u = l.receive(7, "8:orgid:a", "Ann", "\n", 1600);
        assert_eq!((u[0].text.as_str(), u[0].is_final), ("Hello", true));
        let u = l.receive(7, "", "", "Next", 5000);
        assert_eq!(
            (u[0].text.as_str(), u[0].at_ms, u[0].name.as_str()),
            ("Next", 5000, "Ann")
        );
    }

    #[test]
    fn typing_on_a_second_device_ends_the_first_line() {
        let mut l = Lines::new();
        l.receive(7, "8:orgid:a", "Ann", "On the laptop", 1000);
        let u = l.receive(9, "8:orgid:a", "Ann", "On the phone", 2000);
        assert_eq!(u.len(), 2);
        assert_eq!(
            (u[0].source, u[0].text.as_str(), u[0].is_final),
            (7, "On the laptop", true)
        );
        assert_eq!((u[1].source, u[1].is_final), (9, false));
    }

    #[test]
    fn leaving_and_holding_end_lines() {
        let mut l = Lines::new();
        l.receive(7, "8:orgid:a", "Ann", "Bye", 1000);
        l.receive(8, "8:orgid:b", "Bo", "Hold on", 1000);
        let u = l.end_user("8:orgid:a");
        assert_eq!(
            (u.len(), u[0].text.as_str(), u[0].is_final),
            (1, "Bye", true)
        );
        let u = l.end_all();
        assert_eq!((u.len(), u[0].text.as_str()), (1, "Hold on"));
        assert!(l.end_all().is_empty());
    }

    #[test]
    fn the_window_shows_one_typing_line_each_and_keeps_ended_ones() {
        let (mut typing, mut window) = (Vec::new(), vec![intro(500)]);
        let mut l = Lines::new();
        for u in l.receive(7, "8:orgid:a", "Ann", "Hel", 1000) {
            show(&u, &mut typing, &mut window, 1000);
        }
        for u in l.receive(7, "8:orgid:a", "Ann", "lo", 1300) {
            show(&u, &mut typing, &mut window, 1300);
        }
        assert_eq!(typing.len(), 1);
        assert_eq!(
            (typing[0].text.as_str(), typing[0].is_final),
            ("Hello", false)
        );
        for u in l.receive(7, "8:orgid:a", "Ann", "\n", 1600) {
            show(&u, &mut typing, &mut window, 1600);
        }
        assert!(typing.is_empty());
        assert_eq!(window.len(), 2);
        assert_eq!(
            (
                window[1].kind.clone(),
                window[1].text.as_str(),
                window[1].at_ms
            ),
            (Kind::RealTimeText, "Hello", 1600)
        );
        // Erased to nothing: gone.
        for u in l.receive(7, "8:orgid:a", "Ann", "x", 2000) {
            show(&u, &mut typing, &mut window, 2000);
        }
        for u in l.receive(7, "8:orgid:a", "Ann", "\u{8}", 2100) {
            show(&u, &mut typing, &mut window, 2100);
        }
        assert!(typing.is_empty());
        assert_eq!(window.len(), 2);
    }

    #[test]
    fn your_typing_line_is_at_the_bottom() {
        let e = |user: &str, at: i64| Entry {
            user_id: user.into(),
            at_ms: at,
            ..intro(at)
        };
        let order = typing_order(
            &[e("8:orgid:me", 1), e("8:orgid:a", 2), e("8:orgid:b", 3)],
            "8:orgid:ME",
        );
        let users: Vec<&str> = order.iter().map(|e| e.user_id.as_str()).collect();
        assert_eq!(users, ["8:orgid:b", "8:orgid:a", "8:orgid:me"]);
    }
}
