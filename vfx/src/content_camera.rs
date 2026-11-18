//! Teams' Content from camera effects on I420 camera frames (SlimCV's
//! "scan" effects that Teams' setup dialog drives through
//! `applyScanVideoEffect` / `scanVideoEffect`):
//!
//! - **Quad detection** ("Detect edges"): the whiteboard or page in view,
//!   found on a ~320 px wide copy of the frame (a bright, colourless
//!   region: Otsu's threshold, a 3 x 3 close, the largest component, its
//!   convex hull, the largest quadrilateral on the hull), checked (at least
//!   15 % of the frame, corners 50–130°, the hull close to a quadrilateral,
//!   mostly filled), eased (α 0.3) and called stable once every corner has
//!   stayed within 1 % of the diagonal for 10 detections.
//! - **Zoom**: the quad rectified (a homography, bilinear) and fitted into
//!   the output with bars (Teams' pillar boxing), the output always the
//!   camera's own size.
//! - **Clean-up** ("Overlay presenter"): the board's white found per 16 px
//!   cell (the bright end of each cell, a 3 x 3 median over cells, eased
//!   over time where nobody stands), every pixel divided by it so the
//!   board turns white and the ink stays (darker, more saturated); the
//!   presenter (person segmentation) is drawn at half strength over the
//!   board as it was before they stepped in front of it.
//! - **Rotation**: 90° steps clockwise, the quad turned with the picture
//!   (Teams' `rotateVideo`).
//!
//! Options and state are Teams' `ScanVideoEffectsInput` /
//! `ScanVideoEffectsResponse`.

use std::sync::{Arc, Mutex, mpsc};

use super::{MASK, Segmenter, model_input};

/// Teams' full-frame quad (`[0,0,1,0,1,1,0,1]`: TL, TR, BR, BL).
pub const FULL_FRAME: [f32; 8] = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
/// Teams' "no quad yet" (all zeros).
pub const NO_QUAD: [f32; 8] = [0.0; 8];

/// Teams' `E0`: a quad that is the whole frame or none at all.
pub fn is_trivial(q: &[f32; 8]) -> bool {
    *q == FULL_FRAME || *q == NO_QUAD
}

/// What is in front of the camera (Teams' content types).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Whiteboard,
    Document,
    Video,
}

impl Kind {
    pub fn parse(s: &str) -> Self {
        match s {
            "whiteboard" => Self::Whiteboard,
            "document" => Self::Document,
            _ => Self::Video,
        }
    }
}

/// Teams' `ScanVideoEffectsInput`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Options {
    pub quad_enabled: bool,
    pub cleanup_enabled: bool,
    pub zoom_enabled: bool,
    pub normalized_quad: [f32; 8],
}

impl Default for Options {
    fn default() -> Self {
        Self::off()
    }
}

impl Options {
    /// Everything off (Teams' `resetScanVideoEffect`).
    pub fn off() -> Self {
        Self { quad_enabled: false, cleanup_enabled: false, zoom_enabled: false, normalized_quad: NO_QUAD }
    }

    /// Teams' defaults per content type (`n4`): a whiteboard detects edges
    /// and cleans up, a document only detects edges, video does neither.
    pub fn defaults(kind: Kind) -> Self {
        Self {
            quad_enabled: kind != Kind::Video,
            cleanup_enabled: kind == Kind::Whiteboard,
            zoom_enabled: true,
            normalized_quad: FULL_FRAME,
        }
    }
}

/// Teams' `ScanVideoEffectsResponse`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct State {
    pub quad_enabled: bool,
    pub cleanup_enabled: bool,
    pub zoom_enabled: bool,
    /// The quad in use: the detected one while detecting (zeros until one
    /// is found), else the one given.
    pub normalized_quad: [f32; 8],
    pub quad_stable: bool,
    /// The (rotated) camera frame's size.
    pub frame_size: (u32, u32),
    /// Clockwise, 0 / 90 / 180 / 270.
    pub rotation: u32,
}

/// Turn a quad with a 90° clockwise turn of the picture (Teams' `Dt`):
/// `(x, y) → (1 − y, x)`, the corners renumbered so TL stays first.
pub fn rotate_quad(q: &[f32; 8]) -> [f32; 8] {
    if is_trivial(q) {
        return *q;
    }
    [1.0 - q[7], q[6], 1.0 - q[1], q[0], 1.0 - q[3], q[2], 1.0 - q[5], q[4]]
}

/// Detections between a quad found and called stable.
const STABLE_AFTER: u32 = 10;
/// A corner moving less than this (of the diagonal) is still.
const STILL: f32 = 0.01;
/// Detect every this many frames (15 fps → 5 a second).
const DETECT_EVERY: u64 = 3;
/// Clean-up's cell size (output pixels).
const CELL: usize = 16;

/// Runs the person segmentation on its own thread; the newest mask wins.
struct SegWorker {
    tx: mpsc::SyncSender<Vec<u8>>,
    newest: Arc<Mutex<Option<Vec<f32>>>>,
}

impl SegWorker {
    fn start() -> Option<Self> {
        let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(1);
        let newest = Arc::new(Mutex::new(None));
        let out = newest.clone();
        std::thread::Builder::new()
            .name("ost-ccam-segment".into())
            .spawn(move || {
                let Ok(seg) = Segmenter::new() else { return };
                while let Ok(rgb) = rx.recv() {
                    if let Ok(m) = seg.segment(&rgb) {
                        *out.lock().unwrap() = Some(m);
                    }
                }
            })
            .ok()?;
        Some(Self { tx, newest })
    }
}

/// The effects for one camera, frame by frame.
pub struct Processor {
    opts: Options,
    quad: [f32; 8],
    stable: bool,
    still: u32,
    misses: u32,
    rotation: u32,
    frame_size: (u32, u32),
    count: u64,
    rotated: Vec<u8>,
    seg: Option<SegWorker>,
    mask: Vec<f32>,
    have_mask: bool,
    rect: Vec<u8>,
    out_mask: Vec<u8>,
    clean: Cleaner,
    out: Vec<u8>,
}

impl Default for Processor {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor {
    pub fn new() -> Self {
        Self {
            opts: Options::off(),
            quad: NO_QUAD,
            stable: false,
            still: 0,
            misses: 0,
            rotation: 0,
            frame_size: (0, 0),
            count: 0,
            rotated: Vec::new(),
            seg: None,
            mask: vec![0.0; MASK * MASK],
            have_mask: false,
            rect: Vec::new(),
            out_mask: Vec::new(),
            clean: Cleaner::default(),
            out: Vec::new(),
        }
    }

