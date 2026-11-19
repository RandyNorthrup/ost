//! Sign language detection: Teams' "actively signing" signal in Sign
//! language mode. While a signer's camera is on, their client watches it and
//! tells the meeting when they sign, so the signer is treated as an active
//! speaker. Teams runs a downloaded proprietary model (a landmark tracker
//! and a sequence classifier); OST does the same job with an open pose model
//! (MoveNet SinglePose Lightning, Apache-2.0, run with tract) and a rule over
//! the last moments of its keypoints:
//!
//! - the camera is evaluated about ten times a second ([`EVAL_INTERVAL_MS`]);
//!   frames between evaluations keep the last decision;
//! - a person must be there (both shoulders found), and a hand (a wrist) must
//!   be up in the signing space: in front of the upper body, from above the
//!   head down to about the bottom of the chest, measured in shoulder widths
//!   from the shoulders' centre, so it doesn't matter how far the signer
//!   sits from the camera or where they are in the picture;
//! - and that hand must be signing over the last [`WINDOW_MS`]: moving (its
//!   positions, relative to the shoulders so moving in the chair doesn't
//!   count, spread over at least [`MIN_MOTION`] shoulder widths), or, held in
//!   place, changing shape (fingerspelling: the picture of the hand, a coarse
//!   grid of its luma, changes by at least [`MIN_SHAPE_CHANGE`] from one
//!   evaluation to the next on average).
//!
//! So a still person, someone holding a hand up without moving it, someone
//! talking with their hands down (or out of the picture), and an empty room
//! aren't signing. Talking with lively hand gestures in front of the chest
//! can look the same to it.
//!
//! [`SigningAggregator`] turns the per-frame decisions into Teams' messages
//! (its sign language detection worker's rules), and has no model.

use std::collections::VecDeque;
use std::sync::Arc;

use tract_onnx::prelude::*;

/// The model's file name. It isn't shipped with OST: OST downloads it on
/// first need (the engine's calling::sign_detection) and hands its bytes to
/// [`SignDetector::new`].
pub const MODEL_FILE: &str = "movenet_singlepose_lightning.onnx";

/// The model's input: a square RGB picture this many points across.
pub const INPUT: usize = 192;

/// Frames are evaluated this often on average; frames in between keep the
/// last decision.
pub const EVAL_INTERVAL_MS: u64 = 100;

/// How far back a hand's signing is looked at.
pub const WINDOW_MS: u64 = 800;

/// How much a raised hand must move over [`WINDOW_MS`] to count as signing:
/// the diagonal of the box its positions span, in shoulder widths.
pub const MIN_MOTION: f32 = 0.3;

/// How much a raised hand's picture must change from one evaluation to the
/// next, on average over [`WINDOW_MS`], to count as signing with the hand
/// in place: mean luma levels per cell (a still hand's picture changes by
/// 1 to 3 with camera noise and compression).
pub const MIN_SHAPE_CHANGE: f32 = 4.0;

/// The hand's centre is taken this far past the wrist, in forearm lengths
/// (elbow to wrist)...
const HAND_REACH: f32 = 0.4;
/// ...and its picture is a square this many shoulder widths across...
const HAND_SIDE: f32 = 0.8;
/// ...of this many cells across.
const PATCH: usize = 8;

/// The keypoint confidence below which a keypoint counts as not found.
const MIN_SCORE: f32 = 0.3;

/// The narrowest shoulders taken as a person (a fraction of the model's
/// picture): anything smaller is too far away to see hands on.
const MIN_SHOULDER_WIDTH: f32 = 0.04;

/// The signing space, relative to the shoulders' centre in shoulder widths
/// (y grows downwards): from this far above the shoulders...
const SPACE_TOP: f32 = -2.5;
/// ...to this far below them (about the bottom of the chest)...
const SPACE_BOTTOM: f32 = 1.1;
/// ...and this far to either side.
const SPACE_SIDE: f32 = 1.5;

/// The fewest evaluations of a raised hand in the window (or changes of its
/// picture) before it is judged.
const MIN_SAMPLES: usize = 3;
// MoveNet's keypoints (COCO order).
const LEFT_SHOULDER: usize = 5;
const RIGHT_SHOULDER: usize = 6;
const LEFT_ELBOW: usize = 7;
const RIGHT_ELBOW: usize = 8;
const LEFT_WRIST: usize = 9;
const RIGHT_WRIST: usize = 10;
const KEYPOINTS: usize = 17;

