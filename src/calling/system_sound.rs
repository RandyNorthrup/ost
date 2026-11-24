//! Teams' "Include sound" (the share tray's switch, the sharing bar's
//! Share sound): your computer's sound goes into the call with your
//! screen. As Teams does it (calling-pluginless `addAudioSharingStream`,
//! desktop `shareSystemSound`), it is mixed into your normal outgoing
//! audio — no stream of its own, nothing signalled — and it keeps going
//! while your mic is muted (only the mic is muted then).
//!
//! On Linux the computer's sound is PipeWire's: OST captures it with a
//! stream of its own that PipeWire doesn't connect anywhere, and links
//! every other application's playback stream into it (as Teams' system
//! audio driver leaves Teams' own playback out, OST leaves out its own —
//! the call — so others don't hear themselves). Streams that start later
//! are linked as they appear.

use std::cell::RefCell;
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::Result;
use pipewire as pw;
use pw::spa;
use pw::types::ObjectType;

/// The call's rate (mono samples a second).
const RATE: u32 = super::audio_codec::CALL_RATE;
/// Keep at most this much sound waiting (a quarter second).
const MAX_QUEUED: usize = RATE as usize / 4;

/// Captured sound, mono at the call's rate, waiting to be mixed.
fn queue() -> &'static Mutex<VecDeque<i16>> {
    static Q: Mutex<VecDeque<i16>> = Mutex::new(VecDeque::new());
    &Q
}

static RUNNING: AtomicBool = AtomicBool::new(false);

/// Whether the computer's sound is being shared.
pub fn running() -> bool {
    RUNNING.load(Ordering::Relaxed)
}

/// Mix the computer's sound into one outgoing frame: `mic` (None while
/// muted) and `len` samples of shared sound when there are any.
pub fn mix(mic: Option<Vec<i16>>, len: usize) -> Option<Vec<i16>> {
    if !running() || len == 0 {
        return mic;
    }
    let shared: Vec<i16> = {
        let mut q = queue().lock().unwrap_or_else(|e| e.into_inner());
        if q.len() < len {
            return mic;
        }
        q.drain(..len).collect()
    };
    Some(mix_into(mic, &shared))
}

fn mix_into(mic: Option<Vec<i16>>, shared: &[i16]) -> Vec<i16> {
    match mic {
        Some(mut m) => {
            for (a, b) in m.iter_mut().zip(shared) {
                *a = a.saturating_add(*b);
            }
            m
        }
        None => shared.to_vec(),
    }
}

/// Stereo float frames to mono 16-bit samples.
fn to_mono(samples: &[f32], channels: usize) -> Vec<i16> {
    let channels = channels.max(1);
    samples
        .chunks_exact(channels)
        .map(|f| {
            let v = f.iter().sum::<f32>() / channels as f32;
            (v.clamp(-1.0, 1.0) * 32767.0) as i16
        })
        .collect()
}

/// Sharing the computer's sound; drop it to stop.
pub struct SystemSound {
    stop: Arc<AtomicBool>,
}

impl SystemSound {
    pub fn start() -> Result<Self> {
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        queue().lock().unwrap_or_else(|e| e.into_inner()).clear();
        RUNNING.store(true, Ordering::Relaxed);
        std::thread::Builder::new().name("ost-system-sound".into()).spawn(move || {
            if let Err(e) = run(&stop2) {
                tracing::warn!("system sound ended: {e:#}");
            }
            RUNNING.store(false, Ordering::Relaxed);
        })?;
        tracing::info!("system sound shared");
        Ok(Self { stop })
    }
}

impl Drop for SystemSound {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        RUNNING.store(false, Ordering::Relaxed);
        queue().lock().unwrap_or_else(|e| e.into_inner()).clear();
        tracing::info!("system sound stopped");
    }
}

/// What the registry tells about nodes and ports.
#[derive(Default)]
struct Graph {
    /// Playback streams of other applications: node id.
    sources: Vec<u32>,
    /// Ports: id -> (node, output, channel).
    ports: HashMap<u32, (u32, bool, String)>,
    /// Links made: (output port, input port).
    linked: Vec<(u32, u32)>,
    links: Vec<pw::link::Link>,
}

