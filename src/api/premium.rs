//! Teams Premium's low-friction trial, as Teams' "Unlock Teams Premium"
//! uses it (captured at Teams' start on winpc 2026-11-15): the auth
//! service's `v1.0/lfts/TeamsPremium/policies/selfserve` (PolicyValue 0
//! ENABLED, 1 ONLY_TRIALS_WITHOUT_PAYMENT_METHOD, 2 DISABLED),
//! `…/eligibility/` (`{lowFrictionEntityDetails, ineligibilityReason}`) and
//! Start trial's `POST …/acquire/` with `{}` (202 with the trial, `state` 0
//! while it is set up), then `GET …/entity` until `state` is 1 (active);
//! Cancel trial's `POST …/cancel` (captured on winpc 2026-11-15).
//!
//! The title bar's pill and the ··· menu's row follow Teams' own rule
//! (`entry`, from its TeamsPremiumTitleBar and MoreOptionsMenuItem in
//! MSTeams 26304): the trial as Teams' LFT service reads these replies,
//! the licence details, ECS' premium settings and what the device keeps
//! (when the trial ends, when each pill first showed).

use anyhow::{Context, Result};

const BASE: &str = "https://teams.microsoft.com/api/authsvc/v1.0/lfts/TeamsPremium";

/// The trial's state (0 setting up, 1 active).
pub fn entity_state(entity: &serde_json::Value) -> Option<i64> {
    entity.get("state").and_then(|s| s.as_i64())
}

/// Your trial now (`GET …/entity`), if you have one.
pub async fn entity(http: &reqwest::Client) -> Result<Option<serde_json::Value>> {
    let token = token().await?;
    let resp = request(
        http,
        reqwest::Method::GET,
        &format!("{BASE}/entity"),
        &token,
        "getLowFrictionTrialEntity",
    )
    .send()
    .await
    .context("Trial")?;
    if resp.status() == reqwest::StatusCode::NOT_FOUND
        || resp.status() == reqwest::StatusCode::CONFLICT
    {
        return Ok(None);
    }
    let v: serde_json::Value = resp
        .error_for_status()
        .context("Trial")?
        .json()
        .await
        .context("Trial reply")?;
    Ok(v.get("lowFrictionEntityDetails")
        .filter(|e| !e.is_null())
        .cloned())
}

/// Cancel trial (Teams: "Your trial will cancel within 24 hours.").
pub async fn cancel(http: &reqwest::Client) -> Result<()> {
    let token = token().await?;
    // As Teams: a POST with no body; the reply is the trial, now state 2.
    let resp = request(
        http,
        reqwest::Method::POST,
        &format!("{BASE}/cancel"),
        &token,
        "cancelLowFrictionTrialLicense",
    )
    .send()
    .await
    .context("Cancel trial")?;
    anyhow::ensure!(
        resp.status().is_success(),
        "Cancel trial: HTTP {}",
        resp.status().as_u16()
    );
    Ok(())
}

async fn token() -> Result<String> {
    crate::auth::oauth::access_token_for("https://api.spaces.skype.com/.default").await
}

