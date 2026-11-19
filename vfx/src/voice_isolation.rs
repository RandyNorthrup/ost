//! Voice isolation: Teams' noise suppression mode that keeps only your own
//! voice. Teams conditions a proprietary model on your voice profile; OST does
//! the same job with an open speaker-verification model (3D-Speaker CAM++,
//! VoxCeleb, Apache-2.0, run with tract): while someone is talking, a worker
//! thread compares the last second or so of speech with your voice profile and,
//! when it is somebody else, the microphone is faded to silence until you talk
//! again. Noise is left alone (WebRTC's noise suppression runs before this).
//!
//! The model wants Kaldi fbank features (80 log mel bins, 25 ms Povey windows
//! every 10 ms, samples in −1..1, no dither) with the mean of each bin over the
//! utterance taken away (its metadata: `normalize_samples=1`,
//! `feature_normalize_type=global-mean`, as sherpa-onnx and 3D-Speaker's own
//! `FBank(mean_nor=True)` use it), and gives a 512-value embedding.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex, OnceLock, mpsc};

use rustfft::{Fft, FftPlanner, num_complex::Complex};
use tract_onnx::prelude::*;

/// The model's file name. It isn't shipped with OST: like Teams with its own
/// voice isolation model, OST downloads it on first need (the engine's
/// calling::voice_isolation) and hands it over with [`load_model`].
pub const MODEL_FILE: &str = "3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx";

/// The model's sample rate.
pub const SAMPLE_RATE: u32 = 16_000;
/// Mel bins per feature frame.
pub const MEL_BINS: usize = 80;
/// The embedding's length.
pub const EMBEDDING_DIM: usize = 512;

// Kaldi fbank options (torchaudio.compliance.kaldi.fbank defaults, which
// 3D-Speaker trained with): 25 ms frames every 10 ms, snip edges, remove DC,
// pre-emphasis 0.97, Povey window, 512-point FFT, power spectrum, 80 bins from
// 20 Hz to Nyquist, natural log floored at f32::EPSILON.
const FRAME_LEN: usize = 400;
const FRAME_SHIFT: usize = 160;
const FFT_LEN: usize = 512;
const PREEMPHASIS: f64 = 0.97;
const LOW_FREQ: f64 = 20.0;
const HIGH_FREQ: f64 = 8000.0;

/// Kaldi's mel scale.
fn mel(f: f64) -> f64 {
    1127.0 * (1.0 + f / 700.0).ln()
}

/// Kaldi fbank (see the constants above), without mean normalisation.
pub struct Fbank {
    window: Vec<f64>,
    /// Each bin's first FFT bin and triangle weights.
    banks: Vec<(usize, Vec<f64>)>,
    fft: Arc<dyn Fft<f64>>,
}

impl Default for Fbank {
    fn default() -> Self {
        Self::new()
    }
}

impl Fbank {
    pub fn new() -> Self {
        let window = (0..FRAME_LEN)
            .map(|i| {
                (0.5 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / (FRAME_LEN - 1) as f64).cos())
                    .powf(0.85)
            })
            .collect();
        let (lo, hi) = (mel(LOW_FREQ), mel(HIGH_FREQ));
        let delta = (hi - lo) / (MEL_BINS + 1) as f64;
        let bin_hz = SAMPLE_RATE as f64 / FFT_LEN as f64;
        let banks = (0..MEL_BINS)
            .map(|b| {
                let (l, c, r) = (
                    lo + b as f64 * delta,
                    lo + (b + 1) as f64 * delta,
                    lo + (b + 2) as f64 * delta,
                );
                let w: Vec<(usize, f64)> = (0..FFT_LEN / 2)
                    .filter_map(|i| {
                        let m = mel(i as f64 * bin_hz);
                        (m > l && m < r).then(|| {
                            (
                                i,
                                if m <= c {
                                    (m - l) / (c - l)
                                } else {
                                    (r - m) / (r - c)
                                },
                            )
                        })
                    })
                    .collect();
                (
                    w.first().map_or(0, |p| p.0),
                    w.into_iter().map(|p| p.1).collect(),
                )
            })
            .collect();
        Self {
            window,
            banks,
            fft: FftPlanner::new().plan_fft_forward(FFT_LEN),
        }
    }

    /// Frames in `n` samples (Kaldi's snip_edges).
    pub fn frames(n: usize) -> usize {
        if n < FRAME_LEN {
            0
        } else {
            1 + (n - FRAME_LEN) / FRAME_SHIFT
        }
    }

    /// 16 kHz samples in −1..1 to `frames(len)` rows of MEL_BINS log mel
    /// energies, row after row.
    pub fn compute(&self, pcm: &[f32]) -> Vec<f32> {
        let n = Self::frames(pcm.len());
        let mut out = Vec::with_capacity(n * MEL_BINS);
        let mut frame = [0f64; FRAME_LEN];
        let mut buf = vec![Complex::new(0.0, 0.0); FFT_LEN];
        let mut power = [0f64; FFT_LEN / 2 + 1];
        for t in 0..n {
            let src = &pcm[t * FRAME_SHIFT..t * FRAME_SHIFT + FRAME_LEN];
            let mean = src.iter().map(|&s| s as f64).sum::<f64>() / FRAME_LEN as f64;
            for (d, &s) in frame.iter_mut().zip(src) {
                *d = s as f64 - mean;
            }
            for i in (1..FRAME_LEN).rev() {
                frame[i] -= PREEMPHASIS * frame[i - 1];
            }
            frame[0] -= PREEMPHASIS * frame[0];
            for (i, b) in buf.iter_mut().enumerate() {
                *b = Complex::new(
                    if i < FRAME_LEN {
                        frame[i] * self.window[i]
                    } else {
                        0.0
                    },
                    0.0,
                );
            }
            self.fft.process(&mut buf);
            for (p, b) in power.iter_mut().zip(&buf) {
                *p = b.norm_sqr();
            }
            for (start, w) in &self.banks {
                let e: f64 = w.iter().zip(&power[*start..]).map(|(w, p)| w * p).sum();
                out.push(e.max(f32::EPSILON as f64).ln() as f32);
            }
        }
        out
    }
}

