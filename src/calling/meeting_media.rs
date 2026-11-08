//! Video in meetings and group calls, as Teams does it: our offer carries
//! receive slots (main-video lines) and a data line; the media processor's
//! answer gives each slot a stream id and an SSRC range; and over the
//! data channel's media control plane we ask for whose video goes in which
//! slot. See docs/spec/meeting-video.md.

use super::datachannel::{DataEvent, DataSender};
use super::mcp::{Incoming, Session, SourceRequest};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Our camera's line.
pub const CAMERA_MID: &str = "1";
/// How many others' videos we can show at once (Teams' gallery shows up
/// to nine without paging).
pub const SLOT_COUNT: usize = 9;
/// The screen-sharing line.
pub const SHARE_MID: &str = "11";
/// The data line: SCTP for the media control plane.
pub const DATA_MID: &str = "12";
/// The data channel Teams opens for the media control plane.
pub const DATA_LABEL: &str = "main-channel";
const SCTP_PORT: u16 = 5000;
const MAX_MESSAGE_SIZE: u32 = 262_144;
/// Heartbeats go every second, as Teams sends them.
const HEARTBEAT: Duration = Duration::from_secs(1);
/// The H.264 we decode: constrained baseline, level 3.1.
const PROFILE_LEVEL_ID: u32 = 0x42e01f;
/// Shared screens: Teams asks for High 3.1 (presenters encode them so).
const SHARE_PROFILE_LEVEL_ID: u32 = 0x64001f;

/// The receive slots' mids, in order.
pub fn slot_mids() -> impl Iterator<Item = String> {
    (2..2 + SLOT_COUNT).map(|m| m.to_string())
}

/// The frame key a slot's decoded video is published under.
pub fn frame_key(mid: &str) -> String {
    format!("slot-{mid}")
}

/// Our data line, as Teams writes it (`x-data` with SCTP inside).
pub fn data_section(
    port: u16,
    addr: &str,
    ufrag: &str,
    pwd: &str,
    fingerprint: &str,
    ssrc: u32,
) -> String {
    let mut s = String::new();
    s.push_str(&format!("m=x-data {port} RTP/SAVP 127 126\r\n"));
    s.push_str(&format!("c=IN IP4 {addr}\r\n"));
    s.push_str("a=x-data-protocol:sctp\r\n");
    s.push_str(&format!("a=x-ssrc-range:{ssrc}-{ssrc}\r\n"));
    s.push_str("a=rtpmap:127 x-data/90000\r\n");
    s.push_str("a=rtpmap:126 rtx/90000\r\n");
    s.push_str("a=fmtp:126 apt=127\r\n");
    s.push_str(&format!("a=ice-ufrag:{ufrag}\r\n"));
    s.push_str(&format!("a=ice-pwd:{pwd}\r\n"));
    s.push_str(&format!("a=fingerprint:{fingerprint}\r\n"));
    s.push_str("a=setup:actpass\r\n");
    s.push_str(&format!("a=mid:{DATA_MID}\r\n"));
    s.push_str("a=sendrecv\r\n");
    s.push_str("a=rtcp-mux\r\n");
    s.push_str("a=label:data\r\n");
    s.push_str(&format!("a=sctp-port:{SCTP_PORT}\r\n"));
    s.push_str(&format!("a=max-message-size:{MAX_MESSAGE_SIZE}\r\n"));
    s
}

/// A receive slot as the media processor answered it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Slot {
    pub mid: String,
    /// `a=x-source-streamid`: what source requests name it by.
    pub stream_msid: i64,
    /// The SSRCs the processor sends this slot's video with (its RTX
    /// SSRCs too, which `pt` tells apart).
    pub ssrcs: (u32, u32),
    /// The video payload type (the line's first format).
    pub pt: u8,
}

/// The m-sections of an SDP with their mids.
fn sections(sdp: &str) -> Vec<(String, &str)> {
    let mut out = Vec::new();
    let mut rest = sdp;
    while let Some(i) = rest.find("m=") {
        let body = &rest[i..];
        let end = body[2..].find("\nm=").map(|e| e + 3).unwrap_or(body.len());
        let section = &body[..end];
        let mid = section
            .lines()
            .find_map(|l| l.trim_end().strip_prefix("a=mid:"))
            .unwrap_or_default()
            .to_string();
        out.push((mid, section));
        rest = &body[end..];
    }
    out
}

