---
id: TASK-0344
title: Join with a meeting ID fails when the lobby holds you
status: Done
assignee:
  - '@meet'
created_date: '2026-11-27T04:51:00Z'
updated_date: '2026-11-27T06:46:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0342 (2026-11-26): with the Meet-now meeting set to Only organizers and co-organizers bypass the lobby, OST Test 3 joining by meeting ID and passcode failed twice with "We couldn't find a meeting with that ID and passcode." The log said "join with an ID: The meeting's conversation named no thread" (signaling.rs, the meeting-code conversation lookup). The same meeting joined fine by its meetup-join link and waited in the lobby, and by ID whenever the lobby didn't apply.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Joining by meeting ID and passcode reaches the lobby when the meeting holds you there, as Teams does, verified live
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read how Teams joins with an ID (MeetingDataCoordinates: joinType MeetingData, meetingData {meetingCode, passcode, meetingUrl}, no thread).
2. When the resolve names no thread (the lobby holds us), join the conversation and then the call by meetingData, and take the chat from the update that admits us.
3. Verify live: OST Test 3 by ID into a lobby-held test meeting, admitted by the OST organizer; compare with Teams desktop on testpc1.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: Join with an ID resolved the meeting by joining its conversation with meetingData, reading the thread, leaving, then joining by link. While the lobby holds you, that answer names no thread (and no subject), so the join stopped with "The meeting's conversation named no thread".
- Teams: Join with an ID joins with coordinates {joinType: "MeetingData", meetingData: {meetingCode, passcode, meetingUrl}}, with no thread up front. On testpc1 (Teams desktop as ost-test1, 2026-11-26) the pre-join was titled "Microsoft Teams meeting". It waited in the lobby, was admitted by the OST organizer, and the window then showed "OST TEST 344" with its Chat.
- Fix:
  - With no thread, resolving hands back the meeting's short link, and the join parses it as a meeting known by its ID (MeetingLink::parse_short, meeting_data).
  - The conversation and then the call go out with meetingData, without groupChat or meetingInfo.
  - On admission the call adopts activeModalities.groupChat.threadId. The call window opens that chat and titles the meeting with the chat's topic.
  - The "ongoing call" lookup is skipped while the thread is unknown.
  - QML joins short links instead of opening them in a browser.
- Verified live, 2026-11-26: test meeting "OST TEST 344" (organizer OST Test 2) with AutoAdmittedUsers set to OrganizerOnly (was EveryoneInCompany; restored, read back, and the meeting deleted afterwards).
  - OST Test 3 joined by ID and passcode: "no thread before the lobby; joining by meetingData", then the call carried meetingData and waited in the lobby.
  - OST Test 2 admitted it (--join-admit-each). The chat was named on admission (the meeting's own thread; its members loaded), and the title became "OST TEST 344".
- Harness: --join-admit-each admits everyone who waits; the --join-lobby-wait log shows chat and title.

- Codex review (PR #33):
  - The chat a short-link join names without a lobby wasn't copied to the call window.
  - After admission, the meeting kept its short link, so its options link and Controls stayed empty.
- Fixed with one step for both paths (adopt_meeting_chat: the join's answer via JoinedView, and the admitting update). It sets the chat and loads its members, then reads the chat's properties: the topic for the title, and the `meeting` property's join link (or organizer and tenant) for the full join link. That gives the options link and loads Controls.
- Re-verified live with "OST TEST 344b" (lobby OrganizerOnly, restored to EveryoneInCompany and read back, meeting deleted): after admission, chat true, title "OST TEST 344b", options true.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Joining a meeting by its ID and passcode now works while the lobby holds you. You wait in the lobby, and once let in the meeting's chat and title appear, as in Teams desktop.

Cause: OST resolved an ID to the meeting's thread before joining. A lobby-held participant isn't told the thread until admitted, so the join failed with "We couldn't find a meeting with that ID and passcode."

Changes:
- `MeetingLink` can be a meeting known only by its ID (`meeting_data`; `parse_short` for teams.microsoft.com/meet/<ID>?p=… links, `parse_join` for either kind).
- With no thread, the meeting's conversation and then its call are joined by `meetingData`, without groupChat or meetingInfo (Teams' joinType MeetingData).
- On admission the call takes the chat the update names. The call window opens it and titles the meeting with its topic.
- No "ongoing call" lookup without a thread.
- QML joins short links rather than opening them externally.
- Spec (calendar.md) updated; unit test for short links.

Tests:
- cargo test --features audio,video --lib -- calling::outgoing calling::signaling
- Live with OST Test 3 by ID into a lobby-held test meeting (OST Test 2 organizer admitting): lobby, admission, chat and title.
- Teams desktop on testpc1 compared.

Review follow-up: the chat, title and full join link (meeting options, Controls) are taken the same way whether the join names the chat or the admission does; re-verified live.
<!-- SECTION:FINAL_SUMMARY:END -->
