//! Receiving H.264 video from WebRTC peers (Teams web and the conference
//! server): RTP payloads (RFC 6184: single NAL units, STAP-A, FU-A) are
//! reassembled into access units on a dedicated thread, decoded with
//! openh264 and published as RGBA frames ([`super::frames`]).
//!
//! A lost packet spoils the rest of the frame and, until the next
//! keyframe, everything after it, so the receiver asks for a keyframe
//! (the session turns that into an RTCP PLI) and drops frames until an
//! IDR picture arrives.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;

/// One RTP packet's video payload.
pub struct VideoPacket {
    pub payload: Vec<u8>,
    pub marker: bool,
    pub seq: u16,
    pub timestamp: u32,
}

/// Largest access unit we assemble (a 1080p keyframe is well under this).
const MAX_ACCESS_UNIT: usize = 4 * 1024 * 1024;
/// Packets queued for the decoder before new ones are dropped.
const QUEUE: usize = 512;

/// Reassembles RTP payloads into Annex B access units.
#[derive(Default)]
pub struct Depacketizer {
    au: Vec<u8>,
    fu: Option<Vec<u8>>,
    last_seq: Option<u16>,
    timestamp: Option<u32>,
    /// A packet went missing: wait for the next IDR.
    broken: bool,
    has_idr: bool,
}

/// What a packet completed.
#[derive(Debug, PartialEq, Eq)]
pub enum Output {
    /// More packets needed.
    Pending,
    /// A whole access unit (Annex B), and whether it holds an IDR slice.
    AccessUnit(Vec<u8>, bool),
    /// Packets were lost; ask the sender for a keyframe.
    Lost,
}

const START: [u8; 4] = [0, 0, 0, 1];

impl Depacketizer {
    fn push_nal(&mut self, nal: &[u8]) {
        if nal.is_empty() || self.au.len() + nal.len() + 4 > MAX_ACCESS_UNIT {
            return;
        }
        if nal[0] & 0x1f == 5 {
            self.has_idr = true;
        }
        self.au.extend_from_slice(&START);
        self.au.extend_from_slice(nal);
    }

    pub fn push(&mut self, p: &VideoPacket) -> Output {
        let mut lost = false;
        if let Some(last) = self.last_seq
            && p.seq != last.wrapping_add(1)
        {
            lost = true;
        }
        self.last_seq = Some(p.seq);
        // A new timestamp starts a new picture; whatever was pending is
        // incomplete.
        if self.timestamp.is_some_and(|t| t != p.timestamp) && !self.au.is_empty() {
            lost = true;
        }
        if lost {
            self.au.clear();
            self.fu = None;
            self.has_idr = false;
            self.broken = true;
        }
        self.timestamp = Some(p.timestamp);

        let data = &p.payload;
        if let Some(&first) = data.first() {
            match first & 0x1f {
                1..=23 => self.push_nal(data),
                24 => {
                    // STAP-A: 16-bit size, NAL, repeated.
                    let mut i = 1;
                    while i + 2 <= data.len() {
                        let n = u16::from_be_bytes([data[i], data[i + 1]]) as usize;
                        i += 2;
                        if n == 0 || i + n > data.len() {
                            break;
                        }
                        let nal = data[i..i + n].to_vec();
                        self.push_nal(&nal);
                        i += n;
                    }
                }
                28 if data.len() >= 2 => {
                    // FU-A
                    let (ind, hdr) = (data[0], data[1]);
                    if hdr & 0x80 != 0 {
                        let mut nal = vec![(ind & 0xe0) | (hdr & 0x1f)];
                        nal.extend_from_slice(&data[2..]);
                        self.fu = Some(nal);
                    } else if let Some(nal) = self.fu.as_mut()
                        && nal.len() + data.len() <= MAX_ACCESS_UNIT
                    {
                        nal.extend_from_slice(&data[2..]);
                    }
                    if hdr & 0x40 != 0
                        && let Some(nal) = self.fu.take()
                    {
                        self.push_nal(&nal);
                    }
                }
                _ => {}
            }
        }

        if !p.marker {
            return if lost { Output::Lost } else { Output::Pending };
        }
        let au = std::mem::take(&mut self.au);
        let idr = std::mem::take(&mut self.has_idr);
        self.fu = None;
        self.timestamp = None;
        if self.broken && !idr {
            return Output::Lost;
        }
        self.broken = false;
        if au.is_empty() {
            Output::Pending
        } else {
            Output::AccessUnit(au, idr)
        }
    }
}

/// Decodes a peer's video on its own thread and publishes it as `key`.
pub struct VideoReceiver {
    tx: mpsc::SyncSender<VideoPacket>,
    /// Set when the decoder needs a keyframe (send a PLI).
    pub keyframe_wanted: Arc<AtomicBool>,
    key: String,
}

