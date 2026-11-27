//! Meeting chats' kinds (a town hall's "Event group", a meeting's
//! "Planning group") as Teams learns them: from its chat sync, not from
//! each meeting's thread.
//!
//! The chat service's chat list leaves `meetingChatType` out of a chat's
//! threadProperties. Teams (bundles 26304, shared worker) takes it from its
//! CSA start-up sync instead: `GET {csa}/api/v3/teams/users/me?…`
//! (`startupclean`) once, then `GET {csa}/api/v3/teams/users/me/updates?…`
//! with the `x-ms-synctoken` it was handed (`startupdelta`). Each chat in
//! it carries `meetingChatType` ("backroom", "lobby") and
//! `meetingInformation.templateDetails`, which Teams copies into the
//! chat's threadProperties (`W.meetingChatType = j.meetingChatType`). On
//! testpc1 (2026-11-27) a restarted Teams read only the `updates` call and
//! no meeting thread at all.
//!
//! The clean sync is partial (`metadata.hasMoreChats`): for ost-test1
//! (2026-11-27) it held 269 of the 373 chats the chat service lists, and
//! its 7 backrooms; of the 66 listed meeting chats it left out, none of
//! the 63 whose threads answered was a backroom. Teams' later
//! `GET {csa}/api/v1/teams/users/me/nonrecentchats?skipNonRecentMeeting=…`
//! added one chat, so OST doesn't read it.
//!
//! OST does the same: one clean sync per session, then a delta, only when
//! the chat list shows a titled meeting chat no sync has been asked about
//! yet (a new one), at most once a minute. A chat a sync left out stays
//! unnamed (its plain title) rather than being asked about again. A
//! refused sync is remembered: nothing is asked again before its
//! `Retry-After`, or a backoff (5 s doubling to 5 min) when it gave none.

use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

use anyhow::Result;

use super::client::TeamsClient;

/// Teams' start-up sync query (getStartupDataCommon for v3).
const QUERY: &str = "isPrefetch=false&enableMembershipSummary=true\
&supportsAdditionalSystemGeneratedFolders=true&supportsSliceItems=true\
&enableEngageCommunities=true";

/// The shortest time between two delta syncs.
const DELTA_EVERY: Duration = Duration::from_secs(60);
/// The first wait after a refused sync that named no `Retry-After`.
const BACKOFF_FIRST: Duration = Duration::from_secs(5);
/// The longest wait after refused syncs.
const BACKOFF_MAX: Duration = Duration::from_secs(300);

/// What the syncs said so far.
#[derive(Default)]
struct SyncState {
    /// Chat id → backroom kind ("event", "meeting" or "") for every chat
    /// a sync named.
    kinds: HashMap<String, String>,
    /// The chats wanted when a sync answered: one it left out isn't
    /// asked about again (only a chat that turns up later is).
    asked: HashSet<String>,
    /// The token the last sync handed out, for the next delta.
    token: Option<String>,
    /// When the last sync answered.
    synced_at: Option<Instant>,
    /// Nothing is asked before this (a refused sync's wait).
    retry_at: Option<Instant>,
    /// Refused syncs in a row.
    failures: u32,
    /// Syncs asked for this session (for the start-up log).
    requests: u32,
}

static STATE: std::sync::Mutex<Option<SyncState>> = std::sync::Mutex::new(None);
/// One sync at a time: list reads that overlap wait for the one in flight.
static IN_FLIGHT: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

fn with_state<T>(f: impl FnOnce(&mut SyncState) -> T) -> T {
    f(STATE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(Default::default))
}

/// A sync's chats as chat id → backroom kind, and its next sync token.
pub(crate) fn kinds_from(v: &serde_json::Value) -> (HashMap<String, String>, Option<String>) {
    let kinds = v
        .get("chats")
        .and_then(|c| c.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let id = c.get("id")?.as_str()?.to_string();
            let mut props = HashMap::new();
            if let Some(t) = c.get("meetingChatType") {
                props.insert("meetingChatType".to_string(), t.clone());
            }
            if let Some(m) = c.get("meetingInformation") {
                props.insert("meeting".to_string(), m.clone());
            }
            Some((id, super::chat::backroom_kind(&props).to_string()))
        })
        .collect();
    let token = v
        .pointer("/metadata/syncToken")
        .and_then(|t| t.as_str())
        .filter(|t| !t.is_empty())
        .map(str::to_string);
    (kinds, token)
}

