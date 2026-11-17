//! Presenting as Teams (TASK-0210; docs/spec/call-and-meeting-window.md
//! §9–10): presenter modes and Add background, Give control and Take
//! control, and what the Sharing control bar does (Share sound, Optimize,
//! Layout). The call window shows it from `call_presenting_json`:
//!
//! `{mode, background, optimize, control: {capable, deniedBySharer,
//! state, controller, request, controllable}}`, where `state` is "none",
//! "requested" (we asked), "controlling" (we control their screen) or
//! "controlled" (someone controls ours), and the people are MRIs.

use super::*;
use teams_cli::calling::meeting_media::ControlCommand;
use teams_cli::calling::presenter_mode::{Background, Mode, Published};

/// What the call window shows of presenting.
#[derive(Default)]
pub struct Presenting {
    /// Our presenter mode (chosen in the tray before sharing, or with
    /// the bar's Layout while sharing).
    pub mode: Mode,
    /// Add background's picture for Side-by-side and Reporter.
    pub background: Option<Background>,
    /// Optimize for video content.
    pub optimize: bool,
    /// What we shared (the remote control portal offers the same).
    pub kind: Option<teams_cli::calling::screencast::Source>,
    /// The mode published for this share.
    pub published: Mode,
    pub control: Control,
}

#[derive(Default, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Control {
    pub capable: bool,
    pub denied_by_sharer: bool,
    pub state: String,
    pub controller: String,
    pub request: String,
    pub controllable: Vec<String>,
}

/// The remote control portal's session while someone controls our screen:
/// the controller's events, in order.
fn injector() -> &'static std::sync::Mutex<Option<tokio::sync::mpsc::UnboundedSender<Vec<u8>>>> {
    static I: std::sync::Mutex<Option<tokio::sync::mpsc::UnboundedSender<Vec<u8>>>> = std::sync::Mutex::new(None);
    &I
}

/// Start the injector (the portal asks the person once) unless running.
fn start_injector(kind: teams_cli::calling::screencast::Source) {
    let mut slot = injector().lock().unwrap_or_else(|e| e.into_inner());
    if slot.is_some() {
        return;
    }
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
    *slot = Some(tx);
    runtime().spawn(async move {
        let mut inj = match teams_cli::calling::remote_input::Injector::start(kind).await {
            Ok(i) => i,
            Err(e) => {
                tracing::warn!("remote control: {}", short_error(&e));
                *injector().lock().unwrap_or_else(|e| e.into_inner()) = None;
                return;
            }
        };
        while let Some(bytes) = rx.recv().await {
            if let Err(e) = inj.inject(&bytes).await {
                tracing::debug!("remote control input: {}", short_error(&e));
            }
        }
        inj.stop().await;
        tracing::info!("remote control session ended");
    });
}

fn stop_injector() {
    *injector().lock().unwrap_or_else(|e| e.into_inner()) = None;
}

/// The controller's event for the injector (dropped until it's ready).
pub fn control_input(bytes: Vec<u8>) {
    if let Some(tx) = injector().lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
        let _ = tx.send(bytes);
    }
}

/// Tell the meeting's media control plane, in order (keys and clicks
/// must reach the presenter as they were made).
fn command(c: ControlCommand) {
    static QUEUE: std::sync::OnceLock<tokio::sync::mpsc::UnboundedSender<ControlCommand>> = std::sync::OnceLock::new();
    let tx = QUEUE.get_or_init(|| {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<ControlCommand>();
        runtime().spawn(async move {
            while let Some(c) = rx.recv().await {
                if let Some(call) = call_slot().lock().await.outgoing.as_ref() {
                    call.screen_control(c);
                }
            }
        });
        tx
    });
    let _ = tx.send(c);
}

/// Publish (or take back) our presenter mode for this share.
fn publish(mode: Mode, background: Option<Background>) {
    ost_vfx::set_presenter_mask(mode.cuts_background());
    runtime().spawn(async move {
        let layout = (mode != Mode::ContentOnly)
            .then(|| serde_json::to_value(Published::initial(mode, background)).unwrap_or_default());
        let mut slot = call_slot().lock().await;
        let Some(call) = slot.outgoing.as_mut() else { return };
        if let Err(e) = call.weather_person(layout).await {
            tracing::warn!("presenter mode: {}", short_error(&e));
        } else {
            tracing::info!(?mode, "presenter mode published");
        }
    });
}

