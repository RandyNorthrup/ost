//! Cameras from PipeWire, as Chromium (and so Teams on the web) and other
//! current Linux apps get them: PipeWire's Video/Source camera nodes cover
//! UVC webcams (WirePlumber's V4L2 monitor) and cameras only libcamera can
//! drive, such as Intel IPU6 laptop cameras, with proper names. In the
//! Flatpak the connection comes from the desktop's Camera portal
//! (org.freedesktop.portal.Camera), which asks the person once and then
//! exposes only the cameras; `OST_CAMERA_PORTAL=1` uses it outside the
//! Flatpak too.
//!
//! A monitor thread keeps a live list (cameras plugged in or removed show
//! up the next time the list is read); each capture runs its own stream.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock, mpsc};
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use pipewire as pw;
use pw::spa;

use super::camera::YuvFrame;
use super::camera_node::{NodeInfo, Verdict};
use super::pixfmt::{self, PixelFormat, Plane};

/// A PipeWire object's properties.
pub type Props = HashMap<String, String>;

/// A camera PipeWire offers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PwCamera {
    /// Its global id on the PipeWire server.
    pub id: u32,
    /// object.serial, which a stream targets.
    pub serial: String,
    /// node.name, stable across restarts (what Settings keeps).
    pub node_name: String,
    pub name: String,
    /// device.api: "v4l2", "libcamera" or empty (a virtual camera).
    pub api: String,
    /// The V4L2 node behind it, for a V4L2 camera.
    pub v4l2_path: Option<String>,
    /// The device numbers (dev_t) of the kernel nodes it uses.
    pub devids: Vec<u64>,
    /// A virtual camera (v4l2loopback, a PipeWire video source an app
    /// makes): listed after real ones.
    pub virtual_camera: bool,
}

const SUFFIXES: [&str; 2] = [" (V4L2)", " (libcamera)"];

/// The camera a Video/Source node is (with its device's properties), or
/// `None` when it isn't one: a screen-cast or other video stream, or a
/// V4L2 node that can't deliver a picture by itself (IPU6 ISYS and other
/// media-controller nodes, metadata nodes), judged by the same rules as
/// OST's own V4L2 list.
pub fn camera_of(id: u32, node: &Props, device: Option<&Props>) -> Option<PwCamera> {
    let get = |k: &str| {
        node.get(k)
            .or_else(|| device.and_then(|d| d.get(k)))
            .map(String::as_str)
            .filter(|v| !v.is_empty())
    };
    if node.get("media.class").map(String::as_str) != Some("Video/Source") {
        return None;
    }
    let api = get("device.api").unwrap_or_default();
    let role = node.get("media.role").map(String::as_str);
    if role == Some("Screen") || (role != Some("Camera") && !matches!(api, "v4l2" | "libcamera")) {
        return None;
    }
    if api == "v4l2" {
        let hex =
            |k: &str| get(k).and_then(|v| u32::from_str_radix(v.trim_start_matches("0x"), 16).ok());
        if let (Some(capabilities), Some(device_caps)) = (
            hex("api.v4l2.cap.capabilities"),
            hex("api.v4l2.cap.device-caps"),
        ) {
            let info = NodeInfo {
                driver: get("api.v4l2.cap.driver").unwrap_or_default().to_string(),
                card: get("api.v4l2.cap.card").unwrap_or_default().to_string(),
                bus_info: get("api.v4l2.cap.bus_info").unwrap_or_default().to_string(),
                capabilities,
                device_caps,
                formats: None,
            };
            let verdict = info.verdict();
            if verdict != Verdict::Camera {
                tracing::debug!(node = ?node.get("node.name"), ?verdict, "PipeWire V4L2 node is no camera");
                return None;
            }
        }
    }
    let description = node
        .get("node.description")
        .map(|d| {
            SUFFIXES
                .iter()
                .fold(d.as_str(), |d, s| d.strip_suffix(s).unwrap_or(d))
                .trim()
                .to_string()
        })
        .filter(|d| !d.is_empty());
    let name = description
        .or_else(|| get("node.nick").map(str::to_string))
        .or_else(|| get("device.description").map(str::to_string))
        .or_else(|| node.get("node.name").cloned())?;
    Some(PwCamera {
        id,
        serial: node
            .get("object.serial")
            .cloned()
            .unwrap_or_else(|| id.to_string()),
        node_name: node.get("node.name")?.clone(),
        name,
        api: api.to_string(),
        v4l2_path: get("api.v4l2.path").map(str::to_string),
        devids: get("device.devids").map(parse_devids).unwrap_or_default(),
        virtual_camera: api.is_empty() || get("api.v4l2.cap.driver") == Some("v4l2 loopback"),
    })
}

