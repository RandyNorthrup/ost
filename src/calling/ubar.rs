//! The call window's control bar, built as Teams desktop builds its
//! "unified bar" (module 414673, docs/spec/call-and-meeting-window.md §1):
//! not from a fixed list but from the calling service's layout config.
//!
//! - [`ubar_layout.json`](ubar_layout.json) holds Teams' live settings:
//!   `ubarLayoutPresets[0]` (the `Inline` preset the live `ubarLayoutSetup`
//!   picks) and the `ubarLayoutOverrides` entries for the layouts OST's
//!   calls use (`default`, `oneToOneOrGroupCall`, `oneToOnePstn`,
//!   `consultAndAdd`).
//! - [`layout_name`] picks the layout as Teams' `eq` does; [`Layout::build`]
//!   walks the preset like `xQ.createLayoutMap`: controls not in the
//!   layout's `available` list are skipped, a nested control whose menu
//!   parent isn't available is promoted, and the layout's overrides move a
//!   menu control onto the bar as a group of its own before its root group.
//! - Dividers follow the group's grouping strategy (`cr`, `_$`), and
//!   [`overflow`] is Fluent's `Overflow`: the lowest priority leaves first
//!   (`AsFirst` 0, `AsLast` 500; `Docked` never), the last in bar order on
//!   ties; what leaves goes to the top of More, in bar order.

use serde::{Deserialize, Serialize};
use serde_json::Value;

const CONFIG: &str = include_str!("ubar_layout.json");

/// How a control leaves the bar when it doesn't fit.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Overflow {
    /// Priority 0: among the first to go.
    AsFirst,
    /// Priority 500: the last to go.
    AsLast,
    /// Never leaves the bar.
    Docked,
}

impl Overflow {
    fn parse(s: Option<&str>) -> Self {
        match s {
            Some("AsLast") => Overflow::AsLast,
            Some("Docked") => Overflow::Docked,
            _ => Overflow::AsFirst,
        }
    }

    /// Fluent's priority (`kc`); None for docked controls.
    pub fn priority(self) -> Option<u32> {
        match self {
            Overflow::AsFirst => Some(0),
            Overflow::AsLast => Some(500),
            Overflow::Docked => None,
        }
    }
}

/// How dividers fall between a slot's groups.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Grouping {
    /// A divider between every two non-empty groups.
    AlwaysKeep,
    /// A group of one merges into the next one, without a divider.
    MergeWithNext,
    /// A divider only before a group of more than one.
    MergeWithPrevious,
}

impl Grouping {
    fn parse(s: Option<&str>) -> Option<Self> {
        match s? {
            "AlwaysKeep" => Some(Grouping::AlwaysKeep),
            "MergeWithNext" => Some(Grouping::MergeWithNext),
            "MergeWithPrevious" => Some(Grouping::MergeWithPrevious),
            _ => None,
        }
    }
}

/// Which of Teams' layouts a call uses (`eq`, first match wins; only the
/// cases OST's calls can be).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutName {
    /// Meetings and group calls.
    Default,
    /// A 1:1 Teams call (callType P2P).
    OneToOneOrGroupCall,
    /// A 1:1 call with a phone number.
    OneToOnePstn,
    /// A consult call (`CONSULT_AND_ADD`).
    ConsultAndAdd,
}

impl LayoutName {
    fn config_name(self) -> &'static str {
        match self {
            LayoutName::Default => "default",
            LayoutName::OneToOneOrGroupCall => "oneToOneOrGroupCall",
            LayoutName::OneToOnePstn => "oneToOnePstn",
            LayoutName::ConsultAndAdd => "consultAndAdd",
        }
    }
}

/// The layout for a call: consult first, then 1:1 PSTN, then 1:1 (P2P),
/// else default (meetings and group calls alike).
pub fn layout_name(p2p: bool, pstn: bool, consult: bool) -> LayoutName {
    if consult {
        LayoutName::ConsultAndAdd
    } else if p2p && pstn {
        LayoutName::OneToOnePstn
    } else if p2p {
        LayoutName::OneToOneOrGroupCall
    } else {
        LayoutName::Default
    }
}

/// A control on the bar.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BarControl {
    pub name: String,
    pub overflow: Overflow,
    /// Enabled while the call is on hold (Teams disables the rest).
    pub on_hold: bool,
}

/// A run of controls from one preset group.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BarGroup {
    pub name: String,
    pub controls: Vec<BarControl>,
}

