//! Call audio codecs. Teams offers Opus first (opus/48000/2, minptime=10,
//! useinbandfec=1) and keeps G.711 for phones; OST sends Opus whenever the
//! other side takes it and PCMU otherwise. The call's audio runs at 48 kHz
//! in 20 ms frames; PCMU is resampled to and from its 8 kHz.

/// The rate the call's audio runs at (capture, playback, processing).
pub const CALL_RATE: u32 = 48_000;
/// Samples in one 20 ms frame at [`CALL_RATE`].
pub const FRAME: usize = (CALL_RATE as usize) / 50;

/// The codec a call sends with, and its payload type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Codec {
    Pcmu,
    Opus(u8),
}

impl Codec {
    pub fn payload_type(self) -> u8 {
        match self {
            Codec::Pcmu => 0,
            Codec::Opus(pt) => pt,
        }
    }

    /// RTP clock ticks in a 20 ms packet.
    pub fn timestamp_step(self) -> u32 {
        match self {
            Codec::Pcmu => 160,
            Codec::Opus(_) => 960,
        }
    }

    /// The telephone-event clock that goes with it.
    pub fn dtmf_clock(self) -> u32 {
        match self {
            Codec::Pcmu => 8000,
            Codec::Opus(_) => 48000,
        }
    }
}

/// The Opus payload type in an SDP audio section (`a=rtpmap:<pt>
/// opus/48000/2`, any case), if offered.
pub fn opus_payload_type(section: &str) -> Option<u8> {
    section.lines().find_map(|l| {
        let rest = l.trim_end().strip_prefix("a=rtpmap:")?;
        let (pt, codec) = rest.split_once(' ')?;
        codec
            .to_ascii_lowercase()
            .starts_with("opus/48000")
            .then(|| pt.parse().ok())
            .flatten()
    })
}

/// The payload type of `telephone-event/<clock>` in an SDP audio section.
pub fn dtmf_payload_type(section: &str, clock: u32) -> Option<u8> {
    let want = format!("telephone-event/{clock}");
    section.lines().find_map(|l| {
        let rest = l.trim_end().strip_prefix("a=rtpmap:")?;
        let (pt, codec) = rest.split_once(' ')?;
        codec.eq_ignore_ascii_case(&want).then(|| pt.parse().ok()).flatten()
    })
}

/// What to send with: Opus when the section carries it, else PCMU.
pub fn choose(section: &str) -> Codec {
    if cfg!(feature = "audio")
        && let Some(pt) = opus_payload_type(section)
    {
        return Codec::Opus(pt);
    }
    Codec::Pcmu
}

/// A half-band-ish low-pass FIR for 48 kHz ↔ 8 kHz (cut-off 3.6 kHz,
/// Hann-windowed sinc, 48 taps): keeps PCMU from aliasing.
fn lowpass_taps() -> &'static [f32] {
    static TAPS: std::sync::OnceLock<Vec<f32>> = std::sync::OnceLock::new();
    TAPS.get_or_init(|| {
        let n = 48;
        let fc = 3600.0 / CALL_RATE as f32;
        let mut t: Vec<f32> = (0..n)
            .map(|i| {
                let m = i as f32 - (n as f32 - 1.0) / 2.0;
                let sinc = if m == 0.0 {
                    2.0 * fc
                } else {
                    (2.0 * std::f32::consts::PI * fc * m).sin() / (std::f32::consts::PI * m)
                };
                let w = 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (n as f32 - 1.0)).cos();
                sinc * w
            })
            .collect();
        let sum: f32 = t.iter().sum();
        t.iter_mut().for_each(|x| *x /= sum);
        t
    })
}

/// 48 kHz → 8 kHz with filtering, keeping history between frames.
#[derive(Default)]
pub struct Down6 {
    hist: Vec<f32>,
}

