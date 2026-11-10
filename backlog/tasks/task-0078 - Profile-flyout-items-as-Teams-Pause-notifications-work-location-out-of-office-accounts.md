---
id: TASK-0078
title: >-
  Profile flyout items as Teams: Pause notifications, work location, out of
  office, accounts
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T16:14:00Z'
updated_date: '2026-11-10T09:07:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rest of Teams desktop's profile flyout, measured on winpc: each item behaves as in Teams, with the same data and services, so OST's flyout matches item for item.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pause notifications works as Teams' (durations, the flyout row, banners held while paused)
- [x] #2 Set work location shows and sets the same location Teams does, when the tenant offers it
- [ ] #3 Schedule out of office opens Teams' out-of-office dialog and saves the same automatic replies
- [ ] #4 Add another account behaves as Teams' (OST's sign-in, separate profiles)
- [ ] #5 Others' status messages show in their profile cards and the 1:1 chat header as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Pause notifications done (see commit): durations, paused card with edit/resume, Custom dialog with Fluent date picker, DND banner; verified both ways with Teams on winpc (OST pause showed "Notifications paused, Until 12:29 AM" in Teams; OST resume put Teams back to Available). Banner Change settings opens Notifications until Settings gets Privacy (TASK-0088).

- Set work location done: Office / Remote / Clear as Teams (PUT v1/me/workLocation/ with location 1/2/0, captured from Teams); OST-set Office showed "In the office" in Teams; cleared from OST and Teams showed Set work location again.

- Own pinned status message banner (presence-statusmessage-banner) and banner queue as Teams (9da2f31); verified against Teams on winpc (same text and date format; dismissing DND revealed the note banner in both).

- AC #5 (others' status message / out of office above compose, profile cards): strings found ("Status of {memberOne}: {message}", "{memberOne} is out of office and may not respond"); measuring the compose banner needs a second account's view (Randy's Teams web) and the Chrome Control extension is disconnected (native host registered to app/current, server is versions/1.11.0; needs browser_extension_install or the user to reload). Profile cards don't exist in OST yet: TASK-0089.
<!-- SECTION:NOTES:END -->
