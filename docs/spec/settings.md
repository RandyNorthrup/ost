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
- **Voicemail** (settings-app `$a`/`bA`/`rg`, 527114 getVoicemailSettings; read 2026-11-19):
  - Read: the voice admin settings' `electedSettings` (`POST {mt}/beta/users/useraggregatesettings
    {"voiceAdminSettings": true}` → voiceAdminSettings.value.electedSettings).
  - Save: `POST …/voicemailsettings` with the nine VoicemailSettingsInput keys (vmEnabled, vmUseOof,
    vmUseAutoRepliesForOof, vmUseCalForOof, vmCallAnswerRule, vmAudioLang, vmTransferTarget,
    vmDefaultGreetingPromptOverwrite, vmDefaultOofGreetingPromptOverwrite). It sends the current
    settings with the change; keys never read go as null, which is what the 2026-11-10 capture
    showed. A rule change also sets vmEnabled true.
  - vmCallAnswerRule values, in Teams' order: RegularVoicemail ("Let the caller record a message"),
    VoicemailWithTransferOption ("Let the caller record a message or be transferred to someone
    else"), PromptOnly ("Play your greeting and end the call"), PromptOnlyWithTransfer ("Play
    greeting then transfer the call to someone else"), DeclineCall ("End the call without
    playing your greeting"). Long options wrap: 32 or 52 tall, 2 px apart.
  - A transfer rule picked with no target is held on the page, with its people picker, until
    someone is picked.
    - Then `vmTransferTarget {objectId, tenantId (only with an object id), type User (8:orgid) |
      ApplicationEndpoint (28:orgid, call queues and auto attendants) | Pstn, sipUri null,
      telUri: the MRI minus its first "4:"}` is saved with vmCallAnswerRule.
    - The saved target shows as `8:orgid:` / `28:orgid:` + objectId, or `4:` + telUri.
    - Delete only clears the box; nothing is saved.
  - Picker (measured on winpc 2026-11-19), 15.6 under the dropdown, at the body's right:
    - Box: 294 x 33.3, filled #F0F0F0, radius 4, text 12 in, "Type a name or number" #424242.
    - Suggestions (filter voicemailTransferTarget: AADTenant, Guest, B2BMembers, Bot,
      DisabledUser, ModernGroup, UserDefinedGroup, Pstn, CallQandAA, SkypeConsumer; not you)
      appear right under the box: Fluent surface, padding 4. Rows are 50 tall: picture 32 at
      12, 9; the name 14/20 at 60, with the typed part bold; a second line 12/16 #616161 at 27.5.
    - Typed text with three or more letters is read as a phone keypad number and offered first
      ("+1 6788378" for "OST Test"), with a #48D1CC person picture and an External badge
      (12/600 white on #616161, radius 4, 24 tall).
    - The chosen target: a 294 x 48 box of the same fill; picture 32 (with presence) at 12, 8;
      the name 14 at 52; Delete (32 x 31.3, delete-20 #424242, tooltip "Delete") at 255, 8.3.
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

## Devices ▸ Audio device button controls and Sync device buttons (measured 2026-11-17)

- Teams (desktop, outside VDI: `enableSyncDeviceButtonsToggle`) shows two rows in the Audio settings card between
  "Make a test call" and Noise suppression (dividers above and below, at 30): "Audio device button controls" ("Choose
  whether this Teams app responds to buttons on connected audio devices.", headset glyph) with "Transfer controls to
  this app" (disabled, tooltip "This app already responds to buttons on your audio device.", while this app has the
  buttons), and "Sync audio device buttons when in use on this app" ("The Teams buttons will always work when this app
  is in use. (Recommended)"), a switch centred on its two lines. Without Teams' multi-app HID control
  (`hid2MultiCloudMultiAppEnabled`) the switch alone shows, as "Sync device buttons" ("This lets you use all the
  buttons on your device. The Teams button will always work.").
- The switch is `audioDeviceSyncEnabled` in Teams' device settings (local storage), on unless turned off. Off, the
  call-control reports (Telephony page, LEDs page, Button 7) are ignored and the headset's lights aren't set; the Teams
  button still works. OST keeps it as the local setting `audioDeviceSyncEnabled`.
- Which app answers the buttons (Teams' HID2 control between its apps): the one that started first takes them; another
  that finds them held while a headset is connected asks "Transfer audio device buttons to this app?" ("Buttons on your
  connected audio device, such as mute, answer, and hang up, will control this Teams app. Other Teams apps will no
  longer respond to these buttons.", Cancel / Transfer controls). OST does the same between OST instances (profiles),
  with `$XDG_RUNTIME_DIR/ost-hid-control` naming the instance that has them.
- What the buttons do is in docs/spec/call-and-meeting-window.md "Headset call controls".

## Devices ▸ Connected devices (measured 2026-11-15)

- The last card on Devices (204.9 tall, a laptop icon): "Manage your connected devices" with
  **Manage devices**, and "Automatically activate meeting room mode when in a meeting" (on by
  default) with "Optimizes meeting setup for connected audio/video devices and room displays.
  Attendees see only meeting content on the room display. Learn More"
  (https://aka.ms/meetingroommode). Teams keeps the switch on the device (clientPreferences
  `byod.pushToRoomAudio`); OST keeps it as the local setting `pushToRoomAudio`.
- **Manage devices** opens "Devices › Manage devices": "Select a device to connect", then the
  Teams phones paired with this PC (Teams' Better Together, TASK-0162): each with Teams'
  screen-and-phone glyph, the phone's name, "Connected" while it is, and **Disconnect**.
  - Layout (Teams' BttDeviceSettings Griffel classes, rem = 10 px; read from its CSS, as no
    phone could be paired with Teams on winpc to measure): the list 15 under the text
    and 15 apart (Flex gap.medium); each phone a hoverable column padded 10 (hover
    colorNeutralBackground2Hover), 10 apart inside (gap.small): glyph (Fluent
    video_person_call_20), name 16 semibold (55rem wide), "Connected" 14, then the button.
  - Transport (Teams' SlimCore "BTT", registrar listing read 2026-11-21): Teams desktop's
    calling registration (NextGenCalling, `DesktopNgc_2.5:SkypeNgc`) carries a second Trouter
    transport, context `BetterTogether`, path `https://<socket>-t.trouter.teams.microsoft.com
    :443/…/bettertogether/send` (the socket's user-token front: the `-f` host at 3443 turns a
    Skype token away with 401). The calling registration id is the endpoint id; the user's
    endpoints are found by listing the registrar (`{bindings: […]}`). A command is
    one JSON message POSTed to the other side's URL: `{registrationId, command,
    commandSequenceNumber, commandDetails (JSON text), transportDetails {context, endpointType
    "BetterTogether", url}, debugContent {chainId, causeId}}`. The receiver acknowledges it in
    the Trouter reply (200 `{}`, or 300 `{errorCode}`, e.g. DEVICE_NOT_PAIRED from a phone that
    isn't paired) and later sends a `response` command `{requestCauseId, statusCode, salt, …}`.
  - Proximity: the phone advertises Microsoft's Bluetooth manufacturer data `34 F0 40`, the
    user's packed object id, a byte, its salt (bytes 17-18, little-endian) and its endpoint
    signature (19-20). The PC scans 15 s for it (-75 dBm or better), unless a command carries
    the salt last heard or the phone is wired (`WIRED_CONNECTION`).
  - `broadcast` is answered with the PC's OS name; `pair {deviceName, clientType,
    clientVersion, endpointSignature, capabilities, salt}` asks the user ("Connection request": "<name> would like to pair with your PC. Click on \"Connect\" to approve.", Connect / Cancel, 50 s)
    and on Pair keeps the phone Connected and answers `{accepted: true, salt}`. A connected
    phone gets `keepalive` every 30 s; two misses send `lock` (Locked); hearing it again sends
    `keepalive` and `unlock` (Connected). `locked`, `unlocked`, `autopair`, `updateendpoint`
    and `unpair` from the phone are taken as Teams takes them.
  - Disconnect (Teams' betterTogetherUnpairDevice) sends the phone `unpair` (`{salt,
    targetEndpointId, companionResponseRequired: false}`) and forgets it at once. The list is
    kept on the device as Teams keeps it (`BTPairedDevices`, without the connection status:
    every phone starts disconnected).
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

## Teams 26304 changes (measured on winpc 2026-11-20)

Teams changed these pages since the 2026-11-10/14 captures (ost-test1 now also has Teams Phone
and a Copilot licence, and is in Targeted release):

- **General ▸ Opening content in Teams windows** (`window-mode-section`, card 331.7 tall): it
  absorbed the old "Starting chats" card. Under the subtitle ("Choose to open the following
  content in either the main window or a new window. This will only apply to this account.") the
  two pictures (`evergreen-assets/settings/new-chat/new-chat-{mainwindow,popout}-{default,dark,
  contrast,classic}.svg`, 148 x 88, 24.6 under the header, their labels 4 under them), then a
  table 24.7 lower: "Content" (14/700) with "Main window" and "New window" columns (108 wide from
  346.5 in), a 29 tall header and 32 tall rows, each row a radio pair centred in the columns:
  - "Notifications and links to chats, channels, and messages": the client preference
    windowing.shouldOpenContentInNewWindow (device).
  - "New chats": the synced messagingSettings.alwaysPopOutNewChat.
- **General ▸ Language and regional formats**: the subtitle is now "Please restart Teams to apply
  language settings. Date and time format settings are applied automatically."
  (`restart_teams_to_apply_language_and_regional_settings_autoapplied`, when the host applies OS
  regional changes live). Save and restart still restarts.
- **Chats and channels ▸ Chats and channels list**: "Show private chats in meetings" after Show
  time stamps (simpleCollabUserSettings.hasUserEnabledNewPrivateChatInMeetingChat, on unless
  off): with it off a meeting chat shows only Everyone, no private chat tabs.
- **Chats and channels ▸ Compose** (199.3 tall, after Automatically follow threads): Enter to send
  moved here from its own card: "When writing a message, press Enter to" (14/20) and "This
  setting doesn't apply when message formatting is active." (12/16) under the header, the radios
  10 under that.
- **Chats ▸ Copilot** (the list card's switch): shown to licensed users
  (isUserLicensedToM365CopilotBusinessChat) with ECS messaging.enableMetaOSCopilotToggleInSettings
  and the Microsoft 365 Copilot app (`b5abf2ae-…`) installed; userPersonalSettings.
  messagingSettings.shouldShowMetaOSCopilotApp (default true).
- **Notifications and activity**: "Posts in all shown channels" / "Include replies" are gone.
  New: **Reminders** (key `Reminder`, Show in Activity and banner by default; after Likes and
  reactions) and the **Channel Notifications** card (93.3 tall: "Choose where to see notifications
  for each channel, or turn them off. By default, all new channel notifications are set to
  '@Mentions & replies' unless changed individually." with Manage). Manage opens
  "Notifications and activity › Manage": the Channel Notifications card (padding 15.7, icon at
  24.7), then one card with "Team" (14/600 #424242) and every team as an expander (44 tall:
  chevron, the 20 px picture, the name 14/600) with its channels 47.3 apart: the name, a 294 x
  31.3 dropdown (All new messages / @mentions and replies / Mute, each with Teams' hint) at 367.3
  and Customize (the channel notification dialog).
- **Notifications ▸ Apps** (section): an expander per app with Graph activity notifications
  (Meeting Recaps; Q&A): the app's 18 px icon, its name, an On/Off switch (appNotificationEnabled)
  and a chevron ("Notification panel") that opens one dropdown per activity type of the app's
  manifest ("When meeting recap is ready for meetings I follow", …; Q&A: Replies to your posts,
  Organizer replies to your post, Reactions to your posts, New question posted, Post approved, New
  post pending approval, Teams Q&A enabled, New discussion posted, New private reply, Organizer
  private reply, New anonymous reply, New post, Other activities). Kept in userGraphSettings per
  app. (Not built in OST yet.)
- **Privacy ▸ Delete Copilot activity history** (93.3 tall, after Blocked contacts; ECS
  messaging.enableCopilotDeleteHistorySetting and the Copilot licence check for ChatInfoPane):
  "You can delete your history in your Microsoft account." with the link "Learn how to delete
  Copilot activity history" (copilotDeleteHistorySettingLearnMoreUrl,
  https://go.microsoft.com/fwlink/p/?linkid=2250168) inline (12/16, wrapping at 433.4), and the
  button "Open Copilot activity history" with an open glyph (233.3 x 31.3;
  copilotDeleteHistorySettingDeleteHistoryUrl,
  https://myaccount.microsoft.com/settingsandprivacy/privacy).
- **Calls** (Teams Phone): an "Intelligent call delegation" card (Set up → a sub-page with an
  Off switch and "Inactive"), Call handling and forwarding with "Forward all my calls", "When you
  receive a call" (Do not ring anyone else / Also ring a new number or contact / call group /
  delegates, by the calling policy's isCallGroupsAllowed, isDelegationAllowed,
  isForwardingToUserAllowed, isForwardingToPhoneAllowed), "When you can't answer a call" with
  "Redirect to a new number or contact", ringtones for you / forwarded (CallGroup) / delegated
  (Delegate) calls, "Viewing incoming calls" (user preference callViewMode immersive | minimized:
  Large window / Small window, pictures `evergreen-assets/settings/calling/{immersive,minimized}-
  view-{theme}.svg`), and the Call group (Add a call group → "Calls › Call group": "Add a call
  group member", Type a name or number) and Delegates (Add a delegate → "Calls › Manage
  delegates") cards. (Built: see "Calls ▸ Call group, Delegates, …" below.)
- **About ▸ Version**: a ring line "**Early Access** through Targeted release ↗" (the host's ring
  ring3_6 assigned = Targeted release; links from ECS core.aboutRingInfoLinks), and an **Early
  access** card with "Public preview" (the desktop host's setNextLaunchIsPublicPreview, offered when
  the update policy allows public preview). (Built.)


## Calls ▸ Call group, Delegates, Intelligent call delegation, Viewing incoming calls (measured on winpc 2026-11-21)

Teams 26304, ost-test1 (Teams Phone). Page order: **Intelligent call delegation** (first card,
where ECS calling.enablePersonalAttendant and teamsPersonalAttendantPolicy.personalAttendant is
`EnabledUserOverride` or `Enabled`), **Call handling and forwarding** (ending with the three
ringtones and Viewing incoming calls), **Voicemail**, **Out-of-office voicemail** (the heading
lost its "Manage"), **Call group**, **Delegates**.

- **Intelligent call delegation card** (77.3 tall): the 32 px avatar
  (`evergreen-assets/personal-attendant/personal_attendant_avatar.svg`) at 12.7, "Intelligent call
  delegation" and "An AI-powered tool that answers, routes, and filters calls on your behalf.",
  button "Set up" (off) / "Manage" (on) → "Calls › Intelligent call delegation":
  - The switch card (129.3 tall where the policy is EnabledUserOverride): a 10 px status dot (on
    #0E700E; off hollow, 0.67 #707070) at the body's left, "Active" / "Inactive" 22 after it, the
    switch at the end.
  - On: four collapsible cards (a 32 x 31.3 chevron button at the end): **Call handling**
    (call-inbound icon; "Control how your calls are managed. Any call you don’t answer will be
    handled on your behalf."; "Choose how external calls are handled" where inboundFederatedCalls
    and inboundPSTNCalls are EnabledUserOverride, "Choose how internal calls are handled" where
    inboundInternalCalls is: Automatically answer calls / Let calls ring me first; "VIPs" with
    "Calls from these people go straight to you…" and Edit → Privacy ▸ Manage priority access),
    **Personalization** (Voice and greeting, Custom instructions, "Test voice quality and
    interaction behavior" Make a test call), **Skills** (Follow-ups where calendarBookings allows;
    "Prevent suspected spam calls from disturbing you" = enableCallScreening, on unless false,
    where callScreening allows; "Save transcriptions and recordings for all screened calls" =
    enableAutomaticRecording + enableAutomaticTranscription where both allow), **Notifications**
    ("Display banner for answered calls" = enableScreeningNotification).
  - Saved with `PUT {mt}/beta/usersettings/personalAttendantSettings`, the whole object
    (bookingCalendarId, bookingCode, bookingServiceId, calleeName, defaultLanguage, defaultTone,
    defaultVoice, enable* flags, id "personalAttendantSettingsId", isEnabled). Read from the voice
    admin settings' personalAttendantSettings.
  - The first turn-on where Bookings is allowed (ECS enableBookingsByDefaultForPA, on) sets
    enableBookingCalendar and makes the personal Bookings service: `POST {mt}/beta/personalbookings/
    bookingsService?email=<upn>&settingsSync=false&provisionMailbox=true` {title "Personal Attendant
    Followup", PT30M, maximumAdvance P60D, minimumLeadTime PT1H, timeSlotInterval PT15M, private,
    online, …} → bookingUrlDetails {serviceId, bookingCode}, then PUTs the settings again with them.
  - With it on, Call handling and forwarding shows, in place of the forwarding choices, the 28.8 px
    avatar and "Intelligent call delegation answers incoming (external) calls on your behalf.
    Settings below apply only when calls are routed to you." (card 603 tall).
- **Viewing incoming calls** (in the forwarding card, 31.7 under the last ringtone): the title,
  Teams' 12/16 subtitle ("…only the large window will show when you or someone else enables RTT
  or captions."), then two picture radios 12 below (168 x 133, 181.4 apart): Large window /
  Small window = user property callViewMode `immersive` (default) | `minimized`. Teams reads it
  when you accept a 1:1 or group call (ECS enableMinimizedViewForCalls) and opens the call that way.
- **Call group card** (77.3 tall, people-team icon): "Call group members can receive calls on
  your behalf." with "Add a call group", or "Manage" plus "Ring everyone at once:" / "Ring in the
  order below:" (14/20, 26 tall) and the members' 32 px pictures (151.3 tall with one).
  "Calls › Call group": the card's subtitle "Call group members can receive calls on your behalf.
  Select members to be in your call group and then forward to them whenever you need to.", "Add a
  call group member" with the people picker (294 x 33.3, #F0F0F0, radius 4) at the right; with
  members, "Group members" and "Ring:" (12, #C7C7C7 while disabled) Everyone at once / In the order
  below (12/600; disabled outside 2–5 members, tooltip "Pick the ring order for your call group
  members to receive your calls"), and a row per member: 668 x 48, #F0F0F0, radius 4, padding 8 7
  8 12, picture 32 with presence, the name 14/20 at 52, Delete (32 x 31.3) at the end. At most 25
  ("Maximum number of call group members reached"). Saved at once: `POST …/callredirectionsettings`
  with callGroupDetails.targets (and callOrder, falling back to simultaneous outside 2–5).
- **Delegates card** (109.3 tall): "Delegates can make and receive calls on your behalf. They'll
  be notified when you change call settings to send your calls to them." with "Add a delegate" /
  "Manage" and the delegates' pictures. "Calls › Manage delegates": the card "Add a delegate" with
  "Delegates can receive and make calls on your behalf. Once you add a delegate, select them to
  choose what they can do.", the picker row; "Your delegates" (14/20); each delegate an expander:
  header 668 x 48 #F0F0F0 (chevron at 12, picture 32 at 36, name, Delete), panel #FAFAFA with five
  checkboxes 33 apart (Make calls, Receive calls, Change call and delegate settings, Pick up held
  calls on; Join active calls off), then "Announce when delegates join the call" / "You will only
  be notified when delegates join an active call." with its switch.
  - `POST {mt}/beta/usersettings/{mri}/delegate` {userMri, isActive true, allowedActions,
    createdDate}; `PATCH …/delegate/{delegateMri}` {isActive, allowedActions}; `DELETE
    …/delegate/{delegateMri}`; `PATCH …/delegationWarningTone` {playWarningTone}. Read from the
    voice admin settings' delegationSettings (userDelegates.delegates, userDelegators.delegators).

## Calls ▸ Intelligent call delegation ▸ Personalization, Follow-ups, test call (TASK-0242; measured on winpc 2026-11-21)

With the feature on, the page's cards are Call handling (CallInbound), **Personalization**
(Wand), **Skills** (TaskListLtr) and **Notifications** (AlertBadge); rows inside a card are 15
above and below a divider.

- **Personalization** (270 tall): "Voice and greeting" / "Choose the voice, tone, and greeting
  style that represents you during your calls." Manage → `personal_attendant_custom_greeting_title`;
  "Custom instructions" / its two-line subtitle, Manage → `personal_attendant_custom_instructions_
  title`; "Test voice quality and interaction behavior" with "Make a test call" (VideoPersonCall,
  149.7 wide) where ECS calling.enableTestCallToPA.
- **Skills ▸ Follow-ups** (where calendarBookings allows): its subtitle, Manage →
  `personal_attendant_booking_manage_hours`.
- **Voice and greeting** ("Calls › Intelligent call delegation › Voice and greeting"; one card,
  PersonVoice icon, 252 tall): "Choose the default language" with a 292.7 × 30 dropdown (ECS
  personalAttendantSupportedLanguages, 28 for ost-test1 from Arabic (Saudi Arabia) to Turkish
  (Türkiye); "en"/"fr" read as en-US/fr-FR; saved as defaultLanguage), "Customize greeting
  message" / "Write the exact message you want intelligent call delegation to use when answering
  calls." with "Write a greeting message" (or "Edit greeting message"), then the test call row.
  The greeting dialog: 700 × 264.7, radius 8, padding 24, title 20/28/600, the area 650.7 × 120
  (0.67 border, brand bottom when focused) with the placeholder "Type your greeting message here:
  • E.g.: "Hi, you've reached {first name}. …"" (no name: "Hi you've reached [owner's name]'s
  line. …"), Cancel / Save (96 × 31.3); Save only when the trimmed text changed and is at most 200
  characters ("Greeting cannot exceed 200 characters").
- **Custom instructions** (TaskListLtr, 528.7 tall): "Write your custom instructions or select a
  prompt", a plain-text box 676.7 × 220 (0.67 #D1D1D1, radius 4, padding 8 12), the prompt box
  (padding 8 12; transparent border until a category is picked): circular pills Conversation,
  Scheduling, Protection (+ Call handling with ECS enablePACallRoutingInstructions), 31.3 tall,
  ≥ 96 wide, 8 apart; the picked one brand-filled with its suggestions under it (radius 8, padding
  4 12, the [placeholders] 600 in brand); a suggestion appends its line. Under it the AI notice
  (Sparkle 12, 12/16/600 brand on #E8EBFA, radius 4) with thumbs up/down (Teams' feedback,
  PERSONAL_ATTENDANT_CALLEE_FEEDBACK / PACustomInstructions), then right-aligned "{n}/{max}
  characters" (max ECS personalAttendantConfiguration.customInstructions.maxLength, else 10000;
  over it "Length limit exceeded. …" in red), Make a test call and Save (primary, only when
  changed). "@" offers "Add call transfer target" / "Share contact" and a people search ("Search
  for a person"); people are stored as `<route|contact name="…" mri="…" tenantId="…">`.
- **Where they're saved**: the greeting and the instructions live in personalAttendantSettings.
  calleeName = Base64(UTF-8 JSON {customGreeting, customInstructions, useCustomInstructions, …},
  empty values dropped), PUT with the whole settings as the rest of the page.
- **Follow-ups** (CalendarEdit, 560.3 tall): "Enable scheduling follow-ups" (enableBookingCalendar
  in the attendant settings), then 110 apart between dividers: "How long should follow-up events
  be" (15 / 30 / 45 mins / 1 hr = PT15M…PT1H), "How soon can follow-ups be scheduled" (1 / 8 / 12
  hrs / 1 / 2 days = PT1H…PT48H), "How far in advance can follow-ups be scheduled" (7 / 14 / 30 / 60
  / 90 days = P7D…P90D), "Define available hours" (Use work hours / Use custom hours: per day the
  English day name, Available / Unavailable with a switch, up to five slots of 15-minute steps,
  start "to" end, + on the first, delete on the others; 9:00–17:00 on weekdays to start). Read with
  `GET {mt}/beta/personalbookings/bookingsService?email=&bookingServiceId=&bookingCode=&settingsSync=false&provisionMailbox=false`
  and saved at once with `PUT …?email=&bookingServiceId=&bookingCode=` {minimumLeadTime,
  maximumAdvance, defaultDuration, hasCustomServiceWindows, bookingServiceWindows [{bookableHours:
  [{day, timeSlots [{start, end}]}]}]} (minutes from midnight).
- **Custom instructions' people** (measured 2026-11-22): each is Teams' pill, an uneditable inline
  span: 23.33 tall, margin 0 2, padding 1 8 1 4, a 0.67 NeutralStroke2 (#E0E0E0) border, radius 4,
  NeutralBackground3 (#F5F5F5), 2 between a 16 px icon and the name (12/20 #242424), vertical-align
  middle. A call transfer target (`<route …>`) has the Call icon in colorBrandForeground1 (#5B5FC7), a
  shared contact (`<contact …>`) the ContactCard icon in colorPalettePurpleForeground2 (#341A51). "@"
  at a word's start opens a 220-wide menu at the "@" (padding 4 0, 28-tall rows, 16 px icons, text at
  36): Add call transfer target (Call) / Share contact (ContactCard), then a 320-wide people search
  (padding 8, the box #F0F0F0); the person's pill replaces the "@", a space after it. OST keeps each
  pill as one object character in the plain-text box (richtext.cpp's chips), the room it takes in the
  line its size, and draws the pill over it.
- **Custom hours** (measured 2026-11-22): each day 15 below the last (the dropdown's bottom for
  Monday): its English name at the left, Available / Unavailable 16 before its switch, the switch 8 in
  from the right; its slots 8 under that row and 8 apart, right-aligned: start and end as 120 × 32
  filled-darker selects (#F5F5F5, no border, the time 14 px 12 in, chevron 20 10 from the right),
  "to" between them 8 apart, then + on the first slot while there are fewer than five, else a trash
  button (24 × 23.3, a 20 px #424242 icon, brand on hover); an unavailable day has no slots.
- **Make a test call**: Teams' TestCallToPA intent: a 1:1 call to your own MRI with no chat thread,
  audio only, which SlimCore places as `callToPersonalAttendant` (botType personalAttendant); the
  attendant (GraphCommunicationsClient-PersonalAttendantBot) answers with your greeting. The window
  is titled "Test call with your Call Delegation" and shows only Mic (with its options), More and
  Leave (measured). OST sends the callee as `{id: <your MRI>, endpointType: "personalAttendant"}`.

## More than one account (TASK-0078; measured on winpc 2026-11-22 with OST Test 2 added to ost-test1)

- **Add another account** (the profile flyout's footer) opens Teams' "Add another account" dialog
  (440 × 540, radius 6: the device's Windows accounts, then "Create or use another account"),
  which opens Microsoft's sign-in ("Sign in to Microsoft Teams") and, after the password, "Sign in
  to all apps and websites on this device?" (No, this app only / Yes). The window then switches to
  the new account.
- **Title bar**: the profile button becomes a 140 × 28 pill: the organisation's name (12/16
  #424242 at 6.7, cut at 107.9) and the 28 px picture at its end; its name reads "Your profile,
  status {status} for {address} in {organisation}".
- **Profile flyout** (320 wide): the signed-in account's menu on white, then, on #F5F5F5, an 80.3
  tall row per other account: the 48 px picture at 16 (presence 12 at 36, 36), the name 14/20/600
  at 76, 8 and the address 12/16 under it ("Switch to account {address},  Status {status}"); then
  the footer "Add another account" (65 tall, #F0F0F0, the 32 px #E6E6E6 slot at 26 with the 16 px
  person-add glyph, the text 14/600 at 76).
- **App bar**: "Activity in other accounts and orgs" at the bottom (52 × 48, a 24 px glyph #616161,
  a red #D13438 count badge of the other accounts' activity).
- **Settings ▸ Accounts and orgs**: one card per account in the order they were added (788 × 121,
  28 apart): the signed-in account's card has Refresh license and restart and its organisation in
  bold; another account's card has Manage only and its organisation in regular weight.
- **Sign out** (the flyout's): "Sign out of Teams" ("We'll sign you out and remove any offline
  data, including message drafts. Learn more" and the multiple-accounts tip) with Add another
  account / Cancel / Sign out; afterwards the window is the remaining account's again.
- **OST**: each account is its own profile (its own sign-in, window, keyring entry); the device's
  accounts (with their organisation) are kept in accounts.json, one entry per account (a second
  profile of the same account isn't listed). Add another account starts OST for a new profile at
  Microsoft's sign-in page; Switch to account brings that account's window forward. Not built: the
  app bar's "Activity in other accounts and orgs" hub: below.
- **Activity in other accounts and orgs** (Teams' MTMA hub v2, measured 2026-11-22 with OST Test 2
  as the second account): the app bar tile (52 × 48 at 8 from the bar's left, its bottom on the bar's,
  radius 8; PersonAlert 24 #616161, filled brand on white while hovered or open; the other accounts'
  count in #D13438, 10/14 600, at 26, 0) opens a 380-wide flyout 2 beside the bar, its bottom on the
  tile's, at most ~0.7 of the window tall (shadow 0 0 2 / 0 8 16, radius 4):
  - the title "Activity in other accounts and orgs" (14/600, 16 in, 24 tall), a 0.67 #E0E0E0 rule at
    56.7; at 73.3 the pills Unread, Channels, Chats (24 tall, 12 px, padding 3 8, a #D1D1D1 hairline,
    8 apart; picked: #4F52B2 with white text) and Filter (24 × 23.3 at 339.3, filter glyph);
  - from 113.3 the accounts, each an accordion: a 320.7 × 48 header 12.7 in (chevron 14 at 4, the
    32 px picture at 22 with the account's count 4 above its corner, the name 14/600 and address
    12/20 #616161 at 66) and Account settings ··· (24 × 23.3 at 333.3, 16.8 down) — a 240-wide menu
    of the account's organisations (48 tall: a 20 px square initial, the name, a chevron) whose
    submenu has Switch (ArrowRight) and Pin this org;
  - its entries (352.7 wide, 12.7 in, padding 8; a 6 px dot column, the 32 px picture at 22, the
    text at 62, the time 12/16 #616161 at the right, 8 from the text): unread activity (title bold,
    two lines; the place 12/16 #616161; a 4 px dot; a white 18 px disc at the picture's corner with
    the kind's 16 px brand icon; a missed call has Call and Chat, 65 × 24, 14/600, a #D1D1D1
    hairline) and recent chats (a meeting's calendar on a #C5CBFA disc; the last message 12/16
    #424242, "You: …", up to two lines; bold and a dot while unread), newest first; the time within
    the last day, else the date; hover #F5F5F5;
  - a footer "Scroll to see more" (12/20 #4F52B2 and an arrow, padding 8 16) under a #E0E0E0 rule
    while more is below;
  - Filter by (240 wide at the flyout's right edge, under the button): "Filter by" 14/600 (52 tall),
    then 40 px rows (text at 40): Mentions, Tag mentions, Followed threads, Orgs ›.
  - Picking an entry switches to that account at it.
  - **Pin this org** (the org's submenu, pin glyph; at two pinned orgs it is
    disabled: "Maximum tenants are pinned. Unpin one to add another."; measured
    2026-11-22): the org leaves the hub (its count with it; nothing left:
    "We couldn't find any results." under the search illustration) and gets
    its own app bar tile above the hub's: 52 × 48 at 8, radius 8 (white while
    open), the org's colourful square initial (28, radius 4) at 12, 10, its
    count at 30, 4, the org's name as tooltip ("Current org" for the account's
    own). The tile opens the hub's flyout for that org alone (379 wide, beside
    the bar, its bottom on the hub's): a 72.67 tall header (padding 16; the
    32 px square initial with its count at 20, 0; the name 14/600 and the
    address 12/20 #616161 at 60; Tenant settings ··· 24 × 23.33 at 338.67,
    24.33), a #D1D1D1 rule, the pills 16 under it, the entries from 128.67.
    Tenant settings: Switch and Unpin this org (pin-off glyph), 240 wide at
    the flyout's right edge.
  - **OST**: the pinned orgs (accounts' addresses, in pin order, at most two)
    are kept for the device in `hub-pins.json`.
- **OST**: each account's window publishes its own summary (its app-bar count, its unread activity
  and recent chats) to `hub.json` in its profile folder; the other accounts' windows read them every
  few seconds for the tile and the flyout. Picking an entry asks that account's running window (its
  instance socket, `open\t<thread>\t<name>`) to come forward and open it; when it isn't running,
  the account starts. An account's summary is as fresh as its window (Teams runs every account's
  data in its one app; OST runs each account as its own profile).

## Links into Settings (TASK-0088 AC3; Teams 26304, bundles read and measured on winpc 2026-11-21)

Every link goes through `entityCommanding.settings.launch(command, id)` or
`launchSection(id, command, {settingCategory, settingId, settingSectionId, focusId})`
(or an entity command `{type: settingsstore, action: view, id}`), always in the main window.
The settings app resolves it (settings-app `Ar`, sub-page map `LV`):

- **No id** → General. `launch(command, General)` (Settings and more ▸ Settings, and Ctrl+,
  from anywhere, also after another page was open) opens General with focus in "Find in
  settings" (measured).
- **A category and a setting id** → that page; 50 ms later the element `#focusId || #settingId`
  is scrolled into view (`scrollIntoView({behavior: "smooth", block: "center"})`), its first
  focusable control focused, and the section (`#settingSectionId`, else the setting) gets the
  arrival highlight: `box-shadow: inset 0 0 0 0.1rem colorPaletteDarkOrangeBorderActive`
  (#DA3B01; dark #E9835E) fading to transparent over 4 s (ease-out; ECS
  junoSearchConfigs.junoSearchAnimationDuration/Delay, defaults 4000/50 ms). The root font is
  10 px, so the edge is 1 px (measured: `rgba(218, 59, 1, 0.898) 0 0 0 1px inset` 0.25 s in,
  0.565 0.8 s in, gone at 4 s). A setting id whose element isn't shown changes nothing.
