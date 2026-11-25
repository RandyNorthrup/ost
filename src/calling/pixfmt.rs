//! Camera pictures in the pixel formats cameras deliver (through V4L2 or
//! PipeWire, including libcamera's), converted to the I420 the encoder,
//! the video effects and the preview take: BT.601, studio range.

use super::camera::YuvFrame;

/// A camera's pixel format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    /// Planar 4:2:0, U then V (V4L2 YU12, SPA I420).
    I420,
    /// Planar 4:2:0, V then U.
    Yv12,
    /// Y plane, then interleaved U/V at half size.
    Nv12,
    /// Y plane, then interleaved V/U.
    Nv21,
    /// Packed 4:2:2: the byte offsets of Y0, U, Y1 and V in each 4 bytes
    /// (YUYV/YUY2, YVYU, UYVY).
    Packed422 { y0: u8, u: u8, y1: u8, v: u8 },
    /// 4 bytes a pixel (one unused or alpha): the offsets of R, G and B.
    Rgb32 { r: u8, g: u8, b: u8 },
    /// 3 bytes a pixel: the offsets of R, G and B.
    Rgb24 { r: u8, g: u8, b: u8 },
    /// Motion JPEG: each frame is a JPEG picture.
    Mjpg,
}

pub const YUYV: PixelFormat = PixelFormat::Packed422 {
    y0: 0,
    u: 1,
    y1: 2,
    v: 3,
};
pub const YVYU: PixelFormat = PixelFormat::Packed422 {
    y0: 0,
    v: 1,
    y1: 2,
    u: 3,
};
pub const UYVY: PixelFormat = PixelFormat::Packed422 {
    u: 0,
    y0: 1,
    v: 2,
    y1: 3,
};

impl PixelFormat {
    /// The format of a V4L2 fourcc (byte order as V4L2 documents it).
    pub fn from_fourcc(fourcc: &[u8; 4]) -> Option<Self> {
        use PixelFormat::*;
        let rgb32 = |r, g, b| Some(Rgb32 { r, g, b });
        match fourcc {
            b"YU12" => Some(I420),
            b"YV12" => Some(Yv12),
            b"NV12" => Some(Nv12),
            b"NV21" => Some(Nv21),
            b"YUYV" => Some(YUYV),
            b"YVYU" => Some(YVYU),
            b"UYVY" => Some(UYVY),
            b"MJPG" | b"JPEG" => Some(Mjpg),
            b"RGB3" => Some(Rgb24 { r: 0, g: 1, b: 2 }),
            b"BGR3" => Some(Rgb24 { r: 2, g: 1, b: 0 }),
            // ABGR32/XBGR32 and the old BGR32: B, G, R, A in memory.
            b"AR24" | b"XR24" | b"BGR4" => rgb32(2, 1, 0),
            // BGRA32/BGRX32: A, B, G, R.
            b"RA24" | b"RX24" => rgb32(3, 2, 1),
            // RGBA32/RGBX32: R, G, B, A.
            b"AB24" | b"XB24" => rgb32(0, 1, 2),
            // ARGB32/XRGB32 and the old RGB32: A, R, G, B.
            b"BA24" | b"BX24" | b"RGB4" => rgb32(1, 2, 3),
            _ => None,
        }
    }

    /// How well OST takes it: lower is better (uncompressed 4:2:x
    /// first, then RGB, Motion JPEG last as it costs a decode).
    pub fn rank(self) -> u8 {
        use PixelFormat::*;
        match self {
            Packed422 { .. } => 0,
            Nv12 | Nv21 => 1,
            I420 | Yv12 => 2,
            Rgb32 { .. } | Rgb24 { .. } => 3,
            Mjpg => 4,
        }
    }
}

/// One plane of a picture: its bytes and the bytes from one row to the
/// next.
#[derive(Clone, Copy)]
pub struct Plane<'a> {
    pub data: &'a [u8],
    pub stride: usize,
}

