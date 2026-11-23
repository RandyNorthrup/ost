# Teams' Events app — spec

Measured in Teams on the web (teams.cloud.microsoft) as ost-test1 on
2026-11-16, inside OST's own web profile (spatest) on linuxlt over its
DevTools port, in a 1212 x 752 window (the app area 1144 wide from x 68,
its header 61 tall from y 84, the 36 px notification banner above it):
layout from the DOM (boxes, type, colours), requests from the network log
(parameter names and non-secret values only; tokens redacted whole), and
Teams' code: the meet-app bundle (the Events UI, `one-events-*`),
services-virtual-events (the REST transport), events-scheduling-form and
the virtualEvents strings bundle. One draft was made to measure the save
and was deleted again (Cancel); nothing was published.
OST: `desktop/qml/EventsView.qml`, `api::events`, `backend.eventsRequest`,
`--events-test`.

Events isn't a hosted page: Teams draws it itself from the virtual events
service (app id `a63f7012-8cc9-42d5-99c3-e35f526fab17`, View more apps ▸
Events; it then takes the app bar's open-app slot under Copilot).

## The service
- Token: Teams' own (client 5e3ce6c0) for resource
  `7fc21101-d09b-4343-8eb3-21187e0431a4` (ECS
  `virtualEventsServiceResource`); headers `authorization`,
  `content-type: application/json`, `x-ms-correlation-id`.
- Discover: `GET {regional}/eventOverviews` (the region discovery's `virtualEventsService`,
  e.g. `https://teams.microsoft.com/api/teamsevents/us`, as ECS
  `useRegionalVirtualEventsServiceEndpointResolver` is on; the global
  `virtualevents/prod/beta` address is only the fallback, TASK-0241)
  (`x-api-version: 2.0`; GraphQL
  `eventOverviewsV2`), three lists:

| list (category) | query |
|---|---|
| Happening now (UP_NEXT) | `pageSize=9&sortBy=StartTime&sortOrder=Ascending&startTo=<now+5 min>&endFrom=<now>` |
| Upcoming (UPCOMING) | `pageSize=21&sortBy=StartTime&sortOrder=Ascending&startFrom=<now+5 min>` |
| Past (PAST) | `pageSize=9&sortBy=EndTime&sortOrder=Descending&endTo=<now>` |

  each `&returnRequesterProperties=true&eventStatus=Published&includeRequesterStatus=AllInOrg`
  (times ISO with milliseconds, UTC). The Filters pane's My events asks
  `includeRequesterStatus` REGISTERED, INVITED instead of ALL_IN_ORG (code;
  the REST spelling `Registered`/`Invited` is OST's reading, not seen on
  the wire: the tenant has no published events). Replies
  `{results: [{eventDetails, eventSessions, registrationInfo, …}]}`
  (`{"results": []}` here).
- Everything else goes to the regional service (region discovery
  `virtualEventsService`; on the web `https://teams.cloud.microsoft/api/teamsevents/us`,
  from the Outlook calendar frame `https://teams.microsoft.com/api/teamsevents/us/`):
  - `GET users/{oid}/eventFeatureDetails` →
    `{eventCapacity: {allowedAttendeeCount 3000, eventCapacityOptions:
    [{capacity, isBaseEventExperience, isLargeScaleLicenseRequired,
    isAvailableForUserLicense, isAvailableForUpdate}]}, licenseStatus
    "Allowed", isLicenseEnforcementEnabled false}` (options 3000, 5000,
    10000 base, 10000 … 100000 large-scale);
  - Manage: `GET eventOverviews?manageFilterType=Published|Draft&pageSize=1&includeTotalCount=true`
    (the counts) and `GET eventOverviews?manageFilterType=Draft|Published|Past&pageSize=4&includeTotalCount=true&eventTypes=Townhall,Webinar`
    → `{nextPageSkipToken, totalCount, results: [{eventDetails: {id
    (<guid>@<tenant>), title, eventTime {startTime, endTime,
    timeZoneDetails}, type, state, siteUrl, access, owner, theme
    {promoImage, primaryColor}, …}, eventSessions: [{…, meetingContext
    {threadId, joinLink, …}}], registeredAttendeeCount, roles:
    ["Organizer"]}]}`;
  - Save and continue: `POST events` (201, the event; state Draft) with
    `{type: "Webinar" (Create from scratch), sessionType "Single",
    description, language "en-us", title, eventTime {startTime, endTime
    (ISO, ms, UTC), timeZoneDetails {timeZone "PacificSt", utcOffset -480,
    ianaTimeZone "US/Pacific", windowsTimeZone "PacificSt",
    localizedTimeZoneString "PacificSt"}}, owner {email, displayName,
    identity {mri, objectId, tenantId, upn null}, userBio {…},
    userPurpose "unknown"}, team [], access {accessType "Private",
    inviteOnly false, isRegistrationEnabled false}, presenters [],
    attendees [], communicationProperties {…}, speakerJoinLinkProperties,
    productionModeProperties, commentStreamProperties,
    eventCapacityProperties null, substrateGroupSessionKey (a new guid),
    meetingOptions {allowTeamsMeetingReactions, allowMeetingChat
    "Enabled", yammerQNAEnabled, …, attendeeRestrictions "UnRestricted",
    stagingRoomEnabled, …}, clientTags {version "2.0"}, theme
    {primaryColor "#5B5FC7", promoImage}}`. "Your organization" is
    `Private` with `inviteOnly` false, Specific people `Private` + true,
    Public `Public`. A chosen capacity is `eventCapacityProperties
    {maxEventCapacity, isBaseEventExperience}` (events-scheduling-form).
    Attendee restrictions: UnRestricted, DisableAudio, DisableVideo,
    DisableAv. The time zone keys are Windows names shortened ("Pacific
    Standard Time" → "PacificSt").
  - Then `GET events/{id}/overview`, `…/sessions`, `…/registration`,
    `…/users/{oid}/registration` (404 "Attendee registration not found").
    The draft also makes a meeting in your calendar and an event group.
  - Cancel (the event page's ··· ▸ Cancel, "Cancel event?" "Once canceled,
    you cannot uncancel. Attendees will be notified by email."):
    `DELETE events/{id}` (204; Teams' cancelVirtualEvent, drafts and
    published alike). The calendar keeps "Canceled: <title>" until
    removed.
- Promo pictures: `{amsV2}/v1/objects/{promoImage}/views/imgpsh_fullsize?v=1`
  (Teams' media store, skype token).

## Layout
Header (`header`, #FAFAFA, 61 tall, a #EBEBEB line under it):
- the app tile 32 x 32 #5B5FC7 radius 4 (a white 20 px glyph) 20 in, 14
  down; "Events" 20/28.57 semibold #616161 at 60;
- the tablist ("Events app navigation") at 136, 8 down: Discover
  (`one-events-discover-tab`, 83.8 x 44) and Manage (80.5 x 44), text 10
  in, 14/20, the chosen one semibold #242424 with the brand line under its
  text, the other #424242;
- right, 8 apart, 20 from the edge, 32 tall: Pin app
  (`one-events-pin-app-button`, 104 wide, pin glyph, 14/20 semibold
  #424242, transparent), Filters (`events-filter-button`, 96, Discover
  only), Create event (`create-event-button`, 141, white, #D1D1D1 border,
  #242424).

Discover (the page #FAFAFA, scrolling under the header):
- the intro card, sticky at the top (32 from the top while unscrolled):
  1066 x 136 at 32 in, #F5F5F5, a #D1D1D1 hairline, radius 16, 17 in: "Introducing
  an app for all things events!" (h2 16/22 semibold), "Discover what's
  happening in your org and plan your own professional events, all in one
  place. You can still access your meetings and audio recaps." (16/22),
  then View meetings and View audio recaps (24 tall, 12/16, white,
  #D1D1D1, radius 4, 10 apart) 99 down;
- no events: the picture (`v2/calendar-add-l-standard.svg`, 128) 56 under
  the card, "No events have been scheduled yet" (16/22 bold) 16 under it,
  "Customize everything from registration to how you want attendees to
  interact. We'll walk you through each step." (14/20, 450 wide,
  centred) 16 under, Create event (primary, 155 x 38) 16 under;
- "Get started with a template" (16/22 semibold) 32 under, 8 in; the
  cards 30 under it: 517 x 317 (two columns 16 apart, 8 in), white,
  radius 24, the card shadow (0 0 2 / 0 2 4); the picture panel 12 in,
  163 tall, #FAFAFA radius 16 with the 88 px illustration centred; the
  title 16/22 semibold 22 in, 187 down; the text 14/20 (two lines) 221
  down; the feature chips (24 tall, pill, #F5F5F5, 12/16, 8 apart) 279
  down. Templates and their chips: Webinar (Registration, Video on
  demand, Waitlist, Green room), Town hall (Up to 10K attendees, Green
  room, Video on demand, HD video stream), All hands (Moderated Q&A,
  Real-time reactions, Green room, Video on demand), Training (Breakout
  rooms, Polls, Live captions, Registration, Video on demand), Ask me
  anything (Moderated Q&A, Polls, Green room, Producer controls),
  Community event (Registration, Event chat, Highlights, Green room,
  Waitlist); illustrations from
  `teams.public.onecdn.static.microsoft/evergreen-assets/illustrations/`.
- Filters pane (352 wide, white, from the header's bottom, a #E0E0E0
  line): "Filters" 20/28 semibold 25 in, Close filters; My events (16/22
  semibold, "Events you're invited to or registered for" 12/16) with a
  switch; Date range (Today, This week, This month, Custom range radios,
  two columns); Clear all (brand link), Cancel and Apply (96 x 32) at the
  bottom.

Manage: Connect apps (`connect-apps-button`, 146 x 32, outlined, 32 down,
right); with no events the empty state and templates as on Discover; with
events the sections Drafts (n) / Published / Past (`one-events-drafts-
section` …): the title 20/28 semibold 26 down, See more (brand) on the
right, then up to four event cards (`event-card`, 351 x 303, radius 24,
12 in: the promo picture 327 x 109 radius 16, the title 16/22 semibold
131 down, "Monday, Nov 16, 3:30 PM - 4:00 PM" 14/20 #616161, Organizer
and Online (12/16 #616161 with 16 px glyphs), Edit (64 x 24 outlined) and
··· (Chat with participants, Chat with event group, Duplicate)); an empty
section says "Published events will show up here." (16/22 #616161 with a
glyph). Below: "Manage immersive collections".

Create event: a back arrow (32 x 32, 24 in, 32 down) and "Create" (h1
20/28 semibold); "Choose what you're organizing" (20/28 semibold) 90
down; the cards 134 down in three columns (347.3 x 292.4, 20 apart):
Create from scratch ("Mix and match capabilities as you go") then the six
templates; the picture panel 106.4 tall.

New event (Create from scratch):
- "New event" with the back arrow; Save and continue (primary, save glyph,
  180 x 32, 22 from the right);
- the welcome card (1100 x 162, #F5F5F5, #E0E0E0, radius 16): "Welcome!
  Let's walk through creating your first event." and three steps with 64
  px pictures: 1. Fill out details, 2. Personalize event page, 3. Spread
  the word (16/22, their text 12/16 #424242); Dismiss;
- four cards (white, radius 16, 25 in, 16 apart; the header 20/28
  semibold with a chevron, 82 tall closed):
  - Add event details: Name * (40 tall field, 16 px text, "New event"),
    Start date / Start time / End date / End time (four 240.5 wide fields,
    16 apart, 32 tall) and the time zone globe; Location (Teams Online
    Meeting chip, #E8EBFA with a brand camera disc, "Add a room");
    Description (an editor 137 tall with Bold, Italic, Underline,
    highlight, font colour, size, clear, indents, lists, link);
  - Who's planning the event?: Send invites as ("OST Test 1 on behalf of
    New event"; "Invites sent from Event mailbox. Co-organizers have full
    access to manage the event."), Organizers (you), Co-organizers and
    Presenters people pickers ("They'll receive invites when you save the
    event.");
  - Who can attend? (summary "Your organization · Registration Off"):
    three option cards (339 x 114, radius 12, the chosen one's border
    brand, a 36 px icon disc): Public, Your organization (default),
    Specific people and groups; Invite people to attend (Optional); Turn
    on registration? (switch);
  - Set up experience and options (summary "1,000 attendees"): Set your
    max event capacity (250 px dropdown) and Optimize for large audience
    (switch, info); Attendee participation tiles (132 x 75, radius 12,
    #E0E0E0: Mic, Camera, React, Chat ▾, Q&A); Enable green room; a stage
    preview (a sample picture of an event); All options, Manage apps
    (disabled: "Available after you save.").
- Save and continue opens "Save as a draft and continue?" ("Attendees
  can't view the event until after you publish it."; "These settings will
  be locked after saving": Invites from: Event mailbox, Optimize for large
  audience: Off; "Get back to events you're organizing faster" with Pin
  the Events app ✓; Cancel, Save and continue); then the event's page with
  the toast "Draft event created": a draft card ("This event is a draft.
  Publish when you're ready to share with attendees." Publish event),
  the title with Edit details, Share, ···, Preview; Overview, People &
  emails, Insights, Highlights; the promo picture, the title card, the
  date/location/access card with Join, Manage apps.

## The rest (TASK-0212; Teams desktop 26304 on winpc as ost-test1, 2026-11-18)
Measured over CDP (DOM, network with tokens redacted) and read in Teams'
desktop bundles (meet-app, events-scheduling-form, services-virtual-events,
config-prod, services-io-collab-object). Test events "OST TEST 212 draft"
(draft) and "OST TEST 212 duplicate" (published, only OST Test 2 / 3 and the
test room invited) and the template "OST TEST 212 template" were made and
removed again.

Create's templates open the form as (measured on winpc, not saved):
| card | type | form title | who can attend | registration | large audience | green room | chat tile |
|---|---|---|---|---|---|---|---|
| Create from scratch | Webinar | New event | Your organization | Off | Off | Off | Chat |
| Webinar | Webinar | New webinar | Public | On | Off | On | During event |
| Town hall | Townhall | New town hall | Your organization | Off | On (3,000) | On | — |
| All hands | Webinar | New all hands | Your organization | Off | Off | On | Chat |
| Training | Webinar | New training | Public | On | Off | Off | Chat |
| Ask me anything | Townhall | New ask me anything | Your organization | Off | On (3,000) | Off | — |
| Community event | Webinar | New community event | Public | On | Off | On | During event |
(The card texts aren't in the desktop bundle: Teams loads the Events
modules from its CDN, `teams-modular-packages`.)

Discover:
- The sections are "Happening now" (left out while empty), "Upcoming
  events in your org" and "Catch up on past events", each with See more
  (brand link, right).
- Teams keeps the three lists as slots in its worker store
  (`one-events-manager` → `one-events`, `{slotId, events, lastSyncedAt}`) and
  refreshes only DISCOVER_UP_NEXT and DISCOVER_UPCOMING on its interval and
  activation; DISCOVER_PAST is synced when Teams starts. On winpc
  (2026-11-21) the past slot dated from 2026-11-19 13:25Z and still showed
  "OST TEST 217 r3 town hall", while the service answered the same past
  query with no events: what Teams showed was its two-day-old copy. OST asks
  all three when Discover opens (as Teams at start).
- **Filters ▸ Custom range**: From and To (native date fields, 146 x 32,
  "mm/dd/yyyy"; "Select a date." under an empty one). Any date range or My
  events asks the **regional** service once: `GET {regional}/eventOverviews?
  pageSize=100&sortBy=StartTime&startFrom=<From's local midnight>&startTo=
  <To's 23:59:59.999>&returnRequesterProperties=true&eventStatus=Published
  &includeRequesterStatus=Registered&includeRequesterStatus=Invited` (My
  events; else AllInOrg). The filters show as chips under the intro card
  (24 tall, #D1D1D1, radius 4, 12/16 #424242, a dismiss: "My events",
  "November 18 - 30, 2026") with Clear all; no match: "No events match your
  filters. Clear all filters".
- **View audio recaps** opens the Meeting Recaps app (below) on Audio recaps.
- A card: "in 25 mins" (10/10 semibold brand on #E8EBFA with a clock) before
  the time while it starts within the hour; your role or "By {first
  presenter}"; "Online", or "In-person and online" when a room is a speaker;
  Edit (outlined), Share (published) and ··· (Chat with participants, Chat
  with event group, Duplicate) for organizers.

Manage:
- Section titles count everything: "Drafts (1)", "Published (1)". **See
  more** opens the whole section: a back arrow and the title, "Showing 1
  event" (Teams' events_showing_count_mf), the cards in rows; `GET
  …/eventOverviews?manageFilterType=<Draft|Published|Past>&pageSize=25&
  includeTotalCount=true&eventTypes=Townhall,Webinar` (next pages with the
  reply's skip token).
- **Connect apps** ("Connect apps and workflows", 900 wide, 28/20 semibold;
  "Save time by sharing event data with your favorite apps."): ECS
  `virtualEvents.integrationsThirdParty` as cards (416 x 142, #D1D1D1,
  radius 8, the apps' 28 px logos, an open-in-new glyph, name 14/20
  semibold, description 12/16 #616161): Hubspot, Pardot (Zapier), Marketo
  (Zapier); a card opens its link outside Teams. (Teams also asks Power
  Automate's gallery `api.flow.microsoft.com/…/teamsworkflowtemplates?
  $filter=…teamswebinar_marketing_integration…` but shows only the three.)

Create:
- **Your saved templates** under the templates (20/28 semibold): `GET
  {regional}/eventTemplates` → `[{id, name, description, eventTemplateData
  {eventType, title, description, access, team, presenters, attendees,
  theme, meetingOptions, …}}]`; a card (the promo picture 323 x 108, the
  name, Schedule, ··· Edit template / Delete). Delete: `DELETE
  eventTemplates/{id}`, no question, toast "Template deleted"; Edit
  template: the form titled "Edit template" (date and time off), `PATCH
  eventTemplates/{id}`; empty: "Save an event as a template and it will
  show up here." with v2/document-add-l-standard.svg.

The form:
- Desktop adds a pop-out button left of Save and continue.
- **Time zone**: the globe (32 x 32 toggle, brand glyph, #F0F0F0 while on,
  tooltip "Time zone") opens a "Time zone" row: a dropdown of Teams' 140
  zones ("(UTC-08:00) Pacific Time (US & Canada)"; keys like PacificSt
  mapped to IANA by Teams' module 331201; OST: `api::events_tz`). Sent as
  `timeZoneDetails {timeZone, utcOffset (the label's), ianaTimeZone,
  windowsTimeZone, localizedTimeZoneString}`.
- **Location ▸ Add a room**: `POST outlook.office.com/SchedulingB2/api/
  v1.0/me/findmeetinglocations {MaxCandidates 25, ConferenceRoomsOnly,
  QueryConstraint {Query}, LocationProvider "80", TimeConstraint {Timeslots
  [{Start/End {DateTime "yyyy-MM-dd HH:mm:ss", TimeZone "Pacific Standard
  Time"}}]}, ResolveLocationsAvailability true}` per keystroke; rows show
  the initials, the name and "Available · address" (green) from
  `Availability`; "We couldn't find any matches.". A room becomes a chip
  and a presenter `{…, userType "Room", userPurpose "room"}`; **Room
  options** appears beside the field ("Teams rooms options": per room "Set
  up room for" Presenting / Attendee viewing; Save).
- **Description toolbar** ("Formatting", 32 px buttons): Bold, Italic,
  Underline | Text highlight color (No highlight + 8 swatches), Font color
  (Automatic + 8), Font size (Large, Medium, Small), Clear all formatting |
  Decrease indent, Increase indent, Bulleted list, Numbered list | Insert
  link; the same swatches as the compose box. Sent as HTML
  (`<p>OST TEST 212 <strong>bold</strong></p>`).
- **People pickers**: `POST {mt}/beta/users/searchV2?<flags>&source=oneEvents`
  with the text as the body: Co-organizers `includeDLs=false&enableGuest=
  false&includeBots=true&skypeTeamsInfo=true`, Presenters `includeDLs=false
  &enableGuest=true&includeBots=true&includeMTOUsers=true&skypeTeamsInfo=
  true`, Invite people to attend `includeDLs=true&…` (groups too). Rows 50
  tall: 32 px avatar, the name 14 #424242 and the alias in capitals (a
  group's mail) 12 #616161, the typed text bold; picked: tags (20 px
  avatar, name, ×). "They'll receive invites when you save the event." /
  "They'll be invited when the event is published. Customize your invite
  preferences in the **People & emails** tab."
- Sent: `team: [{email, displayName, identity {mri, objectId, tenantId,
  upn}, userBio {…}, userType "ADUser", userPurpose "unknown"}]`,
  `presenters: [… sessionsProps [{allowBypassLobby false}] …]` (with the
  session's id when editing), rooms as presenters.
- **Stage preview**: Teams' mini meeting window (598 x 374) beside the
  participation tiles: title bar, command bar (LIVE pill and running time,
  Chat, Q&A, Raise, React | Camera, Mic in brand while allowed, Leave), nine
  tiles playing Teams' sample videos (`evergreen-assets/virtual-events/
  event-stage-preview/participant-videos/*.mp4`), the chat panel when chat
  is on; "Approximate preview. Actual event experience may vary based on
  your set up."
- **All options**: the event template's meeting options, `GET {mt}//beta/
  meetingTemplates/details/firstparty_d892ef44-…(webinar)|firstparty_
  21f91ef7-…(town hall)?isChannelMeeting=false&language=en-us&
  useCategoriesV2=true` (the meeting options dialog's shape, with
  `meetingsOptions_*` strings), shown in the Meeting options dialog with the
  event's values; event-only rows: Who can manage Q&A, Spoken language,
  Who can record and transcribe, Enable multilingual speech recognition,
  Who has access to the recording or transcript.
- **Manage apps**: disabled ("Available after you save.") until the event
  exists; on the page it is "Manage or add apps for your session here." →
  Teams' manageAppsLinkUrl `/l/meeting/{tenant}/{organizer}/{thread}/0`.
- The save dialog lists "Invites will be sent to": Organizers n ("Can view
  and edit") and Presenters n ("Can view"), 268 x 111 #FAFAFA radius 8
  cards with 24 px avatars; the Pin the Events app row only while unpinned.
- Leaving a changed form asks "Unsaved changes" / "Do you want to discard
  edits or continue editing?" (Continue editing, Discard).

The event page:
- Title row: Edit details (outlined), Share (32 x 31; off while a draft,
  tooltip "Event sharing is available after publishing."), ··· (Duplicate,
  Save as template, Cancel), a divider and Preview (on Overview; "Preview as
  published" on Highlights).
- **Tabs** ("Event navigation tabs"): Overview, People & emails, Insights,
  Highlights.
  - Overview: the promo (646 x 215, Edit event banner), the title card
    (24/32 semibold, the description), Presenter cards (48 px avatar, the
    name), on the right the time / "OST Test Room • Online" / access card
    with Join (split; "Join - Event isn't published yet.") and the chat
    button (split for webinars), Manage apps.
  - People & emails: cards (title 20/28 semibold, a chevron, open):
    Email notifications (Attendees, Send attendee emails switch =
    `communicationProperties.disableAttendeeEmails`; Email / When it's
    sent / Actions: Event invite "Event is published or updated", Event
    recording available "As soon as recording is published", Preview and
    Edit), Organizers (n) (Name, Email; Manage organizers), Presenters (n)
    (Manage presenters), Location (n), Attendees ("When attendees RSVP or
    register, they'll show up here."). Data: `GET events/{id}` (team,
    presenters with rooms, attendees), `…/attendees?status=…`, `…/speakers`.
  - Insights: an inline illustration, "No reports yet" / "You'll get a set
    of reports after the event ends."
  - Highlights: "Recording used for highlights:" (No video is selected),
    Download, View recap, Included content, Publish (all off without a
    recording), then v2/ai-video-record-l-standard.svg, "No AI highlights
    yet" / "Check back after the event has ended to generate them and share
    with attendees."
  - With a recording (measured on winpc 2026-11-21, "OST TEST 212
    recording"; Teams 26304 event-highlights-tab / -organizer): opening
    the tab reads the meeting's artifacts (Recording, TranscriptV2,
    Highlights); with no Highlights file Teams makes one (createHighlights
    = `POST {mcps}/spe/highlights` `{threadId, organizer: "oid@tid",
    meetingTitle, externalEntityKey: ""}`, 201 or 409) and generates from
    the latest recording over AugLoop ("teams_event_highlights": the
    TeamsEventHighlightsProgressAnnotation steps FetchGroundingData,
    GenerateHighlights, WriteToLoop, and the TeamsEventHighlightsAnnotation
    `{succeeded, errorCode}`; signal `{eventContext {eventId, threadId,
    eventLanguage}, recording {driveId, itemId}, loopFile {driveId, itemId,
    siteUrl}}`); the highlights are written into the Loop file.
  - Toolbar (49 tall): the picker 311 x 30 ("Nov 21, 2026 1:17 PM – 1:20
    PM"; a "Current recording" group, then Select from OneDrive); Download
    64 x 31 (Video, Transcript); right: View recap 32 x 31, Included content
    149 x 32 ("Choose what to include in highlights": Recording + text
    highlights, default, / Recording only), Publish 96 x 31. A 36 tall
    status bar: "**Generating AI highlights from event recording...** This
    might take a minute. Feel free to leave this tab and come back." (a
    spinner), then "**Highlights aren't published yet.** Publish them when
    you're ready to share with attendees." (info icon). Then the
    recording's OnePlayer (804 x 452) and the highlights card (796 wide):
    the event's title 24/600 and the highlights' Loop page ("Event
    summary", …). Picking another recording asks "Generate new AI
    highlights?" ("A new set of highlights will be generated using the
    recording you selected. This will replace the current highlights and
    can't be undone.", Generate highlights).
  - The session's recording (Teams' activeRecording) is the first of
    `GET events/{id}/sessions` → `[0].recordings[0]` `{id, name,
    publishProgress {status Draft|Scheduled|InProgress|Published|Failed|
    Expired}, expirationDate, isExpirationExtended, hasHighlights,
    sourceUrl, sourceDriveId, sourceItemId}`. With none, the first meeting
    recording (the contents list's first) is picked: saved as a draft and
    the highlights generated from it (no dialog). Picking another file
    saves it as the draft at once, then asks "Generate new AI
    highlights?". A meeting recording goes as `{id: driveItemId, name: the
    artifact's id, objectUrl: its location}`.
  - The draft and Publish are `POST events/{id}/sessions/{sid}/recordings`
    (x-skypetoken) `{name, webUrl, duration (the video's ms), 
    expirationDurationDays 30, driveId, itemId}` + `isDraft: true` for the
    draft, + `highlightsContent` on Publish with Recording + text
    highlights: the highlights Loop component's
    `ComponentSerializable.serialize()` (Teams' getSerializedContentRef).
    Publish is usable on a Draft / Failed / Expired recording of a
    published event ("This option is only available after the event has
    been published." on a draft event).
  - Publish's dialog: "Ready to publish highlights?", the text by what's
    included and whether attendee emails are on ("Invited and registered
    attendees will be notified by email. They'll be able to view
    highlights and play recordings on the event page." / "…play the
    recording…" / "Attendees won't be notified because email
    notifications are turned off for this event. …"), Preview email
    (leading, the Event recording available email) when emails are on,
    Cancel / Publish highlights.
  - Status bars (Fluent MessageBar): Generating (spinner), a generation
    error (warning: "Couldn't generate highlights." + "There was an error
    while creating your highlights." with Retry, or "Recording not
    available for highlights" + "Select a video with a transcript and try
    again." for TranscriptNotFound/TooShort/Empty), not published (info),
    "Publishing highlights..." + "This might take a minute. Feel free to
    leave this tab and we'll notify you when it's done." with Cancel
    publish (spinner), "Highlights published to event page." + "Expires
    {date}" + Extend for 60 days (success; "Extend expiration date?" →
    `PATCH …/recordings/{rid} {expirationDurationExtensionDays: 60}`),
    "Failed to publish recording" (error), "Recording expired" (warning),
    and after a failed publish "There was a problem publishing this file.
    Let's try again." / "This file can't be published because recording
    has been already published for this event.". Published replaces
    Included content and Publish by Remove highlights ("Remove highlights
    from event page?"); it and Cancel publish reset to a draft (`DELETE
    …/recordings/{rid}`, then the draft POSTed again).
  - Select from OneDrive (the picker's group and the empty state's
    button): Teams' OneDrive file picker (files, shared libraries, .mp4 and
    .mov, one file); the pick is treated as above.
- **Preview** on: "This is a preview of what attendees will see." instead of
  the tabs; the attendee's page (Add to calendar, no banner edit, no Manage
  apps).
- **Edit details** (and a card's Edit): the form with the event (`GET
  events/{id}`, `…/sessions`), "Save changes" → `PATCH events/{id}` {type,
  description, access {isRegistrationEnabled, isDiscoverable}, presenters
  (with sessionsProps' sessionId), attendees, meetingOptions}.
- **Duplicate**: the form with the event's details ("Save and continue") →
  `POST events/{id}/duplicate` with a new event's body.
- **Save as template** ("Save this event as a template?", 722 wide: "We'll
  save everything except the date and time for you to use again.", the
  promo, Name *, Description; Save template) → `POST events/{id}/
  saveAsTemplate` {…event, eventTemplateName}; toast "Template saved · View
  your templates".
- **Share** ("Help attendees discover this event", 24/32 bold) and, after
  publishing, "Success! Your event has been published": the attendee card
  (369 x 309) "Here's what attendees will see.", Show event in Events app
  ("Attendees with access can view" = `access.isDiscoverable`), Copy join
  details, Copy event page link. **Copy join details** copies the meeting's
  invitation HTML: the session's `meetingUpdateLink` (`api.scheduler.teams.
  microsoft.com/teams/{tid}/{oid}/{thread}/0`) → `views.html` (a data URL);
  toasts "Join details copied successfully", "Event page link copied
  successfully", "Join link copied successfully".

**Pin app** is Teams' pinned apps: your entitlements (`POST {mt}/beta/users/
apps/aggregatedEntitlements?appbarview=userpinned` → `isAppBarPinned`,
`appBarOrder`) and `POST {mt}/beta/users/apps/pinned {"appBarPinnedApps":
[{appId, appBarOrder}, …]}` with every pinned app (Events
a63f7012-8cc9-42d5-99c3-e35f526fab17 added last); toast "The Events app has
been pinned."; once pinned the header has no Pin app (the app bar's Unpin
takes it off).

**Meeting Recaps** (View audio recaps): header (28 px tile, "Meeting Recaps"
16 bold, Home / Audio recaps, Pin to app bar); Home (below), its meetings from
`GET {mcps}/user/meetings/contents?top=20&startDateTime=&endDateTime=&
includeTypes=Recording,TranscriptV2,MeetingChat,MeetingStage,Notes` per local
day; Audio recaps (`GET {mcps}/podcasts?top=10`) or "Get started on your first
audio recap" / Generate audio recap.

**Home** is Teams' Recap Home V2 (ECS MeetingRecap `enableRecapHomeV2`; bundle
meeting-recap-home, measured on winpc 2026-11-23 at 1280 x 680, TASK-0252):
- The page: a brand wash (color-mix(BrandBackground2 34%, NeutralBackground1)
  under two radial glows: 640 x 320 at 88% -4%, BrandForegroundInverted 30% →
  InvertedHover 12% at 44% → none at 62%; 420 x 200 at 74% 24%, Lilac
  Background2 12% → 6% at 46% → none at 66%; on a box at least 1373 wide). The
  greeting 32/40 semibold at 48, 36 down: "Good morning/afternoon/evening,
  {first name}" from 5, 12 and 17 o'clock, "Hello, {first name}" from 22 to 5
  (Teams' `tr`). The filter pills (33.3 tall, radius 16; the chosen one
  #E8EBFA, brand border, #4F52B2) 107 down; Search for meetings (280 x 32) and
  list / grid (36 x 32 each) 48 from the right. The list in a white card
  (radius 12, a 0.67 #E0E0E0 line) 156 down, 48 in, 12 from the bottom, that
  scrolls by itself (14 kept for the scroll bar).
- Groups as the Generate dialog (`Ye`, the same as `ka`): This week, Last week,
  else each older day ("Friday, November 6"); 44 tall headers (2 4 around, a
  13 px filled caret at 10, the label 14/600 at 31). "Loaded all meetings in
  the last 30 days." (12/16 #616161, 16 in) at the end.
- A row (84 + a subtle line; hovered #F5F5F5, radius 8; 12 in): with a Copilot
  licence a checkbox at 4 on hover (picks meetings for an audio recap: Home's
  audio recap bar, below); the preview at 44 (104 x 60, #E8EBFA, radius
  8, a 0.67 #E0E0E0 line): the recording's thumbnail (`So`/`Mn`: the
  recording the catch-up names, else the first; Graph c126x72) with the date
  tile 36 x 36 at 4.67 over it (#F5F5F5, radius 6, Fluent shadow 4, the day
  14/16 600 over the weekday 11/12, brand; tooltip "Friday, November 20");
  without a thumbnail a 16 px badge 4.67 from the bottom right: slide text for
  a meeting with only a transcript, a lock when you may open none of its
  recordings and transcripts (`ot.t`: NoPermission / Good / TranscriptOnly).
  From 160: the title (14/20 600 #424242), "Friday, November 20 · 8:23 PM -
  9:02 PM, OST Test 1" (12/16 #616161; Today / Yesterday), and the catch-up's
  speakers (`recommendationData.speakers` with an id and a name; 16 px
  avatars with a 2 px ring, three, else two and "+n" with a "View more
  people" popover) 4 below. From 60% of the row the chips (20 tall pills on
  #F5F5F5, 0 6 padding, a 16 px brand glyph and the count 12/20 #616161, 8
  apart): files (`meetingFiles`: the meeting's MeetingChat, MeetingStage and
  Notes resources with an id and an address, once each; none without
  permission), mentions and tasks (the counts are the catch-up's items, so a
  meeting whose day has no recommendation shows none), then a reason tag
  (Missed, Followed, Joined late, Left early). On the right, 12 in: Go to chat
  (32 x 31.3, shown on hover; `enableRecapHomeChatIcon`), 5 apart the
  headphones (24 x 24; with a transcript you may read) and Recap (50 x 24,
  outlined #D1D1D1, 12/16 600), 8 apart.
- What it opens: the title, the thumbnail and Recap open the recap window
  (Teams' own window "{subject} | Microsoft Teams", on AI summary). A chip
  opens its popover below it (28 right, 16 down; above when there's no room):
  tasks / mentions (321 wide: "3 tasks for people to follow up on" 12/20 600
  #616161, "AI-generated content may be incorrect" 12/16 on #FAFAFA, the
  items 12/20 ("Updated Project Plan: Send the updated project plan to the
  team. (OST Test 1)", the headline bold; a mention: who · when over the words
  with your name), lines between, "Are these tasks useful?" with Like and
  Dislike; an item opens the recap, a mention on Mentions); files ("Attached"
  14/20 600, each file 32 tall: its glyph, the name 12/20, ··· with Open in
  Browser and Copy link; a meeting note is "Agenda and notes"). Go to chat
  opens the meeting's chat; the headphones make an audio recap of the meeting
  with your saved style (Teams' `yo` → generateAndPopoutPodcast; a first-run
  dialog first when ECS Podcast `enableAudioRecapFreDialog` is on and it
  wasn't seen; unset for ost-test1). Teams draws the row's glyphs from the 20 px Fluent set at 16 (attach, mention, checkmark circle, slide text, lock).
- Filters and search are Teams' own (client side): Mentions has mentions of
  you, Missed a MISSED_MEETING reason, Followed a followed meeting; the search
  matches the subject, organizer, speakers, mentions, tasks and files.
- **Picking meetings for an audio recap** (TASK-0253; meeting-recap-home `ns`
  / `ts` / `jn`, the V2 bar `Yi` in `Ki`; measured on winpc 2026-11-23,
  ticking and unticking only): with Copilot (`recapEntitlement` COPILOT;
  without it neither the checkboxes nor the headphones show) each row has a
  32 x 32 Fluent square checkbox 4 in (the 16 px box at 8, radius 2, a 0.67
  #616161 line; ticked #5B5FC7, #4F52B2 hovered, a white 12 px check), its
  opacity 0 until the row is hovered or focused and 1 while ticked (120 ms
  ease). Only the checkbox ticks; a ticked row is #EBEBEB
  (NeutralBackground1Selected) hovered or not. The picks are the meetings by
  id in the order ticked (PodcastGenerateProvider, Home's own: going to Audio
  recaps and back clears them; they survive the filters and search). A
  meeting can't be ticked (aria-disabled, opacity 0.45, not-allowed cursor,
  a tooltip on hover or click) when it has only a recording or no transcript
  you may read ("Audio recap couldn't be generated for this meeting."), nor
  once ECS Calling `podcastMaxMeetingSelectionCount` (8) are picked ("Select
  up to eight meetings."); a ticked one can always be unticked. Screen
  readers hear "Select this meeting to include it with other meetings when
  generating an audio recap."
- With one or more picked the filters, search and list / grid give way to the
  bar (`audioRecapGenerationBar`, at the filters' place: 48 in, 100.3 down
  in a 48 slot, the page's width less 96, 48 tall, white, radius 8, a 0.67
  #D1D1D1 line, Fluent shadow 8, padding 8 12): Generate audio recap (a
  transparent button 31.3 tall, padding 5 12, the headphones 20 and the text
  14/20 600 #424242 6 apart; hovered brand with the filled headphones) and at
  the right "✕ 1/8 selected" (a circular outlined button 31.3 tall: white, a
  0.67 #D1D1D1 line, #F5F5F5 and #C7C7C7 hovered; dismiss 20, 14/600
  #242424), which clears the picks. Ask Copilot comes first only with ECS
  MeetingRecap `enableRecapHomeCopilot` (off for ost-test1). Generate is
  generateAndPopoutPodcast with every picked meeting's event and transcripts
  (range from the earliest start to the latest end, your saved host, format
  and language, origin RecapHome; the Podcast first-run dialog first when it
  is on), so Audio recaps shows the new recap being made; the V1 bar's "pick
  at least one meeting" warning can't happen here (the bar shows only with
  picks). Opened from a notification Home also picks the last day's missed,
  followed and mentioning meetings by itself (not in OST: it has no recap
  notification).
- A recap window opened from Home lists **Attendance** under Shared files as
  Teams does (its artifacts platform adds an AttendanceReport item when
  `meetingThreadProperties.hasAttendanceReport`; OST asks the meeting's
  attendance report history, which answers the organizer and co-organizers).
  Teams' Attendance there opens the meeting chat in a window of its own on
  Attendance (the chat header, then the report); OST opens the meeting chat on
  its Attendance tab in the main window.
- OST: api::recaps::row_from carries `actionItems`, `mentions`, `speakers`,
  `reasons`, `recapFile`, `recordings`, `thumb`, `access` and `files`
  (`meeting_files`); MeetingRecapsView's Home, `weekGroups` shared with the
  dialog; the recap window opens on Mentions or Notes when asked
  (Conversation.openRecapRef(ref, tab)).

## TASK-0212 leftovers (Teams desktop 26304 bundles and Teams on winpc, 2026-11-19)

**Email notifications** (People & emails): the rows are the event's templates
(`GET {regional}/events/{id}/emailtemplates` → `{emailTemplates: [{templateId,
templateType, sendTimeInterval, adO4867893_IsBodyEditableStatusCode}]}`) in Teams'
order: Registration confirmation, Registration pending, Registration cancellation,
Cancellation request, Registration after waitlist, Waitlist confirmation,
Registration rejected, Date and time update, Event cancellation, Event reminder (its
timing a brand link: "1 day before event", "{n} hours before event" … → Send event
reminder: 1-23 Hours or 1 Day, "before the event starts."), Event invite, Attendees
event invitation, Event recording available. Edit shows only with your events policy's
`allowEmailEditing` Enabled (on for ost-test1, seen on winpc); Preview always. The
"Send attendee emails" switch (aria "Turn off/on all attendee notifications") changes
only a draft: PATCH events/{id} `{communicationProperties: {…every prop,
disableAttendeeEmails}}`.
- **Edit email template** (600 wide; winpc: Sender's name * (disabled: needs
  registration and over 3,000 allowed attendees, or Premium), Sender's email
  (disabled), Email subject * (`{{eventName}}`), Cover image (the theme's banner),
  Logo ("No logo"), Email body * with the Formatting toolbar and Personalization (Event
  Name, Event Date Time, Event Description, Organization Name, Event Invite Card for an
  invite; tokens are read-only chips `itemtype=…VirtualEventsPersonalizationToken
  itemid=eventName|dateTime|eventDescription|eventOrganization`), Email footer
  (disabled, "This is set by your IT admin."); Preview, Cancel, Save): `GET
  …/emailtemplates/{templateId}` → `{subject, body, senderName, senderEmail, footer,
  sendTimeInterval}`; Save `PATCH …/emailtemplates/{templateId} {subject, body,
  senderName[, sendTimeInterval]}` (empty values left out); a failed save keeps the
  dialog open. Preview draws the email with sample values and "The design seen by your
  recipients may not look like this preview, …". BodyNotEditable / Indeterminate show
  Teams' domain banners and lock the body.

**Edit event banner** (Overview; organizers; 40 px round button 24 from the banner's top
right) opens **Branding** (722 wide, seen on winpc): "Choose a PNG or JPG file (max 5
MB). For best results, image ratio should be at least 796 x 265 pixels." (info: "The
images you upload will be hosted in a publicly available CDN."), Cover image (3:1,
Edit image / Upload image), Logo (90 x 90, Upload logo), Theme color (Default #5B5FC7,
Red #B82F41, Orange #FFA08F, Yellow #FFBA82, Green #9DE3CB, Teal #9EE5DE, Blue #257ACC,
Pink #D13B6D, Grey #F0F0F0; the chosen one underlined), Cancel / Save. Edit image: a
670 x 223 crop (logo 300 x 300) with Upload image, Zoom out / level / Zoom in, Back /
Save; the crop is re-encoded as JPEG. Save, in turn: `PATCH events/{id}/theme
{primaryColor}`, `PATCH events/{id}/theme/promo {imageId, image: data URL}`, `PATCH
events/{id}/theme/logo {imageId|"null", image}` (If-Match the event's eTag, the image
ones with x-skypetoken; the service hosts the image); toasts "Cover image successfully
updated.", "Logo successfully updated.", "Theme color successfully updated."; errors
"Choose a PNG or JPG file.", "Choose a file smaller than 5 MB. ", "Something went wrong.
Please try again.".

**Manage immersive collections** (Manage, after the sections; ECS
`enableImmersiveContentManagementInMeetApp` and the events policy's immersive events,
both on for ost-test1, seen on winpc): a card (Teams' archive picture, "Manage
immersive collections", "Use immersive collections to save and manage templates for
immersive events.", View immersive collections). The page (winpc): the retirement
warning ("Changes are coming to Immersive Events in Teams." …, Learn more →
aka.ms/ImmersiveUpdate, Dismiss), back, "Immersive collections (n)", Create
collection, the cards or "You don’t have any immersive collections" (folder-favorite
picture). Data: Graph `me/memberOf?$filter=resourceBehaviorOptions/any(i:i eq
'teams.immersive')…` (ConsistencyLevel eventual); the immersive worlds service
(`https://eur.worlds.mesh.cloud.microsoft`, token resource 3016d0ce-…):
`POST /v3.0/collections {DisplayName, Description?}` (a Microsoft 365 group; 403 →
"Your organization doesn't allow you to create Microsoft 365 groups…"), `GET
/v3.0/collections/{id}` (`{collection, privileges, status}`, asked every second until
Succeeded; "Your collection is being created! …" while Provisioning), PATCH, DELETE
("Delete this collection?"), owners and members from Graph `groups/{id}/owners|members`,
changed with `/owners {userId}`, `/owners/remove`, `/members {userIds}`,
`/members/remove {userId}` (Add people to this collection, Remove person from this
collection?). The details page: Templates ("Immersive templates (0)", the
design-from-scatch picture), Members (Owners (n) with Add people, Members (n); Name
and email, Title, Role), Settings (Collection details with Edit details, Manage ▸
Delete collection).

**Manage apps** (seen on winpc): a webinar's card says "Manage or add apps for your
session here."; "here" opens the session meeting's details page
(entityCommanding.calendar.meetingDetails, its default tab; OST: Calendar's meeting
details). A town hall's card (measured 2026-11-21 on an "OST TEST 212 town hall apps"
draft, TASK-0212) lists the apps Teams allows in a town hall's own thread: ECS
`extensibility.baseTownhallAppEntityAllowlist` (the worker's filter `isTownHall →
base allowlist`, `isStreamingThread → streamingTownhallAppEntityAllowlist`; the
26304 defaults hold only AI Producer e7fb100c…, the live ECS adds Custom Streaming
a59fe11a…), each named and pictured from batchedDefinitions; Teams listed Custom
Streaming above AI Producer. Card 350 wide, #F5F5F5, radius 16, padding 20; "Manage
apps" 16/22 semibold; rows 48 apart: icon 32 (radius 2), name 14/20 at 65, Add 80 x
28 (12/16, radius 4, white, 1 px #D1D1D1) at the right edge; with an app added its row
shows "Added" (14, #424242) and a 28 x 28 Uninstall button (trash 20), and the Add
buttons move into that column. Add: `POST {mt}/beta/chats/{event thread}/apps/
entitlements` (the definition), then Teams' tab configuration dialog (app icon and
name, About, the app's configuration page — Custom Streaming's is Teams' own
`teams.microsoft.com/extensibility-apps/meetingstream/rtmp/config?host=teams`, code
`teams-modular-packages/hashed-assets/meeting-stream-rtmp-*.js` loaded at runtime —
and Save, no Back and no post to the chat), saved as the chat's tab property
(`tab::<id>` extension-tab, entityId streaming-controls). Uninstall asks "Uninstall
{app} from this event?" / "This removes the app for everyone in the event. You can add
it again later." (Cancel, Uninstall), then sets the tab property to null and `DELETE
{mt}/beta/chats/{thread}/apps/entitlements/{app}`. "Added" follows the chat's
`GET {mt}/beta/chats/{thread}/apps/chatentitlements`. OST: the same card
(`api::events::townhall_apps`, `townhall_app_install`, `townhall_app_remove`;
harness `--events-test=thapps:<title>`).

**Room options**: Presenting sends the room in `presenters` (with sessionsProps),
Attendee viewing in `attendees` (userType Room, no sessionsProps) — Teams' code
(locationsWithMeetingRole Everyone / Attendees); a draft Teams made on winpc with
Attendee viewing was read back from the service with the room among its attendees
(see the notes). With registration on only Presenting is offered.

**Meeting Recaps ▸ Audio recaps**: the empty state's picture is
`evergreen-assets/podcast/no-podcast.png` (128, seen on winpc), the title 18 bold, the
text, Generate audio recap → the **Generate audio recap** dialog (the window less 32 px
each side): Style (Executive "Two speakers. Essential info with minimal commentary.",
Newscast "One speaker. Fast and concise.", Casual "Two speakers. Extra color and
commentary. Longest format."), Language (English (US)), "Select up to 8 meetings"
(info "Select up to eight meetings."), All / Missed / Mentions / Followed, Search for
meetings, your meetings with a transcript from the last 30 days, else
`illustrations/png/128/calendar-three-people-l-standard-128x128.png` and "No meetings
were transcribed"; Generate (off until a meeting is picked). Teams' Generate is an
AugLoop operation (teams_recap_podcast_generation) with the meetings' transcripts.

The dialog's meetings (winpc 2026-11-22): grouped in an accordion ("This week", "Last
week", else each older day on its own, "Friday, November 6", with the year when not this
year's: Teams' `ka`, checked live in TASK-0247; 44 tall headers, a 13 px filled caret, 14/600);
rows 72.7 tall: a checkbox, the title 14/600 over "Today · 1:00 PM - 1:30 PM ,
{organizer}" (12 #616161; Today / Yesterday / "Friday, November 20"); from the row's
middle the chips (24 tall on #F5F5F5, a 16 px brand glyph and the count 12/600; tooltip
"3 tasks for people to follow up on") from Teams' meeting catch-up recommendations
(`POST substrate.office.com/search/api/v1/recommendations?setflight=AiTasksV2,
AiNotesV2,AllowResultsWithoutMeeting,PeopleMentionsV2`, EntityType and scenario
MeetingCatchUp: `PointsOfInterest.ActionItems` / `MentionEvents`); the recording's
thumbnail 84 x 48 at the right (Graph `drives/{d}/items/{i}/thumbnails/0/c126x72/content`);
a picked row #F5F5F5; "✕ n/8 selected" (a pill) left of the search box.

**How the list is made** (Teams 26304 bundles, TASK-0250): Home and the dialog share
useMeetingRecapList → the worker's meetingRecapList resolver → getMeetingRecapByDay, one
local day per page (today first, then fetchMore a day at a time back to 30 days). Each day
(00:00:00.000 to 23:59:59.999 local, as UTC) asks the day's artifacts
(`user/meetings/contents`, top 20) and, with a Copilot licence, the catch-up
recommendations for the same range (no Top). The recommendations become threads (`qb`:
MeetingId as eventId, MeetingRecording.ICalUid / TeamsThreadId, a TranscriptV2 resource
when the Description names the transcript's GUID, recommendationData with the counts) and
are merged by lower-cased iCalUid (`Um`): one recommendation per meeting (`Lm`: the one
whose DriveId:DriveItemId is the meeting's recording, else one with a file), its
recommendationData put on the artifacts' thread, or the recommendation kept as its own
thread; artifacts without an iCalUid drop out. The resolver lists a thread when it has an
eventId and recommendationData or a Recording / TranscriptV2 resource; the node's id is
the eventId. A meeting across midnight is in both days' artifacts (the calendar times
overlap both), but its recommendation comes on one day only: the range is matched on when
it was recorded ("OST TEST 248 agenda", recorded from 11:33 PM: its first day; "OST TEST
250 midnight", 11:45 PM - 12:15 AM recorded at 3:20 AM: its second day only). The hook
keeps one node per id (`W`, `ye`: the day asked later, the older one, over the newer;
transcripts and recordings only when it has some), sorted by start, newest first, so it is
listed once, under the day it starts. Every day's cache refresh is also pushed to the list
(artifactsByUserUpdateEvent, the latest per id wins), so the counts end up those of the day
that has them: on winpc (2026-11-23) "OST TEST 250 midnight" showed no chip on the
dialog's first render and "14" once the refreshes were in (dialog and Home). OST does the
same, keeping the counts of the day that has a recommendation (api::recaps::meetings /
day_rows, MeetingRecapsView.meetingList; 8 days at a time as Teams' range fetch).

**A finished audio recap** (winpc, "OST TEST 212 recap long", 5 min 38 s): the list row
shows the title and its length ("5m 38s", or "4m 3s left" once started). The detail:
title 16/600, Listen on mobile, a New badge, ··· (Learn more: a 676 wide dialog with three
paragraphs; Delete: "Delete audio recap?" "Are you sure you want to delete this audio
recap? The audio recap will also be deleted on your OneDrive."); the day 12; AI generated
with Like / Dislike; a line; Chapters / Transcript. Chapters are grouped by meeting
(`chapters[].meetings[0]`): the first and last chapters without one stand alone ("Intro",
"Outro", 18/600, their start at the right), a meeting's group opens with its name
(18/600), "Today · 1:00 PM - 1:30 PM, {organizer}" (12) and Recap, then its chapters (31.3
rows: a 12 px brand play glyph, the title 14, the one playing 600 brand, "mm:ss" at the
right); a chapter's start is the sum of the earlier durations. Transcript: the recap's
caption file (WebVTT, fetched with the file's site token); voices are "Speaker 1",
"Speaker 2" in order of first speech; "Speaker n · mm:ss" (12 #707070) where the speaker
changes, 12 above it, each line 14/20. The player: the chapter's title 14/600, a 6 px bar
in chapter segments, "01:41 / 05:38", then speed, back 10, Play (40), forward 10 and Play
in new window. Generating in Teams auto-plays the new recap.

**Playing a recap while it's made** (Teams 26304, TASK-0248: 75874 `kt`, 599106's state
`_x`/684945, services-podcast's PodcastPlaybackManager): Generate's AugLoop annotation
updates the recap as it's made (its id, then its chapters with their status NotStarted /
InProgress / Completed / Failed and each chapter's own `audioFile`, an HLS playlist
`…/streams/…m3u8` of the recap's file). The recap's state is HAS_CHAPTERS as soon as a
chapter is InProgress or Completed (before GENERATION_IN_PROGRESS), so the detail shows its
chapters and the recap seen generating starts playing then (`setPodcastStatus({isPlaying:
true, currentTime: 0})`), not when it completes. Teams plays every recap a chapter at a time
(hls.js over the chapter's playlist, start 0, each request with the site's token): at a
chapter's end the next one that hasn't failed; one without audio yet is waited for, as is a
chapter whose audio ran out before it was Completed, and, while the recap is still made, the
next chapter to appear. OST does the same for a recap being made (Generate's progress
updates to the view; `recapChapterAudio` serves the chapter's playlist and segments through
`live_stream::StreamProxy::site` with the site's token); a made recap plays from its
`fullAudioFile`. A recap being made already names its `fullAudioFile` (not written yet), so
OST plays by chapter until it's made. A chapter's playlist (`…/streams/
dcontent_teamspodcast.<n>.m3u8/content`) lists MPEG-TS segments named `…/streams/
dcontent_teamspodcast.<n>.0000/content`; it grows while the chapter is made and ends with
`#EXT-X-ENDLIST`. The proxy serves the segments as `.ts` (their first bytes; FFmpeg's HLS
only opens segments with media extensions) and, the first time, a growing playlist with only
its first segment, so FFmpeg starts from the start (as hls.js' `startPosition: 0`) rather than
three segments from the live end. Measured on winpc 2026-11-23 (Generate of "OST TEST
248 agenda", AugLoop frames and the player's button read over CDP): the first chapter came
InProgress with its audio at 00:34:47 and the player showed Pause at 00:34:48; the Intro ran
out at about 00:35:00 (Play, waiting) and the next chapter's audio came at 00:35:03 (Pause
again); the whole recap was made in about 1 min 45 s and went on playing (03:41 / 06:03
later). (A first Generate a few minutes earlier didn't start by itself at all; not
explained.) Chapter statuses also include EmptyContent and TopicParsed (not yet made).

**Attendees** card: the picture is `illustrations/v2/people-l-standard.svg` (dark
`people-d-standard.svg`) at 128, under "When attendees RSVP or register, they'll show up
here." (winpc). Manage's empty Drafts says "Events you haven’t published yet will show
up here." (winpc).

## OST status (live checks 2026-11-16, ost-test1 on linuxlt, `--events-test`)
- Discover and Manage loaded from the service (both empty for this
  tenant, as in Teams); Create event and the form drawn; a draft saved
  (POST events, 201, state Draft, a default promo picture shown), its page
  shown with "Draft event created", then cancelled (DELETE, 204) and its
  "Canceled:" calendar entry removed.
- [x] Events from View more apps opens natively: header, Discover (intro
  card, lists or empty state, templates), Manage (sections with totals
  and cards, or the empty state), Filters (My events, Today / This week /
  This month), Pin app (keeps Events on OST's app bar), Create event's
  page, the New event form (name, dates and times, Online, description,
  access, registration, capacity and large audience, participation tiles,
  green room), the save dialog, the draft's page and Cancel.
- [x] TASK-0212 (OST Test 3 on linuxlt, 2026-11-18/19, `--events-test=full`,
  `--recaps-test`): Discover's My events and Custom range (the regional
  query with Registered/Invited, chips, "No events match your filters"),
  See more, Connect apps, Create's saved templates (Schedule, Edit
  template, Delete), the form's time zone, room search with availability
  and Room options, the description toolbar (sent as `<strong>`),
  co-organizer / presenter / invitee pickers (Teams' searchV2 flags), the
  stage preview, All options (the event template's options) and Manage
  apps; the save dialog's invite cards; the event page's Edit details,
  Share, ··· (Duplicate, Save as template, Cancel), Preview and its four
  tabs; Publish's success dialog with the attendee card, Show event in
  Events app and Copy join details (the scheduler's invitation HTML); Pin
  app in Teams' pinned apps (and the app bar's Pin / Unpin); Meeting
  Recaps for View audio recaps. A draft (OST Test 2 co-organizer, OST Test
  1 presenter, OST Test Room), a template, a duplicate (edited and
  published) were made and all cancelled / deleted again.
- [ ] Left: Manage immersive collections; the email templates' Edit
  (Preview shows the service's template); the promo banner's Edit event
  banner; Highlights with a real recording. Room options' Attendee viewing
  sends the room with the attendees (Teams' meeting role Attendees, read
  from its code; not captured on the wire).
- [x] TASK-0212 leftovers (2026-11-19, linuxlt): My events with real data (OST Test 3
  invited to "OST TEST 212 invite", listed with Live and Join); Email notifications'
  rows, Edit (PATCH saved, tokens kept) and Preview; Branding (Teal and a cover image:
  theme and theme/promo PATCHes, the new banner shown); immersive collections
  (create, provisioning, add a member, delete, as OST Test 3); Generate audio recap's
  dialog (empty, as Teams with no transcribed meetings); Manage apps → the meeting's
  details; a Teams-made draft with Room options' Attendee viewing read back with the
  room among its attendees; Discover's lists drawn again (they never were).
- [ ] Left: Highlights with a recording (needs a recorded, transcribed event), a town
  hall's Manage apps list (newer than the 26304 bundles), Generate audio recap's
  AugLoop submission (no transcribed meeting to test with), the logo crop's live save.
- [x] Since TASK-0184 (docs/spec/town-halls-and-webinars.md): the Town hall
  template's form, Publish event with Teams' two dialogs, Upcoming, Join
  and its menu, and the event chat button.
- [x] TASK-0212 round meetK (2026-11-22, a 12-minute recorded and transcribed event "OST TEST 212
  recap long", ost-test1 and OST Test 3 on linuxlt with a synthetic two-voice dialogue):
  OST generated the event's highlights itself (createHighlights 201, AugLoop steps
  FetchGroundingData, GenerateHighlights, WriteToLoop), saved the session's draft, published
  with the Loop page's serialized content ("Highlights published to event page. Expires …"),
  removed them again (back to a draft); Select from OneDrive picked a video from Home (its
  ids looked up first) as the draft; Generate audio recap made a recap from the meeting;
  Teams' finished recap shown with its chapters, transcript and playback.
- [x] TASK-0247 (2026-11-22): Generate audio recap's meetings. Teams 26304 lists them from
  its meeting recap list (`meetingRecapList` → `getMeetingRecapByDay`, a day at a time for
  30 days): the meeting artifacts of the day (`user/meetings/contents`, named by
  `threadInfo.subject`) raced against the Copilot catch-up recommendations of the day; the
  first answer is shown, both are then merged (the artifacts keep their subject, the
  recommendations add their counts) and cached per day, and the cache is shown first on the
  next visit while it refreshes. A recommendation without a calendar event (`MeetingId`
  empty, all of them in this tenant but "OST TEST 240 recap meeting") isn't listed. The AugLoop
  `teams_recap_podcast_event_list` (`meetingList(timerange)`) is not used by any 26304 UI
  bundle. The name difference seen in TASK-0212 was Teams' day cache: "OST TEST 212 recap
  long" from before its calendar item was renamed and cancelled ("Canceled: Recording of OST
  TEST 212 recap long is now available", no resources left) — after a refresh Teams dropped
  it from Home too. OST lists the same artifacts, by the same subject, and ends both Home and
  the dialog with Teams' "Loaded all meetings in the last 30 days." (12/16 #616161; 16 8 0 16
  on Home, 16 8 16 16 in the dialog) once today and the 30 days before it are read.
- [x] TASK-0247: a recap's header has Teams' Listen on mobile (podcast QR button: a phone
  glyph 20 px in a 37.3 x 31.3 transparent button, its label 14/600 only when the app area is
  at least 1280 wide; for a recap with an id, being made or made) and the New badge (36.7 x 20,
  round, brand, 12/600 white; ECS `showListenOnPhoneNewBadge` (on) for
  `listenOnPhoneBadgeExpirationDays` (14) days from the first time a recap header was shown,
  Teams' `listenOnPhoneNewBadgeStartDateTime`). Listen on mobile opens a 600 wide dialog
  (padding 24, radius 8): "Listen on mobile" 20/28 semibold with Close, 8 below "Scan the
  following code…" 14/20, 20 below a 130 px picture (white, 0.67 #D1D1D1 edge, radius 20, 10
  in) of qrcode-svg's 200 px code (error correction L, 4 modules of quiet zone; version 5, 45
  modules, for a recap id like "01BV7C2B…") of `https://teams.microsoft.com/l/meetingpodcast?
  id={podcastId}&origin=desktopQRCode` (measured on winpc 2026-11-22 for "OST TEST 247 agenda"). A recap made with Generate plays by itself from the start once it's made
  (Teams' autoPlay: the recap seen generating plays when its chapters come, unless another
  recap was picked meanwhile).