fn attr<'a>(section: &'a str, name: &str) -> Option<&'a str> {
    section
        .lines()
        .find_map(|l| l.trim_end().strip_prefix(name))
}

fn rejected(section: &str) -> bool {
    section.split_whitespace().nth(1) == Some("0")
}

/// A video line of the processor's SDP as a slot.
fn slot(mid: String, s: &str) -> Option<Slot> {
    if !s.starts_with("m=video") || rejected(s) {
        return None;
    }
    let stream_msid = attr(s, "a=x-source-streamid:")?.trim().parse().ok()?;
    let range = attr(s, "a=x-ssrc-range:")?;
    let (lo, hi) = range.split_once('-')?;
    let pt = s.lines().next()?.split_whitespace().nth(3)?.parse().ok()?;
    Some(Slot {
        mid,
        stream_msid,
        ssrcs: (lo.trim().parse().ok()?, hi.trim().parse().ok()?),
        pt,
    })
}

/// Our receive slots in the processor's SDP (answer or re-offer).
pub fn answered_slots(sdp: &str) -> Vec<Slot> {
    let mids: Vec<String> = slot_mids().collect();
    sections(sdp)
        .into_iter()
        .filter(|(mid, _)| mids.contains(mid))
        .filter_map(|(mid, s)| slot(mid, s))
        .collect()
}

/// The screen-sharing line in the processor's SDP.
pub fn answered_share(sdp: &str) -> Option<Slot> {
    sections(sdp)
        .into_iter()
        .find(|(mid, _)| mid == SHARE_MID)
        .and_then(|(mid, s)| slot(mid, s))
}

/// The processor's stream id for our data line, when it accepted it.
pub fn data_stream(sdp: &str) -> Option<i64> {
    sections(sdp)
        .into_iter()
        .find(|(mid, s)| mid == DATA_MID && s.starts_with("m=x-data") && !rejected(s))
        .and_then(|(_, s)| attr(s, "a=x-source-streamid:")?.trim().parse().ok())
}

/// What the media control plane does for us.
enum Command {
    /// (Re)send what changed in the source requests.
    Resend,
}

/// The source id that asks for nothing (MS-RTP's SOURCE_NONE): Teams
/// releases a slot with it.
const SOURCE_NONE: i64 = -1;

/// What we ask the processor for.
#[derive(Default)]
struct State {
    slots: Vec<Slot>,
    /// The screen-sharing line, when the processor took it.
    share_slot: Option<Slot>,
    /// mid -> the camera shown there.
    assigned: HashMap<String, i64>,
    /// source -> how large it's shown, in pixels across.
    widths: HashMap<i64, u32>,
    /// Whose screen to receive (their applicationsharing-video source).
    share: Option<i64>,
}

/// Others' video in a meeting: which source is in which slot, and the
/// media control plane session that asks for them.
pub struct MeetingVideo {
    state: Arc<Mutex<State>>,
    commands: tokio::sync::mpsc::UnboundedSender<Command>,
    task: tokio::task::JoinHandle<()>,
}

impl Drop for MeetingVideo {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl MeetingVideo {
    /// Run the media control plane on an open data channel.
    pub fn start(
        slots: Vec<Slot>,
        share_slot: Option<Slot>,
        sender: DataSender,
        events: tokio::sync::mpsc::UnboundedReceiver<DataEvent>,
    ) -> Self {
        let state = Arc::new(Mutex::new(State {
            slots,
            share_slot,
            ..Default::default()
        }));
        let (commands, rx) = tokio::sync::mpsc::unbounded_channel();
        let task = tokio::spawn(run(sender, events, rx, state.clone()));
        Self {
            state,
            commands,
            task,
        }
    }

    fn changed(&self) {
        let _ = self.commands.send(Command::Resend);
    }

    /// The processor re-offered: its slots may carry new stream ids, so
    /// ask again for what they show.
    pub fn update_slots(&self, slots: Vec<Slot>, share_slot: Option<Slot>) {
        if slots.is_empty() {
            return;
        }
        let mut st = lock(&self.state);
        if st.slots != slots || (share_slot.is_some() && st.share_slot != share_slot) {
            st.slots = slots;
            if share_slot.is_some() {
                st.share_slot = share_slot;
            }
            drop(st);
            self.changed();
        }
    }

