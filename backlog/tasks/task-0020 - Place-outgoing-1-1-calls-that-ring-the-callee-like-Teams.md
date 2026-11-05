---
id: TASK-0020
title: Place outgoing 1:1 calls that ring the callee like Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T05:38:00Z'
updated_date: '2026-11-05T15:24:00Z'
labels:
  - calling
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outgoing calls from OST must ring the other person and connect peer to peer, as a Teams 1:1 call does.

Findings (2026-11-05):
- epconv create_1to1_call with groupChat.threadId creates a server-hosted conversation (conversationType adHocMeeting). The media mixer accepts at once (callAcceptance.mediaContent.fromMixer = true), so "answered" is not the callee.
- With participants.to = [] plus an explicit /add invite (202), Teams web later showed "Call missed", but no ring toast was seen. With participants.to = [callee], the service rejected it with 409 ("failure to resolve ownership") while an earlier ad-hoc call in the thread was still alive; once that cleared, it again accepted from the mixer without a visible ring.
- Incoming calls from Teams web arrive as forked callNotification (evt 107) with isMultiParty=false, so Teams 1:1 calls are not mixer-hosted. Find the request Teams web uses to start one (calling-pluginless bundle: createConversationRequest / call to the CC) and mirror it.
- The WebRTC audio side is ready: LocalAudio::offer_sdp (actpass) and WebRtcAudioSession::start_as_offerer (ICE controlling, DTLS server or client) have unit tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Calling a user from a 1:1 chat rings their Teams client
- [x] #2 OST shows Calling until the callee answers, then connects with two-way audio
- [x] #3 Declined, unanswered and cancelled calls end cleanly on both sides
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Outgoing 1:1 calls now ring the callee as a peer-to-peer Teams call and connect with two-way DTLS-SRTP audio.

Changes:
- No groupChat in the create request when there is a named callee (that made it a chat-hosted meeting).
- Trouter reply to the callAcceptance push carries callAcceptanceAcknowledgement (synchronous Trouter response); without it the Call Controller ended the call after 30 s with 408/10056.
- Removed the callback re-registration on the call leg.
- Hang-up while ringing leaves the conversation (487); 60 s no-answer leaves with 408.
- Call button ungated.

Tests:
- cargo test --workspace (150 passed), including new trouter and leave-link tests.
- Live with Teams web: ring, answer, audio past 30 s, hang-up from either side, decline goes to voicemail, cancel while ringing removes the toast.
<!-- SECTION:FINAL_SUMMARY:END -->
