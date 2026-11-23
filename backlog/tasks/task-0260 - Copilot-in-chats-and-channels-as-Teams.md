---
id: TASK-0260
title: Copilot in chats and channels as Teams
status: In Progress
assignee:
  - '@copY'
created_date: '2026-11-23T18:09:00Z'
updated_date: '2026-11-23T18:46:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0257: Teams' chat and channel headers have an Open Copilot button for Copilot-licensed users (ost-test1 has a Copilot licence), which opens a side pane that reads the conversation; the compose box has its own Copilot (Rewrite / Adjust). OST has neither. See docs/parity/chat.md section 16.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Licensed users see Open Copilot in chat and channel headers where Teams shows it, and it opens Teams' Copilot pane for that conversation with its suggested prompts, answers, sources and feedback
- [ ] #2 The compose box's Copilot (Rewrite, Adjust, custom tone) works on drafts and on edits of sent messages as in Teams
- [ ] #3 Unlicensed users see neither, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc 2026-11-23 (CDP read-only frame capture): chat header Open Copilot hosts the M365 Copilot app (bizChat) in a 360 end pane; chats: scope Chat/ChatPanel, reference sha256(chatId), cmm cmmnho609kr, ViewChat + HasUnreadMessageTime, [disableGPT5]; meeting chats: Meeting context (sessionType Recap, vroomId = recap id), scope Meeting/ChatPanel, cmm cmm4p9gchbg, []; channel threads (Threads channel thread header, L2): Channel/ChannelL2, cmm cmmce9gzagp, ViewChannel. Channel L1 headers show no Copilot. Sources call executeDeepLink with /l/message links; Teams scrolls to the message and keeps the pane.
- Compose Copilot is already built (TASK-0164); Teams also shows it in the in-place edit box (Format, Emoji, Attach, Write with Copilot, +, Cancel, Done), popover over the edit box.
- Spec: docs/spec/chat-list-and-header.md 7.9d.
<!-- SECTION:NOTES:END -->