    /// Teams' `applyScanVideoEffect`. Detection starts afresh when it is
    /// turned on or given no quad; with it off the quad given is used as
    /// it is (Share freezes the detected one this way).
    pub fn apply(&mut self, o: Options) {
        let restart = o.quad_enabled && (!self.opts.quad_enabled || o.normalized_quad == NO_QUAD);
        if restart {
            self.quad = NO_QUAD;
            self.stable = false;
            self.still = 0;
            self.misses = 0;
        } else if !o.quad_enabled && o.normalized_quad != self.quad {
            self.quad = o.normalized_quad;
            self.stable = false;
        }
        if o.cleanup_enabled && !self.opts.cleanup_enabled {
            self.clean = Cleaner::default();
        }
        self.opts = o;
    }

    /// Teams' Rotate: a quarter turn clockwise; a stable quad turns with
    /// the picture and detection stops, else it goes on.
    pub fn rotate(&mut self) -> u32 {
        self.rotation = (self.rotation + 90) % 360;
        self.quad = rotate_quad(&self.quad);
        self.opts.normalized_quad = rotate_quad(&self.opts.normalized_quad);
        if self.stable {
            self.opts.quad_enabled = false;
        }
        self.clean = Cleaner::default();
        self.frame_size = (self.frame_size.1, self.frame_size.0);
        self.rotation
    }

    pub fn set_rotation(&mut self, degrees: u32) {
        while self.rotation != degrees % 360 {
            self.rotate();
        }
    }

    pub fn state(&self) -> State {
        State {
            quad_enabled: self.opts.quad_enabled,
            cleanup_enabled: self.opts.cleanup_enabled,
            zoom_enabled: self.opts.zoom_enabled,
            normalized_quad: self.quad,
            quad_stable: self.stable,
            frame_size: self.frame_size,
            rotation: self.rotation,
        }
    }

    /// The processed picture (I420, the input's size).
    pub fn process(&mut self, w: u32, h: u32, data: &[u8]) -> &[u8] {
        let (w, h) = (w as usize & !1, h as usize & !1);
        if w < 16 || h < 16 || data.len() < w * h * 3 / 2 {
            self.out.clear();
            self.out.extend_from_slice(data);
            return &self.out;
        }
        self.count += 1;
        let (sw, sh) = if self.rotation == 0 {
            (w, h)
        } else {
            rotate_i420(data, w, h, self.rotation, &mut self.rotated)
        };
        self.frame_size = (sw as u32, sh as u32);
        let rotated = std::mem::take(&mut self.rotated);
        let src: &[u8] = if self.rotation == 0 { data } else { &rotated };
        if self.opts.quad_enabled && self.count % DETECT_EVERY == 1 {
            let found = detect_quad(src, sw, sh);
            self.track(found, sw, sh);
        }
        // The presenter, for Overlay presenter.
        if self.opts.cleanup_enabled {
            if self.seg.is_none() {
                self.seg = SegWorker::start();
            }
            if let Some(s) = &self.seg {
                if self.count % 2 == 0 {
                    let _ = s.tx.try_send(model_input(src, sw as u32, sh as u32));
                }
                if let Some(m) = s.newest.lock().unwrap().take() {
                    if self.have_mask {
                        for (a, b) in self.mask.iter_mut().zip(m.iter()) {
                            *a = *a * 0.4 + *b * 0.6;
                        }
                    } else {
                        self.mask = m;
                        self.have_mask = true;
                    }
                }
            }
        } else {
            self.have_mask = false;
        }
        let quad = if self.opts.zoom_enabled && !is_trivial(&self.quad) { self.quad } else { FULL_FRAME };
        let corners = to_pixels(&quad, sw, sh);
        let fit = fit_rect(&corners, w, h);
        let mask = if self.opts.cleanup_enabled && self.have_mask { Some(&self.mask[..]) } else { None };
        rectify(src, sw, sh, &corners, fit, w, h, &mut self.rect, mask, &mut self.out_mask);
        if self.opts.cleanup_enabled {
            let m = if mask.is_some() { Some(&self.out_mask[..]) } else { None };
            self.clean.run(&self.rect, w, h, fit, m, &mut self.out);
        } else {
            std::mem::swap(&mut self.out, &mut self.rect);
        }
        self.rotated = rotated;
        &self.out
    }

