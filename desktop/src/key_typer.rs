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
        /// ("\n" is Return, "\u{1}" Ctrl+End).
        #[qinvokable]
        #[cxx_name = "typeText"]
        fn type_text(self: Pin<&mut KeyTyper>, text: &QString);
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
}
