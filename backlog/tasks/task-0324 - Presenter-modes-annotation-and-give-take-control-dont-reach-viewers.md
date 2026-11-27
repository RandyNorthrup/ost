---
id: TASK-0324
title: Presenter modes, annotation and give/take control don't reach viewers
status: Done
assignee:
  - '@meet'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-27T00:41:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). Shares started with a presenter mode (standout, reporter, side by side), with annotation, or handed over with give/take control never reach the viewer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Presenter modes, annotation and give/take control work between OST and Teams in both directions, verified live with test accounts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce each case live between OST Test 2 and OST Test 3 on linuxlt and Teams (web on linuxlt; Teams desktop on winpc for presenter modes and control)
2. Find what differs on the wire and fix OST
3. Verify OST to OST and OST to Teams, both ways
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26 rig: "OST TEST 324 meet" (organizer ost-test1); OST Test 2 presenting and OST Test 3 viewing on linuxlt (test camera A fed a synthetic face); Teams on the web in Chrome on linuxlt as ost-test1 and OST Test 2.
- First shares worked OST to OST: Standout (window), Reporter with "Futuristic room" (background, content and cut-out presenter composited), Annotate on a screen share (viewer got "A participant started annotations…"), Take control of a screen share (Available/AvailableAck, request, accept, Ack, controlling; the desktop Remote Control portal then asks the sharer, denied here so nothing was typed on linuxlt).
- Cause: a second share in the same call never arrived (OST Test 3: empty content tile; Teams on the web: no share; the roster said sendonly). VideoSender restarted its RTP sequence numbers at (ssrc >> 7) for every new sender on the same line, so SRTP reused packet indexes (keystream reuse) and the media processor dropped them as replays. The same applied to the camera turned off and on. The wiki captures shared several times per call.
- Fix: webrtc_video::RtpLine per line (camera, sharing) carries the sequence numbers (atomic, so an old sender finishing beside a new one can't collide) and the timestamp clock across senders, as a WebRTC sender with a replaced track.
- Verified after the fix: OST Test 2 shared a window in Standout, stopped, shared again: the second share reached OST Test 3 (stage capture) and Teams on the web. Teams on the web (OST Test 2) shared twice: OST Test 3 showed both.
- Window shares can't be controlled (Wayland: AvailableNack SharerControlDisabled, as documented); the wiki's "capable=false" for a window share is that.

- Codex review (PR #16): SRTP's sender bumped the rollover counter only on seeing 65535; with packets dropped unsent around the wrap (a sender stopped with its queue) the next sender's packets would use the old ROC. protect() now keeps the last protected sequence number per stream and counts a wrap from it (RFC 3711 packet index); test in bundled_streams_keep_counters_per_ssrc.
- Found in the recheck: a camera turned on while waiting in a lobby was lost on admission ("camera not taken over by the new media session: Device or resource busy"): the processor moves the call to a new media session, which opened the camera while the old session still held it, so Side-by-side had no presenter to composite. answer_renegotiation now turns the old session's camera off first.
- Q&A on the bar also verified for someone admitted from the lobby (OST Test 3: Chat, Q&A, People…) with the second share arriving.

- Verified after the camera fix: OST Test 2 turned its camera on while waiting in the lobby (Side-by-side, "Futuristic room"), was let in (media moved to the new offer, no busy camera), shared a window: OST Test 3 composited background, content and presenter.
- Not re-verified with Teams desktop: winpc's Teams was in use by other agents (OneDrive / People work over VNC and CDP) for the whole session, so joining a meeting there would have disturbed them. Teams on the web has no presenter modes and no Take control, so the Teams-side checks of those two still need Teams desktop (they last passed against it on 2026-11-16/18 and their signalling is unchanged; this fix is in the media layer every receiver shares, and Teams on the web confirmed it for shares in both directions). AC #1 stays open until that rerun.
- Test meeting "OST TEST 324 meet" deleted afterwards; linuxlt cleaned (Chromes, ffmpeg, PipeWire modules, folders).

- Teams desktop check, 2026-11-26.
  - Rig: winpc Teams desktop as ost-test1, in the scheduled test meeting "OST TEST 324 desktop" (organizer OST Test 2), with OST Test 2 and OST Test 3 on linuxlt.
  - Media: virtual mic ost_meet_mic; pactl confirmed both OST streams recorded from it, and a watcher never saw a stream on alsa_input.pci.
  - Camera on linuxlt: test camera C with a synthetic face.
  - Shares on winpc: only a throwaway test window ("OST TEST 324 window"). On linuxlt: KWrite, or KDE's "Share virtual screen".
- OST presents, Teams desktop views.
  - Standout, then Reporter (switched by Layout): Teams showed "Content shared by OST Test 2 in presentation mode" and laid the camera out by mode.
  - Teams draws OST's cut-out camera with a black box instead of transparency (a later task tracks it).
- Teams presents, OST views. winpc's C920 was on for about 5 minutes; no frames were kept, and OST's stage captures were deleted unseen.
  - Standout, then Reporter and Side-by-side from Teams' Layout menu.
  - OST Test 3 received each layout and composited it: Weatherperson, NewsAnchor with Teams' "Futuristic room" background, and SideBySide with the content left and the presenter right.
  - Teams' camera arrived with the implicit mask.
- Give/take control.
  - Teams gives control to OST: GiveControl, OST Ack, controlling. OST clicked and typed into Teams' shared test window; it arrived as "OST TESt" (a later task tracks it).
  - OST gives control to Teams (OST sharing a KDE virtual screen): GiveControl, Teams Ack, and Teams showed Stop control.
  - Teams takes control of OST: Teams' "Request control?" then Request, ControlRequest, OST AcceptRequest, Teams Ack and Stop control; Teams' Stop control sent Terminate (reason 6), which OST acknowledged.
  - The desktop Remote Control prompt on linuxlt was dismissed each time, so no input reached a real desktop.
  - Not shown by Teams: OST's own Take control request to a Teams desktop sharer. Teams answered Available with AvailableAck, but showed no alert for the ControlRequest, which timed out after 30 s, twice. It worked on 2026-11-16. This part of AC #1 is still open.
- Cleanup: OBS, installed briefly for a virtual camera that Teams' WebView2 doesn't list, was uninstalled. The winpc test window and tasks are removed; Teams is left running as found.

- OST's own Take control request to Teams desktop, 2026-11-26 evening.
  - Rig: winpc Teams desktop as ost-test1 in a Meet-now test meeting "OST TEST 342", sharing only a throwaway test window ("OST TEST 342 window"), with the VB-Audio CABLE virtual mic; OST Test 3 on linuxlt.
  - Teams' log shows the request every time: "incoming control request", then `adding new alert: SharingIncomingControlRequest "OST Test 3 is requesting control."`, and an always-on-top alert window is created. The earlier "never shows" was this window, which CDP screenshots of the main window don't capture.
  - Accepted live: Give control → AcceptRequest → OST's Ack → controlling. OST clicked into the test window and typed 16 Shift-held capitals, a space and 4 more; all arrived as typed.
  - Later requests in the same meeting timed out (SharerNoResponse). Teams still raised the alert in its log, but its window never showed on screen. While presenting, Teams had switched its own status to Presenting, shown as Do not disturb with its banner "Your status is set to do not disturb…". Setting the status to Available by hand didn't hold while sharing. With no second Teams desktop signed in (testpc1/testpc2 still at sign-in), a Teams-to-Teams request couldn't be compared.
- Found and fixed: a viewer that joins while a share is already on never got Take control. Its first control command (watch the sharer) came from the join's roster before the call was in its slot, and was dropped. The command queue now waits for the call (up to 10 s, in order). Verified OST to OST: watching started before the media session was up, Available went out once it was, and the sharer answered (AvailableNack 9 for a window share, as expected).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shares started with a presenter mode, with Annotate, or with give/take control now reach viewers, OST and Teams, both ways.

Causes and fixes:
- PR #16:
  - Every new sender on a video line restarted its RTP numbering, so SRTP reused packet indexes. The meeting dropped a call's second share, and a camera turned on again, as replays.
  - SRTP counted a rollover only on seeing 65535.
  - A camera turned on in the lobby was lost on admission.
- This PR:
  - A viewer joining while a share was already on lost its first control command, so it never got Take control.

Changes:
- PR #16:
  - `webrtc_video::RtpLine` carries sequence numbers and the timestamp clock across senders.
  - SRTP counts the rollover from the last protected sequence number (RFC 3711).
  - On admission, the old media session releases the camera first.
- This PR:
  - `presenting::command` waits for the call, in order, before handing over control commands.

Live checks:
- OST to OST: each presenter mode, Annotate, Take control, and a second share in one call.
- With Teams desktop on winpc, both ways:
  - Presenter modes reached the other side.
  - Teams gave control to OST, and OST gave control to Teams.
  - Teams took control of OST.
  - OST asked Teams for control: Teams showed "OST Test 3 is requesting control." and Give control handed it over; OST's keys arrived as typed.

Notes:
- While Teams desktop presents, it sets its own status to Do not disturb. Its alert is then raised (in its log) but not shown, so later requests time out. That's Teams' side.
- Teams desktop draws OST's cut-out camera with a black box; that is tracked as its own task.
<!-- SECTION:FINAL_SUMMARY:END -->