    fn track(&mut self, found: Option<[f32; 8]>, sw: usize, sh: usize) {
        let Some(raw) = found else {
            self.misses += 1;
            self.still = 0;
            if self.misses >= 5 {
                self.stable = false;
            }
            return;
        };
        self.misses = 0;
        if self.quad == NO_QUAD || is_trivial(&self.quad) {
            self.quad = raw;
            self.still = 0;
            return;
        }
        let diag = ((sw * sw + sh * sh) as f32).sqrt();
        let mut moved = 0f32;
        for c in 0..4 {
            let dx = (raw[c * 2] - self.quad[c * 2]) * sw as f32;
            let dy = (raw[c * 2 + 1] - self.quad[c * 2 + 1]) * sh as f32;
            moved = moved.max((dx * dx + dy * dy).sqrt() / diag);
        }
        for i in 0..8 {
            self.quad[i] += 0.3 * (raw[i] - self.quad[i]);
        }
        if moved < STILL {
            self.still += 1;
            if self.still >= STABLE_AFTER {
                self.stable = true;
            }
        } else {
            self.still = 0;
            if moved > 5.0 * STILL {
                self.stable = false;
            }
        }
    }
}

/// Rotate an I420 picture clockwise by 90, 180 or 270°; its new size.
fn rotate_i420(src: &[u8], w: usize, h: usize, deg: u32, out: &mut Vec<u8>) -> (usize, usize) {
    let (ow, oh) = if deg == 180 { (w, h) } else { (h, w) };
    out.resize(w * h * 3 / 2, 0);
    let plane = |s: &[u8], d: &mut [u8], pw: usize, ph: usize| {
        let ow = if deg == 180 { pw } else { ph };
        for y in 0..ph {
            for x in 0..pw {
                let (nx, ny) = match deg {
                    90 => (ph - 1 - y, x),
                    180 => (pw - 1 - x, ph - 1 - y),
                    _ => (y, pw - 1 - x),
                };
                d[ny * ow + nx] = s[y * pw + x];
            }
        }
    };
    let (sy, sc) = src.split_at(w * h);
    let (su, sv) = sc.split_at((w / 2) * (h / 2));
    let (dy, dc) = out.split_at_mut(w * h);
    let (du, dv) = dc.split_at_mut((w / 2) * (h / 2));
    plane(sy, dy, w, h);
    plane(&su[..(w / 2) * (h / 2)], du, w / 2, h / 2);
    plane(&sv[..(w / 2) * (h / 2)], dv, w / 2, h / 2);
    (ow, oh)
}

/// A normalized quad in source pixels (edges, not centres).
fn to_pixels(q: &[f32; 8], sw: usize, sh: usize) -> [(f32, f32); 4] {
    let mut p = [(0f32, 0f32); 4];
    for (i, c) in p.iter_mut().enumerate() {
        *c = (q[i * 2] * sw as f32, q[i * 2 + 1] * sh as f32);
    }
    p
}

/// Where the rectified content goes in the w x h output: its aspect (the
/// average of opposite sides) fitted in, centred, on even pixels.
fn fit_rect(c: &[(f32, f32); 4], w: usize, h: usize) -> (usize, usize, usize, usize) {
    let d = |a: (f32, f32), b: (f32, f32)| ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
    let qw = (d(c[0], c[1]) + d(c[3], c[2])) / 2.0;
    let qh = (d(c[0], c[3]) + d(c[1], c[2])) / 2.0;
    let aspect = if qh > 1.0 { qw / qh } else { w as f32 / h as f32 };
    let (mut bw, mut bh) = if aspect > w as f32 / h as f32 {
        (w, (w as f32 / aspect).round() as usize)
    } else {
        ((h as f32 * aspect).round() as usize, h)
    };
    bw = (bw.clamp(2, w)) & !1;
    bh = (bh.clamp(2, h)) & !1;
    let bx = ((w - bw) / 2) & !1;
    let by = ((h - bh) / 2) & !1;
    (bx, by, bw, bh)
}

/// The unit square → the quad (Heckbert's square-to-quad), as
/// [a, b, c, d, e, f, g, h]: x = (a u + b v + c) / (g u + h v + 1), y alike.
fn square_to_quad(p: &[(f32, f32); 4]) -> [f32; 8] {
    let (x0, y0) = p[0];
    let (x1, y1) = p[1];
    let (x2, y2) = p[2];
    let (x3, y3) = p[3];
    let sx = x0 - x1 + x2 - x3;
    let sy = y0 - y1 + y2 - y3;
    if sx.abs() < 1e-6 && sy.abs() < 1e-6 {
        return [x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0.0, 0.0];
    }
    let (dx1, dx2, dy1, dy2) = (x1 - x2, x3 - x2, y1 - y2, y3 - y2);
    let den = dx1 * dy2 - dx2 * dy1;
    let den = if den.abs() < 1e-9 { 1e-9 } else { den };
    let g = (sx * dy2 - dx2 * sy) / den;
    let hh = (dx1 * sy - sx * dy1) / den;
    [x1 - x0 + g * x1, x3 - x0 + hh * x3, x0, y1 - y0 + g * y1, y3 - y0 + hh * y3, y0, g, hh]
}

#[inline]
fn bilinear(p: &[u8], pw: usize, ph: usize, x: f32, y: f32) -> u8 {
    let x = x.clamp(0.0, (pw - 1) as f32);
    let y = y.clamp(0.0, (ph - 1) as f32);
    let (x0, y0) = (x as usize, y as usize);
    let (x1, y1) = ((x0 + 1).min(pw - 1), (y0 + 1).min(ph - 1));
    let (fx, fy) = (x - x0 as f32, y - y0 as f32);
    let a = p[y0 * pw + x0] as f32;
    let b = p[y0 * pw + x1] as f32;
    let c = p[y1 * pw + x0] as f32;
    let d = p[y1 * pw + x1] as f32;
    let top = a + (b - a) * fx;
    let bot = c + (d - c) * fx;
    (top + (bot - top) * fy + 0.5) as u8
}

/// Warp the quad of `src` (sw x sh) into `fit` of a w x h output with
/// black bars; with a person mask (MASK x MASK over the source) also its
/// warped copy at output size (0–255).
#[allow(clippy::too_many_arguments)]
fn rectify(
    src: &[u8],
    sw: usize,
    sh: usize,
    corners: &[(f32, f32); 4],
    fit: (usize, usize, usize, usize),
    w: usize,
    h: usize,
    out: &mut Vec<u8>,
    mask: Option<&[f32]>,
    out_mask: &mut Vec<u8>,
) {
    let (bx, by, bw, bh) = fit;
    out.resize(w * h * 3 / 2, 0);
    let (oy, oc) = out.split_at_mut(w * h);
    let (ou, ov) = oc.split_at_mut((w / 2) * (h / 2));
    oy.fill(16);
    ou.fill(128);
    ov.fill(128);
    if mask.is_some() {
        out_mask.resize(w * h, 0);
        out_mask.fill(0);
    }
    let (sy, sc) = src.split_at(sw * sh);
    let (su, sv) = sc.split_at((sw / 2) * (sh / 2));
    let (cw, ch) = (sw / 2, sh / 2);
    let m = square_to_quad(corners);
    let (mx, my) = (MASK as f32 / sw as f32, MASK as f32 / sh as f32);
    // Luma: per row, the homography's terms are linear in u.
    let du = 1.0 / bw as f32;
    for y in 0..bh {
        let v = (y as f32 + 0.5) / bh as f32;
        let u0 = 0.5 * du;
        let (mut nx, mut ny, mut dd) = (m[0] * u0 + m[1] * v + m[2], m[3] * u0 + m[4] * v + m[5], m[6] * u0 + m[7] * v + 1.0);
        let (sx, sy_, sd) = (m[0] * du, m[3] * du, m[6] * du);
        let row = (by + y) * w + bx;
        for x in 0..bw {
            let inv = 1.0 / dd;
            let (px, py) = (nx * inv, ny * inv);
            oy[row + x] = bilinear(sy, sw, sh, px - 0.5, py - 0.5);
            if let Some(mk) = mask {
                let ix = ((px * mx) as usize).min(MASK - 1);
                let iy = ((py * my) as usize).min(MASK - 1);
                out_mask[row + x] = (mk[iy * MASK + ix] * 255.0) as u8;
            }
            nx += sx;
            ny += sy_;
            dd += sd;
        }
    }
    // Chroma at half size: each chroma sample sits between four lumas.
    let (cbx, cby, cbw, cbh) = (bx / 2, by / 2, bw / 2, bh / 2);
    let cdu = 1.0 / cbw as f32;
    for y in 0..cbh {
        let v = (y as f32 + 0.5) / cbh as f32;
        let u0 = 0.5 * cdu;
        let (mut nx, mut ny, mut dd) = (m[0] * u0 + m[1] * v + m[2], m[3] * u0 + m[4] * v + m[5], m[6] * u0 + m[7] * v + 1.0);
        let (sx, sy_, sd) = (m[0] * cdu, m[3] * cdu, m[6] * cdu);
        let row = (cby + y) * (w / 2) + cbx;
        for x in 0..cbw {
            let inv = 1.0 / dd;
            let (px, py) = (nx * inv * 0.5 - 0.5, ny * inv * 0.5 - 0.5);
            ou[row + x] = bilinear(su, cw, ch, px, py);
            ov[row + x] = bilinear(&sv[..cw * ch], cw, ch, px, py);
            nx += sx;
            ny += sy_;
            dd += sd;
        }
    }
}

/// The whiteboard clean-up's memory: the board's white per cell, and the
/// cleaned board as it was where the presenter now stands.
#[derive(Default)]
struct Cleaner {
    grid: (usize, usize),
    white: Vec<f32>,
    wu: Vec<f32>,
    wv: Vec<f32>,
    seen: Vec<bool>,
    board: Vec<u8>,
    board_key: (usize, usize, usize, usize),
}

impl Cleaner {
    fn run(&mut self, src: &[u8], w: usize, h: usize, fit: (usize, usize, usize, usize), mask: Option<&[u8]>, out: &mut Vec<u8>) {
        let (bx, by, bw, bh) = fit;
        out.resize(src.len(), 0);
        out.copy_from_slice(src);
        let gw = bw.div_ceil(CELL);
        let gh = bh.div_ceil(CELL);
        if self.grid != (gw, gh) {
            self.grid = (gw, gh);
            self.white = vec![0.0; gw * gh];
            self.wu = vec![128.0; gw * gh];
            self.wv = vec![128.0; gw * gh];
            self.seen = vec![false; gw * gh];
        }
        let (sy, sc) = src.split_at(w * h);
        let (su, sv) = sc.split_at((w / 2) * (h / 2));
        let cwid = w / 2;
        // 1. Each cell's white: its bright end (the 85th percentile of the
        // pixels nobody stands on), and the colour there.
        let mut hist = [0u16; 256];
        let mut fresh = vec![f32::NAN; gw * gh];
        for gy in 0..gh {
            for gx in 0..gw {
                hist.fill(0);
                let (x0, y0) = (bx + gx * CELL, by + gy * CELL);
                let (x1, y1) = ((x0 + CELL).min(bx + bw), (y0 + CELL).min(by + bh));
                let mut n = 0u32;
                for y in y0..y1 {
                    for x in x0..x1 {
                        let i = y * w + x;
                        if mask.is_some_and(|m| m[i] > 76) {
                            continue;
                        }
                        hist[sy[i] as usize] += 1;
                        n += 1;
                    }
                }
                let total = ((x1 - x0) * (y1 - y0)) as u32;
                if n * 4 < total {
                    continue;
                }
                let target = n - n * 85 / 100;
                let mut acc = 0u32;
                let mut val = 255usize;
                for v in (0..256).rev() {
                    acc += hist[v] as u32;
                    if acc >= target.max(1) {
                        val = v;
                        break;
                    }
                }
                fresh[gy * gw + gx] = val as f32;
                // The white's colour: chroma where the luma is near it.
                let (mut su_, mut sv_, mut k) = (0f32, 0f32, 0f32);
                for y in (y0..y1).step_by(2) {
                    for x in (x0..x1).step_by(2) {
                        if sy[y * w + x] as f32 >= val as f32 * 0.92 {
                            let ci = (y / 2) * cwid + x / 2;
                            su_ += su[ci] as f32;
                            sv_ += sv[ci] as f32;
                            k += 1.0;
                        }
                    }
                }
                let c = gy * gw + gx;
                if k > 0.0 {
                    let (u, v) = (su_ / k, sv_ / k);
                    if self.seen[c] {
                        self.wu[c] += 0.2 * (u - self.wu[c]);
                        self.wv[c] += 0.2 * (v - self.wv[c]);
                    } else {
                        self.wu[c] = u;
                        self.wv[c] = v;
                    }
                }
            }
        }
        // 2. A 3 x 3 median over the cells (ink-filled cells take their
        // neighbours' white), then eased into what was seen before.
        let mut med = vec![f32::NAN; gw * gh];
        let mut any = Vec::with_capacity(gw * gh);
        for gy in 0..gh {
            for gx in 0..gw {
                let mut v = [0f32; 9];
                let mut n = 0;
                for dy in -1i32..=1 {
                    for dx in -1i32..=1 {
                        let (x, y) = (gx as i32 + dx, gy as i32 + dy);
                        if x < 0 || y < 0 || x >= gw as i32 || y >= gh as i32 {
                            continue;
                        }
                        let f = fresh[y as usize * gw + x as usize];
                        if !f.is_nan() {
                            v[n] = f;
                            n += 1;
                        }
                    }
                }
                if n > 0 {
                    v[..n].sort_by(|a, b| a.partial_cmp(b).unwrap());
                    // The upper median: ink pulls cells darker, never lighter.
                    let m = v[n / 2];
                    med[gy * gw + gx] = m;
                    any.push(m);
                }
            }
        }
        let fallback = if any.is_empty() {
            200.0
        } else {
            any.sort_by(|a, b| a.partial_cmp(b).unwrap());
            any[any.len() * 3 / 4]
        };
        for c in 0..gw * gh {
            let m = med[c];
            if !m.is_nan() {
                if self.seen[c] {
                    self.white[c] += 0.25 * (m - self.white[c]);
                } else {
                    self.white[c] = m;
                    self.seen[c] = true;
                }
            } else if !self.seen[c] {
                self.white[c] = fallback;
            }
            self.white[c] = self.white[c].max(60.0);
        }
        // 3. Every pixel against its white (bilinear between cells).
        self.whiten(sy, su, sv, w, h, fit, out);
        // 4. Overlay presenter: the board as it was under them, the
        // presenter at half strength over it.
        let Some(m) = mask else { return };
        if self.board_key != fit || self.board.len() != out.len() {
            self.board_key = fit;
            self.board = out.clone();
        }
        let (oy, oc) = out.split_at_mut(w * h);
        let (ou, ov) = oc.split_at_mut((w / 2) * (h / 2));
        let (byp, bcp) = self.board.split_at_mut(w * h);
        let (bup, bvp) = bcp.split_at_mut((w / 2) * (h / 2));
        for y in by..by + bh {
            for x in bx..bx + bw {
                let i = y * w + x;
                let a = m[i] as f32 / 255.0;
                if a < 0.2 {
                    byp[i] = oy[i];
                } else {
                    let s = 0.5 * ((a - 0.2) / 0.3).clamp(0.0, 1.0);
                    oy[i] = (byp[i] as f32 * (1.0 - s) + sy[i] as f32 * s) as u8;
                }
            }
        }
        for y in (by / 2)..(by + bh) / 2 {
            for x in (bx / 2)..(bx + bw) / 2 {
                let ci = y * cwid + x;
                let a = m[(y * 2) * w + x * 2] as f32 / 255.0;
                if a < 0.2 {
                    bup[ci] = ou[ci];
                    bvp[ci] = ov[ci];
                } else {
                    let s = 0.5 * ((a - 0.2) / 0.3).clamp(0.0, 1.0);
                    ou[ci] = (bup[ci] as f32 * (1.0 - s) + su[ci] as f32 * s) as u8;
                    ov[ci] = (bvp[ci] as f32 * (1.0 - s) + sv[ci] as f32 * s) as u8;
                }
            }
        }
    }

