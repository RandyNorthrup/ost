# Town halls and webinars — spec (TASK-0184, TASK-0073 #2)

Measured 2026-11-17 in Teams on the web as ost-test1 inside OST's web
profile (spatest) on linuxlt, over its DevTools port (DOM, network log with
tokens redacted whole), with one public test town hall ("OST TEST 184 town
hall", organizer ost-test1, nobody invited, not shown in the Events app)
created, published, run and cancelled. Teams on the web refuses town hall
presenters (below), and the Windows PC was in use, so the presenter's side
was read in Teams' desktop bundles (build 26276.x: unified-bar-container-
manager, 527114, calling-app, pluginless, r_data-client-calling, string
tables) and checked live with OST, which joins as Teams desktop does.
Events app basics: docs/spec/events.md.

## 1. Creating them (Events app, Calendar)

- Calendar ▸ New ▾ lists Event, Channel meeting and, under "Organization
  templates", Webinar, Town hall, Virtual appointment and Live Event. On
  the web, Town hall there showed nothing; the Events app's Create event ▸
  Town hall is the path measured.
- **Town hall form** ("New town hall"), differences from Create from
  scratch:
  - Set up experience and options: capacity 1,000 / **3,000** (default) /
    10,000 attendees (View only, with Q&A); **Optimize for large
    audience** on (switch with an info button). On: the tiles are Mic and
    Camera (unavailable, 0.3 opacity, "Selected capacity does not support
    this engagement feature.") and Q&A. Off: capacity 1,000 and the tiles
    Mic, Camera, React, "During event" (chat), Q&A.
  - **Manage what attendees see** (410 wide dropdown: Off, On, On with
    preview), "Control the layout, content, and people seen on screen."
  - **Enable green room** on by default.
  - The panel (relative): capacity dropdown 248 × 30 at 57; the switch at
    266, its label at 322, info at 511; "Attendee participation" at 106,
    tiles 132 × 75 at 142 (8 apart); "Manage what attendees see" 233, its
    text 259, dropdown 282; "Enable green room" 329.
  - All options adds Production tools (Who has control of production
    tools; Manage what attendees see; Enable Green room) and, under
    Copilot and other AI, **Facilitator** ("Takes notes, joins the meeting
    chat, and more using the meeting's spoken language. Available when
    Copilot is enabled.").
- Save asks "Save as a draft and continue?" with "Optimize for large
  audience: On". `POST events` for a town hall differs from a webinar:
  `type "Townhall"`, `commentStreamProperties` all on but
  `useBackroomChatAsMainThread`, `eventCapacityProperties {3000, false}`,
  and in `meetingOptions` no `allowTeamsMeetingReactions` or
  `autoAdmittedUsers`, `allowMeetingChat` null, `attendeeRestrictions
  "DisableAudio,DisableVideo"`, `stagingRoomEnabled` true,
  `attendeeViewModes` null **even with Manage what attendees see On** (the
  meeting then had `attendeeViewModes "HostMode"`). The draft makes a
  Microsoft 365 group (`groupId`).
- **Publish**: the draft card's Publish event (172 × 40) ▸ "Ready to
  publish your event?" ("Invites will be sent to attendees. You can add
  more attendees and share the event after it's published."; "These
  settings can't be changed after publishing": Who can view and join,
  Registration; Cancel, Publish event) ▸ `PATCH events/{id}`
  `{"state":"Published","meetingOptions":null}` ▸ "Success! Your event has
  been published" / "Help your attendees discover it:" with "Show event
  in Events app" (off: `isDiscoverable` false), Copy join details, Copy
  event page link, Copy embed code. The page then shows "Upcoming", Join
  (split: Copy join link, Copy join details) and the chat button, the Q&A
  section (Viva Engage) and Manage apps (Custom Streaming, AI Producer).

## 2. Joining

- Every join answers `conversationType "scheduledTownhall"`,
  `convergedMeetingType "v2.townhall"`, `convergedMeetingMode
  "streaming"` for a town hall.
- **Presenters on the web are refused**: 403, subCode 5131, "Presenter
  had BlockPresenterJoinInEvents client capability and so their townhall
  join was blocked." Teams on the web shows "Join this town hall from the
  Teams app" / "Joining a town hall as a presenter or organizer isn't
  available on the web." (Dismiss). The capability is
  `ClientEndpointCapabilities.blockPresenterJoinInEvents` (16384), which
  OST had copied from the web client; the desktop app doesn't send it, and
  without it OST joins as organizer.
- **Anonymous attendees before the start**: 403, subCode 5134
  ("Anonymous user cannot start the meeting, and lobby is disabled for
  streaming enabled meeting."); Teams on the web: "External participants
  are not permitted to join before the event begins. Please join after
  the event has started." (Dismiss).
- The meeting tells what it is in `meetingDetails.meetingCapability`
  (organizer's join): `forceAttendeeStreaming` true, `stagingRoomEnabled`
  true, `meetingLiveState {phase "staging", seqNum 0}`, `attendeeViewModes
  "HostMode"`, `yammerQNAEnabled` true, `allowTeamsMeetingReactions`
  false, `raiseHands "Disabled"`, `attendeeRestrictions "DisableAv"`,
  `maxEventCapacity` 3000; the conversation offers
  `links.updateMeetingLiveState` and `links.setMeetingLayout`, and an
  `activeModalities.broadcast`.
- Teams' town hall check: `forceAttendeeStreaming` or a
  `scheduledTownhall` conversation; webinars and town halls also by their
  template (webinar `firstparty_d892ef44-003e-480c-9929-07349265a2e2`,
  town hall `firstparty_21f91ef7-6265-4064-b78b-41ab66889d90`).

## 3. The green room and going live (presenters)

From Teams' code (mixin `UOe` and the ubar's `zo` phase helper):
- Phase: `prelive` (green room on, not live), `active` (`meetingLiveState.
  phase` "live"), `ended`. Presenters wait in the green room (connected,
  meeting group "greenGroup"); attendees wait in call state Staging
  ("stagingGroup").
- In the green room the bar's end slot has **Start meeting**
  (`staging-room-start-meeting-ubar`, before Leave; "Start event" only
  with `enableTownhallDelayMessage`, off in shipped clients), for
  organizers and presenters. Disabled while starting: "A presenter already
  started the meeting" ("…event"). The alert "Start the meeting whenever
  you're ready." (info, dismissable).
- Start asks "Start the meeting for everyone?" / "{n} attendees will
  enter the meeting" (Cancel, Start meeting; the town hall wording "Start
  the event for everyone?" / "… will enter and watch the event at a slight
  delay." needs the same flag). Failure: "Unable to start meeting" / "Let's
  try starting the meeting again." (then "Wait and try again later or ask
  another presenter or organizer to start the meeting for you."), Close /
  Try again.
- Going live (Teams' meetingGoLive): publish a user-level `ufd` state
  `{"publishStateUFDType":"stage-curtain","meetingPhase":"live",
  "teamsCallId":…}`, wait 3 s, `POST links.updateMeetingLiveState`
  `{from, meetingLiveState {phase "live", sequenceNumber}, links
  {updateMeetingLiveStateStatus}, operationId}`, remove the curtain.
- Live: **End event** (town halls and webinars; "End meeting" otherwise)
  ▸ "End the event for attendees?" / "This will end the event for all
  attendees and return organizers and presenters to the Green Room." /
  "End event for all attendees"; the same steps with "stage-end-curtain"
  and phase "ended". There is no restart.
- The state pill (VirtualEventsLiveIndicator): "Not started", "Live",
  "Ended", then a divider, people glyph and the attendee count; tooltips
  "# attendees waiting" / "# attendees watching" / "# attendees remain";
  attendees see "Waiting" ("Waiting for the event to start."), "Live",
  "Ended".
- Town halls hide Rooms, Whiteboard, Controls, Report a concern and
  Facilitator; webinars hide Report and Facilitator (keep Rooms).
- Manage what attendees see "On" (`HostMode`): People's spotlight becomes
  **Bring on screen** / **Take off screen** (the spotlight state, content
  `{"isParticipantSpotlighted":true,"isScreenShareSpotlighted":false}`).
  "On with preview" (`AdvancedHostMode`) uses production layouts
  (setMeetingLayout) with a Preview and a Live stage.

## 4. Q&A

The bar's Q&A (YammerQnaButton) where `yammerQNAEnabled`: Viva Engage's
meeting Q&A in the side pane,
`https://web.yammer.com/teamsmeeting/teams-meeting/<base64 {"_type":
"TeamsMeeting","id": base64("0#<thread>#0")}>?client=teams&qnaAppType=native&meetingTenantId=…&callId=…&meetingTemplate=Townhall|Webinar&appSessionId=…`.

## 5. Attendees (streaming)

A town hall's attendees join in streaming mode: the stream is described
by a bot participant's `endpointDetails[].streamInformation.streams[]`
(HLS or UMS URLs, key token and delivery URL, eCDN plugin) and played by
Microsoft's Hydra player. Attendees' bar: indicators (Live), Q&A, React,
captions, More, Camera and Mic (off), Leave; before the start "Welcome to"
/ the title / "This meeting will start shortly"; after the end "The event
has concluded. Thank you for attending."

Measured live (OST as organizer started the town hall, 2026-11-17):
- After Start the service answered `updateMeetingLiveStateStatus`
  `{result {code 0, subCode 5999, "No Error."}, additionalDetail
  {successCount 2}}` and the conversation's `meetingLiveState` became
  `{phase "live", seqNum 1}`; End made it `{phase "ended", seqNum 2}`.
  `streamingModeActive` turned true once live.
- The composition service joins as a bot participant
  (`28:e32c9418-…`, "s04-prdnoamcompsvc", presenter) before the start;
  the town hall recorded automatically (its option) once live.
- ost-test2 (an org attendee, OST's capabilities include
  `supportsStreaming`) joined the live town hall's conversation (200, the
  roster with the composition bot) but its call was never answered: a
  streaming attendee doesn't get a media call.
- The anonymous guest was still refused while live (403, 5134, the same
  "External participants are not permitted to join before the event
  begins." in Teams on the web), so Teams' attendee view wasn't seen.

## 6. Run of Show (TASK-0073 #2)

Run of Show is a third meeting timer (`rosTimer` sections with presenters
and durations) started when a town hall or webinar goes live. Teams gates
it on `enableRunOfShowForTownhalls`, which the shipped configuration turns
on only for local and container builds (Teams' prod configuration, read
2026-11-17), so **Teams doesn't show Run of Show in this tenant**: the
town hall's form and All options have no Run of Show setting. Teams'
desktop window couldn't be watched going live (the Windows PC was busy),
so that last step is from the configuration, not seen.

## OST status (see the task's notes for the live checks)

- [x] Events: the Town hall template's form (capacity, large audience,
  tiles, Manage what attendees see, green room), its draft as Teams sends
  it, Publish with Teams' dialogs (People & emails read first), Upcoming,
  Join (pre-join) with Copy join link / details, and the event chat.
- [x] Joining a town hall as organizer or presenter (the desktop's
  capabilities).
- [x] The green room: Start meeting (confirmation, go-live, failure),
  End event, the state pill, the alert, the bar rules for town halls and
  webinars, Q&A, Bring on screen / Take off screen.
- [x] An attendee's staging screen ("Welcome to" / title / "This meeting
  will start shortly", and the end text) where the call connects (webinar
  attendees); the presenters' alert after the end.
- [ ] Streaming playback for town hall attendees (the composition bot's
  stream, Hydra/HLS): an OST attendee's call goes unanswered ("No answer"
  after a minute). Hiding the composition bot from the stage and People
  (Teams' rule not traced). "On with preview" (production layouts),
  Preview as attendee, the Join as Organizer / Presenter split button,
  Calendar ▸ New ▸ Webinar / Town hall, Copy embed code, Show event in
  Events app, the webinar's own form and registration. Webinars were not
  run live (only town halls).
