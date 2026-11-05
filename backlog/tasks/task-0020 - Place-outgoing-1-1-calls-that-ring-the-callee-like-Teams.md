---
id: TASK-0020
title: Place outgoing 1:1 calls that ring the callee like Teams
status: To Do
assignee: []
created_date: '2026-11-05T05:38:00Z'
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
- [ ] #1 Calling a user from a 1:1 chat rings their Teams client
- [ ] #2 OST shows Calling until the callee answers, then connects with two-way audio
- [ ] #3 Declined, unanswered and cancelled calls end cleanly on both sides
<!-- AC:END -->
