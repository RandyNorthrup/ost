//! V4L2 camera capture — reads YUV420 (or YUYV) frames from /dev/video0.
//!
//! Uses the `v4l` crate with mmap streaming. Converts YUYV to I420 if needed.
//! Runs a capture thread that sends raw YUV frames over a channel.

use anyhow::{Context, Result};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};
use std::time::{Duration, Instant};
use v4l::buffer::Type;
use v4l::io::mmap::Stream;
use v4l::io::traits::CaptureStream;
use v4l::video::Capture;
use v4l::{Device, FourCC};

/// The cameras V4L2 offers (capture nodes only, as Teams lists cameras):
/// `(path, name)`, e.g. `("/dev/video0", "Integrated Camera")`.
pub fn list_devices() -> Vec<(String, String)> {
    let mut nodes: Vec<(u32, String)> = std::fs::read_dir("/dev")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().into_string().ok()?;
            let n: u32 = name.strip_prefix("video")?.parse().ok()?;
            Some((n, format!("/dev/{name}")))
        })
        .collect();
    nodes.sort();
    nodes
        .into_iter()
        .filter_map(|(_, path)| {
            let dev = match Device::with_path(&path) {
                Ok(d) => d,
                // A camera you may not open is still there (Teams lists it
                // and reports "Teams needs permission to use this device", OST its own name):
                // its name from sysfs, capture nodes only (a UVC camera's
                // metadata node is its second, index 1).
                Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
                    return sysfs_camera(&path);
                }
                Err(_) => return None,
            };
            let caps = dev.query_caps().ok()?;
            // Metadata and output nodes aren't cameras.
            caps.capabilities
                .contains(v4l::capability::Flags::VIDEO_CAPTURE)
                .then(|| {
                    let card = caps.card.trim().to_string();
                    // UVC names repeat the model ("Integrated Camera: Integrated C").
                    let name = card.split(':').next().unwrap_or(&card).trim().to_string();
                    (path, if name.is_empty() { card } else { name })
                })
        })
        .collect()
}

/// A camera node we can't open: `(path, name)` from
/// /sys/class/video4linux/<node>/{name,index}, when it is a device's first
/// node.
fn sysfs_camera(path: &str) -> Option<(String, String)> {
    let node = path.strip_prefix("/dev/")?;
    let dir = std::path::Path::new("/sys/class/video4linux").join(node);
    let index = std::fs::read_to_string(dir.join("index")).ok()?;
    if index.trim() != "0" {
        return None;
    }
    let card = std::fs::read_to_string(dir.join("name"))
        .ok()?
        .trim()
        .to_string();
    let name = card.split(':').next().unwrap_or(&card).trim().to_string();
    Some((path.to_string(), if name.is_empty() { card } else { name }))
}

/// A captured YUV420 (I420) frame.
pub struct YuvFrame {
    pub width: u32,
    pub height: u32,
    /// Planar I420: Y plane (w*h), U plane (w*h/4), V plane (w*h/4).
    pub data: Vec<u8>,
}

/// Camera capture handle. Keeps the capture thread alive; dropping it
/// stops the thread and returns once the device is closed, so the camera
/// can be opened again at once (the pre-join preview handing it to the
/// call, or the camera turned off and on).
pub struct CameraCapture {
    handle: Option<std::thread::JoinHandle<()>>,
    /// Asks the capture thread to stop.
    stop: Arc<AtomicBool>,
    /// Its run in [`super::device_health`] (0: not watched).
    run: u64,
}

impl CameraCapture {
    /// Open the camera and start capturing frames.
    ///
    /// Returns the capture handle and a receiver for YUV frames.
    /// `device_path` defaults to "/dev/video0" if None.
    /// Target resolution is 320x240 at 15fps (low bandwidth for Teams).
    pub fn start(
        device_path: Option<&str>,
        width: u32,
        height: u32,
        fps: u32,
    ) -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        if device_path == Some(AVATAR_DEVICE) {
            return Ok(Self::avatar(width, height, fps));
        }
        let path = device_path.unwrap_or("/dev/video0");
        let dev = match Device::with_path(path) {
            Ok(d) => d,
            Err(e) => {
                // Teams' VideoCapturePermissionDenied / start failure.
                super::device_health::note_camera(
                    if e.kind() == std::io::ErrorKind::PermissionDenied {
                        super::device_health::Open::Permission
                    } else {
                        super::device_health::Open::Failed
                    },
                );
                return Err(
                    anyhow::Error::new(e).context(format!("Failed to open camera at {}", path))
                );
            }
        };
        // Teams' "Automatically adjust camera controls", where chosen.
        super::camera_controls::apply_preferred(path);

