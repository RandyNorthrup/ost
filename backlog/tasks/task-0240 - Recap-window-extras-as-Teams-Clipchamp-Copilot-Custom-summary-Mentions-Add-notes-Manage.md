---
id: TASK-0240
title: >-
  Recap window extras as Teams: Clipchamp, Copilot, Custom summary, Mentions,
  Add notes, Manage
status: To Do
assignee: []
created_date: '2026-11-20T22:51:00Z'
updated_date: '2026-11-21T01:18:00Z'
labels:
  - desktop
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0098 built Teams' recap pop-out (player, Speakers/Topics/Chapters, Shared files, Transcript/AI summary tabs, Share). Still missing versus Teams: Open in Clipchamp and Copilot buttons, the Custom summary and Mentions tabs, Notes' Add notes, and Teams' Manage button (OST plays through OneDrive's player and shows Open in browser).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The recap window has Teams' Open in Clipchamp, Copilot and Manage buttons and they act as in Teams
- [ ] #2 Custom summary, Mentions and Notes' Add notes work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chatC), from Teams 26304 (mostly module 991291; requests in the shared worker):
  - Open in Clipchamp (recap-open-in-stream-button, 169.8 at 965.3, 101): the label MeetingRecap.enableOpenInClipchamp gives "Watch in browser". It runs host.open(webUrl + "?web=1" + referrer=Teams.TEAMS-ELECTRON & referrerScenario=RecapOpenInStreamButton.view), which opens the browser.
  - Copilot (recap-copilot-button, 96.2): shown for Copilot licences. It toggles the recap's Copilot info pane: the Microsoft 365 Copilot app (bizChat) with entryPoint "Recap" ("RecapCall" for calls), cmm id ECS Copilot.copilotEntryPointsCMMIds.meetingRecap, and the meeting context with sessionType Recap and vroomId.
  - Manage (Teams' own button over the player, 117.6 x 31.3, 12 in from the player's top-right; dark, with a gear and a chevron) opens a dark menu:
    - Download (native downloadFile).
    - Expires in {n} days ▸ Extend by 60 days / Remove expiration. These call `POST {site}/_api/web/GetFileByServerRelativePath(DecodedUrl=@url)/SetExpirationDate?@url='{path}'` with {expirationDate}. Toasts: "Expiration date updated successfully." / "Failed to update expiration date. Please try again."
  - Custom summary:
    - Cards in pages: 4 when the pane is 948 wide or more, 3 at 480–947, 2 below. Create template comes first, then Speaker summary, Executive report, Project update and your own templates (OneDrive Recordings/CustomSummaryTemplates). Next/Previous templates arrows (25 x 25).
    - Empty state: meeting-notes illustration (192) and "Pick a template or create your own" (16/700).
    - Summary: `POST substrate.office.com/m365Copilot/Chat?scenario=teamsmeetingrecap&variants=…`. The message is the template key (SpeakersBasedRecap / ExecutiveSummary / ProjectSummary), or 209818's recap prompt with your template put in. EnterpriseSearch carries the meeting (callId, organizerId, threadId, iCalUid, sessionType, canvasType "Unknown", vroomId). The token audience is substrate /sydney.
  - Mentions: substrate recommendations MeetingCatchUp.MeetingRecap. On winpc, for OST TEST 217 town hall 2, Teams shows warning-l-standard (192), "We couldn't load mentions" and "Something went wrong. Try again."
  - Notes: "Add meeting notes for everyone" / "Anyone can contribute to the notes, anytime." with an outlined Add notes button (124.4 x 31.3, the 20 px Loop icon, 14/600 #242424). It calls the meeting-notes service getOrCreateMeetingNotes, then shows the Loop notes.
  - Opened from the thumbnail, the 4th pill is Mentions; opened from the Transcript chip, it is Transcript. The other one goes under "Show 1 more item".
  - AI summary has Copy all (32 x 31.3 at the right of the "AI-generated content may be incorrect" row). The left card has Collapse panel (32 x 32) at its bottom right.
<!-- SECTION:NOTES:END -->
