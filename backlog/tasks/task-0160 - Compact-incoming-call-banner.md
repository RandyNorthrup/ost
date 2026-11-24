---
id: TASK-0160
title: Compact incoming-call banner
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T16:13:00Z'
updated_date: '2026-11-15T16:55:00Z'
labels:
  - desktop
  - notifications
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' incoming-call card has a Compact layout (114 px; notifications-app fo() 'compact') used when Settings ▸ Notifications ▸ Display ▸ Size is Compact. OST's call card in NotificationBanners is always the 240 px Comfy one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With Size set to Compact, an incoming call shows Teams' compact call card (layout and size measured against Teams)
- [x] #2 Accept, Decline and Ignore work from it as from the Comfy card
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured Teams' calling banner on winpc by ringing OST Test 1 from OST Test 2 (OST on linuxlt, --call-out --cancel-ring), Comfy (240) and Compact (114); Teams' size setting put back to Comfy.
- Teams' calling card differed from OST's old one in Comfy too, so both were redone.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's incoming-call banner is now Teams' calling card in both sizes.

- Comfy 240: Teams' header (app, More options, Dismiss = ignore), the caller's picture or initials filling the card blurred (10 px) under Teams' top and bottom dark gradients, the 80 px picture, name and "is calling you" on 16 px lines, Accept with video / Accept with audio / Decline (102.67 x 32, 8 apart; #5B5FC7 and #D13438).
- Compact 114: 48 px picture, name with small More options and Dismiss, "is calling you", the same three buttons below.
- IncomingCall.qml removed; the card lives in NotificationBanners.qml. A call whose video is found after it starts ringing updates the card.

Tests: --notif-banner-test (call card in all corners and both sizes), a real call from OST Test 2 to OST Test 1 on linuxlt (banner shown, rang out).
<!-- SECTION:FINAL_SUMMARY:END -->
