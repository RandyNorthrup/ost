---
id: TASK-0212
title: Events and meeting Notes leftovers as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-17T01:27:00Z'
updated_date: '2026-11-21T03:02:00Z'
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

- Merged 9dc657f/95bad95 onto desktop/foundation (2026-11-19), conflicts with TASK-0217 resolved keeping both (one Share/published dialog; Live and "in N mins" badges; typed people lists). 772 lib + 29 desktop tests passed; live smoke on test3: --events-test=full, --call-notes-test, --events-test=townhall.
- Open: Manage immersive collections, editing email templates, Edit event banner, Highlights with a recording; Meeting Notes shared-link path live; Room options attendee viewing on the wire; Manage apps target; Generate audio recap; Audio recaps empty-state image; My events with real data; leftover Canceled: copies in ost-test1/test2 calendars.

- 2026-11-19 research (Teams 26304 bundles): Manage immersive collections = card gated by ECS enableImmersiveContentManagementInMeetApp + teamsEventsPolicy.immersiveEvents; list = Graph me/memberOf filtered teams.immersive (ConsistencyLevel eventual); worlds service eur.worlds.mesh.cloud.microsoft (resource 3016d0ce-…) /v3.0/collections POST {DisplayName, Description}, GET {collection, privileges, status}, PATCH, DELETE, /owners, /owners/remove, /members {userIds}, /members/remove.
- Email templates: GET events/{id}/emailtemplates (+/{templateId}), PATCH {subject, body, senderName[, sendTimeInterval]}; Edit only with teamsEventsPolicy.allowEmailEditing Enabled; tokens {{eventName}} etc.; reminder timing dialog.
- Edit event banner: Branding dialog (cover 3:1 crop, logo 1:1, theme colours); PATCH events/{id}/theme {primaryColor}, /theme/promo and /theme/logo {imageId, image: data URL} with If-Match eTag + x-skypetoken; PNG/JPG max 5 MB.

- 2026-11-19 winpc (Teams 26304.1207, CDP read + test-only clicks): email Edit dialog (fields, tokens eventName/dateTime/eventDescription/eventOrganization, Personalization menu), Branding dialog, immersive collections page (retirement banner + empty state), Audio recaps empty picture podcast/no-podcast.png 128, Generate audio recap dialog (Style Executive/Newscast/Casual, Language, chips, calendar-three-people empty state), Attendees picture v2/people-l-standard.svg 128, Drafts empty text, Manage apps (webinar link; town hall lists Custom Streaming / AI Producer with Add - not in the 26304 bundles). Made draft "OST TEST 212 room options" (OST Test Room, Attendee viewing) on winpc to read back; to cancel with --events-test=uninvite. Page requests run in a worker, so the wire capture used the service read-back.
- Built (uncommitted yet): email rows/editor/timing, Branding dialog + theme PATCHes, immersive collections pages (api::immersive), Generate audio recap dialog, Manage apps -> meeting details, harness --events-test=invite|myevents|uninvite|calclean|emails|branding|collections, --join-notes.

- Live 2026-11-19 (linuxlt): "OST TEST 212 invite 02:26" published by ost-test1 with OST Test 3 as attendee (Specific people); as OST Test 3, My events listed it (the regional Registered/Invited query answers with it; Live badge, Join) - also fixed Discover never drawing its lists (a Repeater hands nested arrays as sequences). Emails: rows from the service (Event invite, Event recording available), Edit loaded subject {{eventName}}, sender, body with token chips; Save PATCH answered with the template; Preview drawn. Branding: Teal + a 1200x400 PNG cropped -> PATCH theme (primaryColor #9EE5DE) and theme/promo (new imageId), banner shown on Overview and in My events. Immersive collections (OST Test 3): created "OST TEST 212 collection" (worlds service, Provisioning -> Succeeded), added OST Test 2 (Graph members show it), deleted; Manage card and page per ECS/policy (both on). Meeting Notes, two people (ost-test1 Meet now + OST Test 3 joining): OST Test 3 opened the same notes page live, but both got it from the meeting-notes service, so the shared link wasn't exercised; reordered the Meet now path to Teams' (leader claim, then share) - retest pending. test2 calendar: 11 "Canceled: OST TEST 212" entries removed.

- Final 2026-11-19: Meet now notes reordered to Teams' way (claim first) - the tenant refuses the claim (updateMeetingStates 400) for Calendar's Meet now, so both people got the service's notes again; the shared-link reception is still unexercised live. Email Save now sends clean HTML (no chip shading, indentation collapsed). Room options: the winpc draft read back through OST with OST Test Room as an attendee (AttendeeViewing). Cleanup: "OST TEST 212 invite" and "room options" cancelled; Canceled: entries removed from ost-test1 (7+2), OST Test 2 (11), OST Test 3 (3); two test collections deleted (soft-deleted M365 groups); Events unpinned again for ost-test1 (the save dialog had pinned it). 776 lib tests pass.
- Open: Highlights with a recording; town hall Manage apps (Custom Streaming / AI Producer, not in the 26304 bundles); Generate audio recap's AugLoop submit; Meeting Notes shared-link path live.

- Merged 4a78253 (2026-11-19): email template edit, Edit event banner, immersive collections, My events with real data, Discover lists fix, Room options attendee viewing confirmed, Manage apps → meeting details, Generate audio recap dialog, images. Open: Highlights with a recording, a town hall's Manage apps list (Custom Streaming, AI Producer), the Generate submission, the Meeting Notes shared-link path (tenant returns 400 to the claim).

- 2026-11-20 (teamsB, with TASK-0238): Events' Pin app writes Teams' pinned apps (beta/users/apps/pinned), and OST's app bar now reloads from them when it changes, so Events appears or leaves the bar in OST and in Teams alike.
- Still open (not attempted this round): Highlights with a recording; a town hall's Manage apps list (Custom Streaming, AI Producer, not in the 26304 bundles); the Generate audio recap AugLoop submission; the Meeting Notes shared-link path live (the tenant answers 400 to the Meet now leader claim); the scheduled-meeting notes service; the notes panel's other ··· items.

- 2026-11-20 round 2 (linuxlt, OST Test 2 organizer --call-notes-test --call-notes-stay, OST Test 3 joining by link with --join-notes; the join link is now logged): a scheduled meeting needs no leader claim (that's the Meet now path): the organizer's notes go through Teams' collab object service (reserve → make the Loop page in OneDrive Meetings → commit), and that works: run 1 (solo) and runs 2–3 made 'OST TEST 212 notes OST.loop', shared it and showed the page; the ··· menu listed Shared locations, Copy component, See who has access, Open in Loop, Add to Loop workspace.
- Second person: OST Test 3 joined (runs 3 and 4) and the collab object answered them 'pending / someone else is making them' even after the organizer had committed; in run 4 the organizer itself got back the location committed in run 3's meeting (a file deleted by that run's cleanup → ODSP 404). So the collab object keys these test meetings so that one meeting's notes show up in the next, and the second person never got the committed link. Likely cause to check next: what OST sends as the meeting's keys (externalEntityKey / seriesExternalEntityKey from the event's iCalUid, threadId) for each new event, compared with Teams' reserve request on winpc.
- Still open: the second person's view in a scheduled meeting (above), the Meet now claim 400 (unchanged; Meet now only), Highlights with a recording, a town hall's Manage apps list, the Generate audio recap submit. No tenant settings were changed. All test meetings and their notes files were deleted.
<!-- SECTION:NOTES:END -->
