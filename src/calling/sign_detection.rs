//! Teams' Sign language mode "actively signing" signal: while you sign with
//! your camera on, your client tells the meeting, so you count as an active
//! speaker.
//!
//! Teams detects signing on the local camera with a downloaded model. OST
//! does the same with its own open one, in ost_vfx::sign_detection (a pose
//! model and a rule over the hands' movement), and Teams' messaging rules
//! (`{signDetected, duration}`, started after half a second of signing,
//! repeated while it goes on, stopped when it ends).
//!
//! Like Teams' model, OST's isn't shipped with the app: [`prepare`]
//! downloads it on first need from its release, checks it against
//! [`MODEL_SHA256`], keeps it in the cache (`~/.cache/ost/models`) and loads
//! it on a worker thread. The camera hands frames over with [`push_frame`]
//! (dropped while the worker is busy, or detection is off); every 500 ms
//! [`tick`] gives the messages to send. Both take times from [`now_ms`].

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(feature = "video")]
pub use ost_vfx::sign_detection::SignMessage;
#[cfg(feature = "video")]
use ost_vfx::sign_detection::{EVAL_INTERVAL_MS, SignDetector, SigningAggregator};

/// The model's file name (in the cache's `models` folder).
pub const MODEL_FILE: &str = "movenet_singlepose_lightning.onnx";
/// Where the model is downloaded from: the ONNX export of Google's MoveNet
/// SinglePose Lightning (Apache-2.0; see vfx/NOTICE.md) on Hugging Face,
/// pinned to its commit.
pub const MODEL_URL: &str = "https://huggingface.co/Xenova/movenet-singlepose-lightning/resolve/ed0f314bb7356fd1dbf1e4f52c2d40791bf6534f/onnx/model.onnx";
/// The model's SHA-256: a download or cached file that doesn't match isn't
/// used.
pub const MODEL_SHA256: &str = "1ad4f8d6c2f776a9967db3993c9ca740bc350104f9d37c151dc183fc29a464ad";
/// The largest download taken (the model is 9.4 MB).
#[cfg(feature = "video")]
const MODEL_MAX_BYTES: usize = 32 << 20;

static ON: AtomicBool = AtomicBool::new(false);

/// A camera frame on its way to the worker.
#[cfg(feature = "video")]
struct Frame {
    i420: Vec<u8>,
    width: u32,
    height: u32,
    t_ms: u64,
}

/// What the worker and the ticks share.
#[cfg(feature = "video")]
#[derive(Default)]
struct Signal {
    on: bool,
    aggregator: SigningAggregator,
    /// The stop from turning detection off, until [`tick`] gives it out.
    queue: Vec<SignMessage>,
}

#[cfg(feature = "video")]
fn signal() -> std::sync::MutexGuard<'static, Signal> {
    static SIGNAL: std::sync::LazyLock<std::sync::Mutex<Signal>> =
        std::sync::LazyLock::new(Default::default);
    SIGNAL.lock().unwrap_or_else(|e| e.into_inner())
}

/// The worker's frame slot (a rendezvous channel: a frame is only taken
/// while the worker waits for one), once the model is loaded.
#[cfg(feature = "video")]
static WORKER: std::sync::OnceLock<std::sync::mpsc::SyncSender<Frame>> = std::sync::OnceLock::new();