impl Down6 {
    pub fn process(&mut self, input: &[i16]) -> Vec<i16> {
        let taps = lowpass_taps();
        self.hist.extend(input.iter().map(|&s| s as f32));
        let mut out = Vec::with_capacity(input.len() / 6);
        let mut i = 0;
        while i + taps.len() <= self.hist.len() {
            let acc: f32 = taps.iter().zip(&self.hist[i..]).map(|(t, x)| t * x).sum();
            out.push(acc.round().clamp(-32768.0, 32767.0) as i16);
            i += 6;
        }
        self.hist.drain(..i);
        out
    }
}

/// 8 kHz → 48 kHz: zero-stuffed and filtered.
#[derive(Default)]
pub struct Up6 {
    hist: Vec<f32>,
}

impl Up6 {
    pub fn process(&mut self, input: &[i16]) -> Vec<i16> {
        let taps = lowpass_taps();
        for &s in input {
            self.hist.push(s as f32 * 6.0);
            self.hist.extend(std::iter::repeat_n(0.0, 5));
        }
        let mut out = Vec::with_capacity(input.len() * 6);
        let mut i = 0;
        while i + taps.len() <= self.hist.len() {
            let acc: f32 = taps.iter().zip(&self.hist[i..]).map(|(t, x)| t * x).sum();
            out.push(acc.round().clamp(-32768.0, 32767.0) as i16);
            i += 1;
        }
        self.hist.drain(..i);
        out
    }
}

/// Encodes the call's 20 ms frames.
pub struct Encoder {
    codec: Codec,
    down: Down6,
    #[cfg(feature = "audio")]
    opus: Option<opus::Encoder>,
}

impl Encoder {
    pub fn new(codec: Codec) -> Self {
        #[cfg(feature = "audio")]
        let opus = match codec {
            Codec::Opus(_) => match opus::Encoder::new(CALL_RATE, opus::Channels::Mono, opus::Application::Voip) {
                Ok(mut e) => {
                    // Teams' own Opus for calls: about 36 kbit/s with
                    // in-band FEC.
                    let _ = e.set_bitrate(opus::Bitrate::Bits(36_000));
                    let _ = e.set_inband_fec(true);
                    let _ = e.set_packet_loss_perc(5);
                    Some(e)
                }
                Err(e) => {
                    tracing::warn!("Opus encoder: {e}");
                    None
                }
            },
            Codec::Pcmu => None,
        };
        Encoder {
            codec,
            down: Down6::default(),
            #[cfg(feature = "audio")]
            opus,
        }
    }

    pub fn codec(&self) -> Codec {
        self.codec
    }

    /// One packet's payload for a 20 ms frame at [`CALL_RATE`] (silence
    /// when `frame` is None: muted, held or no microphone).
    pub fn encode(&mut self, frame: Option<&[i16]>) -> Vec<u8> {
        let silence = [0i16; FRAME];
        let pcm = frame.filter(|f| f.len() == FRAME).unwrap_or(&silence);
        match self.codec {
            #[cfg(feature = "audio")]
            Codec::Opus(_) => {
                if let Some(e) = self.opus.as_mut() {
                    let mut out = vec![0u8; 400];
                    if let Ok(n) = e.encode(pcm, &mut out) {
                        out.truncate(n);
                        return out;
                    }
                }
                Vec::new()
            }
            _ => {
                let narrow = self.down.process(pcm);
                let mut enc: Vec<u8> = narrow.iter().map(|&s| super::rtp::linear_to_ulaw(s)).collect();
                enc.resize(super::rtp::SAMPLES_PER_PACKET, 0xFF);
                enc
            }
        }
    }
}

/// Decodes what the other side sends, by payload type, to [`CALL_RATE`].
pub struct Decoder {
    opus_pt: Option<u8>,
    up: Up6,
    #[cfg(feature = "audio")]
    opus: Option<opus::Decoder>,
}

impl Decoder {
    /// `opus_pt`: the payload type the session uses for Opus, if any.
    pub fn new(opus_pt: Option<u8>) -> Self {
        Decoder {
            opus_pt,
            up: Up6::default(),
            #[cfg(feature = "audio")]
            opus: opus_pt.and_then(|_| opus::Decoder::new(CALL_RATE, opus::Channels::Mono).ok()),
        }
    }