/// The wait before asking again after `failures` refused syncs in a row,
/// the last one asking for `retry_after`.
fn backoff(failures: u32, retry_after: Option<Duration>) -> Duration {
    retry_after.unwrap_or_else(|| {
        BACKOFF_FIRST
            .saturating_mul(1u32 << failures.saturating_sub(1).min(16))
            .min(BACKOFF_MAX)
    })
}

/// Whether a sync is due for these titled meeting chats: one of them no
/// sync has been asked about yet, no refused sync's wait is running, and
/// the last sync is a minute old.
fn due(s: &SyncState, wanted: &[String], now: Instant) -> bool {
    if wanted
        .iter()
        .all(|id| s.kinds.contains_key(id) || s.asked.contains(id))
    {
        return false;
    }
    if s.retry_at.is_some_and(|at| now < at) {
        return false;
    }
    s.synced_at.is_none_or(|at| now >= at + DELTA_EVERY)
}

async fn sync(client: &TeamsClient, token: Option<&str>) -> Result<serde_json::Value> {
    let (base, aad) = super::teams::csa(client).await?;
    let url = match token {
        Some(_) => format!("{base}/v3/teams/users/me/updates?{QUERY}"),
        None => format!("{base}/v3/teams/users/me?{QUERY}"),
    };
    let mut req = client.http().get(&url).bearer_auth(aad);
    if let Some(t) = token {
        req = req.header("x-ms-synctoken", t);
    }
    let resp = req.send().await?;
    let status = resp.status();
    if !status.is_success() {
        let retry_after = super::client::retry_after(resp.headers());
        let body = resp.text().await.unwrap_or_default();
        return Err(super::client::HttpError {
            status: status.as_u16(),
            url: url.split('?').next().unwrap_or_default().to_string(),
            body: body.chars().take(200).collect(),
            retry_after,
        }
        .into());
    }
    Ok(resp.json().await?)
}