/// The MRIs whose data sources are in `sources`.
fn mris(roster: &[teams_cli::calling::roster::Participant], sources: &[u32]) -> Vec<String> {
    roster
        .iter()
        .filter(|p| p.data_sources.iter().chain(p.share_data_source.iter()).any(|d| sources.contains(&(*d as u32))))
        .map(|p| p.id.clone())
        .collect()
}

/// A participant's data source for give / take control.
fn source_of(roster: &[teams_cli::calling::roster::Participant], mri: &str) -> Option<u32> {
    let p = roster.iter().find(|p| p.id.eq_ignore_ascii_case(mri))?;
    p.share_data_source.or_else(|| p.data_sources.first().copied()).map(|s| s as u32)
}

impl qobject::Backend {
    fn show_presenting(mut self: Pin<&mut Self>) {
        let p = &self.rust().presenting;
        let mode = match p.mode {
            Mode::ContentOnly => "ContentOnly",
            Mode::Weatherperson => "Weatherperson",
            Mode::SideBySide => "SideBySide",
            Mode::NewsAnchor => "NewsAnchor",
        };
        let json = serde_json::json!({
            "mode": mode,
            "background": p.background,
            "optimize": p.optimize,
            "control": p.control,
        })
        .to_string();
        if self.rust().call_presenting_json.to_string() != json {
            self.as_mut().set_call_presenting_json(QString::from(json.as_str()));
        }
    }

    /// Tray Presenter mode, or the bar's Layout: Teams' setSharingLayoutMode.
    pub fn set_presenter_mode(mut self: Pin<&mut Self>, mode: &QString) {
        let mode = Mode::parse(&mode.to_string());
        self.as_mut().rust_mut().presenting.mode = mode;
        if self.rust().call_sharing && self.rust().presenting.published != mode {
            self.as_mut().rust_mut().presenting.published = mode;
            let bg = self.rust().presenting.background.clone();
            publish(mode, bg);
            // Side-by-side and Reporter can't be controlled (Teams:
            // "Unavailable with this layout.").
        }
        self.show_presenting();
    }

    /// Add background: `{id, url, name}` (or empty for none).
    pub fn set_presenter_background(mut self: Pin<&mut Self>, json: &QString) {
        let bg: Option<Background> = serde_json::from_str(&json.to_string()).ok().filter(|b: &Background| !b.id.is_empty());
        self.as_mut().rust_mut().presenting.background = bg.clone();
        let mode = self.rust().presenting.published;
        if self.rust().call_sharing && mode.takes_background() {
            publish(mode, bg);
        }
        self.show_presenting();
    }

    /// Optimize for video content: the screen at a video's frame rate.
    pub fn set_share_optimize(mut self: Pin<&mut Self>, on: bool) {
        self.as_mut().rust_mut().presenting.optimize = on;
        teams_cli::calling::webrtc_video::set_screen_motion(on);
        self.show_presenting();
    }

    /// The call window saw sharing start or stop: tell the control plane,
    /// publish the chosen mode (Teams' startSharing with its layout), and
    /// take it all back when it stops.
    pub fn presenting_sharing_changed(mut self: Pin<&mut Self>) {
        let on = self.rust().call_sharing;
        if on {
            let mode = self.rust().presenting.mode;
            let mode = if self.rust().call_camera_on { mode } else { Mode::ContentOnly };
            self.as_mut().rust_mut().presenting.published = mode;
            if mode != Mode::ContentOnly {
                publish(mode, self.rust().presenting.background.clone());
            }
            // A screen can be controlled. A window can't: the
            // desktop's remote control portal moves the pointer over the
            // whole screen, and nothing tells an app where the shared
            // window is, so the controller's clicks would land elsewhere.
            let whole_screen = self.rust().presenting.kind == Some(teams_cli::calling::screencast::Source::Screen);
            runtime().spawn(async move {
                let enabled = whole_screen && teams_cli::calling::remote_input::available().await;
                tracing::info!(enabled, "sharing: give control");
                command(ControlCommand::Sharing { on: true, enabled });
            });
        } else {
            if self.rust().presenting.published != Mode::ContentOnly {
                publish(Mode::ContentOnly, None);
            }
            ost_vfx::set_presenter_mask(false);
            self.as_mut().rust_mut().presenting.published = Mode::ContentOnly;
            self.as_mut().rust_mut().presenting.mode = Mode::ContentOnly;
            command(ControlCommand::Sharing { on: false, enabled: false });
            stop_injector();
            teams_cli::calling::webrtc_video::set_screen_motion(false);
            self.as_mut().rust_mut().presenting.optimize = false;
            let mut rust = self.as_mut().rust_mut();
            let c = &mut rust.presenting.control;
            c.controllable.clear();
            c.request.clear();
            if c.state == "controlled" {
                c.state = "none".into();
                c.controller.clear();
            }
        }
        self.show_presenting();
    }

