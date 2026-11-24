---
id: TASK-0108
title: Channel meeting posts as Teams (live meeting card with Join, ended summary)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T04:55:00Z'
updated_date: '2026-11-11T07:22:00Z'
labels:
  - meetings
  - channels
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams shows a meeting started in a channel (Meet now, or a scheduled channel meeting) as a post: while live, a card with the meeting title, who is in it and Join; once ended, its summary (duration, recap) with the post's replies. OST drops these posts from the channel, so a channel meeting can't be seen or joined from OST.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A live channel meeting shows as Teams' card in the channel with its title, participants and Join, measured on winpc
- [x] #2 Join from the card joins that meeting (verified live with the second test account)
- [x] #3 An ended channel meeting shows Teams' ended post with its duration, and replies stay under it
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channel meetings now show in a channel's posts as Teams draws them (measured on winpc 2026-11-10).

- The meeting's callStarted event is the post (author resolved by MRI via users/fetchShortProfile), subject = meeting title or `Meeting in "<channel>"`, "… ended" once over; rejoins (linked roots) and call events fold into it.
- Live: Teams' banner (#333357, video tile, title, running mm:ss, who's in it from the watched conversation, Join). Join opens the pre-join screen and joins that meeting (verified live: OST Test 1 joined OST Test 2's channel meeting from the post).
- Ended: "See details" opens Teams' post view in the pane (PostThread.qml, shared with the pop-out thread window) with the call-end rows.
- New: MessageView meeting fields, api::directory::short_profiles, channel meeting join links, spec docs/spec/channel-meetings.md.

Follow-up: TASK-0109 (Attendance card).
Tests: 427 lib tests pass; live runs on linuxlt (--open-channel[-join|-details]).
<!-- SECTION:FINAL_SUMMARY:END -->
