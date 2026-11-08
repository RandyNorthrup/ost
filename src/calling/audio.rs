//! Audio capture and playback using cpal.
//!
//! Opens the chosen (else default) input/output devices at 8000 Hz mono
//! i16 (PCMU native rate).
//! If the device doesn't support 8000 Hz, captures/plays at the device's native
//! rate and resamples with simple linear interpolation.
//!
//! Gated behind `#[cfg(feature = "audio")]` — when the feature is off, the
//! public types are not compiled and media.rs falls back to silence mode.

use std::sync::mpsc;
use std::thread;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, SampleFormat, StreamConfig};

/// Devices chosen in the app's settings (by name); `None` = the system's
/// default. Calls opened afterwards use them.
static PREFERRED: std::sync::RwLock<(Option<String>, Option<String>)> =
    std::sync::RwLock::new((None, None));

/// A device's human-readable name (what the settings store and show).
fn device_name(d: &cpal::Device) -> Option<String> {
    use cpal::traits::DeviceTrait;
    d.description().ok().map(|x| x.name().to_string())
}

/// Bumped whenever the chosen devices change: running calls move their
/// capture and playback to the new devices (Teams' in-call device picker).
static GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
/// The call's speaker volume, 0-100 (Teams' in-call volume slider).
static SPEAKER_VOLUME: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(100);
/// The microphone's current level, 0-100 (peak of the last frame), for
/// Teams' in-call mic meter.
static MIC_LEVEL: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// Use these devices (by the names `list_devices` reports) for calls;
/// `None` (or a name no longer present) means the system default. Calls
/// in progress switch to them.
pub fn set_preferred_devices(input: Option<String>, output: Option<String>) {
    let changed = {
        let mut p = PREFERRED.write().unwrap();
        let changed = p.0 != input || p.1 != output;
        *p = (input, output);
        changed
    };
    if changed {
        GENERATION.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    }
}

/// The devices chosen for calls: (microphone, speaker); `None` = default.
pub fn preferred_devices() -> (Option<String>, Option<String>) {
    PREFERRED.read().unwrap().clone()
}

/// Set the call's playback volume (0-100).
pub fn set_speaker_volume(volume: u32) {
    SPEAKER_VOLUME.store(volume.min(100), std::sync::atomic::Ordering::Relaxed);
}

pub fn speaker_volume() -> u32 {
    SPEAKER_VOLUME.load(std::sync::atomic::Ordering::Relaxed)
}

/// The microphone's level (0-100) while a call captures it.
/// The loudest sample played lately, 0–100 (call audio reaching the
/// speaker).
static SPEAKER_PEAK: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// The loudest microphone sample sent (after processing) lately, 0–100.
static MIC_OUT_PEAK: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// The loudest processed microphone sample since the last call, 0–100.
pub fn take_mic_out_peak() -> u32 {
    MIC_OUT_PEAK.swap(0, std::sync::atomic::Ordering::Relaxed)
}

/// The loudest sample played since the last call, 0–100.
pub fn take_speaker_peak() -> u32 {
    SPEAKER_PEAK.swap(0, std::sync::atomic::Ordering::Relaxed)
}

pub fn mic_level() -> u32 {
    MIC_LEVEL.load(std::sync::atomic::Ordering::Relaxed)
}

/// Wait while the stream should run: returns `true` to rebuild it on newly
/// chosen devices, `false` when the owner dropped it.
fn park_until_switch(keep_rx: &mpsc::Receiver<()>, generation: u64) -> bool {
    loop {
        match keep_rx.recv_timeout(std::time::Duration::from_millis(100)) {
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if GENERATION.load(std::sync::atomic::Ordering::SeqCst) != generation {
                    return true;
                }
            }
            _ => return false,
        }
    }
}

/// The audio endpoints a person picks from, as Teams lists them: real
/// microphones (sources) or speakers (sinks), by name. With PipeWire, cpal
/// also reports its "follow the default" placeholders, other applications'
/// streams (factory `client-node`) and sinks again as inputs (their
/// monitors); none of those are devices.
fn endpoints(host: &cpal::Host, input: bool) -> Vec<Device> {
    use cpal::DeviceDirection;
    let devices: Vec<Device> = if input {
        host.input_devices()
            .map(|it| it.collect())
            .unwrap_or_default()
    } else {
        host.output_devices()
            .map(|it| it.collect())
            .unwrap_or_default()
    };
    if host.id() != cpal::HostId::PipeWire {
        return devices;
    }
    devices
        .into_iter()
        .filter(|d| {
            let Ok(desc) = d.description() else {
                return false;
            };
            let real = desc.driver().is_some_and(|f| f != "client-node");
            let right_way = if input {
                desc.direction() == DeviceDirection::Input
            } else {
                matches!(
                    desc.direction(),
                    DeviceDirection::Output | DeviceDirection::Duplex
                )
            };
            real && right_way
        })
        .collect()
}

