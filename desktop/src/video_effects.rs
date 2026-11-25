//! Teams' video effects on your camera: the background (None, Standard or
//! Portrait blur, one of Teams' catalog backgrounds, still or animated, or
//! a picture of your own), Adjust brightness and Soft focus. The choices are settings (shared with
//! the QML through backend.setting / setSetting); applying them hands the
//! engine (ost-vfx) what to do, downloading and playing a catalog
//! background (src/vfxplayer.cpp) when one is chosen.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ost_vfx::{Animated, Background, Blur, Picture, Settings};
use teams_cli::calling::webrtc_video::{SEND_H, SEND_W};

/// Teams' background catalog (the animated ones first, then the pictures),
/// as the calling app loads it.
pub const CATALOG_URL: &str =
    "https://statics.teams.cdn.office.net/evergreen-assets/backgroundimages/animated.json?v=7";
const CDN: &str = "https://statics.teams.cdn.office.net";

/// One of Teams' backgrounds.
#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub animated: bool,
    /// The background itself and its thumbnail (absolute URLs).
    pub src: String,
    pub thumb: String,
}

impl Entry {
    pub fn json(&self) -> serde_json::Value {
        serde_json::json!({ "id": self.id, "name": self.name, "animated": self.animated, "thumb": self.thumb })
    }
}

