# Gap list: calls and meetings (OST vs Teams desktop)

Compiled 2026-11-06 on branch `desktop/foundation`. Each item compares Teams with OST and gives a reference on both sides:

- **Teams side**: `spec §` is `docs/spec/call-and-meeting-window.md` (with line numbers as `L…`). `calls.md §` and `meetings.md §` are the feature inventories in `docs/parity/`. Where they conflict, the spec wins.
- **OST side**: these files, read as of commit `dd1b394`:
  - `desktop/qml/CallWindow.qml`, `IncomingCall.qml`, `PreJoin.qml`, `CallsView.qml`, `Main.qml`, `SettingsView.qml`, `Conversation.qml`, `CalendarView.qml`
  - `desktop/src/backend.rs`
  - `src/calling/*.rs`

Priorities:
- **[P1]** core, used every day
- **[P2]** common
- **[P3]** rare, policy- or licence-gated, or admin-only

Counts: 37 P1, 109 P2, 61 P3 (207 gaps).

"Absent" means no code path exists. Open backlog work is noted as `TASK-00xx`.

---

## 1. Call window shell and toolbar layout (spec §1.1–1.3, §1.5)

- [ ] [P1] The toolbar is built from server config, not hard-coded — Teams: items, order, slots and nesting come from the ECS `ubarLayoutPresets` / `ubarLayoutSetup` (`Inline`) / `ubarLayoutOverrides` settings. The layout is chosen per call type: `default`, `oneToOneOrGroupCall`, `oneToOnePstn`, `consultAndAdd`… — OST: two fixed QML rows, one for "meeting" and one for "not meeting" (ref: spec §1.1 L48–81; OST: CallWindow.qml:130–275)
- [ ] [P1] A group call uses the meeting (`default`) layout, and an incoming group call does too — Teams: group calls use `default`, the same as meetings — OST: an outgoing group call from a group chat does get the meeting row. An **incoming** call always gets the 1:1 row, because `set_call_meeting(false)` runs on every invitation (ref: spec §1.1 L77–80; OST: backend.rs:1150, backend.rs:1832)
- [ ] [P2] Group calls don't show meeting-only controls — Teams: a group call loses Notes, Rooms, Report a concern, Shared content and Meeting options — OST: the group-call window shows Notes always (and Rooms/Controls to an organizer) (ref: spec §1.4 L233–240; OST: CallWindow.qml:154–157)
- [ ] [P2] Button metrics — Teams: buttons 48 px high, 48–72 px wide, margins 6/4 px, 25 px icon, 11 px label. A 2 px × 66% status bar shows under a button whose panel is open — OST: buttons 52 px high, at least 56 px wide, 20 px icon, 12 px label (`theme.small`), and no open-panel status bar. Open panels are shown with a filled background instead (ref: spec §1.2 L104–111; OST: CallWindow.qml:796–822, Theme.qml:75)
- [ ] [P2] Slot template — Teams: Inline puts `[indicators][horizontalMiddleEnd right-justified] | [horizontalEnd]`, with a single slot divider before Leave. Group dividers follow the grouping strategy (MergeWithNext; MergeWithPrevious for 1:1; AlwaysKeep for PSTN) — OST: dividers are hand-placed. The meeting row has a divider between More and Camera that MergeWithNext wouldn't draw for that run (ref: spec §1.2 L96–126; OST: CallWindow.qml:160, 180, 205, 237, 249, 269)
- [ ] [P2] `role="toolbar"`/`group` and `data-tid` semantics — Teams: the toolbar role applies when a slot holds more than one control — OST: each BarButton is just `Accessible.Button`, with no toolbar or group role on the row (ref: spec §1.2 L116–117; OST: CallWindow.qml:828)
- [ ] [P1] Tooltips on every bar control, with the shortcut appended as `{{tooltip}} ({{keyboardShortcut}})` — Teams: for example "Mute mic (Ctrl+Shift+M)", "Turn camera off", "Change your view", "More actions", "Leave" — OST: no tooltips anywhere in the call window (ref: spec §1.2 L112–115, §13 L972; OST: CallWindow.qml:785–830)
- [ ] [P1] Width-driven overflow into More — Teams: Fluent Overflow measures widths, with no fixed breakpoints. AsFirst items leave from the right first, then the groups further left, then React and Raise (AsLast). More, Camera, Mic, Volume, Share, Pause share and Leave never overflow. Overflowed items are prepended to More in bar order — OST: no overflow. The rows are fixed, and the window's minimum width (720) clips them (ref: spec §1.5 L242–261; OST: CallWindow.qml:80, 130–275)
- [ ] [P3] Layout-shift click protection — Teams: while the pointer is over the bar, a click within 2000 ms of a resize, child change or overflow change is swallowed — OST: absent (ref: spec §1.5 L263–268; OST: absent)
- [ ] [P3] Toolbar customization (Pin/Unpin, Move before/after, drag to More, Reset) — Teams: off in the live build (`enableUbarCustomization` false). The MC1317197 refresh documents it as GA. Verify on winpc before building — OST: absent (ref: spec §1.6 L270–287; calls.md §7; meetings.md §6; OST: absent)
- [ ] [P3] Auto-hide meeting controls — Teams: off live (`enableHideUbar` false) — OST: absent (ref: spec §1.7; OST: absent)
- [ ] [P2] Indicator group — Teams: indicators for BroadcastState, E2EE, Recording, Copilot, AI interpretation, CallDuration and more, then "More status indicators" — OST: only the timer, plus a shield icon in meetings that isn't in the spec's indicator list. The shield does nothing (ref: spec §1.3 L133; OST: CallWindow.qml:117–127)
- [ ] [P3] Timer format past one hour — Teams: `HH:MM:SS`, every field zero-padded — OST: `H:MM:SS`, with the hour not padded (ref: spec §1.9 L340; OST: CallWindow.qml:103–107)
- [ ] [P2] Timer start — Teams: counts from `callStartTimestamp(teamsCallId)`, so someone joining a running meeting sees the meeting's elapsed time. Tooltip "Elapsed time", aria "Elapsed time {{elapsedTime}}" — OST: counts from the local connect moment, with no tooltip or aria (ref: spec §1.9 L338–342; OST: CallWindow.qml:93–100)
- [ ] [P2] Bar mounting rules — Teams: the bar is mounted only in Connected / Staging / Local- or RemoteHold, or (P2P only) Connecting / EarlyMedia, or InLobby with the lobby variant. In a moderated meeting's staging phase it is hidden — OST: the bar is always shown, including while calling/connecting a meeting and after "ended" (ref: spec §1 L41–46; OST: CallWindow.qml:112–186)

## 2. Visibility and disabled rules per call type and role (spec §1.4)

