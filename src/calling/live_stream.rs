//! A town hall's stream for its attendees (docs/spec/town-halls-and-webinars.md §5).
//!
//! Teams' calling stack (pluginless `handleRosterParticipant`, read
//! 2026-11-18): an attendee joins the meeting like any other, but the
//! service never answers its call. Instead the roster lists our own
//! endpoint with a `stream` modality (or `streamLobby` before the event
//! starts) and Teams switches the call to streaming mode
//! (`configureStreamingMode`: call mode 2, the call connected, its media
//! and pending call setup dropped, call end subCode
//! DowngradeToStreamingClient). The picture and sound come from the
//! meeting's composition service, a bot participant whose endpoint carries
//! `streamInformation.streams[]`: per delivery pipeline (HLS
//! "MiddleLaneHttpLiveStreaming", "MiddleLaneUltraLowLatency" and the old
//! "AMS") a primary and an alternate stream with their URLs and keys.
//!
//! Teams picks the pipeline as its streaming player resolver does (`pn`):
//! ULL when the ECS `useULLPlayerWithILiveStreamForStreaming` says so (only
//! local builds), else HLS when `useHttpLiveStreamingPlayerForStreaming`
//! (on in prod), else AMS. The HLS player is Microsoft's web player in an
//! iframe; OST plays the same HLS stream natively.

use serde_json::Value;

/// One stream of the composition bot (Teams' `StreamDetail`).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StreamDetail {
    pub urls: Vec<String>,
    pub is_primary: bool,
    /// "MiddleLaneHttpLiveStreaming", "MiddleLaneUltraLowLatency", "AMS".
    pub delivery_pipeline_type: String,
    /// Where the player gets its key cookie (HLS and ULL).
    pub set_key_authorization_cookie_uri: String,
    pub key_authorization_token: String,
    /// The stream's own key (ULL, or the AMS decryption token's value).
    pub decryption_key_id: String,
    pub decryption_key_value: String,
    /// AMS's cookie address.
    pub set_cookie_url: String,
}

/// The stream Teams' resolver picks: the pipeline's primary stream and an
/// alternate one with other URLs.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StreamChoice {
    /// Teams' player type: "HttpLiveStreamingPlayer",
    /// "UltraLowLatencyPlayer" or "AzureMediaPlayer".
    pub player_type: String,
    pub stream: Option<StreamDetail>,
    pub alt_stream: Option<StreamDetail>,
}

impl StreamChoice {
    /// The URL to play first (primary, else the alternate).
    pub fn url(&self) -> Option<&str> {
        self.stream
            .iter()
            .chain(self.alt_stream.iter())
            .find_map(|s| s.urls.first().map(String::as_str))
    }

    /// The stream that `url` belongs to.
    pub fn detail_for(&self, url: &str) -> Option<&StreamDetail> {
        self.stream
            .iter()
            .chain(self.alt_stream.iter())
            .find(|s| s.urls.iter().any(|u| u == url))
    }
}

fn s(v: &Value, k: &str) -> String {
    v.get(k)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

/// The roster names the pipelines in words ("Middle Lane HLS Network");
/// Teams' calling service maps them to its player's names (`gV`), the
/// rest to AMS.
fn pipeline(roster_name: &str) -> &'static str {
    match roster_name {
        "Middle Lane HLS Network" | "MiddleLaneHttpLiveStreaming" => "MiddleLaneHttpLiveStreaming",
        "Middle Lane ULL Network" | "MiddleLaneUltraLowLatency" => "MiddleLaneUltraLowLatency",
        _ => "AMS",
    }
}