/// The catalog's entries from its JSON ({"videoBackgroundImages": [...]}).
pub fn parse_catalog(text: &str) -> Vec<Entry> {
    let v: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
    let abs = |p: &str| {
        if p.starts_with("http") {
            p.to_string()
        } else {
            format!("{CDN}{p}")
        }
    };
    v.get("videoBackgroundImages")
        .and_then(|a| a.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|e| {
                    let s = |k: &str| {
                        e.get(k)
                            .and_then(|x| x.as_str())
                            .unwrap_or_default()
                            .to_string()
                    };
                    let (id, src) = (s("id"), s("src"));
                    if id.is_empty() || src.is_empty() {
                        return None;
                    }
                    Some(Entry {
                        name: s("name"),
                        animated: s("filetype") == "mp4",
                        thumb: abs(&s("thumb_src")),
                        src: abs(&src),
                        id,
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn catalog_cell() -> &'static Mutex<Vec<Entry>> {
    static C: std::sync::OnceLock<Mutex<Vec<Entry>>> = std::sync::OnceLock::new();
    C.get_or_init(|| Mutex::new(Vec::new()))
}

/// The catalog as last loaded.
pub fn catalog() -> Vec<Entry> {
    catalog_cell().lock().unwrap().clone()
}

fn dir() -> PathBuf {
    crate::backend::cache_base().join("backgrounds")
}

/// Load the catalog: from Teams' CDN, or the copy kept from last time when
/// it can't be reached.
pub async fn load_catalog() -> Vec<Entry> {
    let cached = dir().join("animated.json");
    let fresh = async {
        let r = reqwest::get(CATALOG_URL).await?.error_for_status()?;
        anyhow::Ok(r.text().await?)
    }
    .await;
    let text = match fresh {
        Ok(t) if !parse_catalog(&t).is_empty() => {
            let _ = std::fs::create_dir_all(dir());
            let _ = std::fs::write(&cached, &t);
            t
        }
        other => {
            if let Err(e) = other {
                tracing::warn!("background catalog: {e:#}");
            }
            std::fs::read_to_string(&cached).unwrap_or_default()
        }
    };
    let list = parse_catalog(&text);
    *catalog_cell().lock().unwrap() = list.clone();
    list
}

/// Your own backgrounds (Teams desktop's Add new keeps them on the device:
/// `<uuid>.jpeg` and `<uuid>_thumb.jpeg`).
pub fn uploads_dir() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_else(std::env::temp_dir)
        .join("ost/backgrounds/uploads")
}

/// One of your own backgrounds: its id (Teams names it by its uuid) and
/// thumbnail.
#[derive(Clone, Debug, PartialEq)]
pub struct Upload {
    pub id: String,
    pub thumb: PathBuf,
}

/// Your backgrounds, oldest first.
pub fn uploads() -> Vec<Upload> {
    uploads_in(&uploads_dir())
}

fn uploads_in(dir: &Path) -> Vec<Upload> {
    let mut list: Vec<(std::time::SystemTime, Upload)> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            let id = name.strip_suffix(".jpeg")?;
            if id.ends_with("_thumb") || !is_upload_id(id) {
                return None;
            }
            let when = e
                .metadata()
                .and_then(|m| m.modified())
                .unwrap_or(std::time::UNIX_EPOCH);
            Some((
                when,
                Upload {
                    id: id.to_string(),
                    thumb: dir.join(format!("{id}_thumb.jpeg")),
                },
            ))
        })
        .collect();
    list.sort_by_key(|(when, _)| *when);
    list.into_iter().map(|(_, u)| u).collect()
}

/// A uuid (an upload's id), never a path.
pub fn is_upload_id(id: &str) -> bool {
    uuid::Uuid::parse_str(id).is_ok()
}

/// Why Add new turned a picture down (Teams' messages).
#[derive(Debug, PartialEq)]
pub enum AddError {
    InvalidType,
    InvalidSize,
    Failed,
}

impl AddError {
    pub fn message(&self) -> String {
        match self {
            AddError::InvalidType => {
                crate::backend::tr("Couldn't add background: Invalid image type.")
            }
            AddError::InvalidSize => {
                crate::backend::tr("Couldn't add background: Invalid image size.")
            }
            AddError::Failed => crate::backend::tr("Couldn't add background."),
        }
    }
}

unsafe extern "C" {
    fn ost_vfx_import_picture(
        src: *const core::ffi::c_char,
        dst: *const core::ffi::c_char,
        thumb: *const core::ffi::c_char,
    ) -> i32;
}

/// Add the picture at `src` as one of your backgrounds; its id.
pub fn add_upload(src: &Path) -> Result<String, AddError> {
    // Teams' file picker offers these; anything else isn't an image to it.
    let ext = src
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    if !["png", "jpeg", "jpg", "bmp"].contains(&ext.as_str()) {
        return Err(AddError::InvalidType);
    }
    let dir = uploads_dir();
    std::fs::create_dir_all(&dir).map_err(|_| AddError::Failed)?;
    let id = uuid::Uuid::new_v4().to_string();
    let c = |p: &Path| {
        std::ffi::CString::new(p.to_string_lossy().as_bytes()).map_err(|_| AddError::Failed)
    };
    let (s, d, t) = (
        c(src)?,
        c(&dir.join(format!("{id}.jpeg")))?,
        c(&dir.join(format!("{id}_thumb.jpeg")))?,
    );
    // SAFETY: NUL-terminated paths.
    match unsafe { ost_vfx_import_picture(s.as_ptr(), d.as_ptr(), t.as_ptr()) } {
        0 => Ok(id),
        1 => Err(AddError::InvalidType),
        2 => Err(AddError::InvalidSize),
        _ => {
            remove_upload(&id);
            Err(AddError::Failed)
        }
    }
}

/// Remove one of your backgrounds.
pub fn remove_upload(id: &str) -> bool {
    if !is_upload_id(id) {
        return false;
    }
    let dir = uploads_dir();
    let gone = std::fs::remove_file(dir.join(format!("{id}.jpeg"))).is_ok();
    let _ = std::fs::remove_file(dir.join(format!("{id}_thumb.jpeg")));
    gone
}

/// Where a background is kept once downloaded.
fn local_path(e: &Entry) -> PathBuf {
    let name = e
        .src
        .split('?')
        .next()
        .unwrap_or_default()
        .rsplit('/')
        .next()
        .unwrap_or("background")
        .to_string();
    dir().join(name)
}

async fn download(e: &Entry) -> anyhow::Result<PathBuf> {
    let path = local_path(e);
    if path.exists() {
        return Ok(path);
    }
    let bytes = reqwest::get(&e.src)
        .await?
        .error_for_status()?
        .bytes()
        .await?;
    std::fs::create_dir_all(dir())?;
    let tmp = path.with_extension("part");
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, &path)?;
    Ok(path)
}

unsafe extern "C" {
    fn ost_vfx_player_open(
        path: *const core::ffi::c_char,
        width: i32,
        height: i32,
    ) -> *mut core::ffi::c_void;
    fn ost_vfx_player_fps(player: *mut core::ffi::c_void) -> f64;
    fn ost_vfx_player_next(player: *mut core::ffi::c_void, out: *mut u8) -> bool;
    fn ost_vfx_player_close(player: *mut core::ffi::c_void);
}

