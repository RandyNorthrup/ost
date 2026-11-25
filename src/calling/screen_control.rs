//! Give control and Take control of a shared screen, as Teams does it
//! (calling-pluginless `ScreenSharingControl`, read 2026-11-16; see
//! docs/spec/call-and-meeting-window.md §9b and §10).
//!
//! Both ends talk on the meeting's main data channel, addressed to one
//! participant's data source id:
//! - data id 1 (the control protocol): `{"type":0,"message":"<json>"}`, the
//!   inner JSON being `{action, terminatedReason, causeId?, handshakeId?}`;
//! - data id 2 (the controller's input): 7-byte mouse and 3-byte keyboard
//!   events ([`MouseEvent`], [`KeyEvent`]).
//!
//! A viewer watching someone's screen sends Available (retrying every
//! 2 s × n, six times) until the sharer answers AvailableAck (it can be
//! controlled: Teams' Give control lists the viewer, and the viewer's bar
//! shows Take control) or AvailableNack. A request (ControlRequest) waits
//! 30 s for AcceptRequest / RejectRequest; whoever gets an Accept or a
//! GiveControl answers Ack, and the sharer waits 10 s for that Ack. Either
//! side ends it with Terminate (answered with Ack) or TerminateNoAck.
//!
//! [`Session`] is the state machine of one end, without I/O: it is fed
//! messages and the time, and returns what to send and what to show.

use std::collections::BTreeSet;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

/// The data ids on the main data channel.
pub const PROTOCOL_DATA_ID: u8 = 1;
pub const INPUT_DATA_ID: u8 = 2;

/// How long a request waits for the sharer (Teams' `YW`).
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
/// How long the sharer waits for the controller's Ack (Teams' `HT`).
pub const ACK_TIMEOUT: Duration = Duration::from_secs(10);
/// Available is retried after 2 s × the attempt (Teams' `XW`)…
const AVAILABLE_RETRY: Duration = Duration::from_secs(2);
/// …at most this many times (Teams' `QW`).
const AVAILABLE_RETRIES: u32 = 6;

/// The protocol's actions (Teams' `Qn`).
pub mod action {
    pub const AVAILABLE: u8 = 0;
    pub const CONTROL_REQUEST: u8 = 1;
    pub const CANCEL_CONTROL_REQUEST: u8 = 2;
    pub const ACCEPT_REQUEST: u8 = 3;
    pub const REJECT_REQUEST: u8 = 4;
    pub const ACK: u8 = 5;
    pub const GIVE_CONTROL: u8 = 6;
    pub const TERMINATE_NO_ACK: u8 = 7;
    pub const TERMINATE: u8 = 8;
    pub const AVAILABLE_ACK: u8 = 9;
    pub const AVAILABLE_NACK: u8 = 10;
    pub const RENDERED_AT_VIEWER: u8 = 11;
}

/// Why control ended or was refused (Teams' `Ia`).
pub mod reason {
    pub const NONE: u8 = 0;
    pub const SHARER_DENIED: u8 = 1;
    pub const SHARER_NO_RESPONSE: u8 = 2;
    pub const SHARER_BUSY: u8 = 3;
    pub const ACK_TIMEOUT: u8 = 4;
    pub const SHARER_TERMINATED: u8 = 5;
    pub const VIEWER_TERMINATED: u8 = 6;
    pub const DATA_CHANNEL_ERROR: u8 = 7;
    pub const VIEWER_CANCELLED: u8 = 8;
    pub const SHARER_CONTROL_DISABLED: u8 = 9;
    pub const UNKNOWN_SENDER: u8 = 10;
    pub const MULTIPLE_SHARERS: u8 = 11;
}

/// One protocol message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub action: u8,
    pub terminated_reason: u8,
    pub cause_id: Option<String>,
    pub handshake_id: Option<String>,
}

impl Message {
    pub fn new(action: u8, terminated_reason: u8) -> Self {
        Self {
            action,
            terminated_reason,
            cause_id: None,
            handshake_id: None,
        }
    }

    fn cause(mut self, id: Option<&str>) -> Self {
        self.cause_id = id.map(str::to_string);
        self
    }

    fn handshake(mut self, id: &str) -> Self {
        self.handshake_id = Some(id.to_string());
        self
    }

    /// The data-id-1 payload: Teams' `{type: 0, message: JSON}`, each
    /// character a byte.
    pub fn encode(&self) -> Vec<u8> {
        let mut inner = json!({"action": self.action, "terminatedReason": self.terminated_reason});
        if let Some(c) = &self.cause_id {
            inner["causeId"] = json!(c);
        }
        if let Some(h) = &self.handshake_id {
            inner["handshakeId"] = json!(h);
        }
        json!({"type": 0, "message": inner.to_string()})
            .to_string()
            .into_bytes()
    }

    pub fn decode(payload: &[u8]) -> Option<Self> {
        // Teams reads the bytes as characters (String.fromCharCode).
        let text: String = payload.iter().map(|&b| b as char).collect();
        let outer: Value = serde_json::from_str(&text).ok()?;
        let inner: Value = match outer.get("message")? {
            Value::String(s) => serde_json::from_str(s).ok()?,
            v @ Value::Object(_) => v.clone(),
            _ => return None,
        };
        let id = |k: &str| match inner.get(k) {
            Some(Value::String(s)) => Some(s.clone()),
            Some(Value::Number(n)) => Some(n.to_string()),
            _ => None,
        };
        Some(Self {
            action: inner.get("action")?.as_u64()? as u8,
            terminated_reason: inner
                .get("terminatedReason")
                .and_then(Value::as_u64)
                .unwrap_or(0) as u8,
            cause_id: id("causeId"),
            handshake_id: id("handshakeId"),
        })
    }
}

