//! Teams' media control plane (MCP): JSON messages to and from a meeting's
//! media processor over the call's "main-channel" data channel. Video
//! subscriptions (source requests), bandwidth estimates, dominant speaker
//! history and our camera's layer requests travel here. Format captured
//! from Teams; see docs/spec/meeting-video.md.

use serde_json::{Value, json};

/// The media processor's MCP id.
pub const PROCESSOR_ID: i32 = -4;
/// Ours until the processor's `ack` names us.
const UNASSIGNED_ID: i32 = -2;
const HEADER_LEN: usize = 16;
/// Bytes 1–2 of every header.
const MAGIC: [u8; 2] = [0x0f, 0x92];
/// What we take part in, as Teams declares it in `syn`.
const CLIENT_CAPABILITIES: [&str; 7] = ["dsh", "bwe", "sr", "ssbwe", "leave", "vdclc", "heartbeat"];

/// One message's header fields.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub seq: u16,
    pub from: i32,
    pub to: i32,
}

/// A frame: the 16-byte header, then a JSON array holding the message.
pub fn encode(h: Header, message: &Value) -> Vec<u8> {
    let mut f = Vec::with_capacity(HEADER_LEN + 128);
    f.push(HEADER_LEN as u8);
    f.extend_from_slice(&MAGIC);
    f.extend_from_slice(&h.seq.to_be_bytes());
    f.push(0);
    f.extend_from_slice(&h.from.to_be_bytes());
    f.push(1);
    f.extend_from_slice(&h.to.to_be_bytes());
    f.push(1);
    f.extend_from_slice(json!([message]).to_string().as_bytes());
    f
}

/// A frame's header and messages, or None for something else.
pub fn decode(frame: &[u8]) -> Option<(Header, Vec<Value>)> {
    let len = usize::from(*frame.first()?);
    if len < HEADER_LEN || frame.len() < len || frame[1..3] != MAGIC {
        return None;
    }
    let i32_at =
        |i: usize| i32::from_be_bytes([frame[i], frame[i + 1], frame[i + 2], frame[i + 3]]);
    let header = Header {
        seq: u16::from_be_bytes([frame[3], frame[4]]),
        from: i32_at(6),
        to: i32_at(11),
    };
    let body: Value = serde_json::from_slice(&frame[len..]).ok()?;
    let messages = match body {
        Value::Array(list) => list,
        other => vec![other],
    };
    Some((header, messages))
}

/// Bytes 1–2 of the frames that carry the meeting's speech recognition
/// (the transcript and live captions).
const TRANSCRIPT_MAGIC: [u8; 2] = [0x0b, 0x83];

/// A speech recognition frame's JSON (`{"version": "1.1",
/// "recognitionResults": […]}` or `{"events": […]}`): the media processor
/// sends them on the same channel with their own header, the JSON from its
/// first `{`.
pub fn transcript_payload(frame: &[u8]) -> Option<Value> {
    if frame.len() < 4 || frame[1..3] != TRANSCRIPT_MAGIC {
        return None;
    }
    let start = frame.iter().skip(3).position(|&b| b == b'{')? + 3;
    serde_json::from_slice(&frame[start..]).ok()
}

/// What the media processor told us.
#[derive(Debug, Clone, PartialEq)]
pub enum Incoming {
    /// The session is up; we are `id` from now on.
    Ack {
        id: i32,
    },
    Heartbeat,
    /// Downlink estimate, bits per second (`video_bw`: the video share).
    Bandwidth {
        total: u64,
        video: Option<u64>,
    },
    /// The answer to source request `seq`: "ok", "duplicate", …
    SourceResult {
        seq: u64,
        result: String,
    },
    /// Dominant speaker history, most recent first (audio source ids).
    DominantSpeakers(Vec<i64>),
    /// What to send of our stream `stream`: one fmtp-style string per layer.
    SendLayers {
        stream: i64,
        layers: Vec<String>,
    },
    /// Speech recognition (transcript or captions) results and events.
    Transcript(Value),
    Other(Value),
}

/// One video source request: show `source_id` (a roster `main-video`
/// sourceId) in our receive slot `stream_msid` (the slot's
/// x-source-streamid), at most `max_fs` macroblocks per frame at
/// `max_fps` frames a second.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceRequest {
    pub source_id: i64,
    pub stream_msid: i64,
    pub max_fs: u32,
    pub max_mbps: u32,
    pub max_fps: u32,
    /// H.264 profile-level-id we decode, e.g. 0x42e01f.
    pub profile_level_id: u32,
}

/// Our side of an MCP session.
#[derive(Debug)]
pub struct Session {
    id: i32,
    seq: u16,
    /// Source requests are numbered across the call (Teams keeps one
    /// counter for all of its video control messages).
    request_seq: u64,
}