/// A background being played at the camera's size.
struct Player(*mut core::ffi::c_void);

// The player is used by one thread at a time.
unsafe impl Send for Player {}

impl Player {
    fn open(path: &Path) -> Option<Self> {
        let c = std::ffi::CString::new(path.to_string_lossy().as_bytes()).ok()?;
        // SAFETY: a NUL-terminated path; null means it couldn't be opened.
        let p = unsafe { ost_vfx_player_open(c.as_ptr(), SEND_W as i32, SEND_H as i32) };
        (!p.is_null()).then_some(Self(p))
    }

    fn fps(&self) -> f64 {
        // SAFETY: an open player.
        unsafe { ost_vfx_player_fps(self.0) }
    }

    fn next(&mut self) -> Option<Picture> {
        let mut data = vec![0u8; (SEND_W * SEND_H * 3 / 2) as usize];
        // SAFETY: an open player; `data` holds one I420 frame of its size.
        unsafe { ost_vfx_player_next(self.0, data.as_mut_ptr()) }
            .then(|| Picture::from_i420(SEND_W, SEND_H, data))
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        // SAFETY: closed once.
        unsafe { ost_vfx_player_close(self.0) }
    }
}

/// Teams' Custom Filters video app (Frames and Styles).
pub const FILTERS_APP: &str = "73d49226-b5c0-42f0-b918-acd20e8a22d8";

/// One of the app's filters: Teams shows its name without the category
/// prefix ("Frames_Crystal" is "Crystal" under Frames).
#[derive(Clone, Debug, PartialEq)]
pub struct Filter {
    pub id: String,
    pub name: String,
    pub category: String,
    pub thumb: String,
}

