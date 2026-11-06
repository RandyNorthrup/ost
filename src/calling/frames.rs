//! The latest decoded video frame of each stream ("remote", "self"),
//! shared between the media threads that produce them and the UI that
//! draws them. Each publish bumps a sequence number so a drawer knows
//! when there is something new.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

/// An RGBA8888 picture.
#[derive(Debug, Clone)]
pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub rgba: Arc<Vec<u8>>,
    /// Increases with every new frame of this stream.
    pub seq: u64,
}

fn store() -> &'static Mutex<HashMap<String, Frame>> {
    static S: OnceLock<Mutex<HashMap<String, Frame>>> = OnceLock::new();
    S.get_or_init(Default::default)
}

/// Publish a new frame for `key`. Frames whose size doesn't match their
/// buffer are ignored.
pub fn publish(key: &str, width: u32, height: u32, rgba: Vec<u8>) {
    if width == 0 || height == 0 || rgba.len() != (width as usize) * (height as usize) * 4 {
        return;
    }
    let mut s = store().lock().unwrap_or_else(|e| e.into_inner());
    let seq = s.get(key).map_or(1, |f| f.seq + 1);
    s.insert(
        key.to_string(),
        Frame {
            width,
            height,
            rgba: Arc::new(rgba),
            seq,
        },
    );
}

/// The newest frame of `key`, if any.
pub fn latest(key: &str) -> Option<Frame> {
    store()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get(key)
        .cloned()
}

/// Forget `key`'s frames (its video stopped).
pub fn clear(key: &str) {
    store()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .remove(key);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_are_published_and_cleared() {
        publish("t-frames", 2, 1, vec![0; 8]);
        publish("t-frames", 2, 1, vec![1; 8]);
        let f = latest("t-frames").unwrap();
        assert_eq!((f.width, f.height, f.seq), (2, 1, 2));
        publish("t-frames", 2, 2, vec![0; 3]); // wrong size: ignored
        assert_eq!(latest("t-frames").unwrap().seq, 2);
        clear("t-frames");
        assert!(latest("t-frames").is_none());
    }
}
