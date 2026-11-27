//! Video effects, as Teams applies them to your camera: Standard and
//! Portrait blur, a background picture (still or animated), Adjust
//! brightness (low light), Soft focus and Denoising, on I420 frames. A person segmentation model (PP-HumanSeg, Apache-2.0, run with
//! tract) finds you in the picture on a worker thread; each frame uses the
//! newest mask, smoothed over time, so the camera never waits for it.

use std::sync::{Arc, Mutex, mpsc};

use tract_onnx::prelude::*;

pub mod avatar;
pub mod content_camera;
pub mod sign_detection;
pub mod voice_isolation;

/// The model's input and mask size.
pub const MASK: usize = 192;

static MODEL: &[u8] = include_bytes!("../human_segmentation_pphumanseg_2023mar.onnx");

/// What is behind you.
#[derive(Clone, Default)]
pub enum Background {
    #[default]
    None,
    /// Teams' Standard blur (strong) or Portrait blur (lighter, more like a
    /// camera's shallow focus).
    Blur(Blur),
    /// A picture (I420, any size; fitted to cover the frame).
    Picture(Arc<Picture>),
    /// A moving picture: its newest frame, kept up to date by its player.
    Animated(Arc<Animated>),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Blur {
    #[default]
    Standard,
    Portrait,
}

/// An animated background's current frame.
#[derive(Default)]
pub struct Animated {
    frame: Mutex<Option<Arc<Picture>>>,
    /// When a camera frame last asked for it (ms since the epoch): its
    /// player rests while no camera is using it.
    wanted: std::sync::atomic::AtomicU64,
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

impl Animated {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// The player's newest frame.
    pub fn set_frame(&self, p: Picture) {
        *self.frame.lock().unwrap() = Some(Arc::new(p));
    }

    pub fn frame(&self) -> Option<Arc<Picture>> {
        self.wanted
            .store(now_ms(), std::sync::atomic::Ordering::Relaxed);
        self.frame.lock().unwrap().clone()
    }

    /// Whether a camera used it in the last two seconds.
    pub fn in_use(&self) -> bool {
        now_ms().saturating_sub(self.wanted.load(std::sync::atomic::Ordering::Relaxed)) < 2000
    }
}

/// A background picture as I420.
pub struct Picture {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

impl Picture {
    /// I420 data as it is (`data` holds width x height x 3/2 bytes).
    pub fn from_i420(width: u32, height: u32, data: Vec<u8>) -> Self {
        Self {
            width,
            height,
            data,
        }
    }

    /// From RGBA pixels.
    pub fn from_rgba(width: u32, height: u32, rgba: &[u8]) -> Self {
        let (w, h) = (width as usize & !1, height as usize & !1);
        let mut data = vec![0u8; w * h * 3 / 2];
        let (yp, uv) = data.split_at_mut(w * h);
        let (up, vp) = uv.split_at_mut(w * h / 4);
        for y in 0..h {
            for x in 0..w {
                let i = (y * width as usize + x) * 4;
                let (r, g, b) = (rgba[i] as f32, rgba[i + 1] as f32, rgba[i + 2] as f32);
                yp[y * w + x] = (0.257 * r + 0.504 * g + 0.098 * b + 16.0).clamp(0.0, 255.0) as u8;
                if y % 2 == 0 && x % 2 == 0 {
                    let c = (y / 2) * (w / 2) + x / 2;
                    up[c] = (-0.148 * r - 0.291 * g + 0.439 * b + 128.0).clamp(0.0, 255.0) as u8;
                    vp[c] = (0.439 * r - 0.368 * g - 0.071 * b + 128.0).clamp(0.0, 255.0) as u8;
                }
            }
        }
        Self {
            width: w as u32,
            height: h as u32,
            data,
        }
    }
}

/// The effects chosen (shared by the camera paths).
#[derive(Clone, Default)]
pub struct Settings {
    pub background: Background,
    /// Teams' Adjust brightness.
    pub brightness: bool,
    /// Teams' Soft focus: your skin smoothed.
    pub soft_focus: bool,
    /// Teams' Denoising (Settings ▸ Devices ▸ Video, on unless turned
    /// off): the camera's grain evened out over time before the other
    /// effects (Teams' camera video filter `Denoising`, set on the camera
    /// itself, so your preview and what is sent both show it).
    pub denoise: bool,
    /// Teams' Green Screen: with a background on, what is your backdrop's
    /// colour is keyed out (sharper edges, things you hold stay). `None`
    /// keeps the person mask alone.
    pub green_screen: Option<GreenScreen>,
}

static PICKING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Teams' Weatherperson effect (presenter modes Standout and Reporter):
/// your camera is sent with the background cut out, written into the
/// picture itself (an "implicit mask" in the luma), so each receiver can
/// lay you over the shared screen.
static PRESENTER: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Turn the Weatherperson effect on or off for every camera picture.
pub fn set_presenter_mask(on: bool) {
    PRESENTER.store(on, std::sync::atomic::Ordering::Relaxed);
}

pub fn presenter_mask() -> bool {
    PRESENTER.load(std::sync::atomic::Ordering::Relaxed)
}

/// SlimCV's implicit mask (ExtractAlphaLuma's inverse, as Teams' web
/// compositor documents it): compressionFactor 28, REDUCED_RANGE 16–240,
/// LUMA_COMPRESS_LEVEL 32. Your luma is squeezed into 59…255; the
/// background is black (below the receivers' threshold of 23).
pub mod implicit {
    pub const RANGE_HIGH: f32 = 240.0;
    pub const RANGE_LOW: f32 = 16.0;
    /// compressionFactor / LUMA_COMPRESS_LEVEL.
    pub const CF: f32 = 28.0 / 32.0;
    /// lumaMin = 255 − (240 − 16) × 28 / 32.
    pub const LUMA_MIN: u8 = 59;
    /// floor(59 × 0.4): below it is background.
    pub const THRESHOLD: u8 = 23;

    /// A person's luma, squeezed into LUMA_MIN…255.
    pub fn encode(y: u8) -> u8 {
        let y = (y as f32).clamp(RANGE_LOW, RANGE_HIGH);
        (255.0 - (RANGE_HIGH - y) * CF)
            .round()
            .clamp(LUMA_MIN as f32, 255.0) as u8
    }

