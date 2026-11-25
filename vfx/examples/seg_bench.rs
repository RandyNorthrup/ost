//! Background effects on a picture (debugging aid):
//! `cargo run -p ost-vfx --example seg_bench -- in.ppm out-prefix`
//! writes `out-prefix-mask.pgm`, `-blur.ppm` and `-picture.ppm` (the
//! picture background is a gradient), and prints how long each step takes.
use ost_vfx::*;
use std::time::Instant;

fn read_ppm(path: &str) -> (u32, u32, Vec<u8>) {
    let b = std::fs::read(path).expect("read");
    let mut fields = Vec::new();
    let mut i = 0;
    while fields.len() < 4 {
        while b[i].is_ascii_whitespace() {
            i += 1;
        }
        if b[i] == b'#' {
            while b[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        let s = i;
        while !b[i].is_ascii_whitespace() {
            i += 1;
        }
        fields.push(String::from_utf8_lossy(&b[s..i]).to_string());
    }
    let (w, h): (u32, u32) = (fields[1].parse().unwrap(), fields[2].parse().unwrap());
    let rgb = &b[i + 1..][..(w * h * 3) as usize];
    let rgba: Vec<u8> = rgb
        .chunks(3)
        .flat_map(|p| [p[0], p[1], p[2], 255])
        .collect();
    (w, h, rgba)
}

fn write_ppm(path: &str, w: usize, h: usize, i420: &[u8]) {
    let mut out = format!("P6\n{w} {h}\n255\n").into_bytes();
    for y in 0..h {
        for x in 0..w {
            let yv = i420[y * w + x] as f32 - 16.0;
            let c = (y / 2) * (w / 2) + x / 2;
            let u = i420[w * h + c] as f32 - 128.0;
            let v = i420[w * h + w * h / 4 + c] as f32 - 128.0;
            for p in [
                1.164 * yv + 1.596 * v,
                1.164 * yv - 0.392 * u - 0.813 * v,
                1.164 * yv + 2.017 * u,
            ] {
                out.push(p.clamp(0.0, 255.0) as u8);
            }
        }
    }
    std::fs::write(path, out).unwrap();
}

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let (w, h, rgba) = read_ppm(&args[1]);
    let frame = Picture::from_rgba(w, h, &rgba);
    let (w, h) = (frame.width as usize, frame.height as usize);
    let t = Instant::now();
    let seg = Segmenter::new()?;
    println!(
        "model loaded in {:.0} ms",
        t.elapsed().as_secs_f64() * 1000.0
    );
    let input = model_input(&frame.data, w as u32, h as u32);
    let t = Instant::now();
    let mut mask = Vec::new();
    for _ in 0..10 {
        mask = seg.segment(&input)?;
    }
    println!(
        "segmentation: {:.1} ms a frame",
        t.elapsed().as_secs_f64() * 100.0
    );
    let pgm: Vec<u8> = format!("P5\n{MASK} {MASK}\n255\n")
        .into_bytes()
        .into_iter()
        .chain(mask.iter().map(|m| (m * 255.0) as u8))
        .collect();
    std::fs::write(format!("{}-mask.pgm", args[2]), pgm)?;

    let t = Instant::now();
    let mut blur = Vec::new();
    blur_i420(&frame.data, w, h, 8, &mut blur);
    let mut out = frame.data.clone();
    composite(&mut out, &blur, &mask, w, h);
    println!(
        "blur + composite: {:.1} ms",
        t.elapsed().as_secs_f64() * 1000.0
    );
    write_ppm(&format!("{}-blur.ppm", args[2]), w, h, &out);

    let grad: Vec<u8> = (0..400 * 300)
        .flat_map(|i| {
            [
                (i % 400 * 255 / 400) as u8,
                120,
                (i / 400 * 255 / 300) as u8,
                255,
            ]
        })
        .collect();
    let pic = Picture::from_rgba(400, 300, &grad);
    let t = Instant::now();
    let back = fit_cover(&pic, w, h);
    let mut out = frame.data.clone();
    composite(&mut out, &back, &mask, w, h);
    println!(
        "picture + composite: {:.1} ms",
        t.elapsed().as_secs_f64() * 1000.0
    );
    write_ppm(&format!("{}-picture.ppm", args[2]), w, h, &out);
    Ok(())
}