/// A mouse event's kind.
pub mod mouse {
    pub const MOVE: u8 = 0;
    pub const WHEEL: u8 = 1;
    pub const BUTTON: u8 = 2;
    pub const LEFT: u8 = 0;
    pub const RIGHT: u8 = 1;
    pub const MIDDLE: u8 = 2;
}

/// The controller's mouse, over the shared picture: x and y from 0 (left,
/// top) to 65535 (right, bottom).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MouseEvent {
    pub kind: u8,
    pub button: u8,
    pub down: bool,
    pub x: u16,
    pub y: u16,
    /// ±120 a notch, up positive.
    pub wheel: i8,
}

impl MouseEvent {
    /// Teams' 7 bytes: 1, kind | button << 2 | down << 5, x and y
    /// (little-endian), the wheel as a byte.
    pub fn encode(&self) -> Vec<u8> {
        let flags = (self.kind & 3) | ((self.button & 7) << 2) | ((self.down as u8) << 5);
        let mut b = vec![1, flags];
        b.extend_from_slice(&self.x.to_le_bytes());
        b.extend_from_slice(&self.y.to_le_bytes());
        b.push(self.wheel as u8);
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() != 7 || b[0] != 1 {
            return None;
        }
        Some(Self {
            kind: b[1] & 3,
            button: (b[1] >> 2) & 7,
            down: (b[1] >> 5) & 1 == 1,
            x: u16::from_le_bytes([b[2], b[3]]),
            y: u16::from_le_bytes([b[4], b[5]]),
            wheel: b[6] as i8,
        })
    }
}

/// A key, as a Windows virtual-key code (Teams sends `keyCode`, code type
/// 1: VIRTUAL_KEY).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyEvent {
    pub code: u8,
    pub up: bool,
    pub repeat: bool,
}

impl KeyEvent {
    pub fn encode(&self) -> Vec<u8> {
        vec![
            0,
            1 | ((self.up as u8) << 4) | ((self.repeat as u8) << 5),
            self.code,
        ]
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() != 3 || b[0] != 0 {
            return None;
        }
        Some(Self {
            code: b[2],
            up: (b[1] >> 4) & 1 == 1,
            repeat: (b[1] >> 5) & 1 == 1,
        })
    }
}

/// Keys: Teams' viewer sends Windows virtual-key codes (`keyCode`).
pub mod keys {
    /// A Windows virtual-key code as a Linux evdev key code (US layout
    /// positions, as Teams' viewer sends the key's code, not its character).
    pub fn evdev_from_vk(vk: u8) -> Option<i32> {
        // Letters A–Z on their QWERTY keys.
        const LETTERS: [i32; 26] = [
            30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22, 47,
            17, 45, 21, 44,
        ];
        Some(match vk {
            0x41..=0x5a => LETTERS[(vk - 0x41) as usize],
            0x31..=0x39 => 2 + (vk - 0x31) as i32,
            0x30 => 11,
            0x70..=0x79 => 59 + (vk - 0x70) as i32,
            0x7a => 87,
            0x7b => 88,
            0x08 => 14,
            0x09 => 15,
            0x0d => 28,
            0x10 | 0xa0 => 42,
            0xa1 => 54,
            0x11 | 0xa2 => 29,
            0xa3 => 97,
            0x12 | 0xa4 => 56,
            0xa5 => 100,
            0x13 => 119,
            0x14 => 58,
            0x1b => 1,
            0x20 => 57,
            0x21 => 104,
            0x22 => 109,
            0x23 => 107,
            0x24 => 102,
            0x25 => 105,
            0x26 => 103,
            0x27 => 106,
            0x28 => 108,
            0x2c => 99,
            0x2d => 110,
            0x2e => 111,
            0x5b => 125,
            0x5c => 126,
            0x5d => 127,
            0x60..=0x69 => [82, 79, 80, 81, 75, 76, 77, 71, 72, 73][(vk - 0x60) as usize],
            0x6a => 55,
            0x6b => 78,
            0x6d => 74,
            0x6e => 83,
            0x6f => 98,
            0x90 => 69,
            0x91 => 70,
            0xba => 39,
            0xbb => 13,
            0xbc => 51,
            0xbd => 12,
            0xbe => 52,
            0xbf => 53,
            0xc0 => 41,
            0xdb => 26,
            0xdc => 43,
            0xdd => 27,
            0xde => 40,
            _ => return None,
        })
    }

    /// An evdev key code as a Windows virtual-key code.
    pub fn vk_from_evdev(code: i32) -> Option<u8> {
        // The first virtual key mapping to it (generic Shift, Ctrl, Alt
        // before their left and right ones).
        (0x01..=0xfeu8).find(|vk| evdev_from_vk(*vk) == Some(code))
    }

