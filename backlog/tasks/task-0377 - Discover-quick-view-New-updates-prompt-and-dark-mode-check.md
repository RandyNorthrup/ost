---
id: TASK-0377
title: 'Discover quick view: New updates prompt and dark mode check'
status: Done
assignee:
  - '@t377'
created_date: '2026-11-28T00:08:00Z'
updated_date: '2026-11-28T02:40:00Z'
labels:
  - desktop
  - chat
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0365 (PR #56): Teams' Discover feed shows a New updates prompt when new posts arrive; OST doesn't (how often Teams checks wasn't measured). Discover was also not checked in dark or high-contrast themes, and sending a reply from a Discover card wasn't tried live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Discover shows Teams' New updates prompt at Teams' refresh rule (measured and documented)
- [x] #2 Discover matches Teams in dark and high-contrast themes
- [x] #3 Replying from a Discover card works as in Teams (checked live with test accounts)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams 26304 discover-surface bundles and worker for the New updates rule; capture Teams web (OST Test 2) worker requests with Discover open to time the polls.
2. Build the poll (ECS discoverPollingInterval, 5 min), first-post comparison and Teams' New updates button in DiscoverView.
3. Measure Teams web Discover in light, dark and High contrast (computed styles, Fluent tokens) and fix OST's colours.
4. Reply from a Discover card live: Teams web (OST Test 2) and OST (test account) in OST Test Team, deleting each reply.
5. Harness --discover-poll-test / --discover-reply=, spec section, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: replying from a Discover card (DiscoverView.qml replyInput/sendReply, TASK-0365 PR #56) and theme-token colours are built but not checked live; the New updates prompt is left.

- Teams rule (26304 bundles + Teams web as OST Test 2, worker requests captured over CDP): with Discover open, GET …/discover?pageSize=7&continuationToken=null (TeamsFeed_Reload) every discoverPollingInterval (5 min; measured +5:00 and +10:00 after opening, nothing between); a changed first post sets New updates and stops polling until used. 9 h background sync (dataSyncIntervalTime) and start-up sync only set the flag, which opening Discover clears. Spec: docs/spec/chat-list-and-header.md §5.6.13.
- OST: poll timer from ECS (300000), api::discover::feed_poll, Teams' button (primary, ArrowSync, 10 below the header, 400 ms fade), refetch over the cards + announcement. Live on testpc2 (OST Test 3): --discover-poll-test showed and cleared it; --discover-timer: the timer polled once at +5:00.
- Themes measured on Teams web in light/dark/High contrast (computed styles + Fluent tokens) and fixed: card NeutralBackground1 (#292929 dark), card lines, header line, Yes/No, Reply in thread HC hover, secondary buttons, reply box. OST shots in dark and HC match.
- Reply: Teams web (OST Test 2, OST Test Team › OST threads test) sent and deleted; OST (OST Test 3, --discover-reply on testpc1, OST Test Team › General) sent, shown, deleted (server reports deleted). Tombstone + Undo kept as Teams; focus back to Reply in thread.
- Not done: Teams' in-card composer toolbar (Format/Emoji/Attach/Loop/+); Teams' button after a genuinely new post was not seen (only at start-up).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Discover now has Teams' New updates prompt, timed by Teams' measured rule, matches Teams in dark and High contrast, and replying from a card was checked live.

- New updates: while Discover is open OST asks for the first page every discoverPollingInterval (ECS, 5 min; Teams measured at +5:00/+10:00, pageSize=7, TeamsFeed_Reload). A changed first post shows Teams' button (Fluent primary, ArrowSync, centred 10 below the header, 400 ms fade); using it scrolls up, refetches over the cards and announces the update.
- Themes: card fill, card and header lines, Yes/No, Reply in thread's High contrast hover, secondary buttons and the reply box use Teams' measured light/dark/HC values.
- Replies: focus returns to Reply in thread after sending; a reply deleted here stays as Teams' tombstone with Undo (tombstone text in the normal colour).
- Spec §5.6.13; harness --discover-poll-test, --discover-timer, --discover-reply=TEXT; unit test for the poll URL.

Not built: Teams' full composer toolbar in the card's reply box.
<!-- SECTION:FINAL_SUMMARY:END -->
