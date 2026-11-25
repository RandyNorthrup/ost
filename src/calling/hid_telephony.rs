//! Headset call controls over HID telephony, as Teams' HID service drives
//! them (Settings ▸ Devices ▸ "Sync device buttons").
//!
//! Teams opens the HID device that belongs to the selected microphone and
//! reads its Telephony page (0x0B): Hook Switch answers a ringing call
//! (off hook) or ends the call (on hook), Phone Mute toggles (relative) or
//! sets (absolute) the mute, Flash answers or holds, and the Button page's
//! usage 7 rejects a ringing call. It drives the LED page back: Off-Hook
//! (0x17) while a call is up, Ring (0x18, Teams' "pulsing") while one
//! rings, Mute (0x09) and Hold (0x20). The Teams button is the vendor page
//! 0xFF99 usage 4; it asks the device for its context over Teams' ASP
//! protocol (feature report 0x9A) and opens what that names.
//!
//! Which buttons count depends on Teams' driver for the device: known
//! vendors' devices (and ones whose UCQ string says headset, speakerphone
//! or Bluetooth) get its "Standard Hook Protect USB" behaviour, everything
//! else only the mute button ("Safe Mute Only driver").
//!
//! On Linux the device is a hidraw node: its report descriptor comes from
//! sysfs, reports are read and written on /dev/hidrawN and feature reports
//! go through HIDIOCSFEATURE / HIDIOCGFEATURE.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock, mpsc};
use std::time::{Duration, Instant};

// ---- HID report descriptors ----

/// HID usage pages Teams reads.
pub const PAGE_LEDS: u16 = 0x08;
pub const PAGE_BUTTON: u16 = 0x09;
pub const PAGE_TELEPHONY: u16 = 0x0B;
/// Teams' vendor page (CustomPage 65433).
pub const PAGE_TEAMS: u16 = 0xFF99;

/// Telephony usages.
pub const HOOK_SWITCH: u16 = 0x20;
pub const FLASH: u16 = 0x21;
pub const PHONE_MUTE: u16 = 0x2F;
/// Button page usage 7: Teams' reject ("Delete").
pub const BUTTON_REJECT: u16 = 0x07;
/// LED usages.
pub const LED_MUTE: u16 = 0x09;
pub const LED_OFF_HOOK: u16 = 0x17;
pub const LED_RING: u16 = 0x18;
pub const LED_HOLD: u16 = 0x20;
/// Teams page usages: its button and the ASP feature report.
pub const TEAMS_BUTTON: u16 = 0x04;
pub const ASP_FEATURE: u16 = 0x03;
/// The ASP feature report's id (Teams' `hn.REPORT_ID`).
pub const ASP_REPORT_ID: u8 = 0x9A;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Input,
    Output,
    Feature,
}

/// One report field: a usage, where its bits are in its report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Field {
    pub kind: Kind,
    pub report_id: u8,
    pub page: u16,
    pub usage: u16,
    /// Bit offset in the report's data (after the report id byte).
    pub bit: u32,
    pub size: u32,
    /// The main item's Relative flag (Teams' `isRelative`).
    pub relative: bool,
    pub logical_min: i32,
}

#[derive(Debug, Clone, Default)]
pub struct Descriptor {
    pub fields: Vec<Field>,
    /// The size of each report's data in bits, by (kind, report id).
    sizes: Vec<(Kind, u8, u32)>,
    pub uses_ids: bool,
}

impl Descriptor {
    /// Parse a HID report descriptor (HID 1.11 §6.2.2). Arrays and
    /// constants advance the bit offset; only variable fields are kept.
    pub fn parse(d: &[u8]) -> Descriptor {
        #[derive(Clone, Default)]
        struct Globals {
            page: u16,
            lmin: i32,
            size: u32,
            count: u32,
            id: u8,
        }
        let mut g = Globals::default();
        let mut stack: Vec<Globals> = Vec::new();
        let mut usages: Vec<(u16, u16)> = Vec::new();
        let mut range: Option<(u32, u32)> = None;
        let mut out = Descriptor::default();
        let mut offsets: HashMap<(u8, u8), u32> = HashMap::new();
        let mut i = 0;
        while i < d.len() {
            let prefix = d[i];
            if prefix == 0xFE {
                // A long item: skip it.
                let len = *d.get(i + 1).unwrap_or(&0) as usize;
                i += 3 + len;
                continue;
            }
            let len = match prefix & 3 {
                3 => 4,
                n => n as usize,
            };
            if i + 1 + len > d.len() {
                break;
            }
            let raw = &d[i + 1..i + 1 + len];
            let mut u: u32 = 0;
            for (k, b) in raw.iter().enumerate() {
                u |= (*b as u32) << (8 * k);
            }
            let s: i32 = match len {
                1 => raw[0] as i8 as i32,
                2 => u as u16 as i16 as i32,
                4 => u as i32,
                _ => 0,
            };
            let tag = prefix & 0xFC;
            i += 1 + len;
            match tag {
                // Main items: Input, Output, Feature.
                0x80 | 0x90 | 0xB0 => {
                    let kind = match tag {
                        0x80 => Kind::Input,
                        0x90 => Kind::Output,
                        _ => Kind::Feature,
                    };
                    let kind_key = match kind {
                        Kind::Input => 0,
                        Kind::Output => 1,
                        Kind::Feature => 2,
                    };
                    let off = offsets.entry((kind_key, g.id)).or_insert(0);
                    let constant = u & 1 != 0;
                    let variable = u & 2 != 0;
                    let relative = u & 4 != 0;
                    // The usages this item's fields take, in order.
                    let mut list: Vec<(u16, u16)> = usages.clone();
                    if let Some((lo, hi)) = range {
                        for v in lo..=hi.min(lo + 255) {
                            let page = if v > 0xFFFF { (v >> 16) as u16 } else { g.page };
                            list.push((page, v as u16));
                        }
                    }
                    if !constant && variable {
                        for n in 0..g.count {
                            let Some(&(page, usage)) = list.get(n as usize).or(list.last()) else {
                                break;
                            };
                            out.fields.push(Field {
                                kind,
                                report_id: g.id,
                                page,
                                usage,
                                bit: *off + n * g.size,
                                size: g.size,
                                relative,
                                logical_min: g.lmin,
                            });
                        }
                    }
                    *off += g.count * g.size;
                    usages.clear();
                    range = None;
                }
                // Collection, End Collection: local items reset.
                0xA0 | 0xC0 => {
                    usages.clear();
                    range = None;
                }
                // Globals.
                0x04 => g.page = u as u16,
                0x14 => g.lmin = s,
                0x74 => g.size = u,
                0x94 => g.count = u,
                0x84 => {
                    g.id = u as u8;
                    out.uses_ids = true;
                }
                0xA4 => stack.push(g.clone()),
                0xB4 => {
                    if let Some(p) = stack.pop() {
                        g = p;
                    }
                }
                // Locals: Usage, Usage Minimum, Usage Maximum.
                0x08 => {
                    if len == 4 {
                        usages.push(((u >> 16) as u16, u as u16));
                    } else {
                        usages.push((g.page, u as u16));
                    }
                }
                0x18 => range = Some((u, range.map_or(u, |r| r.1.max(u)))),
                0x28 => range = Some((range.map_or(0, |r| r.0), u)),
                _ => {}
            }
        }
        for ((k, id), bits) in offsets {
            let kind = match k {
                0 => Kind::Input,
                1 => Kind::Output,
                _ => Kind::Feature,
            };
            out.sizes.push((kind, id, bits));
        }
        out
    }

    pub fn field(&self, kind: Kind, page: u16, usage: u16) -> Option<&Field> {
        self.fields
            .iter()
            .find(|f| f.kind == kind && f.page == page && f.usage == usage)
    }

