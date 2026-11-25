//! Teams' avatars: Microsoft's Avatars video app draws your avatar into
//! the frames Teams hands it, which go out as your camera (Teams selects
//! the avatar as its camera device). Nothing is captured: the frames are
//! camera-less (`requireCameraStream: false`), and each carries the
//! newest result of the app's viseme model run on your microphone
//! (`audioInferenceModel`), so the avatar's mouth follows your speech.
//!
//! The desktop hosts the app (qml/AvatarHost.qml); this is the exchange
//! between its frames and the camera, and the lip-sync model.

use std::sync::{Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

use tract_onnx::prelude::*;

/// A frame the app is asked to draw: its size, number and the viseme
/// model's newest output (the app's `audioInferenceResult`: 22 f32, little
/// endian), empty when there is none.
#[derive(Clone, Debug, PartialEq)]
pub struct Request {
    pub width: u32,
    pub height: u32,
    pub seq: u64,
    pub visemes: Vec<u8>,
}

#[derive(Default)]
struct State {
    active: bool,
    next_seq: u64,
    request: Option<Request>,
    /// The app's newest frame (NV12) and when it came.
    output: Option<(super::filter::Frame, Instant)>,
    visemes: Option<(Vec<u8>, Instant)>,
}

fn state() -> &'static (Mutex<State>, Condvar) {
    static S: OnceLock<(Mutex<State>, Condvar)> = OnceLock::new();
    S.get_or_init(|| (Mutex::new(State::default()), Condvar::new()))
}

/// The avatar is the camera (Teams' avatar mode with an avatar chosen) or
/// not.
pub fn set_active(on: bool) {
    let (m, cv) = state();
    let mut s = m.lock().unwrap();
    s.active = on;
    if !on {
        s.request = None;
        s.output = None;
    }
    cv.notify_all();
}

pub fn active() -> bool {
    state().0.lock().unwrap().active
}

/// Whether the app has drawn a frame lately.
pub fn drawing() -> bool {
    state()
        .0
        .lock()
        .unwrap()
        .output
        .as_ref()
        .is_some_and(|(_, at)| at.elapsed() < OUTPUT_FRESH)
}

/// Visemes older than this are dropped (the microphone stopped).
const VISEMES_FRESH: Duration = Duration::from_millis(300);
/// The app's last frame is shown no longer than this when it stalls.
const OUTPUT_FRESH: Duration = Duration::from_secs(2);

/// The camera side: ask the app for the next frame at `width` x `height`,
/// and take its newest one (NV12), if it has drawn one lately at that size.
pub fn tick(width: u32, height: u32) -> Option<super::filter::Frame> {
    let (m, cv) = state();
    let mut s = m.lock().unwrap();
    if !s.active {
        return None;
    }
    s.next_seq += 1;
    let visemes = match &s.visemes {
        Some((v, at)) if at.elapsed() < VISEMES_FRESH => v.clone(),
        _ => Vec::new(),
    };
    s.request = Some(Request {
        width,
        height,
        seq: s.next_seq,
        visemes,
    });
    cv.notify_all();
    match &s.output {
        Some((f, at)) if f.width == width && f.height == height && at.elapsed() < OUTPUT_FRESH => {
            Some(f.clone())
        }
        _ => None,
    }
}

/// The app side: the next request newer than `after`, waiting up to
/// `wait` for one.
pub fn next_request(after: u64, wait: Duration) -> Option<Request> {
    let (m, cv) = state();
    let deadline = Instant::now() + wait;
    let mut s = m.lock().unwrap();
    loop {
        if let Some(r) = &s.request
            && r.seq > after
        {
            return Some(r.clone());
        }
        let now = Instant::now();
        if now >= deadline || !s.active {
            return None;
        }
        s = cv.wait_timeout(s, deadline - now).unwrap().0;
    }
}

/// The app side: a frame it drew (NV12).
pub fn put_output(f: super::filter::Frame) {
    let (m, _) = state();
    let mut s = m.lock().unwrap();
    if s.active && f.data.len() >= (f.width * f.height * 3 / 2) as usize {
        s.output = Some((f, Instant::now()));
    }
}

fn set_visemes(v: Vec<u8>) {
    state().0.lock().unwrap().visemes = Some((v, Instant::now()));
}

/// Forget the visemes (muted, or the microphone closed): the avatar's
/// mouth rests.
pub fn clear_visemes() {
    state().0.lock().unwrap().visemes = None;
}

/// The viseme model the app hands Teams (`VisemeModel-0.3.39.onnx`):
/// 1992 samples of 16 kHz mono audio (664 back, 1328 ahead) in, the
/// chances of 21 visemes and silence out, 30 times a second.
pub struct VisemeModel {
    model: Arc<TypedRunnableModel>,
}

/// The model's sample rate, window and rate (its metadata: sample_rate,
/// lookback + lookahead, frame_rate).
pub const RATE: u32 = 16_000;
pub const WINDOW: usize = 1992;
pub const HOP: usize = (RATE / 30) as usize;
pub const OUTPUTS: usize = 22;

