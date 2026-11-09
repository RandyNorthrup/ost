//! An app's details as Teams shows them in its About dialog
//! (`app-details-northstar-dialog`), and sharing an app as Teams' Share
//! form does.
//!
//! Where the data comes from:
//! - **Definition:** the middle tier's `beta/users/apps/batchedDefinitions`.
//! - **Rating:** AppSuggestions' `api/v2/apps/ratings`, a list of every
//!   rated app. The desktop client's worker reads this one; the middle
//!   tier's per-app rating answers 500.
//! - **Installs last month:** `odata/v1/apps/{id}?$expand=usage`.
//! - **Reviews:** `odata/v1/apps/{id}/reviews`.
//! - **More like this:** the middle tier's catalog (`definitionsv2`),
//!   ranked by `api/v1/users/apps/suggestions`.
//!
//! Permissions, capabilities, languages, pricing and "Works in" are worked
//! out from the definition, as Teams' client does.
//!
//! Spec: docs/spec/app-details.md.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;

/// The AppSuggestions service's token audience.
const SUGGESTIONS_SCOPE: &str = "https://prod.appsuggestions.teams.core.microsoft/.default";
/// The card Teams posts for a shared app is attributed to this app id.
const APP_CARD_APP_ID: &str = "08648EF4-F8B6-45DA-AB44-74F21AABD840";
/// Teams' message in the Share form for an app.
pub const SHARE_MESSAGE: &str = "Take a look at this app.";
/// Reviews Teams counts and lists when no filter is chosen.
const DEFAULT_REVIEWS_FILTER: &str =
    "length(Content) gt 0 or length(Title) gt 0 or author/me eq true";
/// Teams' "More like this": six cards; the first six apps by the same
/// developer are left out of it.
const MORE_LIKE_THIS: usize = 6;
/// Installed states (Teams' worker list).
const INSTALLED: [&str; 4] = [
    "Installed",
    "InstalledAndFavorited",
    "InstalledAndPermanent",
    "AdminPreInstalled",
];

fn locales() -> &'static Vec<(String, String)> {
    static L: OnceLock<Vec<(String, String)>> = OnceLock::new();
    L.get_or_init(|| serde_json::from_str(include_str!("app_locales.json")).unwrap_or_default())
}

fn permission_strings() -> &'static HashMap<String, String> {
    static S: OnceLock<HashMap<String, String>> = OnceLock::new();
    S.get_or_init(|| {
        serde_json::from_str(include_str!("app_permission_strings.json")).unwrap_or_default()
    })
}

#[derive(Deserialize)]
struct Subcategory {
    #[serde(rename = "subcategoryKey")]
    key: String,
    order: i64,
    properties: Vec<String>,
    #[serde(rename = "otherPermissions")]
    other: Vec<String>,
}

#[derive(Deserialize)]
struct Category {
    #[serde(rename = "categoryKey")]
    key: String,
    order: i64,
    properties: Vec<String>,
    subcategories: Vec<Subcategory>,
}