/// The app's page and filters from its definition
/// (meetingExtensionDefinition: videoAppContentUrl, filters).
pub fn parse_filters(def: &serde_json::Value) -> (String, Vec<Filter>) {
    let m = &def["meetingExtensionDefinition"];
    let url = m["videoAppContentUrl"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    let list = m["filters"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|f| {
                    let full = f["name"].as_str()?;
                    let (category, name) = full.split_once('_').unwrap_or(("", full));
                    Some(Filter {
                        id: f["id"].as_str()?.to_string(),
                        name: name.to_string(),
                        category: category.to_string(),
                        thumb: f["thumbnail"].as_str().unwrap_or_default().to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    (url, list)
}

// The filter app's frames: its page (qml/VideoFilterHost.qml) connects to
// a WebSocket on 127.0.0.1 with a secret path; each camera frame goes to it
// as a binary message (a 16-byte header — u32 width, u32 height, u64
// sequence, little endian — then NV12) and comes back processed the same
// way, one at a time.

/// The page's address for the frames (`ws://127.0.0.1:<port>/<secret>`),
/// starting the server on first use.
pub fn filter_socket() -> String {
    static URL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    URL.get_or_init(|| {
        let secret = uuid::Uuid::new_v4().simple().to_string();
        let std_listener = match std::net::TcpListener::bind("127.0.0.1:0") {
            Ok(l) => l,
            Err(e) => {
                tracing::warn!("filter frames: {e}");
                return String::new();
            }
        };
        let port = std_listener.local_addr().map(|a| a.port()).unwrap_or(0);
        let _ = std_listener.set_nonblocking(true);
        let path = format!("/{secret}");
        crate::backend::runtime().spawn(async move {
            let Ok(listener) = tokio::net::TcpListener::from_std(std_listener) else {
                return;
            };
            while let Ok((stream, _)) = listener.accept().await {
                let path = path.clone();
                tokio::spawn(async move {
                    if let Err(e) = serve_filter_page(stream, &path).await {
                        tracing::debug!("filter frames: {e:#}");
                    }
                });
            }
        });
        format!("ws://127.0.0.1:{port}/{secret}")
    })
    .clone()
}

/// A frame as the page takes it.
pub fn encode_frame(f: &ost_vfx::filter::Frame) -> Vec<u8> {
    let mut out = Vec::with_capacity(16 + f.data.len());
    out.extend_from_slice(&f.width.to_le_bytes());
    out.extend_from_slice(&f.height.to_le_bytes());
    out.extend_from_slice(&f.seq.to_le_bytes());
    out.extend_from_slice(&f.data);
    out
}

/// A processed frame from the page.
pub fn decode_frame(b: &[u8]) -> Option<ost_vfx::filter::Frame> {
    if b.len() <= 16 {
        return None;
    }
    let width = u32::from_le_bytes(b[0..4].try_into().ok()?);
    let height = u32::from_le_bytes(b[4..8].try_into().ok()?);
    let seq = u64::from_le_bytes(b[8..16].try_into().ok()?);
    let data = b[16..].to_vec();
    (data.len() >= width as usize * height as usize * 3 / 2).then_some(ost_vfx::filter::Frame {
        width,
        height,
        seq,
        data,
    })
}

async fn serve_filter_page(stream: tokio::net::TcpStream, path: &str) -> anyhow::Result<()> {
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::{
        Message,
        handshake::server::{ErrorResponse, Request, Response},
    };
    // Only the page that was given the secret path.
    #[allow(
        clippy::result_large_err,
        reason = "tungstenite's handshake callback returns its own ErrorResponse"
    )]
    let check = |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        if req.uri().path() == path {
            Ok(resp)
        } else {
            Err(Response::builder().status(404).body(None).unwrap())
        }
    };
    let mut ws = tokio_tungstenite::accept_hdr_async(stream, check).await?;
    let mut after = 0u64;
    loop {
        let frame = tokio::task::spawn_blocking(move || {
            ost_vfx::filter::next_frame(after, Duration::from_millis(500))
        })
        .await?;
        let Some(frame) = frame else { continue };
        after = frame.seq;
        ws.send(Message::Binary(encode_frame(&frame).into()))
            .await?;
        // The app's result (or give up on this frame after a second).
        match tokio::time::timeout(Duration::from_secs(1), ws.next()).await {
            Ok(Some(Ok(Message::Binary(b)))) => {
                if let Some(f) = decode_frame(&b) {
                    ost_vfx::filter::put_processed(f);
                }
            }
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) => return Ok(()),
            Ok(Some(Err(e))) => return Err(e.into()),
            _ => {}
        }
    }
}

/// Each apply's number: a background still loading or playing stops when a
/// newer choice is made.
static GENERATION: AtomicU64 = AtomicU64::new(0);

fn flag(map: &serde_json::Map<String, serde_json::Value>, key: &str) -> bool {
    map.get(key).and_then(|v| v.as_str()) == Some("true")
}

/// "#RRGGBB" as RGB.
pub fn parse_hex(s: &str) -> Option<[u8; 3]> {
    let h = s.strip_prefix('#')?;
    if h.len() != 6 {
        return None;
    }
    let b = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).ok();
    Some([b(0)?, b(2)?, b(4)?])
}

pub fn hex(c: [u8; 3]) -> String {
    format!("#{:02X}{:02X}{:02X}", c[0], c[1], c[2])
}

/// The colour at (`fx`, `fy`) (0–1 across the picture) of the frame your
/// preview shows.
pub fn preview_colour_at(fx: f64, fy: f64) -> Option<[u8; 3]> {
    let f = teams_cli::calling::frames::latest("self")?;
    let (w, h) = (f.width as usize, f.height as usize);
    if w == 0 || h == 0 {
        return None;
    }
    let x = ((fx.clamp(0.0, 1.0) * (w - 1) as f64).round() as usize).min(w - 1);
    let y = ((fy.clamp(0.0, 1.0) * (h - 1) as f64).round() as usize).min(h - 1);
    let i = (y * w + x) * 4;
    f.rgba.get(i..i + 3).map(|p| [p[0], p[1], p[2]])
}

/// What background a setting value names.
#[derive(Debug, PartialEq)]
pub enum Choice {
    None,
    Blur(Blur),
    Catalog(String),
}

pub fn choice(map: &serde_json::Map<String, serde_json::Value>) -> Choice {
    let get = |k: &str| map.get(k).and_then(|v| v.as_str()).unwrap_or_default();
    match get("videoBackground") {
        "" | "none" => Choice::None,
        "blur" => Choice::Blur(if get("videoBlur") == "portrait" {
            Blur::Portrait
        } else {
            Blur::Standard
        }),
        id => Choice::Catalog(id.to_string()),
    }
}

