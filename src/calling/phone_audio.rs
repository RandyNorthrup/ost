//! Teams' phone audio for meetings (Audio Conferencing): the meeting's
//! dial-in details, whether Phone audio is offered, and "Call me" (Teams
//! calls your phone and puts it in the meeting for you).
//!
//! Measured in Teams on the web as ost-test1 (2026-11-16, a solo scheduled
//! meeting) and read from Teams' code (pstn-dialog-manager, the calling
//! meeting info panel's dial-in block, the PSTN state provider and the
//! web calling stack's call me back):
//!
//! - **Dial-in details** are the conversation's
//!   `meetingDetails.pstnDetails`: `{acpMcuInfo: {settings: {tollNumber,
//!   tollFreeNumber, participantPasscode}}, dialinUrl, …}` (numbers are
//!   digits without "+"). Teams shows them only with both a toll number and
//!   a conference ID: "+18723339415 (Toll)", "+1… (Toll-Free)", "Get local
//!   numbers" (the `dialinUrl`), "Conference ID: 975 755 048 #".
//! - **Phone audio is offered** (Teams' `pstnStateProvider`) when the
//!   meeting's capability allows PSTN conferencing
//!   (`meetingCapability.allowPstnConferencing`), its dial-out type isn't
//!   "Disabled" (`pstnConferencingDialOutType`), it has dial-in details,
//!   and you're neither anonymous nor in an end-to-end encrypted meeting.
//!   Dial-in is `allowPstnConferencing`; "Call me" (dial-out) is the
//!   dial-out type not being "Disabled" (anonymous users and broadcast
//!   attendees need `allowAnonymousUsersToDialOut`).
//! - **Call me** asks the conversation to add your phone:
//!   `POST links.addParticipantAndModality` with `participants.to =
//!   [{id: "4:<number>", assertedId: <your participant id>}]`, the group
//!   chat and the add-participant callbacks. The answer comes back as
//!   `conversation/addParticipantSuccess/` or `…Failure/` (120 s at most).
//! - **The number** goes through your dial plan's normalization rules
//!   (`policySettings.dialPlanPolicy`), as Teams' `PhoneNumberNormalizer`.

use serde_json::{Value, json};

/// The meeting's dial-in details (`meetingDetails.pstnDetails`).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DialIn {
    /// Digits without "+", e.g. "18723339415".
    pub toll: String,
    pub toll_free: String,
    /// The conference ID ("participantPasscode"), digits.
    pub conference_id: String,
    /// "Get local numbers" / "Find a local number".
    pub local_numbers_url: String,
}

fn meeting_details(json: &Value) -> Option<&Value> {
    [
        "/meetingDetails",
        "/conversationResponse/meetingDetails",
        "/conversation/meetingDetails",
        "/body/meetingDetails",
        "/body/conversationUpdate/meetingDetails",
        "/conversationUpdate/meetingDetails",
    ]
    .iter()
    .find_map(|p| json.pointer(p))
    .filter(|d| d.is_object())
}

