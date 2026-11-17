//! A camera's own controls (V4L2), for Teams' Settings ▸ Devices ▸ Video
//! settings ▸ "Automatically adjust camera controls" and "Open camera
//! settings".
//!
//! Teams desktop (settings-app, `auto-camera-controls`): the switch calls
//! the preview renderer's `cameraAutoControl(enable)`, which puts the
//! camera's own automatic controls (exposure, white balance, focus, …) on
//! or off; Teams keeps the choice on the device
//! (`automaticCameraSettingsSelected`) and, until one is made, shows what
//! the camera is set to. With the switch off it offers "Open camera
//! settings" (the camera's settings: its controls set by hand) and "Some
//! settings might not be available for all camera types.".
//!
//! On Linux those are the camera's V4L2 controls: the automatic ones
//! ([`AUTO_CONTROLS`]) and the standard user and camera-class controls the
//! camera offers ([`controls`]).

use anyhow::{Context, Result};
use serde::Serialize;
use v4l::control::{Description, Flags, MenuItem, Type};
use v4l::Device;

pub const BRIGHTNESS: u32 = 0x0098_0900;
pub const CONTRAST: u32 = 0x0098_0901;
pub const SATURATION: u32 = 0x0098_0902;
pub const HUE: u32 = 0x0098_0903;
pub const AUTO_WHITE_BALANCE: u32 = 0x0098_090c;
pub const GAMMA: u32 = 0x0098_0910;
pub const AUTOGAIN: u32 = 0x0098_0912;
pub const GAIN: u32 = 0x0098_0913;
pub const POWER_LINE_FREQUENCY: u32 = 0x0098_0918;
pub const HUE_AUTO: u32 = 0x0098_0919;
pub const WHITE_BALANCE_TEMPERATURE: u32 = 0x0098_091a;
pub const SHARPNESS: u32 = 0x0098_091b;
pub const BACKLIGHT_COMPENSATION: u32 = 0x0098_091c;
pub const EXPOSURE_AUTO: u32 = 0x009a_0901;
pub const EXPOSURE_ABSOLUTE: u32 = 0x009a_0902;
pub const EXPOSURE_AUTO_PRIORITY: u32 = 0x009a_0903;
pub const PAN_ABSOLUTE: u32 = 0x009a_0908;
pub const TILT_ABSOLUTE: u32 = 0x009a_0909;
pub const FOCUS_ABSOLUTE: u32 = 0x009a_090a;
pub const FOCUS_AUTO: u32 = 0x009a_090c;
pub const ZOOM_ABSOLUTE: u32 = 0x009a_090d;
pub const IRIS_ABSOLUTE: u32 = 0x009a_0911;

/// V4L2's exposure modes (`V4L2_CID_EXPOSURE_AUTO`).
const EXPOSURE_MANUAL: i64 = 1;
const EXPOSURE_AUTO_MODE: i64 = 0;
const EXPOSURE_APERTURE_PRIORITY: i64 = 3;

/// The camera's automatic controls, each with the control it sets by hand
/// when off.
pub const AUTO_CONTROLS: [(u32, Option<u32>); 5] = [
    (EXPOSURE_AUTO, Some(EXPOSURE_ABSOLUTE)),
    (AUTO_WHITE_BALANCE, Some(WHITE_BALANCE_TEMPERATURE)),
    (FOCUS_AUTO, Some(FOCUS_ABSOLUTE)),
    (AUTOGAIN, Some(GAIN)),
    (HUE_AUTO, Some(HUE)),
];

/// The controls the camera settings show, in their order (the Windows
/// camera property pages': picture, then camera).
const ORDER: [(u32, &str); 18] = [
    (BRIGHTNESS, "Brightness"),
    (CONTRAST, "Contrast"),
    (HUE, "Hue"),
    (SATURATION, "Saturation"),
    (SHARPNESS, "Sharpness"),
    (GAMMA, "Gamma"),
    (WHITE_BALANCE_TEMPERATURE, "White balance"),
    (BACKLIGHT_COMPENSATION, "Backlight compensation"),
    (GAIN, "Gain"),
    (POWER_LINE_FREQUENCY, "Power line frequency"),
    (ZOOM_ABSOLUTE, "Zoom"),
    (FOCUS_ABSOLUTE, "Focus"),
    (EXPOSURE_ABSOLUTE, "Exposure"),
    (IRIS_ABSOLUTE, "Iris"),
    (PAN_ABSOLUTE, "Pan"),
    (TILT_ABSOLUTE, "Tilt"),
    (EXPOSURE_AUTO_PRIORITY, "Low light compensation"),
    (AUTO_WHITE_BALANCE, "Automatic white balance"),
];

