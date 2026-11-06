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
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use openssl::asn1::Asn1Time;
use openssl::bn::{BigNum, MsbOption};
use openssl::ec::{EcGroup, EcKey};
use openssl::hash::MessageDigest;
use openssl::nid::Nid;
use openssl::pkey::{PKey, Private};
use openssl::ssl::{HandshakeError, SslContext, SslMethod, SslVerifyMode};
use openssl::x509::{X509NameBuilder, X509};
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, Mutex};

use super::{ice, rtp, srtp};

#[cfg(feature = "audio")]
use super::audio;

/// RTP payload type for PCMU.
const PT_PCMU: u8 = 0;
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
}

/// The peer's main video stream as offered.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OfferedVideo {
    pub mid: String,
    pub payload_type: u8,
    pub ssrc: Option<u32>,
    /// The peer sends video (`sendrecv` or `sendonly`).
    pub sends: bool,
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
/// main-video (else the first video m-line), with an H.264 format we
/// decode. Constrained baseline (42e0..) is preferred, then baseline.
fn offered_video(sdp: &str, sections: &[(String, String, String)]) -> Option<OfferedVideo> {
    let candidates: Vec<&(String, String, String)> =
        sections.iter().filter(|s| s.1 == "video").collect();
    let main = candidates
        .iter()
        .find(|s| section_with_mid(sdp, &s.0).is_some_and(|t| t.contains("a=label:main-video")))
        .or(candidates.first())?;
    let text = section_with_mid(sdp, &main.0)?;
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
    let payload_type = h264
        .iter()
        .find(|pt| usable(pt, "42e0"))
        .or_else(|| h264.iter().find(|pt| usable(pt, "4200")))
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
    let sends = text
        .lines()
        .any(|l| matches!(l.trim_end(), "a=sendrecv" | "a=sendonly"));
    Some(OfferedVideo {
        mid: main.0.clone(),
        payload_type,
        ssrc,
        sends,
    })
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
            } else if let Some(mid) = l.strip_prefix("a=mid:") {
                if let Some((kind, fmts)) = current.take() {
                    sections.push((mid.to_string(), kind, fmts));
                }
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
    /// The answer accepted the peer's video: receive and show it.
    pub receive_video: bool,
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
            receive_video: false,
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
        s.push_str(&self.audio_section(port, &addr, "0", "actpass"));
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

    /// Our main video m-line: receive H.264 with keyframe requests.
    fn video_section(&self, port: u16, addr: &str, mid: &str, setup: &str, pt: u8) -> String {
        let mut s = String::new();
        s.push_str(&format!("m=video {port} RTP/SAVP {pt}\r\n"));
        s.push_str(&format!("c=IN IP4 {addr}\r\n"));
        s.push_str(&format!("a=ice-ufrag:{}\r\n", self.ufrag));
        s.push_str(&format!("a=ice-pwd:{}\r\n", self.pwd));
        s.push_str(&format!("a=fingerprint:{}\r\n", self.identity.fingerprint));
        s.push_str(&format!("a=setup:{setup}\r\n"));
        s.push_str(&format!("a=mid:{mid}\r\n"));
        s.push_str("a=recvonly\r\n");
        s.push_str("a=rtcp-mux\r\n");
        s.push_str(&format!("a=rtpmap:{pt} H264/90000\r\n"));
        s.push_str(&format!(
            "a=fmtp:{pt} level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\n"
        ));
        s.push_str(&format!("a=rtcp-fb:{pt} nack pli\r\n"));
        s.push_str(&format!("a=rtcp-fb:{pt} ccm fir\r\n"));
        s.push_str("a=label:main-video\r\n");
        s
    }

    fn audio_section(&self, port: u16, addr: &str, mid: &str, setup: &str) -> String {
        let mut s = String::new();
        s.push_str(&format!("m=audio {port} RTP/SAVP {PT_PCMU}\r\n"));
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
        s.push_str(&format!("a=x-ssrc-range:{0}-{0}\r\n", self.ssrc));
        s.push_str(&format!("a=ssrc:{} cname:ost\r\n", self.ssrc));
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
        let mut s = String::new();
        s.push_str("v=0\r\n");
        s.push_str(&format!("o=- {session_id} 2 IN IP4 127.0.0.1\r\n"));
        s.push_str("s=-\r\nt=0 0\r\n");
        match video {
            Some(v) => s.push_str(&format!("a=group:BUNDLE {} {}\r\n", offer.audio_mid, v.mid)),
            None => s.push_str(&format!("a=group:BUNDLE {}\r\n", offer.audio_mid)),
        }
        s.push_str("a=msid-semantic: WMS ost\r\n");
        for (mid, kind, proto_fmts) in &offer.sections {
            if *mid == offer.audio_mid {
                s.push_str(&self.audio_section(port, &addr, mid, "active"));
            } else if let Some(v) = video.filter(|v| v.mid == *mid) {
                s.push_str(&self.video_section(port, &addr, mid, "active", v.payload_type));
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
    /// The peer's video, decoded and published as the "remote" frame.
    #[cfg(feature = "video")]
    _video_rx: Option<Arc<super::webrtc_video::VideoReceiver>>,
    muted: Arc<AtomicBool>,
    stats: Arc<Mutex<WebRtcStats>>,
    #[cfg(feature = "audio")]
    _capture: Option<audio::AudioCapture>,
    #[cfg(feature = "audio")]
    _playback: Option<audio::AudioPlayback>,
}

impl Drop for WebRtcAudioSession {
    fn drop(&mut self) {
        for t in &self.tasks {
            t.abort();
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

    pub async fn stats(&self) -> WebRtcStats {
        *self.stats.lock().await
    }

    /// Answerer side: ICE controlled, DTLS client (we answered `active`).
    pub async fn start(local: LocalAudio, offer: WebRtcOffer) -> Result<Self> {
        Self::start_with_role(local, offer, false, true).await
    }

    /// Offerer side: ICE controlling; DTLS role from the peer's answer
    /// (`active` makes us the server, `passive` the client).
    pub async fn start_as_offerer(local: LocalAudio, answer: WebRtcOffer) -> Result<Self> {
        let dtls_client = answer.setup.eq_ignore_ascii_case("passive");
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

        // The peer's video, when the answer accepted it.
        #[cfg(feature = "video")]
        let video_rx = offer
            .video
            .as_ref()
            .filter(|v| local.receive_video && v.sends)
            .map(|v| {
                (
                    v.payload_type,
                    Arc::new(super::webrtc_video::VideoReceiver::start("remote")),
                )
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
            #[cfg(feature = "video")]
            video: video_rx.clone(),
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
        let keys = {
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

        let muted = Arc::new(AtomicBool::new(false));

        // Send audio every 20 ms.
        tasks.push(tokio::spawn(send_loop(
            socket.clone(),
            remote.clone(),
            srtp_ctx.clone(),
            local.ssrc,
            stats.clone(),
            mic_rx,
            muted.clone(),
        )));

        // Ask for a keyframe (RTCP PLI) whenever the video decoder needs one.
        #[cfg(feature = "video")]
        if let Some((_, rx)) = &video_rx {
            let (socket, srtp, want) =
                (socket.clone(), srtp_ctx.clone(), rx.keyframe_wanted.clone());
            let (ours, theirs) = (
                local.video_ssrc,
                offer.video.as_ref().and_then(|v| v.ssrc).unwrap_or(0),
            );
            tasks.push(tokio::spawn(async move {
                loop {
                    if want.load(Ordering::Relaxed) {
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

        Ok(Self {
            tasks,
            #[cfg(feature = "video")]
            _video_rx: video_rx.map(|(_, rx)| rx),
            muted,
            stats,
            #[cfg(feature = "audio")]
            _capture: capture,
            #[cfg(feature = "audio")]
            _playback: playback,
        })
    }
}

struct RecvCtx {
    socket: Arc<UdpSocket>,
    local_pwd: String,
    dtls_tx: std::sync::mpsc::Sender<Vec<u8>>,
    peer_tx: mpsc::Sender<SocketAddr>,
    srtp: Arc<Mutex<Option<srtp::SrtpStreams>>>,
    stats: Arc<Mutex<WebRtcStats>>,
    spk_tx: Option<std::sync::mpsc::SyncSender<Vec<i16>>>,
    /// The video payload type and its receiver.
    #[cfg(feature = "video")]
    video: Option<(u8, Arc<super::webrtc_video::VideoReceiver>)>,
}

async fn recv_loop(ctx: RecvCtx) {
    let mut buf = vec![0u8; 2048];
    let mut announced = false;
    loop {
        let Ok((len, from)) = ctx.socket.recv_from(&mut buf).await else {
            continue;
        };
        let data = &buf[..len];
        match data.first().copied().unwrap_or(255) {
            0..=3 => {
                if ice::is_stun_request(data) {
                    if let Some(txn) = ice::get_transaction_id(data) {
                        let resp =
                            ice::build_binding_response(&txn, from, Some(ctx.local_pwd.as_bytes()));
                        let _ = ctx.socket.send_to(&resp, from).await;
                    }
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
                    continue;
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
                #[cfg(feature = "video")]
                if let Some((vpt, rx)) = &ctx.video {
                    if pt == *vpt {
                        if let Ok(pkt) = rtp::decode(&plain) {
                            rx.push(super::webrtc_video::VideoPacket {
                                payload: pkt.payload.to_vec(),
                                marker: pkt.marker,
                                seq: pkt.sequence_number,
                                timestamp: pkt.timestamp,
                            });
                        }
                        continue;
                    }
                }
                if let (Some(tx), Ok(pkt)) = (&ctx.spk_tx, rtp::decode(&plain)) {
                    if pkt.payload_type == PT_PCMU {
                        let pcm: Vec<i16> = pkt
                            .payload
                            .iter()
                            .map(|&b| rtp::ulaw_to_linear(b))
                            .collect();
                        let _ = tx.try_send(pcm);
                    }
                }
            }
            _ => {}
        }
    }
}

async fn send_loop(
    socket: Arc<UdpSocket>,
    remote: Arc<Mutex<Option<SocketAddr>>>,
    srtp_ctx: Arc<Mutex<Option<srtp::SrtpStreams>>>,
    ssrc: u32,
    stats: Arc<Mutex<WebRtcStats>>,
    mic_rx: Option<std::sync::mpsc::Receiver<Vec<i16>>>,
    muted: Arc<AtomicBool>,
) {
    let r = random_u64();
    let (mut seq, mut ts) = (r as u16, (r >> 16) as u32);
    let mut tick = tokio::time::interval(Duration::from_millis(rtp::PACKET_INTERVAL_MS));
    loop {
        tick.tick().await;
        let frame = mic_rx.as_ref().and_then(|rx| rx.try_recv().ok());
        let payload = match frame {
            Some(samples) if !muted.load(Ordering::Relaxed) => {
                let mut enc: Vec<u8> = samples.iter().map(|&s| rtp::linear_to_ulaw(s)).collect();
                enc.resize(rtp::SAMPLES_PER_PACKET, 0xFF);
                enc
            }
            _ => rtp::silence_payload(),
        };
        let packet = rtp::encode(PT_PCMU, seq, ts, ssrc, &payload);
        let protected = {
            let mut guard = srtp_ctx.lock().await;
            guard.as_mut().and_then(|c| c.protect(&packet).ok())
        };
        let target = *remote.lock().await;
        if let (Some(p), Some(to)) = (protected, target) {
            if socket.send_to(&p, to).await.is_ok() {
                stats.lock().await.packets_sent += 1;
            }
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
}

impl std::io::Read for DtlsIo {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self.rx.recv_timeout(Duration::from_millis(200)) {
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

/// Run the DTLS client handshake and export SRTP keys:
/// (our keying material, the peer's keying material).
fn dtls_handshake(
    socket: Arc<UdpSocket>,
    peer: SocketAddr,
    rx: std::sync::mpsc::Receiver<Vec<u8>>,
    identity: &DtlsIdentity,
    expected_fingerprint: &str,
    client: bool,
) -> Result<(srtp::SrtpKeyingMaterial, srtp::SrtpKeyingMaterial)> {
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

    let io = DtlsIo { socket, peer, rx };
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
    Ok(split_srtp_keys(&km, client))
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

    const OFFER: &str =
        "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1 2\r\n\
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
        let (local, remote) = tokio::task::spawn_blocking(move || {
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
        let (local, remote) = tokio::task::spawn_blocking(move || {
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
            a=fmtp:102 packetization-mode=1;profile-level-id=42e01f\r\na=label:applicationsharing-video\r\n";
        let o = WebRtcOffer::parse(offer).unwrap();
        let v = o.video.clone().unwrap();
        assert_eq!(
            v,
            OfferedVideo {
                mid: "1".into(),
                payload_type: 108,
                ssrc: Some(3236),
                sends: true
            }
        );
        let rt = tokio::runtime::Runtime::new().unwrap();
        let local = rt.block_on(LocalAudio::prepare()).unwrap();
        let a = local.answer_sdp_with(&o, true);
        assert!(a.contains("a=group:BUNDLE 0 1\r\n"));
        assert!(a.contains("m=video ") && a.contains("a=rtpmap:108 H264/90000"));
        assert!(
            a.contains("a=mid:2\r\na=inactive"),
            "screen sharing stays off"
        );
        assert!(!local.answer_sdp(&o).contains("a=rtpmap:108"));
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
                receive_video: false,
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
}
