//! Cameras: the list Settings > Devices, the pre-join screen and a call's
//! camera menu offer, and capture from the chosen one as I420 frames.
//!
//! Cameras come from PipeWire first ([`super::camera_pw`]), as Chromium
//! and other current Linux apps get them: that covers UVC webcams and
//! cameras only libcamera drives (Intel IPU6 and other MIPI laptop
//! cameras), and in the Flatpak it goes through the Camera portal. V4L2
//! nodes PipeWire doesn't offer follow (systems without PipeWire,
//! v4l2loopback devices), keeping only nodes that deliver a picture by
//! themselves ([`super::camera_node`]); a camera both offer is listed once.
//!
//! A camera's ID is `pipewire:<node.name>` or its V4L2 path
//! (`/dev/videoN`); a saved V4L2 path that PipeWire now offers is that
//! PipeWire camera.

use anyhow::{Context, Result};
use std::os::unix::fs::MetadataExt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};
use std::time::{Duration, Instant};
use v4l::buffer::Type;
use v4l::io::mmap::Stream;
use v4l::io::traits::CaptureStream;
use v4l::video::Capture;
use v4l::{Device, FourCC};

use super::camera_node::{self, Verdict};
use super::camera_pw::{self, PwCamera};
use super::pixfmt::{self, PixelFormat};

/// The ID prefix of a PipeWire camera.
pub const PIPEWIRE_PREFIX: &str = "pipewire:";

/// How long a list waits for PipeWire's first answer.
const PIPEWIRE_WAIT: Duration = Duration::from_millis(1500);

/// A camera OST can use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CameraInfo {
    /// What Settings keeps: `pipewire:<node.name>` or `/dev/videoN`.
    pub id: String,
    pub name: String,
    /// The V4L2 node behind it, when there is one (its controls).
    pub v4l2_path: Option<String>,
}

/// The cameras, as Teams lists them: PipeWire's, then V4L2 nodes PipeWire
/// doesn't offer.
pub fn cameras() -> Vec<CameraInfo> {
    let pw = camera_pw::cameras(PIPEWIRE_WAIT).unwrap_or_default();
    merge(&pw, v4l2_cameras(), rdev)
}

/// PipeWire's cameras and the V4L2 cameras `(path, name)`, without the
/// V4L2 nodes a PipeWire camera already uses (`dev` gives a path's
/// device number).
fn merge(
    pw: &[PwCamera],
    v4l2: Vec<(String, String)>,
    dev: impl Fn(&str) -> Option<u64>,
) -> Vec<CameraInfo> {
    let mut list: Vec<CameraInfo> = pw
        .iter()
        .map(|c| CameraInfo {
            id: format!("{PIPEWIRE_PREFIX}{}", c.node_name),
            name: c.name.clone(),
            v4l2_path: c.v4l2_path.clone(),
        })
        .collect();
    for (path, name) in v4l2 {
        let taken = pw.iter().any(|c| {
            c.v4l2_path.as_deref() == Some(path.as_str())
                || dev(&path).is_some_and(|d| c.devids.contains(&d))
        });
        if !taken {
            list.push(CameraInfo {
                v4l2_path: Some(path.clone()),
                id: path,
                name,
            });
        }
    }
    list
}

fn rdev(path: &str) -> Option<u64> {
    std::fs::metadata(path).ok().map(|m| m.rdev())
}

/// The cameras as `(id, name)`, e.g. `("pipewire:libcamera_input…",
/// "Built-in Front Camera")` or `("/dev/video20", "OST test camera A")`.
pub fn list_devices() -> Vec<(String, String)> {
    cameras().into_iter().map(|c| (c.id, c.name)).collect()
}

/// The listed camera `wanted` names: its ID, or a V4L2 path saved before
/// PipeWire offered that camera.
pub fn find<'a>(list: &'a [CameraInfo], wanted: &str) -> Option<&'a CameraInfo> {
    list.iter()
        .find(|c| c.id == wanted)
        .or_else(|| list.iter().find(|c| c.v4l2_path.as_deref() == Some(wanted)))
}

/// Whether two camera IDs name the same camera (a saved V4L2 path and the
/// PipeWire camera wrapping it do).
pub fn same_camera(a: &str, b: &str) -> bool {
    if a == b {
        return true;
    }
    let list = cameras();
    match (find(&list, a), find(&list, b)) {
        (Some(x), Some(y)) => x.id == y.id,
        _ => false,
    }
}

