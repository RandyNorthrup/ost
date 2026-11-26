//! OST desktop: a native Qt 6 / QML client on the OST engine.

mod avatars;
mod backend;
mod better_together;
mod cameo_feed;
mod camera_feed;
mod clip_edit;
mod clip_frames;
mod clip_mask;
mod help_bundle;
mod hfp_calls;
mod key_typer;
mod launcher_badge;
mod lock_watch;
mod rich_text;
mod room_ble;
mod room_host;
mod room_remote;
mod tray;
mod video_effects;
mod video_item;
mod window_tool;
mod work_location;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};
use tracing_subscriber::EnvFilter;

unsafe extern "C" {
    /// QtWebEngineQuick::initialize() (src/webengine.cpp).
    fn ost_webengine_initialize();
    /// Development: load QML from a directory (src/native.cpp).
    #[cfg_attr(not(feature = "test-harness"), allow(dead_code))]
    fn ost_dev_qml_dir(engine: *mut core::ffi::c_void, dir: *const core::ffi::c_char);
    /// FluentIcon's pictures, "image://fluent/…" (src/native.cpp).
    fn ost_add_icon_provider(engine: *mut core::ffi::c_void);
}

/// OST's log file (what Help › Collect Support Files packs up):
/// `$XDG_STATE_HOME/ost/ost-desktop.log`, started afresh each run.
pub fn log_path() -> std::path::PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/state"))
        })
        .unwrap_or_else(std::env::temp_dir);
    // (A second account's profile, OST_PROFILE, logs on its own.)
    match teams_cli::config::profile() {
        Some(p) => base.join("ost").join(format!("ost-desktop-{p}.log")),
        None => base.join("ost").join("ost-desktop.log"),
    }
}

/// With extended diagnostics, the log grows across sessions to this size
/// before the older part moves to `previous_log_path`.
const EXTENDED_LOG_LIMIT: u64 = 64 * 1024 * 1024;

/// The older half of an extended-diagnostics log.
pub fn previous_log_path() -> std::path::PathBuf {
    log_path().with_extension("previous.log")
}

/// The socket a running OST listens on, so launching it again brings that
/// window back (Teams keeps a single instance).
fn instance_socket() -> Option<std::path::PathBuf> {
    std::env::var_os("XDG_RUNTIME_DIR").map(|d| match teams_cli::config::profile() {
        Some(p) => std::path::PathBuf::from(d).join(format!("ost-desktop-{p}.sock")),
        None => std::path::PathBuf::from(d).join("ost-desktop.sock"),
    })
}

/// When OST is already running: ask it to show its window, and return true.
/// Otherwise listen for later launches and return false.
fn hand_over_to_running_instance() -> bool {
    use std::io::{BufRead, Write};
    use std::os::unix::net::{UnixListener, UnixStream};
    let Some(path) = instance_socket() else {
        return false;
    };
    if let Ok(mut s) = UnixStream::connect(&path) {
        let _ = s.write_all(b"activate\n");
        return true;
    }
    // Nothing answers: a socket left by a crash is stale.
    let _ = std::fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else {
        return false;
    };
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut line = String::new();
            if std::io::BufReader::new(stream).read_line(&mut line).is_ok() {
                if line.trim() == "activate" {
                    tracing::info!("another launch asked for the window");
                    backend::request_activate();
                } else if let Some(rest) =
                    line.trim_end_matches(['\n', '\r']).strip_prefix("open\t")
                {
                    // Another account's "Activity in other accounts and
                    // orgs" picked one of this account's chats.
                    let (thread, name) = rest.split_once('\t').unwrap_or((rest, ""));
                    tracing::info!("another account's hub opened a chat here");
                    backend::request_open_chat(thread.to_string(), name.to_string());
                }
            }
        }
    });
    false
}

/// What `ost-desktop --help` prints.
const USAGE: &str = "\
Usage: ost-desktop [OPTION]

OST, a desktop client for Microsoft Teams. Started without options, it
opens its window (or brings back the one already running).

Options:
  -h, --help       Show this help and exit
  -V, --version    Show the version and exit
      --room       Run as a Teams Rooms device (also OST_ROOM=1)

Environment:
  OST_PROFILE=<name>   Use another signed-in account's profile, side by side
  OST_NO_KEYRING=1     Keep tokens in a file only you can read (0600) instead
                       of the system keyring (weaker; without a keyring and
                       without this, the sign-in lasts until OST quits)
  OST_SYSTEM_FRAME=1   Use the desktop's own window frame

More in docs/desktop.md.
";

/// Qt's own options a desktop session may pass (`-session` from session
/// managers restoring apps), with whether each takes a value.
#[cfg_attr(feature = "test-harness", allow(dead_code))]
const QT_OPTIONS: &[(&str, bool)] = &[
    ("-platform", true),
    ("-platformtheme", true),
    ("-style", true),
    ("-session", true),
    ("-display", true),
    ("-qwindowgeometry", true),
    ("-qwindowtitle", true),
    ("-reverse", false),
];

