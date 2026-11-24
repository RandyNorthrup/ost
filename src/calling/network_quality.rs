//! Your connection's quality as Teams rates it for its network strength
//! indicator (the bars in your name tag), following Teams' calling stack
//! (`processInboundSample` / `processOutboundSample`, sampled every second,
//! `webrtcStatPollInterval` 1000):
//!
//! - Receiving: the share of audio that had to be concealed ("healed"),
//!   averaged over the last 5 samples once 10 s of audio has arrived; Good
//!   below 0.175, Bad from 0.265, Poor between, with Teams' 0.01
//!   hysteresis around its 0.18 and 0.26 levels. OST plays what arrives
//!   without concealment, so the missing share is the packets lost.
//! - Sending (after 200 packets): the peer's reports on our audio — jitter
//!   averaged over 3 samples (Good below 0.2 s, Bad above 0.35 s) and the
//!   loss rate (Good below 0.2, Bad above 0.3), each holding a Bad rating
//!   for 5 s before it may return to Good.
//! - The indicator shows the worse of the two.

/// Teams' three levels.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Strength {
    Good,
    Poor,
    Bad,
}

impl Strength {
    pub fn name(self) -> &'static str {
        match self {
            Strength::Good => "Good",
            Strength::Poor => "Poor",
            Strength::Bad => "Bad",
        }
    }
}

const GOOD_LEVEL: f64 = 0.18;
const BAD_LEVEL: f64 = 0.26;
const HYSTERESIS: f64 = 0.01;
const HEALED_WINDOW: usize = 5;
const JITTER_WINDOW: usize = 3;
/// 10 s of audio at 48 kHz.
const MIN_SAMPLES_RECEIVED: u64 = 48_000 * 10;
const MIN_PACKETS_SENT: u64 = 200;
const STICKINESS_MS: u64 = 5_000;

/// Teams' two-threshold rating with a sticky Bad (`WO` with `UK`).
#[derive(Debug, Clone)]
struct StateProcessor {
    low: f64,
    high: f64,
    in_lower: bool,
    current: bool, // true: Good
    stick_started: Option<u64>,
}

impl StateProcessor {
    fn new(low: f64, high: f64) -> Self {
        StateProcessor { low, high, in_lower: true, current: true, stick_started: None }
    }

    /// Rate a sample taken at `now_ms`; true is Good.
    fn on_sample(&mut self, value: f64, now_ms: u64) -> bool {
        let mut lower = self.in_lower;
        if self.in_lower {
            if value > self.high {
                lower = false;
            }
        } else if value < self.low {
            lower = true;
        }
        let wanted = lower;
        // The stickiness: leaving Bad waits for the wanted Good to last.
        let result = if wanted == self.current {
            self.stick_started = None;
            self.current
        } else if !self.current {
            match self.stick_started {
                None => {
                    self.stick_started = Some(now_ms);
                    self.current
                }
                Some(t) if now_ms.saturating_sub(t) > STICKINESS_MS => {
                    self.current = wanted;
                    self.stick_started = None;
                    self.current
                }
                Some(_) => self.current,
            }
        } else {
            self.current = wanted;
            self.stick_started = None;
            self.current
        };
        // Teams moves its range only when the result differs from what the
        // old range rated.
        if result != self.in_lower {
            self.in_lower = lower;
        }
        result
    }
}

/// One second's measurements.
#[derive(Debug, Clone, Copy, Default)]
pub struct Sample {
    /// Audio samples received so far in the call.
    pub samples_received: u64,
    /// The share of this second's expected audio that didn't arrive.
    pub missing_ratio: Option<f64>,
    /// Packets we've sent so far.
    pub packets_sent: u64,
    /// The peer's latest report on our audio: jitter in seconds and the
    /// fraction lost (0–1).
    pub remote_jitter: Option<f64>,
    pub remote_loss: Option<f64>,
}

/// The rating as samples come in.
#[derive(Debug, Clone)]
pub struct Rater {
    healed: std::collections::VecDeque<f64>,
    jitter: std::collections::VecDeque<f64>,
    inbound: Strength,
    jitter_state: StateProcessor,
    loss_state: StateProcessor,
    outbound: Strength,
}

impl Default for Rater {
    fn default() -> Self {
        Rater {
            healed: Default::default(),
            jitter: Default::default(),
            inbound: Strength::Good,
            jitter_state: StateProcessor::new(0.2, 0.35),
            loss_state: StateProcessor::new(0.2, 0.3),
            outbound: Strength::Good,
        }
    }
}

fn mean(v: &std::collections::VecDeque<f64>) -> f64 {
    v.iter().sum::<f64>() / v.len().max(1) as f64
}

impl Rater {
    /// Take one second's sample (at `now_ms`) and return the strength.
    pub fn sample(&mut self, s: Sample, now_ms: u64) -> Strength {
        if let Some(r) = s.missing_ratio {
            self.healed.push_back(r.clamp(0.0, 1.0));
            while self.healed.len() > HEALED_WINDOW {
                self.healed.pop_front();
            }
        }
        if s.samples_received >= MIN_SAMPLES_RECEIVED && self.healed.len() == HEALED_WINDOW {
            let m = mean(&self.healed);
            if m > 0.0 {
                self.inbound = self.inbound_level(m);
            }
        }
        if s.packets_sent >= MIN_PACKETS_SENT {
            if let Some(j) = s.remote_jitter {
                self.jitter.push_back(j);
                while self.jitter.len() > JITTER_WINDOW {
                    self.jitter.pop_front();
                }
            }
            let jitter_good = if self.jitter.len() == JITTER_WINDOW {
                self.jitter_state.on_sample(mean(&self.jitter), now_ms)
            } else {
                true
            };
            let loss_good = match s.remote_loss {
                Some(l) if l > 0.0 => self.loss_state.on_sample(l, now_ms),
                _ => true,
            };
            self.outbound = if jitter_good && loss_good { Strength::Good } else { Strength::Bad };
        }
        self.inbound.max(self.outbound)
    }

