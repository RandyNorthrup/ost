---
id: TASK-0184
title: Webinars and town halls as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-17T06:06:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams schedules and runs webinars and town halls (registration, presenters); OST has none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Webinars and town halls can be scheduled, joined and run as in Teams, where the tenant allows
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (0f8c9a9, merged as 749b449); spec docs/spec/town-halls-and-webinars.md.
- OST stopped sending Teams-web's blockPresenterJoinInEvents capability (Teams desktop doesn't), so it joins town halls as organizer or presenter. Call window: green room, Start meeting with confirmation, going live, End event, Not started / Live / Ended pill, Teams' town hall bar rules, Q&A pane, Bring on screen / Take off screen, the attendee welcome screen. Events app: Town hall form, Publish with Teams' dialogs, Join.
- Live: organizer joined in the green room, opened Q&A, started (the service confirmed live), ended for attendees and left. Town hall draft saved and cancelled from OST. Test events cancelled, calendar entries and the recording / notes files removed; no event group left.
- Attendee viewing, webinars and extras: TASK-0217.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Town halls as Teams for organizers and presenters: joining as Teams desktop does, the green room, going live, ending, Q&A and Bring on screen; Events app's Town hall form, Publish and Join.

Harness: --join-event (-qna, -start, -end), --events-test=townhall. Follow-up TASK-0217 (attendees, webinars live, extras).
<!-- SECTION:FINAL_SUMMARY:END -->