    /// Divide every board pixel by its cell's white (bilinear between
    /// cells): white turns white, ink stays, darker and more saturated.
    #[allow(clippy::too_many_arguments)]
    fn whiten(&self, sy: &[u8], su: &[u8], sv: &[u8], w: usize, h: usize, fit: (usize, usize, usize, usize), out: &mut [u8]) {
        let (bx, by, bw, bh) = fit;
        let (gw, gh) = self.grid;
        let cwid = w / 2;
        let (oy, oc) = out.split_at_mut(w * h);
        let (ou, ov) = oc.split_at_mut((w / 2) * (h / 2));
        let white_at = |x: usize, y: usize, grid: &[f32]| -> f32 {
            let fx = ((x - bx) as f32 + 0.5) / CELL as f32 - 0.5;
            let fy = ((y - by) as f32 + 0.5) / CELL as f32 - 0.5;
            let fx = fx.clamp(0.0, (gw - 1) as f32);
            let fy = fy.clamp(0.0, (gh - 1) as f32);
            let (x0, y0) = (fx as usize, fy as usize);
            let (x1, y1) = ((x0 + 1).min(gw - 1), (y0 + 1).min(gh - 1));
            let (ax, ay) = (fx - x0 as f32, fy - y0 as f32);
            let t = grid[y0 * gw + x0] + (grid[y0 * gw + x1] - grid[y0 * gw + x0]) * ax;
            let b = grid[y1 * gw + x0] + (grid[y1 * gw + x1] - grid[y1 * gw + x0]) * ax;
            t + (b - t) * ay
        };
        for y in by..by + bh {
            for x in bx..bx + bw {
                let i = y * w + x;
                let c = sy[i] as f32 / white_at(x, y, &self.white);
                oy[i] = ink_luma(c);
            }
        }
        for y in (by / 2)..(by + bh) / 2 {
            for x in (bx / 2)..(bx + bw) / 2 {
                let ci = y * cwid + x;
                let (lx, ly) = (x * 2, y * 2);
                let c = sy[ly * w + lx] as f32 / white_at(lx, ly, &self.white);
                let k = ((0.85 - c) / 0.3).clamp(0.0, 1.0) * 1.7;
                let (wu, wv) = (white_at(lx, ly, &self.wu), white_at(lx, ly, &self.wv));
                ou[ci] = (128.0 + (su[ci] as f32 - wu) * k).clamp(16.0, 240.0) as u8;
                ov[ci] = (128.0 + (sv[ci] as f32 - wv) * k).clamp(16.0, 240.0) as u8;
            }
        }
    }
}

/// A pixel's luma after clean-up, from its brightness against the white:
/// near white is white, ink is stretched darker.
#[inline]
fn ink_luma(c: f32) -> u8 {
    if c >= 0.82 {
        return 235;
    }
    let t = ((c - 0.15) / (0.82 - 0.15)).clamp(0.0, 1.0);
    (16.0 + 219.0 * t.powf(1.5)) as u8
}

/// Find the whiteboard or page: the largest bright, colourless region
/// that is (nearly) a convex quadrilateral. Normalized TL, TR, BR, BL.
pub fn detect_quad(src: &[u8], w: usize, h: usize) -> Option<[f32; 8]> {
    let f = (w / 320).max(1);
    let (dw, dh) = (w / f, h / f);
    let (sy, sc) = src.split_at(w * h);
    let (su, sv) = sc.split_at((w / 2) * (h / 2));
    let mut ys = vec![0u8; dw * dh];
    let mut cd = vec![0u8; dw * dh];
    let mut hist = [0u32; 256];
    for y in 0..dh {
        for x in 0..dw {
            let mut s = 0u32;
            for yy in 0..f {
                let r = (y * f + yy) * w + x * f;
                for xx in 0..f {
                    s += sy[r + xx] as u32;
                }
            }
            let l = (s / (f * f) as u32) as u8;
            ys[y * dw + x] = l;
            hist[l as usize] += 1;
            let ci = ((y * f + f / 2) / 2).min(h / 2 - 1) * (w / 2) + ((x * f + f / 2) / 2).min(w / 2 - 1);
            let d = (su[ci] as i32 - 128).abs() + (sv[ci] as i32 - 128).abs();
            cd[y * dw + x] = d.min(255) as u8;
        }
    }
    let t = otsu(&hist, (dw * dh) as u32).max(90);
    let mut m: Vec<u8> = (0..dw * dh).map(|i| (ys[i] >= t && cd[i] < 48) as u8).collect();
    // Close: dilate then erode (3 x 3), bridging thin ink strokes.
    m = morph(&m, dw, dh, true);
    m = morph(&m, dw, dh, false);
    // The largest 4-connected region.
    let (label, count) = largest_component(&m, dw, dh)?;
    if count < dw * dh / 10 {
        return None;
    }
    // Its outline: each row's ends, as pixel edges.
    let mut pts = Vec::with_capacity(dh * 4);
    for y in 0..dh {
        let row = &label[y * dw..(y + 1) * dw];
        let Some(x0) = row.iter().position(|&v| v) else { continue };
        let x1 = row.iter().rposition(|&v| v).unwrap();
        for (px, py) in [(x0, y), (x0, y + 1), (x1 + 1, y), (x1 + 1, y + 1)] {
            pts.push((px as f32, py as f32));
        }
    }
    let hull = convex_hull(pts);
    if hull.len() < 4 {
        return None;
    }
    let quad = max_quad(&hull)?;
    let qa = poly_area(&quad);
    let ha = poly_area(&hull);
    let frame = (dw * dh) as f32;
    // Too small, not a quadrilateral, mostly holes — or the whole view
    // (nothing to zoom to: Teams counts the full frame as no quad).
    if qa < 0.15 * frame || qa > 0.92 * frame || ha > qa * 1.12 || (count as f32) < qa * 0.6 {
        return None;
    }
    for i in 0..4 {
        let (a, b, c) = (quad[(i + 3) % 4], quad[i], quad[(i + 1) % 4]);
        let (v1, v2) = ((a.0 - b.0, a.1 - b.1), (c.0 - b.0, c.1 - b.1));
        let cos = (v1.0 * v2.0 + v1.1 * v2.1) / ((v1.0.hypot(v1.1) * v2.0.hypot(v2.1)).max(1e-6));
        let deg = cos.clamp(-1.0, 1.0).acos().to_degrees();
        if !(50.0..=130.0).contains(&deg) {
            return None;
        }
    }
    // Clockwise on screen (y down), starting top left.
    let mut q = quad;
    let signed: f32 = (0..4).map(|i| q[i].0 * q[(i + 1) % 4].1 - q[(i + 1) % 4].0 * q[i].1).sum();
    if signed < 0.0 {
        q.reverse();
    }
    let start = (0..4).min_by(|&a, &b| (q[a].0 + q[a].1).partial_cmp(&(q[b].0 + q[b].1)).unwrap()).unwrap();
    let mut out = [0f32; 8];
    for i in 0..4 {
        let p = q[(start + i) % 4];
        out[i * 2] = (p.0 / dw as f32).clamp(0.0, 1.0);
        out[i * 2 + 1] = (p.1 / dh as f32).clamp(0.0, 1.0);
    }
    Some(out)
}

fn otsu(hist: &[u32; 256], total: u32) -> u8 {
    let sum: f64 = hist.iter().enumerate().map(|(i, &c)| i as f64 * c as f64).sum();
    let (mut sum_b, mut w_b, mut best, mut best_t) = (0f64, 0f64, 0f64, 128u8);
    for (t, &c) in hist.iter().enumerate() {
        w_b += c as f64;
        if w_b == 0.0 {
            continue;
        }
        let w_f = total as f64 - w_b;
        if w_f == 0.0 {
            break;
        }
        sum_b += t as f64 * c as f64;
        let (m_b, m_f) = (sum_b / w_b, (sum - sum_b) / w_f);
        let between = w_b * w_f * (m_b - m_f).powi(2);
        if between > best {
            best = between;
            best_t = t as u8;
        }
    }
    best_t.saturating_add(1)
}

fn morph(m: &[u8], w: usize, h: usize, dilate: bool) -> Vec<u8> {
    let mut tmp = vec![0u8; w * h];
    let mut out = vec![0u8; w * h];
    let pick = |a: u8, b: u8| if dilate { a.max(b) } else { a.min(b) };
    for y in 0..h {
        for x in 0..w {
            let mut v = m[y * w + x];
            if x > 0 {
                v = pick(v, m[y * w + x - 1]);
            }
            if x + 1 < w {
                v = pick(v, m[y * w + x + 1]);
            }
            tmp[y * w + x] = v;
        }
    }
    for y in 0..h {
        for x in 0..w {
            let mut v = tmp[y * w + x];
            if y > 0 {
                v = pick(v, tmp[(y - 1) * w + x]);
            }
            if y + 1 < h {
                v = pick(v, tmp[(y + 1) * w + x]);
            }
            out[y * w + x] = v;
        }
    }
    out
}

/// The largest 4-connected region of `m` (as a map) and its size.
fn largest_component(m: &[u8], w: usize, h: usize) -> Option<(Vec<bool>, usize)> {
    let mut lab = vec![0u32; w * h];
    let mut next = 0u32;
    let (mut best, mut best_n) = (0u32, 0usize);
    let mut stack = Vec::new();
    for start in 0..w * h {
        if m[start] == 0 || lab[start] != 0 {
            continue;
        }
        next += 1;
        lab[start] = next;
        stack.push(start);
        let mut n = 0;
        while let Some(i) = stack.pop() {
            n += 1;
            let (x, y) = (i % w, i / w);
            let mut push = |j: usize| {
                if m[j] != 0 && lab[j] == 0 {
                    lab[j] = next;
                    stack.push(j);
                }
            };
            if x > 0 {
                push(i - 1);
            }
            if x + 1 < w {
                push(i + 1);
            }
            if y > 0 {
                push(i - w);
            }
            if y + 1 < h {
                push(i + w);
            }
        }
        if n > best_n {
            best_n = n;
            best = next;
        }
    }
    if best == 0 {
        return None;
    }
    Some((lab.iter().map(|&l| l == best).collect(), best_n))
}

fn cross(o: (f32, f32), a: (f32, f32), b: (f32, f32)) -> f32 {
    (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
}

/// Andrew's monotone chain; nearly collinear points dropped.
fn convex_hull(mut p: Vec<(f32, f32)>) -> Vec<(f32, f32)> {
    p.sort_by(|a, b| a.partial_cmp(b).unwrap());
    p.dedup();
    if p.len() < 3 {
        return p;
    }
    let mut hull: Vec<(f32, f32)> = Vec::with_capacity(p.len() * 2);
    for pass in 0..2 {
        let start = hull.len();
        let iter: Box<dyn Iterator<Item = &(f32, f32)>> = if pass == 0 { Box::new(p.iter()) } else { Box::new(p.iter().rev()) };
        for &q in iter {
            while hull.len() >= start + 2 && cross(hull[hull.len() - 2], hull[hull.len() - 1], q) <= 0.0 {
                hull.pop();
            }
            hull.push(q);
        }
        hull.pop();
    }
    // Drop vertices on (nearly) straight runs: few corners to try.
    let mut changed = true;
    while changed && hull.len() > 4 {
        changed = false;
        let n = hull.len();
        for i in 0..n {
            let (a, b, c) = (hull[(i + n - 1) % n], hull[i], hull[(i + 1) % n]);
            let base = ((c.0 - a.0).powi(2) + (c.1 - a.1).powi(2)).sqrt().max(1e-6);
            if cross(a, b, c).abs() / base < 0.75 {
                hull.remove(i);
                changed = true;
                break;
            }
        }
    }
    hull
}

fn poly_area(p: &[(f32, f32)]) -> f32 {
    let n = p.len();
    (0..n).map(|i| p[i].0 * p[(i + 1) % n].1 - p[(i + 1) % n].0 * p[i].1).sum::<f32>().abs() / 2.0
}

/// The largest quadrilateral with corners on the hull.
fn max_quad(h: &[(f32, f32)]) -> Option<[(f32, f32); 4]> {
    let n = h.len();
    if n < 4 {
        return None;
    }
    let tri = |a: usize, b: usize, c: usize| cross(h[a], h[b], h[c]).abs() / 2.0;
    let mut best = (0f32, [0usize; 4]);
    for i in 0..n {
        for k in (i + 2)..n {
            if n - (k - i) < 2 {
                continue;
            }
            let (mut bj, mut aj) = (i + 1, 0f32);
            for j in (i + 1)..k {
                let a = tri(i, j, k);
                if a > aj {
                    aj = a;
                    bj = j;
                }
            }
            let (mut bl, mut al) = ((k + 1) % n, 0f32);
            let mut l = (k + 1) % n;
            while l != i {
                let a = tri(k, l, i);
                if a > al {
                    al = a;
                    bl = l;
                }
                l = (l + 1) % n;
            }
            if aj + al > best.0 {
                best = (aj + al, [i, bj, k, bl]);
            }
        }
    }
    if best.0 <= 0.0 {
        return None;
    }
    let [a, b, c, d] = best.1;
    Some([h[a], h[b], h[c], h[d]])
}

/// An I420 picture as RGBA (BT.601 limited range), for the preview.
pub fn to_rgba(i420: &[u8], w: usize, h: usize) -> Vec<u8> {
    super::i420_to_rgba(i420, w, h)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A w x h I420 picture: grey with a white board (the quad, in pixels)
    /// carrying dark strokes, lit unevenly.
    fn scene(w: usize, h: usize, quad: [(f32, f32); 4]) -> Vec<u8> {
        let mut f = vec![128u8; w * h * 3 / 2];
        let inside = |x: f32, y: f32| (0..4).all(|i| cross(quad[i], quad[(i + 1) % 4], (x, y)) >= 0.0);
        for y in 0..h {
            for x in 0..w {
                let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
                let v = if inside(px, py) {
                    // Brighter on the left (a window), strokes as bands.
                    let light = 210.0 - 40.0 * (x as f32 / w as f32);
                    let stroke = ((x / 9) % 7 == 0 && (y / 30) % 3 == 1) || ((y / 5) % 13 == 0 && x % 100 < 60);
                    if stroke { light * 0.35 } else { light }
                } else {
                    95.0 + 10.0 * ((x * 7 + y * 3) % 5) as f32 / 5.0
                };
                f[y * w + x] = v as u8;
            }
        }
        f
    }

    fn clockwise(q: [(f32, f32); 4]) -> [(f32, f32); 4] {
        // `scene`'s inside test wants the corners clockwise on screen.
        q
    }

    #[test]
    fn trivial_quads_are_teams_e0() {
        assert!(is_trivial(&FULL_FRAME));
        assert!(is_trivial(&NO_QUAD));
        assert!(!is_trivial(&[0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]));
    }

    #[test]
    fn rotate_quad_is_teams_formula() {
        let q = [0.1, 0.2, 0.8, 0.15, 0.85, 0.9, 0.12, 0.8];
        let r = rotate_quad(&q);
        // Teams: [1 − q7, q6, 1 − q1, q0, 1 − q3, q2, 1 − q5, q4].
        assert_eq!(r, [1.0 - 0.8, 0.12, 1.0 - 0.2, 0.1, 1.0 - 0.15, 0.8, 1.0 - 0.9, 0.85]);
        // Four turns are no turn.
        let mut s = q;
        for _ in 0..4 {
            s = rotate_quad(&s);
        }
        for i in 0..8 {
            assert!((s[i] - q[i]).abs() < 1e-6);
        }
        assert_eq!(rotate_quad(&FULL_FRAME), FULL_FRAME);
    }

    #[test]
    fn defaults_follow_teams() {
        let wb = Options::defaults(Kind::Whiteboard);
        assert!(wb.quad_enabled && wb.cleanup_enabled && wb.zoom_enabled);
        let doc = Options::defaults(Kind::Document);
        assert!(doc.quad_enabled && !doc.cleanup_enabled && doc.zoom_enabled);
        let v = Options::defaults(Kind::Video);
        assert!(!v.quad_enabled && !v.cleanup_enabled && v.zoom_enabled);
    }

    #[test]
    fn finds_a_slightly_turned_board() {
        let (w, h) = (640, 360);
        let truth = clockwise([(110.0, 60.0), (540.0, 80.0), (520.0, 310.0), (95.0, 290.0)]);
        let f = scene(w, h, truth);
        let q = detect_quad(&f, w, h).expect("a board");
        for i in 0..4 {
            let (x, y) = (q[i * 2] * w as f32, q[i * 2 + 1] * h as f32);
            let d = ((x - truth[i].0).powi(2) + (y - truth[i].1).powi(2)).sqrt();
            assert!(d < 8.0, "corner {i}: ({x}, {y}) vs {:?}", truth[i]);
        }
    }

    #[test]
    fn no_board_no_quad() {
        let (w, h) = (640, 360);
        let mut f = vec![128u8; w * h * 3 / 2];
        for y in 0..h {
            for x in 0..w {
                f[y * w + x] = ((x * 13 + y * 7) % 90 + 40) as u8;
            }
        }
        assert!(detect_quad(&f, w, h).is_none());
        // A bright disc is no quadrilateral.
        for y in 0..h {
            for x in 0..w {
                let d = ((x as f32 - 320.0).powi(2) + (y as f32 - 180.0).powi(2)).sqrt();
                f[y * w + x] = if d < 150.0 { 220 } else { 90 };
            }
        }
        assert!(detect_quad(&f, w, h).is_none());
    }

    #[test]
    fn full_frame_is_the_picture_itself() {
        let (w, h) = (64, 36);
        let mut f = vec![0u8; w * h * 3 / 2];
        for (i, v) in f.iter_mut().enumerate() {
            *v = (i * 7 % 200 + 20) as u8;
        }
        let c = to_pixels(&FULL_FRAME, w, h);
        let fit = fit_rect(&c, w, h);
        assert_eq!(fit, (0, 0, w, h));
        let (mut out, mut om) = (Vec::new(), Vec::new());
        rectify(&f, w, h, &c, fit, w, h, &mut out, None, &mut om);
        assert_eq!(out, f);
    }

    #[test]
    fn a_square_board_is_pillarboxed() {
        let c = [(100.0, 50.0), (300.0, 50.0), (300.0, 250.0), (100.0, 250.0)];
        let (bx, by, bw, bh) = fit_rect(&c, 640, 360);
        assert_eq!((by, bh), (0, 360));
        assert_eq!(bw, 360);
        assert_eq!(bx, 140);
    }

    #[test]
    fn rectified_board_fills_the_output_and_cleans_white() {
        let (w, h) = (640, 360);
        let truth = [(110.0, 60.0), (540.0, 80.0), (520.0, 310.0), (95.0, 290.0)];
        let f = scene(w, h, truth);
        let mut p = Processor::new();
        p.apply(Options::defaults(Kind::Whiteboard));
        // Overlay presenter needs the model; this test is about the board.
        p.opts.cleanup_enabled = false;
        for _ in 0..60 {
            p.process(w as u32, h as u32, &f);
        }
        let st = p.state();
        assert!(st.quad_stable, "{st:?}");
        assert!(!is_trivial(&st.normalized_quad));
        let out = p.process(w as u32, h as u32, &f).to_vec();
        // The board's middle is board, the grey is gone from the corners
        // of the content box.
        let fit = fit_rect(&to_pixels(&st.normalized_quad, w, h), w, h);
        let (bx, by, bw, bh) = fit;
        let at = |x: usize, y: usize| out[y * w + x];
        assert!(at(bx + 6, by + 6) > 150, "{}", at(bx + 6, by + 6));
        assert!(at(bx + bw - 7, by + bh - 7) > 140);
        // Clean-up: the uneven board turns white, ink stays dark.
        let mut c = Cleaner::default();
        let mut cleaned = Vec::new();
        c.run(&out, w, h, fit, None, &mut cleaned);
        let whites = (by + 10..by + bh - 10)
            .flat_map(|y| (bx + 10..bx + bw - 10).map(move |x| (x, y)))
            .filter(|&(x, y)| out[y * w + x] > 150)
            .map(|(x, y)| cleaned[y * w + x] as u32)
            .collect::<Vec<_>>();
        let mean = whites.iter().sum::<u32>() as f32 / whites.len() as f32;
        assert!(mean > 225.0, "white {mean}");
        let inks = (by..by + bh)
            .flat_map(|y| (bx..bx + bw).map(move |x| (x, y)))
            .filter(|&(x, y)| out[y * w + x] < 90)
            .map(|(x, y)| cleaned[y * w + x] as u32)
            .collect::<Vec<_>>();
        assert!(!inks.is_empty());
        let ink = inks.iter().sum::<u32>() as f32 / inks.len() as f32;
        assert!(ink < 90.0, "ink {ink}");
    }

    #[test]
    fn share_freezes_the_quad() {
        let (w, h) = (640, 360);
        let truth = [(110.0, 60.0), (540.0, 80.0), (520.0, 310.0), (95.0, 290.0)];
        let f = scene(w, h, truth);
        let mut p = Processor::new();
        p.apply(Options { cleanup_enabled: false, ..Options::defaults(Kind::Document) });
        for _ in 0..60 {
            p.process(w as u32, h as u32, &f);
        }
        let st = p.state();
        assert!(st.quad_stable);
        // Teams' Share: detection off, the stable quad kept.
        p.apply(Options { quad_enabled: false, cleanup_enabled: false, zoom_enabled: true, normalized_quad: st.normalized_quad });
        let grey = vec![100u8; w * h * 3 / 2];
        p.process(w as u32, h as u32, &grey);
        assert_eq!(p.state().normalized_quad, st.normalized_quad);
        assert!(!p.state().quad_enabled);
        // Scan Again: zeros, detection on again.
        p.apply(Options::off());
        p.apply(Options { quad_enabled: true, cleanup_enabled: false, zoom_enabled: true, normalized_quad: NO_QUAD });
        assert_eq!(p.state().normalized_quad, NO_QUAD);
        assert!(!p.state().quad_stable);
    }

    #[test]
    fn rotation_turns_frame_and_quad() {
        let (w, h) = (64, 36);
        let mut f = vec![128u8; w * h * 3 / 2];
        f[0] = 250; // top left luma
        let mut p = Processor::new();
        p.apply(Options { quad_enabled: false, cleanup_enabled: false, zoom_enabled: true, normalized_quad: [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9] });
        p.process(w as u32, h as u32, &f);
        assert_eq!(p.state().frame_size, (64, 36));
        assert_eq!(p.rotate(), 90);
        let out = p.process(w as u32, h as u32, &f).to_vec();
        assert_eq!(p.state().frame_size, (36, 64));
        assert_eq!(out.len(), w * h * 3 / 2);
        let mut r = Vec::new();
        let (rw, rh) = rotate_i420(&f, w, h, 90, &mut r);
        assert_eq!((rw, rh), (36, 64));
        // Top left goes to top right.
        assert_eq!(r[rw - 1], 250);
    }

    #[test]
    fn a_wobbling_quad_is_not_stable() {
        let mut p = Processor::new();
        p.apply(Options::defaults(Kind::Document));
        for i in 0..40 {
            let d = if i % 2 == 0 { 0.0 } else { 0.05 };
            p.track(Some([0.1 + d, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]), 640, 360);
        }
        assert!(!p.state().quad_stable);
        for _ in 0..12 {
            p.track(Some([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]), 640, 360);
        }
        // Eased in, then still for ten detections.
        for _ in 0..20 {
            p.track(Some([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]), 640, 360);
        }
        assert!(p.state().quad_stable);
    }
}
