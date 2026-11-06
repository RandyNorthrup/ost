//! Your screen, for sharing it in a call: the desktop's ScreenCast portal
//! (xdg-desktop-portal: Hyprland, GNOME, KDE and others) shows its own
//! picker for a screen or window, and PipeWire delivers that source's
//! frames. They're converted to I420, scaled to fit [`MAX_W`]x[`MAX_H`],
//! for the H.264 encoder.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;

use anyhow::{Context, Result};
use ashpd::desktop::PersistMode;
use ashpd::desktop::screencast::{CursorMode, Screencast, SelectSourcesOptions, SourceType};
use pipewire as pw;
use pw::spa;

use super::camera::YuvFrame;

/// The largest picture we send; bigger screens are scaled down to fit.
pub const MAX_W: u32 = 1280;
pub const MAX_H: u32 = 720;

/// A running screen capture; drop it to stop (and end the portal session).
pub struct ScreenCapture {
    stop: Arc<AtomicBool>,
    session: Option<ashpd::desktop::Session<Screencast>>,
}

impl ScreenCapture {
    /// Ask the portal what to share (it shows its picker) and start
    /// capturing it. Fails if the person cancels the picker.
    pub async fn start() -> Result<(Self, mpsc::Receiver<YuvFrame>)> {
        let proxy = Screencast::new()
            .await
            .context("The desktop's screen-sharing portal isn't available")?;
        let session = proxy.create_session(Default::default()).await?;
        proxy
            .select_sources(
                &session,
                SelectSourcesOptions::default()
                    .set_cursor_mode(CursorMode::EMBEDDED)
                    .set_sources(SourceType::MONITOR | SourceType::WINDOW)
                    .set_multiple(false)
                    .set_persist_mode(PersistMode::DoNot),
            )
            .await?
            .response()
            .context("The screen-sharing portal refused the request")?;
        let streams = proxy
            .start(&session, None, Default::default())
            .await?
            .response()
            .context("Sharing was cancelled")?;
        let node = streams
            .streams()
            .first()
            .context("Nothing was picked to share")?
            .pipe_wire_node_id();
        let fd = proxy
            .open_pipe_wire_remote(&session, Default::default())
            .await?;
        let (tx, rx) = mpsc::sync_channel::<YuvFrame>(2);
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        std::thread::Builder::new()
            .name("ost-screencast".into())
            .spawn(move || {
                if let Err(e) = capture(fd, node, tx, &stop2) {
                    tracing::warn!("screen capture ended: {e:#}");
                }
            })?;
        tracing::info!(node, "screen capture started");
        Ok((
            Self {
                stop,
                session: Some(session),
            },
            rx,
        ))
    }

    /// Whether the capture has stopped (the shared window closed, or the
    /// person ended it from the desktop).
    pub fn ended(&self) -> bool {
        self.stop.load(Ordering::Relaxed)
    }
}

impl Drop for ScreenCapture {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(session) = self.session.take()
            && let Ok(rt) = tokio::runtime::Handle::try_current()
        {
            rt.spawn(async move {
                let _ = session.close().await;
            });
        }
    }
}

/// The pixel layouts we take from PipeWire (all 4 bytes a pixel).
#[derive(Clone, Copy, Debug, PartialEq)]
enum Layout {
    Bgrx,
    Rgbx,
}