fn fbank() -> &'static Fbank {
    static F: OnceLock<Fbank> = OnceLock::new();
    F.get_or_init(Fbank::new)
}

/// The CAM++ speaker embedding model.
#[derive(Clone)]
pub struct SpeakerEmbedder {
    model: Arc<TypedRunnableModel>,
}

/// The shortest speech the embedder takes (it needs a few frames).
const MIN_EMBED_SAMPLES: usize = SAMPLE_RATE as usize / 4;

/// The process's embedder, once [`load_model`] has run.
static SHARED: Mutex<Option<SpeakerEmbedder>> = Mutex::new(None);

/// Loads the model (the ONNX file's bytes) for the process: from then on
/// [`SpeakerEmbedder::shared`], [`profile_embedding`] and [`Isolator::new`]
/// work. Takes about a second (optimising it).
pub fn load_model(onnx: &[u8]) -> anyhow::Result<()> {
    let e = SpeakerEmbedder::new(onnx)?;
    *SHARED.lock().unwrap_or_else(|e| e.into_inner()) = Some(e);
    Ok(())
}

/// The model is loaded.
pub fn model_loaded() -> bool {
    SHARED.lock().unwrap_or_else(|e| e.into_inner()).is_some()
}

impl SpeakerEmbedder {
    /// Loads and optimises the model from its ONNX bytes (about a second):
    /// [`load_model`] keeps one for the process.
    pub fn new(onnx: &[u8]) -> anyhow::Result<Self> {
        let model = tract_onnx::onnx().model_for_read(&mut &onnx[..])?;
        let t = model.symbols.sym("T");
        let model = model
            .with_input_fact(
                0,
                f32::fact([1.to_dim(), t.to_dim(), MEL_BINS.to_dim()]).into(),
            )?
            .into_optimized()?
            .into_runnable()?;
        Ok(Self { model })
    }

    /// The process's embedder (an error until [`load_model`] has run).
    pub fn shared() -> anyhow::Result<Self> {
        SHARED
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .ok_or_else(|| anyhow::anyhow!("the voice isolation model isn't loaded"))
    }

    /// L2-normalised embedding of 16 kHz mono speech in [-1, 1].
    pub fn embed(&self, pcm16k: &[f32]) -> anyhow::Result<Vec<f32>> {
        anyhow::ensure!(
            pcm16k.len() >= MIN_EMBED_SAMPLES,
            "too little audio to embed ({} samples)",
            pcm16k.len()
        );
        let mut feats = fbank().compute(pcm16k);
        let frames = feats.len() / MEL_BINS;
        // global-mean: each bin's mean over the utterance taken away.
        for b in 0..MEL_BINS {
            let mean = (0..frames).map(|t| feats[t * MEL_BINS + b]).sum::<f32>() / frames as f32;
            for t in 0..frames {
                feats[t * MEL_BINS + b] -= mean;
            }
        }
        let input: Tensor =
            tract_ndarray::Array3::from_shape_vec((1, frames, MEL_BINS), feats)?.into();
        let out = self.model.run(tvec!(input.into()))?;
        let mut e = out[0]
            .to_plain_array_view::<f32>()?
            .iter()
            .copied()
            .collect::<Vec<f32>>();
        let norm = e.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-12);
        e.iter_mut().for_each(|v| *v /= norm);
        Ok(e)
    }
}

pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let dot: f32 = a.iter().zip(b).map(|(x, y)| x * y).sum();
    let na = a.iter().map(|v| v * v).sum::<f32>().sqrt();
    let nb = b.iter().map(|v| v * v).sum::<f32>().sqrt();
    if na == 0.0 || nb == 0.0 {
        0.0
    } else {
        dot / (na * nb)
    }
}

