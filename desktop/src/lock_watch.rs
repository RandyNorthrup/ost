//! The machine's lock state, as Teams' host reports it to presence
//! (docs/spec/presence.md "Machine lock / unlock"): logind's session
//! `LockedHint` (lockers set it, or call Lock/Unlock), and suspend as
//! locked until resume.

use futures::StreamExt;
use teams_cli::api::presence;

#[zbus::proxy(
    interface = "org.freedesktop.login1.Session",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1/session/auto"
)]
trait Session {
    #[zbus(property)]
    fn locked_hint(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn id(&self) -> zbus::Result<String>;
    #[zbus(signal)]
    fn lock(&self) -> zbus::Result<()>;
    #[zbus(signal)]
    fn unlock(&self) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait Manager {
    #[zbus(signal)]
    fn prepare_for_sleep(&self, start: bool) -> zbus::Result<()>;
    fn get_session(&self, id: &str) -> zbus::Result<zbus::zvariant::OwnedObjectPath>;
}

/// Follow the session's lock state until the app exits.
pub async fn run() {
    if let Err(e) = watch().await {
        tracing::warn!("lock state unavailable: {e:#}");
    }
}

async fn watch() -> zbus::Result<()> {
    let bus = zbus::Connection::system().await?;
    let manager = ManagerProxy::new(&bus).await?;
    // Signals come from the session's own object, not the `auto` alias
    // (which resolves to the user's display session even for processes
    // the compositor started outside it).
    let id = SessionProxy::new(&bus).await?.id().await?;
    let path = manager.get_session(&id).await?;
    let session = SessionProxy::builder(&bus).path(path)?.build().await?;
    presence::set_machine_locked(session.locked_hint().await.unwrap_or(false));
    let mut hint = session.receive_locked_hint_changed().await;
    let mut locks = session.receive_lock().await?;
    let mut unlocks = session.receive_unlock().await?;
    let mut sleeps = manager.receive_prepare_for_sleep().await?;
    loop {
        tokio::select! {
            Some(c) = hint.next() => {
                if let Ok(v) = c.get().await {
                    presence::set_machine_locked(v);
                }
            }
            Some(_) = locks.next() => presence::set_machine_locked(true),
            Some(_) = unlocks.next() => presence::set_machine_locked(false),
            Some(s) = sleeps.next() => {
                // Suspending counts as locked; on resume, logind's hint decides.
                if let Ok(args) = s.args() {
                    let locked = if *args.start() { true } else { session.locked_hint().await.unwrap_or(false) };
                    presence::set_machine_locked(locked);
                }
            }
            else => break,
        }
    }
    Ok(())
}
