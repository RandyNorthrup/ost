//! The unread count on OST's taskbar entry where the desktop draws app
//! badges itself: the Unity launcher API (`com.canonical.Unity.LauncherEntry`),
//! which KDE Plasma's task manager, Ubuntu's dock and GNOME's Dash to
//! Dock show as a count on the app's button. It carries Teams' taskbar
//! count (the app bar's unread total); the window icon carries Teams' full
//! overlay for taskbars that show window icons (src/native.cpp).
//!
//! As other apps do, OST sends the `Update` signal whenever the count
//! changes and answers `Query` (the current count) on the same object, so
//! a dock started after OST shows it too.
//!
//! The desktop matches the signal's `application://<id>.desktop` to an
//! installed desktop entry (Plasma's task manager drops it with "Failed to
//! find service for Unity Launcher" otherwise). OST's packages install
//! one; an OST run from a tarball, an AppImage or a build folder has none,
//! so OST writes its own entry (and icon) for the current user then, as
//! Telegram's portable build does ([`register_desktop_entry`]).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI64, Ordering};
use zbus::zvariant::{OwnedValue, Value};

const APP_ID: &str = "io.github.RandyNorthrup.ost";
const APP_URI: &str = "application://io.github.RandyNorthrup.ost.desktop";
const OBJECT_PATH: &str = "/com/canonical/unity/launcherentry/ost";
const INTERFACE: &str = "com.canonical.Unity.LauncherEntry";
/// Marks an entry OST wrote itself (it may rewrite that one, never another).
const GENERATED_KEY: &str = "X-OST-Generated=true";
/// The app's icon, as the packages install it.
const ICON_PNG: &[u8] = include_bytes!("../packaging/io.github.RandyNorthrup.ost.png");

/// The count last shown (what `Query` answers).
static COUNT: AtomicI64 = AtomicI64::new(0);

/// The launcher entry's properties for `count` (hidden at 0).
fn properties(count: i64) -> HashMap<&'static str, Value<'static>> {
    let mut props = HashMap::new();
    props.insert("count", Value::from(count.max(0)));
    props.insert("count-visible", Value::from(count > 0));
    props
}

/// `com.canonical.Unity.LauncherEntry.Query`: the app's URI and its
/// current properties.
struct Entry;

#[zbus::interface(name = "com.canonical.Unity.LauncherEntry")]
impl Entry {
    fn query(&self) -> (String, HashMap<String, OwnedValue>) {
        let props = properties(COUNT.load(Ordering::Relaxed))
            .into_iter()
            .filter_map(|(k, v)| OwnedValue::try_from(v).ok().map(|v| (k.to_string(), v)))
            .collect();
        (APP_URI.to_string(), props)
    }
}

async fn connection() -> Option<&'static zbus::Connection> {
    static CONN: tokio::sync::OnceCell<Option<zbus::Connection>> =
        tokio::sync::OnceCell::const_new();
    CONN.get_or_init(|| async {
        match zbus::Connection::session().await {
            Ok(c) => {
                if let Err(e) = c.object_server().at(OBJECT_PATH, Entry).await {
                    tracing::debug!("launcher badge: Query not served: {e}");
                }
                Some(c)
            }
            Err(e) => {
                tracing::debug!("launcher badge: no session bus: {e}");
                None
            }
        }
    })
    .await
    .as_ref()
}

async fn emit(count: i64) {
    let Some(conn) = connection().await else {
        return;
    };
    if let Err(e) = conn
        .emit_signal(
            None::<()>,
            OBJECT_PATH,
            INTERFACE,
            "Update",
            &(APP_URI, properties(count)),
        )
        .await
    {
        tracing::debug!("launcher badge: {e}");
    }
}

/// Show `count` on the launcher entry (hidden at 0).
pub async fn update(count: i64) {
    COUNT.store(count.max(0), Ordering::Relaxed);
    emit(count).await;
}

/// Send the current count again (after the desktop learned of a new
/// desktop entry: it ignored the earlier signals).
async fn resend_later() {
    for secs in [5, 20] {
        tokio::time::sleep(std::time::Duration::from_secs(secs)).await;
        emit(COUNT.load(Ordering::Relaxed)).await;
    }
}

/// `$XDG_DATA_HOME` (default ~/.local/share), then `$XDG_DATA_DIRS`
/// (default /usr/local/share:/usr/share), as the XDG base directory
/// specification orders them.
fn data_dirs() -> (Option<PathBuf>, Vec<PathBuf>) {
    let home = std::env::var_os("XDG_DATA_HOME")
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")));
    let dirs = std::env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|d| !d.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".to_string());
    let dirs = dirs
        .split(':')
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .collect();
    (home, dirs)
}

