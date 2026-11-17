---
id: TASK-0217
title: Town hall attendees, webinars and event extras as Teams
status: To Do
assignee: []
created_date: '2026-11-17T06:06:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0184 left (docs/spec/town-halls-and-webinars.md):
- Town hall attendees: Teams streams the event from a service bot in the meeting and plays it in its own player; OST's attendee join gets no answer. The service bot ("s04-prdnoamcompsvc") shows on OST's stage and in People; Teams' rule for hiding it isn't traced.
- Webinars run live; OST's own Publish and Join on the event page; the attendee staging screen and post-end alert live; Bring on screen with a second presenter.
- Not built: "On with preview", Preview as attendee and Join as Organizer / Presenter, Calendar > New > Webinar / Town hall, Copy embed code, Show event in Events app, the published card's Live badge, Join and share; the Start / End buttons' and Live pill's measured styling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Town hall attendees watch the event in OST as in Teams, and the service bot is hidden as Teams hides it
- [ ] #2 Webinars are scheduled, joined and run in OST, checked live
- [ ] #3 The event extras listed above work and look as in Teams
<!-- AC:END -->
