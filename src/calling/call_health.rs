//! Teams' Call health pane (More ▸ Settings ▸ Call health; research:
//! scratchpad ch/spec.md, session 744c3998): what OST measures of the
//! call's media and how Teams turns it into the pane's values.
//!
//! - **Counting** ([`Media`]): the media paths count what they send and
//!   receive per stream (bytes, packets, frames, size, loss), the peer's
//!   receiver reports give round-trip times (RFC 3550: now − LSR − DLSR),
//!   arrival times give the received audio's jitter (RFC 3550 A.8), and
//!   the media processor's estimate gives the receive limit.
//! - **Sampling** ([`Sampler`]): every second a snapshot; Teams computes
//!   each value over the last 15 (`teamsRealtimeTelemetry.pollingInterval`)
//!   — averages of the per-second deltas for bitrates and frame rates, the
//!   difference for packet counts, the last value for sizes and loss, and
//!   running means since the start for round-trip time and jitter.
//! - **Showing** ([`Report`]): Teams' formatters ("29.00 ms", "0.00%",
//!   "40 Kbps", "1.25 Mbps", "30.00 fps", "1280 x 720 px", "742 packets"),
//!   "--" when there's nothing, keyed by the pane's data-tids.
//!
//! OST has no send-side bandwidth estimator, so "Teams send limit" shows
//! "--" (the estimate is a separate piece of work).

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

/// One stream's running counts.
#[derive(Debug, Default)]
pub struct Stream {
    pub bytes: AtomicU64,
    pub packets: AtomicU64,
    pub frames: AtomicU64,
    pub width: AtomicU32,
    pub height: AtomicU32,
    /// Received: packets expected by sequence number (for the loss rate).
    pub expected: AtomicU64,
    /// The latest round-trip time (µs; 0 = none) from a receiver report.
    pub rtt_us: AtomicU64,
    /// The latest interarrival jitter (µs).
    pub jitter_us: AtomicU64,
    loss: Mutex<SequenceTracker>,
    jitter: Mutex<JitterTracker>,
}

impl Stream {
    /// A packet went out: its payload bytes.
    pub fn sent(&self, payload: usize) {
        self.bytes.fetch_add(payload as u64, Ordering::Relaxed);
        self.packets.fetch_add(1, Ordering::Relaxed);
    }

    /// A packet arrived: its payload bytes and sequence number.
    pub fn received(&self, payload: usize, seq: u16) {
        self.bytes.fetch_add(payload as u64, Ordering::Relaxed);
        self.packets.fetch_add(1, Ordering::Relaxed);
        let grew = self
            .loss
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .on_packet(seq);
        self.expected.fetch_add(grew, Ordering::Relaxed);
    }

    /// Received audio's arrival (RTP timestamp at `clock` Hz, seconds on a
    /// monotonic clock): updates the jitter.
    pub fn arrived(&self, rtp_ts: u32, at_s: f64, clock: u32) {
        let j = self
            .jitter
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .on_packet(rtp_ts, at_s, clock);
        self.jitter_us.store((j * 1e6) as u64, Ordering::Relaxed);
    }

    pub fn frame(&self, width: u32, height: u32) {
        self.frames.fetch_add(1, Ordering::Relaxed);
        self.width.store(width, Ordering::Relaxed);
        self.height.store(height, Ordering::Relaxed);
    }

    /// A receiver report's block on this stream: LSR and DLSR (RFC 3550).
    pub fn report(&self, lsr: u32, dlsr: u32) {
        if let Some(rtt) = rtt_seconds(lsr, dlsr, ntp_middle_now()) {
            self.rtt_us.store((rtt * 1e6) as u64, Ordering::Relaxed);
        }
    }

    fn snapshot(&self) -> Counts {
        let o = Ordering::Relaxed;
        Counts {
            bytes: self.bytes.load(o),
            packets: self.packets.load(o),
            frames: self.frames.load(o),
            expected: self.expected.load(o),
            width: self.width.load(o),
            height: self.height.load(o),
            rtt_ms: match self.rtt_us.load(o) {
                0 => None,
                us => Some(us as f64 / 1000.0),
            },
            jitter_ms: self.jitter_us.load(o) as f64 / 1000.0,
        }
    }
}

/// Packets expected by sequence number.
#[derive(Debug, Default)]
struct SequenceTracker {
    highest: Option<u16>,
}

