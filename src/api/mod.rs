//! API client module for Microsoft Teams

pub mod activity;
pub mod calendar;
mod chat;
pub mod client;
pub mod contacts;
pub mod directory;
pub mod drive;
pub mod emoticons;
pub mod files;
mod me;
pub mod messages;
pub mod msgactions;
pub mod onenote;
pub mod outbox;
pub mod planner;
pub mod presence;
pub mod store;
pub mod tabs;
mod teams;

use anyhow::Result;

// Re-export data types for TUI integration
pub use chat::{ChatInfo, MessageInfo};
pub use me::UserInfo;
pub use presence::PresenceInfo;
pub use teams::TeamInfo;

// Re-export ChannelInfo for use in TUI sidebar (currently consumed
// only through TeamInfo.channels, but kept public for future callers).
#[allow(unused_imports)]
pub use teams::ChannelInfo;

// Re-export data-returning functions for TUI integration
pub use chat::{
    CallRecord, call_history, create_group_chat, list_chats_data, read_messages_data,
    send_html_with_client, send_message_with_client, send_typing, strip_html,
};
pub use me::whoami_data;
pub use presence::get_presence_data;
pub use teams::list_teams_data;

/// List recent chats (native Teams API)
pub async fn list_chats(limit: usize) -> Result<()> {
    chat::list_chats(limit).await
}

/// Read messages from a chat (native Teams API)
pub async fn read_messages(chat_id: &str, limit: usize) -> Result<()> {
    chat::read_messages(chat_id, limit).await
}

/// Send a message to a chat (native Teams API)
pub async fn send_message(to: &str, message: &str) -> Result<()> {
    chat::send_message(to, message).await
}

/// Get current presence status
pub async fn get_presence() -> Result<()> {
    presence::get_presence().await
}

/// Set presence status
pub async fn set_presence(status: &str) -> Result<()> {
    presence::set_presence(status).await
}

/// Show current user info
pub async fn whoami() -> Result<()> {
    me::whoami().await
}

/// List joined teams and their channels
pub async fn list_teams() -> Result<()> {
    teams::list_teams().await
}