    /// RestorePixel: 240 − (255 − y) × 32/28.
    pub fn decode(y: u8) -> u8 {
        (RANGE_HIGH - (255.0 - y as f32) / CF).max(0.0).round() as u8
    }
}

/// Write the implicit mask into an I420 frame: where `mask` (MASK x
/// MASK, the person's chance) is under one half the luma is 0 and the
/// colour neutral; elsewhere the luma is squeezed into 59…255.
pub fn apply_implicit_mask(data: &mut [u8], mask: &[f32], w: usize, h: usize) {
    if data.len() < w * h * 3 / 2 || mask.len() < MASK * MASK {
        return;
    }
    let (cw, ch) = (w / 2, h / 2);
    let at = |x: usize, y: usize| {
        mask[(y * MASK / h).min(MASK - 1) * MASK + (x * MASK / w).min(MASK - 1)]
    };
    let (yp, uv) = data.split_at_mut(w * h);
    let (up, vp) = uv.split_at_mut(cw * ch);
    for y in 0..h {
        for x in 0..w {
            let i = y * w + x;
            yp[i] = if at(x, y) >= 0.5 {
                implicit::encode(yp[i])
            } else {
                0
            };
        }
    }
    for cy in 0..ch {
        for cx in 0..cw {
            let back = (0..2).all(|dy| (0..2).all(|dx| yp[(cy * 2 + dy) * w + cx * 2 + dx] == 0));
            if back {
                up[cy * cw + cx] = 128;
                vp[cy * cw + cx] = 128;
            }
        }
    }
}

/// An I420 picture as RGBA at full resolution (BT.601 limited range; each
/// 2 x 2 block shares its chroma).
pub fn i420_to_rgba(i420: &[u8], w: usize, h: usize) -> Vec<u8> {
    let mut out = vec![255u8; w * h * 4];
    if w < 2 || h < 2 || i420.len() < w * h * 3 / 2 {
        return out;
    }
    let (y_plane, rest) = i420.split_at(w * h);
    let (u_plane, v_plane) = rest.split_at((w / 2) * (h / 2));
    for py in 0..h {
        let crow = (py / 2).min(h / 2 - 1) * (w / 2);
        for px in 0..w {
            let y = y_plane[py * w + px] as f32 - 16.0;
            let ci = crow + (px / 2).min(w / 2 - 1);
            let (u, v) = (u_plane[ci] as f32 - 128.0, v_plane[ci] as f32 - 128.0);
            let o = (py * w + px) * 4;
            out[o] = (1.164 * y + 1.596 * v).clamp(0.0, 255.0) as u8;
            out[o + 1] = (1.164 * y - 0.392 * u - 0.813 * v).clamp(0.0, 255.0) as u8;
            out[o + 2] = (1.164 * y + 2.017 * u).clamp(0.0, 255.0) as u8;
        }
    }
    out
}

/// A received camera with an implicit mask, as RGBA: Teams' compositor
/// shader (a 3x3 luma erosion against the threshold; the rest restored
/// and decoded as BT.601) — background pixels come out transparent.
pub fn implicit_mask_rgba(
    yp: &[u8],
    up: &[u8],
    vp: &[u8],
    strides: (usize, usize, usize),
    w: usize,
    h: usize,
    out: &mut [u8],
) {
    if out.len() < w * h * 4 {
        return;
    }
    let luma = |x: isize, y: isize| -> u8 {
        let (x, y) = (
            x.clamp(0, w as isize - 1) as usize,
            y.clamp(0, h as isize - 1) as usize,
        );
        yp[y * strides.0 + x]
    };
    for y in 0..h {
        for x in 0..w {
            let o = (y * w + x) * 4;
            let (xi, yi) = (x as isize, y as isize);
            let mut keep = true;
            'n: for dy in -1..=1 {
                for dx in -1..=1 {
                    if luma(xi + dx, yi + dy) < implicit::THRESHOLD {
                        keep = false;
                        break 'n;
                    }
                }
            }
            if !keep {
                out[o..o + 4].copy_from_slice(&[0, 0, 0, 0]);
                continue;
            }
            let yv = implicit::decode(yp[y * strides.0 + x]) as f32;
            let u = up[(y / 2) * strides.1 + x / 2] as f32;
            let v = vp[(y / 2) * strides.2 + x / 2] as f32;
            let rgb = yuv_to_rgb(yv, u, v);
            out[o..o + 3].copy_from_slice(&rgb);
            out[o + 3] = 255;
        }
    }
}

/// Green Screen's colour picking: the camera picture without effects
/// meanwhile.
pub fn set_picking(on: bool) {
    PICKING.store(on, std::sync::atomic::Ordering::Relaxed);
}

/// Green Screen's backdrop colour (RGB), or `None` to detect it.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GreenScreen {
    pub color: Option<[u8; 3]>,
}

fn detected_cell() -> &'static Mutex<Option<[u8; 3]>> {
    static D: std::sync::OnceLock<Mutex<Option<[u8; 3]>>> = std::sync::OnceLock::new();
    D.get_or_init(|| Mutex::new(None))
}

/// The backdrop colour Green Screen found behind you (RGB), once it has.
pub fn detected_backdrop() -> Option<[u8; 3]> {
    *detected_cell().lock().unwrap()
}

pub fn rgb_to_yuv(c: [u8; 3]) -> [f32; 3] {
    let (r, g, b) = (c[0] as f32, c[1] as f32, c[2] as f32);
    [
        0.257 * r + 0.504 * g + 0.098 * b + 16.0,
        -0.148 * r - 0.291 * g + 0.439 * b + 128.0,
        0.439 * r - 0.368 * g - 0.071 * b + 128.0,
    ]
}

pub fn yuv_to_rgb(y: f32, u: f32, v: f32) -> [u8; 3] {
    let (y, u, v) = (y - 16.0, u - 128.0, v - 128.0);
    [
        (1.164 * y + 1.596 * v).clamp(0.0, 255.0) as u8,
        (1.164 * y - 0.392 * u - 0.813 * v).clamp(0.0, 255.0) as u8,
        (1.164 * y + 2.017 * u).clamp(0.0, 255.0) as u8,
    ]
}

fn settings() -> &'static Mutex<Settings> {
    static S: std::sync::OnceLock<Mutex<Settings>> = std::sync::OnceLock::new();
    S.get_or_init(|| Mutex::new(Settings::default()))
}

