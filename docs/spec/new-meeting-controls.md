# New meeting controls — Teams desktop behaviour (spec)

Measured on winpc (Teams 26276.513 build line, signed in as ost-test1) on
2026-11-16, through the WebView2 debugger only (DOM, React context, element
pictures of the controls; camera and mic off; a solo Meet now from the
Calendar, left afterwards). Teams' code was read in the saved client
bundles. TASK-0155.

## 1. The setting (Settings ▸ General ▸ Meeting)

- The Meeting card (790 wide, card at 468) holds two rows:
  1. **New meeting controls** (14/20 #242424) with the sublabel **"Meetings
     are easier than ever with a simplified, organized, and intuitive
     experience."** (12/16 #616161) and an On/Off switch whose top is level
     with the title (title 68.7, sublabel 88.7, switch 68.7 in the card).
  2. **Ask me to confirm when I leave a meeting** (title 127.7, switch
     119.7), 59 below the first row's title.
- Strings: `teamsLabs:new_meeting_controls_feature_name`,
  `teamsLabs:new_meeting_controls_feature_description`.
- **What it is.** A Teams Labs feature, id
  `32b3a453-8695-4f73-8d60-dd39887ceabf`, named by the calling ECS setting
  `meetingSettingsUbarRevampTeamsLabsFeature.featureId`. The row
  (`general-meeting-new-controls-setting`) shows only when
  `enableTeamsLabs || enableTeamsLabsService` (live: false / true) and the
  feature exists; its title and sublabel are the feature's assets; the
  value is the feature's `enabled`; it is disabled when the feature can't
  be toggled.
- **Where it is saved: on the device, not synced.** The Teams Labs service
  keeps feature states in the browser Cache Storage
  `teams-labs-service-cache-storage`, keys
  `https://teams.microsoft.com/feature-<id>` ("true"/"false") and
  `…/revision-<id>` (live "true" and "0"). The feature's mode is `OptIn`
  (ECS `teamsLabs.<id>.configuration.mode`): off by default; turning it off
  clears both keys (`n === (mode === "OptOut")` → clear). Nothing is sent to
  a service. A stored revision older than ECS's resets the choice.
- **What on means.** The feature carries ECS overrides that Teams applies
  live (`calculateAndNotify`):
  - calling: `ubarLayoutSetup` **InlineCentered**, `enableUbarSlotGrouping`
    true, `enableUbarCustomization` true, `showRaiseHandInReactionMenu`
    true, `enableIndicatorOverflowInUbar` false,
    `enableUbarControlExtendedStates` true,
    `enableUbarMultiModalAiSplitControls` true,
    `enableAiInterpreterSplitButton` true,
    `enableReactionsPersistentFlyout` true;
  - extensibility: `maxHorizontalAppsCountInMeeting` 0,
    `maxPrimaryOverflowAppsCountInMeeting` 99999 (no app buttons on the
    bar).
- **Turning it off** opens the feature's opt-out action, Teams' RDX survey
  (`feedbackType MEETING_CONTROLS_THUMBS_DOWN`, `featureArea
  NEW_MEETING_CONTROLS`): "Submit feedback to Microsoft". Never submit it.
- The pre-join screen does not change (no pre-join code reads these
  settings; measured: same layout as §2 of call-and-meeting-window.md).
- Leaving a meeting with the setting on logs `MeetingLeaveRevamp`
  (telemetry only).

**OST:** the setting is `newMeetingControls` in OST's local settings (as
Teams: this device only, off by default). The call window reads it when it
opens and whenever it is activated. Turning it off opens OST's feedback
form ("Report a problem", area "New meeting controls"), which goes to OST's
GitHub (feedback-and-help.md).

## 2. The layout: `ubarLayoutPresets[1]` (InlineCentered)

The preset is unchanged since 2026-11-06 and is kept in
`src/calling/ubar_layout.json` as `centered`. The per-call-type
`ubarLayoutOverrides` are the same as for the current layout.

Groups, in order:

