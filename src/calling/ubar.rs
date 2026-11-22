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
//! - Teams' "New meeting controls" (Settings ▸ General ▸ Meeting, a Teams
//!   Labs feature) switches `ubarLayoutSetup` to `InlineCentered`, which
//!   picks `ubarLayoutPresets[1]` (kept here as `centered`): Mic, Camera
//!   and Share first, More's grid and list, Leave apart, and the user's
//!   own arrangement ([`Customization`]: Pin, Unpin, Move before/after).
//!   docs/spec/new-meeting-controls.md.

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
    /// Watching a town hall's stream (Teams' isStreamingClient: call mode
    /// Streaming).
    StreamingClient,
}

impl LayoutName {
    fn config_name(self) -> &'static str {
        match self {
            LayoutName::Default => "default",
            LayoutName::OneToOneOrGroupCall => "oneToOneOrGroupCall",
            LayoutName::OneToOnePstn => "oneToOnePstn",
            LayoutName::ConsultAndAdd => "consultAndAdd",
            LayoutName::StreamingClient => "streamingClient",
        }
    }
}

/// The layout for a call: consult first, then 1:1 PSTN, then 1:1 (P2P),
/// then a town hall's stream, else default (meetings and group calls
/// alike).
pub fn layout_name(p2p: bool, pstn: bool, consult: bool) -> LayoutName {
    layout_for(p2p, pstn, consult, false)
}

/// [`layout_name`] with Teams' streaming client case.
pub fn layout_for(p2p: bool, pstn: bool, consult: bool, streaming: bool) -> LayoutName {
    if consult {
        LayoutName::ConsultAndAdd
    } else if p2p && pstn {
        LayoutName::OneToOnePstn
    } else if p2p {
        LayoutName::OneToOneOrGroupCall
    } else if streaming {
        LayoutName::StreamingClient
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
    /// The group's own grouping strategy (else the layout's).
    #[serde(skip)]
    pub grouping: Option<Grouping>,
    /// The user may reorder and unpin this group's controls
    /// (`layoutCustomizationBehaviour` All).
    pub customizable: bool,
}

/// A More menu section and its controls (each a name; menus hold their
/// own sections).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MenuSection {
    pub name: String,
    pub items: Vec<MenuItem>,
    /// Drawn as Teams' grid of labelled buttons (`MenuGridControls`)
    /// rather than a list.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub grid: bool,
}

/// The user's arrangement of the new controls (Teams keeps it per client:
/// `stageSettings.callingControlsPreferences`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Customization {
    /// Controls moved off the bar into More (the most recent first).
    pub unpinned: Vec<String>,
    /// Controls of More's grid pinned to the bar, in the order pinned.
    pub pinned: Vec<String>,
    /// The customizable groups' controls in the user's order.
    pub order: Vec<String>,
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
    /// `ubarLayoutPresets[1]`, the `InlineCentered` preset.
    centered: PresetNode,
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
    #[serde(rename = "groupingStrategy")]
    grouping: Option<String>,
    #[serde(rename = "layoutCustomizationBehaviour")]
    customization: Option<String>,
    #[serde(rename = "rendererLibrary")]
    renderer: Option<String>,
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