    /// Show these cameras (roster `main-video` sourceIds, in the order they
    /// should get slots, with how wide each is shown); returns sourceId ->
    /// frame key for each one that has a slot. Sources keep their slots.
    pub fn show(&self, sources: &[(i64, u32)]) -> HashMap<i64, String> {
        let mut st = lock(&self.state);
        let mids: Vec<String> = st.slots.iter().map(|s| s.mid.clone()).collect();
        let before = st.assigned.clone();
        let widths_before = st.widths.clone();
        let ids: Vec<i64> = sources.iter().map(|s| s.0).collect();
        st.assigned.retain(|_, src| ids.contains(src));
        for src in &ids {
            if st.assigned.values().any(|s| s == src) {
                continue;
            }
            if let Some(free) = mids.iter().find(|m| !st.assigned.contains_key(*m)) {
                st.assigned.insert(free.clone(), *src);
            }
        }
        st.widths = sources.iter().copied().collect();
        let out = st
            .assigned
            .iter()
            .map(|(mid, src)| (*src, frame_key(mid)))
            .collect();
        // A slot given to someone else mustn't show the last frame of
        // whoever had it.
        for (mid, src) in &before {
            if st.assigned.get(mid) != Some(src) {
                super::frames::clear(&frame_key(mid));
            }
        }
        let changed = st.assigned != before || st.widths != widths_before;
        drop(st);
        if changed {
            self.changed();
        }
        out
    }