fn detail(v: &Value) -> StreamDetail {
    StreamDetail {
        urls: v
            .get("urls")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|u| u.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default(),
        is_primary: v.get("isPrimary").and_then(Value::as_bool).unwrap_or(false),
        delivery_pipeline_type: pipeline(&s(v, "deliveryPipelineType")).to_string(),
        set_key_authorization_cookie_uri: s(v, "setKeyAuthorizationCookieUri"),
        key_authorization_token: s(v, "keyAuthorizationToken"),
        decryption_key_id: v
            .pointer("/decryptionKey/id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        decryption_key_value: v
            .pointer("/decryptionKey/value")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        set_cookie_url: s(v, "setCookieUrl"),
    }
}

/// The participants of a roster update or a join response
/// (`body.participants` / `roster.participants`).
fn participants(json: &Value) -> Option<&serde_json::Map<String, Value>> {
    [
        "/body/participants",
        "/roster/participants",
        "/participants",
        "/conversationResponse/roster/participants",
    ]
    .iter()
    .find_map(|p| json.pointer(p)?.as_object())
}

/// Our own endpoint in streaming mode, as Teams reads the roster: Some(true)
/// in the stream's lobby (`streamLobby`, the event hasn't started), Some(false)
/// watching (`stream`), None when the roster doesn't put us there.
pub fn self_streaming(json: &Value, my_mri: &str, endpoint_id: &str) -> Option<bool> {
    let me = participants(json)?
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(my_mri))?
        .1;
    let ep = me
        .get("endpoints")?
        .as_object()?
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(endpoint_id))?
        .1;
    if ep.get("stream").is_some_and(|v| !v.is_null()) {
        Some(false)
    } else if ep.get("streamLobby").is_some_and(|v| !v.is_null()) {
        Some(true)
    } else {
        None
    }
}

/// Every stream the roster's stream providers offer (Teams'
/// getStreamInformationMap: endpoints with `streamInformation`, not ours).
pub fn streams(json: &Value, my_mri: &str) -> Option<Vec<StreamDetail>> {
    let mut out = Vec::new();
    let mut found = false;
    for (mri, p) in participants(json)? {
        if mri.eq_ignore_ascii_case(my_mri) {
            continue;
        }
        for ep in p
            .get("endpoints")
            .and_then(Value::as_object)
            .into_iter()
            .flat_map(|e| e.values())
        {
            if let Some(list) = ep
                .pointer("/streamInformation/streams")
                .and_then(Value::as_array)
            {
                found = true;
                out.extend(list.iter().map(detail));
            }
        }
    }
    found.then_some(out)
}

/// Teams' pick (`pn`, with prod's configuration unless ECS says otherwise).
pub fn choose(streams: &[StreamDetail], use_ull: bool, use_hls: bool) -> StreamChoice {
    let has = |t: &str| streams.iter().any(|s| s.delivery_pipeline_type == t);
    let (pipeline, player) = if has("MiddleLaneUltraLowLatency") && use_ull {
        ("MiddleLaneUltraLowLatency", "UltraLowLatencyPlayer")
    } else if has("MiddleLaneHttpLiveStreaming") && use_hls {
        ("MiddleLaneHttpLiveStreaming", "HttpLiveStreamingPlayer")
    } else {
        ("AMS", "AzureMediaPlayer")
    };
    let primary = streams
        .iter()
        .find(|s| s.is_primary && s.delivery_pipeline_type == pipeline)
        .cloned();
    let first_url = primary
        .as_ref()
        .and_then(|p| p.urls.first().cloned())
        .unwrap_or_default();
    // The alternate: the same pipeline with URLs, none of them the primary's.
    let alt = streams
        .iter()
        .find(|s| {
            s.delivery_pipeline_type == pipeline
                && !s.urls.is_empty()
                && !s.urls.contains(&first_url)
        })
        .cloned();
    StreamChoice {
        player_type: player.into(),
        stream: primary,
        alt_stream: alt,
    }
}

/// Teams' choice with ECS's Streaming settings (prod: HLS).
pub fn choose_as_teams(streams: &[StreamDetail]) -> StreamChoice {
    let flag = |k: &str, default: bool| {
        crate::api::ecs::setting("Streaming", k)
            .or_else(|| crate::api::ecs::setting("Broadcast", k))
            .and_then(|v| v.as_bool())
            .unwrap_or(default)
    };
    choose(
        streams,
        flag("useULLPlayerWithILiveStreamForStreaming", false),
        flag("useHttpLiveStreamingPlayerForStreaming", true),
    )
}