/// Choose the effects for every camera picture from now on.
pub fn set(s: Settings) {
    *settings().lock().unwrap() = s;
}

pub fn current() -> Settings {
    settings().lock().unwrap().clone()
}

/// Person segmentation: a 192 x 192 RGB picture in, the chance that each
/// point is a person (0–1) out.
pub struct Segmenter {
    model: Arc<TypedRunnableModel>,
}

impl Segmenter {
    pub fn new() -> anyhow::Result<Self> {
        let model = tract_onnx::onnx()
            .model_for_read(&mut &MODEL[..])?
            .with_input_fact(0, f32::fact([1, 3, MASK, MASK]).into())?
            .into_optimized()?
            .into_runnable()?;
        Ok(Self { model })
    }

    /// `rgb`: MASK x MASK x 3 bytes. The mask, MASK x MASK.
    pub fn segment(&self, rgb: &[u8]) -> anyhow::Result<Vec<f32>> {
        // PP-HumanSeg's input: RGB scaled to −1..1 (mean 0.5, std 0.5).
        let input: Tensor =
            tract_ndarray::Array4::<f32>::from_shape_fn((1, 3, MASK, MASK), |(_, c, y, x)| {
                rgb[(y * MASK + x) * 3 + c] as f32 / 127.5 - 1.0
            })
            .into();
        let out = self.model.run(tvec!(input.into()))?;
        let logits = out[0].to_plain_array_view::<f32>()?;
        let mut mask = vec![0f32; MASK * MASK];
        for y in 0..MASK {
            for x in 0..MASK {
                // Two classes (background, person): the person's softmax.
                let (b, p) = (logits[[0, 0, y, x]], logits[[0, 1, y, x]]);
                mask[y * MASK + x] = 1.0 / (1.0 + (b - p).exp());
            }
        }
        Ok(mask)
    }
}

/// An I420 frame's colours at a point (nearest), as RGB.
fn rgb_at(data: &[u8], w: usize, h: usize, x: usize, y: usize) -> [u8; 3] {
    let yv = data[y * w + x] as f32 - 16.0;
    let c = (y / 2) * (w / 2) + x / 2;
    let u = data[w * h + c] as f32 - 128.0;
    let v = data[w * h + w * h / 4 + c] as f32 - 128.0;
    let r = 1.164 * yv + 1.596 * v;
    let g = 1.164 * yv - 0.392 * u - 0.813 * v;
    let b = 1.164 * yv + 2.017 * u;
    [
        r.clamp(0.0, 255.0) as u8,
        g.clamp(0.0, 255.0) as u8,
        b.clamp(0.0, 255.0) as u8,
    ]
}

/// The frame shrunk to the model's input.
pub fn model_input(data: &[u8], w: u32, h: u32) -> Vec<u8> {
    let (w, h) = (w as usize, h as usize);
    let mut rgb = vec![0u8; MASK * MASK * 3];
    for my in 0..MASK {
        for mx in 0..MASK {
            let x = (mx * w + w / 2) / MASK;
            let y = (my * h + h / 2) / MASK;
            let p = rgb_at(data, w, h, x.min(w - 1), y.min(h - 1));
            rgb[(my * MASK + mx) * 3..][..3].copy_from_slice(&p);
        }
    }
    rgb
}

/// Applies the chosen effects to camera frames.
pub struct Processor {
    to_worker: Option<mpsc::SyncSender<Vec<u8>>>,
    newest: Arc<Mutex<Option<Vec<f32>>>>,
    /// The mask used, eased towards each new one.
    mask: Vec<f32>,
    have_mask: bool,
    /// The background picture fitted to the frame size (cached).
    fitted: Option<(usize, usize, *const Picture, Vec<u8>)>,
    blur: Vec<u8>,
    denoiser: Denoiser,
}

// The cached picture pointer is only compared, never read through.
unsafe impl Send for Processor {}

impl Default for Processor {
    fn default() -> Self {
        Self::new()
    }
}

impl Processor {
    pub fn new() -> Self {
        Self {
            to_worker: None,
            newest: Arc::new(Mutex::new(None)),
            mask: vec![0.0; MASK * MASK],
            have_mask: false,
            fitted: None,
            blur: Vec::new(),
            denoiser: Denoiser::default(),
        }
    }

    fn worker(&mut self) -> Option<&mpsc::SyncSender<Vec<u8>>> {
        if self.to_worker.is_none() {
            let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(1);
            let newest = self.newest.clone();
            let spawned = std::thread::Builder::new()
                .name("ost-vfx-segment".into())
                .spawn(move || {
                    let seg = match Segmenter::new() {
                        Ok(s) => s,
                        Err(e) => {
                            eprintln!("ost-vfx: the segmentation model didn't load: {e}");
                            return;
                        }
                    };
                    while let Ok(rgb) = rx.recv() {
                        if let Ok(mask) = seg.segment(&rgb) {
                            *newest.lock().unwrap() = Some(mask);
                        }
                    }
                });
            if spawned.is_ok() {
                self.to_worker = Some(tx);
            }
        }
        self.to_worker.as_ref()
    }

    /// Apply the chosen effects to an I420 frame in place: brightness,
    /// soft focus and the background, then a video app's filter.
    /// The Weatherperson effect, after [`Self::process`] (and after the
    /// self-view took its copy): the background cut out into the luma.
    /// Nothing until the first mask is in.
    pub fn presenter_effect(&mut self, width: u32, height: u32, data: &mut [u8]) {
        if presenter_mask() && self.have_mask {
            apply_implicit_mask(data, &self.mask, width as usize, height as usize);
        }
    }

    pub fn process(&mut self, width: u32, height: u32, data: &mut [u8]) {
        // An avatar is drawn with its own background; Teams' video effects
        // are the camera's.
        if avatar::active() {
            return;
        }
        // Denoising is the camera's own filter: first, and also while you
        // pick Green Screen's colour.
        if current().denoise {
            self.denoiser.apply(width as usize, height as usize, data);
        } else {
            self.denoiser.reset();
        }
        // While you pick Green Screen's colour you see your real backdrop.
        if PICKING.load(std::sync::atomic::Ordering::Relaxed) {
            return;
        }
        self.own_effects(width, height, data);
        filter::apply(width, height, data);
    }