fn categories() -> &'static Vec<Category> {
    static C: OnceLock<Vec<Category>> = OnceLock::new();
    C.get_or_init(|| {
        serde_json::from_str(include_str!("app_permission_categories.json")).unwrap_or_default()
    })
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Rating {
    /// Teams' `+average.toFixed(1)`: "3.3", or "4" for 4.0.
    pub average: String,
    pub count: u64,
    /// `count` as Teams writes it (compact: "27.8K").
    pub count_text: String,
    /// Five stars first.
    pub stars: [u64; 5],
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Capability {
    pub title: String,
    pub description: String,
    /// A Fluent icon (OST's assets/icons name).
    pub icon: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct PermissionGroup {
    pub title: String,
    pub icon: String,
    pub items: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct PermissionCategory {
    /// "Permission to read and access:" or "Permission to perform these
    /// actions:".
    pub title: String,
    pub groups: Vec<PermissionGroup>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct AppCard {
    pub id: String,
    pub name: String,
    pub short: String,
    pub icon: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct AppDetails {
    pub id: String,
    pub name: String,
    pub developer: String,
    pub developer_url: String,
    pub icon: String,
    pub short_description: String,
    pub description: String,
    pub version: String,
    pub privacy_url: String,
    pub terms_url: String,
    pub works_in: String,
    pub pricing_label: String,
    pub pricing_sublabel: String,
    /// Details ▸ Pricing.
    pub pricing_details: String,
    pub installed: bool,
    pub capabilities: Vec<Capability>,
    pub permissions: Vec<PermissionCategory>,
    pub languages: Vec<String>,
    /// The language shown first ("English (United States)"), or the
    /// first when yours isn't among them.
    pub language_first: String,
    pub rating: Rating,
    pub installs: u64,
    pub installs_text: String,
    pub reviews_count: u64,
    pub reviews_count_text: String,
    /// `https://teams.microsoft.com/l/app/{id}?source=app-header-share-entrypoint`.
    pub share_link: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Review {
    pub id: String,
    pub title: String,
    pub content: String,
    pub rating: u8,
    /// The author's name, "You", or "Anonymous".
    pub author: String,
    /// "2 days ago" (date-fns' strict distance, as Teams writes it).
    pub when: String,
    pub developer_reply: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct ReviewPage {
    pub count: u64,
    pub reviews: Vec<Review>,
    /// The next page's link, verbatim, or empty.
    pub next: String,
}

/// Teams' review orders.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReviewSort {
    MostRecent,
    HighestRating,
    LowestRating,
}

impl ReviewSort {
    pub fn parse(s: &str) -> Self {
        match s {
            "highest" => Self::HighestRating,
            "lowest" => Self::LowestRating,
            _ => Self::MostRecent,
        }
    }
    fn order_by(self) -> &'static str {
        match self {
            Self::HighestRating => "rating desc, content desc",
            Self::LowestRating => "rating asc, content desc",
            Self::MostRecent => "author/me desc, updatedAt desc",
        }
    }
}

fn str_at<'a>(v: &'a serde_json::Value, key: &str) -> &'a str {
    v.get(key).and_then(|s| s.as_str()).unwrap_or_default()
}

fn non_empty_array(v: &serde_json::Value, key: &str) -> bool {
    v.get(key)
        .and_then(|a| a.as_array())
        .is_some_and(|a| !a.is_empty())
}

/// English list formatting (Intl.ListFormat, conjunction): "A", "A and B",
/// "A, B, and C".
pub fn list_format(items: &[String]) -> String {
    match items {
        [] => String::new(),
        [a] => a.clone(),
        [a, b] => format!("{a} and {b}"),
        _ => format!(
            "{}, and {}",
            items[..items.len() - 1].join(", "),
            items[items.len() - 1]
        ),
    }
}

/// Teams' compact number (formatNumber, notation compact, short, one
/// fraction digit): 950, "1.5K", "12K", "3.2M".
pub fn compact(n: u64) -> String {
    let f = |v: f64, s: &str| {
        let r = (v * 10.0).round() / 10.0;
        if r.fract() == 0.0 {
            format!("{}{s}", r as u64)
        } else {
            format!("{r:.1}{s}")
        }
    };
    match n {
        0..=999 => n.to_string(),
        1_000..=999_949 => f(n as f64 / 1e3, "K"),
        1_000_000..=999_949_999 => f(n as f64 / 1e6, "M"),
        _ => f(n as f64 / 1e9, "B"),
    }
}

/// `+average.toFixed(1)`.
pub fn average_text(avg: f64) -> String {
    let s = format!("{:.1}", (avg * 10.0).round() / 10.0);
    s.strip_suffix(".0").map(str::to_string).unwrap_or(s)
}

/// A locale code's native name as Teams looks it up: a code with a region
/// matches exactly; a bare language ("fr") takes the first entry of that
/// language with its region dropped ("Français").
pub fn native_name(code: &str) -> Option<String> {
    let want = code.to_ascii_uppercase();
    let regional = want.contains('-');
    let (_, name) = locales().iter().find(|(c, _)| {
        let c = c.to_ascii_uppercase();
        if !regional && let Some(i) = c.find('-') {
            return c[..i] == want;
        }
        c == want
    })?;
    if regional {
        return Some(name.clone());
    }
    // Teams strips "(…)": "Français (Canada)" → "Français".
    Some(match (name.find('('), name.find(')')) {
        (Some(a), Some(b)) => format!("{}{}", &name[..a], &name[b + 1..])
            .trim()
            .to_string(),
        _ => name.clone(),
    })
}

/// The app's languages, deduplicated, and the one Teams shows first.
pub fn languages(codes: &[String], user_locale: &str) -> (Vec<String>, String) {
    let mut out: Vec<String> = Vec::new();
    for c in codes {
        if let Some(n) = native_name(c)
            && !out.contains(&n)
        {
            out.push(n);
        }
    }
    let mine = native_name(user_locale);
    let first = match mine {
        Some(m) if out.contains(&m) => m,
        _ => out.first().cloned().unwrap_or_default(),
    };
    (out, first)
}

/// "Works in": the hubs Teams names, else Teams.
pub fn works_in(def: &serde_json::Value) -> String {
    let hubs: Vec<String> = def
        .get("supportedHubs")
        .and_then(|h| h.as_array())
        .into_iter()
        .flatten()
        .filter_map(|h| h.as_str())
        .filter_map(|h| match h.to_ascii_uppercase().as_str() {
            "TEAMS" => Some("Teams"),
            "COPILOT" => Some("Copilot"),
            "OUTLOOK" => Some("Outlook"),
            "OFFICE" => Some("Office"),
            "WORD" => Some("Word"),
            "EXCEL" => Some("Excel"),
            "POWERPOINT" => Some("Power Point"),
            _ => None,
        })
        .map(str::to_string)
        .collect();
    if hubs.is_empty() {
        "Teams".into()
    } else {
        list_format(&hubs)
    }
}

fn is_declarative_copilot(def: &serde_json::Value) -> bool {
    def.pointer("/metaCapabilities/declarativeCopilots")
        .is_some_and(|v| !v.is_null())
}

fn is_copilot(def: &serde_json::Value) -> bool {
    is_declarative_copilot(def)
        || def
            .pointer("/metaCapabilities/customEngineCopilots")
            .is_some_and(|v| !v.is_null())
        || def
            .pointer("/metaCapabilities/copilotExtensions")
            .is_some_and(|v| !v.is_null())
}

/// The stats row's pricing (label, sub-label) and Details ▸ Pricing.
pub fn pricing(def: &serde_json::Value) -> (String, String, String) {
    let offer = def
        .pointer("/subscriptionOffer/offerId")
        .and_then(|o| o.as_str())
        .is_some_and(|o| !o.is_empty());
    let free = ("Free", "Free to add and use", "Free to add and use");
    let (a, b, c) = if is_declarative_copilot(def) {
        match str_at(def, "agentClassification") {
            "Consumption" => ("Usage", "Pay as you use it", "Pay as you use it"),
            "Licensed" => ("License", "Required", "License required"),
            _ => free,
        }
    } else if offer {
        (
            "Subscription",
            "Plans available",
            "Subscription plans available",
        )
    } else {
        free
    };
    (a.into(), b.into(), c.into())
}

/// Whether the app's bots, connectors or tabs (and, outside Team, its
/// message extensions) work in `scope` (Teams' supportsScope).
pub fn supports_scope(scope: &str, def: &serde_json::Value) -> bool {
    let has = |key: &str| {
        def.get(key)
            .and_then(|a| a.as_array())
            .into_iter()
            .flatten()
            .any(|c| {
                c.get("scopes")
                    .and_then(|s| s.as_array())
                    .is_some_and(|s| s.iter().any(|x| x.as_str() == Some(scope)))
            })
    };
    let base = has("bots") || has("connectors") || has("galleryTabs") || has("staticTabs");
    if scope == "Team" {
        return base;
    }
    base || has("messageExtensions")
}

/// "Capabilities in Teams", in Teams' order.
pub fn capabilities(def: &serde_json::Value) -> Vec<Capability> {
    let cap = |title: &str, description: &str, icon: &str| Capability {
        title: title.into(),
        description: description.into(),
        icon: icon.into(),
    };
    let static_scope = |scope: &str| {
        def.get("staticTabs")
            .and_then(|a| a.as_array())
            .into_iter()
            .flatten()
            .any(|t| {
                t.get("scopes")
                    .and_then(|s| s.as_array())
                    .is_some_and(|s| s.iter().any(|x| x.as_str() == Some(scope)))
            })
    };
    let mut out = Vec::new();
    if is_copilot(def) {
        out.push(cap(
            "Agent",
            "Chat to get answers, find info, complete complex tasks, and more.",
            "sparkle-20",
        ));
    }
    if non_empty_array(def, "bots") {
        out.push(cap(
            "Bot",
            "Chat using prompts to complete simple tasks.",
            "bot-20",
        ));
    }
    if non_empty_array(def, "extensions") {
        out.push(cap(
            "Mail and Calendar extensions",
            "Get notified by the app when something needs your attention, like updates or tasks.",
            "tab-desktop-20",
        ));
    }
    if non_empty_array(def, "messageExtensions") {
        out.push(cap(
            "Messaging",
            "Insert app content in messages to send more than just text.",
            "chat-20",
        ));
    }
    if non_empty_array(def, "connectors") {
        out.push(cap(
            "Notifications",
            "Get notified by the app when something needs your attention, like updates or tasks.",
            "alert-20",
        ));
    }
    if static_scope("Personal") {
        out.push(cap(
            "Personal app",
            "Use the app privately outside of a chat, channel, or meeting.",
            "person-20",
        ));
    }
    if non_empty_array(def, "galleryTabs") || static_scope("Team") {
        out.push(cap(
            "Tab",
            "Collaborate in a chat or channel by adding a tab for the app.",
            "tab-desktop-20",
        ));
    }
    out
}

const RSC_RESOURCES: [&str; 36] = [
    "TeamSettings",
    "ChannelSettings",
    "Channel",
    "ChannelMessage",
    "TeamsTab",
    "Member",
    "Owner",
    "TeamMember",
    "TeamsAppInstallation",
    "File",
    "ChatMember",
    "ChatMessage",
    "ChatSettings",
    "Chat",
    "OnlineMeeting",
    "CameraStream",
    "OutgoingVideoStream",
    "OnlineMeetingParticipant",
    "ChannelMeetingParticipant",
    "InAppPurchase",
    "ChannelMeeting",
    "TeamsActivity",
    "Calls",
    "MeetingStage",
    "ChannelMeetingStage",
    "MicrophoneStream",
    "OnlineMeetingIncomingAudio",
    "ChannelMeetingIncomingAudio",
    "OnlineMeetingActiveSpeaker",
    "ChannelMeetingActiveSpeaker",
    "ChannelMeetingAudioVideo",
    "LiveShareSession",
    "MeetingParticipantReaction",
    "OnlineMeetingNotification",
    "ChannelMeetingNotification",
    "ChatMessageReadReceipt",
];
const RSC_OTHER: [&str; 12] = [
    "Document",
    "MailboxRoamingSettings",
    "MailboxItem",
    "Mailbox",
    "SearchQuery",
    "ChannelMeetingTranscript",
    "OnlineMeetingTranscript",
    "OnlineMeetingArtifact",
    "AiEnterpriseInteraction",
    "ChannelMember",
    "VirtualEvent",
    "VirtualEventRegistration-Anon",
];
const RSC_ACTIONS: [&str; 18] = [
    "Read",
    "ReadAll",
    "Create",
    "ReadWrite",
    "Delete",
    "Manage",
    "ManageDeletion",
    "ReadBasic",
    "ToggleIncomingAudio",
    "Write",
    "Allow",
    "Send",
    "AccessMedia",
    "JoinGroupCalls",
    "Detect",
    "Stream",
    "AccessSharedFolders",
    "AppendOnSend",
];
const RSC_SCOPES: [&str; 3] = ["Group", "Chat", "User"];

/// The app's permission keys, as Teams' client works them out (module
/// 523993 with the key sets of 96201).
pub fn permission_keys(def: &serde_json::Value) -> Vec<String> {
    let mut caps: Vec<&str> = [
        "bots",
        "connectors",
        "galleryTabs",
        "messageExtensions",
        "staticTabs",
    ]
    .into_iter()
    .filter(|k| non_empty_array(def, k))
    .collect();
    for k in [
        "copilotExtensions",
        "declarativeCopilots",
        "customEngineCopilots",
    ] {
        if def
            .pointer(&format!("/metaCapabilities/{k}"))
            .is_some_and(|v| !v.is_null())
        {
            caps.push(k);
        }
    }
    if def
        .get("isFullScreenApp")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        caps.push("isFullScreenApp");
    }
    let copilot = is_declarative_copilot(def)
        || def
            .pointer("/metaCapabilities/customEngineCopilots")
            .is_some_and(|v| !v.is_null());
    let mut keys: Vec<String> = Vec::new();
    let mut add_set = |set: &[(&str, &[&str])]| {
        for (key, needs) in set {
            if needs.iter().any(|n| caps.contains(n)) {
                keys.push((*key).to_string());
            }
        }
    };
    if !copilot {
        const TAB_LIKE: &[&str] = &[
            "galleryTabs",
            "staticTabs",
            "bots",
            "messageExtensions",
            "copilotExtensions",
            "declarativeCopilots",
            "customEngineCopilots",
        ];
        add_set(&[
            ("app_details_basic_full_permission", TAB_LIKE),
            ("app_details_basic_bots_permission", &["bots"]),
            ("app_details_full_screen_permission", &["isFullScreenApp"]),
            ("app_details_identity_permission", TAB_LIKE),
        ]);
        let team = supports_scope("Team", def);
        let chat = supports_scope("GroupChat", def);
        const TEAM_LIKE: &[&str] = &["galleryTabs", "staticTabs", "bots", "messageExtensions"];
        if team && chat {
            add_set(&[
                ("app_details_team_and_chat_full_permission", TEAM_LIKE),
                (
                    "app_details_team_and_chat_bots_connectors_permission",
                    &["bots", "connectors"],
                ),
                ("app_details_identity_team_and_chat_permission", TEAM_LIKE),
            ]);
        } else if team {
            add_set(&[
                (
                    "extension_addAppDialogTeamAndChatAndMeetingPermission1",
                    TEAM_LIKE,
                ),
                (
                    "extension_addAppDialogTeamAndChatAndMeetingPermission2",
                    &["bots", "connectors"],
                ),
                (
                    "extension_addAppDialogIdentityTeamAndChatAndMeetingPermission",
                    TEAM_LIKE,
                ),
            ]);
        } else if chat {
            add_set(&[
                (
                    "app_details_chat_galleryTabs_bots_permission",
                    &["galleryTabs", "bots"],
                ),
                ("app_details_chat_bots_permission", &["bots"]),
                (
                    "app_details_identity_chat_permission",
                    &["galleryTabs", "bots"],
                ),
            ]);
        }
    }
    // Resource-specific consent: "Resource.Action.Scope" names become
    // app_details_permission_<resource>_<actions>_<scope> keys.
    let mut rsc: Vec<String> = Vec::new();
    if let Some(a) = def
        .pointer("/webApplicationInfo/applicationPermissions")
        .and_then(|a| a.as_array())
    {
        rsc.extend(
            a.iter()
                .filter_map(|p| p.as_str())
                .filter(|p| !p.is_empty())
                .map(str::to_string),
        );
    }
    if let Some(a) = def
        .pointer("/authorization/permissions/resourceSpecific")
        .and_then(|a| a.as_array())
    {
        rsc.extend(
            a.iter()
                .filter_map(|p| p.get("name").and_then(|n| n.as_str()))
                .map(str::to_string),
        );
    }
    if !rsc.is_empty() {
        let strings = permission_strings();
        let mut left: Vec<String> = rsc.clone();
        let mut found: Vec<String> = Vec::new();
        for resource in RSC_RESOURCES.iter().chain(RSC_OTHER.iter()) {
            for scope in RSC_SCOPES {
                let mut actions = Vec::new();
                for action in RSC_ACTIONS {
                    let name = format!("{resource}.{action}.{scope}");
                    if let Some(i) = left.iter().position(|l| *l == name) {
                        actions.push(action);
                        left.remove(i);
                    }
                }
                if actions.is_empty() {
                    continue;
                }
                let key = |acts: &str| {
                    format!("app_details_permission_{resource}_{acts}_{scope}").to_lowercase()
                };
                let joined = key(&actions.join("_"));
                if strings.contains_key(&joined) {
                    found.push(joined);
                } else {
                    found.extend(actions.iter().map(|a| key(a)));
                }
            }
        }
        // Names Teams doesn't know stay as they are (and aren't shown).
        found.extend(left);
        if !copilot {
            found.push("app_details_permission_teams_access".into());
        }
        keys.extend(found);
    }
    // Device permissions, for apps without tabs.
    if !caps.contains(&"staticTabs") && !caps.contains(&"galleryTabs") {
        for d in def
            .get("devicePermissions")
            .and_then(|a| a.as_array())
            .into_iter()
            .flatten()
        {
            let k = match d.as_str().unwrap_or_default() {
                "Media" => "extension_addAppDialogDeviceConsent",
                "Geolocation" => "extension_addAppDialogLocationConsent",
                "Notifications" => "extension_addAppDialogNotificationsConsent",
                "OpenExternal" => "extension_addAppDialogExternalLinkContent",
                "Midi" => "extension_addAppDialogMIDIContent",
                _ => continue,
            };
            keys.push(k.into());
        }
    }
    if def
        .pointer("/meetingExtensionDefinition/supportsStreaming")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        keys.push("app_details_permission_meeting_streaming_access".into());
    }
    let mut seen = HashSet::new();
    keys.retain(|k| seen.insert(k.clone()));
    keys
}

fn category_title(key: &str) -> &'static str {
    if key == "app_details_categories_readaccess" {
        "Permission to read and access:"
    } else {
        "Permission to perform these actions:"
    }
}

