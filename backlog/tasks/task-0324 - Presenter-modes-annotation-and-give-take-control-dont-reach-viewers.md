---
id: TASK-0324
title: Presenter modes, annotation and give/take control don't reach viewers
status: Done
assignee:
  - '@meet'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T21:40:00Z'
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
  - Teams draws OST's cut-out camera with a black box instead of transparency. Follow-up: TASK-0342.
- Teams presents, OST views. winpc's C920 was on for about 5 minutes; no frames were kept, and OST's stage captures were deleted unseen.
  - Standout, then Reporter and Side-by-side from Teams' Layout menu.
  - OST Test 3 received each layout and composited it: Weatherperson, NewsAnchor with Teams' "Futuristic room" background, and SideBySide with the content left and the presenter right.
  - Teams' camera arrived with the implicit mask.
- Give/take control.
  - Teams gives control to OST: GiveControl, OST Ack, controlling. OST clicked and typed into Teams' shared test window; it arrived as "OST TESt", see TASK-0342.
  - OST gives control to Teams (OST sharing a KDE virtual screen): GiveControl, Teams Ack, and Teams showed Stop control.
  - Teams takes control of OST: Teams' "Request control?" then Request, ControlRequest, OST AcceptRequest, Teams Ack and Stop control; Teams' Stop control sent Terminate (reason 6), which OST acknowledged.
  - The desktop Remote Control prompt on linuxlt was dismissed each time, so no input reached a real desktop.
  - Not shown by Teams: OST's own Take control request to a Teams desktop sharer. Teams answered Available with AvailableAck, but showed no alert for the ControlRequest, which timed out after 30 s, twice. It worked on 2026-11-16. Added to TASK-0342.
- Cleanup: OBS, installed briefly for a virtual camera that Teams' WebView2 doesn't list, was uninstalled. The winpc test window and tasks are removed; Teams is left running as found.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shares started with a presenter mode, with Annotate, or with give/take control now reach viewers, OST and Teams, both ways.

Causes, fixed in PR #16:
- Every new sender on a video line restarted its RTP numbering. SRTP then reused packet indexes, and the meeting dropped the second share in a call (and a camera turned on again) as replays.
- SRTP counted a rollover only on seeing 65535.
- A camera turned on in the lobby was lost when the lobby let us in.

Changes (PR #16):
- `webrtc_video::RtpLine` carries each line's sequence numbers and timestamp clock across senders.
- SRTP counts a rollover from the last sequence number it protected (RFC 3711).
- On admission, the old media session releases the camera before the new session opens it.
- Specs updated.

Live checks:
- OST to OST: Standout, Reporter and Side-by-side with a background, Annotate, Take control and a second share in one call. Teams on the web saw both shares.
- With Teams desktop on winpc (2026-11-26):
  - Each presenter mode reached the other side, both ways. OST composited Teams' layouts with Teams' mask.
  - Control: Teams gave control to OST, OST gave control to Teams, and Teams took control of OST, each ending cleanly.

Follow-ups in TASK-0342:
- Teams desktop draws OST's cut-out camera with a black box.
- One typed key lost its Shift.
- Teams showed no alert for OST's own control request.
<!-- SECTION:FINAL_SUMMARY:END -->