    /// A Qt key event as a virtual-key code: by the key's position (the
    /// native scan code is evdev + 8 on Linux), else by Qt's key.
    pub fn vk_from_qt(key: i32, native_scan_code: u32) -> Option<u8> {
        if native_scan_code > 8
            && let Some(vk) = vk_from_evdev(native_scan_code as i32 - 8)
        {
            return Some(vk);
        }
        let k = key as u32;
        Some(match k {
            0x41..=0x5a | 0x30..=0x39 | 0x20 => k as u8,
            0x61..=0x7a => (k - 0x20) as u8,
            0x0100_0000 => 0x1b,
            0x0100_0001 | 0x0100_0002 => 0x09,
            0x0100_0003 => 0x08,
            0x0100_0004 | 0x0100_0005 => 0x0d,
            0x0100_0006 => 0x2d,
            0x0100_0007 => 0x2e,
            0x0100_0008 => 0x13,
            0x0100_0009 => 0x2c,
            0x0100_0010 => 0x24,
            0x0100_0011 => 0x23,
            0x0100_0012 => 0x25,
            0x0100_0013 => 0x26,
            0x0100_0014 => 0x27,
            0x0100_0015 => 0x28,
            0x0100_0016 => 0x21,
            0x0100_0017 => 0x22,
            0x0100_0020 => 0x10,
            0x0100_0021 => 0x11,
            0x0100_0022 => 0x5b,
            0x0100_0023 => 0x12,
            0x0100_0024 => 0x14,
            0x0100_0025 => 0x90,
            0x0100_0026 => 0x91,
            0x0100_0030..=0x0100_003b => (0x70 + (k - 0x0100_0030)) as u8,
            0x0100_0055 => 0x5d,
            0x2c | 0x3c => 0xbc,
            0x2d | 0x5f => 0xbd,
            0x2e | 0x3e => 0xbe,
            0x2f | 0x3f => 0xbf,
            0x3b | 0x3a => 0xba,
            0x3d | 0x2b => 0xbb,
            0x5b | 0x7b => 0xdb,
            0x5c | 0x7c => 0xdc,
            0x5d | 0x7d => 0xdd,
            0x60 | 0x7e => 0xc0,
            0x27 | 0x22 => 0xde,
            0x21 => 0x31,
            0x40 => 0x32,
            0x23 => 0x33,
            0x24 => 0x34,
            0x25 => 0x35,
            0x5e => 0x36,
            0x26 => 0x37,
            0x2a => 0x38,
            0x28 => 0x39,
            0x29 => 0x30,
            _ => return None,
        })
    }
}

/// Teams' control states (`kr`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum State {
    #[default]
    None,
    /// A viewer asked and waits.
    RequestSent,
    /// The sharer accepted or gave control and waits for the Ack.
    WaitingForControlAck,
    /// The sharer's screen is controlled by someone.
    RemoteControlling,
    /// The viewer controls the sharer's screen.
    LocalControlling,
    /// A Terminate waits for its Ack.
    WaitingForTerminateAck,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Role {
    #[default]
    None,
    Sharer,
    Viewer,
}

/// What the session wants done.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Out {
    /// Send this to one data source.
    Send { to: u32, message: Message },
    /// Viewer: whether the sharer can be asked (Teams' Take control);
    /// `denied_by_sharer` when its AvailableNack said SharerDenied.
    Capable {
        capable: bool,
        denied_by_sharer: bool,
    },
    /// Sharer: who can be given control (their data sources).
    Controllable(Vec<u32>),
    /// Sharer: `from` asks for control.
    IncomingRequest { from: u32 },
    /// Sharer: their request was withdrawn (cancelled, timed out).
    RequestWithdrawn { from: u32 },
    /// Control changed: `controller` is the data source in control (the
    /// sharer's view) or None for "us" (the viewer's view).
    ControlChanged {
        in_control: bool,
        controller: Option<u32>,
        reason: u8,
    },
    /// Viewer: the request was refused or timed out.
    RequestFailed { reason: u8 },
}

/// One end of the protocol.
#[derive(Debug, Default)]
pub struct Session {
    role: Role,
    state: State,
    cause_id: Option<String>,
    deadline: Option<Instant>,
    // Viewer.
    sharer: Option<u32>,
    handshake: Option<Handshake>,
    capable: bool,
    rendered_sent: bool,
    // Sharer.
    enabled: bool,
    viewers: BTreeSet<u32>,
    request: Option<(u32, Option<String>)>,
    controller: Option<u32>,
}

#[derive(Debug)]
struct Handshake {
    id: String,
    attempt: u32,
    next: Instant,
}

fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

impl Session {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn role(&self) -> Role {
        self.role
    }

    pub fn state(&self) -> State {
        self.state
    }

    /// The data source controlling our shared screen (its input is taken).
    pub fn controller(&self) -> Option<u32> {
        (self.role == Role::Sharer && self.state == State::RemoteControlling)
            .then_some(self.controller)
            .flatten()
    }

    /// The sharer we control (our input goes to it).
    pub fn controlled_sharer(&self) -> Option<u32> {
        (self.role == Role::Viewer && self.state == State::LocalControlling)
            .then_some(self.sharer)
            .flatten()
    }

    /// Whether `source`'s input moves our screen now.
    pub fn takes_input_from(&self, source: u32) -> bool {
        self.controller() == Some(source)
    }

    fn reset(&mut self) {
        self.state = State::None;
        self.cause_id = None;
        self.deadline = None;
        self.request = None;
        self.controller = None;
    }

    // ---- Sharer ----

    /// We started sharing. `enabled`: we can be controlled (an input
    /// injector is available); viewers are refused otherwise.
    pub fn start_sharing(&mut self, enabled: bool) -> Vec<Out> {
        let mut out = self.stop_viewing();
        self.reset();
        self.role = Role::Sharer;
        self.enabled = enabled;
        self.viewers.clear();
        out.push(Out::Controllable(Vec::new()));
        out
    }