/// A hand up in the signing space, at one evaluation.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Hand {
    /// The wrist relative to the shoulders' centre, in shoulder widths.
    rel: [f32; 2],
    /// The hand's centre (past the wrist, away from the elbow) and the side
    /// of the square around it, in the model's picture (0..1 across).
    centre: [f32; 2],
    side: f32,
}

/// One evaluation: each wrist's raised position, and how much its hand's
/// picture changed since the evaluation before.
struct Sample {
    t_ms: u64,
    wrists: [Option<[f32; 2]>; 2],
    changes: [Option<f32>; 2],
}

/// Detects signing on a camera's I420 frames.
pub struct SignDetector {
    model: Arc<TypedRunnableModel>,
    history: VecDeque<Sample>,
    /// Each raised hand's picture at the last evaluation.
    patches: [Option<Patch>; 2],
    /// When the next frame is evaluated (0: the first frame is).
    next_eval: u64,
    signing: bool,
}

impl SignDetector {
    /// Loads and optimises the pose model from its ONNX bytes (MoveNet
    /// SinglePose Lightning: 1 x 192 x 192 x 3 RGB as int32 in, 1 x 1 x 17
    /// x 3 keypoints (y, x, score) out).
    pub fn new(model: &[u8]) -> anyhow::Result<Self> {
        let model = tract_onnx::onnx()
            .model_for_read(&mut &model[..])?
            .with_input_fact(0, i32::fact([1, INPUT, INPUT, 3]).into())?
            .into_optimized()?
            .into_runnable()?;
        Ok(Self {
            model,
            history: VecDeque::new(),
            patches: [None, None],
            next_eval: 0,
            signing: false,
        })
    }

    /// One camera frame (`width` x `height` I420, taken at `t_ms` on a
    /// steady clock): whether it counts as signing. Frames are evaluated
    /// every [`EVAL_INTERVAL_MS`] on average (see [`next_eval_ms`]); the
    /// others get the last decision. A frame too short for its size isn't
    /// signing.
    ///
    /// [`next_eval_ms`]: Self::next_eval_ms
    pub fn push_frame(&mut self, i420: &[u8], width: u32, height: u32, t_ms: u64) -> bool {
        let (w, h) = (width as usize, height as usize);
        if w < 2 || h < 2 || i420.len() < w * h + 2 * (w / 2) * (h / 2) {
            self.signing = false;
            return false;
        }
        if t_ms < self.next_eval {
            if self.next_eval - t_ms <= EVAL_INTERVAL_MS {
                return self.signing;
            }
            // The clock went back: what was seen is no longer comparable.
            self.history.clear();
            self.patches = [None, None];
            self.next_eval = t_ms;
        }
        // A pause (no frames for a while): the last hand pictures are stale.
        if t_ms - self.next_eval > EVAL_INTERVAL_MS {
            self.patches = [None, None];
        }
        // On schedule (a 30 fps camera gets ten evaluations a second, not one
        // every fourth frame), but never two frames in a row after a pause.
        self.next_eval = (self.next_eval.max(t_ms.saturating_sub(EVAL_INTERVAL_MS)) + EVAL_INTERVAL_MS)
            .max(t_ms + EVAL_INTERVAL_MS / 2);
        let hands = match self.keypoints(i420, w, h) {
            Ok(k) => raised_hands(&k),
            Err(e) => {
                note_failure(&e);
                [None, None]
            }
        };
        let mut changes = [None, None];
        for (i, hand) in hands.iter().enumerate() {
            let patch = hand.and_then(|hand| Patch::new(i420, w, h, hand.centre, hand.side));
            changes[i] = self.patches[i].as_ref().zip(patch.as_ref()).map(|(a, b)| a.change(b));
            self.patches[i] = patch;
        }
        while self.history.front().is_some_and(|s| s.t_ms + WINDOW_MS < t_ms || s.t_ms > t_ms) {
            self.history.pop_front();
        }
        self.history.push_back(Sample {
            t_ms,
            wrists: hands.map(|h| h.map(|h| h.rel)),
            changes,
        });
        self.signing = (0..2).any(|i| hands[i].is_some() && (moving(&self.history, i) || shaping(&self.history, i)));
        self.signing
    }

