//! Teams' media control plane (MCP): JSON messages to and from a meeting's
//! media processor over the call's "main-channel" data channel. Video
//! subscriptions (source requests), bandwidth estimates, dominant speaker
//! history and our camera's layer requests travel here. Format captured
//! from Teams; see docs/spec/meeting-video.md. The same channel carries
//! the meeting's speech recognition and real-time text, each under its
//! own data id ([`super::datapacket`]).

use serde_json::{Value, json};

use super::datapacket::{self, Depacketizer};

/// The media processor's MCP id.
pub const PROCESSOR_ID: i32 = -4;
/// Ours until the processor's `ack` names us.
const UNASSIGNED_ID: i32 = -2;
/// The data ids of what we read and send on the channel.
pub const MCP_DATA_ID: u8 = 18;
/// The meeting's speech recognition (the transcript and live captions).
pub const TRANSCRIPT_DATA_ID: u8 = 3;
/// Real-time text (Teams' RTT handler).
pub const RTT_DATA_ID: u8 = 24;
/// An MCP payload's first byte: its format's version.
const PAYLOAD_VERSION: u8 = 1;
/// What we take part in, as Teams declares it in `syn`.
const CLIENT_CAPABILITIES: [&str; 7] = ["dsh", "bwe", "sr", "ssbwe", "leave", "vdclc", "heartbeat"];

/// One MCP message's packet fields.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub seq: u16,
    pub from: i32,
    pub to: i32,
}

/// An MCP packet: the version byte, then a JSON array holding the message.
pub fn encode(h: Header, message: &Value) -> Vec<u8> {
    let mut payload = vec![PAYLOAD_VERSION];
    payload.extend_from_slice(json!([message]).to_string().as_bytes());
    datapacket::packetize(MCP_DATA_ID, h.seq, h.from as u32, &[h.to as u32], &payload)
}

/// An MCP packet's header and messages, or None for something else.
pub fn decode(packet: &[u8]) -> Option<(Header, Vec<Value>)> {
    let m = Depacketizer::new().push(packet)?;
    let seq = u16::from_be_bytes([packet[3], packet[4]]);
    mcp_messages(&m).map(|messages| (header(seq, &m), messages))
}

fn header(seq: u16, m: &datapacket::Message) -> Header {
    Header {
        seq,
        from: m.source_id as i32,
        to: m.recipients.first().map_or(0, |r| *r as i32),
    }
}

fn mcp_messages(m: &datapacket::Message) -> Option<Vec<Value>> {
    if m.data_id != MCP_DATA_ID || m.payload.first() != Some(&PAYLOAD_VERSION) {
        return None;
    }
    Some(match serde_json::from_slice(&m.payload[1..]).ok()? {
        Value::Array(list) => list,
        other => vec![other],
    })
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
    /// Someone's real-time text: what they typed since their last (`s`:
    /// characters, a backspace removing one, a newline ending the line),
    /// from their data source.
    RealTimeText { source: u32, text: String },
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
    /// Real-time text's own packet sequence.
    rtt_seq: u16,
    packets: Depacketizer,
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
            rtt_seq: 0,
            packets: Depacketizer::new(),
            request_seq: 0,
        }
    }

    /// Whether the processor has acknowledged us.
    pub fn is_up(&self) -> bool {
        self.id != UNASSIGNED_ID
    }

    /// Our data source id, once the processor named it.
    pub fn source_id(&self) -> Option<u32> {
        self.is_up().then_some(self.id as u32)
    }

    /// What we typed for real-time text since the last (Teams' `{s}`),
    /// to everyone; None until the session is up.
    pub fn real_time_text(&mut self, text: &str) -> Option<Vec<u8>> {
        let source = self.source_id()?;
        let packet = datapacket::packetize(
            RTT_DATA_ID,
            self.rtt_seq,
            source,
            &[],
            json!({ "s": text }).to_string().as_bytes(),
        );
        self.rtt_seq = self.rtt_seq.wrapping_add(1);
        Some(packet)
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
        self.rtt_seq = 0;
        self.packets = Depacketizer::new();
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

    /// Read a packet from the channel (a whole message once its last
    /// piece is in).
    pub fn receive(&mut self, packet: &[u8]) -> Vec<Incoming> {
        let seq = if packet.len() > 4 { u16::from_be_bytes([packet[3], packet[4]]) } else { 0 };
        let Some(m) = self.packets.push(packet) else {
            if datapacket::data_id(packet).is_none() {
                let hex: String = packet.iter().take(32).map(|b| format!("{b:02x}")).collect();
                tracing::debug!(len = packet.len(), %hex, "data channel packet not read");
            }
            return Vec::new();
        };
        match m.data_id {
            TRANSCRIPT_DATA_ID => {
                return serde_json::from_slice(&m.payload)
                    .map(|v| vec![Incoming::Transcript(v)])
                    .unwrap_or_default();
            }
            RTT_DATA_ID => {
                // Ours shouldn't come back; if one does, Teams has shown it
                // already, as it was typed.
                if Some(m.source_id) == self.source_id() {
                    return Vec::new();
                }
                return serde_json::from_slice::<Value>(&m.payload)
                    .ok()
                    .and_then(|v| v.get("s")?.as_str().map(str::to_string))
                    .map(|text| vec![Incoming::RealTimeText { source: m.source_id, text }])
                    .unwrap_or_default();
            }
            _ => {}
        }
        let header = header(seq, &m);
        let Some(messages) = mcp_messages(&m) else {
            tracing::debug!(data_id = m.data_id, len = m.payload.len(), "data channel message not read");
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
        // Captured: 10 0b 83 (data id 3), the sequence, no more pieces,
        // the sender's source, no recipients, then the JSON.
        let mut f = vec![0x10, 0x0b, 0x83, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x9e, 0x7a, 0x00];
        f.extend_from_slice(br#"{"version":"1.1","recognitionResults":[{"text":"Front.","isFinal":false}]}"#);
        let mut s = Session::new();
        match s.receive(&f).as_slice() {
            [Incoming::Transcript(v)] => assert_eq!(v["recognitionResults"][0]["text"], "Front."),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn real_time_text_goes_to_everyone_from_our_source() {
        let mut s = Session::new();
        assert!(s.real_time_text("h").is_none(), "not before the ack");
        s.syn();
        let mut ack = hex("10 0f 92 65 07 00 ff ff ff fc 01 00 00 0c 7b 01");
        ack.extend_from_slice(br#"[{"type":"ack"}]"#);
        s.receive(&ack);
        let p = s.real_time_text("hi").unwrap();
        assert_eq!(&p[..11], &hex("10 0b 98 00 00 00 00 00 0c 7b 00")[..]);
        assert_eq!(&p[11..], br#"{"s":"hi"}"#);
        assert_eq!(s.real_time_text("\u{8}").unwrap()[4], 1, "its own sequence");
        // Someone else's, and ours (not shown twice).
        let theirs = datapacket::packetize(RTT_DATA_ID, 4, 1030, &[], br#"{"s":"Hello"}"#);
        assert_eq!(
            s.receive(&theirs),
            vec![Incoming::RealTimeText { source: 1030, text: "Hello".into() }]
        );
        assert!(s.receive(&p).is_empty());
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