    /// We stopped sharing: a pending request is refused, a controller
    /// loses control.
    pub fn stop_sharing(&mut self) -> Vec<Out> {
        if self.role != Role::Sharer {
            return Vec::new();
        }
        let mut out = Vec::new();
        if let Some((from, cause)) = self.request.take() {
            out.push(Out::RequestWithdrawn { from });
            out.push(Out::Send {
                to: from,
                message: Message::new(action::REJECT_REQUEST, reason::SHARER_TERMINATED)
                    .cause(cause.as_deref()),
            });
        }
        if let Some(c) = self
            .controller
            .filter(|_| self.state == State::RemoteControlling)
        {
            out.push(Out::ControlChanged {
                in_control: false,
                controller: Some(c),
                reason: reason::SHARER_TERMINATED,
            });
        }
        self.reset();
        self.viewers.clear();
        self.role = Role::None;
        out.push(Out::Controllable(Vec::new()));
        out
    }

    /// Sharer: accept the pending request.
    pub fn accept(&mut self, now: Instant) -> Vec<Out> {
        let Some((from, cause)) = self.request.take().filter(|_| self.role == Role::Sharer) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        if let Some(c) = self
            .controller
            .filter(|c| *c != from && self.state == State::RemoteControlling)
        {
            out.push(Out::Send {
                to: c,
                message: Message::new(action::TERMINATE_NO_ACK, reason::SHARER_TERMINATED),
            });
            out.push(Out::ControlChanged {
                in_control: false,
                controller: Some(c),
                reason: reason::SHARER_TERMINATED,
            });
        }
        out.push(Out::Send {
            to: from,
            message: Message::new(action::ACCEPT_REQUEST, reason::NONE).cause(cause.as_deref()),
        });
        self.controller = Some(from);
        self.cause_id = cause;
        self.state = State::WaitingForControlAck;
        self.deadline = Some(now + ACK_TIMEOUT);
        out
    }

    /// Sharer: refuse the pending request.
    pub fn deny(&mut self) -> Vec<Out> {
        let Some((from, cause)) = self.request.take().filter(|_| self.role == Role::Sharer) else {
            return Vec::new();
        };
        vec![Out::Send {
            to: from,
            message: Message::new(action::REJECT_REQUEST, reason::SHARER_DENIED)
                .cause(cause.as_deref()),
        }]
    }

    /// Sharer: give control to `to` (Give control ▸ a person).
    pub fn give(&mut self, to: u32, now: Instant) -> Vec<Out> {
        if self.role != Role::Sharer || !self.enabled {
            return Vec::new();
        }
        let mut out = Vec::new();
        if self.state == State::RemoteControlling {
            match self.controller {
                Some(c) if c == to => return out,
                Some(c) => {
                    out.push(Out::Send {
                        to: c,
                        message: Message::new(action::TERMINATE_NO_ACK, reason::SHARER_TERMINATED),
                    });
                    out.push(Out::ControlChanged {
                        in_control: false,
                        controller: Some(c),
                        reason: reason::SHARER_TERMINATED,
                    });
                }
                None => {}
            }
        }
        let cause = new_id();
        out.push(Out::Send {
            to,
            message: Message::new(action::GIVE_CONTROL, reason::NONE).cause(Some(&cause)),
        });
        self.cause_id = Some(cause);
        self.controller = Some(to);
        self.state = State::WaitingForControlAck;
        self.deadline = Some(now + ACK_TIMEOUT);
        out
    }

    /// Sharer: Take back. Viewer: Stop control.
    pub fn terminate(&mut self, now: Instant) -> Vec<Out> {
        match (self.role, self.state) {
            (Role::Sharer, State::RemoteControlling) => {
                let Some(c) = self.controller else {
                    return Vec::new();
                };
                self.state = State::WaitingForTerminateAck;
                self.deadline = Some(now + ACK_TIMEOUT);
                vec![
                    Out::Send {
                        to: c,
                        message: Message::new(action::TERMINATE, reason::SHARER_TERMINATED),
                    },
                    Out::ControlChanged {
                        in_control: false,
                        controller: Some(c),
                        reason: reason::SHARER_TERMINATED,
                    },
                ]
            }
            (Role::Viewer, State::LocalControlling) => {
                let Some(s) = self.sharer else {
                    return Vec::new();
                };
                self.state = State::WaitingForTerminateAck;
                self.deadline = Some(now + ACK_TIMEOUT);
                vec![
                    Out::Send {
                        to: s,
                        message: Message::new(action::TERMINATE, reason::VIEWER_TERMINATED),
                    },
                    Out::ControlChanged {
                        in_control: false,
                        controller: None,
                        reason: reason::VIEWER_TERMINATED,
                    },
                ]
            }
            _ => Vec::new(),
        }
    }

    // ---- Viewer ----

    /// We watch `sharer`'s screen (their data source): start the
    /// Available handshake.
    pub fn start_viewing(&mut self, sharer: u32, now: Instant) -> Vec<Out> {
        if self.role == Role::Sharer {
            return Vec::new();
        }
        if self.role == Role::Viewer && self.sharer == Some(sharer) {
            return Vec::new();
        }
        let mut out = self.stop_viewing();
        self.reset();
        self.role = Role::Viewer;
        self.sharer = Some(sharer);
        self.capable = false;
        self.rendered_sent = false;
        let id = new_id();
        out.push(Out::Send {
            to: sharer,
            message: Message::new(action::AVAILABLE, reason::NONE).handshake(&id),
        });
        self.handshake = Some(Handshake {
            id,
            attempt: 1,
            next: now + AVAILABLE_RETRY,
        });
        out
    }