| group | strategy | items (slot horizontalMiddleEnd unless noted) |
|---|---|---|
| indicators | | as today (shield, AI, recording, timer…) |
| primary | (layout's) | **Mic, Camera, Share** (Docked, critical), Pause share, Volume |
| secondary | MergeWithNext, customizable (All) | **React** (AsLast), Raise (AsLast), **Chat**, **People**, BizChat/MeetingCollab/OneCopilot (Copilot), **Controls**, Yammer Q&A, Broadcast Q&A, CallContext |
| contextual | MergeWithNext, customizable (All) | Transfer during consult, **Dial pad**, **Hold**, Upgrade, Consult, Transfer, Transfer ▸, Merge, Take control, Whiteboard/PPT, MR toolbar, Annotation, Stop spotlight, **Pop out**, Together mode |
| overflowAndHoisting | MergeWithPrevious | **More** (Docked) |
| callControls (slot **horizontalEnd**) | | **Join room**, **Return**, Follow, Staging start/end, Agent state, **Resume**, **Leave** |

More holds two sections:
- `collaborationCommunication` (rendererLibrary **MenuGridControls**,
  AlwaysKeep, DragOnly): Park, SLA lock, **Record**, **Transcribe** (▸
  Transcript), Facilitator, Interpreter (AI for all), Live interpretation,
  **Timer**, Meeting notes, **Notes** (MeetingDetailsButton), **Captions**,
  Whiteboard, **Rooms**, **RTT**, Shared, Coach, Insights, app tabs, **Apps**
  (Docked, "button" template).
- `overflowSecondaryControls` (MenuVerticalControls): **View ▸**
  (grid / screen / videocontrols), Streaming ▸, **Join info ▸** (Meeting
  info, Call me, Call health), **Settings ▸** (settingsMenu1: Privacy mode,
  Backgrounds, Meeting options, **Accessibility settings**; settingsMenu2:
  **Chat bubbles**, Hide controls, **Hide me**; settingsMenu3: **Video
  effects and settings**, Backgrounds, **Audio settings**, Devices, **Optimize
  for room**, Voice isolation, Music mode, Yammer; settingsMenu4: Data),
  Restart event, Extend to room, Music mode, Yammer, Report a problem,
  **Report a concern**, **Help**.

Raise is not on the bar: with `showRaiseHandInReactionMenu` it is in
React's menu. (Bold: what Teams showed in the measured meeting, or what OST
shows.)

### Measured bar (Meet now, organizer, 1280 wide; window 856 the same set)

`[shield][AI][00:55]   [Mic ▾][Camera ▾][Share] | [React][Chat][People][Copilot][Controls][More]   [Leave ▾]`

- Bar 60 tall, white, 0.67 bottom border #E0E0E0, `data-layout`
  InlineCentered.
- Indicators toolbar at 8, 113.1 wide (shield 30, AI 37.3, timer slot
  45.8).
- The middle slot runs from the indicators' end + 4 (125.1) to the end
  slot − 4; its controls are **centred in it** (at 1280: content 378.1 to
  935.1, centre 656.6 = the slot's centre).
- Slots as today: buttons 48 × 48 at 6 down in 56 px slots (4 either side);
  split buttons 74 (4 + 48 + 22, no right margin); the divider 17 (a 0.67
  × 33 line 8 in, 13.5 down). Labels 11/16.
- Only one divider, after Share (primary has three; More's group of one
  merges, MergeWithPrevious).
- End slot 74 wide, 14 from the window's right: Leave (48) and its 22 px
  chevron ("More options": Leave / End meeting, as today).
- Glyphs (25 px, all #424242 at rest; Leave's label #242424): MicOff /
  Mic **regular**, VideoOff / Video regular, ShareScreenStart regular,
  **EmojiHand** regular (React; EmojiHand filled in brand #5B5FC7 while your
  hand is raised, `reaction-menu-button-hand-raised`), Chat, Person,
  CopilotIcon, ShieldWithGear (Controls), MoreHorizontal, CallEnd filled
  #B10E1C.
- Tooltips: Mic "Unmute mic (Ctrl+Shift+M)", chevron "Open audio options";
  Camera "Turn camera on (Ctrl+Shift+O)", "Open video options"; Share
  "Share content (Ctrl+Shift+E)"; React **"React or raise your hand. Your
  hand is not raised"** / "React or lower your hand. Your hand is raised"
  (240 wide, two lines); Chat "Show conversation"; People **"Show
  participants"** (no count); Copilot "Open Copilot (Alt+C)"; Controls none;
  More "More actions"; Leave "Leave (Ctrl+Shift+H)". Customizable controls
  add "Has context menu" for screen readers.

### Narrow windows (widths emulated 1280 → 360)

- Overflow is Fluent's, as today (10 px kept free; lowest priority first,
  the last in bar order on ties): **Controls** goes first (at 760),
  **Copilot** (720), **People** (660), **Chat** (600), then **React** (540,
  AsLast). Mic, Camera, Share, More and Leave never go.
- What overflowed heads More's grid, in bar order (Chat, People, Copilot,
  Controls ▸ at 600).
