//! OST desktop: a native Qt 6 / QML client on the OST engine.

mod backend;
mod video_item;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};
use tracing_subscriber::EnvFilter;

unsafe extern "C" {
    /// QtWebEngineQuick::initialize() (src/webengine.cpp).
    fn ost_webengine_initialize();
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "warn".into()))
        .init();

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
}
