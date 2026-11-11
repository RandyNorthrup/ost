//! Send-side bandwidth estimation, as Teams' clients do it for Call
//! health's "Teams send limit" (network-sent-bw-estimate) and their video
//! encoder: every RTP packet we send carries a transport-wide sequence
//! number (header extension 3, draft-holmer-rmcat-transport-wide-cc-
//! extensions-01, the extension our offers already declare); the meeting's
//! media processor reports when each arrived (RTCP RTPFB, FMT 15), and a
//! Google-congestion-control style estimator turns those reports into the
//! rate the network takes:
//! - delay-based: one-way delay variation between packet groups through a
//!   trendline filter against an adaptive threshold (overuse cuts to 85 %
//!   of what got through, normal grows 8 % a second, underuse holds);
//! - loss-based: under 2 % loss grows 5 %, over 10 % cuts by half the loss;
//! - the estimate is the lower of the two.

use std::collections::{BTreeMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use super::twcc::EXTENSION_ID;

/// Where the estimate starts (bit/s), and its bounds.
const START_BPS: f64 = 600_000.0;
const MIN_BPS: f64 = 80_000.0;
const MAX_BPS: f64 = 4_000_000.0;
/// Packets sent within this of each other are one group (GCC's burst).
const BURST: Duration = Duration::from_millis(5);
/// The trendline filter's window and gain.
const WINDOW: usize = 20;
const TREND_GAIN: f64 = 4.0;
const SMOOTHING: f64 = 0.9;
/// How long send history is kept for matching feedback.
const HISTORY: Duration = Duration::from_secs(5);

/// The estimate for this process's call (bit/s; 0 when nothing yet): Call
/// health and the video encoder read it.
static CURRENT: AtomicU64 = AtomicU64::new(0);

pub fn current_bps() -> u64 {
    CURRENT.load(Ordering::Relaxed)
}

/// One call's send side: shared by the audio and video senders (they
/// share the transport, so the sequence is transport-wide) and the RTCP
/// reader.
pub type Shared = Arc<Mutex<SendSide>>;

pub fn shared() -> Shared {
    CURRENT.store(START_BPS as u64, Ordering::Relaxed);
    Arc::new(Mutex::new(SendSide::new()))
}

/// Call ended: no estimate.
pub fn reset() {
    CURRENT.store(0, Ordering::Relaxed);
}

struct Sent {
    at: Instant,
    size: usize,
}

pub struct SendSide {
    next_seq: u64,
    history: BTreeMap<u64, Sent>,
    estimator: Estimator,
}

impl Default for SendSide {
    fn default() -> Self {
        Self::new()
    }
}

impl SendSide {
    pub fn new() -> Self {
        SendSide { next_seq: 1, history: BTreeMap::new(), estimator: Estimator::new(START_BPS) }
    }

    /// Give an RTP packet (no extensions yet, as ours are built) its
    /// transport-wide sequence number and remember when it went.
    pub fn stamp(&mut self, rtp: &mut Vec<u8>, now: Instant) {
        let seq = self.next_seq;
        self.next_seq += 1;
        if add_extension(rtp, seq as u16) {
            self.history.insert(seq, Sent { at: now, size: rtp.len() });
        }
        while let Some((&first, s)) = self.history.iter().next() {
            if now.duration_since(s.at) > HISTORY {
                self.history.remove(&first);
            } else {
                break;
            }
        }
    }

    /// Feed a decrypted RTCP compound packet; returns the new estimate
    /// when it held transport-wide feedback.
    pub fn on_rtcp(&mut self, rtcp: &[u8], now: Instant) -> Option<f64> {
        let (got, want) = feedback_counts(rtcp);
        if want > 0 {
            self.estimator.loss(got, want, now);
        }
        let mut updated = None;
        for fb in feedback_packets(rtcp) {
            let latest = self.next_seq.saturating_sub(1);
            let mut results = Vec::new();
            for (seq16, arrival) in fb {
                let seq = unwrap_seq(seq16, latest);
                if let Some(s) = self.history.get(&seq) {
                    results.push(PacketResult { send: s.at, size: s.size, arrival_us: arrival });
                }
            }
            if !results.is_empty() {
                updated = Some(self.estimator.update(&results, now));
            }
        }
        if let Some(b) = updated {
            CURRENT.store(b as u64, Ordering::Relaxed);
        }
        updated
    }
}

/// The 64-bit sequence for a 16-bit one, nearest the latest we sent.
fn unwrap_seq(seq: u16, latest: u64) -> u64 {
    let base = latest & !0xffff;
    let candidates = [base.wrapping_sub(0x10000), base, base + 0x10000];
    candidates
        .into_iter()
        .map(|b| b | u64::from(seq))
        .min_by_key(|c| c.abs_diff(latest))
        .unwrap_or(u64::from(seq))
}

/// Append a one-byte header extension (id 3, two bytes) to a packet
/// without extensions. False when the packet already has some.
pub fn add_extension(rtp: &mut Vec<u8>, seq: u16) -> bool {
    if rtp.len() < 12 || rtp[0] & 0x10 != 0 {
        return false;
    }
    let cc = usize::from(rtp[0] & 0x0f);
    let at = 12 + 4 * cc;
    if rtp.len() < at {
        return false;
    }
    rtp[0] |= 0x10;
    let ext = [0xBE, 0xDE, 0x00, 0x01, (EXTENSION_ID << 4) | 1, (seq >> 8) as u8, seq as u8, 0x00];
    rtp.splice(at..at, ext);
    true
}

/// Each transport-wide feedback in a compound packet: (sequence, arrival
/// in µs on the receiver's clock) for every packet it says arrived.
pub fn feedback_packets(rtcp: &[u8]) -> Vec<Vec<(u16, i64)>> {
    let mut out = Vec::new();
    let mut at = 0;
    while at + 4 <= rtcp.len() {
        let fmt = rtcp[at] & 0x1f;
        let pt = rtcp[at + 1];
        let len = (usize::from(u16::from_be_bytes([rtcp[at + 2], rtcp[at + 3]])) + 1) * 4;
        if at + len > rtcp.len() {
            break;
        }
        if pt == 205 && fmt == 15
            && let Some(fb) = parse_feedback(&rtcp[at..at + len])
        {
            out.push(fb);
        }
        at += len;
    }
    out
}

fn parse_feedback(p: &[u8]) -> Option<Vec<(u16, i64)>> {
    if p.len() < 20 {
        return None;
    }
    let base = u16::from_be_bytes([p[12], p[13]]);
    let count = usize::from(u16::from_be_bytes([p[14], p[15]]));
    // 24-bit signed reference time in 64 ms units.
    let raw = (u32::from(p[16]) << 16) | (u32::from(p[17]) << 8) | u32::from(p[18]);
    let reference = if raw & 0x80_0000 != 0 { raw as i64 - 0x100_0000 } else { raw as i64 };
    let mut at = 20;
    let mut symbols = Vec::with_capacity(count);
    while symbols.len() < count {
        let chunk = u16::from_be_bytes([*p.get(at)?, *p.get(at + 1)?]);
        at += 2;
        if chunk & 0x8000 == 0 {
            let symbol = ((chunk >> 13) & 0x3) as u8;
            let run = usize::from(chunk & 0x1fff);
            for _ in 0..run.min(count - symbols.len()) {
                symbols.push(symbol);
            }
        } else if chunk & 0x4000 == 0 {
            for i in 0..14 {
                if symbols.len() == count {
                    break;
                }
                symbols.push(((chunk >> (13 - i)) & 1) as u8);
            }
        } else {
            for i in 0..7 {
                if symbols.len() == count {
                    break;
                }
                symbols.push(((chunk >> (12 - 2 * i)) & 3) as u8);
            }
        }
    }
    let mut time = reference * 64_000;
    let mut out = Vec::new();
    for (i, s) in symbols.iter().enumerate() {
        let seq = base.wrapping_add(i as u16);
        match s {
            1 => {
                time += i64::from(*p.get(at)?) * 250;
                at += 1;
                out.push((seq, time));
            }
            2 => {
                time += i64::from(i16::from_be_bytes([*p.get(at)?, *p.get(at + 1)?])) * 250;
                at += 2;
                out.push((seq, time));
            }
            _ => {}
        }
    }
    // Lost packets are the ones missing from `out` among `count`.
    Some(out)
}

struct PacketResult {
    send: Instant,
    size: usize,
    arrival_us: i64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Usage {
    Normal,
    Over,
    Under,
}

struct Estimator {
    delay_bps: f64,
    loss_bps: f64,
    // Trendline state.
    last_group: Option<(Instant, i64)>,
    group: Option<(Instant, Instant, i64)>,
    accumulated: f64,
    smoothed: f64,
    first_arrival: Option<i64>,
    window: VecDeque<(f64, f64)>,
    threshold: f64,
    last_threshold_update: Option<i64>,
    overuse_since: Option<i64>,
    usage: Usage,
    // Throughput of what arrived, for the decrease step.
    acked: VecDeque<(i64, usize)>,
    last_increase: Option<Instant>,
    last_loss_update: Option<Instant>,
    lost_window: (usize, usize),
}

impl Estimator {
    fn new(start: f64) -> Self {
        Estimator {
            delay_bps: start,
            // No cap from loss until reports say otherwise.
            loss_bps: MAX_BPS,
            last_group: None,
            group: None,
            accumulated: 0.0,
            smoothed: 0.0,
            first_arrival: None,
            window: VecDeque::new(),
            threshold: 12.5,
            last_threshold_update: None,
            overuse_since: None,
            usage: Usage::Normal,
            acked: VecDeque::new(),
            last_increase: None,
            last_loss_update: None,
            lost_window: (0, 0),
        }
    }

    fn acked_bps(&self) -> f64 {
        let (Some(first), Some(last)) = (self.acked.front(), self.acked.back()) else { return 0.0 };
        let span = (last.0 - first.0) as f64 / 1e6;
        if span < 0.2 {
            return 0.0;
        }
        let bytes: usize = self.acked.iter().map(|a| a.1).sum();
        bytes as f64 * 8.0 / span
    }

    fn update(&mut self, results: &[PacketResult], now: Instant) -> f64 {
        let mut sorted: Vec<&PacketResult> = results.iter().collect();
        sorted.sort_by_key(|r| r.send);
        for r in &sorted {
            self.acked.push_back((r.arrival_us, r.size));
            self.packet(r.send, r.arrival_us);
        }
        while let (Some(f), Some(l)) = (self.acked.front(), self.acked.back()) {
            if l.0 - f.0 > 1_000_000 {
                self.acked.pop_front();
            } else {
                break;
            }
        }
        self.rate_control(now);
        self.delay_bps.min(self.loss_bps).clamp(MIN_BPS, MAX_BPS)
    }

    /// Loss from a feedback window: (received, expected).
    fn loss(&mut self, received: usize, expected: usize, now: Instant) {
        self.lost_window.0 += received;
        self.lost_window.1 += expected;
        if self.last_loss_update.is_some_and(|t| now.duration_since(t) < Duration::from_secs(1)) || self.lost_window.1 < 20 {
            return;
        }
        let (got, want) = std::mem::take(&mut self.lost_window);
        let loss = 1.0 - got as f64 / want as f64;
        self.last_loss_update = Some(now);
        let estimate = self.loss_bps.min(self.delay_bps);
        if loss > 0.10 {
            self.loss_bps = (estimate * (1.0 - 0.5 * loss)).max(MIN_BPS);
        } else if loss < 0.02 {
            self.loss_bps = (self.loss_bps * 1.05).min(MAX_BPS);
        }
    }

    fn packet(&mut self, send: Instant, arrival: i64) {
        match self.group {
            Some((first, _, _)) if send.duration_since(first) <= BURST => {
                self.group = Some((first, send, arrival.max(self.group.map_or(arrival, |g| g.2))));
            }
            _ => {
                if let Some((_, last_send, last_arrival)) = self.group.take() {
                    if let Some((prev_send, prev_arrival)) = self.last_group {
                        let send_delta = last_send.duration_since(prev_send).as_secs_f64() * 1000.0;
                        let arrival_delta = (last_arrival - prev_arrival) as f64 / 1000.0;
                        self.trend(arrival_delta - send_delta, last_arrival);
                    }
                    self.last_group = Some((last_send, last_arrival));
                }
                self.group = Some((send, send, arrival));
            }
        }
    }

    fn trend(&mut self, delta_ms: f64, arrival: i64) {
        let first = *self.first_arrival.get_or_insert(arrival);
        self.accumulated += delta_ms;
        self.smoothed = SMOOTHING * self.smoothed + (1.0 - SMOOTHING) * self.accumulated;
        self.window.push_back(((arrival - first) as f64 / 1000.0, self.smoothed));
        if self.window.len() > WINDOW {
            self.window.pop_front();
        }
        if self.window.len() < WINDOW {
            return;
        }
        let n = self.window.len() as f64;
        let (mx, my) = self.window.iter().fold((0.0, 0.0), |(a, b), (x, y)| (a + x, b + y));
        let (mx, my) = (mx / n, my / n);
        let (num, den) = self.window.iter().fold((0.0, 0.0), |(a, b), (x, y)| (a + (x - mx) * (y - my), b + (x - mx) * (x - mx)));
        let slope = if den > 0.0 { num / den } else { 0.0 };
        let modified = slope * n.min(60.0) * TREND_GAIN;
        // Adaptive threshold (GCC: k_up 0.0087, k_down 0.039, ms).
        let now_ms = arrival / 1000;
        let dt = self.last_threshold_update.map_or(0, |t| (now_ms - t).min(100)) as f64;
        self.last_threshold_update = Some(now_ms);
        if modified.abs() < self.threshold + 15.0 {
            let k = if modified.abs() < self.threshold { 0.039 } else { 0.0087 };
            self.threshold = (self.threshold + k * (modified.abs() - self.threshold) * dt).clamp(6.0, 600.0);
        }
        self.usage = if modified > self.threshold {
            let since = *self.overuse_since.get_or_insert(now_ms);
            if now_ms - since >= 10 { Usage::Over } else { self.usage }
        } else if modified < -self.threshold {
            self.overuse_since = None;
            Usage::Under
        } else {
            self.overuse_since = None;
            Usage::Normal
        };
    }

    fn rate_control(&mut self, now: Instant) {
        let dt = self.last_increase.map_or(0.0, |t| now.duration_since(t).as_secs_f64().min(1.0));
        self.last_increase = Some(now);
        match self.usage {
            Usage::Over => {
                let acked = self.acked_bps();
                let base = if acked > 0.0 { acked } else { self.delay_bps };
                self.delay_bps = (0.85 * base).max(MIN_BPS);
                // One cut per overuse episode.
                self.usage = Usage::Normal;
                self.overuse_since = None;
            }
            Usage::Normal => {
                // Don't run far ahead of what actually gets through.
                let acked = self.acked_bps();
                let cap = if acked > 0.0 { 1.5 * acked + 10_000.0 } else { MAX_BPS };
                self.delay_bps = (self.delay_bps * 1.08f64.powf(dt)).min(cap.max(self.delay_bps)).min(MAX_BPS);
            }
            Usage::Under => {}
        }
    }
}

/// Expected and received packet counts in a compound packet's feedback.
pub fn feedback_counts(rtcp: &[u8]) -> (usize, usize) {
    let mut at = 0;
    let (mut got, mut want) = (0, 0);
    while at + 4 <= rtcp.len() {
        let fmt = rtcp[at] & 0x1f;
        let pt = rtcp[at + 1];
        let len = (usize::from(u16::from_be_bytes([rtcp[at + 2], rtcp[at + 3]])) + 1) * 4;
        if at + len > rtcp.len() {
            break;
        }
        if pt == 205 && fmt == 15 && len >= 20 {
            want += usize::from(u16::from_be_bytes([rtcp[at + 14], rtcp[at + 15]]));
            if let Some(fb) = parse_feedback(&rtcp[at..at + len]) {
                got += fb.len();
            }
        }
        at += len;
    }
    (got, want)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extension_is_added_as_teams_reads_it() {
        let mut p = vec![0x80, 111, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0xAA, 0xBB];
        assert!(add_extension(&mut p, 0x1234));
        assert_eq!(super::super::twcc::sequence_number(&p), Some(0x1234));
        assert_eq!(&p[p.len() - 2..], &[0xAA, 0xBB]);
        assert!(!add_extension(&mut p, 1), "only once");
    }

    /// A feedback packet: base 100, 4 packets (received, received,
    /// lost, received large), reference time 1 (64 ms).
    fn sample() -> Vec<u8> {
        let mut p = vec![0x8f, 205, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2];
        p.extend_from_slice(&100u16.to_be_bytes());
        p.extend_from_slice(&4u16.to_be_bytes());
        p.extend_from_slice(&[0, 0, 1, 7]);
        // Status vector, 2-bit symbols: 1, 1, 0, 2, then padding.
        let chunk: u16 = 0xC000 | (1 << 12) | (1 << 10) | (2 << 6);
        p.extend_from_slice(&chunk.to_be_bytes());
        p.extend_from_slice(&[4, 8]); // 1 ms, 2 ms
        p.extend_from_slice(&(-4i16).to_be_bytes()); // -1 ms
        while p.len() % 4 != 0 {
            p.push(0);
        }
        let words = (p.len() / 4 - 1) as u16;
        p[2..4].copy_from_slice(&words.to_be_bytes());
        p
    }

    #[test]
    fn feedback_is_read() {
        let fb = feedback_packets(&sample());
        assert_eq!(fb, vec![vec![(100, 65_000), (101, 67_000), (103, 66_000)]]);
        assert_eq!(feedback_counts(&sample()), (3, 4));
    }

    #[test]
    fn sequence_unwraps_near_the_latest() {
        assert_eq!(unwrap_seq(65535, 65537), 65535);
        assert_eq!(unwrap_seq(1, 65537), 65537);
        assert_eq!(unwrap_seq(10, 5), 10);
    }

    #[test]
    fn steady_delivery_grows_and_queueing_cuts() {
        let mut e = Estimator::new(START_BPS);
        let t0 = Instant::now();
        let mut arrival = 0i64;
        // 2 s of 1200-byte packets every 10 ms arriving evenly: grows.
        for i in 0..200 {
            let send = t0 + Duration::from_millis(i * 10);
            arrival += 10_000;
            e.update(&[PacketResult { send, size: 1200, arrival_us: arrival }], send);
        }
        let grown = e.delay_bps.min(e.loss_bps);
        assert!(grown > START_BPS, "{grown}");
        // Then each packet arrives 3 ms later than the last: queues build.
        for i in 200..400 {
            let send = t0 + Duration::from_millis(i * 10);
            arrival += 13_000;
            e.update(&[PacketResult { send, size: 1200, arrival_us: arrival }], send);
        }
        assert!(e.delay_bps < grown, "{} < {grown}", e.delay_bps);
    }

    #[test]
    fn heavy_loss_cuts() {
        let mut e = Estimator::new(1_000_000.0);
        let t0 = Instant::now();
        e.loss(70, 100, t0);
        e.loss(70, 100, t0 + Duration::from_secs(2));
        assert!(e.loss_bps < 1_000_000.0);
    }
}
