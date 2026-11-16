//! Teams Premium's low-friction trial, as Teams' "Unlock Teams Premium"
//! uses it (captured at Teams' start on winpc 2026-11-15): the auth
//! service's `v1.0/lfts/TeamsPremium/policies/selfserve` (PolicyValue 0
//! ENABLED, 1 ONLY_TRIALS_WITHOUT_PAYMENT_METHOD, 2 DISABLED),
//! `…/eligibility/` (`{lowFrictionEntityDetails, ineligibilityReason}`) and
//! Start trial's `POST …/acquire/` with `{}`.

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
    let elig: serde_json::Value = request(http, reqwest::Method::GET, &format!("{BASE}/eligibility/"), &token, "getLowFrictionTrialEligibility")
        .send()
        .await
        .context("Trial eligibility")?
        .error_for_status()
        .context("Trial eligibility")?
        .json()
        .await
        .context("Trial eligibility reply")?;
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
}