impl Default for Session {
    fn default() -> Self {
        Self::new()
    }
}

impl Session {
    pub fn new() -> Self {
        Self {
            id: UNASSIGNED_ID,
            seq: 0,
            request_seq: 0,
        }
    }

    /// Whether the processor has acknowledged us.
    pub fn is_up(&self) -> bool {
        self.id != UNASSIGNED_ID
    }

    fn frame(&mut self, message: &Value) -> Vec<u8> {
        let h = Header {
            seq: self.seq,
            from: self.id,
            to: PROCESSOR_ID,
        };
        self.seq = self.seq.wrapping_add(1);
        encode(h, message)
    }

    /// The opening `syn`; a new data channel starts a new session.
    pub fn syn(&mut self) -> Vec<u8> {
        self.id = UNASSIGNED_ID;
        self.seq = 0;
        self.frame(&json!({"type": "syn", "client_capabilities": CLIENT_CAPABILITIES}))
    }

    pub fn heartbeat(&mut self) -> Vec<u8> {
        self.frame(&json!({"type": "heartbeat", "state": 0}))
    }

    /// A source request; returns its sequence number and the frame.
    pub fn source_request(&mut self, r: SourceRequest) -> (u64, Vec<u8>) {
        self.request_seq += 1;
        let seq = self.request_seq;
        let frame = self.frame(&json!({
            "type": "sr",
            "controlVideoStreaming": {
                "sequenceNumber": seq,
                "controlInfo": {
                    "sourceId": r.source_id,
                    "streamMsid": r.stream_msid,
                    "fmtParams": [{
                        "max-fs": r.max_fs,
                        "max-mbps": r.max_mbps,
                        "max-fps": r.max_fps,
                        "profile-level-id": format!("{:06x}", r.profile_level_id),
                    }],
                },
            },
        }));
        (seq, frame)
    }

    /// Our send-side estimate for one of our streams (`ssbwe`).
    pub fn send_bandwidth(&mut self, stream_msid: i64, bits_per_second: u64) -> Vec<u8> {
        self.frame(&json!({
            "type": "ssbwe",
            "BwMessage": [{"streamMsid": stream_msid, "bw": bits_per_second}],
        }))
    }

    /// Read a frame from the processor.
    pub fn receive(&mut self, frame: &[u8]) -> Vec<Incoming> {
        if let Some(t) = transcript_payload(frame) {
            return vec![Incoming::Transcript(t)];
        }
        let Some((header, messages)) = decode(frame) else {
            let hex: String = frame.iter().take(32).map(|b| format!("{b:02x}")).collect();
            tracing::debug!(len = frame.len(), %hex, "MCP frame not decoded");
            return Vec::new();
        };
        messages
            .into_iter()
            .map(|m| {
                let s = |k: &str| {
                    m.get(k)
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .to_string()
                };
                match m.get("type").and_then(Value::as_str).unwrap_or_default() {
                    "ack" => {
                        self.id = header.to;
                        Incoming::Ack { id: header.to }
                    }
                    "heartbeat" => Incoming::Heartbeat,
                    "bwe" => Incoming::Bandwidth {
                        total: m.get("bw").and_then(Value::as_u64).unwrap_or_default(),
                        video: m.get("video_bw").and_then(Value::as_u64),
                    },
                    "sr_res" => Incoming::SourceResult {
                        seq: m
                            .get("sequenceNumber")
                            .and_then(Value::as_u64)
                            .unwrap_or_default(),
                        result: s("result"),
                    },
                    "dsh" => Incoming::DominantSpeakers(dominant_speakers(&m)),
                    "vdclc" => Incoming::SendLayers {
                        stream: m
                            .get("sourceId")
                            .and_then(Value::as_i64)
                            .unwrap_or_default(),
                        layers: m
                            .get("fmtParamsList")
                            .and_then(Value::as_array)
                            .into_iter()
                            .flatten()
                            .filter_map(|l| l.as_str().map(str::to_string))
                            .collect(),
                    },
                    _ => Incoming::Other(m),
                }
            })
            .collect()
    }
}

