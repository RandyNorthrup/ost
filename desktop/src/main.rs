//! OST desktop: a native Qt 6 / QML client on the OST engine.

mod backend;
mod key_typer;
mod lock_watch;
mod rich_text;
mod video_item;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};
use tracing_subscriber::EnvFilter;

unsafe extern "C" {
    /// QtWebEngineQuick::initialize() (src/webengine.cpp).
    fn ost_webengine_initialize();
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
    base.join("ost").join("ost-desktop.log")
}

/// The socket a running OST listens on, so launching it again brings that
/// window back (Teams keeps a single instance).
fn instance_socket() -> Option<std::path::PathBuf> {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(|d| std::path::PathBuf::from(d).join("ost-desktop.sock"))
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
            if std::io::BufReader::new(stream).read_line(&mut line).is_ok()
                && line.trim() == "activate"
            {
                tracing::info!("another launch asked for the window");
                backend::request_activate();
            }
        }
    });
    false
}

fn main() {
    // A plain launch (no test arguments) keeps one instance.
    if std::env::args().len() <= 1 && hand_over_to_running_instance() {
        return;
    }
    let log = log_path();
    let file = log
        .parent()
        .and_then(|d| std::fs::create_dir_all(d).ok())
        .and_then(|_| std::fs::File::create(&log).ok());
    {
        use tracing_subscriber::prelude::*;
        let filter = || EnvFilter::try_from_default_env().unwrap_or_else(|_| "warn".into());
        let stderr = tracing_subscriber::fmt::layer().with_filter(filter());
        let to_file = file.map(|f| {
            tracing_subscriber::fmt::layer()
                .with_ansi(false)
                .with_writer(std::sync::Mutex::new(f))
                .with_filter(EnvFilter::new("info"))
        });
        tracing_subscriber::registry()
            .with(stderr)
            .with(to_file)
            .init();
    }

    // FluentIcon reads the bundled SVGs (qrc:/) with XMLHttpRequest to
    // recolour them. All QML here is compiled into the binary, so no
    // untrusted script can use this to read files.
    // SAFETY: set before Qt or the Tokio runtime start, while main is the
    // only thread.
    unsafe { std::env::set_var("QML_XHR_ALLOW_FILE_READ", "1") };

    // Before the application: Teams' web apps (Whiteboard…) are embedded.
    // SAFETY: a plain Qt call with no arguments, made once, before Qt starts.
    unsafe { ost_webengine_initialize() };
    let mut app = QGuiApplication::new();
    // Wayland compositors match windows to ost-desktop.desktop by app id,
    // which is how the window gets the OST cheese icon.
    QGuiApplication::set_desktop_file_name(&QString::from("ost-desktop"));
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("OST"));
        app.as_mut()
            .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
    }
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/com/ost/desktop/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
    // Quit: later launches start afresh.
    if std::env::args().len() <= 1
        && let Some(path) = instance_socket()
    {
        let _ = std::fs::remove_file(path);
    }
}
