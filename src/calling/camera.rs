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
//!
//! Listing cameras opens no camera node: what PipeWire's V4L2 monitor
//! read, sysfs and udev tell what each node is. Only a node none of them
//! describes well enough (a capture card, a media-controller node without
//! PipeWire) is opened to ask, and only while the camera list is shown or
//! when it is the chosen camera, once ([`Probe`]).

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

use super::camera_mode;
use super::camera_node::{self, Listing, SysNode, Verdict};
use super::camera_pw::{self, PwCamera, PwV4l2Node};
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

/// Which V4L2 nodes a list may open to ask what they are, of those that
/// neither PipeWire nor sysfs describe well enough. No other node is
/// opened to list cameras.
#[derive(Debug, Clone, Copy)]
pub enum Probe<'a> {
    /// None: such a node is listed only as an earlier probe found it.
    Nothing,
    /// These cameras' nodes (the chosen camera's).
    These(&'a [&'a str]),
    /// Any: the camera list is being shown.
    All,
}

impl Probe<'_> {
    fn allows(&self, path: &str) -> bool {
        match self {
            Probe::Nothing => false,
            Probe::These(ids) => ids.contains(&path),
            Probe::All => true,
        }
    }

    /// Whether this node is asked for by name (the chosen camera's).
    fn names(&self, path: &str) -> bool {
        matches!(self, Probe::These(ids) if ids.contains(&path))
    }
}

/// The cameras, as Teams lists them: PipeWire's, then V4L2 nodes PipeWire
/// doesn't offer. Opens no camera node ([`Probe::Nothing`]).
pub fn cameras() -> Vec<CameraInfo> {
    cameras_probing(Probe::Nothing)
}

/// The cameras for a camera list being shown (Settings > Devices, the
/// pre-join screen, a call's camera menu).
pub fn cameras_shown() -> Vec<CameraInfo> {
    cameras_probing(Probe::All)
}

/// The cameras, asking the nodes of `ids` (the chosen camera) if need be.
pub fn cameras_with(ids: &[&str]) -> Vec<CameraInfo> {
    cameras_probing(Probe::These(ids))
}

pub fn cameras_probing(probe: Probe) -> Vec<CameraInfo> {
    let pw = camera_pw::cameras(PIPEWIRE_WAIT).unwrap_or_default();
    merge(&pw, v4l2_fallback(&pw, probe), rdev)
}

/// The camera a call uses when none is chosen: the first one (asking
/// nodes only when nothing else is a camera).
pub fn first_camera() -> Option<CameraInfo> {
    let pw = camera_pw::cameras(PIPEWIRE_WAIT).unwrap_or_default();
    first_of(&pw)
}

fn first_of(pw: &[PwCamera]) -> Option<CameraInfo> {
    merge(pw, v4l2_fallback(pw, Probe::Nothing), rdev)
        .into_iter()
        .next()
        .or_else(|| {
            merge(pw, v4l2_fallback(pw, Probe::All), rdev)
                .into_iter()
                .next()
        })
}

/// Where V4L2 nodes and udev's records of them are.
const SYS_VIDEO4LINUX: &str = "/sys/class/video4linux";
const UDEV_DATA: &str = "/run/udev/data";

/// The V4L2 cameras OST lists itself. None when cameras come through the
/// Camera portal: what the portal offers (or the person allowed, or is
/// still being asked) is all there is, never a way around their answer.
fn v4l2_fallback(pw: &[PwCamera], probe: Probe) -> Vec<(String, String)> {
    if camera_pw::use_portal() {
        return Vec::new();
    }
    let nodes = camera_node::sys_nodes(
        std::path::Path::new(SYS_VIDEO4LINUX),
        std::path::Path::new(UDEV_DATA),
    );
    v4l2_cameras(
        &nodes,
        pw,
        &camera_pw::v4l2_nodes(),
        |path| probe.names(path),
        |n| probe_node(n, probe),
    )
}