fn subcategory(key: &str) -> (&'static str, &'static str) {
    match key {
        "app_details_subcategories_information_related_to_you" => {
            ("Information related to you", "person")
        }
        "app_details_subcategories_information_chatschannelsmeetings" => (
            "Information in chats, channels, and meetings",
            "people-team",
        ),
        "app_details_subcategories_other_readaccess" => ("Other read access", "ost"),
        "app_details_subcategories_send_receive_messages_notifications" => {
            ("Send and receive messages and notifications", "alert-badge")
        }
        "app_details_subcategories_content_settings" => ("Content and settings", "settings"),
        "app_details_subcategories_manage_media_devices" => ("Manage media and devices", "video"),
        _ => ("Other", "cursor-click"),
    }
}

/// Which category and subcategory a permission key falls under (Teams'
/// Zr: listed keys first, then an RSC key's actions, then "other").
fn place(key: &str) -> (i64, String, i64, String) {
    let cats = categories();
    for c in cats {
        for s in &c.subcategories {
            if s.other.iter().any(|o| o == key) {
                return (c.order, c.key.clone(), s.order, s.key.clone());
            }
        }
    }
    const DEFAULT: (&str, i64) = ("app_details_categories_perform_actions", 99);
    let rsc = key.starts_with("app_details_permission_");
    let parts: Vec<String> = {
        let p: Vec<&str> = key
            .trim_start_matches("app_details_permission_")
            .split('_')
            .collect();
        p[..p.len().saturating_sub(1)]
            .iter()
            .map(|s| s.to_string())
            .collect()
    };
    let one_category = || {
        let hits: Vec<&Category> = cats
            .iter()
            .filter(|c| c.properties.iter().any(|p| parts.contains(p)))
            .collect();
        if hits.len() == 1 {
            hits[0].key.clone()
        } else {
            DEFAULT.0.to_string()
        }
    };
    if rsc {
        let cat = one_category();
        for c in cats.iter().filter(|c| c.key == cat) {
            for s in &c.subcategories {
                if s.properties.iter().any(|p| parts.contains(p)) {
                    return (c.order, c.key.clone(), s.order, s.key.clone());
                }
            }
        }
    }
    let cat = if rsc {
        one_category()
    } else {
        DEFAULT.0.to_string()
    };
    let sub = if cat == "app_details_categories_readaccess" {
        "app_details_subcategories_other_readaccess"
    } else {
        "app_details_subcategories_other"
    };
    let c = cats.iter().find(|c| c.key == cat);
    let s = c.and_then(|c| c.subcategories.iter().find(|s| s.key == sub));
    (
        c.map_or(DEFAULT.1, |c| c.order),
        cat,
        s.map_or(DEFAULT.1, |s| s.order),
        sub.to_string(),
    )
}