impl SequenceTracker {
    /// How many more packets are now expected.
    fn on_packet(&mut self, seq: u16) -> u64 {
        match self.highest {
            None => {
                self.highest = Some(seq);
                1
            }
            Some(h) => {
                let d = seq.wrapping_sub(h);
                if d != 0 && d < 0x8000 {
                    self.highest = Some(seq);
                    u64::from(d)
                } else {
                    0
                }
            }
        }
    }
}

/// RFC 3550 A.8 interarrival jitter, in seconds.
#[derive(Debug, Default)]
struct JitterTracker {
    last: Option<(u32, f64)>,
    jitter: f64,
}

impl JitterTracker {
    fn on_packet(&mut self, rtp_ts: u32, at_s: f64, clock: u32) -> f64 {
        if let Some((ts, at)) = self.last {
            let rtp_gap = rtp_ts.wrapping_sub(ts) as i32 as f64 / f64::from(clock);
            let d = ((at_s - at) - rtp_gap).abs();
            self.jitter += (d - self.jitter) / 16.0;
        }
        self.last = Some((rtp_ts, at_s));
        self.jitter
    }
}

/// The middle 32 bits of the NTP time now (RTCP's LSR clock).
pub fn ntp_middle_now() -> u32 {
    (super::rtcp::ntp_timestamp() >> 16) as u32
}

/// Round-trip time from a report block: now − LSR − DLSR, in seconds
/// (all in 1/65536 s); None without an SR to refer to.
pub fn rtt_seconds(lsr: u32, dlsr: u32, now_middle: u32) -> Option<f64> {
    if lsr == 0 {
        return None;
    }
    let rtt = now_middle.wrapping_sub(lsr).wrapping_sub(dlsr);
    // A report from the future or older than ~an hour is nonsense.
    (rtt < 0x8000_0000).then(|| f64::from(rtt) / 65536.0)
}

/// What kind a stream is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    AudioSend,
    AudioRecv,
    VideoSend,
    VideoRecv,
    ShareSend,
    ShareRecv,
}

/// The call's media, as the paths count it.
#[derive(Debug, Default)]
pub struct Media {
    streams: Mutex<HashMap<(Kind, u32), Arc<Stream>>>,
    /// The media processor's estimate of what we can receive (bit/s).
    pub receive_estimate: AtomicU64,
    codecs: Mutex<HashMap<Kind, String>>,
}

impl Media {
    /// The stream of `kind` with SSRC `ssrc` (created on first use).
    pub fn stream(&self, kind: Kind, ssrc: u32) -> Arc<Stream> {
        self.streams
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry((kind, ssrc))
            .or_default()
            .clone()
    }

    /// Our sending stream with this SSRC, if one is known.
    pub fn sending(&self, ssrc: u32) -> Option<Arc<Stream>> {
        let s = self.streams.lock().unwrap_or_else(|e| e.into_inner());
        [Kind::AudioSend, Kind::VideoSend, Kind::ShareSend]
            .iter()
            .find_map(|k| s.get(&(*k, ssrc)).cloned())
    }

    /// The codec a kind of stream uses, as Teams names it ("OPUS", "H264 sw").
    pub fn set_codec(&self, kind: Kind, name: &str) {
        self.codecs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(kind, name.to_string());
    }

    fn snapshot(&self, at_ms: i64) -> Snapshot {
        let streams = self.streams.lock().unwrap_or_else(|e| e.into_inner());
        let sum = |kind: Kind| -> Option<Counts> {
            let all: Vec<Counts> = streams
                .iter()
                .filter(|((k, _), _)| *k == kind)
                .map(|(_, s)| s.snapshot())
                .collect();
            if all.is_empty() {
                return None;
            }
            Some(all.iter().fold(Counts::default(), |a, c| Counts {
                bytes: a.bytes + c.bytes,
                packets: a.packets + c.packets,
                frames: a.frames + c.frames,
                expected: a.expected + c.expected,
                width: a.width.max(c.width),
                height: a.height.max(c.height),
                rtt_ms: a.rtt_ms.or(c.rtt_ms),
                jitter_ms: a.jitter_ms.max(c.jitter_ms),
            }))
        };
        Snapshot {
            at_ms,
            streams: [
                Kind::AudioSend,
                Kind::AudioRecv,
                Kind::VideoSend,
                Kind::VideoRecv,
                Kind::ShareSend,
                Kind::ShareRecv,
            ]
            .into_iter()
            .filter_map(|k| sum(k).map(|c| (k, c)))
            .collect(),
            receive_estimate: self.receive_estimate.load(Ordering::Relaxed),
        }
    }
}