fn request(
    http: &reqwest::Client,
    method: reqwest::Method,
    url: &str,
    token: &str,
    scenario: &str,
) -> reqwest::RequestBuilder {
    http.request(method, url)
        .bearer_auth(token)
        .header("Cache-control", "no-cache, no-store")
        .header("Accept", "application/json")
        .header(
            "Prefer",
            "exchange.behavior=\"ApplicationData,SubstrateFiles\"",
        )
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

/// The tenant's self-serve policy ("ENABLED",
/// "ONLY_TRIALS_WITHOUT_PAYMENT_METHOD" or "DISABLED"; "" when the
/// service says no, as Teams' FORBIDDEN or THROTTLED).
pub async fn policy(http: &reqwest::Client) -> Result<String> {
    let token = token().await?;
    let resp = request(
        http,
        reqwest::Method::GET,
        &format!("{BASE}/policies/selfserve"),
        &token,
        "getLowFrictionTrialPolicy",
    )
    .send()
    .await
    .context("Trial policy")?;
    if !resp.status().is_success() {
        return Ok(String::new());
    }
    let v: serde_json::Value = resp.json().await.context("Trial policy reply")?;
    Ok(v["PolicyValue"]
        .as_i64()
        .map(policy_name)
        .unwrap_or_default()
        .to_string())
}

/// Your trial as Teams reads it: the eligibility reply, or (with a
/// Premium licence or the trial's) the entity reply, as Teams' LFT
/// service picks.
pub async fn trial(http: &reqwest::Client, licensed: bool) -> Result<Option<Trial>> {
    let token = token().await?;
    let (url, scenario) = if licensed {
        (format!("{BASE}/entity"), "getLowFrictionTrialEntity")
    } else {
        (
            format!("{BASE}/eligibility/"),
            "getLowFrictionTrialEligibility",
        )
    };
    let resp = request(http, reqwest::Method::GET, &url, &token, scenario)
        .send()
        .await
        .context("Trial")?;
    let status = resp.status().as_u16();
    let body: serde_json::Value = resp.json().await.unwrap_or_default();
    Ok(if licensed {
        Trial::from_entity(status, &body)
    } else {
        Trial::from_eligibility(status, &body)
    })
}

/// Start trial: acquire the low-friction trial licence.
pub async fn acquire(http: &reqwest::Client) -> Result<serde_json::Value> {
    let token = token().await?;
    let resp = request(
        http,
        reqwest::Method::POST,
        &format!("{BASE}/acquire/"),
        &token,
        "acquireLowFrictionTrialLicense",
    )
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

/// Teams' view of your low-friction trial (its LowFrictionTrial: the
/// eligibility or entity reply as its LFT service turns it into one).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Trial {
    pub is_eligible: bool,
    pub end_date: Option<String>,
    /// "Pending", "Active" or "Inactive" (Teams' order of the entity's
    /// `state` 0, 1, 2); empty when the reply has none.
    pub status: String,
    /// "EXPIRED_LFT" or "COMMERCE_HARD_BLOCK" (Teams' order of the 403
    /// reply's numeric `ineligibilityReason`).
    pub ineligibility_reason: Option<String>,
}

const TRIAL_STATUS: [&str; 3] = ["Pending", "Active", "Inactive"];
const INELIGIBILITY: [&str; 2] = ["EXPIRED_LFT", "COMMERCE_HARD_BLOCK"];

impl Trial {
    /// Teams' reading of a reply body with a trial in it (its `bj`).
    pub fn from_details(body: &serde_json::Value) -> Self {
        let entity = body
            .get("lowFrictionEntityDetails")
            .filter(|e| !e.is_null());
        let end_date = entity
            .and_then(|e| e.get("endDate"))
            .and_then(|d| d.as_str())
            .map(str::to_string);
        let state = entity.and_then(|e| e.get("state")).and_then(|s| s.as_u64());
        let status_of = |s: u64| TRIAL_STATUS.get(s as usize).copied().unwrap_or_default();
        if let Some(reason) = body.get("ineligibilityReason").and_then(|r| r.as_u64()) {
            // As Teams: a state of 0 (falsy) reads as Inactive here.
            return Self {
                is_eligible: false,
                end_date,
                status: match state {
                    Some(s) if s != 0 => status_of(s),
                    _ => "Inactive",
                }
                .to_string(),
                ineligibility_reason: INELIGIBILITY.get(reason as usize).map(|r| r.to_string()),
            };
        }
        Self {
            is_eligible: false,
            status: state.map(status_of).unwrap_or_default().to_string(),
            end_date,
            ineligibility_reason: None,
        }
    }

    /// The eligibility reply: 200 eligible, 403 with the trial you had.
    pub fn from_eligibility(status: u16, body: &serde_json::Value) -> Option<Self> {
        match status {
            200 => Some(Self {
                is_eligible: true,
                status: "Inactive".into(),
                ..Default::default()
            }),
            403 => Some(Self::from_details(body)),
            _ => None,
        }
    }

    /// The entity reply: 200 your trial, 404 or 409 none (Inactive).
    pub fn from_entity(status: u16, body: &serde_json::Value) -> Option<Self> {
        match status {
            200 => Some(Self::from_details(body)),
            404 | 409 => Some(Self {
                status: "Inactive".into(),
                ..Default::default()
            }),
            _ => None,
        }
    }

    /// Ended: used up, or inactive with an end date.
    pub fn is_ended(&self) -> bool {
        self.ineligibility_reason.as_deref() == Some("EXPIRED_LFT")
            || (self.status == "Inactive" && self.end_date.is_some())
    }

    /// Days left in an active trial: from today to the end date's day (in
    /// your time zone), as Teams counts them.
    pub fn remaining_days(&self, today: jiff::civil::Date, tz: &jiff::tz::TimeZone) -> Option<i64> {
        if self.status != "Active" {
            return None;
        }
        let end = local_day(self.end_date.as_deref()?, tz)?;
        let days = crate::clock::days_between(today, end);
        (days >= 0).then_some(days)
    }
}

/// An ISO time's day in your time zone (Teams' `new Date(x)
/// .toDateString()`). A time without an offset (the eligibility reply's
/// "2027-01-15T01:42:45.9200065") is local time to JavaScript, so its day
/// is its own.
pub fn local_day(iso: &str, tz: &jiff::tz::TimeZone) -> Option<jiff::civil::Date> {
    match crate::clock::parse_instant(iso) {
        Some(t) => Some(t.to_zoned_datetime(tz.clone()).date()),
        None => {
            let part = |r: std::ops::Range<usize>| iso.get(r)?.parse::<i16>().ok();
            if iso.get(4..5) != Some("-") || iso.get(7..8) != Some("-") {
                return None;
            }
            jiff::civil::Date::new(part(0..4)?, part(5..7)? as i8, part(8..10)? as i8).ok()
        }
    }
}

/// Teams Premium's ECS settings for its title bar entry (premium
/// namespace).
#[derive(Debug, Clone, Default)]
pub struct EntryConfig {
    /// enableTeamsPremiumGlobalEntry
    pub global_entry: bool,
    /// enableLazyEligibilityCheckGlobalEntry
    pub lazy_check: bool,
    /// enableDtbPolicyCheck
    pub policy_check: bool,
    /// enableTeamsPremiumPolicyDisabledGlobalEntry
    pub policy_disabled_entry: bool,
    /// enableTeamsPremiumLicensedBenefitsGlobal
    pub licensed_benefits: bool,
    /// premiumTitleBarConfig
    pub promo_days: Option<i64>,
    pub promo_start: Option<String>,
    pub promo_end: Option<String>,
    pub post_trial_promo_days: Option<i64>,
}

impl EntryConfig {
    pub fn from_ecs(premium: &serde_json::Value) -> Self {
        let flag = |k: &str| premium.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
        let bar = premium
            .get("premiumTitleBarConfig")
            .map(|v| match v {
                serde_json::Value::String(s) => serde_json::from_str(s).unwrap_or_default(),
                v => v.clone(),
            })
            .unwrap_or_default();
        let num = |k: &str| bar.get(k).and_then(|v| v.as_i64());
        let text = |k: &str| bar.get(k).and_then(|v| v.as_str()).map(str::to_string);
        Self {
            global_entry: flag("enableTeamsPremiumGlobalEntry"),
            lazy_check: flag("enableLazyEligibilityCheckGlobalEntry"),
            policy_check: flag("enableDtbPolicyCheck"),
            policy_disabled_entry: flag("enableTeamsPremiumPolicyDisabledGlobalEntry"),
            licensed_benefits: flag("enableTeamsPremiumLicensedBenefitsGlobal"),
            promo_days: num("promoDurationInDays"),
            promo_start: text("promoStartDate"),
            promo_end: text("promoEndDate"),
            post_trial_promo_days: num("postTrialPromoDurationInDays"),
        }
    }
}

/// What Teams keeps on the device for its entry (localStorage, per
/// account): the trial's end date once its "N days left" pill showed
/// (TeamsPremiumUserTrialEndDateGlobalEntryPoint) and when each promo pill
/// first showed (TeamsPremiumUserFirstView…GlobalEntryPoint), ISO times.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct EntryMarks {
    pub trial_end: Option<String>,
    pub first_view_pre: Option<String>,
    pub first_view_post: Option<String>,
}

