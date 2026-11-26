//! Which of a camera's own modes (format, size, frame rate) to capture in.
//!
//! A camera only delivers the modes it lists. Asking for anything else
//! goes wrong in ways that depend on the camera and the stack: PipeWire's
//! V4L2 source fixates a size and rate it then can't set ("error set
//! output format: -22", seen with a MacroSilicon MS2109 HDMI capture card
//! asked for 640x360 at 15 fps), and V4L2 drivers round to the nearest
//! size and rate, which can be a raw mode at a third of the rate Motion
//! JPEG offers at that size. As Chromium and WebRTC do, OST reads the
//! camera's modes and picks the one closest to what it wants: the
//! smallest size that covers it (else the largest), then the lowest rate
//! that reaches the wanted one (else the highest), then the cheaper
//! format.

use super::pixfmt::PixelFormat;

/// One mode a camera offers. `format` is the stack's own name for the
/// pixel format (a V4L2 fourcc, a SPA video format or Motion JPEG).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Mode<F> {
    pub format: F,
    pub pixel: PixelFormat,
    pub width: u32,
    pub height: u32,
    /// Frames per second as a fraction; 0/1 for a variable rate.
    pub fps_num: u32,
    pub fps_den: u32,
}

impl<F> Mode<F> {
    /// Its frame rate in thousandths of a frame per second (a variable
    /// rate counts as the wanted one).
    fn millifps(&self, want: u32) -> u64 {
        if self.fps_num == 0 || self.fps_den == 0 {
            return u64::from(want) * 1000;
        }
        u64::from(self.fps_num) * 1000 / u64::from(self.fps_den)
    }

    /// Lower sorts first.
    fn key(&self, want: (u32, u32), fps: u32) -> (bool, u64, bool, u64, u8) {
        let area = u64::from(self.width) * u64::from(self.height);
        let covers = self.width >= want.0 && self.height >= want.1;
        let rate = self.millifps(fps);
        let fast = rate >= u64::from(fps) * 1000;
        (
            !covers,
            if covers { area } else { u64::MAX - area },
            !fast,
            if fast { rate } else { u64::MAX - rate },
            self.pixel.rank(),
        )
    }
}

/// `modes` best first for a picture of about `want` at `fps`.
pub fn order<F>(modes: &mut [Mode<F>], want: (u32, u32), fps: u32) {
    modes.sort_by_key(|m| m.key(want, fps));
}

/// A value from a camera's range: `want` within `min..=max`, on `step`.
pub fn in_range(want: u32, min: u32, max: u32, step: u32) -> u32 {
    let v = want.clamp(min, max.max(min));
    if step > 1 {
        let v = min + (v - min) / step * step;
        v.max(min)
    } else {
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::calling::pixfmt;

    fn m(pixel: PixelFormat, width: u32, height: u32, fps: u32) -> Mode<&'static str> {
        Mode {
            format: if pixel == PixelFormat::Mjpg {
                "MJPG"
            } else {
                "YUYV"
            },
            pixel,
            width,
            height,
            fps_num: fps,
            fps_den: 1,
        }
    }

    /// The MacroSilicon MS2109 HDMI capture card's modes (USB 534d:2109):
    /// Motion JPEG up to 1920x1080 at 60 fps, YUYV at 5-10 fps above
    /// 800x600.
    fn ms2109() -> Vec<Mode<&'static str>> {
        let mut v = Vec::new();
        for (w, h) in [
            (1920, 1080),
            (1600, 1200),
            (1280, 720),
            (1024, 768),
            (800, 600),
            (640, 480),
        ] {
            for fps in [60, 30, 25, 20, 10] {
                v.push(m(PixelFormat::Mjpg, w, h, fps));
            }
        }
        for (w, h, rates) in [
            (1920, 1080, &[5][..]),
            (1280, 720, &[10][..]),
            (800, 600, &[20, 10, 5][..]),
            (720, 480, &[30, 20, 10, 5][..]),
            (640, 480, &[30, 20, 10, 5][..]),
        ] {
            for &fps in rates {
                v.push(m(pixfmt::YUYV, w, h, fps));
            }
        }
        v
    }

    #[test]
    fn a_capture_card_gives_motion_jpeg_where_raw_is_too_slow() {
        let mut modes = ms2109();
        order(&mut modes, (1280, 720), 30);
        assert_eq!(modes[0], m(PixelFormat::Mjpg, 1280, 720, 30));
        order(&mut modes, (1920, 1080), 30);
        assert_eq!(modes[0], m(PixelFormat::Mjpg, 1920, 1080, 30));
    }

    #[test]
    fn a_size_the_camera_lacks_is_the_smallest_that_covers_it() {
        let mut modes = ms2109();
        // The preview's 640x360 at 15 fps: raw 640x480 at 20 fps.
        order(&mut modes, (640, 360), 15);
        assert_eq!(modes[0], m(pixfmt::YUYV, 640, 480, 20));
        // Nothing covers it: the largest.
        let mut small = vec![m(pixfmt::YUYV, 320, 240, 30), m(pixfmt::YUYV, 640, 480, 30)];
        order(&mut small, (1920, 1080), 30);
        assert_eq!(small[0], m(pixfmt::YUYV, 640, 480, 30));
    }

    #[test]
    fn a_rate_too_low_is_the_highest_there_is() {
        let mut modes = vec![
            m(pixfmt::YUYV, 1280, 720, 5),
            m(pixfmt::YUYV, 1280, 720, 10),
        ];
        order(&mut modes, (1280, 720), 30);
        assert_eq!(modes[0].fps_num, 10);
    }

    #[test]
    fn raw_goes_first_when_it_is_fast_enough() {
        let mut modes = vec![
            m(PixelFormat::Mjpg, 1280, 720, 30),
            m(pixfmt::YUYV, 1280, 720, 30),
        ];
        order(&mut modes, (1280, 720), 30);
        assert_eq!(modes[0].pixel, pixfmt::YUYV);
    }

    #[test]
    fn a_variable_rate_counts_as_the_one_wanted() {
        let mut modes = vec![
            Mode {
                fps_num: 0,
                ..m(pixfmt::YUYV, 1280, 720, 0)
            },
            m(pixfmt::YUYV, 1280, 720, 10),
        ];
        order(&mut modes, (1280, 720), 30);
        assert_eq!(modes[0].fps_num, 0);
    }

    #[test]
    fn range_values_stay_on_the_step() {
        assert_eq!(in_range(640, 16, 1920, 1), 640);
        assert_eq!(in_range(8, 16, 1920, 1), 16);
        assert_eq!(in_range(4000, 16, 1920, 1), 1920);
        assert_eq!(in_range(641, 16, 1920, 8), 640);
    }
}