    /// A report's data length in bytes (without its id).
    pub fn report_len(&self, kind: Kind, id: u8) -> usize {
        self.sizes
            .iter()
            .find(|(k, i, _)| *k == kind && *i == id)
            .map_or(0, |(_, _, bits)| bits.div_ceil(8) as usize)
    }

    /// A telephony device: one with Telephony page inputs (Teams opens
    /// devices on that page).
    pub fn is_telephony(&self) -> bool {
        self.fields
            .iter()
            .any(|f| f.kind == Kind::Input && f.page == PAGE_TELEPHONY)
    }

    /// Teams' ASP: the device has its feature report 0x9A (vendor page
    /// usage 3).
    pub fn has_asp(&self) -> bool {
        self.fields.iter().any(|f| {
            f.kind == Kind::Feature
                && f.report_id == ASP_REPORT_ID
                && f.page == PAGE_TEAMS
                && f.usage == ASP_FEATURE
        })
    }
}

fn get_bits(data: &[u8], bit: u32, size: u32) -> u32 {
    let mut v = 0u32;
    for k in 0..size.min(32) {
        let b = bit + k;
        if let Some(byte) = data.get((b / 8) as usize)
            && byte >> (b % 8) & 1 != 0
        {
            v |= 1 << k;
        }
    }
    v
}

fn set_bits(data: &mut [u8], bit: u32, size: u32, value: u32) {
    for k in 0..size.min(32) {
        let b = bit + k;
        if let Some(byte) = data.get_mut((b / 8) as usize) {
            if value >> k & 1 != 0 {
                *byte |= 1 << (b % 8);
            } else {
                *byte &= !(1 << (b % 8));
            }
        }
    }
}

/// An input element as Teams' HID layer hands it on: page, usage, value,
/// relative.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Element {
    pub page: u16,
    pub usage: u16,
    pub value: i32,
    pub relative: bool,
}

/// The elements of an input report (as read from hidraw: the report id
/// first when the device numbers its reports) that changed since the last
/// one; relative fields count whenever they're set.
pub fn decode_input(
    desc: &Descriptor,
    report: &[u8],
    last: &mut HashMap<(u16, u16), i32>,
) -> Vec<Element> {
    let (id, data) = if desc.uses_ids {
        match report.split_first() {
            Some((id, rest)) => (*id, rest),
            None => return Vec::new(),
        }
    } else {
        (0, report)
    };
    let mut out = Vec::new();
    for f in desc
        .fields
        .iter()
        .filter(|f| f.kind == Kind::Input && f.report_id == id)
    {
        let raw = get_bits(data, f.bit, f.size);
        // Signed when the logical minimum is negative.
        let value =
            if f.logical_min < 0 && f.size > 0 && f.size < 32 && raw >> (f.size - 1) & 1 != 0 {
                raw as i32 - (1 << f.size)
            } else {
                raw as i32
            };
        let key = (f.page, f.usage);
        if f.relative {
            if value != 0 {
                out.push(Element {
                    page: f.page,
                    usage: f.usage,
                    value,
                    relative: true,
                });
            }
            last.insert(key, value);
        } else if last.get(&key) != Some(&value) {
            let first = !last.contains_key(&key);
            last.insert(key, value);
            // The first report only sets the baseline, unless something is
            // pressed in it.
            if !first || value != 0 {
                out.push(Element {
                    page: f.page,
                    usage: f.usage,
                    value,
                    relative: false,
                });
            }
        }
    }
    out
}

/// The output reports (id first when numbered) that set these LEDs.
pub fn encode_leds(
    desc: &Descriptor,
    leds: &[(u16, bool)],
    current: &HashMap<u16, bool>,
) -> Vec<Vec<u8>> {
    let mut ids: Vec<u8> = Vec::new();
    for (usage, _) in leds {
        if let Some(f) = desc.field(Kind::Output, PAGE_LEDS, *usage)
            && !ids.contains(&f.report_id)
        {
            ids.push(f.report_id);
        }
    }
    ids.into_iter()
        .map(|id| {
            let mut data = vec![0u8; desc.report_len(Kind::Output, id)];
            for f in desc
                .fields
                .iter()
                .filter(|f| f.kind == Kind::Output && f.report_id == id && f.page == PAGE_LEDS)
            {
                let on = leds
                    .iter()
                    .find(|(u, _)| *u == f.usage)
                    .map(|(_, v)| *v)
                    .or_else(|| current.get(&f.usage).copied())
                    .unwrap_or(false);
                set_bits(&mut data, f.bit, f.size, on as u32);
            }
            if desc.uses_ids {
                let mut r = vec![id];
                r.extend(data);
                r
            } else {
                data
            }
        })
        .collect()
}

// ---- Teams' ASP (Teams-certified device) messages ----

/// ASP message ids (Teams' `xi`).
pub mod msg {
    pub const VERSION: u8 = 0;
    pub const FEATURE: u8 = 1;
    pub const LOCALE: u8 = 2;
    pub const EVENT: u8 = 3;
    pub const CONTEXT: u8 = 4;
}

/// ASP notification events (Teams' `vt`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AspEvent {
    None = 0,
    MissedCall = 1,
    Meeting = 2,
    Voicemail = 4,
    Dialer = 8,
}

impl AspEvent {
    pub fn from_u8(v: u8) -> AspEvent {
        match v {
            1 => AspEvent::MissedCall,
            2 => AspEvent::Meeting,
            4 => AspEvent::Voicemail,
            8 => AspEvent::Dialer,
            _ => AspEvent::None,
        }
    }
}

/// Teams' press types in a context's metadata (`Vs`).
pub const SHORT_PRESS: u8 = 1;
pub const LONG_PRESS: u8 = 2;

/// An ASP message (Teams' `hn`): id and metadata flag in one byte, a
/// big-endian payload length and payload, then (with the flag) the
/// metadata's.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct AspMessage {
    pub id: u8,
    pub payload: Vec<u8>,
    pub metadata: Option<Vec<u8>>,
}

impl AspMessage {
    pub fn new(id: u8, payload: Vec<u8>) -> AspMessage {
        AspMessage {
            id,
            payload,
            metadata: None,
        }
    }

    pub fn serialize(&self) -> Vec<u8> {
        let mut e = vec![ASP_REPORT_ID, self.id << 4 | self.metadata.is_some() as u8];
        e.push((self.payload.len() >> 8) as u8);
        e.push(self.payload.len() as u8);
        e.extend(&self.payload);
        if let Some(m) = &self.metadata {
            e.push((m.len() >> 8) as u8);
            e.push(m.len() as u8);
            e.extend(m);
        }
        e
    }

    /// Parse a feature report read back (report id first).
    pub fn parse(e: &[u8]) -> Option<AspMessage> {
        if e.len() < 4 {
            return None;
        }
        let id = e[1] >> 4;
        let flag = e[1] & 15;
        let len = (e[2] as usize) << 8 | e[3] as usize;
        let mut t = 4;
        let payload = e.get(t..t + len)?.to_vec();
        t += len;
        let metadata = if flag != 0 && e.len() > t + 1 {
            let ml = (e[t] as usize) << 8 | e[t + 1] as usize;
            Some(e.get(t + 2..t + 2 + ml).unwrap_or(&[]).to_vec())
        } else {
            None
        };
        Some(AspMessage {
            id,
            payload,
            metadata,
        })
    }
}

/// Teams' setLocaleAndTime body: `L<locale>D<yyyy-MM-ddThh:mm:ss>` (12-hour).
pub fn locale_payload(locale: &str, now: chrono::NaiveDateTime) -> Vec<u8> {
    format!("L{locale}D{}", now.format("%Y-%m-%dT%I:%M:%S")).into_bytes()
}