/// The dial-in details in a join response or conversation update, as
/// Teams shows them: None without a toll number and conference ID.
pub fn dial_in(json: &Value) -> Option<DialIn> {
    let p = meeting_details(json)?.get("pstnDetails")?;
    let s = p.pointer("/acpMcuInfo/settings")?;
    let text = |v: &Value, k: &str| match v.get(k) {
        Some(Value::String(s)) => s.trim().to_string(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    };
    let d = DialIn {
        toll: text(s, "tollNumber").trim_start_matches('+').to_string(),
        toll_free: text(s, "tollFreeNumber").trim_start_matches('+').to_string(),
        conference_id: text(s, "participantPasscode"),
        local_numbers_url: text(p, "dialinUrl"),
    };
    (!d.toll.is_empty() && !d.conference_id.is_empty()).then_some(d)
}

impl DialIn {
    /// "+18723339415", as Teams writes the number (no grouping).
    pub fn toll_text(&self) -> String {
        format!("+{}", self.toll)
    }

    pub fn toll_free_text(&self) -> String {
        if self.toll_free.is_empty() { String::new() } else { format!("+{}", self.toll_free) }
    }

    /// "Conference ID: 975 755 048 #" (Teams adds a space after every three
    /// digits).
    pub fn conference_text(&self) -> String {
        format!("Conference ID: {}#", group_threes(&self.conference_id))
    }

    /// The links' screen-reader names ("Dial in using toll number + 1 8 7
    /// 2…, conference ID 9 7 5…").
    pub fn toll_aria(&self, toll_free: bool) -> String {
        let spaced = |s: &str| s.chars().map(String::from).collect::<Vec<_>>().join(" ");
        let number = if toll_free { self.toll_free_text() } else { self.toll_text() };
        format!(
            "Dial in using {} number {}, conference ID {}",
            if toll_free { "toll free" } else { "toll" },
            spaced(&number),
            spaced(&self.conference_id)
        )
    }

    pub fn to_json(&self) -> Value {
        json!({
            "toll": self.toll_text(),
            "tollFree": self.toll_free_text(),
            "conferenceId": self.conference_id,
            "conferenceText": self.conference_text(),
            "localNumbersUrl": self.local_numbers_url,
            "tollAria": self.toll_aria(false),
            "tollFreeAria": if self.toll_free.is_empty() { String::new() } else { self.toll_aria(true) },
        })
    }
}

/// Teams' `Ce`: a space after every group of three digits.
fn group_threes(digits: &str) -> String {
    let mut out = String::new();
    let mut run = 0;
    for c in digits.chars() {
        out.push(c);
        if c.is_ascii_digit() {
            run += 1;
            if run == 3 {
                out.push(' ');
                run = 0;
            }
        } else {
            run = 0;
        }
    }
    out
}

/// The dial-in details a Teams meeting invitation carries (its "Dial in by
/// phone" block: `tel:+18723339415,,975755048#` and the "Find a local
/// number" link), for a meeting not joined yet.
pub fn dial_in_from_invite(body_html: &str) -> Option<DialIn> {
    let at = body_html.find("tel:+")?;
    let rest = &body_html[at + 5..];
    let end = rest.find(|c: char| !(c.is_ascii_digit() || c == ',' || c == '#'))?;
    let tel = &rest[..end];
    let (toll, conf) = tel.split_once(",,")?;
    let conference_id = conf.trim_end_matches('#').to_string();
    let local_numbers_url = body_html
        .find("https://dialin.teams")
        .map(|i| {
            let r = &body_html[i..];
            r[..r.find(['"', '\'', '<', ' ']).unwrap_or(r.len())].replace("&amp;", "&")
        })
        .unwrap_or_default();
    let d = DialIn { toll: toll.to_string(), toll_free: String::new(), conference_id, local_numbers_url };
    (!d.toll.is_empty() && !d.conference_id.is_empty() && d.conference_id.bytes().all(|b| b.is_ascii_digit())).then_some(d)
}

/// Whether the meeting offers phone audio, and which kinds.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PhoneAudio {
    /// Teams' `isPSTNEnabled` (the pre-join option, the dialog, Call me).
    pub available: bool,
    /// Dial in with the meeting's numbers.
    pub dial_in: bool,
    /// "Call me" (the meeting calls your phone).
    pub dial_out: bool,
}

/// Teams' PSTN state for a meeting from its join response (or a
/// conversation update carrying `meetingDetails`): `anonymous` for a guest
/// without an account.
pub fn phone_audio(json: &Value, anonymous: bool) -> Option<PhoneAudio> {
    let d = meeting_details(json)?;
    let cap = d.get("meetingCapability")?;
    let flag = |k: &str| cap.get(k).and_then(Value::as_bool).unwrap_or(false);
    let dial_out_type = cap
        .get("pstnConferencingDialOutType")
        .and_then(Value::as_str)
        .unwrap_or("");
    let dial_out_allowed = !dial_out_type.is_empty() && !dial_out_type.eq_ignore_ascii_case("Disabled");
    let allow = flag("allowPstnConferencing");
    let e2ee = flag("meetingEndToEndEncryptionEnabled");
    let anonymous_blocked = anonymous && !flag("allowAnonymousUsersToDialOut");
    let has_details = d.get("pstnDetails").is_some_and(|p| !p.is_null());
    Some(PhoneAudio {
        available: allow && dial_out_allowed && has_details && !anonymous_blocked && !e2ee,
        dial_in: allow,
        dial_out: (dial_out_allowed && !anonymous) || (anonymous && flag("allowAnonymousUsersToDialOut")),
    })
}

