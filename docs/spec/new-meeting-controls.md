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
- Drag and drop between the bar and More (dnd-kit) does the same.

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
- [ ] Drag and drop between the bar and More.
- [x] Copilot (licensed users; call-and-meeting-window.md §1.8j).
- [ ] Facilitator, Interpreter, Call me (OST has no such features;
  hidden as in the current layout).
- [ ] Dark and High contrast were not measured in Teams with the new
  controls on; OST draws them with the same Fluent tokens as the current
  bar (checked in OST with `--theme=dark` / `--theme=highContrast`).
- [ ] The Meet now and group-call visibility of Notes, Rooms, Record and the
  like still follows OST's current rules (Teams showed Notes and Rooms in a
  Meet now); not compared with the setting off.

Live check (2026-11-16, linuxlt, ost-test1, the OST calendar test meeting
alone): `--join-test --join-new-controls --join-stay=80` in light, dark and
High contrast; `--cards-test` gives the Meeting card 176.3 tall, as Teams.