/// "[ 20736 20737 ]" (PipeWire's device.devids) as numbers.
fn parse_devids(s: &str) -> Vec<u64> {
    s.trim_matches(|c| c == '[' || c == ']')
        .split([' ', ','])
        .filter_map(|n| n.trim().parse().ok())
        .collect()
}

/// The cameras among PipeWire's nodes (id → props) and devices: real
/// cameras first (the first is the default), by V4L2 node, then virtual
/// ones. A UVC camera WirePlumber offers both through V4L2 and libcamera
/// (they share kernel nodes) is listed once, as its V4L2 node.
pub fn cameras_from(nodes: &HashMap<u32, Props>, devices: &HashMap<u32, Props>) -> Vec<PwCamera> {
    let mut list: Vec<PwCamera> = nodes
        .iter()
        .filter_map(|(id, n)| {
            let device = n
                .get("device.id")
                .and_then(|d| d.parse::<u32>().ok())
                .and_then(|d| devices.get(&d));
            camera_of(*id, n, device)
        })
        .collect();
    let node_number = |c: &PwCamera| {
        c.v4l2_path
            .as_deref()
            .and_then(|p| p.strip_prefix("/dev/video"))
            .and_then(|n| n.parse::<u32>().ok())
            // Cameras without a V4L2 node (libcamera's, an app's) after.
            .unwrap_or(u32::MAX)
    };
    list.sort_by_key(|c| (c.virtual_camera, node_number(c), c.id));
    let v4l2_ids: Vec<u64> = list
        .iter()
        .filter(|c| c.api == "v4l2")
        .flat_map(|c| c.devids.iter().copied())
        .collect();
    list.retain(|c| c.api != "libcamera" || !c.devids.iter().any(|d| v4l2_ids.contains(d)));
    // A node's info can arrive twice under one name only by mistake; keep
    // the first.
    let mut seen = Vec::new();
    list.retain(|c| {
        let new = !seen.contains(&c.node_name);
        seen.push(c.node_name.clone());
        new
    });
    list
}

/// Whether cameras come through the Camera portal.
pub fn use_portal() -> bool {
    std::path::Path::new("/.flatpak-info").exists()
        || std::env::var("OST_CAMERA_PORTAL").is_ok_and(|v| v == "1")
}

/// The person allowed the camera (in this run).
static ACCESS: AtomicBool = AtomicBool::new(false);
/// The person refused it: don't ask again in this run.
static DENIED: AtomicBool = AtomicBool::new(false);

/// Whether the portal refused camera access.
pub fn denied() -> bool {
    DENIED.load(Ordering::Relaxed)
}

/// A PipeWire connection with the cameras on it, from the Camera portal
/// (asking for access the first time). Call it off any async runtime.
fn portal_remote() -> Result<std::os::fd::OwnedFd> {
    if denied() {
        anyhow::bail!("Camera access was denied");
    }
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    rt.block_on(async {
        let camera = ashpd::desktop::camera::Camera::new()
            .await
            .context("The desktop's camera portal isn't available")?;
        if !ACCESS.load(Ordering::Relaxed) {
            let reply = camera.request_access(Default::default()).await?.response();
            if let Err(e) = reply {
                DENIED.store(true, Ordering::Relaxed);
                return Err(anyhow!(e).context("Camera access was denied"));
            }
            ACCESS.store(true, Ordering::Relaxed);
            tracing::info!("camera portal: access granted");
        }
        Ok(camera.open_pipe_wire_remote(Default::default()).await?)
    })
}

fn connect(context: &pw::context::ContextRc) -> Result<pw::core::CoreRc> {
    if use_portal() {
        let fd = portal_remote()?;
        Ok(context.connect_fd_rc(fd, None)?)
    } else {
        Ok(context.connect_rc(None)?)
    }
}

#[derive(Clone)]
enum Snapshot {
    Starting,
    Ready(Vec<PwCamera>),
    Unavailable,
}

struct Shared {
    state: Mutex<Snapshot>,
    changed: Condvar,
}

impl Shared {
    fn set(&self, s: Snapshot) {
        *self.state.lock().unwrap_or_else(|e| e.into_inner()) = s;
        self.changed.notify_all();
    }
}