- **Under 480 px the bar turns compact**: 40 tall; buttons 32 × 32 at 3.7
  down without labels, icon 20 at 6; 36 px slots (2 either side); split
  buttons 54 (2 + 32 + 20, chevron glyph 12 at 4, 10); the divider 9 (line
  4 in, 21.6 tall at 8.9); end slot 54. Indicators shrink: shield 22 × 22
  with a 14 px glyph at (12, 12.7), AI 24.9 × 22 (pill 19.6 × 14), timer
  12 px; the middle slot starts at 92.1.

## 3. More (`callingButtons-showMoreBtn-menu`)

- Surface 309.3 wide, padding 12.67, radius 4, shadow 2 / 8×16;
  **start-aligned** under More 5.3 below its bottom (91.3 at 1280: More at
  883.1, surface 883.3), **end-aligned** (right edges) when it would leave
  the window (856: surface 410–719.3, More 671.1–719.1).
- The grid: 70 × 52 items in three 96 px columns from 24.7 (12 into the
  section), rows every 58 from 12.7; a 25 px glyph at (22.5, 4.5); the
  label 11/16 #424242 at 33.3. Hover #EBEBEB with #242424 ink. A split item
  (Facilitator) adds a 22 px chevron part (16 px ChevronDown at 3, 18);
  with one in the first two columns the surface is 323.3 wide.
- Items seen (organizer, Meet now): Record (RecordingMenuIcon), Transcribe
  (SlideTextEdit), Facilitator ▾, Interpreter (SoundWaveCircleSparkle),
  Timer, Notes (DocumentOnePageMultiple), Captions (ClosedCaption), Rooms
  (BreakoutRoom), RTT (SlideTextCall). Labels switch to "Recording" /
  "Transcribing" while on (`calling_ubar_*_active_button_short_label`).
