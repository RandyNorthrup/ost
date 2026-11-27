//! Teams' "Test mic and speaker" (the pre-join's audio test wizard, read in
//! Teams' calling code 2026-11-27): the speaker step loops Teams' test
//! sound (`evergreen-assets/audio/teams_test_audio_tone_loop.wav`, 48 kHz
//! stereo PCM) on the chosen speaker; the microphone step monitors the
//! microphone ("Speak and pause. Do you hear the playback?"): what you say
//! is played back on the speaker once you pause.
//!
//! Both run on the preferred devices ([`super::audio::set_preferred_devices`]),
//! so picking another device in the wizard and restarting the step moves
//! them.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

use super::audio::{AudioCapture, AudioPlayback};

/// Teams' test sound on its public CDN.
pub const TONE_URL: &str =
    "https://statics.teams.cdn.office.net/evergreen-assets/audio/teams_test_audio_tone_loop.wav";

/// The rate both steps run at.
const RATE: u32 = 48_000;
/// 20 ms at [`RATE`].
const FRAME: usize = (RATE / 50) as usize;

/// A WAV file's 16-bit PCM as stereo frames (a mono file is doubled).
/// None when it isn't 16-bit PCM at 48 kHz with one or two channels.
pub fn parse_wav(bytes: &[u8]) -> Option<Vec<[i16; 2]>> {
    if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return None;
    }
    let mut at = 12;
    let mut channels = 0u16;
    let mut ok_format = false;
    while at + 8 <= bytes.len() {
        let id = &bytes[at..at + 4];
        let len = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().ok()?) as usize;
        let body = bytes.get(at + 8..(at + 8 + len).min(bytes.len()))?;
        if id == b"fmt " && body.len() >= 16 {
            let format = u16::from_le_bytes([body[0], body[1]]);
            channels = u16::from_le_bytes([body[2], body[3]]);
            let rate = u32::from_le_bytes([body[4], body[5], body[6], body[7]]);
            let bits = u16::from_le_bytes([body[14], body[15]]);
            ok_format =
                format == 1 && bits == 16 && rate == RATE && (channels == 1 || channels == 2);
        } else if id == b"data" {
            if !ok_format {
                return None;
            }
            let samples: Vec<i16> = body
                .chunks_exact(2)
                .map(|b| i16::from_le_bytes([b[0], b[1]]))
                .collect();
            return Some(if channels == 2 {
                samples.chunks_exact(2).map(|c| [c[0], c[1]]).collect()
            } else {
                samples.iter().map(|&s| [s, s]).collect()
            });
        }
        // Chunks are word aligned.
        at += 8 + len + (len & 1);
    }
    None
}

/// How far ahead of the speaker the steps queue audio: under the 200 ms
/// the playback keeps (it drops anything older).
const LEAD: Duration = Duration::from_millis(80);

/// Paces 20 ms frames to real time: [`Pacer::frame`] waits until another
/// frame may be queued without getting more than [`LEAD`] ahead.
struct Pacer {
    start: std::time::Instant,
    sent: u32,
}

impl Pacer {
    fn new() -> Self {
        Pacer {
            start: std::time::Instant::now(),
            sent: 0,
        }
    }

    /// When the audio queued so far will have played.
    fn queued_until(&self) -> std::time::Instant {
        self.start + Duration::from_millis(20) * self.sent
    }

    fn frame(&mut self) {
        let ahead = self
            .queued_until()
            .saturating_duration_since(std::time::Instant::now());
        if ahead > LEAD {
            thread::sleep(ahead - LEAD);
        }
        self.sent += 1;
    }
}

/// A running step; dropping it stops it.
pub struct Running {
    stop: Arc<AtomicBool>,
}

impl Drop for Running {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
    }
}

