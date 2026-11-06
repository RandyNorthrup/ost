---
id: TASK-0034
title: 'Desktop: screen sharing in calls and meetings'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-06T15:39:00Z'
labels:
  - desktop
  - calling
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Share is the last greyed control on the call bar. Teams shares a screen as a second video stream (applicationsharing-video); OST needs Wayland capture (xdg-desktop-portal ScreenCast + PipeWire; Hyprland's portal is installed), H.264 encoding (exists) and Teams' content-sharing signalling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Share in a 1:1 call shows the picked screen or window in Teams web
- [ ] #2 Share in a meeting shows it to the other participants
- [x] #3 Stop sharing ends the stream on both sides
- [x] #4 A screen shared by the other person in a call shows on OST's stage, and is taken down when they stop
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Receive: parse and accept the applicationsharing-video line (own payload type, SSRC, track id), decode it to a "share" frame, show it letterboxed on the stage; clear it when a re-offer stops sharing.
2. Send: capture through xdg-desktop-portal ScreenCast + PipeWire, H.264-encode, offer the sharing line in a re-offer.
3. Meetings: same streams through the media processor.
4. Live tests from Randy's Teams web both ways.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Receive done and tested live: Randy's Teams web shared a tab (example.com) to OST in a 1:1 call; OST showed it with "<name> is presenting", camera moved to a corner tile; Stop sharing cleared it.
- Root cause of a first failed attempt: the answer's H.264 profile-level-id for PT 102 didn't match the offer's (42001f), so Chrome rejected the answer and DTLS timed out. Each video line now echoes the offer's profile.
- The share is accepted in audio-only calls too, as Teams allows.

- Send done and tested live in a call Randy placed to OST: OST shared a test window; Randy's Teams web showed it; Stop sharing returned both sides to the call view.
- What Teams needs (found in its calling bundle and a captured share of its own): the re-offer's mediaContent must be application/sdp-ngc-1.0 (Teams' processOffer refuses plain application/sdp with 488/3102); the answer must be acknowledged (an empty POST to its links.mediaAcknowledgement); and video lines must carry only a=x-ssrc-range (no a=ssrc msid), so Teams names the stream after the label (applicationsharingVideo-<ssrc>). With msid:ost ... its renderer showed "something went wrong".
- Re-offers start from the description we last sent (re-answers update it) and use setup:actpass, as Teams' do.
- Still to do: calls OST places (our offer has no sharing line yet) and meetings (AC #2).
<!-- SECTION:NOTES:END -->