/// One control as the camera settings show it.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CameraControl {
    pub id: u32,
    pub name: String,
    /// "int", "bool" or "menu".
    pub kind: &'static str,
    pub min: i64,
    pub max: i64,
    pub step: i64,
    pub default: i64,
    pub value: i64,
    /// A menu's choices: (value, label).
    pub items: Vec<(i64, String)>,
    /// Set by the camera itself now (its automatic control is on).
    pub inactive: bool,
    /// Its automatic control, if the camera has one (shown as "Auto").
    pub auto_id: Option<u32>,
    pub auto: bool,
}

/// The camera, its controls asked for one by one (VIDIOC_QUERYCTRL on the
/// ids above): the v4l crate's enumeration panics on the compound and
/// rectangle controls cameras also carry (UVC's region of interest).
struct Cam {
    dev: Device,
}

/// `struct v4l2_queryctrl`.
#[repr(C)]
#[derive(Default)]
struct QueryCtrl {
    id: u32,
    typ: u32,
    name: [u8; 32],
    minimum: i32,
    maximum: i32,
    step: i32,
    default_value: i32,
    flags: u32,
    reserved: [u32; 2],
}

/// `struct v4l2_querymenu` (packed; the name and the integer value share
/// its first 32 bytes).
#[repr(C, packed)]
struct QueryMenu {
    id: u32,
    index: u32,
    name: [u8; 32],
    reserved: u32,
}

/// `struct v4l2_control`.
#[repr(C)]
struct Ctrl {
    id: u32,
    value: i32,
}

fn ioctl<T>(d: &Device, request: v4l::v4l2::vidioc::_IOC_TYPE, arg: &mut T) -> std::io::Result<()> {
    // SAFETY: `arg` is the request's own structure (same layout as the
    // kernel's), live for the call.
    unsafe { v4l::v4l2::ioctl(d.handle().fd(), request, arg as *mut T as *mut std::os::raw::c_void) }
}

impl Cam {
    fn query(&self, id: u32) -> Option<Description> {
        let mut q = QueryCtrl { id, ..Default::default() };
        ioctl(&self.dev, v4l::v4l2::vidioc::VIDIOC_QUERYCTRL, &mut q).ok()?;
        if q.id != id {
            return None;
        }
        let typ = match q.typ {
            1 => Type::Integer,
            2 => Type::Boolean,
            3 => Type::Menu,
            9 => Type::IntegerMenu,
            _ => return None,
        };
        let name = String::from_utf8_lossy(&q.name).trim_end_matches('\0').to_string();
        let items = matches!(typ, Type::Menu | Type::IntegerMenu).then(|| {
            (q.minimum..=q.maximum)
                .filter_map(|i| {
                    let mut m = QueryMenu { id, index: i as u32, name: [0; 32], reserved: 0 };
                    ioctl(&self.dev, v4l::v4l2::vidioc::VIDIOC_QUERYMENU, &mut m).ok()?;
                    let raw = m.name;
                    let item = if typ == Type::IntegerMenu {
                        let mut v = [0u8; 8];
                        v.copy_from_slice(&raw[..8]);
                        MenuItem::Value(i64::from_ne_bytes(v))
                    } else {
                        MenuItem::Name(String::from_utf8_lossy(&raw).trim_end_matches('\0').to_string())
                    };
                    Some((i as u32, item))
                })
                .collect()
        });
        Some(Description {
            id,
            typ,
            name,
            minimum: i64::from(q.minimum),
            maximum: i64::from(q.maximum),
            step: u64::try_from(q.step.max(1)).unwrap_or(1),
            default: i64::from(q.default_value),
            flags: Flags::from_bits_truncate(q.flags),
            items,
        })
    }

    /// The standard controls (picture and camera) this camera has.
    fn query_controls(&self) -> Result<Vec<Description>> {
        let mut ids: Vec<u32> = ORDER.iter().map(|(id, _)| *id).collect();
        ids.extend(AUTO_CONTROLS.iter().map(|(a, _)| *a));
        ids.sort_unstable();
        ids.dedup();
        Ok(ids.into_iter().filter_map(|id| self.query(id)).collect())
    }

