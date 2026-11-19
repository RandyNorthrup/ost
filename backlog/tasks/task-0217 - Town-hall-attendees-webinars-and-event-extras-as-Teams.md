---
id: TASK-0217
title: Town hall attendees, webinars and event extras as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-17T06:06:00Z'
updated_date: '2026-11-19T11:28:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0184 left (docs/spec/town-halls-and-webinars.md):
- Town hall attendees: Teams streams the event from a service bot in the meeting and plays it in its own player; OST's attendee join gets no answer. The service bot ("s04-prdnoamcompsvc") shows on OST's stage and in People; Teams' rule for hiding it isn't traced.
- Webinars run live; OST's own Publish and Join on the event page; the attendee staging screen and post-end alert live; Bring on screen with a second presenter.
- Not built: "On with preview", Preview as attendee and Join as Organizer / Presenter, Calendar > New > Webinar / Town hall, Copy embed code, Show event in Events app, the published card's Live badge, Join and share; the Start / End buttons' and Live pill's measured styling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Town hall attendees watch the event in OST as in Teams, and the service bot is hidden as Teams hides it
- [ ] #2 Webinars are scheduled, joined and run in OST, checked live
- [ ] #3 The event extras listed above work and look as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-18 (agent TASK-0217): measured Teams desktop on winpc over CDP as town hall attendee, organizer and webinar attendee; spec §7 in docs/spec/town-halls-and-webinars.md.
- Town hall attendees: streaming mode from the roster (`stream` on our endpoint), the composition bot's HLS stream (fMP4, AES-128, key with the bare keyAuthorizationToken) played natively via calling::live_stream (loopback proxy + Qt Multimedia, LiveStreamPlayer.qml); verified live: OST Test 2 played OST TEST 217 town hall 2 (player playing, stream shot att4-event-stream-30.png).
- Composition bot hidden by Teams' blacklistedBots list (+ botData.hiddenParticipant).
- streamingClient bar layout, Waiting/Live/Ended pill and Start event/End event as measured; Preview as Attendee + Join as Organizer/Presenter split (participationPreferences attendee); Calendar New > Webinar/Town hall; published dialog (card preview, Show event in Events app = PATCH isDiscoverable with eTag, Copy embed code); card Live / in N mins badges and Join.
- Webinar OST TEST 217 webinar run live: OST Test 2 organized in OST (start/end), OST Test 3 presenter in OST, ost-test1 attended in Teams (LIVE, then "The event has concluded. Thank you for attending."). All three test events cancelled.

- Also verified: Preview as Attendee from OST (ost-test1 organizer of OST TEST 217 town hall 3) joined as a streaming attendee (Waiting bar, curtain). Lib tests 758 passed on linuxlt.
- Open: (1) when OST is the organizer who starts the event, a streaming attendee lost the call (Teams attendee in run 1, OST Test 2 in run 3) while Teams starting it kept them: compare OST go-live with Teams; (2) Bring on screen with a second presenter not rechecked live (test webinar was not HostMode); (3) webinar registration not built; (4) On with preview and the Manage screen panel not built; (5) Virtual appointment / Live Event not built; (6) the pre-join split menu needs the preheat to finish, not yet seen on screen; (7) OST Test 3 keeps cancelled OST TEST 217 webinar entries.