/// A More menu section and its controls (each a name; menus hold their
/// own sections).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MenuSection {
    pub name: String,
    pub items: Vec<MenuItem>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MenuItem {
    pub name: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub sections: Vec<MenuSection>,
}

/// The bar for a call: the middle slot's groups (right-justified, More and
/// the primary controls at its end), the end slot (Leave) and More's menu.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Layout {
    pub middle: Vec<BarGroup>,
    pub end: Vec<BarControl>,
    pub more: Vec<MenuSection>,
    pub grouping: Grouping,
}

#[derive(Deserialize)]
struct Config {
    preset: PresetNode,
    overrides: std::collections::HashMap<String, OverrideEntry>,
}

#[derive(Deserialize)]
struct PresetNode {
    #[serde(default)]
    groups: Vec<PresetGroup>,
}

#[derive(Deserialize)]
struct PresetGroup {
    name: String,
    #[serde(default)]
    items: Vec<PresetItem>,
}

#[derive(Deserialize)]
struct PresetItem {
    name: String,
    slot: Option<String>,
    #[serde(rename = "overflowBehaviour")]
    overflow: Option<String>,
    #[serde(rename = "isOnHold", default)]
    on_hold: bool,
    #[serde(default)]
    groups: Vec<PresetGroup>,
}

#[derive(Deserialize)]
struct OverrideEntry {
    available: Vec<String>,
    #[serde(default)]
    overrides: std::collections::HashMap<String, Vec<Value>>,
    #[serde(default)]
    settings: Value,
}

fn config() -> &'static Config {
    static C: std::sync::OnceLock<Config> = std::sync::OnceLock::new();
    C.get_or_init(|| serde_json::from_str(CONFIG).expect("ubar_layout.json"))
}

impl Layout {
    /// Build a layout. `shown` is each control's visibility rule (Teams'
    /// `MQ.calculateVisibilityOverrides` plus the control's own check):
    /// controls whose rule fails are left out, and a menu with nothing
    /// left in it disappears.
    pub fn build(name: LayoutName, shown: &dyn Fn(&str) -> bool) -> Layout {
        let cfg = config();
        let entry = cfg
            .overrides
            .get(name.config_name())
            .or_else(|| cfg.overrides.get("default"))
            .expect("default layout");
        let available = |n: &str| entry.available.iter().any(|a| a == n);
        // Controls the layout moves onto the bar's middle slot.
        let moved: Vec<String> = entry
            .overrides
            .get("horizontalMiddleEnd")
            .into_iter()
            .flatten()
            .filter_map(|o| o.get("name").and_then(Value::as_str).map(str::to_string))
            .collect();
        let grouping = Grouping::parse(entry.settings.get("groupingStrategy").and_then(Value::as_str))
            .unwrap_or(Grouping::MergeWithNext);

        let mut middle = Vec::new();
        let mut end = Vec::new();
        let mut more = Vec::new();
        for group in &cfg.preset.groups {
            let mut controls = Vec::new();
            // Menu controls the overrides lift out of this group's menus:
            // their own group, placed before this one, in preset order.
            let mut lifted = Vec::new();
            for item in &group.items {
                collect_moved(item, &moved, &available, shown, &mut lifted);
                if !available(&item.name) && item.name != "MoreButton" {
                    continue;
                }
                let visible = item.name == "MoreButton" || shown(&item.name);
                if item.name == "MoreButton" {
                    more = menu_sections(&item.groups, &available, shown, &moved);
                }
                if !visible {
                    continue;
                }
                let control = BarControl {
                    name: item.name.clone(),
                    overflow: Overflow::parse(item.overflow.as_deref()),
                    on_hold: item.on_hold,
                };
                match item.slot.as_deref() {
                    Some("horizontalMiddleEnd") => controls.push(control),
                    Some("horizontalEnd") => end.push(control),
                    _ => {}
                }
            }
            if !lifted.is_empty() {
                middle.push(BarGroup { name: format!("{}Overrides", group.name), controls: lifted });
            }
            if !controls.is_empty() {
                middle.push(BarGroup { name: group.name.clone(), controls });
            }
        }
        Layout { middle, end, more, grouping }
    }