// ---- Teams' drivers ----

/// Teams' HID driver for a device.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Driver {
    /// "Standard Hook Protect USB" (and its speakerphone, Bluetooth and
    /// desk phone variants): hook switch, flash, mute and reject.
    HookProtect,
    /// "Safe Mute Only driver": the mute button only.
    MuteOnly,
    /// "UnSupported": a device on Teams' `hidDevicesBlacklist`; its
    /// buttons aren't read.
    Unsupported,
}

/// Teams' vendor ids (`_r`) whose devices get the hook-protect driver
/// with or without a UCQ string: the ones it defaults to it
/// (`getDriverUsingUCQ(…, true)`: EPOS, Microsoft, Plantronics, Jabra,
/// Polycom, Yealink, Bose; prod `allowHookByVendorId`) and the ones it
/// gives it outright (Sony, Cisco, Bang & Olufsen, AudioCodes, Anker,
/// Sennheiser, Onward, Shure, Legrand).
pub const HOOK_VENDORS: [u16; 16] = [
    5013, 1118, 1151, 2830, 2397, 27027, 1447, 1356, 1446, 3284, 3430, 10522, 4983, 14145, 5357,
    9665,
];

/// Teams' vendors whose other devices need a UCQ string for call controls
/// (Logitech, HP, Lenovo, Dell: `getDriverUsingUCQ(…, !isUcqImplemented)`),
/// with the products it names a call-control driver for.
pub const UCQ_VENDOR_PRODUCTS: [(u16, &[u16]); 4] = [
    // Logitech: H650e, H570e, H820e, Zone Wired, Meetup, ConferenceCam
    // Connect, Group speaker, Rally, speakerphone dock, Zone Wireless (2),
    // Zone True Wireless.
    (
        1133,
        &[
            2630, 2646, 2633, 2733, 2151, 2124, 2135, 2181, 2764, 2704, 2800, 2728,
        ],
    ),
    // HP Slice.
    (1008, &[3430]),
    // Lenovo HUB500, HUB700.
    (6127, &[40983, 40984]),
    // Dell C2422HE, C2722DE, C3422WE, BT100 audio, HR024.
    (16700, &[49163, 49165, 49167, 33281, 33282, 33283, 42279]),
];

/// Teams' prod `hidDevicesBlacklist`: devices it opens no driver for.
pub const BLACKLIST: [(u16, &[u16]); 4] = [
    (0x047F, &[0xAF08, 0xC002, 0xCA00, 0xDA41]),
    (0x0B0E, &[0x235E, 0x24ED, 0xA346]),
    (0x046D, &[0x0A38, 0x0A3A]),
    (0x291A, &[0x3301, 0x3523]),
];

/// The USB string descriptor Teams reads a device's UCQ string from: its
/// native HID layer answers `property("UCQ")` with HidD_GetIndexedString
/// of index 0x21.
pub const UCQ_STRING_INDEX: u8 = 0x21;

/// Teams' driver choice (`hidDeviceDriverFactory.getDeviceDriver` with its
/// prod config: `useUCQToAssignDeviceDrivers`, `consolidateDrivers` and
/// `allowHookByVendorId` on): a blacklisted device gets none; one with a
/// UCQ string (any text at string 0x21) gets the hook-protect driver;
/// without one, the hook-protect vendors' devices and the named products
/// still do, and everything else gets mute only.
pub fn driver_for(vendor: u16, product: u16, ucq: Option<&str>) -> Driver {
    if BLACKLIST
        .iter()
        .any(|(v, p)| *v == vendor && p.contains(&product))
    {
        return Driver::Unsupported;
    }
    if ucq.is_some_and(|u| !u.is_empty()) {
        return Driver::HookProtect;
    }
    let named = UCQ_VENDOR_PRODUCTS
        .iter()
        .any(|(v, p)| *v == vendor && p.contains(&product));
    if HOOK_VENDORS.contains(&vendor) || named {
        Driver::HookProtect
    } else {
        Driver::MuteOnly
    }
}

/// What a UCQ string says the device is (Teams' `Pa` positions; Teams logs
/// them and picks the driver variant from them).
pub fn ucq_kind(ucq: &str) -> &'static str {
    let at = |i: usize| ucq.as_bytes().get(i) == Some(&b'1');
    match () {
        _ if at(4) && at(11) => "wireless speakerphone",
        _ if at(4) => "speakerphone",
        _ if at(11) => "wireless",
        _ if at(6) => "headset",
        _ if at(5) => "handset",
        _ => "other",
    }
}

/// What the app is doing, as Teams' HID service keeps it (`appState`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct AppState {
    /// No call (Teams' `hooked`); a ringing call is still hooked.
    pub hooked: bool,
    /// A call is ringing (Teams' `pulsing`).
    pub ringing: bool,
    /// The call's mute.
    pub muted: bool,
    /// The pre-join screen is up, and its mic is off.
    pub in_prejoin: bool,
    pub prejoin_muted: bool,
    pub held: bool,
}

/// What a button asks the app to do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Answer,
    Reject,
    HangUp,
    /// Mute (true) or unmute the call, or the pre-join mic.
    SetMuted(bool),
    ToggleHold,
    /// The Teams button, with the context the device gave.
    TeamsButton {
        event: AspEvent,
        long: bool,
    },
    /// Another OST holds the headset's buttons and a device is connected:
    /// Teams asks whether to take them ("Transfer audio device buttons to
    /// this app?").
    TransferPrompt,
}

/// Teams' hook protection: after an off hook or mute from the device, or
/// the app taking the device off hook, on-hook reports are ignored for a
/// while (`hookProtectionTimeout`: prod `hookProtectionTimeoutConfig`,
/// 1100 ms; `aL`, 1 s, without it).
pub const HOOK_PROTECT: Duration = Duration::from_millis(1100);

/// One device's button logic (Teams' driver over its `appState`).
#[derive(Debug, Clone)]
pub struct Buttons {
    pub driver: Driver,
    hook_disabled_until: Option<Instant>,
    /// The LEDs as last set.
    pub leds: HashMap<u16, bool>,
}

impl Buttons {
    pub fn new(driver: Driver) -> Buttons {
        Buttons {
            driver,
            hook_disabled_until: None,
            leds: HashMap::new(),
        }
    }

    fn hook_disabled(&self, now: Instant) -> bool {
        self.hook_disabled_until.is_some_and(|t| now < t)
    }

    pub fn hook_protect(&mut self, now: Instant) {
        self.hook_disabled_until = Some(now + HOOK_PROTECT);
    }

    fn mute_disabled(app: &AppState) -> bool {
        // Teams' isMuteDisabled: no call and not in the pre-join screen.
        app.hooked && !app.in_prejoin
    }

    fn muted_now(app: &AppState) -> bool {
        app.muted || (app.in_prejoin && app.prejoin_muted)
    }

