---
id: TASK-0049
title: >-
  Call window as Teams: toolbar engine, Leave/End, People pane, lobby,
  reactions, compact view, pre-join preview
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-08T17:19:00Z'
labels:
  - calls
  - meetings
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Call window P1 gaps (docs/parity/gaps-calls-meetings.md), per docs/spec/call-and-meeting-window.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Toolbar built from Teams' layout config per call type with tooltips and width-driven overflow into More
- [x] #2 Leave ▾ (Leave / Leave on all my devices / End meeting with confirmation) per role
- [ ] #3 People pane sections, sort, search and invite field as Teams
- [ ] #4 Lobby on both sides (waiting screen; Admit/Deny/Admit all and the lobby toast)
- [x] #5 Send and receive meeting reactions
- [ ] #6 Compact view window when minimised; pre-join live camera preview
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-07: Lobby, organizer side, built and verified live against Teams desktop on winpc with two anonymous guests from linuxlt:
  - People pane rebuilt to measurements (360 wide, 58 px header, Type a name search that filters, 38 px section headers with chevrons, 48 px rows).
  - Waiting in lobby (n), split into Waiting / Suspected threats when join shield flags a guest; Admit all, Admit (n) and Deny (n) per Teams rules.
  - Unverified badge and Teams' eight guest avatars, picked by Teams' id hash (verified: same colours as Teams).
  - Admit ✓ / Deny ✗ (Deny = removeParticipant; the guest sees "you were denied access").
  - Admit of a suspected guest asks "Admit this unverified bot?"; "This isn't a bot" posts participantScreening isBot:false (markedBy admitter) to updateParticipantProperties; verified in the roster.
  - Lobby toast with Teams' button rules (Deny/Admit; Deny/View Lobby for bots; View Lobby for more), mute for the rest of the meeting with an 8 s Undo confirmation, dismiss until the lobby changes.
  - People button red badge (18 px, #C50F1F, 2 px white ring).
- Still open in this area:
  - Share invite dialog (needs the meeting short link teams.microsoft.com/meet/<id>?p=<passcode>).
  - Participants ··· menu.
  - People added to the chat section.
  - Single-person toast "More info" link offsets.
  - Dark-mode values for the lobby UI (only light measured).
  - The waiting-in-lobby screen when OST itself is held in a lobby.

- 2026-11-07: Call toolbar rebuilt to measurements (slots, glyphs, hover, checked line, Leave group).
- Leave ▾ menu (Leave; End meeting for the organizer) with the "End the meeting?" confirmation; End meeting verified live (DELETE conversationController, HTTP 204, everyone dropped).
- "Leave on all my devices" not seen in Teams' menu with a single device; needs a two-device test.
- Camera/Mic chevrons (device flyouts) still to do.

- 2026-11-08: Leave on all my devices (removeParticipant scope "all" with our endpoint, then leave) shown with 2+ of your devices, measured and verified with winpc. Reactions done as TASK-0035.
<!-- SECTION:NOTES:END -->