impl VideoReceiver {
    pub fn start(key: &str) -> Self {
        let (tx, rx) = mpsc::sync_channel::<VideoPacket>(QUEUE);
        // Ask for a keyframe straight away: we may have joined mid-stream.
        let keyframe_wanted = Arc::new(AtomicBool::new(true));
        let want = keyframe_wanted.clone();
        let k = key.to_string();
        std::thread::Builder::new()
            .name("ost-video-rx".into())
            .spawn(move || decode_loop(rx, want, &k))
            .ok();
        Self {
            tx,
            keyframe_wanted,
            key: key.to_string(),
        }
    }

    /// The frame key it publishes under.
    pub fn key(&self) -> &str {
        &self.key
    }

    /// Queue a packet (dropped if the decoder is behind).
    pub fn push(&self, p: VideoPacket) {
        if self.tx.try_send(p).is_err() {
            self.keyframe_wanted.store(true, Ordering::Relaxed);
        }
    }
}

impl Drop for VideoReceiver {
    fn drop(&mut self) {
        super::frames::clear(&self.key);
    }
}

fn decode_loop(rx: mpsc::Receiver<VideoPacket>, want: Arc<AtomicBool>, key: &str) {
    // Call health: what's decoded (in software) of others' cameras or a
    // shared screen.
    let kind = if key == "share" {
        super::call_health::Kind::ShareRecv
    } else {
        super::call_health::Kind::VideoRecv
    };
    let media = super::call_health::current();
    media.set_codec(kind, "H264 sw");
    let health = media.stream(kind, 0);
    use openh264::OpenH264API;
    use openh264::decoder::{Decoder, DecoderConfig};
    use openh264::formats::YUVSource;
    let mut decoder =
        match Decoder::with_api_config(OpenH264API::from_source(), DecoderConfig::new()) {
            Ok(d) => d,
            Err(e) => {
                tracing::warn!("H.264 decoder unavailable: {e:?}");
                return;
            }
        };
    let mut depack = Depacketizer::default();
    let mut decoded = 0u64;
    while let Ok(p) = rx.recv() {
        match depack.push(&p) {
            Output::Pending => {}
            Output::Lost => want.store(true, Ordering::Relaxed),
            Output::AccessUnit(au, idr) => {
                if idr {
                    want.store(false, Ordering::Relaxed);
                }
                match decoder.decode(&au) {
                    Ok(Some(yuv)) => {
                        let (w, h) = yuv.dimensions();
                        let mut rgba = vec![0u8; w * h * 4];
                        if super::frames::implicit_mask(key) {
                            // A presenter in Standout or Reporter: their
                            // background, cut out into the luma, clears.
                            ost_vfx::implicit_mask_rgba(
                                yuv.y(),
                                yuv.u(),
                                yuv.v(),
                                yuv.strides(),
                                w,
                                h,
                                &mut rgba,
                            );
                            if decoded.is_multiple_of(150) {
                                let clear = rgba.chunks_exact(4).filter(|p| p[3] == 0).count();
                                tracing::info!(
                                    key,
                                    w,
                                    h,
                                    clear_percent = clear * 100 / (w * h).max(1),
                                    "presenter camera with implicit mask"
                                );
                            }
                        } else {
                            yuv.write_rgba8(&mut rgba);
                        }
                        super::frames::publish(key, w as u32, h as u32, rgba);
                        health.frame(w as u32, h as u32);
                        decoded += 1;
                        if decoded == 1 || decoded.is_multiple_of(300) {
                            tracing::info!(decoded, w, h, "video frames decoded");
                        }
                    }
                    Ok(None) => {}
                    Err(e) => {
                        tracing::debug!("H.264 decode error: {e:?}");
                        want.store(true, Ordering::Relaxed);
                    }
                }
            }
        }
    }
}

/// Largest RTP payload we send (leaves room for SRTP, UDP and TURN).
pub const MTU: usize = 1100;

/// RFC 6184 packetization of one access unit: a NAL that fits goes alone,
/// a bigger one is split into FU-A fragments. Returns (payload, marker);
/// the marker is set on the access unit's last packet.
pub fn packetize(nals: &[Vec<u8>], mtu: usize) -> Vec<(Vec<u8>, bool)> {
    let mut out = Vec::new();
    for nal in nals.iter().filter(|n| !n.is_empty()) {
        if nal.len() <= mtu {
            out.push((nal.clone(), false));
            continue;
        }
        let (hdr, body) = (nal[0], &nal[1..]);
        let indicator = (hdr & 0xe0) | 28;
        let chunks: Vec<&[u8]> = body.chunks(mtu - 2).collect();
        for (i, c) in chunks.iter().enumerate() {
            let mut fu = hdr & 0x1f;
            if i == 0 {
                fu |= 0x80;
            }
            if i + 1 == chunks.len() {
                fu |= 0x40;
            }
            let mut p = Vec::with_capacity(c.len() + 2);
            p.push(indicator);
            p.push(fu);
            p.extend_from_slice(c);
            out.push((p, false));
        }
    }
    if let Some(last) = out.last_mut() {
        last.1 = true;
    }
    out
}

