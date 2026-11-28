//! Calls and meetings for a personal Microsoft account (Teams for personal
//! use, "TFL").
//!
//! Teams on the web for personal use places and answers calls with the
//! same conversation and call-controller protocol as work Teams, with
//! these differences (captured 2026-11-28 between OST Personal 1 and 2,
//! docs/research/personal-accounts-protocol.md §10):
//!
//! - Conversations are created at `api.flightproxy.skype.com/api/v2/cpconv`
//!   (work: the region's `epconv`), and every conversation and
//!   call-controller request carries the Skype token as `X-Skypetoken`
//!   (work: `Authorization: Bearer <IC3 token>`). Consumer accounts have
//!   no IC3 token.
//! - The conversation request (and an incoming call's attach) names
//!   `applicationType: "TFL"`.
//! - Calls reach a second Trouter socket on `go.trouter.teams.microsoft.com`
//!   registered as `SkypeSpacesWeb` / `TFLSkypeSpacesWeb_2.0` with
//!   transport context `TFL` ([`crate::trouter::registrar::register_personal_calling`]),
//!   next to the chat socket on the Skype Trouter.
//! - Meeting links are `https://teams.live.com/meet/<ID>?p=<passcode>`,
//!   joined by their `meetingData` as work Teams' Join with an ID.
//! - Free accounts get 60-minute meetings with up to 100 people (the
//!   authz response's `consumerLicenseDetails`).

use reqwest::header::{HeaderMap, HeaderValue};

/// Where a personal account creates its conversations (Teams free's
/// `conversationServiceUrl`).
pub const CPCONV_URL: &str = "https://api.flightproxy.skype.com/api/v2/cpconv";

/// The application type Teams for personal use names in its conversation
/// requests.
pub const APPLICATION_TYPE: &str = "TFL";

/// Personal meeting links' host (`https://teams.live.com/meet/<ID>?p=…`).
pub const MEET_LINK_BASE: &str = "https://teams.live.com/meet/";

/// A free account's meeting length and size (Teams' "Your free benefits":
/// 1 hour for each meeting and call, up to 100 participants), used when the
/// authz response doesn't say.
pub const FREE_MEETING_MINUTES: u64 = 60;
pub const FREE_MEETING_PARTICIPANTS: u64 = 100;

/// Most people a call from a chat can have in Teams for personal use;
/// above that Teams asks for a meeting.
pub const MAX_CHAT_CALL_PARTICIPANTS: usize = 20;

/// Whether the signed-in account is a personal one (read each time: the
/// first sign-in happens while OST runs).
pub fn is_personal() -> bool {
    crate::config::Config::load()
        .ok()
        .is_some_and(|c| is_personal_config(&c))
}

/// Whether `config` is a personal account's.
pub fn is_personal_config(config: &crate::config::Config) -> bool {
    crate::auth::is_personal_flow(config.auth_flow.as_deref())
        || config.identity().is_some_and(|i| i.is_personal())
}

/// The token a calling request carries: the IC3 token for a work account,
/// the Skype token for a personal one (which has no IC3 token). None when
/// the one it needs is missing.
pub fn calling_token(config: &crate::config::Config) -> Option<String> {
    stored_calling_token(config).map(|t| t.token)
}

fn stored_calling_token(
    config: &crate::config::Config,
) -> Option<crate::auth::tokens::StoredToken> {
    if is_personal_config(config) {
        config.get_skype_token()
    } else {
        config.get_ic3_token()
    }
}

/// Whether the calling token ([`calling_token`]) is missing or expired, so
/// the tokens need a refresh first.
pub fn calling_token_stale(config: &crate::config::Config) -> bool {
    stored_calling_token(config).is_none_or(|t| t.is_expired())
}

/// The authentication headers for a conversation or call-controller
/// request with `token` (from [`calling_token`]): `X-Skypetoken` for a
/// personal account, `Authorization: Bearer` for a work one.
pub fn auth_headers(token: &str) -> HeaderMap {
    auth_headers_for(is_personal(), token)
}

pub fn auth_headers_for(personal: bool, token: &str) -> HeaderMap {
    let mut h = HeaderMap::new();
    let (name, value) = if personal {
        ("X-Skypetoken", token.to_string())
    } else {
        ("Authorization", format!("Bearer {token}"))
    };
    if let Ok(mut v) = HeaderValue::from_str(&value) {
        v.set_sensitive(true);
        h.insert(name, v);
    }
    h
}

