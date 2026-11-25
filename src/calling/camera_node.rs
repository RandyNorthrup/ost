//! Which V4L2 device nodes are cameras a call can use.
//!
//! A computer has many video nodes that aren't: a UVC webcam's second node
//! carries metadata; Intel IPU6 (and IPU3, Rockchip, i.MX and other
//! media-controller devices) registers dozens of raw capture nodes ("ipu6",
//! driver "isys") that only deliver a picture once a pipeline is set up
//! through the media controller, which libcamera does and then offers the
//! camera through PipeWire; codecs (memory-to-memory) and output devices
//! aren't cameras either. Chromium and Teams' web client list cameras from
//! PipeWire for that reason; these rules decide the V4L2 nodes OST still
//! lists itself (systems without PipeWire, v4l2loopback devices PipeWire
//! doesn't offer).

use super::pixfmt::PixelFormat;

/// V4L2 capability bits (linux/videodev2.h).
pub const CAP_VIDEO_CAPTURE: u32 = 0x0000_0001;
pub const CAP_VIDEO_OUTPUT: u32 = 0x0000_0002;
pub const CAP_VIDEO_CAPTURE_MPLANE: u32 = 0x0000_1000;
pub const CAP_VIDEO_M2M_MPLANE: u32 = 0x0000_4000;
pub const CAP_VIDEO_M2M: u32 = 0x0000_8000;
pub const CAP_META_CAPTURE: u32 = 0x0080_0000;
pub const CAP_STREAMING: u32 = 0x0400_0000;
pub const CAP_IO_MC: u32 = 0x2000_0000;
pub const CAP_DEVICE_CAPS: u32 = 0x8000_0000;

/// What VIDIOC_QUERYCAP and VIDIOC_ENUM_FMT say about a node.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NodeInfo {
    pub driver: String,
    pub card: String,
    pub bus_info: String,
    /// The whole device's capabilities.
    pub capabilities: u32,
    /// This node's (valid when `capabilities` has [`CAP_DEVICE_CAPS`]).
    pub device_caps: u32,
    /// The capture formats it offers (fourccs), when they were asked.
    pub formats: Option<Vec<[u8; 4]>>,
}

/// Why a node isn't listed (for the log), or `Ok` when it's a camera.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    Camera,
    /// No single-planar video capture with streaming I/O (metadata,
    /// output-only, radio, multi-planar raw nodes).
    NotCapture,
    /// Configured through the media controller (IPU6 ISYS and the like):
    /// libcamera turns these into a camera, offered by PipeWire.
    MediaController,
    /// A codec or converter.
    MemoryToMemory,
    /// Offers no picture format OST can show (Bayer, metadata, nothing).
    NoUsableFormat,
}

impl NodeInfo {
    /// This node's own capabilities.
    pub fn caps(&self) -> u32 {
        if self.capabilities & CAP_DEVICE_CAPS != 0 {
            self.device_caps
        } else {
            self.capabilities
        }
    }

    /// A v4l2loopback device: a capture node once something writes to it
    /// (with exclusive_caps=1 only then; with exclusive_caps=0 it offers
    /// capture and output at once).
    pub fn is_loopback(&self) -> bool {
        self.driver == "v4l2 loopback"
    }

    pub fn verdict(&self) -> Verdict {
        let caps = self.caps();
        if caps & (CAP_VIDEO_M2M | CAP_VIDEO_M2M_MPLANE) != 0 {
            return Verdict::MemoryToMemory;
        }
        if caps & CAP_IO_MC != 0 {
            return Verdict::MediaController;
        }
        if caps & CAP_VIDEO_CAPTURE == 0 || caps & CAP_STREAMING == 0 {
            return Verdict::NotCapture;
        }
        // Capture and output on one node is a converter, except a
        // loopback device with exclusive_caps=0.
        if caps & CAP_VIDEO_OUTPUT != 0 && !self.is_loopback() {
            return Verdict::MemoryToMemory;
        }
        match &self.formats {
            // A loopback device nothing writes to yet has no format; it
            // gets one when its producer starts.
            Some(f) if f.is_empty() && self.is_loopback() => Verdict::Camera,
            Some(f) if !f.iter().any(|c| PixelFormat::from_fourcc(c).is_some()) => {
                Verdict::NoUsableFormat
            }
            _ => Verdict::Camera,
        }
    }

