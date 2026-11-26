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

/// What sysfs and udev tell about a V4L2 node, read without opening it
/// (opening a camera node, even to ask what it is, wakes the camera and
/// touches a device the person may not have chosen).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SysNode {
    /// "video0".
    pub node: String,
    pub number: u32,
    /// The node's name (the driver's card name).
    pub name: String,
    /// Its index among its device's nodes (a UVC camera's picture is 0,
    /// its metadata 1).
    pub index: Option<u32>,
    /// Its device number (dev_t), as PipeWire's device.devids give it.
    pub dev: Option<u64>,
    /// The parent device's driver ("uvcvideo"); none for a virtual node.
    pub driver: Option<String>,
    /// No parent device (v4l2loopback and other virtual drivers).
    pub virtual_node: bool,
    /// A v4l2loopback device (it has the module's sysfs attributes).
    pub loopback: bool,
    /// v4l2loopback's `state`: "capture" while a producer writes to it.
    pub loopback_state: Option<String>,
    /// v4l2loopback's `format` ("YUYV:1280x720@15"), empty while idle.
    pub loopback_format: Option<String>,
    /// udev's ID_V4L_CAPABILITIES (":capture:"), read when the node
    /// appeared.
    pub udev_caps: Option<String>,
    /// Where the node's device sits in sysfs (its bus path).
    pub sys_path: Option<String>,
    /// When udev set the node up (its `I:` USEC_INITIALIZED): new each
    /// time the device is plugged in again.
    pub udev_initialized: Option<String>,
}

/// What a node is, from [`SysNode`] alone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Listing {
    /// A camera, by this name.
    Camera(String),
    /// Not a camera (why, for the log).
    NotCamera(&'static str),
    /// Only the node itself can tell (a driver sysfs says too little
    /// about, such as a capture card or an IPU6 ISYS node).
    Unknown,
}

impl SysNode {
    fn udev_capture(&self) -> Option<bool> {
        self.udev_caps
            .as_deref()
            .map(|c| c.split(':').any(|t| t == "capture"))
    }

    /// What the node is, as far as sysfs and udev tell.
    pub fn listing(&self) -> Listing {
        let camera = || Listing::Camera(clean_card(&self.name));
        if self.loopback {
            // Capturing only while something writes to it (exclusive_caps=1),
            // or always (exclusive_caps=0, which udev saw as capture).
            if self.loopback_state.as_deref() == Some("capture") {
                return self.loopback_fed();
            }
            if self.udev_capture() == Some(true) {
                return camera();
            }
            if self.loopback_state.is_some() {
                return Listing::NotCamera("loopback nothing writes to");
            }
            // An older module without `state`: its format shows while it
            // is fed (udev's record is from before, when it may have been
            // idle).
            return match self.loopback_format.as_deref() {
                Some(f) if !f.trim().is_empty() => self.loopback_fed(),
                Some(_) => Listing::NotCamera("loopback nothing writes to"),
                None => Listing::Unknown,
            };
        }
        match self.udev_capture() {
            Some(false) => return Listing::NotCamera("no video capture"),
            None if self.driver.as_deref() == Some("uvcvideo") && self.index != Some(0) => {
                return Listing::NotCamera("UVC metadata node");
            }
            _ => {}
        }
        if self.driver.as_deref() == Some("uvcvideo") {
            return camera();
        }
        Listing::Unknown
    }

    /// A loopback device something writes to: a camera, unless what is
    /// written is a format OST can't show.
    fn loopback_fed(&self) -> Listing {
        let fourcc = self
            .loopback_format
            .as_deref()
            .and_then(|f| f.split(':').next())
            .map(str::as_bytes)
            .and_then(|b| <[u8; 4]>::try_from(b).ok());
        match fourcc {
            Some(f) if PixelFormat::from_fourcc(&f).is_none() => {
                Listing::NotCamera("loopback fed a format OST can't show")
            }
            _ => Listing::Camera(clean_card(&self.name)),
        }
    }

