//! Teams' Voice isolation (its "PNS", personalized noise suppression;
//! TASK-0181): with your voice profile, only your voice goes out in calls.
//!
//! Teams hands its media stack the profile's own voice signature for a
//! downloaded proprietary model. OST does the equivalent with its own open
//! model, in ost_vfx::voice_isolation: your voice profile's recording (the
//! enrollment audio the Recognition service keeps and exports) is turned
//! into a speaker embedding, and the microphone, after echo cancellation and
//! noise suppression, is held to that voice (other people's speech is
//! suppressed; silence and your own speech pass).
//!
//! Like Teams' model, OST's isn't shipped with the app: [`prepare`] downloads
//! it on first need (a voice profile, with Voice isolation chosen) from its
//! release, checks it against [`MODEL_SHA256`], keeps it in the cache
//! (`~/.cache/ost/models`) and loads it. Until then calls get standard noise
//! suppression only, as Teams' do while its model downloads.

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(feature = "video")]
use ost_vfx::voice_isolation::{Isolator, IsolatorStats};

/// The model's file name (in the cache's `models` folder).
pub const MODEL_FILE: &str = "3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx";
/// Where the model is downloaded from: sherpa-onnx's ONNX export of
/// 3D-Speaker's CAM++ VoxCeleb model (Apache-2.0; see vfx/NOTICE.md). The
/// release tag's spelling is sherpa-onnx's own.
pub const MODEL_URL: &str = "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx";
/// The model's SHA-256: a download or cached file that doesn't match isn't
/// used.
pub const MODEL_SHA256: &str = "98daf9bcf1c8abf3db374fec4c27a5eda7c58705bb3f180d057b085a72a88bb5";
/// The largest download taken (the model is 29.6 MB).
const MODEL_MAX_BYTES: usize = 64 << 20;

#[cfg(feature = "video")]
static ISOLATOR: Mutex<Option<Isolator>> = Mutex::new(None);

/// Your voice profile: its recording, and its embedding once the model has
/// made it (kept for the next call).
struct Profile {
    wav: Vec<u8>,
    embedding: Option<Vec<f32>>,
}

static PROFILE: Mutex<Option<Profile>> = Mutex::new(None);
static ON: AtomicBool = AtomicBool::new(false);

fn profile() -> std::sync::MutexGuard<'static, Option<Profile>> {
    PROFILE.lock().unwrap_or_else(|e| e.into_inner())
}

/// Your voice profile's recording, a WAV (None: no profile). Its embedding
/// is made by [`prepare`].
pub fn set_profile_recording(wav: Option<Vec<u8>>) {
    {
        let mut p = profile();
        if p.as_ref().map(|p| &p.wav) != wav.as_ref() {
            *p = wav.map(|wav| Profile { wav, embedding: None });
        }
    }
    rebuild();
}

pub fn has_profile() -> bool {
    profile().is_some()
}

/// Settings ▸ Devices ▸ Noise suppression ▸ Voice isolation (on with the
/// switch on and the radio on Voice isolation).
pub fn set_enabled(on: bool) {
    ON.store(on, Ordering::Relaxed);
    rebuild();
}

/// The model is loaded and the profile's embedding made: with Voice
/// isolation chosen, calls are held to your voice. Until then (the model
/// downloading) they get standard noise suppression.
#[cfg(feature = "video")]
pub fn ready() -> bool {
    ost_vfx::voice_isolation::model_loaded() && profile().as_ref().is_some_and(|p| p.embedding.is_some())
}

#[cfg(not(feature = "video"))]
pub fn ready() -> bool {
    false
}

fn rebuild() {
    #[cfg(feature = "video")]
    {
        let mut g = ISOLATOR.lock().unwrap_or_else(|e| e.into_inner());
        *g = None;
        if !ON.load(Ordering::Relaxed) {
            tracing::info!(on = false, "voice isolation");
            return;
        }
        let embedding = profile().as_ref().map(|p| p.embedding.clone());
        match embedding {
            None => tracing::info!(on = false, "voice isolation: no voice profile"),
            Some(None) => tracing::info!(
                on = false,
                "voice isolation: its model isn't ready yet; standard noise suppression meanwhile"
            ),
            Some(Some(e)) => match Isolator::new(e, 48_000) {
                Ok(i) => {
                    *g = Some(i);
                    tracing::info!(on = true, "voice isolation");
                }
                Err(e) => tracing::warn!("voice isolation unavailable, standard noise suppression: {e:#}"),
            },
        }
    }
}

/// The cached model's path under OST's cache folder (`~/.cache/ost`).
pub fn model_path(cache_dir: &Path) -> PathBuf {
    cache_dir.join("models").join(MODEL_FILE)
}

fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