    /// The middle slot in bar order, with dividers: `None` is a divider.
    pub fn with_dividers(&self, kept: &dyn Fn(&str) -> bool) -> Vec<Option<&BarControl>> {
        let groups: Vec<Vec<&BarControl>> = self
            .middle
            .iter()
            .map(|g| g.controls.iter().filter(|c| kept(&c.name)).collect::<Vec<_>>())
            .filter(|g| !g.is_empty())
            .collect();
        let mut out = Vec::new();
        for (i, g) in groups.iter().enumerate() {
            if i > 0 {
                let divider = match self.grouping {
                    Grouping::AlwaysKeep => true,
                    Grouping::MergeWithNext => groups[i - 1].len() > 1,
                    Grouping::MergeWithPrevious => g.len() > 1,
                };
                if divider {
                    out.push(None);
                }
            }
            out.extend(g.iter().map(|c| Some(*c)));
        }
        out
    }
}

/// The controls under `item` that the layout moves onto the bar (in
/// preset order), when available and shown.
fn collect_moved(
    item: &PresetItem,
    moved: &[String],
    available: &dyn Fn(&str) -> bool,
    shown: &dyn Fn(&str) -> bool,
    out: &mut Vec<BarControl>,
) {
    for g in &item.groups {
        for child in &g.items {
            if moved.contains(&child.name) {
                // A moved menu shows only with something in it.
                let has_content = child.groups.is_empty()
                    || !menu_sections(&child.groups, available, shown, &[]).is_empty();
                if available(&child.name) && shown(&child.name) && has_content {
                    out.push(BarControl {
                        name: child.name.clone(),
                        overflow: Overflow::AsFirst,
                        on_hold: child.on_hold,
                    });
                }
            } else {
                collect_moved(child, moved, available, shown, out);
            }
        }
    }
}

/// A menu's sections: available, shown controls; a nested menu that isn't
/// available gives its controls to the section it sits in (Teams promotes
/// them to the nearest available ancestor); empty sections and menus are
/// dropped; controls moved onto the bar aren't repeated.
fn menu_sections(
    groups: &[PresetGroup],
    available: &dyn Fn(&str) -> bool,
    shown: &dyn Fn(&str) -> bool,
    moved: &[String],
) -> Vec<MenuSection> {
    let mut out = Vec::new();
    for g in groups {
        let mut items = Vec::new();
        for item in &g.items {
            menu_items(item, available, shown, moved, &mut items);
        }
        if !items.is_empty() {
            out.push(MenuSection { name: g.name.clone(), items });
        }
    }
    out
}

fn menu_items(
    item: &PresetItem,
    available: &dyn Fn(&str) -> bool,
    shown: &dyn Fn(&str) -> bool,
    moved: &[String],
    out: &mut Vec<MenuItem>,
) {
    if moved.contains(&item.name) {
        return;
    }
    if available(&item.name) {
        if item.groups.is_empty() {
            if shown(&item.name) {
                out.push(MenuItem { name: item.name.clone(), sections: Vec::new() });
            }
        } else {
            let sections = menu_sections(&item.groups, available, shown, moved);
            if !sections.is_empty() && shown(&item.name) {
                out.push(MenuItem { name: item.name.clone(), sections });
            }
        }
        return;
    }
    // Not available: its children move up to this section.
    for g in &item.groups {
        for child in &g.items {
            menu_items(child, available, shown, moved, out);
        }
    }
}

/// Fluent's `Overflow` for the middle slot: which controls leave the bar
/// so that the rest fit in `available` px. `widths[i]` is the width of the
/// i-th control in bar order (dividers excluded); `divider` is a divider's
/// width, added wherever [`Layout::with_dividers`] puts one. Returns the
/// names that overflow, in bar order.
pub fn overflow(layout: &Layout, widths: &dyn Fn(&str) -> f64, divider: f64, available: f64) -> Vec<String> {
    let order: Vec<&BarControl> = layout.middle.iter().flat_map(|g| g.controls.iter()).collect();
    let mut gone: Vec<String> = Vec::new();
    loop {
        let kept = |n: &str| !gone.iter().any(|g| g == n);
        let used: f64 = layout
            .with_dividers(&kept)
            .iter()
            .map(|c| c.map_or(divider, |c| widths(&c.name)))
            .sum();
        if used <= available {
            break;
        }
        // The lowest priority goes first; on ties the last in bar order.
        let next = order
            .iter()
            .enumerate()
            .filter(|(_, c)| kept(&c.name))
            .filter_map(|(i, c)| c.overflow.priority().map(|p| (p, i, c)))
            .min_by(|a, b| a.0.cmp(&b.0).then(b.1.cmp(&a.1)));
        match next {
            Some((_, _, c)) => gone.push(c.name.clone()),
            None => break,
        }
    }
    order
        .iter()
        .filter(|c| gone.contains(&c.name))
        .map(|c| c.name.clone())
        .collect()
}