/// The title bar's pill.
#[derive(Debug, Clone, PartialEq)]
pub enum Pill {
    /// "N days left".
    DaysLeft(i64),
    /// "Get Premium" after a trial ended.
    PostTrial,
    /// "Get Premium" before a trial.
    PreTrial,
}

/// The ··· menu's Premium row.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MenuRow {
    /// "Unlock Teams Premium" (the trial dialog).
    Unlock,
    /// "Teams Premium benefits" (in a trial).
    Benefits,
    /// "Get Teams Premium" (after a trial, or trials turned off: the
    /// licence request dialog).
    Get,
}

/// Teams Premium's entry points as Teams shows them.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub pill: Option<Pill>,
    pub menu: Option<MenuRow>,
    /// Teams' separate "Teams Premium benefits" row for a Premium licence
    /// not in an active trial.
    pub benefits_row: bool,
    /// The marks after showing it (Teams writes them as the pill shows).
    pub marks: EntryMarks,
}

/// Inside `days` days from the day `first` (an ISO time) was, or never
/// seen (Teams' `i9`).
fn within(
    first: Option<&str>,
    days: i64,
    today: jiff::civil::Date,
    tz: &jiff::tz::TimeZone,
) -> bool {
    let Some(start) = first.and_then(|f| local_day(f, tz)) else {
        return true;
    };
    start <= today && crate::clock::days_between(start, today) <= days
}