/// The account's tenant for a call's `meetingInfo`: a work account's, or
/// "" for a personal account (Teams for personal use sends no tenant).
pub fn tenant_or_none(config: &crate::config::Config) -> anyhow::Result<String> {
    match config.tenant_id() {
        Some(t) => Ok(t),
        None if is_personal_config(config) => Ok(String::new()),
        None => anyhow::bail!("No tenant id"),
    }
}

/// The conversation service a call is created at: Teams free's `cpconv`
/// for a personal account, else the region's `epconv`.
pub fn conversation_service_url(
    config: &crate::config::Config,
    region_gtms: Option<&serde_json::Value>,
) -> Option<String> {
    if let Ok(url) = std::env::var("TEAMS_EPCONV_URL") {
        return Some(url);
    }
    if is_personal_config(config) {
        return Some(CPCONV_URL.to_string());
    }
    super::call_test::derive_epconv_url(region_gtms?)
}

/// Mark a conversation request as Teams for personal use's
/// (`conversationRequest.applicationType`), for a personal account.
pub fn mark_application(payload: &mut serde_json::Value) {
    if is_personal() {
        mark_application_for(payload);
    }
}

pub fn mark_application_for(payload: &mut serde_json::Value) {
    // No tenant: Teams for personal use sends no meetingInfo of its own.
    if payload
        .pointer("/meetingInfo/tenantId")
        .and_then(|t| t.as_str())
        .is_some_and(str::is_empty)
    {
        payload["meetingInfo"] = serde_json::Value::Null;
    }
    if let Some(req) = payload
        .get_mut("conversationRequest")
        .and_then(|r| r.as_object_mut())
    {
        req.insert("applicationType".into(), APPLICATION_TYPE.into());
    }
    if let Some(attach) = payload.get_mut("attach").and_then(|a| a.as_object_mut()) {
        attach.insert("applicationType".into(), APPLICATION_TYPE.into());
    }
}

/// A personal meeting's `teams.live.com/meet/<ID>?p=<passcode>` link.
pub fn meet_link(code: &str, passcode: &str) -> String {
    if passcode.is_empty() {
        format!("{MEET_LINK_BASE}{code}")
    } else {
        format!("{MEET_LINK_BASE}{code}?p={passcode}")
    }
}

/// A free account's meeting limits (minutes, people) from the authz
/// response's `consumerLicenseDetails` (`teamsFree` or top level), with
/// Teams' defaults when they're missing. None for a subscriber whose
/// limits the response doesn't give (Microsoft 365 Personal or Family).
pub fn meeting_limits(license: Option<&serde_json::Value>) -> (u64, u64) {
    let get = |k: &str| {
        license.and_then(|l| {
            l.pointer(&format!("/teamsFree/{k}"))
                .or_else(|| l.get(k))
                .and_then(|v| v.as_u64())
        })
    };
    (
        get("maxMeetingDurationMinutes").unwrap_or(FREE_MEETING_MINUTES),
        get("maxMeetingParticipants").unwrap_or(FREE_MEETING_PARTICIPANTS),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn personal_requests_carry_the_skype_token() {
        let h = auth_headers_for(true, "tok");
        assert_eq!(h.get("X-Skypetoken").unwrap(), "tok");
        assert!(h.get("Authorization").is_none());
        let w = auth_headers_for(false, "ic3");
        assert_eq!(w.get("Authorization").unwrap(), "Bearer ic3");
        assert!(w.get("X-Skypetoken").is_none());
    }

    #[test]
    fn personal_conversation_requests_name_tfl() {
        let mut p = serde_json::json!({"conversationRequest": {"subject": null}});
        mark_application_for(&mut p);
        assert_eq!(p["conversationRequest"]["applicationType"], "TFL");
        // An incoming call's attach (captured from Teams free's web client).
        let mut a = serde_json::json!({"attach": {"requireMediaContent": false}});
        mark_application_for(&mut a);
        assert_eq!(a["attach"]["applicationType"], "TFL");
    }

    #[test]
    fn personal_free_limits_from_the_license() {
        let l = serde_json::json!({"teamsFree": {"maxMeetingDurationMinutes": 60, "maxMeetingParticipants": 100}});
        assert_eq!(meeting_limits(Some(&l)), (60, 100));
        let top =
            serde_json::json!({"maxMeetingDurationMinutes": 1800, "maxMeetingParticipants": 300});
        assert_eq!(meeting_limits(Some(&top)), (1800, 300));
        assert_eq!(meeting_limits(None), (60, 100));
    }

    #[test]
    fn personal_meet_links() {
        assert_eq!(
            meet_link("931", "Ab"),
            "https://teams.live.com/meet/931?p=Ab"
        );
        assert_eq!(meet_link("931", ""), "https://teams.live.com/meet/931");
    }
}
