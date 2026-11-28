//! The system's default audio endpoints from PipeWire's "default" metadata
//! (`default.audio.source` / `default.audio.sink`), by their descriptions:
//! the names cpal's PipeWire host lists, so the in-call device picker can
//! show which device is in use when none was chosen (Teams marks the
//! system default).

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use pipewire as pw;
use pw::metadata::Metadata;
use pw::types::ObjectType;

/// (microphone, speaker) descriptions, or `None` where PipeWire has no
/// default (or isn't running).
pub fn default_endpoints() -> (Option<String>, Option<String>) {
    query().unwrap_or((None, None))
}

fn query() -> Option<(Option<String>, Option<String>)> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None).ok()?;
    let context = pw::context::ContextRc::new(&mainloop, None).ok()?;
    let core = context.connect_rc(None).ok()?;
    let registry = core.get_registry_rc().ok()?;

    // node.name -> node.description for sinks and sources.
    let names: Rc<RefCell<HashMap<String, String>>> = Rc::default();
    // The default sink's and source's node.name.
    let defaults: Rc<RefCell<(Option<String>, Option<String>)>> = Rc::default();
    // Bound metadata and its listener stay alive until the loop ends.
    let keep: Rc<RefCell<Vec<(Metadata, pw::metadata::MetadataListener)>>> = Rc::default();
    let pending: Rc<RefCell<Vec<pw::spa::utils::result::AsyncSeq>>> = Rc::default();
    pending.borrow_mut().push(core.sync(0).ok()?);

    let _core_listener = core
        .add_listener_local()
        .done({
            let pending = pending.clone();
            let mainloop = mainloop.clone();
            move |id, seq| {
                if id != pw::core::PW_ID_CORE {
                    return;
                }
                let mut p = pending.borrow_mut();
                if let Some(i) = p.iter().position(|s| *s == seq) {
                    p.remove(i);
                }
                if p.is_empty() {
                    mainloop.quit();
                }
            }
        })
        .register();

    let _registry_listener = registry
        .add_listener_local()
        .global({
            let names = names.clone();
            let defaults = defaults.clone();
            let keep = keep.clone();
            let pending = pending.clone();
            let registry = registry.clone();
            let core = core.clone();
            move |global| {
                let Some(props) = global.props else { return };
                match global.type_ {
                    ObjectType::Node => {
                        let class = props.get(*pw::keys::MEDIA_CLASS).unwrap_or_default();
                        if (class == "Audio/Sink" || class == "Audio/Source")
                            && let (Some(name), Some(desc)) = (
                                props.get(*pw::keys::NODE_NAME),
                                props.get(*pw::keys::NODE_DESCRIPTION),
                            )
                        {
                            names
                                .borrow_mut()
                                .insert(name.to_string(), desc.to_string());
                        }
                    }
                    ObjectType::Metadata => {
                        if props.get("metadata.name") != Some("default") {
                            return;
                        }
                        let Ok(metadata) = registry.bind::<Metadata, _>(global) else {
                            return;
                        };
                        let defaults = defaults.clone();
                        let listener = metadata
                            .add_listener_local()
                            .property(move |_subject, key, _type, value| {
                                let slot = match key {
                                    Some("default.audio.source") => 0,
                                    Some("default.audio.sink") => 1,
                                    _ => return 0,
                                };
                                let name = value.and_then(node_name_of);
                                let mut d = defaults.borrow_mut();
                                if slot == 0 {
                                    d.0 = name
                                } else {
                                    d.1 = name
                                }
                                0
                            })
                            .register();
                        keep.borrow_mut().push((metadata, listener));
                        // Another round trip delivers the metadata's properties.
                        if let Ok(seq) = core.sync(0) {
                            pending.borrow_mut().push(seq);
                        }
                    }
                    _ => {}
                }
            }
        })
        .register();

    mainloop.run();
    let names = names.borrow();
    let d = defaults.borrow();
    let describe = |n: &Option<String>| n.as_ref().and_then(|n| names.get(n).cloned());
    Some((describe(&d.0), describe(&d.1)))
}

/// One of Teams' audio devices (the Calls app's device menu): a card with
/// both a microphone and a speaker, used together.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct DeviceGroup {
    /// PipeWire's device id.
    pub id: String,
    /// The card's name; empty for the computer's own audio, which Teams
    /// calls "PC Mic and Speakers".
    pub label: String,
    /// The computer's built-in audio.
    pub internal: bool,
    /// The microphone's and the speaker's names (as `audio::list_devices`).
    pub mic: String,
    pub speaker: String,
}

/// An endpoint PipeWire lists: its device id, whether it's a speaker, and
/// its description.
#[derive(Debug, Clone)]
pub struct Endpoint {
    pub device: String,
    pub sink: bool,
    pub description: String,
}

/// A card PipeWire lists: its id, its name (`device.name`, such as
/// `alsa_card.pci-0000_00_1f.3`) and its description.
#[derive(Debug, Clone, Default)]
pub struct Card {
    pub id: String,
    pub name: String,
    pub description: String,
}

/// The audio devices: every card with a microphone and a speaker.
pub fn device_groups() -> Vec<DeviceGroup> {
    let Some((endpoints, cards)) = query_cards() else {
        return Vec::new();
    };
    group_devices(&endpoints, &cards)
}