    /// The name a camera is listed by: the card name, without the model
    /// repeated after a colon ("Integrated Camera: Integrated C").
    pub fn display_name(&self) -> String {
        clean_card(&self.card)
    }
}

/// A V4L2 card name without the model repeated after a colon.
pub fn clean_card(card: &str) -> String {
    let card = card.trim();
    let name = card.split(':').next().unwrap_or(card).trim();
    if name.is_empty() {
        card.to_string()
    } else {
        name.to_string()
    }
}

/// struct v4l2_capability.
#[repr(C)]
struct RawCapability {
    driver: [u8; 16],
    card: [u8; 32],
    bus_info: [u8; 32],
    version: u32,
    capabilities: u32,
    device_caps: u32,
    reserved: [u32; 3],
}

fn c_str(b: &[u8]) -> String {
    let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    String::from_utf8_lossy(&b[..end]).into_owned()
}

/// Ask an open node what it is: its raw capabilities (the v4l crate
/// drops bits it doesn't know, such as IO_MC) and capture formats.
pub fn query(dev: &v4l::Device) -> std::io::Result<NodeInfo> {
    use v4l::video::Capture;
    // SAFETY: VIDIOC_QUERYCAP fills a struct v4l2_capability, which
    // RawCapability lays out exactly.
    let raw = unsafe {
        let mut raw: RawCapability = std::mem::zeroed();
        v4l::v4l2::ioctl(
            dev.handle().fd(),
            v4l::v4l2::vidioc::VIDIOC_QUERYCAP,
            &mut raw as *mut RawCapability as *mut std::os::raw::c_void,
        )?;
        raw
    };
    let mut info = NodeInfo {
        driver: c_str(&raw.driver),
        card: c_str(&raw.card),
        bus_info: c_str(&raw.bus_info),
        capabilities: raw.capabilities,
        device_caps: raw.device_caps,
        formats: None,
    };
    if info.caps() & CAP_VIDEO_CAPTURE != 0 {
        info.formats = Some(
            dev.enum_formats()
                .map(|f| f.into_iter().map(|d| d.fourcc.repr).collect())
                .unwrap_or_default(),
        );
    }
    Ok(info)
}

