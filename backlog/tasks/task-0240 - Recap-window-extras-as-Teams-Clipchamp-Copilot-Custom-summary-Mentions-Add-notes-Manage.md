---
id: TASK-0240
title: >-
  Recap window extras as Teams: Clipchamp, Copilot, Custom summary, Mentions,
  Add notes, Manage
status: In Progress
assignee: []
created_date: '2026-11-20T22:51:00Z'
updated_date: '2026-11-21T08:26:00Z'
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

- 2026-11-20 (chatE3), Custom summary's Create template, from Teams 26304 (customize-notes panel, 209818/633679/855033, the shared worker's template resolvers):
  - "Describe your summary format" (RecapTemplateEditor.qml): Teams' modal (min(100 %, 1080) x 80 %, max 704), the editor box with Preview inside, the blank message, Suggestions (three pills that replace the text; 3/2 columns by window width with ‹ › in two), the preview panel (default page, Teams' loading card, the Markdown under "AI-generated content may be incorrect", or "We couldn't load custom AI summary"), Discard / Save and Apply ("Saving your template...", stacked below 480).
  - Preview sends 633679's recap prompt with the trimmed text through the same m365Copilot/Chat call; a saved template's text is read again by id and put in the same prompt, as Teams does (before, OST sent the text JSON-quoted). The answer is cleaned as 855033 does (api::recaps::clean_summary).
  - "Save as a template" (RecapTemplateNameDialog.qml): Teams' checks as you type, Save off while there's a message. PUT …/Recordings/CustomSummaryTemplates/{name}:/content (201 only), then the list is fetched again and the new one chosen. Edit saves in place (PUT content). Rename: PATCH {name}. Delete: DELETE (204), and the remembered choice is forgotten.
  - The cards are in Teams' order (Create template, yours newest first, then the three built-ins). The chosen card is NeutralBackground1Selected with a brand checkmark; hovering yours shows ··· with Edit / Share (copies the text; toast "Prompt copied") / Rename / Delete (red). The chosen template is remembered per meeting chat (setting recapCustomSummaryTemplates), moved to the front the first time, and summarised.
  - The recap window's toasts (Share, and Manage's expiration) were never shown: backend.toast isn't invokable. They now go to the app's toast.
- Checked live on linuxlt as ost-test1 (--recap-window-test=template, OST TEST 217 town hall 2): the blank message; a suggestion; Preview sent (Copilot answers 500 for this meeting, so Teams' error page shows); a bad name refused; "OST TEST 240 template" saved (201) and chosen; renamed; Edit read back the saved text and saved the new one; Share copied the edited text; deleted (204), leaving no template and no remembered choice.
- Still open: a meeting whose Copilot summary works, to see a real preview and summary.

- 2026-11-21 (chatE3), a meeting with a transcript and no recording ("OST TEST 240 recap meeting"), from Teams 26304's code:
  - Teams' recap id (597421 Tv) is SPO_{base64url of the drive's site,web,library GUIDs}_{itemId}, made from the recording's file, or from the latest TranscriptV2 resource's file when there is no recording. It is the catch-up EntityId (Mentions) and Copilot's vroomId. OST sent the bare item id, which is empty without a recording (400). Now: api::recaps::canonical_recap_id, RecapRef.recap_id, and the transcript's file read from the meeting artifacts contents.
  - Custom summary goes the way Teams sends it with today's ECS (enableCustomSummaryStreaming and enableMeetingRecapCustomizedNotesCatalystEndpoint on): a SignalR stream on wss://substrate.office.com/m365Copilot/Chathub/{oid}@{tid}, Teams' Catalyst variants and query, then the chat call with the message annotated as the meeting. With enableCustomSummaryCurrentCallGrounding there is no iCalUID and the canvas is RecapCall. Speaker summary and Executive report send 633679's OM/TJ prompts with the summary's language from the catch-up, and Project update is hidden (hideCustomSummaryProjectUpdate). The old m365Copilot/Chat POST answered 500.
  - Mentions' empty pages show Teams' tag illustration (the warning only on an error).
- Checked live on linuxlt (--recap-window-test=extras --recap-chat=OST~TEST~240): Mentions shows "We didn't find mentions of you", the same as Teams on winpc. Speaker summary returns a summary (1661 characters, logged; before, the server error). The cards are Create template, Speaker summary, Executive report, as in Teams.
- Still open for this meeting: Teams' band (Audio recap, Open in Clipchamp) and the Transcript pill, which come from the transcript's file, not a recording.
<!-- SECTION:NOTES:END -->