/// Start watching PipeWire's cameras now, so the first list is quick.
/// Through the Camera portal it waits until a camera is first asked for
/// (the portal may ask the person then).
pub fn prepare() {
    if !camera_pw::use_portal() {
        camera_pw::start();
    }
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
    let list = cameras_with(&[a, b]);
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
    // Through the portal, the device itself isn't OST's to open.
    if camera_pw::use_portal() {
        return None;
    }
    if id.starts_with("/dev/video") {
        return Some(id.to_string());
    }
    let name = id.strip_prefix(PIPEWIRE_PREFIX)?;
    camera_pw::cameras(PIPEWIRE_WAIT)?
        .into_iter()
        .find(|c| c.node_name == name)?
        .v4l2_path
}

/// The V4L2 nodes that are cameras, `(path, name)` in node order, of
/// `nodes`, leaving out those PipeWire's cameras use: by what sysfs and
/// udev tell, else by what PipeWire's V4L2 monitor read (`known`), else
/// by what `ask` finds (opening the node). A node `chosen` names (the
/// chosen camera's, asked for by name) is asked even when sysfs or
/// PipeWire say it isn't a camera: what they recorded may be stale.
fn v4l2_cameras(
    nodes: &[SysNode],
    pw: &[PwCamera],
    known: &[PwV4l2Node],
    chosen: impl Fn(&str) -> bool,
    mut ask: impl FnMut(&SysNode) -> Option<String>,
) -> Vec<(String, String)> {
    nodes
        .iter()
        .filter_map(|n| {
            let path = format!("/dev/{}", n.node);
            let taken = pw.iter().any(|c| {
                c.v4l2_path.as_deref() == Some(path.as_str())
                    || n.dev.is_some_and(|d| c.devids.contains(&d))
            });
            if taken {
                return None;
            }
            let name = match n.listing() {
                Listing::Camera(name) => Some(name),
                Listing::NotCamera(_) if chosen(&path) => ask(n),
                Listing::NotCamera(why) => {
                    tracing::trace!(path, why, "not a camera");
                    None
                }
                // (A loopback device's caps change as producers come and
                // go; PipeWire's are from when it found it.)
                Listing::Unknown => match known
                    .iter()
                    .find(|k| k.path == path && !k.info.is_loopback())
                {
                    Some(k) => match k.info.verdict() {
                        Verdict::Camera => Some(if k.info.card.is_empty() {
                            camera_node::clean_card(&n.name)
                        } else {
                            k.info.display_name()
                        }),
                        _ if chosen(&path) => ask(n),
                        verdict => {
                            tracing::trace!(path, ?verdict, "not a camera (PipeWire)");
                            None
                        }
                    },
                    None => ask(n),
                },
            }?;
            Some((path, name))
        })
        .collect()
}

/// What opening nodes found: path -> (the node's fingerprint, its name if
/// it is a camera).
static PROBED: std::sync::Mutex<Vec<(String, String, Option<String>)>> =
    std::sync::Mutex::new(Vec::new());

