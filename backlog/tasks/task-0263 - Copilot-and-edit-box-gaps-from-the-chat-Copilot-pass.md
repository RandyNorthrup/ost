---
id: TASK-0263
title: Copilot and edit box gaps from the chat Copilot pass
status: Done
assignee:
  - '@copY2'
created_date: '2026-11-23T20:28:00Z'
updated_date: '2026-11-24T00:42:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0260: Teams' edit box shows Attach files and Actions and apps while editing a sent message (OST hides them); the Copilot button in a Posts-layout channel's post view wasn't measured (OST shows none); OST hosts Copilot with ring "general" where Teams sends "ring3_6".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Editing a sent message shows the same compose buttons as Teams, each working as in Teams
- [x] #2 A Posts-layout channel's post view shows Copilot exactly where Teams does (or not at all if Teams has none), measured on winpc
- [x] #3 OST hosts Copilot with the same ring and parameters Teams sends for the user
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc 2026-11-23 (CDP, read-only capture; own test messages only):
  - Chat edit box tools: Format, Emoji, Attach files, Write with Copilot, Actions and apps | Cancel, Done (no Loop button). Attach = the same flyout as compose (cloud search/recents, Attach cloud files, Upload from this device), 306.3 wide, right on the box's toolbar end, bottom at the buttons. Actions and apps = the short menu (234.3 wide, rows 218 x 36 from 7.7/12.7, ending 2.7 before the button's right edge): Collaborate with Loop, Set delivery options, Record video clip (a post edit adds Change permissions, Post in other channels).
  - Edit PUT bodies captured: importance "high"/"" from delivery options; files (same entries as a send) added/removed; Loop adds the FluidEmbedCard span to content and properties.cards (sourceType Compose); its trash asks "Discard draft message" and Teams DELETEs the Loop file. OST TEST 95 is back to its text (Edited).
  - Posts-channel post view (L2: See details, Followed threads, pop-out): header Go to channel, Open in new window, divider, Open Copilot (channel-copilot-button) W-107, Find in post W-75, More W-43; open, the view narrows to 532 and Find moves into More; Copilot pane 360 at the end; pop-out window: divider, Copilot, Find, More (narrow 588: Find in More). Context = ChannelL2 (cmm cmmce9gzagp, ViewChannel, channelContext), reference sha256("{team}-{channel}-{post}").
  - Ring: the Copilot frame has hostRing=ring3_6 and context ringId ring3_6: Teams' Metadata.ring.id, which its host takes from ECS Segmentation.TeamsRing.

- Built (copY2): edit box keeps Attach files (its own CloudAttach + Upload from this device; the message's files as removable cards) and Actions and apps (short menu: Collaborate with Loop, Set delivery options without Urgent, Record video clip); Done sends backend.editMessageWith → api::messages::edit_message_with/apply_edit_extras (importance, files kept/removed/added, Loop span + card, clip AMSVideo + amsreferences; a message's own Loop span kept). Recorder fills the box that asked (Conversation.clipBox). Edits in chats, channel posts/replies and post views use it.
- Built: PostThread Open Copilot (channelPost gate = channel flag + channels.enableChannelCopilotInL2Header), Find inline only at header width >= 640, pane 360 beside the post or covering a too-narrow window; ChannelThread.team_in_reference for the "{team}-{channel}-{post}" reference.
- Built: api::ecs::ring() (Segmentation.TeamsRing, else metadata.ring.id, else general) used for Copilot hostRing, TeamsJS ringId, uihRing, x-ringoverride, calendar Copilot hostRing and Workflows ringId; CopilotPane hosts the app with no conversation in its context, as Teams.
- Verified live on linuxlt (ost-test1, self chat, new message "OST TEST 263 edit tools"): edit tools at 968.6/1000.6/1032.6/1064.6/1096.6, Cancel 1137.3, Done 1169.3 (Teams 968.7…1169.3); + menu 234.3 x 133.3 at 891.6 (Teams 892) with Loop/delivery/clip; delivery 217.3 x 113.3 at 1046 (Teams 1046); Attach popover 305 at 896.1 (Teams 896). Important + local file → message importance high with copY2-edit.txt; restore → importance "" and file removed; Loop in edit → fluidEmbedCard card; clip in edit stored (AMS) and sent.
- Verified live: General meeting post See details: Copilot at 1173, Find 1205, More 1237 (Teams same); anchor a375eae6… identical to Teams; open: view 532, Copilot 845, More 877, pane 920 x 360 with ChatReady; post window 588: Copilot 513, More 545, pane covers (Teams same). hostRing=ring3_6 and ringId ring3_6; app context keys/values match Teams' capture (chatId/channelId "", tenant teamSiteDomain, manifest 1.23, SSR true) except Teams' extra appIconPosition -17 and OST's extra defaultOneNoteSectionId. Chat Copilot (OST TEST group call) still reaches ChatReady.
- Tests on linuxlt: lib 941 passed, desktop 37 passed.