/// The permissions grouped as Teams shows them (keys without a sentence
/// are left out, as Teams leaves them out).
pub fn permissions(keys: &[String]) -> Vec<PermissionCategory> {
    let strings = permission_strings();
    let mut cats: Vec<(i64, String, Vec<(i64, String, Vec<String>)>)> = Vec::new();
    for k in keys {
        let Some(text) = strings.get(k) else { continue };
        let (co, ck, so, sk) = place(k);
        let cat = match cats.iter_mut().position(|c| c.1 == ck) {
            Some(i) => &mut cats[i],
            None => {
                cats.push((co, ck.clone(), Vec::new()));
                cats.last_mut().unwrap()
            }
        };
        match cat.2.iter_mut().find(|s| s.1 == sk) {
            Some(s) => s.2.push(text.clone()),
            None => cat.2.push((so, sk, vec![text.clone()])),
        }
    }
    cats.sort_by_key(|c| c.0);
    cats.into_iter()
        .map(|(_, ck, mut subs)| {
            subs.sort_by_key(|s| s.0);
            PermissionCategory {
                title: category_title(&ck).into(),
                groups: subs
                    .into_iter()
                    .map(|(_, sk, items)| {
                        let (title, icon) = subcategory(&sk);
                        PermissionGroup {
                            title: title.into(),
                            icon: icon.into(),
                            items,
                        }
                    })
                    .collect(),
            }
        })
        .collect()
}

/// date-fns' formatDistanceStrict with a suffix, as Teams dates reviews:
/// "2 days ago", "1 year ago".
pub fn relative_time(
    then: chrono::DateTime<chrono::Utc>,
    now: chrono::DateTime<chrono::Utc>,
) -> String {
    let secs = (now - then).num_milliseconds() as f64 / 1000.0;
    let past = secs >= 0.0;
    let minutes = secs.abs() / 60.0;
    let (n, unit) = if minutes < 1.0 {
        (secs.abs().round(), "second")
    } else if minutes < 60.0 {
        (minutes.round(), "minute")
    } else if minutes < 1440.0 {
        ((minutes / 60.0).round(), "hour")
    } else if minutes < 43200.0 {
        ((minutes / 1440.0).round(), "day")
    } else if minutes < 525600.0 {
        ((minutes / 43200.0).round(), "month")
    } else {
        ((minutes / 525600.0).round(), "year")
    };
    let n = n as u64;
    let s = if n == 1 { "" } else { "s" };
    if past {
        format!("{n} {unit}{s} ago")
    } else {
        format!("in {n} {unit}{s}")
    }
}

fn review_from(v: &serde_json::Value, now: chrono::DateTime<chrono::Utc>) -> Review {
    let me = v
        .pointer("/author/me")
        .and_then(|m| m.as_bool())
        .unwrap_or(false);
    let anonymous = v
        .get("anonymous")
        .and_then(|a| a.as_bool())
        .unwrap_or(false);
    let name = v
        .pointer("/author/name")
        .and_then(|n| n.as_str())
        .unwrap_or_default();
    let author = if me {
        "You".to_string()
    } else if anonymous || name.is_empty() {
        "Anonymous".to_string()
    } else {
        name.to_string()
    };
    let when = chrono::DateTime::parse_from_rfc3339(str_at(v, "updatedAt"))
        .map(|d| relative_time(d.with_timezone(&chrono::Utc), now))
        .unwrap_or_default();
    Review {
        id: str_at(v, "id").into(),
        title: str_at(v, "title").into(),
        content: str_at(v, "content").into(),
        rating: v.get("rating").and_then(|r| r.as_u64()).unwrap_or(0).min(5) as u8,
        author,
        when,
        developer_reply: v
            .pointer("/developerReply/content")
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .into(),
    }
}

/// A rating entry (`{average, count, breakdown{oneStar..fiveStars}}`).
pub fn rating_from(v: &serde_json::Value) -> Rating {
    let n = |k: &str| {
        v.pointer(&format!("/breakdown/{k}"))
            .and_then(|x| x.as_u64())
            .unwrap_or(0)
    };
    let count = v.get("count").and_then(|c| c.as_u64()).unwrap_or(0);
    let avg = v.get("average").and_then(|a| a.as_f64()).unwrap_or(0.0);
    Rating {
        average: if count > 0 {
            average_text(avg)
        } else {
            String::new()
        },
        count,
        count_text: compact(count),
        stars: [
            n("fiveStars"),
            n("fourStars"),
            n("threeStars"),
            n("twoStars"),
            n("oneStar"),
        ],
    }
}

/// Teams' "More like this" from the catalog and the suggestions ranking:
/// apps sharing the app's first category that isn't "Microsoft", in
/// suggestion order (unranked ones after, in catalog order), leaving out
/// apps you have for good and the first six by the same developer.
pub fn more_like_this(
    app: &serde_json::Value,
    catalog: &[serde_json::Value],
    ranked: &[String],
    entitlements: &HashMap<String, String>,
) -> Vec<AppCard> {
    let id = str_at(app, "id");
    let tenant = str_at(app, "tenantId");
    let developer = str_at(app, "developerName");
    let cats: Vec<String> = app
        .get("categories")
        .and_then(|c| c.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| c.as_str())
        .map(str::to_lowercase)
        .collect();
    let Some(category) = cats.iter().find(|c| *c != "microsoft").cloned() else {
        return Vec::new();
    };
    let has_category = |d: &serde_json::Value, pred: &dyn Fn(&str) -> bool| {
        d.get("categories")
            .and_then(|c| c.as_array())
            .is_some_and(|a| {
                a.iter()
                    .filter_map(|c| c.as_str())
                    .any(|c| pred(&c.to_lowercase()))
            })
    };
    let rank: HashMap<&str, usize> = ranked
        .iter()
        .enumerate()
        .map(|(i, r)| (r.as_str(), i))
        .collect();
    let mut related: Vec<&serde_json::Value> = catalog
        .iter()
        // Teams' worker (module 30158 cG): no deprecated apps, none you
        // have for good or deprecated (your entitlements), no custom bots
        // or uploaded apps without a tenant.
        .filter(|d| {
            let mine = entitlements
                .get(&str_at(d, "id").to_lowercase())
                .map(String::as_str)
                .unwrap_or_default();
            str_at(d, "state") != "InstalledAndDeprecated"
                && mine != "InstalledAndPermanent"
                && mine != "InstalledAndDeprecated"
                && !(d.get("externalId").is_some_and(|e| !e.is_null())
                    && str_at(d, "tenantId").is_empty())
                && !non_empty_array(d, "customBots")
        })
        .filter(|d| {
            (!tenant.is_empty() && str_at(d, "tenantId") == tenant)
                || (!developer.is_empty() && str_at(d, "developerName") == developer)
                || has_category(d, &|c| cats.iter().any(|x| x == c))
        })
        .collect();
    related.sort_by_key(|d| rank.get(str_at(d, "id")).copied().unwrap_or(usize::MAX));
    let same_dev: HashSet<&str> = related
        .iter()
        .filter(|d| {
            str_at(d, "id") != id
                && if tenant.is_empty() {
                    str_at(d, "developerName") == developer && d.get("externalId").is_none()
                } else {
                    str_at(d, "tenantId") == tenant
                }
        })
        .take(MORE_LIKE_THIS)
        .map(|d| str_at(d, "id"))
        .collect();
    related
        .into_iter()
        .filter(|d| str_at(d, "id") != id && has_category(d, &|c| c == category))
        .take(MORE_LIKE_THIS * 2)
        .filter(|d| !same_dev.contains(str_at(d, "id")))
        .take(MORE_LIKE_THIS)
        .map(|d| AppCard {
            id: str_at(d, "id").into(),
            name: str_at(d, "name").into(),
            short: str_at(d, "shortDescription").into(),
            icon: super::tabs::https_only(str_at(d, "largeImageUrl")),
        })
        .collect()
}

