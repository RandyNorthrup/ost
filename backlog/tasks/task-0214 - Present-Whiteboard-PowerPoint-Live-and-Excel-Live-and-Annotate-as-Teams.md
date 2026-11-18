---
id: TASK-0214
title: Present Whiteboard, PowerPoint Live and Excel Live, and Annotate, as Teams
status: To Do
assignee: []
created_date: '2026-11-17T02:43:00Z'
updated_date: '2026-11-18T19:37:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0210 left (docs/spec/call-and-meeting-window.md §9c): starting a Microsoft Whiteboard, PowerPoint Live or Excel Live share (each a content-sharing session that viewers open as Whiteboard or Office for the web) and viewing one shared by Teams; Annotate on a shared screen (Teams' shared ink); Content from camera's live preview and whiteboard/document clean-up; controlling a shared screen from Teams checked end to end on linuxlt; Give control started from OST's side checked live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST starts and views Whiteboard, PowerPoint Live and Excel Live shares as Teams
- [ ] #2 Annotate works on a shared screen as in Teams
- [ ] #3 Content from camera has Teams' preview and clean-up
- [ ] #4 Teams controls a screen OST shares, and OST gives control from its side, checked live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (Teams' bundles on linuxlt, live captures on winpc): Whiteboard, PowerPoint Live, Excel Live and Annotate are content-sharing sessions (addModality contentSharing; identifier = base64 of the content JSON; updateSessionState; DELETE controller; viewers find sessionInformation in the roster and join). Spec docs/spec/content-sharing.md.
- Built: `calling::content_sharing` (+ OutgoingCall start/update/stop/join/events, roster content_sessions), desktop content_share.rs, ContentStage.qml (Whiteboard and Excel pages as TeamsJS meetingStage apps), PptLiveStage.qml + ppt_host.js (Teams' bundled PowerPoint bootstrapper: the slideshow.aspx form, its frame protocol, the Nav state), `api::live_share` (redeem, snap, recent docs, Excel share link and stage page), AnnotationOverlay.qml (overlay layer-shell window, KWin excludeFromCapture, click-through input region), the bar's Stop sharing / Layout + Stop sharing / "Stop presenting?", Pop out of a session.
- Live: PowerPoint Live both ways with Teams (slides follow); Whiteboard OST->Teams (same board, edits sync) and Teams->OST; Excel Live OST Test 2->Teams (the workbook opens in Teams); Annotate's overlay with Whiteboard's toolbar, kept out of the share.
- Content from camera: built by a helper (merged: ContentCameraDialog.qml, ost_vfx::content_camera); I added learning the board behind a presenter already standing there, reran the 11 s no-edges path, and checked Teams as the viewer of OST's camera share.
- AC4: Teams took control of OST's shared screen (portal approved; Teams' press moved linuxlt's cursor to that point); OST's Give control reached Teams (Ack, Stop control).
- Open: PowerPoint's attendee Take control, laser/ink sync and Cameo frames; Excel Live from a Teams presenter (no recent workbook in Teams' tray); Teams as viewer of OST's Whiteboard/Annotate from a second browser-signed-in account (OST Test 2's device-code sign-in can't mint the Whiteboard/Excel NAA tokens); Teams' keys while controlling (Teams drops focus after its first press when driven through VNC).
<!-- SECTION:NOTES:END -->