    /// We stopped watching: a request is withdrawn, control ends.
    pub fn stop_viewing(&mut self) -> Vec<Out> {
        if self.role != Role::Viewer {
            return Vec::new();
        }
        let mut out = Vec::new();
        if let Some(s) = self.sharer {
            match self.state {
                State::RequestSent => {
                    out.push(Out::Send {
                        to: s,
                        message: Message::new(
                            action::CANCEL_CONTROL_REQUEST,
                            reason::VIEWER_CANCELLED,
                        )
                        .cause(self.cause_id.as_deref()),
                    });
                    out.push(Out::RequestFailed {
                        reason: reason::VIEWER_CANCELLED,
                    });
                }
                State::LocalControlling => {
                    out.push(Out::ControlChanged {
                        in_control: false,
                        controller: None,
                        reason: reason::VIEWER_TERMINATED,
                    });
                }
                _ => {}
            }
        }
        if self.capable {
            out.push(Out::Capable {
                capable: false,
                denied_by_sharer: false,
            });
        }
        self.reset();
        self.role = Role::None;
        self.sharer = None;
        self.handshake = None;
        self.capable = false;
        out
    }

    /// Viewer: Take control ▸ Request.
    pub fn request(&mut self, now: Instant) -> Vec<Out> {
        let Some(s) = self
            .sharer
            .filter(|_| self.role == Role::Viewer && self.state == State::None)
        else {
            return Vec::new();
        };
        let cause = new_id();
        self.state = State::RequestSent;
        self.deadline = Some(now + REQUEST_TIMEOUT);
        let message = Message::new(action::CONTROL_REQUEST, reason::NONE).cause(Some(&cause));
        self.cause_id = Some(cause);
        vec![Out::Send { to: s, message }]
    }

    /// Viewer: withdraw the request.
    pub fn cancel_request(&mut self) -> Vec<Out> {
        let Some(s) = self
            .sharer
            .filter(|_| self.role == Role::Viewer && self.state == State::RequestSent)
        else {
            return Vec::new();
        };
        let cause = self.cause_id.take();
        self.state = State::None;
        self.deadline = None;
        vec![
            Out::Send {
                to: s,
                message: Message::new(action::CANCEL_CONTROL_REQUEST, reason::VIEWER_CANCELLED)
                    .cause(cause.as_deref()),
            },
            Out::RequestFailed {
                reason: reason::VIEWER_CANCELLED,
            },
        ]
    }

    // ---- Both ----

    /// A protocol message from data source `from`.
    pub fn receive(&mut self, from: u32, m: &Message, now: Instant) -> Vec<Out> {
        let ack = || Out::Send {
            to: from,
            message: Message::new(action::ACK, reason::NONE),
        };
        match m.action {
            action::AVAILABLE if self.role == Role::Sharer => {
                let hs = m.handshake_id.clone().unwrap_or_default();
                if !self.enabled {
                    return vec![Out::Send {
                        to: from,
                        message: Message::new(
                            action::AVAILABLE_NACK,
                            reason::SHARER_CONTROL_DISABLED,
                        )
                        .handshake(&hs),
                    }];
                }
                self.viewers.insert(from);
                vec![
                    Out::Send {
                        to: from,
                        message: Message::new(action::AVAILABLE_ACK, reason::NONE).handshake(&hs),
                    },
                    Out::Controllable(self.viewers.iter().copied().collect()),
                ]
            }
            action::CONTROL_REQUEST if self.role == Role::Sharer => {
                if !self.enabled {
                    return vec![Out::Send {
                        to: from,
                        message: Message::new(
                            action::REJECT_REQUEST,
                            reason::SHARER_CONTROL_DISABLED,
                        ),
                    }];
                }
                if self.request.is_some() {
                    return vec![Out::Send {
                        to: from,
                        message: Message::new(action::REJECT_REQUEST, reason::SHARER_BUSY),
                    }];
                }
                self.request = Some((from, m.cause_id.clone()));
                vec![Out::IncomingRequest { from }]
            }
            action::CANCEL_CONTROL_REQUEST if self.role == Role::Sharer => match &self.request {
                Some((r, _)) if *r == from => {
                    self.request = None;
                    vec![Out::RequestWithdrawn { from }]
                }
                _ => Vec::new(),
            },
            action::ACK => match (self.role, self.state) {
                (Role::Sharer, State::WaitingForControlAck) if self.controller == Some(from) => {
                    self.state = State::RemoteControlling;
                    self.deadline = None;
                    vec![Out::ControlChanged {
                        in_control: true,
                        controller: Some(from),
                        reason: m.terminated_reason,
                    }]
                }
                (_, State::WaitingForTerminateAck) => {
                    self.reset();
                    Vec::new()
                }
                _ => Vec::new(),
            },
            action::AVAILABLE_ACK if self.role == Role::Viewer => {
                self.handshake = None;
                self.capable = true;
                // Teams' viewer also says its renderer shows the share
                // (RenderedAtViewer, once it draws the first frame).
                let mut out = vec![Out::Capable {
                    capable: true,
                    denied_by_sharer: false,
                }];
                if !self.rendered_sent {
                    self.rendered_sent = true;
                    out.insert(
                        0,
                        Out::Send {
                            to: from,
                            message: Message::new(action::RENDERED_AT_VIEWER, reason::NONE),
                        },
                    );
                }
                out
            }
            action::AVAILABLE_NACK if self.role == Role::Viewer => {
                if m.terminated_reason == reason::UNKNOWN_SENDER {
                    return Vec::new();
                }
                self.handshake = None;
                self.capable = false;
                vec![Out::Capable {
                    capable: false,
                    denied_by_sharer: m.terminated_reason == reason::SHARER_DENIED,
                }]
            }
            action::ACCEPT_REQUEST
                if self.role == Role::Viewer && self.state == State::RequestSent =>
            {
                self.state = State::LocalControlling;
                self.deadline = None;
                vec![
                    ack(),
                    Out::ControlChanged {
                        in_control: true,
                        controller: None,
                        reason: reason::NONE,
                    },
                ]
            }
            action::REJECT_REQUEST
                if self.role == Role::Viewer && self.state == State::RequestSent =>
            {
                self.state = State::None;
                self.deadline = None;
                self.cause_id = None;
                vec![Out::RequestFailed {
                    reason: m.terminated_reason,
                }]
            }
            action::GIVE_CONTROL if self.role == Role::Viewer => {
                self.cause_id = m.cause_id.clone();
                self.state = State::LocalControlling;
                self.deadline = None;
                vec![
                    ack(),
                    Out::ControlChanged {
                        in_control: true,
                        controller: None,
                        reason: m.terminated_reason,
                    },
                ]
            }
            action::TERMINATE | action::TERMINATE_NO_ACK => {
                let was = match self.role {
                    Role::Viewer
                        if matches!(self.state, State::LocalControlling | State::RequestSent) =>
                    {
                        Some(None)
                    }
                    Role::Sharer if self.controller == Some(from) && self.state != State::None => {
                        Some(Some(from))
                    }
                    _ => None,
                };
                let mut out = Vec::new();
                if let Some(controller) = was {
                    self.reset();
                    out.push(Out::ControlChanged {
                        in_control: false,
                        controller,
                        reason: m.terminated_reason,
                    });
                }
                if m.action == action::TERMINATE {
                    out.push(ack());
                }
                out
            }
            _ => {
                let _ = now;
                Vec::new()
            }
        }
    }

