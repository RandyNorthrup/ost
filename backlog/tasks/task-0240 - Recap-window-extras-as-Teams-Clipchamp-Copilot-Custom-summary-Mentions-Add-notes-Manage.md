---
id: TASK-0240
title: >-
  Recap window extras as Teams: Clipchamp, Copilot, Custom summary, Mentions,
  Add notes, Manage
status: In Progress
assignee: []
created_date: '2026-11-20T22:51:00Z'
updated_date: '2026-11-21T07:15:00Z'
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
- [x] #1 The recap window has Teams' Open in Clipchamp, Copilot and Manage buttons and they act as in Teams
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

- 2026-11-20 (chatC), built and checked live on linuxlt as ost-test1 (`--recap-window-test=extras`, OST TEST 217 town hall 2):
  - Open in Clipchamp: the recording's page with web=1 and Teams' referrer, opened in the browser.
  - Copilot: shown for the Copilot licence. The pane loads the M365 Copilot app (launch_recap: entryPoint Recap, ECS meetingRecap cmm id, sessionType Recap, vroomId).
  - Manage over the player (dark button and dark menu): Download (driveDownload); Expires in 118 days (the same as Teams) ▸ Extend by 60 days / Remove expiration (SetExpirationDate). It is offered for your own recordings.
  - Custom summary: Teams' cards (Create template, Speaker summary, Executive report, Project update, your OneDrive templates; 2/3/4 per page with Next/Previous), the empty state, and Copilot's m365Copilot/Chat summary with Teams' body. For this meeting Copilot answers 500, so OST shows Teams' "We couldn't load custom AI summary".
  - Mentions: the MeetingCatchUp call. It answers 400 for this meeting, so OST shows Teams' page: warning illustration, "We couldn't load mentions", "Something went wrong. Try again." This matches what Teams shows on winpc for the same meeting.
  - Notes: Teams' outlined Add notes (Loop icon). It runs getOrCreateMeetingNotes, then shows the Loop notes.
  - The 4th pill is Mentions from the thumbnail and Transcript from the chip, as in Teams.
- Still open:
  - Create template's editor (Describe your summary format / Preview / Save and Apply).
  - A meeting with a working transcript, to see Mentions and Custom summary results.
  - Add notes was not pressed live; it would create notes in the meeting.
  - The player is OneDrive's; it shows "Open in browser", which Teams' streamembed doesn't have.

- 2026-11-20 merged: Open in Clipchamp, Copilot and Manage (Download, Expires in 118 days, Extend / Remove expiration) checked live. AC2 open: Custom summary got Copilot's server error for this meeting; Mentions shows Teams' own error; Add notes not pressed; Create template editor not built.

- 2026-11-20 (chatE): test meeting "OST TEST 240 recap meeting" (organizer ost-test1, OST Test 3 invited; calendar event via examples/create_event), run on linuxlt: ost-test1 in OST with `--join-copilot` (transcript started, Copilot pane), OST Test 3 in OST speaking Piper speech through a PipeWire virtual mic (OST_MIC_DEVICE), about 6 minutes; "Meeting ended: 6m 27s".
  - Teams on winpc for it: recap card "1 speaker, 3 tasks, Transcript"; recap window with Shared files (Attendance), pills Notes / AI summary / Custom summary (New) / Mentions / Transcript, header Audio recap / Share / Open in Clipchamp. AI summary is written ("Project Plan And Budget Updates…", "Launch Review Rescheduling…"). Mentions: "We didn't find mentions of you". Custom summary cards: Create template, Speaker summary, Executive report (no Project update); Speaker summary returns a summary under the speaker "OST".
  - OST (`--recap-window-test=extras --recap-chat=OST~TEST~240`, the harness now waits for that chat's own messages): Mentions answers 400 and Speaker summary errors, because OST sends the recording's item as the catch-up entity and vroomId, and this meeting has only a transcript. Being fixed with the Create template editor (separate branch).
<!-- SECTION:NOTES:END -->