/// A WAV's samples as mono f32 in −1..1 and its rate (PCM 16-bit, or 32-bit
/// float; channels mixed down).
pub fn read_wav(wav: &[u8]) -> anyhow::Result<(Vec<f32>, u32)> {
    anyhow::ensure!(
        wav.len() >= 12 && &wav[0..4] == b"RIFF" && &wav[8..12] == b"WAVE",
        "not a WAV file"
    );
    let u16_at = |p: usize| u16::from_le_bytes([wav[p], wav[p + 1]]);
    let u32_at = |p: usize| u32::from_le_bytes([wav[p], wav[p + 1], wav[p + 2], wav[p + 3]]);
    let (mut fmt, mut pos) = (None, 12);
    while pos + 8 <= wav.len() {
        let id = &wav[pos..pos + 4];
        let size = (u32_at(pos + 4) as usize).min(wav.len() - pos - 8);
        let body = pos + 8;
        if id == b"fmt " && size >= 16 {
            let mut tag = u16_at(body);
            if tag == 0xFFFE && size >= 26 {
                tag = u16_at(body + 24); // WAVE_FORMAT_EXTENSIBLE: the sub-format's first two bytes.
            }
            fmt = Some((
                tag,
                u16_at(body + 2).max(1) as usize,
                u32_at(body + 4),
                u16_at(body + 14),
            ));
        } else if id == b"data" {
            let (tag, channels, rate, bits) =
                fmt.ok_or_else(|| anyhow::anyhow!("WAV data before its format"))?;
            let data = &wav[body..body + size];
            let samples: Vec<f32> = match (tag, bits) {
                (1, 16) => data
                    .chunks_exact(2)
                    .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
                    .collect(),
                (3, 32) => data
                    .chunks_exact(4)
                    .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
                    .collect(),
                _ => anyhow::bail!("unsupported WAV format {tag} with {bits} bits"),
            };
            let mono = samples
                .chunks_exact(channels)
                .map(|c| c.iter().sum::<f32>() / channels as f32)
                .collect();
            return Ok((mono, rate));
        }
        pos = body + size + (size & 1);
    }
    anyhow::bail!("WAV without data")
}

/// Resamples to 16 kHz: a windowed-sinc low-pass below 8 kHz when coming down,
/// then linear interpolation (for 48 kHz that is exact decimation by three).
struct Resampler {
    /// Input samples per output sample.
    step: f64,
    taps: Vec<f32>,
    /// The last `taps.len() - 1` input samples.
    history: Vec<f32>,
    /// Filtered input not yet consumed.
    filtered: Vec<f32>,
    /// The next output's position in `filtered`.
    pos: f64,
}

impl Resampler {
    fn new(rate: u32) -> Self {
        let step = rate as f64 / SAMPLE_RATE as f64;
        let taps = if rate > SAMPLE_RATE {
            // Cut-off at 7.6 kHz, ~16 output samples of support.
            let fc = 7600.0 / rate as f64;
            let n = (step * 16.0).round() as usize * 2 + 1;
            let mid = (n / 2) as f64;
            let mut t: Vec<f64> = (0..n)
                .map(|i| {
                    let x = i as f64 - mid;
                    let sinc = if x == 0.0 {
                        2.0 * fc
                    } else {
                        (2.0 * std::f64::consts::PI * fc * x).sin() / (std::f64::consts::PI * x)
                    };
                    let blackman = 0.42
                        - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / (n - 1) as f64).cos()
                        + 0.08 * (4.0 * std::f64::consts::PI * i as f64 / (n - 1) as f64).cos();
                    sinc * blackman
                })
                .collect();
            let sum: f64 = t.iter().sum();
            t.iter_mut().for_each(|v| *v /= sum);
            t.into_iter().map(|v| v as f32).collect()
        } else {
            vec![1.0]
        };
        Self {
            step,
            history: vec![0.0; taps.len() - 1],
            taps,
            filtered: Vec::new(),
            pos: 0.0,
        }
    }

    /// Appends `input`'s 16 kHz samples to `out`.
    fn push(&mut self, input: impl Iterator<Item = f32>, out: &mut Vec<f32>) {
        let n = self.taps.len();
        for s in input {
            self.history.push(s);
            let w = &self.history[self.history.len() - n..];
            self.filtered.push(
                w.iter()
                    .zip(self.taps.iter().rev())
                    .map(|(a, b)| a * b)
                    .sum(),
            );
        }
        let keep = self.history.len() - (n - 1);
        self.history.drain(..keep);
        while self.pos + 1.0 < self.filtered.len() as f64 {
            let i = self.pos as usize;
            let f = (self.pos - i as f64) as f32;
            out.push(self.filtered[i] * (1.0 - f) + self.filtered[i + 1] * f);
            self.pos += self.step;
        }
        let used = (self.pos as usize).min(self.filtered.len());
        self.filtered.drain(..used);
        self.pos -= used as f64;
    }
}

