---
id: TASK-0018
title: Echo test call sometimes returns no audio
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T03:22:00Z'
updated_date: '2026-11-10T16:26:00Z'
labels:
  - calling
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
About 1 in 5 Echo bot calls (call-test --echo --tone) gets ICE and signalling through but receives 0 RTP: the bot's RTCP SR shows pkt_count=0 for the whole call. In the one failure seen after the SSRC fix (2026-11-04), the bot's x-ssrc-range started at 1000; in every successful call it started at 1101 or higher. That may be coincidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Root cause of the silent calls is identified from logs or packet capture
- [x] #2 10 consecutive Echo calls each return audio containing the echoed test tone
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Root cause: in the silent calls the Echo bot never answered. The SSRC range was a symptom, not the cause.

What happens: the 1:1 call POST returns 201 Created instead of 200 OK with the bot's answer. About 10 s later the call controller sends the acceptance for a hostless ad-hoc meeting (`state.isMultiParty: true`, `isHostless: true`, `conversationType: "adHocMeeting"`). Its roster (the conversationUpdate frames) holds only the caller. The SDP answer then comes from the media processor (audio SSRC 1000, video 1001–1100), whose RTCP reports `pkt_count=0` all call long, because nobody else is in the conversation. In answered calls the bot's own SSRCs appear (1101, 23203, 45305…). Reproduced on the first call of this session, by comparing logs.

Fix:
- `signaling::acknowledge_call_acceptance` returns the acknowledgement body.
- New `became_hostless_meeting` recognises the fallback. call-test then prints `callee_never_joined=true`, hangs up and redials (up to 3 attempts), as a person would.
- recording.rs and outgoing.rs are adapted to the new return type.

Tests:
- New `an_unanswered_echo_call_is_recognised`, built from the real acknowledgement.
- 10 consecutive `call-test --echo --tone -d 30` calls all reported echo_detected=true (correlation 0.995–0.999, 710–1032 audio packets back). The first one hit the unanswered case and its redial worked.
<!-- SECTION:FINAL_SUMMARY:END -->
