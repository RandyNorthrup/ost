---
id: TASK-0212
title: Events and meeting Notes leftovers as Teams
status: To Do
assignee: []
created_date: '2026-11-17T01:27:00Z'
updated_date: '2026-11-19T06:52:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0209 left (docs/spec/events.md, docs/spec/call-and-meeting-window.md):
- Events: co-organizer, presenter and invitee pickers; View audio recaps, Connect apps, Custom range filter, See more; card ··· items and the event page's other tabs; Edit details, Share, Preview, Publish, Duplicate, Save as template; rooms, description toolbar, time-zone picker, stage preview, All options, Manage apps; My events and template mapping checked against published events; Pin app synced where Teams keeps pinned apps.
- Meeting Notes: the shared-link path (untested live); making the notes in a Meet now (Teams claims collab leadership; in scheduled meetings Teams uses another service, not traced); the panel's ··· items other than Copy component and Open in Loop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Events' remaining pages, actions and pickers work as in Teams (publishing only to test accounts)
- [ ] #2 Meeting Notes opens or makes the notes in every kind of meeting as Teams, and its ··· menu matches
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Researched in Teams desktop 26304 on winpc (CDP: DOM + network, tokens redacted) and its bundles (copied to linuxlt ~/teams-26304): spec docs/spec/events.md "The rest" and app-host.md Meeting Notes.
- Events: Custom range / My events (regional query, Registered/Invited), chips, See more, Connect apps (ECS integrationsThirdParty), saved templates (eventTemplates: Schedule, Edit template, Delete), time zone (Teams' 140 zones, api::events_tz), room search with availability + Room options, description toolbar (FormatBar custom groups + RichText), co-organizer/presenter/invitee pickers (searchV2 flags as Teams), stage preview (Teams' sample videos), All options (meetingTemplates/details in MeetingOptionsDialog), Manage apps, save dialog invite cards, event page tabs (Overview, People & emails, Insights, Highlights), Preview, Edit details (PATCH), Share / success dialog (attendee card, isDiscoverable), Duplicate (POST duplicate), Save as template, Copy join details (scheduler views.html, resource 7557eb47-…), Pin app in Teams' pinned apps (+ app bar Pin/Unpin), template mapping per Teams (All hands = webinar, Ask me anything = town hall, access/registration/green room defaults), Meeting Recaps for View audio recaps.
- Meeting Notes: scheduled meetings now use Teams' collab object service first (reserveresource → make page → commitresource, hostClient TeamsInMeeting); More actions: Shared locations, Copy component, See who has access (Manage access), Open in Loop, Add to Loop workspace (loop.microsoft.com/p/<base64>).
- Live (OST Test 3, linuxlt): --events-test=full end to end (draft with OST Test 2 co-organizer, OST Test 1 presenter, OST Test Room; template; duplicate edited + published; pin/unpin synced; all cancelled/deleted); --call-notes-test (collab path committed) and --call-notes-meetnow (service path); --recaps-test. Cleanup: ost-test1's two winpc test events cancelled and their Canceled: entries removed; notes .loop files deleted.
<!-- SECTION:NOTES:END -->