/// Energy-VAD trim of a recording: keeps the 20 ms frames within
/// `PROFILE_VAD_RANGE_DB` of the loud (95th percentile) frames and above
/// −60 dBFS.
fn trim_silence(pcm: &[f32]) -> Vec<f32> {
    const FRAME: usize = 320;
    const PROFILE_VAD_RANGE_DB: f32 = 35.0;
    let db: Vec<f32> = pcm
        .chunks_exact(FRAME)
        .map(|f| 10.0 * (f.iter().map(|s| s * s).sum::<f32>() / FRAME as f32 + 1e-12).log10())
        .collect();
    if db.is_empty() {
        return Vec::new();
    }
    let mut sorted = db.clone();
    sorted.sort_by(f32::total_cmp);
    let loud = sorted[(sorted.len() * 95 / 100).min(sorted.len() - 1)];
    let gate = (loud - PROFILE_VAD_RANGE_DB).max(-60.0);
    pcm.chunks_exact(FRAME)
        .zip(&db)
        .filter(|(_, d)| **d > gate)
        .flat_map(|(f, _)| f.iter().copied())
        .collect()
}

/// The embedding of a voice profile's recording: a 16 kHz 16-bit mono WAV
/// (Teams' voice profile RawData); silence trimmed by an energy VAD before
/// embedding. Other rates and channel counts are converted.
pub fn profile_embedding(wav: &[u8]) -> anyhow::Result<Vec<f32>> {
    let (pcm, rate) = read_wav(wav)?;
    let pcm = if rate == SAMPLE_RATE {
        pcm
    } else {
        let mut out = Vec::new();
        Resampler::new(rate).push(pcm.into_iter(), &mut out);
        out
    };
    let speech = trim_silence(&pcm);
    anyhow::ensure!(
        speech.len() >= SAMPLE_RATE as usize,
        "the voice profile has under a second of speech"
    );
    SpeakerEmbedder::shared()?.embed(&speech)
}

// ---------------------------------------------------------------- Isolator

/// The longest speech compared with the profile (s). Longer is surer, but
/// it also takes longer to notice that someone else took over.
const WINDOW_MAX_S: f32 = 1.5;
/// No decision on less speech than this (s): until then a new talk spurt is
/// passed (the cost is the start of another person's speech leaking through).
const WINDOW_MIN_S: f32 = 0.5;
/// The fast-restore check while suppressing: the newest 0.5 s alone.
const SHORT_WINDOW_S: f32 = 0.5;
/// How often speech is compared with the profile: every 160 ms of speech...
const DECISION_EVERY: usize = SAMPLE_RATE as usize * 16 / 100;
/// ...or every 480 ms once a full window has given a clear answer (more than
/// SETTLED_MARGIN from the threshold): a 1.5 s embedding takes ~150 ms of
/// one core (release build), so checking a settled talker three times less
/// often keeps the cost to about a third of a core while someone talks.
const DECISION_EVERY_SETTLED: usize = SAMPLE_RATE as usize * 48 / 100;
const SETTLED_MARGIN: f32 = 0.15;

// Thresholds on the cosine similarity with the profile. Measured with this
// model on Piper TTS voices: 12 LibriTTS-R speakers (6 female, 6 male) plus
// lessac and ryan; profiles from ~13-17 s of trimmed speech; windows of
// trimmed speech every 160 ms. The owner's scores (min/mean) against their own
// profile, and everyone else's (max, p95, mean) against the owner's profile,
// for two owners (LibriTTS-R speaker 100, female, as in testdata; lessac):
//
//   window   owner        min   mean | others  max   p95   mean
//   0.5 s    LibriTTS 100 0.34  0.52 |         0.48  0.39  0.17
//            lessac       0.38  0.56 |         0.33  0.24  0.10
//   0.75 s   LibriTTS 100 0.52  0.62 |         0.51  0.46  0.21
//            lessac       0.48  0.66 |         0.29  0.23  0.10
//   1.0 s    LibriTTS 100 0.56  0.69 |         0.57  0.50  0.22
//            lessac       0.57  0.71 |         0.29  0.21  0.09
//   1.5 s    LibriTTS 100 0.70  0.77 |         0.59  0.53  0.25
//            lessac       0.63  0.78 |         0.27  0.20  0.09
//
// (The LibriTTS-R voices are all fine-tuned from one model and are much more
// alike than real people: its same-gender pairs score up to 0.59. Other-gender
// voices stay under 0.33.) Real microphones bring the owner's scores down (a
// profile recorded elsewhere, on another device), and taking the owner for
// someone else is far worse than letting someone else through, so the
// thresholds sit well under the owner's minimum, near the mean of other
// voices: 0.22 for 0.5 s of speech rising to 0.30 for 1.5 s. Similar voices
// get through.
const SUPPRESS_BELOW_SHORT: f32 = 0.22;
const SUPPRESS_BELOW_LONG: f32 = 0.30;
/// Once suppressing, the voice must score this much above the threshold to be
/// let through again, so a borderline window does not flicker the gain.
const RESTORE_MARGIN: f32 = 0.08;

