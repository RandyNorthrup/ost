//! Audio with WebRTC peers: ICE (controlled) + DTLS-SRTP + PCMU on one
//! bundled UDP socket.
//!
//! Teams web (and other WebRTC clients) offer media secured with DTLS-SRTP
//! (`a=fingerprint`, `a=setup:actpass`) and no SDES `a=crypto` lines. We
//! answer `a=setup:active`, run the DTLS handshake as the client once ICE has
//! found the peer, and derive the SRTP keys from the handshake (RFC 5764).
//!
//! One task owns the socket's receive side and demultiplexes by first byte
//! (RFC 7983): STUN (0-3) is answered or matched, DTLS (20-63) feeds the
//! handshake, RTP/RTCP (128-191) is decrypted and played.

use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use openssl::asn1::Asn1Time;
use openssl::bn::{BigNum, MsbOption};
use openssl::ec::{EcGroup, EcKey};
use openssl::hash::MessageDigest;
use openssl::nid::Nid;
use openssl::pkey::{PKey, Private};
use openssl::ssl::{HandshakeError, SslContext, SslMethod, SslVerifyMode};
use openssl::x509::{X509, X509NameBuilder};
use tokio::net::UdpSocket;
use tokio::sync::{Mutex, mpsc};

use super::{ice, rtp, srtp};

#[cfg(feature = "audio")]
use super::audio;

/// RTP payload type for PCMU.
const PT_PCMU: u8 = 0;
/// Our H.264 payload type when we offer video.
const PT_H264_OFFER: u8 = 107;
/// What a meeting asks of a stream we send: (its stream id, its layers
/// as `vdclc` writes them).
#[cfg(feature = "video")]
type VideoControl = dyn Fn(i64, &[String]) + Send + Sync;

/// The H.264 payload type we offer for screen sharing (its own, so the
/// two video streams can be told apart).
const PT_H264_SHARE_OFFER: u8 = 102;
/// The mids of the camera and sharing lines in our offers.
const VIDEO_MID: &str = "1";
const SHARE_MID: &str = "2";
/// Our payload type for DTMF (RFC 4733 telephone-event/8000) when we offer.
const PT_DTMF_DEFAULT: u8 = 101;
/// How long one dial-pad tone lasts, in 20 ms packets (160 ms).
const DTMF_PACKETS: u32 = 8;
/// SRTP profile negotiated in the DTLS `use_srtp` extension.
const SRTP_PROFILE: &str = "SRTP_AES128_CM_SHA1_80";
/// Bytes exported for SRTP: two 16-byte keys and two 14-byte salts.
const SRTP_KEYING_LEN: usize = 2 * (16 + 14);
/// How long ICE may take to find the peer.
const ICE_TIMEOUT: Duration = Duration::from_secs(15);
/// How long the DTLS handshake may take once the peer is known.
const DTLS_TIMEOUT: Duration = Duration::from_secs(10);
/// STUN consent / keep-alive period (RFC 7675 asks for <= 5 s on average).
const CONSENT_INTERVAL: Duration = Duration::from_secs(4);

/// A self-signed DTLS certificate and its SDP fingerprint.
pub struct DtlsIdentity {
    cert: X509,
    key: PKey<Private>,
    /// `sha-256 AA:BB:...` for `a=fingerprint:`.
    pub fingerprint: String,
}

impl DtlsIdentity {
    /// A fresh P-256 certificate, valid for 30 days, as WebRTC endpoints use.
    pub fn generate() -> Result<Self> {
        let group = EcGroup::from_curve_name(Nid::X9_62_PRIME256V1)?;
        let key = PKey::from_ec_key(EcKey::generate(&group)?)?;
        let mut name = X509NameBuilder::new()?;
        name.append_entry_by_nid(Nid::COMMONNAME, "OST")?;
        let name = name.build();
        let mut serial = BigNum::new()?;
        serial.rand(64, MsbOption::MAYBE_ZERO, false)?;
        let mut b = X509::builder()?;
        b.set_version(2)?;
        let serial = serial.to_asn1_integer()?;
        b.set_serial_number(&serial)?;
        b.set_subject_name(&name)?;
        b.set_issuer_name(&name)?;
        b.set_pubkey(&key)?;
        let not_before = Asn1Time::days_from_now(0)?;
        b.set_not_before(&not_before)?;
        let not_after = Asn1Time::days_from_now(30)?;
        b.set_not_after(&not_after)?;
        b.sign(&key, MessageDigest::sha256())?;
        let cert = b.build();
        let digest = cert.digest(MessageDigest::sha256())?;
        let hex: Vec<String> = digest.iter().map(|b| format!("{b:02X}")).collect();
        Ok(Self {
            cert,
            key,
            fingerprint: format!("sha-256 {}", hex.join(":")),
        })
    }
}

/// What the offer tells us about the peer's WebRTC audio.
#[derive(Debug, Clone)]
pub struct WebRtcOffer {
    pub ice_ufrag: String,
    pub ice_pwd: String,
    /// `a=fingerprint` value, e.g. `sha-256 91:15:...`.
    pub fingerprint: String,
    pub candidates: Vec<ice::IceCandidate>,
    /// `a=mid` of every m-line, in order, with its media kind and formats.
    pub sections: Vec<(String, String, String)>,
    /// mid of the audio m-line.
    pub audio_mid: String,
    /// The peer's `a=setup` role: `actpass`, `active` or `passive`.
    pub setup: String,
    /// The main video m-line, if offered: its mid, the H.264 payload type
    /// we can decode (packetization mode 1, baseline profile) and the
    /// peer's video SSRC.
    pub video: Option<OfferedVideo>,
    /// The peer's telephone-event/8000 payload type (dial-pad tones).
    pub dtmf_pt: Option<u8>,
    /// The screen-sharing video line, if offered (even inactive).
    pub sharing: Option<OfferedVideo>,
    /// A media processor's answer to a meeting offer: our receive slots.
    pub slots: Vec<super::meeting_media::Slot>,
    /// … and its stream id for our data line, when it took it.
    pub data_stream: Option<i64>,
    /// … and the screen-sharing line, as a slot.
    pub share_slot: Option<super::meeting_media::Slot>,
    /// … and its stream id for our camera line.
    pub camera_stream: Option<i64>,
}

/// The payload type of `telephone-event/8000` in an audio section.
fn dtmf_payload_type(audio: &str) -> Option<u8> {
    audio.lines().find_map(|l| {
        let rest = l.trim_end().strip_prefix("a=rtpmap:")?;
        let (pt, codec) = rest.split_once(' ')?;
        codec
            .eq_ignore_ascii_case("telephone-event/8000")
            .then(|| pt.parse().ok())
            .flatten()
    })
}

/// The direction attribute of one SDP section (sendrecv when absent).
fn section_direction(section: &str) -> &'static str {
    for l in section.lines().map(str::trim_end) {
        match l {
            "a=sendrecv" => return "sendrecv",
            "a=sendonly" => return "sendonly",
            "a=recvonly" => return "recvonly",
            "a=inactive" => return "inactive",
            _ => {}
        }
    }
    "sendrecv"
}

/// The sections of an SDP (from each "m=" line), with their mids.
fn sections(sdp: &str) -> Vec<(Option<String>, String)> {
    let mut out: Vec<(Option<String>, String)> = Vec::new();
    for l in sdp.split_inclusive('\n') {
        if l.starts_with("m=") {
            out.push((None, String::new()));
        }
        if let Some((mid, body)) = out.last_mut() {
            if let Some(m) = l.trim_end().strip_prefix("a=mid:") {
                *mid = Some(m.to_string());
            }
            body.push_str(l);
        }
    }
    out
}

/// Whether a re-offer puts us on hold: its audio neither sends nor is
/// active (`sendonly` or `inactive`, RFC 3264 8.4).
pub fn offer_holds(offer: &str) -> bool {
    sections(offer)
        .iter()
        .find(|(_, b)| b.starts_with("m=audio"))
        .is_some_and(|(_, b)| matches!(section_direction(b), "sendonly" | "inactive"))
}

/// Answer a re-offer (hold, resume, a camera turned on, a media processor
/// adding streams) from our earlier SDP, following the new offer's m-lines
/// one for one (RFC 3264 8): a section we already carry keeps our
/// transport and codecs, with its direction mirroring the offer's and our
/// established DTLS role (`setup`: "active" or "passive"); any other
/// section is rejected with port 0. BUNDLE lists what we accept, and the
/// session version is bumped.
pub fn reanswer(ours: &str, offer: &str, version: u64, setup: &str) -> String {
    let mine = sections(ours);
    let mut head = String::new();
    let head_end = ours.find("\nm=").map(|i| i + 1).unwrap_or(ours.len());
    for l in ours[..head_end].split_inclusive('\n') {
        if l.starts_with("a=group:BUNDLE") {
            head.push_str("{BUNDLE}");
            continue;
        }
        match l.strip_prefix("o=") {
            Some(o) => {
                let mut f: Vec<&str> = o.trim_end().split(' ').collect();
                let v = version.to_string();
                if f.len() > 2 {
                    f[2] = &v;
                }
                head.push_str("o=");
                head.push_str(&f.join(" "));
                head.push_str("\r\n");
            }
            None => head.push_str(l),
        }
    }
    let mut body = String::new();
    let mut bundle: Vec<String> = Vec::new();
    for (mid, theirs) in sections(offer) {
        let m_line = theirs.lines().next().unwrap_or_default();
        let mut parts = m_line.trim_start_matches("m=").split_whitespace();
        let kind = parts.next().unwrap_or("audio");
        let _port = parts.next();
        let proto = parts.next().unwrap_or("RTP/SAVP");
        let fmt = parts.next().unwrap_or("0");
        let kept = mid.as_ref().and_then(|m| {
            mine.iter().find(|(om, ob)| {
                om.as_ref() == Some(m)
                    && ob.starts_with(&format!("m={kind} "))
                    && ob.split_whitespace().nth(1) != Some("0")
            })
        });
        let peer_rejected = m_line.split_whitespace().nth(1) == Some("0");
        match kept.filter(|_| !peer_rejected) {
            Some((m, ob)) => {
                let dir = match section_direction(&theirs) {
                    "sendonly" => "recvonly",
                    "recvonly" => "sendonly",
                    "inactive" => "inactive",
                    _ => "sendrecv",
                };
                for l in ob.split_inclusive('\n') {
                    let t = l.trim_end();
                    if matches!(t, "a=sendrecv" | "a=sendonly" | "a=recvonly" | "a=inactive") {
                        body.push_str(&format!("a={dir}\r\n"));
                    } else if t.starts_with("a=setup:") {
                        body.push_str(&format!("a=setup:{setup}\r\n"));
                    } else {
                        body.push_str(l);
                    }
                }
                if let Some(m) = m {
                    bundle.push(m.clone());
                }
            }
            None => {
                body.push_str(&format!("m={kind} 0 {proto} {fmt}\r\n"));
                body.push_str("c=IN IP4 0.0.0.0\r\n");
                if let Some(m) = &mid {
                    body.push_str(&format!("a=mid:{m}\r\n"));
                }
                body.push_str("a=inactive\r\n");
            }
        }
    }
    let group = if bundle.is_empty() {
        String::new()
    } else {
        format!("a=group:BUNDLE {}\r\n", bundle.join(" "))
    };
    head.replace("{BUNDLE}", &group) + &body
}

/// The RFC 4733 event code of a dial-pad key.
pub fn dtmf_event(key: char) -> Option<u8> {
    match key {
        '0'..='9' => Some(key as u8 - b'0'),
        '*' => Some(10),
        '#' => Some(11),
        'A'..='D' => Some(12 + (key as u8 - b'A')),
        _ => None,
    }
}

/// A telephone-event payload (RFC 4733 2.3): event, E bit + volume, duration.
fn dtmf_payload(event: u8, end: bool, duration: u16) -> [u8; 4] {
    let d = duration.to_be_bytes();
    // Volume 10 (-10 dBm0), as phones send.
    [event, if end { 0x80 } else { 0 } | 10, d[0], d[1]]
}

/// The peer's main video stream as offered.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OfferedVideo {
    pub mid: String,
    pub payload_type: u8,
    /// That payload type's profile-level-id (echoed in our answer, so the
    /// formats match).
    pub profile: String,
    pub ssrc: Option<u32>,
    /// The peer sends video (`sendrecv` or `sendonly`).
    pub sends: bool,
    /// The peer takes video (`sendrecv` or `recvonly`): we may send ours.
    pub receives: bool,
}

impl OfferedVideo {
    /// Our answer's direction, mirroring theirs (RFC 3264 6.1).
    fn answer_direction(&self) -> &'static str {
        match (self.sends, self.receives) {
            (true, true) => "sendrecv",
            (true, false) => "recvonly",
            (false, true) => "sendonly",
            (false, false) => "inactive",
        }
    }
}

/// The m-line section of `sdp` whose `a=mid` is `mid`.
fn section_with_mid<'a>(sdp: &'a str, mid: &str) -> Option<&'a str> {
    let mut start = None;
    let mut found = false;
    let mut offset = 0;
    for line in sdp.split_inclusive('\n') {
        if line.starts_with("m=") {
            if found {
                return Some(&sdp[start?..offset]);
            }
            start = Some(offset);
        } else if start.is_some() && line.trim_end() == format!("a=mid:{mid}") {
            found = true;
        }
        offset += line.len();
    }
    found.then(|| &sdp[start.unwrap_or(0)..])
}

/// The main video stream of an offer: the first video m-line labelled
/// main-video (else the first video m-line that isn't screen sharing),
/// with an H.264 format we decode. Constrained baseline (42e0..) is
/// preferred, then baseline. An inactive main video line is no video.
fn offered_video(sdp: &str, sections: &[(String, String, String)]) -> Option<OfferedVideo> {
    let candidates: Vec<&(String, String, String)> =
        sections.iter().filter(|s| s.1 == "video").collect();
    let labelled = |s: &&&(String, String, String), label: &str| {
        section_with_mid(sdp, &s.0).is_some_and(|t| t.contains(&format!("a=label:{label}")))
    };
    let main = candidates
        .iter()
        .find(|s| labelled(s, "main-video"))
        .or_else(|| {
            candidates
                .iter()
                .find(|s| !labelled(s, "applicationsharing-video"))
        })?;
    video_line(sdp, &main.0, None).filter(|v| v.sends || v.receives)
}

/// The screen-sharing video line of an offer (labelled
/// applicationsharing-video), kept even while inactive so a later
/// re-offer can turn it on. Its H.264 payload type differs from the main
/// video's where the offer allows, so the two streams can be told apart.
fn offered_sharing(
    sdp: &str,
    sections: &[(String, String, String)],
    main_pt: Option<u8>,
) -> Option<OfferedVideo> {
    let mid = sections.iter().filter(|s| s.1 == "video").find(|s| {
        section_with_mid(sdp, &s.0).is_some_and(|t| t.contains("a=label:applicationsharing-video"))
    })?;
    video_line(sdp, &mid.0, main_pt)
}

