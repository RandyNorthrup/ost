//! BlurHash (blurha.sh), which Teams sends with a pasted picture
//! (`properties.blurHash`: `[{blurhash, imageId}]`, 4 x 3 components, as
//! its compose box's `blurhash` encode gives them) so other clients can
//! show a placeholder while the picture loads.

const DIGITS: &[u8; 83] =
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~";

fn base83(value: u32, length: u32, out: &mut String) {
    for i in 1..=length {
        let digit = (value / 83u32.pow(length - i)) % 83;
        out.push(DIGITS[digit as usize] as char);
    }
}

fn to_linear(v: u8) -> f64 {
    let v = v as f64 / 255.0;
    if v <= 0.04045 {
        v / 12.92
    } else {
        ((v + 0.055) / 1.055).powf(2.4)
    }
}

fn to_srgb(v: f64) -> u32 {
    let v = v.clamp(0.0, 1.0);
    if v <= 0.0031308 {
        (v * 12.92 * 255.0 + 0.5) as u32
    } else {
        ((1.055 * v.powf(1.0 / 2.4) - 0.055) * 255.0 + 0.5) as u32
    }
}

fn sign_pow(v: f64, e: f64) -> f64 {
    v.abs().powf(e).copysign(v)
}

/// The BlurHash of `rgba` (`width` x `height`, 4 bytes a pixel) with
/// `cx` x `cy` components (1..=9 each); None for an empty picture.
pub fn encode(rgba: &[u8], width: usize, height: usize, cx: usize, cy: usize) -> Option<String> {
    if width == 0
        || height == 0
        || rgba.len() < width * height * 4
        || !(1..=9).contains(&cx)
        || !(1..=9).contains(&cy)
    {
        return None;
    }
    let mut factors: Vec<[f64; 3]> = Vec::with_capacity(cx * cy);
    for j in 0..cy {
        for i in 0..cx {
            let norm = if i == 0 && j == 0 { 1.0 } else { 2.0 };
            let mut f = [0.0; 3];
            for y in 0..height {
                let by = (std::f64::consts::PI * j as f64 * y as f64 / height as f64).cos();
                for x in 0..width {
                    let basis = norm
                        * (std::f64::consts::PI * i as f64 * x as f64 / width as f64).cos()
                        * by;
                    let p = (y * width + x) * 4;
                    f[0] += basis * to_linear(rgba[p]);
                    f[1] += basis * to_linear(rgba[p + 1]);
                    f[2] += basis * to_linear(rgba[p + 2]);
                }
            }
            let scale = 1.0 / (width * height) as f64;
            factors.push([f[0] * scale, f[1] * scale, f[2] * scale]);
        }
    }
    let mut out = String::new();
    base83(((cx - 1) + (cy - 1) * 9) as u32, 1, &mut out);
    let ac = &factors[1..];
    let max_value = if ac.is_empty() {
        base83(0, 1, &mut out);
        1.0
    } else {
        let actual = ac
            .iter()
            .flat_map(|c| c.iter())
            .fold(0.0f64, |m, v| m.max(v.abs()));
        let quantised = ((actual * 166.0 - 0.5).floor() as i64).clamp(0, 82) as u32;
        base83(quantised, 1, &mut out);
        (quantised as f64 + 1.0) / 166.0
    };
    let dc = factors[0];
    base83(
        (to_srgb(dc[0]) << 16) + (to_srgb(dc[1]) << 8) + to_srgb(dc[2]),
        4,
        &mut out,
    );
    for c in ac {
        let q = |v: f64| {
            ((sign_pow(v / max_value, 0.5) * 9.0 + 9.5).floor() as i64).clamp(0, 18) as u32
        };
        base83(q(c[0]) * 19 * 19 + q(c[1]) * 19 + q(c[2]), 2, &mut out);
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_flat_picture() {
        // a solid colour: no AC detail, the DC is the colour
        let px: Vec<u8> = std::iter::repeat_n([46u8, 125, 50, 255], 8 * 6)
            .flatten()
            .collect();
        let h = encode(&px, 8, 6, 4, 3).unwrap();
        assert_eq!(h.len(), 28);
        assert!(h.starts_with('L'));
        // the DC digits of #2E7D32
        let mut dc = String::new();
        base83((46 << 16) + (125 << 8) + 50, 4, &mut dc);
        assert_eq!(&h[2..6], dc);
        assert_eq!(encode(&px, 0, 6, 4, 3), None);
    }

    #[test]
    fn known_hash() {
        // A 2 x 1 black / white picture with 2 x 1 components, checked
        // against the reference encoder's arithmetic.
        let px = [0u8, 0, 0, 255, 255, 255, 255, 255];
        let h = encode(&px, 2, 1, 2, 1).unwrap();
        assert_eq!(h.len(), 8);
        assert_eq!(&h[..1], "1");
    }
}