/// How long Teams' pre-join waits for the meeting's PSTN details before
/// it decides from the capability alone (ECS `pstnCapabilitiesTimeoutInMs`,
/// 15000).
pub const PSTN_CAPABILITIES_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(15);

/// Teams' pre-join Phone audio (its `pstnStateProvider`, read from Teams
/// on the web 2026-11-16) from the meeting's latest details: the preheated
/// call's join response or a conversation update. `None` while the
/// details can't tell yet: Teams decides only once the meeting's
/// capability is there (with a dial-out type other than "Disabled", or
/// PSTN conferencing not refused) together with its invitation; then
/// Phone audio is offered exactly when [`phone_audio`] says it is
/// available. Held in a lobby the details never get that far (no
/// invitation, no dial-in): see [`prejoin_fallback`].
pub fn prejoin_pstn(json: &Value, anonymous: bool) -> Option<bool> {
    let d = meeting_details(json)?;
    let cap = d.get("meetingCapability").filter(|c| c.is_object())?;
    let dial_out = cap.get("pstnConferencingDialOutType").and_then(Value::as_str).unwrap_or("");
    let dial_out_allowed = !dial_out.is_empty() && !dial_out.eq_ignore_ascii_case("Disabled");
    let refused = cap.get("allowPstnConferencing") == Some(&Value::Bool(false));
    let invitation = d.get("invitation").is_some_and(|i| !i.is_null());
    if !(dial_out_allowed || !refused) || !invitation {
        return None;
    }
    Some(phone_audio(json, anonymous).is_some_and(|p| p.available))
}

/// Teams' pre-join Phone audio when the details didn't settle it within
/// [`PSTN_CAPABILITIES_TIMEOUT`]: the meeting allows PSTN conferencing
/// (Teams' `getPstnDialCapabilities().isDialInEnabled`), from its latest
/// details (`None`: none came).
pub fn prejoin_fallback(json: Option<&Value>) -> bool {
    json.and_then(meeting_details)
        .and_then(|d| d.pointer("/meetingCapability/allowPstnConferencing"))
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

/// Whether a response or conversation update carries the meeting's
/// details (the pre-join keeps the latest).
pub fn has_meeting_details(json: &Value) -> bool {
    meeting_details(json).is_some()
}

/// One of the dial plan's normalization rules.
#[derive(Debug, Clone)]
struct Rule {
    pattern: regex::Regex,
    translation: String,
}

/// Teams' `PhoneNumberNormalizer` with your dial plan
/// (`dialPlanPolicy.normalizationRules`, `ituCountryPrefix`).
#[derive(Debug, Clone, Default)]
pub struct DialPlan {
    rules: Vec<Rule>,
    country_prefix: String,
}

/// A number as the normalizer leaves it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Normalized {
    pub number: String,
    pub normalized: bool,
}

