---
id: TASK-0270
title: Mic during a cast and showing hidden in-room attendees as Teams
status: Done
assignee:
  - '@castU'
created_date: '2026-11-24T06:59:00Z'
updated_date: '2026-11-24T09:17:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0228/0268: during a cast OST greys out the mic where Teams shows it muted but usable; after Hide Attendees, Teams' way to show in-room attendees again wasn't found, so OST offers none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 During a cast the mic button looks and works as Teams' (muted but usable)
- [x] #2 Hidden in-room attendees can be shown again wherever Teams offers it, verified on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (agent castU) research, Teams' bundles (26304 + ha):
  - Mic during a cast: Teams' cast intent joins with outgoingAudio/incomingAudio false, i.e. its content-only mode (mic and speaker muted, isContentOnlyMode). The unified-bar Mic button is never disabled for it: isAudioOff (contentOnly or mic and speaker both off) shows the "speaker-mute" glyph, tooltip calling_confirm_audio_escalation_tooltip "Turn audio on", and toggleMuteInternal opens the confirm-audio-escalation dialog ("Turn audio on?", call/meeting text, Cancel / Turn audio on); on the presenter toolbar it unmutes directly, in the call monitor it shows the call window, in a shared audio group (selfMeetingSpaceGroupDetails) it unmutes without asking. Confirm = toggleMuteAudio(Unmute, audio-escalation-dialog-multiwindow), which also unmutes the speaker (content-only mode ends).
  - Hidden in-room attendees: VideoLayoutItem.shouldHideItemInSameRoom = enableUnhideOtherRoomParticipants ? (shouldHideSameRoomParticipants && isInSameRoom && !isHandRaised) : (isInSameRoom && !isHandRaised). The flag is only ever set true (UnhideRoomParticipantsUfd's Hide Attendees); no string or UI sets it back. Stage checkers: PinStage takes pinned/spotlighted items regardless, MixedStage shows hidden ones when pinned or spotlighted.
- Verified on winpc (Teams cast to OST Test Room, room mode on linuxlt): Mic showed the speaker-mute glyph, tooltip "Turn audio on (Ctrl+Shift+M)"; clicking opened "Turn audio on?" (600 x 164.67 CSS, text wrapped as OST's); Turn audio on -> mic unmuted (and speaker on); muting again showed the normal mic-off. After Hide Attendees: View menu (Gallery/Speaker/Full screen/Focus/Show gallery at top/Gallery size/Turn off other videos/Show videos first), People pane and the room row menu (Mute participant/Pin for me/Spotlight for everyone/Control Room System/Make an attendee/Remove/Report) have no show option; Pin for me brought the room back to the stage, Unpin hid it again. A later cast in the same Teams session showed the room and the Joined in room alert again (hide is per call).
- Built: Mic stays usable without audio (Teams' speaker-mute glyph, filled in the old controls; "Turn audio on" tooltip); pressing it (bar, Ctrl+Shift+M, Alt+A, audio flyout/pane) asks "Turn audio on?" (ConfirmDialog 600 wide, call/meeting text); the sharing control bar turns audio on at once; the compact call monitor opens the call window. Backend turn_audio_on: media unheld (unless the call is on hold), has_audio on, unmuted. In-room hiding now follows shouldHideItemInSameRoom (raised hand shows them; ECS enableUnhideOtherRoomParticipants false hides always); pinning/spotlighting already shows them via the pin area. Speaker view with nobody else shown falls back to your own tile (was a TypeError).
- Live OST (ost-test1 on linuxlt casting a window to OST Test Room via the relayed beacon, --cast-test --cast-room-checks, run c2): Mic before {hasAudio false, muted, enabled, speaker-mute-20-filled, "Turn audio on"}; pressed -> dialog shown; Turn audio on -> {hasAudio true, unmuted, call-mic-filled}; muted again -> call-mic-off; Joined in room alert shown; Hide Attendees -> stage shows nobody but you; Pin for me on the room -> pinned; unpin -> hidden again. Room auto-accepted, window shared (portal restore, no picker). Run c1 (room joined but the caster got no roster update that run) captured the Mic and dialog screenshots, matching Teams'.

- Caveat: in c2 the call window was minimized while sharing (as Teams'), so the hidden/pinned stage wasn't screenshotted; the stage state came from the logs (pinned id set, room hidden from the gallery list); the pinned room's tile comes from the existing pin area (pinArea takes callWindow.others, unfiltered).

- Tests (linuxlt): cargo test --features audio,video --lib 950 passed; desktop 37 passed. Cleanup: both OST cast runs left their calls (CAST done + call ended) and exited; the room left each meeting by itself (Call end 202) before it was stopped; beacon gone (hci0 ActiveInstances 0); relay, btvirt pair and test window stopped; portal restore tokens deleted; dumps removed. winpc: Teams ost-test1 on Chat, in no call, Cast window closed; test window, scheduled task and script removed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
During a cast the Mic now behaves as in Teams, and hidden in-room attendees come back in the ways Teams allows. Both were checked against Teams on winpc during a cast to OST Test Room.

What Teams does (from its bundles, confirmed on winpc):
- Cast joins in Teams' content-only mode, with mic and speaker off. The Mic button stays enabled. It shows a speaker-mute glyph and the tooltip "Turn audio on (Ctrl+Shift+M)".
- Clicking the Mic asks "Turn audio on?" with Cancel and Turn audio on. Turning audio on unmutes both the mic and the speaker.
- From the presenter toolbar, the same button turns audio on without asking. From the call monitor it opens the call window instead.
- Teams has no "show" option after Hide Attendees: none in View, People or the room's menu. A hidden attendee comes back only when pinned or spotlighted, or when they raise a hand, and the hide lasts only for the current call.
- On winpc, Pin for me brought the room back, unpinning hid it again, and the next cast showed the room and the alert again.

Changes (commit 71b8120b):
- Mic without audio: Teams' speaker-mute glyph (filled in the old controls), the "Turn audio on" tooltip, and the "Turn audio on?" dialog (600 x 164.67, as measured). The dialog opens from the bar, Ctrl+Shift+M, Alt+A and the audio flyout/pane.
- The sharing control bar turns audio on at once; the compact call monitor opens the call window instead.
- New backend turn_audio_on: restores media unless the call is on hold, sets has_audio and unmutes.
- In-room hiding follows Teams' shouldHideItemInSameRoom: a raised hand shows them, and the ECS flag enableUnhideOtherRoomParticipants=false hides them always. Pinned and spotlighted attendees already show through the pin area.
- Speaker view with nobody else shown now falls back to your own tile (it threw a TypeError before).
- New harness flags --cast-test --cast-room-checks.
- i18n ids regenerated (including TASK-0268's strings).

Verified live with ost-test1 on linuxlt casting a window to OST Test Room:
- Mic: enabled, speaker-mute glyph, "Turn audio on" → dialog → unmuted with audio on → muted again.
- Joined in room alert → Hide Attendees → Pin for me → unpin.
- The dialog matched Teams' layout.

Tests: lib 950 passed, desktop 37 passed.

Open:
- The stage with a pinned hidden room wasn't screenshotted, because OST minimizes the call window while sharing, as Teams does. Only its state was logged.
- Teams' "Control Room System" item on the room row isn't in OST.
<!-- SECTION:FINAL_SUMMARY:END -->