/// Rewrite an HLS playlist so every URI in it (media lines and `URI="…"`
/// attributes: variants, segments, keys, maps) goes through `register`,
/// resolved against the playlist's own address.
pub fn rewrite_playlist(
    body: &str,
    base: &url::Url,
    mut register: impl FnMut(String) -> String,
) -> String {
    let mut out = String::with_capacity(body.len() + 256);
    for line in body.lines() {
        let t = line.trim();
        if t.is_empty() {
            out.push('\n');
            continue;
        }
        if !t.starts_with('#') {
            let abs = base
                .join(t)
                .map(|u| u.to_string())
                .unwrap_or_else(|_| t.to_string());
            out.push_str(&register(abs));
            out.push('\n');
            continue;
        }
        // A tag: its URI="…" attribute, if any.
        if let Some(i) = t.find("URI=\"") {
            let start = i + 5;
            if let Some(len) = t[start..].find('"') {
                let uri = &t[start..start + len];
                let abs = base
                    .join(uri)
                    .map(|u| u.to_string())
                    .unwrap_or_else(|_| uri.to_string());
                out.push_str(&t[..start]);
                out.push_str(&register(abs));
                out.push_str(&t[start + len..]);
                out.push('\n');
                continue;
            }
        }
        out.push_str(t);
        out.push('\n');
    }
    out
}

/// A loopback HTTP server that hands the stream to OST's player (Qt
/// Multimedia's FFmpeg HLS demuxer): playlists are fetched and rewritten
/// so their variants, segments and keys come back through it; the key
/// requests carry the stream's `keyAuthorizationToken` as Teams' player
/// sends it.
pub struct StreamProxy {
    /// What the player opens.
    pub url: String,
    stop: Option<tokio::sync::oneshot::Sender<()>>,
}

impl Drop for StreamProxy {
    fn drop(&mut self) {
        if let Some(s) = self.stop.take() {
            let _ = s.send(());
        }
    }
}

/// What the proxy adds to its upstream requests.
enum ProxyAuth {
    /// A town hall's stream: its `keyAuthorizationToken` on key requests.
    Key(String),
    /// A file's HLS stream in SharePoint or OneDrive (an audio recap's
    /// chapters): the site's own token on every request, which only goes
    /// to that site.
    Site(String),
}

struct ProxyState {
    http: reqwest::Client,
    urls: std::sync::Mutex<Vec<String>>,
    auth: ProxyAuth,
    /// The playlists served so far (a file's stream starts from its first
    /// segment, see [`from_the_start`]).
    served: std::sync::Mutex<std::collections::HashSet<String>>,
}

/// Teams plays a recap chapter's growing playlist from its start (hls.js
/// `startPosition: 0`); FFmpeg starts a live playlist (no `#EXT-X-ENDLIST`)
/// three segments from its end. The first time such a playlist is served
/// only its first segment is listed, so FFmpeg starts there and takes the
/// rest at its next reload.
fn from_the_start(playlist: &str) -> String {
    if playlist.contains("#EXT-X-ENDLIST") {
        return playlist.to_string();
    }
    let mut out = String::with_capacity(playlist.len());
    for line in playlist.lines() {
        out.push_str(line);
        out.push('\n');
        if !line.trim().is_empty() && !line.starts_with('#') {
            break;
        }
    }
    out
}

impl ProxyState {
    fn register(&self, u: String, prefix: &str) -> String {
        self.register_as(u, prefix, None)
    }

    /// Register an address served under `ext` instead of its own (a
    /// segment whose address names no media type).
    fn register_as(&self, u: String, prefix: &str, ext: Option<&str>) -> String {
        let mut urls = self.urls.lock().expect("proxy urls");
        let i = urls.iter().position(|x| *x == u).unwrap_or_else(|| {
            urls.push(u);
            urls.len() - 1
        });
        format!(
            "{prefix}/{i}.{}",
            ext.unwrap_or_else(|| extension_of(&urls[i]))
        )
    }
}

/// Extensions FFmpeg's HLS demuxer opens segments by (its
/// allowed_segment_extensions, the media ones).
const MEDIA_EXTENSIONS: &[&str] = &[
    "3gp", "aac", "ac3", "avi", "ec3", "flac", "m4a", "m4s", "m4v", "mkv", "mov", "mp2", "mp3",
    "mp4", "mpeg", "mpg", "oga", "ogg", "ogv", "opus", "ts", "wav", "webm",
];

/// A segment's media type from its first bytes: MPEG-TS, fragmented MP4,
/// ADTS AAC (also after an ID3 timestamp, HLS packed audio) or MP3.
fn sniff_extension(head: &[u8]) -> Option<&'static str> {
    if head.first() == Some(&0x47) {
        return Some("ts");
    }
    if head.len() >= 8 && matches!(&head[4..8], b"ftyp" | b"styp" | b"moof" | b"sidx" | b"moov") {
        return Some("m4s");
    }
    let mut at = 0;
    if head.starts_with(b"ID3") && head.len() >= 10 {
        let size = head[6..10]
            .iter()
            .fold(0usize, |n, b| (n << 7) | (*b as usize & 0x7f));
        at = 10 + size;
    }
    match (head.get(at), head.get(at + 1)) {
        (Some(0xFF), Some(b)) if b & 0xF6 == 0xF0 => Some("aac"),
        (Some(0xFF), Some(b)) if b & 0xE0 == 0xE0 => Some("mp3"),
        _ => None,
    }
}