/// What the call window knows about the call, for Teams' visibility rules
/// (`MQ.calculateVisibilityOverrides` and each control's own check, §1.4).
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Facts {
    /// A 1:1 call (callType P2P).
    pub p2p: bool,
    /// With a phone number.
    pub pstn: bool,
    /// A consult call.
    pub consult: bool,
    /// A scheduled meeting (joined from its link), not a chat's group call
    /// or Meet now.
    pub scheduled: bool,
    /// Your meeting role is Organizer.
    pub organizer: bool,
    /// You put the call on hold.
    pub on_hold: bool,
    /// Someone else presents, and their content isn't popped out.
    pub can_pop_out: bool,
    /// The meeting allows reactions.
    pub reactions: bool,
}

impl Facts {
    /// Whether Teams shows `control` (bar controls and More's items OST
    /// has).
    pub fn shows(&self, control: &str) -> bool {
        match control {
            "PopoutContentButton" => self.can_pop_out,
            "ResumeButton" => self.p2p && self.on_hold,
            "CallTransferButtonV2" | "CallConsultativeTransferButtonV2" => self.p2p,
            "ChatButton" => !self.pstn,
            "RosterButton" | "ViewModeButton" | "VideoButton" | "MicrophoneButton" | "ShareButton"
            | "CallButton" | "DialpadButton" => true,
            // Not in 1:1 calls (the component renders nothing for P2P).
            "RaiseHandsButton" => !self.p2p,
            "ReactionButton" => !self.p2p && self.reactions,
            "OrganizerControlButton" => self.organizer,
            // Private scheduled meetings (not Meet now: its flag is off).
            "MeetingDetailsButton" => self.scheduled,
            "StartBreakoutRoomButton" => self.scheduled && self.organizer,
            "MeetingAppsAddButton" => !self.pstn,
            "HoldButton" => self.p2p && !self.on_hold,
            "MergeCallsButton" => self.consult,
            // In More (live: the AV framework replaces Devices with these).
            "AudioSettingsButton" | "CameraEffectsButton" => true,
            // Meetings (Teams' isMeeting), not a chat's group call.
            "MeetingInfoButton" => self.scheduled,
            // Record and transcribe ▸ (the meeting's call recorder).
            // Show or hide the Transcript pane (the call window adds it
            // once a transcript has run, as Teams' hasBeenStarted).
            "RecordingMenuControl" | "RecordingButton" | "TranscriptButton" | "TranscriptPanelButton" => {
                self.scheduled
            }
            // Language and speech ▸ Show live captions (the meeting's
            // recorder provides them).
            "LanguageSpeechMenuControl" | "ClosedCaptionsButton" => self.scheduled,
            // Settings ▸ Accessibility settings (the in-meeting pane).
            "SettingsMenuControl" | "AccessibilitySettingsButton" => self.scheduled,
            _ => false,
        }
    }
}

/// The bar laid out for a width, as the call window draws it.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Arranged {
    /// The middle slot in order; "|" is a divider.
    pub bar: Vec<String>,
    pub end: Vec<String>,
    /// Controls that didn't fit: More's first items, in bar order.
    pub overflowed: Vec<String>,
    /// More's own sections (each a list of control names; a menu control
    /// is followed by its sections).
    pub more: Vec<MenuSection>,
    /// Controls Teams keeps enabled on hold (the rest are disabled).
    pub on_hold: Vec<String>,
}

