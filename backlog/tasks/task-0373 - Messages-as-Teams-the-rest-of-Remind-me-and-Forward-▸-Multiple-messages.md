---
id: TASK-0373
title: 'Messages as Teams: the rest of Remind me and Forward ▸ Multiple messages'
status: Done
assignee:
  - '@t373'
created_date: '2026-11-27T21:42:00Z'
updated_date: '2026-11-28T02:56:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-0363 (its second PR added Remind me, the Reminders quick view, Ask Copilot and Forward ▸ Multiple messages in chats). What Teams does that OST doesn't yet, from Teams 26304 (docs/spec/message-actions.md §13-15):
- Channel posts: Forward is a split item there too (enableForwardMultiselectChannelPane): picking posts in the posts list, with the same selection bar.
- Leaving a chat mid-selection: Teams asks "Discard and leave" (message_list_multiselect_discard_event_*); OST drops the selection.
- Reminders view rows: More options also has Save / Unsave this message.
- The saved bookmark and reminder alarm in channel posts and replies (OST shows neither in channel views).
- Ask Copilot in a channel post's view (L2) and thread pane.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Channel posts: Forward ▸ Multiple messages works as in Teams, checked side by side
- [x] #2 Leaving a chat while picking messages asks Discard and leave, as Teams
- [x] #3 Reminders rows' More options include Save / Unsave this message
- [x] #4 Channel posts and replies show the Saved and reminder icons as Teams
- [x] #5 Ask Copilot is offered in a channel post's view and thread pane where Teams offers it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research on Teams desktop 26304 (testpc2 OST Test 2, testpc1 ost-test1) and bundles: channel L1/L2 multiselect, speedbump, Reminders row menu, status icons, Ask Copilot in L2/thread pane.
2. ForwardSelection (shared picks/rules) + SelectCheck; ChannelPosts (L1 posts) and PostThread (L2 post + replies) selection modes and bars.
3. LeaveSelectionDialog + guards (chat list, quick views, app bar, back/forward, Go to channel / Open in new window).
4. Reminders row menu: icons, Save/Unsave (saved state from rcmetadata), Open in new window.
5. MessageStatusIcons in ChannelPosts and PostThread (posts, replies, grouped replies).
6. Ask Copilot in PostThread / thread panes (Channel annotation in CopilotPane).
7. Build on testpc2, live check OST beside Teams, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (Teams desktop 26304; testpc2 as OST Test 2, testpc1 as ost-test1, driven by a scheduled-task mouse script; bundles 26304 on linuxlt):
  - AC3 was NOT met: QuickListView's Reminders row menu (remMenu) had only Edit reminder / Remove reminder / Go to conversation. Teams: Edit reminder ▸, Remove reminder, Save/Unsave this message, Go to conversation, Open in new window, all with icons, end-aligned under the button.
  - Channel L1: Forward split on posts only (not replies, canForwardMultiselect !(isL1View && ChannelReply)); picking hides reactions/replies/Reply in thread, content +32, checkbox 13 in centred, meeting posts disabled "This message can't be forwarded."; footer replaces Post in channel.
  - Channel L2 (post view): split on post and replies; each a separate card 12 apart, no avatars, content 52 in.
  - Speedbump: chat-app j_ (multiselect-speedbump-dialog), 600 wide, Cancel / Discard; chat list click and Go to channel both blocked; Discard carries on.
  - Status icons: Berry bookmark/alarm ~10 after Edited / time on the name line (395276 v).
  - Ask Copilot: L2 reply menu (ost-test1) Forward ▸, Copy link, Save, Remind me, Ask Copilot | …; not in L1 (enableAskCopilotInChannelL1 unset). Channel annotation from 830567; thread pane uses openThreadsCopilot.
- Research side effects on OST Test 2 (to undo after the live check): Saved the "0.3 release checklist" post and set a Tomorrow reminder on OST Test 2's reply "Release notes are reviewed…" in OST Test Team > General.