fn shared() -> &'static Shared {
    static SHARED: OnceLock<&'static Shared> = OnceLock::new();
    SHARED.get_or_init(|| {
        let s: &'static Shared = Box::leak(Box::new(Shared {
            state: Mutex::new(Snapshot::Starting),
            changed: Condvar::new(),
        }));
        if let Err(e) = std::thread::Builder::new()
            .name("ost-cameras".into())
            .spawn(move || monitor(s))
        {
            tracing::warn!("camera monitor: {e}");
            s.set(Snapshot::Unavailable);
        }
        s
    })
}

/// PipeWire's cameras, waiting up to `wait` for the first list; `None`
/// when PipeWire (or the portal) isn't there or refused.
pub fn cameras(wait: Duration) -> Option<Vec<PwCamera>> {
    let s = shared();
    let guard = s.state.lock().unwrap_or_else(|e| e.into_inner());
    let (guard, _) = s
        .changed
        .wait_timeout_while(guard, wait, |st| matches!(st, Snapshot::Starting))
        .unwrap_or_else(|e| e.into_inner());
    match &*guard {
        Snapshot::Ready(list) => Some(list.clone()),
        _ => None,
    }
}

/// Keep the list current, reconnecting when PipeWire restarts.
fn monitor(s: &'static Shared) {
    let mut backoff = Duration::from_secs(2);
    let mut logged = false;
    loop {
        let e = watch(s).unwrap_err();
        if !logged {
            tracing::info!("PipeWire cameras: {e:#}");
            logged = true;
        }
        s.set(Snapshot::Unavailable);
        if denied() {
            return;
        }
        std::thread::sleep(backoff);
        backoff = (backoff * 2).min(Duration::from_secs(30));
    }
}

/// Watch PipeWire's camera nodes until the connection ends.
fn watch(s: &'static Shared) -> Result<()> {
    use pw::types::ObjectType;
    type Map = Rc<RefCell<HashMap<u32, Props>>>;
    fn own(dict: Option<&pw::spa::utils::dict::DictRef>) -> Props {
        dict.map(|d| {
            d.iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect()
        })
        .unwrap_or_default()
    }

    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = connect(&context)?;
    let registry = core.get_registry_rc()?;
    let nodes: Map = Rc::default();
    let devices: Map = Rc::default();
    let keep: Rc<RefCell<HashMap<u32, Box<dyn std::any::Any>>>> = Rc::default();
    let pending: Rc<RefCell<Vec<pw::spa::utils::result::AsyncSeq>>> = Rc::default();
    let synced = Rc::new(Cell::new(false));
    pending.borrow_mut().push(core.sync(0)?);

    let publish: Rc<dyn Fn()> = {
        let (nodes, devices, synced) = (nodes.clone(), devices.clone(), synced.clone());
        Rc::new(move || {
            if synced.get() {
                let list = cameras_from(&nodes.borrow(), &devices.borrow());
                tracing::debug!(cameras = list.len(), "PipeWire cameras");
                s.set(Snapshot::Ready(list));
            }
        })
    };

    let _core_listener = core
        .add_listener_local()
        .done({
            let (pending, synced, publish) = (pending.clone(), synced.clone(), publish.clone());
            move |id, seq| {
                if id != pw::core::PW_ID_CORE {
                    return;
                }
                let mut p = pending.borrow_mut();
                p.retain(|s| *s != seq);
                if p.is_empty() && !synced.get() {
                    drop(p);
                    synced.set(true);
                    publish();
                }
            }
        })
        .error({
            let mainloop = mainloop.clone();
            move |id, _seq, res, message| {
                if id == pw::core::PW_ID_CORE {
                    tracing::info!(res, message, "PipeWire connection lost");
                    mainloop.quit();
                }
            }
        })
        .register();

    let _registry_listener = registry
        .add_listener_local()
        .global({
            let (nodes, devices, keep, pending, synced, publish) = (
                nodes.clone(),
                devices.clone(),
                keep.clone(),
                pending.clone(),
                synced.clone(),
                publish.clone(),
            );
            let (registry, core) = (registry.clone(), core.clone());
            move |global| {
                let prop = |k: &str| global.props.and_then(|p| p.get(k)).unwrap_or("");
                let id = global.id;
                match global.type_ {
                    ObjectType::Node if prop("media.class") == "Video/Source" => {
                        let Ok(node) = registry.bind::<pw::node::Node, _>(global) else {
                            return;
                        };
                        let (nodes, publish) = (nodes.clone(), publish.clone());
                        let listener = node
                            .add_listener_local()
                            .info(move |info| {
                                if let Some(props) = info.props() {
                                    nodes.borrow_mut().insert(id, own(Some(props)));
                                    publish();
                                }
                            })
                            .register();
                        keep.borrow_mut().insert(id, Box::new((node, listener)));
                    }
                    ObjectType::Device
                        if prop("media.class") == "Video/Device"
                            || matches!(prop("device.api"), "v4l2" | "libcamera") =>
                    {
                        let Ok(device) = registry.bind::<pw::device::Device, _>(global) else {
                            return;
                        };
                        let (devices, publish) = (devices.clone(), publish.clone());
                        let listener = device
                            .add_listener_local()
                            .info(move |info| {
                                if let Some(props) = info.props() {
                                    devices.borrow_mut().insert(id, own(Some(props)));
                                    publish();
                                }
                            })
                            .register();
                        keep.borrow_mut().insert(id, Box::new((device, listener)));
                    }
                    _ => return,
                }
                // Before the first list: another round trip brings the
                // bound object's info.
                if !synced.get()
                    && let Ok(seq) = core.sync(0)
                {
                    pending.borrow_mut().push(seq);
                }
            }
        })
        .global_remove({
            let (nodes, devices, keep, publish) = (
                nodes.clone(),
                devices.clone(),
                keep.clone(),
                publish.clone(),
            );
            move |id| {
                let gone = nodes.borrow_mut().remove(&id).is_some()
                    | devices.borrow_mut().remove(&id).is_some();
                keep.borrow_mut().remove(&id);
                if gone {
                    publish();
                }
            }
        })
        .register();

    mainloop.run();
    Err(anyhow!("PipeWire connection ended"))
}