/// A plain RTP packet (V=2, no extensions).
pub fn rtp_packet(
    pt: u8,
    marker: bool,
    seq: u16,
    timestamp: u32,
    ssrc: u32,
    payload: &[u8],
) -> Vec<u8> {
    let mut p = Vec::with_capacity(12 + payload.len());
    p.push(0x80);
    p.push(if marker { 0x80 | pt } else { pt });
    p.extend_from_slice(&seq.to_be_bytes());
    p.extend_from_slice(&timestamp.to_be_bytes());
    p.extend_from_slice(&ssrc.to_be_bytes());
    p.extend_from_slice(payload);
    p
}

/// Whether an RTCP compound packet asks `ours` for a keyframe (PLI or FIR).
pub fn wants_keyframe(rtcp: &[u8], ours: u32) -> bool {
    let mut i = 0;
    while i + 12 <= rtcp.len() {
        let (fmt, pt) = (rtcp[i] & 0x1f, rtcp[i + 1]);
        let len = (u16::from_be_bytes([rtcp[i + 2], rtcp[i + 3]]) as usize + 1) * 4;
        if len < 4 || i + len > rtcp.len() {
            break;
        }
        let media = u32::from_be_bytes([rtcp[i + 8], rtcp[i + 9], rtcp[i + 10], rtcp[i + 11]]);
        if pt == 206 && fmt == 1 && (media == ours || media == 0) {
            return true;
        }
        // FIR (RFC 5104): the target SSRC is in its FCI.
        if pt == 206 && fmt == 4 {
            let mut j = i + 12;
            while j + 8 <= i + len {
                if u32::from_be_bytes([rtcp[j], rtcp[j + 1], rtcp[j + 2], rtcp[j + 3]]) == ours {
                    return true;
                }
                j += 8;
            }
        }
        i += len;
    }
    false
}

/// Our camera, encoded and handed out as plain RTP packets; drop it to
/// stop. The newest picture is also published as the "self" frame.
/// Your camera before a call: its picture as the "self" preview (Teams'
/// pre-join preview), until dropped.
pub struct CameraPreview {
    stop: Arc<AtomicBool>,
}

impl CameraPreview {
    pub fn start(device: Option<String>) -> anyhow::Result<Self> {
        let (w, h, fps) = capture_format(device.as_deref());
        let (camera, frames) = super::camera::CameraCapture::start(device.as_deref(), w, h, fps)?;
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        std::thread::Builder::new()
            .name("ost-camera-preview".into())
            .spawn(move || {
                let _camera = camera;
                // The preview shows the video effects as they'll be sent.
                let mut effects = ost_vfx::Processor::new();
                while !stop2.load(Ordering::Relaxed) {
                    if let Ok(mut f) = frames.recv_timeout(std::time::Duration::from_millis(250)) {
                        effects.process(f.width, f.height, &mut f.data);
                        super::frames::publish(
                            "self",
                            f.width,
                            f.height,
                            preview_rgba(&f.data, f.width, f.height),
                        );
                    }
                }
                super::frames::clear("self");
            })?;
        Ok(Self { stop })
    }
}

