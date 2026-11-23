---
id: TASK-0258
title: 'Calendar dark theme: event fills, mini-month week and header lines as Teams'
status: Done
assignee:
  - '@calX'
created_date: '2026-11-23T17:39:00Z'
updated_date: '2026-11-23T19:36:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0255 gave the work week grid Teams' dark palette (days, hours outside the working day, grid lines). In dark theme OST still draws other calendar parts with light colours: event fills (#C7C9EE/#E1E1F6), the mini month's selected week strip, the #E0E0E0 header and month lines and the dashed slot lines. Teams' hosted calendar takes them from its dark palette (measured 2026-11-23: themeLighter #2F2F4A, themeLighterAlt #2B2B40, neutralQuaternary #3D3D3D, neutralLight #141414, ...).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every calendar view (day, work week, week, month, mini month, event cards) draws Teams' dark colours in dark theme, measured on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (calX) Measured on winpc: Teams switched to Dark 09:45-09:52 (winpc time); Day, Work week, Week and Month (the view menu has no agenda or list view), the peek card and the event page read over CDP in the hosted Outlook frame; then back to "Follow operating system theme" (light checked by screenshot, view back to Work week) and the same reads in light.
- Event colours come from Outlook's bundle (read from the frame's scripts): the calendar colour (default calendar: themePrimary #5B5FC7, dark #7F85F5) through Fluent's shade generator (dark darkens where light lightens). Fill at 90 %: busy calLight (dark calTertiary), free/tentative/unanswered calLighter (dark calLight); ended events are dimmed one step ("dim past events"); canceled or declined: the day colour at 75 % with an edge. Text: the grey nearest the fill with 8:1 contrast (Month 11:1, ended 5.5:1, canceled 6:1). Bar: calPrimary at 90 % (ended calLight, dark calTertiary); tentative hatched with the day colour; free and canceled open with an edge. Selected: a 2 px inset ring #242424 / #D6D6D6.
- The model gives exactly the measured light #C7C9EE/#E1E1F6 with #323232/#414141, light ended #E1E1F6 + #555555 text + #C7C9EE bar, light canceled #646464, dark ended #26284A + #A5A5A5 + #4C5093 bar, dark canceled #A0A0A0.
- Dark palette measured: days #292929, past days and off hours #242424, toolbar #292929, side pane #0F0F0F (light #FFFFFF), hour/header/month lines #5C5C5C (light #D1D1D1, OST had #E0E0E0), time scale dashes #141414 (light #EBEBEB), mini month range #383966 (light #DCE0FA), every date in the calendar colour, every mini month day in the text colour (the next month's too), Month's today circle #7F85F5 with #242424 text, past month cells #242424; peek card #292929 with #141414 edge and lines, title #ADADAD, outlined buttons #666666, links #7F85F5.

- Verified live on linuxlt (ost-calX, profile spatest = ost-test1, --cal-test --cal-date=2026-11-20): dark, light and high contrast pictures of Work week, Week, Day, Month, the card, the event page, the form and dialogs; dark/light pixel samples equal Teams' (see summary). Tests: lib 935 passed, desktop 36 passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The calendar takes Teams' hosted-calendar colours in dark (and high contrast), measured on winpc with Teams in Dark and Light.

Changes (desktop/qml/CalendarView.qml):
- Event colours as Outlook's hosted calendar computes them: the calendar colour (themePrimary #5B5FC7 / dark #7F85F5) through Fluent's shade generator; fills at 90 % by show-as, ended events dimmed one step, canceled/declined the day colour at 75 % with an edge; text the grey nearest the fill with Teams' contrast targets (8:1, Month 11:1, ended 5.5:1, canceled 6:1); show-as bar in the calendar colour (dimmed once ended; tentative hatched with the day colour; free and canceled open); selected event a 2 px neutralDark ring.
- Grid, header and month lines neutralTertiaryAlt (#D1D1D1 / #5C5C5C), time-scale dashes #EBEBEB / #141414, toolbar and grid on #FFFFFF / #292929, side pane #FFFFFF / #0F0F0F, mini month's range #DCE0FA / #383966 (black ink in HC), every mini month day in the text colour, dates in the calendar colour, a busy day the calendar colour at 10 % over the day.
- Month: past cells #FAFAFA / #242424, today's circle #5B5FC7 / #7F85F5 (dark ink #242424), "+N" #F0F0F0 / #141414.
- Peek card: edge and lines #141414, title #ADADAD, outlined buttons #666666, links #7F85F5, buttons and note on the card colour.
- docs/spec/calendar.md: the event colour model and the dark palette.

Tests: OST's --cal-test on linuxlt as ost-test1 (Nov 16-20, OST TEST 240's card and page) in dark, light and high contrast; pixel samples match Teams (dark ended busy #26284A fill, #A5A5A5 text, #4C5093 bar; canceled #A0A0A0; light ended #555555, canceled #646464). Lib tests 935 passed.

Open: unmeasured (no live instance on ost-test1's calendar): a not-yet-ended event in dark (computed from the same model), the busy all-day day tint in dark, Month's "+N" in dark; the event page's body links keep Qt's default #0000FF in both themes.
<!-- SECTION:FINAL_SUMMARY:END -->
