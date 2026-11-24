//! Speaking while muted, as Teams tells (calling-pluginless'
//! speechDetectionDiagnostics, raising the DeviceSpeakWhileMuted alert):
//! every second (its stats poll) it notes whether the microphone's level is
//! above [`SPEAKING_LEVEL`]; while you're muted it keeps the last
//! [`WINDOW`] notes, and more than [`THRESHOLD`] of them speaking means
//! you're talking with the mic off. Unmuting forgets them.

use std::collections::VecDeque;

/// How many one-second notes Teams keeps (speakingWhileMutedDetectionWindow).
pub const WINDOW: usize = 3;
/// More than this many of them must be speaking
/// (speakingWhileMutedSpeechThreshold).
pub const THRESHOLD: usize = 1;
/// A level above this is speaking (isSpeakingInputLevel, of WebRTC's 0–1
/// audioLevel).
pub const SPEAKING_LEVEL: f32 = 0.1;

/// The last few seconds while muted.
#[derive(Debug, Default)]
pub struct Detector {
    notes: VecDeque<bool>,
}

impl Detector {
    pub fn new() -> Self {
        Self::default()
    }

    /// One second's report: whether you're muted and the mic's level now.
    /// True while Teams would say you're speaking muted.
    pub fn report(&mut self, muted: bool, level: f32) -> bool {
        if !muted {
            self.notes.clear();
            return false;
        }
        if self.notes.len() == WINDOW {
            self.notes.pop_front();
        }
        self.notes.push_back(level > SPEAKING_LEVEL);
        self.notes.len() == WINDOW && self.notes.iter().filter(|s| **s).count() > THRESHOLD
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_of_the_last_three_seconds_muted_and_loud() {
        let mut d = Detector::new();
        assert!(!d.report(true, 0.5), "a window isn't full yet");
        assert!(!d.report(true, 0.5));
        assert!(d.report(true, 0.02), "two of three");
        assert!(!d.report(true, 0.02), "one of three");
        assert!(!d.report(true, 0.3), "still one of three");
        assert!(d.report(true, 0.3));
    }

    #[test]
    fn unmuting_forgets() {
        let mut d = Detector::new();
        d.report(true, 0.5);
        d.report(true, 0.5);
        assert!(!d.report(false, 0.9));
        assert!(!d.report(true, 0.5), "starts over");
        assert!(!d.report(true, 0.1), "0.1 itself isn't speaking");
        assert!(!d.report(true, 0.05));
    }
}