    /// One input element: the actions it asks for, and LEDs set at once
    /// (Teams lights the mute LED before muting).
    pub fn on_input(
        &mut self,
        e: Element,
        app: &AppState,
        now: Instant,
    ) -> (Vec<Action>, Vec<(u16, bool)>) {
        let mut actions = Vec::new();
        let mut leds = Vec::new();
        match (e.page, e.usage) {
            (PAGE_TELEPHONY, PHONE_MUTE) => {
                if Self::mute_disabled(app) {
                    return (actions, leds);
                }
                let muted = Self::muted_now(app);
                if e.relative {
                    if e.value == 0 {
                        return (actions, leds);
                    }
                    self.hook_protect(now);
                    leds.push((LED_MUTE, !muted));
                    actions.push(Action::SetMuted(!muted));
                } else if (e.value == 1) != muted {
                    self.hook_protect(now);
                    actions.push(Action::SetMuted(e.value == 1));
                }
            }
            _ if self.driver == Driver::MuteOnly => {}
            (PAGE_TELEPHONY, HOOK_SWITCH) => {
                if e.value == 1 {
                    // Off hook: answers a ringing call (Teams ignores it
                    // while a call is already up).
                    if app.hooked || app.ringing {
                        self.hook_protect(now);
                        if app.ringing {
                            actions.push(Action::Answer);
                        }
                    }
                } else if !self.hook_disabled(now) && !app.ringing && !app.hooked {
                    actions.push(Action::HangUp);
                }
            }
            (PAGE_TELEPHONY, FLASH) => {
                if e.relative && e.value == 0 {
                    return (actions, leds);
                }
                self.hook_protect(now);
                if app.ringing {
                    actions.push(Action::Answer);
                } else if !app.hooked {
                    actions.push(Action::ToggleHold);
                }
            }
            (PAGE_BUTTON, BUTTON_REJECT) => {
                if !self.hook_disabled(now) && e.value == 1 && app.ringing {
                    actions.push(Action::Reject);
                }
            }
            _ => {}
        }
        (actions, leds)
    }

    /// The LEDs Teams sets for this state: Off-Hook while a call is up,
    /// Ring while one rings, Mute with the call's (or the pre-join's) mute,
    /// Hold while held. Returns the ones that change.
    pub fn leds_for(&mut self, app: &AppState, now: Instant) -> Vec<(u16, bool)> {
        let want = [
            (LED_OFF_HOOK, !app.hooked),
            (LED_RING, app.ringing),
            (
                LED_MUTE,
                if app.hooked {
                    app.in_prejoin && app.prejoin_muted
                } else {
                    app.muted
                },
            ),
            (LED_HOLD, !app.hooked && app.held),
        ];
        let mut changed = Vec::new();
        for (usage, on) in want {
            if self.leds.get(&usage) != Some(&on) {
                // Teams' offHook on its hook-protect driver protects the
                // hook switch from the device's own answer to it.
                if usage == LED_OFF_HOOK && on {
                    self.hook_protect(now);
                }
                changed.push((usage, on));
            }
        }
        changed
    }
}

// ---- Devices (Linux hidraw) ----

/// A hidraw device.
#[derive(Debug, Clone)]
pub struct HidDevice {
    pub node: String,
    pub vendor: u16,
    pub product: u16,
    pub name: String,
    pub desc: Descriptor,
    /// Its USB device in sysfs, if on USB.
    pub usb_path: Option<std::path::PathBuf>,
    /// Its USB interface in sysfs (where its hiddev node is), if on USB.
    pub usb_interface: Option<std::path::PathBuf>,
}

/// The telephony HID devices (hidraw nodes with a Telephony page).
#[cfg(target_os = "linux")]
pub fn telephony_devices() -> Vec<HidDevice> {
    let mut out = Vec::new();
    let Ok(dir) = std::fs::read_dir("/sys/class/hidraw") else {
        return out;
    };
    for entry in dir.flatten() {
        let base = entry.path().join("device");
        let Ok(uevent) = std::fs::read_to_string(base.join("uevent")) else {
            continue;
        };
        let Ok(rd) = std::fs::read(base.join("report_descriptor")) else {
            continue;
        };
        let desc = Descriptor::parse(&rd);
        if !desc.is_telephony() {
            continue;
        }
        let mut vendor = 0;
        let mut product = 0;
        let mut name = String::new();
        let mut bus = 0;
        for line in uevent.lines() {
            if let Some(v) = line.strip_prefix("HID_ID=") {
                let p: Vec<&str> = v.split(':').collect();
                if p.len() == 3 {
                    bus = u32::from_str_radix(p[0], 16).unwrap_or(0);
                    vendor = u32::from_str_radix(p[1], 16).unwrap_or(0) as u16;
                    product = u32::from_str_radix(p[2], 16).unwrap_or(0) as u16;
                }
            } else if let Some(v) = line.strip_prefix("HID_NAME=") {
                name = v.to_string();
            }
        }
        // …/hidrawN/device is the HID device under its USB interface.
        let usb_interface = (bus == 3)
            .then(|| std::fs::canonicalize(base.join("..")).ok())
            .flatten()
            .filter(|p| p.join("bInterfaceNumber").exists());
        let usb_path = usb_interface
            .as_deref()
            .and_then(|i| std::fs::canonicalize(i.join("..")).ok())
            .filter(|p| p.join("busnum").exists());
        out.push(HidDevice {
            node: format!("/dev/{}", entry.file_name().to_string_lossy()),
            vendor,
            product,
            name,
            desc,
            usb_path,
            usb_interface,
        });
    }
    out.sort_by(|a, b| a.node.cmp(&b.node));
    out
}

#[cfg(not(target_os = "linux"))]
pub fn telephony_devices() -> Vec<HidDevice> {
    Vec::new()
}

/// Where a device's UCQ string came from, for the log.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UcqSource {
    /// HIDIOCGSTRING on its hiddev node: the HID class's indexed string,
    /// as Teams' HidD_GetIndexedString.
    Hiddev,
    /// A GET_DESCRIPTOR control transfer through usbfs.
    Usbfs,
}

/// The device's UCQ string: USB string descriptor 0x21, read the way
/// Teams reads it (an indexed string through the HID class driver: on
/// Linux the hiddev node's HIDIOCGSTRING), else with a control transfer on
/// its usbfs node. `Err` says why neither could ask the device; `Ok(None)`:
/// the device has no string 0x21.
#[cfg(target_os = "linux")]
fn read_ucq(dev: &HidDevice) -> Result<Option<(String, UcqSource)>, String> {
    let mut why = Vec::new();
    if let Some(intf) = dev.usb_interface.as_deref() {
        match hiddev_node(intf) {
            Some(node) => match hiddev_string(&node, UCQ_STRING_INDEX) {
                Ok(s) => return Ok(s.map(|s| (s, UcqSource::Hiddev))),
                Err(e) => why.push(format!("{node}: {e}")),
            },
            None => why.push("no hiddev node".into()),
        }
    }
    if let Some(usb) = dev.usb_path.as_deref() {
        match usbfs_string(usb, UCQ_STRING_INDEX) {
            Ok(s) => return Ok(s.map(|s| (s, UcqSource::Usbfs))),
            Err(e) => why.push(e),
        }
    }
    Err(why.join("; "))
}

/// The hiddev node (`/dev/usb/hiddevN`) of a USB HID interface.
#[cfg(target_os = "linux")]
fn hiddev_node(intf: &std::path::Path) -> Option<String> {
    let dir = std::fs::read_dir(intf.join("usbmisc")).ok()?;
    let name = dir
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .find(|n| n.starts_with("hiddev"))?;
    ["/dev/usb/", "/dev/"]
        .iter()
        .map(|d| format!("{d}{name}"))
        .find(|p| std::path::Path::new(p).exists())
}