- "**Get more apps and agents**": a 284 × 32 outlined button (0.67 #D1D1D1,
  radius 4, 14 px #424242 centred) 12 under the grid.
- A full-width divider (0.67, #E0E0E0) at 242.7, then the list: 284 × 32
  rows every 34 from 255.3; a 20 px glyph at 6, label 14/20 at 30, a 16 px
  chevron 6 from the end; hover #F5F5F5, the glyph brand. Rows: **View ▸**
  (TableSimple), **Join info ▸** (Info), **Settings ▸** (Settings), **Report
  a concern** (ShieldError), **Help** (QuestionCircle).
- Submenus (255.3 wide, rows 230, padding 12.67, dividers 20.67) open on
  hover to the **left** of More, their top level with the row; one that
  won't fit below **ends level with the row's bottom** (View at y 38,
  Settings at 196.7 in a 537 tall window).
  - **View ▸**: Gallery ✓ (TableSimple), Speaker (PersonCircle) | Full
    screen F11 (PageFit), Focus on content (ContentView; disabled with
    nothing shared), Show gallery at top (PanelRightGallery), Gallery size
    ▸ (SlideGrid) | Turn off other videos (VideoPersonOff), Show videos
    first.
  - **Join info ▸**: Meeting info (Info), Call me (Call), Call health
    (Pulse).
  - **Settings ▸**: Accessibility settings (Accessibility), Don't show chat
    bubbles (ChatOff), Hide me (EyeOff) | Video effects and settings
    (VideoPersonSparkle), Audio settings (SpeakerSettings), Optimize for
    room (TabletLaptop). ("Unhide me" once hidden; a section of one merges
    into the next, so no divider after Accessibility.)

## 4. React

- `reaction-menu-button-popover`: 250 × 104.7, start-aligned with the React
  button, 5.3 under it. Five 32 px reaction buttons (24 px pictures) at
  16.7, 62.8, 109, 155.2, 201.3 (y 16.7).
- Under them **Raise hand**: 224.7 × 35.3 at (12.7, 56.7), outlined
  (#D1D1D1), HandRight 24 + "Raise hand" 14/600 #424242, centred, 6 apart.
  Raised: brand fill (#5B5FC7, hover #4F52B2), white "Lower hand", a
  #C7C7C7 edge.
- The popover stays open after a reaction or Raise/Lower
  (`enableReactionsPersistentFlyout`).

## 5. Camera ▾, Mic ▾, Leave ▾, Chat, People, Controls

- The Mic and Camera flyouts are today's (§3 of call-and-meeting-window.md).
  Mic ▾ at 856: right-aligned to the chevron would leave the window, so it
  starts at the Mic slot (166) instead; 92 down (the bar's bottom).
- Leave ▾: Leave / End meeting (163.3 wide), as today.
- Chat, People and Controls open what they open today.

## 6. Arranging the controls (`enableUbarCustomization`)

- Right-click a customizable bar control (secondary or contextual group):
  a 207 wide menu at the pointer: **Move before "{previous}"** (ArrowLeft),
  **Move after "{next}"** (ArrowRight) — within its group, each only when
  there is a neighbour — **Unpin** (PinOff), a divider, **Reset meeting
  controls** (ArrowReset). Mic, Camera, Share, More and Leave have none.
- Right-click a grid item: **Pin** (Pin), a divider, Reset meeting controls.
- Unpin moves the control to the front of More's grid (Copilot unpinned:
  grid "Copilot, Record, Transcribe, Facilitator ▾ …"); Pin puts it back
  (or a grid item onto the bar); Reset restores the preset.
- Saved per client: `localStorage` "Settings"/"UserAndExperience",
  `stageSettings.callingControlsPreferences.layouts[{id, controls:[{name,
  slot, group, priority}]}]` — not synced.
- Drag and drop between the bar and More (dnd-kit) does the same (§6a).

### 6a. Drag and drop (measured on winpc 2026-11-16 by driving Teams' pointer through the debugger; Teams' unified-bar bundle) — TASK-0208

- **What moves.** A customizable bar control (secondary and contextual
  groups: React, Chat, People, Copilot, Controls…) and a More grid item
  (not "Get more apps and agents"). Docked controls (Mic, Camera, Share,
  More, Leave) don't move. Sensors: the mouse after **2 px** (dnd-kit
  `distance: 2`), touch after a 200 ms hold (tolerance 5), and the
  keyboard's arrows.
- **While dragging** (dnd-kit `DragOverlay`, z 1031): a copy of the control
  follows the pointer at **opacity 0.7** with `cursor: grabbing`, drawn by
  the renderer of the group it is over (a bar button over the bar — 56 × 60
  slot, its 48 px button in the hover fill #EBEBEB with #242424 ink — a grid
  item over the grid), tooltips off. The control itself keeps its place
  invisible, and the bar makes room where it would land (the other controls
  slide over: Chat dragged right over People → React, People, [gap], Copilot…).
- **Over More** (the button, a droppable "slot container"): "Unpin {name}".
  More shows pressed (light #D6D6D6, dark #141414) with a brand glyph, the
  copy fades to **0.4** (`transition: opacity .35s ease-out`) and the bar
  closes the gap. Dropping unpins (the control heads More's grid).
- **Over a control of its own group**: "Move {name} before / after
  {other}" — `after` when the drag has travelled right (`delta.x > 0`),
  `before` when left. Dropping reorders.
- **A grid item over the bar**: "Pin {name}" — the bar makes room for it;
  dropping pins it there (Chat from the grid dropped over People after a
  rightward drag landed after People).
- **Not allowed** (a control that can't take it, e.g. a bar control over
  Mic): the evaluator says `blocked`; the pointer shows not-allowed and a
  drop changes nothing. A drop whose copy doesn't overlap its target
  (`cancelDrop`) changes nothing either. Escape cancels.
- **Drop**: the copy animates to its place in 200 ms (`ease`), the control
  showing again at the end. Screen readers hear each step (dnd-kit
  announcements: "Move Chat after People", "Unpin Chat", "Pin Record").
- The result is saved exactly as Move / Pin / Unpin save it (§6).

## 7. Dark and High contrast (measured on winpc 2026-11-16, setting on) — TASK-0208

| | Light | Dark | High contrast |
|---|---|---|---|
| Bar | #FFFFFF, bottom 0.67 #E0E0E0 | **#292929**, bottom 0.67 #525252 | #000000, bottom 0.67 #FFFFFF |
| Glyphs and labels at rest | #424242 | #D6D6D6 | #FFFFFF |
| Hovered button (its half of a split button) | #EBEBEB, ink #242424 | **#333333**, ink #FFFFFF | #1AEBFF, ink #000000 |
| The other half of a hovered split button | **#F5F5F5** (ink stays #424242) | **#3D3D3D** | #1AEBFF |
| Leave glyph / label | #B10E1C / #242424 | **#DC626D** / #FFFFFF | #FFFFFF / #FFFFFF |
| Leave hovered / its other half | #FDF3F4 / #FDF6F3 | #3B0509 / #411200 | #1AEBFF |
| Checked (People with its pane open) | glyph and 30.8 × 2 underline #5B5FC7, label #242424 | glyph and underline #7F85F5, label #FFFFFF | glyph and underline #FFFFFF |
| Divider | 0.67 #D1D1D1 | 0.67 #666666 | 0.67 #FFFFFF |
| Timer, shield | #424242 | #D6D6D6 | #FFFFFF |
| More, React popover, right-click menu | #FFFFFF | #292929 | #000000 with a 0.67 #FFFFFF edge |
| Grid item hovered | #EBEBEB, ink #242424 | #333333, ink #FFFFFF | #1AEBFF, ink #000000 |
| List row hovered | #F5F5F5, glyph brand #5B5FC7 | #3D3D3D, glyph #7F85F5 | #1AEBFF, ink #000000 |
| More's divider | #E0E0E0 | #525252 | #FFFFFF |
| "Get more apps and agents" | #FFFFFF, edge #D1D1D1; hovered #EBEBEB, edge #C7C7C7 | #292929, edge #666666; hovered #333333, edge #757575 | #000000, edge #FFFFFF; hovered #1AEBFF |
| Raise hand | outlined as the apps button | #292929, edge #666666; hovered #333333, #757575 | as the apps button |
| A reaction hovered | #EBEBEB, the picture growing to 38.4 px | #333333 | #1AEBFF |

## 8. Meet now and group calls (TASK-0208)

- **Meet now** (Calendar ▸ Meet now, organizer, alone; winpc 2026-11-16):
  with the setting **on**, the same controls as the scheduled meeting —
  bar Mic, Camera, Share | React, Chat, People, Copilot, Controls, More,
  Leave; grid Record, Transcribe, Facilitator ▾, Interpreter, Timer, Notes,
  Captions, Rooms, RTT, Apps; list View ▸, Join info ▸ (Meeting info, Call
  me, Call health), Settings ▸ (Accessibility settings, Don't show chat
  bubbles, Hide me, Video effects and settings, Audio settings, Optimize for
  room), Report a concern, Help. With it **off**, the current bar — Chat,
  People, Raise, React, View, Controls, More | Camera, Mic, Share | Leave —
  with Notes, Breakout rooms, Copilot and Apps overflowed into More at the
  top (856 px window), then Record and transcribe ▸, Meeting info,
  Facilitator, Timer, Video effects and settings, Audio settings, Language
  and speech ▸, Settings ▸ (Call health, Accessibility settings, Don't show
  chat bubbles, Mute notifications), Call me, Report a concern, Help. Teams'
  visibility rules don't depend on the setting.
- **Teams' rules for the kinds of call** (`calculateVisibilityOverrides`):
  Notes needs a private meeting or a scheduled channel meeting and, ad hoc,
  `enableMeetingNotesInMeetNowCall` and not a channel meeting — so a
  calendar Meet now has Notes, a channel's Meet now (an ad hoc channel
  meeting) doesn't; Rooms needs a meeting (`isMeeting`) and the organizer;
  Report a concern needs a private, ad hoc or Meet now meeting and not a
  group call; Controls needs the Organizer role. Record, Transcribe,
  Captions, Meeting info, Chat bubbles, Hide me and Accessibility don't look
  at the kind of call; Timer is off in group calls unless
  `supportStructuredMeetingsTimerInGroupCalls`; RTT follows its policy.
- **Calendar Meet now, re-measured** (winpc 2026-11-18, "OST TEST 208
  Meet now", 1280 × 680, DOM only): the same as above with the setting on
  (bar at 382–931: Mic, Camera, Share | React, Chat, People, Copilot,
  Controls, More; grid Record, Transcribe, Facilitator ▾, Interpreter,
  Timer, Notes, Captions, Rooms, RTT, Apps; list View ▸, Join info ▸ (Meeting
  info, Call me, Call health), Settings ▸, Report a concern, Help) and off
  (at 1280 nothing overflows: Chat, People, Raise, React, View, Controls,
  Notes, Rooms, Copilot, Apps, More | Camera, Mic, Share | Leave; More:
  Record and transcribe ▸ (Start recording, Start transcription), Meeting
  info, Facilitator ▸ (Turn on Facilitator, Enable voice), Timer, Video
  effects and settings, Audio settings, Language and speech ▸ (Show live
  captions Alt+Shift+C, Turn on Interpreter, Turn on RTT for this call),
  Settings ▸ (Call health, Accessibility settings, Don't show chat bubbles,
  Mute notifications), Call me, Report a concern, Help). Turning the
  setting off opened Teams' "Submit feedback to Microsoft" ("What made you
  switch back?" with eight reasons: not ready for this change, missing the
  buttons that were on the toolbar before, Raise hand within React,
  controls in the middle, the order of buttons, the new More layout, can't
  find the tools, prefer the previous toolbar), cancelled unsent; the open
  meeting's bar switched at once (`calculateAndNotify`).
- **Group calls** (measured on winpc 2026-11-18 in a test-only group chat
  "OST TEST group call": ost-test1, OST Test 2, OST Test 3). A group chat's
  header offers **Meet now** (`audio-drop-in-button`: joins at once with
  the mic on, no pre-join, nobody rung; the window is "Meeting in {chat}")
  and, under its chevron, **Audio call** (asks "Are you sure you want to
  call everyone in the group?" [Cancel] [Confirm], then rings everyone;
  "Call with {chat}"; with nobody answering it ends by itself within
  seconds and shows "Pick up where you left off").
  - The chat's **Meet now**, setting **on**: Mic, Camera, Share | React,
    Chat, People, Copilot, Controls, More, Leave (bar 363–912 at 1280); grid
    Record, Transcribe, Interpreter, Timer, Captions, RTT, Apps; list View
    ▸, Join info ▸ (**Call me, Call health**: no Meeting info), Settings ▸
    (the same six), **Help**. No Notes, Rooms, Facilitator, Meeting info or
    Report a concern.
  - The chat's **Meet now**, setting **off**: Chat, People, Raise, React,
    View, Controls, Copilot, Apps, More | Camera, Mic, Share | Leave; More:
    Record and transcribe ▸ (Start recording, Start transcription), Timer,
    Video effects and settings, Audio settings, Language and speech ▸ (Show
    live captions, Turn on Interpreter, Turn on RTT for this call), Settings
    ▸ (Call health, Accessibility settings, Don't show chat bubbles, Mute
    notifications), Call me, Help.
  - The chat's **Audio call** (Teams as the caller, OST Test 2 answering):
    the same bar and More as its Meet now, with the setting on and off.
  - So Teams treats it as a group call (Report a concern's
    `!isGroupCall`), where Record, Transcribe, Captions, RTT, Help and the
    accessibility settings show as the rules say, Timer shows
    (`supportStructuredMeetingsTimerInGroupCalls` is on), Controls shows for
    the one who started it (the Organizer role), and Meeting info, Notes,
    Rooms, Facilitator and Report a concern don't.

## OST status

Built (CallWindow.qml, MenuPopup.qml, SettingsView.qml,
`teams_cli::calling::ubar`):
- [x] The setting, its text, device-local storage, feedback on turning off.
- [x] The InlineCentered preset with per-group dividers, centred middle
  slot, Resume / Join room / Return in the end slot, Raise in React.
- [x] Teams' glyphs (from Teams' Fluent icon set, `nmc-*.svg`), labels and
  tooltips; React's Raise / Lower hand button and persistent popover.
- [x] More's grid (with overflowed and unpinned controls first, Apps
  button), list and submenus (left, flipped to fit), Transcribe's own menu.
- [x] Overflow order and the compact bar under 480 px.
- [x] Move before / after, Pin, Unpin, Reset (saved per layout in OST's
  local settings, `meetingControlsLayouts`).
- [x] Drag and drop between the bar and More (§6a; CallWindow.qml
  `dragBegin` / `dragMove` / `dragEnd`): 2 px to start, Teams' 0.7 copy in
  the hovered button's or grid item's look, the bar making room as the
  result would be (the arrangement previewed live, the control hidden in
  its place), More pressed and the copy at 0.4 over More (unpin), before /
  after by the drag's direction, grid items pinned on the bar, not-allowed
  over Mic, Camera, Share and Leave, Escape cancels; saved as the
  right-click menu saves. Not built: touch's 200 ms hold, the keyboard
  sensor, the 200 ms drop animation and the screen-reader announcements.
- [x] Copilot (licensed users; call-and-meeting-window.md §1.8j).
- [x] Join info ▸ Call me (with dial-in; call-and-meeting-window.md
  §1.8k).
- [ ] Facilitator ▾ in More's grid (the current controls' More ▸
  Facilitator ▸ is built, §1.8h) and Interpreter (OST has no AI
  interpretation).
- [x] Dark and High contrast as measured (§7; Theme.qml `nmc*`): the bar's
  #292929 in dark, Teams' hover pair on split buttons, Leave's red tints
  and #DC626D, checked glyph and underline (white in High contrast), the
  More / React surfaces, hovered grid items, the apps and Raise buttons,
  reactions growing on hover, list glyphs turning brand on hover.
- [x] Meet now (§8): a channel's Meet now is a meeting (`adhoc`): Rooms,
  Record and transcribe, Captions, RTT, Timer, Meeting info, Report a
  concern, Help and the accessibility settings show as in a meeting, and
  Notes doesn't (an ad hoc channel meeting). OST has no Calendar Meet now
  (without a channel), whose controls are a scheduled meeting's.
- [x] Group calls (§8, measured 2026-11-18): a chat's Meet now and Audio
  call show Record and transcribe, Captions, RTT, Timer, Help and the
  accessibility settings (and Settings ▸) as Teams does; Meeting info,
  Notes, Rooms, Facilitator and Report a concern stay hidden
  (`ubar::Facts::group_call`); Timer shows there (no presenter option in
  a group call). A group call that rings OST (a chat's Audio call) is
  joined as the chat's group call (`IncomingCall::group_thread`), so it gets
  the group call's window and controls instead of a 1:1 call's. Checked
  live 2026-11-18 with OST Test 2 in Teams' group calls (`--group-call-nmc`):
  setting off — Chat, People, Raise, React, View, Apps, More | Camera, Mic,
  Share | Leave, More with Record and transcribe ▸, Timer, Video effects and
  settings, Audio settings, Language and speech ▸, Settings ▸ (Call health,
  Accessibility settings, chat bubbles, Mute notifications), Help; on —
  Mic, Camera, Share | React, Chat, People, More, grid Record, Transcribe,
  Timer, Captions, RTT, Apps, list View ▸, Join info ▸ (Call health),
  Settings ▸, Help. (Controls and Copilot are Teams' starter's and a
  Copilot licence's.) Rechecked 2026-11-18 after two fixes: an answered
  group call now stays up (the unanswered invitation's own end — untagged,
  408 "Call timed out without any signaling after attach from callee
  endpoints", ~58 s in — is ignored), and the group call's dial-in from its
  join is published, so Join info ▸ shows **Call me** and Call health, as
  Teams does for an Audio Conferencing user.
- What Teams needs for the two (unified-bar-container-manager, async-entry,
  live licence check 2026-11-18):
  - **Interpreter** (useAiInterpretationAvailable): ECS
    `enableAiInterpretation`, and either the bypass flag or the meeting
    policy's `aiInterpreter` (`meetingPolicy.aiInterpreter`; the calling
    policy's for 1:1 calls) "Enabled" **and** a Microsoft 365 Copilot
    licence (`isCopilot`, not for MTO); or the organizer turned
    interpretation on for everyone (then attendees without Copilot get it
    too). The test accounts' meeting policy has `aiInterpreter` Enabled;
    only ost-test1 has a Copilot licence (MICROSOFT_365_COPILOT_FOR_BUSINESS,
    the tenant's 25-seat trial with 24 seats unassigned). OST Test 2 and 3
    would show Interpreter with one of those trial seats assigned. OST
    has no AI interpretation of its own yet.
  - **Call me** (PstnButton, sM): the call's `pstnCapabilities.isDialInEnabled`
    and `isPSTNEnabled`, an interactive calling screen, and dial-in details
    for the meeting (`meetingInfoFromCall.pstnDetails`, there when the
    organizer has Audio Conferencing). ost-test1 and OST Test 2 have
    Microsoft Teams Audio Conferencing (dial-out USA/CAN); OST Test 3 has
    only Teams Phone Standard and Business Basic, so it gets no Call me.

Live check (2026-11-16, linuxlt, ost-test1, the OST calendar test meeting
alone): `--join-test --join-new-controls --join-stay=80` in light, dark and
High contrast; `--cards-test` gives the Meeting card 176.3 tall, as Teams.