    /// Changes when what the node is may have (for a cache of what
    /// opening it told).
    pub fn fingerprint(&self) -> String {
        format!(
            "{:?}|{:?}|{:?}|{:?}|{:?}|{:?}|{:?}|{}",
            self.dev,
            self.sys_path,
            self.udev_initialized,
            self.driver,
            self.loopback_state,
            self.loopback_format,
            self.udev_caps,
            self.name
        )
    }
}

/// A device number as the kernel packs it (glibc's makedev).
pub fn makedev(major: u64, minor: u64) -> u64 {
    ((major & 0xffff_f000) << 32)
        | ((major & 0xfff) << 8)
        | ((minor & 0xffff_ff00) << 12)
        | (minor & 0xff)
}

/// The V4L2 nodes in `class` (/sys/class/video4linux) with what udev
/// recorded in `udev` (/run/udev/data), in node order. Nothing is opened.
pub fn sys_nodes(class: &std::path::Path, udev: &std::path::Path) -> Vec<SysNode> {
    let mut nodes: Vec<SysNode> = std::fs::read_dir(class)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let node = e.file_name().into_string().ok()?;
            let number: u32 = node.strip_prefix("video")?.parse().ok()?;
            Some(sys_node(&e.path(), node, number, udev))
        })
        .collect();
    nodes.sort_by_key(|n| n.number);
    nodes
}

