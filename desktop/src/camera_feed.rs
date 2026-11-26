//! `CameraFeed`: a camera from OST's own camera list (PipeWire, the
//! camera portal in the Flatpak, filtered V4L2 nodes: calling::camera)
//! for the video clip recorder and face capture, captured as calls
//! capture it, instead of Qt Multimedia's camera list and capture. The
//! camera is open only between `open` and `close` (or the item going):
//! Teams opens a camera only while it shows its picture. It opens on a
//! worker thread (`opening` meanwhile), and `running` goes false again if
//! the camera stops by itself (unplugged), so the dialogs can try again.
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
        /// The camera is being opened.
        #[qproperty(bool, opening)]
        /// The camera opened (its ID in OST's camera list), empty when
        /// none is.
        #[qproperty(QString, camera)]
        type CameraFeed = super::CameraFeedRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        /// Open camera `id` ("" for the one chosen in Settings > Devices)
        /// at about `width` x `height` and `fps`, closing the one open
        /// first. `running` follows once it is open; false when it
        /// couldn't start trying.
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
    impl cxx_qt::Threading for CameraFeed {}
}

use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use teams_cli::calling::{camera, frames, webrtc_video::CameraPreview};

pub struct CameraFeedRust {
    source: QString,
    running: bool,
    opening: bool,
    camera: QString,
    /// The open camera (dropping it closes the camera).
    capture: Option<CameraPreview>,
    /// Counts opens and closes: what a worker brings back for an older one
    /// is let go (its camera closed).
    generation: u64,
    /// Set to stop the open under way (closed meanwhile).
    cancel: Arc<AtomicBool>,
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
            opening: false,
            camera: QString::default(),
            capture: None,
            generation: 0,
            cancel: Arc::new(AtomicBool::new(false)),
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
        let generation = self.rust().generation;
        let cancel = Arc::new(AtomicBool::new(false));
        self.as_mut().rust_mut().cancel = cancel.clone();
        let wanted = Some(id.to_string())
            .filter(|i| !i.is_empty())
            .or_else(crate::backend::selected_camera);
        let key = self.rust().source.to_string();
        let size = |v: i32, d: u32| u32::try_from(v).ok().filter(|v| *v > 0).unwrap_or(d);
        let (width, height, fps) = (size(width, 1280), size(height, 720), size(fps, 30));
        let qt = self.qt_thread();
        // (Opening may take seconds: a PipeWire camera links and
        // negotiates first.)
        let spawned = std::thread::Builder::new()
            .name("ost-camera-feed".into())
            .spawn(move || {
                // That camera and no other: while it isn't there, nothing
                // opens (it is asked for again). With none chosen, the
                // first camera, as calls do.
                let id = wanted.or_else(|| camera::first_camera().map(|c| c.id));
                let opened = match id {
                    None => Err(anyhow::anyhow!("no camera")),
                    Some(id) => {
                        let back = qt.clone();
                        let ended = Box::new(move || {
                            let _ = back.queue(move |this| this.ended(generation));
                        });
                        let size = (width, height, fps);
                        CameraPreview::start_plain(Some(&id), &key, size, ended, &cancel)
                            .map(|capture| {
                                // As the list names it (a V4L2 path saved
                                // before PipeWire offered that camera is the
                                // PipeWire one).
                                let shown =
                                    camera::find(&camera::cameras_with(&[id.as_str()]), &id)
                                        .map_or_else(|| id.clone(), |c| c.id.clone());
                                (shown, capture)
                            })
                            .map_err(|e| e.context(id))
                    }
                };
                // (If the feed is gone, the camera closes here.)
                let _ = qt.queue(move |this| this.opened(generation, opened));
            });
        if let Err(e) = spawned {
            tracing::info!("camera feed: {e}");
            return false;
        }
        self.as_mut().set_opening(true);
        true
    }

    /// A worker's open for `generation` is done.
    fn opened(
        mut self: Pin<&mut Self>,
        generation: u64,
        opened: anyhow::Result<(String, CameraPreview)>,
    ) {
        if generation != self.rust().generation {
            // Closed (or opened again) meanwhile: let it go.
            return;
        }
        self.as_mut().set_opening(false);
        match opened {
            Ok((id, capture)) => {
                tracing::info!(camera = id, key = %self.rust().source, "camera feed opened");
                self.as_mut().rust_mut().capture = Some(capture);
                self.as_mut().set_camera(QString::from(id.as_str()));
                self.as_mut().set_running(true);
            }
            Err(e) => tracing::info!("camera feed: {e:#}"),
        }
    }

    /// The camera of `generation` stopped by itself. (Also before its open
    /// came back: closing moves the generation on, so that result is let
    /// go instead of reviving a dead camera.)
    fn ended(self: Pin<&mut Self>, generation: u64) {
        if generation == self.rust().generation {
            tracing::info!(key = %self.rust().source, "camera feed: the camera stopped");
            self.close();
        }
    }

    pub fn close(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().generation += 1;
        // An open under way stops (its camera closes there).
        self.rust().cancel.store(true, Ordering::Relaxed);
        // (Dropping it returns once the camera is closed.)
        if self.as_mut().rust_mut().capture.take().is_some() {
            frames::clear(&self.rust().source.to_string());
            tracing::info!(key = %self.rust().source, "camera feed closed");
        }
        self.as_mut().set_opening(false);
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