/// Teams' title bar pill and ··· menu row for Premium (its
/// TeamsPremiumTitleBar and TeamsPremiumMoreOptionsMenuItem, MSTeams
/// 26304): from the trial (`None` when it couldn't be read), the
/// self-serve policy ("ENABLED", "ONLY_TRIALS_WITHOUT_PAYMENT_METHOD",
/// "DISABLED" or "" unknown), the licence details (isTPManagement,
/// isTeamsPremiumSelfAssigned), ECS and the device's marks.
#[allow(clippy::too_many_arguments)]
pub fn entry(
    trial: Option<&Trial>,
    policy: &str,
    tp_management: bool,
    self_assigned: bool,
    cfg: &EntryConfig,
    marks: &EntryMarks,
    now: jiff::Timestamp,
    tz: &jiff::tz::TimeZone,
) -> Entry {
    let today = now.to_zoned_datetime(tz.clone()).date();
    let policy_disabled = policy == "DISABLED";
    let policy_active = !policy.is_empty() && !policy_disabled;
    // Teams' trial query is skipped for a Premium licence that isn't the
    // trial's, a trial licence without Premium management, or trials
    // turned off; else when the caller skips it and it isn't your active
    // trial (self-assigned).
    let blocked =
        (tp_management && !self_assigned) || (!tp_management && self_assigned) || policy_disabled;
    let trial_if = |skip: bool| {
        if (skip && !self_assigned) || blocked {
            None
        } else {
            trial
        }
    };
    let local_end = marks.trial_end.as_deref().and_then(|e| local_day(e, tz));
    let local_expired = local_end.is_some_and(|e| today > e);

    // The pill.
    let post_active = cfg
        .post_trial_promo_days
        .is_some_and(|d| within(marks.first_view_post.as_deref(), d, today, tz));
    let mut pre_active = cfg
        .promo_days
        .is_some_and(|d| within(marks.first_view_pre.as_deref(), d, today, tz));
    if let Some(end) = &cfg.promo_end {
        let started = cfg
            .promo_start
            .as_deref()
            .and_then(|s| local_day(s, tz))
            .is_none_or(|s| s <= today);
        pre_active = started && local_day(end, tz).is_some_and(|e| e > today);
    }
    let lazy = cfg.lazy_check && (!cfg.policy_check || policy_active);
    let bar_trial = trial_if(
        !cfg.global_entry
            || (!pre_active && !post_active)
            || cfg.lazy_check
            || policy_disabled
            || local_end.is_some(),
    );
    let mut out = marks.clone();
    let stamp = now.to_string();
    let days = bar_trial
        .and_then(|t| t.remaining_days(today, tz))
        .filter(|d| *d > 0);
    let show_post = (post_active && local_expired) || bar_trial.is_some_and(Trial::is_ended);
    let show_pre = pre_active
        && (bar_trial.is_some_and(|t| t.is_eligible) || lazy)
        && !tp_management
        && local_end.is_none();
    let pill = if let Some(d) = days {
        if out.trial_end.is_none() {
            out.trial_end = bar_trial.and_then(|t| t.end_date.clone());
        }
        Some(Pill::DaysLeft(d))
    } else if show_post {
        out.first_view_post.get_or_insert_with(|| stamp.clone());
        Some(Pill::PostTrial)
    } else if show_pre {
        out.first_view_pre.get_or_insert_with(|| stamp.clone());
        Some(Pill::PreTrial)
    } else {
        None
    };

    // The menu row.
    let menu_trial = trial_if(!cfg.global_entry || cfg.lazy_check || policy_disabled);
    let post_trial = menu_trial.is_some_and(Trial::is_ended) || local_expired;
    let in_trial = menu_trial
        .is_some_and(|t| t.status == "Active" && t.remaining_days(today, tz).unwrap_or(0) > 0);
    let disabled_row = cfg.policy_disabled_entry && policy_disabled;
    let shown = menu_trial.is_some_and(|t| t.is_eligible)
        || in_trial
        || disabled_row
        || (lazy && !tp_management)
        || post_trial;
    let menu = shown.then(|| {
        if disabled_row || post_trial {
            MenuRow::Get
        } else if in_trial {
            MenuRow::Benefits
        } else {
            MenuRow::Unlock
        }
    });
    let benefits_row = cfg.licensed_benefits
        && tp_management
        && !(self_assigned && trial.is_some_and(|t| t.status == "Active"));
    Entry {
        pill,
        menu,
        benefits_row,
        marks: out,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ecs() -> EntryConfig {
        // ost-test1's ECS premium settings (2026-11-27).
        EntryConfig::from_ecs(&serde_json::json!({
            "enableDtbPolicyCheck": true,
            "enableTeamsPremiumGlobalEntry": true,
            "enableTeamsPremiumLicensedBenefitsGlobal": true,
            "premiumTitleBarConfig": {"postTrialPromoDurationInDays": 14, "promoDurationInDays": 14, "promoEndDate": "2026-05-10T07:00:00Z"}
        }))
    }

    fn at(iso: &str) -> jiff::Timestamp {
        crate::clock::parse_instant(iso).unwrap()
    }

    const END: &str = "2027-01-15T01:42:45.9200065Z";

    /// ost-test1 after its cancelled trial: eligibility 403 with the trial.
    fn ended() -> Trial {
        Trial::from_eligibility(
            403,
            &serde_json::json!({"ineligibilityReason": 0, "lowFrictionEntityDetails": {"state": 2, "endDate": END}}),
        )
        .unwrap()
    }

    #[test]
    fn an_ended_trial_reads_as_teams_reads_it() {
        let t = ended();
        assert_eq!(t.status, "Inactive");
        assert_eq!(t.ineligibility_reason.as_deref(), Some("EXPIRED_LFT"));
        assert!(t.is_ended() && !t.is_eligible);
        let ok = Trial::from_eligibility(200, &serde_json::json!({})).unwrap();
        assert!(ok.is_eligible && !ok.is_ended());
        let none = Trial::from_entity(404, &serde_json::Value::Null).unwrap();
        assert!(!none.is_ended());
    }

    #[test]
    fn ended_trial_on_a_device_that_showed_the_trial() {
        // winpc: its trial's end date was kept while "N days left" showed;
        // until that day passes there is no pill, and one menu row.
        let tz = jiff::tz::TimeZone::UTC;
        let marks = EntryMarks {
            trial_end: Some(END.into()),
            ..Default::default()
        };
        let e = entry(
            Some(&ended()),
            "ENABLED",
            false,
            false,
            &ecs(),
            &marks,
            at("2026-11-27T18:00:00Z"),
            &tz,
        );
        assert_eq!(e.pill, None);
        assert_eq!(e.menu, Some(MenuRow::Get));
        assert!(!e.benefits_row);
        assert_eq!(e.marks, marks);
        // The day after it ends, "Get Premium" for 14 days from then.
        let e = entry(
            None,
            "ENABLED",
            false,
            false,
            &ecs(),
            &marks,
            at("2027-01-16T12:00:00Z"),
            &tz,
        );
        assert_eq!(e.pill, Some(Pill::PostTrial));
        assert_eq!(e.menu, Some(MenuRow::Get));
    }

    #[test]
    fn end_dates_without_an_offset_are_local() {
        let tz = jiff::tz::TimeZone::fixed(jiff::tz::Offset::from_seconds(-8 * 3600).unwrap());
        assert_eq!(
            local_day("2027-01-15T01:42:45.9200065", &tz),
            Some(jiff::civil::date(2027, 1, 15))
        );
        assert_eq!(local_day(END, &tz), Some(jiff::civil::date(2027, 1, 14)));
        assert_eq!(local_day("soon", &tz), None);
    }

    #[test]
    fn ended_trial_on_a_new_device() {
        // testpc1: never saw the trial, so "Get Premium" shows for 14 days
        // from the first time it does.
        let tz = jiff::tz::TimeZone::UTC;
        let e = entry(
            Some(&ended()),
            "ENABLED",
            false,
            false,
            &ecs(),
            &EntryMarks::default(),
            at("2026-11-27T17:43:47Z"),
            &tz,
        );
        assert_eq!(e.pill, Some(Pill::PostTrial));
        assert_eq!(e.menu, Some(MenuRow::Get));
        let first = e.marks.first_view_post.clone().unwrap();
        assert!(first.starts_with("2026-11-27T17:43:47"), "{first}");
        let later = |iso: &str| {
            entry(
                Some(&ended()),
                "ENABLED",
                false,
                false,
                &ecs(),
                &e.marks,
                at(iso),
                &tz,
            )
            .pill
        };
        assert_eq!(later("2026-12-11T10:00:00Z"), Some(Pill::PostTrial));
        assert_eq!(later("2026-12-12T10:00:00Z"), None);
    }

    #[test]
    fn in_a_trial_and_just_after_cancelling() {
        let tz = jiff::tz::TimeZone::UTC;
        let active = Trial::from_entity(
            200,
            &serde_json::json!({"lowFrictionEntityDetails": {"state": 1, "endDate": END}}),
        )
        .unwrap();
        let e = entry(
            Some(&active),
            "ENABLED",
            true,
            true,
            &ecs(),
            &EntryMarks::default(),
            at("2026-11-16T02:00:00Z"),
            &tz,
        );
        assert_eq!(e.pill, Some(Pill::DaysLeft(60)));
        assert_eq!(e.menu, Some(MenuRow::Benefits));
        assert!(!e.benefits_row);
        assert_eq!(e.marks.trial_end.as_deref(), Some(END));
        // Cancelled, the trial licence still assigned (until the service
        // removes it): "Get Premium", Get Teams Premium and Teams Premium
        // benefits, as Teams showed on 2026-11-15.
        let cancelled = Trial::from_entity(
            200,
            &serde_json::json!({"lowFrictionEntityDetails": {"state": 2, "endDate": END}}),
        )
        .unwrap();
        let e = entry(
            Some(&cancelled),
            "ENABLED",
            true,
            true,
            &ecs(),
            &e.marks,
            at("2026-11-16T03:00:00Z"),
            &tz,
        );
        assert_eq!(e.pill, Some(Pill::PostTrial));
        assert_eq!(e.menu, Some(MenuRow::Get));
        assert!(e.benefits_row);
    }

    #[test]
    fn before_a_trial() {
        let tz = jiff::tz::TimeZone::UTC;
        let ok = Trial::from_eligibility(200, &serde_json::json!({})).unwrap();
        // The promo ended (promoEndDate 2026-05-10): no pill, the row.
        let e = entry(
            Some(&ok),
            "ENABLED",
            false,
            false,
            &ecs(),
            &EntryMarks::default(),
            at("2026-11-27T12:00:00Z"),
            &tz,
        );
        assert_eq!(e.pill, None);
        assert_eq!(e.menu, Some(MenuRow::Unlock));
        // During a promo: "Get Premium".
        let mut cfg = ecs();
        cfg.promo_end = Some("2026-12-31T00:00:00Z".into());
        let e = entry(
            Some(&ok),
            "ENABLED",
            false,
            false,
            &cfg,
            &EntryMarks::default(),
            at("2026-11-27T12:00:00Z"),
            &tz,
        );
        assert_eq!(e.pill, Some(Pill::PreTrial));
        // Trials turned off: nothing.
        let e = entry(
            Some(&ok),
            "DISABLED",
            false,
            false,
            &ecs(),
            &EntryMarks::default(),
            at("2026-11-27T12:00:00Z"),
            &tz,
        );
        assert_eq!((e.pill, e.menu), (None, None));
    }

    #[test]
    fn entity_state_reads() {
        let e = serde_json::json!({"endDate": END, "state": 1});
        assert_eq!(entity_state(&e), Some(1));
    }
}
