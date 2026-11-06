//! `VideoFrame`: a QML item that draws the newest decoded frame of a
//! video stream ("remote" for the person you're calling), scaled to fill
//! the item and cropped, as Teams fills its video tiles. QML calls
//! `refresh()` on a timer; it repaints only when there is a new frame.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtQuick/QQuickPaintedItem>);
        type QQuickPaintedItem;
        include!("cxx-qt-lib/qpainter.h");
        type QPainter = cxx_qt_lib::QPainter;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qrect.h");
        type QRect = cxx_qt_lib::QRect;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QQuickPaintedItem]
        #[qproperty(QString, source)]
        #[qproperty(bool, has_frame)]
        #[qproperty(i32, frame_width)]
        #[qproperty(i32, frame_height)]
        type VideoFrame = super::VideoFrameRust;
    }

    unsafe extern "RustQt" {
        #[cxx_override]
        unsafe fn paint(self: Pin<&mut VideoFrame>, painter: *mut QPainter);

        /// Repaint if the stream has a new frame.
        #[qinvokable]
        fn refresh(self: Pin<&mut VideoFrame>);
    }

    // QQuickPaintedItem takes a QQuickItem parent, not the QObject one the
    // default constructor passes; construct without one (QML parents it).
    impl cxx_qt::Constructor<()> for VideoFrame {}

    unsafe extern "RustQt" {
        #[inherit]
        fn update(self: Pin<&mut VideoFrame>, rect: &QRect);
        #[inherit]
        fn width(self: &VideoFrame) -> f64;
        #[inherit]
        fn height(self: &VideoFrame) -> f64;
    }
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{ClipOperation, QImage, QImageFormat, QPainterRenderHint, QRect, QString};
use teams_cli::calling::frames;

#[derive(Default)]
pub struct VideoFrameRust {
    source: QString,
    has_frame: bool,
    frame_width: i32,
    frame_height: i32,
    /// The frame sequence last drawn.
    shown: u64,
}

impl cxx_qt::Constructor<()> for qobject::VideoFrame {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> VideoFrameRust {
        VideoFrameRust::default()
    }
}

impl qobject::VideoFrame {
    pub fn refresh(mut self: Pin<&mut Self>) {
        let key = self.rust().source.to_string();
        match frames::latest(&key) {
            Some(f) if f.seq != self.rust().shown => {
                self.as_mut().set_has_frame(true);
                self.as_mut().set_frame_width(f.width as i32);
                self.as_mut().set_frame_height(f.height as i32);
                self.as_mut().update(&QRect::default());
            }
            Some(_) => {}
            None if self.rust().has_frame => {
                self.as_mut().rust_mut().shown = 0;
                self.as_mut().set_has_frame(false);
                self.as_mut().update(&QRect::default());
            }
            None => {}
        }
    }

    /// # Safety
    /// Called by Qt with a valid painter for the duration of the call.
    pub unsafe fn paint(mut self: Pin<&mut Self>, painter: *mut cxx_qt_lib::QPainter) {
        let Some(painter) = (unsafe { painter.as_mut() }) else {
            return;
        };
        let mut painter = unsafe { Pin::new_unchecked(painter) };
        let key = self.rust().source.to_string();
        let Some(f) = frames::latest(&key) else {
            return;
        };
        self.as_mut().rust_mut().shown = f.seq;
        let (w, h) = (self.width(), self.height());
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        // Fill and crop: scale so the frame covers the item.
        let scale = (w / f.width as f64).max(h / f.height as f64);
        let (dw, dh) = (f.width as f64 * scale, f.height as f64 * scale);
        let target = QRect::new(
            ((w - dw) / 2.0).round() as i32,
            ((h - dh) / 2.0).round() as i32,
            dw.round() as i32,
            dh.round() as i32,
        );
        // QImage takes its own copy of the pixels (it frees them itself).
        let image = unsafe {
            QImage::from_raw_bytes(
                f.rgba.as_ref().clone(),
                f.width as i32,
                f.height as i32,
                QImageFormat::Format_RGBA8888,
            )
        };
        painter.as_mut().set_clip_rect(
            &QRect::new(0, 0, w as i32, h as i32),
            ClipOperation::ReplaceClip,
        );
        painter
            .as_mut()
            .set_render_hint(QPainterRenderHint::SmoothPixmapTransform, true);
        painter.as_mut().draw_image(&target, &image);
    }
}