/// Whether `id` looks like a camera ID (for settings read from disk).
pub fn is_camera_id(id: &str) -> bool {
    id == AVATAR_DEVICE
        || id
            .strip_prefix("/dev/video")
            .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
        || id
            .strip_prefix(PIPEWIRE_PREFIX)
            .is_some_and(|n| !n.is_empty() && !n.contains('\n'))
}

/// The V4L2 node behind a camera (for its controls), if it has one.
pub fn v4l2_path(id: &str) -> Option<String> {
    if id.starts_with("/dev/video") {
        return Some(id.to_string());
    }
    let name = id.strip_prefix(PIPEWIRE_PREFIX)?;
    camera_pw::cameras(PIPEWIRE_WAIT)?
        .into_iter()
        .find(|c| c.node_name == name)?
        .v4l2_path
}

/// The V4L2 nodes that are cameras: `(path, name)`, in node order.
fn v4l2_cameras() -> Vec<(String, String)> {
    let mut nodes: Vec<(u32, String)> = std::fs::read_dir("/dev")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().into_string().ok()?;
            let n: u32 = name.strip_prefix("video")?.parse().ok()?;
            Some((n, name))
        })
        .collect();
    nodes.sort();
    nodes
        .into_iter()
        .filter_map(|(_, node)| {
            let path = format!("/dev/{node}");
            let dev = match Device::with_path(&path) {
                Ok(d) => d,
                // A camera you may not open is still there (Teams lists it
                // and reports "Teams needs permission to use this device").
                Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
                    return camera_node::unopenable_camera(&node).map(|n| (path, n));
                }
                Err(_) => return None,
            };
            let info = camera_node::query(&dev).ok()?;
            match info.verdict() {
                Verdict::Camera => Some((path, info.display_name())),
                verdict => {
                    tracing::trace!(path, driver = info.driver, ?verdict, "not a camera");
                    None
                }
            }
        })
        .collect()
}

/// A captured YUV420 (I420) frame.
pub struct YuvFrame {
    pub width: u32,
    pub height: u32,
    /// Planar I420: Y plane (w*h), U plane (w*h/4), V plane (w*h/4).
    pub data: Vec<u8>,
}

/// Camera capture handle. Keeps the capture thread alive; dropping it
/// stops the thread and returns once the device is closed (or the
/// PipeWire stream disconnected), so the camera can be opened again at
/// once (the pre-join preview handing it to the call, or the camera turned
/// off and on).
pub struct CameraCapture {
    handle: Option<std::thread::JoinHandle<()>>,
    /// Asks the capture thread to stop.
    stop: Arc<AtomicBool>,
    /// Its run in [`super::device_health`] (0: not watched).
    run: u64,
}