/// Teams' deep link to an app from its header's Share app.
pub fn share_link(app_id: &str) -> String {
    format!("https://teams.microsoft.com/l/app/{app_id}?source=app-header-share-entrypoint")
}

/// The Adaptive Card Teams posts for a shared app (module 61199).
pub fn share_card(d: &AppDetails) -> serde_json::Value {
    let mut body = vec![
        serde_json::json!({"columns": [
            {"width": "auto", "items": [{"altText": d.name, "size": "small", "style": "roundedCorners",
                "url": d.icon, "height": "auto", "type": "Image"}],
             "verticalContentAlignment": "center", "type": "Column"},
            {"width": "stretch", "items": [
                {"columns": [{"width": "auto", "items": [{"maxLines": 1, "size": "medium", "text": d.name,
                    "weight": "bolder", "wrap": true, "type": "TextBlock"}], "spacing": "small", "type": "Column"}],
                 "type": "ColumnSet"},
                {"isSubtle": true, "maxLines": 1, "size": "small", "text": d.developer, "wrap": true,
                 "spacing": "None", "type": "TextBlock"}],
             "verticalContentAlignment": "center", "type": "Column"}],
         "type": "ColumnSet"}),
        serde_json::json!({"maxLines": 2, "size": "small",
            "text": if d.short_description.is_empty() { &d.description } else { &d.short_description },
            "wrap": true, "spacing": "small", "type": "TextBlock"}),
    ];
    if d.rating.count > 0 {
        let count = if d.rating.count == 1 {
            "(1 rating)".to_string()
        } else {
            format!("({} ratings)", compact(d.rating.count))
        };
        body.push(serde_json::json!({"columns": [
            {"width": "auto", "items": [{"name": "Star", "size": "xxSmall", "style": "filled", "color": "accent", "type": "Icon"}], "type": "Column"},
            {"width": "auto", "items": [{"size": "small", "text": d.rating.average, "weight": "bolder", "wrap": true, "type": "TextBlock"}], "spacing": "ExtraSmall", "type": "Column"},
            {"width": "auto", "items": [{"size": "small", "text": count, "wrap": true, "type": "TextBlock"}], "spacing": "ExtraSmall", "type": "Column"}],
         "spacing": "small", "type": "ColumnSet"}));
    }
    serde_json::json!({
        "type": "AdaptiveCard",
        "body": [{"items": body, "type": "Container"}],
        "actions": [],
        "version": "1.5",
        "selectAction": {"url": d.share_link, "id": d.id, "type": "Action.OpenUrl"},
    })
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// The message Teams posts when sharing an app: the note, a link to the
/// app, and the app's card (`properties.cards`, `properties.links`).
pub fn share_message(
    note_html: &str,
    d: &AppDetails,
    uuid: &str,
    display_name: &str,
    with_card: bool,
) -> serde_json::Value {
    let card_id = format!("app-preview-card-ps{uuid}app-store-link-preview");
    let link = html_escape(&d.share_link);
    let mut content = format!(
        "<p>{note_html}<br><br><a href=\"{link}\" rel=\"noreferrer noopener\" title=\"{link}\" target=\"_blank\">{}</a></p>",
        html_escape(&d.name)
    );
    if with_card {
        content.push_str(&format!(
            "<span itemid=\"{card_id}\" itemscope=\"\" itemtype=\"http://schema.skype.com/InputExtension\"><span itemprop=\"cardId\"></span></span>"
        ));
    }
    let cards = serde_json::json!([{
        "appId": APP_CARD_APP_ID,
        "cardClientId": card_id,
        "appName": d.name,
        "sourceType": "APP_HEADER_SHARE_ENTRYPOINT",
        "content": share_card(d),
        "contentType": "application/vnd.microsoft.card.adaptive",
    }]);
    let links = serde_json::json!([{
        "@type": "http://schema.skype.com/HyperLink",
        "itemid": "0",
        "url": d.share_link,
        "previewenabled": false,
        "preview": {},
    }]);
    serde_json::json!({
        "content": content,
        "messagetype": "RichText/Html",
        "contenttype": "Text",
        "clientmessageid": super::outbox::new_client_message_id(),
        "imdisplayname": display_name,
        "properties": {
            "importance": "",
            "formatVariant": "TEAMS",
            "mentions": "[]",
            "files": "[]",
            "cards": if with_card { cards.to_string() } else { "[]".to_string() },
            "links": links.to_string(),
        },
    })
}

/// Build the details from what the services returned.
pub fn details_from(
    def: &serde_json::Value,
    rating: &serde_json::Value,
    installs: u64,
    reviews_count: u64,
    user_locale: &str,
    entitlement: Option<&str>,
) -> AppDetails {
    let id = str_at(def, "id").to_string();
    let (label, sublabel, details) = pricing(def);
    let codes: Vec<String> = def
        .get("supportedLanguages")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
        .filter_map(|l| l.as_str())
        .map(str::to_string)
        .collect();
    let (languages, language_first) = languages(&codes, user_locale);
    let version = match str_at(def, "version") {
        "" => str_at(def, "manifestVersion"),
        v => v,
    };
    AppDetails {
        name: str_at(def, "name").into(),
        developer: str_at(def, "developerName").into(),
        developer_url: super::tabs::https_only(str_at(def, "developerUrl")),
        icon: super::tabs::https_only(str_at(def, "largeImageUrl")),
        short_description: str_at(def, "shortDescription").into(),
        description: super::tabs::description_html(str_at(def, "longDescription")),
        version: version.into(),
        privacy_url: super::tabs::https_only(str_at(def, "privacyUrl")),
        terms_url: super::tabs::https_only(str_at(def, "termsOfUseUrl")),
        works_in: works_in(def),
        pricing_label: label,
        pricing_sublabel: sublabel,
        pricing_details: details,
        installed: INSTALLED.contains(&entitlement.unwrap_or_else(|| str_at(def, "state"))),
        capabilities: capabilities(def),
        permissions: permissions(&permission_keys(def)),
        languages,
        language_first,
        rating: rating_from(rating),
        installs,
        installs_text: compact(installs),
        reviews_count,
        reviews_count_text: compact(reviews_count),
        share_link: share_link(&id),
        id,
    }
}

pub(crate) fn suggestions_base(client: &TeamsClient) -> Result<String> {
    let base = client
        .region_endpoint("appsSuggestionService")
        .context("No app suggestions endpoint")?;
    let base = base.trim_end_matches('/');
    Ok(base.strip_suffix("/api").unwrap_or(base).to_string())
}

pub(crate) async fn suggestions_token() -> Result<String> {
    static CACHE: Mutex<Option<(String, std::time::Instant)>> = Mutex::new(None);
    if let Some((t, at)) = CACHE.lock().unwrap_or_else(|e| e.into_inner()).as_ref()
        && at.elapsed() < std::time::Duration::from_secs(45 * 60)
    {
        return Ok(t.clone());
    }
    let t = crate::auth::oauth::access_token_for(SUGGESTIONS_SCOPE).await?;
    *CACHE.lock().unwrap_or_else(|e| e.into_inner()) = Some((t.clone(), std::time::Instant::now()));
    Ok(t)
}

/// Teams' clientInfo header for these services.
pub(crate) fn client_info() -> String {
    let offset = chrono::Local::now().offset().local_minus_utc();
    let sign = if offset < 0 { '-' } else { '+' };
    let o = offset.abs();
    format!(
        "os=linux; osVer=1; proc=x86; lcid=en-us; deviceType=1; country=us; clientName=skypeteams; clientVer=1415/26276.513; utcOffset={sign}{:02}:{:02}",
        o / 3600,
        o % 3600 / 60
    )
}

async fn suggestions_get(
    client: &TeamsClient,
    url: &str,
    page: Option<usize>,
) -> Result<Option<serde_json::Value>> {
    let token = suggestions_token().await?;
    let mut rq = client
        .http()
        .get(url)
        .bearer_auth(token)
        .header("clientInfo", client_info())
        .header("X-Client-UI-Language", "en-us");
    if let Some(n) = page {
        rq = rq.header("Prefer", format!("odata.maxpagesize={n}"));
    }
    let r = rq.send().await?;
    if r.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(None);
    }
    Ok(Some(r.error_for_status()?.json().await?))
}