- **A sub-page id** → "Page › Sub-page": general_settings_oof_settings_page_title,
  general_settings_editor_sdk_manage_spellcheck_languages_page_title, follow_presence_settings,
  shown_channels_centralized_settings, privacy_manage_priority_access, privacy_manage_blocked_users,
  privacy_manage_vip_contacts, privacy_diagnostic_data_viewer, privacy_device_home_building_settings,
  appearance_settings_manage_interpreters, better_together_devices_dialog_title,
  call_group_section_subpage_title, delegation_section_subpage_title,
  personal_attendant_group_section_title and its personal_attendant_custom_greeting_title /
  personal_attendant_custom_instructions_title / personal_attendant_booking_manage_hours.
- **Any other id** is a page (general, appearance, chats_and_channels, notifications, accounts,
  privacy, accessibility, devices, calls, files_and_links, app_permissions, recognition, about, …).
- Without a setting id the page opens at its top and, 100 ms later, its first control takes
  focus unless something outside Settings still has it (measured: Privacy's first switch).
- Notifications scrolls "Replies to followed threads and posts" to the top when the setting id
  is replies-to-threads-and-posts-settings, even with no category (no highlight).

The links Teams has, and where they go:

| Where | Opens |
|---|---|
| Settings and more ▸ Settings; Ctrl+,; `/settings` slash command | General, Find focused |
| DND / pause banner ▸ Change settings | Privacy › Manage priority access |
| Profile flyout ▸ Pause notifications ▸ Notifications settings | Notifications at web-activity-settings (not shown for ost-test1: the page at its top, focus unchanged; measured) |
| Profile flyout presence ▸ status settings | the same |
| Title bar menu ▸ Pause notifications ▸ Notifications settings | Notifications |
| Profile flyout ▸ Schedule out of office | General › Out of office |
| Profile flyout ▸ Manage org; guest invitation banner; external team invitation | Accounts and orgs |
| App bar ▸ Customize app bar | Appearance at app-bar-settings (highlight; Show app names focused; measured) |
| Compose box's Enter / Shift+Enter hint | Chats and channels with setting id configure-enter-to-send-setting but no category: the page at its top, first control focused (measured) |
| Chat list ··· ▸ Customize view | Chats and channels |
| Channel / chat notification dialog ▸ "notifications settings for all …" | Notifications |
| Channel follow settings; Chats ▸ Automatically follow threads link | Notifications at Replies to followed threads and posts |
| Activity slices / headline "follow settings" | Chats and channels at auto-follow-threads-settings |
| Activity ▸ Notification settings (recommendation dialog) | Notifications |
| Editor card ▸ Editor settings… / Manage languages… | General at editor-spellcheck-section / General › Manage spellcheck languages |
| A message's translation menu ▸ settings | General at translation-settings |
| Title bar menu efficiency row | General at optimized-perf-section |
| Intelligent call delegation ▸ VIPs Edit | Privacy › Manage priority access |
| Calls app / call settings header | Calls (and the delegator / call queue / alternate line pages) |
| App card footer ▸ permissions | Privacy |
| Leave chat and block toast | Privacy |
| Work location banners and toasts; device home banner | Privacy; Privacy › Stationary device location |
| Windows Focus Assist banner | Notifications |
| NDI banner | App permissions |
| People app | People settings; Privacy › searchability |
| `teams.microsoft.com/l/settings/<page>[/manage-vip-contacts]` | that page (General when unknown) |

OST: SettingsView.launchSection(id, options) resolves ids the same way and draws the highlight;
Main.launchSettings / launchSettingsGeneral open them in the main window. Wired: Settings and more
▸ Settings, Ctrl+,, the DND banner, Pause notifications ▸ Notifications settings, Schedule out of
office, Customize app bar, the compose hint, Customize view, both notification dialogs' links, the
auto-follow link, the Editor card's links, VIPs Edit, the app card footer, notification banners'
settings, settings deep links in messages. Not in OST (so no link): the message translation menu,
the efficiency row (VDI only), Teams Premium/Insider/Labs pages, People settings, contacts sync,
leave-and-block, NDI, Focus Assist (Windows), Calls app call-queue pages.

## About ▸ ring line (TASK-0088)

Teams' host asks ECS with the user's id and tenant; Segmentation.TeamsRing ("ring3_6" for a
Targeted release user) becomes its ring (ecs_request_param.json on winpc). The About page shows
"**Early Access** through" and the link when ring.id is ring3_6 (core.disableAboutRingInfo off):
"Targeted release" (the ring is the user's own, isAssignedRing) → core.aboutRingInfoLinks.
targetedReleaseLink (default https://go.microsoft.com/fwlink/?linkid=2254754); "Ring 3.6" with
enableReleaseDashboardButton.
## Copilot surfaces (TASK-0165, Teams 26304)

- **Search box**: with the licence (`userLicenseDetails.isCopilot`) and ECS
  autosuggest.enableSerpCatalystEntrySuggestion, the placeholder is "Search or ask Copilot
  (Ctrl+E)" and, focused, "Look for people, messages, files and more or ask Copilot". A query of
  more than one word (no scope, filter, command or KQL) gets "Ask Copilot about <b>query</b>" first
  among the top hits (50 tall, a 32 px #F0F0F0 circle at 16 with Copilot's 16 px glyph #424242, the
  text 14/20 at 58). Choosing it opens the search results with the Microsoft 365 Copilot app in the
  right pane (the preview's 40 %; a 60.7 tall header with Copilot's colour mark at 26.7 and
  "Copilot" at 50), launched with scope "Search", entry point "SearchAutosuggestAskCopilot", ECS
  Copilot.copilotEntryPointsCMMIds.searchAutosuggestAskCopilot (cmmi7lmhneb), copilotReferenceId =
  SHA-256 of the search session id (the frame's address is `chat/sessionanchor/<that>`); once up the
  host posts contextualChatChanged {contentType "teams", contentItems [{contextType "Search"}]} and
  updatePromptInputData with the SearchPrompt (the query and Teams' CopilotSearch annotation:
  searchType AllTab, entityTypes [All], appName Teams).
- **Chat list**: Copilot at the top (`list-item-metaos-copilot`) when ECS
  chatList.enableBizChatMetaOSChatListEntryPoint (simple collab: simpleCollab.
  enableBizChatMetaOSSimpleCollabEntryPoint), the Copilot app installed for you and
  shouldShowMetaOSCopilotApp is not false.
- **App bar**: Copilot is one of your pinned personal apps (b5abf2ae-…), as the service lists them.

## Workplace check-in over Wi-Fi (TASK-0149)

Teams' worker (PlacesManager, wifiAutoLocationHelper, IC3 location service client): with the
work-location policy on (and ECS places.enableAutoDetectPlaceWifi) and your switch on, a Wi-Fi
network change gets the tenant's SSID allow list (`GET {iC3LocationService}/v1/me/ssid-allowlist`,
`{SSIDList}`, cached a day; resource https://ic3.teams.office.com) and, on a listed network,
`PUT …/v1/me/endpoints/{endpointId}/location/network {bssid, [ssid], eventTime, shouldUpdate: true,
canShareLocationDetails: true}`: 200 {placeId, name} checks you in at that building (BSSID
match), 207 "In the office" (SSID match), 404 not found. On another network it checks you out
(`DELETE …/location/wifiNetwork`). Headers: x-ms-client-user-agent Teams-V2-desktop,
x-ms-endpoint-id (the presence endpoint), x-ms-correlation-id, ms-cv. Admins list the SSIDs with
`Set-PlacesSettings -Collection Presence -WorkplaceWifiNetworkSSIDList 'Default:…'` and map BSSIDs
to buildings with `Add-WifiDevices` (MicrosoftPlaces module), 24–48 h to propagate; check-in only
happens within your working hours. OST reads the network from NetworkManager over D-Bus
(desktop/src/work_location.rs).

Details read from Teams 26304's worker (WifiAutoLocationHelper, IC3LocationService):
- The endpoint id is the presence endpoint's (else a new one); the allow-list GET adds
  x-ms-client-os / x-ms-client-os-ver. The reply is `{SSIDList}`; it doesn't depend on those
  headers (checked with linux, windows and mac values: same list).
- Guests and anonymous users are skipped (USER_ROLE_NOT_ALLOWED). There is no client-side
  working-hours check: the service applies your Outlook working hours.
- Switch on: `PUT …/location/network` (above). Switch never set and the first-run banner not
  seen (Ask mode): `GET …/location/wifiNetwork?bssid=…` instead, then Teams' first-run banner
  (not built in OST).
- Checking out on a non-office network only happens with ECS places.adlCheckout, a non-empty
  SSID, and a work location that a check-in set (presence `workLocation.locationSource`
  "VerifiedLocation"); OST follows that. Teams also has a wired-connection checkout tied to a
  device's home building (not built).
- A check-in's work location is `{location: "Office", locationSource: "VerifiedLocation",
  approximateDetails: {id, idType: "Directory", name}}`. Teams' profile flyout then reads
  "In <building>" ("Planned in <building>" for the work plan); OST does the same.
- Live (2026-11-23, test tenant): with the BSSID mapped, the service answered 200 with the
  building on most reports but 404 on about one in three, for the same access point and
  endpoint.

## OST status

- Built: the left pane and header, General (System, opening content, Out of office, keyboard
  shortcuts), Appearance (theme, skin tone), Chats and channels, Privacy (auto DND, block
  anonymous calls, surveys, attendance reports, unmute shortcut), Accessibility (sign
  language mode, captions settings) and Devices.
- Calls: forwarding, unanswered calls, ring delay, the voicemail answer rules (all five; the
  transfer rules with Teams' people picker, TASK-0180) and out-of-office voicemail.
  - Choose a ringtone for you (TASK-0144): Teams' 18 ringtones (assets/sounds, Teams' own
    files), saved with `POST {mt}/beta/usersettings/{mri}/ringtonesettings` and read with
    `POST {mt}/beta/users/useraggregatesettings {"voiceAdminSettings": true}`; incoming calls
    ring with it on the speaker and the secondary ringer.
  - Record a greeting (TASK-0152): Teams' call to your own voicemail.
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