    fn own_effects(&mut self, width: u32, height: u32, data: &mut [u8]) {
        let s = current();
        let (w, h) = (width as usize, height as usize);
        if data.len() < w * h * 3 / 2 || w < 2 || h < 2 {
            return;
        }
        if s.brightness {
            brighten(&mut data[..w * h]);
        }
        let presenter = presenter_mask();
        if matches!(s.background, Background::None) && !s.soft_focus && !presenter {
            self.have_mask = false;
            return;
        }
        // A new picture for the model when it is free (the newest frame).
        let input = model_input(data, width, height);
        if let Some(tx) = self.worker() {
            let _ = tx.try_send(input);
        }
        if let Some(m) = self.newest.lock().unwrap().take() {
            if self.have_mask {
                for (a, b) in self.mask.iter_mut().zip(m.iter()) {
                    *a = *a * 0.4 + *b * 0.6;
                }
            } else {
                self.mask = m;
                self.have_mask = true;
            }
        }
        if !self.have_mask {
            return;
        }
        if s.soft_focus {
            soften(&mut data[..w * h], &self.mask, w, h, &mut self.blur);
        }
        if presenter && matches!(s.background, Background::None) {
            return;
        }
        // What goes behind you.
        let picture = match &s.background {
            Background::Picture(p) => Some(p.clone()),
            Background::Animated(a) => a.frame(),
            _ => None,
        };
        let back: &[u8] = match (&s.background, picture) {
            (Background::Blur(kind), _) => {
                blur_i420(
                    data,
                    w,
                    h,
                    if *kind == Blur::Portrait { 4 } else { 8 },
                    &mut self.blur,
                );
                &self.blur
            }
            (_, Some(p)) => {
                let key = Arc::as_ptr(&p);
                if !matches!(&self.fitted, Some((fw, fh, k, _)) if *fw == w && *fh == h && *k == key)
                {
                    self.fitted = Some((w, h, key, fit_cover(&p, w, h)));
                }
                &self.fitted.as_ref().unwrap().3
            }
            _ => return,
        };
        match s.green_screen {
            Some(GreenScreen { color: Some(c) }) => {
                let yuv = rgb_to_yuv(c);
                composite_keyed(data, back, w, h, [yuv[1], yuv[2]]);
            }
            Some(GreenScreen { color: None }) => {
                // Find the backdrop: the average of what the mask calls
                // background.
                if let Some(c) = backdrop_colour(data, &self.mask, w, h) {
                    *detected_cell().lock().unwrap() = Some(c);
                }
                composite(data, back, &self.mask, w, h);
            }
            None => composite(data, back, &self.mask, w, h),
        }
    }
}

/// The average colour (RGB) where the mask is sure there's no one.
pub fn backdrop_colour(data: &[u8], mask: &[f32], w: usize, h: usize) -> Option<[u8; 3]> {
    let (mut sy, mut su, mut sv, mut n) = (0f64, 0f64, 0f64, 0f64);
    let (cw, ch) = (w / 2, h / 2);
    for y in (0..ch).step_by(2) {
        for x in (0..cw).step_by(2) {
            if alpha_at(mask, w, h, x * 2, y * 2) > 0.02 {
                continue;
            }
            sy += data[(y * 2) * w + x * 2] as f64;
            su += data[w * h + y * cw + x] as f64;
            sv += data[w * h + cw * ch + y * cw + x] as f64;
            n += 1.0;
        }
    }
    (n > 50.0).then(|| yuv_to_rgb((sy / n) as f32, (su / n) as f32, (sv / n) as f32))
}

/// Green Screen: what is close to the backdrop's chroma (`key` U, V)
/// becomes the background, the rest stays; a soft band between keeps edges
/// clean.
pub fn composite_keyed(data: &mut [u8], back: &[u8], w: usize, h: usize, key: [f32; 2]) {
    let (cw, ch) = (w / 2, h / 2);
    let mut alpha = vec![0f32; cw * ch];
    for y in 0..ch {
        for x in 0..cw {
            let u = data[w * h + y * cw + x] as f32 - key[0];
            let v = data[w * h + cw * ch + y * cw + x] as f32 - key[1];
            let d = (u * u + v * v).sqrt();
            let t = ((d - 10.0) / 18.0).clamp(0.0, 1.0);
            alpha[y * cw + x] = t * t * (3.0 - 2.0 * t);
        }
    }
    for y in 0..h {
        for x in 0..w {
            let a = alpha[(y / 2) * cw + x / 2];
            let i = y * w + x;
            data[i] = (data[i] as f32 * a + back[i] as f32 * (1.0 - a)) as u8;
        }
    }
    for y in 0..ch {
        for x in 0..cw {
            let a = alpha[y * cw + x];
            for plane in [w * h, w * h + cw * ch] {
                let i = plane + y * cw + x;
                data[i] = (data[i] as f32 * a + back[i] as f32 * (1.0 - a)) as u8;
            }
        }
    }
}

/// A video app's filter (Teams' Filters: Frames, Styles): the app runs
/// elsewhere (the desktop hosts Teams' Custom Filters web app); camera
/// frames are handed to it as NV12 and its newest processed frame comes
/// back. The camera never waits: each frame goes out, and the latest
/// result (when recent and the same size) replaces it.
pub mod filter {
    use std::sync::{Condvar, Mutex, OnceLock};
    use std::time::{Duration, Instant};

    /// A frame in NV12 (Y plane, then interleaved UV), as Teams' video apps
    /// take them.
    #[derive(Clone, Debug, PartialEq)]
    pub struct Frame {
        pub width: u32,
        pub height: u32,
        pub seq: u64,
        pub data: Vec<u8>,
    }

    #[derive(Default)]
    struct State {
        active: bool,
        next_seq: u64,
        /// The newest camera frame waiting for the app.
        inbound: Option<Frame>,
        /// The app's newest result, and when it came.
        outbound: Option<(Frame, Instant)>,
    }