/// Apply the effects chosen in `map`.
pub fn apply(map: &serde_json::Map<String, serde_json::Value>) {
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    let mut s = Settings {
        brightness: flag(map, "adjustBrightness"),
        soft_focus: flag(map, "softFocus"),
        green_screen: flag(map, "greenScreen").then(|| ost_vfx::GreenScreen {
            color: map
                .get("greenScreenColor")
                .and_then(|v| v.as_str())
                .and_then(parse_hex),
        }),
        background: ost_vfx::current().background,
    };
    match choice(map) {
        Choice::None => s.background = Background::None,
        Choice::Blur(kind) => s.background = Background::Blur(kind),
        Choice::Catalog(id) => {
            // The current background stays until the new one is ready.
            ost_vfx::set(s.clone());
            crate::backend::runtime().spawn(async move {
                if let Err(e) = load_background(&id, generation).await {
                    tracing::warn!("background {id}: {e:#}");
                }
            });
            return;
        }
    }
    ost_vfx::set(s);
}

async fn load_background(id: &str, generation: u64) -> anyhow::Result<()> {
    if is_upload_id(id) {
        let path = uploads_dir().join(format!("{id}.jpeg"));
        anyhow::ensure!(path.exists(), "removed");
        return tokio::task::spawn_blocking(move || play(&path, generation)).await?;
    }
    let mut list = catalog();
    if list.is_empty() {
        list = load_catalog().await;
    }
    let entry = list
        .into_iter()
        .find(|e| e.id == id)
        .ok_or_else(|| anyhow::anyhow!("not in Teams' catalog"))?;
    let path = download(&entry).await?;
    tokio::task::spawn_blocking(move || play(&path, generation)).await?
}

fn set_background(b: Background, generation: u64) -> bool {
    if GENERATION.load(Ordering::SeqCst) != generation {
        return false;
    }
    let mut s = ost_vfx::current();
    s.background = b;
    ost_vfx::set(s);
    true
}

