---
id: TASK-0327
title: Meeting Q&A tab doesn't load
status: Done
assignee:
  - '@meet'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T16:10:00Z'
labels:
  - bug
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The Q&A tab in meetings (town halls, webinars and meetings with Q&A on) doesn't load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Q&A loads and works (ask, reply, upvote, moderate) as in Teams, verified live
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Turn Q&A on in a test meeting; compare Teams on the web Q&A frames (chat tab, call side pane) with OST
2. Fix the differences
3. Verify ask, reply, upvote and moderate live between OST and Teams
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26: Q&A turned on in "OST TEST 324 meet" (Meeting options in Teams on the web). Engage's Q&A works in this tenant (Business Basic includes Viva Engage); no licence gap.
- Cause of the wiki "This page isn't loading right now": the account used OST's device-code session, which can't mint NAA tokens for embedded apps (log: NAA token for 00bf137d from https://web.yammer.com failed: "Embedded apps' tokens need the browser sign-in"). With the browser sign-in (OST Test 3 after its one interactive sign-in, ost-test1) the chat tab loads.
- Differences from Teams on the web fixed: the call's side pane URL lacked callId and entryPoint=sidePanel; the bar's Q&A came only from town hall / webinar facts (event_json returned nothing for a plain meeting), so a meeting with Q&A on had no Q&A button (Teams: after Chat); someone let in from the lobby never got the meeting's facts in the call window (admission applied them but didn't publish).
- Verified live: OST Test 3 asked in OST's chat tab; Teams on the web (OST Test 2) saw it, upvoted and replied; OST showed the vote and the reply; OST's reply showed in Teams; ost-test1 as organizer in OST marked Teams' reply Best answer (organizer view with settings and archive). Call side pane in OST: Engage's side-panel view, URL now `…&meetingTenantId=…&callId=…&entryPoint=sidePanel&appSessionId=…`; the organizer's bar shows Chat, Q&A, People…
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting Q&A loads and works in OST. Its Teams differences are fixed.

Cause: the wiki capture used an account still on a device-code session. Embedded apps get NAA tokens only through the browser sign-in, so Engage (client 00bf137d) got none and showed "This page isn't loading right now". With the browser sign-in, OST's Q&A tab works. No licence gap: Business Basic includes Viva Engage. Comparing with Teams on the web found three gaps:
- The call's side pane URL lacked callId and entryPoint=sidePanel.
- The bar offered Q&A only in town halls and webinars. Teams shows it after Chat in any meeting with Q&A on.
- Anyone let in from the lobby never got the meeting's facts (Q&A, and an event's bar) in the call window.

Changes:
- CallWindow.qnaUrl adds callId (Backend.currentCallId) and entryPoint=sidePanel.
- event_json returns {"qna": true} for a plain meeting with Q&A on, so the bar shows Q&A after Chat.
- Lobby admission now publishes the meeting's event facts to the call window.
- Spec: app-host.md (Meeting Q&A).

Live checks (2026-11-26):
- OST Test 3 asked a question in OST's chat tab. Teams on the web (OST Test 2) saw it, upvoted it and replied; OST showed the vote and the reply. OST's reply showed in Teams.
- ost-test1 as organizer in OST marked Teams' reply Best answer.
- In OST's call, the side pane loads with Teams' URL. The bar shows Chat, Q&A, People… for the organizer, and also for OST Test 3 after being let in from the lobby.

PR #16.
<!-- SECTION:FINAL_SUMMARY:END -->