/// The names of the audio devices: (microphones, speakers).
pub fn list_devices() -> (Vec<String>, Vec<String>) {
    let host = cpal::default_host();
    let names = |input| {
        endpoints(&host, input)
            .iter()
            .filter_map(device_name)
            .collect::<Vec<_>>()
    };
    (names(true), names(false))
}

/// The system's default devices' names: (microphone, speaker).
pub fn default_devices() -> (Option<String>, Option<String>) {
    let host = cpal::default_host();
    // PipeWire's defaults are placeholders in cpal; ask PipeWire which
    // endpoints they are.
    #[cfg(target_os = "linux")]
    if host.id() == cpal::HostId::PipeWire {
        return super::pw_defaults::default_endpoints();
    }
    (
        host.default_input_device().and_then(|d| device_name(&d)),
        host.default_output_device().and_then(|d| device_name(&d)),
    )
}

/// The preferred device of a kind if it is present, else the default.
fn pick_device(host: &cpal::Host, input: bool) -> Option<Device> {
    let wanted = {
        let p = PREFERRED.read().unwrap();
        if input { p.0.clone() } else { p.1.clone() }
    };
    if let Some(name) = wanted {
        let found = endpoints(host, input)
            .into_iter()
            .find(|d| device_name(d).as_deref() == Some(name.as_str()));
        if found.is_some() {
            return found;
        }
        tracing::info!("Chosen audio device is gone; using the default");
    }
    if input {
        host.default_input_device()
    } else {
        host.default_output_device()
    }
}

/// About how long played audio takes to come back into the microphone
/// (the playback queue and device buffers); the echo canceller refines it.
const APM_DELAY_MS: i32 = 60;

/// The call's sample rate when none is given (PCMU's 8 kHz).
const TARGET_RATE: u32 = 8000;

// ---------------------------------------------------------------------------
// Resampling helpers (public for testing)
// ---------------------------------------------------------------------------

/// Downsample from `src_rate` to `dst_rate` using simple linear interpolation.
///
/// Both rates must be > 0. Returns a new buffer at the target rate.
pub fn resample(samples: &[i16], src_rate: u32, dst_rate: u32) -> Vec<i16> {
    if src_rate == dst_rate || samples.is_empty() {
        return samples.to_vec();
    }
    let ratio = src_rate as f64 / dst_rate as f64;
    let out_len = ((samples.len() as f64) / ratio).round() as usize;
    if out_len == 0 {
        return vec![];
    }
    let mut out = Vec::with_capacity(out_len);
    for i in 0..out_len {
        let pos = i as f64 * ratio;
        let idx = pos as usize;
        let frac = pos - idx as f64;
        let s0 = samples[idx.min(samples.len() - 1)] as f64;
        let s1 = samples[(idx + 1).min(samples.len() - 1)] as f64;
        let val = s0 + frac * (s1 - s0);
        out.push(val.round() as i16);
    }
    out
}

// ---------------------------------------------------------------------------
// AudioCapture
// ---------------------------------------------------------------------------

/// Captures audio from the default input device and delivers 160-sample
/// (20ms at 8kHz) frames via a channel.
///
/// The cpal Stream is kept alive on a dedicated OS thread so that
/// `AudioCapture` is Send + Sync (required for MediaSession which lives
/// across await points in tokio::spawn).
pub struct AudioCapture {
    _keep_alive: std::sync::mpsc::Sender<()>,
}

impl AudioCapture {
    /// Try to open the default input device. Returns `None` (with a warning log)
    /// if no device is available or the stream cannot be built.
    ///
    /// The returned `Receiver` yields `Vec<i16>` frames of approximately 160
    /// samples (20ms at 8000 Hz).
    pub fn start() -> Option<(Self, mpsc::Receiver<Vec<i16>>)> {
        Self::start_at(TARGET_RATE)
    }

