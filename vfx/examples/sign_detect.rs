//! Sign language detection on a video (validation aid): raw I420 frames on
//! stdin, as ffmpeg writes them, e.g.
//!
//! ```text
//! ffmpeg -i clip.webm -f rawvideo -pix_fmt yuv420p -s 640x360 -r 30 - |
//!   cargo run --release -p ost-vfx --example sign_detect -- movenet.onnx 640 360 30
//! ```
//!
//! Prints, for each second of video, the share of frames counted as signing
//! and how long the evaluations took; the messages the meeting would get
//! (ticks every 500 ms of video time); and a summary.
use std::io::Read;
use std::time::Instant;

use ost_vfx::sign_detection::{SignDetector, SigningAggregator, TICK_MS};

/// One second of video's figures.
#[derive(Default)]
struct Second {
    index: u64,
    frames: u32,
    signing: u32,
    /// How long its evaluations took (ms).
    evals: Vec<f64>,
}

impl Second {
    /// A frame at `t_ms`, and how long it took when it was evaluated.
    fn add(&mut self, t_ms: u64, signing: bool, took: Option<f64>) {
        if t_ms / 1000 != self.index {
            self.flush();
            *self = Self {
                index: t_ms / 1000,
                ..Self::default()
            };
        }
        self.frames += 1;
        self.signing += u32::from(signing);
        self.evals.extend(took);
    }

    fn flush(&self) {
        if self.frames == 0 {
            return;
        }
        let mean = self.evals.iter().sum::<f64>() / self.evals.len().max(1) as f64;
        let max = self.evals.iter().copied().fold(0.0, f64::max);
        println!(
            "{:5} s  signing {:4.2}  {} evals, {mean:5.1} ms mean, {max:5.1} ms max",
            self.index,
            self.signing as f64 / self.frames as f64,
            self.evals.len()
        );
    }
}

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, model, w, h, fps] = &args[..] else {
        anyhow::bail!("usage: sign_detect MODEL.onnx WIDTH HEIGHT FPS < frames.i420");
    };
    let (w, h, fps): (u32, u32, f64) = (w.parse()?, h.parse()?, fps.parse()?);
    let started = Instant::now();
    let mut detector = SignDetector::new(&std::fs::read(model)?)?;
    println!(
        "model loaded in {:.0} ms",
        started.elapsed().as_secs_f64() * 1000.0
    );

    let mut frame = vec![0u8; (w * h * 3 / 2) as usize];
    let mut agg = SigningAggregator::new();
    let mut stdin = std::io::stdin().lock();
    let (mut n, mut signing_total, mut evals) = (0u64, 0u64, Vec::new());
    let mut sec = Second::default();
    let mut next_tick = TICK_MS;
    let mut messages = 0;
    while stdin.read_exact(&mut frame).is_ok() {
        let t_ms = (n as f64 * 1000.0 / fps) as u64;
        while t_ms >= next_tick {
            if let Some(m) = agg.tick(next_tick) {
                messages += 1;
                println!("  {:7.1} s  {m:?}", next_tick as f64 / 1000.0);
            }
            next_tick += TICK_MS;
        }
        let due = detector.next_eval_ms();
        let t = Instant::now();
        let signing = detector.push_frame(&frame, w, h, t_ms);
        let took = (detector.next_eval_ms() != due).then(|| t.elapsed().as_secs_f64() * 1000.0);
        evals.extend(took);
        agg.push(signing, t_ms);
        n += 1;
        signing_total += u64::from(signing);
        sec.add(t_ms, signing, took);
    }
    sec.flush();
    evals.sort_by(f64::total_cmp);
    let pct = |p: f64| {
        evals
            .get(((evals.len() as f64 - 1.0) * p) as usize)
            .copied()
            .unwrap_or(0.0)
    };
    println!(
        "{n} frames ({:.1} s): signing {:.2}; {} evaluations, median {:.1} ms, p95 {:.1} ms, max {:.1} ms; {messages} messages",
        n as f64 / fps,
        signing_total as f64 / n.max(1) as f64,
        evals.len(),
        pct(0.5),
        pct(0.95),
        pct(1.0)
    );
    Ok(())
}
