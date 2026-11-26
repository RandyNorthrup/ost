//! `WindowTool`: a QML item that tells and sets what QML can't about the
//! window it is in.
//!
//! - `exposed()`: whether the desktop shows the window. A Wayland client is
//!   never told it was minimized (Qt's `visibility` stays `Windowed` after
//!   KWin's, GNOME's or Hyprland's minimize, a move to another workspace,
//!   a click on its taskbar button): the compositor only stops drawing it,
//!   which Qt reports as the window no longer being exposed (xdg-shell's
//!   `suspended` state, or frame callbacks that stop coming). Teams' compact
//!   call view opens on exactly that (CallWindow.qml).
//! - `layerPrepare` / `layerPlace`: make the window a wlr-layer-shell
//!   surface (where the compositor has one: KDE Plasma, Hyprland, Sway…)
//!   and anchor it, as a floating always-on-top window Teams places itself
//!   needs on Wayland, where an app can neither place its windows nor keep
//!   them above others (src/native.cpp).

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
        type WindowTool = super::WindowToolRust;
    }

    unsafe extern "RustQt" {
        /// Whether this item's window is shown on the screen now (false
        /// while minimized, on another workspace or not yet shown).
        #[qinvokable]
        fn exposed(self: Pin<&mut WindowTool>) -> bool;

        /// Before the window first shows: make it a layer-shell surface on
        /// `layer` (2 top, 3 overlay) that takes the keyboard only when
        /// clicked and shows without taking focus, named `scope`. False
        /// where there is no layer shell (X11, GNOME): the window stays an
        /// ordinary one.
        #[qinvokable]
        #[cxx_name = "layerPrepare"]
        fn layer_prepare(self: Pin<&mut WindowTool>, scope: &QString, layer: i32) -> bool;

        /// Anchor the layer surface to the work area's edges in `anchors`
        /// (top 1, bottom 2, left 4, right 8) with these margins.
        #[qinvokable]
        #[cxx_name = "layerPlace"]
        fn layer_place(
            self: Pin<&mut WindowTool>,
            anchors: i32,
            left: i32,
            top: i32,
            right: i32,
            bottom: i32,
        );
    }

    // QQuickItem takes a QQuickItem parent; QML parents it.
    impl cxx_qt::Constructor<()> for WindowTool {}
}

use core::pin::Pin;
use cxx_qt_lib::QString;

unsafe extern "C" {
    /// Whether `item`'s window is exposed (src/native.cpp).
    fn ost_item_window_exposed(item: *mut core::ffi::c_void) -> bool;
    /// Make `item`'s window a layer-shell surface (src/native.cpp).
    fn ost_item_layer_prepare(
        item: *mut core::ffi::c_void,
        scope: *const core::ffi::c_char,
        layer: i32,
    ) -> bool;
    /// Anchor `item`'s layer-shell window (src/native.cpp).
    fn ost_item_layer_place(
        item: *mut core::ffi::c_void,
        anchors: i32,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    );
}

#[derive(Default)]
pub struct WindowToolRust;

impl cxx_qt::Constructor<()> for qobject::WindowTool {
    type BaseArguments = ();
    type InitializeArguments = ();
    type NewArguments = ();

    fn route_arguments(_: ()) -> ((), (), ()) {
        ((), (), ())
    }

    fn new(_: ()) -> WindowToolRust {
        WindowToolRust
    }
}

impl qobject::WindowTool {
    fn item(self: Pin<&mut Self>) -> *mut core::ffi::c_void {
        // SAFETY: only the address is taken; the C++ side treats it as the
        // QQuickItem it is.
        unsafe { self.get_unchecked_mut() as *mut Self as *mut core::ffi::c_void }
    }

    pub fn exposed(self: Pin<&mut Self>) -> bool {
        // SAFETY: `self` is the live C++ WindowTool (a QQuickItem); the
        // call only reads its window, on the Qt thread.
        unsafe { ost_item_window_exposed(self.item()) }
    }

    pub fn layer_prepare(self: Pin<&mut Self>, scope: &QString, layer: i32) -> bool {
        let Ok(scope) = std::ffi::CString::new(scope.to_string()) else {
            return false;
        };
        // SAFETY: as above; the scope is a C string valid for the call.
        unsafe { ost_item_layer_prepare(self.item(), scope.as_ptr(), layer) }
    }

    pub fn layer_place(
        self: Pin<&mut Self>,
        anchors: i32,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    ) {
        // SAFETY: as above.
        unsafe { ost_item_layer_place(self.item(), anchors, left, top, right, bottom) }
    }
}