    /// The same at `rate` Hz: 20 ms mono frames (`rate / 50` samples).
    pub fn start_at(rate: u32) -> Option<(Self, mpsc::Receiver<Vec<i16>>)> {
        let (frame_tx, frame_rx) = mpsc::sync_channel::<Vec<i16>>(50);
        // Channel to keep the stream-owning thread alive; dropping sender kills it.
        let (keep_tx, keep_rx) = mpsc::channel::<()>();

        let started = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let started2 = started.clone();

        thread::spawn(move || {
            loop {
                let generation = GENERATION.load(std::sync::atomic::Ordering::SeqCst);
                let Some(stream) = open_capture(frame_tx.clone(), rate) else {
                    // Keep the call's channel; try again when devices change.
                    if !park_until_switch(&keep_rx, generation) {
                        return;
                    }
                    continue;
                };
                started2.store(true, std::sync::atomic::Ordering::SeqCst);
                let again = park_until_switch(&keep_rx, generation);
                drop(stream);
                MIC_LEVEL.store(0, std::sync::atomic::Ordering::Relaxed);
                if !again {
                    return;
                }
            }
        });

        // Give the thread a moment to initialize.
        thread::sleep(std::time::Duration::from_millis(100));

        if started.load(std::sync::atomic::Ordering::SeqCst) {
            Some((
                AudioCapture {
                    _keep_alive: keep_tx,
                },
                frame_rx,
            ))
        } else {
            None
        }
    }
}

// ---------------------------------------------------------------------------
// AudioPlayback
// ---------------------------------------------------------------------------

/// Plays audio to the default output device. Accepts 160-sample (20ms at 8kHz)
/// frames via a channel.
///
/// Like AudioCapture, the cpal Stream lives on a dedicated OS thread.
pub struct AudioPlayback {
    _keep_alive: std::sync::mpsc::Sender<()>,
}

impl AudioPlayback {
    /// Try to open the default output device. Returns `None` (with a warning log)
    /// if no device is available or the stream cannot be built.
    ///
    /// Send `Vec<i16>` frames of 160 samples (20ms at 8000 Hz) into the
    /// returned `SyncSender`.
    pub fn start() -> Option<(Self, mpsc::SyncSender<Vec<i16>>)> {
        Self::start_at(TARGET_RATE)
    }

    /// The same for mono frames at `rate` Hz.
    pub fn start_at(call_rate: u32) -> Option<(Self, mpsc::SyncSender<Vec<i16>>)> {
        let (frame_tx, frame_rx) = mpsc::sync_channel::<Vec<i16>>(50);
        let (keep_tx, keep_rx) = mpsc::channel::<()>();

        let started = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let started2 = started.clone();

        // The call writes frames here; a feeder resamples them into the
        // ring the current output stream drains (at that device's rate).
        let ring = std::sync::Arc::new(std::sync::Mutex::new(
            std::collections::VecDeque::<i16>::new(),
        ));
        let device_rate = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(call_rate));
        {
            let ring = ring.clone();
            let device_rate = device_rate.clone();
            thread::spawn(move || {
                while let Ok(frame) = frame_rx.recv() {
                    // What we play is the echo canceller's reference.
                    if call_rate == 48_000
                        && let Some(p) = super::apm::current()
                    {
                        let mut reference = frame.clone();
                        p.lock().unwrap_or_else(|e| e.into_inner()).render(&mut reference);
                    }
                    let peak = frame.iter().map(|s| s.unsigned_abs() as u32).max().unwrap_or(0) * 100 / 32768;
                    SPEAKER_PEAK.fetch_max(peak, std::sync::atomic::Ordering::Relaxed);
                    let rate = device_rate.load(std::sync::atomic::Ordering::Relaxed);
                    let samples = if rate != call_rate {
                        resample(&frame, call_rate, rate)
                    } else {
                        frame
                    };
                    let mut r = ring.lock().unwrap();
                    // Keep at most 200 ms queued (a stalled device drops audio).
                    let cap = (rate as usize / 1000) * 200;
                    r.extend(samples.iter());
                    while r.len() > cap {
                        r.pop_front();
                    }
                }
            });
        }

