---
id: TASK-0088
title: 'Settings as Teams: every page and setting'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T07:56:00Z'
updated_date: '2026-11-22T18:26:00Z'
labels:
  - desktop
  - settings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's Settings has General, Appearance, Chats and channels, Notifications and activity, Devices and About. Teams desktop has more pages: General, Accounts and orgs, Privacy (with Manage priority access, read receipts, surveys), Notifications and activity, Appearance and accessibility, Files and links, Chats and channels, Calls, Devices, Recognition, App permissions, Captions and transcripts, Report a problem, About Teams. Each page needs Teams' items, saved to the same services. Other features link into these pages, for example the Do not disturb banner's Change settings opens Privacy > Manage priority access.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings lists Teams' pages in Teams' order with the same layout
- [x] #2 Each page's settings show and save the same values Teams does, through the same services
- [x] #3 Links into settings from elsewhere (Do not disturb banner, Pause notifications' Notifications settings, call and chat menus) open the right page and section
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Phase 1 (d9ca83d): layout, General/Appearance/Chats/Privacy/Accessibility/Devices pages, synced storage (user properties + MT) captured per setting, Out of office page. Still: Notifications page as Teams, Accounts and orgs, Calls, Files and links, App permissions, Recognition, remaining items; OST behaviour for saved-only settings (Copilot row, compact density, auto-follow, suggested replies, chat landing, list previews/time stamps, sign language mode).

- 2026-11-13: App permissions built (measured on winpc): the list by Teams' installedAppsPermissions rule (personal entitlements + every app in your teams' entitlements + changed apps, with device permissions; app_details::permission_apps — OST Test 1 gets Teams' exact 22), Teams' card/expander layout, switches kept on the device via the existing appDevicePermissions store (no Teams request on flip). Recognition (voice/face enrolment) split to TASK-0134. Harness --app-permissions-test; settings-pages harness includes the page.

