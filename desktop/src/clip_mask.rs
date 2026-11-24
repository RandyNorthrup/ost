//! `ClipMask`: the person mask of the clip recorder's camera, for its
//! Backdrop (an image or video behind you, or Blur), as Stream's recorder
//! segments the camera. The camera's frames come from its QML video sink
//! (src/clipmask.cpp shrinks one to the model's 192 x 192 whenever the
//! model is free); ost-vfx's person segmentation runs on a worker thread,
//! and the item paints the newest mask (white: you) stretched over itself,
//! for the recorder's camera shader (shaders/clip_camera.frag) to cut
//! you out with.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtQuick/QQuickPaintedItem>);
        type QQuickPaintedItem;
        include!("cxx-qt-lib/qpainter.h");
        type QPainter = cxx_qt_lib::QPainter;
        include!("cxx-qt-lib/qrect.h");
        type QRect = cxx_qt_lib::QRect;
        include!(<QtCore/QObject>);
        type QObject;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QQuickPaintedItem]
        /// Segment while on (off: the worker idles and frames are ignored).
        #[qproperty(bool, active)]
        /// A mask has come in since it was turned on.
        #[qproperty(bool, has_mask)]
        type ClipMask = super::ClipMaskRust;
    }

    unsafe extern "RustQt" {
        #[cxx_override]
        unsafe fn paint(self: Pin<&mut ClipMask>, painter: *mut QPainter);

        /// Take the camera's frames from `sink` (a VideoOutput's videoSink).
        #[qinvokable]
        unsafe fn attach(self: Pin<&mut ClipMask>, sink: *mut QObject);
        /// Show the newest mask, if a new one is in (QML calls it on a timer).
        #[qinvokable]
        fn refresh(self: Pin<&mut ClipMask>);
    }

    impl cxx_qt::Constructor<()> for ClipMask {}

    unsafe extern "RustQt" {
        #[inherit]
        fn update(self: Pin<&mut ClipMask>, rect: &QRect);
        #[inherit]
        fn width(self: &ClipMask) -> f64;
        #[inherit]
        fn height(self: &ClipMask) -> f64;
    }
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QImage, QImageFormat, QPainterRenderHint, QRect};
use ost_vfx::MASK;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc};

pub struct ClipMaskRust {
    active: bool,
    has_mask: bool,
    worker: Option<mpsc::SyncSender<Vec<u8>>>,
    /// The worker's newest mask.
    newest: Arc<Mutex<Option<Vec<f32>>>>,
    /// The worker is segmenting a frame.
    busy: Arc<AtomicBool>,
    /// The mask shown, eased towards each new one (as ost-vfx does).
    mask: Vec<f32>,
}

impl Default for ClipMaskRust {
    fn default() -> Self {
        Self { active: false, has_mask: false, worker: None, newest: Arc::new(Mutex::new(None)), busy: Arc::new(AtomicBool::new(false)), mask: vec![0.0; MASK * MASK] }
    }
}

impl cxx_qt::Constructor<()> for qobject::ClipMask {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> ClipMaskRust {
        ClipMaskRust::default()
    }
}

unsafe extern "C" {
    fn ost_clip_mask_attach(item: *mut core::ffi::c_void, sink: *mut core::ffi::c_void);
}

/// Shared with the camera thread's callback: hand a frame to the worker.
fn submit(r: &mut ClipMaskRust, rgb: Vec<u8>) {
    if r.worker.is_none() {
        let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(1);
        let (newest, busy) = (r.newest.clone(), r.busy.clone());
        let spawned = std::thread::Builder::new().name("ost-clip-segment".into()).spawn(move || {
            let seg = match ost_vfx::Segmenter::new() {
                Ok(s) => s,
                Err(e) => {
                    tracing::warn!("clip backdrop: the segmentation model didn't load: {e}");
                    return;
                }
            };
            while let Ok(rgb) = rx.recv() {
                if let Ok(mask) = seg.segment(&rgb) {
                    *newest.lock().unwrap() = Some(mask);
                }
                busy.store(false, Ordering::SeqCst);
            }
        });
        if spawned.is_ok() {
            r.worker = Some(tx);
        }
    }
    if let Some(tx) = &r.worker {
        r.busy.store(true, Ordering::SeqCst);
        if tx.try_send(rgb).is_err() {
            r.busy.store(false, Ordering::SeqCst);
        }
    }
}

