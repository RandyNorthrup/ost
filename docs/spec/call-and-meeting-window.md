# Call and meeting window — Teams desktop behaviour (spec)

Source: the Teams client itself (build 26276.513, Windows desktop). Its modules
were read from the published client bundles; module ids are given so this can be
re-checked against later builds.

The toolbar layout and all flag values were read from the running Windows app on
winpc, signed in as ost-test1, through the WebView2 debugger. These were
read-only reads of the ECS `calling` settings from React context, made while no
call was active. "(live X)" means the value seen there.

Anything not confirmed in code is marked **unverified**.

Main modules:

| module | what |
|---|---|
| 414673 | unified bar (toolbar), all bar buttons, More/View/Leave menus, visibility rules |
| 615280 | pre-join screen, call window titles, compact-view title bar |
| 620894 | pre-join per-state presets |
| 221949 / 320296 / 978369 | People pane / rows and menu / sort |
| 522284, 512425 | lobby |
| 710637 | raise-hand state |
| 477421, 2998, 972234, 296162 | stage segments, areas, grid, gallery size |
| 325285 | share tray |
| 827897 | sharing control bar |
| 459205, 657347 | compact view |
| 691083 | call quality survey |
| 504800 | key map |
| 448700 (in `r_data-client-calling-*.js`), 527114 | calling GraphQL resolvers and calling-service proxy |

**Where the service layer ends.** Calling mutations are *not* resolved in the
data-layer web worker. Each client-side resolver is a thin
`getCallingService("<name>").<name>(args)` call (module 448700) into the
in-process calling stack, whose code is not shipped as JS. So for calling
actions the contract a clone has to honour is the mutation name, its arguments,
and the calling-stack method it reaches; both are listed below.

## 1. Meeting/call toolbar ("unified bar", module 414673)

Component tree: `UnifiedBarWrapper` (`Cq`) → `hq` (call query) → `uq` → `rq`/`oq`
(configuration loader) → `HI` (settings provider) → `MQ` (visibility) → slot
renderers. The bar is only mounted when the call state is Connected, Staging,
LocalHold or RemoteHold, or (P2P only) Connecting/EarlyMedia, or InLobby when the
lobby variant is enabled (`pq`, `hq`). In a moderated meeting's staging phase it is
not shown.

### 1.1 Where the item list comes from: server config, not code
The items, their order, their slot and their menu nesting are **not hard-coded**.
They come from three ECS settings in the `calling` category (live values read from
the Windows client, saved in the research dir as presets.json / overrides.json):

- `ubarLayoutPresets`: 10 presets. Each is a tree of groups → items → nested
  groups. A preset is picked by `layoutSetup` and `filter` (`GQ`): exact match on
  both scores 3, a filter match with no setup scores 2, a preset with neither scores 1.
  The main bar uses filter none. Others: `meeting-room`, `presenter-toolbar`,
  `callsmonitor`, `lightweight-callsmonitor`, `speaker-only-callsmonitor`.
- `ubarLayoutSetup`: live value **`Inline`**. That selects preset 0 (no preset has
  setup "Inline"). The other setup, `InlineCentered`, is the alternative
  "centred" design (preset 1), which Settings ▸ General ▸ Meeting ▸ New
  meeting controls switches on (new-meeting-controls.md). The template
  names are Anchor, Inline, InlineCentered and Stacked (`GI`).
- `ubarLayoutOverrides`: 30 per-call-type entries (`configName`). Each lists the
  `available` controls (a whitelist), plus `overrides` that move a control to
  another slot or change its props, and `settings` (groupingStrategy,
  layoutTemplate, suppressTooltips...). The entry is looked up by name, and
  falls back to `default`.
- `ubarActiveExperiments` / `ubarExperimentDefinitions` can patch the overrides.
  Live value: none active.

**Layout name** (`eq`, first match wins): presenter toolbar active →
`presenterToolbar`/`presenterToolbarMinimized`; personal attendant test call /
personal attendant; follow mode; broadcast (Producer → `broadcastProducer`);
voicemail greeting or emergency → `greetingEmergency`; content-only stage →
`contentOnly`; agent monitor/whisper; conversationType `CONSULT_AND_ADD` →
`consultAndAdd`; VTC call; **1:1 PSTN → `oneToOnePstn`**; Skype consumer;
**callType P2P → `oneToOneOrGroupCall`**; streaming client (town hall attendee) →
`streamingClient`; immersive event; local Copilot session; **otherwise `default`**.
So a Teams **group call** (callType Conference, `extendedCallType.isGroupCall`)
uses the **`default`** layout, the same as a meeting. The difference between them
comes only from the visibility rules (§1.4). Calls-monitor (mini window) layouts
are chosen separately (`KQ`, §8).

**Building the slots** (`xQ.createLayoutMap`): the preset tree is walked in
order. Items not in `available` are skipped. MoreButton is always added. Nested
items keep their nearest available ancestor as the menu parent. If no ancestor is
available, the item is promoted to the root's slot. Every bar item also gets a
**placeholder** in the overflow (More) menu, and the placeholders are
*prepended* to the More menu. Every item that lives in More gets a hidden
placeholder in the bar (used for hoisting). An override slot moves a nested item
onto the bar as its own group, inserted before the root group (`placeBefore`).
Defaults per item: isCritical false, overflowBehaviour `AsFirst`, template
`default`. `isCritical` only means "mounted in the first render phase", not
"never overflows".

### 1.2 Slot arrangement (template), sizes
`rQ`:
- **Inline** (live): `[indicators][horizontalMiddleEnd]` | `[horizontalEnd]`.
  The middle slot is right-justified (`justify-content:end`). A slot divider
  (`showSlotDividers` = `enableUbarSlotGrouping`, live true) separates the main
  group from the end group, which holds Leave.
- InlineCentered: one group `[indicators][horizontalMiddleEnd centred][horizontalEnd]`.
- Anchor: `[indicators][hStart][hMiddleStart centred][hMiddleEnd]` | `[hEnd]`. Stacked: `[indicators][hStart][hEnd]`.

The root font size is 10px, so 1rem = 10px (read from the live client).
- Bar button, `default` template: height 48px, min-width 48px, max-width 72px,
  margin 6px vertical / 4px horizontal (spacingVerticalSNudge /
  spacingHorizontalXS). Icon 25px. Label below the icon, 11px, regular weight.
  When the control's panel is open, a status bar shows under the button: 2px
  high, 66% wide, 5px below.
- `truncated` template: 32px high, min-width 32px, max-width 72px, icon only (the
  label becomes the aria label). `minimized`: 32×32px, icon 20px.
- Labels show when `enableIconLabelsInUbar` (live true) and the layout doesn't
  suppress them. Tooltips are suppressed on meeting-room consoles and in the
  presenter toolbar. A tooltip with a shortcut reads `{{tooltip}} ({{keyboardShortcut}})`
  (`calling_ubar_control_tooltip_with_shortcut`).
- `role="toolbar"` when a slot holds more than one control, else `role="group"`.
  The wrapper has `data-tid="ubar-toolbar-wrapper"`, `data-layout=<template>`.

**Dividers between groups** (`cr`, `_$`). Each preset group becomes a run of
items. The divider rule follows the group's `groupingStrategy`, else the
layout's. The default is `MergeWithNext`; the `oneToOneOrGroupCall` layout uses
`MergeWithPrevious`.
- AlwaysKeep: a divider between every pair of non-empty groups.
- MergeWithNext: a group with exactly one visible item merges into the next
  group, with no divider.
- MergeWithPrevious: a divider only before a group with more than one item.

### 1.3 Order in the bar (live `Inline` preset 0)
Left to right. Items whose visibility rule (§1.4) fails are removed.

| # | group | control | label (bar) | tooltip/title | string keys |
|---|---|---|---|---|---|
| — | indicators | BroadcastState, E2EEncryption, Recording, VirtualEventsLive, Copilot, AiInterpretation, **CallDuration** (timer), ImmersiveEventLive, BroadcastAttendeeCount, VdiLocalStackStatus, IndicatorOverflow | — | "More status indicators" | `ubar_calling_indicator_overflow_button_tooltip` |
| 1 | contextual | ReturnToBreakoutRoom, BreakoutRoomReturnToMain, CallTransferDuringConsult, CallTransferButtonV2, CallConsultativeTransferButtonV2, **Resume** (on hold), ScreensharingControl (Take control), Whiteboard/PPT control sections, MixedRealityToolbar, AnnotationViewer, StopSpotlight, PopoutContent, TogetherMode×3 | e.g. "Resume", "Take control", "Transfer", "Consult" | | `calling_resume_call`, `calling_screensharing_viewer_action_request_control_label`, `calling_transfer_call`, `calling_consultThenTransfer_button_label` |
| 2 | secondary | **ChatButton** | Chat | Chat | `calling_chat_icon_label` |
| 3 | | YammerQnaButton | Q&A | | `yammer_qna_icon_label` |
| 4 | | **RosterButton** | People | | `calling_participants_icon_label` |
| 5 | | **RaiseHandsButton** | Raise | "Raise your hand" / "Lower your hand" | `calling_raise_hand_icon_label` |
| 6 | | **ReactionButton** | React | "Send a reaction" | `calling_react_menu_icon_label`, `calling_meeting_reactions` |
| 7 | | **ViewModeButton** | View | "Change your view" | `calling_view_mode_icon_label`, `calling_change_view_mode_button_tooltip` |
| 8 | | OrganizerControlButton | Controls | Controls | `calling_organizer_control_button_icon_label` |
| 9 | | BroadcastQnaButton | Q&A | | `broadcast_qna_icon_label` |
| 10 | | **MeetingDetailsButton** | Notes | "Open notes"/"Close notes"; opens the meeting's notes (a Loop page) in the side panel, app-host.md "Meeting Notes" | `calling_meeting_details_icon_label` |
| 11 | | **StartBreakoutRoomButton** | Rooms | "Create breakout rooms" | `calling_breakout_room_icon_label` |
| 12 | | MeetingCollab / OneCopilot / BizChatCopilot | (Copilot; label not traced) | | |
| 13 | | CallContextButton | | | |
| 14 | | PlatformTabSection (pinned meeting apps, one button per app tab) | app name | | |
| 15 | | **MeetingAppsAddButton** | Apps | "Find apps and more" / "Close apps" | `calling_apps_add_menu_icon_label`, `calling_ubar_meeting_apps_open_tooltip` |
| 16 | | **MoreButton** (Docked) | More | "More actions" | `calling_more_menu_icon_label`, `calling_more_actions` |
| 17 | primary | **VideoButton** (Docked) | Camera | Camera | `calling_camera_icon_label` |
| 18 | | **MicrophoneButton** (Docked) | Mic | "Mute mic"/"Unmute mic" | `calling_microphone_icon_label`, `calling_ubar_mic_button_mute_tooltip` |
| 19 | | VolumeControlButton (Docked) | | | |
| 20 | | **ShareButton** (Docked) | Share | "Share content" / "Stop sharing" | `calling_share_icon_label`, `calling_share_button_open_sharetray_label`, `calling_share_button_stop_sharing_label` |
| 21 | | PauseScreenShareButton (Docked, while sharing) | Pause / Resume | "Pause screen share" / "Resume screen share" | `calling_pause_screenshare`, … |
| 22 | callControls (horizontalEnd) | MonitoredAgentStateChange, FollowChange ("Join"), StagingRoomStart/EndMeeting ("End meeting"), **CallButton** (Leave) | Leave | Leave | `call_leave`, `calling_ubar_hangup_button_tooltip`, `calling_end_call` |

The `InlineCentered` preset (not live) differs:
- Order: Mic, Camera, Share, PauseShare, Volume, then React, Raise, Chat, People,
  Copilot, Controls, Q&A, CallContext, then the contextual group (Dial pad, Hold,
  Upgrade, Transfer…), then More.
- Leave is in the same centred group.
- More becomes a grid section ("collaborationCommunication") with
  `hoistingBehaviour`, which promotes a More item into the bar while it is
  active, notified or clicked.

### 1.4 Visibility per call type and role (`MQ.calculateVisibilityOverrides`)
A control is shown only if it is in the layout's `available` list **and** its
rule here is true. Rules that matter for the main bar (flags in brackets; live
value given when known):

| control | shown when |
|---|---|
| Chat | `showUbarChatButton` (true). Not in a 1:1 PSTN call (unless `enableSmsChatForEnterpriseVoice`), not in a voicemail-greeting call. Streaming client only with `enableStreamChatFeature`. Not in appliance mode |
| People | `enableRosterButtonInUbar` (true), not an immersive event, not a voicemail greeting |
| Raise | Host `isRaiseHandsEnabled` (true), not appliance mode, not an immersive event; streaming client only for a town hall with `enableRaiseHandForStreaming`. The component (`414673` ~l.21026) also renders nothing when **callType == P2P**: Raise is in the 1:1 `available` list but never shows in a 1:1 call. With `hideRaiseHandIfDisabled` (true) the button stays hidden until raising is allowed; after it has once appeared, a later revoke makes it *disabled*, not hidden. Disabled reasons: "Disabled by the organizer", "Only available when the event is live", "Disabled in Preview" |
| React | not an immersive event (map). The component (104370) additionally needs `enableMeetingReactions`, **not P2P**, not broadcast, not an overflow streaming call, and meeting option `allowMeetingReactions` (or policy). Also absent from the 1:1 and 1:1 PSTN `available` lists. Disabled when not connected, during transfer, or when a town hall attendee is behind the live edge ("Only available when the event is live") |
| View | `enableViewModeButton`, not the meeting-room layout dialog, not a production meeting |
| Controls (organizer) | meetingRole == Organizer && `enableOrganizerControlButton` (true) && not a town hall. Or the security-threats variant: private/channel meeting && `enableMeetingControlsPanel` && `enableThreatDetection` |
| Meeting options (in More › Settings) | legacy case: not a 1:1, `enableMeetingOptionsButtonInUbar` (true), private/channel meeting (or broadcast with RTMP), Organizer, **and the Controls button is not shown** |
| Notes | `enableMeetingDetailsButtonInUbar`. Not a town hall attendee. Ad hoc meetings only when `enableMeetingNotesInMeetNowCall` and not a channel meeting. Private meeting (meetingType Recurring, MeetNow or Scheduled, with `isPrivateMeeting`) or channel meeting with `enableChannelMeetingNotes`. So **never in plain group calls or 1:1 calls** |
| Rooms | `enableBreakoutRooms` && not a town hall; the component also requires a scheduled meeting (`isMeeting`). Organizer or breakout manager: button shown (hidden on web unless `enableBreakoutRoomsOrganizerExperienceOnWeb`, inside a breakout room unless self-select, or when the meeting capability `isBreakoutRoomsAllowed` is false). Participant: hidden. A demoted manager sees it disabled. Self-assigning participant: shown with `enableSelfSelectBreakoutRoomsCapability`. Never for a screen-share call, a private channel without support, or a cancelled meeting (module 414673 `B8`/`_8`) |
| Apps | `enableMeetingAppAddButtonInUbar`. Not a town hall (unless `enableTownhallAppsInstallationInMeeting`). Not a 1:1 PSTN call (unless `enableAgentsInPstnCalls`) |
| App tabs (PlatformTabSection) | `enablePlatformTabSection`. Town hall attendees need `enableTownhallAppsForAttendees`; town hall attendee endpoints that aren't attendees: no |
| Camera | not appliance mode, not AV-over-IP blocked, not disabled in VDI, not an immersive event |
| Mic | not AV-over-IP blocked, not disabled in VDI. Emergency call: only for the non-caller (with self capabilities). Streaming client: town hall raise-hands only. Immersive event: `enableImmersiveEventsMicButton` |
| Share | not appliance mode; immersive event only with `enableImmersiveEventsShareButton` |
| Pause share | `enableScreenSharePauseResume` && Share available |
| Hold | `isOneToOneCall` (P2P) only |
| Dial pad | always, unless `disableDtmfForNonP2pAndEmergencyCalls` (live false), in which case P2P, voicemail greeting or emergency only |
| Transfer (V2 buttons on the bar) | `enableUbarTransferButtonOnL1` (true) → `CallTransferButtonV2`/`CallConsultativeTransferButtonV2` shown, V1 menu items hidden. Not appliance mode (Transfer V2 also allowed in survivability mode) |
| Upgrade ("Upgrade to video call") | `enableUpgradeCall` (false) |
| Merge calls | not appliance mode |
| Park call | not appliance mode, not an ACS interop call |

**Disabled, not hidden** (`propagateCallConfigChanges`). A visible control gets
`forceDisabledReason`, in this order of precedence:
- OnHold: when the call is on hold and the item lacks `isOnHold`. Enabled on
  hold: Chat, More, Mic, Leave, Resume, Breakout…
- Disconnected
- InLobby: unless `isLobbyEnabled`; only Leave has it.
- StagingRoom: in a green room, unless `isStagingRoom`.
- GreenRoom: items with `isGreenRoomDisabled`, i.e. React and most View options.
- ImmersiveView

Items flagged `isE2EEHidden` are **removed** when end-to-end encryption is on:
Notes, Rooms, Apps, Copilot, recording, transcript, Large gallery, Together…

**1:1 Teams call (`oneToOneOrGroupCall`).** `available` = View, Controls, the
View-menu items, indicators, screen-sharing controls, Resume, People, Chat,
Raise, Music mode, More, Camera, Mic, Share, Leave, Settings menu, device/audio
settings, Call health, Dial pad, Hold, Transfer, Merge, Park, SLA lock, Video
effects, Join info, Language & speech, captions, interpretation, coach,
recording/transcript, Other videos, Copilot, Apps, app tabs, Whiteboard,
Streaming, RTT, CallContext, Hide controls, Insights, Annotation.
**Missing: React, Notes, Rooms, Organizer Controls' meeting options, Report.**
Overrides put **HoldButton, CallTransferMenuControl and DialpadButton on the
bar** (horizontalMiddleEnd, isCritical). They form their own group
("callingOverflow"), inserted before the Chat/People group. With
`enableUbarTransferButtonOnL1` the Transfer menu has no visible children, so it
is hidden; the V2 Transfer/Consult buttons show in the contextual group instead.
Resulting 1:1 bar:

`[timer…] [Transfer][Consult] [Dial pad][Hold] | [Chat][People][View][Apps][More] [Camera][Mic][Share] | [Leave]`
(1:1 has no Raise, no React, no Notes, no Rooms.)

**1:1 PSTN (`oneToOnePstn`).** No Camera, Share, View, React or video options.
Hold, Transfer menu, Dial pad, Transfer V2, Consult V2 and Upgrade are all
critical bar items. Grouping is AlwaysKeep.

**Consult call (`consultAndAdd`).** Merge calls, Dial pad and Hold on the bar,
plus Chat, Camera, Mic, Share, More and Leave.

**Group call vs meeting.** Both use `default`. A group call loses:
- Notes (needs a private or channel meeting)
- Rooms (needs a scheduled meeting)
- Report a concern (not a group call)
- Shared content bin
- the organizer's Meeting options (needs a private or channel meeting)

Controls needs meetingRole Organizer, which group calls don't have.

### 1.5 Overflow as the window narrows (no fixed breakpoints)
The middle slot (`horizontalMiddleEnd`) uses Fluent v9 `Overflow`
(`overflowConfiguration {type:"Dynamic", overflowParent: MoreButton}`, `c$`).
Items that don't fit move into **More**, at the top of its menu, in bar order.
Overflow is measured from widths; there is **no px breakpoint table**.
Priorities (`kc`): `AsFirst` = 0, `AsLast` = 500, `Docked` = pinned (never
overflows). Fluent hides the lowest priority first. On ties it hides the **last
item in DOM order** first (overflowDirection "end").

For the live preset, items leave the bar in this order:
1. The secondary group's AsFirst items, right to left: Apps, app tabs, CallContext, Copilot, Rooms, Notes, broadcast Q&A, Controls, View, People, Yammer Q&A, Chat.
2. Then the bar groups further left (in a 1:1 call: Hold, Dial pad; then the contextual group: Transfer, Consult, Resume, Take control…).
3. Last of all **React**, then **Raise** (AsLast).

More, Camera, Mic, Volume, Share, Pause share and Leave never overflow.

**Measured on winpc (2026-11-08).** Fluent's Overflow keeps **10 px** free at the end of the container: a control stays only while the visible content is at most the slot's width − 10 (Chat came back at a 455.86 px slot for 445 px of content, not at 453.86). The middle slot starts 4 px after the indicator toolbar and ends 4 px before the end slot; button wrappers are 56 (48 + 4 either side), split buttons 74, dividers 17. Overflowed controls are More's first rows, in bar order, followed by a divider; their menu text: "Chat", "People" / "Hide people", "Raise hand" / "Lower hand", "Send a reaction", "View ▸", "Controls ▸", "Open notes", "Breakout rooms", "Get more apps and agents".

**Tooltips** (Fluent Tooltip): 10 px below the 48 px button, the left edge on the button's, or the right edge on the button's when it would leave the window; 12/16 text, padding 4 / 11 / 6, radius 4, a 12 px arrow at the button's centre, shadows 2 and 8; "{tooltip} ({shortcut})". Texts: Chat "Show conversation" / "Hide conversation"; People "{n} participants. Show participants" / "… Hide participants"; Raise "Raise your hand" / "Lower your hand" (Ctrl+Shift+K); React "Send a reaction"; View "Change your view"; Controls none; Notes "Open notes"; Rooms "Create breakout rooms"; Apps "Find apps and more" / "Close apps"; More "More actions"; Camera "Turn camera on" / "Turn camera off" (Ctrl+Shift+O); its chevron "Open video options"; Mic "Mute mic" / "Unmute mic", or "Turn audio on" without audio (Ctrl+Shift+M); its chevron "Open audio options"; Share "Share content" (Ctrl+Shift+E); Leave "Leave" (Ctrl+Shift+H); Leave's chevron none; 1:1: "Hold", "Dial pad", "Transfer", "Consult then transfer", "Resume", "Pop out".

Group dividers are overflow items with priority AsFirst, and are hidden when
their group empties. Indicators overflow into "More status indicators" after 4
items, but only with `enableIndicatorOverflowInUbar` (live false). Mutations of
the toolbar re-run overflow, debounced 50ms with a max wait of 1000ms (`l$`).

**Layout-shift click protection** (`WH`, `ubarLayoutShiftProtection` live
`{enabled:true, onClickSuppressTimeMs:2000}`). While the pointer is over the bar:
- A shift marks the bar for 2000ms. A shift is a resize, a child change, or a
  `data-overflowing` change.
- A click in that window is swallowed (`data-layout-shifting`), so the user
  doesn't click a control that just moved under the cursor.

### 1.6 Customization / pinning
Customization needs `enableUbarCustomization`, which is **false live**, so
current users can't customize. When enabled:
- Right-clicking a control opens a context menu:
  - "Move before {control}" / "Move after {control}"
  - "Pin" (the item is in More) or "Unpin"
  - divider, then "Reset meeting controls"
  Keys: `calling_ubar_control_contextual_menu_pin_action_name`, `…unpin…`,
  `…reset_layout_action_name`. The move items only appear when the group's
  `layoutCustomizationBehaviour` is All or ArrangeOnly.
- Drag and drop (dnd-kit) between the bar and More. Announcements: "Pin
  {{controlLabel}}", "Pin {{controlLabel}} to {{slotLabel}}", "Unpin
  {{controlLabel}}", "{{controlLabel}} pinned to {{slotLabel}}",
  "{{controlLabel}} unpinned".
- Docked items can't be moved.
- The layout is saved per layout id `"<entityType>-<layoutTemplate>"` through
  `updateUserExperiencePreferences` (`stageSettings.callingControlsPreferences.layouts[{id, controls:[{name, slot: HORIZONTAL_MIDDLE_END|OVERFLOW|…, group, priority}]}]`).
  Session-only hoisting is saved through `setCallingControlsSessionSettings(layoutId, controls)`.

### 1.7 Auto-hide ("Hide meeting controls")
- Needs `enableHideUbar` (live false). Then More › Settings has "Hide meeting
  controls" / "Always show meeting controls" (`calling_hide_controls_button`,
  `calling_show_controls_button`).
- The choice is stored in `clientPreferences(category:meeting).hideControls`
  (`ComponentsMeetingSettingsHideControlsMutation`).
- Hide delays: `hideUbarInitialDelay` 3000ms, `hideUbarDelay` 500ms.
- Always hidden by default with `enableHideUbarByDefault`.
### 1.8 More (…) menu (live `Inline` preset 0, `default` layout)
The menu opens from MoreButton. It has label "More", tooltip "More actions" and
is `Docked`. It is a vertical menu (`MenuControls`); groups are separated by
dividers. Its contents, top to bottom:
1. **Overflowed bar items**: placeholders of every bar item that doesn't fit,
   in bar order (§1.5).
2. The preset's groups. An item shows only if it is available for the layout
   and visible by its rule. A submenu shows only when at least one child is
   visible (`hierarchy.hasVisibleNodes`).

On winpc (meeting, nothing overflowed) More reads: Record and transcribe ▸, Meeting info, Timer, Video effects and settings, Audio settings, Language and speech ▸, Settings ▸, divider, Report a concern, Help. Sections follow the bar's MergeWithNext rule (a section of one merges into the next without a divider). The menu is View's style (padding 16, 230 px rows) at the More button's left, 5.33 below it.

Menu item text is the control's `title` when it has one (the menu renderer `VC`
drops `buttonLabel`); otherwise its label.

| group | item (control) | text (en-us) | shown when (besides layout `available`) |
|---|---|---|---|
| overflowTop | RestartEvent | "Restart event" | broadcast producer, `enableRestartEventForBroadcastProducers` |
| | Streaming ▸ (StreamingMenuControl) | "Streaming" → Streams / Broadcast / Switchboard | `enableMediaStreamsPanel` / NDI visible in calling UI |
| | Record and transcribe ▸ (RecordingMenuControl) | "Record and transcribe" → "Start recording"/"Stop recording" (RecordingButton), "Local recording" ("Record to my computer"), then "Start transcription"/"Transcript" (TranscriptButton, TranscriptPanelButton "Transcript"), "Stop Data Collection", then "Voice ID" | recording: not appliance mode, not a green room, not E2EE; local recording `enableLocalRecording` (live false); transcript panel `enableCallTranscript` (live true) |
| | IsolateVoiceButton | "Voice isolation" | `enableIsolateVoiceButton` (live false) |
| | MusicModeButton | "Music mode" (title "High fidelity music mode") | `enableHighFidelityAudioToggle` (true), not 1:1 PSTN, town hall only with its own flag |
| | BroadcastYammerButton | "Yammer" | broadcast |
| settings | MeetingInfoButton | "Info" | `enableMeetingInfoButton` = `!pn.tO()` (what that platform check means is unverified) |
| | FacilitatorButton | "{{appName}}" ("Facilitator") | Copilot facilitator flags; private/channel meeting |
| | MeetingFacilitatorTimerButton | "Timer" → "Ad-hoc timer" / "Agenda timer" | `enableTimerUBarButton` (true); not town hall, webinar, Attendee, or group call |
| | MeetingInsightsButton | | `enableMeetingInsightsPanel` |
| | WhiteboardButton | "Whiteboard" (title "Start Whiteboard") | `enableWhiteboardButtonInUbar` (live false), not town hall, not E2EE |
| | MeetingNotesButton | "Notes" | `enableMeetingNotesLink` |
| | MeetingContentBinButton | "Shared" (title "Open shared content") | private scheduled meeting only (not channel, ad hoc, Meet now, town hall, webinar, 1:1 or group call) and `enableMeetingContentBinControlInUbar` |
| | CameraEffectsButton | "Video effects and settings" (other titles depending on flags: "Video effects", "Effects and avatars", "Video settings", "Video settings and avatars"; while open "Hide …") | not appliance mode, not AV-over-IP blocked, and either (not E2EE and video extensibility/avatars) or `enableAVFramework` (live true) |
| | CustomVideoBackgroundsPanelButton | "Backgrounds" | `enableVideoBackground` && not `enableAVFramework` → **hidden live** |
| | AudioSettingsButton | "Audio settings" ("Hide audio settings" while open) | `enableAVFramework` (live true), not broadcast producer, not town hall streaming |
| | Language and speech ▸ | "Language and speech" → "Captions" (ClosedCaptionsButton), "Interpreter" (AI interpretation for all), "Interpretation" (live interpretation), "Speaker Coach", "RTT" | captions: not appliance mode, not E2EE unless local captions |
| | Settings ▸ | "Settings" → group 1: "Devices" (DeviceSettingsButton, title "Device settings"), "Privacy mode", "Call health", "Meeting options", "Accessibility"; group 2: "Chat bubbles", "Notifications", "Hide meeting controls"; group 3: "Data" ("Collect my meeting data") | Devices: **hidden when `enableAVFramework`** (live true), except for a town hall Attendee; Call health `enableCallHealthForMeetings` (true); Meeting options = organizer legacy rule (§1.4); Accessibility `enableAccessibilityView` (true); Chat bubbles `enableChatBubbles` (true); Notifications `enableMuteNotifications` (true), labels "Mute notifications"/"Allow notifications"; Hide controls `enableHideUbar` (false) |
| callingOverflow | (flat; see note) | "Call me" (PstnButton, PSTN call-me-back), "Dial pad", "Hold", "Upgrade" ("Upgrade to video call"), "Transfer" (V1), "Merge Calls", "Park Call", "Lock Call"/"Unlock Call" (SLA lock) | `CallMenuControl` ("Call ▸") is in **no** live layout's `available` list. Its children are therefore promoted into More itself, as a flat "callingOverflow" group. `CallTransferMenuControl` ("Transfer ▸": Transfer / Consult then transfer) exists only in the 1:1 and PSTN layouts, and is hidden when `enableUbarTransferButtonOnL1` is on (live) |
| reportMeeting | ReportMeetingButton | "Report a concern" (short "Report") | `enableReportMeeting`, private/ad hoc/Meet now meeting, not town hall, webinar, 1:1 or group call |
| help | ReportProblemButton | "Report a problem" | not in the `default` layout's `available` list, so not shown in meetings (verified on winpc: More ends with "Report a concern", "Help") |
| | MeetingHelpButton | "Help" | |

In the 1:1 layout, Hold, Dial pad and Transfer are on the bar (§1.4). Call ▸ then
only holds what is left (Merge, Park, Lock).

