---
id: TASK-0073
title: Facilitator agenda timer and Run of Show as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T09:29:00Z'
updated_date: '2026-11-20T23:22:00Z'
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
- [ ] #2 Run of Show in a town hall or webinar shows and behaves as Teams'
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (dde4544): More > Facilitator > Turn on/off Facilitator and Enable/Disable voice with Teams' requests (ost-test1's Copilot licence is enough); checked live on and off.

Not built: the agenda timer never appeared in Teams in this tenant (its setting to start an agenda yourself is off), so there is nothing to compare against; Run of Show needs a town hall or webinar with Facilitator (TASK-0184); Facilitator ▾ with the new controls.

- Run of Show (#2): Teams only enables it for internal test builds; the town hall form has no Run of Show setting in this tenant (TASK-0184, 2026-11-16).

- 2026-11-20 (callsC) research (scratchpad c073/agenda.md, strings c073/strings-en.tsv; timer bundle unchanged since timer/raw.js): with the live ECS (enableAgendaTimer true, enableAgendaUbar unset = false, enableMeetNowFaAgendaTimerDisabled true) nobody can start an agenda in Teams: the agenda view shows only when the shared agendaTimer is not Cancelled or a Facilitator draft is pending consent (organizer/co-organizer fetches it over AugLoop Meeting_Agenda_Draft_Fetch; Share = Meeting_Agenda_Submit {topics:[{subject,duration ms,subtopics:[]}]}, Dismiss = Meeting_Agenda_Reject; signal AugLoop_TeamsMeetingAgenda_TeamsMeetingAgendaUISignal). pendingConsent/consentRequested/relevanceScore are written by the service. So a live check needs a scheduled (not Meet now) meeting with Facilitator on whose Facilitator drafts an agenda.

- 2026-11-20 (callsC): not built further this session (time went to 0235/0199/0225). Next step: a scheduled meeting (not Meet now) with an agenda in its invitation, Facilitator turned on in Teams on winpc, to see whether the Facilitator drafts an agenda (pendingConsent preview with Share/Dismiss over AugLoop); only then can the agenda view be built and compared. Run of Show stays out of reach (Teams enables it only for internal builds; no Run of Show setting on the town hall form in this tenant).
<!-- SECTION:NOTES:END -->