        thread::spawn(move || {
            loop {
                let generation = GENERATION.load(std::sync::atomic::Ordering::SeqCst);
                let Some(stream) = open_playback(ring.clone(), device_rate.clone(), call_rate) else {
                    if !park_until_switch(&keep_rx, generation) {
                        return;
                    }
                    continue;
                };
                started2.store(true, std::sync::atomic::Ordering::SeqCst);
                let again = park_until_switch(&keep_rx, generation);
                drop(stream);
                if !again {
                    return;
                }
            }
        });

        thread::sleep(std::time::Duration::from_millis(100));

        if started.load(std::sync::atomic::Ordering::SeqCst) {
            Some((
                AudioPlayback {
                    _keep_alive: keep_tx,
                },
                frame_tx,
            ))
        } else {
            None
        }
    }
}

/// Open the chosen (else default) microphone, sending 20 ms frames at
/// 8 kHz to `frame_tx` and keeping MIC_LEVEL current.
fn open_capture(frame_tx: mpsc::SyncSender<Vec<i16>>, target: u32) -> Option<cpal::Stream> {
    let host = cpal::default_host();
    let Some(device) = pick_device(&host, true) else {
        tracing::warn!("No audio input device found — mic capture disabled");
        return None;
    };
    let dev_name = device_name(&device).unwrap_or_else(|| "unknown".into());
    tracing::info!("Audio input device: {}", dev_name);
    let Some((config, device_rate)) = pick_config(&device, true, target) else {
        tracing::warn!("Cannot find suitable input config for {}", dev_name);
        return None;
    };
    let frame_device_samples = (device_rate as usize * 20) / 1000;
    let need_resample = device_rate != target;
    let channels = usize::from(config.channels.max(1));
    let mut dump = std::env::var_os("OST_DUMP_MIC").and_then(|p| std::fs::File::create(p).ok());
    tracing::info!(channels = config.channels, rate = device_rate, buffer = ?config.buffer_size, "audio capture config");
    let mut logged = 0u32;
    let mut acc = Vec::<i16>::with_capacity(frame_device_samples * 2);
    let stream = match device.build_input_stream(
        config,
        move |data: &[i16], _: &cpal::InputCallbackInfo| {
            // OST_DUMP_MIC=<file>: the device's raw samples (diagnostics).
            if let Some(f) = dump.as_mut() {
                use std::io::Write;
                let bytes: Vec<u8> = data.iter().flat_map(|s| s.to_le_bytes()).collect();
                let _ = f.write_all(&bytes);
            }
            if channels == 1 {
                acc.extend_from_slice(data);
            } else {
                // Mix the device's channels down to mono.
                acc.extend(data.chunks_exact(channels).map(|f| {
                    (f.iter().map(|&x| i32::from(x)).sum::<i32>() / channels as i32) as i16
                }));
            }
            while acc.len() >= frame_device_samples {
                let chunk: Vec<i16> = acc.drain(..frame_device_samples).collect();
                let peak = chunk
                    .iter()
                    .map(|s| s.unsigned_abs() as u32)
                    .max()
                    .unwrap_or(0);
                MIC_LEVEL.store(peak * 100 / 32768, std::sync::atomic::Ordering::Relaxed);
                if logged < 3 {
                    logged += 1;
                    let rms = (chunk.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / chunk.len() as f64).sqrt();
                    tracing::debug!(peak, rms, first = ?&chunk[..8.min(chunk.len())], "mic frame");
                }
                let mut frame = if need_resample {
                    resample(&chunk, device_rate, target)
                } else {
                    chunk
                };
                // The call's echo cancellation, noise suppression and gain.
                if target == 48_000
                    && let Some(p) = super::apm::current()
                {
                    p.lock().unwrap_or_else(|e| e.into_inner()).capture(&mut frame, APM_DELAY_MS);
                }
                let out = frame.iter().map(|s| s.unsigned_abs() as u32).max().unwrap_or(0) * 100 / 32768;
                MIC_OUT_PEAK.fetch_max(out, std::sync::atomic::Ordering::Relaxed);
                let _ = frame_tx.try_send(frame);
            }
        },
        move |err| {
            tracing::warn!("Audio input stream error: {}", err);
        },
        None,
    ) {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Failed to build audio input stream: {}", e);
            return None;
        }
    };
    if let Err(e) = stream.play() {
        tracing::warn!("Failed to start audio input stream: {}", e);
        return None;
    }
    tracing::info!(
        "Audio capture started (device {}Hz, target {}Hz)",
        device_rate,
        target
    );
    Some(stream)
}

