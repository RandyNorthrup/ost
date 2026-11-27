//! `KeyTyper`: a QML item that types text into OST's own window as real
//! key presses (Qt key events, as a keyboard sends), for pages that only
//! answer real typing. A channel Page's insert row uses it to give Loop
//! the "/" commands Teams' row runs. It only reaches the window it is in.

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
        type KeyTyper = super::KeyTyperRust;
    }

    unsafe extern "RustQt" {
        /// Type `text` into whatever has focus in this item's window
        /// ("\n" is Return, "\u{8}" Backspace, "\u{1}" Ctrl+End, "\u{2}"
        /// Shift+Home, "\u{3}" Shift+F10, "\u{16}" Ctrl+V, "\u{1a}" Ctrl+Z,
        /// "\u{1b}" Escape).
        #[qinvokable]
        #[cxx_name = "typeText"]
        fn type_text(self: Pin<&mut KeyTyper>, text: &QString);

        /// Drag the mouse with the left button held from (x1, y1) to
        /// (x2, y2) in this item's coordinates (a text selection).
        #[qinvokable]
        fn drag(self: Pin<&mut KeyTyper>, x1: f64, y1: f64, x2: f64, y2: f64);

        /// Move the mouse (no button held) to (x, y) in this item's
        /// coordinates: what's there is hovered.
        #[qinvokable]
        fn hover(self: Pin<&mut KeyTyper>, x: f64, y: f64);
    }

    // QQuickItem takes a QQuickItem parent; QML parents it.
    impl cxx_qt::Constructor<()> for KeyTyper {}
}

use core::pin::Pin;
use cxx_qt_lib::QString;

unsafe extern "C" {
    /// Send `utf8` (NUL-terminated) to `item`'s window as key presses
    /// (src/webengine.cpp).
    fn ost_type_keys(item: *mut core::ffi::c_void, utf8: *const core::ffi::c_char);
    /// Drag the mouse across `item`'s window (src/webengine.cpp).
    fn ost_mouse_drag(item: *mut core::ffi::c_void, x1: f64, y1: f64, x2: f64, y2: f64);
    /// Move the mouse over `item`'s window (src/webengine.cpp).
    fn ost_mouse_move(item: *mut core::ffi::c_void, x: f64, y: f64);
}

#[derive(Default)]
pub struct KeyTyperRust;

impl cxx_qt::Constructor<()> for qobject::KeyTyper {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> KeyTyperRust {
        KeyTyperRust
    }
}

impl qobject::KeyTyper {
    pub fn type_text(self: Pin<&mut Self>, text: &QString) {
        let Ok(text) = std::ffi::CString::new(text.to_string()) else {
            return;
        };
        // SAFETY: `self` is the live C++ KeyTyper (a QQuickItem); the call
        // only reads its window and the string, both valid for the call.
        unsafe {
            let item = self.get_unchecked_mut() as *mut Self as *mut core::ffi::c_void;
            ost_type_keys(item, text.as_ptr());
        }
    }

    pub fn drag(self: Pin<&mut Self>, x1: f64, y1: f64, x2: f64, y2: f64) {
        // SAFETY: `self` is the live C++ KeyTyper (a QQuickItem); the call
        // only reads its window and sends it mouse events.
        unsafe {
            let item = self.get_unchecked_mut() as *mut Self as *mut core::ffi::c_void;
            ost_mouse_drag(item, x1, y1, x2, y2);
        }
    }

    pub fn hover(self: Pin<&mut Self>, x: f64, y: f64) {
        // SAFETY: `self` is the live C++ KeyTyper (a QQuickItem); the call
        // only reads its window and sends it a mouse move.
        unsafe {
            let item = self.get_unchecked_mut() as *mut Self as *mut core::ffi::c_void;
            ost_mouse_move(item, x, y);
        }
    }
}
