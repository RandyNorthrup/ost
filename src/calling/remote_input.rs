//! Give control, the sharer's side: the controller's mouse and keys
//! ([`super::screen_control`]'s data-id-2 events) played into this desktop
//! through the desktop's RemoteDesktop portal, which asks the person once
//! to allow it and to pick the screen or window being controlled (Wayland
//! lets no app move the pointer on its own). Teams' Windows injector does
//! the same with SendInput; its virtual-key codes are mapped to evdev
//! codes here.

use anyhow::{Context, Result};
use ashpd::desktop::PersistMode;
use ashpd::desktop::remote_desktop::{Axis, DeviceType, KeyState, RemoteDesktop, SelectDevicesOptions};
use ashpd::desktop::screencast::{Screencast, SelectSourcesOptions, SourceType};

use super::screen_control::keys::evdev_from_vk;
use super::screen_control::{KeyEvent, MouseEvent, mouse};
use super::screencast::Source;

/// A RemoteDesktop session: input goes to its stream (the shared screen
/// or window, as picked in the portal).
pub struct Injector {
    proxy: RemoteDesktop,
    session: ashpd::desktop::Session<RemoteDesktop>,
    stream: u32,
    size: (f64, f64),
    /// Buttons held down, released if control ends mid-drag.
    held: Vec<i32>,
    keys: Vec<i32>,
    keys_injected: u64,
}

/// Whether the desktop can let us take input (a RemoteDesktop portal
/// with a pointer and a keyboard).
pub async fn available() -> bool {
    match RemoteDesktop::new().await {
        Ok(p) => p
            .available_device_types()
            .await
            .is_ok_and(|t| t.contains(DeviceType::POINTER | DeviceType::KEYBOARD)),
        Err(_) => false,
    }
}

const BTN_LEFT: i32 = 0x110;
const BTN_RIGHT: i32 = 0x111;
const BTN_MIDDLE: i32 = 0x112;

impl Injector {
    /// Ask the desktop (its portal dialog) to allow control of what we
    /// share: `kind` offers the same choice as the share did.
    pub async fn start(kind: Source) -> Result<Self> {
        let proxy = RemoteDesktop::new().await.context("The desktop's remote control portal isn't available")?;
        let screencast = Screencast::new().await?;
        let session = proxy.create_session(Default::default()).await?;
        proxy
            .select_devices(
                &session,
                SelectDevicesOptions::default()
                    .set_devices(DeviceType::KEYBOARD | DeviceType::POINTER)
                    .set_persist_mode(PersistMode::DoNot),
            )
            .await?
            .response()
            .context("The remote control portal refused the request")?;
        let sources = match kind {
            Source::Screen => SourceType::MONITOR.into(),
            Source::Window => SourceType::WINDOW.into(),
            Source::Any => SourceType::MONITOR | SourceType::WINDOW,
        };
        screencast
            .select_sources(
                &session,
                SelectSourcesOptions::default().set_sources(sources).set_multiple(false),
            )
            .await?
            .response()
            .context("The remote control portal refused the screen")?;
        let started = proxy
            .start(&session, None, Default::default())
            .await?
            .response()
            .context("Control wasn't allowed")?;
        let stream = started.streams().first().context("Nothing was picked to control")?;
        let size = stream.size().map_or((1920.0, 1080.0), |(w, h)| (w as f64, h as f64));
        tracing::info!(node = stream.pipe_wire_node_id(), ?size, devices = ?started.devices(), "remote control allowed");
        Ok(Self { proxy, stream: stream.pipe_wire_node_id(), size, session, held: Vec::new(), keys: Vec::new(), keys_injected: 0 })
    }

    /// Play one of the controller's events.
    pub async fn inject(&mut self, bytes: &[u8]) -> Result<()> {
        if let Some(m) = MouseEvent::decode(bytes) {
            return self.mouse(m).await;
        }
        if let Some(k) = KeyEvent::decode(bytes) {
            return self.key(k).await;
        }
        Ok(())
    }

    async fn mouse(&mut self, m: MouseEvent) -> Result<()> {
        let s = &self.session;
        match m.kind {
            mouse::WHEEL => {
                // Teams: +120 a notch up; the portal's steps go down.
                let steps = -(m.wheel as i32) / 120;
                if steps != 0 {
                    self.proxy.notify_pointer_axis_discrete(s, Axis::Vertical, steps, Default::default()).await?;
                }
            }
            kind => {
                let (x, y) = (m.x as f64 / 65535.0 * self.size.0, m.y as f64 / 65535.0 * self.size.1);
                self.proxy.notify_pointer_motion_absolute(s, self.stream, x, y, Default::default()).await?;
                if kind == mouse::BUTTON {
                    let button = match m.button {
                        mouse::RIGHT => BTN_RIGHT,
                        mouse::MIDDLE => BTN_MIDDLE,
                        _ => BTN_LEFT,
                    };
                    let state = if m.down { KeyState::Pressed } else { KeyState::Released };
                    self.proxy.notify_pointer_button(s, button, state, Default::default()).await?;
                    if m.down {
                        self.held.push(button);
                    } else {
                        self.held.retain(|b| *b != button);
                    }
                }
            }
        }
        Ok(())
    }

    async fn key(&mut self, k: KeyEvent) -> Result<()> {
        let Some(code) = evdev_from_vk(k.code) else {
            tracing::debug!(vk = k.code, "remote control: no key for this code");
            return Ok(());
        };
        let state = if k.up { KeyState::Released } else { KeyState::Pressed };
        self.proxy.notify_keyboard_keycode(&self.session, code, state, Default::default()).await?;
        // How many went in (not which: a controller may type a password).
        self.keys_injected += 1;
        if self.keys_injected <= 40 || self.keys_injected.is_multiple_of(50) {
            tracing::info!(count = self.keys_injected, "remote control: key played");
        }
        if k.up {
            self.keys.retain(|c| *c != code);
        } else if !self.keys.contains(&code) {
            self.keys.push(code);
        }
        Ok(())
    }

    /// Control ended: let go of anything held, and end the session.
    pub async fn stop(mut self) {
        for b in std::mem::take(&mut self.held) {
            let _ = self.proxy.notify_pointer_button(&self.session, b, KeyState::Released, Default::default()).await;
        }
        for c in std::mem::take(&mut self.keys) {
            let _ = self.proxy.notify_keyboard_keycode(&self.session, c, KeyState::Released, Default::default()).await;
        }
        let _ = self.session.close().await;
    }
}