impl Drop for CameraPreview {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

pub struct VideoSender {
    stop: Arc<AtomicBool>,
    /// Set when the peer asked for a keyframe.
    pub keyframe: Arc<AtomicBool>,
}

/// Teams' Efficiency mode (Settings ▸ General): "reduces processor,
/// memory and network usage … may affect some functionality such as camera
/// resolution". On, the camera is sent at no more than 424x240
/// (EFFICIENT_FS macroblocks) and 300 kbit/s.
static EFFICIENCY: AtomicBool = AtomicBool::new(false);
const EFFICIENT_FS: u32 = (424 / 16 + 1) * (240 / 16);
const EFFICIENT_KBPS: u32 = 300;

/// The Sharing control bar's Optimize ("Optimize for video content"):
/// the shared screen is sent at a video's frame rate.
static SCREEN_MOTION: AtomicBool = AtomicBool::new(false);
const MOTION_FPS: u32 = 30;
const MOTION_KBPS: u32 = 2500;

pub fn set_screen_motion(on: bool) {
    SCREEN_MOTION.store(on, Ordering::Relaxed);
}

pub fn screen_motion() -> bool {
    SCREEN_MOTION.load(Ordering::Relaxed)
}

pub fn set_efficiency(on: bool) {
    EFFICIENCY.store(on, Ordering::Relaxed);
}

pub fn efficiency() -> bool {
    EFFICIENCY.load(Ordering::Relaxed)
}

/// What we send: 640x360 at 15 fps, about 600 kbit/s, a keyframe every 2 s.
pub const SEND_W: u32 = 640;
pub const SEND_H: u32 = 360;
const SEND_FPS: u32 = 15;
const SEND_KBPS: u32 = 600;

/// How one outgoing stream is encoded.
#[derive(Clone, Copy)]
struct SendConfig {
    fps: u32,
    kbps: u32,
    /// Publish a preview of what we send under this frame key.
    preview: Option<&'static str>,
    /// Resend the last picture this often when nothing new arrives (a
    /// still screen sends no frames, but viewers joining need one).
    repeat: Option<std::time::Duration>,
    /// What Call health counts it as.
    health: super::call_health::Kind,
    /// Apply the chosen video effects (background, brightness): the
    /// camera's picture, not a shared screen.
    effects: bool,
}

/// Your avatar as the camera: Teams has the Avatars app draw at 1280 x 720
/// and sends it at about 27 fps (measured); a meeting's media processor may
/// still ask for less (vdclc), as for a camera.
pub const AVATAR_W: u32 = 1280;
pub const AVATAR_H: u32 = 720;
const AVATAR_FPS: u32 = 30;
const AVATAR: SendConfig = SendConfig {
    fps: AVATAR_FPS,
    kbps: 1500,
    preview: Some("self"),
    repeat: None,
    health: super::call_health::Kind::VideoSend,
    effects: true,
};

/// The capture size and rate for a camera device (the avatar's own).
fn capture_format(device: Option<&str>) -> (u32, u32, u32) {
    if device == Some(super::camera::AVATAR_DEVICE) {
        (AVATAR_W, AVATAR_H, AVATAR_FPS)
    } else {
        (SEND_W, SEND_H, SEND_FPS)
    }
}

const CAMERA: SendConfig = SendConfig {
    fps: SEND_FPS,
    kbps: SEND_KBPS,
    preview: Some("self"),
    repeat: None,
    health: super::call_health::Kind::VideoSend,
    effects: true,
};

/// A shared screen: up to 1280x720 at 10 fps, sharper (more bits a
/// frame) than the camera, as text has to stay readable.
#[cfg(feature = "screencast")]
const SCREEN: SendConfig = SendConfig {
    fps: 10,
    kbps: 1500,
    preview: None,
    repeat: Some(std::time::Duration::from_secs(1)),
    health: super::call_health::Kind::ShareSend,
    effects: false,
};

/// What a meeting's media processor asks our camera for (Teams' `vdclc`):
/// at most `max_fs` macroblocks a frame, `max_kbps`, `max_fps`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SendLimits {
    pub max_fs: u32,
    pub max_kbps: u32,
    pub max_fps: u32,
}

/// The latest limits, shared between the media control plane and the
/// sender.
#[derive(Default)]
pub struct SendControl {
    limits: std::sync::Mutex<Option<SendLimits>>,
}

impl SendControl {
    pub fn set(&self, l: SendLimits) {
        *self.limits.lock().unwrap_or_else(|e| e.into_inner()) = Some(l);
    }