    /// Receive this presenter's screen (their applicationsharing-video
    /// sourceId), or stop.
    pub fn show_share(&self, source: Option<i64>) {
        let mut st = lock(&self.state);
        if st.share != source {
            st.share = source;
            drop(st);
            if source.is_none() {
                super::frames::clear("share");
            }
            self.changed();
        }
    }
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// The capabilities Teams asks a camera with, by how wide it's shown:
/// (max-fs, max-mbps). Large tiles take up to 1080p at 30; the side
/// gallery's 160 px tiles 320x180.
fn camera_caps(width: u32) -> (u32, u32) {
    match width {
        0..200 => (240, 8_437),
        200..400 => (920, 33_750),
        _ => (8160, 244_800),
    }
}

/// Every request we want in force, by the receiving stream: cameras in
/// their slots, the presenter's screen on the sharing line.
fn requests(st: &State) -> HashMap<i64, SourceRequest> {
    let mut out: HashMap<i64, SourceRequest> = st
        .slots
        .iter()
        .filter_map(|s| {
            let src = *st.assigned.get(&s.mid)?;
            let (max_fs, max_mbps) = camera_caps(st.widths.get(&src).copied().unwrap_or(1280));
            Some((
                s.stream_msid,
                SourceRequest {
                    source_id: src,
                    stream_msid: s.stream_msid,
                    max_fs,
                    max_mbps,
                    max_fps: 3000,
                    profile_level_id: PROFILE_LEVEL_ID,
                },
            ))
        })
        .collect();
    if let (Some(slot), Some(src)) = (&st.share_slot, st.share) {
        // Teams asks shared screens for up to 1080p at 15.
        out.insert(
            slot.stream_msid,
            SourceRequest {
                source_id: src,
                stream_msid: slot.stream_msid,
                max_fs: 8160,
                max_mbps: 135_000,
                max_fps: 1500,
                profile_level_id: SHARE_PROFILE_LEVEL_ID,
            },
        );
    }
    out
}

/// What to send now, given what's in force (`sent`, by stream): the
/// changed requests, and SOURCE_NONE for streams nothing is wanted on.
fn due(
    wanted: &HashMap<i64, SourceRequest>,
    sent: &HashMap<i64, SourceRequest>,
) -> Vec<SourceRequest> {
    let mut out: Vec<SourceRequest> = wanted
        .values()
        .filter(|r| sent.get(&r.stream_msid) != Some(r))
        .copied()
        .collect();
    out.extend(
        sent.values()
            .filter(|r| r.source_id != SOURCE_NONE && !wanted.contains_key(&r.stream_msid))
            .map(|r| SourceRequest {
                source_id: SOURCE_NONE,
                ..*r
            }),
    );
    out.sort_by_key(|r| r.stream_msid);
    out
}

async fn run(
    sender: DataSender,
    mut events: tokio::sync::mpsc::UnboundedReceiver<DataEvent>,
    mut commands: tokio::sync::mpsc::UnboundedReceiver<Command>,
    state: Arc<Mutex<State>>,
) {
    let mut session = Session::new();
    let mut tick = tokio::time::interval(HEARTBEAT);
    // What's in force on each receiving stream.
    let mut sent: HashMap<i64, SourceRequest> = HashMap::new();
    let send_requests = |session: &mut Session, sent: &mut HashMap<i64, SourceRequest>| {
        let wanted = requests(&lock(&state));
        for r in due(&wanted, sent) {
            let (seq, frame) = session.source_request(r);
            tracing::info!(
                source = r.source_id,
                stream = r.stream_msid,
                max_fs = r.max_fs,
                seq,
                "MCP source request"
            );
            sent.insert(r.stream_msid, r);
            sender.send(frame);
        }
    };
    loop {
        tokio::select! {
            ev = events.recv() => match ev {
                Some(DataEvent::Open) => {
                    sent.clear();
                    sender.send(session.syn());
                }
                Some(DataEvent::Message(m)) => {
                    for inc in session.receive(&m) {
                        match inc {
                            Incoming::Ack { id } => {
                                tracing::info!(id, "MCP session up");
                                sent.clear();
                                send_requests(&mut session, &mut sent);
                            }
                            Incoming::SourceResult { seq, result } => {
                                tracing::info!(seq, %result, "MCP source result");
                            }
                            Incoming::DominantSpeakers(ids) => {
                                crate::event_hub::publish(
                                    crate::event_hub::EventKind::Call,
                                    serde_json::json!({
                                        "callAgentPath": "ost/dominantSpeakers/",
                                        "body": {"sourceIds": ids},
                                    })
                                    .to_string(),
                                );
                            }
                            Incoming::SendLayers { stream, layers } => {
                                tracing::debug!(stream, ?layers, "MCP send layers");
                            }
                            Incoming::Bandwidth { total, video } => {
                                tracing::debug!(total, ?video, "MCP bandwidth");
                            }
                            Incoming::Heartbeat => {}
                            Incoming::Other(v) => tracing::debug!("MCP message {v}"),
                        }
                    }
                }
                Some(DataEvent::Closed) | None => {
                    tracing::info!("MCP data channel closed");
                    return;
                }
            },
            c = commands.recv() => match c {
                Some(Command::Resend) => {
                    if session.is_up() {
                        // Streams no longer in the slot table are gone.
                        let st = lock(&state);
                        let live: Vec<i64> = st
                            .slots
                            .iter()
                            .chain(st.share_slot.iter())
                            .map(|s| s.stream_msid)
                            .collect();
                        drop(st);
                        sent.retain(|m, _| live.contains(m));
                        send_requests(&mut session, &mut sent);
                    }
                }
                None => return,
            },
            _ = tick.tick() => {
                if session.is_up() {
                    sender.send(session.heartbeat());
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The video lines of a media processor's answer to Teams' offer
    /// (trimmed from the capture).
    const ANSWER: &str = "v=0\r\nm=audio 3478 RTP/SAVP 0\r\na=mid:0\r\n\
m=video 3478 RTP/SAVP 107 99\r\na=x-source-streamid:628\r\na=label:main-video\r\na=mid:1\r\na=x-ssrc-range:3403-3502\r\n\
m=video 3478 RTP/SAVP 107 99\r\na=x-source-streamid:629\r\na=label:main-video\r\na=mid:2\r\na=x-ssrc-range:3503-3602\r\n\
m=video 3478 RTP/SAVP 107 99\r\na=x-source-streamid:630\r\na=label:main-video\r\na=mid:3\r\na=sendonly\r\na=x-ssrc-range:3603-3702\r\n\
m=video 0 RTP/SAVP 107\r\na=mid:4\r\n\
m=x-data 3478 RTP/SAVP 127 126\r\na=x-source-streamid:639\r\na=mid:12\r\n";

    #[test]
    fn slots_and_the_data_stream_come_from_the_answer() {
        assert_eq!(
            answered_slots(ANSWER),
            vec![
                Slot {
                    mid: "2".into(),
                    stream_msid: 629,
                    ssrcs: (3503, 3602),
                    pt: 107
                },
                Slot {
                    mid: "3".into(),
                    stream_msid: 630,
                    ssrcs: (3603, 3702),
                    pt: 107
                },
            ],
            "the camera line and rejected lines aren't slots"
        );
        assert_eq!(data_stream(ANSWER), Some(639));
        assert_eq!(
            data_stream("v=0\r\nm=x-data 0 RTP/SAVP 127\r\na=mid:12\r\n"),
            None
        );
    }

    #[test]
    fn data_line_is_teams_x_data_with_sctp() {
        let s = data_section(9, "1.2.3.4", "u", "p", "sha-256 AA", 5);
        for want in [
            "m=x-data 9 RTP/SAVP 127 126",
            "a=x-data-protocol:sctp",
            "a=mid:12",
            "a=sctp-port:5000",
            "a=max-message-size:262144",
            "a=label:data",
        ] {
            assert!(s.contains(want), "{want}");
        }
    }

    #[tokio::test]
    async fn sources_keep_their_slots() {
        let (tx, _rx) = std::sync::mpsc::channel();
        let (_etx, erx) = tokio::sync::mpsc::unbounded_channel();
        let v = MeetingVideo::start(
            answered_slots(ANSWER),
            None,
            super::super::datachannel::DataSender::for_test(tx),
            erx,
        );
        let w = |ids: &[i64]| ids.iter().map(|i| (*i, 450)).collect::<Vec<_>>();
        let a = v.show(&w(&[2244, 2031]));
        assert_eq!(a.len(), 2);
        let b = v.show(&w(&[2031, 2244]));
        assert_eq!(a, b, "order changes don't move anyone");
        let c = v.show(&w(&[2031, 9999]));
        assert_eq!(c[&2031], a[&2031]);
        assert_eq!(c[&9999], a[&2244], "a freed slot is reused");
        let d = v.show(&w(&[1, 2, 3]));
        assert_eq!(d.len(), 2, "no more than the slots there are");
    }

    fn slot(mid: &str, msid: i64) -> Slot {
        Slot {
            mid: mid.into(),
            stream_msid: msid,
            ssrcs: (0, 0),
            pt: 107,
        }
    }

    #[test]
    fn requests_ask_as_teams_does() {
        let st = State {
            slots: vec![slot("2", 7761), slot("3", 7762)],
            share_slot: Some(slot("11", 7771)),
            assigned: [("2".to_string(), 2244), ("3".to_string(), 2031)].into(),
            widths: [(2244, 450), (2031, 156)].into(),
            share: Some(17143),
        };
        let r = requests(&st);
        let caps = |m: i64| (r[&m].source_id, r[&m].max_fs, r[&m].max_mbps, r[&m].max_fps);
        // As Teams asked: a gallery tile, a side gallery tile, a screen.
        assert_eq!(caps(7761), (2244, 8160, 244_800, 3000));
        assert_eq!(caps(7762), (2031, 240, 8_437, 3000));
        assert_eq!(caps(7771), (17143, 8160, 135_000, 1500));
    }

    #[test]
    fn freed_streams_are_released_and_unchanged_ones_left_alone() {
        let mut st = State {
            slots: vec![slot("2", 7761), slot("3", 7762)],
            assigned: [("2".to_string(), 2244), ("3".to_string(), 2031)].into(),
            ..Default::default()
        };
        let sent = requests(&st);
        assert!(due(&requests(&st), &sent).is_empty());
        st.assigned.remove("3");
        let d = due(&requests(&st), &sent);
        assert_eq!(d.len(), 1);
        assert_eq!((d[0].stream_msid, d[0].source_id), (7762, SOURCE_NONE));
    }

    #[test]
    fn the_sharing_line_is_read_from_the_answer() {
        let sdp = "v=0\r\nm=video 3478 RTP/SAVP 107 99\r\na=x-source-streamid:638\r\na=label:applicationsharing-video\r\na=mid:11\r\na=x-ssrc-range:4403-4502\r\n";
        assert_eq!(
            answered_share(sdp),
            Some(Slot {
                mid: "11".into(),
                stream_msid: 638,
                ssrcs: (4403, 4502),
                pt: 107
            })
        );
    }
}
