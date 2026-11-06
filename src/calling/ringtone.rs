//! The incoming-call ring: a soft two-tone chime on the default output
//! device, repeated until dropped. Synthesised here (OST does not ship
//! Microsoft's ringtone).

use std::f32::consts::TAU;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use super::audio::AudioPlayback;

/// Sample rate of the playback frames.
const RATE: f32 = 8000.0;
/// 20 ms frames, as AudioPlayback expects.
const FRAME: usize = 160;
/// The chord (C5 + G5) and its loudness.
const TONES_HZ: [f32; 2] = [523.25, 783.99];
const LEVEL: f32 = 0.22;
/// Edge fade so the tone does not click.
const FADE_MS: f32 = 12.0;
/// on, off, on, rest (ms).
const PATTERN_MS: [(bool, u32); 4] = [(true, 400), (false, 200), (true, 400), (false, 2000)];

/// Rings while alive.
pub struct Ringtone {
    stop: Arc<AtomicBool>,
}

impl Ringtone {
    /// Start ringing; `None` if there is no output device.
    pub fn start() -> Option<Self> {
        let (playback, tx) = AudioPlayback::start()?;
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        std::thread::spawn(move || {
            let _playback = playback;
            while !flag.load(Ordering::Relaxed) {
                for frame in ring_cycle() {
                    if flag.load(Ordering::Relaxed) || tx.send(frame).is_err() {
                        return;
                    }
                }
            }
        });
        Some(Self { stop })
    }
}

impl Drop for Ringtone {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// One full ring pattern as 20 ms frames.
fn ring_cycle() -> Vec<Vec<i16>> {
    let mut samples = Vec::new();
    for (on, ms) in PATTERN_MS {
        let n = (RATE * ms as f32 / 1000.0) as usize;
        let fade = (RATE * FADE_MS / 1000.0) as usize;
        for i in 0..n {
            if !on {
                samples.push(0i16);
                continue;
            }
            let t = i as f32 / RATE;
            let env = (i.min(n - 1 - i) as f32 / fade as f32).min(1.0);
            let v: f32 =
                TONES_HZ.iter().map(|f| (TAU * f * t).sin()).sum::<f32>() / TONES_HZ.len() as f32;
            samples.push((v * env * LEVEL * i16::MAX as f32) as i16);
        }
    }
    samples
        .chunks(FRAME)
        .map(|c| {
            let mut f = c.to_vec();
            f.resize(FRAME, 0);
            f
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cycle_is_three_seconds_of_quiet_clickless_frames() {
        let frames = ring_cycle();
        assert_eq!(frames.len(), 150); // 3000 ms / 20 ms
        assert!(frames.iter().all(|f| f.len() == FRAME));
        let peak = frames
            .iter()
            .flatten()
            .map(|s| s.unsigned_abs())
            .max()
            .unwrap();
        assert!(
            peak > 1000 && peak < (i16::MAX as f32 * 0.3) as u16,
            "peak {peak}"
        );
        // Faded edges: the first sample of the tone is silent.
        assert_eq!(frames[0][0], 0);
    }

    /// Plays on the real output device; run by hand with --ignored.
    #[test]
    #[ignore]
    fn rings_on_the_default_device() {
        let r = Ringtone::start().expect("no output device");
        std::thread::sleep(std::time::Duration::from_secs(3));
        drop(r);
    }
}