/// The backroom kind of each of `wanted` (titled meeting chats) that a
/// sync named; a chat no sync named yet isn't in the map. Syncs only when
/// [`due`].
pub(crate) async fn meeting_kinds(
    client: &TeamsClient,
    wanted: &[String],
) -> HashMap<String, String> {
    let pick = |s: &mut SyncState| {
        wanted
            .iter()
            .filter_map(|id| Some((id.clone(), s.kinds.get(id)?.clone())))
            .collect::<HashMap<_, _>>()
    };
    if !with_state(|s| due(s, wanted, Instant::now())) {
        return with_state(pick);
    }
    let _one = IN_FLIGHT.lock().await;
    // (Another list read may have synced while this one waited.)
    let Some(token) = with_state(|s| {
        due(s, wanted, Instant::now()).then(|| {
            s.requests += 1;
            s.token.clone()
        })
    }) else {
        return with_state(pick);
    };
    let delta = token.is_some();
    let answer = sync(client, token.as_deref()).await;
    with_state(|s| {
        let now = Instant::now();
        match answer {
            Ok(v) => {
                let (kinds, next) = kinds_from(&v);
                let (chats, backrooms) = (
                    kinds.len(),
                    kinds.values().filter(|k| !k.is_empty()).count(),
                );
                s.kinds.extend(kinds);
                s.asked.extend(wanted.iter().cloned());
                let left_out = wanted.iter().filter(|id| !s.kinds.contains_key(*id));
                tracing::info!(
                    delta,
                    chats,
                    backrooms,
                    wanted = wanted.len(),
                    left_out = left_out.count(),
                    requests = s.requests,
                    "chat sync read (meeting chat kinds)"
                );
                if next.is_some() {
                    s.token = next;
                }
                s.synced_at = Some(now);
                s.retry_at = None;
                s.failures = 0;
            }
            Err(e) => {
                s.failures += 1;
                let retry_after = e
                    .chain()
                    .find_map(|c| c.downcast_ref::<super::client::HttpError>())
                    .and_then(|h| h.retry_after);
                let wait = backoff(s.failures, retry_after);
                tracing::warn!(
                    delta,
                    wait_s = wait.as_secs(),
                    "chat sync failed, not asked again before the wait: {e:#}"
                );
                s.retry_at = Some(now + wait);
            }
        }
        pick(s)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_sync_names_backrooms_by_their_template() {
        let v = serde_json::json!({
            "chats": [
                {"id": "19:meeting_a@thread.v2", "chatType": "meeting", "meetingChatType": "backroom",
                 "meetingInformation": {"templateDetails": {"id": crate::calling::live_event::TOWNHALL_TEMPLATE}}},
                {"id": "19:meeting_b@thread.v2", "chatType": "meeting", "meetingChatType": "backroom",
                 "meetingInformation": {"subject": "Plan"}},
                {"id": "19:meeting_c@thread.v2", "chatType": "meeting", "meetingChatType": "lobby"},
                {"id": "19:meeting_d@thread.v2", "chatType": "meeting", "meetingInformation": null},
                {"id": "19:x@thread.v2", "chatType": "chat"}
            ],
            "metadata": {"syncToken": "tok", "isPartialData": true}
        });
        let (kinds, token) = kinds_from(&v);
        assert_eq!(kinds["19:meeting_a@thread.v2"], "event");
        assert_eq!(kinds["19:meeting_b@thread.v2"], "meeting");
        assert_eq!(kinds["19:meeting_c@thread.v2"], "");
        assert_eq!(kinds["19:meeting_d@thread.v2"], "");
        assert_eq!(kinds["19:x@thread.v2"], "");
        assert_eq!(token.as_deref(), Some("tok"));
        let (_, none) =
            kinds_from(&serde_json::json!({"chats": [], "metadata": {"syncToken": ""}}));
        assert_eq!(none, None);
    }

    #[test]
    fn syncs_are_paced_and_refusals_remembered() {
        let now = Instant::now();
        let wanted = vec!["19:meeting_new@thread.v2".to_string()];
        let mut s = SyncState::default();
        // Never synced: due.
        assert!(due(&s, &wanted, now));
        // Everything wanted known: nothing asked.
        s.kinds.insert(wanted[0].clone(), String::new());
        assert!(!due(&s, &wanted, now));
        s.kinds.clear();
        // A chat a sync was asked about and left out: not asked again.
        s.asked.insert(wanted[0].clone());
        s.synced_at = Some(now);
        assert!(!due(&s, &wanted, now + DELTA_EVERY * 10));
        s.asked.clear();
        // Synced moments ago: the next sync waits a minute (with a token
        // or without one, so a clean sync that named no token isn't asked
        // again on every list read).
        assert!(!due(&s, &wanted, now + Duration::from_secs(10)));
        s.token = Some("t".into());
        assert!(!due(&s, &wanted, now + Duration::from_secs(10)));
        assert!(due(&s, &wanted, now + DELTA_EVERY));
        // A refused sync: nothing before its wait.
        s.retry_at = Some(now + DELTA_EVERY + Duration::from_secs(30));
        assert!(!due(&s, &wanted, now + DELTA_EVERY));
        assert!(due(
            &s,
            &wanted,
            now + DELTA_EVERY + Duration::from_secs(30)
        ));
    }

    #[test]
    fn refusals_back_off_unless_told_how_long() {
        assert_eq!(backoff(1, None), Duration::from_secs(5));
        assert_eq!(backoff(2, None), Duration::from_secs(10));
        assert_eq!(backoff(4, None), Duration::from_secs(40));
        assert_eq!(backoff(30, None), BACKOFF_MAX);
        assert_eq!(
            backoff(3, Some(Duration::from_secs(7))),
            Duration::from_secs(7)
        );
    }
}
