//! Receiving H.264 video from WebRTC peers (Teams web and the conference
//! server): RTP payloads (RFC 6184: single NAL units, STAP-A, FU-A) are
//! reassembled into access units on a dedicated thread, decoded with
//! openh264 and published as RGBA frames ([`super::frames`]).
//!
//! A lost packet spoils the rest of the frame and, until the next
//! keyframe, everything after it, so the receiver asks for a keyframe
//! (the session turns that into an RTCP PLI) and drops frames until an
//! IDR picture arrives.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;

/// One RTP packet's video payload.
pub struct VideoPacket {
    pub payload: Vec<u8>,
    pub marker: bool,
    pub seq: u16,
    pub timestamp: u32,
}

/// Largest access unit we assemble (a 1080p keyframe is well under this).
const MAX_ACCESS_UNIT: usize = 4 * 1024 * 1024;
/// Packets queued for the decoder before new ones are dropped.
const QUEUE: usize = 512;

/// Reassembles RTP payloads into Annex B access units.
#[derive(Default)]
pub struct Depacketizer {
    au: Vec<u8>,
    fu: Option<Vec<u8>>,
    last_seq: Option<u16>,
    timestamp: Option<u32>,
    /// A packet went missing: wait for the next IDR.
    broken: bool,
    has_idr: bool,
}

/// What a packet completed.
#[derive(Debug, PartialEq, Eq)]
pub enum Output {
    /// More packets needed.
    Pending,
    /// A whole access unit (Annex B), and whether it holds an IDR slice.
    AccessUnit(Vec<u8>, bool),
    /// Packets were lost; ask the sender for a keyframe.
    Lost,
}

const START: [u8; 4] = [0, 0, 0, 1];

impl Depacketizer {
    fn push_nal(&mut self, nal: &[u8]) {
        if nal.is_empty() || self.au.len() + nal.len() + 4 > MAX_ACCESS_UNIT {
            return;
        }
        if nal[0] & 0x1f == 5 {
            self.has_idr = true;
        }
        self.au.extend_from_slice(&START);
        self.au.extend_from_slice(nal);
    }

    pub fn push(&mut self, p: &VideoPacket) -> Output {
        let mut lost = false;
        if let Some(last) = self.last_seq {
            if p.seq != last.wrapping_add(1) {
                lost = true;
            }
        }
        self.last_seq = Some(p.seq);
        // A new timestamp starts a new picture; whatever was pending is
        // incomplete.
        if self.timestamp.is_some_and(|t| t != p.timestamp) && !self.au.is_empty() {
            lost = true;
        }
        if lost {
            self.au.clear();
            self.fu = None;
            self.has_idr = false;
            self.broken = true;
        }
        self.timestamp = Some(p.timestamp);

        let data = &p.payload;
        if let Some(&first) = data.first() {
            match first & 0x1f {
                1..=23 => self.push_nal(data),
                24 => {
                    // STAP-A: 16-bit size, NAL, repeated.
                    let mut i = 1;
                    while i + 2 <= data.len() {
                        let n = u16::from_be_bytes([data[i], data[i + 1]]) as usize;
                        i += 2;
                        if n == 0 || i + n > data.len() {
                            break;
                        }
                        let nal = data[i..i + n].to_vec();
                        self.push_nal(&nal);
                        i += n;
                    }
                }
                28 if data.len() >= 2 => {
                    // FU-A
                    let (ind, hdr) = (data[0], data[1]);
                    if hdr & 0x80 != 0 {
                        let mut nal = vec![(ind & 0xe0) | (hdr & 0x1f)];
                        nal.extend_from_slice(&data[2..]);
                        self.fu = Some(nal);
                    } else if let Some(nal) = self.fu.as_mut() {
                        if nal.len() + data.len() <= MAX_ACCESS_UNIT {
                            nal.extend_from_slice(&data[2..]);
                        }
                    }
                    if hdr & 0x40 != 0 {
                        if let Some(nal) = self.fu.take() {
                            self.push_nal(&nal);
                        }
                    }
                }
                _ => {}
            }
        }

        if !p.marker {
            return if lost { Output::Lost } else { Output::Pending };
        }
        let au = std::mem::take(&mut self.au);
        let idr = std::mem::take(&mut self.has_idr);
        self.fu = None;
        self.timestamp = None;
        if self.broken && !idr {
            return Output::Lost;
        }
        self.broken = false;
        if au.is_empty() {
            Output::Pending
        } else {
            Output::AccessUnit(au, idr)
        }
    }
}

/// Decodes a peer's video on its own thread and publishes it as `key`.
pub struct VideoReceiver {
    tx: mpsc::SyncSender<VideoPacket>,
    /// Set when the decoder needs a keyframe (send a PLI).
    pub keyframe_wanted: Arc<AtomicBool>,
    key: String,
}

impl VideoReceiver {
    pub fn start(key: &str) -> Self {
        let (tx, rx) = mpsc::sync_channel::<VideoPacket>(QUEUE);
        // Ask for a keyframe straight away: we may have joined mid-stream.
        let keyframe_wanted = Arc::new(AtomicBool::new(true));
        let want = keyframe_wanted.clone();
        let k = key.to_string();
        std::thread::Builder::new()
            .name("ost-video-rx".into())
            .spawn(move || decode_loop(rx, want, &k))
            .ok();
        Self {
            tx,
            keyframe_wanted,
            key: key.to_string(),
        }
    }

