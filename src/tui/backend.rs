//! Async backend: bridges the sync TUI event loop with async API calls.
//!
//! Uses an mpsc channel pair. The TUI sends `BackendCommand` values, and a
//! background tokio task executes them and sends `BackendResponse` values back.

use std::sync::Arc;

use anyhow::Result;
use tokio::sync::mpsc;

use crate::api;
use crate::api::client::TeamsClient;

/// Commands sent from the TUI event loop to the async backend.
pub enum BackendCommand {
    LoadTeams,
    LoadChats { limit: usize },
    LoadMessages { chat_id: String, limit: usize },
    SendMessage { chat_id: String, message: String },
    LoadUserInfo,
    LoadPresence,
    /// Mark a chat or channel read up to its newest message (Teams'
    /// consumption horizon), as opening it in Teams does.
    MarkRead { chat_id: String },
}

/// Responses from the async backend to the TUI.
pub enum BackendResponse {
    Teams(Result<Vec<api::TeamInfo>>),
    Chats(Result<Vec<api::ChatInfo>>),
    Messages {
        chat_id: String,
        result: Result<Vec<api::MessageInfo>>,
    },
    MessageSent(Result<()>),
    UserInfo(Result<api::UserInfo>),
    Presence(Result<api::PresenceInfo>),
    /// Initial client creation failed (auth issue).
    ClientError(String),
    /// Teams pushed chat-service events (Trouter): the conversations they
    /// changed, and those with a new message from someone else.
    Push {
        changed: Vec<String>,
        new_from_others: Vec<String>,
    },
    /// The push channel (re)connected.
    PushConnected,
    /// Push events were dropped: reload everything.
    PushLagged,
}

/// Handle for interacting with the backend from the TUI side.
pub struct Backend {
    cmd_tx: mpsc::UnboundedSender<BackendCommand>,
    resp_rx: mpsc::UnboundedReceiver<BackendResponse>,
}

impl Backend {
    /// Start the backend. Spawns a tokio task that processes commands.
    ///
    /// Returns the Backend handle for sending commands and receiving responses.
    pub fn start() -> Self {
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        let (resp_tx, resp_rx) = mpsc::unbounded_channel();

        tokio::spawn(backend_loop(cmd_rx, resp_tx));

        Self { cmd_tx, resp_rx }
    }

    /// Send a command to the backend (non-blocking).
    pub fn send(&self, cmd: BackendCommand) {
        if self.cmd_tx.send(cmd).is_err() {
            tracing::error!("Backend channel closed -- command dropped");
        }
    }

    /// Receive a response from the backend.
    ///
    /// Suspends until a response is available. Returns `None` only when the
    /// backend channel is permanently closed (all senders dropped).
    /// Designed to be used inside `tokio::select!`.
    pub async fn recv(&mut self) -> Option<BackendResponse> {
        self.resp_rx.recv().await
    }
}

/// Background loop that processes commands.
///
/// Creates a TeamsClient once and reuses it across all API calls.
/// If client creation fails, sends a ClientError response and exits.
async fn backend_loop(
    mut cmd_rx: mpsc::UnboundedReceiver<BackendCommand>,
    resp_tx: mpsc::UnboundedSender<BackendResponse>,
) {
    // Try to create the client. If this fails, the user needs to login first.
    let client = match TeamsClient::new().await {
        Ok(c) => Arc::new(c),
        Err(e) => {
            let _ = resp_tx.send(BackendResponse::ClientError(format!("{:#}", e)));
            return;
        }
    };

    start_push(&client, resp_tx.clone());

    while let Some(cmd) = cmd_rx.recv().await {
        let client = Arc::clone(&client);
        let resp_tx = resp_tx.clone();

        // Spawn each command as a separate task so we don't block the loop.
        tokio::spawn(async move {
            match cmd {
                BackendCommand::LoadTeams => {
                    let result = api::tui_teams(&client).await;
                    let _ = resp_tx.send(BackendResponse::Teams(result));
                }
                BackendCommand::LoadChats { limit } => {
                    let result = api::list_chats_data(&client, limit).await;
                    let _ = resp_tx.send(BackendResponse::Chats(result));
                }
                BackendCommand::LoadMessages { chat_id, limit } => {
                    let result = api::read_messages_data(&client, &chat_id, limit).await;
                    let _ = resp_tx.send(BackendResponse::Messages { chat_id, result });
                }
                BackendCommand::SendMessage { chat_id, message } => {
                    let result = api::send_message_with_client(&client, &chat_id, &message).await;
                    let _ = resp_tx.send(BackendResponse::MessageSent(result));
                }
                BackendCommand::LoadUserInfo => {
                    let result = api::whoami_data(&client).await;
                    let _ = resp_tx.send(BackendResponse::UserInfo(result));
                }
                BackendCommand::LoadPresence => {
                    let result = api::get_presence_data(&client).await;
                    let _ = resp_tx.send(BackendResponse::Presence(result));
                }
                BackendCommand::MarkRead { chat_id } => {
                    if let Err(e) = api::messages::mark_chat_read_to_latest(&client, &chat_id).await {
                        tracing::warn!("mark read failed: {:#}", e);
                    }
                }
            }
        });
    }
}

