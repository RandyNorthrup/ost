---
id: TASK-0346
title: No 'Meeting started' banner for a channel Meet now
status: In Progress
assignee:
  - '@calls2'
created_date: '2026-11-27T05:47:00Z'
updated_date: '2026-11-27T07:38:00Z'
labels:
  - calls
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in wiki round 3 (row 446): a channel Meet now started by OST Test 3 gave OST Test 1 (a team member) no 'Meeting started' notification banner, which Teams shows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST matches Teams desktop when a team member starts a channel Meet now (Teams shows no Meeting started banner or activity for it), verified against Teams desktop on a test PC
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture what a team member receives when another member starts a channel Meet now (Teams web as OST Test 3 over CDP, Teams desktop on testpc1 as OST Test 1, meeting started by OST Test 2 on testpc2)
2. Compare with Teams desktop: banner, activity feed
3. Read Teams' meeting-started notification code for the rules
4. Make OST match, verify live
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26 22:09 and 22:12: OST Test 2 (Teams desktop, testpc2) started Meet now in OST Test Team > General twice.
- Teams desktop 26304 on testpc1 (OST Test 1, Available): no banner, no toast, no Activity entry, with Settings > Meetings > "Meet now start notifications" Off (its value) and again with it On (restored to Off afterwards). Teams on the web (OST Test 3) showed none either.
- What members receive: only chat-service messaging events on the channel thread (NewMessage/MessageUpdate of the Event/Call "callStarted" post, ThreadUpdate). No trouter notificationType push (no HuddleMeetingStart / MeetingStart) arrives for a channel meeting.
- Teams' code (527114 bundle, MeetingStartedNotificationService): toasts come only from HuddleMeetingStart pushes (group-chat Meet now, gated by huddleStartedNotification), MeetingStart pushes, and MeetingStartFromChatSvc, which requires conversationType ScheduledMeeting that is in your calendar in its time window with a passcode. A channel Meet now meets none of these, so Teams shows no banner.

- OST check 2026-11-27 07:33 UTC: OST (OST Test 1) running on linuxlt while OST Test 2 (Teams on the web) started Meet now in OST Test Team > General: OST received the channel's callStarted post pushes and showed no banner or activity, the same as Teams desktop. No code change needed: the reported gap was not Teams behavior.

- AC #1 (OST should show the banner) was removed: Teams desktop 26304 shows neither a banner nor an activity entry for a channel Meet now (tested twice on testpc1, also with Meet now start notifications on), so showing one would not match Teams. Replaced by the parity AC.
<!-- SECTION:NOTES:END -->
