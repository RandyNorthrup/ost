//! `CameraFeed`: a camera from OST's own camera list (PipeWire, the
//! camera portal in the Flatpak, filtered V4L2 nodes: calling::camera)
//! for the video clip recorder and face capture, captured as calls
//! capture it, instead of Qt Multimedia's camera list and capture. The
//! camera is open only between `open` and `close` (or the item going):
//! Teams opens a camera only while it shows its picture.
//!
//! The picture is published as the frame `source` (for a `VideoFrame`),
//! can be handed to a QML video sink (`show_in`, for a `VideoOutput` the
//! recorder's effects draw from) and saved as a photo (`save_frame`).

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        /// The frame its picture is published as (for a `VideoFrame`).
        #[qproperty(QString, source)]
        /// The camera is open.
        #[qproperty(bool, running)]
        /// The camera opened (its ID in OST's camera list), empty when
        /// none is.
        #[qproperty(QString, camera)]
        type CameraFeed = super::CameraFeedRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        /// Open camera `id` ("" for the one chosen in Settings > Devices)
        /// at about `width` x `height` and `fps`, closing the one open
        /// first. Whether it opened.
        #[qinvokable]
        fn open(
            self: Pin<&mut CameraFeed>,
            id: &QString,
            width: i32,
            height: i32,
            fps: i32,
        ) -> bool;
        /// Close the camera (returns once it is closed).
        #[qinvokable]
        fn close(self: Pin<&mut CameraFeed>);
        /// Hand the newest picture to `sink` (a VideoOutput's videoSink),
        /// if there is a new one; none (the camera closed) clears it.
        #[qinvokable]
        unsafe fn show_in(self: Pin<&mut CameraFeed>, sink: *mut QObject);
        /// Save the newest picture to `path` as a JPEG. Whether it did.
        #[qinvokable]
        fn save_frame(self: &CameraFeed, path: &QString) -> bool;
    }

    impl cxx_qt::Constructor<()> for CameraFeed {}
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use std::sync::atomic::{AtomicU64, Ordering};
use teams_cli::calling::{camera, frames, webrtc_video::CameraPreview};

pub struct CameraFeedRust {
    source: QString,
    running: bool,
    camera: QString,
    /// The open camera (dropping it closes the camera).
    capture: Option<CameraPreview>,
    /// The frame last handed to a sink (0: none).
    shown: u64,
}

impl cxx_qt::Constructor<()> for qobject::CameraFeed {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> CameraFeedRust {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        CameraFeedRust {
            source: QString::from(format!("camera-feed-{n}").as_str()),
            running: false,
            camera: QString::default(),
            capture: None,
            shown: 0,
        }
    }
}

unsafe extern "C" {
    fn ost_camera_feed_show(
        sink: *mut core::ffi::c_void,
        rgba: *const u8,
        width: i32,
        height: i32,
    ) -> bool;
    fn ost_camera_feed_save(
        rgba: *const u8,
        width: i32,
        height: i32,
        path: *const core::ffi::c_char,
    ) -> bool;
}

impl qobject::CameraFeed {
    pub fn open(mut self: Pin<&mut Self>, id: &QString, width: i32, height: i32, fps: i32) -> bool {
        self.as_mut().close();
        let wanted = Some(id.to_string())
            .filter(|i| !i.is_empty())
            .or_else(crate::backend::selected_camera);
        // That camera and no other: while it isn't there, nothing opens
        // (it is asked for again). With none chosen, the first camera, as
        // calls do. (A chosen camera is opened without listing them all:
        // listing opens every V4L2 node.)
        let id = match wanted {
            Some(w) => w,
            None => match camera::cameras().into_iter().next() {
                Some(c) => c.id,
                None => {
                    tracing::info!("camera feed: no camera");
                    return false;
                }
            },
        };
        let key = self.rust().source.to_string();
        let size = |v: i32, d: u32| u32::try_from(v).ok().filter(|v| *v > 0).unwrap_or(d);
        match CameraPreview::start_plain(
            Some(&id),
            &key,
            size(width, 1280),
            size(height, 720),
            size(fps, 30),
        ) {
            Ok(capture) => {
                tracing::info!(camera = id, key, "camera feed opened");
                self.as_mut().rust_mut().capture = Some(capture);
                // As the list names it (a V4L2 path saved before PipeWire
                // offered that camera is the PipeWire one).
                let id = camera::find(&camera::cameras(), &id).map_or(id, |c| c.id.clone());
                self.as_mut().set_camera(QString::from(id.as_str()));
                self.as_mut().set_running(true);
                true
            }
            Err(e) => {
                tracing::info!(camera = id, "camera feed: {e:#}");
                false
            }
        }
    }

    pub fn close(mut self: Pin<&mut Self>) {
        // (Dropping it returns once the camera is closed.)
        if self.as_mut().rust_mut().capture.take().is_some() {
            frames::clear(&self.rust().source.to_string());
            tracing::info!(key = %self.rust().source, "camera feed closed");
        }
        self.as_mut().set_running(false);
        self.as_mut().set_camera(QString::default());
    }

    /// # Safety
    /// `sink` is null or a live QObject (QML passes a VideoOutput's sink).
    pub unsafe fn show_in(mut self: Pin<&mut Self>, sink: *mut cxx_qt::QObject) {
        if sink.is_null() {
            return;
        }
        let sink = sink.cast::<core::ffi::c_void>();
        match frames::latest(&self.rust().source.to_string()) {
            Some(f) if f.seq != self.rust().shown => {
                let (Ok(w), Ok(h)) = (i32::try_from(f.width), i32::try_from(f.height)) else {
                    return;
                };
                // SAFETY: `rgba` holds w * h RGBA pixels (frames::publish
                // checks); C++ copies them before returning.
                if unsafe { ost_camera_feed_show(sink, f.rgba.as_ptr(), w, h) } {
                    self.as_mut().rust_mut().shown = f.seq;
                }
            }
            Some(_) => {}
            None if self.rust().shown != 0 => {
                // SAFETY: a null picture clears the sink.
                unsafe { ost_camera_feed_show(sink, core::ptr::null(), 0, 0) };
                self.as_mut().rust_mut().shown = 0;
            }
            None => {}
        }
    }

    pub fn save_frame(&self, path: &QString) -> bool {
        let Some(f) = frames::latest(&self.source.to_string()) else {
            return false;
        };
        let (Ok(w), Ok(h)) = (i32::try_from(f.width), i32::try_from(f.height)) else {
            return false;
        };
        let path = path.to_string();
        let Ok(path) = std::ffi::CString::new(path.trim_start_matches("file://")) else {
            return false;
        };
        // SAFETY: as in show_in; `path` is a C string for the call.
        unsafe { ost_camera_feed_save(f.rgba.as_ptr(), w, h, path.as_ptr()) }
    }
}
