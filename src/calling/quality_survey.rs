//! Teams' post-call "How was the call quality?" (its CQF questionnaire with
//! the live `callQualityFeedbackUxStyle` "ThumbsCombined"), as an opt-in
//! (docs/spec/feedback-and-help.md §5). Read from Teams desktop's bundles
//! 2026-11-18 (the CQF items `mE`, `CreateCQFItems`, the questionnaire UI's
//! shuffles; calling_cqf_* strings):
//! - Teams asks after a sampled share of calls (`samplingRatesForCQF`:
//!   1:1, group, meeting and share-from-chat 0.1; PSTN and interop 0), only
//!   when surveys are allowed (Settings ▸ Privacy ▸ Surveys);
//! - "Had issues" (rating 1) or "Good" (rating 5): Good is sent at once;
//!   Had issues shows "What could've been better?" with the categories
//!   Audio, Video and Screenshare (Video left out where the call can't
//!   carry video; PSTN calls ask about audio only), each a list of
//!   checkboxes in two columns. With ThumbsCombined both the categories
//!   and the items are shuffled and the first category is selected.
//!
//! OST sends nothing to Microsoft: Had issues with its reasons opens
//! Report a problem for the feedback repo with the call's technical
//! details (no one's name), and the reporter submits it on GitHub.

use serde::Serialize;

/// One reason to tick (`calling_cqf_item_<id>`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Item {
    pub id: &'static str,
    pub label: &'static str,
}

/// A category tab and its reasons.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Category {
    pub id: &'static str,
    pub label: &'static str,
    pub items: Vec<Item>,
}

const fn it(id: &'static str, label: &'static str) -> Item {
    Item { id, label }
}

/// Teams' Audio items (categories "q" and "r"; the "Other, please
/// specify" box is an input the thumbs survey doesn't show).
fn audio() -> Vec<Item> {
    vec![
        it("audio_nolocal", "I could not hear any sound"),
        it("audio_noremote", "The other side could not hear any sound"),
        it("audio_quality_echo", "I heard echo in the call"),
        it("audio_quality_noise", "I heard noise in the call"),
        it("audio_quality_volume", "Volume was low"),
        it("audio_dropped", "The call ended unexpectedly"),
        it(
            "audio_quality_distorted",
            "Speech was not natural or sounded distorted",
        ),
        it("audio_quality_delay", "We kept interrupting each other"),
        it("reliability_join", "People had trouble joining the call"),
        it(
            "reliability_invite",
            "I could not invite someone into the call",
        ),
    ]
}

fn video() -> Vec<Item> {
    vec![
        it("video_nolocal", "I could not see any video"),
        it("video_noremote", "The other side could not see my video"),
        it("video_quality_poor", "Image quality was poor"),
        it("video_quality_freezing", "Video kept freezing"),
        it("video_dropped", "Video stopped unexpectedly"),
        it("video_quality_dark", "The other side was too dark"),
        it("video_quality_sync", "Video was ahead or behind audio"),
        it(
            "video_quality_backgroundblur",
            "Video blurring didn't work as expected",
        ),
    ]
}

fn screenshare() -> Vec<Item> {
    vec![
        it("ss_nolocal", "I could not see any presented content"),
        it(
            "ss_noremote",
            "The other side could not see my presented content",
        ),
        it("ss_quality_start", "I couldn't present my content"),
        it("ss_quality_freezing", "The presented content kept freezing"),
        it(
            "ss_quality_poor",
            "The image quality of the presented content was poor",
        ),
        it("ss_dropped", "The presentation stopped unexpectedly"),
        it(
            "ss_quality_sync",
            "There was a large delay in the presented content",
        ),
        it(
            "ss_quality_systemaudio",
            "System audio didn't work as expected",
        ),
    ]
}

/// What kind of call ended (Teams' CQF call types).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallKind {
    OneToOne,
    Group,
    Meeting,
    ScreenshareFromChat,
    Pstn,
    Interop,
}

impl CallKind {
    pub fn parse(s: &str) -> Self {
        match s {
            "group" => CallKind::Group,
            "meeting" => CallKind::Meeting,
            "screenshareFromChat" => CallKind::ScreenshareFromChat,
            "pstn" => CallKind::Pstn,
            "interop" => CallKind::Interop,
            _ => CallKind::OneToOne,
        }
    }

    /// Teams desktop's `samplingRatesForCQF`.
    pub fn sampling_rate(self) -> f64 {
        match self {
            CallKind::OneToOne
            | CallKind::Group
            | CallKind::Meeting
            | CallKind::ScreenshareFromChat => 0.1,
            CallKind::Pstn | CallKind::Interop => 0.0,
        }
    }

    /// The question ("How was the screen share quality?" after a share
    /// started from chat).
    pub fn question(self) -> &'static str {
        match self {
            CallKind::ScreenshareFromChat => "How was the screen share quality?",
            _ => "How was the call quality?",
        }
    }
}