/// The threshold for `len_s` seconds of speech.
fn suppress_below(len_s: f32) -> f32 {
    let t = ((len_s - WINDOW_MIN_S) / (WINDOW_MAX_S - WINDOW_MIN_S)).clamp(0.0, 1.0);
    SUPPRESS_BELOW_SHORT + (SUPPRESS_BELOW_LONG - SUPPRESS_BELOW_SHORT) * t
}

/// The level suppressed speech is brought to.
const FLOOR_DB: f32 = -60.0;
/// Fade to the floor over 20 ms; back to full level over 5 ms.
const ATTACK_MS: f32 = 20.0;
const RELEASE_MS: f32 = 5.0;

// The speech detector, on each 10 ms frame. WebRTC's noise suppression has
// already run, so the floor is low and steady.
/// Speech is this far above the tracked noise floor...
const VAD_SNR_DB: f32 = 12.0;
/// ...and above this level.
const VAD_MIN_DBFS: f32 = -50.0;
/// Quiet frames crossing zero this often (per second) are hiss, not voice.
const VAD_HISS_ZC_PER_S: f32 = 5000.0;
/// Loud enough to be speech whatever its zero crossings (fricatives).
const VAD_LOUD_SNR_DB: f32 = 25.0;
/// Speech goes on for this many frames after the last voiced one.
const VAD_HANGOVER_FRAMES: u32 = 15;
/// This many frames without speech end a talk spurt: the next one starts
/// over (passed until it is judged), so a reply right after someone else
/// is not held back by their audio.
const SPURT_GAP_FRAMES: u32 = 35;

struct Vad {
    floor_db: f32,
    hangover: u32,
}

impl Vad {
    fn update(&mut self, frame: &[i16], rate: u32) -> bool {
        let n = frame.len().max(1) as f32;
        let energy = frame
            .iter()
            .map(|&s| (s as f32 / 32768.0).powi(2))
            .sum::<f32>()
            / n;
        let db = 10.0 * (energy + 1e-12).log10();
        let crossings = frame
            .windows(2)
            .filter(|w| (w[0] >= 0) != (w[1] >= 0))
            .count() as f32;
        let zc_per_s = crossings * rate as f32 / n;
        // The floor follows quiet frames down quickly and creeps up 3 dB/s.
        if db < self.floor_db {
            self.floor_db += 0.3 * (db - self.floor_db);
        } else {
            self.floor_db += 0.03;
        }
        self.floor_db = self.floor_db.clamp(-90.0, -35.0);
        let above = db > (self.floor_db + VAD_SNR_DB).max(VAD_MIN_DBFS);
        let voiced =
            above && (zc_per_s < VAD_HISS_ZC_PER_S || db > self.floor_db + VAD_LOUD_SNR_DB);
        if voiced {
            self.hangover = VAD_HANGOVER_FRAMES;
        } else {
            self.hangover = self.hangover.saturating_sub(1);
        }
        voiced || self.hangover > 0
    }
}

/// What the isolator is doing.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct IsolatorStats {
    /// The newest similarity of the speech with the profile.
    pub similarity: Option<f32>,
    /// Whether someone is talking.
    pub speech: bool,
    /// Whether the speech is being faded out (someone else's voice).
    pub suppressing: bool,
    /// 10 ms frames faded out so far.
    pub frames_suppressed: u64,
    /// Comparisons made so far.
    pub decisions: u64,
}

struct Request {
    spurt: u64,
    pcm: Vec<f32>,
    short: bool,
}

struct Decision {
    spurt: u64,
    len_s: f32,
    similarity: Option<f32>,
    short: Option<f32>,
    pcm: Vec<f32>,
}

/// Keeps only the profile owner's voice in a call's microphone audio.
pub struct Isolator {
    rate: u32,
    resampler: Resampler,
    scratch: Vec<f32>,
    /// The current talk spurt's newest speech, 16 kHz.
    ring: VecDeque<f32>,
    spurt: u64,
    spurt_len: usize,
    since_request: usize,
    /// The last answer was clear: check less often.
    settled: bool,
    quiet_frames: u32,
    vad: Vad,
    stats: IsolatorStats,
    gain: f32,
    attack: f32,
    release: f32,
    floor: f32,
    requests: mpsc::SyncSender<Request>,
    decisions: mpsc::Receiver<Decision>,
    spare: Option<Vec<f32>>,
}