/// Run PipeWire's loop for one stream until `stop`, sending each frame.
fn capture(
    fd: std::os::fd::OwnedFd,
    node: u32,
    tx: mpsc::SyncSender<YuvFrame>,
    stop: &Arc<AtomicBool>,
) -> Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_fd_rc(fd, None)?;
    let stream = pw::stream::StreamBox::new(
        &core,
        "ost-screen-share",
        pw::properties::properties! {
            *pw::keys::MEDIA_TYPE => "Video",
            *pw::keys::MEDIA_CATEGORY => "Capture",
            *pw::keys::MEDIA_ROLE => "Screen",
        },
    )?;
    struct Negotiated {
        layout: Option<Layout>,
        width: u32,
        height: u32,
    }
    let ended = stop.clone();
    let _listener = stream
        .add_local_listener_with_user_data(Negotiated {
            layout: None,
            width: 0,
            height: 0,
        })
        .state_changed(move |_, _, _, new| {
            if matches!(
                new,
                pw::stream::StreamState::Error(_) | pw::stream::StreamState::Unconnected
            ) {
                ended.store(true, Ordering::Relaxed);
            }
        })
        .param_changed(|_, n, id, param| {
            let Some(param) = param else { return };
            if id != spa::param::ParamType::Format.as_raw() {
                return;
            }
            let mut info = spa::param::video::VideoInfoRaw::default();
            if info.parse(param).is_err() {
                return;
            }
            n.layout = match info.format() {
                spa::param::video::VideoFormat::BGRx | spa::param::video::VideoFormat::BGRA => {
                    Some(Layout::Bgrx)
                }
                spa::param::video::VideoFormat::RGBx | spa::param::video::VideoFormat::RGBA => {
                    Some(Layout::Rgbx)
                }
                _ => None,
            };
            (n.width, n.height) = (info.size().width, info.size().height);
            tracing::info!(format = ?info.format(), n.width, n.height, "screen capture format");
        })
        .process(move |stream, n| {
            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };
            let Some(layout) = n.layout else { return };
            let datas = buffer.datas_mut();
            let Some(d) = datas.first_mut() else { return };
            let (offset, size, stride) = (
                d.chunk().offset() as usize,
                d.chunk().size() as usize,
                d.chunk().stride(),
            );
            let Some(bytes) = d.data() else { return };
            let stride = if stride > 0 {
                stride as usize
            } else {
                n.width as usize * 4
            };
            let Some(pixels) = bytes.get(offset..offset + size) else {
                return;
            };
            if let Some(frame) = to_i420(pixels, n.width, n.height, stride, layout) {
                // The encoder takes what it can; a full queue drops frames.
                let _ = tx.try_send(frame);
            }
        })
        .register()?;

    let format = spa::pod::object!(
        spa::utils::SpaTypes::ObjectParamFormat,
        spa::param::ParamType::EnumFormat,
        spa::pod::property!(
            spa::param::format::FormatProperties::MediaType,
            Id,
            spa::param::format::MediaType::Video
        ),
        spa::pod::property!(
            spa::param::format::FormatProperties::MediaSubtype,
            Id,
            spa::param::format::MediaSubtype::Raw
        ),
        spa::pod::property!(
            spa::param::format::FormatProperties::VideoFormat,
            Choice,
            Enum,
            Id,
            spa::param::video::VideoFormat::BGRx,
            spa::param::video::VideoFormat::BGRx,
            spa::param::video::VideoFormat::BGRA,
            spa::param::video::VideoFormat::RGBx,
            spa::param::video::VideoFormat::RGBA
        ),
        spa::pod::property!(
            spa::param::format::FormatProperties::VideoSize,
            Choice,
            Range,
            Rectangle,
            spa::utils::Rectangle {
                width: 1920,
                height: 1080
            },
            spa::utils::Rectangle {
                width: 16,
                height: 16
            },
            spa::utils::Rectangle {
                width: 8192,
                height: 8192
            }
        ),
        spa::pod::property!(
            spa::param::format::FormatProperties::VideoFramerate,
            Choice,
            Range,
            Fraction,
            spa::utils::Fraction { num: 15, denom: 1 },
            spa::utils::Fraction { num: 0, denom: 1 },
            spa::utils::Fraction { num: 60, denom: 1 }
        ),
    );
    let bytes: Vec<u8> = spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(format),
    )
    .map_err(|e| anyhow::anyhow!("format pod: {e:?}"))?
    .0
    .into_inner();
    let mut params = [spa::pod::Pod::from_bytes(&bytes).context("format pod")?];
    stream.connect(
        spa::utils::Direction::Input,
        Some(node),
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;

    // Check for the stop flag a few times a second.
    let weak = mainloop.downgrade();
    let stop_check = stop.clone();
    let timer = mainloop.loop_().add_timer(move |_| {
        if stop_check.load(Ordering::Relaxed)
            && let Some(l) = weak.upgrade()
        {
            l.quit();
        }
    });
    timer
        .update_timer(
            Some(std::time::Duration::from_millis(200)),
            Some(std::time::Duration::from_millis(200)),
        )
        .into_result()?;
    mainloop.run();
    stop.store(true, Ordering::Relaxed);
    Ok(())
}

