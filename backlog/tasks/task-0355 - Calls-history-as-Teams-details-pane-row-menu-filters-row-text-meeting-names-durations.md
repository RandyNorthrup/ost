---
id: TASK-0355
title: >-
  Calls history as Teams: details pane, row menu, filters, row text, meeting
  names, durations
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-27T17:32:00Z'
updated_date: '2026-11-27T18:16:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope B), which compared Teams desktop on winpc (ost-test1, read over CDP) with OST main 7d1c3a38 on linuxlt. Each acceptance criterion is one verified gap. The full entry for each (what Teams does, what OST does, severity, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditB.md, under its B-number, with screenshots in audit/shots-B/ (t-* Teams, o-* OST).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 B-06: Calls app: clicking a history row opens a Details pane, as Teams desktop does it, checked side by side
- [ ] #2 B-07: Calls app: row hover shows ··· (Chat, Remove from view, Report call), as Teams desktop does it, checked side by side
- [ ] #3 B-08: Calls app: History "Filter by name or number" and the Voicemail filter, as Teams desktop does it, checked side by side
- [ ] #4 B-09: Calls app: history row text, duration placement and dates, as Teams desktop does it, checked side by side
- [ ] #5 B-13: Calls history: meeting calls named by a person, and extra "Unknown" rows, as Teams desktop does it, checked side by side
- [ ] #6 B-22: Calls history: durations are rounded, Teams truncates, as Teams desktop does it, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Research (Teams 26304 on winpc as ost-test1, CDP read-only + its JS bundles):
- List rows come from 48:calllogs; Teams drops rows by its reduceCallHistoryMessages filters (isOutgoingCallWithNoTarget: outgoing, no target, no other participants; deleted (isDeleted); screen-sharing sessions; call-park bot targets) and lists only call-log Text messages (personal-attendant logs are merged, not rows).
- Group call (MultiParty with a thread or >1 other participants): named by the thread's topic (groupCall.title), else the other participants (first names, '+N' past the pane-width limit). Others: the resolved person (target if you placed it, else originator).
- Second line: Outgoing / Incoming / Missed incoming, '... from <originator>' for group calls. Duration under the time, floor of (end-connect), hidden under 1 s and on missed calls. Dates: time today, Yesterday, weekday after start of day 8 days ago, else short date with year.
- Unread missed: missedCall activity (matched by startTime ms) unread: bold + red dot; opening Details marks it read.
- Hover: '···' (plus Call on 1:1 rows); menu: Call back, Chat, Remove from view, Add to speed dial, Add contact, Report call (group rows: Chat, Remove from view, Report call). Remove from view = PUT call-log property with isDeleted:true. Report call = 'Report a concern' dialog, POST middle tier beta/reports.
- Click: Details pane (avatar(s), name, chat/org/video/call, quick message, the call's timeline: date, direction+time, Made/Answered by you, Call ended, Total call time).
- Filter button: 'Filter by name or number' (matches the resolved person's name), '···' type menu (Outgoing, Incoming, Missed, Voicemail) shown as a removable chip, X closes. All pill menu: Missed, Incoming, Outgoing, Voicemail.
Plan: extend api::chat call records + filters + tests; backend enrichment (names/given names, thread topics, unread missed); remove/report/mark-read calls; CallsView rows, menu, details pane, filter header; verify side by side on linuxlt vs winpc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
B-13 cause (from the call records): OST listed every 48:calllogs message and named each by 'whichever end isn't me'. Teams instead (a) drops rows by its reduceCallHistoryMessages filters, here isOutgoingCallWithNoTarget: the four 'Unknown' rows are Meet now calls where ost-test1 was alone (outgoing, target null, participantList only you), and (b) names a group call (multiParty in a chat) by the chat's topic (groupCall.title, e.g. 'OST TEST 348 ost' is a group chat with that topic), else its other people; the 'OST Test 1' rows were calls whose log target is you, the 'OST Test 3' ones missed calls in those chats. B-22: Teams' durationInMs is end-connect in ms and the label floors the seconds; OST rounded.
<!-- SECTION:NOTES:END -->