- Merged 7120e0c/c38329a (2026-11-19): build OK, 758 lib tests passed. Town hall attendee streaming verified live; webinar run live; extras partly built. Open: organizer start drops attendees, Bring on screen, waiting screen, registration, On with preview, Manage screen, New menu items.
- Handoff for the follow-up items (coordinator list, 2026-11-18):
  - Go-live drop: Teams desktop's signaling is native (SlimCore), so CDP on winpc shows only JS; Teams' go-live JS is calling-app meetingGoLive (ufd stage-curtain, 3 s, updateMeetingLiveState). Teams starting it kept OST Test 2 streaming; OST starting it dropped attendees (Teams attendee run 1: call ended at go-live; OST Test 2 run 3: "call ended by the other side" 06:16:42Z, before the start, so run 3 may be a separate join-time drop). Compare OST's live_state_body/curtain_state with Teams' meetingGoLive payload in calling-pluginless (updateMeetingLiveState request) and the ufd publishState body.
  - Tools: examples/virtual_event (create/publish/cancel/purge, test accounts only); scratchpad th/cdp.mjs (read-only CDP: list, js, net browser <file> <s> <regex>; tokens redacted); th/dump.js (DOM boxes); harness --join-event[-start|-end], --join-preview-attendee; RUST_LOG=teams_cli::calling::live_stream=debug.
  - Registration API (services-virtual-events): POST events/{id}/attendee/register (RegisterVirtualEventAttendeeInput, registrationType Registration|AddToCalendar), GET events/{id}/users/{oid}/registration; capture Teams' body on winpc before building.
  - HostMode for a webinar: the form's Manage what attendees see sends attendeeViewModes null; find how Teams sets HostMode (meeting options after save?) before the Bring on screen run.

- 2026-11-19 round 2 (agent TASK-0217 r2), findings so far:
  - Join-time drop (run 3): OST Test 2 was dropped at 06:16:42.9Z, the moment ost-test1's OST preheat (Preview as Attendee) had joined the SAME conversation (conv-usce-01 7bbBq...) and left it again ("Leave conversation" 06:16:42.8, preheat cancelled by Join). Rerun with the call-end payload logged.
  - Go-live: Teams' calling stack posts a published state's content as an object (pluginless publishStateAsync parses it before building the payload); OST sent the curtain and spotlight contents as JSON strings. Both now go as objects. The updateMeetingLiveState body is otherwise identical (from {id, endpointId, participantId, languageId, displayName}, meetingLiveState {phase, sequenceNumber = meetingCapability.meetingLiveState.seqNum}, links, operationId).
  - Calendar New > Live Event: dialog "Teams Live Events is Retiring" (340 x 209 Fluent v8; Create town hall / Continue); Continue opens a 946 x 713 "New live event" window: Prohibited icon at 80, "Teams live events is retiring, please use Teams town halls for your large digital and hybrid events" (link adoption.microsoft.com .../town-halls/), Close.
  - Calendar New > Virtual appointment: a "New meeting" window headed "Virtual appointment": external guest name and email (+ Add additional external guest), a notice bar, Options (Who can present: Only organizers and co-organizers; Record and transcribe automatically: Off; Meeting chat: In-meeting only). Send = POST {mt}/v2.0/me/calendars/default/events?isOnlineMeeting=true with meetingTemplateId firstparty_e514e598-fba6-4e1f-b8b3-138dd3bca748 and virtualAppointmentInfo {appointmentClients [{displayName, emailAddress}], eTag "", isSmsEligible false, settings {allowClientToJoinUsingBrowser true, notifications [], organizerLocale "en-us"}}; guests are not attendees. Test sent to OST Test 2 only ("OST TEST 217 virtual appointment"; delete it).
  - Manage what attendees see: the webinar form has no such option in this tenant (neither quick setup nor All options). The town hall form's "On with preview" is not sent (POST events meetingOptions.attendeeViewModes null, publish PATCH meetingOptions null): the meeting came out HostMode. In-meeting Meeting options offer Off / On / On with preview (Default / HostMode / AdvancedHostMode) through MT meetings/v1/options.
  - Teams' green room with HostMode: the Manage screen panel dumped (scratchpad th2/green-preview-dump.txt).