/// The controls Teams' presets mark `isE2EEHidden`: left out of an
/// end-to-end encrypted call (recording, transcription, transfer, park,
/// merge, Copilot, apps…).
pub fn e2ee_hidden(name: &str) -> bool {
    static NAMES: std::sync::OnceLock<std::collections::HashSet<String>> = std::sync::OnceLock::new();
    NAMES
        .get_or_init(|| {
            fn walk(v: &Value, out: &mut std::collections::HashSet<String>) {
                match v {
                    Value::Object(o) => {
                        if o.get("isE2EEHidden").and_then(Value::as_bool) == Some(true)
                            && let Some(n) = o.get("name").and_then(Value::as_str)
                        {
                            out.insert(n.to_string());
                        }
                        o.values().for_each(|c| walk(c, out));
                    }
                    Value::Array(a) => a.iter().for_each(|c| walk(c, out)),
                    _ => {}
                }
            }
            let mut out = std::collections::HashSet::new();
            if let Ok(v) = serde_json::from_str::<Value>(CONFIG) {
                walk(&v, &mut out);
            }
            out
        })
        .contains(name)
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
        Self::build_with(name, false, &Customization::default(), shown)
    }

    /// Build a layout from Teams' current preset, or (`centered`) from the
    /// new meeting controls' preset with the user's arrangement applied.
    pub fn build_with(
        name: LayoutName,
        centered: bool,
        custom: &Customization,
        shown: &dyn Fn(&str) -> bool,
    ) -> Layout {
        let mut layout = Self::build_preset(name, centered, shown);
        if centered {
            layout.customize(custom, shown);
        }
        layout
    }

    fn build_preset(name: LayoutName, centered: bool, shown: &dyn Fn(&str) -> bool) -> Layout {
        let cfg = config();
        let preset = if centered { &cfg.centered } else { &cfg.preset };
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
        for group in &preset.groups {
            let mut controls = Vec::new();
            // Menu controls the overrides lift out of this group's menus:
            // their own group, placed before this one, in preset order.
            let mut lifted = Vec::new();
            let mut more_moved = false;
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
                // A layout that names More among its moved controls
                // (`isDisconnected`, the streamingClient layout) takes it
                // out of its group into the moved controls' group, after
                // what it lifted (Teams' attendee bar: Q&A, Captions, More).
                if item.name == "MoreButton" && moved.iter().any(|m| m == "MoreButton") {
                    lifted.push(control);
                    more_moved = true;
                    continue;
                }
                match item.slot.as_deref() {
                    Some("horizontalMiddleEnd") => controls.push(control),
                    Some("horizontalEnd") => end.push(control),
                    _ => {}
                }
            }
            let lifted_group = (!lifted.is_empty()).then(|| BarGroup {
                name: format!("{}Overrides", group.name),
                controls: lifted,
                grouping: None,
                customizable: false,
            });
            // Lifted controls go before their group, unless More went with
            // them: then after it, at the middle slot's end.
            if !more_moved && let Some(g) = &lifted_group {
                middle.push(g.clone());
            }
            // The new controls keep each group, even an empty one, so the
            // user's pins have somewhere to go.
            if !controls.is_empty() || (centered && group.customization.as_deref() == Some("All")) {
                middle.push(BarGroup {
                    name: group.name.clone(),
                    controls,
                    grouping: Grouping::parse(group.grouping.as_deref()),
                    customizable: group.customization.as_deref() == Some("All"),
                });
            }
            if more_moved && let Some(g) = lifted_group {
                middle.push(g);
            }
        }
        Layout { middle, end, more, grouping }
    }

    /// The user's arrangement: unpinned controls leave the bar for the
    /// front of More's grid, pinned grid controls join the end of the
    /// first customizable group, and customizable groups take the user's
    /// order.
    fn customize(&mut self, custom: &Customization, shown: &dyn Fn(&str) -> bool) {
        let in_grid: Vec<String> = self
            .more
            .iter()
            .filter(|s| s.grid)
            .flat_map(|s| s.items.iter().map(|i| i.name.clone()))
            .collect();
        let pinned: Vec<String> = custom
            .pinned
            .iter()
            .filter(|n| in_grid.contains(n) && pinnable(n) && !custom.unpinned.contains(n))
            .cloned()
            .collect();
        let mut unpinned = Vec::new();
        let first_custom = self.middle.iter().position(|g| g.customizable);
        for (gi, g) in self.middle.iter_mut().enumerate() {
            if !g.customizable {
                continue;
            }
            g.controls.retain(|c| {
                let gone = custom.unpinned.contains(&c.name);
                if gone {
                    unpinned.push(c.name.clone());
                }
                !gone
            });
            if Some(gi) == first_custom {
                for n in &pinned {
                    g.controls.push(BarControl { name: n.clone(), overflow: Overflow::AsFirst, on_hold: false });
                }
            }
            if !custom.order.is_empty() {
                let default: Vec<String> = g.controls.iter().map(|c| c.name.clone()).collect();
                let key = |n: &str| {
                    custom
                        .order
                        .iter()
                        .position(|o| o == n)
                        .unwrap_or(custom.order.len() + default.iter().position(|d| d == n).unwrap_or(0))
                };
                g.controls.sort_by_key(|c| key(&c.name));
            }
        }
        self.middle.retain(|g| !g.controls.is_empty());
        // Unpinned controls head the grid, the most recently unpinned first.
        unpinned.sort_by_key(|n| custom.unpinned.iter().position(|u| u == n));
        if let Some(grid) = self.more.iter_mut().find(|s| s.grid) {
            grid.items.retain(|i| !pinned.contains(&i.name));
            for (i, n) in unpinned.iter().enumerate() {
                if shown(n) {
                    grid.items.insert(i, MenuItem { name: n.clone(), sections: Vec::new() });
                }
            }
        }
    }

    /// The middle slot in bar order, with dividers: `None` is a divider.
    pub fn with_dividers(&self, kept: &dyn Fn(&str) -> bool) -> Vec<Option<&BarControl>> {
        let groups: Vec<(Grouping, Vec<&BarControl>)> = self
            .middle
            .iter()
            .map(|g| (g.grouping.unwrap_or(self.grouping), g.controls.iter().filter(|c| kept(&c.name)).collect::<Vec<_>>()))
            .filter(|g| !g.1.is_empty())
            .collect();
        let mut out = Vec::new();
        for (i, (strategy, g)) in groups.iter().enumerate() {
            if i > 0 {
                // The group's own strategy, else the layout's.
                let divider = match strategy {
                    Grouping::AlwaysKeep => true,
                    Grouping::MergeWithNext => groups[i - 1].1.len() > 1,
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
            let grid = g.renderer.as_deref() == Some("MenuGridControls");
            out.push(MenuSection { name: g.name.clone(), items, grid });
        }
    }
    out
}

/// Whether the user can pin a grid control to the bar (Teams' Docked
/// controls stay where they are).
pub fn pinnable(name: &str) -> bool {
    name != "MeetingAppsAddButton"
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
        // View keeps its own menu (the call window builds it).
        if item.groups.is_empty() || item.name == "ViewModeButton" {
            if shown(&item.name) {
                out.push(MenuItem { name: item.name.clone(), sections: Vec::new() });
            }
        } else {
            // A menu control needs something in it; a button with a menu
            // of its own (the new controls' Record, Transcribe) shows
            // without one.
            let sections = menu_sections(&item.groups, available, shown, moved);
            if (!sections.is_empty() || !item.name.ends_with("MenuControl")) && shown(&item.name) {
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
    /// A Meet now meeting (Teams' ad hoc meeting: a channel's Meet now). A
    /// meeting all the same (Teams' isMeeting, not isGroupCall): Teams
    /// shows it a meeting's controls, except Notes, which an ad hoc
    /// channel meeting doesn't have (TASK-0208).
    pub adhoc: bool,
    /// Your meeting role is Organizer.
    pub organizer: bool,
    /// You put the call on hold.
    pub on_hold: bool,
    /// Someone else presents, and their content isn't popped out.
    pub can_pop_out: bool,
    /// The meeting allows reactions.
    pub reactions: bool,
    /// A breakout room you're assigned to is open and you're not in it
    /// (Teams' "Join room").
    pub room_to_join: bool,
    /// In a breakout room whose organizer lets people go back (Teams'
    /// "Return").
    pub can_return_to_main: bool,
    /// This call is a breakout room (Teams shows no Notes there).
    pub breakout_room: bool,
    /// Teams' New meeting controls are on (the `InlineCentered` layout).
    pub centered: bool,
    /// Teams' test call with the Echo bot (measured 2026-11-16: no Chat
    /// or People on its bar; 2026-11-18: no Apps).
    pub echo: bool,
    /// Copilot in meetings for this user (a Copilot licence; Teams'
    /// shouldEnableMeetingCollabButton with useAIFeatureLicense).
    pub copilot: bool,
    /// Someone else shares and can be controlled from here (their
    /// AvailableAck came: Teams' ScreensharingControlButton).
    pub can_take_control: bool,
    /// The user's arrangement of the new controls.
    pub customization: Customization,
    /// The meeting offers phone audio with dial-in (Teams' PstnButton:
    /// `pstnCapabilities.isDialInEnabled && isPSTNEnabled` and dial-in
    /// details).
    pub call_me: bool,
    /// Teams' Facilitator entry point (More ▸ Facilitator ▸): a Copilot
    /// licence in a scheduled meeting.
    pub facilitator: bool,
    /// A town hall (Teams' isTownhall: `forceAttendeeStreaming` or a
    /// `scheduledTownhall` conversation).
    pub town_hall: bool,
    /// A webinar (its template).
    pub webinar: bool,
    /// Your meeting role is Attendee.
    pub attendee: bool,
    /// Watching the meeting's stream as a town hall's attendee (Teams'
    /// isStreamingClient).
    pub streaming: bool,
    /// Teams' isGreenRoom: not an attendee, connected, the green room on
    /// and the event not live.
    pub green_room: bool,
    /// Teams' stagingRoomEventPhase: "prelive", "active", "ended" or "".
    pub event_phase: String,
    /// The meeting's Q&A is on (`yammerQNAEnabled`).
    pub qna: bool,
    /// The call is end-to-end encrypted (Teams hides what its presets mark
    /// `isE2EEHidden`).
    pub e2ee: bool,
    /// Teams' isCallParkAvailable: call park allowed by your policy and
    /// Enterprise Voice (a Teams Phone licence), the call not on hold.
    pub can_park: bool,
    /// Teams' voicemail greeting call (Settings ▸ Calls ▸ Record a
    /// greeting, `isVoicemailGreeting`; measured on winpc 2026-11-17): Mic,
    /// Dial pad, More (only Audio settings) and Leave; no Chat, People,
    /// View, Apps, Camera or Share, and it can't be held, transferred or
    /// parked.
    pub voicemail: bool,
    /// Teams' test call to your intelligent call delegation (measured on
    /// winpc 2026-11-21: Mic with its audio options, More and Leave).
    pub attendant_test: bool,
    /// We present a Microsoft Whiteboard (Teams' WhiteboardControlsSection:
    /// Stop sharing on the bar).
    pub whiteboard_sharing: bool,
    /// We present PowerPoint Live (PptControlsSection: Layout, Stop
    /// sharing).
    pub ppt_sharing: bool,
    /// We view someone's PowerPoint Live and may take it over
    /// (PptControlsSection's viewer controls, Take control: any meeting
    /// role but Attendee).
    pub ppt_viewing: bool,
}

impl Facts {
    /// A meeting (scheduled or Meet now), not a chat's group call.
    pub fn is_meeting(&self) -> bool {
        self.scheduled || self.adhoc
    }

    /// A chat's group call (its Meet now or Audio call): neither a meeting
    /// nor a 1:1 call, and not the test call.
    pub fn group_call(&self) -> bool {
        !self.is_meeting() && !self.p2p && !self.pstn && !self.consult && !self.echo && !self.voicemail && !self.attendant_test
    }

    /// Whether Teams shows `control` (bar controls and More's items OST
    /// has).
    pub fn shows(&self, control: &str) -> bool {
        if self.e2ee && e2ee_hidden(control) {
            return false;
        }
        if self.voicemail {
            return matches!(control, "MicrophoneButton" | "DialpadButton" | "CallButton" | "AudioSettingsButton");
        }
        if self.attendant_test {
            return matches!(control, "MicrophoneButton" | "CallButton" | "AudioSettingsButton");
        }
        // A town hall's stream (measured in Teams desktop as an attendee,
        // 2026-11-18): Q&A where the meeting has it, Captions once the
        // event is live (Teams' live stream captions), More (Device
        // settings) and Leave. Chat waits for a comment stream, and Mic and
        // Raise for town hall raise hands, both off in prod.
        if self.streaming {
            return match control {
                "YammerQnaButton" => self.qna,
                "ClosedCaptionsButton" => matches!(self.event_phase.as_str(), "active" | "ended"),
                "MoreButton" | "CallButton" | "DeviceSettingsButton" => true,
                _ => false,
            };
        }
        match control {
            "PopoutContentButton" => self.can_pop_out,
            "ScreensharingControlButton" => self.can_take_control,
            "WhiteboardControlsSection" => self.whiteboard_sharing,
            "PptControlsSection" => self.ppt_sharing || self.ppt_viewing,
            "ResumeButton" => self.p2p && self.on_hold && !self.voicemail,
            "CallTransferButtonV2" | "CallConsultativeTransferButtonV2" => self.p2p && !self.voicemail,
            "ChatButton" => !self.pstn && !self.echo && !self.voicemail,
            "RosterButton" => !self.echo && !self.voicemail,
            "ViewModeButton" | "VideoButton" | "MicrophoneButton" | "ShareButton"
            | "CallButton" | "DialpadButton" => true,
            // Not in 1:1 calls (the component renders nothing for P2P).
            // The new controls raise hands from React's menu
            // (showRaiseHandInReactionMenu).
            "RaiseHandsButton" => !self.p2p && !(self.centered && self.shows("ReactionButton")),
            "ReactionButton" => !self.p2p && self.reactions,
            // Not for town halls (Teams' isTownhall hides Controls).
            "OrganizerControlButton" => self.organizer && !self.town_hall,
            // Copilot: meetings and group calls (not 1:1 calls), licensed.
            "MeetingCollabButton" => self.copilot && !self.p2p,
            // Private meetings and scheduled channel meetings: Teams'
            // `(!isAdhocMeeting || enableMeetingNotesInMeetNowCall &&
            // !isChannelMeeting) && (isPrivateMeeting || channel notes)`, so
            // not an ad hoc channel meeting (OST's Meet now) or a group call.
            "MeetingDetailsButton" => self.scheduled && !self.breakout_room,
            "StartBreakoutRoomButton" => self.is_meeting() && self.organizer && !self.town_hall,
            "ReturnToBreakoutRoomButton" => self.room_to_join,
            "BreakoutRoomReturnToMainButton" => self.can_return_to_main,
            // The test call's classic bar has no Apps either (measured
            // 2026-11-18: Raise, React, View, Controls, Copilot, More).
            "MeetingAppsAddButton" => !self.pstn && !self.echo,
            "HoldButton" => self.p2p && !self.on_hold && !self.voicemail,
            "MergeCallsButton" => self.consult,
            "CallParkButton" => self.p2p && self.can_park && !self.on_hold && !self.voicemail,
            // In More (live: the AV framework replaces Devices with these).
            "AudioSettingsButton" | "CameraEffectsButton" => true,
            // Meetings (Teams' isMeeting), not a chat's group call.
            "MeetingInfoButton" => self.is_meeting(),
            // Record and transcribe ▸ (the meeting's call recorder).
            // Show or hide the Transcript pane (the call window adds it
            // once a transcript has run, as Teams' hasBeenStarted).
            // Teams' rules don't look at the kind of call (measured
            // 2026-11-18: a group chat's Meet now and Audio call show
            // them), so meetings and group calls; not a 1:1 call.
            "RecordingMenuControl" | "RecordingButton" | "TranscriptButton" | "TranscriptPanelButton" => {
                self.is_meeting() || self.group_call()
            }
            // More ▸ Timer (the meeting's shared timer; the call window
            // hides it where Teams' timer can't be seen).
            // Group calls too (supportStructuredMeetingsTimerInGroupCalls:
            // Teams showed Timer in a group chat's Meet now).
            "MeetingFacilitatorTimerButton" => self.is_meeting() || self.group_call(),
            // Language and speech ▸ Show live captions (the meeting's
            // recorder provides them).
            "LanguageSpeechMenuControl" | "ClosedCaptionsButton" => self.is_meeting() || self.group_call(),
            // Language and speech ▸ Turn on RTT for this call (real-time
            // text on the meeting's data channel).
            "RealTimeTextButton" => self.is_meeting() || self.group_call(),
            // More ▸ Help (Teams' Help app on its meetings page).
            "MeetingHelpButton" => self.is_meeting() || self.group_call(),
            // More ▸ Report a concern (a security report about the meeting).
            "ReportMeetingButton" => self.is_meeting() && !self.town_hall && !self.webinar,
            // Settings ▸ Call health (every call: the media path counts
            // its streams in any call).
            "CallHealth" => true,
            // Settings ▸ Accessibility settings (the in-meeting pane).
            "AccessibilitySettingsButton" | "MuteNotificationsButton" | "ChatBubblesButton" => self.is_meeting() || self.group_call(),
            // The new controls keep Video effects and Audio settings in
            // Settings ▸, so it shows in every call.
            "SettingsMenuControl" => self.is_meeting() || self.group_call() || self.centered,
            // The new controls' More: Join info ▸ (Meeting info, Call
            // health) and Settings ▸ Hide me / Optimize for room (the old
            // controls keep those two in View ▸ More options).
            "JoinInfoMenuControl" => true,
            // More ▸ Call me (the old controls' flat callingOverflow;
            // Join info ▸ Call me with the new ones).
            "PstnButton" => self.call_me && !self.p2p,
            // More ▸ Facilitator ▸ Turn on / off Facilitator, Enable voice.
            "FacilitatorButton" => self.facilitator && self.scheduled && !self.breakout_room && !self.town_hall && !self.webinar,
            // The green room's Start meeting (presenters, before the event
            // is live) and End event / End meeting (once it is).
            "StagingRoomStartMeetingButton" => self.event_phase == "prelive" && !self.attendee && self.green_room,
            "StagingRoomEndMeetingButton" => self.event_phase == "active" && !self.attendee,
            // Q&A (Viva Engage's meeting Q&A) where the meeting has it on.
            "YammerQnaButton" => self.qna,
            "ToggleHideMyselfButton" | "ByodMeetingRoomModeButton" => self.centered && !self.p2p,
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
    /// The new controls: each customizable group's controls in order (for
    /// Move before / Move after and Unpin).
    pub movable: Vec<Vec<String>>,
}

/// Lay the bar out for `facts` in `available` px of middle slot.
pub fn arrange(facts: &Facts, widths: &dyn Fn(&str) -> f64, divider: f64, available: f64) -> Arranged {
    let layout = Layout::build_with(
        layout_for(facts.p2p, facts.pstn, facts.consult, facts.streaming),
        facts.centered,
        &facts.customization,
        &|n| facts.shows(n),
    );
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
    let movable = layout
        .middle
        .iter()
        .filter(|g| g.customizable)
        .map(|g| g.controls.iter().map(|c| c.name.clone()).collect())
        .collect();
    Arranged {
        bar,
        end: layout.end.iter().map(|c| c.name.clone()).collect(),
        overflowed,
        more: layout.more,
        on_hold,
        movable,
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

    /// Teams' voicemail greeting call: the dial pad stays (the voicemail
    /// is driven by keys), Chat, People, hold, transfer and park don't.
    #[test]
    fn the_attendant_test_call_keeps_mic_more_and_leave() {
        let facts = Facts { p2p: true, attendant_test: true, can_park: true, ..Default::default() };
        for c in ["MicrophoneButton", "CallButton", "AudioSettingsButton"] {
            assert!(facts.shows(c), "{c}");
        }
        for c in ["VideoButton", "ShareButton", "ChatButton", "RosterButton", "DialpadButton", "HoldButton", "CallParkButton", "CallTransferButtonV2"] {
            assert!(!facts.shows(c), "{c}");
        }
    }

    #[test]
    fn a_voicemail_greeting_call_keeps_only_the_dial_pad() {
        let facts = Facts { p2p: true, voicemail: true, can_park: true, ..Default::default() };
        let a = arrange(&facts, &|_| 48.0, 17.0, 5000.0);
        let all: Vec<&str> = a
            .bar
            .iter()
            .map(String::as_str)
            .chain(a.more.iter().flat_map(|s| s.items.iter().map(|i| i.name.as_str())))
            .collect();
        assert!(all.contains(&"DialpadButton") && all.contains(&"MicrophoneButton") && all.contains(&"AudioSettingsButton"));
        assert_eq!(a.end, ["CallButton"]);
        for gone in ["ChatButton", "RosterButton", "HoldButton", "CallTransferButtonV2", "CallParkButton", "VideoButton", "ShareButton", "ViewModeButton", "MeetingAppsAddButton", "CameraEffectsButton"] {
            assert!(!all.contains(&gone), "{gone} shown");
        }
        let plain = arrange(&Facts { p2p: true, ..Default::default() }, &|_| 48.0, 17.0, 5000.0);
        assert!(plain.bar.iter().any(|n| n == "ChatButton"));
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
    fn join_room_leads_the_bar() {
        // Teams desktop, a participant whose room opened (2026-11-11):
        // "Join room" before Chat.
        let facts = Facts { scheduled: true, room_to_join: true, reactions: true, ..Default::default() };
        let a = arrange(&facts, &|_| 48.0, 17.0, 2000.0);
        assert_eq!(a.bar.first().map(String::as_str), Some("ReturnToBreakoutRoomButton"));
        assert!(!arrange(&Facts { scheduled: true, ..Default::default() }, &|_| 48.0, 17.0, 2000.0)
            .bar
            .iter()
            .any(|n| n == "ReturnToBreakoutRoomButton" || n == "BreakoutRoomReturnToMainButton"));
        // In a room (Teams desktop, 2026-11-11): no Notes.
        let room = Facts { scheduled: true, breakout_room: true, reactions: true, ..Default::default() };
        assert!(!arrange(&room, &|_| 48.0, 17.0, 2000.0).bar.iter().any(|n| n == "MeetingDetailsButton"));
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

    /// Teams' Meet now is a meeting (measured on winpc 2026-11-16 with New
    /// meeting controls on and off: the same controls as a scheduled
    /// meeting); an ad hoc channel meeting has no Notes; a group call
    /// none of the meeting's own controls.
    #[test]
    fn meet_now_is_a_meeting_and_group_calls_are_not() {
        let w = |_: &str| 56.0;
        let grid = |a: &Arranged| a.more.iter().filter(|s| s.grid).flat_map(|s| s.items.iter().map(|i| i.name.clone())).collect::<Vec<_>>();
        for centered in [true, false] {
            let meet_now = Facts { adhoc: true, organizer: true, reactions: true, centered, ..Default::default() };
            let a = arrange(&meet_now, &w, 17.0, 5000.0);
            let all: Vec<String> = a.bar.iter().cloned().chain(grid(&a)).chain(a.more.iter().flat_map(|s| s.items.iter().map(|i| i.name.clone()))).collect();
            for want in ["StartBreakoutRoomButton", "OrganizerControlButton", "MeetingHelpButton"] {
                assert!(all.iter().any(|n| n == want), "Meet now ({centered}) shows {want}: {all:?}");
            }
            assert!(!all.iter().any(|n| n == "MeetingDetailsButton"), "an ad hoc channel meeting has no Notes");
            let group = Facts { reactions: true, centered, ..Default::default() };
            let g = arrange(&group, &w, 17.0, 5000.0);
            let gall: Vec<String> = g.bar.iter().cloned().chain(g.more.iter().flat_map(|s| s.items.iter().map(|i| i.name.clone()))).collect();
            for gone in ["MeetingDetailsButton", "StartBreakoutRoomButton", "OrganizerControlButton", "ReportMeetingButton"] {
                assert!(!gall.iter().any(|n| n == gone), "a group call ({centered}) has no {gone}");
            }
        }
    }

    #[test]
    fn a_town_hall_stream_has_the_attendee_bar() {
        // Teams desktop as a town hall attendee (2026-11-18): Waiting with
        // Q&A, More, Leave; live with Q&A, Captions, More, Leave.
        let waiting = Facts { scheduled: true, attendee: true, streaming: true, town_hall: true, qna: true, event_phase: "prelive".into(), ..Default::default() };
        let l = Layout::build(layout_for(false, false, false, true), &|c| waiting.shows(c));
        let bar: Vec<String> = l.middle.iter().flat_map(|g| g.controls.iter().map(|c| c.name.clone())).collect();
        assert_eq!(bar, vec!["YammerQnaButton", "MoreButton"]);
        assert_eq!(l.end.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(), vec!["CallButton"]);
        let live = Facts { event_phase: "active".into(), ..waiting };
        let l = Layout::build(layout_for(false, false, false, true), &|c| live.shows(c));
        let bar: Vec<String> = l.middle.iter().flat_map(|g| g.controls.iter().map(|c| c.name.clone())).collect();
        assert_eq!(bar, vec!["YammerQnaButton", "ClosedCaptionsButton", "MoreButton"]);
    }

    #[test]
    fn a_town_hall_green_room() {
        // The organizer in a town hall's green room (Teams' calculate-
        // VisibilityOverrides): Start meeting before Leave, Q&A; no
        // Controls, Rooms, Report or Facilitator.
        let w = |_: &str| 56.0;
        let green = Facts { scheduled: true, organizer: true, town_hall: true, green_room: true, event_phase: "prelive".into(),
                            qna: true, facilitator: true, ..Default::default() };
        let a = arrange(&green, &w, 17.0, 5000.0);
        assert_eq!(a.end, ["StagingRoomStartMeetingButton", "CallButton"]);
        assert!(a.bar.contains(&"YammerQnaButton".to_string()));
        for gone in ["OrganizerControlButton", "StartBreakoutRoomButton"] {
            assert!(!a.bar.iter().any(|n| n == gone), "{gone}");
        }
        let more: Vec<String> = a.more.iter().flat_map(|s| s.items.iter().map(|i| i.name.clone())).collect();
        assert!(!more.iter().any(|n| n == "ReportMeetingButton" || n == "FacilitatorButton"));
        // Live: End event instead.
        let live = Facts { green_room: false, event_phase: "active".into(), ..green.clone() };
        assert_eq!(arrange(&live, &w, 17.0, 5000.0).end, ["StagingRoomEndMeetingButton", "CallButton"]);
        // Attendees never get either.
        let att = Facts { attendee: true, organizer: false, ..green };
        assert_eq!(arrange(&att, &w, 17.0, 5000.0).end, ["CallButton"]);
        // A webinar keeps breakout rooms.
        let web = Facts { scheduled: true, organizer: true, webinar: true, ..Default::default() };
        assert!(arrange(&web, &w, 17.0, 5000.0).bar.contains(&"StartBreakoutRoomButton".to_string()));
    }

    fn new_controls_meeting() -> Facts {
        Facts { scheduled: true, organizer: true, reactions: true, centered: true, ..Default::default() }
    }

    fn more_names(a: &Arranged) -> Vec<Vec<String>> {
        a.more.iter().map(|s| s.items.iter().map(|i| i.name.clone()).collect()).collect()
    }

    #[test]
    fn new_controls_bar_as_teams_on_winpc() {
        // Teams on winpc with New meeting controls on (2026-11-16): Mic,
        // Camera, Share | React, Chat, People, (Copilot), Controls, More;
        // Leave apart; Raise is in React's menu.
        let a = arrange(&new_controls_meeting(), &|_| 56.0, 17.0, 5000.0);
        assert_eq!(
            a.bar,
            ["MicrophoneButton", "VideoButton", "ShareButton", "|", "ReactionButton", "ChatButton", "RosterButton",
             "OrganizerControlButton", "MoreButton"]
        );
        assert_eq!(a.end, ["CallButton"]);
        // More: the grid, then the list.
        assert!(a.more[0].grid && !a.more[1].grid);
        assert_eq!(
            more_names(&a)[0],
            ["RecordingButton", "TranscriptButton", "MeetingFacilitatorTimerButton", "MeetingDetailsButton",
             "ClosedCaptionsButton", "StartBreakoutRoomButton", "RealTimeTextButton", "MeetingAppsAddButton"]
        );
        assert_eq!(
            more_names(&a)[1],
            ["ViewModeButton", "JoinInfoMenuControl", "SettingsMenuControl", "ReportMeetingButton", "MeetingHelpButton"]
        );
        let settings = &a.more[1].items[2];
        let sec: Vec<Vec<&str>> = settings.sections.iter().map(|s| s.items.iter().map(|i| i.name.as_str()).collect()).collect();
        assert_eq!(
            sec,
            [vec!["AccessibilitySettingsButton"], vec!["ChatBubblesButton", "ToggleHideMyselfButton"],
             vec!["CameraEffectsButton", "AudioSettingsButton", "ByodMeetingRoomModeButton"]]
        );
        let info = &a.more[1].items[1];
        assert_eq!(info.sections[0].items.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(), ["MeetingInfoButton", "CallHealth"]);
        // The current controls are unchanged.
        let old = arrange(&Facts { centered: false, ..new_controls_meeting() }, &|_| 56.0, 17.0, 5000.0);
        assert_eq!(old.bar.first().map(String::as_str), Some("ChatButton"));
        assert!(old.bar.contains(&"RaiseHandsButton".to_string()));
    }

    #[test]
    fn new_controls_overflow_as_teams() {
        // Teams (winpc, widths swept 2026-11-16): Controls leaves first,
        // then (Copilot), People, Chat; React last.
        let w = |n: &str| if n == "MicrophoneButton" || n == "VideoButton" { 74.0 } else { 56.0 };
        let f = new_controls_meeting();
        let full = 74.0 * 2.0 + 56.0 + 17.0 + 5.0 * 56.0;
        assert!(arrange(&f, &w, 17.0, full).overflowed.is_empty());
        assert_eq!(arrange(&f, &w, 17.0, full - 1.0).overflowed, ["OrganizerControlButton"]);
        assert_eq!(arrange(&f, &w, 17.0, full - 3.0 * 56.0).overflowed, ["ChatButton", "RosterButton", "OrganizerControlButton"]);
        let gone = arrange(&f, &w, 17.0, 0.0);
        assert_eq!(gone.bar, ["MicrophoneButton", "VideoButton", "ShareButton", "MoreButton"]);
        assert!(gone.overflowed.contains(&"ReactionButton".to_string()));
    }

    #[test]
    fn new_controls_follow_the_users_arrangement() {
        let mut f = new_controls_meeting();
        f.customization = Customization {
            unpinned: vec!["RosterButton".into()],
            pinned: vec!["MeetingFacilitatorTimerButton".into()],
            order: vec!["ChatButton".into(), "ReactionButton".into()],
        };
        let a = arrange(&f, &|_| 56.0, 17.0, 5000.0);
        assert_eq!(
            a.bar,
            ["MicrophoneButton", "VideoButton", "ShareButton", "|", "ChatButton", "ReactionButton",
             "OrganizerControlButton", "MeetingFacilitatorTimerButton", "MoreButton"]
        );
        let grid = &more_names(&a)[0];
        assert_eq!(grid[0], "RosterButton");
        assert!(!grid.contains(&"MeetingFacilitatorTimerButton".to_string()));
        assert_eq!(a.movable[0], ["ChatButton", "ReactionButton", "OrganizerControlButton", "MeetingFacilitatorTimerButton"]);
        // Apps stays docked in the grid.
        f.customization.pinned = vec!["MeetingAppsAddButton".into()];
        assert!(!arrange(&f, &|_| 56.0, 17.0, 5000.0).bar.contains(&"MeetingAppsAddButton".to_string()));
    }

    #[test]
    fn new_controls_one_to_one() {
        let a = arrange(&Facts { p2p: true, centered: true, ..Default::default() }, &|_| 56.0, 17.0, 5000.0);
        assert_eq!(a.bar[..4], ["MicrophoneButton", "VideoButton", "ShareButton", "|"]);
        assert!(a.bar.contains(&"HoldButton".to_string()) && a.bar.contains(&"DialpadButton".to_string()));
        assert!(!a.bar.contains(&"RaiseHandsButton".to_string()) && !a.bar.contains(&"ReactionButton".to_string()));
        // On hold: Resume is with Leave.
        let held = arrange(&Facts { p2p: true, on_hold: true, centered: true, ..Default::default() }, &|_| 56.0, 17.0, 5000.0);
        assert_eq!(held.end, ["ResumeButton", "CallButton"]);
    }

    #[test]
    fn end_to_end_encrypted_calls_drop_what_teams_hides() {
        for centered in [false, true] {
            let plain = arrange(&Facts { p2p: true, centered, ..Default::default() }, &|_| 56.0, 17.0, 5000.0);
            assert!(plain.bar.contains(&"CallTransferButtonV2".to_string()));
            let e2ee = arrange(&Facts { p2p: true, centered, e2ee: true, ..Default::default() }, &|_| 56.0, 17.0, 5000.0);
            for gone in ["CallTransferButtonV2", "CallConsultativeTransferButtonV2", "MeetingAppsAddButton"] {
                assert!(!e2ee.bar.contains(&gone.to_string()), "{gone} in an E2EE call");
            }
            assert!(e2ee.bar.contains(&"HoldButton".to_string()) && e2ee.bar.contains(&"DialpadButton".to_string()));
        }
        for n in ["RecordingButton", "TranscriptButton", "CallParkButton", "MergeCallsButton", "RecordingIndicator"] {
            assert!(e2ee_hidden(n), "{n}");
        }
        assert!(!e2ee_hidden("HoldButton") && !e2ee_hidden("E2EEncryptionIndicator"));
        // Park: Teams' isCallParkAvailable (policy and Enterprise Voice),
        // not on hold, not end-to-end encrypted.
        assert!(!Facts { p2p: true, ..Default::default() }.shows("CallParkButton"));
        assert!(Facts { p2p: true, can_park: true, ..Default::default() }.shows("CallParkButton"));
        assert!(!Facts { p2p: true, can_park: true, on_hold: true, ..Default::default() }.shows("CallParkButton"));
        assert!(!Facts { p2p: true, can_park: true, e2ee: true, ..Default::default() }.shows("CallParkButton"));
    }

    #[test]
    fn picks_teams_layouts() {
        assert_eq!(layout_name(false, false, false), LayoutName::Default);
        assert_eq!(layout_name(true, false, false), LayoutName::OneToOneOrGroupCall);
        assert_eq!(layout_name(true, true, false), LayoutName::OneToOnePstn);
        assert_eq!(layout_name(true, false, true), LayoutName::ConsultAndAdd);
    }

    #[test]
    fn call_me_and_facilitator_in_more_as_teams() {
        // Teams on the web (2026-11-16, a meeting with Audio Conferencing,
        // ost-test1 licensed for Copilot): More reads … Meeting info,
        // Facilitator ▸, Timer … Settings ▸ | Call me, Report a concern,
        // Help.
        let facts = Facts { scheduled: true, organizer: true, reactions: true, call_me: true, facilitator: true, ..Default::default() };
        let a = arrange(&facts, &|_| 56.0, 17.0, 5000.0);
        let flat: Vec<String> = more_names(&a).concat();
        let at = |n: &str| flat.iter().position(|x| x == n).unwrap_or_else(|| panic!("{n} missing: {flat:?}"));
        assert!(at("MeetingInfoButton") < at("FacilitatorButton") && at("FacilitatorButton") < at("MeetingFacilitatorTimerButton"));
        assert!(at("SettingsMenuControl") < at("PstnButton") && at("PstnButton") < at("ReportMeetingButton"));
        // Call me is a section of one (callingOverflow) right before Report
        // a concern and Help: the menu merges it into theirs (no divider).
        let secs = more_names(&a);
        assert!(secs.iter().any(|s| s == &["PstnButton".to_string()]), "Call me alone: {secs:?}");
        assert_eq!(flat[at("PstnButton")..], ["PstnButton", "ReportMeetingButton", "MeetingHelpButton"]);
        // Without dial-in (or a licence) neither shows.
        let plain = arrange(&Facts { scheduled: true, ..Default::default() }, &|_| 56.0, 17.0, 5000.0);
        let flat: Vec<String> = more_names(&plain).concat();
        assert!(!flat.contains(&"PstnButton".to_string()) && !flat.contains(&"FacilitatorButton".to_string()));
        // The new controls: Join info ▸ Meeting info, Call me, Call health.
        let n = arrange(&Facts { call_me: true, ..new_controls_meeting() }, &|_| 56.0, 17.0, 5000.0);
        let info = n.more.iter().flat_map(|s| s.items.iter()).find(|i| i.name == "JoinInfoMenuControl").unwrap();
        let items: Vec<&str> = info.sections.iter().flat_map(|s| s.items.iter().map(|i| i.name.as_str())).collect();
        assert_eq!(items, ["MeetingInfoButton", "PstnButton", "CallHealth"]);
    }
}