    /// When [`push_frame`](Self::push_frame) next evaluates a frame: one
    /// taken before then (and after the last evaluation) only gets the last
    /// decision, so a caller handing frames to another thread can skip it.
    pub fn next_eval_ms(&self) -> u64 {
        self.next_eval
    }

    /// The pose's keypoints, `[x, y, score]` in the model's square picture
    /// (0..1 across; the frame is letterboxed into it).
    fn keypoints(&self, i420: &[u8], w: usize, h: usize) -> anyhow::Result<[[f32; 3]; KEYPOINTS]> {
        let input: Tensor = tract_ndarray::Array4::from_shape_vec((1, INPUT, INPUT, 3), model_input(i420, w, h))?.into();
        let out = self.model.run(tvec!(input.into()))?;
        let out = out[0].to_plain_array_view::<f32>()?;
        let out = out
            .as_slice()
            .filter(|o| o.len() == KEYPOINTS * 3)
            .ok_or_else(|| anyhow::anyhow!("unexpected pose output shape {:?}", out.shape()))?;
        let mut k = [[0f32; 3]; KEYPOINTS];
        for (k, p) in k.iter_mut().zip(out.chunks_exact(3)) {
            *k = [p[1], p[0], p[2]];
        }
        Ok(k)
    }
}

/// Failing to run the model on a frame isn't worth stopping for (the next
/// frame is tried); it is only noted once.
fn note_failure(e: &anyhow::Error) {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| eprintln!("sign detection: the pose model failed on a frame: {e:#}"));
}

/// The frame letterboxed into the model's square input (RGB, int32 0..255;
/// each point the average of the luma it covers).
fn model_input(i420: &[u8], w: usize, h: usize) -> Vec<i32> {
    let mut rgb = vec![0i32; INPUT * INPUT * 3];
    let scale = w.max(h) as f32 / INPUT as f32;
    let (cw, ch) = (
        ((w as f32 / scale).round() as usize).min(INPUT),
        ((h as f32 / scale).round() as usize).min(INPUT),
    );
    let (ox, oy) = ((INPUT - cw) / 2, (INPUT - ch) / 2);
    let (cw2, u_at, v_at) = (w / 2, w * h, w * h + (w / 2) * (h / 2));
    for my in 0..ch {
        let y0 = ((my as f32 * scale) as usize).min(h - 1);
        let y1 = (((my + 1) as f32 * scale) as usize).clamp(y0 + 1, h);
        for mx in 0..cw {
            let x0 = ((mx as f32 * scale) as usize).min(w - 1);
            let x1 = (((mx + 1) as f32 * scale) as usize).clamp(x0 + 1, w);
            let luma = box_mean(i420, w, x0..x1, y0..y1);
            let c = (((y0 + y1) / 4).min(h / 2 - 1)) * cw2 + ((x0 + x1) / 4).min(cw2 - 1);
            let p = crate::yuv_to_rgb(luma, i420[u_at + c] as f32, i420[v_at + c] as f32);
            let o = ((oy + my) * INPUT + ox + mx) * 3;
            for (d, s) in rgb[o..o + 3].iter_mut().zip(p) {
                *d = s as i32;
            }
        }
    }
    rgb
}

/// The mean luma of a (non-empty, in-frame) box of a `w`-wide frame.
fn box_mean(i420: &[u8], w: usize, xs: std::ops::Range<usize>, ys: std::ops::Range<usize>) -> f32 {
    let n = (xs.len() * ys.len()) as f32;
    let mut sum = 0u32;
    for row in i420[ys.start * w..ys.end * w].chunks_exact(w) {
        sum += row[xs.clone()].iter().map(|&v| v as u32).sum::<u32>();
    }
    sum as f32 / n
}

