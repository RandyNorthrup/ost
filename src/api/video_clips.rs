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
        let height = xml_attr(tag, "height").and_then(|h| h.parse().ok()).unwrap_or(0);
        if id.is_empty() || height == 0 || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
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
        n += 1 + xml_attr(tag, "r").and_then(|r| r.parse::<usize>().ok()).unwrap_or(0);
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
    anyhow::ensure!(super::messages::is_ams_url(clip_url), "Not a Teams media URL");
    let bytes = client.ams_get(&format!("{clip_url}.mpd")).await?;
    String::from_utf8(bytes).context("Clip manifest")
}

/// The clip as one playable MP4: Teams' own MP4 (`rendition` None, the
/// player's Auto), or a rendition's segments joined.
pub async fn playable(client: &TeamsClient, clip_url: &str, rendition: Option<&str>, mpd: Option<&str>) -> Result<Vec<u8>> {
    anyhow::ensure!(super::messages::is_ams_url(clip_url), "Not a Teams media URL");
    let Some(rep) = rendition else {
        return client.ams_get(clip_url).await;
    };
    anyhow::ensure!(rep.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'), "Bad rendition");
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
    let base = clip_url.strip_suffix("/video").context("Not a clip address")?;
    let mut out = Vec::new();
    for k in 0..=count {
        out.extend(client.ams_get(&format!("{base}/{rep}/videoSegment/{k}")).await?);
    }
    Ok(out)
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
    fn a_clips_qualities_are_its_renditions() {
        let r = renditions(MPD);
        assert_eq!(r.iter().map(|r| (r.id.as_str(), r.height)).collect::<Vec<_>>(), vec![("video_original", 720), ("video_480p", 480), ("video_360p", 360)]);
        assert_eq!(segment_count(MPD), 3);
        assert_eq!(segment_count(r#"<S d="1" r="4" /><S d="2" />"#), 6);
    }
}