/// One video m-line: its H.264 payload type (not `avoid` when another
/// will do), the peer's SSRC and the direction.
fn video_line(sdp: &str, mid: &str, avoid: Option<u8>) -> Option<OfferedVideo> {
    let text = section_with_mid(sdp, mid)?;
    let h264: Vec<u8> = text
        .lines()
        .filter_map(|l| l.trim_end().strip_prefix("a=rtpmap:"))
        .filter_map(|r| {
            let (pt, codec) = r.split_once(' ')?;
            codec
                .to_ascii_uppercase()
                .starts_with("H264/")
                .then(|| pt.parse().ok())?
        })
        .collect();
    let fmtp = |pt: u8| {
        text.lines()
            .find_map(|l| {
                l.trim_end()
                    .strip_prefix(&format!("a=fmtp:{pt} "))
                    .map(str::to_string)
            })
            .unwrap_or_default()
            .to_ascii_lowercase()
    };
    let usable = |pt: &u8, profile: &str| {
        let f = fmtp(*pt);
        f.contains("packetization-mode=1") && f.contains(&format!("profile-level-id={profile}"))
    };
    // Constrained Baseline (42e0…, or 42c0… as media processors write
    // it), then Baseline.
    let ranked: Vec<u8> = h264
        .iter()
        .filter(|pt| usable(pt, "42e0") || usable(pt, "42c0"))
        .chain(h264.iter().filter(|pt| usable(pt, "4200")))
        .copied()
        .collect();
    let payload_type = ranked
        .iter()
        .find(|pt| Some(**pt) != avoid)
        .or(ranked.first())
        .copied()?;
    let ssrc = text
        .lines()
        .find_map(|l| l.trim_end().strip_prefix("a=ssrc-group:FID "))
        .and_then(|g| g.split_whitespace().next()?.parse().ok())
        .or_else(|| {
            text.lines()
                .find_map(|l| l.trim_end().strip_prefix("a=ssrc:"))
                .and_then(|r| r.split_whitespace().next()?.parse().ok())
        });
    let dir = section_direction(text);
    let profile = fmtp(payload_type)
        .split(';')
        .find_map(|p| p.trim().strip_prefix("profile-level-id="))
        .unwrap_or("42e01f")
        .to_string();
    Some(OfferedVideo {
        mid: mid.to_string(),
        payload_type,
        profile,
        ssrc,
        sends: matches!(dir, "sendrecv" | "sendonly"),
        receives: matches!(dir, "sendrecv" | "recvonly"),
    })
}

/// Our re-offer: our current SDP with each `(mid, direction)` in `lines`
/// set, and the session version set to `version`. A line the current SDP
/// has turned down (port 0, its mid gone, as after an audio-only answer)
/// comes back whole from `base`, the description that first had it.
pub fn media_offer(ours: &str, base: &str, lines: &[(&str, &str)], version: u64) -> String {
    let mut restored = ours.to_string();
    for (mid, _) in lines {
        restored = restore_section(&restored, base, mid);
    }
    let ours = restored.as_str();
    let head_end = ours.find("\nm=").map(|i| i + 1).unwrap_or(ours.len());
    let mut out = String::new();
    for l in ours[..head_end].split_inclusive('\n') {
        match l.strip_prefix("o=") {
            Some(o) => {
                let mut f: Vec<&str> = o.trim_end().split(' ').collect();
                let v = version.to_string();
                if f.len() > 2 {
                    f[2] = &v;
                }
                out.push_str("o=");
                out.push_str(&f.join(" "));
                out.push_str("\r\n");
            }
            None => out.push_str(l),
        }
    }
    for (m, text) in sections(ours) {
        let dir = lines
            .iter()
            .find(|(mid, _)| m.as_deref() == Some(*mid))
            .map(|(_, d)| *d);
        let Some(dir) = dir else {
            out.push_str(&text);
            continue;
        };
        for l in text.split_inclusive('\n') {
            if matches!(
                l.trim_end(),
                "a=sendrecv" | "a=sendonly" | "a=recvonly" | "a=inactive"
            ) {
                out.push_str(&format!("a={dir}\r\n"));
            } else {
                out.push_str(l);
            }
        }
    }
    // An offer leaves the DTLS role to the answerer (RFC 8842), as Teams'
    // own re-offers do; with the transport unchanged it keeps its role.
    out.split_inclusive('\n')
        .map(|l| {
            if l.starts_with("a=setup:") {
                "a=setup:actpass\r\n"
            } else {
                l
            }
        })
        .collect()
}

/// `ours` with the m-section at the position `base` has `mid` at put back
/// from `base` when it was turned down.
fn restore_section(ours: &str, base: &str, mid: &str) -> String {
    let base_sections = sections(base);
    let Some(k) = base_sections
        .iter()
        .position(|(m, _)| m.as_deref() == Some(mid))
    else {
        return ours.to_string();
    };
    let current = sections(ours);
    let rejected = current.get(k).is_some_and(|(m, t)| {
        m.as_deref() != Some(mid) || t.split_whitespace().nth(1) == Some("0")
    });
    if !rejected {
        return ours.to_string();
    }
    let head_end = ours.find("\nm=").map(|i| i + 1).unwrap_or(ours.len());
    let mut out = ours[..head_end].to_string();
    for (i, (_, text)) in current.iter().enumerate() {
        out.push_str(if i == k { &base_sections[k].1 } else { text });
    }
    // The restored line is bundled again.
    let mids: Vec<String> = sections(&out)
        .iter()
        .filter(|(_, t)| t.split_whitespace().nth(1) != Some("0"))
        .filter_map(|(m, _)| m.clone())
        .collect();
    out.split_inclusive('\n')
        .map(|l| {
            if l.starts_with("a=group:BUNDLE") {
                format!("a=group:BUNDLE {}\r\n", mids.join(" "))
            } else {
                l.to_string()
            }
        })
        .collect()
}

/// Whether an answer receives what we send on line `mid` (not rejected,
/// and receiving).
pub fn answer_receives(answer: &str, mid: &str) -> bool {
    sections(answer).iter().any(|(m, text)| {
        m.as_deref() == Some(mid)
            && text.split_whitespace().nth(1) != Some("0")
            && matches!(section_direction(text), "recvonly" | "sendrecv")
    })
}

/// Whether an offer's screen-sharing line is sending (someone presents).
pub fn offer_shares(offer: &str) -> bool {
    WebRtcOffer::parse(offer)
        .and_then(|o| o.sharing)
        .is_some_and(|v| v.sends)
}

/// What a re-offer of ours changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reoffer {
    /// Our camera on (the video line sends) or off (it only receives).
    Camera(bool),
    /// Our screen on (the sharing line sends) or off.
    Share(bool),
}

impl Reoffer {
    /// (camera, screen) sending after this change.
    fn apply(self, (camera, share): (bool, bool)) -> (bool, bool) {
        match self {
            Reoffer::Camera(on) => (on, share),
            Reoffer::Share(on) => (camera, on),
        }
    }
}

/// What differs between our video m-lines.
struct VideoLine<'a> {
    mid: &'a str,
    /// DTLS role: actpass in our offers, active in our answers.
    setup: &'a str,
    pt: u8,
    /// H.264 profile-level-id for `pt`: the offer's in an answer.
    profile: &'a str,
    direction: &'a str,
    /// main-video or applicationsharing-video.
    label: &'a str,
    ssrc: u32,
}

impl WebRtcOffer {
    /// Parse an offer that uses DTLS-SRTP; `None` for SDES offers.
    pub fn parse(sdp: &str) -> Option<Self> {
        let line = |prefix: &str| {
            sdp.lines()
                .find_map(|l| l.trim_end().strip_prefix(prefix).map(str::to_string))
        };
        let fingerprint = line("a=fingerprint:")?;
        let mut sections = Vec::new();
        let mut current: Option<(String, String)> = None;
        for l in sdp.lines().map(str::trim_end) {
            if let Some(m) = l.strip_prefix("m=") {
                let mut parts = m.split_whitespace();
                let kind = parts.next().unwrap_or_default().to_string();
                let rest: Vec<&str> = parts.collect();
                // m=<kind> <port> <proto> <fmt...>
                let proto_and_fmts = rest.get(1..).map(|r| r.join(" ")).unwrap_or_default();
                current = Some((kind, proto_and_fmts));
            } else if let Some(mid) = l.strip_prefix("a=mid:")
                && let Some((kind, fmts)) = current.take()
            {
                sections.push((mid.to_string(), kind, fmts));
            }
        }
        let audio_mid = sections.iter().find(|s| s.1 == "audio")?.0.clone();
        let audio = audio_section(sdp)?;
        let candidates = ice::parse_candidates_from_sdp_section(sdp, "audio");
        let in_audio = |prefix: &str| {
            audio
                .lines()
                .find_map(|l| l.trim_end().strip_prefix(prefix).map(str::to_string))
                .or_else(|| line(prefix))
        };
        Some(Self {
            ice_ufrag: in_audio("a=ice-ufrag:")?,
            ice_pwd: in_audio("a=ice-pwd:")?,
            fingerprint,
            candidates,
            video: offered_video(sdp, &sections),
            sharing: {
                let main_pt = offered_video(sdp, &sections).map(|v| v.payload_type);
                offered_sharing(sdp, &sections, main_pt)
            },
            dtmf_pt: dtmf_payload_type(&audio),
            slots: super::meeting_media::answered_slots(sdp),
            data_stream: super::meeting_media::data_stream(sdp),
            share_slot: super::meeting_media::answered_share(sdp),
            camera_stream: super::meeting_media::stream_id(sdp, super::meeting_media::CAMERA_MID),
            sections,
            audio_mid,
            setup: in_audio("a=setup:").unwrap_or_else(|| "actpass".into()),
        })
    }

    /// Whether the peer offered PCMU, the codec we send.
    pub fn offers_pcmu(&self, sdp: &str) -> bool {
        audio_section(sdp)
            .and_then(|a| a.lines().next().map(str::to_string))
            .is_some_and(|m| m.split_whitespace().skip(3).any(|f| f == "0"))
    }
}

fn audio_section(sdp: &str) -> Option<String> {
    let start = sdp.find("m=audio")?;
    let rest = &sdp[start..];
    let end = rest[1..].find("\nm=").map(|i| i + 1).unwrap_or(rest.len());
    Some(rest[..end].to_string())
}

/// Our side of the answer.
pub struct LocalAudio {
    pub socket: Arc<UdpSocket>,
    pub ufrag: String,
    pub pwd: String,
    pub ssrc: u32,
    pub candidates: Vec<ice::IceCandidate>,
    pub identity: DtlsIdentity,
    /// Our video SSRC (used for RTCP feedback even before we send video).
    pub video_ssrc: u32,
    /// Our screen-sharing SSRC.
    pub share_ssrc: u32,
    /// The answer accepted the peer's video: receive and show it.
    pub receive_video: bool,
    /// Our camera starts on: our video line sends from the start (else it
    /// only receives until a re-offer turns the camera on, as Teams does).
    pub camera_on: bool,
    /// The telephone-event payload type to put in our SDP (the peer's when
    /// answering, ours when offering); None leaves DTMF out.
    pub dtmf_pt: Option<u8>,
    /// A meeting or group call: our offer has receive slots and a data
    /// line, and others' video comes through the media control plane.
    pub meeting: bool,
}

impl LocalAudio {
    /// Bind the media socket and gather host and server-reflexive candidates.
    pub async fn prepare() -> Result<Self> {
        let socket = UdpSocket::bind("0.0.0.0:0")
            .await
            .context("Bind media socket")?;
        let port = socket.local_addr()?.port();
        let local_ip = super::sdp::get_local_ip();
        let mut candidates = vec![ice::IceCandidate {
            foundation: "1".into(),
            component: 1,
            transport: ice::Transport::Udp,
            priority: 2130706431,
            address: local_ip,
            port,
            candidate_type: ice::CandidateType::Host,
            raddr: None,
            rport: None,
        }];
        if let Some(srflx) = ice::gather_srflx_candidate(&socket, ice::DEFAULT_STUN_SERVER).await {
            candidates.push(srflx);
        }
        Ok(Self {
            socket: Arc::new(socket),
            ufrag: super::sdp::generate_ice_ufrag(),
            pwd: super::sdp::generate_ice_pwd(),
            ssrc: super::video::generate_ssrc(),
            candidates,
            identity: DtlsIdentity::generate()?,
            video_ssrc: super::video::generate_ssrc(),
            share_ssrc: super::video::generate_ssrc(),
            receive_video: false,
            camera_on: false,
            dtmf_pt: Some(PT_DTMF_DEFAULT),
            meeting: false,
        })
    }

    /// An audio-only offer (PCMU, DTLS actpass) for placing a call.
    pub fn offer_sdp(&self) -> String {
        let port = self.socket.local_addr().map(|a| a.port()).unwrap_or(9);
        let addr = self.public_address();
        let session_id = u64::from(self.ssrc) << 16 | 1;
        let mut s = String::new();
        s.push_str("v=0\r\n");
        s.push_str(&format!("o=- {session_id} 2 IN IP4 127.0.0.1\r\n"));
        s.push_str("s=-\r\nt=0 0\r\n");
        s.push_str("a=group:BUNDLE 0\r\n");
        s.push_str("a=msid-semantic: WMS ost\r\n");
        s.push_str(&self.audio_section(port, &addr, "0", "actpass", self.dtmf_pt));
        s
    }

    /// An offer with audio and H.264 video (sendrecv), bundled, for a 1:1
    /// call: the callee's camera shows when they turn it on, and ours can
    /// go on and off without renegotiating.
    pub fn offer_sdp_with_video(&self) -> String {
        let port = self.socket.local_addr().map(|a| a.port()).unwrap_or(9);
        let addr = self.public_address();
        let session_id = u64::from(self.ssrc) << 16 | 1;
        let mut s = String::new();
        s.push_str("v=0\r\n");
        s.push_str(&format!("o=- {session_id} 2 IN IP4 127.0.0.1\r\n"));
        s.push_str("s=-\r\nt=0 0\r\n");
        s.push_str("a=group:BUNDLE 0 1 2\r\n");
        s.push_str("a=msid-semantic: WMS ost\r\n");
        s.push_str(&self.audio_section(port, &addr, "0", "actpass", self.dtmf_pt));
        s.push_str(&self.video_section(
            port,
            &addr,
            VideoLine {
                mid: VIDEO_MID,
                setup: "actpass",
                pt: PT_H264_OFFER,
                profile: "42e01f",
                direction: if self.camera_on {
                    "sendrecv"
                } else {
                    "recvonly"
                },
                label: "main-video",
                ssrc: self.video_ssrc,
            },
        ));
        // Screen sharing, off until one side re-offers it (as Teams'
        // own offers have it).
        s.push_str(&self.video_section(
            port,
            &addr,
            VideoLine {
                mid: SHARE_MID,
                setup: "actpass",
                pt: PT_H264_SHARE_OFFER,
                profile: "42e01f",
                direction: "inactive",
                label: "applicationsharing-video",
                ssrc: self.share_ssrc,
            },
        ));
        s
    }