impl qobject::ClipMask {
    /// SAFETY: `sink` is the QVideoSink QML passes (or null).
    pub unsafe fn attach(self: Pin<&mut Self>, sink: *mut qobject::QObject) {
        // SAFETY: only the pointer is taken; C++ treats it as the item.
        let item = unsafe { self.get_unchecked_mut() as *mut qobject::ClipMask as *mut core::ffi::c_void };
        unsafe { ost_clip_mask_attach(item, sink as *mut core::ffi::c_void) }
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        if !self.rust().active {
            if self.rust().has_mask {
                self.as_mut().rust_mut().mask.iter_mut().for_each(|m| *m = 0.0);
                self.as_mut().set_has_mask(false);
            }
            return;
        }
        let Some(m) = self.rust().newest.lock().unwrap().take() else { return };
        let first = !self.rust().has_mask;
        {
            let mut r = self.as_mut().rust_mut();
            if first {
                r.mask = m;
            } else {
                for (a, b) in r.mask.iter_mut().zip(m.iter()) {
                    *a = *a * 0.4 + *b * 0.6;
                }
            }
        }
        if first {
            self.as_mut().set_has_mask(true);
        }
        let (w, h) = (self.width() as i32, self.height() as i32);
        self.as_mut().update(&QRect::new(0, 0, w.max(1), h.max(1)));
    }

    /// Called by Qt with a valid painter for the duration of the call.
    pub unsafe fn paint(self: Pin<&mut Self>, painter: *mut cxx_qt_lib::QPainter) {
        let Some(painter) = (unsafe { painter.as_mut() }) else { return };
        let mut painter = unsafe { Pin::new_unchecked(painter) };
        let mut rgba = vec![0u8; MASK * MASK * 4];
        for (i, m) in self.rust().mask.iter().enumerate() {
            let v = (m.clamp(0.0, 1.0) * 255.0) as u8;
            rgba[i * 4..i * 4 + 4].copy_from_slice(&[v, v, v, 255]);
        }
        // QImage takes its own copy of the pixels (it frees them itself).
        let image = unsafe { QImage::from_raw_bytes(rgba, MASK as i32, MASK as i32, QImageFormat::Format_RGBA8888) };
        painter.as_mut().set_render_hint(QPainterRenderHint::SmoothPixmapTransform, true);
        let target = QRect::new(0, 0, self.width().ceil() as i32, self.height().ceil() as i32);
        painter.as_mut().draw_image(&target, &image);
    }
}

/// SAFETY (both): called by src/clipmask.cpp on the GUI thread, with the
/// item passed to ost_clip_mask_attach; the connection dies with the item.
unsafe fn item<'a>(p: *mut core::ffi::c_void) -> Pin<&'a mut qobject::ClipMask> {
    unsafe { Pin::new_unchecked(&mut *(p as *mut qobject::ClipMask)) }
}

/// Whether a frame is wanted now (on, and the model free).
#[unsafe(no_mangle)]
extern "C" fn ost_clip_mask_wants(p: *mut core::ffi::c_void) -> bool {
    if p.is_null() {
        return false;
    }
    let it = unsafe { item(p) };
    it.rust().active && !it.rust().busy.load(Ordering::SeqCst)
}

/// A frame shrunk to MASK x MASK RGB.
#[unsafe(no_mangle)]
extern "C" fn ost_clip_mask_frame(p: *mut core::ffi::c_void, rgb: *const u8, side: i32) {
    if p.is_null() || rgb.is_null() || side as usize != MASK {
        return;
    }
    let data = unsafe { std::slice::from_raw_parts(rgb, MASK * MASK * 3) }.to_vec();
    let mut it = unsafe { item(p) };
    submit(&mut it.as_mut().rust_mut(), data);
}
