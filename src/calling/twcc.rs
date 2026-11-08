//! Transport-wide congestion control feedback (draft-holmer-rmcat-
//! transport-wide-cc-extensions-01), as Teams' clients send it: every
//! packet the media processor sends carries a transport-wide sequence
//! number (RTP header extension 3), and we report when each arrived. From
//! that the processor estimates our downlink and picks the video layers
//! it sends us.

use std::collections::BTreeMap;
use std::time::Instant;

/// The header extension's id in our offers, and its URI as Teams writes
/// it (with backslashes).
pub const EXTENSION_ID: u8 = 3;
pub const EXTENSION_URI: &str =
    r"http:\\www.ietf.org\id\draft-holmer-rmcat-transport-wide-cc-extensions-01";

/// Receive deltas are in 250 µs units; reference time in 64 ms units.
const DELTA_US: i64 = 250;
const REFERENCE_US: i64 = 64_000;

/// The transport-wide sequence number in an RTP packet (one-byte or
/// two-byte header extensions), if it has one.
pub fn sequence_number(rtp: &[u8]) -> Option<u16> {
    let b0 = *rtp.first()?;
    if b0 & 0x10 == 0 {
        return None;
    }
    let cc = usize::from(b0 & 0x0f);
    let start = 12 + 4 * cc;
    let profile = u16::from_be_bytes([*rtp.get(start)?, *rtp.get(start + 1)?]);
    let words = usize::from(u16::from_be_bytes([
        *rtp.get(start + 2)?,
        *rtp.get(start + 3)?,
    ]));
    let ext = rtp.get(start + 4..start + 4 + words * 4)?;
    let mut i = 0;
    if profile == 0xBEDE {
        while i < ext.len() {
            let id = ext[i] >> 4;
            let len = usize::from(ext[i] & 0x0f) + 1;
            if id == 0 {
                i += 1;
                continue;
            }
            if id == 15 {
                break;
            }
            if id == EXTENSION_ID && len == 2 {
                return Some(u16::from_be_bytes([*ext.get(i + 1)?, *ext.get(i + 2)?]));
            }
            i += 1 + len;
        }
    } else if profile & 0xfff0 == 0x1000 {
        while i + 1 < ext.len() {
            let id = ext[i];
            if id == 0 {
                i += 1;
                continue;
            }
            let len = usize::from(ext[i + 1]);
            if id == EXTENSION_ID && len == 2 {
                return Some(u16::from_be_bytes([*ext.get(i + 2)?, *ext.get(i + 3)?]));
            }
            i += 2 + len;
        }
    }
    None
}

/// Arrival times by (unwrapped) transport sequence number, and what's
/// been reported.
pub struct Recorder {
    epoch: Instant,
    /// Unwrapped sequence number -> arrival, µs since `epoch`.
    arrivals: BTreeMap<i64, i64>,
    last_seq: Option<i64>,
    /// The next sequence number a report starts at.
    next_report: Option<i64>,
    feedback_count: u8,
}

impl Default for Recorder {
    fn default() -> Self {
        Self::new()
    }
}

impl Recorder {
    pub fn new() -> Self {
        Self {
            epoch: Instant::now(),
            arrivals: BTreeMap::new(),
            last_seq: None,
            next_report: None,
            feedback_count: 0,
        }
    }

    /// Note a packet's arrival.
    pub fn record(&mut self, seq: u16, at: Instant) {
        let unwrapped = match self.last_seq {
            None => i64::from(seq),
            Some(last) => {
                let diff = i64::from(seq.wrapping_sub(last as u16) as i16);
                last + diff
            }
        };
        if self.last_seq.is_none_or(|l| unwrapped > l) {
            self.last_seq = Some(unwrapped);
        }
        if self.next_report.is_some_and(|n| unwrapped < n) {
            return; // already reported
        }
        let us = at.saturating_duration_since(self.epoch).as_micros() as i64;
        self.arrivals.insert(unwrapped, us);
    }