    /// Retries and timeouts; call often (every half second).
    pub fn tick(&mut self, now: Instant) -> Vec<Out> {
        let mut out = Vec::new();
        if let (Role::Viewer, Some(s)) = (self.role, self.sharer)
            && let Some(h) = self.handshake.as_mut()
            && now >= h.next
        {
            if h.attempt <= AVAILABLE_RETRIES {
                h.attempt += 1;
                h.next = now + AVAILABLE_RETRY * h.attempt;
                out.push(Out::Send {
                    to: s,
                    message: Message::new(action::AVAILABLE, reason::NONE).handshake(&h.id),
                });
            } else {
                // Teams: "Reached Available retry limit! Control
                // capability will be false".
                self.handshake = None;
                out.push(Out::Capable {
                    capable: false,
                    denied_by_sharer: false,
                });
            }
        }
        if self.deadline.is_some_and(|d| now >= d) {
            self.deadline = None;
            match (self.role, self.state) {
                (Role::Viewer, State::RequestSent) => {
                    if let Some(s) = self.sharer {
                        out.push(Out::Send {
                            to: s,
                            message: Message::new(
                                action::CANCEL_CONTROL_REQUEST,
                                reason::SHARER_NO_RESPONSE,
                            )
                            .cause(self.cause_id.as_deref()),
                        });
                    }
                    self.state = State::None;
                    self.cause_id = None;
                    out.push(Out::RequestFailed {
                        reason: reason::SHARER_NO_RESPONSE,
                    });
                }
                (Role::Sharer, State::WaitingForControlAck) => {
                    if let Some(c) = self.controller {
                        out.push(Out::Send {
                            to: c,
                            message: Message::new(action::TERMINATE_NO_ACK, reason::ACK_TIMEOUT)
                                .cause(self.cause_id.as_deref()),
                        });
                        out.push(Out::ControlChanged {
                            in_control: false,
                            controller: Some(c),
                            reason: reason::ACK_TIMEOUT,
                        });
                    }
                    self.reset();
                }
                (_, State::WaitingForTerminateAck) => {
                    let to = if self.role == Role::Sharer {
                        self.controller
                    } else {
                        self.sharer
                    };
                    if let Some(t) = to {
                        out.push(Out::Send {
                            to: t,
                            message: Message::new(action::TERMINATE_NO_ACK, reason::ACK_TIMEOUT),
                        });
                    }
                    self.reset();
                }
                _ => {}
            }
        }
        out
    }

