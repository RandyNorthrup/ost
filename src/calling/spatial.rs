//! Teams' spatial audio (Settings ▸ Devices ▸ Audio settings ▸ Spatial
//! audio): each speaker's voice comes from where their tile is on your
//! screen.
//!
//! How Teams does it (desktop bundle, `SpatialAudioMixinImplementation`):
//! - It is on only while all of these hold (`isValidToCallIC3`): the
//!   setting is on, the layout is supported (Gallery, Speaker and Together
//!   mode on desktop: `enableSpatialAudioForGalleryView`,
//!   `enableSpatialAudioForTogetherMode`), the speaker can play it
//!   (`isSpatialCapable`: stereo, not wireless headphones), the call isn't
//!   a 1:1 call (P2P) and more than one person (not bots) is in it.
//! - The call window reports each tile's place on the stage as a
//!   percentage (`updateSpatialAudioParticipantsPosition`), and Teams hands
//!   the media stack each participant's audio source with that place
//!   (`setParticipantSpatialAudioPositions [{participantId: sourceId, x,
//!   y}]`), which renders each voice from there (an HRTF panner per
//!   stream).
//!
//! OST asks the meeting for each speaker's own audio (x-much2, `super::much`)
//! and places each voice at its own tile: an equal-power pan with the
//! interaural time difference of a voice from that direction. A plain mix
//! (no x-much2) is placed where the tiles of the people speaking in it are
//! (its RTP CSRCs).

use std::collections::BTreeMap;
use std::sync::Mutex;

/// The widest angle a tile at the stage's edge is heard from (degrees off
/// centre).
pub const MAX_AZIMUTH_DEG: f32 = 60.0;
/// The largest interaural time difference (a voice from straight beside
/// you), in seconds.
const MAX_ITD_S: f32 = 0.00066;

#[derive(Default)]
struct State {
    /// The user's setting (Teams' spatialAudioEnabled).
    enabled: bool,
    /// The call window's state allows it now (layout, call type, people,
    /// a stereo speaker).
    valid: bool,
    /// Audio source → its tile's centre on the stage, 0–100 across.
    positions: BTreeMap<u32, (f32, f32)>,
}

fn state() -> &'static Mutex<State> {
    static S: Mutex<State> = Mutex::new(State {
        enabled: false,
        valid: false,
        positions: BTreeMap::new(),
    });
    &S
}

fn lock() -> std::sync::MutexGuard<'static, State> {
    state().lock().unwrap_or_else(|e| e.into_inner())
}

/// Teams' Spatial audio setting.
pub fn set_enabled(on: bool) {
    lock().enabled = on;
}

pub fn enabled() -> bool {
    lock().enabled
}

/// Whether spatial audio may play now (Teams' `isValidToCallIC3` and a
/// spatial-capable speaker); off, the mix plays as before.
pub fn set_valid(valid: bool) {
    lock().valid = valid;
}

/// Spatial audio is playing.
pub fn active() -> bool {
    let s = lock();
    s.enabled && s.valid
}

/// Each participant's audio source and their tile's centre (0–100 across
/// and down the stage), as Teams' `setParticipantSpatialAudioPositions`.
pub fn set_positions(positions: &[(u32, f32, f32)]) {
    let mut s = lock();
    s.positions = positions
        .iter()
        .map(|&(id, x, y)| (id, (x.clamp(0.0, 100.0), y.clamp(0.0, 100.0))))
        .collect();
}

/// Where one speaker (an audio source) is heard: their tile's place as an
/// azimuth (-1 left edge … 1 right), None when spatial audio is off or
/// they have no tile.
pub fn azimuth_of(source: u32) -> Option<f32> {
    let s = lock();
    if !(s.enabled && s.valid) {
        return None;
    }
    s.positions.get(&source).map(|p| (p.0 - 50.0) / 50.0)
}

static CAPABLE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// The speaker calls use can play spatial audio (Teams' isSpatialCapable).
pub fn set_capable(on: bool) {
    CAPABLE.store(on, std::sync::atomic::Ordering::Relaxed);
}

/// Whether a meeting joined now asks for each speaker's own audio
/// (x-much2), as Teams does while spatial audio is on and the speaker can
/// play it (its MUCHv2 codec selection), or while Interpreter balances the
/// interpretation against the meeting (enableLiveInterpretation).
pub fn wants_unmixed() -> bool {
    enabled() && CAPABLE.load(std::sync::atomic::Ordering::Relaxed)
        || super::ai_interpreter::listening()
}

/// Where a packet with these contributing sources is heard: the mean of
/// their tiles' places, as an azimuth from -1 (left edge) to 1 (right);
/// None when spatial audio is off or none of them has a tile.
pub fn azimuth_for(csrcs: &[u32]) -> Option<f32> {
    let s = lock();
    if !(s.enabled && s.valid) {
        return None;
    }
    let xs: Vec<f32> = csrcs
        .iter()
        .filter_map(|c| s.positions.get(c).map(|p| p.0))
        .collect();
    if xs.is_empty() {
        return None;
    }
    let mean = xs.iter().sum::<f32>() / xs.len() as f32;
    Some((mean - 50.0) / 50.0)
}

/// Teams' `isSpatialCapable` for a speaker: stereo, and not over
/// Bluetooth ("Not yet available with wireless headphones").
pub fn speaker_capable(channels: u32, bus: &str) -> bool {
    channels >= 2 && bus != "bluetooth"
}