    /// Whether `pt` is audio this decoder plays.
    pub fn handles(&self, pt: u8) -> bool {
        pt == 0 || Some(pt) == self.opus_pt
    }

    /// The samples in one packet (empty for what it doesn't decode).
    pub fn decode(&mut self, pt: u8, payload: &[u8]) -> Vec<i16> {
        if pt == 0 {
            let narrow: Vec<i16> = payload.iter().map(|&b| super::rtp::ulaw_to_linear(b)).collect();
            return self.up.process(&narrow);
        }
        #[cfg(feature = "audio")]
        if Some(pt) == self.opus_pt
            && let Some(d) = self.opus.as_mut()
        {
            // Up to 120 ms in one packet.
            let mut out = vec![0i16; FRAME * 6];
            match d.decode(payload, &mut out, false) {
                Ok(n) => {
                    out.truncate(n);
                    return out;
                }
                Err(e) => tracing::debug!(len = payload.len(), "Opus decode: {e}"),
            }
        }
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_opus_from_teams_offer() {
        let section = "m=audio 48340 RTP/SAVP 105 111 97 9 0 8 13 110 126\r\na=rtpmap:105 CN/48000\r\na=rtpmap:111 opus/48000/2\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:110 telephone-event/48000\r\na=rtpmap:126 telephone-event/8000\r\n";
        assert_eq!(opus_payload_type(section), Some(111));
        assert_eq!(dtmf_payload_type(section, 48000), Some(110));
        assert_eq!(dtmf_payload_type(section, 8000), Some(126));
        // The media processor writes it in capitals.
        assert_eq!(opus_payload_type("a=rtpmap:111 OPUS/48000/2\r\n"), Some(111));
        assert_eq!(opus_payload_type("a=rtpmap:0 PCMU/8000\r\n"), None);
        if cfg!(feature = "audio") {
            assert_eq!(choose(section), Codec::Opus(111));
        }
        assert_eq!(choose("a=rtpmap:0 PCMU/8000\r\n"), Codec::Pcmu);
    }

    #[test]
    fn pcmu_round_trip_keeps_a_tone() {
        // A 1 kHz tone at 48 kHz survives 48 → 8 → 48 kHz.
        let tone: Vec<i16> = (0..FRAME * 10)
            .map(|i| ((i as f32 * 2.0 * std::f32::consts::PI * 1000.0 / 48000.0).sin() * 8000.0) as i16)
            .collect();
        let mut enc = Encoder::new(Codec::Pcmu);
        let mut dec = Decoder::new(None);
        let mut out = Vec::new();
        for f in tone.chunks(FRAME) {
            let payload = enc.encode(Some(f));
            assert_eq!(payload.len(), 160);
            out.extend(dec.decode(0, &payload));
        }
        let tail = &out[out.len() / 2..];
        let rms = (tail.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / tail.len() as f64).sqrt();
        assert!(rms > 4000.0 && rms < 7000.0, "rms {rms}");
    }

    #[cfg(feature = "audio")]
    #[test]
    fn opus_round_trip() {
        let mut enc = Encoder::new(Codec::Opus(111));
        let mut dec = Decoder::new(Some(111));
        let tone: Vec<i16> = (0..FRAME * 20)
            .map(|i| ((i as f32 * 2.0 * std::f32::consts::PI * 440.0 / 48000.0).sin() * 8000.0) as i16)
            .collect();
        let mut out = Vec::new();
        for f in tone.chunks(FRAME) {
            let payload = enc.encode(Some(f));
            assert!(!payload.is_empty() && payload.len() < 400);
            out.extend(dec.decode(111, &payload));
        }
        assert_eq!(out.len(), tone.len());
        let tail = &out[out.len() / 2..];
        let rms = (tail.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / tail.len() as f64).sqrt();
        assert!(rms > 3000.0, "rms {rms}");
        assert!(dec.handles(111) && dec.handles(0) && !dec.handles(9));
    }
}