/// Whether this call is asked about: `roll` is a uniform draw in [0, 1).
pub fn sampled(kind: CallKind, roll: f64) -> bool {
    roll < kind.sampling_rate()
}

/// The categories as Teams builds them for the call (`CreateCQFItems`):
/// PSTN asks about audio only, a share from chat about the share only,
/// and Video goes when the call can't carry video.
pub fn categories(kind: CallKind, with_video: bool) -> Vec<Category> {
    let mut out = Vec::new();
    let share_only = kind == CallKind::ScreenshareFromChat;
    if !share_only {
        out.push(Category {
            id: "audio",
            label: "Audio",
            items: audio(),
        });
        if with_video && kind != CallKind::Pstn {
            out.push(Category {
                id: "video",
                label: "Video",
                items: video(),
            });
        }
    }
    if kind != CallKind::Pstn {
        out.push(Category {
            id: "screenshare",
            label: "Screenshare",
            items: screenshare(),
        });
    }
    out
}

/// Teams' Fisher–Yates shuffle (`ve`), with `rand(n)` a uniform index
/// below n.
pub fn shuffle<T>(v: &mut [T], mut rand: impl FnMut(usize) -> usize) {
    for e in (1..v.len()).rev() {
        let s = rand(e + 1);
        v.swap(e, s);
    }
}

/// The survey Teams' ThumbsCombined shows: the categories and each one's
/// items shuffled.
pub fn questionnaire(
    kind: CallKind,
    with_video: bool,
    mut rand: impl FnMut(usize) -> usize,
) -> serde_json::Value {
    let mut cats = categories(kind, with_video);
    shuffle(&mut cats, &mut rand);
    for c in &mut cats {
        shuffle(&mut c.items, &mut rand);
    }
    // Shown in the app language (the report keeps the English).
    let cats: Vec<serde_json::Value> = cats
        .iter()
        .map(|c| {
            let items: Vec<serde_json::Value> = c
                .items
                .iter()
                .map(|i| serde_json::json!({ "id": i.id, "label": item_label(i) }))
                .collect();
            serde_json::json!({ "id": c.id, "label": category_label(c), "items": items })
        })
        .collect();
    let question = match kind {
        CallKind::ScreenshareFromChat => {
            crate::i18n::tr_id("How was the screen share quality?", "calling:k23er1l9k")
        }
        _ => crate::i18n::tr_id("How was the call quality?", "calling:kdvbsnqen"),
    };
    serde_json::json!({ "question": question, "categories": cats })
}

/// A category's name as Teams' survey shows it (calling_cqf_category_*).
fn category_label(c: &Category) -> String {
    use crate::i18n::tr_id;
    match c.id {
        "audio" => tr_id("Audio", "calling:k983ku35h"),
        "video" => tr_id("Video", "calling:k9axev4ju"),
        "screenshare" => tr_id("Screenshare", "calling:k4ywi5k9m"),
        _ => c.label.to_string(),
    }
}

/// An item as Teams' survey shows it (`calling_cqf_item_${id}`).
fn item_label(i: &Item) -> String {
    use crate::i18n::tr_id;
    match i.id {
        "audio_nolocal" => tr_id("I could not hear any sound", "calling:k3kkga19p"),
        "audio_noremote" => tr_id(
            "The other side could not hear any sound",
            "calling:k7qu0inyw",
        ),
        "audio_quality_echo" => tr_id("I heard echo in the call", "calling:k1hc1xh6u"),
        "audio_quality_noise" => tr_id("I heard noise in the call", "calling:kbpog2xrd"),
        "audio_quality_volume" => tr_id("Volume was low", "calling:k90whlwoj"),
        "audio_dropped" => tr_id("The call ended unexpectedly", "calling:k5jsbvff7"),
        "audio_quality_distorted" => tr_id(
            "Speech was not natural or sounded distorted",
            "calling:k4hzq4rg1",
        ),
        "audio_quality_delay" => tr_id("We kept interrupting each other", "calling:kbobdcld6"),
        "reliability_join" => tr_id("People had trouble joining the call", "calling:k3gscsjpj"),
        "reliability_invite" => tr_id(
            "I could not invite someone into the call",
            "calling:k8jcn7w6m",
        ),
        "video_nolocal" => tr_id("I could not see any video", "calling:k35v95yea"),
        "video_noremote" => tr_id("The other side could not see my video", "calling:kadks0ed3"),
        "video_quality_poor" => tr_id("Image quality was poor", "calling:k67ej9daa"),
        "video_quality_freezing" => tr_id("Video kept freezing", "calling:k3vn0znc4"),
        "video_dropped" => tr_id("Video stopped unexpectedly", "calling:k5534rcjs"),
        "video_quality_dark" => tr_id("The other side was too dark", "calling:k67e320jm"),
        "video_quality_sync" => tr_id("Video was ahead or behind audio", "calling:k67endli3"),
        "video_quality_backgroundblur" => tr_id(
            "Video blurring didn't work as expected",
            "calling:k9fnjkkoh",
        ),
        "ss_nolocal" => tr_id("I could not see any presented content", "calling:k8bb61ph7"),
        "ss_noremote" => tr_id(
            "The other side could not see my presented content",
            "calling:kbp9nhpdu",
        ),
        "ss_quality_start" => tr_id("I couldn't present my content", "calling:k4jcpy44n"),
        "ss_quality_freezing" => tr_id("The presented content kept freezing", "calling:k1kn7dx3j"),
        "ss_quality_poor" => tr_id(
            "The image quality of the presented content was poor",
            "calling:kcgik9ed9",
        ),
        "ss_dropped" => tr_id("The presentation stopped unexpectedly", "calling:kaaj1n3mp"),
        "ss_quality_sync" => tr_id(
            "There was a large delay in the presented content",
            "calling:kcgiodml2",
        ),
        "ss_quality_systemaudio" => {
            tr_id("System audio didn't work as expected", "calling:kayk5093w")
        }
        _ => i.label.to_string(),
    }
}

