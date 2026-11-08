//! Who is speaking in a meeting, as Teams shows it with the voice-level
//! outline: a participant speaks while their audio source is one of the
//! contributing sources (RTP CSRCs) of the mix the media processor sends.
//! Teams' calling stack sets a participant's voice level to 1 when its
//! audio source is among them, else 0.
//!
//! Measured against Teams web (2026-11-08): the outline goes off about
//! 60 ms after a speaker's CSRCs stop arriving, and gaps of up to about
//! 120 ms in a talker's CSRCs don't turn it off. A source counts as
//! speaking for [`HOLD`] after its last packet.

use std::collections::HashMap;
use std::time::{Duration, Instant};

/// How long a source still counts as speaking after its last packet.
pub const HOLD: Duration = Duration::from_millis(150);

/// The audio sources heard lately, and the set last reported.
#[derive(Default)]
pub struct Tracker {
    seen: HashMap<u32, Instant>,
    reported: Vec<u32>,
}

impl Tracker {
    /// Note a mixed audio packet's contributing sources.
    pub fn record(&mut self, csrcs: &[u32], at: Instant) {
        for &c in csrcs {
            self.seen.insert(c, at);
        }
    }

    /// The sources speaking at `now`, when that changed since the last
    /// call (sorted).
    pub fn changed(&mut self, now: Instant) -> Option<Vec<u32>> {
        self.seen
            .retain(|_, t| now.saturating_duration_since(*t) < HOLD);
        let mut active: Vec<u32> = self.seen.keys().copied().collect();
        active.sort_unstable();
        (active != self.reported).then(|| {
            self.reported = active.clone();
            active
        })
    }
}

/// The CSRCs of an RTP packet.
pub fn csrcs(rtp: &[u8]) -> Vec<u32> {
    let cc = usize::from(rtp.first().copied().unwrap_or(0) & 0x0f);
    rtp.get(12..12 + 4 * cc)
        .unwrap_or_default()
        .chunks_exact(4)
        .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_csrcs() {
        let mut p = vec![0x82, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 9];
        p.extend_from_slice(&17132u32.to_be_bytes());
        p.extend_from_slice(&20966u32.to_be_bytes());
        p.extend_from_slice(&[0xaa; 20]);
        assert_eq!(csrcs(&p), vec![17132, 20966]);
        assert!(csrcs(&[0x80, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 9, 1]).is_empty());
        assert!(csrcs(&[0x8f]).is_empty(), "too short for its count");
    }

    #[test]
    fn speaking_holds_through_short_gaps_and_ends_after_the_hold() {
        let t0 = Instant::now();
        let ms = |n| t0 + Duration::from_millis(n);
        let mut t = Tracker::default();
        assert_eq!(t.changed(t0), None, "nobody, as before");
        t.record(&[17132], t0);
        assert_eq!(t.changed(ms(10)), Some(vec![17132]));
        // A 60 ms gap in the CSRCs: still speaking, nothing reported.
        t.record(&[], ms(20));
        assert_eq!(t.changed(ms(80)), None);
        t.record(&[17132], ms(90));
        t.record(&[17132, 20966], ms(100));
        assert_eq!(t.changed(ms(110)), Some(vec![17132, 20966]));
        // Both stop: off once the hold passes.
        assert_eq!(t.changed(ms(200)), None);
        assert_eq!(t.changed(ms(260)), Some(vec![]));
        assert_eq!(t.changed(ms(300)), None);
    }
}