impl DialPlan {
    /// From the dial plan policy (`{normalizationRules: [{pattern,
    /// translation}], ituCountryPrefix}`); rules that aren't valid
    /// patterns are left out, as Teams does.
    pub fn from_policy(policy: &Value) -> Self {
        let rules = policy
            .get("normalizationRules")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|r| {
                let pattern = regex::Regex::new(r.get("pattern")?.as_str()?).ok()?;
                // JavaScript's "$1" is Rust's "${1}".
                let t = r.get("translation")?.as_str()?;
                let translation = regex::Regex::new(r"\$(\d+)").ok()?.replace_all(t, "$${$1}").into_owned();
                Some(Rule { pattern, translation })
            })
            .collect();
        let country_prefix = policy
            .get("ituCountryPrefix")
            .and_then(|v| v.as_str().map(str::to_string).or_else(|| v.as_i64().map(|n| n.to_string())))
            .unwrap_or_default();
        Self { rules, country_prefix }
    }

    pub fn has_rules(&self) -> bool {
        !self.rules.is_empty()
    }

    /// Teams' `normalize`: format characters out, the first matching rule
    /// applied, else (Teams' addCountryCodeDuringNormalization) the
    /// country code put in front of plain digits.
    pub fn normalize(&self, input: &str) -> Normalized {
        let t = remove_format_characters(input);
        for r in &self.rules {
            if r.pattern.is_match(&t) {
                return Normalized { number: r.pattern.replacen(&t, 1, r.translation.as_str()).into_owned(), normalized: true };
            }
        }
        if !t.starts_with('+') && !t.is_empty() && t.bytes().all(|b| b.is_ascii_digit()) {
            let prefix = if self.country_prefix.is_empty() { String::new() } else { format!("+{}", self.country_prefix) };
            return Normalized { normalized: !prefix.is_empty(), number: format!("{prefix}{t}") };
        }
        Normalized { number: t, normalized: false }
    }

    /// Whether Teams enables Call me for this text (`isNormalized`: a
    /// rule normalized it, or it's a possible phone number).
    pub fn can_call(&self, input: &str) -> bool {
        if input.trim().is_empty() {
            return false;
        }
        if self.rules.is_empty() {
            return true;
        }
        self.normalize(input).normalized || is_possible_number(input)
    }

    /// The text Teams puts in the box when it loses focus: "+1
    /// 425-555-0100" for a North American number, the number as typed
    /// otherwise.
    pub fn display(&self, input: &str) -> String {
        if self.rules.is_empty() {
            return input.to_string();
        }
        let n = self.normalize(input);
        // What libphonenumber parses: the normalized number, or one typed
        // in international form.
        let number = if n.normalized {
            n.number
        } else if is_possible_number(input) {
            remove_format_characters(input)
        } else {
            return input.to_string();
        };
        match nanp_display(&number) {
            Some(s) => s,
            None if number.len() > 3 && number.starts_with("+1") && number[2..].bytes().all(|b| b.is_ascii_digit()) => number,
            None => input.to_string(),
        }
    }

    /// The participant id Teams calls: "4:" and the normalized number.
    pub fn phone_mri(&self, input: &str) -> String {
        let n = self.normalize(input);
        let number = if n.normalized { n.number } else { remove_format_characters(input) };
        format!("4:{number}")
    }
}

/// Teams' `removeFormatCharacters`: spaces, brackets, dashes, underscores
/// and slashes out.
pub fn remove_format_characters(s: &str) -> String {
    s.chars().filter(|c| !(c.is_whitespace() || "()-_/".contains(*c))).collect()
}

/// libphonenumber's display of a "+1" number: "+1 425-555-0100" when it has
/// ten digits, "+1 5550100" for another length of at least two digits not
/// starting with 0 (Teams formats what it can parse). None otherwise.
fn nanp_display(number: &str) -> Option<String> {
    let rest = number.strip_prefix("+1")?;
    if rest.len() < 2 || !rest.bytes().all(|b| b.is_ascii_digit()) || rest.starts_with('0') {
        return None;
    }
    if rest.len() == 10 {
        return Some(format!("+1 {}-{}-{}", &rest[..3], &rest[3..6], &rest[6..]));
    }
    Some(format!("+1 {rest}"))
}

/// ITU country calling codes in use (one, two and three digits), for
/// libphonenumber's "possible number" check.
const COUNTRY_CODES_1_2: &[u32] = &[
    1, 7, 20, 27, 30, 31, 32, 33, 34, 36, 39, 40, 41, 43, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56, 57,
    58, 60, 61, 62, 63, 64, 65, 66, 81, 82, 84, 86, 90, 91, 92, 93, 94, 95, 98,
];

/// Whether the text is a possible phone number (libphonenumber's
/// `isPossibleNumber` on an international number: a known country code and
/// 4 to 14 national digits). Plain local digits are left to the dial plan.
pub fn is_possible_number(input: &str) -> bool {
    let t = remove_format_characters(input);
    let Some(digits) = t.strip_prefix('+') else { return false };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    let code_len = (1..=3).find(|&n| {
        digits.len() > n
            && digits[..n].parse::<u32>().is_ok_and(|c| {
                if n <= 2 { COUNTRY_CODES_1_2.contains(&c) } else { (200..=999).contains(&c) && !matches!(c, 999 | 888 | 878 | 800..=809) }
            })
    });
    let Some(code_len) = code_len else { return false };
    let national = digits.len() - code_len;
    (4..=14).contains(&national)
}

