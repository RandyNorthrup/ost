---
id: TASK-0263
title: Copilot and edit box gaps from the chat Copilot pass
status: In Progress
assignee:
  - '@copY2'
created_date: '2026-11-23T20:28:00Z'
updated_date: '2026-11-23T20:53:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0260: Teams' edit box shows Attach files and Actions and apps while editing a sent message (OST hides them); the Copilot button in a Posts-layout channel's post view wasn't measured (OST shows none); OST hosts Copilot with ring "general" where Teams sends "ring3_6".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Editing a sent message shows the same compose buttons as Teams, each working as in Teams
- [ ] #2 A Posts-layout channel's post view shows Copilot exactly where Teams does (or not at all if Teams has none), measured on winpc
- [ ] #3 OST hosts Copilot with the same ring and parameters Teams sends for the user
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc 2026-11-23 (CDP, read-only capture; own test messages only):
  - Chat edit box tools: Format, Emoji, Attach files, Write with Copilot, Actions and apps | Cancel, Done (no Loop button). Attach = the same flyout as compose (cloud search/recents, Attach cloud files, Upload from this device), 306.3 wide, right on the box's toolbar end, bottom at the buttons. Actions and apps = the short menu (234.3 wide, rows 218 x 36 from 7.7/12.7, ending 2.7 before the button's right edge): Collaborate with Loop, Set delivery options, Record video clip (a post edit adds Change permissions, Post in other channels).
  - Edit PUT bodies captured: importance "high"/"" from delivery options; files (same entries as a send) added/removed; Loop adds the FluidEmbedCard span to content and properties.cards (sourceType Compose); its trash asks "Discard draft message" and Teams DELETEs the Loop file. OST TEST 95 is back to its text (Edited).
  - Posts-channel post view (L2: See details, Followed threads, pop-out): header Go to channel, Open in new window, divider, Open Copilot (channel-copilot-button) W-107, Find in post W-75, More W-43; open, the view narrows to 532 and Find moves into More; Copilot pane 360 at the end; pop-out window: divider, Copilot, Find, More (narrow 588: Find in More). Context = ChannelL2 (cmm cmmce9gzagp, ViewChannel, channelContext), reference sha256("{team}-{channel}-{post}").
  - Ring: the Copilot frame has hostRing=ring3_6 and context ringId ring3_6: Teams' Metadata.ring.id, which its host takes from ECS Segmentation.TeamsRing.
<!-- SECTION:NOTES:END -->