    /// A meeting or group call offer, as Teams makes it: audio, our camera
    /// line, receive slots for others' video, screen sharing, and the
    /// data line the media control plane runs on.
    pub fn offer_sdp_meeting(&self) -> String {
        use super::meeting_media as mm;
        let port = self.socket.local_addr().map(|a| a.port()).unwrap_or(9);
        let addr = self.public_address();
        let session_id = u64::from(self.ssrc) << 16 | 1;
        let mids: Vec<String> = std::iter::once(mm::CAMERA_MID.to_string())
            .chain(mm::slot_mids())
            .chain([mm::SHARE_MID.to_string(), mm::DATA_MID.to_string()])
            .collect();
        let mut s = String::new();
        s.push_str("v=0\r\n");
        s.push_str(&format!("o=- {session_id} 2 IN IP4 127.0.0.1\r\n"));
        s.push_str("s=-\r\nt=0 0\r\n");
        s.push_str(&format!("a=group:BUNDLE 0 {}\r\n", mids.join(" ")));
        s.push_str("a=msid-semantic: WMS ost\r\n");
        s.push_str(&self.audio_section(port, &addr, "0", "actpass", self.dtmf_pt));
        s.push_str(&self.video_section(
            port,
            &addr,
            VideoLine {
                mid: mm::CAMERA_MID,
                setup: "actpass",
                pt: PT_H264_OFFER,
                profile: "42e01f",
                // Teams offers its camera and sharing lines sendrecv and
                // turns them on and off with media descriptions, not
                // re-offers (a line described sending must be sendrecv).
                direction: "sendrecv",
                label: "main-video",
                ssrc: self.video_ssrc,
            },
        ));
        for mid in mm::slot_mids() {
            // Receive only: Teams writes these with the SSRC range 1-1.
            s.push_str(&self.video_section(
                port,
                &addr,
                VideoLine {
                    mid: &mid,
                    setup: "actpass",
                    pt: PT_H264_OFFER,
                    profile: "42e01f",
                    direction: "recvonly",
                    label: "main-video",
                    ssrc: 1,
                },
            ));
        }
        s.push_str(&self.video_section(
            port,
            &addr,
            VideoLine {
                mid: mm::SHARE_MID,
                setup: "actpass",
                pt: PT_H264_SHARE_OFFER,
                profile: "42e01f",
                // Receiving whoever presents, and sending when we do.
                direction: "sendrecv",
                label: "applicationsharing-video",
                ssrc: self.share_ssrc,
            },
        ));
        s.push_str(&mm::data_section(
            port,
            &addr,
            &self.ufrag,
            &self.pwd,
            &self.identity.fingerprint,
            self.ssrc.wrapping_add(1),
        ));
        s
    }

    fn public_address(&self) -> String {
        self.candidates
            .iter()
            .find(|c| c.candidate_type == ice::CandidateType::ServerReflexive)
            .or(self.candidates.first())
            .map(|c| c.address.clone())
            .unwrap_or_else(|| "0.0.0.0".into())
    }

    /// One of our video m-lines (camera or screen sharing): H.264 with
    /// keyframe requests.
    fn video_section(&self, port: u16, addr: &str, line: VideoLine<'_>) -> String {
        let VideoLine {
            mid,
            setup,
            pt,
            profile,
            direction,
            label,
            ssrc,
        } = line;
        let mut s = String::new();
        s.push_str(&format!("m=video {port} RTP/SAVP {pt}\r\n"));
        s.push_str(&format!("c=IN IP4 {addr}\r\n"));
        s.push_str(&format!("a=ice-ufrag:{}\r\n", self.ufrag));
        s.push_str(&format!("a=ice-pwd:{}\r\n", self.pwd));
        s.push_str(&format!("a=fingerprint:{}\r\n", self.identity.fingerprint));
        s.push_str(&format!("a=setup:{setup}\r\n"));
        s.push_str(&format!("a=mid:{mid}\r\n"));
        // Mirroring their direction; sending (when they take video) is
        // agreed up front so the camera can go on and off without
        // renegotiating.
        s.push_str(&format!("a={direction}\r\n"));
        s.push_str("a=rtcp-mux\r\n");
        s.push_str(&format!("a=rtpmap:{pt} H264/90000\r\n"));
        s.push_str(&format!(
            "a=fmtp:{pt} level-asymmetry-allowed=1;packetization-mode=1;profile-level-id={profile}\r\n"
        ));
        s.push_str("a=x-signaling-fb:* x-message app send:src recv:src,vc\r\n");
        if self.meeting {
            s.push_str(&format!(
                "a=extmap:{} {}\r\n",
                super::twcc::EXTENSION_ID,
                super::twcc::EXTENSION_URI
            ));
            s.push_str("a=rtcp-fb:* transport-cc\r\n");
        }
        s.push_str("a=rtcp-rsize\r\n");
        s.push_str(&format!("a=rtcp-fb:{pt} nack pli\r\n"));
        s.push_str(&format!("a=rtcp-fb:{pt} ccm fir\r\n"));
        s.push_str(&format!("a=label:{label}\r\n"));
        // Only the SSRC range, as Teams' own clients write it: Teams then
        // names the stream after the line's label (`applicationsharingVideo-
        // <ssrc>` for a shared screen), which is how it knows what it is.
        s.push_str(&format!("a=x-ssrc-range:{0}-{0}\r\n", ssrc));
        s
    }

    /// Our audio m-line; `dtmf` adds telephone-event with that payload type.
    fn audio_section(
        &self,
        port: u16,
        addr: &str,
        mid: &str,
        setup: &str,
        dtmf: Option<u8>,
    ) -> String {
        let mut s = String::new();
        match dtmf {
            Some(d) => s.push_str(&format!("m=audio {port} RTP/SAVP {PT_PCMU} {d}\r\n")),
            None => s.push_str(&format!("m=audio {port} RTP/SAVP {PT_PCMU}\r\n")),
        }
        s.push_str(&format!("c=IN IP4 {addr}\r\n"));
        for c in &self.candidates {
            // to_sdp_line() omits the "a=" prefix.
            s.push_str("a=");
            s.push_str(&c.to_sdp_line());
            s.push_str("\r\n");
        }
        s.push_str(&format!("a=ice-ufrag:{}\r\n", self.ufrag));
        s.push_str(&format!("a=ice-pwd:{}\r\n", self.pwd));
        s.push_str(&format!("a=fingerprint:{}\r\n", self.identity.fingerprint));
        s.push_str(&format!("a=setup:{setup}\r\n"));
        s.push_str(&format!("a=mid:{mid}\r\n"));
        s.push_str("a=sendrecv\r\n");
        s.push_str("a=rtcp-mux\r\n");
        s.push_str(&format!("a=rtpmap:{PT_PCMU} PCMU/8000\r\n"));
        if let Some(d) = dtmf {
            s.push_str(&format!("a=rtpmap:{d} telephone-event/8000\r\n"));
            s.push_str(&format!("a=fmtp:{d} 0-15\r\n"));
        }
        // We take dominant speaker history (Teams' audio lines say so).
        s.push_str("a=x-signaling-fb:* x-message app recv:dsh\r\n");
        if self.meeting {
            s.push_str(&format!(
                "a=extmap:{} {}\r\n",
                super::twcc::EXTENSION_ID,
                super::twcc::EXTENSION_URI
            ));
            s.push_str("a=rtcp-fb:* transport-cc\r\n");
        }
        s.push_str(&format!("a=x-ssrc-range:{0}-{0}\r\n", self.ssrc));
        s.push_str(&format!("a=ssrc:{} cname:ost\r\n", self.ssrc));
        // Teams pairs streams by label.
        s.push_str("a=label:main-audio\r\n");
        s
    }

    /// The SDP answer: audio (PCMU, DTLS active) bundled alone; every other
    /// offered m-line is rejected with port 0.
    pub fn answer_sdp(&self, offer: &WebRtcOffer) -> String {
        self.answer_sdp_with(offer, false)
    }

    /// The SDP answer, also accepting the peer's main video when `video`
    /// is set and it offered H.264 we decode (bundled with the audio, so
    /// one socket and one DTLS handshake carry both).
    pub fn answer_sdp_with(&self, offer: &WebRtcOffer, video: bool) -> String {
        let port = self.socket.local_addr().map(|a| a.port()).unwrap_or(9);
        let addr = self.public_address();
        let session_id = u64::from(self.ssrc) << 16 | 1;
        let video = offer.video.as_ref().filter(|_| video);
        // Screen sharing is accepted whenever we can decode it, in audio
        // calls too (as Teams allows), and even while inactive so the other
        // side can turn it on in a re-offer.
        let sharing = offer.sharing.as_ref().filter(|_| cfg!(feature = "video"));
        let mut s = String::new();
        s.push_str("v=0\r\n");
        s.push_str(&format!("o=- {session_id} 2 IN IP4 127.0.0.1\r\n"));
        s.push_str("s=-\r\nt=0 0\r\n");
        let bundle: Vec<&str> = std::iter::once(offer.audio_mid.as_str())
            .chain(video.map(|v| v.mid.as_str()))
            .chain(sharing.map(|v| v.mid.as_str()))
            .collect();
        s.push_str(&format!("a=group:BUNDLE {}\r\n", bundle.join(" ")));
        s.push_str("a=msid-semantic: WMS ost\r\n");
        for (mid, kind, proto_fmts) in &offer.sections {
            if *mid == offer.audio_mid {
                // DTMF only with the payload type the peer offered.
                s.push_str(&self.audio_section(port, &addr, mid, "active", offer.dtmf_pt));
            } else if let Some(v) = video.filter(|v| v.mid == *mid) {
                s.push_str(&self.video_section(
                    port,
                    &addr,
                    VideoLine {
                        mid,
                        setup: "active",
                        pt: v.payload_type,
                        profile: &v.profile,
                        // We send only with the camera on; otherwise we
                        // just take theirs.
                        direction: if self.camera_on {
                            v.answer_direction()
                        } else if v.sends {
                            "recvonly"
                        } else {
                            "inactive"
                        },
                        label: "main-video",
                        ssrc: self.video_ssrc,
                    },
                ));
            } else if let Some(sh) = sharing.filter(|v| v.mid == *mid) {
                s.push_str(&self.video_section(
                    port,
                    &addr,
                    VideoLine {
                        mid,
                        setup: "active",
                        pt: sh.payload_type,
                        profile: &sh.profile,
                        direction: sh.answer_direction(),
                        label: "applicationsharing-video",
                        ssrc: self.share_ssrc,
                    },
                ));
            } else {
                let fmt = proto_fmts.split_whitespace().nth(1).unwrap_or("0");
                let proto = proto_fmts.split_whitespace().next().unwrap_or("RTP/SAVP");
                s.push_str(&format!("m={kind} 0 {proto} {fmt}\r\n"));
                s.push_str("c=IN IP4 0.0.0.0\r\n");
                s.push_str(&format!("a=mid:{mid}\r\n"));
                s.push_str("a=inactive\r\n");
            }
        }
        s
    }
}

/// Media counters.
#[derive(Debug, Default, Clone, Copy)]
pub struct WebRtcStats {
    pub packets_sent: u64,
    pub packets_received: u64,
    pub bytes_received: u64,
    /// RTP packets that arrived but didn't decrypt (diagnostics).
    pub packets_undecryptable: u64,
}

/// A running WebRTC audio session; dropping it stops the media.
pub struct WebRtcAudioSession {
    tasks: Vec<tokio::task::JoinHandle<()>>,
    /// What sending our camera needs: the socket, the peer, SRTP, and the
    /// negotiated video payload type and our SSRC.
    #[cfg(feature = "video")]
    video_out: Option<VideoOut>,
    #[cfg(feature = "video")]
    camera: Option<(
        super::webrtc_video::VideoSender,
        tokio::task::JoinHandle<()>,
    )>,
    /// What sending our screen needs, and the sharing line's mid.
    #[cfg(feature = "video")]
    share_out: Option<(VideoOut, String)>,
    /// Our screen, while we share it.
    #[cfg(feature = "video")]
    share: Option<(
        super::webrtc_video::VideoSender,
        tokio::task::JoinHandle<()>,
    )>,
    /// The description we last sent (answer, re-answer or accepted
    /// re-offer): what our own re-offers start from.
    current_sdp: std::sync::Mutex<String>,
    /// Our re-offer awaiting the other side's answer, its version, and
    /// what it changes.
    pending_offer: std::sync::Mutex<Option<(String, u64, Reoffer)>>,
    /// What's negotiated as sending: (our camera, our screen).
    negotiated: std::sync::Mutex<(bool, bool)>,
    /// The mid of our camera's video line.
    #[cfg(feature = "video")]
    video_mid: Option<String>,
    /// The peer's video, decoded and published as the "remote" frame.
    #[cfg(feature = "video")]
    _video_rx: Vec<Arc<super::webrtc_video::VideoReceiver>>,
    /// In a meeting: others' video and the control plane asking for it.
    meeting_video: Option<super::meeting_media::MeetingVideo>,
    /// A meeting's requests for what we send (see [`Self::control_video`]).
    #[cfg(feature = "video")]
    video_control: Option<Arc<VideoControl>>,
    /// What a meeting's processor asks our camera for.
    #[cfg(feature = "video")]
    send_control: Arc<super::webrtc_video::SendControl>,
    /// … and our screen.
    #[cfg(feature = "video")]
    #[cfg_attr(not(feature = "screencast"), allow(dead_code))]
    share_control: Arc<super::webrtc_video::SendControl>,
    /// The receive slots' SSRC ranges by mid, which re-offers may move.
    #[cfg(feature = "video")]
    slot_ranges: Vec<(String, Arc<std::sync::atomic::AtomicU64>)>,
    muted: Arc<AtomicBool>,
    /// On hold: nothing is sent or played until it's resumed.
    held: Arc<AtomicBool>,
    /// Dial-pad tones to send (RFC 4733 event codes), when negotiated.
    dtmf_tx: Option<mpsc::UnboundedSender<u8>>,
    /// The SDP we last sent, and its session version, for re-answers.
    local_sdp: std::sync::Mutex<(String, u64)>,
    /// The other side put the call on hold.
    held_by_peer: AtomicBool,
    /// Our DTLS role, kept in re-answers: "active" (client) or "passive".
    dtls_role: &'static str,
    stats: Arc<Mutex<WebRtcStats>>,
    #[cfg(feature = "audio")]
    _capture: Option<audio::AudioCapture>,
    #[cfg(feature = "audio")]
    _playback: Option<audio::AudioPlayback>,
}

