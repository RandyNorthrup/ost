//! Teams' Content from camera, the camera side: a camera opened for its
//! setup dialog, every frame put through [`ost_vfx::content_camera`]
//! (edge detection, rectification with pillar boxing, whiteboard clean-up
//! and Overlay presenter, rotation) and shown as the dialog's preview
//! (the "content-camera" frames). Share hands the same processed frames
//! to the screen-sharing line, with the effects as the dialog left them;
//! the camera runs until both the dialog and the share are done with it.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};

use anyhow::Result;
use ost_vfx::content_camera::{Options, Processor, State};

use super::camera::{CameraCapture, YuvFrame};

/// The preview's frame key.
pub const PREVIEW_KEY: &str = "content-camera";
/// What goes out while sharing, once a second (for tests and checks).
pub const SHARED_KEY: &str = "content-camera-shared";

/// The camera's size: Teams' screen-sharing line takes up to 1280 x 720.
const WIDTH: u32 = 1280;
const HEIGHT: u32 = 720;
const FPS: u32 = 15;

/// A change for the camera's thread.
enum Change {
    Apply(Options),
    Rotate,
}

struct Inner {
    device: String,
    stop: AtomicBool,
    /// The camera stopped by itself (unplugged, taken, never opened).
    ended: Arc<AtomicBool>,
    preview: AtomicBool,
    changes: Mutex<Vec<Change>>,
    state: Mutex<State>,
    out: Mutex<Option<mpsc::SyncSender<YuvFrame>>>,
    frames: AtomicU64,
    /// Changes asked for, and the newest one the state reflects.
    asked: AtomicU64,
    applied: AtomicU64,
}

/// A running content camera; clones share it, the last one dropped stops
/// it.
#[derive(Clone)]
pub struct ContentCamera {
    inner: Arc<Guard>,
}

struct Guard(Arc<Inner>);

impl Drop for Guard {
    fn drop(&mut self) {
        self.0.stop.store(true, Ordering::Relaxed);
    }
}

impl ContentCamera {
    /// Open `device` and start processing (and previewing) its frames.
    /// The camera may still be held by your video turning off: opening is
    /// retried for a few seconds.
    pub fn start(device: &str) -> Result<Self> {
        let inner = Arc::new(Inner {
            device: device.to_string(),
            stop: AtomicBool::new(false),
            ended: Arc::new(AtomicBool::new(false)),
            preview: AtomicBool::new(true),
            changes: Mutex::new(Vec::new()),
            state: Mutex::new(Processor::new().state()),
            out: Mutex::new(None),
            frames: AtomicU64::new(0),
            asked: AtomicU64::new(0),
            applied: AtomicU64::new(0),
        });
        let run = inner.clone();
        std::thread::Builder::new()
            .name("ost-content-camera".into())
            .spawn(move || run_camera(&run))?;
        tracing::info!(device, "content camera started");
        Ok(Self { inner: Arc::new(Guard(inner)) })
    }

    pub fn device(&self) -> &str {
        &self.inner.0.device
    }

    /// Teams' `applyScanVideoEffect`.
    pub fn apply(&self, o: Options) {
        let mut c = self.inner.0.changes.lock().unwrap();
        c.push(Change::Apply(o));
        self.inner.0.asked.fetch_add(1, Ordering::Relaxed);
    }

    /// Teams' Rotate: a quarter turn clockwise, from the next frame on
    /// (the angle shows in [`Self::state`]).
    pub fn rotate(&self) {
        let mut c = self.inner.0.changes.lock().unwrap();
        c.push(Change::Rotate);
        self.inner.0.asked.fetch_add(1, Ordering::Relaxed);
    }

    /// Teams' `scanVideoEffect` (as of the newest frame).
    pub fn state(&self) -> State {
        *self.inner.0.state.lock().unwrap()
    }

    /// Changes not yet taken by the camera's thread: [`Self::state`] is
    /// from before them.
    pub fn pending(&self) -> bool {
        self.inner.0.asked.load(Ordering::Relaxed) != self.inner.0.applied.load(Ordering::Relaxed)
    }

