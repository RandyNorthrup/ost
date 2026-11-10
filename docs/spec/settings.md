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

## OST status

- Built: the left pane and header, General (System, opening content, Out of office, keyboard
  shortcuts), Appearance (theme, skin tone), Chats and channels, Privacy (auto DND, block
  anonymous calls, surveys, attendance reports, unmute shortcut), Accessibility (sign
  language mode, captions settings) and Devices.
- Calls: forwarding, unanswered calls, ring delay, the voicemail answer rule (no transfer
  rules) and out-of-office voicemail.
  - Not built: the ringtone choice (OST synthesises its ring and doesn't ship Microsoft's
    audio; whether to ship Teams' MP3s is the project's call), recorded and text-to-speech
    greetings, the greeting language, and the transfer rules (they need the people picker).
- Still to build: Notifications and activity as Teams', Accounts and orgs, Files and links,
  App permissions, Recognition, and the remaining items on built pages.
- Chat list (measured with the settings on):
  - Previews: chat rows are 52 tall, with a 36 px picture at 16, 8, the name at 64 and the
    preview (12/16 #616161) at 64, 26. It reads "You: …" for yours and "Name: …" in groups.
    Teams' own words for system events and media ("Bot added", "User added", "Sent an
    image", "Recording is ready", …; messaging 390776 `u`) show in italics.
  - Time stamps: 12/16 #616161, 12 from the row's right, on chats and channels alike: the
    time today, else M/d.
  - Filters off: no pills, and the list starts right under the header.
- Saved but not yet acted on by OST: Copilot row, compact density, auto-follow, suggested
  replies, chat landing, sign language mode.