/// HIDIOCGSTRING: a string descriptor of a hiddev's USB device, in UTF-8.
#[cfg(target_os = "linux")]
fn hiddev_string(node: &str, index: u8) -> Result<Option<String>, String> {
    use std::os::fd::AsRawFd;
    #[repr(C)]
    struct StringDescriptor {
        index: i32,
        value: [u8; 256],
    }
    let file = std::fs::File::open(node).map_err(|e| e.to_string())?;
    let mut d = StringDescriptor {
        index: index as i32,
        value: [0; 256],
    };
    // _IOR('H', 0x04, struct hiddev_string_descriptor)
    let req = (2u64 << 30)
        | ((std::mem::size_of::<StringDescriptor>() as u64) << 16)
        | ((b'H' as u64) << 8)
        | 0x04;
    // SAFETY: an open hiddev fd and a buffer of the ioctl's size.
    let n = unsafe { libc::ioctl(file.as_raw_fd(), req as _, &mut d) };
    if n < 0 {
        let e = std::io::Error::last_os_error();
        // EPIPE / EINVAL: the device stalls the request (no such string).
        return match e.raw_os_error() {
            Some(libc::EPIPE) | Some(libc::EINVAL) => Ok(None),
            _ => Err(e.to_string()),
        };
    }
    let len = d
        .value
        .iter()
        .position(|b| *b == 0)
        .unwrap_or(d.value.len());
    Ok((len > 0).then(|| String::from_utf8_lossy(&d.value[..len]).into_owned()))
}

/// A string descriptor through usbfs (needs write access to its node).
#[cfg(target_os = "linux")]
fn usbfs_string(usb: &std::path::Path, index: u8) -> Result<Option<String>, String> {
    use std::os::fd::AsRawFd;
    let num = |f: &str| {
        std::fs::read_to_string(usb.join(f))
            .ok()?
            .trim()
            .parse::<u32>()
            .ok()
    };
    let (Some(bus), Some(devnum)) = (num("busnum"), num("devnum")) else {
        return Err("no usbfs node".into());
    };
    let path = format!("/dev/bus/usb/{bus:03}/{devnum:03}");
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&path)
        .map_err(|e| format!("{path}: {e}"))?;
    #[repr(C)]
    struct Ctrl {
        request_type: u8,
        request: u8,
        value: u16,
        index: u16,
        length: u16,
        timeout: u32,
        data: *mut libc::c_void,
    }
    // _IOWR('U', 0, struct usbdevfs_ctrltransfer)
    let req = (3u64 << 30) | ((std::mem::size_of::<Ctrl>() as u64) << 16) | ((b'U' as u64) << 8);
    let get = |index: u8, lang: u16| -> Option<Vec<u8>> {
        let mut buf = [0u8; 255];
        let mut c = Ctrl {
            request_type: 0x80,
            request: 6,
            value: 0x0300 | index as u16,
            index: lang,
            length: 255,
            timeout: 500,
            data: buf.as_mut_ptr().cast(),
        };
        // SAFETY: a valid usbfs fd and a control transfer into `buf`.
        let n = unsafe { libc::ioctl(file.as_raw_fd(), req as _, &mut c) };
        (n > 0).then(|| buf[..n as usize].to_vec())
    };
    let Some(langs) = get(0, 0) else {
        return Ok(None);
    };
    let lang = if langs.len() >= 4 {
        u16::from_le_bytes([langs[2], langs[3]])
    } else {
        0x0409
    };
    let Some(d) = get(index, lang) else {
        return Ok(None);
    };
    let units: Vec<u16> = d
        .get(2..)
        .unwrap_or(&[])
        .chunks(2)
        .filter(|c| c.len() == 2)
        .map(|c| u16::from_le_bytes([c[0], c[1]]))
        .collect();
    let s = String::from_utf16_lossy(&units);
    Ok((!s.is_empty()).then_some(s))
}

#[cfg(target_os = "linux")]
mod io {
    use std::os::fd::{AsRawFd, OwnedFd};

    fn ioc(dir: u64, nr: u64, size: usize) -> u64 {
        (dir << 30) | ((size as u64) << 16) | ((b'H' as u64) << 8) | nr
    }

    pub fn open(node: &str) -> std::io::Result<OwnedFd> {
        use std::os::unix::fs::OpenOptionsExt;
        let f = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(node)?;
        Ok(f.into())
    }

    pub fn write(fd: &OwnedFd, data: &[u8]) -> bool {
        // SAFETY: writing a buffer to an open hidraw fd.
        unsafe {
            libc::write(fd.as_raw_fd(), data.as_ptr().cast(), data.len()) == data.len() as isize
        }
    }