/// The SPA video formats a camera stream takes, best first, and how
/// OST reads each.
fn raw_formats() -> [(spa::param::video::VideoFormat, PixelFormat); 17] {
    use PixelFormat::{Rgb24, Rgb32};
    use spa::param::video::VideoFormat as V;
    [
        (V::YUY2, pixfmt::YUYV),
        (V::NV12, PixelFormat::Nv12),
        (V::I420, PixelFormat::I420),
        (V::YV12, PixelFormat::Yv12),
        (V::NV21, PixelFormat::Nv21),
        (V::UYVY, pixfmt::UYVY),
        (V::YVYU, pixfmt::YVYU),
        (V::BGRx, Rgb32 { r: 2, g: 1, b: 0 }),
        (V::BGRA, Rgb32 { r: 2, g: 1, b: 0 }),
        (V::RGBx, Rgb32 { r: 0, g: 1, b: 2 }),
        (V::RGBA, Rgb32 { r: 0, g: 1, b: 2 }),
        (V::xRGB, Rgb32 { r: 1, g: 2, b: 3 }),
        (V::ARGB, Rgb32 { r: 1, g: 2, b: 3 }),
        (V::xBGR, Rgb32 { r: 3, g: 2, b: 1 }),
        (V::ABGR, Rgb32 { r: 3, g: 2, b: 1 }),
        (V::RGB, Rgb24 { r: 0, g: 1, b: 2 }),
        (V::BGR, Rgb24 { r: 2, g: 1, b: 0 }),
    ]
}