#[cfg(feature = "video")]
struct VideoOut {
    socket: Arc<UdpSocket>,
    peer: SocketAddr,
    srtp: Arc<Mutex<Option<srtp::SrtpStreams>>>,
    pt: u8,
    ssrc: u32,
    /// Where the RTCP reader flags keyframe requests for the camera.
    keyframe_req: KeyframeSlot,
}

impl Drop for WebRtcAudioSession {
    fn drop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
        #[cfg(feature = "video")]
        if let Some((_, fwd)) = self.camera.take() {
            fwd.abort();
        }
    }
}

impl WebRtcAudioSession {
    pub fn set_muted(&self, muted: bool) {
        self.muted.store(muted, Ordering::Relaxed);
    }

    pub fn is_muted(&self) -> bool {
        self.muted.load(Ordering::Relaxed)
    }

    /// Put the call on hold (no audio either way) or resume it.
    pub fn set_held(&self, held: bool) {
        self.held.store(held, Ordering::Relaxed);
    }

    pub fn is_held(&self) -> bool {
        self.held.load(Ordering::Relaxed)
    }

    /// Remember the SDP we sent (offer or answer), to answer re-offers.
    pub fn set_local_sdp(&self, sdp: &str) {
        *self.local_sdp.lock().unwrap_or_else(|e| e.into_inner()) = (sdp.to_string(), 2);
        *self.current_sdp.lock().unwrap_or_else(|e| e.into_inner()) = sdp.to_string();
    }

    /// Answer the peer's re-offer, noting whether it holds the call.
    pub fn answer_reoffer(&self, offer: &str) -> Result<String> {
        let mut g = self.local_sdp.lock().unwrap_or_else(|e| e.into_inner());
        if g.0.is_empty() {
            bail!("No earlier SDP to answer with");
        }
        g.1 += 1;
        let sdp = reanswer(&g.0, offer, g.1, self.dtls_role);
        *self.current_sdp.lock().unwrap_or_else(|e| e.into_inner()) = sdp.clone();
        self.held_by_peer
            .store(offer_holds(offer), Ordering::Relaxed);
        // They stopped presenting: take their last shared frame down.
        if !offer_shares(offer) {
            super::frames::clear("share");
        }
        // A media processor's re-offer may renumber the receive slots.
        let slots = super::meeting_media::answered_slots(offer);
        let share = super::meeting_media::answered_share(offer);
        #[cfg(feature = "video")]
        for slot in slots.iter().chain(share.iter()) {
            if let Some((_, r)) = self.slot_ranges.iter().find(|(m, _)| *m == slot.mid) {
                r.store(pack_range(slot.ssrcs), Ordering::Relaxed);
            }
        }
        if let Some(v) = &self.meeting_video {
            v.update_slots(slots, share);
        }
        Ok(sdp)
    }

    /// In a meeting: show these video sources (roster `main-video`
    /// sourceIds, most wanted first); returns sourceId -> frame key for
    /// those that got a slot.
    pub fn show_videos(&self, sources: &[(i64, u32)]) -> std::collections::HashMap<i64, String> {
        self.meeting_video
            .as_ref()
            .map(|v| v.show(sources))
            .unwrap_or_default()
    }

    /// A meeting's controlVideoStreaming request for one of our streams
    /// (`sourceId`, and its `fmtParams` as "max-fs=…;max-br=…;…"): send it
    /// within those limits, starting with a keyframe for whoever now
    /// watches, as Teams' media stack does.
    pub fn control_video(&self, source_id: i64, fmt_params: &str) {
        #[cfg(feature = "video")]
        if let Some(h) = &self.video_control {
            h(source_id, &[format!("KeyFrame=1;{fmt_params}")]);
        }
        #[cfg(not(feature = "video"))]
        let _ = (source_id, fmt_params);
    }

    /// In a meeting: receive this presenter's screen (their
    /// applicationsharing-video sourceId), or stop.
    pub fn show_share(&self, source: Option<i64>) {
        if let Some(v) = &self.meeting_video {
            v.show_share(source);
        }
    }

    /// The other side has the call on hold.
    pub fn is_held_by_peer(&self) -> bool {
        self.held_by_peer.load(Ordering::Relaxed)
    }

    /// Whether the call negotiated dial-pad tones (telephone-event).
    pub fn can_dtmf(&self) -> bool {
        self.dtmf_tx.is_some()
    }

    /// Send a dial-pad key (0-9, *, #, A-D) as an RFC 4733 tone.
    pub fn send_dtmf(&self, key: char) -> Result<()> {
        let event = dtmf_event(key).context("Not a dial-pad key")?;
        self.dtmf_tx
            .as_ref()
            .context("This call doesn't take dial-pad tones")?
            .send(event)
            .ok()
            .context("The call has ended")
    }

    pub async fn stats(&self) -> WebRtcStats {
        *self.stats.lock().await
    }

    /// Whether this call negotiated video we can send.
    pub fn can_send_video(&self) -> bool {
        #[cfg(feature = "video")]
        return self.video_out.is_some();
        #[cfg(not(feature = "video"))]
        false
    }

    /// Turn our camera on or off (`device`: a V4L2 path, else the first).
    pub fn set_camera(&mut self, on: bool, device: Option<String>) -> Result<()> {
        #[cfg(feature = "video")]
        {
            if !on {
                if let Some((sender, fwd)) = self.camera.take() {
                    drop(sender);
                    fwd.abort();
                }
                if let Some(v) = &self.video_out {
                    *v.keyframe_req.lock().unwrap_or_else(|e| e.into_inner()) = None;
                }
                return Ok(());
            }
            if self.camera.is_some() {
                return Ok(());
            }
            let v = self.video_out.as_ref().context("This call has no video")?;
            let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
            let sender = super::webrtc_video::VideoSender::start(
                tx,
                v.pt,
                v.ssrc,
                device,
                Some(self.send_control.clone()),
            )?;
            *v.keyframe_req.lock().unwrap_or_else(|e| e.into_inner()) =
                Some(sender.keyframe.clone());
            let (socket, peer, srtp) = (v.socket.clone(), v.peer, v.srtp.clone());
            let fwd = tokio::spawn(async move {
                while let Some(p) = rx.recv().await {
                    let sealed = srtp.lock().await.as_mut().and_then(|c| c.protect(&p).ok());
                    if let Some(p) = sealed {
                        let _ = socket.send_to(&p, peer).await;
                    }
                }
            });
            self.camera = Some((sender, fwd));
            Ok(())
        }
        #[cfg(not(feature = "video"))]
        {
            let _ = (on, device);
            bail!("OST was built without video")
        }
    }

    /// Whether this call has a screen-sharing line we can send on.
    pub fn can_share(&self) -> bool {
        #[cfg(feature = "screencast")]
        {
            let Some((_, mid)) = &self.share_out else {
                return false;
            };
            let g = self.local_sdp.lock().unwrap_or_else(|e| e.into_inner());
            sections(&g.0).iter().any(|(m, t)| {
                m.as_deref() == Some(mid.as_str()) && t.split_whitespace().nth(1) != Some("0")
            })
        }
        #[cfg(not(feature = "screencast"))]
        false
    }

    /// Our re-offer making `change` (camera or screen on or off), keeping
    /// the rest as negotiated; the answer goes to [`Self::take_reoffer_answer`].
    pub fn reoffer(&self, change: Reoffer) -> Result<String> {
        #[cfg(feature = "video")]
        {
            let mut pending = self.pending_offer.lock().unwrap_or_else(|e| e.into_inner());
            if pending.is_some() {
                bail!("Another media change is still waiting for an answer");
            }
            match change {
                Reoffer::Share(_) if self.share_out.is_none() => {
                    bail!("This call has no screen-sharing line")
                }
                Reoffer::Camera(_) if self.video_mid.is_none() => bail!("This call has no video"),
                _ => {}
            }
            let (camera, share) =
                change.apply(*self.negotiated.lock().unwrap_or_else(|e| e.into_inner()));
            let mut lines: Vec<(&str, &str)> = Vec::new();
            if let Some(mid) = &self.video_mid {
                lines.push((mid, if camera { "sendrecv" } else { "recvonly" }));
            }
            if let Some((_, mid)) = &self.share_out {
                lines.push((mid, if share { "sendonly" } else { "recvonly" }));
            }
            let (base, version) = {
                let g = self.local_sdp.lock().unwrap_or_else(|e| e.into_inner());
                (g.0.clone(), g.1 + 1)
            };
            let current = self
                .current_sdp
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone();
            if current.is_empty() {
                bail!("No earlier SDP to re-offer");
            }
            let sdp = media_offer(&current, &base, &lines, version);
            *pending = Some((sdp.clone(), version, change));
            Ok(sdp)
        }
        #[cfg(not(feature = "video"))]
        {
            let _ = change;
            bail!("OST was built without video")
        }
    }

    /// The other side's answer to our re-offer: what it was for, and
    /// whether the answer takes it (it receives the camera or screen we
    /// offered to send). Our offer becomes our current description.
    pub fn take_reoffer_answer(&self, answer: &str) -> Result<(Reoffer, bool)> {
        let (sdp, version, change) = self
            .pending_offer
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
            .context("No re-offer is waiting for an answer")?;
        #[cfg(feature = "video")]
        let accepted = match change {
            Reoffer::Share(true) => self
                .share_out
                .as_ref()
                .is_some_and(|(_, mid)| answer_receives(answer, mid)),
            Reoffer::Camera(true) => self
                .video_mid
                .as_deref()
                .is_some_and(|mid| answer_receives(answer, mid)),
            _ => true,
        };
        #[cfg(not(feature = "video"))]
        let accepted = {
            let _ = answer;
            false
        };
        if accepted {
            let mut n = self.negotiated.lock().unwrap_or_else(|e| e.into_inner());
            *n = change.apply(*n);
        }
        // Re-answers still mirror the first answer; the version moves on.
        self.local_sdp.lock().unwrap_or_else(|e| e.into_inner()).1 = version;
        *self.current_sdp.lock().unwrap_or_else(|e| e.into_inner()) =
            sdp.replace("a=setup:actpass", &format!("a=setup:{}", self.dtls_role));
        Ok((change, accepted))
    }

    /// Drop our re-offer (the other side refused it); nothing changes.
    pub fn cancel_reoffer(&self) {
        *self.pending_offer.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }

    /// Whether a re-offer of ours is waiting for its answer.
    pub fn reoffer_pending(&self) -> bool {
        self.pending_offer
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
    }

    /// (camera, screen) sending once `change` is made.
    pub fn negotiated_after(&self, change: Reoffer) -> (bool, bool) {
        change.apply(*self.negotiated.lock().unwrap_or_else(|e| e.into_inner()))
    }

    /// Whether our camera line is negotiated as sending.
    pub fn camera_negotiated(&self) -> bool {
        self.negotiated.lock().unwrap_or_else(|e| e.into_inner()).0
    }

    /// Start sending a screen capture on the sharing line.
    #[cfg(feature = "screencast")]
    pub fn start_share(
        &mut self,
        capture: super::screencast::ScreenCapture,
        frames: std::sync::mpsc::Receiver<super::camera::YuvFrame>,
    ) -> Result<()> {
        self.stop_share();
        let (v, _) = self
            .share_out
            .as_ref()
            .context("This call has no screen-sharing line")?;
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
        let sender = super::webrtc_video::VideoSender::start_screen(
            tx,
            v.pt,
            v.ssrc,
            capture,
            frames,
            Some(self.share_control.clone()),
        )?;
        *v.keyframe_req.lock().unwrap_or_else(|e| e.into_inner()) = Some(sender.keyframe.clone());
        let (socket, peer, srtp) = (v.socket.clone(), v.peer, v.srtp.clone());
        let fwd = tokio::spawn(async move {
            while let Some(p) = rx.recv().await {
                let sealed = srtp.lock().await.as_mut().and_then(|c| c.protect(&p).ok());
                if let Some(p) = sealed {
                    let _ = socket.send_to(&p, peer).await;
                }
            }
        });
        self.share = Some((sender, fwd));
        Ok(())
    }

    /// Stop sending our screen (the capture ends with it).
    pub fn stop_share(&mut self) {
        #[cfg(feature = "video")]
        {
            if let Some((sender, fwd)) = self.share.take() {
                drop(sender);
                fwd.abort();
            }
            if let Some((v, _)) = &self.share_out {
                *v.keyframe_req.lock().unwrap_or_else(|e| e.into_inner()) = None;
            }
        }
    }

    /// Whether our shared screen went away by itself (the window closed,
    /// or sharing was stopped from the desktop).
    pub fn share_ended(&self) -> bool {
        #[cfg(feature = "video")]
        return self.share.as_ref().is_some_and(|(s, _)| s.ended());
        #[cfg(not(feature = "video"))]
        false
    }

    /// Whether we're sending our screen.
    pub fn is_sharing(&self) -> bool {
        #[cfg(feature = "video")]
        return self.share.is_some();
        #[cfg(not(feature = "video"))]
        false
    }

    pub fn camera_on(&self) -> bool {
        #[cfg(feature = "video")]
        return self.camera.is_some();
        #[cfg(not(feature = "video"))]
        false
    }

    /// Answerer side: ICE controlled, DTLS client (we answered `active`).
    pub async fn start(local: LocalAudio, offer: WebRtcOffer) -> Result<Self> {
        Self::start_with_role(local, offer, false, true).await
    }

    /// Offerer side: ICE controlling; DTLS role from the peer's answer
    /// (`active` makes us the server, `passive` the client).
    pub async fn start_as_offerer(local: LocalAudio, mut answer: WebRtcOffer) -> Result<Self> {
        let dtls_client = answer.setup.eq_ignore_ascii_case("passive");
        // Our video offers carry a sharing line. An answer that turned it
        // down (an audio-only answer drops its mid) still leaves it ours to
        // re-offer later, as Teams does when someone shares.
        let (video_mid, share_mid) = if local.meeting {
            (
                super::meeting_media::CAMERA_MID,
                super::meeting_media::SHARE_MID,
            )
        } else {
            (VIDEO_MID, SHARE_MID)
        };
        if local.receive_video && answer.video.is_none() {
            answer.video = Some(OfferedVideo {
                mid: video_mid.into(),
                payload_type: PT_H264_OFFER,
                profile: "42e01f".into(),
                ssrc: None,
                sends: false,
                receives: false,
            });
        }
        if local.receive_video && answer.sharing.is_none() {
            answer.sharing = Some(OfferedVideo {
                mid: share_mid.into(),
                payload_type: PT_H264_SHARE_OFFER,
                profile: "42e01f".into(),
                ssrc: None,
                sends: false,
                receives: false,
            });
        }
        Self::start_with_role(local, answer, true, dtls_client).await
    }