/// The source ids of a `dsh` message, most recent first: every integer it
/// carries under a history or speaker key (its exact shape varies by
/// processor version, so it is read loosely and logged in full).
fn dominant_speakers(m: &Value) -> Vec<i64> {
    tracing::debug!(target: "teams_cli::calling::mcp", "dsh {m}");
    let mut out = Vec::new();
    for key in ["dominantSpeakerHistory", "history", "dsh", "sourceIds"] {
        if let Some(list) = m.get(key).and_then(Value::as_array) {
            out.extend(list.iter().filter_map(Value::as_i64));
        }
    }
    if out.is_empty()
        && let Some(id) = m.get("dominantSpeaker").and_then(Value::as_i64)
    {
        out.push(id);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_speech_recognition_frames() {
        // Captured: 10 0b 83, the sequence, then the JSON.
        let mut f = vec![0x10, 0x0b, 0x83, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x9e, 0x7a, 0x00];
        f.extend_from_slice(br#"{"version":"1.1","recognitionResults":[{"text":"Front.","isFinal":false}]}"#);
        let v = transcript_payload(&f).unwrap();
        assert_eq!(v["recognitionResults"][0]["text"], "Front.");
        let mut s = Session::new();
        assert!(matches!(s.receive(&f).as_slice(), [Incoming::Transcript(_)]));
        assert!(transcript_payload(&encode(Header { seq: 1, from: -4, to: 1 }, &json!({"type": "heartbeat"}))).is_none());
    }

    fn hex(s: &str) -> Vec<u8> {
        s.split_whitespace()
            .map(|b| u8::from_str_radix(b, 16).unwrap())
            .collect()
    }

    #[test]
    fn syn_matches_teams_byte_for_byte() {
        // As Teams web sent it on a new main-channel.
        let mut want = hex("10 0f 92 00 00 00 ff ff ff fe 01 ff ff ff fc 01");
        want.extend_from_slice(
            br#"[{"client_capabilities":["dsh","bwe","sr","ssbwe","leave","vdclc","heartbeat"],"type":"syn"}]"#,
        );
        let mut s = Session::new();
        let got = s.syn();
        assert_eq!(got[..16], want[..16]);
        let (_, m) = decode(&got).unwrap();
        let (_, w) = decode(&want).unwrap();
        assert_eq!(m, w);
    }

    #[test]
    fn ack_assigns_our_id_and_later_frames_carry_it() {
        let mut s = Session::new();
        s.syn();
        let mut ack = hex("10 0f 92 65 07 00 ff ff ff fc 01 00 00 1e 5c 01");
        ack.extend_from_slice(br#"[{"receive_capabilities":["sr","ssbwe","leave","heartbeat"],"send_capabilities":["bwe","dsh","sr_res","heartbeat","vdclc"],"type":"ack"}]"#);
        assert_eq!(s.receive(&ack), vec![Incoming::Ack { id: 0x1e5c }]);
        assert!(s.is_up());
        let (seq, sr) = s.source_request(SourceRequest {
            source_id: 2244,
            stream_msid: 7761,
            max_fs: 8160,
            max_mbps: 244_800,
            max_fps: 3000,
            profile_level_id: 0x64001f,
        });
        assert_eq!(seq, 1);
        // Teams' frame for the same request.
        let mut want = hex("10 0f 92 00 01 00 00 00 1e 5c 01 ff ff ff fc 01");
        want.extend_from_slice(br#"[{"type":"sr","controlVideoStreaming":{"sequenceNumber":1,"controlInfo":{"sourceId":2244,"streamMsid":7761,"fmtParams":[{"max-fs":8160,"max-mbps":244800,"max-fps":3000,"profile-level-id":"64001f"}]}}}]"#);
        assert_eq!(sr[..16], want[..16]);
        assert_eq!(decode(&sr).unwrap().1, decode(&want).unwrap().1);
    }

    #[test]
    fn reads_the_processors_messages() {
        let mut s = Session::new();
        let frame = |json: &str| {
            let mut f = hex("10 0f 92 65 09 00 ff ff ff fc 01 00 00 1e 5c 01");
            f.extend_from_slice(json.as_bytes());
            f
        };
        assert_eq!(
            s.receive(&frame(
                r#"[{"result":"ok","sequenceNumber":43,"type":"sr_res"}]"#
            )),
            vec![Incoming::SourceResult {
                seq: 43,
                result: "ok".into()
            }]
        );
        assert_eq!(
            s.receive(&frame(
                r#"[{"bw":1500000,"type":"bwe","video_bw":1271458}]"#
            )),
            vec![Incoming::Bandwidth {
                total: 1_500_000,
                video: Some(1_271_458)
            }]
        );
        assert_eq!(
            s.receive(&frame(r#"[{"fmtParamsList":["KeyFrame=1;max-br=586;rid=1"],"sourceId":7761,"type":"vdclc"}]"#)),
            vec![Incoming::SendLayers { stream: 7761, layers: vec!["KeyFrame=1;max-br=586;rid=1".into()] }]
        );
        assert_eq!(
            s.receive(&frame(r#"[{"state":0,"type":"heartbeat"}]"#)),
            vec![Incoming::Heartbeat]
        );
        assert!(s.receive(b"not a frame").is_empty());
    }
}
