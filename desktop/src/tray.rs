//! OST's tray icon and menu, as Teams' notification-area icon offers them:
//! the logo with your presence badge, and a menu with your name and
//! organisation, your status (and the statuses to set), Help › Collect
//! Support Files, and Quit OST — the only real quit. It is a freedesktop
//! StatusNotifierItem with a DBus menu (ksni), which Plasma, waybar and
//! GNOME's AppIndicator host all show.

use ksni::menu::{StandardItem, SubMenu};
use ksni::{Icon, MenuItem, ToolTip, Tray, TrayMethods};
use tokio::sync::mpsc::UnboundedSender;

/// What the tray asks the app to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Bring the window back (the icon's click, or the name row).
    Show,
    /// Set your status (Teams' availability key, or "Reset").
    Status(&'static str),
    CollectSupportFiles,
    Quit,
}

/// The tray icon per presence: the logo with Teams' badge (make.py).
fn tray_png(kind: &str) -> &'static [u8] {
    match kind {
        "available" => include_bytes!("../assets/tray/ost-available.png"),
        "away" => include_bytes!("../assets/tray/ost-away.png"),
        "busy" => include_bytes!("../assets/tray/ost-busy.png"),
        "dnd" => include_bytes!("../assets/tray/ost-dnd.png"),
        "oof" => include_bytes!("../assets/tray/ost-oof.png"),
        "offline" => include_bytes!("../assets/tray/ost-offline.png"),
        _ => include_bytes!("../assets/tray/ost-unknown.png"),
    }
}

/// The menu's presence icons (coloured; a DBus menu can't tint).
fn presence_png(kind: &str) -> &'static [u8] {
    match kind {
        "available" => include_bytes!("../assets/tray/presence-available-16.png"),
        "away" => include_bytes!("../assets/tray/presence-away-16.png"),
        "busy" => include_bytes!("../assets/tray/presence-busy-16.png"),
        "dnd" => include_bytes!("../assets/tray/presence-dnd-16.png"),
        "oof" => include_bytes!("../assets/tray/presence-oof-16.png"),
        "offline" => include_bytes!("../assets/tray/presence-offline-16.png"),
        _ => include_bytes!("../assets/tray/presence-unknown-16.png"),
    }
}

const RESET_PNG: &[u8] = include_bytes!("../assets/tray/reset-16.png");

/// A PNG as the StatusNotifierItem pixmap: ARGB32, big-endian.
fn pixmap(png_bytes: &[u8]) -> Option<Icon> {
    let mut decoder = png::Decoder::new(std::io::Cursor::new(png_bytes));
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().ok()?;
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).ok()?;
    let rgba: Vec<u8> = match info.color_type {
        png::ColorType::Rgba => buf[..info.buffer_size()].to_vec(),
        png::ColorType::Rgb => buf[..info.buffer_size()]
            .chunks(3)
            .flat_map(|p| [p[0], p[1], p[2], 255])
            .collect(),
        _ => return None,
    };
    let data = rgba
        .chunks(4)
        .flat_map(|p| [p[3], p[0], p[1], p[2]])
        .collect();
    Some(Icon {
        width: info.width as i32,
        height: info.height as i32,
        data,
    })
}

/// The tray's state.
pub struct OstTray {
    /// "Name | Organisation".
    pub name_line: String,
    /// Presence kind: available, away, busy, dnd, oof, offline, unknown.
    pub kind: String,
    /// Your status as the menu names it ("Available", "In a meeting"…).
    pub status_label: String,
    actions: UnboundedSender<Action>,
}

impl OstTray {
    pub fn new(actions: UnboundedSender<Action>) -> Self {
        Self {
            name_line: String::new(),
            kind: "unknown".into(),
            status_label: String::new(),
            actions,
        }
    }

    fn send(&self, a: Action) {
        let _ = self.actions.send(a);
    }
}

/// A menu row that sends `action`.
fn item(label: &str, icon: &[u8], action: Action) -> MenuItem<OstTray> {
    StandardItem {
        label: label.replace('_', "__"),
        icon_data: icon.to_vec(),
        activate: Box::new(move |t: &mut OstTray| t.send(action.clone())),
        ..Default::default()
    }
    .into()
}

impl Tray for OstTray {
    fn id(&self) -> String {
        "ost-desktop".into()
    }

    fn title(&self) -> String {
        "OST".into()
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        pixmap(tray_png(&self.kind)).into_iter().collect()
    }

    fn tool_tip(&self) -> ToolTip {
        ToolTip {
            title: "OST".into(),
            ..Default::default()
        }
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        self.send(Action::Show);
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let statuses: [(&str, &str, &'static str); 6] = [
            ("Available", "available", "Available"),
            ("Busy", "busy", "Busy"),
            ("Do not disturb", "dnd", "DoNotDisturb"),
            ("Be right back", "away", "BeRightBack"),
            ("Appear away", "away", "Away"),
            ("Appear offline", "offline", "Offline"),
        ];
        let mut status_rows: Vec<MenuItem<Self>> = statuses
            .iter()
            .map(|(label, kind, key)| item(label, presence_png(kind), Action::Status(key)))
            .collect();
        status_rows.push(MenuItem::Separator);
        status_rows.push(item("Reset Status", RESET_PNG, Action::Status("Reset")));
        vec![
            item(&self.name_line, tray_png(&self.kind), Action::Show),
            SubMenu {
                label: self.status_label.replace('_', "__"),
                icon_data: presence_png(&self.kind).to_vec(),
                submenu: status_rows,
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            SubMenu {
                label: "Help".into(),
                submenu: vec![item(
                    "Collect Support Files",
                    &[],
                    Action::CollectSupportFiles,
                )],
                ..Default::default()
            }
            .into(),
            item("Quit OST", &[], Action::Quit),
        ]
    }
}

/// Start the tray; it lives until the process ends.
pub async fn spawn(tray: OstTray) -> Option<ksni::Handle<OstTray>> {
    match tray.spawn().await {
        Ok(h) => Some(h),
        Err(e) => {
            tracing::warn!("No system tray: {e}");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tray_icons_decode_to_argb() {
        let icon = pixmap(tray_png("busy")).expect("decodes");
        assert_eq!((icon.width, icon.height), (64, 64));
        assert_eq!(icon.data.len(), 64 * 64 * 4);
        assert!(pixmap(presence_png("available")).is_some());
    }

    #[test]
    fn the_menu_is_teams_tray_menu() {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let mut t = OstTray::new(tx);
        t.name_line = "OST Test 1 | Secure Coast".into();
        t.kind = "busy".into();
        t.status_label = "In a meeting".into();
        let menu = t.menu();
        let label = |m: &MenuItem<OstTray>| match m {
            MenuItem::Standard(s) => s.label.clone(),
            MenuItem::SubMenu(s) => s.label.clone(),
            MenuItem::Separator => "-".into(),
            _ => "?".into(),
        };
        let labels: Vec<String> = menu.iter().map(label).collect();
        assert_eq!(
            labels,
            [
                "OST Test 1 | Secure Coast",
                "In a meeting",
                "-",
                "Help",
                "Quit OST"
            ]
        );
        if let MenuItem::SubMenu(s) = &menu[1] {
            let names: Vec<String> = s.submenu.iter().map(label).collect();
            assert_eq!(names.len(), 8);
            assert_eq!(names[2], "Do not disturb");
            if let MenuItem::Standard(dnd) = &s.submenu[2] {
                (dnd.activate)(&mut t);
            }
        }
        assert_eq!(rx.try_recv().unwrap(), Action::Status("DoNotDisturb"));
    }
}