    /// Teams' `determineInboundQualityLevel`.
    fn inbound_level(&self, m: f64) -> Strength {
        let (bad_hi, bad_lo) = (BAD_LEVEL + HYSTERESIS / 2.0, BAD_LEVEL - HYSTERESIS / 2.0);
        let (good_hi, good_lo) = (GOOD_LEVEL + HYSTERESIS / 2.0, GOOD_LEVEL - HYSTERESIS / 2.0);
        let was = self.inbound;
        if m < good_lo {
            Strength::Good
        } else if m < good_hi {
            if was == Strength::Good { Strength::Good } else { Strength::Poor }
        } else if m < bad_lo {
            Strength::Poor
        } else if m < bad_hi {
            if was == Strength::Bad { Strength::Bad } else { Strength::Poor }
        } else {
            Strength::Bad
        }
    }
}

/// Packet arrival bookkeeping for one audio stream: the share of each
/// interval's expected packets that went missing.
#[derive(Debug, Default, Clone, Copy)]
pub struct LossCounter {
    highest: Option<u16>,
    expected: u64,
    received: u64,
}

impl LossCounter {
    pub fn on_packet(&mut self, seq: u16) {
        match self.highest {
            None => {
                self.highest = Some(seq);
                self.expected += 1;
            }
            Some(h) => {
                let d = seq.wrapping_sub(h);
                // A newer packet (within half the sequence space).
                if d != 0 && d < 0x8000 {
                    self.expected += u64::from(d);
                    self.highest = Some(seq);
                }
            }
        }
        self.received += 1;
    }

    /// The missing share since the last call (None without traffic).
    pub fn take_ratio(&mut self) -> Option<f64> {
        let (e, r) = (self.expected, self.received);
        self.expected = 0;
        self.received = 0;
        (e > 0).then(|| (e.saturating_sub(r)) as f64 / e as f64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(missing: f64, t: u64) -> Sample {
        Sample { samples_received: 48_000 * (t + 20), missing_ratio: Some(missing), packets_sent: 0, ..Default::default() }
    }

    #[test]
    fn receiving_levels_with_teams_hysteresis() {
        let mut r = Rater::default();
        for t in 0..5 {
            assert_eq!(r.sample(s(0.05, t), t * 1000), Strength::Good);
        }
        // 0.18 sits in the Good band's hysteresis: still Good.
        for t in 5..10 {
            r.sample(s(0.18, t), t * 1000);
        }
        assert_eq!(r.sample(s(0.18, 10), 10_000), Strength::Good);
        for t in 11..16 {
            r.sample(s(0.22, t), t * 1000);
        }
        assert_eq!(r.sample(s(0.22, 16), 16_000), Strength::Poor);
        for t in 17..23 {
            r.sample(s(0.4, t), t * 1000);
        }
        assert_eq!(r.sample(s(0.4, 23), 23_000), Strength::Bad);
        // 0.26 in the Bad band's hysteresis stays Bad once Bad.
        for t in 24..30 {
            r.sample(s(0.26, t), t * 1000);
        }
        assert_eq!(r.sample(s(0.26, 30), 30_000), Strength::Bad);
        // Nothing until 10 s of audio has arrived.
        let mut fresh = Rater::default();
        for t in 0..6 {
            let early = Sample { samples_received: 48_000 * t, missing_ratio: Some(0.5), ..Default::default() };
            assert_eq!(fresh.sample(early, t * 1000), Strength::Good);
        }
    }

    #[test]
    fn sending_bad_sticks_for_five_seconds() {
        let mut r = Rater::default();
        let out = |loss: f64| Sample { packets_sent: 500, remote_loss: Some(loss), ..Default::default() };
        assert_eq!(r.sample(out(0.05), 0), Strength::Good);
        assert_eq!(r.sample(out(0.4), 1000), Strength::Bad);
        // Back under the low threshold: Bad holds for 5 s.
        assert_eq!(r.sample(out(0.05), 2000), Strength::Bad);
        assert_eq!(r.sample(out(0.05), 6000), Strength::Bad);
        assert_eq!(r.sample(out(0.05), 7500), Strength::Good);
    }

    #[test]
    fn counts_missing_packets() {
        let mut c = LossCounter::default();
        for seq in [10u16, 11, 13, 14, 17] {
            c.on_packet(seq);
        }
        // 10..=17 expected (8), 5 arrived.
        assert_eq!(c.take_ratio(), Some(3.0 / 8.0));
        assert_eq!(c.take_ratio(), None);
        let mut w = LossCounter::default();
        w.on_packet(65534);
        w.on_packet(65535);
        w.on_packet(1);
        // 65534, 65535, 0, 1 expected; 0 missing.
        assert_eq!(w.take_ratio(), Some(0.25), "wraps");
    }
}