    fn state() -> &'static (Mutex<State>, Condvar) {
        static S: OnceLock<(Mutex<State>, Condvar)> = OnceLock::new();
        S.get_or_init(|| (Mutex::new(State::default()), Condvar::new()))
    }

    /// Turn the filter path on (a filter is chosen and its app runs) or off.
    pub fn set_active(on: bool) {
        let (m, cv) = state();
        let mut s = m.lock().unwrap();
        s.active = on;
        if !on {
            s.inbound = None;
            s.outbound = None;
        }
        cv.notify_all();
    }

    pub fn active() -> bool {
        state().0.lock().unwrap().active
    }

    /// How long a result stays usable (the app's last frame is shown no
    /// longer than this when it stalls).
    const FRESH: Duration = Duration::from_millis(400);

    /// The camera side: hand this frame to the app and replace it with the
    /// app's newest result.
    pub fn apply(width: u32, height: u32, i420: &mut [u8]) {
        let (m, cv) = state();
        let mut s = m.lock().unwrap();
        if !s.active {
            return;
        }
        s.next_seq += 1;
        let seq = s.next_seq;
        s.inbound = Some(Frame {
            width,
            height,
            seq,
            data: i420_to_nv12(i420, width as usize, height as usize),
        });
        cv.notify_all();
        if let Some((f, at)) = &s.outbound
            && f.width == width
            && f.height == height
            && at.elapsed() < FRESH
        {
            nv12_to_i420(&f.data, width as usize, height as usize, i420);
        }
    }

    /// The app side: the next camera frame newer than `after`, waiting up
    /// to `wait` for one.
    pub fn next_frame(after: u64, wait: Duration) -> Option<Frame> {
        let (m, cv) = state();
        let deadline = Instant::now() + wait;
        let mut s = m.lock().unwrap();
        loop {
            if let Some(f) = &s.inbound
                && f.seq > after
            {
                return Some(f.clone());
            }
            let now = Instant::now();
            if now >= deadline || !s.active {
                return None;
            }
            s = cv.wait_timeout(s, deadline - now).unwrap().0;
        }
    }

    /// The app side: a processed frame (NV12).
    pub fn put_processed(f: Frame) {
        let (m, _) = state();
        let mut s = m.lock().unwrap();
        if s.active && f.data.len() >= (f.width * f.height * 3 / 2) as usize {
            s.outbound = Some((f, Instant::now()));
        }
    }

    pub fn i420_to_nv12(i420: &[u8], w: usize, h: usize) -> Vec<u8> {
        let (ys, cs) = (w * h, (w / 2) * (h / 2));
        let mut out = Vec::with_capacity(ys + 2 * cs);
        out.extend_from_slice(&i420[..ys]);
        let (u, v) = (&i420[ys..ys + cs], &i420[ys + cs..ys + 2 * cs]);
        for i in 0..cs {
            out.push(u[i]);
            out.push(v[i]);
        }
        out
    }

    pub fn nv12_to_i420(nv12: &[u8], w: usize, h: usize, out: &mut [u8]) {
        let (ys, cs) = (w * h, (w / 2) * (h / 2));
        out[..ys].copy_from_slice(&nv12[..ys]);
        for i in 0..cs {
            out[ys + i] = nv12[ys + 2 * i];
            out[ys + cs + i] = nv12[ys + 2 * i + 1];
        }
    }
}

