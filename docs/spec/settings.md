# Settings — Teams desktop behaviour (spec)

Measured on winpc (Teams desktop as ost-test1), 2026-11-10. Each synced setting was found by
flipping it in Teams and putting it back while recording the requests (page and worker
targets). The dumps and screenshots live in the session scratchpad.

## Layout

- **Left pane:** 380 wide. "Settings" (18/25.7 bold) sits at 32, 20, and "Find in Settings
  (Ctrl+F)" (332 x 32) at 32, 73.
  - Pages start at 17, 120: 346 x 32 each, one every 33. The icon (20) is at 16.7 and the
    label (14) at 49.7.
  - The open page is white with a 0.67 rgba(0,0,0,0.05) border, and its icon is filled in
    brand.
  - About sits at the bottom, 17 up.
- **Page order:** General, Appearance, Chats and channels, Notifications and activity,
  Accounts and orgs, Privacy, Accessibility, Devices, Calls, Files and links, App permissions,
  Recognition; About Teams.
- **Header:** 61 tall, with the title (18/25.7 bold) at 20, 17.6. A sub-page shows
  "Page › Sub-page", for example "General › Out of office".
- **Page:** a scroller padded 0 8 32 20. Cards are 790 wide, from 12 down, 12 apart.
  - A card has a 0.67 #D1D1D1 border, radius 8 and padding 20 x 12.
  - Its icon (20) sits at 18.7, 26.7, its title (14/20) at 57, 27, and the subtitle (12/16
    #616161) under the title.
  - Rows start 42 under the title, at x 57.
- **Rows:**
  - Switch rows are 51 tall. "On"/"Off" sits before a 40 x 20 switch whose right edge is 57
    in from the card's.
  - Checkbox rows are 47 tall: a 16 px box and the label 28 in.
  - Radio rows are 32 tall (48 with a second line).
  - Image radio cards are 169.3 x 130.3, radius 4, with a #E0E0E0 border and shadow2. The
    140-wide picture sits at 12.7, 14.7; the label and the radio glyph (20) run along the
    bottom. Pictures come from `teams.public.onecdn.static.microsoft/evergreen-assets/…`.
  - A single-setting card puts its switch on the title's row (y 43) or its button there
    (y 29).

## Where settings are kept

Synced settings live in chat-service user properties:
`PUT {chatsvc}/v1/users/ME/properties?name=<name>` with body `{"<name>": "<string>"}`, where
JSON objects are stringified and Teams sends the whole merged object. Read them all with
`GET {chatsvc}/v1/users/ME/properties`. A setting nobody has changed is absent and takes
Teams' default.

| Page | Setting | Kept in |
|---|---|---|
| Chats | Show message previews | simpleCollabUserSettings.hasUserEnabledMessagePreviews |
| Chats | Show time stamps | simpleCollabUserSettings.hasUserEnabledShowTimeStamps |
| Chats | Filters | simpleCollabUserSettings.hasUserDisabledShowingFilterAtTop (inverted) |
| Chats | Copilot | userPersonalSettings.messagingSettings.shouldShowMetaOSCopilotApp |
| Chats | Auto-follow (3) | userPersonalSettings.teamsAndChannelsSettings.autoFollow{Authored,Participated,AtMentioned}{Threads,Posts} |
| Chats | Message density | messageDensity COMFY / COMPACT |
| Chats | When I open a chat | userPersonalSettings.messagingSettings.navigateToLastReadMessage |
| Chats | Enter to send | local |
| Chats | Read receipts | readReceiptsEnabled |
| Chats | Post channels' recent activity | enableChannelsV2 ("false" = at the top) |
| Chats | Suggested replies | suggestedRepliesSettings.suggestionsEnabled |
| General | Starting chats in a new window | userPersonalSettings.messagingSettings.alwaysPopOutNewChat |
| General | System, opening content, meeting, efficiency | local |
| General | Meeting ▸ New meeting controls | device-local (Teams Labs cache storage `feature-32b3a453-…`; OST setting newMeetingControls) |
| Appearance | Theme, dark calls, app bar | local |
| Appearance | Skin tone | preferredSkinToneIndex |
| Privacy | Surveys | userEnableSurveysNotification |
| Privacy | Attendance reports | showInMeetingReport |
| Privacy | Keyboard shortcut to unmute | enablePushToTalk |
| Privacy | Automatic work location | placesSettings (JSON: autoUpdateLocationPreference "Enabled"/"Disabled", autoLocationFirstEngagement) |
| Privacy | Stationary device location | device-local (Teams' client preferences places.deviceHomeBuildingId; OST setting deviceHomeBuildingId) |
| Accessibility | Sign language mode | callAccessibilitySettings.accessibilityModeEnabledV2 |
| Accessibility | Always show captions | callAccessibilitySettings.startCaptionsAutomatically |
| Accessibility | Profanity filter | callAccessibilitySettings.profanityFilterEnabled |

Middle tier (`{mt}`):

- **Auto DND while sharing:** `PUT beta/usersettings/allowAutoDndSettings {"isEnabled"}`.
  It is write only and on unless saved off.
- **Block calls with no caller ID:** `POST beta/usersettings/blockedCallers
  {"blockAnonymousCaller"}`; read it with GET.
- **Identify me in captions and transcripts:**
  `PUT beta/users/updateUserTranscriptMeetingSettings/tenant/{t}/user/{o}
  {"attributionSettings":{"enableSpeakerAttribution"}}`; read it from
  `GET beta/users/getUserTranscriptMeetingSettings/…`. Teams raced on a quick flip-back and
  sent false twice.
- **Out of office:** `GET beta/users/automaticRepliesSetting`, and
  `POST beta/users/updateAutomaticRepliesSetting` with status (disabled / alwaysEnabled /
  scheduled), internalReplyMessage, externalReplyMessage, externalAudience (none /
  contactsOnly / all), scheduledStartDateTime and scheduledEndDateTime.
  - The profile flyout's "Schedule out of office" opens Settings › General › Out of office.
  - Teams' page keeps its first read and doesn't re-read on reopen.
- Turning "New meeting controls" off opens "Submit feedback to Microsoft"; never submit it.
  The setting is a Teams Labs feature kept on the device only; see
  new-meeting-controls.md.

## Calls (captured 2026-11-10)

- **Call handling and forwarding:** read from `GET {mt}/beta/usersettings/{mri}/voicesettings`
  (callRedirectionSettings) and saved with `POST …/callredirectionsettings`, the whole object:
  - Forward all: callForwardingSettings {isEnabled true, Immediate, Voicemail}, with
    unanswered off.
  - Otherwise: {isEnabled false, Simultaneous}, with unansweredCallSettings {isEnabled,
    targetType Voicemail, delaySeconds 5–60 (20 default), safeForward false},
    callGroupDetails {simultaneous, 0, []} and favoriteTargets {[]}.
  - "When you can't answer a call" offers "Do not redirect calls" and "Redirect to
    voicemail".
- **Voicemail:** `POST …/voicemailsettings` with nine keys, only the changed one set and the
  rest null (vmUseOof, vmUseAutoRepliesForOof, vmCallAnswerRule, …). There is no GET for it.
  - vmCallAnswerRule values: RegularVoicemail (record a message), VoicemailWithTransferOption
    (record, or be transferred), PromptOnly (greeting, then end), PromptOnlyWithTransfer
    (greeting, then transfer), DeclineCall (end without the greeting).
  - The two transfer rules first ask for a transfer target in a people picker.
- **Ringtone:** `POST …/ringtonesettings {"assignments":{"ringToneAssignments":[{type
  Regular, value "Beep", associatedEntityId ""}]}}`, with [] for Default.
  - Choices: Default, Beep, Bop, Bounce, Bubbles, Bubbles (Loud), Drip Drop, Eureka, Flutter,
    High Score, Next Level, Plink, Remix, Ring Ring, Ripple, Spacetime, Wish Granted, Wobble.
  - The sounds are MP3s in Teams' package (Audio/*.mp3).

## Files and links (captured 2026-11-10)

- Downloads location (Change) and "Always ask where to save downloaded file": local.
- "Always open Word, PowerPoint, and Excel files in": Teams / Browser, kept in
  userPersonalSettings.filesSettings.fileOpenPreference ("teamsV2" / "web").
- "Always open web links in": a local browser choice.
- File previews: userPersonalSettings.filesSettings.enableThumbnailPreview.

## Notifications and activity (captured 2026-11-10)

Everything below is in userPersonalSettings unless marked local.

- **Mute all (except calls and meetings):** toastSettings.muteGenericNotifications On/Off.
  "Always allow urgent and priority contact notifications" is enabled only while muted.
- **Sounds:**
  - Play sounds with notifications: soundsSettings.alertSound All/Off.
  - Urgent and priority: toastSettings.PlayNotificationSoundsForUrgentAndPriority.
  - Calls and meeting start: soundsSettings.incomingCallsAndMeetingStartSound.
  - When busy: toastSettings.PlayNotificationSoundsWhenBusyOrInMeetings.
- **Display:**
  - Previews: toastSettings.ShowPreviewInToasts. With it off, the body is "Message preview
    hidden".
  - During calls and meetings: toastSettings.MuteNotificationsDuringMeetings (On = hide).
  - Flash taskbar, dismiss time (5 s default, 7 s, 15 s, 30 s, 1 min, 5 min), position and
    size: local.
  - Test notification: "This is a test notification" / "Message preview.".
- **Missed activity emails:** emailSettings.EmailNotificationDelay, one of Immediately,
  Every10Mins, Hourly, EveryEightHours, Daily or Never.
- **Chat messages:** toastSettings.Chat with activityGenerationSettings.Chat (Off / Show in
  banner).
- **Mentions:** Show in Activity and banner / Show in Activity / Off set toastSettings,
  activityGenerationSettings and emailSettings for each key:
  - Channel and team: Mention_Team and Visible_ChannelMention_v2.
  - Tag: Mention_Tag.
  - Everyone in chat: MentionInChat_Everyone.
  - Personal (no Off): Mention_Person and MentionInChat_Person_v2.
  - Replies: Reply and ReplyToReply. Likes: Like and LikeInChat_v2.
  - The @Mentions master switch didn't restore its sub-settings on a round trip in Teams.
- **Meetings:**
  - Meeting start: toastSettings.MeetingWentLiveNotification.
  - Join bar: toastSettings.liveMeetingStatusBanner.
  - Meet now start: toastSettings.HuddleStartedNotification (off by default).
  - Meeting chat: chatSettings.meetingChatNotificationFor{Accepted,Tentative}Meetings.
- **Calendar:** userGraphSettings.{app id}.{toastSettings,activityGenerationSettings}.privateMeeting….

## App permissions (measured 2026-11-13)

- One card (790 wide, a 0.67 #F0F0F0 edge, radius 8): the shield at 18.7, 22.7, "App
  permissions" (14/20) at 68.5, 5.5, then "Control what your apps can access when using Teams.
  Some apps have permissions enabled by default for your convenience. Learn more" (12, line
  17.14).
- An expander per app, 65.33 tall and 75 apart from 64.7: the icon (32, a 0.67 #F0F0F0 edge,
  radius 6) at 19.3, 16.6, the name (14/20) at 69.3, 22.6 and a chevron at 754.7. Open, each
  permission the manifest asks for: the filled and regular glyphs at 59.3 and 94.3, the title
  (14/20) at 129.3 over its subtitle (12/16, light: "Always" for Notifications, "Only when app
  is open and in view" for the others), a switch at 698.7 with no On/Off label; then "Note:
  Permission updates will be applied the next time you open or refresh this app."
- The apps (worker resolver `installedAppsPermissions`): your installed apps (aggregated
  entitlements) that ask for device permissions, every app in your teams' entitlements
  (whatever its state, so suggested ones like ScrumGenius show), and any app whose permissions
  were changed; by name, 100 at most. On OST Test 1 that is the same 22 apps Teams lists.
- The switches stay on the device (Teams made no request when one was flipped).

## Recognition (seen 2026-11-13, built 2026-11-15)

- Voice Recognition and Face Recognition cards with Microsoft's biometric consent text and Start
  voice capture / Start face capture (face: "Create my face profile now", "Takes about 30
  seconds"). Built in TASK-0153: OST enrols, updates, exports and deletes both profiles with
  Teams' biometric service (`api::biometric`), with Teams' capture dialogs.

## Calls ▸ Voicemail ▸ Record a greeting (read 2026-11-17)

- The card's first row (measured on winpc 2026-11-10): "Record a custom greeting" with the
  secondary button "Record a greeting" (138.3 x 31.3) at the body's top, a divider 15 under it,
  then the greeting language.
- The button is Teams' `ComponentsCallSettingsStartCallMutation`: `startCall(conversation: {id:
  <your MRI>}, isVoicemail: true)`. Teams' `startVoicemailCall` makes a 1:1 call to yourself,
  titled "Voicemail" (calling `voicemail_call_title`), `startCallToVoicemail({voicemailResourcePath:
  "greeting"})`. The call request names the callee `{id: <your MRI>, endpointType: "voicemail"}`
  and carries `callInvitation.voicemailSettings {localResourcePath: "greeting"}`; Teams'
  voicemail service (`28:14524421-25b4-403a-a0f7-e62d4379cabc`) answers it.
- In the call (`isVoicemailGreeting`; measured on winpc 2026-11-17): the bar is Mic, Dial pad,
  More (only Audio settings) and Leave, with the dial pad open from the start; no Chat, People,
  View, Apps, Camera, Share, recording indicator, hold, transfer or park.
- The voicemail's menu (heard 2026-11-17): 1 plays and records your personal greeting ("Please
  record your greeting after the tone… press the pound key", then 1 accept, 2 re-record, 3
  delete and use the default greeting, * cancel), 2 the away greeting, * exits.
- OST: `outgoing::call_own_voicemail`, Backend `record_voicemail_greeting`, the ubar fact
  `voicemail`.

## Devices ▸ Spatial audio (read 2026-11-17, row measured 2026-11-14)

- The row sits in Audio settings after Voice isolation, between dividers (30.7 under the first,
  30 over the next), Fluent's person-sound-spatial glyph in the card's icon column centred on
  it: "Spatial audio" over "Voices will sound like they're coming from where each
  person is positioned on your screen. Not yet available with wireless headphones. Available
  with Together mode, Gallery and Speaker view. Learn more" (12 px, #616161), the switch centred
  on the text. Learn more:
  https://support.microsoft.com/en-us/office/spatial-audio-in-teams-meetings-547b5f81-1825-4ee1-a1cf-f02e12db4fdb
- It is kept on the device (`spatialAudioEnabled`), off by default (`enableSpatialAudioDefaultOn`
  false). It shows Off and disabled when the speaker isn't spatial capable (slimcore's
  `isSpatialCapable`: stereo, not wireless) or during a 1:1 call.
- In a call (`SpatialAudioMixinImplementation`) it applies while the layout is Gallery, Speaker
  or Together mode, the call isn't P2P and more than one other person (not bots) is in it. The
  call window sends each tile's place on the stage in percent
  (`updateSpatialAudioParticipantsPosition`, at most every 240 ms) and Teams passes
  `[{participantId: <audio sourceId>, x, y}]` to the media stack. Teams' own path receives the
  speakers unmixed (codec `x-much2`/`x-much3`) and pans each with an HRTF panner.
- x-much2 on the wire (received from Teams' media processor 2026-11-17): offered as
  `a=rtpmap:113 x-much2/48000/2` ahead of Opus, the answer keeps it and the media processor
  sends every meeting audio packet as PT 113 from its mix SSRC, the active speakers in the
  CSRCs (plus a one-byte header extension, id 3, counting packets). The payload is: u8 stream
  count, then per active speaker u8 kind (0x44: Opus), u32 audio source id (big endian, the
  roster sourceId), u16 frame length (big endian) and the frame: 20 ms of mono Opus at 48 kHz
  (SILK wideband, TOC 0x48). Each speaker's frames decode on their own with libopus.
- OST (`calling::spatial`, `calling::much`): while spatial audio is on and the speaker can play
  it, a meeting offers x-much2; each speaker gets their own Opus decoder and their own placer
  (equal-power pan over ±60° with the interaural time difference) at their tile, and the
  placed voices are summed in stereo. Without x-much2 (spatial audio off at join, or a mix) the
  mix is placed at its CSRCs' mean place.
- Mid-meeting: Teams' audio codec manager raises `negotiationNeeded` when spatial audio is
  turned on or off (`configureSpatialAudio` → `triggerRenegotiation`), and the call re-offers
  through the leg's `mediaRenegotiation` link (`renegotiateOutgoing`). OST does the same
  (`Reoffer::Unmixed`): its current description re-offered with x-much2 added first on the
  audio line or taken off it; the media processor's answer keeps or drops it and its packets
  switch to per-speaker or the mix (measured 2026-11-17: the answer arrived in ~0.45 s both
  ways).

## Devices ▸ Automatically adjust camera controls (read 2026-11-17, row measured 2026-11-14)

- In Video settings under Camera: "Automatically adjust camera controls" with its switch (a 36
  px row, 30.7 under the camera). With the switch off, "Open camera settings" (14 px, brand;
  on Windows after a 16 px Windows logo, which OST leaves out) right under it and "Some
  settings might not be available for all camera types." (12 px on a 17.1 line), 30 over Green
  Screen.
- The switch is the preview renderer's `cameraAutoControl(enable)`: the camera's own automatic
  exposure, white balance, focus and gain. Teams keeps the choice on the device
  (`automaticCameraSettingsSelected`); until one is made it shows what the camera is set to.
- Open camera settings opens Windows' camera settings (`ms-settings:camera?cameraId=…`, where
  `enableWindowsCameraSettingsLaunch` is on, Windows 11) or else the camera's own settings
  (`openCameraSettings`, its driver's property page).
- OST: `calling::camera_controls` (V4L2: `auto_exposure`, `white_balance_automatic`,
  `focus_automatic_continuous`, `gain_automatic`, `hue_auto`; off keeps the values the camera
  reached), applied whenever a camera opens; Open camera settings opens OST's camera settings
  (CameraSettingsDialog) with the camera's controls, each with Auto where it has one.

## Accessibility ▸ Teletypewriter (TTY) mode (read 2026-11-17, card measured 2026-11-16)

- The last card (93.3 tall): Teams' accessibility glyph, "Teletypewriter (TTY) mode" and "Use the
  TTY mode to communicate using text over the phone. For this to work, you’ll need to connect a
  TTY device." with its switch. After a change the card shows Teams' info glyph and "Changes
  will be applied for your next call" (`tty_dialog_active_call_warning`, also announced).
- The switch is `toggleTTYSetting` → `deviceManagerService.enableTTYSupport` → the media stack's
  `mediaConfigurationService.enableTtySupport` (`setMediaConfig {enableTtySupport}`), kept in local
  storage and loaded at start (`loadTTYSetting`); desktop only (`showTTYSettings`).
- Natively RtmMediaManager parses `enableTtySupport` into the audio channel's `EnableTty` and the
  audio engine's TTY mode (`AudioEngineSetSettingTTyMode`, beside `EnableSilenceSuppression`,
  comfort noise and receive AGC).
- OST (`apm::set_tty_mode`): a call that starts in TTY mode sends the microphone unprocessed (no
  echo cancellation, noise suppression or gain control) and Opus at 64 kbit/s CBR in its CELT
  mode, so a TTY device's Baudot tones go through whole.

## Devices ▸ Connected devices (measured 2026-11-15)

- The last card on Devices (204.9 tall, a laptop icon): "Manage your connected devices" with
  **Manage devices**, and "Automatically activate meeting room mode when in a meeting" (on by
  default) with "Optimizes meeting setup for connected audio/video devices and room displays.
  Attendees see only meeting content on the room display. Learn More"
  (https://aka.ms/meetingroommode). Teams keeps the switch on the device (clientPreferences
  `byod.pushToRoomAudio`); OST keeps it as the local setting `pushToRoomAudio`.
- **Manage devices** opens "Devices › Manage devices": "Select a device to connect", the Teams
  phones paired with this PC (Teams' Better Together). OST pairs with no phone, so the list is
  empty, as on a PC with none (pairing is TASK-0162).
- Meeting room mode acts in the pre-join screen. A connected room device is a USB device that
  is both a speaker and a microphone (no headsets). OST reads these from PipeWire with their
  USB ids (`calling::room_devices`). If the device's id is on Teams' `byodRoomDeviceVidPids`
  list, Room audio is picked with it and the device's speaker, microphone and camera are
  chosen. With meeting room mode off, Room audio is only marked "(suggested)". Joining with
  it opens the shared display on a second screen and shows Teams' "Connected to a room
  device" notice (its explanation the first three times).

## Privacy ▸ Manage my work location (measured 2026-11-15)

- **When it shows the switch.** Teams maps the user's effective `teamsWorkLocationDetectionPolicy` (middle tier `POST beta/users/effectivePolicies`) onto `places.enableWorkLocationDetectionPolicy` and `places.adlUserSettingsDefault`. The switch shows when that policy is on and the ECS flights `places.enableAutoDetectPlaceWifi` and `places.enableAutoDetectLocationToggle` are on. "Manage stationary location" also needs `places.adlWiredCheckout`, which defaults to on. With the policy off, the card says automatic work location "has been turned off by your IT department".
- **Card layout.**
  - The header (title 14/20, subtitle 12 on 17.14 lines) is 54.3 tall. The subtitle ends with the link "Learn about automatically setting a work location".
  - "Manage stationary location" (31.3 tall) sits 12 under the header. The Outlook note (12/17.14) sits 12 under that.
  - The switch ("On"/"Off" before it) is centred on the whole card. The card is 185.2 tall.
  - Links are #4F52B2 and not underlined.
- **The switch's value.** It is the user property `placesSettings.autoUpdateLocationPreference`. Teams writes it with `autoLocationFirstEngagement: "SETTING_TOGGLE"` (`PUT chatsvc v1/users/ME/properties?name=placesSettings`).
  - An unset preference is on only when the policy default is "Enabled", `adlEnableDefaultOptIn` is on, and this isn't the first run. Otherwise `adlSettingDefaultEnabled` or `tpp` decides.
  - Turning it on also asks Places to detect the location now (`attemptAutoDetectLocationOptIn`). The Wi-Fi and peripheral detection is still to do.
- **Learn about… dialog.**
  - 600 wide, radius 8, centred. Teams' illustration (598.67 × 319.33) runs across the top.
  - "Why set my work location automatically?" (20/28 semibold) sits 24 under the picture, followed by two paragraphs (14/20, 16 and 20 apart).
  - The buttons (31.33 tall) sit 36 under the text, at the bottom right. With the setting off they are "Not now" and "Set my location automatically" (primary; it turns the setting on). With it on there is only "Got it" (primary).
- **Stationary device location** (Privacy › Stationary device location).
  - The text "Set a permanent location for stationary devices that stay in one building. When Wi-Fi isn't detected, this device will remain checked in at the selected building instead of being automatically checked out." (14/20 #424242) sits 8 down.
  - "Permanent device building" (14 semibold) sits 16 under it. A "Find a building" combobox (300 × 32, chevron-down 20) sits 15 under that.
  - The list opens beside the box: 2 to the right, 4 up, 300 wide, padding 4.
  - The buildings come from Places: middle tier `GET v2.0/places/findPlaces?filterQuery=Type = "Building"`, which replies `{"data":{"places":[…]}}`. With none, the list shows a disabled "No buildings found" (#BDBDBD).
  - The choice is this device's own, not synced.

## Appearance ▸ Theme ▸ High contrast (measured 2026-11-15)

Teams' fifth theme, after Classic. It is Fluent's Teams high-contrast palette (all token values: `docs/spec/teams-tokens-high-contrast.json`):
- **Surfaces** are black: panes, the title bar, cards, bubbles, menus and inputs.
- **Text, icons and strokes** are white. `TransparentStroke` is also white, so bubbles, cards, menus, dialogs, reaction pills and filled inputs all get a white outline.
- **Hover, pressed and selected** use #1AEBFF, with black text and icons on top. Examples:
  - the selected chat row and the selected Settings nav item;
  - the selected app-bar item, which fills all of its 68 × 44 with a black bar;
  - a checked switch track or checkbox (0.67 px white border on the switch).
- **Brand** (`BrandBackground`, the primary button) is white with black text. `CompoundBrand`, used for indicators such as the tab underline and the skin-tone bar, is #1AEBFF.
- **Links** are #FFFF00. **Disabled** is #3FF23F: text, strokes, and the "Always use dark theme for calls" label.
- **Badges** are white with black numbers.
- **Avatars:**
  - a person's or group's picture sits inside a 2 px white ring;
  - a meeting's calendar glyph is white on black in a 0.67 px white ring.
- A pressed reaction has a 1.33 px white outline; the others 0.67 px.

How OST does it:
- `Theme.highContrast`; `dark` is also on, so dark assets are used.
- `pick(light, dark, hc)`. Every colour in the QML has a High contrast value, chosen by its role (background, text, stroke) and state. Literal colours use `theme.hc(...)`.
- `theme.onFill(fills, colour)` makes text black on whatever light fill is under it.
- Content colours (skin tones, avatar palettes, charts) keep their own colours.

## OST status

- Built: the left pane and header, General (System, opening content, Out of office, keyboard
  shortcuts), Appearance (theme, skin tone), Chats and channels, Privacy (auto DND, block
  anonymous calls, surveys, attendance reports, unmute shortcut), Accessibility (sign
  language mode, captions settings) and Devices.
- Calls: forwarding, unanswered calls, ring delay, the voicemail answer rule (no transfer
  rules) and out-of-office voicemail.
  - Choose a ringtone for you (TASK-0144): Teams' 18 ringtones (assets/sounds, Teams' own
    files), saved with `POST {mt}/beta/usersettings/{mri}/ringtonesettings` and read with
    `POST {mt}/beta/users/useraggregatesettings {"voiceAdminSettings": true}`; incoming calls
    ring with it on the speaker and the secondary ringer.
  - Record a greeting (TASK-0152): Teams' call to your own voicemail.
  - Not built: the transfer rules (they need the people picker).
- Files and links: the download location (OST's downloads use it), the file-open choice,
  file previews, "Always ask where to save downloaded file" and "Always open web links in:"
  (TASK-0119; docs/spec/file-actions.md).
- Accounts and orgs: the account card (picture, name, e-mail, Manage) and the organisation;
  not "Refresh license and restart".
- Notifications and activity: OST's banners follow mute all (with urgent allowed), chat and
  personal-mention banners, previews, calls and meetings, sounds, the dismiss time, taskbar
  flash and Meet now start notifications.
  - Display ▸ Position on the screen and Size (TASK-0145): kept on the device as
    `notificationCorner` (BR, TR, BL, TL) and `notificationSize` (COMFY, COMPACT), as Teams
    keeps them in its device-wide notificationCrossCloudSettings. Shown only where OST draws
    its own banners (not on GNOME's Wayland).
  - Display ▸ Flash taskbar has no "taskbar flashing setting in your Windows OS settings"
    line: that setting is Windows'.
  - Sound (TASK-0144): Teams' notification and urgent sounds (toastSettings.alertSoundType,
    alertUrgentSoundType) with Preview; banners play them; the meeting-started banner plays
    Teams' meet-up reminder.
  - Not built: posts in shown channels, meeting chat, Presence ▸ Manage notifications and
    Calendar.
- App permissions: built (the list by Teams' rule, the expanders and switches, kept on the
  device and honoured by OST's app views).
- Recognition (TASK-0153): Teams' voice and face cards in each of Teams' states, the voice
  capture (16 kHz recording → Azure Speech signature → `v2/voice/enroll`), the face capture
  (Center, Left, Right photos → signature service → `beta/me/face/enroll/mandatory/signatures`),
  passive voice opt-in and Opt out, Export, and Teams' completion step; api::biometric.
- Still to build: the remaining items on built pages.
- Chat list (measured with the settings on):
  - Previews: chat rows are 52 tall, with a 36 px picture at 16, 8, the name at 64 and the
    preview (12/16 #616161) at 64, 26. It reads "You: …" for yours and "Name: …" in groups.
    Teams' own words for system events and media ("Bot added", "User added", "Sent an
    image", "Recording is ready", …; messaging 390776 `u`) show in italics.
  - Time stamps: 12/16 #616161, 12 from the row's right, on chats and channels alike: the
    time today, else M/d.
  - Filters off: no pills, and the list starts right under the header.
- Saved and acted on (TASK-0090): compact density, auto-follow (the service's), suggested
  replies and chat landing. Saved but not yet acted on: the Copilot row and sign language
  mode.
