//! `ClipFrames`: records a video clip from what the recorder's picture
//! shows (src/clipframes.cpp), as Teams' recorder records its canvas. A
//! QML item placed inside the picture item it records.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtQuick/QQuickItem>);
        type QQuickItem;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QQuickItem]
        type ClipFrames = super::ClipFramesRust;
    }

    unsafe extern "RustQt" {
        /// Get ready to record the parent item at `width` x `height` with
        /// microphone `mic_id` ("" for the default), muted unless `mic_on`
        /// (the microphone opens now: Qt's encoder waits for audio).
        #[qinvokable]
        fn prepare(self: Pin<&mut ClipFrames>, mic_id: &QString, mic_on: bool, width: i32, height: i32) -> bool;
        /// Start recording to `path` (a local file), after prepare.
        #[qinvokable]
        fn start(self: Pin<&mut ClipFrames>, path: &QString) -> bool;
        #[qinvokable]
        fn pause(self: Pin<&mut ClipFrames>);
        #[qinvokable]
        fn resume(self: Pin<&mut ClipFrames>);
        /// Stop; `stopped` follows once the file is complete.
        #[qinvokable]
        fn stop(self: Pin<&mut ClipFrames>);
        /// Let the finished (or abandoned) recording go.
        #[qinvokable]
        fn release(self: Pin<&mut ClipFrames>);

        /// The time recorded so far (paused time excluded).
        #[qsignal]
        fn recorded(self: Pin<&mut ClipFrames>, ms: i64);
        /// The recording is complete in `path`.
        #[qsignal]
        fn stopped(self: Pin<&mut ClipFrames>, path: QString);
        #[qsignal]
        fn failed(self: Pin<&mut ClipFrames>, message: QString);
    }

    impl cxx_qt::Constructor<()> for ClipFrames {}
}

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::ffi::{CStr, CString};

#[derive(Default)]
pub struct ClipFramesRust;

impl cxx_qt::Constructor<()> for qobject::ClipFrames {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> ClipFramesRust {
        ClipFramesRust
    }
}

unsafe extern "C" {
    fn ost_clip_frames_prepare(
        helper: *mut core::ffi::c_void,
        mic_id: *const core::ffi::c_char,
        mic_on: bool,
        width: i32,
        height: i32,
    ) -> bool;
    fn ost_clip_frames_start(helper: *mut core::ffi::c_void, path: *const core::ffi::c_char) -> bool;
    fn ost_clip_frames_pause(helper: *mut core::ffi::c_void);
    fn ost_clip_frames_resume(helper: *mut core::ffi::c_void);
    fn ost_clip_frames_stop(helper: *mut core::ffi::c_void);
    fn ost_clip_frames_release(helper: *mut core::ffi::c_void);
}

fn helper(item: Pin<&mut qobject::ClipFrames>) -> *mut core::ffi::c_void {
    // SAFETY: only the pointer is taken; C++ treats it as the QQuickItem.
    unsafe { item.get_unchecked_mut() as *mut qobject::ClipFrames as *mut core::ffi::c_void }
}

fn c(s: &QString) -> CString {
    CString::new(s.to_string().replace('\0', "")).unwrap_or_default()
}

impl qobject::ClipFrames {
    pub fn prepare(self: Pin<&mut Self>, mic_id: &QString, mic_on: bool, width: i32, height: i32) -> bool {
        let m = c(mic_id);
        unsafe { ost_clip_frames_prepare(helper(self), m.as_ptr(), mic_on, width, height) }
    }
    pub fn start(self: Pin<&mut Self>, path: &QString) -> bool {
        let p = c(path);
        unsafe { ost_clip_frames_start(helper(self), p.as_ptr()) }
    }
    pub fn pause(self: Pin<&mut Self>) {
        unsafe { ost_clip_frames_pause(helper(self)) }
    }
    pub fn resume(self: Pin<&mut Self>) {
        unsafe { ost_clip_frames_resume(helper(self)) }
    }
    pub fn stop(self: Pin<&mut Self>) {
        unsafe { ost_clip_frames_stop(helper(self)) }
    }
    pub fn release(self: Pin<&mut Self>) {
        unsafe { ost_clip_frames_release(helper(self)) }
    }
}

/// SAFETY (all three): called by src/clipframes.cpp on the GUI thread with
/// the item passed to ost_clip_frames_start, which stays alive until it
/// calls release (QML does so when the recorder goes).
unsafe fn item<'a>(helper: *mut core::ffi::c_void) -> Pin<&'a mut qobject::ClipFrames> {
    unsafe { Pin::new_unchecked(&mut *(helper as *mut qobject::ClipFrames)) }
}

#[unsafe(no_mangle)]
extern "C" fn ost_clip_frames_recorded(helper: *mut core::ffi::c_void, ms: i64) {
    if !helper.is_null() {
        unsafe { item(helper) }.recorded(ms);
    }
}

#[unsafe(no_mangle)]
extern "C" fn ost_clip_frames_stopped(helper: *mut core::ffi::c_void, path: *const core::ffi::c_char) {
    if helper.is_null() || path.is_null() {
        return;
    }
    let p = unsafe { CStr::from_ptr(path) }.to_string_lossy().to_string();
    unsafe { item(helper) }.stopped(QString::from(p.as_str()));
}

#[unsafe(no_mangle)]
extern "C" fn ost_clip_frames_failed(helper: *mut core::ffi::c_void, message: *const core::ffi::c_char) {
    if helper.is_null() || message.is_null() {
        return;
    }
    let m = unsafe { CStr::from_ptr(message) }.to_string_lossy().to_string();
    unsafe { item(helper) }.failed(QString::from(m.as_str()));
}
