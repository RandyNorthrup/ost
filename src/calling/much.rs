//! Teams' per-speaker meeting audio, `x-much2` ("MUCHv2"): instead of one
//! mix, the media processor sends each active speaker's own audio in every
//! packet, so the client can place each voice where that person's tile is
//! (Teams' spatial audio: `SpatialAudioMixinImplementation`, codec
//! `MUCHv2`, PT 113, `a=rtpmap:113 x-much2/48000/2`).
//!
//! The payload, as received from Teams' media processor (2026-11-17, two
//! guests talking at once; every frame decoded with libopus):
//!
//! ```text
//! u8   stream count
//! per stream:
//!   u8   kind (0x44: an Opus frame)
//!   u32  the speaker's audio source id (big endian; their roster
//!        `sourceId`, also in the packet's CSRCs)
//!   u16  frame length (big endian)
//!   ...  the frame (20 ms of Opus, mono, 48 kHz)
//! ```
//!
//! [`MuchMixer`] decodes each speaker with their own Opus decoder and places
//! them with their own [`Spatializer`](super::spatial::Spatializer).

use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Teams' payload type and SDP name for MUCHv2.
pub const PAYLOAD_TYPE: u8 = 113;
pub const RTPMAP: &str = "x-much2/48000/2";

/// The stream kind carrying an Opus frame.
pub const KIND_OPUS: u8 = 0x44;

/// One speaker's part of a packet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Substream<'a> {
    pub kind: u8,
    pub source: u32,
    pub frame: &'a [u8],
}

/// Split an x-much2 payload into its speakers; None if it doesn't parse.
pub fn parse(payload: &[u8]) -> Option<Vec<Substream<'_>>> {
    let (&count, mut rest) = payload.split_first()?;
    let mut out = Vec::with_capacity(usize::from(count));
    for _ in 0..count {
        let (head, tail) = rest.split_at_checked(7)?;
        let len = usize::from(u16::from_be_bytes([head[5], head[6]]));
        let (frame, tail) = tail.split_at_checked(len)?;
        out.push(Substream {
            kind: head[0],
            source: u32::from_be_bytes([head[1], head[2], head[3], head[4]]),
            frame,
        });
        rest = tail;
    }
    rest.is_empty().then_some(out)
}

/// The x-much2 payload type in an SDP audio section, when present.
pub fn payload_type(section: &str) -> Option<u8> {
    section.lines().find_map(|l| {
        let rest = l.trim_end().strip_prefix("a=rtpmap:")?;
        let (pt, codec) = rest.split_once(' ')?;
        codec.to_ascii_lowercase().starts_with("x-much2/").then(|| pt.parse().ok()).flatten()
    })
}

/// How long a speaker's decoder is kept after their last frame.
const IDLE: Duration = Duration::from_secs(2);

struct Speaker {
    #[cfg(feature = "audio")]
    decoder: opus::Decoder,
    place: super::spatial::Spatializer,
    seen: Instant,
}

/// Decodes and places every speaker in x-much2 packets.
pub struct MuchMixer {
    rate: u32,
    speakers: HashMap<u32, Speaker>,
    unknown_kinds: Vec<u8>,
}

impl MuchMixer {
    pub fn new(rate: u32) -> Self {
        MuchMixer { rate, speakers: HashMap::new(), unknown_kinds: Vec::new() }
    }

    /// One packet's 20 ms, each speaker at their own place (`place`: a
    /// source's azimuth, None for centred), mixed in stereo. Empty if the
    /// packet carries no audio OST can decode.
    pub fn decode(&mut self, payload: &[u8], place: &dyn Fn(u32) -> Option<f32>) -> Vec<[i16; 2]> {
        let Some(streams) = parse(payload) else {
            tracing::debug!(len = payload.len(), "x-much2 packet didn't parse");
            return Vec::new();
        };
        let now = Instant::now();
        let mut mix: Vec<[i32; 2]> = Vec::new();
        for s in streams {
            if s.kind != KIND_OPUS {
                if !self.unknown_kinds.contains(&s.kind) {
                    self.unknown_kinds.push(s.kind);
                    tracing::info!(kind = s.kind, "x-much2 stream kind not decoded");
                }
                continue;
            }
            let pcm = self.decode_one(s.source, s.frame, now);
            if pcm.is_empty() {
                continue;
            }
            let Some(sp) = self.speakers.get_mut(&s.source) else { continue };
            // Interpreter's balance: the interpreter against everyone else.
            let gain = super::ai_interpreter::gain_for(s.source);
            let pcm: Vec<i16> = if (gain - 1.0).abs() < f32::EPSILON {
                pcm
            } else {
                pcm.iter().map(|&x| (f32::from(x) * gain) as i16).collect()
            };
            let placed = sp.place.process(&pcm, place(s.source));
            if mix.len() < placed.len() {
                mix.resize(placed.len(), [0, 0]);
            }
            for (m, p) in mix.iter_mut().zip(&placed) {
                m[0] += i32::from(p[0]);
                m[1] += i32::from(p[1]);
            }
        }
        self.speakers.retain(|_, sp| now.duration_since(sp.seen) < IDLE);
        mix.iter()
            .map(|m| [m[0].clamp(-32768, 32767) as i16, m[1].clamp(-32768, 32767) as i16])
            .collect()
    }

