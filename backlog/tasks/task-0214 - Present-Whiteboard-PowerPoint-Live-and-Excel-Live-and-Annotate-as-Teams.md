---
id: TASK-0214
title: Present Whiteboard, PowerPoint Live and Excel Live, and Annotate, as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-17T02:43:00Z'
updated_date: '2026-11-18T23:54:00Z'
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
- [x] #3 Content from camera has Teams' preview and clean-up
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

- Merged into desktop/foundation (2026-11-18): build OK; 741 lib, 28 desktop and 24 vfx tests passed. AC3 (Content from camera) verified live, including the 11 s no-board path and Teams as viewer. Open: the rechecks, viewing from a different account, Excel Live from Teams, PowerPoint Live's control/laser/ink/camera, keys during give control.
- 2026-11-18 (evening) rechecks and open items:
  - Annotate overlay out of the share: verified (KWin excludeFromCapture true once mapped; the overlay card shows on linuxlt, not in Teams' picture).
  - Teams presenting Whiteboard: OST showed Teams' existing board ("Note pack - yellow") and followed Teams' Follow me.
  - Different account (OST Test 3, browser sign-in): Teams viewed its Whiteboard (same meeting board, both users on it). Annotate: session and overlay fine, but Teams showed no annotation layer; Teams' sharer publishes screenSharerAttributes {source, annotationWindowSize}, which OST now sends too (verified sent; Teams' view of it not yet rechecked).
  - Excel Live from Teams (workbook opened once in Teams so the tray lists it): OST Test 3 hosted Excel's page; fixed: Teams sends onExtensibleAppContextChanged to the app and its content/state carry appLoadState preLoadApp/fullLoadApp, fileId, substrateId — OST now does both, and asks Teams' "Share with all participants?" before its own Excel Live (MeetingFileShareDialog, measured 400 × 235). Now Excel opens the workbook in OST but says "You don't have access to this file": Teams' state permits only the presenter (in a Meet now nobody is invited); needs a scheduled meeting with test3 invited to tell OST from Teams.
  - PowerPoint Live (OST Test 3 presenting a deck with a cameo): Teams' takeControlPptBtn took it over; OST showed "Another user took control / OST Test 1 is now in control of the presentation. [Take back]", the viewer's Take control, and PowerPoint switched roles in place; Take back took it again (Teams back to Take control). Ink: Teams' pen stroke appeared in OST (DryInk state), Teams' laser too (LiveInking); OST's pen stroke appeared in Teams, OST's LiveInking posts answered 202. Cameo: Teams enables Layout ▸ Cameo only with the camera on and a cameo in the deck (OST does the same); with OST presenting and its (test) camera on, Teams showed OST's camera inside the slide's cameo. OST's own slide show didn't get frames (PowerPoint sends no slide-view bounds there; now sized from its CameoFrameRequestForSlide) — recheck pending.
  - Keys while Teams controls OST's screen: typed through SendInput in winpc's interactive session (scheduled task, no VNC). Teams forwards the move, the press and four modifier key-ups, then nothing; Teams' own log shows its control capturer saw the mouse (Mouse entering render region, Synced Key states, Mouse clicked) but no keys — Teams appears to ignore injected keystrokes, so this needs a real key press on winpc's keyboard.

- Cameo recheck (default profile, --join-content-cameo): frames reach OST's own slide show over the loopback feed, but PowerPoint doesn't draw them in OST's cameo yet (open). Annotate with screenSharerAttributes sent: Teams still shows no annotation layer (open). Test files, boards and the test camera cleaned up.

- Merged 067b8cd (2026-11-18): build OK, 748 lib and 29 desktop tests passed. Open: keys during give control, Annotate seen by Teams, Cameo in OST's own presenter view, Excel from Teams with access.
<!-- SECTION:NOTES:END -->