impl CameraCapture {
    /// Open the camera `device` (an ID from [`cameras`]; the first camera
    /// if `None`) and start capturing frames of about `width`x`height` at
    /// `fps`.
    ///
    /// Returns the capture handle and a receiver for YUV frames.
    pub fn start(
        device: Option<&str>,
        width: u32,
        height: u32,
        fps: u32,
    ) -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        if device == Some(AVATAR_DEVICE) {
            return Ok(Self::avatar(width, height, fps));
        }
        let pw = camera_pw::cameras(PIPEWIRE_WAIT).unwrap_or_default();
        let id = match device {
            Some(d) => d.to_string(),
            None => match merge(&pw, v4l2_cameras(), rdev).into_iter().next() {
                Some(c) => c.id,
                None => {
                    super::device_health::note_camera(super::device_health::Open::Failed);
                    anyhow::bail!("No camera found");
                }
            },
        };
        let through_pw = match id.strip_prefix(PIPEWIRE_PREFIX) {
            Some(name) => match pw.iter().find(|c| c.node_name == name) {
                Some(c) => Some(c.clone()),
                None => {
                    super::device_health::note_camera(super::device_health::Open::Failed);
                    anyhow::bail!("The camera {name} isn't there");
                }
            },
            // A V4L2 camera PipeWire offers is captured through PipeWire,
            // which shares it with other apps.
            None => pw
                .iter()
                .find(|c| c.v4l2_path.as_deref() == Some(id.as_str()))
                .cloned(),
        };
        match through_pw {
            Some(cam) => Self::start_pipewire(&cam, width, height, fps),
            None => Self::start_v4l2(&id, width, height, fps),
        }
    }

    fn start_pipewire(
        cam: &PwCamera,
        width: u32,
        height: u32,
        fps: u32,
    ) -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        if let Some(path) = &cam.v4l2_path {
            // Teams' "Automatically adjust camera controls", where chosen.
            super::camera_controls::apply_preferred(path);
        }
        let (tx, rx) = mpsc::sync_channel::<YuvFrame>(2);
        let stop = Arc::new(AtomicBool::new(false));
        let run = super::device_health::camera_started();
        match camera_pw::capture(cam, width, height, fps, tx, stop.clone()) {
            Ok(handle) => Ok((
                CameraCapture {
                    handle: Some(handle),
                    stop,
                    run,
                },
                rx,
            )),
            Err(e) => {
                super::device_health::camera_stopped(run);
                Err(e.context(format!("Failed to open camera {}", cam.name)))
            }
        }
    }

    fn start_v4l2(
        path: &str,
        width: u32,
        height: u32,
        fps: u32,
    ) -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        let failed = || super::device_health::note_camera(super::device_health::Open::Failed);
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

        // The best format it offers (a loopback device fed already offers
        // just its producer's).
        let mut fmt = dev
            .format()
            .inspect_err(|_| failed())
            .context("Failed to get camera format")?;
        let offered: Vec<FourCC> = dev
            .enum_formats()
            .map(|f| f.into_iter().map(|d| d.fourcc).collect())
            .unwrap_or_default();
        if let Some(best) = offered
            .iter()
            .filter(|c| PixelFormat::from_fourcc(&c.repr).is_some())
            .min_by_key(|c| PixelFormat::from_fourcc(&c.repr).map_or(u8::MAX, PixelFormat::rank))
        {
            fmt.fourcc = *best;
        }
        fmt.width = width;
        fmt.height = height;
        let actual = dev
            .set_format(&fmt)
            .inspect_err(|_| failed())
            .context("Failed to set camera format")?;
        let Some(pixel) = PixelFormat::from_fourcc(&actual.fourcc.repr) else {
            failed();
            anyhow::bail!("The camera's format {} isn't supported", actual.fourcc);
        };
        tracing::info!(
            "Camera opened: {}x{} fourcc={} stride={} (requested {}x{} @ {}fps)",
            actual.width,
            actual.height,
            actual.fourcc,
            actual.stride,
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
        let shape = Shape {
            pixel,
            width: actual.width,
            height: actual.height,
            stride: actual.stride as usize,
            want: (width, height),
        };
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let handle = std::thread::spawn(move || {
            if let Err(e) = capture_loop(dev, shape, tx, &stop2) {
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

/// A V4L2 capture's negotiated picture.
struct Shape {
    pixel: PixelFormat,
    width: u32,
    height: u32,
    stride: usize,
    want: (u32, u32),
}

/// A frame no bigger than `want` (scaled down, keeping its shape).
pub(crate) fn fit(f: YuvFrame, want: (u32, u32)) -> YuvFrame {
    let (w, h) = pixfmt::fit_within(f.width, f.height, want.0.max(2), want.1.max(2));
    if (w, h) == (f.width, f.height) {
        return f;
    }
    YuvFrame {
        data: super::webrtc_video::scale_i420(&f.data, f.width, f.height, w, h),
        width: w,
        height: h,
    }
}

/// Hand a captured frame on: `false` once nobody takes frames.
pub(crate) fn deliver(frame: YuvFrame, tx: &mpsc::SyncSender<YuvFrame>) -> bool {
    super::device_health::camera_frame();
    // Sign language mode's detection sees the real camera (Teams never
    // runs it on the avatar camera); a no-op unless it's on.
    super::sign_detection::push_frame(
        &frame.data,
        frame.width,
        frame.height,
        super::sign_detection::now_ms(),
    );
    // Non-blocking: a receiver that's behind loses this frame.
    !matches!(tx.try_send(frame), Err(mpsc::TrySendError::Disconnected(_)))
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
    shape: Shape,
    tx: mpsc::SyncSender<YuvFrame>,
    stop: &AtomicBool,
) -> Result<()> {
    let mut stream = Stream::with_buffers(&dev, Type::VideoCapture, 4)
        .context("Failed to start V4L2 mmap stream")?;
    // Reads give up now and then, so a stop is seen even without frames.
    stream.set_timeout(FRAME_WAIT);
    let Shape {
        pixel,
        width,
        height,
        stride,
        want,
    } = shape;
    let stride = if stride > 0 {
        stride
    } else {
        pixfmt::min_stride(pixel, width)
    };
    let mut warned = false;
    while !stop.load(Ordering::Relaxed) {
        let (buf, meta) = match stream.next() {
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
        let used = match meta.bytesused as usize {
            0 => buf.len(),
            n => n.min(buf.len()),
        };
        let planes = pixfmt::split(pixel, height, &buf[..used], stride);
        let Some(frame) = pixfmt::to_i420(pixel, width, height, &planes) else {
            if !warned {
                tracing::warn!(used, ?pixel, "camera frame doesn't convert");
                warned = true;
            }
            continue;
        };
        if !deliver(fit(frame, want), &tx) {
            break;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pw(node: &str, path: Option<&str>, devids: &[u64]) -> PwCamera {
        PwCamera {
            id: 1,
            serial: "1".into(),
            node_name: node.into(),
            name: node.into(),
            api: if path.is_some() { "v4l2" } else { "libcamera" }.into(),
            v4l2_path: path.map(str::to_string),
            devids: devids.to_vec(),
            virtual_camera: false,
        }
    }

    /// PipeWire's cameras come first; a V4L2 node PipeWire already uses
    /// (by path, or by device number for libcamera) isn't listed again;
    /// loopback devices PipeWire doesn't offer are.
    #[test]
    fn pipewire_and_v4l2_cameras_merge_without_duplicates() {
        let pw = [
            pw("v4l2_input.usb", Some("/dev/video0"), &[20736]),
            pw("libcamera_input.ipu6", None, &[20739]),
        ];
        let v4l2 = vec![
            ("/dev/video0".to_string(), "Integrated Camera".to_string()),
            ("/dev/video3".to_string(), "ipu6".to_string()),
            ("/dev/video20".to_string(), "OST test camera A".to_string()),
        ];
        let dev = |p: &str| match p {
            "/dev/video3" => Some(20739),
            "/dev/video20" => Some(20738 + 18),
            _ => None,
        };
        let list = merge(&pw, v4l2, dev);
        let ids: Vec<&str> = list.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(
            ids,
            [
                "pipewire:v4l2_input.usb",
                "pipewire:libcamera_input.ipu6",
                "/dev/video20"
            ]
        );
        // A V4L2 path saved before resolves to the PipeWire camera.
        assert_eq!(
            find(&list, "/dev/video0").unwrap().id,
            "pipewire:v4l2_input.usb"
        );
        assert_eq!(
            find(&list, "/dev/video20").unwrap().name,
            "OST test camera A"
        );
        assert!(find(&list, "/dev/video9").is_none());
    }

    /// A live check on a machine with cameras: lists them, and captures a
    /// few frames from each ID in OST_CAMERA_LIVE (comma-separated):
    /// `OST_CAMERA_LIVE=pipewire:<node>,/dev/video40 cargo test --features
    /// audio,video --lib live_cameras -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn live_cameras() {
        for c in cameras() {
            println!("CAMERA {} | {} | {:?}", c.id, c.name, c.v4l2_path);
        }
        let ids = std::env::var("OST_CAMERA_LIVE").unwrap_or_default();
        for id in ids.split(',').filter(|i| !i.is_empty()) {
            let (cam, rx) = CameraCapture::start(Some(id), 640, 360, 15).expect("camera starts");
            let mut got = 0;
            let deadline = std::time::Instant::now() + Duration::from_secs(8);
            while got < 10 && std::time::Instant::now() < deadline {
                if let Ok(f) = rx.recv_timeout(Duration::from_millis(500)) {
                    let n = (f.width * f.height) as usize;
                    let mean =
                        |p: &[u8]| p.iter().map(|&v| v as u64).sum::<u64>() / p.len().max(1) as u64;
                    if got == 0 {
                        println!(
                            "FRAME {id}: {}x{} Y {} U {} V {}",
                            f.width,
                            f.height,
                            mean(&f.data[..n]),
                            mean(&f.data[n..n + n / 4]),
                            mean(&f.data[n + n / 4..])
                        );
                    }
                    got += 1;
                }
            }
            drop(cam);
            println!("FRAMES {id}: {got}");
            assert!(got >= 10, "{id} delivered {got} frames");
        }
    }

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

    #[test]
    fn camera_ids() {
        assert!(is_camera_id("/dev/video12"));
        assert!(is_camera_id("pipewire:libcamera_input._SB_.PCI0"));
        assert!(is_camera_id(AVATAR_DEVICE));
        assert!(!is_camera_id("/dev/video"));
        assert!(!is_camera_id("/dev/videoX"));
        assert!(!is_camera_id("pipewire:"));
        assert!(!is_camera_id("/etc/passwd"));
    }
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
