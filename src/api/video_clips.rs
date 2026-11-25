//! Video clips in messages, as Teams plays them: the media store keeps the
//! clip's transcoded MP4 (`…/views/video`) and a DASH manifest
//! (`…/views/video.mpd`) whose renditions (720p, 480p, 360p) are Teams'
//! player's Quality choices. A rendition is its initialization segment
//! followed by its media segments, which joined make one playable MP4.

use anyhow::{Context, Result};

use super::client::TeamsClient;

/// One of a clip's renditions: its manifest id ("video_480p") and height.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Rendition {
    pub id: String,
    pub height: u32,
}

/// The renditions a manifest offers, tallest first, one per height (the
/// manifest's "video_cellular" repeats 360p).
pub fn renditions(mpd: &str) -> Vec<Rendition> {
    let mut out: Vec<Rendition> = Vec::new();
    let mut rest = mpd;
    while let Some(i) = rest.find("<Representation") {
        let end = rest[i..].find('>').map(|e| i + e).unwrap_or(rest.len());
        let tag = &rest[i..end];
        rest = &rest[end..];
        let id = xml_attr(tag, "id").unwrap_or_default();
        let height = xml_attr(tag, "height")
            .and_then(|h| h.parse().ok())
            .unwrap_or(0);
        if id.is_empty()
            || height == 0
            || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        {
            continue;
        }
        if !out.iter().any(|r| r.height == height) {
            out.push(Rendition { id, height });
        }
    }
    out.sort_by(|a, b| b.height.cmp(&a.height));
    out
}

/// How many media segments the manifest's timeline has (each `<S>` once,
/// plus its `r` repeats).
pub fn segment_count(mpd: &str) -> usize {
    let mut n = 0usize;
    let mut rest = mpd;
    while let Some(i) = rest.find("<S ") {
        let end = rest[i..].find('>').map(|e| i + e).unwrap_or(rest.len());
        let tag = &rest[i..end];
        rest = &rest[end..];
        n += 1 + xml_attr(tag, "r")
            .and_then(|r| r.parse::<usize>().ok())
            .unwrap_or(0);
    }
    n
}

fn xml_attr(tag: &str, name: &str) -> Option<String> {
    let key = format!(" {name}=\"");
    let i = tag.find(&key)? + key.len();
    let j = tag[i..].find('"')? + i;
    Some(tag[i..j].to_string())
}

/// The clip's manifest (`{clip}.mpd`, the clip's `…/views/video` address).
pub async fn manifest(client: &TeamsClient, clip_url: &str) -> Result<String> {
    anyhow::ensure!(
        super::messages::is_ams_url(clip_url),
        "Not a Teams media URL"
    );
    let bytes = client.ams_get(&format!("{clip_url}.mpd")).await?;
    String::from_utf8(bytes).context("Clip manifest")
}

/// The clip as one playable MP4: Teams' own MP4 (`rendition` None, the
/// player's Auto), or a rendition's segments joined.
pub async fn playable(
    client: &TeamsClient,
    clip_url: &str,
    rendition: Option<&str>,
    mpd: Option<&str>,
) -> Result<Vec<u8>> {
    anyhow::ensure!(
        super::messages::is_ams_url(clip_url),
        "Not a Teams media URL"
    );
    let Some(rep) = rendition else {
        return client.ams_get(clip_url).await;
    };
    anyhow::ensure!(
        rep.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'),
        "Bad rendition"
    );
    let owned;
    let mpd = match mpd {
        Some(m) => m,
        None => {
            owned = manifest(client, clip_url).await?;
            owned.as_str()
        }
    };
    let count = segment_count(mpd);
    anyhow::ensure!(count > 0 && count < 10_000, "Clip manifest has no segments");
    let base = clip_url
        .strip_suffix("/video")
        .context("Not a clip address")?;
    let mut out = Vec::new();
    for k in 0..=count {
        out.extend(
            client
                .ams_get(&format!("{base}/{rep}/videoSegment/{k}"))
                .await?,
        );
    }
    Ok(out)
}

