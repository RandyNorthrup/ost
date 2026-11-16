//! `RichText`: the compose box's formatting, as Teams' formatting bar
//! applies it. A QML item placed inside a TextEdit; it edits that
//! TextEdit's QTextDocument (src/richtext.cpp) and writes it out as clean
//! HTML for `teams_html_with_media`.
//!
//! In received messages it finds inline code's place in the laid-out text,
//! for QML to draw Teams' box behind it (`code_boxes`).

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
        /// Put HTML this item exported back in the (empty) box with every
        /// format it had: quotes, code blocks, tables, lists, headings,
        /// inline code, links, and mentions in `mention_color` (a draft
        /// coming back).
        #[qinvokable]
        #[cxx_name = "importHtml"]
        fn import_html(self: Pin<&mut RichText>, html: &QString, mention_color: &QString);
        /// The quote and code runs, as JSON, for QML to draw behind.
        #[qinvokable]
        fn regions(self: Pin<&mut RichText>) -> QString;
        /// Received inline code (the runs set in `family`): room beside
        /// each run, and its boxes, as JSON {border, dpr, settled, boxes:
        /// [{x, y, w, h, open_start, open_end}]}, for QML to draw behind
        /// the text. Not settled: ask again once the text is laid out anew.
        #[qinvokable]
        #[cxx_name = "codeBoxes"]
        fn code_boxes(self: Pin<&mut RichText>, family: &QString) -> QString;
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
    fn ost_rich_import(
        helper: *mut core::ffi::c_void,
        blocks_json: *const core::ffi::c_char,
        mention_color: *const core::ffi::c_char,
    );
    fn ost_rich_free(s: *mut core::ffi::c_char);
    fn ost_rich_dpr(helper: *mut core::ffi::c_void) -> f64;
    fn ost_rich_code_runs(
        helper: *mut core::ffi::c_void,
        family: *const core::ffi::c_char,
        room: f64,
    ) -> *mut core::ffi::c_char;
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

    pub fn code_boxes(self: Pin<&mut Self>, family: &QString) -> QString {
        let Ok(family) = CString::new(family.to_string()) else {
            return QString::default();
        };
        let me = self.this();
        // SAFETY: `me` is this live item.
        let dpr = unsafe { ost_rich_dpr(me) };
        let border = code_border(dpr);
        // SAFETY: `me` is this live item; `family` outlives the call.
        let runs = take(unsafe { ost_rich_code_runs(me, family.as_ptr(), code_room(border)) });
        QString::from(code_boxes_json(&runs.to_string(), dpr).as_str())
    }

    pub fn export_html(self: Pin<&mut Self>) -> QString {
        let me = self.this();
        // SAFETY: `me` is this live item.
        take(unsafe { ost_rich_export(me) })
    }

    pub fn import_html(self: Pin<&mut Self>, html: &QString, mention_color: &QString) {
        // The blocks are read here (teams-cli's compose_blocks); richtext.cpp
        // builds them into the document.
        let blocks = teams_cli::api::compose_blocks::compose_blocks_json(&html.to_string());
        let (Ok(blocks), Ok(color)) = (CString::new(blocks), CString::new(mention_color.to_string()))
        else {
            return;
        };
        let me = self.this();
        // SAFETY: `me` is this live item; the strings outlive the call.
        unsafe { ost_rich_import(me, blocks.as_ptr(), color.as_ptr()) };
    }
}

// Teams' inline code as received ("OST TEST 70", measured on winpc): a box
// with padding 4, a 0.67 border and margin 0 2 around the glyphs. Chromium
// draws it 4.67 out from the glyphs' content area (the font's ascent and
// descent, in whole device pixels) and leaves the margin outside it; a
// box broken over lines is open where the line breaks (box-decoration-break
// slice), one box per line.
const CODE_PADDING: f64 = 4.0;
const CODE_MARGIN: f64 = 2.0;
const CODE_BORDER: f64 = 0.67;

/// The border as Chromium draws it: whole device pixels, at least one.
fn code_border(dpr: f64) -> f64 {
    let dpr = if dpr > 0.0 { dpr } else { 1.0 };
    (CODE_BORDER * dpr + 1e-6).floor().max(1.0) / dpr
}

/// The room beside a run: margin, border and padding.
fn code_room(border: f64) -> f64 {
    CODE_MARGIN + border + CODE_PADDING
}

/// One line's piece of a run (richtext.cpp's `ost_rich_code_runs`).
#[derive(Debug, Clone, Copy, PartialEq)]
struct CodeRun {
    /// Where the glyphs start.
    x0: f64,
    /// Where the room after the run ends (or, broken, its last glyph).
    x1: f64,
    base: f64,
    ascent: f64,
    descent: f64,
    open_start: bool,
    open_end: bool,
}