fn run(stop: &Arc<AtomicBool>) -> Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;
    let registry = core.get_registry_rc()?;
    let stream = pw::stream::StreamBox::new(
        &core,
        "ost-include-sound",
        pw::properties::properties! {
            *pw::keys::MEDIA_TYPE => "Audio",
            *pw::keys::MEDIA_CATEGORY => "Capture",
            *pw::keys::MEDIA_ROLE => "Screen",
            *pw::keys::NODE_NAME => "ost-include-sound",
            *pw::keys::NODE_DESCRIPTION => "OST shared sound",
            "node.autoconnect" => "false",
            "audio.position" => "FL,FR",
        },
    )?;
    let channels = Rc::new(RefCell::new(2usize));
    // Our stream's node, once PipeWire has made it.
    let our_node = Rc::new(std::cell::Cell::new(u32::MAX));
    let _listener = stream
        .add_local_listener_with_user_data(channels.clone())
        .state_changed({
            let our_node = our_node.clone();
            move |stream, _, _, new| {
                if matches!(new, pw::stream::StreamState::Paused | pw::stream::StreamState::Streaming) {
                    our_node.set(stream.node_id());
                }
            }
        })
        .param_changed(|_, ch, id, param| {
            let Some(param) = param else { return };
            if id != spa::param::ParamType::Format.as_raw() {
                return;
            }
            let mut info = spa::param::audio::AudioInfoRaw::new();
            if info.parse(param).is_ok() {
                *ch.borrow_mut() = info.channels().max(1) as usize;
            }
        })
        .process(|stream, ch| {
            let Some(mut buffer) = stream.dequeue_buffer() else { return };
            let datas = buffer.datas_mut();
            let Some(d) = datas.first_mut() else { return };
            let size = d.chunk().size() as usize;
            let Some(bytes) = d.data() else { return };
            let bytes = &bytes[..size.min(bytes.len())];
            let floats: Vec<f32> = bytes.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
            let mono = to_mono(&floats, *ch.borrow());
            let mut q = queue().lock().unwrap_or_else(|e| e.into_inner());
            q.extend(mono);
            let excess = q.len().saturating_sub(MAX_QUEUED);
            q.drain(..excess);
        })
        .register()?;

    let mut info = spa::param::audio::AudioInfoRaw::new();
    info.set_format(spa::param::audio::AudioFormat::F32LE);
    info.set_rate(RATE);
    info.set_channels(2);
    let mut position = [0u32; spa::param::audio::MAX_CHANNELS];
    position[0] = spa::sys::SPA_AUDIO_CHANNEL_FL;
    position[1] = spa::sys::SPA_AUDIO_CHANNEL_FR;
    info.set_position(position);
    let values: Vec<u8> = spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(spa::pod::Object {
            type_: spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
            id: spa::param::ParamType::EnumFormat.as_raw(),
            properties: info.into(),
        }),
    )?
    .0
    .into_inner();
    let mut params = [spa::pod::Pod::from_bytes(&values).ok_or_else(|| anyhow::anyhow!("format"))?];
    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::MAP_BUFFERS | pw::stream::StreamFlags::RT_PROCESS,
        &mut params,
    )?;

    let me = std::process::id().to_string();
    let graph: Rc<RefCell<Graph>> = Rc::default();
    // Link whatever can be linked now.
    let relink = {
        let graph = graph.clone();
        let our_node = our_node.clone();
        let core = core.clone();
        move || {
            let our = our_node.get();
            if our == u32::MAX {
                return;
            }
            let mut g = graph.borrow_mut();
            let inputs: Vec<(u32, String)> = g.ports.iter().filter(|(_, p)| p.0 == our && !p.1).map(|(id, p)| (*id, p.2.clone())).collect();
            if inputs.is_empty() {
                return;
            }
            let outputs: Vec<(u32, u32, String)> = g
                .ports
                .iter()
                .filter(|(_, p)| p.1 && g.sources.contains(&p.0))
                .map(|(id, p)| (*id, p.0, p.2.clone()))
                .collect();
            for (out, node, channel) in outputs {
                for (inp, in_channel) in &inputs {
                    // Same channel, or a mono stream into both.
                    if !(channel == *in_channel || channel == "MONO") || g.linked.contains(&(out, *inp)) {
                        continue;
                    }
                    match core.create_object::<pw::link::Link>(
                        "link-factory",
                        &pw::properties::properties! {
                            "link.output.node" => node.to_string(),
                            "link.output.port" => out.to_string(),
                            "link.input.node" => our.to_string(),
                            "link.input.port" => inp.to_string(),
                            "object.linger" => "false",
                        },
                    ) {
                        Ok(link) => {
                            g.linked.push((out, *inp));
                            g.links.push(link);
                        }
                        Err(e) => tracing::warn!("system sound link: {e}"),
                    }
                }
            }
        }
    };
    let relink = Rc::new(relink);
    let _registry_listener = registry
        .add_listener_local()
        .global({
            let graph = graph.clone();
            let relink = relink.clone();
            let me = me.clone();
            move |global| {
                let Some(props) = global.props else { return };
                match global.type_ {
                    ObjectType::Node => {
                        let class = props.get(*pw::keys::MEDIA_CLASS).unwrap_or_default();
                        let pid = props.get("application.process.id").unwrap_or_default();
                        if class == "Stream/Output/Audio" && pid != me {
                            graph.borrow_mut().sources.push(global.id);
                        }
                    }
                    ObjectType::Port => {
                        let node = props.get("node.id").and_then(|n| n.parse::<u32>().ok());
                        let output = props.get("port.direction") == Some("out");
                        let channel = props.get("audio.channel").unwrap_or_default().to_string();
                        // Monitor ports aren't the stream's sound.
                        if let Some(node) = node
                            && props.get("port.monitor") != Some("true")
                        {
                            graph.borrow_mut().ports.insert(global.id, (node, output, channel));
                        }
                    }
                    _ => return,
                }
                relink();
            }
        })
        .global_remove({
            let graph = graph.clone();
            move |id| {
                let mut g = graph.borrow_mut();
                g.sources.retain(|s| *s != id);
                g.ports.remove(&id);
                g.linked.retain(|(o, i)| *o != id && *i != id);
            }
        })
        .register();
    // Our own ports appear once the stream is set up: link then, and
    // check now and then whether to stop.
    let timer = mainloop.loop_().add_timer({
        let mainloop = mainloop.clone();
        let stop = stop.clone();
        let relink = relink.clone();
        let graph = graph.clone();
        let our_node = our_node.clone();
        let ticks = std::cell::Cell::new(0u32);
        move |_| {
            if stop.load(Ordering::Relaxed) {
                mainloop.quit();
            } else {
                relink();
                ticks.set(ticks.get() + 1);
                if ticks.get() % 10 == 1 {
                    let g = graph.borrow();
                    tracing::info!(node = our_node.get(), streams = g.sources.len(), links = g.links.len(),
                        queued = queue().lock().map(|q| q.len()).unwrap_or(0), "system sound");
                }
            }
        }
    });
    timer
        .update_timer(Some(std::time::Duration::from_millis(200)), Some(std::time::Duration::from_millis(500)))
        .into_result()?;
    mainloop.run();
    let _ = stream.disconnect();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixing_adds_and_keeps_sound_while_muted() {
        assert_eq!(mix_into(Some(vec![100, -100, 32000]), &[50, -50, 1000]), vec![150, -150, 32767]);
        assert_eq!(mix_into(None, &[7, 8]), vec![7, 8]);
    }

    #[test]
    fn stereo_to_mono() {
        assert_eq!(to_mono(&[0.5, 0.5, -1.0, 1.0, 2.0, 2.0], 2), vec![16383, 0, 32767]);
    }

    #[test]
    fn nothing_is_mixed_unless_shared() {
        assert!(!running());
        assert_eq!(mix(Some(vec![1, 2]), 2), Some(vec![1, 2]));
        assert_eq!(mix(None, 2), None);
    }
}