    /// The speakers whose decoders are live (their sources).
    pub fn speakers(&self) -> Vec<u32> {
        let mut v: Vec<u32> = self.speakers.keys().copied().collect();
        v.sort_unstable();
        v
    }

    #[cfg(feature = "audio")]
    fn decode_one(&mut self, source: u32, frame: &[u8], now: Instant) -> Vec<i16> {
        let rate = self.rate;
        if !self.speakers.contains_key(&source) {
            let Ok(decoder) = opus::Decoder::new(rate, opus::Channels::Mono) else { return Vec::new() };
            self.speakers.insert(source, Speaker { decoder, place: super::spatial::Spatializer::new(rate), seen: now });
            tracing::info!(source, gain = super::ai_interpreter::gain_for(source), "x-much2: a speaker starts");
        }
        let Some(sp) = self.speakers.get_mut(&source) else { return Vec::new() };
        sp.seen = now;
        let mut out = vec![0i16; rate as usize / 1000 * 120];
        match sp.decoder.decode(frame, &mut out, false) {
            Ok(n) => {
                out.truncate(n);
                out
            }
            Err(e) => {
                tracing::debug!(source, len = frame.len(), "x-much2 Opus: {e}");
                Vec::new()
            }
        }
    }

    #[cfg(not(feature = "audio"))]
    fn decode_one(&mut self, _source: u32, _frame: &[u8], _now: Instant) -> Vec<i16> {
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A packet as Teams' media processor sent it with two guests talking
    /// at once (2026-11-17): two speakers, sources 627 and 840.
    const TWO_SPEAKERS: &str = "0244000002730016480beb4ca51b3866c2cf7ffac84659f261d913a470054400000348001a480beae73c7f5b9d9a16c3a7e556f5405c8b42fe2e3b1b143605";

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn a_packet_carries_each_speakers_frame() {
        let p = hex(TWO_SPEAKERS);
        let s = parse(&p).expect("parses");
        assert_eq!(s.len(), 2);
        assert_eq!((s[0].kind, s[0].source, s[0].frame.len()), (KIND_OPUS, 627, 22));
        assert_eq!((s[1].kind, s[1].source, s[1].frame.len()), (KIND_OPUS, 840, 26));
        // Opus SILK-only wideband 20 ms frames (TOC 0x48).
        assert!(s.iter().all(|x| x.frame[0] == 0x48));
        // Truncated or trailing bytes don't parse.
        assert!(parse(&p[..p.len() - 1]).is_none());
        let mut longer = p.clone();
        longer.push(0);
        assert!(parse(&longer).is_none());
        assert_eq!(parse(&[0]).map(|v| v.len()), Some(0));
    }

    #[test]
    fn the_sdp_names_it() {
        let section = "m=audio 3478 RTP/SAVP 96 113 109 111\r\na=rtpmap:96 x-much3/48000/2\r\na=rtpmap:113 x-much2/48000/2\r\na=rtpmap:111 OPUS/48000/2\r\n";
        assert_eq!(payload_type(section), Some(113));
        assert_eq!(payload_type("a=rtpmap:111 opus/48000/2\r\n"), None);
    }

    /// Each speaker is decoded on their own and placed on their own side.
    #[cfg(feature = "audio")]
    #[test]
    fn two_speakers_are_placed_apart() {
        let mut enc = opus::Encoder::new(48_000, opus::Channels::Mono, opus::Application::Voip).unwrap();
        let tone = |f: f32, n: usize| -> Vec<i16> {
            (0..960).map(|i| (((n * 960 + i) as f32 * 2.0 * std::f32::consts::PI * f / 48000.0).sin() * 8000.0) as i16).collect()
        };
        let mut m = MuchMixer::new(48_000);
        let place = |s: u32| Some(if s == 1 { -1.0 } else { 1.0 });
        let mut left_only = Vec::new();
        let mut right_only = Vec::new();
        for n in 0..30 {
            // Speaker 1 alone, then speaker 2 alone.
            let (src, f) = if n < 15 { (1u32, 440.0) } else { (2u32, 660.0) };
            let mut frame = vec![0u8; 400];
            let len = enc.encode(&tone(f, n), &mut frame).unwrap();
            let mut p = vec![1u8, KIND_OPUS];
            p.extend(src.to_be_bytes());
            p.extend((len as u16).to_be_bytes());
            p.extend(&frame[..len]);
            let out = m.decode(&p, &place);
            assert_eq!(out.len(), 960);
            if (5..15).contains(&n) {
                left_only.extend(out);
            } else if n >= 20 {
                right_only.extend(out);
            }
        }
        let e = |v: &[[i16; 2]], c: usize| v.iter().map(|x| f64::from(x[c]).powi(2)).sum::<f64>();
        assert!(e(&left_only, 0) > 4.0 * e(&left_only, 1));
        assert!(e(&right_only, 1) > 4.0 * e(&right_only, 0));
        assert_eq!(m.speakers(), vec![1, 2]);
    }
}