/// Places mono frames in the stereo field, gliding between places so a
/// change of speaker doesn't click.
pub struct Spatializer {
    rate: u32,
    /// The current azimuth (-1..1) and the gains and delay that go with it.
    azimuth: f32,
    /// The last samples, for the far ear's delay.
    history: Vec<f32>,
}

impl Spatializer {
    pub fn new(rate: u32) -> Self {
        let max_delay = (MAX_ITD_S * rate as f32).ceil() as usize + 2;
        Spatializer {
            rate,
            azimuth: 0.0,
            history: vec![0.0; max_delay],
        }
    }

    fn gains(azimuth: f32) -> (f32, f32) {
        // Equal-power pan over the azimuth's angle.
        let angle = azimuth.clamp(-1.0, 1.0) * MAX_AZIMUTH_DEG.to_radians();
        let p = (angle / MAX_AZIMUTH_DEG.to_radians() + 1.0) * std::f32::consts::FRAC_PI_4;
        (
            p.cos() * std::f32::consts::SQRT_2,
            p.sin() * std::f32::consts::SQRT_2,
        )
    }

    fn delay(&self, azimuth: f32) -> f32 {
        let angle = azimuth.clamp(-1.0, 1.0) * MAX_AZIMUTH_DEG.to_radians();
        MAX_ITD_S * angle.sin().abs() * self.rate as f32
    }

    /// One frame placed at `azimuth` (None: centred, as an unplaced mix),
    /// interleaved left/right.
    pub fn process(&mut self, mono: &[i16], azimuth: Option<f32>) -> Vec<[i16; 2]> {
        let target = azimuth.unwrap_or(0.0).clamp(-1.0, 1.0);
        let start = self.azimuth;
        let n = mono.len().max(1);
        let hist = self.history.len();
        let mut buf: Vec<f32> = self.history.clone();
        buf.extend(mono.iter().map(|&s| f32::from(s)));
        let out = mono
            .iter()
            .enumerate()
            .map(|(i, &s)| {
                let a = start + (target - start) * (i + 1) as f32 / n as f32;
                let (gl, gr) = Self::gains(a);
                // Unplaced (centred) audio keeps its level: the equal-power
                // gains are 1 each at the centre.
                let d = self.delay(a);
                let here = f32::from(s);
                // The far ear hears it `d` samples later (linear
                // interpolation between the delayed samples).
                let pos = (hist + i) as f32 - d;
                let k = pos.floor().max(0.0) as usize;
                let frac = pos - k as f32;
                let late = buf[k] * (1.0 - frac) + buf.get(k + 1).copied().unwrap_or(here) * frac;
                let (l, r) = if a < 0.0 { (here, late) } else { (late, here) };
                let clamp = |v: f32| v.round().clamp(-32768.0, 32767.0) as i16;
                [clamp(l * gl), clamp(r * gr)]
            })
            .collect();
        self.azimuth = target;
        let keep = buf.len().saturating_sub(hist);
        self.history = buf[keep..].to_vec();
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn energy(frames: &[[i16; 2]], ch: usize) -> f64 {
        frames.iter().map(|f| f64::from(f[ch]).powi(2)).sum()
    }

    fn tone(n: usize) -> Vec<i16> {
        (0..n)
            .map(|i| {
                ((i as f32 * 2.0 * std::f32::consts::PI * 440.0 / 48000.0).sin() * 8000.0) as i16
            })
            .collect()
    }

    /// A voice from a tile on the left is louder in the left ear, and
    /// reaches the right ear later; centred it is the same in both.
    #[test]
    fn a_left_tile_is_heard_on_the_left() {
        let mut s = Spatializer::new(48_000);
        let mut out = Vec::new();
        for _ in 0..10 {
            out.extend(s.process(&tone(960), Some(-1.0)));
        }
        let tail = &out[960 * 5..];
        assert!(
            energy(tail, 0) > 4.0 * energy(tail, 1),
            "left {} right {}",
            energy(tail, 0),
            energy(tail, 1)
        );
        let mut c = Spatializer::new(48_000);
        let centre = c.process(&tone(960), None);
        assert!(centre.iter().all(|f| f[0] == f[1]));
        assert!(
            (energy(&centre, 0)
                - energy(&tone(960).iter().map(|&x| [x, x]).collect::<Vec<_>>(), 0))
            .abs()
                < 1.0
        );
    }

    /// The mix is placed where its speakers' tiles are, only while spatial
    /// audio is on and allowed.
    #[test]
    fn the_mix_goes_where_its_speakers_tiles_are() {
        set_positions(&[(10, 0.0, 50.0), (20, 100.0, 50.0), (30, 75.0, 50.0)]);
        set_enabled(false);
        set_valid(true);
        assert_eq!(azimuth_for(&[10]), None);
        set_enabled(true);
        assert_eq!(azimuth_for(&[10]), Some(-1.0));
        assert_eq!(azimuth_for(&[20]), Some(1.0));
        assert_eq!(azimuth_for(&[10, 20]), Some(0.0));
        assert_eq!(azimuth_for(&[30, 99]), Some(0.5));
        assert_eq!(azimuth_for(&[99]), None);
        set_valid(false);
        assert_eq!(azimuth_for(&[10]), None);
        set_enabled(false);
        assert!(
            speaker_capable(2, "pci")
                && !speaker_capable(1, "usb")
                && !speaker_capable(2, "bluetooth")
        );
    }
}