/// Lay the bar out for `facts` in `available` px of middle slot.
pub fn arrange(facts: &Facts, widths: &dyn Fn(&str) -> f64, divider: f64, available: f64) -> Arranged {
    let layout = Layout::build(layout_name(facts.p2p, facts.pstn, facts.consult), &|n| facts.shows(n));
    let overflowed = overflow(&layout, widths, divider, available);
    let kept = |n: &str| !overflowed.iter().any(|o| o == n);
    let bar = layout
        .with_dividers(&kept)
        .iter()
        .map(|c| c.map_or_else(|| "|".to_string(), |c| c.name.clone()))
        .collect();
    let on_hold = layout
        .middle
        .iter()
        .flat_map(|g| &g.controls)
        .chain(&layout.end)
        .filter(|c| c.on_hold)
        .map(|c| c.name.clone())
        .collect();
    Arranged {
        bar,
        end: layout.end.iter().map(|c| c.name.clone()).collect(),
        overflowed,
        more: layout.more,
        on_hold,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(l: &Layout) -> Vec<String> {
        l.with_dividers(&|_| true)
            .iter()
            .map(|c| c.map_or("|".to_string(), |c| c.name.clone()))
            .collect()
    }

    /// What a meeting organizer sees in a scheduled meeting.
    fn meeting_rule(n: &str) -> bool {
        matches!(
            n,
            "ChatButton" | "RosterButton" | "RaiseHandsButton" | "ReactionButton" | "ViewModeButton"
                | "OrganizerControlButton" | "MeetingDetailsButton" | "StartBreakoutRoomButton"
                | "MeetingAppsAddButton" | "VideoButton" | "MicrophoneButton" | "ShareButton"
                | "CallButton" | "GridButton" | "SpeakerViewButton" | "DeviceSettingsButton"
                | "MeetingHelpButton" | "MeetingInfoButton" | "SettingsMenuControl"
        )
    }

    #[test]
    fn a_meeting_bar_in_teams_order() {
        let l = Layout::build(LayoutName::Default, &meeting_rule);
        assert_eq!(
            names(&l),
            [
                "ChatButton", "RosterButton", "RaiseHandsButton", "ReactionButton", "ViewModeButton",
                "OrganizerControlButton", "MeetingDetailsButton", "StartBreakoutRoomButton",
                "MeetingAppsAddButton", "MoreButton", "|", "VideoButton", "MicrophoneButton", "ShareButton"
            ]
        );
        assert_eq!(l.end.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(), ["CallButton"]);
        // View's own choices stay in View's menu, not in More.
        assert!(!l.more.iter().flat_map(|s| &s.items).any(|i| i.name == "GridButton"));
        // More: Info in settings, then Settings ▸ Devices, then Report a problem.
        let more: Vec<&str> = l.more.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(more, ["settings", "help"]);
        let settings = &l.more[0].items;
        assert_eq!(settings[0].name, "MeetingInfoButton");
        assert_eq!(settings[1].name, "SettingsMenuControl");
        assert_eq!(settings[1].sections[0].items[0].name, "DeviceSettingsButton");
    }

    #[test]
    fn a_one_to_one_bar_lifts_dial_pad_and_hold() {
        let rule = |n: &str| {
            matches!(
                n,
                "CallTransferButtonV2" | "CallConsultativeTransferButtonV2" | "ChatButton" | "RosterButton"
                    | "RaiseHandsButton" | "ViewModeButton" | "MeetingAppsAddButton" | "VideoButton"
                    | "MicrophoneButton" | "ShareButton" | "CallButton" | "DialpadButton" | "HoldButton"
                    | "CallTransferMenuControl" | "MergeCallsButton" | "CallParkButton"
            )
        };
        let l = Layout::build(LayoutName::OneToOneOrGroupCall, &rule);
        // 1:1 layout has no React; Raise never shows in P2P (the rule says
        // so in OST, here it is left in to see the order).
        assert_eq!(
            names(&l),
            [
                "CallTransferButtonV2", "CallConsultativeTransferButtonV2", "|", "DialpadButton", "HoldButton",
                "|", "ChatButton", "RosterButton", "RaiseHandsButton", "ViewModeButton", "MeetingAppsAddButton",
                "MoreButton", "|", "VideoButton", "MicrophoneButton", "ShareButton"
            ]
        );
        // The transfer menu has nothing left (V1 buttons hidden), so it
        // isn't on the bar; Call ▸ isn't available, so Merge and Park are
        // promoted into More's callingOverflow section.
        let calling = l.more.iter().find(|s| s.name == "callingOverflow").expect("callingOverflow");
        let items: Vec<&str> = calling.items.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(items, ["MergeCallsButton", "CallParkButton"]);
    }

    #[test]
    fn grouping_strategies_place_dividers_as_teams() {
        let rule = |n: &str| matches!(n, "PopoutContentButton" | "ChatButton" | "VideoButton" | "CallButton");
        let l = Layout::build(LayoutName::Default, &rule);
        // MergeWithNext: Pop out alone merges into Chat's group; Chat and
        // More are two, so a divider before Camera.
        assert_eq!(names(&l), ["PopoutContentButton", "ChatButton", "MoreButton", "|", "VideoButton"]);
        let l = Layout::build(LayoutName::OneToOnePstn, &|n| matches!(n, "HoldButton" | "ChatButton" | "MicrophoneButton"));
        // AlwaysKeep.
        assert_eq!(names(&l), ["HoldButton", "|", "ChatButton", "MoreButton", "|", "MicrophoneButton"]);
    }

    #[test]
    fn overflow_leaves_in_teams_order() {
        let l = Layout::build(LayoutName::Default, &meeting_rule);
        let w = |n: &str| if n == "MicrophoneButton" || n == "VideoButton" { 74.0 } else { 56.0 };
        // Everything fits.
        assert!(overflow(&l, &w, 17.0, 2000.0).is_empty());
        let full: f64 = 10.0 * 56.0 + 17.0 + 74.0 * 2.0 + 56.0;
        assert!(overflow(&l, &w, 17.0, full).is_empty());
        // One short: Apps leaves first (the last AsFirst control).
        assert_eq!(overflow(&l, &w, 17.0, full - 1.0), ["MeetingAppsAddButton"]);
        // Then Rooms, Notes, Controls, View, People, Chat; React and Raise last.
        let gone = overflow(&l, &w, 17.0, full - 7.0 * 56.0);
        assert_eq!(
            gone,
            ["ChatButton", "RosterButton", "ViewModeButton", "OrganizerControlButton", "MeetingDetailsButton",
             "StartBreakoutRoomButton", "MeetingAppsAddButton"]
        );
        let gone = overflow(&l, &w, 17.0, 0.0);
        assert!(gone.contains(&"RaiseHandsButton".to_string()) && gone.contains(&"ReactionButton".to_string()));
        assert!(!gone.contains(&"MoreButton".to_string()) && !gone.contains(&"ShareButton".to_string()));
    }

    #[test]
    fn arranges_a_narrow_meeting_bar() {
        let facts = Facts { scheduled: true, organizer: true, reactions: true, ..Default::default() };
        let w = |_: &str| 56.0;
        let wide = arrange(&facts, &w, 17.0, 5000.0);
        assert!(wide.overflowed.is_empty());
        assert_eq!(wide.bar.first().map(String::as_str), Some("ChatButton"));
        assert_eq!(wide.end, ["CallButton"]);
        assert!(wide.on_hold.contains(&"MicrophoneButton".to_string()));
        assert!(!wide.on_hold.contains(&"VideoButton".to_string()));
        let narrow = arrange(&facts, &w, 17.0, 6.0 * 56.0 + 17.0);
        // Raise, React, More | Camera, Mic, Share.
        assert_eq!(narrow.bar, ["RaiseHandsButton", "ReactionButton", "MoreButton", "|", "VideoButton", "MicrophoneButton", "ShareButton"]);
        assert_eq!(narrow.overflowed[0], "ChatButton");
        let audio = narrow.more.iter().flat_map(|s| &s.items).any(|i| i.name == "AudioSettingsButton");
        assert!(audio, "More keeps Audio settings");
        // A group call: no Notes, Rooms or Controls.
        let group = arrange(&Facts { reactions: true, ..Default::default() }, &w, 17.0, 5000.0);
        assert!(!group.bar.iter().any(|n| n == "MeetingDetailsButton" || n == "StartBreakoutRoomButton" || n == "OrganizerControlButton"));
        // 1:1 on hold: Resume, no Hold.
        let held = arrange(&Facts { p2p: true, on_hold: true, ..Default::default() }, &w, 17.0, 5000.0);
        assert!(held.bar.contains(&"ResumeButton".to_string()) && !held.bar.contains(&"HoldButton".to_string()));
        assert!(!held.bar.contains(&"RaiseHandsButton".to_string()));
    }

    #[test]
    fn picks_teams_layouts() {
        assert_eq!(layout_name(false, false, false), LayoutName::Default);
        assert_eq!(layout_name(true, false, false), LayoutName::OneToOneOrGroupCall);
        assert_eq!(layout_name(true, true, false), LayoutName::OneToOnePstn);
        assert_eq!(layout_name(true, false, true), LayoutName::ConsultAndAdd);
    }
}