        // Try to set format — prefer YUYV (widely supported), fall back to whatever works
        let mut fmt = dev
            .format()
            .inspect_err(|_| super::device_health::note_camera(super::device_health::Open::Failed))
            .context("Failed to get camera format")?;
        fmt.width = width;
        fmt.height = height;

        // Try YUYV first (most USB cameras support it)
        fmt.fourcc = FourCC::new(b"YUYV");
        let actual_fmt = match dev.set_format(&fmt) {
            Ok(f) => f,
            Err(_) => {
                // Try MJPG as fallback — we won't use it but log what we get
                fmt.fourcc = FourCC::new(b"MJPG");
                dev.set_format(&fmt)
                    .inspect_err(|_| {
                        super::device_health::note_camera(super::device_health::Open::Failed)
                    })
                    .context("Failed to set camera format (tried YUYV and MJPG)")?
            }
        };

        let actual_fourcc = actual_fmt.fourcc;
        let actual_w = actual_fmt.width;
        let actual_h = actual_fmt.height;
        tracing::info!(
            "Camera opened: {}x{} fourcc={} (requested {}x{} @ {}fps)",
            actual_w,
            actual_h,
            actual_fourcc,
            width,
            height,
            fps,
        );

        // Set frame rate via stream parameters
        if let Ok(mut params) = dev.params() {
            params.interval = v4l::Fraction::new(1, fps);
            let _ = dev.set_params(&params);
        }

        let (tx, rx) = mpsc::sync_channel::<YuvFrame>(2); // small buffer, drop old frames

        // Its frames are watched from here: none for 5 s is Teams'
        // VideoCaptureDeviceFreeze.
        let run = super::device_health::camera_started();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let handle = std::thread::spawn(move || {
            if let Err(e) = capture_loop(dev, actual_w, actual_h, actual_fourcc, tx, &stop2) {
                tracing::error!("Camera capture loop exited: {:#}", e);
                super::device_health::note_camera(super::device_health::Open::Failed);
            }
        });

        Ok((
            CameraCapture {
                handle: Some(handle),
                stop,
                run,
            },
            rx,
        ))
    }
}

/// Your avatar as the camera (Teams' avatar mode selects the avatar as
/// its camera device): nothing is captured; each tick asks the Avatars
/// app for a frame and passes on the newest one it drew.
pub const AVATAR_DEVICE: &str = "ost-avatar";

impl CameraCapture {
    fn avatar(width: u32, height: u32, fps: u32) -> (Self, mpsc::Receiver<YuvFrame>) {
        let (tx, rx) = mpsc::sync_channel::<YuvFrame>(2);
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let every = Duration::from_millis(1000 / u64::from(fps.max(1)));
        let handle = std::thread::spawn(move || {
            tracing::info!("Avatar camera: {width}x{height} at {fps} fps");
            let mut next = Instant::now();
            loop {
                if let Some(f) = ost_vfx::avatar::tick(width, height) {
                    let mut data = vec![0u8; (width * height * 3 / 2) as usize];
                    ost_vfx::filter::nv12_to_i420(
                        &f.data,
                        width as usize,
                        height as usize,
                        &mut data,
                    );
                    match tx.try_send(YuvFrame {
                        width,
                        height,
                        data,
                    }) {
                        Ok(()) | Err(mpsc::TrySendError::Full(_)) => {}
                        Err(mpsc::TrySendError::Disconnected(_)) => break,
                    }
                }
                if stop2.load(Ordering::Relaxed) {
                    break;
                }
                next += every;
                let now = Instant::now();
                if next > now {
                    std::thread::sleep(next - now);
                } else {
                    next = now;
                }
            }
            tracing::info!("Avatar camera stopped");
        });
        (
            CameraCapture {
                handle: Some(handle),
                stop,
                run: 0,
            },
            rx,
        )
    }
}

impl Drop for CameraCapture {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            finish_thread(h, STOP_WAIT);
        }
        super::device_health::camera_stopped(self.run);
    }
}

/// How long a camera's read waits for a frame before looking whether it
/// was asked to stop (a camera that gives none still stops promptly).
const FRAME_WAIT: Duration = Duration::from_millis(200);

/// How long stopping a camera waits for its threads to let the device go.
pub(crate) const STOP_WAIT: Duration = Duration::from_secs(2);