/// The "Call me" request: our participant (`from`, also the asserted
/// identity) adding the phone `phone_mri` to the meeting.
pub fn call_me_back_body(from: &Value, phone_mri: &str, thread_id: &str, message_id: Option<&str>, links: Value) -> Value {
    let asserted = from.get("id").cloned().unwrap_or(Value::Null);
    json!({
        "participants": {
            "from": from,
            "to": [{ "id": phone_mri, "assertedId": asserted }],
        },
        "participantInvitationData": {},
        "groupContext": null,
        "groupChat": { "threadId": thread_id, "messageId": message_id },
        "links": links,
    })
}

/// What an add-participant callback says about `phone_mri`: Some(Ok) when
/// it joined, Some(Err(text)) with Teams' message when it failed.
pub fn call_me_back_result(event: &Value, phone_mri: &str) -> Option<Result<(), String>> {
    let path = event.get("callAgentPath").and_then(Value::as_str).unwrap_or("");
    let body = event.get("body").unwrap_or(event);
    let same = |id: &str| id.eq_ignore_ascii_case(phone_mri);
    if path.contains("addParticipantSuccess") {
        let ids: Vec<String> = if let Some(infos) = body.get("participantInfos").and_then(Value::as_array) {
            infos.iter().filter_map(|i| i.get("id").and_then(Value::as_str).map(str::to_string)).collect()
        } else {
            body.get("participants")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(|p| p.as_str().map(str::to_string).or_else(|| p.get("id").and_then(Value::as_str).map(str::to_string)))
                .collect()
        };
        return ids.iter().any(|i| same(i)).then_some(Ok(()));
    }
    if path.contains("addParticipantFailure") {
        let end = if let Some(infos) = body.get("participantInfos").and_then(Value::as_array) {
            infos
                .iter()
                .find(|i| i.pointer("/participant/id").and_then(Value::as_str).is_some_and(same))
                .and_then(|i| i.get("transactionEnd"))
        } else {
            body.get("participants")
                .and_then(Value::as_object)
                .and_then(|m| m.iter().find(|(k, _)| same(k)).map(|(_, v)| v))
        }?;
        return Some(Err(failure_text(end).to_string()));
    }
    None
}

/// Teams' message for a failed Call me (`getAddParticipantMessageErrorType`
/// and the dialog's `$t`).
pub fn failure_text(end: &Value) -> &'static str {
    let code = end.get("code").and_then(Value::as_i64);
    let sub = end.get("subCode").and_then(Value::as_i64);
    let categories: Vec<&str> = end
        .get("resultCategories")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .collect();
    if sub.is_some_and(|s| (10500..=10549).contains(&s)) {
        return "Call not allowed in this location.";
    }
    if categories.contains(&"EntitlementFailure") || (code == Some(403) && sub.is_some_and(|s| (510566..=510569).contains(&s))) {
        return "You are not allowed to dial-out to this destination. Please contact your administrator.";
    }
    "We could not complete the call. The user is unavailable at the moment."
}

#[cfg(test)]
mod tests {
    use super::*;

    fn join_response() -> Value {
        json!({"meetingDetails": {
            "pstnDetails": {"bridgeId": "b", "userBridgeId": "u", "acpMcuInfo": {"settings": {"tollNumber": "18723339415", "tollFreeNumber": null, "participantPasscode": "975755048"}}, "isStatic": false, "dialinUrl": "https://dialin.teams.cloud.microsoft/u?id=975755048", "meetingInvitePhoneNumbers": []},
            "meetingCapability": {"allowPstnConferencing": true, "pstnConferencingDialOutType": "InternationalAndDomestic", "allowAnonymousUsersToDialOut": false, "meetingEndToEndEncryptionEnabled": false}
        }})
    }

