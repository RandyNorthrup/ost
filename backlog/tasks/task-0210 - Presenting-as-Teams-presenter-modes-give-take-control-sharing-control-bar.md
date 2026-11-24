---
id: TASK-0210
title: 'Presenting as Teams: presenter modes, give/take control, sharing control bar'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T23:23:00Z'
updated_date: '2026-11-17T02:43:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0185 left of Teams' sharing (docs/spec/call-and-meeting-window.md §9a–b): presenter modes (Standout, Reporter, Side-by-side: each receiver composites the presenter's camera over the shared screen) and Add background; Give / take control on both sides (data-channel messages, format in the spec); Teams' separate Sharing control bar window (Give control, Share sound, Optimize, Layout, Annotate, More, Stop sharing, Pin); Whiteboard, Content from camera, PowerPoint and Excel Live in the tray; the tray's exact position and height.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Presenter modes and Add background work as in Teams, for the presenter and for receivers
- [x] #2 Teams' Sharing control bar window appears while sharing, with its controls
- [x] #3 Give control and take control work both ways with Teams for a shared screen (a shared window can't be controlled on Wayland: platform difference)
- [x] #4 The tray offers Whiteboard, Content from camera, PowerPoint Live and Excel Live rows at Teams' positions, and Content from camera shares a camera as content
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (c3c467e, merged); spec docs/spec/call-and-meeting-window.md §9c.
- Presenter modes: OST publishes Teams' layout and cuts its camera background out as Teams; as receiver composites with Teams' numbers. Live: Teams showed OST's share "in presentation mode" (Standout, Side-by-side, Reporter); OST read Teams' Standout layout and placed the camera as Teams' numbers say. Add background's 13 pictures.
- Control: Teams' handshake, request card and dialogs; OST typed "OST TEST" into Teams' shared Notepad; Teams' Take control reached OST through the remote-control portal. A shared window can't be controlled on Wayland (no window position), so OST tells Teams control isn't allowed, as Teams does when control is off.
- Sharing control bar window with Teams' controls (Annotate disabled).
- Tray rows and drill-downs; Content from camera shares a camera.
- Found: TASK-0213 (data channel after lobby). Left: TASK-0214.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Presenting as Teams: presenter modes and Add background, give/take control, the Sharing control bar window and the tray's extra rows.

Tests: control protocol, input formats, layout arithmetic and background mask unit tests (library, screencast and video features); live with Teams on winpc both ways. Follow-ups TASK-0213 (bug), TASK-0214.
<!-- SECTION:FINAL_SUMMARY:END -->