    fn get(&self, id: u32) -> Option<i64> {
        let mut c = Ctrl { id, value: 0 };
        ioctl(&self.dev, v4l::v4l2::vidioc::VIDIOC_G_CTRL, &mut c).ok()?;
        Some(i64::from(c.value))
    }

    fn put(&self, id: u32, value: i64) -> std::io::Result<()> {
        let mut c = Ctrl { id, value: i32::try_from(value).unwrap_or(0) };
        ioctl(&self.dev, v4l::v4l2::vidioc::VIDIOC_S_CTRL, &mut c)
    }
}

fn open(path: &str) -> Result<Cam> {
    Ok(Cam { dev: Device::with_path(path).with_context(|| format!("Can't open {path}"))? })
}

fn value_of(d: &Cam, id: u32) -> Option<i64> {
    d.get(id)
}

fn kind_of(t: Type) -> Option<&'static str> {
    match t {
        Type::Integer => Some("int"),
        Type::Boolean => Some("bool"),
        Type::Menu | Type::IntegerMenu => Some("menu"),
        _ => None,
    }
}

fn set_value(d: &Cam, desc: &Description, v: i64) -> Result<()> {
    let v = if desc.typ == Type::Boolean { i64::from(v != 0) } else { v };
    d.put(desc.id, v).with_context(|| format!("Setting {} to {v}", desc.name))
}

/// The automatic mode an automatic control takes when on.
fn auto_value(desc: &Description) -> i64 {
    if desc.id != EXPOSURE_AUTO {
        return 1;
    }
    // UVC cameras offer manual and aperture priority; others full auto.
    let offered = |v: i64| desc.items.as_ref().is_some_and(|i| i.iter().any(|(k, _)| i64::from(*k) == v));
    if offered(EXPOSURE_APERTURE_PRIORITY) { EXPOSURE_APERTURE_PRIORITY } else { EXPOSURE_AUTO_MODE }
}

fn is_auto(desc: &Description, v: i64) -> bool {
    if desc.id == EXPOSURE_AUTO { v != EXPOSURE_MANUAL } else { v != 0 }
}

fn usable(desc: &Description) -> bool {
    !desc.flags.intersects(Flags::DISABLED | Flags::READ_ONLY | Flags::WRITE_ONLY) && kind_of(desc.typ).is_some()
}

/// Whether the camera's automatic controls are on (all of those it has);
/// None if it has none.
pub fn auto_state(path: &str) -> Result<Option<bool>> {
    let d = open(path)?;
    let descs = d.query_controls()?;
    let states: Vec<bool> = AUTO_CONTROLS
        .iter()
        .filter_map(|(id, _)| descs.iter().find(|x| x.id == *id && usable(x)))
        .filter_map(|desc| value_of(&d, desc.id).map(|v| is_auto(desc, v)))
        .collect();
    Ok((!states.is_empty()).then(|| states.iter().all(|&s| s)))
}

/// Teams' `cameraAutoControl(enable)`: the camera's automatic controls on
/// or off. Off, each set-by-hand control keeps the value the camera had
/// reached. Answers how many automatic controls it set.
pub fn set_auto(path: &str, on: bool) -> Result<usize> {
    let d = open(path)?;
    let descs = d.query_controls()?;
    let mut set = 0;
    for (id, manual) in AUTO_CONTROLS {
        let Some(desc) = descs.iter().find(|x| x.id == id && usable(x)) else { continue };
        // What the camera chose, so turning auto off doesn't jump.
        let reached = manual.and_then(|m| value_of(&d, m).map(|v| (m, v)));
        let v = if on { auto_value(desc) } else if id == EXPOSURE_AUTO { EXPOSURE_MANUAL } else { 0 };
        set_value(&d, desc, v)?;
        set += 1;
        if !on
            && let Some((m, v)) = reached
            && let Some(md) = descs.iter().find(|x| x.id == m)
        {
            let _ = set_value(&d, md, v);
        }
    }
    tracing::info!(path, on, set, "camera automatic controls");
    Ok(set)
}

/// The user's "Automatically adjust camera controls" (None: not chosen,
/// the camera keeps its own setting, as Teams leaves it until you choose).
static PREFERRED: std::sync::Mutex<Option<bool>> = std::sync::Mutex::new(None);

pub fn set_preferred_auto(on: Option<bool>) {
    *PREFERRED.lock().unwrap_or_else(|e| e.into_inner()) = on;
}