    #[test]
    fn reads_the_dial_in_details_as_teams_shows_them() {
        let d = dial_in(&join_response()).expect("dial-in");
        assert_eq!(d.toll_text(), "+18723339415");
        assert_eq!(d.toll_free_text(), "");
        assert_eq!(d.conference_text(), "Conference ID: 975 755 048 #");
        assert_eq!(d.local_numbers_url, "https://dialin.teams.cloud.microsoft/u?id=975755048");
        assert_eq!(
            d.toll_aria(false),
            "Dial in using toll number + 1 8 7 2 3 3 3 9 4 1 5, conference ID 9 7 5 7 5 5 0 4 8"
        );
        // The conversation-only join (before the call) has no details.
        assert_eq!(dial_in(&json!({"meetingDetails": {"pstnDetails": null}})), None);
    }

    /// What Teams' pre-join saw (Teams on the web, 2026-11-16): the
    /// conversation-only join (no invitation yet), the preheated call's
    /// details (an OST-made meeting and a Meet now alike), and a lobby
    /// (capability without a dial-out type, no invitation, no dial-in).
    #[test]
    fn prejoin_decides_phone_audio_as_teams() {
        let mut call = join_response();
        call["meetingDetails"]["invitation"] = json!({"text": "Microsoft Teams meeting"});
        assert_eq!(prejoin_pstn(&call, false), Some(true));
        // The conversation-only join: refused, and no invitation.
        let conv = json!({"meetingDetails": {"pstnDetails": null, "meetingCapability": {"allowPstnConferencing": false, "pstnConferencingDialOutType": "InternationalAndDomestic"}}});
        assert_eq!(prejoin_pstn(&conv, false), None);
        assert!(!prejoin_fallback(Some(&conv)));
        // Held in a lobby: undecided, then the fallback offers it.
        let lobby = json!({"body": {"meetingDetails": {"pstnDetails": null, "invitation": null, "meetingCapability": {"allowPstnConferencing": true, "pstnConferencingDialOutType": null}}}});
        assert_eq!(prejoin_pstn(&lobby, false), None);
        assert!(prejoin_fallback(Some(&lobby)));
        assert!(!prejoin_fallback(None));
        // Decided but without dial-in details: not offered.
        let mut no_details = call.clone();
        no_details["meetingDetails"]["pstnDetails"] = Value::Null;
        assert_eq!(prejoin_pstn(&no_details, false), Some(false));
        // An organizer without Audio Conferencing: refused, dial-out off.
        let mut refused = call.clone();
        refused["meetingDetails"]["meetingCapability"]["allowPstnConferencing"] = false.into();
        refused["meetingDetails"]["meetingCapability"]["pstnConferencingDialOutType"] = "Disabled".into();
        assert_eq!(prejoin_pstn(&refused, false), None);
        assert!(!prejoin_fallback(Some(&refused)));
        assert!(has_meeting_details(&lobby) && !has_meeting_details(&json!({"body": {}})));
    }

    #[test]
    fn reads_the_dial_in_block_of_an_invitation() {
        let body = r#"<span>Dial in by phone</span><a href="tel:+18723339415,,975755048#">+1 872-333-9415,,975755048#</a> United States, Chicago <a href="https://dialin.teams.cloud.microsoft/474a?id=975755048">Find a local number</a> Phone conference ID: 975 755 048#"#;
        let d = dial_in_from_invite(body).expect("dial-in");
        assert_eq!(d.toll_text(), "+18723339415");
        assert_eq!(d.conference_id, "975755048");
        assert_eq!(d.local_numbers_url, "https://dialin.teams.cloud.microsoft/474a?id=975755048");
        assert_eq!(dial_in_from_invite("<p>Microsoft Teams meeting</p>"), None);
    }

    #[test]
    fn offers_phone_audio_by_teams_rules() {
        let p = phone_audio(&join_response(), false).unwrap();
        assert_eq!(p, PhoneAudio { available: true, dial_in: true, dial_out: true });
        // Anonymous guests can't be called back unless the meeting allows it.
        assert!(!phone_audio(&join_response(), true).unwrap().available);
        let mut v = join_response();
        v["meetingDetails"]["meetingCapability"]["pstnConferencingDialOutType"] = "Disabled".into();
        assert!(!phone_audio(&v, false).unwrap().available);
        let mut v = join_response();
        v["meetingDetails"]["pstnDetails"] = Value::Null;
        assert!(!phone_audio(&v, false).unwrap().available);
        let mut v = join_response();
        v["meetingDetails"]["meetingCapability"]["allowPstnConferencing"] = false.into();
        assert_eq!(phone_audio(&v, false).unwrap(), PhoneAudio { available: false, dial_in: false, dial_out: true });
    }

