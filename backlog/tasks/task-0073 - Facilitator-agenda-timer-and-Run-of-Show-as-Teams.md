---
id: TASK-0073
title: Facilitator agenda timer and Run of Show as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T09:29:00Z'
updated_date: '2026-11-21T05:55:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' meeting timer also has an agenda timer (Copilot Facilitator drafts topics; add, rename, delete, reorder, resize, mark discussed, share with consent) and Run of Show (town halls and webinars). Both need Facilitator on (meetingCapability.groupCopilotDetails.enabled); the test tenant has it off, so Teams shows neither there. OST keeps their shared state untouched. Spec: scratchpad timer/spec.md §8–9 (session 744c3998).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With Facilitator on, the agenda timer shows and edits as Teams', verified against Teams in a Facilitator-enabled meeting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (dde4544): More > Facilitator > Turn on/off Facilitator and Enable/Disable voice with Teams' requests (ost-test1's Copilot licence is enough); checked live on and off.

Not built: the agenda timer never appeared in Teams in this tenant (its setting to start an agenda yourself is off), so there is nothing to compare against; Run of Show needs a town hall or webinar with Facilitator (TASK-0184); Facilitator ▾ with the new controls.

- Run of Show (#2): Teams only enables it for internal test builds; the town hall form has no Run of Show setting in this tenant (TASK-0184, 2026-11-16).

- 2026-11-20 (callsC) research (scratchpad c073/agenda.md, strings c073/strings-en.tsv; timer bundle unchanged since timer/raw.js): with the live ECS (enableAgendaTimer true, enableAgendaUbar unset = false, enableMeetNowFaAgendaTimerDisabled true) nobody can start an agenda in Teams: the agenda view shows only when the shared agendaTimer is not Cancelled or a Facilitator draft is pending consent (organizer/co-organizer fetches it over AugLoop Meeting_Agenda_Draft_Fetch; Share = Meeting_Agenda_Submit {topics:[{subject,duration ms,subtopics:[]}]}, Dismiss = Meeting_Agenda_Reject; signal AugLoop_TeamsMeetingAgenda_TeamsMeetingAgendaUISignal). pendingConsent/consentRequested/relevanceScore are written by the service. So a live check needs a scheduled (not Meet now) meeting with Facilitator on whose Facilitator drafts an agenda.

- 2026-11-20 (callsC): not built further this session (time went to 0235/0199/0225). Next step: a scheduled meeting (not Meet now) with an agenda in its invitation, Facilitator turned on in Teams on winpc, to see whether the Facilitator drafts an agenda (pendingConsent preview with Share/Dismiss over AugLoop); only then can the agenda view be built and compared. Run of Show stays out of reach (Teams enables it only for internal builds; no Run of Show setting on the town hall form in this tenant).

- 2026-11-20 (callsC) live: scheduled "OST TEST 73 agenda" in Teams (ost-test1, OST Test 2 invited, agenda of four timed topics in the invite, "Facilitator is on for this meeting"). On joining, transcription started automatically per the organizer setting, the Facilitator joined and posted in the chat "Here's the agenda from the invite:" (card with Add topic / Add agenda), and Teams' strip showed the agenda at once (no pending-consent preview: Welcome 5:00, Project status review 10:00, Budget questions 10:00, Next steps 5:00, + Add topic and ▾ More options = Add topic / Cancel tracker; a click opens the editor: title box, "Mark … as discussed", Delete topic; discussed = filled check circle; nothing shown for undiscussed in this build; ChevronUpDown switcher left). Measured (scratchpad c073/strip.json, pop.json; shots c073/t*.png).
- Built: AgendaTimerRow.qml in the timer strip (switcher with Ad-hoc timer / Agenda timer, 35 px slide; topics sized by duration, elapsed fill from the left, last topic fading red, all red over time, current topic countdown, durations, discussed check / reorder dots on hover, tooltips, resize handles with drag and keyboard, drag / Shift+Alt+arrow / Move left|right reorder, topic editor with rename (dedupe, Unnamed Topic, required error), mark discussed, delete, Add topic split button, Cancel tracker for all? dialog, read-only click toggles discussed); src/calling/agenda.rs (Teams' add/delete/rename/resize/move/discussed algorithms, tested); backend agenda_edit publishes {adhoc, agenda, ros} with the last sequence; CallWindow opens the strip on the agenda when it starts and closes it when cancelled.
- Verified live (OST spatest ost-test1 + Teams on winpc, same meeting): OST showed the same agenda (state, topics, widths, current topic countdown, fill); Teams' Mark discussed reached OST within a second; OST's and OST Test 2's edits (discussed, resize) were accepted by the meeting (sequence advanced, the other OST client showed them) but the Teams desktop client did NOT update its strip for them. Open: why Teams ignores agenda writes made through the conversation's updateMeetingStates link (Teams writes via its updateMeetingTimer GraphQL path); needs a capture of what Teams receives.
- Run of Show: Teams enables it only for internal builds; recorded, not built.

- 2026-11-20: Run of Show is enabled only in Teams' internal builds (its flag is off for released Teams), so it isn't part of the Teams OST matches; AC removed and recorded on the Remaining Work page. AC1 open: Teams' strip doesn't show agenda edits made from OST (OST clients see each other's); capture what Teams receives.

- 2026-11-21 (callsC) OST → Teams sync, live in "OST TEST 73 sync" (Teams ost-test1 on winpc as organizer, Facilitator on; OST Test Room on linuxlt with the `room` profile; cancelled afterwards):
  - Teams 26304's meeting state can't be seen on the network from the page (signalling is native), so Teams' strip state was read from React (props of the strip) once a second while OST wrote.
  - OST's writes reach Teams: every edit from OST Test Room (discussed, undiscussed, resize) appeared in Teams' strip state within a second, and resizes and OST's ad-hoc timer (start, running count, pause) show in Teams' strip.
  - Cause of the missing check marks: this Teams build decides "discussed" by the topic's lifecycle (`topicLifecycleUserOverride` over `topicLifecycleStage`, values NotStarted / Done; the Facilitator writes stages on every topic) and ignores `isDiscussed` when a stage is set. Teams' own Mark discussed writes isDiscussed and topicRelevanceUserOverride true, topicLifecycleStage "Done" and topicLifecycleUserOverride "Done"; unmark writes NotStarted and drops the override. Topics with no known stage (tried "InProgress") are shown the older way: an empty circle until discussed, "Discussed / Not discussed".
  - Fixed: agenda.rs reads and writes the lifecycle as Teams does; AgendaTimerRow shows the lifecycle (no marker for Not started, check for Done; the empty circle for topics without a stage) and its spoken status. Verified: OST Test Room's mark showed in Teams as "Welcome, Done…" within a second and its unmark as "Not started".
  - The earlier misses with spatest (ost-test1, the same account as Teams) were most likely this lifecycle issue too; the same-account check itself was not run (spatest was busy).
<!-- SECTION:NOTES:END -->