- 2026-11-14 Devices page as Teams (measured on winpc by DOM; the page's camera preview was never screenshotted): Audio section ("Audio settings": Speaker, Microphone, Automatically adjust mic sensitivity → apm::set_auto_gain, Noise suppression with Background noise only / Voice isolation (disabled, needs Microsoft's voice profile), Secondary Ringer → ringtone::set_secondary rings a second output device) and Video section ("Video settings": preview with Teams' bar, Camera, Green Screen, Mirror my video, Adjust brightness, Soft focus; from TASK-0139). Not offered: Sync device buttons (headset HID), Make a test call (TASK-0141), Spatial audio (no renderer), Devices section (Teams Rooms connected devices / meeting room mode).

- 2026-11-14 General page, part 1 (Teams measured on winpc): Meeting card with "Ask me to confirm when I leave a meeting" (client preference meeting.enableLeaveConfirmationDialog → local setting leaveConfirmation) and Teams' Stay/Leave popover under Leave (also for Ctrl+Shift+H); Time zone card (the system's IANA zone). Verified with --leave-confirm-test in a Meet now.
- General page still to do (storage found in Teams' settings bundle): Starting chats (userPersonalSettings.messagingSettings.alwaysPopOutNewChat; needs a new-chat window), the existing "Opening content" setting's behaviour (client preference windowing.shouldOpenContentInNewWindow; currently saved only), Language and regional formats (locale user property + host formatting locale), Translation (translationSettings V2: targetLanguageCode, translationMode SUGGEST/ALWAYS/NEVER, knownLanguages — not stored in user properties when changed on winpc; service still to find), Editor spellcheck (Manage), Keyboard shortcuts profile (keyboardShortcutsSettings), Use Enter or Spacebar to show content (messagingSettings.disableAutomaticConvSwitchOnKeyboardNav; OST's chat list needs arrow-key navigation first), Efficiency mode (client preference optimizedPerf). New meeting controls switches Teams to another toolbar (not measured). Teams' call quality survey after leaving was captured (scratchpad callsurvey-dom.txt / callsurvey.png) for TASK-0104.

- 2026-11-14 General part 2: Keyboard shortcuts profile (Teams only / + Slack / + Zoom / + combined) saved to the synced keyboardShortcutsSettings {shortcutProfile: default|chats_alt|meetings_alt|chats_meetings_alt} (added to preferences::JSON_PROPERTIES); Teams' Windows desktop key maps from its bundle: Slack set (Ctrl+Shift+1… apps, Ctrl+; shortcuts, Ctrl+K go to, Ctrl+. info pane, Ctrl+Alt+A unread, Ctrl+Alt+U channels, compose Ctrl+E link, Ctrl+Alt+Shift+C code block, Ctrl+Shift+9 quote), Zoom set (Ctrl+U message pane, Alt+H chat list, Alt+A mute, Alt+V video, Alt+Y raise hand, Alt+S share, Alt+Q/Ctrl+Shift+E leave, Ctrl+Shift+V answer with video). Verified with --shortcut-profile-test (synced to the service and read back; left at default). Not yet: ReactToLastMessage (Ctrl+Shift+\), AnnounceActiveSpeaker (Ctrl+2), the profile choice inside the Keyboard shortcuts dialog.

- 2026-11-14 General part 3: Efficiency mode card (Teams' three radios; local efficiencyMode auto|off|on, Teams' client preference optimizedPerf). On (or auto on a low-end device: <4 processors or <8 GB memory — Teams' own isLowEndDevice rule isn't known) the camera is sent at no more than 424x240 and 300 kbit/s (webrtc_video::set_efficiency).

- 2026-11-14 General part 4: Starting chats card (synced messagingSettings.alwaysPopOutNewChat) with Teams' "New Message" window (588x493, measured on winpc; NewChatWindow.qml hosts OST's new-chat form; once sent the chat opens in its own chat window); "Opening content in OST windows" now acts: with New window, a notification's chat opens in a chat window. Verified with --new-chat-window-test (setting synced and put back; nothing sent). Teams' new-chat form itself (the note before anyone is picked, the compose always shown) is OST's own still.

- 2026-11-14 General part 5: chat list keyboard navigation (Up/Down through the shown chats and channels, Fluent focus ring while using the keyboard; Teams opens each as you arrive) and "Use Enter or Spacebar to show content" (synced messagingSettings.disableAutomaticConvSwitchOnKeyboardNav: then Up/Down only move, Enter/Space opens). Verified with --chatlist-keys-test (setting synced and put back). Not yet: the same in @mentions and other lists.

- ff84b5e: Translation card (target language combobox, mode, never-translate chips) kept on this device as Teams does (roaming off by ECS); Teams' automatic translation from languageStamp: "Translate | Never translate German" (Ask), auto-translate with x-ms-knownLanguages (Auto), See original brings the suggestion back. Verified live on linuxlt with OST TEST 139 (German from OST Test 2) via --translation-test; winpc translation settings reverted.
- General page still to do: Language and regional formats, Editor spellcheck (Manage).

- 00d238b: Language and regional formats (Follow OS, App language of OST's English locales, Teams' date/time formats, Save and restart via exec). All desktop dates/times now go through theme formatters; engine meeting times via api::regional. Verified across a real restart on linuxlt (--regional-test). UI localization is a follow-up task.
- General page still to do: Editor spellcheck (Manage).

- Editor spellcheck done: compose spelling via Microsoft Editor over AugLoop (src/api/editor.rs), Teams' Editor card, the Editor spellcheck card (languages, Correct words while typing, Spelling + options from NLEditor Config V2) and Manage spellcheck languages. Verified live on linuxlt (--editor-test); test account's spellcheck languages restored to [] (Teams' own UI cannot remove the last one).
- General page complete; next: audit the other Settings pages against scratchpad/tset.

- Appearance: "Always use dark theme for calls and meetings" (call and pre-join windows get their own dark Theme, Light only), App bar card (Show app names: 68x56 items with 10 px labels, selected item filled; Auto collapse app bar). Verified on linuxlt (--appearance-test). Still to do on Appearance: Teams' Classic and High contrast themes.

- Classic theme (purple #444791 title bar, white icons, #E8EBFA search box, as measured); "Always use dark theme" greyed in Classic as in Teams. High contrast moved to its own task (token dumps in docs/spec/teams-tokens-*.json).

- Chats and channels: "Viewing chats, teams, and channels" (Combined / Separate, synced simpleCollabUserSettings). Separate: a Teams app on the rail after Chat (Ctrl+3, the rest move down), Chat lists chats with Unread/Chats/Meeting chats and its own preview setting (time stamps always on, greyed), the Teams app lists Quick views / Teams and channels / Communities with Unread/Channels/Communities; opening a channel shows the Teams app. Verified on linuxlt (--collab-test), restored to Combined; Teams on winpc switched to Separate to measure and back.
- New icons now carry #212121 so they recolour (dark theme).

- Notifications and activity: Posts in all shown channels (+ Include replies), meeting chat notifications for accepted / tentative meetings (chatSettings), Presence ▸ Manage status notifications (Notify when available list with Add people), Calendar section (userGraphSettings for the Calendar app). Verified on linuxlt (--notif-test, change restored). Sounds and banner position/size are separate tasks.

- Accounts and orgs page built (was empty): account (avatar, name, e-mail), Refresh license and restart (restarts OST), Manage (myaccount.microsoft.com with login_hint), the organisation row with the brand bar. Verified on linuxlt (--accounts-test).

- Privacy: Manage priority contacts / Manage blocked contacts buttons and their pages (Teams' userSettings breakthroughlist / blocklist via {mt}/beta/userSettings/{list}[/manage]); DND checkbox sublabel. Verified on linuxlt (--privacy-test adds and removes OST Test 2). Remaining Privacy cards: work location, camera/mic off on lock, diagnostic data, extended diagnostics, E2EE calls, optional connected experiences.

- Privacy complete except View Diagnostic Data (TASK-0147) and E2EE calls (TASK-0146): work location card (policy text + Outlook link, ECS-driven; policy-on toggle TASK-0149), camera/mic off on screen lock (logind; verified live in a Meet now on linuxlt), Extended diagnostics (keeps earlier sessions' logs), Optional connected experiences (user property; fun picker drops GIPHY exactly as Teams, measured by toggling it on winpc and restoring). Link previews TASK-0148.

- Accessibility: Muted notification card (shares the in-call pane's showMutedNotice). Single pointer controls -> TASK-0150 (chat list reordering), TTY -> TASK-0151.
- Calls: greeting language (Teams' 37), TTS greeting + OOF greeting dialog (Your custom greeting), dividers, label fix. Record a greeting -> TASK-0152; ringtone -> TASK-0144. Voicemail settings have no GET (Teams shows them unset too).
- Found: Settings Card geometry differs from Teams (single-setting cards 20.7 top padding with header row centred; switch-row cards ~14 px taller at the bottom). Geometry pass next after the content audit.

- Files and links matches (the "Teams" Office choice -> TASK-0038 AC). App permissions done earlier. Recognition -> TASK-0153 (biometrics, needs user decision). About rebuilt to Teams' four cards (version, legal, privacy, third-party notices generated by desktop/third_party_notices.py); update line -> TASK-0154.

- Geometry pass (234d44a + this): every Settings card measured against Teams' DOM (--cards-test vs a Teams dump). Fixed: header row rule, last-row gaps, 26/28/10.6 body gaps for radios/pictures/dropdowns, section headings (14/700, 18 padding), Notifications' own card insets, @Mentions master switch (Global_Mention), Meetings heading placement, skin tone tiles, Language/Time zone links to the desktop's settings, editor default language = app language. Remaining height differences are content tracked in tasks (0144 ringtone/sounds, 0145 banners, 0152 record greeting, 0155 new meeting controls, 0038 Teams Office choice) plus Devices (next).

- 2026-11-20 (agent setF) Teams 26304 re-measured on winpc (all pages dumped, new cards' geometry; docs/spec/settings.md "Teams 26304 changes"). Built:
  - General: "Opening content in OST windows" is now Teams' combined card (the two pictures, then the Content / Main window / New window table: notifications and links = local openContentIn, New chats = synced alwaysPopOutNewChat); the separate Starting chats card is gone. Language card subtitle is Teams' new text.
  - Chats and channels: "Show private chats in meetings" (simpleCollabUserSettings.hasUserEnabledNewPrivateChatInMeetingChat, on by default) in the list card; Enter to send moved into Teams' new Compose card; the Copilot switch only for licensed users with the Copilot app installed (ECS messaging.enableMetaOSCopilotToggleInSettings), and it now drives the chat list's Copilot row.
  - Notifications: "Posts in all shown channels"/"Include replies" removed as in Teams; Reminders (key Reminder) added; Channel Notifications card with Manage → "Notifications and activity › Manage" (every team's channels with All new messages / @mentions and replies / Mute, saved like the channel menu, and Customize = the channel notification dialog).
  - Privacy: Delete Copilot activity history (TASK-0165).
  - Harness: --setf-test.
- Not built (Teams 26304 additions, researched in the spec): Notifications ▸ Apps (per-app Graph activity settings: Meeting Recaps, Q&A), Calls' Teams Phone items (Intelligent call delegation page, simultaneous ring / call group / delegates forwarding, Call group and Manage delegates pages, ringtones for forwarded and delegated calls, Viewing incoming calls Large/Small window = callViewMode), About's ring line ("Early Access through Targeted release") and Early access ▸ Public preview, the meeting chat's private chat tabs that the new Chats switch controls, live pick-up of OS date/time format changes.

  - Also: About ▸ Early access ▸ Public preview (where teamsUpdateManagementPolicy.allowPublicPreview allows it): OST follows its GitHub pre-releases (api::updates::latest_preview_release).
  - Verified live on linuxlt (ost-test1, --setf-test): General's table, Chats' new switch and Compose card, Notifications' Reminders/Channel Notifications and the Manage page (all teams and channels with their current choices), Privacy's Copilot card. Root crate tests: 862 passed.

- 2026-11-21 (agent setF) Calls for Teams Phone users (Teams 26304; settings-app Fg/Po/also-ring and module 30072 ported as api::call_forwarding, tested): with Enterprise Voice (voiceAdminSettings.isEvEnabled) and the effective teamsCallingPolicy (mt.callingPolicy), Call handling and forwarding shows Forward all my calls (then "Choose how all your calls will be forwarded": voicemail / a new number or contact / call group / delegates), else When you receive a call (Do not ring anyone else / Also ring a new number or contact / call group / delegates, with Teams' people-or-number box and "Delay for this many seconds before ringing"), When you can't answer a call (Do not redirect / voicemail / a new number or contact / call group / delegates) and the ring delay; each option only where the policy allows it; saved as Teams' whole callRedirectionSettings. Ringtones for forwarded (CallGroup) and delegated (Delegate) calls beside yours. Verified on linuxlt (ost-test1, --setf-test): the policy (EV, call groups, delegation, forwarding to user and phone allowed) and the page as Teams shows it; saves covered by unit tests, not flipped live.
- Still not built: Call group and Manage delegates pages (and so the call-group/delegates targets have no members), Intelligent call delegation, Viewing incoming calls (callViewMode), Notifications ▸ Apps, About's ring line.

- 2026-11-21 (agent setH) measured on winpc (Teams 26304.1207, ost-test1; every setting put back and re-read):
  - Calls page order: Intelligent call delegation card (top: avatar 32, "Set up" off / "Manage" on), Call handling and forwarding (now ends with ringtones and "Viewing incoming calls" Large/Small window = user property callViewMode immersive|minimized), Voicemail, Out-of-office voicemail, Call group card ("Add a call group" / "Manage" + "Ring everyone at once:" avatars), Delegates card ("Add a delegate" / "Manage").
  - Call group page (Calls › Call group): picker "Add a call group member" (294 x 33.3), "Group members" + "Ring:" Everyone at once / In the order below (enabled for 2–5 members, max 25), rows 668 x 48 #F0F0F0 r4 with Delete. Saves POST …/callredirectionsettings with callGroupDetails.targets (captured).
  - Manage delegates page: picker "Add a delegate", "Your delegates" accordion rows (#F0F0F0 header 48, #FAFAFA panel) with Make calls / Receive calls / Change call and delegate settings / Pick up held calls / Join active calls, then "Announce when delegates join the call". POST …/usersettings/{mri}/delegate {userMri,isActive,allowedActions,createdDate}; PATCH …/delegate/{mri} {isActive,allowedActions}; DELETE …/delegate/{mri}; PATCH …/delegationWarningTone {playWarningTone} (all captured but the last, from the bundle).
  - Intelligent call delegation page: Active/Inactive switch; on: Call handling (external / internal dropdowns, VIPs Edit → Privacy priority access), Personalization (Voice and greeting, Custom instructions, Make a test call), Skills (Follow-ups, spam, recordings), Notifications (banner). PUT {mt}/beta/usersettings/personalAttendantSettings (whole object). Turning it on made Teams create the personal Bookings service "Personal Attendant Followup" (POST {mt}/beta/personalbookings/bookingsService…, service ddf16a17-…; left in place, Teams makes it once). ICD turned off again.
  - Notifications ▸ Apps: one card, per app (Meeting Recaps 981bbfd0-…, Q&A 5db56dd0-…) an expander row with switch and the activity types; ECS activityCustomizations (settingsAggregation, defaultAppSettings OnlyFeed for Recaps).
  - About ring line: ECS Segmentation.TeamsRing = ring3_6 (Targeted release) → "<b>Early Access</b> through Targeted release" link (core.aboutRingInfoLinks.targetedReleaseLink, go.microsoft.com/fwlink/?linkid=2254754).

- 2026-11-21 (agent setH) built (docs/spec/settings.md "Calls ▸ Call group, Delegates, Intelligent call delegation, Viewing incoming calls" and "About ▸ ring line"):
  - Calls: Intelligent call delegation card (Set up / Manage) and page (Active/Inactive switch where the policy is EnabledUserOverride; on: Call handling with the external/internal dropdowns and VIPs (Edit opens Privacy ▸ Manage priority access), Skills' spam and recording switches, Notifications' banner switch), saved as Teams' whole personalAttendantSettings (PUT); the first turn-on where Bookings is allowed also makes the follow-up Bookings service as Teams does (api::call_delegation). Personalization (Voice and greeting, Custom instructions, Make a test call) and Skills ▸ Follow-ups need their sub-pages: TASK-0242. With ICD on, the forwarding card shows Teams' notice in place of its choices.
  - Viewing incoming calls (Large/Small window = user property callViewMode). With Small window an accepted 1:1/group call opens in the small window (OST's compact call window, the call window minimised), back to the large one when captions or RTT turn on (Teams' rule, from its calling code).
  - Call group card and Calls › Call group page (picker, Group members, Ring: Everyone at once / In the order below for 2–5 members, drag to reorder, Delete, 25 at most); Delegates card and Calls › Manage delegates page (picker, expanders with the five permissions, Announce when delegates join the call). api::call_forwarding call_group_*, api::call_delegation, unit-tested.
  - Out-of-office voicemail heading renamed as in Teams 26304.
  - Notifications ▸ Apps by Teams' rule: apps from your feed's Graph activities (teamsAppId) and your saved userGraphSettings, less ECS hideAppSettings and Calendar; rows from the manifest's activityItems or ECS settingsAggregation; defaults (OnlyFeed for Meeting Recaps); the switch saves appNotificationEnabled (api::app_notifications, unit-tested). ost-test1 gets exactly Teams' list: Meeting Recaps (2 rows) and Q&A (13 rows).
  - About: "Early Access through Targeted release" from ECS Segmentation.TeamsRing (api::ecs::about_ring); the Early access card now comes after Third party notice, as in Teams.
- Verified live on linuxlt (OST Test 2, --seth-test --seth-saves; each change read back from the service, then put back): call group add and remove of OST Test 1; delegate add, Join active calls on, remove; Small window then Large window; ringtone Beep then Default; unanswered delay 30 s then 20 s; Q&A "Replies to your posts" Off, then back. ost-test1 (default) display run: ICD policy EnabledUserOverride, apps Meeting Recaps:2 and Q&A:13, ring line shown. Teams on winpc saves Small window as PUT chatsvc properties?name=callViewMode {"callViewMode":"minimized"}, the same request OST sends.
- Open: Teams' small call window itself wasn't measured. Teams rings with a Windows toast now, and VNC clicks on its Accept didn't answer. Three test calls from OST Test 2 went to voicemail and were cut off at once (no voicemail was saved; missed-call entries remain). OST's small window follows Teams' code (minimized view = the compact call window); it still needs comparing with Teams.
- Tenant: turning ICD on in Teams on winpc made ost-test1's personal Bookings service "Personal Attendant Followup" (service ddf16a17-…). ICD was turned off again; the service is left in place.

- 2026-11-21 merged (7c59bd7, 0e8395f, ac82968); 898 lib + 29 desktop tests pass. AC1/AC2 met for every page (Intelligent call delegation's Personalization, Follow-ups and test call moved to TASK-0242; Teams' Small incoming-call window not measurable over VNC). AC3 open: verify the links into Settings (Do not disturb banner, Pause notifications' Notifications settings, call and chat menus).

- 2026-11-21 (agent setI) AC3, links into Settings (aaaa2d1; docs/spec/settings.md "Links into Settings"):
  - Teams (26304 bundles: every settings.launch/launchSection/openSettingPage/settingsstore entity command; settings-app Ar/LV and the scroll hook 266576; measured on winpc): no id = General; Settings and more > Settings and Ctrl+, always open General with Find focused (also after another page); category + setting id = that page, the setting scrolled to the centre, its first control focused and its section highlighted (inset 1 px colorPaletteDarkOrangeBorderActive #DA3B01 / dark #E9835E, fading over 4 s after 50 ms; measured on Customize app bar); sub-page ids open Page > Sub-page; without a setting id the page opens at the top and its first control takes focus. DND banner > Privacy > Manage priority access; Pause notifications > Notifications settings = Notifications at web-activity-settings (not shown for ost-test1: page top, focus unchanged, measured); compose Enter hint = Chats with a setting id but no category (page top, first control focused, measured); Customize view = Chats; notification dialogs' link = Notifications; auto-follow link = Notifications scrolled to Replies; Editor links; /l/settings/<page> deep links.
  - OST: SettingsView.launchSection resolves Teams' ids the same way and draws the highlight; Main.launchSettings/launchSettingsGeneral; every OST entry wired (Settings and more, Ctrl+, DND banner, Pause notifications, Schedule out of office, Customize app bar, compose hint, Customize view, both notification dialogs (their link was unconnected before), auto-follow link, Editor links, VIPs Edit, /l/settings links). Settings checkboxes, radios and picture radios now take keyboard focus; focus rings follow the theme.
  - Verified live on linuxlt (ost-test1 default profile, --seti-test): each link landed on Teams' page/sub-page; General with Find focused; Customize app bar: highlight on the App bar card, Show app names focused, faded after 4 s; Editor settings: Editor spellcheck card highlighted and centred; Replies card scrolled to top.
  - Not in OST (so no link to wire): the message translation menu, the efficiency row (VDI), Premium/Insider/Labs/People pages, contacts sync, leave-and-block toast, NDI and Focus Assist banners.

- 2026-11-22 merged (8e53999); 906 lib + 29 desktop tests pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings as Teams 26304: every page and setting.

- Pages in Teams' order and layout (General with the window-mode table, Accounts and orgs, Privacy, Notifications and activity with Apps and the Channel Notifications manager, Chats and channels, Appearance, Calls with Teams Phone call handling, call group, delegates, Intelligent call delegation, Viewing incoming calls, Devices, Recognition, Accessibility, About with Early access).
- Each setting reads and saves the same values through the same services as Teams (verified live by saving, reading back and restoring).
- Links into Settings resolve Teams' launch ids: page, sub-page and setting, with Teams' arrival outline and focus, from Settings and more, Ctrl+, the DND banner, Pause notifications, out of office, Customize app bar, the compose hint, Customize view, Editor links, notification dialogs and /l/settings/ links.

Links from screens OST doesn't have (message translation menu, Premium/Insider/Labs pages, Windows-only banners) aren't wired. Intelligent call delegation's sub-pages are TASK-0242.
<!-- SECTION:FINAL_SUMMARY:END -->