/// The hands up in the signing space, when there is a person.
fn raised_hands(k: &[[f32; 3]; KEYPOINTS]) -> [Option<Hand>; 2] {
    let (l, r) = (k[LEFT_SHOULDER], k[RIGHT_SHOULDER]);
    if l[2] < MIN_SCORE || r[2] < MIN_SCORE {
        return [None, None];
    }
    let width = (l[0] - r[0]).hypot(l[1] - r[1]);
    if width < MIN_SHOULDER_WIDTH {
        return [None, None];
    }
    let centre = [(l[0] + r[0]) / 2.0, (l[1] + r[1]) / 2.0];
    [(LEFT_WRIST, LEFT_ELBOW), (RIGHT_WRIST, RIGHT_ELBOW)].map(|(wi, ei)| {
        let (p, e) = (k[wi], k[ei]);
        let rel = [(p[0] - centre[0]) / width, (p[1] - centre[1]) / width];
        let raised = p[2] >= MIN_SCORE && (SPACE_TOP..=SPACE_BOTTOM).contains(&rel[1]) && rel[0].abs() <= SPACE_SIDE;
        // Without its elbow, the hand is taken to be around the wrist.
        let reach = if e[2] >= MIN_SCORE { HAND_REACH } else { 0.0 };
        raised.then(|| Hand {
            rel,
            centre: [p[0] + reach * (p[0] - e[0]), p[1] + reach * (p[1] - e[1])],
            side: HAND_SIDE * width,
        })
    })
}

/// A hand's picture: the mean luma of each cell of a [`PATCH`] x [`PATCH`]
/// grid over the square around it, less the square's mean (so a camera's
/// exposure changes don't count).
struct Patch([f32; PATCH * PATCH]);

impl Patch {
    /// The square around `centre` with sides `side` (in the model's
    /// picture), moved into the frame where it sticks out. None when it is
    /// too small to see a hand on, or larger than the frame.
    fn new(i420: &[u8], w: usize, h: usize, centre: [f32; 2], side: f32) -> Option<Self> {
        let long = w.max(h) as f32;
        let side = (side * long) as usize;
        if side < PATCH * 2 || side > w.min(h) {
            return None;
        }
        // The model's picture is the frame letterboxed into a square.
        let x = centre[0] * long - (long - w as f32) / 2.0 - side as f32 / 2.0;
        let y = centre[1] * long - (long - h as f32) / 2.0 - side as f32 / 2.0;
        let (x0, y0) = ((x.max(0.0) as usize).min(w - side), (y.max(0.0) as usize).min(h - side));
        let mut cells = [0f32; PATCH * PATCH];
        for (i, cell) in cells.iter_mut().enumerate() {
            let (cx, cy) = (i % PATCH, i / PATCH);
            let xs = x0 + cx * side / PATCH..x0 + (cx + 1) * side / PATCH;
            let ys = y0 + cy * side / PATCH..y0 + (cy + 1) * side / PATCH;
            *cell = box_mean(i420, w, xs, ys);
        }
        let mean = cells.iter().sum::<f32>() / cells.len() as f32;
        cells.iter_mut().for_each(|c| *c -= mean);
        Some(Self(cells))
    }

    /// How different another picture of the hand is: the mean absolute
    /// difference of the cells, in luma levels.
    fn change(&self, other: &Self) -> f32 {
        self.0.iter().zip(&other.0).map(|(a, b)| (a - b).abs()).sum::<f32>() / self.0.len() as f32
    }
}

/// Whether wrist `i` moved enough while raised over the window.
fn moving(history: &VecDeque<Sample>, i: usize) -> bool {
    motion(history, i).is_some_and(|m| m >= MIN_MOTION)
}

/// How far wrist `i` moved while raised over the window: the diagonal of
/// the box its positions span (None: seen raised too few times).
fn motion(history: &VecDeque<Sample>, i: usize) -> Option<f32> {
    let mut n = 0;
    let (mut lo, mut hi) = ([f32::MAX; 2], [f32::MIN; 2]);
    for p in history.iter().filter_map(|s| s.wrists[i]) {
        n += 1;
        for a in 0..2 {
            lo[a] = lo[a].min(p[a]);
            hi[a] = hi[a].max(p[a]);
        }
    }
    (n >= MIN_SAMPLES).then(|| (hi[0] - lo[0]).hypot(hi[1] - lo[1]))
}

/// Whether hand `i` changed shape enough while raised over the window.
fn shaping(history: &VecDeque<Sample>, i: usize) -> bool {
    shape_change(history, i).is_some_and(|c| c >= MIN_SHAPE_CHANGE)
}

