//! Bring-your-own-device (BYOD) meeting rooms, as Teams finds them: a USB
//! device that is both a speaker and a microphone (Teams' composite audio
//! device, a room speakerphone or bar) is a "connected room device"; one
//! whose USB id is on Teams' `byodRoomDeviceVidPids` list is a meeting room
//! Teams picks for Room audio in the pre-join screen ("meeting room mode"),
//! or only suggests when Settings ▸ Devices ▸ "Automatically activate
//! meeting room mode when in a meeting" is off.
//!
//! Teams reads its devices from SlimCore and names them from its native
//! device discovery (the USB product name). OST reads them from PipeWire:
//! each USB audio device's speaker and microphone nodes, with the device's
//! USB vendor and product ids.

use serde::Serialize;

/// One USB audio device with both a speaker and a microphone.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RoomDevice {
    /// Teams' `label`: the device's model (its USB product name).
    pub label: String,
    /// The speaker's and microphone's names in OST's device lists.
    pub speaker: String,
    pub microphone: String,
    /// The device's camera (`/dev/videoN`) when it has one.
    pub camera: Option<String>,
    pub vendor_id: u16,
    pub product_id: u16,
}

/// Teams' room devices for the pre-join screen (its `bringYourOwnDeviceRooms`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct RoomDevices {
    /// Every connected room device ("Connected room devices").
    pub devices: Vec<RoomDevice>,
    /// The meeting room Teams picks for Room audio.
    pub select: Option<RoomDevice>,
    /// Room audio is only suggested: "(suggested)", "We've detected a room
    /// device."
    pub suggest: bool,
}

/// Teams' bundled `byodRoomDeviceVidPids`: USB vendor id → product ids of
/// certified room devices (Teams client, 2026-11).
const BUNDLED_VID_PIDS: &[(u16, &[u16])] = &[
    (0x2574, &[0x09c1, 0x0991, 0x0ab0, 0x0a00]),
    (0x0a57, &[0xa213]),
    (
        0x0b0e,
        &[
            0x3012, 0x3011, 0x3009, 0x306f, 0x3071, 0x3081, 0x3082, 0x3083, 0x3084, 0x3085,
            0x3086, 0x3087, 0x3088, 0x3089, 0x308a, 0x308b, 0x308c, 0x308d, 0x308e, 0x308f,
            0x3093, 0x3094, 0x3095, 0x3096, 0x3097, 0x3098, 0x3099,
        ],
    ),
    (0x046d, &[0x0885, 0x0898, 0x08d2, 0x0867, 0x087c, 0x0963, 0x0967]),
    (0x2e43, &[0x0230]),
    (0x095d, &[0x9101, 0x9217, 0x095d, 0x92c8, 0x92c6]),
    (0x0499, &[0x4043]),
    (0x6993, &[0xb035, 0xb04e, 0xb050, 0xb05d]),
    (0x045e, &[0x0106]),
    (0x6993, &[0xb00b, 0xb00a, 0xb096]),
    (0x14be, &[0x0051, 0x0064, 0x0065, 0x0066]),
    (0x0600, &[0x0114]),
];

/// The room-device list: ECS's `byod.byodRoomDeviceVidPids` when it sets
/// one (`[{vendorId:"0b0e", productIds:["3012", …]}]`, hex), else Teams'
/// bundled list.
pub fn vid_pids() -> Vec<(u16, Vec<u16>)> {
    crate::api::ecs::setting("byod", "byodRoomDeviceVidPids")
        .and_then(|v| parse_vid_pids(&v))
        .unwrap_or_else(|| {
            BUNDLED_VID_PIDS
                .iter()
                .map(|(v, p)| (*v, p.to_vec()))
                .collect()
        })
}

fn parse_vid_pids(v: &serde_json::Value) -> Option<Vec<(u16, Vec<u16>)>> {
    let hex = |s: &serde_json::Value| u16::from_str_radix(s.as_str()?, 16).ok();
    v.as_array()?
        .iter()
        .map(|o| {
            Some((
                hex(o.get("vendorId")?)?,
                o.get("productIds")?.as_array()?.iter().filter_map(hex).collect(),
            ))
        })
        .collect()
}

/// A Teams ECS flag in the `byod` category; Teams' desktop default when
/// ECS doesn't set it.
fn flag(key: &str, default: bool) -> bool {
    crate::api::ecs::setting("byod", key)
        .and_then(|v| v.as_bool())
        .unwrap_or(default)
}