    /// The camera went off: the camera modes stop (Teams' "presenter video
    /// stopped": back to Content only).
    pub fn presenting_camera_changed(mut self: Pin<&mut Self>) {
        if !self.rust().call_camera_on && self.rust().presenting.mode != Mode::ContentOnly {
            let mode = QString::from("ContentOnly");
            self.as_mut().set_presenter_mode(&mode);
        }
    }

    /// Give / take control from the call window: "request", "cancel",
    /// "release" (viewer); "accept", "deny", "give" (`arg`: their MRI),
    /// "takeBack" (sharer).
    pub fn screen_control(mut self: Pin<&mut Self>, action: &QString, arg: &QString) {
        let c = match action.to_string().as_str() {
            "request" => {
                self.as_mut().rust_mut().presenting.control.state = "requested".into();
                ControlCommand::Request
            }
            "cancel" => {
                self.as_mut().rust_mut().presenting.control.state = "none".into();
                ControlCommand::CancelRequest
            }
            "release" | "takeBack" => ControlCommand::Terminate,
            "accept" => {
                if let Some(kind) = self.rust().presenting.kind {
                    start_injector(kind);
                }
                self.as_mut().rust_mut().presenting.control.request.clear();
                ControlCommand::Accept
            }
            "deny" => {
                self.as_mut().rust_mut().presenting.control.request.clear();
                ControlCommand::Deny
            }
            "give" => {
                let Some(to) = source_of(&self.rust().roster, &arg.to_string()) else {
                    tracing::warn!("give control: no data source for them");
                    return;
                };
                if let Some(kind) = self.rust().presenting.kind {
                    start_injector(kind);
                }
                ControlCommand::Give(to)
            }
            other => {
                tracing::warn!(other, "screen control: unknown action");
                return;
            }
        };
        command(c);
        self.show_presenting();
    }

    /// The viewer's mouse over the shared screen while in control: `kind`
    /// 0 move, 1 wheel, 2 button; `x`, `y` from 0 to 1 over the picture.
    pub fn control_mouse(self: Pin<&mut Self>, kind: i32, button: i32, down: bool, x: f64, y: f64, wheel: i32) {
        if self.rust().presenting.control.state != "controlling" {
            return;
        }
        let e = teams_cli::calling::screen_control::MouseEvent {
            kind: kind as u8,
            button: button as u8,
            down,
            x: (x.clamp(0.0, 1.0) * 65535.0).round() as u16,
            y: (y.clamp(0.0, 1.0) * 65535.0).round() as u16,
            wheel: wheel.clamp(-120, 120) as i8,
        };
        command(ControlCommand::Input(e.encode()));
    }

    /// The viewer's key while in control (Qt key and native scan code).
    pub fn control_key(self: Pin<&mut Self>, key: i32, scan_code: u32, up: bool, repeat: bool) {
        if self.rust().presenting.control.state != "controlling" {
            return;
        }
        let Some(code) = teams_cli::calling::screen_control::keys::vk_from_qt(key, scan_code) else {
            return;
        };
        let e = teams_cli::calling::screen_control::KeyEvent { code, up, repeat };
        command(ControlCommand::Input(e.encode()));
    }

    /// Where a receiver draws a presenter's mode: Teams' compositor
    /// arithmetic for the published `layout` on a `w` x `h` stage.
    pub fn presenter_layout(&self, layout: &QString, w: f64, h: f64, content_aspect: f64, presenter_aspect: f64) -> QString {
        let Ok(p) = serde_json::from_str::<Published>(&layout.to_string()) else {
            return QString::default();
        };
        let c = teams_cli::calling::presenter_mode::composite(
            &p,
            (w.max(1.0), h.max(1.0)),
            (content_aspect > 0.0).then_some(content_aspect),
            (presenter_aspect > 0.0).then_some(presenter_aspect),
        );
        QString::from(serde_json::to_string(&c).unwrap_or_default().as_str())
    }