/// Wait (at most `limit`) for a thread that was asked to stop to end, so
/// what it holds (the camera device) is released when this returns. A
/// thread still running after that is left to end on its own.
pub(crate) fn finish_thread(handle: std::thread::JoinHandle<()>, limit: Duration) {
    if handle.thread().id() == std::thread::current().id() {
        return;
    }
    let until = Instant::now() + limit;
    while !handle.is_finished() {
        if Instant::now() >= until {
            tracing::warn!(
                thread = handle.thread().name().unwrap_or(""),
                "camera thread still stopping"
            );
            return;
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    let _ = handle.join();
}

/// A read that ended without a frame (timed out or interrupted): the
/// stream stays as it was, so waiting again is safe.
fn no_frame_yet(e: &std::io::Error) -> bool {
    matches!(
        e.kind(),
        std::io::ErrorKind::TimedOut | std::io::ErrorKind::Interrupted
    )
}

/// Main capture loop — runs on a dedicated thread.
fn capture_loop(
    dev: Device,
    width: u32,
    height: u32,
    fourcc: FourCC,
    tx: mpsc::SyncSender<YuvFrame>,
    stop: &AtomicBool,
) -> Result<()> {
    let mut stream = Stream::with_buffers(&dev, Type::VideoCapture, 4)
        .context("Failed to start V4L2 mmap stream")?;
    // Reads give up now and then, so a stop is seen even without frames.
    stream.set_timeout(FRAME_WAIT);

    while !stop.load(Ordering::Relaxed) {
        let (buf, _meta) = match stream.next() {
            Ok(f) => f,
            Err(e) if no_frame_yet(&e) => {
                // The buffer that read queued is still queued: wait for a
                // frame without queueing it again (that picture is skipped).
                loop {
                    if stop.load(Ordering::Relaxed) {
                        return Ok(());
                    }
                    match CaptureStream::dequeue(&mut stream) {
                        Ok(_) => break,
                        Err(e) if no_frame_yet(&e) => {}
                        Err(e) => return Err(e).context("Failed to read camera frame"),
                    }
                }
                continue;
            }
            Err(e) => return Err(e).context("Failed to read camera frame"),
        };
        super::device_health::camera_frame();

        let yuv_data = if fourcc == FourCC::new(b"YUYV") {
            yuyv_to_i420(buf, width, height)
        } else {
            // If format is already I420/YU12, use as-is
            buf.to_vec()
        };
        // Sign language mode's detection sees the real camera (Teams never
        // runs it on the avatar camera); a no-op unless it's on.
        super::sign_detection::push_frame(
            &yuv_data,
            width,
            height,
            super::sign_detection::now_ms(),
        );

        let frame = YuvFrame {
            width,
            height,
            data: yuv_data,
        };

        // Non-blocking send — drop frame if receiver is behind
        match tx.try_send(frame) {
            Ok(()) => {}
            Err(std::sync::mpsc::TrySendError::Full(_)) => {
                // Receiver is behind — drop frame, keep going
            }
            Err(std::sync::mpsc::TrySendError::Disconnected(_)) => {
                // Channel closed, exit
                break;
            }
        }
    }

    Ok(())
}

/// Capture ~3s of video from V4L2 camera, then play it back in an SDL2 window.
#[cfg(feature = "video-capture")]
pub fn cam_test() -> anyhow::Result<()> {
    use super::display::{DisplayFrame, VideoDisplay};
    use anyhow::bail;

    println!("=== Camera Test ===");
    println!("Capturing 3 seconds of video...\n");

    let (capture, cam_rx) =
        CameraCapture::start(None, 320, 240, 15).context("Failed to start camera")?;

    let mut frames: Vec<YuvFrame> = Vec::with_capacity(45);
    let start = std::time::Instant::now();
    let capture_duration = std::time::Duration::from_secs(3);

    while start.elapsed() < capture_duration {
        match cam_rx.recv_timeout(std::time::Duration::from_millis(100)) {
            Ok(frame) => {
                if frames.is_empty() {
                    println!("  First frame: {}x{}", frame.width, frame.height);
                }
                frames.push(frame);
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                bail!("Camera disconnected during capture");
            }
        }
    }
    drop(capture);

    let capture_elapsed = start.elapsed().as_secs_f64();
    let capture_fps = frames.len() as f64 / capture_elapsed;
    println!(
        "\nCaptured {} frames in {:.3}s ({:.1} fps)",
        frames.len(),
        capture_elapsed,
        capture_fps,
    );

    if frames.is_empty() {
        bail!("No frames captured");
    }

    println!("Playing back...\n");
    let (display, display_tx) =
        VideoDisplay::start("Camera Test Playback").context("Failed to start video display")?;

    let playback_start = std::time::Instant::now();
    let frame_interval_us = (capture_elapsed * 1_000_000.0 / frames.len() as f64) as u64;
    let frame_interval = std::time::Duration::from_micros(frame_interval_us);
    let n_frames = frames.len();
    for (i, frame) in frames.into_iter().enumerate() {
        let df = DisplayFrame {
            width: frame.width,
            height: frame.height,
            data: frame.data,
        };
        if display_tx.send(df).is_err() {
            break; // window closed
        }
        // Sleep until target wall-clock time to avoid drift from send overhead
        let target = playback_start + frame_interval * (i + 1) as u32;
        let now = std::time::Instant::now();
        if target > now {
            std::thread::sleep(target - now);
        }
    }
    let playback_elapsed = playback_start.elapsed().as_secs_f64();
    let playback_fps = n_frames as f64 / playback_elapsed;

    // Let last frame linger briefly, then close channel so display thread exits cleanly
    std::thread::sleep(std::time::Duration::from_millis(500));
    drop(display_tx);
    // Wait for display thread to finish SDL2 teardown
    display.join();

    println!(
        "Recording : {:.3}s  ({} frames, {:.1} fps)",
        capture_elapsed, n_frames, capture_fps
    );
    println!(
        "Playback  : {:.3}s  ({} frames, {:.1} fps)",
        playback_elapsed, n_frames, playback_fps
    );
    let ratio = playback_elapsed / capture_elapsed;
    if ratio > 1.05 {
        println!(
            "Playback was {:.0}% slower than recording (frame interval too long)",
            (ratio - 1.0) * 100.0
        );
    } else if ratio < 0.95 {
        println!(
            "Playback was {:.0}% faster than recording",
            (1.0 - ratio) * 100.0
        );
    } else {
        println!("Playback matched recording duration");
    }
    Ok(())
}

/// Convert YUYV (YUV 4:2:2 packed) to I420 (YUV 4:2:0 planar).
fn yuyv_to_i420(yuyv: &[u8], width: u32, height: u32) -> Vec<u8> {
    let w = width as usize;
    let h = height as usize;
    let y_size = w * h;
    let uv_size = (w / 2) * (h / 2);
    let mut out = vec![0u8; y_size + uv_size * 2];

    let (y_plane, uv_planes) = out.split_at_mut(y_size);
    let (u_plane, v_plane) = uv_planes.split_at_mut(uv_size);

    for row in 0..h {
        for col in (0..w).step_by(2) {
            let yuyv_offset = (row * w + col) * 2;
            if yuyv_offset + 3 >= yuyv.len() {
                break;
            }
            let y0 = yuyv[yuyv_offset];
            let u = yuyv[yuyv_offset + 1];
            let y1 = yuyv[yuyv_offset + 2];
            let v = yuyv[yuyv_offset + 3];

            y_plane[row * w + col] = y0;
            y_plane[row * w + col + 1] = y1;

            // Subsample U/V by 2x2
            if row % 2 == 0 {
                let uv_row = row / 2;
                let uv_col = col / 2;
                u_plane[uv_row * (w / 2) + uv_col] = u;
                v_plane[uv_row * (w / 2) + uv_col] = v;
            }
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stopping_waits_for_the_thread_to_let_go() {
        let stop = Arc::new(AtomicBool::new(false));
        let released = Arc::new(AtomicBool::new(false));
        let (s, r) = (stop.clone(), released.clone());
        let t = std::thread::spawn(move || {
            while !s.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(5));
            }
            // Letting the device go takes a while.
            std::thread::sleep(Duration::from_millis(100));
            r.store(true, Ordering::Relaxed);
        });
        stop.store(true, Ordering::Relaxed);
        finish_thread(t, STOP_WAIT);
        assert!(released.load(Ordering::Relaxed));
    }

    #[test]
    fn a_thread_that_never_stops_is_not_waited_for_long() {
        let started = Instant::now();
        let t = std::thread::spawn(|| std::thread::sleep(Duration::from_secs(3)));
        finish_thread(t, Duration::from_millis(100));
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn a_read_without_a_frame_is_waited_out_and_other_errors_end_it() {
        assert!(no_frame_yet(&std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            "VIDIOC_DQBUF"
        )));
        assert!(no_frame_yet(&std::io::Error::from(
            std::io::ErrorKind::Interrupted
        )));
        // EBUSY.
        assert!(!no_frame_yet(&std::io::Error::from_raw_os_error(16)));
    }
}