/// Pair each card's first microphone with its first speaker, in the order
/// PipeWire lists the cards.
pub fn group_devices(endpoints: &[Endpoint], cards: &[Card]) -> Vec<DeviceGroup> {
    cards
        .iter()
        .filter_map(|c| {
            let first = |sink: bool| {
                endpoints
                    .iter()
                    .find(|e| e.device == c.id && e.sink == sink)
                    .map(|e| e.description.clone())
            };
            let (mic, speaker) = (first(false)?, first(true)?);
            // The computer's own audio: a card on its PCI bus or its
            // system-on-chip (USB and Bluetooth cards are add-ons).
            let internal =
                c.name.starts_with("alsa_card.pci-") || c.name.starts_with("alsa_card.platform-");
            Some(DeviceGroup {
                id: c.id.clone(),
                label: if internal {
                    String::new()
                } else {
                    c.description.clone()
                },
                internal,
                mic,
                speaker,
            })
        })
        .collect()
}

fn query_cards() -> Option<(Vec<Endpoint>, Vec<Card>)> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None).ok()?;
    let context = pw::context::ContextRc::new(&mainloop, None).ok()?;
    let core = context.connect_rc(None).ok()?;
    let registry = core.get_registry_rc().ok()?;
    let endpoints: Rc<RefCell<Vec<Endpoint>>> = Rc::default();
    let cards: Rc<RefCell<Vec<Card>>> = Rc::default();
    let pending = core.sync(0).ok()?;
    let _core_listener = core
        .add_listener_local()
        .done({
            let mainloop = mainloop.clone();
            move |id, seq| {
                if id == pw::core::PW_ID_CORE && seq == pending {
                    mainloop.quit();
                }
            }
        })
        .register();
    let _registry_listener = registry
        .add_listener_local()
        .global({
            let endpoints = endpoints.clone();
            let cards = cards.clone();
            move |global| {
                let Some(props) = global.props else { return };
                let get = |k: &str| props.get(k).unwrap_or_default().to_string();
                match global.type_ {
                    ObjectType::Node => {
                        let class = get(*pw::keys::MEDIA_CLASS);
                        let device = get("device.id");
                        let description = get(*pw::keys::NODE_DESCRIPTION);
                        if (class == "Audio/Sink" || class == "Audio/Source")
                            && !device.is_empty()
                            && !description.is_empty()
                        {
                            endpoints.borrow_mut().push(Endpoint {
                                device,
                                sink: class == "Audio/Sink",
                                description,
                            });
                        }
                    }
                    ObjectType::Device if get(*pw::keys::MEDIA_CLASS) == "Audio/Device" => {
                        cards.borrow_mut().push(Card {
                            id: global.id.to_string(),
                            name: get("device.name"),
                            description: get("device.description"),
                        });
                    }
                    _ => {}
                }
            }
        })
        .register();
    mainloop.run();
    let e = endpoints.borrow().clone();
    let c = cards.borrow().clone();
    Some((e, c))
}

/// The node name in a default-device value: `{"name":"alsa_output…"}`.
fn node_name_of(value: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(value)
        .ok()?
        .get("name")?
        .as_str()
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    #[test]
    fn cards_with_a_mic_and_a_speaker_are_devices() {
        use super::{Card, Endpoint};
        let ep = |d: &str, sink: bool, n: &str| Endpoint {
            device: d.into(),
            sink,
            description: n.into(),
        };
        let card = |id: &str, name: &str, n: &str| Card {
            id: id.into(),
            name: name.into(),
            description: n.into(),
        };
        // linuxlt (2026-11-27): the laptop's audio, a capture card with
        // only a microphone, and a USB headset.
        let endpoints = [
            ep("60", true, "Built-in Audio Analog Stereo"),
            ep("60", false, "Built-in Audio Analog Stereo"),
            ep("90", false, "USB Video Analog Stereo"),
            ep("95", false, "Jabra Evolve2 65 Mono"),
            ep("95", true, "Jabra Evolve2 65 Analog Stereo"),
        ];
        let cards = [
            card("60", "alsa_card.pci-0000_00_1f.3", "Built-in Audio"),
            card("90", "alsa_card.usb-MACROSILICON_USB_Video-02", "USB Video"),
            card(
                "95",
                "alsa_card.usb-GN_Netcom_A_S_Jabra_EVOLVE2_65-00",
                "Jabra Evolve2 65",
            ),
        ];
        let g = super::group_devices(&endpoints, &cards);
        assert_eq!(g.len(), 2);
        assert!(g[0].internal && g[0].label.is_empty());
        assert_eq!(
            (g[0].mic.as_str(), g[0].speaker.as_str()),
            (
                "Built-in Audio Analog Stereo",
                "Built-in Audio Analog Stereo"
            )
        );
        assert_eq!(
            (g[1].label.as_str(), g[1].internal),
            ("Jabra Evolve2 65", false)
        );
        assert_eq!(g[1].mic, "Jabra Evolve2 65 Mono");
    }

    #[test]
    fn default_values_name_the_node() {
        assert_eq!(
            super::node_name_of(r#"{"name":"alsa_output.pci-0000_00_1f.3.analog-stereo"}"#)
                .as_deref(),
            Some("alsa_output.pci-0000_00_1f.3.analog-stereo")
        );
        assert_eq!(super::node_name_of("not json"), None);
    }
}