    /// Wait up to `ms` for a report, then read it.
    pub fn read(fd: &OwnedFd, ms: i32) -> Result<Option<Vec<u8>>, ()> {
        let mut p = libc::pollfd {
            fd: fd.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: one pollfd for an open fd.
        let n = unsafe { libc::poll(&mut p, 1, ms) };
        if n <= 0 {
            return Ok(None);
        }
        if p.revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0 {
            return Err(());
        }
        let mut buf = [0u8; 256];
        // SAFETY: reading into a local buffer.
        let r = unsafe { libc::read(fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
        match r {
            n if n > 0 => Ok(Some(buf[..n as usize].to_vec())),
            0 => Err(()),
            _ if std::io::Error::last_os_error().kind() == std::io::ErrorKind::WouldBlock => {
                Ok(None)
            }
            _ => Err(()),
        }
    }

    /// HIDIOCSFEATURE: send a feature report (id first).
    pub fn set_feature(fd: &OwnedFd, data: &[u8]) -> bool {
        let mut buf = data.to_vec();
        // SAFETY: the ioctl reads `buf.len()` bytes.
        unsafe {
            libc::ioctl(
                fd.as_raw_fd(),
                ioc(3, 0x06, buf.len()) as _,
                buf.as_mut_ptr(),
            ) >= 0
        }
    }

    /// HIDIOCGFEATURE: read a feature report back (id first).
    pub fn get_feature(fd: &OwnedFd, id: u8, len: usize) -> Option<Vec<u8>> {
        let mut buf = vec![0u8; len];
        buf[0] = id;
        // SAFETY: the ioctl writes at most `buf.len()` bytes.
        let n = unsafe {
            libc::ioctl(
                fd.as_raw_fd(),
                ioc(3, 0x07, buf.len()) as _,
                buf.as_mut_ptr(),
            )
        };
        (n > 0).then(|| buf[..n as usize].to_vec())
    }
}

// ---- Which OST answers the buttons (Teams' HID2 multi-app control) ----

/// The file naming the OST process that has the headset's buttons.
fn control_file() -> std::path::PathBuf {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    dir.join("ost-hid-control")
}

fn control_holder() -> Option<u32> {
    let pid: u32 = std::fs::read_to_string(control_file())
        .ok()?
        .trim()
        .parse()
        .ok()?;
    // A holder that has gone frees it.
    std::path::Path::new(&format!("/proc/{pid}"))
        .exists()
        .then_some(pid)
}

fn claim_control() {
    let _ = std::fs::write(control_file(), std::process::id().to_string());
}

// ---- The service ----

/// What the service is doing (for Settings and the logs).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Status {
    /// The headset in use, by name.
    pub device: Option<String>,
    pub driver: Option<String>,
    pub asp: bool,
    /// This OST has the buttons (Teams' hasHidControl).
    pub has_control: bool,
    pub sync_enabled: bool,
}

enum Cmd {
    State(AppState),
    Prefs { mic: Option<String>, sync: bool },
    TakeControl,
    Push(AspEvent),
}

struct Service {
    tx: Mutex<mpsc::Sender<Cmd>>,
    status: Mutex<Status>,
}

static SERVICE: OnceLock<Service> = OnceLock::new();
/// Preferences given before the service started.
static PREFS: Mutex<Option<(Option<String>, bool)>> = Mutex::new(None);

/// Start the headset service; `on_action` runs on its thread for each
/// button action.
pub fn start(on_action: impl Fn(Action) + Send + 'static) {
    if SERVICE.get().is_some() {
        return;
    }
    let (tx, rx) = mpsc::channel();
    let prefs = PREFS.lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some((mic, sync)) = prefs {
        let _ = tx.send(Cmd::Prefs { mic, sync });
    }
    let _ = SERVICE.set(Service {
        tx: Mutex::new(tx),
        status: Mutex::new(Status {
            sync_enabled: true,
            ..Status::default()
        }),
    });
    std::thread::Builder::new()
        .name("ost-hid".into())
        .spawn(move || run(rx, Box::new(on_action)))
        .ok();
}

fn send(cmd: Cmd) {
    if let Some(s) = SERVICE.get() {
        let _ = s.tx.lock().unwrap_or_else(|e| e.into_inner()).send(cmd);
    }
}

/// The app's state changed (the headset's LEDs follow it).
pub fn set_app_state(state: AppState) {
    send(Cmd::State(state));
}

/// The selected microphone (its name as OST lists it; `None` for the
/// system default) and Teams' "Sync device buttons".
pub fn set_preferences(mic: Option<String>, sync: bool) {
    if SERVICE.get().is_none() {
        *PREFS.lock().unwrap_or_else(|e| e.into_inner()) = Some((mic, sync));
        return;
    }
    send(Cmd::Prefs { mic, sync });
}

/// Teams' "Transfer controls to this app".
pub fn take_control() {
    send(Cmd::TakeControl);
}

/// Teams' push notification to a Teams device (a missed call; `None`
/// clears it).
pub fn push_notification(event: AspEvent) {
    send(Cmd::Push(event));
}

pub fn status() -> Status {
    SERVICE
        .get()
        .map(|s| s.status.lock().unwrap_or_else(|e| e.into_inner()).clone())
        .unwrap_or(Status {
            sync_enabled: true,
            ..Status::default()
        })
}

fn set_status(f: impl FnOnce(&mut Status)) {
    if let Some(s) = SERVICE.get() {
        f(&mut s.status.lock().unwrap_or_else(|e| e.into_inner()));
    }
}

/// The USB ids of the microphone's device (the selected one, else the
/// system default), from PipeWire.
fn mic_ids(mic: Option<&str>) -> Option<(u16, u16)> {
    let endpoints = crate::calling::room_devices::audio_endpoints();
    #[cfg(all(feature = "audio", target_os = "linux"))]
    let default = || crate::calling::pw_defaults::default_endpoints().0;
    #[cfg(not(all(feature = "audio", target_os = "linux")))]
    let default = || None::<String>;
    let name = mic.map(str::to_string).or_else(default)?;
    let e = endpoints.iter().find(|e| !e.sink && e.name == name)?;
    Some((e.vendor_id?, e.product_id?))
}

#[cfg(target_os = "linux")]
struct Open {
    dev: HidDevice,
    fd: std::os::fd::OwnedFd,
    buttons: Buttons,
    last: HashMap<(u16, u16), i32>,
    asp: bool,
    asp_attempts: u32,
}

#[cfg(target_os = "linux")]
impl Open {
    fn write_leds(&mut self, changes: &[(u16, bool)]) {
        let changes: Vec<(u16, bool)> = changes
            .iter()
            .copied()
            .filter(|(u, _)| self.dev.desc.field(Kind::Output, PAGE_LEDS, *u).is_some())
            .collect();
        if changes.is_empty() {
            return;
        }
        for r in encode_leds(&self.dev.desc, &changes, &self.buttons.leds) {
            if !io::write(&self.fd, &r) {
                tracing::info!(device = %self.dev.name, "headset: writing its LEDs failed");
            }
        }
        for (u, on) in &changes {
            self.buttons.leds.insert(*u, *on);
        }
        tracing::info!(device = %self.dev.name, ?changes, "headset: LEDs");
    }

    /// Send an ASP message and read the device's answer.
    fn asp(&self, m: &AspMessage) -> Option<AspMessage> {
        let len = self.dev.desc.report_len(Kind::Feature, ASP_REPORT_ID) + 1;
        let mut out = m.serialize();
        if out.len() > len {
            return None;
        }
        out.resize(len, 0);
        if !io::set_feature(&self.fd, &out) {
            tracing::info!("headset: ASP set feature failed");
            return None;
        }
        let back = io::get_feature(&self.fd, ASP_REPORT_ID, len)?;
        let r = AspMessage::parse(&back)?;
        (r.id == m.id && (!r.payload.is_empty())).then_some(r)
    }

    /// Teams' initASP: Version (protocol 1), then the events it supports,
    /// then (with the dialer) the locale and time.
    fn init_asp(&mut self) {
        if !self.dev.desc.has_asp() || self.asp_attempts > 5 {
            return;
        }
        self.asp_attempts += 1;
        let ok = (|| {
            let v = self.asp(&AspMessage::new(msg::VERSION, vec![]))?;
            if v.payload.first() != Some(&1) {
                return None;
            }
            let mask = *self
                .asp(&AspMessage::new(msg::FEATURE, vec![]))?
                .payload
                .first()?;
            if mask == 0 {
                return None;
            }
            if mask & AspEvent::Dialer as u8 != 0 {
                self.asp(&AspMessage::new(
                    msg::LOCALE,
                    locale_payload("en-US", chrono::Local::now().naive_local()),
                ))?;
            }
            Some(mask)
        })();
        self.asp = ok.is_some();
        if self.asp {
            self.asp_attempts = 0;
        }
        tracing::info!(device = %self.dev.name, events = ?ok, "headset: ASP {}", if self.asp { "connected" } else { "unavailable" });
    }
}

fn run(rx: mpsc::Receiver<Cmd>, on_action: Box<dyn Fn(Action) + Send>) {
    #[cfg(target_os = "linux")]
    run_linux(rx, on_action);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = on_action;
        while rx.recv().is_ok() {}
    }
}

#[cfg(target_os = "linux")]
fn run_linux(rx: mpsc::Receiver<Cmd>, on_action: Box<dyn Fn(Action) + Send>) {
    let mut app = AppState {
        hooked: true,
        ..AppState::default()
    };
    let mut mic: Option<String> = None;
    let mut sync = true;
    let mut open: Option<Open> = None;
    let mut want: Option<(u16, u16)> = None;
    let mut last_scan: Option<Instant> = None;
    let mut last_pw: Option<Instant> = None;
    let mut prompted = false;
    let mut mine = false;
    loop {
        // Commands from the app.
        loop {
            match rx.try_recv() {
                Ok(Cmd::State(s)) => {
                    app = s;
                    if let Some(o) = open.as_mut()
                        && sync
                        && mine
                    {
                        let ch = o.buttons.leds_for(&app, Instant::now());
                        o.write_leds(&ch);
                    }
                }
                Ok(Cmd::Prefs { mic: m, sync: s }) => {
                    if m != mic || last_scan.is_none() {
                        mic = m;
                        want = None;
                        last_pw = None;
                        last_scan = None;
                        if open
                            .as_ref()
                            .is_some_and(|o| Some((o.dev.vendor, o.dev.product)) != want)
                        {
                            tracing::info!("headset: the microphone changed");
                            open = None;
                        }
                    }
                    sync = s;
                    set_status(|st| st.sync_enabled = s);
                }
                Ok(Cmd::TakeControl) => {
                    claim_control();
                    tracing::info!(
                        "headset: took the device's buttons (Transfer controls to this app)"
                    );
                }
                Ok(Cmd::Push(ev)) => {
                    if let Some(o) = open.as_mut()
                        && o.asp
                    {
                        let mut m = AspMessage::new(msg::EVENT, vec![ev as u8]);
                        m.metadata = None;
                        let ok = o.asp(&m).is_some();
                        tracing::info!(?ev, ok, "headset: ASP push notification");
                    }
                }
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => return,
            }
        }
        // Teams' HID2 control: take it when free; if another OST has it
        // while a device is here, ask once.
        let holder = control_holder();
        if holder.is_none() {
            claim_control();
        }
        let now_mine = control_holder() == Some(std::process::id());
        if now_mine != mine {
            mine = now_mine;
            tracing::info!(has_control = mine, "headset: button control");
            set_status(|st| st.has_control = mine);
            if !mine {
                open = None;
                // Another app took the buttons ("Transfer controls"): no
                // prompt to take them straight back; Devices' "Transfer
                // controls to this app" does that.
                prompted = true;
            } else {
                last_scan = None;
                prompted = false;
            }
        }
        // Find the selected microphone's HID device.
        if open.is_none() && last_scan.is_none_or(|t| t.elapsed() > Duration::from_secs(3)) {
            last_scan = Some(Instant::now());
            let devices = telephony_devices();
            // Ask PipeWire which device the microphone is on only while a
            // telephony device is here that isn't it (every 10 s at most).
            let matched = devices.iter().any(|d| Some((d.vendor, d.product)) == want);
            if !devices.is_empty()
                && !matched
                && last_pw.is_none_or(|t| t.elapsed() > Duration::from_secs(10))
            {
                last_pw = Some(Instant::now());
                want = mic_ids(mic.as_deref());
            }
            if !mine {
                if !devices.is_empty() && !prompted {
                    prompted = true;
                    on_action(Action::TransferPrompt);
                }
            } else if let Some(dev) = devices
                .into_iter()
                .find(|d| Some((d.vendor, d.product)) == want)
            {
                // Teams reads the UCQ string with the device's properties,
                // before it picks a driver.
                let ucq = read_ucq(&dev);
                let ucq_text = ucq
                    .as_ref()
                    .ok()
                    .and_then(|u| u.as_ref().map(|(s, _)| s.clone()));
                let driver = driver_for(dev.vendor, dev.product, ucq_text.as_deref());
                match &ucq {
                    Ok(Some((s, from))) => {
                        tracing::info!(device = %dev.name, ucq = %s, kind = ucq_kind(s), ?from, "headset: UCQ string")
                    }
                    Ok(None) => tracing::info!(device = %dev.name, "headset: no UCQ string"),
                    Err(e) => {
                        tracing::info!(device = %dev.name, "headset: can't read the UCQ string ({e}); needs read access to its hiddev node")
                    }
                }
                if driver == Driver::Unsupported {
                    tracing::info!(device = %dev.name, vendor = format!("{:04x}", dev.vendor), product = format!("{:04x}", dev.product), "headset: not supported (Teams' HID blacklist)");
                    continue;
                }
                match io::open(&dev.node) {
                    Ok(fd) => {
                        tracing::info!(device = %dev.name, node = %dev.node, ?driver, asp = dev.desc.has_asp(), "headset: opened");
                        let mut o = Open {
                            dev,
                            fd,
                            buttons: Buttons::new(driver),
                            last: HashMap::new(),
                            asp: false,
                            asp_attempts: 0,
                        };
                        o.init_asp();
                        // Teams syncs a newly selected device with the app.
                        if sync {
                            let ch = o.buttons.leds_for(&app, Instant::now());
                            o.write_leds(&ch);
                        }
                        let (name, asp) = (o.dev.name.clone(), o.asp);
                        set_status(|st| {
                            st.device = Some(name);
                            st.driver = Some(format!("{driver:?}"));
                            st.asp = asp;
                        });
                        open = Some(o);
                    }
                    Err(e) => {
                        tracing::info!(node = %dev.node, "headset: can't open it: {e} (needs read and write access to its hidraw node)");
                    }
                }
            }
        }
        // Its reports.
        let Some(o) = open.as_mut() else {
            if open.is_none() {
                set_status(|st| {
                    st.device = None;
                    st.driver = None;
                    st.asp = false;
                });
            }
            std::thread::sleep(Duration::from_millis(150));
            continue;
        };
        match io::read(&o.fd, 150) {
            Ok(Some(report)) => {
                let elements = decode_input(&o.dev.desc, &report, &mut o.last);
                for e in elements {
                    tracing::info!(
                        page = format!("{:#06x}", e.page),
                        usage = format!("{:#04x}", e.usage),
                        value = e.value,
                        relative = e.relative,
                        "headset: input"
                    );
                    let call_control = matches!(e.page, PAGE_TELEPHONY | PAGE_LEDS)
                        || (e.page == PAGE_BUTTON && e.usage == BUTTON_REJECT);
                    if call_control {
                        if !sync {
                            tracing::info!("headset: ignored (Sync device buttons is off)");
                            continue;
                        }
                        let (actions, leds) = o.buttons.on_input(e, &app, Instant::now());
                        o.write_leds(&leds);
                        for a in actions {
                            tracing::info!(?a, "headset: action");
                            on_action(a);
                        }
                    } else if e.page == PAGE_TEAMS && e.usage == TEAMS_BUTTON && e.value == 1 {
                        // Teams' onTeamsButtonClicked: the device's context.
                        if !o.asp {
                            o.init_asp();
                        }
                        let ctx = if o.asp {
                            o.asp(&AspMessage::new(msg::CONTEXT, vec![]))
                        } else {
                            None
                        };
                        match ctx {
                            Some(c) => {
                                let event = AspEvent::from_u8(c.payload[0]);
                                let press = c
                                    .metadata
                                    .as_ref()
                                    .and_then(|m| m.first().copied())
                                    .unwrap_or(0);
                                tracing::info!(?event, press, "headset: Teams button");
                                if press == SHORT_PRESS || press == LONG_PRESS {
                                    on_action(Action::TeamsButton {
                                        event,
                                        long: press == LONG_PRESS,
                                    });
                                }
                            }
                            None => tracing::info!(
                                "headset: Teams button with no context from the device; nothing to do"
                            ),
                        }
                    }
                }
            }
            Ok(None) => {}
            Err(()) => {
                tracing::info!(device = %o.dev.name, "headset: disconnected");
                open = None;
                last_scan = None;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The emulated Jabra headset's descriptor (the test rig's).
    pub const HEADSET: &[u8] = &[
        0x05, 0x0B, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x02, 0x15, 0x00, 0x25, 0x01, 0x09, 0x20, 0x75,
        0x01, 0x95, 0x01, 0x81, 0x22, 0x09, 0x2F, 0x81, 0x06, 0x09, 0x21, 0x81, 0x06, 0x05, 0x09,
        0x09, 0x07, 0x81, 0x02, 0x95, 0x04, 0x81, 0x03, 0x05, 0x08, 0x85, 0x03, 0x09, 0x17, 0x09,
        0x18, 0x09, 0x09, 0x09, 0x20, 0x95, 0x04, 0x91, 0x22, 0x95, 0x04, 0x91, 0x03, 0xC0, 0x06,
        0x99, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x85, 0x04, 0x09, 0x04, 0x15, 0x00, 0x25, 0x01, 0x75,
        0x01, 0x95, 0x01, 0x81, 0x22, 0x95, 0x07, 0x81, 0x03, 0x85, 0x9A, 0x09, 0x03, 0x15, 0x00,
        0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x3F, 0xB1, 0x02, 0xC0,
    ];

    #[test]
    fn parses_a_telephony_headset() {
        let d = Descriptor::parse(HEADSET);
        assert!(d.uses_ids && d.is_telephony() && d.has_asp());
        let hook = d.field(Kind::Input, PAGE_TELEPHONY, HOOK_SWITCH).unwrap();
        assert_eq!((hook.report_id, hook.bit, hook.relative), (2, 0, false));
        let mute = d.field(Kind::Input, PAGE_TELEPHONY, PHONE_MUTE).unwrap();
        assert_eq!((mute.bit, mute.relative), (1, true));
        assert_eq!(
            d.field(Kind::Input, PAGE_BUTTON, BUTTON_REJECT)
                .unwrap()
                .bit,
            3
        );
        assert_eq!(d.field(Kind::Output, PAGE_LEDS, LED_RING).unwrap().bit, 1);
        assert_eq!(d.report_len(Kind::Input, 2), 1);
        assert_eq!(d.report_len(Kind::Feature, ASP_REPORT_ID), 63);
        assert_eq!(
            d.field(Kind::Input, PAGE_TEAMS, TEAMS_BUTTON)
                .unwrap()
                .report_id,
            4
        );
    }

    #[test]
    fn decodes_changes_and_toggles() {
        let d = Descriptor::parse(HEADSET);
        let mut last = HashMap::new();
        // Off hook.
        let e = decode_input(&d, &[2, 0b0001], &mut last);
        assert_eq!(
            e,
            vec![Element {
                page: PAGE_TELEPHONY,
                usage: HOOK_SWITCH,
                value: 1,
                relative: false
            }]
        );
        // Mute pressed while off hook: only the toggle reports.
        let e = decode_input(&d, &[2, 0b0011], &mut last);
        assert_eq!(
            e,
            vec![Element {
                page: PAGE_TELEPHONY,
                usage: PHONE_MUTE,
                value: 1,
                relative: true
            }]
        );
        let e = decode_input(&d, &[2, 0b0001], &mut last);
        assert!(e.is_empty());
        // On hook.
        let e = decode_input(&d, &[2, 0], &mut last);
        assert_eq!(e[0].value, 0);
    }

    #[test]
    fn encodes_leds_keeping_the_others() {
        let d = Descriptor::parse(HEADSET);
        let mut cur = HashMap::new();
        cur.insert(LED_OFF_HOOK, true);
        let r = encode_leds(&d, &[(LED_MUTE, true)], &cur);
        assert_eq!(r, vec![vec![3, 0b0101]]);
    }

    #[test]
    fn hook_switch_answers_and_hangs_up_as_teams() {
        let now = Instant::now();
        let mut b = Buttons::new(Driver::HookProtect);
        let ringing = AppState {
            hooked: true,
            ringing: true,
            ..AppState::default()
        };
        let hook = |v| Element {
            page: PAGE_TELEPHONY,
            usage: HOOK_SWITCH,
            value: v,
            relative: false,
        };
        assert_eq!(b.on_input(hook(1), &ringing, now).0, vec![Action::Answer]);
        // On hook while ringing: ignored (Teams' hook-protect drivers).
        assert!(
            b.on_input(hook(0), &ringing, now + Duration::from_secs(2))
                .0
                .is_empty()
        );
        let in_call = AppState {
            hooked: false,
            ..AppState::default()
        };
        // Within the hook protection: ignored; after it, hangs up.
        b.hook_protect(now);
        assert!(
            b.on_input(hook(0), &in_call, now + Duration::from_millis(500))
                .0
                .is_empty()
        );
        assert_eq!(
            b.on_input(hook(0), &in_call, now + Duration::from_secs(2))
                .0,
            vec![Action::HangUp]
        );
        // Off hook in a call: nothing.
        assert!(
            b.on_input(hook(1), &in_call, now + Duration::from_secs(3))
                .0
                .is_empty()
        );
        // Reject button while ringing.
        let rej = Element {
            page: PAGE_BUTTON,
            usage: BUTTON_REJECT,
            value: 1,
            relative: false,
        };
        assert_eq!(
            b.on_input(rej, &ringing, now + Duration::from_secs(5)).0,
            vec![Action::Reject]
        );
    }

    #[test]
    fn mute_toggles_in_calls_and_prejoin_only() {
        let now = Instant::now();
        let mut b = Buttons::new(Driver::MuteOnly);
        let mute = Element {
            page: PAGE_TELEPHONY,
            usage: PHONE_MUTE,
            value: 1,
            relative: true,
        };
        let idle = AppState {
            hooked: true,
            ..AppState::default()
        };
        assert!(b.on_input(mute, &idle, now).0.is_empty());
        let in_call = AppState {
            hooked: false,
            muted: false,
            ..AppState::default()
        };
        let (a, leds) = b.on_input(mute, &in_call, now);
        assert_eq!(
            (a, leds),
            (vec![Action::SetMuted(true)], vec![(LED_MUTE, true)])
        );
        let prejoin = AppState {
            hooked: true,
            in_prejoin: true,
            prejoin_muted: true,
            ..AppState::default()
        };
        assert_eq!(
            b.on_input(mute, &prejoin, now).0,
            vec![Action::SetMuted(false)]
        );
        // The mute-only driver ignores the hook switch.
        let ringing = AppState {
            hooked: true,
            ringing: true,
            ..AppState::default()
        };
        let hook = Element {
            page: PAGE_TELEPHONY,
            usage: HOOK_SWITCH,
            value: 1,
            relative: false,
        };
        assert!(b.on_input(hook, &ringing, now).0.is_empty());
    }

    #[test]
    fn leds_follow_the_call() {
        let now = Instant::now();
        let mut b = Buttons::new(Driver::HookProtect);
        let ch = b.leds_for(
            &AppState {
                hooked: true,
                ringing: true,
                ..AppState::default()
            },
            now,
        );
        assert!(ch.contains(&(LED_RING, true)) && ch.contains(&(LED_OFF_HOOK, false)));
        for (u, v) in ch {
            b.leds.insert(u, v);
        }
        let ch = b.leds_for(
            &AppState {
                hooked: false,
                muted: true,
                ..AppState::default()
            },
            now,
        );
        assert!(
            ch.contains(&(LED_OFF_HOOK, true))
                && ch.contains(&(LED_RING, false))
                && ch.contains(&(LED_MUTE, true))
        );
    }

    #[test]
    fn asp_messages_round_trip() {
        let m = AspMessage {
            id: msg::CONTEXT,
            payload: vec![1],
            metadata: Some(vec![SHORT_PRESS]),
        };
        let s = m.serialize();
        assert_eq!(s, vec![0x9A, 0x41, 0, 1, 1, 0, 1, 1]);
        assert_eq!(AspMessage::parse(&s).unwrap(), m);
        assert_eq!(
            AspMessage::new(msg::VERSION, vec![]).serialize(),
            vec![0x9A, 0x00, 0, 0]
        );
    }

    #[test]
    fn drivers_as_teams_picks_them() {
        // Jabra with or without a UCQ string.
        assert_eq!(driver_for(0x0B0E, 0x2400, None), Driver::HookProtect);
        assert_eq!(
            driver_for(0x0B0E, 0x2400, Some("UCQ00010000000100000")),
            Driver::HookProtect
        );
        // An unknown vendor: mute only, unless it has a UCQ string
        // (Teams' prod consolidateDrivers: any UCQ string).
        assert_eq!(driver_for(0x16C0, 0x0AB1, None), Driver::MuteOnly);
        assert_eq!(driver_for(0x16C0, 0x0AB1, Some("")), Driver::MuteOnly);
        assert_eq!(
            driver_for(0x16C0, 0x0AB1, Some("UCQ00010000000100000")),
            Driver::HookProtect
        );
        assert_eq!(ucq_kind("UCQ00010000000100000"), "headset");
        assert_eq!(ucq_kind("UCQ01000000000100000"), "speakerphone");
        // Logitech: its named headsets, others only with a UCQ string.
        assert_eq!(driver_for(0x046D, 2630, None), Driver::HookProtect);
        assert_eq!(driver_for(0x046D, 0x0ABC, None), Driver::MuteOnly);
        assert_eq!(
            driver_for(0x046D, 0x0ABC, Some("UCQ00010000000100000")),
            Driver::HookProtect
        );
        // Teams' blacklist.
        assert_eq!(
            driver_for(0x0B0E, 0x24ED, Some("UCQ00010000000100000")),
            Driver::Unsupported
        );
    }
}
