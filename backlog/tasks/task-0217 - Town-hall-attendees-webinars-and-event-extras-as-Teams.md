---
id: TASK-0217
title: Town hall attendees, webinars and event extras as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-17T06:06:00Z'
updated_date: '2026-11-19T13:46:00Z'
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

- 2026-11-19 round 3 (agent TASK-0217 r3), progress:
  - Send live = Teams' production studio setProductionLayout -> convertLayoutToPayload {layoutDetails {layout {...layoutDetails, action "put", kind, participants}, sequenceNumber}, operationId} -> calling-electron setMeetingLayout (meetingLayoutJson = JSON of layoutDetails) -> SlimCore CSetMeetingLayoutOperation, POST to the conversation's setMeetingLayout link; the pluginless twin (aG) posts {from {id, endpointId, participantId, languageId, displayName}, layoutDetails, operationId, sequenceNumber (meetingLayoutSequenceNumber), links {setMeetingLayoutStatus}}. Conversations carry layoutDetails {lastNonScreenshareLayoutKind, lastSideBySideLayoutKind, lastUpdatedBy, layout {kind, operationId, participants, sequenceNumber, ...}, sequenceNumber}. The preview stays local (Teams' previewProductionStudioLayout cache) until Send live. Bundles on linuxlt ~/teams-26304: 527114 (ProductionStudioMixin), 119108 (use-production-studio-layout), calling-app (PreviewSubStageContainer). CDP logpoint tool: scratchpad th3/logpoint.mjs.
  - Item 4 (OST TEST 217 r3 town hall, ost-test1 organizer in OST, linuxlt ~/th217r3/M4b*): the split's menu showed Join as Organizer / Preview as Attendee and Preview joined as attendee. Teams' menu measured: items 140.9 x 32, 2 apart, 14/400 #424242, from Join now's left edge +5, 4.5 under it; OST's menu moved to match.
  - Item 1b verified: Teams (ost-test1 organizing, HostMode town hall) flipped OST Test 2's Stage presence; OST Test 2 in OST showed itself on stage (onScreen 1, its switch on; ~/th217r3/P1-event-stream-60.png).
  - ManagedMode changed during the meeting (MT options, also through Teams' own Meeting options Apply) does not reach the running conversation's attendeeViewModes; the next conversation gets it.

- 2026-11-19 r3, Send live captured and built:
  - Teams desktop's Send live, logged on winpc with a CDP logpoint in calling-electron setMeetingLayout: layoutDetails {layout {id "<teamsCallId>_Preview", participants [{id, participantId, endpointId, modality "VIDEO", isRTMPInVideo false, state null}], nameTag {isEnabled true}, kind "CLASSIC", kindDetails null, background null, action "put"}, sequenceNumber = the conversation's layout sequence}, operationId. The service answers with conversationUpdate layoutDetails (layout adds lastUpdatedById, operationId, resolution 1280x720, participants with isOnStage true; outer sequenceNumber +1). An empty preview sent live clears the live screen.
  - OST builds it (live_event::set_layout_body / production_layout, OutgoingCall::set_meeting_layout, Backend send_live, CallWindow production view: Preview and Live stages, Send live, Manage screen strip with Add to preview switches; webinar attendees in AdvancedHostMode see only the live layout).
  - Verified live (OST TEST 217 r3 town hall B, AdvancedHostMode): OST Test 2 organizing in OST put itself, OST Test 3 and ost-test1 on the preview and sent it live (setMeetingLayout 202, layout seq 1); Teams desktop (ost-test1, presenter) showed the three on its Live stage (2 + 1 grid of 196.7 x 110.6 tiles, "Last updated by OST Test 2"); OST Test 3 in OST showed them on its Live stage. Earlier Teams' own Send live (organizer ost-test1, town hall r3) reached OST Test 2's Live stage within a second.
  - Teams measured: Live and Preview frames 2.67 #FDE300 before the start; Send live has a 0.67 #D1D1D1 border; the strip's header has a 0.67 #E0E0E0 top border; "Last updated by <b>name</b>" (13/400, "you" for yourself) right-aligned on the Live title row.
  - Registration: OST's discoverable PATCH was wrong: Teams' updateVirtualEvent converter sends {"access": {"isDiscoverable": on}, "meetingOptions": null}; top-level isDiscoverable is ignored, which is why the r2 org-wide webinar never reached Discover. Fixed. Teams' Register payload (meet-app Es + resolver jt): {language, timeZoneDetails {ianaTimeZone, windowsTimeZone, localizedTimeZoneString "GMT-08:00 <iana>", utcOffset, timeZone}, firstName, lastName, email, answers [{Id, Answer}], hasAcceptedTermsOfUse}; no registrationType (Add to calendar sends "AddToCalendar").
  - Webinars by OST Test 2 have no ManagedMode meeting option (town halls do), so the Bring on screen check uses a town hall.

- 2026-11-19 r3, more:
  - Item 1 (Bring on screen with a second presenter) verified live on "OST TEST 217 r3 town hall B" (HostMode): OST Test 2 organizing in OST turned Stage presence on for OST Test 3 and ost-test1 (Spotlight 200 x2); Teams desktop (ost-test1, presenter) showed both On stage and on its managed stage (517.3 x 291 side by side); OST Test 3 in OST showed 2 on screen; taken off again (Stop spotlight 200). Teams side: Teams organizer flipping OST Test 2's Stage presence put OST Test 2 on its own OST stage (see above).
  - Registration captured in Teams desktop (Discover ▸ Register on "OST TEST 217 r3 webinar reg", ost-test1): POST {teamsevents}/events/{id}/attendee/register (body in spec section 9), the dialog and success view measured, Unregister = POST events/{id}/attendees/{registrationId}/cancel (204). ost-test1 is unregistered again in Teams; OST's own Register run follows.
  - Build note: abuild.sh's cp -al shares target/debug/.cargo-lock between build folders (5 hard links), so one agent's cargo blocks the others'; replaced ost-build-th3's lock with its own file.

- 2026-11-19 r3, wrap-up:
  - Registration built and verified: OST (ost-test1) registered from Discover's card (Register dialog, terms, "You're registered!", "Event Registered" toast; events: registered status Registered); Teams desktop's Discover card then said Registered. OST's Unregister ("Cancel your registration?" ▸ Cancel registration, POST .../attendees/{id}/cancel) put it back; Teams then showed Register.
  - Fixed on the way: Discover's lists rendered no cards on Qt 6.10 (a list nested in the Repeater's rows isn't a JS Array, so items came out empty); now copied out by index.
  - "On with preview" rechecked live with the final layout: OST Test 2 started the event, sent itself, ost-test1 and OST Test 3 live; OST's view matched Teams' (2 + 1 grid, "Last updated by you", the Live frame #D13438 once live, as Teams measured); ended the event; everyone left (hung up 202 in both OST logs, Teams out of the call).
  - Gallery: near ties go to more columns (two people side by side on the managed stage, as Teams).
  - Cleanup: OST TEST 217 r3 town hall, town hall B, webinar and webinar reg cancelled; their calendar entries purged for ost-test1, OST Test 2 and OST Test 3.
  - Open: the green room's recording alert for auto-recorded events ("Recording and transcription will begin when the meeting starts."); registration forms with questions (OST sends no answers); Discover's attendee card lacks "By <presenter>" (pre-existing).
<!-- SECTION:NOTES:END -->