/// The binary a generated entry starts (its `Exec`), read back the way
/// desktop environments read it: the value as a desktop-entry string
/// (`\\` is `\`, `\s` a space…), then its first argument (inside quotes
/// `\x` stands for x), then `%%` for `%`.
fn entry_exec(text: &str) -> Option<PathBuf> {
    let raw = text.lines().find_map(|l| l.strip_prefix("Exec="))?.trim();
    let mut value = String::new();
    let mut chars = raw.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            value.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => value.push(' '),
            Some('n') => value.push('\n'),
            Some('t') => value.push('\t'),
            Some('r') => value.push('\r'),
            Some('\\') => value.push('\\'),
            Some(o) => {
                value.push('\\');
                value.push(o);
            }
            None => value.push('\\'),
        }
    }
    let arg = match value.strip_prefix('"') {
        Some(rest) => {
            let mut arg = String::new();
            let mut chars = rest.chars();
            while let Some(c) = chars.next() {
                match c {
                    '"' => break,
                    '\\' => arg.extend(chars.next()),
                    c => arg.push(c),
                }
            }
            arg
        }
        None => value
            .split_whitespace()
            .next()
            .unwrap_or_default()
            .to_string(),
    };
    let mut path = String::new();
    let mut chars = arg.chars().peekable();
    while let Some(c) = chars.next() {
        path.push(c);
        if c == '%' && chars.peek() == Some(&'%') {
            chars.next();
        }
    }
    (!path.is_empty()).then(|| PathBuf::from(path))
}

/// `exe` as the desktop entry specification has it in `Exec`: quoted, with
/// `"`, `` ` ``, `$` and `\` escaped inside the quotes, then every `\`
/// doubled again because the value is itself an escaped string. None for a
/// path an entry can't hold: not UTF-8, control characters, or `%` (the
/// specification's `%%` launches, but GLib looks for a binary named with
/// the `%%` and drops the entry; a single `%` would be a field code).
fn exec_value(exe: &Path) -> Option<String> {
    let path = exe.to_str()?;
    if path.chars().any(|c| c.is_control() || c == '%') {
        return None;
    }
    let mut arg = String::from("\"");
    for c in path.chars() {
        match c {
            '"' | '`' | '$' | '\\' => {
                arg.push('\\');
                arg.push(c);
            }
            c => arg.push(c),
        }
    }
    arg.push('"');
    Some(arg.replace('\\', "\\\\"))
}

/// The link schemes OST takes (TASK-0369), as the packaged entry's
/// `MimeType` line has them: Teams' own msteams: and web+msteams:.
const MIME_TYPES: &str = "MimeType=x-scheme-handler/msteams;x-scheme-handler/web+msteams;";

/// The desktop entry OST writes for itself: the packaged entry's fields,
/// started with the binary (or AppImage) now running, with `%u` for the
/// Teams link the desktop passes.
fn entry_text(exe: &Path) -> Option<String> {
    let exec = exec_value(exe)?;
    Some(format!(
        "[Desktop Entry]\nType=Application\nName=OST\nGenericName=Team chat and calls\n\
         Comment=Native client for Microsoft Teams chats, calls and meetings\n\
         Exec={exec} %u\nIcon={APP_ID}\nTerminal=false\n\
         Categories=Network;InstantMessaging;Chat;VideoConference;\n\
         {MIME_TYPES}\nStartupWMClass=ost-desktop\n{GENERATED_KEY}\n"
    ))
}

/// What [`register_desktop_entry`] should do, from what is installed.
#[derive(Debug, PartialEq, Eq)]
enum EntryPlan {
    /// An entry is installed (a package's, or OST's own that still works).
    Keep,
    /// Write OST's own entry.
    Write,
}

/// `installed`: the first entry with OST's id in the data directories,
/// with its text. OST writes its own only where there is none, or where
/// the one there is OST's own and its binary is gone (a moved AppImage,
/// a deleted build) or it is from before OST took Teams links.
fn plan(installed: Option<&str>, exe_exists: impl Fn(&Path) -> bool) -> EntryPlan {
    match installed {
        None => EntryPlan::Write,
        Some(text) if text.lines().any(|l| l.trim() == GENERATED_KEY) => match entry_exec(text) {
            Some(p) if exe_exists(&p) && text.lines().any(|l| l.trim() == MIME_TYPES) => {
                EntryPlan::Keep
            }
            _ => EntryPlan::Write,
        },
        Some(_) => EntryPlan::Keep,
    }
}