### 1.8a Recording and AI indicators (RecordingIndicator `g3`, CopilotIndicator `J3`/`aR`; measured on winpc, 2026-11-08)
- **Where the state comes from.** The call recorder joins the roster as a hidden `28:` participant (no display name). Its endpoint's `endpointMetadata.processingModes` has `realTimeTranscript`, `recording`, `copilot` (and `closedCaptions`, `ephemeralTranscript`, `faceStream`), each `{state: "Active" | "Inactive", userId, timestamp, properties}`. The join response's `roster` carries it, and `conversation/rosterUpdate` callbacks change it (Stop → "Inactive").
- **Order in the indicators slot.** Shield (x 8, 30 × 32), then the recording indicator (30 × 32, glyph 5 in), then the AI indicator (37.33 × 32), then the duration (text 6.67 into its slot). Teams' layout config has no `LockMeetingIndicator`, so a locked meeting shows no lock here.
- **Recording indicator.** State: "Transcribing" (transcript only: the transcript glyph), "Recording" or "RecordingAndTranscribing" (the ring `M16 8c-4.4…` in #424242 with a red #D13438 dot of r 4.6, viewBox 6 6 20 20). Tooltip from who started each, by name:
  - "Transcription started by {name}."
  - "Recording started by {names}."
  - "Recording and transcription started by {name}." (same person)
  - "Recording started by {names}. Transcription started by {name}."
  - Without names: "Transcription started" / "Recording started".
- **AI indicator** (`calling-agents-control-ubar-indicator`):
  - **When it shows.** Only in meetings: Meet now, or a non-channel ("private") meeting with a calendar event (`iCalUid`). Not in ad hoc calls, channel meetings (`enableAiIndicatorControlForChannelMeeting` is unset) or end-to-end encrypted meetings. 1:1 and group calls fall back to the legacy Copilot indicator, which only shows while Copilot runs.
  - **Disabled** unless `meetingCapability.copilotMode` is "Enabled" or "EnabledWithTranscript".
  - **On** while the transcript (or Copilot's own) runs.
  - **Looks.** A 28 × 20 pill (padding 0 4, fully rounded) holding a 20 px glyph.
    - Off: Sparkle Off on NeutralBackground1, #242424, brand on hover.
    - On: filled Sparkle in white on BrandBackground (BrandBackgroundHover on hover).
  - **Tooltips.** "AI is on in the meeting" / "AI is turned off and doesn't have access to the meeting" / "AI isn't available in this meeting". Bar tooltips sit 4 under the bar, start-aligned, up to 240 wide.
- **"Meeting AI" menu** (`calling-agents-control-ubar-indicator-popover`, `enableAiControlsMenuList`):
  - **Popover.** 313.33 × 205.33, 13.33 under the indicator, its left edge on the indicator's. Padding 16.
  - **Contents**, a 280-wide group:
    - Header "Meeting AI": 32 tall, 12/20 600 #616161, padding 0 8.
    - Read-only note (`read-only-ai-access-message`, people without a Copilot licence): "You don't have access to AI in this meeting.", 36 tall, #F5F5F5 with a #D1D1D1 hairline, 12/16 text 12 in.
    - Switch rows (32 tall, padding 6, 20 px glyph, label at 32, 40 × 20 switch 4 from the end): Copilot, Facilitator, Intelligent recap.
  - **Checked states.**
    - Copilot: transcript running && AI enabled.
    - Facilitator: transcript running && `groupCopilotDetails.enabled`.
    - Intelligent recap: Copilot checked && recap enabled.
  - **Unlicensed.** All rows are disabled: #BDBDBD text and glyph, and the track stays #F0F0F0 with a #E0E0E0 hairline when checked too. The 14.4 px thumb's 18 px box sits 0.67 in, or 20.67 when checked.

### 1.8b Meeting info pane (More ▸ Meeting info; `calling-meeting-info-panel`; measured on winpc, 2026-11-08)
- **When it shows.** `MeetingInfoButton` is in meetings only (`isMeeting`), not in breakout rooms or screen-share-from-chat calls.
- **Where it opens.** The 360-wide right side panel (#F5F5F5), with rail header "Meeting info" (16/22 bold) and close ("Hide meeting info pane").
- **Content.** Column 20.67 in and 305.33 wide, 16 under the header:
  - Title (`call-title`, 20/28, 10 below).
  - `meeting-hours`: "3:00 PM - 3:30 PM (30 minutes)" (`duration_full_mf`; no line when there are no hours or minutes).
  - `recurrence`:
    - Single meeting: "November 6, 2026 at 3:00 PM - 3:30 PM".
    - Series: "Occurs every … @ {time}[ until {Month D}]".
  - `location`, all 14/20.
  - The empty dial-in and support slots add 15 px gaps each, so the copy row sits 30 below.
- **Copy row.** Link glyph, then "Copy join info" (240 × 31.33, padding 5 12, 14/20 600, #D1D1D1 hairline). It becomes "Copied to clipboard" for 2 s.
  - It copies the event body's `div.me-email-text` (HTML + text).
  - Else it copies the `WordSection1` child holding the join link.
  - Else it copies `<div><a …>Join Teams meeting</a></div>` with the short `/meet/` link, plain text = the link. This was verified on winpc's clipboard.
- **Body** (`meeting-body`, 30 below). The calendar event's body, found by iCalUid, with newlines as spaces and only AMS images kept. Outlook's 11pt text renders at 14.67 px on 20.95 px lines; links are brand #4F52B2 and not underlined. URLs wrap only after "-", "?" and spaces, else at the line's edge.
- **Data.** Title, start, end and location come from the join response's `meetingDetails` (`meetingChatProperties`). Recurrence comes from `eventRecurrencePattern` / `eventRecurrenceRange`; OST uses the event's Graph `recurrence`.

### 1.8c Audio settings pane (More ▸ Audio settings / Mic ▾ "More audio settings"; `audio-settings-panel`; measured on winpc, 2026-11-08)
- **Layout.** A side pane with rail header "Audio settings" ("Close audio pane"). Below it, Fluent accordion sections 10 under the header: 32 px headers, Northstar caret 16 px 4.67 in, 12 px titles 20.67 in. Content sits 20.67 in, 305.33 wide.
- **Speaker.** Device radios: rows are the text + 10, the radio 20 px at −2, names 26 in. Then the speaker button (−6) and the volume slider.
- **Microphone.** Device radios, then the mic button and the 17-bar meter across the column. Sections are 16 apart.
- **Advanced settings.**
  - Spatial audio comes first (TASK-0232; audio-settings-panel 311594: SpatialAudioContainer at SETTINGS_PANEL, `shouldHideDescription`, info shown, AVF). It shows only when the media stack can render it (`isSpatialAudioAvailable`). Its row is the noise suppression row's layout (label 14, the 24 px info button after it, the switch with Fluent's −8 margin so its 40 × 20 track ends at the column edge; justify space-between, centred). The info popover reads `calling_spatial_audio_title_tooltip_avf` "Enable this to experience audio to come from where the person speaking is positioned on your screen. Works well with Together mode, gallery and speaker view. Not available on wireless headphones yet. Learn more" (12/16 NeutralForeground2; the link is ECS `spatialAudioLearnMoreLink`). Off and disabled where the speaker isn't spatial capable or in a P2P call (or a meeting space group), as in the Mic flyout; switching it is `setSpatialAudio`, the device setting.
  - Noise suppression is a 36 px row with a switch 40 × 20 ending at the column edge; the switch is outlined in #616161 when off. The Background noise only / Voice isolation radios show only when voice isolation is supported; otherwise the row has the info button (tooltip "Enable this to enhance your microphone audio quality by removing background noise. Learn more" → aka.ms/noisesuppression).
  - High fidelity music mode (info → fwlink 2168036), then "Recommended for studio environment." (12/16 #424242) 30 down. Then checkboxes, 32 tall with a 16 px box: "Display in the microphone dropdown menu" and "Enable echo cancellation" (on by default), disabled while music mode is off.
- **Behaviour.**
  - Turning music mode on turns noise suppression off; turning it off restores it. Noise suppression can be turned back on during music mode.
  - With "Display in…", Mic ▾ shows the music mode row after noise suppression, with the description 30 down and 10 before the divider.
  - Music mode per Microsoft: 32 kHz sampling at up to 128 kbps, mono, no gain control, echo cancellation optional.
- **InfoButton.** 24 px with the 16 px Info (regular at rest, filled and brand on hover). Its popover is 264 wide, padding 12, 12/16 text, 6 above the button. When it would leave the pane it sits at the pane's left edge.

### 1.8d Record and transcribe ▸ (RecordingMenuControl; captured on winpc, 2026-11-09)
- **Submenu.** Opens to the left of More, its surface's right edge at More's list and its top at the row's.
- **Items, by state.**
  - Recording: Start recording / Stop recording. Tooltips: "Start recording and transcription", or "Start recording only" while transcribing; "Stop recording and transcription".
  - Transcription: Start transcription / Stop transcription.
  - Hide / Show transcript (the Transcript pane).
- **Dialogs.**
  - "What language is everyone speaking?" (480 wide): the language dropdown with the current choice first, then 57 languages.
  - "Start recording and transcription" (522 wide): the same, plus More options ▸ Choose what to record (Video and audio / Audio only).
  - "Start recording" (522 wide, while transcribing): only the record-mode choice.
  - Stops ask "Stop transcription?" / "Stop recording and transcription?" (400 × 152.67, Cancel / Stop).
- **Protocol.** A POST to the hidden recorder participant's `endpointMetadata.commandUrl`:
  - Auth: Bearer token, aud 4580fd1d-…, scope `access_recorder_service`, plus `x-microsoft-skype-chain-id`.
  - Body: `{timestamp, participantMri, participantLegId, action, mode?, processingModes, actionParameters?, participantSkypeToken: ""}`.
  - Transcription: mode "transcription", modes `["realTimeTranscript"]`.
  - Recording: modes `["recording","realTimeTranscript"]` and `recordingMode` Normal / AudioOnly.
  - A start's `actionParameters`: features, OneDrive storage "<title>-YYYYMMDD_HHMMSS-Meeting Transcript|Recording", iCalUid, correlationId, meetingTitle, meetingOrganizer, spokenLanguage, type "start".
  - The reply is `{CorrelationId}`; the roster's processingModes then change.
- **Roster.** The recorder is hidden: its endpoint has `__platform.ui.hidden`, though not every update repeats it. Its updates can arrive out of order, so a participant's `version` decides.
- **Recorder not in the call** (a fresh meeting conversation or a group call).
  - Teams first invites it, the combined recording / transcript / captions bot `28:bdd75849-e0a6-4cce-8fc1-d7c0d4da43e5`.
  - It POSTs the conversation's `addParticipant` link (IC3 bearer) with `participants {from, to:[{id: <bot>, participantId}]}` and `participantInvitationData.botData {meetingTitle "", clientInfo, callId, threadId, recorderFeatures, mode "RecordingAndTranscription", iCalUid, consumerType "Teams", spokenLanguage, initiatorUserToken (the recorder-service token), exchangeId, meetingOrganizer}`, plus the success and failure callback links.
  - The service answers 202. The bot joins the roster with its commandUrl within seconds (3.7 s measured), and then the command goes out.

### 1.8e Transcript pane (`call-transcript-panel`; measured on winpc, 2026-11-09)
- **Opening it.** More ▸ Record and transcribe ▸ Show transcript / Hide transcript ✓ (TranscriptPanelButton, `transcript-panel-button`).
  - The row appears once a transcript has run in the meeting (Teams' `hasBeenStarted`).
  - Its check is 16 px, 6 px from the row's end.
  - Teams opens the pane for whoever starts the transcript.
- **Header.** Like the other side panes: "Transcript" (16/22 bold, at 20.67, 19.67), then Language settings (32 × 31.33 at x 276) and Close (at x 308).
- **Captions message bar.** 84 tall, #F5F5F5, shown while live captions are available.
  - The info glyph (20, #616161) and "Follow the conversation better in real time by using live captions." (14/20, at 40.67, 283.33 wide).
  - Dismiss (24 × 23.33 at x 324).
  - "Switch to live captions" (23.33 tall, 14/16 semibold, #D1D1D1 hairline, radius 4, 12 from the right).
- **List.** From y 145 under the bar, else under the header; the runway is 10 px in.
  - Above the first row: the info glyph (16, at 21.67) and "AI-generated content may be incorrect" (14/20, at 47.67), 12 down.
  - Transcript start or stop: the record glyph (16, #424242, at 21.67, 11 down) and "<name> started transcription" / "stopped transcription" (14/20 at 47.67, 9 down); 31 tall.
  - Speech: a 32 px avatar (x 10.67, 13.19 down); the name (12/20 semibold, x 52.67, 12.53 down); a guest's unverified glyph 4 px after; the time ("6:22 PM", 12/16 #616161) 8 px after; the text (14/20, x 52.67, 30.53 down, 259.33 wide).
  - The same speaker's next rows drop the header: text 9.2 down.
  - A new header starts when the speaker id changes or an event comes between. Every row has 2 px below.
- **Follow.** The list stays on the newest row unless you scroll up. Then "Go to current" appears: primary, 125.16 × 28, 20 px from the right and bottom, padding 0 8 1 5, a 20 px arrow-down glyph and 14/28 semibold text.
- **Data.**
  - Live: the media processor's speech recognition on the MCP data channel ("main-channel"), in frames headed `10 0b 83`. The JSON is `{recognitionResults:[{id, userId, displayName, text, isFinal, timestampAudioSent (100 ns since 1900), …}]}`. The pane lists the finals, then each speaker's current partial (see 1.8f).
  - Stored, read on opening: POST `{"artifactTypes":["Transcript","CallEvents"],"maxResults":-1}` to the join response's `meetingDetails.realTimeActivityFeedDetails.links.getArtifacts`. It uses the IC3 token, `x-ms-session-id`, `x-ms-correlation-id` and `x-microsoft-skype-chain-id`.
  - Transcript entries: `jsonContent {entryId, text, speakerId "<oid>@<tenant>", displayName, startTime, …}`.
  - CallEvents: `{eventType TranscriptStarted|TranscriptStopped|…, userId, displayName}`.
  - Teams merges the two by time.
- **Speaker ids.** Teams resolves "<oid>@<tenant>" to "8:orgid:<oid>", leaves "<n>@local" as is (its name "@n" reads "Speaker n"), and adds "8:" to bare ids.
  - So a guest's stored rows (8:orgid:<guid>) and live rows (8:teamsvisitor:<guid>) group separately.
  - A stored event without a name takes the person's name from the meeting.

### 1.8f Live captions (Language and speech ▸; captions v2; measured on winpc, 2026-11-09)
- **Menu.** More ▸ Language and speech ▸ (LanguageSpeechMenuControl): "Show live captions" / "Hide live captions ✓" (Alt+Shift+C) and "Turn on RTT for this call".
  - More and its submenus have 230 px rows inside 16.67 padding.
  - The shortcut ends 6 px before the 16 px check.
- **Window.** A strip under the stage (or under the bar, "At top"), 4 px in from the window's sides and bottom, in the background colour.
  - Height by Panel height: 118 / 132 / 148 px in windows up to 682 px tall, else 22 / 43 / 72.5 % of the area under the bar.
  - The stage ends 2.67 px from it.
  - The list is centred, 550 / 620 / 870 / 1000 px wide by Font size, at most 75 px narrower than the strip (then flush left). It scrolls, with the newest at the bottom.
- **Caption.** 2 px above.
  - The speaker's 32 px avatar sits at x 8, 4 down.
  - The name (10/14, 12/16, 14/20 or 16/22 semibold) is followed by a guest's unverified glyph.
  - The words (12/16, 16/22, 24/32 or 28/36) start at x 52, 15 down, with 2 px below. Items are 39 / 61 / 83 px for 1 / 2 / 3 lines at Medium.
  - Every caption shows its speaker. Teams has a path that drops the header for a final from the same speaker, but in 90 s of sampling it never fired.
- **Before any caption.** "Captions will be shown in English (US)." (16/22.86, centred, in the font colour).
- **Buttons.** 32 px, 6 down, 8 from the right.
  - Teams shows Thumb up, Thumb down, caption settings, Open captions in new window and Hide live captions.
  - When they don't fit beside the list, all but Hide fold into "…".
  - OST leaves out the thumbs (they only send Microsoft telemetry, which OST never sends).
- **Caption settings menu.** It opens above the gear, right-aligned.
  - "Meeting spoken language" with the language (12/20 #616161) and a chevron. The languages open to the left: the current one first with its check, a divider, then the 57 languages; the list scrolls past 270.
  - A divider, then Caption styles.
  - "Position" (At top / At bottom).
  - A divider, then "Always turn on captions" and "Filter profane words", each with a 40 × 20 switch.
- **Caption styles pane.**
  - Font color: White, Black, Red #FE0000, Green #00FF00, Blue #0000FF, Yellow #FFFF00, Aqua #00FFFF. Background color: Black, White and the same colours.
  - Swatches are 32 px with radius 4, a 0.67 #D1D1D1 border, and the chosen one 2 px #444791.
  - Font size: Small, Medium, Large, Extra large. Panel height: Small, Medium, Large.
  - Stored on the device ("closed-captions-settings"). Defaults follow the theme: black on white when light.
- **Protocol.**
  - On:
    - If the recorder isn't running captions, POST its commandUrl with `{action:"start", mode:"transcription", processingModes:["closedCaptions"], participantSkypeToken:""}` (no actionParameters), using the recorder token and `X-Skypetoken`.
    - Once the roster shows `closedCaptions` Active, PUT the conversation's `updateEndpointMetadata` with `{participants:{from:<us>}, endpointMetadata:{transcriptionPrefs:{closedCaptions:true}}}`.
  - Off: only that PUT with `false`. The recorder stops once no endpoint wants captions.
  - Spoken language: `action:"setLanguage"` with `actionParameters {spokenLanguage, type:"setLanguage"}`.
  - "Always turn on captions" and "Filter profane words" are `startCaptionsAutomatically` and `profanityFilterEnabled` in the `callAccessibilitySettings` user property. Teams PUTs the whole JSON object to the chat service `/v1/users/ME/properties?name=callAccessibilitySettings`.
  - The filter chooses the service's `text` (filtered) over `rawText`. It applies to the Transcript pane too.
- **Data.** The same recognition results as the transcript.
  - Each partial and each final has its own id.
  - A speaker has one partial at a time: the next replaces it and the final removes it.
  - A partial not refined for 5 s is dropped.
  - The Transcript pane lists the finals, then the current partials.
- **RTT (real-time text; measured on winpc, 2026-11-09).**
  - Language and speech ▸ "Turn on RTT for this call" asks first: "RTT" (20/28 semibold), "RTT (real-time text) will be turned on for everyone in the call." (14/20), then Cancel above Turn on, each the full width (270.67 × 31.33, 8 apart). The dialog is 320 × 204, padding 24.67.
  - Once on, the item is greyed with its check; RTT stays on for the call. Nothing is signalled: everyone else's turns on with the first words that reach them, and their card leaves out "by you".
  - The captions window shows while RTT is on, captions or not. Its only button is "…": a "Live Captions" switch (36 tall: a 40 × 20 track 8 in, the label at 60) that starts and stops captions, Open caption settings ▸, and "Open RTT/Captions in new window".
  - The list opens on a card: 596 wide, 9 in and 7 down, padding 12, radius 4, a card shadow. "RTT" (14/20 bold), then 12 below: "RTT (Real-time text) has been enabled [by you] for all participants throughout this meeting [call]. All typed conversations in the RTT text box will be recorded, transcribed, and included in the transcript, in accordance with the Microsoft Privacy Statement." The link is the tenant's privacy statement (`GET {mt}/beta/tenant/privacyProfile` `statementUrl`), else Microsoft's (go.microsoft.com/fwlink/p/?linkid=857875).
  - The RTT box sits under the list, as wide as it, 6 above the window's bottom (38 px for it). It's an outlined input 32 tall, radius 4: sides #B3B3B3, bottom #4D4D4D, a 2 px brand line while focused, "Type a message in real-time" 12 in.
  - What's typed goes every 300 ms: a backspace (U+0008) for each character after what the old and new text share, then the new end. A change of nothing but spaces waits. Enter ends the line (what's left and `\n`); so do 3 s without a key (`\n`). The box then empties. 2000 characters at most.
  - Above the box, when needed, a 36 px bar (#F5F5F5, a #D1D1D1 border, radius 4, its words 20.67 in): "Please type a message to continue." (Enter on nothing but spaces; nothing is sent) or "You cannot type more than 2000 characters" (the box keeps what it had).
  - A sender's line is built per data source: characters append, a backspace removes one, a newline ends it (a line of only spaces ends empty). It keeps the time it began. Someone typing on a second device ends their line on the first. Someone who leaves has their line ended.
  - Each person has one line being typed. It shows as a caption does, but 14.67 further in after a 1.33 px brand line 12 in (40 tall, 8 down), with "RTT Typing" (the name's size, semibold) 12 after the name. The lines being typed are at the bottom, yours last. An ended line joins the captions at the time it ended. One erased to nothing goes.
  - Your own lines show as you type (Teams doesn't wait for them to come back). When your account types on another device, this box empties.
  - In the window of its own the heading is "RTT", the "Live Captions" switch sits at 333.93 (its label ending 122 from the right), and the box is 23 in, 24 from the right, the list 10 above it.

### 1.8g Settings ▸ and the in-meeting Accessibility pane (measured on winpc, 2026-11-09)
- **Settings ▸ items.** Call health, Accessibility settings, a divider, "Don't show chat bubbles" / "Show chat bubbles", and "Mute notifications" / "Allow notifications".
- **More ▸ Report a concern.** Opens "Report a security concern", 600 × 460.67.
  - Meeting card: #E8EBFA with a 6 px brand bar, showing the title, the start ("Nov 6, 3:00 PM") and the organizer.
  - Explanation: up to 250 characters, a 4-row filled text area, with a character counter.
  - "Report participants (optional)" picker: the chat's members, then the meeting's other participants, never you. Chosen people show as pills.
  - Disclaimer, then Cancel and Report.
  - Report sends the unified report API (`POST {mt}/beta/reports`) with `{reportTimestamp, reportType: "Meeting", reportedUsers: [MRIs], actions: [], category: "Security", comment, callId, iCalUId, threadId}`.
  - Success shows "Your report was sent". Failure shows "Failed to submit report. Please try again." (14/20 PaletteRedForeground1, 12 below it) right under the card, moving the rest down.
  - Both cards carry Fluent's shadow2.
- **Participant ··· ▸ Report** (last, after Remove from meeting; a divider before them). Opens the same dialog in its "person" mode: "Report this person", 600 × 359.33, a 48 px card (#F5F5F5, radius 4, padding 8 × 12, shadow2: the 32 px avatar and the name 14/20 semibold) in place of the meeting card, and no participant picker. It sends the same unified report (`reportType: "Meeting"`, `category: "Security"`) naming that one person in `reportedUsers` (meet-app-modal and the meet-for-work resolver). Not filed while testing.
  - No live report was filed to check the success toast's layout.
- **More ▸ Help.** Opens Teams' Help app in a window of its own (946 × 593 content).
  - URL: `https://help.svc.cloud.microsoft/f1/home/?shownav=True&NS=MSFTTEAMS&version=16&omkt=<locale>&RingId=general&context=<JSON>`.
  - The context has `SubEntityId: "helpappmeetings"`, plus the theme, session, app version, `HostClientType: "desktop"` and `TeamsHostName: "TeamsModern"`. Teams also sends the tenant SKU and licence type, which OST doesn't know for every tenant.
  - The page opens on "Get help with Microsoft Teams meetings".
  - The window (measured on winpc, 2026-11-09): Teams' child-window title row (32 tall on the #EBEBEB chrome, "Help" 12/16 8 in, and "Settings and more": Pin window on top / Unpin window, Ctrl+Shift+T; Teams also lists Zoom, tracked with the main window's in docs/parity, and Report a problem, feedback to Microsoft, which OST doesn't send).
  - Then the Help app's header (entity-header, 61 tall, a 0.67 #E0E0E0 line): the app's tile (32, round, from its app definition, id 5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83) 20 in, "Help" (18/25.71 bold) at 72, and "More Help actions" (32 × 31.33, 7 from the right): Reload app, a divider, About and Share app (Teams' app details dialog and Share form, in the Help window; docs/spec/app-details.md).
- **Captions in a window of their own** (Open captions in new window; flyout-closed-captions).
  - 606 × 353, kept on top until unpinned. Once unpinned, Teams no longer shows the pin.
  - Title row, the same child-window title row: Pop in (32 × 31.33), the meeting title (12/16, 8 after it), then the pin (24 × 23.33, "Unpin window") and Settings and more.
  - "Live Captions" (20/28.57 bold) sits 20 in, with caption settings 18 from the right. Then the captions, 15 in.
  - The strip under the stage goes away while it's out. Pop in, or closing the window, brings it back.
  - In the strip, the pop-out button sits between settings and close; when the strip is narrow it moves under "…".
- **Chat bubbles** (ufd_chatBubble). Someone else's message in the call's chat shows while the chat pane is closed.
  - One bubble at a time; a newer message replaces it. It lasts about 4 s (measured) and fades over 300 ms.
  - Placement: 320 wide, centred over the stage, 10.67 under the bar.
  - Card: #FAFAFA, radius 8, 0.67 #F0F0F0 border, 68 tall for one line and 88 for two.
    - The sender's 32 px avatar with presence ("Unknown" for a guest) sits at x 12.67.
    - Name: 12/20 #242424, then a guest's unverified glyph.
    - "Mute these notifications" (the bell-snooze glyph) and Close, both 20 px.
    - Message: 14/20 #616161, at most two lines, at x 56.67 and 40.67 down. Teams previews 200 characters.
  - Clicking the bubble opens the chat. "Mute these notifications" turns bubbles off for the call, the same as Settings ▸ "Don't show chat bubbles", which then reads "Show chat bubbles".
- **Mute notifications.** Per call (`muteNotificationsDuringMeetings` for the teamsCallId).
  - While muted, message notifications don't show; calls and meetings still ring.
  - The row reads "Allow notifications" with the bell glyph. Screen readers hear "Notifications muted" / "Notifications allowed".
  - Teams' layout config also lists Device settings, Privacy mode, Meeting options and Hide controls where they apply.
- **Accessibility pane.**
  - Background #F5F5F5 under the rail header "Accessibility".
  - Cards 305.33 wide at x 20.67, 12 apart from y 89. Each has a 0.67 #D1D1D1 border, radius 8 and padding 20 × 12.
  - A 20 px glyph sits at 18.67. The title (14/20) is at 56.67, with a description below (12/16 #616161, 138.68 wide).
  - The switch is 40 × 20, with "On" / "Off" (14/20) 10.67 before it.
  - Group cards (Captions, Monitoring participants) put their title beside the glyph and their settings 68.67 down.
  - Cards:
    - Sign language mode.
    - Captions: "Always show captions in my calls and meetings" and "Filter out profane words in live captions", both in `callAccessibilitySettings`.
    - Muted notification: the 'You're muted' notice, stored on the device.
    - Monitoring participants: "Hide Call Monitor when minimizing meeting window" (`hideCallMonitorOnMinimize`). It keeps the compact call window away, except while you share.
  - OST shows the Muted notification card (it turns "Your microphone is muted" on and off; meeting-video.md). The Sign language card waits for sign language mode.

### 1.8h Meeting timer (More ▸ Timer; lazy-meeting-timer bundle, measured on winpc, 2026-11-09)
Full code reading: scratchpad timer/spec.md (session 744c3998); the model is `calling::meeting_timer`.
- **Shared state.** The conversation meeting state `timer` = `{sequenceNumber, value: {data: "<JSON {adhocTimer, agendaTimer, rosTimer}>", lastEditTime}}`. Each timer is `{state: InProgress | Paused | Cancelled, remainingDuration (ms as of its lastEditTime), lastEditTime, previousState, sections: [{title, originalDuration}], pendingConsent, consentRequested}`; the ad-hoc one has one untitled section, at most 99:59. The service stamps the outer `lastEditTime`; on receipt a timer that was running loses the time up to that stamp, which becomes its `lastEditTime`. Updates Teams would refuse are ignored.
- **Changing it.** POST the conversation's `updateMeetingStates` link: `{from, meetingStates: {timer: {sequenceNumber: <last seen>, value: {data}}}, updateMeetingStatesStatus: <callback>, operationId}`. Nothing changes locally until the update comes back. Start / Resume / Pause / Reset (runs it again from the top) / +1, +5, +10 min (resumes a paused one) / Cancel timer (keeps its length for next time) / Start a new length / Cancel timer for everyone (over time); leaving `lastEditTime` out means "from now".
- **Who.** Shown where everyone can present (`presenterOption` Everyone / EveryoneInCompany); attendees see it view-only (countdown and track). It opens for everyone when someone starts one and when you join with one running; when it's cancelled only the person who cancelled keeps it. More ▸ Timer (✓ while shown) toggles it; with no timer running the setup opens at once.
- **Strip** (legacy layout): under the bar, white, a 1 px #D1D1D1 line, 2 + 35 + 2 tall, 12 in. The countdown (24/32 semibold #5B5FC7; red #B10E1C and "-mm:ss" once over time; seconds rounded up) is the "Timer controls" trigger (padding 0 5, radius 8, hover #F5F5F5, open #E0E0E0). Then ▶/‖ (Start new timer / Pause timer / Resume timer; over time "Cancel timer for everyone") and ↻ Reset timer (off while cancelled), 21.33 px, 10 apart. Then the track (24 tall, radius 8, #EBEBEB): the time left in #C5CBFA from the right, its end turning #F1BBBC after 60 %; whole when the timer is off; "Paused" (white 14/20 semibold) over 40 % black; over time red, growing back over 400 ms then blinking 3 times, with "Time's up!" (#960B18). Time-up plays Teams' chime (OST synthesises its own).
- **Timer controls** (213.33 × 153, padding 16.67, 10 apart): "mm : ss" (32 semibold brand) or, to set one, minutes and seconds boxes (70 × 42.67 on #F5F5F5, increment and decrement 24 × 16); "+1 min", "+5 min", "+10 min" (12/16, spread across); Cancel timer (off while none runs) or Undo, and Edit or Start (off at 00:00). A new timer starts at 05:00, then the last length used.
- **Screen readers.** 10, 5 and 1 minute and 10 seconds left; "Timer has run out of time."; for everyone on each update: started with / paused at / resumed with … / Timer stopped.
- **Agenda and Run of Show** need Teams' Facilitator (Copilot); without it (`groupCopilotDetails.enabled` false) Teams shows neither and OST keeps their shared state untouched (TASK-0073).
- **Facilitator turned off mid-meeting** (Teams 26304, TASK-0248): the timer's `isFacilitatorOn` (useMeetingTimer, module 357072) is the call's `meetingDetails.meetingCapability.groupCopilotDetails.enabled` (false in a Meet now while ECS `meetingCollaboration.enableMeetNowFaAgendaTimerDisabled`, on for this tenant), which a conversation update carries when the organizer turns Facilitator off (`updateMeetingSettings` `groupCopilotDetails.enabled: false`). Without it the agenda drops out of the timers Teams offers (no switcher) and, as the strip's view state is left alone (only with ECS `enableAgendaUbar`, off here, does Teams move it to the ad-hoc timer or close it), the strip stays open and shows the ad-hoc timer in the agenda's place, and with no timer active Teams opens that timer's controls for whoever can set a timer (lazy-meeting-timer `ws`: its popover shows while no timer is active and the ad-hoc view shows, not view-only); Facilitator turned on again brings the agenda back and closes them. Seen live on winpc 2026-11-23 ("OST TEST 248 agenda", Facilitator's 2 / 2 / 1 min agenda): turned off, Teams showed 05:00 ▶ ↻ with Timer controls (05 : 00, +1 / +5 / +10 min, Cancel timer, Start) open; turned on again, the agenda strip came back. OST does the same: the capability update refreshes the timer's Facilitator flag at once (`Backend::refresh_timer_facilitator`, `meeting_options::facilitator_on`), and the call window keeps the strip and its view (`agendaChanged`).
- **Facilitator** (measured in Teams on the web, 2026-11-16, ost-test1 with the Microsoft 365 Copilot licence, a solo scheduled meeting): the meeting editor says "Facilitator is off for this meeting. Turn on"; in the call More has **Facilitator ▸** (between Meeting info and Timer; 230 × 32 rows, its glyph #5B5FC7 while on) with "Turn on Facilitator" / "Turn off Facilitator" and "Enable voice" / "Disable voice" (SoundWaveCircle; disabled while off).
  - Turn on: `POST {mt}/beta/meetings/v1/facilitator/options/{organizer}/{thread}/{message}?monarch=true` `{"options":[{"name":"IsGroupCopilotEnabled","type":"Boolean","currentValue":true}]}`; with no transcript Teams shows the calling alert "Start transcription to use Facilitator" / "Transcription is required to get help from Facilitator in this meeting." (320 × 138, #FAFAFA with a #F0F0F0 hairline, radius 8; the 16 px glyph 13 in; Dismiss and Start 143 × 32 at 93), then "What language is everyone speaking?" and the transcript (the recorder invited with mode RecordingAndTranscription). The Facilitator agent (`28:8e55a7b1-6766-4f0a-8610-ecacfe3d569a`) joins, posts "Hi everybody. I'll take notes and track the agenda…" with an "Add agenda" button (it prefills "@Facilitator Here's the agenda:"), and the Notes become Facilitator's (Agenda, Meeting notes, Follow-up tasks).
  - Turn off: the same POST with false, `removeParticipant` of the agent, and `PUT updateMeetingSettings` `{groupCopilotDetails: {enabled: false, liveNotesEnabled: false, speechEnabled: false}}`. Enable voice: `PUT updateMeetingSettings` `{groupCopilotDetails: {enabled: true, liveNotesEnabled: false, speechEnabled: true}}`.
  - The agenda timer did **not** appear: in 25 minutes with Facilitator on, topics typed into its notes' Agenda and an "@Facilitator Here's the agenda: …" message (unanswered), the meeting's `agendaTimer` stayed `Cancelled` with no sections and no pending consent (read from Teams' own state), so Teams' switcher stayed hidden (`showSwitcher` false; it needs two live timers, or Teams' `enableAgendaUbar`, which this tenant's ECS doesn't set). More ▸ Timer had no Ad-hoc / Agenda chevron.
- **Agenda topics' widths and labels** (Teams 26304 on winpc, 2026-11-22, "OST TEST 247 agenda": the Facilitator's 2 / 2 / 1 min topics and Open discussion 23 min, meeting window 1280 and 1024 wide): each topic has a slot by its length (10 apart); a topic whose slot is narrower than its padding (26 left, 11 right while the time is hidden, so 37; read-only 27 + 11) is drawn at that width centred on its slot, over the gaps beside it, and the others keep their slots: 1280 with the chat open 56.1 / 56.1 / 37 / 645.4 (gaps 10.1, 5.5, 5.5); without it 81.8 / 81.8 / 40.9 / 941.1 (all by length); 1024 with the chat open 37.8 / 37.8 / 37 / 435.1 (gaps 10.1, 0.9, 1.0). The time shows from 80 px (90 / 100 / 110 for longer or negative times); its padding is 40 / 44 when shown. The title (12/600, centred) is cut by CSS text-overflow: ellipsis: "B…" / "P…" in 19.1 and 15.8 px; the first letter is never cut off for the "…": where not even it and "…" fit, Chrome draws both from the start and clips them ("B…" just cut in 15.8 px, the left of the "V" in 3.9 px, nothing in 0 px). OST draws the same (AgendaTimerRow `slotX`, `widthOf`, `shortLabel`; TASK-0247).
- Verified live both ways with Teams on winpc: start, pause, resume, +1 min, cancel (the canceller keeps the strip), a new 1:30 timer, Teams' own resume and pause, a 10 s timer running out on both.

### 1.8i Call health (More ▸ Settings ▸ Call health; call-health-panel bundle, measured on winpc, 2026-11-09)

- **Menu item.** `CallHealth` in Settings ▸ group 1, in every call (meetings: `enableCallHealthForMeetings`, live true). Pulse glyph; the label toggles: "Call health" / "Hide call health" while the pane is open. It toggles the right-side pane.
- **Root page.** Header "Call health" (16/22 bold) and a close button ("Close call health pane"). Below it:
  - "Your call is receiving data. Most metrics refresh every 15 seconds." and a "Learn more" link (12/16).
  - "Last updated at: h:mm:ss AM".
  - Four cards (#F0F0F0, 313.33 wide, title 14/20 semibold, rows "Label: value" 14/20 every 23 px), each followed by a "View more … data" card with a chevron:
    - Network: round trip time and received packet loss.
    - Audio: sent bitrate and received jitter.
    - Video: sent and received bitrate, sent frame rate, resolution, codec, and video processing.
    - Screen Sharing: the same for sending, plus the received ones.
  - A card whose sending media is off shows an ⓘ after its title: "Turn on your microphone to get metrics", "Turn on your camera to get metrics" or "Start screensharing to get metrics".
- **Detail pages.** A back button ("Go back to call health root panel") and the category title, then one tile per metric (#F0F0F0, 73.33 high, 2 px apart). Each tile has the label (12/16 semibold) with an ⓘ, and the value below it (16/22). The ⓘ's tooltip is the metric's help text, or its "turn on" text while the metric is disabled.
- **Values.** The values are pre-formatted strings, for example "29.00 ms", "0.00%", "40 Kbps", "1.25 Mbps", "30.00 fps", "1280 x 720 px", "742 packets" and "H264 sw". A metric shows "--" when it is empty or its media is off. There are no colours, warnings or badges.
- **Refresh.** Values refresh every 15 s, and at once when your mic, camera or screen share turns on or off.
  - Each refresh reads a 15-sample, 1 s window:
    - bitrates and frame rates are averages of deltas;
    - packet counts are the window's difference;
    - sizes and loss are the last value;
    - RTT and jitter are running means.
  - RTT comes from RTCP report blocks: now − LSR − DLSR.
- **OST.** The `CallHealthPane` QML pane gets its values from `calling::call_health`:
  - the media path counts every stream it sends and receives (audio, video, share);
  - `Sampler` turns the counts into Teams' strings;
  - the receive limit is the MCP bandwidth estimate.
  - The send limit is OST's send-side estimate (TASK-0074, src/calling/send_bwe.rs): every RTP packet OST sends in a meeting carries the transport-wide sequence number (extension 3), the media processor answers with transport-wide feedback (RTCP 205/15), and a GCC-style estimator (delay trend with an adaptive threshold, loss, AIMD from 600 kbps) gives the rate; the camera and screen encoders take what it leaves after audio and overhead (×0.85), within the processor's own video limits. Measured live 2026-11-11: about 1.4 Mbps with 720p test video, the encoder following it up to the processor's 600 kbps cap.

### 1.8j Copilot in the meeting (MeetingCollabButton; measured on winpc, 2026-11-16, ost-test1 with a Microsoft 365 Copilot licence) — TASK-0188
- **The button.** `meeting-collab-button`, label "Copilot", tooltip "Open Copilot (Alt+C)" / "Close Copilot" ("Has context menu" for screen readers with the new controls). Glyph: Teams' CopilotIcon (48 viewBox), regular at rest, filled while the pane is open. Teams showed it in a scheduled meeting and in the Echo test call (a group call); with the new controls it sits after People in the secondary group. Shortcut Alt+C (`ToggleCopilotPane`).
  - Visible for a licensed user (`useAIFeatureLicense`: `enableMeetingCollab` and the licence's `isCopilot`); unlicensed users get no button (only the AI indicator, §1.8a). Disabled when the meeting's `copilotMode` is Disabled.
  - Which pane: `MeetingCollaboration.enableBizChatCopilotForMeeting` and the licence list give ost-test1 the **bizChat** variant — the Microsoft 365 Copilot app (`b5abf2ae-c16b-4310-8f8a-d3bcdb52f162`, the rail's Copilot) hosted as a TeamsJS side panel. (The other variant, "personalCopilot", is a native pane over AugLoop's `AugLoop_TeamsCopilotApp_TeamsCopilotMeetingSignal`; not given to this tenant.)
- **Transcript off.** Clicking Copilot first shows Teams' calling alert `ufd_copilotShowTranscriptUfd`: a 320 × 136.7 card (#FAFAFA, radius 8) centred 10.7 under the bar — the Copilot glyph (20) at 12.7, "Start transcription to use Copilot" (12 px) at 40.7, Close (16 px dismiss) at the end; "Transcription is required to get help from Copilot in the meeting." (14/20 #616161) at 40.7; Cancel and Start (143.3 × 31.3, Start primary) at 92.7. Start runs the spoken-language confirmation ("What language is everyone speaking?", Confirm), starts the transcript and opens the pane. **Measured live 2026-11-18** (Teams desktop on winpc, ost-test1 under a temporary policy with Copilot "Only during the meeting", a solo test meeting): with `copilotMode` "Enabled" and nothing running, Copilot asks nothing more: Teams goes straight to "What language is everyone speaking?" (Confirm), starts Copilot alone through the recorder (`{action: "start", mode: "transcription", processingModes: ["copilot"], actionParameters: {spokenLanguage, type: "start"}}`, the Skype token with the recorder token; nothing is kept after the meeting), opens the pane and shows the calling alert "Copilot is available in this meeting" (320 x 149.33 here, #FAFAFA, radius 8, 0.67 #F0F0F0 border; the 20 px Sparkle (#242424) and the title (12/20 #242424) 12.67 down, the title at 40.67; the text 14/20 #616161 at 12.67, 40.67, 294.67 wide, 8.67 under it; Close (16) at 291.33, 14.67; centred over the stage beside the pane, 10.67 under the bar): "Copilot uses your data to generate responses during the meeting and an Intelligent recap after the meeting. Interactions and summaries with Copilot might be retained due to the host organization’s policy. Privacy policy" (the tenant's privacy link, else go.microsoft.com/fwlink/p/?linkid=857875; without the meeting's Intelligent recap option the text leaves the recap out). The pane is told `isTranscriptRunningDuringMeeting: true`, `isTemporaryStorageForMeetingTranscript: true`. The "Turn on Copilot for everyone?" question in its code (copilot-ufd-control `Fn`, `M.Op`) only appears with the flag `enableToggleCopilotDuringMeeting`, which this tenant doesn't have. Calls ask "Turn on Copilot for everyone in this call?" (Just Copilot / Transcribe; read in the code, not seen live: the Echo test call can't be transcribed). In the Echo test call Copilot opens its pane at once, with no alert, in either mode.
- **The pane's width** is Teams' end slot (app-layout-area--end): 32rem under 947 px, 36rem to 1439, 42rem to 1679, 48rem to 1919, then 60rem; measured 360 at 1280 x 680. With the pane open the bar stays full width above it, and at 1280 both bars keep Copilot (classic: Chat, People, Raise, React, View, Controls, Notes, Rooms, Copilot, Apps, More; new controls: React, Chat, People, Copilot, Controls, More).
- **The pane** (app-layout-area--end, 320 wide, flush with the window): a 44 tall white header — Teams' coloured Copilot mark (20) at 24.7, 11.7; "Copilot" 14/600 at 49.7; Close Copilot (32 × 31.3, dismiss 20) 24 from the end; a hairline under it — over the app's frame (`cacheable-iframe:b5abf2ae…`, hwc-iframe). The app showed "Hi, how can I help?", "I'm here to help when you need me. Tell me what you're working on, and we can get started.", the prompts "Recap the meeting so far", "Create an agenda for this meeting", "Highlights from meeting chat", "AI-generated content may be incorrect" and "Message Copilot".
- **How Teams launches the app** (read in the frame and Teams' bundles, module 539064 `O`/`A`):
  - Teams desktop server-renders it (measured again 2026-11-18 with a CDP hook on both sides of the frame: the app then sends ChatReady `{renderMode: "SSR"}`; its whole conversation with the host is initialize, getContext ×2, the registerHandler calls, ChatReady, appInitialization.success, nestedAppAuth.execute, shortcutRelay.getHostShortcuts and focusEnter's registerHandler; the initialize answer's supports add `appPerformanceMetrics`, `copilot.eligibility` and `mouseRelay`, the context has `hostFeatures.serverSideRendering: true`; its first page reads "Hi, how can I help?", "I'm here to help when you need me. Tell me what you're working on, and we can get started." and the three prompts): a form POST to `https://m365copilotapp.svc.cloud.microsoft/chat?OID=<oid>@<tid>&hostApp=hub&isanonymous=true&culture=en-us&mysite=<tenant>-my.sharepoint.com&hostName=TeamsModern&hostClientType=desktop&sessionId=<app session>&renderingSurface=copilotSidePanel&theme=default&hostRing=<ring>&parentSessionId=<host session>` with `cv-id`, `Authorization` (a token for the app) and `hostContext` (clientPlatform, hostName, locale, theme, appSessionId, userClickTime, hostSessionId, subPageId); it redirects to `…/chat/sessionanchor/<copilotReferenceId>?…`. Without server rendering (Teams on the web, and OST) the same address is loaded as the frame.
  - getContext: `frameContext` "sidePanel", `renderingSurface` "copilotSidePanel", `userLicenseType` "Copilot", `isFullScreen` true, `entityId` "entity1-<uuid>", and `subEntityId` = `{"hostSettings":{"enableDeeplinks":"true","focusOnLoad":"Compose"},"launchOptionPayload":"<base64>"}`; the payload is `{"id":"","scenario":"Default","chatType":"","properties":{},"version":1,"referral":{"cmmid":"cmm35g04qbs"},"callerInfo":{"scope":"Meeting","entryPoint":"PrivateViewDuringMeeting","copilotReferenceId":<sha256 hex of the call id>},"serverVariants":[]}` (checked: the hash of the meeting's call id `58ff6acc-…` is the reference Teams sent).
  - The app registers custom handlers (contextualChatChanged, updatePromptInputData, updateDataContext, copilotSearchSidePaneVisibilityChanged, updateCapabilities, reloadConversation, edgeStopAction, onAppFirstForeground, onAppForeground) and sends **ChatReady** (`{renderMode}`); Teams' bizChat custom-message service answers `[]` and posts
    `contextualChatChanged [{contentType:"teams", contentItems:[{contextType:"Meeting", meetingContext:{context:"Meeting", callId, organizerId:"<oid>@<tid>", threadId, iCalUid, messageId:"0", sessionType:"PrivateViewDuringMeeting", groupId:"", vroomId:"", exchangeEventId:"", subject, isTranscriptRunningDuringMeeting, isTemporaryStorageForMeetingTranscript:false}, scenarioName:"TeamsMeetingSidepaneWorkCopilot"}]}]`
    and `updateCapabilities [[{name:"disableGPT5"},{name:"disableVoiceInput"}]]`; contextualChatChanged again when the transcript starts or stops.
  - The app then signs in over nested app auth (tokens for its own resources) and talks to Copilot itself; it reports QuerySubmit, onUserSubmittedQuery, firstTokenReceived and queryResponseReceived (custom messages Teams only logs).
- **A harmless prompt, measured:** "Recap the meeting so far" (the suggestion) answered from the meeting: "Key takeaways — OST calendar test: created from OST is still in progress, but there isn't enough spoken content available yet…", with follow-up suggestions.

**OST** (`api::meeting_copilot`, CallWindow's `copilotPane`/`copilotAsk`, `app_host.js` ChatReady): the Copilot button for licensed users (`composeCopilotJson.meeting`, from the licence details and `calling.enableMeetingCollab`), the transcription alert with Teams' text and layout, Start through Teams' language confirmation, the pane's header, and the app hosted with OST's TeamsJS host: the same address with Teams' `hostRing`, server-rendered as Teams desktop does (the app's token posted with its host context; `serverSideRendering` in the context; the extra runtime capabilities), context and launch payload, ChatReady answered and the meeting posted, again on transcript or Copilot changes; Turn on Copilot for everyone (`recorder::Command::StartCopilot`) and its notice. Alt+C. Harness `--join-copilot` (`--join-copilot-turn-on`, `--join-copilot-stop`).

### 1.8k Dial-in and phone audio (Audio Conferencing; measured in Teams on the web as ost-test1, 2026-11-16, a solo scheduled meeting "OST TEST 187 dial-in") — TASK-0187
- **Where the numbers come from.** The call's join response, `meetingDetails.pstnDetails`: `{bridgeId, userBridgeId, acpMcuInfo: {settings: {tollNumber: "18723339415", tollFreeNumber: null, participantPasscode: "975755048"}}, isStatic, dialinUrl: "https://dialin.teams.cloud.microsoft/<userBridgeId>?id=975755048", meetingInvitePhoneNumbers: []}`. The conversation-only join Teams makes first (`POST /api/v2/epconv` without a call) has `pstnDetails: null`; Teams' pre-join reads them from the call it joins *preheated* while the pre-join window shows (`endpointProperties.preheatProperties: 1`, made visible by Join now).
- **Whether phone audio is offered** (Teams' PSTN state provider): `meetingCapability.allowPstnConferencing` (true here), `pstnConferencingDialOutType` not "Disabled" ("InternationalAndDomestic" here), dial-in details present, not anonymous (unless `allowAnonymousUsersToDialOut`), not end-to-end encrypted. Dial-in = `allowPstnConferencing`; Call me = the dial-out type.
- **The pre-join's preheat** (TASK-0215; Teams on the web as ost-test1 in OST's web profile, 2026-11-16, its signalling captured and its calling code read; meetings made by OST through Graph, by Teams' Calendar ▸ Meet now, organized by OST Test 2 with a lobby, and one OST Test 2 was already in):
  - As the pre-join window opens Teams joins the meeting's conversation (`POST epconv` without a call) and at once its call, **preheated**: the call request to the conversation it answers with, as for a join, with `endpointState.endpointProperties.preheatProperties: 1`, `callModalities: ["Audio", "ScreenViewer"]`, your mic muted and the speaker off (Teams' `PreheatFlags.IsPreheatOnly`: audio both ways, video and sharing receive-only), `mediaDescriptions` all `recvonly`. The media is set up as for a join (the processor's acceptance has `acceptedCallModalities: []`, as in a lobby), so the meeting's details arrive as for a join (`pstnDetails`, `invitation`, the capability; with someone in the meeting the conversation join already has them).
  - Nobody sees a preheated endpoint: the roster leaves it out (`participantCounts.preheatedParticipants` stays 0; OST Test 2, in the meeting, got no roster change), the meeting's lobby doesn't list it; held in a lobby only you see yourself there (`endpoints.<you>.lobby: {}` in your own roster). The pre-join shows "1 other joined" from that roster.
  - **Join now** on a preheated call (`joinPreheatedCall`): `POST links.updateEndpointState` `{from, endpointState: {endpointStateSequenceNumber: 1, endpointProperties: {preheatProperties: 0}}}` (plus `state: {isMuted: true}` joining with the mic off), then `PUT links.updateEndpointMetadata` `{participants: {from}, endpointMetadata: {holographicCapabilities: 3}}`; Teams then unmutes its mic and speaker locally. Nothing is renegotiated. The roster then lists you; in a lobby meeting you're now in its lobby ("Hi, OST. Someone will let you in when the meeting starts.") and admission goes on as for any join.
  - **Cancel** (and Escape): `POST links.leave` `{participants: {from}, conversationTransactionEnd: {reason: "noError", code: 0, phrase: "ConversationEndNoModalityConnected"}, callTransactionEnd: {code: 0, subCode: 0, phrase: "CallEndReasonLocalUserInitiated", resultCategories: ["Success"]}}`; the call's `call/end` follows. Nothing else is left (the Meet now made from the Calendar left no event).
  - **A minute** after the call is preheated (ECS `preheatedCallTimeoutInMs` 60000) Teams leaves it the same way; Join now then joins afresh (conversation, then call). One preheated call at a time (a new pre-join leaves the last).
  - **Phone audio** (`pstnStateProvider`, from the call's latest `meetingDetails`): undecided ("Checking for dial-in info…") until the capability is there with a dial-out type other than "Disabled" or `allowPstnConferencing` not false, **and** `meetingDetails.invitation`; then offered exactly when the PSTN state above is (`allowPstnConferencing`, the dial-out type, `pstnDetails`, not anonymous, not E2EE). Undecided after 15 s (`pstnCapabilitiesTimeoutInMs`): offered if `allowPstnConferencing` (Teams' `getPstnDialCapabilities().isDialInEnabled`). Measured: an OST-made meeting and a Teams Meet now offered it about 2 s after the window opened (the conversation join has `allowPstnConferencing: false` and no invitation; the preheated call's details settle it); held in OST Test 2's lobby the details never had an invitation or dial-in, and 15 s later the fallback offered it. The meeting's invitation in your calendar plays no part.
  - **Teams desktop** (winpc, MSTeams 26304.1201, 2026-11-17; TASK-0219). Its calling stack is native (SlimCore), so its requests aren't visible over CDP; what decides the preheat is Teams' JS (preheatService `startPreheatingMW`, calling-electron passes `preheatFlags` to SlimCore), and its settings and behaviour were measured:
    - Enabled when `enableCallPreHeatDesktop` (true), SlimCore ≥ `callPreHeatDesktopMinSlimcoreVersion` ("2023.28.01.2") and SlimCore's own ECS `enablePreheat` (true in winpc's `sc-tfw/slimcore-ecs-cache.data`); never anonymous. ost-test1's ECS (the reply OST asks for exactly as Teams desktop does) overrides only `joinOngoingMeetingInPreheatedFlow: true` and `isStreamingAttendeesPreheatDisabled: true` (town hall attendees aren't preheated); `enablePreheatWhileCallIsActive` stays true, `preheatedCallTimeoutInMs` 60000. Teams' preheat options: audio both ways, video and sharing receive-only, `PreheatFlags.IsPreheatOnly`, no video.
    - A scheduled meeting's pre-join: Phone audio offered at once (≤ 1.2 s; "OST TEST 187 dial-in").
    - **In a call** (Teams desktop in a meeting, a second meeting's pre-join opened from its chat's Join): preheated too, Phone audio disabled as the window opened and offered 1.2 s later (`enablePreheatWhileCallIsActive`; only the "another active call" check stands in its way, and it is on). Cancel left it; the first meeting went on.
    - **Channel Meet now** (OST Test Team ▸ General ▸ Meet ▸ Meet now): not preheated — there is no meeting until Start (Join now) creates it: no channel post appeared, and Phone audio stayed disabled for over a minute (not even the 15 s fallback, which needs the preheated call's capability). Calendar Meet now (not a channel) waits for the scheduling service's meeting and then preheats it (`schedulingServiceEventPromise`).
    - The dial plan: `enableDialPlans` (Teams' `isDialPlansEnabled`, Call me's normalization) true, not overridden for ost-test1.
    - **`joinOngoingMeetingInPreheatedFlow`** (ECS `meetingJoin`, default false; true for ost-test1; TASK-0222, read from Teams' bundles and watched with CDP logpoints in Teams desktop's own preheatService on winpc, 2026-11-17): with it on, `startPreheating` first asks the active calls service for a call already going on in the meeting (`getExistingCallInfo`: for a meeting link the chat's active call, `getCallsByConversationId(thread)[0]`; for Join with an ID the call with that meeting code, unless `disableAwarenessForJoinByCode`) and, when there is one, preheats by **joining that call where it is** (`joinExistingCall` → `call.join({conversationUrl, conversationId})`, the meeting chat's `awareness_conversationLiveState` entry: its `conversationUrl`, `conversationId` and `meetingData`), as Teams' join of an ongoing meeting without a pre-join does (`joinMeetingFromIntent`). Otherwise (and always with the flag off) it starts the call (`call.start`: the conversation first, then the call to it). The active calls service only knows chats you're a member of whose thread names a live state it has loaded; in the winpc run Teams desktop took the flag's branch (`flag-on branch` logged) but found no active call for meeting3 (ost-test1 had left that meeting's chat), so it started the call. Re-checked 2026-11-18 after OST Test 2 re-added ost-test1 to meeting3's chat (`examples/chat_members`) and with OST Test 3 holding a call in meeting1: Teams' active calls still had only expired entries for both chats (the previous calls' `expiration`), so the branch again found no call (meeting1's pre-join wasn't preheated at all: `startPreheatingMW` ran but its observed call never reached `startPreheating`); Teams desktop's local chat copies don't take a new live state promptly, so the joining branch wasn't seen end to end. **Seen end to end 2026-11-18** after restarting Teams desktop (new Teams, CDP on 9222 again), which reloads its chats and their live state: with OST Test 2 in meeting3, the pre-join's preheat took the branch with `existing: true` and called `joinExistingCall` with `callUrl` = the running call's own conversation (`…/conv/zkU0y2ykEUSykw…`, the URL in OST Test 2's log) and `callId` = the live state's `conversationId` (cb53c170…). So a running Teams desktop doesn't refresh a chat's live state after you're re-added to it (`activeCallsService` updates only from the local chat copy, `updateConversationCallInfo`, and only for chats you're a member of); a restart does. OST posts its preheat to that same URL with that id as its chain id. Teams on the web (flag off there) preheated an ongoing meeting with the conversation join and then the call (captured in OST's web profile).
  - **The preheated call request**, as Teams sends it (captured on the web, 2026-11-16): `callInvitation.callModalities ["Audio", "ScreenViewer"]`, `mediaContent.mediaDescriptions {descriptions: [{mid, direction: "recvonly"} for every m-line], requestId: 1}`, `clientTransferContext`, `customContext`, `emergencyContent`, `locationContent`, `networkContent`, `areaContent` null, `voicemailSettings {}`, `contentSharing: null`, and `participantPropertyBag.aiVoiceConsent {value: {aiVoiceConsentValue: "0"}, sequenceNumber: 0}` (every meeting call carries the bag; the value is the AI interpreter voice consent from policy and preference). Its acceptance is acknowledged **only in the Trouter reply** (`callAcceptanceAcknowledgement.links` with the call's own callback base: mediaRenegotiation, transfer, replacement, balanceUpdate, retargetCompletion, controlVideoStreaming, updateMediaDescriptions); nothing is `POST`ed to the acknowledgement link, for preheated and ordinary meeting joins alike.
- **The invitation** (Exchange/Teams' meeting block in the event body, and `meetingDetails.invitation`): "Dial in by phone", "+1 872-333-9415,,975755048# United States, Chicago" (a `tel:` link), "Find a local number" (the `dialinUrl`), "Phone conference ID: 975 755 048#", "For organizers: Meeting options | Reset dial-in PIN". Teams' calendar peek card shows none of it (only Join ▾: Join Teams meeting, Copy join link).
- **Pre-join "Phone audio"**: enabled once the PSTN state is known ("Checking for dial-in info…" before; disabled with "You don't have access to dial-in information for this meeting"). Selected: its header grows to fill the column (448.8 × 89.8, white, 1 px #E0E0E0, top radius 4) over a #FAFAFA panel (448.8 × 89.3, bottom radius 4, padding 16 18) reading "We'll give you a number to call after you join, or we can call you." (14/20 #616161). Other choices 44.8 tall, 6 apart. The choice is cached (Room / None aren't).
- **Joining with Phone audio**: no computer audio (Camera and Mic greyed), and "Use phone for audio" opens by itself:
  - Overlay rgba(37, 36, 36, 0.75); the card 400 wide, centred, radius 8, shadow 64 (0 0 8 0.12 + 0 32 64 0.14), padding 27 32 32.
  - Title 18/25.7 bold #242424; Close 32 × 32 (14 px dismiss) 24 from the right, 3 above the title.
  - Call me view (263.7 tall): "Enter your number and we'll call you." 12/16 at +35.7; the box (336 × 32, #F5F5F5, radius 4, text 12 in, placeholder "Enter phone number", focused) at +73.7; "Call me" (primary 336 × 32; #F0F0F0 / #BDBDBD while disabled) 20 below; "Dial in manually" (transparent, 14/600 #424242, underlined, padding 5 0) 15 below.
  - Call me is enabled while the dial plan takes the text: Teams' normalizer (format characters out, the first `dialPlanPolicy.normalizationRules` match, else the country code before plain digits) or libphonenumber's possible number. With ost-test1's plan (effective policy `tenantDialPlan`): "12" yes, "abc" no, "5550100" yes, "+999 1234" no, "425 555 0100 x12" yes. Leaving the box formats it: "4255550100" → "+1 425-555-0100", "5550100" → "+1 5550100", "0000000000" → "+10000000000", "+44 20 7946 0000" as typed.
  - Dial in view (234.7 tall): "Dial in with one of the following phone numbers.", "+18723339415" (a `tel:` link, #4F52B2, underlined on hover) " (Toll)", "Get local numbers", "Conference ID: 975 755 048 #", then "Call me back".
  - Calling: "We are calling your phone" with the number and "Calling..."; connected: "Meeting audio" with the number and Disconnect (removes the phone from the meeting); Teams then mutes the computer's mic and speaker. Failure messages: "We could not complete the call. The user is unavailable at the moment." (default), "Call not allowed in this location." (subCode 10500–10549), "You are not allowed to dial-out to this destination. Please contact your administrator." (EntitlementFailure, or 403 with subCode 510566–510569). Without phone audio: "Phone audio isn't available" / "Unmute your mic for meeting audio.".
  - Favourites: up to ten numbers Teams called before (kept locally) and your work and mobile numbers, under "Favorites".
- **Call me (protocol, from Teams' web calling stack)**: `POST links.addParticipantAndModality` with `{participants: {from: <you>, to: [{id: "4:+14255550100", assertedId: <your participant id>}]}, participantInvitationData: {}, groupContext: null, groupChat: {threadId, messageId}, links: {addParticipantSuccess, addParticipantFailure}}`; the answer comes back on those callbacks within 120 s.
- **More**: … Settings ▸ | **Call me** (PstnButton, the Call glyph), Report a concern, Help; with the new controls Join info ▸ Meeting info, Call me, Call health. Shown with dial-in and phone audio; disabled while not connected.
- **Meeting info**: 30 under the location the dial-in block — the 20 px dial pad glyph, then 30 in "Dial in manually", "+18723339415 (Toll)", "Get local numbers", "Conference ID: 975 755 048 #" (14/20, links #4F52B2), then Copy join info 30 below, then the invitation (with its own dial-in block).

**OST** (`calling::phone_audio`, `PhoneAudioDialog.qml`, `MeetingInfoPane`, `PreJoin`'s Phone audio): the dial-in details and PSTN state from the join response (and conversation updates), the dial plan from the effective policy `tenantDialPlan`, Call me as above, the dialog in all its views, More ▸ Call me and Join info ▸ Call me, Meeting info's block, and the pre-join option. OST joins meetings as Teams does, the conversation first (`POST epconv` without a call) and then the call to the conversation it answers with (joined in one request, the meeting's details came without `pstnDetails`). Its pre-join preheats as Teams' does (`outgoing::preheat_meeting`, `Backend::check_prejoin_phone`'s `preheat_for_prejoin`): the meeting's call joined hidden with its media held, its events kept from the call window, Phone audio decided by `phone_audio::prejoin_pstn` from the latest details or after 15 s by `prejoin_fallback`; Join now (`join_meeting_from_prejoin`) makes the preheated call visible (`OutgoingCall::join_preheated`) and it becomes the meeting's call (lobby and admission as for any join); Cancel, Escape or closing the window leaves it (`cancel_prejoin`, `OutgoingCall::leave`), and so does the minute's timeout (Join now then joins afresh). The preheated call request carries Teams' fields above (`signaling::create_call_with`: Audio and ScreenViewer, recvonly media descriptions from the offer's mids, the property bag), and OST's Trouter reply to its acceptance carries the acknowledgement links with the call's own tag (`trouter::sync_reply_body`); meeting joins no longer `POST` the acknowledgement. With Teams' `joinOngoingMeetingInPreheatedFlow` on (OST reads it from ECS, `outgoing::preheat_joins_ongoing`), a meeting whose call is going on (the chat's live state, `api::thread_live_call`) is preheated by posting the preheated call straight to that call's `conversationUrl` with its `meetingData` (`groupChat: null`, no conversation join first; TASK-0222). Join now or Cancel while the preheat is still being placed withdraws it and leaves an answer that still comes (it used to be dropped mid-request, leaving a preheated endpoint of ours in the meeting: `preheatedParticipants` stayed 1). A pre-join opened while OST is in a call preheats too (closing it leaves the preheated call); a channel Meet now pre-join isn't preheated (Phone audio unavailable), as in Teams desktop. Harnesses `--phone-audio-test` (`--phone-audio-invalid-call`, `--phone-audio-facilitator`) and `--preheat-test` (`--preheat-cancel`, `--preheat-join`, `--preheat-expire`, `--preheat-host[-admit]`, `--preheat-in-call=<link>`).

### 1.8l Moving into a breakout room and back (captured from Teams on the web as ost-test1 in OST Test 2's meeting, 2026-11-17) — TASK-0216
- **Same two steps as any join.** Teams moves with a calling intent built from the room's `meetingJoinUrl` with `bypassPrejoin` (breakoutRoomParticipantsService `moveToMeetingByJoinUrl` → `moveToMeetingByIntent` → `startOrJoinCallFromIntent`; Join room on the bar, the organizer's Join on a room's menu with `keepSourceCallOnHold`, and the way back all go there). On the wire: `POST epconv` without a call for the room (`groupChat {threadId: <room thread>, messageId: "0"}`, `meetingInfo` the main organizer's), then 1.8 s later the call `POST`ed to the conversation it answers with, carrying `meetingData {meetingCode, passcode}` (the room's) besides `meetingInfo`.
- **The main meeting.** Once the room's call is accepted, a participant leaves the main meeting's conversation (`…/leave`) and at once joins it again without a call (`POST` to the main conversation's URL, a new participant id), so its updates keep coming while in the room. Going back (Return, or the room closing) posts the call straight to that conversation (`groupChat: null`, the main meeting's `meetingData`), then leaves the room.
- **A room you can't join.** Joining a room that was never opened (checked live with OST as organizer, 2026-11-17): the conversation join and the call request both succeed, then the conversation ends with 403 / sub-code 5745 ("Conversation ending after breakout room is not open.") and the room's call acceptance still arrives about a second later. A closed room can still be joined until the service ends it; after that the call request itself answers HTTP 403. Teams shows its retry screen `NotAllowedToJoinBreakoutRoom`: "You don't have access to this room" / "The room isn't open yet, or you might have been assigned to a different one." (no Rejoin). A room call that never connected doesn't take you back to the main meeting by itself; an organizer's held main meeting stays held with Resume.

- **Where `meetingData` comes from** (TASK-0218, from the same capture): the conversation-only join's `conversation/conversationUpdate` (Trouter, ~1.3 s after the `POST epconv`) carries top-level `meetingData {meetingCode, passcode}`; Teams' signalling keeps it (`e.meetingData && (this.meetingData = e.meetingData)`) and sends it with the call. The thread's `awareness_conversationLiveState` names it too while a call is going on. The preheated pre-join's call (0.8 s after its conversation join) went before that update and carried none.
- **The retry screen for a refused room** (Teams' bundles, components-calling-retry-screen and the calling state props): `NotAllowedToJoinBreakoutRoom` when the call ends with 403 / 5745 — no icon, the title and description above, and no retry button (`isRejoinable` is false: `checkBreakoutRoomsConditions`), so Dismiss only; it is shown in the room's own window.
- **The invite when people aren't moved automatically** (calling alert `ufd_BreakoutRoomInvite`, measured in Teams desktop on winpc 2026-11-18, the call window 1280 x 680): when your room opens, Teams shows a 320 x 116.67 card centred over the stage 8 below its top (10.67 under the bar): #FAFAFA (NeutralBackground2), 0.67 #F0F0F0 border, radius 8, shadow (0 0.6 1.8 0.11, 0 3.2 7.2 0.13), no Dismiss. "Join breakout room?" 12/20 regular #242424 at 12 in; "You've been assigned to "Room 1"." 14/20 #616161 8 below (296.67 wide); then Later (white, 0.67 #D1D1D1) and Join room (#5B5FC7, white text), 143.33 x 31.33, 8 apart, 14/20 semibold, radius 4, 12 from the bottom. It stays until answered (still up after 2.5 minutes); Later closes it and "Join room" stays on the bar; Join room moves you in.
- **Joining after the rooms opened** (TASK-0222; Teams desktop as ost-test1 on winpc, assigned to Room 1 before it joined OST Test 2's meeting3, Room 1 open; CDP logpoints in breakoutRoomParticipantCallChangeHandler, 2026-11-17): the join already carries `meetingDetails.breakoutDetails.mainMeetingProperties.assignedBreakoutRooms` (OST's join response has it too). When the main meeting's call connects Teams subscribes to it and takes the room assigned at that moment as where it starts from (`resetPrevAssignedRoom`); a change only counts against it (`prev → next`: closed → open or none → open = into the room, open → closed or gone = back to the main meeting, open A → open B = between rooms, else nothing). So a late joiner whose room is open already is **not moved and gets no alert or dialog**: "Join room" stands on the bar (Calling controls, before Leave), and pressing it moves them in (`GoToAssignedBreakoutRoom`). A room assigned or opened after they joined moves them as anyone else (the logged change was `breakoutRoomInviteFromMainMeeting`).
- **Going back into a main meeting with a lobby** (TASK-0222 follow-up; Teams desktop on winpc, meeting3 with its lobby OrganizerOnly, Leave room from Room 1, 2026-11-18): the main meeting's new call lands in its lobby (`CallState.InLobby`) and Teams **stays in the room** — the room's call Connected, its window still "Room 1", no lobby screen — until the organizer lets it in (about 4 minutes in the run); then the main meeting's call connects, the room is left and the window shows the main meeting. Teams leaves the room only once the target call is Connected (`finalizeTransitionBetweenMeetings`), and a lobby call isn't.
- **A participant refused by a room** (same run: Teams' own move into a room of its choice, `moveToNewMeeting`, aimed at an unopened Room 2): the room's call ended with 403 / 5745 ("ConversationEstablishmentFailed"); Teams tried once more (`retryMoveAfterTargetDisconnect`, ECS `enableRetryMoveOnTargetCallDisconnect` true), which failed too, and then **showed nothing**: the participant stayed in the main meeting, connected (never on hold: Teams desktop moves within the same window, `enableMoveWithinSameWindow`, and leaves the main meeting only once the room connects), its window unchanged — no retry screen, no alert, no toast. The retry screen above is for a room joined over a held main meeting (an organizer's Join).

**OST** (`outgoing::join_meeting_with`, `outgoing::KeptConversation`, `backend::move_meeting` / `join_room_holding_main` / `leave_and_keep_main`): rooms and the way back are joined in Teams' two steps, and a move (or an organizer's Join over the held main meeting) waits up to 2 s after the conversation join for its `meetingData` (`signaling::meeting_data_of` on the tagged conversation update), which the call then carries. A participant whose room answered leaves the main meeting (`POST links.leave`) and joins its conversation again without a call (`signaling::join_conversation_without_call`, a new participant id and callback tag), keeping it while in the room (its updates noted, its end dropping it); going back posts the call straight to that conversation (`groupChat: null`, its `meetingData`, the kept participant id), then leaves the room; a kept conversation nothing goes back to is left 30 s after the call ends. A room that refuses an organizer's Join over the held main meeting (403 / 5745) turns the call window into the retry screen above (`RetryScreen` reason `notAllowedToJoinBreakoutRoom`, Dismiss only) while the main meeting stays on hold in its own "On hold" window with Resume; another failed Join resumes the held main meeting with "Couldn't join the meeting" in an alert. A participant's move that fails (a refusing room or anything else) is tried once more, as Teams does, and then the participant just stays in the meeting they came from, its view and breakout state back, with nothing shown (TASK-0222). The room assigned when the main meeting's call connects (from the join response's `breakoutDetails`, `breakout::assigned_rooms_at_join`) is where OST starts from, with Teams' change rule (Main.qml `breakoutChange`): a late joiner whose room is open gets "Join room" on the bar and no move or alert. Going back into a main meeting whose lobby holds us, OST stays in the room (its call, view and breakout state) until the main meeting lets it in, then leaves the room (`CallSlot::lobby_return`; Leave leaves that lobby too; if the room ends first, the lobby is shown). Each join has its own callback tag: whatever a failed join still sends (its end, a late acceptance, which is hung up at once) can't end or change the meeting you're in; a call request that fails after the conversation join leaves that conversation. Harness: `--breakout-test --breakout-join --breakout-join-unopened` (organizer; rooms an earlier run left are removed first; on the refused room it logs the retry screen and the held window, then Dismisses and Resumes), `--breakout-watch --breakout-watch-rejoin` (participant; `--breakout-watch-join` presses Join room once a room is assigned and open; a refused room is Dismissed and Resumed after a few seconds), `--breakout-manual`, `--breakout-wait=<s>`. Verified live 2026-11-17 (OST Test 2 organizing in OST, ost-test1 in OST as participant): both room calls carried the room's `meetingData`, the participant kept the main conversation and went back through it (with the main meeting's `meetingData`), the organizer stayed alone in the main meeting meanwhile, and the organizer's Join on an unopened room showed the retry screen over its held main meeting.

### 1.8m Encryption indicator and end-to-end encrypted calls (measured on winpc and in Teams' bundles, 2026-11-17) — TASK-0146
- **The indicator** (E2EEncryptionIndicator, `id e2ee-status`, first in the `indicators` slot and kept on hold): in 1:1 calls and meetings alike, a 30 × 32 button at x 8 with the 20 px Shield (Teams' ShieldRegular; ShieldKeyhole while the call is end-to-end encrypted, measured), then the timer (`call-duration-custom` at 38). Tooltip "Encryption status". Measured in a 1:1 call from Teams desktop to OST Test 2 (new meeting controls on): shield at (8, 46), timer 00:25 at (38, 46).
- **Its card** (a Fluent popover, `data-tid e2ee-status-mtr-dialog`, `role dialog`): 280.3 wide, 13.3 under the button, start-aligned to it, white, radius 4, padding 12, shadow `drop-shadow(0 0 2px rgba(0,0,0,.12)) drop-shadow(0 8px 16px rgba(0,0,0,.14))`. Not end-to-end encrypted: "This call is secured by Teams data encryption." (meetings: "This meeting is secured by Teams data encryption.") in 12/16 #616161, then "Learn more" (#4F52B2, `https://go.microsoft.com/fwlink/?linkid=2174896`, aria "Learn more about Teams data encryption"). End-to-end encrypted (Teams' M8, from the bundle): the title "End-to-end encryption enabled for this call" (meetings "…for this meeting"), "Verify your call's encryption by making sure the numbers below are the same for both of you." (meetings "This meeting is end-to-end encrypted if the numbers below are the same for all participants."), Learn more to `e2eeCallingLearnMoreLink` (2174740), the numbers on a band (aria "End-to-end encryption numbers"), and in meetings "Updated {{n}} minutes ago".
- **The numbers** come from the calling stack's `e2eEncryptionStatusChanged {enabled, fingerprintsJson, errorMessage}` (`fingerprintsJson` = `{fingerprintHash: [bytes], timestamp}`): the bytes as hex, cut into 8-hex chunks, each `parseInt(chunk, 16) % 100000` zero-padded to 5 digits, all joined and cut into 4-digit groups. A call that drops from E2EE to non-E2EE is left ("E2EE becomes NonE2EE").
- **The setting** (Settings ▸ Privacy, card `e2ee-settings`, Call icon): "End-to-end encrypted calls" / "One-on-one Teams calls are end-to-end encrypted if both participants turn on this setting. Some features won't be available, including recording and transcription. Learn more" (2174740), switch `toggle-e2ee-setting`, between "Identify me in attendance reports" and "Optional connected experiences". GraphQL `isE2EECallEnabled, isE2EESettingEnabledByTenantAdmin` / `toggleE2EECall(enable)`; the switch is disabled unless the tenant allows it. Kept in the middle tier (`e2eeReadSettingFromBVD` on): `GET {mt}/beta/usersettings/useEndToEndEncryption` answers a bare `false`/`true`, `PUT` the same address with `{useEndToEndEncryption}`. Allowed = the effective `teamsEnhancedEncryptionPolicy.callingEndtoEndEncryptionEnabledType` ≠ "Disabled" (Teams' default).
- **This tenant** (Teams PowerShell, 2026-11-17): Global `CallingEndtoEndEncryptionEnabledType` Disabled (so the switch was greyed); the built-in `Tag:UserControlled` (DisabledUserOverride) was granted to ost-test1 and ost-test2 only. The effective policy changed at once; Teams on winpc still showed the switch greyed after two restarts and two hours (it caches policies in IndexedDB `Teams:policies-manager…` store `policies` and refreshes every 2–4 h: `policyRefreshIntervalInMs` 72e5, `policiesSyncStrategyRefreshIntervalInMs` 144e5); deleting that cached record and restarting Teams brought the switch up enabled at once. Teams' Privacy switch then wrote `true` to the same middle-tier setting OST reads.
- **What is hidden in an E2EE call**: every control the presets mark `isE2EEHidden` — RecordingButton, TranscriptButton, TranscriptPanelButton, RecordingIndicator, LocalRecordingButton, CallTransferButton(V2), CallConsultativeTransferButton(V2), CallParkButton, MergeCallsButton, MeetingCollabButton, CopilotIndicator, MeetingAppsAddButton, MeetingNotesButton, MeetingDetailsButton, LiveInterpretationButton, StartBreakoutRoomButton, LargeGridButton, ImmersiveViewModeButton and the app tabs; also `isTransferAllowed` / `isCallParkAvailable` are false with `encryptionDetails.e2eeEnabled`, roster adds are refused ("New participants can’t be added to an end-to-end encrypted call."), phone audio isn't offered.
- **The 1:1 negotiation (captured 2026-11-17, Teams desktop calling OST Test 2 with both settings on).** The only change in Teams' call is one session-level SDP line, `a=x-e2ee`, before `a=group:BUNDLE`; its offer still carries SDES `a=crypto` lines and `a=fingerprint`. When the answer also carries `a=x-e2ee` and the media is keyed by the DTLS handshake (OST answers DTLS-SRTP, `a=setup:active`), Teams shows "End-to-end encryption enabled for this call" with five 4-digit groups (e.g. 8180 4703 2537 6632 5599: a 16-byte hash), the ShieldKeyhole indicator, and drops Transfer, Consult, Copilot and More's Record, Transcribe, Interpreter, Captions, RTT and Get more apps (More kept View, Join info, Settings). Without `a=x-e2ee` in the answer the same call is "secured by Teams data encryption".
- **The numbers** are Teams' DTLS security code, recovered in full (2026-11-17) and checked against two live calls. Native half (Ghidra on `RtmMediaManager.dll`, `MSRTC/src/mediamgr/src/security_code_utils.cpp`): SlimCore's `MMConf::GetDtlsFingerprintHash` forwards to `CMediaCallImpl::GetDtlsFingerprintHash` → `FUN_180068cc0`, which requires both raw DTLS fingerprints (32-byte SHA-256 of each DER certificate) to be 32 bytes, sorts them by byte value, takes `SHA-512(low || high)` (`HashSortedFingerprints`), runs `spl::pbkdf2Hmac(digest, salt = "", iterations = 16384, SHA-512, dkLen = 64)` (skypert → `BCryptDeriveKeyPBKDF2`) and returns the **last 16 bytes**. Web half (the e2ee status popup's formatter, found in Teams desktop's WebView2 Service Worker cache on winpc): hex-encode the 16 bytes, split into 8-hex-digit chunks, `parseInt(chunk, 16) % 100000` zero-padded to 5, join (20 digits), split into 4-digit groups. Both captured calls reproduce exactly (4507 0411 8497 0193 3733; 6167 3878 8004 3470 2825). The input is only the two certificates, so no extra key exchange is involved; the signalling carries just `a=x-e2ee`. OST: `calling::e2ee::security_numbers` (openssl SHA-512 + PBKDF2), computed from the DTLS session after the handshake (`WebRtcAudioSession::e2ee_numbers`, empty unless the call is E2EE), shown in the encryption card (`call_e2ee_numbers`). **Live (2026-11-17, Teams desktop on winpc calling OST Test 2, both E2EE switches on):** a third call's fingerprints give 6026 9984 5420 4912 2598, as Teams showed, and in the next call OST's card and Teams' popup both showed 9323 6013 6055 6756 4498. Teams' popup (280.3 x 217.3, padding 12, radius 4): a 10 px column; title 14/20 semibold #242424 with 16 px bottom padding; description 12/20 #616161 with Learn more; the numbers 14/20 #242424, 16 px further down on a #FAFAFA band (radius 4, padding 10, 40 tall), spread edge to edge. OST's card matches (280.33 x 216). The backend properties `call_e2ee` / `call_e2ee_numbers` reach QML as `callE2Ee` / `callE2EeNumbers` (cxx-qt capitalises after the digit); the card's binding used `callE2ee`, so until this fix OST never showed a call as end-to-end encrypted.
- **How the encryption is set up** is native (slimcore, not in Teams' JS; the web stack has no E2EE and says "Unable to join end-to-end encrypted meetings from the web"). Strings in SlimCoreWebview2.dll and RtmPltfm.dll show the shape: the account config's `preferE2EEncryption`; an encrypted conversation (`POST-CreateEncryptedConversation`, `e2eeData`, `publicKeyFingerprint`); call states `NegotiatingEncryption` / `NegotiatingEncryptionLobby` and `disableEncryptingMode`; endpoint `encryptionState` / `e2EEProperties`; media keyed by DTLS (`DtlsForE2EESuccessfullyNegotiated`) with `localFingerprint`, `remoteFingerprint`, `remoteCertificate` and `GetDtlsFingerprintHash`, and a check "Session fingerprint doesn't match roster fingerprint."; group keys (AES_256_GCM, commitments and nonces) for E2EE meetings. Teams desktop's ordinary 1:1 offer already carries both SDES `a=crypto` lines and `a=fingerprint:sha-256` (no `a=setup`), `clientEndpointCapabilities` 15611602 (bit 64, "end-to-end encryption", is set whatever the setting).

**OST**: the indicator and its card in every call (`encryptionCard`, `e2ee` / `e2eeNumbers` on CallWindow), the Privacy card and its setting where Teams keeps it (`api::preferences::E2EE_SETTING_PATH`, `e2ee_calls_allowed`), the E2EE call's hidden controls (`ubar::e2ee_hidden`, `Facts.e2ee`), and the negotiation: while your setting is on (read at sign-in, `webrtc_audio::set_prefer_e2ee`), OST's 1:1 offers carry `a=x-e2ee` and its answers echo it when the offer has it; the call is then marked end-to-end encrypted (`WebRtcAudioSession::is_e2ee`, `callE2ee`) and the window shows the ShieldKeyhole and Teams' E2EE card. Checked live: Teams desktop shows the call with OST as end-to-end encrypted. OST's card shows no numbers: their derivation isn't known. Harness `--e2ee-setting-test[=on|off]`, `--call-encryption`.

### 1.9 Call timer (CallDurationIndicator, `tp`, module 414673; format 494225/877513)
- Start time comes from `callStartTimestamp(teamsCallId)`. It ticks every 1000 ms.
- Format `MM:SS`, becoming `HH:MM:SS` once hours > 0. Every field is zero-padded to 2 digits.
- Shows `--:--` before the start time is known.
- Tooltip "Elapsed time"; aria "Elapsed time {{elapsedTime}}".

## 1b. Controls and Meeting options (organizers; unified-bar-container-manager `St`/`xe`/`je`, calling-meeting-options-form)
Measured and captured on winpc 2026-11-10 (CSS px).
- **Controls** opens a Fluent menu (`organizer-control-button-menu`), the View menu's style: surface 263.3 wide, padding 16.67, radius 4, shadow 16; rows 32 tall (padding 6, radius 4, label 14/400 #424242 at 10), checks (16) 6 from the right; its left edge at the Controls button's.
  1. Lock meeting — checked while locked; opens the lock dialog. Tooltip "When the meeting is locked, nobody else can join the meeting." Disabled with open breakout rooms ("You can't lock the meeting while breakout rooms are open.").
  2. Enable lobby — checked while `AutoAdmittedUsers` ≠ Everyone. Tooltip "When lobby is enabled, participants will wait in a lobby until admitted by an organizer."
  3. divider; heading "Allow all participants to:" (12/600 #616161, 32 tall, 8 in).
  4. Present — checked while `PresenterOption` = Everyone.
  5. Chat — checked unless the meeting chat is disabled.
  6. Unmute themselves / Turn on their cameras — from `AttendeeRestrictions`; disabled (#BDBDBD) while everyone presents (`PresenterOption` Everyone or EveryoneInCompany): "This option is locked because everyone in this meeting already has presenter permissions."
  7. divider; View more options — the Meeting options dialog.
- Each item saves one option through the meeting options API. Toggling a list option: Everyone → the saved value, or OrganizerOnly when that is Everyone; anything else → Everyone. Chat: Disabled → Enabled (InMeeting when that was saved), else Disabled. A/V bits (`je`): UnRestricted → DisableAudio / DisableVideo; DisableAudio → UnRestricted (audio) / both (video); DisableVideo → both (audio) / UnRestricted (video).
- **The options API**: `GET {mt}/beta/meetings/v1/options/{tenant}/{organizer}/{thread}/{message}/{message}?monarch=true` (the thread's `:` as `_`; `0/0` for a scheduled meeting, the meeting post's id for a channel meeting) lists `{name, type, values, currentValue, category, isDisabled, isLocked}` plus the meeting's `invitees` (`{mri, upn, objectId, tenantId, meetingRole}`), `meetingDetails` and the dialog's `translations`; Apply POSTs every option back, each in its type's shape (List/Boolean/BitMask `{name, type, currentValue, isRecommended: null}`; people pickers `{selectedPeople: [{upn, mri, objectId, userType: "Member", tenantId?}], isValid}`; Interpretation adds `isValid` and `category`; ExternalFeed adds `refreshKey`, `isBackupEnabled`, `sslEnabled`). The reply repeats them with `success`.
- **Meeting options dialog**: 780.7 × 538.7, white, padding 0 24; "Meeting options" 20/600 at 24, 24; Close 24 in from the right.
  - Tabs (215 wide, at 24, 78.5): 28 tall every 32, padding 4 8, icon 20 (filled when chosen) at 8, label at 34 (600 when chosen), a 3 px brand bar on the chosen tab. Clicking scrolls to that section; scrolling moves the choice.
  - Sections scroll in a 512.7 × 413.8 area at 244, 78.5: icon and title (16/700, line 22); fields from 48.5 under it; sections 57 apart over a divider. Field: label 14/600 #616161; description 12/16 #616161 (450.7 wide beside a switch, 498.7 otherwise); a dropdown 497.3 × 30 8.7 under, or a 40 × 20 switch on the label's row.
  - Meeting access: Who can bypass the lobby? (Everyone; People in my org, trusted orgs, and guests; People in my org and guests; People in my org; People who were invited; Only organizers and co-organizers) with its description; People dialing in can bypass the lobby; Who can admit from the lobby (Organizers, co-organizers, and presenters; Organizers and co-organizers); Show meeting info on join screen (Users allowed to bypass the lobby; Everyone); Announce when people dialing in join or leave; Require unverified participants to verify their info before joining.
  - Roles: Choose co-organizers: (a people picker, below); Teams' planning-group note over Who can present once there are co-organizers or Who can present is Specific people / Only organizers and co-organizers (#F5F5F5, radius 5, padding 5, filled info 16, text 12/16 with Learn more → support.microsoft.com/teams/meetings/chat-with-event-group-microsoft-teams); Who can present (Everyone; People in my org and guests; Specific people; Only organizers and co-organizers); Enable language interpretation.
  - Production tools: Who has control of production tools (Organizer and co-organizers; Organizer, co-organizers, and presenters; Specific people); Enable Green room.
  - Participation: Allow mic for attendees; Allow camera for attendees (the two `AttendeeRestrictions` bits, on while not disabled); Meeting chat (On; Off; In-meeting only); Q&A; Allow reactions; Allow attendance report; Who can start annotations? (Active sharer; Everyone).
  - Recording & transcription: Record and transcribe automatically (Record and transcribe; Transcribe only; Off).
  - Copilot and other AI: Allow Copilot (During and after the meeting; Only during the meeting; Off — `isLocked` by the admin in the test tenant); Start Intelligent Recap when Copilot is turned on.
  - Accessibility: Provide CART Captions.
  - A label's buttons (24 × 23.3, transparent, 16 px glyph filled in brand on hover, Fluent tooltip with arrow above: white, radius 4, padding 4 11 6, 12/16, max 240): a lock when `isLocked` ("This option is locked by admin.", the control disabled), an info button when `meetingsOptions_<name>_<value>_Info` exists (that text; e.g. Allow Copilot, Who has control of production tools).
  - **People pickers** (Fluent TagPicker; PeopleSelection `Xn`, PeoplePicker `da`): 498.7 × 33.3, white, radius 4, NeutralStroke1 border with the accessible stroke at the bottom, 2 px brand line while focused, 12.67 in; picked people as tags (20 tall, radius 12, #F5F5F5, a 16 px colourful avatar with one initial, name 14 #424242, dismiss 12; 4 apart); "Search for participants" only while nobody's picked. In a meeting the picker doesn't search the directory: it offers the meeting's invitees (co-organizers: plus those picked, never the organizer or people from another org; specific producers: plus the organizer), minus anyone picked in the same section, filtered by name; at most `maxPeopleSelectionAllowed` (10). With nobody to offer it is disabled. The list drops 2.2 under the box: white, radius 4, padding 4 + 2, menu shadow; rows 44 (padding 6 8, radius 4), 32 px colourful avatar, name 14; max 15.5rem. Names come from the people service (`fetchShortProfile`). Avatars use Fluent's colourful palette (name hashed over 30 persona colours, Background2 / Foreground2).
  - Specific presenters / producers are required while "Specific people" is chosen (red border); Apply then scrolls to the empty picker instead of saving.
  - Apply (71 × 31.3, bottom right, 24 in) is disabled until something changes. Close or Escape with unsaved changes asks "Unsaved changes" / "Do you want to discard edits or continue editing?" (600 wide, radius 8, padding 24; Continue editing (primary), Discard).

## 2. Pre-join screen (module 615280; per-state presets 620894; audio enum 548277; hooks 398206)
Window title: "Meeting join | {{meetingTitle}}" (`calling_meeting_window_title`). `enablePrejoinVisualRefresh` is off live, so this section describes the **classic** layout.

### Structure (`BG`, top to bottom)
1. Alert banners: watermark, audio-only, screen-capture protection.
2. Account picker: `Auth.enableAccountSelectionOnPreMeetingJoin` (true), meetings only, not ad hoc. Re-auth tooltip: "To join this meeting, sign in again or select another account."
3. **Header**:
   - H1 = meeting title, or "Microsoft Teams meeting" when there is none. Ad hoc meetings get an editable title box.
   - The title is replaced by "Connecting", by "Encrypting your meeting. This may take a moment" (E2EE), or by the lobby/staging text.
   - "Choose your video and audio options for {{meetingTitle}}" is **screen-reader only**; it is never shown as visible text.
   - Under the title, for Scheduled/Recurring/Broadcast meetings only, after `prejoinMeetingContextDetailsDelayInMs` 5000 ms:
     - date
     - "start – end TZ"
     - participant summary: "Organizer joined" / "Organizer +{{participantsString}}" / "1 other joined" / "{{numberJoined}} others joined" / "over 99 others joined"
     - The summary opens a popover: "In this meeting", "+{{lobbyCount}} waiting in lobby".
     - Recurring meetings add an icon with "This is an occurrence of a series."
   - Anonymous users get a name box "Type your name", max 50 characters. Errors: "Enter a name to join the meeting." / "Your name can be up to 50 characters." / "Your name can only include letters, numbers, spaces, and these symbols: - ' . _ @".
4. **Content row**: video preview on the left, audio options on the right.
   - If only Computer audio is possible (phone, room and none options all false), the mic toggle moves into the video toolbar and the audio column disappears. The toolbar landmark is then called "Join options" instead of "Video options".
   - **Below 720 px width** only the selected audio option shows, with a "More audio options" chevron. It opens a popover listing every option (icon, title, short subtitle, "Suggested" badge).
5. Action buttons **below** the row, right-aligned (centred in computer-audio-only mode).

### Video preview + toolbar (`dk`, `fk`; data-tid `prejoin-v2-video-actions`)
- Preview rendered natively. Camera-off text: "Your camera is turned off" / "No camera is connected" / "Video preview is not available" / device failure / "Your camera is being used by another application…". Notification banners over the preview disappear after 7000 ms.
- Toolbar: [mic toggle (computer-audio-only mode)] [camera toggle] | divider | [effects button].
- **Camera toggle**: camera icon, a chevron ("Open video options") and an on/off switch.
  - Labels "Turn camera on" / "Turn camera off" (+ shortcut).
  - Disabled when: admin block ("Video sharing is disabled by the administrator"), no camera, or permission denied ("Allow Teams to access your camera. Go to your privacy settings to allow it.").
  - Flyout (686534): "Camera" list + "More video settings", which opens the `videoeffectsandsettings` pane. No backgrounds row in pre-join.
- **Effects button**, exactly one, first match wins (`Kk`):
  1. avatar mode → "Effects and avatars"
  2. video extensibility → "Video effects"
  3. `enableVideoAutoAdjust` (false) → "Video effects"
  4. blur-capable device → **"Background filters"**, which toggles the `videobackgrounds` pane. Needs `enableVideoBackground` (true) and a filter policy other than NoFilters (live AllFilters), or org images. Disabled while video is off ("Turn on video to use background effects").
  - Which one shows live depends on runtime contexts (unverified).

### Audio options (radio group "Audio options"; order `M7`)

| value | title | subtitle (wide; shown only when nothing is selected yet or on the suggested option) | narrow subtitle | content when selected |
|---|---|---|---|---|
| 0 | "Computer audio" | "Use your default mic and speaker." | "Use this device." | mic row, speaker row, "Test mic and speaker" |
| 1 | "Phone audio" | "Checking for dial-in info…", then "Dial in from any phone, or we'll call you." (disabled: "You don't have access to dial-in information for this meeting") | "Dial in or receive a call on my phone." | "We'll give you a number to call after you join, or we can call you." |
| 2 | "Room audio" | "Use the meeting room's audio system." / "We've detected a room device." | "Connect to a Teams room system." | room picker (638130): "Search for a room", "Nearby", "Other Suggestions", "Unable to find any rooms", "Requires a room with an audio system." |
| 3 | "Don't use audio" | "We'll mute your device when you join." / "You're in a room that already has meeting audio." | "We'll mute your mic and speaker." | "Join muted to avoid causing audio disruption." |
| 4 | "Follow Meeting" | (follow mode; flags off) | "You will join in follow mode. You won't be able to see or hear others." | |

- **Room audio's rooms** (TASK-0161, Teams' RoomService and room dropdown, captured on winpc 2026-11-17):
  - The list: "Connected room devices" (BYOD, see settings.md), "Nearby" (Teams Rooms heard over Bluetooth; each with
    Teams' signal glyph, CellularData1 when adjacent, else CellularData3) or "Unable to find any rooms", then "Other
    Suggestions" (the tenant's rooms) or "Unable to find any rooms". A room shows its presence under its name
    ("Offline", "Available").
  - Other Suggestions: `POST https://outlook.office.com/SchedulingB2/api/v1.0/me/findmeetinglocations`
    `{"MaxCandidates":10,"ConferenceRoomsOnly":true}` (Outlook token, `client-request-id`).
  - Search for a room: the same with `"QueryConstraint":{"Query":"<typed>"},"LocationProvider":"80"`; its results replace
    the list.
  - Each room's `LocationEmailAddress` is resolved like a person by mail (`POST {mt}/beta/users/fetchShortProfile?
    isMailAddress=true&…&includeDisabledAccounts=true`); its MRI is the room's id. A room without a Teams account has
    no MRI and isn't listed.
  - Nearby (Teams' BluetoothLEService): advertisements with Microsoft's manufacturer data (company 0x0006) `34 F0`, a
    protocol byte (type << 5 | version; Teams Rooms 0/0), the room account's object id (packed GUID) and the validation
    code (big-endian; a Surface Hub appends `20 00`); kept 30 s after the last one; listed from -75 dBm, "adjacent" from
    -50 dBm.
  - The hint under the picker: a room picked: "We'll add the room's audio system to the meeting after you join.";
    else with Bluetooth: on "Requires a room with an audio system.", off "Enable Bluetooth to improve list of available
    rooms." (with the mic blocked too: "Turn on Bluetooth or enable your microphone to detect nearby rooms."); no
    Bluetooth LE: "Automatic room discovery isn't available on your device yet."
  - Joining with a tenant room: the computer's audio stays off, and once in the meeting Teams adds the room
    (addRoomParticipant): `POST links.addParticipantAndModality` with the room's MRI and `participantInvitationData:
    {invitationData: {proximitySource: 1 (Bluetooth; also for a searched room) or 2 (ultrasound), deviceType:
    "computer", autoAcceptAuthorization: {token: <validation code>} or null, meetingInfo: {organizerId, tenantId}}}`;
    a Teams Rooms device accepts by itself with a valid code.
- **The room's side** (Teams Rooms, the meeting-room host "Rigel" in Teams' bundles 89637 and calling-pluginless, read
  2026-11-18; OST's room mode, `calling::room_mode` and desktop `room_host`, on when the account has a Teams Rooms
  licence, `licenseDetails.meetingRoomLicenseCategories`, or `--room`):
  - It says it's a room: the account configuration's `deviceType: "room"` goes into every conversation request it
    creates, joins or attaches with (`conversationRequest.deviceType`), and the roster lists its endpoint with
    `endpointDetails[].deviceType: "room"` (participant deviceType Room; laptops mapped to it nest under it).
  - Its beacon (DevicesBLEService, `bluetoothBeaconEnabled` default on): the data above with a salt from the
    ProximityValidationService: a random 16-bit number, replaced every `proximitySaltUpdateTime` (60 s) and re-advertised;
    the replaced one stays in a history of `proximitySaltHistoryLength` (1). `isValidProof(token, proximitySaltLifetime
    60 s)`: the salt, or a history salt n places back with `(len - n) × 60 s <= 60 s`, so the last two salts.
  - An incoming meeting (Conference) or 1:1 call goes to the auto-join check (onCallStateNotified). byomAutoAcceptService
    accepts it when `byomAutoAcceptEnabled` (default true) and `byomAutoAcceptSetting` (disabled / intenant (default) /
    all; InTenant needs a caller of the room's tenant) allow, the source is allowed (Bluetooth, ultrasound and QR on by
    default, Copilot QR off), a token is there and valid; within 4 s, else (and in every other case) it rings on the
    room's console for manual accept. The invitationData is read from the attached invitation
    (`callInvitation.invitationData`).
  - Accepting: `acceptCall(call, isVideoAllowed, muted=false)`: the microphone on, the camera on when the meeting policy
    allows IP video (never for Copilot QR). When the call ends it goes back to the home screen. An invitation into a
    meeting (a cast, Room audio) comes from the meeting's media processor with its meeting lines (audio, camera, nine
    receive slots, the sharing line, data; send-only sharing while someone presents); OST answers it as a meeting join
    does (receive slots and the media control plane), so the room shows the cameras and a presented screen.
  - Cast: Teams Rooms has no cast rule of its own. "Just cast" makes a Meet now (meetingType "MeetNow", endTime
    0001-01-01), which is neither ad hoc nor ends, so the room stays in it after the caster leaves until someone ends
    it or the room leaves (Teams Rooms 26198 RigelAutoExitMeetingManager; verified with OST in room mode).
  - Auto exit (`autoExitMeetingEnabled`, default on; RigelAutoExitMeetingManager, the same in Teams desktop 26304 and
    the Teams Rooms build): it leaves an ad-hoc meeting (`meetingDetails.meetingType` exactly "Adhoc": a group chat's
    call or a channel's Meet now; a Meet now made from a chat or the calendar is "MeetNow") at once when nobody else
    is left, unless the meeting "escalated" (more than one other person was in it at some point). Nobody else: no
    one connected but calling bots and the room's own endpoints (phone numbers and guests count). Once a meeting's scheduled end has passed
    and nobody else is in it (no HDMI ingest, not an instant meeting), after 300 s (60 s for ad hoc) it shows the dialog
    with a bar filling in 25 ms steps over `autoExitDialogProgressBarCompletionTimeInMs` (15 s) and Snooze (again in
    900 s) / Leave now; the bar filling leaves. Its strings are Teams Rooms' own (namespace meetingRoomConsole, which
    Teams desktop doesn't ship: it's in the Teams Rooms build of Teams, MSTeams-Rooms-x64.msix 26198.304 inside the
    Teams Rooms on Windows 5.7.112 package, go.microsoft.com/fwlink/?linkid=2151817): "About to leave meeting ..."
    (`meeting_room_auto_exit_dialog_title`), "Snooze", "Leave now". The dialog (MeetingRoomAutoExitDialogRenderer): the
    surface 45% x 27% of the screen, square; a column of the title (Text largest, bold, one line, grow 1), the large
    progress bar (grow 1.1) and the buttons (grow 0.8, at the end, large; Leave now with the brand background and 0.8rem
    either side). OST takes the end from the meeting chat's `meeting` property, the invitation's meeting details, or
    the room's calendar entry (RoomAutoExit.qml).
  - The call's title (what the console's meeting-room-in-call-info and the call header show; useMeetingTitle with
    `enableTitleFetchForAllCalls`, on for Rooms): the calling intent's title, else the call's (callTitleService:
    Rooms' message service has no meetup titles, so getDefaultCallTitle from the conversation), else "Microsoft Teams
    meeting". From the conversation: a meeting chat's topic (the subject); a channel `Meeting in "{name}"`; a group
    chat "Call with {topic}" ("Meeting in {topic}" for a huddle); without a topic a meeting or breakout room "Microsoft
    Teams meeting", otherwise the other people's names (sorted, ", ", past three "{first name} and {n} others"). OST
    shows it once the room accepts (the window title), the ringing console showing who invites the room
    (`room_mode::call_title`).
  - The home screen (meeting-room-front-of-room-home): the date above the clock, the room name with the cast icon, the
    room's QR code (`https://teams.microsoft.com/l/qr_code/?actions=5&identity=<room MRI>&tenant_id=<tenant>&salt=
    <salt>&name=<name>`, encodeURI'd, padded with spaces to 221, error correction H, 160 px, the app icon in the
    middle; renewed with each salt), its calendar (today's meeting cards: title or "Private Meeting" or "Meeting with
    {organizer}", "{start} - {end}" or "All day", the organizer, Join for Teams meetings; "Available" when free) and
    "Add this room to a meeting with your personal device". Join on a card joins at once (no pre-join).
- A suggested option gets "(suggested)", or "Suggested" in the narrow layout.
  - Room is suggested when a Bluetooth room is detected or BYOD.
  - None is suggested when a room loudspeaker is already in the meeting.
- Phone is hidden for broadcast roles. Room is hidden for anonymous users.
- Dial-in availability comes from the `subscribedCallChangedEvent{isPSTNEnabled,isPSTNInitialized}` subscription.
- **Default selection**: the cached `prejoinScreenSelectedAudio`, else ECS `defaultPreJoinAudioOption` = 0 (Computer). Room, None and Follow are never cached (`blackListPrejoinAudioOptionsCache` ["2","3","4"]). A companion device forces Computer.
- **Computer audio content** (`HY`):
  1. Mic row: Fluent Switch with a mic-icon label.
     - Tooltip "Mute mic" / "Unmute mic" (+ shortcut). Unavailable: "Mic is not available".
     - Next to it, the device name as a button (aria "Selected microphone: {{deviceName}}, open microphone options"). It opens a flyout: "Microphone" list, 17-segment level meter, "More audio settings".
  2. Speaker row (833394): speaker on/off ("Turn speaker off/on ({{shortcut}})"), volume slider (`enablePrejoinComputerAudioVolumeSlider` true), speaker-name flyout.
  3. "Test mic and speaker" (773962). Disabled in another call or in the lobby: "Testing isn't available while you're in another meeting." / "…waiting to join the meeting."
  - Auto-mute notice: "There are already {{participantsCount}} people in the meeting. We have muted your mic." (threshold `preJoinAutoMuteParticipantThreshold` = 4 is likely the trigger; not traced).
- Toggles call `setCallPrejoinState(newState, callingIntentId)` and `updatePrejoinDevicesConfiguration(callingIntentId, cameraOn, microphoneOn, speakerOn)`.

### Buttons and Join (`HG`)
- [Cancel] (secondary), **[Join now]** (primary, `prejoin-join-button`), then "Lobby chat" (lobby only, after an unread lobby message).
- Town hall / broadcast with a role: Join now is a split button. Menu: "Join as Producer/Presenter/Organizer", "Join as Attendee", "Preview as Attendee".
- Join now is enabled when the state allows joining, an audio option is selected (or computer-audio-only mode), you are online, and the name is valid.
- **Join** (`vM` → `_joinCallFromPreJoinState` → `_internalJoinCall`):
  1. Saves the audio choice.
  2. Runs the anonymous-name, re-auth, consent/CAPTCHA and bot checks.
  3. Builds the join options:
     - `outgoingAudio`/`incomingAudio`: false unless Computer audio, or Room with BYOD/ad hoc space.
     - `outgoingVideo`: off in follow mode.
     - `isTransfer`.
     - `meeting{isFollowMode, isPSTN, title, displayName, isByodEnabledFromPrejoin, roomParticipantToAdd, roomParticipantInMeeting, isRoomAudioSelected, byodRoomName, adhocMeetingSpace}`.
     - consent/CAPTCHA fields, `joinEventAsAttendee`, `shouldSendHigherFrameRateVideo`.
  4. Caches the video state, and the mic state only if you toggled it.
  5. Sets the Connecting state.
  6. `mutation joinCallFromIntent($callingIntentId,$joinOptions)` (+ `weatherpersonCapable`, `nativeMeetingStageEnabled`, `stageEngineEnabled`).
- **Cancel**: `tryStopCall` if a call already exists (lobby/connecting), else `abandonCallingIntent(callingIntentId, "DismissPrejoinScreen")`. A drop survey may ask first: "We noticed you're leaving before joining the meeting. What happened?".
- Phone audio after joining (890111): "Use phone for audio".
  - Call-me option: "Enter your number and we'll call you." / "Enter phone number" / [Call me].
  - Dial-in option: "Dial in with one of the following phone numbers."
  - Status: "We are calling your phone", "Disconnect".

### States (620894, chosen by `QH`)

| state | preset | behaviour |
|---|---|---|
| PreJoin, signed in | `BA` | **Camera default off**, mic default on, cached states applied, focus on Join now (`turnOnVideoByDefaultOnPrejoinScreen` off) |
| PreJoin, anonymous | `TE` | camera default **on**, focus on the name box |
| Connecting | `aN` | title "Connecting" + animated dots, everything disabled, focus on Cancel |
| Staging (moderated) | `R0` | "A moderator is required due to org policy. The meeting will start when they join." |
| InLobby, a presenter is present | `jF` | "Hi, {{userName}}. Someone will let you in shortly." |
| InLobby, no presenter | `MM` | "Hi, {{userName}}. Someone will let you in when the meeting starts." |

- **Held in the lobby, the protocol** (captured from a Teams web guest in the test meeting, 2026-11-08): the join response gives our endpoint a `lobby` modality (no `call`), `activeModalities` is null and the conversation links are few (leave, updateEndpointState, publishState…). The media processor still accepts the call with an SDP answer but `acceptedCallModalities: []`. Admission is a `conversation/conversationUpdate` with `activeModalities.call` (and `lobby: null`) carrying the full links, then the roster moves the endpoint to `call` and the media processor renegotiates (`call/mediaRenegotiation` offer, answered on the negotiation link). Teams' lobby text uses `isPresenterConnected`; OST takes the conversation's `state.isMeetingActivated`.
- **Admitted: the media move and the data channel** (TASK-0213; a Teams web guest's signalling and RTCPeerConnections captured in the test meeting, and OST's own trouter dumps, 2026-11-16):
  - In the lobby the call already has its media and its data channel: Teams creates `main-channel` before its first offer, the processor answers every line, the SCTP association comes up and the media control plane runs (`syn`/`ack`, bandwidth) while you wait.
  - On admission the leg is retargeted (`call/mediaAcknowledgement` "Participant retarget was successful." with the new leg's links) and the meeting's processor moves the call to itself with **`call/mediaRenegotiation`, `mediaContent.newOffer: true`** (`escalationOccurring` false, `fromMixer`, `callModalities: []`). Its SDP offers **the lines of your first offer again, in the same order — audio, your camera, the nine receive slots, sharing, data — under mids of its own** (live: audio 1, camera 2, slots 5–13, sharing 3, data 4; `a=group:BUNDLE 1 2 5 6 7 8 9 10 11 12 13 3 4`), in Teams' RTP/AVP dialect with SDES keys and a fingerprint, no `a=setup` and no directions, each line with its `x-source-streamid` and SSRC range (the data line's `a=x-data-protocol:rtp sctp`), transport-wide cc as `extmap:5`, H.265 first and H.264 as 107.
  - Teams (pluginless) treats it as a retarget: a **new RTCPeerConnection**, `createDataChannel("main-channel")` on it at once, the offer set and answered with every line — audio sendrecv, the camera line sendrecv, the slots `recvonly` with `x-ssrc-range:1-1`, sharing sendrecv, the data line `x-data-protocol:sctp`, `sctp-port:5000`, all `a=setup:active` — keeping the offer's mids and extension ids (`extmap:5` for transport-wide cc). The answer goes to the negotiation's `mediaAnswer` link with `callModalities: ["Audio", "ScreenViewer"]` (the processor's offer names none), `sender`, `links.mediaAcknowledgement` and `clientContentForMediaController` (`controlVideoStreaming`, `csrcInfo`); Teams also sends `mediaDescriptions` (with the processor's mids) and `applyChannelParameters` (`sendSideBWSeed`). The old connection and its channel close once the new one connects; the new `main-channel` opens about a second later and the media control plane starts over (`syn`, a new `ack` naming a new data source id; give / take control's handshake starts again on it).
  - A plain re-offer (`newOffer: false`) follows within a second with the same mids, answered on the new connection.

**OST** (`incoming::answer_renegotiation`, `webrtc_audio::MidMap`): a meeting session's new offer is answered as Teams answers it — a new meeting session (slots, sharing, data line) with the processor's mids on the wire and OST's own inside, its transport-wide cc under the offer's id, the controller callbacks and Teams' modalities in the answer; the new data channel opens and the media control plane starts over, the cameras and the share are asked for again from the roster, give / take control takes its role up on the new session, the camera goes on sending if it was on, and the call's echo canceller and send estimate stay with the new session. Before, OST answered the move as an audio call: no data channel (captions, real-time text, give / take control, dominant speaker) and no video after a lobby admission. Checked live with Teams on winpc (2026-11-16): OST Test 2 admitted from the lobby, `MCP session up` on the new channel, live captions of a guest's speech, Teams' shared screen taken over ("OST TEST" typed into its Notepad), released.
- **Joining someone else's meeting** (verified live 2026-11-10 with a second account, OST Test 2, against Teams desktop as organizer): the join (`epconv`) body carries `meetingInfo {tenantId, organizerId}` from the join link's context (`Tid`, `Oid`); a guest's Teams adds `replyChainMessageId: "0"` and `meetingType: 1`. Without it the call service starts a new ad hoc meeting on the same thread, organized by whoever joins, and they sit in it alone.
- **The date line while held in the lobby**: "Friday, Nov 6 • 3:00 PM – 3:30 PM PST" (the end time carries the time-zone abbreviation). When the meeting wasn't picked from the calendar, OST takes the times from the join response's `meetingDetails` (`startTime`, `endTime`) and shows no line until then. Those are empty for someone held in the lobby unless the meeting option "Show meeting info on join screen" (`AllowedUsersForMeetingDetails`) is Everyone; with the default, "Users allowed to bypass the lobby", the lobby screen has no date line (seen live 2026-11-10).
- **Lobby settings and running meetings**: a change to "Who can bypass the lobby?" applies at once to the running meeting (verified live 2026-11-10: set to Everyone while the meeting ran, the next person walked straight in; set back to Only organizers, the next one waited). An earlier reading that it only applied to the next conversation came from joins that were really separate ad hoc meetings (the missing `meetingInfo`).
- In the lobby, the audio option headers are disabled; the mic and camera toggles still work. Join is disabled and the speaker toggle is disabled.
- Teams Free variants: "We've let the organizer know you're waiting." / "When the meeting starts, we'll let the organizer know you're waiting."
- Overflow/streaming: "Attendee mics and cameras are turned off by default for this event." / "The meeting has reached capacity. You are joining in audio-only mode."

### Device settings pane (`devicesettings`, module 912295; frame 867038 "Device settings", close "Hide settings pane")
In-call, live, with `enableAVFramework` the Devices item is hidden from More. These settings are then reached through Mic ▾ "More audio settings" (`audiosettings`) and Camera ▾ "More video effects and settings" (`videoeffectsandsettings`).
1. "Audio Settings":
   - Speaker dropdown (`selectDevice(id,"Speaker")`; "None" when empty).
   - In-call volume slider 0–100, default 50 (localStorage `speakerVolume`, `setSpeakerVolume`), mute "Speaker is on/off".
   - Microphone dropdown + level meter.
   - "Spatial audio".
   - "Noise suppression" switch + "Background noise only" / "Voice isolation" (`updateNoiseSuppression(Auto|High|None|NoneWithPns)`).
2. "Video Settings": Camera dropdown, "Mirror my video", "Adjust brightness", "Soft focus", "Advanced settings" › "Super resolution".
3. "Extended Displays": "Shared Display Mode" (BYOD).
- "Make a test call" (`startEchoBotCall`) lives only in the Settings app (918664).

### Background effects pane (`videobackgrounds`, module 41834)
- Tiles, in order:
  1. "None"
  2. "Blur" (with `enableBokehBlur`: split "Standard blur" / "Portrait blur")
  3. (style my room)
  4. **"Add new"**, placed right after Blur, not at the end (policy AllFilters + user upload enabled)
  5. images: the selected/recent one first, then org images, then Microsoft's 23 CDN images, then the user's uploads
- Grid: 3 columns (`enableThreeColumnBackgroundLayout`), cells `minmax(91px,1fr)`, rows 58 px, tiles 88×50.
- **Pre-join: a tile click applies at once and persists.** In a call: [Preview] / "Stop preview". Preview turns your video off and shows a 640×360 self-view ("Others won't see your video while you preview."). Then [Apply] / [Apply and turn on video].
- Apply: `applyVideoBackgroundEffects(callingIntentId, imageId, imagePath, persistEffect, isUserImage, imageSrc, imageProvider)`, after `downloadVideoBackgroundImage` for Microsoft/org images (timeout 1000 ms).
- Upload: `.png .jpeg .jpg .bmp`, at least 360 px per side, aspect ratio ≤ 4. The tooltip's "2048 px" is not enforced on desktop. POSTed to `${deepLinkDomain}/maglev/custom-video-background/upload`. Remove is in the tile's "…" menu.
- Policy banners: "Your org sets background to Blur unless something else is selected." / "Some settings are managed by your organization."
## 3. Camera ▾ and Mic ▾ (module 414673; flyouts in 686534 and 269248; mic reasons in 467033)

### Camera (VideoButton, `id video-button`)
- Label "Camera" (`calling_camera_icon_label`). Tooltip "Turn camera off" / "Turn camera on"; "Turning on camera…" while it toggles.
- Icons: `call-video`, `call-video-off`, `call-video-disabled` (attendee video restricted), `call-video-error`. An internal failure disables the button with the aria label "Disabled due to internal failure".
- Toggle: `toggleVideoWithState(teamsCallId, videoOn, context, shouldSendHigherFrameRateVideo, toggleVideoExecutionCounter)`, then `confirmCallToggleState`.
- **Disabled reasons**, first match wins (tooltip text):
  1. "Your camera is being used by another application. Close the other application, then rejoin the call to share video."
  2. "Video devices loading..."
  3. "No available camera found"
  4. "Video sharing is disabled by the administrator"
  5. PSTN call-me-back AV block
  6. "Only select participants can share video" (attendee video restricted), or "Unavailable until the meeting starts" (staging)
  7. "You can share your video when you're done screensharing"
  8. "Video is unavailable for audio-only participants"
  9. "You're sharing content from your camera"
  10. "Disabled by Coordinated Meeting"
  11. "Video call is disabled"
  12. minors-recording restriction
  13. "Allow Teams to access your camera. Go to your privacy settings to allow it."
- **▾ split** (`id video-button-configure`, aria/tooltip "Open video options"). Present when `enableAVFramework` (true). Disabled together with the main button (`enableNoCameraVideoFlyout` false).
- **Flyout**, top to bottom:
  - Live preview while video is off ("Your camera failed" on error).
  - Tabs "Effects and settings" | "Avatars", only when there is more than one tab. Avatars needs avatar mode and `enableAvatarTabInFlyout` (true).
  - Effects tab:
    - "Camera": device list, plus any device error.
    - Divider, then "Backgrounds": a one-row quick picker, shown if tenant backgrounds or a background policy exist.
    - Divider, then the toggles "Adjust brightness" and "Soft focus", each only if the device supports it.
    - Divider, then "More video effects and settings" ("More video settings" in pre-join). It opens the `videoeffectsandsettings` side pane.
  - Avatars tab: avatar picker plus "Turn on avatars".
  - The flyout has **no "Mirror my video" item**.

### Video effects (measured on winpc, 2026-11-14; TASK-0064)
- **Camera ▾ flyout** (`video-button-configure-popover`, 359.3 wide, content 326 at 16.7): preview 326 x 180; tabs (32 px) "Effects and settings" | "Avatars"; "Camera" (12 px) and the cameras as radios (34.3 px rows); divider; "Backgrounds" (12 px) and one row of 77 x 48 tiles 6 apart: None, Standard blur, the first two catalog backgrounds; divider; Adjust brightness and Soft focus (14 px #424242, Fluent switches, 36 px rows); divider; "More video effects and settings" (14 px, 32 high).
- **Tiles**: #E6E6E6, radius 2. None, Standard blur and Show all show a 16 px glyph (prohibited, the video-background-effect person, MoreHorizontal filled) over a 10 px/600 label. Standard blur's 16 px chevron (`bokeh-blur-chevron`) opens a 128.7 x 66 menu of radio items (32 px, checkmark 16 at 6, 14 px text at 26): Standard blur, Portrait blur ("Portrait blur is selected for light blur effect."). Pictures fill the tile; animated ones carry a 20 px video-clip mark 3 px from the bottom left. The chosen tile has a 2 px brand ring outside it and Teams' Checkmark12 (filled part under the outline) at its top right.
- **Catalog**: `https://statics.teams.cdn.office.net/evergreen-assets/backgroundimages/animated.json?v=7` — 6 animated MP4s, then 70 pictures; each `{name, id, filetype, src, thumb_src}` (paths under the CDN).
- **Pre-join quick picker** (`video-effects-quick-picker`, under the camera panel, opened by "Effects and avatars"): tabs Video effects | Avatars; "Backgrounds" (12 px) and a row of 74 x 42 tiles in 82 x 50 cells from 10 in; "Filters" and its row; "More video effects" (12 px, brand) at the end. With the camera off: "To enable video effects, turn on camera".
- **Side pane** "Video effects and settings" (pre-join: "Video effects", no tabs): header 58 (16/700); tabs (44) Video effects | Avatars | Settings.
  - Video effects: accordion "Backgrounds" (32, 12 px) over 88 x 50 tiles, 3 per 109.1 x 58 cell row from 16.7 in: None, Standard blur, Add new, 14 catalog entries, Show all; "Green screen settings" + info; accordion "Filters" (None, then Frames / Styles / Snapchat / Maybelline chips and their grid; TASK-0139).
  - Show all: a sub-view under the tabs — back button (32 x 25, "Back to all video effects") and "Backgrounds" (14 px), then (31 below) None, Standard blur, Add new, your uploads (named by their uuid, oldest first), then the whole catalog. Tiles show the 2 px brand ring on hover too.
  - Add new (TASK-0138): a file picker ("Open", "Custom files" = .png, .jpeg, .jpg, .bmp). Teams accepts an image ≥ 360 px each way with width/height ≤ 4 (no maximum on desktop), keeps it **on this device** (`LocalCache\Microsoft\MSTeams\Backgrounds\Uploads\<uuid>.jpeg` plus a 280-wide `<uuid>_thumb.jpeg`), selects it and shows an info bar over the grid (#EBEBEB, #D1D1D1 edge, 37.3 high, info glyph, dismiss): "Background added.", or "Couldn't add background: Invalid image size." / "…: Invalid image type." / "Couldn't add background.". An upload's tile shows a 16 px ··· on hover; its menu (128.7 x 32) has Remove (delete glyph) → "Background removed.". (The AMS/OneDrive upload with the `userCustomVideoBackground` preference is Teams' VDI path only.) OST keeps uploads in `~/.local/share/ost/backgrounds/uploads`.
  - Settings: Camera (radios); Appearance: Adjust brightness ("Enhance the quality of your video in low light conditions."), Soft focus ("Smoothen your appearance for a polished look."); Advanced settings: Super resolution (TASK-0139), Mirror my video ("Changing this setting will only change the view for you. This setting doesn’t currently work in Together mode."). Info popovers 241.3 wide, 12 px, padding 12.
  - With the camera off in a call, a footer: info glyph + "Others won't see your video while you preview." (12 px), Preview (339.3 x 32, white) and "Apply and turn on video" (brand). Preview shows your preview (325.3 x 183) above the footer; the text becomes "Others will see this image reversed." (while mirrored) and the button "Stop preview".
- **Filters** come from Teams video apps (TeamsJS video extensibility). Frames and Styles are Microsoft's "Custom Filters" app (`73d49226-b5c0-42f0-b918-acd20e8a22d8`, v4.2.5): its definition's `meetingExtensionDefinition.filters` (32: names `Styles_…` / `Frames_…`, the prefix being the category chip) and `videoAppContentUrl` (`https://res.cdn.office.net/midgard/1.latest/custom-filters/index.html`, a WebGL/WASM page with TeamsJS 2.23.0). Teams hosts the page out of sight; the app calls `videoEffects.registerForVideoEffect` and `registerForVideoFrame({videoBufferHandler, videoFrameHandler, config: {format: NV12}})`. Without WebView2 texture streams the buffer path is used: the host sends `video.newVideoFrame` ({width, height, videoFrameBuffer, lumaStride, timestamp}), the app edits the buffer in place and answers `video.videoFrameProcessed` [timestamp]; choosing a filter is `video.effectParameterChange` [id], answered by `video.videoEffectReadiness` [true, id]. Snapchat (`3ddb70b6…`, `6855e072…`) and Maybelline (`1820aede…`) are third-party video apps. Category order: Frames, Styles, Snapchat, Maybelline, YouCam, Warmly; the quick picker's filters (`videoEffectsQuickPickerFilters`) are two Snap lenses then Sweet, Animated purple gradient, Blue waves. Filters accordion: None (88 x 50, 20.7 in), chips (24 high, radius 32, 12 px/500, chosen #4F52B2 with #FAFAFA text, else #E6E6E6/#424242; 20 in, 13 below), then the 3-column grid.
- **Green Screen** lives in Settings ▸ Devices ▸ Video settings (the pane's "Green screen settings" opens it there: openSettingsPanelWithWindowFocus(Devices, GreenScreen)). The group: preview (640 x 360, a 24 px rgba(0,0,0,0.5) bar: "Preview", 12/600 white), Camera (dropdown 292.7 x 30), Automatically adjust camera controls + "Open camera settings" (Windows camera controls), Green Screen ("Turn on Green screen for a better look when you're using a virtual background."), Mirror my video, Adjust brightness, Soft focus, Super resolution; rows 36 high, 30 apart. With Green Screen on the bar reads "What is your background color?" with a 14 px swatch (radius 3, #D1D1D1 edge) in a 22 px white frame (2 px, radius 5) at its right ("Select a color"); pressing it turns the preview into an eyedropper (24 px cursor, hotspot 2,19) — click your backdrop. OST: ost-vfx keys out the picked colour (chroma distance, soft band) with a background on; before a pick it uses the colour it detects behind you, and the preview shows the camera without effects while picking.
- **Super resolution** (AI upscaling of incoming video) is shown by Teams only on devices that can run it ("only works when your device has resources available": the isVideoEffectCapable check). OST has no GPU/NPU inference; on its CPU path a small open model (ONNX Zoo's sub-pixel CNN) takes ~120 ms per 224 x 224 tile (0.25–0.5 s per low-resolution frame), too slow for live video, so OST, like an incapable device, doesn't show the switch.
- **OST filters**: `desktop/qml/VideoFilterHost.qml` hosts the Custom Filters page in a hidden WebEngineView with a TeamsJS host of its own (TeamsJS' frameless transport: `window.nativeInterface.framelessPostMessage` / `window.onNativeMessage`, replies deferred a tick). Camera frames reach it as NV12 over a localhost WebSocket with a secret path (`src/video_effects.rs`), one at a time; the processed frame comes back the same way and ost-vfx's filter bridge puts the newest result into the camera picture (the camera never waits). Snapchat and Maybelline aren't offered.
- **OST**: effects run in `vfx/` (ost-vfx: PP-HumanSeg 2023mar person segmentation via tract, on a worker thread; blur, pictures, animated frames, brightness, soft focus on I420) for both the camera preview and the call's sender. Catalog backgrounds are downloaded to `~/.cache/ost/backgrounds` and played by `desktop/src/vfxplayer.cpp` (FFmpeg) at the camera's 640 x 360. Avatars: below.

### Avatars (TASK-0140; read from Teams on the web's code and config, the Avatars app's definition and its own code, 2026-11-16)
- **Where Teams offers them**: only the desktop app. `isAvatarEnabled()` needs ECS `enableAvatar` (true on the desktop platforms only, false on the web), the new desktop app on WebView2 ("MagLev", with Edge's video extensibility), WebView2's texture-stream APIs, not VDI, at least `avatarMinHardwareConcurrency` (2) cores and `avatarMinDeviceMemory` GB (5 on the desktop platforms, 8 otherwise), and SlimCore at least `avatarMinSlimcoreVersion` (2023.28.01.6; 2023.32.01.20 on one platform). Teams on the web shows no avatar UI (verified in this tenant as ost-test1). Where it isn't enabled Teams shows the "Video effects" button and no Avatars tab anywhere (OST does too until it has the Avatars app's definition).
- **Where they show** (when enabled; measured on Teams desktop on winpc as ost-test1, 2026-11-17, a solo Meet now; modules 681758, 686534, 694696, 506826, 906550, 811151, 710235):
  - **Pre-join**: the effects button reads "Effects and avatars" (aria "Camera is off, show effects and avatars options" / "Camera is on, …" / "Hide effects and avatars options"). Its picker (#F0F0F0, 509.5 wide) has tabs Video effects | Avatars (two equal halves, 44 high, a 0.67 px rgba(0,0,0,0.12) line under; 14 px, the chosen one 600 #242424 over a brand bar) — Avatars while the camera is off, Video effects while it's on, following the camera. Avatars tab: the **retirement notice** (16 in, 8 down: a Fluent warning bar #FFF9F5, 1 px #FDCFB4, radius 4, the Warning glyph, "Changes are coming to Avatars in Teams" 14/600 over "Avatars will remain available and supported through April 2027. If your organization uses Avatars, please watch for additional guidance." and "Learn more" → aka.ms/AvatarsUpdate, Dismiss); then "Avatars" (12 px) over a row of 74 x 42 tiles in 82 x 50 cells from 10 in — None ("No avatar" / "No avatar selected"), your avatars (≤ 3, named "Avatar 1", …) and "Create More" (person-add glyph, 10/600) while you have fewer than 3; "Backgrounds" (12 px, 30 high) and None plus the app's backgrounds to fill six columns (Teams' own catalog names: "Gold shimmer holiday background", …), disabled (half opacity) until an avatar is chosen; "More avatar settings" (12 px brand) at the right. With the camera on: "To enable avatars, turn off camera". Without avatars: Teams' "create your avatar" (`avatar-fre`: the app's welcome picture 200 x 179, "Create your avatar in just a few steps.", a "Create your avatar" button) — which opens the Avatars app's builder, or the Store's Avatars page when the app isn't added (seen). The camera panel shows "Select an avatar" (bold #616161), then your avatar on a dark backdrop once chosen (the camera switch stays off); **Join now then joins with your avatar as your video** (checked: the call's Camera button read "Turn camera off").
  - **Camera ▾ in a call with your avatar on**: only a 326 x 180 #F0F0F0 box (top corners rounded) — "Turn off Avatars" (25 high, 14/600, centred 42.5 down) over "This removes your avatars from view, and starts video preview. Your video preview is only visible to you." (12/600 #616161, 240 wide, 20 px lines) — then "More avatar settings" (a 32 px row, 14 px #424242, 8 below). Otherwise the tabs "Effects and settings" | "Avatars" (14 px, 32 high, from 8 left of the content; under the preview while video is off); the Avatars tab (measured with the camera on): the retirement notice (326 wide, 10 below the tabs), "Avatars" (12 px) over a 72 px row of 77 x 48 tiles 6 apart (None, Avatar 1, Create More), "Backgrounds" and None plus three backgrounds, a divider, "More avatar settings" (32 px row, 14 px #424242) and "Turn on avatars" (brand, 320 x 32, 3 in); with video off your avatar's preview sits above the tabs.
  - **Side pane** "Video effects and settings": tabs Video effects | Avatars | Settings; More avatar settings opens it on Avatars: the retirement notice (327.3 wide), the Avatars app's own panel (its page with `uiOnly=true&avatarId=…&backgroundId=…` in an hwc-iframe filling the space: "Your Avatar", the avatars, "Edit my avatar", backgrounds, emotes, mood, camera), then "Others won't see your avatar while you preview." (12 px, info glyph 10 in), Preview / Stop preview (339.3 x 32, white) and "Apply avatars" (brand), 10 apart. Pre-join's More avatar settings opens an "Avatars" pane: the same without Preview and Apply.
  - **Avatar builder**: Teams' "Customize Avatar" deep link (Create More, Create your avatar, the panel's "Edit my avatar") opens the app's personal tab from the app bar (the app joins the bar once added: "Avatars" with Teams' app header and Present now); first run "Welcome to avatars for Microsoft Teams" with Create from base / Create from photo, then the base avatars and Save and finish / Save and customize; with an avatar, Customize and the + for up to 3.
  - **Frames**: Teams renders its avatar at 1280 x 720 at about 27 fps (the renderer's resolution and frame count read live).
  - **Preview window** (side pane, while previewing): `calling-avatar-preview-window` 339.3 x 198.6 with your video (`myself-video`) 330 x 185.6 in it, above "Others won't see your avatar while you preview.".
  - **Alone in a meeting** (Meet now, measured 2026-11-17): with your video (or avatar) on, your own video (`myself-video`) fills the stage at 16:9 (1031.8 x 578.7 in a 1274.7 x 582.7 stage) with its name tag (`participant-info-nametag`, 24 high, rgba(0,0,0,0.5), radius 4, 8 in from the bottom left: voice level bars or muted); with it off, your picture (154 px) and "Invite people to join you" (24 px semibold; OST shows the strings table's "Waiting for others to join..." to attendees). Camera ▾ with video off still opens on its Avatars tab with the picker and "Turn on avatars".
- **What renders them**: Microsoft's **Avatars** app (`96a116ab-6847-4d22-90f3-f4dd6af74938`, ECS `avatarAppId`; Microsoft Mesh; resource-specific consent MicrophoneStream.Read.User, OutgoingVideoStream.Write.User, MeetingParticipantReaction.Read.User; a personal tab "Avatar builder" at `https://mesh.public.onecdn.static.microsoft/mesh/avatars/prod/studio?appSessionId={appSessionId}`), a TeamsJS **video app** (`meetingExtensionDefinition.videoAppContentUrl` `…/mesh/avatars/prod/video?appSessionId={appSessionId}`). Its page is a **Unity WebGL build** (WebGL 2, WebAssembly): it runs only inside a frame (top-level it redirects to microsoft.com/microsoft-teams/enterprise, checked in OST's web profile, where WebGL 2 is available), signs in through nested app auth (MSAL client `eea619ad-603a-4b03-a386-860fcc7410d1`, scopes `https://collab.mixedreality.microsoft.com/Mesh.Profile.ReadWrite` and Substrate `User.ReadWrite` with `X-AnchorMailbox`), keeps your avatars with Mesh (`https://global.worlds.mesh.cloud.microsoft` `/v2.0/userconfig`, `/items`, `/auxiliary`), lists them to Teams as video effects (their thumbnails) and draws the chosen one into frames it asks Teams for: `video.registerForVideoFrame({videoFrameHandler, videoBufferHandler, config: {format: NV12, requireCameraStream: false, audioInferenceModel}})`, the `audioInferenceModel` being its viseme model (`VisemeModel-0.3.39.onnx`), which Teams runs on your microphone so the avatar's mouth follows your speech; meeting reactions (`meeting.registerMeetingReactionReceivedHandler`) play as its emotes.
- **What others get**: ordinary video. Teams switches your camera to the avatar's output (`setAvatarModeState` selects the avatar as the camera device) and sends it as your camera; nothing else is signalled (`isAvatarOn` goes only into Teams' own telemetry).
- **How Teams feeds the renderer** (TeamsJS 2 in the app; Teams' handlers 447092 / 942930 / 948066): Teams desktop advertises `supports.video.mediaStream` (WebView2's `chrome.webview.getTextureStream` / `registerTextureStream`), so the app sends `video.mediaStream.registerForVideoFrame [config]`; Teams answers with the event `video.startVideoExtensibilityVideoStream [{streamId, metadataInTexture: true}]`, the app opens that stream and registers the stream it draws under the same id. Each NV12 input frame carries TeamsJS' one-texture layout: rows 0–1 a header of u32s (1869900081, version, frameRowOffset, format, width, height, multiStreamHeaderRowOffset, multiStreamCount), from multiStreamHeaderRowOffset a table of `[streamId, offset, length]` and the data (828664161 = the audio inference result: the viseme model's 22 f32), the picture from frameRowOffset. Choosing is `video.effectParameterChange [avatarId(, backgroundId)]` (the background only when there is one; "microsoft_none" is none); the app answers `video.videoEffectReadiness`, lists your avatars and backgrounds with `video.personalizedEffectsChanged [[{id, type avatar|background, name, thumbnail}]]` and its panel reports picks with `video.videoEffectChanged [EffectChanged|EffectDisabled, avatarId, backgroundId]`. Muted, Teams sends `video.mediaStream.audioInferenceDiscardStatusChange [{discardAudioInferenceResult: true}]`. Your own meeting reactions reach it as `meeting.meetingReactionReceived [{meetingReactionType}]` (like, heart, laugh, surprised, applause), played as emotes.
- **The viseme model** (`VisemeModel-0.3.39.onnx`, 153 kB, from the app's `/models/`): input `[batch, 1, 1992]` f32 — 16 kHz mono, 664 samples back and 1328 ahead —, four strided Conv1d + LeakyReLU, average pool, Gemm, Softmax over 22: the 21 visemes of its metadata (`Aa_02` … `Y_Iy_Ih_Ix_06`) and silence (last; 0.93 on silence), at 30 frames a second.
- **OST** (TASK-0140): `desktop/qml/AvatarHost.qml` runs the Avatars app out of sight on OST's TeamsJS host (WebApp `teamsHost`, frameContext sidePanel, nested app auth through `auth::broker`; Mesh sign-in and your avatars work as in Teams) while avatars are shown or your avatar is the camera, letting it go 10 s after. `desktop/src/video_app_frame.js` gives the app's frame WebView2's `chrome.webview` texture streams (MediaStreamTrackGenerator / MediaStreamTrackProcessor); `app_host.js` starts the stream, builds each camera-less NV12 frame in Teams' one-texture layout with the newest visemes, and passes frames between the frame and OST's localhost socket (`desktop/src/avatars.rs`). `vfx/src/avatar.rs` asks for a frame each camera tick and keeps the app's newest; the app's own viseme model (its `audioInferenceModel`, run with tract) runs on the call's processed microphone 30 times a second. Your avatar is a camera device (`ost-avatar`, Teams' setAvatarModeState): the call sends it as your video at Teams' 1280 x 720 and up to 30 fps (what a meeting's media processor allows; others just see video), and your preview shows it at full resolution, and the video effects don't apply to it. UI: AvatarPicker / AvatarNotice / AvatarCreate / AvatarPanel in the pre-join picker and pane, Camera ▾ and the side pane; the app's builder is the "Avatars" app in the app bar (its personal tab with Teams' subEntityId). Your last avatar and background are kept on this device in OST's settings (`avatarLastUsed`), as Teams keeps lastUsedAvatarFilter: its client preferences live in the browser's local storage (ClientPreferencesService: `storage.get/set`, no service call), so Teams doesn't carry them between devices either. Your own reactions reach the app as `meeting.meetingReactionReceived` and your raised hand as `meeting.raiseHandStateChanged` (`[{raiseHandState: {isHandRaised}}]`), as in Teams: the app maps like, heart, laugh, surprised and applause to its emotes and the raised hand to its hand-raise emote, hands Unity the same `TeamsSendMessageReceiver.ReceivedEmoteTriggeredBroadcastChannelMessage` Teams' renderer gets (recorded on winpc), loads the emote (`catalog.mesh.cloud.microsoft/api/items/<emote>/assets/…`) and plays it in the video it draws (Like: a raised thumbs-up for about 4 s, within about a second). Both log "[Ava2EmoteSystem]: The emote … doesn't exist in the database!" first; it's harmless. The player's first emote only plays once it has had enough frames: the frames OST feeds it are camera-less, so the host page sends the app's frame only the four header rows and the frame lays them over a blank picture it keeps, and the drawn frames are copied once (after the 20-byte socket head) — with frame-sized buffers crossing between the pages the app drew about 15 frames a second and a first emote took 20–40 s on a busy machine; now 30 a second and about a second (OST Test 3 saw 9 of 9 Likes, release builds, load 5–8). Teams itself on a CPU-saturated PC played 1 of 2. The renderer page's Web Audio starts without a click (`playbackRequiresUserGesture` off for video apps), as in WebView2. The Avatars app's personal tab has Teams' header: its colour icon (largeImageUrl, 32 px, round, on #FAFAFA, 20 in), its name (18 px bold) and Present now (116.4 x 32, a 20 px icon, 14 px semibold, just left of More options) (`personal_app_header_present_button_title`: "Share {{appName}}" / "You'll be sharing this app for everyone in the meeting to view." / Start sharing, or outside a call "Start a meeting and share {{appName}}" / "After the meeting starts, you'll be sharing this app for everyone to view." / Start meeting, the meeting titled "Meeting with <you>"); the app bar shows its outline icon (smallImageUrl).

### Mic (MicrophoneButton, `id microphone-button`)
- Label "Mic". Tooltip "Mute mic" / "Unmute mic". Variants:
  - "Mute mic (speaker is muted)"
  - "Turn audio on", when audio is off; it opens the audio escalation dialog
  - in a shared room: "Audio is linked with other devices in the same room as you. Mute this mic only" / "… Unmute this mic only"
- Announcements: "Your microphone is muted" / "Your microphone is unmuted".
- Toggle debounce: `minToggleMutePeriod` 100 ms. The icon shows a live volume meter (`enableMicVolumeIndicatorInUbarMicIcon` true).
- Toggle: `toggleMuteWithState(teamsCallId, muteCall, context, causeId, toggleMuteExecutionCounter)`, then `confirmCallToggleState`. Push to talk: `togglePushToTalk(teamsCallId, unmuteCall)`.
- **Disabled reasons**, first match wins:
  1. PSTN AV blocked
  2. Hard mute: "Only meeting organizers and presenters can unmute", or v2 "Only select participants can unmute", or "Unavailable until the meeting starts"
  3. "Audio devices loading..."
  4. "No audio devices available"
  5. no device selected
  6. "Unable to unmute yourself."
  7. "Microphone disabled due to policy."
  8. "Microphone disabled for coordinated meetings."
  9. "Microphone disabled."
  10. "Unmuting..." / "Muting..."
  11. minors restriction
  12. "Allow Teams to access your mic. Go to your privacy settings to allow it."
  13. "Your microphone isn't working. Try reconnecting it or select a different device."
- There is no "Ask to unmute" string in this build. Hard-mute hints: "Mic is disabled for all attendees.", "Raise your hand if you'd like to speak."
- **▾ split** (`id audio-button-configure`, "Open audio options"). Flyout, in default mode:
  - "Speaker": device list, then a volume slider.
  - Divider, then "Microphone": device list, then a level meter.
  - Divider, then the effects section, only if audio effects exist and it isn't an immersive event:
    - "Spatial audio" (only applies to non-P2P calls; `setSpatialAudio`). `SpatialAudioContainer` at FLYOUT with no description and no info button; shown wherever spatial audio is available (desktop, `isSpatialAudioAvailable`), off and disabled when the speaker isn't spatial capable or the call is P2P (Teams' test call is not P2P: enabled there). Measured on winpc 2026-11-19 (meeting and test call): a 36 px row first in the section, "Spatial audio" 14/20 #242424 (8.67 down), the 40 × 20 switch 228 in and 8 down (off: 0.67 #616161 ring and knob), Noise suppression's 36 px row right under it.
    - "Noise suppression": an On/Off switch plus the radios "Background noise only" / "Voice isolation" (`updateNoiseSuppression`).
    - "High fidelity music mode", if supported and the user turned on "Display in the microphone dropdown menu".
  - Divider, then "More audio settings", which opens the `audiosettings` pane.
  - Streaming attendees get a microphone-only variant.

## 4. Leave / End (CallButton `ZS` → `PS`, module 414673; speedbump 588771)
- Button `id hangup-button`, `uiStyle terminal` (red). App-wide shortcut `LeaveCall`.
- Label "Leave" (`call_leave`) in 1:1 calls *and* meetings; there is no "Hang up" string. Other labels:
  - "Leave room" when returning from a breakout room
  - "End monitoring"
  - "Unfollow" in follow mode
- Tooltip "Leave". `enableUbarLeaveButtonSlim` (true) forces the default icon template instead of the wide textual button.
- **▾ split** (`hangup-button-more-options`, aria "More options"). Shown when:
  `((Organizer && !shouldHideHangupEndMeeting) || multipleEndpoints || breakoutReturn || moderator || restartAvailable)`,
  and not follow mode, not a meeting-room console, not a call monitor, and (not a breakout room, or breakout return).
  Items, in order:
  1. "Leave": Organizer (not an attendee endpoint) or moderator.
  2. "Leave on all my devices": more than one own endpoint, `enableEndCallOnUserEndpoints` (true), not streaming or immersive.
  3. "End meeting": (Organizer && !shouldHideHangupEndMeeting) or moderator.
  4. "Restart event": town hall/staging only.
  - In a breakout room the menu is "Leave room" / "Leave meeting" instead.
  - **Presenters and attendees get no End meeting.** In a 1:1 call the ▾ only appears with multiple endpoints, and then holds only "Leave on all my devices".
  - `shouldHideHangupEndMeeting` = (staging end-curtain active, not moderated) or immersive event.
- **End meeting** first asks "End the meeting?" / "You'll end the meeting for everyone." [Cancel] [End]. It then sends `stopCall(callId, "confirm-end-meeting", {forEveryone:true})`.
- **Leave**: `stopCall(callId, "hangup-button_click", {forEveryone:false, forAllUserEndpoints:false})`. "Leave on all my devices" sends `forAllUserEndpoints:true`. Announcements: "Leaving..." then "You have left the call".
- **Leave confirmation ("speedbump")**, `enableHangupSpeedbumpMode` live "Always":
  - While you are screen sharing, a popover anchored on the button: "You're currently sharing. Are you sure you want to leave?" [Stay] [Leave].
  - Otherwise only if the user preference `clientPreferences.meeting.enableLeaveConfirmationDialog` is on (default off). That preference is Settings › General "Ask me to confirm when I leave a meeting", shown only in mode Always. Popover text: "Are you sure you want to leave?" [Stay] [Leave].
  - Never from the keyboard shortcut, in breakout rooms, or in call monitors.
- Breakout return: `goToMainMeetingFromBreakoutRoom(breakoutRoomTeamsCallId)`.

## 5. 1:1 call flows: hold, transfer, consult, merge, park, dial pad (414673; resolvers in 448700 / r_data-client-calling)

| control | id / label | visible & enabled | action |
|---|---|---|---|
| Hold | `hold-button`, "Hold" | P2P only. Enabled in Connected/RemoteHold, not barge | `toggleHoldCall(teamsCallId, context:"Hold")`, announces "You've put the call on hold" |
| Resume | `resume-button`, "Resume" | state LocalHold and not Transferring (or the overflow room is held) | `toggleHoldCall(context:"Resume")`, announces "Call resumed". Overflow room: `resumeOverflowRoom` |
| Transfer | `transfer-button`, "Transfer" | `enableCallTransfer`. Connected/LocalHold, not transferring, not barge, `capabilities.isTransferAllowed`, not a consult call | puts the call on hold (`context:"Transfer"`), then opens the dialog |
| Consult | `consultative-transfer-button`, "Consult" (tooltip "Consult then transfer") | `enableCallConsultTransfer`; as Transfer | hold (`context:"ConsultativeTransfer"`), then the dialog in consult mode |
| Transfer (during a delegate consult) | `transfer-during-consult-custom`, "Transfer" | only when `consultContext.consultingWith=="boss"`; enabled if `canTransfer` | `transferCallConsultation(teamsCallId)` |
| Merge Calls | `merge-calls`, "Merge Calls" | `enableMergeCalls`, `isMergeable`, Connected/LocalHold | dialog "Choose a call to merge" (rows "Call with"; [Merge] [Cancel]; query `mergeableCalls`), then `mergeCalls(targetCallId, callToMergeId)`. In a CONSULT_AND_ADD call: `mergeConsultCall` directly ("Merging calls...") |
| Park Call | `park-button`, "Park Call" | `enableCallPark`, `capabilities.isCallParkAvailable` | `parkCall`, announces "Parking..." then "Call is parked". Shows "Share this code {{pickupCode}} to retrieve the call" [Copy code] (378194). Policy: timeout 300 s, codes 10–99 |
| Dial pad | `dialpad-button`, "Dial pad" | `showDtmfKeypad`; always shown (see §1.4) | toggles `callingScreenStatus.isDtmfKeypadVisible`. Keys send `sendDtmf(teamsCallId, dtmfString)` (798196) |

Held state on the stage (98585):
- local hold: "On hold"
- remote hold: "You've been put on hold"
- calls list (320880): "On Hold" / "Held by {{caller}}"

**Transfer dialog** (V2, because `enableTransferCopilotSummary` is on):
- Title: "Transfer the call", or in consult mode "Consult then transfer the call".
- People picker "Type a name or number" (PSTN numbers allowed; self hidden). Up to `suggestedTransferTargetCount` = 3 suggestions (query `callTransferSuggestions`).
- For a Teams target, a destination dropdown: "Transfer to an audio call" / "Transfer to their work voicemail" / "Transfer to their mobile number: N" / "Transfer to their work number: N".
- Checkbox "Ring back if there's no answer." when `isSafeTransferAllowed` && `enableSafeTransfer`.
- Copilot toggles "Include a call topic for the recipient", "Generate call transfer context for the recipient with Copilot".
- Footer: [Transfer] [Cancel]. Consult mode: [Start a call] (a menu: Audio call / Mobile / Work, when numbers exist) and [Open chat]. With context: "Send message and call" / "Send message and open chat".
- Mutations:
  - `transferCall(teamsCallId, targetUserMri, isSafeTransfer, transferToVoicemail, callContext, callTopic)`, which resolves to `callTransferService.transferCall`.
  - `startConsultation(teamsCallId, targetUserMri, mode:"TeamsCall"|"Chat", recipientMessage, callContext)`.
- Unverified: how an ordinary (non-delegate) consult completes the transfer.

**Park, consult-then-transfer and merge on the wire** (Teams' web calling stack, `calling-pluginless` and 89637; read 2026-11-17) — TASK-0186
- **Who gets Park.** `isCallParkAvailable(call)`: a P2P call, not voicemail-greeting, SfC, TFL or a park call itself, not held (local or remote) or server-held, a Teams-only user, not end-to-end encrypted, `_isCallParkEnabled` (the effective `teamsCallParkPolicy.allowCallPark`, left out of the policy when false; `forceEnableCallPark` / `honorCallParkPolicy` ECS) **and `_isEvEnabled`** (`voiceAdminSettings.isEvEnabled`: Enterprise Voice, which takes a Teams Phone licence). Measured: with the Global park policy (AllowCallPark False) and no Teams Phone, More had no Park Call. After a test-only park policy ("OST test accounts", AllowCallPark True) was granted to ost-test1/2/3, Teams Phone Standard (trial) licences assigned to them and Enterprise Voice turned on, and Teams' cached policies (IndexedDB `Teams:policies-manager…`) were cleared and Teams restarted, Teams desktop on winpc showed More ▸ **Park Call** (`park-button`, Fluent "Call Park" icon) in a 1:1 call with OST Test 2 (2026-11-17).
- **Park, measured (2026-11-17, Teams desktop on winpc parks a call with OST).** Park is park-by-transfer: the parker's client sends the *other* party a `call/transfer/` with `callTransfer {target: {id: <the parker>}, transferor {details, authorizationToken}, parkType: "teamPark", isConsultative, replacementDetails, links {transferAcceptance, transferCompletion}}`; the parked side places a new call to the target carrying that `transferor` (and `clientTransferContext`), answers `transferAcceptance {}` and then `transferCompletion {code: 0}` once it connects; the park server takes the call and the parker's transfer completion carries `unparkContent.pickupCode`. Teams' window then reads "Call is parked" (24/32 bold), "Share this code 11 to retrieve the call" (16/22 bold), [Copy code] (192 × 31.3, white, radius 4, 14/20 semibold; aria "Copy code 11"), 30 px apart, centred. Codes are 10–99 (policy). Retrieve: Calls ▸ "Pick up a parked call" ("Enter park code", [Pick up] / Cancel) places a call to the team park server `4:*11` (Teams' `Kd.PARK`; `*14` is the call queue's CallParkV2, `*13` music on hold) whose `callInvitation.unparkContent = {pickupCode: <int>}`.
- **OST park.** Being parked or transferred: a `call/transfer/` on our call is read (`incoming::transfer_request`), the asked-for call placed with Teams' transferor and context (`outgoing::place_transfer_call`, `signaling::CallExtras`), `transferAcceptance` then `transferCompletion {code: 0}` (500 if it fails) answered, and the new call carries on in the window; the replaced call's ends are ignored. Measured: Teams desktop parked its call with OST Test 2; OST placed the transfer call, both answers were 202, and Teams showed "Call is parked / Share this code 11 to retrieve the call". Parking: More ▸ Park Call (shown when `preferences::call_park_available`, policy and EV, not on hold, not E2EE) sends Teams' park transfer (`incoming::park_body`, `parkType "teamPark"`, to ourselves) and on its completion shows Teams' parked view with the code. Retrieving: `unpark_call(code)` (`outgoing::unpark_call`). Harness `--park-test`, `--unpark=<code>`.
- **Transfer** (`callTransfer`): `POST links.transfer {callTransfer: {target: {id, endpointType: "voicemail"?}, transferor: {details: {id, endpointId, participantId, languageId}, authorizationToken: null}, links: {transferAcceptance, transferCompletion}, replacementDetails, disableForwardingAndUnanswered, transferContext}}`. Blind: no `replacementDetails`. **Consult then transfer**: the consult is a second call to the target while the first is held; Transfer sends the first call's request with `replacementDetails: {replaces: <the consult call's links.replace>}` (`TransferTypeStandard`, `CallTransferType.Consultative`). The target's client gets, on its consult call's `call/replacement/` callback, a call notification with `callType "replaces"` (and `consultativeCallId`), accepts it as the call that replaces the consult call, and the transferor's two calls end.
- **Merge** (`mergeCalls`, two P2P calls → `P2PAndP2P`): Teams finds or makes the group chat of everyone in both calls, then on the active call `POST links.addParticipant` with `groupChat {threadId, messageId}` and, for each person of the held call, `{id, participantId: <new>, replacementDetails: <that person's leg in the held call>}` (ReplaceParticipant) and `links {addParticipantSuccess, addParticipantFailure}`; the active call becomes a group call on that thread, the held call is left. A consult call made for "consult and add" merges with `mergeConsultCall`. The merge list (`mergeableCalls`) needs ECS `enableCallMergeParticipants` and `enableCallMergeWithPickupCode`.
- **OST** (`calling::consult`, `outgoing::{place_call_tagged, merge_body, MergePerson, leg_replacement, one_to_one_chat_id}`, `incoming::transfer_body`, backend `consult_call` / `consult_transfer` / `consult_merge` / `consult_end`, CallWindow's consult banner): two calls at once. Consult ▸ a person starts a call (the row; "Open chat" keeps the chat consult): the first call is held and the consult call placed with its own callback tag, so its events and end are its own; Transfer sends the first call's `callTransfer` with `replacementDetails {replaces: <the consult call's links.replace>}`; Merge Calls makes the group chat of all three and adds the held call's person to the consult call (`addParticipant` with `groupChat`), silently when a roster gave that person's leg (each remote endpoint's `callLinks.replacement`, kept slot-wide because an answered call's first roster arrives with its acceptance, before the call is stored; passed as `replacementDetails`, Teams' ReplaceParticipant) and otherwise by inviting them; it leaves the held call 15 s later in the silent case (leaving at once loses the leg: `addParticipantFailure` 580/5201, "Replacement call was not found", 404/10202), at once otherwise, the consult call going on as the group call. Live (2026-11-17, Teams on winpc + OST Test 2 + OST Test 3): `addParticipantSuccess`, Teams did not ring, its call window went straight to "OST Test 2, OST Test 3" with all three in the roster; End consult hangs it up and resumes the held call; if the held call ends first, the consult call carries on as the call. A transfer, merge or park retrieve that replaces the call keeps the window open and its clock running (`call_continues`), not restarting it (live `--clock-log`: merge 24 → 29 → 34 s; Teams-started consult transfer, the transferee 129 → 134 and the target 48 → 52 → 58). **Consult transfer started by Teams** (live): Teams' Consult (`consultative-transfer-button` → people picker → `consult-call-button` "Start a call") then Transfer (`transfer-during-consult-custom`) sends OST Test 2 a `call/transfer/` with replacementDetails; OST places the call to OST Test 3 carrying the transferor, answers transferAcceptance and transferCompletion; OST Test 3 gets the new call on its consult call's `call/replacement/`, answers it and then **leaves the replaced consult call itself** — Teams, as transferor, keeps that consult call on hold until the target leaves it (measured: without this Teams sat on "On hold"). The transferee names its new peer from `acceptedBy` when Teams' request has no target name. Retrieve has a Calls-app dialog too (CallsView's More ▸ "Pick up a parked call" → `UnparkDialog`, Teams' unpark-call-dialog bundle: title "Pick up a parked call", field "Enter park code", Cancel / Pick up). Harness `--consult-call=<oid>` (`--consult-transfer`, `--consult-merge`), `--unpark-dialog-test`.
- **Measured with two test users (2026-11-17).** A consult to the same person as the held call (ost-test1 on a second device) collides in the shared 1:1 chat: the consult call failed within 1.5 s ("This conversation has ended as all participants left the audio-video modality"), the held call ended, and Teams on winpc then showed "You're in a call with OST Test 2 on another device". So consult-then-transfer and merge need a third user.
- **Measured with three test users (2026-11-17: Teams desktop on winpc as ost-test1, OST as ost-test2 and ost-test3).** *Consult then transfer:* Teams calls OST Test 2; OST Test 2 consults OST Test 3 (Teams is held) and transfers with `replacementDetails {replaces: <the consult call's callAcceptance.links.replacement>}`. Teams acts on the transfer request after 3–30 s; the new call reaches OST Test 3 on its consult call's `call/replacement/` callback as a call notification (`callType` "transfer", `transferor` OST Test 2), is answered at once, and the consult call's ends (call/end and conversationEnd, both naming the transferor as sender) are not the call's end. Teams then showed a call with "OST Test 3" and audio flowed both ways; OST Test 2 showed "Call transferred" and left. Without the replacement link (an early `mediaAnswer` was once taken for the answer, so the consult call had no `replacement` or `callLeg` link) the same transfer is blind: OST Test 3 got a second incoming call while busy and Teams went to voicemail. If the consult call is hung up before Teams acts, the transfer fails (`transferCompletion` failure) and Teams stays on hold. *Merge:* OST Test 2 merges; the group chat of all three is made and Teams is invited into the consult call (now the group call): Teams rang "OST Test 2 is calling you from a group", and once accepted its roster had OST Test 1, OST Test 2 and OST Test 3, audio both ways on both OST sides. The held call's end (it is left, untagged) is not the group call's. *Park:* Teams parked its call with OST Test 2 (pickup code 13); OST Test 3 retrieved it with that code: the park server replaced OST Test 2's parked call with OST Test 3's (`call/replacement/`), and both OST sides talked; OST Test 2 parked a call with Teams (code 12) and OST Test 3 retrieved it, Teams' roster then "OST Test 3 joined the call". Teams keeps its parker's window on "Call is parked" after the call is retrieved.
## 6. People pane (roster) (module 221949; rows 320296; sort 978369; lobby 522284/512425)

### Header and top area
- Title "Participants" (`participants_header`). While searching rooms it reads "Add a room". Close button: "Close participants pane". Drill-in panes show a back button, "Return to main Participants panel".
- The search box `roster-participants-search-input` gets focus on open, unless `disableParticpantsSearchInputFocus` is set.
  - No results: "We didn't find any matches."
  - Error: "Search failed." [Try again]
- Invite field (815275), placeholder "Invite someone or dial a number". Picking someone calls `addParticipant1`. Hidden in breakout rooms, for guests and in VTC calls.
- "Share invite":
  - Shown only in meetings, and not in broadcasts or breakout rooms, unless `disableParticipantsToShareInvite`.
  - Disabled at E2EE capacity: "This end-to-end encrypted meeting is at capacity".
  - In freemium meetings it becomes an icon button, "Copy join info".
- "More actions" (…) popover (below-end). Meetings only, and only when at least one item is visible. Items in order:

| # | label | shown when | action |
|---|---|---|---|
| 1 | Mute all | role ≠ attendee, at least 1 other person unmuted, not 1:1, not screen-share-from-chat, not a guest (`canMuteOthers` with self-capabilities) | "Mute everyone?" / "This will mute everyone in the meeting but you." [Mute], then `muteAllParticipants1(teamsCallId, scope)` |
| 2 | Disable mic for attendees / Allow mic for attendees | there are attendees, Host `isAttendeeRestrictionsUpdatesEnabled` (true), role ≠ attendee, not broadcast, not a guest | "Disable mic for attendees?" / "Attendees won't be able to unmute themselves. The organizer and presenters can let people unmute as needed." [Disable mics] [Cancel], then `updateAttendeeRestrictions` |
| 3 | Disable camera for attendees / Allow camera for attendees | as #2, plus `enableAttendeeVideoRestriction` (true) | "Disable camera for attendees?" [Disable cameras] / [Allow cameras] |
| 4 | Lower all hands | at least 1 raised hand, `enableLowerAllRaisehands` (true), role ≠ attendee, not a guest | "Lower all hands?" / "You'll lower {n} raised hand(s)." [Lower all hands] [Cancel], then `lowerAllRaisedHands` |
| 5 | Manage permissions | organizer, and `enableMeetingOptionsButtonInRoster` (false → hidden live) | opens the meeting options URL |
| 6 | Download attendance list | organizer, `enableAttendanceReportInRoster` (true), engagement report policy Enabled, not broadcast, not P2P | v2 builds a TSV ("Full Name / User Action / Timestamp") and calls `downloadLocalReport` |
| 7 | Stop all spotlights | multi-spotlight active, role ≠ attendee | spotlight dialog (634992) |
| 8 | Lock the meeting / Unlock the meeting | `enableLockMeeting` (true), organizer, not in or with breakout rooms, not broadcast | "Lock the meeting?" (943063), then `updateMeetingLock`; on failure "Couldn't lock the meeting" |

### More actions: measured and wired (winpc and Teams' code, 2026-11-08)
- **Button and menu.** The ··· (`more-menu-trigger`) is 32 x 31.33 just left of close, a transparent button (no fill; the glyph turns filled and brand-coloured on hover and while open). The popover (`roster-header-more-menu`) opens below it, flush with its right edge: padding 8 x 4 inside a 0.67 edge, radius 4, shadow 16. Items are 32 tall and 2 apart, as wide as the longest label + 40 (glyph 20 at 6, label at 32). Glyphs: MicOff, MicProhibited / Mic, VideoProhibited / Video, HandRightOff, ArrowDownload, Spotlight, LockClosed (for Lock and Unlock).
- **Requests.**
  - Lock / Unlock and the attendee mic and camera restrictions **PUT** the conversation's `updateMeetingSettings` link with `{from:{id,displayName,endpointId,participantId,languageId}, meetingSettings, sequenceNumber}`: `{lockMeeting: bool}` or `{attendeeRestrictions: bits}` (Audio 1, Video 2, Chat 4). POST is refused with 405. Verified: 202, and the roster's `meetingDetails.meetingCapability` follows.
  - `meetingCapability.attendeeRestrictions` comes back as a name (`UnRestricted`, `DisableAudio`, `DisableVideo`, `DisableAv`, `DisableChat`) or the bitmap; `lockMeeting` as a bool.
  - Lower all hands: `removeState` `{from, sequenceNumber, scope:"all", stateType:"raiseHands"}` (200). Stop all spotlights: the same with `"spotlight"`.
  - Download attendance list: the client's own join/leave log (`participantActions`: "Joined before" for those present when you joined, "Joined", "Left"; a change is noted only when it differs from that person's last one), written as `meetingAttendanceList.csv`, tab-separated, UTF-16LE with a BOM; header "Full Name / User Action / Timestamp"; timestamps like `11/8/26, 10:21:33 AM`; a cell piece starting with one of `=+-@|%"` gets a leading space.
- **Dialogs.**
  - Disable / Allow mic (or camera) for attendees (`confirm-attendee-hard-mute-dialog`): 410 wide; when disabling, a 16 px filled warning 10 before the 20/28 title; the text from y 60.67 wrapping at 360.67; Cancel and the action are fixed 96 wide, so "Disable mics" wraps to two lines (buttons 51.33 tall); 410 x 204.67.
  - Lower all hands? (`confirm-attendee-lower-all-raised-hand`): 400 x 152.67, "You'll lower {n} raised hand(s).", the action as wide as its label (124.09).
  - The text block is at least 32 tall; buttons sit 6 below it.
  - Lock the meeting? / Unlock the meeting (`confirm-meeting-lock-dialog` / `-unlock-`): 430 wide; a 250 tall illustration (the scene 380.66 x 204 at y 95.66, the lock 117.27 x 180 at 156.36, 107.67); the text at y 322.67; buttons 20 below; 438.67 / 418.67 tall. On failure: "Couldn't lock the meeting" / "An error occurred. Try locking it again." [Try again], 430 wide with the warning glyph.
- **Alerts.** `ufd_MeetingLocked` "This meeting is locked." / "No one else can join." and `ufd_MeetingUnlocked` "This meeting is unlocked." / "People can join.": the notice card (320 x 69.33, filled LockClosed 20), shown for 10 s whenever the lock changes while you're in the meeting.
- **Change role?** Make an attendee / Make a presenter first ask (`confirm-demote-dialog` / `confirm-promote-dialog`, the older dialog style): 600 x 184.04, padding 27 / 32 / 32, an 18 px bold title, "A participant's role determines whether they can share content, mute others, and more." (or, demoting the person sharing, "The person sharing now will be able to continue, but they won't be able to start again"), [Cancel] [Change]; backdrop 75 % #252424.
- **Sections.** With attendees, "In this meeting (n)" becomes "Presenters (n)" and "Attendees (n)". A raised hand sorts first and shows its queue number (14 px) and the 32 px raised-hand emoji (`raisehandV3-3D`) 5 before the mic; a pin moves 12 before the number.

### Sections (320296 `Hg`), top to bottom
Titles use the format "{{title}} ({{participantsCount}})". Empty sections are not drawn. The root view shows at most **20 rows per section** (15 for suspected threats), then "See more" (a drill-in) and "+{{n}} more".
1. **Waiting in lobby**. Only when you are not an attendee and not anonymous. With suspected threats it splits into "Waiting" and "Suspected threats".
2. **Presenters**. The title varies:
   - "In this meeting" when the meeting has no attendees
   - "Currently in this call" in a non-meeting call ("Currently in this screenshare" for screen-share-from-chat)
   - "Event group" in a broadcast
3. **Attendees** ("External presenters" in a broadcast). Only when there are attendees.
4. Interpreters.
5. Following (follow mode).
6. **Others invited**: Exchange invitees not in the call, with the status Accepted / Declined / No response / Tentative.
7. **People added to the chat**: thread members.
8. **Suggestions**. Not in breakout rooms.
9. "View Only Attendees" / "Attendees watching event".
10. Agents: `enableAgentsAndBotsInCallingRoster` (true), at most `agentsAndBotsInCallingRosterMaxLimit` (5).

Sections 6–8 are hidden when `maskIdentitiesForRole` is set.

**Sort** (978369 `Eb`), in this order:
1. sign-language signer/interpreter (sign mode only)
2. the group Copilot bot
3. **raised hands, by `raiseHandsOrderedRank` ascending**
4. signers
5. impersonation-detected users
6. external recorder
7. PSTN before non-PSTN
8. display name (`localeCompare`)

In the section that holds you: raised hands first, then **you**, then everyone else.

A separate Raised hands pane, "Raised Hands (N)", sorts by rank. Empty state: "Raise your hand to appear here."

### Row
- Avatar, then the name. The secondary line is one of:
  - an app name
  - "Organizer" / "Moderator" / "Organizer, Moderator" / interpreter language
  - a hybrid room name
  - "Meeting guest" or "External"
  - in the lobby: the impersonation email or "Verifying identity…"
- State text:
  - "Calling...", "On hold", "Leaving..."
  - "Declined" / "No response", with [Retry]
  - "Muting...", "Admitting...", "Denying...", "Changing role...", "Renaming..."
  - "Action failed", which clears after 3000 ms
- Trailing icons, in order:
  1. video off for me
  2. signer
  3. "Pinned"
  4. "Spotlighted"
  5. PSTN
  6. audio off
  7. **raised hand: rank number + hand emoji in the user's skin tone** (aria "Hand raised position {{rank}}")
  8. "Cannot share video"
  9. mic: "Cannot unmute" / "Muted" / "Unmuted"
- "More options" (…) appears on hover; right-click opens the same menu. Ringing participants get an inline [Cancel] instead.

### Participant menu, in order (`Cg`)
1. **Mute participant**: not 1:1. Needs the right to manage the participant (`canMuteOthers` with self-capabilities); disabled when the participant is already server-muted.
   - **On the wire** (calling-pluginless `muteAsync`; captured from Teams on the web in a meeting, 2026-11-25, TASK-0323): Mute participant (MuteSpecifiedSync) and Mute all (MuteAllSync) both POST to the conversation's `mute` link with the call's headers (Bearer IC3 token with `X-MS-Migration: True`, `x-microsoft-skype-chain-id`, a fresh `x-microsoft-skype-message-id`, `x-microsoft-skype-client`, `ms-teams-partition/region/ring`). The body is `{"from":{id, displayName, endpointId, participantId, languageId}, "scope":"specified"|"all", "muteParticipants":[{"id":"8:orgid:…"}], "mediaTypes":["audio"], "links":{"clientCallback":"<trouter>/callAgent/<endpoint>/<operationId>/conversation/muteUnmuteAsync/"}, "operationId":"<uuid>"}`.
     - Each person is an `{id}` object; a bare MRI string is refused with HTTP 400.
     - Mute all names no one (`[]`) and mutes everyone but you.
     - `links` and `operationId` are sent because ECS SkypeCalling `enableAsyncMute` is on.
   - The service answers 202 with `{"muteUnmuteResponse":{}}`. The result follows on the callback as `{"muteUnmuteResponseAsync":{…}, "operationId"}`, a map of each MRI to their endpoints' results (`{participantId, reason, serverMuteVersion}`). For each `reason` "success" Teams marks that endpoint's audio as `serverMuted` straight away, before the roster update arrives. OST does the same with both the reply and the callback.
   - Teams' Mute all dialog ("Mute everyone?" / "This will mute everyone in the meeting but you." [Cancel] [Mute]) has no option about unmuting. People it mutes can unmute themselves. Stopping attendees from unmuting is the separate Disable mic for attendees (hard mute).
   - After Mute all, the service also mutes people who join later in the same meeting session: a Teams web guest and OST Test 2 on the web joined to "You've been muted".
     - The rosterUpdate that says so can arrive a moment before the join completes.
     - OST keeps the rosterUpdates that arrive while it joins and applies its own server mute from them once the join shows. It then joins muted with the same notice.
2. Allow mic / Disable mic, Allow camera / Disable camera (per attendee).
3. **Lower hand**: their hand is raised, it isn't you, and you are not an attendee or guest.
4. **Pin for me** / Unpin (for yourself: "Pin for me" / "Unpin for me"). Disabled at the pin limit ("You reached the maximum number of pins"), when spotlighted ("Can't pin a participant that is spotlighted"), and in managed/presenter mode. Local only (`togglePinItem`).
5. For yourself: Hide me / Include me in gallery / Remove me from gallery.
6. **Spotlight for everyone** ("Add spotlight" when someone is already spotlighted) / "Stop spotlighting" (for yourself: "Exit spotlight"). Needs `enableSpotlightFeature` and you not an attendee. At most `numberOfAllowedSpotlights` = 7 ("No more people can be spotlighted").
7. Fit to frame / Fill frame.
8. Show video for me / Hide video for me; Make a signer; Add as my interpreter.
9. Lower my hand: `enableStageAndRosterLowerHandsEntrypoints` (false → hidden).
10. Make an interpreter (organizer only).
11. Control Room System (room devices).
12. Edit display name: yourself only, `enableRosterRenameAction` (true), and the meeting allows renaming. Calls `renameParticipant`.
13. Join/leave meeting space.
14. **Make a presenter** (target is an attendee) / 15. **Make an attendee** (target is a presenter). Both open "Change role?" / "A participant's role determines whether they can share content, mute others, and more." [Change] [Cancel].
16. divider, then **Remove from meeting**. Takes effect immediately, with no confirmation.
17. Threat items: View threat details (placed at the top, followed by a divider), Report, Report as not a concern.

**Missing on purpose:** there is no Chat, View profile or "Ask to unmute" item in the in-call menu.

Services:
- `muteParticipant1` → `callMuteService.muteParticipant`
- `muteAllParticipants1` → `muteAllInSection`
- `removeParticipant1` → `addParticipantService.removeParticipant`
- `promoteAttendeeToPresenter` / `demotePresenterToAttendee` → `changeParticipantRole`
- `updateCallParticipantRestrictions` / `clearCallParticipantRestriction`
- `updateMeetingLock` → `lockMeetingsService.setMeetingLockedFlag`

### Lobby
- Each row has icon buttons Admit ✓ / Deny ✕ (aria "Admit participant in lobby" / "Deny participant in lobby").
- Section header:
  - "Chat" (lobby chat): organizer only, when lobby chat is enabled.
  - With more than 1 waiting: "Admit all" (drill-in: "Admit ({{n}})").
  - Confirm variant: "Admit everyone in the lobby?" / "Some of the people waiting aren't shown." [Admit everyone] (XL meetings also get "See who's waiting").
  - Suspected threats: "Deny all".
- **Lobby chat** (TASK-0055; captured on winpc 2026-11-11 with OST Test 2 waiting):
  - The organizer's toast has a chat button before Deny ("Send message to lobby participants": 32 × 31.3, white, NeutralStroke1 edge, radius 4, chat glyph 20), and the lobby section's action is "Chat" (72 × 24, glyph 20 and 12 px label) while one person waits.
  - Either opens the call chat pane with tabs under its header: **Everyone** ("Chat for everyone in the meeting") and **Lobby** ("Chat for organizers messaging people in the lobby") with a count badge ("1 waiting": 12/600 #4F52B2 on #E8EBFA; "0 waiting": #616161 on #F0F0F0). Tabs: a 46.5 row 8 in, padding 12 10, 14/20 (600 chosen) with a 3 px brand bar inset 12; a 0.67 #E0E0E0 line under the row.
  - The thread: `POST {mt}/beta/meetings/lobby/getOrCreateLobbyChatThreadId` `{messageId, organizerId, tenantId, threadId}` → `{lobbyThreadId}` (a `LobbyChat` thread, `meetingChatType` lobby, identity masking on). People waiting join it as masked temporary members ("Attendee", `8:teamsvisitor:`, `meetingMemberType` temp, read-only) and get `activeModalities.groupChat.lobbyThreadId` in a conversationUpdate; they see only messages sent while they wait.
  - The Lobby tab lists the messages and "{{name}} is in the lobby." rows (with one person waiting Teams names them: "Attendee (OST Test 2)"), nothing else. Before any message: Teams' empty chat header (chat-pencil illustration, "Messages you send to people waiting in the lobby will show up here."). On the compose (Format and Send only) a note (#F0F0F0, radius 6 6 0 0, padding 8 16 6, 14/20): "Messages you send are only visible to people currently in the lobby. They can view messages but not reply."; with nobody waiting the compose is off and the note (#616161) reads "Chat will be available when someone is waiting in the lobby."
  - People waiting (TASK-0110, measured on winpc 2026-11-11 with Teams waiting in OST Test 2's meeting): once an organizer writes, "Lobby chat" (secondary, chat glyph, 8 after Join now) appears and the **Lobby** pane opens at the right: 360 wide, a 58 header ("Lobby" 18/700, Close chat pane 32 × 30), a #F0F0F0 banner between 0.67 #E0E0E0 lines (padding 5 16, 12/17.1 #424242: "Only organizers and people in the lobby can view these messages."), then the messages listed from the top as "Meeting Organizer" (no pictures; bubbles #F5F5F5, 16.7 in), read-only. The pre-join content shrinks and centres in the rest. They learn the thread from a conversationUpdate (`activeModalities.groupChat.lobbyThreadId`) when it's created, or, when it already exists, from the chat push of that thread (`meetingChatType` "lobby"). The greeting uses your first name ("Hi, OST. Someone will let you in shortly.").
  - Lobby chat exists for scheduled meetings only: for a channel meeting getOrCreateLobbyChatThreadId answers 404.
  - Rechecked 2026-11-26 (TASK-0325; "OST TEST 324 meet", organizer ost-test1 in Teams on the web, lobby "Only organizers and co-organizers"): Teams' organizer → OST Test 3 waiting works both when the thread is made while they wait (conversationUpdate) and when it already exists (their chat push: ConversationUpdate "addedBy" the organizer, then NewMessage); they see only messages sent while they wait. OST as the organizer lost its own meeting role a moment after joining: Teams sends the organizer's entry with `advancedMeetingRole`, then one with only `{details: {displayName}, state}`, and OST replaced the whole entry, so the toast's chat button and the Lobby tab went away. A participant's role is now kept until an update carries one (as Teams' participant merges updates).
- Toast (512425): "Waiting in the lobby", "{{name}} +{{n}}".
  - 1 person: [Deny] [Admit] plus "More info", which opens the roster.
  - More than 1 person, or impersonation suspected: [View Lobby].
- Services:
  - `admitParticipant1(teamsCallId, participantId, entryPoint, markedAsNotBot)` → `callLobbyService.admitParticipant`
  - `admitAllParticipants1(teamsCallId, participantIds)`; the list is empty when `enableLobbyAdmitAllScopeAll` (true)
  - `denyParticipant(teamsCallId, participantId)`; Deny all sends one per person
- Failsafe 100 s. The XL lobby list refreshes every 5 s.
- **Who is listed** (TASK-0230): Teams' People pane partitions the call's roster by participant state (`partition(participants, isInLobby)`; a remote participant is InLobby when every endpoint `isLobby`), so the people who waited before you joined are listed at once: the join response's roster names them with endpoints only in the lobby modality. The `getAllParticipants` `scope: "lobby"` query is the XL drill-in's. Seen live 2026-11-19: Teams on winpc joined OST calendar test as organizer with OST Test 2 and 3 waiting and showed "Waiting in the lobby" / View Lobby and "Waiting in lobby (2)" at once.
- **OST** (`roster::apply_lobby`, `Backend::publish_lobby`): the lobby list is kept from every roster delta (the join roster too) as Teams keeps it, and refreshed from the lobby query when `participantCounts.lobbyParticipants` changes (a refresh asked while the join is still finishing waits for the call). It is shown, as in Teams, to people who aren't attendees.

## 7. Raise hand (414673, 527114, 710637, 615280)
- Bar button `raisehands-button`, label "Raise". Standalone, because `showRaiseHandInReactionMenu` is false. Title "Raise your hand" / "Lower your hand"; shown in the active state while raised. Visibility: §1.4 (never in P2P).
- Announcements: "Your hand is raised." / "Your hand is lowered".
- Service:
  - `toggleRaiseHands(callId, skinTone)` → `raiseHand` = `call.publishState({type:RaiseHands, level:User, content:{skinTone}})`, or `dismissHand` = `call.removeState({stateIds})`.
  - Others: `lowerOtherParticipantsHand` → `dismissParticipantHand` (needs the DismissParticipantHand capability, which organizers and presenters have).
  - All: `lowerAllRaisedHands` → `call.removeStatesForEveryone({type:RaiseHands})`.
  - The UI updates optimistically and rolls back after 10 s without confirmation. Errors: "Couldn't raise your hand. Try again." / "Couldn't lower your hand. Try again."
- **Queue**: the server `raiseHandRank` (publish order), ascending. `raiseHandsOrderedRank` 1…N is computed only up to 20 (`raiseHandsOrderedRankLimit`). The rank number shows next to the hand in the roster and on the tile.
- "Someone raised a hand" popup:
  - Shown for 10 s (`raiseHandsNotificationTimeout`).
  - Text "{name} + # other(s)", where name is the newest raiser.
  - Not shown while the roster is open or someone is in the lobby.
- People button badge = lobby count + raised hands (non-attendees only). Aria "{n} people with new activity. Show participants".
- Auto-lower:
  - Speaking with your hand up for `lowerHandUfdDelayInMs` 3000 ms shows "We noticed you've spoken."
  - With `enableAutoLowerHand` (true) it reads "Lowering your hand in a few seconds" [Keep it raised]. If dismissed without keeping it, the hand is lowered.
  - Manual variant: "Lower your hand?" [Keep it raised] [Lower hand].
  - Unraised speaking can prompt "We noticed you tried to join the conversation" / "Would you like to raise your hand?" [Yes].
## 8. View menu, video stage and reactions

### 8.1 View menu (ViewModeButton `N6`, module 414673)
- Bar label "View", tooltip "Change your view". The icon follows the current layout.
- Menu rows show `title`. Layout items are radio items: the selected one has `uiStatus "open"` and shows a checkmark.
- Order comes from preset 0; rules from `calculateVisibilityOverrides` and each component.

| group | item | text | shown (live) | disabled / notes |
|---|---|---|---|---|
| grid | GridButton | "Gallery" | only when mixed grid is off → **hidden** (`enableMixedGridView` true) | |
| | MixedGridButton | "Gallery" | not 1:1 PSTN | checked for MixedGridView or PrioritizeVideoView. "Unavailable while managing what attendees see" in host managed mode. Selecting it restores Videos first if that is the stored preference |
| | DynamicViewButton | "Dynamic" | hidden (`enableDynamicViewButtonInUbar` false) | |
| | SpeakerViewButton | "Speaker" | `enableSpeakerView` (true), not 1:1 PSTN | disabled in presenter/attendee host view mode. Saves `preferredLayout:"SPEAKER_VIEW"` |
| | AudienceButton | "Together mode" | hidden (`enableAudienceView` false). Never in 1:1/PSTN or with a watermark | enabled from 4 participants ("Share a virtual space with {{n}} or more people") |
| | LargeGridButton | "Large gallery" | `enableLargeGalleryView` (true), not 1:1/PSTN, no watermark, not ACS. **Also only when the device can't show 49 in Gallery**: `allowLargeGalleryForSelectedDevicesOnly` (true) && min(49, maxNumberOfStreams, device gallery limit) < 49 | disabled until **9** remote participants have video. It then stays enabled. Tooltip "View more than 9 videos at once" |
| | AccessibilityButton | "Sign language" | `enableAccessibilityView` and the user's sign-language setting | disabled in presenter host mode |
| | ImmersiveViewModeButton | "Immersive space (3D)" | hidden | |
| | FrontRowButton | "Front Row" | hidden | |
| | FocusModeButton | "Focus on content" (tooltip "Enlarge shared content and hide the gallery") | `enableFocusMode` (true) | disabled unless content is being shared, in host view mode, in immersive view, or when content is popped out. Toggles `isFocusModeEnabled` |
| screen | GalleryViewSizeButton | "Gallery size" ▸ radio: "4 people", "9 people", "16 people", "49 people" | only in MixedGridView / PrioritizeVideoView | sizes above the device limit: disabled when popped out ("Unavailable when content is popped out"), otherwise a warning "Your device might not be able to show this many videos". Saves `preferredGallerySize`; announces "Gallery size changed to {{size}} people" |
| | PrioritizeVideoButton | switch, title "Show videos first" / "Don't show videos first" (bar "Videos first") | mixed grid, `enablePrioritizeVideoViewControlInUbar` (true), MixedGridView/PrioritizeVideoView | stores `isPrioritizeVideoLayoutPreference` |
| | ParticipantsPopoutButton | "Pop out interpreters" | hidden | |
| | ViewModeMoreOptionsMenuControl | "More options" ▸ | | |
| More options | NarrowModeButton | "Show gallery at top" / "Show gallery on right" | `enableNarrowMode` && `enableModernStage` (true) | with spatial audio on: "Turn off spatial audio to select a different view" |
| | IncomingVideoButton | "Turn off other videos" / "Turn on other videos" | `enableToggleIncomingVideo` (true); not 1:1 PSTN | `toggleIncomingVideo(callId)` |
| | ToggleHideMyselfButton | "Hide me" / "Unhide me" | `enableHideMyselfV2`, not broadcast or host view mode | disabled when you are pinned |
| | ToggleMyselfInGridButton | "Include me in gallery" / "Remove me from gallery" | `enableMyselfInGrid` | only in Gallery / Videos first / Speaker. Disabled while hidden or pinned. Videos first needs your camera on |
| | FullScreenButton | "Full screen" (F11) | `enableFullScreen` (true) | announces "Fullscreen mode was set" / "…exited" |

The chosen layout is saved through `updateUserExperiencePreferences{stageSettings{preferredLayout, isPrioritizeVideoLayoutPreference}}`.

### 8.2 Stage layout rules (477421 segments; 2998 areas; 972234 grid; 296162 gallery size)
- Layouts: `MixedGridView` (Gallery, **the default**), `SpeakerView`, `PrioritizeVideoView` (Videos first), `LargeGrid`, `Audience`, `Accessibility`, `FrontRow`.
- Every layout is a Central segment plus a Bar segment:
  - Gallery: Central = shared content (Stage) if any, else the first of HolographicStage, PinStage, MixedStage, MyselfVideo. The others go to the **right column** (side bar).
  - Speaker: SpeakerStage (1 tile, the active speaker; 0 while there are pins or content) comes before MixedStage.
  - Videos first: adds LeanAudioStage for audio-only people.
  - Focus on content: Central = content; the bar keeps only pins and self.
  - "Narrow" variants put the bar on **top**.
- **Gallery at top automatically** (`enableDynamicNarrowMode` true): when the central segment is portrait (h > w), or when content in Central gets a bigger 16:9 area with a top bar.
- **Gallery size**: `mixedGridSizes {defaultSize:16, sizes:[4,9,16,49]}`.
  - `limit` = the largest size ≤ min(maxNumberOfStreams, device decode limit: gallery 49 / sidebar 9 / popout 49).
  - `recommended` = the largest size ≤ min(limit, 16).
  - `selected` = the stored `preferredGallerySize`, else recommended.
  - Streams are also capped by the server's optimal video count (default 49; refresh 30 s).
  - When the selection exceeds the limit, a toast says "You might not see everyone's video" / "The device you're using can only show a limited number of videos at this time."
- **Grid fitting** (lean layouts, fixed 16:9 cells, `972234` class `O`):
  - 1 item → 1×1.
  - 2 items → 1×2 when the container aspect ≥ 1.25.
  - Otherwise grow from 1×1: one row or one column if everything fits there; else take the single "+1 row" or "+1 column" step that fits everything; else add whichever of row/column brings `cols*16/(rows*9)` closer to the container aspect.
  - Then drop a trailing empty row.
  - Rows are centred, so a partial last row is centred. The whole grid is letterboxed at 16:9 in the container.
  - **2 px inset per tile**: 4 px between tiles, 2 px at the edges (`stageLayoutContainerPixelGap` 2, 769760).
- **Side and top bars** (108874/544727):
  - Tile ratios 16:9 / 4:3 / 1:1 (min areas 14000 / 11500 / 10000 px²).
  - Side bar: one column of 16:9 tiles if they all fit, else 2 columns of 4:3.
  - Top bar: the ratio that fits the most tiles.
  - Lean bar widths are chosen from 70/90/100/120/160/240/327 px, top-bar heights from 70/90/134/184 px, by stage-size buckets (78251).
- **Pagination** (`enablePagination` true; 790339): a 36 px strip with "Previous page", "{{currentPage}}/{{pageCount}}", "Next page" (narrow: buttons at both ends, 68 px total). Announces "Page {{currentPage}}/{{pageCount}} selected".
  - Overflow tile "+N" (aria "{{hiddenItemsCount}} more participants").
  - Participants tile: total capped at "99+" ("{{totalItemsCount}} people are in the meeting").
- **Active speaker**: in MixedStage, SpeakerStage and LeanAudioStage, a speaker who isn't visible replaces the first visible tile that isn't speaking (not hidden, not order-preserved), else the least prominent speaker. No swapping while anything is pinned or spotlighted.
  - Screen share, self-in-grid and pins keep their places.
  - Raised hands are promoted into view (`enableRaiseHandPromotion` true).
- **Pins**: up to 9 (`maxPinnedItems` with `enableVideoStage`). The menu disables at `maxItemsOnStage`, which is 9 with 3×3 or else 4; which applies live is unverified ("You reached the maximum number of pins").
- **Spotlight**: up to 7.
- **Self view**: "Myself in grid" is on by default (`enableMyselfInGrid {isEnabled, isDefault:true}`, stored `stageSettings.isMyselfInGrid`). When off, self is a separate floating/bar tile.
- **Two people: you float over the stage** (`updateShouldMeBeInOverlay`, flag `enableMeTileOverlayForOneOnOneInMVS`, live): when the people tiles (not screen shares) number at most `ps` = 2, your tile renders as an overlay. Measured on winpc 2026-11-10 (CSS px, window 1266×673):
  - the other person (`participant-speaker`) fills the stage, 2.6 in from the stage layout, avatar 200 (the tile avatar's maximum);
  - you (`myself-video`): a 245×137 layout box, 5.6 from the stage's right and 5.5 from its bottom, a 2 px #F5F5F5 ring with radius 6 around a 241×133 tile, avatar 65.8;
  - your name tag there has no name: network bars and the mic glyph only (55 wide, 8 px in).
- Tiles without video show the avatar.

### 8.2a Video tile ··· menu (CallingParticipantContextMenu 879019 `getMoreMenuItems`; your tile: MyselfVideo 846553 `renderMoreMenu`; measured on winpc, 2026-11-24) — TASK-0278
- **Where**: hovering a tile shows "More options" in its name tag, 4 after the last glyph (20 × 24, the tag 6 on past it); someone else's ··· is a 16 px glyph 2 in and 4 down, yours 20 px 2 down; white, brand (#5B5FC7) while the menu is open. Right-clicking the tile opens the same menu at the pointer (Fluent `openOnContext`, "above", flipped below near the stage top), centred on it.
- **Placement**: someone else's menu sits right of the ···, bottom-aligned ("after-bottom"); yours above it, start-aligned ("above-start").
- **Surface**: white, radius 4, 2 px in, Fluent's menu shadow (0 0 2 / 0 8 16), no edge; items 32 tall 2 apart, as wide as the longest label + 36 (glyph 20 at 6, label 14/20 #424242 at 30); disabled #BDBDBD; a divider is 0.67 with 4 above and below. Each item's title is its tooltip.
- **Someone else** (in order; each only where Teams offers it): Mute participant (you present, not 1:1, not a bot; disabled while they're muted) · Lower hand (they raised it) · Pin for me / Unpin ("Pin this video to your view"; disabled when the pin area is full or they're spotlighted) · Spotlight for everyone / Add spotlight / Stop spotlighting (you present; a meeting; limit 7: "No more people can be spotlighted"; Bring on screen / Take off screen when presenters manage what attendees see) · Fit to frame / Fill frame (their video shows; per stream, kept for the call) · Control Room System (a Teams Room; ECS enableRoomRemoteDesktop) · divider · Report (a scheduled or ad hoc meeting). Not here: Remove from meeting and role changes (People pane only), Hide video for me (enableToggleParticipantLocalVideo off for the tenant).
  - Measured as the organizer: OST Test 3 (presenter, video) → Mute participant (disabled: muted), Pin for me, Spotlight for everyone, Fit to frame, —, Report; OST Test Room → Mute participant, Pin for me, Spotlight for everyone, Control Room System, —, Report.
- **You**: Switch camera (video on, more than one camera) · Pin for me / Unpin for me ("Pin your own video") · Hide me ("Hide your own video. Others will still see it."; disabled while pinned: "Unpin your video to hide it") · Remove me from gallery / Include me in gallery (Gallery) · Spotlight for everyone / Exit spotlight (you present) · Lower my hand · Fit to frame / Fill frame (your camera in the gallery). Measured: Pin for me, Hide me, Remove me from gallery, Spotlight for everyone (195.08 wide).
- **Spotlight** asks first (634992): "Spotlight for everyone?" / "You'll highlight this video for everyone in the meeting." (yours: "…your video…") / Cancel, Spotlight for everyone; stopping: "Stop spotlighting this video?" / "Exit spotlight?". 600 × 152.67.
- **Fit to frame** shows the whole picture in the tile, the tile's light background around it; Fill frame (the default) crops it to fill. When one person fills the stage and you float over it, Teams fits their video by itself (`automaticFor1x1call`) until you choose, so their menu offers Fill frame (measured with a guest's 4:3 camera).
- **A guest** (anonymous, Unverified) gets the same menu as anyone else: measured as the organizer of a Meet now, Mute participant, Pin for me, Spotlight for everyone, Fill frame, divider, Report.

### 8.3 Reactions (React menu `mw`, 414673; items 402023; overlay 385168/776505)
- Shown only when `enableMeetingReactions`, **not P2P**, not broadcast or overflow streaming, and meeting option `allowMeetingReactions` (or policy). Hidden in immersive events.
- Flyout (toolbox, closes on click), in order: **Like, Love, Applause, Laugh, Surprised** (ids like, heart, applause, laugh, surprised).
  - Skin tone applies to like, applause, okay, wave, handshake, luck.
  - The expanded set (Celebrate, 100, Fire, …) needs `enableExpandedMeetingReactions` (unset → off).
  - **Raise hand is not inside the menu** (`showRaiseHandInReactionMenu` false); it is its own button.
- Shortcuts Alt+Shift+1…5 only with `enableMeetingReactionShortcuts` (unset → off).
- Send: `sendMeetingReaction(teamsCallId, {id:uuid, type, attributes:{skinTone}}, causeId)` (`enableMeetingReactionsThroughNGC` true). Fallback: LiveStateBroadcast `sendMeetingReactionLiveState`. Announces "{{meetingReactionType}} sent". Receive: `meetingReactionsEvent`.
- **On the sender's tile**: only the latest reaction, centred over a dimmed tile, for 4250 ms (`meetingReactionLifetimeInMs`).
  - Emoji size by tile height: <100 → 42 px, <150 → 56, <280 → 84, <410 → 112, <715 → 140, <875 → 168, else 224.
  - A stack of reactions shows at most 8.
- **Floating overlay** over the stage:
  - Emoji 56 px (74 px when the overlay is ≥ 1228 px wide).
  - Each rises from the bottom over 2.133 s with `cubic-bezier(0,0.83,0.19,1.09)`. Opacity reaches max at 31.2%, holds to 67.2%, then fades.
  - Fewer than 3 concurrent: 95% travel at scale 1. More: random scale 1/0.9/0.8 with travel 95/66.5/38%.
  - x follows a repeating 25-step offset pattern around the centre.
  - 24 fps sprites. Capacity: primary 50, burst 100, single-emission cap 12, `maxNewReactionsCount` 5.
  - Same-type reactions in a batch are aggregated.
- There is **no "turn off others' reactions" user setting** in this build. Only the organizer option "Allow reactions" and policy.
## 9. Share tray (module 325285; gate 282627; button in 414673)
- The live tray is the **classic floating tray (325285)**. The modern tray (354183: tabs All / Screens / Interactive files / More options) is dormant: `modernShareTrayConfig.enabled` false, `enableModernShareTray` false, `isFloatingSharetray` true.
- ShareButton ("Share") toggles `callingScreenStatus.isShareTrayVisible`. Shortcut `ToggleShareTray` (Ctrl+Shift+E).
  - While sharing, the button reads "Stop sharing" and calls `stopSharing(callId)`. From the compact view it also shows the call window.
  - Disabled when:
    - the call is not Connected
    - you are an attendee ("Only meeting organizers and presenters can share")
    - you are server-muted or audio-only
    - VDI+E2EE, BYOD, or an external-tenant policy ("Content sharing isn't available in meetings hosted by another org")
    - policy blocks every sharing type
- Tray layout, top to bottom:
  1. Header: "Share content". On the right, the toggle "Include sound" (`share_audio`, `data-tid=system-audio-checkbox`), hidden when `systemAudioSupport=="NotSupported"`; it calls `tryToggleIncludeSystemAudio`. In a drill-down the header shows the section name and a back button ("Back to share tray main content").
  2. **"Presenter mode"**: icon radio buttons "Content only", "Standout", "Side-by-side", "Reporter", plus "Add background".
     - Shown if `isWeatherpersonPresenterEnabled`, more than one layout is supported, not `forceAttendeeStreaming`, and screen sharing is supported.
     - The camera layouts are disabled when the camera is off ("Turn on your camera to select this layout") and during multi-share ("Presenter modes won't work while multiple people are sharing.").
  3. **"Screen"** ("Screen (n)" when n>1): live thumbnails in a 2-column grid (1 column for a single screen).
     - At most `maxDesktopPreviewsAllowedInMainView` = 4. More screens go behind a "More" drill-down.
     - Missing preview: "Screen {{screenNumber}}".
  4. **"Window"**: a single tile, "Opens list of {{windowsCount}} active windows", that drills down to "Choose window". Previews are loaded lazily via `callScreenPreviewsList(APP)` / `callScreenPreviewsImages`.
  5. "Microsoft Whiteboard" / "Start Whiteboard": Member role only, `enableWhiteboardSharing && !enableWhiteboardButtonInUbar`, not a broadcast or immersive event.
  6. "Content from camera" ("Share a document, a whiteboard, and more": Whiteboard / Document / Video). Not shown with `forceAttendeeStreaming`.
  7. "PowerPoint Live" ("See your notes, slides, and audience while you present."), then the recent-files grid.
     - "Excel Live" ("Share a workbook for everyone to work on together."; up to 100 people; files ≤ 2048 MB).
     - "Browse OneDrive", "Browse my computer".
     - In events: "Presenter mode, Whiteboard, PowerPoint Live, and Excel Live aren't available during this event."
- Picking (Windows): there is **no OS picker**. Thumbnails come from the calling stack (`callScreenPreviewsV2`). A click calls `startSharing(callId, sourceId, sharingLayoutMode, aplDefaultBackground, sharingPreviewType)` → `{isScreenSharingOn, screenSharingBounds}`.
  - A window whose title matches an Office file may be redirected to PowerPoint Live (`startFileSharing1`).
  - A "replace the current sharer" or recording-interruption dialog can come first.
  - Esc closes the tray.
  - Sharing from a chat without a call: `fireCallingIntent` → `joinCallFromIntent(sharingSourceId)`.


### 9a. The tray as measured (winpc, 2026-11-16, the test meeting, camera and mic off; window 856 × 537) — TASK-0185
- `share-popup` / `floating-sharetray-wrapper`: 360 wide at (318, 91.3), its top 0.7 over the bar's bottom, as tall as the window allows (438.7: to 7.3 above the bottom), white, radius 4, shadow `0 0.8px 1.8px rgba(0,0,0,.13), 0 0.15px 0.45px rgba(0,0,0,.11)`; Include sound has keyboard focus on open.
- Header (71 tall): "Share content" (16/700) at (23.7, 34.7); "Include sound" (12 px) at (198.7, 29.7) and its switch (`system-audio-checkbox`, the 40 × 20 track at 293.3, 37.7), off.
- Below it scrolls (content 622 tall):
  - "Presenter mode" (14/600) at 10; a toolbar of four 32 × 31.3 icon radios at 23.7, 65.7, 107.7, 149.7 (y 41, radius 3): `sharing-layout-content-only` "Content only" (checked: #E0E0E0, #BDBDBD edge), `-weatherperson` "Standout", `-sidebyside` "Side-by-side", `-newsanchor` "Reporter" (camera off: disabled, #F0F0F0, glyph #BDBDBD, described "Turn on your camera to select this layout"); "Add background" (131.4 × 32 outlined) at (204.3, 42).
  - "Screen" (14/600) at (23.7, 100.3) over a 154 × 90 option (`share_desktop`, named by the monitor: "Generic PnP Monitor"; 4.67 ring, the 144.7 × 80 #FAFAFA card with its live thumbnail); "Window (3)" at 191.7 over `share_window` "Opens list of 3 active windows" (Teams' illustration on #F5F5F5).
  - "Microsoft Whiteboard" / "Start Whiteboard" (36 tall row), "Content from camera" / "Share a document, a whiteboard, and more", "PowerPoint Live" / "See your notes, slides, and audience while you present." with "No files available", "Excel Live" / "Share a workbook for everyone to work on together." with "No files available", then Browse OneDrive and Browse my computer.
- Window ▸ drills down: back ("Back to share tray main content"), "Window" as the title, Include sound kept, and 322.7 × 82 rows per window (116 × 68 thumbnail, app icon 20, title 14/20).
- Sharing a window (Notepad with "OST TEST") opened the **Sharing control bar** window (298 × 36 minimized: Dragger, "You're sharing a window" 12/500, a red "Stop sharing" 87 × 22.7 button radius 6) and the compact view. Expanded (734 × 56; the inner card 714 × 45.3 #FAFAFA radius 8, #F0F0F0 edge): Dragger (20), the timer (12 px), Mic, Camera | Give control (disabled: "Participants are not allowed to control the shared content" — no other participant), Share sound ("Share system sound is off"), Optimize ("Optimize for video content is off"), Layout (disabled: "Turn on your camera to select this layout"), Annotate ("Start annotation") | More (Chat, People — they don't fit) | Stop sharing (red glyph #B10E1C) | Pin ("Pin toolbar" / "Unpin toolbar"). 40 × 39.3 buttons with 10 px labels; dividers 24.2 tall. It minimizes after 4 s unless pinned.

### 9b. What the extras are (Teams' bundles: calling-pluginless, 527114, 616836; 2026-11-16)
- **Include sound** is mixed into your normal outgoing audio (`addAudioSharingStream`: an AudioContext mixer of mic + shared sound, `replaceTrack` on the audio sender; desktop `call.shareSystemSound(true/false)` with Teams' loopback driver). Nothing is signalled. With the mic muted only the mic is muted.
- **Presenter modes** (`ContentOnly`, `Weatherperson` = Standout, `NewsAnchor` = Reporter, `SideBySide`, `Cameo` for PowerPoint) are composited by **the receivers**: the presenter publishes `publishState {stateType:"weatherPerson", level:"user", content:{mode, x, y, width, height, zOrder:2, background?:{id,url,name}}}` and keeps sending the plain screen plus its camera; for Standout and Reporter its camera carries a background mask in the luma (background Y < 23/255, foreground squeezed into 59…255). Geometry (prod ECS): Standout presenter 0.5 of the content at the bottom right; Side-by-side content max 0.66 × 0.65, margin 0.025, gap 0.0225; Reporter content 0.6 × 0.65 at a 0.025 margin, presenter box (0.3, 0.2, 1.0, 0.8). Stopping: `removeStatesForEveryone` weatherPerson.
- **Give / take control** runs on the main data channel, addressed to one participant's data source id: data id 1 carries `{type:0, message: JSON {action, terminatedReason, causeId?, handshakeId?}}` (action 0 Available, 1 ControlRequest, 2 CancelControlRequest, 3 AcceptRequest, 4 RejectRequest, 5 Ack, 6 GiveControl, 7 TerminateNoAck, 8 Terminate, 9 AvailableAck, 10 AvailableNack, 11 RenderedAtViewer); viewers handshake with Available on watching (retries 2 s × n, 6 times); request timeout 30 s, ack timeout 10 s. Data id 2 carries the controller's input: mouse 7 bytes (`1`, type/button/down bits, x and y as u16 0…65535 of the shared frame, wheel ±120 as u8), keyboard 3 bytes (`0`, code type / key up / repeat bits, Windows virtual-key code). Policies `allowParticipantGiveRequestControl` / `allowExternalParticipantGiveRequestControl`.
- **PowerPoint Live / Excel Live** are Office for the web sessions: the file is redeemed, PowerPoint's snap service makes a presentation URL, the conversation gets a contentSharing modality, and attendees host PowerPoint Online (Excel Online for Excel Live, app `1c256a65-…`) in an iframe.

### 9c. Presenting: what Teams does, in detail (winpc and Teams' code, 2026-11-16) — TASK-0210
- **Add background** (`apl-custom-background-button`, shown when Side-by-side or Reporter is supported): a drill-down "Add a background" (header 49 tall: back 20 px at 21/23, the title 16/700 at 55; Include sound hidden), a 2-column menu of Teams' 13 APL pictures (ECS `videoBackgroundImages`, context BackgroundAPL, `statics.teams.cdn.office.net/evergreen-assets/backgroundimages/aplBackground_0nn[_thumb].jpg?v=0.1`), the default "Futuristic room" (003) first: 136.3 × 77.4 `menuitemcheckbox`es 24 in and 24 apart (#E6E6E6, radius 4, the 135 × 76.1 thumbnail inside), the chosen one with a 0.67 black border plus a 1 px inset ring and Fluent's 20 px checkmark (`M7.03 13.9…`, #242424) at 109.6 / 8.7. Names: Wavy pink and blue, Paper rectangles, Futuristic room, Floating shapes, Glowing light, Pink cubes, Circles and squares, Stacked blocks, Green fabric, Colorful bubbles, Skylight, Garden, Green chalkboard. Picking one calls `setAplCustomBackgroundV2({url: src, id})`; the presenter's published layout then carries `background: {id, url, name}` (Side-by-side and Reporter only).
- **Content from camera** drill-down (same header, "Content from camera"): three 322.7 wide `menuitem`s 18 in from y 10 — Whiteboard ("Use your device's camera to share a nearby whiteboard.", 65.3 tall), Document ("Use an external camera to share a document.", 61.3), Video ("Share live video in real time.", 61.3) — each with Teams' 48 px illustration at 6.6 and the title (14/600) and line (12 px) at 64.6. Picking one opens the setup dialog (Camera and Content type dropdowns, the preview, "Turn on camera" / "Share"; whiteboard cleanup and document edge detection are SlimCV effects), then `toggleVideoSharing(cameraId)`: the camera goes out as shared content.
- **Content from camera's setup dialog** (TASK-0214; Teams' `share-tray-content-camera-setup-dialog` bundle and its Griffel CSS, 1rem = 10 px; prod ECS `contentCameraLearnMoreLink` https://aka.ms/AAdu0p9, `enableContentCameraRotation` true, `enableContentCameraPillarBoxing` true, `enableContentCameraSnapshot` false, `enableContentCameraSecondStream` false, `enablePresenterToolbarForContentCamera` false, `enableTextureStreamVideoForContentCamera` true):
  - A Fluent alert dialog, 800 wide with padding 32 (in a window up to 1000 wide: 520, padding 20). Title "Content from camera" (h2) with a subtle close X (`content-camera-dialog-close-button`, the filled Dismiss glyph); there is no Cancel. Closing (X or Esc) resets the effects (`resetScanVideoEffect`), the rotation (0) and the scan type (none). Opening announces "Content from camera".
  - Under a NeutralStroke3 divider, a row (a column in windows up to 720 wide):
    - "Camera" (padding 6 above, 4 below) over a `filled-lighter` dropdown (`contentScanPreview-cameras`, 200 wide, 140 in windows up to 1000 wide; placeholder "None"; picking one is a global camera change, `selectDevice`, and re-applies the type's effects) and an info button ("For the best experience, use wireless headphones and a camera with at least 720p resolution."), 20 to the next column.
    - "Content type" over a dropdown (`contentScanPreview-contentTypes`, same widths, 10 after it): Whiteboard, Document, Video. Picking one shows that type's info if it hasn't been dismissed, else applies its defaults (everything off first).
    - At the row's end, bottom-aligned, the `content-camera-toolbar` (Fluent Toolbar, transparent medium buttons with Teams' 16 px glyphs, tooltips below): Cleanup ("Overlay presenter" / "Don't overlay presenter"; announces "Overlay presenter turned on" / "off"), QuadDetection ("Detect edges" / "Don't detect edges"; "Edge detection turned off"), Rotate ("Rotate"; with `enableContentCameraRotation`, enabled when the camera supports rotation). Disabled while the info shows. "Detect edges" reads on while detection runs or a real quad is set.
  - 20 under the row, a 450 tall area (300 in windows up to 1000 tall):
    - **Info** (whiteboard and document, until "Don't show again"; localStorage `tmp.dont-show-again-<type>` holds whether to show it, written when the box is ticked): the illustration (whiteboard 221 × 126 `evergreen-assets/illustrations/setup_whiteboard_call_share.svg`, document 150 × 142 `empty_sharing_document_camera.svg`, 10 from the top), then 15 apart "Share a whiteboard" / "Share a document" (h3, 20 px, padding 14), "Point your camera at a nearby whiteboard to detect it." / "Put the document in view of your document camera or webcam." (15.6 px, padding 100, 14 in narrower windows; the "… We'll stop sharing your video while you're doing this." variants exist but this path never shows them), primary "Got it" (`content-camera-consent-button`, aria "Got it, dismiss whiteboard sharing information and start camera preview", 10 below it), and "Don't show again" at the bottom left (`consent-view-checkbox`). The dropdowns are disabled meanwhile. Got it hides the info for the session and applies the type's defaults.
    - **Preview**: the camera with the effects applied (`content-scan-preview-myself-video-container`, 420 tall or 270, fitted, not mirrored), then "**Preview** (only you can see this)" (padding-top 10). Teams' toast (`content-camera-settings-toast`) sits over it with its top at the dialog's middle, centred: NeutralBackground1, radius 3, padding 6 10, 12/14 NeutralForeground1, fading in to 0.75 opacity over 0.8 s.
  - Footer: "Learn more" (a Fluent link) at the start; primary "Scan Again" (`content-camera-scan-again-button`) and primary "Share" (`content-camera-share-button`) at the end, both disabled until the preview has started (Share takes focus then).
  - Effects: `applyScanVideoEffect {quadEnabled, cleanupEnabled, zoomEnabled, quadDetails: {normalizedQuad}}`; the native side answers `scanVideoEffect {…, quadDetails: {normalizedQuad, quadStable, frameSize}}`. A quad is normalised `[x0,y0,x1,y1,x2,y2,x3,y3]` (TL, TR, BR, BL); `[0,0,1,0,1,1,0,1]` and all zeros both count as no quad. Defaults: whiteboard quad + cleanup + zoom, document quad + zoom, video zoom only.
  - Edge detection: when quadEnabled turns on, the toast "Looking for a whiteboard" / "Looking for a document" (announced "Detecting edges"), and a poll every 200 ms until the quad is stable and real: the toast goes, "Edges detected". After 11 s without that: quad detection off (cleanup kept, zoom on, the full-frame quad), the toast hidden, 800 ms later "Couldn't detect edges. We've turned off edge detection, but you can still share the whiteboard." (or "…the document.") for 7 s. The toolbar's Detect edges turns everything off, then quad on with a zero quad; Don't detect edges sets the full-frame quad, zoom as cleanup. Scan Again: everything off, then quad and zoom on with a zero quad, cleanup kept.
  - Rotate: the camera turns a quarter clockwise; the quad turns with it (`[1−q7, q6, 1−q1, q0, 1−q3, q2, 1−q5, q4]`), the frame size swaps, and detection stops if the quad was stable.
  - Share: the dialog closes, `toggleVideoSharing(cameraId)` shares the camera as content, and the effects are frozen: quad detection off, zoom and cleanup as they were, the stable quad (else the full frame). Receivers just see the processed picture.
  - Teams' native side (RtmCodecs `vep::Whiteboard` on SlimCV SlimLens) runs three models: person segmentation, the quad (board or page corners) and the clean-up (ink enhancement); a background thread finds the quad and cleans at a low rate, a foreground thread segments and composites every frame; "Overlay presenter" is the cleaned board with the presenter drawn over it see-through. SlimCV isn't available, so OST's processing is its own.
- **Microsoft Whiteboard** row: Teams' Whiteboard logo (a 40-unit SVG with the #30E5D0→#0C34FB board and the pen) 21 px at 5.5 / 5.5 in a 32 px #0027B4 tile (radius 2). Starting it is `startWhiteboardSharing` → a content-sharing session (`addModality` with `contentSharing: {identifier: <the sharing content JSON>, subject, sessionState, sequenceNumber, links: {sessionUpdate, sessionEnd}}`, header `X-Microsoft-Skype-ContentSharing-Chain-ID`); viewers host the board. PowerPoint Live and Excel Live are content-sharing sessions of type ppt / Excel hosting Office for the web.
- **Presenter modes, the receiver's arithmetic** (WeatherpersonMixin 616836; prod ECS `aplPositioningConfig` and `weatherpersonPresenterSize` 0.5):
  - What is published (`getInitialLayoutStateConfig`, zOrder 2): Standout `{x: .5, y: .5, width: .5, height: .5}`, Side-by-side `{x: 0, y: 0, width: .66, height: .65}`, Reporter `{x: 0, y: 0, width: .6, height: .65}`; content `{mode, …, zOrder: 2, background?}` as an object; removal `removeState {scope: "all", stateType: "weatherPerson"}`.
  - The content box: Standout and Content only the whole stage (fitted); Side-by-side the content fitted in (stage × .66 − 2 × .025 margins − .0225 gap) × (stage × .65), at margin + x-margin, vertically centred, the presenter box after it (gap .0225) to the right margin, as tall as the content, widened no further than 3:4 (`sbsMaximumPresenterAspectRatio` .75, the content shifted to centre the pair); Reporter the content fitted in .6 × .65 at x .025, vertically centred, the presenter box (`t × −2 + 2.2`, `−h + 1.45`, x `t − .3`) = (.3, .2, 1.0, .8) cropping past the right edge; Standout the presenter box inside the fitted content, 0.5 of its height (portrait content: of its width) at the camera's aspect, bottom right (bottom left when published x is 0).
  - Scaling: Standout fits the camera in its box, the others crop; Standout and Reporter draw the camera with its alpha (`useAlpha`), Side-by-side doesn't. A published `x === 1` flips the content to the right.
  - Background: zOrder 0, the published picture cropped to the stage (Side-by-side, Reporter); none otherwise.
  - **The camera's alpha is an implicit mask in its luma** (SlimCV ExtractAlphaLuma, documented in Teams' web compositor shader): the presenter squeezes their luma into 59…255 (`255 − (240 − Y) × 28/32`) and sends the background at Y 0; a receiver treats a pixel whose 3 × 3 neighbourhood has any luma below 23/255 as transparent and restores the rest as `240 − (255 − Y) × 32/28`, then decodes BT.601.
- **Give / take control, more of the wire** (calling-pluginless ScreenSharingControl, ControlCapturer, ControlInjector):
  - Mouse events are 7 bytes: `1`, `type | button << 2 | down << 5 | wheelButtonDown << 6`, x and y as **little-endian** u16 (0…65535 over the picture as shown), the wheel as a byte (±120, −120 written as 136). Types: 0 move (every second move event, or one per 50 ms / 30 ms while a button is down), 1 wheel, 2 button; buttons 0 left, 1 right, 2 middle.
  - Keyboard events are 3 bytes: `0`, `codeType | keyUp << 4 | repeat << 5` (codeType 1, VIRTUAL_KEY), the key's `keyCode` (a Windows virtual-key code). Losing focus releases Ctrl, Shift, Alt and Win.
  - The viewer starts the Available handshake when it starts rendering the share (`startOrStopControlForViewer`), answers RenderedAtViewer (11) once its renderer shows the first frame; the sharer answers AvailableAck (and then lists the viewer under Give control) or AvailableNack with the reason (9 SharerControlDisabled when it can't inject, 10 UnknownSender, 1 SharerDenied by policy).
  - Request → AcceptRequest (with the request's causeId) → the viewer's Ack → control; Deny is RejectRequest with reason 1; Give control is GiveControl with a new causeId → Ack; Take back is Terminate reason 5 (SharerTerminated), Stop control Terminate reason 6 (ViewerTerminated), each answered with Ack; no Ack in 10 s ends it with TerminateNoAck reason 4.
- **Measured live** (winpc Teams with OST Test 2 in the test meeting, 2026-11-16; DOM only):
  - The viewer's button is `#screensharing-control-button` "Take control" (Fluent's 20 px glyph `M3.5 2C2.67 2 2 2.67 2 3.5v10…` — a screen with a pointer), in the bar's middle group (it overflowed into More in the 856 px window). Clicking it opens Teams' 400-wide dialog "Request control?" / "You'll control the content the presenter is sharing." [Cancel] [Request] (`confirm-request-control-dialog-button`, 96 × 31.3).
  - The sharer's alert is its own small window (280 × 91.3, #FAFAFA, radius 8; `ufd_SharingIncomingControlRequest`): the title "Presenter mode" (12 px #242424 at 12/6), "{name} is requesting control." (12 px #616161 at 12/28), then [Deny] (outlined) and [Give control] (#5B5FC7, white), 124 × 23.3 each at y 56, 8 apart.
  - Give control ▸ (`give-control-button-popover`): 305.3 × 131.3 for one person, 5 under the button: a 256 × 32 #FAFAFA search box "Give control of your screen to" (also for a window) with a 20 px magnifier, then 270 × 48 rows (32 px avatar 10 in, the name 14 px at 50). The bar's window grows to 248 while it's open (230 for Layout).
  - Layout ▸ (`apl-mode-switcher-button-menu-popover`): 255.3 wide, 5 under the button, 12.7 in: `menuitemcheckbox` rows 230 × 32, 2 apart — Content only, Standout, Side-by-side, Reporter, each with its 20 px glyph at 6 and its name (14 px #424242) at 30, the chosen one's 16 px check 6 from the end; the button itself shows the current mode's glyph (`apl-sharing-layout-button-<mode>`).
  - Teams desktop answered OST's Available with AvailableAck, accepted its ControlRequest and Ack, took OST's Terminate; as a viewer of OST it sent Available, ControlRequest, then input exactly as above (mouse `[1, 0, 229, 28, 39, 127, 0]`, a press `[1, 34, …]`; keys `[0, 17, 17]` = Ctrl up on focus loss).
  - Teams' published Standout layout (read by OST from the roster): `{"mode":"Weatherperson","x":0.5,"y":0.5,"width":0.5,"height":0.5,"zOrder":2}` (an object, no scope); its camera arrives with the implicit mask (OST cleared 77 % of a 320 × 180 frame as background). With OST in Standout or Reporter, Teams labels the share "Content shared by OST Test 2 in presentation mode" and draws it through its `compositor-renderer`; after OST's removeState the label goes back.

**OST** (ShareTray.qml, `screencast::Source`, `calling::system_sound`):
- [x] Share opens the tray (Ctrl+Shift+E too; Stop sharing while sharing), with Teams' header, Include sound, Presenter mode and the Screen / Window options at Teams' places. Screen and Window open the desktop's portal picker for screens or for windows (Wayland gives no thumbnails or window list before it: the Screen option shows Teams' no-preview name "Screen 1", Window Teams' illustration).
- [x] Include sound: OST captures the computer's sound with a PipeWire stream of its own linked to every other application's playback (OST's own, the call, left out) and mixes it into the outgoing audio as Teams does, also while muted; stops with the share.
- [x] Presenter modes (TASK-0210; `calling::presenter_mode`, `ost_vfx` implicit mask, presenting.rs): the tray's camera modes once your camera is on, the bar's Layout while sharing; OST publishes Teams' weatherPerson layout (removed on Content only, a camera turned off, or the share's end) and, for Standout and Reporter, sends its camera with the background cut out into the luma as SlimCV does. As a receiver OST composites a presenter's camera over the screen with Teams' arithmetic and decodes the implicit mask as Teams' shader does (3 × 3 erosion, luma restored).
- [x] Add background: Teams' drill-down and its 13 pictures; the choice goes into the published layout for Side-by-side and Reporter, and receivers draw it behind.
- [x] Give / take control (`calling::screen_control`, `calling::remote_input`): the handshake, requests, Accept / Deny, Give control, Take back and Stop control, both ways with Teams (live 2026-11-16). As a viewer OST's Take control (Teams' ScreensharingControlButton and its "Request control?") sends the mouse (move every 50 ms, 30 ms while pressed) and keys as Windows virtual keys over the picture. As a sharer the desktop's RemoteDesktop portal plays the controller's input (it asks once); only a shared **screen** can be controlled — on Wayland the portal moves the pointer over the whole screen and nothing tells an app where a shared window is, so OST answers a window share's handshake with AvailableNack SharerControlDisabled (Teams then says "Participants are not allowed to control the shared content").
  - Checked end to end on linuxlt (2026-11-18; OST Test 2 sharing linuxlt's screen, a full-screen test text window, to Teams on winpc as ost-test1): Teams' Take control ▸ Request reached OST, OST accepted (AcceptRequest, Teams' Ack; the card "OST Test 1 has control." with Take control), the desktop's Remote Control portal asked once and was approved, and Teams' pointer drove linuxlt's — its press at (0.21, 0.32) of the picture put the cursor at (403, 343) of the 1920 × 1080 screen (KWin's cursorPos). From OST's side, Give control (the bar's list) sent GiveControl, Teams answered Ack and showed Stop control; the portal asked again for that session. Driven through VNC, Teams sent its focus-loss key-ups (Ctrl, Shift, Alt) right after its first press and nothing after it (as on 2026-11-16), so keys typed in Teams weren't seen arriving.
  - Rechecked 2026-11-18 without VNC (OST Test 3 sharing; keys typed through SendInput from a scheduled task in winpc's interactive session, Teams' meeting window in front throughout): the same — Teams sent the move, the press and four modifier key-ups (OST played all four), then nothing for 26 typed keys. Teams' own log shows its ControlCapturer saw the mouse ("Mouse entering render region", "Synced Key states", "Mouse clicked") and no keys, so Teams appears to ignore injected keystrokes; a real key press on winpc's keyboard is needed to finish this check. OST now counts received and played keys in its log (never which keys).
  - Proved end to end the same day with keys Teams' own page receives: after a CDP mouse click on the shared picture (Input.dispatchMouseEvent), `document.activeElement` in Teams' meeting page is its `compositor-renderer` surface, and CDP key events (Input.dispatchKeyEvent, "OST cdp keys") went out from Teams, OST counted and played 30 key events, and the text appeared in the test text window on linuxlt. The SendInput attempts never gave that surface focus, which is why Teams sent nothing then.
- [x] The Sharing control bar window (SharingControlBar.qml): Teams' expanded and minimized bars and sizes, 4 s auto-minimize unless hovered or pinned, Pin, Dragger, Ctrl+Shift+Space, Give control / Take back with its list, Share sound, Optimize (the screen at 30 fps), Layout, More (Chat, People), Stop sharing; a layer-shell surface at the top of the screen on Wayland. The meeting window minimizes to its compact view while sharing, as Teams'. A control request shows Teams' 280 × 91.3 "Presenter mode" card (Deny / Give control) under the bar, as Teams' alert window does while the meeting window is minimized. Annotate shows but is off (Teams' collaborative annotations aren't built).
- [x] Content from camera (TASK-0214; ContentCameraDialog.qml, `ost_vfx::content_camera`, `calling::content_camera`): Teams' drill-down (Whiteboard, Document, Video) and its setup dialog as above: the info views with Teams' pictures and Don't show again (OST's settings, Teams' key names), the live processed preview, the toolbar, the toasts and their timings, Scan Again, Share, Learn more, both window breakpoints, dark and high contrast through the theme. Share freezes the effects as Teams does and sends the processed camera on the screen-sharing line; your video turns off first when it's the same camera. OST's processing runs on I420 frames in ost-vfx (built optimised), as close to Teams' description as it can be:
  - Edges: on a ~320 px wide copy, Otsu's threshold over bright, colourless pixels, a 3 × 3 close, the largest region, its convex hull, the largest quadrilateral on the hull. It is accepted when it is brighter than the rest of the view (mean luma ≥ 130 and 15 % above the rest), doesn't touch three or four edges of the frame (a wall), covers 15–92 % of the frame, the hull is within 12 % of it, it is at least 60 % filled and its corners are 50–130°. Five detections a second, eased (α 0.3), stable once every corner stayed within 1 % of the diagonal for 10 detections. A stable quad then holds while the board is hidden or someone stands in front of a corner (detections within 3 % are ignored); only a different board seen for 3 s replaces it.
  - Zoom: the quad rectified with a homography (bilinear) and fitted into the camera's own size with black bars (pillar boxing); a rotated camera is fitted the same way.
  - Overlay presenter (cleanup): each 16 px cell's white (the 85th percentile of the pixels nobody stands on, a 3 × 3 median over cells, eased over time); every pixel divided by it (0.82 and up turns white, ink is stretched darker and its colour pushed away from the board's). With PP-HumanSeg's person mask (the background effects' 0.3–0.7 smoothstep) warped onto the board (bilinear), the board as it was last seen under the presenter shows, with them drawn over it at half strength; the board is only learnt away from them (the mask grown by ~3 % of the frame, as a moving person's mask lags), and just beside them the learnt board shows, so no ghost edges trail them. Where someone already stands when the clean-up starts, the board behind them isn't known: they are drawn over a clean white board there until they step aside and it is learnt (as Teams' does), not over a copy of themselves.
  - Rechecked 2026-11-18 on linuxlt (test camera C on /dev/video22, removed afterwards): with no board in view, "Looking for a whiteboard" for 11 s, then edge detection off (zoom on, clean-up kept, the full frame) and, 800 ms later, "Couldn't detect edges. We've turned off edge detection, but you can still share the whiteboard." for 7 s. Teams on winpc as the viewer of OST Test 2's Content from camera share: an ordinary content tile, "Content shared by OST Test 2" with the presenter's name tag, the cleaned, rectified board with the presenter over it, and no Take control (Teams offers none for a camera share).
  - Measured on linuxlt (2026-11-18) with a v4l2loopback test camera fed a turned whiteboard with marker strokes and a synthetic presenter: edges found within about 2 s (corners within a few pixels of the drawn board), the board rectified white with the ink kept, Rotate pillarboxed, the presenter see-through over the ink; in the test meeting the processed 1280 × 720 picture went out on the screen-sharing line and stopped with Stop sharing.
- [x] Microsoft Whiteboard, PowerPoint Live, Excel Live and Annotate: content-sharing sessions, as Teams (docs/spec/content-sharing.md; TASK-0214): Start Whiteboard, the recent decks and workbooks and Browse OneDrive start them; the stage hosts Whiteboard, PowerPoint for the web or Excel for the web as every participant does.
- [x] Sharing again in the same call (TASK-0324, 2026-11-26): each share (and each camera start) is a new sender on the same line, and OST started its RTP sequence numbers over from the same value every time. SRTP then reused packet indexes it had already sent and the meeting's processor dropped the packets, so a second share in a call never reached anyone (OST Test 3 showed an empty content tile, Teams on the web no share at all; the roster said sendonly). A line now keeps its RTP numbering and timestamp clock across its senders (`webrtc_video::RtpLine`), as a WebRTC sender does when its track is replaced; the SRTP sender counts a rollover from the last sequence number it protected (RFC 3711's packet index), not from seeing 65535, so a wrap whose packets were dropped unsent still counts. A camera that was on while waiting in a lobby was lost when the lobby let us in: the processor moves the call to a new media session, which found the camera busy; the old session now lets it go first. Checked OST to OST on linuxlt the same day: Standout (window share), Reporter with "Futuristic room" (the background, the content and the cut-out presenter composited at OST Test 3), Annotate (OST Test 3 got the annotation layer, "A participant started annotations…"), and Take control of a shared screen (Available / AvailableAck, request, accept, Ack: OST Test 3 controlling).

## 10. While presenting
### Sharing control bar (presenter toolbar window, module 827897; layouts `presenterToolbar` / `presenterToolbarMinimized`)
- A separate top-level window titled "Sharing control bar". It opens when `isScreenSharingOn` turns true (call-monitor service 459205) and closes when sharing stops or the call ends. Draggable (`enableDraggablePresenterToolbar` true).
- **Expanded**, left to right:
  1. drag handle (aria "Dragger"; arrow keys move it 20 px)
  2. indicators: Recording, AI interpretation, duration
  3. Camera, Mic (no ▾)
  4. Give control, Share sound, Optimize, Layout, Annotate
  5. Chat, People, More
  6. Pause (only with `enableScreenSharePauseResume`; off live)
  7. "Stop sharing"
  8. Pin
  - Grouping is AlwaysKeep, template Inline, no slot grouping, **no tooltips**.
- **Minimized**: handle, badge "You're sharing your screen" / "You're sharing a window" / "You've paused sharing", then the text button "Stop sharing" (+ Pause). Hovering or clicking the badge expands it.
- Sizes:
  - Expanded: height 55. Width = content + 22, max 790 minus a compensation for each hidden button (video 56, mic 56, give control 70, annotate 56, share sound 70, optimize 56, layout 56, people 56, chat 56, plus 100 when the share didn't start from a chat). Never wider than 90% of the screen.
  - Minimized: 297×35 (+143 wide when paused).
- Position: centred on the shared screen, 8 px from its top (5 px minimized), never above the work area. Remembered per call (`setPresenterToolbarPosition`, saved after a move of more than 5 px).
- Auto-minimizes after `draggablePresenterToolbarTimeoutInMs` 4000 ms, unless hovered, focused or pinned. Fades in after 150 ms.
- Pin aria: "Pin toolbar" / "Unpin toolbar". Announcements: "Sharing control bar is pinned." / "…unpinned."
- Ctrl+Shift+Space (global) expands and focuses it, announcing "Entering Sharing control bar. To bring Sharing control bar back, use Shift + Ctrl + Space".
- Buttons:
  - **Give control** → "Take back" while someone else has control.
    - Opens a searchable list: "Give control of your screen to" / "Give control of your window to".
    - Give: `screenSharingGiveControlRequest(userId)`. Take back: `screenSharingTerminateControlRequest`.
    - Disabled in Side-by-side or Reporter ("Unavailable with this layout."), during multi-share, by policy, or when no viewer can control ("Participants are not allowed to control the shared content").
    - With PowerPoint slide control it becomes a menu: "Of your window" / "Of your slides".
  - **Share sound**: "Share system sound is on" / "…off".
  - **Optimize**: "Optimize for video content is on" / "…off".
  - **Layout**: radio menu of the 4 presenter modes → `setSharingUpdateLayout`.
  - **Annotate**: presenter or organizer, whole-screen shares only (`sharingSourceType=="Monitor"`).
  - Flags: `enableGiveControlInPresenterToolbar`, `enableShareSystemAudio`, `enableAplT2`, `enableHighMotionScreenSharingButtonInUbar` (all true).
- The red border around the shared screen is not drawn by JS. It is presumably native (unverified).

### Viewer side (ScreensharingControlButton `Zw`, contextual group)

| state | label / behaviour |
|---|---|
| NotInControl | "Take control" (tooltip "Take control of the presentation"). Dialog "Request control?" / "You'll control the content the presenter is sharing." [Cancel] [Request] → `screenSharingRequestControl` |
| RequestSent | "Waiting for approval" (disabled) |
| InControl | "Stop control" → `screenSharingReleaseControl`, announces "Screen control has been stopped" |
| Disabled | "Requesting control is disabled by the sharer company's administrator" |
| NotControlCapable | hidden |

- Sharer alert (523673): "Presenter mode" / "{{displayName}} is requesting control." [Give control] [Deny]. Afterwards: "{{displayName}} has control." [Take control].
- Viewer messages: "You have been given screen control", "You didn't get control" / "Your request for control wasn't accepted.", "The person sharing took control back."

## 11. Compact view ("Meeting compact view", call-monitor service 459205; views 657347)
- Desktop modern monitor (`enableModernCallMonitor` true).
  - When the **call window is minimized** (becomes not visible), a separate always-on-top window opens, titled **"Meeting compact view | {title}"**. It closes when the call window becomes visible again.
  - OST (TASK-0326): X11 reports the minimize; a Wayland client is never told (KWin, GNOME and Hyprland only stop drawing the window), so there the call window counts as minimized while it isn't exposed (Qt: xdg-shell `suspended`, or frame callbacks that stopped; `WindowTool.exposed()`, checked every 250 ms in a call). A window that is only covered stays exposed (KWin), as Teams keeps the compact view away then. On Wayland with a layer shell (Plasma, Hyprland, Sway) the compact view is a layer-shell surface at the work area's bottom right over other windows (dragged by its title bar through its margins; Minimize puts it away until the meeting window shows again); GNOME has no layer shell, so it is an ordinary window there; "Maximize meeting window" activates the meeting window, which brings it back.
  - Not shown if the user turned on "Hide Call Monitor when minimizing meeting window".
  - After 4 minimizes, a "Don't need the floating window?" prompt offers [Hide window] (211532).
  - When a local share stops, the call window is shown again.
- The in-app floating monitor for navigating away inside the main window is used only on web / single-window mode (`showCallMonitorOnWeb` false). On desktop the call has its own window (unverified whether the in-app monitor ever shows on desktop).
- Views:
  - Default `callMonitorDefaultView` "MultiParticipant": a horizontal gallery of up to 4 tiles ("speaker only" = 1 tile).
  - While I'm sharing: a vertical Gallery (my share preview + my video).
  - Lightweight speaker line: "{{name}} is speaking" / "You are speaking" / "Nobody is speaking" (500 ms debounce).
  - The preference is saved in localStorage `callMonitorPreferredView`. Gallery size goes through `updateUserExperiencePreferences`.
- Sizes:

  | mode | size |
  |---|---|
  | Simple | 304×247 |
  | Lightweight | 334 wide (382 with Pop out) × 120 |
  | Gallery | 192 wide; height = segments + 78 (default 180) |
  | Horizontal gallery | tile height ≤ 170; window ≥ 334+12 wide |

  Placed bottom-right of the work area with a 30 px margin (or on the shared screen), capped at 75% of the screen. The last position is kept.
- Title bar: title; view switch "Show only active speaker" / "Show more people" (or a menu: Show only speaker / Hide videos / Show videos / Show more people); "Minimize"; **"Maximize meeting window"**, which shows the call window again (`navigateToMainWindow`).
- Toolbars (no labels, no ▾):

  | layout (`KQ`) | used when | controls |
  |---|---|---|
  | callsMonitorForParticipant | Simple, not sharing | Camera, Mic, Share, Leave |
  | callsMonitor | Simple, sharing | Camera, Mic, People, Share (+Recording, Duration) |
  | lightweightCallsMonitorForParticipant | Lightweight / horizontal gallery, not sharing | Camera, Mic, Share, Pop out, Raise, React, People, Leave |
  | lightweightCallsMonitor | as above, sharing | same, without Leave |
  | lightweightSpeakerOnlyGallery | speaker-only | Camera, Mic, Share, Pop out, More (React, Raise, People), Leave |
  | callsMonitorGalleryForParticipant / callsMonitorGallery | vertical gallery, not sharing / sharing | Camera, Mic, Share, Leave / Camera, Mic, People, Share |
  | callsMonitorPstn / lightweightCallsMonitorPstn | PSTN | Mic, Leave |

  The window title string is `calling_call_monitor_window_title`.

## 12a. Test call (Settings ▸ Devices ▸ Make a test call; measured on winpc, 2026-11-16) — TASK-0141
- **The button** (`start-echo-bot-call`): a Fluent outlined button, 149.7 × 31.3 (padding 5 12, radius 4, #D1D1D1 hairline, 14/600 #242424), its 20 px glyph (a person in a frame with a phone: `M10 11a2.5 2.5 0 1 0…`) 12.7 in; in the Audio settings card 30 under Automatically adjust mic sensitivity, 12 left of the card's text, 30 over the divider.
- **What it does** (CallingEchoBotCallService, module 527114): makes sure the 1:1 chat with the Echo bot (`28:cf28171e-fcfd-47e4-a1d6-79460b0b3ca0`, "Echo") exists (`POST /v1/threads` `{members: [me, bot] as Admin, properties: {threadType: chat, fixedRoster, uniquerosterthread}}` → `19:<my oid>_cf28171e…@unq.gbl.spaces`), starts a **group call** in it (calling intent context EchoBotCall, outgoing video and audio on, no pre-join; scenario CreateUserInitiatedTestCall) and adds the bot (handleAddParticipant). Disabled when a transport companion device is selected.
- **The call window** (856 × 537, titled "Echo"): the meeting bar (with New meeting controls: Mic, Camera, Share | React, Copilot, Controls, More | Leave — no Chat or People), the bot's tile with its square agent avatar (200 × 200, radius 4) and "Echo", your own tile at the bottom right (245 × 137). The camera starts on. The bot says its prompt, records you after the beep and plays it back; it then leaves (about 20 s after joining) and the call ends.
- **The results** (post-echo-bot-screen, "Post EchoBot Calling Screen" region, on #F5F5F5): a 500-wide list centred in the window (vertically centred when it fits): Microphone, Speaker, Camera, Network, rows 15 apart — each 48 (padding 0 10) + 16 + a #D1D1D1 hairline + 10; the filled glyph (MicSpeaking with Teams' #A6A7DC dot, Speaker2, Video, Wifi1; 20 px) at 10, 4.7; "Microphone - <device>" (14/20; the selected device's label) at 40; under it "Connected" or each problem (14 px, red #BC2F32); at the end (24 in, 8 down) a 14 px CheckmarkCircle (#0E700E) or Teams' warning triangle (#C4314B). 30 under the list: Close and Show Device Settings (outlined, min 96, 30 apart, centred).
  - Problems (Teams' echoBotReport, calling_echoCallReport_*): from the call's bad quality events — speaker/mic not functioning or silent "Didn’t work", muted "Muted", no devices "None found", permission "Teams needs permission to use this device", reconnect/no network "Call drop detected", poor send/receive "Poor connection", camera start failure/freeze "Didn’t work" — then at the end: no camera "None found", mic or speaker still muted "Muted". Measured: muted mic gave "Microphone - Microphone (HD Pro Webcam C920) (046d:082d)" / "Muted".
  - Show Device Settings opens Teams' Device settings pane (350.8 wide; under the list when the window is too narrow, the region then scrolls) and reads Hide Device Settings: "Device settings" (16/700), "Audio Settings" (14/600) — Speaker, Microphone (12 px labels over 308 × 30 dropdowns), Spatial audio, Noise suppression with Background noise only / Voice isolation — "Video Settings": Camera, Mirror my video, Adjust brightness, Soft focus. Close closes the window.

**OST** (`signaling::create_echo_call` + `invite_echo_bot`, `outgoing::start_test_call`, `calling::echo_report`, TestCallReport.qml, TestCallDevices.qml): the button with Teams' glyph and place; the bot chat made as Teams does; the group call with scenario `UserInitiatedTestCall`, camera on when there is one (Settings ▸ Devices' preview lets go of it); the bar without Chat, People and Apps (Teams' classic test-call bar, measured 2026-11-18: Raise, React, View, Controls, Copilot, More), Copilot there opening its pane at once; the bot kept in the roster as "Echo"; the call ends when the bot leaves; the report from OST's own measurements (mic giving no sound while on for 5 s "Didn’t work", network strength Bad for 3 s "Poor connection", no devices "None found", no camera "None found", muted at the end "Muted") with the devices' names; Teams' results screen, Device settings pane (Spatial audio left out, as in Settings) and Close. Harness `--test-call-test`.

**The Echo bot's avatar** (read from Teams desktop's DOM in the test call, 2026-11-18): any `28:` participant is a bot (`isBot`), and its tile shows Teams' agent avatar (`data-testid="agent-avatar"`, the same size as a person's: 200 on a whole stage): a Fluent square avatar (radius 4 = borderRadiusMedium, overflow hidden, shadow4 `0 0 2px rgba(0,0,0,.12), 0 2px 4px rgba(0,0,0,.14)`) holding the picture as a squircle (`border-radius: 50%` with `corner-shape: squircle`, i.e. a superellipse of exponent 4; 28.56% radius where corner-shape isn't supported), on colorNeutralBackground2 (#FAFAFA), with a 1 px colorNeutralStrokeAlpha (rgba(0,0,0,.05)) outline at -1 offset. The Echo bot has no picture of its own, so Teams draws its default bot image (module 961014: the white `<··>` mark on #3C97E4, 300 × 300). OST: `BotAvatar.qml` for every `28:` tile, with that image (`assets/illustrations/default-bot.png`).

**The report's causes** (Teams' `addDescriptionForQualityEvent`; the events come from its native stack, whose rules Microsoft documents for Azure Communication Services as User Facing Diagnostics): microphone or camera permission refused (AudioCapturePermissionDenied / VideoCapturePermissionDenied → "Teams needs permission to use this device"; OST says "OST needs permission to use this device"); a device that fails to start (DeviceCaptureNotFunctioning, DeviceRenderNotFunctioning, VideoCapturerDeviceStart*: "Didn’t work"); the camera giving no frame for more than 5 s (VideoCaptureDeviceFreeze: "Didn’t work"); the network disconnected (NetworkReconnect "Bad", NoNetwork: "Call drop detected"; a lost media path alone is only "Poor" and isn't reported). OST (`calling::device_health`, `echo_report::Watch::devices`): the audio and camera code note each open (EACCES / "Permission denied" is permission, any other failure didn't work; a camera you may not open is still listed, by its sysfs name), every camera frame, and the watch checks each second for a frozen camera (5 s) and for a default route (IPv4 or IPv6, not loopback): none is a call drop.

## 12. Call ended
- **Call quality survey** (UI 691083, logic 527114). Live `callQualityFeedbackUxStyle` = "ThumbsCombined", so **thumbs, not stars**.
  - "How was the call quality?" ("How was the screen share quality?" for a share started from chat), with [Had issues] (rating 1) and [Good] (rating 5).
  - Issue categories (Audio / Video / Screenshare / Live Captions) on the same page, with [Send feedback], [Dismiss] and "Privacy statement".
  - Rating 5 submits immediately; the thank-you shows for 3 s. Auto-dismiss after 60 s.
  - `submitCallFeedback` / `cancelCallFeedback`.
  - Sampling (`samplingRatesForCQF`, desktop): 1:1 0.1, group 0.1, meeting 0.1, share-from-chat 0.1, streaming 1, PSTN 0, interop 0. Needs `enableDesktopPostCallCQFForCallingAndMeetings` (true).
- **Short call**: you hung up and the call lasted under 5000 ms (call) or 8000 ms (meeting), sampled at 1.0. Prompt: "We noticed your call was pretty short. Can you let us know why?", "Call ended: {{duration}}" / "Meeting ended: {{duration}}" (246648).
- **Rejoin** screen (29382) only after abnormal ends: reconnect failed, removed, not admitted, breakout room closed. Buttons "Rejoin" / "Rejoin meeting" / "Call back" / "Try again" (`hideRejoinButton` false).
  - Anonymous end screen (428492): "Did you leave by mistake?" / "Rejoin the call".
  - "Call was answered elsewhere" (729518).
  - Follow-up card "Pick up where you left off" / "Join again" / "Schedule meeting" (611318; conditions unverified).
  - A normal leave closes the call window (plus the survey when sampled).
- **The retry screen** (`calling-retry-screen`, bundle components-calling-retry-screen; states in 527114 `pRe.props`), measured live on winpc 2026-11-10 with the second test account denying and removing Teams (CSS px, window 1266 × 673):
  - Why: the service ends the call with `callEnd {code: 0, subCode}`: 5854 DeniedInLobby → `DeniedFromLobby`, 5855 TimedOutInLobby → `NotAdmittedForLongTime`, 5000 RemovedFromConversation / 5300 RemovedFromCall → `KickedFromMeeting` (in a call, `KickedFromCall`). All three confirmed live from OST's own log; the lobby times out after 30 minutes unadmitted.
  - Where: denied or timed out, the "Meeting join | …" (pre-join) window turns into it; removed, the meeting window does, toolbar and all.
  - Layout: #F5F5F5; one column centred under the title bar (20 px side padding): the alert (title, then the description 15 under it), 30 px, the buttons.
  - Title: 18/600 #252423, line 25.7; with an icon, the icon is 24 px (Fluent regular) and 15 px before the text.
  - Description: 14/400, line 20.
  - Buttons 8 apart: Dismiss (`calling-retry-cancelbutton`, 96 min × 31.3, padding 5/12, 14/600 #242424, 0.67 px #D1D1D1 border, radius 4, transparent), then the retry button (`calling-retry-rejoinbutton`, same size, #5B5FC7, white).
  - Texts: denied — prohibited icon, "Sorry, but you were denied access to the meeting.", Dismiss only. Not admitted — "Sorry, no one has responded to your request to join. Please try again.", Rejoin (`calling_rejoin_call`; Teams rejoins straight into the lobby, `isRejoiningLobby`). Removed — "Removed from the meeting" / "Someone just removed you from the meeting. You can try to rejoin.", Rejoin (`calling_callFailed_rejoin_meeting`).
  - Rejoin joins the same meeting again without the pre-join screen (`retryCall`); for a lobbied meeting that is the lobby again.

## 13. Keyboard shortcuts in calls (Windows key map: class `P` in 504800; names in 790959)

| keys | action | notes |
|---|---|---|
| Ctrl+Shift+M | Toggle mute (`ToggleMuteCurrentCall`, app-wide) | |
| Ctrl+Space | Temporarily unmute (push to talk) | |
| Ctrl+Shift+O | Toggle video (`ToggleVideoCurrentCall`, app-wide) | |
| Ctrl+Shift+K | Raise or lower your hand | |
| Ctrl+Shift+E | Toggle share content tray | |
| Ctrl+Shift+H | Leave meeting or call (`LeaveCall`, app-wide; skips the leave confirmation) | |
| Ctrl+Shift+Space | Go to the sharing toolbar | global (OS-wide) |
| Ctrl+Shift+U | Toggle speaker | |
| Ctrl+Shift+P | Toggle background blur | |
| Ctrl+Shift+Y | Admit people from the lobby notification | |
| Alt+Shift+C | Toggle live captions | |
| Ctrl+Shift+L | Announce raised hands | screen reader |
| Ctrl+Alt+Shift+S | Announce the active speaker | `enableAnnounceActiveSpeaker` true |
| Ctrl+Shift+A / Ctrl+Shift+S / Ctrl+Shift+D | Accept video call (or screen share) / accept audio call / decline | global |
| Ctrl+Shift+J / Ctrl+Shift+R | Join from the meeting-started toast / open meeting chat from the toast | global |
| Alt+Shift+A / Alt+Shift+V | Start audio / video call | |
| F11 | Full screen | |
| Alt+Shift+ +, −, 0, arrows | Zoom in / zoom out / reset / pan shared content | |
| Alt+Shift+1…5 | Like / Love / Applause / Laugh / Surprised | `enableMeetingReactionShortcuts` unset → off |
| Ctrl+Shift+G | Visual Assist | `enableVisualAssist` false |

- Tooltips append the shortcut: `{{tooltip}} ({{keyboardShortcut}})`.
- Alternative profile "meetings_alt" (`enableShortcutProfiles`): Alt+A mute, Alt+V video, Alt+Y hand, Alt+Q leave, Alt+S share tray, Alt+H chat.

## 14. Services touched by the call window (summary)

| UI action | GraphQL operation | calling-stack method (448700/527114) |
|---|---|---|
| Join | `joinCallFromIntent(callingIntentId, joinOptions)` | — |
| Cancel pre-join | `abandonCallingIntent(callingIntentId, "DismissPrejoinScreen")` | — |
| Pre-join toggles | `setCallPrejoinState`, `updatePrejoinDevicesConfiguration` | — |
| Mic / Camera | `toggleMuteWithState`, `toggleVideoWithState`, `confirmCallToggleState`, `togglePushToTalk` | same names |
| Leave / End / all devices | `stopCall(callId, context, {forEveryone, forAllUserEndpoints})` | `stopCall` |
| Hold / Resume | `toggleHoldCall(teamsCallId, context)` | `toggleHoldCall` |
| Transfer / Consult / Merge / Park / DTMF | `transferCall`, `startConsultation`, `transferCallConsultation`, `mergeCalls`, `mergeConsultCall`, `parkCall`, `sendDtmf` | `callTransferService.transferCall`, … |
| Raise / lower hand | `toggleRaiseHands(callId, skinTone)`, `lowerOtherParticipantsHand`, `lowerAllRaisedHands` | `publishState` / `removeState` / `removeStatesForEveryone` (RaiseHands) |
| Reaction | `sendMeetingReaction` (fallback `sendMeetingReactionLiveState`) | calling service / LiveStateBroadcast |
| Roster | `addParticipant1`, `muteParticipant1`, `muteAllParticipants1`, `removeParticipant1`, `promoteAttendeeToPresenter`, `demotePresenterToAttendee`, `updateAttendeeRestrictions`, `updateCallParticipantRestrictions`, `updateMeetingLock`, `renameParticipant` | `callMuteService`, `addParticipantService`, `changeParticipantRole`, `lockMeetingsService` |
| Lobby | `admitParticipant1`, `admitAllParticipants1`, `denyParticipant` | `callLobbyService` |
| Share | `startSharing`, `stopSharing`, `tryToggleIncludeSystemAudio`, `setSharingUpdateLayout`, `screenSharingGiveControlRequest` / `RequestControl` / `ReleaseControl` / `TerminateControlRequest` | same names |
| Recording / transcript / captions | `startRecording`, `stopRecording`, `startTranscript`, `startRecordingAndTranscript`, `startClosedCaptions`, `stopClosedCaptions` | |
| Other videos | `toggleIncomingVideo(callId)` | |
| Layout prefs / toolbar customization | `updateUserExperiencePreferences{stageSettings{preferredLayout, preferredGallerySize, isMyselfInGrid, callingControlsPreferences}}`, `setCallingControlsSessionSettings` | — |
| Backgrounds | `applyVideoBackgroundEffects`, `downloadVideoBackgroundImage`; upload POST `${deepLinkDomain}/maglev/custom-video-background/upload` | |
| Feedback | `submitCallFeedback`, `cancelCallFeedback`, `openFeedbackDialog` | |

## OST status against this spec
- [ ] Toolbar order from the live `Inline` preset (§1.3):
      `[timer] … Chat, People, Raise, React, View, Controls, Notes, Rooms, Apps, More | Camera, Mic, Share | Leave`,
      with labels under 48×(48–72) px buttons and dividers per the grouping rules.
- [ ] Layout chosen per call type (§1.1). A group call uses the meeting (`default`) layout.
- [ ] 1:1 bar: no Raise, React, Notes or Rooms. Transfer, Consult, Dial pad and Hold on the bar.
- [ ] 1:1 PSTN bar: no Camera, Share or View.
- [ ] Visibility and disabled-reason rules per role and meeting type (§1.4). Notes only in private/channel meetings; Rooms only for the organizer of a scheduled meeting; Controls only for the organizer; End meeting only for the organizer or a moderator.
- [ ] Width-driven overflow into More (§1.5): AsFirst items from the right first, then React and Raise; More, Camera, Mic, Share and Leave never overflow. Overflowed items appear at the top of More.
- [ ] Clicks are suppressed for 2000 ms after the toolbar layout shifts under the pointer.
- [ ] More menu groups and items exactly as §1.8. Devices is hidden in favour of "Video effects and settings" / "Audio settings" while `enableAVFramework` is on. The Call ▸ items are flat.
- [ ] Timer format `MM:SS` / `HH:MM:SS` / `--:--`.
- [ ] Pre-join (§2):
  - [ ] classic layout, camera off by default (anonymous: on)
  - [ ] audio options in order with the wide and narrow subtitles; narrow layout below 720 px
  - [ ] cached audio choice, but Room, None and Follow are never cached
  - [ ] "Background filters" pane; tile click applies immediately
  - [ ] Join builds `joinOptions` as specified; Cancel abandons the intent
  - [ ] lobby texts "Hi, {name}. Someone will let you in shortly."
- [ ] Camera ▾ and Mic ▾ flyouts with exact sections, and the ordered disabled-reason tooltips (§3).
- [ ] Leave (§4):
  - [ ] split menu only for the organizer, a moderator, or multiple own endpoints
  - [ ] "End the meeting?" confirmation; `stopCall` flags
  - [ ] leave confirmation only while sharing, or when the user setting is on
- [ ] Hold/Resume, Transfer dialog (V2), Consult, Merge, Park (pickup code), Dial pad (§5).
- [ ] People pane (§6):
  - [ ] header actions and More actions menu with its conditions
  - [ ] section order, titles and counts; 20-row cap with "See more"
  - [ ] sort: raised hands, then self, then name
  - [ ] row icons
  - [ ] participant menu order; Remove has no confirmation
  - [ ] lobby admit/deny, Admit all, waiting toast
- [ ] Raise hand (§7): rank queue numbers, 10 s popup, People badge count, auto-lower prompt after 3 s of speaking.
- [ ] View menu items, labels and conditions (§8.1). Large gallery only on limited devices, enabled at 9 videos. Gallery size 4/9/16/49, default 16.
- [ ] Stage (§8.2):
  - [ ] default Gallery with self in grid
  - [ ] 16:9 grid-fitting algorithm with a 2 px inset; side-bar/top-bar rules; automatic gallery-at-top
  - [ ] pagination strip
  - [ ] active-speaker swap rules; pins (max 9) and spotlight (max 7)
- [ ] Reactions (§8.3):
  - [ ] 5 reactions; not in 1:1 calls
  - [ ] tile overlay for 4250 ms with size steps by tile height
  - [ ] floating overlay animation (2.133 s, easing, scale/travel steps)
- [ ] Share tray (§9, §9a–b): classic tray, Include sound, Presenter mode, Screen grid (max 4), Window drill-down, Whiteboard, PowerPoint/Excel Live; `startSharing` arguments. (Built: the tray with Teams' layout and drill-downs, Include sound, Screen/Window through the portal, presenter modes and Add background, Content from camera, give / take control, the Sharing control bar; Whiteboard / PowerPoint Live / Excel Live sessions not built; see §9b–c.)
- [ ] Sharing control bar (§10): separate window, expanded/minimized sizes, 4 s auto-minimize, pin, Ctrl+Shift+Space; Give/Take control flows on both sides.
- [ ] Compact view (§11): opens only when the call window is minimized; title "Meeting compact view | {title}"; sizes and position; per-mode toolbars without labels; "Maximize meeting window".
- [ ] Call ended (§12): thumbs survey ("Had issues" / "Good") sampled at 10%; short-call prompt; Rejoin only after abnormal ends.
- [ ] Keyboard shortcuts (§13), including the global ones and the shortcut text in tooltips.

## Headset call controls (TASK-0156; Teams' HID service, read from its bundles 2026-11-17)

- Teams opens the HID device of the selected microphone (matched by its USB ids) on the Telephony page. Its driver
  (TASK-0223, `hidDeviceDriverFactory` with the prod config `useUCQToAssignDeviceDrivers`, `consolidateDrivers`,
  `allowHookByVendorId`):
  - devices on `hidDevicesBlacklist` (047f:af08/c002/ca00/da41, 0b0e:235e/24ed/a346, 046d:0a38/0a3a,
    291a:3301/3523) get none ("UnSupported");
  - a device with a UCQ string gets "Standard Hook Protect USB". Teams' native HID layer answers `property("UCQ")`
    with HidD_GetIndexedString of USB string descriptor 0x21 and, with `consolidateDrivers`, takes any text there
    (the UCQ positions 4 speakerphone, 5 handset, 6 headset, 11 wireless only pick the variant without it);
  - without one: EPOS, Microsoft, Plantronics, Jabra, Polycom, Yealink, Bose, Sony, Cisco, Bang & Olufsen,
    AudioCodes, Anker, Sennheiser, Onward, Shure and Legrand devices still get it, and so do Logitech, HP, Lenovo
    and Dell products it names (H650e, Rally, Slice, HUB500, BT100…); any other device gets "Safe Mute Only" (the
    mute button only).
  - OST reads string 0x21 the same way through the HID class: HIDIOCGSTRING on the device's hiddev node (falling
    back to a control transfer on its usbfs node). Hook protection lasts 1100 ms (prod `hookProtectionTimeoutConfig`).
- Buttons, with Sync device buttons on:
  - Hook Switch 1 (off hook) while a call rings: answer. Hook Switch 0 (on hook) in a call: hang up (ignored while
    ringing and for 1 s after the device or Teams took it off hook or toggled mute: Teams' hook protection).
  - Button page usage 7 while ringing: reject. Flash: answer while ringing, else hold or resume.
  - Phone Mute (relative: toggle; absolute: set): mutes or unmutes the call, or the pre-join screen's mic; ignored
    with no call and no pre-join screen.
  - The Teams button (vendor page 0xFF99 usage 4): Teams asks the device for its context over ASP (feature report 0x9A:
    Version → protocol 1, Feature → event mask, Context → event and press). Short press: a missed call opens Calls
    (Teams pushes MissedCall to the device), else Teams (and an ongoing meeting's window) comes forward; long press in
    a meeting: raise or lower your hand. Without ASP the Teams button does nothing.
- Lights: Off-Hook while a call is connecting or up, Ring while one rings, Mute with the call's (or the pre-join
  screen's) mute, Hold while held; all off when the call ends.

## Bluetooth (HFP) headset call controls (TASK-0223; Teams' HfpVoipCallCoordinatorImpl, Windows' BTAGService)

- Teams doesn't read a Bluetooth headset. Windows' audio gateway (BTAGService) speaks HFP with it; Teams reports its
  calls to Windows' VoIP call coordinator: a ringing call (reportIncomingCall: the gateway sends RING and
  +CIEV callsetup), an answered call as it connects (reportCallAccepted), a placed call (requestStartCall) and its
  connection (reportOutgoingCallConnected), hold (reportHoldCall) and the end (reportCallEnded).
- The headset's commands come back as the coordinator's events: ATA answers (AnswerRequested), AT+CHUP rejects a
  ringing call (RejectRequested) or ends the call (EndRequested), AT+CHLD holds. Windows 11 carries the mute in the
  microphone gain: AT+VGM=0 mutes and a gain back above 0 unmutes (HfpAtVgmReceivedExpectMuteChange; the first gain
  only sets the baseline), and Teams' own mute sends the headset +VGM: 0 (HfpAtVgmSentMuteChange).
- Teams acts on them only with Sync device buttons on (isHFPDeviceSyncEnabled), with a Bluetooth hands-free
  microphone selected (its connection type Bluetooth) and with one such device present (multi-device mode off);
  otherwise it fails the action and the gateway answers ERROR. Mute from the device acts on a call.
- OST: PipeWire's native HFP backend is the gateway. It takes ATA and AT+CHUP to the calls of a ModemManager modem
  at ModemManager's name on the system bus; OST offers its calls as one (ModemManager's Modem, Modem3gpp, Voice and
  Call interfaces). On stock PipeWire that takes desktop/packaging/install-hfp-calls.sh: WirePlumber's
  `bluez5.hfphsp-backend-native-modem = "ost"` (default "none"), a D-Bus system policy letting the user own
  `org.freedesktop.ModemManager1`, and ModemManager not running (it holds the name for good; the script disables it
  when it has no modem, after asking). OST shows the modem, and takes Accept/Hangup, only from the user's own
  PipeWire gateway (WirePlumber, by its connection's uid and process); other system clients see a ModemManager
  without modems. contrib/pipewire's patch (`bluez5.hfphsp-backend-native-modem-bus = "session"`) is the other way;
  OST offers its calls on both buses. PipeWire turns AT+VGM into the headset microphone's volume and a route volume
  into +VGM, so OST's mute zeroes that gain and unmuting puts it back. Only the OST that has the headset's buttons
  ("Transfer controls to this app") offers its calls.
- Without that setup PipeWire never reads OST's modem (its org.pipewire.Telephony service is for PipeWire as a
  phone's hands-free side). Then answer and hang-up aren't offered and nothing is shown, as Teams shows nothing where
  the platform lacks call control ("Platform not supported" in its log); OST logs why, and the gain-based mute still
  works.