/// The call's media now (one call at a time; a new call starts afresh).
pub fn current() -> Arc<Media> {
    slot().lock().unwrap_or_else(|e| e.into_inner()).clone()
}

/// A new call: forget the last one's counts.
pub fn begin_call() {
    *slot().lock().unwrap_or_else(|e| e.into_inner()) = Arc::default();
}

fn slot() -> &'static Mutex<Arc<Media>> {
    static SLOT: OnceLock<Mutex<Arc<Media>>> = OnceLock::new();
    SLOT.get_or_init(Default::default)
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
struct Counts {
    bytes: u64,
    packets: u64,
    frames: u64,
    expected: u64,
    width: u32,
    height: u32,
    rtt_ms: Option<f64>,
    jitter_ms: f64,
}

#[derive(Debug, Clone, Default)]
struct Snapshot {
    at_ms: i64,
    streams: HashMap<Kind, Counts>,
    receive_estimate: u64,
}

/// Teams' window: 15 one-second samples.
pub const WINDOW: usize = 15;

/// Teams' running mean (since the stream started).
#[derive(Debug, Clone, Copy, Default)]
struct Mean {
    sum: f64,
    n: u64,
}

impl Mean {
    fn add(&mut self, v: f64) {
        self.sum += v;
        self.n += 1;
    }
    fn get(&self) -> Option<f64> {
        (self.n > 0).then(|| self.sum / self.n as f64)
    }
}

/// The last 15 seconds, and the running means.
#[derive(Debug, Default)]
pub struct Sampler {
    window: VecDeque<Snapshot>,
    rtt: HashMap<Kind, Mean>,
    jitter: Mean,
    /// Teams' loss rate per received kind: Δlost / Δexpected, renewed once
    /// 100 more packets have come.
    loss: HashMap<Kind, (u64, u64, f64)>,
}

impl Sampler {
    pub fn new() -> Self {
        Self::default()
    }

    /// Take this second's snapshot of `media`.
    pub fn sample(&mut self, media: &Media, now_ms: i64) {
        let snap = media.snapshot(now_ms);
        for (kind, c) in &snap.streams {
            if let Some(rtt) = c.rtt_ms {
                self.rtt.entry(*kind).or_default().add(rtt);
            }
            if *kind == Kind::AudioRecv && c.packets > 0 {
                self.jitter.add(c.jitter_ms);
            }
            if matches!(kind, Kind::AudioRecv | Kind::VideoRecv | Kind::ShareRecv) {
                let e = self
                    .loss
                    .entry(*kind)
                    .or_insert((c.expected, c.packets, 0.0));
                let (de, dr) = (
                    c.expected.saturating_sub(e.0),
                    c.packets.saturating_sub(e.1),
                );
                if dr >= 100 {
                    let lost = de.saturating_sub(dr);
                    e.2 = (lost as f64 / (lost + dr) as f64).clamp(0.0, 1.0);
                    e.0 = c.expected;
                    e.1 = c.packets;
                }
            }
        }
        self.window.push_back(snap);
        while self.window.len() > WINDOW {
            self.window.pop_front();
        }
    }

    /// The average per-second change of a counter over the window.
    fn rate(&self, kind: Kind, f: impl Fn(&Counts) -> u64) -> Option<f64> {
        let pts: Vec<(i64, u64)> = self
            .window
            .iter()
            .filter_map(|s| s.streams.get(&kind).map(|c| (s.at_ms, f(c))))
            .collect();
        let (first, last) = (pts.first()?, pts.last()?);
        let secs = (last.0 - first.0) as f64 / 1000.0;
        (secs > 0.0).then(|| last.1.saturating_sub(first.1) as f64 / secs)
    }

    /// The change over the window (Teams' Difference).
    fn difference(&self, kind: Kind, f: impl Fn(&Counts) -> u64) -> Option<u64> {
        let pts: Vec<u64> = self
            .window
            .iter()
            .filter_map(|s| s.streams.get(&kind).map(&f))
            .collect();
        Some(pts.last()?.saturating_sub(*pts.first()?))
    }

    fn last(&self, kind: Kind) -> Option<Counts> {
        self.window.back()?.streams.get(&kind).copied()
    }

