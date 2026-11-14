---
id: TASK-0088
title: 'Settings as Teams: every page and setting'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-10T07:56:00Z'
updated_date: '2026-11-14T04:29:00Z'
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
<!-- SECTION:NOTES:END -->