/// For a node OST may not open (no permission): whether to list it
/// anyway, from sysfs. Nothing can be checked but what sysfs tells, so
/// only a USB camera's first node or a v4l2loopback device is listed (and
/// its name, from sysfs).
pub fn unopenable_camera(node: &str) -> Option<String> {
    let dir = std::path::Path::new("/sys/class/video4linux").join(node);
    let read = |f: &str| std::fs::read_to_string(dir.join(f)).ok();
    if read("index")?.trim() != "0" {
        return None;
    }
    let driver = std::fs::read_link(dir.join("device/driver"))
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()));
    let virtual_node = std::fs::canonicalize(&dir)
        .map(|p| p.starts_with("/sys/devices/virtual"))
        .unwrap_or(false);
    match driver.as_deref() {
        Some("uvcvideo") => {}
        None if virtual_node => {}
        _ => return None,
    }
    Some(clean_card(&read("name")?))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(driver: &str, card: &str, caps: u32, device: u32, formats: &[&[u8; 4]]) -> NodeInfo {
        NodeInfo {
            driver: driver.into(),
            card: card.into(),
            bus_info: String::new(),
            capabilities: caps,
            device_caps: device,
            formats: Some(formats.iter().map(|f| **f).collect()),
        }
    }

    /// Intel IPU6 ISYS capture nodes (drivers/media/pci/intel/ipu6,
    /// "Intel IPU6 ISYS Capture N"): driver "isys", card "ipu6", device
    /// caps STREAMING | IO_MC | VIDEO_CAPTURE | META_CAPTURE. Their format
    /// list includes YUYV and UYVY (what a CSI-2 sensor may send), so only
    /// IO_MC tells them apart.
    #[test]
    fn ipu6_isys_nodes_are_not_cameras() {
        let isys = NodeInfo {
            bus_info: "PCI:0000:00:05.0".into(),
            ..node(
                "isys",
                "ipu6",
                0xa480_0001,
                0x2480_0001,
                &[
                    b"BG12", b"BA10", b"BG10", b"GREY", b"UYVY", b"YUYV", b"RGBP", b"BGR3",
                ],
            )
        };
        assert_eq!(isys.verdict(), Verdict::MediaController);
        // Even before its formats are asked.
        let bare = NodeInfo {
            formats: None,
            ..isys.clone()
        };
        assert_eq!(bare.verdict(), Verdict::MediaController);
        // IPU3 CIO2 ("ipu3-cio2", multi-planar, IO_MC) and vimc's raw
        // capture nodes are the same kind.
        let cio2 = node(
            "ipu3-cio2",
            "Intel IPU3 CIO2",
            0xa400_1000,
            0x2400_1000,
            &[b"ip3G"],
        );
        assert_ne!(cio2.verdict(), Verdict::Camera);
        let vimc = node(
            "vimc",
            "Virtual Media Controller",
            0xa520_0001,
            0x2520_0001,
            &[b"BA81"],
        );
        assert_eq!(vimc.verdict(), Verdict::MediaController);
    }

    /// A UVC webcam (values from linuxlt's Chicony "Integrated Camera"):
    /// its first node captures, its second carries metadata.
    #[test]
    fn uvc_capture_node_is_a_camera_and_its_metadata_node_is_not() {
        let capture = node(
            "uvcvideo",
            "Integrated Camera: Integrated C",
            0x84a0_0001,
            0x0420_0001,
            &[b"MJPG", b"YUYV"],
        );
        assert_eq!(capture.verdict(), Verdict::Camera);
        assert_eq!(capture.display_name(), "Integrated Camera");
        let meta = NodeInfo {
            formats: None,
            ..node(
                "uvcvideo",
                "Integrated Camera: Integrated C",
                0x84a0_0001,
                0x04a0_0000,
                &[],
            )
        };
        assert_eq!(meta.verdict(), Verdict::NotCapture);
    }

    /// v4l2loopback (values from linuxlt): exclusive_caps=1 without a
    /// producer is output-only; with one (or with exclusive_caps=0) it
    /// captures.
    #[test]
    fn v4l2loopback_is_a_camera_while_it_can_capture() {
        let idle = node(
            "v4l2 loopback",
            "OST test camera A",
            0x8520_0002,
            0x0520_0002,
            &[],
        );
        assert_eq!(idle.verdict(), Verdict::NotCapture);
        let fed = node(
            "v4l2 loopback",
            "OST test camera A",
            0x8520_0001,
            0x0520_0001,
            &[b"YUYV"],
        );
        assert_eq!(fed.verdict(), Verdict::Camera);
        // exclusive_caps=0: capture and output, no format until fed.
        let shared = node(
            "v4l2 loopback",
            "Dummy video device (0x0000)",
            0x8520_0003,
            0x0520_0003,
            &[],
        );
        assert_eq!(shared.verdict(), Verdict::Camera);
        // Fed something OST can't show.
        let bayer = node("v4l2 loopback", "Raw", 0x8520_0001, 0x0520_0001, &[b"BA81"]);
        assert_eq!(bayer.verdict(), Verdict::NoUsableFormat);
    }

    #[test]
    fn codecs_and_old_drivers() {
        // A stateful decoder (multi-planar M2M).
        let codec = node(
            "hantro-vpu",
            "rockchip,rk3399-vpu-dec",
            0x8420_4000,
            0x0420_4000,
            &[b"NV12"],
        );
        assert_eq!(codec.verdict(), Verdict::MemoryToMemory);
        // Single-planar M2M converter with capture and output bits.
        let conv = node("vim2m", "vim2m", 0x8420_8003, 0x0420_8003, &[b"RGBP"]);
        assert_eq!(conv.verdict(), Verdict::MemoryToMemory);
        // A driver without DEVICE_CAPS: `capabilities` is the node's.
        let old = node("bttv", "BT878 video", 0x0500_0001, 0, &[b"YUYV"]);
        assert_eq!(old.verdict(), Verdict::Camera);
    }
}