    /// Teams' values for the pane.
    pub fn report(&self, media: &Media, state: &MediaState) -> Report {
        let codecs = media
            .codecs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let codec = |k: Kind| codecs.get(&k).cloned().unwrap_or_default();
        let processing = |k: Kind| processing_type(&codec(k));
        let bps = |k: Kind| self.rate(k, |c| c.bytes).map(|b| b * 8.0);
        let fps = |k: Kind| self.rate(k, |c| c.frames);
        let res = |k: Kind| {
            self.last(k)
                .filter(|c| c.width > 0 && c.height > 0)
                .map(|c| format!("{} x {}", c.width, c.height))
        };
        let rtt = |k: Kind| self.rtt.get(&k).and_then(Mean::get);
        let loss = |k: Kind| self.loss.get(&k).map(|l| l.2);
        let packets = |k: Kind| self.difference(k, |c| c.packets);
        let receive_estimate = self.window.back().map_or(0, |s| s.receive_estimate);

        // Network: the worst of the streams (Teams' max over strings that
        // start at 0, so no data shows as 0 for loss and "--" for time).
        let net_rtt = [Kind::AudioSend, Kind::VideoSend, Kind::ShareSend]
            .iter()
            .filter_map(|k| rtt(*k))
            .fold(0.0, f64::max);
        let net_loss = [Kind::AudioRecv, Kind::VideoRecv, Kind::ShareRecv]
            .iter()
            .filter_map(|k| loss(*k))
            .fold(0.0, f64::max);

        let mut r = Report::default();
        let mut put = |tid: &str, value: String, enabled: bool| {
            r.values.insert(tid.to_string(), Value { value, enabled });
        };
        put("network-sent-bw-estimate", String::new(), true);
        put(
            "network-received-bw-estimate",
            mbps(receive_estimate as f64),
            true,
        );
        put("network-send-rtt-avg", ms(net_rtt), true);
        put("network-recv-loss-rate-avg", percent(net_loss), true);

        let mic = state.microphone;
        put(
            "audio-send-bps",
            bps(Kind::AudioSend).map(kbps).unwrap_or_default(),
            mic,
        );
        put(
            "audio-rtp-packets-sent",
            packets(Kind::AudioSend)
                .map(packets_text)
                .unwrap_or_default(),
            mic,
        );
        put(
            "audio-send-rtt-avg",
            rtt(Kind::AudioSend).map(ms).unwrap_or_default(),
            mic,
        );
        put("audio-send-codec", codec(Kind::AudioSend), mic);
        put(
            "audio-nw-jitter-avg",
            self.jitter.get().map(ms).unwrap_or_default(),
            true,
        );
        put(
            "audio-recv-loss-rate-avg",
            loss(Kind::AudioRecv).map(percent).unwrap_or_default(),
            true,
        );
        put(
            "audio-rtp-packets-received",
            packets(Kind::AudioRecv)
                .map(packets_text)
                .unwrap_or_default(),
            true,
        );
        put("audio-received-codec", codec(Kind::AudioRecv), true);

        let cam = state.camera;
        put(
            "video-send-current-bitrate",
            bps(Kind::VideoSend).map(mbps).unwrap_or_default(),
            cam,
        );
        put(
            "video-receive-current-bitrate",
            bps(Kind::VideoRecv).map(mbps).unwrap_or_default(),
            true,
        );
        put(
            "video-send-current-frame-rate",
            fps(Kind::VideoSend).map(fps_text).unwrap_or_default(),
            cam,
        );
        put(
            "video-send-resolution",
            res(Kind::VideoSend)
                .map(|v| format!("{v} px"))
                .unwrap_or_default(),
            cam,
        );
        put(
            "video-send-rtt-avg",
            rtt(Kind::VideoSend).map(ms).unwrap_or_default(),
            cam,
        );
        put(
            "video-rtp-packets-sent",
            packets(Kind::VideoSend)
                .map(packets_text)
                .unwrap_or_default(),
            cam,
        );
        put("video-sent-codec-name", codec(Kind::VideoSend), cam);
        put("video-processing-type", processing(Kind::VideoSend), cam);

        let sharing = state.sharing;
        let watching = state.watching_share;
        put(
            "screen-sharing-send-current-bitrate",
            bps(Kind::ShareSend).map(mbps).unwrap_or_default(),
            sharing,
        );
        put(
            "screen-sharing-send-current-frame-rate",
            fps(Kind::ShareSend).map(fps_text).unwrap_or_default(),
            sharing,
        );
        put(
            "screen-sharing-send-resolution",
            res(Kind::ShareSend)
                .map(|v| format!("{v} px"))
                .unwrap_or_default(),
            sharing,
        );
        put(
            "screen-sharing-send-rtt-avg",
            rtt(Kind::ShareSend).map(ms).unwrap_or_default(),
            sharing,
        );
        put(
            "screen-sharing-rtp-packets-sent",
            packets(Kind::ShareSend)
                .map(packets_text)
                .unwrap_or_default(),
            sharing,
        );
        put(
            "screen-sharing-sent-codec-name",
            codec(Kind::ShareSend),
            sharing,
        );
        put(
            "screen-sharing-send-processing-type",
            processing(Kind::ShareSend),
            sharing,
        );
        put(
            "screen-sharing-receive-current-bitrate",
            bps(Kind::ShareRecv).map(mbps).unwrap_or_default(),
            watching,
        );
        put(
            "screen-sharing-receive-current-frame-rate",
            fps(Kind::ShareRecv).map(fps_text).unwrap_or_default(),
            watching,
        );
        put(
            "screen-sharing-received-resolution",
            res(Kind::ShareRecv)
                .map(|v| format!("{v} px"))
                .unwrap_or_default(),
            watching,
        );
        put(
            "screen-sharing-recv-loss-rate-avg",
            loss(Kind::ShareRecv).map(percent).unwrap_or_default(),
            watching,
        );
        put(
            "screen-sharing-rtp-packets-received",
            packets(Kind::ShareRecv)
                .map(packets_text)
                .unwrap_or_default(),
            watching,
        );
        put(
            "screen-sharing-received-codec",
            codec(Kind::ShareRecv),
            watching,
        );
        put(
            "screen-sharing-received-processing-type",
            processing(Kind::ShareRecv),
            watching,
        );
        r
    }
}