/// A recorded clip as Teams' message carries it (captured on winpc,
/// 2026-11-14, OST TEST 135): an empty paragraph, then the AMSVideo element
/// with its card id, length (ISO 8601, ms precision) and size, the text
/// following it.
pub fn clip_html(
    ams_base: &str,
    id: &str,
    card_id: &str,
    duration_ms: u64,
    width: u32,
    height: u32,
) -> String {
    let secs = duration_ms as f64 / 1000.0;
    let mut dur = format!("{secs:.3}");
    while dur.contains('.') && (dur.ends_with('0') || dur.ends_with('.')) {
        dur.pop();
    }
    format!(
        "<p>&nbsp;</p><video src=\"{}/v1/objects/{id}/views/video\" cardId=\"{card_id}\" itemscope itemtype=\"http://schema.skype.com/AMSVideo\" data-duration=\"PT{dur}S\" width=\"{width}\" height=\"{height}\">Video-Clip</video>",
        ams_base.trim_end_matches('/')
    )
}

/// A new clip's card id (32 hex digits, as Teams' `cardId`).
pub fn new_card_id() -> String {
    uuid::Uuid::new_v4().simple().to_string()
}

/// Upload a recorded clip (its file and poster) for `conv`'s members and
/// return the media-store object id.
pub async fn upload(
    client: &TeamsClient,
    conv: &str,
    original: Vec<u8>,
    thumbnail: Vec<u8>,
) -> Result<String> {
    client.ams_upload_video(conv, original, thumbnail).await
}