/// How much hand `i`'s picture changed from one evaluation to the next
/// while raised over the window, on average (None: too few to tell).
fn shape_change(history: &VecDeque<Sample>, i: usize) -> Option<f32> {
    let changes: Vec<f32> = history.iter().filter_map(|s| s.changes[i]).collect();
    (changes.len() >= MIN_SAMPLES).then(|| changes.iter().sum::<f32>() / changes.len() as f32)
}
/// Signing must last this long before the meeting is told
/// (`kSignEventMinDurationMs`).
pub const MIN_DURATION_MS: u64 = 500;
/// While signing goes on, the meeting is told again on each tick from this
/// long after the start (`kRegularSigningEventIntervalMs`).
pub const REGULAR_INTERVAL_MS: u64 = 2000;
/// The aggregator's tick period.
pub const TICK_MS: u64 = 500;
/// Started, with no `signed` message for this long, it stops
/// (`timeoutOfSigningSignal`).
pub const SIGNAL_TIMEOUT_MS: u64 = 3000;
/// Signing frames this far apart (or closer) are one stretch of signing; a
/// longer gap starts the [`MIN_DURATION_MS`] over.
const RUN_GAP_MS: u64 = 300;

/// A message to the meeting: `{signDetected, duration}`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SignMessage {
    /// Signing (started or still going on), or stopped.
    pub signed: bool,
    /// How long since signing started (0 at the start and on a stop).
    pub duration_ms: u64,
}

impl SignMessage {
    const STOP: Self = Self {
        signed: false,
        duration_ms: 0,
    };
}

/// Teams' messaging rules for the signal, from its sign language detection
/// worker: fed each frame's decision ([`push`](Self::push)) and a tick every
/// [`TICK_MS`] ([`tick`](Self::tick)), on one clock in milliseconds. The
/// messages come from the ticks:
///
/// - the first tick after signing frames have covered [`MIN_DURATION_MS`]
///   starts it: `{true, 0}`;
/// - from [`REGULAR_INTERVAL_MS`] after the start, each tick that saw a
///   signing frame since the last tick: `{true, ms since the start}`;
/// - the first tick with no signing frame since the last message, or
///   [`SIGNAL_TIMEOUT_MS`] without a `true` message, stops it: `{false, 0}`.
#[derive(Default)]
pub struct SigningAggregator {
    /// The current stretch of signing frames: its first and last frame.
    run: Option<(u64, u64)>,
    /// When it started (the start message).
    started: Option<u64>,
    last_true: u64,
    since_tick: bool,
    since_message: bool,
}