    /// Frames processed so far (the preview has started once there's one).
    pub fn frames(&self) -> u64 {
        self.inner.0.frames.load(Ordering::Relaxed)
    }

    pub fn ended(&self) -> bool {
        self.inner.0.ended.load(Ordering::Relaxed)
    }

    /// Show the preview or not.
    pub fn set_preview(&self, on: bool) {
        self.inner.0.preview.store(on, Ordering::Relaxed);
        if !on {
            super::frames::clear(PREVIEW_KEY);
        }
    }

    /// The processed frames from now on, for the screen-sharing line; the
    /// camera keeps running while the receiver (or this handle) lives.
    pub fn share(&self) -> (mpsc::Receiver<YuvFrame>, Arc<AtomicBool>) {
        let (tx, rx) = mpsc::sync_channel(2);
        *self.inner.0.out.lock().unwrap() = Some(tx);
        (rx, self.inner.0.ended.clone())
    }
}

fn run_camera(inner: &Inner) {
    let started = Instant::now();
    let (camera, frames) = loop {
        match CameraCapture::start(Some(&inner.device), WIDTH, HEIGHT, FPS) {
            Ok(c) => break c,
            Err(e) if started.elapsed() < Duration::from_secs(4) && !inner.stop.load(Ordering::Relaxed) => {
                tracing::debug!("content camera: {e:#}; trying again");
                std::thread::sleep(Duration::from_millis(300));
            }
            Err(e) => {
                tracing::warn!("content camera: {e:#}");
                inner.ended.store(true, Ordering::Relaxed);
                return;
            }
        }
    };
    let _camera = camera;
    let mut fx = Processor::new();
    let mut last_shared = Instant::now() - Duration::from_secs(2);
    while !inner.stop.load(Ordering::Relaxed) {
        let f = match frames.recv_timeout(Duration::from_millis(250)) {
            Ok(f) => f,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                tracing::info!("content camera: the camera stopped");
                break;
            }
        };
        let (changes, upto) = {
            let mut c = inner.changes.lock().unwrap();
            (std::mem::take(&mut *c), inner.asked.load(Ordering::Relaxed))
        };
        for c in changes {
            match c {
                Change::Apply(o) => {
                    tracing::info!(?o, "content camera: effects");
                    fx.apply(o)
                }
                Change::Rotate => {
                    let r = fx.rotate();
                    tracing::info!(rotation = r, "content camera: rotated");
                }
            }
        }
        let (w, h) = (f.width & !1, f.height & !1);
        let out = fx.process(w, h, &f.data).to_vec();
        *inner.state.lock().unwrap() = fx.state();
        inner.applied.store(upto, Ordering::Relaxed);
        inner.frames.fetch_add(1, Ordering::Relaxed);
        let preview = inner.preview.load(Ordering::Relaxed);
        let sharing = {
            let mut slot = inner.out.lock().unwrap();
            match slot.as_ref() {
                Some(tx) => match tx.try_send(YuvFrame { width: w, height: h, data: out.clone() }) {
                    Ok(()) | Err(mpsc::TrySendError::Full(_)) => true,
                    Err(mpsc::TrySendError::Disconnected(_)) => {
                        *slot = None;
                        false
                    }
                },
                None => false,
            }
        };
        if preview {
            super::frames::publish(PREVIEW_KEY, w, h, ost_vfx::i420_to_rgba(&out, w as usize, h as usize));
        }
        if sharing && last_shared.elapsed() >= Duration::from_secs(1) {
            last_shared = Instant::now();
            super::frames::publish(SHARED_KEY, w, h, ost_vfx::i420_to_rgba(&out, w as usize, h as usize));
        }
    }
    inner.ended.store(true, Ordering::Relaxed);
    super::frames::clear(PREVIEW_KEY);
    super::frames::clear(SHARED_KEY);
    tracing::info!(device = inner.device, "content camera stopped");
}