/// Report a problem's details for "Had issues": the reasons ticked and
/// the call's technical details (`metrics`: Call health's values by
/// name), never anyone's name.
pub fn report_details(
    kind: CallKind,
    duration_s: u64,
    reasons: &[String],
    metrics: &[(String, String)],
) -> String {
    let all: Vec<Item> = audio()
        .into_iter()
        .chain(video())
        .chain(screenshare())
        .collect();
    let label = |id: &str| {
        all.iter()
            .find(|i| i.id == id)
            .map(|i| i.label)
            .unwrap_or("")
    };
    let kind_name = match kind {
        CallKind::OneToOne => "1:1 call",
        CallKind::Group => "Group call",
        CallKind::Meeting => "Meeting",
        CallKind::ScreenshareFromChat => "Screen share from chat",
        CallKind::Pstn => "Phone call",
        CallKind::Interop => "Interop call",
    };
    let mut s = format!(
        "Call quality survey: Had issues\nCall: {kind_name}, {}:{:02}\n",
        duration_s / 60,
        duration_s % 60
    );
    if !reasons.is_empty() {
        s.push_str("What could've been better:\n");
        for r in reasons {
            let l = label(r);
            if !l.is_empty() {
                s.push_str(&format!("- {l} ({r})\n"));
            }
        }
    }
    let shown: Vec<&(String, String)> = metrics.iter().filter(|(_, v)| !v.is_empty()).collect();
    if !shown.is_empty() {
        s.push_str("Media (Call health at the end of the call):\n");
        for (k, v) in shown {
            s.push_str(&format!("- {k}: {v}\n"));
        }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sampling_as_teams_desktop() {
        assert!(sampled(CallKind::Meeting, 0.05));
        assert!(!sampled(CallKind::Meeting, 0.1));
        assert!(!sampled(CallKind::Pstn, 0.0));
        assert_eq!(CallKind::parse("group").sampling_rate(), 0.1);
    }

    #[test]
    fn categories_per_call() {
        let ids = |v: Vec<Category>| v.iter().map(|c| c.id).collect::<Vec<_>>();
        assert_eq!(
            ids(categories(CallKind::Meeting, true)),
            ["audio", "video", "screenshare"]
        );
        assert_eq!(
            ids(categories(CallKind::OneToOne, false)),
            ["audio", "screenshare"]
        );
        assert_eq!(ids(categories(CallKind::Pstn, true)), ["audio"]);
        assert_eq!(
            ids(categories(CallKind::ScreenshareFromChat, true)),
            ["screenshare"]
        );
        let c = categories(CallKind::Meeting, true);
        assert_eq!(c[0].items.len(), 10);
        assert_eq!(c[1].items.len(), 8);
        assert_eq!(c[2].items.len(), 8);
        assert_eq!(
            CallKind::ScreenshareFromChat.question(),
            "How was the screen share quality?"
        );
    }

    #[test]
    fn the_shuffle_keeps_every_item() {
        let mut n = 7usize;
        let q = questionnaire(CallKind::Meeting, true, |m| {
            n = (n * 31 + 11) % 97;
            n % m
        });
        let cats = q["categories"].as_array().unwrap();
        assert_eq!(cats.len(), 3);
        let mut all: Vec<String> = cats
            .iter()
            .flat_map(|c| {
                c["items"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|i| i["id"].as_str().unwrap().to_string())
            })
            .collect();
        all.sort();
        all.dedup();
        assert_eq!(all.len(), 26);
        assert_eq!(q["question"], "How was the call quality?");
    }

    #[test]
    fn details_name_no_one() {
        let d = report_details(
            CallKind::Meeting,
            125,
            &["video_quality_freezing".into(), "audio_quality_echo".into()],
            &[
                ("network-round-trip-time".into(), "29.00 ms".into()),
                ("audio-codec".into(), String::new()),
            ],
        );
        assert!(d.contains("Meeting, 2:05"));
        assert!(d.contains("- Video kept freezing (video_quality_freezing)"));
        assert!(d.contains("- network-round-trip-time: 29.00 ms"));
        assert!(!d.contains("audio-codec"));
    }
}
