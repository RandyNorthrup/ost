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
                        if class == "Audio/Sink" || class == "Audio/Source" {
                            if let (Some(name), Some(desc)) = (
                                props.get(*pw::keys::NODE_NAME),
                                props.get(*pw::keys::NODE_DESCRIPTION),
                            ) {
                                names
                                    .borrow_mut()
                                    .insert(name.to_string(), desc.to_string());
                            }
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
    fn default_values_name_the_node() {
        assert_eq!(
            super::node_name_of(r#"{"name":"alsa_output.pci-0000_00_1f.3.analog-stereo"}"#)
                .as_deref(),
            Some("alsa_output.pci-0000_00_1f.3.analog-stereo")
        );
        assert_eq!(super::node_name_of("not json"), None);
    }
}