/// Every rated app's rating (one list for all apps; kept for the session,
/// as Teams keeps it).
async fn all_ratings(
    client: &TeamsClient,
) -> Result<std::sync::Arc<HashMap<String, serde_json::Value>>> {
    static CACHE: Mutex<Option<std::sync::Arc<HashMap<String, serde_json::Value>>>> =
        Mutex::new(None);
    if let Some(c) = CACHE.lock().unwrap_or_else(|e| e.into_inner()).clone() {
        return Ok(c);
    }
    let url = format!("{}/api/v2/apps/ratings", suggestions_base(client)?);
    let list = suggestions_get(client, &url, None)
        .await?
        .unwrap_or_default();
    let map: HashMap<String, serde_json::Value> = list
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|r| Some((r.get("id")?.as_str()?.to_lowercase(), r.clone())))
        .collect();
    let map = std::sync::Arc::new(map);
    *CACHE.lock().unwrap_or_else(|e| e.into_inner()) = Some(map.clone());
    Ok(map)
}

/// Your apps and their states (Teams' aggregated user entitlements:
/// `POST {mt}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned`
/// with `[]`), by lowercase app id.
pub async fn entitlements(client: &TeamsClient) -> Result<HashMap<String, String>> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let v: serde_json::Value = client
        .http()
        .post(format!(
            "{base}/beta/users/apps/aggregatedEntitlements?appbarview=userpinned"
        ))
        .bearer_auth(token)
        .json(&serde_json::json!([]))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    Ok(v.pointer("/value/userEntitlements")
        .and_then(|u| u.as_object())
        .into_iter()
        .flat_map(|o| o.values())
        .filter_map(|l| l.as_array())
        .flatten()
        .filter_map(|e| {
            Some((
                e.get("id")?.as_str()?.to_lowercase(),
                e.get("state")
                    .and_then(|s| s.as_str())
                    .unwrap_or_default()
                    .to_string(),
            ))
        })
        .collect())
}

/// An app's definition from the middle tier (Teams' batchedDefinitions).
pub async fn definition(client: &TeamsClient, app_id: &str) -> Result<serde_json::Value> {
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let v: serde_json::Value = client
        .http()
        .post(format!("{base}/beta/users/apps/batchedDefinitions"))
        .bearer_auth(token)
        .json(&serde_json::json!([app_id]))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let list = v.get("value").cloned().unwrap_or(v);
    list.as_array()
        .and_then(|a| a.first().cloned())
        .context("The app isn't available")
}

/// The reviews Teams lists (`first` of them, sorted), or the page at
/// `next`.
pub async fn reviews(
    client: &TeamsClient,
    app_id: &str,
    sort: ReviewSort,
    first: usize,
    next: Option<&str>,
) -> Result<ReviewPage> {
    let base = suggestions_base(client)?;
    let url = match next {
        Some(n) if n.starts_with(&base) => n.to_string(),
        Some(_) => anyhow::bail!("Unexpected reviews link"),
        None => {
            let enc =
                |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>();
            format!(
                "{base}/odata/v1/apps/{}/reviews?$filter={}&$orderby={}&$count=true",
                enc(app_id),
                enc(DEFAULT_REVIEWS_FILTER),
                enc(sort.order_by())
            )
        }
    };
    let v = suggestions_get(client, &url, Some(first))
        .await?
        .unwrap_or_default();
    let now = chrono::Utc::now();
    Ok(ReviewPage {
        count: v.get("@odata.count").and_then(|c| c.as_u64()).unwrap_or(0),
        reviews: v
            .get("value")
            .and_then(|a| a.as_array())
            .into_iter()
            .flatten()
            .map(|r| review_from(r, now))
            .collect(),
        next: str_at(&v, "@odata.nextLink").to_string(),
    })
}

/// Everything the About dialog shows but reviews and More like this.
pub async fn details(client: &TeamsClient, app_id: &str) -> Result<AppDetails> {
    let def = definition(client, app_id).await?;
    let base = suggestions_base(client)?;
    let enc: String = url::form_urlencoded::byte_serialize(app_id.as_bytes()).collect();
    let usage_url = format!("{base}/odata/v1/apps/{enc}?$expand=usage");
    let (ratings, usage, count, mine) = tokio::join!(
        all_ratings(client),
        suggestions_get(client, &usage_url, None),
        reviews(client, app_id, ReviewSort::HighestRating, 1, None),
        entitlements(client),
    );
    let state = mine
        .ok()
        .and_then(|m| m.get(&app_id.to_lowercase()).cloned());
    let rating = ratings
        .ok()
        .and_then(|r| r.get(&app_id.to_lowercase()).cloned())
        .unwrap_or_default();
    let installs = usage
        .ok()
        .flatten()
        .and_then(|u| u.pointer("/usage/installCount").and_then(|c| c.as_u64()))
        .unwrap_or(0);
    let reviews_count = count.map(|c| c.count).unwrap_or(0);
    Ok(details_from(
        &def,
        &rating,
        installs,
        reviews_count,
        "en-us",
        state.as_deref(),
    ))
}

/// The middle tier's catalog of apps (Teams' definitionsv2), kept for the
/// session.
pub async fn catalog(client: &TeamsClient) -> Result<std::sync::Arc<Vec<serde_json::Value>>> {
    static CACHE: Mutex<Option<std::sync::Arc<Vec<serde_json::Value>>>> = Mutex::new(None);
    if let Some(c) = CACHE.lock().unwrap_or_else(|e| e.into_inner()).clone() {
        return Ok(c);
    }
    let base = client
        .middle_tier_url()
        .context("No Teams middle-tier endpoint")?;
    let token = super::directory::middle_tier_token().await?;
    let mut all = Vec::new();
    let mut cont: Option<String> = None;
    for _ in 0..50 {
        let mut rq = client
            .http()
            .get(format!("{base}/beta/users/apps/definitionsv2"))
            .bearer_auth(&token);
        if let Some(c) = &cont {
            rq = rq.header("x-ms-continuation", c);
        }
        let v: serde_json::Value = rq.send().await?.error_for_status()?.json().await?;
        all.extend(
            v.pointer("/value/appDefinitions")
                .and_then(|a| a.as_array())
                .cloned()
                .unwrap_or_default(),
        );
        cont = v
            .pointer("/value/continuationToken")
            .and_then(|c| c.as_str())
            .filter(|c| !c.is_empty())
            .map(str::to_string);
        if cont.is_none() {
            break;
        }
    }
    let all = std::sync::Arc::new(all);
    *CACHE.lock().unwrap_or_else(|e| e.into_inner()) = Some(all.clone());
    Ok(all)
}