- After the clip edit the message keeps its Loop card and has the clip (videos [0-wus-d10-…]); post view open-state shot matches Teams (filled brand Copilot, Find in More, pane prompts Summarize this thread / open items / decisions). Committed a86346ab.
- Left (follow-ups): Teams' More "View Copilot history" (viewSummaryHistory) in the post view; the edit box doesn't show a message's existing Loop card or clip (kept as they are on Done); a post edit in Teams is the post composer (subject, Change permissions, Post in other channels); OST has no Followed-threads L2 view (Teams puts Copilot in More there); context lacks Teams' appIconPosition (-17).
- Test data: self chat message "OST TEST 263 edit tools" (Loop card + 3 s test clip, edited); its Loop file in ost-test1's OneDrive; copY2-edit.txt in "Microsoft Teams Chat Files"; OST TEST 95 edited in Teams and restored to its text (Edited).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' edit box tools, Copilot in a Posts channel post's view, and Teams' ring for the apps OST hosts, all measured on winpc (2026-11-23) and verified live on linuxlt as ost-test1.

Teams (winpc, own test messages, edit PUTs captured read-only):
- The edit box is Format, Emoji, Attach files, Write with Copilot, Actions and apps | Cancel, Done. Attach is the compose popover. Actions and apps is a short menu: Collaborate with Loop, Set delivery options (Standard/Important), Record video clip. Done PUTs importance, files, and a Loop card + span.
- A post's view (See details, Followed threads, pop-out) has Open Copilot before Find in post (W-107). Find goes into More under a 640 wide header. The pane is 360, or covers a 588 window. The app gets ChannelL2 context and reference sha256("{team}-{channel}-{post}").
- hostRing/ringId are ring3_6 = ECS Segmentation.TeamsRing.

Changes:
- ComposeBox: edit-mode Attach (own CloudAttach + upload) and the message's files as removable cards; the short + menu with Loop; delivery popup without Urgent (217.3 x 113.3); editExtras()/editSent().
- backend editMessageWith + api::messages::edit_message_with / apply_edit_extras (+ test); Conversation/ChannelPosts/PostThread edit boxes use it; the recorder fills the asking box (clipBox).
- PostThread: Copilot button and pane, the 640 rule for Find, Alt+C; channelPost gate (channels.enableChannelCopilotInL2Header); ChannelThread.team_in_reference (+ test with Teams' anchor).
- api::ecs::ring() (+ test) for Copilot hostRing, TeamsJS ringId, uihRing, x-ringoverride, calendar Copilot, Workflows; CopilotPane gives the app Teams' conversation-free context.
- Harnesses --edit-tools-test, --post-copilot-test; specs messages-and-composer (edit box tools), chat-list-and-header 7.9d (post view, ring); i18n ids regenerated.

Verified: edit tool, menu, popup and popover geometry equal to Teams'. Important + file applied and restored; Loop and clip added by edit. Post view and window header positions and the pane equal Teams'. Anchor a375eae6… is identical. hostRing and ringId are ring3_6. The chat Copilot still works.
Tests: lib 941 passed, desktop 37 passed.

Follow-ups: View Copilot history (post view More); the edit box does not show an existing Loop or clip; Teams edits posts in the post composer (Change permissions, Post in other channels); no Followed-threads L2 view in OST.
<!-- SECTION:FINAL_SUMMARY:END -->
