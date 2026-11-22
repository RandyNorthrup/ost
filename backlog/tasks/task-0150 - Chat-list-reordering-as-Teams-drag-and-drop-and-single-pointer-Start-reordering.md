---
id: TASK-0150
title: >-
  Chat list reordering as Teams: drag and drop, and single pointer 'Start
  reordering'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T05:37:00Z'
updated_date: '2026-11-21T21:40:00Z'
labels:
  - chat-list
  - accessibility
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lets you reorder chats in Favorites and custom sections, and teams and channels, by drag and drop. Settings > Accessibility > 'Turn on single pointer controls' (clientPreferences simpleCollab.enableSinglePointReordering, on this device) adds 'Start reordering', an alternative to drag and drop in the chats and channels list. OST's chat list can't be reordered yet, so the Accessibility card is left out until this is built. Measure Teams' drag feedback, the Start reordering mode and where the order is saved (sections/favorites order, teamsOrder) on winpc first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chats in Favorites and custom sections, and teams and channels, can be reordered by drag and drop as in Teams, and the order is saved where Teams saves it (Teams on winpc shows the same order)
- [x] #2 Settings > Accessibility shows 'Turn on single pointer controls' with Teams' text and icon (hand point), kept on this device
- [x] #3 With it on, the chat list's item menu has 'Start reordering', which reorders without dragging as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (dd601ea): drag and drop in Favorites, custom sections and teams with Teams' visuals (overlay, faded row, 2 px drop line, Escape cancels, teams fold while dragging a team; channels don't reorder); chat order saved through Teams' section-reorder request (a restarted Teams on winpc showed OST's order); team order saved in Teams' user property and read back. Settings > Accessibility > Turn on single pointer controls (device-only) and Start reordering with Move Up / Move Down.

Left: confirm Teams shows OST's team order (not picked up within 7 s; not checked after a Teams restart); dragging a whole section and dragging a chat into another section; keeping teams folded after a team drag.

- 2026-11-21 (teamsH) team order, both ways, live (spatest = ost-test1; winpc Teams 26304): OST's Start reordering moved OST Test Team above Secure Coast Network Solutions and saved it (users/ME/properties teamsOrder). Teams dragging a team writes exactly the same request (captured: PUT {chatsvc}/v1/users/ME/properties?name=teamsOrder with {"teamsOrder": "[{teamId, order}]"}), and OST read Teams' order back on its next start. Moving it back in OST, the running Teams showed OST's order within about 15 s, no restart. The order ends as it was (Secure Coast Network Solutions, OST Test Team). (One earlier OST write wasn't shown after a Teams restart: Teams had been killed seconds after it; the live check is the clean one.) Chats in Favorites and custom sections were confirmed in Teams after a restart in dd601ea; channels don't reorder in Teams either.
- Fixed: the generic --shots timer quit --reorder-test runs early (now excluded).

- 2026-11-21 (review on merge): reopened. Team order was verified both ways with Teams; drag-and-drop of chats in Favorites and custom sections, and of channels, still needs the same live check before AC1 is met.

- 2026-11-21 (meetI) AC1 chats and channels by drag and drop, live (spatest = ost-test1, winpc Teams 26304): new harness --reorder-drag=<from>:<to> drags with real mouse events sent to the window, so the row's own DragHandler runs (press, moves, release). Test set-up in Teams: OST Test 2 into Favorites; section "OST TEST 150 section" (Custom order) with OST Test 3, OST group test, OST test channel, OST test channel 2.
  - Favorites: OST dragged OST Test 2 above OST Test 1 (You); the server kept it, and the running Teams showed the same order within seconds (no restart). Dragged back the same way; Teams followed.
  - Custom section: OST dragged OST Test 3 below OST group test (chat), then OST test channel 2 above OST test channel (channel). Both were kept by the server, and Teams showed each new order live.
  - Other way: a drag in Teams (OST test channel) showed in OST on its next start. Teams put the channel at the top of the section, although its drop line was under OST Test 3 (Teams quirk, seen with a VNC drag). OST's drags then restored the section's order.
  - Channels within a team don't reorder in Teams (no drop line), and OST matches that.
- Restored: the test section removed and OST Test 2 taken out of Favorites (in Teams). The list is as before: Favorites = OST Test 1 (You), no custom sections, team order unchanged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chat and team reordering as Teams: drag and drop in Favorites, custom sections and teams (dd601ea), single pointer Start reordering, and the order saved where Teams keeps it.

Verified live (2026-11-21): team order written by OST (users/ME/properties teamsOrder, the same request Teams sends when you drag a team) shows in the running Teams on winpc within seconds, and Teams' order reads back into OST; chat order in sections confirmed earlier after a Teams restart. Original order restored.

Tests: --reorder-test=teams --reorder-only-up (spatest), winpc CDP capture of Teams' drag. Fix: the generic --shots timer no longer quits reorder runs.
<!-- SECTION:FINAL_SUMMARY:END -->
