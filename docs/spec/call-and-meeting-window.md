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
  "centred" design (preset 1). The template names are Anchor, Inline,
  InlineCentered and Stacked (`GI`).
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
| 10 | | **MeetingDetailsButton** | Notes | "Open notes"/"Close notes" | `calling_meeting_details_icon_label` |
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
  - Spatial audio shows only when the media stack can render it (`isSpatialAudioAvailable`).
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
  - Then the Help app's header (entity-header, 61 tall, a 0.67 #E0E0E0 line): the app's tile (32, round, from its app definition, id 5a0e35f9-d3c8-45b6-9dd9-983ab47f1b83) 20 in, "Help" (18/25.71 bold) at 72, and "More Help actions" (32 × 31.33, 7 from the right): Reload app, then (TASK-0072) About and Share app.
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
- **Agenda and Run of Show** need Teams' Facilitator (Copilot); without it (as in the test tenant: `groupCopilotDetails.enabled` false) Teams shows neither and OST keeps their shared state untouched (TASK-0073).
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
  - The send limit stays "--" until OST has a send-side estimator.

### 1.9 Call timer (CallDurationIndicator, `tp`, module 414673; format 494225/877513)
- Start time comes from `callStartTimestamp(teamsCallId)`. It ticks every 1000 ms.
- Format `MM:SS`, becoming `HH:MM:SS` once hours > 0. Every field is zero-padded to 2 digits.
- Shows `--:--` before the start time is known.
- Tooltip "Elapsed time"; aria "Elapsed time {{elapsedTime}}".

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
    - "Spatial audio" (only applies to non-P2P calls; `setSpatialAudio`).
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
- Toast (512425): "Waiting in the lobby", "{{name}} +{{n}}".
  - 1 person: [Deny] [Admit] plus "More info", which opens the roster.
  - More than 1 person, or impersonation suspected: [View Lobby].
- Services:
  - `admitParticipant1(teamsCallId, participantId, entryPoint, markedAsNotBot)` → `callLobbyService.admitParticipant`
  - `admitAllParticipants1(teamsCallId, participantIds)`; the list is empty when `enableLobbyAdmitAllScopeAll` (true)
  - `denyParticipant(teamsCallId, participantId)`; Deny all sends one per person
- Failsafe 100 s. The XL lobby list refreshes every 5 s.

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
- Tiles without video show the avatar.

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
- [ ] Share tray (§9): classic tray, Include sound, Presenter mode, Screen grid (max 4), Window drill-down, Whiteboard, PowerPoint/Excel Live; `startSharing` arguments.
- [ ] Sharing control bar (§10): separate window, expanded/minimized sizes, 4 s auto-minimize, pin, Ctrl+Shift+Space; Give/Take control flows on both sides.
- [ ] Compact view (§11): opens only when the call window is minimized; title "Meeting compact view | {title}"; sizes and position; per-mode toolbars without labels; "Maximize meeting window".
- [ ] Call ended (§12): thumbs survey ("Had issues" / "Good") sampled at 10%; short-call prompt; Rejoin only after abnormal ends.
- [ ] Keyboard shortcuts (§13), including the global ones and the shortcut text in tooltips.
