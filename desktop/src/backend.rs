//! The QML-facing backend: one QObject that drives the OST engine.
//!
//! Engine calls are async and run on a shared Tokio runtime; results are
//! posted back to the Qt thread with `qt_thread().queue`, so properties are
//! only ever written on the Qt thread. Lists cross to QML as JSON strings,
//! which QML parses into its own models; this keeps the bridge small.

use std::pin::Pin;
use std::sync::OnceLock;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::json;
use teams_cli::api::{self, client::TeamsClient};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, busy)]
        #[qproperty(bool, signed_in)]
        #[qproperty(QString, user_name)]
        #[qproperty(QString, status_text)]
        #[qproperty(QString, chats_json)]
        #[qproperty(QString, messages_json)]
        #[qproperty(QString, current_chat_id)]
        #[qproperty(QString, current_chat_name)]
        #[qproperty(bool, has_credentials)]
        #[qproperty(QString, sign_in_code)]
        #[qproperty(QString, sign_in_url)]
        type Backend = super::BackendRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        /// Load the signed-in user and the chat list.
        #[qinvokable]
        fn refresh(self: Pin<&mut Backend>);

        /// Decide what to show at startup: the app, or the sign-in screen.
        #[qinvokable]
        fn start(self: Pin<&mut Backend>);

        /// Begin a device-code sign-in; the code and page appear in
        /// `signInCode` / `signInUrl`, and the app loads once approved.
        #[qinvokable]
        fn begin_sign_in(self: Pin<&mut Backend>);

        /// Forget the stored credentials and return to the sign-in screen.
        #[qinvokable]
        fn sign_out(self: Pin<&mut Backend>);

        /// Open a chat and load its messages.
        #[qinvokable]
        fn select_chat(self: Pin<&mut Backend>, chat_id: &QString, chat_name: &QString);

        /// Send a message to the open chat, then reload it.
        #[qinvokable]
        fn send_message(self: Pin<&mut Backend>, text: &QString);
    }

    impl cxx_qt::Threading for Backend {}
}

#[derive(Default)]
pub struct BackendRust {
    busy: bool,
    signed_in: bool,
    user_name: QString,
    status_text: QString,
    chats_json: QString,
    messages_json: QString,
    current_chat_id: QString,
    current_chat_name: QString,
    has_credentials: bool,
    sign_in_code: QString,
    sign_in_url: QString,
}

/// How many chats and messages to load per request.
const CHAT_LIMIT: usize = 50;
const MESSAGE_LIMIT: usize = 50;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("failed to start the engine runtime")
    })
}

/// A short, single-line error for the status bar. Never includes tokens:
/// engine errors are built from endpoint error codes, not response bodies.
fn short_error(e: &anyhow::Error) -> String {
    let text = format!("{e:#}");
    let line = text.lines().next().unwrap_or_default();
    line.chars().take(200).collect()
}

async fn load_overview() -> anyhow::Result<(String, String)> {
    let client = TeamsClient::new().await?;
    let me = api::whoami_data(&client).await?;
    let chats = api::list_chats_data(&client, CHAT_LIMIT).await?;
    let list: Vec<_> = chats
        .iter()
        .map(|c| {
            json!({
                "id": c.id,
                "name": c.name,
                "isGroup": c.is_group,
                "time": c.last_message_time,
                "sender": c.last_message_sender,
                "preview": c.last_message_preview,
            })
        })
        .collect();
    Ok((me.display_name, serde_json::to_string(&list)?))
}

async fn load_messages(chat_id: String) -> anyhow::Result<String> {
    let client = TeamsClient::new().await?;
    let own = client.display_name().unwrap_or_default();
    let messages = api::read_messages_data(&client, &chat_id, MESSAGE_LIMIT).await?;
    let list: Vec<_> = messages
        .iter()
        .map(|m| {
            json!({
                "sender": m.sender,
                "time": m.timestamp,
                "text": m.content,
                "mine": !own.is_empty() && m.sender == own,
            })
        })
        .collect();
    Ok(serde_json::to_string(&list)?)
}

impl qobject::Backend {
    pub fn start(mut self: Pin<&mut Self>) {
        let stored = teams_cli::auth::has_credentials();
        self.as_mut().set_has_credentials(stored);
        if stored {
            self.refresh();
        }
    }

    pub fn begin_sign_in(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_status_text(QString::default());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let pending = match teams_cli::auth::begin_sign_in().await {
                Ok(p) => p,
                Err(e) => {
                    let msg = short_error(&e);
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_busy(false);
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                    });
                    return;
                }
            };
            let code = pending.user_code().to_string();
            let url = pending.verification_uri().to_string();
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_sign_in_code(QString::from(code.as_str()));
                this.as_mut().set_sign_in_url(QString::from(url.as_str()));
            });
            let result = teams_cli::auth::finish_sign_in(pending).await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                this.as_mut().set_sign_in_code(QString::default());
                this.as_mut().set_sign_in_url(QString::default());
                match result {
                    Ok(missing) => {
                        if !missing.is_empty() {
                            tracing::warn!("signed in without: {}", missing.join(", "));
                        }
                        this.as_mut().set_has_credentials(true);
                        this.as_mut().refresh();
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn sign_out(mut self: Pin<&mut Self>) {
        if let Err(e) = teams_cli::auth::sign_out() {
            self.as_mut()
                .set_status_text(QString::from(short_error(&e).as_str()));
            return;
        }
        self.as_mut().set_has_credentials(false);
        self.as_mut().set_signed_in(false);
        self.as_mut().set_user_name(QString::default());
        self.as_mut().set_chats_json(QString::from("[]"));
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().set_current_chat_id(QString::default());
        self.as_mut().set_current_chat_name(QString::default());
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_status_text(QString::from("Loading…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = load_overview().await;
            tracing::info!(ok = result.is_ok(), "overview loaded");
            if let Err(e) = &result {
                tracing::warn!("overview failed: {}", short_error(e));
            }
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok((name, chats)) => {
                        this.as_mut().set_signed_in(true);
                        this.as_mut().set_user_name(QString::from(name.as_str()));
                        this.as_mut().set_chats_json(QString::from(chats.as_str()));
                        this.as_mut().set_status_text(QString::default());
                    }
                    Err(e) => {
                        this.as_mut().set_signed_in(false);
                        this.as_mut()
                            .set_status_text(QString::from(short_error(&e).as_str()));
                    }
                }
            });
        });
    }

    pub fn select_chat(mut self: Pin<&mut Self>, chat_id: &QString, chat_name: &QString) {
        self.as_mut().set_current_chat_id(chat_id.clone());
        self.as_mut().set_current_chat_name(chat_name.clone());
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().reload_messages();
    }

    pub fn send_message(mut self: Pin<&mut Self>, text: &QString) {
        let body = text.to_string();
        let chat_id = self.rust().current_chat_id.to_string();
        if body.trim().is_empty() || chat_id.is_empty() {
            return;
        }
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::send_message_with_client(&client, &chat_id, &body).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => this.as_mut().reload_messages(),
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    fn reload_messages(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let wanted = chat_id.clone();
            let result = load_messages(chat_id).await;
            tracing::info!(ok = result.is_ok(), "messages loaded");
            let _ = qt.queue(move |mut this| {
                // Ignore a late answer for a chat the user has already left.
                if this.rust().current_chat_id.to_string() != wanted {
                    return;
                }
                match result {
                    Ok(json) => this
                        .as_mut()
                        .set_messages_json(QString::from(json.as_str())),
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }
}
