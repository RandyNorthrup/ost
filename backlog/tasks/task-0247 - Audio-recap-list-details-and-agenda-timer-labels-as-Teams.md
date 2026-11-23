---
id: TASK-0247
title: Audio recap list details and agenda timer labels as Teams
status: To Do
assignee: []
created_date: '2026-11-23T04:05:00Z'
updated_date: '2026-11-23T06:49:00Z'
labels:
  - desktop
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0212 and TASK-0246: the Generate audio recap dialog names meetings from Teams' event list (OST shows the recording-renamed chat topic, e.g. 'Recording of OST TEST 212 recap long is now available'); Listen on mobile and the New badge aren't built; Teams auto-plays a recap it just made; the agenda timer strip leaves out Teams' shortened topic labels in narrow segments; the Facilitator's questions list could not be produced live (it answers in plain text).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The audio recap dialog and list show Teams' meeting names, New badge and Listen on mobile, and a just-made recap auto-plays as in Teams
- [ ] #2 The agenda timer shows Teams' shortened labels in narrow segments
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-22 (meetL) measured on winpc (Teams 26304, ost-test1, CDP) and in Teams' bundles:
  - Generate audio recap's meetings come from Teams' meetingRecapList (useMeetingRecapList -> getMeetingRecapByDay, 30 days, a day at a time): the day's meeting artifacts (user/meetings/contents, threadInfo.subject) raced against the day's Copilot catch-up recommendations; the first answer shows, both are merged (artifacts keep their subject, recommendations add counts) and cached per day; the cache shows first on the next visit. Recommendations without a calendar event (MeetingId empty: all but OST TEST 240 here) are not listed. The AugLoop teams_recap_podcast_event_list (meetingList(timerange)) is not queried by any 26304 UI bundle.
  - The TASK-0212 name difference was Teams' day cache: "OST TEST 212 recap long" from before its calendar item became "Canceled: Recording of OST TEST 212 recap long is now available" (no resources left); after a refresh Teams dropped it from Home too (captured: the artifacts reply carries the new subject).
  - Teams ends Home and the dialog with "Loaded all meetings in the last 30 days." (12/16 #616161; padding 16 8 0 16 on Home, 16 8 16 16 in the dialog). Older groups are one per day ("Friday, November 6"; Teams' ka), not per week.
  - Listen on mobile (podcast QR button 37.3 x 31.3, phone 20 px, label only from 1280 app width) and New badge (36.7 x 20, round, #5B5FC7, 12/600; ECS showListenOnPhoneNewBadge on, 14 days from listenOnPhoneNewBadgeStartDateTime). Its dialog: 600 wide, padding 24, title 20/28, text 14/20, a 130 px picture (radius 20, 0.67 #D1D1D1, 10 in) of qrcode-svg's code, error correction L, 45 modules. zbarimg on Teams' code: https://teams.microsoft.com/l/meetingpodcast?id=<podcast id>&origin=desktopQRCode.
  - Auto-play (75874 kt): a recap seen generating plays from the start when its chapters come, unless another one was picked.
  - Agenda strip (3 Facilitator meetings, 2/2/1 min + Open discussion): each topic has a slot by length; a slot under 37 (26 + 11 padding) is drawn 37 wide centred on it, over the gaps; title via CSS ellipsis: "B…" in 19.1, "B…" cut in 15.8, the left of "V" in 3.9, nothing at 0-0.8. Widths: 1280+chat 56.1/56.1/37/645.4, 1024+chat 37.8/37.8/37/435.1, 1322 no chat 81.9/81.9/40.9/982.4.
- Built: recap list as Teams (30 days, footer, day groups, comment fixed), Listen on mobile + New badge + QR dialog (backend podcastQr, room_host::qr_rows_at, api::podcast::mobile_link), auto-play of a just-made recap; agenda slots with the 37 px minimum centred, Chrome-style label shortening, rounded progress fill; harness --call-notes-unmuted/--call-notes-keep/--call-notes-cleanup, --agenda-strip-test, RECAPS listen/auto-play lines.
- Verified live (linuxlt, default = ost-test1): "OST TEST 247 agenda" (OST organizer, Teams on winpc as a second device, Facilitator agenda, a 9 min Piper dialogue into OST's mic for a transcript). OST Generate from it: COMPLETED, RECAPS auto-play, playing from 0 (Teams lists the same recap). OST's dialog: This week / Last week / Friday, November 6 and the footer, as Teams. Recap header: phone button + New, QR dialog; zbarimg on OST's code gives the same link as Teams'. Agenda: OST at 1032 (row 529.7) 37/37/37/438.3 vs Teams 37/37/37/438.4 with the same positions; OST maximized 81.8/81.8/40.9/981.2 vs Teams 81.9/81.9/40.9/982.4; --agenda-strip-test at Teams' three rows gives Teams' widths, places and labels.
- Tests: 917 lib + 30 desktop pass on linuxlt.
- Cleanup: Facilitator turned off in Teams in all three meetings, Teams left (survey dismissed); OST left each call (logs: callState empty, audio devices closed). Deleted: "OST TEST 247 agenda" (--call-notes-cleanup), "OST TEST 247 agenda 2" and "3" (harness), their notes (OST TEST 247 agenda.loop, agenda 3.loop, and "Meeting Notes.loop" made for agenda 2), both test audio recaps (247 and an earlier failed one, deletePodcasts 2 of 2), the meetL PipeWire devices. Left: the meetings' chats and their transcripts (stay with the chats).
- Seen, not in scope: after Teams turned Facilitator off, OST kept showing the agenda strip while Teams switched to the ad-hoc timer; OST named agenda 2's notes "Meeting Notes" instead of the subject.
<!-- SECTION:NOTES:END -->
