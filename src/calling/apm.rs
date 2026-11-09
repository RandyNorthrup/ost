//! WebRTC's audio processing on the call's audio (as Teams' media stack
//! does its own): acoustic echo cancellation, noise suppression and
//! automatic gain control on the microphone, with what is played as the
//! echo canceller's reference. 48 kHz mono, 10 ms frames, through the
//! distribution's webrtc-audio-processing-1 (src/calling/native/apm.cpp).

use std::sync::{Arc, Mutex};

#[repr(C)]
struct RawApm {
    _private: [u8; 0],
}

unsafe extern "C" {
    fn ost_apm_new(sample_rate: i32) -> *mut RawApm;
    fn ost_apm_set(a: *mut RawApm, echo: bool, noise: bool, noise_level: i32, gain: bool);
    fn ost_apm_render(a: *mut RawApm, frame: *mut i16) -> i32;
    fn ost_apm_capture(a: *mut RawApm, frame: *mut i16, delay_ms: i32) -> i32;
    fn ost_apm_free(a: *mut RawApm);
}

/// Samples in one 10 ms frame at 48 kHz.
pub const CHUNK: usize = 480;

/// Noise suppression strength (Teams' Auto / High / Low; Off disables it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoiseLevel {
    Off,
    Low,
    High,
}

/// One audio processor for a call.
pub struct Processor {
    raw: *mut RawApm,
}

// SAFETY: WebRTC's AudioProcessing is built for the render and capture
// sides to run on different threads; every call here also goes through
// the Mutex in [`Shared`].
unsafe impl Send for Processor {}

impl Processor {
    pub fn new() -> Option<Self> {
        // SAFETY: a plain constructor; null on failure.
        let raw = unsafe { ost_apm_new(48_000) };
        (!raw.is_null()).then_some(Processor { raw })
    }

    pub fn configure(&mut self, echo: bool, noise: NoiseLevel, gain: bool) {
        let (on, level) = match noise {
            NoiseLevel::Off => (false, 2),
            NoiseLevel::Low => (true, 1),
            NoiseLevel::High => (true, 2),
        };
        // SAFETY: `raw` is live until Drop.
        unsafe { ost_apm_set(self.raw, echo, on, level, gain) }
    }

    /// What is about to be played (any length; whole 10 ms chunks are
    /// fed, the rest is dropped from the reference).
    pub fn render(&mut self, frame: &mut [i16]) {
        for chunk in frame.as_chunks_mut::<CHUNK>().0 {
            // SAFETY: a 480-sample buffer, as configured.
            unsafe { ost_apm_render(self.raw, chunk.as_mut_ptr()) };
        }
    }

    /// The microphone's samples, processed in place, given roughly how
    /// long played audio takes to come back into the microphone.
    pub fn capture(&mut self, frame: &mut [i16], delay_ms: i32) {
        for chunk in frame.as_chunks_mut::<CHUNK>().0 {
            // SAFETY: as above.
            unsafe { ost_apm_capture(self.raw, chunk.as_mut_ptr(), delay_ms) };
        }
    }
}

impl Drop for Processor {
    fn drop(&mut self) {
        // SAFETY: freed once.
        unsafe { ost_apm_free(self.raw) }
    }
}

/// The processor the running call's audio goes through.
pub type Shared = Arc<Mutex<Processor>>;

/// The user's choices (Teams' noise suppression setting).
static NOISE: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(2);

pub fn noise_level() -> NoiseLevel {
    match NOISE.load(std::sync::atomic::Ordering::Relaxed) {
        0 => NoiseLevel::Off,
        1 => NoiseLevel::Low,
        _ => NoiseLevel::High,
    }
}

pub fn set_noise_level(level: NoiseLevel) {
    NOISE.store(
        match level {
            NoiseLevel::Off => 0,
            NoiseLevel::Low => 1,
            NoiseLevel::High => 2,
        },
        std::sync::atomic::Ordering::Relaxed,
    );
    reconfigure();
}

/// Teams' High fidelity music mode: gain control off, echo cancellation
/// only if chosen ("Enable echo cancellation"), and the encoder at music
/// quality (see `audio_codec`).
static MUSIC: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static MUSIC_ECHO: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

pub fn music_mode() -> bool {
    MUSIC.load(std::sync::atomic::Ordering::Relaxed)
}

pub fn set_music_mode(on: bool, echo_cancellation: bool) {
    MUSIC.store(on, std::sync::atomic::Ordering::Relaxed);
    MUSIC_ECHO.store(echo_cancellation, std::sync::atomic::Ordering::Relaxed);
    reconfigure();
}

/// The processing the settings call for: (echo, noise, gain).
fn wanted() -> (bool, NoiseLevel, bool) {
    if music_mode() {
        // Noise suppression stays the user's switch (Teams turns it off
        // when music mode starts, and lets you turn it back on).
        (MUSIC_ECHO.load(std::sync::atomic::Ordering::Relaxed), noise_level(), false)
    } else {
        (true, noise_level(), true)
    }
}

fn reconfigure() {
    if let Some(p) = current() {
        let (echo, noise, gain) = wanted();
        p.lock().unwrap_or_else(|e| e.into_inner()).configure(echo, noise, gain);
    }
}

fn slot() -> &'static Mutex<Option<Shared>> {
    static S: Mutex<Option<Shared>> = Mutex::new(None);
    &S
}

/// The running call's processor.
pub fn current() -> Option<Shared> {
    slot().lock().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Start processing for a call (dropping the returned handle's last copy
/// and calling [`stop`] ends it).
pub fn start() -> Option<Shared> {
    // OST_APM=off: no processing (diagnostics).
    if std::env::var("OST_APM").is_ok_and(|v| v == "off") {
        return None;
    }
    let mut p = Processor::new()?;
    let (echo, noise, gain) = wanted();
    p.configure(echo, noise, gain);
    let shared = Arc::new(Mutex::new(p));
    *slot().lock().unwrap_or_else(|e| e.into_inner()) = Some(shared.clone());
    Some(shared)
}

pub fn stop() {
    *slot().lock().unwrap_or_else(|e| e.into_inner()) = None;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A tone played and picked up again is cancelled from the microphone
    /// once the echo canceller has converged.
    #[test]
    fn cancels_a_played_echo() {
        let mut p = Processor::new().expect("apm");
        p.configure(true, NoiseLevel::Off, false);
        let tone = |i: usize| ((i as f32 * 2.0 * std::f32::consts::PI * 700.0 / 48000.0).sin() * 6000.0) as i16;
        let mut before = 0.0;
        let mut after = 0.0;
        for n in 0..600 {
            let mut far: Vec<i16> = (0..CHUNK).map(|i| tone(n * CHUNK + i)).collect();
            p.render(&mut far);
            // The microphone hears it 20 ms later at half level.
            let mut near: Vec<i16> = (0..CHUNK).map(|i| tone((n * CHUNK + i).saturating_sub(960)) / 2).collect();
            let rms = |f: &[i16]| (f.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / f.len() as f64).sqrt();
            let input = rms(&near);
            p.capture(&mut near, 20);
            if n == 10 {
                before = input;
            }
            if n >= 550 {
                after += rms(&near) / 50.0;
            }
        }
        assert!(after < before / 4.0, "echo {after} of {before}");
    }
}