/// What's on in the call (Teams turns metrics off with it).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct MediaState {
    pub microphone: bool,
    pub camera: bool,
    pub sharing: bool,
    /// Someone else is presenting.
    pub watching_share: bool,
}

/// One metric's text ("" for none: the pane shows "--") and whether it's on.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Value {
    pub value: String,
    pub enabled: bool,
}

/// The pane's values by data-tid.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Report {
    pub values: HashMap<String, Value>,
}

/// JavaScript's `parseFloat(x.toFixed(2))`: two decimals, trailing zeros
/// dropped.
fn trimmed(v: f64) -> String {
    let s = format!("{v:.2}");
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s == "-0" { "0".into() } else { s.into() }
}

/// Teams' `convertToMs`: none for 0.
pub fn ms(v: f64) -> String {
    if v == 0.0 || v.is_nan() {
        String::new()
    } else {
        format!("{v:.2} ms")
    }
}

/// Teams' `convertToPercentage` of a 0–1 fraction (0 shows "0.00%").
pub fn percent(v: f64) -> String {
    format!("{:.2}%", v * 100.0)
}

/// Teams' `convertToKBps` (audio: Kbps from bit/s; none for 0).
pub fn kbps(bits: f64) -> String {
    let b = bits.trunc();
    if b == 0.0 {
        String::new()
    } else {
        format!("{} Kbps", trimmed(b / 1000.0))
    }
}

/// Teams' `convertToMBps` (Mbps from bit/s; none for 0).
pub fn mbps(bits: f64) -> String {
    let b = bits.trunc();
    if b == 0.0 {
        String::new()
    } else {
        format!("{} Mbps", trimmed(b / 1e6))
    }
}

/// Teams' `convertToFps` (none for 0).
pub fn fps_text(v: f64) -> String {
    if v == 0.0 || v.is_nan() {
        String::new()
    } else {
        format!("{v:.2} fps")
    }
}

/// Teams' `convertToPackets` (none for 0).
pub fn packets_text(n: u64) -> String {
    if n == 0 {
        String::new()
    } else {
        format!("{n} packets")
    }
}