/// Loop `sound` on the preferred speaker (Teams' looping test sound).
/// None when no speaker can be opened.
pub fn play_loop(sound: Arc<Vec<[i16; 2]>>) -> Option<Running> {
    if sound.is_empty() {
        return None;
    }
    let (playback, tx) = AudioPlayback::start_stereo_at(RATE)?;
    let stop = Arc::new(AtomicBool::new(false));
    let done = stop.clone();
    thread::spawn(move || {
        let _playback = playback;
        let mut at = 0;
        let mut pace = Pacer::new();
        while !done.load(Ordering::SeqCst) {
            let frame: Vec<[i16; 2]> = (0..FRAME).map(|i| sound[(at + i) % sound.len()]).collect();
            at = (at + FRAME) % sound.len();
            pace.frame();
            if tx.send(frame).is_err() {
                break;
            }
        }
    });
    Some(Running { stop })
}

/// What the monitor does with each 20 ms of microphone audio.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Monitor {
    /// Waiting for you to speak.
    Listening,
    /// Recording what you say.
    Recording,
    /// Playing it back (the microphone is ignored meanwhile).
    Playing,
}

/// The speech gate: frames louder than this count as speech.
const SPEECH_RMS: f64 = 0.02;
/// A pause this long ends what you said.
const PAUSE_FRAMES: usize = 35;
/// Kept from before speech starts (its first syllable).
const PREROLL_FRAMES: usize = 10;
/// The longest stretch played back.
const MAX_FRAMES: usize = 500;

/// The monitor's decisions, apart from the audio devices (testable).
#[derive(Debug, Default)]
pub struct Gate {
    preroll: std::collections::VecDeque<Vec<i16>>,
    take: Vec<Vec<i16>>,
    quiet: usize,
    recording: bool,
}

impl Gate {
    /// One 20 ms frame in; the take to play back once a pause ends it.
    pub fn push(&mut self, frame: Vec<i16>) -> Option<Vec<Vec<i16>>> {
        let loud = rms(&frame) >= SPEECH_RMS;
        if !self.recording {
            if loud {
                self.recording = true;
                self.quiet = 0;
                self.take = self.preroll.drain(..).collect();
                self.take.push(frame);
            } else {
                self.preroll.push_back(frame);
                if self.preroll.len() > PREROLL_FRAMES {
                    self.preroll.pop_front();
                }
            }
            return None;
        }
        self.take.push(frame);
        self.quiet = if loud { 0 } else { self.quiet + 1 };
        if self.quiet >= PAUSE_FRAMES || self.take.len() >= MAX_FRAMES {
            self.recording = false;
            self.quiet = 0;
            return Some(std::mem::take(&mut self.take));
        }
        None
    }

    pub fn state(&self) -> Monitor {
        if self.recording {
            Monitor::Recording
        } else {
            Monitor::Listening
        }
    }
}

fn rms(samples: &[i16]) -> f64 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum: f64 = samples.iter().map(|&s| f64::from(s) * f64::from(s)).sum();
    (sum / samples.len() as f64).sqrt() / 32768.0
}

/// Monitor the preferred microphone: once you pause, what you said plays
/// on the preferred speaker. `ready` turns true once the microphone is
/// open (Teams' "Getting your microphone ready…" until then). None when
/// neither device can be opened.
pub fn monitor(ready: Arc<AtomicBool>) -> Option<Running> {
    let (capture, frames) = AudioCapture::start_at(RATE)?;
    let (playback, speaker) = AudioPlayback::start_at(RATE)?;
    ready.store(true, Ordering::SeqCst);
    let stop = Arc::new(AtomicBool::new(false));
    let done = stop.clone();
    thread::spawn(move || {
        let _devices = (capture, playback);
        let mut gate = Gate::default();
        while !done.load(Ordering::SeqCst) {
            let Ok(frame) = frames.recv_timeout(Duration::from_millis(100)) else {
                continue;
            };
            if let Some(take) = gate.push(frame) {
                let mut pace = Pacer::new();
                for f in take {
                    if done.load(Ordering::SeqCst) {
                        break;
                    }
                    pace.frame();
                    if speaker.send(f).is_err() {
                        break;
                    }
                }
                // Wait for the take to finish playing (and its echo to die
                // down), then drop what the microphone heard meanwhile: the
                // playback itself.
                let end = pace.queued_until() + Duration::from_millis(250);
                while !done.load(Ordering::SeqCst) && std::time::Instant::now() < end {
                    thread::sleep(Duration::from_millis(20));
                }
                while frames.try_recv().is_ok() {}
            }
        }
        ready.store(false, Ordering::SeqCst);
    });
    Some(Running { stop })
}

