//! The packets on a meeting's "main-channel" data channel, as Teams' media
//! stack frames them (calling-pluginless packetizer): an 11-byte header
//! plus 4 bytes per recipient, then the payload.
//!
//! - byte 0: 0x10 (version 1) with the header length's high 4 bits;
//! - byte 1: the header length's low 8 bits;
//! - byte 2: 0x80 on a message's first packet, then the data id (6 bits):
//!   18 the media control plane, 3 speech recognition, 24 real-time text;
//! - bytes 3–4: the sender's packet sequence for that data id;
//! - byte 5: how many more packets the message takes (0: it's whole);
//! - bytes 6–9: the sender's data source id;
//! - byte 10: how many recipients follow (none: everyone), 4 bytes each.
//!
//! A message split into several packets carries its source and recipients
//! in the first; the rest follow in sequence.

use std::collections::HashMap;

const BASE_HEADER_LEN: usize = 11;
const VERSION: u8 = 0x10;
const START: u8 = 0x80;
const DATA_ID_MASK: u8 = 0x3f;

/// A whole message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub data_id: u8,
    /// The sender's data source id.
    pub source_id: u32,
    /// Who it is for (empty: everyone).
    pub recipients: Vec<u32>,
    pub payload: Vec<u8>,
}

/// One packet holding a whole message.
pub fn packetize(
    data_id: u8,
    seq: u16,
    source_id: u32,
    recipients: &[u32],
    payload: &[u8],
) -> Vec<u8> {
    let header_len = BASE_HEADER_LEN + recipients.len() * 4;
    let mut p = Vec::with_capacity(header_len + payload.len());
    p.push(VERSION | ((header_len >> 8) as u8 & 0x0f));
    p.push((header_len & 0xff) as u8);
    p.push(START | (data_id & DATA_ID_MASK));
    p.extend_from_slice(&seq.to_be_bytes());
    p.push(0);
    p.extend_from_slice(&source_id.to_be_bytes());
    p.push(recipients.len() as u8);
    for r in recipients {
        p.extend_from_slice(&r.to_be_bytes());
    }
    p.extend_from_slice(payload);
    p
}

/// A packet's data id, or None for something that isn't a packet.
pub fn data_id(packet: &[u8]) -> Option<u8> {
    (packet.len() >= BASE_HEADER_LEN && packet[0] & 0xf0 == VERSION)
        .then(|| packet[2] & DATA_ID_MASK)
}

/// A message still arriving in pieces.
#[derive(Debug, Default)]
struct Pending {
    remaining: u8,
    next_seq: u16,
    source_id: u32,
    recipients: Vec<u32>,
    /// Packets taken so far.
    parts: usize,
    payload: Vec<u8>,
}

/// Puts messages back together, per data id.
#[derive(Debug, Default)]
pub struct Depacketizer {
    pending: HashMap<u8, Pending>,
}

impl Depacketizer {
    pub fn new() -> Self {
        Self::default()
    }

    /// Take a packet; returns the message it completes.
    pub fn push(&mut self, packet: &[u8]) -> Option<Message> {
        let data_id = data_id(packet)?;
        let header_len = (usize::from(packet[0] & 0x0f) << 8) | usize::from(packet[1]);
        if header_len < BASE_HEADER_LEN || packet.len() < header_len {
            return None;
        }
        let seq = u16::from_be_bytes([packet[3], packet[4]]);
        let p = if packet[2] & START != 0 {
            let count = usize::from(packet[10]);
            if BASE_HEADER_LEN + count * 4 > header_len {
                return None;
            }
            if self.pending.get(&data_id).is_some_and(|p| p.parts > 0) {
                tracing::debug!(data_id, seq, "data channel message left unfinished");
            }
            let at = |i: usize| {
                u32::from_be_bytes([packet[i], packet[i + 1], packet[i + 2], packet[i + 3]])
            };
            self.pending.insert(
                data_id,
                Pending {
                    remaining: packet[5],
                    next_seq: seq,
                    source_id: at(6),
                    recipients: (0..count).map(|n| at(BASE_HEADER_LEN + n * 4)).collect(),
                    parts: 0,
                    payload: Vec::new(),
                },
            );
            self.pending.get_mut(&data_id)?
        } else {
            let p = self.pending.get_mut(&data_id)?;
            if p.parts == 0 || p.next_seq != seq || p.remaining == 0 {
                tracing::debug!(data_id, seq, "data channel packet out of sequence");
                self.pending.remove(&data_id);
                return None;
            }
            p.remaining -= 1;
            p
        };
        p.next_seq = seq.wrapping_add(1);
        p.parts += 1;
        p.payload.extend_from_slice(&packet[header_len..]);
        if p.remaining > 0 {
            return None;
        }
        let p = self.pending.remove(&data_id)?;
        Some(Message {
            data_id,
            source_id: p.source_id,
            recipients: p.recipients,
            payload: p.payload,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packets_carry_teams_header() {
        // The media control plane's syn (data id 18) to the processor (-4)
        // before it named us (-2): Teams' bytes.
        let p = packetize(18, 0, (-2i32) as u32, &[(-4i32) as u32], &[1, b'[', b']']);
        assert_eq!(
            p,
            [
                0x10, 0x0f, 0x92, 0, 0, 0, 0xff, 0xff, 0xff, 0xfe, 1, 0xff, 0xff, 0xff, 0xfc, 1,
                b'[', b']'
            ]
        );
        // Real-time text to everyone (data id 24).
        let p = packetize(24, 7, 3195, &[], br#"{"s":"h"}"#);
        assert_eq!(&p[..11], &[0x10, 0x0b, 0x98, 0, 7, 0, 0, 0, 0x0c, 0x7b, 0]);
        assert_eq!(&p[11..], br#"{"s":"h"}"#);
    }

    #[test]
    fn whole_messages_come_back_as_sent() {
        let mut d = Depacketizer::new();
        let m = d.push(&packetize(24, 1, 99, &[], b"hello")).unwrap();
        assert_eq!(
            m,
            Message {
                data_id: 24,
                source_id: 99,
                recipients: vec![],
                payload: b"hello".to_vec()
            }
        );
        let m = d.push(&packetize(18, 1, 4, &[5, 6], b"x")).unwrap();
        assert_eq!(m.recipients, vec![5, 6]);
        assert!(d.push(b"not a packet").is_none());
    }

    #[test]
    fn fragments_are_joined_in_sequence() {
        // A message in three packets: the first says two more follow.
        let mut first = packetize(3, 10, 42, &[], b"{\"a\":");
        first[5] = 2;
        let mut second = packetize(3, 11, 42, &[], b"\"bc");
        second[2] &= !START;
        let mut third = packetize(3, 12, 42, &[], b"d\"}");
        third[2] &= !START;
        let mut d = Depacketizer::new();
        assert!(d.push(&first).is_none());
        assert!(d.push(&second).is_none());
        let m = d.push(&third).unwrap();
        assert_eq!(m.payload, br#"{"a":"bcd"}"#);
        assert_eq!(m.source_id, 42);
        // A continuation out of order drops what was pending.
        let mut d = Depacketizer::new();
        assert!(d.push(&first).is_none());
        assert!(d.push(&third).is_none());
        assert!(d.push(&second).is_none());
    }
}