/// Show the background at `path`: a picture once, an animation frame by
/// frame (resting while no camera uses it) until another is chosen.
fn play(path: &Path, generation: u64) -> anyhow::Result<()> {
    let mut player = Player::open(path).ok_or_else(|| anyhow::anyhow!("can't be played"))?;
    let fps = player.fps();
    let first = player
        .next()
        .ok_or_else(|| anyhow::anyhow!("has no picture"))?;
    if fps <= 0.0 {
        set_background(Background::Picture(Arc::new(first)), generation);
        return Ok(());
    }
    let anim = Animated::new();
    anim.set_frame(first);
    if !set_background(Background::Animated(anim.clone()), generation) {
        return Ok(());
    }
    let every = std::time::Duration::from_secs_f64(1.0 / fps.clamp(1.0, 30.0));
    let mut next = std::time::Instant::now() + every;
    while GENERATION.load(Ordering::SeqCst) == generation {
        if !anim.in_use() {
            std::thread::sleep(std::time::Duration::from_millis(200));
            next = std::time::Instant::now();
            continue;
        }
        let Some(frame) = player.next() else { break };
        anim.set_frame(frame);
        let now = std::time::Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        }
        next = next.max(now) + every;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_catalog_reads_as_teams_lists_it() {
        let list = parse_catalog(
            r#"{"videoBackgroundImages":[
            {"name":"Animated feeling dreamy 2","id":"Microsoft_feelingDreamy2Animated","filetype":"mp4",
             "src":"/evergreen-assets/backgroundimages/animated/feelingDreamy2Animated.mp4?v=0.1",
             "thumb_src":"/evergreen-assets/backgroundimages/animated/feelingDreamy2Animated_thumb.png?v=0.1"},
            {"name":"Gold shimmer holiday","id":"Microsoft_goldShimmerHoliday","filetype":"jpg",
             "src":"/evergreen-assets/backgroundimages/goldShimmerHoliday.jpg?v=0.1",
             "thumb_src":"/evergreen-assets/backgroundimages/goldShimmerHoliday_thumb.jpg?v=0.1"},
            {"name":"broken"}]}"#,
        );
        assert_eq!(list.len(), 2);
        assert!(list[0].animated && !list[1].animated);
        assert_eq!(
            list[1].src,
            "https://statics.teams.cdn.office.net/evergreen-assets/backgroundimages/goldShimmerHoliday.jpg?v=0.1"
        );
        assert_eq!(
            local_path(&list[1]).file_name().unwrap(),
            "goldShimmerHoliday.jpg"
        );
    }

    #[test]
    fn uploads_are_listed_by_their_uuid_oldest_first() {
        let dir = std::env::temp_dir().join(format!("ost-uploads-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let (a, b) = (
            "7dfbac61-4292-4c1a-b3ba-abf4ce314c8b",
            "0a1b2c3d-4292-4c1a-b3ba-abf4ce314c8b",
        );
        for name in [
            format!("{a}.jpeg"),
            format!("{a}_thumb.jpeg"),
            "notes.jpeg".into(),
            "x.png".into(),
        ] {
            std::fs::write(dir.join(name), b"x").unwrap();
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
        std::fs::write(dir.join(format!("{b}.jpeg")), b"x").unwrap();
        let list = uploads_in(&dir);
        assert_eq!(
            list.iter().map(|u| u.id.as_str()).collect::<Vec<_>>(),
            [a, b]
        );
        assert_eq!(list[0].thumb, dir.join(format!("{a}_thumb.jpeg")));
        std::fs::remove_dir_all(&dir).unwrap();
        assert!(!is_upload_id("../x"));
        assert_eq!(
            add_upload(Path::new("/tmp/a.gif")),
            Err(AddError::InvalidType)
        );
    }

    #[test]
    fn the_filters_app_lists_frames_and_styles() {
        let def = serde_json::json!({ "meetingExtensionDefinition": {
            "videoAppContentUrl": "https://res.cdn.office.net/midgard/1.latest/custom-filters/index.html",
            "filters": [
                { "id": "a0d54440-381e-4328-baf9-bf0323b4b39c", "name": "Styles_Sweet", "thumbnail": "https://x/s.png" },
                { "id": "f1adab11-0a32-46e1-ad15-347e699bb1bd", "name": "Frames_Crystal", "thumbnail": "https://x/c.png" },
                { "name": "broken" }
            ] } });
        let (url, list) = parse_filters(&def);
        assert!(url.ends_with("/custom-filters/index.html"));
        assert_eq!(list.len(), 2);
        assert_eq!(
            (list[0].category.as_str(), list[0].name.as_str()),
            ("Styles", "Sweet")
        );
        assert_eq!(
            (list[1].category.as_str(), list[1].name.as_str()),
            ("Frames", "Crystal")
        );
    }

    #[test]
    fn filter_frames_round_trip_through_the_wire_format() {
        let f = ost_vfx::filter::Frame {
            width: 4,
            height: 2,
            seq: 7,
            data: vec![1; 12],
        };
        let back = decode_frame(&encode_frame(&f)).unwrap();
        assert_eq!(
            (back.width, back.height, back.seq, back.data),
            (4, 2, 7, vec![1; 12])
        );
        assert!(decode_frame(&[0; 16]).is_none());
    }

    #[test]
    fn colours_read_and_write_as_teams_hex() {
        assert_eq!(parse_hex("#00B294"), Some([0, 0xB2, 0x94]));
        assert_eq!(parse_hex("00B294"), None);
        assert_eq!(hex([0, 0xB2, 0x94]), "#00B294");
    }

    #[test]
    fn settings_name_the_background() {
        let m = |pairs: &[(&str, &str)]| {
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), serde_json::Value::String(v.to_string())))
                .collect::<serde_json::Map<_, _>>()
        };
        assert_eq!(choice(&m(&[])), Choice::None);
        assert_eq!(
            choice(&m(&[("videoBackground", "blur")])),
            Choice::Blur(Blur::Standard)
        );
        assert_eq!(
            choice(&m(&[
                ("videoBackground", "blur"),
                ("videoBlur", "portrait")
            ])),
            Choice::Blur(Blur::Portrait)
        );
        assert_eq!(
            choice(&m(&[("videoBackground", "Microsoft_x")])),
            Choice::Catalog("Microsoft_x".into())
        );
    }
}