/// The size a `w`x`h` source is sent at: fitted inside MAX_W x MAX_H,
/// never enlarged, with even sides (I420 halves them).
pub fn fitted(w: u32, h: u32) -> (u32, u32) {
    let scale = (MAX_W as f64 / w as f64)
        .min(MAX_H as f64 / h as f64)
        .min(1.0);
    let even = |v: f64| ((v as u32) & !1).max(2);
    (even(w as f64 * scale), even(h as f64 * scale))
}

/// Convert (and scale down) a 4-byte-a-pixel picture to I420 (BT.601,
/// studio range, as H.264 decoders expect). `None` if it's too short.
fn to_i420(px: &[u8], w: u32, h: u32, stride: usize, layout: Layout) -> Option<YuvFrame> {
    if w < 2 || h < 2 || px.len() < stride * (h as usize - 1) + w as usize * 4 {
        return None;
    }
    let (ow, oh) = fitted(w, h);
    let (ow_, oh_) = (ow as usize, oh as usize);
    // Source column and row for each output column and row.
    let xs: Vec<usize> = (0..ow_).map(|x| x * w as usize / ow_).collect();
    let ys: Vec<usize> = (0..oh_).map(|y| y * h as usize / oh_).collect();
    let rgb = |x: usize, y: usize| {
        let i = y * stride + x * 4;
        let (a, b, c) = (px[i] as i32, px[i + 1] as i32, px[i + 2] as i32);
        match layout {
            Layout::Bgrx => (c, b, a),
            Layout::Rgbx => (a, b, c),
        }
    };
    let mut data = vec![0u8; ow_ * oh_ * 3 / 2];
    let (y_plane, uv) = data.split_at_mut(ow_ * oh_);
    let (u_plane, v_plane) = uv.split_at_mut(ow_ * oh_ / 4);
    for (oy, &sy) in ys.iter().enumerate() {
        for (ox, &sx) in xs.iter().enumerate() {
            let (r, g, b) = rgb(sx, sy);
            y_plane[oy * ow_ + ox] = (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16) as u8;
        }
    }
    for cy in 0..oh_ / 2 {
        for cx in 0..ow_ / 2 {
            // Average the 2x2 block's colour.
            let (mut r, mut g, mut b) = (0, 0, 0);
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let (pr, pg, pb) = rgb(xs[cx * 2 + dx], ys[cy * 2 + dy]);
                (r, g, b) = (r + pr, g + pg, b + pb);
            }
            let (r, g, b) = (r / 4, g / 4, b / 4);
            let i = cy * (ow_ / 2) + cx;
            u_plane[i] = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128).clamp(0, 255) as u8;
            v_plane[i] = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128).clamp(0, 255) as u8;
        }
    }
    Some(YuvFrame {
        width: ow,
        height: oh,
        data,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn screens_are_fitted_to_720p_with_even_sides() {
        assert_eq!(fitted(1920, 1080), (1280, 720));
        assert_eq!(fitted(2560, 1600), (1152, 720));
        assert_eq!(fitted(1271, 681), (1270, 680));
        assert_eq!(fitted(800, 3000), (192, 720));
    }

    #[test]
    fn colours_convert_to_studio_range_i420() {
        // 4x2 BGRx: white on the left half, pure red on the right.
        let mut px = Vec::new();
        for _ in 0..2 {
            px.extend_from_slice(&[255, 255, 255, 0, 255, 255, 255, 0]);
            px.extend_from_slice(&[0, 0, 255, 0, 0, 0, 255, 0]);
        }
        let f = to_i420(&px, 4, 2, 16, Layout::Bgrx).unwrap();
        assert_eq!((f.width, f.height, f.data.len()), (4, 2, 12));
        assert_eq!(f.data[0], 235, "white is Y 235");
        assert_eq!(f.data[2], 82, "red is Y 82");
        // Chroma: white is neutral; red has V well above 128.
        assert_eq!((f.data[8], f.data[10]), (128, 128));
        assert!(f.data[11] > 200 && f.data[9] < 128);
        // RGBx reads the same picture with red and blue swapped.
        let f2 = to_i420(&px, 4, 2, 16, Layout::Rgbx).unwrap();
        assert_ne!(f2.data[2], 82);
        assert!(to_i420(&px[..10], 4, 2, 16, Layout::Bgrx).is_none());
    }
}