/// Make sure the desktop has a desktop entry for OST's app id, so its
/// task manager can show the unread badge (and the window its icon): see
/// the module notes. Not inside Flatpak or Snap, whose entries the
/// package exports.
pub fn register_desktop_entry() {
    if std::env::var_os("FLATPAK_ID").is_some()
        || std::env::var_os("SNAP").is_some()
        || Path::new("/.flatpak-info").exists()
    {
        return;
    }
    let (home, dirs) = data_dirs();
    let Some(home) = home else {
        return;
    };
    let file = format!("applications/{APP_ID}.desktop");
    let installed = std::iter::once(&home)
        .chain(dirs.iter())
        .map(|d| d.join(&file))
        .find(|p| p.is_file());
    let text = installed
        .as_ref()
        .and_then(|p| std::fs::read_to_string(p).ok());
    if installed.is_some() && text.is_none() {
        return;
    }
    if plan(text.as_deref(), |p| p.is_file()) == EntryPlan::Keep {
        return;
    }
    // A generated entry elsewhere than the user's own folder isn't OST's
    // to rewrite.
    let target = home.join(&file);
    if installed.as_ref().is_some_and(|p| p != &target) {
        return;
    }
    // From an AppImage, the AppImage itself (current_exe is inside its
    // mount, which is gone after it exits).
    let exe = match std::env::var_os("APPIMAGE") {
        Some(a) => PathBuf::from(a),
        None => match std::env::current_exe() {
            Ok(e) => e,
            Err(_) => return,
        },
    };
    let icon = format!("icons/hicolor/256x256/apps/{APP_ID}.png");
    let has_icon = std::iter::once(&home).chain(dirs.iter()).any(|d| {
        d.join(&icon).is_file()
            || d.join(format!("icons/hicolor/scalable/apps/{APP_ID}.svg"))
                .is_file()
    });
    let write = |path: &Path, bytes: &[u8]| -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        // Written beside, then moved into place: the desktop's watcher
        // never reads half a file.
        let tmp = path.with_extension("ost-tmp");
        std::fs::write(&tmp, bytes)?;
        std::fs::rename(&tmp, path)
    };
    if !has_icon && let Err(e) = write(&home.join(&icon), ICON_PNG) {
        tracing::warn!("desktop entry: icon not written: {e}");
    }
    let Some(text) = entry_text(&exe) else {
        tracing::warn!("desktop entry: not written: the binary's path can't be in one");
        return;
    };
    match write(&target, text.as_bytes()) {
        Ok(()) => {
            tracing::info!("desktop entry: wrote {}", target.display());
            // The desktop's list of which app takes which link (its
            // msteams: handler); desktops that scan entries themselves
            // don't need it.
            if let Some(dir) = target.parent() {
                let _ = std::process::Command::new("update-desktop-database")
                    .arg(dir)
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .spawn();
            }
            crate::backend::runtime().spawn(resend_later());
        }
        Err(e) => tracing::warn!("desktop entry: not written: {e}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_is_read_quoted_or_bare() {
        assert_eq!(
            entry_exec("[Desktop Entry]\nExec=\"/opt/my apps/ost-desktop\"\n"),
            Some(PathBuf::from("/opt/my apps/ost-desktop"))
        );
        assert_eq!(
            entry_exec("Exec=ost-desktop %U\n"),
            Some(PathBuf::from("ost-desktop"))
        );
        assert_eq!(entry_exec("Name=OST\n"), None);
    }

    #[test]
    fn writes_only_where_no_working_entry_is() {
        let packaged = "[Desktop Entry]\nExec=ost-desktop\n";
        let ours = entry_text(Path::new("/home/u/OST.AppImage")).unwrap();
        assert_eq!(plan(None, |_| true), EntryPlan::Write);
        // A package's entry is never touched, whatever its Exec.
        assert_eq!(plan(Some(packaged), |_| false), EntryPlan::Keep);
        // OST's own: kept while its binary is there, rewritten once gone.
        assert_eq!(plan(Some(&ours), |_| true), EntryPlan::Keep);
        assert_eq!(plan(Some(&ours), |_| false), EntryPlan::Write);
        // One from before OST took Teams links is brought up to date.
        let older = ours
            .replace(&format!("{MIME_TYPES}\n"), "")
            .replace(" %u", "");
        assert_eq!(plan(Some(&older), |_| true), EntryPlan::Write);
    }

    #[test]
    fn generated_exec_is_escaped_for_both_parsing_stages() {
        // Quoting inside the argument, then the desktop-entry string's own
        // escapes (every backslash doubled). The same paths were launched
        // through GLib's loader (Gio.DesktopAppInfo) to check them.
        let text = entry_text(Path::new("/tmp/a \"b\"/done/$x`y\\z")).unwrap();
        assert!(text.contains("Exec=\"/tmp/a \\\\\"b\\\\\"/done/\\\\$x\\\\`y\\\\\\\\z\" %u\n"));
        assert!(text.contains("MimeType=x-scheme-handler/msteams;"));
        assert!(text.contains(&format!("Icon={APP_ID}\n")));
        assert!(text.lines().any(|l| l == GENERATED_KEY));
        for p in [
            "/opt/my apps/ost-desktop",
            "/tmp/a \"b\"/done/$x`y\\z",
            "/home/u/OST.AppImage",
        ] {
            assert_eq!(
                entry_exec(&entry_text(Path::new(p)).unwrap()),
                Some(PathBuf::from(p))
            );
        }
        // Paths an entry can't hold.
        assert!(entry_text(Path::new("/tmp/a\nb")).is_none());
        assert!(entry_text(Path::new("/tmp/100%done/ost-desktop")).is_none());
    }
}