/// The cached model, when it's there and its hash checks out (a file that
/// doesn't is removed, to be downloaded again).
fn read_cached(path: &Path) -> Option<Vec<u8>> {
    let bytes = std::fs::read(path).ok()?;
    let got = sha256_hex(&bytes);
    if got == MODEL_SHA256 {
        tracing::info!(path = %path.display(), "voice isolation model: cached, SHA-256 verified");
        Some(bytes)
    } else {
        tracing::warn!(path = %path.display(), sha256 = %got, "voice isolation model: cached file doesn't match; downloading again");
        let _ = std::fs::remove_file(path);
        None
    }
}

/// Writes `bytes` to `path` through a temporary file in the same folder,
/// synced and renamed into place, so a reader never sees part of it.
fn write_atomic(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    use std::io::Write;
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("download");
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
async fn download(path: &Path) -> anyhow::Result<Vec<u8>> {
    use anyhow::Context;
    tracing::info!(url = MODEL_URL, "voice isolation model: downloading");
    let started = std::time::Instant::now();
    let mut resp = reqwest::Client::builder()
        .user_agent(concat!("OST/", env!("CARGO_PKG_VERSION")))
        .build()?
        .get(MODEL_URL)
        .send()
        .await
        .context("voice isolation model request")?
        .error_for_status()
        .context("voice isolation model")?;
    let mut bytes = Vec::with_capacity(resp.content_length().unwrap_or(0).min(MODEL_MAX_BYTES as u64) as usize);
    while let Some(chunk) = resp.chunk().await.context("voice isolation model download")? {
        bytes.extend_from_slice(&chunk);
        anyhow::ensure!(bytes.len() <= MODEL_MAX_BYTES, "the voice isolation model download is too large");
    }
    let (bytes, got) = tokio::task::spawn_blocking(move || {
        let got = sha256_hex(&bytes);
        (bytes, got)
    })
    .await?;
    anyhow::ensure!(
        got == MODEL_SHA256,
        "the downloaded voice isolation model's SHA-256 is {got}, not {MODEL_SHA256}"
    );
    let path = path.to_path_buf();
    let (path, bytes) = tokio::task::spawn_blocking(move || {
        write_atomic(&path, &bytes)
            .with_context(|| format!("saving the voice isolation model to {}", path.display()))
            .map(|()| (path, bytes))
    })
    .await??;
    tracing::info!(
        bytes = bytes.len(),
        secs = started.elapsed().as_secs_f32(),
        path = %path.display(),
        "voice isolation model: downloaded, SHA-256 verified"
    );
    Ok(bytes)
}

/// Gets Voice isolation ready: its model loaded (from the cache under
/// `cache_dir`, downloaded there first when it isn't) and your profile's
/// embedding made; then calls are held to your voice. Until this returns,
/// they get standard noise suppression. Calls wait for one another; when
/// everything is ready it returns at once.
#[cfg(feature = "video")]
pub async fn prepare(cache_dir: &Path) -> anyhow::Result<()> {
    static BUSY: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
    let _busy = BUSY.lock().await;
    if !ost_vfx::voice_isolation::model_loaded() {
        let path = model_path(cache_dir);
        let cached = {
            let path = path.clone();
            tokio::task::spawn_blocking(move || read_cached(&path)).await?
        };
        let onnx = match cached {
            Some(b) => b,
            None => download(&path).await?,
        };
        tokio::task::spawn_blocking(move || ost_vfx::voice_isolation::load_model(&onnx)).await??;
        tracing::info!("voice isolation model: loaded");
    }
    let wav = profile().as_ref().filter(|p| p.embedding.is_none()).map(|p| p.wav.clone());
    if let Some(wav) = wav {
        let (wav, embedding) = tokio::task::spawn_blocking(move || {
            let e = ost_vfx::voice_isolation::profile_embedding(&wav);
            (wav, e)
        })
        .await?;
        let result = {
            let mut p = profile();
            let current = p.as_ref().is_some_and(|p| p.wav == wav);
            match embedding {
                Ok(e) => {
                    if let Some(p) = p.as_mut().filter(|_| current) {
                        p.embedding = Some(e);
                    }
                    Ok(())
                }
                // A recording the model can't use (under a second of
                // speech): as no profile.
                Err(e) => {
                    if current {
                        *p = None;
                    }
                    Err(e.context("voice profile"))
                }
            }
        };
        rebuild();
        return result;
    }
    rebuild();
    Ok(())
}

#[cfg(not(feature = "video"))]
pub async fn prepare(_cache_dir: &Path) -> anyhow::Result<()> {
    anyhow::bail!("OST was built without voice isolation")
}

/// The call's microphone at 48 kHz, after echo cancellation and noise
/// suppression: held to your voice while Voice isolation is on.
pub fn process(frame: &mut [i16]) {
    #[cfg(feature = "video")]
    {
        let mut g = ISOLATOR.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(iso) = g.as_mut() {
            for chunk in frame.chunks_mut(480) {
                if chunk.len() == 480 {
                    iso.process(chunk);
                }
            }
        }
    }
    #[cfg(not(feature = "video"))]
    let _ = frame;
}

/// The isolator's state now (for the harness): its last similarity, speech
/// present, suppressing, frames suppressed.
#[cfg(feature = "video")]
pub fn stats() -> Option<IsolatorStats> {
    ISOLATOR.lock().unwrap_or_else(|e| e.into_inner()).as_ref().map(|i| i.stats())
}

/// Your voice profile's recording from the Recognition service's voice
/// export (a zip; the first WAV in it).
pub fn profile_recording_from_export(zip: &[u8]) -> anyhow::Result<Vec<u8>> {
    zip_entries(zip)?
        .into_iter()
        .map(|(_, data)| data)
        .find(|data| data.starts_with(b"RIFF"))
        .ok_or_else(|| anyhow::anyhow!("The voice export has no recording"))
}

/// The files of a zip (stored or deflated), by its central directory.
pub fn zip_entries(zip: &[u8]) -> anyhow::Result<Vec<(String, Vec<u8>)>> {
    use std::io::Read;
    let u16_at = |o: usize| zip.get(o..o + 2).map(|b| u16::from_le_bytes([b[0], b[1]]) as usize);
    let u32_at = |o: usize| zip.get(o..o + 4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize);
    // The end of central directory record, searched from the end.
    let eocd = (0..zip.len().saturating_sub(21)).rev().find(|&o| zip[o..].starts_with(b"PK\x05\x06")).ok_or_else(|| anyhow::anyhow!("Not a zip"))?;
    let count = u16_at(eocd + 10).unwrap_or(0);
    let mut at = u32_at(eocd + 16).unwrap_or(0);
    let mut out = Vec::new();
    for _ in 0..count {
        if !zip.get(at..).is_some_and(|b| b.starts_with(b"PK\x01\x02")) {
            break;
        }
        let method = u16_at(at + 10).unwrap_or(0);
        let packed = u32_at(at + 20).unwrap_or(0);
        let (name_len, extra_len, comment_len) = (u16_at(at + 28).unwrap_or(0), u16_at(at + 30).unwrap_or(0), u16_at(at + 32).unwrap_or(0));
        let local = u32_at(at + 42).unwrap_or(0);
        let name = String::from_utf8_lossy(zip.get(at + 46..at + 46 + name_len).unwrap_or_default()).to_string();
        at += 46 + name_len + extra_len + comment_len;
        let start = local + 30 + u16_at(local + 26).unwrap_or(0) + u16_at(local + 28).unwrap_or(0);
        let body = zip.get(start..start + packed).ok_or_else(|| anyhow::anyhow!("A zip entry runs past the end"))?;
        let data = match method {
            0 => body.to_vec(),
            8 => {
                let mut v = Vec::new();
                flate2::read::DeflateDecoder::new(body).read_to_end(&mut v)?;
                v
            }
            m => anyhow::bail!("Zip method {m} isn't supported"),
        };
        out.push((name, data));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn voice_isolation_model_url_and_name_agree() {
        assert!(MODEL_URL.ends_with(&format!("/{MODEL_FILE}")));
        #[cfg(feature = "video")]
        assert_eq!(MODEL_FILE, ost_vfx::voice_isolation::MODEL_FILE);
        assert_eq!(MODEL_SHA256.len(), 64);
        assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    #[test]
    fn voice_isolation_cached_model_is_checked_and_written_atomically() {
        let dir = std::env::temp_dir().join(format!("ost-vi-test-{}", std::process::id()));
        let path = model_path(&dir);
        write_atomic(&path, b"not the model").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"not the model");
        // No temporary file is left behind.
        let left: Vec<_> = std::fs::read_dir(path.parent().unwrap()).unwrap().flatten().map(|e| e.file_name()).collect();
        assert_eq!(left, vec![std::ffi::OsString::from(MODEL_FILE)]);
        // A file that doesn't match the hash isn't used, and is removed.
        assert!(read_cached(&path).is_none());
        assert!(!path.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn voice_isolation_waits_for_its_model() {
        // A profile without its embedding (the model not ready) is a profile,
        // but Voice isolation isn't in effect: calls keep standard noise
        // suppression.
        set_profile_recording(Some(b"RIFF....WAVE".to_vec()));
        set_enabled(true);
        assert!(has_profile());
        assert!(!ready());
        #[cfg(feature = "video")]
        assert!(stats().is_none());
        let mut frame = [1234i16; 480];
        process(&mut frame);
        assert!(frame.iter().all(|&s| s == 1234));
        set_enabled(false);
        set_profile_recording(None);
        assert!(!has_profile());
    }
}
