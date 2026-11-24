---
id: TASK-0234
title: Town hall Event group chats as Teams
status: Done
assignee: []
created_date: '2026-11-20T04:10:00Z'
updated_date: '2026-11-20T23:13:00Z'
labels:
  - chat
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0142's winpc comparison: Teams handles a town hall's Event group chat differently from a meeting chat: it titles it "Event group: <title>", says people "joined the Event Group Chat…", and shows "<title> has started." / "<title> has ended." instead of "Meeting ended:". OST shows these chats like any meeting chat.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A town hall's Event group chat shows Teams' title, join line and started/ended rows, in every app language, verified against Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chat agent), measured on winpc ("Event group: OST TEST 217 town hall 2") and read from Teams' code:
  - A backroom chat is a thread with `meetingChatType` "Backroom"; a town hall's or webinar's (meeting templateDetails.id = the town hall or webinar template, Teams' isTownhall / isWebinar) is titled "Event group: {title}" (messaging:k6wwmex4q, event_backroom_chat_title_prefix), a meeting's "Planning group: {title}" (k21d43hht). Its avatar is the calendar-lock glyph (data-testid backroom-chat-icon).
  - Joining: "{name} joined the Event Group Chat: {title} for organizers, presenters, and people helping with the event." (tmp_messages_memberJoinedOneMemberEventBackroom, k69befoe9 plain / kc2rbbia0 rich); added by someone: OneTarget k899lqo1k, TwoTargets kd1b5sjah, ManyTargets k7kl5h3i0; the meeting variants ("…the Planning Group: … helping with the meeting.") k59mdytpy / kc7do3qud / k8bbbov2 / k5ke58ztx.
  - Calls: "{title} has started." (tmp_messages_backroom_call_event_started, k15ntfp7n; meeting kd3dbdxsw) and "{title} has ended." + the bold duration (k-ids kqok16p0 / meeting k3flolqwp), after the time as other call rows.
- Built: api::chat::backroom_kind / backroom_title / backroom_of (ChatInfo.backroom + topic, chat JSON backroom/topic), messages::backroom_event_text, Conversation call rows, the calendar-lock avatar in the chat list and header. Strings carry Teams' ids (l10n gen still to be run for ids.json).

- 2026-11-20 (chatB): the join lines are now Teams' shown (rich) strings, picked as Teams' module 121919 `Ma` does: self-join tmp_messages_memberJoinedOneMember{Event,Meeting}Backroom (kc2rbbia0 / k8tfy1qp9), added by someone addMemberSystemMessage{OneTarget,TwoTargets,ManyTargets}{Event,Meeting}Backroom (kd2pf534f, kcux3ubsg, k69ip80jz / kd4z24g30, k5hlqlh91, kajtcnui4), "{n} others" from tmp_messages_otherTargets_mf. They were written with format!() before, so l10n gen never keyed them; now literal and in ids.json, translated in all 63 of Teams' string locales. Checked in German on linuxlt (ost-test1, app language de-de): "OST Test 1 ist dem Veranstaltungsgruppenchat OST TEST 217 town hall 2 für Personen, die organisieren, präsentieren und bei der Veranstaltung helfen, beigetreten." and the title "Ereignisgruppe: OST TEST 217 town hall 2".

- 2026-11-20 (chatB), compared with Teams on winpc: adding OST Test 3 to "Event group: OST TEST 217 town hall 2" (ost-test1 adding someone else) shows Teams' plain "OST Test 1 added OST Test 3 to the chat.", not the Event Group sentence: Teams (121919) uses the backroom sentence only for a self-join or when the adder is among those added (`p`), else the meeting chat's added line without shared history. OST now does the same (ChatEvent.actor_added; unit test event_group_join_lines_as_teams) and showed the same line live; the two-person and "and {n} others" sentences arise only in the adder-included case (the event service's adds), checked by unit tests and in all 63 locales' strings. OST Test 3 removed from the chat again afterwards.

- 2026-11-20 merged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Town hall Event group chats as Teams: "Event group: …" title, calendar-with-lock icon, join line and started/ended rows. The join lines now use Teams' string ids in all 63 locales (German checked live); when someone else adds people OST shows Teams' plain "X added Y to the chat.", the joined form only when the adder is among those added (verified on winpc; unit tests). OST finds these chats by asking the chat service once per meeting chat, as the chat list lacks the field.
<!-- SECTION:FINAL_SUMMARY:END -->