impl Isolator {
    /// `profile`: the user's embedding; `rate`: the call's capture rate
    /// (48000 in OST), frames of 10 ms.
    pub fn new(profile: Vec<f32>, rate: u32) -> anyhow::Result<Self> {
        anyhow::ensure!(
            profile.len() == EMBEDDING_DIM,
            "a voice profile embedding has {EMBEDDING_DIM} values"
        );
        anyhow::ensure!(rate >= 8000, "unsupported rate {rate}");
        let embedder = SpeakerEmbedder::shared()?;
        let (requests, worker_rx) = mpsc::sync_channel::<Request>(1);
        let (worker_tx, decisions) = mpsc::channel();
        std::thread::Builder::new()
            .name("voice-isolation".into())
            .spawn(move || {
                let short_len = (SHORT_WINDOW_S * SAMPLE_RATE as f32) as usize;
                while let Ok(r) = worker_rx.recv() {
                    let similarity = embedder.embed(&r.pcm).ok().map(|e| cosine(&e, &profile));
                    let short = (r.short && r.pcm.len() >= 2 * short_len)
                        .then(|| {
                            embedder
                                .embed(&r.pcm[r.pcm.len() - short_len..])
                                .ok()
                                .map(|e| cosine(&e, &profile))
                        })
                        .flatten();
                    let len_s = r.pcm.len() as f32 / SAMPLE_RATE as f32;
                    if worker_tx
                        .send(Decision {
                            spurt: r.spurt,
                            len_s,
                            similarity,
                            short,
                            pcm: r.pcm,
                        })
                        .is_err()
                    {
                        break;
                    }
                }
            })?;
        let per_ms = rate as f32 / 1000.0;
        let floor = 10f32.powf(FLOOR_DB / 20.0);
        Ok(Self {
            rate,
            resampler: Resampler::new(rate),
            scratch: Vec::new(),
            ring: VecDeque::with_capacity((WINDOW_MAX_S * SAMPLE_RATE as f32) as usize + 1024),
            spurt: 0,
            spurt_len: 0,
            since_request: 0,
            settled: false,
            quiet_frames: SPURT_GAP_FRAMES,
            vad: Vad {
                floor_db: -70.0,
                hangover: 0,
            },
            stats: IsolatorStats::default(),
            gain: 1.0,
            attack: floor.powf(1.0 / (ATTACK_MS * per_ms)),
            release: (1.0 / floor).powf(1.0 / (RELEASE_MS * per_ms)),
            floor,
            requests,
            decisions,
            spare: None,
        })
    }

    pub fn stats(&self) -> IsolatorStats {
        self.stats
    }

    /// One 10 ms mono i16 frame, processed in place; adds no latency (the
    /// decision for a frame uses the speech before it).
    pub fn process(&mut self, frame: &mut [i16]) {
        let speech = self.vad.update(frame, self.rate);
        self.stats.speech = speech;
        self.scratch.clear();
        self.resampler
            .push(frame.iter().map(|&s| s as f32 / 32768.0), &mut self.scratch);
        if speech {
            if self.quiet_frames >= SPURT_GAP_FRAMES {
                // A new talk spurt: judged afresh, passed until then.
                self.spurt += 1;
                self.spurt_len = 0;
                self.since_request = 0;
                self.settled = false;
                self.ring.clear();
                self.stats.suppressing = false;
                self.stats.similarity = None;
            }
            self.quiet_frames = 0;
            let cap = (WINDOW_MAX_S * SAMPLE_RATE as f32) as usize;
            for &s in &self.scratch {
                if self.ring.len() == cap {
                    self.ring.pop_front();
                }
                self.ring.push_back(s);
            }
            self.spurt_len += self.scratch.len();
            self.since_request += self.scratch.len();
            let every = if self.settled {
                DECISION_EVERY_SETTLED
            } else {
                DECISION_EVERY
            };
            if self.since_request >= every
                && self.spurt_len >= (WINDOW_MIN_S * SAMPLE_RATE as f32) as usize
            {
                let mut pcm = self.spare.take().unwrap_or_default();
                pcm.clear();
                pcm.extend(self.ring.iter());
                let short = self.stats.suppressing;
                match self.requests.try_send(Request {
                    spurt: self.spurt,
                    pcm,
                    short,
                }) {
                    Ok(()) => self.since_request = 0,
                    // Busy: try again next frame.
                    Err(mpsc::TrySendError::Full(r)) | Err(mpsc::TrySendError::Disconnected(r)) => {
                        self.spare = Some(r.pcm)
                    }
                }
            }
        } else {
            self.quiet_frames = self.quiet_frames.saturating_add(1);
        }
        while let Ok(d) = self.decisions.try_recv() {
            if d.spurt == self.spurt {
                self.decide(&d);
            }
            self.spare = Some(d.pcm);
        }

        let target = if self.stats.suppressing && speech {
            self.floor
        } else {
            1.0
        };
        if self.stats.suppressing && speech {
            self.stats.frames_suppressed += 1;
        }
        if target == 1.0 && self.gain == 1.0 {
            return;
        }
        for s in frame.iter_mut() {
            self.gain = if self.gain > target {
                (self.gain * self.attack).max(target)
            } else {
                (self.gain * self.release).min(target)
            };
            *s = (*s as f32 * self.gain).round() as i16;
        }
    }