- [ ] [P1] Controls that can't work are hidden or carry a disabled reason, never a greyed placeholder — Teams: React and Rooms appear only when their rules hold. Disabled controls get a `forceDisabledReason` tooltip, in this order of precedence: OnHold, Disconnected, InLobby, StagingRoom, GreenRoom — OST: React is always disabled, and Rooms is disabled for organizers. There are no reasons (ref: spec §1.4 L171–203; OST: CallWindow.qml:151, 157)
- [ ] [P2] On hold, Mic stays enabled — Teams: items enabled on hold are Chat, More, Mic, Leave, Resume… — OST: Mic is disabled while held (ref: spec §1.4 L197–198; OST: CallWindow.qml:258)
- [ ] [P2] Notes visibility — Teams: only in private scheduled/recurring/MeetNow meetings (with `isPrivateMeeting`) or channel meetings with the flag. Never in group or 1:1 calls. Hidden for town hall attendees — OST: always shown in the meeting row (ref: spec §1.4 L180; OST: CallWindow.qml:156)
- [ ] [P2] Controls visibility — Teams: Organizer && `enableOrganizerControlButton` && not a town hall (or the threat-detection variant) — OST: organizer role from the roster. Close, but there's no threat variant and no town hall check (ref: spec §1.4 L178; OST: CallWindow.qml:36, 154)
- [ ] [P2] Rooms visibility — Teams: needs a scheduled meeting (`isMeeting`) and an organizer or breakout manager. A self-select participant can see it. Hidden in screen-share calls and cancelled meetings, and when `isBreakoutRoomsAllowed` is false — OST: shown disabled to anyone whose roster role is "organizer", group calls included (ref: spec §1.4 L181; OST: CallWindow.qml:157; TASK-0037)
- [ ] [P2] Apps visibility — Teams: hidden in 1:1 PSTN calls and town halls — OST: shown in every call (ref: spec §1.4 L182; OST: CallWindow.qml:158, 247)
- [ ] [P2] App tabs (PlatformTabSection): one bar button per pinned meeting-app tab — Teams: `enablePlatformTabSection` — OST: absent (ref: spec §1.3 #14, §1.4 L183; OST: absent)
- [ ] [P3] Chat hidden in 1:1 PSTN and voicemail-greeting calls — OST: Chat is always shown; there are no PSTN calls (ref: spec §1.4 L173; OST: CallWindow.qml:134, 238)
- [ ] [P3] `isE2EEHidden` items removed under E2EE — Teams: Notes, Rooms, Apps, Copilot, recording, transcript, Large gallery… — OST: no E2EE (ref: spec §1.4 L205–206; OST: absent)
- [ ] [P2] Camera/Mic/Share hidden or blocked by AV-over-IP policy, VDI or appliance mode, and Share blocked for attendees ("Only meeting organizers and presenters can share") — OST: no role- or policy-based gating (ref: spec §1.4 L184–186, §9 L822–827; OST: CallWindow.qml:161–179)

## 3. More (…) menu (spec §1.8)

- [ ] [P1] More menu contents and grouping — Teams: overflowed bar items first, then these groups:
  - overflowTop: Record and transcribe ▸, Music mode…
  - settings: Info, Timer, Video effects and settings, Audio settings, Language and speech ▸, Settings ▸ (Call health, Meeting options, Accessibility, Chat bubbles, Notifications…)
  - callingOverflow: Call me, Dial pad, Hold, Upgrade, Transfer, Merge, Park, Lock
  - Report a concern
  - help: Report a problem, Help

  OST: two items, "Device settings" (which jumps to the main window's Settings) and "Full screen" (ref: spec §1.8 L297–336; OST: CallWindow.qml:630–639, Main.qml:577)
- [ ] [P2] "Device settings" isn't a More item while `enableAVFramework` is on — Teams: Devices is hidden, and settings are reached through "Video effects and settings" / "Audio settings" side panes — OST: has a "Device settings" item that leaves the call window (ref: spec §1.8 L329, §2 L443; OST: CallWindow.qml:635)
- [ ] [P2] Settings ▸ Call health side pane — Teams: Network / Audio / Video / Screen sharing stats, refreshed every 15 s — OST: stats are only logged every 5 s (ref: spec §1.8 L329; calls.md §21; OST: backend.rs:886–915)
- [ ] [P3] Music mode ("High fidelity music mode") toggle — OST: absent (ref: spec §1.8 L316; OST: absent)
- [ ] [P3] Timer (ad-hoc / agenda) — OST: absent (ref: spec §1.8 L320; OST: absent)
- [ ] [P3] Settings ▸ Chat bubbles, Mute notifications, Accessibility, Privacy mode, Data — OST: absent (ref: spec §1.8 L329; OST: absent)
- [ ] [P3] Report a concern / Report a problem (`openFeedbackDialog`) / Help — OST: absent (ref: spec §1.8 L331–333; OST: absent)
- [ ] [P2] Meeting "Info" item (join info) — OST: absent (ref: spec §1.8 L318; OST: absent)

## 4. View menu and stage (spec §8.1–8.2; meetings.md §12–13)

- [ ] [P1] Video tiles in meetings and group calls — Teams: each participant's camera shows on their tile. You subscribe to streams through the media processor — OST: meetings and group calls are audio-only. Tiles show avatars only, and Camera is disabled because `can_video` is never set (ref: spec §8.2; meetings.md §12; OST: outgoing.rs:702–710, backend.rs:1851–1855, 1936–1940, CallWindow.qml:382; TASK-0036 AC #2)
- [ ] [P1] Active speaker — Teams: speaker swap rules in MixedStage/SpeakerStage/LeanAudioStage, no swapping while anything is pinned or spotlighted, and a speaking outline on the tile. Speaker view shows the active speaker — OST: `dominantSpeakerInfo`/`csrcInfo` callbacks are registered but never handled, so Speaker view always shows the first roster entry (ref: spec §8.2 L791–793; OST: signaling.rs:335–336, backend.rs:1265–1284, CallWindow.qml:312)
- [ ] [P1] Grid fitting — Teams: fixed 16:9 cells, the documented row/column growth algorithm, a trailing empty row dropped, a centred partial last row, the whole grid letterboxed at 16:9, and a 2 px inset (4 px between tiles) — OST: `ceil(sqrt(n))` columns with tiles stretched to fill and 8 px spacing (ref: spec §8.2 L776–782; OST: CallWindow.qml:307–321)
- [ ] [P1] Self view in the grid by default — Teams: `enableMyselfInGrid` isDefault true — OST: self is a floating 240×134 tile at bottom-right, and in meetings it shows only once others are present (ref: spec §8.2 L796; OST: CallWindow.qml:466–497)
- [ ] [P1] View menu items — Teams:
  - Gallery, Speaker, Large gallery (on limited devices; enabled at 9 videos), Focus on content
  - Gallery size ▸ 4/9/16/49 (default 16), Show videos first
  - More options ▸: Show gallery at top/right, Turn off/on other videos, Hide me, Include me in gallery, Full screen

  OST: Gallery and Speaker (meetings only), Full screen, and "Turn off incoming video" (ref: spec §8.1 L737–759; OST: CallWindow.qml:591–609)
- [ ] [P2] Gallery and Speaker in 1:1 Teams calls — Teams: MixedGrid and Speaker are hidden only for 1:1 PSTN — OST: the 1:1 View menu has only Full screen and incoming video (ref: spec §8.1 L740–742; OST: CallWindow.qml:595–598)
- [ ] [P2] Label "Turn off other videos" / "Turn on other videos", under View › More options, calling `toggleIncomingVideo` — OST: "Turn off incoming video" at the top level, and only local (hides the frame; the stream still arrives) (ref: spec §8.1 L754; OST: CallWindow.qml:601, 382)
- [ ] [P2] Layout and gallery size persisted per user — Teams: `updateUserExperiencePreferences{stageSettings{preferredLayout, preferredGallerySize, isPrioritizeVideoLayoutPreference, isMyselfInGrid}}` — OST: the layout is a window property, reset on every call (ref: spec §8.1 L759; OST: CallWindow.qml:58)
- [ ] [P2] Side bar and top bar — Teams: with content in Central, the others go to a right column of 16:9 tiles (or 2 columns of 4:3). There is a top-bar variant and automatic gallery-at-top. Bar widths and heights are chosen from bucket tables — OST: shared content covers the stage, and in 1:1 calls the remote video shrinks to one 240×135 corner tile. No side bar in meetings (ref: spec §8.2 L763–787; OST: CallWindow.qml:374–392)
- [ ] [P2] Pagination strip (36 px; "Previous page", "n/N", "Next page"), a "+N" overflow tile, and a "99+" participants tile — OST: absent; every participant is drawn (ref: spec §8.2 L788–790; OST: CallWindow.qml:316)
- [ ] [P2] Pin for me (up to 9) — Teams: local only, via `togglePinItem` — OST: absent (ref: spec §6 L671, §8.2 L794; meetings.md §13; OST: absent)
- [ ] [P2] Spotlight for everyone (up to 7) / Stop spotlighting / Exit spotlight — OST: absent (ref: spec §6 L673, §8.2 L795; meetings.md §6, §13; OST: absent)
- [ ] [P2] Fit to frame / Fill frame per tile — OST: absent (ref: spec §6 L674; meetings.md §12; OST: absent)
- [ ] [P2] Hide me / Unhide me, Include/Remove me in gallery — OST: absent (ref: spec §8.1 L755–756; OST: absent)
- [ ] [P2] Focus on content — Teams: enabled only while content is shared — OST: absent (ref: spec §8.1 L748; OST: absent)
- [ ] [P2] Raised hands promoted into view (`enableRaiseHandPromotion`) — OST: absent (ref: spec §8.2 L793; OST: absent)
- [ ] [P2] Swap content with gallery by selecting a tile — OST: absent (ref: meetings.md §12; OST: absent)
- [ ] [P2] Large gallery (7×7) with paging — OST: absent (ref: spec §8.1 L744; meetings.md §12; OST: absent)
- [ ] [P3] Toast "You might not see everyone's video" when the gallery size exceeds the device limit — OST: absent (ref: spec §8.2 L775; OST: absent)
- [ ] [P3] Sign language view; Together mode is retired (don't build it) — OST: absent (ref: spec §8.1 L745–746; meetings.md §12; OST: absent)
- [ ] [P2] Tile name chip and status — Teams: names on tiles smaller than 250×140 show on hover only; the tile shows a mic-off icon and video-off state — OST: always shows the name chip; mic state only on the self tile (ref: calls.md §7; OST: CallWindow.qml:343–348, 490–496)
- [ ] [P2] Full screen via F11, with "Fullscreen mode was set" / "…exited" announcements — OST: menu item only, no F11 (ref: spec §8.1 L757, §13 L967; OST: CallWindow.qml:74, 600; no F11 in Main.qml)

## 5. Camera, mic, devices and effects (spec §3, §2 device panes; calls.md §17–18; meetings.md §4–5)

- [ ] [P1] Camera ▾ split (`video-button-configure`, "Open video options") and its flyout — Teams: live preview while video is off, the Camera device list, a Backgrounds quick picker, Adjust brightness / Soft focus, and "More video effects and settings" — OST: a single toggle (ref: spec §3 L486–496; OST: CallWindow.qml:161–166, 250–255)
- [ ] [P1] Mic ▾ split (`audio-button-configure`, "Open audio options") and its flyout — Teams: Speaker list and volume slider, Microphone list and level meter, Spatial audio, Noise suppression (On/Off plus Background noise only / Voice isolation), Music mode, "More audio settings" — OST: a single toggle (ref: spec §3 L521–529; OST: CallWindow.qml:167–172, 256–261)
- [ ] [P1] Switching devices during a call — Teams: `selectDevice(id, "Speaker")` from the flyouts and panes — OST: devices apply only to the next call ("Used for calls you start or answer after changing them") (ref: spec §2 L445–447, §3; OST: SettingsView.qml:356–371)
- [ ] [P1] Noise suppression and echo cancellation (on by default; Auto/High/None) — Teams: `updateNoiseSuppression(Auto|High|None|NoneWithPns)` — OST: no audio processing in the capture path; no noise, AEC or AGC code exists (ref: spec §2 L449, §3 L526; calls.md §17; OST: src/calling/audio.rs, webrtc_audio.rs — absent)
- [ ] [P2] Mic icon live volume meter (`enableMicVolumeIndicatorInUbarMicIcon`) — OST: absent (ref: spec §3 L504; OST: CallWindow.qml:168)
- [ ] [P2] Mic label and tooltip — Teams: label stays "Mic"; tooltips "Mute mic" / "Unmute mic" / "Mute mic (speaker is muted)"; announcements "Your microphone is muted/unmuted"; 100 ms toggle debounce — OST: label "Mic" with no tooltip, announcements or debounce (ref: spec §3 L499–504; OST: CallWindow.qml:167–172)
- [ ] [P1] Ordered disabled-reason tooltips for Camera (13 reasons, for example "No available camera found", "You can share your video when you're done screensharing") and Mic (13 reasons, for example hard mute "Only meeting organizers and presenters can unmute", "No audio devices available") — OST: buttons grey out with no reason (ref: spec §3 L472–485, L506–519; OST: CallWindow.qml:163, 169, 252, 258)
- [ ] [P2] Hard mute (attendee mic/camera disabled by the organizer) reflected on your own Mic/Camera — Teams: hints "Mic is disabled for all attendees.", "Raise your hand if you'd like to speak." — OST: server mute is parsed for others' rows only; your own controls ignore it (ref: spec §3 L508, L520; OST: roster.rs:67–70, CallWindow.qml:45)
- [ ] [P2] Mute goes through the call service — Teams: `toggleMuteWithState(teamsCallId, muteCall, …)` + `confirmCallToggleState`, so the roster shows you muted — OST: mute only silences local capture; nothing is signalled, so others' rosters don't show it (ref: spec §3 L505, §14 L982; OST: backend.rs:2027–2039)
- [ ] [P2] Camera toggle states — Teams: tooltip "Turning on camera…" while it toggles; icons `call-video-off` / `-disabled` / `-error` — OST: no pending state or error icon (ref: spec §3 L469–471; OST: CallWindow.qml:162)
- [ ] [P2] Background effects pane (`videobackgrounds`) — Teams: None, Blur (Standard/Portrait), Add new right after Blur, images (recent, org, 23 Microsoft CDN images, uploads), 3-column grid, Preview / Apply / "Apply and turn on video", upload to `maglev/custom-video-background/upload` — OST: absent. calls.md §18 notes Teams itself lacks effects on Linux; decide on native parity (ref: spec §2 L454–465; calls.md §18; meetings.md §4; OST: absent)
- [ ] [P2] "Video effects and settings" / "Audio settings" side panes in the call window — Teams: speaker/mic dropdowns, in-call volume slider (default 50), Spatial audio, Noise suppression, Camera, Mirror my video, Adjust brightness, Soft focus, Super resolution — OST: absent (ref: spec §2 L442–452, §1.8 L325–327; OST: absent)
- [ ] [P2] Camera selection in the UI — OST: a `cameraDevice` setting is read, but no screen sets it; Settings › Devices lists audio only (ref: calls.md §12 "Video settings > Camera with preview"; OST: backend.rs:928–934, SettingsView.qml:353–372)
- [ ] [P3] Speaker toggle (Ctrl+Shift+U) and speaker mute state — OST: absent (ref: spec §13 L958; calls.md §17; OST: absent)
- [ ] [P3] Avatars tab, Decorate (AI backgrounds), org backgrounds, video filters — OST: absent (ref: spec §3 L489; calls.md §18; meetings.md §4; OST: absent)
- [ ] [P3] Turn off my camera and mic when my screen locks (Privacy) — OST: absent (ref: meetings.md §4; calls.md §12; OST: absent)

## 6. Leave and End (spec §4; meetings.md §25)

- [ ] [P1] Leave ▾ split (`hangup-button-more-options`) for an organizer, a moderator, or someone with multiple own endpoints — Teams: items "Leave", "Leave on all my devices", "End meeting" (plus "Restart event") — OST: Leave is a plain button (ref: spec §4 L538–548; OST: CallWindow.qml:181–185, 270–274)
- [ ] [P1] End meeting — Teams: the "End the meeting?" / "You'll end the meeting for everyone." [Cancel] [End] dialog, then `stopCall(…, {forEveryone:true})` — OST: absent (ref: spec §4 L549; meetings.md §25; OST: absent)
- [ ] [P2] Leave on all my devices (`forAllUserEndpoints:true`) — OST: absent (ref: spec §4 L543, L550; OST: absent)
- [ ] [P2] Leave confirmation while sharing — Teams: popover "You're currently sharing. Are you sure you want to leave?" [Stay] [Leave]; also when the user setting is on. Never from the keyboard shortcut — OST: leaves at once (ref: spec §4 L551–554; OST: CallWindow.qml:184)
- [ ] [P3] Settings › General "Ask me to confirm when I leave a meeting" — OST: absent (ref: spec §4 L553; OST: SettingsView.qml:12–18)
- [ ] [P3] Announcements "Leaving..." then "You have left the call"; labels "Leave room" / "Unfollow" / "End monitoring" — OST: absent (ref: spec §4 L533–536, L550; OST: absent)

## 7. 1:1 telephony: hold, transfer, consult, merge, park, dial pad (spec §5; calls.md §8)

- [ ] [P2] Resume as its own contextual bar button (`resume-button`, "Resume") at the left of the bar; Hold stays (disabled outside Connected/RemoteHold) — Teams: announcements "You've put the call on hold" / "Call resumed" — OST: Hold is replaced in place by a bordered "Resume" pill, with no announcements (ref: spec §1.3 #1, §5 L561–562; OST: CallWindow.qml:213–236)
- [ ] [P2] Stage text for hold — Teams: "On hold" (local) / "You've been put on hold" (remote) — OST: "On hold mm:ss" (local) / "On hold" (remote) (ref: spec §5 L570–572; OST: CallWindow.qml:438–448)
- [ ] [P2] Transfer flow — Teams: Transfer first holds the call (`context:"Transfer"`), then opens the "Transfer the call" dialog — OST: opens a "Transfer to" popup without holding (ref: spec §5 L563; OST: CallWindow.qml:191–197)
- [ ] [P2] Transfer dialog V2 — Teams:
  - picker "Type a name or number" (PSTN numbers allowed), up to 3 suggestions (`callTransferSuggestions`)
  - destination dropdown (audio call / work voicemail / mobile / work number)
  - "Ring back if there's no answer." (safe transfer)
  - call topic, and the Copilot context toggle
  - [Transfer] [Cancel]

  OST: a name search popup showing 6 directory matches; picking someone transfers at once; no options (ref: spec §5 L575–585; calls.md §8; OST: CallWindow.qml:697–748, backend.rs:2128–2150)
- [ ] [P2] Consult — Teams: the hold, then the "Consult then transfer the call" dialog with [Start a call] (voice consult, `startConsultation mode:"TeamsCall"`) or [Open chat] (`mode:"Chat"`), then Transfer — OST: chat-only. It holds, opens a 1:1 chat in the side pane, and shows a "Consulting X" banner with Transfer / Resume. There is no voice consult leg and no `startConsultation` (ref: spec §5 L564, L581–584; calls.md §8; OST: Main.qml:583–587, CallWindow.qml:750–777)
- [ ] [P2] Transfer outcome UI — Teams: transfer state "Transferring" disables controls; announcements — OST: only status-bar text "Transferring…" / "Call transferred" / "Transfer failed: …" (ref: spec §5 L563; OST: backend.rs:2142–2149, 1219–1243)
- [ ] [P2] Call waiting: a second incoming call while you're in a call rings; accepting it holds the current call — OST: a second call is silently ignored (ref: calls.md §6, §8 "Call merge"; OST: backend.rs:1134–1136)
- [ ] [P3] Multiple held calls (up to 3 on desktop), with a held-call bar and Resume — OST: one call slot (ref: calls.md §8; OST: backend.rs:654–665)
- [ ] [P3] Merge Calls — Teams: "Choose a call to merge" dialog, `mergeCalls` / `mergeConsultCall` — OST: absent (ref: spec §5 L566; calls.md §8; OST: absent)
- [ ] [P3] Park Call — Teams: `parkCall`, "Share this code {{pickupCode}} to retrieve the call" [Copy code], plus Unpark in the Calls app — OST: absent (ref: spec §5 L567; calls.md §8; OST: absent)
- [ ] [P3] Transfer during a delegate consult; Lock/Unlock call (SLA) — OST: absent (ref: spec §5 L565, §1.8 L330; calls.md §14; OST: absent)
- [ ] [P3] Upgrade to video call (`enableUpgradeCall` false live); Call me (PSTN call-me-back) — OST: absent (ref: spec §1.8 L330; OST: absent)
- [ ] [P2] Dial pad always shown — Teams: always, unless `disableDtmfForNonP2pAndEmergencyCalls` (false live) — OST: shown, but disabled unless the media negotiated telephone-event, and disabled on hold (ref: spec §1.4 L189, §5 L568; OST: CallWindow.qml:206–212)
- [ ] [P3] Dial pad in group calls and meetings (DTMF to an IVR participant) — Teams: always shown — OST: no dial pad in the meeting row (ref: spec §1.4 L189; OST: CallWindow.qml:130–186)

## 8. People pane and roster management (spec §6; meetings.md §8–9)

- [ ] [P1] Section structure — Teams, in order:
  1. Waiting in lobby
  2. Presenters ("In this meeting" when there are no attendees; "Currently in this call" in non-meeting calls)
  3. Attendees
  4. Interpreters
  5. Following
  6. Others invited (with RSVP status)
  7. People added to the chat
  8. Suggestions
  9. View-only attendees
  10. Agents

  Titles read "{{title}} ({{n}})". Empty sections are hidden. Each root section shows at most 20 rows, then "See more"

  OST: one section, "In this meeting (n)" or "In this call (n)" (ref: spec §6 L611–627; OST: CallWindow.qml:535–540)
- [ ] [P1] Sort order — Teams: raised hands by rank, then you, then PSTN, then display name (`localeCompare`) — OST: you first, then roster join order (ref: spec §6 L629–639; OST: CallWindow.qml:44–49)
- [ ] [P1] Search box (`roster-participants-search-input`, focused on open) — OST: absent (ref: spec §6 L590–592; OST: absent)
- [ ] [P1] "Invite someone or dial a number" field → `addParticipant1` — Teams: also turns a 1:1 call into a group call — OST: absent. `signaling::invite_user` is used only to ring group-call members at start (ref: spec §6 L593; calls.md §5, §8; meetings.md §8; OST: outgoing.rs:758)
- [ ] [P2] Share invite (Copy meeting link / Share via default email) — OST: absent (ref: spec §6 L594–597; meetings.md §8; OST: absent)
- [ ] [P2] Header "More actions" menu — Teams: Mute all, Disable/Allow mic for attendees, Disable/Allow camera for attendees, Lower all hands, Download attendance list, Stop all spotlights, Lock/Unlock the meeting, each with its confirm dialog — OST: absent (ref: spec §6 L598–609; OST: absent)
- [ ] [P2] Row secondary line ("Organizer" / "Moderator" / "Meeting guest" / "External" / room name) and state text ("Calling...", "On hold", "Declined" [Retry], "Muting...", "Action failed") — OST: shows the raw role capitalised (for example "Presenter", "Attendee"; Teams shows no secondary line for these) and no state text (ref: spec §6 L643–654; OST: CallWindow.qml:558–563)
- [ ] [P2] Trailing row icons, in order: video off, signer, Pinned, Spotlighted, PSTN, audio off, raised hand with rank number and skin-tone hand, Cannot share video, mic Cannot unmute/Muted/Unmuted — OST: a plain ✋ (no rank) and a mic icon (ref: spec §6 L655–664; OST: CallWindow.qml:565–574)
- [ ] [P2] Participant "More options" (…) on hover and right-click — Teams menu: Mute participant, Allow/Disable mic and camera, Lower hand, Pin for me, Spotlight, Fit/Fill, Edit display name (self), Make a presenter / Make an attendee (confirm "Change role?"), Remove from meeting (no confirm) — OST: absent (ref: spec §6 L665–685; meetings.md §8; OST: absent)
- [ ] [P2] Services behind the menu — Teams: `muteParticipant1`, `muteAllParticipants1`, `removeParticipant1`, `promoteAttendeeToPresenter` / `demotePresenterToAttendee`, `updateAttendeeRestrictions`, `updateMeetingLock`, `renameParticipant` — OST: none implemented (ref: spec §6 L687–693, §14 L988; OST: absent)
- [ ] [P2] Close button aria "Close participants pane"; drill-in back "Return to main Participants panel" — OST: "Close participants" (ref: spec §6 L589; OST: CallWindow.qml:533)
- [ ] [P2] Roster identity — Teams: the initial participant list carries roles, mute state and hands — OST: `getAllParticipants` keeps names only, so roles and hands of people already present stay unknown until they change (ref: spec §6; OST: outgoing.rs:143–175, backend.rs:1919–1929)
- [ ] [P2] Ringing participants ("Calling...") with an inline [Cancel] — OST: absent (ref: spec §6 L651, L665; OST: absent)
- [ ] [P3] Roles: co-organizers, LimitPresenterRolePermissions, role persistence on rejoin — OST: roles are display only (ref: meetings.md §9; OST: roster.rs:61–65)
- [ ] [P3] Hide attendee names (`maskIdentitiesForRole`); compliance-recording bot notice — OST: absent (ref: spec §6 L627; meetings.md §8; OST: absent)

## 9. Lobby (spec §2 states, §6 Lobby; meetings.md §7)

- [ ] [P1] Waiting in the lobby, joiner's side — Teams: the pre-join stays up with "Hi, {{userName}}. Someone will let you in shortly." / "…when the meeting starts." Join and speaker are disabled; the mic and camera toggles still work — OST: no lobby state. CallWindow states are calling/connecting/connected/ended only, and PreJoin closes on Join (ref: spec §2 L427–438; OST: CallWindow.qml:14, PreJoin.qml:171)
- [ ] [P1] Admit / Deny, organizer's side — Teams: "Waiting in lobby" rows with ✓ / ✕ (`admitParticipant1` / `denyParticipant`), "Admit all" when more than one wait (`admitAllParticipants1`), confirm variants — OST: absent (ref: spec §6 L695–709; meetings.md §7; OST: absent)
- [ ] [P1] Lobby toast "Waiting in the lobby" / "{{name}} +{{n}}": [Deny] [Admit] + "More info" for one person, [View Lobby] for several; Ctrl+Shift+Y admits — OST: absent (ref: spec §6 L702–704, §13 L960; meetings.md §7; OST: absent)
- [ ] [P2] People badge = lobby count + raised hands (non-attendees only), aria "{n} people with new activity. Show participants" — OST: the badge shows raised hands in red, otherwise the total roster count (ref: spec §7 L724; OST: CallWindow.qml:141–142)
- [ ] [P3] Staging (moderated) text "A moderator is required…"; green room; lobby chat; Suspected threats with Deny all; "Not admitted" rejoin — OST: absent (ref: spec §2 L434, §6 L698–701; meetings.md §7; OST: absent)

## 10. Raise hand (spec §7; meetings.md §10)

- [ ] [P2] Queue rank from the server's `raiseHandRank` (`raiseHandsOrderedRank` 1…N, computed up to 20) — OST: rank = position in roster join order among raised hands (ref: spec §7 L719; OST: CallWindow.qml:43, 325; roster.rs:71–82 doesn't parse a rank)
- [ ] [P2] Label stays "Raise"; title "Raise your hand" / "Lower your hand"; active state while raised; announcements "Your hand is raised." / "…lowered" — OST: label flips to "Lower"; no title or announcement (ref: spec §7 L712–713; OST: CallWindow.qml:145–150)
- [ ] [P2] Skin tone in the published state and in the hand emoji — OST: always `skinTone: 0` (ref: spec §7 L715, §6 L662; OST: outgoing.rs:108)
- [ ] [P2] "Someone raised a hand" popup (10 s; "{name} + # other(s)"; not while the roster is open or someone is in the lobby) — OST: absent (ref: spec §7 L720–723; OST: absent)
- [ ] [P2] Auto-lower — Teams: after 3000 ms of speaking, "We noticed you've spoken." / "Lowering your hand in a few seconds" [Keep it raised] — OST: absent (ref: spec §7 L725–729; meetings.md §10; OST: absent)
- [ ] [P2] Lower other participants' hands (`lowerOtherParticipantsHand`) and Lower all hands (`lowerAllRaisedHands`) — OST: absent (ref: spec §7 L716–717; OST: absent)
- [ ] [P3] Optimistic update with a 10 s rollback without confirmation; errors "Couldn't raise your hand. Try again." — OST: rolls back only on an HTTP error, with a generic status text (ref: spec §7 L718; OST: backend.rs:2105–2126)
- [ ] [P3] Ctrl+Shift+K (raise/lower) and Ctrl+Shift+L (announce raised hands) — OST: absent (ref: spec §13 L954, L962; OST: Main.qml:79–86)

## 11. Reactions (spec §8.3; meetings.md §11)

- [ ] [P1] React flyout (Like, Love, Applause, Laugh, Surprised) sending `sendMeetingReaction` — Teams: not in P2P calls; needs meeting option `allowMeetingReactions` — OST: React is a disabled placeholder (ref: spec §8.3 L799–806; OST: CallWindow.qml:151; TASK-0035)
- [ ] [P1] Receiving reactions (`meetingReactionsEvent` / broker) — Teams: shown on the sender's tile for 4250 ms (emoji size stepped by tile height; at most 8 stacked) and as a floating overlay (2.133 s rise, given easing and scale/travel steps) — OST: absent (ref: spec §8.3 L807–816; OST: absent; TASK-0035)
- [ ] [P3] Skin tone for like/applause/okay/wave…; expanded set and Alt+Shift+1…5 (both off live) — OST: absent (ref: spec §8.3 L802–805; OST: absent)

## 12. Share tray, presenting, viewing (spec §9–10; calls.md §19; meetings.md §15–17)

- [ ] [P1] Share in meetings and group calls — Teams: the share goes through the media processor — OST: Share is disabled, because `can_share` is never set for meetings or group calls (ref: spec §9; OST: backend.rs:1851–1855, 1936–1940; TASK-0034 AC #2)
- [ ] [P1] Receive others' share in meetings — OST: the share frame comes only from a 1:1 re-offer; meetings are audio-only (ref: spec §8.2; OST: outgoing.rs:702–710)
- [ ] [P1] Classic floating share tray (Ctrl+Shift+E toggles; Esc closes) — Teams:
  - "Share content" header with an "Include sound" toggle
  - Presenter mode (Content only / Standout / Side-by-side / Reporter / Add background)
  - "Screen (n)" live thumbnails in 2 columns (max 4, then More)
  - "Window" drill-down "Choose window"
  - Whiteboard; Content from camera
  - PowerPoint Live + recent files; Excel Live
  - Browse OneDrive / Browse my computer

  OST: Share opens the desktop portal picker directly. The spec says Teams has no OS picker; on Wayland the portal is needed for capture (ref: spec §9 L818–847; OST: CallWindow.qml:173–179, backend.rs:753–769, screencast.rs:32)
- [ ] [P2] Include system sound (`tryToggleIncludeSystemAudio`) — OST: absent (ref: spec §9 L829; calls.md §19; OST: absent)
- [ ] [P1] Sharing control bar — Teams: a separate top-level window "Sharing control bar", draggable. Expanded: handle, indicators, Camera, Mic, Give control, Share sound, Optimize, Layout, Annotate, Chat, People, More, Stop sharing, Pin. Minimized after 4 s: badge "You're sharing your screen" + "Stop sharing" (297×35). Ctrl+Shift+Space focuses it — OST: absent. A "You're presenting" chip shows inside the call window instead (ref: spec §10 L850–880; OST: CallWindow.qml:406–419)
- [ ] [P2] Call window behaviour while presenting — Teams: the call window minimizes into the compact view showing your share preview and video, and is shown again when the share stops — OST: the call window stays as it is (ref: spec §11 L898–901, L905; calls.md §19; OST: absent)
- [ ] [P2] Give control / Take back, and the viewer's Take control ("Request control?" → "Waiting for approval" → "Stop control"), with sharer alert "{{displayName}} is requesting control." [Give control] [Deny] — OST: absent (ref: spec §10 L871–894; calls.md §19; meetings.md §15; OST: absent)
- [ ] [P3] Pause / Resume screen share (`enableScreenSharePauseResume` off live) — OST: absent (ref: spec §1.3 #21, §10; OST: absent)
- [ ] [P2] Viewer zoom and pan of shared content (+/− buttons, Ctrl+scroll, Alt+Shift+ +/−/0/arrows) and "Open in new window" — OST: absent (ref: spec §13 L968; calls.md §19; meetings.md §15; OST: absent)
- [ ] [P2] Viewer label — Teams: none specified; spec §8.2 puts content in Central with the gallery on the right — OST: adds a "<peer> is presenting" chip and moves the camera to a corner tile [verify the chip on winpc] (ref: spec §8.2 L764; OST: CallWindow.qml:393–400)
- [ ] [P2] Share disabled reasons ("Only meeting organizers and presenters can share", server-muted, audio-only, policy) and "Stop sharing" label calling `stopSharing` — OST: "Stop sharing" label present; no reasons (ref: spec §9 L820–827; OST: CallWindow.qml:173–179)
- [ ] [P3] Annotate; Optimize for video; presenter Layout menu; PowerPoint Live (presenter and attendee views); Excel Live; Whiteboard sharing; incoming share accept/decline Ctrl+Shift+A/D — OST: absent (ref: spec §10; meetings.md §15–17; OST: absent)
- [ ] [P3] Red border around the shared screen (native in Teams, unverified) — OST: absent (ref: spec §10 L881; OST: absent)

## 13. Compact view and multitasking (spec §11; calls.md §22)

- [ ] [P1] Compact view window — Teams: opens when the call window is minimized; always on top; titled "Meeting compact view | {title}". Default MultiParticipant horizontal gallery (≤4 tiles), Simple 304×247 / Lightweight 334×120. Placed bottom-right with a 30 px margin, and the position is kept. Per-mode toolbars without labels (Camera, Mic, Share, Leave…); title bar with view switch, Minimize, "Maximize meeting window" — OST: absent (ref: spec §11 L896–931; calls.md §22; OST: absent)
- [ ] [P3] "Don't need the floating window?" prompt after 4 minimizes; "Hide Call Monitor when minimizing meeting window" setting — OST: absent (ref: spec §11 L899–900; OST: absent)
- [ ] [P2] Pop out Chat / Notes into their own windows — OST: Chat is an in-window pane only (ref: calls.md §22; OST: CallWindow.qml:510–516)
- [ ] [P3] Second device: "Add this device" / "Transfer to this device" banner and flow — OST: absent (ref: calls.md §22; meetings.md §27; OST: absent)

## 14. Pre-join screen (spec §2; meetings.md §3)

- [ ] [P1] Live camera preview and a working camera toggle — Teams: camera default off when signed in; toggle with chevron "Open video options" flyout (Camera list, "More video settings") and on/off switch — OST: static "Your camera is turned off" with a disabled switch (ref: spec §2 L366–372, L431; OST: PreJoin.qml:69–86; TASK-0036 AC #3)
- [ ] [P2] Effects button — Teams: exactly one of "Effects and avatars" / "Video effects" / "Background filters", which toggles the `videobackgrounds` pane; a tile click applies at once in pre-join — OST: absent (ref: spec §2 L373–378, L462; OST: absent)
- [ ] [P1] Computer audio content — Teams: mic Switch with tooltip; device name as a button opening a flyout (Microphone list, 17-segment level meter, "More audio settings"); Speaker row with on/off, volume slider and device flyout; "Test mic and speaker" — OST: mic switch and plain device names only (ref: spec §2 L396–401; OST: PreJoin.qml:91–118)
- [ ] [P2] Audio option subtitles — Teams: wide ("Use your default mic and speaker.", "Dial in from any phone, or we'll call you.", …) and narrow forms; "(suggested)" badge; Phone's "Checking for dial-in info…" driven by `subscribedCallChangedEvent{isPSTNEnabled}` — OST: titles only; Phone permanently disabled (ref: spec §2 L380–394; OST: PreJoin.qml:96–149)
- [ ] [P2] Room audio picker — Teams: "Search for a room", "Nearby", "Other Suggestions", "Unable to find any rooms", "Requires a room with an audio system." — OST: invented text "No rooms found nearby. Join with computer audio, or try again when you're in a Teams Room."; joining with Room selected actually uses computer audio (ref: spec §2 L386; OST: PreJoin.qml:137–142, 170–171)
- [ ] [P2] "Don't use audio" — Teams: sends `outgoingAudio/incomingAudio:false` in `joinOptions`; content "Join muted to avoid causing audio disruption." — OST: joins with audio, then silences local media after connect (ref: spec §2 L387, L413; OST: Main.qml:545–548, backend.rs:2091–2103)
- [ ] [P2] Join with the mic off — Teams: the mic state goes in `joinOptions` — OST: toggles mute only after connecting, so there's a brief unmuted window (ref: spec §2 L409–418; OST: Main.qml:541–544)
- [ ] [P2] Narrow layout below 720 px — Teams: only the selected audio option, a "More audio options" chevron and a popover — OST: the minimum window width is 1000, so there's no narrow layout (ref: spec §2 L363; OST: PreJoin.qml:22)
- [ ] [P2] Cached audio choice (`prejoinScreenSelectedAudio`; Room, None and Follow never cached) and cached video/mic state — OST: resets to Computer audio, mic on, every time (ref: spec §2 L395, L418; OST: PreJoin.qml:30)
- [ ] [P2] Header — Teams: H1 title ("Microsoft Teams meeting" when there is none); date, "start – end TZ" and participant summary ("Organizer joined" / "n others joined", with an "In this meeting" popover) only for Scheduled/Recurring meetings after 5000 ms; recurring-series icon — OST: title plus date/time at once; no timezone, participant summary or series icon; adds a logo (ref: spec §2 L350–359; OST: PreJoin.qml:39–61)
- [ ] [P1] Connecting state on the pre-join — Teams: title "Connecting" with animated dots, everything disabled, focus on Cancel; Cancel calls `tryStopCall` / `abandonCallingIntent` — OST: PreJoin closes on Join; the call window shows "Connecting…" (ref: spec §2 L421, L433; OST: PreJoin.qml:171, CallWindow.qml:302)
- [ ] [P2] Auto-mute notice "There are already {{n}} people in the meeting. We have muted your mic." (threshold likely 4) — OST: absent (ref: spec §2 L402; OST: absent)
- [ ] [P2] Join now enabled only when the state allows, an audio option is chosen, you're online and the name is valid — OST: always enabled (ref: spec §2 L408; OST: PreJoin.qml:165–174)
- [ ] [P3] Account picker / switch account; anonymous name box and its validation; town hall "Join as…" split button; consent/CAPTCHA; email OTP verification; early-leave drop survey — OST: absent (ref: spec §2 L349, L360, L407, L410, L421; meetings.md §2–3; OST: absent)
- [ ] [P3] Alert banners (watermark, audio-only, screen-capture protection); overflow/view-only notices — OST: absent (ref: spec §2 L348, L440; OST: absent)
- [ ] [P3] Phone audio after joining ("Use phone for audio": Call me / dial-in numbers) — OST: absent (ref: spec §2 L422–425; OST: absent)

## 15. Incoming calls and starting calls (calls.md §2, §4–6; meetings.md §1–2)

- [ ] [P1] Video call button in chat headers (and Alt+Shift+V) — Teams: chat headers have both Video call and Audio call — OST: Audio call only; the ▾ menu holds just "Audio call" (ref: calls.md §4, §23; OST: Conversation.qml:279–298, Main.qml:79)
- [ ] [P1] Calls from New chat (To: names → Video/Audio call), profile cards and search — OST: calls start only from an open chat or from Calls/History (ref: calls.md §4; OST: backend.rs:1753–1772)
- [ ] [P2] Group-chat call confirmation and the 20-person limit (calling buttons disabled above 20) — OST: no confirmation, no disabled state; `MAX_RING` 20 caps only who is rung (ref: calls.md §4–5; OST: outgoing.rs:18, Conversation.qml:279–285)
- [ ] [P2] Incoming toast context — Teams: which of your lines is called; forwarded / delegated ("on behalf of") / call group / call queue / private line; "Spam Likely" — OST: name and photo only (ref: calls.md §3, §6; OST: IncomingCall.qml:71–91)
- [ ] [P2] Incoming group call or meeting ring shows as a group call — OST: shown as a 1:1 call from the caller (ref: spec §1.1; OST: backend.rs:1145–1152)
- [ ] [P2] Settings › Calls › Viewing incoming calls: Large window / Small window — OST: one fixed 360×240 toast (ref: calls.md §6, §12; OST: IncomingCall.qml:19)
- [ ] [P3] Distinct ringtones (normal / forwarded / delegated), choose a ringtone, secondary ringer, call-waiting beep every 5 s — OST: one built-in ringtone (ref: calls.md §6, §12; OST: backend.rs:2583–2595, ringtone.rs)
- [ ] [P3] Missed call consolidated with its voicemail as one entry (MC1485056) — OST: Activity lists missed calls (`missedCall` kind), but there's no voicemail to merge with (ref: calls.md §6, §9; OST: ActivityView.qml:135, 222)
- [ ] [P2] Meet now — Calendar "Meet now" (name, Get a link to share, Start meeting), channel Meet now, group-chat Meet now with Ring / Ring all, `/meetnow` — OST: absent (ref: meetings.md §1; OST: absent)
- [ ] [P2] Join with an ID (meeting ID + passcode) — OST: absent (ref: meetings.md §2; OST: absent)
- [ ] [P2] Join from the meeting chat (Join button at the top), from the channel post/header, from the live meeting join bar, and from the "Meeting started" toast (Ctrl+Shift+J); Ctrl+Shift+R opens the chat from the toast — OST: join only from the Calendar event's Join (ref: meetings.md §2, spec §13 L965; OST: CalendarView.qml:452–453, Main.qml:1474–1478)
- [ ] [P3] Join links on teams.live.com / short links / `meet` URLs — OST: only `/l/meetup-join/` links; anything else opens in the browser (ref: meetings.md §2; OST: outgoing.rs:560–595, Main.qml:1475)
- [ ] [P3] `/call` command, dial from the top search bar, federated calling — OST: absent (ref: calls.md §2; OST: absent)

## 16. Call ended (spec §12)

- [ ] [P2] A normal leave closes the call window at once — OST: shows "Call ended" / "You left the meeting" for 2 s, then closes (ref: spec §12 L945; OST: Main.qml:615–619, CallWindow.qml:302, 429)
- [ ] [P2] Rejoin screen, only after abnormal ends (reconnect failed, removed, not admitted, breakout closed): "Rejoin" / "Rejoin meeting" / "Call back" / "Try again"; "Call was answered elsewhere" — OST: errors go to the status bar and the window closes (ref: spec §12 L941–944; OST: backend.rs:1811–1818, 1942–1951)
- [ ] [P3] Call quality survey — Teams: thumbs "How was the call quality?" [Had issues] [Good], issue categories, sampled at 0.1, `submitCallFeedback` — OST: absent (ref: spec §12 L934–939; calls.md §21; OST: absent)
- [ ] [P3] Short-call prompt "We noticed your call was pretty short…" — OST: absent (ref: spec §12 L940; OST: absent)
- [ ] [P3] Reconnect after network loss — Teams: "reconnect failed" is one of the abnormal ends that leads to Rejoin, so a reconnect attempt comes first — OST: no reconnect code. A `call/replacement/` callback is registered but never handled (ref: spec §12 L941; OST: incoming.rs:1362, backend.rs:1094–1285)

## 17. Keyboard shortcuts (spec §13; calls.md §23; meetings.md §33)

- [ ] [P2] Ctrl+Space push to talk (`togglePushToTalk`) — OST: absent (ref: spec §13 L952, §3 L505; OST: Main.qml:79–86)
- [ ] [P2] Ctrl+Shift+E share tray, Ctrl+Shift+K hand, F11 full screen — OST: absent (ref: spec §13 L954–955, L967; OST: Main.qml:79–86)
- [ ] [P2] Ctrl+Shift+Space sharing toolbar (OS-wide), and global Ctrl+Shift+A/S/D/M/O/H when OST isn't focused — OST: `Qt.ApplicationShortcut` only works while an OST window is focused (ref: spec §13 L957, L964; OST: Main.qml:81–86)
- [ ] [P3] Ctrl+Shift+U, Ctrl+Shift+P, Ctrl+Shift+Y, Alt+Shift+C, Ctrl+Shift+L, Ctrl+Alt+Shift+S, Ctrl+Shift+J/R, Alt+Shift+V, Alt+Shift zoom/pan — OST: absent (ref: spec §13 L958–968; OST: Main.qml:79–86)
- [ ] [P3] Alternative "meetings_alt" profile (Alt+A, Alt+V, …) — OST: absent (ref: spec §13 L973; OST: absent)

## 18. Recording, transcription, captions, notes, Copilot, apps (spec §1.8, §14; calls.md §20; meetings.md §20–22, §28–30)

- [ ] [P2] Record and transcribe ▸ (Start/Stop recording, Start transcription, Transcript pane) and the recording indicator/banner for everyone — OST: a recorder-bot flow exists in `recording.rs`, but only the CLI call test uses it; no desktop UI or indicator (ref: spec §1.8 L314, §14 L991; meetings.md §20–21; OST: recording.rs:323, call_test.rs:530)
- [ ] [P2] Live captions (Language and speech ▸ Captions; Alt+Shift+C), caption settings, spoken-language prompt — OST: absent (ref: spec §1.8 L328; meetings.md §22; OST: absent)
- [ ] [P2] Notes pane in the call window (Loop notes) — Teams: Notes toggles a side pane — OST: opens the meeting chat on the web in the browser (ref: spec §1.3 #10; meetings.md §28; OST: CallWindow.qml:156, outgoing.rs:608–614; TASK-0038)
- [ ] [P2] Controls panel in the call window — Teams: participant permissions and meeting protection; View more options opens the options page — OST: opens the meeting options URL in the browser (ref: spec §1.3 #8; meetings.md §6, §18; OST: CallWindow.qml:154)
- [ ] [P2] Apps flyout "Find apps and more" with meeting apps — Teams: the flyout's contents aren't specified in the spec — OST: a hard-coded list (Whiteboard, Planner, OneNote, Clipchamp); Whiteboard and Clipchamp open the browser [verify against winpc] (ref: spec §1.3 #15; OST: CallWindow.qml:612–628; TASK-0038)
- [ ] [P3] Copilot, Facilitator, Speaker Coach, Interpreter / interpretation, RTT — OST: absent (ref: spec §1.8 L319, L328; meetings.md §28; OST: absent)
- [ ] [P3] Breakout rooms (create/assign/open/close, participant move, return) — OST: Rooms placeholder (ref: spec §1.4 L181; meetings.md §23; OST: CallWindow.qml:157; TASK-0037)
- [ ] [P3] Polls, Q&A, Whiteboard in-meeting, Shared content bin — OST: absent (ref: spec §1.3 #3, #9, §1.8 L322–324; meetings.md §17, §29–30; OST: absent)
- [ ] [P3] Recap tab, attendance report, Recordings and Transcripts tab — OST: absent (ref: meetings.md §31; OST: absent)

## 19. Calls app (calls.md §1–3, §9–11, §13)

- [ ] [P2] Dial pad in the Calls app — Teams: number or name box, a 0–9 * # keypad, paste with formatting tolerated, dial-plan normalisation; hidden without a PSTN plan — OST: "Type a name" person search only (ref: calls.md §1–2; OST: CallsView.qml:108–176)
- [ ] [P2] Group call from the dial box (several names or numbers) — OST: one person (ref: calls.md §2, §5; OST: CallsView.qml:113, 173)
- [ ] [P2] Voicemail — Teams: History filter Voicemail; details pane with transcript and playback (play/pause, scrub, speed); Call back — OST: absent (ref: calls.md §9–10; OST: CallsView.qml:16–17)
- [ ] [P2] History row "More actions" — Teams: Call back, chat, Add to speed dial, Add to contacts, line picker; Recap / View summary — OST: hover Chat and Call buttons only (ref: calls.md §9; OST: CallsView.qml:299–328)
- [ ] [P2] Contacts in the Calls app (an A–Z list with search, contact groups, add from inside or outside the org) — OST: "View contacts" opens Outlook on the web (ref: calls.md §1, §11; OST: CallsView.qml:80–94)
- [ ] [P3] Speed dial stored in the account — OST: kept on this device only [verify where Teams stores it] (ref: calls.md §11; OST: CallsView.qml:27–29)
- [ ] [P3] Bottom-left quick menu — Teams: forwarding status ("Don't forward", "Forward to voicemail", recent targets, call groups, "More Settings") — OST: a speaker picker only (ref: calls.md §1, §13; OST: CallsView.qml:178–208)
- [ ] [P3] Call as myself / delegator lines; number tabs for multi-line; Personal plus delegator tabs with Ongoing/Join; Unpark; emergency location — OST: one static "Personal" tab (ref: calls.md §1, §3, §14, §24; OST: CallsView.qml:68–79)
- [ ] [P3] History limits — Teams: 3,000 records or 6 months — OST: 100 (ref: calls.md §9; OST: backend.rs:918)

## 20. Settings for calls and devices (calls.md §12, §16–17; meetings.md §5)

- [ ] [P2] Settings › Calls page — Teams: call handling and forwarding, simultaneous ring with delay, unanswered handling, busy options, call groups, ringtones, delegates, Manage voicemail (greeting, call answer rules), Viewing incoming calls, call queues — OST: no Calls page (ref: calls.md §12–14; OST: SettingsView.qml:12–18)
- [ ] [P2] Settings › Devices — Teams: Make a test call (`startEchoBotCall`), noise suppression, secondary ringer, camera with preview — OST: speaker and microphone choice only. An echo-bot flow exists only in the CLI (ref: spec §2 L452; calls.md §12, §17; OST: SettingsView.qml:353–372, signaling.rs:672)
- [ ] [P3] Privacy — Teams: blocked contacts, block calls with no caller ID, priority access, "Keyboard shortcut to unmute" (gates Ctrl+Space) — OST: absent (ref: calls.md §12, §16; meetings.md §5; OST: absent)
- [ ] [P3] Do not disturb routing to voicemail / priority access, and busy-on-busy — mostly server-side; the client shows them only through settings — OST: absent (ref: calls.md §16; OST: absent)

## 21. Call quality and status (calls.md §21)

- [ ] [P2] Network strength indicator (3 bars; others' poor networks; bandwidth suggestions) — OST: absent (ref: calls.md §21; OST: absent)
- [ ] [P2] Call health panel (see §3) — OST: logs only (ref: calls.md §21; OST: backend.rs:886–915)

## 22. PSTN, E2EE, delegation, events (calls.md §3, §14–16, §24–27; meetings.md §19, §26, §32)

- [ ] [P3] PSTN calling (dial a number, caller ID, multi-line, private line, the `oneToOnePstn` layout without Camera/Share/View) — OST: Teams-to-Teams only (ref: spec §1.4 L226–228; calls.md §2–3, §25; OST: outgoing.rs:408–421)
- [ ] [P3] End-to-end encrypted 1:1 calls (opt-in, 20-digit security code, disabled features) — OST: absent (ref: calls.md §26; meetings.md §19; OST: absent)
- [ ] [P3] Delegation / shared line, call queues, call park policy, emergency calling — OST: absent (ref: calls.md §14–15, §24; OST: absent)
- [ ] [P3] Webinar / town hall attendee experience, view-only overflow, follow mode, broadcast/producer layouts — OST: absent (ref: spec §1.1 L70–76; meetings.md §26, §32; OST: absent)
- [ ] [P3] Admin and organizer policy gates the client must honour (AllowPrivateCalling, video/screen-sharing policies, `allowMeetingChat`, `allowTeamworkReactions`, `allowedPresenters`…) — OST: no policy is read; controls appear regardless (ref: calls.md §27; meetings.md §18; OST: absent)

---

## Ordered build plan

Order follows dependencies: media and signalling first, then the UI that consumes them. **R** marks items that need protocol research. The Teams services are named as OST's code and the spec name them: call controller (`*.cc.skype.com` call-leg links), conversation service (epconv / `api.flightproxy.teams.microsoft.com` conversation links and roster callbacks), media processor (MP; the conference media endpoint), conversation broker (`links.subscribe` / brokerPublish), ECS config, Trouter push.

1. **Meeting and group-call media through the media processor (R)** — video subscription (send ours, receive others), applicationsharing send and receive, `dominantSpeakerInfo` / `csrcInfo` handling. Unblocks §4 tiles and active speaker, §12 share in meetings, and the pre-join preview. Services: media processor (SDP/NGC offer with video and sharing lines; subscription messages), call controller re-offer/acknowledge (already done for 1:1). Tasks: TASK-0036 AC #2, TASK-0034 AC #2.
2. **Audio processing** — echo cancellation, noise suppression, AGC in the capture path, plus in-call device switching. No protocol work, and every call depends on it. Then Mute through `toggleMuteWithState`-equivalent signalling **(R: call controller / conversation endpoint state `isMuted`)**, so rosters show you muted.
3. **Lobby, both sides (R)** — detect the InLobby state on join (conversation service `controllerName:"lobby"` / admit links appear in OST's SDP dictionary); keep PreJoin up with the lobby texts; organizer admit/deny/admit all and the lobby toast. Services: conversation service (`admit` link, `callLobbyService` equivalent).
4. **Toolbar engine** — read or embed the live `Inline` preset and the per-call-type overrides (§1.1); visibility and disabled-reason rules (§1.4); tooltips with shortcuts; width-driven overflow into More; correct More menu skeleton (§1.8). Pure UI on top of existing state. Fix the incoming-group-call → `default` layout routing at the same time (needs the invitation's group flag; **R: call controller invitation fields**).
5. **Stage layout** — the 16:9 grid-fitting algorithm, self in grid, side/top bars, pagination, gallery size, Speaker view on the active speaker, the full View menu, layout persistence (**R: user preferences service** for `updateUserExperiencePreferences`, or keep locally until researched). Depends on 1 for video tiles.
6. **Camera ▾ / Mic ▾ flyouts and the device/effects side panes** — device lists, level meters, volume, noise suppression switch, camera preview. Depends on 2. Background effects are a separate local job (segmentation); decide policy since Teams on Linux lacks them.
7. **Pre-join completion** — camera preview and toggle (after 1/6), Connecting and lobby states (after 3), real computer-audio rows, cached choices, `joinOptions` carrying mic/audio state instead of muting after join (**R: conversation service join body**), narrow layout, participant summary (**R: which service gives "n others joined" before join**).
8. **Leave ▾ / End meeting (R)** — End for everyone (`stopCall forEveryone`, likely the conversation service's end link; needs research), Leave on all my devices, the sharing speedbump.
9. **People pane** — sections, sort, search, row icons, then the management actions **(R: conversation service links `mute`, `removeParticipant`, `addParticipant`, role change, attendee restrictions, `updateMeetingLock`)**. Fill roles and hands for pre-existing participants (`getAllParticipants` response fields; **R**). Invite field depends on `addParticipant`.
10. **Raise hand completion** — `raiseHandRank` from published states (**R: roster field name**), popup, auto-lower (needs speaking detection from 2), lower others/all (`removeStatesForEveryone`; **R**), Ctrl+Shift+K.
11. **Reactions (R)** — subscribe to the conversation broker and publish Reaction messages; tile and floating overlays. TASK-0035.
12. **Share tray and Sharing control bar** — tray UI (thumbnails via the PipeWire portal on Wayland), Include sound (PipeWire audio capture), separate control-bar window; then Give/Request control **(R: screen-sharing control messages; the service is unverified, likely the MP data channel or the call controller)**.
13. **Compact view** — a separate window on minimize, with per-mode toolbars. Depends on 4 for toolbar layouts and 5 for tiles.
14. **1:1 telephony depth** — Transfer dialog V2 (suggestions, safe transfer, voicemail/mobile targets; **R: call controller `transfer` body fields `isSafeTransfer`, `transferToVoicemail`**), voice consult (`startConsultation`; **R**), call waiting with auto-hold (multi-slot `CallSlot`), Resume button placement and hold texts.
15. **Entry points** — Video call in chat headers (offer video on start; the media path exists), Meet now (**R: Graph `onlineMeetings` or the Teams meetnow service**), Join with ID (**R: meeting-ID resolution service**), join from chat/channel/join bar/started toast (Trouter meeting-started event; **R**).
16. **Call-ended flows** — close on normal leave, Rejoin screen on abnormal ends (call controller end codes), reconnect handling (**R: call controller reconnect/replacement links**); survey (`submitCallFeedback`; **R: feedback service**) last.
17. **Recording/transcription/captions** — wire the existing `recording.rs` recorder-service flow to the More menu with indicators; captions **(R: captions service; unverified)**.
18. **Calls app and settings** — keypad dialling (PSTN needs a licensed test account), voicemail (**R: voicemail via Exchange/Graph**), forwarding/call groups/delegates settings (**R: user calling settings service; data model as in `Set-CsUserCallingSettings`**), Make a test call (echo bot exists in `signaling.rs:672`), call health panel from existing stats.
19. **P3 tail** — breakout rooms (TASK-0037; conversation service meeting-group links), embedded Notes/Whiteboard/Apps (TASK-0038; needs QtWebEngine or native Loop), park/merge/lock, PSTN/E2EE/delegation/events, customization (verify live flags first).