/// Open the chosen (else default) speaker, draining `ring` (filled at the
/// rate stored in `device_rate`) with the call's volume applied.
fn open_playback(
    ring: std::sync::Arc<std::sync::Mutex<std::collections::VecDeque<i16>>>,
    device_rate: std::sync::Arc<std::sync::atomic::AtomicU32>,
    target: u32,
) -> Option<cpal::Stream> {
    let host = cpal::default_host();
    let Some(device) = pick_device(&host, false) else {
        tracing::warn!("No audio output device found — speaker playback disabled");
        return None;
    };
    let dev_name = device_name(&device).unwrap_or_else(|| "unknown".into());
    tracing::info!("Audio output device: {}", dev_name);
    let Some((config, rate)) = pick_config(&device, false, target) else {
        tracing::warn!("Cannot find suitable output config for {}", dev_name);
        return None;
    };
    device_rate.store(rate, std::sync::atomic::Ordering::Relaxed);
    ring.lock().unwrap().clear();
    let channels = config.channels;
    let stream = match device.build_output_stream(
        config,
        move |data: &mut [i16], _: &cpal::OutputCallbackInfo| {
            let volume = SPEAKER_VOLUME.load(std::sync::atomic::Ordering::Relaxed) as i32;
            let mut r = ring.lock().unwrap();
            // The call is mono: the same sample on every channel.
            for frame in data.chunks_mut(usize::from(channels.max(1))) {
                let s = (r.pop_front().unwrap_or(0) as i32 * volume / 100) as i16;
                frame.iter_mut().for_each(|x| *x = s);
            }
        },
        move |err| {
            tracing::warn!("Audio output stream error: {}", err);
        },
        None,
    ) {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Failed to build audio output stream: {}", e);
            return None;
        }
    };
    if let Err(e) = stream.play() {
        tracing::warn!("Failed to start audio output stream: {}", e);
        return None;
    }
    tracing::info!(
        "Audio playback started (device {}Hz {}ch, target {}Hz mono)",
        rate,
        channels,
        target
    );
    Some(stream)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pick a mono i16 stream config, preferring 8000 Hz but falling back to
/// the device's default rate.
fn pick_config(device: &Device, input: bool, target: u32) -> Option<(StreamConfig, u32)> {
    // Collect into Vec since input/output iterators are different types.
    let configs: Vec<cpal::SupportedStreamConfigRange> = if input {
        device.supported_input_configs().ok()?.collect()
    } else {
        device.supported_output_configs().ok()?.collect()
    };
    tracing::debug!(input, configs = ?configs.iter().map(|c| (c.sample_format(), c.channels(), c.min_sample_rate(), c.max_sample_rate())).collect::<Vec<_>>(), "device configs");

    for cfg in &configs {
        if cfg.sample_format() == SampleFormat::I16
            && cfg.channels() == 1
            && cfg.min_sample_rate() <= target
            && cfg.max_sample_rate() >= target
        {
            let sc = (*cfg).with_sample_rate(target);
            return Some((sc.into(), target));
        }
    }

    // Second pass: any i16 config, use its default/max rate, we'll resample.
    for cfg in &configs {
        if cfg.sample_format() == SampleFormat::I16 {
            // Prefer 48000, then 44100, then max.
            let rate = if cfg.min_sample_rate() <= 48000 && cfg.max_sample_rate() >= 48000 {
                48000
            } else if cfg.min_sample_rate() <= 44100 && cfg.max_sample_rate() >= 44100 {
                44100
            } else {
                cfg.max_sample_rate()
            };
            // The device's own channel count: PipeWire hands back garbage
            // when asked for mono on a stereo-only source. Callers mix
            // down (capture) or copy out (playback) per frame.
            let sc: StreamConfig = (*cfg).with_sample_rate(rate).into();
            return Some((sc, rate));
        }
    }

    // Third pass: any format, we'll force mono i16 and hope for the best.
    if let Some(cfg) = configs.first() {
        let rate = cfg.max_sample_rate().clamp(8000, 48000);
        let sc = StreamConfig {
            channels: 1,
            sample_rate: rate,
            buffer_size: cpal::BufferSize::Default,
        };
        return Some((sc, rate));
    }

    None
}

