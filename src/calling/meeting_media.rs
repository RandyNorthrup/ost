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

/// Our receive slots in the processor's SDP (answer or re-offer).
pub fn answered_slots(sdp: &str) -> Vec<Slot> {
    let mids: Vec<String> = slot_mids().collect();
    sections(sdp)
        .into_iter()
        .filter(|(mid, s)| mids.contains(mid) && s.starts_with("m=video") && !rejected(s))
        .filter_map(|(mid, s)| {
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
        })
        .collect()
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
    /// (Re)send every slot's source request.
    Resend,
}

/// Others' video in a meeting: which source is in which slot, and the
/// media control plane session that asks for them.
pub struct MeetingVideo {
    slots: Arc<Mutex<Vec<Slot>>>,
    /// mid -> the source shown there.
    assigned: Arc<Mutex<HashMap<String, i64>>>,
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
        sender: DataSender,
        events: tokio::sync::mpsc::UnboundedReceiver<DataEvent>,
    ) -> Self {
        let slots = Arc::new(Mutex::new(slots));
        let assigned: Arc<Mutex<HashMap<String, i64>>> = Arc::default();
        let (commands, rx) = tokio::sync::mpsc::unbounded_channel();
        let task = tokio::spawn(run(sender, events, rx, slots.clone(), assigned.clone()));
        Self {
            slots,
            assigned,
            commands,
            task,
        }
    }

    /// The processor re-offered: its slots may carry new stream ids, so
    /// ask again for what they show.
    pub fn update_slots(&self, slots: Vec<Slot>) {
        if slots.is_empty() {
            return;
        }
        let mut cur = lock(&self.slots);
        if *cur != slots {
            *cur = slots;
            drop(cur);
            let _ = self.commands.send(Command::Resend);
        }
    }

    /// Show these sources (roster `main-video` sourceIds, in the order
    /// they should get slots); returns sourceId -> frame key for each one
    /// that has a slot. Sources keep the slot they had.
    pub fn show(&self, sources: &[i64]) -> HashMap<i64, String> {
        let mids: Vec<String> = lock(&self.slots).iter().map(|s| s.mid.clone()).collect();
        let mut assigned = lock(&self.assigned);
        let before = assigned.clone();
        assigned.retain(|_, src| sources.contains(src));
        for src in sources {
            if assigned.values().any(|s| s == src) {
                continue;
            }
            if let Some(free) = mids.iter().find(|m| !assigned.contains_key(*m)) {
                assigned.insert(free.clone(), *src);
            }
        }
        let out = assigned
            .iter()
            .map(|(mid, src)| (*src, frame_key(mid)))
            .collect();
        // A slot given to someone else mustn't show the last frame of
        // whoever had it.
        for (mid, src) in &before {
            if assigned.get(mid) != Some(src) {
                super::frames::clear(&frame_key(mid));
            }
        }
        if *assigned != before {
            drop(assigned);
            let _ = self.commands.send(Command::Resend);
        }
        out
    }
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Source requests for what each slot shows, with the capabilities Teams
/// asks with (up to 1080p at 30; the processor picks the layer our
/// downlink allows).
fn requests(slots: &[Slot], assigned: &HashMap<String, i64>) -> Vec<SourceRequest> {
    slots
        .iter()
        .filter_map(|s| {
            assigned.get(&s.mid).map(|src| SourceRequest {
                source_id: *src,
                stream_msid: s.stream_msid,
                max_fs: 8160,
                max_mbps: 244_800,
                max_fps: 3000,
                profile_level_id: PROFILE_LEVEL_ID,
            })
        })
        .collect()
}

async fn run(
    sender: DataSender,
    mut events: tokio::sync::mpsc::UnboundedReceiver<DataEvent>,
    mut commands: tokio::sync::mpsc::UnboundedReceiver<Command>,
    slots: Arc<Mutex<Vec<Slot>>>,
    assigned: Arc<Mutex<HashMap<String, i64>>>,
) {
    let mut session = Session::new();
    let mut tick = tokio::time::interval(HEARTBEAT);
    // What was last asked for each slot, so a resend skips the unchanged.
    let mut sent: HashMap<i64, i64> = HashMap::new();
    let send_requests = |session: &mut Session, sent: &mut HashMap<i64, i64>| {
        let wanted = requests(&lock(&slots), &lock(&assigned));
        for r in wanted {
            if sent.get(&r.stream_msid) == Some(&r.source_id) {
                continue;
            }
            let (seq, frame) = session.source_request(r);
            tracing::info!(
                source = r.source_id,
                slot = r.stream_msid,
                seq,
                "MCP source request"
            );
            sent.insert(r.stream_msid, r.source_id);
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
                        // A changed slot table invalidates what was sent.
                        let msids: Vec<i64> = lock(&slots).iter().map(|s| s.stream_msid).collect();
                        sent.retain(|m, _| msids.contains(m));
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
            super::super::datachannel::DataSender::for_test(tx),
            erx,
        );
        let a = v.show(&[2244, 2031]);
        assert_eq!(a.len(), 2);
        let b = v.show(&[2031, 2244]);
        assert_eq!(a, b, "order changes don't move anyone");
        let c = v.show(&[2031, 9999]);
        assert_eq!(c[&2031], a[&2031]);
        assert_eq!(c[&9999], a[&2244], "a freed slot is reused");
        let d = v.show(&[1, 2, 3]);
        assert_eq!(d.len(), 2, "no more than the slots there are");
    }

    #[test]
    fn requests_ask_as_teams_does() {
        let slots = vec![Slot {
            mid: "2".into(),
            stream_msid: 7761,
            ssrcs: (0, 0),
            pt: 107,
        }];
        let a: HashMap<String, i64> = [("2".to_string(), 2244)].into();
        let r = requests(&slots, &a);
        assert_eq!(
            (
                r[0].source_id,
                r[0].stream_msid,
                r[0].max_fs,
                r[0].max_mbps,
                r[0].max_fps
            ),
            (2244, 7761, 8160, 244_800, 3000)
        );
    }
}