    fn decide(&mut self, d: &Decision) {
        let Some(sim) = d.similarity else {
            // The model failed: never hold the user back on that.
            self.stats.suppressing = false;
            return;
        };
        self.stats.decisions += 1;
        self.stats.similarity = Some(sim);
        let threshold = suppress_below(d.len_s);
        self.settled = d.len_s >= WINDOW_MAX_S - 0.01 && (sim - threshold).abs() > SETTLED_MARGIN;
        if self.stats.suppressing {
            let short_back = d
                .short
                .is_some_and(|s| s > suppress_below(SHORT_WINDOW_S) + RESTORE_MARGIN);
            if sim > threshold + RESTORE_MARGIN || short_back {
                self.stats.suppressing = false;
            }
        } else if sim < threshold {
            self.stats.suppressing = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    const PROFILE_WAV: &[u8] = include_bytes!("../testdata/a_profile.wav");
    const AB_WAV: &[u8] = include_bytes!("../testdata/ab_alternating.wav");
    /// ab_alternating.wav's turns (speaker, first sample, end), 16 kHz.
    const TURNS: [(char, usize, usize); 4] = [
        ('A', 0, 60001),
        ('B', 71201, 128973),
        ('A', 140173, 200545),
        ('B', 211745, 272860),
    ];

    fn ab() -> Vec<f32> {
        read_wav(AB_WAV).unwrap().0
    }

    /// The model for the tests that need it: the file at
    /// $OST_VOICE_ISOLATION_MODEL (it isn't in the repository; OST downloads
    /// it at run time). False, with a note, when that isn't set.
    fn model() -> bool {
        static LOADED: OnceLock<bool> = OnceLock::new();
        let loaded = *LOADED.get_or_init(|| {
            let Some(path) = std::env::var_os("OST_VOICE_ISOLATION_MODEL") else {
                return false;
            };
            let onnx = std::fs::read(&path)
                .unwrap_or_else(|e| panic!("OST_VOICE_ISOLATION_MODEL={path:?}: {e}"));
            load_model(&onnx).unwrap();
            true
        });
        if !loaded {
            eprintln!(
                "skipped: set OST_VOICE_ISOLATION_MODEL to the path of {MODEL_FILE} \
                 (sherpa-onnx's speaker-recongition-models release; see vfx/NOTICE.md)"
            );
        }
        loaded
    }

    #[test]
    fn voice_isolation_fbank_matches_kaldi() {
        // Values from a NumPy port of torchaudio.compliance.kaldi.fbank with
        // the same options.
        let pcm: Vec<f32> = (0..16000)
            .map(|n| {
                let t = n as f64 / 16000.0;
                let tau = 2.0 * std::f64::consts::PI;
                (0.3 * (tau * 440.0 * t).sin()
                    + 0.1 * (tau * 3000.0 * t).sin()
                    + 0.02 * (tau * 7000.0 * t).sin() * t) as f32
            })
            .collect();
        let f = Fbank::new().compute(&pcm);
        assert_eq!(Fbank::frames(pcm.len()), 98);
        assert_eq!(f.len(), 98 * MEL_BINS);
        for (t, b, want) in [
            (0, 0, -12.57477),
            (0, 10, -5.59503),
            (10, 20, -8.35769),
            (50, 40, -15.94238),
            (97, 79, -13.42019),
            (30, 60, -14.06971),
        ] {
            let got = f[t * MEL_BINS + b];
            assert!(
                (got - want).abs() < 0.01,
                "fbank[{t},{b}] = {got}, want {want}"
            );
        }
        // After pre-emphasis the 3 kHz tone's bin is the loudest.
        let row = &f[50 * MEL_BINS..51 * MEL_BINS];
        let peak = (0..MEL_BINS)
            .max_by(|&a, &b| row[a].total_cmp(&row[b]))
            .unwrap();
        let (lo, hi) = (mel(LOW_FREQ), mel(HIGH_FREQ));
        let centre = |b: usize| lo + (b + 1) as f64 * (hi - lo) / (MEL_BINS + 1) as f64;
        assert!(
            (centre(peak) - mel(3000.0)).abs() < (hi - lo) / (MEL_BINS + 1) as f64,
            "peak bin {peak}"
        );
    }

    #[test]
    fn voice_isolation_embedder_is_deterministic_and_matches_onnxruntime() {
        if !model() {
            return;
        }
        let e = SpeakerEmbedder::shared().unwrap();
        let pcm = &ab()[..24000];
        let a = e.embed(pcm).unwrap();
        let b = e.embed(pcm).unwrap();
        assert_eq!(a, b);
        assert_eq!(a.len(), EMBEDDING_DIM);
        assert!((a.iter().map(|v| v * v).sum::<f32>() - 1.0).abs() < 1e-4);
        // onnxruntime's output with the reference features.
        for (got, want) in a
            .iter()
            .zip([-0.028_298_5, 0.039_518_07, -0.037_509_5, -0.010_388_29])
        {
            assert!((got - want).abs() < 2e-3, "{got} vs {want}");
        }
        let started = Instant::now();
        for _ in 0..5 {
            e.embed(pcm).unwrap();
        }
        let long = started.elapsed() / 5;
        let started = Instant::now();
        for _ in 0..5 {
            e.embed(&pcm[..8000]).unwrap();
        }
        let short = started.elapsed() / 5;
        let started = Instant::now();
        for _ in 0..10 {
            fbank().compute(pcm);
        }
        println!(
            "embedding 1.5 s: {long:?}; 0.5 s: {short:?}; fbank of 1.5 s: {:?}",
            started.elapsed() / 10
        );
    }

    #[test]
    fn voice_isolation_same_speaker_scores_higher() {
        if !model() {
            return;
        }
        let profile = profile_embedding(PROFILE_WAV).unwrap();
        let e = SpeakerEmbedder::shared().unwrap();
        let pcm = ab();
        let (mut same, mut other) = (Vec::new(), Vec::new());
        for (who, start, end) in TURNS {
            let speech = trim_silence(&pcm[start..end]);
            let whole = cosine(&e.embed(&speech).unwrap(), &profile);
            let windows: Vec<f32> = speech
                .chunks_exact(24000)
                .map(|w| cosine(&e.embed(w).unwrap(), &profile))
                .collect();
            println!("{who}: whole turn {whole:.3}, 1.5 s windows {windows:.3?}");
            (if who == 'A' { &mut same } else { &mut other })
                .extend(std::iter::once(whole).chain(windows));
        }
        let min_same = same.iter().copied().fold(f32::MAX, f32::min);
        let max_other = other.iter().copied().fold(f32::MIN, f32::max);
        println!("same speaker min {min_same:.3}, other speaker max {max_other:.3}");
        assert!(
            min_same > max_other + 0.3,
            "same {min_same} vs other {max_other}"
        );
        assert!(min_same > SUPPRESS_BELOW_LONG + RESTORE_MARGIN && max_other < SUPPRESS_BELOW_LONG);
    }

    #[test]
    fn voice_isolation_isolator_keeps_the_owner_and_fades_others() {
        if !model() {
            return;
        }
        let profile = profile_embedding(PROFILE_WAV).unwrap();
        let pcm16 = ab();
        // The call's 48 kHz capture (linear interpolation of the 16 kHz file).
        let pcm48: Vec<i16> = (0..pcm16.len() * 3)
            .map(|i| {
                let (j, f) = (i / 3, (i % 3) as f32 / 3.0);
                let next = pcm16.get(j + 1).copied().unwrap_or(0.0);
                ((pcm16[j] * (1.0 - f) + next * f) * 32767.0).round() as i16
            })
            .collect();
        let mut iso = Isolator::new(profile, 48000).unwrap();
        let mut out = pcm48.clone();
        // In real time, so the worker's latency counts as it would in a call.
        let started = Instant::now();
        for (k, frame) in out.chunks_exact_mut(480).enumerate() {
            iso.process(frame);
            let due = Duration::from_millis(10 * (k as u64 + 1));
            if let Some(wait) = due.checked_sub(started.elapsed()) {
                std::thread::sleep(wait);
            }
        }
        let stats = iso.stats();
        println!("{stats:?}");
        let energy = |x: &[i16]| x.iter().map(|&s| (s as f64).powi(2)).sum::<f64>();
        for (who, start, end) in TURNS {
            let (s, e) = (start * 3 / 480, end * 3 / 480);
            let (mut per_frame, mut frames, mut first_cut) = (0.0, 0, None);
            for f in s..e {
                let r = f * 480..(f + 1) * 480;
                let ein = energy(&pcm48[r.clone()]);
                // Speech frames only (above −50 dBFS).
                if ein / 480.0 < (32768.0f64 * 10f64.powf(-50.0 / 20.0)).powi(2) {
                    continue;
                }
                let db = (10.0 * (energy(&out[r]).max(1e-3) / ein).log10()).max(FLOOR_DB as f64);
                if db < -20.0 && first_cut.is_none() {
                    first_cut = Some((f - s) * 10);
                }
                per_frame += db;
                frames += 1;
            }
            let mean = per_frame / frames as f64;
            let r = start * 3..end * 3;
            let whole =
                10.0 * (energy(&out[r.clone()]).max(1e-3) / energy(&pcm48[r.clone()])).log10();
            let settled = (start + 16000) * 3..end * 3;
            let after_1s =
                10.0 * (energy(&out[settled.clone()]).max(1e-3) / energy(&pcm48[settled])).log10();
            println!(
                "{who} turn: mean per-frame {mean:.1} dB, turn energy {whole:.1} dB, after its first second {after_1s:.1} dB, first faded frame at {first_cut:?} ms"
            );
            if who == 'A' {
                assert!(
                    mean > -0.5 && whole > -0.5,
                    "the owner was faded: {mean} dB / {whole} dB"
                );
            } else {
                assert!(mean < -20.0, "another voice was only faded by {mean} dB");
                assert!(
                    after_1s < -20.0,
                    "another voice leaks after its first second: {after_1s} dB"
                );
            }
        }
        assert!(stats.frames_suppressed > 0);
    }
}