impl VisemeModel {
    pub fn new(onnx: &[u8]) -> anyhow::Result<Self> {
        let model = tract_onnx::onnx()
            .model_for_read(&mut &onnx[..])?
            .with_input_fact(0, f32::fact([1, 1, WINDOW]).into())?
            .into_optimized()?
            .into_runnable()?;
        Ok(Self { model })
    }

    /// `window`: WINDOW samples, −1..1. The model's output.
    pub fn infer(&self, window: &[f32]) -> anyhow::Result<Vec<f32>> {
        anyhow::ensure!(window.len() == WINDOW, "the model takes {WINDOW} samples");
        let input: Tensor =
            tract_ndarray::Array3::<f32>::from_shape_fn((1, 1, WINDOW), |(_, _, i)| window[i])
                .into();
        let out = self.model.run(tvec!(input.into()))?;
        Ok(out[0]
            .to_plain_array_view::<f32>()?
            .iter()
            .copied()
            .collect())
    }
}

/// The model's output as the app takes it (`new Float32Array(new
/// Uint8Array(result).buffer)`).
pub fn viseme_bytes(v: &[f32]) -> Vec<u8> {
    v.iter().flat_map(|x| x.to_le_bytes()).collect()
}

struct Lipsync {
    model: Option<VisemeModel>,
    /// 16 kHz samples not yet run, the window's past kept in front.
    samples: Vec<f32>,
    /// Where the next window starts in `samples`.
    pending: usize,
    muted: bool,
    /// Resampling position (source samples per output sample).
    phase: f64,
}

fn lipsync() -> &'static Mutex<Lipsync> {
    static L: OnceLock<Mutex<Lipsync>> = OnceLock::new();
    L.get_or_init(|| {
        Mutex::new(Lipsync {
            model: None,
            samples: Vec::new(),
            pending: 0,
            muted: false,
            phase: 0.0,
        })
    })
}

/// Load the app's viseme model (its `audioInferenceModel`); an empty or
/// broken one turns lip sync off, as the app expects.
pub fn set_viseme_model(onnx: &[u8]) -> anyhow::Result<()> {
    let model = if onnx.len() > 2000 {
        Some(VisemeModel::new(onnx)?)
    } else {
        None
    };
    let mut l = lipsync().lock().unwrap();
    l.model = model;
    l.samples.clear();
    l.pending = 0;
    Ok(())
}

pub fn has_viseme_model() -> bool {
    lipsync().lock().unwrap().model.is_some()
}

/// Muted: the model doesn't run and the mouth rests.
pub fn set_muted(on: bool) {
    lipsync().lock().unwrap().muted = on;
    if on {
        clear_visemes();
    }
}

/// The microphone's processed samples (mono, at `rate` Hz) while a call
/// captures it: run the model each 1/30 s while an avatar is on.
pub fn feed(samples: &[i16], rate: u32) {
    if !active() || rate == 0 {
        return;
    }
    let mut l = lipsync().lock().unwrap();
    if l.model.is_none() || l.muted {
        return;
    }
    // Down to 16 kHz (linear).
    let step = rate as f64 / RATE as f64;
    let mut pos = l.phase;
    while pos < samples.len() as f64 {
        let i = pos as usize;
        let f = pos - i as f64;
        let a = samples[i] as f64;
        let b = samples.get(i + 1).copied().unwrap_or(samples[i]) as f64;
        l.samples.push(((a + (b - a) * f) / 32768.0) as f32);
        pos += step;
    }
    l.phase = pos - samples.len() as f64;
    let mut newest = None;
    while l.pending + WINDOW <= l.samples.len() {
        let at = l.pending;
        let out = l
            .model
            .as_ref()
            .and_then(|m| m.infer(&l.samples[at..at + WINDOW]).ok());
        if let Some(out) = out {
            newest = Some(out);
        }
        l.pending += HOP;
    }
    // Keep only what the next window needs.
    if l.pending > 0 {
        let drop = l.pending.min(l.samples.len());
        l.samples.drain(..drop);
        l.pending -= drop;
    }
    drop(l);
    if let Some(v) = newest {
        set_visemes(viseme_bytes(&v));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn camera_ticks_ask_the_app_and_take_its_frames() {
        set_active(true);
        assert!(tick(4, 2).is_none());
        let r = next_request(0, Duration::from_millis(10)).unwrap();
        assert_eq!((r.width, r.height), (4, 2));
        put_output(super::super::filter::Frame {
            width: 4,
            height: 2,
            seq: r.seq,
            data: vec![9; 12],
        });
        let f = tick(4, 2).unwrap();
        assert_eq!(f.data, vec![9; 12]);
        // Another size is a different camera: not the old picture.
        assert!(tick(8, 4).is_none());
        assert!(next_request(r.seq, Duration::from_millis(10)).unwrap().seq > r.seq);
        set_active(false);
        assert!(tick(4, 2).is_none());
    }

    #[test]
    fn visemes_go_to_the_app_as_float_bytes() {
        assert_eq!(
            viseme_bytes(&[1.0, 0.5]),
            vec![0, 0, 0x80, 0x3f, 0, 0, 0, 0x3f]
        );
        assert!(set_viseme_model(&[]).is_ok());
        assert!(!has_viseme_model());
        assert!(set_viseme_model(&[0u8; 4000]).is_err());
    }
}
