//! Teams' avatars: Microsoft's Avatars video app (Teams' ECS `avatarAppId`)
//! hosted as Teams hosts it (qml/AvatarHost.qml on OST's TeamsJS host),
//! drawing camera-less frames that go out as your camera, with its viseme
//! model run on your microphone (vfx/src/avatar.rs).
//!
//! The host page's isolated world talks to this module over a WebSocket on
//! 127.0.0.1 with a secret path. Binary messages, little endian:
//! - to the page, a frame to draw: u32 kind 1, u32 width, u32 height,
//!   u64 number, u32 viseme length, the visemes (the app's
//!   `audioInferenceResult`);
//! - from the page, kind 1: u32 width, u32 height, u64 number, NV12 (the
//!   frame the app drew); kind 2: the app's `audioInferenceModel`.

use std::time::Duration;

/// Microsoft's Avatars app (Microsoft Mesh).
pub const AVATARS_APP: &str = "96a116ab-6847-4d22-90f3-f4dd6af74938";

/// The app's page (its videoAppContentUrl), its personal tab (Teams'
/// "Avatar builder") and name, from its definition.
pub fn app_info(def: &serde_json::Value) -> serde_json::Value {
    let facts = teams_cli::api::app_host::facts_from(def);
    let studio = facts.static_tabs.iter().find(|t| t.content_url.starts_with("https://"));
    serde_json::json!({
        "appId": AVATARS_APP,
        "name": def["name"].as_str().map(str::to_string).unwrap_or_else(|| crate::backend::tr("Avatars")),
        "url": def["meetingExtensionDefinition"]["videoAppContentUrl"].as_str().unwrap_or_default(),
        "studio": studio.map(|t| t.content_url.clone()).unwrap_or_default(),
        "studioName": studio.map(|t| t.name.clone()).unwrap_or_default(),
        "studioEntity": studio.map(|t| t.entity_id.clone()).unwrap_or_default(),
        // Its icons and colour (Teams' app header shows the colour icon on
        // the accent colour; the app bar, the outline icon).
        "icon": https(def["largeImageUrl"].as_str()),
        "outline": https(def["smallImageUrl"].as_str()),
        "accentColor": def["accentColor"].as_str().filter(|c| c.starts_with('#')).unwrap_or_default(),
    })
}

fn https(u: Option<&str>) -> String {
    u.filter(|u| u.starts_with("https://")).unwrap_or_default().to_string()
}

const TO_DRAW: u32 = 1;
const DRAWN: u32 = 1;
const MODEL: u32 = 2;

/// A request as the page takes it.
pub fn encode_request(r: &ost_vfx::avatar::Request) -> Vec<u8> {
    let mut out = Vec::with_capacity(24 + r.visemes.len());
    out.extend_from_slice(&TO_DRAW.to_le_bytes());
    out.extend_from_slice(&r.width.to_le_bytes());
    out.extend_from_slice(&r.height.to_le_bytes());
    out.extend_from_slice(&r.seq.to_le_bytes());
    out.extend_from_slice(&(r.visemes.len() as u32).to_le_bytes());
    out.extend_from_slice(&r.visemes);
    out
}

/// What the page sent.
#[derive(Debug, PartialEq)]
pub enum FromPage {
    Drawn(ost_vfx::filter::Frame),
    Model(Vec<u8>),
}

pub fn decode(b: &[u8]) -> Option<FromPage> {
    let kind = u32::from_le_bytes(b.get(0..4)?.try_into().ok()?);
    match kind {
        DRAWN => {
            let width = u32::from_le_bytes(b.get(4..8)?.try_into().ok()?);
            let height = u32::from_le_bytes(b.get(8..12)?.try_into().ok()?);
            let seq = u64::from_le_bytes(b.get(12..20)?.try_into().ok()?);
            let data = b.get(20..)?.to_vec();
            (width > 0 && height > 0 && data.len() >= width as usize * height as usize * 3 / 2)
                .then_some(FromPage::Drawn(ost_vfx::filter::Frame { width, height, seq, data }))
        }
        MODEL => Some(FromPage::Model(b[4..].to_vec())),
        _ => None,
    }
}

/// The page's address for frames (`ws://127.0.0.1:<port>/<secret>`),
/// starting the server on first use.
pub fn socket() -> String {
    static URL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    URL.get_or_init(|| {
        let secret = uuid::Uuid::new_v4().simple().to_string();
        let std_listener = match std::net::TcpListener::bind("127.0.0.1:0") {
            Ok(l) => l,
            Err(e) => {
                tracing::warn!("avatar frames: {e}");
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
                        tracing::debug!("avatar frames: {e:#}");
                    }
                });
            }
        });
        format!("ws://127.0.0.1:{port}/{secret}")
    })
    .clone()
}