    /// Find the peer with ICE, run DTLS, and start sending and receiving.
    async fn start_with_role(
        local: LocalAudio,
        offer: WebRtcOffer,
        controlling: bool,
        dtls_client: bool,
    ) -> Result<Self> {
        let socket = local.socket.clone();
        let (dtls_tx, dtls_rx) = std::sync::mpsc::channel::<Vec<u8>>();
        let (peer_tx, mut peer_rx) = mpsc::channel::<SocketAddr>(8);
        let srtp_ctx: Arc<Mutex<Option<srtp::SrtpStreams>>> = Arc::new(Mutex::new(None));
        let stats = Arc::new(Mutex::new(WebRtcStats::default()));
        let remote: Arc<Mutex<Option<SocketAddr>>> = Arc::new(Mutex::new(None));

        #[cfg(feature = "audio")]
        let (capture, mic_rx) = match audio::AudioCapture::start() {
            Some((c, rx)) => (Some(c), Some(rx)),
            None => (None, None),
        };
        #[cfg(not(feature = "audio"))]
        let mic_rx: Option<std::sync::mpsc::Receiver<Vec<i16>>> = None;
        #[cfg(feature = "audio")]
        let (playback, spk_tx) = match audio::AudioPlayback::start() {
            Some((p, tx)) => (Some(p), Some(tx)),
            None => (None, None),
        };
        #[cfg(not(feature = "audio"))]
        let spk_tx: Option<std::sync::mpsc::SyncSender<Vec<i16>>> = None;

        let mut tasks = Vec::new();
        let held = Arc::new(AtomicBool::new(false));

        #[cfg(feature = "video")]
        let keyframe_req: KeyframeSlot = Default::default();
        // What a meeting's processor asks our camera for.
        #[cfg(feature = "video")]
        let send_control: Arc<super::webrtc_video::SendControl> = Arc::default();
        #[cfg(feature = "video")]
        let share_control: Arc<super::webrtc_video::SendControl> = Arc::default();
        #[cfg(feature = "video")]
        let share_keyframe_req: KeyframeSlot = Default::default();
        // The peer's video, when the answer accepted it.
        #[cfg(feature = "video")]
        // The peer's camera ("remote") and screen share ("share"): each a
        // payload type, its decoder and the SSRC last seen carrying it.
        // Started even while the peer isn't sending: a re-offer may turn
        // either on later.
        // The camera only when the answer accepted video; the share always
        // (the answer always accepts it).
        let video_rx: Vec<VideoStream> = [
            (
                offer.video.as_ref().filter(|_| local.receive_video),
                "remote",
            ),
            (offer.sharing.as_ref(), "share"),
        ]
        .into_iter()
        .filter_map(|(v, key)| {
            // In a meeting the sharing line is a slot too: the processor
            // sends the presenter's screen on its SSRC range.
            let share = (key == "share" && local.meeting)
                .then(|| offer.share_slot.clone())
                .flatten();
            // (The processor sends with the payload types of our offer.)
            v.map(|v| VideoStream {
                pt: share
                    .as_ref()
                    .map_or(v.payload_type, |_| PT_H264_SHARE_OFFER),
                rx: Arc::new(super::webrtc_video::VideoReceiver::start(key)),
                ssrc: Arc::new(std::sync::atomic::AtomicU32::new(v.ssrc.unwrap_or(0))),
                range: share
                    .map(|s| Arc::new(std::sync::atomic::AtomicU64::new(pack_range(s.ssrcs)))),
            })
        })
        .chain(
            // Others' video in a meeting, one decoder per receive slot.
            offer
                .slots
                .iter()
                .filter(|_| local.meeting)
                .map(|slot| VideoStream {
                    // Our offer's H.264 payload type: what it's sent with.
                    pt: PT_H264_OFFER,
                    rx: Arc::new(super::webrtc_video::VideoReceiver::start(
                        &super::meeting_media::frame_key(&slot.mid),
                    )),
                    ssrc: Arc::new(std::sync::atomic::AtomicU32::new(0)),
                    range: Some(Arc::new(std::sync::atomic::AtomicU64::new(pack_range(
                        slot.ssrcs,
                    )))),
                }),
        )
        .collect();
        #[cfg(feature = "video")]
        let slot_ranges: Vec<(String, Arc<std::sync::atomic::AtomicU64>)> = offer
            .share_slot
            .iter()
            .filter(|_| local.meeting)
            .chain(offer.slots.iter().filter(|_| local.meeting))
            .zip(video_rx.iter().filter_map(|v| v.range.clone()))
            .map(|(slot, r)| (slot.mid.clone(), r))
            .collect();

        // Meetings: transport-wide congestion control, as Teams does, so
        // the processor knows our downlink and sends video layers to fit.
        let twcc = local.meeting.then(|| {
            (
                Arc::new(std::sync::Mutex::new(super::twcc::Recorder::new())),
                Arc::new(std::sync::atomic::AtomicU32::new(0)),
            )
        });

        // Meetings: who speaks, from the mix's contributing sources (Teams'
        // voice-level outline), reported as they change.
        let speakers = local.meeting.then(|| {
            let tracker: Arc<std::sync::Mutex<super::active_speakers::Tracker>> = Arc::default();
            let t = tracker.clone();
            tasks.push(tokio::spawn(async move {
                let mut tick = tokio::time::interval(Duration::from_millis(50));
                loop {
                    tick.tick().await;
                    let changed = t
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .changed(std::time::Instant::now());
                    if let Some(ids) = changed {
                        crate::event_hub::publish(
                            crate::event_hub::EventKind::Call,
                            serde_json::json!({
                                "callAgentPath": "ost/activeSpeakers/",
                                "body": {"sourceIds": ids},
                            })
                            .to_string(),
                        );
                    }
                }
            }));
            tracker
        });

        // Receive and demultiplex.
        tasks.push(tokio::spawn(recv_loop(RecvCtx {
            socket: socket.clone(),
            local_pwd: local.pwd.clone(),
            dtls_tx,
            peer_tx: peer_tx.clone(),
            srtp: srtp_ctx.clone(),
            stats: stats.clone(),
            spk_tx,
            held: held.clone(),
            twcc: twcc.clone(),
            speakers,
            #[cfg(feature = "video")]
            video: video_rx.clone(),
            #[cfg(feature = "video")]
            keyframe_req: vec![
                (local.video_ssrc, keyframe_req.clone()),
                (local.share_ssrc, share_keyframe_req.clone()),
            ],
        })));

        // ICE: check every remote candidate until one answers; the peer's
        // own checks reaching us (handled in recv_loop) also identify it.
        let username = format!("{}:{}", offer.ice_ufrag, local.ufrag);
        let tie_breaker = random_u64();
        let checks = {
            let (socket, username, pwd) = (socket.clone(), username.clone(), offer.ice_pwd.clone());
            let targets: Vec<SocketAddr> = offer
                .candidates
                .iter()
                .filter(|c| c.transport == ice::Transport::Udp && c.component == 1)
                .filter_map(|c| format!("{}:{}", c.address, c.port).parse().ok())
                .collect();
            tokio::spawn(async move {
                for _ in 0..30 {
                    for t in &targets {
                        let txn = ice::generate_transaction_id();
                        let req = ice::build_ice_binding_request(
                            &txn,
                            &username,
                            pwd.as_bytes(),
                            1694498815,
                            controlling,
                            tie_breaker,
                        );
                        let _ = socket.send_to(&req, t).await;
                    }
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
            })
        };
        let peer = tokio::time::timeout(ICE_TIMEOUT, peer_rx.recv())
            .await
            .ok()
            .flatten()
            .context("ICE found no path to the caller")?;
        checks.abort();
        *remote.lock().await = Some(peer);
        tracing::info!(%peer, "ICE connected");

        // DTLS (client, since we answered setup:active).
        let (keys, dtls) = {
            let socket = socket.clone();
            let identity = local.identity;
            let expected = offer.fingerprint.clone();
            tokio::task::spawn_blocking(move || {
                dtls_handshake(socket, peer, dtls_rx, &identity, &expected, dtls_client)
            })
            .await
            .context("DTLS task failed")??
        };
        *srtp_ctx.lock().await = Some(srtp::SrtpStreams::new(&keys.0, &keys.1)?);
        tracing::info!("DTLS-SRTP established");
        // A meeting's media control plane: a data channel in this DTLS
        // session, when the processor took our data line.
        // The processor's layer requests for what we send, by stream: its
        // size, bitrate and frame rate, and keyframes. They come over the
        // media control plane (`vdclc`) or as controlVideoStreaming events.
        #[cfg(feature = "video")]
        let video_control: Option<Arc<VideoControl>> = local.meeting.then(|| {
            // Requests for the sharing line's stream are for our screen;
            // the rest for our camera.
            let share_stream = offer.share_slot.as_ref().map(|s| s.stream_msid);
            let camera = (send_control.clone(), keyframe_req.clone());
            let screen = (share_control.clone(), share_keyframe_req.clone());
            let handler: Arc<VideoControl> = Arc::new(move |stream: i64, layers: &[String]| {
                let (control, slot) = if Some(stream) == share_stream {
                    &screen
                } else {
                    &camera
                };
                let parsed: Vec<_> = layers
                    .iter()
                    .filter_map(|l| super::webrtc_video::parse_layer(l))
                    .collect();
                // One stream: the largest layer asked for.
                if let Some((limits, _)) = parsed.iter().max_by_key(|(l, _)| l.max_fs) {
                    control.set(*limits);
                }
                if parsed.iter().any(|(_, key)| *key)
                    && let Some(flag) = slot.lock().unwrap_or_else(|e| e.into_inner()).as_ref()
                {
                    flag.store(true, Ordering::Relaxed);
                }
            });
            handler
        });
        let meeting_video = match offer.data_stream {
            Some(stream_id) if local.meeting => {
                let mut dtls = dtls;
                dtls.get_mut().wait = super::datachannel::RECV_WAIT;
                tracing::info!(
                    stream_id,
                    slots = offer.slots.len(),
                    "Opening the media control plane"
                );
                let (tx, events) =
                    super::datachannel::open(dtls, super::meeting_media::DATA_LABEL, 0);
                #[cfg(feature = "video")]
                let on_layers: super::meeting_media::LayerHandler = match &video_control {
                    Some(h) => {
                        let h = h.clone();
                        Box::new(move |stream: i64, layers: &[String]| h(stream, layers))
                    }
                    None => Box::new(|_, _| {}),
                };
                #[cfg(not(feature = "video"))]
                let on_layers: super::meeting_media::LayerHandler = Box::new(|_, _| {});
                Some(super::meeting_media::MeetingVideo::start(
                    offer.slots.clone(),
                    offer.share_slot.clone(),
                    tx,
                    events,
                    on_layers,
                ))
            }
            _ => None,
        };

        let muted = Arc::new(AtomicBool::new(false));
        let (dtmf_tx, dtmf_rx) = mpsc::unbounded_channel::<u8>();
        let dtmf_tx = offer.dtmf_pt.map(|_| dtmf_tx);

        // Send audio every 20 ms.
        tasks.push(tokio::spawn(send_loop(SendCtx {
            socket: socket.clone(),
            remote: remote.clone(),
            srtp: srtp_ctx.clone(),
            ssrc: local.ssrc,
            stats: stats.clone(),
            mic_rx,
            muted: muted.clone(),
            held: held.clone(),
            dtmf: offer.dtmf_pt.map(|pt| (pt, dtmf_rx)),
        })));

        // Ask for a keyframe (RTCP PLI) whenever the video decoder needs one.
        #[cfg(feature = "video")]
        for stream in &video_rx {
            let (socket, srtp, want, theirs) = (
                socket.clone(),
                srtp_ctx.clone(),
                stream.rx.keyframe_wanted.clone(),
                stream.ssrc.clone(),
            );
            let ours = local.video_ssrc;
            tasks.push(tokio::spawn(async move {
                loop {
                    let theirs = theirs.load(Ordering::Relaxed);
                    if want.load(Ordering::Relaxed) && theirs != 0 {
                        let pli = super::webrtc_video::pli(ours, theirs);
                        let sealed = srtp
                            .lock()
                            .await
                            .as_mut()
                            .and_then(|c| c.protect_rtcp(&pli).ok());
                        if let Some(p) = sealed {
                            let _ = socket.send_to(&p, peer).await;
                        }
                    }
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
            }));
        }

        // Transport-wide feedback every 50 ms.
        if let Some((rec, media)) = twcc.clone() {
            let (socket, srtp, ours) = (socket.clone(), srtp_ctx.clone(), local.ssrc);
            tasks.push(tokio::spawn(async move {
                let mut tick = tokio::time::interval(Duration::from_millis(50));
                loop {
                    tick.tick().await;
                    let fb = rec
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .feedback(ours, media.load(Ordering::Relaxed));
                    let Some(fb) = fb else { continue };
                    let sealed = srtp
                        .lock()
                        .await
                        .as_mut()
                        .and_then(|c| c.protect_rtcp(&fb).ok());
                    if let Some(p) = sealed {
                        let _ = socket.send_to(&p, peer).await;
                    }
                }
            }));
        }

        // Consent freshness: keep sending binding requests to the peer.
        {
            let (socket, pwd) = (socket.clone(), offer.ice_pwd.clone());
            tasks.push(tokio::spawn(async move {
                loop {
                    tokio::time::sleep(CONSENT_INTERVAL).await;
                    let txn = ice::generate_transaction_id();
                    let req = ice::build_ice_binding_request(
                        &txn,
                        &username,
                        pwd.as_bytes(),
                        1694498815,
                        controlling,
                        tie_breaker,
                    );
                    let _ = socket.send_to(&req, peer).await;
                }
            }));
        }

        #[cfg(feature = "video")]
        let video_out = offer
            .video
            .as_ref()
            // Also when they don't take video yet: a re-offer turns it on.
            .filter(|_| local.receive_video)
            .map(|v| VideoOut {
                socket: socket.clone(),
                peer,
                srtp: srtp_ctx.clone(),
                pt: v.payload_type,
                ssrc: local.video_ssrc,
                keyframe_req: keyframe_req.clone(),
            });
        // The screen-sharing line, for sharing ours later (a re-offer turns
        // it on).
        #[cfg(feature = "video")]
        let share_out = offer.sharing.as_ref().map(|v| VideoOut {
            socket: socket.clone(),
            peer,
            srtp: srtp_ctx.clone(),
            pt: v.payload_type,
            ssrc: local.share_ssrc,
            keyframe_req: share_keyframe_req.clone(),
        });
        Ok(Self {
            tasks,
            #[cfg(feature = "video")]
            video_out,
            #[cfg(feature = "video")]
            camera: None,
            #[cfg(feature = "video")]
            share_out: share_out.map(|o| {
                (
                    o,
                    offer
                        .sharing
                        .as_ref()
                        .map(|v| v.mid.clone())
                        .unwrap_or_default(),
                )
            }),
            #[cfg(feature = "video")]
            share: None,
            pending_offer: std::sync::Mutex::new(None),
            negotiated: std::sync::Mutex::new((local.camera_on, false)),
            #[cfg(feature = "video")]
            video_mid: offer.video.as_ref().map(|v| v.mid.clone()),
            #[cfg(feature = "video")]
            _video_rx: video_rx.into_iter().map(|v| v.rx).collect(),
            meeting_video,
            #[cfg(feature = "video")]
            video_control,
            #[cfg(feature = "video")]
            send_control,
            #[cfg(feature = "video")]
            share_control,
            #[cfg(feature = "video")]
            slot_ranges,
            muted,
            held,
            dtmf_tx,
            local_sdp: std::sync::Mutex::new((String::new(), 2)),
            current_sdp: std::sync::Mutex::new(String::new()),
            held_by_peer: AtomicBool::new(false),
            dtls_role: if dtls_client { "active" } else { "passive" },
            stats,
            #[cfg(feature = "audio")]
            _capture: capture,
            #[cfg(feature = "audio")]
            _playback: playback,
        })
    }
}

/// A video stream we receive: its payload type, decoder, and the SSRC
/// last seen carrying it (for keyframe requests).
#[cfg(feature = "video")]
#[derive(Clone)]
struct VideoStream {
    pt: u8,
    rx: Arc<super::webrtc_video::VideoReceiver>,
    ssrc: Arc<std::sync::atomic::AtomicU32>,
    /// A meeting receive slot: the SSRC range the processor sends it with
    /// (low << 32 | high; a re-offer may move it).
    range: Option<Arc<std::sync::atomic::AtomicU64>>,
}

/// An SSRC range packed for an AtomicU64.
#[cfg(feature = "video")]
fn pack_range((lo, hi): (u32, u32)) -> u64 {
    u64::from(lo) << 32 | u64::from(hi)
}

#[cfg(feature = "video")]
fn in_range(range: &std::sync::atomic::AtomicU64, ssrc: u32) -> bool {
    let r = range.load(Ordering::Relaxed);
    ((r >> 32) as u32..=r as u32).contains(&ssrc)
}

struct RecvCtx {
    socket: Arc<UdpSocket>,
    local_pwd: String,
    dtls_tx: std::sync::mpsc::Sender<Vec<u8>>,
    peer_tx: mpsc::Sender<SocketAddr>,
    srtp: Arc<Mutex<Option<srtp::SrtpStreams>>>,
    stats: Arc<Mutex<WebRtcStats>>,
    spk_tx: Option<std::sync::mpsc::SyncSender<Vec<i16>>>,
    /// On hold: the peer's audio isn't played.
    held: Arc<AtomicBool>,
    /// In a meeting: arrival times for transport-wide congestion control,
    /// and the last SSRC the processor sent (feedback names one).
    twcc: Option<(
        Arc<std::sync::Mutex<super::twcc::Recorder>>,
        Arc<std::sync::atomic::AtomicU32>,
    )>,
    /// In a meeting: who the mixed audio says is speaking.
    speakers: Option<Arc<std::sync::Mutex<super::active_speakers::Tracker>>>,
    /// The video payload type and its receiver.
    #[cfg(feature = "video")]
    video: Vec<VideoStream>,
    /// For each stream we send (camera, screen): our SSRC and where to
    /// flag the peer's keyframe requests for it.
    #[cfg(feature = "video")]
    keyframe_req: Vec<(u32, KeyframeSlot)>,
}

/// Where the RTCP reader flags a keyframe request for one stream we send
/// (empty while that stream is off).
#[cfg(feature = "video")]
type KeyframeSlot = Arc<std::sync::Mutex<Option<Arc<AtomicBool>>>>;

async fn recv_loop(ctx: RecvCtx) {
    let mut buf = vec![0u8; 2048];
    let mut announced = false;
    // Streams nothing took, noted once each (diagnostics).
    let mut unrouted = std::collections::HashSet::<(u32, u8)>::new();
    loop {
        let Ok((len, from)) = ctx.socket.recv_from(&mut buf).await else {
            continue;
        };
        let data = &buf[..len];
        match data.first().copied().unwrap_or(255) {
            0..=3 => {
                if ice::is_stun_request(data)
                    && let Some(txn) = ice::get_transaction_id(data)
                {
                    let resp =
                        ice::build_binding_response(&txn, from, Some(ctx.local_pwd.as_bytes()));
                    let _ = ctx.socket.send_to(&resp, from).await;
                }
                // Either their check reached us or ours was answered: this
                // address works.
                if !announced && (ice::is_stun_request(data) || ice::is_stun_response(data)) {
                    announced = ctx.peer_tx.try_send(from).is_ok();
                }
            }
            20..=63 => {
                let _ = ctx.dtls_tx.send(data.to_vec());
            }
            128..=191 => {
                // RTCP (payload types 200-204 after the marker bit) is
                // not decoded yet.
                let pt = data.get(1).map(|b| b & 0x7f).unwrap_or(0);
                if (72..=76).contains(&pt) {
                    // RTCP: only keyframe requests for what we send matter.
                    #[cfg(feature = "video")]
                    {
                        let flags: Vec<(u32, Arc<AtomicBool>)> = ctx
                            .keyframe_req
                            .iter()
                            .filter_map(|(ssrc, slot)| {
                                let f = slot.lock().unwrap_or_else(|e| e.into_inner()).clone();
                                f.map(|f| (*ssrc, f))
                            })
                            .collect();
                        if !flags.is_empty() {
                            let plain = ctx
                                .srtp
                                .lock()
                                .await
                                .as_mut()
                                .and_then(|c| c.unprotect_rtcp(data).ok());
                            if let Some(p) = plain {
                                for (ssrc, flag) in flags {
                                    if super::webrtc_video::wants_keyframe(&p, ssrc) {
                                        tracing::debug!(ssrc, "keyframe requested");
                                        flag.store(true, Ordering::Relaxed);
                                    }
                                }
                            }
                        }
                    }
                    continue;
                }
                // The header (and its extensions) is in the clear.
                if let Some((rec, ssrc)) = &ctx.twcc
                    && let Some(seq) = super::twcc::sequence_number(data)
                {
                    rec.lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .record(seq, std::time::Instant::now());
                    if let Some(b) = data.get(8..12) {
                        ssrc.store(
                            u32::from_be_bytes([b[0], b[1], b[2], b[3]]),
                            Ordering::Relaxed,
                        );
                    }
                }
                let plain = {
                    let mut guard = ctx.srtp.lock().await;
                    match guard.as_mut() {
                        Some(c) => c.unprotect(data).ok(),
                        None => None,
                    }
                };
                let Some(plain) = plain else {
                    ctx.stats.lock().await.packets_undecryptable += 1;
                    continue;
                };
                {
                    let mut s = ctx.stats.lock().await;
                    s.packets_received += 1;
                    s.bytes_received += len as u64;
                }
                // A meeting slot by its SSRC range, else the line by its
                // payload type (RTX on a slot's range falls through).
                #[cfg(feature = "video")]
                let ssrc = plain
                    .get(8..12)
                    .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
                    .unwrap_or(0);
                #[cfg(feature = "video")]
                if let Some(stream) = ctx
                    .video
                    .iter()
                    .find(|v| v.pt == pt && v.range.as_ref().is_some_and(|r| in_range(r, ssrc)))
                    .or_else(|| ctx.video.iter().find(|v| v.pt == pt && v.range.is_none()))
                {
                    if let Ok(pkt) = rtp::decode(&plain) {
                        stream.ssrc.store(pkt.ssrc, Ordering::Relaxed);
                        stream.rx.push(super::webrtc_video::VideoPacket {
                            payload: pkt.payload.to_vec(),
                            marker: pkt.marker,
                            seq: pkt.sequence_number,
                            timestamp: pkt.timestamp,
                        });
                    }
                    continue;
                }
                if pt != PT_PCMU
                    && let Ok(pkt) = rtp::decode(&plain)
                    && unrouted.insert((pkt.ssrc, pt))
                {
                    tracing::debug!(ssrc = pkt.ssrc, pt, len, "RTP stream nothing receives");
                }
                // A meeting's mix names who is in it: the speakers.
                if pt == PT_PCMU
                    && let Some(speakers) = &ctx.speakers
                {
                    let csrcs = super::active_speakers::csrcs(&plain);
                    speakers
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .record(&csrcs, std::time::Instant::now());
                }
                if let (Some(tx), Ok(pkt)) = (&ctx.spk_tx, rtp::decode(&plain))
                    && pkt.payload_type == PT_PCMU
                    && !ctx.held.load(Ordering::Relaxed)
                {
                    let pcm: Vec<i16> = pkt
                        .payload
                        .iter()
                        .map(|&b| rtp::ulaw_to_linear(b))
                        .collect();
                    let _ = tx.try_send(pcm);
                }
            }
            _ => {}
        }
    }
}

struct SendCtx {
    socket: Arc<UdpSocket>,
    remote: Arc<Mutex<Option<SocketAddr>>>,
    srtp: Arc<Mutex<Option<srtp::SrtpStreams>>>,
    ssrc: u32,
    stats: Arc<Mutex<WebRtcStats>>,
    mic_rx: Option<std::sync::mpsc::Receiver<Vec<i16>>>,
    muted: Arc<AtomicBool>,
    held: Arc<AtomicBool>,
    /// The telephone-event payload type and the keys to send.
    dtmf: Option<(u8, mpsc::UnboundedReceiver<u8>)>,
}

/// A dial-pad tone being sent: its event, start timestamp and packets sent.
struct Tone {
    event: u8,
    start_ts: u32,
    sent: u32,
}

/// The packets of one tone: DTMF_PACKETS growing ones, the last marked end,
/// then the end packet twice more (RFC 4733 2.5.1.4 asks for three).
fn tone_packet(tone: &Tone) -> Option<(bool, [u8; 4])> {
    let end_at = DTMF_PACKETS - 1;
    if tone.sent > end_at + 2 {
        return None;
    }
    let n = tone.sent.min(end_at);
    let duration = ((n + 1) * rtp::TIMESTAMP_INCREMENT) as u16;
    Some((
        tone.sent == 0,
        dtmf_payload(tone.event, tone.sent >= end_at, duration),
    ))
}

async fn send_loop(mut ctx: SendCtx) {
    let r = random_u64();
    let (mut seq, mut ts) = (r as u16, (r >> 16) as u32);
    let mut tick = tokio::time::interval(Duration::from_millis(rtp::PACKET_INTERVAL_MS));
    let mut tone: Option<Tone> = None;
    loop {
        tick.tick().await;
        let frame = ctx.mic_rx.as_ref().and_then(|rx| rx.try_recv().ok());
        if tone.is_none()
            && let Some((_, rx)) = ctx.dtmf.as_mut()
            && let Ok(event) = rx.try_recv()
        {
            tone = Some(Tone {
                event,
                start_ts: ts,
                sent: 0,
            });
        }
        let packet = match (tone.as_ref().and_then(tone_packet), ctx.dtmf.as_ref()) {
            (Some((first, payload)), Some((pt, _))) => {
                let t = tone.as_mut().map(|t| {
                    t.sent += 1;
                    t.start_ts
                });
                let mut p = rtp::encode(*pt, seq, t.unwrap_or(ts), ctx.ssrc, &payload);
                if first {
                    p[1] |= 0x80;
                }
                p
            }
            _ => {
                tone = None;
                let payload = match frame {
                    Some(samples)
                        if !ctx.muted.load(Ordering::Relaxed)
                            && !ctx.held.load(Ordering::Relaxed) =>
                    {
                        let mut enc: Vec<u8> =
                            samples.iter().map(|&s| rtp::linear_to_ulaw(s)).collect();
                        enc.resize(rtp::SAMPLES_PER_PACKET, 0xFF);
                        enc
                    }
                    _ => rtp::silence_payload(),
                };
                rtp::encode(PT_PCMU, seq, ts, ctx.ssrc, &payload)
            }
        };
        let protected = {
            let mut guard = ctx.srtp.lock().await;
            guard.as_mut().and_then(|c| c.protect(&packet).ok())
        };
        let target = *ctx.remote.lock().await;
        if let (Some(p), Some(to)) = (protected, target)
            && ctx.socket.send_to(&p, to).await.is_ok()
        {
            ctx.stats.lock().await.packets_sent += 1;
        }
        seq = seq.wrapping_add(1);
        ts = ts.wrapping_add(rtp::TIMESTAMP_INCREMENT);
    }
}

/// Blocking DTLS transport over the shared socket: writes go straight out,
/// reads come from the receive loop's DTLS channel.
struct DtlsIo {
    socket: Arc<UdpSocket>,
    peer: SocketAddr,
    rx: std::sync::mpsc::Receiver<Vec<u8>>,
    /// How long a read waits for a datagram.
    wait: Duration,
}

impl std::io::Read for DtlsIo {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self.rx.recv_timeout(self.wait) {
            Ok(pkt) => {
                let n = pkt.len().min(buf.len());
                buf[..n].copy_from_slice(&pkt[..n]);
                Ok(n)
            }
            Err(_) => Err(std::io::ErrorKind::WouldBlock.into()),
        }
    }
}

impl std::io::Write for DtlsIo {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        // Non-blocking send on the shared tokio socket; a full buffer drops
        // the datagram and DTLS retransmits.
        match self.socket.try_send_to(buf, self.peer) {
            Ok(n) => Ok(n),
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(buf.len()),
            Err(e) => Err(e),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// Run the DTLS handshake and export SRTP keys: (our keying material, the
/// peer's), and the session (a meeting's data channel runs in it).
fn dtls_handshake(
    socket: Arc<UdpSocket>,
    peer: SocketAddr,
    rx: std::sync::mpsc::Receiver<Vec<u8>>,
    identity: &DtlsIdentity,
    expected_fingerprint: &str,
    client: bool,
) -> Result<(
    (srtp::SrtpKeyingMaterial, srtp::SrtpKeyingMaterial),
    openssl::ssl::SslStream<DtlsIo>,
)> {
    let mut ctx = SslContext::builder(SslMethod::dtls())?;
    ctx.set_certificate(&identity.cert)?;
    ctx.set_private_key(&identity.key)?;
    ctx.set_tlsext_use_srtp(SRTP_PROFILE)?;
    // PEER also makes a server request the client's certificate.
    // WebRTC peers use self-signed certificates; trust comes from the SDP
    // fingerprint, checked below against the certificate actually presented.
    ctx.set_verify_callback(SslVerifyMode::PEER, |_, _| true);
    let ctx = ctx.build();
    let ssl = openssl::ssl::Ssl::new(&ctx)?;

    let io = DtlsIo {
        socket,
        peer,
        rx,
        wait: Duration::from_millis(200),
    };
    let deadline = std::time::Instant::now() + DTLS_TIMEOUT;
    let mut attempt = if client {
        ssl.connect(io)
    } else {
        ssl.accept(io)
    };
    let stream = loop {
        match attempt {
            Ok(s) => break s,
            Err(HandshakeError::WouldBlock(mid)) => {
                if std::time::Instant::now() > deadline {
                    bail!("DTLS handshake timed out");
                }
                // Let OpenSSL retransmit its flight if its timer expired.
                // SAFETY: the pointer is the live SSL owned by `mid`.
                unsafe {
                    openssl_sys::SSL_ctrl(
                        foreign_types_ptr(mid.ssl()),
                        DTLS_CTRL_HANDLE_TIMEOUT,
                        0,
                        std::ptr::null_mut(),
                    );
                }
                attempt = mid.handshake();
            }
            Err(HandshakeError::SetupFailure(e)) => return Err(e.into()),
            Err(HandshakeError::Failure(mid)) => {
                bail!("DTLS handshake failed: {}", mid.error())
            }
        }
    };

    let ssl = stream.ssl();
    let presented = ssl
        .peer_certificate()
        .context("Peer sent no DTLS certificate")?
        .digest(MessageDigest::sha256())?;
    let hex: Vec<String> = presented.iter().map(|b| format!("{b:02X}")).collect();
    let presented = format!("sha-256 {}", hex.join(":"));
    if !presented.eq_ignore_ascii_case(expected_fingerprint.trim()) {
        bail!("DTLS certificate does not match the SDP fingerprint");
    }
    let profile = ssl
        .selected_srtp_profile()
        .map(|p| p.name().to_string())
        .unwrap_or_default();
    if profile != SRTP_PROFILE {
        bail!("Peer chose unsupported SRTP profile {profile:?}");
    }
    let mut km = [0u8; SRTP_KEYING_LEN];
    ssl.export_keying_material(&mut km, "EXTRACTOR-dtls_srtp", None)?;
    Ok((split_srtp_keys(&km, client), stream))
}

/// The raw `SSL*` behind an `SslRef`.
fn foreign_types_ptr(ssl: &openssl::ssl::SslRef) -> *mut openssl_sys::SSL {
    use foreign_types::ForeignTypeRef;
    ssl.as_ptr()
}

fn random_u64() -> u64 {
    let b = uuid::Uuid::new_v4().into_bytes();
    u64::from_be_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]])
}