/// Connect to Teams' push channel (Trouter), as the desktop app does, and
/// hand its chat events to the TUI.
fn start_push(client: &TeamsClient, resp_tx: mpsc::UnboundedSender<BackendResponse>) {
    use crate::event_hub::{self, EventKind};
    use tokio::sync::broadcast::error::RecvError;

    let mut events = event_hub::subscribe();
    tokio::spawn(async {
        let opts = crate::trouter::ListenOptions { better_together: false, ..crate::trouter::ListenOptions::EMBEDDED };
        if let Err(e) = crate::trouter::listen(opts, std::future::pending).await {
            tracing::warn!("push channel stopped: {:#}", e);
        }
    });
    let me = client
        .object_id()
        .map(|o| format!("8:orgid:{o}"))
        .unwrap_or_default();
    tokio::spawn(async move {
        loop {
            let ev = match events.recv().await {
                Ok(ev) => ev,
                Err(RecvError::Lagged(n)) => {
                    tracing::warn!("missed {n} push events; reloading");
                    if resp_tx.send(BackendResponse::PushLagged).is_err() {
                        return;
                    }
                    continue;
                }
                Err(RecvError::Closed) => return,
            };
            let response = match ev.kind {
                EventKind::Connected => BackendResponse::PushConnected,
                EventKind::Call | EventKind::BetterTogether => continue,
                EventKind::Chat => {
                    let changed = event_hub::conversation_ids(&ev.json);
                    if changed.is_empty() {
                        continue;
                    }
                    let new_from_others = new_from_others(&ev.json, &me);
                    tracing::debug!(chats = changed.len(), "chat push");
                    BackendResponse::Push { changed, new_from_others }
                }
            };
            if resp_tx.send(response).is_err() {
                return;
            }
        }
    });
}

/// The conversations (a channel for its replies too) that a pushed event
/// brings someone else's new message to.
fn new_from_others(json: &str, me: &str) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    for m in crate::event_hub::message_events(json) {
        let mine = !me.is_empty() && m.sender_mri.eq_ignore_ascii_case(me);
        if !mine && !ids.contains(&m.conversation_id) {
            ids.push(m.conversation_id);
        }
    }
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn own_messages_are_not_new_from_others() {
        let ev = |from: &str, conv: &str| {
            format!(
                r#"{{"resourceType":"NewMessage","resourceLink":"https://x/v1/users/ME/conversations/{conv}/messages/2","resource":{{"id":"2","messagetype":"Text","content":"hi","from":"https://x/v1/users/ME/contacts/{from}","conversationLink":"https://x/v1/users/ME/conversations/{conv}"}}}}"#
            )
        };
        let batch = format!(
            r#"{{"eventMessages":[{},{},{}]}}"#,
            ev("8:orgid:me", "19:a@thread.v2"),
            ev("8:orgid:other", "19:b@thread.v2"),
            ev("8:orgid:other", "19:c@thread.tacv2;messageid=1")
        );
        assert_eq!(
            new_from_others(&batch, "8:orgid:me"),
            vec!["19:b@thread.v2".to_string(), "19:c@thread.tacv2".to_string()]
        );
    }
}
