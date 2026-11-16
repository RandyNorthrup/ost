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
  - Not built: recorded greetings and the transfer rules (they need the people picker).
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
