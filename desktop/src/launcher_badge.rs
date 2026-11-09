//! The unread count on OST's taskbar entry where the desktop draws app
//! badges itself: the freedesktop launcher API
//! (`com.canonical.Unity.LauncherEntry.Update`), which KDE Plasma's task
//! manager and GNOME's docks show as a count on the app's button. It
//! carries Teams' taskbar count (the app bar's unread total); the window
//! icon carries Teams' full overlay for taskbars that show window icons
//! (src/native.cpp).

use std::collections::HashMap;
use zbus::zvariant::Value;

const APP_URI: &str = "application://ost-desktop.desktop";

async fn connection() -> Option<&'static zbus::Connection> {
    static CONN: tokio::sync::OnceCell<Option<zbus::Connection>> = tokio::sync::OnceCell::const_new();
    CONN.get_or_init(|| async {
        match zbus::Connection::session().await {
            Ok(c) => Some(c),
            Err(e) => {
                tracing::debug!("launcher badge: no session bus: {e}");
                None
            }
        }
    })
    .await
    .as_ref()
}

/// Show `count` on the launcher entry (hidden at 0).
pub async fn update(count: i64) {
    let Some(conn) = connection().await else { return };
    let mut props: HashMap<&str, Value<'_>> = HashMap::new();
    props.insert("count", Value::from(count.max(0)));
    props.insert("count-visible", Value::from(count > 0));
    if let Err(e) = conn
        .emit_signal(
            None::<()>,
            "/com/ost/desktop/launcher",
            "com.canonical.Unity.LauncherEntry",
            "Update",
            &(APP_URI, props),
        )
        .await
    {
        tracing::debug!("launcher badge: {e}");
    }
}