    /// Queue a packet (dropped if the decoder is behind).
    pub fn push(&self, p: VideoPacket) {
        if self.tx.try_send(p).is_err() {
            self.keyframe_wanted.store(true, Ordering::Relaxed);
        }
    }
}

impl Drop for VideoReceiver {
    fn drop(&mut self) {
        super::frames::clear(&self.key);
    }
}

fn decode_loop(rx: mpsc::Receiver<VideoPacket>, want: Arc<AtomicBool>, key: &str) {
    use openh264::decoder::{Decoder, DecoderConfig};
    use openh264::formats::YUVSource;
    use openh264::OpenH264API;
    let mut decoder =
        match Decoder::with_api_config(OpenH264API::from_source(), DecoderConfig::new()) {
            Ok(d) => d,
            Err(e) => {
                tracing::warn!("H.264 decoder unavailable: {e:?}");
                return;
            }
        };
    let mut depack = Depacketizer::default();
    let mut decoded = 0u64;
    while let Ok(p) = rx.recv() {
        match depack.push(&p) {
            Output::Pending => {}
            Output::Lost => want.store(true, Ordering::Relaxed),
            Output::AccessUnit(au, idr) => {
                if idr {
                    want.store(false, Ordering::Relaxed);
                }
                match decoder.decode(&au) {
                    Ok(Some(yuv)) => {
                        let (w, h) = yuv.dimensions();
                        let mut rgba = vec![0u8; w * h * 4];
                        yuv.write_rgba8(&mut rgba);
                        super::frames::publish(key, w as u32, h as u32, rgba);
                        decoded += 1;
                        if decoded == 1 || decoded.is_multiple_of(300) {
                            tracing::info!(decoded, w, h, "video frames decoded");
                        }
                    }
                    Ok(None) => {}
                    Err(e) => {
                        tracing::debug!("H.264 decode error: {e:?}");
                        want.store(true, Ordering::Relaxed);
                    }
                }
            }
        }
    }
}

/// An RTCP Picture Loss Indication (RFC 4585) from `sender` about `media`.
pub fn pli(sender: u32, media: u32) -> Vec<u8> {
    let mut p = vec![0x81, 206, 0, 2];
    p.extend_from_slice(&sender.to_be_bytes());
    p.extend_from_slice(&media.to_be_bytes());
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pkt(payload: &[u8], marker: bool, seq: u16, ts: u32) -> VideoPacket {
        VideoPacket {
            payload: payload.to_vec(),
            marker,
            seq,
            timestamp: ts,
        }
    }

    #[test]
    fn stap_a_and_fu_a_make_an_access_unit() {
        let mut d = Depacketizer::default();
        // STAP-A with SPS (7) and PPS (8).
        let stap = [24, 0, 2, 0x67, 1, 0, 2, 0x68, 2];
        assert_eq!(d.push(&pkt(&stap, false, 1, 90)), Output::Pending);
        // An IDR slice in two FU-A fragments.
        assert_eq!(
            d.push(&pkt(&[0x7c, 0x85, 0xaa], false, 2, 90)),
            Output::Pending
        );
        let out = d.push(&pkt(&[0x7c, 0x45, 0xbb], true, 3, 90));
        let mut want = vec![
            0, 0, 0, 1, 0x67, 1, 0, 0, 0, 1, 0x68, 2, 0, 0, 0, 1, 0x65, 0xaa, 0xbb,
        ];
        assert_eq!(out, Output::AccessUnit(want.clone(), true));
        // The next frame: a single non-IDR slice.
        want = vec![0, 0, 0, 1, 0x41, 9];
        assert_eq!(
            d.push(&pkt(&[0x41, 9], true, 4, 180)),
            Output::AccessUnit(want, false)
        );
    }

    #[test]
    fn a_lost_packet_waits_for_the_next_idr() {
        let mut d = Depacketizer::default();
        assert!(matches!(
            d.push(&pkt(&[0x65, 1], true, 1, 90)),
            Output::AccessUnit(_, true)
        ));
        // seq 2 lost
        assert_eq!(d.push(&pkt(&[0x41, 1], true, 3, 180)), Output::Lost);
        assert_eq!(d.push(&pkt(&[0x41, 1], true, 4, 270)), Output::Lost);
        assert!(matches!(
            d.push(&pkt(&[0x65, 1], true, 5, 360)),
            Output::AccessUnit(_, true)
        ));
        assert!(matches!(
            d.push(&pkt(&[0x41, 1], true, 6, 450)),
            Output::AccessUnit(_, false)
        ));
    }

    #[test]
    fn malformed_stap_a_is_ignored() {
        let mut d = Depacketizer::default();
        assert_eq!(
            d.push(&pkt(&[24, 0xff, 0xff, 1], true, 1, 1)),
            Output::Pending
        );
        assert_eq!(pli(1, 2), vec![0x81, 206, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2]);
    }
}