async fn serve(stream: tokio::net::TcpStream, path: &str) -> anyhow::Result<()> {
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::{
        Message,
        handshake::server::{ErrorResponse, Request, Response},
    };
    let check = |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        if req.uri().path() == path {
            Ok(resp)
        } else {
            Err(Response::builder().status(404).body(None).unwrap())
        }
    };
    let ws = tokio_tungstenite::accept_hdr_async(stream, check).await?;
    let (mut tx, mut rx) = ws.split();
    tracing::info!("Avatars app connected for frames");
    // Requests out as the camera ticks; drawn frames in as they come (the
    // app draws one per request, never holding the camera up).
    let sender = tokio::spawn(async move {
        let mut after = 0u64;
        let mut lip_sync = false;
        loop {
            let r = tokio::task::spawn_blocking(move || ost_vfx::avatar::next_request(after, Duration::from_millis(500))).await?;
            let Some(r) = r else { continue };
            after = r.seq;
            if !r.visemes.is_empty() && !lip_sync {
                lip_sync = true;
                tracing::info!(bytes = r.visemes.len(), "avatar lip sync: the viseme model's output reaches the app");
            }
            tx.send(Message::Binary(encode_request(&r).into())).await?;
        }
        #[allow(unreachable_code)]
        anyhow::Ok(())
    });
    let mut drawn = 0u64;
    let mut since = std::time::Instant::now();
    while let Some(m) = rx.next().await {
        match m? {
            Message::Binary(b) => match decode(&b) {
                Some(FromPage::Drawn(f)) => {
                    drawn += 1;
                    if drawn == 1 {
                        tracing::info!(width = f.width, height = f.height, "Avatars app drew its first frame");
                        since = std::time::Instant::now();
                    } else if drawn % 300 == 0 {
                        let fps = 299.0 / since.elapsed().as_secs_f64();
                        tracing::info!(drawn, fps = format!("{fps:.1}"), "Avatars app drawing");
                        since = std::time::Instant::now();
                    }
                    ost_vfx::avatar::put_output(f);
                }
                Some(FromPage::Model(m)) => match ost_vfx::avatar::set_viseme_model(&m) {
                    Ok(()) => tracing::info!(bytes = m.len(), loaded = ost_vfx::avatar::has_viseme_model(), "avatar viseme model"),
                    Err(e) => tracing::warn!("avatar viseme model: {e:#}"),
                },
                None => {}
            },
            Message::Close(_) => break,
            _ => {}
        }
    }
    sender.abort();
    tracing::info!(drawn, "Avatars app disconnected");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_app_definition_names_its_page_and_builder() {
        let def = serde_json::json!({ "name": "Avatars", "accentColor": "#121212", "largeImageUrl": "https://x/c.png", "smallImageUrl": "http://x/o.png",
            "meetingExtensionDefinition": { "videoAppContentUrl": "https://mesh.public.onecdn.static.microsoft/mesh/avatars/prod/video?appSessionId={appSessionId}" },
            "staticTabs": [{ "entityId": "Customize Avatar", "name": "Avatar builder", "scopes": ["personal"],
                "contentUrl": "https://mesh.public.onecdn.static.microsoft/mesh/avatars/prod/studio?appSessionId={appSessionId}" }] });
        let i = app_info(&def);
        assert!(i["url"].as_str().unwrap().ends_with("/video?appSessionId={appSessionId}"));
        assert!(i["studio"].as_str().unwrap().ends_with("/studio?appSessionId={appSessionId}"));
        assert_eq!(i["studioName"], "Avatar builder");
        assert_eq!(i["studioEntity"], "Customize Avatar");
        assert_eq!((i["icon"].as_str(), i["outline"].as_str(), i["accentColor"].as_str()), (Some("https://x/c.png"), Some(""), Some("#121212")));
    }

    #[test]
    fn requests_and_drawn_frames_cross_the_wire() {
        let r = ost_vfx::avatar::Request { width: 4, height: 2, seq: 9, visemes: vec![1, 2, 3, 4] };
        let b = encode_request(&r);
        assert_eq!(b.len(), 24 + 4);
        assert_eq!(&b[0..4], &1u32.to_le_bytes());
        assert_eq!(&b[20..24], &4u32.to_le_bytes());
        let mut drawn = vec![1, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0];
        drawn.extend_from_slice(&9u64.to_le_bytes());
        drawn.extend_from_slice(&[7; 12]);
        match decode(&drawn) {
            Some(FromPage::Drawn(f)) => assert_eq!((f.width, f.height, f.seq, f.data.len()), (4, 2, 9, 12)),
            other => panic!("{other:?}"),
        }
        // Too little picture for its size.
        assert!(decode(&drawn[..30]).is_none());
        assert_eq!(decode(&[2, 0, 0, 0, 5, 6]), Some(FromPage::Model(vec![5, 6])));
        assert!(decode(&[3, 0, 0, 0]).is_none());
    }
}
