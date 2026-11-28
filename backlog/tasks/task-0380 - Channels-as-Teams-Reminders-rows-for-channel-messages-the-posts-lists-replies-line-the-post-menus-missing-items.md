---
id: TASK-0380
title: >-
  Channels as Teams: Reminders rows for channel messages, the posts list's
  replies line, the post menu's missing items
status: Done
assignee:
  - '@t380'
created_date: '2026-11-28T02:55:00Z'
updated_date: '2026-11-28T06:53:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Differences seen beside Teams desktop 26304 (testpc2 as OST Test 2, testpc1 as ost-test1) during TASK-0373, 2026-11-27; not covered by an existing task (searched the backlog and the QML):
- Chat > Reminders: Teams shows a channel message's reminder like a Followed threads row (the channel's picture and name, the post's subject, then "{sender}: {text}" after the sender's 20 px picture) and an upcoming reminder's chip with a grey outline; a chat reminder's text wraps to two lines. OST shows every row as a chat row, one line, brand chip.
- Posts list: Teams' replies line reads "Open {n} replies from {people}"; OST shows "{n} earlier reply".
- Channel post and reply ··· menus: Share to Outlook, Immersive Reader and Report this message are missing (MessageHost: "not built yet").
- A channel meeting's post in OST shows a calendar card dated "Sunday, December 31, -0001" (an empty start) that Teams doesn't show.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A channel message's row in Chat > Reminders looks as in Teams (channel, post subject, sender line, chip styles; two-line text for chats), checked side by side
- [x] #2 The posts list's replies line reads as Teams' does
- [x] #3 Channel post and reply menus include Share to Outlook, Immersive Reader and Report this message where Teams shows them
- [x] #4 A channel meeting's post shows no calendar card with an empty date
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams 26304 (bundles + Teams web as OST Test 2): reminders slice rows, response summary, channel menu registry.
2. Reminders: parse parentMessageSubject/Preview for channel replies; channel rows as Followed threads rows; chip styles per state; two-line chat text.
3. Posts list: Teams' response summary text (response_summary_N_users_mf), 12/16 brand, opens the post view.
4. Channel post/reply menus: secondary items in registry order (first 3 on the menu, rest under More actions), Report this message for others' messages; Share to Outlook on the channel id (bodyType SingleMessage in Threads channels).
5. Harness --channel-rows-test; unit test; live check beside Teams.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: AC #4 is met by TASK-0378 (PR #72, merged 2026-11-27): ended channel-meeting posts with the .NET zero date no longer get a calendar card (src/api/messages.rs, Teams' after-1970 rule, unit test). TASK-0373's agent saw the '-0001' card on a build from before that merge.

Research (2026-11-27): Teams 26304 bundles (linuxlt ~/teams-26304) and Teams on the web as OST Test 2 in a headless Chrome on linuxlt (testpc1/testpc2 Teams were being driven by other agents, so DOM measurements came from the web client, same code).
- Replies line: 733522 Fs, channels:response_summary_{1..3}_users_mf, e.g. 'Open {repliesCount} replies from {user1} and {user2}' (always 'replies'), shown when a post has more replies than the 3 shown; the count is every reply; repliers newest first (unique, up to 3 named, you as 'you'; the rest as ', and N others'); 12/16 regular #5B5FC7, 18 in, 12 down, a 41 px row; click opens the post view (L1 -> L2). Teams desktop on testpc2 showed 'you and OST Test 1' for the same post from a stale cache; web and the code give 'OST Test 1 and you', which OST shows.
- Menus: someone else's post: ... | Mark as unread, Share to Outlook, Translate | Report this message | More actions > Immersive Reader, apps. Reply: ... | Share to Outlook, Translate, Immersive Reader | Report this message | More actions > apps only. Own: Delete, no Report. Teams' Immersive Reader icon is Fluent read_aloud (was a book icon in OST, chats too).
- Reminders rows: a channel message's row is a Followed threads row (team picture radius 4, channel name, a reply's post subject 12/16 #424242 from activityContext.parentMessageSubject/Preview, then 20 px picture + 'Name: text' up to 2 lines, chip 5.3 under); chat rows' text wraps to 2 lines (chip 4 under); chips are Fluent badges: due brand tint (#E8EBFA, #C5CBFA edge, #4F52B2), upcoming outline (#FFFFFF, #E0E0E0 edge, #616161), completed green (#F1FAF1, #9FD89F edge, #0E700E, checkmark); icon 4 in, text 24 in.

Built: src/api/quick_views.rs (reminders carry a reply's post subject/preview, unit test channel_reminders_name_the_post_of_a_reply), QuickListView (channel rows, two-line chat text, chip styles, picture indent 28), ChannelPosts (Teams' replies line, opens the post view; ChannelWindow opens it in a thread window), MessageHost (channel secondary items in registry order, first 3 on the menu, the rest under More actions, disabled when empty; Report this message on others' posts/replies; Share to Outlook on the channel id, bodyType SingleMessage in Threads-layout channels; ChannelWindow/PostThread pass their channel id), read-aloud-20 icon, harness --channel-rows-test.

Live check (linuxlt, OST Test 2, General of OST Test Team, beside Teams web): replies line 'Open 4 replies from OST Test 1 and you' identical; post/reply/own-reply menus identical to Teams (OST adds Teams desktop's Open conversation in new window); Report dialog opened and cancelled (report_result stayed empty, nothing sent); Share to Outlook on the post made the channel draft, framed Outlook (initialize, appLoaded, success) and discarded it on close; Immersive Reader launched on the reply; Reminders rows (chat due, channel post upcoming, channel reply completed) match Teams' side by side. Test reminders set in Teams web were removed afterwards.

Not verified: the bodyType=SingleMessage draft in a Threads-layout channel; the bold replies line for unread replies (Teams bolds it when replies are new; OST has no per-reply unread state there); the totals use the replies OST has loaded, as before.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chat > Reminders shows a channel message's reminder as Teams does (channel, a reply's post subject, sender line, chips per state; chat text on two lines); the posts list's replies line reads 'Open N replies from …' and opens the post view; channel post and reply menus have Share to Outlook, Immersive Reader (Teams' read-aloud icon) and Report this message where Teams puts them. Checked live beside Teams web as OST Test 2 (--channel-rows-test); AC #4 was done by TASK-0378.
<!-- SECTION:FINAL_SUMMARY:END -->
