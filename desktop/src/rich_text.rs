//! `RichText`: the compose box's formatting, as Teams' formatting bar
//! applies it. A QML item placed inside a TextEdit; it edits that
//! TextEdit's QTextDocument (src/richtext.cpp) and writes it out as clean
//! HTML for `teams_html_with_media`.

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
        type RichText = super::RichTextRust;
    }

    unsafe extern "RustQt" {
        /// Apply a command to the text from `a` to `b` (bold, italic,
        /// underline, strike, bg/fg/size with a value or "", code, clear,
        /// heading 0-3, indent, outdent, hr, quote, codeblock, lang).
        #[qinvokable]
        fn apply(self: Pin<&mut RichText>, a: i32, b: i32, op: &QString, arg: &QString);
        /// What applies at `pos`, as JSON.
        #[qinvokable]
        fn state(self: Pin<&mut RichText>, pos: i32) -> QString;
        /// The text as clean HTML.
        #[qinvokable]
        #[cxx_name = "exportHtml"]
        fn export_html(self: Pin<&mut RichText>) -> QString;
        /// The quote and code runs, as JSON, for QML to draw behind.
        #[qinvokable]
        fn regions(self: Pin<&mut RichText>) -> QString;
    }

    impl cxx_qt::Constructor<()> for RichText {}
}

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::ffi::{CStr, CString};

unsafe extern "C" {
    fn ost_rich_apply(
        helper: *mut core::ffi::c_void,
        a: i32,
        b: i32,
        op: *const core::ffi::c_char,
        arg: *const core::ffi::c_char,
    );
    fn ost_rich_state(helper: *mut core::ffi::c_void, pos: i32) -> *mut core::ffi::c_char;
    fn ost_rich_export(helper: *mut core::ffi::c_void) -> *mut core::ffi::c_char;
    fn ost_rich_regions(helper: *mut core::ffi::c_void) -> *mut core::ffi::c_char;
    fn ost_rich_free(s: *mut core::ffi::c_char);
}

#[derive(Default)]
pub struct RichTextRust;

impl cxx_qt::Constructor<()> for qobject::RichText {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> RichTextRust {
        RichTextRust
    }
}

/// A C string from richtext.cpp, freed.
fn take(p: *mut core::ffi::c_char) -> QString {
    if p.is_null() {
        return QString::default();
    }
    // SAFETY: richtext.cpp returns a malloc'd NUL-terminated UTF-8 string,
    // which ost_rich_free releases once it is copied.
    let s = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
    unsafe { ost_rich_free(p) };
    QString::from(s.as_str())
}

impl qobject::RichText {
    fn this(self: Pin<&mut Self>) -> *mut core::ffi::c_void {
        // SAFETY: the pointer is only used by richtext.cpp during this call,
        // as the QQuickItem this object is.
        unsafe { self.get_unchecked_mut() as *mut Self as *mut core::ffi::c_void }
    }

    pub fn apply(self: Pin<&mut Self>, a: i32, b: i32, op: &QString, arg: &QString) {
        let (Ok(op), Ok(arg)) = (CString::new(op.to_string()), CString::new(arg.to_string()))
        else {
            return;
        };
        let me = self.this();
        // SAFETY: `me` is this live item; the strings outlive the call.
        unsafe { ost_rich_apply(me, a, b, op.as_ptr(), arg.as_ptr()) };
    }

    pub fn state(self: Pin<&mut Self>, pos: i32) -> QString {
        let me = self.this();
        // SAFETY: `me` is this live item.
        take(unsafe { ost_rich_state(me, pos) })
    }

    pub fn regions(self: Pin<&mut Self>) -> QString {
        let me = self.this();
        // SAFETY: `me` is this live item.
        take(unsafe { ost_rich_regions(me) })
    }

    pub fn export_html(self: Pin<&mut Self>) -> QString {
        let me = self.this();
        // SAFETY: `me` is this live item.
        take(unsafe { ost_rich_export(me) })
    }
}