impl SigningAggregator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Signing has started and not stopped.
    pub fn started(&self) -> bool {
        self.started.is_some()
    }

    /// A frame's decision, taken at `t_ms`.
    pub fn push(&mut self, signing: bool, t_ms: u64) {
        if !signing {
            return;
        }
        self.since_tick = true;
        self.since_message = true;
        let first = match self.run {
            Some((first, last)) if t_ms >= last && t_ms - last <= RUN_GAP_MS => first,
            _ => t_ms,
        };
        self.run = Some((first, t_ms));
    }

    /// The tick at `now_ms`: the start, a `signed` message while signing
    /// goes on, or the stop.
    pub fn tick(&mut self, now_ms: u64) -> Option<SignMessage> {
        let since_tick = std::mem::take(&mut self.since_tick);
        let Some(start) = self.started else {
            let long_enough = self.run.is_some_and(|(first, last)| last - first >= MIN_DURATION_MS);
            if !(since_tick && long_enough) {
                return None;
            }
            self.started = Some(now_ms);
            self.last_true = now_ms;
            self.since_message = false;
            return Some(SignMessage {
                signed: true,
                duration_ms: 0,
            });
        };
        if !self.since_message {
            return self.stop();
        }
        let elapsed = now_ms.saturating_sub(start);
        if since_tick && elapsed >= REGULAR_INTERVAL_MS {
            self.last_true = now_ms;
            self.since_message = false;
            return Some(SignMessage {
                signed: true,
                duration_ms: elapsed,
            });
        }
        if now_ms.saturating_sub(self.last_true) >= SIGNAL_TIMEOUT_MS {
            return self.stop();
        }
        None
    }

    /// Starts over (detection turned off): the stop message if signing had
    /// started.
    pub fn stop(&mut self) -> Option<SignMessage> {
        let started = self.started.is_some();
        *self = Self::default();
        started.then_some(SignMessage::STOP)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const START: SignMessage = SignMessage {
        signed: true,
        duration_ms: 0,
    };

    fn signed(duration_ms: u64) -> SignMessage {
        SignMessage {
            signed: true,
            duration_ms,
        }
    }

    /// Feeds frames every 100 ms from `from` to `to` (exclusive) with a tick
    /// after each one on a multiple of 500 ms; the messages with their times.
    fn run(a: &mut SigningAggregator, from: u64, to: u64, signing: impl Fn(u64) -> bool) -> Vec<(u64, SignMessage)> {
        let mut out = Vec::new();
        for t in (from..to).step_by(100) {
            a.push(signing(t), t);
            if t % TICK_MS == 0
                && let Some(m) = a.tick(t)
            {
                out.push((t, m));
            }
        }
        out
    }

    #[test]
    fn sign_detection_starts_after_half_a_second_of_signing() {
        let mut a = SigningAggregator::new();
        a.push(true, 1000);
        a.push(true, 1300);
        a.push(true, 1499);
        assert_eq!(a.tick(1499), None);
        a.push(true, 1500);
        assert!(!a.started());
        assert_eq!(a.tick(1510), Some(START));
        assert!(a.started());
        // Once started, more signing doesn't start it again.
        a.push(true, 1600);
        assert_eq!(a.tick(2010), None);
    }

    #[test]
    fn sign_detection_a_gap_starts_the_minimum_over() {
        let mut a = SigningAggregator::new();
        a.push(true, 0);
        a.push(true, 300);
        // 400 ms without a signing frame: the stretch starts again here.
        a.push(true, 700);
        a.push(true, 1000);
        assert_eq!(a.tick(1100), None);
        a.push(true, 1200);
        assert_eq!(a.tick(1250), Some(START));
        // Frames that aren't signing don't count.
        let mut a = SigningAggregator::new();
        assert!(run(&mut a, 0, 3000, |_| false).is_empty());
        // Nor a stretch that ended before the last tick.
        let mut a = SigningAggregator::new();
        a.push(true, 0);
        a.push(true, 300);
        assert_eq!(a.tick(400), None);
        a.push(true, 700);
        assert_eq!(a.tick(900), None);
        assert_eq!(a.tick(1400), None);
    }

    #[test]
    fn sign_detection_reports_regularly_from_two_seconds_and_stops() {
        let mut a = SigningAggregator::new();
        // Signing from 0 to 4.9 s.
        let msgs = run(&mut a, 0, 7000, |t| t < 5000);
        assert_eq!(
            msgs,
            vec![
                (500, START),
                // Nothing until 2 s after the start, then each tick.
                (2500, signed(2000)),
                (3000, signed(2500)),
                (3500, signed(3000)),
                (4000, signed(3500)),
                (4500, signed(4000)),
                // 4.6 to 4.9 s were signing: one more.
                (5000, signed(4500)),
                // The first tick with no signing since the last message.
                (5500, SignMessage::STOP),
            ]
        );
        assert!(!a.started());
    }

    #[test]
    fn sign_detection_stops_on_the_first_quiet_tick_after_the_start() {
        let mut a = SigningAggregator::new();
        let msgs = run(&mut a, 0, 3000, |t| t <= 500);
        assert_eq!(msgs, vec![(500, START), (1000, SignMessage::STOP)]);
    }

    #[test]
    fn sign_detection_times_out_without_a_signed_message() {
        let mut a = SigningAggregator::new();
        // Signing for a while after the start, then not; before 2 s there
        // are no regular messages, so it is the timeout that stops it.
        let msgs = run(&mut a, 0, 5000, |t| t <= 800);
        assert_eq!(msgs, vec![(500, START), (3500, SignMessage::STOP)]);
        // The same with ticks off the frame times.
        let mut a = SigningAggregator::new();
        for t in (0..=900).step_by(100) {
            a.push(true, t);
        }
        assert_eq!(a.tick(950), Some(START));
        a.push(true, 1000);
        a.push(true, 1100);
        for now in [1450, 1950, 2450, 2950, 3450] {
            assert_eq!(a.tick(now), None);
        }
        assert_eq!(a.tick(3950), Some(SignMessage::STOP));
    }

    #[test]
    fn sign_detection_starts_again_after_a_stop() {
        let mut a = SigningAggregator::new();
        let msgs = run(&mut a, 0, 10_000, |t| t < 3000 || (6000..9000).contains(&t));
        let starts: Vec<u64> = msgs.iter().filter(|(_, m)| *m == START).map(|(t, _)| *t).collect();
        let stops: Vec<u64> = msgs.iter().filter(|(_, m)| *m == SignMessage::STOP).map(|(t, _)| *t).collect();
        assert_eq!(starts, vec![500, 6500]);
        assert_eq!(stops, vec![3500, 9500]);
    }

    #[test]
    fn sign_detection_stop_sends_the_stop_only_when_started() {
        let mut a = SigningAggregator::new();
        assert_eq!(a.stop(), None);
        for t in [0, 250, 500] {
            a.push(true, t);
        }
        assert_eq!(a.tick(500), Some(START));
        assert_eq!(a.stop(), Some(SignMessage::STOP));
        assert!(!a.started());
        assert_eq!(a.tick(1000), None);
        // The stretch starts over too.
        a.push(true, 600);
        assert_eq!(a.tick(700), None);
    }

    #[test]
    fn sign_detection_hand_rule() {
        let person = |wrist: [f32; 3]| {
            let mut k = [[0f32; 3]; KEYPOINTS];
            k[LEFT_SHOULDER] = [0.6, 0.5, 0.9];
            k[RIGHT_SHOULDER] = [0.4, 0.5, 0.9];
            k[LEFT_ELBOW] = [0.65, 0.7, 0.9];
            k[LEFT_WRIST] = wrist;
            k[RIGHT_WRIST] = [0.4, 0.95, 0.9];
            k
        };
        // A wrist in front of the chest is up; one at the hips isn't, nor
        // one the model isn't sure of.
        let hands = raised_hands(&person([0.55, 0.6, 0.8]));
        let hand = hands[0].unwrap();
        assert!((hand.rel[0] - 0.25).abs() < 1e-5 && (hand.rel[1] - 0.5).abs() < 1e-5);
        // The hand is past the wrist, away from the elbow.
        assert!((hand.centre[0] - 0.51).abs() < 1e-5 && (hand.centre[1] - 0.56).abs() < 1e-5);
        assert!((hand.side - 0.16).abs() < 1e-5);
        assert!(hands[1].is_none());
        assert!(raised_hands(&person([0.55, 0.6, 0.1]))[0].is_none());
        // No shoulders: no person.
        let mut k = person([0.55, 0.6, 0.8]);
        k[LEFT_SHOULDER][2] = 0.1;
        assert_eq!(raised_hands(&k), [None, None]);

        let history = |points: &[(Option<[f32; 2]>, Option<f32>)]| -> VecDeque<Sample> {
            points
                .iter()
                .enumerate()
                .map(|(i, &(p, c))| Sample {
                    t_ms: i as u64 * 100,
                    wrists: [p, None],
                    changes: [c, None],
                })
                .collect()
        };
        let at = |p: [f32; 2]| (Some(p), Some(1.0));
        // A hand held still (keypoint jitter, camera noise) isn't signing; a
        // moving one is; too few sightings aren't judged.
        let still = history(&[at([0.2, 0.3]), at([0.22, 0.31]), at([0.21, 0.29]), at([0.2, 0.3])]);
        assert!(!moving(&still, 0) && !shaping(&still, 0));
        let signing = history(&[at([0.2, 0.3]), at([0.4, 0.1]), at([0.1, 0.4]), at([0.3, 0.2])]);
        assert!(moving(&signing, 0));
        let brief = history(&[(None, None), (None, None), at([0.2, 0.3]), at([0.6, 0.1])]);
        assert!(!moving(&brief, 0));
        // A hand in place that changes shape is signing.
        let p = Some([0.2, 0.3]);
        let spelling = history(&[(p, None), (p, Some(6.0)), (p, Some(3.5)), (p, Some(5.0))]);
        assert!(!moving(&spelling, 0) && shaping(&spelling, 0));
    }

    #[test]
    fn sign_detection_hand_pictures() {
        // A 320 x 240 grey frame with a bright square ("a hand") at
        // (100..140, 60..100).
        let (w, h) = (320, 240);
        let frame = |dx: usize| {
            let mut f = vec![128u8; w * h * 3 / 2];
            for y in 60..100 {
                for x in 100 + dx..140 + dx {
                    f[y * w + x] = 220;
                }
            }
            f
        };
        // The model's picture: the frame letterboxed to 320 x 320 (40 above).
        let centre = [120.0 / 320.0, (80.0 + 40.0) / 320.0];
        let side = 64.0 / 320.0;
        let a = Patch::new(&frame(0), w, h, centre, side).unwrap();
        // The square's middle cells are brighter than the mean, the corners
        // darker.
        assert!(a.0[3 * PATCH + 3] > 20.0 && a.0[0] < -10.0);
        // The same picture again (or one brighter all over) hasn't changed;
        // the square moved has.
        assert!(a.change(&Patch::new(&frame(0), w, h, centre, side).unwrap()) < 1e-3);
        let mut brighter = frame(0);
        brighter[..w * h].iter_mut().for_each(|v| *v += 10);
        assert!(a.change(&Patch::new(&brighter, w, h, centre, side).unwrap()) < 1e-3);
        assert!(a.change(&Patch::new(&frame(16), w, h, centre, side).unwrap()) > MIN_SHAPE_CHANGE);
        // Sticking out of the frame, it is moved in; too small or too large,
        // there is none.
        assert!(Patch::new(&frame(0), w, h, [0.0, 0.0], side).is_some());
        assert!(Patch::new(&frame(0), w, h, centre, 0.01).is_none());
        assert!(Patch::new(&frame(0), w, h, centre, 0.9).is_none());
    }

    #[test]
    fn sign_detection_letterboxes_the_frame() {
        // A 320 x 180 frame, white on the left half and black on the right.
        let (w, h) = (320, 180);
        let mut f = vec![128u8; w * h * 3 / 2];
        for y in 0..h {
            for x in 0..w {
                f[y * w + x] = if x < w / 2 { 235 } else { 16 };
            }
        }
        let rgb = model_input(&f, w, h);
        let at = |x: usize, y: usize| rgb[(y * INPUT + x) * 3];
        // Letterboxed: 192 x 108 in the middle, black above and below.
        assert_eq!(at(10, 10), 0);
        assert!(at(10, 42) >= 250 && at(10, 96) >= 250 && at(10, 149) >= 250);
        assert_eq!(at(180, 96), 0);
        assert_eq!(at(10, 180), 0);
    }

    /// The model for the tests that need it: the file at
    /// $OST_SIGN_DETECTION_MODEL (it isn't in the repository; OST downloads
    /// it at run time). None, with a note, when that isn't set.
    fn detector() -> Option<SignDetector> {
        let Some(path) = std::env::var_os("OST_SIGN_DETECTION_MODEL") else {
            eprintln!(
                "skipped: set OST_SIGN_DETECTION_MODEL to the path of {MODEL_FILE} \
                 (MoveNet SinglePose Lightning; see vfx/NOTICE.md)"
            );
            return None;
        };
        let onnx = std::fs::read(&path).unwrap_or_else(|e| panic!("OST_SIGN_DETECTION_MODEL={path:?}: {e}"));
        Some(SignDetector::new(&onnx).unwrap())
    }

    #[test]
    fn sign_detection_an_empty_picture_is_not_signing() {
        let Some(mut d) = detector() else { return };
        let (w, h) = (640u32, 360u32);
        let n = (w * h) as usize;
        // A grey wall, then noise.
        let mut f = vec![128u8; n * 3 / 2];
        for t in 0..20 {
            assert!(!d.push_frame(&f, w, h, t * 100));
        }
        let mut seed = 1u32;
        for t in 20..40 {
            for v in &mut f[..n] {
                seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                *v = (seed >> 24) as u8;
            }
            assert!(!d.push_frame(&f, w, h, t * 100));
        }
        // A frame shorter than its size says isn't looked at.
        assert!(!d.push_frame(&f[..100], w, h, 5000));
    }

    #[test]
    fn sign_detection_evaluates_ten_times_a_second() {
        let Some(mut d) = detector() else { return };
        let f = vec![128u8; 320 * 180 * 3 / 2];
        let mut evaluated = 0;
        for t in (0..1000).step_by(33) {
            let due = d.next_eval_ms();
            d.push_frame(&f, 320, 180, t);
            evaluated += usize::from(d.next_eval_ms() != due);
        }
        // A 30 fps camera: 31 frames in the second, 10 evaluated.
        assert_eq!(evaluated, 10);
        // After a pause the next frame is evaluated, but not the one after.
        let due = d.next_eval_ms();
        d.push_frame(&f, 320, 180, 5000);
        assert!(d.next_eval_ms() > due);
        let due = d.next_eval_ms();
        d.push_frame(&f, 320, 180, 5033);
        assert_eq!(d.next_eval_ms(), due);
        // The clock going back is evaluated at once.
        d.push_frame(&f, 320, 180, 100);
        assert_eq!(d.next_eval_ms(), 200);
    }
}