- Found while checking AC3: Chat ▸ Reminders opened Followed threads on main (TASK-0365's Discover change set QuickListView.kind to saved/followed only). Fixed in Main.qml.
- Live (testpc2, OST under WSLg with OST_QML_DIR, OST Test 2 beside Teams desktop as OST Test 2):
  - AC3: Reminders row ··· = Edit reminder ▸ / Remove reminder / Save this message / Go to conversation / Open in new window with icons, same as Teams. Save from the row: the chat message got its bookmark, Teams' row menu then said "Unsave this message"; Unsave removed it again.
  - AC1 L1: General post ··· ▸ Forward options ▸ Multiple messages: post-only cards, checkbox 13 in, content +32, meeting posts disabled with "This message can't be forwarded.", footer for Post in channel; clicking toggles (0 selected / Next off).
  - AC1 L2 (Followed threads ▸ General post view): every reply has the split; picking turns post and replies into separate cards (matches Teams); Next opened Forward this message with both picked replies (cancelled; nothing sent).
  - AC2: chat list click, app bar (Calendar) and the post view's Go to channel all ask Discard and leave; Cancel keeps the picks, Discard goes on (Team lunch / the channel).
  - AC4: bookmark after Edited on the post and the alarm after the reply's time, in the posts list and the post view (Teams side by side the same).
  - AC5 (default profile ost-test1): post-view reply ··· has Ask Copilot after Remind me (as Teams for ost-test1); clicking opened the post view's Copilot pane with the quoted reply and Teams' prompt, answered (COPILOTPANE ask sent channel). Same in a Threads channel's followed thread.
- Not verified live: forwarding picked channel messages to a chat (typing into the recipient box doesn't reach WSLg; the send path is TASK-0363's forwardMessages with the channel as source); the Threads pane's own thread (ThreadsPane) Ask Copilot (same code as the followed thread; no thread with replies in OST layout test); the Reminders Unsave icon tweak (outline, as Teams) after the live run.
- Cleanup: the post save and the reply reminder made for research were undone from OST; Teams on testpc1/testpc2 left on the chats they showed. A stray: my driver clicked once into another agent's OST window on testpc2 (it opened chat OST TEST 349 there) before I added a window-size guard.
- Follow-up TASK-0380 for differences seen on the way (channel reminder rows, replies line, missing post-menu items, the empty-date meeting card).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Finishes TASK-0363's message menu work for channels, as Teams desktop 26304 does it.

- Forward ▸ Multiple messages in channels: the posts list picks posts (not replies, as Teams), the post view picks the post and its replies. Shared ForwardSelection (rules, limit 5, meeting posts disabled with "This message can't be forwarded.") and SelectCheck (checkbox 13 in, a MouseArea so links and cards under it don't act). Picking strips cards to the post, moves content in, turns the post view into one card per message, and swaps Post in channel / Reply in thread for the selection bar.
- Discard and leave (Teams' multiselect speedbump): LeaveSelectionDialog guards the chat list, quick views, app bar, back/forward and the post view's Go to channel / Open in new window; Discard drops the picks and carries on.
- Reminders rows' More options: icons, Save / Unsave this message (saved state from each conversation's rcmetadata, set_saved_at) and Open in new window. Also fixes Chat ▸ Reminders showing Followed threads (lost in TASK-0365).
- Saved and reminder icons in channel posts, replies and grouped replies (posts list and post view).
- Ask Copilot in a channel's post view and Threads thread panes: the Copilot pane gets Teams' prompt with a Channel annotation (830567).
- FluentSurface depth 0 draws no shadow.

Tests: quick_views reminders_marked_saved_by_their_conversation (+ existing quick_views tests). Live checks on testpc2 beside Teams desktop are in the notes; not verified live: sending a channel multi-forward, ThreadsPane Ask Copilot. Follow-up TASK-0380.
<!-- SECTION:FINAL_SUMMARY:END -->