    /// The feedback packet for what arrived since the last one, or None
    /// when nothing did.
    pub fn feedback(&mut self, sender_ssrc: u32, media_ssrc: u32) -> Option<Vec<u8>> {
        let (&first, _) = self.arrivals.iter().next()?;
        let (&last, _) = self.arrivals.iter().next_back()?;
        let base = self.next_report.map_or(first, |n| n.min(first));
        // Packets reported missing before may be reported again; a report
        // covers at most 0xffff packets.
        let last = last.min(base + 0xfffe);
        let reference = self.arrivals[&first] / REFERENCE_US;

        let mut symbols: Vec<u8> = Vec::new();
        let mut deltas: Vec<u8> = Vec::new();
        let mut prev = reference * REFERENCE_US;
        for seq in base..=last {
            match self.arrivals.get(&seq) {
                None => symbols.push(0),
                Some(&t) => {
                    let delta = (t - prev).div_euclid(DELTA_US);
                    if (0..=255).contains(&delta) {
                        symbols.push(1);
                        deltas.push(delta as u8);
                    } else {
                        let d = delta.clamp(i64::from(i16::MIN), i64::from(i16::MAX)) as i16;
                        symbols.push(2);
                        deltas.extend_from_slice(&d.to_be_bytes());
                    }
                    prev = t;
                }
            }
        }

        let mut p = vec![0u8; 4];
        p.extend_from_slice(&sender_ssrc.to_be_bytes());
        p.extend_from_slice(&media_ssrc.to_be_bytes());
        p.extend_from_slice(&((base & 0xffff) as u16).to_be_bytes());
        p.extend_from_slice(&(symbols.len() as u16).to_be_bytes());
        let reference24 = (reference & 0x00ff_ffff) as u32;
        p.extend_from_slice(&((reference24 << 8) | u32::from(self.feedback_count)).to_be_bytes());
        // Run-length chunks: 0 | symbol (2 bits) | run length (13 bits).
        let mut i = 0;
        while i < symbols.len() {
            let s = symbols[i];
            let mut run = 1;
            while i + run < symbols.len() && symbols[i + run] == s && run < 0x1fff {
                run += 1;
            }
            p.extend_from_slice(&((u16::from(s) << 13) | run as u16).to_be_bytes());
            i += run;
        }
        p.extend_from_slice(&deltas);
        // Pad to 32 bits; the last padding byte counts the padding (P bit).
        let padding = (4 - p.len() % 4) % 4;
        if padding > 0 {
            p.extend(std::iter::repeat_n(0u8, padding - 1));
            p.push(padding as u8);
        }
        p[0] = 0x80 | if padding > 0 { 0x20 } else { 0 } | 15;
        p[1] = 205;
        let words = (p.len() / 4 - 1) as u16;
        p[2..4].copy_from_slice(&words.to_be_bytes());

        self.feedback_count = self.feedback_count.wrapping_add(1);
        self.next_report = Some(last + 1);
        self.arrivals.retain(|s, _| *s > last);
        Some(p)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    /// An RTP header with a one-byte extension carrying `seq` (and the
    /// abs-send-time element before it, as the processor sends).
    fn rtp_with(seq: u16) -> Vec<u8> {
        let mut p = vec![0x90, 107, 0, 1, 0, 0, 0, 1, 0, 0, 0x0d, 0x5c];
        p.extend_from_slice(&[0xBE, 0xDE, 0, 2]);
        p.extend_from_slice(&[0x22, 1, 2, 3]); // id 2, 3 bytes
        p.extend_from_slice(&[0x31]); // id 3, 2 bytes
        p.extend_from_slice(&seq.to_be_bytes());
        p.push(0); // padding
        p.extend_from_slice(&[0xaa; 20]);
        p
    }

    #[test]
    fn reads_the_transport_sequence_number() {
        assert_eq!(sequence_number(&rtp_with(4660)), Some(4660));
        let plain = [0x80u8, 107, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0xaa];
        assert_eq!(sequence_number(&plain), None);
    }

    /// Decode a feedback packet: (base, statuses, deltas in 250 µs).
    fn decode(p: &[u8]) -> (u16, Vec<u8>, Vec<i64>) {
        assert_eq!(p[0] & 0x1f, 15);
        assert_eq!(p[1], 205);
        assert_eq!(
            (usize::from(u16::from_be_bytes([p[2], p[3]])) + 1) * 4,
            p.len()
        );
        let base = u16::from_be_bytes([p[12], p[13]]);
        let count = usize::from(u16::from_be_bytes([p[14], p[15]]));
        let mut i = 20;
        let mut statuses = Vec::new();
        while statuses.len() < count {
            let c = u16::from_be_bytes([p[i], p[i + 1]]);
            i += 2;
            assert_eq!(c >> 15, 0, "run-length chunks only");
            let s = ((c >> 13) & 3) as u8;
            statuses.extend(std::iter::repeat_n(s, usize::from(c & 0x1fff)));
        }
        let mut deltas = Vec::new();
        for s in &statuses {
            match s {
                1 => {
                    deltas.push(i64::from(p[i]));
                    i += 1;
                }
                2 => {
                    deltas.push(i64::from(i16::from_be_bytes([p[i], p[i + 1]])));
                    i += 2;
                }
                _ => {}
            }
        }
        (base, statuses, deltas)
    }

    #[test]
    fn reports_arrivals_losses_and_large_gaps() {
        let mut r = Recorder::new();
        let t0 = r.epoch + Duration::from_millis(1000);
        r.record(10, t0);
        r.record(11, t0 + Duration::from_micros(500));
        // 12 is lost; 13 comes 100 ms later (a large delta).
        r.record(13, t0 + Duration::from_millis(100));
        let p = r.feedback(1, 2).unwrap();
        let (base, statuses, deltas) = decode(&p);
        assert_eq!(base, 10);
        assert_eq!(statuses, vec![1, 1, 0, 2]);
        // First delta from the 64 ms reference: 1000 ms = 15*64 + 40 ms.
        assert_eq!(deltas, vec![40_000 / 250, 2, 99_500 / 250]);
        // Reported once; the next report starts after 13.
        assert!(r.feedback(1, 2).is_none());
        r.record(14, t0 + Duration::from_millis(101));
        let (base, statuses, _) = decode(&r.feedback(1, 2).unwrap());
        assert_eq!((base, statuses), (14, vec![1]));
    }

    #[test]
    fn sequence_numbers_wrap() {
        let mut r = Recorder::new();
        let t = r.epoch;
        r.record(65535, t);
        r.record(0, t + Duration::from_millis(1));
        let (base, statuses, _) = decode(&r.feedback(1, 2).unwrap());
        assert_eq!((base, statuses), (65535, vec![1, 1]));
    }
}