/// Keep the preferred microphone open (its level for a meter, nothing
/// played): the pre-join's microphone flyout. None when it can't be
/// opened.
pub fn meter() -> Option<Running> {
    let (capture, frames) = AudioCapture::start_at(RATE)?;
    let stop = Arc::new(AtomicBool::new(false));
    let done = stop.clone();
    thread::spawn(move || {
        let _capture = capture;
        while !done.load(Ordering::SeqCst) {
            let _ = frames.recv_timeout(Duration::from_millis(100));
        }
    });
    Some(Running { stop })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wav(channels: u16, rate: u32, samples: &[i16]) -> Vec<u8> {
        let data: Vec<u8> = samples.iter().flat_map(|s| s.to_le_bytes()).collect();
        let mut out = b"RIFF".to_vec();
        out.extend(((36 + data.len()) as u32).to_le_bytes());
        out.extend(b"WAVEfmt ");
        out.extend(16u32.to_le_bytes());
        out.extend(1u16.to_le_bytes());
        out.extend(channels.to_le_bytes());
        out.extend(rate.to_le_bytes());
        out.extend((rate * u32::from(channels) * 2).to_le_bytes());
        out.extend((channels * 2).to_le_bytes());
        out.extend(16u16.to_le_bytes());
        out.extend(b"data");
        out.extend((data.len() as u32).to_le_bytes());
        out.extend(data);
        out
    }

    #[test]
    fn reads_teams_test_sound_format() {
        // Teams' test sound: 16-bit PCM, stereo, 48 kHz.
        let s = parse_wav(&wav(2, 48_000, &[1, 2, 3, 4])).unwrap();
        assert_eq!(s, vec![[1, 2], [3, 4]]);
        // Mono plays on both sides.
        assert_eq!(parse_wav(&wav(1, 48_000, &[5])).unwrap(), vec![[5, 5]]);
        // Anything else isn't played.
        assert!(parse_wav(&wav(2, 44_100, &[1, 2])).is_none());
        assert!(parse_wav(b"not a wav").is_none());
    }

    #[test]
    fn plays_back_what_you_said_after_a_pause() {
        let quiet = vec![0i16; FRAME];
        let loud = vec![8000i16; FRAME];
        let mut g = Gate::default();
        // Silence: nothing to play, and only a short preroll is kept.
        for _ in 0..50 {
            assert!(g.push(quiet.clone()).is_none());
        }
        assert_eq!(g.state(), Monitor::Listening);
        // Speech, then a pause.
        for _ in 0..20 {
            assert!(g.push(loud.clone()).is_none());
        }
        assert_eq!(g.state(), Monitor::Recording);
        let mut take = None;
        for _ in 0..PAUSE_FRAMES {
            take = take.or(g.push(quiet.clone()));
        }
        let take = take.expect("played back after the pause");
        assert_eq!(take.len(), PREROLL_FRAMES + 20 + PAUSE_FRAMES);
        assert_eq!(g.state(), Monitor::Listening);
    }

    #[test]
    fn paces_frames_to_real_time() {
        // 25 frames (500 ms) take at least 500 ms less the lead.
        let t = std::time::Instant::now();
        let mut p = Pacer::new();
        for _ in 0..25 {
            p.frame();
        }
        assert!(t.elapsed() >= Duration::from_millis(500) - LEAD - Duration::from_millis(20));
        assert!(p.queued_until() >= t + Duration::from_millis(500));
    }

    #[test]
    fn a_long_take_is_cut() {
        let loud = vec![8000i16; FRAME];
        let mut g = Gate::default();
        let mut n = 0;
        let take = loop {
            n += 1;
            if let Some(t) = g.push(loud.clone()) {
                break t;
            }
            assert!(n < MAX_FRAMES + 5);
        };
        assert_eq!(take.len(), MAX_FRAMES);
    }
}
