---
id: TASK-0098
title: Meeting recap card on a meeting's ended row, as Teams
status: To Do
assignee: []
created_date: '2026-11-10T17:18:00Z'
updated_date: '2026-11-20T22:06:00Z'
labels:
  - desktop
  - messages
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams adds a recap card under a meeting's "Meeting ended: {duration}" row. Seen on winpc on 2026-11-10 in OST calendar test (Sunday 8:53 PM), it holds:
- the meeting title (bold) and its date range ("Saturday, November 7, 2026 7:24 PM - Sunday, November 8 8:53 PM");
- a Share icon and a brand "View recap" button;
- a "Content" section with a "Transcript" chip;
- a recording thumbnail labelled "5 recordings", with "Set to expire" under it.

It is built from the call-end XML (MeetingDetails) plus the recording messages folded into it (docs/spec/message-types.md §20). Teams' UI module 174639 hasn't been traced yet. "View recap" opens the meeting's Recap tab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A meeting chat's ended row shows the recap card with Teams' layout, title, date range, transcript chip and recordings thumbnail/count
- [ ] #2 View recap, the transcript chip and the thumbnail open what Teams opens
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chat agent): measured on winpc ("Event group: OST TEST 217 town hall 2", the 50m 5s town hall with a recording and transcript): 646 x 162 card 14 under the ended row, white, radius 8, shadow 0 0 2 .12 / 0 2 4 .14, padding 14 20 0; subject 16/20 600 #242424 and the date range 12 #616161 ("Wednesday, November 18, 2026 8:40 PM - 9:40 PM"); Share (32 x 32, recap-share-button) and the recap button ("Highlights" split for the event's organizer: recapSplitPrimaryButton 114.2 x 32 brand + a 20 x 32 chevron); a line; "Content" 12/600 #616161; the Transcript chip (96 x 32, 0.67 #F0F0F0, radius 4); the recording thumbnail (108 x 60, radius 6) with its "47m 40s" pill (rgba(0,0,0,.4), radius 2, 12 px white) and "Expires in 119 days" (10 px #616161, a 10 px clock). Meeting chats without recordings or transcript (OST calendar test) show only the Attendance cards.
- Teams' code (meeting-recap-chiclet-app, 983864/102674; research notes in the scratchpad recap-research.md): shown when the call's recording/transcript messages fold into its ended row (by callId); title = a group chat's topic, else the call-end XML's Subject; button "View recap" (messaging:k1tc0zdrt) or for Split/Menu styles "Recap" (extensibility:k5hpfls5x) with Audio/Video recap; town hall / webinar organizers see "Highlights" (meetingRecap:kc40v5p0g) with Highlights / Recap; "Content" kaeryhl69; Transcript artifactsPlatform:k1tttxcnb; no content kcorsfr1k; "{n} recordings" kc0ilq7jw; "Saving..." ka97b62m1; expiry kanosvkvh_mf / "No expiration" k9n0fpa7u / "Set to expire" k7mpmiird. View recap, the thumbnail and the chip open the meeting's Recap (intelligentRecap with defaultRightTab); Highlights opens the event's Highlights in Events; Share opens recap sharing.
- Built: messages::attach_recaps (Recap / RecapRecording on the ended row, from the page's recording and transcript messages and the call-end XML), the thumbnails cached (localize_recap), RecapCard.qml in place of the attendance card; View recap / chip / thumbnail open the chat's Recap tab.

- 2026-11-20 (chatB), measured on winpc (Event group: OST TEST 217 town hall 2):
  - Transcript chip and thumbnail open Teams' intelligent recap in a pop-out window (1283 x 730, title bar "OST TEST 217 town hall 2"): header 61 (home icon, title 18/24 700); a #F5F5F5 band 48 tall (date 14 at 12, then Share 78 x 32 with icon, "Open in Clipchamp" 169.8, "Copilot" 96.2, ··· 32 x 30 = Go to chat / Delete recap content); left card 755.6 x 574 (white, radius 8) = the recording player (SharePoint streamembed.aspx iframe, 755.6 x 414, embed hv TeamsRecap) then pills Speakers / Topics / Chapters (31.3 tall, radius 15, 13/20) and "Speaker info isn't available for this meeting." (16/22.86 700); right: "Shared files" card (Attendance chip 226 x 32) and a card with pills Notes, AI summary, Custom summary [New], {Transcript|Mentions}, "+1 v" (the other); the Transcript panel is SharePoint's xplatplugins.aspx iframe (472 x 375) with "Is this transcript useful?" and thumbs.
  - Chip: Transcript pill chosen; thumbnail: AI summary ("AI-generated content may be incorrect", "Meeting notes" / "We didn't find any notes for this meeting.", "Follow-up tasks" / "We didn't find any tasks for this meeting.").
  - Highlights (organizer split button): Events app on the event's page (this one is Canceled, Overview only).
  - Share: a menu "Share recap access" / "Copy link". Share recap access = a 600 x 280 dialog (title 20/28 600, "People you specify will have access to the recap", "Share access with" picker "Enter name, email, group or tag", "Notify them in chat" ticked, Give access 97 x 31.3). Give access = POST {teams}/api/mcps/{region}/recapSharing {threadId, iCalUid, messageId:"", organizerId "{oid}@{tid}", driveId, driveItemId, recapSharingToList ["{oid}@{tid}"]}; with Notify, a 1:1 message: a teams-copy-link div with the meetingrecap link (itemtype HyperLink/MeetingRecap, data-itemprops {version 1, kind meetingRecap, meetingTitle, meetingStartTimeMs, meetingEndTimeMs}), text "Recap: {title} {Weekday, Month d} | Meeting | Microsoft Teams", and two links[] entries (preview title/description, recapSharingLinkMeta). Capture: scratchpad chatB/recapshare-capture.jsonl. Shared with OST Test 2 as the test (its 1:1 chat got the notify message: to delete).

- 2026-11-20 (chatB), built (RecapWindow.qml, RecapShareDialog.qml, api::recaps RecapRef / recap_link / share_access / share_message / player_url / transcript) and checked on linuxlt as ost-test1 (`--recap-window-test`):
  - The transcript chip opens the recap window on Transcript, the thumbnail and View recap on AI summary, as Teams: 1283 x 730, header, the date band with Share and More options (Go to chat), the recording playing in OneDrive's own player (Graph driveItem/preview of the recording), Speakers / Topics / Chapters with Teams' texts, Shared files (Attendance), Notes / AI summary / Custom summary (New) / Transcript|Mentions / +1, the transcript from the recording's Stream transcripts (none here: "No transcript available", as Teams shows for this meeting).
  - Share on the card and in the window: Teams' menu; Copy link copies Teams' meetingrecap link (same parameters as Teams' own, threadId = the meeting chat's thread, organizer from the meeting); Share recap access = Teams' dialog, Give access POSTs recapSharing and (Notify) sends Teams' 1:1 message.
  - Highlights (event organizer): Events opens on the event (found by title and start among your events).
  - Open: the band's Open in Clipchamp and Copilot, the Custom summary and Mentions pages, Notes' Add notes, and the player is OneDrive's player rather than the streamembed page Teams frames (it shows an "Open in browser" button where Teams has Manage). Give access was not sent from OST (it was captured from Teams with OST Test 2; the notify message deleted).
<!-- SECTION:NOTES:END -->
