//! Teams Premium's low-friction trial, as Teams' "Unlock Teams Premium"
//! uses it (captured at Teams' start on winpc 2026-11-15): the auth
//! service's `v1.0/lfts/TeamsPremium/policies/selfserve` (PolicyValue 0
//! ENABLED, 1 ONLY_TRIALS_WITHOUT_PAYMENT_METHOD, 2 DISABLED),
//! `…/eligibility/` (`{lowFrictionEntityDetails, ineligibilityReason}`) and
//! Start trial's `POST …/acquire/` with `{}` (202 with the trial, `state` 0
//! while it is set up), then `GET …/entity` until `state` is 1 (active);
//! Cancel trial's `POST …/cancel` (captured on winpc 2026-11-15).

use anyhow::{Context, Result};

const BASE: &str = "https://teams.microsoft.com/api/authsvc/v1.0/lfts/TeamsPremium";

/// Whether you may start the trial, and whether one is already yours.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct TrialState {
    /// The tenant's self-serve policy: "ENABLED",
    /// "ONLY_TRIALS_WITHOUT_PAYMENT_METHOD" or "DISABLED".
    pub policy: String,
    /// No reason against starting it.
    pub eligible: bool,
    pub ineligibility_reason: String,
    /// A trial you already have (its details, as the service gives them).
    pub entity: Option<serde_json::Value>,
}

impl TrialState {
    /// Teams offers "Unlock Teams Premium" while the policy allows trials
    /// and you are eligible.
    pub fn offered(&self) -> bool {
        self.policy != "DISABLED" && !self.policy.is_empty() && self.eligible && self.entity.is_none()
    }
}

/// The trial's state (0 setting up, 1 active).
pub fn entity_state(entity: &serde_json::Value) -> Option<i64> {
    entity.get("state").and_then(|s| s.as_i64())
}

/// Whole days left in a trial (Teams' "60 days left": the time to its
/// `endDate`, rounded up).
pub fn days_left(entity: &serde_json::Value, now: chrono::DateTime<chrono::Utc>) -> Option<i64> {
    let end = chrono::DateTime::parse_from_rfc3339(entity.get("endDate")?.as_str()?).ok()?;
    let secs = (end.with_timezone(&chrono::Utc) - now).num_seconds();
    Some(if secs <= 0 { 0 } else { (secs + 86_399) / 86_400 })
}

/// Your trial now (`GET …/entity`), if you have one.
pub async fn entity(http: &reqwest::Client) -> Result<Option<serde_json::Value>> {
    let token = token().await?;
    let resp = request(http, reqwest::Method::GET, &format!("{BASE}/entity"), &token, "getLowFrictionTrialEntity")
        .send()
        .await
        .context("Trial")?;
    if resp.status() == reqwest::StatusCode::NOT_FOUND || resp.status() == reqwest::StatusCode::CONFLICT {
        return Ok(None);
    }
    let v: serde_json::Value = resp.error_for_status().context("Trial")?.json().await.context("Trial reply")?;
    Ok(v.get("lowFrictionEntityDetails").filter(|e| !e.is_null()).cloned())
}

/// Cancel trial (Teams: "Your trial will cancel within 24 hours.").
pub async fn cancel(http: &reqwest::Client) -> Result<()> {
    let token = token().await?;
    // As Teams: a POST with no body; the reply is the trial, now state 2.
    let resp = request(http, reqwest::Method::POST, &format!("{BASE}/cancel"), &token, "cancelLowFrictionTrialLicense")
        .send()
        .await
        .context("Cancel trial")?;
    anyhow::ensure!(resp.status().is_success(), "Cancel trial: HTTP {}", resp.status().as_u16());
    Ok(())
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await
}

fn request(http: &reqwest::Client, method: reqwest::Method, url: &str, token: &str, scenario: &str) -> reqwest::RequestBuilder {
    http.request(method, url)
        .bearer_auth(token)
        .header("Cache-control", "no-cache, no-store")
        .header("Accept", "application/json")
        .header("Prefer", "exchange.behavior=\"ApplicationData,SubstrateFiles\"")
        .header("ScenarioTag", scenario)
}

/// The self-serve policy name for PolicyValue.
pub fn policy_name(v: i64) -> &'static str {
    match v {
        0 => "ENABLED",
        1 => "ONLY_TRIALS_WITHOUT_PAYMENT_METHOD",
        _ => "DISABLED",
    }
}

/// The trial's policy and your eligibility.
pub async fn state(http: &reqwest::Client) -> Result<TrialState> {
    let token = token().await?;
    let policy: serde_json::Value = request(http, reqwest::Method::GET, &format!("{BASE}/policies/selfserve"), &token, "getLowFrictionTrialPolicy")
        .send()
        .await
        .context("Trial policy")?
        .error_for_status()
        .context("Trial policy")?
        .json()
        .await
        .context("Trial policy reply")?;
    let resp = request(http, reqwest::Method::GET, &format!("{BASE}/eligibility/"), &token, "getLowFrictionTrialEligibility")
        .send()
        .await
        .context("Trial eligibility")?;
    // Forbidden once your trial is used up (after Cancel trial).
    let elig: serde_json::Value = if resp.status() == reqwest::StatusCode::FORBIDDEN {
        serde_json::json!({ "ineligibilityReason": "FORBIDDEN" })
    } else {
        resp.error_for_status().context("Trial eligibility")?.json().await.context("Trial eligibility reply")?
    };
    Ok(state_from(&policy, &elig))
}

/// The state from the policy and eligibility replies.
pub fn state_from(policy: &serde_json::Value, elig: &serde_json::Value) -> TrialState {
    let reason = elig["ineligibilityReason"].as_str().unwrap_or_default().to_string();
    TrialState {
        policy: policy["PolicyValue"].as_i64().map(policy_name).unwrap_or_default().to_string(),
        eligible: reason.is_empty(),
        ineligibility_reason: reason,
        entity: elig.get("lowFrictionEntityDetails").filter(|e| !e.is_null()).cloned(),
    }
}

/// Start trial: acquire the low-friction trial licence.
pub async fn acquire(http: &reqwest::Client) -> Result<serde_json::Value> {
    let token = token().await?;
    let resp = request(http, reqwest::Method::POST, &format!("{BASE}/acquire/"), &token, "acquireLowFrictionTrialLicense")
        .header("Content-Type", "application/json")
        .body("{}")
        .send()
        .await
        .context("Start trial")?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    anyhow::ensure!(status.is_success(), "Start trial: HTTP {}", status.as_u16());
    Ok(serde_json::from_str(&text).unwrap_or(serde_json::Value::Null))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trial_state_from_replies() {
        let s = state_from(&serde_json::json!({"PolicyValue": 0}), &serde_json::json!({"lowFrictionEntityDetails": null, "ineligibilityReason": null}));
        assert_eq!(s.policy, "ENABLED");
        assert!(s.eligible && s.offered());
        let off = state_from(&serde_json::json!({"PolicyValue": 2}), &serde_json::json!({}));
        assert!(!off.offered());
        let no = state_from(&serde_json::json!({"PolicyValue": 0}), &serde_json::json!({"ineligibilityReason": "AlreadyLicensed"}));
        assert!(!no.offered());
    }

    #[test]
    fn days_left_round_up() {
        let e = serde_json::json!({"startDate": "2026-11-16T01:42:49Z", "endDate": "2027-01-15T01:42:45.9200065Z", "state": 1});
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-16T01:50:00Z").unwrap().with_timezone(&chrono::Utc);
        assert_eq!(days_left(&e, now), Some(60));
        assert_eq!(entity_state(&e), Some(1));
    }
}