/// One kept part of a recorded clip, in the order it plays.
#[derive(Debug, Clone, PartialEq, serde::Deserialize)]
pub struct Segment {
    /// The recording (a local file).
    pub path: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

/// Music under the clip (Teams' Music): a local copy of the track and its
/// level (0–1; Teams starts at 15 %). It loops for the clip's length.
#[derive(Debug, Clone, PartialEq, serde::Deserialize)]
pub struct Music {
    pub path: String,
    pub level: f64,
}

/// The recorder's music library (Teams' Music: Microsoft Stream's tracks on
/// Microsoft's public CDN): a track's file, fetched once.
pub const MUSIC_BASE: &str = "https://res.public.onecdn.static.microsoft/files/odsp-web-prod_2026-10-30.005/streamcameraembed/";

/// Fetch a track of the music library (only from it).
pub async fn fetch_music(url: &str) -> Result<Vec<u8>> {
    anyhow::ensure!(
        url.starts_with(MUSIC_BASE) && !url.contains(".."),
        "Not a music library address"
    );
    let resp = reqwest::get(url).await.context("Music download failed")?;
    anyhow::ensure!(
        resp.status().is_success(),
        "Music download failed ({})",
        resp.status()
    );
    Ok(resp.bytes().await.context("Music download")?.to_vec())
}

/// A path as a filter's option value inside a filter graph (FFmpeg's two
/// levels of escaping: the option's, then the graph's).
fn graph_path(path: &str) -> String {
    let mut opt = String::new();
    for c in path.chars() {
        if matches!(c, '\\' | '\'' | ':') {
            opt.push('\\');
        }
        opt.push(c);
    }
    let mut out = String::new();
    for c in opt.chars() {
        if matches!(c, '\\' | '\'' | '[' | ']' | ',' | ';' | '=') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

fn secs(ms: u64) -> String {
    format!("{}.{:03}", ms / 1000, ms % 1000)
}

/// The edit as an FFmpeg filter graph with outputs [v] and [a]: each part
/// cut from its recording and fitted to `width` x `height` (letterboxed),
/// 30 frames a second, the parts joined in order, and the music mixed in
/// at its level, looping, for as long as the clip.
pub fn edit_graph(segments: &[Segment], music: Option<&Music>, width: u32, height: u32) -> String {
    let mut parts: Vec<String> = Vec::new();
    for (i, s) in segments.iter().enumerate() {
        let (a, b) = (secs(s.start_ms), secs(s.end_ms.max(s.start_ms + 1)));
        parts.push(format!(
            "movie={p}:streams=dv+da[mv{i}][ma{i}];\
             [mv{i}]trim=start={a}:end={b},setpts=PTS-STARTPTS,scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v{i}];\
             [ma{i}]atrim=start={a}:end={b},asetpts=PTS-STARTPTS,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[a{i}]",
            p = graph_path(&s.path)
        ));
    }
    let n = segments.len();
    if n == 1 {
        parts.push("[v0]null[cv];[a0]anull[ca]".into());
    } else {
        let pads: String = (0..n).map(|i| format!("[v{i}][a{i}]")).collect();
        parts.push(format!("{pads}concat=n={n}:v=1:a=1[cv][ca]"));
    }
    parts.push("[cv]null[v]".into());
    match music {
        Some(m) => parts.push(format!(
            "amovie={p}:loop=0,volume={l:.2},aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[m];\
             [ca][m]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]",
            p = graph_path(&m.path),
            l = m.level.clamp(0.0, 1.0)
        )),
        None => parts.push("[ca]anull[a]".into()),
    }
    parts.join(";")
}

#[cfg(test)]
mod tests {
    use super::*;

    // OST TEST 135's manifest (recorded in Teams on winpc).
    const MPD: &str = r#"<MPD mediaPresentationDuration="PT0M12.2S" type="static"><Period><AdaptationSet id="0" contentType="video" mimeType="video/mp4">
      <SegmentTemplate initialization="$RepresentationID$/videoSegment/0" media="$RepresentationID$/videoSegment/$Number$" startNumber="1" timescale="15360">
        <SegmentTimeline><S d="76800" /><S d="76800" /><S d="34298" /></SegmentTimeline></SegmentTemplate>
      <Representation bandwidth="97715" codecs="avc1.4d401f" frameRate="30/1" height="720" id="video_original" mimeType="video/mp4" width="1280" />
      <Representation bandwidth="56769" codecs="avc1.4d401f" frameRate="30/1" height="480" id="video_480p" mimeType="video/mp4" width="853" />
      <Representation bandwidth="35768" codecs="avc1.4d401f" frameRate="30/1" height="360" id="video_360p" mimeType="video/mp4" width="640" />
      <Representation bandwidth="32379" codecs="avc1.4d401f" frameRate="30/1" height="360" id="video_cellular" mimeType="video/mp4" width="640" />
    </AdaptationSet></Period></MPD>"#;

    #[test]
    fn edits_render_as_one_clip() {
        let a = Segment {
            path: "/c/ost/recordings/r1.mp4".into(),
            start_ms: 1500,
            end_ms: 4000,
        };
        let b = Segment {
            path: "/c/ost/recordings/r2.mp4".into(),
            start_ms: 0,
            end_ms: 2250,
        };
        let g = edit_graph(std::slice::from_ref(&a), None, 1280, 720);
        assert!(g.starts_with("movie=/c/ost/recordings/r1.mp4:streams=dv+da[mv0][ma0];"));
        assert!(g.contains("[mv0]trim=start=1.500:end=4.000,setpts=PTS-STARTPTS,scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:"));
        assert!(g.contains("[ma0]atrim=start=1.500:end=4.000,asetpts=PTS-STARTPTS"));
        assert!(g.ends_with("[v0]null[cv];[a0]anull[ca];[cv]null[v];[ca]anull[a]"));
        let g2 = edit_graph(
            &[a, b],
            Some(&Music {
                path: "/c/m/in_a_dream.aac".into(),
                level: 0.15,
            }),
            1280,
            720,
        );
        assert!(g2.contains("[v0][a0][v1][a1]concat=n=2:v=1:a=1[cv][ca]"));
        assert!(g2.contains("amovie=/c/m/in_a_dream.aac:loop=0,volume=0.15,"));
        assert!(
            g2.ends_with("[ca][m]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]")
        );
        // Paths are escaped for the option and for the graph.
        assert_eq!(
            graph_path("/a b/x:y,z[1]'q"),
            "/a b/x\\\\:y\\,z\\[1\\]\\\\\\'q"
        );
    }

    #[test]
    fn a_recorded_clip_is_sent_as_teams_sends_it() {
        let h = clip_html(
            "https://us-api.asm.skype.com",
            "0-wus-d12-8635",
            "3fa840bc60ba4f07915f9df495c20daf",
            16309,
            1280,
            720,
        );
        assert_eq!(
            h,
            r#"<p>&nbsp;</p><video src="https://us-api.asm.skype.com/v1/objects/0-wus-d12-8635/views/video" cardId="3fa840bc60ba4f07915f9df495c20daf" itemscope itemtype="http://schema.skype.com/AMSVideo" data-duration="PT16.309S" width="1280" height="720">Video-Clip</video>"#
        );
        assert!(clip_html("https://x", "i", "c", 21000, 1, 1).contains("data-duration=\"PT21S\""));
    }

    #[test]
    fn a_clips_qualities_are_its_renditions() {
        let r = renditions(MPD);
        assert_eq!(
            r.iter()
                .map(|r| (r.id.as_str(), r.height))
                .collect::<Vec<_>>(),
            vec![
                ("video_original", 720),
                ("video_480p", 480),
                ("video_360p", 360)
            ]
        );
        assert_eq!(segment_count(MPD), 3);
        assert_eq!(segment_count(r#"<S d="1" r="4" /><S d="2" />"#), 6);
    }
}
