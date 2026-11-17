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
- Discover: `GET https://teams.microsoft.com/api/virtualevents/prod/beta/eventOverviews`
  (ECS `virtualEventsServiceEndpoint`, `x-api-version: 2.0`; GraphQL
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
- [ ] Not built: View audio recaps, Connect apps, Custom range, See more,
  the event card's ··· items, the event page's tabs other than Overview,
  Edit details, Share, Preview, Duplicate, Save as
  template; the form's people pickers (co-organizers, presenters,
  invitees), room locations, the description's formatting toolbar, the
  time zone picker, the stage preview, All options and Manage apps;
  Manage immersive collections. Pin app is kept on this device (Teams'
  pinned-apps setting isn't traced).
- [x] Since TASK-0184 (docs/spec/town-halls-and-webinars.md): the Town hall
  template's form, Publish event with Teams' two dialogs, Upcoming, Join
  and its menu, and the event chat button.