    fn us_plan() -> DialPlan {
        DialPlan::from_policy(&json!({"normalizationRules": [
            {"pattern": "^988$", "translation": "+18002738255"},
            {"pattern": "^011(\\d+)$", "translation": "+$1"},
            {"pattern": "^((\\+)?(\\d+))(;)?(ext|extn|EXT|EXTN|x|X)(=)?(\\d+)$", "translation": "$1;ext=$7"},
            {"pattern": "^1(\\d+)$", "translation": "+1$1"},
            {"pattern": "^(\\d{10})$", "translation": "+1$1"}
        ], "ituCountryPrefix": "1"}))
    }

    #[test]
    fn checks_and_formats_numbers_as_teams_did() {
        // Measured in Teams on the web (Call me enabled, the box after it
        // loses focus) with ost-test1's dial plan.
        let p = us_plan();
        let cases = [
            ("12", true, "12"),
            ("abc", false, "abc"),
            ("5550100", true, "+1 5550100"),
            ("14255550100", true, "+1 425-555-0100"),
            ("+14255550100", true, "+1 425-555-0100"),
            ("+44 20 7946 0000", true, "+44 20 7946 0000"),
            ("(425) 555-0100", true, "+1 425-555-0100"),
            ("0000000000", true, "+10000000000"),
            ("+999 1234", false, "+999 1234"),
            ("425 555 0100 x12", true, "425 555 0100 x12"),
        ];
        for (input, enabled, shown) in cases {
            assert_eq!(p.can_call(input), enabled, "{input}");
            assert_eq!(p.display(input), shown, "{input}");
        }
        assert_eq!(p.phone_mri("(425) 555-0100"), "4:+14255550100");
        assert_eq!(p.phone_mri("988"), "4:+18002738255");
        assert_eq!(p.phone_mri("+44 20 7946 0000"), "4:+442079460000");
        // Without a dial plan Teams takes any text.
        assert!(DialPlan::default().can_call("x"));
    }

    #[test]
    fn builds_the_call_me_request_as_teams() {
        let from = json!({"id": "8:orgid:o", "displayName": "OST Test 1", "endpointId": "e", "participantId": "p", "languageId": "en-us"});
        let b = call_me_back_body(&from, "4:+14255550100", "19:meeting_x@thread.v2", Some("0"), json!({"addParticipantSuccess": "s", "addParticipantFailure": "f"}));
        assert_eq!(b["participants"]["to"][0], json!({"id": "4:+14255550100", "assertedId": "8:orgid:o"}));
        assert_eq!(b["groupChat"], json!({"threadId": "19:meeting_x@thread.v2", "messageId": "0"}));
        assert_eq!(b["links"]["addParticipantFailure"], "f");
    }

    #[test]
    fn reads_the_call_me_outcome() {
        let ok = json!({"callAgentPath": "conversation/addParticipantSuccess/", "body": {"participants": ["4:+14255550100"]}});
        assert_eq!(call_me_back_result(&ok, "4:+14255550100"), Some(Ok(())));
        let fail = json!({"callAgentPath": "conversation/addParticipantFailure/", "body": {"participantInfos": [
            {"participant": {"id": "4:+10000000000", "participantId": "x"}, "transactionEnd": {"code": 404, "subCode": 560404, "phrase": "Invalid number"}}
        ]}});
        assert_eq!(
            call_me_back_result(&fail, "4:+10000000000"),
            Some(Err("We could not complete the call. The user is unavailable at the moment.".into()))
        );
        let lbr = json!({"callAgentPath": "conversation/addParticipantFailure/", "body": {"participants": {"4:+1": {"code": 403, "subCode": 10510}}}});
        assert_eq!(call_me_back_result(&lbr, "4:+1"), Some(Err("Call not allowed in this location.".into())));
        let dom = json!({"code": 403, "subCode": 510567});
        assert_eq!(failure_text(&dom), "You are not allowed to dial-out to this destination. Please contact your administrator.");
        assert_eq!(call_me_back_result(&ok, "4:+19999999999"), None);
    }
}