/// The box (x, y, w, h) around a run's piece, its edges on device pixels.
fn code_box(r: &CodeRun, dpr: f64) -> (f64, f64, f64, f64) {
    let dpr = if dpr > 0.0 { dpr } else { 1.0 };
    let snap = |v: f64| (v * dpr).round() / dpr;
    let out = CODE_PADDING + code_border(dpr);
    let left = if r.open_start { r.x0 } else { r.x0 - out };
    let right = if r.open_end { r.x1 } else { r.x1 - CODE_MARGIN };
    let top = r.base - snap(r.ascent) - out;
    let bottom = r.base + snap(r.descent) + out;
    let (l, t) = (snap(left), snap(top));
    (l, t, snap(right) - l, snap(bottom) - t)
}

fn code_boxes_json(runs: &str, dpr: f64) -> String {
    let all: serde_json::Value = serde_json::from_str(runs).unwrap_or_default();
    let settled = all.get("settled").and_then(serde_json::Value::as_bool).unwrap_or(true);
    let runs = all.get("runs").and_then(serde_json::Value::as_array).cloned().unwrap_or_default();
    let num = |v: &serde_json::Value, k: &str| v.get(k).and_then(serde_json::Value::as_f64).unwrap_or(0.0);
    let flag = |v: &serde_json::Value, k: &str| v.get(k).and_then(serde_json::Value::as_bool).unwrap_or(false);
    let boxes: Vec<serde_json::Value> = runs
        .iter()
        .map(|v| {
            let r = CodeRun {
                x0: num(v, "x0"),
                x1: num(v, "x1"),
                base: num(v, "base"),
                ascent: num(v, "ascent"),
                descent: num(v, "descent"),
                open_start: flag(v, "open_start"),
                open_end: flag(v, "open_end"),
            };
            let (x, y, w, h) = code_box(&r, dpr);
            serde_json::json!({ "x": x, "y": y, "w": w, "h": h, "open_start": r.open_start, "open_end": r.open_end })
        })
        .collect();
    serde_json::json!({ "border": code_border(dpr), "boxes": boxes, "dpr": dpr, "settled": settled }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(x0: f64, x1: f64, open_start: bool, open_end: bool) -> CodeRun {
        CodeRun { x0, x1, base: 16.0, ascent: 12.99, descent: 3.28, open_start, open_end }
    }

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 0.01
    }

    #[test]
    fn border_is_whole_device_pixels() {
        assert!(close(code_border(1.0), 1.0));
        assert!(close(code_border(1.5), 2.0 / 3.0));
        assert!(close(code_border(2.0), 0.5));
        assert!(close(code_border(3.0), 2.0 / 3.0));
    }

    #[test]
    fn box_as_teams_draws_it_at_150_percent() {
        // winpc (DPR 1.5): text after "ab " ending at 19.198 starts at
        // 25.865, the box at 21.198 (margin 2); it is 25.333 tall from
        // 1.333 above the line, around a 16 px content area.
        let room = code_room(code_border(1.5));
        assert!(close(room, 6.667));
        let glyphs = 24.5;
        let r = CodeRun { x0: 19.198 + room, x1: 19.198 + room + glyphs + room, base: 16.0, ascent: 12.667, descent: 3.333, open_start: false, open_end: false };
        let (x, y, w, h) = code_box(&r, 1.5);
        assert!(close(x, 21.333), "{x}"); // 21.198 on device pixels
        assert!(close(y, -1.333), "{y}");
        assert!(close(h, 25.333), "{h}");
        // 33.833 in Chromium; on device pixels, within one of it.
        assert!((w - (glyphs + 2.0 * (4.0 + 0.667))).abs() <= 2.0 / 3.0, "{w}");
    }

    #[test]
    fn box_at_100_percent() {
        let (x, y, w, h) = code_box(&run(7.0, 50.0, false, false), 1.0);
        // 4 padding + 1 border out from the glyphs; the margin outside.
        assert_eq!((x, y), (2.0, 16.0 - 13.0 - 5.0));
        assert_eq!(w, 48.0 - 2.0);
        assert_eq!(h, 13.0 + 3.0 + 10.0);
    }

    #[test]
    fn wrapped_run_is_open_where_it_breaks() {
        let (x, _, w, _) = code_box(&run(100.0, 180.0, false, true), 1.0);
        assert_eq!((x, x + w), (95.0, 180.0));
        let (x, _, w, _) = code_box(&run(0.0, 60.0, true, false), 1.0);
        assert_eq!((x, x + w), (0.0, 58.0));
    }

    #[test]
    fn json_round_trip() {
        let out = code_boxes_json(
            r#"{"settled":false,"runs":[{"x0":7,"x1":50,"base":16,"ascent":12.99,"descent":3.28,"open_start":false,"open_end":true}]}"#,
            1.0,
        );
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["border"], 1.0);
        assert_eq!(v["boxes"][0]["x"], 2.0);
        assert_eq!(v["boxes"][0]["w"], 48.0);
        assert_eq!(v["boxes"][0]["open_end"], true);
        assert_eq!(v["settled"], false);
        assert_eq!(code_boxes_json("garbage", 1.0), r#"{"border":1.0,"boxes":[],"dpr":1.0,"settled":true}"#);
    }
}