/// The planes of a picture held in one buffer (as V4L2 single-planar
/// formats and most PipeWire buffers hold it), `stride` being the first
/// plane's.
pub fn split(fmt: PixelFormat, h: u32, data: &[u8], stride: usize) -> Vec<Plane<'_>> {
    let (h, stride) = (h as usize, stride.max(1));
    let at = |from: usize| data.get(from.min(data.len())..).unwrap_or_default();
    match fmt {
        PixelFormat::I420 | PixelFormat::Yv12 => {
            let c_stride = stride / 2;
            let y_len = stride * h;
            let c_len = c_stride * h.div_ceil(2);
            vec![
                Plane { data, stride },
                Plane {
                    data: at(y_len),
                    stride: c_stride,
                },
                Plane {
                    data: at(y_len + c_len),
                    stride: c_stride,
                },
            ]
        }
        PixelFormat::Nv12 | PixelFormat::Nv21 => vec![
            Plane { data, stride },
            Plane {
                data: at(stride * h),
                stride,
            },
        ],
        _ => vec![Plane { data, stride }],
    }
}

/// The bytes a row of `w` pixels takes in the first plane (the stride
/// when the source gives none).
pub fn min_stride(fmt: PixelFormat, w: u32) -> usize {
    let w = w as usize;
    match fmt {
        PixelFormat::Packed422 { .. } => w * 2,
        PixelFormat::Rgb32 { .. } => w * 4,
        PixelFormat::Rgb24 { .. } => w * 3,
        _ => w,
    }
}

/// Convert a `w`x`h` picture to I420 (odd sides lose their last row or
/// column). `None` when the planes are too short for it or a JPEG doesn't
/// decode.
pub fn to_i420(fmt: PixelFormat, w: u32, h: u32, planes: &[Plane<'_>]) -> Option<YuvFrame> {
    if fmt == PixelFormat::Mjpg {
        return mjpg_to_i420(planes.first()?.data);
    }
    let (w, h) = ((w & !1) as usize, (h & !1) as usize);
    if w == 0 || h == 0 {
        return None;
    }
    let (cw, ch) = (w / 2, h / 2);
    let mut out = vec![0u8; w * h + 2 * cw * ch];
    let (y_out, c_out) = out.split_at_mut(w * h);
    let (u_out, v_out) = c_out.split_at_mut(cw * ch);
    // Every row a plane must hold: `len` bytes at `stride` apart.
    let fits = |p: &Plane<'_>, rows: usize, len: usize| {
        p.stride >= len && p.data.len() >= p.stride * (rows - 1) + len
    };
    match fmt {
        PixelFormat::I420 | PixelFormat::Yv12 => {
            let [yp, a, b] = planes else { return None };
            let (up, vp) = if fmt == PixelFormat::I420 {
                (a, b)
            } else {
                (b, a)
            };
            if !fits(yp, h, w) || !fits(up, ch, cw) || !fits(vp, ch, cw) {
                return None;
            }
            copy_plane(yp, w, h, y_out);
            copy_plane(up, cw, ch, u_out);
            copy_plane(vp, cw, ch, v_out);
        }
        PixelFormat::Nv12 | PixelFormat::Nv21 => {
            let [yp, uv] = planes else { return None };
            if !fits(yp, h, w) || !fits(uv, ch, w) {
                return None;
            }
            copy_plane(yp, w, h, y_out);
            let (ui, vi) = if fmt == PixelFormat::Nv12 {
                (0, 1)
            } else {
                (1, 0)
            };
            for row in 0..ch {
                let src = &uv.data[row * uv.stride..];
                for col in 0..cw {
                    u_out[row * cw + col] = src[col * 2 + ui];
                    v_out[row * cw + col] = src[col * 2 + vi];
                }
            }
        }
        PixelFormat::Packed422 { y0, u, y1, v } => {
            let p = planes.first()?;
            if !fits(p, h, w * 2) {
                return None;
            }
            let (y0, u, y1, v) = (y0 as usize, u as usize, y1 as usize, v as usize);
            for row in 0..h {
                let src = &p.data[row * p.stride..];
                let dst = &mut y_out[row * w..];
                for col in 0..cw {
                    let px = &src[col * 4..col * 4 + 4];
                    dst[col * 2] = px[y0];
                    dst[col * 2 + 1] = px[y1];
                }
            }
            // Chroma: the average of each pair of rows.
            for row in 0..ch {
                let a = &p.data[row * 2 * p.stride..];
                let b = &p.data[(row * 2 + 1) * p.stride..];
                for col in 0..cw {
                    let (pa, pb) = (&a[col * 4..], &b[col * 4..]);
                    u_out[row * cw + col] = avg2(pa[u], pb[u]);
                    v_out[row * cw + col] = avg2(pa[v], pb[v]);
                }
            }
        }
        PixelFormat::Rgb32 { r, g, b } | PixelFormat::Rgb24 { r, g, b } => {
            let p = planes.first()?;
            let bpp = if matches!(fmt, PixelFormat::Rgb32 { .. }) {
                4
            } else {
                3
            };
            if !fits(p, h, w * bpp) {
                return None;
            }
            let (r, g, b) = (r as usize, g as usize, b as usize);
            for row in 0..ch {
                let rows = [
                    &p.data[row * 2 * p.stride..],
                    &p.data[(row * 2 + 1) * p.stride..],
                ];
                for col in 0..cw {
                    let (mut sr, mut sg, mut sb) = (0i32, 0i32, 0i32);
                    for (dy, src) in rows.iter().enumerate() {
                        for dx in 0..2 {
                            let px = &src[(col * 2 + dx) * bpp..];
                            let (pr, pg, pb) = (px[r] as i32, px[g] as i32, px[b] as i32);
                            y_out[(row * 2 + dy) * w + col * 2 + dx] = luma(pr, pg, pb);
                            (sr, sg, sb) = (sr + pr, sg + pg, sb + pb);
                        }
                    }
                    let (ar, ag, ab) = ((sr + 2) / 4, (sg + 2) / 4, (sb + 2) / 4);
                    u_out[row * cw + col] =
                        clamp(((-38 * ar - 74 * ag + 112 * ab + 128) >> 8) + 128);
                    v_out[row * cw + col] =
                        clamp(((112 * ar - 94 * ag - 18 * ab + 128) >> 8) + 128);
                }
            }
        }
        PixelFormat::Mjpg => unreachable!(),
    }
    Some(YuvFrame {
        width: w as u32,
        height: h as u32,
        data: out,
    })
}