/// `DTLS_CTRL_HANDLE_TIMEOUT` (openssl/dtls1.h): run pending retransmits.
const DTLS_CTRL_HANDLE_TIMEOUT: std::os::raw::c_int = 74;

/// RFC 5764 §4.2 layout: client key, server key, client salt, server salt.
/// Returns (local, remote) for the given role.
fn split_srtp_keys(
    km: &[u8; SRTP_KEYING_LEN],
    we_are_client: bool,
) -> (srtp::SrtpKeyingMaterial, srtp::SrtpKeyingMaterial) {
    let mat = |key: &[u8], salt: &[u8]| {
        let mut m = srtp::SrtpKeyingMaterial {
            master_key: [0; 16],
            master_salt: [0; 14],
            tag: 1,
        };
        m.master_key.copy_from_slice(key);
        m.master_salt.copy_from_slice(salt);
        m
    };
    let client = mat(&km[0..16], &km[32..46]);
    let server = mat(&km[16..32], &km[46..60]);
    if we_are_client {
        (client, server)
    } else {
        (server, client)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OFFER: &str = "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1 2\r\n\
m=audio 59842 RTP/SAVP 105 111 0 8 126\r\nc=IN IP4 52.115.84.98\r\n\
a=candidate:1 1 UDP 2130706431 52.115.84.98 59842 typ relay raddr 10.0.0.1 rport 5000\r\n\
a=ice-ufrag:2wdP\r\na=ice-pwd:F8gUHddBXyfqYtixpZlIvgWH\r\n\
a=fingerprint:sha-256 91:15:3E\r\na=setup:actpass\r\na=mid:0\r\na=rtcp-mux\r\n\
m=video 59842 RTP/SAVP 102 104\r\na=mid:1\r\n\
m=x-data 59842 RTP/SAVP 127 126\r\na=mid:2\r\n";

    #[test]
    fn parses_dtls_offer() {
        let o = WebRtcOffer::parse(OFFER).unwrap();
        assert_eq!(o.ice_ufrag, "2wdP");
        assert_eq!(o.fingerprint, "sha-256 91:15:3E");
        assert_eq!(o.audio_mid, "0");
        assert_eq!(o.sections.len(), 3);
        assert_eq!(o.candidates.len(), 1);
        assert!(o.offers_pcmu(OFFER));
        assert!(WebRtcOffer::parse("v=0\r\nm=audio 1 RTP/SAVP 0\r\na=crypto:1 x\r\n").is_none());
    }

    #[test]
    fn a_media_processors_constrained_baseline_line_is_usable() {
        // A meeting answer's camera and sharing lines, as the processor
        // writes them (profile 42C01E): we send with its payload type.
        let line = |mid: &str, label: &str| {
            format!(
                "m=video 3478 RTP/SAVP 107\r\na=label:{label}\r\na=mid:{mid}\r\n\
                 a=rtpmap:107 H264/90000\r\n\
                 a=fmtp:107 profile-level-id=42C01E;packetization-mode=1;max-fs=3600\r\n"
            )
        };
        let sdp = format!(
            "v=0\r\n{}{}",
            line("1", "main-video"),
            line("11", "applicationsharing-video")
        );
        let camera = video_line(&sdp, "1", None).unwrap();
        assert_eq!(
            (camera.payload_type, camera.profile.as_str()),
            (107, "42c01e")
        );
        let sections = vec![
            ("1".to_string(), "video".to_string(), String::new()),
            ("11".to_string(), "video".to_string(), String::new()),
        ];
        let share = offered_sharing(&sdp, &sections, Some(107)).unwrap();
        assert_eq!((share.mid.as_str(), share.payload_type), ("11", 107));
    }

    #[test]
    fn identity_fingerprint_is_sha256_hex() {
        let id = DtlsIdentity::generate().unwrap();
        let hex = id.fingerprint.strip_prefix("sha-256 ").unwrap();
        assert_eq!(hex.split(':').count(), 32);
    }

    #[test]
    fn srtp_keys_follow_rfc5764_layout() {
        let km: [u8; 60] = std::array::from_fn(|i| i as u8);
        let (local, remote) = split_srtp_keys(&km, true);
        assert_eq!(local.master_key[0], 0);
        assert_eq!(remote.master_key[0], 16);
        assert_eq!(local.master_salt[0], 32);
        assert_eq!(remote.master_salt[0], 46);
        let (l2, r2) = split_srtp_keys(&km, false);
        assert_eq!(l2.master_key, remote.master_key);
        assert_eq!(r2.master_salt, local.master_salt);
    }

    #[tokio::test]
    async fn dtls_handshake_between_two_local_endpoints() {
        // Server side uses openssl directly; client is our handshake.
        let a = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let b = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        let (a_addr, b_addr) = (a.local_addr().unwrap(), b.local_addr().unwrap());
        let server_id = DtlsIdentity::generate().unwrap();
        let server_fp = server_id.fingerprint.clone();

        // Server thread.
        let server = std::thread::spawn(move || {
            b.connect(a_addr).unwrap();
            b.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
            struct Io(std::net::UdpSocket);
            impl std::io::Read for Io {
                fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
                    self.0.recv(buf)
                }
            }
            impl std::io::Write for Io {
                fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
                    self.0.send(buf)
                }
                fn flush(&mut self) -> std::io::Result<()> {
                    Ok(())
                }
            }
            let mut ctx = SslContext::builder(SslMethod::dtls()).unwrap();
            ctx.set_certificate(&server_id.cert).unwrap();
            ctx.set_private_key(&server_id.key).unwrap();
            ctx.set_tlsext_use_srtp(SRTP_PROFILE).unwrap();
            let ssl = openssl::ssl::Ssl::new(&ctx.build()).unwrap();
            let s = ssl
                .accept(Io(b))
                .unwrap_or_else(|_| panic!("server DTLS handshake failed"));
            let mut km = [0u8; SRTP_KEYING_LEN];
            s.ssl()
                .export_keying_material(&mut km, "EXTRACTOR-dtls_srtp", None)
                .unwrap();
            km
        });

        // Client: feed datagrams from `a` into the handshake.
        let (tx, rx) = std::sync::mpsc::channel();
        let reader = {
            let a = a.clone();
            tokio::spawn(async move {
                let mut buf = vec![0u8; 2048];
                while let Ok((n, _)) = a.recv_from(&mut buf).await {
                    if tx.send(buf[..n].to_vec()).is_err() {
                        break;
                    }
                }
            })
        };
        let client_id = DtlsIdentity::generate().unwrap();
        let ((local, remote), _session) = tokio::task::spawn_blocking(move || {
            dtls_handshake(a, b_addr, rx, &client_id, &server_fp, true)
        })
        .await
        .unwrap()
        .unwrap();
        reader.abort();
        let server_km = server.join().unwrap();
        let (server_local, server_remote) = split_srtp_keys(&server_km, false);
        assert_eq!(local.master_key, server_remote.master_key);
        assert_eq!(remote.master_key, server_local.master_key);
        assert_eq!(local.master_salt, server_remote.master_salt);
    }

    #[tokio::test]
    async fn dtls_server_role_against_an_openssl_client() {
        let a = Arc::new(UdpSocket::bind("127.0.0.1:0").await.unwrap());
        let b = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        let (a_addr, b_addr) = (a.local_addr().unwrap(), b.local_addr().unwrap());
        let client_id = DtlsIdentity::generate().unwrap();
        let client_fp = client_id.fingerprint.clone();
        let client = std::thread::spawn(move || {
            b.connect(a_addr).unwrap();
            b.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
            struct Io(std::net::UdpSocket);
            impl std::io::Read for Io {
                fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
                    self.0.recv(buf)
                }
            }
            impl std::io::Write for Io {
                fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
                    self.0.send(buf)
                }
                fn flush(&mut self) -> std::io::Result<()> {
                    Ok(())
                }
            }
            let mut ctx = SslContext::builder(SslMethod::dtls()).unwrap();
            ctx.set_certificate(&client_id.cert).unwrap();
            ctx.set_private_key(&client_id.key).unwrap();
            ctx.set_tlsext_use_srtp(SRTP_PROFILE).unwrap();
            ctx.set_verify(SslVerifyMode::NONE);
            let ssl = openssl::ssl::Ssl::new(&ctx.build()).unwrap();
            let s = ssl
                .connect(Io(b))
                .unwrap_or_else(|_| panic!("client DTLS handshake failed"));
            let mut km = [0u8; SRTP_KEYING_LEN];
            s.ssl()
                .export_keying_material(&mut km, "EXTRACTOR-dtls_srtp", None)
                .unwrap();
            km
        });
        let (tx, rx) = std::sync::mpsc::channel();
        let reader = {
            let a = a.clone();
            tokio::spawn(async move {
                let mut buf = vec![0u8; 2048];
                while let Ok((n, _)) = a.recv_from(&mut buf).await {
                    if tx.send(buf[..n].to_vec()).is_err() {
                        break;
                    }
                }
            })
        };
        let server_id = DtlsIdentity::generate().unwrap();
        let ((local, remote), _session) = tokio::task::spawn_blocking(move || {
            dtls_handshake(a, b_addr, rx, &server_id, &client_fp, false)
        })
        .await
        .unwrap()
        .unwrap();
        reader.abort();
        let client_km = client.join().unwrap();
        let (client_local, client_remote) = split_srtp_keys(&client_km, true);
        assert_eq!(local.master_key, client_remote.master_key);
        assert_eq!(remote.master_key, client_local.master_key);
    }

    #[test]
    fn teams_web_video_offers_are_answered_bundled() {
        // The shape of Teams web's video call offer (trimmed, made up keys).
        let offer = "v=0\r\na=group:BUNDLE 0 1 2\r\n\
            m=audio 9 RTP/SAVP 111 0\r\na=ice-ufrag:u\r\na=ice-pwd:pppppppppppppppppppppp\r\n\
            a=fingerprint:sha-256 AA:BB\r\na=setup:actpass\r\na=mid:0\r\na=sendrecv\r\n\
            a=rtpmap:111 opus/48000/2\r\na=rtpmap:0 PCMU/8000\r\na=label:main-audio\r\n\
            m=video 9 RTP/SAVP 102 104 108 103\r\na=mid:1\r\na=sendrecv\r\n\
            a=rtpmap:102 H264/90000\r\na=rtpmap:104 H264/90000\r\na=rtpmap:108 H264/90000\r\na=rtpmap:103 rtx/90000\r\n\
            a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\n\
            a=fmtp:104 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\n\
            a=fmtp:108 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\n\
            a=ssrc-group:FID 3236 2038\r\na=ssrc:3236 cname:x\r\na=label:main-video\r\n\
            m=video 9 RTP/SAVP 102\r\na=mid:2\r\na=sendrecv\r\na=rtpmap:102 H264/90000\r\n\
            a=fmtp:102 packetization-mode=1;profile-level-id=42001f\r\na=label:applicationsharing-video\r\n";
        let o = WebRtcOffer::parse(offer).unwrap();
        let v = o.video.clone().unwrap();
        assert_eq!(
            v,
            OfferedVideo {
                mid: "1".into(),
                payload_type: 108,
                profile: "42e01f".into(),
                ssrc: Some(3236),
                sends: true,
                receives: true
            }
        );
        // A recvonly offer is answered sendonly; an inactive one is no video.
        let recv_only = offer.replacen("a=mid:1\r\na=sendrecv", "a=mid:1\r\na=recvonly", 1);
        let ro = WebRtcOffer::parse(&recv_only).unwrap();
        assert_eq!(ro.video.as_ref().unwrap().answer_direction(), "sendonly");
        let inactive = offer.replacen("a=mid:1\r\na=sendrecv", "a=mid:1\r\na=inactive", 1);
        assert!(WebRtcOffer::parse(&inactive).unwrap().video.is_none());
        let rt = tokio::runtime::Runtime::new().unwrap();
        let local = rt.block_on(LocalAudio::prepare()).unwrap();
        // The sharing line is parsed with its own payload type.
        let sh = o.sharing.clone().unwrap();
        assert_eq!((sh.mid.as_str(), sh.payload_type), ("2", 102));
        let a = local.answer_sdp_with(&o, true);
        // Without the video feature there's no H.264, so the sharing line is
        // turned down; the rest of this test is about taking it.
        if !cfg!(feature = "video") {
            assert!(
                a.contains("a=group:BUNDLE 0 1\r\n") && a.contains("m=video 0 RTP/SAVP 102"),
                "{a}"
            );
            return;
        }
        assert!(a.contains("a=group:BUNDLE 0 1 2\r\n"), "{a}");
        assert!(a.contains("m=video ") && a.contains("a=rtpmap:108 H264/90000"));
        // Screen sharing is accepted (bundled, mirrored, labelled), so a
        // re-offer can turn it on; an inactive offer is answered inactive.
        assert!(
            a.contains("a=mid:2\r\na=sendrecv") && a.contains("a=label:applicationsharing-video")
        );
        assert!(a.contains("a=rtpmap:102 H264/90000"));
        // Each line echoes the offer's profile for its payload type.
        assert!(a.contains(
            "a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f"
        ));
        // No msid: Teams names each stream after its line's label.
        assert!(
            !a.contains("msid:ost ost-") && a.matches("a=x-ssrc-range:").count() == 3,
            "{a}"
        );
        let share_off = offer.replacen("a=mid:2\r\na=sendrecv", "a=mid:2\r\na=inactive", 1);
        assert!(offer_shares(offer) && !offer_shares(&share_off));
        let so = local.answer_sdp_with(&WebRtcOffer::parse(&share_off).unwrap(), true);
        assert!(
            so.contains("a=mid:2\r\na=inactive") && !so.contains("m=video 0 "),
            "{so}"
        );
        // An audio-only answer still takes the screen share.
        let audio_only = local.answer_sdp(&o);
        assert!(!audio_only.contains("a=rtpmap:108"));
        assert!(
            audio_only.contains("a=group:BUNDLE 0 2\r\n")
                && audio_only.contains("a=label:applicationsharing-video"),
            "{audio_only}"
        );
    }

    #[test]
    fn reoffers_are_mirrored_and_holds_seen() {
        let ours = "v=0\r\no=- 77 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1\r\nm=audio 5000 RTP/SAVP 0\r\na=setup:active\r\na=mid:0\r\na=sendrecv\r\nm=video 5000 RTP/SAVP 107\r\na=mid:1\r\na=sendonly\r\nm=video 0 RTP/SAVP 0\r\na=mid:2\r\na=inactive\r\n";
        let hold = "v=0\r\nm=audio 1 RTP/SAVP 0\r\na=setup:actpass\r\na=mid:0\r\na=sendonly\r\nm=video 1 RTP/SAVP 107\r\na=mid:1\r\na=inactive\r\nm=video 1 RTP/SAVP 107\r\na=mid:2\r\na=sendrecv\r\n";
        assert!(offer_holds(hold));
        let a = reanswer(ours, hold, 3, "active");
        assert!(a.contains("o=- 77 3 IN IP4"));
        assert!(a.contains("a=setup:active\r\na=mid:0\r\na=recvonly"), "{a}");
        assert!(a.contains("a=mid:1\r\na=inactive"));
        // A section we rejected stays rejected.
        assert!(a.contains("m=video 0 RTP/SAVP 107\r\nc=IN IP4 0.0.0.0\r\na=mid:2\r\na=inactive"));
        assert!(a.contains("a=group:BUNDLE 0 1\r\n"));
        let resume = hold
            .replace("a=sendonly", "a=sendrecv")
            .replace("a=mid:1\r\na=inactive", "a=mid:1\r\na=sendrecv");
        assert!(!offer_holds(&resume));
        let b = reanswer(ours, &resume, 4, "active");
        assert!(b.contains("a=mid:0\r\na=sendrecv") && b.contains("a=mid:1\r\na=sendrecv"));
    }

    #[test]
    fn the_camera_line_sends_only_with_the_camera_on() {
        let offer = "v=0\r\na=group:BUNDLE 0 1\r\n\
            m=audio 9 RTP/SAVP 0\r\na=ice-ufrag:u\r\na=ice-pwd:pppppppppppppppppppppp\r\n\
            a=fingerprint:sha-256 AA:BB\r\na=setup:actpass\r\na=mid:0\r\na=sendrecv\r\na=rtpmap:0 PCMU/8000\r\n\
            m=video 9 RTP/SAVP 108\r\na=mid:1\r\na=sendrecv\r\na=rtpmap:108 H264/90000\r\n\
            a=fmtp:108 packetization-mode=1;profile-level-id=42e01f\r\na=label:main-video\r\n";
        let o = WebRtcOffer::parse(offer).unwrap();
        let rt = tokio::runtime::Runtime::new().unwrap();
        let mut local = rt.block_on(LocalAudio::prepare()).unwrap();
        // Camera off: we take theirs only (Teams then shows our picture).
        assert!(
            local
                .answer_sdp_with(&o, true)
                .contains("a=mid:1\r\na=recvonly")
        );
        let quiet =
            WebRtcOffer::parse(&offer.replace("a=mid:1\r\na=sendrecv", "a=mid:1\r\na=recvonly"))
                .unwrap();
        assert!(
            local
                .answer_sdp_with(&quiet, true)
                .contains("a=mid:1\r\na=inactive")
        );
        assert!(
            local
                .offer_sdp_with_video()
                .contains("a=mid:1\r\na=recvonly")
        );
        // Camera on: mirrored, and offered sending.
        local.camera_on = true;
        assert!(
            local
                .answer_sdp_with(&o, true)
                .contains("a=mid:1\r\na=sendrecv")
        );
        assert!(
            local
                .answer_sdp_with(&quiet, true)
                .contains("a=mid:1\r\na=sendonly")
        );
        assert!(
            local
                .offer_sdp_with_video()
                .contains("a=mid:1\r\na=sendrecv")
        );
        // A camera re-offer changes only the camera line.
        let ours = local.offer_sdp_with_video();
        let off = media_offer(&ours, &ours, &[("1", "recvonly")], 3);
        assert!(off.contains("a=mid:1\r\na=recvonly") && off.contains("a=mid:2\r\na=inactive"));
    }

    #[test]
    fn reoffer_changes_combine() {
        assert_eq!(Reoffer::Camera(true).apply((false, true)), (true, true));
        assert_eq!(Reoffer::Share(false).apply((true, true)), (true, false));
    }

    #[test]
    fn our_video_offers_carry_an_idle_sharing_line() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let local = rt.block_on(LocalAudio::prepare()).unwrap();
        let o = local.offer_sdp_with_video();
        assert!(o.contains("a=group:BUNDLE 0 1 2\r\n"), "{o}");
        assert!(
            o.contains("a=mid:2\r\na=inactive") && o.contains("a=label:applicationsharing-video")
        );
        assert!(o.contains("a=rtpmap:102 H264/90000") && o.contains("a=rtpmap:107 H264/90000"));
        assert!(!o.contains("msid:ost ost-"));
        // An answer that keeps it lets us share later.
        let answer = o.replace("a=setup:actpass", "a=setup:passive");
        let parsed = WebRtcOffer::parse(&answer).unwrap();
        assert_eq!(
            parsed
                .sharing
                .as_ref()
                .map(|v| (v.mid.as_str(), v.payload_type)),
            Some(("2", 102))
        );
        assert_eq!(parsed.video.as_ref().map(|v| v.payload_type), Some(107));
    }

    #[test]
    fn reoffers_change_only_the_lines_asked() {
        let ours = "v=0\r\no=- 7 3 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 2\r\n\
            m=audio 4000 RTP/SAVP 0\r\na=setup:active\r\na=mid:0\r\na=sendrecv\r\n\
            m=video 0 RTP/SAVP 102\r\nc=IN IP4 0.0.0.0\r\na=mid:1\r\na=inactive\r\n\
            m=video 4000 RTP/SAVP 102\r\na=setup:active\r\na=mid:2\r\na=inactive\r\na=label:applicationsharing-video\r\n";
        let on = media_offer(ours, ours, &[("2", "sendonly")], 4);
        assert!(on.contains("o=- 7 4 IN IP4"), "{on}");
        assert!(on.contains("a=mid:2\r\na=sendonly"));
        assert!(on.contains("a=mid:0\r\na=sendrecv") && on.contains("a=mid:1\r\na=inactive"));
        assert!(on.contains("a=setup:actpass") && !on.contains("a=setup:active"));
        assert_eq!(on.matches("\nm=").count(), 3);
        let off = media_offer(&on, ours, &[("2", "recvonly")], 5);
        assert!(off.contains("a=mid:2\r\na=recvonly") && off.contains("o=- 7 5 "));
        // The answer has to take it: receiving, not rejected.
        let takes = on.replace("a=sendonly", "a=recvonly");
        assert!(answer_receives(&takes, "2"));
        assert!(!answer_receives(
            &takes.replace("a=recvonly", "a=inactive"),
            "2"
        ));
        assert!(!answer_receives(
            &takes.replace("m=video 4000", "m=video 0"),
            "2"
        ));
        assert!(!answer_receives(&takes, "9"));
        // A sharing line an answer turned down comes back from the base.
        let turned_down = ours.replace(
            "m=video 4000 RTP/SAVP 102\r\na=setup:active\r\na=mid:2\r\na=inactive\r\na=label:applicationsharing-video\r\n",
            "m=video 0 RTP/SAVP 34\r\na=inactive\r\n",
        ).replace("a=group:BUNDLE 0 2", "a=group:BUNDLE 0");
        assert!(turned_down.contains("m=video 0 RTP/SAVP 34"));
        let back = media_offer(&turned_down, ours, &[("2", "sendonly")], 6);
        assert!(
            back.contains("m=video 4000 RTP/SAVP 102") && back.contains("a=mid:2\r\na=sendonly"),
            "{back}"
        );
        assert!(back.contains("a=group:BUNDLE 0 2\r\n") && !back.contains("RTP/SAVP 34"));
        assert_eq!(back.matches("\nm=").count(), 3);
    }

    #[test]
    fn reanswers_follow_a_media_processors_new_m_lines() {
        // A meeting we joined with an audio offer; the MP re-offers audio
        // plus a data channel (as when someone else joins).
        let ours = "v=0\r\no=- 5 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\nm=audio 43044 RTP/SAVP 0 101\r\na=setup:actpass\r\na=mid:0\r\na=sendrecv\r\n";
        let reoffer = "v=0\r\no=- 239465 1 IN IP4 127.0.0.1\r\na=group:BUNDLE 0 4\r\nm=audio 3478 RTP/SAVP 96 0 101\r\na=setup:passive\r\na=mid:0\r\nm=x-data 3480 RTP/SAVP 127 126\r\na=setup:passive\r\na=mid:4\r\n";
        let a = reanswer(ours, reoffer, 3, "active");
        assert_eq!(
            a.matches("\nm=").count(),
            2,
            "one answer m-line per offered one: {a}"
        );
        assert!(a.contains("a=setup:active") && !a.contains("actpass"));
        assert!(a.contains("m=x-data 0 RTP/SAVP 127\r\nc=IN IP4 0.0.0.0\r\na=mid:4\r\na=inactive"));
        assert!(a.contains("a=group:BUNDLE 0\r\n") && !a.contains("BUNDLE 0 4"));
    }

    #[test]
    fn dial_pad_tones_follow_rfc4733() {
        assert_eq!(dtmf_event('5'), Some(5));
        assert_eq!(dtmf_event('*'), Some(10));
        assert_eq!(dtmf_event('#'), Some(11));
        assert_eq!(dtmf_event('x'), None);
        let mut t = Tone {
            event: 1,
            start_ts: 0,
            sent: 0,
        };
        let mut packets = Vec::new();
        while let Some(p) = tone_packet(&t) {
            packets.push(p);
            t.sent += 1;
        }
        // 8 growing packets, the last marked end, then 2 more end packets.
        assert_eq!(packets.len(), 10);
        assert!(packets[0].0 && !packets[1].0, "marker only on the first");
        assert_eq!(packets[0].1, [1, 10, 0, 160]);
        assert_eq!(packets[6].1[1] & 0x80, 0);
        for p in &packets[7..] {
            assert_eq!(p.1, [1, 0x80 | 10, 0x05, 0x00], "end, 1280 samples");
        }
        let sdp = "m=audio 9 UDP/TLS/RTP/SAVPF 111 0 126\r\na=rtpmap:111 opus/48000/2\r\na=rtpmap:110 telephone-event/48000\r\na=rtpmap:126 telephone-event/8000\r\n";
        assert_eq!(dtmf_payload_type(sdp), Some(126));
    }

    #[test]
    fn offer_is_audio_only_actpass() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let local = rt.block_on(async {
            let socket = UdpSocket::bind("127.0.0.1:0").await.unwrap();
            LocalAudio {
                socket: Arc::new(socket),
                ufrag: "abcd".into(),
                pwd: "p".repeat(24),
                ssrc: 42,
                video_ssrc: 43,
                share_ssrc: 44,
                receive_video: false,
                camera_on: false,
                dtmf_pt: Some(PT_DTMF_DEFAULT),
                meeting: false,
                candidates: vec![ice::IceCandidate {
                    foundation: "1".into(),
                    component: 1,
                    transport: ice::Transport::Udp,
                    priority: 2130706431,
                    address: "192.0.2.1".into(),
                    port: 5000,
                    candidate_type: ice::CandidateType::Host,
                    raddr: None,
                    rport: None,
                }],
                identity: DtlsIdentity::generate().unwrap(),
            }
        });
        let offer = local.offer_sdp();
        assert!(offer.contains("a=setup:actpass"));
        // Every line is a valid "<type>=<value>" SDP line.
        assert!(
            offer.lines().all(|l| l.len() > 2 && &l[1..2] == "="),
            "{offer}"
        );
        assert!(offer.contains("a=group:BUNDLE 0"));
        assert_eq!(offer.matches("m=").count(), 1);
        let parsed = WebRtcOffer::parse(&offer).unwrap();
        assert_eq!(parsed.setup, "actpass");
        assert_eq!(parsed.ice_ufrag, "abcd");
    }

    #[test]
    fn meeting_offers_have_slots_and_a_data_line_as_teams() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let local = rt.block_on(async {
            let mut l = LocalAudio::prepare().await.unwrap();
            l.meeting = true;
            l
        });
        let o = local.offer_sdp_meeting();
        assert!(o.contains("a=group:BUNDLE 0 1 2 3 4 5 6 7 8 9 10 11 12\r\n"));
        let sections: Vec<&str> = o.split("\r\nm=").skip(1).collect();
        assert_eq!(sections.len(), 13);
        // Our camera, nine receive slots, sharing, data.
        assert!(sections[1].contains("a=mid:1") && sections[1].contains("a=label:main-video"));
        for (i, sec) in sections[2..11].iter().enumerate() {
            assert!(sec.contains(&format!("a=mid:{}\r\n", i + 2)));
            assert!(sec.contains("a=recvonly") && sec.contains("a=label:main-video"));
            assert!(sec.contains("a=x-ssrc-range:1-1"));
            assert!(sec.contains("a=x-signaling-fb:* x-message app send:src recv:src,vc"));
        }
        assert!(sections[11].contains("a=label:applicationsharing-video"));
        assert!(
            sections[12].starts_with("x-data ") && sections[12].contains("a=x-data-protocol:sctp")
        );
        // Every line carries the DTLS fingerprint the data channel uses.
        assert_eq!(o.matches("a=fingerprint:").count(), 13);
    }
}