/// The mask at a frame point (bilinear), eased so edges are soft but firm.
fn alpha_at(mask: &[f32], w: usize, h: usize, x: usize, y: usize) -> f32 {
    let fx = (x as f32 + 0.5) * MASK as f32 / w as f32 - 0.5;
    let fy = (y as f32 + 0.5) * MASK as f32 / h as f32 - 0.5;
    let x0 = fx.floor().clamp(0.0, (MASK - 1) as f32) as usize;
    let y0 = fy.floor().clamp(0.0, (MASK - 1) as f32) as usize;
    let (x1, y1) = ((x0 + 1).min(MASK - 1), (y0 + 1).min(MASK - 1));
    let (tx, ty) = (
        (fx - x0 as f32).clamp(0.0, 1.0),
        (fy - y0 as f32).clamp(0.0, 1.0),
    );
    let a = mask[y0 * MASK + x0] * (1.0 - tx) + mask[y0 * MASK + x1] * tx;
    let b = mask[y1 * MASK + x0] * (1.0 - tx) + mask[y1 * MASK + x1] * tx;
    let p = a * (1.0 - ty) + b * ty;
    // Smoothstep from 0.3 to 0.7.
    let t = ((p - 0.3) / 0.4).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// You over `back` (both I420, the same size), by the mask.
pub fn composite(data: &mut [u8], back: &[u8], mask: &[f32], w: usize, h: usize) {
    for y in 0..h {
        for x in 0..w {
            let a = alpha_at(mask, w, h, x, y);
            let i = y * w + x;
            data[i] = (data[i] as f32 * a + back[i] as f32 * (1.0 - a)) as u8;
        }
    }
    let (cw, ch) = (w / 2, h / 2);
    for y in 0..ch {
        for x in 0..cw {
            let a = alpha_at(mask, w, h, x * 2 + 1, y * 2 + 1);
            for plane in [w * h, w * h + cw * ch] {
                let i = plane + y * cw + x;
                data[i] = (data[i] as f32 * a + back[i] as f32 * (1.0 - a)) as u8;
            }
        }
    }
}

/// A blur of the whole frame: each plane shrunk by `f` (8 for Standard
/// blur, 4 for Portrait blur's lighter one), box-blurred twice, and
/// stretched back.
pub fn blur_i420(data: &[u8], w: usize, h: usize, f: usize, out: &mut Vec<u8>) {
    out.resize(w * h * 3 / 2, 0);
    let planes = [
        (0, w, h),
        (w * h, w / 2, h / 2),
        (w * h + w * h / 4, w / 2, h / 2),
    ];
    for (off, pw, ph) in planes {
        let f = f.max(1);
        let (sw, sh) = (pw.div_ceil(f).max(1), ph.div_ceil(f).max(1));
        let mut small = vec![0f32; sw * sh];
        for sy in 0..sh {
            for sx in 0..sw {
                let (mut sum, mut n) = (0f32, 0f32);
                for y in sy * f..((sy + 1) * f).min(ph) {
                    for x in sx * f..((sx + 1) * f).min(pw) {
                        sum += data[off + y * pw + x] as f32;
                        n += 1.0;
                    }
                }
                small[sy * sw + sx] = if n > 0.0 { sum / n } else { 0.0 };
            }
        }
        for _ in 0..2 {
            let src = small.clone();
            for sy in 0..sh {
                for sx in 0..sw {
                    let (mut sum, mut n) = (0f32, 0f32);
                    for dy in -2i32..=2 {
                        for dx in -2i32..=2 {
                            let (x, y) = (sx as i32 + dx, sy as i32 + dy);
                            if x >= 0 && y >= 0 && (x as usize) < sw && (y as usize) < sh {
                                sum += src[y as usize * sw + x as usize];
                                n += 1.0;
                            }
                        }
                    }
                    small[sy * sw + sx] = sum / n;
                }
            }
        }
        for y in 0..ph {
            for x in 0..pw {
                let fx = ((x as f32 + 0.5) / f as f32 - 0.5).max(0.0);
                let fy = ((y as f32 + 0.5) / f as f32 - 0.5).max(0.0);
                let (x0, y0) = ((fx as usize).min(sw - 1), (fy as usize).min(sh - 1));
                let (x1, y1) = ((x0 + 1).min(sw - 1), (y0 + 1).min(sh - 1));
                let (tx, ty) = (fx - x0 as f32, fy - y0 as f32);
                let a = small[y0 * sw + x0] * (1.0 - tx) + small[y0 * sw + x1] * tx;
                let b = small[y1 * sw + x0] * (1.0 - tx) + small[y1 * sw + x1] * tx;
                out[off + y * pw + x] = (a * (1.0 - ty) + b * ty) as u8;
            }
        }
    }
}

/// The picture scaled to cover w x h (centred, cropped), as I420.
pub fn fit_cover(p: &Picture, w: usize, h: usize) -> Vec<u8> {
    let (pw, ph) = (p.width as usize, p.height as usize);
    let scale = (w as f32 / pw as f32).max(h as f32 / ph as f32);
    let (ox, oy) = (
        (pw as f32 * scale - w as f32) / 2.0,
        (ph as f32 * scale - h as f32) / 2.0,
    );
    let mut out = vec![0u8; w * h * 3 / 2];
    let sample = |plane_off: usize, plane_w: usize, plane_h: usize, x: f32, y: f32| -> u8 {
        let (xi, yi) = ((x as usize).min(plane_w - 1), (y as usize).min(plane_h - 1));
        p.data[plane_off + yi * plane_w + xi]
    };
    for y in 0..h {
        for x in 0..w {
            out[y * w + x] = sample(0, pw, ph, (x as f32 + ox) / scale, (y as f32 + oy) / scale);
        }
    }
    let (cw, ch, pcw, pch) = (w / 2, h / 2, pw / 2, ph / 2);
    for y in 0..ch {
        for x in 0..cw {
            let (sx, sy) = (
                (x as f32 * 2.0 + ox) / scale / 2.0,
                (y as f32 * 2.0 + oy) / scale / 2.0,
            );
            out[w * h + y * cw + x] = sample(pw * ph, pcw, pch, sx, sy);
            out[w * h + cw * ch + y * cw + x] = sample(pw * ph + pcw * pch, pcw, pch, sx, sy);
        }
    }
    out
}

/// Soft focus: on you (by the mask), small differences in brightness are
/// evened out (skin smoothed) while edges, eyes and hair stay sharp.
pub fn soften(yplane: &mut [u8], mask: &[f32], w: usize, h: usize, scratch: &mut Vec<u8>) {
    // A 5 x 5 box mean from an integral image.
    let mut sum = vec![0u32; (w + 1) * (h + 1)];
    for y in 0..h {
        let mut row = 0u32;
        for x in 0..w {
            row += yplane[y * w + x] as u32;
            sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + row;
        }
    }
    scratch.resize(w * h, 0);
    scratch.copy_from_slice(&yplane[..w * h]);
    let r = 2usize;
    for y in 0..h {
        let (y0, y1) = (y.saturating_sub(r), (y + r + 1).min(h));
        for x in 0..w {
            let a = alpha_at(mask, w, h, x, y);
            if a <= 0.0 {
                continue;
            }
            let (x0, x1) = (x.saturating_sub(r), (x + r + 1).min(w));
            let total = sum[y1 * (w + 1) + x1] + sum[y0 * (w + 1) + x0]
                - sum[y0 * (w + 1) + x1]
                - sum[y1 * (w + 1) + x0];
            let mean = total as f32 / ((y1 - y0) * (x1 - x0)) as f32;
            let v = scratch[y * w + x] as f32;
            // Only small differences are smoothed (an edge is kept).
            let d = (v - mean).abs();
            let k = (1.0 - d / 18.0).clamp(0.0, 1.0) * 0.8 * a;
            yplane[y * w + x] = (v + (mean - v) * k).round() as u8;
        }
    }
}

/// Denoising: a motion-adaptive temporal filter. Where a point changes a
/// little from one frame to the next (sensor grain), the new value is
/// blended into what was shown there; where it changes a lot (you moved),
/// it is taken as it is, so motion never smears. What counts as "a
/// little" follows the camera's own grain, measured on each frame (the
/// median frame-to-frame change), so a clean camera is left alone and a
/// grainy one in low light is calmed (by about half, on a still picture).
#[derive(Default)]
pub struct Denoiser {
    /// The last frame shown (I420), and its size.
    prev: Vec<u8>,
    size: (usize, usize),
    /// The noise threshold in use (luma, eased between frames).
    threshold: f32,
}

/// The threshold's bounds (luma steps), and its share for chroma.
const DENOISE_MIN: f32 = 6.0;
const DENOISE_MAX: f32 = 40.0;
const DENOISE_CHROMA: f32 = 0.7;
/// How much of a still point's new value is taken (of 256): the rest is
/// the frames before it.
const DENOISE_KEEP: u32 = 40;
/// Up to this share of the threshold a change is all grain; above it the
/// new value is taken more and more, all of it at the threshold.
const DENOISE_KNEE: f32 = 0.6;

impl Denoiser {
    pub fn reset(&mut self) {
        self.prev.clear();
        self.size = (0, 0);
        self.threshold = 0.0;
    }

    pub fn apply(&mut self, w: usize, h: usize, data: &mut [u8]) {
        let len = w * h + 2 * (w.div_ceil(2) * h.div_ceil(2));
        if w == 0 || h == 0 || data.len() < len {
            return;
        }
        if self.size != (w, h) || self.prev.len() != len {
            self.prev.clear();
            self.prev.extend_from_slice(&data[..len]);
            self.size = (w, h);
            self.threshold = 0.0;
            return;
        }
        // The grain: the median change of a sample of points. Grain of
        // standard deviation s changes a point by about 0.7 s (median);
        // four times that covers nearly all of it.
        let mut hist = [0u32; 256];
        let mut n = 0u32;
        for (c, p) in data[..w * h].iter().zip(&self.prev[..w * h]).step_by(7) {
            hist[(*c as i32 - *p as i32).unsigned_abs() as usize] += 1;
            n += 1;
        }
        let mut seen = 0u32;
        let median = hist
            .iter()
            .position(|&k| {
                seen += k;
                seen * 2 >= n
            })
            .unwrap_or(0) as f32;
        let want = (median * 4.0 + 1.0).clamp(DENOISE_MIN, DENOISE_MAX);
        self.threshold = if self.threshold == 0.0 {
            want
        } else {
            self.threshold * 0.8 + want * 0.2
        };
        let luma = weights(self.threshold);
        let chroma = weights((self.threshold * DENOISE_CHROMA).max(DENOISE_MIN * 0.7));
        let (y, uv) = data[..len].split_at_mut(w * h);
        let (py, puv) = self.prev.split_at_mut(w * h);
        blend(y, py, &luma);
        blend(uv, puv, &chroma);
    }
}

/// The share of the new value taken (of 256) for each size of change.
fn weights(threshold: f32) -> [u32; 256] {
    let t = threshold.max(1.0);
    let mut out = [256u32; 256];
    for (d, w) in out.iter_mut().enumerate() {
        let x = d as f32 / t;
        if x < DENOISE_KNEE {
            *w = DENOISE_KEEP;
        } else if x < 1.0 {
            let ramp = (x - DENOISE_KNEE) / (1.0 - DENOISE_KNEE);
            *w = DENOISE_KEEP + ((256 - DENOISE_KEEP) as f32 * ramp) as u32;
        }
    }
    out
}

fn blend(cur: &mut [u8], prev: &mut [u8], weight: &[u32; 256]) {
    for (c, p) in cur.iter_mut().zip(prev.iter_mut()) {
        let (a, b) = (*p as i32, *c as i32);
        let k = weight[(b - a).unsigned_abs() as usize] as i32;
        let v = (a + (((b - a) * k + 128) >> 8)) as u8;
        *c = v;
        *p = v;
    }
}

/// Adjust brightness: a dim picture is lifted (gamma), a well-lit one left
/// as it is.
pub fn brighten(yplane: &mut [u8]) {
    if yplane.is_empty() {
        return;
    }
    let mean = yplane.iter().step_by(7).map(|&v| v as u32).sum::<u32>() as f32
        / yplane.iter().step_by(7).count() as f32;
    if mean >= 110.0 {
        return;
    }
    // Bring the mean towards 120: y' = 255 (y / 255)^g.
    let g = ((120.0f32 / 255.0).ln() / (mean.max(8.0) / 255.0).ln()).clamp(0.45, 1.0);
    let lut: Vec<u8> = (0..256)
        .map(|v| (255.0 * (v as f32 / 255.0).powf(g)).round() as u8)
        .collect();
    for v in yplane.iter_mut() {
        *v = lut[*v as usize];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dim_picture_is_brightened_and_a_bright_one_kept() {
        let mut dim = vec![40u8; 64];
        brighten(&mut dim);
        assert!(dim[0] > 80, "{}", dim[0]);
        let mut bright = vec![150u8; 64];
        brighten(&mut bright);
        assert_eq!(bright[0], 150);
    }

    #[test]
    fn the_background_shows_where_no_one_is() {
        let (w, h) = (8usize, 8usize);
        let mut frame = vec![200u8; w * h * 3 / 2];
        let back = vec![50u8; w * h * 3 / 2];
        composite(&mut frame, &back, &vec![0.0; MASK * MASK], w, h);
        assert!(frame.iter().all(|&v| v == 50));
        let mut frame = vec![200u8; w * h * 3 / 2];
        composite(&mut frame, &back, &vec![1.0; MASK * MASK], w, h);
        assert!(frame.iter().all(|&v| v == 200));
    }

    #[test]
    fn denoising_calms_grain_but_keeps_motion() {
        let (w, h) = (64usize, 36usize);
        let len = w * h * 3 / 2;
        // A still grey picture with grain (amplitude `a`) that changes
        // every frame.
        let mut seed = 1u32;
        let mut grain = |a: i32| -> Vec<u8> {
            (0..len)
                .map(|_| {
                    seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12_345);
                    (128 + ((seed >> 16) % (2 * a as u32 + 1)) as i32 - a) as u8
                })
                .collect()
        };
        let change = |a: &[u8], b: &[u8]| {
            a[..w * h]
                .iter()
                .zip(&b[..w * h])
                .map(|(x, y)| (*x as i32 - *y as i32).abs())
                .sum::<i32>() as f32
                / (w * h) as f32
        };
        for a in [6, 20] {
            let mut d = Denoiser::default();
            let mut out = Vec::new();
            let mut raw = Vec::new();
            for _ in 0..30 {
                let f = grain(a);
                let mut g = f.clone();
                d.apply(w, h, &mut g);
                raw.push(f);
                out.push(g);
            }
            let before = change(&raw[28], &raw[29]);
            let after = change(&out[28], &out[29]);
            assert!(after < before * 0.6, "grain {a}: {after} vs {before}");
            // You move: a big change comes through at once.
            let mut moved = vec![250u8; len];
            d.apply(w, h, &mut moved);
            assert!(moved.iter().all(|&v| v == 250), "grain {a}");
        }
        // A new size starts over, untouched; a clean camera stays as it is.
        let mut d = Denoiser::default();
        let mut first = grain(4);
        let copy = first.clone();
        d.apply(w, h, &mut first);
        assert_eq!(first, copy);
        let still = vec![90u8; len];
        let mut f = still.clone();
        d.apply(w, h, &mut f);
        let mut f = still.clone();
        d.apply(w, h, &mut f);
        assert!(f.iter().all(|&v| (v as i32 - 90).abs() <= 2));
    }

    #[test]
    fn soft_focus_evens_out_skin_but_keeps_edges() {
        let (w, h) = (16usize, 16usize);
        // Gentle noise on the left, a hard edge in the middle.
        let mut y: Vec<u8> = (0..w * h)
            .map(|i| {
                if i % w < 8 {
                    120 + (i % 3) as u8 * 6
                } else {
                    240
                }
            })
            .collect();
        let before = y.clone();
        soften(&mut y, &vec![1.0; MASK * MASK], w, h, &mut Vec::new());
        let spread = |v: &[u8]| {
            (0..h)
                .flat_map(|r| v[r * w + 2..r * w + 5].to_vec())
                .fold((255u8, 0u8), |(lo, hi), p| (lo.min(p), hi.max(p)))
        };
        let (lo0, hi0) = spread(&before);
        let (lo1, hi1) = spread(&y);
        assert!(hi1 - lo1 < hi0 - lo0, "{lo1}..{hi1} vs {lo0}..{hi0}");
        assert_eq!(y[5 * w + 12], 240);
        assert!(y[5 * w + 7] < 140, "{}", y[5 * w + 7]);
    }

    #[test]
    fn nv12_round_trips_and_the_filter_result_replaces_the_frame() {
        let (w, h) = (4usize, 2usize);
        let i420: Vec<u8> = (0..(w * h * 3 / 2) as u8).collect();
        let nv12 = filter::i420_to_nv12(&i420, w, h);
        assert_eq!(&nv12[8..], &[8, 10, 9, 11]);
        let mut back = vec![0u8; i420.len()];
        filter::nv12_to_i420(&nv12, w, h, &mut back);
        assert_eq!(back, i420);

        filter::set_active(true);
        let mut frame = i420.clone();
        filter::apply(w as u32, h as u32, &mut frame);
        assert_eq!(frame, i420, "no result yet: the frame is unchanged");
        let f = filter::next_frame(0, std::time::Duration::from_millis(10))
            .expect("a frame for the app");
        filter::put_processed(filter::Frame {
            data: vec![200; f.data.len()],
            ..f
        });
        filter::apply(w as u32, h as u32, &mut frame);
        assert!(frame.iter().all(|&v| v == 200));
        filter::set_active(false);
        assert!(filter::next_frame(0, std::time::Duration::from_millis(5)).is_none());
    }

    #[test]
    fn green_screen_keys_out_the_backdrop_colour() {
        let (w, h) = (8usize, 8usize);
        let green = rgb_to_yuv([0, 200, 0]);
        let red = rgb_to_yuv([200, 0, 0]);
        // Left half green backdrop, right half a red thing held up.
        let mut frame = vec![0u8; w * h * 3 / 2];
        for y in 0..h {
            for x in 0..w {
                frame[y * w + x] = if x < 4 { green[0] } else { red[0] } as u8;
            }
        }
        for y in 0..h / 2 {
            for x in 0..w / 2 {
                let c = if x < 2 { green } else { red };
                frame[w * h + y * 4 + x] = c[1] as u8;
                frame[w * h + 16 + y * 4 + x] = c[2] as u8;
            }
        }
        let back = vec![128u8; w * h * 3 / 2];
        let before = frame.clone();
        composite_keyed(&mut frame, &back, w, h, [green[1], green[2]]);
        assert_eq!(frame[0], 128, "the backdrop is replaced");
        assert_eq!(frame[7], before[7], "the red thing stays");
        let c = yuv_to_rgb(green[0], green[1], green[2]);
        assert!(c[1] > 180 && c[0] < 30, "{c:?}");
    }

    #[test]
    fn portrait_blur_is_lighter_than_standard() {
        let (w, h) = (64usize, 64usize);
        let data: Vec<u8> = (0..w * h * 3 / 2)
            .map(|i| if (i / 4) % 2 == 0 { 0 } else { 255 })
            .collect();
        let (mut a, mut b) = (Vec::new(), Vec::new());
        blur_i420(&data, w, h, 8, &mut a);
        blur_i420(&data, w, h, 4, &mut b);
        let dev = |v: &[u8]| {
            v[..w * h]
                .iter()
                .map(|&p| (p as i32 - 128).abs())
                .sum::<i32>()
        };
        assert!(dev(&b) >= dev(&a));
    }

    #[test]
    fn the_implicit_mask_is_teams_luma_squeeze() {
        // Teams' constants: lumaMin 59, threshold 23.
        assert_eq!(implicit::encode(16), 59);
        assert_eq!(implicit::encode(240), 255);
        assert_eq!(implicit::encode(0), 59, "below the video range is clamped");
        for y in [16u8, 60, 128, 200, 240] {
            assert!(
                (implicit::decode(implicit::encode(y)) as i32 - y as i32).abs() <= 1,
                "{y}"
            );
        }
        // A frame: the left half is the person, the right half background.
        let (w, h) = (16usize, 8usize);
        let mut frame = vec![100u8; w * h * 3 / 2];
        let mask: Vec<f32> = (0..MASK * MASK)
            .map(|i| if i % MASK < MASK / 2 { 1.0 } else { 0.0 })
            .collect();
        apply_implicit_mask(&mut frame, &mask, w, h);
        assert_eq!(frame[0], implicit::encode(100));
        assert_eq!(frame[w - 1], 0);
        assert_eq!(
            frame[w * h + w / 2 - 1],
            128,
            "the background's colour is neutral"
        );
        // Received: the person is opaque with its luma back, the rest clear
        // (and a pixel next to the background is eroded away).
        let (yp, uv) = frame.split_at(w * h);
        let (up, vp) = uv.split_at(w * h / 4);
        let mut rgba = vec![0u8; w * h * 4];
        implicit_mask_rgba(yp, up, vp, (w, w / 2, w / 2), w, h, &mut rgba);
        assert_eq!(rgba[3], 255);
        assert_eq!(rgba[(w - 1) * 4 + 3], 0);
        assert_eq!(rgba[(w / 2 - 1) * 4 + 3], 0, "eroded at the edge");
        let back = yuv_to_rgb(100.0, 100.0, 100.0);
        assert!((rgba[0] as i32 - back[0] as i32).abs() <= 2);
    }

    #[test]
    fn a_picture_covers_the_frame() {
        let rgba = vec![255u8; 4 * 4 * 4];
        let p = Picture::from_rgba(4, 4, &rgba);
        let out = fit_cover(&p, 8, 6);
        assert_eq!(out.len(), 8 * 6 * 3 / 2);
        assert!(out[..48].iter().all(|&v| v > 200));
    }
}
