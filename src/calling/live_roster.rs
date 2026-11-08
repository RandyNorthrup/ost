//! Who is in a chat's call when you aren't: Teams subscribes to the call's
//! conversation without joining it (calling-pluginless `subscribeToCall`,
//! a conversation request with no call to the liveness entry's
//! `conversationUrl`), takes the roster from the response, follows its
//! roster updates, and leaves when the chat closes. The chat header's
//! live roster (the group call pill, a meeting's live band) shows it.

use anyhow::{Context, Result};

use super::roster::{self, Participant};
use super::signaling::{self, ConversationCallParams};
use crate::config::Config;

/// A watched call: where to leave it, and who is in it.
pub struct LiveRoster {
    pub thread_id: String,
    /// The meeting's lobby chat (`activeModalities.groupChat.lobbyThreadId`).
    pub lobby_thread: Option<String>,
    pub roster: Vec<Participant>,
    leave_url: Option<String>,
    params: OwnedParams,
    http: reqwest::Client,
}

/// The signaling parameters, owned.
struct OwnedParams {
    ic3_token: String,
    trouter_surl: String,
    caller_mri: String,
    caller_display_name: String,
    endpoint_id: String,
    participant_id: String,
    thread_id: String,
    chain_id: String,
    message_id: String,
    caller_oid: String,
    tenant_id: String,
}

impl OwnedParams {
    fn params(&self) -> ConversationCallParams<'_> {
        ConversationCallParams {
            ic3_token: &self.ic3_token,
            trouter_surl: &self.trouter_surl,
            caller_mri: &self.caller_mri,
            caller_display_name: &self.caller_display_name,
            endpoint_id: &self.endpoint_id,
            participant_id: &self.participant_id,
            thread_id: &self.thread_id,
            chain_id: &self.chain_id,
            message_id: &self.message_id,
            caller_oid: &self.caller_oid,
            tenant_id: &self.tenant_id,
        }
    }
}

impl LiveRoster {
    /// Watch the call going on in `thread_id` (its liveness entry's
    /// `conversationUrl` and call id).
    pub async fn subscribe(thread_id: &str, conversation_url: &str, call_id: &str) -> Result<Self> {
        if !super::incoming::is_service_link(conversation_url) {
            anyhow::bail!("Not a Teams conversation link");
        }
        let mut config = Config::load()?;
        if config.get_ic3_token().is_none_or(|t| t.is_expired()) {
            crate::auth::oauth::refresh()
                .await
                .context("Token refresh failed")?;
            config = Config::load()?;
        }
        let ic3_token = config
            .get_ic3_token()
            .context("No calling (IC3) token")?
            .token;
        let oid = config
            .object_id()
            .context("Signed-in user has no object id")?;
        let (trouter_surl, endpoint_id) =
            crate::trouter::current_endpoint().context("Push channel is not connected")?;
        let params = OwnedParams {
            ic3_token,
            trouter_surl,
            caller_mri: format!("8:orgid:{oid}"),
            caller_display_name: config.display_name().unwrap_or_default(),
            endpoint_id,
            participant_id: uuid::Uuid::new_v4().to_string(),
            thread_id: thread_id.to_string(),
            chain_id: if call_id.is_empty() {
                uuid::Uuid::new_v4().to_string()
            } else {
                call_id.to_string()
            },
            message_id: uuid::Uuid::new_v4().to_string(),
            caller_oid: oid.clone(),
            tenant_id: config.tenant_id().unwrap_or_default(),
        };
        let http = reqwest::Client::new();
        let body =
            signaling::subscribe_conversation(&http, conversation_url, &params.params()).await?;
        let lobby_thread = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .and_then(|v| {
                ["", "/conversationResponse"].iter().find_map(|p| {
                    v.pointer(&format!("{p}/activeModalities/groupChat/lobbyThreadId"))
                        .and_then(|t| t.as_str())
                        .map(str::to_string)
                })
            });
        tracing::info!(
            ?lobby_thread,
            links = ?serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|v| v.get("links").and_then(|l| l.as_object()).map(|o| o.keys().cloned().collect::<Vec<_>>())),
            "watched call"
        );
        let mut people = roster::joined(&body);
        people.retain(|p| p.active);
        Ok(Self {
            thread_id: thread_id.to_string(),
            lobby_thread,
            roster: people,
            leave_url: leave_link(&body),
            params,
            http,
        })
    }

    /// Who is in the call besides you (Teams' live roster leaves you out).
    pub fn others(&self) -> impl Iterator<Item = &Participant> {
        let me = self.params.caller_mri.to_ascii_lowercase();
        self.roster.iter().filter(move |p| p.active && p.id != me)
    }

    /// A `subscription/rosterUpdate/` event for this call.
    pub fn apply(&mut self, json: &str) -> bool {
        match roster::subscription_roster_delta(json) {
            Some(delta) => {
                roster::apply(&mut self.roster, delta);
                true
            }
            None => false,
        }
    }

    /// Stop watching (Teams leaves the conversation).
    pub async fn leave(self) {
        tracing::info!(
            has_link = self.leave_url.is_some(),
            "leaving the watched call"
        );
        if let Some(url) = &self.leave_url
            && let Err(e) =
                signaling::leave_conversation(&self.http, url, &self.params.params(), 0).await
        {
            tracing::warn!("Leaving the watched call failed: {:#}", e);
        }
    }
}

fn leave_link(response: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(response).ok()?;
    v.pointer("/links/leave")
        .or_else(|| v.pointer("/conversationResponse/links/leave"))
        .and_then(|u| u.as_str())
        .filter(|u| super::incoming::is_service_link(u))
        .map(str::to_string)
}
