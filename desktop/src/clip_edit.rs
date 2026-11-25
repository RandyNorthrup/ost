//! Rendering the recorder's edit (src/clipedit.cpp, FFmpeg): the parts of
//! the recordings in order, cut and joined, with music under them.

use std::ffi::CString;

unsafe extern "C" {
    fn ost_clip_render(
        graph: *const core::ffi::c_char,
        out: *const core::ffi::c_char,
        width: i32,
        height: i32,
        error: *mut core::ffi::c_char,
        error_len: i32,
    ) -> i32;
}

/// Render `graph` (outputs [v] and [a]) to the MP4 `out`.
pub fn render(graph: &str, out: &str, width: u32, height: u32) -> anyhow::Result<()> {
    let g = CString::new(graph)?;
    let o = CString::new(out)?;
    let mut err = vec![0 as core::ffi::c_char; 512];
    // SAFETY: NUL-terminated inputs; `err` has room for the message.
    let r = unsafe {
        ost_clip_render(
            g.as_ptr(),
            o.as_ptr(),
            width as i32,
            height as i32,
            err.as_mut_ptr(),
            err.len() as i32,
        )
    };
    if r != 0 {
        let msg = unsafe { std::ffi::CStr::from_ptr(err.as_ptr()) }
            .to_string_lossy()
            .to_string();
        anyhow::bail!("Couldn't make the clip: {msg}");
    }
    Ok(())
}
