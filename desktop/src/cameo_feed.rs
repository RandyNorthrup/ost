//! PowerPoint Live's Cameo pictures (docs/spec/content-sharing.md §3):
//! with the Cameo layout every client composites the presenter's camera
//! into PowerPoint's frame itself — the presenter its own camera, each
//! attendee the presenter's incoming video — at the size of the slide view
//! PowerPoint reports (Teams' PptSharingContainer cameo compositor and
//! `VideoFrameToPptForCameo`: `postMessage({bufferMetadata, arrayBuffer})`
//! with BGRA). The slide-show page (ppt_host.js) connects to a WebSocket
//! on 127.0.0.1 with a secret path, says which picture and size it wants
//! (`{"key": "self" | <a remote stream>, "width", "height"}`, as text,
//! again whenever that changes), and gets frames as binary messages: a
//! u32 width and u32 height (little endian), then BGRA. A 0 × 0 frame
//! means there's no picture (Teams' blank frame).

use std::time::Duration;

/// The page's address (`ws://127.0.0.1:<port>/<secret>`), starting the
/// server on first use.
pub fn socket() -> String {
    static URL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    URL.get_or_init(|| {
        let secret = uuid::Uuid::new_v4().simple().to_string();
        let std_listener = match std::net::TcpListener::bind("127.0.0.1:0") {
            Ok(l) => l,
            Err(e) => {
                tracing::warn!("cameo frames: {e}");
                return String::new();
            }
        };
        let port = std_listener.local_addr().map(|a| a.port()).unwrap_or(0);
        let _ = std_listener.set_nonblocking(true);
        let path = format!("/{secret}");
        crate::backend::runtime().spawn(async move {
            let Ok(listener) = tokio::net::TcpListener::from_std(std_listener) else { return };
            while let Ok((stream, _)) = listener.accept().await {
                let path = path.clone();
                tokio::spawn(async move {
                    if let Err(e) = serve(stream, &path).await {
                        tracing::debug!("cameo frames: {e:#}");
                    }
                });
            }
        });
        format!("ws://127.0.0.1:{port}/{secret}")
    })
    .clone()
}

/// What the page asked for.
#[derive(Debug, Clone, Default, PartialEq, serde::Deserialize)]
struct Want {
    key: String,
    width: u32,
    height: u32,
}

/// The largest picture sent (PowerPoint scales it into the cameo).
const MAX_WIDTH: u32 = 1280;
/// Teams sends the camera's frames as they come; 15 a second is plenty.
const INTERVAL: Duration = Duration::from_millis(66);

async fn serve(stream: tokio::net::TcpStream, path: &str) -> anyhow::Result<()> {
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::{Message, handshake::server::{ErrorResponse, Request, Response}};
    #[allow(clippy::result_large_err, reason = "tungstenite's handshake callback returns its own ErrorResponse")]
    let check = |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        if req.uri().path() == path {
            Ok(resp)
        } else {
            Err(Response::builder().status(404).body(None).unwrap())
        }
    };
    let mut ws = tokio_tungstenite::accept_hdr_async(stream, check).await?;
    let mut want = Want::default();
    let mut last_seq = 0u64;
    let mut blank_sent = false;
    let mut tick = tokio::time::interval(INTERVAL);
    loop {
        tokio::select! {
            msg = ws.next() => match msg {
                Some(Ok(Message::Text(t))) => {
                    if let Ok(w) = serde_json::from_str::<Want>(&t) {
                        want = w;
                        last_seq = 0;
                        blank_sent = false;
                    }
                }
                Some(Ok(Message::Close(_))) | None => return Ok(()),
                Some(Err(e)) => return Err(e.into()),
                _ => {}
            },
            _ = tick.tick() => {
                if want.key.is_empty() || want.width == 0 || want.height == 0 {
                    continue;
                }
                match teams_cli::calling::frames::latest(&want.key) {
                    Some(f) if f.seq != last_seq => {
                        last_seq = f.seq;
                        blank_sent = false;
                        let (w, h) = fit(want.width, want.height);
                        let out = tokio::task::spawn_blocking(move || compose(&f, w, h)).await?;
                        ws.send(Message::Binary(out.into())).await?;
                    }
                    Some(_) => {}
                    None if !blank_sent => {
                        blank_sent = true;
                        ws.send(Message::Binary(vec![0u8; 8].into())).await?;
                    }
                    None => {}
                }
            }
        }
    }
}

/// The picture's size: the slide view's, at most [`MAX_WIDTH`] wide.
fn fit(width: u32, height: u32) -> (u32, u32) {
    if width <= MAX_WIDTH {
        return (width.max(1), height.max(1));
    }
    let h = (height as u64 * MAX_WIDTH as u64 / width as u64).max(1) as u32;
    (MAX_WIDTH, h)
}

/// The camera picture covering `w` × `h` (centred, cropped to fill, as a
/// video tile), as BGRA after the 8-byte size header.
fn compose(f: &teams_cli::calling::frames::Frame, w: u32, h: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + (w * h * 4) as usize);
    out.extend_from_slice(&w.to_le_bytes());
    out.extend_from_slice(&h.to_le_bytes());
    let (sw, sh) = (f.width as f64, f.height as f64);
    let scale = (w as f64 / sw).max(h as f64 / sh);
    let (ox, oy) = ((sw - w as f64 / scale) / 2.0, (sh - h as f64 / scale) / 2.0);
    for y in 0..h {
        let sy = ((oy + (y as f64 + 0.5) / scale) as u32).min(f.height - 1);
        let row = (sy * f.width) as usize * 4;
        for x in 0..w {
            let sx = ((ox + (x as f64 + 0.5) / scale) as u32).min(f.width - 1);
            let i = row + sx as usize * 4;
            let p = &f.rgba[i..i + 4];
            out.extend_from_slice(&[p[2], p[1], p[0], p[3]]);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fits_and_composes_bgra() {
        assert_eq!(fit(800, 450), (800, 450));
        assert_eq!(fit(2560, 1440), (1280, 720));
        // A 2 × 1 red | blue picture covering 2 × 2: the centre column pair.
        let f = teams_cli::calling::frames::Frame {
            width: 2,
            height: 1,
            rgba: std::sync::Arc::new(vec![255, 0, 0, 255, 0, 0, 255, 255]),
            seq: 1,
        };
        let out = compose(&f, 2, 2);
        assert_eq!(&out[0..8], &[2, 0, 0, 0, 2, 0, 0, 0]);
        assert_eq!(out.len(), 8 + 16);
        // BGRA: red is 0,0,255.
        assert_eq!(&out[8..12], &[0, 0, 255, 255]);
        assert_eq!(&out[12..16], &[255, 0, 0, 255]);
    }
}
