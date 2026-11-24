---
id: TASK-0269
title: Series Cancel menu and event page layouts as Teams
status: In Progress
assignee: []
created_date: '2026-11-24T05:55:00Z'
updated_date: '2026-11-24T06:23:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0267: the event card's Cancel ▾ for a series (this event / this and following / all) isn't built; the 'This event' page layout wasn't re-measured; a Teams meeting's card with the Copilot rows wasn't measured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancel on a series' card offers Teams' choices and cancels each as Teams does, verified with attendees
- [ ] #2 The This event page and a Teams meeting's card match Teams' layout, measured on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (canW) Measured on winpc (ost-test1; series T1 Teams meeting, T2/T3 plain, S1 one-off Teams meeting, all inviting OST Test 2/3) with CDP DOM reads and a passive netlog:
- Card Cancel on a series: Cancel ▾ This event / This and all following events / All events in the series (Outlook ContextualMenu 194.33 wide, 36 px rows). Picking one (or Cancel on a one-off) turns the Edit/Cancel row into "Cancel [this event|this and all following events|all events in the series|event] and notify attendees", a 320x72 message box and Send/Discard; the card keeps its bottom edge.
- Send = Outlook CancelCalendarEvent: EventScope 1 (this event, one-off too, own id), 2 (following, occurrence id), 3 (all, series master id); Notes HTML <div>msg</div> only with a message. Teams meetings the same (no middle tier). Attendees get "Canceled: <subject>" with the message.
- Event page Cancel (▾ on a series) opens Outlook's "Cancel meeting" dialog (600 wide, same header/box/Send/Discard).
- Teams meeting card: charm before the title, Join ▾ (Join Teams meeting / Copy join link), "No location added" + "Add a room with Copilot" under it, no description row for the join block, no "key talking points" prompt while live.
- This event page (Outlook form): 48 px title bar "<subject> - Event instance", command bar card, info bar, Prepare card, form card, body card, Tracking card; OST's page is still Teams-web calv2 layout.
<!-- SECTION:NOTES:END -->
