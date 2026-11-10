//! API client module for Microsoft Teams

pub mod activity;
pub mod app_details;
pub mod calendar;
mod chat;
pub mod client;
pub mod contacts;
pub mod custom_emoji;
pub mod directory;
pub mod drive;
pub mod ecs;
pub mod emoticons;
pub mod files;
pub mod folders;
pub mod funstuff;
mod me;
pub mod messages;
pub mod msgactions;
pub mod onenote;
pub mod outbox;
pub mod planner;
pub mod preferences;
pub mod presence;
pub mod profile;
pub mod store;
pub mod store_content;
pub mod channels;
pub mod tabs;
pub mod teams;
pub mod quick_views;
pub mod scheduled;
pub mod team_create;

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
    CallRecord, LiveCall, Member, ThreadMeeting, call_history, chat_meeting, chat_members,
    create_group_chat, ensure_one_on_one_chat, list_chats_data, read_messages_data,
    send_html_with_client, send_message_with_client, send_typing, strip_html, thread_live_call,
    thread_member_ids, user_display_name,
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
