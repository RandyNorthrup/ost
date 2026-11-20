---
id: TASK-0098
title: Meeting recap card on a meeting's ended row, as Teams
status: In Progress
assignee: []
created_date: '2026-11-10T17:18:00Z'
updated_date: '2026-11-20T19:52:00Z'
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
- [x] #1 A meeting chat's ended row shows the recap card with Teams' layout, title, date range, transcript chip and recordings thumbnail/count
- [ ] #2 View recap, the transcript chip and the thumbnail open what Teams opens
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chat agent): measured on winpc ("Event group: OST TEST 217 town hall 2", the 50m 5s town hall with a recording and transcript): 646 x 162 card 14 under the ended row, white, radius 8, shadow 0 0 2 .12 / 0 2 4 .14, padding 14 20 0; subject 16/20 600 #242424 and the date range 12 #616161 ("Wednesday, November 18, 2026 8:40 PM - 9:40 PM"); Share (32 x 32, recap-share-button) and the recap button ("Highlights" split for the event's organizer: recapSplitPrimaryButton 114.2 x 32 brand + a 20 x 32 chevron); a line; "Content" 12/600 #616161; the Transcript chip (96 x 32, 0.67 #F0F0F0, radius 4); the recording thumbnail (108 x 60, radius 6) with its "47m 40s" pill (rgba(0,0,0,.4), radius 2, 12 px white) and "Expires in 119 days" (10 px #616161, a 10 px clock). Meeting chats without recordings or transcript (OST calendar test) show only the Attendance cards.
- Teams' code (meeting-recap-chiclet-app, 983864/102674; research notes in the scratchpad recap-research.md): shown when the call's recording/transcript messages fold into its ended row (by callId); title = a group chat's topic, else the call-end XML's Subject; button "View recap" (messaging:k1tc0zdrt) or for Split/Menu styles "Recap" (extensibility:k5hpfls5x) with Audio/Video recap; town hall / webinar organizers see "Highlights" (meetingRecap:kc40v5p0g) with Highlights / Recap; "Content" kaeryhl69; Transcript artifactsPlatform:k1tttxcnb; no content kcorsfr1k; "{n} recordings" kc0ilq7jw; "Saving..." ka97b62m1; expiry kanosvkvh_mf / "No expiration" k9n0fpa7u / "Set to expire" k7mpmiird. View recap, the thumbnail and the chip open the meeting's Recap (intelligentRecap with defaultRightTab); Highlights opens the event's Highlights in Events; Share opens recap sharing.
- Built: messages::attach_recaps (Recap / RecapRecording on the ended row, from the page's recording and transcript messages and the call-end XML), the thumbnails cached (localize_recap), RecapCard.qml in place of the attendance card; View recap / chip / thumbnail open the chat's Recap tab.
<!-- SECTION:NOTES:END -->