/// A key request (the playlists' `EXT-X-KEY` URI): Teams' Hydra player
/// fetches it from the key delivery service (`…keys.ml.teams.microsoft.com/
/// v3/hlskeydelivery/{stream}/get-key/…`) with the stream's
/// `keyAuthorizationToken` as the bare `Authorization` header (measured in
/// Teams desktop as a town hall attendee, 2026-11-18); segments and
/// playlists go without.
fn is_key_request(url: &str) -> bool {
    // The key token goes to Teams' own services over https only, never to
    // a host a (proxied, rewritten) playlist names.
    if !crate::auth::token_hosts::allowed(url, crate::auth::token_hosts::Audience::Teams) {
        return false;
    }
    url::Url::parse(url).is_ok_and(|u| {
        u.path().contains("/get-key/") || u.host_str().is_some_and(|h| h.contains(".keys."))
    })
}

impl StreamProxy {
    /// Serve the chosen stream; None when it has no URL.
    pub async fn start(choice: &StreamChoice) -> anyhow::Result<Self> {
        let first = choice
            .url()
            .ok_or_else(|| anyhow::anyhow!("The stream has no address"))?
            .to_string();
        let detail = choice.detail_for(&first).cloned().unwrap_or_default();
        Self::serve(first, ProxyAuth::Key(detail.key_authorization_token)).await
    }

    /// Serve a file's HLS stream from SharePoint or OneDrive (`https://
    /// {tenant}[-my].sharepoint.com/…/streams/…m3u8/content`, an audio
    /// recap chapter's audio), each request with the site's token as Teams'
    /// HLS loader sends it.
    pub async fn site(url: &str) -> anyhow::Result<Self> {
        let host = site_host(url).ok_or_else(|| anyhow::anyhow!("Not a file address"))?;
        Self::serve(url.to_string(), ProxyAuth::Site(host)).await
    }

    async fn serve(first: String, auth: ProxyAuth) -> anyhow::Result<Self> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let port = listener.local_addr()?.port();
        let secret = uuid::Uuid::new_v4().simple().to_string();
        let prefix = format!("http://127.0.0.1:{port}/{secret}");
        let state = std::sync::Arc::new(ProxyState {
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(20))
                .build()?,
            urls: std::sync::Mutex::new(Vec::new()),
            auth,
            served: Default::default(),
        });
        let url = state.register(first, &prefix);
        let (stop, mut stopped) = tokio::sync::oneshot::channel();
        let path_prefix = format!("/{secret}/");
        tokio::spawn(async move {
            loop {
                let (mut sock, _) = tokio::select! {
                    a = listener.accept() => match a { Ok(a) => a, Err(_) => break },
                    _ = &mut stopped => break,
                };
                let (state, prefix, path_prefix) =
                    (state.clone(), prefix.clone(), path_prefix.clone());
                tokio::spawn(async move {
                    // One request per connection is enough for FFmpeg.
                    let mut buf = vec![0u8; 8192];
                    let mut n = 0;
                    while n < buf.len() {
                        match sock.read(&mut buf[n..]).await {
                            Ok(0) | Err(_) => return,
                            Ok(k) => n += k,
                        }
                        if buf[..n].windows(4).any(|w| w == b"\r\n\r\n") {
                            break;
                        }
                    }
                    let req = String::from_utf8_lossy(&buf[..n]).to_string();
                    let path = req
                        .split_whitespace()
                        .nth(1)
                        .unwrap_or_default()
                        .to_string();
                    let idx = path
                        .strip_prefix(&path_prefix)
                        .and_then(|r| r.split('.').next())
                        .and_then(|i| i.parse::<usize>().ok());
                    let upstream = idx.and_then(|i| state.urls.lock().ok()?.get(i).cloned());
                    let reply = match upstream {
                        Some(u) => fetch(&state, &u, &prefix).await,
                        None => Err(anyhow::anyhow!("not found")),
                    };
                    let resp = match reply {
                        Ok((ctype, body)) => {
                            let mut r = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                body.len()
                            )
                            .into_bytes();
                            r.extend_from_slice(&body);
                            r
                        }
                        Err(e) => {
                            tracing::debug!("stream proxy: {path}: {e:#}");
                            b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_vec()
                        }
                    };
                    let _ = sock.write_all(&resp).await;
                    let _ = sock.shutdown().await;
                });
            }
        });
        Ok(Self {
            url,
            stop: Some(stop),
        })
    }
}