    /// A give / take control event from the control plane
    /// (`ost/screenControl/`'s body).
    pub(super) fn screen_control_event(mut self: Pin<&mut Self>, body: serde_json::Value) {
        let roster = self.rust().roster.clone();
        let src = |v: &serde_json::Value| v.as_u64().map(|s| s as u32);
        let who = |s: Option<u32>| s.map(|s| mris(&roster, &[s]).into_iter().next().unwrap_or_default()).unwrap_or_default();
        let kind = body.get("type").and_then(|t| t.as_str()).unwrap_or_default().to_string();
        let mut notice: Option<(String, String)> = None;
        {
            let mut rust = self.as_mut().rust_mut();
            let c = &mut rust.presenting.control;
            match kind.as_str() {
                "capable" => {
                    c.capable = body["capable"].as_bool().unwrap_or(false);
                    c.denied_by_sharer = body["deniedBySharer"].as_bool().unwrap_or(false);
                }
                "controllable" => {
                    let list: Vec<u32> = body["sources"].as_array().into_iter().flatten().filter_map(src).collect();
                    c.controllable = mris(&roster, &list);
                }
                "request" => {
                    c.request = who(src(&body["source"]));
                    notice = Some(("request".into(), c.request.clone()));
                }
                "withdrawn" => {
                    let w = who(src(&body["source"]));
                    if c.request == w {
                        c.request.clear();
                    }
                    notice = Some(("withdrawn".into(), w));
                }
                "changed" => {
                    let in_control = body["inControl"].as_bool().unwrap_or(false);
                    let reason = body["reason"].as_u64().unwrap_or(0) as u8;
                    let controller = who(src(&body["controller"]));
                    let was = c.state.clone();
                    if body["controller"].is_null() {
                        // Ours: we control the presenter's screen, or not.
                        c.state = if in_control { "controlling" } else { "none" }.into();
                        let n = if in_control {
                            "given"
                        } else if reason == teams_cli::calling::screen_control::reason::SHARER_TERMINATED {
                            "takenBack"
                        } else {
                            "stopped"
                        };
                        notice = Some((n.into(), String::new()));
                    } else {
                        c.state = if in_control { "controlled" } else { "none" }.into();
                        c.controller = if in_control { controller.clone() } else { String::new() };
                        notice = Some((if in_control { "hasControl" } else { "controlEnded" }.into(), controller));
                    }
                    tracing::info!(was, now = %c.state, reason, "screen control changed");
                }
                "failed" => {
                    let reason = body["reason"].as_u64().unwrap_or(0) as u8;
                    c.state = "none".into();
                    if reason != teams_cli::calling::screen_control::reason::VIEWER_CANCELLED {
                        notice = Some(("denied".into(), String::new()));
                    }
                }
                _ => {}
            }
        }
        self.as_mut().show_presenting();
        if let Some((kind, mri)) = notice {
            let name = roster.iter().find(|p| p.id == mri).map(|p| p.name.clone()).unwrap_or_default();
            self.as_mut().screen_control_notice(QString::from(kind.as_str()), QString::from(mri.as_str()), QString::from(name.as_str()));
        }
    }

    /// The roster changed: who we watch (the presenter's data source),
    /// who left, and whose camera carries an implicit mask.
    pub(super) fn presenting_roster(
        self: Pin<&mut Self>,
        left: &[teams_cli::calling::roster::Participant],
        presenter: Option<&teams_cli::calling::roster::Participant>,
    ) {
        let gone: Vec<u32> = left.iter().flat_map(|p| p.data_sources.iter().map(|d| *d as u32)).collect();
        if !gone.is_empty() {
            command(ControlCommand::Left(gone));
        }
        let viewing = presenter.and_then(|p| p.share_data_source.or_else(|| p.data_sources.first().copied())).map(|s| s as u32);
        if self.rust().presenting_viewing != viewing {
            self.rust_mut().presenting_viewing = viewing;
            tracing::info!(?viewing, "screen control: watching");
            command(ControlCommand::Viewing(viewing));
        }
    }
}
