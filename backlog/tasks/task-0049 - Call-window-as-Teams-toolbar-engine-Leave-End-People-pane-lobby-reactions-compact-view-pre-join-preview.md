---
id: TASK-0049
title: >-
  Call window as Teams: toolbar engine, Leave/End, People pane, lobby,
  reactions, compact view, pre-join preview
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-11T04:48:00Z'
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
- [x] #1 Toolbar built from Teams' layout config per call type with tooltips and width-driven overflow into More
- [x] #2 Leave ▾ (Leave / Leave on all my devices / End meeting with confirmation) per role
- [x] #3 People pane sections, sort, search and invite field as Teams
- [ ] #4 Lobby on both sides (waiting screen; Admit/Deny/Admit all and the lobby toast)
- [x] #5 Send and receive meeting reactions
- [x] #6 Compact view window when minimised; pre-join live camera preview
- [x] #7 Teams' call keyboard shortcuts: Ctrl+Shift+M, Ctrl+Shift+O, Ctrl+Shift+K, Ctrl+Shift+E, Ctrl+Shift+H, Ctrl+Space and Ctrl+Shift+Y
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

- 2026-11-08: compact view (call monitor) built to winpc measurements; verified through XWayland (Wayland doesn't report minimised windows). Pre-join live camera preview still open for #6.

- 2026-11-08: pre-join live camera preview and joining with the camera on (11dceeb).
- 2026-11-08: participant ··· menu (Mute participant, Pin for me, Spotlight for everyone/Stop spotlighting, Make an attendee/presenter, Remove from meeting) to winpc measurements; spotlight 200/stop 200 and role 202 verified live against the roster (c2b4b17). Report is left to its own task (no real reports may be filed while testing).

- 2026-11-08: People pane completed (ab02ff6): More actions menu (Mute all, attendee mic/camera, Lower all hands, attendance list, Stop all spotlights, Lock/Unlock) with Teams' dialogs and notices; Presenters/Attendees sections; raised-hand sort, rank and emoji; "Change role?" confirmation. All requests verified live (202/200). Report on a participant is left to its own task.

- 2026-11-08: bar from Teams' layout config (Rust engine over ubarLayoutPresets/Overrides): layout per call type, overrides, dividers, Fluent overflow with its 10 px padding (measured by resizing winpc's window), overflowed controls at the top of More with Teams' menu texts, Teams' tooltips. Shortcuts: Ctrl+Shift+M, K, H and Ctrl+Space verified live with a uinput keyboard; Ctrl+Shift+O and E bound the same way (no camera on linuxlt; E opens the share picker).
- More's own items beyond Video effects and settings / Audio settings are TASK-0062.

- 2026-11-08: OST held in a lobby: pre-join InLobby state and admission handling (protocol from a Teams web guest's capture, unit-tested). Not verified live: ost-test1 organizes the test meeting and organizers bypass the lobby, so AC #4 stays open until a second, non-organizer test account exists (the user creates/signs in test accounts).

- 2026-11-10: lobby verified live from the waiting side with OST Test 2 (09672de): held in the lobby of OST Test 1's meeting (Meeting options: only organizers bypass), Teams desktop's toast admitted it into the same meeting, and Deny ended its call. Fixed on the way: joins now send meetingInfo {tenantId, organizerId} from the link (OST had been starting a separate ad hoc meeting for non-organizers). Also the two-person me-tile overlay as Teams.
- Still open for #4: what a denied (or long-unadmitted) person sees. Teams shows its call-ended screen ("Sorry, but you were denied access to the meeting.", ban icon; "Sorry, no one has responded to your request to join. Please try again."); OST just closes. See the call-ended screens task.
<!-- SECTION:NOTES:END -->