/// An EnumFormat pod: raw video in the formats OST reads, or MJPG; sizes
/// up to `max`, preferring `want`; frame rates around `fps`.
fn format_pod(mjpg: bool, want: (u32, u32), max: (u32, u32), fps: u32) -> Result<Vec<u8>> {
    use spa::param::format::{FormatProperties as F, MediaSubtype, MediaType};
    use spa::pod::{ChoiceValue, Object, Property, PropertyFlags, Value};
    use spa::utils::{Choice, ChoiceEnum, ChoiceFlags, Fraction, Id, Rectangle};
    let prop = |key: F, value: Value| Property {
        key: key.as_raw(),
        flags: PropertyFlags::empty(),
        value,
    };
    let rect = |(width, height): (u32, u32)| Rectangle { width, height };
    let mut properties = vec![
        prop(F::MediaType, Value::Id(Id(MediaType::Video.as_raw()))),
        prop(
            F::MediaSubtype,
            Value::Id(Id(if mjpg {
                MediaSubtype::Mjpg
            } else {
                MediaSubtype::Raw
            }
            .as_raw())),
        ),
    ];
    if !mjpg {
        let ids: Vec<Id> = raw_formats().iter().map(|(v, _)| Id(v.as_raw())).collect();
        properties.push(prop(
            F::VideoFormat,
            Value::Choice(ChoiceValue::Id(Choice(
                ChoiceFlags::empty(),
                ChoiceEnum::Enum {
                    default: ids[0],
                    alternatives: ids,
                },
            ))),
        ));
    }
    properties.push(prop(
        F::VideoSize,
        Value::Choice(ChoiceValue::Rectangle(Choice(
            ChoiceFlags::empty(),
            ChoiceEnum::Range {
                default: rect((want.0.min(max.0), want.1.min(max.1))),
                min: rect((16, 16)),
                max: rect(max),
            },
        ))),
    ));
    properties.push(prop(
        F::VideoFramerate,
        Value::Choice(ChoiceValue::Fraction(Choice(
            ChoiceFlags::empty(),
            ChoiceEnum::Range {
                default: Fraction { num: fps, denom: 1 },
                min: Fraction { num: 0, denom: 1 },
                max: Fraction { num: 120, denom: 1 },
            },
        ))),
    ));
    serialize(Object {
        type_: spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
        id: spa::param::ParamType::EnumFormat.as_raw(),
        properties,
    })
}

/// Buffers OST can read without a GPU: memory it can map.
fn buffers_pod() -> Result<Vec<u8>> {
    use spa::pod::{ChoiceValue, Object, Property, PropertyFlags, Value};
    use spa::utils::{Choice, ChoiceEnum, ChoiceFlags};
    let types = (1 << spa::sys::SPA_DATA_MemPtr) | (1 << spa::sys::SPA_DATA_MemFd);
    serialize(Object {
        type_: spa::utils::SpaTypes::ObjectParamBuffers.as_raw(),
        id: spa::param::ParamType::Buffers.as_raw(),
        properties: vec![Property {
            key: spa::sys::SPA_PARAM_BUFFERS_dataType,
            flags: PropertyFlags::empty(),
            value: Value::Choice(ChoiceValue::Int(Choice(
                ChoiceFlags::empty(),
                ChoiceEnum::Flags {
                    default: types,
                    flags: vec![],
                },
            ))),
        }],
    })
}

fn serialize(object: spa::pod::Object) -> Result<Vec<u8>> {
    Ok(spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(object),
    )
    .map_err(|e| anyhow!("pod: {e:?}"))?
    .0
    .into_inner())
}

/// Capture from `cam`, sending frames no bigger than `width`x`height` to
/// `tx` until `stop`. Returns once the stream is linked to the camera (or
/// has failed to be).
pub fn capture(
    cam: &PwCamera,
    width: u32,
    height: u32,
    fps: u32,
    tx: mpsc::SyncSender<YuvFrame>,
    stop: Arc<AtomicBool>,
) -> Result<std::thread::JoinHandle<()>> {
    let (ready_tx, ready_rx) = mpsc::channel::<Result<()>>();
    let cam = cam.clone();
    let handle = std::thread::Builder::new()
        .name("ost-camera-pw".into())
        .spawn(move || {
            let ready = ready_tx.clone();
            if let Err(e) = stream(&cam, (width, height), fps, tx, &stop, ready_tx) {
                tracing::warn!(camera = cam.node_name, "PipeWire camera: {e:#}");
                super::device_health::note_camera(if denied() {
                    super::device_health::Open::Permission
                } else {
                    super::device_health::Open::Failed
                });
                let _ = ready.send(Err(e));
            }
        })?;
    match ready_rx.recv_timeout(Duration::from_secs(5)) {
        Ok(Err(e)) => Err(e),
        // Linked, or still negotiating (frames will tell).
        Ok(Ok(())) | Err(mpsc::RecvTimeoutError::Timeout) => Ok(handle),
        Err(mpsc::RecvTimeoutError::Disconnected) => Ok(handle),
    }
}