/// The extension a proxied address keeps (the demuxer goes by it for
/// playlists, and FFmpeg's HLS only opens segments with media extensions):
/// the last path part's, or for a SharePoint stream (`…/streams/
/// seg1.ts/content`) the part before `content`.
fn extension_of(url: &str) -> &str {
    url.split(['?', '#'])
        .next()
        .unwrap_or_default()
        .rsplit('/')
        .take(2)
        .find_map(|part| part.rsplit_once('.').map(|(_, e)| e))
        .filter(|e| !e.is_empty() && e.len() <= 5 && e.chars().all(|c| c.is_ascii_alphanumeric()))
        .unwrap_or("bin")
}

/// The SharePoint host of an https file address.
fn site_host(url: &str) -> Option<String> {
    let u = url::Url::parse(url).ok()?;
    let host = u.host_str()?.to_ascii_lowercase();
    (u.scheme() == "https" && host.ends_with(".sharepoint.com")).then_some(host)
}

async fn fetch(
    state: &ProxyState,
    upstream: &str,
    prefix: &str,
) -> anyhow::Result<(String, Vec<u8>)> {
    let mut req = state.http.get(upstream);
    match &state.auth {
        ProxyAuth::Key(token) if is_key_request(upstream) && !token.is_empty() => {
            req = req.header(reqwest::header::AUTHORIZATION, token);
        }
        ProxyAuth::Site(host) => {
            // The token goes to its own site only.
            anyhow::ensure!(
                site_host(upstream).as_deref() == Some(host.as_str()),
                "Not the file's site"
            );
            let token =
                crate::auth::oauth::access_token_for(&format!("https://{host}/.default")).await?;
            req = req.bearer_auth(token);
        }
        _ => {}
    }
    let r = req.send().await?;
    let status = r.status();
    anyhow::ensure!(status.is_success(), "HTTP {status}");
    let ctype = r
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/octet-stream")
        .to_string();
    let body = r.bytes().await?.to_vec();
    let is_playlist = ctype.contains("mpegurl")
        || upstream
            .split('?')
            .next()
            .is_some_and(|p| p.ends_with(".m3u8"))
        || body.starts_with(b"#EXTM3U");
    if is_playlist {
        let base = url::Url::parse(upstream)?;
        let mut text = String::from_utf8_lossy(&body).to_string();
        if matches!(state.auth, ProxyAuth::Site(_))
            && state
                .served
                .lock()
                .map(|mut s| s.insert(upstream.to_string()))
                .unwrap_or(false)
        {
            text = from_the_start(&text);
        }
        // What the stream is made of (its tags, addresses left out).
        let tags: Vec<String> = text
            .lines()
            .filter(|l| {
                l.starts_with("#EXT-X-KEY")
                    || l.starts_with("#EXT-X-STREAM-INF")
                    || l.starts_with("#EXT-X-MEDIA:")
                    || l.starts_with("#EXT-X-MAP")
            })
            .map(|l| {
                l.split(",URI=")
                    .next()
                    .unwrap_or_default()
                    .split("URI=")
                    .next()
                    .unwrap_or_default()
                    .chars()
                    .take(160)
                    .collect()
            })
            .take(6)
            .collect();
        tracing::debug!(?tags, "stream proxy: playlist");
        if matches!(state.auth, ProxyAuth::Site(_)) {
            let segments = text
                .lines()
                .filter(|l| !l.trim().is_empty() && !l.starts_with('#'))
                .count();
            // (A segment's last path parts show its kind; no query.)
            let first: String = text
                .lines()
                .find(|l| !l.trim().is_empty() && !l.starts_with('#'))
                .map(|l| {
                    l.split('?')
                        .next()
                        .unwrap_or_default()
                        .rsplit('/')
                        .take(2)
                        .collect::<Vec<_>>()
                        .join(" < ")
                })
                .unwrap_or_default()
                .chars()
                .take(120)
                .collect();
            tracing::info!(segments, ended = text.contains("#EXT-X-ENDLIST"), kind = text.lines().find(|l| l.starts_with("#EXT-X-PLAYLIST-TYPE")).unwrap_or(""), map = text.contains("#EXT-X-MAP"), %first, "recap audio: playlist");
        }
        // A SharePoint stream's segments (`…/streams/x.0.0000/content`)
        // name no media type, which FFmpeg's HLS won't open: they're served
        // under the type their first bytes show.
        let mut seg_ext: Option<&str> = None;
        if matches!(state.auth, ProxyAuth::Site(_))
            && let Some(first) = text
                .lines()
                .map(str::trim)
                .find(|l| !l.is_empty() && !l.starts_with('#'))
            && let Ok(abs) = base.join(first)
            && !MEDIA_EXTENSIONS.contains(&extension_of(abs.as_str()))
        {
            let head = Box::pin(fetch(state, abs.as_str(), prefix))
                .await
                .map(|(_, b)| b)
                .unwrap_or_default();
            seg_ext = sniff_extension(&head[..head.len().min(4096)]);
            tracing::info!(ext = seg_ext.unwrap_or(""), "recap audio: segment type");
        }
        let out = rewrite_playlist(&text, &base, |u| {
            let own = extension_of(&u);
            let ext = seg_ext.filter(|_| own != "m3u8" && !MEDIA_EXTENSIONS.contains(&own));
            state.register_as(u, prefix, ext)
        });
        return Ok(("application/vnd.apple.mpegurl".into(), out.into_bytes()));
    }
    Ok((ctype, body))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn site_tokens_stay_on_their_site() {
        assert_eq!(site_host("https://t-my.sharepoint.com/personal/u/_api/v2.1/drives/b/items/i/versions/current/streams/a.m3u8/content").as_deref(), Some("t-my.sharepoint.com"));
        assert_eq!(site_host("http://t-my.sharepoint.com/x"), None);
        assert_eq!(site_host("https://evil.example/x.sharepoint.com"), None);
    }

    #[test]
    fn key_tokens_go_only_to_teams_key_service() {
        assert!(is_key_request(
            "https://euno.keys.ml.teams.microsoft.com/v3/hlskeydelivery/s/get-key/k1"
        ));
        assert!(is_key_request(
            "https://x.teams.microsoft.com/v3/hlskeydelivery/s/get-key/k1"
        ));
        // Another host, even one that names the key path or a `.keys.` label.
        assert!(!is_key_request("https://evil.example/get-key/k1"));
        assert!(!is_key_request("https://a.keys.evil.example/k1"));
        assert!(!is_key_request(
            "https://evil.example/x?u=https://a.keys.ml.teams.microsoft.com/get-key/"
        ));
        assert!(!is_key_request(
            "https://keys.ml.teams.microsoft.com.evil.example/get-key/k1"
        ));
        // Not https, or not a key address.
        assert!(!is_key_request(
            "http://euno.keys.ml.teams.microsoft.com/v3/hlskeydelivery/s/get-key/k1"
        ));
        assert!(!is_key_request(
            "https://x.teams.microsoft.com/hls/seg-1.ts"
        ));
    }

    #[test]
    fn growing_playlists_start_at_their_first_segment() {
        let live = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:10,\na/content\n#EXTINF:10,\nb/content\n#EXTINF:10,\nc/content\n#EXTINF:10,\nd/content\n";
        assert_eq!(
            from_the_start(live),
            "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:10,\na/content\n"
        );
        let done = format!("{live}#EXT-X-ENDLIST\n");
        assert_eq!(from_the_start(&done), done);
    }

    #[test]
    fn segment_types_from_their_bytes() {
        assert_eq!(sniff_extension(&[0x47, 0x40, 0x11]), Some("ts"));
        assert_eq!(sniff_extension(b"\0\0\0\x18ftypiso6"), Some("m4s"));
        assert_eq!(sniff_extension(&[0xFF, 0xF1, 0x50]), Some("aac"));
        let mut id3 = b"ID3\x04\0\0\0\0\0\x02xx".to_vec();
        id3.extend([0xFF, 0xF9, 0x50]);
        assert_eq!(sniff_extension(&id3), Some("aac"));
        assert_eq!(sniff_extension(&[0xFF, 0xFB, 0x90]), Some("mp3"));
        assert_eq!(sniff_extension(b"<html>"), None);
    }

    #[test]
    fn proxied_addresses_keep_their_extension() {
        assert_eq!(extension_of("https://cdn/live/abc/seg-1.ts?tok=1"), "ts");
        assert_eq!(
            extension_of(
                "https://t-my.sharepoint.com/_api/v2.1/drives/b/items/i/versions/current/streams/x.m3u8/content"
            ),
            "m3u8"
        );
        assert_eq!(
            extension_of(
                "https://t-my.sharepoint.com/_api/v2.1/drives/b/items/i/versions/current/streams/seg1.aac/content?a=1"
            ),
            "aac"
        );
        assert_eq!(extension_of("https://keys.example/k/1"), "bin");
    }

    #[test]
    fn playlists_come_back_through_the_proxy() {
        let base = url::Url::parse("https://cdn.example/live/abc/master.m3u8?tok=1").unwrap();
        let mut seen = Vec::new();
        let out = rewrite_playlist(
            "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://keys.example/k/1\",IV=0x1\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv1/index.m3u8\nseg-1.ts\n",
            &base,
            |u| {
                seen.push(u);
                format!("L{}", seen.len())
            },
        );
        assert_eq!(
            seen,
            vec![
                "https://keys.example/k/1",
                "https://cdn.example/live/abc/v1/index.m3u8",
                "https://cdn.example/live/abc/seg-1.ts"
            ]
        );
        assert!(out.contains("URI=\"L1\",IV=0x1"));
        assert!(out.contains("\nL2\nL3\n"));
    }

    fn roster() -> Value {
        json!({"callAgentPath": "conversation/rosterUpdate/", "body": {"participants": {
            "8:orgid:me": {"endpoints": {"EP": {"participantId": "p1", "streamLobby": {"serverMuted": true}}}},
            "28:e32c9418-a835-4eb1-bfb9-733fa74dd6e8": {"endpoints": {"bot": {"participantId": "p2", "streamInformation": {"streams": [
                {"urls": ["https://a/hls/master.m3u8"], "isPrimary": true, "deliveryPipelineType": "Middle Lane HLS Network",
                 "setKeyAuthorizationCookieUri": "https://k/set", "keyAuthorizationToken": "t"},
                {"urls": ["https://b/hls/master.m3u8"], "isPrimary": false, "deliveryPipelineType": "Middle Lane HLS Network"},
                {"urls": ["wss://u/ull"], "isPrimary": true, "deliveryPipelineType": "Middle Lane ULL Network",
                 "decryptionKey": {"id": "k1", "value": "v1"}}
            ]}}}}
        }}})
    }

    #[test]
    fn reads_our_streaming_endpoint() {
        let r = roster();
        assert_eq!(self_streaming(&r, "8:orgid:ME", "ep"), Some(true));
        let mut live = r.clone();
        live["body"]["participants"]["8:orgid:me"]["endpoints"]["EP"] = json!({"stream": {}});
        assert_eq!(self_streaming(&live, "8:orgid:me", "EP"), Some(false));
        live["body"]["participants"]["8:orgid:me"]["endpoints"]["EP"] = json!({"call": {}});
        assert_eq!(self_streaming(&live, "8:orgid:me", "EP"), None);
    }

    #[test]
    fn picks_the_stream_as_teams() {
        let all = streams(&roster(), "8:orgid:me").unwrap();
        assert_eq!(all.len(), 3);
        let c = choose(&all, false, true);
        assert_eq!(c.player_type, "HttpLiveStreamingPlayer");
        assert_eq!(c.url(), Some("https://a/hls/master.m3u8"));
        assert_eq!(
            c.alt_stream.as_ref().unwrap().urls[0],
            "https://b/hls/master.m3u8"
        );
        assert_eq!(
            c.detail_for("https://a/hls/master.m3u8")
                .unwrap()
                .key_authorization_token,
            "t"
        );
        let u = choose(&all, true, true);
        assert_eq!(u.player_type, "UltraLowLatencyPlayer");
        assert_eq!(u.stream.unwrap().decryption_key_value, "v1");
        assert!(
            streams(
                &json!({"body": {"participants": {"8:orgid:me": {}}}}),
                "8:orgid:me"
            )
            .is_none()
        );
    }
}