/// Why a build without the test harness won't start with these arguments
/// (None: it will). Only OST's own options (--help, --version, --room) and
/// Qt's are taken; the harness's flags and positional capture paths are
/// refused, so nothing a launch passes can drive the app or run script.
#[cfg_attr(feature = "test-harness", allow(dead_code))]
fn release_argument_error(args: &[String]) -> Option<String> {
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        match a {
            "-h" | "--help" | "-V" | "--version" | "--room" => {}
            _ => match QT_OPTIONS.iter().find(|(o, _)| *o == a) {
                Some((_, true)) if i + 1 < args.len() => i += 1,
                Some((_, false)) => {}
                _ => return Some(a.to_string()),
            },
        }
        i += 1;
    }
    None
}

/// `--version` / `--help`: print and exit before anything starts.
fn print_and_exit_for(arg: Option<&str>) -> bool {
    match arg {
        Some("-V" | "--version") => println!("ost-desktop {}", env!("CARGO_PKG_VERSION")),
        Some("-h" | "--help") => print!("{USAGE}"),
        _ => return false,
    }
    true
}

fn main() {
    if print_and_exit_for(std::env::args().nth(1).as_deref()) {
        return;
    }
    // Release builds: the test harness's flags aren't there to take.
    #[cfg(not(feature = "test-harness"))]
    if let Some(arg) = release_argument_error(&std::env::args().skip(1).collect::<Vec<_>>()) {
        eprintln!(
            "ost-desktop: unrecognized option '{arg}' (test-harness flags need a build with the test-harness feature)\nTry 'ost-desktop --help' for more information."
        );
        std::process::exit(2);
    }
    // A plain launch (no test arguments) keeps one instance.
    if std::env::args().len() <= 1 && hand_over_to_running_instance() {
        return;
    }
    let log = log_path();
    let file = log
        .parent()
        .and_then(|d| std::fs::create_dir_all(d).ok())
        .and_then(|_| {
            // Settings ▸ Privacy ▸ Extended diagnostics data: keep earlier
            // sessions' logs (Teams persists its logs past the in-memory
            // buffer); otherwise each start begins a fresh log.
            if backend::extended_diagnostics() {
                if std::fs::metadata(&log).is_ok_and(|m| m.len() > EXTENDED_LOG_LIMIT) {
                    let _ = std::fs::rename(&log, previous_log_path());
                }
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&log)
                    .ok()
            } else {
                let _ = std::fs::remove_file(previous_log_path());
                std::fs::File::create(&log).ok()
            }
        });
    {
        use tracing_subscriber::prelude::*;
        let filter = || EnvFilter::try_from_default_env().unwrap_or_else(|_| "warn".into());
        // Both logs take tokens out of every line before it's written
        // (teams_cli::feedback::scrub_secrets): logs never hold a token.
        use teams_cli::feedback::Scrubbed;
        let stderr = tracing_subscriber::fmt::layer()
            .with_writer(Scrubbed(std::io::stderr))
            .with_filter(filter());
        let to_file = file.map(|f| {
            tracing_subscriber::fmt::layer()
                .with_ansi(false)
                .with_writer(Scrubbed(std::sync::Mutex::new(f)))
                .with_filter(EnvFilter::new("info"))
        });
        tracing_subscriber::registry()
            .with(stderr)
            .with(to_file)
            .init();
    }

    // QML reads local files with XMLHttpRequest: bundled ones (qrc:/:
    // Loop's glyphs, the sticker catalog, Qt's web channel script) and the
    // emoji category pictures. All QML here is compiled into the binary, so
    // no untrusted script can use this to read files.
    // SAFETY: set before Qt or the Tokio runtime start, while main is the
    // only thread.
    unsafe { std::env::set_var("QML_XHR_ALLOW_FILE_READ", "1") };

    // Teams' video filter app runs in a view nobody looks at (and keeps
    // running while OST's main window is hidden): Chromium must not slow
    // its timers or rendering then.
    {
        let mut flags = std::env::var("QTWEBENGINE_CHROMIUM_FLAGS").unwrap_or_default();
        for f in [
            "--disable-background-timer-throttling",
            "--disable-renderer-backgrounding",
            "--disable-backgrounding-occluded-windows",
        ] {
            if !flags.contains(f) {
                flags = format!("{flags} {f}").trim().to_string();
            }
        }
        // SAFETY: set before Qt or the Tokio runtime start, while main is
        // the only thread.
        unsafe { std::env::set_var("QTWEBENGINE_CHROMIUM_FLAGS", flags) };
    }
    // After a sign-out, this profile's web storage goes before Qt
    // WebEngine opens it again.
    backend::wipe_web_storage_if_signed_out();
    // Before the application: Teams' web apps (Whiteboard…) are embedded.
    // SAFETY: a plain Qt call with no arguments, made once, before Qt starts.
    unsafe { ost_webengine_initialize() };
    let mut app = QGuiApplication::new();
    // Wayland compositors match windows to io.github.RandyNorthrup.ost.desktop
    // by app id, which is how the window gets the OST icon.
    QGuiApplication::set_desktop_file_name(&QString::from("io.github.RandyNorthrup.ost"));
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("OST"));
        app.as_mut()
            .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
    }
    // Teams' App language: its text, direction and culture, before any QML.
    backend::install_app_language();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        // OST_QML_DIR (development, test-harness builds only): QML from a
        // checkout instead of the compiled-in copy.
        #[cfg(feature = "test-harness")]
        if let Some(dir) = std::env::var("OST_QML_DIR")
            .ok()
            .filter(|d| !d.is_empty())
            .and_then(|d| std::ffi::CString::new(d).ok())
        {
            // SAFETY: the engine is alive and owns the interceptor's use;
            // only the pointer is passed.
            unsafe {
                ost_dev_qml_dir(
                    engine.as_mut().get_unchecked_mut() as *mut QQmlApplicationEngine
                        as *mut core::ffi::c_void,
                    dir.as_ptr(),
                )
            };
        }
        // SAFETY: the engine is alive and takes ownership of the provider.
        unsafe {
            ost_add_icon_provider(
                engine.as_mut().get_unchecked_mut() as *mut QQmlApplicationEngine
                    as *mut core::ffi::c_void,
            )
        };
        engine.load(&QUrl::from("qrc:/qt/qml/com/ost/desktop/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
    // Teams' Save and restart (and Sign out, which restarts to clear the
    // web storage): start again with the same arguments, straight away.
    // exec replaces the whole process, so nothing needs tearing down, and
    // tearing down a signed-in session's QML first can crash in libQt6Qml
    // before the restart happens (seen on sign-out, 2026-11-25).
    if backend::restart_requested()
        && let Ok(exe) = std::env::current_exe()
    {
        use std::os::unix::process::CommandExt;
        if std::env::args().len() <= 1
            && let Some(path) = instance_socket()
        {
            let _ = std::fs::remove_file(path);
        }
        let err = std::process::Command::new(exe)
            .args(std::env::args_os().skip(1))
            .exec();
        tracing::warn!("restart failed: {err}");
    }
    // Tear down our own Qt objects while the application still exists: the
    // QML engine (windows, Backend and its callbacks) first, then the app.
    drop(engine);
    drop(app);
    // Quit: later launches start afresh.
    if std::env::args().len() <= 1
        && let Some(path) = instance_socket()
    {
        let _ = std::fs::remove_file(path);
    }
    exit_without_static_teardown();
}

/// Leave without running C++ static destructors. Qt Multimedia keeps its
/// PipeWire audio context in a global whose destructor (run from the exit
/// handlers) stops its PipeWire thread while that thread can still be
/// handling a registry event as other audio nodes go away (WebEngine's, our
/// sound effects'); it then copies into freed memory and the quit
/// segfaults (seen intermittently, backtrace: `__run_exit_handlers` →
/// `pw_thread_loop_stop` on the main thread, `memcpy` in libQt6Multimedia on
/// the "QAudioContext" thread). Our own objects are already gone, the log
/// file is written unbuffered, and the OS reclaims the rest, so nothing
/// needs those destructors; the Tokio workers and Chromium's threads stop
/// with the process instead of racing teardown too.
fn exit_without_static_teardown() -> ! {
    use std::io::Write;
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().flush();
    unsafe extern "C" {
        fn _exit(status: i32) -> !;
    }
    // SAFETY: `_exit` only ends the process; it is called once, at the very
    // end of main, after every Rust value that needs dropping is dropped.
    unsafe { _exit(0) }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn release_builds_take_only_ost_and_qt_options() {
        for ok in [
            &[][..],
            &["--room"],
            &["--help"],
            &["-V"],
            &["-platform", "xcb"],
            &["-session", "1234_5678", "-reverse"],
        ] {
            assert_eq!(release_argument_error(&args(ok)), None, "{ok:?}");
        }
        for (bad, why) in [
            (&["--nav-test"][..], "--nav-test"),
            (&["--cal-test", "--cal-page-steps=cv.x()"], "--cal-test"),
            (&["--loop-test"], "--loop-test"),
            (&["/tmp/shot.png"], "/tmp/shot.png"),
            (&["--room", "--shots=/tmp"], "--shots=/tmp"),
            (&["--tray"], "--tray"),
            (&["-platform"], "-platform"),
            (&["--size=800x600"], "--size=800x600"),
        ] {
            assert_eq!(
                release_argument_error(&args(bad)).as_deref(),
                Some(why),
                "{bad:?}"
            );
        }
    }
}