- 2026-11-19 r2, live runs (linuxlt ~/th217r2, run.sh <name> <profile> <stay> <flags>; scratchpad th2/):
  - Run A (OST TEST 217 town hall preview, organizer ost-test1 in OST, attendee OST Test 2 in OST): the attendee was dropped at 09:17:05Z by conversation/conversationEnd code 0 subCode 5020 "This conversation has ended as there are no non-hidden participants in the incoming roster." right when the organizer's OST preheat was withdrawn ("Leave conversation" 09:17:05.09, preheat cancelled by Join now). Teams' code only logs 5020 (CallEndDiagnosticsWithNoInnerParticipant): the service ends a town hall's conversation once its last non-hidden participant leaves, so OST must never leave a preheat it is about to join. Start with object contents: Stage curtain 200, Meeting live state 202, live seq 1, End 202 (ended seq 2).
  - Run B (OST TEST 217 town hall B, organizer OST Test 2 in OST, attendee ost-test1 in Teams desktop): Teams' attendee waited ("WAITING", "The event isn't live right now.") and was dropped (call-quality survey) when OST's organizer joined: the harness closes the pre-join window before Join now, and the window closing withdrew the preheat ("pre-join closed: leaving its preheated call" 09:35:39) although Join now was waiting for it. Fixed: Join now waits for a preheat still being placed and joins it (Teams promotes its preheated call, never leaves and rejoins); a preheat Join now waits for is never withdrawn by the window closing. Rerun pending.
  - Streaming attendee (Run A): Leave split false and the "Start the meeting whenever you're ready" alert hidden (harness flags split/alert), organizer: split true, alert true.
  - The Manage screen panel works in OST (HostMode / AdvancedHostMode green room: panel, filters, self tile with Stage presence switch, "Bring presenters on screen..." stage).
  - On with preview in Teams (set via the meeting options; MT option name ManagedMode, value AdvancedHostMode; OST's meeting_options example answered 400 but the value took): Preview stage and Live stage (402.9 x 226.6, 2.67 #FDE300 edges, titles 16/700), "Send live" (96 x 31.3 #FDE300 600) under Preview, "The event hasn't started yet." on Live, Manage screen strip along the bottom (header 60: "Manage screen" 18/700, info, hint 12, pills at 514, Add Videos at right; tiles 273 x 152 with an "Add to preview" switch). Dump th2/advanced-green-dump.txt. Send live is Teams' setMeetingLayout (production layout {kind CLASSIC..., participants [...], action put}, sequenceNumber, operationId) built in Teams' production service; not built in OST yet.
  - test3's leftover "Canceled: OST TEST 217 webinar" purged; the test virtual appointment deleted.

- 2026-11-19 r2, more live checks:
  - Item 1 verified (OST TEST 217 town hall B2): OST Test 2 organized in OST, joined through its preheated call ("join meeting (preheated)"), started (curtain 200, live state 202) and ended the event while ost-test1 watched in Teams desktop: WAITING -> LIVE (player position counting) -> ENDED, never dropped.
  - Webinar attendee before the start in Teams ("OST TEST 217 webinar reg2", invited): Teams joins the call; "Not started" pill, full attendee bar, "Welcome to" 14/400 #616161, title 20/700/28, "This meeting will start shortly" 14/400 #616161, the recording alert. OST's staging screen now uses these styles.
  - Registration: an invited attendee joins from Calendar without registering; "Private" + registration is refused by the service here ("Registration-gated private invite-only events are not currently supported."); an organization webinar with registration made discoverable (PATCH isDiscoverable true answered, overview still says discoverable false) never showed in Teams' Discover upcoming list, so Teams' Register (POST events/{id}/attendee/register) wasn't captured. OST reads your registration (events::my_registration, virtual_event registration <id>); the Register button is open.
  - Webinar Manage what attendees see: no option in the webinar form in this tenant; set it through the meeting's options (ManagedMode HostMode), then People's Bring on screen applies. Bring on screen with a second presenter not rerun live this round.
  - All OST TEST 217 events cancelled and calendar entries purged (ost-test1, OST Test 2, OST Test 3).

- Merged f45a524 (2026-11-19): build OK, 773 lib tests passed. AC1 verified live (stream plays; bot hidden; organizer start no longer drops attendees). Open: Bring on screen rerun live, webinar registration, "On with preview" production layout (Send live), the Join as / Preview menu harness run.
<!-- SECTION:NOTES:END -->