fn sys_node(dir: &std::path::Path, node: String, number: u32, udev: &std::path::Path) -> SysNode {
    let read = |f: &str| {
        std::fs::read_to_string(dir.join(f))
            .ok()
            .map(|s| s.trim().to_string())
    };
    let dev_str = read("dev");
    let dev = dev_str.as_deref().and_then(|d| {
        let (major, minor) = d.split_once(':')?;
        Some(makedev(major.parse().ok()?, minor.parse().ok()?))
    });
    let record = dev_str.and_then(|d| std::fs::read_to_string(udev.join(format!("c{d}"))).ok());
    let field = |prefix: &str| {
        record
            .as_deref()?
            .lines()
            .find_map(|l| l.strip_prefix(prefix))
            .map(|v| v.trim().to_string())
    };
    let udev_caps = field("E:ID_V4L_CAPABILITIES=");
    let udev_initialized = field("I:");
    let device = dir.join("device");
    let virtual_node = std::fs::symlink_metadata(&device).is_err();
    SysNode {
        name: read("name").unwrap_or_default(),
        index: read("index").and_then(|i| i.parse().ok()),
        dev,
        driver: std::fs::read_link(device.join("driver"))
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned())),
        virtual_node,
        loopback: virtual_node && dir.join("max_openers").exists(),
        loopback_state: read("state"),
        loopback_format: read("format"),
        udev_caps,
        sys_path: std::fs::canonicalize(dir)
            .ok()
            .map(|p| p.to_string_lossy().into_owned()),
        udev_initialized,
        node,
        number,
    }
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

    fn sys(node: &str, name: &str, driver: Option<&str>, udev: Option<&str>) -> SysNode {
        SysNode {
            node: node.into(),
            number: node.trim_start_matches("video").parse().unwrap(),
            name: name.into(),
            index: Some(0),
            dev: None,
            driver: driver.map(str::to_string),
            virtual_node: driver.is_none(),
            loopback: false,
            loopback_state: None,
            loopback_format: None,
            udev_caps: udev.map(str::to_string),
            ..Default::default()
        }
    }

    /// linuxlt's UVC camera (sysfs and udev as they are there): its picture
    /// node is a camera by its name, its metadata node isn't, with or
    /// without udev's record.
    #[test]
    fn uvc_nodes_from_sysfs() {
        let cam = sys(
            "video0",
            "Integrated Camera: Integrated C",
            Some("uvcvideo"),
            Some(":capture:"),
        );
        assert_eq!(cam.listing(), Listing::Camera("Integrated Camera".into()));
        let meta = SysNode {
            index: Some(1),
            ..sys(
                "video1",
                "Integrated Camera: Integrated C",
                Some("uvcvideo"),
                Some(":"),
            )
        };
        assert!(matches!(meta.listing(), Listing::NotCamera(_)));
        let no_udev = |index| SysNode {
            index: Some(index),
            ..sys("video1", "Integrated Camera", Some("uvcvideo"), None)
        };
        assert!(matches!(no_udev(1).listing(), Listing::NotCamera(_)));
        assert_eq!(
            no_udev(0).listing(),
            Listing::Camera("Integrated Camera".into())
        );
    }

    /// v4l2loopback: a camera while something writes to it (`state`
    /// capture, as /dev/video20 on linuxlt), or always with
    /// exclusive_caps=0 (udev saw capture); not while idle; an older
    /// module without `state` shows its format while fed.
    #[test]
    fn loopback_nodes_from_sysfs() {
        let lb = |state: Option<&str>, format: Option<&str>, udev: Option<&str>| SysNode {
            loopback: true,
            loopback_state: state.map(str::to_string),
            loopback_format: format.map(str::to_string),
            ..sys("video20", "OST test camera A", None, udev)
        };
        let a = Listing::Camera("OST test camera A".into());
        assert_eq!(
            lb(
                Some("capture"),
                Some("YUYV:1280x720@15"),
                Some(":video_output:")
            )
            .listing(),
            a
        );
        assert!(matches!(
            lb(Some("output"), Some(""), Some(":video_output:")).listing(),
            Listing::NotCamera(_)
        ));
        assert_eq!(
            lb(Some("output"), Some(""), Some(":capture:video_output:")).listing(),
            a
        );
        assert!(matches!(
            lb(Some("capture"), Some("BA81:640x480@30"), None).listing(),
            Listing::NotCamera(_)
        ));
        assert_eq!(lb(None, Some("YUYV:640x480@30"), None).listing(), a);
        // (udev saw it idle, before its producer started.)
        assert_eq!(
            lb(None, Some("YUYV:640x480@30"), Some(":video_output:")).listing(),
            a
        );
        assert!(matches!(
            lb(None, Some(""), Some(":video_output:")).listing(),
            Listing::NotCamera(_)
        ));
        assert_eq!(lb(None, None, None).listing(), Listing::Unknown);
        // The fingerprint follows its state, so a probe is asked again.
        assert_ne!(
            lb(Some("output"), Some(""), None).fingerprint(),
            lb(Some("capture"), Some("YUYV:640x480@30"), None).fingerprint()
        );
    }

    /// A node of a driver sysfs says too little about (IPU6 ISYS capture
    /// nodes, which udev sees as capture devices; a capture card) is for
    /// PipeWire or the node itself to tell; one udev saw without capture
    /// isn't a camera.
    #[test]
    fn other_drivers_from_sysfs() {
        let isys = sys(
            "video3",
            "Intel IPU6 ISYS Capture 0",
            Some("intel-ipu6-isys"),
            Some(":capture:"),
        );
        assert_eq!(isys.listing(), Listing::Unknown);
        assert_eq!(
            sys("video5", "BT878 video", Some("bttv"), None).listing(),
            Listing::Unknown
        );
        assert!(matches!(
            sys("video9", "vim2m", Some("vim2m"), Some(":video_output:")).listing(),
            Listing::NotCamera(_)
        ));
        assert_eq!(makedev(81, 0), 20736);
        assert_eq!(makedev(81, 4), 20740);
    }

    /// The nodes are read from sysfs and udev's records (a tree laid out
    /// as /sys/class/video4linux and /run/udev/data are).
    #[test]
    fn sys_nodes_reads_sysfs_and_udev() {
        use std::fs;
        use std::os::unix::fs::symlink;
        let root = std::env::temp_dir().join(format!("ost-sysfs-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let class = root.join("class");
        let udev = root.join("udev");
        let usb = root.join("devices/usb1/1-8:1.0");
        fs::create_dir_all(root.join("drivers/uvcvideo")).unwrap();
        fs::create_dir_all(&usb).unwrap();
        fs::create_dir_all(&udev).unwrap();
        symlink(root.join("drivers/uvcvideo"), usb.join("driver")).unwrap();
        let node = |n: &str, files: &[(&str, &str)], parent: Option<&std::path::Path>| {
            let d = class.join(n);
            fs::create_dir_all(&d).unwrap();
            for (f, v) in files {
                fs::write(d.join(f), format!("{v}\n")).unwrap();
            }
            if let Some(p) = parent {
                symlink(p, d.join("device")).unwrap();
            }
        };
        let cam = [
            ("name", "Integrated Camera: Integrated C"),
            ("index", "0"),
            ("dev", "81:0"),
        ];
        node("video0", &cam, Some(&usb));
        node(
            "video1",
            &[
                ("name", "Integrated Camera: Integrated C"),
                ("index", "1"),
                ("dev", "81:1"),
            ],
            Some(&usb),
        );
        node(
            "video20",
            &[
                ("name", "OST test camera A"),
                ("index", "0"),
                ("dev", "81:2"),
                ("max_openers", "10"),
                ("state", "capture"),
                ("format", "YUYV:1280x720@15"),
            ],
            None,
        );
        fs::write(
            udev.join("c81:0"),
            "I:51234567\nE:ID_V4L_VERSION=2\nE:ID_V4L_CAPABILITIES=:capture:\n",
        )
        .unwrap();
        fs::write(udev.join("c81:1"), "E:ID_V4L_CAPABILITIES=:\n").unwrap();
        fs::write(udev.join("c81:2"), "E:ID_V4L_CAPABILITIES=:video_output:\n").unwrap();
        fs::write(class.join("not-a-node"), "").unwrap();

        let nodes = sys_nodes(&class, &udev);
        // The camera plugged in again: same node and number, a new udev
        // record, so what a probe found isn't reused.
        fs::write(
            udev.join("c81:0"),
            "I:99234567\nE:ID_V4L_VERSION=2\nE:ID_V4L_CAPABILITIES=:capture:\n",
        )
        .unwrap();
        let replugged = sys_nodes(&class, &udev);
        let _ = fs::remove_dir_all(&root);
        assert_eq!(nodes[0].udev_initialized.as_deref(), Some("51234567"));
        assert!(
            nodes[0]
                .sys_path
                .as_deref()
                .is_some_and(|p| p.ends_with("/class/video0"))
        );
        assert_ne!(nodes[0].fingerprint(), replugged[0].fingerprint());
        assert_eq!(nodes[1].fingerprint(), replugged[1].fingerprint());
        let names: Vec<&str> = nodes.iter().map(|n| n.node.as_str()).collect();
        assert_eq!(names, ["video0", "video1", "video20"]);
        assert_eq!(nodes[0].driver.as_deref(), Some("uvcvideo"));
        assert_eq!(nodes[0].dev, Some(20736));
        assert_eq!(nodes[0].udev_caps.as_deref(), Some(":capture:"));
        assert!(!nodes[0].virtual_node && !nodes[0].loopback);
        assert_eq!(nodes[1].index, Some(1));
        assert!(nodes[2].virtual_node && nodes[2].loopback);
        assert_eq!(nodes[2].loopback_state.as_deref(), Some("capture"));
        let listings: Vec<Listing> = nodes.iter().map(SysNode::listing).collect();
        assert_eq!(listings[0], Listing::Camera("Integrated Camera".into()));
        assert!(matches!(listings[1], Listing::NotCamera(_)));
        assert_eq!(listings[2], Listing::Camera("OST test camera A".into()));
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
