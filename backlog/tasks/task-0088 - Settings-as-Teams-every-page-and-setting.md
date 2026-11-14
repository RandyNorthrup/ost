---
id: TASK-0088
title: 'Settings as Teams: every page and setting'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-10T07:56:00Z'
updated_date: '2026-11-14T22:58:00Z'
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
- [ ] #1 Settings lists Teams' pages in Teams' order with the same layout
- [ ] #2 Each page's settings show and save the same values Teams does, through the same services
- [ ] #3 Links into settings from elsewhere (Do not disturb banner, Pause notifications' Notifications settings, call and chat menus) open the right page and section
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Phase 1 (d9ca83d): layout, General/Appearance/Chats/Privacy/Accessibility/Devices pages, synced storage (user properties + MT) captured per setting, Out of office page. Still: Notifications page as Teams, Accounts and orgs, Calls, Files and links, App permissions, Recognition, remaining items; OST behaviour for saved-only settings (Copilot row, compact density, auto-follow, suggested replies, chat landing, list previews/time stamps, sign language mode).

- 2026-11-13: App permissions built (measured on winpc): the list by Teams' installedAppsPermissions rule (personal entitlements + every app in your teams' entitlements + changed apps, with device permissions; app_details::permission_apps — OST Test 1 gets Teams' exact 22), Teams' card/expander layout, switches kept on the device via the existing appDevicePermissions store (no Teams request on flip). Recognition (voice/face enrolment) split to TASK-0134. Harness --app-permissions-test; settings-pages harness includes the page.

- 2026-11-14 Devices page as Teams (measured on winpc by DOM; the page's camera preview was never screenshotted): Audio section ("Audio settings": Speaker, Microphone, Automatically adjust mic sensitivity → apm::set_auto_gain, Noise suppression with Background noise only / Voice isolation (disabled, needs Microsoft's voice profile), Secondary Ringer → ringtone::set_secondary rings a second output device) and Video section ("Video settings": preview with Teams' bar, Camera, Green Screen, Mirror my video, Adjust brightness, Soft focus; from TASK-0139). Not offered: Sync device buttons (headset HID), Make a test call (TASK-0141), Spatial audio (no renderer), Devices section (Teams Rooms connected devices / meeting room mode).

- 2026-11-14 General page, part 1 (Teams measured on winpc): Meeting card with "Ask me to confirm when I leave a meeting" (client preference meeting.enableLeaveConfirmationDialog → local setting leaveConfirmation) and Teams' Stay/Leave popover under Leave (also for Ctrl+Shift+H); Time zone card (the system's IANA zone). Verified with --leave-confirm-test in a Meet now.
- General page still to do (storage found in Teams' settings bundle): Starting chats (userPersonalSettings.messagingSettings.alwaysPopOutNewChat; needs a new-chat window), the existing "Opening content" setting's behaviour (client preference windowing.shouldOpenContentInNewWindow; currently saved only), Language and regional formats (locale user property + host formatting locale), Translation (translationSettings V2: targetLanguageCode, translationMode SUGGEST/ALWAYS/NEVER, knownLanguages — not stored in user properties when changed on winpc; service still to find), Editor spellcheck (Manage), Keyboard shortcuts profile (keyboardShortcutsSettings), Use Enter or Spacebar to show content (messagingSettings.disableAutomaticConvSwitchOnKeyboardNav; OST's chat list needs arrow-key navigation first), Efficiency mode (client preference optimizedPerf). New meeting controls switches Teams to another toolbar (not measured). Teams' call quality survey after leaving was captured (scratchpad callsurvey-dom.txt / callsurvey.png) for TASK-0104.

- 2026-11-14 General part 2: Keyboard shortcuts profile (Teams only / + Slack / + Zoom / + combined) saved to the synced keyboardShortcutsSettings {shortcutProfile: default|chats_alt|meetings_alt|chats_meetings_alt} (added to preferences::JSON_PROPERTIES); Teams' Windows desktop key maps from its bundle: Slack set (Ctrl+Shift+1… apps, Ctrl+; shortcuts, Ctrl+K go to, Ctrl+. info pane, Ctrl+Alt+A unread, Ctrl+Alt+U channels, compose Ctrl+E link, Ctrl+Alt+Shift+C code block, Ctrl+Shift+9 quote), Zoom set (Ctrl+U message pane, Alt+H chat list, Alt+A mute, Alt+V video, Alt+Y raise hand, Alt+S share, Alt+Q/Ctrl+Shift+E leave, Ctrl+Shift+V answer with video). Verified with --shortcut-profile-test (synced to the service and read back; left at default). Not yet: ReactToLastMessage (Ctrl+Shift+\), AnnounceActiveSpeaker (Ctrl+2), the profile choice inside the Keyboard shortcuts dialog.
<!-- SECTION:NOTES:END -->