/// Whether a node sysfs and PipeWire don't describe is a camera: what an
/// earlier probe of it found, else (where `probe` allows) what opening it
/// tells.
fn probe_node(n: &SysNode, probe: Probe) -> Option<String> {
    let path = format!("/dev/{}", n.node);
    let fingerprint = n.fingerprint();
    let mut probed = PROBED.lock().unwrap_or_else(|e| e.into_inner());
    if let Some((_, _, name)) = probed
        .iter()
        .find(|(p, f, _)| *p == path && *f == fingerprint)
    {
        return name.clone();
    }
    if !probe.allows(&path) {
        return None;
    }
    let dev = match Device::with_path(&path) {
        Ok(d) => d,
        // A camera you may not open is still there (Teams lists it and
        // reports "Teams needs permission to use this device"). Not kept:
        // the permission may change.
        Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
            return camera_node::unopenable_camera(&n.node);
        }
        Err(_) => return None,
    };
    let name = match camera_node::query(&dev) {
        Ok(info) => match info.verdict() {
            Verdict::Camera => Some(info.display_name()),
            verdict => {
                tracing::trace!(path, driver = info.driver, ?verdict, "not a camera");
                None
            }
        },
        // Not kept either: a failed query says nothing about the node, so
        // the next list shown asks again.
        Err(e) => {
            tracing::debug!(path, "camera node query failed: {e}");
            return None;
        }
    };
    drop(dev);
    tracing::debug!(path, camera = ?name, "camera node asked");
    probed.retain(|(p, _, _)| *p != path);
    probed.push((path, fingerprint, name.clone()));
    name
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
        Self::start_cancellable(device, width, height, fps, None)
    }

    /// As [`start`](Self::start); setting `cancel` while a PipeWire camera
    /// is still being linked ends that and fails.
    pub fn start_cancellable(
        device: Option<&str>,
        width: u32,
        height: u32,
        fps: u32,
        cancel: Option<&AtomicBool>,
    ) -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        if device == Some(AVATAR_DEVICE) {
            return Ok(Self::avatar(width, height, fps));
        }
        let pw = camera_pw::cameras(PIPEWIRE_WAIT).unwrap_or_default();
        let id = match device {
            Some(d) => d.to_string(),
            None => match first_of(&pw) {
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
            Some(cam) => Self::start_pipewire(&cam, width, height, fps, cancel),
            // Through the portal only (see v4l2_fallback).
            None if camera_pw::use_portal() => {
                super::device_health::note_camera(if camera_pw::denied() {
                    super::device_health::Open::Permission
                } else {
                    super::device_health::Open::Failed
                });
                anyhow::bail!("The camera portal doesn't offer {id}")
            }
            None => Self::start_v4l2(&id, width, height, fps),
        }
    }

    fn start_pipewire(
        cam: &PwCamera,
        width: u32,
        height: u32,
        fps: u32,
        cancel: Option<&AtomicBool>,
    ) -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        if let Some(path) = &cam.v4l2_path {
            // Teams' "Automatically adjust camera controls", where chosen.
            super::camera_controls::apply_preferred(path);
        }
        let (tx, rx) = mpsc::sync_channel::<YuvFrame>(2);
        let stop = Arc::new(AtomicBool::new(false));
        let run = super::device_health::camera_started();
        match camera_pw::capture(cam, width, height, fps, tx, stop.clone(), cancel) {
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

        // The best of the modes it offers (camera_mode; a loopback device
        // fed already offers just its producer's). Without a list, the
        // best format at the size asked, as the driver rounds it.
        let mut fmt = dev
            .format()
            .inspect_err(|_| failed())
            .context("Failed to get camera format")?;
        let mut modes = v4l2_modes(&dev, (width, height), fps);
        camera_mode::order(&mut modes, (width, height), fps);
        let mode = modes.first().copied();
        if let Some(m) = mode {
            tracing::info!(
                path,
                modes = modes.len(),
                fourcc = %m.format,
                m.width,
                m.height,
                fps = format!("{}/{}", m.fps_num, m.fps_den),
                "camera mode"
            );
            fmt.fourcc = m.format;
            fmt.width = m.width;
            fmt.height = m.height;
        } else {
            let offered: Vec<FourCC> = dev
                .enum_formats()
                .map(|f| f.into_iter().map(|d| d.fourcc).collect())
                .unwrap_or_default();
            if let Some(best) = offered
                .iter()
                .filter(|c| PixelFormat::from_fourcc(&c.repr).is_some())
                .min_by_key(|c| {
                    PixelFormat::from_fourcc(&c.repr).map_or(u8::MAX, PixelFormat::rank)
                })
            {
                fmt.fourcc = *best;
            }
            fmt.width = width;
            fmt.height = height;
        }
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
            params.interval = match mode {
                Some(m) if m.fps_num > 0 && m.fps_den > 0 => {
                    v4l::Fraction::new(m.fps_den, m.fps_num)
                }
                _ => v4l::Fraction::new(1, fps),
            };
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

/// The modes an open V4L2 node offers in the formats OST reads (a
/// stepwise size or rate taken at `want` / `fps` within it).
fn v4l2_modes(dev: &Device, want: (u32, u32), fps: u32) -> Vec<camera_mode::Mode<FourCC>> {
    use v4l::frameinterval::FrameIntervalEnum;
    use v4l::framesize::FrameSizeEnum;
    let mut out = Vec::new();
    for desc in dev.enum_formats().unwrap_or_default() {
        let Some(pixel) = PixelFormat::from_fourcc(&desc.fourcc.repr) else {
            continue;
        };
        for size in dev.enum_framesizes(desc.fourcc).unwrap_or_default() {
            let (w, h) = match size.size {
                FrameSizeEnum::Discrete(d) => (d.width, d.height),
                FrameSizeEnum::Stepwise(s) => (
                    camera_mode::in_range(want.0, s.min_width, s.max_width, s.step_width),
                    camera_mode::in_range(want.1, s.min_height, s.max_height, s.step_height),
                ),
            };
            let mode = |fps_num, fps_den| camera_mode::Mode {
                format: desc.fourcc,
                pixel,
                width: w,
                height: h,
                fps_num,
                fps_den,
            };
            let rates = dev
                .enum_frameintervals(desc.fourcc, w, h)
                .unwrap_or_default();
            if rates.is_empty() {
                out.push(mode(0, 1));
            }
            for r in rates {
                match r.interval {
                    // An interval: frames per second is its inverse.
                    FrameIntervalEnum::Discrete(f) => out.push(mode(f.denominator, f.numerator)),
                    FrameIntervalEnum::Stepwise(s) => {
                        let rate = |f: v4l::Fraction| {
                            if f.numerator == 0 {
                                0
                            } else {
                                f.denominator / f.numerator
                            }
                        };
                        // The longest interval is the lowest rate.
                        let (lo, hi) = (rate(s.max), rate(s.min));
                        out.push(mode(fps.clamp(lo.min(hi), hi.max(lo)).max(1), 1));
                    }
                }
            }
        }
    }
    out
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

    fn sys(node: &str, name: &str, driver: Option<&str>, udev: &str, dev: u64) -> SysNode {
        SysNode {
            node: node.into(),
            number: node.trim_start_matches("video").parse().unwrap(),
            name: name.into(),
            index: Some(0),
            dev: Some(dev),
            driver: driver.map(str::to_string),
            virtual_node: driver.is_none(),
            loopback: driver.is_none(),
            loopback_state: driver.is_none().then(|| "capture".to_string()),
            loopback_format: None,
            udev_caps: Some(udev.into()),
            ..Default::default()
        }
    }

    /// linuxlt's nodes: the UVC camera PipeWire offers, its metadata node,
    /// a loopback PipeWire found idle (so offers no node for) and a
    /// capture-card node; an IPU6 ISYS node PipeWire describes. Only the
    /// capture card would be opened, and only when probing is allowed.
    #[test]
    fn v4l2_list_opens_only_nodes_nothing_describes() {
        let nodes = [
            sys(
                "video0",
                "Integrated Camera: Integrated C",
                Some("uvcvideo"),
                ":capture:",
                20736,
            ),
            SysNode {
                index: Some(1),
                ..sys(
                    "video1",
                    "Integrated Camera: Integrated C",
                    Some("uvcvideo"),
                    ":",
                    20737,
                )
            },
            sys(
                "video3",
                "Intel IPU6 ISYS Capture 0",
                Some("intel-ipu6-isys"),
                ":capture:",
                20739,
            ),
            sys("video5", "BT878 video", Some("bttv"), ":capture:", 20741),
            sys(
                "video20",
                "OST test camera A",
                None,
                ":video_output:",
                20738,
            ),
        ];
        let pw = [pw("v4l2_input.usb", Some("/dev/video0"), &[20736])];
        let known = [PwV4l2Node {
            path: "/dev/video3".into(),
            devids: vec![20739],
            info: camera_node::NodeInfo {
                driver: "isys".into(),
                card: "ipu6".into(),
                capabilities: 0xa480_0001,
                device_caps: 0x2480_0001,
                ..Default::default()
            },
        }];
        let mut asked = Vec::new();
        let list = v4l2_cameras(
            &nodes,
            &pw,
            &known,
            |_| false,
            |n| {
                asked.push(n.node.clone());
                Some("BT878 video".into())
            },
        );
        assert_eq!(asked, ["video5"]);
        assert_eq!(
            list,
            [
                ("/dev/video5".to_string(), "BT878 video".to_string()),
                ("/dev/video20".to_string(), "OST test camera A".to_string()),
            ]
        );
        // PipeWire not there: the UVC camera from sysfs, still unopened.
        let mut asked = Vec::new();
        let list = v4l2_cameras(
            &nodes,
            &[],
            &[],
            |_| false,
            |n| {
                asked.push(n.node.clone());
                None
            },
        );
        assert_eq!(asked, ["video3", "video5"]);
        let paths: Vec<&str> = list.iter().map(|(p, _)| p.as_str()).collect();
        assert_eq!(paths, ["/dev/video0", "/dev/video20"]);
        assert_eq!(list[0].1, "Integrated Camera");
    }

    /// The chosen camera is asked even when sysfs or PipeWire say it isn't
    /// one (a loopback whose recorded state is stale, an IPU6 node PipeWire
    /// judged); other nodes they describe as no camera are never opened.
    #[test]
    fn the_chosen_camera_is_asked_even_when_described_as_none() {
        let idle = SysNode {
            loopback_state: Some("output".into()),
            ..sys(
                "video21",
                "OST test camera B",
                None,
                ":video_output:",
                20739,
            )
        };
        let meta = SysNode {
            index: Some(1),
            ..sys(
                "video1",
                "Integrated Camera: Integrated C",
                Some("uvcvideo"),
                ":",
                20737,
            )
        };
        let isys = sys(
            "video3",
            "Intel IPU6 ISYS Capture 0",
            Some("isys"),
            ":capture:",
            20740,
        );
        let known = [PwV4l2Node {
            path: "/dev/video3".into(),
            devids: vec![20740],
            info: camera_node::NodeInfo {
                driver: "isys".into(),
                capabilities: 0xa480_0001,
                device_caps: 0x2480_0001,
                ..Default::default()
            },
        }];
        let nodes = [meta, isys, idle];
        let run = |chosen: &[&str]| {
            let mut asked = Vec::new();
            let list = v4l2_cameras(
                &nodes,
                &[],
                &known,
                |p| chosen.contains(&p),
                |n| {
                    asked.push(n.node.clone());
                    (n.node == "video21").then(|| "OST test camera B".to_string())
                },
            );
            (asked, list)
        };
        let (asked, list) = run(&[]);
        assert!(asked.is_empty() && list.is_empty());
        let (asked, list) = run(&["/dev/video21"]);
        assert_eq!(asked, ["video21"]);
        assert_eq!(
            list,
            [("/dev/video21".to_string(), "OST test camera B".to_string())]
        );
        let (asked, _) = run(&["/dev/video3"]);
        assert_eq!(asked, ["video3"]);
        assert!(Probe::These(&["/dev/video21"]).names("/dev/video21"));
        assert!(!Probe::All.names("/dev/video21"));
    }

    #[test]
    fn probing_is_allowed_for_the_list_shown_or_the_chosen_camera() {
        assert!(!Probe::Nothing.allows("/dev/video5"));
        assert!(Probe::All.allows("/dev/video5"));
        let chosen = Probe::These(&["/dev/video5", "pipewire:x"]);
        assert!(chosen.allows("/dev/video5"));
        assert!(!chosen.allows("/dev/video6"));
        // An unprobed node isn't opened when probing isn't allowed.
        let n = sys("video97", "Nothing", Some("bttv"), ":capture:", 1);
        assert_eq!(probe_node(&n, Probe::Nothing), None);
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