// ---------------------------------------------------------------------------
// mic_test — capture 3 seconds, then play back
// ---------------------------------------------------------------------------

/// Capture 3 seconds of microphone audio, then play it back through the speaker.
///
/// Prints a VU meter bar every 100ms during capture so you can see the level.
pub fn mic_test() -> anyhow::Result<()> {
    use anyhow::bail;

    println!("=== Microphone Test ===");
    println!("Recording for 3 seconds — speak now!\n");

    let (capture, mic_rx) = match AudioCapture::start() {
        Some(c) => c,
        None => bail!("No audio input device found"),
    };

    // Capture 3 seconds of 160-sample frames (50 frames/sec * 3 = 150 frames)
    let mut frames: Vec<Vec<i16>> = Vec::with_capacity(150);
    let start = std::time::Instant::now();
    let mut last_vu = start;

    while start.elapsed() < std::time::Duration::from_secs(3) {
        match mic_rx.recv_timeout(std::time::Duration::from_millis(25)) {
            Ok(frame) => {
                // VU meter: compute RMS level
                if last_vu.elapsed() >= std::time::Duration::from_millis(100) {
                    let rms = rms_level(&frame);
                    let db = if rms > 0.0 { 20.0 * rms.log10() } else { -60.0 };
                    let bar_len = ((db + 60.0) / 60.0 * 30.0).clamp(0.0, 30.0) as usize;
                    let bar: String = "█".repeat(bar_len) + &"░".repeat(30 - bar_len);
                    print!("\r  [{bar}] {db:5.1} dBFS ");
                    use std::io::Write;
                    let _ = std::io::stdout().flush();
                    last_vu = std::time::Instant::now();
                }
                frames.push(frame);
            }
            Err(_) => continue,
        }
    }
    drop(capture);
    println!(
        "\n\nCaptured {} frames ({:.1}s)",
        frames.len(),
        frames.len() as f64 * 0.02
    );

    // Play back
    println!("Playing back...\n");
    let (playback, speaker_tx) = match AudioPlayback::start() {
        Some(p) => p,
        None => bail!("No audio output device found"),
    };

    for frame in &frames {
        let _ = speaker_tx.send(frame.clone());
        thread::sleep(std::time::Duration::from_millis(20));
    }
    // Drain: let playback finish
    thread::sleep(std::time::Duration::from_millis(200));
    drop(playback);

    println!("Done.");
    Ok(())
}

/// Compute RMS level of a frame, normalized to 0.0–1.0 range.
fn rms_level(samples: &[i16]) -> f64 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum_sq: f64 = samples.iter().map(|&s| (s as f64) * (s as f64)).sum();
    (sum_sq / samples.len() as f64).sqrt() / 32768.0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resample_identity() {
        let input: Vec<i16> = (0..160).collect();
        let out = resample(&input, 8000, 8000);
        assert_eq!(out, input);
    }

    #[test]
    fn test_resample_upsample_6x() {
        // 8000 -> 48000 = 6x
        let input: Vec<i16> = vec![0, 1000, 2000, 0];
        let out = resample(&input, 8000, 48000);
        assert_eq!(out.len(), 24);
        // First sample should be 0, last should be near 0
        assert_eq!(out[0], 0);
        // Midpoint-ish samples should interpolate
        assert!(out[3] > 0 && out[3] < 1000);
    }

    #[test]
    fn test_resample_downsample_6x() {
        // 48000 -> 8000 = 1/6
        let input: Vec<i16> = (0..48).map(|i| (i * 100) as i16).collect();
        let out = resample(&input, 48000, 8000);
        assert_eq!(out.len(), 8);
        assert_eq!(out[0], 0);
    }

    #[test]
    fn test_resample_empty() {
        let out = resample(&[], 48000, 8000);
        assert!(out.is_empty());
    }

    #[test]
    fn test_audio_capture_graceful_on_headless() {
        // On CI/headless, this should return None without panicking.
        // On a machine with audio, it returns Some.
        let result = AudioCapture::start();
        // Either outcome is fine — just don't panic.
        if result.is_none() {
            tracing::info!("No audio input device (expected on headless)");
        }
    }

    #[test]
    fn test_audio_playback_graceful_on_headless() {
        let result = AudioPlayback::start();
        if result.is_none() {
            tracing::info!("No audio output device (expected on headless)");
        }
    }
}