/// Teams' room response (`createLocalRoomResponse`, then
/// `validatePushToRoomSettingAndUpdate`): every device is listed; the
/// first one on the list is picked, or only suggested when meeting room
/// mode is off; with no pick, a listed device is suggested.
pub fn room_response(
    devices: Vec<RoomDevice>,
    list: &[(u16, Vec<u16>)],
    meeting_room_mode: bool,
    flags: Flags,
) -> RoomDevices {
    let known = |d: &&RoomDevice| {
        list.iter()
            .any(|(v, p)| *v == d.vendor_id && p.contains(&d.product_id))
    };
    let select = flags
        .move_for_vid_pids
        .then(|| devices.iter().find(known).cloned())
        .flatten();
    let suggest = select.is_none() && flags.suggest_for_vid_pids && devices.iter().any(|d| known(&d));
    let (select, suggest) = if meeting_room_mode {
        (select, suggest)
    } else if select.is_some() {
        (None, true)
    } else {
        (None, false)
    };
    RoomDevices {
        devices,
        // The pre-join screen honours a pick or a suggestion only with
        // Teams' move-to / suggest room audio on.
        select: select.filter(|_| flags.move_to_room_audio),
        suggest: suggest && flags.suggest_room_audio,
    }
}

/// Teams' BYOD switches (ECS `byod`).
#[derive(Debug, Clone, Copy)]
pub struct Flags {
    pub move_for_vid_pids: bool,
    pub suggest_for_vid_pids: bool,
    pub move_to_room_audio: bool,
    pub suggest_room_audio: bool,
}

impl Flags {
    pub fn from_ecs() -> Option<Flags> {
        flag("enableBYOD", true).then(|| Flags {
            move_for_vid_pids: flag("enableBYODMoveToRoomAudioForVidPids", true),
            suggest_for_vid_pids: flag("enableBYODSuggestRoomAudioForVidPids", true),
            move_to_room_audio: flag("enableBYODMoveToRoomAudio", true),
            suggest_room_audio: flag("enableBYODSuggestRoomAudio", true),
        })
    }
}

/// The connected room devices and Teams' pick (an empty answer when Teams'
/// BYOD is off or no audio system is available).
pub fn find(meeting_room_mode: bool) -> RoomDevices {
    let Some(flags) = Flags::from_ecs() else {
        return RoomDevices::default();
    };
    room_response(connected(), &vid_pids(), meeting_room_mode, flags)
}

/// A PipeWire audio endpoint with its device's properties.
#[derive(Debug, Clone, Default)]
pub struct Endpoint {
    /// node.description: the name OST's device lists show.
    pub name: String,
    pub sink: bool,
    /// The device it belongs to (its PipeWire device, else its USB ids
    /// and product name).
    pub device_key: String,
    pub bus: String,
    pub vendor_id: Option<u16>,
    pub product_id: Option<u16>,
    pub product_name: String,
    pub form_factor: String,
}

/// Teams' composite audio devices from the endpoints: USB devices with a
/// speaker and a microphone, except headsets, headphones and handsets
/// (Teams' device discovery drops those).
pub fn composites(endpoints: &[Endpoint]) -> Vec<RoomDevice> {
    let mut keys: Vec<&str> = Vec::new();
    for e in endpoints {
        if !keys.contains(&e.device_key.as_str()) {
            keys.push(&e.device_key);
        }
    }
    keys.into_iter()
        .filter_map(|key| {
            let mine: Vec<&Endpoint> = endpoints.iter().filter(|e| e.device_key == key).collect();
            let first = mine[0];
            let speaker = mine.iter().find(|e| e.sink)?;
            let microphone = mine.iter().find(|e| !e.sink)?;
            if first.bus != "usb"
                || matches!(first.form_factor.as_str(), "headset" | "headphone" | "handset")
            {
                return None;
            }
            Some(RoomDevice {
                label: if first.product_name.is_empty() { speaker.name.clone() } else { first.product_name.clone() },
                speaker: speaker.name.clone(),
                microphone: microphone.name.clone(),
                camera: None,
                vendor_id: first.vendor_id?,
                product_id: first.product_id?,
            })
        })
        .collect()
}

/// A USB id property: "0x0b0e" (PipeWire) or "0b0e".
pub fn usb_id(s: &str) -> Option<u16> {
    u16::from_str_radix(s.trim().trim_start_matches("0x"), 16).ok()
}

/// The connected room devices, with their cameras (a V4L2 camera on the
/// same USB device).
pub fn connected() -> Vec<RoomDevice> {
    #[allow(unused_mut)]
    let mut devices = composites(&endpoints());
    #[cfg(all(target_os = "linux", feature = "video"))]
    for d in &mut devices {
        d.camera = camera_of(d.vendor_id, d.product_id);
    }
    devices
}