/// Teams' "More like this" for an app.
pub async fn similar(client: &TeamsClient, app_id: &str) -> Result<Vec<AppCard>> {
    let catalog = catalog(client).await?;
    let app = match catalog.iter().find(|d| str_at(d, "id") == app_id) {
        Some(a) => a.clone(),
        None => definition(client, app_id).await?,
    };
    let url = format!(
        "{}/api/v1/users/apps/suggestions",
        suggestions_base(client)?
    );
    let ranked: Vec<String> = async {
        let token = suggestions_token().await?;
        let v: serde_json::Value = client
            .http()
            .post(&url)
            .bearer_auth(token)
            .header("clientInfo", client_info())
            .json(&serde_json::json!([]))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        anyhow::Ok(
            v.get("value")
                .and_then(|a| a.as_array())
                .into_iter()
                .flatten()
                .filter_map(|s| {
                    s.get("teamsAppId")
                        .and_then(|i| i.as_str())
                        .map(str::to_string)
                })
                .collect(),
        )
    }
    .await
    .unwrap_or_default();
    let mine = entitlements(client).await.unwrap_or_default();
    Ok(more_like_this(&app, &catalog, &ranked, &mine))
}

/// Post a shared app to a chat or channel, as Teams' Share form posts it.
pub async fn share(
    client: &TeamsClient,
    conversation: &str,
    note: &str,
    d: &AppDetails,
    with_card: bool,
) -> Result<()> {
    let note_html = html_escape(note).replace('\n', "<br>");
    let body = share_message(
        &note_html,
        d,
        &uuid::Uuid::new_v4().to_string(),
        &client.display_name().unwrap_or_default(),
        with_card,
    );
    let url = format!(
        "{}/v1/users/ME/conversations/{}/messages",
        client.chat_service_url(),
        conversation
    );
    client.chat_post(&url, &body).await?;
    Ok(())
}

/// Post a review (Teams' Write a review): `anonymous` unless the person
/// ticks "Post my review publicly as …".
pub async fn post_review(
    client: &TeamsClient,
    app_id: &str,
    rating: u8,
    title: &str,
    content: &str,
    anonymous: bool,
) -> Result<()> {
    let enc: String = url::form_urlencoded::byte_serialize(app_id.as_bytes()).collect();
    let url = format!("{}/odata/v1/apps/{enc}/reviews", suggestions_base(client)?);
    let mut body = serde_json::json!({"rating": rating.clamp(1, 5), "anonymous": anonymous});
    if !title.trim().is_empty() {
        body["title"] = title.trim().into();
    }
    if !content.trim().is_empty() {
        body["content"] = content.trim().into();
    }
    client
        .http()
        .post(url)
        .bearer_auth(suggestions_token().await?)
        .header("clientInfo", client_info())
        .json(&body)
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

/// Report a review to AppSource (Teams' Report review): `reason` is
/// OffensiveContent, SpamAndAdvertising, InvalidReview or Other.
pub async fn report_review(
    client: &TeamsClient,
    app_id: &str,
    review_id: &str,
    reason: &str,
    comment: &str,
) -> Result<()> {
    if ![
        "OffensiveContent",
        "SpamAndAdvertising",
        "InvalidReview",
        "Other",
    ]
    .contains(&reason)
    {
        anyhow::bail!("Unknown report reason");
    }
    let enc = |s: &str| url::form_urlencoded::byte_serialize(s.as_bytes()).collect::<String>();
    let url = format!(
        "{}/odata/v1/apps/{}/reviews/{}/reports",
        suggestions_base(client)?,
        enc(app_id),
        enc(review_id)
    );
    client
        .http()
        .post(url)
        .bearer_auth(suggestions_token().await?)
        .header("clientInfo", client_info())
        .json(&serde_json::json!({"content": comment, "reason": reason}))
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Help's definition as the middle tier returned it (2026-11-09),
    /// trimmed to what the dialog reads.
    fn help() -> serde_json::Value {
        serde_json::json!({
            "id": "5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83",
            "name": "Help", "developerName": "Microsoft Corporation",
            "developerUrl": "https://products.office.com/microsoft-teams/group-chat-software",
            "shortDescription": "In-App Teams Help", "longDescription": "Help and Support content for Teams",
            "version": "1.2.23", "manifestVersion": "1.25",
            "categories": ["CustomerSupport", "Microsoft", "Productivity"],
            "staticTabs": [{"entityId": "help", "scopes": ["Personal"]}],
            "metaCapabilities": {"staticTabs": {"scopes": ["Personal"]}},
            "supportedHubs": [],
            "supportedLanguages": ["en-us", "et", "fil", "fi", "fr", "de", "el", "he", "hi", "hu", "is", "id", "it",
                "lv", "lt", "pl", "pt", "ro", "ru", "sr", "sk", "sl", "es", "sv", "th", "tr", "uk", "vi", "ar", "bg",
                "ca", "zh", "hr", "cs", "da", "nl", "cy", "ko", "ja", "nb", "ms"],
            "state": "InstalledAndPermanent",
            "privacyUrl": "https://privacy.microsoft.com/privacystatement",
            "termsOfUseUrl": "https://www.microsoft.com/servicesagreement",
        })
    }

    #[test]
    fn help_reads_as_teams_shows_it() {
        let rating = serde_json::json!({"average": 3.318, "count": 950,
            "breakdown": {"oneStar": 292, "twoStars": 64, "threeStars": 66, "fourStars": 106, "fiveStars": 422}});
        let d = details_from(
            &help(),
            &rating,
            0,
            219,
            "en-us",
            Some("InstalledAndPermanent"),
        );
        assert_eq!(d.works_in, "Teams");
        assert_eq!(
            (d.pricing_label.as_str(), d.pricing_sublabel.as_str()),
            ("Free", "Free to add and use")
        );
        assert_eq!(d.rating.average, "3.3");
        assert_eq!(d.rating.stars, [422, 106, 66, 64, 292]);
        assert_eq!(d.version, "1.2.23");
        assert!(d.installed);
        assert_eq!(d.capabilities.len(), 1);
        assert_eq!(d.capabilities[0].title, "Personal app");
        assert_eq!(
            d.capabilities[0].description,
            "Use the app privately outside of a chat, channel, or meeting."
        );
        // "English (United States) and 40 more".
        assert_eq!(d.language_first, "English (United States)");
        assert_eq!(d.languages.len(), 41);
        assert!(d.languages.contains(&"Français".to_string()));
        // Permissions overview: two columns, one group each.
        assert_eq!(d.permissions.len(), 2);
        assert_eq!(d.permissions[0].title, "Permission to read and access:");
        assert_eq!(
            d.permissions[0].groups[0].title,
            "Information related to you"
        );
        assert!(d.permissions[0].groups[0].items[0].starts_with("Access my profile information"));
        assert_eq!(
            d.permissions[1].title,
            "Permission to perform these actions:"
        );
        assert_eq!(
            d.permissions[1].groups[0].title,
            "Send and receive messages and notifications"
        );
        assert_eq!(
            d.permissions[1].groups[0].items[0].replace('\u{a0}', " "),
            "Receive messages and data that I provide to it."
        );
    }

    #[test]
    fn rsc_permissions_join_known_action_sets() {
        let def = serde_json::json!({
            "bots": [{"botId": "b", "scopes": ["Team", "GroupChat"]}],
            "authorization": {"permissions": {"resourceSpecific": [
                {"name": "ChannelMessage.Read.Group"}, {"name": "ChatMessage.Read.Chat"}, {"name": "Weird.Thing"}]}},
        });
        let keys = permission_keys(&def);
        assert!(keys.contains(&"app_details_basic_bots_permission".to_string()));
        assert!(keys.contains(&"app_details_team_and_chat_full_permission".to_string()));
        assert!(keys.contains(&"app_details_permission_channelmessage_read_group".to_string()));
        assert!(keys.contains(&"app_details_permission_teams_access".to_string()));
        let groups = permissions(&keys);
        // RSC reads land under "Information in chats, channels, and meetings".
        assert!(groups[0].groups.iter().any(|g| g.icon == "people-team"));
    }

    #[test]
    fn languages_and_numbers_format_as_teams() {
        assert_eq!(
            native_name("en-us").as_deref(),
            Some("English (United States)")
        );
        assert_eq!(native_name("FR").as_deref(), Some("Français"));
        assert_eq!(native_name("xx"), None);
        assert_eq!(
            list_format(&["Teams".into(), "Outlook".into(), "Copilot".into()]),
            "Teams, Outlook, and Copilot"
        );
        assert_eq!(compact(950), "950");
        assert_eq!(compact(1500), "1.5K");
        assert_eq!(compact(12000), "12K");
        assert_eq!(average_text(4.0), "4");
        assert_eq!(average_text(3.318), "3.3");
    }

    #[test]
    fn review_dates_read_as_date_fns_strict() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-11-09T10:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let at = |s: &str| {
            chrono::DateTime::parse_from_rfc3339(s)
                .unwrap()
                .with_timezone(&chrono::Utc)
        };
        assert_eq!(relative_time(at("2026-11-07T09:00:00Z"), now), "2 days ago");
        assert_eq!(relative_time(at("2025-09-25T18:45:56Z"), now), "1 year ago");
        assert_eq!(
            relative_time(at("2026-11-09T09:59:00Z"), now),
            "1 minute ago"
        );
        assert_eq!(
            relative_time(at("2026-08-01T10:00:00Z"), now),
            "3 months ago"
        );
    }

    #[test]
    fn more_like_this_follows_teams_worker() {
        let app = |id: &str, name: &str, dev: &str, cats: &[&str], state: &str| serde_json::json!({"id": id, "name": name, "developerName": dev, "categories": cats, "state": state});
        let me = app(
            "help",
            "Help",
            "MS",
            &["CustomerSupport", "Microsoft"],
            "InstalledAndPermanent",
        );
        let mut catalog = vec![me.clone()];
        // Six apps by the same developer, ranked first: left out.
        for i in 0..6 {
            catalog.push(app(
                &format!("ms{i}"),
                &format!("MS app {i}"),
                "MS",
                &["CustomerSupport"],
                "",
            ));
        }
        catalog.push(app(
            "old",
            "Old help",
            "MS",
            &["CustomerSupport"],
            "InstalledAndDeprecated",
        ));
        catalog.push(app(
            "have",
            "Have it",
            "Other",
            &["CustomerSupport"],
            "InstalledAndPermanent",
        ));
        catalog.push(app(
            "added",
            "Added",
            "Other",
            &["CustomerSupport"],
            "Installed",
        ));
        // Yours for good (an entitlement): left out, whatever the catalog says.
        let mine: HashMap<String, String> =
            [("have".to_string(), "InstalledAndPermanent".to_string())].into();
        catalog.push(app("ms6", "Walkie Talkie", "MS", &["CustomerSupport"], ""));
        catalog.push(app("x1", "Doorbell", "Other", &["CustomerSupport"], ""));
        catalog.push(app("x2", "Elsewhere", "Other", &["Education"], ""));
        let ranked: Vec<String> = (0..6).map(|i| format!("ms{i}")).collect();
        let got: Vec<String> = more_like_this(&me, &catalog, &ranked, &mine)
            .into_iter()
            .map(|c| c.name)
            .collect();
        assert_eq!(got, vec!["Added", "Walkie Talkie", "Doorbell"]);
    }

    #[test]
    fn shared_apps_post_as_teams_posts_them() {
        let rating = serde_json::json!({"average": 3.318, "count": 950, "breakdown": {}});
        let mut d = details_from(
            &help(),
            &rating,
            0,
            219,
            "en-us",
            Some("InstalledAndPermanent"),
        );
        d.icon = "https://res.cdn.office.net/help.png".into();
        let m = share_message(
            "Take a look at this app.",
            &d,
            "1442ca6d-0424-48b2-8966-fe70722c70cf",
            "OST Test 1",
            true,
        );
        let content = m["content"].as_str().unwrap();
        assert!(content.starts_with("<p>Take a look at this app.<br><br><a href=\"https://teams.microsoft.com/l/app/5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83?source=app-header-share-entrypoint\""));
        assert!(content.contains("itemid=\"app-preview-card-ps1442ca6d-0424-48b2-8966-fe70722c70cfapp-store-link-preview\""));
        let cards: serde_json::Value =
            serde_json::from_str(m["properties"]["cards"].as_str().unwrap()).unwrap();
        assert_eq!(cards[0]["appId"], APP_CARD_APP_ID);
        assert_eq!(cards[0]["sourceType"], "APP_HEADER_SHARE_ENTRYPOINT");
        let body = &cards[0]["content"]["body"][0]["items"];
        assert_eq!(body[1]["text"], "In-App Teams Help");
        assert_eq!(body[2]["columns"][1]["items"][0]["text"], "3.3");
        assert_eq!(body[2]["columns"][2]["items"][0]["text"], "(950 ratings)");
        assert_eq!(
            cards[0]["content"]["selectAction"]["id"],
            "5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83"
        );
    }
}