/// Teams' processing type, from a codec name's hw / sw tag.
pub fn processing_type(codec: &str) -> String {
    let c = codec.to_ascii_uppercase();
    let sw = c.contains("SW");
    let hw = c.contains("HW") || c.contains("CAM");
    if c.contains("INVALID") || codec.is_empty() {
        String::new()
    } else if sw && hw {
        "Hardware + Software".into()
    } else if sw {
        "Software enabled".into()
    } else if hw {
        "Hardware enabled".into()
    } else {
        String::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values_are_written_as_teams_writes_them() {
        assert_eq!(ms(29.0), "29.00 ms");
        assert_eq!(ms(0.0), "");
        assert_eq!(percent(0.0), "0.00%");
        assert_eq!(percent(0.0123), "1.23%");
        assert_eq!(kbps(40_000.0), "40 Kbps");
        assert_eq!(kbps(32_500.0), "32.5 Kbps");
        assert_eq!(mbps(1_250_000.0), "1.25 Mbps");
        assert_eq!(mbps(300_000.0), "0.3 Mbps");
        assert_eq!(mbps(2_000_000.0), "2 Mbps");
        assert_eq!(mbps(4_000.0), "0 Mbps");
        assert_eq!(mbps(0.0), "");
        assert_eq!(fps_text(30.0), "30.00 fps");
        assert_eq!(packets_text(742), "742 packets");
        assert_eq!(processing_type("H264 sw"), "Software enabled");
        assert_eq!(processing_type("H264 hw"), "Hardware enabled");
        assert_eq!(processing_type("OPUS"), "");
    }

    #[test]
    fn round_trip_is_now_less_lsr_less_dlsr() {
        // Sent at 100 s, held 0.5 s by the peer, back at 100.6 s: 0.1 s.
        let lsr = 100 << 16;
        let dlsr = 1 << 15;
        let now = (100 << 16) + 39_322; // 0.6 s later
        let rtt = rtt_seconds(lsr, dlsr, now).unwrap();
        assert!((rtt - 0.1).abs() < 0.001, "{rtt}");
        assert_eq!(rtt_seconds(0, dlsr, now), None);
        assert_eq!(
            rtt_seconds(lsr, dlsr, lsr),
            None,
            "a report from the future"
        );
    }

    #[test]
    fn jitter_follows_rfc_3550() {
        let mut j = JitterTracker::default();
        // 20 ms packets at 48 kHz arriving every 20 ms: no jitter.
        for i in 0..50u32 {
            j.on_packet(i * 960, f64::from(i) * 0.02, 48_000);
        }
        assert!(j.jitter < 1e-9);
        // One packet 16 ms late moves it by 1/16 of that.
        let v = j.on_packet(50 * 960, 50.0 * 0.02 + 0.016, 48_000);
        assert!((v - 0.001).abs() < 1e-6, "{v}");
    }

    #[test]
    fn a_window_of_samples_gives_teams_values() {
        let media = Media::default();
        let send = media.stream(Kind::AudioSend, 1);
        let recv = media.stream(Kind::AudioRecv, 2);
        media.set_codec(Kind::AudioSend, "OPUS");
        media.receive_estimate.store(2_740_000, Ordering::Relaxed);
        let mut s = Sampler::new();
        let mut seq = 0u16;
        for sec in 0..20i64 {
            for _ in 0..50 {
                send.sent(100); // 50 × 100 bytes a second: 40 kbit/s
                // Every 10th packet lost.
                seq = seq.wrapping_add(if seq % 10 == 9 { 2 } else { 1 });
                recv.received(80, seq);
            }
            send.rtt_us.store(29_000, Ordering::Relaxed);
            s.sample(&media, sec * 1000);
        }
        let r = s.report(
            &media,
            &MediaState {
                microphone: true,
                ..Default::default()
            },
        );
        let v = |t: &str| r.values[t].value.clone();
        assert_eq!(v("audio-send-bps"), "40 Kbps");
        assert_eq!(v("audio-rtp-packets-sent"), "700 packets");
        assert_eq!(v("audio-send-rtt-avg"), "29.00 ms");
        assert_eq!(v("network-send-rtt-avg"), "29.00 ms");
        assert_eq!(v("audio-send-codec"), "OPUS");
        assert_eq!(v("network-received-bw-estimate"), "2.74 Mbps");
        assert_eq!(v("network-sent-bw-estimate"), "");
        assert_eq!(v("video-send-current-bitrate"), "");
        assert_eq!(
            v("audio-recv-loss-rate-avg"),
            v("network-recv-loss-rate-avg")
        );
        assert!(
            v("audio-recv-loss-rate-avg").starts_with("9."),
            "{}",
            v("audio-recv-loss-rate-avg")
        );
        // Muted: Teams turns the send metrics off.
        let muted = s.report(&media, &MediaState::default());
        assert!(!muted.values["audio-send-bps"].enabled);
        assert!(muted.values["audio-nw-jitter-avg"].enabled);
    }
}
