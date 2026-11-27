---
id: TASK-0363
title: >-
  Messages as Teams: hover bar above neighbours, ··· menu Remind me / Ask
  Copilot / Forward submenu, plain-text URLs, grouped thread replies
status: Done
assignee:
  - '@claude-0363'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T21:59:00Z'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A-09: Message hover bar is drawn underneath the message above it; fixed to match Teams desktop, checked side by side
- [x] #2 A-10: Message ··· menu lacks "Remind me", "Ask Copilot" and Forward's split submenu; fixed to match Teams desktop, checked side by side
- [x] #3 A-04: OST turns plain-text URLs in received/sent messages into links; Teams shows them as text; fixed to match Teams desktop, checked side by side
- [x] #4 A-20: Consecutive replies by the same person in a channel thread aren't grouped; fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. A-09: raise the hovered message above its neighbours in Conversation's BottomToTop list (z while the bar shows) and make the bar's HoverHandler blocking, so the message above neither covers the bar nor takes the hover.
2. A-04: Teams' renderer links only <a> elements (TextDeserializer 721466 passes text through); stop linkifying bare URLs in message HTML (keep it for status notes).
3. A-20: Teams' worker groups channel replies (92502 d: same sender/app, previous not deleted, ordinary messages, <=5 min, never the first reply; summary view's first shown reply keeps its header); avatar+indicator hidden (visibility), header gone, body 8 under the previous. Apply in ChannelPosts (L1) and PostThread (L2).
4. A-10: research Remind me (rcmetadata r/dr, 48:reminders), Ask Copilot (BizChat side pane, ChatHighlights prompt) and Forward split (This message / Multiple messages + multiselect forward mode); implement in a second PR.
5. Live checks side by side with Teams (web as OST Test 2 / desktop on testpc2) and OST on linuxlt as OST Test 2/3.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- A-09 cause: Conversation's list is BottomToTop, so the message above is a later delegate and paints over the bar that sits on this bubble's top edge. Fix: delegate z 2 while its bar shows; the bar's HoverHandler is blocking, so the message under it doesn't take the hover. Channel replies already raised themselves.
- A-04: Teams' renderer links only <a> (721466 TextDeserializer passes text through; Teams on the web shows the audit URL as text). sanitize_html no longer linkifies; status notes keep it (sanitize_note_html).
- A-20: Teams' worker 92502 `d` sets reply `attached`; measured on Teams web (OST test channel 2): grouped reply is 28 tall (4+20+4, margins 4), avatar+indicator visibility:hidden, no header. ChannelPosts and PostThread group with MessageHost.replyAttached.
- A-10 research (Remind me / Ask Copilot / Forward split) done; implemented in a second PR (branch task-0363-message-menu).

- Live (linuxlt, OST Test 3, PR1 build, --pointer-script harness in OST's own window): hovering "One more thing" draws its bar over "The slides…"; moving up onto it keeps it (More reactions tooltip); a received message's bar sits over the "Today" divider and stays while moving up; the ··· of the short "Also, lunch…" opens its menu (Reply with quote … Delete). Teams on the web (OST Test 2) side by side.
- Live A-04: "OST TEST 363 plain URL check: https://example.com/… is the guide" sent from Teams on the web (no anchor in its HTML; Teams shows text) shows as plain text in OST. The audit's Fedora message in OST Test 1 ↔ OST Test 2 also has no anchor in Teams.
- Live A-20: OST test channel 2 — OST Test 2's two replies under one header, the second text 36 px under the first (Teams on the web: 36).

- A-10 research (Teams 26304 + Teams on the web as OST Test 2): Remind me = rcmetadata {r, mid} / {dr:true} / {r:0}; 48:reminders stream (newReminder, then reminderDue without preview/name; removal rewrites the newest record as deleteReminder); Activity dueReminderInChat; Ask Copilot = BizChat side pane with updatePromptInputData; Forward split in chats (This message / Multiple messages), selection mode measured (checkbox 16 at avatar+4, bubbles +24, footer padding 32 64 24).
- Live (linuxlt, OST Test 3, PR2 build, pointer-script harness): received message menu matches Teams' (Forward F | >, Copy link, Save, Remind me >, Pin | Mark as unread, Share to Outlook, Translation | Report | More actions); Remind me submenu Now / Later today 1:30 PM / Tomorrow Sat, 9:00 AM / Next week Mon, 9:00 AM / Custom; Now -> "A reminder has been set. View", alarm on the message, Reminders quick view with 1 due, row "Due 12:43 PM"; Edit reminder + Remove reminder; Later today -> upcoming chip "2:00 PM"; row ··· Remove -> "Reminder removed.", list empty; Custom dialog (Fri Nov 27 2026, 1:00 PM) Add -> at 13:30 the "Reminder due" banner (OST Test 2) showed; Forward ▸ Multiple messages -> checkboxes, "2 selected", Next -> Forward this message with both cards (cancelled, nothing sent).
- Not verified live: Ask Copilot as a Copilot-licensed account (both ost-test1 profiles on linuxlt were in use by other agents; a fresh profile's sign-in didn't complete). Its menu item stays hidden for OST Test 3, as Teams hides it for OST Test 2.
- Follow-up: TASK-0373 (channel posts multiselect, Discard and leave, Save in Reminders rows, icons in channel views, Ask Copilot in channel L2).

- Live Ask Copilot (ost-test1, default profile, rebased build): menu = Teams' for ost-test1 (Ask Copilot after Pin); clicking it opened the chat's Copilot pane with the quoted message and "Search for more context and explain this in more detail", answered at once.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Messages as Teams (audit A items 9, 10, 4, 20), in two PRs.

PR #55 (merged): the hover bar is raised above the message above and its hover blocks the message under it (a short message's ··· was unreachable); bare URLs stay text as Teams renders them (only <a> links; notes still link); channel replies group as Teams' worker does (same sender/app, <=5 min, not after a deleted one, first reply never), keeping "Edited"; a --pointer-script harness that drives OST's own window.

PR 2: the ··· menu's Remind me (presets, Custom, Edit/Remove; rcmetadata), the message alarm, "A reminder has been set." with View, Chat ▸ Quick views ▸ Reminders over 48:reminders (Due/Upcoming/Completed, Mark as completed, Edit/Remove/Go to conversation, due count, New), Activity's Reminder due and the Reminder due banner; Ask Copilot (the chat's Copilot pane with Teams' prompt and the message as annotation); Forward as Teams' split item with Multiple messages (selection, bar, multi-card dialog, one forward call).

Tests: msgactions reminders_come_from_r_and_rl2, quick_views reminders_read_like_teams, activity due_reminders_read_reminder_due, messages bare_urls_stay_text...; live checks listed in the notes. Not verified: Ask Copilot with a licensed account; the Edited line on a grouped reply and PostThread grouping against Teams. Follow-up TASK-0373.
<!-- SECTION:FINAL_SUMMARY:END -->
