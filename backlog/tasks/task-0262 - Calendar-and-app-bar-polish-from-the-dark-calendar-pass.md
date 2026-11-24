---
id: TASK-0262
title: Calendar and app bar polish from the dark calendar pass
status: Done
assignee:
  - '@polZ'
created_date: '2026-11-23T19:37:00Z'
updated_date: '2026-11-23T21:20:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0258: links in an event page's body show Qt's default blue in both themes; the app bar's Chat and Calendar icons are missing in the first frame after start; three dark calendar colours (upcoming event, all-day busy day tint, Month's +N button) come from Teams' model, not a measurement, because ost-test1 had no such events.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Links in event page bodies use Teams' link colours in light, dark and high contrast
- [x] #2 The app bar shows all its icons from the first frame after start, as Teams
- [x] #3 Upcoming events, all-day busy days and Month's +N button match Teams in dark, measured with test events
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (polZ) Test data: 11 events in ost-test1's calendar created over Graph (no attendees, no reminders): "OST TEST polZ upcoming" (Tue 11/24 10-11, busy, body with a link), "... upcoming free" (11/24 1-2 PM), "... all-day" (Wed 11/25, busy), "OST TEST polZ 1".."8" (Fri 11/27 8:30-12:30, busy, for +N); later "OST TEST polZ body link" (Teams meeting, Thu 11/26) from OST's form.
- Measured on winpc over CDP (Teams Dark 11:52-11:55, High contrast 11:55-11:56 winpc time, then back to "Follow operating system theme", checked light, view back to Work week):
  - Event page (Outlook's editor, for plain events and Teams meetings alike): links underlined, light #0000EE (browser default), dark `.Z6_Ux a:link` #BA7CFF (visited #E49FFF); High contrast keeps the page dark, #BA7CFF.
  - Dark upcoming busy: fill #4C5093 at 90 %, text #FFFFFF, bar #7F85F5 at 90 %; free: #26284A at 90 %, text #C3C3C3 (Month #E6E6E6), bar the day colour with a #7F85F5 90 % edge. Exactly Outlook's model already in OST.
  - All-day busy day: a #7F85F5 / #5B5FC7 layer at opacity 0.1 over the whole column, its hours outside 8-17 and its header: dark #32323E / #2D2D39, light #EEEFF9 / #EAEBF5. OST left the outside hours untinted.
  - Month +N: dark #141414, text #ADADAD 12/400, hover #5C5C5C; light #F0F0F0, #616161, hover #EBEBEB (OST had hover #E0E0E0 / #3D3D3D).
- App bar cause: FluentIcon read the SVG with an async XHR and showed it as a data: URL, which Qt's pixmap cache always loads in the background. Instrumented run before the fix: the frame after switching to Calendar had chat and calendar-filled in Image.Loading (blank, as in the cal-test shot). Fix: a "fluent" QQuickImageProvider (src/native.cpp) drawing the recoloured SVG synchronously.
- Rich text: Text.linkColor does nothing for RichText (only StyledText); Qt then draws #0000FF. Chat messages, posts and meeting details already put a <style> ahead; AdaptiveCard, ConnectorCard, AppDetailsDialog, TabAboutDialog, ForwardCard and the Events app description did not - fixed with theme.linkCss().

- Verified live on linuxlt (ost-polZ, profile spatest, --cal-test --cal-date=2026-11-24, dark/light/highContrast): event page link pixels #0000EE light, #BA7CFF dark and HC; busy-day tint #EEEFF9/#EAEAF5 light, #32323E/#2D2E39 dark (Teams #EAEBF5/#2D2D39, 1 off in one channel); dark busy tile #484C88 with #FFFFFF text, free #262847, Month free text #E6E6E6, +N #141414 (light #F0F0F0). Instrumented runs: before the fix the frame after switching to Calendar had chat and calendar-filled Loading; with the provider all 7 rail icons Ready in frames 0-2 and the frame after the switch, and the shot taken right after the switch shows them.
- Saved body checked: a meeting scheduled from OST's form in dark with a link body was stored as <a href><span style="text-decoration:underline"> (no colour). Send update on a plain (non-meeting) event fails with Teams' "Conversation id cannot be null" - existing behaviour, not from this change.
- All 12 polZ test events deleted (Graph DELETE, none left). Tests: lib 935 passed, desktop 36 passed. Commit b394c8b2.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Event page links, app bar icons and the last dark calendar colours, all measured on winpc and checked live.

Changes:
- MeetingForm: links in the details in Teams' event page colours (#0000EE light, #BA7CFF dark and high contrast); the colour is put on with a style sheet and taken out of the saved body; fragment markers dropped.
- Theme.linkCss(): Text.linkColor does nothing for RichText, so AdaptiveCard, ConnectorCard, AppDetailsDialog, TabAboutDialog, ForwardCard and the Events description now set link colours through a style sheet (chat, posts and meeting details already did).
- FluentIcon: pictures from a synchronous "fluent" image provider (src/native.cpp, registered in main.rs) instead of an XHR + data: URL, which Qt always decoded in the background; icons no longer blank for a frame after start or when the app bar switches apps.
- CalendarView: the all-day busy tint also covers the hours outside the working day (Teams' layer at opacity 0.1); Month +N hover #EBEBEB / #5C5C5C.
- docs/spec/calendar.md: measured dark upcoming colours, the busy-day tint, +N and event page links.

Tests: lib 935 passed, desktop 36 passed; live runs on linuxlt in dark, light and high contrast.

Open: Teams' High contrast calendar draws yellow event tiles where OST draws black ones; OST's toolbar shows "Filter applied" for ost-test1 where Teams shows none; Send update on a non-meeting event fails (Teams meeting update API).
<!-- SECTION:FINAL_SUMMARY:END -->