/// One of an app's device permissions as Teams' App permissions dialog
/// lists it (the manifest's devicePermissions, in its order).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DevicePermission {
    /// Teams' key: "media", "geolocation", "notifications", "midi" or
    /// "openExternal".
    pub kind: String,
    pub title: String,
    /// "" for External links (Teams shows no subtitle).
    pub subtitle: String,
}

/// The device permissions an app asks for, with Teams' strings
/// (extensibility app_device_permission_*).
pub fn device_permissions(def: &serde_json::Value) -> Vec<DevicePermission> {
    let open = "Only when app is open and in view";
    def.get("devicePermissions")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .filter_map(|d| {
            let (kind, title, subtitle) = match d.as_str()?.to_lowercase().as_str() {
                "media" => ("media", "Media (Camera, microphone, speakers)", open),
                "geolocation" => ("geolocation", "Location", open),
                "notifications" => ("notifications", "Notifications", "Always"),
                "midi" => ("midi", "MIDI devices", open),
                "openexternal" => ("openExternal", "External links", ""),
                _ => return None,
            };
            Some(DevicePermission { kind: kind.into(), title: title.into(), subtitle: subtitle.into() })
        })
        .collect()
}

/// Whether Teams turns an app's device permissions on by default (ECS
/// extensibility.autoApprovedDevicePermissionApps).
pub fn device_permissions_preapproved(app_id: &str) -> bool {
    super::ecs::setting("extensibility", "autoApprovedDevicePermissionApps")
        .and_then(|l| l.as_array().cloned())
        .unwrap_or_default()
        .iter()
        .any(|x| x.as_str().is_some_and(|x| x.eq_ignore_ascii_case(app_id)))
}

#[cfg(test)]
mod device_permission_tests {
    use super::*;

    #[test]
    fn listed_as_teams_lists_them() {
        // OneNote's manifest asks for media only.
        let def = serde_json::json!({"devicePermissions": ["media"]});
        let p = device_permissions(&def);
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].title, "Media (Camera, microphone, speakers)");
        assert_eq!(p[0].subtitle, "Only when app is open and in view");
        let all = device_permissions(&serde_json::json!({"devicePermissions": ["Geolocation", "Notifications", "OpenExternal"]}));
        assert_eq!(all.iter().map(|d| d.kind.as_str()).collect::<Vec<_>>(), ["geolocation", "notifications", "openExternal"]);
        assert_eq!(all[2].subtitle, "");
    }
}
