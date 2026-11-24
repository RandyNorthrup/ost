---
id: TASK-0260
title: Copilot in chats and channels as Teams
status: Done
assignee:
  - '@copY'
created_date: '2026-11-23T18:09:00Z'
updated_date: '2026-11-23T20:28:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0257: Teams' chat and channel headers have an Open Copilot button for Copilot-licensed users (ost-test1 has a Copilot licence), which opens a side pane that reads the conversation; the compose box has its own Copilot (Rewrite / Adjust). OST has neither. See docs/parity/chat.md section 16.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Licensed users see Open Copilot in chat and channel headers where Teams shows it, and it opens Teams' Copilot pane for that conversation with its suggested prompts, answers, sources and feedback
- [x] #2 The compose box's Copilot (Rewrite, Adjust, custom tone) works on drafts and on edits of sent messages as in Teams
- [x] #3 Unlicensed users see neither, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc 2026-11-23 (CDP read-only frame capture): chat header Open Copilot hosts the M365 Copilot app (bizChat) in a 360 end pane; chats: scope Chat/ChatPanel, reference sha256(chatId), cmm cmmnho609kr, ViewChat + HasUnreadMessageTime, [disableGPT5]; meeting chats: Meeting context (sessionType Recap, vroomId = recap id), scope Meeting/ChatPanel, cmm cmm4p9gchbg, []; channel threads (Threads channel thread header, L2): Channel/ChannelL2, cmm cmmce9gzagp, ViewChannel. Channel L1 headers show no Copilot. Sources call executeDeepLink with /l/message links; Teams scrolls to the message and keeps the pane.
- Compose Copilot is already built (TASK-0164); Teams also shows it in the in-place edit box (Format, Emoji, Attach, Write with Copilot, +, Cancel, Done), popover over the edit box.
- Spec: docs/spec/chat-list-and-header.md 7.9d.

- Built: CopilotPane.qml (the 360 end pane hosting the M365 Copilot app, as the meeting/recap panes do), api::meeting_copilot::launch_chat / launch_channel / launch_meeting_chat (+ unit tests against the captured values), backend eventsRequest "chatCopilot", gates chat/channel/meetingChat in compose_copilot_state (licence + Teams' bizChat flags), Conversation header Open Copilot (first context button, Alt+C, closes on chat change / Find), ThreadsPane thread header Copilot (thread takes the channel's place, pane at right), ChatWindow pane, Sources -> showFound jump; Write with Copilot no longer hidden while editing.
- Verified live on linuxlt as ost-test1: OST TEST group call (pane, context identical to Teams', app restored the earlier answer with Sources; clicking a Source logged COPILOT source here 1795448240133 and jumped; new prompt "What are open items in this chat?" answered with Sources, copy, thumbs, follow-up suggestions); OST TEST 240 recap meeting (meeting context identical to Teams' incl. vroomId SPO_..., prompts Recap the meeting / Highlights from meeting chat / List action items; "Recap the meeting" answered "based on the meeting transcript"); OST threads test thread OST TEST 81 (channel context identical to Teams', anchor 73c5697e..., prompts Summarize this thread / open items / decisions). Channel headers show no button (as Teams).
- Unlicensed: OST Test 2 and 3 profiles have isCopilot false (licence details); the gate gives chat/channel/meetingChat false without a licence (unit test chat_copilot_gate_tests).

- Edits verified live (--edit-copilot-test, self chat, OST TEST 95 from the TUI): Write with Copilot in the edit box; popover x 606 w 602 h 118.7 as Teams; Rewrite answered "OST TEST 95 from TUI"; Replace put it in the edit box; Cancel left the message unchanged.
- Tests on linuxlt: lib 937 passed (7 meeting_copilot incl. 3 new), desktop 37 passed (incl. chat_copilot_gate_tests). Committed 640429c9.
- Gaps left: Teams' edit box also shows Attach files and Actions and apps (OST hides them in edits); posts-layout channel post views have no Copilot button yet (Teams' L2 in a Posts channel was not measured); thumbs feedback/copy are the app's own; OST uses hostRing "general" (Teams: ring3_6).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Open Copilot in chats, meeting chats, Threads-channel threads and pop-out chat windows, as Teams desktop: the Microsoft 365 Copilot app in a 360 end pane, launched with Teams' exact values; and Write with Copilot while editing sent messages.

Teams (winpc 2026-11-23, frame messages captured read-only): chat header chat-copilot-button (before Find, Alt+C) opens the bizChat app with scope Chat/ChatPanel, sha256(chat) reference, ViewChat (+ HasUnreadMessageTime), chatContext, [disableGPT5]; meeting chats send the meeting (Recap session, recap id vroomId); a Threads channel's thread header has Copilot (ChannelL2, channelContext, thread takes the channel's place). Channel headers have none.

Changes:
- src/api/meeting_copilot.rs: launch_chat, launch_channel, launch_meeting_chat (+ tests from captured values).
- backend: eventsRequest chatCopilot; gate chat/channel/meetingChat in compose_copilot_state (licence + Teams' bizChat flags; unlicensed off).
- QML: CopilotPane (new), Conversation header button and request, Main end-pane chain + Source links jump (showFound), ThreadsPane thread Copilot with the expanded layout, ChatWindow pane; ComposeBox keeps Write with Copilot in edits.
- Harnesses --chat-copilot-test, --edit-copilot-test; spec chat-list-and-header.md 7.9d; parity chat.md updated.

Verified live on linuxlt (ost-test1): OST TEST group call (answers, Sources jump, copy/thumbs), OST TEST 240 recap meeting (recap from the transcript), OST threads test thread; edit-box Rewrite/Replace/Cancel. OST Test 2/3 have no Copilot licence (isCopilot false) so they get neither.

Follow-ups: Attach/Actions and apps in edit boxes; Posts-channel post-view Copilot unmeasured.
<!-- SECTION:FINAL_SUMMARY:END -->