    /// A participant left (their data sources): a controller loses
    /// control; a viewer forgets a sharer who left.
    pub fn left(&mut self, sources: &[u32]) -> Vec<Out> {
        let mut out = Vec::new();
        match self.role {
            Role::Sharer => {
                let before = self.viewers.len();
                self.viewers.retain(|v| !sources.contains(v));
                if let Some(c) = self.controller.filter(|c| sources.contains(c)) {
                    if self.state == State::RemoteControlling {
                        out.push(Out::ControlChanged {
                            in_control: false,
                            controller: Some(c),
                            reason: reason::SHARER_TERMINATED,
                        });
                    }
                    self.reset();
                }
                if let Some((r, _)) = self.request.clone().filter(|(r, _)| sources.contains(r)) {
                    self.request = None;
                    out.push(Out::RequestWithdrawn { from: r });
                }
                if self.viewers.len() != before {
                    out.push(Out::Controllable(self.viewers.iter().copied().collect()));
                }
            }
            Role::Viewer if self.sharer.is_some_and(|s| sources.contains(&s)) => {
                out = self.stop_viewing()
            }
            _ => {}
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sends(out: &[Out]) -> Vec<(u32, u8, u8)> {
        out.iter()
            .filter_map(|o| match o {
                Out::Send { to, message } => Some((*to, message.action, message.terminated_reason)),
                _ => None,
            })
            .collect()
    }

    /// Deliver every Send from `out` that's addressed to `to_id` into `to`.
    fn deliver(out: &[Out], from: u32, to_id: u32, to: &mut Session, now: Instant) -> Vec<Out> {
        let mut got = Vec::new();
        for o in out {
            if let Out::Send { to: t, message } = o
                && *t == to_id
            {
                let wire = message.encode();
                got.extend(to.receive(from, &Message::decode(&wire).unwrap(), now));
            }
        }
        got
    }

    #[test]
    fn messages_are_teams_json_inside_json() {
        let m = Message::new(action::CONTROL_REQUEST, 0).cause(Some("c-1"));
        let wire = String::from_utf8(m.encode()).unwrap();
        let outer: Value = serde_json::from_str(&wire).unwrap();
        assert_eq!(outer["type"], 0);
        let inner: Value = serde_json::from_str(outer["message"].as_str().unwrap()).unwrap();
        assert_eq!(
            inner,
            json!({"action": 1, "terminatedReason": 0, "causeId": "c-1"})
        );
        assert_eq!(Message::decode(wire.as_bytes()).unwrap(), m);
        // Teams' own: what its _sendRequest builds for AvailableAck.
        let teams = br#"{"type":0,"message":"{\"action\":9,\"terminatedReason\":0,\"handshakeId\":\"h\"}"}"#;
        let d = Message::decode(teams).unwrap();
        assert_eq!(
            (d.action, d.handshake_id.as_deref()),
            (action::AVAILABLE_ACK, Some("h"))
        );
    }

    #[test]
    fn input_events_are_teams_bytes() {
        let m = MouseEvent {
            kind: mouse::BUTTON,
            button: mouse::RIGHT,
            down: true,
            x: 0x1234,
            y: 65535,
            wheel: 0,
        };
        assert_eq!(
            m.encode(),
            vec![1, 2 | (1 << 2) | (1 << 5), 0x34, 0x12, 0xff, 0xff, 0]
        );
        assert_eq!(MouseEvent::decode(&m.encode()), Some(m));
        let w = MouseEvent {
            kind: mouse::WHEEL,
            wheel: -120,
            ..Default::default()
        };
        assert_eq!(w.encode()[6], 136, "Teams writes -120 with setUint8");
        assert_eq!(MouseEvent::decode(&w.encode()).unwrap().wheel, -120);
        let k = KeyEvent {
            code: 0x41,
            up: true,
            repeat: false,
        };
        assert_eq!(k.encode(), vec![0, 1 | (1 << 4), 0x41]);
        assert_eq!(KeyEvent::decode(&k.encode()), Some(k));
        assert_eq!(KeyEvent::decode(&[1, 0, 0]), None);
    }

    #[test]
    fn keys_map_both_ways() {
        use keys::*;
        assert_eq!(evdev_from_vk(b'A'), Some(30));
        assert_eq!(evdev_from_vk(b'Z'), Some(44));
        assert_eq!(evdev_from_vk(b'O'), Some(24));
        assert_eq!(evdev_from_vk(b'0'), Some(11));
        assert_eq!(evdev_from_vk(b'1'), Some(2));
        assert_eq!(evdev_from_vk(0x0d), Some(28), "Enter");
        assert_eq!(evdev_from_vk(0x10), Some(42), "Shift");
        assert_eq!(evdev_from_vk(0x7b), Some(88), "F12");
        assert_eq!(evdev_from_vk(0xff), None);
        assert_eq!(vk_from_evdev(30), Some(b'A'));
        assert_eq!(vk_from_evdev(42), Some(0x10), "the generic Shift");
        assert_eq!(vk_from_evdev(54), Some(0xa1), "right Shift");
        // Qt: by scan code (evdev + 8), else by key.
        assert_eq!(vk_from_qt(0x41, 38), Some(b'A'));
        assert_eq!(vk_from_qt(0x41, 0), Some(b'A'));
        assert_eq!(vk_from_qt(0x0100_0004, 0), Some(0x0d));
        assert_eq!(vk_from_qt(0x21, 0), Some(b'1'), "Shift+1 is the 1 key");
    }

    #[test]
    fn a_viewer_asks_and_the_sharer_accepts() {
        let now = Instant::now();
        let (mut sharer, mut viewer) = (Session::new(), Session::new());
        sharer.start_sharing(true);
        // Viewer (source 20) watches the sharer (source 10).
        let out = viewer.start_viewing(10, now);
        assert_eq!(sends(&out), vec![(10, action::AVAILABLE, 0)]);
        let back = deliver(&out, 20, 10, &mut sharer, now);
        assert!(back.contains(&Out::Controllable(vec![20])));
        let got = deliver(&back, 10, 20, &mut viewer, now);
        assert!(got.contains(&Out::Capable {
            capable: true,
            denied_by_sharer: false
        }));
        assert_eq!(sends(&got), vec![(10, action::RENDERED_AT_VIEWER, 0)]);
        assert_eq!(
            sends(&viewer.receive(10, &Message::new(action::AVAILABLE_ACK, 0), now)),
            vec![],
            "RenderedAtViewer goes once"
        );
        // Request, accept, ack.
        let req = viewer.request(now);
        let at_sharer = deliver(&req, 20, 10, &mut sharer, now);
        assert_eq!(at_sharer, vec![Out::IncomingRequest { from: 20 }]);
        let acc = sharer.accept(now);
        assert_eq!(sharer.state(), State::WaitingForControlAck);
        let at_viewer = deliver(&acc, 10, 20, &mut viewer, now);
        assert_eq!(viewer.controlled_sharer(), Some(10));
        let done = deliver(&at_viewer, 20, 10, &mut sharer, now);
        assert_eq!(
            done,
            vec![Out::ControlChanged {
                in_control: true,
                controller: Some(20),
                reason: 0
            }]
        );
        assert!(sharer.takes_input_from(20) && !sharer.takes_input_from(21));
        // The sharer takes control back; the viewer acks.
        let tb = sharer.terminate(now);
        let at_viewer = deliver(&tb, 10, 20, &mut viewer, now);
        assert!(at_viewer.contains(&Out::ControlChanged {
            in_control: false,
            controller: None,
            reason: reason::SHARER_TERMINATED
        }));
        deliver(&at_viewer, 20, 10, &mut sharer, now);
        assert_eq!((sharer.state(), viewer.state()), (State::None, State::None));
    }

    #[test]
    fn the_sharer_gives_control_and_the_viewer_stops() {
        let now = Instant::now();
        let (mut sharer, mut viewer) = (Session::new(), Session::new());
        sharer.start_sharing(true);
        viewer.start_viewing(10, now);
        let give = sharer.give(20, now);
        assert_eq!(sends(&give), vec![(20, action::GIVE_CONTROL, 0)]);
        let ack = deliver(&give, 10, 20, &mut viewer, now);
        assert_eq!(viewer.state(), State::LocalControlling);
        deliver(&ack, 20, 10, &mut sharer, now);
        assert_eq!(sharer.controller(), Some(20));
        let stop = viewer.terminate(now);
        assert_eq!(
            sends(&stop),
            vec![(10, action::TERMINATE, reason::VIEWER_TERMINATED)]
        );
        let at_sharer = deliver(&stop, 20, 10, &mut sharer, now);
        assert!(at_sharer.contains(&Out::ControlChanged {
            in_control: false,
            controller: Some(20),
            reason: reason::VIEWER_TERMINATED
        }));
        deliver(&at_sharer, 10, 20, &mut viewer, now);
        assert_eq!((sharer.state(), viewer.state()), (State::None, State::None));
    }

    #[test]
    fn denials_timeouts_and_retries() {
        let now = Instant::now();
        let (mut sharer, mut viewer) = (Session::new(), Session::new());
        sharer.start_sharing(true);
        viewer.start_viewing(10, now);
        let req = viewer.request(now);
        deliver(&req, 20, 10, &mut sharer, now);
        let no = sharer.deny();
        let at_viewer = deliver(&no, 10, 20, &mut viewer, now);
        assert_eq!(
            at_viewer,
            vec![Out::RequestFailed {
                reason: reason::SHARER_DENIED
            }]
        );
        // Unanswered: cancelled after 30 s.
        viewer.request(now);
        let late = viewer.tick(now + REQUEST_TIMEOUT);
        assert!(late.contains(&Out::RequestFailed {
            reason: reason::SHARER_NO_RESPONSE
        }));
        assert_eq!(
            sends(&late).last().map(|s| s.1),
            Some(action::CANCEL_CONTROL_REQUEST)
        );
        // No Ack after a give: TerminateNoAck after 10 s.
        sharer.give(20, now);
        let t = sharer.tick(now + ACK_TIMEOUT);
        assert_eq!(
            sends(&t),
            vec![(20, action::TERMINATE_NO_ACK, reason::ACK_TIMEOUT)]
        );
        // Available is retried 2 s × n, six times, then given up.
        let mut v = Session::new();
        v.start_viewing(10, now);
        let mut at = now;
        let mut tries = 1;
        for n in 2..=7u32 {
            at += AVAILABLE_RETRY * (n - 1);
            tries += sends(&v.tick(at)).len();
        }
        assert_eq!(tries, 7);
        at += Duration::from_secs(20);
        assert!(v.tick(at).contains(&Out::Capable {
            capable: false,
            denied_by_sharer: false
        }));
        // A sharer that can't be controlled refuses the handshake.
        let mut locked = Session::new();
        locked.start_sharing(false);
        let out = v.start_viewing(11, now);
        let back = deliver(&out, 20, 11, &mut locked, now);
        assert_eq!(
            sends(&back),
            vec![(20, action::AVAILABLE_NACK, reason::SHARER_CONTROL_DISABLED)]
        );
    }

    #[test]
    fn a_controller_leaving_ends_control() {
        let now = Instant::now();
        let (mut sharer, mut viewer) = (Session::new(), Session::new());
        sharer.start_sharing(true);
        viewer.start_viewing(10, now);
        let ack = deliver(&sharer.give(20, now), 10, 20, &mut viewer, now);
        deliver(&ack, 20, 10, &mut sharer, now);
        let out = sharer.left(&[20]);
        assert!(out.contains(&Out::ControlChanged {
            in_control: false,
            controller: Some(20),
            reason: reason::SHARER_TERMINATED
        }));
        assert_eq!(sharer.controller(), None);
    }
}