/// When the detector next evaluates a frame: frames before then aren't
/// copied for it.
#[cfg(feature = "video")]
static NEXT_DUE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Milliseconds on the clock [`push_frame`] and [`tick`] use (steady, from
/// the first call in the process).
pub fn now_ms() -> u64 {
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_millis() as u64
}

/// Detection on or off: on while you are a signer in Sign language mode
/// with your camera on in a call. Turning it off stops a signal that had
/// started (the stop is in the next [`tick`]); off, [`push_frame`] does
/// nothing.
pub fn set_enabled(on: bool) {
    ON.store(on, Ordering::Relaxed);
    #[cfg(feature = "video")]
    {
        let mut s = signal();
        s.on = on;
        if !on && let Some(m) = s.aggregator.stop() {
            s.queue.push(m);
        }
    }
    tracing::info!(on, "sign language detection");
}

pub fn enabled() -> bool {
    ON.load(Ordering::Relaxed)
}

/// The model is loaded: frames are looked at.
#[cfg(feature = "video")]
pub fn ready() -> bool {
    WORKER.get().is_some()
}

#[cfg(not(feature = "video"))]
pub fn ready() -> bool {
    false
}

/// A camera frame (`width` x `height` I420, taken at `t_ms` on [`now_ms`]'s
/// clock), from the capture thread: returns at once. Copied to the worker
/// when detection is on, the model loaded, the detector due for a frame
/// and the worker free; otherwise dropped.
#[cfg(feature = "video")]
pub fn push_frame(i420: &[u8], width: u32, height: u32, t_ms: u64) {
    if !enabled() {
        return;
    }
    let Some(worker) = WORKER.get() else { return };
    let due = NEXT_DUE.load(Ordering::Relaxed);
    if t_ms < due && due - t_ms <= EVAL_INTERVAL_MS {
        return;
    }
    let (w, h) = (width as usize, height as usize);
    let Some(i420) = i420.get(..w * h + 2 * (w / 2) * (h / 2)) else {
        return;
    };
    let _ = worker.try_send(Frame {
        i420: i420.to_vec(),
        width,
        height,
        t_ms,
    });
}

/// The 500 ms tick, at `now_ms` on [`now_ms`]'s clock: the messages to send
/// to the meeting, in order (the stop from turning detection off, then the
/// tick's own).
#[cfg(feature = "video")]
pub fn tick(now_ms: u64) -> Vec<SignMessage> {
    let mut s = signal();
    let mut out = std::mem::take(&mut s.queue);
    out.extend(s.aggregator.tick(now_ms));
    out
}

/// Starts the worker with the loaded detector.
#[cfg(feature = "video")]
fn start_worker(mut detector: SignDetector) -> anyhow::Result<()> {
    let (tx, rx) = std::sync::mpsc::sync_channel::<Frame>(0);
    std::thread::Builder::new()
        .name("sign-detection".into())
        .spawn(move || {
            for f in rx {
                let signing = detector.push_frame(&f.i420, f.width, f.height, f.t_ms);
                NEXT_DUE.store(detector.next_eval_ms(), Ordering::Relaxed);
                let mut s = signal();
                // A frame taken before detection was turned off doesn't count.
                if s.on {
                    s.aggregator.push(signing, f.t_ms);
                }
            }
        })?;
    WORKER
        .set(tx)
        .map_err(|_| anyhow::anyhow!("the sign language detection worker is already running"))
}

/// The cached model's path under OST's cache folder (`~/.cache/ost`).
pub fn model_path(cache_dir: &Path) -> PathBuf {
    cache_dir.join("models").join(MODEL_FILE)
}

#[cfg(any(feature = "video", test))]
fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// The cached model, when it's there and its hash checks out (a file that
/// doesn't is removed, to be downloaded again).
#[cfg(any(feature = "video", test))]
fn read_cached(path: &Path) -> Option<Vec<u8>> {
    let bytes = std::fs::read(path).ok()?;
    let got = sha256_hex(&bytes);
    if got == MODEL_SHA256 {
        tracing::info!(path = %path.display(), "sign language detection model: cached, SHA-256 verified");
        Some(bytes)
    } else {
        tracing::warn!(path = %path.display(), sha256 = %got, "sign language detection model: cached file doesn't match; downloading again");
        let _ = std::fs::remove_file(path);
        None
    }
}

/// Writes `bytes` to `path` through a temporary file in the same folder,
/// synced and renamed into place, so a reader never sees part of it.
#[cfg(any(feature = "video", test))]
fn write_atomic(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    use std::io::Write;
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("download");
    let tmp = dir.join(format!(".{name}.{}.part", std::process::id()));
    let result = (|| {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
        std::fs::rename(&tmp, path)?;
        anyhow::Ok(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    result
}

/// Downloads the model from [`MODEL_URL`], checks its SHA-256 and writes it
/// to `path`.
#[cfg(feature = "video")]
async fn download(path: &Path) -> anyhow::Result<Vec<u8>> {
    use anyhow::Context;
    tracing::info!(
        url = MODEL_URL,
        "sign language detection model: downloading"
    );
    let started = std::time::Instant::now();
    let mut resp = reqwest::Client::builder()
        .user_agent(concat!("OST/", env!("CARGO_PKG_VERSION")))
        .build()?
        .get(MODEL_URL)
        .send()
        .await
        .context("sign language detection model request")?
        .error_for_status()
        .context("sign language detection model")?;
    let mut bytes = Vec::with_capacity(
        resp.content_length()
            .unwrap_or(0)
            .min(MODEL_MAX_BYTES as u64) as usize,
    );
    while let Some(chunk) = resp
        .chunk()
        .await
        .context("sign language detection model download")?
    {
        bytes.extend_from_slice(&chunk);
        anyhow::ensure!(
            bytes.len() <= MODEL_MAX_BYTES,
            "the sign language detection model download is too large"
        );
    }
    let (bytes, got) = tokio::task::spawn_blocking(move || {
        let got = sha256_hex(&bytes);
        (bytes, got)
    })
    .await?;
    anyhow::ensure!(
        got == MODEL_SHA256,
        "the downloaded sign language detection model's SHA-256 is {got}, not {MODEL_SHA256}"
    );
    let path = path.to_path_buf();
    let (path, bytes) = tokio::task::spawn_blocking(move || {
        write_atomic(&path, &bytes)
            .with_context(|| {
                format!(
                    "saving the sign language detection model to {}",
                    path.display()
                )
            })
            .map(|()| (path, bytes))
    })
    .await??;
    tracing::info!(
        bytes = bytes.len(),
        secs = started.elapsed().as_secs_f32(),
        path = %path.display(),
        "sign language detection model: downloaded, SHA-256 verified"
    );
    Ok(bytes)
}

/// Gets detection ready: its model loaded (from the cache under
/// `cache_dir`, downloaded there first when it isn't) and its worker
/// started. Until then frames aren't looked at. Calls wait for one another;
/// once it's ready it returns at once.
#[cfg(feature = "video")]
pub async fn prepare(cache_dir: &Path) -> anyhow::Result<()> {
    static BUSY: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
    let _busy = BUSY.lock().await;
    if ready() {
        return Ok(());
    }
    let path = model_path(cache_dir);
    let cached = {
        let path = path.clone();
        tokio::task::spawn_blocking(move || read_cached(&path)).await?
    };
    let onnx = match cached {
        Some(b) => b,
        None => download(&path).await?,
    };
    let detector = tokio::task::spawn_blocking(move || SignDetector::new(&onnx)).await??;
    start_worker(detector)?;
    tracing::info!("sign language detection model: loaded");
    Ok(())
}

#[cfg(not(feature = "video"))]
pub async fn prepare(_cache_dir: &Path) -> anyhow::Result<()> {
    anyhow::bail!("OST was built without sign language detection")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_detection_model_name_and_hash() {
        #[cfg(feature = "video")]
        assert_eq!(MODEL_FILE, ost_vfx::sign_detection::MODEL_FILE);
        assert!(
            MODEL_URL.starts_with("https://huggingface.co/") && MODEL_URL.contains("/resolve/")
        );
        assert_eq!(MODEL_SHA256.len(), 64);
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn sign_detection_cached_model_is_checked_and_written_atomically() {
        let dir = std::env::temp_dir().join(format!("ost-sld-test-{}", std::process::id()));
        let path = model_path(&dir);
        write_atomic(&path, b"not the model").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"not the model");
        // No temporary file is left behind.
        let left: Vec<_> = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .flatten()
            .map(|e| e.file_name())
            .collect();
        assert_eq!(left, vec![std::ffi::OsString::from(MODEL_FILE)]);
        // A file that doesn't match the hash isn't used, and is removed.
        assert!(read_cached(&path).is_none());
        assert!(!path.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(feature = "video")]
    #[test]
    fn sign_detection_waits_for_its_model_and_stops_when_turned_off() {
        // Without the model, frames are dropped and nothing is sent.
        set_enabled(true);
        assert!(enabled());
        assert!(!ready());
        let frame = vec![128u8; 64 * 48 * 3 / 2];
        push_frame(&frame, 64, 48, now_ms());
        push_frame(&frame[..10], 64, 48, now_ms());
        assert!(tick(now_ms()).is_empty());
        // Signing that had started is stopped by turning detection off.
        {
            let mut s = signal();
            for t in [0, 250, 500] {
                s.aggregator.push(true, t);
            }
        }
        assert_eq!(
            tick(500),
            vec![SignMessage {
                signed: true,
                duration_ms: 0
            }]
        );
        set_enabled(false);
        assert!(!enabled());
        assert_eq!(
            tick(1000),
            vec![SignMessage {
                signed: false,
                duration_ms: 0
            }]
        );
        assert!(tick(1500).is_empty());
    }
}