fn copy_plane(p: &Plane<'_>, w: usize, h: usize, out: &mut [u8]) {
    for row in 0..h {
        out[row * w..(row + 1) * w].copy_from_slice(&p.data[row * p.stride..row * p.stride + w]);
    }
}

fn avg2(a: u8, b: u8) -> u8 {
    ((a as u16 + b as u16 + 1) / 2) as u8
}

fn clamp(v: i32) -> u8 {
    v.clamp(0, 255) as u8
}

/// BT.601 studio-range luma of an RGB pixel.
fn luma(r: i32, g: i32, b: i32) -> u8 {
    clamp(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)
}

/// Decode a Motion JPEG frame (full-range YCbCr, as JFIF has it) to
/// studio-range I420.
fn mjpg_to_i420(jpeg: &[u8]) -> Option<YuvFrame> {
    use zune_jpeg::JpegDecoder;
    use zune_jpeg::zune_core::bytestream::ZCursor;
    use zune_jpeg::zune_core::colorspace::ColorSpace;
    use zune_jpeg::zune_core::options::DecoderOptions;

    let mut probe = JpegDecoder::new(ZCursor::new(jpeg));
    probe.decode_headers().ok()?;
    let gray = probe.input_colorspace() == Some(ColorSpace::Luma);
    let out_space = if gray {
        ColorSpace::Luma
    } else {
        ColorSpace::YCbCr
    };
    let mut decoder = JpegDecoder::new_with_options(
        ZCursor::new(jpeg),
        DecoderOptions::default().jpeg_set_out_colorspace(out_space),
    );
    let px = decoder.decode().ok()?;
    let info = decoder.info()?;
    let (sw, sh) = (info.width as usize, info.height as usize);
    let bpp = if gray { 1 } else { 3 };
    if px.len() < sw * sh * bpp {
        return None;
    }
    let (w, h) = (sw & !1, sh & !1);
    if w == 0 || h == 0 {
        return None;
    }
    let (cw, ch) = (w / 2, h / 2);
    let mut out = vec![128u8; w * h + 2 * cw * ch];
    let (y_out, c_out) = out.split_at_mut(w * h);
    let (u_out, v_out) = c_out.split_at_mut(cw * ch);
    // Full range to studio range: Y 16..235, Cb/Cr 16..240.
    let y_lim = |y: u8| (16 + (y as u32 * 219 + 127) / 255) as u8;
    let c_lim =
        |c: u32| (128 + ((c as i32 - 128) * 224 + 127 * (c as i32 - 128).signum()) / 255) as u8;
    for row in 0..h {
        for col in 0..w {
            y_out[row * w + col] = y_lim(px[(row * sw + col) * bpp]);
        }
    }
    if !gray {
        for row in 0..ch {
            for col in 0..cw {
                let (mut cb, mut cr) = (0u32, 0u32);
                for (dy, dx) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                    let i = ((row * 2 + dy) * sw + col * 2 + dx) * 3;
                    cb += px[i + 1] as u32;
                    cr += px[i + 2] as u32;
                }
                u_out[row * cw + col] = c_lim((cb + 2) / 4);
                v_out[row * cw + col] = c_lim((cr + 2) / 4);
            }
        }
    }
    Some(YuvFrame {
        width: w as u32,
        height: h as u32,
        data: out,
    })
}