fn stream(
    cam: &PwCamera,
    want: (u32, u32),
    fps: u32,
    tx: mpsc::SyncSender<YuvFrame>,
    stop: &Arc<AtomicBool>,
    ready: mpsc::Sender<Result<()>>,
) -> Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = connect(&context)?;
    let stream = pw::stream::StreamBox::new(
        &core,
        "ost-camera",
        pw::properties::properties! {
            *pw::keys::MEDIA_TYPE => "Video",
            *pw::keys::MEDIA_CATEGORY => "Capture",
            *pw::keys::MEDIA_ROLE => "Camera",
            *pw::keys::TARGET_OBJECT => cam.serial.as_str(),
            // This camera or none: never another one in its place.
            "node.dont-fallback" => "true",
            *pw::keys::NODE_DONT_RECONNECT => "true",
        },
    )?;
    struct Negotiated {
        fmt: Option<PixelFormat>,
        width: u32,
        height: u32,
        first: bool,
    }
    let ended = stop.clone();
    let unused = stop.clone();
    let ready_state = ready.clone();
    let name = cam.node_name.clone();
    let _listener = stream
        .add_local_listener_with_user_data(Negotiated {
            fmt: None,
            width: 0,
            height: 0,
            first: true,
        })
        .state_changed(move |_, _, old, new| {
            tracing::debug!(camera = name, ?old, ?new, "PipeWire camera stream");
            match new {
                pw::stream::StreamState::Paused | pw::stream::StreamState::Streaming => {
                    let _ = ready_state.send(Ok(()));
                }
                pw::stream::StreamState::Error(e) => {
                    let _ = ready_state.send(Err(anyhow!("the camera's stream failed: {e}")));
                    super::device_health::note_camera(super::device_health::Open::Failed);
                    ended.store(true, Ordering::Relaxed);
                }
                pw::stream::StreamState::Unconnected => {
                    let _ = ready_state.send(Err(anyhow!("the camera isn't there")));
                    ended.store(true, Ordering::Relaxed);
                }
                pw::stream::StreamState::Connecting => {}
            }
        })
        .param_changed(|stream, n, id, param| {
            let Some(param) = param else { return };
            if id != spa::param::ParamType::Format.as_raw() {
                return;
            }
            let Ok((media, sub)) = spa::param::format_utils::parse_format(param) else {
                return;
            };
            if media != spa::param::format::MediaType::Video {
                return;
            }
            if sub == spa::param::format::MediaSubtype::Mjpg {
                n.fmt = Some(PixelFormat::Mjpg);
                tracing::info!("PipeWire camera format: MJPG");
            } else {
                let mut info = spa::param::video::VideoInfoRaw::default();
                if info.parse(param).is_err() {
                    return;
                }
                n.fmt = raw_formats()
                    .iter()
                    .find(|(v, _)| *v == info.format())
                    .map(|(_, p)| *p);
                (n.width, n.height) = (info.size().width, info.size().height);
                tracing::info!(format = ?info.format(), n.width, n.height, "PipeWire camera format");
            }
            if let Ok(bytes) = buffers_pod()
                && let Some(pod) = spa::pod::Pod::from_bytes(&bytes)
            {
                let _ = stream.update_params(&mut [pod]);
            }
        })
        .process(move |stream, n| {
            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };
            let Some(fmt) = n.fmt else { return };
            let (w, h) = (n.width, n.height);
            let datas = buffer.datas_mut();
            let mut planes: Vec<Plane<'_>> = Vec::with_capacity(datas.len());
            for (i, d) in datas.iter_mut().enumerate() {
                let (offset, size, stride) = {
                    let c = d.chunk();
                    (c.offset() as usize, c.size() as usize, c.stride())
                };
                let Some(bytes) = d.data() else { break };
                let bytes: &[u8] = bytes;
                let end = if size == 0 {
                    bytes.len()
                } else {
                    (offset + size).min(bytes.len())
                };
                let Some(slice) = bytes.get(offset.min(end)..end) else {
                    break;
                };
                let stride = match (stride, fmt, i) {
                    (s, _, _) if s > 0 => s as usize,
                    (_, _, 0) => pixfmt::min_stride(fmt, w),
                    (_, PixelFormat::Nv12 | PixelFormat::Nv21, _) => w as usize,
                    _ => w as usize / 2,
                };
                planes.push(Plane {
                    data: slice,
                    stride,
                });
            }
            let need = match fmt {
                PixelFormat::I420 | PixelFormat::Yv12 => 3,
                PixelFormat::Nv12 | PixelFormat::Nv21 => 2,
                _ => 1,
            };
            let frame = if planes.len() >= need {
                pixfmt::to_i420(fmt, w, h, &planes[..need])
            } else if let Some(p) = planes.first() {
                pixfmt::to_i420(fmt, w, h, &pixfmt::split(fmt, h, p.data, p.stride))
            } else {
                None
            };
            let Some(frame) = frame else { return };
            if n.first {
                n.first = false;
                tracing::info!(w = frame.width, h = frame.height, "PipeWire camera: first frame");
            }
            if !super::camera::deliver(super::camera::fit(frame, want), &tx) {
                // Nobody takes frames any more.
                unused.store(true, Ordering::Relaxed);
            }
        })
        .register()?;

    // Preferred: raw at about the size asked; then raw up to twice that;
    // then any raw size; then Motion JPEG.
    let twice = (want.0 * 2, want.1 * 2);
    let pods = [
        format_pod(false, want, want, fps)?,
        format_pod(false, want, twice, fps)?,
        format_pod(false, want, (8192, 8192), fps)?,
        format_pod(true, want, twice, fps)?,
        format_pod(true, want, (8192, 8192), fps)?,
    ];
    let mut params: Vec<&spa::pod::Pod> = pods
        .iter()
        .map(|b| spa::pod::Pod::from_bytes(b).context("format pod"))
        .collect::<Result<_>>()?;
    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;
    tracing::info!(
        camera = cam.node_name,
        name = cam.name,
        "PipeWire camera: connecting"
    );

    // Check for the stop flag (or the stream ending, or no one taking
    // frames) a few times a second.
    let weak = mainloop.downgrade();
    let stop_check = stop.clone();
    let timer = mainloop.loop_().add_timer(move |_| {
        if stop_check.load(Ordering::Relaxed)
            && let Some(l) = weak.upgrade()
        {
            l.quit();
        }
    });
    timer
        .update_timer(
            Some(Duration::from_millis(50)),
            Some(Duration::from_millis(50)),
        )
        .into_result()?;
    mainloop.run();
    let _ = stream.disconnect();
    tracing::info!(camera = cam.node_name, "PipeWire camera stopped");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn props(pairs: &[(&str, &str)]) -> Props {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    /// linuxlt's UVC camera as WirePlumber's V4L2 monitor offers it.
    fn uvc_node() -> Props {
        props(&[
            ("media.class", "Video/Source"),
            ("media.role", "Camera"),
            ("device.api", "v4l2"),
            ("api.v4l2.path", "/dev/video0"),
            ("api.v4l2.cap.driver", "uvcvideo"),
            ("api.v4l2.cap.card", "Integrated Camera: Integrated C"),
            ("api.v4l2.cap.capabilities", "0x84a00001"),
            ("api.v4l2.cap.device-caps", "0x04200001"),
            ("device.devids", "[ 20736 ]"),
            ("device.id", "35"),
            ("node.description", "Integrated Camera (V4L2)"),
            ("node.nick", "Integrated Camera"),
            ("node.name", "v4l2_input.pci-0000_00_14.0-usb-0_8_1.0"),
            ("object.serial", "66"),
        ])
    }

    #[test]
    fn v4l2_camera_nodes_are_listed_by_their_names() {
        let c = camera_of(61, &uvc_node(), None).unwrap();
        assert_eq!(c.name, "Integrated Camera");
        assert_eq!(c.serial, "66");
        assert_eq!(c.v4l2_path.as_deref(), Some("/dev/video0"));
        assert_eq!(c.devids, vec![20736]);
    }

    /// The node WirePlumber would make of an IPU6 ISYS capture node (when
    /// udev reports it as a capture device) isn't a camera; the camera
    /// libcamera builds from them is.
    #[test]
    fn ipu6_raw_nodes_are_dropped_and_its_libcamera_camera_kept() {
        let mut isys = uvc_node();
        for (k, v) in [
            ("api.v4l2.path", "/dev/video3"),
            ("api.v4l2.cap.driver", "isys"),
            ("api.v4l2.cap.card", "ipu6"),
            ("api.v4l2.cap.capabilities", "0xa4800001"),
            ("api.v4l2.cap.device-caps", "0x24800001"),
            ("device.devids", "[ 20739 ]"),
            ("node.description", "ipu6 (V4L2)"),
            ("node.name", "v4l2_input.pci-0000_00_05.0.3"),
        ] {
            isys.insert(k.into(), v.into());
        }
        assert_eq!(camera_of(70, &isys, None), None);
        let libcamera = props(&[
            ("media.class", "Video/Source"),
            ("media.role", "Camera"),
            ("node.name", "libcamera_input._SB_.PCI0.LNK1"),
            ("node.description", "Built-in Front Camera"),
            ("device.id", "80"),
            ("object.serial", "120"),
        ]);
        let device = props(&[
            ("device.api", "libcamera"),
            ("media.class", "Video/Device"),
            ("device.devids", "[ 20739 20740 ]"),
            ("api.libcamera.location", "front"),
        ]);
        let mut nodes = HashMap::new();
        nodes.insert(70, isys);
        nodes.insert(81, libcamera);
        let mut devices = HashMap::new();
        devices.insert(80, device);
        let list = cameras_from(&nodes, &devices);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "Built-in Front Camera");
        assert_eq!(list[0].api, "libcamera");
        assert_eq!(list[0].v4l2_path, None);
    }

    #[test]
    fn a_uvc_camera_offered_twice_is_listed_once() {
        let libcamera = props(&[
            ("media.class", "Video/Source"),
            ("media.role", "Camera"),
            ("device.api", "libcamera"),
            ("device.devids", "[ 20736 ]"),
            (
                "node.name",
                "libcamera_input._SB_.PCI0.XHC_.RHUB.HS08-8:1.0-04f2:b6d9",
            ),
            ("node.description", "Integrated Camera (libcamera)"),
        ]);
        let mut nodes = HashMap::new();
        nodes.insert(90, libcamera);
        nodes.insert(61, uvc_node());
        let list = cameras_from(&nodes, &HashMap::new());
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].api, "v4l2");
    }

    /// Real cameras come first (the default is the first), then loopback
    /// and other virtual ones, whatever order PipeWire made them in.
    #[test]
    fn real_cameras_are_listed_before_virtual_ones() {
        let mut loopback = uvc_node();
        for (k, v) in [
            ("api.v4l2.path", "/dev/video20"),
            ("api.v4l2.cap.driver", "v4l2 loopback"),
            ("api.v4l2.cap.card", "OST test camera A"),
            ("api.v4l2.cap.capabilities", "0x85200001"),
            ("api.v4l2.cap.device-caps", "0x05200001"),
            ("device.devids", "[ 20756 ]"),
            ("node.description", "OST test camera A (V4L2)"),
            (
                "node.name",
                "v4l2_input._sys_devices_virtual_video4linux_video20",
            ),
        ] {
            loopback.insert(k.into(), v.into());
        }
        let virt = props(&[
            ("media.class", "Video/Source"),
            ("media.role", "Camera"),
            ("node.name", "ost-virtual-cam"),
        ]);
        let mut nodes = HashMap::new();
        nodes.insert(10, loopback);
        nodes.insert(11, virt);
        nodes.insert(61, uvc_node());
        let names: Vec<String> = cameras_from(&nodes, &HashMap::new())
            .into_iter()
            .map(|c| c.node_name)
            .collect();
        assert_eq!(
            names,
            [
                "v4l2_input.pci-0000_00_14.0-usb-0_8_1.0",
                "v4l2_input._sys_devices_virtual_video4linux_video20",
                "ost-virtual-cam"
            ]
        );
    }

    #[test]
    fn screen_casts_and_plain_streams_are_not_cameras() {
        let kwin = props(&[
            ("media.class", "Stream/Output/Video"),
            ("node.name", "kwin_wayland"),
        ]);
        assert_eq!(camera_of(134, &kwin, None), None);
        let screen = props(&[
            ("media.class", "Video/Source"),
            ("media.role", "Screen"),
            ("node.name", "xdg-desktop-portal-wlr"),
        ]);
        assert_eq!(camera_of(140, &screen, None), None);
        let unknown = props(&[("media.class", "Video/Source"), ("node.name", "gst")]);
        assert_eq!(camera_of(141, &unknown, None), None);
        // A virtual camera that says it is one (OBS, a GStreamer
        // pipewiresink) is listed.
        let virt = props(&[
            ("media.class", "Video/Source"),
            ("media.role", "Camera"),
            ("node.name", "ost-virtual-cam"),
            ("node.description", "Virtual Camera"),
        ]);
        let c = camera_of(142, &virt, None).unwrap();
        assert_eq!((c.name.as_str(), c.api.as_str()), ("Virtual Camera", ""));
    }

    #[test]
    fn format_pods_serialize() {
        assert!(
            spa::pod::Pod::from_bytes(&format_pod(false, (640, 360), (640, 360), 15).unwrap())
                .is_some()
        );
        assert!(
            spa::pod::Pod::from_bytes(&format_pod(true, (640, 360), (8192, 8192), 15).unwrap())
                .is_some()
        );
        assert!(spa::pod::Pod::from_bytes(&buffers_pod().unwrap()).is_some());
    }
}