    fn get(&self) -> Option<SendLimits> {
        *self.limits.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// One layer of a `vdclc` message ("KeyFrame=1;max-br=291;max-fps=1500.000000;
/// max-fs=405;…"): the limits, and whether a keyframe is wanted. `max-fps`
/// is in hundredths.
pub fn parse_layer(layer: &str) -> Option<(SendLimits, bool)> {
    let field = |k: &str| {
        layer.split(';').find_map(|kv| {
            let (key, v) = kv.split_once('=')?;
            (key.trim() == k)
                .then(|| v.trim().parse::<f64>().ok())
                .flatten()
        })
    };
    Some((
        SendLimits {
            max_fs: field("max-fs")? as u32,
            max_kbps: field("max-br")? as u32,
            max_fps: ((field("max-fps")? / 100.0).round() as u32).max(1),
        },
        field("KeyFrame").is_some_and(|k| k >= 1.0),
    ))
}

/// The largest even size with the picture's shape that fits `max_fs`
/// 16x16 macroblocks (never larger than it is).
pub fn fit_to_fs(w: u32, h: u32, max_fs: u32) -> (u32, u32) {
    let mbs = |w: u32, h: u32| w.div_ceil(16) * h.div_ceil(16);
    if max_fs == 0 || mbs(w, h) <= max_fs {
        return (w, h);
    }
    let scale = ((max_fs * 256) as f64 / (w * h) as f64).sqrt();
    let mut nw = ((w as f64 * scale) as u32) & !1;
    let mut nh = ((h as f64 * scale) as u32) & !1;
    while nw > 2 && nh > 2 && mbs(nw, nh) > max_fs {
        nw -= 2;
        nh = ((nw as u64 * h as u64 / w as u64) as u32) & !1;
    }
    (nw.max(2), nh.max(2))
}

/// One plane resized (bilinear).
fn scale_plane(src: &[u8], w: usize, h: usize, nw: usize, nh: usize, out: &mut Vec<u8>) {
    let fx = w as f32 / nw as f32;
    let fy = h as f32 / nh as f32;
    for y in 0..nh {
        let sy = ((y as f32 + 0.5) * fy - 0.5).clamp(0.0, (h - 1) as f32);
        let (y0, wy) = (sy as usize, sy.fract());
        let y1 = (y0 + 1).min(h - 1);
        for x in 0..nw {
            let sx = ((x as f32 + 0.5) * fx - 0.5).clamp(0.0, (w - 1) as f32);
            let (x0, wx) = (sx as usize, sx.fract());
            let x1 = (x0 + 1).min(w - 1);
            let p = |yy: usize, xx: usize| src[yy * w + xx] as f32;
            let top = p(y0, x0) * (1.0 - wx) + p(y0, x1) * wx;
            let bottom = p(y1, x0) * (1.0 - wx) + p(y1, x1) * wx;
            out.push((top * (1.0 - wy) + bottom * wy).round() as u8);
        }
    }
}

/// An I420 frame resized to `nw`x`nh` (even sizes).
pub fn scale_i420(data: &[u8], w: u32, h: u32, nw: u32, nh: u32) -> Vec<u8> {
    let (w, h, nw, nh) = (w as usize, h as usize, nw as usize, nh as usize);
    let mut out = Vec::with_capacity(nw * nh * 3 / 2);
    let y_len = w * h;
    let c_len = (w / 2) * (h / 2);
    scale_plane(&data[..y_len], w, h, nw, nh, &mut out);
    scale_plane(
        &data[y_len..y_len + c_len],
        w / 2,
        h / 2,
        nw / 2,
        nh / 2,
        &mut out,
    );
    scale_plane(
        &data[y_len + c_len..y_len + 2 * c_len],
        w / 2,
        h / 2,
        nw / 2,
        nh / 2,
        &mut out,
    );
    out
}

impl VideoSender {
    /// Open the camera (`device`, else /dev/video0) and start sending RTP
    /// packets (payload type `pt`, `ssrc`) to `out`; in a meeting,
    /// `control` carries what the media processor asks for.
    pub fn start(
        out: tokio::sync::mpsc::UnboundedSender<Vec<u8>>,
        pt: u8,
        ssrc: u32,
        device: Option<String>,
        control: Option<Arc<SendControl>>,
    ) -> anyhow::Result<Self> {
        let (w, h, fps) = capture_format(device.as_deref());
        let cfg = if device.as_deref() == Some(super::camera::AVATAR_DEVICE) {
            AVATAR
        } else {
            CAMERA
        };
        let (camera, frames) = super::camera::CameraCapture::start(device.as_deref(), w, h, fps)?;
        let stop = Arc::new(AtomicBool::new(false));
        let keyframe = Arc::new(AtomicBool::new(true));
        let (stop2, key2) = (stop.clone(), keyframe.clone());
        std::thread::Builder::new()
            .name("ost-video-tx".into())
            .spawn(move || {
                let _camera = camera;
                send_loop(
                    frames,
                    RtpOut { tx: out, pt, ssrc },
                    &stop2,
                    &key2,
                    cfg,
                    control,
                );
                super::frames::clear("self");
            })?;
        Ok(Self { stop, keyframe })
    }

    /// Send a screen capture's frames (payload type `pt`, `ssrc`) to `out`.
    #[cfg(feature = "screencast")]
    pub fn start_screen(
        out: tokio::sync::mpsc::UnboundedSender<Vec<u8>>,
        pt: u8,
        ssrc: u32,
        capture: super::screencast::ScreenCapture,
        frames: mpsc::Receiver<super::camera::YuvFrame>,
        control: Option<Arc<SendControl>>,
    ) -> anyhow::Result<Self> {
        let stop = Arc::new(AtomicBool::new(false));
        let keyframe = Arc::new(AtomicBool::new(true));
        let (stop2, key2) = (stop.clone(), keyframe.clone());
        std::thread::Builder::new()
            .name("ost-share-tx".into())
            .spawn(move || {
                let _capture = capture;
                send_loop(
                    frames,
                    RtpOut { tx: out, pt, ssrc },
                    &stop2,
                    &key2,
                    SCREEN,
                    control,
                );
                // The capture ended (or we were stopped): say so.
                stop2.store(true, Ordering::Relaxed);
            })?;
        Ok(Self { stop, keyframe })
    }
}

impl VideoSender {
    /// Whether sending has ended (stopped, or its source went away).
    pub fn ended(&self) -> bool {
        self.stop.load(Ordering::Relaxed)
    }
}

impl Drop for VideoSender {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// Where a sender's RTP goes: the channel, its payload type and SSRC.
struct RtpOut {
    tx: tokio::sync::mpsc::UnboundedSender<Vec<u8>>,
    pt: u8,
    ssrc: u32,
}

fn send_loop(
    frames: mpsc::Receiver<super::camera::YuvFrame>,
    out: RtpOut,
    stop: &AtomicBool,
    keyframe: &AtomicBool,
    cfg: SendConfig,
    control: Option<Arc<SendControl>>,
) {
    // The encoder and what it was made for: (width, height, kbps, fps).
    let mut encoder: Option<((u32, u32, u32, u32), super::codec::H264Encoder)> = None;
    let mut last: Option<super::camera::YuvFrame> = None;
    let mut last_sent = std::time::Instant::now();
    let started = std::time::Instant::now();
    let RtpOut { tx: out, pt, ssrc } = out;
    // Call health: OpenH264 encodes in software.
    let media = super::call_health::current();
    media.set_codec(cfg.health, "H264 sw");
    let health = media.stream(cfg.health, ssrc);
    let mut seq: u16 = (ssrc >> 7) as u16;
    let mut sent = 0u64;
    let mut last_frame: Option<std::time::Instant> = None;
    let mut effects = cfg.effects.then(ost_vfx::Processor::new);
    while !stop.load(Ordering::Relaxed) {
        // A meeting's processor may ask for less (Teams' vdclc).
        let limits = control.as_ref().and_then(|c| c.get());
        let motion = cfg.health == super::call_health::Kind::ShareSend && screen_motion();
        let (base_fps, base_kbps) = if motion {
            (MOTION_FPS, MOTION_KBPS)
        } else {
            (cfg.fps, cfg.kbps)
        };
        let fps = limits.map_or(base_fps, |l| l.max_fps.clamp(1, 30));
        let kbps = limits.map_or(base_kbps, |l| l.max_kbps.clamp(50, 4000));
        // In a meeting, also what the send-side estimate leaves for video
        // after audio and packet overhead (Teams' encoder follows its send
        // limit the same way).
        let kbps = match super::send_bwe::current_bps() {
            0 => kbps,
            bps => kbps.min((((bps as f64 - 64_000.0) * 0.85) / 1000.0).max(50.0) as u32),
        };
        // Efficiency mode: the camera at a lower resolution and bitrate.
        let efficient = cfg.effects && efficiency();
        let kbps = if efficient {
            kbps.min(EFFICIENT_KBPS)
        } else {
            kbps
        };
        // A little under the frame interval, so 15 fps cameras aren't halved.
        let min_gap = std::time::Duration::from_millis(1000 / fps as u64 * 8 / 10);
        let f = match frames.recv_timeout(std::time::Duration::from_millis(250)) {
            Ok(f) => f,
            // Nothing new: resend the last picture now and then, if asked.
            Err(mpsc::RecvTimeoutError::Timeout) => match (&last, cfg.repeat) {
                (Some(l), Some(every)) if last_sent.elapsed() >= every => super::camera::YuvFrame {
                    width: l.width,
                    height: l.height,
                    data: l.data.clone(),
                },
                _ => continue,
            },
            Err(mpsc::RecvTimeoutError::Disconnected) => return,
        };
        if f.data.len() < (f.width * f.height * 3 / 2) as usize {
            continue;
        }
        // Cameras may ignore the frame rate asked for: pace to SEND_FPS.
        let now = std::time::Instant::now();
        if last_frame.is_some_and(|t: std::time::Instant| now - t < min_gap) {
            continue;
        }
        last_frame = Some(now);
        last_sent = now;
        // Your background and brightness, as chosen in Video effects.
        let mut f = f;
        if let Some(fx) = effects.as_mut() {
            fx.process(f.width, f.height, &mut f.data);
        }
        if let Some(key) = cfg.preview {
            super::frames::publish(
                key,
                f.width,
                f.height,
                preview_rgba(&f.data, f.width, f.height),
            );
        }
        // Presenter modes Standout and Reporter: the background cut out
        // into the picture (Teams' Weatherperson effect); you still see
        // yourself as usual.
        if let Some(fx) = effects.as_mut() {
            fx.presenter_effect(f.width, f.height, &mut f.data);
        }
        // The size the processor allows (16x16 macroblocks a frame).
        let (tw, th) = limits.map_or((f.width, f.height), |l| {
            fit_to_fs(f.width, f.height, l.max_fs)
        });
        let (tw, th) = if efficient {
            fit_to_fs(tw, th, EFFICIENT_FS)
        } else {
            (tw, th)
        };
        let f = if (tw, th) != (f.width, f.height) {
            super::camera::YuvFrame {
                width: tw,
                height: th,
                data: scale_i420(&f.data, f.width, f.height, tw, th),
            }
        } else {
            f
        };
        // A new encoder for a new size or frame rate; a new bitrate is set
        // in place (no keyframe).
        if let Some(((w, h, k, r), enc)) = encoder.as_mut()
            && (*w, *h, *r) == (f.width, f.height, fps)
            && *k != kbps
        {
            enc.set_bitrate(kbps);
            tracing::info!(from = *k, kbps, "video bitrate");
            *k = kbps;
        }
        let made_for = (f.width, f.height, kbps, fps);
        if encoder.as_ref().is_none_or(|(m, _)| *m != made_for) {
            match super::codec::H264Encoder::new_realtime(
                f.width,
                f.height,
                fps as f32,
                kbps,
                fps * 2,
            ) {
                Ok(e) => {
                    tracing::info!(w = f.width, h = f.height, kbps, fps, "video encoder");
                    encoder = Some((made_for, e));
                    // A new encoder starts with a keyframe anyway.
                }
                Err(e) => {
                    tracing::warn!("H.264 encoder unavailable: {e:#}");
                    return;
                }
            }
        }
        let Some((_, enc)) = encoder.as_mut() else {
            continue;
        };
        if keyframe.swap(false, Ordering::Relaxed) {
            enc.force_keyframe();
        }
        let nals = match enc.encode(&f.data) {
            Ok(n) => n,
            Err(e) => {
                tracing::debug!("encode failed: {e:#}");
                continue;
            }
        };
        let ts = (started.elapsed().as_micros() * 90 / 1000) as u32;
        for (payload, marker) in packetize(&nals, MTU) {
            if out
                .send(rtp_packet(pt, marker, seq, ts, ssrc, &payload))
                .is_err()
            {
                return;
            }
            seq = seq.wrapping_add(1);
        }
        sent += 1;
        health.frame(f.width, f.height);
        if sent == 1 || sent.is_multiple_of(300) {
            tracing::info!(sent, w = f.width, h = f.height, "video frames sent");
        }
        tracing::debug!(
            sent,
            ssrc,
            nals = ?nals.iter().map(|n| n.first().map(|b| b & 0x1f).unwrap_or(0)).collect::<Vec<_>>(),
            "video frame sent"
        );
        if cfg.repeat.is_some() {
            last = Some(f);
        }
    }
}

/// A half-size RGBA picture of an I420 frame (the self-view tile is small).
fn preview_rgba(i420: &[u8], w: u32, h: u32) -> Vec<u8> {
    // At full resolution, so the preview is as sharp as what's sent (in
    // ost-vfx, which is built optimised).
    ost_vfx::i420_to_rgba(i420, w as usize, h as usize)
}

/// An RTCP Picture Loss Indication (RFC 4585) from `sender` about `media`.
pub fn pli(sender: u32, media: u32) -> Vec<u8> {
    let mut p = vec![0x81, 206, 0, 2];
    p.extend_from_slice(&sender.to_be_bytes());
    p.extend_from_slice(&media.to_be_bytes());
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pkt(payload: &[u8], marker: bool, seq: u16, ts: u32) -> VideoPacket {
        VideoPacket {
            payload: payload.to_vec(),
            marker,
            seq,
            timestamp: ts,
        }
    }

    #[test]
    fn layer_requests_read_as_teams_writes_them() {
        let (l, key) = parse_layer(
            "KeyFrame=1;max-br=291;max-fps=1500.000000;max-fs=405;max-mbps=6075;sequence-number=0;ssrc=893793192",
        )
        .unwrap();
        assert_eq!(
            l,
            SendLimits {
                max_fs: 405,
                max_kbps: 291,
                max_fps: 15
            }
        );
        assert!(key);
        assert!(
            !parse_layer("KeyFrame=0;max-br=646;max-fps=3000.0;max-fs=920")
                .unwrap()
                .1
        );
    }

    #[test]
    fn efficiency_mode_sends_at_most_424x240() {
        let (w, h) = fit_to_fs(640, 360, EFFICIENT_FS);
        assert!(w <= 432 && h <= 240, "{w}x{h}");
        assert!(w >= 400, "{w}x{h}");
    }

    #[test]
    fn frames_fit_the_macroblock_budget() {
        // 920 macroblocks: 640x360 (40x23 = 920) from 1280x720.
        assert_eq!(fit_to_fs(1280, 720, 920), (640, 360));
        let (w, h) = fit_to_fs(1280, 720, 405);
        assert!(w.div_ceil(16) * h.div_ceil(16) <= 405 && w % 2 == 0 && h % 2 == 0);
        assert!((w as f32 / h as f32 - 16.0 / 9.0).abs() < 0.05);
        assert_eq!(fit_to_fs(640, 360, 3600), (640, 360), "never larger");
    }

    #[test]
    fn i420_scales_to_the_new_size() {
        let (w, h) = (8u32, 4u32);
        let mut f = vec![200u8; (w * h) as usize];
        f.extend(vec![100u8; (w * h / 2) as usize]);
        let s = scale_i420(&f, w, h, 4, 2);
        assert_eq!(s.len(), 4 * 2 * 3 / 2);
        assert!(s[..8].iter().all(|&v| v == 200));
        assert!(s[8..].iter().all(|&v| v == 100));
    }

    #[test]
    fn stap_a_and_fu_a_make_an_access_unit() {
        let mut d = Depacketizer::default();
        // STAP-A with SPS (7) and PPS (8).
        let stap = [24, 0, 2, 0x67, 1, 0, 2, 0x68, 2];
        assert_eq!(d.push(&pkt(&stap, false, 1, 90)), Output::Pending);
        // An IDR slice in two FU-A fragments.
        assert_eq!(
            d.push(&pkt(&[0x7c, 0x85, 0xaa], false, 2, 90)),
            Output::Pending
        );
        let out = d.push(&pkt(&[0x7c, 0x45, 0xbb], true, 3, 90));
        let mut want = vec![
            0, 0, 0, 1, 0x67, 1, 0, 0, 0, 1, 0x68, 2, 0, 0, 0, 1, 0x65, 0xaa, 0xbb,
        ];
        assert_eq!(out, Output::AccessUnit(want.clone(), true));
        // The next frame: a single non-IDR slice.
        want = vec![0, 0, 0, 1, 0x41, 9];
        assert_eq!(
            d.push(&pkt(&[0x41, 9], true, 4, 180)),
            Output::AccessUnit(want, false)
        );
    }

    #[test]
    fn a_lost_packet_waits_for_the_next_idr() {
        let mut d = Depacketizer::default();
        assert!(matches!(
            d.push(&pkt(&[0x65, 1], true, 1, 90)),
            Output::AccessUnit(_, true)
        ));
        // seq 2 lost
        assert_eq!(d.push(&pkt(&[0x41, 1], true, 3, 180)), Output::Lost);
        assert_eq!(d.push(&pkt(&[0x41, 1], true, 4, 270)), Output::Lost);
        assert!(matches!(
            d.push(&pkt(&[0x65, 1], true, 5, 360)),
            Output::AccessUnit(_, true)
        ));
        assert!(matches!(
            d.push(&pkt(&[0x41, 1], true, 6, 450)),
            Output::AccessUnit(_, false)
        ));
    }

    #[test]
    fn packets_round_trip_through_the_depacketizer() {
        let big: Vec<u8> = std::iter::once(0x65)
            .chain((0..3000).map(|i| i as u8))
            .collect();
        let nals = vec![vec![0x67, 1, 2], vec![0x68, 3], big.clone()];
        let pkts = packetize(&nals, 1000);
        assert!(pkts.len() >= 5 && pkts.iter().all(|(p, _)| p.len() <= 1000));
        assert!(pkts.last().unwrap().1 && pkts.iter().filter(|p| p.1).count() == 1);
        let mut d = Depacketizer::default();
        let mut got = None;
        for (i, (p, m)) in pkts.iter().enumerate() {
            if let Output::AccessUnit(au, idr) = d.push(&pkt(p, *m, i as u16, 90)) {
                got = Some((au, idr));
            }
        }
        let (au, idr) = got.unwrap();
        assert!(idr);
        let mut want = Vec::new();
        for n in &nals {
            want.extend_from_slice(&[0, 0, 0, 1]);
            want.extend_from_slice(n);
        }
        assert_eq!(au, want);
        let r = rtp_packet(102, true, 7, 9, 11, &[1]);
        assert_eq!(r[1], 0x80 | 102);
    }

    #[test]
    fn keyframe_requests_are_recognised() {
        assert!(wants_keyframe(&pli(5, 42), 42));
        assert!(!wants_keyframe(&pli(5, 41), 42));
        // FIR for 42 after a receiver report.
        let mut c = vec![0x80, 201, 0, 1, 0, 0, 0, 5];
        c.extend_from_slice(&[
            0x84, 206, 0, 4, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 42, 1, 0, 0, 0,
        ]);
        assert!(wants_keyframe(&c, 42));
        assert!(!wants_keyframe(&[0x81, 206, 0, 9], 42));
    }

    #[test]
    fn previews_are_full_size_rgba() {
        let (w, h) = (4u32, 2u32);
        let mut f = vec![235u8; 8];
        f.extend_from_slice(&[128, 128, 128, 128]);
        let p = preview_rgba(&f, w, h);
        assert_eq!(p.len(), 8 * 4);
        assert!(p[0] > 250 && p[3] == 255 && p[7 * 4] > 250);
    }

    #[test]
    fn malformed_stap_a_is_ignored() {
        let mut d = Depacketizer::default();
        assert_eq!(
            d.push(&pkt(&[24, 0xff, 0xff, 1], true, 1, 1)),
            Output::Pending
        );
        assert_eq!(pli(1, 2), vec![0x81, 206, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2]);
    }
}