/// The size a `w`x`h` picture is brought down to so it fits in
/// `max_w`x`max_h` (never enlarged; even sides).
pub fn fit_within(w: u32, h: u32, max_w: u32, max_h: u32) -> (u32, u32) {
    if w <= max_w && h <= max_h {
        return (w & !1, h & !1);
    }
    let scale = (max_w as f64 / w as f64).min(max_h as f64 / h as f64);
    let even = |v: f64| ((v as u32) & !1).max(2);
    (even(w as f64 * scale), even(h as f64 * scale))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 4x2 picture's I420 planes, for checking each format against.
    fn expect(frame: &YuvFrame, y: &[u8], u: &[u8], v: &[u8]) {
        let n = (frame.width * frame.height) as usize;
        let c = n / 4;
        assert_eq!(&frame.data[..n], y, "Y");
        assert_eq!(&frame.data[n..n + c], u, "U");
        assert_eq!(&frame.data[n + c..], v, "V");
    }

    #[test]
    fn fourccs_map_to_formats() {
        assert_eq!(PixelFormat::from_fourcc(b"YUYV"), Some(YUYV));
        assert_eq!(PixelFormat::from_fourcc(b"MJPG"), Some(PixelFormat::Mjpg));
        assert_eq!(
            PixelFormat::from_fourcc(b"XR24"),
            Some(PixelFormat::Rgb32 { r: 2, g: 1, b: 0 })
        );
        // Bayer and other raw sensor formats aren't pictures OST can show.
        assert_eq!(PixelFormat::from_fourcc(b"BA10"), None);
        assert_eq!(PixelFormat::from_fourcc(b"pRAA"), None);
        assert_eq!(PixelFormat::from_fourcc(b"GREY"), None);
    }

    #[test]
    fn packed_422_formats_split_into_planes() {
        // Two rows of 4 pixels; the chroma of a pair of rows is averaged.
        let yuyv = [
            10, 100, 11, 200, 12, 101, 13, 201, //
            20, 102, 21, 202, 22, 103, 23, 203,
        ];
        let f = to_i420(YUYV, 4, 2, &split(YUYV, 2, &yuyv, 8)).unwrap();
        expect(
            &f,
            &[10, 11, 12, 13, 20, 21, 22, 23],
            &[101, 102],
            &[201, 202],
        );
        let uyvy = [
            100, 10, 200, 11, 101, 12, 201, 13, //
            102, 20, 202, 21, 103, 22, 203, 23,
        ];
        let f = to_i420(UYVY, 4, 2, &split(UYVY, 2, &uyvy, 8)).unwrap();
        expect(
            &f,
            &[10, 11, 12, 13, 20, 21, 22, 23],
            &[101, 102],
            &[201, 202],
        );
    }

    #[test]
    fn semi_planar_and_planar_formats_honour_strides() {
        // NV12 with 2 bytes of padding a row.
        let nv12 = [
            1, 2, 3, 4, 0, 0, //
            5, 6, 7, 8, 0, 0, //
            50, 60, 51, 61, 0, 0,
        ];
        let f = to_i420(
            PixelFormat::Nv12,
            4,
            2,
            &split(PixelFormat::Nv12, 2, &nv12, 6),
        );
        expect(&f.unwrap(), &[1, 2, 3, 4, 5, 6, 7, 8], &[50, 51], &[60, 61]);
        let f = to_i420(
            PixelFormat::Nv21,
            4,
            2,
            &split(PixelFormat::Nv21, 2, &nv12, 6),
        );
        expect(&f.unwrap(), &[1, 2, 3, 4, 5, 6, 7, 8], &[60, 61], &[50, 51]);
        let yv12 = [1, 2, 3, 4, 5, 6, 7, 8, 60, 61, 50, 51];
        let f = to_i420(
            PixelFormat::Yv12,
            4,
            2,
            &split(PixelFormat::Yv12, 2, &yv12, 4),
        );
        expect(&f.unwrap(), &[1, 2, 3, 4, 5, 6, 7, 8], &[50, 51], &[60, 61]);
        // Separate planes, as PipeWire may hand them over.
        let (y, u, v) = ([1u8, 2, 3, 4, 5, 6, 7, 8], [50u8, 51], [60u8, 61]);
        let planes = [
            Plane {
                data: &y,
                stride: 4,
            },
            Plane {
                data: &u,
                stride: 2,
            },
            Plane {
                data: &v,
                stride: 2,
            },
        ];
        let f = to_i420(PixelFormat::I420, 4, 2, &planes).unwrap();
        expect(&f, &y, &u, &v);
    }

    #[test]
    fn rgb_formats_convert_to_studio_range() {
        // White, black, red, blue in BGRx, twice.
        let row = [255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 255, 0, 255, 0, 0, 0];
        let bgrx: Vec<u8> = row.iter().chain(row.iter()).copied().collect();
        let fmt = PixelFormat::Rgb32 { r: 2, g: 1, b: 0 };
        let f = to_i420(fmt, 4, 2, &split(fmt, 2, &bgrx, 16)).unwrap();
        assert_eq!(&f.data[..4], &[235, 16, 82, 41]);
        // A grey average (white + black) has neutral chroma.
        assert_eq!(f.data[8], 128);
        assert_eq!(f.data[10], 128);
        // RGB24 (as libcamera's soft ISP gives it) reads the same.
        let rgb: Vec<u8> = bgrx.chunks(4).flat_map(|p| [p[2], p[1], p[0]]).collect();
        let fmt = PixelFormat::Rgb24 { r: 0, g: 1, b: 2 };
        let g = to_i420(fmt, 4, 2, &split(fmt, 2, &rgb, 12)).unwrap();
        assert_eq!(f.data, g.data);
    }

    #[test]
    fn short_buffers_and_odd_sides() {
        assert!(to_i420(YUYV, 4, 2, &split(YUYV, 2, &[0; 15], 8)).is_none());
        assert!(
            to_i420(
                PixelFormat::Mjpg,
                4,
                2,
                &[Plane {
                    data: &[1, 2, 3],
                    stride: 0
                }]
            )
            .is_none()
        );
        // 5x3 YUYV keeps 4x2.
        let f = to_i420(YUYV, 5, 3, &split(YUYV, 3, &[16; 30], 10)).unwrap();
        assert_eq!((f.width, f.height, f.data.len()), (4, 2, 12));
    }

    #[test]
    fn large_pictures_are_fitted() {
        assert_eq!(fit_within(1920, 1080, 640, 360), (640, 360));
        assert_eq!(fit_within(640, 480, 640, 360), (480, 360));
        assert_eq!(fit_within(320, 240, 640, 360), (320, 240));
    }

    /// A tiny baseline JPEG (16x8, 4:2:0, solid mid grey made by
    /// ffmpeg) decodes to studio-range grey.
    #[test]
    fn motion_jpeg_frames_decode() {
        let jpeg = include_bytes!("testdata/grey16x8.jpg");
        let f = to_i420(
            PixelFormat::Mjpg,
            0,
            0,
            &[Plane {
                data: jpeg,
                stride: 0,
            }],
        )
        .unwrap();
        assert_eq!((f.width, f.height), (16, 8));
        let y = f.data[0] as i32;
        assert!((y - (16 + 128 * 219 / 255)).abs() <= 2, "Y {y}");
        assert!((f.data[16 * 8] as i32 - 128).abs() <= 2);
    }
}