/// The camera node whose USB device has these ids.
#[cfg(all(target_os = "linux", feature = "video"))]
fn camera_of(vendor: u16, product: u16) -> Option<String> {
    let read = |p: std::path::PathBuf| std::fs::read_to_string(p).ok().and_then(|s| usb_id(&s));
    for entry in std::fs::read_dir("/sys/class/video4linux").ok()?.flatten() {
        // …/videoN/device is the USB interface; its parent has the ids.
        let usb = entry.path().join("device").join("..");
        if read(usb.join("idVendor")) == Some(vendor) && read(usb.join("idProduct")) == Some(product) {
            let path = format!("/dev/{}", entry.file_name().to_string_lossy());
            if crate::calling::camera::list_devices().iter().any(|(p, _)| *p == path) {
                return Some(path);
            }
        }
    }
    None
}

#[cfg(all(feature = "audio", target_os = "linux"))]
fn endpoints() -> Vec<Endpoint> {
    pipewire_endpoints().unwrap_or_default()
}

#[cfg(not(all(feature = "audio", target_os = "linux")))]
fn endpoints() -> Vec<Endpoint> {
    Vec::new()
}

/// PipeWire's audio sinks and sources with their devices' USB properties.
/// A registry global carries only a few properties, so each node and
/// device is bound for its full ones.
#[cfg(all(feature = "audio", target_os = "linux"))]
fn pipewire_endpoints() -> Option<Vec<Endpoint>> {
    use std::cell::RefCell;
    use std::collections::HashMap;
    use std::rc::Rc;

    use pipewire as pw;
    use pw::types::ObjectType;

    type Props = HashMap<String, String>;
    fn own(dict: Option<&pw::spa::utils::dict::DictRef>) -> Props {
        dict.map(|d| d.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect())
            .unwrap_or_default()
    }
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None).ok()?;
    let context = pw::context::ContextRc::new(&mainloop, None).ok()?;
    let core = context.connect_rc(None).ok()?;
    let registry = core.get_registry_rc().ok()?;

    let devices: Rc<RefCell<HashMap<u32, Props>>> = Rc::default();
    let nodes: Rc<RefCell<Vec<Props>>> = Rc::default();
    // Bound proxies and their listeners live until the loop ends.
    let keep: Rc<RefCell<Vec<Box<dyn std::any::Any>>>> = Rc::default();
    let pending: Rc<RefCell<Vec<pw::spa::utils::result::AsyncSeq>>> = Rc::default();
    pending.borrow_mut().push(core.sync(0).ok()?);

    let _core_listener = core
        .add_listener_local()
        .done({
            let pending = pending.clone();
            let mainloop = mainloop.clone();
            move |id, seq| {
                if id != pw::core::PW_ID_CORE {
                    return;
                }
                let mut p = pending.borrow_mut();
                if let Some(i) = p.iter().position(|s| *s == seq) {
                    p.remove(i);
                }
                if p.is_empty() {
                    mainloop.quit();
                }
            }
        })
        .register();
    let _registry_listener = registry
        .add_listener_local()
        .global({
            let devices = devices.clone();
            let nodes = nodes.clone();
            let keep = keep.clone();
            let pending = pending.clone();
            let registry = registry.clone();
            let core = core.clone();
            move |global| {
                match global.type_ {
                    ObjectType::Device => {
                        let Ok(device) = registry.bind::<pw::device::Device, _>(global) else { return };
                        let id = global.id;
                        let devices = devices.clone();
                        let listener = device
                            .add_listener_local()
                            .info(move |info| {
                                devices.borrow_mut().insert(id, own(info.props()));
                            })
                            .register();
                        keep.borrow_mut().push(Box::new((device, listener)));
                    }
                    ObjectType::Node => {
                        let class = global.props.and_then(|p| p.get("media.class")).unwrap_or("");
                        if class != "Audio/Sink" && class != "Audio/Source" {
                            return;
                        }
                        let Ok(node) = registry.bind::<pw::node::Node, _>(global) else { return };
                        let nodes = nodes.clone();
                        let listener = node
                            .add_listener_local()
                            .info(move |info| {
                                if let Some(props) = info.props() {
                                    nodes.borrow_mut().push(own(Some(props)));
                                }
                            })
                            .register();
                        keep.borrow_mut().push(Box::new((node, listener)));
                    }
                    _ => return,
                }
                // Another round trip delivers the bound object's info.
                if let Ok(seq) = core.sync(0) {
                    pending.borrow_mut().push(seq);
                }
            }
        })
        .register();
    mainloop.run();

    let devices = devices.borrow();
    let get = |own: &Props, dev: Option<&Props>, key: &str| -> String {
        own.get(key)
            .or_else(|| dev.and_then(|d| d.get(key)))
            .cloned()
            .unwrap_or_default()
    };
    let mut seen = Vec::new();
    Some(
        nodes
            .borrow()
            .iter()
            .filter_map(|n| {
                // A node's info can arrive more than once.
                let node_name = n.get("node.name")?.clone();
                if seen.contains(&node_name) {
                    return None;
                }
                seen.push(node_name);
                let name = n.get("node.description")?.clone();
                let device_id = n.get("device.id").and_then(|s| s.parse::<u32>().ok());
                let dev = device_id.and_then(|id| devices.get(&id));
                let vendor = get(n, dev, "device.vendor.id");
                let product = get(n, dev, "device.product.id");
                let product_name = get(n, dev, "device.product.name");
                Some(Endpoint {
                    sink: n.get("media.class").is_some_and(|c| c == "Audio/Sink"),
                    device_key: match device_id {
                        Some(id) => format!("pw:{id}"),
                        None => format!("usb:{vendor}:{product}:{product_name}"),
                    },
                    bus: get(n, dev, "device.bus"),
                    vendor_id: usb_id(&vendor),
                    product_id: usb_id(&product),
                    form_factor: get(n, dev, "device.form-factor"),
                    product_name,
                    name,
                })
            })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ep(name: &str, sink: bool, key: &str, ids: (u16, u16)) -> Endpoint {
        Endpoint {
            name: name.into(),
            sink,
            device_key: key.into(),
            bus: "usb".into(),
            vendor_id: Some(ids.0),
            product_id: Some(ids.1),
            product_name: format!("{key} model"),
            form_factor: String::new(),
        }
    }

    const ALL: Flags = Flags {
        move_for_vid_pids: true,
        suggest_for_vid_pids: true,
        move_to_room_audio: true,
        suggest_room_audio: true,
    };

    #[test]
    fn composites_need_a_usb_speaker_and_microphone() {
        let mut headset = ep("Headset", true, "h", (0x0b0e, 0x3012));
        headset.form_factor = "headset".into();
        let mut headset_mic = ep("Headset mic", false, "h", (0x0b0e, 0x3012));
        headset_mic.form_factor = "headset".into();
        let mut internal = ep("Speakers", true, "pci", (1, 1));
        internal.bus = "pci".into();
        let mut internal_mic = ep("Mic", false, "pci", (1, 1));
        internal_mic.bus = "pci".into();
        let list = [
            ep("Jabra Speaker", true, "j", (0x0b0e, 0x3012)),
            ep("Jabra Mic", false, "j", (0x0b0e, 0x3012)),
            ep("Webcam mic", false, "w", (0x046d, 0x0825)),
            headset,
            headset_mic,
            internal,
            internal_mic,
        ];
        let c = composites(&list);
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].label, "j model");
        assert_eq!((c[0].speaker.as_str(), c[0].microphone.as_str()), ("Jabra Speaker", "Jabra Mic"));
    }

    fn dev(label: &str, ids: (u16, u16)) -> RoomDevice {
        RoomDevice {
            label: label.into(),
            speaker: format!("{label} speaker"),
            microphone: format!("{label} mic"),
            camera: None,
            vendor_id: ids.0,
            product_id: ids.1,
        }
    }

    #[test]
    fn known_devices_are_picked_or_suggested_as_teams() {
        let list = vid_pids_bundled();
        let other = dev("Other speakerphone", (0x1234, 0x0001));
        let jabra = dev("Jabra Speak 750", (0x0b0e, 0x3012));
        let r = room_response(vec![other.clone(), jabra.clone()], &list, true, ALL);
        assert_eq!(r.devices.len(), 2);
        assert_eq!(r.select.as_ref(), Some(&jabra));
        assert!(!r.suggest);
        // Meeting room mode off: only suggested.
        let r = room_response(vec![jabra.clone()], &list, false, ALL);
        assert_eq!((r.select, r.suggest), (None, true));
        // An unknown device is listed, never picked or suggested.
        let r = room_response(vec![other.clone()], &list, true, ALL);
        assert_eq!((r.select, r.suggest, r.devices.len()), (None, false, 1));
        // Without auto-pick for known ids, Teams suggests instead.
        let flags = Flags { move_for_vid_pids: false, ..ALL };
        let r = room_response(vec![jabra.clone()], &list, true, flags);
        assert_eq!((r.select, r.suggest), (None, true));
        // …and with meeting room mode off a suggestion is dropped.
        let r = room_response(vec![jabra], &list, false, flags);
        assert_eq!((r.select, r.suggest), (None, false));
    }

    fn vid_pids_bundled() -> Vec<(u16, Vec<u16>)> {
        BUNDLED_VID_PIDS.iter().map(|(v, p)| (*v, p.to_vec())).collect()
    }

    #[test]
    fn ecs_lists_are_hex() {
        let v = serde_json::json!([{ "vendorId": "0b0e", "productIds": ["3012", "306F"] }]);
        assert_eq!(parse_vid_pids(&v), Some(vec![(0x0b0e, vec![0x3012, 0x306f])]));
        assert_eq!(usb_id("0x0b0e"), Some(0x0b0e));
        assert_eq!(usb_id("3012\n"), Some(0x3012));
    }
}
