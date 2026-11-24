---
id: TASK-0209
title: Events app and in-call Meeting Notes as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T22:37:00Z'
updated_date: '2026-11-17T01:27:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0038 (docs/spec/app-host.md):
- Events is not a web page in Teams: Teams draws it itself (Discover and Manage tabs, Create event) from the virtual-events API. OST's app bar still opens Teams on the web for it.
- The call window's Notes button gets or makes the meeting's notes through Teams' meeting-notes service and shows them as a Loop page (read from Teams' code, not captured live). OST's Loop host (TASK-0205) can show the page.
Immersive Reader on messages with cards also needs the card text added, as Teams does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Events opens natively in OST with Teams' Discover and Manage tabs and Create event, as in Teams
- [x] #2 The call window's Notes opens the meeting's notes as Teams does
- [x] #3 Immersive Reader includes a card's text as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (f5d4d2e, merged as 647946f); spec docs/spec/events.md.
- Events: native EventsView (Discover's three virtual-events queries, Manage's drafts / published / past, Filters, Pin app, Create event's templates and the New event form, save dialog, draft page, Cancel). Draft create and cancel checked live; re-checked Discover / Manage / Create / form on the merged build.
- Meeting Notes: MeetingNotesPane (360 px) tries the call's shared link, Teams' meeting-notes service, then making the notes, and shows the Loop page; checked live in a solo scheduled meeting (needed the calendar id from the meeting chat).
- Immersive Reader: card placeholders replaced with Teams' card text (matched Teams' captured chunk for OST TEST 168a).
- Test drafts, calendar entries, meeting and .loop files deleted; ost-test1 is in no leftover event group (checked its memberOf).
- Leftovers: TASK-0212.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Events, in-call Meeting Notes and Immersive Reader card text, as Teams.

- Events opens natively with Discover, Manage, Filters, Create event and the New event form, from the same virtual-events requests as Teams.
- The call window's Notes shows the meeting's Loop notes in Teams' side panel, got the way Teams gets them.
- Immersive Reader reads cards' text as Teams does.

Harness: --events-test, --call-notes-test, --embed-message. Follow-up TASK-0212.
<!-- SECTION:FINAL_SUMMARY:END -->
