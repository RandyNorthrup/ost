---
id: TASK-0262
title: Calendar and app bar polish from the dark calendar pass
status: In Progress
assignee:
  - '@polZ'
created_date: '2026-11-23T19:37:00Z'
updated_date: '2026-11-23T20:55:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0258: links in an event page's body show Qt's default blue in both themes; the app bar's Chat and Calendar icons are missing in the first frame after start; three dark calendar colours (upcoming event, all-day busy day tint, Month's +N button) come from Teams' model, not a measurement, because ost-test1 had no such events.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Links in event page bodies use Teams' link colours in light, dark and high contrast
- [ ] #2 The app bar shows all its icons from the first frame after start, as Teams
- [ ] #3 Upcoming events, all-day busy days and Month's +N button match Teams in dark, measured with test events
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
<!-- SECTION:NOTES:END -->