/// Put the camera's automatic controls as chosen (Teams' loadAutoCameraSettings
/// as the camera starts).
pub fn apply_preferred(path: &str) {
    let Some(on) = *PREFERRED.lock().unwrap_or_else(|e| e.into_inner()) else { return };
    if let Err(e) = set_auto(path, on) {
        tracing::info!("camera automatic controls: {e:#}");
    }
}

/// The controls the camera offers, as the camera settings show them.
pub fn controls(path: &str) -> Result<Vec<CameraControl>> {
    let d = open(path)?;
    let descs = d.query_controls()?;
    let auto_of = |id: u32| AUTO_CONTROLS.iter().find(|(_, m)| *m == Some(id)).map(|(a, _)| *a);
    let mut out = Vec::new();
    for (id, name) in ORDER {
        let Some(desc) = descs.iter().find(|x| x.id == id && usable(x)) else { continue };
        // Automatic white balance shows with White balance, unless the
        // camera has no temperature to set.
        if id == AUTO_WHITE_BALANCE && descs.iter().any(|x| x.id == WHITE_BALANCE_TEMPERATURE && usable(x)) {
            continue;
        }
        let Some(value) = value_of(&d, id) else { continue };
        let auto_id = auto_of(id).filter(|a| descs.iter().any(|x| x.id == *a && usable(x)));
        let auto = auto_id
            .and_then(|a| descs.iter().find(|x| x.id == a).and_then(|ad| value_of(&d, a).map(|v| is_auto(ad, v))))
            .unwrap_or(false);
        out.push(CameraControl {
            id,
            name: name.to_string(),
            kind: kind_of(desc.typ).unwrap_or("int"),
            min: desc.minimum,
            max: desc.maximum,
            step: i64::try_from(desc.step.max(1)).unwrap_or(1),
            default: desc.default,
            value,
            items: desc
                .items
                .iter()
                .flatten()
                .map(|(k, item)| {
                    let label = match item {
                        MenuItem::Name(n) => n.clone(),
                        MenuItem::Value(v) => v.to_string(),
                    };
                    (i64::from(*k), label)
                })
                .collect(),
            inactive: desc.flags.contains(Flags::INACTIVE) || auto,
            auto_id,
            auto,
        });
    }
    Ok(out)
}

/// Set one control (by hand), or its automatic control (`auto_id`, 1/0).
pub fn set(path: &str, id: u32, value: i64) -> Result<()> {
    let d = open(path)?;
    let descs = d.query_controls()?;
    let desc = descs.iter().find(|x| x.id == id && usable(x)).context("The camera has no such control")?;
    let v = if AUTO_CONTROLS.iter().any(|(a, _)| *a == id) {
        if value != 0 { auto_value(desc) } else if id == EXPOSURE_AUTO { EXPOSURE_MANUAL } else { 0 }
    } else {
        value.clamp(desc.minimum, desc.maximum)
    };
    set_value(&d, desc, v)
}

/// Every control back to the camera's default.
pub fn reset(path: &str) -> Result<()> {
    let d = open(path)?;
    for desc in d.query_controls()? {
        if ORDER.iter().any(|(id, _)| *id == desc.id) || AUTO_CONTROLS.iter().any(|(a, _)| *a == desc.id) {
            if usable(&desc) {
                let _ = set_value(&d, &desc, desc.default);
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn desc(id: u32, items: &[u32]) -> Description {
        Description {
            id,
            typ: if items.is_empty() { Type::Boolean } else { Type::Menu },
            name: String::new(),
            minimum: 0,
            maximum: 3,
            step: 1,
            default: 0,
            flags: Flags::empty(),
            items: (!items.is_empty()).then(|| items.iter().map(|&k| (k, MenuItem::Name(k.to_string()))).collect()),
        }
    }

    /// Exposure's automatic mode is aperture priority on a UVC camera
    /// (manual and aperture priority only), full auto elsewhere; manual is
    /// the only "off".
    #[test]
    fn exposure_modes_follow_what_the_camera_offers() {
        assert_eq!(auto_value(&desc(EXPOSURE_AUTO, &[1, 3])), 3);
        assert_eq!(auto_value(&desc(EXPOSURE_AUTO, &[0, 1])), 0);
        assert_eq!(auto_value(&desc(AUTO_WHITE_BALANCE, &[])), 1);
        let e = desc(EXPOSURE_AUTO, &[1, 3]);
        assert!(is_auto(&e, 3) && is_auto(&e, 0) && !is_auto(&e, 1));
        assert!(!is_auto(&desc(FOCUS_AUTO, &[]), 0));
    }
}
